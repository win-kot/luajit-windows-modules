local ffi = require("ffi")
local bit = require("bit")

ffi.cdef [[
int __stdcall MultiByteToWideChar(
    uint32_t CodePage,
    uint32_t dwFlags,
    const char *lpMultiByteStr,
    int cbMultiByte,
    uint16_t *lpWideCharStr,
    int cchWideChar
);

int __stdcall WideCharToMultiByte(
    uint32_t CodePage,
    uint32_t dwFlags,
    const uint16_t *lpWideCharStr,
    int cchWideChar,
    char *lpMultiByteStr,
    int cbMultiByte,
    const char *lpDefaultChar,
    int32_t *lpUsedDefaultChar
);

uint32_t __stdcall GetLastError(void);
void __stdcall SetLastError(uint32_t);

uint32_t __stdcall FormatMessageW(
    uint32_t dwFlags,
    const void *lpSource,
    uint32_t dwMessageId,
    uint32_t dwLanguageId,
    uint16_t *lpBuffer,
    uint32_t nSize,
    void *Arguments
);

void __stdcall Sleep(
    uint32_t dwMilliseconds
);

uint64_t __stdcall GetTickCount64(void);

int __stdcall CompareStringOrdinal(
    const uint16_t *lpString1,
    int cchCount1,
    const uint16_t *lpString2,
    int cchCount2,
    int bIgnoreCase
);

int __stdcall EnumWindows(
    int (__stdcall *lpEnumFunc)(void *hWnd, intptr_t lParam),
    intptr_t lParam
);

int __stdcall IsWindow(
    void *hWnd
);

int __stdcall IsWindowVisible(
    void *hWnd
);

int __stdcall IsWindowEnabled(
    void *hWnd
);

int __stdcall IsIconic(
    void *hWnd
);

int __stdcall IsZoomed(
    void *hWnd
);

int __stdcall GetWindowTextLengthW(
    void *hWnd
);

int __stdcall GetWindowTextW(
    void *hWnd,
    uint16_t *lpString,
    int nMaxCount
);

int __stdcall SetWindowTextW(
    void *hWnd,
    const uint16_t *lpString
);

int __stdcall GetClassNameW(
    void *hWnd,
    uint16_t *lpClassName,
    int nMaxCount
);

uint32_t __stdcall GetWindowThreadProcessId(
    void *hWnd,
    uint32_t *lpdwProcessId
);

int __stdcall fw_window_GetWindowRect(
    void *hWnd,
    int32_t *lpRect
) __asm__("GetWindowRect");

int __stdcall MoveWindow(
    void *hWnd,
    int X,
    int Y,
    int nWidth,
    int nHeight,
    int bRepaint
);

int __stdcall ShowWindow(
    void *hWnd,
    int nCmdShow
);

int __stdcall SetForegroundWindow(
    void *hWnd
);

int __stdcall BringWindowToTop(
    void *hWnd
);

int __stdcall EnableWindow(
    void *hWnd,
    int bEnable
);

int __stdcall PostMessageW(
    void *hWnd,
    uint32_t Msg,
    uintptr_t wParam,
    intptr_t lParam
);

void * __stdcall GetForegroundWindow(void);

intptr_t __stdcall GetWindowLongPtrW(
    void *hWnd,
    int nIndex
);

int __stdcall SetWindowPos(
    void *hWnd,
    void *hWndInsertAfter,
    int X,
    int Y,
    int cx,
    int cy,
    uint32_t uFlags
);
]]

local kernel32 = ffi.load("kernel32")
local user32 = ffi.load("user32")

local window = {}

local CP_UTF8 = 65001
local MB_ERR_INVALID_CHARS = 0x00000008

local FORMAT_MESSAGE_IGNORE_INSERTS = 0x00000200
local FORMAT_MESSAGE_FROM_SYSTEM = 0x00001000

local CSTR_EQUAL = 2

local SW_HIDE = 0
local SW_SHOWMAXIMIZED = 3
local SW_SHOW = 5
local SW_MINIMIZE = 6
local SW_RESTORE = 9

local WM_CLOSE = 0x0010

local GWL_STYLE = -16
local GWL_EXSTYLE = -20
local WS_EX_TOPMOST = 0x00000008

local SWP_NOSIZE = 0x0001
local SWP_NOMOVE = 0x0002
local SWP_NOACTIVATE = 0x0010
local SWP_TOPMOST_FLAGS = SWP_NOSIZE + SWP_NOMOVE + SWP_NOACTIVATE

local HWND_TOPMOST = ffi.cast("void *", -1)
local HWND_NOTOPMOST = ffi.cast("void *", -2)


-- ============================================================
-- UTF-8 -> UTF-16
-- ============================================================

local function Utf8ToWide(text)
    if text == nil then
        return nil, 0
    end

    text = tostring(text)

    if text:find("\0", 1, true) then
        return nil, nil
    end

    if text == "" then
        local wideBuf = ffi.new("uint16_t[1]")
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
        "uint16_t[?]",
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

local function WideToUtf8(
    widePtr,
    wideLength
)
    if widePtr == nil
        or wideLength == 0
    then
        return ""
    end

    local utf8Length = kernel32.WideCharToMultiByte(
        CP_UTF8,
        0,
        widePtr,
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
        widePtr,
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
-- Win32 errors
-- ============================================================

local function ErrorMessage(errorCode)
    errorCode = errorCode
        or tonumber(
            kernel32.GetLastError()
        )

    local errorBuf = ffi.new(
        "uint16_t[2048]"
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

    local text = WideToUtf8(
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


local function WinError(prefix)
    return prefix
        .. ": "
        .. ErrorMessage()
end


-- ============================================================
-- HWND validation
-- ============================================================

local function CheckHwnd(hwnd)
    if hwnd == nil
        or hwnd == ffi.NULL
    then
        return nil,
            "invalid HWND"
    end

    if user32.IsWindow(hwnd) == 0 then
        return nil,
            "window no longer exists"
    end

    return true
end


-- ============================================================
-- HWND conversion
-- ============================================================

function window.HwndToNumber(hwnd)
    if hwnd == nil
        or hwnd == ffi.NULL
    then
        return nil
    end

    local kind = type(hwnd)
    if kind ~= "number" and kind ~= "cdata" then return nil, "invalid HWND type" end
    if kind == "number" and (hwnd < 0 or hwnd > 9007199254740991 or hwnd % 1 ~= 0) then
        return nil, "invalid HWND value"
    end
    local ok, value = pcall(ffi.cast, "uintptr_t", hwnd)
    if not ok then return nil, "invalid HWND value" end
    if value > 9007199254740991ULL then return nil, "HWND is outside the exact numeric range" end
    return tonumber(value)
end

function window.NumberToHwnd(value)
    local numberValue = tonumber(value)

    if numberValue == nil
        or numberValue <= 0
        or numberValue > 9007199254740991
        or numberValue ~= math.floor(numberValue)
    then
        return nil
    end

    return ffi.cast(
        "void *",
        ffi.cast(
            "uintptr_t",
            numberValue
        )
    )
end

-- ============================================================
-- Window title
-- ============================================================

local function GetTitleInternal(hwnd, wideOnly)
    kernel32.SetLastError(0)
    local length = user32.GetWindowTextLengthW(hwnd)
    if length == 0 and kernel32.GetLastError() ~= 0 then
        return nil, nil, 0, WinError("GetWindowTextLengthW failed")
    end
    local titleBuf = ffi.new("uint16_t[?]", length + 1)
    kernel32.SetLastError(0)
    local copied = user32.GetWindowTextW(hwnd, titleBuf, length + 1)
    if copied == 0 and kernel32.GetLastError() ~= 0 then
        return nil, nil, 0, WinError("GetWindowTextW failed")
    end
    -- Window searches compare UTF-16 directly and do not need a UTF-8 copy.
    if wideOnly then return nil, titleBuf, copied end
    local text = WideToUtf8(titleBuf, copied)
    if text == nil then return nil, nil, 0, WinError("UTF-16 conversion failed") end
    return text, titleBuf, copied
end

function window.TitleGet(hwnd)
    local ok, err = CheckHwnd(hwnd)
    if not ok then return nil, err end
    local title, _, _, titleErr = GetTitleInternal(hwnd)
    return title, titleErr
end

-- ============================================================
-- Unicode case-insensitive substring
-- ============================================================

local function WideContains(
    textWide,
    textLength,
    findWide,
    findLength
)
    if findLength == 0 then
        return true
    end

    if textLength < findLength then
        return false
    end

    local lastIndex =
        textLength - findLength

    for index = 0, lastIndex do
        local compareResult =
            kernel32.CompareStringOrdinal(
                textWide + index,
                findLength,
                findWide,
                findLength,
                1
            )

        if compareResult == CSTR_EQUAL then
            return true
        end
    end

    return false
end


-- ============================================================
-- Find first top-level window
--
-- includeHidden:
-- false/nil = visible windows only
-- true      = visible and hidden windows
-- ============================================================

function window.Find(
    titlePart,
    includeHidden
)
    if titlePart == nil then
        return nil,
            "title cannot be nil"
    end

    titlePart = tostring(titlePart)

    local findWide,
    findLength =
        Utf8ToWide(
            titlePart
        )

    if findWide == nil then
        return nil,
            "title is not valid UTF-8"
    end

    local foundHwnd = nil

    local Callback

    Callback = ffi.cast(
        "int (__stdcall *)(void *, intptr_t)",
        function(hwnd, param)
            if not includeHidden
                and user32.IsWindowVisible(hwnd) == 0
            then
                return 1
            end

            local title,
            titleWide,
            titleLength =
            GetTitleInternal(hwnd, true)

            if titleWide ~= nil
                and WideContains(
                    titleWide,
                    titleLength,
                    findWide,
                    findLength
                )
            then
                foundHwnd = hwnd

                return 0
            end

            return 1
        end
    )

    kernel32.SetLastError(0)
    local enumerated = user32.EnumWindows(Callback, 0)
    local enumError = tonumber(kernel32.GetLastError())
    Callback:free()
    if enumerated == 0 and enumError ~= 0 then
        return nil, "EnumWindows failed: " .. ErrorMessage(enumError)
    end

    if foundHwnd == nil then
        return nil
    end

    return foundHwnd
end

-- ============================================================
-- Find all matching top-level windows
-- ============================================================

function window.FindAll(
    titlePart,
    includeHidden
)
    if titlePart == nil then
        return nil,
            "title cannot be nil"
    end

    local findWide,
    findLength =
        Utf8ToWide(
            tostring(titlePart)
        )

    if findWide == nil then
        return nil,
            "title is not valid UTF-8"
    end

    local result = {}

    local Callback

    Callback = ffi.cast(
        "int (__stdcall *)(void *, intptr_t)",
        function(hwnd, param)
            if not includeHidden
                and user32.IsWindowVisible(hwnd) == 0
            then
                return 1
            end

            local title,
            titleWide,
            titleLength =
            GetTitleInternal(hwnd, true)

            if titleWide ~= nil
                and WideContains(
                    titleWide,
                    titleLength,
                    findWide,
                    findLength
                )
            then
                result[#result + 1] = hwnd
            end

            return 1
        end
    )

    kernel32.SetLastError(0)
    local enumerated = user32.EnumWindows(Callback, 0)
    local enumError = tonumber(kernel32.GetLastError())
    Callback:free()
    if enumerated == 0 and enumError ~= 0 then
        return nil, "EnumWindows failed: " .. ErrorMessage(enumError)
    end

    return result
end

-- ============================================================
-- Exists
-- ============================================================

function window.Exists(hwnd)
    if hwnd == nil
        or hwnd == ffi.NULL
    then
        return false
    end

    return user32.IsWindow(hwnd) ~= 0
end

-- ============================================================
-- Visible
-- ============================================================

function window.IsVisible(hwnd)
    local ok, err = CheckHwnd(hwnd)

    if not ok then
        return false
    end

    return user32.IsWindowVisible(hwnd) ~= 0
end

-- ============================================================
-- Enabled
-- ============================================================

function window.IsEnabled(hwnd)
    local ok, err = CheckHwnd(hwnd)

    if not ok then
        return false
    end

    return user32.IsWindowEnabled(hwnd) ~= 0
end

-- ============================================================
-- Minimized
-- ============================================================

function window.IsMinimized(hwnd)
    local ok, err = CheckHwnd(hwnd)

    if not ok then
        return false
    end

    return user32.IsIconic(hwnd) ~= 0
end

-- ============================================================
-- Maximized
-- ============================================================

function window.IsMaximized(hwnd)
    local ok, err = CheckHwnd(hwnd)

    if not ok then
        return false
    end

    return user32.IsZoomed(hwnd) ~= 0
end

-- ============================================================
-- Class name
-- ============================================================

function window.ClassGet(hwnd)
    local ok, err = CheckHwnd(hwnd)

    if not ok then
        return nil, err
    end

    local classBuf = ffi.new(
        "uint16_t[512]"
    )

    local length = user32.GetClassNameW(
        hwnd,
        classBuf,
        512
    )

    if length == 0 then
        return nil,
            WinError(
                "GetClassNameW failed"
            )
    end

    return WideToUtf8(
        classBuf,
        length
    )
end

-- ============================================================
-- PID / Thread ID
-- ============================================================

function window.PidGet(hwnd)
    local ok, err = CheckHwnd(hwnd)

    if not ok then
        return nil, err
    end

    local pidBuf = ffi.new(
        "uint32_t[1]"
    )

    local threadId =
        user32.GetWindowThreadProcessId(
            hwnd,
            pidBuf
        )

    if threadId == 0 then
        return nil,
            WinError(
                "GetWindowThreadProcessId failed"
            )
    end

    return tonumber(pidBuf[0]),
        tonumber(threadId)
end

-- ============================================================
-- Position and size
-- ============================================================

function window.RectGet(hwnd)
    local ok, err = CheckHwnd(hwnd)

    if not ok then
        return nil, err
    end

    local rectBuf = ffi.new(
        "int32_t[4]"
    )

    if user32.fw_window_GetWindowRect(
            hwnd,
            rectBuf
        ) == 0 then
        return nil,
            WinError(
                "GetWindowRect failed"
            )
    end

    local left =
        tonumber(rectBuf[0])

    local top =
        tonumber(rectBuf[1])

    local right =
        tonumber(rectBuf[2])

    local bottom =
        tonumber(rectBuf[3])

    return {
        x = left,
        y = top,

        width =
            right - left,

        height =
            bottom - top,

        left = left,
        top = top,
        right = right,
        bottom = bottom
    }
end

-- ============================================================
-- Move and resize
-- ============================================================

function window.Move(
    hwnd,
    x,
    y,
    width,
    height,
    repaint
)
    local ok, err = CheckHwnd(hwnd)

    if not ok then
        return nil, err
    end

    x = tonumber(x)
    y = tonumber(y)
    width = tonumber(width)
    height = tonumber(height)

    if x == nil
        or y == nil
        or width == nil
        or height == nil
    then
        return nil,
            "invalid window coordinates"
    end

    if repaint == nil then
        repaint = true
    end

    local result = user32.MoveWindow(
        hwnd,
        math.floor(x),
        math.floor(y),
        math.floor(width),
        math.floor(height),
        repaint and 1 or 0
    )

    if result == 0 then
        return nil,
            WinError(
                "MoveWindow failed"
            )
    end

    return true
end

-- ============================================================
-- Move only
-- ============================================================

function window.MoveTo(
    hwnd,
    x,
    y
)
    local rect, err =
        window.RectGet(hwnd)

    if not rect then
        return nil, err
    end

    return window.Move(
        hwnd,
        x,
        y,
        rect.width,
        rect.height
    )
end

-- ============================================================
-- Resize only
-- ============================================================

function window.Resize(
    hwnd,
    width,
    height
)
    local rect, err =
        window.RectGet(hwnd)

    if not rect then
        return nil, err
    end

    return window.Move(
        hwnd,
        rect.x,
        rect.y,
        width,
        height
    )
end

-- ============================================================
-- Show
-- ============================================================

function window.Show(hwnd)
    local ok, err = CheckHwnd(hwnd)

    if not ok then
        return nil, err
    end

    user32.ShowWindow(
        hwnd,
        SW_SHOW
    )

    return true
end

-- ============================================================
-- Hide
-- ============================================================

function window.Hide(hwnd)
    local ok, err = CheckHwnd(hwnd)

    if not ok then
        return nil, err
    end

    user32.ShowWindow(
        hwnd,
        SW_HIDE
    )

    return true
end

-- ============================================================
-- Minimize
-- ============================================================

function window.Minimize(hwnd)
    local ok, err = CheckHwnd(hwnd)

    if not ok then
        return nil, err
    end

    user32.ShowWindow(
        hwnd,
        SW_MINIMIZE
    )

    return true
end

-- ============================================================
-- Maximize
-- ============================================================

function window.Maximize(hwnd)
    local ok, err = CheckHwnd(hwnd)

    if not ok then
        return nil, err
    end

    user32.ShowWindow(
        hwnd,
        SW_SHOWMAXIMIZED
    )

    return true
end

-- ============================================================
-- Restore
-- ============================================================

function window.Restore(hwnd)
    local ok, err = CheckHwnd(hwnd)

    if not ok then
        return nil, err
    end

    user32.ShowWindow(
        hwnd,
        SW_RESTORE
    )

    return true
end

-- ============================================================
-- Activate
-- ============================================================

function window.Activate(hwnd)
    local ok, err = CheckHwnd(hwnd)

    if not ok then
        return nil, err
    end

    if user32.IsIconic(hwnd) ~= 0 then
        user32.ShowWindow(
            hwnd,
            SW_RESTORE
        )
    end

    user32.BringWindowToTop(
        hwnd
    )

    local result =
        user32.SetForegroundWindow(
            hwnd
        )

    if result == 0 then
        return false,
            "Windows did not allow the window to become foreground"
    end

    return true
end

-- ============================================================
-- Enable / Disable
-- ============================================================

function window.Enable(
    hwnd,
    enabled
)
    local ok, err = CheckHwnd(hwnd)

    if not ok then
        return nil, err
    end

    if enabled == nil then
        enabled = true
    end

    user32.EnableWindow(
        hwnd,
        enabled and 1 or 0
    )

    return true
end

function window.Disable(hwnd)
    return window.Enable(
        hwnd,
        false
    )
end

-- ============================================================
-- Set title
-- ============================================================

function window.TitleSet(
    hwnd,
    text
)
    local ok, err = CheckHwnd(hwnd)

    if not ok then
        return nil, err
    end

    local textWide =
        Utf8ToWide(
            tostring(text or "")
        )

    if textWide == nil then
        return nil,
            "text is not valid UTF-8"
    end

    if user32.SetWindowTextW(
            hwnd,
            textWide
        ) == 0 then
        return nil,
            WinError(
                "SetWindowTextW failed"
            )
    end

    return true
end

-- ============================================================
-- Close
-- ============================================================

function window.Close(hwnd)
    local ok, err = CheckHwnd(hwnd)

    if not ok then
        return nil, err
    end

    if user32.PostMessageW(
            hwnd,
            WM_CLOSE,
            0,
            0
        ) == 0 then
        return nil,
            WinError(
                "PostMessageW(WM_CLOSE) failed"
            )
    end

    return true
end

-- ============================================================
-- Wait for window
-- ============================================================

function window.Wait(
    titlePart,
    timeout,
    includeHidden
)
    if timeout ~= nil then
        timeout = tonumber(timeout)

        if timeout == nil
            or timeout ~= timeout or timeout == math.huge
            or timeout < 0
        then
            return nil,
                "invalid timeout"
        end
    end

    local startTime =
        tonumber(
            kernel32.GetTickCount64()
        )

    while true do
        local hwnd, err =
            window.Find(
                titlePart,
                includeHidden
            )

        if err then return nil, err end
        if hwnd ~= nil then
            return hwnd
        end

        if timeout ~= nil then
            local elapsed =
                tonumber(
                    kernel32.GetTickCount64()
                )
                - startTime

            if elapsed >= timeout then
                return nil,
                    "timeout"
            end
        end

        kernel32.Sleep(50)
    end
end

-- ============================================================
-- Wait until HWND is destroyed
-- ============================================================

function window.WaitClose(
    hwnd,
    timeout
)
    if hwnd == nil
        or hwnd == ffi.NULL
    then
        return true
    end

    if timeout ~= nil then
        timeout = tonumber(timeout)

        if timeout == nil
            or timeout ~= timeout or timeout == math.huge
            or timeout < 0
        then
            return nil,
                "invalid timeout"
        end
    end

    local startTime =
        tonumber(
            kernel32.GetTickCount64()
        )

    while true do
        if user32.IsWindow(hwnd) == 0 then
            return true
        end

        if timeout ~= nil then
            local elapsed =
                tonumber(
                    kernel32.GetTickCount64()
                )
                - startTime

            if elapsed >= timeout then
                return false,
                    "timeout"
            end
        end

        kernel32.Sleep(50)
    end
end

-- ============================================================
-- AHK v2-like window automation layer
--
-- This layer is intentionally additive. The original API above
-- keeps exactly the same names, arguments and behavior.
--
-- New Win... functions accept:
--   * HWND cdata
--   * numeric HWND
--   * partial window title
--   * "A" for the current foreground window
--
-- For the new WinWait... functions timeout is in seconds.
-- ============================================================

local function AhkTimeoutToMs(timeoutSeconds)
    if timeoutSeconds == nil then
        return nil
    end

    timeoutSeconds = tonumber(timeoutSeconds)

    if timeoutSeconds == nil
        or timeoutSeconds ~= timeoutSeconds
        or timeoutSeconds == math.huge
        or timeoutSeconds < 0
    then
        return nil, "invalid timeout"
    end

    return timeoutSeconds * 1000
end

local function AhkActiveHwnd()
    local hwnd = user32.GetForegroundWindow()

    if hwnd == nil
        or hwnd == ffi.NULL
        or user32.IsWindow(hwnd) == 0
    then
        return nil
    end

    return hwnd
end

local function AhkNormalizeHwnd(value)
    if type(value) == "cdata" then
        if user32.IsWindow(value) ~= 0 then
            return value
        end

        return nil
    end

    if type(value) == "number" then
        local hwnd = window.NumberToHwnd(value)

        if hwnd ~= nil
            and user32.IsWindow(hwnd) ~= 0
        then
            return hwnd
        end

        return nil
    end

    return nil
end

local function AhkResolveTarget(
    target,
    includeHidden
)
    local hwnd = AhkNormalizeHwnd(target)

    if hwnd ~= nil then
        return hwnd
    end

    if type(target) == "cdata"
        or type(target) == "number"
    then
        return nil
    end

    if type(target) ~= "string" then
        return nil,
            "window target must be HWND, numeric HWND, or title string"
    end

    if target == "A" then
        return AhkActiveHwnd()
    end

    return window.Find(
        target,
        includeHidden == true
    )
end

local function AhkResolveRequired(
    target,
    includeHidden
)
    local hwnd, err = AhkResolveTarget(
        target,
        includeHidden
    )

    if hwnd ~= nil then
        return hwnd
    end

    if err ~= nil then
        return nil, err
    end

    return nil,
        "window not found"
end

local function AhkSameHwnd(
    firstHwnd,
    secondHwnd
)
    if firstHwnd == nil
        or secondHwnd == nil
    then
        return false
    end

    return ffi.cast(
        "uintptr_t",
        firstHwnd
    ) == ffi.cast(
        "uintptr_t",
        secondHwnd
    )
end

local function AhkWaitUntil(
    CheckFunction,
    timeoutSeconds
)
    local timeoutMs, timeoutErr =
        AhkTimeoutToMs(
            timeoutSeconds
        )

    if timeoutErr ~= nil then
        return nil, timeoutErr
    end

    local startTime =
        tonumber(
            kernel32.GetTickCount64()
        )

    while true do
        local result, err =
            CheckFunction()

        if err ~= nil then
            return nil, err
        end

        if result then
            return result
        end

        if timeoutMs ~= nil then
            local elapsed =
                tonumber(
                    kernel32.GetTickCount64()
                )
                - startTime

            if elapsed >= timeoutMs then
                return nil
            end
        end

        kernel32.Sleep(50)
    end
end

local function AhkNormalizeOnOff(
    value,
    currentState
)
    if value == true
        or value == 1
        or value == "On"
        or value == "on"
    then
        return true
    end

    if value == false
        or value == 0
        or value == "Off"
        or value == "off"
    then
        return false
    end

    if value == -1
        or value == "Toggle"
        or value == "toggle"
    then
        return not currentState
    end

    return nil,
        "value must be true/false, 1/0, On/Off, or Toggle"
end

local function AhkGetWindowLongPtr(
    hwnd,
    index
)
    kernel32.SetLastError(0)

    local value =
        user32.GetWindowLongPtrW(
            hwnd,
            index
        )

    local errorCode =
        tonumber(
            kernel32.GetLastError()
        )

    if value == 0
        and errorCode ~= 0
    then
        return nil,
            "GetWindowLongPtrW failed: "
            .. ErrorMessage(errorCode)
    end

    return tonumber(value)
end

-- ============================================================
-- Search / wait
-- ============================================================

function window.WinExist(
    target,
    includeHidden
)
    return AhkResolveTarget(
        target,
        includeHidden
    )
end

function window.WinGetID(
    target,
    includeHidden
)
    return window.WinExist(
        target,
        includeHidden
    )
end

function window.WinWait(
    target,
    timeoutSeconds,
    includeHidden
)
    return AhkWaitUntil(
        function()
            return AhkResolveTarget(
                target,
                includeHidden
            )
        end,
        timeoutSeconds
    )
end

function window.WinWaitClose(
    target,
    timeoutSeconds,
    includeHidden
)
    local hwnd, err =
        AhkResolveTarget(
            target,
            includeHidden
        )

    if err ~= nil then
        return nil, err
    end

    if hwnd == nil then
        return true
    end

    local result, waitErr =
        AhkWaitUntil(
            function()
                if user32.IsWindow(hwnd) == 0 then
                    return true
                end

                return nil
            end,
            timeoutSeconds
        )

    if result then
        return true
    end

    if waitErr ~= nil then
        return nil, waitErr
    end

    return false,
        "timeout"
end

function window.WinActive(
    target,
    includeHidden
)
    local activeHwnd =
        AhkActiveHwnd()

    if activeHwnd == nil then
        return nil
    end

    if target == nil
        or target == "A"
    then
        return activeHwnd
    end

    local directHwnd =
        AhkNormalizeHwnd(target)

    if directHwnd ~= nil then
        if AhkSameHwnd(
            activeHwnd,
            directHwnd
        ) then
            return activeHwnd
        end

        return nil
    end

    if type(target) ~= "string" then
        return nil,
            "window target must be HWND, numeric HWND, or title string"
    end

    local matches, err =
        window.FindAll(
            target,
            includeHidden == true
        )

    if matches == nil then
        return nil, err
    end

    for index = 1, #matches do
        if AhkSameHwnd(
            activeHwnd,
            matches[index]
        ) then
            return activeHwnd
        end
    end

    return nil
end

function window.WinWaitActive(
    target,
    timeoutSeconds,
    includeHidden
)
    return AhkWaitUntil(
        function()
            return window.WinActive(
                target,
                includeHidden
            )
        end,
        timeoutSeconds
    )
end

function window.WinWaitNotActive(
    target,
    timeoutSeconds,
    includeHidden
)
    local result, err =
        AhkWaitUntil(
            function()
                local activeHwnd,
                activeErr =
                    window.WinActive(
                        target,
                        includeHidden
                    )

                if activeErr ~= nil then
                    return nil,
                        activeErr
                end

                if activeHwnd == nil then
                    return true
                end

                return nil
            end,
            timeoutSeconds
        )

    if result then
        return true
    end

    if err ~= nil then
        return nil, err
    end

    return false,
        "timeout"
end

-- ============================================================
-- Actions
-- ============================================================

function window.WinActivate(
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.Activate(hwnd)
end

function window.WinClose(
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.Close(hwnd)
end

function window.WinShow(
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.Show(hwnd)
end

function window.WinHide(
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.Hide(hwnd)
end

function window.WinMinimize(
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.Minimize(hwnd)
end

function window.WinMaximize(
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.Maximize(hwnd)
end

function window.WinRestore(
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.Restore(hwnd)
end

-- ============================================================
-- Information
-- ============================================================

function window.WinGetTitle(
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.TitleGet(hwnd)
end

function window.WinGetClass(
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.ClassGet(hwnd)
end

function window.WinGetPID(
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    local pid, threadId =
        window.PidGet(hwnd)

    if pid == nil then
        return nil, threadId
    end

    return pid
end

function window.WinGetPos(
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    local rect, rectErr =
        window.RectGet(hwnd)

    if rect == nil then
        return nil, rectErr
    end

    return rect.x,
        rect.y,
        rect.width,
        rect.height
end

function window.WinGetMinMax(
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    if window.IsMinimized(hwnd) then
        return -1
    end

    if window.IsMaximized(hwnd) then
        return 1
    end

    return 0
end

function window.WinGetCount(
    title,
    includeHidden
)
    if type(title) ~= "string" then
        return nil,
            "title must be a string"
    end

    local matches, err =
        window.FindAll(
            title,
            includeHidden == true
        )

    if matches == nil then
        return nil, err
    end

    return #matches
end

function window.WinGetList(
    title,
    includeHidden
)
    if type(title) ~= "string" then
        return nil,
            "title must be a string"
    end

    return window.FindAll(
        title,
        includeHidden == true
    )
end

function window.WinGetStyle(
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return AhkGetWindowLongPtr(
        hwnd,
        GWL_STYLE
    )
end

function window.WinGetExStyle(
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return AhkGetWindowLongPtr(
        hwnd,
        GWL_EXSTYLE
    )
end

-- ============================================================
-- Changes
-- ============================================================

function window.WinMove(
    x,
    y,
    width,
    height,
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    local rect, rectErr =
        window.RectGet(hwnd)

    if rect == nil then
        return nil, rectErr
    end

    if x == nil then x = rect.x end
    if y == nil then y = rect.y end
    if width == nil then width = rect.width end
    if height == nil then height = rect.height end

    return window.Move(
        hwnd,
        x,
        y,
        width,
        height
    )
end

function window.WinSetTitle(
    newTitle,
    target,
    includeHidden
)
    if type(newTitle) ~= "string" then
        return nil,
            "newTitle must be a string"
    end

    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.TitleSet(
        hwnd,
        newTitle
    )
end

function window.WinSetEnabled(
    value,
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    local currentState =
        window.IsEnabled(hwnd)

    local enabled, valueErr =
        AhkNormalizeOnOff(
            value,
            currentState
        )

    if enabled == nil then
        return nil, valueErr
    end

    return window.Enable(
        hwnd,
        enabled
    )
end

function window.WinIsAlwaysOnTop(
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    local exStyle, styleErr =
        AhkGetWindowLongPtr(
            hwnd,
            GWL_EXSTYLE
        )

    if exStyle == nil then
        return nil, styleErr
    end

    return bit.band(
        exStyle,
        WS_EX_TOPMOST
    ) ~= 0
end

function window.WinSetAlwaysOnTop(
    value,
    target,
    includeHidden
)
    local hwnd, err =
        AhkResolveRequired(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    local currentState, stateErr =
        window.WinIsAlwaysOnTop(hwnd)

    if currentState == nil then
        return nil, stateErr
    end

    local enabled, valueErr =
        AhkNormalizeOnOff(
            value,
            currentState
        )

    if enabled == nil then
        return nil, valueErr
    end

    local insertAfter =
        HWND_NOTOPMOST

    if enabled then
        insertAfter =
            HWND_TOPMOST
    end

    if user32.SetWindowPos(
            hwnd,
            insertAfter,
            0,
            0,
            0,
            0,
            SWP_TOPMOST_FLAGS
        ) == 0
    then
        return nil,
            WinError(
                "SetWindowPos failed"
            )
    end

    return true
end

-- WinAPI window calls can synchronously re-enter Lua WNDPROC callbacks.
jit.off(GetTitleInternal, true)
for _, fn in pairs(window) do
    if type(fn) == "function" then jit.off(fn, true) end
end
do
    local win = require("_win_extension")
    ffi.cdef[[
    intptr_t __stdcall SendMessageTimeoutW(void *, uint32_t, uintptr_t, intptr_t,
        uint32_t, uint32_t, uintptr_t *);
    ]]
    local function checkedHwnd(hwnd)
        if type(hwnd) == "number" and win.Integer(hwnd, 1, 9007199254740991) then
            hwnd = ffi.cast("void *", hwnd)
        end
        if type(hwnd) ~= "cdata" or not ffi.istype("void *", hwnd) or not CheckHwnd(hwnd) then
            return win.Error("Invalid HWND", 1400)
        end
        return hwnd
    end

    local function target(hwnd, msg, wParam, lParam)
        local handle, err, code = checkedHwnd(hwnd)
        if not handle then return nil, err, code end
        if not win.Integer(msg, 0, 0xFFFF) or
           (wParam ~= nil and not win.Integer(wParam, -9007199254740991, 9007199254740991)) or
           (lParam ~= nil and not win.Integer(lParam, -9007199254740991, 9007199254740991)) then
            return win.Error("Expected numeric message and integer parameters", 87)
        end
        return handle
    end

    function window.MessagePost(hwnd, msg, wParam, lParam)
        local handle, err, code = target(hwnd, msg, wParam, lParam)
        if not handle then return nil, err, code end
        if user32.PostMessageW(handle, msg, wParam or 0, lParam or 0) == 0 then
            return win.Error("PostMessageW")
        end
        return true
    end

    local function sendTimeout(handle, msg, wParam, lParam, timeout)
        local code
        local result = ffi.new("uintptr_t[1]")
        kernel32.SetLastError(0)
        if user32.SendMessageTimeoutW(handle, msg, wParam or 0, lParam or 0, 0x23, timeout, result) == 0 then
            code = tonumber(kernel32.GetLastError())
            if code == 1460 then return false end
            return win.Error("SendMessageTimeoutW", code == 0 and 31 or code)
        end
        return win.Exact(ffi.cast("intptr_t", result[0]))
    end
    jit.off(sendTimeout, true)

    function window.MessageSend(hwnd, msg, wParam, lParam, timeoutMs)
        local handle, err, code = target(hwnd, msg, wParam, lParam)
        if not handle then return nil, err, code end
        local timeout
        timeout, err, code = win.Timeout(timeoutMs, 1000)
        if not timeout then return nil, err, code end
        return sendTimeout(handle, msg, wParam, lParam, timeout)
    end

    ffi.cdef[[
    typedef struct {
        uintptr_t dataId;
        uint32_t size;
        const void *data;
        uint8_t bytes[?];
    } fw_window_copydata;
    ]]

    local function ownerPid(handle)
        local pid = ffi.new("uint32_t[1]")
        if user32.GetWindowThreadProcessId(handle, pid) == 0 then
            return win.Error("GetWindowThreadProcessId")
        end
        return tonumber(pid[0])
    end

    function window.CopyDataSend(hwnd, bytes, dataId, timeoutMs, senderHwnd)
        local handle, err, code = checkedHwnd(hwnd)
        if not handle then return nil, err, code end
        if type(bytes) ~= "string" or #bytes > 4 * 1024 * 1024 then
            return win.Error("Expected a binary string of up to 4 MiB", 87)
        end
        if dataId ~= nil and not win.Integer(dataId, 0, 0xFFFFFFFF) then
            return win.Error("dataId must be a DWORD", 87)
        end
        local timeout
        timeout, err, code = win.Timeout(timeoutMs, 1000)
        if not timeout then return nil, err, code end
        local pid
        pid, err, code = ownerPid(handle)
        if not pid then return nil, err, code end
        local self = win.kernel.GetCurrentProcessId()
        -- Use cross-process marshaling so Windows owns the receiver's copy
        -- even if a timeout occurs during its window procedure.
        if pid == self then return win.Error("CopyDataSend requires a window in another process", 87) end
        local sender = 0
        if senderHwnd ~= nil then
            sender, err, code = checkedHwnd(senderHwnd)
            if not sender then return nil, err, code end
            pid, err, code = ownerPid(sender)
            if not pid then return nil, err, code end
            if pid ~= self then return win.Error("senderHwnd must belong to the calling process", 87) end
            sender = ffi.cast("uintptr_t", sender)
        end
        local payload = ffi.new("fw_window_copydata", #bytes)
        payload.dataId, payload.size = dataId or 0, #bytes
        if #bytes > 0 then
            ffi.copy(payload.bytes, bytes, #bytes)
            payload.data = payload.bytes
        end
        local pointer = ffi.cast("fw_window_copydata *", payload)
        local result, message, status = sendTimeout(handle, 0x004A, sender, ffi.cast("intptr_t", pointer), timeout)
        -- Keep the structure and its inline buffer alive through the native call.
        payload.data = nil
        return result, message, status
    end
    jit.off(window.CopyDataSend, true)
end

return window
