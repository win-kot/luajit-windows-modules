local ffi = require("ffi")
local win = require("_win_extension")
local native = require("_win_native")
local errors = require("_errors")
local k = win.kernel
local M = {}
ffi.cdef[[
typedef struct {
    unsigned long size;
    uint16_t *scheme;
    unsigned long schemeLength;
    int schemeId;
    uint16_t *host;
    unsigned long hostLength;
    uint16_t port;
    uint16_t *user;
    unsigned long userLength;
    uint16_t *password;
    unsigned long passwordLength;
    uint16_t *path;
    unsigned long pathLength;
    uint16_t *extra;
    unsigned long extraLength;
} fw_url_components;
int __stdcall WinHttpCrackUrl(const uint16_t *, unsigned long, unsigned long, fw_url_components *);
void *__stdcall WinHttpOpen(const uint16_t *, unsigned long, const uint16_t *, const uint16_t *, unsigned long);
void *__stdcall WinHttpConnect(void *, const uint16_t *, uint16_t, unsigned long);
void *__stdcall WinHttpOpenRequest(void *, const uint16_t *, const uint16_t *, const uint16_t *,
    const uint16_t *, const uint16_t **, unsigned long);
int __stdcall WinHttpSetTimeouts(void *, int, int, int, int);
int __stdcall WinHttpSetOption(void *, unsigned long, void *, unsigned long);
int __stdcall WinHttpSendRequest(void *, const uint16_t *, unsigned long, const void *,
    unsigned long, unsigned long, uintptr_t);
int __stdcall WinHttpReceiveResponse(void *, void *);
int __stdcall WinHttpQueryOption(void *, unsigned long, void *, unsigned long *);
int __stdcall WinHttpQueryHeaders(void *, unsigned long, const uint16_t *, void *, unsigned long *, unsigned long *);
int __stdcall WinHttpReadData(void *, void *, unsigned long, unsigned long *);
int __stdcall WinHttpWriteData(void *, const void *, unsigned long, unsigned long *);
int __stdcall WinHttpCloseHandle(void *);
int __stdcall IdnToAscii(unsigned long, const uint16_t *, int, uint16_t *, int);
void *__stdcall LoadLibraryExW(const uint16_t *, void *, unsigned long);
void *__stdcall GetProcAddress(void *, const char *);
int __stdcall FreeLibrary(void *);
typedef unsigned long (*fw_http_attach_fn)(void *, void **);
typedef unsigned long (*fw_http_send_fn)(void *, void *, const uint16_t *, unsigned long,
    const void *, unsigned long, unsigned long, unsigned long);
typedef unsigned long (*fw_http_write_fn)(void *, void *, const void *, unsigned long, unsigned long);
typedef unsigned long (*fw_http_receive_fn)(void *, void *, unsigned long);
typedef unsigned long (*fw_http_read_fn)(void *, void *, const char **, unsigned long *, unsigned long);
typedef void (*fw_http_release_fn)(void *);
]]
local moduleSource = debug.getinfo(1, "S").source
local moduleDir = moduleSource:match("^@(.*)[/\\]")
if moduleSource:sub(1, 1) == "@" and not moduleDir then moduleDir = "." end
local bridgePath, bridgePathError, bridgePathCode
if moduleDir then bridgePath, bridgePathError, bridgePathCode = native.PathWide(moduleDir .. "\\FwWinHttp64.dll") end
local bridge, bridgeError, bridgeCode

local function loadBridge()
    if bridge ~= nil then return bridge, bridgeError, bridgeCode end
    local wide, message, code = bridgePath, bridgePathError, bridgePathCode
    if not moduleDir then
        local exe; exe, message, code = native.ExePath()
        local folder = exe and exe:match("^(.*)[/\\]")
        if folder then
            wide, message, code = win.PathWide(folder .. "\\FwWinHttp64.dll")
        end
    end
    bridge = false
    if not wide then bridgeError, bridgeCode = message or "Не удалось определить путь к FwWinHttp64.dll", code; return bridge, bridgeError, bridgeCode end
    -- An absolute path and System32-only imports keep the working directory out of DLL resolution.
    -- Hold the loaded module for the lifetime of the process: WinHTTP may still call it after cancellation.
    local library = k.LoadLibraryExW(wide, nil, 0x800)
    if library == nil then bridgeCode = tonumber(k.GetLastError()); return bridge, bridgeError, bridgeCode end
    local methods = {}
    for _, name in ipairs({"attach", "send", "receive", "read", "write", "release"}) do
        local symbol = k.GetProcAddress(library, "fw_http_" .. (name == "send" and "send_v2" or name))
        if symbol == nil then
            bridgeCode = tonumber(k.GetLastError())
            k.FreeLibrary(library)
            return bridge, bridgeError, bridgeCode
        end
        methods[name] = ffi.cast("fw_http_" .. name .. "_fn", symbol)
    end
    bridge = methods
    return bridge
end
local TOKEN = "^[!#$%%&'*+%.%^_\096|~%w%-]+$"
local function urlParts(dll, url)
    if type(url) ~= "string" or url:find("[%z\1-\31\127\\]") or not url:lower():match("^https?://") then
        return win.Error("Expected absolute HTTP or HTTPS URL", 12005)
    end
    local wide, units, code = win.ToWide(url)
    if not wide then return nil, units, code end
    local fragment = url:find("#", 1, true)
    if fragment then
        url = url:sub(1, fragment - 1)
        wide, units = win.ToWide(url)
    end
    local parts = ffi.new("fw_url_components[1]")
    parts[0].size = ffi.sizeof(parts[0])
    parts[0].hostLength, parts[0].pathLength = 1, 1
    parts[0].userLength, parts[0].passwordLength, parts[0].extraLength = 1, 1, 1
    if dll.WinHttpCrackUrl(wide, units, 0, parts) == 0 then return win.Error("WinHttpCrackUrl") end
    local p = parts[0]
    if p.hostLength == 0 or p.userLength ~= 0 or p.passwordLength ~= 0 or
        url:match("^[^:]+://[^/?]*@") then
        return win.Error("Invalid HTTP host or embedded credentials", 12005)
    end
    local host, err
    host, err, code = win.FromWide(p.host, p.hostLength)
    if not host then return nil, err, code end
    local hostWide = win.ToWide(host)
    if host:find("[\128-\255]") then
        local idn
        idn, err, code = win.Library("normaliz")
        if not idn then return nil, err, code end
        local n = idn.IdnToAscii(2, hostWide, -1, nil, 0)
        if n <= 0 then return win.Error("IdnToAscii") end
        local ascii = ffi.new("uint16_t[?]", n)
        if idn.IdnToAscii(2, hostWide, -1, ascii, n) == 0 then return win.Error("IdnToAscii") end
        hostWide = ascii
    end
    local path
    path, err, code = win.FromWide(p.path, p.pathLength)
    if not path then return nil, err, code end
    local query
    query, err, code = win.FromWide(p.extra, p.extraLength)
    if not query then return nil, err, code end
    local target; target, err, code = win.ToWide((path == "" and "/" or path) .. query)
    if not target then return nil, err, code end
    return {host = hostWide, hostName = host, port = p.port, secure = url:lower():match("^https:") ~= nil,
        target = target}
end

local function headersWide(headers)
    if headers == nil then return false, 0 end
    if type(headers) ~= "table" then return win.Error("headers must be a table", 87) end
    local lines, seen = {}, {}
    for name, value in pairs(headers) do
        if type(name) ~= "string" or not name:match(TOKEN) or type(value) ~= "string" or
            value:find("[%z\1-\8\10-\31\127]") then
            return win.Error("Invalid HTTP header", 87)
        end
        local lower = name:lower()
        if seen[lower] or lower == "content-length" or lower == "transfer-encoding" then
            return win.Error("Duplicate header or managed body length", 87)
        end
        seen[lower] = true
        lines[#lines + 1] = name .. ": " .. value .. "\r\n"
    end
    if #lines == 0 then return false, 0 end
    table.sort(lines)
    return win.ToWide(table.concat(lines))
end

local function timeout(value)
    if value == nil then return 15000 end
    if win.Integer(value, 1, 0x7FFFFFFF) then return value end
end

local function config(method, options, download)
    if options == nil then options = {} end
    if type(options) ~= "table" or type(method) ~= "string" or not method:match(TOKEN) then
        return win.Error("Invalid HTTP method or options", 87)
    end
    local connect, send, receive = timeout(options.connectTimeoutMs), timeout(options.sendTimeoutMs),
        timeout(options.receiveTimeoutMs)
    local redirects = options.maxRedirects
    if redirects == nil then redirects = 10 end
    local maximum = options.maxBodyBytes
    if maximum == nil then maximum = download and math.huge or 16 * 1024 * 1024 end
    local body = options.body
    if body == nil then body = "" end
    local onProgress = options.onProgress
    if onProgress ~= nil and (not download or type(onProgress) ~= "function") then
        return win.Error("onProgress must be a function for http.Download", 87)
    end
    if not connect or not send or not receive or not win.Integer(redirects, 0, 100) or
        (options.timeoutMs ~= nil and not win.Integer(options.timeoutMs, 1, 0x7FFFFFFF)) or
        (options.maxBodyBytes ~= nil and not win.Integer(maximum, 0, 9007199254740991)) or
        (not download and maximum > 0x7FFFFFFF) or type(body) ~= "string" or #body > 0x7FFFFFFF or
        (options.overwrite ~= nil and type(options.overwrite) ~= "boolean") then
        return win.Error("Invalid HTTP timeout, redirect limit, body or size limit", 87)
    end
    local headers, units, code = headersWide(options.headers)
    if headers == nil then return nil, units, code end
    -- WinHTTP forwards custom headers unchanged on redirects.
    if headers or body ~= "" or (method ~= "GET" and method ~= "HEAD") then redirects = 0 end
    return {method = win.ToWide(method), headers = headers, headerUnits = units, body = body,
        connect = connect, send = send, receive = receive, redirects = redirects,
        totalTimeout = options.timeoutMs, maximum = maximum, overwrite = options.overwrite,
        onProgress = onProgress}
end

local function wideQuery(query, operation)
    local size = ffi.new("unsigned long[1]")
    if query(nil, size) ~= 0 then return "" end
    local code = tonumber(k.GetLastError())
    if code ~= 122 or size[0] == 0 then return win.Error(operation, code) end
    local buffer = ffi.new("uint16_t[?]", math.ceil(tonumber(size[0]) / 2) + 1)
    if query(buffer, size) == 0 then return win.Error(operation) end
    return win.FromWide(buffer)
end

local function metadata(dll, request)
    local value, size = ffi.new("unsigned long[1]"), ffi.new("unsigned long[1]", 4)
    if dll.WinHttpQueryHeaders(request, 0x20000013, nil, value, size, nil) == 0 then
        return win.Error("WinHttpQueryHeaders(status)")
    end
    local raw, err, code = wideQuery(function(buffer, bytes)
        return dll.WinHttpQueryHeaders(request, 22, nil, buffer, bytes, nil)
    end, "WinHttpQueryHeaders(headers)")
    if not raw then return nil, err, code end
    local final
    final, err, code = wideQuery(function(buffer, bytes)
        return dll.WinHttpQueryOption(request, 34, buffer, bytes)
    end, "WinHttpQueryOption(URL)")
    if not final then return nil, err, code end
    local headers = {}
    for line in raw:gmatch("[^\r\n]+") do
        local name, valueText = line:match("^([^:]+):[ \t]*(.*)$")
        if name and name:match(TOKEN) then
            name = name:lower()
            if not headers[name] then headers[name] = {} end
            headers[name][#headers[name] + 1] = valueText
        end
    end
    return {status = tonumber(value[0]), headers = headers, finalUrl = final}
end

local function expectedBodyLength(response, method)
    local lengths = response.headers["content-length"]
    if method:upper() == "HEAD" or response.status < 200 or response.status == 204 or
        response.status == 304 or not lengths or response.headers["transfer-encoding"] then
        return false
    end
    local text = lengths[1]:match("^%s*(%d+)%s*$")
    local expected = text and tonumber(text)
    if not win.Integer(expected, 0, 9007199254740991) then
        return win.Error("Invalid HTTP Content-Length", 13)
    end
    return expected
end

local function timeLeft(opts, limit)
    if not opts.deadline then return limit end
    return math.max(0, math.min(limit, opts.deadline - tonumber(k.GetTickCount64())))
end

local function stream(dll, request, opts, expected, consume)
    local maximum = opts.maximum
    if expected and expected > maximum then return win.Error("HTTP body exceeds maxBodyBytes", 223) end
    local buffer = not opts.async and ffi.new("char[65536]")
    local data = opts.async and ffi.new("const char *[1]")
    local count = ffi.new("unsigned long[1]")
    local total = 0
    while true do
        if opts.async then
            local left = timeLeft(opts, opts.receive)
            if left == 0 then return win.Error("WinHttpReadData", 12002) end
            local status = opts.async.read(request, opts.state, data, count, left)
            if status ~= 0 then return win.Error("WinHttpReadData", status) end
            if timeLeft(opts, 1) == 0 then return win.Error("WinHttpReadData", 12002) end
            buffer = data[0]
        elseif dll.WinHttpReadData(request, buffer, 65536, count) == 0 then
            return win.Error("WinHttpReadData")
        end
        local n = tonumber(count[0])
        if n == 0 then
            if expected and total ~= expected then return win.Error("Incomplete HTTP body", 38) end
            return total
        end
        if n > maximum - total then return win.Error("HTTP body exceeds maxBodyBytes", 223) end
        total = total + n
        local ok, err, code = consume(ffi.string(buffer, n), total)
        if not ok then return nil, err, code end
    end
end

local function withRequest(method, url, options, download, consume, upload)
    local opts, err, code = config(method, options, download)
    if not opts then return nil, err, code end
    if upload and opts.body ~= "" then return win.Error("Upload cannot include options.body", 87) end
    if opts.totalTimeout then opts.deadline = tonumber(k.GetTickCount64()) + opts.totalTimeout end
    opts.async, err, code = loadBridge()
    if not opts.async and opts.totalTimeout then
        if err then return nil, "Для HTTP timeoutMs нужна FwWinHttp64.dll: " .. err, code end
        return win.Error("загрузку FwWinHttp64.dll для HTTP timeoutMs", code)
    end
    local dll
    dll, err, code = win.Library("winhttp")
    if not dll then return nil, err, code end
    local address
    address, err, code = urlParts(dll, url)
    if not address then return nil, err, code end
    local session = dll.WinHttpOpen(win.ToWide("LuaJIT FrameWork"), 4, nil, nil, opts.async and 0x10000000 or 0)
    if session == nil then return win.Error("WinHttpOpen") end
    ffi.gc(session, dll.WinHttpCloseHandle)
    local connection, request
    local function execute()
        if dll.WinHttpSetTimeouts(session, opts.connect, opts.connect, opts.send, opts.receive) == 0 then
            return win.Error("WinHttpSetTimeouts")
        end
        local redirect = ffi.new("unsigned long[1]", opts.redirects == 0 and 0 or 1)
        if dll.WinHttpSetOption(session, 88, redirect, 4) == 0 then return win.Error("WinHttpSetOption(redirect policy)") end
        if opts.redirects > 0 then
            local max = ffi.new("unsigned long[1]", opts.redirects)
            if dll.WinHttpSetOption(session, 89, max, 4) == 0 then return win.Error("WinHttpSetOption(redirect limit)") end
        end
        connection = dll.WinHttpConnect(session, address.host, address.port, 0)
        if connection == nil then return win.Error("WinHttpConnect", nil, address.hostName) end
        ffi.gc(connection, dll.WinHttpCloseHandle)
        request = dll.WinHttpOpenRequest(connection, opts.method, address.target, nil, nil, nil,
            address.secure and 0x00800000 or 0)
        if request == nil then return win.Error("WinHttpOpenRequest", nil, address.hostName) end
        ffi.gc(request, dll.WinHttpCloseHandle)
        if dll.WinHttpSetTimeouts(request, opts.connect, opts.connect, opts.send, opts.receive) == 0 then
            return win.Error("WinHttpSetTimeouts(request)")
        end
        local responseTimeout = ffi.new("unsigned long[1]", opts.receive)
        if dll.WinHttpSetOption(request, 7, responseTimeout, 4) == 0 then
            return win.Error("WinHttpSetOption(receive response timeout)")
        end
        local rejectUserInfo = ffi.new("unsigned long[1]", 1)
        if dll.WinHttpSetOption(request, 100, rejectUserInfo, 4) == 0 then
            return win.Error("WinHttpSetOption(reject URL credentials)")
        end
        local autologon = ffi.new("unsigned long[1]", 2)
        if dll.WinHttpSetOption(request, 77, autologon, 4) == 0 then return win.Error("WinHttpSetOption(autologon)") end
        local body = #opts.body > 0 and opts.body or nil
        local total = upload and upload.size or #opts.body
        if opts.async then
            local state = ffi.new("void *[1]")
            local status = opts.async.attach(request, state)
            if status ~= 0 then return win.Error("WinHttpSetStatusCallback", status) end
            opts.state = ffi.gc(state[0], opts.async.release)
            -- WinHTTP can delay SendRequest completion until the server starts replying.
            local left = timeLeft(opts, math.min(opts.connect * 2 + opts.send, opts.receive))
            if left == 0 then return win.Error("WinHttpSendRequest", 12002, address.hostName) end
            status = opts.async.send(request, opts.state, opts.headers or nil, opts.headerUnits, body, #opts.body, total, left)
            if status ~= 0 then return win.Error("WinHttpSendRequest", status, address.hostName) end
            if upload then
                local sent, reason, errorCode = upload.write(function(chunk)
                    local remaining = timeLeft(opts, opts.send)
                    if remaining == 0 then return win.Error("WinHttpWriteData", 12002) end
                    local result = opts.async.write(request, opts.state, chunk, #chunk, remaining)
                    if result ~= 0 then return win.Error("WinHttpWriteData", result) end
                    return true
                end)
                if not sent then return nil, reason, errorCode end
            end
            left = timeLeft(opts, opts.receive)
            if left == 0 then return win.Error("WinHttpReceiveResponse", 12002, address.hostName) end
            status = opts.async.receive(request, opts.state, left)
            if status ~= 0 then return win.Error("WinHttpReceiveResponse", status, address.hostName) end
        else
            if dll.WinHttpSendRequest(request, opts.headers or nil, opts.headerUnits, body,
                #opts.body, total, 0) == 0 then return win.Error("WinHttpSendRequest", nil, address.hostName) end
            if upload then
                local count = ffi.new("unsigned long[1]")
                local sent, reason, errorCode = upload.write(function(chunk)
                    if dll.WinHttpWriteData(request, chunk, #chunk, count) == 0 then
                        return win.Error("WinHttpWriteData")
                    end
                    if count[0] ~= #chunk then return win.Error("Incomplete HTTP upload", 29) end
                    return true
                end)
                if not sent then return nil, reason, errorCode end
            end
            if dll.WinHttpReceiveResponse(request, nil) == 0 then return win.Error("WinHttpReceiveResponse", nil, address.hostName) end
        end
        local response, message, status = metadata(dll, request)
        if not response then return nil, message, status end
        if timeLeft(opts, 1) == 0 then return win.Error("HTTP request deadline", 12002) end
        return consume(response, dll, request, opts)
    end
    local ok, result, message, status = pcall(execute)
    if request ~= nil then dll.WinHttpCloseHandle(ffi.gc(request, nil)) end
    if opts.state then opts.async.release(ffi.gc(opts.state, nil)) end
    if connection ~= nil then dll.WinHttpCloseHandle(ffi.gc(connection, nil)) end
    dll.WinHttpCloseHandle(ffi.gc(session, nil))
    if not ok then error(result, 0) end
    return result, message, status
end

local function requestResponse(method, url, options, upload)
    return withRequest(method, url, options, false, function(response, dll, request, opts)
        local expected, err, code = expectedBodyLength(response, method)
        if expected == nil then return nil, err, code end
        local chunks = {}
        local total, message, status = stream(dll, request, opts, expected, function(chunk)
            chunks[#chunks + 1] = chunk
            return true
        end)
        if not total then return nil, message, status end
        response.body = table.concat(chunks)
        return response
    end, upload)
end

function M.Request(method, url, options) return requestResponse(method, url, options) end

function M.Upload(url, path, options)
    local file, err, code = require("fs").Open(path, "r", {share = "read"})
    if not file then return nil, err, code end
    local ok, result, message, status = pcall(function()
        local size, reason, resultCode = file:GetSize()
        if size == nil then return nil, reason, resultCode end
        if type(size) ~= "number" or size >= 0xFFFFFFFF then
            return win.Error("HTTP upload exceeds the supported file size", 223)
        end
        return requestResponse("POST", url, options, {
            size = size,
            write = function(send)
                local left = size
                while left > 0 do
                    local bytes, detail, number = file:Read(math.min(left, 65536))
                    if bytes == nil then return nil, detail, number end
                    if bytes == "" then return win.Error("HTTP upload file was truncated", 38) end
                    local sent
                    sent, detail, number = send(bytes)
                    if not sent then return nil, detail, number end
                    left = left - #bytes
                end
                return true
            end
        })
    end)
    local closed, closeError, closeCode = file:Close()
    if not ok then error(result, 0) end
    if result and not closed then return nil, closeError, closeCode end
    return result, message, status
end

function M.Get(url, options) return M.Request("GET", url, options) end
function M.Head(url, options) return M.Request("HEAD", url, options) end

function M.Post(url, body, options)
    if options ~= nil and type(options) ~= "table" then return win.Error("Invalid HTTP options", 87) end
    local opts = {}
    for name, value in pairs(options or {}) do opts[name] = value end
    if body ~= nil then opts.body = body end
    return M.Request("POST", url, opts)
end

function M.Download(url, destination, options)
    local wide, err, code = win.PathWide(destination)
    if not wide then return nil, err, code end
    local absolute
    absolute, err, code = win.FromWide(wide)
    if not absolute then return nil, err, code end
    local directory, basename = absolute:match("^(.*\\)([^\\]+)$")
    if not directory or basename:find(":", 1, true) or absolute:sub(1, 4) ~= "\\\\?\\" then
        return win.Error("Download requires a file destination", 87)
    end
    return withRequest("GET", url, options, true, function(response, dll, request, opts)
        if response.status < 200 or response.status >= 300 then return response end
        if response.status == 206 then return win.Error("Download received a partial HTTP representation", 13) end
        local expected, reason, errorCode = expectedBodyLength(response, "GET")
        if expected == nil then return nil, reason, errorCode end
        local handle, part, tempCode = native.FsMkstemp(directory .. ".framework-download.part-XXXXXX")
        if not handle then return nil, part, tempCode end
        local total, message, status = stream(dll, request, opts, expected, function(chunk, bytesWritten)
            local written, detail, writeCode = native.FsWrite(handle, chunk)
            if not written then return nil, detail, writeCode end
            if written ~= #chunk then return win.Error("Short file write", 29) end
            if opts.onProgress then
                local ok, decision = pcall(opts.onProgress, bytesWritten, expected or nil)
                if not ok then
                    return errors.Callback("Сбой в обработчике хода загрузки", decision)
                end
                if decision == false then return win.Error("HTTP download cancelled", 1223) end
            end
            return true
        end)
        if total then
            local ok, detail, flushCode = native.FsFsync(handle)
            if not ok then total, message, status = nil, detail, flushCode end
        end
        local closed, detail, closeCode = native.FsClose(handle)
        if not closed and total then total, message, status = nil, detail, closeCode end
        if total and timeLeft(opts, 1) == 0 then
            total, message, status = win.Error("HTTP download deadline", 12002)
        end
        if total then
            local partWide = win.ToWide(part)
            if k.MoveFileExW(partWide, wide, opts.overwrite and 1 or 0) ~= 0 then
                response.path, response.bytes = destination, total
                return response
            end
            total, message, status = win.Error("MoveFileExW(download)")
        end
        local removed, cleanup = native.FsUnlink(part)
        if not removed then message = message .. " | cleanup: " .. cleanup end
        return nil, message, status
    end)
end

return M
