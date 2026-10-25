local ffi = require("ffi")
local native = require("win_native")

local M = {}

M.VERSION = "1.0-standalone"

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

local function fail(message, level)
    error(message, (level or 1) + 1)
end

local function check_string(value, name)
    if type(value) ~= "string" then
        fail((name or "value") .. " must be a string", 2)
    end
end

local function utf8_to_wide_z(text)
    check_string(text, "text")
    if text:find("\0", 1, true) then return nil, "text contains NUL character" end

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
        return nil, "UTF-8 to UTF-16 conversion failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")"
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
        return nil, "UTF-8 to UTF-16 conversion failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")"
    end

    wide_text[written] = 0
    return wide_text
end

local function wide_to_utf8(wide_text, wide_length)
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
        return nil, "UTF-16 to UTF-8 conversion failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")"
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
        return nil, "UTF-16 to UTF-8 conversion failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")"
    end

    return ffi.string(utf8_text, written)
end

local function get_raw(name)
    local valid, err = utf8_to_wide_z(name)
    if not valid then return nil, err end
    local value, message, code = native.os_getenv(name)
    if code == 'ENOENT' then return nil, false end
    if value == nil then return nil, message end
    return value, true
end

function M.get(name, default_value)
    check_string(name, "name")

    local value, found = get_raw(name)

    if type(found) == "string" then return nil, found end
    if found then
        return value
    end

    return default_value
end

function M.exists(name)
    check_string(name, "name")

    local _, found = get_raw(name)
    if type(found) == "string" then return nil, found end
    return found
end

function M.set(name, value)
    check_string(name, 'name'); check_string(value, 'value')
    local valid, err = utf8_to_wide_z(name)
    if not valid then return nil, err end
    valid, err = utf8_to_wide_z(value)
    if not valid then return nil, err end
    local ok; ok, err = native.os_setenv(name, value)
    if not ok then return nil, err end
    return true
end

function M.unset(name)
    check_string(name, 'name')
    local valid, err = utf8_to_wide_z(name)
    if not valid then return nil, err end
    local ok; ok, err = native.os_unsetenv(name)
    if not ok then return nil, err end
    return true
end

function M.expand(text)
    check_string(text, "text")
    if text:find("\0", 1, true) then return nil, "text contains NUL character" end

    local wide_text, err = utf8_to_wide_z(text)
    if not wide_text then return nil, err end

    local needed = kernel32.ExpandEnvironmentStringsW(
        wide_text,
        nil,
        0
    )

    if needed == 0 then
        return nil, "ExpandEnvironmentStringsW failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")"
    end

    while true do
        local wide_result = ffi.new("unsigned short[?]", needed)

        local written = kernel32.ExpandEnvironmentStringsW(
            wide_text,
            wide_result,
            needed
        )

        if written == 0 then
            return nil, "ExpandEnvironmentStringsW failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")"
        end

        if written <= needed then
            return wide_to_utf8(wide_result, written - 1)
        end

        needed = written
    end
end

return M
