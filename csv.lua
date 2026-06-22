-------------------------------------------------------------------------------
-- lua-csv (Modernized Fork)
--
-- Features:
--  + Streaming CSV parser
--  + Embedded quoted newlines
--  + CRLF/LF/CR support
--  + UTF-8 BOM stripping
--  + UTF-16 BOM rejection
--  + Strict mode
--  + Header mode
--  + CSV encoding/writing
--  + LuaLS annotations
--  + Lua 5.1–5.4 + LuaJIT friendly
-------------------------------------------------------------------------------

local DEFAULT_BUFFER_BLOCK_SIZE = 1024 * 1024


-------------------------------------------------------------------------------
-- LuaLS / EmmyLua Type Definitions
-------------------------------------------------------------------------------

---@alias CsvDuplicateHeaderMode
---| '"error"'


---@class CsvParameters
---@field separator string? Single-character separator. Default: ","
---@field header boolean? Use first row as headers
---@field strict boolean? Validate consistent field counts
---@field skip_blank_lines boolean? Default true
---@field duplicate_headers CsvDuplicateHeaderMode?
---@field buffer_size integer? Streaming buffer size
---@field filename string?
---@field record_limit integer?
---@field columns table?
---@field column_map CsvColumnMap?
---@field newline string?



---@class CsvFieldPosition
---@field line integer
---@field column integer


---@alias CsvRow table<any, string>


---@class CsvFile
---@field buffer any
---@field parameters CsvParameters
---@field _iterator function?
---@field lines fun(self: CsvFile): fun():table?
---@field read fun(self: CsvFile): table?
---@field readall fun(self: CsvFile): table[]
---@field close fun(self: CsvFile)
---@field name fun(self: CsvFile): string


---@class CsvWriter
---@field file file*
---@field parameters CsvParameters
---@field write fun(self: CsvWriter, row: table)
---@field close fun(self: CsvWriter)


---@class CsvColumnDefinition
---@field name string?
---@field names string[]?
---@field transform function?
---@field default any


---@class CsvColumnMap
---@field name_map table<string, CsvColumnDefinition>
---@field index_map table<integer, CsvColumnDefinition>
---@field read_header fun(self: CsvColumnMap, header: table): boolean?
---@field transform fun(self: CsvColumnMap, value: any, index: integer): any, string?


------------------------------------------------------------------------------

local function trim_space(s)
    return s:match("^%s*(.-)%s*$")
end


local function fix_quotes(s)
    return string.sub(s:gsub('""', '"'), 1, -2)
end


local function escape_pattern_class_char(s)
    return (s:gsub("([%%%^%]%-])", "%%%1"))
end


------------------------------------------------------------------------------

---@class CsvColumnMapClass: CsvColumnMap
---@field __index CsvColumnMapClass
local column_map = {}
column_map.__index = column_map


local function normalise_string(s)
    return (
        s:lower()
        :gsub("[^%w%d]+", " ")
        :gsub("^ *(.-) *$", "%1")
    )
end


--- Parse column definitions.
---
---@param columns table
---@return CsvColumnMap
function column_map:new(columns)
    local name_map = {}

    for n, v in pairs(columns) do
        local names
        local t

        if type(v) == "table" then
            t = {
                transform = v.transform,
                default = v.default,
            }

            if v.name then
                names = {
                    normalise_string(v.name)
                }
            elseif v.names then
                names = v.names

                for i, name in ipairs(names) do
                    names[i] = normalise_string(name)
                end
            end
        else
            if type(v) == "function" then
                t = {
                    transform = v
                }
            else
                t = {}

                if type(v) == "string" then
                    names = {
                        normalise_string(v)
                    }
                end
            end
        end

        if not names then
            names = {
                normalise_string(n)
            }
        end

        t.name = n

        for _, name in ipairs(names) do
            name_map[name:lower()] = t
        end
    end

    ---@type CsvColumnMap
    local map = setmetatable({
        name_map = name_map,
        index_map = {},
    }, column_map)

    return map
end

--- Read and validate header row.
---
---@param header table
---@return boolean?
function column_map:read_header(header)
    local index_map = {}

    local found = {}
    local found_any

    for i, word in ipairs(header) do
        word = normalise_string(word)

        local r = self.name_map[word]

        if r then
            index_map[i] = r
            found[r.name] = true
            found_any = true
        end
    end

    if not found_any then
        return
    end

    local not_found = {}

    for name, r in pairs(self.name_map) do
        if not found[r.name] then
            local nf = not_found[r.name]

            if nf then
                nf[#nf + 1] = name
            else
                not_found[r.name] = { name }
            end
        end
    end

    if next(not_found) then
        local problems = {}

        for _, v in pairs(not_found) do
            local missing

            if #v == 1 then
                missing = "'" .. v[1] .. "'"
            else
                missing = "'" .. v[1] .. "'"

                for i = 2, #v - 1 do
                    missing = missing .. ", '" .. v[i] .. "'"
                end

                missing = missing .. " or '" .. v[#v] .. "'"
            end

            problems[#problems + 1] =
                "Couldn't find a column named " .. missing
        end

        error(table.concat(problems, "\n"), 0)
    end

    self.index_map = index_map

    return true
end

---@param value any
---@param index integer
---@return any, string?
function column_map:transform(value, index)
    local field = self.index_map[index]

    if field then
        if field.transform then
            local ok

            ok, value = pcall(field.transform, value)

            if not ok then
                error(
                    ("Error reading field '%s': %s")
                    :format(field.name, value),
                    0
                )
            end
        end

        return value or field.default, field.name
    end
end

------------------------------------------------------------------------------

local file_buffer = {}
file_buffer.__index = file_buffer


---@param file file*
---@param buffer_block_size integer?
---@return table
function file_buffer:new(file, buffer_block_size)
    return setmetatable({
        file              = file,
        buffer_block_size = buffer_block_size or DEFAULT_BUFFER_BLOCK_SIZE,
        buffer_start      = 0,
        buffer            = "",
    }, file_buffer)
end

function file_buffer:truncate(p)
    p = p - self.buffer_start

    if p > self.buffer_block_size then
        local remove =
            self.buffer_block_size *
            math.floor((p - 1) / self.buffer_block_size)

        self.buffer = self.buffer:sub(remove + 1)
        self.buffer_start = self.buffer_start + remove
    end
end

function file_buffer:find(pattern, init)
    while true do
        local first, last, capture =
            self.buffer:find(pattern, init - self.buffer_start)

        if not first or last == #self.buffer then
            local s = self.file:read(self.buffer_block_size)

            if not s then
                if not first then
                    return
                else
                    return first + self.buffer_start,
                        last + self.buffer_start,
                        capture
                end
            end

            self.buffer = self.buffer .. s
        else
            return first + self.buffer_start,
                last + self.buffer_start,
                capture
        end
    end
end

function file_buffer:extend(offset)
    local extra = offset - #self.buffer - self.buffer_start

    if extra > 0 then
        local size =
            self.buffer_block_size *
            math.ceil(extra / self.buffer_block_size)

        local s = self.file:read(size)

        if not s then
            return
        end

        self.buffer = self.buffer .. s
    end
end

function file_buffer:sub(a, b)
    self:extend(b)

    b = b == -1 and b or b - self.buffer_start

    return self.buffer:sub(a - self.buffer_start, b)
end

function file_buffer:close()
    self.file:close()
    self.file = nil
end

------------------------------------------------------------------------------

local separator_candidates = {
    ",",
    "\t",
    "|",
    ";"
}

local guess_separator_params = {
    record_limit = 8
}


local function try_separator(buffer, sep, f)
    local params = {
        separator = sep,
        record_limit = guess_separator_params.record_limit,
        filename = "<separator guess>",
    }

    local min, max = math.huge, 0
    local lines, split_lines = 0, 0

    local iterator = coroutine.wrap(function()
        f(buffer, params)
    end)

    for t in iterator do
        min = math.min(min, #t)
        max = math.max(max, #t)

        split_lines = split_lines + (t[2] and 1 or 0)
        lines = lines + 1
    end

    if lines == 0 then
        return math.huge
    end

    if split_lines / lines > 0.75 then
        return max - min
    else
        return math.huge
    end
end


local function guess_separator(buffer, f)
    local best_separator, lowest_diff = ",", math.huge

    for _, s in ipairs(separator_candidates) do
        local ok, diff = pcall(function()
            return try_separator(buffer, s, f)
        end)

        if ok and diff < lowest_diff then
            best_separator = s
            lowest_diff = diff
        end
    end

    return best_separator
end


local function find_unicode_BOM(sub)
    local first3 = sub(1, 3)

    if first3 == "\239\187\191" then
        return 3
    end

    local first2 = sub(1, 2)

    if first2 == "\254\255" or first2 == "\255\254" then
        error(
            "UTF-16 BOM detected, but UTF-16 decoding is not supported",
            0
        )
    end

    return 0
end


------------------------------------------------------------------------------

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


    local function field_sub(a, b)
        b = b == -1 and b or b + field_start - 1

        return buffer:sub(a + field_start - 1, b)
    end


    local function field_find(pattern, init)
        init = init or 1

        local f, l, c =
            buffer:find(pattern, init + field_start - 1)

        if not f then
            return
        end

        return f - field_start + 1,
            l - field_start + 1,
            c
    end


    advance(find_unicode_BOM(field_sub))

    local raw_separator =
        parameters.separator or
        guess_separator(buffer, separated_values_iterator)

    raw_separator = raw_separator or ","

    if #raw_separator ~= 1 then
        error("separator must be a single character", 0)
    end

    local sep =
        "([" ..
        escape_pattern_class_char(raw_separator) ..
        "\n\r])"

    local line_start = 1
    local line = 1

    local field_count, fields, starts, nonblanks =
        0, {}, {}, false

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
                local _, b, c =
                    field_find('"("?)', current_pos + 1)

                if not b then
                    problem("unmatched quote")
                end

                current_pos = b

                if c ~= '"' then
                    break
                end
            end

            tidy = fix_quotes

            field_end, sep_end, this_sep =
                field_find(" *([^ ])", current_pos + 1)

            if this_sep and not this_sep:match(sep) then
                problem("unexpected character after closing quote")
            end
        else
            field_end, sep_end, this_sep =
                field_find(sep, 1)

            tidy = trim_space
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

        if #value > 0 then
            nonblanks = true
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

        if not this_sep or
            this_sep == "\r" or
            this_sep == "\n"
        then
            if parameters.column_map and not header_read then
                header_read =
                    parameters.column_map:read_header(fields)

                if header_read and parameters.strict then
                    expected_field_count = field_count
                end
            elseif parameters.header and not header_read then
                if should_keep_record() then
                    if parameters.duplicate_headers == "error" then
                        local seen = {}

                        for _, name in ipairs(fields) do
                            if seen[name] then
                                problem(
                                    "duplicate header: " ..
                                    tostring(name)
                                )
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

                    if parameters.record_limit and
                        record_count >= parameters.record_limit
                    then
                        break
                    end
                end
            end

            field_count, fields, starts, nonblanks =
                0, {}, {}, false
        end

        if not sep_end then
            break
        end

        if this_sep == "\r" or this_sep == "\n" then
            if this_sep == "\r" and
                field_sub(sep_end + 1, sep_end + 1) == "\n"
            then
                sep_end = sep_end + 1
            end

            line = line + 1
            line_start = field_start + sep_end
        end

        advance(sep_end)
    end
end


------------------------------------------------------------------------------

local buffer_mt = {

    lines = function(t)
        return coroutine.wrap(function()
            separated_values_iterator(
                t.buffer,
                t.parameters
            )
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


------------------------------------------------------------------------------

--- Use an existing string/file/buffer as CSV input.
---
---@param buffer any
---@param parameters CsvParameters?
---@return CsvFile
local function use(buffer, parameters)
    parameters = parameters or {}

    parameters.filename =
        parameters.filename or "<unknown>"

    parameters.column_map =
        parameters.columns and
        column_map:new(parameters.columns)

    if not buffer then
        buffer =
            file_buffer:new(
                io.stdin,
                parameters.buffer_size
            )
    elseif io.type(buffer) == "file" then
        buffer =
            file_buffer:new(
                buffer,
                parameters.buffer_size
            )
    end

    local f = setmetatable({
        buffer = buffer,
        parameters = parameters,
    }, buffer_mt)

    ---@cast f CsvFile
    return f
end


------------------------------------------------------------------------------

--- Open a CSV file from disk.

---@param filename string
---@param parameters CsvParameters?
---@return CsvFile?, string?
local function open(filename, parameters)
    local file, message = io.open(filename, "rb")

    if not file then
        return nil, message
    end

    parameters = parameters or {}
    parameters.filename = filename

    return use(file, parameters), nil
end


------------------------------------------------------------------------------

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


------------------------------------------------------------------------------

--- Open CSV data from a string.
---
---@param filecontents string
---@param parameters CsvParameters?
---@return CsvFile
local function openstring(filecontents, parameters)
    parameters = parameters or {}

    parameters.filename =
        parameters.filename or makename(filecontents)

    parameters.buffer_size =
        parameters.buffer_size or #filecontents

    return use(filecontents, parameters)
end


------------------------------------------------------------------------------

local function encode_field(value, separator)
    separator = separator or ","

    value = tostring(value or "")

    local must_quote =
        value:find(separator, 1, true) or
        value:find('"', 1, true) or
        value:find("\r", 1, true) or
        value:find("\n", 1, true)

    if must_quote then
        value = value:gsub('"', '""')

        return '"' .. value .. '"'
    end

    return value
end


------------------------------------------------------------------------------

--- Encode a single row into CSV text.
---
---@param row table
---@param parameters CsvParameters?
---@return string
local function encode_row(row, parameters)
    parameters = parameters or {}

    local separator = parameters.separator or ","

    if #separator ~= 1 then
        error("separator must be a single character", 0)
    end

    local fields = {}

    for _, value in ipairs(row) do
        fields[#fields + 1] =
            encode_field(value, separator)
    end

    return table.concat(fields, separator)
end


------------------------------------------------------------------------------

--- Encode rows into CSV text.
---
---@param rows table[]
---@param parameters CsvParameters?
---@return string
local function encode(rows, parameters)
    parameters = parameters or {}

    local newline =
        parameters.newline or "\r\n"

    local out = {}

    for _, row in ipairs(rows) do
        out[#out + 1] =
            encode_row(row, parameters)
    end

    return table.concat(out, newline)
end


------------------------------------------------------------------------------

local writer_mt = {}

writer_mt.__index = writer_mt


function writer_mt:write(row)
    self.file:write(
        encode_row(row, self.parameters)
    )

    self.file:write(
        self.parameters.newline or "\r\n"
    )
end

function writer_mt:close()
    self.file:close()
end

------------------------------------------------------------------------------

--- Create a CSV writer.
---
---@param filename string
---@param parameters CsvParameters?
---@return CsvWriter?, string?
local function writer(filename, parameters)
    parameters = parameters or {}

    local file, message =
        io.open(filename, "wb")

    if not file then
        return nil, message
    end

    local out = setmetatable({
        file = file,
        parameters = parameters,
    }, writer_mt)

    ---@cast out CsvWriter
    return out, nil
end


------------------------------------------------------------------------------

--- Decode CSV text into rows.
---
---@param s string
---@param parameters CsvParameters?
---@return table[]
local function decode(s, parameters)
    local f = openstring(s, parameters)

    return f:readall()
end


------------------------------------------------------------------------------

return {

    open = open,
    openstring = openstring,
    use = use,

    decode = decode,

    encode = encode,
    encode_row = encode_row,

    writer = writer,
}
