local ffi = require("ffi")
local win = require("_win_extension")
local desktop = require("_desktop")
local options = require("_options")
local M = {}
local voices = setmetatable({}, {__mode = "k"})
local methods = {}
local definitions = {
    speech_voices = "int32_t (*)(void **)",
    speech_next = "int32_t (*)(void *, uint16_t **, uint16_t **)",
    speech_speak = "int32_t (*)(const uint16_t *, const uint16_t *, int, int, int, void **)",
    speech_wait = "int32_t (*)(void *, uint32_t)", speech_stop = "int32_t (*)(void *)",
    release = "void (*)(void *)", free = "void (*)(void *)",
    com_begin = "int32_t (*)()", com_end = "void (*)()"
}

function M.ListVoices()
    return desktop.Com(function()
        local api, err, code = desktop.Functions(definitions)
        if not api then return nil, err, code end
        local list = ffi.new("void *[1]")
        local status = api.speech_voices(list)
        if status < 0 then return desktop.Error("SAPI EnumTokens", status) end
        local out = {}
        local id, name = ffi.new("uint16_t *[1]"), ffi.new("uint16_t *[1]")
        while true do
            status = api.speech_next(list[0], id, name)
            if status == 0 then
                local identifier = id[0] ~= nil and win.FromWide(id[0])
                local label = name[0] ~= nil and win.FromWide(name[0])
                if identifier then out[#out + 1] = {id = identifier, name = label or identifier} end
            end
            api.free(id[0])
            api.free(name[0])
            id[0], name[0] = nil, nil
            if status ~= 0 then break end
        end
        api.release(list[0])
        if status < 0 then return desktop.Error("SAPI Next", status) end
        return out
    end)
end

function methods:Wait(timeoutMs)
    local state = voices[self]
    if not state or not state.handle then return win.Error("Speech handle is closed", 6) end
    local timeout, err, code = win.Timeout(timeoutMs, 5000)
    if not timeout then return nil, err, code end
    local status = state.api.speech_wait(state.handle, timeout)
    if status == 1 then return false end
    return desktop.Error("SAPI WaitUntilDone", status)
end

function methods:Stop()
    local state = voices[self]
    if not state or not state.handle then return true end
    return desktop.Error("SAPI Stop", state.api.speech_stop(state.handle))
end

function methods:Close()
    local state = voices[self]
    if not state or not state.handle then return true end
    state.cleanup(ffi.gc(state.handle, nil))
    state.handle = nil
    return true
end

function M.Speak(text, opts)
    local optionError
    opts, optionError = options(opts, {voice = "string", rate = "number", volume = "number", async = "boolean"})
    if not opts then return nil, optionError end
    local rate, volume = opts.rate or 0, opts.volume or 100
    if not (win.Integer(rate, -10, 10) and win.Integer(volume, 0, 100)) then return nil, "Недопустимая скорость речи или громкость" end
    local wide, err, code = win.ToWide(text)
    if not wide then return nil, err, code end
    local voice
    if opts.voice then
        voice, err, code = win.ToWide(opts.voice)
        if not voice then return nil, err, code end
    end
    local api
    api, err, code = desktop.Functions(definitions)
    if not api then return nil, err, code end
    local status = api.com_begin()
    if status < 0 and status ~= -2147417850 then return desktop.Error("CoInitializeEx", status) end
    local initialized = status >= 0
    local out = ffi.new("void *[1]")
    status = api.speech_speak(wide, voice, rate, volume, opts.async and 1 or 0, out)
    if status < 0 or not opts.async then
        if initialized then api.com_end() end
        return desktop.Error("SAPI Speak", status)
    end
    local function cleanup(handle)
        api.speech_stop(handle)
        api.release(handle)
        if initialized then api.com_end() end
    end
    local object = setmetatable({}, {__index = methods})
    voices[object] = {handle = ffi.gc(out[0], cleanup), cleanup = cleanup, api = api}
    return object
end

return M
