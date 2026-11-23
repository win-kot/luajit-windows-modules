local ffi = require("ffi")
local win = require("_win_extension")
local k = win.kernel
ffi.cdef[[
void *__stdcall OpenEventW(unsigned long, int, const uint16_t *);
int __stdcall SetEvent(void *);
int __stdcall ResetEvent(void *);
void *__stdcall CreateMutexW(void *, int, const uint16_t *);
void *__stdcall OpenMutexW(unsigned long, int, const uint16_t *);
int __stdcall ReleaseMutex(void *);
]]
local M = {}
local objects = setmetatable({}, {__mode = "k"})
local function make(kind, name, create, manualReset, initialState)
    local wide, err, code = win.Named(name, "Local\\")
    if not wide then return nil, err, code end
    local handle
    if create then
        local attrs
        attrs, err, code = win.UserAcl()
        if not attrs then return nil, err, code end
        k.SetLastError(0)
        if kind == "event" then
            handle = k.CreateEventW(attrs, manualReset and 1 or 0, initialState and 1 or 0, wide)
        else
            handle = k.CreateMutexW(attrs, 0, wide)
        end
        code = tonumber(k.GetLastError())
        k.LocalFree(attrs[0].descriptor)
    else
        handle = (kind == "event" and k.OpenEventW or k.OpenMutexW)(kind == "event" and 0x100002 or 0x100001, 0, wide)
        if handle == nil then code = tonumber(k.GetLastError()) end
    end
    if handle == nil then return win.Error((create and "Create " or "Open ") .. kind, code) end
    local object = {}
    objects[object] = {kind = kind, handle = win.Own(handle)}
    if create then return object, code ~= 183 end
    return object
end

local function get(object, kind)
    local state = objects[object]
    if state and state.kind == kind and state.handle then return state.handle end
    return win.Error("Invalid or closed " .. kind, 6)
end

local function close(object, kind)
    local state = objects[object]
    if not state or state.kind ~= kind then return win.Error("Invalid " .. kind, 6) end
    if not state.handle then return true end
    local ok, err, code = win.Close(state.handle)
    if ok then state.handle = nil end
    return ok, err, code
end

local function wait(object, kind, timeoutMs)
    local handle, err, code = get(object, kind)
    if not handle then return nil, err, code end
    local timeout
    timeout, err, code = win.Timeout(timeoutMs, 5000)
    if not timeout then return nil, err, code end
    local result = k.WaitForSingleObject(handle, timeout)
    if result == 0 then return true end
    if result == 128 then return true, "abandoned" end
    if result == 258 then return false end
    return win.Error("WaitForSingleObject")
end

local function action(object, kind, name)
    local handle, err, code = get(object, kind)
    if not handle then return nil, err, code end
    if k[name](handle) == 0 then return win.Error(name) end
    return true
end

function M.EventCreate(name, manualReset, initialState)
    if (manualReset ~= nil and type(manualReset) ~= "boolean") or
       (initialState ~= nil and type(initialState) ~= "boolean") then
        return win.Error("Event flags must be boolean", 87)
    end
    return make("event", name, true, manualReset, initialState)
end
function M.EventOpen(name) return make("event", name, false) end
function M.EventSet(event) return action(event, "event", "SetEvent") end
function M.EventReset(event) return action(event, "event", "ResetEvent") end
function M.EventWait(event, timeoutMs) return wait(event, "event", timeoutMs) end
function M.EventClose(event) return close(event, "event") end
function M.MutexCreate(name) return make("mutex", name, true) end
function M.MutexOpen(name) return make("mutex", name, false) end
function M.MutexLock(mutex, timeoutMs) return wait(mutex, "mutex", timeoutMs) end
function M.MutexUnlock(mutex) return action(mutex, "mutex", "ReleaseMutex") end
function M.MutexClose(mutex) return close(mutex, "mutex") end
return M
