-- test_csv.lua
--
-- Core test suite for lua-csv (Luau/Lune version).
-- Covers reading, header mode, decoding strings, embedded newlines,
-- escaped quotes, encoding rows, writing files, and column mapping.
--
-- This test uses simple assert-style helpers, so no external test
-- framework is required.
--
-- Lune changes:
--   - Replaced debug.getinfo with process.cwd for path resolution
--   - Replaced io.open with fs.writeFile / fs.readFile

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

local sample_path = script_dir .. "sample_test.csv"

write_file(sample_path, [[
id,name,email,role
1,Daniel,daniel@example.com,Admin
2,Alex,alex@example.com,Editor
3,Maria,maria@example.com,User
]])

-------------------------------------------------------------------------------
-- Test: basic open/readall with headers
-------------------------------------------------------------------------------

do
    local file = assert(csv.open(sample_path, {
        header = true,
        strict = true,
        duplicate_headers = "error",
    }))

    local rows = file:readall()
    file:close()

    assert_equal(#rows, 3, "should read 3 data rows")
    assert_equal(rows[1].id, "1")
    assert_equal(rows[1].name, "Daniel")
    assert_equal(rows[2].role, "Editor")
    assert_equal(rows[3].email, "maria@example.com")
end

-------------------------------------------------------------------------------
-- Test: decode string
-------------------------------------------------------------------------------

do
    local rows = csv.decode([[
id,name
10,Lua
20,CSV
]], {
        header = true,
        strict = true,
    })

    assert_equal(#rows, 2)
    assert_equal(rows[1].id, "10")
    assert_equal(rows[1].name, "Lua")
    assert_equal(rows[2].id, "20")
    assert_equal(rows[2].name, "CSV")
end

-------------------------------------------------------------------------------
-- Test: embedded newline and escaped quotes
-------------------------------------------------------------------------------

do
    local rows = csv.decode([[
id,note
1,"hello
world"
2,"hello ""quoted"" value"
]], {
        header = true,
        strict = true,
    })

    assert_equal(rows[1].note, "hello\nworld")
    assert_equal(rows[2].note, 'hello "quoted" value')
end

-------------------------------------------------------------------------------
-- Test: encode row
-------------------------------------------------------------------------------

do
    local row = csv.encode_row({
        "Daniel",
        'hello, "world"',
    })

    assert_equal(row, 'Daniel,"hello, ""world"""')
end

-------------------------------------------------------------------------------
-- Test: encode rows
-------------------------------------------------------------------------------

do
    local text = csv.encode({
        { "id", "name" },
        { 1,    "Daniel" },
        { 2,    "Alex" },
    }, {
        newline = "\n",
    })

    assert_equal(text, "id,name\n1,Daniel\n2,Alex")
end

-------------------------------------------------------------------------------
-- Test: writer
-------------------------------------------------------------------------------

do
    local output_path = script_dir .. "writer_output.csv"

    local writer = assert(csv.writer(output_path, {
        newline = "\n",
    }))

    writer:write({ "id", "name" })
    writer:write({ 1, "Daniel" })
    writer:write({ 2, "Alex" })
    writer:close()

    local file = assert(csv.open(output_path, {
        header = true,
        strict = true,
    }))

    local rows = file:readall()
    file:close()

    assert_equal(#rows, 2)
    assert_equal(rows[1].name, "Daniel")
    assert_equal(rows[2].name, "Alex")
end

-------------------------------------------------------------------------------
-- Test: column mapping
-------------------------------------------------------------------------------

do
    local rows = csv.decode([[
User ID,First Name,Age
101,Daniel,30
102,Alex,25
]], {
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
        },
    })

    assert_equal(#rows, 2)
    assert_equal(rows[1].user_id, 101)
    assert_equal(rows[1].first_name, "Daniel")
    assert_equal(rows[1].age, 30)
end

print("test_csv.lua: all tests passed")
