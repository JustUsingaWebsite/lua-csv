-- test_assets.lua
--
-- Fixture-based test for a real-world cleaned asset CSV export.
-- Verifies that the file can be opened in header mode and that expected
-- asset-related columns are present on every row.
--
-- Expected fixture path:
--
--     tests/fixtures/cleaned_assets.csv
--
-- Lune changes:
--   - Replaced debug.getinfo with process.cwd for path resolution

local process = require("@lune/process")

local script_dir = process.cwd

local csv = require("../csv")

local function assert_truthy(value, message)
    if not value then
        error(message or "expected truthy value", 2)
    end
end

local fixture_path = script_dir .. "\\tests\\fixtures\\cleaned_assets.csv"

local file = assert(csv.open(fixture_path, {
    header = true,
    strict = true,
    duplicate_headers = "error",
}))

local row_count = 0
local first_row

for row in file:lines() do
    row_count = row_count + 1

    if not first_row then
        first_row = row
    end

    assert_truthy(row["Asset #"] ~= nil, "missing column: Asset #")
    assert_truthy(row["Tag #"] ~= nil, "missing column: Tag #")
    assert_truthy(row["Description"] ~= nil, "missing column: Description")
    assert_truthy(row["Location Name"] ~= nil, "missing column: Location Name")
    assert_truthy(row["Acquisition Date"] ~= nil, "missing column: Acquisition Date")
end

file:close()

assert_truthy(row_count > 0, "expected at least one asset row")
assert_truthy(first_row, "expected first row")

print("test_assets.lua: read " .. row_count .. " asset rows successfully")
