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

uint32_t __stdcall FormatMessageW(
    uint32_t dwFlags,
    const void *lpSource,
    uint32_t dwMessageId,
    uint32_t dwLanguageId,
    uint16_t *lpBuffer,
    uint32_t nSize,
    void *Arguments
);

uint32_t __stdcall ExpandEnvironmentStringsW(
    const uint16_t *lpSrc,
    uint16_t *lpDst,
    uint32_t nSize
);

int32_t __stdcall RegOpenKeyExW(
    void *hKey,
    const uint16_t *lpSubKey,
    uint32_t ulOptions,
    uint32_t samDesired,
    void **phkResult
);

int32_t __stdcall RegCreateKeyExW(
    void *hKey,
    const uint16_t *lpSubKey,
    uint32_t Reserved,
    uint16_t *lpClass,
    uint32_t dwOptions,
    uint32_t samDesired,
    void *lpSecurityAttributes,
    void **phkResult,
    uint32_t *lpdwDisposition
);

int32_t __stdcall RegCloseKey(
    void *hKey
);

int32_t __stdcall RegGetValueW(
    void *hkey,
    const uint16_t *lpSubKey,
    const uint16_t *lpValue,
    uint32_t dwFlags,
    uint32_t *pdwType,
    void *pvData,
    uint32_t *pcbData
);

int32_t __stdcall RegSetValueExW(
    void *hKey,
    const uint16_t *lpValueName,
    uint32_t Reserved,
    uint32_t dwType,
    const uint8_t *lpData,
    uint32_t cbData
);

int32_t __stdcall RegDeleteValueW(
    void *hKey,
    const uint16_t *lpValueName
);

int32_t __stdcall RegDeleteKeyExW(
    void *hKey,
    const uint16_t *lpSubKey,
    uint32_t samDesired,
    uint32_t Reserved
);

int32_t __stdcall RegDeleteTreeW(
    void *hKey,
    const uint16_t *lpSubKey
);

int32_t __stdcall RegEnumKeyExW(
    void *hKey,
    uint32_t dwIndex,
    uint16_t *lpName,
    uint32_t *lpcchName,
    uint32_t *lpReserved,
    uint16_t *lpClass,
    uint32_t *lpcchClass,
    void *lpftLastWriteTime
);

int32_t __stdcall RegEnumValueW(
    void *hKey,
    uint32_t dwIndex,
    uint16_t *lpValueName,
    uint32_t *lpcchValueName,
    uint32_t *lpReserved,
    uint32_t *lpType,
    uint8_t *lpData,
    uint32_t *lpcbData
);
]]

local kernel32 = ffi.load("kernel32")
local advapi32 = ffi.load("advapi32")

local registry = {}

local CP_UTF8 = 65001
local MB_ERR_INVALID_CHARS = 0x00000008

local FORMAT_MESSAGE_IGNORE_INSERTS = 0x00000200
local FORMAT_MESSAGE_FROM_SYSTEM = 0x00001000

local ERROR_SUCCESS = 0
local ERROR_FILE_NOT_FOUND = 2
local ERROR_PATH_NOT_FOUND = 3
local ERROR_NO_MORE_ITEMS = 259

local KEY_QUERY_VALUE = 0x0001
local KEY_SET_VALUE = 0x0002
local KEY_CREATE_SUB_KEY = 0x0004
local KEY_ENUMERATE_SUB_KEYS = 0x0008

local DELETE_ACCESS = 0x00010000

local KEY_READ = 0x00020019
local KEY_WRITE = 0x00020006

local KEY_WOW64_64KEY = 0x0100
local KEY_WOW64_32KEY = 0x0200

local REG_OPTION_NON_VOLATILE = 0

local REG_CREATED_NEW_KEY = 1
local REG_OPENED_EXISTING_KEY = 2

local REG_NONE = 0
local REG_SZ = 1
local REG_EXPAND_SZ = 2
local REG_BINARY = 3
local REG_DWORD = 4
local REG_MULTI_SZ = 7
local REG_QWORD = 11

local RRF_RT_ANY = 0x0000ffff
local RRF_NOEXPAND = 0x10000000

local UINT32_BASE = 4294967296
local MAX_SAFE_INTEGER = 9007199254740991


-- ============================================================
-- Public constants
-- ============================================================

registry.REG_NONE = REG_NONE
registry.REG_SZ = REG_SZ
registry.REG_EXPAND_SZ = REG_EXPAND_SZ
registry.REG_BINARY = REG_BINARY
registry.REG_DWORD = REG_DWORD
registry.REG_MULTI_SZ = REG_MULTI_SZ
registry.REG_QWORD = REG_QWORD


-- ============================================================
-- Predefined root keys
-- ============================================================

local function make_root(value)
    local signedValue =
        ffi.cast("int32_t", value)

    local pointerValue =
        ffi.cast("intptr_t", signedValue)

    return ffi.cast(
        "void *",
        pointerValue
    )
end


local ROOTS = {
    HKCR = make_root(0x80000000),
    HKEY_CLASSES_ROOT = make_root(0x80000000),

    HKCU = make_root(0x80000001),
    HKEY_CURRENT_USER = make_root(0x80000001),

    HKLM = make_root(0x80000002),
    HKEY_LOCAL_MACHINE = make_root(0x80000002),

    HKU = make_root(0x80000003),
    HKEY_USERS = make_root(0x80000003),

    HKCC = make_root(0x80000005),
    HKEY_CURRENT_CONFIG = make_root(0x80000005)
}


-- ============================================================
-- Registry type names
-- ============================================================

local TYPE_NAMES = {
    [REG_NONE] = "REG_NONE",
    [REG_SZ] = "REG_SZ",
    [REG_EXPAND_SZ] = "REG_EXPAND_SZ",
    [REG_BINARY] = "REG_BINARY",
    [REG_DWORD] = "REG_DWORD",
    [REG_MULTI_SZ] = "REG_MULTI_SZ",
    [REG_QWORD] = "REG_QWORD"
}


function registry.typeName(valueType)
    return TYPE_NAMES[valueType]
        or ("REG_TYPE_" .. tostring(valueType))
end

-- ============================================================
-- UTF-8 -> UTF-16
-- ============================================================

local function utf8_to_wide(text, allowNul)
    if text == nil then
        return nil, 0
    end

    text = tostring(text)

    if not allowNul
        and text:find("\0", 1, true)
    then
        return nil, nil
    end

    if text == "" then
        local wideBuf =
            ffi.new("uint16_t[1]")

        wideBuf[0] = 0

        return wideBuf, 0
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
            wideLength + 1
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

    wideBuf[wideLength] = 0

    return wideBuf, wideLength
end


-- ============================================================
-- UTF-16 -> UTF-8
-- ============================================================

local function wide_to_utf8(widePtr, wideLength)
    if widePtr == nil
        or wideLength == 0
    then
        return ""
    end

    local utf8Length =
        kernel32.WideCharToMultiByte(
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

    local utf8Buf =
        ffi.new(
            "char[?]",
            utf8Length
        )

    local result =
        kernel32.WideCharToMultiByte(
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
-- Win32 error
-- ============================================================

local function error_message(statusCode)
    local errorBuf =
        ffi.new("uint16_t[2048]")

    local length =
        kernel32.FormatMessageW(
            bit.bor(
                FORMAT_MESSAGE_FROM_SYSTEM,
                FORMAT_MESSAGE_IGNORE_INSERTS
            ),
            nil,
            statusCode,
            0,
            errorBuf,
            2048,
            nil
        )

    if length == 0 then
        return "Win32 error "
            .. tostring(statusCode)
    end

    local text =
        wide_to_utf8(
            errorBuf,
            tonumber(length)
        )

    if not text then
        return "Win32 error "
            .. tostring(statusCode)
    end

    text =
        text:gsub(
            "[\r\n]+$",
            ""
        )

    return text
        .. " (Win32 error "
        .. tostring(statusCode)
        .. ")"
end


local function status_error(prefix, statusCode)
    return prefix
        .. ": "
        .. error_message(statusCode)
end


-- ============================================================
-- Registry path
-- ============================================================

local function parse_path(path)
    if path == nil then
        return nil, nil,
            "registry path cannot be nil"
    end

    local text =
        tostring(path):gsub(
            "/",
            "\\"
        )

    while text:sub(-1) == "\\" do
        text = text:sub(1, -2)
    end

    if text == "" then
        return nil, nil,
            "registry path cannot be empty"
    end

    local separator =
        text:find(
            "\\",
            1,
            true
        )

    local rootName
    local subPath

    if separator then
        rootName =
            text:sub(
                1,
                separator - 1
            )

        subPath =
            text:sub(
                separator + 1
            )
    else
        rootName = text
        subPath = ""
    end

    rootName =
        rootName:upper()

    local rootHandle =
        ROOTS[rootName]

    if rootHandle == nil then
        return nil, nil,
            "unknown registry root: "
            .. rootName
    end

    return rootHandle, subPath
end


-- ============================================================
-- Registry view
-- ============================================================

local function get_view_flag(view)
    if view == nil
        or view == ""
        or view == "native"
    then
        return 0
    end

    local viewText =
        tostring(view):lower()

    if viewText == "32"
        or viewText == "x86"
    then
        return KEY_WOW64_32KEY
    end

    if viewText == "64"
        or viewText == "x64"
    then
        return KEY_WOW64_64KEY
    end

    return nil
end


-- ============================================================
-- Key helpers
-- ============================================================

local function close_key(handle, mustClose)
    if mustClose
        and handle ~= nil
        and handle ~= ffi.NULL
    then
        advapi32.RegCloseKey(
            handle
        )
    end
end


local function open_subkey(
    rootHandle,
    subPath,
    access,
    viewFlag
)
    if subPath == "" then
        return rootHandle, false
    end

    local widePath =
        utf8_to_wide(subPath)

    if widePath == nil then
        return nil, nil,
            "registry path is not valid UTF-8"
    end

    local resultHandle =
        ffi.new("void *[1]")

    local statusCode =
        advapi32.RegOpenKeyExW(
            rootHandle,
            widePath,
            0,
            bit.bor(
                access,
                viewFlag
            ),
            resultHandle
        )

    if statusCode ~= ERROR_SUCCESS then
        return nil, nil,
            status_error(
                "RegOpenKeyExW failed",
                statusCode
            ),
            statusCode
    end

    return resultHandle[0], true
end


local function open_key(
    path,
    access,
    view
)
    local rootHandle,
    subPath,
    pathErr =
        parse_path(path)

    if not rootHandle then
        return nil, nil, pathErr
    end

    local viewFlag =
        get_view_flag(view)

    if viewFlag == nil then
        return nil, nil,
            "invalid registry view"
    end

    return open_subkey(
        rootHandle,
        subPath,
        access,
        viewFlag
    )
end


local function create_key_internal(
    path,
    view
)
    local rootHandle,
    subPath,
    pathErr =
        parse_path(path)

    if not rootHandle then
        return nil, nil, nil, pathErr
    end

    local viewFlag =
        get_view_flag(view)

    if viewFlag == nil then
        return nil, nil, nil,
            "invalid registry view"
    end

    if subPath == "" then
        return rootHandle,
            false,
            REG_OPENED_EXISTING_KEY
    end

    local widePath =
        utf8_to_wide(subPath)

    if widePath == nil then
        return nil, nil, nil,
            "registry path is not valid UTF-8"
    end

    local resultHandle =
        ffi.new("void *[1]")

    local disposition =
        ffi.new("uint32_t[1]")

    local access =
        bit.bor(
            KEY_READ,
            KEY_WRITE,
            viewFlag
        )

    local statusCode =
        advapi32.RegCreateKeyExW(
            rootHandle,
            widePath,
            0,
            nil,
            REG_OPTION_NON_VOLATILE,
            access,
            nil,
            resultHandle,
            disposition
        )

    if statusCode ~= ERROR_SUCCESS then
        return nil, nil, nil,
            status_error(
                "RegCreateKeyExW failed",
                statusCode
            ),
            statusCode
    end

    return resultHandle[0],
        true,
        tonumber(disposition[0])
end


-- ============================================================
-- Value name
-- ============================================================

local function value_name_wide(valueName)
    if valueName == nil
        or valueName == ""
    then
        return nil
    end

    local wideName =
        utf8_to_wide(valueName)

    return wideName
end


-- ============================================================
-- Exact REG_QWORD support
-- ============================================================

local function qword_from_parts(highPart, lowPart)
    local qwordBuf =
        ffi.new("uint64_t[1]")

    local words =
        ffi.cast(
            "uint32_t *",
            qwordBuf
        )

    words[0] = lowPart
    words[1] = highPart

    return qwordBuf[0]
end


local function qword_parts(qwordValue)
    local qwordBuf =
        ffi.new(
            "uint64_t[1]",
            qwordValue
        )

    local words =
        ffi.cast(
            "uint32_t *",
            qwordBuf
        )

    return tonumber(words[1]),
        tonumber(words[0])
end


local function parse_qword_string(text)
    if text == nil then
        return nil,
            "invalid QWORD"
    end

    text = tostring(text)

    if text == "" then
        return nil,
            "invalid QWORD"
    end

    if not text:match("^%d+$") then
        return nil,
            "QWORD must contain decimal digits only"
    end

    local highPart = 0
    local lowPart = 0

    for index = 1, #text do
        local digit =
            tonumber(
                text:sub(index, index)
            )

        local lowTemp =
            lowPart * 10
            + digit

        local carry =
            math.floor(
                lowTemp / UINT32_BASE
            )

        lowPart =
            lowTemp
            - carry * UINT32_BASE

        local highTemp =
            highPart * 10
            + carry

        if highTemp >= UINT32_BASE then
            return nil,
                "QWORD value is too large"
        end

        highPart = highTemp
    end

    return qword_from_parts(
        highPart,
        lowPart
    )
end


function registry.qword(value)
    if type(value) == "string" then
        return parse_qword_string(
            value
        )
    end

    if type(value) == "number" then
        if value < 0
            or value > MAX_SAFE_INTEGER
            or value ~= math.floor(value)
        then
            return nil,
                "number is outside exact Lua number range"
        end

        local highPart =
            math.floor(
                value / UINT32_BASE
            )

        local lowPart =
            value
            - highPart * UINT32_BASE

        return qword_from_parts(
            highPart,
            lowPart
        )
    end

    if type(value) == "cdata" then
        local integer = false
        for _, name in ipairs({"int8_t", "uint8_t", "int16_t", "uint16_t",
                               "int32_t", "uint32_t", "int64_t", "uint64_t",
                               "long", "unsigned long", "char"}) do
            if ffi.istype(name, value) then integer = true; break end
        end
        if not integer then return nil, "QWORD requires integer scalar cdata" end
        if value < 0 then return nil, "QWORD cannot be negative" end
        return ffi.cast("uint64_t", value)
    end

    return nil,
        "invalid QWORD value"
end

function registry.qwordToString(value)
    local qwordValue, err =
        registry.qword(value)

    if qwordValue == nil then
        return nil, err
    end

    local highPart,
    lowPart =
        qword_parts(qwordValue)

    if highPart == 0
        and lowPart == 0
    then
        return "0"
    end

    local digits = {}

    while highPart ~= 0
        or lowPart ~= 0
    do
        local highQuotient =
            math.floor(
                highPart / 10
            )

        local highRemainder =
            highPart
            - highQuotient * 10

        local combined =
            highRemainder
            * UINT32_BASE
            + lowPart

        local lowQuotient =
            math.floor(
                combined / 10
            )

        local remainder =
            combined
            - lowQuotient * 10

        digits[#digits + 1] =
            tostring(remainder)

        highPart = highQuotient
        lowPart = lowQuotient
    end

    local result = {}

    for index = #digits, 1, -1 do
        result[#result + 1] =
            digits[index]
    end

    return table.concat(result)
end

-- ============================================================
-- Decode registry data
-- ============================================================

local function decode_string(
    dataBuf,
    dataSize
)
    local widePtr =
        ffi.cast(
            "uint16_t *",
            dataBuf
        )

    local maxLength =
        math.floor(
            dataSize / 2
        )

    local wideLength = 0

    while wideLength < maxLength do
        if widePtr[wideLength] == 0 then
            break
        end

        wideLength =
            wideLength + 1
    end

    return wide_to_utf8(
        widePtr,
        wideLength
    )
end


local function decode_multi_string(
    dataBuf,
    dataSize
)
    local widePtr =
        ffi.cast(
            "uint16_t *",
            dataBuf
        )

    local maxLength =
        math.floor(
            dataSize / 2
        )

    local result = {}
    local startIndex = 0
    local index = 0

    while index < maxLength do
        if widePtr[index] == 0 then
            if index == startIndex then
                break
            end

            local text =
                wide_to_utf8(
                    widePtr + startIndex,
                    index - startIndex
                )

            result[#result + 1] =
                text or ""

            startIndex =
                index + 1
        end

        index = index + 1
    end

    return result
end


local function decode_value(
    dataBuf,
    dataSize,
    valueType
)
    if valueType == REG_SZ
        or valueType == REG_EXPAND_SZ
    then
        return decode_string(
            dataBuf,
            dataSize
        )
    end

    if valueType == REG_MULTI_SZ then
        return decode_multi_string(
            dataBuf,
            dataSize
        )
    end

    if valueType == REG_DWORD then
        if dataSize < 4 then
            return nil,
                "invalid REG_DWORD size"
        end

        local numberBuf =
            ffi.new("uint32_t[1]")

        ffi.copy(
            numberBuf,
            dataBuf,
            4
        )

        return tonumber(
            numberBuf[0]
        )
    end

    if valueType == REG_QWORD then
        if dataSize < 8 then
            return nil,
                "invalid REG_QWORD size"
        end

        local numberBuf =
            ffi.new("uint64_t[1]")

        ffi.copy(
            numberBuf,
            dataBuf,
            8
        )

        return numberBuf[0]
    end

    return ffi.string(
        dataBuf,
        dataSize
    )
end


-- ============================================================
-- Read value from open key
-- ============================================================

local function read_handle(
    handle,
    valueName
)
    local wideName =
        value_name_wide(valueName)

    if valueName ~= nil
        and valueName ~= ""
        and wideName == nil
    then
        return nil,
            "value name is not valid UTF-8"
    end

    local valueType =
        ffi.new("uint32_t[1]")

    local dataSize =
        ffi.new("uint32_t[1]")

    local flags =
        bit.bor(
            RRF_RT_ANY,
            RRF_NOEXPAND
        )

    local statusCode =
        advapi32.RegGetValueW(
            handle,
            nil,
            wideName,
            flags,
            valueType,
            nil,
            dataSize
        )

    if statusCode ~= ERROR_SUCCESS then
        return nil,
            status_error(
                "RegGetValueW failed",
                statusCode
            ),
            statusCode
    end

    local bufferSize =
        tonumber(dataSize[0])
        + 4

    if bufferSize < 4 then
        bufferSize = 4
    end

    local dataBuf =
        ffi.new(
            "uint8_t[?]",
            bufferSize
        )

    dataSize[0] = bufferSize

    statusCode =
        advapi32.RegGetValueW(
            handle,
            nil,
            wideName,
            flags,
            valueType,
            dataBuf,
            dataSize
        )

    if statusCode ~= ERROR_SUCCESS then
        return nil,
            status_error(
                "RegGetValueW failed",
                statusCode
            ),
            statusCode
    end

    local typeNumber =
        tonumber(valueType[0])

    local value,
    decodeErr =
        decode_value(
            dataBuf,
            tonumber(dataSize[0]),
            typeNumber
        )

    if value == nil
        and decodeErr
    then
        return nil, decodeErr
    end

    return value,
        registry.typeName(typeNumber),
        typeNumber
end


-- ============================================================
-- Read
-- ============================================================

function registry.read(
    path,
    valueName,
    view
)
    local handle,
    mustClose,
    openErr,
    statusCode =
        open_key(
            path,
            KEY_QUERY_VALUE,
            view
        )

    if not handle then
        if statusCode == 2 or statusCode == 3 then return nil end
        return nil,
            openErr,
            statusCode
    end

    local value,
    valueType,
    typeNumber,
    readStatus =
        read_handle(
            handle,
            valueName
        )

    close_key(
        handle,
        mustClose
    )

    if value == nil and (typeNumber == 2 or typeNumber == 3) then return nil end

    if value == nil
        and valueType
    then
        return nil,
            valueType,
            typeNumber
    end

    return value,
        valueType,
        typeNumber,
        readStatus
end

-- ============================================================
-- Resolve registry type
-- ============================================================

local function resolve_type(
    valueType,
    value
)
    if valueType == nil then
        if type(value) == "string" then
            return REG_SZ
        end

        if type(value) == "table" then
            return REG_MULTI_SZ
        end

        if type(value) == "number" then
            return REG_DWORD
        end

        if type(value) == "cdata" then
            return REG_QWORD
        end

        return nil
    end

    if type(valueType) == "number" then
        return valueType
    end

    local name =
        tostring(valueType):upper()

    local names = {
        REG_NONE = REG_NONE,
        NONE = REG_NONE,

        REG_SZ = REG_SZ,
        SZ = REG_SZ,
        STRING = REG_SZ,

        REG_EXPAND_SZ = REG_EXPAND_SZ,
        EXPAND_SZ = REG_EXPAND_SZ,

        REG_BINARY = REG_BINARY,
        BINARY = REG_BINARY,

        REG_DWORD = REG_DWORD,
        DWORD = REG_DWORD,

        REG_MULTI_SZ = REG_MULTI_SZ,
        MULTI_SZ = REG_MULTI_SZ,

        REG_QWORD = REG_QWORD,
        QWORD = REG_QWORD
    }

    return names[name]
end


-- ============================================================
-- Encode registry data
-- ============================================================

local function encode_value(
    value,
    valueType
)
    if valueType == REG_SZ
        or valueType == REG_EXPAND_SZ
    then
        if value == nil then
            value = ""
        end

        value = tostring(value)

        if value:find(
                "\0",
                1,
                true
            ) then
            return nil, nil,
                "string contains NUL character"
        end

        local wideBuf,
        wideLength =
            utf8_to_wide(value)

        if wideBuf == nil then
            return nil, nil,
                "string is not valid UTF-8"
        end

        return ffi.cast(
                "uint8_t *",
                wideBuf
            ),
            (wideLength + 1) * 2,
            wideBuf
    end

    if valueType == REG_MULTI_SZ then
        if type(value) ~= "table" then
            return nil, nil,
                "REG_MULTI_SZ requires a table"
        end

        local parts = {}

        for index = 1, #value do
            local text =
                tostring(value[index])

            if text == "" then
                return nil, nil, "REG_MULTI_SZ items must not be empty"
            end

            if text:find(
                    "\0",
                    1,
                    true
                ) then
                return nil, nil,
                    "REG_MULTI_SZ item contains NUL character"
            end

            parts[#parts + 1] =
                text
        end

        local combined

        if #parts == 0 then
            combined = "\0\0"
        else
            combined =
                table.concat(
                    parts,
                    "\0"
                )
                .. "\0\0"
        end

        local wideBuf,
        wideLength =
            utf8_to_wide(
                combined,
                true
            )

        if wideBuf == nil then
            return nil, nil,
                "REG_MULTI_SZ contains invalid UTF-8"
        end

        return ffi.cast(
                "uint8_t *",
                wideBuf
            ),
            wideLength * 2,
            wideBuf
    end

    if valueType == REG_DWORD then
        local numberValue =
            tonumber(value)

        if numberValue == nil
            or numberValue < 0
            or numberValue > 4294967295
            or numberValue ~= math.floor(numberValue)
        then
            return nil, nil,
                "invalid REG_DWORD value"
        end

        local numberBuf =
            ffi.new(
                "uint32_t[1]",
                numberValue
            )

        return ffi.cast(
                "uint8_t *",
                numberBuf
            ),
            4,
            numberBuf
    end

    if valueType == REG_QWORD then
        local qwordValue,
        qwordErr =
            registry.qword(value)

        if qwordValue == nil then
            return nil, nil,
                qwordErr
        end

        local numberBuf =
            ffi.new(
                "uint64_t[1]",
                qwordValue
            )

        return ffi.cast(
                "uint8_t *",
                numberBuf
            ),
            8,
            numberBuf
    end

    if valueType == REG_BINARY
        or valueType == REG_NONE
    then
        if type(value) ~= "string" then
            return nil, nil,
                "binary registry data must be a Lua string"
        end

        if #value == 0 then
            return nil, 0, nil
        end

        local binaryBuf =
            ffi.new(
                "uint8_t[?]",
                #value
            )

        ffi.copy(
            binaryBuf,
            value,
            #value
        )

        return binaryBuf,
            #value,
            binaryBuf
    end

    return nil, nil,
        "unsupported registry value type"
end


-- ============================================================
-- Write
-- ============================================================

function registry.write(
    path,
    valueName,
    value,
    valueType,
    view
)
    local typeNumber =
        resolve_type(
            valueType,
            value
        )

    if typeNumber == nil then
        return nil,
            "unknown registry value type"
    end

    local handle,
    mustClose,
    disposition,
    createErr,
    createStatus =
        create_key_internal(
            path,
            view
        )

    if not handle then
        return nil,
            createErr,
            createStatus
    end

    local wideName =
        value_name_wide(valueName)

    if valueName ~= nil
        and valueName ~= ""
        and wideName == nil
    then
        close_key(
            handle,
            mustClose
        )

        return nil,
            "value name is not valid UTF-8"
    end

    local dataPtr,
    dataSize,
    keepAlive,
    encodeErr =
        encode_value(
            value,
            typeNumber
        )

    if dataSize == nil then
        close_key(
            handle,
            mustClose
        )

        return nil, keepAlive -- encode_value returns its error in slot three
    end

    local statusCode =
        advapi32.RegSetValueExW(
            handle,
            wideName,
            0,
            typeNumber,
            dataPtr,
            dataSize
        )

    keepAlive = keepAlive

    close_key(
        handle,
        mustClose
    )

    if statusCode ~= ERROR_SUCCESS then
        return nil,
            status_error(
                "RegSetValueExW failed",
                statusCode
            ),
            statusCode
    end

    return true,
        disposition == REG_CREATED_NEW_KEY
end

-- ============================================================
-- Create key
-- ============================================================

function registry.createKey(
    path,
    view
)
    local handle,
    mustClose,
    disposition,
    createErr,
    statusCode =
        create_key_internal(
            path,
            view
        )

    if not handle then
        return nil,
            createErr,
            statusCode
    end

    close_key(
        handle,
        mustClose
    )

    return true,
        disposition == REG_CREATED_NEW_KEY
end

-- ============================================================
-- Key exists
-- ============================================================

function registry.keyExists(
    path,
    view
)
    local handle,
    mustClose,
    openErr,
    statusCode =
        open_key(
            path,
            KEY_READ,
            view
        )

    if handle then
        close_key(
            handle,
            mustClose
        )

        return true
    end

    if statusCode == ERROR_FILE_NOT_FOUND
        or statusCode == ERROR_PATH_NOT_FOUND
    then
        return false
    end

    return nil, openErr
end

-- ============================================================
-- Value exists
-- ============================================================

function registry.valueExists(
    path,
    valueName,
    view
)
    local handle,
    mustClose,
    openErr,
    openStatus =
        open_key(
            path,
            KEY_QUERY_VALUE,
            view
        )

    if not handle then
        if openStatus == ERROR_FILE_NOT_FOUND
            or openStatus == ERROR_PATH_NOT_FOUND
        then
            return false
        end

        return nil, openErr
    end

    local wideName =
        value_name_wide(valueName)

    if valueName ~= nil
        and valueName ~= ""
        and wideName == nil
    then
        close_key(
            handle,
            mustClose
        )

        return nil,
            "value name is not valid UTF-8"
    end

    local valueType =
        ffi.new("uint32_t[1]")

    local dataSize =
        ffi.new("uint32_t[1]")

    local statusCode =
        advapi32.RegGetValueW(
            handle,
            nil,
            wideName,
            bit.bor(
                RRF_RT_ANY,
                RRF_NOEXPAND
            ),
            valueType,
            nil,
            dataSize
        )

    close_key(
        handle,
        mustClose
    )

    if statusCode == ERROR_SUCCESS then
        return true
    end

    if statusCode == ERROR_FILE_NOT_FOUND
        or statusCode == ERROR_PATH_NOT_FOUND
    then
        return false
    end

    return nil,
        status_error(
            "RegGetValueW failed",
            statusCode
        )
end

-- ============================================================
-- Delete value
-- ============================================================

function registry.deleteValue(
    path,
    valueName,
    view
)
    local handle,
    mustClose,
    openErr,
    openStatus =
        open_key(
            path,
            KEY_SET_VALUE,
            view
        )

    if not handle then
        return nil,
            openErr,
            openStatus
    end

    local wideName =
        value_name_wide(valueName)

    if valueName ~= nil
        and valueName ~= ""
        and wideName == nil
    then
        close_key(
            handle,
            mustClose
        )

        return nil,
            "value name is not valid UTF-8"
    end

    local statusCode =
        advapi32.RegDeleteValueW(
            handle,
            wideName
        )

    close_key(
        handle,
        mustClose
    )

    if statusCode ~= ERROR_SUCCESS then
        return nil,
            status_error(
                "RegDeleteValueW failed",
                statusCode
            ),
            statusCode
    end

    return true
end

-- ============================================================
-- Enum subkeys
-- ============================================================

function registry.enumKeys(
    path,
    view
)
    local handle,
    mustClose,
    openErr,
    openStatus =
        open_key(
            path,
            KEY_ENUMERATE_SUB_KEYS,
            view
        )

    if not handle then
        return nil,
            openErr,
            openStatus
    end

    local result = {}
    local index = 0

    local nameBuf =
        ffi.new(
            "uint16_t[32768]"
        )

    local nameLength =
        ffi.new("uint32_t[1]")

    while true do
        nameLength[0] = 32767

        local statusCode =
            advapi32.RegEnumKeyExW(
                handle,
                index,
                nameBuf,
                nameLength,
                nil,
                nil,
                nil,
                nil
            )

        if statusCode == ERROR_NO_MORE_ITEMS then
            break
        end

        if statusCode ~= ERROR_SUCCESS then
            close_key(
                handle,
                mustClose
            )

            return nil,
                status_error(
                    "RegEnumKeyExW failed",
                    statusCode
                ),
                statusCode
        end

        local name =
            wide_to_utf8(
                nameBuf,
                tonumber(nameLength[0])
            )

        result[#result + 1] =
            name or ""

        index = index + 1
    end

    close_key(
        handle,
        mustClose
    )

    return result
end

-- ============================================================
-- Enum values
-- ============================================================

function registry.enumValues(
    path,
    view
)
    local handle,
    mustClose,
    openErr,
    openStatus =
        open_key(
            path,
            KEY_QUERY_VALUE,
            view
        )

    if not handle then
        return nil,
            openErr,
            openStatus
    end

    local result = {}
    local index = 0

    local nameBuf =
        ffi.new(
            "uint16_t[16384]"
        )

    local nameLength =
        ffi.new("uint32_t[1]")

    local valueType =
        ffi.new("uint32_t[1]")

    while true do
        nameLength[0] = 16384

        local statusCode =
            advapi32.RegEnumValueW(
                handle,
                index,
                nameBuf,
                nameLength,
                nil,
                valueType,
                nil,
                nil
            )

        if statusCode == ERROR_NO_MORE_ITEMS then
            break
        end

        if statusCode ~= ERROR_SUCCESS then
            close_key(
                handle,
                mustClose
            )

            return nil,
                status_error(
                    "RegEnumValueW failed",
                    statusCode
                ),
                statusCode
        end

        local name =
            wide_to_utf8(
                nameBuf,
                tonumber(nameLength[0])
            ) or ""

        local value,
        typeName,
        typeNumber =
            read_handle(
                handle,
                name
            )

        if value == nil and typeName then
            close_key(handle, mustClose)
            return nil, typeName, typeNumber
        end

        result[#result + 1] = {
            name = name,
            value = value,
            type = typeName,
            typeId = typeNumber
        }

        index = index + 1
    end

    close_key(
        handle,
        mustClose
    )

    return result
end

-- ============================================================
-- Delete key
-- ============================================================

function registry.deleteKey(
    path,
    recursive,
    view
)
    local rootHandle,
    subPath,
    pathErr =
        parse_path(path)

    if not rootHandle then
        return nil, pathErr
    end

    if subPath == "" then
        return nil,
            "cannot delete a predefined root key"
    end

    local viewFlag =
        get_view_flag(view)

    if viewFlag == nil then
        return nil,
            "invalid registry view"
    end

    local reversePosition =
        subPath:reverse():find(
            "\\",
            1,
            true
        )

    local parentPath
    local keyName

    if reversePosition then
        local separator =
            #subPath
            - reversePosition
            + 1

        parentPath =
            subPath:sub(
                1,
                separator - 1
            )

        keyName =
            subPath:sub(
                separator + 1
            )
    else
        parentPath = ""
        keyName = subPath
    end

    local access =
        bit.bor(
            KEY_READ,
            KEY_WRITE,
            DELETE_ACCESS
        )

    local parentHandle,
    mustClose,
    openErr,
    openStatus =
        open_subkey(
            rootHandle,
            parentPath,
            access,
            viewFlag
        )

    if not parentHandle then
        return nil,
            openErr,
            openStatus
    end

    local wideName =
        utf8_to_wide(keyName)

    if wideName == nil then
        close_key(
            parentHandle,
            mustClose
        )

        return nil,
            "registry key name is not valid UTF-8"
    end

    if recursive then
        local treeStatus =
            advapi32.RegDeleteTreeW(
                parentHandle,
                wideName
            )

        if treeStatus ~= ERROR_SUCCESS
            and treeStatus ~= ERROR_FILE_NOT_FOUND
        then
            close_key(
                parentHandle,
                mustClose
            )

            return nil,
                status_error(
                    "RegDeleteTreeW failed",
                    treeStatus
                ),
                treeStatus
        end
    end

    local statusCode =
        advapi32.RegDeleteKeyExW(
            parentHandle,
            wideName,
            viewFlag,
            0
        )

    close_key(
        parentHandle,
        mustClose
    )

    if recursive
        and statusCode == ERROR_FILE_NOT_FOUND
    then
        return true
    end

    if statusCode ~= ERROR_SUCCESS then
        return nil,
            status_error(
                "RegDeleteKeyExW failed",
                statusCode
            ),
            statusCode
    end

    return true
end

-- ============================================================
-- Expand REG_EXPAND_SZ style string
-- ============================================================

function registry.expand(text)
    if text == nil then
        return nil,
            "text cannot be nil"
    end

    local sourceWide =
        utf8_to_wide(text)

    if sourceWide == nil then
        return nil,
            "text is not valid UTF-8"
    end

    local required =
        kernel32.ExpandEnvironmentStringsW(
            sourceWide,
            nil,
            0
        )

    if required == 0 then
        return nil,
            "ExpandEnvironmentStringsW failed"
    end

    while true do
        local resultBuf = ffi.new("uint16_t[?]", required)
        local result = kernel32.ExpandEnvironmentStringsW(sourceWide, resultBuf, required)
        if result == 0 then return nil, "ExpandEnvironmentStringsW failed" end
        if result <= required then return wide_to_utf8(resultBuf, result - 1) end
        required = result
    end
end

return registry
