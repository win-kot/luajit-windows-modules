local ffi = require("ffi")
local win = require("_win_extension")
local k = win.kernel
local M = {}
ffi.cdef[[
void *__stdcall OpenProcess(unsigned long, int, unsigned long);
]]

local function elevated(handle)
    local adv, err, code = win.Library("advapi32")
    if not adv then return nil, err, code end
    local token = ffi.new("void *[1]")
    if adv.OpenProcessToken(handle, 8, token) == 0 then return win.Error("OpenProcessToken") end
    local value, size = ffi.new("unsigned long[1]"), ffi.new("unsigned long[1]")
    local ok = adv.GetTokenInformation(token[0], 20, value, ffi.sizeof(value), size)
    code = ok == 0 and tonumber(k.GetLastError())
    k.CloseHandle(token[0])
    if ok == 0 then return win.Error("GetTokenInformation(TokenElevation)", code) end
    return value[0] ~= 0
end

function M.IsElevated() return elevated(k.GetCurrentProcess()) end
function M.UserSidGet() return win.UserSid() end

function M.ProcessElevationGet(pid)
    if not win.Integer(pid, 1, 0xFFFFFFFF) then return win.Error("Invalid PID", 87) end
    local handle = k.OpenProcess(0x1000, 0, pid)
    if handle == nil then return win.Error("OpenProcess") end
    local result, err, code = elevated(handle)
    k.CloseHandle(handle)
    return result, err, code
end
return M
