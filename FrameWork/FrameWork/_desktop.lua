local ffi = require("ffi")
local win = require("_win_extension")
local errors = require("_errors")
local native = require("_win_native")
local k = win.kernel
ffi.cdef[[
void *__stdcall LoadLibraryExW(const uint16_t *, void *, unsigned long);
void *__stdcall GetProcAddress(void *, const char *);
]]

local source = debug.getinfo(1, "S").source
local folder, pathError, pathCode
if source:sub(1, 1) == "@" then
    folder = source:sub(2):match("^(.*)[/\\]") or "."
else
    local exe; exe, pathError, pathCode = native.ExePath()
    folder = exe and exe:match("^(.*)[/\\]")
end
local path
if folder then path, pathError, pathCode = native.PathWide(folder .. "\\FwDesktop64.dll") end
local library
local symbols = {}
local M = {}

function M.Symbol(name, signature)
    if symbols[name] then return symbols[name] end
    if not path then return nil, pathError or "Не удалось определить путь к FwDesktop64.dll", pathCode end
    if not library then
        library = k.LoadLibraryExW(path, nil, 0x800)
        if library == nil then return win.Error("LoadLibraryExW(FwDesktop64.dll)") end
    end
    local symbol = k.GetProcAddress(library, name)
    if symbol == nil then return win.Error(name) end
    symbols[name] = ffi.cast(signature, symbol)
    return symbols[name]
end

function M.Functions(definitions)
    local methods = {}
    for name, signature in pairs(definitions) do
        local fn, err, code = M.Symbol("fw_" .. name, signature)
        if not fn then return nil, err, code end
        methods[name] = fn
    end
    return methods
end

function M.Error(operation, status)
    if status >= 0 then return true end
    local _, message = errors.Status(operation, "HRESULT", ("0x%08X"):format(tonumber(ffi.cast("uint32_t", status))))
    return nil, message, tonumber(status)
end

function M.Com(callback)
    local calls, err, code = M.Functions({com_begin = "int32_t (*)()", com_end = "void (*)()"})
    if not calls then return nil, err, code end
    local status = calls.com_begin()
    if status < 0 and status ~= -2147417850 then return M.Error("CoInitializeEx", status) end
    local ok, value, message, result = pcall(callback)
    if status >= 0 then calls.com_end() end
    if not ok then error(value, 0) end
    return value, message, result
end

return M
