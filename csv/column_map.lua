-- csv/column_map.lua
-- Header mapping and value transforms. Lets users map messy CSV headers to
-- clean Lua keys and optionally transform/default values.
--
-- Luau rewrite: uses Luau string interpolation.

local util = require("./util")

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

---@class CsvColumnMapClass: CsvColumnMap
---@field __index CsvColumnMapClass
local column_map = {}
column_map.__index = column_map

---Build a column mapper from user column definitions.
---@param columns table
---@return CsvColumnMap
function column_map.new(columns)
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
                names = { util.normalise_string(v.name) }
            elseif v.names then
                names = v.names

                for i, name in ipairs(names) do
                    names[i] = util.normalise_string(name)
                end
            end
        else
            if type(v) == "function" then
                t = { transform = v }
            else
                t = {}

                if type(v) == "string" then
                    names = { util.normalise_string(v) }
                end
            end
        end

        if not names then
            names = { util.normalise_string(n) }
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

---Read CSV header row and connect physical column indexes to mapped names.
---@param header table
---@return boolean?
function column_map:read_header(header)
    local index_map = {}
    local found = {}
    local found_any

    for i, word in ipairs(header) do
        word = util.normalise_string(word)

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

---Apply a column transform/default and return the mapped output key.
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
                error("Error reading field '" .. field.name .. "': " .. tostring(value), 0)
            end
        end

        return value or field.default, field.name
    end
end

return column_map
