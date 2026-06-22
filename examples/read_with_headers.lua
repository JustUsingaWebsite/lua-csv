-- read_with_headers.lua
--
-- Example showing how to read a CSV file using the first row as headers.
-- When header = true, each row is returned as a key/value table:
--
--     row.id
--     row.first_name
--     row.email
--
-- This is useful when working with structured CSV exports.

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("^(.*[\\/])") or ""
local root_dir = script_dir:gsub("examples[\\/]*$", "")

package.path = root_dir .. "?.lua;" .. package.path

local csv = require("csv")

local sample_path = script_dir .. "sample_headers.csv"

local f = assert(io.open(sample_path, "wb"))
f:write([[
id,first_name,last_name,email
101,Jane,Doe,jane@example.com
102,John,Smith,john@example.com
]])
f:close()

local file = assert(csv.open(sample_path, {
    header = true,
    strict = true,
    duplicate_headers = "error",
}))

for row in file:lines() do
    print(row.id, row.first_name, row.last_name, row.email)
end

file:close()
