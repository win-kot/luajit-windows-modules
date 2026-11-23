---@diagnostic disable: undefined-field, inject-field

local ffi = require("ffi")
local native = require("_win_native")

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

local function Utf8ToWide(text)
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


local function WideToUtf8(wideText, length)
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

local errors = require("_errors")
local function WinError(prefix, errorCode)
    local _, message = errors.Win32(prefix, errorCode)
    return message
end

-- ============================================================
-- Handle helpers
-- ============================================================

local function IsValidHandle(handle)
    return handle ~= nil
        and handle ~= ffi.NULL
        and handle ~= INVALID_HANDLE_VALUE
end


local function CloseHandle(handle)
    if IsValidHandle(handle) then
        k32.CloseHandle(handle)
    end
end

local function Trim(value)
    return tostring(value):match("^%s*(.-)%s*$")
end

local function TimeoutSecondsToMs(timeout)
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

local QuoteArgument = require('_win_quote')
function process.ArgQuote(value)
    return QuoteArgument(tostring(value))
end

function process.Command(exePath, args)
    if type(exePath) ~= "string" or exePath == "" then
        return nil, "program must be a non-empty string"
    end

    local parts = {
        process.ArgQuote(exePath)
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
        parts[#parts + 1] = process.ArgQuote(args[index])
    end

    return table.concat(parts, " ")
end

-- ============================================================
-- Pipe helpers
-- ============================================================

local function CreatePipe()
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
        local _, message, code = errors.Win32("CreatePipe")
        return nil, nil, message, code
    end

    if k32.SetHandleInformation(
            readHandle[0],
            HANDLE_FLAG_INHERIT,
            0
        ) == 0 then
        local _, errorText, errorCode = errors.Win32("SetHandleInformation")

        CloseHandle(readHandle[0])
        CloseHandle(writeHandle[0])

        return nil, nil, errorText, errorCode
    end

    return readHandle[0], writeHandle[0]
end


local function CreateNullInput()
    local attributes = ffi.new("SECURITY_ATTRIBUTES[1]")

    attributes[0].nLength = ffi.sizeof("SECURITY_ATTRIBUTES")
    attributes[0].lpSecurityDescriptor = nil
    attributes[0].bInheritHandle = 1

    local nullName = Utf8ToWide("NUL")

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
        return errors.Win32("CreateFileW(NUL) failed")
    end

    return handle
end


-- ============================================================
-- CreateProcessW
-- ============================================================

local function CreateProcess(commandLine, options, capture)
    if type(commandLine) ~= "string" or commandLine == "" then
        return nil, "commandLine must be a non-empty string"
    end

    options = options or {}

    local commandWide = Utf8ToWide(commandLine)

    if commandWide == nil then
        return nil, "command line is not valid UTF-8"
    end

    local cwdWide = nil

    if options.cwd ~= nil then
        cwdWide = Utf8ToWide(options.cwd)

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
        local err, code

        stdoutRead, stdoutWrite, err, code = CreatePipe()

        if stdoutRead == nil then
            return nil, err, code
        end

        stderrRead, stderrWrite, err, code = CreatePipe()

        if stderrRead == nil then
            CloseHandle(stdoutRead)
            CloseHandle(stdoutWrite)

            return nil, err, code
        end

        nullInput, err, code = CreateNullInput()

        if nullInput == nil then
            CloseHandle(stdoutRead)
            CloseHandle(stdoutWrite)
            CloseHandle(stderrRead)
            CloseHandle(stderrWrite)

            return nil, err, code
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
        local _, errorText, errorCode = errors.Win32("CreateProcessW")

        CloseHandle(stdoutRead)
        CloseHandle(stdoutWrite)

        CloseHandle(stderrRead)
        CloseHandle(stderrWrite)

        CloseHandle(nullInput)

        return nil, errorText, errorCode
    end

    CloseHandle(info[0].hThread)

    if capture then
        CloseHandle(stdoutWrite)
        CloseHandle(stderrWrite)
        CloseHandle(nullInput)
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

function process.Run(commandLine, options)
    if options == nil then
        options = {}
    end

    if type(options) ~= "table" then
        return nil, "options must be a table or nil"
    end

    local proc, err, code = CreateProcess(
        commandLine,
        options,
        false
    )

    if proc == nil then
        return nil, err, code
    end

    local pid = proc.pid

    CloseHandle(proc.handle)

    return pid
end

function process.RunWait(commandLine, options)
    if options == nil then
        options = {}
    end

    if type(options) ~= "table" then
        return nil, "options must be a table or nil"
    end

    local timeout = INFINITE

    if options.timeout ~= nil then
        local timeoutMs, timeoutErr =
            TimeoutSecondsToMs(options.timeout)

        if timeoutMs == nil then
            return nil, timeoutErr
        end

        timeout = timeoutMs
    end

    local proc, err, code = CreateProcess(
        commandLine,
        options,
        false
    )

    if proc == nil then
        return nil, err, code
    end

    local waitResult = k32.WaitForSingleObject(
        proc.handle,
        timeout
    )

    if waitResult == WAIT_TIMEOUT then
        local pid = proc.pid

        CloseHandle(proc.handle)

        return nil, "timeout", pid
    end

    if waitResult == WAIT_FAILED then
        local errorCode = tonumber(k32.GetLastError())
        local errorText = WinError(
            "WaitForSingleObject failed",
            errorCode
        )

        CloseHandle(proc.handle)

        return nil, errorText, errorCode
    end

    local exitCode = ffi.new("DWORD[1]")

    if k32.GetExitCodeProcess(
            proc.handle,
            exitCode
        ) == 0 then
        local errorCode = tonumber(k32.GetLastError())
        local errorText = WinError(
            "GetExitCodeProcess failed",
            errorCode
        )

        CloseHandle(proc.handle)

        return nil, errorText, errorCode
    end

    local code = tonumber(exitCode[0])
    local pid = proc.pid

    CloseHandle(proc.handle)

    return code, pid
end

-- ============================================================
-- Capture stdout / stderr
-- ============================================================

local function DrainPipe(
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

            return errors.Win32(
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

            return errors.Win32(
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


function process.RunCapture(commandLine, options)
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
        TimeoutSecondsToMs(captureOptions.timeout)

    if timeoutErr then
        return nil, timeoutErr
    end

    local proc, err, code = CreateProcess(
        commandLine,
        captureOptions,
        true
    )

    if proc == nil then
        return nil, err, code
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

    local function CleanupCapture()
        CloseHandle(proc.stdoutRead)
        CloseHandle(proc.stderrRead)
        CloseHandle(proc.handle)
    end

    local function DrainBoth(maxReads)
        local _, stdoutErr, stdoutCode = DrainPipe(
            proc.stdoutRead,
            stdoutChunks,
            buf,
            bufferSize,
            available,
            bytesRead,
            maxReads
        )

        if stdoutErr then
            return nil, stdoutErr, stdoutCode
        end

        local _, stderrErr, stderrCode = DrainPipe(
            proc.stderrRead,
            stderrChunks,
            buf,
            bufferSize,
            available,
            bytesRead,
            maxReads
        )

        if stderrErr then
            return nil, stderrErr, stderrCode
        end

        return true
    end

    local function TerminateOnTimeout()
        local waitNow = k32.WaitForSingleObject(
            proc.handle,
            0
        )

        if waitNow == WAIT_OBJECT_0 then
            return false
        end

        if waitNow == WAIT_FAILED then
            local errorCode = tonumber(k32.GetLastError())
            return errors.Win32(
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
                return errors.Win32(
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
            return errors.Win32(
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
        local ok, drainErr, status = DrainBoth(4)

        if not ok then
            CleanupCapture()
            return nil, drainErr, status
        end

        local waitTime = 10

        if timeoutMs ~= nil then
            local elapsed =
                tonumber(k32.GetTickCount64()) - startTime
            local remaining = timeoutMs - elapsed

            if remaining <= 0 then
                local killed, timeoutKillErr, status =
                    TerminateOnTimeout()

                if killed == nil then
                    CleanupCapture()
                    return nil, timeoutKillErr, status
                end

                timedOut = killed

                local finalOk, finalErr, status = DrainBoth(64)

                if not finalOk then
                    CleanupCapture()
                    return nil, finalErr, status
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
            local finalOk, finalErr, status = DrainBoth(64)

            if not finalOk then
                CleanupCapture()
                return nil, finalErr, status
            end

            break
        end

        if waitResult == WAIT_FAILED then
            local errorCode = tonumber(k32.GetLastError())
            local errorText = WinError(
                "WaitForSingleObject failed",
                errorCode
            )

            CleanupCapture()
            return nil, errorText, errorCode
        end

        if waitResult ~= WAIT_TIMEOUT then
            CleanupCapture()
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
        local errorText = WinError(
            "GetExitCodeProcess failed",
            errorCode
        )

        CleanupCapture()
        return nil, errorText, errorCode
    end

    local stdoutText = table.concat(stdoutChunks)
    local stderrText = table.concat(stderrChunks)
    local code = tonumber(exitCode[0])
    local pid = proc.pid

    CleanupCapture()

    return stdoutText, stderrText, code, pid, timedOut
end

-- ============================================================
-- Snapshot
-- ============================================================

local function CreateSnapshot()
    local snapshot = k32.CreateToolhelp32Snapshot(
        TH32CS_SNAPPROCESS,
        0
    )

    if snapshot == INVALID_HANDLE_VALUE then
        return errors.Win32(
            "CreateToolhelp32Snapshot failed"
        )
    end

    return snapshot
end


local function BaseName(path)
    local name = path:match("([^\\/]+)$")

    if name then
        return name
    end

    return path
end

local function NormalizeProcessTarget(target)
    if target == nil then
        return native.OsGetpid(), nil
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

    local text = Trim(target)

    if text == "" then
        return native.OsGetpid(), nil
    end

    if text:match("^%d+$") then
        return tonumber(text), nil
    end

    local targetName = BaseName(text)
    local targetWide = Utf8ToWide(targetName)

    if targetWide == nil then
        return nil, nil, "process name is not valid UTF-8"
    end

    return nil, targetWide
end

local function FindProcessInfo(target)
    local targetPid, targetWide, targetErr =
        NormalizeProcessTarget(target)

    if targetErr then
        return nil, targetErr
    end

    local snapshot, err = CreateSnapshot()

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
        CloseHandle(snapshot)

        return errors.Win32(
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
                name = WideToUtf8(entry[0].szExeFile)
            }

            CloseHandle(snapshot)
            return info
        end

        result = k32.Process32NextW(
            snapshot,
            entry
        )
    end

    local code = tonumber(k32.GetLastError())
    CloseHandle(snapshot)
    if code ~= 18 then return errors.Win32("Process32NextW failed", code) end
    return nil
end

local function FindProcess(target)
    local info, err = FindProcessInfo(target)

    if info == nil then
        return nil, nil, err
    end

    return info.pid, info.name
end


-- ============================================================
-- Exists
-- ============================================================

function process.Exists(target)
    local pid, _, err = FindProcess(target)

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

function process.NameGet(target)
    local foundPid, name, err = FindProcess(target)

    if err then
        return nil, err
    end

    if foundPid == nil then
        return nil
    end

    return name
end

function process.ParentGet(target)
    local info, err = FindProcessInfo(target)

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

function process.PathGet(target)
    local pid, _, findErr = FindProcess(target)

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

    if not IsValidHandle(handle) then
        return errors.Win32("OpenProcess failed")
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
        local errorText = WinError(
            "QueryFullProcessImageNameW failed",
            errorCode
        )

        CloseHandle(handle)
        return nil, errorText, errorCode
    end

    local path = WideToUtf8(
        pathBuf,
        tonumber(pathLength[0])
    )

    CloseHandle(handle)
    return path
end

-- ============================================================
-- Process list
-- ============================================================

function process.ListGet()
    local snapshot, err = CreateSnapshot()

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
        CloseHandle(snapshot)

        return errors.Win32(
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

            name = WideToUtf8(
                entry[0].szExeFile
            )
        }

        result = k32.Process32NextW(
            snapshot,
            entry
        )
    end

    local code = tonumber(k32.GetLastError())
    CloseHandle(snapshot)
    if code ~= 18 then return errors.Win32("Process32NextW failed", code) end

    return list
end

-- ============================================================
-- Close process
-- ============================================================

function process.Close(target, exitCode)
    if target == nil
        or (type(target) == "string" and Trim(target) == "")
    then
        return nil, "target is required"
    end

    local pid, _, err = FindProcess(target)

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

    if not IsValidHandle(handle) then
        return errors.Win32("OpenProcess failed")
    end

    if k32.TerminateProcess(handle, exitCode) == 0 then
        local errorCode = tonumber(k32.GetLastError())
        local errorText = WinError(
            "TerminateProcess failed",
            errorCode
        )

        CloseHandle(handle)
        return nil, errorText, errorCode
    end

    CloseHandle(handle)
    return true, pid
end

function process.PrioritySet(priority, target)
    if type(priority) ~= "string" then
        return nil, "priority must be a string"
    end

    local value = Trim(priority):lower():gsub("[%s_%-]", "")

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

    local pid, _, findErr = FindProcess(target)

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

    if not IsValidHandle(handle) then
        return errors.Win32("OpenProcess failed")
    end

    if k32.SetPriorityClass(handle, priorityClass) == 0 then
        local errorCode = tonumber(k32.GetLastError())
        local errorText = WinError(
            "SetPriorityClass failed",
            errorCode
        )

        CloseHandle(handle)
        return nil, errorText, errorCode
    end

    CloseHandle(handle)
    return true, pid
end

-- ============================================================
-- Wait
-- ============================================================

local function TimeoutReached(startTime, timeoutMs)
    if timeoutMs == nil then
        return false
    end

    return tonumber(k32.GetTickCount64())
        - startTime >= timeoutMs
end

local function SleepForProcessPoll(startTime, timeoutMs)
    if timeoutMs == nil then
        native.Sleep(100)
        return
    end

    local elapsed = tonumber(k32.GetTickCount64()) - startTime
    local remaining = timeoutMs - elapsed

    if remaining <= 0 then
        return
    end

    if remaining > 100 then
        native.Sleep(100)
    else
        native.Sleep(math.floor(remaining))
    end
end

function process.Wait(target, timeout)
    if target == nil
        or (type(target) == "string" and Trim(target) == "")
    then
        return nil, "target is required"
    end

    local timeoutMs, timeoutErr = TimeoutSecondsToMs(timeout)

    if timeoutErr then
        return nil, timeoutErr
    end

    local startTime = tonumber(k32.GetTickCount64())

    while true do
        local pid, _, err = FindProcess(target)

        if err then
            return nil, err
        end

        if pid ~= nil then
            return true, pid
        end

        if TimeoutReached(startTime, timeoutMs) then
            return false
        end

        SleepForProcessPoll(startTime, timeoutMs)
    end
end

function process.WaitClose(target, timeout)
    if target == nil
        or (type(target) == "string" and Trim(target) == "")
    then
        return nil, "target is required"
    end

    local timeoutMs, timeoutErr = TimeoutSecondsToMs(timeout)

    if timeoutErr then
        return nil, timeoutErr
    end

    local startTime = tonumber(k32.GetTickCount64())

    while true do
        local pid, _, err = FindProcess(target)

        if err then
            return nil, err
        end

        if pid == nil then
            return true
        end

        if TimeoutReached(startTime, timeoutMs) then
            return false, pid
        end

        SleepForProcessPoll(startTime, timeoutMs)
    end
end

-- ============================================================
-- Console output decoding
-- ============================================================

function process.AcpGet()
    return tonumber(k32.GetACP())
end

function process.OemcpGet()
    return tonumber(k32.GetOEMCP())
end

local function ResolveCodePage(codePage)
    if codePage == nil then
        return tonumber(k32.GetOEMCP())
    end

    if type(codePage) == "number" then
        return codePage
    end

    local name =
        Trim(codePage):upper()

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


function process.Decode(data, codePage)
    if data == nil or data == "" then
        return data or ""
    end

    local cp = ResolveCodePage(codePage)

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
        return errors.Win32(
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
        return errors.Win32(
            "MultiByteToWideChar failed"
        )
    end

    return WideToUtf8(
        wideBuf,
        wideLength
    )
end

-- ============================================================
-- Structured execution helpers. Public names use lower camelCase.
-- ============================================================

local function MakeRunOptions(workingDir, options)
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

local function CaptureResult(target, runOptions)
    if type(target) ~= "string" or Trim(target) == "" then
        return nil, "target must be a non-empty command line"
    end

    local stdoutText, stderrText, exitCode, pid, timedOut =
        process.RunCapture(target, runOptions)

    if stdoutText == nil then
        return nil, stderrText, exitCode
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

-- Structured arguments use the same quoting and execution paths as run*.
local function ExecNative(program, args, workingDir, options, kind)
    local command, err = process.Command(program, args)
    if not command then return nil, err end
    local opts; opts, err = MakeRunOptions(workingDir, options)
    if not opts then return nil, err end
    if type(args) ~= 'string' then
        local _, timeoutErr = TimeoutSecondsToMs(opts.timeout)
        if timeoutErr then return nil, timeoutErr end
    end
    if kind == 'capture' then return CaptureResult(command, opts) end
    if kind == 'wait' then return process.RunWait(command, opts) end
    return process.Run(command, opts)
end

function process.Exec(program, args, workingDir, options)
    return ExecNative(program, args, workingDir, options, 'capture')
end

function process.ExecRun(program, args, workingDir, options)
    return ExecNative(program, args, workingDir, options, 'run')
end

function process.ExecWait(program, args, workingDir, options)
    return ExecNative(program, args, workingDir, options, 'wait')
end
function process.ExecShell(command, workingDir, options)
    if type(command) ~= "string" or Trim(command) == "" then
        return nil, "command must be a non-empty string"
    end

    local comspec, envErr, envCode = native.OsGetEnv('ComSpec')
    if envErr and envCode ~= 203 then return nil, envErr, envCode end

    if comspec == nil or comspec == "" then
        comspec = "C:\\Windows\\System32\\cmd.exe"
    end

    local commandLine =
        process.ArgQuote(comspec) ..
        ' /D /S /C "' ..
        command ..
        '"'

    local opts, err = MakeRunOptions(workingDir, options)
    if not opts then return nil, err end
    return CaptureResult(commandLine, opts)
end

do
    local native = require("_win_native")
    local win = require("_win_extension")
    ffi.cdef[[
    typedef struct {
        unsigned long size, pageFaultCount;
        size_t peakWorkingSetBytes, workingSetBytes, quotaPeakPagedPoolBytes, quotaPagedPoolBytes,
            quotaPeakNonPagedPoolBytes, quotaNonPagedPoolBytes, pagefileBytes, peakPagefileBytes, privateBytes;
    } fw_process_memory;
    typedef struct { uint32_t low, high; } fw_process_filetime;
    int __stdcall K32GetProcessMemoryInfo(void *, fw_process_memory *, unsigned long);
    int __stdcall IsWow64Process2(void *, uint16_t *, uint16_t *);
    int __stdcall IsWow64Process(void *, int *);
    void __stdcall fw_GetNativeSystemInfo(void *) __asm__("GetNativeSystemInfo");
    int __stdcall fw_GetProcessTimes(void *, fw_process_filetime *, fw_process_filetime *,
        fw_process_filetime *, fw_process_filetime *) __asm__("GetProcessTimes");
    uint32_t __stdcall GetActiveProcessorCount(uint16_t);
    unsigned long __stdcall WaitForInputIdle(void *, unsigned long);
    ]]
    local function withProcess(pid, access, query)
        if not win.Integer(pid, 1, 0xFFFFFFFF) then return win.Error("Invalid PID", 87) end
        local handle = k32.OpenProcess(access, 0, pid)
        if handle == nil then return win.Error("OpenProcess") end
        win.Own(handle)
        local result, err, code = query(handle)
        win.Close(handle)
        return result, err, code
    end

    function process.IdGet() return native.OsGetpid() end

    function process.ExitCodeGet(pid)
        return withProcess(pid, 0x1000, function(handle)
            local result = ffi.new("DWORD[1]")
            if k32.GetExitCodeProcess(handle, result) == 0 then return win.Error("GetExitCodeProcess") end
            return tonumber(result[0])
        end)
    end

    function process.MemoryGet(pid)
        return withProcess(pid, 0x410, function(handle)
            local info = ffi.new("fw_process_memory[1]")
            info[0].size = ffi.sizeof(info[0])
            if k32.K32GetProcessMemoryInfo(handle, info, info[0].size) == 0 then
                return win.Error("GetProcessMemoryInfo")
            end
            local data = {pageFaultCount = tonumber(info[0].pageFaultCount)}
            for _, field in ipairs({"workingSetBytes", "peakWorkingSetBytes", "pagefileBytes",
                "peakPagefileBytes", "privateBytes", "quotaPeakPagedPoolBytes", "quotaPagedPoolBytes",
                "quotaPeakNonPagedPoolBytes", "quotaNonPagedPoolBytes"}) do
                data[field] = win.Exact(info[0][field])
            end
            return data
        end)
    end

    local architectures = {[0x014C] = "x86", [0x8664] = "x64", [0xAA64] = "ARM64", [0x01C4] = "ARM"}
    function process.ArchitectureGet(pid)
        return withProcess(pid, 0x1000, function(handle)
            local query = win.Symbol(k32, "IsWow64Process2")
            if query then
                local machine, host = ffi.new("uint16_t[1]"), ffi.new("uint16_t[1]")
                if query(handle, machine, host) == 0 then return win.Error("IsWow64Process2") end
                local processMachine = machine[0] ~= 0 and machine[0] or host[0]
                return architectures[processMachine] or "unknown", architectures[host[0]] or "unknown"
            end
            local wow = ffi.new("int[1]")
            if k32.IsWow64Process(handle, wow) == 0 then return win.Error("IsWow64Process") end
            local systemInfo = ffi.new("uint64_t[6]")
            k32.fw_GetNativeSystemInfo(systemInfo)
            local host = ({[0] = "x86", [9] = "x64", [12] = "ARM64"})[ffi.cast("uint16_t *", systemInfo)[0]] or "unknown"
            if host == "ARM64" then return "unknown", host end
            return wow[0] ~= 0 and "x86" or host, host
        end)
    end

    local function getProcessTimes(handle)
        local times = ffi.new("fw_process_filetime[4]")
        if k32.fw_GetProcessTimes(handle, times, times + 1, times + 2, times + 3) == 0 then
            return win.Error("GetProcessTimes")
        end
        return times
    end

    local function ticks(time)
        return time.high * 4294967296ULL + time.low
    end

    function process.TimesGet(pid)
        return withProcess(pid, 0x1000, function(handle)
            local times, err, code = getProcessTimes(handle)
            if not times then return nil, err, code end
            return {created100ns = win.Exact(ticks(times[0])), exited100ns = win.Exact(ticks(times[1])),
                kernel100ns = win.Exact(ticks(times[2])), user100ns = win.Exact(ticks(times[3]))}
        end)
    end

    function process.GetCPUUsage(pid, intervalMs)
        local interval, err, code = win.Timeout(intervalMs, 250)
        if not interval then return nil, err, code end
        if interval == 0 then return win.Error("intervalMs must be positive", 87) end
        local processors = k32.GetActiveProcessorCount(0xFFFF)
        if processors == 0 then return win.Error("GetActiveProcessorCount") end
        local now = require("timer").Now
        -- Hold the same handle for the two samples, even if the PID is reused.
        return withProcess(pid, 0x101000, function(handle)
            local before, message, status = getProcessTimes(handle)
            if not before then return nil, message, status end
            local started = now()
            local waited = k32.WaitForSingleObject(handle, interval)
            if waited == 0 then return win.Error("Process exited during CPU measurement", 1067) end
            if waited ~= 258 then return win.Error("WaitForSingleObject") end
            local after
            after, message, status = getProcessTimes(handle)
            if not after then return nil, message, status end
            local elapsed = now() - started
            local cpu = ticks(after[2]) - ticks(before[2]) + ticks(after[3]) - ticks(before[3])
            local cpuSeconds = tonumber(cpu) / 10000000
            return math.min(100, 100 * cpuSeconds / (elapsed * processors))
        end)
    end

    function process.InputIdleWait(pid, timeoutMs)
        local timeout, err, code = win.Timeout(timeoutMs, 5000)
        if not timeout then return nil, err, code end
        return withProcess(pid, 0x100400, function(handle)
            local user32 = ffi.load("user32")
            local result = user32.WaitForInputIdle(handle, timeout)
            if result == 0 then return true end
            if result == 258 then return false end
            return win.Error("WaitForInputIdle")
        end)
    end
end

return process

