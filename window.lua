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

int __stdcall GetWindowRect(
    void *hWnd,
    int32_t *lpRect
);

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

local function utf8_to_wide(text)
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

local function wide_to_utf8(
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

local function error_message(errorCode)
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
-- HWND validation
-- ============================================================

local function check_hwnd(hwnd)
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

function window.hwndToNumber(hwnd)
    if hwnd == nil
        or hwnd == ffi.NULL
    then
        return nil
    end

    return tonumber(
        ffi.cast(
            "uintptr_t",
            hwnd
        )
    )
end

function window.numberToHwnd(value)
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

local function get_title_internal(hwnd)
    kernel32.SetLastError(0)
    local length = user32.GetWindowTextLengthW(hwnd)
    if length == 0 and kernel32.GetLastError() ~= 0 then
        return nil, nil, 0, win_error("GetWindowTextLengthW failed")
    end
    local titleBuf = ffi.new("uint16_t[?]", length + 1)
    kernel32.SetLastError(0)
    local copied = user32.GetWindowTextW(hwnd, titleBuf, length + 1)
    if copied == 0 and kernel32.GetLastError() ~= 0 then
        return nil, nil, 0, win_error("GetWindowTextW failed")
    end
    local text = wide_to_utf8(titleBuf, copied)
    if text == nil then return nil, nil, 0, win_error("UTF-16 conversion failed") end
    return text, titleBuf, copied
end

function window.getTitle(hwnd)
    local ok, err = check_hwnd(hwnd)
    if not ok then return nil, err end
    local title, _, _, titleErr = get_title_internal(hwnd)
    return title, titleErr
end

-- ============================================================
-- Unicode case-insensitive substring
-- ============================================================

local function wide_contains(
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

function window.find(
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
        utf8_to_wide(
            titlePart
        )

    if findWide == nil then
        return nil,
            "title is not valid UTF-8"
    end

    local foundHwnd = nil

    local callback

    callback = ffi.cast(
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
                get_title_internal(hwnd)

            if titleWide ~= nil
                and wide_contains(
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
    local enumerated = user32.EnumWindows(callback, 0)
    local enumError = tonumber(kernel32.GetLastError())
    callback:free()
    if enumerated == 0 and enumError ~= 0 then
        return nil, "EnumWindows failed: " .. error_message(enumError)
    end

    if foundHwnd == nil then
        return nil
    end

    return foundHwnd
end

-- ============================================================
-- Find all matching top-level windows
-- ============================================================

function window.findAll(
    titlePart,
    includeHidden
)
    if titlePart == nil then
        return nil,
            "title cannot be nil"
    end

    local findWide,
    findLength =
        utf8_to_wide(
            tostring(titlePart)
        )

    if findWide == nil then
        return nil,
            "title is not valid UTF-8"
    end

    local result = {}

    local callback

    callback = ffi.cast(
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
                get_title_internal(hwnd)

            if titleWide ~= nil
                and wide_contains(
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
    local enumerated = user32.EnumWindows(callback, 0)
    local enumError = tonumber(kernel32.GetLastError())
    callback:free()
    if enumerated == 0 and enumError ~= 0 then
        return nil, "EnumWindows failed: " .. error_message(enumError)
    end

    return result
end

-- ============================================================
-- Exists
-- ============================================================

function window.exists(hwnd)
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

function window.isVisible(hwnd)
    local ok, err = check_hwnd(hwnd)

    if not ok then
        return false
    end

    return user32.IsWindowVisible(hwnd) ~= 0
end

-- ============================================================
-- Enabled
-- ============================================================

function window.isEnabled(hwnd)
    local ok, err = check_hwnd(hwnd)

    if not ok then
        return false
    end

    return user32.IsWindowEnabled(hwnd) ~= 0
end

-- ============================================================
-- Minimized
-- ============================================================

function window.isMinimized(hwnd)
    local ok, err = check_hwnd(hwnd)

    if not ok then
        return false
    end

    return user32.IsIconic(hwnd) ~= 0
end

-- ============================================================
-- Maximized
-- ============================================================

function window.isMaximized(hwnd)
    local ok, err = check_hwnd(hwnd)

    if not ok then
        return false
    end

    return user32.IsZoomed(hwnd) ~= 0
end

-- ============================================================
-- Class name
-- ============================================================

function window.getClass(hwnd)
    local ok, err = check_hwnd(hwnd)

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
            win_error(
                "GetClassNameW failed"
            )
    end

    return wide_to_utf8(
        classBuf,
        length
    )
end

-- ============================================================
-- PID / Thread ID
-- ============================================================

function window.getPid(hwnd)
    local ok, err = check_hwnd(hwnd)

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
            win_error(
                "GetWindowThreadProcessId failed"
            )
    end

    return tonumber(pidBuf[0]),
        tonumber(threadId)
end

-- ============================================================
-- Position and size
-- ============================================================

function window.getRect(hwnd)
    local ok, err = check_hwnd(hwnd)

    if not ok then
        return nil, err
    end

    local rectBuf = ffi.new(
        "int32_t[4]"
    )

    if user32.GetWindowRect(
            hwnd,
            rectBuf
        ) == 0 then
        return nil,
            win_error(
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

function window.move(
    hwnd,
    x,
    y,
    width,
    height,
    repaint
)
    local ok, err = check_hwnd(hwnd)

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
            win_error(
                "MoveWindow failed"
            )
    end

    return true
end

-- ============================================================
-- Move only
-- ============================================================

function window.moveTo(
    hwnd,
    x,
    y
)
    local rect, err =
        window.getRect(hwnd)

    if not rect then
        return nil, err
    end

    return window.move(
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

function window.resize(
    hwnd,
    width,
    height
)
    local rect, err =
        window.getRect(hwnd)

    if not rect then
        return nil, err
    end

    return window.move(
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

function window.show(hwnd)
    local ok, err = check_hwnd(hwnd)

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

function window.hide(hwnd)
    local ok, err = check_hwnd(hwnd)

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

function window.minimize(hwnd)
    local ok, err = check_hwnd(hwnd)

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

function window.maximize(hwnd)
    local ok, err = check_hwnd(hwnd)

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

function window.restore(hwnd)
    local ok, err = check_hwnd(hwnd)

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

function window.activate(hwnd)
    local ok, err = check_hwnd(hwnd)

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

function window.enable(
    hwnd,
    enabled
)
    local ok, err = check_hwnd(hwnd)

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

function window.disable(hwnd)
    return window.enable(
        hwnd,
        false
    )
end

-- ============================================================
-- Set title
-- ============================================================

function window.setTitle(
    hwnd,
    text
)
    local ok, err = check_hwnd(hwnd)

    if not ok then
        return nil, err
    end

    local textWide =
        utf8_to_wide(
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
            win_error(
                "SetWindowTextW failed"
            )
    end

    return true
end

-- ============================================================
-- Close
-- ============================================================

function window.close(hwnd)
    local ok, err = check_hwnd(hwnd)

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
            win_error(
                "PostMessageW(WM_CLOSE) failed"
            )
    end

    return true
end

-- ============================================================
-- Wait for window
-- ============================================================

function window.wait(
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
            window.find(
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

function window.waitClose(
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

local function ahk_timeout_to_ms(timeoutSeconds)
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

local function ahk_active_hwnd()
    local hwnd = user32.GetForegroundWindow()

    if hwnd == nil
        or hwnd == ffi.NULL
        or user32.IsWindow(hwnd) == 0
    then
        return nil
    end

    return hwnd
end

local function ahk_normalize_hwnd(value)
    if type(value) == "cdata" then
        if user32.IsWindow(value) ~= 0 then
            return value
        end

        return nil
    end

    if type(value) == "number" then
        local hwnd = window.numberToHwnd(value)

        if hwnd ~= nil
            and user32.IsWindow(hwnd) ~= 0
        then
            return hwnd
        end

        return nil
    end

    return nil
end

local function ahk_resolve_target(
    target,
    includeHidden
)
    local hwnd = ahk_normalize_hwnd(target)

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
        return ahk_active_hwnd()
    end

    return window.find(
        target,
        includeHidden == true
    )
end

local function ahk_resolve_required(
    target,
    includeHidden
)
    local hwnd, err = ahk_resolve_target(
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

local function ahk_same_hwnd(
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

local function ahk_wait_until(
    checkFunction,
    timeoutSeconds
)
    local timeoutMs, timeoutErr =
        ahk_timeout_to_ms(
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
            checkFunction()

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

local function ahk_normalize_on_off(
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

local function ahk_get_window_long_ptr(
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
            .. error_message(errorCode)
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
    return ahk_resolve_target(
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
    return ahk_wait_until(
        function()
            return ahk_resolve_target(
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
        ahk_resolve_target(
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
        ahk_wait_until(
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
        ahk_active_hwnd()

    if activeHwnd == nil then
        return nil
    end

    if target == nil
        or target == "A"
    then
        return activeHwnd
    end

    local directHwnd =
        ahk_normalize_hwnd(target)

    if directHwnd ~= nil then
        if ahk_same_hwnd(
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
        window.findAll(
            target,
            includeHidden == true
        )

    if matches == nil then
        return nil, err
    end

    for index = 1, #matches do
        if ahk_same_hwnd(
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
    return ahk_wait_until(
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
        ahk_wait_until(
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
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.activate(hwnd)
end

function window.WinClose(
    target,
    includeHidden
)
    local hwnd, err =
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.close(hwnd)
end

function window.WinShow(
    target,
    includeHidden
)
    local hwnd, err =
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.show(hwnd)
end

function window.WinHide(
    target,
    includeHidden
)
    local hwnd, err =
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.hide(hwnd)
end

function window.WinMinimize(
    target,
    includeHidden
)
    local hwnd, err =
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.minimize(hwnd)
end

function window.WinMaximize(
    target,
    includeHidden
)
    local hwnd, err =
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.maximize(hwnd)
end

function window.WinRestore(
    target,
    includeHidden
)
    local hwnd, err =
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.restore(hwnd)
end

-- ============================================================
-- Information
-- ============================================================

function window.WinGetTitle(
    target,
    includeHidden
)
    local hwnd, err =
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.getTitle(hwnd)
end

function window.WinGetClass(
    target,
    includeHidden
)
    local hwnd, err =
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.getClass(hwnd)
end

function window.WinGetPID(
    target,
    includeHidden
)
    local hwnd, err =
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    local pid, threadId =
        window.getPid(hwnd)

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
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    local rect, rectErr =
        window.getRect(hwnd)

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
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    if window.isMinimized(hwnd) then
        return -1
    end

    if window.isMaximized(hwnd) then
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
        window.findAll(
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

    return window.findAll(
        title,
        includeHidden == true
    )
end

function window.WinGetStyle(
    target,
    includeHidden
)
    local hwnd, err =
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return ahk_get_window_long_ptr(
        hwnd,
        GWL_STYLE
    )
end

function window.WinGetExStyle(
    target,
    includeHidden
)
    local hwnd, err =
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return ahk_get_window_long_ptr(
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
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    local rect, rectErr =
        window.getRect(hwnd)

    if rect == nil then
        return nil, rectErr
    end

    if x == nil then x = rect.x end
    if y == nil then y = rect.y end
    if width == nil then width = rect.width end
    if height == nil then height = rect.height end

    return window.move(
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
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    return window.setTitle(
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
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    local currentState =
        window.isEnabled(hwnd)

    local enabled, valueErr =
        ahk_normalize_on_off(
            value,
            currentState
        )

    if enabled == nil then
        return nil, valueErr
    end

    return window.enable(
        hwnd,
        enabled
    )
end

function window.WinIsAlwaysOnTop(
    target,
    includeHidden
)
    local hwnd, err =
        ahk_resolve_required(
            target,
            includeHidden
        )

    if hwnd == nil then
        return nil, err
    end

    local exStyle, styleErr =
        ahk_get_window_long_ptr(
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
        ahk_resolve_required(
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
        ahk_normalize_on_off(
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
            win_error(
                "SetWindowPos failed"
            )
    end

    return true
end

-- WinAPI window calls can synchronously re-enter Lua WNDPROC callbacks.
jit.off(get_title_internal, true)
for _, fn in pairs(window) do
    if type(fn) == "function" then jit.off(fn, true) end
end
return window
