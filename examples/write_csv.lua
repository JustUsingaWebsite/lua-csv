-- write_csv.lua
--
-- Example showing how to write rows to a CSV file.
-- Demonstrates csv.writer(), writer:write(), and writer:close().
--
-- Also shows that commas, quotes, and embedded newlines are escaped
-- automatically when writing CSV fields.

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("^(.*[\\/])") or ""
local root_dir = script_dir:gsub("examples[\\/]*$", "")

package.path = root_dir .. "?.lua;" .. package.path

local csv = require("csv")

local output_path = script_dir .. "output.csv"

local writer = assert(csv.writer(output_path))

writer:write({ "id", "name", "note" })
writer:write({ 1, "Daniel", 'hello, "world"' })
writer:write({ 2, "Lua", "line one\nline two" })
writer:write({ 3, "CSV", "comma, inside field" })

writer:close()

print("Wrote:", output_path)
