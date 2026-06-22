-- csv/util.lua
-- Small string/pattern helpers used by the parser, encoder, and column mapper.

local util = {}

---Trim leading and trailing whitespace from an unquoted CSV field.
---@param s string
---@return string
function util.trim_space(s)
    return s:match("^%s*(.-)%s*$")
end

---Unescape doubled quotes inside a quoted field and remove the closing quote.
---The parser reads quoted field contents starting after the opening quote and
---ending at the closing quote, so this turns: hello ""world""" -> hello "world".
---@param s string
---@return string
function util.fix_quotes(s)
    return string.sub(s:gsub('""', '"'), 1, -2)
end

---Escape characters that are special inside a Lua pattern character class.
---Used when building a separator matcher like: ([,\n\r])
---@param s string
---@return string
function util.escape_pattern_class_char(s)
    return (s:gsub("([%%%^%]%-])", "%%%1"))
end

---Normalize header names for column mapping.
---Example: "First Name" and "first-name" both become "first name".
---@param s string|number
---@return string
function util.normalise_string(s)
    s = tostring(s)

    return (
        s:lower()
        :gsub("[^%w%d]+", " ")
        :gsub("^ *(.-) *$", "%1")
    )
end

return util
