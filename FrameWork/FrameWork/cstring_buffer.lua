-- Fixed-capacity byte buffers for NUL-terminated C strings.
-- Capacity includes the terminating NUL. This module does not validate UTF-8.
-- This is char[] storage, not WCHAR[] / UTF-16. Do not pass it as a
-- writable output buffer to Windows W APIs; allocate WCHAR[] separately.
local ffi = require("ffi")
ffi.cdef[[void *memchr(const void *ptr, int value, size_t count);]]
local M = {}

function M.New(size)
    if type(size) ~= "number" or size ~= math.floor(size) or size < 1 or size > 2147483647 then
        return nil, "buffer size must be an integer from 1 to 2147483647"
    end

    local ok, data = pcall(ffi.new, "char[?]", size)
    if not ok then
        return nil, tostring(data)
    end

    return {
        data = data,
        size = size,

        Set = function(self, text)
            if type(text) ~= "string" then
                return nil, "expected a string"
            end

            if text:find("\0", 1, true) then
                return nil, "embedded NUL is not allowed in a C string"
            end

            if #text >= size then
                return nil, "string does not fit in buffer (including NUL)"
            end

            ffi.copy(data, text, #text)
            data[#text] = 0
            return self
        end,

        ToString = function(self)
            -- Bound the scan even when native code has overwritten the NUL.
            local nul = ffi.C.memchr(data, 0, size)

            if nul == nil then
                return nil, "buffer is not NUL-terminated"
            end

            return ffi.string(data, tonumber(ffi.cast("const char *", nul) - data))
        end
    }
end

return M
