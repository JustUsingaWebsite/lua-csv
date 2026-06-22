require("csv.types")

local parser = require("csv.parser")
local encoder = require("csv.encoder")

local csv = {
    open = parser.open,
    openstring = parser.openstring,
    use = parser.use,
    decode = parser.decode,

    encode = encoder.encode,
    encode_row = encoder.encode_row,
    writer = encoder.writer,
}

return csv
