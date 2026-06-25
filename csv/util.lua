-- csv/util.lua
-- Small string/pattern helpers used by the parser, encoder, and column mapper.
--
-- Luau rewrite: uses Luau string interpolation where applicable.

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

---Get the directory portion of a file path.
---Replaces the common `debug.getinfo(1, "S").source:sub(2)` pattern
---which is unavailable in Lune.
---
---Usage: `local script_dir = util.script_dir()`
---@return string
function util.script_dir()
    -- In Lune, process.cwd and args can help determine the working directory.
    -- For script-relative paths, Lune resolves requires relative to the script.
    -- We use the Luau require path resolution instead of debug.getinfo.
    local ok, process = pcall(function()
        return require("@lune/process")
    end)

    if ok then
        -- Lune: use cwd as the base directory
        return process.cwd .. "/"
    end

    -- Fallback: try debug.getinfo if available (standard Lua)
    local debug_ok, info = pcall(function()
        return debug.getinfo(2, "S")
    end)

    if debug_ok and info and info.source then
        local path = info.source:sub(2)
        local dir = path:match("^(.*[\\/])") or ""
        return dir
    end

    -- Last resort: current directory
    return "./"
end

return util
