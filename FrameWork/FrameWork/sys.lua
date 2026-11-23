local ffi = require("ffi")
local registry = require("registry")
local win = require("_win_extension")
local k = win.kernel
local M = {}

ffi.cdef[[
typedef struct {
    uint16_t architecture, reserved;
    uint32_t pageSize;
    void *minimumAddress, *maximumAddress;
    uintptr_t activeMask;
    uint32_t processorCount, processorType, allocationGranularity;
    uint16_t level, revision;
} fw_sys_system_info;
void __stdcall fw_sys_GetNativeSystemInfo(fw_sys_system_info *) __asm__("GetNativeSystemInfo");
uint32_t __stdcall GetActiveProcessorCount(uint16_t);
int __stdcall GetUserDefaultLocaleName(uint16_t *, int);
typedef struct { uint32_t size, tick; } fw_sys_last_input;
int __stdcall fw_sys_GetLastInputInfo(fw_sys_last_input *) __asm__("GetLastInputInfo");
]]

local architectures = {[0] = "x86", [5] = "arm", [9] = "x64", [12] = "arm64"}

function M.GetProcessorInfo()
    local count = k.GetActiveProcessorCount(0xFFFF)
    if count == 0 then return win.Error("GetActiveProcessorCount") end
    local info = ffi.new("fw_sys_system_info[1]")
    k.fw_sys_GetNativeSystemInfo(info)
    local name = registry.Read("HKLM\\HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", "ProcessorNameString")
    return {
        architecture = architectures[info[0].architecture] or "unknown",
        logicalProcessors = tonumber(count),
        level = tonumber(info[0].level),
        revision = tonumber(info[0].revision),
        pageSize = tonumber(info[0].pageSize),
        name = type(name) == "string" and name or nil
    }
end

function M.GetIdleTime()
    local user, err, code = win.Library("user32")
    if not user then return nil, err, code end
    local info = ffi.new("fw_sys_last_input[1]")
    info[0].size = ffi.sizeof(info[0])
    if user.fw_sys_GetLastInputInfo(info) == 0 then return win.Error("GetLastInputInfo", 31) end
    local now = tonumber(ffi.cast("uint32_t", k.GetTickCount64()))
    return (now - tonumber(info[0].tick)) % 4294967296
end

function M.GetLocale()
    local name = ffi.new("uint16_t[85]")
    local count = k.GetUserDefaultLocaleName(name, 85)
    if count == 0 then return win.Error("GetUserDefaultLocaleName") end
    return win.FromWide(name, count - 1)
end

return M
