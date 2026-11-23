local ffi = require("ffi")
local win = require("_win_extension")
local desktop = require("_desktop")
local optsCheck = require("_options")
local errors = require("_errors")
local M = {}
local objects = setmetatable({}, {__mode = "k"})
local methods = {}
local defs = {
    tray_create = "uint32_t (*)(const uint16_t *, const uint16_t *, void **)",
    tray_text = "uint32_t (*)(void *, const uint16_t *, const uint16_t *)",
    tray_icon = "uint32_t (*)(void *, const uint16_t *)",
    tray_menu = "uint32_t (*)(void *, uint32_t, const uint16_t **)",
    tray_poll = "uint32_t (*)(void *)",
    tray_close = "void (*)(void *)"
}

local function result(operation, code)
    if code == 0 then return true end
    return win.Error(operation, code)
end

local function text(value, maximum)
    local wide, units, code = win.ToWide(value)
    if not wide then return nil, units, code end
    if units > maximum then return win.Error("Tray text exceeds UTF-16 limit", 87) end
    return wide
end

function M.Create(opts)
    local optionError
    opts, optionError = optsCheck(opts, {icon = "string", tooltip = "string"})
    if not opts then return nil, optionError end
    local api, err, code = desktop.Functions(defs)
    if not api then return nil, err, code end
    local tip
    tip, err, code = text(opts.tooltip or "", 127)
    if not tip then return nil, err, code end
    local icon
    if opts.icon then
        icon, err, code = win.PathWide(opts.icon)
        if not icon then return nil, err, code end
    end
    local ptr = ffi.new("void *[1]")
    code = api.tray_create(icon, tip, ptr)
    if code ~= 0 then return win.Error("Shell_NotifyIconW(NIM_ADD)", code) end
    local object = setmetatable({}, {__index = methods})
    objects[object] = {api = api, handle = ffi.gc(ptr[0], api.tray_close)}
    return object
end

local function state(object)
    local entry = objects[object]
    if entry and entry.handle then return entry end
    return win.Error("Tray icon is closed or invalid", 6)
end

function M.SetIcon(object, path)
    local entry, err, code = state(object)
    if not entry then return nil, err, code end
    local wide
    wide, err, code = win.PathWide(path)
    if not wide then return nil, err, code end
    return result("Tray icon", entry.api.tray_icon(entry.handle, wide))
end

function M.SetTooltip(object, value)
    local entry, err, code = state(object)
    if not entry then return nil, err, code end
    local wide
    wide, err, code = text(value, 127)
    if not wide then return nil, err, code end
    return result("Tray tooltip", entry.api.tray_text(entry.handle, wide, nil))
end

function M.ShowNotification(object, title, message)
    local entry, err, code = state(object)
    if not entry then return nil, err, code end
    local name
    name, err, code = text(title, 63)
    if not name then return nil, err, code end
    local description
    description, err, code = text(message, 255)
    if not description then return nil, err, code end
    return result("Tray notification", entry.api.tray_text(entry.handle, description, name))
end

function M.SetMenu(object, items)
    local entry, err, code = state(object)
    if not entry then return nil, err, code end
    if type(items) ~= "table" or #items > 255 then return nil, "Требуется массив максимум из 255 пунктов меню" end
    local labels, kept, callbacks = ffi.new("const uint16_t *[?]", math.max(1, #items)), {}, {}
    for i = 1, #items do
        local item = items[i]
        if type(item) ~= "table" or type(item.onClick) ~= "function" then return nil, "Для пункта меню требуется обработчик onClick" end
        kept[i], err, code = text(item.text, 255)
        if not kept[i] then return nil, err, code end
        labels[i - 1], callbacks[i] = kept[i], item.onClick
    end
    local status = entry.api.tray_menu(entry.handle, #items, labels)
    if kept[#items] then labels[0] = nil end
    if status == 0 then entry.callbacks = callbacks end
    return result("Tray menu", status)
end

function M.Poll(object)
    local entry, err, code = state(object)
    if not entry then return nil, err, code end
    local event = entry.api.tray_poll(entry.handle)
    if event >= 0x10000 then
        local index = event - 0x10000
        local callback = entry.callbacks and entry.callbacks[index]
        if callback then
            local ok, message = pcall(callback, object, index)
            if not ok then return errors.Callback("Tray menu callback", message) end
        end
        return "menu", index
    end
    if event ~= 0 then return "mouse", event end
    return false
end

function M.Destroy(object)
    local entry = objects[object]
    if not entry then return win.Error("Invalid tray icon", 6) end
    if entry.handle then entry.api.tray_close(ffi.gc(entry.handle, nil)); entry.handle = nil end
    entry.callbacks = nil
    return true
end
methods.Close, methods.Poll = M.Destroy, M.Poll

return M
