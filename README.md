# lua-csv

Fast CSV reader/writer optimized for Luau through Lune.

`lua-csv` supports CSV parsing, header rows, strict validation, embedded quoted newlines, UTF-8 BOM stripping, UTF-16LE/UTF-16BE decoding, custom single-character separators, CSV validation, and CSV encoding/writing.

## Features

- Fast single-pass CSV reader for UTF-8 strings and Lune file input
- CSV writer and encoder
- Header-based row access
- Strict validation mode
- CSV validation helpers
- Embedded newlines inside quoted fields
- Escaped quote handling
- UTF-8 BOM stripping
- UTF-16LE and UTF-16BE input support
- Encoding auto-detection
- CRLF, LF, and CR line endings
- Custom separators: comma, tab, pipe, semicolon, etc.
- Optional field trimming
- Optional empty-field-to-nil conversion
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
│   ├── types.lua
│   ├── unicode.lua
│   ├── util.lua
│   └── validate.lua
└── main.lua
````

Then require it:

```lua
local csv = require("csv")
```

If Lua cannot find the module, add your project root to `package.path`:

```lua
package.path = "./?.lua;./?/init.lua;" .. package.path
```

### Running with Lune

When using [Lune](https://lune-org.github.io), requires are file-relative:

```lua
local csv = require("./csv")
-- or from a subdirectory:
local csv = require("../csv")
```

Run scripts from the project root:

```bash
lune run main.lua
```

> **Important:** Lune resolves file paths relative to your current working directory, not the script location. Always run from the project root so that temp files and fixtures are written to the expected locations.

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

## Validate CSV

Validate a file:

```lua
local csv = require("csv")

local ok, err = csv.validate("users.csv", {
    header = true,
    strict = true,
})

if not ok then
    print("Invalid CSV:", err)
end
```

Validate a string:

```lua
local csv = require("csv")

local ok, err = csv.validate_string([[
id,name
1,Daniel
2,Alex
]], {
    header = true,
    strict = true,
})

if not ok then
    print("Invalid CSV:", err)
end
```

## Encoding

`lua-csv` supports UTF-8 by default and can decode UTF-16LE or UTF-16BE input before parsing.

```lua
local csv = require("csv")

local file = assert(csv.open("excel_export.csv", {
    encoding = "auto",
    header = true,
    strict = true,
}))

for row in file:lines() do
    print(row.id, row.name)
end

file:close()
```

Supported encoding values:

```lua
encoding = "auto"
encoding = "utf-8"
encoding = "utf-16le"
encoding = "utf-16be"
```

When running under Lune, files are read with `@lune/fs.readFile` and then parsed from memory. UTF-16 files are decoded into UTF-8 in memory before parsing.

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

## Useful Options

### Quote all written fields

```lua
local csv = require("csv")

local text = csv.encode({
    { "id", "name" },
    { 1, "Daniel" },
}, {
    quote_all = true,
    newline = "\n",
})

print(text)
```

Output:

```csv
"id","name"
"1","Daniel"
```

### Preserve unquoted spaces

By default, unquoted fields are trimmed.

```lua
local csv = require("csv")

local rows = csv.decode("id,name\n1, Daniel \n", {
    header = true,
    trim_fields = false,
})

print(rows[1].name) -- " Daniel "
```

### Convert empty fields to nil

```lua
local csv = require("csv")

local rows = csv.decode("id,email\n1,\n", {
    header = true,
    empty_as_nil = true,
})

print(rows[1].email) -- nil
```

### Select only some columns

Use `select` to return only the columns your script needs. With `header = true`, pass header names. Without headers, pass physical column indexes.

```lua
local csv = require("csv")

local rows = csv.decode("id,name,email,role\n1,Daniel,d@example.com,Admin\n", {
    header = true,
    select = { "id", "role" },
})

print(rows[1].id, rows[1].role)
print(rows[1].name) -- nil
```

### Return field positions

By default the reader only returns row data. Enable `positions` when you need the starting line and column for each field.

```lua
local csv = require("csv")

local file = csv.openstring("id,name\n1,Daniel\n", {
    header = true,
    positions = true,
})

local row, starts = file:read()

print(row.name) -- "Daniel"
print(starts.name.line, starts.name.column) -- 2, 3
```

### Reuse row tables

For high-throughput iteration, `reuse_record` reuses the same row table between reads. Do not store rows from `file:lines()` or `file:read()` when this is enabled unless you copy them first. `readall()` copies rows before storing them.

```lua
local csv = require("csv")

local file = csv.open("users.csv", {
    header = true,
    reuse_record = true,
})

for row in file:lines() do
    print(row.id, row.name)
end
```

## API

### Reading

```lua
csv.open(filename, parameters)       -- open CSV file
csv.openstring(text, parameters)     -- open CSV from string
csv.decode(text, parameters)         -- decode CSV string into rows
csv.validate(filename, parameters)   -- validate CSV file
csv.validate_string(text, parameters) -- validate CSV string
```

### Reader methods

```lua
file:lines()    -- iterator over rows, plus positions when positions=true
file:read()     -- read one row, plus positions when positions=true
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
    encoding = "auto",            -- "auto", "utf-8", "utf-16le", or "utf-16be"

    header = true,                -- use first row as keys
    strict = true,                -- validate field counts
    skip_blank_lines = true,      -- skip blank rows
    duplicate_headers = "error",  -- error on duplicate headers
    record_limit = nil,           -- optional max rows to read
    select = nil,                  -- optional header names or column indexes
    positions = false,            -- return field start metadata
    reuse_record = false,         -- reuse row table during iteration

    newline = "\r\n",             -- writer newline
    quote_all = false,            -- writer: quote every field
    nil_value = "",               -- writer: replacement for nil values

    columns = nil,                -- optional column mapping
    trim_fields = true,           -- reader: trim unquoted fields
    empty_as_nil = false,         -- reader: convert empty fields to nil
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
* UTF-16LE and UTF-16BE input are supported.
* UTF-16 input is decoded into UTF-8 before parsing.
* Lune file input is read into memory with `@lune/fs.readFile`.
* Multi-character separators are not supported.
* `select` reduces returned columns, but the parser still scans all fields to preserve CSV correctness and strict validation.
* Rows are returned as strings unless transformed through `columns`.
* The parser uses coroutines internally for streaming iteration.
* `file:lines()` and `file:read()` return field position metadata only when `positions = true`.
* When running under Lune, file I/O uses `@lune/fs` and stdin uses `@lune/stdio`. Standard Lua fallbacks read `io` handles into memory before parsing.

## Supported Lua Versions

* Luau (via [Lune](https://lune-org.github.io))
* Lua 5.1-5.4 and LuaJIT are compatibility targets, but this branch is optimized and tested primarily on Lune.

