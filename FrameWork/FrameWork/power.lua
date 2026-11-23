local ffi = require("ffi")
local win = require("_win_extension")
local k = win.kernel
local M = {}
ffi.cdef[[
unsigned long __stdcall SetThreadExecutionState(unsigned long);
]]

function M.KeepAwake(displayToo)
    if displayToo ~= nil and type(displayToo) ~= "boolean" then
        return win.Error("displayToo must be boolean", 87)
    end
    if k.SetThreadExecutionState(displayToo and 0x80000003 or 0x80000001) == 0 then
        return win.Error("SetThreadExecutionState", 31)
    end
    return true
end

function M.AllowSleep()
    if k.SetThreadExecutionState(0x80000000) == 0 then return win.Error("SetThreadExecutionState", 31) end
    return true
end
return M
