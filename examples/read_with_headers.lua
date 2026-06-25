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
--
-- Lune changes:
--   - Replaced debug.getinfo with process.cwd
--   - Replaced io.open with fs.writeFile

local fs = require("@lune/fs")
local process = require("@lune/process")

local script_dir = process.cwd .. "/"

local csv = require("../csv")

local sample_path = script_dir .. "sample_headers.csv"

fs.writeFile(sample_path, [[
id,first_name,last_name,email
101,Jane,Doe,jane@example.com
102,John,Smith,john@example.com
]])

local file = assert(csv.open(sample_path, {
    header = true,
    strict = true,
    duplicate_headers = "error",
}))

for row in file:lines() do
    print(row.id, row.first_name, row.last_name, row.email)
end

file:close()
