local ffi = require("ffi")
local win = require("_win_extension")
local k = win.kernel
local M = {}

ffi.cdef[[
typedef struct {
    union {
        const uint16_t *text;
        uint8_t byte;
        uint16_t word;
        uint32_t dword;
        uint64_t qword;
        int32_t boolean;
    } value;
    uint32_t count, type;
} fw_evt_variant;
typedef struct {
    uint16_t year, month, dayOfWeek, day, hour, minute, second, milliseconds;
} fw_evt_system_time;

int __stdcall EvtClose(void *);
void *__stdcall EvtOpenChannelEnum(void *, uint32_t);
int __stdcall EvtNextChannelPath(void *, uint32_t, uint16_t *, uint32_t *);
void *__stdcall EvtOpenChannelConfig(void *, const uint16_t *, uint32_t);
int __stdcall EvtGetChannelConfigProperty(void *, int, uint32_t, uint32_t, fw_evt_variant *, uint32_t *);
void *__stdcall EvtOpenLog(void *, const uint16_t *, uint32_t);
int __stdcall EvtGetLogInfo(void *, int, uint32_t, fw_evt_variant *, uint32_t *);
int __stdcall EvtExportLog(void *, const uint16_t *, const uint16_t *, const uint16_t *, uint32_t);
void *__stdcall EvtQuery(void *, const uint16_t *, const uint16_t *, uint32_t);
int __stdcall EvtNext(void *, uint32_t, void **, uint32_t, uint32_t, uint32_t *);
void *__stdcall EvtCreateRenderContext(uint32_t, const uint16_t **, uint32_t);
int __stdcall EvtRender(void *, void *, uint32_t, uint32_t, void *, uint32_t *, uint32_t *);
int __stdcall fw_evt_FileTimeToSystemTime(const uint64_t *, fw_evt_system_time *) __asm__("FileTimeToSystemTime");
]]

local INSUFFICIENT_BUFFER, NO_MORE_ITEMS, TIMEOUT = 122, 259, 1460
local MAX_BUFFER = 16 * 1024 * 1024
local variantSize = ffi.sizeof("fw_evt_variant")
local channelTypes = {[0] = "admin", [1] = "operational", [2] = "analytic", [3] = "debug"}

local function withHandle(dll, operation, acquire, use)
    local handle = acquire()
    if handle == nil then return win.Error(operation) end
    local ok, result, message, status = pcall(use, handle)
    local closed = dll.EvtClose(handle)
    local closeCode = closed == 0 and k.GetLastError()
    if not ok then error(result, 0) end
    if result ~= nil and closed == 0 then return win.Error("EvtClose", closeCode) end
    return result, message, status
end

local function readBuffer(operation, call, initialBytes, unitSize)
    local size = initialBytes
    local used = ffi.new("uint32_t[1]")
    for _ = 1, 4 do
        local buffer = ffi.new("uint8_t[?]", size * unitSize)
        if call(size, buffer, used) ~= 0 then return buffer, used[0] end
        local code = tonumber(k.GetLastError())
        if code ~= INSUFFICIENT_BUFFER then return win.Error(operation, code) end
        if used[0] <= size or used[0] > MAX_BUFFER / unitSize then
            return win.Error(operation .. " buffer limit", 223)
        end
        size = used[0]
    end
    return win.Error(operation .. " buffer changed", INSUFFICIENT_BUFFER)
end

local function channelWide(channel)
    if type(channel) ~= "string" or channel == "" then return win.Error("Expected a channel name", 87) end
    return win.ToWide(channel)
end

local function variant(value)
    local t, data = value.type, value.value
    if t == 0 then return nil end
    if t == 1 then
        if data.text == nil then return nil end
        return win.FromWide(data.text)
    end
    if t == 4 then return data.byte end
    if t == 6 then return data.word end
    if t == 8 then return data.dword end
    if t == 10 or t == 17 or t == 21 then return win.Exact(data.qword) end
    if t == 13 then return data.boolean ~= 0 end
    return win.Error("Unexpected EVT_VARIANT type " .. t, 13)
end

local function formatUtc(ticks)
    local fileTime = ffi.new("uint64_t[1]", ticks)
    local systemTime = ffi.new("fw_evt_system_time[1]")
    if k.fw_evt_FileTimeToSystemTime(fileTime, systemTime) == 0 then
        return win.Error("FileTimeToSystemTime")
    end
    local t = systemTime[0]
    return ("%04d-%02d-%02dT%02d:%02d:%02d.%07dZ"):format(
        t.year, t.month, t.day, t.hour, t.minute, t.second, tonumber(ticks % 10000000ULL))
end

function M.ChannelsGet()
    local dll, err, code = win.Library("wevtapi")
    if not dll then return nil, err, code end
    return withHandle(dll, "EvtOpenChannelEnum", function() return dll.EvtOpenChannelEnum(nil, 0) end,
        function(enumerator)
            local channels = {}
            while true do
                local buffer, message, status = readBuffer("EvtNextChannelPath", function(size, data, used)
                    return dll.EvtNextChannelPath(enumerator, size, ffi.cast("uint16_t *", data), used)
                end, 256, 2)
                if not buffer then
                    if status == NO_MORE_ITEMS then
                        table.sort(channels)
                        return channels
                    end
                    return nil, message, status
                end
                local name
                name, message, status = win.FromWide(ffi.cast("uint16_t *", buffer))
                if not name then return nil, message, status end
                channels[#channels + 1] = name
            end
        end)
end

function M.ChannelInfoGet(channel)
    local wide, err, code = channelWide(channel)
    if not wide then return nil, err, code end
    local dll
    dll, err, code = win.Library("wevtapi")
    if not dll then return nil, err, code end
    return withHandle(dll, "EvtOpenChannelConfig", function() return dll.EvtOpenChannelConfig(nil, wide, 0) end,
        function(handle)
            local result = {channel = channel}
            for index, field in ipairs({"enabled", "isolationCode", "typeCode", "owningPublisher", "classic"}) do
                local buffer, message, status = readBuffer("EvtGetChannelConfigProperty", function(size, data, used)
                    return dll.EvtGetChannelConfigProperty(handle, index - 1, 0, size,
                        ffi.cast("fw_evt_variant *", data), used)
                end, 256, 1)
                if not buffer then return nil, message, status end
                result[field], message, status = variant(ffi.cast("fw_evt_variant *", buffer)[0])
                if message then return nil, message, status end
            end
            result.type = channelTypes[result.typeCode] or "unknown"
            return result
        end)
end

local logProperties = {{2, "lastWriteUtc"}, {3, "sizeBytes"}, {5, "recordCount"},
    {6, "oldestRecordNumber"}, {7, "full"}}
local function logInfo(source, file)
    local wide, err, code = (file and win.PathWide or channelWide)(source)
    if not wide then return nil, err, code end
    local dll
    dll, err, code = win.Library("wevtapi")
    if not dll then return nil, err, code end
    local flags = file and 2 or 1
    return withHandle(dll, "EvtOpenLog", function() return dll.EvtOpenLog(nil, wide, flags) end, function(handle)
        local data, used = ffi.new("fw_evt_variant[1]"), ffi.new("uint32_t[1]")
        local result = file and {path = source} or {channel = source}
        for _, property in ipairs(logProperties) do
            local id, field = property[1], property[2]
            if dll.EvtGetLogInfo(handle, id, variantSize, data, used) == 0 then
                return win.Error("EvtGetLogInfo(" .. field .. ")")
            end
            local value, message, status
            if id == 2 and data[0].type == 17 then
                value, message, status = formatUtc(data[0].value.qword)
            else
                value, message, status = variant(data[0])
            end
            if message then return nil, message, status end
            result[field] = value
        end
        return result
    end)
end

function M.LogInfoGet(channel) return logInfo(channel, false) end
function M.FileInfoGet(path) return logInfo(path, true) end

local fields = {
    [0] = "provider", [2] = "eventId", [3] = "qualifiers", [4] = "level", [5] = "task",
    [6] = "opcode", [7] = "keywords", [8] = "time100ns", [9] = "recordId",
    [12] = "processId", [13] = "threadId", [14] = "channel", [15] = "computer", [17] = "version"
}

local function eventInfo(dll, context, event, includeXml)
    local count = ffi.new("uint32_t[1]")
    local buffer, err, code = readBuffer("EvtRender(system)", function(size, data, used)
        return dll.EvtRender(context, event, 0, size, data, used, count)
    end, 1024, 1)
    if not buffer then return nil, err, code end
    if count[0] * variantSize > err then return win.Error("Invalid event property count", 13) end
    local data = ffi.cast("fw_evt_variant *", buffer)
    local result = {}
    for index, field in pairs(fields) do
        if index < count[0] then
            local message
            result[field], message, code = variant(data[index])
            if message then return nil, message, code end
        end
    end
    if result.time100ns then
        result.timeUtc, err, code = formatUtc(data[8].value.qword)
        if not result.timeUtc then return nil, err, code end
    end
    if includeXml then
        local xml
        xml, err, code = readBuffer("EvtRender(XML)", function(size, out, used)
            return dll.EvtRender(nil, event, 1, size, out, used, count)
        end, 4096, 1)
        if not xml then return nil, err, code end
        result.xml, err, code = win.FromWide(ffi.cast("uint16_t *", xml))
        if not result.xml then return nil, err, code end
    end
    return result
end
jit.off(eventInfo, true)

local function readEvents(dll, query, context, limit, timeout, includeXml)
    local batchSize = 16
    local handles = ffi.new("void *[?]", batchSize)
    local count = ffi.new("uint32_t[1]")
    local events, xmlBytes = {}, 0
    while #events < limit do
        count[0] = 0
        if dll.EvtNext(query, math.min(batchSize, limit - #events), handles, timeout, 0, count) == 0 then
            local code = tonumber(k.GetLastError())
            if code == NO_MORE_ITEMS then return events, false end
            if code == TIMEOUT then return events, true end
            return win.Error("EvtNext", code)
        end
        if count[0] == 0 then return events, false end
        local ok, accepted, message, status = pcall(function()
            for index = 0, count[0] - 1 do
                local event, err, code = eventInfo(dll, context, handles[index], includeXml)
                if not event then return nil, err, code end
                if event.xml then
                    xmlBytes = xmlBytes + #event.xml
                    if xmlBytes > MAX_BUFFER then return win.Error("Event XML output exceeds 16 MiB", 223) end
                end
                events[#events + 1] = event
            end
            return true
        end)
        local closeCode
        for index = 0, count[0] - 1 do
            if dll.EvtClose(handles[index]) == 0 then closeCode = k.GetLastError() end
            handles[index] = nil
        end
        if not ok then error(accepted, 0) end
        if not accepted then return nil, message, status end
        if closeCode then return win.Error("EvtClose(event)", closeCode) end
    end
    return events, false
end

local function queryWide(filter)
    if filter == nil then filter = "*" end
    if type(filter) ~= "string" or filter == "" or filter:match("^%s*<") then
        return win.Error("Expected an XPath event query", 87)
    end
    return win.ToWide(filter)
end

local function read(source, options, file)
    if options == nil then options = {} end
    if type(options) ~= "table" then return win.Error("Expected event query options", 87) end
    local limit = options.limit
    if limit == nil then limit = 50 end
    if not win.Integer(limit, 1, 1000) or
        (options.newestFirst ~= nil and type(options.newestFirst) ~= "boolean") or
        (options.includeXml ~= nil and type(options.includeXml) ~= "boolean") then
        return win.Error("Invalid event query options", 87)
    end
    local wide, err, code = (file and win.PathWide or channelWide)(source)
    if not wide then return nil, err, code end
    local xpath
    xpath, err, code = queryWide(options.query)
    if not xpath then return nil, err, code end
    local timeout
    timeout, err, code = win.Timeout(options.timeoutMs, 5000)
    if not timeout then return nil, err, code end
    local dll
    dll, err, code = win.Library("wevtapi")
    if not dll then return nil, err, code end
    local direction = options.newestFirst == false and 0x100 or 0x200
    local flags = direction + (file and 2 or 1)
    return withHandle(dll, "EvtQuery", function() return dll.EvtQuery(nil, wide, xpath, flags) end, function(query)
        return withHandle(dll, "EvtCreateRenderContext", function() return dll.EvtCreateRenderContext(0, nil, 1) end,
            function(context) return readEvents(dll, query, context, limit, timeout, options.includeXml) end)
    end)
end

function M.Read(channel, options) return read(channel, options, false) end
function M.FileRead(path, options) return read(path, options, true) end

local function stagingDirectory(parent)
    local crypto = require("crypto")
    for _ = 1, 8 do
        local random, err, code = crypto.RandomBytes(12)
        if not random then return nil, err, code end
        local suffix = random:gsub(".", function(byte) return ("%02x"):format(byte:byte()) end)
        local path = parent .. ".fw-evtx-" .. suffix
        local wide
        wide, err, code = win.ToWide(path)
        if not wide then return nil, err, code end
        if k.CreateDirectoryW(wide, nil) ~= 0 then return path, wide end
        code = tonumber(k.GetLastError())
        if code ~= 183 and code ~= 80 then return win.Error("CreateDirectoryW(export staging)", code) end
    end
    return win.Error("Could not reserve an event export directory", 183)
end

local function cleanupExport(part, directory, published)
    local failure, status
    if not published and k.DeleteFileW(part) == 0 then
        local code = tonumber(k.GetLastError())
        if code ~= 2 and code ~= 3 then
            local _
            _, failure, status = win.Error("DeleteFileW(export staging)", code)
        end
    end
    if k.RemoveDirectoryW(directory) == 0 then
        local code = tonumber(k.GetLastError())
        if code ~= 2 and code ~= 3 and not failure then
            local _
            _, failure, status = win.Error("RemoveDirectoryW(export staging)", code)
        end
    end
    return failure, status
end

function M.Export(channel, destination, options)
    if options == nil then options = {} end
    if type(options) ~= "table" or (options.overwrite ~= nil and type(options.overwrite) ~= "boolean") then
        return win.Error("Invalid event export options", 87)
    end
    local source, err, code = channelWide(channel)
    if not source then return nil, err, code end
    local xpath
    xpath, err, code = queryWide(options.query)
    if not xpath then return nil, err, code end
    local target
    target, err, code = win.PathWide(destination)
    if not target then return nil, err, code end
    local absolute
    absolute, err, code = win.FromWide(target)
    if not absolute then return nil, err, code end
    local parent, name = absolute:match("^(.*\\)([^\\]+)$")
    if not parent or name:find(":", 1, true) or absolute:sub(1, 4) ~= "\\\\?\\" then
        return win.Error("Expected an event log file destination", 87)
    end
    local dll
    dll, err, code = win.Library("wevtapi")
    if not dll then return nil, err, code end

    if not options.overwrite then
        if k.GetFileAttributesW(target) ~= 0xFFFFFFFF then
            return win.Error("Event export destination already exists", 183)
        end
        code = tonumber(k.GetLastError())
        if code ~= 2 and code ~= 3 then return win.Error("GetFileAttributesW(event export)", code) end
    end

    local path, directory
    path, directory, code = stagingDirectory(parent)
    if not path then return nil, directory, code end
    local part
    part, err, code = win.ToWide(path .. "\\events.evtx")
    if not part then
        k.RemoveDirectoryW(directory)
        return nil, err, code
    end
    local action
    if dll.EvtExportLog(nil, source, xpath, part, 1) == 0 then
        code, action = tonumber(k.GetLastError()), "EvtExportLog"
    elseif k.MoveFileExW(part, target, options.overwrite and 1 or 0) == 0 then
        code, action = tonumber(k.GetLastError()), "MoveFileExW(event export)"
    end
    local cleanup, cleanupCode = cleanupExport(part, directory, not action)
    if not action then return true, cleanup, cleanupCode end
    local _, message = win.Error(action, code)
    if cleanup then message = message .. " | cleanup: " .. cleanup end
    return nil, message, code
end

return M
