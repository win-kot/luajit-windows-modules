local ffi = require("ffi")
local sync = require("sync")
local win = require("_win_extension")
local k = win.kernel
local M = {}

ffi.cdef[[
typedef struct {
    uint32_t magic, version, capacity, length, valid;
} fw_shared_header;
void *__stdcall CreateFileMappingW(void *, void *, unsigned long, unsigned long,
    unsigned long, const uint16_t *);
void *__stdcall OpenFileMappingW(unsigned long, int, const uint16_t *);
void *__stdcall MapViewOfFile(void *, unsigned long, unsigned long, unsigned long, size_t);
int __stdcall UnmapViewOfFile(const void *);
]]

local HEADER_SIZE = ffi.sizeof("fw_shared_header")
local MAGIC, VERSION = 0x48535746, 1 -- FWSH, little-endian
local DEFAULT_CAPACITY, MAX_CAPACITY = 1024 * 1024, 64 * 1024 * 1024
local PREFIX = "LuaJIT.FrameWork.SharedMemory."
local objects = setmetatable({}, {__mode = "k"})

local function withLock(mutex, timeout, action)
    local acquired, reason, code = sync.MutexLock(mutex, timeout)
    if not acquired then return acquired, reason, code end
    local ok, result, message, status = pcall(action)
    local released, releaseMessage, releaseCode = sync.MutexUnlock(mutex)
    if not ok then error(result, 0) end
    if not released then return nil, releaseMessage, releaseCode end
    return result, message, status
end

local function viewOpen(mapping, size)
    local view = k.MapViewOfFile(mapping, 2, 0, 0, size)
    if view == nil then return win.Error("MapViewOfFile") end
    return ffi.gc(view, k.UnmapViewOfFile)
end

local function viewClose(view)
    if k.UnmapViewOfFile(view) == 0 then return win.Error("UnmapViewOfFile") end
    ffi.gc(view, nil)
    return true
end

local function headerValid(header)
    return header.magic == MAGIC and header.version == VERSION and
        win.Integer(header.capacity, 1, MAX_CAPACITY)
end

local function mappingOpen(wide, capacity)
    if capacity == nil then
        local mapping = k.OpenFileMappingW(2, 0, wide)
        if mapping == nil then return win.Error("OpenFileMappingW") end
        return win.Own(mapping), false
    end
    local attrs, err, code = win.UserAcl()
    if not attrs then return nil, err, code end
    k.SetLastError(0)
    local mapping = k.CreateFileMappingW(win.invalidHandle, attrs, 4, 0, capacity + HEADER_SIZE, wide)
    code = tonumber(k.GetLastError())
    k.LocalFree(attrs[0].descriptor)
    if mapping == nil then return win.Error("CreateFileMappingW", code) end
    return win.Own(mapping), code ~= 183
end

local function openView(mapping, created, requested)
    local size = requested
    if not created then
        local view, err, code = viewOpen(mapping, HEADER_SIZE)
        if not view then return nil, err, code end
        local header = ffi.cast("fw_shared_header *", view)
        local valid = headerValid(header)
        size = tonumber(header.capacity)
        local closed
        closed, err, code = viewClose(view)
        if not closed then return nil, err, code end
        if not valid then return win.Error("Invalid shared memory format", 13) end
        if requested and requested ~= size then
            return win.Error("Existing shared memory has a different capacity", 183)
        end
    end
    local view, err, code = viewOpen(mapping, HEADER_SIZE + size)
    if not view then return nil, err, code end
    local header = ffi.cast("fw_shared_header *", view)
    if created then
        header.magic, header.version, header.capacity = MAGIC, VERSION, size
        header.length, header.valid = 0, 1
    end
    return view, size
end

local function open(name, capacity, timeoutMs)
    local wide, err, code = win.Named(name, "Local\\" .. PREFIX .. "Map.")
    if not wide then return nil, err, code end
    local timeout
    timeout, err, code = win.Timeout(timeoutMs, 5000)
    if not timeout then return nil, err, code end
    local mutex
    local getMutex = capacity and sync.MutexCreate or sync.MutexOpen
    mutex, err, code = getMutex(PREFIX .. "Lock." .. name)
    if not mutex then return nil, err, code end
    local state, created
    state, created, code = withLock(mutex, timeout, function()
        local mapping, fresh, status = mappingOpen(wide, capacity)
        if not mapping then return nil, fresh, status end
        local view, size
        view, size, status = openView(mapping, fresh, capacity)
        if not view then
            win.Close(mapping)
            return nil, size, status
        end
        return {mapping = mapping, view = view, capacity = size, mutex = mutex}, fresh
    end)
    if not state then
        sync.MutexClose(mutex)
        return state, created, code
    end
    local object = {}
    objects[object] = state
    if capacity then return object, created end
    return object, state.capacity
end

function M.SharedMemoryCreate(name, capacity, timeoutMs)
    if capacity == nil then capacity = DEFAULT_CAPACITY end
    if not win.Integer(capacity, 1, MAX_CAPACITY) then
        return win.Error("Shared memory capacity must be between 1 byte and 64 MiB", 87)
    end
    return open(name, capacity, timeoutMs)
end

function M.SharedMemoryOpen(name, timeoutMs)
    return open(name, nil, timeoutMs)
end

local function access(object, timeoutMs, action)
    local state = objects[object]
    if not state or not state.view or not state.mapping or not state.mutex then
        return win.Error("Invalid or closed shared memory object", 6)
    end
    local timeout, err, code = win.Timeout(timeoutMs, 5000)
    if not timeout then return nil, err, code end
    return withLock(state.mutex, timeout, function()
        local header = ffi.cast("fw_shared_header *", state.view)
        if not headerValid(header) or header.capacity ~= state.capacity then
            return win.Error("Invalid shared memory header", 13)
        end
        return action(header, ffi.cast("uint8_t *", state.view) + HEADER_SIZE, state.capacity)
    end)
end

function M.SharedMemoryRead(object, timeoutMs)
    return access(object, timeoutMs, function(header, data, capacity)
        if header.valid ~= 1 or header.length > capacity then
            return win.Error("No complete shared memory value", 13)
        end
        return ffi.string(data, header.length)
    end)
end

function M.SharedMemoryWrite(object, bytes, timeoutMs)
    if type(bytes) ~= "string" then return win.Error("Expected a binary string", 87) end
    return access(object, timeoutMs, function(header, data, capacity)
        if #bytes > capacity then return win.Error("Shared memory capacity exceeded", 122) end
        -- A reader can only observe the committed length or a failed write.
        header.valid = 0
        ffi.copy(data, bytes, #bytes)
        header.length = #bytes
        header.valid = 1
        return true
    end)
end
jit.off(M.SharedMemoryWrite, true)

function M.SharedMemoryClose(object)
    local state = objects[object]
    if not state then return win.Error("Invalid shared memory object", 6) end
    if state.view then
        local ok, err, code = viewClose(state.view)
        if not ok then return nil, err, code end
        state.view = nil
    end
    if state.mapping then
        local ok, err, code = win.Close(state.mapping)
        if not ok then return nil, err, code end
        state.mapping = nil
    end
    if state.mutex then
        local ok, err, code = sync.MutexClose(state.mutex)
        if not ok then return nil, err, code end
        state.mutex = nil
    end
    return true
end

return M
