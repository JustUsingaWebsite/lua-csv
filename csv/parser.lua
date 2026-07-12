-- csv/parser.lua
-- Streaming CSV parser and reader object implementation.
--
-- Luau/Lune rewrite:
--   - Uses Lune's fs module for file reading (replaces io.open)
--   - Uses Luau string interpolation for error messages
--   - Lune file reads use fs.readFile, then parse the in-memory string
--   - The parser hot path scans byte positions directly instead of using
--     repeated Lua patterns and buffer-to-string conversions

require("./types")
local column_map = require("./column_map")
local util = require("./util")
local unicode = require("./unicode")
local separator = require("./separator")

-- Lune provides its own fs module, but we also fall back to io for
-- compatibility with standard Lua if running outside Lune.
local fs = nil
local has_lune_fs = false

do
    local ok, lune_fs = pcall(function()
        return require("@lune/fs")
    end)

    if ok then
        fs = lune_fs
        has_lune_fs = true
    end
end


-- Localized library functions: calling string.byte(s, i) directly is faster
-- than s:byte(i) in Luau, since method syntax goes through metatable
-- resolution while a direct/localized call can hit the builtin fastcall path.
-- This module's hot loop calls byte() once per character of the input, so
-- this matters a lot here.
local byte, sub, find, gsub = string.byte, string.sub, string.find, string.gsub

-- Luau's table.clear/table.clone are native (C-implemented) and avoid the
-- Lua-level pairs() loop the hand-rolled versions used.
local clear_table = table.clear
local copy_table = table.clone

local function make_numeric_select(select)
    if not select then
        return nil
    end

    local indexes = {}

    for _, index in ipairs(select) do
        if type(index) == "number" then
            indexes[index] = true
        end
    end

    if next(indexes) then
        return indexes
    end

    return nil
end

---Parse separated values from a string and yield rows.
---@param data string
---@param parameters CsvParameters
local function separated_values_iterator(data, parameters)
    if type(data) ~= "string" then
        error("csv parser expects string input in Lune mode", 0)
    end

    local raw_separator =
        parameters.separator or
        separator.guess(data, separated_values_iterator)

    raw_separator = raw_separator or ","

    if #raw_separator ~= 1 then
        error("separator must be a single character", 0)
    end

    local len = #data
    local sep_byte = byte(raw_separator, 1)
    local pos = 1
    local line_start = 1
    local line = 1
    local field_count = 0
    local fields = parameters.reuse_record and {} or nil
    local starts = parameters.positions and parameters.reuse_record and {} or nil
    local nonblanks = false
    local header, header_read
    local field_start_line, field_start_column
    local record_count = 0
    local expected_field_count
    local last_field_count
    local selected_indexes = parameters.header and nil or make_numeric_select(parameters.select)
    local selected_keys

    local function problem(message)
        -- Luau string interpolation: cleaner than string.format
        error(
            tostring(parameters.filename or "<unknown>") ..
            ":" ..
            tostring(field_start_line or line) .. ":" .. tostring(field_start_column or 1) .. ": " .. tostring(message),
            0
        )
    end

    -- Once we've seen a full row, expected_field_count (in strict mode) or
    -- the header's length tells us how many array slots each row needs.
    -- Pre-sizing with table.create avoids repeated array-part growth as
    -- fields are added one by one. This only helps the array-shaped case
    -- (no header/column_map, where keys are 1..N) - with a header or
    -- column map, fields is dictionary-shaped and table.create can't help.
    local function row_size_hint()
        if parameters.header or parameters.column_map then
            return nil
        end

        return expected_field_count or last_field_count or (header and #header) or nil
    end

    local function new_row_table()
        if parameters.reuse_record then
            clear_table(fields)

            if parameters.positions then
                clear_table(starts)
            end
        else
            local hint = row_size_hint()
            fields = hint and table.create(hint) or {}
            starts = parameters.positions and {} or nil
        end
    end

    local function build_header_select()
        if not parameters.select then
            return
        end

        selected_indexes = {}
        selected_keys = {}

        local wanted = {}

        for _, name in ipairs(parameters.select) do
            if type(name) == "string" then
                wanted[util.normalise_string(name)] = true
            elseif type(name) == "number" then
                selected_indexes[name] = true
                selected_keys[name] = header[name]
            end
        end

        for index, name in ipairs(header) do
            if wanted[util.normalise_string(name)] then
                selected_indexes[index] = true
                selected_keys[index] = name
            end
        end
    end

    local function should_keep_field(index)
        if not header_read and (parameters.header or parameters.column_map) then
            return true
        end

        if parameters.column_map and header_read then
            return parameters.column_map.index_map[index] ~= nil
        end

        if selected_indexes then
            return selected_indexes[index] == true
        end

        return true
    end

    local function should_keep_record()
        return
            parameters.skip_blank_lines == false or
            nonblanks or
            field_count > 1
    end

    local function validate_field_count()
        if parameters.strict then
            if not expected_field_count then
                expected_field_count = field_count
            elseif field_count ~= expected_field_count then
                problem(
                    "wrong number of fields: expected " .. expected_field_count .. ", got " .. field_count
                )
            end
        end
    end

    local function normalize_newlines(value)
        if find(value, "\r", 1, true) then
            return gsub(gsub(value, "\r\n", "\n"), "\r", "\n")
        end

        return value
    end

    local function line_column_at(index)
        return line, index - line_start + 1
    end

    local function count_raw_newlines(start_index, end_index)
        local scan = start_index

        while scan <= end_index do
            local b = byte(data, scan)

            if b == 13 then
                if scan < end_index and byte(data, scan + 1) == 10 then
                    scan = scan + 1
                end

                line = line + 1
                line_start = scan + 1
            elseif b == 10 then
                line = line + 1
                line_start = scan + 1
            end

            scan = scan + 1
        end
    end

    local function add_position(key, keep)
        if parameters.positions and keep and key then
            starts[key] = {
                line = field_start_line,
                column = field_start_column,
            }
        end
    end

    local function add_field(value)
        if value ~= "" then
            nonblanks = true
        end

        field_count = field_count + 1
        local keep = should_keep_field(field_count)
        local key

        if not keep then
            return
        end

        value = normalize_newlines(value)

        if parameters.empty_as_nil and value == "" then
            value = nil
        end


        if parameters.column_map and header_read then
            local ok

            ok, value, key = pcall(
                parameters.column_map.transform,
                parameters.column_map,
                value,
                field_count
            )

            if not ok then
                problem(value)
            end
        elseif header then
            key = selected_keys and selected_keys[field_count] or header[field_count]
        else
            key = field_count
        end

        if key then
            fields[key] = value
            add_position(key, keep)
        end
    end

    local function finish_record()
        if parameters.column_map and not header_read then
            header_read = parameters.column_map:read_header(fields)

            if header_read and parameters.strict then
                expected_field_count = field_count
            end
        elseif parameters.header and not header_read then
            if should_keep_record() then
                if parameters.duplicate_headers == "error" then
                    local seen = {}

                    for _, name in ipairs(fields) do
                        if seen[name] then
                            problem("duplicate header: " .. tostring(name))
                        end

                        seen[name] = true
                    end
                end

                if parameters.reuse_record then
                    header = copy_table(fields)
                else
                    header = fields
                end

                header_read = true
                build_header_select()

                if parameters.strict then
                    expected_field_count = field_count
                end
            end
        else
            if should_keep_record() then
                validate_field_count()
                coroutine.yield(fields, starts)

                record_count = record_count + 1

                if parameters.record_limit and record_count >= parameters.record_limit then
                    return true
                end
            end
        end

        return false
    end

    local bom_skip = unicode.find_bom(function(a, b)
        return sub(data, a, b)
    end)

    pos = bom_skip + 1
    line_start = pos

    new_row_table()

    while pos <= len + 1 do
        field_start_line, field_start_column = line_column_at(pos)

        local value
        local sep_pos
        local sep_value

        if pos <= len and byte(data, pos) == 34 then
            local start = pos + 1
            local scan = start
            local parts
            local quote_end

            while true do
                local quote = find(data, '"', scan, true)

                if not quote then
                    problem("unmatched quote")
                end

                if quote < len and byte(data, quote + 1) == 34 then
                    if not parts then
                        parts = {}
                    end

                    parts[#parts + 1] = sub(data, scan, quote)
                    scan = quote + 2
                else
                    if parts then
                        parts[#parts + 1] = sub(data, scan, quote - 1)
                        value = table.concat(parts)
                    else
                        value = sub(data, start, quote - 1)
                    end

                    quote_end = quote - 1
                    scan = quote + 1
                    break
                end
            end

            count_raw_newlines(start, quote_end)

            while scan <= len and byte(data, scan) == 32 do
                scan = scan + 1
            end

            if scan <= len then
                local b = byte(data, scan)

                if b ~= sep_byte and b ~= 10 and b ~= 13 then
                    problem("unexpected character after closing quote")
                end

                sep_pos = scan
                sep_value = b
            end
        else
            local start = pos
            local scan = pos

            while scan <= len do
                local b = byte(data, scan)

                if b == sep_byte or b == 10 or b == 13 then
                    break
                end

                scan = scan + 1
            end

            value = sub(data, start, scan - 1)

            if parameters.trim_fields ~= false then
                value = util.trim_space(value)
            end

            if scan <= len then
                sep_pos = scan
                sep_value = byte(data, scan)
            end
        end

        add_field(value)

        if not sep_value or sep_value == 10 or sep_value == 13 then
            local stop = finish_record()

            if stop then
                break
            end

            if not sep_value then
                break
            end

            local next_pos = sep_pos + 1

            if sep_value == 13 and next_pos <= len and byte(data, next_pos) == 10 then
                next_pos = next_pos + 1
            end

            line = line + 1
            line_start = next_pos
            pos = next_pos
            last_field_count = field_count
            field_count, nonblanks = 0, false
            new_row_table()
        else
            pos = sep_pos + 1
        end
    end
end

local buffer_mt = {
    lines = function(t)
        return coroutine.wrap(function()
            separated_values_iterator(t.buffer, t.parameters)
        end)
    end,

    read = function(t)
        if not t._iterator then
            t._iterator = t:lines()
        end

        return t._iterator()
    end,

    readall = function(t)
        local rows = {}

        while true do
            local row = t:read()

            if not row then
                break
            end

            if t.parameters.reuse_record then
                row = copy_table(row)
            end

            rows[#rows + 1] = row
        end

        return rows
    end,

    close = function(t)
        if t.buffer.close then
            t.buffer:close()
        end
    end,

    name = function(t)
        return t.parameters.filename
    end,
}

buffer_mt.__index = buffer_mt

local parser = {}

---Use an existing string/file/buffer as CSV input.
---@param buffer any
---@param parameters CsvParameters?
---@return CsvFile
function parser.use(buf, parameters)
    parameters = parameters or {}
    parameters.filename = parameters.filename or "<unknown>"
    parameters.column_map = parameters.columns and column_map.new(parameters.columns)

    if not buf then
        -- stdin: in Lune, read from process.stdin; in Lua, use io.stdin
        if has_lune_fs then
            local stdio = require("@lune/stdio")
            buf = stdio.readToEnd()
        else
            buf = io.stdin:read("*a") or ""
        end
    elseif type(buf) == "userdata" or (io and io.type and io.type(buf) == "file") then
        buf = buf:read("*a") or ""
    end

    local f = setmetatable({
        buffer = buf,
        parameters = parameters,
    }, buffer_mt)

    ---@cast f CsvFile
    return f
end

---Open a CSV file from disk.
---Uses Lune's fs.readFile when available, falls back to io.open for pure Lua.
---@param filename string
---@param parameters CsvParameters?
---@return CsvFile?, string?
function parser.open(filename, parameters)
    parameters = parameters or {}
    parameters.filename = filename

    local requested_encoding = parameters.encoding or "auto"

    if has_lune_fs then
        -- Lune path: read file with fs.readFile
        local ok, contents = pcall(function()
            return fs.readFile(filename)
        end)

        if not ok then
            return nil, tostring(contents)
        end

        -- UTF-16 files are decoded into UTF-8 before parsing.
        if requested_encoding ~= "utf-8" then
            local sample = contents:sub(1, 4)
            local detected = unicode.detect_encoding(sample, requested_encoding)

            if detected == "utf-16le" then
                local decoded = unicode.decode_utf16(contents, "utf-16le")
                return parser.use(decoded, parameters), nil
            elseif detected == "utf-16be" then
                local decoded = unicode.decode_utf16(contents, "utf-16be")
                return parser.use(decoded, parameters), nil
            end
        end

        -- UTF-8 or ASCII: use the string directly with openstring
        -- for streaming behavior through the buffer
        parameters.buffer_size = parameters.buffer_size or #contents

        return parser.use(contents, parameters), nil
    else
        -- Fallback Lua path: use io.open for streaming
        local file, message = io.open(filename, "rb")

        if not file then
            return nil, message
        end

        if requested_encoding ~= "utf-8" then
            local sample = file:read(4) or ""

            file:seek("set", 0)

            local detected = unicode.detect_encoding(sample, requested_encoding)

            if detected == "utf-16le" then
                local contents = file:read("*a") or ""
                file:close()

                local decoded = unicode.decode_utf16(contents, "utf-16le")

                return parser.use(decoded, parameters), nil
            elseif detected == "utf-16be" then
                local contents = file:read("*a") or ""
                file:close()

                local decoded = unicode.decode_utf16(contents, "utf-16be")

                return parser.use(decoded, parameters), nil
            end
        end

        return parser.use(file, parameters), nil
    end
end

local function makename(s)
    local t = {}

    t[#t + 1] = "<(String) "
    t[#t + 1] = (s:gmatch("[^\n]+")() or ""):sub(1, 15)

    if #t[#t] > 14 then
        t[#t + 1] = "..."
    end

    t[#t + 1] = " >"

    return table.concat(t)
end

---Open CSV data from a string.
---@param filecontents string
---@param parameters CsvParameters?
---@return CsvFile
function parser.openstring(filecontents, parameters)
    parameters = parameters or {}

    parameters.filename =
        parameters.filename or makename(filecontents)

    local requested_encoding = parameters.encoding or "auto"

    if requested_encoding ~= "utf-8" then
        local decoded = unicode.decode_if_needed(filecontents, requested_encoding)
        filecontents = decoded
    end

    parameters.buffer_size =
        parameters.buffer_size or #filecontents

    return parser.use(filecontents, parameters)
end

---Decode CSV text into rows.
---@param s string
---@param parameters CsvParameters?
---@return table[]
function parser.decode(s, parameters)
    local f = parser.openstring(s, parameters)
    return f:readall()
end

return parser
