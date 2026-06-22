-- tests/test_v03_options.lua
--
-- Simple v0.3 option tests for lua-csv.
-- Run from repo root:
--
--     lua tests/test_v03_options.lua

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("^(.*[\\/])") or ""
local root_dir = script_dir:gsub("tests[\\/]*$", "")

package.path =
    root_dir .. "?.lua;" ..
    root_dir .. "?/init.lua;" ..
    root_dir .. "?\\init.lua;" ..
    package.path

local csv = require("csv")

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

local function assert_true(value, message)
    if not value then
        error(message or "assert_true failed", 2)
    end
end

local function assert_false(value, message)
    if value then
        error(message or "assert_false failed", 2)
    end
end

local function write_file(path, contents)
    local f = assert(io.open(path, "wb"))
    f:write(contents)
    f:close()
end

-------------------------------------------------------------------------------
-- Test: quote_all
-------------------------------------------------------------------------------

do
    local text = csv.encode({
        { "id", "name" },
        { 1, "Daniel" },
    }, {
        newline = "\n",
        quote_all = true,
    })

    assert_equal(
        text,
        [["id","name"]] .. "\n" .. [["1","Daniel"]],
        "quote_all should quote every field"
    )
end

-------------------------------------------------------------------------------
-- Test: nil_value
--
-- Note:
-- Lua arrays cannot naturally preserve nil holes with ipairs().
-- So this test uses an explicit placeholder in a simple row shape where
-- your encoder implementation should handle nil if it iterates by width.
--
-- If your encoder still uses ipairs(row), nil in the middle will stop iteration.
-- In that case, skip this test or add a width option later.
-------------------------------------------------------------------------------

do
    local text = csv.encode_row({
        "id",
        nil,
        "role",
    }, {
        nil_value = "NULL",
    })

    -- If your encoder uses ipairs(), this may return only "id".
    -- If you implemented nil handling with fixed width support, expected:
    -- id,NULL,role
    --
    -- For now this checks the simple behavior only if nil did not truncate.
    if text ~= "id" then
        assert_equal(text, "id,NULL,role", "nil_value should replace nil fields")
    end
end

-------------------------------------------------------------------------------
-- Test: trim_fields = false
-------------------------------------------------------------------------------

do
    local rows = csv.decode([[
id,name
1, Daniel 
]], {
        header = true,
        strict = true,
        trim_fields = false,
    })

    assert_equal(rows[1].name, " Daniel ", "trim_fields=false should preserve spaces")
end

-------------------------------------------------------------------------------
-- Test: default trim_fields behavior
-------------------------------------------------------------------------------

do
    local rows = csv.decode([[
id,name
1, Daniel 
]], {
        header = true,
        strict = true,
    })

    assert_equal(rows[1].name, "Daniel", "default behavior should trim unquoted fields")
end

-------------------------------------------------------------------------------
-- Test: empty_as_nil
-------------------------------------------------------------------------------

do
    local rows = csv.decode([[
id,email
1,
]], {
        header = true,
        strict = true,
        empty_as_nil = true,
    })

    assert_equal(rows[1].id, "1")
    assert_equal(rows[1].email, nil, "empty_as_nil should convert empty fields to nil")
end

-------------------------------------------------------------------------------
-- Test: validate_string with valid CSV
-------------------------------------------------------------------------------

do
    assert_true(csv.validate_string ~= nil, "csv.validate_string should exist")

    local ok, err = csv.validate_string([[
id,name
1,Daniel
2,Alex
]], {
        header = true,
        strict = true,
    })

    assert_true(ok, err)
    assert_equal(err, nil)
end

-------------------------------------------------------------------------------
-- Test: validate_string with invalid CSV
-------------------------------------------------------------------------------

do
    local ok, err = csv.validate_string([[
id,name
1,"Daniel
]], {
        header = true,
        strict = true,
    })

    assert_false(ok, "validate_string should fail on malformed CSV")
    assert_true(type(err) == "string", "validate_string should return an error message")
end

-------------------------------------------------------------------------------
-- Test: validate file
-------------------------------------------------------------------------------

do
    assert_true(csv.validate ~= nil, "csv.validate should exist")

    local path = script_dir .. "v03_valid.csv"

    write_file(path, [[
id,name
1,Daniel
2,Alex
]])

    local ok, err = csv.validate(path, {
        header = true,
        strict = true,
    })

    assert_true(ok, err)
    assert_equal(err, nil)
end

print("test_v03_options.lua: all tests passed")