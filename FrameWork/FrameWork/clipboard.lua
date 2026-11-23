local ffi = require("ffi")

ffi.cdef [[
typedef void *HANDLE;
typedef HANDLE HWND;
typedef HANDLE HGLOBAL;
typedef HANDLE HINSTANCE;
typedef HANDLE HMENU;
typedef void *LPVOID;
typedef const void *LPCVOID;

typedef uint16_t WCHAR;
typedef uint32_t DWORD;
typedef uint32_t UINT;
typedef int32_t BOOL;
typedef uintptr_t SIZE_T;

BOOL __stdcall OpenClipboard(HWND hWndNewOwner);
BOOL __stdcall CloseClipboard(void);
BOOL __stdcall EmptyClipboard(void);

HANDLE __stdcall GetClipboardData(UINT uFormat);
HANDLE __stdcall SetClipboardData(UINT uFormat, HANDLE hMem);

BOOL __stdcall IsClipboardFormatAvailable(UINT format);
DWORD __stdcall GetClipboardSequenceNumber(void);

HWND __stdcall CreateWindowExW(
    DWORD dwExStyle,
    const WCHAR *lpClassName,
    const WCHAR *lpWindowName,
    DWORD dwStyle,
    int X,
    int Y,
    int nWidth,
    int nHeight,
    HWND hWndParent,
    HMENU hMenu,
    HINSTANCE hInstance,
    LPVOID lpParam
);

BOOL __stdcall DestroyWindow(HWND hWnd);

HGLOBAL __stdcall GlobalAlloc(
    UINT uFlags,
    SIZE_T dwBytes
);

LPVOID __stdcall GlobalLock(
    HGLOBAL hMem
);

BOOL __stdcall GlobalUnlock(
    HGLOBAL hMem
);

HGLOBAL __stdcall GlobalFree(
    HGLOBAL hMem
);

SIZE_T __stdcall GlobalSize(
    HGLOBAL hMem
);

HINSTANCE __stdcall GetModuleHandleW(
    const WCHAR *lpModuleName
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

int __stdcall MultiByteToWideChar(
    UINT CodePage,
    DWORD dwFlags,
    const char *lpMultiByteStr,
    int cbMultiByte,
    WCHAR *lpWideCharStr,
    int cchWideChar
);

int __stdcall WideCharToMultiByte(
    UINT CodePage,
    DWORD dwFlags,
    const WCHAR *lpWideCharStr,
    int cchWideChar,
    char *lpMultiByteStr,
    int cbMultiByte,
    const char *lpDefaultChar,
    BOOL *lpUsedDefaultChar
);

void __stdcall Sleep(DWORD dwMilliseconds);
]]

local user32 = ffi.load("user32")
local kernel32 = ffi.load("kernel32")

local clipboard = {}

local CF_UNICODETEXT = 13

local GMEM_MOVEABLE = 0x0002
local GMEM_ZEROINIT = 0x0040

local CP_UTF8 = 65001
local MB_ERR_INVALID_CHARS = 0x00000008

local FORMAT_MESSAGE_IGNORE_INSERTS = 0x00000200
local FORMAT_MESSAGE_FROM_SYSTEM = 0x00001000

local HWND_MESSAGE = ffi.cast("HWND", -3)

local ownerHwnd = nil


-- ============================================================
-- UTF-8 -> UTF-16
-- ============================================================

local function Utf8ToWide(text)
    if text == nil then
        return nil, nil
    end

    if text == "" then
        local wideBuf = ffi.new("WCHAR[1]")
        wideBuf[0] = 0

        return wideBuf, 0
    end

    local wideLength = kernel32.MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        text,
        #text,
        nil,
        0
    )

    if wideLength == 0 then
        return nil, nil
    end

    local wideBuf = ffi.new(
        "WCHAR[?]",
        wideLength + 1
    )

    local result = kernel32.MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        text,
        #text,
        wideBuf,
        wideLength
    )

    if result == 0 then
        return nil, nil
    end

    wideBuf[wideLength] = 0

    return wideBuf, wideLength
end


-- ============================================================
-- UTF-16 -> UTF-8
-- ============================================================

local function WideToUtf8(wideText, wideLength)
    if wideText == nil then
        return ""
    end

    if wideLength == 0 then
        return ""
    end

    local utf8Length = kernel32.WideCharToMultiByte(
        CP_UTF8,
        0,
        wideText,
        wideLength,
        nil,
        0,
        nil,
        nil
    )

    if utf8Length == 0 then
        return nil
    end

    local utf8Buf = ffi.new(
        "char[?]",
        utf8Length
    )

    local result = kernel32.WideCharToMultiByte(
        CP_UTF8,
        0,
        wideText,
        wideLength,
        utf8Buf,
        utf8Length,
        nil,
        nil
    )

    if result == 0 then
        return nil
    end

    return ffi.string(
        utf8Buf,
        utf8Length
    )
end


-- ============================================================
-- Win32 error
-- ============================================================

local WinError = require("_errors").Win32

local function GetOwnerWindow()
    if ownerHwnd ~= nil
        and ownerHwnd ~= ffi.NULL
    then
        return ownerHwnd
    end

    local classWide =
        Utf8ToWide("STATIC")

    local titleWide =
        Utf8ToWide(
            "LuaJIT Clipboard Owner"
        )

    local instance =
        kernel32.GetModuleHandleW(nil)

    local hwnd =
        user32.CreateWindowExW(
            0,
            classWide,
            titleWide,
            0,
            0,
            0,
            0,
            0,
            HWND_MESSAGE,
            nil,
            instance,
            nil
        )

    if hwnd == nil
        or hwnd == ffi.NULL
    then
        local code = tonumber(kernel32.GetLastError())
        return WinError("CreateWindowExW", code)
    end

    ownerHwnd = ffi.gc(hwnd, function(h) user32.DestroyWindow(h) end)

    return ownerHwnd
end


-- ============================================================
-- Open clipboard
-- ============================================================

local function OpenClipboard()
    local hwnd, err, code =
        GetOwnerWindow()

    if not hwnd then
        return nil, err, code
    end

    -- Clipboard can temporarily be opened by
    -- another application.
    for attempt = 1, 50 do
        if user32.OpenClipboard(hwnd) ~= 0 then
            return true
        end

        code = tonumber(kernel32.GetLastError())
        kernel32.Sleep(10)
    end

    return WinError("OpenClipboard", code)
end


-- ============================================================
-- Has Unicode text
-- ============================================================

function clipboard.TextExists()
    return user32.IsClipboardFormatAvailable(
        CF_UNICODETEXT
    ) ~= 0
end

-- ============================================================
-- Read text
-- ============================================================

function clipboard.TextGet()
    if not clipboard.TextExists() then
        return nil
    end

    local ok, err, code = OpenClipboard()

    if not ok then
        return nil, err, code
    end

    local memoryHandle =
        user32.GetClipboardData(
            CF_UNICODETEXT
        )

    if memoryHandle == nil
        or memoryHandle == ffi.NULL
    then
        local _, errorText, errorCode = WinError(
                "GetClipboardData failed"
            )

        user32.CloseClipboard()

        return nil, errorText, errorCode
    end

    local memorySize =
        tonumber(
            kernel32.GlobalSize(
                memoryHandle
            )
        )

    if memorySize == 0 then
        local _, err, status = WinError("GlobalSize")
        user32.CloseClipboard()
        return nil, err, status
    end

    local memoryPtr =
        kernel32.GlobalLock(
            memoryHandle
        )

    if memoryPtr == nil
        or memoryPtr == ffi.NULL
    then
        local _, errorText, errorCode = WinError(
                "GlobalLock failed"
            )

        user32.CloseClipboard()

        return nil, errorText, errorCode
    end

    local widePtr =
        ffi.cast(
            "WCHAR *",
            memoryPtr
        )

    local maxLength =
        math.floor(memorySize / 2)

    local wideLength = 0

    while wideLength < maxLength do
        if widePtr[wideLength] == 0 then
            break
        end

        wideLength =
            wideLength + 1
    end

    local text =
        WideToUtf8(
            widePtr,
            wideLength
        )

    kernel32.GlobalUnlock(
        memoryHandle
    )

    local closed = user32.CloseClipboard()

    if text == nil then
        return nil,
            "UTF-16 to UTF-8 conversion failed"
    end

    if closed == 0 then return WinError("CloseClipboard") end
    return text
end

-- ============================================================
-- Write text
-- ============================================================

function clipboard.TextSet(text)
    if text == nil then
        return nil,
            "text cannot be nil"
    end

    text = tostring(text)

    if text:find(
            "\0",
            1,
            true
        ) then
        return nil,
            "text contains NUL character"
    end

    local wideBuf, wideLength =
        Utf8ToWide(text)

    if wideBuf == nil then
        return nil,
            "text is not valid UTF-8"
    end

    local ok, err, code = OpenClipboard()

    if not ok then
        return nil, err, code
    end

    if user32.EmptyClipboard() == 0 then
        local _, errorText, errorCode = WinError(
                "EmptyClipboard failed"
            )

        user32.CloseClipboard()

        return nil, errorText, errorCode
    end

    local byteCount =
        (wideLength + 1)
        * ffi.sizeof("WCHAR")

    local memoryHandle =
        kernel32.GlobalAlloc(
            GMEM_MOVEABLE
            + GMEM_ZEROINIT,
            byteCount
        )

    if memoryHandle == nil
        or memoryHandle == ffi.NULL
    then
        local _, errorText, errorCode = WinError(
                "GlobalAlloc failed"
            )

        user32.CloseClipboard()

        return nil, errorText, errorCode
    end

    local memoryPtr =
        kernel32.GlobalLock(
            memoryHandle
        )

    if memoryPtr == nil
        or memoryPtr == ffi.NULL
    then
        local _, errorText, errorCode = WinError(
                "GlobalLock failed"
            )

        kernel32.GlobalFree(
            memoryHandle
        )

        user32.CloseClipboard()

        return nil, errorText, errorCode
    end

    ffi.copy(
        memoryPtr,
        wideBuf,
        byteCount
    )

    kernel32.GlobalUnlock(
        memoryHandle
    )

    local result =
        user32.SetClipboardData(
            CF_UNICODETEXT,
            memoryHandle
        )

    if result == nil
        or result == ffi.NULL
    then
        local _, errorText, errorCode = WinError(
                "SetClipboardData failed"
            )

        kernel32.GlobalFree(
            memoryHandle
        )

        user32.CloseClipboard()

        return nil, errorText, errorCode
    end

    -- Do NOT GlobalFree(memoryHandle) here.
    -- After successful SetClipboardData(),
    -- Windows owns the memory.

    if user32.CloseClipboard() == 0 then return WinError("CloseClipboard") end
    return true
end

-- ============================================================
-- Clear clipboard
-- ============================================================

function clipboard.Clear()
    local ok, err, code = OpenClipboard()

    if not ok then
        return nil, err, code
    end

    if user32.EmptyClipboard() == 0 then
        local _, errorText, errorCode = WinError(
                "EmptyClipboard failed"
            )

        user32.CloseClipboard()

        return nil, errorText, errorCode
    end

    if user32.CloseClipboard() == 0 then return WinError("CloseClipboard") end
    return true
end

-- ============================================================
-- Clipboard sequence number
-- ============================================================

function clipboard.SequenceNumberGet()
    return tonumber(
        user32.GetClipboardSequenceNumber()
    )
end

do
    local win = require("_win_extension")
    ffi.cdef[[
    typedef struct {
        uint32_t offset;
        int32_t x, y, nonClient, wide;
    } fw_dropfiles;
    unsigned int __stdcall DragQueryFileW(void *, unsigned int, uint16_t *, unsigned int);
    ]]
    local CF_HDROP = 15

    local function checkFileList(handle)
        local size = tonumber(kernel32.GlobalSize(handle))
        if size == 0 then return win.Error("GlobalSize(CF_HDROP)") end
        local headerSize = ffi.sizeof("fw_dropfiles")
        if size < headerSize + 2 then return win.Error("Truncated CF_HDROP", 13) end
        local ptr = kernel32.GlobalLock(handle)
        if ptr == nil then return win.Error("GlobalLock(CF_HDROP)") end
        local header = ffi.cast("const fw_dropfiles *", ptr)
        local offset = header.offset
        local wide = header.wide ~= 0
        local width = wide and 2 or 1
        local ended = false
        if offset >= headerSize and offset % width == 0 and offset + width * 2 <= size then
            local bytes = ffi.cast("const uint8_t *", ptr) + offset
            local path = wide and ffi.cast("const uint16_t *", bytes) or bytes
            local units = math.floor((size - offset) / width)
            for i = 0, units - 2 do
                if path[i] == 0 and path[i + 1] == 0 then
                    ended = true
                    break
                end
            end
        end
        kernel32.GlobalUnlock(handle)
        if not ended then return win.Error("Invalid CF_HDROP layout or terminator", 13) end
        return true
    end

    function clipboard.FilesExists()
        return user32.IsClipboardFormatAvailable(CF_HDROP) ~= 0
    end

    function clipboard.FilesGet()
        local shell, err, code = win.Library("shell32")
        if not shell then return nil, err, code end
        local opened
        opened, err, code = OpenClipboard()
        if not opened then return nil, err, code end
        local handle = user32.GetClipboardData(CF_HDROP)
        if handle == nil then
            code = tonumber(kernel32.GetLastError())
            user32.CloseClipboard()
            return win.Error("GetClipboardData(CF_HDROP)", code == 0 and 13 or code)
        end
        local valid
        valid, err, code = checkFileList(handle)
        if not valid then
            user32.CloseClipboard()
            return nil, err, code
        end
        local paths = {}
        local count = shell.DragQueryFileW(handle, 0xFFFFFFFF, nil, 0)
        for index = 0, count - 1 do
            local length = shell.DragQueryFileW(handle, index, nil, 0)
            local wide = ffi.new("uint16_t[?]", length + 1)
            if length == 0 or shell.DragQueryFileW(handle, index, wide, length + 1) ~= length then
                user32.CloseClipboard()
                return win.Error("Invalid CF_HDROP path", 13)
            end
            local path
            path, err, code = win.FromWide(wide, length)
            if not path then
                user32.CloseClipboard()
                return nil, err, code
            end
            paths[#paths + 1] = path
        end
        if user32.CloseClipboard() == 0 then return win.Error("CloseClipboard") end
        return paths
    end

    function clipboard.FilesSet(paths)
        if type(paths) ~= "table" or #paths == 0 then return win.Error("Expected a nonempty array of paths", 87) end
        local entries, length = {}, 2
        local count = #paths
        for index in pairs(paths) do
            if not win.Integer(index, 1, count) then return win.Error("Expected an array of paths", 87) end
        end
        for index = 1, count do
            local wide, chars, code = win.ToWide(paths[index])
            if not wide then return nil, chars, code end
            if chars == 0 then return win.Error("Empty CF_HDROP path", 87) end
            local bytes = (chars + 1) * 2
            entries[index] = {wide = wide, bytes = bytes}
            length = length + bytes
        end
        local headerSize = ffi.sizeof("fw_dropfiles")
        local memory = kernel32.GlobalAlloc(GMEM_MOVEABLE + GMEM_ZEROINIT, headerSize + length)
        if memory == nil then return win.Error("GlobalAlloc") end
        local ptr = kernel32.GlobalLock(memory)
        if ptr == nil then
            local code = kernel32.GetLastError()
            kernel32.GlobalFree(memory)
            return win.Error("GlobalLock", code)
        end
        local header = ffi.cast("fw_dropfiles *", ptr)
        header.offset, header.wide = headerSize, 1
        local target = ffi.cast("uint8_t *", ptr) + headerSize
        for _, entry in ipairs(entries) do
            ffi.copy(target, entry.wide, entry.bytes)
            target = target + entry.bytes
        end
        kernel32.GlobalUnlock(memory)
        local opened, err, code = OpenClipboard()
        if not opened then
            kernel32.GlobalFree(memory)
            return nil, err, code
        end
        local action
        if user32.EmptyClipboard() == 0 then
            code, action = kernel32.GetLastError(), "EmptyClipboard"
        elseif user32.SetClipboardData(CF_HDROP, memory) == nil then
            code, action = kernel32.GetLastError(), "SetClipboardData(CF_HDROP)"
        end
        if action then
            kernel32.GlobalFree(memory)
            user32.CloseClipboard()
            return win.Error(action, code)
        end
        if user32.CloseClipboard() == 0 then return win.Error("CloseClipboard") end
        return true
    end
end

function clipboard.OnChange(callback)
    return require("_clipboard_watch").Subscribe(callback, clipboard.SequenceNumberGet)
end

require("_clipboard_image")(clipboard, OpenClipboard)
return clipboard
