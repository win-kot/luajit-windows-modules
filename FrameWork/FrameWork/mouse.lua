local ffi = require("ffi")
local errors = require("_errors")

ffi.cdef [[
typedef struct {
    int32_t dx;
    int32_t dy;
    uint32_t mouseData;
    uint32_t dwFlags;
    uint32_t time;
    uintptr_t dwExtraInfo;
} LJ_MOUSE_MOUSEINPUT;

typedef struct {
    uint16_t wVk;
    uint16_t wScan;
    uint32_t dwFlags;
    uint32_t time;
    uintptr_t dwExtraInfo;
} LJ_MOUSE_KEYBDINPUT;

typedef struct {
    uint32_t uMsg;
    uint16_t wParamL;
    uint16_t wParamH;
} LJ_MOUSE_HARDWAREINPUT;

typedef union {
    LJ_MOUSE_MOUSEINPUT mi;
    LJ_MOUSE_KEYBDINPUT ki;
    LJ_MOUSE_HARDWAREINPUT hi;
} LJ_MOUSE_INPUT_UNION;

typedef struct {
    uint32_t type;
    LJ_MOUSE_INPUT_UNION u;
} LJ_MOUSE_INPUT;

typedef struct {
    int32_t x;
    int32_t y;
} LJ_MOUSE_POINT;

uint32_t __stdcall SendInput(
    uint32_t cInputs,
    void *pInputs,
    int cbSize
);

int __stdcall GetCursorPos(
    LJ_MOUSE_POINT *lpPoint
);

int __stdcall GetSystemMetrics(
    int nIndex
);

uint32_t __stdcall GetDoubleClickTime(void);
uint32_t __stdcall GetLastError(void);
void __stdcall SetLastError(uint32_t code);

void __stdcall Sleep(
    uint32_t dwMilliseconds
);
]]

local user32 = ffi.load("user32")
local kernel32 = ffi.load("kernel32")

local mouse = {}

local INPUT_MOUSE = 0

local MOUSEEVENTF_MOVE = 0x0001
local MOUSEEVENTF_LEFTDOWN = 0x0002
local MOUSEEVENTF_LEFTUP = 0x0004
local MOUSEEVENTF_RIGHTDOWN = 0x0008
local MOUSEEVENTF_RIGHTUP = 0x0010
local MOUSEEVENTF_MIDDLEDOWN = 0x0020
local MOUSEEVENTF_MIDDLEUP = 0x0040
local MOUSEEVENTF_XDOWN = 0x0080
local MOUSEEVENTF_XUP = 0x0100
local MOUSEEVENTF_WHEEL = 0x0800
local MOUSEEVENTF_HWHEEL = 0x1000
local MOUSEEVENTF_VIRTUALDESK = 0x4000
local MOUSEEVENTF_ABSOLUTE = 0x8000

local XBUTTON1 = 0x0001
local XBUTTON2 = 0x0002

local WHEEL_DELTA = 120

local SM_XVIRTUALSCREEN = 76
local SM_YVIRTUALSCREEN = 77
local SM_CXVIRTUALSCREEN = 78
local SM_CYVIRTUALSCREEN = 79


-- ============================================================
-- Send mouse event
-- ============================================================

local function SendEvent(
    flags,
    dx,
    dy,
    data
)
    local inputs =
        ffi.new(
            "LJ_MOUSE_INPUT[1]"
        )

    inputs[0].type =
        INPUT_MOUSE

    inputs[0].u.mi.dx =
        dx or 0

    inputs[0].u.mi.dy =
        dy or 0

    inputs[0].u.mi.mouseData =
        data or 0

    inputs[0].u.mi.dwFlags =
        flags

    inputs[0].u.mi.time = 0
    inputs[0].u.mi.dwExtraInfo = 0

    kernel32.SetLastError(0)
    local sent =
        user32.SendInput(
            1,
            inputs,
            ffi.sizeof(
                "LJ_MOUSE_INPUT"
            )
        )

    if sent ~= 1 then
        return errors.Win32("SendInput", tonumber(kernel32.GetLastError()))
    end

    return true
end


-- ============================================================
-- Current position
-- ============================================================

function mouse.PositionGet()
    local pointObj =
        ffi.new(
            "LJ_MOUSE_POINT[1]"
        )

    if user32.GetCursorPos(
            pointObj
        ) == 0 then
        return errors.Win32("GetCursorPos", tonumber(kernel32.GetLastError()))
    end

    return tonumber(
            pointObj[0].x
        ),
        tonumber(
            pointObj[0].y
        )
end

-- ============================================================
-- Virtual desktop
-- ============================================================

function mouse.VirtualScreenGet()
    return {
        x =
            user32.GetSystemMetrics(
                SM_XVIRTUALSCREEN
            ),

        y =
            user32.GetSystemMetrics(
                SM_YVIRTUALSCREEN
            ),

        width =
            user32.GetSystemMetrics(
                SM_CXVIRTUALSCREEN
            ),

        height =
            user32.GetSystemMetrics(
                SM_CYVIRTUALSCREEN
            )
    }
end

-- ============================================================
-- Relative movement
-- ============================================================

function mouse.Move(dx, dy)
    dx =
        tonumber(dx)

    dy =
        tonumber(dy)

    if dx == nil
        or dy == nil
    then
        return nil,
            "invalid coordinates"
    end

    return SendEvent(
        MOUSEEVENTF_MOVE,
        math.floor(dx),
        math.floor(dy),
        0
    )
end

-- ============================================================
-- Absolute movement
-- ============================================================

local function Clamp(
    value,
    minimum,
    maximum
)
    if value < minimum then
        return minimum
    end

    if value > maximum then
        return maximum
    end

    return value
end


function mouse.MoveTo(x, y)
    x =
        tonumber(x)

    y =
        tonumber(y)

    if x == nil
        or y == nil
    then
        return nil,
            "invalid coordinates"
    end

    local screen =
        mouse.VirtualScreenGet()

    if screen.width <= 1
        or screen.height <= 1
    then
        return nil,
            "invalid virtual screen size"
    end

    local maxX =
        screen.x
        + screen.width
        - 1

    local maxY =
        screen.y
        + screen.height
        - 1

    x =
        Clamp(
            x,
            screen.x,
            maxX
        )

    y =
        Clamp(
            y,
            screen.y,
            maxY
        )

    local normalizedX =
        math.floor(
            (
                (x - screen.x)
                * 65535
                / (screen.width - 1)
            )
            + 0.5
        )

    local normalizedY =
        math.floor(
            (
                (y - screen.y)
                * 65535
                / (screen.height - 1)
            )
            + 0.5
        )

    return SendEvent(
        MOUSEEVENTF_MOVE
        + MOUSEEVENTF_ABSOLUTE
        + MOUSEEVENTF_VIRTUALDESK,
        normalizedX,
        normalizedY,
        0
    )
end

-- ============================================================
-- Button information
-- ============================================================

local function ButtonInfo(
    button,
    keyUp
)
    local name =
        tostring(
            button or "left"
        ):lower()

    if name == "left"
        or name == "l"
    then
        if keyUp then
            return MOUSEEVENTF_LEFTUP, 0
        end

        return MOUSEEVENTF_LEFTDOWN, 0
    end

    if name == "right"
        or name == "r"
    then
        if keyUp then
            return MOUSEEVENTF_RIGHTUP, 0
        end

        return MOUSEEVENTF_RIGHTDOWN, 0
    end

    if name == "middle"
        or name == "m"
    then
        if keyUp then
            return MOUSEEVENTF_MIDDLEUP, 0
        end

        return MOUSEEVENTF_MIDDLEDOWN, 0
    end

    if name == "x1" then
        if keyUp then
            return MOUSEEVENTF_XUP,
                XBUTTON1
        end

        return MOUSEEVENTF_XDOWN,
            XBUTTON1
    end

    if name == "x2" then
        if keyUp then
            return MOUSEEVENTF_XUP,
                XBUTTON2
        end

        return MOUSEEVENTF_XDOWN,
            XBUTTON2
    end

    return nil, nil
end


-- ============================================================
-- Button down
-- ============================================================

function mouse.Down(button)
    local flags, data =
        ButtonInfo(
            button,
            false
        )

    if flags == nil then
        return nil,
            "unknown mouse button"
    end

    return SendEvent(
        flags,
        0,
        0,
        data
    )
end

-- ============================================================
-- Button up
-- ============================================================

function mouse.Up(button)
    local flags, data =
        ButtonInfo(
            button,
            true
        )

    if flags == nil then
        return nil,
            "unknown mouse button"
    end

    return SendEvent(
        flags,
        0,
        0,
        data
    )
end

-- ============================================================
-- Click
-- ============================================================

function mouse.Click(
    button,
    count,
    delay
)
    count = count == nil and 1 or tonumber(count)
    delay = delay == nil and 0 or tonumber(delay)
    if not count or count ~= count or count > 9007199254740991 or count < 1 then
        return nil, "count must be a finite number at least 1"
    end
    if not delay or delay ~= delay or delay < 0 or delay >= 4294967295 then
        return nil, "delay must be finite and between 0 and 4294967294 ms"
    end
    count = math.floor(count)

    if count < 1 then
        return nil,
            "count must be at least 1"
    end

    for index = 1, count do
        local ok, err, code =
            mouse.Down(button)

        if not ok then
            return nil, err, code
        end

        ok, err, code =
            mouse.Up(button)

        if not ok then
            return nil, err, code
        end

        if delay > 0
            and index < count
        then
            kernel32.Sleep(
                delay
            )
        end
    end

    return true
end

-- ============================================================
-- Double click
-- ============================================================

function mouse.DoubleClick(button)
    local doubleClickTime =
        tonumber(
            user32.GetDoubleClickTime()
        )

    local delay =
        math.floor(
            doubleClickTime / 4
        )

    return mouse.Click(
        button,
        2,
        delay
    )
end

-- ============================================================
-- Click at coordinates
-- ============================================================

function mouse.ClickAt(
    x,
    y,
    button,
    count
)
    local ok, err, code =
        mouse.MoveTo(
            x,
            y
        )

    if not ok then
        return nil, err, code
    end

    return mouse.Click(
        button,
        count
    )
end

-- ============================================================
-- Vertical wheel
--
-- positive = up
-- negative = down
-- ============================================================

function mouse.Wheel(steps)
    steps =
        tonumber(steps)

    if steps == nil then
        return nil,
            "invalid wheel amount"
    end

    local delta =
        math.floor(
            steps * WHEEL_DELTA
        )

    return SendEvent(
        MOUSEEVENTF_WHEEL,
        0,
        0,
        ffi.cast(
            "uint32_t",
            delta
        )
    )
end

-- ============================================================
-- Horizontal wheel
--
-- positive = right
-- negative = left
-- ============================================================

function mouse.HWheel(steps)
    steps =
        tonumber(steps)

    if steps == nil then
        return nil,
            "invalid wheel amount"
    end

    local delta =
        math.floor(
            steps * WHEEL_DELTA
        )

    return SendEvent(
        MOUSEEVENTF_HWHEEL,
        0,
        0,
        ffi.cast(
            "uint32_t",
            delta
        )
    )
end

-- ============================================================
-- Drag
-- ============================================================

function mouse.DragTo(
    x,
    y,
    button
)
    button =
        button or "left"

    local ok, err, code =
        mouse.Down(button)

    if not ok then
        return nil, err, code
    end

    ok, err, code =
        mouse.MoveTo(
            x,
            y
        )

    if not ok then
        mouse.Up(button)

        return nil, err, code
    end

    ok, err, code =
        mouse.Up(button)

    if not ok then
        return nil, err, code
    end

    return true
end

-- ============================================================
-- Sleep
-- ============================================================

mouse.Sleep = require("_win_native").Sleep

return mouse
