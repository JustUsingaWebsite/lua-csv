-- basic_read.lua
--
-- Minimal example showing how to read a CSV file without headers.
-- Each row is returned as an array-style table:
--
--     row[1], row[2], row[3], ...
--
-- This example creates a small temporary CSV file, reads it,
-- prints each row, and closes the file.
--
-- Lune changes:
--   - Replaced debug.getinfo with process.cwd
--   - Replaced io.open with fs.writeFile

local fs = require("@lune/fs")
local process = require("@lune/process")

local script_dir = process.cwd .. "/"

local csv = require("../csv")

local sample_path = script_dir .. "sample_basic.csv"

fs.writeFile(sample_path, [[
101,Jane,Doe,jane@example.com
102,John,Smith,john@example.com
103,Alex,Jones,alex@example.com
]])

local file = assert(csv.open(sample_path))

for row in file:lines() do
    print(row[1], row[2], row[3], row[4])
end

file:close()
