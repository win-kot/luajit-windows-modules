-- Win32 icon support for gui.lua (Windows x64).
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

local function Key(hwnd)
    local kind = type(hwnd)
    if kind ~= 'number' and kind ~= 'cdata' then return nil, 'invalid HWND type' end
    if kind == 'number' and (hwnd < 0 or hwnd > 9007199254740991 or hwnd % 1 ~= 0) then
        return nil, 'invalid HWND value'
    end
    local ok, value = pcall(ffi.cast, 'uintptr_t', hwnd)
    if not ok then return nil, 'invalid HWND value' end
    return tostring(value), nil, ffi.cast('void *', value)
end

local function Destroy(record)
    if record then
        user32.DestroyIcon(record.big)
        user32.DestroyIcon(record.small)
    end
end

local WinError = require("_errors").Win32

-- source: nil -> resource 1 in the current EXE; integer -> resource ID;
-- string -> UTF-8 ICO filename (relative to the current working directory).
function M.Set(hwnd, source)
    if hwnd == nil or hwnd == ffi.NULL then return nil, 'GUI window does not exist' end
    local id, err, pointer = Key(hwnd)
    if not id then return nil, err end
    hwnd = pointer
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
        if length == 0 then return WinError('MultiByteToWideChar') end
        wide = ffi.new('unsigned short[?]', length + 1)
        if kernel32.MultiByteToWideChar(65001, 8, source, #source, wide, length) == 0 then
            return WinError('MultiByteToWideChar')
        end
        instance, name, flags = nil, wide, 0x10 -- LR_LOADFROMFILE
    else
        return nil, 'icon source must be an ICO path or resource ID'
    end
    local big = user32.LoadImageW(instance, name, 1,
        user32.GetSystemMetrics(11), user32.GetSystemMetrics(12), flags)
    if big == nil then return WinError('LoadImageW (large icon)', nil, type(source) == 'string' and source or nil) end
    local small = user32.LoadImageW(instance, name, 1,
        user32.GetSystemMetrics(49), user32.GetSystemMetrics(50), flags)
    if small == nil then
        local _, err, code = WinError('LoadImageW (small icon)', nil, type(source) == 'string' and source or nil)
        user32.DestroyIcon(big)
        return nil, err, code
    end
    local record = {big = big, small = small}
    local previous = owned[id]
    user32.SendMessageW(hwnd, 0x80, 1, ffi.cast('intptr_t', big)) -- WM_SETICON / ICON_BIG
    user32.SendMessageW(hwnd, 0x80, 0, ffi.cast('intptr_t', small))
    owned[id] = record
    Destroy(previous) -- only handles allocated by this module are owned
    return true
end

-- Called after window destruction to release owned icon handles.
function M.Release(hwnd, destroying)
    if hwnd == nil or hwnd == ffi.NULL then return true end
    local id, err, pointer = Key(hwnd)
    if not id then return nil, err end
    hwnd = pointer
    if not destroying and user32.IsWindow(hwnd) ~= 0 then return false end
    Destroy(owned[id])
    owned[id] = nil
    return true
end

return M
