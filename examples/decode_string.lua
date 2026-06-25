-- decode_string.lua
--
-- Example showing how to decode CSV data directly from a Lua string.
-- This is useful when CSV content comes from memory, an API response,
-- a generated string, or another source that is not a file on disk.
--
-- Uses csv.decode() and returns all rows at once.
--
-- Lune changes:
--   - Replaced debug.getinfo with process.cwd

local process = require("@lune/process")

local script_dir = process.cwd .. "/"

local csv = require("../csv")

local text = [[
id,name,role
1,Daniel,Admin
2,Alex,Editor
3,Maria,User
]]

local rows = csv.decode(text, {
    header = true,
    strict = true,
})

for i, row in ipairs(rows) do
    print(i, row.id, row.name, row.role)
end

-------------------------------------------------------------------------------
-- Encode Lua rows into CSV text, then decode back
-------------------------------------------------------------------------------

local csv_text = csv.encode({
    { "id", "name", "role" },
    { 1, "Daniel", "Admin" },
    { 2, "Alex", "Editor" },
    { 3, "Maria", "User" },
}, {
    newline = "\n",
})

print("Encoded CSV text:")
print(csv_text)

-------------------------------------------------------------------------------
-- Decode the generated CSV text back into Lua tables
-------------------------------------------------------------------------------

local decoded_rows = csv.decode(csv_text, {
    header = true,
    strict = true,
})

print("")
print("Decoded rows:")

for i, row in ipairs(decoded_rows) do
    print(i, row.id, row.name, row.role)
end
