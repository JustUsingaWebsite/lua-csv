-- csv/buffer.lua
-- Streaming file buffer. Lets the parser search/sub strings while reading from
-- disk in chunks instead of loading the entire CSV into memory.

local DEFAULT_BUFFER_BLOCK_SIZE = 1024 * 1024

---@class CsvFileBuffer
---@field file file*?
---@field buffer_block_size integer
---@field buffer_start integer
---@field buffer string
local file_buffer = {}
file_buffer.__index = file_buffer

---@param file file*
---@param buffer_block_size integer?
---@return CsvFileBuffer
function file_buffer.new(file, buffer_block_size)
    return setmetatable({
        file = file,
        buffer_block_size = buffer_block_size or DEFAULT_BUFFER_BLOCK_SIZE,
        buffer_start = 0,
        buffer = "",
    }, file_buffer)
end

---Drop already-consumed bytes from the front of the buffer.
---@param p integer Absolute parser position.
function file_buffer:truncate(p)
    p = p - self.buffer_start

    if p > self.buffer_block_size then
        local remove =
            self.buffer_block_size *
            math.floor((p - 1) / self.buffer_block_size)

        self.buffer = self.buffer:sub(remove + 1)
        self.buffer_start = self.buffer_start + remove
    end
end

---Find a Lua pattern, extending the buffer from disk until found or EOF.
---@param pattern string
---@param init integer
---@return integer?, integer?, string?
function file_buffer:find(pattern, init)
    while true do
        local first, last, capture =
            self.buffer:find(pattern, init - self.buffer_start)

        if not first or last == #self.buffer then
            local s = self.file and self.file:read(self.buffer_block_size)

            if not s then
                if not first then
                    return
                end

                return first + self.buffer_start,
                    last + self.buffer_start,
                    capture
            end

            self.buffer = self.buffer .. s
        else
            return first + self.buffer_start,
                last + self.buffer_start,
                capture
        end
    end
end

---Ensure buffer contains bytes up to the requested absolute offset.
---@param offset integer
function file_buffer:extend(offset)
    local extra = offset - #self.buffer - self.buffer_start

    if extra > 0 then
        local size =
            self.buffer_block_size *
            math.ceil(extra / self.buffer_block_size)

        local s = self.file and self.file:read(size)

        if not s then
            return
        end

        self.buffer = self.buffer .. s
    end
end

---Substring using absolute parser positions.
---@param a integer
---@param b integer
---@return string
function file_buffer:sub(a, b)
    self:extend(b)

    b = b == -1 and b or b - self.buffer_start

    return self.buffer:sub(a - self.buffer_start, b)
end

function file_buffer:close()
    if self.file then
        self.file:close()
        self.file = nil
    end
end

return file_buffer
