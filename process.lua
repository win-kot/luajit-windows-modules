---@diagnostic disable: undefined-field, inject-field

local ffi = require("ffi")
local native = require("win_native")

ffi.cdef [[
typedef void *HANDLE;
typedef void *LPVOID;
typedef const void *LPCVOID;

typedef uint8_t BYTE;
typedef uint16_t WORD;
typedef uint16_t WCHAR;
typedef uint32_t DWORD;
typedef int32_t LONG;
typedef int32_t BOOL;
typedef uintptr_t ULONG_PTR;
typedef uint64_t ULONGLONG;

typedef struct {
    DWORD nLength;
    LPVOID lpSecurityDescriptor;
    BOOL bInheritHandle;
} SECURITY_ATTRIBUTES;

typedef struct {
    DWORD cb;
    WCHAR *lpReserved;
    WCHAR *lpDesktop;
    WCHAR *lpTitle;
    DWORD dwX;
    DWORD dwY;
    DWORD dwXSize;
    DWORD dwYSize;
    DWORD dwXCountChars;
    DWORD dwYCountChars;
    DWORD dwFillAttribute;
    DWORD dwFlags;
    WORD wShowWindow;
    WORD cbReserved2;
    BYTE *lpReserved2;
    HANDLE hStdInput;
    HANDLE hStdOutput;
    HANDLE hStdError;
} STARTUPINFOW;

typedef struct {
    HANDLE hProcess;
    HANDLE hThread;
    DWORD dwProcessId;
    DWORD dwThreadId;
} PROCESS_INFORMATION;

typedef struct {
    DWORD dwSize;
    DWORD cntUsage;
    DWORD th32ProcessID;
    ULONG_PTR th32DefaultHeapID;
    DWORD th32ModuleID;
    DWORD cntThreads;
    DWORD th32ParentProcessID;
    LONG pcPriClassBase;
    DWORD dwFlags;
    WCHAR szExeFile[260];
} PROCESSENTRY32W;

int __stdcall MultiByteToWideChar(
    uint32_t CodePage,
    DWORD dwFlags,
    const char *lpMultiByteStr,
    int cbMultiByte,
    WCHAR *lpWideCharStr,
    int cchWideChar
);

int __stdcall WideCharToMultiByte(
    uint32_t CodePage,
    DWORD dwFlags,
    const WCHAR *lpWideCharStr,
    int cchWideChar,
    char *lpMultiByteStr,
    int cbMultiByte,
    const char *lpDefaultChar,
    BOOL *lpUsedDefaultChar
);

DWORD __stdcall GetLastError(void);

DWORD __stdcall FormatMessageW(
    DWORD dwFlags,
    LPCVOID lpSource,
    DWORD dwMessageId,
    DWORD dwLanguageId,
    WCHAR *lpBuffer,
    DWORD nSize,
    void *Arguments
);

BOOL __stdcall CloseHandle(HANDLE hObject);

BOOL __stdcall CreateProcessW(
    const WCHAR *lpApplicationName,
    WCHAR *lpCommandLine,
    void *lpProcessAttributes,
    void *lpThreadAttributes,
    BOOL bInheritHandles,
    DWORD dwCreationFlags,
    LPVOID lpEnvironment,
    const WCHAR *lpCurrentDirectory,
    void *lpStartupInfo,
    void *lpProcessInformation
);

DWORD __stdcall WaitForSingleObject(
    HANDLE hHandle,
    DWORD dwMilliseconds
);

BOOL __stdcall GetExitCodeProcess(
    HANDLE hProcess,
    DWORD *lpExitCode
);

BOOL __stdcall TerminateProcess(
    HANDLE hProcess,
    uint32_t uExitCode
);

HANDLE __stdcall OpenProcess(
    DWORD dwDesiredAccess,
    BOOL bInheritHandle,
    DWORD dwProcessId
);

BOOL __stdcall SetPriorityClass(
    HANDLE hProcess,
    DWORD dwPriorityClass
);


HANDLE __stdcall CreateToolhelp32Snapshot(
    DWORD dwFlags,
    DWORD th32ProcessID
);

BOOL __stdcall Process32FirstW(
    HANDLE hSnapshot,
    PROCESSENTRY32W *lppe
);

BOOL __stdcall Process32NextW(
    HANDLE hSnapshot,
    PROCESSENTRY32W *lppe
);

BOOL __stdcall QueryFullProcessImageNameW(
    HANDLE hProcess,
    DWORD dwFlags,
    WCHAR *lpExeName,
    DWORD *lpdwSize
);

BOOL __stdcall CreatePipe(
    HANDLE *hReadPipe,
    HANDLE *hWritePipe,
    void *lpPipeAttributes,
    DWORD nSize
);

BOOL __stdcall SetHandleInformation(
    HANDLE hObject,
    DWORD dwMask,
    DWORD dwFlags
);

BOOL __stdcall ReadFile(
    HANDLE hFile,
    LPVOID lpBuffer,
    DWORD nNumberOfBytesToRead,
    DWORD *lpNumberOfBytesRead,
    LPVOID lpOverlapped
);

BOOL __stdcall PeekNamedPipe(
    HANDLE hNamedPipe,
    LPVOID lpBuffer,
    DWORD nBufferSize,
    DWORD *lpBytesRead,
    DWORD *lpTotalBytesAvail,
    DWORD *lpBytesLeftThisMessage
);

HANDLE __stdcall CreateFileW(
    const WCHAR *lpFileName,
    DWORD dwDesiredAccess,
    DWORD dwShareMode,
    void *lpSecurityAttributes,
    DWORD dwCreationDisposition,
    DWORD dwFlagsAndAttributes,
    HANDLE hTemplateFile
);

int __stdcall CompareStringOrdinal(
    const WCHAR *lpString1,
    int cchCount1,
    const WCHAR *lpString2,
    int cchCount2,
    BOOL bIgnoreCase
);

DWORD __stdcall GetACP(void);
DWORD __stdcall GetOEMCP(void);

ULONGLONG __stdcall GetTickCount64(void);
]]

local k32 = ffi.load("kernel32")
local kernelbase = ffi.load("KernelBase")

local process = {}

local CP_UTF8 = 65001
local MB_ERR_INVALID_CHARS = 0x00000008

local FORMAT_MESSAGE_IGNORE_INSERTS = 0x00000200
local FORMAT_MESSAGE_FROM_SYSTEM = 0x00001000

local TH32CS_SNAPPROCESS = 0x00000002

local PROCESS_TERMINATE = 0x0001
local PROCESS_SET_INFORMATION = 0x0200
local PROCESS_QUERY_LIMITED_INFORMATION = 0x1000

local IDLE_PRIORITY_CLASS = 0x00000040
local BELOW_NORMAL_PRIORITY_CLASS = 0x00004000
local NORMAL_PRIORITY_CLASS = 0x00000020
local ABOVE_NORMAL_PRIORITY_CLASS = 0x00008000
local HIGH_PRIORITY_CLASS = 0x00000080
local REALTIME_PRIORITY_CLASS = 0x00000100

local STARTF_USESHOWWINDOW = 0x00000001
local STARTF_USESTDHANDLES = 0x00000100

local SW_HIDE = 0

local CREATE_NO_WINDOW = 0x08000000

local WAIT_OBJECT_0 = 0
local WAIT_TIMEOUT = 258
local WAIT_FAILED = 0xffffffff
local INFINITE = 0xffffffff

local HANDLE_FLAG_INHERIT = 0x00000001

local GENERIC_READ = 0x80000000
local FILE_SHARE_READ = 0x00000001
local FILE_SHARE_WRITE = 0x00000002
local OPEN_EXISTING = 3
local FILE_ATTRIBUTE_NORMAL = 0x00000080

local ERROR_BROKEN_PIPE = 109

local INVALID_HANDLE_VALUE = ffi.cast("HANDLE", -1)

local MAX_PATH_LONG = 32768


-- ============================================================
-- Unicode
-- ============================================================

local function utf8_to_wide(text)
    if text == nil then
        return nil
    end

    text = tostring(text)
    if text:find("\0", 1, true) then return nil end

    if text == "" then
        return ffi.new("WCHAR[1]")
    end

    local length = k32.MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        text,
        #text,
        nil,
        0
    )

    if length == 0 then
        return nil
    end

    local wideText = ffi.new("WCHAR[?]", length + 1)

    local result = k32.MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        text,
        #text,
        wideText,
        length
    )

    if result == 0 then
        return nil
    end

    wideText[length] = 0

    return wideText
end


local function wide_to_utf8(wideText, length)
    if wideText == nil then
        return ""
    end

    if length == nil then
        local size = k32.WideCharToMultiByte(
            CP_UTF8,
            0,
            wideText,
            -1,
            nil,
            0,
            nil,
            nil
        )

        if size <= 1 then
            return ""
        end

        local output = ffi.new("char[?]", size)

        local result = k32.WideCharToMultiByte(
            CP_UTF8,
            0,
            wideText,
            -1,
            output,
            size,
            nil,
            nil
        )

        if result == 0 then
            return ""
        end

        return ffi.string(output, result - 1)
    end

    if length == 0 then
        return ""
    end

    local size = k32.WideCharToMultiByte(
        CP_UTF8,
        0,
        wideText,
        length,
        nil,
        0,
        nil,
        nil
    )

    if size == 0 then
        return ""
    end

    local output = ffi.new("char[?]", size)

    local result = k32.WideCharToMultiByte(
        CP_UTF8,
        0,
        wideText,
        length,
        output,
        size,
        nil,
        nil
    )

    if result == 0 then
        return ""
    end

    return ffi.string(output, result)
end


-- ============================================================
-- Errors
-- ============================================================

local function error_message(errorCode)
    errorCode = errorCode or tonumber(k32.GetLastError())

    local errorBuf = ffi.new("WCHAR[2048]")

    local length = k32.FormatMessageW(
        FORMAT_MESSAGE_FROM_SYSTEM + FORMAT_MESSAGE_IGNORE_INSERTS,
        nil,
        errorCode,
        0,
        errorBuf,
        2048,
        nil
    )

    if length == 0 then
        return "Win32 error " .. tostring(errorCode)
    end

    local text = wide_to_utf8(errorBuf, tonumber(length))

    text = text:gsub("[\r\n]+$", "")

    return text .. " (Win32 error " .. tostring(errorCode) .. ")"
end


local function win_error(prefix, errorCode)
    return prefix .. ": " .. error_message(errorCode)
end


-- ============================================================
-- Handle helpers
-- ============================================================

local function is_valid_handle(handle)
    return handle ~= nil
        and handle ~= ffi.NULL
        and handle ~= INVALID_HANDLE_VALUE
end


local function close_handle(handle)
    if is_valid_handle(handle) then
        k32.CloseHandle(handle)
    end
end

local function trim(value)
    return tostring(value):match("^%s*(.-)%s*$")
end

local function timeout_seconds_to_ms(timeout)
    if timeout == nil then
        return nil
    end

    local seconds = tonumber(timeout)

    if seconds == nil or seconds ~= seconds or seconds == math.huge or seconds < 0 then
        return nil, "timeout must be zero or greater"
    end

    local milliseconds = seconds * 1000

    if milliseconds > 0xfffffffe then
        milliseconds = 0xfffffffe
    end

    return math.floor(milliseconds)
end


-- ============================================================
-- Command line
-- ============================================================

function process.quoteArg(value)
    local text = tostring(value)

    if text == "" then
        return '""'
    end

    if not text:find('[%s"]') then
        return text
    end

    local output = { '"' }
    local slashCount = 0

    for index = 1, #text do
        local char = text:sub(index, index)

        if char == "\\" then
            slashCount = slashCount + 1
        elseif char == '"' then
            if slashCount > 0 then
                output[#output + 1] = string.rep("\\", slashCount * 2)
            end

            output[#output + 1] = '\\"'
            slashCount = 0
        else
            if slashCount > 0 then
                output[#output + 1] = string.rep("\\", slashCount)
                slashCount = 0
            end

            output[#output + 1] = char
        end
    end

    if slashCount > 0 then
        output[#output + 1] = string.rep("\\", slashCount * 2)
    end

    output[#output + 1] = '"'

    return table.concat(output)
end

function process.command(exePath, args)
    if type(exePath) ~= "string" or exePath == "" then
        return nil, "program must be a non-empty string"
    end

    local parts = {
        process.quoteArg(exePath)
    }

    if args == nil then
        return parts[1]
    end

    if type(args) == "string" then
        if args ~= "" then
            parts[#parts + 1] = args
        end

        return table.concat(parts, " ")
    end

    if type(args) ~= "table" then
        return nil, "args must be string, table or nil"
    end

    for index = 1, #args do
        parts[#parts + 1] = process.quoteArg(args[index])
    end

    return table.concat(parts, " ")
end

-- ============================================================
-- Pipe helpers
-- ============================================================

local function create_pipe()
    local attributes = ffi.new("SECURITY_ATTRIBUTES[1]")

    attributes[0].nLength = ffi.sizeof("SECURITY_ATTRIBUTES")
    attributes[0].lpSecurityDescriptor = nil
    attributes[0].bInheritHandle = 1

    local readHandle = ffi.new("HANDLE[1]")
    local writeHandle = ffi.new("HANDLE[1]")

    if k32.CreatePipe(
            readHandle,
            writeHandle,
            attributes,
            65536
        ) == 0 then
        return nil, nil, win_error("CreatePipe failed")
    end

    if k32.SetHandleInformation(
            readHandle[0],
            HANDLE_FLAG_INHERIT,
            0
        ) == 0 then
        local errorText = win_error("SetHandleInformation failed")

        close_handle(readHandle[0])
        close_handle(writeHandle[0])

        return nil, nil, errorText
    end

    return readHandle[0], writeHandle[0]
end


local function create_null_input()
    local attributes = ffi.new("SECURITY_ATTRIBUTES[1]")

    attributes[0].nLength = ffi.sizeof("SECURITY_ATTRIBUTES")
    attributes[0].lpSecurityDescriptor = nil
    attributes[0].bInheritHandle = 1

    local nullName = utf8_to_wide("NUL")

    local handle = k32.CreateFileW(
        nullName,
        GENERIC_READ,
        FILE_SHARE_READ + FILE_SHARE_WRITE,
        attributes,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        nil
    )

    if handle == INVALID_HANDLE_VALUE then
        return nil, win_error("CreateFileW(NUL) failed")
    end

    return handle
end


-- ============================================================
-- CreateProcessW
-- ============================================================

local function create_process(commandLine, options, capture)
    if type(commandLine) ~= "string" or commandLine == "" then
        return nil, "commandLine must be a non-empty string"
    end

    options = options or {}

    local commandWide = utf8_to_wide(commandLine)

    if commandWide == nil then
        return nil, "command line is not valid UTF-8"
    end

    local cwdWide = nil

    if options.cwd ~= nil then
        cwdWide = utf8_to_wide(options.cwd)

        if cwdWide == nil then
            return nil, "cwd is not valid UTF-8"
        end
    end

    local startup = ffi.new("STARTUPINFOW[1]")
    local info = ffi.new("PROCESS_INFORMATION[1]")

    startup[0].cb = ffi.sizeof("STARTUPINFOW")

    local creationFlags = 0

    local stdoutRead = nil
    local stdoutWrite = nil

    local stderrRead = nil
    local stderrWrite = nil

    local nullInput = nil

    if options.hidden then
        startup[0].dwFlags = startup[0].dwFlags + STARTF_USESHOWWINDOW
        startup[0].wShowWindow = SW_HIDE

        creationFlags = creationFlags + CREATE_NO_WINDOW
    end

    if capture then
        local err

        stdoutRead, stdoutWrite, err = create_pipe()

        if stdoutRead == nil then
            return nil, err
        end

        stderrRead, stderrWrite, err = create_pipe()

        if stderrRead == nil then
            close_handle(stdoutRead)
            close_handle(stdoutWrite)

            return nil, err
        end

        nullInput, err = create_null_input()

        if nullInput == nil then
            close_handle(stdoutRead)
            close_handle(stdoutWrite)
            close_handle(stderrRead)
            close_handle(stderrWrite)

            return nil, err
        end

        startup[0].dwFlags =
            startup[0].dwFlags + STARTF_USESTDHANDLES

        startup[0].hStdInput = nullInput
        startup[0].hStdOutput = stdoutWrite
        startup[0].hStdError = stderrWrite
    end

    local inheritHandles = capture and 1 or 0

    local result = k32.CreateProcessW(
        nil,
        commandWide,
        nil,
        nil,
        inheritHandles,
        creationFlags,
        nil,
        cwdWide,
        startup,
        info
    )

    if result == 0 then
        local errorText = win_error("CreateProcessW failed")

        close_handle(stdoutRead)
        close_handle(stdoutWrite)

        close_handle(stderrRead)
        close_handle(stderrWrite)

        close_handle(nullInput)

        return nil, errorText
    end

    close_handle(info[0].hThread)

    if capture then
        close_handle(stdoutWrite)
        close_handle(stderrWrite)
        close_handle(nullInput)
    end

    return {
        pid = tonumber(info[0].dwProcessId),
        handle = info[0].hProcess,
        stdoutRead = stdoutRead,
        stderrRead = stderrRead
    }
end


-- ============================================================
-- Process run
-- ============================================================

function process.run(commandLine, options)
    if options == nil then
        options = {}
    end

    if type(options) ~= "table" then
        return nil, "options must be a table or nil"
    end

    local proc, err = create_process(
        commandLine,
        options,
        false
    )

    if proc == nil then
        return nil, err
    end

    local pid = proc.pid

    close_handle(proc.handle)

    return pid
end

function process.runWait(commandLine, options)
    if options == nil then
        options = {}
    end

    if type(options) ~= "table" then
        return nil, "options must be a table or nil"
    end

    local timeout = INFINITE

    if options.timeout ~= nil then
        local timeoutMs, timeoutErr =
            timeout_seconds_to_ms(options.timeout)

        if timeoutMs == nil then
            return nil, timeoutErr
        end

        timeout = timeoutMs
    end

    local proc, err = create_process(
        commandLine,
        options,
        false
    )

    if proc == nil then
        return nil, err
    end

    local waitResult = k32.WaitForSingleObject(
        proc.handle,
        timeout
    )

    if waitResult == WAIT_TIMEOUT then
        local pid = proc.pid

        close_handle(proc.handle)

        return nil, "timeout", pid
    end

    if waitResult == WAIT_FAILED then
        local errorCode = tonumber(k32.GetLastError())
        local errorText = win_error(
            "WaitForSingleObject failed",
            errorCode
        )

        close_handle(proc.handle)

        return nil, errorText
    end

    local exitCode = ffi.new("DWORD[1]")

    if k32.GetExitCodeProcess(
            proc.handle,
            exitCode
        ) == 0 then
        local errorCode = tonumber(k32.GetLastError())
        local errorText = win_error(
            "GetExitCodeProcess failed",
            errorCode
        )

        close_handle(proc.handle)

        return nil, errorText
    end

    local code = tonumber(exitCode[0])
    local pid = proc.pid

    close_handle(proc.handle)

    return code, pid
end

-- ============================================================
-- Capture stdout / stderr
-- ============================================================

local function drain_pipe(
    handle,
    chunks,
    buf,
    bufferSize,
    available,
    bytesRead,
    maxReads
)
    local totalRead = 0
    local readPasses = 0

    while maxReads == nil or readPasses < maxReads do
        available[0] = 0

        local result = k32.PeekNamedPipe(
            handle,
            nil,
            0,
            nil,
            available,
            nil
        )

        if result == 0 then
            local errorCode = tonumber(k32.GetLastError())

            if errorCode == ERROR_BROKEN_PIPE then
                return totalRead
            end

            return nil, win_error(
                "PeekNamedPipe failed",
                errorCode
            )
        end

        local count = tonumber(available[0])

        if count == 0 then
            return totalRead
        end

        if count > bufferSize then
            count = bufferSize
        end

        bytesRead[0] = 0

        result = k32.ReadFile(
            handle,
            buf,
            count,
            bytesRead,
            nil
        )

        if result == 0 then
            local errorCode = tonumber(k32.GetLastError())

            if errorCode == ERROR_BROKEN_PIPE then
                return totalRead
            end

            return nil, win_error(
                "ReadFile failed",
                errorCode
            )
        end

        local readCount = tonumber(bytesRead[0])

        if readCount == 0 then
            return totalRead
        end

        chunks[#chunks + 1] = ffi.string(buf, readCount)
        totalRead = totalRead + readCount
        readPasses = readPasses + 1
    end

    return totalRead
end


function process.runCapture(commandLine, options)
    if options == nil then
        options = {}
    end

    if type(options) ~= "table" then
        return nil, "options must be a table or nil"
    end

    local captureOptions = {}

    for key, value in pairs(options) do
        captureOptions[key] = value
    end

    if captureOptions.hidden == nil then
        captureOptions.hidden = true
    end

    local timeoutMs, timeoutErr =
        timeout_seconds_to_ms(captureOptions.timeout)

    if timeoutErr then
        return nil, timeoutErr
    end

    local proc, err = create_process(
        commandLine,
        captureOptions,
        true
    )

    if proc == nil then
        return nil, err
    end

    local stdoutChunks = {}
    local stderrChunks = {}

    local bufferSize = 65536
    local buf = ffi.new("uint8_t[?]", bufferSize)
    local available = ffi.new("DWORD[1]")
    local bytesRead = ffi.new("DWORD[1]")

    local startTime = nil
    local timedOut = false

    if timeoutMs ~= nil then
        startTime = tonumber(k32.GetTickCount64())
    end

    local function cleanup_capture()
        close_handle(proc.stdoutRead)
        close_handle(proc.stderrRead)
        close_handle(proc.handle)
    end

    local function drain_both(maxReads)
        local _, stdoutErr = drain_pipe(
            proc.stdoutRead,
            stdoutChunks,
            buf,
            bufferSize,
            available,
            bytesRead,
            maxReads
        )

        if stdoutErr then
            return nil, stdoutErr
        end

        local _, stderrErr = drain_pipe(
            proc.stderrRead,
            stderrChunks,
            buf,
            bufferSize,
            available,
            bytesRead,
            maxReads
        )

        if stderrErr then
            return nil, stderrErr
        end

        return true
    end

    local function terminate_on_timeout()
        local waitNow = k32.WaitForSingleObject(
            proc.handle,
            0
        )

        if waitNow == WAIT_OBJECT_0 then
            return false
        end

        if waitNow == WAIT_FAILED then
            local errorCode = tonumber(k32.GetLastError())
            return nil, win_error(
                "WaitForSingleObject failed",
                errorCode
            )
        end

        if k32.TerminateProcess(proc.handle, 1) == 0 then
            local terminateError = tonumber(k32.GetLastError())

            waitNow = k32.WaitForSingleObject(
                proc.handle,
                0
            )

            if waitNow ~= WAIT_OBJECT_0 then
                return nil, win_error(
                    "TerminateProcess failed",
                    terminateError
                )
            end

            return false
        end

        local waitResult = k32.WaitForSingleObject(
            proc.handle,
            INFINITE
        )

        if waitResult == WAIT_FAILED then
            local errorCode = tonumber(k32.GetLastError())
            return nil, win_error(
                "WaitForSingleObject after timeout failed",
                errorCode
            )
        end

        if waitResult ~= WAIT_OBJECT_0 then
            return nil,
                "Unexpected WaitForSingleObject result after timeout: " ..
                tostring(tonumber(waitResult))
        end

        return true
    end

    while true do
        local ok, drainErr = drain_both(4)

        if not ok then
            cleanup_capture()
            return nil, drainErr
        end

        local waitTime = 10

        if timeoutMs ~= nil then
            local elapsed =
                tonumber(k32.GetTickCount64()) - startTime
            local remaining = timeoutMs - elapsed

            if remaining <= 0 then
                local killed, timeoutKillErr =
                    terminate_on_timeout()

                if killed == nil then
                    cleanup_capture()
                    return nil, timeoutKillErr
                end

                timedOut = killed

                local finalOk, finalErr = drain_both(64)

                if not finalOk then
                    cleanup_capture()
                    return nil, finalErr
                end

                break
            end

            if remaining < waitTime then
                waitTime = math.floor(remaining)
            end
        end

        local waitResult = k32.WaitForSingleObject(
            proc.handle,
            waitTime
        )

        if waitResult == WAIT_OBJECT_0 then
            local finalOk, finalErr = drain_both(64)

            if not finalOk then
                cleanup_capture()
                return nil, finalErr
            end

            break
        end

        if waitResult == WAIT_FAILED then
            local errorCode = tonumber(k32.GetLastError())
            local errorText = win_error(
                "WaitForSingleObject failed",
                errorCode
            )

            cleanup_capture()
            return nil, errorText
        end

        if waitResult ~= WAIT_TIMEOUT then
            cleanup_capture()
            return nil,
                "Unexpected WaitForSingleObject result: " ..
                tostring(tonumber(waitResult))
        end
    end

    local exitCode = ffi.new("DWORD[1]")

    if k32.GetExitCodeProcess(
            proc.handle,
            exitCode
        ) == 0 then
        local errorCode = tonumber(k32.GetLastError())
        local errorText = win_error(
            "GetExitCodeProcess failed",
            errorCode
        )

        cleanup_capture()
        return nil, errorText
    end

    local stdoutText = table.concat(stdoutChunks)
    local stderrText = table.concat(stderrChunks)
    local code = tonumber(exitCode[0])
    local pid = proc.pid

    cleanup_capture()

    return stdoutText, stderrText, code, pid, timedOut
end

-- ============================================================
-- Snapshot
-- ============================================================

local function create_snapshot()
    local snapshot = k32.CreateToolhelp32Snapshot(
        TH32CS_SNAPPROCESS,
        0
    )

    if snapshot == INVALID_HANDLE_VALUE then
        return nil, win_error(
            "CreateToolhelp32Snapshot failed"
        )
    end

    return snapshot
end


local function basename(path)
    local name = path:match("([^\\/]+)$")

    if name then
        return name
    end

    return path
end

local function normalize_process_target(target)
    if target == nil then
        return native.os_getpid(), nil
    end

    if type(target) == "number" then
        if target ~= math.floor(target) or target < 0 or target > 0xffffffff then
            return nil, nil, "invalid PID"
        end

        return math.floor(target), nil
    end

    if type(target) ~= "string" then
        return nil, nil,
            "process target must be PID, process name or nil"
    end

    local text = trim(target)

    if text == "" then
        return native.os_getpid(), nil
    end

    if text:match("^%d+$") then
        return tonumber(text), nil
    end

    local targetName = basename(text)
    local targetWide = utf8_to_wide(targetName)

    if targetWide == nil then
        return nil, nil, "process name is not valid UTF-8"
    end

    return nil, targetWide
end

local function find_process_info(target)
    local targetPid, targetWide, targetErr =
        normalize_process_target(target)

    if targetErr then
        return nil, targetErr
    end

    local snapshot, err = create_snapshot()

    if snapshot == nil then
        return nil, err
    end

    local entry = ffi.new("PROCESSENTRY32W[1]")
    entry[0].dwSize = ffi.sizeof("PROCESSENTRY32W")

    local result = k32.Process32FirstW(
        snapshot,
        entry
    )

    if result == 0 then
        local errorCode = tonumber(k32.GetLastError())
        close_handle(snapshot)

        return nil, win_error(
            "Process32FirstW failed",
            errorCode
        )
    end

    while result ~= 0 do
        local currentPid = tonumber(entry[0].th32ProcessID)
        local matches = false

        if targetPid ~= nil then
            matches = currentPid == targetPid
        else
            local compareResult = kernelbase.CompareStringOrdinal(
                entry[0].szExeFile,
                -1,
                targetWide,
                -1,
                1
            )

            matches = compareResult == 2
        end

        if matches then
            local info = {
                pid = currentPid,
                parentPid = tonumber(
                    entry[0].th32ParentProcessID
                ),
                threads = tonumber(entry[0].cntThreads),
                name = wide_to_utf8(entry[0].szExeFile)
            }

            close_handle(snapshot)
            return info
        end

        result = k32.Process32NextW(
            snapshot,
            entry
        )
    end

    local code = tonumber(k32.GetLastError())
    close_handle(snapshot)
    if code ~= 18 then return nil, win_error("Process32NextW failed", code) end
    return nil
end

local function find_process(target)
    local info, err = find_process_info(target)

    if info == nil then
        return nil, nil, err
    end

    return info.pid, info.name
end


-- ============================================================
-- Exists
-- ============================================================

function process.exists(target)
    local pid, _, err = find_process(target)

    if err then
        return nil, err
    end

    if pid == nil then
        return false
    end

    return true, pid
end

-- ============================================================
-- Get name
-- ============================================================

function process.getName(target)
    local foundPid, name, err = find_process(target)

    if err then
        return nil, err
    end

    if foundPid == nil then
        return nil
    end

    return name
end

function process.getParent(target)
    local info, err = find_process_info(target)

    if err then
        return nil, err
    end

    if info == nil then
        return nil
    end

    return info.parentPid
end

-- ============================================================
-- Process path
-- ============================================================

function process.getPath(target)
    local pid, _, findErr = find_process(target)

    if findErr then
        return nil, findErr
    end

    if pid == nil then
        return nil
    end

    local handle = k32.OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION,
        0,
        pid
    )

    if not is_valid_handle(handle) then
        return nil, win_error("OpenProcess failed")
    end

    local pathBuf = ffi.new("WCHAR[?]", MAX_PATH_LONG)
    local pathLength = ffi.new("DWORD[1]")
    pathLength[0] = MAX_PATH_LONG

    local result = k32.QueryFullProcessImageNameW(
        handle,
        0,
        pathBuf,
        pathLength
    )

    if result == 0 then
        local errorCode = tonumber(k32.GetLastError())
        local errorText = win_error(
            "QueryFullProcessImageNameW failed",
            errorCode
        )

        close_handle(handle)
        return nil, errorText
    end

    local path = wide_to_utf8(
        pathBuf,
        tonumber(pathLength[0])
    )

    close_handle(handle)
    return path
end

-- ============================================================
-- Process list
-- ============================================================

function process.getList()
    local snapshot, err = create_snapshot()

    if snapshot == nil then
        return nil, err
    end

    local entry = ffi.new("PROCESSENTRY32W[1]")

    entry[0].dwSize =
        ffi.sizeof("PROCESSENTRY32W")

    local result = k32.Process32FirstW(
        snapshot,
        entry
    )

    if result == 0 then
        local errorCode = tonumber(k32.GetLastError())
        close_handle(snapshot)

        return nil, win_error(
            "Process32FirstW failed",
            errorCode
        )
    end

    local list = {}

    while result ~= 0 do
        list[#list + 1] = {
            pid = tonumber(
                entry[0].th32ProcessID
            ),

            parentPid = tonumber(
                entry[0].th32ParentProcessID
            ),

            threads = tonumber(
                entry[0].cntThreads
            ),

            name = wide_to_utf8(
                entry[0].szExeFile
            )
        }

        result = k32.Process32NextW(
            snapshot,
            entry
        )
    end

    local code = tonumber(k32.GetLastError())
    close_handle(snapshot)
    if code ~= 18 then return nil, win_error("Process32NextW failed", code) end

    return list
end

-- ============================================================
-- Close process
-- ============================================================

function process.close(target, exitCode)
    if target == nil
        or (type(target) == "string" and trim(target) == "")
    then
        return nil, "target is required"
    end

    local pid, _, err = find_process(target)

    if err then
        return nil, err
    end

    if pid == nil then
        return nil
    end

    if exitCode == nil then
        exitCode = 0
    else
        exitCode = tonumber(exitCode)

        if exitCode == nil
            or exitCode < 0
            or exitCode > 0xffffffff
            or exitCode ~= math.floor(exitCode)
        then
            return nil, "exitCode must be an integer from 0 to 4294967295"
        end
    end

    local handle = k32.OpenProcess(
        PROCESS_TERMINATE,
        0,
        pid
    )

    if not is_valid_handle(handle) then
        return nil, win_error("OpenProcess failed")
    end

    if k32.TerminateProcess(handle, exitCode) == 0 then
        local errorCode = tonumber(k32.GetLastError())
        local errorText = win_error(
            "TerminateProcess failed",
            errorCode
        )

        close_handle(handle)
        return nil, errorText
    end

    close_handle(handle)
    return true, pid
end

function process.setPriority(priority, target)
    if type(priority) ~= "string" then
        return nil, "priority must be a string"
    end

    local value = trim(priority):lower():gsub("[%s_%-]", "")

    local priorities = {
        l = IDLE_PRIORITY_CLASS,
        low = IDLE_PRIORITY_CLASS,
        idle = IDLE_PRIORITY_CLASS,

        b = BELOW_NORMAL_PRIORITY_CLASS,
        belownormal = BELOW_NORMAL_PRIORITY_CLASS,

        n = NORMAL_PRIORITY_CLASS,
        normal = NORMAL_PRIORITY_CLASS,

        a = ABOVE_NORMAL_PRIORITY_CLASS,
        abovenormal = ABOVE_NORMAL_PRIORITY_CLASS,

        h = HIGH_PRIORITY_CLASS,
        high = HIGH_PRIORITY_CLASS,

        r = REALTIME_PRIORITY_CLASS,
        realtime = REALTIME_PRIORITY_CLASS
    }

    local priorityClass = priorities[value]

    if priorityClass == nil then
        return nil, "unknown priority: " .. tostring(priority)
    end

    local pid, _, findErr = find_process(target)

    if findErr then
        return nil, findErr
    end

    if pid == nil then
        return nil
    end

    local handle = k32.OpenProcess(
        PROCESS_SET_INFORMATION,
        0,
        pid
    )

    if not is_valid_handle(handle) then
        return nil, win_error("OpenProcess failed")
    end

    if k32.SetPriorityClass(handle, priorityClass) == 0 then
        local errorCode = tonumber(k32.GetLastError())
        local errorText = win_error(
            "SetPriorityClass failed",
            errorCode
        )

        close_handle(handle)
        return nil, errorText
    end

    close_handle(handle)
    return true, pid
end

-- ============================================================
-- Wait
-- ============================================================

local function timeout_reached(startTime, timeoutMs)
    if timeoutMs == nil then
        return false
    end

    return tonumber(k32.GetTickCount64())
        - startTime >= timeoutMs
end

local function sleep_for_process_poll(startTime, timeoutMs)
    if timeoutMs == nil then
        native.sleep(100)
        return
    end

    local elapsed = tonumber(k32.GetTickCount64()) - startTime
    local remaining = timeoutMs - elapsed

    if remaining <= 0 then
        return
    end

    if remaining > 100 then
        native.sleep(100)
    else
        native.sleep(math.floor(remaining))
    end
end

function process.wait(target, timeout)
    if target == nil
        or (type(target) == "string" and trim(target) == "")
    then
        return nil, "target is required"
    end

    local timeoutMs, timeoutErr = timeout_seconds_to_ms(timeout)

    if timeoutErr then
        return nil, timeoutErr
    end

    local startTime = tonumber(k32.GetTickCount64())

    while true do
        local pid, _, err = find_process(target)

        if err then
            return nil, err
        end

        if pid ~= nil then
            return true, pid
        end

        if timeout_reached(startTime, timeoutMs) then
            return false
        end

        sleep_for_process_poll(startTime, timeoutMs)
    end
end

function process.waitClose(target, timeout)
    if target == nil
        or (type(target) == "string" and trim(target) == "")
    then
        return nil, "target is required"
    end

    local timeoutMs, timeoutErr = timeout_seconds_to_ms(timeout)

    if timeoutErr then
        return nil, timeoutErr
    end

    local startTime = tonumber(k32.GetTickCount64())

    while true do
        local pid, _, err = find_process(target)

        if err then
            return nil, err
        end

        if pid == nil then
            return true
        end

        if timeout_reached(startTime, timeoutMs) then
            return false, pid
        end

        sleep_for_process_poll(startTime, timeoutMs)
    end
end

-- ============================================================
-- Console output decoding
-- ============================================================

function process.getACP()
    return tonumber(k32.GetACP())
end

function process.getOEMCP()
    return tonumber(k32.GetOEMCP())
end

local function resolve_code_page(codePage)
    if codePage == nil then
        return tonumber(k32.GetOEMCP())
    end

    if type(codePage) == "number" then
        return codePage
    end

    local name =
        trim(codePage):upper()

    if name == "OEM" or name == "OEMCP" then
        return tonumber(k32.GetOEMCP())
    end

    if name == "ANSI"
        or name == "ACP"
    then
        return tonumber(k32.GetACP())
    end

    if name == "UTF8"
        or name == "UTF-8"
    then
        return CP_UTF8
    end

    local cpNumber = name:match("^CP(%d+)$")

    if cpNumber then
        return tonumber(cpNumber)
    end

    local number = tonumber(codePage)

    if number then
        return number
    end

    return nil
end


function process.decode(data, codePage)
    if data == nil or data == "" then
        return data or ""
    end

    local cp = resolve_code_page(codePage)

    if cp == nil then
        return nil, "invalid code page"
    end

    local flags = 0

    if cp == CP_UTF8 then
        flags = MB_ERR_INVALID_CHARS
    end

    local wideLength =
        k32.MultiByteToWideChar(
            cp,
            flags,
            data,
            #data,
            nil,
            0
        )

    if wideLength == 0 then
        return nil, win_error(
            "MultiByteToWideChar failed"
        )
    end

    local wideBuf = ffi.new(
        "WCHAR[?]",
        wideLength
    )

    local result =
        k32.MultiByteToWideChar(
            cp,
            flags,
            data,
            #data,
            wideBuf,
            wideLength
        )

    if result == 0 then
        return nil, win_error(
            "MultiByteToWideChar failed"
        )
    end

    return wide_to_utf8(
        wideBuf,
        wideLength
    )
end

-- ============================================================
-- AHK v2-like public interface
-- Names are AHK-like; return values follow Lua conventions.
-- ============================================================

local function make_run_options(workingDir, options)
    local result = {}

    if workingDir ~= nil and tostring(workingDir) ~= "" then
        result.cwd = tostring(workingDir)
    end

    if options == nil or options == "" then
        return result
    end

    if type(options) == "table" then
        for key, value in pairs(options) do
            result[key] = value
        end

        if result.cwd == nil and workingDir ~= nil
            and tostring(workingDir) ~= ""
        then
            result.cwd = tostring(workingDir)
        end

        if result.hide ~= nil and result.hidden == nil then
            result.hidden = not not result.hide
        end

        return result
    end

    if type(options) ~= "string" then
        return nil, "options must be string, table or nil"
    end

    for word in options:gmatch("%S+") do
        if word:lower() == "hide" then
            result.hidden = true
        else
            return nil, "unsupported Run option: " .. word
        end
    end

    return result
end

function process.ProcessExist(target)
    return process.exists(target)
end

function process.ProcessClose(target)
    return process.close(target, 0)
end

function process.ProcessGetName(target)
    return process.getName(target)
end

function process.ProcessGetParent(target)
    return process.getParent(target)
end

function process.ProcessGetPath(target)
    return process.getPath(target)
end

function process.ProcessSetPriority(priority, target)
    return process.setPriority(priority, target)
end

function process.ProcessWait(target, timeout)
    return process.wait(target, timeout)
end

function process.ProcessWaitClose(target, timeout)
    return process.waitClose(target, timeout)
end

function process.ProcessGetList()
    return process.getList()
end

function process.Run(target, workingDir, options)
    if type(target) ~= "string" or trim(target) == "" then
        return nil, "target must be a non-empty command line"
    end

    local runOptions, optionsErr = make_run_options(
        workingDir,
        options
    )

    if runOptions == nil then
        return nil, optionsErr
    end

    return process.run(target, runOptions)
end

function process.RunWait(target, workingDir, options)
    if type(target) ~= "string" or trim(target) == "" then
        return nil, "target must be a non-empty command line"
    end

    local runOptions, optionsErr = make_run_options(
        workingDir,
        options
    )

    if runOptions == nil then
        return nil, optionsErr
    end

    return process.runWait(target, runOptions)
end

function process.RunCapture(target, workingDir, options)
    if type(target) ~= "string" or trim(target) == "" then
        return nil, "target must be a non-empty command line"
    end

    local runOptions, optionsErr = make_run_options(
        workingDir,
        options
    )

    if runOptions == nil then
        return nil, optionsErr
    end

    local stdoutText, stderrText, exitCode, pid, timedOut =
        process.runCapture(target, runOptions)

    if stdoutText == nil then
        return nil, stderrText
    end

    return {
        pid = pid,
        exitCode = exitCode,
        stdout = stdoutText,
        stderr = stderrText,
        timedOut = timedOut,
        ok = exitCode == 0 and not timedOut
    }
end

function process.QuoteArg(value)
    return process.quoteArg(value)
end

function process.Command(program, args)
    return process.command(program, args)
end

-- Structured arguments use the same native quoting and capture path as Run*.
local function exec_native(program, args, workingDir, options, kind)
    local command, err = process.Command(program, args)
    if not command then return nil, err end
    local opts; opts, err = make_run_options(workingDir, options)
    if not opts then return nil, err end
    if type(args) ~= 'string' then
        local _, timeoutErr = timeout_seconds_to_ms(opts.timeout)
        if timeoutErr then return nil, timeoutErr end
    end
    if kind == 'capture' then return process.RunCapture(command, workingDir, options) end
    if kind == 'wait' then return process.RunWait(command, workingDir, options) end
    return process.Run(command, workingDir, options)
end

function process.Exec(program, args, workingDir, options)
    return exec_native(program, args, workingDir, options, 'capture')
end

function process.ExecRun(program, args, workingDir, options)
    return exec_native(program, args, workingDir, options, 'run')
end

function process.ExecWait(program, args, workingDir, options)
    return exec_native(program, args, workingDir, options, 'wait')
end
function process.ExecShell(command, workingDir, options)
    if type(command) ~= "string" or trim(command) == "" then
        return nil, "command must be a non-empty string"
    end

    local comspec, envErr, envCode = native.os_getenv('ComSpec')
    if envErr and envCode ~= 'ENOENT' then return nil, envErr end

    if comspec == nil or comspec == "" then
        comspec = "C:\\Windows\\System32\\cmd.exe"
    end

    local commandLine =
        process.quoteArg(comspec) ..
        ' /D /S /C "' ..
        command ..
        '"'

    return process.RunCapture(commandLine, workingDir, options)
end

function process.GetACP()
    return process.getACP()
end

function process.GetOEMCP()
    return process.getOEMCP()
end

function process.Decode(data, codePage)
    return process.decode(data, codePage)
end

return process

