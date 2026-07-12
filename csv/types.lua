-- csv/types.lua
-- Shared LuaLS / EmmyLua type definitions for lua-csv.
-- This module exists mainly for annotations. It returns an empty table.

---@alias CsvDuplicateHeaderMode
---| '"error"'

---@class CsvParameters
---@field separator string? Single-character separator. Default: ","
---@field header boolean? Use first row as headers.
---@field strict boolean? Validate consistent field counts.
---@field skip_blank_lines boolean? Default true.
---@field duplicate_headers CsvDuplicateHeaderMode?
---@field buffer_size integer? Streaming buffer size.
---@field filename string?
---@field record_limit integer?
---@field columns table?
---@field column_map CsvColumnMap?
---@field newline string?
---@field quote_all boolean? Quote every written field.
---@field nil_value any Value used when writing nil fields. Default: "".
---@field trim_fields boolean? Trim unquoted fields. Default: true.
---@field empty_as_nil boolean? Convert empty fields to nil when reading.
---@field encoding '"auto"'|'"utf-8"'|'"utf-16le"'|'"utf-16be"'? Input encoding. Default: "auto".
---@field positions boolean? Return field position metadata as second iterator result. Default: false.
---@field reuse_record boolean? Reuse the same row table between iterator reads. Default: false.
---@field select (string|integer)[]? Return only these header names or physical column indexes.

---@class CsvFieldPosition
---@field line integer
---@field column integer

---@alias CsvRow table<any, string>

---@class CsvFile
---@field buffer any
---@field parameters CsvParameters
---@field _iterator function?
---@field lines fun(self: CsvFile): fun(): table?, table?
---@field read fun(self: CsvFile): table?, table?
---@field readall fun(self: CsvFile): table[]
---@field close fun(self: CsvFile)
---@field name fun(self: CsvFile): string

---@class CsvWriter
---@field filename string
---@field file file*?
---@field parameters CsvParameters
---@field chunks string[]
---@field write fun(self: CsvWriter, row: table)
---@field close fun(self: CsvWriter)

return {}
