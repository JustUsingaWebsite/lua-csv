-- column_mapping.lua
--
-- Example showing how to map CSV header names to cleaner Lua keys.
-- Also demonstrates transforming values while reading, such as:
--
--     "101"   -> 101
--     "true"  -> true
--
-- Useful for normalizing messy CSV exports into cleaner Lua tables.
--
-- Lune changes:
--   - Replaced debug.getinfo with process.cwd
--   - Replaced io.open with fs.writeFile

local fs = require("@lune/fs")
local process = require("@lune/process")

local script_dir = process.cwd .. "/"

local csv = require("../csv")

local sample_path = script_dir .. "sample_column_mapping.csv"

fs.writeFile(sample_path, [[
User ID,First Name,Age,Active
101,Daniel,30,true
102,Alex,25,false
]])

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
