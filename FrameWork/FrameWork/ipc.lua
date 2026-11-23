local ffi = require("ffi")
local win = require("_win_extension")
local k = win.kernel
ffi.cdef[[
typedef struct {
    uintptr_t internal, transferred;
    unsigned long offset, offsetHigh;
    void *event;
} fw_overlapped;
void *__stdcall CreateNamedPipeW(const uint16_t *, unsigned long, unsigned long,
    unsigned long, unsigned long, unsigned long, unsigned long, void *);
int __stdcall ConnectNamedPipe(void *, fw_overlapped *);
int __stdcall DisconnectNamedPipe(void *);
int __stdcall WaitNamedPipeW(const uint16_t *, unsigned long);
int __stdcall GetNamedPipeClientProcessId(void *, unsigned long *);
int __stdcall GetNamedPipeServerProcessId(void *, unsigned long *);
int __stdcall fw_GetOverlappedResult(void *, fw_overlapped *, unsigned long *, int) __asm__("GetOverlappedResult");
int __stdcall fw_CancelIoEx(void *, fw_overlapped *) __asm__("CancelIoEx");
int __stdcall ResetEvent(void *);
]]
local M = {}
local objects = setmetatable({}, {__mode = "k"})
local DEFAULT_TIMEOUT, DEFAULT_MAX, DEFAULT_BUFFER = 5000, 4 * 1024 * 1024, 65536

local function new(handle, server, timeout, maximum)
    local event = k.CreateEventW(nil, 1, 0, nil)
    if event == nil then
        local code = k.GetLastError()
        k.CloseHandle(handle)
        return win.Error("CreateEventW", code)
    end
    local object = {}
    objects[object] = {
        handle = win.Own(handle), event = win.Own(event), server = server,
        connected = not server, timeout = timeout, maximum = maximum
    }
    return object
end

local function get(object, serverOnly, connectedOnly)
    local state = objects[object]
    if not state or not state.handle or (serverOnly and not state.server) then
        return win.Error("Invalid or closed pipe", 6)
    end
    if connectedOnly and not state.connected then return win.Error("Pipe is disconnected", 233) end
    return state
end

local function remaining(deadline)
    return math.max(0, deadline - tonumber(k.GetTickCount64()))
end

local function operation(state, action, buffer, length, deadline)
    if k.ResetEvent(state.event) == 0 then return nil, tonumber(k.GetLastError()) end
    local ov = ffi.new("fw_overlapped[1]")
    ov[0].event = state.event
    local count = ffi.new("unsigned long[1]")
    local ok
    if action == "ConnectNamedPipe" then
        ok = k.ConnectNamedPipe(state.handle, ov)
    else
        ok = k[action](state.handle, buffer, length, count, ov)
    end
    if ok ~= 0 then return tonumber(count[0]) end
    local code = tonumber(k.GetLastError())
    if action == "ConnectNamedPipe" and code == 535 then return 0 end
    if code ~= 997 then return nil, code end
    local wait = k.WaitForSingleObject(state.event, remaining(deadline))
    if wait == 0 then
        if k.fw_GetOverlappedResult(state.handle, ov, count, 0) ~= 0 then return tonumber(count[0]) end
        return nil, tonumber(k.GetLastError())
    end
    local waitError = wait ~= 258 and tonumber(k.GetLastError())
    k.fw_CancelIoEx(state.handle, ov)
    -- Windows owns ov and buffer until completion. Local NPFS I/O supports cancellation.
    if k.fw_GetOverlappedResult(state.handle, ov, count, 1) ~= 0 then return tonumber(count[0]) end
    code = tonumber(k.GetLastError())
    if wait == 258 and code == 995 then return false end
    return nil, waitError or code
end

local function disconnect(state)
    if not state.server then
        state.connected = false
        local ok, err, code = win.Close(state.handle)
        if ok then state.handle = nil end
        return ok, err, code
    end
    state.connected = false
    if k.DisconnectNamedPipe(state.handle) == 0 then
        local code = tonumber(k.GetLastError())
        if code ~= 233 then
            if win.Close(state.handle) then state.handle = nil end
            return win.Error("DisconnectNamedPipe", code)
        end
    end
    return true
end

function M.PipeServerCreate(name, options)
    local wide, err, code = win.Named(name, "\\\\.\\pipe\\")
    if not wide then return nil, err, code end
    if options == nil then options = {} end
    if type(options) ~= "table" then return win.Error("Expected pipe options table", 87) end
    local maximum = options.maxMessageBytes
    local buffer = options.bufferBytes
    if maximum == nil then maximum = DEFAULT_MAX end
    if buffer == nil then buffer = DEFAULT_BUFFER end
    if not win.Integer(maximum, 0, 0x7FFFFFFB) or not win.Integer(buffer, 1, 0x1000000) or
        (options.localOnly ~= nil and type(options.localOnly) ~= "boolean") then
        return win.Error("Invalid pipe options", 87)
    end
    local timeout
    timeout, err, code = win.Timeout(options.timeoutMs, DEFAULT_TIMEOUT)
    if not timeout then return nil, err, code end
    local attrs
    attrs, err, code = win.UserAcl()
    if not attrs then return nil, err, code end
    local mode = options.localOnly == false and 0 or 8
    local handle = k.CreateNamedPipeW(wide, 0x40000003, mode, 255, buffer, buffer, timeout, attrs)
    code = handle == win.invalidHandle and tonumber(k.GetLastError())
    k.LocalFree(attrs[0].descriptor)
    if code then return win.Error("CreateNamedPipeW", code) end
    return new(handle, true, timeout, maximum)
end

function M.PipeAccept(server, timeoutMs)
    local state, err, code = get(server, true)
    if not state then return nil, err, code end
    if state.connected then return win.Error("Pipe already connected", 535) end
    local timeout
    timeout, err, code = win.Timeout(timeoutMs, state.timeout)
    if not timeout then return nil, err, code end
    local result
    result, code = operation(state, "ConnectNamedPipe", nil, 0, tonumber(k.GetTickCount64()) + timeout)
    if result == false then return false end
    if not result then
        -- ERROR_NO_DATA: a client opened and closed the pipe before ConnectNamedPipe.
        if code == 232 then
            local reset, message, resetCode = disconnect(state)
            if not reset then return nil, message, resetCode end
        end
        return win.Error("ConnectNamedPipe", code)
    end
    state.connected = true
    return true
end

function M.PipeConnect(name, timeoutMs)
    local wide, err, code = win.Named(name, "\\\\.\\pipe\\")
    if not wide then return nil, err, code end
    local timeout
    timeout, err, code = win.Timeout(timeoutMs, DEFAULT_TIMEOUT)
    if not timeout then return nil, err, code end
    local deadline = tonumber(k.GetTickCount64()) + timeout
    repeat
        -- Read/write data and synchronize. Identification-only client token.
        local handle = k.CreateFileW(wide, 0x100003, 0, nil, 3, 0x40110000, nil)
        if handle ~= win.invalidHandle then return new(handle, false, DEFAULT_TIMEOUT, DEFAULT_MAX) end
        code = tonumber(k.GetLastError())
        if code ~= 231 and code ~= 2 and code ~= 3 then return win.Error("CreateFileW(pipe)", code) end
        local left = remaining(deadline)
        if left == 0 then return false end
        if code == 231 then
            if k.WaitNamedPipeW(wide, left) == 0 then
                code = tonumber(k.GetLastError())
                if code == 121 then return false end
                if code ~= 2 and code ~= 3 then return win.Error("WaitNamedPipeW", code) end
            end
        else
            k.Sleep(math.min(10, left))
        end
    until remaining(deadline) == 0
    return false
end

local function transfer(state, action, buffer, length, deadline, alreadyStarted)
    local offset = 0
    while offset < length do
        local size, code = operation(state, action, buffer + offset, length - offset, deadline)
        if size == false then
            -- An aborted write can have published a prefix inside NPFS.
            if offset > 0 or alreadyStarted or action == "WriteFile" then disconnect(state) end
            return false
        end
        if not size or size == 0 then
            disconnect(state)
            return win.Error(action .. "(pipe)", code or 109)
        end
        offset = offset + size
        if offset < length and remaining(deadline) == 0 then
            disconnect(state)
            return false
        end
    end
    return true
end

function M.PipeWrite(conn, bytes, timeoutMs)
    local state, err, code = get(conn, false, true)
    if not state then return nil, err, code end
    if type(bytes) ~= "string" or #bytes > state.maximum then
        return win.Error("Invalid pipe message or message limit exceeded", 87)
    end
    local timeout
    timeout, err, code = win.Timeout(timeoutMs, state.timeout)
    if not timeout then return nil, err, code end
    local deadline = tonumber(k.GetTickCount64()) + timeout
    local frame = ffi.new("uint8_t[?]", #bytes + 4)
    ffi.cast("uint32_t *", frame)[0] = #bytes
    ffi.copy(frame + 4, bytes, #bytes)
    return transfer(state, "WriteFile", frame, #bytes + 4, deadline)
end

function M.PipeRead(conn, timeoutMs)
    local state, err, code = get(conn, false, true)
    if not state then return nil, err, code end
    local timeout
    timeout, err, code = win.Timeout(timeoutMs, state.timeout)
    if not timeout then return nil, err, code end
    local deadline = tonumber(k.GetTickCount64()) + timeout
    local header = ffi.new("uint32_t[1]")
    local ok
    ok, err, code = transfer(state, "ReadFile", ffi.cast("uint8_t *", header), 4, deadline)
    if not ok then return ok, err, code end
    local size = tonumber(header[0])
    if size > state.maximum then
        disconnect(state)
        return win.Error("Received pipe message exceeds limit", 234)
    end
    if size == 0 then return "" end
    local bytes = ffi.new("uint8_t[?]", size)
    ok, err, code = transfer(state, "ReadFile", bytes, size, deadline, true)
    if not ok then return ok, err, code end
    return ffi.string(bytes, size)
end

function M.PipeDisconnect(server)
    local state, err, code = get(server, true)
    if not state then return nil, err, code end
    -- A client can connect at the OS level before PipeAccept records it.
    return disconnect(state)
end

function M.PipeClose(object)
    local state = objects[object]
    if not state then return win.Error("Invalid pipe", 6) end
    if state.handle then
        local ok, err, code = win.Close(state.handle)
        if not ok then return nil, err, code end
        state.handle, state.connected = nil, false
    end
    if state.event then
        local ok, err, code = win.Close(state.event)
        if not ok then return nil, err, code end
        state.event = nil
    end
    return true
end

function M.PipePeerPidGet(conn)
    local state, err, code = get(conn, false, true)
    if not state then return nil, err, code end
    local name = state.server and "GetNamedPipeClientProcessId" or "GetNamedPipeServerProcessId"
    local query = win.Symbol(k, name)
    if not query then return win.Error(name, 127) end
    local pid = ffi.new("unsigned long[1]")
    if query(state.handle, pid) == 0 then return win.Error(name) end
    return tonumber(pid[0])
end

for name, method in pairs(require("_win_shared_memory")) do
    M[name] = method
end

-- Lazy loading keeps pipe-only programs independent of window callbacks.
function M.CommandListen(...) return require("_window_ipc").Listen(...) end
function M.CommandPost(...) return require("_window_ipc").Post(...) end
function M.CommandClose(...) return require("_window_ipc").Close(...) end
jit.off(M.CommandListen, true)
jit.off(M.CommandClose, true)
return M
