-- csv/encoder.lua
-- CSV encoding and writer support.
--
-- Luau/Lune rewrite:
--   - Writer uses Lune's fs.writeFile when available
--   - Falls back to io.open for pure Lua compatibility
--   - Uses Luau string interpolation

local encoder = {}

---Encode one field. Quote only when required by CSV rules.
---@param value any
---@param separator string?
---@return string
local function encode_field(value, separator, parameters)
    parameters = parameters or {}
    separator = separator or ","

    if value == nil then
        value = parameters.nil_value
    end

    value = tostring(value or "")

    local must_quote =
        parameters.quote_all or
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

---Encode a single CSV row.
---@param row table
---@param parameters CsvParameters?
---@return string
function encoder.encode_row(row, parameters)
    parameters = parameters or {}

    local sep = parameters.separator or ","

    if #sep ~= 1 then
        error("separator must be a single character", 0)
    end

    local fields = {}

    for _, value in ipairs(row) do
        fields[#fields + 1] = encode_field(value, sep, parameters)
    end

    return table.concat(fields, sep)
end

---Encode multiple rows into one CSV string.
---@param rows table[]
---@param parameters CsvParameters?
---@return string
function encoder.encode(rows, parameters)
    parameters = parameters or {}

    local newline = parameters.newline or "\r\n"
    local out = {}

    for _, row in ipairs(rows) do
        out[#out + 1] = encoder.encode_row(row, parameters)
    end

    return table.concat(out, newline)
end

-- Detect Lune fs availability
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

local writer_mt = {}
writer_mt.__index = writer_mt

function writer_mt:write(row)
    self.chunks[#self.chunks + 1] = encoder.encode_row(row, self.parameters)
end

function writer_mt:close()
    local content = table.concat(self.chunks, self.parameters.newline or "\r\n")

    if has_lune_fs then
        -- Lune path: write file using fs.writeFile (supports string and buffer)
        fs.writeFile(self.filename, content)
    elseif self.file then
        -- Lua fallback path: write through file handle
        self.file:write(content)
        self.file:close()
        self.file = nil
    end
end

---Create a CSV writer object.
---@param filename string
---@param parameters CsvParameters?
---@return CsvWriter?, string?
function encoder.writer(filename, parameters)
    parameters = parameters or {}

    if not has_lune_fs then
        -- Lua fallback: open file immediately for incremental writes
        local file, message = io.open(filename, "wb")

        if not file then
            return nil, message
        end

        local out = setmetatable({
            filename = filename,
            file = file,
            parameters = parameters,
            chunks = {},
        }, writer_mt)

        ---@cast out CsvWriter
        return out, nil
    end

    -- Lune path: buffer chunks and write all at once on close
    local out = setmetatable({
        filename = filename,
        file = nil,
        parameters = parameters,
        chunks = {},
    }, writer_mt)

    ---@cast out CsvWriter
    return out, nil
end

return encoder
