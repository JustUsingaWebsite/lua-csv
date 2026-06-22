-- csv/unicode.lua
-- BOM detection and UTF-16 decoding helpers.
--
-- The CSV parser itself works on normal Lua strings.
-- UTF-16 input is decoded into UTF-8 before parsing.

local unicode = {}

---@alias CsvEncoding
---| '"auto"'
---| '"utf-8"'
---| '"utf-16le"'
---| '"utf-16be"'

-------------------------------------------------------------------------------
-- UTF-8 encoding
-------------------------------------------------------------------------------

---@param codepoint integer
---@return string
local function codepoint_to_utf8(codepoint)
    if codepoint <= 0x7F then
        return string.char(codepoint)
    elseif codepoint <= 0x7FF then
        return string.char(
            0xC0 + math.floor(codepoint / 0x40),
            0x80 + (codepoint % 0x40)
        )
    elseif codepoint <= 0xFFFF then
        return string.char(
            0xE0 + math.floor(codepoint / 0x1000),
            0x80 + (math.floor(codepoint / 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    elseif codepoint <= 0x10FFFF then
        return string.char(
            0xF0 + math.floor(codepoint / 0x40000),
            0x80 + (math.floor(codepoint / 0x1000) % 0x40),
            0x80 + (math.floor(codepoint / 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    end

    error("invalid Unicode codepoint: " .. tostring(codepoint), 0)
end

-------------------------------------------------------------------------------
-- Encoding detection
-------------------------------------------------------------------------------

---@param sample string
---@param requested CsvEncoding?
---@return '"utf-8"'|'"utf-16le"'|'"utf-16be"'
function unicode.detect_encoding(sample, requested)
    requested = requested or "auto"

    if requested ~= "auto" then
        ---@cast requested '"utf-8"'|'"utf-16le"'|'"utf-16be"'
        return requested
    end

    local b1, b2, b3, b4 = sample:byte(1, 4)

    -- BOM detection.
    if b1 == 0xEF and b2 == 0xBB and b3 == 0xBF then
        return "utf-8"
    end

    if b1 == 0xFF and b2 == 0xFE then
        return "utf-16le"
    end

    if b1 == 0xFE and b2 == 0xFF then
        return "utf-16be"
    end

    -- Simple no-BOM heuristic for mostly ASCII UTF-16 text.
    -- UTF-16LE often looks like: "i\0d\0,\0n\0"
    -- UTF-16BE often looks like: "\0i\0d\0,\0n"
    if b1 and b2 and b3 and b4 then
        if b2 == 0 and b4 == 0 then
            return "utf-16le"
        end

        if b1 == 0 and b3 == 0 then
            return "utf-16be"
        end
    end

    return "utf-8"
end

-------------------------------------------------------------------------------
-- BOM skip helper used by the streaming parser
-------------------------------------------------------------------------------

---@param sub fun(a: integer, b: integer): string
---@return integer
function unicode.find_bom(sub)
    local first3 = sub(1, 3)

    if first3 == "\239\187\191" then
        return 3
    end

    local first2 = sub(1, 2)

    if first2 == "\255\254" then
        error(
            "UTF-16LE BOM detected in streaming parser. Use csv.open/openstring with encoding = 'auto' or 'utf-16le'.",
            0
        )
    elseif first2 == "\254\255" then
        error(
            "UTF-16BE BOM detected in streaming parser. Use csv.open/openstring with encoding = 'auto' or 'utf-16be'.",
            0
        )
    end

    return 0
end

-------------------------------------------------------------------------------
-- UTF-16 decoding
-------------------------------------------------------------------------------

---@param s string
---@param pos integer
---@param endian '"le"'|'"be"'
---@return integer?
local function read_u16(s, pos, endian)
    local b1, b2 = s:byte(pos, pos + 1)

    if not b1 or not b2 then
        return nil
    end

    if endian == "le" then
        return b1 + b2 * 256
    end

    return b1 * 256 + b2
end

---@param s string
---@param encoding '"utf-16le"'|'"utf-16be"'
---@return string
function unicode.decode_utf16(s, encoding)
    local endian = encoding == "utf-16le" and "le" or "be"
    local pos = 1
    local out = {}

    -- Skip BOM if present.
    local b1, b2 = s:byte(1, 2)

    if encoding == "utf-16le" and b1 == 0xFF and b2 == 0xFE then
        pos = 3
    elseif encoding == "utf-16be" and b1 == 0xFE and b2 == 0xFF then
        pos = 3
    end

    while pos <= #s do
        local unit = read_u16(s, pos, endian)

        if not unit then
            error("invalid UTF-16 input: odd number of bytes", 0)
        end

        pos = pos + 2

        local codepoint = unit

        -- Surrogate pair.
        if unit >= 0xD800 and unit <= 0xDBFF then
            local low = read_u16(s, pos, endian)

            if not low then
                error("invalid UTF-16 input: missing low surrogate", 0)
            end

            if low < 0xDC00 or low > 0xDFFF then
                error("invalid UTF-16 input: invalid low surrogate", 0)
            end

            pos = pos + 2

            codepoint =
                0x10000 +
                ((unit - 0xD800) * 0x400) +
                (low - 0xDC00)

        elseif unit >= 0xDC00 and unit <= 0xDFFF then
            error("invalid UTF-16 input: unexpected low surrogate", 0)
        end

        out[#out + 1] = codepoint_to_utf8(codepoint)
    end

    return table.concat(out)
end

---@param s string
---@param requested CsvEncoding?
---@return string
---@return '"utf-8"'|'"utf-16le"'|'"utf-16be"'
function unicode.decode_if_needed(s, requested)
    local encoding = unicode.detect_encoding(s:sub(1, 4), requested)

    if encoding == "utf-16le" then
        return unicode.decode_utf16(s, "utf-16le"), "utf-16le"
    elseif encoding == "utf-16be" then
        return unicode.decode_utf16(s, "utf-16be"), "utf-16be"
    end

    return s, "utf-8"
end

return unicode