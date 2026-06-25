-- tests/test_utf16.lua
--
-- UTF-16 tests for lua-csv (Luau/Lune version).
-- Run from repo root:
--
--     lune tests/test_utf16.lua
--
-- Lune changes:
--   - Replaced debug.getinfo with process.cwd for path resolution
--   - Replaced io.open with fs.writeFile

local fs = require("@lune/fs")
local process = require("@lune/process")

local script_dir = process.cwd .. "/"

local csv = require("../csv")

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(
            (message or "assert_equal failed") ..
            "\nexpected: " .. tostring(expected) ..
            "\nactual:   " .. tostring(actual),
            2
        )
    end
end

local function write_file(path, contents)
    fs.writeFile(path, contents)
end

local function ascii_to_utf16le(s, with_bom)
    local out = {}

    if with_bom then
        out[#out + 1] = string.char(0xFF, 0xFE)
    end

    for i = 1, #s do
        out[#out + 1] = s:sub(i, i)
        out[#out + 1] = "\0"
    end

    return table.concat(out)
end

local function ascii_to_utf16be(s, with_bom)
    local out = {}

    if with_bom then
        out[#out + 1] = string.char(0xFE, 0xFF)
    end

    for i = 1, #s do
        out[#out + 1] = "\0"
        out[#out + 1] = s:sub(i, i)
    end

    return table.concat(out)
end

-------------------------------------------------------------------------------
-- Test: UTF-16LE string with BOM, auto-detected
-------------------------------------------------------------------------------

do
    local text = ascii_to_utf16le([[
id,name,role
1,Daniel,Admin
2,Alex,Editor
]], true)

    local rows = csv.decode(text, {
        encoding = "auto",
        header = true,
        strict = true,
    })

    assert_equal(#rows, 2)
    assert_equal(rows[1].id, "1")
    assert_equal(rows[1].name, "Daniel")
    assert_equal(rows[1].role, "Admin")
    assert_equal(rows[2].name, "Alex")
end

-------------------------------------------------------------------------------
-- Test: UTF-16BE string with BOM, auto-detected
-------------------------------------------------------------------------------

do
    local text = ascii_to_utf16be([[
id,name
1,Daniel
2,Alex
]], true)

    local rows = csv.decode(text, {
        encoding = "auto",
        header = true,
        strict = true,
    })

    assert_equal(#rows, 2)
    assert_equal(rows[1].id, "1")
    assert_equal(rows[1].name, "Daniel")
    assert_equal(rows[2].name, "Alex")
end

-------------------------------------------------------------------------------
-- Test: UTF-16LE string without BOM, explicit encoding
-------------------------------------------------------------------------------

do
    local text = ascii_to_utf16le([[
id,name
1,Daniel
]], false)

    local rows = csv.decode(text, {
        encoding = "utf-16le",
        header = true,
        strict = true,
    })

    assert_equal(#rows, 1)
    assert_equal(rows[1].id, "1")
    assert_equal(rows[1].name, "Daniel")
end

-------------------------------------------------------------------------------
-- Test: UTF-16LE file with BOM, auto-detected
-------------------------------------------------------------------------------

do
    local path = script_dir .. "utf16le_sample.csv"

    write_file(path, ascii_to_utf16le([[
id,name
1,Daniel
2,Alex
]], true))

    local file = assert(csv.open(path, {
        encoding = "auto",
        header = true,
        strict = true,
    }))

    local rows = file:readall()
    file:close()

    assert_equal(#rows, 2)
    assert_equal(rows[1].id, "1")
    assert_equal(rows[1].name, "Daniel")
    assert_equal(rows[2].name, "Alex")
end

-------------------------------------------------------------------------------
-- Test: UTF-16BE file with BOM, auto-detected
-------------------------------------------------------------------------------

do
    local path = script_dir .. "utf16be_sample.csv"

    write_file(path, ascii_to_utf16be([[
id,name
1,Daniel
2,Alex
]], true))

    local file = assert(csv.open(path, {
        encoding = "auto",
        header = true,
        strict = true,
    }))

    local rows = file:readall()
    file:close()

    assert_equal(#rows, 2)
    assert_equal(rows[1].id, "1")
    assert_equal(rows[1].name, "Daniel")
    assert_equal(rows[2].name, "Alex")
end

print("test_utf16.lua: all tests passed")
