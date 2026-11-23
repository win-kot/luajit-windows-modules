local ffi = require("ffi")
local win = require("_win_extension")
local k = win.kernel
local M = {}
ffi.cdef[[
typedef struct {
    uint32_t type, state, controls, win32ExitCode, serviceExitCode, checkPoint, waitHintMs, pid, flags;
} fw_service_status;
typedef struct {
    const uint16_t *name, *displayName;
    fw_service_status status;
} fw_service_entry;
void *__stdcall OpenSCManagerW(const uint16_t *, const uint16_t *, unsigned long);
void *__stdcall OpenServiceW(void *, const uint16_t *, unsigned long);
int __stdcall CloseServiceHandle(void *);
int __stdcall EnumServicesStatusExW(void *, int, unsigned long, unsigned long, void *,
    unsigned long, unsigned long *, unsigned long *, unsigned long *, const uint16_t *);
int __stdcall QueryServiceStatusEx(void *, int, void *, unsigned long, unsigned long *);
int __stdcall StartServiceW(void *, unsigned long, const uint16_t **);
int __stdcall ControlService(void *, unsigned long, void *);
]]
local states = {"stopped", "startPending", "stopPending", "running", "continuePending", "pausePending", "paused"}

local function statusFrom(info)
    return {
        state = states[info.state] or "unknown", stateCode = info.state,
        type = info.type, controls = info.controls, win32ExitCode = info.win32ExitCode,
        serviceExitCode = info.serviceExitCode, checkPoint = info.checkPoint,
        waitHintMs = info.waitHintMs, pid = info.pid, flags = info.flags
    }
end

local function manager(adv, access)
    local handle = adv.OpenSCManagerW(nil, nil, access)
    if handle == nil then return win.Error("OpenSCManagerW") end
    return ffi.gc(handle, adv.CloseServiceHandle)
end

local function close(adv, handle)
    if adv.CloseServiceHandle(handle) == 0 then return win.Error("CloseServiceHandle") end
    ffi.gc(handle, nil)
    return true
end

local function enumerate(adv, scm)
    local capacity = 65536
    local buffer = ffi.new("uint8_t[?]", capacity)
    local count, needed, resume = ffi.new("unsigned long[1]"), ffi.new("unsigned long[1]"), ffi.new("unsigned long[1]")
    local result = {}
    while true do
        local previous = resume[0]
        local ok = adv.EnumServicesStatusExW(scm, 0, 0x30, 3, buffer, capacity, needed, count, resume, nil)
        local code = ok == 0 and tonumber(k.GetLastError())
        if ok == 0 and code ~= 234 then return win.Error("EnumServicesStatusExW", code) end
        local rows = ffi.cast("fw_service_entry *", buffer)
        for index = 0, count[0] - 1 do
            local entry = statusFrom(rows[index].status)
            local name, err, status = win.FromWide(rows[index].name)
            if not name then return nil, err, status end
            local title
            title, err, status = win.FromWide(rows[index].displayName)
            if not title then return nil, err, status end
            entry.name, entry.displayName = name, title
            result[#result + 1] = entry
        end
        if ok ~= 0 then return result end
        local nextCapacity = math.min(262144, math.max(capacity, needed[0]))
        if nextCapacity > capacity then
            capacity = nextCapacity
            buffer = ffi.new("uint8_t[?]", capacity)
        elseif resume[0] == previous or resume[0] == 0 then
            return win.Error("EnumServicesStatusExW did not advance", 234)
        end
    end
end

function M.ListGet()
    local adv, err, code = win.Library("advapi32")
    if not adv then return nil, err, code end
    local scm
    scm, err, code = manager(adv, 4)
    if not scm then return nil, err, code end
    local result
    result, err, code = enumerate(adv, scm)
    local closed, closeError, closeCode = close(adv, scm)
    if result and not closed then return nil, closeError, closeCode end
    return result, err, code
end

local function withService(name, access, action)
    if type(name) ~= "string" or name == "" or name:find("[/\\]") then
        return win.Error("Invalid service name", 87)
    end
    local wide, units, code = win.ToWide(name)
    if not wide then return nil, units, code end
    if units > 256 then return win.Error("Service name exceeds 256 UTF-16 units", 206) end
    local err
    local adv
    adv, err, code = win.Library("advapi32")
    if not adv then return nil, err, code end
    local scm
    scm, err, code = manager(adv, 1)
    if not scm then return nil, err, code end
    local service = adv.OpenServiceW(scm, wide, access)
    code = service == nil and tonumber(k.GetLastError())
    if service ~= nil then ffi.gc(service, adv.CloseServiceHandle) end
    close(adv, scm)
    if service == nil then return win.Error("OpenServiceW", code) end
    local result
    result, err, code = action(adv, service)
    local closed, closeError, closeCode = close(adv, service)
    if result ~= nil and not closed then return nil, closeError, closeCode end
    return result, err, code
end

local function query(adv, service)
    local data, needed = ffi.new("fw_service_status[1]"), ffi.new("unsigned long[1]")
    if adv.QueryServiceStatusEx(service, 0, data, ffi.sizeof(data), needed) == 0 then
        return win.Error("QueryServiceStatusEx")
    end
    return statusFrom(data[0])
end

function M.StatusGet(name)
    return withService(name, 4, query)
end

local function waitFor(adv, service, target, timeout)
    local deadline = tonumber(k.GetTickCount64()) + timeout
    while true do
        local status, err, code = query(adv, service)
        if not status then return nil, err, code end
        if status.stateCode == target then return status end
        if target == 4 and status.stateCode == 1 then
            code = status.win32ExitCode ~= 0 and status.win32ExitCode or 1067
            local action = "Service stopped during startup"
            if code == 1066 then action = action .. " (service exit " .. status.serviceExitCode .. ")" end
            return win.Error(action, code)
        end
        local left = deadline - tonumber(k.GetTickCount64())
        if left <= 0 then return false, status end
        local delay = math.max(50, math.min(500, math.floor(status.waitHintMs / 10)))
        k.Sleep(math.min(left, delay))
    end
end

function M.Start(name, timeoutMs)
    local timeout, err, code = win.Timeout(timeoutMs, 10000)
    if not timeout then return nil, err, code end
    return withService(name, 0x14, function(adv, service)
        local status, err, code = query(adv, service)
        if not status then return nil, err, code end
        if status.stateCode == 4 then return status end
        if status.stateCode ~= 2 and adv.StartServiceW(service, 0, nil) == 0 then
            code = tonumber(k.GetLastError())
            if code ~= 1056 then return win.Error("StartServiceW", code) end
        end
        return waitFor(adv, service, 4, timeout)
    end)
end

function M.Stop(name, timeoutMs)
    local timeout, err, code = win.Timeout(timeoutMs, 10000)
    if not timeout then return nil, err, code end
    return withService(name, 0x24, function(adv, service)
        local status, err, code = query(adv, service)
        if not status then return nil, err, code end
        if status.stateCode == 1 then return status end
        if status.stateCode ~= 3 then
            local info = ffi.new("uint32_t[7]")
            if adv.ControlService(service, 1, info) == 0 then
                code = tonumber(k.GetLastError())
                if code ~= 1062 then return win.Error("ControlService(STOP)", code) end
            end
        end
        return waitFor(adv, service, 1, timeout)
    end)
end

return M
