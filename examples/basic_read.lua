-- basic_read.lua
--
-- Minimal example showing how to read a CSV file without headers.
-- Each row is returned as an array-style table:
--
--     row[1], row[2], row[3], ...
--
-- This example creates a small temporary CSV file, reads it,
-- prints each row, and closes the file.

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("^(.*[\\/])") or ""
local root_dir = script_dir:gsub("examples[\\/]*$", "")

package.path = root_dir .. "?.lua;" .. package.path

local csv = require("csv")

local sample_path = script_dir .. "sample_basic.csv"

local f = assert(io.open(sample_path, "wb"))
f:write([[
101,Jane,Doe,jane@example.com
102,John,Smith,john@example.com
103,Alex,Jones,alex@example.com
]])
f:close()

local file = assert(csv.open(sample_path))

for row in file:lines() do
    print(row[1], row[2], row[3], row[4])
end

file:close()
