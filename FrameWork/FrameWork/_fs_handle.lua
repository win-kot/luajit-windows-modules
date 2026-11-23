local ffi = require("ffi")
local win = require("_win_extension")
local native = require("_win_native")
local options = require("_options")
local k = win.kernel
local handles = setmetatable({}, {__mode = "k"})
local methods = {}
local metatable = {__index = methods}
local modes = {
    r = {0x80000000, 3}, w = {0x40000000, 4}, a = {4, 4},
    ["r+"] = {0xC0000000, 3}, ["w+"] = {0xC0000000, 4}, ["a+"] = {0x80000004, 4}
}
local sharing = {none = 0, read = 1, write = 2, readwrite = 3}
local origins = {begin = 0, current = 1, ["end"] = 2}
local maxExact = 9007199254740991
ffi.cdef[[
typedef struct {
    uintptr_t internal, internalHigh;
    uint32_t low, high;
    void *event;
} fw_lock_overlapped;
int __stdcall LockFileEx(void *, uint32_t, uint32_t, uint32_t, uint32_t, fw_lock_overlapped *);
int __stdcall UnlockFileEx(void *, uint32_t, uint32_t, uint32_t, fw_lock_overlapped *);
]]

local function range(offset, length)
    if not (win.Integer(offset, 0, maxExact) or (ffi.istype("int64_t", offset) and offset >= 0)) then return nil, "Недопустимое смещение блокировки" end
    if not (win.Integer(length, 1, maxExact) or (ffi.istype("int64_t", length) and length > 0)) then return nil, "Недопустимая длина блокировки" end
    offset, length = ffi.cast("uint64_t", offset), ffi.cast("uint64_t", length)
    if offset + length > 9223372036854775808ULL then return nil, "Диапазон блокировки выходит за допустимое смещение" end
    local position = ffi.new("fw_lock_overlapped[1]")
    position[0].low, position[0].high = ffi.cast("uint32_t", offset), tonumber(offset / 4294967296ULL)
    return position, ffi.cast("uint32_t", length), tonumber(length / 4294967296ULL)
end

function methods:Lock(offset, length, opts)
    local handle = handles[self]
    if not handle then return win.Error("File is closed", 6) end
    local err; opts, err = options(opts, {shared = "boolean"}); if not opts then return nil, err end
    local position, low, high = range(offset, length)
    if not position then return nil, low end
    if k.LockFileEx(handle, opts.shared and 1 or 3, 0, low, high, position) ~= 0 then return true end
    local code = tonumber(k.GetLastError())
    if code == 33 then return false end
    return win.Error("LockFileEx", code)
end

function methods:Unlock(offset, length)
    local handle = handles[self]
    if not handle then return win.Error("File is closed", 6) end
    local position, low, high = range(offset, length)
    if not position then return nil, low end
    if k.UnlockFileEx(handle, 0, low, high, position) == 0 then return win.Error("UnlockFileEx") end
    return true
end

function methods:IsOpen()
    return handles[self] ~= nil
end

function methods:Close()
    local handle = handles[self]
    if not handle then return true end
    local ok, err, code = win.Close(handle)
    if ok then handles[self] = nil end
    return ok, err, code
end

function methods:Read(count)
    local handle = handles[self]
    if not handle then return win.Error("File is closed", 6) end
    if count ~= nil and not win.Integer(count, 0, 0x7FFFFFFF) then return nil, "Недопустимое число байт" end
    if count == 0 then return "" end
    local parts = {}
    while count == nil or count > 0 do
        local bytes, err, code = native.FsRead(handle, math.min(count or 65536, 65536))
        if not bytes then return nil, err, code end
        if bytes == "" then break end
        parts[#parts + 1] = bytes
        if count then count = count - #bytes end
    end
    return table.concat(parts)
end

function methods:Write(bytes)
    local handle = handles[self]
    if not handle then return win.Error("File is closed", 6) end
    if type(bytes) ~= "string" then return nil, "Требуется строка байт" end
    return native.FsWrite(handle, bytes)
end

function methods:Seek(offset, origin)
    local handle = handles[self]
    if not handle then return win.Error("File is closed", 6) end
    if not (win.Integer(offset, -maxExact, maxExact) or ffi.istype("int64_t", offset)) then return nil, "Недопустимое смещение файла" end
    local base = origins[origin or "begin"]; if base == nil then return nil, "Недопустимая точка отсчёта" end
    local position = ffi.new("int64_t[1]")
    if k.SetFilePointerEx(handle, offset, position, base) == 0 then return win.Error("SetFilePointerEx") end
    return win.Exact(position[0])
end

function methods:GetSize()
    local handle = handles[self]
    if not handle then return win.Error("File is closed", 6) end
    local size = ffi.new("int64_t[1]")
    if k.GetFileSizeEx(handle, size) == 0 then return win.Error("GetFileSizeEx") end
    return win.Exact(size[0])
end

function methods:Flush()
    local handle = handles[self]
    if not handle then return win.Error("File is closed", 6) end
    return native.FsFsync(handle)
end

return function(fs)
    fs.Lock, fs.Unlock = methods.Lock, methods.Unlock
    function fs.Open(path, mode, opts)
        local spec = modes[mode]; if not spec then return nil, "Нет такого режима открытия файла" end
        local detail; opts, detail = options(opts, {share = "string"}); if not opts then return nil, detail end
        local share = sharing[opts.share or "read"]; if share == nil then return nil, "Нет такого режима совместного доступа" end
        local wide, err, code = win.PathWide(path)
        if not wide then return nil, err, code end
        local handle = k.CreateFileW(wide, spec[1], share, nil, spec[2], 128, nil)
        if handle == win.invalidHandle then return win.Error("CreateFileW", nil, path) end
        handle = win.Own(handle)
        -- Truncate only the selected stream, also for existing hidden files.
        if (mode == "w" or mode == "w+") and k.SetEndOfFile(handle) == 0 then
            local status = tonumber(k.GetLastError())
            win.Close(handle)
            return win.Error("SetEndOfFile", status, path)
        end
        local object = setmetatable({}, metatable)
        handles[object] = handle
        return object
    end
end
