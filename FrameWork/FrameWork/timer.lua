local ffi = require("ffi")
local errors = require("_errors")

ffi.cdef [[
int __stdcall QueryPerformanceCounter(int64_t *lpPerformanceCount);
int __stdcall QueryPerformanceFrequency(int64_t *lpFrequency);
unsigned long long __stdcall GetTickCount64(void);
void __stdcall Sleep(unsigned long);
unsigned long __stdcall GetLastError(void);
]]

local kernel32 = ffi.load("kernel32")

local timer = {}

local freq = ffi.new("int64_t[1]")
local counter = ffi.new("int64_t[1]")

assert(kernel32.QueryPerformanceFrequency(freq) ~= 0, "QueryPerformanceFrequency failed")

local frequency = tonumber(freq[0])
local started = nil
local decimals = nil

local function readCounter()
    if kernel32.QueryPerformanceCounter(counter) == 0 then
        return errors.Win32("QueryPerformanceCounter", tonumber(kernel32.GetLastError()))
    end
    return tonumber(counter[0])
end

function timer.Start(precision)
    if precision ~= nil and (type(precision) ~= "number" or precision < 0
        or precision == math.huge or precision ~= math.floor(precision)) then
        return nil, "Точность должна быть конечным неотрицательным целым числом или nil"
    end
    local value, err, code = readCounter()
    if value == nil then return nil, err, code end
    started = value
    decimals = precision
    return true
end

local scheduled = {}
local timerHandles = setmetatable({}, {__mode = "k"})

function timer.Now()
    local value, err, code = readCounter()
    if value == nil then return nil, err, code end
    return value / frequency
end

function timer.Ticks()
    return tonumber(kernel32.GetTickCount64())
end

function timer.Sleep(ms)
    if type(ms) ~= "number" or not (ms >= 0 and ms < 0xFFFFFFFF and ms % 1 == 0) then
        return nil, "Недопустимая длительность ожидания"
    end
    kernel32.Sleep(ms)
    return true
end

local function schedule(ms, callback, repeatTimer)
    if type(ms) ~= "number" or not (ms >= (repeatTimer and 1 or 0) and ms < 0xFFFFFFFF and ms % 1 == 0) then
        return nil, "Недопустимый интервал таймера"
    end
    if type(callback) ~= "function" then return nil, "Требуется обработчик таймера" end
    local now, err, code = timer.Now()
    if now == nil then return nil, err, code end
    local handle = {}
    local entry = {due = now + ms / 1000, interval = repeatTimer and ms / 1000, callback = callback}
    timerHandles[handle], scheduled[handle] = true, entry
    return handle
end

function timer.SetTimeout(ms, callback) return schedule(ms, callback, false) end
function timer.SetInterval(ms, callback) return schedule(ms, callback, true) end

function timer.Poll()
    local now, err, code = timer.Now()
    if now == nil then return nil, err, code end
    local ready, count = {}, 0
    for handle, entry in pairs(scheduled) do
        if entry.due <= now then ready[#ready + 1] = handle end
    end
    for _, handle in ipairs(ready) do
        local entry = scheduled[handle]
        if entry and entry.due <= now then
            if not entry.interval then scheduled[handle] = nil end
            entry.due = math.huge
            local ok, message = pcall(entry.callback, handle)
            if not ok then scheduled[handle] = nil; return errors.Callback("Timer callback", message) end
            if entry.interval and scheduled[handle] then
                local nextTime, reason, status = timer.Now()
                if nextTime == nil then scheduled[handle] = nil; return nil, reason, status end
                entry.due = nextTime + entry.interval
            end
            count = count + 1
        end
    end
    return count
end

function timer.Stop(handle)
    if handle ~= nil then
        if not timerHandles[handle] then return nil, "invalid timer handle" end
        scheduled[handle] = nil
        return true
    end
    if not started then
        return nil, "timer.Start() was not called"
    end

    local finished, err, code = readCounter()
    if finished == nil then return nil, err, code end
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
Пример испоьзования:
local timer = require("timer")
timer.Start(2)

for i = 1, 1000000 do
end

local ms = timer.Stop()
print(ms, "ms")
]]
