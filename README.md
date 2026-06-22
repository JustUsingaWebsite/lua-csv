# lua-csv (Modernized Fork)

Fast streaming CSV reader/writer for Lua 5.1–5.4 and LuaJIT.

Supports:

* CSV
* TSV
* Pipe-delimited
* Semicolon-delimited
* Custom single-character separators
* Embedded newlines inside quoted fields
* UTF-8 BOM stripping
* Streaming large files
* CSV writing/encoding
* Strict validation mode

***

# Installation

Put `csv.lua` beside your script.

Example:

```text
project/
  csv.lua
  test.lua
```

Then in Lua:

```lua
local csv = require("csv")
```

If Lua cannot find the module, add this before `require()`:

```lua
local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("^(.*[\\/])") or ""

package.path = script_dir .. "?.lua;" ..
               script_dir .. "?\\init.lua;" ..
               package.path
```

***

# Quick Start

## Read CSV

```lua
local csv = require("csv")

local f = csv.open("users.csv")

for row in f:lines() do
    print(row[1], row[2], row[3])
end

f:close()
```

***

## Read CSV with headers

CSV:

```csv
id,name,email
1,Dunkan,dunkan@example.com
```

Lua:

```lua
local csv = require("csv")

local f = csv.open("users.csv", {
    header = true
})

for row in f:lines() do
    print(row.id)
    print(row.name)
    print(row.email)
end

f:close()
```

***

# API

***

# `csv.open(filename, parameters)`

Open a CSV file from disk.

## Example

```lua
local f = csv.open("data.csv")
```

## Parameters

```lua
{
    separator = ",",
    header = true,
    strict = true,
    skip_blank_lines = true,
    duplicate_headers = "error",
    buffer_size = 1024 * 1024,
}
```

***

# `csv.openstring(contents, parameters)`

Open CSV from a Lua string.

## Example

```lua
local f = csv.openstring([[
id,name
1,Daniel
2,Alex
]], {
    header = true
})
```

***

# `csv.use(buffer, parameters)`

Use an existing buffer/file-like object.

Advanced/internal usage.

***

# Reader Methods

***

# `f:lines()`

Iterator over CSV rows.

## Example

```lua
for row in f:lines() do
    print(row[1])
end
```

***

# `f:read()`

Read a single row.

Returns `nil` at EOF.

## Example

```lua
local row = f:read()

if row then
    print(row[1])
end
```

***

# `f:readall()`

Read entire CSV into memory.

## Example

```lua
local rows = f:readall()

for i, row in ipairs(rows) do
    print(row[1])
end
```

***

# `f:close()`

Close the file.

## Example

```lua
f:close()
```

***

# Decode API

***

# `csv.decode(string, parameters)`

Decode CSV string directly into rows.

## Example

```lua
local rows = csv.decode([[
id,name
1,Daniel
]], {
    header = true
})

print(rows[1].name)
```

***

# Writer API

***

# `csv.encode(rows, parameters)`

Convert Lua tables into CSV text.

## Example

```lua
local csv_text = csv.encode({
    { "id", "name" },
    { 1, "Daniel" },
    { 2, "Alex" },
})

print(csv_text)
```

***

# `csv.encode_row(row, parameters)`

Encode a single CSV row.

## Example

```lua
local row = csv.encode_row({
    "Daniel",
    'hello, "world"',
})

print(row)
```

Output:

```csv
Daniel,"hello, ""world"""
```

***

# `csv.writer(filename, parameters)`

Create CSV writer object.

## Example

```lua
local out = csv.writer("output.csv")

out:write({ "id", "name" })
out:write({ 1, "Daniel" })
out:write({ 2, "Alex" })

out:close()
```

***

# Writer Methods

***

# `writer:write(row)`

Write one CSV row.

## Example

```lua
writer:write({
    1,
    "Daniel",
    "Admin"
})
```

***

# `writer:close()`

Close writer file.

***

# Parameters

***

# `separator`

Default:

```lua
","
```

Supported examples:

```lua
separator = ","
separator = "\t"
separator = "|"
separator = ";"
```

Must be a single character.

***

# `header`

Treat first row as column names.

## Example

```lua
header = true
```

Then rows become:

```lua
row.email
row.first_name
```

instead of:

```lua
row[1]
row[2]
```

***

# `strict`

Enable stricter CSV validation.

Checks:

* consistent field counts
* malformed quoted fields
* unexpected characters after quotes

## Example

```lua
strict = true
```

***

# `skip_blank_lines`

Default:

```lua
true
```

To preserve blank rows:

```lua
skip_blank_lines = false
```

***

# `duplicate_headers`

Default behavior:

* later duplicate overwrites earlier

Strict mode:

```lua
duplicate_headers = "error"
```

Example error:

```text
duplicate header: email
```

***

# `buffer_size`

Streaming read buffer size.

Default:

```lua
1024 * 1024
```

Example:

```lua
buffer_size = 8 * 1024 * 1024
```

***

# `columns`

Column mapping / transforms.

## Example

CSV:

```csv
First Name,Age
Daniel,30
```

Lua:

```lua
local f = csv.open("users.csv", {
    header = true,

    columns = {
        first_name = {
            name = "First Name"
        },

        age = {
            transform = tonumber
        }
    }
})
```

Result:

```lua
row.first_name
row.age
```

***

# Embedded Newlines

Supported.

Example CSV:

```csv
id,note
1,"hello
world"
```

Works correctly.

***

# Escaped Quotes

Supported.

CSV:

```csv
name,note
Dunkan,"hello ""world"""
```

Result:

```lua
hello "world"
```

***

# BOM Handling

Supported:

* UTF-8 BOM stripping

Rejected:

* UTF-16 BOMs

Reason:

This parser does not decode UTF-16.

***

# Supported Lua Versions

Tested with:

* Lua 5.1
* Lua 5.2
* Lua 5.3
* Lua 5.4
* LuaJIT

***

# Example Full Read

```lua
local csv = require("csv")

local f = csv.open("sample.csv", {
    header = true,
    strict = true,
})

for row in f:lines() do
    print(
        row.user_id,
        row.first_name,
        row.last_name,
        row.email,
        row.role,
        row.is_active
    )
end

f:close()
```

***

# Example Full Write

```lua
local csv = require("csv")

local out = csv.writer("users.csv")

out:write({
    "user_id",
    "first_name",
    "email"
})

out:write({
    101,
    "Dunkan",
    "dunkan@example.com"
})

out:close()
```

***

# Notes

* Streaming parser designed for large files
* Handles CRLF, LF, and CR line endings
* Does NOT support true multi-character separators
* Does NOT decode UTF-16
* Uses Lua coroutines internally for iteration

***

# Funny Real-World CSV Survival Status

✅ Embedded newlines  
✅ Escaped quotes  
✅ Weird line endings  
✅ UTF-8 BOM  
✅ Large files  
✅ Pipe-delimited exports  
✅ Semicolon Excel exports  
✅ User-generated garbage CSVs  
✅ Corporate nonsense exports
