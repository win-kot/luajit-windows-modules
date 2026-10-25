-- Shared Win32 icon support for gui.lua and gui_pb.lua (Windows x64).
---@class AppIconFFI: ffilib
---@field NULL nil LuaJIT null-pointer comparisons also accept nil.
local ffi = require('ffi')
---@cast ffi AppIconFFI
local jit = require('jit')
jit.off(true, true)

ffi.cdef[[
void* __stdcall LoadImageW(void*, const unsigned short*, unsigned int, int, int, unsigned int);
int __stdcall DestroyIcon(void*);
int __stdcall GetSystemMetrics(int);
int __stdcall IsWindow(void*);
intptr_t __stdcall SendMessageW(void*, unsigned int, uintptr_t, intptr_t);
void* __stdcall GetModuleHandleW(const unsigned short*);
unsigned long __stdcall GetLastError(void);
int __stdcall MultiByteToWideChar(unsigned int, unsigned long, const char*, int, unsigned short*, int);
]]

local user32, kernel32 = ffi.load('user32'), ffi.load('kernel32')
local M, owned = {}, {}

local function key(hwnd)
    return tostring(ffi.cast('uintptr_t', hwnd))
end

local function destroy(record)
    if record then
        user32.DestroyIcon(record.big)
        user32.DestroyIcon(record.small)
    end
end

local function errorText(operation)
    return operation .. ' failed (Win32 error ' .. tonumber(kernel32.GetLastError()) .. ')'
end

-- source: nil -> resource 1 in the current EXE; integer -> resource ID;
-- string -> UTF-8 ICO filename (relative to the current working directory).
function M.set(hwnd, source)
    if hwnd == nil or hwnd == ffi.NULL or user32.IsWindow(hwnd) == 0 then
        return nil, 'GUI window does not exist'
    end
    if source == nil then source = 1 end
    local instance, name, flags, wide
    if type(source) == 'number' then
        if source ~= math.floor(source) or source < 1 or source > 65535 then
            return nil, 'icon resource ID must be an integer from 1 to 65535'
        end
        instance = kernel32.GetModuleHandleW(nil)
        name = ffi.cast('const unsigned short*', source)
        flags = 0
    elseif type(source) == 'string' then
        if source == '' or source:find('\0', 1, true) then
            return nil, 'icon path must be a non-empty UTF-8 string without NUL'
        end
        local length = kernel32.MultiByteToWideChar(65001, 8, source, #source, nil, 0)
        if length == 0 then return nil, errorText('MultiByteToWideChar') end
        wide = ffi.new('unsigned short[?]', length + 1)
        if kernel32.MultiByteToWideChar(65001, 8, source, #source, wide, length) == 0 then
            return nil, errorText('MultiByteToWideChar')
        end
        instance, name, flags = nil, wide, 0x10 -- LR_LOADFROMFILE
    else
        return nil, 'icon source must be an ICO path or resource ID'
    end
    local big = user32.LoadImageW(instance, name, 1,
        user32.GetSystemMetrics(11), user32.GetSystemMetrics(12), flags)
    if big == nil then return nil, errorText('LoadImageW (large icon)') end
    local small = user32.LoadImageW(instance, name, 1,
        user32.GetSystemMetrics(49), user32.GetSystemMetrics(50), flags)
    if small == nil then
        local err = errorText('LoadImageW (small icon)')
        user32.DestroyIcon(big)
        return nil, err
    end
    local record = {big = big, small = small}
    local id = key(hwnd)
    local previous = owned[id]
    user32.SendMessageW(hwnd, 0x80, 1, ffi.cast('intptr_t', big)) -- WM_SETICON / ICON_BIG
    user32.SendMessageW(hwnd, 0x80, 0, ffi.cast('intptr_t', small))
    owned[id] = record
    destroy(previous) -- only handles allocated by this module are owned
    return true
end

-- Called after window destruction; deferred PB close is collected after pump.
function M.release(hwnd, destroying)
    if hwnd == nil or hwnd == ffi.NULL then return true end
    if not destroying and user32.IsWindow(hwnd) ~= 0 then return false end
    local id = key(hwnd)
    destroy(owned[id])
    owned[id] = nil
    return true
end

return M
