local ffi = require("ffi")
local win = require("_win_extension")
local errors = require("_errors")
local user = ffi.load("user32")
local now = require("timer").Ticks
local M = {}

ffi.cdef[[
typedef struct {
    void *hwnd;
    uint32_t message;
    uintptr_t wParam;
    intptr_t lParam;
    uint32_t time;
    long x, y;
    uint32_t privateData;
} fw_clipboard_msg;
void *__stdcall fw_clipboard_CreateWindowExW(uint32_t, const uint16_t *, const uint16_t *, uint32_t,
    int, int, int, int, void *, void *, void *, void *) __asm__("CreateWindowExW");
int __stdcall fw_clipboard_DestroyWindow(void *) __asm__("DestroyWindow");
int __stdcall AddClipboardFormatListener(void *);
int __stdcall RemoveClipboardFormatListener(void *);
int __stdcall fw_clipboard_PeekMessageW(fw_clipboard_msg *, void *, uint32_t, uint32_t, uint32_t)
    __asm__("PeekMessageW");
uint32_t __stdcall MsgWaitForMultipleObjectsEx(uint32_t, const void *, uint32_t, uint32_t, uint32_t);
void __stdcall fw_clipboard_PostQuitMessage(int) __asm__("PostQuitMessage");
]]

local className = assert(win.ToWide("STATIC"))
local windowName = assert(win.ToWide("LuaJIT Framework Clipboard Listener"))
local messageParent = ffi.cast("void *", -3)
local WM_CLIPBOARDUPDATE, WM_QUIT = 0x031D, 0x0012
local listeners = setmetatable({}, {__mode = "v"})

local function notify(state)
    local sequence = state.sequenceNumber()
    if sequence == state.previous then return 0 end
    state.previous = sequence
    local ok, err = pcall(state.callback, {sequence = sequence})
    if not ok then return errors.Callback("Clipboard callback", err) end
    return 1
end

function M.Dispatch(hwnd, message)
    if message ~= WM_CLIPBOARDUPDATE then return false end
    local state = listeners[tostring(ffi.cast("void *", hwnd))]
    if not state then return false end
    local count, err = notify(state)
    if not count then pcall(function() io.stderr:write(err .. "\n") end) end
    return true
end

local function destroy(hwnd)
    user.RemoveClipboardFormatListener(hwnd)
    return user.fw_clipboard_DestroyWindow(hwnd)
end

function M.Subscribe(callback, sequenceNumber)
    if type(callback) ~= "function" then return win.Error("Expected a clipboard callback", 87) end
    local hwnd = user.fw_clipboard_CreateWindowExW(0, className, windowName, 0, 0, 0, 0, 0,
        messageParent, nil, nil, nil)
    if hwnd == nil then return win.Error("CreateWindowExW(clipboard listener)") end
    local previous = sequenceNumber()
    if user.AddClipboardFormatListener(hwnd) == 0 then
        local code = win.kernel.GetLastError()
        user.fw_clipboard_DestroyWindow(hwnd)
        return win.Error("AddClipboardFormatListener", code)
    end
    local key = tostring(ffi.cast("void *", hwnd))
    local state = {hwnd = ffi.gc(hwnd, destroy), callback = callback, sequenceNumber = sequenceNumber,
        previous = previous}
    listeners[key] = state
    return {
        Close = function()
            if state.hwnd == nil then return true end
            if destroy(state.hwnd) == 0 then return win.Error("DestroyWindow(clipboard listener)") end
            ffi.gc(state.hwnd, nil)
            listeners[key], state.hwnd, state.callback = nil, nil, nil
            return true
        end,
        Poll = function(_, timeoutMs)
            if state.hwnd == nil then return win.Error("Clipboard subscription is closed", 6) end
            local timeout, err, code = win.Timeout(timeoutMs, 0)
            if not timeout then return nil, err, code end
            local message = ffi.new("fw_clipboard_msg[1]")
            local deadline = now() + timeout
            while true do
                if user.fw_clipboard_PeekMessageW(message, state.hwnd, WM_CLIPBOARDUPDATE, WM_CLIPBOARDUPDATE, 1) ~= 0 then
                    if message[0].message == WM_QUIT then
                        user.fw_clipboard_PostQuitMessage(tonumber(message[0].wParam))
                        return 0
                    end
                    local changed, detail, status = notify(state)
                    if changed ~= 0 then return changed, detail, status end
                else
                    local left = deadline - now()
                    if left <= 0 then return 0 end
                    local waited = user.MsgWaitForMultipleObjectsEx(0, nil, left, 0x0008, 0) -- QS_POSTMESSAGE
                    if waited == 258 then return 0 end
                    if waited ~= 0 then return win.Error("MsgWaitForMultipleObjectsEx(clipboard listener)") end
                end
                if state.hwnd == nil then return win.Error("Clipboard subscription is closed", 6) end
            end
        end
    }
end

return M
