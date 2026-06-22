-- csv/unicode.lua
-- BOM detection and encoding helpers.
-- Current behavior matches the original parser: strip UTF-8 BOM, reject UTF-16.
-- This file is the right place to add UTF-16LE/UTF-16BE decoding later.

local unicode = {}

---@alias CsvEncoding
---| '"utf-8"'
---| '"utf-16le"'
---| '"utf-16be"'

---Detect BOM at the start of a stream/string.
---@param sub fun(a: integer, b: integer): string Function that returns bytes.
---@return integer skip_bytes Number of bytes to skip for UTF-8 BOM.
---@return CsvEncoding encoding Detected encoding.
function unicode.find_bom(sub)
    local first3 = sub(1, 3)

    if first3 == "\239\187\191" then
        return 3, "utf-8"
    end

    local first2 = sub(1, 2)

    if first2 == "\255\254" then
        error("UTF-16LE BOM detected, but UTF-16 decoding is not supported yet", 0)
    elseif first2 == "\254\255" then
        error("UTF-16BE BOM detected, but UTF-16 decoding is not supported yet", 0)
    end

    return 0, "utf-8"
end

return unicode
