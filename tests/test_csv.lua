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

-------------------------------------------------------------------------------
-- Test: header select returns only requested columns
-------------------------------------------------------------------------------

do
    local rows = csv.decode([[
id,name,email,role
1,Daniel,daniel@example.com,Admin
2,Alex,alex@example.com,Editor
]], {
        header = true,
        strict = true,
        select = { "id", "role" },
    })

    assert_equal(#rows, 2)
    assert_equal(rows[1].id, "1")
    assert_equal(rows[1].role, "Admin")
    assert_equal(rows[1].name, nil)
    assert_equal(rows[1].email, nil)
    assert_equal(rows[2].role, "Editor")
end

-------------------------------------------------------------------------------
-- Test: numeric select returns only requested physical columns
-------------------------------------------------------------------------------

do
    local rows = csv.decode([[
a,b,c,d
1,2,3,4
]], {
        strict = true,
        select = { 1, 3 },
    })

    assert_equal(#rows, 2)
    assert_equal(rows[1][1], "a")
    assert_equal(rows[1][2], nil)
    assert_equal(rows[1][3], "c")
    assert_equal(rows[2][1], "1")
    assert_equal(rows[2][3], "3")
end

-------------------------------------------------------------------------------
-- Test: select still lets strict count skipped fields
-------------------------------------------------------------------------------

do
    local ok, err = csv.validate_string([[
id,name,email
1,Daniel,daniel@example.com
2,Alex
]], {
        header = true,
        strict = true,
        select = { "id" },
    })

    assert_equal(ok, false)
    assert_equal(type(err), "string")
end

-------------------------------------------------------------------------------
-- Test: columns mapping acts as implicit projection
-------------------------------------------------------------------------------

do
    local rows = csv.decode([[
id,name,age,unused
1,Daniel,30,skip
]], {
        strict = true,

        columns = {
            age = {
                name = "age",
                transform = tonumber,
            },
        },
    })

    assert_equal(#rows, 1)
    assert_equal(rows[1].age, 30)
    assert_equal(rows[1].id, nil)
    assert_equal(rows[1].name, nil)
    assert_equal(rows[1].unused, nil)
end

-------------------------------------------------------------------------------
-- Test: optional field positions
-------------------------------------------------------------------------------

do
    local file = csv.openstring([[
id,name
1,Daniel
]], {
        header = true,
        strict = true,
        positions = true,
    })

    local row, starts = file:read()
    file:close()

    assert_equal(row.id, "1")
    assert_equal(starts.id.line, 2)
    assert_equal(starts.id.column, 1)
    assert_equal(starts.name.line, 2)
    assert_equal(starts.name.column, 3)
end

-------------------------------------------------------------------------------
-- Test: reuse_record reuses iterator row but readall copies rows
-------------------------------------------------------------------------------

do
    local file = csv.openstring([[
id,name
1,Daniel
2,Alex
]], {
        header = true,
        strict = true,
        reuse_record = true,
    })

    local first = file:read()
    local second = file:read()
    file:close()

    assert_equal(first, second, "reuse_record should reuse the row table")
    assert_equal(second.id, "2")
    assert_equal(second.name, "Alex")

    local rows = csv.decode([[
id,name
1,Daniel
2,Alex
]], {
        header = true,
        strict = true,
        reuse_record = true,
    })

    assert_equal(#rows, 2)
    assert_equal(rows[1].id, "1")
    assert_equal(rows[2].id, "2")
    assert_equal(rows[1] == rows[2], false, "readall should copy reused rows")
end

print("test_csv.lua: all tests passed")
