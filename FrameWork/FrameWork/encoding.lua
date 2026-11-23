local win = require("_win_extension")
local str = require("str")
local native = require("_win_native")
local options = require("_options")

local ffi = require("ffi")
local k = win.kernel
ffi.cdef[[int __stdcall IsValidCodePage(unsigned int);]]

local function toWide(bytes, page)
    if #bytes == 0 then return "" end
    local flags = native.CodePageRequiresZeroFlags(page) and 0 or 8
    local size = k.MultiByteToWideChar(page, flags, bytes, #bytes, nil, 0)
    if size == 0 then return win.Error("MultiByteToWideChar") end
    local buffer = ffi.new("uint16_t[?]", size)
    if k.MultiByteToWideChar(page, flags, bytes, #bytes, buffer, size) == 0 then
        return win.Error("MultiByteToWideChar")
    end
    return ffi.string(buffer, size * 2)
end

local function fromWide(bytes, page, lossy)
    if #bytes == 0 then return "" end
    if #bytes % 2 ~= 0 then return win.Error("Odd UTF-16 byte length", 1113) end
    local units = #bytes / 2
    local wide = ffi.new("uint16_t[?]", units)
    ffi.copy(wide, bytes, #bytes)
    if page == 65001 then return win.FromWide(wide, units) end
    local zeroFlags = native.CodePageRequiresZeroFlags(page)
    local usedDefault, flags
    if zeroFlags then
        flags = 0
    elseif page == 54936 then
        flags = 0x80
    else
        flags = lossy and 0 or 0x400
        usedDefault = ffi.new("int[1]")
    end
    local size = k.WideCharToMultiByte(page, flags, wide, units, nil, 0, nil, usedDefault)
    if size == 0 then return win.Error("WideCharToMultiByte") end
    local output = ffi.new("char[?]", size)
    if k.WideCharToMultiByte(page, flags, wide, units, output, size, nil, usedDefault) == 0 then
        return win.Error("WideCharToMultiByte")
    end
    if not lossy and usedDefault and usedDefault[0] ~= 0 then return win.Error("Encoding is lossy", 1113) end
    local result = ffi.string(output, size)
    if zeroFlags and not lossy then
        local back, err, code = toWide(result, page)
        if not back then return nil, err, code end
        if back ~= bytes then return win.Error("Encoding is lossy", 1113) end
    end
    return result
end

local boms = {
    {"utf32le", "\255\254\0\0"}, {"utf32be", "\0\0\254\255"},
    {"utf8", "\239\187\191"}, {"utf16le", "\255\254"}, {"utf16be", "\254\255"},
}
local M = {IsValidUtf8 = str.IsValidUtf8, Normalize = str.Normalize}
function M.DetectBom(data)
    if type(data) ~= "string" then return nil, "Требуется строка байт" end
    for _, bom in ipairs(boms) do
        if data:sub(1, #bom[2]) == bom[2] then return bom[1] end
    end
end

function M.RemoveBom(data)
    local name, err = M.DetectBom(data)
    if err then return nil, err end
    for _, bom in ipairs(boms) do
        if bom[1] == name then return data:sub(#bom[2] + 1) end
    end
    return data
end

function M.Utf8ToUtf16(text)
    if type(text) ~= "string" then return nil, "Требуется строка UTF-8" end
    return toWide(text, 65001)
end

function M.Utf16ToUtf8(bytes)
    if type(bytes) ~= "string" then return nil, "Требуется строка байт UTF-16LE" end
    return fromWide(bytes, 65001)
end

local function codepage(value)
    if type(value) == "string" then
        local name = value:lower()
        if name == "utf8" then return 65001 end
        if name == "utf16le" then return 1200 end
        if name == "utf16be" then return 1201 end
        value = tonumber(name:match("^cp(%d+)$"))
    end
    if not win.Integer(value, 1, 65535) then return nil, "Ожидается utf8, utf16le, utf16be или кодовая страница Windows" end
    if value ~= 1200 and value ~= 1201 and k.IsValidCodePage(value) == 0 then return nil, "Windows не поддерживает указанную кодовую страницу" end
    return value
end

local function swap(bytes)
    return (bytes:gsub("(.)(.)", "%2%1"))
end

function M.Convert(data, from, to, opts)
    if type(data) ~= "string" then return nil, "Требуется строка байт" end
    local optionError
    opts, optionError = options(opts, {allowLossy = "boolean"})
    if not opts then return nil, optionError end
    local wide, err, code
    from, err = codepage(from); if not from then return nil, err end
    to, err = codepage(to); if not to then return nil, err end
    if from == 1200 or from == 1201 then
        wide = from == 1201 and swap(data) or data
        local valid
        valid, err, code = M.Utf16ToUtf8(wide)
        if not valid then return nil, err, code end
        if to == 65001 then return valid end
    else
        wide, err, code = toWide(data, from)
        if not wide then return nil, err, code end
    end
    if to == 1200 then return wide end
    if to == 1201 then return swap(wide) end
    local result
    result, err, code = fromWide(wide, to, opts.allowLossy == true)
    if not result then return nil, err, code end
    return result
end
return M
