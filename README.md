# lua-csv

Fast streaming CSV reader/writer for Lua 5.1–5.4 and LuaJIT.

`lua-csv` supports CSV parsing, header rows, strict validation, embedded quoted newlines, UTF-8 BOM stripping, custom single-character separators, and CSV encoding/writing.

## Features

- Streaming CSV reader for large files
- CSV writer and encoder
- Header-based row access
- Strict validation mode
- Embedded newlines inside quoted fields
- Escaped quote handling
- UTF-8 BOM stripping
- CRLF, LF, and CR line endings
- Custom separators: comma, tab, pipe, semicolon, etc.
- LuaLS / EmmyLua annotations

## Installation

Copy `csv.lua` and the `csv/` folder into your project:

```text
project/
├── csv.lua
├── csv/
│   ├── buffer.lua
│   ├── column_map.lua
│   ├── encoder.lua
│   ├── parser.lua
│   ├── separator.lua
│   ├── unicode.lua
│   └── util.lua
└── main.lua
```

Then require it:

```lua
local csv = require("csv")
```

If Lua cannot find the module, add your project root to `package.path`.

```lua
package.path = "./?.lua;./?/init.lua;" .. package.path
```

## Quick Start

### Read a CSV file

```lua
local csv = require("csv")

local file = assert(csv.open("users.csv"))

for row in file:lines() do
    print(row[1], row[2], row[3])
end

file:close()
```

### Read with headers

```lua
local csv = require("csv")

local file = assert(csv.open("users.csv", {
    header = true,
    strict = true,
}))

for row in file:lines() do
    print(row.id, row.name, row.email)
end

file:close()
```

Example CSV:

```csv
id,name,email
1,Daniel,daniel@example.com
2,Alex,alex@example.com
```

## Decode CSV from a string

```lua
local csv = require("csv")

local rows = csv.decode([[
id,name,role
1,Daniel,Admin
2,Alex,Editor
]], {
    header = true,
    strict = true,
})

for _, row in ipairs(rows) do
    print(row.id, row.name, row.role)
end
```

## Encode CSV

```lua
local csv = require("csv")

local text = csv.encode({
    { "id", "name", "note" },
    { 1, "Daniel", 'hello, "world"' },
    { 2, "Lua", "line one\nline two" },
}, {
    newline = "\n",
})

print(text)
```

Output:

```csv
id,name,note
1,Daniel,"hello, ""world"""
2,Lua,"line one
line two"
```

## Write a CSV file

```lua
local csv = require("csv")

local writer = assert(csv.writer("output.csv"))

writer:write({ "id", "name", "email" })
writer:write({ 1, "Daniel", "daniel@example.com" })
writer:write({ 2, "Alex", "alex@example.com" })

writer:close()
```

## Column Mapping

Column mapping lets you map messy headers to cleaner Lua keys and optionally transform values.

```lua
local csv = require("csv")

local file = assert(csv.open("users.csv", {
    strict = true,

    columns = {
        user_id = {
            name = "User ID",
            transform = tonumber,
        },

        first_name = {
            name = "First Name",
        },

        active = {
            name = "Active",
            transform = function(value)
                return value == "true"
            end,
        },
    },
}))

for row in file:lines() do
    print(row.user_id, row.first_name, row.active)
end

file:close()
```

Example CSV:

```csv
User ID,First Name,Active
101,Daniel,true
102,Alex,false
```

## API

### Reading

```lua
csv.open(filename, parameters)      -- open CSV file
csv.openstring(text, parameters)    -- open CSV from string
csv.decode(text, parameters)        -- decode CSV string into rows
```

### Reader methods

```lua
file:lines()    -- iterator over rows
file:read()     -- read one row
file:readall()  -- read all rows into memory
file:close()    -- close file
file:name()     -- return filename
```

### Writing

```lua
csv.encode(rows, parameters)        -- encode rows into CSV text
csv.encode_row(row, parameters)     -- encode one row
csv.writer(filename, parameters)    -- create file writer
```

### Writer methods

```lua
writer:write(row)
writer:close()
```

## Parameters

```lua
{
    separator = ",",              -- single-character separator
    header = true,                -- use first row as keys
    strict = true,                -- validate field counts
    skip_blank_lines = true,      -- skip blank rows
    duplicate_headers = "error",  -- error on duplicate headers
    buffer_size = 1024 * 1024,    -- streaming buffer size
    record_limit = nil,           -- optional max rows to read
    newline = "\r\n",             -- writer newline
    columns = nil,                -- optional column mapping
}
```

<details>
<summary>Separator examples</summary>

```lua
separator = ","   -- CSV
separator = "\t"  -- TSV
separator = "|"   -- pipe-delimited
separator = ";"   -- semicolon-delimited
```

Separators must be a single character.

</details>

## Notes

* UTF-8 BOM is stripped automatically.
* UTF-16 BOMs are detected but rejected.
* Multi-character separators are not supported.
* Rows are returned as strings unless transformed through `columns`.
* The parser uses coroutines internally for streaming iteration.
* `file:lines()` yields row data and field position metadata internally.

## Supported Lua Versions

* Lua 5.1
* Lua 5.2
* Lua 5.3
* Lua 5.4
* LuaJIT
