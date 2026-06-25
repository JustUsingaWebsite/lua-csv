-- write_csv.lua
--
-- Example showing how to write rows to a CSV file.
-- Demonstrates csv.writer(), writer:write(), and writer:close().
--
-- Also shows that commas, quotes, and embedded newlines are escaped
-- automatically when writing CSV fields.
--
-- Lune changes:
--   - Replaced debug.getinfo with process.cwd

local process = require("@lune/process")

local script_dir = process.cwd .. "/"

local csv = require("../csv")

local output_path = script_dir .. "output.csv"

local writer = assert(csv.writer(output_path))

writer:write({ "id", "name", "note" })
writer:write({ 1, "Daniel", 'hello, "world"' })
writer:write({ 2, "Lua", "line one\nline two" })
writer:write({ 3, "CSV", "comma, inside field" })

writer:close()

print("Wrote:", output_path)
