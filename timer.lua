local ffi = require("ffi")

ffi.cdef [[
int __stdcall QueryPerformanceCounter(int64_t *lpPerformanceCount);
int __stdcall QueryPerformanceFrequency(int64_t *lpFrequency);
]]

local kernel32 = ffi.load("kernel32")

local timer = {}

local freq = ffi.new("int64_t[1]")
local counter = ffi.new("int64_t[1]")

assert(kernel32.QueryPerformanceFrequency(freq) ~= 0, "QueryPerformanceFrequency failed")

local frequency = tonumber(freq[0])
local started = nil
local decimals = nil

function timer.start(precision)
    if precision ~= nil and (type(precision) ~= "number" or precision < 0
        or precision == math.huge or precision ~= math.floor(precision)) then
        error("precision must be nil or a finite non-negative integer", 2)
    end
    kernel32.QueryPerformanceCounter(counter)

    started = tonumber(counter[0])
    decimals = precision
end

function timer.stop()
    if not started then
        return nil, "timer.start() was not called"
    end

    kernel32.QueryPerformanceCounter(counter)

    local finished = tonumber(counter[0])
    local elapsed = (finished - started) * 1000 / frequency

    started = nil

    if decimals ~= nil then
        local factor = 10 ^ decimals
        local scaled = elapsed * factor
        -- Very large precisions cannot improve double accuracy. Keep the
        -- measured value when scaling overflows instead of producing NaN/inf.
        if factor < math.huge and scaled < math.huge then
            elapsed = math.floor(scaled + 0.5) / factor
        end
    end

    decimals = nil

    return elapsed
end

return timer

--[[
Usage example:
local timer = require("timer")
timer.start(2)

for i = 1, 1000000 do
end

local ms = timer.stop()
print(ms, "ms")
]]
