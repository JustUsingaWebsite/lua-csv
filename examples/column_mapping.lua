-- column_mapping.lua
--
-- Example showing how to map CSV header names to cleaner Lua keys.
-- Also demonstrates transforming values while reading, such as:
--
--     "101"   -> 101
--     "true"  -> true
--
-- Useful for normalizing messy CSV exports into cleaner Lua tables.

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("^(.*[\\/])") or ""
local root_dir = script_dir:gsub("examples[\\/]*$", "")

package.path = root_dir .. "?.lua;" .. package.path

local csv = require("csv")

local sample_path = script_dir .. "sample_column_mapping.csv"

local f = assert(io.open(sample_path, "wb"))
f:write([[
User ID,First Name,Age,Active
101,Daniel,30,true
102,Alex,25,false
]])
f:close()

local file = assert(csv.open(sample_path, {
    strict = true,

    columns = {
        user_id = {
            name = "User ID",
            transform = tonumber,
        },

        first_name = {
            name = "First Name",
        },

        age = {
            name = "Age",
            transform = tonumber,
        },

        active = {
            name = "Active",
            transform = function(value)
                return value == "true"
            end,
        },
    },
}))

for row in file:lines() do
    print(row.user_id, row.first_name, row.age, row.active)
end

file:close()
