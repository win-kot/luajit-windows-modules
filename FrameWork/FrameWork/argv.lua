local ffi = require("ffi")

local M = {}


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

local errors = require("_errors")

local function WideLength(wide_text)
    local length = 0

    while wide_text[length] ~= 0 do
        length = length + 1
    end

    return length
end

local function WideToUtf8(wide_text, wide_len)
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
        return errors.Win32("WideCharToMultiByte")
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
        return errors.Win32("WideCharToMultiByte")
    end

    return ffi.string(utf8_text, written)
end

local function WideZToUtf8(wide_text)
    return WideToUtf8(wide_text, WideLength(wide_text))
end

local function ReadCommandLine()
    local wide_cmdline = kernel32.GetCommandLineW()

    if wide_cmdline == nil then
        return nil, "GetCommandLineW не вернул командную строку"
    end

    return WideZToUtf8(wide_cmdline)
end

local function ReadArguments()
    local wide_cmdline = kernel32.GetCommandLineW()

    if wide_cmdline == nil then
        return nil, "GetCommandLineW не вернул командную строку"
    end

    local argc_ptr = ffi.new("int[1]")
    local argv_ptr = shell32.CommandLineToArgvW(wide_cmdline, argc_ptr)

    if argv_ptr == nil then
        return errors.Win32("CommandLineToArgvW")
    end

    local values = {}
    local argc = tonumber(argc_ptr[0])

    for index = 0, argc - 1 do
        local text, err, code = WideZToUtf8(argv_ptr[index])
        if text == nil then
            kernel32.LocalFree(argv_ptr)
            return nil, err, code
        end
        values[index + 1] = text
    end
    if kernel32.LocalFree(argv_ptr) ~= nil then return errors.Win32("LocalFree") end

    return values
end

local raw_command_line, commandError, commandCode = ReadCommandLine()
local raw_arguments, argumentsError, argumentsCode = ReadArguments()

function M.CommandLine()
    if raw_command_line == nil then return nil, commandError, commandCode end
    return raw_command_line
end

function M.Get()
    if not raw_arguments then return nil, argumentsError, argumentsCode end
    local values = {}

    for index = 1, #raw_arguments do
        values[index] = raw_arguments[index]
    end

    return values
end

function M.Count()
    if not raw_arguments then return nil, argumentsError, argumentsCode end
    return #raw_arguments
end

function M.At(index)
    if not raw_arguments then return nil, argumentsError, argumentsCode end
    if type(index) ~= "number" or index == math.huge or index == -math.huge or index ~= math.floor(index) then
        return nil, "Индекс аргумента должен быть конечным целым числом"
    end

    if index < 0 then
        index = #raw_arguments + index + 1
    end

    return raw_arguments[index]
end

function M.Program()
    if not raw_arguments then return nil, argumentsError, argumentsCode end
    return raw_arguments[1]
end

return M
