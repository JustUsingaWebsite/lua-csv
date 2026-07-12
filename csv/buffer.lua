-- csv/buffer.lua
-- Streaming file buffer. Lets the parser search/sub strings while reading from
-- disk in chunks instead of loading the entire CSV into memory.
--
-- Luau rewrite: uses Luau's built-in `buffer` type for mutable byte storage.
-- This eliminates O(n^2) string concatenation and reduces GC pressure when
-- reading large CSV files in chunks.

local DEFAULT_BUFFER_BLOCK_SIZE = 1024 * 1024

local sfind, ssub = string.find, string.sub

---@class CsvFileBuffer
---@field file file*?
---@field buffer_block_size integer
---@field buffer_start integer
---@field buf buffer  -- Luau mutable byte buffer
---@field len integer -- logical data length in buf
local file_buffer = {}
file_buffer.__index = file_buffer

---@param file file*
---@param buffer_block_size integer?
---@return CsvFileBuffer
function file_buffer.new(file, buffer_block_size)
    return setmetatable({
        file = file,
        buffer_block_size = buffer_block_size or DEFAULT_BUFFER_BLOCK_SIZE,
        buf = buffer.create(0),
        len = 0,
        buffer_start = 0,
    }, file_buffer)
end

---Grow the internal Luau buffer to accommodate at least `needed` total bytes.
---@param needed integer
function file_buffer:_grow(needed)
    local cap = buffer.len(self.buf)

    if needed <= cap then
        return
    end

    -- Amortized growth: double or use needed, whichever is larger
    local newSize = math.max(needed, cap * 2)
    local newBuf = buffer.create(newSize)

    if self.len > 0 then
        buffer.copy(newBuf, 0, self.buf, 0, self.len)
    end

    self.buf = newBuf
end

---Append a string to the internal buffer without creating intermediate strings.
---@param s string
function file_buffer:appendString(s)
    local slen = #s
    local newLen = self.len + slen

    self:_grow(newLen)
    buffer.writestring(self.buf, self.len, s)
    self.len = newLen
end

---Drop already-consumed bytes from the front of the buffer.
---Uses buffer.copy to shift data in-place — no new string allocation.
---@param p integer Absolute parser position.
function file_buffer:truncate(p)
    p = p - self.buffer_start

    if p > self.buffer_block_size then
        local remove =
            self.buffer_block_size *
            math.floor((p - 1) / self.buffer_block_size)

        local remaining = self.len - remove

        if remaining > 0 then
            -- Copy remaining bytes to the front of the buffer in-place
            buffer.copy(self.buf, 0, self.buf, remove, remaining)
        end

        self.len = remaining
        self.buffer_start = self.buffer_start + remove
    end
end

---Get the current buffer content as a Lua string.
---Only returns the logical length, not the full allocated capacity.
---@return string
function file_buffer:_asString()
    return buffer.readstring(self.buf, 0, self.len)
end

---Find a Lua pattern, extending the buffer from disk until found or EOF.
---@param pattern string
---@param init integer
---@return integer?, integer?, string?
function file_buffer:find(pattern, init)
    while true do
        local str = self:_asString()

        local first, last, capture =
            sfind(str, pattern, init - self.buffer_start)

        if not first or last == self.len then
            local s = self.file and self.file:read(self.buffer_block_size)

            if not s then
                if not first then
                    return
                end

                return first + self.buffer_start,
                    last + self.buffer_start,
                    capture
            end

            self:appendString(s)
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
    local extra = offset - self.len - self.buffer_start

    if extra > 0 then
        local size =
            self.buffer_block_size *
            math.ceil(extra / self.buffer_block_size)

        local s = self.file and self.file:read(size)

        if not s then
            return
        end

        self:appendString(s)
    end
end

---Substring using absolute parser positions.
---@param a integer
---@param b integer
---@return string
function file_buffer:sub(a, b)
    self:extend(b)

    b = b == -1 and b or b - self.buffer_start

    return ssub(self:_asString(), a - self.buffer_start, b)
end

function file_buffer:close()
    if self.file then
        self.file:close()
        self.file = nil
    end
end

return file_buffer
