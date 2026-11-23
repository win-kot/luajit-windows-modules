local ffi = require("ffi")
local native = require("_win_native")
local errors = require("_errors")

local M = {}


ffi.cdef[[
int __stdcall MultiByteToWideChar(
    unsigned int CodePage,
    unsigned long dwFlags,
    const char *lpMultiByteStr,
    int cbMultiByte,
    unsigned short *lpWideCharStr,
    int cchWideChar
);

int __stdcall WideCharToMultiByte(
    unsigned int CodePage,
    unsigned long dwFlags,
    const unsigned short *lpWideCharStr,
    int cchWideChar,
    char *lpMultiByteStr,
    int cbMultiByte,
    const char *lpDefaultChar,
    int *lpUsedDefaultChar
);



unsigned long __stdcall ExpandEnvironmentStringsW(
    const unsigned short *lpSrc,
    unsigned short *lpDst,
    unsigned long nSize
);

unsigned long __stdcall GetLastError(void);
]]

local kernel32 = ffi.load("kernel32")

local CP_UTF8 = 65001
local MB_ERR_INVALID_CHARS = 0x00000008
local WC_ERR_INVALID_CHARS = 0x00000080

local function Utf8ToWideZ(text)
    if type(text) ~= "string" then return nil, "Требуется строка" end
    if text:find("\0", 1, true) then return nil, "Нулевой байт в строке недопустим" end

    if text == "" then
        return ffi.new("unsigned short[1]", 0)
    end

    local needed = kernel32.MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        text,
        #text,
        nil,
        0
    )

    if needed == 0 then
        return errors.Win32("MultiByteToWideChar")
    end

    local wide_text = ffi.new("unsigned short[?]", needed + 1)

    local written = kernel32.MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        text,
        #text,
        wide_text,
        needed
    )

    if written == 0 then
        return errors.Win32("MultiByteToWideChar")
    end

    wide_text[written] = 0
    return wide_text
end

local function WideToUtf8(wide_text, wide_length)
    if wide_length == 0 then
        return ""
    end

    local needed = kernel32.WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        wide_text,
        wide_length,
        nil,
        0,
        nil,
        nil
    )

    if needed == 0 then
        return errors.Win32("WideCharToMultiByte")
    end

    local utf8_text = ffi.new("char[?]", needed)

    local written = kernel32.WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        wide_text,
        wide_length,
        utf8_text,
        needed,
        nil,
        nil
    )

    if written == 0 then
        return errors.Win32("WideCharToMultiByte")
    end

    return ffi.string(utf8_text, written)
end

local function GetRaw(name)
    local valid, err, code = Utf8ToWideZ(name)
    if not valid then return nil, err, code end
    local value, message, code = native.OsGetEnvWide(valid)
    if code == 203 then return nil, false end
    if value == nil then return nil, message, code end
    return value, true
end

function M.Get(name, default_value)

    local value, found, code = GetRaw(name)

    if type(found) == "string" then return nil, found, code end
    if found then
        return value
    end

    return default_value
end

function M.Exists(name)

    local _, found, code = GetRaw(name)

    if type(found) == "string" then return nil, found, code end
    return found
end

function M.Set(name, value)
    local wide_name, err, code = Utf8ToWideZ(name)
    if not wide_name then return nil, err, code end
    local wide_value; wide_value, err, code = Utf8ToWideZ(value)
    if not wide_value then return nil, err, code end
    local ok; ok, err, code = native.OsSetEnvWide(wide_name, wide_value)
    if not ok then return nil, err, code end
    return true
end

function M.Unset(name)
    local valid, err, code = Utf8ToWideZ(name)
    if not valid then return nil, err, code end
    local ok; ok, err, code = native.OsSetEnvWide(valid, nil)
    if not ok then return nil, err, code end
    return true
end

function M.Expand(text)
    local wide_text, err, code = Utf8ToWideZ(text)
    if not wide_text then return nil, err, code end

    local needed = kernel32.ExpandEnvironmentStringsW(
        wide_text,
        nil,
        0
    )

    if needed == 0 then
        return errors.Win32("ExpandEnvironmentStringsW")
    end

    while true do
        local wide_result = ffi.new("unsigned short[?]", needed)

        local written = kernel32.ExpandEnvironmentStringsW(
            wide_text,
            wide_result,
            needed
        )

        if written == 0 then
            return errors.Win32("ExpandEnvironmentStringsW")
        end

        if written <= needed then
            return WideToUtf8(wide_result, written - 1)
        end

        needed = written
    end
end

return M
