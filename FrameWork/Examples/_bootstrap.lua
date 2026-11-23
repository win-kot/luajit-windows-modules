-- Shared example loader. It leaves the process working directory as it is.
local source = debug.getinfo(1, 'S').source
assert(source:sub(1, 1) == '@', 'Load the example bootstrap from a file')
local base = source:sub(2):match('^(.*)[/\\]') or '.'

local ffi = require('ffi')
ffi.cdef[[
int __stdcall MultiByteToWideChar(unsigned int, unsigned long, const char*, int, unsigned short*, int);
int __stdcall WideCharToMultiByte(unsigned int, unsigned long, const unsigned short*, int, char*, int, const char*, int*);
unsigned long __stdcall GetFullPathNameW(const unsigned short*, unsigned long, unsigned short*, unsigned short**);
unsigned long __stdcall GetFileAttributesW(const unsigned short*);
]]
local function Wide(path, page)
    assert(type(path) == 'string' and path ~= '' and not path:find('\0', 1, true), 'Invalid library path')
    local length = ffi.C.MultiByteToWideChar(page, 8, path, #path, nil, 0)
    if length == 0 then return nil end
    local wide = ffi.new('unsigned short[?]', length + 1)
    assert(ffi.C.MultiByteToWideChar(page, 8, path, #path, wide, length) == length)
    return wide, length
end
local function Bytes(wide, length, page)
    local size = ffi.C.WideCharToMultiByte(page, 0, wide, length, nil, 0, nil, nil)
    assert(size > 0, 'Could not convert the library path')
    local bytes = ffi.new('char[?]', size)
    assert(ffi.C.WideCharToMultiByte(page, 0, wide, length, bytes, size, nil, nil) == size)
    return ffi.string(bytes, size)
end
local function RuntimePath(raw)
    -- Launch paths may use UTF-8 or the Windows system code page.
    local wide = Wide(raw, 65001)
    if wide and ffi.C.GetFileAttributesW(wide) ~= 0xffffffff then return wide end
    return assert(Wide(raw, 0), 'Could not read the launch path')
end
local function Absolute(wide)
    local capacity = ffi.C.GetFullPathNameW(wide, 0, nil, nil)
    assert(capacity > 0, 'Could not resolve the full library path')
    local buffer = ffi.new('unsigned short[?]', capacity)
    local length = ffi.C.GetFullPathNameW(wide, capacity, buffer, nil)
    assert(length > 0 and length < capacity, 'Could not resolve the full library path')
    return buffer, length
end
local function Exists(path)
    local file = io.open(path, 'rb')
    if not file then return false end
    file:close()
    return true
end
local function Library(path)
    return Exists(path .. '/setup_paths.lua') and Exists(path .. '/fs.lua') and Exists(path .. '/_win_native.lua')
end

local wide, raw
if (...) ~= false and type(arg) == 'table' and arg[1] ~= nil then
    raw = arg[1]
    wide = RuntimePath(raw)
else
    local config = assert(loadfile(base .. '/_config.lua'))()
    if config == nil then
        raw = base .. '/../FrameWork'
        wide = RuntimePath(raw)
    else
        assert(type(config) == 'string' and config ~= '', 'Set a nonempty path or nil in _config.lua')
        if not config:match('^%a:[/\\]') and not config:match('^[/\\][/\\]') then
            raw = base .. '/' .. config
            local parent, length = Absolute(RuntimePath(base))
            config = Bytes(parent, length, 65001) .. '/' .. config
        end
        wide = assert(Wide(config, 65001), 'Use a UTF-8 path in _config.lua')
    end
end
local absolute, length = Absolute(wide)
local root = Bytes(absolute, length, 65001)
local loadPath = root
if not Library(loadPath) then
    local systemPath = Bytes(absolute, length, 0)
    local check, units = Wide(systemPath, 0)
    if units == length and ffi.string(check, units * 2) == ffi.string(absolute, length * 2) and Library(systemPath) then
        loadPath = systemPath
    else
        assert(raw and Library(raw), 'Could not open the FrameWork library: ' .. root)
        loadPath = raw
    end
end
dofile(loadPath .. '/setup_paths.lua')
return root
