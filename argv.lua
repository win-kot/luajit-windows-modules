local ffi = require("ffi")

local M = {}

M.VERSION = "1.0-standalone"

ffi.cdef[[
const unsigned short * __stdcall GetCommandLineW(void);

unsigned short ** __stdcall CommandLineToArgvW(
    const unsigned short *lpCmdLine,
    int *pNumArgs
);

void * __stdcall LocalFree(void *hMem);

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

unsigned long __stdcall GetLastError(void);
]]

local kernel32 = ffi.load("kernel32")
local shell32 = ffi.load("shell32")

local CP_UTF8 = 65001
local WC_ERR_INVALID_CHARS = 0x00000080

local function fail(message, level)
    error(message, (level or 1) + 1)
end

local function wide_length(wide_text)
    local length = 0

    while wide_text[length] ~= 0 do
        length = length + 1
    end

    return length
end

local function wide_to_utf8(wide_text, wide_len)
    if wide_len == 0 then
        return ""
    end

    local needed = kernel32.WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        wide_text,
        wide_len,
        nil,
        0,
        nil,
        nil
    )

    if needed == 0 then
        fail("UTF-16 to UTF-8 conversion failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")", 2)
    end

    local utf8_text = ffi.new("char[?]", needed)

    local written = kernel32.WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        wide_text,
        wide_len,
        utf8_text,
        needed,
        nil,
        nil
    )

    if written == 0 then
        fail("UTF-16 to UTF-8 conversion failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")", 2)
    end

    return ffi.string(utf8_text, written)
end

local function wide_z_to_utf8(wide_text)
    return wide_to_utf8(wide_text, wide_length(wide_text))
end

local function read_command_line()
    local wide_cmdline = kernel32.GetCommandLineW()

    if wide_cmdline == nil then
        fail("GetCommandLineW failed", 2)
    end

    return wide_z_to_utf8(wide_cmdline)
end

local function read_arguments()
    local wide_cmdline = kernel32.GetCommandLineW()

    if wide_cmdline == nil then
        fail("GetCommandLineW failed", 2)
    end

    local argc_ptr = ffi.new("int[1]")
    local argv_ptr = shell32.CommandLineToArgvW(wide_cmdline, argc_ptr)

    if argv_ptr == nil then
        fail("CommandLineToArgvW failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")", 2)
    end

    local values = {}
    local argc = tonumber(argc_ptr[0])

    local ok, err = pcall(function()
        for index = 0, argc - 1 do
            values[index + 1] = wide_z_to_utf8(argv_ptr[index])
        end
    end)

    kernel32.LocalFree(argv_ptr)

    if not ok then
        error(err, 0)
    end

    return values
end

local command_ok, raw_command_line = pcall(read_command_line)
local arguments_ok, raw_arguments = pcall(read_arguments)

function M.commandLine()
    if not command_ok then return nil, raw_command_line end
    return raw_command_line
end

function M.get()
    if not arguments_ok then return nil, raw_arguments end
    local values = {}

    for index = 1, #raw_arguments do
        values[index] = raw_arguments[index]
    end

    return values
end

function M.count()
    if not arguments_ok then return nil, raw_arguments end
    return #raw_arguments
end

function M.at(index)
    if not arguments_ok then return nil, raw_arguments end
    if type(index) ~= "number" or index ~= math.floor(index) then
        fail("index must be an integer", 1)
    end

    if index < 0 then
        index = #raw_arguments + index + 1
    end

    return raw_arguments[index]
end

function M.program()
    if not arguments_ok then return nil, raw_arguments end
    return raw_arguments[1]
end

return M
