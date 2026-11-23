local ffi = require("ffi")
local win = require("_win_extension")
local sync = require("sync")
local window = require("window")
local M = {}

ffi.cdef[[
typedef intptr_t (__stdcall *fw_window_ipc_proc)(void *, uint32_t, uintptr_t, intptr_t);
typedef struct {
    uint32_t style;
    fw_window_ipc_proc proc;
    int classExtra, windowExtra;
    void *instance, *icon, *cursor, *background;
    const uint16_t *menuName, *className;
} fw_window_ipc_class;
void *__stdcall GetModuleHandleW(const uint16_t *);
uint16_t __stdcall fw_window_ipc_RegisterClassW(const fw_window_ipc_class *) __asm__("RegisterClassW");
void *__stdcall fw_window_ipc_CreateWindowExW(uint32_t, const uint16_t *, const uint16_t *, uint32_t,
    int, int, int, int, void *, void *, void *, void *) __asm__("CreateWindowExW");
intptr_t __stdcall fw_window_ipc_DefWindowProcW(void *, uint32_t, uintptr_t, intptr_t) __asm__("DefWindowProcW");
int __stdcall DestroyWindow(void *);
void *__stdcall fw_window_ipc_FindWindowExW(void *, void *, const uint16_t *, const uint16_t *) __asm__("FindWindowExW");
]]

local user = ffi.load("user32")
local parent = ffi.cast("void *", -3) -- HWND_MESSAGE
local className = assert(win.ToWide("LuaJIT.Framework.WindowIPC.1"))
local messageId = 0x8551 -- WM_APP + 0x551
local callback, instance, hwnd, handler

local function getName(name)
    if type(name) ~= "string" or name == "" then
        return win.Error("Expected a nonempty UTF-8 receiver name", 87)
    end
    local wide, count, code = win.ToWide(name)
    if not wide then return nil, count, code end
    if count > 255 then return win.Error("Receiver name exceeds 255 UTF-16 units", 206) end
    return wide
end

local function register()
    if callback then return true end
    instance = win.kernel.GetModuleHandleW(nil)
    if instance == nil then return win.Error("GetModuleHandleW") end
    local proc = ffi.cast("fw_window_ipc_proc", function(handle, msg, wParam, lParam)
        if msg == 0x82 and handle == hwnd then -- WM_NCDESTROY
            hwnd, handler = nil, nil
        end
        if msg == messageId and handle == hwnd then
            local command, value = tonumber(wParam), tonumber(lParam)
            if handler and win.Integer(command, 0, 2147483647) and win.Integer(value, -2147483648, 2147483647) then
                local ok, reason = pcall(handler, command, value)
                if not ok then
                    pcall(function() io.stderr:write("window_ipc handler: " .. tostring(reason) .. "\n") end)
                end
            end
            return 0
        end
        return user.fw_window_ipc_DefWindowProcW(handle, msg, wParam, lParam)
    end)
    local class = ffi.new("fw_window_ipc_class[1]")
    class[0].instance, class[0].className, class[0].proc = instance, className, proc
    if user.fw_window_ipc_RegisterClassW(class) == 0 then
        local code = win.kernel.GetLastError()
        proc:free()
        return win.Error("RegisterClassW(window_ipc)", code)
    end
    callback = proc
    return true
end

local function find(name)
    return user.fw_window_ipc_FindWindowExW(parent, nil, className, name)
end

local function create(name, onCommand)
    if find(name) ~= nil then return win.Error("Window IPC receiver name is already in use", 183) end
    local ok, err, code = register()
    if not ok then return nil, err, code end
    local handle = user.fw_window_ipc_CreateWindowExW(0, className, name, 0, 0, 0, 0, 0, parent, nil, instance, nil)
    if handle == nil then return win.Error("CreateWindowExW(window_ipc)") end
    hwnd, handler = handle, onCommand
    return true
end

function M.Listen(name, onCommand)
    if hwnd ~= nil then return win.Error("A window IPC receiver is already active in this process", 183) end
    if type(onCommand) ~= "function" then return win.Error("Expected a window IPC handler function", 87) end
    local wide, err, code = getName(name)
    if not wide then return nil, err, code end

    -- Serialize lookup and window creation, including case-insensitive name matches.
    local lock
    lock, err, code = sync.MutexCreate("LuaJIT.Framework.WindowIPC.1.Registry")
    if not lock then return nil, err, code end
    local acquired
    acquired, err, code = sync.MutexLock(lock, 5000)
    if not acquired then
        sync.MutexClose(lock)
        if acquired == false then return win.Error("Window IPC registration timed out", 1460) end
        return nil, err, code
    end
    local called, result, message, status = pcall(create, wide, onCommand)
    sync.MutexUnlock(lock)
    sync.MutexClose(lock)
    if not called then error(result, 0) end
    return result, message, status
end

function M.Post(name, command, value)
    if value == nil then value = 0 end
    if not win.Integer(command, 0, 2147483647) or not win.Integer(value, -2147483648, 2147483647) then
        return win.Error("Expected a nonnegative 31-bit command and a signed 32-bit value", 87)
    end
    local wide, err, code = getName(name)
    if not wide then return nil, err, code end
    local handle = find(wide)
    if handle == nil then return win.Error("Window IPC receiver not found", 1168) end
    return window.MessagePost(handle, messageId, command, value)
end

function M.Close()
    if hwnd == nil then return true end
    if user.DestroyWindow(hwnd) == 0 then return win.Error("DestroyWindow(window_ipc)") end
    hwnd, handler = nil, nil
    return true
end

-- Win32 can re-enter a Lua WNDPROC while creating or destroying an HWND.
jit.off(M.Listen, true)
jit.off(M.Close, true)
return M
