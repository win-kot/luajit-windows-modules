local win = require("_win_extension")
local ffi = require("ffi")
local M = {}
local space = 9007199254740992 -- 2^53
local uintSpace = 9007199254740992ULL

local function secureSample()
    local bytes, err, code = require("crypto").RandomBytes(7)
    if not bytes then return nil, err, code end
    local first, b, c, d, e, f, g = bytes:byte(1, 7)
    return (first % 32) * 281474976710656 + b * 1099511627776 + c * 4294967296 +
        d * 16777216 + e * 65536 + f * 256 + g
end

local function integer(sample, minimum, maximum)
    if not win.Integer(minimum, 1 - space, space - 1) or
        not win.Integer(maximum, minimum, space - 1) or maximum - minimum >= space then
        return win.Error("Invalid random integer range", 87)
    end
    if minimum == maximum then return minimum end
    local width = ffi.cast("uint64_t", maximum - minimum) + 1ULL
    local limit = uintSpace - uintSpace % width
    while true do
        local value, err, code = sample()
        if value == nil then return nil, err, code end
        local candidate = ffi.cast("uint64_t", value)
        if candidate < limit then return minimum + tonumber(candidate % width) end
    end
end

local function ordinarySample()
    -- Three independent draws avoid relying on math.random's handling of wide integer bounds.
    local high = math.random(0, 2097151)
    local middle = math.random(0, 65535)
    local low = math.random(0, 65535)
    return high * 4294967296 + middle * 65536 + low
end

function M.Number()
    return math.random()
end

function M.Integer(minimum, maximum)
    return integer(ordinarySample, minimum, maximum)
end

function M.SecureNumber()
    local value, err, code = secureSample()
    if value == nil then return nil, err, code end
    return value / space
end

function M.SecureInteger(minimum, maximum)
    return integer(secureSample, minimum, maximum)
end

return M
