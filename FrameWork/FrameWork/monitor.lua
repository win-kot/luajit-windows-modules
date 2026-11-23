local ffi = require("ffi")
local win = require("_win_extension")
local user = ffi.load("user32")
local M = {}
ffi.cdef[[
typedef struct { int32_t left, top, right, bottom; } fw_monitor_rect;
typedef struct { int32_t x, y; } fw_monitor_point;
typedef struct {
    uint32_t size;
    fw_monitor_rect rect, work;
    uint32_t flags;
    uint16_t name[32];
} fw_monitor_info;
typedef int (__stdcall *fw_monitor_enum)(void *, void *, const fw_monitor_rect *, intptr_t);
int __stdcall EnumDisplayMonitors(void *, const fw_monitor_rect *, fw_monitor_enum, intptr_t);
int __stdcall fw_GetMonitorInfoW(void *, fw_monitor_info *) __asm__("GetMonitorInfoW");
void *__stdcall fw_MonitorFromWindow(void *, uint32_t) __asm__("MonitorFromWindow");
void *__stdcall MonitorFromPoint(fw_monitor_point, uint32_t);
int32_t __stdcall GetDpiForMonitor(void *, int, uint32_t *, uint32_t *);
int __stdcall IsWindow(void *);
void *__stdcall GetThreadDpiAwarenessContext(void);
int __stdcall GetAwarenessFromDpiAwarenessContext(void *);
]]
local function rect(r)
    return {left = r.left, top = r.top, right = r.right, bottom = r.bottom}
end

local function id(handle)
    return win.Exact(ffi.cast("uintptr_t", handle))
end

local function info(handle)
    local data = ffi.new("fw_monitor_info[1]")
    data[0].size = ffi.sizeof(data[0])
    if user.fw_GetMonitorInfoW(handle, data) == 0 then return win.Error("GetMonitorInfoW") end
    local name, err, code = win.FromWide(data[0].name)
    if not name then return nil, err, code end
    return {id = id(handle), primary = data[0].flags % 2 == 1, rect = rect(data[0].rect),
        work = rect(data[0].work), deviceName = name}
end

function M.ListGet()
    local handles = {}
    local callback = ffi.cast("fw_monitor_enum", function(handle)
        handles[#handles + 1] = handle
        return 1
    end)
    win.kernel.SetLastError(0)
    local ok = user.EnumDisplayMonitors(nil, nil, callback, 0)
    local code = ok == 0 and tonumber(win.kernel.GetLastError())
    callback:free()
    if ok == 0 then return win.Error("EnumDisplayMonitors", code == 0 and 31 or code) end
    local list = {}
    for i, handle in ipairs(handles) do
        local entry, err, status = info(handle)
        if not entry then return nil, err, status end
        list[i] = entry
    end
    return list
end
jit.off(M.ListGet, true)

function M.FromWindow(hwnd)
    if win.Integer(hwnd, 1, 9007199254740991) then hwnd = ffi.cast("void *", hwnd) end
    if type(hwnd) ~= "cdata" or not ffi.istype("void *", hwnd) or user.IsWindow(hwnd) == 0 then
        return win.Error("Invalid HWND", 1400)
    end
    local handle = user.fw_MonitorFromWindow(hwnd, 2)
    if handle == nil then return win.Error("MonitorFromWindow", 1461) end
    return id(handle)
end

function M.FromPoint(x, y)
    if not win.Integer(x, -2147483648, 2147483647) or not win.Integer(y, -2147483648, 2147483647) then
        return win.Error("Expected integer monitor coordinates", 87)
    end
    local handle = user.MonitorFromPoint(ffi.new("fw_monitor_point", x, y), 2)
    if handle == nil then return win.Error("MonitorFromPoint", 1461) end
    return id(handle)
end

function M.DpiGet(monitorId)
    local value
    if win.Integer(monitorId, 1, 9007199254740991) then
        value = monitorId
    elseif type(monitorId) == "string" and monitorId:match("^%d+$") and #monitorId <= 20 then
        value = 0ULL
        for digit in monitorId:gmatch(".") do
            local number = tonumber(digit)
            if value > (18446744073709551615ULL - number) / 10ULL then
                return win.Error("Invalid monitor ID", 87)
            end
            value = value * 10ULL + number
        end
    else
        return win.Error("Invalid monitor ID", 87)
    end
    local shcore, err, code = win.Library("shcore")
    if not shcore then return nil, err, code end
    local query = win.Symbol(shcore, "GetDpiForMonitor")
    if not query then return win.Error("GetDpiForMonitor", 127) end
    local dpi = ffi.new("uint32_t[2]")
    local handle = ffi.cast("void *", value)
    local status = query(handle, 0, dpi, dpi + 1)
    if status < 0 then
        return nil, ("GetDpiForMonitor (HRESULT 0x%08X)"):format(tonumber(ffi.cast("uint32_t", status))), status
    end
    local context = win.Symbol(user, "GetThreadDpiAwarenessContext")
    local awareness = win.Symbol(user, "GetAwarenessFromDpiAwarenessContext")
    -- Some Windows builds return the system DPI from shcore even for an unaware thread.
    if context and awareness and awareness(context()) == 0 then dpi[0], dpi[1] = 96, 96 end
    return {x = dpi[0], y = dpi[1], scaleX = dpi[0] / 96, scaleY = dpi[1] / 96}
end
return M
