-- csv/separator.lua
-- Separator guessing helpers. Tries common delimiters and picks the one that
-- produces the most consistent-looking rows.

local separator = {}

separator.candidates = {
    ",",
    "\t",
    "|",
    ";",
}

separator.guess_params = {
    record_limit = 8,
}

---@param buffer any
---@param sep string
---@param iterator_factory fun(buffer: any, parameters: table)
---@return number
local function try_separator(buffer, sep, iterator_factory)
    local params = {
        separator = sep,
        record_limit = separator.guess_params.record_limit,
        filename = "<separator guess>",
    }

    local min, max = math.huge, 0
    local lines, split_lines = 0, 0

    local iterator = coroutine.wrap(function()
        iterator_factory(buffer, params)
    end)

    for row in iterator do
        min = math.min(min, #row)
        max = math.max(max, #row)
        split_lines = split_lines + (row[2] and 1 or 0)
        lines = lines + 1
    end

    if lines == 0 then
        return math.huge
    end

    if split_lines / lines > 0.75 then
        return max - min
    end

    return math.huge
end

---@param buffer any
---@param iterator_factory fun(buffer: any, parameters: table)
---@return string
function separator.guess(buffer, iterator_factory)
    local best_separator, lowest_diff = ",", math.huge

    for _, s in ipairs(separator.candidates) do
        local ok, diff = pcall(function()
            return try_separator(buffer, s, iterator_factory)
        end)

        if ok and diff < lowest_diff then
            best_separator = s
            lowest_diff = diff
        end
    end

    return best_separator
end

return separator
