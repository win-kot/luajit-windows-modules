local ffi = require("ffi")
local bit = require("bit")

ffi.cdef [[
typedef struct {
    int32_t dx;
    int32_t dy;
    uint32_t mouseData;
    uint32_t dwFlags;
    uint32_t time;
    uintptr_t dwExtraInfo;
} LJ_KEYBOARD_MOUSEINPUT;

typedef struct {
    uint16_t wVk;
    uint16_t wScan;
    uint32_t dwFlags;
    uint32_t time;
    uintptr_t dwExtraInfo;
} LJ_KEYBOARD_KEYBDINPUT;

typedef struct {
    uint32_t uMsg;
    uint16_t wParamL;
    uint16_t wParamH;
} LJ_KEYBOARD_HARDWAREINPUT;

typedef union {
    LJ_KEYBOARD_MOUSEINPUT mi;
    LJ_KEYBOARD_KEYBDINPUT ki;
    LJ_KEYBOARD_HARDWAREINPUT hi;
} LJ_KEYBOARD_INPUT_UNION;

typedef struct {
    uint32_t type;
    LJ_KEYBOARD_INPUT_UNION u;
} LJ_KEYBOARD_INPUT;

uint32_t __stdcall SendInput(
    uint32_t cInputs,
    void *pInputs,
    int cbSize
);

int __stdcall MultiByteToWideChar(
    uint32_t CodePage,
    uint32_t dwFlags,
    const char *lpMultiByteStr,
    int cbMultiByte,
    uint16_t *lpWideCharStr,
    int cchWideChar
);

int16_t __stdcall GetAsyncKeyState(
    int vKey
);

uint32_t __stdcall GetLastError(void);

void __stdcall Sleep(
    uint32_t dwMilliseconds
);
]]

local user32 = ffi.load("user32")
local kernel32 = ffi.load("kernel32")

local keyboard = {}

local INPUT_KEYBOARD = 1

local KEYEVENTF_EXTENDEDKEY = 0x0001
local KEYEVENTF_KEYUP = 0x0002
local KEYEVENTF_UNICODE = 0x0004

local CP_UTF8 = 65001
local MB_ERR_INVALID_CHARS = 0x00000008


-- ============================================================
-- Virtual key codes
-- ============================================================

local KEY_CODES = {
    BACKSPACE = 0x08,
    BS = 0x08,

    TAB = 0x09,

    ENTER = 0x0D,
    RETURN = 0x0D,

    SHIFT = 0x10,
    CTRL = 0x11,
    CONTROL = 0x11,
    ALT = 0x12,

    PAUSE = 0x13,
    CAPSLOCK = 0x14,

    ESC = 0x1B,
    ESCAPE = 0x1B,

    SPACE = 0x20,

    PGUP = 0x21,
    PAGEUP = 0x21,

    PGDN = 0x22,
    PAGEDOWN = 0x22,

    END = 0x23,
    HOME = 0x24,

    LEFT = 0x25,
    UP = 0x26,
    RIGHT = 0x27,
    DOWN = 0x28,

    PRINTSCREEN = 0x2C,
    INSERT = 0x2D,
    DELETE = 0x2E,

    LWIN = 0x5B,
    RWIN = 0x5C,
    APPS = 0x5D,

    NUM0 = 0x60,
    NUM1 = 0x61,
    NUM2 = 0x62,
    NUM3 = 0x63,
    NUM4 = 0x64,
    NUM5 = 0x65,
    NUM6 = 0x66,
    NUM7 = 0x67,
    NUM8 = 0x68,
    NUM9 = 0x69,

    MULTIPLY = 0x6A,
    ADD = 0x6B,
    SUBTRACT = 0x6D,
    DECIMAL = 0x6E,
    DIVIDE = 0x6F,

    NUMLOCK = 0x90,
    SCROLLLOCK = 0x91,

    LSHIFT = 0xA0,
    RSHIFT = 0xA1,

    LCTRL = 0xA2,
    RCTRL = 0xA3,

    LALT = 0xA4,
    RALT = 0xA5,

    VOLUME_MUTE = 0xAD,
    VOLUME_DOWN = 0xAE,
    VOLUME_UP = 0xAF,

    MEDIA_NEXT = 0xB0,
    MEDIA_PREV = 0xB1,
    MEDIA_STOP = 0xB2,
    MEDIA_PLAY_PAUSE = 0xB3
}


for code = string.byte("A"), string.byte("Z") do
    KEY_CODES[string.char(code)] = code
end


for number = 0, 9 do
    KEY_CODES[tostring(number)] =
        0x30 + number
end


for number = 1, 24 do
    KEY_CODES["F" .. number] =
        0x6F + number
end


-- ============================================================
-- Extended keys
-- ============================================================

local EXTENDED_KEYS = {
    [0x21] = true,
    [0x22] = true,
    [0x23] = true,
    [0x24] = true,
    [0x25] = true,
    [0x26] = true,
    [0x27] = true,
    [0x28] = true,

    [0x2C] = true,
    [0x2D] = true,
    [0x2E] = true,

    [0x5B] = true,
    [0x5C] = true,
    [0x5D] = true,

    [0x6F] = true,

    [0xA3] = true,
    [0xA5] = true
}


-- ============================================================
-- Key code
-- ============================================================

function keyboard.keyCode(key)
    if type(key) == "number" then
        if key ~= math.floor(key)
            or key < 0
            or key > 255
        then
            return nil,
                "invalid virtual key code"
        end

        return math.floor(key)
    end

    if type(key) ~= "string" then
        return nil,
            "key must be a name or virtual key code"
    end

    local name =
        key:upper()

    local code =
        KEY_CODES[name]

    if code == nil then
        return nil,
            "unknown key: "
            .. tostring(key)
    end

    return code
end

-- ============================================================
-- Send INPUT array
-- ============================================================

local function send_inputs(inputs, count)
    local sent =
        user32.SendInput(
            count,
            inputs,
            ffi.sizeof(
                "LJ_KEYBOARD_INPUT"
            )
        )

    if sent ~= count then
        return nil,
            "SendInput inserted "
            .. tostring(sent)
            .. " of "
            .. tostring(count)
            .. " events"
    end

    return true
end


-- ============================================================
-- Create keyboard event
-- ============================================================

local function make_key_event(
    inputObj,
    keyCode,
    keyUp
)
    inputObj.type =
        INPUT_KEYBOARD

    inputObj.u.ki.wVk =
        keyCode

    inputObj.u.ki.wScan = 0

    local flags = 0

    if EXTENDED_KEYS[keyCode] then
        flags =
            flags + KEYEVENTF_EXTENDEDKEY
    end

    if keyUp then
        flags =
            flags + KEYEVENTF_KEYUP
    end

    inputObj.u.ki.dwFlags =
        flags

    inputObj.u.ki.time = 0
    inputObj.u.ki.dwExtraInfo = 0
end


-- ============================================================
-- Key down
-- ============================================================

function keyboard.keyDown(key)
    local keyCode, err =
        keyboard.keyCode(key)

    if keyCode == nil then
        return nil, err
    end

    local inputs =
        ffi.new(
            "LJ_KEYBOARD_INPUT[1]"
        )

    make_key_event(
        inputs[0],
        keyCode,
        false
    )

    return send_inputs(
        inputs,
        1
    )
end

-- ============================================================
-- Key up
-- ============================================================

function keyboard.keyUp(key)
    local keyCode, err =
        keyboard.keyCode(key)

    if keyCode == nil then
        return nil, err
    end

    local inputs =
        ffi.new(
            "LJ_KEYBOARD_INPUT[1]"
        )

    make_key_event(
        inputs[0],
        keyCode,
        true
    )

    return send_inputs(
        inputs,
        1
    )
end

-- ============================================================
-- Press key
-- ============================================================

function keyboard.press(
    key,
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
        local ok, err =
            keyboard.keyDown(key)

        if not ok then
            return nil, err
        end

        ok, err =
            keyboard.keyUp(key)

        if not ok then
            return nil, err
        end

        if delay > 0
            and index < count
        then
            kernel32.Sleep(delay)
        end
    end

    return true
end

-- ============================================================
-- Hotkey
--
-- keyboard.hotkey({"CTRL", "SHIFT", "S"})
-- ============================================================

function keyboard.hotkey(keys)
    if type(keys) ~= "table"
        or #keys == 0
    then
        return nil,
            "keys must be a non-empty table"
    end

    local codes = {}

    for index = 1, #keys do
        local code, err =
            keyboard.keyCode(
                keys[index]
            )

        if code == nil then
            return nil, err
        end

        codes[index] = code
    end

    local eventCount =
        #codes * 2

    local inputs =
        ffi.new(
            "LJ_KEYBOARD_INPUT[?]",
            eventCount
        )

    local inputIndex = 0

    for index = 1, #codes do
        make_key_event(
            inputs[inputIndex],
            codes[index],
            false
        )

        inputIndex =
            inputIndex + 1
    end

    for index = #codes, 1, -1 do
        make_key_event(
            inputs[inputIndex],
            codes[index],
            true
        )

        inputIndex =
            inputIndex + 1
    end

    return send_inputs(
        inputs,
        eventCount
    )
end

-- ============================================================
-- UTF-8 -> UTF-16
-- ============================================================

local function utf8_to_wide(text)
    if text == nil then
        return nil, nil
    end

    text = tostring(text)

    if text == "" then
        return ffi.new(
            "uint16_t[1]"
        ), 0
    end

    local wideLength =
        kernel32.MultiByteToWideChar(
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

    local wideBuf =
        ffi.new(
            "uint16_t[?]",
            wideLength
        )

    local result =
        kernel32.MultiByteToWideChar(
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

    return wideBuf,
        wideLength
end


-- ============================================================
-- Unicode event
-- ============================================================

local function make_unicode_event(
    inputObj,
    codeUnit,
    keyUp
)
    inputObj.type =
        INPUT_KEYBOARD

    inputObj.u.ki.wVk = 0
    inputObj.u.ki.wScan =
        codeUnit

    local flags =
        KEYEVENTF_UNICODE

    if keyUp then
        flags =
            flags + KEYEVENTF_KEYUP
    end

    inputObj.u.ki.dwFlags =
        flags

    inputObj.u.ki.time = 0
    inputObj.u.ki.dwExtraInfo = 0
end


-- ============================================================
-- Send Unicode text
-- ============================================================

function keyboard.sendText(text)
    if text == nil then
        return nil,
            "text cannot be nil"
    end

    local wideBuf,
    wideLength =
        utf8_to_wide(
            tostring(text)
        )

    if wideBuf == nil then
        return nil,
            "text is not valid UTF-8"
    end

    if wideLength == 0 then
        return true
    end

    local eventCount =
        wideLength * 2

    local inputs =
        ffi.new(
            "LJ_KEYBOARD_INPUT[?]",
            eventCount
        )

    local inputIndex = 0

    for index = 0, wideLength - 1 do
        local codeUnit =
            wideBuf[index]

        make_unicode_event(
            inputs[inputIndex],
            codeUnit,
            false
        )

        inputIndex =
            inputIndex + 1

        make_unicode_event(
            inputs[inputIndex],
            codeUnit,
            true
        )

        inputIndex =
            inputIndex + 1
    end

    return send_inputs(
        inputs,
        eventCount
    )
end

-- ============================================================
-- Key state
-- ============================================================

function keyboard.isDown(key)
    local keyCode, err =
        keyboard.keyCode(key)

    if keyCode == nil then
        return nil, err
    end

    local state =
        tonumber(
            user32.GetAsyncKeyState(
                keyCode
            )
        )

    return bit.band(
        state,
        0x8000
    ) ~= 0
end

-- ============================================================
-- Sleep helper
-- ============================================================

function keyboard.sleep(ms)
    ms = ms == nil and 0 or tonumber(ms)
    if not ms or ms ~= ms or ms == -math.huge or ms >= 4294967295 then
        return nil, "sleep duration must be finite and below 4294967295 ms"
    end
    if ms < 0 then ms = 0 end

    kernel32.Sleep(
        math.floor(ms)
    )
end

return keyboard
