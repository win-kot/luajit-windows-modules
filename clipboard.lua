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

local function utf8_to_wide(text)
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

local function wide_to_utf8(wideText, wideLength)
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

local function error_message(errorCode)
    errorCode = errorCode
        or tonumber(kernel32.GetLastError())

    local errorBuf = ffi.new(
        "WCHAR[2048]"
    )

    local length = kernel32.FormatMessageW(
        FORMAT_MESSAGE_FROM_SYSTEM
        + FORMAT_MESSAGE_IGNORE_INSERTS,
        nil,
        errorCode,
        0,
        errorBuf,
        2048,
        nil
    )

    if length == 0 then
        return "Win32 error "
            .. tostring(errorCode)
    end

    local text = wide_to_utf8(
        errorBuf,
        tonumber(length)
    )

    if not text then
        return "Win32 error "
            .. tostring(errorCode)
    end

    text = text:gsub(
        "[\r\n]+$",
        ""
    )

    return text
        .. " (Win32 error "
        .. tostring(errorCode)
        .. ")"
end


local function win_error(prefix)
    return prefix
        .. ": "
        .. error_message()
end


-- ============================================================
-- Hidden owner window
-- ============================================================

local function get_owner_window()
    if ownerHwnd ~= nil
        and ownerHwnd ~= ffi.NULL
    then
        return ownerHwnd
    end

    local classWide =
        utf8_to_wide("STATIC")

    local titleWide =
        utf8_to_wide(
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
        return nil,
            win_error(
                "CreateWindowExW failed"
            )
    end

    ownerHwnd = ffi.gc(hwnd, function(h) user32.DestroyWindow(h) end)

    return ownerHwnd
end


-- ============================================================
-- Open clipboard
-- ============================================================

local function open_clipboard()
    local hwnd, err =
        get_owner_window()

    if not hwnd then
        return nil, err
    end

    -- Clipboard can temporarily be opened by
    -- another application.
    for attempt = 1, 50 do
        if user32.OpenClipboard(hwnd) ~= 0 then
            return true
        end

        kernel32.Sleep(10)
    end

    return nil,
        win_error(
            "OpenClipboard failed"
        )
end


-- ============================================================
-- Has Unicode text
-- ============================================================

function clipboard.hasText()
    return user32.IsClipboardFormatAvailable(
        CF_UNICODETEXT
    ) ~= 0
end

-- ============================================================
-- Read text
-- ============================================================

function clipboard.getText()
    if not clipboard.hasText() then
        return nil
    end

    local ok, err =
        open_clipboard()

    if not ok then
        return nil, err
    end

    local memoryHandle =
        user32.GetClipboardData(
            CF_UNICODETEXT
        )

    if memoryHandle == nil
        or memoryHandle == ffi.NULL
    then
        local errorText =
            win_error(
                "GetClipboardData failed"
            )

        user32.CloseClipboard()

        return nil, errorText
    end

    local memorySize =
        tonumber(
            kernel32.GlobalSize(
                memoryHandle
            )
        )

    if memorySize == 0 then
        local err = win_error("GlobalSize failed")
        user32.CloseClipboard()

        return nil, err
    end

    local memoryPtr =
        kernel32.GlobalLock(
            memoryHandle
        )

    if memoryPtr == nil
        or memoryPtr == ffi.NULL
    then
        local errorText =
            win_error(
                "GlobalLock failed"
            )

        user32.CloseClipboard()

        return nil, errorText
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
        wide_to_utf8(
            widePtr,
            wideLength
        )

    kernel32.GlobalUnlock(
        memoryHandle
    )

    user32.CloseClipboard()

    if text == nil then
        return nil,
            "UTF-16 to UTF-8 conversion failed"
    end

    return text
end

-- ============================================================
-- Write text
-- ============================================================

function clipboard.setText(text)
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
        utf8_to_wide(text)

    if wideBuf == nil then
        return nil,
            "text is not valid UTF-8"
    end

    local ok, err =
        open_clipboard()

    if not ok then
        return nil, err
    end

    if user32.EmptyClipboard() == 0 then
        local errorText =
            win_error(
                "EmptyClipboard failed"
            )

        user32.CloseClipboard()

        return nil, errorText
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
        local errorText =
            win_error(
                "GlobalAlloc failed"
            )

        user32.CloseClipboard()

        return nil, errorText
    end

    local memoryPtr =
        kernel32.GlobalLock(
            memoryHandle
        )

    if memoryPtr == nil
        or memoryPtr == ffi.NULL
    then
        local errorText =
            win_error(
                "GlobalLock failed"
            )

        kernel32.GlobalFree(
            memoryHandle
        )

        user32.CloseClipboard()

        return nil, errorText
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
        local errorText =
            win_error(
                "SetClipboardData failed"
            )

        kernel32.GlobalFree(
            memoryHandle
        )

        user32.CloseClipboard()

        return nil, errorText
    end

    -- Do NOT GlobalFree(memoryHandle) here.
    -- After successful SetClipboardData(),
    -- Windows owns the memory.

    user32.CloseClipboard()

    return true
end

-- ============================================================
-- Clear clipboard
-- ============================================================

function clipboard.clear()
    local ok, err =
        open_clipboard()

    if not ok then
        return nil, err
    end

    if user32.EmptyClipboard() == 0 then
        local errorText =
            win_error(
                "EmptyClipboard failed"
            )

        user32.CloseClipboard()

        return nil, errorText
    end

    user32.CloseClipboard()

    return true
end

-- ============================================================
-- Clipboard sequence number
-- ============================================================

function clipboard.getSequenceNumber()
    return tonumber(
        user32.GetClipboardSequenceNumber()
    )
end

return clipboard
