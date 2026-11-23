local ffi = require("ffi")
local win = require("_win_extension")
local desktop = require("_desktop")
local options = require("_options")
local errors = require("_errors")
local M = {}
local definitions = {
    audio_enum = "int32_t (*)(void **)",
    audio_count = "int32_t (*)(void *, uint32_t *)",
    audio_info = "int32_t (*)(void *, uint32_t, uint16_t **, uint16_t **, uint32_t *)",
    audio_level = "int32_t (*)(const uint16_t *, int, float *, int *)",
    release = "void (*)(void *)", free = "void (*)(void *)",
    audio_watch = "int32_t (*)(void **)", audio_changed = "int (*)(void *)", audio_unwatch = "void (*)(void *)",
    com_begin = "int32_t (*)()", com_end = "void (*)()"
}

local function withAudio(fn)
    return desktop.Com(function()
        local api, err, code = desktop.Functions(definitions)
        if not api then return nil, err, code end
        return fn(api)
    end)
end

local function info(api, list, index)
    local id, name, state = ffi.new("uint16_t *[1]"), ffi.new("uint16_t *[1]"), ffi.new("uint32_t[1]")
    local status = api.audio_info(list, index, id, name, state)
    local identifier = id[0] ~= nil and win.FromWide(id[0])
    local label = name[0] ~= nil and win.FromWide(name[0])
    api.free(id[0])
    api.free(name[0])
    if status < 0 then return desktop.Error("IMMDevice information", status) end
    if not identifier then return win.Error("Invalid endpoint ID", 1113) end
    return {id = identifier, name = label or identifier, state = tonumber(state[0])}
end

function M.ListDevices()
    return withAudio(function(api)
        local out = ffi.new("void *[1]")
        local status = api.audio_enum(out)
        if status < 0 then return desktop.Error("EnumAudioEndpoints", status) end
        local count = ffi.new("uint32_t[1]")
        status = api.audio_count(out[0], count)
        local list, message
        if status >= 0 then
            list = {}
            for i = 0, count[0] - 1 do
                local row, err, code = info(api, out[0], i)
                if not row then list, message, status = nil, err, code; break end
                list[#list + 1] = row
            end
        end
        api.release(out[0])
        if message then return nil, message, status end
        if status < 0 then return desktop.Error("IMMDeviceCollection.GetCount", status) end
        return list
    end)
end

function M.GetDefaultDevice()
    return withAudio(function(api) return info(api, nil, 0) end)
end

local function level(operation, device, value)
    if type(device) == "table" then
        device = device.id
        if type(device) ~= "string" then return nil, "Требуется идентификатор аудиоустройства" end
    end
    local wide, err, code
    if device ~= nil then
        wide, err, code = win.ToWide(device)
        if not wide then return nil, err, code end
    end
    return withAudio(function(api)
        local scalar, muted = ffi.new("float[1]", operation == 1 and value or 0),
            ffi.new("int[1]", operation == 3 and value and 1 or 0)
        local status = api.audio_level(wide, operation, scalar, muted)
        if status < 0 then return desktop.Error("IAudioEndpointVolume", status) end
        if operation == 0 then return tonumber(scalar[0]) end
        if operation == 2 then return muted[0] ~= 0 end
        return true
    end)
end

function M.GetVolume(device) return level(0, device) end
function M.SetVolume(value, device)
    if type(value) ~= "number" or not (value >= 0 and value <= 1) then return nil, "Громкость должна быть числом от 0 до 1" end
    return level(1, device, value)
end
function M.GetMute(device) return level(2, device) end
function M.SetMute(enabled, device)
    if type(enabled) ~= "boolean" then return nil, "Требуется логическое состояние отключения звука" end
    return level(3, device, enabled)
end

ffi.cdef[[
unsigned long __stdcall mciSendStringW(const uint16_t *, uint16_t *, unsigned int, void *);
unsigned long __stdcall GetShortPathNameW(const uint16_t *, uint16_t *, unsigned long);
]]
local players = setmetatable({}, {__mode = "k"})
local player = {}
local nextAlias = 0
local MCIERR_FILENAME_REQUIRED = 304

local function mci(dll, command)
    local wide, err, code = win.ToWide(command)
    if not wide then return nil, err, code end
    code = tonumber(dll.mciSendStringW(wide, nil, 0, nil))
    if code == 0 then return true end
    return nil, ("MCI error %d"):format(code), code
end

local function shortPath(path)
    local wide, length = win.ToWide(path)
    if not wide then return nil end
    local buffer = ffi.new("uint16_t[?]", length + 1)
    local actual = win.kernel.GetShortPathNameW(wide, buffer, length + 1)
    if actual == 0 or actual >= length then return nil end
    local short = win.FromWide(buffer, actual)
    if not short then return nil end
    -- MCI selects the driver by extension. A shortened extension can change it.
    local extension = path:lower():match("(%.[^/\\%.]+)$")
    if short:lower():match("(%.[^/\\%.]+)$") == extension then return short end
end

function M.Stop(handle)
    local state = players[handle]
    if not state then return win.Error("Invalid audio handle", 6) end
    if state.closed then return true end
    local ok, err, code = mci(state.dll, "close " .. state.alias)
    if ok then state.closed = true; ffi.gc(state.guard, nil) end
    return ok, err, code
end
player.Stop, player.Close = M.Stop, M.Stop

function M.Play(path, opts)
    local optionError
    opts, optionError = options(opts, {wait = "boolean"})
    if not opts then return nil, optionError end
    local absolute, err, code = require("fs").PathAbsolute(path)
    if not absolute then return nil, err, code end
    if absolute:find('"', 1, true) then return win.Error("Invalid audio path", 87) end
    local dll
    dll, err, code = win.Library("winmm")
    if not dll then return nil, err, code end
    nextAlias = nextAlias + 1
    local alias = "fw_audio_" .. nextAlias
    local ok
    ok, err, code = mci(dll, 'open "' .. absolute .. '" alias ' .. alias)
    if code == MCIERR_FILENAME_REQUIRED then
        local short = shortPath(absolute)
        if short then ok, err, code = mci(dll, 'open "' .. short .. '" alias ' .. alias) end
    end
    if not ok then return nil, err, code end
    ok, err, code = mci(dll, "play " .. alias .. (opts.wait and " wait" or ""))
    if not ok then mci(dll, "close " .. alias); return nil, err, code end
    local object = setmetatable({}, {__index = player})
    local guard = ffi.gc(ffi.new("uint8_t[1]"), function() mci(dll, "close " .. alias) end)
    players[object] = {dll = dll, alias = alias, guard = guard}
    return object
end

local subscription = {}
local function snapshot()
    local devices, err, code = M.ListDevices()
    if not devices then return nil, err, code end
    local default, message, status = M.GetDefaultDevice()
    if not default and status ~= -2147023728 then return nil, message, status end
    local entries = {}
    for _, item in ipairs(devices) do entries[item.id] = item end
    return {devices = entries, default = default and default.id}
end

function M.OnDeviceChange(callback)
    if type(callback) ~= "function" then return nil, "Требуется функция обратного вызова" end
    local api, err, code = desktop.Functions(definitions)
    if not api then return nil, err, code end
    local status = api.com_begin()
    if status < 0 and status ~= -2147417850 then return desktop.Error("CoInitializeEx", status) end
    local initialized = status >= 0
    local handle = ffi.new("void *[1]")
    status = api.audio_watch(handle)
    if status < 0 then
        if initialized then api.com_end() end
        return desktop.Error("RegisterEndpointNotificationCallback", status)
    end
    local function cleanup(ptr)
        api.audio_unwatch(ptr)
        if initialized then api.com_end() end
    end
    local pointer = ffi.gc(handle[0], cleanup)
    local initial, err, code = snapshot()
    if not initial then cleanup(ffi.gc(pointer, nil)); return nil, err, code end
    return setmetatable({callback = callback, previous = initial, api = api, pointer = pointer,
        cleanup = cleanup}, {__index = subscription})
end

function subscription:Poll()
    if not self.callback then return win.Error("Subscription is closed", 6) end
    if not self.retry and self.api.audio_changed(self.pointer) == 0 then return 0 end
    local current, err, code = snapshot()
    self.retry = not current
    if not current then return nil, err, code end
    local previous, count = self.previous, 0
    self.previous = current
    local function emit(kind, item, id)
        if not self.callback then return true end
        local ok, message = pcall(self.callback, {kind = kind, device = item, id = id})
        if not ok then return errors.Callback("Audio callback failed", message) end
        count = count + 1
        return true
    end
    for id, item in pairs(current.devices) do
        local old = previous.devices[id]
        if not old or old.state ~= item.state or old.name ~= item.name then
            local ok, message, status = emit(old and "changed" or "added", item, id)
            if not ok then return nil, message, status end
        end
    end
    for id, item in pairs(previous.devices) do
        if not current.devices[id] then
            local ok, message, status = emit("removed", item, id)
            if not ok then return nil, message, status end
        end
    end
    if current.default ~= previous.default then
        local ok, message, status = emit("default", current.devices[current.default], current.default)
        if not ok then return nil, message, status end
    end
    return count
end

function subscription:Close()
    if self.pointer then self.cleanup(ffi.gc(self.pointer, nil)); self.pointer = nil end
    self.callback, self.previous = nil, nil
    return true
end

return M
