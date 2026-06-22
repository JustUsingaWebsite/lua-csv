-- csv/validate.lua
-- Validation helper. Opens a CSV file and reads through it to catch parser errors.

local parser = require("csv.parser")

local validate = {}

---@param filename string
---@param parameters CsvParameters?
---@return boolean
---@return string?
function validate.file(filename, parameters)
    local file, err = parser.open(filename, parameters)

    if not file then
        return false, err
    end

    local ok, message = pcall(function()
        for _ in file:lines() do
            -- Intentionally consume all rows.
        end
    end)

    file:close()

    if not ok then
        return false, tostring(message)
    end

    return true, nil
end

---@param text string
---@param parameters CsvParameters?
---@return boolean
---@return string?
function validate.string(text, parameters)
    local file = parser.openstring(text, parameters)

    local ok, message = pcall(function()
        for _ in file:lines() do
            -- Intentionally consume all rows.
        end
    end)

    file:close()

    if not ok then
        return false, tostring(message)
    end

    return true, nil
end

return validate