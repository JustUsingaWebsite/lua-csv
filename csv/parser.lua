-- csv/parser.lua
-- Streaming CSV parser and reader object implementation.

require("csv.types")
local file_buffer = require("csv.buffer")
local column_map = require("csv.column_map")
local util = require("csv.util")
local unicode = require("csv.unicode")
local separator = require("csv.separator")


---Parse separated values from a string/file buffer and yield rows.
---@param buffer any
---@param parameters CsvParameters
local function separated_values_iterator(buffer, parameters)
    local field_start = 1
    local advance

    if buffer.truncate then
        advance = function(n)
            field_start = field_start + n
            buffer:truncate(field_start)
        end
    else
        advance = function(n)
            field_start = field_start + n
        end
    end

    -- Return text relative to current field_start.
    local function field_sub(a, b)
        b = b == -1 and b or b + field_start - 1
        return buffer:sub(a + field_start - 1, b)
    end

    -- Find a pattern relative to current field_start.
    local function field_find(pattern, init)
        init = init or 1

        local f, l, c = buffer:find(pattern, init + field_start - 1)

        if not f then
            return
        end

        return f - field_start + 1,
            l - field_start + 1,
            c
    end

    local bom_skip = unicode.find_bom(field_sub)
    advance(bom_skip)

    local raw_separator =
        parameters.separator or
        separator.guess(buffer, separated_values_iterator)

    raw_separator = raw_separator or ","

    if #raw_separator ~= 1 then
        error("separator must be a single character", 0)
    end

    local sep =
        "([" ..
        util.escape_pattern_class_char(raw_separator) ..
        "\n\r])"

    local line_start = 1
    local line = 1
    local field_count, fields, starts, nonblanks = 0, {}, {}, false
    local header, header_read
    local field_start_line, field_start_column
    local record_count = 0
    local expected_field_count

    local function problem(message)
        error(
            ("%s:%d:%d: %s"):format(
                parameters.filename or "<unknown>",
                field_start_line or line,
                field_start_column or 1,
                message
            ),
            0
        )
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
                    ("wrong number of fields: expected %d, got %d")
                    :format(expected_field_count, field_count)
                )
            end
        end
    end

    while true do
        local field_end, sep_end, this_sep
        local tidy

        field_start_line = line
        field_start_column = field_start - line_start + 1

        if field_sub(1, 1) == '"' then
            advance(1)

            ---@type number?
            local current_pos = 0

            while true do
                -- Find next quote. If followed by another quote, it is an
                -- escaped quote (""). Otherwise it closes the quoted field.
                local _, b, c = field_find('"("?)', current_pos + 1)

                if not b then
                    problem("unmatched quote")
                end

                current_pos = b

                if c ~= '"' then
                    break
                end
            end

            tidy = util.fix_quotes

            -- After a quoted field closes, only spaces then a separator/newline
            -- are valid. Anything else is malformed CSV.
            field_end, sep_end, this_sep =
                field_find(" *([^ ])", current_pos + 1)

            if this_sep and not this_sep:match(sep) then
                problem("unexpected character after closing quote")
            end
        else
            field_end, sep_end, this_sep = field_find(sep, 1)
            if parameters.trim_fields == false then
                tidy = function(s)
                    return s
                end
            else
                tidy = util.trim_space
            end
        end

        field_end = (field_end or 0) - 1

        local value = field_sub(1, field_end)

        value =
            value
            :gsub("\r\n", "\n")
            :gsub("\r", "\n")

        for nl in value:gmatch("\n()") do
            line = line + 1
            line_start = nl + field_start
        end

        value = tidy(value)

        if value ~= "" then
            nonblanks = true
        end

        if parameters.empty_as_nil and value == "" then
            value = nil
        end

        field_count = field_count + 1

        local key

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
            key = header[field_count]
        else
            key = field_count
        end

        if key then
            fields[key] = value
            starts[key] = {
                line = field_start_line,
                column = field_start_column,
            }
        end

        if not this_sep or this_sep == "\r" or this_sep == "\n" then
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

                    header = fields
                    header_read = true

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
                        break
                    end
                end
            end

            field_count, fields, starts, nonblanks = 0, {}, {}, false
        end

        if not sep_end then
            break
        end

        if this_sep == "\r" or this_sep == "\n" then
            if this_sep == "\r" and field_sub(sep_end + 1, sep_end + 1) == "\n" then
                sep_end = sep_end + 1
            end

            line = line + 1
            line_start = field_start + sep_end
        end

        advance(sep_end)
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
function parser.use(buffer, parameters)
    parameters = parameters or {}
    parameters.filename = parameters.filename or "<unknown>"
    parameters.column_map = parameters.columns and column_map.new(parameters.columns)

    if not buffer then
        buffer = file_buffer.new(io.stdin, parameters.buffer_size)
    elseif io.type(buffer) == "file" then
        buffer = file_buffer.new(buffer, parameters.buffer_size)
    end

    local f = setmetatable({
        buffer = buffer,
        parameters = parameters,
    }, buffer_mt)

    ---@cast f CsvFile
    return f
end

---Open a CSV file from disk.
---@param filename string
---@param parameters CsvParameters?
---@return CsvFile?, string?
function parser.open(filename, parameters)
    parameters = parameters or {}
    parameters.filename = filename

    local file, message = io.open(filename, "rb")

    if not file then
        return nil, message
    end

    local requested_encoding = parameters.encoding or "auto"

    -- UTF-8 files still stream.
    -- UTF-16 files are decoded into a UTF-8 Lua string first.
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
