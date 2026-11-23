local ffi = require("ffi")

local M = {}

ffi.cdef[[
typedef unsigned int su_uint_t;
typedef unsigned long su_dword_t;
typedef unsigned short su_wchar_t;
typedef int su_bool_t;
typedef long long su_lparam_t;

int __stdcall MultiByteToWideChar(
    su_uint_t CodePage,
    su_dword_t dwFlags,
    const char *lpMultiByteStr,
    int cbMultiByte,
    su_wchar_t *lpWideCharStr,
    int cchWideChar
);

int __stdcall WideCharToMultiByte(
    su_uint_t CodePage,
    su_dword_t dwFlags,
    const su_wchar_t *lpWideCharStr,
    int cchWideChar,
    char *lpMultiByteStr,
    int cbMultiByte,
    const char *lpDefaultChar,
    su_bool_t *lpUsedDefaultChar
);

int __stdcall LCMapStringEx(
    const su_wchar_t *lpLocaleName,
    su_dword_t dwMapFlags,
    const su_wchar_t *lpSrcStr,
    int cchSrc,
    su_wchar_t *lpDestStr,
    int cchDest,
    void *lpVersionInformation,
    void *lpReserved,
    su_lparam_t sortHandle
);

su_dword_t __stdcall GetLastError(void);

int __stdcall NormalizeString(
    int NormForm,
    const su_wchar_t *lpSrcString,
    int cwSrcLength,
    su_wchar_t *lpDstString,
    int cwDstLength
);
]]

local kernel32 = ffi.load("kernel32")
local normaliz_ok, normaliz = pcall(ffi.load, "normaliz")

local CP_UTF8 = 65001
local MB_ERR_INVALID_CHARS = 0x00000008
local WC_ERR_INVALID_CHARS = 0x00000080
local LCMAP_LOWERCASE = 0x00000100
local LCMAP_UPPERCASE = 0x00000200
local ERROR_INSUFFICIENT_BUFFER = 122

local NORMALIZATION_FORMS = {
    NFC = 0x1,
    NFD = 0x2,
    NFKC = 0x5,
    NFKD = 0x6
}

local invariant_locale = ffi.new("su_wchar_t[1]", 0)

local function AssertString(value, arg_name)
    if type(value) ~= "string" then
        error((arg_name or "value") .. " должен быть строкой", 3)
    end
end

local function IsContinuation(value)
    return value ~= nil and value >= 0x80 and value <= 0xBF
end

local function DecodeAt(text, pos)
    local a = text:byte(pos)

    if a == nil then
        return nil, pos, "неожиданный конец строки"
    end

    if a <= 0x7F then
        return a, pos + 1
    end

    local b, c, d = text:byte(pos + 1, pos + 3)

    if a >= 0xC2 and a <= 0xDF and IsContinuation(b) then
        return (a - 0xC0) * 0x40 + (b - 0x80), pos + 2
    end

    if a == 0xE0 and b ~= nil and b >= 0xA0 and b <= 0xBF and IsContinuation(c) then
        return (a - 0xE0) * 0x1000 + (b - 0x80) * 0x40 + (c - 0x80), pos + 3
    end

    if a >= 0xE1 and a <= 0xEC and IsContinuation(b) and IsContinuation(c) then
        return (a - 0xE0) * 0x1000 + (b - 0x80) * 0x40 + (c - 0x80), pos + 3
    end

    if a == 0xED and b ~= nil and b >= 0x80 and b <= 0x9F and IsContinuation(c) then
        return (a - 0xE0) * 0x1000 + (b - 0x80) * 0x40 + (c - 0x80), pos + 3
    end

    if a >= 0xEE and a <= 0xEF and IsContinuation(b) and IsContinuation(c) then
        return (a - 0xE0) * 0x1000 + (b - 0x80) * 0x40 + (c - 0x80), pos + 3
    end

    if a == 0xF0 and b ~= nil and b >= 0x90 and b <= 0xBF and IsContinuation(c) and IsContinuation(d) then
        return (a - 0xF0) * 0x40000 + (b - 0x80) * 0x1000 + (c - 0x80) * 0x40 + (d - 0x80), pos + 4
    end

    if a >= 0xF1 and a <= 0xF3 and IsContinuation(b) and IsContinuation(c) and IsContinuation(d) then
        return (a - 0xF0) * 0x40000 + (b - 0x80) * 0x1000 + (c - 0x80) * 0x40 + (d - 0x80), pos + 4
    end

    if a == 0xF4 and b ~= nil and b >= 0x80 and b <= 0x8F and IsContinuation(c) and IsContinuation(d) then
        return (a - 0xF0) * 0x40000 + (b - 0x80) * 0x1000 + (c - 0x80) * 0x40 + (d - 0x80), pos + 4
    end

    return nil, pos, "некорректный UTF-8 в байте " .. pos
end

local function IsAscii(text)
    for i = 1, #text do
        if text:byte(i) >= 0x80 then return false, i end
    end
    return true
end

local function ValidateUtf8(text)
    local ascii, pos = IsAscii(text)
    if ascii then return true end
    -- The prefix before pos is already known to be valid ASCII.

    while pos <= #text do
        local _, next_pos, err = DecodeAt(text, pos)
        if err then
            return false, pos, err
        end
        pos = next_pos
    end

    return true
end

local function RequireUtf8(text, arg_name)
    AssertString(text, arg_name)

    local ok, _, err = ValidateUtf8(text)
    if not ok then
        error((arg_name or "string") .. ": " .. err, 3)
    end
end

local function BuildOffsets(text)
    AssertString(text, "text")
    local offsets = {}
    local pos = 1
    local count = 0

    while pos <= #text do
        local codepoint, next_pos, err = DecodeAt(text, pos)
        if err then
            error(err, 3)
        end

        count = count + 1
        offsets[count] = pos
        pos = next_pos
    end

    offsets[count + 1] = #text + 1
    return offsets, count
end

-- ASCII needs neither decoding nor an offset table. Other text is validated
-- while building just the offsets needed by character-indexed operations.
local function IndexText(text)
    AssertString(text, "text")
    if IsAscii(text) then
        return nil, #text
    end
    local offsets, length = BuildOffsets(text)
    return offsets, length
end

local function BytePosition(offsets, index)
    return offsets and offsets[index] or index
end

local function CharPosition(offsets, length, pos)
    if not offsets then
        return pos
    end
    local lo, hi = 1, length + 1
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local value = offsets[mid]
        if value == pos then return mid end
        if value < pos then lo = mid + 1 else hi = mid - 1 end
    end
    return nil
end

-- The caller has validated the whole text and bounded index to 1..length+1.
-- Convert only the requested position instead of allocating all offsets.
local function IndexedByte(text, length, index, start_index, start_pos)
    if length == #text then return index end
    local pos = start_pos or 1
    for _ = (start_index or 1) + 1, index do
        local byte = text:byte(pos)
        if byte < 0x80 then pos = pos + 1
        elseif byte < 0xE0 then pos = pos + 2
        elseif byte < 0xF0 then pos = pos + 3
        else pos = pos + 4 end
    end
    return pos
end

-- The text is validated and both indices are bounded; first <= after.
local function IndexedRange(text, length, first, after)
    local first_byte = IndexedByte(text, length, first)
    return first_byte, IndexedByte(text, length, after, first, first_byte)
end

local function NormalizeIndex(index, length, default_value)
    if index == nil then
        index = default_value
    end

    if type(index) ~= "number" or (index ~= math.floor(index) or index == math.huge or index == -math.huge) then
        error("индекс должен быть целым числом", 3)
    end

    if index < 0 then
        index = length + index + 1
    end

    return index
end

local function NormalizeSearchIndex(index, length)
    index = NormalizeIndex(index, length, 1)

    if index < 1 then
        return 1
    end

    if index > length + 1 then
        return length + 1
    end

    return index
end

local errors = require("_errors")
local function Utf8ToWide(text)
    if text == "" then
        return ffi.new("su_wchar_t[1]", 0), 0
    end

    if #text > 2147483647 then
        return nil, nil, "Строка слишком длинная для преобразования UTF-8"
    end

    local needed = kernel32.MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, #text, nil, 0)
    if needed == 0 then
        local _, message, code = errors.Win32("MultiByteToWideChar")
        return nil, nil, message, code
    end

    local wide = ffi.new("su_wchar_t[?]", needed)
    local written = kernel32.MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, #text, wide, needed)
    if written == 0 then
        local _, message, code = errors.Win32("MultiByteToWideChar")
        return nil, nil, message, code
    end

    return wide, written
end

local function WideToUtf8(wide, wide_len)
    if wide_len == 0 then
        return ""
    end

    local needed = kernel32.WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, wide_len, nil, 0, nil, nil)
    if needed == 0 then
        return errors.Win32("WideCharToMultiByte")
    end

    local bytes = ffi.new("char[?]", needed)
    local written = kernel32.WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, wide_len, bytes, needed, nil, nil)
    if written == 0 then
        return errors.Win32("WideCharToMultiByte")
    end

    return ffi.string(bytes, written)
end

local function MapCase(text, flags)
    if type(text) ~= "string" then return nil, "Требуется строка UTF-8" end

    if text == "" then
        return ""
    end

    local wide, wide_len, err, code = Utf8ToWide(text)
    if not wide then
        return nil, err, code
    end

    local needed = kernel32.LCMapStringEx(invariant_locale, flags, wide, wide_len, nil, 0, nil, nil, 0)
    if needed == 0 then
        return errors.Win32("LCMapStringEx")
    end

    local mapped = ffi.new("su_wchar_t[?]", needed)
    local written = kernel32.LCMapStringEx(invariant_locale, flags, wide, wide_len, mapped, needed, nil, nil, 0)
    if written == 0 then
        return errors.Win32("LCMapStringEx")
    end

    return WideToUtf8(mapped, written)
end

local function EncodeCodepoint(codepoint)
    if type(codepoint) ~= "number" or codepoint ~= math.floor(codepoint) then
        error("код символа должен быть целым числом", 3)
    end

    if codepoint < 0 or codepoint > 0x10FFFF or (codepoint >= 0xD800 and codepoint <= 0xDFFF) then
        error("недопустимый код Unicode", 3)
    end

    if codepoint <= 0x7F then
        return string.char(codepoint)
    end

    if codepoint <= 0x7FF then
        local b1 = 0xC0 + math.floor(codepoint / 0x40)
        local b2 = 0x80 + (codepoint % 0x40)
        return string.char(b1, b2)
    end

    if codepoint <= 0xFFFF then
        local b1 = 0xE0 + math.floor(codepoint / 0x1000)
        local b2 = 0x80 + (math.floor(codepoint / 0x40) % 0x40)
        local b3 = 0x80 + (codepoint % 0x40)
        return string.char(b1, b2, b3)
    end

    local b1 = 0xF0 + math.floor(codepoint / 0x40000)
    local b2 = 0x80 + (math.floor(codepoint / 0x1000) % 0x40)
    local b3 = 0x80 + (math.floor(codepoint / 0x40) % 0x40)
    local b4 = 0x80 + (codepoint % 0x40)
    return string.char(b1, b2, b3, b4)
end

local function IsUnicodeSpace(codepoint)
    if codepoint >= 0x09 and codepoint <= 0x0D then
        return true
    end

    return codepoint == 0x20
        or codepoint == 0x85
        or codepoint == 0xA0
        or codepoint == 0x1680
        or (codepoint >= 0x2000 and codepoint <= 0x200A)
        or codepoint == 0x2028
        or codepoint == 0x2029
        or codepoint == 0x202F
        or codepoint == 0x205F
        or codepoint == 0x3000
end

local function RepeatToLength(pad, pad_len, count)
    if count <= 0 then
        return ""
    end

    local full = math.floor(count / pad_len)
    local rest = count % pad_len
    return string.rep(pad, full) .. pad:sub(1, IndexedByte(pad, pad_len, rest + 1) - 1)
end

function M.IsValidUtf8(text)
    AssertString(text, "text")
    return ValidateUtf8(text)
end

function M.Len(text)
    AssertString(text, "text")
    local ascii, pos = IsAscii(text)
    if ascii then return #text end

    local count = pos - 1

    while pos <= #text do
        local _, next_pos, err = DecodeAt(text, pos)
        if err then error("text: " .. err, 2) end
        count = count + 1
        pos = next_pos
    end

    return count
end

function M.Sub(text, first_index, last_index)
    AssertString(text, "text")
    -- Positive indices can be recorded during validation without allocating
    -- a table. Negative indices are resolved after the length is known.
    local first = NormalizeIndex(first_index, 0, 1)
    local last = NormalizeIndex(last_index, 0, -1)
    if IsAscii(text) then
        first = NormalizeIndex(first_index, #text, 1)
        last = NormalizeIndex(last_index, #text, -1)
        if first < 1 then first = 1 end
        if last > #text then last = #text end
        if first > #text or last < 1 or first > last then return "" end
        return text:sub(first, last)
    end
    local pos, length = 1, 0
    local first_byte, after_byte
    while pos <= #text do
        length = length + 1
        if length == first then first_byte = pos end
        if length == last + 1 then after_byte = pos end
        local _, next_pos, err = DecodeAt(text, pos)
        if err then error("text: " .. err, 2) end
        pos = next_pos
    end
    first = NormalizeIndex(first_index, length, 1)
    last = NormalizeIndex(last_index, length, -1)

    if first < 1 then
        first = 1
    end

    if last > length then
        last = length
    end

    if first > length or last < 1 or first > last then
        return ""
    end

    if first == 1 then first_byte = 1 end
    if last == length then after_byte = #text + 1 end
    if not first_byte or not after_byte then
        pos = 1
        for index = 1, last + 1 do
            if index == first then first_byte = pos end
            if index == last + 1 then after_byte = pos; break end
            local _, next_pos = DecodeAt(text, pos)
            pos = next_pos
        end
    end
    return text:sub(first_byte, after_byte - 1)
end

function M.Reverse(text)
    local offsets, length = IndexText(text)
    if not offsets then return text:reverse() end
    local result = {}

    for index = length, 1, -1 do
        result[#result + 1] = text:sub(offsets[index], offsets[index + 1] - 1)
    end

    return table.concat(result)
end

function M.CodePoint(text, first_index, last_index)
    AssertString(text, "text")
    local first = NormalizeIndex(first_index, 0, 1)
    local last = NormalizeIndex(last_index, 0, first)
    -- Only negative indices require the total length before collecting values.
    if (first_index and first_index < 0) or (last_index and last_index < 0) then
        local length = M.Len(text)
        first = NormalizeIndex(first_index, length, 1)
        last = NormalizeIndex(last_index, length, first)
    end
    if first < 1 then first = 1 end
    local scalar = first == last
    local values = not scalar and {} or nil
    local value, count
    local pos, index = 1, 0
    count = 0
    -- Continue to the end even after finding the result: validate all UTF-8.
    while pos <= #text do
        local codepoint, next_pos, err = DecodeAt(text, pos)
        if err then error(err, 3) end
        index = index + 1
        if index >= first and index <= last then
            count = count + 1
            if scalar then value = codepoint else values[count] = codepoint end
        end
        pos = next_pos
    end
    if count == 0 then return nil end
    if scalar then return value end
    return unpack(values, 1, count)
end

function M.Char(...)
    local count = select("#", ...)
    local result = {}

    for index = 1, count do
        result[index] = EncodeCodepoint(select(index, ...))
    end

    return table.concat(result)
end

function M.Chars(text)
    RequireUtf8(text, "text")

    local pos = 1

    return function()
        if pos > #text then
            return nil
        end

        local current = pos
        local _, next_pos = DecodeAt(text, pos)
        pos = next_pos
        return text:sub(current, next_pos - 1)
    end
end

function M.CodePoints(text)
    RequireUtf8(text, "text")

    local pos = 1
    local index = 0

    return function()
        if pos > #text then
            return nil
        end

        local codepoint, next_pos = DecodeAt(text, pos)
        index = index + 1
        pos = next_pos
        return index, codepoint
    end
end

function M.Lower(text)
    return MapCase(text, LCMAP_LOWERCASE)
end

function M.Upper(text)
    return MapCase(text, LCMAP_UPPERCASE)
end

function M.Capitalize(text)
    local length = M.Len(text)

    if text == "" then
        return ""
    end

    local after = IndexedByte(text, length, 2)
    local first = text:sub(1, after - 1)
    local rest = text:sub(after)
    local mapped, err, code = M.Upper(first)

    if not mapped then
        return nil, err, code
    end

    return mapped .. rest
end

function M.Normalize(text, form)
    if type(text) ~= "string" then return nil, "Требуется строка UTF-8" end

    form = form == nil and "NFC" or form
    if type(form) ~= "string" then return nil, "Форма нормализации должна быть строкой" end
    form = string.upper(form)

    local norm_form = NORMALIZATION_FORMS[form]
    if not norm_form then
        return nil, "Допустимые формы нормализации: NFC, NFD, NFKC и NFKD"
    end

    if not normaliz_ok then
        return nil, "Не удалось загрузить Normaliz.dll: " .. tostring(normaliz)
    end

    if text == "" then
        return ""
    end

    local wide, wide_len, err, code = Utf8ToWide(text)
    if not wide then return nil, err, code end

    local needed = normaliz.NormalizeString(norm_form, wide, wide_len, nil, 0)
    if needed <= 0 then
        return errors.Win32("NormalizeString")
    end

    for _ = 1, 4 do
        local normalized = ffi.new("su_wchar_t[?]", needed)
        local written = normaliz.NormalizeString(norm_form, wide, wide_len, normalized, needed)

        if written > 0 then
            return WideToUtf8(normalized, written)
        end

        local win_error = tonumber(kernel32.GetLastError())
        if win_error ~= ERROR_INSUFFICIENT_BUFFER then
            return errors.Win32("NormalizeString", win_error)
        end

        if written < 0 then
            needed = -written
        else
            needed = needed * 2
        end
    end

    return errors.Win32("NormalizeString: буфер не вместил результат", ERROR_INSUFFICIENT_BUFFER)
end

-- Unicode 17.0.0 Default Full Case Folding (C + F; non-Turkic).
-- Source: https://www.unicode.org/Public/17.0.0/ucd/CaseFolding.txt
-- Unicode data license: ../UNICODE-LICENSE.txt. No normalization is implied.
local fold_map
local function GetFoldMap()
    if fold_map then return fold_map end
    fold_map = {
        [0x41] = "\097",
        [0x42] = "\098",
        [0x43] = "\099",
        [0x44] = "\100",
        [0x45] = "\101",
        [0x46] = "\102",
        [0x47] = "\103",
        [0x48] = "\104",
        [0x49] = "\105",
        [0x4a] = "\106",
        [0x4b] = "\107",
        [0x4c] = "\108",
        [0x4d] = "\109",
        [0x4e] = "\110",
        [0x4f] = "\111",
        [0x50] = "\112",
        [0x51] = "\113",
        [0x52] = "\114",
        [0x53] = "\115",
        [0x54] = "\116",
        [0x55] = "\117",
        [0x56] = "\118",
        [0x57] = "\119",
        [0x58] = "\120",
        [0x59] = "\121",
        [0x5a] = "\122",
        [0xb5] = "\206\188",
        [0xc0] = "\195\160",
        [0xc1] = "\195\161",
        [0xc2] = "\195\162",
        [0xc3] = "\195\163",
        [0xc4] = "\195\164",
        [0xc5] = "\195\165",
        [0xc6] = "\195\166",
        [0xc7] = "\195\167",
        [0xc8] = "\195\168",
        [0xc9] = "\195\169",
        [0xca] = "\195\170",
        [0xcb] = "\195\171",
        [0xcc] = "\195\172",
        [0xcd] = "\195\173",
        [0xce] = "\195\174",
        [0xcf] = "\195\175",
        [0xd0] = "\195\176",
        [0xd1] = "\195\177",
        [0xd2] = "\195\178",
        [0xd3] = "\195\179",
        [0xd4] = "\195\180",
        [0xd5] = "\195\181",
        [0xd6] = "\195\182",
        [0xd8] = "\195\184",
        [0xd9] = "\195\185",
        [0xda] = "\195\186",
        [0xdb] = "\195\187",
        [0xdc] = "\195\188",
        [0xdd] = "\195\189",
        [0xde] = "\195\190",
        [0xdf] = "\115\115",
        [0x100] = "\196\129",
        [0x102] = "\196\131",
        [0x104] = "\196\133",
        [0x106] = "\196\135",
        [0x108] = "\196\137",
        [0x10a] = "\196\139",
        [0x10c] = "\196\141",
        [0x10e] = "\196\143",
        [0x110] = "\196\145",
        [0x112] = "\196\147",
        [0x114] = "\196\149",
        [0x116] = "\196\151",
        [0x118] = "\196\153",
        [0x11a] = "\196\155",
        [0x11c] = "\196\157",
        [0x11e] = "\196\159",
        [0x120] = "\196\161",
        [0x122] = "\196\163",
        [0x124] = "\196\165",
        [0x126] = "\196\167",
        [0x128] = "\196\169",
        [0x12a] = "\196\171",
        [0x12c] = "\196\173",
        [0x12e] = "\196\175",
        [0x130] = "\105\204\135",
        [0x132] = "\196\179",
        [0x134] = "\196\181",
        [0x136] = "\196\183",
        [0x139] = "\196\186",
        [0x13b] = "\196\188",
        [0x13d] = "\196\190",
        [0x13f] = "\197\128",
        [0x141] = "\197\130",
        [0x143] = "\197\132",
        [0x145] = "\197\134",
        [0x147] = "\197\136",
        [0x149] = "\202\188\110",
        [0x14a] = "\197\139",
        [0x14c] = "\197\141",
        [0x14e] = "\197\143",
        [0x150] = "\197\145",
        [0x152] = "\197\147",
        [0x154] = "\197\149",
        [0x156] = "\197\151",
        [0x158] = "\197\153",
        [0x15a] = "\197\155",
        [0x15c] = "\197\157",
        [0x15e] = "\197\159",
        [0x160] = "\197\161",
        [0x162] = "\197\163",
        [0x164] = "\197\165",
        [0x166] = "\197\167",
        [0x168] = "\197\169",
        [0x16a] = "\197\171",
        [0x16c] = "\197\173",
        [0x16e] = "\197\175",
        [0x170] = "\197\177",
        [0x172] = "\197\179",
        [0x174] = "\197\181",
        [0x176] = "\197\183",
        [0x178] = "\195\191",
        [0x179] = "\197\186",
        [0x17b] = "\197\188",
        [0x17d] = "\197\190",
        [0x17f] = "\115",
        [0x181] = "\201\147",
        [0x182] = "\198\131",
        [0x184] = "\198\133",
        [0x186] = "\201\148",
        [0x187] = "\198\136",
        [0x189] = "\201\150",
        [0x18a] = "\201\151",
        [0x18b] = "\198\140",
        [0x18e] = "\199\157",
        [0x18f] = "\201\153",
        [0x190] = "\201\155",
        [0x191] = "\198\146",
        [0x193] = "\201\160",
        [0x194] = "\201\163",
        [0x196] = "\201\169",
        [0x197] = "\201\168",
        [0x198] = "\198\153",
        [0x19c] = "\201\175",
        [0x19d] = "\201\178",
        [0x19f] = "\201\181",
        [0x1a0] = "\198\161",
        [0x1a2] = "\198\163",
        [0x1a4] = "\198\165",
        [0x1a6] = "\202\128",
        [0x1a7] = "\198\168",
        [0x1a9] = "\202\131",
        [0x1ac] = "\198\173",
        [0x1ae] = "\202\136",
        [0x1af] = "\198\176",
        [0x1b1] = "\202\138",
        [0x1b2] = "\202\139",
        [0x1b3] = "\198\180",
        [0x1b5] = "\198\182",
        [0x1b7] = "\202\146",
        [0x1b8] = "\198\185",
        [0x1bc] = "\198\189",
        [0x1c4] = "\199\134",
        [0x1c5] = "\199\134",
        [0x1c7] = "\199\137",
        [0x1c8] = "\199\137",
        [0x1ca] = "\199\140",
        [0x1cb] = "\199\140",
        [0x1cd] = "\199\142",
        [0x1cf] = "\199\144",
        [0x1d1] = "\199\146",
        [0x1d3] = "\199\148",
        [0x1d5] = "\199\150",
        [0x1d7] = "\199\152",
        [0x1d9] = "\199\154",
        [0x1db] = "\199\156",
        [0x1de] = "\199\159",
        [0x1e0] = "\199\161",
        [0x1e2] = "\199\163",
        [0x1e4] = "\199\165",
        [0x1e6] = "\199\167",
        [0x1e8] = "\199\169",
        [0x1ea] = "\199\171",
        [0x1ec] = "\199\173",
        [0x1ee] = "\199\175",
        [0x1f0] = "\106\204\140",
        [0x1f1] = "\199\179",
        [0x1f2] = "\199\179",
        [0x1f4] = "\199\181",
        [0x1f6] = "\198\149",
        [0x1f7] = "\198\191",
        [0x1f8] = "\199\185",
        [0x1fa] = "\199\187",
        [0x1fc] = "\199\189",
        [0x1fe] = "\199\191",
        [0x200] = "\200\129",
        [0x202] = "\200\131",
        [0x204] = "\200\133",
        [0x206] = "\200\135",
        [0x208] = "\200\137",
        [0x20a] = "\200\139",
        [0x20c] = "\200\141",
        [0x20e] = "\200\143",
        [0x210] = "\200\145",
        [0x212] = "\200\147",
        [0x214] = "\200\149",
        [0x216] = "\200\151",
        [0x218] = "\200\153",
        [0x21a] = "\200\155",
        [0x21c] = "\200\157",
        [0x21e] = "\200\159",
        [0x220] = "\198\158",
        [0x222] = "\200\163",
        [0x224] = "\200\165",
        [0x226] = "\200\167",
        [0x228] = "\200\169",
        [0x22a] = "\200\171",
        [0x22c] = "\200\173",
        [0x22e] = "\200\175",
        [0x230] = "\200\177",
        [0x232] = "\200\179",
        [0x23a] = "\226\177\165",
        [0x23b] = "\200\188",
        [0x23d] = "\198\154",
        [0x23e] = "\226\177\166",
        [0x241] = "\201\130",
        [0x243] = "\198\128",
        [0x244] = "\202\137",
        [0x245] = "\202\140",
        [0x246] = "\201\135",
        [0x248] = "\201\137",
        [0x24a] = "\201\139",
        [0x24c] = "\201\141",
        [0x24e] = "\201\143",
        [0x345] = "\206\185",
        [0x370] = "\205\177",
        [0x372] = "\205\179",
        [0x376] = "\205\183",
        [0x37f] = "\207\179",
        [0x386] = "\206\172",
        [0x388] = "\206\173",
        [0x389] = "\206\174",
        [0x38a] = "\206\175",
        [0x38c] = "\207\140",
        [0x38e] = "\207\141",
        [0x38f] = "\207\142",
        [0x390] = "\206\185\204\136\204\129",
        [0x391] = "\206\177",
        [0x392] = "\206\178",
        [0x393] = "\206\179",
        [0x394] = "\206\180",
        [0x395] = "\206\181",
        [0x396] = "\206\182",
        [0x397] = "\206\183",
        [0x398] = "\206\184",
        [0x399] = "\206\185",
        [0x39a] = "\206\186",
        [0x39b] = "\206\187",
        [0x39c] = "\206\188",
        [0x39d] = "\206\189",
        [0x39e] = "\206\190",
        [0x39f] = "\206\191",
        [0x3a0] = "\207\128",
        [0x3a1] = "\207\129",
        [0x3a3] = "\207\131",
        [0x3a4] = "\207\132",
        [0x3a5] = "\207\133",
        [0x3a6] = "\207\134",
        [0x3a7] = "\207\135",
        [0x3a8] = "\207\136",
        [0x3a9] = "\207\137",
        [0x3aa] = "\207\138",
        [0x3ab] = "\207\139",
        [0x3b0] = "\207\133\204\136\204\129",
        [0x3c2] = "\207\131",
        [0x3cf] = "\207\151",
        [0x3d0] = "\206\178",
        [0x3d1] = "\206\184",
        [0x3d5] = "\207\134",
        [0x3d6] = "\207\128",
        [0x3d8] = "\207\153",
        [0x3da] = "\207\155",
        [0x3dc] = "\207\157",
        [0x3de] = "\207\159",
        [0x3e0] = "\207\161",
        [0x3e2] = "\207\163",
        [0x3e4] = "\207\165",
        [0x3e6] = "\207\167",
        [0x3e8] = "\207\169",
        [0x3ea] = "\207\171",
        [0x3ec] = "\207\173",
        [0x3ee] = "\207\175",
        [0x3f0] = "\206\186",
        [0x3f1] = "\207\129",
        [0x3f4] = "\206\184",
        [0x3f5] = "\206\181",
        [0x3f7] = "\207\184",
        [0x3f9] = "\207\178",
        [0x3fa] = "\207\187",
        [0x3fd] = "\205\187",
        [0x3fe] = "\205\188",
        [0x3ff] = "\205\189",
        [0x400] = "\209\144",
        [0x401] = "\209\145",
        [0x402] = "\209\146",
        [0x403] = "\209\147",
        [0x404] = "\209\148",
        [0x405] = "\209\149",
        [0x406] = "\209\150",
        [0x407] = "\209\151",
        [0x408] = "\209\152",
        [0x409] = "\209\153",
        [0x40a] = "\209\154",
        [0x40b] = "\209\155",
        [0x40c] = "\209\156",
        [0x40d] = "\209\157",
        [0x40e] = "\209\158",
        [0x40f] = "\209\159",
        [0x410] = "\208\176",
        [0x411] = "\208\177",
        [0x412] = "\208\178",
        [0x413] = "\208\179",
        [0x414] = "\208\180",
        [0x415] = "\208\181",
        [0x416] = "\208\182",
        [0x417] = "\208\183",
        [0x418] = "\208\184",
        [0x419] = "\208\185",
        [0x41a] = "\208\186",
        [0x41b] = "\208\187",
        [0x41c] = "\208\188",
        [0x41d] = "\208\189",
        [0x41e] = "\208\190",
        [0x41f] = "\208\191",
        [0x420] = "\209\128",
        [0x421] = "\209\129",
        [0x422] = "\209\130",
        [0x423] = "\209\131",
        [0x424] = "\209\132",
        [0x425] = "\209\133",
        [0x426] = "\209\134",
        [0x427] = "\209\135",
        [0x428] = "\209\136",
        [0x429] = "\209\137",
        [0x42a] = "\209\138",
        [0x42b] = "\209\139",
        [0x42c] = "\209\140",
        [0x42d] = "\209\141",
        [0x42e] = "\209\142",
        [0x42f] = "\209\143",
        [0x460] = "\209\161",
        [0x462] = "\209\163",
        [0x464] = "\209\165",
        [0x466] = "\209\167",
        [0x468] = "\209\169",
        [0x46a] = "\209\171",
        [0x46c] = "\209\173",
        [0x46e] = "\209\175",
        [0x470] = "\209\177",
        [0x472] = "\209\179",
        [0x474] = "\209\181",
        [0x476] = "\209\183",
        [0x478] = "\209\185",
        [0x47a] = "\209\187",
        [0x47c] = "\209\189",
        [0x47e] = "\209\191",
        [0x480] = "\210\129",
        [0x48a] = "\210\139",
        [0x48c] = "\210\141",
        [0x48e] = "\210\143",
        [0x490] = "\210\145",
        [0x492] = "\210\147",
        [0x494] = "\210\149",
        [0x496] = "\210\151",
        [0x498] = "\210\153",
        [0x49a] = "\210\155",
        [0x49c] = "\210\157",
        [0x49e] = "\210\159",
        [0x4a0] = "\210\161",
        [0x4a2] = "\210\163",
        [0x4a4] = "\210\165",
        [0x4a6] = "\210\167",
        [0x4a8] = "\210\169",
        [0x4aa] = "\210\171",
        [0x4ac] = "\210\173",
        [0x4ae] = "\210\175",
        [0x4b0] = "\210\177",
        [0x4b2] = "\210\179",
        [0x4b4] = "\210\181",
        [0x4b6] = "\210\183",
        [0x4b8] = "\210\185",
        [0x4ba] = "\210\187",
        [0x4bc] = "\210\189",
        [0x4be] = "\210\191",
        [0x4c0] = "\211\143",
        [0x4c1] = "\211\130",
        [0x4c3] = "\211\132",
        [0x4c5] = "\211\134",
        [0x4c7] = "\211\136",
        [0x4c9] = "\211\138",
        [0x4cb] = "\211\140",
        [0x4cd] = "\211\142",
        [0x4d0] = "\211\145",
        [0x4d2] = "\211\147",
        [0x4d4] = "\211\149",
        [0x4d6] = "\211\151",
        [0x4d8] = "\211\153",
        [0x4da] = "\211\155",
        [0x4dc] = "\211\157",
        [0x4de] = "\211\159",
        [0x4e0] = "\211\161",
        [0x4e2] = "\211\163",
        [0x4e4] = "\211\165",
        [0x4e6] = "\211\167",
        [0x4e8] = "\211\169",
        [0x4ea] = "\211\171",
        [0x4ec] = "\211\173",
        [0x4ee] = "\211\175",
        [0x4f0] = "\211\177",
        [0x4f2] = "\211\179",
        [0x4f4] = "\211\181",
        [0x4f6] = "\211\183",
        [0x4f8] = "\211\185",
        [0x4fa] = "\211\187",
        [0x4fc] = "\211\189",
        [0x4fe] = "\211\191",
        [0x500] = "\212\129",
        [0x502] = "\212\131",
        [0x504] = "\212\133",
        [0x506] = "\212\135",
        [0x508] = "\212\137",
        [0x50a] = "\212\139",
        [0x50c] = "\212\141",
        [0x50e] = "\212\143",
        [0x510] = "\212\145",
        [0x512] = "\212\147",
        [0x514] = "\212\149",
        [0x516] = "\212\151",
        [0x518] = "\212\153",
        [0x51a] = "\212\155",
        [0x51c] = "\212\157",
        [0x51e] = "\212\159",
        [0x520] = "\212\161",
        [0x522] = "\212\163",
        [0x524] = "\212\165",
        [0x526] = "\212\167",
        [0x528] = "\212\169",
        [0x52a] = "\212\171",
        [0x52c] = "\212\173",
        [0x52e] = "\212\175",
        [0x531] = "\213\161",
        [0x532] = "\213\162",
        [0x533] = "\213\163",
        [0x534] = "\213\164",
        [0x535] = "\213\165",
        [0x536] = "\213\166",
        [0x537] = "\213\167",
        [0x538] = "\213\168",
        [0x539] = "\213\169",
        [0x53a] = "\213\170",
        [0x53b] = "\213\171",
        [0x53c] = "\213\172",
        [0x53d] = "\213\173",
        [0x53e] = "\213\174",
        [0x53f] = "\213\175",
        [0x540] = "\213\176",
        [0x541] = "\213\177",
        [0x542] = "\213\178",
        [0x543] = "\213\179",
        [0x544] = "\213\180",
        [0x545] = "\213\181",
        [0x546] = "\213\182",
        [0x547] = "\213\183",
        [0x548] = "\213\184",
        [0x549] = "\213\185",
        [0x54a] = "\213\186",
        [0x54b] = "\213\187",
        [0x54c] = "\213\188",
        [0x54d] = "\213\189",
        [0x54e] = "\213\190",
        [0x54f] = "\213\191",
        [0x550] = "\214\128",
        [0x551] = "\214\129",
        [0x552] = "\214\130",
        [0x553] = "\214\131",
        [0x554] = "\214\132",
        [0x555] = "\214\133",
        [0x556] = "\214\134",
        [0x587] = "\213\165\214\130",
        [0x10a0] = "\226\180\128",
        [0x10a1] = "\226\180\129",
        [0x10a2] = "\226\180\130",
        [0x10a3] = "\226\180\131",
        [0x10a4] = "\226\180\132",
        [0x10a5] = "\226\180\133",
        [0x10a6] = "\226\180\134",
        [0x10a7] = "\226\180\135",
        [0x10a8] = "\226\180\136",
        [0x10a9] = "\226\180\137",
        [0x10aa] = "\226\180\138",
        [0x10ab] = "\226\180\139",
        [0x10ac] = "\226\180\140",
        [0x10ad] = "\226\180\141",
        [0x10ae] = "\226\180\142",
        [0x10af] = "\226\180\143",
        [0x10b0] = "\226\180\144",
        [0x10b1] = "\226\180\145",
        [0x10b2] = "\226\180\146",
        [0x10b3] = "\226\180\147",
        [0x10b4] = "\226\180\148",
        [0x10b5] = "\226\180\149",
        [0x10b6] = "\226\180\150",
        [0x10b7] = "\226\180\151",
        [0x10b8] = "\226\180\152",
        [0x10b9] = "\226\180\153",
        [0x10ba] = "\226\180\154",
        [0x10bb] = "\226\180\155",
        [0x10bc] = "\226\180\156",
        [0x10bd] = "\226\180\157",
        [0x10be] = "\226\180\158",
        [0x10bf] = "\226\180\159",
        [0x10c0] = "\226\180\160",
        [0x10c1] = "\226\180\161",
        [0x10c2] = "\226\180\162",
        [0x10c3] = "\226\180\163",
        [0x10c4] = "\226\180\164",
        [0x10c5] = "\226\180\165",
        [0x10c7] = "\226\180\167",
        [0x10cd] = "\226\180\173",
        [0x13f8] = "\225\143\176",
        [0x13f9] = "\225\143\177",
        [0x13fa] = "\225\143\178",
        [0x13fb] = "\225\143\179",
        [0x13fc] = "\225\143\180",
        [0x13fd] = "\225\143\181",
        [0x1c80] = "\208\178",
        [0x1c81] = "\208\180",
        [0x1c82] = "\208\190",
        [0x1c83] = "\209\129",
        [0x1c84] = "\209\130",
        [0x1c85] = "\209\130",
        [0x1c86] = "\209\138",
        [0x1c87] = "\209\163",
        [0x1c88] = "\234\153\139",
        [0x1c89] = "\225\178\138",
        [0x1c90] = "\225\131\144",
        [0x1c91] = "\225\131\145",
        [0x1c92] = "\225\131\146",
        [0x1c93] = "\225\131\147",
        [0x1c94] = "\225\131\148",
        [0x1c95] = "\225\131\149",
        [0x1c96] = "\225\131\150",
        [0x1c97] = "\225\131\151",
        [0x1c98] = "\225\131\152",
        [0x1c99] = "\225\131\153",
        [0x1c9a] = "\225\131\154",
        [0x1c9b] = "\225\131\155",
        [0x1c9c] = "\225\131\156",
        [0x1c9d] = "\225\131\157",
        [0x1c9e] = "\225\131\158",
        [0x1c9f] = "\225\131\159",
        [0x1ca0] = "\225\131\160",
        [0x1ca1] = "\225\131\161",
        [0x1ca2] = "\225\131\162",
        [0x1ca3] = "\225\131\163",
        [0x1ca4] = "\225\131\164",
        [0x1ca5] = "\225\131\165",
        [0x1ca6] = "\225\131\166",
        [0x1ca7] = "\225\131\167",
        [0x1ca8] = "\225\131\168",
        [0x1ca9] = "\225\131\169",
        [0x1caa] = "\225\131\170",
        [0x1cab] = "\225\131\171",
        [0x1cac] = "\225\131\172",
        [0x1cad] = "\225\131\173",
        [0x1cae] = "\225\131\174",
        [0x1caf] = "\225\131\175",
        [0x1cb0] = "\225\131\176",
        [0x1cb1] = "\225\131\177",
        [0x1cb2] = "\225\131\178",
        [0x1cb3] = "\225\131\179",
        [0x1cb4] = "\225\131\180",
        [0x1cb5] = "\225\131\181",
        [0x1cb6] = "\225\131\182",
        [0x1cb7] = "\225\131\183",
        [0x1cb8] = "\225\131\184",
        [0x1cb9] = "\225\131\185",
        [0x1cba] = "\225\131\186",
        [0x1cbd] = "\225\131\189",
        [0x1cbe] = "\225\131\190",
        [0x1cbf] = "\225\131\191",
        [0x1e00] = "\225\184\129",
        [0x1e02] = "\225\184\131",
        [0x1e04] = "\225\184\133",
        [0x1e06] = "\225\184\135",
        [0x1e08] = "\225\184\137",
        [0x1e0a] = "\225\184\139",
        [0x1e0c] = "\225\184\141",
        [0x1e0e] = "\225\184\143",
        [0x1e10] = "\225\184\145",
        [0x1e12] = "\225\184\147",
        [0x1e14] = "\225\184\149",
        [0x1e16] = "\225\184\151",
        [0x1e18] = "\225\184\153",
        [0x1e1a] = "\225\184\155",
        [0x1e1c] = "\225\184\157",
        [0x1e1e] = "\225\184\159",
        [0x1e20] = "\225\184\161",
        [0x1e22] = "\225\184\163",
        [0x1e24] = "\225\184\165",
        [0x1e26] = "\225\184\167",
        [0x1e28] = "\225\184\169",
        [0x1e2a] = "\225\184\171",
        [0x1e2c] = "\225\184\173",
        [0x1e2e] = "\225\184\175",
        [0x1e30] = "\225\184\177",
        [0x1e32] = "\225\184\179",
        [0x1e34] = "\225\184\181",
        [0x1e36] = "\225\184\183",
        [0x1e38] = "\225\184\185",
        [0x1e3a] = "\225\184\187",
        [0x1e3c] = "\225\184\189",
        [0x1e3e] = "\225\184\191",
        [0x1e40] = "\225\185\129",
        [0x1e42] = "\225\185\131",
        [0x1e44] = "\225\185\133",
        [0x1e46] = "\225\185\135",
        [0x1e48] = "\225\185\137",
        [0x1e4a] = "\225\185\139",
        [0x1e4c] = "\225\185\141",
        [0x1e4e] = "\225\185\143",
        [0x1e50] = "\225\185\145",
        [0x1e52] = "\225\185\147",
        [0x1e54] = "\225\185\149",
        [0x1e56] = "\225\185\151",
        [0x1e58] = "\225\185\153",
        [0x1e5a] = "\225\185\155",
        [0x1e5c] = "\225\185\157",
        [0x1e5e] = "\225\185\159",
        [0x1e60] = "\225\185\161",
        [0x1e62] = "\225\185\163",
        [0x1e64] = "\225\185\165",
        [0x1e66] = "\225\185\167",
        [0x1e68] = "\225\185\169",
        [0x1e6a] = "\225\185\171",
        [0x1e6c] = "\225\185\173",
        [0x1e6e] = "\225\185\175",
        [0x1e70] = "\225\185\177",
        [0x1e72] = "\225\185\179",
        [0x1e74] = "\225\185\181",
        [0x1e76] = "\225\185\183",
        [0x1e78] = "\225\185\185",
        [0x1e7a] = "\225\185\187",
        [0x1e7c] = "\225\185\189",
        [0x1e7e] = "\225\185\191",
        [0x1e80] = "\225\186\129",
        [0x1e82] = "\225\186\131",
        [0x1e84] = "\225\186\133",
        [0x1e86] = "\225\186\135",
        [0x1e88] = "\225\186\137",
        [0x1e8a] = "\225\186\139",
        [0x1e8c] = "\225\186\141",
        [0x1e8e] = "\225\186\143",
        [0x1e90] = "\225\186\145",
        [0x1e92] = "\225\186\147",
        [0x1e94] = "\225\186\149",
        [0x1e96] = "\104\204\177",
        [0x1e97] = "\116\204\136",
        [0x1e98] = "\119\204\138",
        [0x1e99] = "\121\204\138",
        [0x1e9a] = "\097\202\190",
        [0x1e9b] = "\225\185\161",
        [0x1e9e] = "\115\115",
        [0x1ea0] = "\225\186\161",
        [0x1ea2] = "\225\186\163",
        [0x1ea4] = "\225\186\165",
        [0x1ea6] = "\225\186\167",
        [0x1ea8] = "\225\186\169",
        [0x1eaa] = "\225\186\171",
        [0x1eac] = "\225\186\173",
        [0x1eae] = "\225\186\175",
        [0x1eb0] = "\225\186\177",
        [0x1eb2] = "\225\186\179",
        [0x1eb4] = "\225\186\181",
        [0x1eb6] = "\225\186\183",
        [0x1eb8] = "\225\186\185",
        [0x1eba] = "\225\186\187",
        [0x1ebc] = "\225\186\189",
        [0x1ebe] = "\225\186\191",
        [0x1ec0] = "\225\187\129",
        [0x1ec2] = "\225\187\131",
        [0x1ec4] = "\225\187\133",
        [0x1ec6] = "\225\187\135",
        [0x1ec8] = "\225\187\137",
        [0x1eca] = "\225\187\139",
        [0x1ecc] = "\225\187\141",
        [0x1ece] = "\225\187\143",
        [0x1ed0] = "\225\187\145",
        [0x1ed2] = "\225\187\147",
        [0x1ed4] = "\225\187\149",
        [0x1ed6] = "\225\187\151",
        [0x1ed8] = "\225\187\153",
        [0x1eda] = "\225\187\155",
        [0x1edc] = "\225\187\157",
        [0x1ede] = "\225\187\159",
        [0x1ee0] = "\225\187\161",
        [0x1ee2] = "\225\187\163",
        [0x1ee4] = "\225\187\165",
        [0x1ee6] = "\225\187\167",
        [0x1ee8] = "\225\187\169",
        [0x1eea] = "\225\187\171",
        [0x1eec] = "\225\187\173",
        [0x1eee] = "\225\187\175",
        [0x1ef0] = "\225\187\177",
        [0x1ef2] = "\225\187\179",
        [0x1ef4] = "\225\187\181",
        [0x1ef6] = "\225\187\183",
        [0x1ef8] = "\225\187\185",
        [0x1efa] = "\225\187\187",
        [0x1efc] = "\225\187\189",
        [0x1efe] = "\225\187\191",
        [0x1f08] = "\225\188\128",
        [0x1f09] = "\225\188\129",
        [0x1f0a] = "\225\188\130",
        [0x1f0b] = "\225\188\131",
        [0x1f0c] = "\225\188\132",
        [0x1f0d] = "\225\188\133",
        [0x1f0e] = "\225\188\134",
        [0x1f0f] = "\225\188\135",
        [0x1f18] = "\225\188\144",
        [0x1f19] = "\225\188\145",
        [0x1f1a] = "\225\188\146",
        [0x1f1b] = "\225\188\147",
        [0x1f1c] = "\225\188\148",
        [0x1f1d] = "\225\188\149",
        [0x1f28] = "\225\188\160",
        [0x1f29] = "\225\188\161",
        [0x1f2a] = "\225\188\162",
        [0x1f2b] = "\225\188\163",
        [0x1f2c] = "\225\188\164",
        [0x1f2d] = "\225\188\165",
        [0x1f2e] = "\225\188\166",
        [0x1f2f] = "\225\188\167",
        [0x1f38] = "\225\188\176",
        [0x1f39] = "\225\188\177",
        [0x1f3a] = "\225\188\178",
        [0x1f3b] = "\225\188\179",
        [0x1f3c] = "\225\188\180",
        [0x1f3d] = "\225\188\181",
        [0x1f3e] = "\225\188\182",
        [0x1f3f] = "\225\188\183",
        [0x1f48] = "\225\189\128",
        [0x1f49] = "\225\189\129",
        [0x1f4a] = "\225\189\130",
        [0x1f4b] = "\225\189\131",
        [0x1f4c] = "\225\189\132",
        [0x1f4d] = "\225\189\133",
        [0x1f50] = "\207\133\204\147",
        [0x1f52] = "\207\133\204\147\204\128",
        [0x1f54] = "\207\133\204\147\204\129",
        [0x1f56] = "\207\133\204\147\205\130",
        [0x1f59] = "\225\189\145",
        [0x1f5b] = "\225\189\147",
        [0x1f5d] = "\225\189\149",
        [0x1f5f] = "\225\189\151",
        [0x1f68] = "\225\189\160",
        [0x1f69] = "\225\189\161",
        [0x1f6a] = "\225\189\162",
        [0x1f6b] = "\225\189\163",
        [0x1f6c] = "\225\189\164",
        [0x1f6d] = "\225\189\165",
        [0x1f6e] = "\225\189\166",
        [0x1f6f] = "\225\189\167",
        [0x1f80] = "\225\188\128\206\185",
        [0x1f81] = "\225\188\129\206\185",
        [0x1f82] = "\225\188\130\206\185",
        [0x1f83] = "\225\188\131\206\185",
        [0x1f84] = "\225\188\132\206\185",
        [0x1f85] = "\225\188\133\206\185",
        [0x1f86] = "\225\188\134\206\185",
        [0x1f87] = "\225\188\135\206\185",
        [0x1f88] = "\225\188\128\206\185",
        [0x1f89] = "\225\188\129\206\185",
        [0x1f8a] = "\225\188\130\206\185",
        [0x1f8b] = "\225\188\131\206\185",
        [0x1f8c] = "\225\188\132\206\185",
        [0x1f8d] = "\225\188\133\206\185",
        [0x1f8e] = "\225\188\134\206\185",
        [0x1f8f] = "\225\188\135\206\185",
        [0x1f90] = "\225\188\160\206\185",
        [0x1f91] = "\225\188\161\206\185",
        [0x1f92] = "\225\188\162\206\185",
        [0x1f93] = "\225\188\163\206\185",
        [0x1f94] = "\225\188\164\206\185",
        [0x1f95] = "\225\188\165\206\185",
        [0x1f96] = "\225\188\166\206\185",
        [0x1f97] = "\225\188\167\206\185",
        [0x1f98] = "\225\188\160\206\185",
        [0x1f99] = "\225\188\161\206\185",
        [0x1f9a] = "\225\188\162\206\185",
        [0x1f9b] = "\225\188\163\206\185",
        [0x1f9c] = "\225\188\164\206\185",
        [0x1f9d] = "\225\188\165\206\185",
        [0x1f9e] = "\225\188\166\206\185",
        [0x1f9f] = "\225\188\167\206\185",
        [0x1fa0] = "\225\189\160\206\185",
        [0x1fa1] = "\225\189\161\206\185",
        [0x1fa2] = "\225\189\162\206\185",
        [0x1fa3] = "\225\189\163\206\185",
        [0x1fa4] = "\225\189\164\206\185",
        [0x1fa5] = "\225\189\165\206\185",
        [0x1fa6] = "\225\189\166\206\185",
        [0x1fa7] = "\225\189\167\206\185",
        [0x1fa8] = "\225\189\160\206\185",
        [0x1fa9] = "\225\189\161\206\185",
        [0x1faa] = "\225\189\162\206\185",
        [0x1fab] = "\225\189\163\206\185",
        [0x1fac] = "\225\189\164\206\185",
        [0x1fad] = "\225\189\165\206\185",
        [0x1fae] = "\225\189\166\206\185",
        [0x1faf] = "\225\189\167\206\185",
        [0x1fb2] = "\225\189\176\206\185",
        [0x1fb3] = "\206\177\206\185",
        [0x1fb4] = "\206\172\206\185",
        [0x1fb6] = "\206\177\205\130",
        [0x1fb7] = "\206\177\205\130\206\185",
        [0x1fb8] = "\225\190\176",
        [0x1fb9] = "\225\190\177",
        [0x1fba] = "\225\189\176",
        [0x1fbb] = "\225\189\177",
        [0x1fbc] = "\206\177\206\185",
        [0x1fbe] = "\206\185",
        [0x1fc2] = "\225\189\180\206\185",
        [0x1fc3] = "\206\183\206\185",
        [0x1fc4] = "\206\174\206\185",
        [0x1fc6] = "\206\183\205\130",
        [0x1fc7] = "\206\183\205\130\206\185",
        [0x1fc8] = "\225\189\178",
        [0x1fc9] = "\225\189\179",
        [0x1fca] = "\225\189\180",
        [0x1fcb] = "\225\189\181",
        [0x1fcc] = "\206\183\206\185",
        [0x1fd2] = "\206\185\204\136\204\128",
        [0x1fd3] = "\206\185\204\136\204\129",
        [0x1fd6] = "\206\185\205\130",
        [0x1fd7] = "\206\185\204\136\205\130",
        [0x1fd8] = "\225\191\144",
        [0x1fd9] = "\225\191\145",
        [0x1fda] = "\225\189\182",
        [0x1fdb] = "\225\189\183",
        [0x1fe2] = "\207\133\204\136\204\128",
        [0x1fe3] = "\207\133\204\136\204\129",
        [0x1fe4] = "\207\129\204\147",
        [0x1fe6] = "\207\133\205\130",
        [0x1fe7] = "\207\133\204\136\205\130",
        [0x1fe8] = "\225\191\160",
        [0x1fe9] = "\225\191\161",
        [0x1fea] = "\225\189\186",
        [0x1feb] = "\225\189\187",
        [0x1fec] = "\225\191\165",
        [0x1ff2] = "\225\189\188\206\185",
        [0x1ff3] = "\207\137\206\185",
        [0x1ff4] = "\207\142\206\185",
        [0x1ff6] = "\207\137\205\130",
        [0x1ff7] = "\207\137\205\130\206\185",
        [0x1ff8] = "\225\189\184",
        [0x1ff9] = "\225\189\185",
        [0x1ffa] = "\225\189\188",
        [0x1ffb] = "\225\189\189",
        [0x1ffc] = "\207\137\206\185",
        [0x2126] = "\207\137",
        [0x212a] = "\107",
        [0x212b] = "\195\165",
        [0x2132] = "\226\133\142",
        [0x2160] = "\226\133\176",
        [0x2161] = "\226\133\177",
        [0x2162] = "\226\133\178",
        [0x2163] = "\226\133\179",
        [0x2164] = "\226\133\180",
        [0x2165] = "\226\133\181",
        [0x2166] = "\226\133\182",
        [0x2167] = "\226\133\183",
        [0x2168] = "\226\133\184",
        [0x2169] = "\226\133\185",
        [0x216a] = "\226\133\186",
        [0x216b] = "\226\133\187",
        [0x216c] = "\226\133\188",
        [0x216d] = "\226\133\189",
        [0x216e] = "\226\133\190",
        [0x216f] = "\226\133\191",
        [0x2183] = "\226\134\132",
        [0x24b6] = "\226\147\144",
        [0x24b7] = "\226\147\145",
        [0x24b8] = "\226\147\146",
        [0x24b9] = "\226\147\147",
        [0x24ba] = "\226\147\148",
        [0x24bb] = "\226\147\149",
        [0x24bc] = "\226\147\150",
        [0x24bd] = "\226\147\151",
        [0x24be] = "\226\147\152",
        [0x24bf] = "\226\147\153",
        [0x24c0] = "\226\147\154",
        [0x24c1] = "\226\147\155",
        [0x24c2] = "\226\147\156",
        [0x24c3] = "\226\147\157",
        [0x24c4] = "\226\147\158",
        [0x24c5] = "\226\147\159",
        [0x24c6] = "\226\147\160",
        [0x24c7] = "\226\147\161",
        [0x24c8] = "\226\147\162",
        [0x24c9] = "\226\147\163",
        [0x24ca] = "\226\147\164",
        [0x24cb] = "\226\147\165",
        [0x24cc] = "\226\147\166",
        [0x24cd] = "\226\147\167",
        [0x24ce] = "\226\147\168",
        [0x24cf] = "\226\147\169",
        [0x2c00] = "\226\176\176",
        [0x2c01] = "\226\176\177",
        [0x2c02] = "\226\176\178",
        [0x2c03] = "\226\176\179",
        [0x2c04] = "\226\176\180",
        [0x2c05] = "\226\176\181",
        [0x2c06] = "\226\176\182",
        [0x2c07] = "\226\176\183",
        [0x2c08] = "\226\176\184",
        [0x2c09] = "\226\176\185",
        [0x2c0a] = "\226\176\186",
        [0x2c0b] = "\226\176\187",
        [0x2c0c] = "\226\176\188",
        [0x2c0d] = "\226\176\189",
        [0x2c0e] = "\226\176\190",
        [0x2c0f] = "\226\176\191",
        [0x2c10] = "\226\177\128",
        [0x2c11] = "\226\177\129",
        [0x2c12] = "\226\177\130",
        [0x2c13] = "\226\177\131",
        [0x2c14] = "\226\177\132",
        [0x2c15] = "\226\177\133",
        [0x2c16] = "\226\177\134",
        [0x2c17] = "\226\177\135",
        [0x2c18] = "\226\177\136",
        [0x2c19] = "\226\177\137",
        [0x2c1a] = "\226\177\138",
        [0x2c1b] = "\226\177\139",
        [0x2c1c] = "\226\177\140",
        [0x2c1d] = "\226\177\141",
        [0x2c1e] = "\226\177\142",
        [0x2c1f] = "\226\177\143",
        [0x2c20] = "\226\177\144",
        [0x2c21] = "\226\177\145",
        [0x2c22] = "\226\177\146",
        [0x2c23] = "\226\177\147",
        [0x2c24] = "\226\177\148",
        [0x2c25] = "\226\177\149",
        [0x2c26] = "\226\177\150",
        [0x2c27] = "\226\177\151",
        [0x2c28] = "\226\177\152",
        [0x2c29] = "\226\177\153",
        [0x2c2a] = "\226\177\154",
        [0x2c2b] = "\226\177\155",
        [0x2c2c] = "\226\177\156",
        [0x2c2d] = "\226\177\157",
        [0x2c2e] = "\226\177\158",
        [0x2c2f] = "\226\177\159",
        [0x2c60] = "\226\177\161",
        [0x2c62] = "\201\171",
        [0x2c63] = "\225\181\189",
        [0x2c64] = "\201\189",
        [0x2c67] = "\226\177\168",
        [0x2c69] = "\226\177\170",
        [0x2c6b] = "\226\177\172",
        [0x2c6d] = "\201\145",
        [0x2c6e] = "\201\177",
        [0x2c6f] = "\201\144",
        [0x2c70] = "\201\146",
        [0x2c72] = "\226\177\179",
        [0x2c75] = "\226\177\182",
        [0x2c7e] = "\200\191",
        [0x2c7f] = "\201\128",
        [0x2c80] = "\226\178\129",
        [0x2c82] = "\226\178\131",
        [0x2c84] = "\226\178\133",
        [0x2c86] = "\226\178\135",
        [0x2c88] = "\226\178\137",
        [0x2c8a] = "\226\178\139",
        [0x2c8c] = "\226\178\141",
        [0x2c8e] = "\226\178\143",
        [0x2c90] = "\226\178\145",
        [0x2c92] = "\226\178\147",
        [0x2c94] = "\226\178\149",
        [0x2c96] = "\226\178\151",
        [0x2c98] = "\226\178\153",
        [0x2c9a] = "\226\178\155",
        [0x2c9c] = "\226\178\157",
        [0x2c9e] = "\226\178\159",
        [0x2ca0] = "\226\178\161",
        [0x2ca2] = "\226\178\163",
        [0x2ca4] = "\226\178\165",
        [0x2ca6] = "\226\178\167",
        [0x2ca8] = "\226\178\169",
        [0x2caa] = "\226\178\171",
        [0x2cac] = "\226\178\173",
        [0x2cae] = "\226\178\175",
        [0x2cb0] = "\226\178\177",
        [0x2cb2] = "\226\178\179",
        [0x2cb4] = "\226\178\181",
        [0x2cb6] = "\226\178\183",
        [0x2cb8] = "\226\178\185",
        [0x2cba] = "\226\178\187",
        [0x2cbc] = "\226\178\189",
        [0x2cbe] = "\226\178\191",
        [0x2cc0] = "\226\179\129",
        [0x2cc2] = "\226\179\131",
        [0x2cc4] = "\226\179\133",
        [0x2cc6] = "\226\179\135",
        [0x2cc8] = "\226\179\137",
        [0x2cca] = "\226\179\139",
        [0x2ccc] = "\226\179\141",
        [0x2cce] = "\226\179\143",
        [0x2cd0] = "\226\179\145",
        [0x2cd2] = "\226\179\147",
        [0x2cd4] = "\226\179\149",
        [0x2cd6] = "\226\179\151",
        [0x2cd8] = "\226\179\153",
        [0x2cda] = "\226\179\155",
        [0x2cdc] = "\226\179\157",
        [0x2cde] = "\226\179\159",
        [0x2ce0] = "\226\179\161",
        [0x2ce2] = "\226\179\163",
        [0x2ceb] = "\226\179\172",
        [0x2ced] = "\226\179\174",
        [0x2cf2] = "\226\179\179",
        [0xa640] = "\234\153\129",
        [0xa642] = "\234\153\131",
        [0xa644] = "\234\153\133",
        [0xa646] = "\234\153\135",
        [0xa648] = "\234\153\137",
        [0xa64a] = "\234\153\139",
        [0xa64c] = "\234\153\141",
        [0xa64e] = "\234\153\143",
        [0xa650] = "\234\153\145",
        [0xa652] = "\234\153\147",
        [0xa654] = "\234\153\149",
        [0xa656] = "\234\153\151",
        [0xa658] = "\234\153\153",
        [0xa65a] = "\234\153\155",
        [0xa65c] = "\234\153\157",
        [0xa65e] = "\234\153\159",
        [0xa660] = "\234\153\161",
        [0xa662] = "\234\153\163",
        [0xa664] = "\234\153\165",
        [0xa666] = "\234\153\167",
        [0xa668] = "\234\153\169",
        [0xa66a] = "\234\153\171",
        [0xa66c] = "\234\153\173",
        [0xa680] = "\234\154\129",
        [0xa682] = "\234\154\131",
        [0xa684] = "\234\154\133",
        [0xa686] = "\234\154\135",
        [0xa688] = "\234\154\137",
        [0xa68a] = "\234\154\139",
        [0xa68c] = "\234\154\141",
        [0xa68e] = "\234\154\143",
        [0xa690] = "\234\154\145",
        [0xa692] = "\234\154\147",
        [0xa694] = "\234\154\149",
        [0xa696] = "\234\154\151",
        [0xa698] = "\234\154\153",
        [0xa69a] = "\234\154\155",
        [0xa722] = "\234\156\163",
        [0xa724] = "\234\156\165",
        [0xa726] = "\234\156\167",
        [0xa728] = "\234\156\169",
        [0xa72a] = "\234\156\171",
        [0xa72c] = "\234\156\173",
        [0xa72e] = "\234\156\175",
        [0xa732] = "\234\156\179",
        [0xa734] = "\234\156\181",
        [0xa736] = "\234\156\183",
        [0xa738] = "\234\156\185",
        [0xa73a] = "\234\156\187",
        [0xa73c] = "\234\156\189",
        [0xa73e] = "\234\156\191",
        [0xa740] = "\234\157\129",
        [0xa742] = "\234\157\131",
        [0xa744] = "\234\157\133",
        [0xa746] = "\234\157\135",
        [0xa748] = "\234\157\137",
        [0xa74a] = "\234\157\139",
        [0xa74c] = "\234\157\141",
        [0xa74e] = "\234\157\143",
        [0xa750] = "\234\157\145",
        [0xa752] = "\234\157\147",
        [0xa754] = "\234\157\149",
        [0xa756] = "\234\157\151",
        [0xa758] = "\234\157\153",
        [0xa75a] = "\234\157\155",
        [0xa75c] = "\234\157\157",
        [0xa75e] = "\234\157\159",
        [0xa760] = "\234\157\161",
        [0xa762] = "\234\157\163",
        [0xa764] = "\234\157\165",
        [0xa766] = "\234\157\167",
        [0xa768] = "\234\157\169",
        [0xa76a] = "\234\157\171",
        [0xa76c] = "\234\157\173",
        [0xa76e] = "\234\157\175",
        [0xa779] = "\234\157\186",
        [0xa77b] = "\234\157\188",
        [0xa77d] = "\225\181\185",
        [0xa77e] = "\234\157\191",
        [0xa780] = "\234\158\129",
        [0xa782] = "\234\158\131",
        [0xa784] = "\234\158\133",
        [0xa786] = "\234\158\135",
        [0xa78b] = "\234\158\140",
        [0xa78d] = "\201\165",
        [0xa790] = "\234\158\145",
        [0xa792] = "\234\158\147",
        [0xa796] = "\234\158\151",
        [0xa798] = "\234\158\153",
        [0xa79a] = "\234\158\155",
        [0xa79c] = "\234\158\157",
        [0xa79e] = "\234\158\159",
        [0xa7a0] = "\234\158\161",
        [0xa7a2] = "\234\158\163",
        [0xa7a4] = "\234\158\165",
        [0xa7a6] = "\234\158\167",
        [0xa7a8] = "\234\158\169",
        [0xa7aa] = "\201\166",
        [0xa7ab] = "\201\156",
        [0xa7ac] = "\201\161",
        [0xa7ad] = "\201\172",
        [0xa7ae] = "\201\170",
        [0xa7b0] = "\202\158",
        [0xa7b1] = "\202\135",
        [0xa7b2] = "\202\157",
        [0xa7b3] = "\234\173\147",
        [0xa7b4] = "\234\158\181",
        [0xa7b6] = "\234\158\183",
        [0xa7b8] = "\234\158\185",
        [0xa7ba] = "\234\158\187",
        [0xa7bc] = "\234\158\189",
        [0xa7be] = "\234\158\191",
        [0xa7c0] = "\234\159\129",
        [0xa7c2] = "\234\159\131",
        [0xa7c4] = "\234\158\148",
        [0xa7c5] = "\202\130",
        [0xa7c6] = "\225\182\142",
        [0xa7c7] = "\234\159\136",
        [0xa7c9] = "\234\159\138",
        [0xa7cb] = "\201\164",
        [0xa7cc] = "\234\159\141",
        [0xa7ce] = "\234\159\143",
        [0xa7d0] = "\234\159\145",
        [0xa7d2] = "\234\159\147",
        [0xa7d4] = "\234\159\149",
        [0xa7d6] = "\234\159\151",
        [0xa7d8] = "\234\159\153",
        [0xa7da] = "\234\159\155",
        [0xa7dc] = "\198\155",
        [0xa7f5] = "\234\159\182",
        [0xab70] = "\225\142\160",
        [0xab71] = "\225\142\161",
        [0xab72] = "\225\142\162",
        [0xab73] = "\225\142\163",
        [0xab74] = "\225\142\164",
        [0xab75] = "\225\142\165",
        [0xab76] = "\225\142\166",
        [0xab77] = "\225\142\167",
        [0xab78] = "\225\142\168",
        [0xab79] = "\225\142\169",
        [0xab7a] = "\225\142\170",
        [0xab7b] = "\225\142\171",
        [0xab7c] = "\225\142\172",
        [0xab7d] = "\225\142\173",
        [0xab7e] = "\225\142\174",
        [0xab7f] = "\225\142\175",
        [0xab80] = "\225\142\176",
        [0xab81] = "\225\142\177",
        [0xab82] = "\225\142\178",
        [0xab83] = "\225\142\179",
        [0xab84] = "\225\142\180",
        [0xab85] = "\225\142\181",
        [0xab86] = "\225\142\182",
        [0xab87] = "\225\142\183",
        [0xab88] = "\225\142\184",
        [0xab89] = "\225\142\185",
        [0xab8a] = "\225\142\186",
        [0xab8b] = "\225\142\187",
        [0xab8c] = "\225\142\188",
        [0xab8d] = "\225\142\189",
        [0xab8e] = "\225\142\190",
        [0xab8f] = "\225\142\191",
        [0xab90] = "\225\143\128",
        [0xab91] = "\225\143\129",
        [0xab92] = "\225\143\130",
        [0xab93] = "\225\143\131",
        [0xab94] = "\225\143\132",
        [0xab95] = "\225\143\133",
        [0xab96] = "\225\143\134",
        [0xab97] = "\225\143\135",
        [0xab98] = "\225\143\136",
        [0xab99] = "\225\143\137",
        [0xab9a] = "\225\143\138",
        [0xab9b] = "\225\143\139",
        [0xab9c] = "\225\143\140",
        [0xab9d] = "\225\143\141",
        [0xab9e] = "\225\143\142",
        [0xab9f] = "\225\143\143",
        [0xaba0] = "\225\143\144",
        [0xaba1] = "\225\143\145",
        [0xaba2] = "\225\143\146",
        [0xaba3] = "\225\143\147",
        [0xaba4] = "\225\143\148",
        [0xaba5] = "\225\143\149",
        [0xaba6] = "\225\143\150",
        [0xaba7] = "\225\143\151",
        [0xaba8] = "\225\143\152",
        [0xaba9] = "\225\143\153",
        [0xabaa] = "\225\143\154",
        [0xabab] = "\225\143\155",
        [0xabac] = "\225\143\156",
        [0xabad] = "\225\143\157",
        [0xabae] = "\225\143\158",
        [0xabaf] = "\225\143\159",
        [0xabb0] = "\225\143\160",
        [0xabb1] = "\225\143\161",
        [0xabb2] = "\225\143\162",
        [0xabb3] = "\225\143\163",
        [0xabb4] = "\225\143\164",
        [0xabb5] = "\225\143\165",
        [0xabb6] = "\225\143\166",
        [0xabb7] = "\225\143\167",
        [0xabb8] = "\225\143\168",
        [0xabb9] = "\225\143\169",
        [0xabba] = "\225\143\170",
        [0xabbb] = "\225\143\171",
        [0xabbc] = "\225\143\172",
        [0xabbd] = "\225\143\173",
        [0xabbe] = "\225\143\174",
        [0xabbf] = "\225\143\175",
        [0xfb00] = "\102\102",
        [0xfb01] = "\102\105",
        [0xfb02] = "\102\108",
        [0xfb03] = "\102\102\105",
        [0xfb04] = "\102\102\108",
        [0xfb05] = "\115\116",
        [0xfb06] = "\115\116",
        [0xfb13] = "\213\180\213\182",
        [0xfb14] = "\213\180\213\165",
        [0xfb15] = "\213\180\213\171",
        [0xfb16] = "\213\190\213\182",
        [0xfb17] = "\213\180\213\173",
        [0xff21] = "\239\189\129",
        [0xff22] = "\239\189\130",
        [0xff23] = "\239\189\131",
        [0xff24] = "\239\189\132",
        [0xff25] = "\239\189\133",
        [0xff26] = "\239\189\134",
        [0xff27] = "\239\189\135",
        [0xff28] = "\239\189\136",
        [0xff29] = "\239\189\137",
        [0xff2a] = "\239\189\138",
        [0xff2b] = "\239\189\139",
        [0xff2c] = "\239\189\140",
        [0xff2d] = "\239\189\141",
        [0xff2e] = "\239\189\142",
        [0xff2f] = "\239\189\143",
        [0xff30] = "\239\189\144",
        [0xff31] = "\239\189\145",
        [0xff32] = "\239\189\146",
        [0xff33] = "\239\189\147",
        [0xff34] = "\239\189\148",
        [0xff35] = "\239\189\149",
        [0xff36] = "\239\189\150",
        [0xff37] = "\239\189\151",
        [0xff38] = "\239\189\152",
        [0xff39] = "\239\189\153",
        [0xff3a] = "\239\189\154",
        [0x10400] = "\240\144\144\168",
        [0x10401] = "\240\144\144\169",
        [0x10402] = "\240\144\144\170",
        [0x10403] = "\240\144\144\171",
        [0x10404] = "\240\144\144\172",
        [0x10405] = "\240\144\144\173",
        [0x10406] = "\240\144\144\174",
        [0x10407] = "\240\144\144\175",
        [0x10408] = "\240\144\144\176",
        [0x10409] = "\240\144\144\177",
        [0x1040a] = "\240\144\144\178",
        [0x1040b] = "\240\144\144\179",
        [0x1040c] = "\240\144\144\180",
        [0x1040d] = "\240\144\144\181",
        [0x1040e] = "\240\144\144\182",
        [0x1040f] = "\240\144\144\183",
        [0x10410] = "\240\144\144\184",
        [0x10411] = "\240\144\144\185",
        [0x10412] = "\240\144\144\186",
        [0x10413] = "\240\144\144\187",
        [0x10414] = "\240\144\144\188",
        [0x10415] = "\240\144\144\189",
        [0x10416] = "\240\144\144\190",
        [0x10417] = "\240\144\144\191",
        [0x10418] = "\240\144\145\128",
        [0x10419] = "\240\144\145\129",
        [0x1041a] = "\240\144\145\130",
        [0x1041b] = "\240\144\145\131",
        [0x1041c] = "\240\144\145\132",
        [0x1041d] = "\240\144\145\133",
        [0x1041e] = "\240\144\145\134",
        [0x1041f] = "\240\144\145\135",
        [0x10420] = "\240\144\145\136",
        [0x10421] = "\240\144\145\137",
        [0x10422] = "\240\144\145\138",
        [0x10423] = "\240\144\145\139",
        [0x10424] = "\240\144\145\140",
        [0x10425] = "\240\144\145\141",
        [0x10426] = "\240\144\145\142",
        [0x10427] = "\240\144\145\143",
        [0x104b0] = "\240\144\147\152",
        [0x104b1] = "\240\144\147\153",
        [0x104b2] = "\240\144\147\154",
        [0x104b3] = "\240\144\147\155",
        [0x104b4] = "\240\144\147\156",
        [0x104b5] = "\240\144\147\157",
        [0x104b6] = "\240\144\147\158",
        [0x104b7] = "\240\144\147\159",
        [0x104b8] = "\240\144\147\160",
        [0x104b9] = "\240\144\147\161",
        [0x104ba] = "\240\144\147\162",
        [0x104bb] = "\240\144\147\163",
        [0x104bc] = "\240\144\147\164",
        [0x104bd] = "\240\144\147\165",
        [0x104be] = "\240\144\147\166",
        [0x104bf] = "\240\144\147\167",
        [0x104c0] = "\240\144\147\168",
        [0x104c1] = "\240\144\147\169",
        [0x104c2] = "\240\144\147\170",
        [0x104c3] = "\240\144\147\171",
        [0x104c4] = "\240\144\147\172",
        [0x104c5] = "\240\144\147\173",
        [0x104c6] = "\240\144\147\174",
        [0x104c7] = "\240\144\147\175",
        [0x104c8] = "\240\144\147\176",
        [0x104c9] = "\240\144\147\177",
        [0x104ca] = "\240\144\147\178",
        [0x104cb] = "\240\144\147\179",
        [0x104cc] = "\240\144\147\180",
        [0x104cd] = "\240\144\147\181",
        [0x104ce] = "\240\144\147\182",
        [0x104cf] = "\240\144\147\183",
        [0x104d0] = "\240\144\147\184",
        [0x104d1] = "\240\144\147\185",
        [0x104d2] = "\240\144\147\186",
        [0x104d3] = "\240\144\147\187",
        [0x10570] = "\240\144\150\151",
        [0x10571] = "\240\144\150\152",
        [0x10572] = "\240\144\150\153",
        [0x10573] = "\240\144\150\154",
        [0x10574] = "\240\144\150\155",
        [0x10575] = "\240\144\150\156",
        [0x10576] = "\240\144\150\157",
        [0x10577] = "\240\144\150\158",
        [0x10578] = "\240\144\150\159",
        [0x10579] = "\240\144\150\160",
        [0x1057a] = "\240\144\150\161",
        [0x1057c] = "\240\144\150\163",
        [0x1057d] = "\240\144\150\164",
        [0x1057e] = "\240\144\150\165",
        [0x1057f] = "\240\144\150\166",
        [0x10580] = "\240\144\150\167",
        [0x10581] = "\240\144\150\168",
        [0x10582] = "\240\144\150\169",
        [0x10583] = "\240\144\150\170",
        [0x10584] = "\240\144\150\171",
        [0x10585] = "\240\144\150\172",
        [0x10586] = "\240\144\150\173",
        [0x10587] = "\240\144\150\174",
        [0x10588] = "\240\144\150\175",
        [0x10589] = "\240\144\150\176",
        [0x1058a] = "\240\144\150\177",
        [0x1058c] = "\240\144\150\179",
        [0x1058d] = "\240\144\150\180",
        [0x1058e] = "\240\144\150\181",
        [0x1058f] = "\240\144\150\182",
        [0x10590] = "\240\144\150\183",
        [0x10591] = "\240\144\150\184",
        [0x10592] = "\240\144\150\185",
        [0x10594] = "\240\144\150\187",
        [0x10595] = "\240\144\150\188",
        [0x10c80] = "\240\144\179\128",
        [0x10c81] = "\240\144\179\129",
        [0x10c82] = "\240\144\179\130",
        [0x10c83] = "\240\144\179\131",
        [0x10c84] = "\240\144\179\132",
        [0x10c85] = "\240\144\179\133",
        [0x10c86] = "\240\144\179\134",
        [0x10c87] = "\240\144\179\135",
        [0x10c88] = "\240\144\179\136",
        [0x10c89] = "\240\144\179\137",
        [0x10c8a] = "\240\144\179\138",
        [0x10c8b] = "\240\144\179\139",
        [0x10c8c] = "\240\144\179\140",
        [0x10c8d] = "\240\144\179\141",
        [0x10c8e] = "\240\144\179\142",
        [0x10c8f] = "\240\144\179\143",
        [0x10c90] = "\240\144\179\144",
        [0x10c91] = "\240\144\179\145",
        [0x10c92] = "\240\144\179\146",
        [0x10c93] = "\240\144\179\147",
        [0x10c94] = "\240\144\179\148",
        [0x10c95] = "\240\144\179\149",
        [0x10c96] = "\240\144\179\150",
        [0x10c97] = "\240\144\179\151",
        [0x10c98] = "\240\144\179\152",
        [0x10c99] = "\240\144\179\153",
        [0x10c9a] = "\240\144\179\154",
        [0x10c9b] = "\240\144\179\155",
        [0x10c9c] = "\240\144\179\156",
        [0x10c9d] = "\240\144\179\157",
        [0x10c9e] = "\240\144\179\158",
        [0x10c9f] = "\240\144\179\159",
        [0x10ca0] = "\240\144\179\160",
        [0x10ca1] = "\240\144\179\161",
        [0x10ca2] = "\240\144\179\162",
        [0x10ca3] = "\240\144\179\163",
        [0x10ca4] = "\240\144\179\164",
        [0x10ca5] = "\240\144\179\165",
        [0x10ca6] = "\240\144\179\166",
        [0x10ca7] = "\240\144\179\167",
        [0x10ca8] = "\240\144\179\168",
        [0x10ca9] = "\240\144\179\169",
        [0x10caa] = "\240\144\179\170",
        [0x10cab] = "\240\144\179\171",
        [0x10cac] = "\240\144\179\172",
        [0x10cad] = "\240\144\179\173",
        [0x10cae] = "\240\144\179\174",
        [0x10caf] = "\240\144\179\175",
        [0x10cb0] = "\240\144\179\176",
        [0x10cb1] = "\240\144\179\177",
        [0x10cb2] = "\240\144\179\178",
        [0x10d50] = "\240\144\181\176",
        [0x10d51] = "\240\144\181\177",
        [0x10d52] = "\240\144\181\178",
        [0x10d53] = "\240\144\181\179",
        [0x10d54] = "\240\144\181\180",
        [0x10d55] = "\240\144\181\181",
        [0x10d56] = "\240\144\181\182",
        [0x10d57] = "\240\144\181\183",
        [0x10d58] = "\240\144\181\184",
        [0x10d59] = "\240\144\181\185",
        [0x10d5a] = "\240\144\181\186",
        [0x10d5b] = "\240\144\181\187",
        [0x10d5c] = "\240\144\181\188",
        [0x10d5d] = "\240\144\181\189",
        [0x10d5e] = "\240\144\181\190",
        [0x10d5f] = "\240\144\181\191",
        [0x10d60] = "\240\144\182\128",
        [0x10d61] = "\240\144\182\129",
        [0x10d62] = "\240\144\182\130",
        [0x10d63] = "\240\144\182\131",
        [0x10d64] = "\240\144\182\132",
        [0x10d65] = "\240\144\182\133",
        [0x118a0] = "\240\145\163\128",
        [0x118a1] = "\240\145\163\129",
        [0x118a2] = "\240\145\163\130",
        [0x118a3] = "\240\145\163\131",
        [0x118a4] = "\240\145\163\132",
        [0x118a5] = "\240\145\163\133",
        [0x118a6] = "\240\145\163\134",
        [0x118a7] = "\240\145\163\135",
        [0x118a8] = "\240\145\163\136",
        [0x118a9] = "\240\145\163\137",
        [0x118aa] = "\240\145\163\138",
        [0x118ab] = "\240\145\163\139",
        [0x118ac] = "\240\145\163\140",
        [0x118ad] = "\240\145\163\141",
        [0x118ae] = "\240\145\163\142",
        [0x118af] = "\240\145\163\143",
        [0x118b0] = "\240\145\163\144",
        [0x118b1] = "\240\145\163\145",
        [0x118b2] = "\240\145\163\146",
        [0x118b3] = "\240\145\163\147",
        [0x118b4] = "\240\145\163\148",
        [0x118b5] = "\240\145\163\149",
        [0x118b6] = "\240\145\163\150",
        [0x118b7] = "\240\145\163\151",
        [0x118b8] = "\240\145\163\152",
        [0x118b9] = "\240\145\163\153",
        [0x118ba] = "\240\145\163\154",
        [0x118bb] = "\240\145\163\155",
        [0x118bc] = "\240\145\163\156",
        [0x118bd] = "\240\145\163\157",
        [0x118be] = "\240\145\163\158",
        [0x118bf] = "\240\145\163\159",
        [0x16e40] = "\240\150\185\160",
        [0x16e41] = "\240\150\185\161",
        [0x16e42] = "\240\150\185\162",
        [0x16e43] = "\240\150\185\163",
        [0x16e44] = "\240\150\185\164",
        [0x16e45] = "\240\150\185\165",
        [0x16e46] = "\240\150\185\166",
        [0x16e47] = "\240\150\185\167",
        [0x16e48] = "\240\150\185\168",
        [0x16e49] = "\240\150\185\169",
        [0x16e4a] = "\240\150\185\170",
        [0x16e4b] = "\240\150\185\171",
        [0x16e4c] = "\240\150\185\172",
        [0x16e4d] = "\240\150\185\173",
        [0x16e4e] = "\240\150\185\174",
        [0x16e4f] = "\240\150\185\175",
        [0x16e50] = "\240\150\185\176",
        [0x16e51] = "\240\150\185\177",
        [0x16e52] = "\240\150\185\178",
        [0x16e53] = "\240\150\185\179",
        [0x16e54] = "\240\150\185\180",
        [0x16e55] = "\240\150\185\181",
        [0x16e56] = "\240\150\185\182",
        [0x16e57] = "\240\150\185\183",
        [0x16e58] = "\240\150\185\184",
        [0x16e59] = "\240\150\185\185",
        [0x16e5a] = "\240\150\185\186",
        [0x16e5b] = "\240\150\185\187",
        [0x16e5c] = "\240\150\185\188",
        [0x16e5d] = "\240\150\185\189",
        [0x16e5e] = "\240\150\185\190",
        [0x16e5f] = "\240\150\185\191",
        [0x16ea0] = "\240\150\186\187",
        [0x16ea1] = "\240\150\186\188",
        [0x16ea2] = "\240\150\186\189",
        [0x16ea3] = "\240\150\186\190",
        [0x16ea4] = "\240\150\186\191",
        [0x16ea5] = "\240\150\187\128",
        [0x16ea6] = "\240\150\187\129",
        [0x16ea7] = "\240\150\187\130",
        [0x16ea8] = "\240\150\187\131",
        [0x16ea9] = "\240\150\187\132",
        [0x16eaa] = "\240\150\187\133",
        [0x16eab] = "\240\150\187\134",
        [0x16eac] = "\240\150\187\135",
        [0x16ead] = "\240\150\187\136",
        [0x16eae] = "\240\150\187\137",
        [0x16eaf] = "\240\150\187\138",
        [0x16eb0] = "\240\150\187\139",
        [0x16eb1] = "\240\150\187\140",
        [0x16eb2] = "\240\150\187\141",
        [0x16eb3] = "\240\150\187\142",
        [0x16eb4] = "\240\150\187\143",
        [0x16eb5] = "\240\150\187\144",
        [0x16eb6] = "\240\150\187\145",
        [0x16eb7] = "\240\150\187\146",
        [0x16eb8] = "\240\150\187\147",
        [0x1e900] = "\240\158\164\162",
        [0x1e901] = "\240\158\164\163",
        [0x1e902] = "\240\158\164\164",
        [0x1e903] = "\240\158\164\165",
        [0x1e904] = "\240\158\164\166",
        [0x1e905] = "\240\158\164\167",
        [0x1e906] = "\240\158\164\168",
        [0x1e907] = "\240\158\164\169",
        [0x1e908] = "\240\158\164\170",
        [0x1e909] = "\240\158\164\171",
        [0x1e90a] = "\240\158\164\172",
        [0x1e90b] = "\240\158\164\173",
        [0x1e90c] = "\240\158\164\174",
        [0x1e90d] = "\240\158\164\175",
        [0x1e90e] = "\240\158\164\176",
        [0x1e90f] = "\240\158\164\177",
        [0x1e910] = "\240\158\164\178",
        [0x1e911] = "\240\158\164\179",
        [0x1e912] = "\240\158\164\180",
        [0x1e913] = "\240\158\164\181",
        [0x1e914] = "\240\158\164\182",
        [0x1e915] = "\240\158\164\183",
        [0x1e916] = "\240\158\164\184",
        [0x1e917] = "\240\158\164\185",
        [0x1e918] = "\240\158\164\186",
        [0x1e919] = "\240\158\164\187",
        [0x1e91a] = "\240\158\164\188",
        [0x1e91b] = "\240\158\164\189",
        [0x1e91c] = "\240\158\164\190",
        [0x1e91d] = "\240\158\164\191",
        [0x1e91e] = "\240\158\165\128",
        [0x1e91f] = "\240\158\165\129",
        [0x1e920] = "\240\158\165\130",
        [0x1e921] = "\240\158\165\131",
    }
    return fold_map
end

local function CheckCaseSensitive(value)
    if value ~= nil and type(value) ~= "boolean" then
        error("caseSensitive должен быть логическим значением", 3)
    end
end

-- ASCII retains its byte/character identity and allocates no position tables.
local function FoldText(text)
    AssertString(text, "text")
    if IsAscii(text) then return string.lower(text) end
    local map, pieces, pos = GetFoldMap(), {}, 1
    while pos <= #text do
        local cp, after, err = DecodeAt(text, pos)
        if err then error("text: " .. err, 3) end
        pieces[#pieces + 1] = map[cp] or text:sub(pos, after - 1)
        pos = after
    end
    return table.concat(pieces)
end

-- Match only complete original scalars: ss matches sharp-s, s does not.
-- Returned byte ranges always refer to the original text.
local function InsensitiveSearch(text, needle, at_end)
    AssertString(text, "text")
    AssertString(needle, "needle")
    if IsAscii(text) and IsAscii(needle) then
        local folded, target = string.lower(text), string.lower(needle)
        return function(start) return folded:find(target, start, true) end, nil, #text
    end
    local target = FoldText(needle)
    local map, pieces = GetFoldMap(), {}
    local offsets, to_original, to_folded = {}, {}, {}
    local pos, folded_pos, length = 1, 1, 0
    while pos <= #text do
        local cp, after, err = DecodeAt(text, pos)
        if err then error("text: " .. err, 3) end
        local piece = map[cp] or text:sub(pos, after - 1)
        length = length + 1
        offsets[length], to_original[folded_pos], to_folded[pos] = pos, pos, folded_pos
        pieces[length] = piece
        pos, folded_pos = after, folded_pos + #piece
    end
    offsets[length + 1] = pos
    to_original[folded_pos], to_folded[pos] = pos, folded_pos
    local folded = table.concat(pieces)
    return function(start)
        local search = to_folded[start]
        if at_end then
            local first = #folded - #target + 1
            if search and first >= search and to_original[first] and folded:sub(first) == target then
                return to_original[first], #text
            end
            return nil
        end
        while search do
            local first, last = folded:find(target, search, true)
            if not first then return nil end
            if to_original[first] and to_original[last + 1] then
                return to_original[first], to_original[last + 1] - 1
            end
            search = first + 1
        end
    end, offsets, length
end

-- caseSensitive defaults to true. false uses Unicode full case folding.
function M.StartsWith(text, prefix, caseSensitive)
    CheckCaseSensitive(caseSensitive)
    if caseSensitive == false then
        local Search = InsensitiveSearch(text, prefix)
        return Search(1) == 1
    end
    RequireUtf8(text, "text")
    RequireUtf8(prefix, "prefix")
    return text:sub(1, #prefix) == prefix
end

function M.EndsWith(text, suffix, caseSensitive)
    CheckCaseSensitive(caseSensitive)
    if caseSensitive == false then
        AssertString(text, "text")
        AssertString(suffix, "suffix")
        if IsAscii(text) and IsAscii(suffix) then
            return suffix == "" or string.lower(text:sub(-#suffix)) == string.lower(suffix)
        end
        local Search = InsensitiveSearch(text, suffix, true)
        return Search(1) ~= nil
    end
    RequireUtf8(text, "text")
    RequireUtf8(suffix, "suffix")
    return suffix == "" or text:sub(-#suffix) == suffix
end

function M.Contains(text, needle, caseSensitive)
    CheckCaseSensitive(caseSensitive)
    if caseSensitive == false then
        local Search = InsensitiveSearch(text, needle)
        return Search(1) ~= nil
    end
    RequireUtf8(text, "text")
    RequireUtf8(needle, "needle")
    return text:find(needle, 1, true) ~= nil
end

function M.Equals(left, right, caseSensitive)
    CheckCaseSensitive(caseSensitive)
    if caseSensitive == false then return FoldText(left) == FoldText(right) end
    RequireUtf8(left, "left")
    RequireUtf8(right, "right")
    return left == right
end

function M.LFind(text, needle, init, caseSensitive)
    CheckCaseSensitive(caseSensitive)
    if caseSensitive == false then
        local Search, offsets, length = InsensitiveSearch(text, needle)
        if not Search then return nil, offsets end
        local start = NormalizeSearchIndex(init, length)
        local first, last = Search(BytePosition(offsets, start))
        if not first then return nil end
        return CharPosition(offsets, length, first), CharPosition(offsets, length, last + 1) - 1
    end
    -- The usual start position needs no offset table. Search in bytes, then
    -- validate the entire text while translating both result boundaries.
    if init == nil or init == 1 or init == 0 then
        AssertString(text, "text")
        RequireUtf8(needle, "needle")
        local first_byte, last_byte = string.find(text, needle, 1, true)
        if IsAscii(text) then
            if not first_byte then return nil end
            return first_byte, last_byte
        end
        local pos, count = 1, 0
        local first_char, after_char
        while pos <= #text do
            count = count + 1
            if pos == first_byte then first_char = count end
            if last_byte and pos == last_byte + 1 then after_char = count end
            local _, next_pos, err = DecodeAt(text, pos)
            if err then error("text: " .. err, 2) end
            pos = next_pos
        end
        if not first_byte then return nil end
        if first_byte == #text + 1 then first_char = count + 1 end
        if last_byte + 1 == #text + 1 then after_char = count + 1 end
        return first_char, after_char - 1
    end
    local offsets, length = IndexText(text)
    RequireUtf8(needle, "needle")

    local start_index = NormalizeSearchIndex(init, length)

    if needle == "" then
        return start_index, start_index - 1
    end

    if start_index == length + 1 then
        return nil
    end

    local byte_init = BytePosition(offsets, start_index)
    local first_byte, last_byte = string.find(text, needle, byte_init, true)

    if not first_byte then
        return nil
    end

    local first_char = CharPosition(offsets, length, first_byte)
    local after_char = CharPosition(offsets, length, last_byte + 1)

    if not first_char or not after_char then
        return nil, "результат поиска заканчивается внутри символа UTF-8"
    end

    return first_char, after_char - 1
end

local function LastLiteral(text, needle, limit)
    local last_first, last_last
    local search = 1
    while true do
        local first, last = text:find(needle, search, true)
        if not first or first > limit then break end
        last_first, last_last = first, last
        search = first + 1
    end
    return last_first, last_last
end

function M.RFind(text, needle, init, caseSensitive)
    CheckCaseSensitive(caseSensitive)
    if caseSensitive == false then
        AssertString(text, "text")
        AssertString(needle, "needle")
        if IsAscii(text) and IsAscii(needle) then
            local length = #text
            local limit = NormalizeIndex(init, length, length)
            if needle == "" then
                if limit < 1 and not (length == 0 and limit == 0) then return nil end
                limit = math.min(limit, length)
                return limit + 1, limit
            end
            if limit < 1 then return nil end
            return LastLiteral(string.lower(text), string.lower(needle), math.min(limit, length))
        end
        local Search, offsets, length = InsensitiveSearch(text, needle)
        if not Search then return nil, offsets end
        local limit = NormalizeIndex(init, length, length)
        if needle == "" then
            if limit < 1 and not (length == 0 and limit == 0) then return nil end
            limit = math.min(limit, length)
            return limit + 1, limit
        end
        if limit < 1 then return nil end
        limit = math.min(limit, length)
        local pos, found_first, found_last = 1
        while pos <= limit do
            local first, last = Search(BytePosition(offsets, pos))
            if not first or first > BytePosition(offsets, limit) then break end
            found_first = CharPosition(offsets, length, first)
            found_last = CharPosition(offsets, length, last + 1) - 1
            pos = found_first + 1
        end
        return found_first, found_last
    end
    AssertString(text, "text")
    -- Keep whole-input validation and scalar positions without an offset table.
    local ascii = IsAscii(text)
    local length = #text
    if not ascii then
        local pos, count = 1, 0
        while pos <= #text do
            local _, next_pos, err = DecodeAt(text, pos)
            if err then error(err, 3) end
            pos, count = next_pos, count + 1
        end
        length = count
    end
    RequireUtf8(needle, "needle")
    local limit = NormalizeIndex(init, length, length)
    if needle == "" then
        if limit < 1 and not (length == 0 and limit == 0) then return nil end
        limit = math.min(limit, length)
        return limit + 1, limit
    end
    if limit < 1 then return nil end
    if limit > length then limit = length end
    local byte_limit = IndexedByte(text, length, limit)
    local first, last = LastLiteral(text, needle, byte_limit)
    if not first then return nil end
    if ascii then return first, last end
    -- Valid UTF-8 literals always match at complete scalar boundaries.
    local pos, index, first_char = 1, 1
    while pos <= last + 1 do
        if pos == first then first_char = index end
        if pos == last + 1 then return first_char, index - 1 end
        local byte = text:byte(pos)
        if byte < 0x80 then pos = pos + 1
        elseif byte < 0xE0 then pos = pos + 2
        elseif byte < 0xF0 then pos = pos + 3
        else pos = pos + 4 end
        index = index + 1
    end
end

function M.Replace(text, old_text, new_text, limit, caseSensitive)
    CheckCaseSensitive(caseSensitive)
    RequireUtf8(text, "text")
    RequireUtf8(old_text, "old_text")
    RequireUtf8(new_text, "new_text")

    if old_text == "" then
        return nil, "old_text не должен быть пустым"
    end

    if limit ~= nil and (type(limit) ~= "number" or (limit ~= math.floor(limit) or limit == math.huge or limit == -math.huge) or limit < 0) then
        return nil, "limit должен быть неотрицательным целым числом"
    end

    local Search
    if caseSensitive == false then
        local err
        Search, err = InsensitiveSearch(text, old_text)
        if not Search then return nil, err end
    end
    local result = {}
    local byte_pos = 1
    local count = 0

    while byte_pos <= #text do
        if limit ~= nil and count >= limit then
            break
        end

        local first_byte, last_byte
        if Search then first_byte, last_byte = Search(byte_pos)
        else first_byte, last_byte = string.find(text, old_text, byte_pos, true) end
        if not first_byte then
            break
        end

        result[#result + 1] = text:sub(byte_pos, first_byte - 1)
        result[#result + 1] = new_text
        count = count + 1
        byte_pos = last_byte + 1
    end

    result[#result + 1] = text:sub(byte_pos)
    return table.concat(result), count
end

function M.Count(text, needle, caseSensitive)
    CheckCaseSensitive(caseSensitive)
    RequireUtf8(text, "text")
    RequireUtf8(needle, "needle")

    if needle == "" then
        return nil, "needle не должен быть пустым"
    end

    local Search
    if caseSensitive == false then
        local err
        Search, err = InsensitiveSearch(text, needle)
        if not Search then return nil, err end
    end
    local count = 0
    local byte_pos = 1

    while byte_pos <= #text do
        local first_byte, last_byte
        if Search then first_byte, last_byte = Search(byte_pos)
        else first_byte, last_byte = string.find(text, needle, byte_pos, true) end
        if not first_byte then
            break
        end

        count = count + 1
        byte_pos = last_byte + 1
    end

    return count
end

-- Match only complete UTF-8 whitespace sequences at the requested edge.
-- Trimming does not validate the rest of the string; use isValidUtf8 for that.
-- Keep this set in sync with IsUnicodeSpace (Unicode White_Space).
local function LeadingSpaceWidth(text, pos)
    local a = text:byte(pos)
    if a == 0x20 or (a >= 0x09 and a <= 0x0D) then return 1 end
    if a < 0x80 then return 0 end
    if a == 0xC2 then
        local b = text:byte(pos + 1)
        if b == 0x85 or b == 0xA0 then return 2 end
    elseif a == 0xE1 or a == 0xE2 or a == 0xE3 then
        local b, c = text:byte(pos + 1, pos + 2)
        if a == 0xE1 then
            if b == 0x9A and c == 0x80 then return 3 end
        elseif a == 0xE2 then
            if b == 0x80 and c and
                ((c >= 0x80 and c <= 0x8A) or c == 0xA8 or c == 0xA9 or c == 0xAF) then
                return 3
            end
            if b == 0x81 and c == 0x9F then return 3 end
        elseif b == 0x80 and c == 0x80 then
            return 3
        end
    end
    return 0
end

local function TrailingSpaceWidth(text, pos)
    local c = text:byte(pos)
    if c == 0x20 or (c >= 0x09 and c <= 0x0D) then return 1 end
    if c < 0x80 then return 0 end
    if pos >= 2 and (c == 0x85 or c == 0xA0) and text:byte(pos - 1) == 0xC2 then
        return 2
    end
    if pos >= 3 then
        local a, b = text:byte(pos - 2, pos - 1)
        if a == 0xE1 then
            if b == 0x9A and c == 0x80 then return 3 end
        elseif a == 0xE2 then
            if b == 0x80 and
                ((c >= 0x80 and c <= 0x8A) or c == 0xA8 or c == 0xA9 or c == 0xAF) then
                return 3
            end
            if b == 0x81 and c == 0x9F then return 3 end
        elseif a == 0xE3 and b == 0x80 and c == 0x80 then
            return 3
        end
    end
    return 0
end

local function TrimText(text, left, right)
    AssertString(text, "text")
    local first, last = 1, #text
    if left then
        while first <= last do
            local width = LeadingSpaceWidth(text, first)
            if width == 0 then break end
            first = first + width
        end
    end
    if right then
        while last >= first do
            local width = TrailingSpaceWidth(text, last)
            if width == 0 then break end
            last = last - width
        end
    end
    if first > last then return "" end
    if first == 1 and last == #text then return text end
    return text:sub(first, last)
end

function M.LTrim(text) return TrimText(text, true, false) end
function M.RTrim(text) return TrimText(text, false, true) end
function M.Trim(text) return TrimText(text, true, true) end

-- wholeSeparator: false uses a set of characters, true uses the entire delimiter.
-- keepEmpty: false (default) skips empty fields, true preserves them.
function M.Split(text, sep, wholeSeparator, keepEmpty)
    if wholeSeparator ~= nil and type(wholeSeparator) ~= "boolean" then
        error("wholeSeparator должен быть логическим значением", 2)
    end
    if keepEmpty ~= nil and type(keepEmpty) ~= "boolean" then
        error("keepEmpty должен быть логическим значением", 2)
    end
    RequireUtf8(text, "text")
    sep = sep == nil and " " or sep
    RequireUtf8(sep, "sep")
    local result = {}
    local function Add(first, after)
        if keepEmpty == true or first < after then
            result[#result + 1] = text:sub(first, after - 1)
        end
    end
    if sep == "" then
        Add(1, #text + 1)
        return result
    end
    if wholeSeparator == true then
        local pos = 1
        while true do
            local first, last = text:find(sep, pos, true)
            if not first then break end
            Add(pos, first)
            pos = last + 1
        end
        Add(pos, #text + 1)
    else
        local delimiters, pos = {}, 1
        while pos <= #sep do
            local codepoint, next_pos = DecodeAt(sep, pos)
            delimiters[codepoint] = true
            pos = next_pos
        end
        local first = 1
        pos = 1
        while pos <= #text do
            local codepoint, next_pos = DecodeAt(text, pos)
            if delimiters[codepoint] then
                Add(first, pos)
                first = next_pos
            end
            pos = next_pos
        end
        Add(first, #text + 1)
    end
    return result
end


local function PreparePadding(text, width, pad)
    local length = M.Len(text)
    if type(width) ~= "number" or (width ~= math.floor(width) or width == math.huge or width == -math.huge) or width < 0 then
        error("ширина должна быть неотрицательным целым числом", 3)
    end
    local missing = width - length
    if missing <= 0 then return missing end
    pad = pad == nil and " " or pad
    local pad_len = M.Len(pad)
    if pad_len == 0 then error("заполнитель не должен быть пустым", 3) end
    return missing, pad, pad_len
end

function M.LPad(text, width, pad)
    local missing, padding, pad_len = PreparePadding(text, width, pad)
    if missing <= 0 then return text end
    return RepeatToLength(padding, pad_len, missing) .. text
end

function M.RPad(text, width, pad)
    local missing, padding, pad_len = PreparePadding(text, width, pad)
    if missing <= 0 then return text end
    return text .. RepeatToLength(padding, pad_len, missing)
end

function M.Center(text, width, pad)
    local missing, padding, pad_len = PreparePadding(text, width, pad)
    if missing <= 0 then return text end
    local left = math.floor(missing / 2)
    local right = missing - left
    return RepeatToLength(padding, pad_len, left) .. text ..
        RepeatToLength(padding, pad_len, right)
end

local function FormatStringValue(value, flags, width_text, precision_text)
    local text = tostring(value)
    local text_len = M.Len(text)

    if precision_text ~= "" then
        local precision = tonumber(precision_text:sub(2)) or 0
        if precision < text_len then
            text = text:sub(1, IndexedByte(text, text_len, precision + 1) - 1)
            text_len = precision
        end
    end

    local width = tonumber(width_text) or 0

    if width > text_len then
        local padding = string.rep(" ", width - text_len)
        if flags:find("-", 1, true) then
            text = text .. padding
        else
            text = padding .. text
        end
    end

    return text
end

function M.Format(format_text, ...)
    RequireUtf8(format_text, "format")

    local args = { n = select("#", ...), ... }
    local arg_index = 1
    local result = {}
    local pos = 1

    while pos <= #format_text do
        local percent = string.find(format_text, "%", pos, true)

        if not percent then
            result[#result + 1] = format_text:sub(pos)
            break
        end

        result[#result + 1] = format_text:sub(pos, percent - 1)

        if format_text:sub(percent + 1, percent + 1) == "%" then
            result[#result + 1] = "%"
            pos = percent + 2
        else
            local cursor = percent + 1
            local flags_start = cursor

            while true do
                local char = format_text:sub(cursor, cursor)
                if char == "-" or char == "+" or char == " " or char == "#" or char == "0" then
                    cursor = cursor + 1
                else
                    break
                end
            end

            local flags = format_text:sub(flags_start, cursor - 1)
            local width_start = cursor

            while format_text:sub(cursor, cursor):match("%d") do
                cursor = cursor + 1
            end

            local width_text = format_text:sub(width_start, cursor - 1)
            local precision_text = ""

            if format_text:sub(cursor, cursor) == "." then
                local precision_start = cursor
                cursor = cursor + 1

                while format_text:sub(cursor, cursor):match("%d") do
                    cursor = cursor + 1
                end

                precision_text = format_text:sub(precision_start, cursor - 1)
            end

            local conversion = format_text:sub(cursor, cursor)
            if conversion == "" then
                error("незавершённый спецификатор формата", 2)
            end

            if not conversion:match("[cdiouxXeEfgGqs]") then
                error("недопустимый спецификатор формата %" .. conversion, 2)
            end

            if arg_index > args.n then
                error("недостаточно аргументов формата", 2)
            end

            local value = args[arg_index]
            arg_index = arg_index + 1
            local spec = format_text:sub(percent, cursor)

            if conversion == "s" then
                result[#result + 1] = FormatStringValue(value, flags, width_text, precision_text)
            elseif conversion == "c" then
                local character = M.Char(value)
                local width = tonumber(width_text) or 0

                if width > 1 then
                    if flags:find("-", 1, true) then
                        character = character .. string.rep(" ", width - 1)
                    else
                        character = string.rep(" ", width - 1) .. character
                    end
                end

                result[#result + 1] = character
            else
                result[#result + 1] = string.format(spec, value)
            end

            pos = cursor + 1
        end
    end

    if arg_index <= args.n then
        error("слишком много аргументов формата", 2)
    end

    return table.concat(result)
end

-- Extra high-level string helpers inspired by Python, C#, Java, Kotlin and Rust.

function M.IsBlank(text)
    AssertString(text, "text")
    local pos = 1
    while pos <= #text do
        local width = LeadingSpaceWidth(text, pos)
        if width == 0 then return false end
        pos = pos + width
    end
    return true
end

function M.CharAt(text, index)
    local length = M.Len(text)
    local normalized = NormalizeIndex(index, length, nil)

    if normalized < 1 or normalized > length then
        return nil
    end

    local pos = IndexedByte(text, length, normalized)
    local _, next_pos = DecodeAt(text, pos)
    return text:sub(pos, next_pos - 1)
end







function M.PrefixRemove(text, prefix)
    RequireUtf8(text, "text")
    RequireUtf8(prefix, "prefix")

    if prefix == "" or text:sub(1, #prefix) ~= prefix then
        return text
    end

    return text:sub(#prefix + 1)
end

function M.SuffixRemove(text, suffix)
    RequireUtf8(text, "text")
    RequireUtf8(suffix, "suffix")

    if suffix == "" or text:sub(-#suffix) ~= suffix then
        return text
    end

    return text:sub(1, #text - #suffix)
end

function M.Divide(text, separator)
    RequireUtf8(text, "text")
    RequireUtf8(separator, "separator")

    if separator == "" then
        return nil, "разделитель не должен быть пустым"
    end

    local first, last = text:find(separator, 1, true)
    if not first then
        return text, ""
    end

    return text:sub(1, first - 1), text:sub(last + 1)
end


function M.Words(text)
    AssertString(text, "text")
    local result = {}
    local pos, first = 1
    while pos <= #text do
        local codepoint, next_pos, err = DecodeAt(text, pos)
        if err then error("text: " .. err, 2) end
        if IsUnicodeSpace(codepoint) then
            if first then
                result[#result + 1] = text:sub(first, pos - 1)
                first = nil
            end
        elseif not first then
            first = pos
        end
        pos = next_pos
    end
    if first then result[#result + 1] = text:sub(first) end
    return result
end

function M.WhitespaceCollapse(text, replacement)
    replacement = replacement == nil and " " or replacement
    RequireUtf8(replacement, "replacement")

    return table.concat(M.Words(text), replacement)
end

local function LineBreakAt(text, pos)
    local a, b, c = text:byte(pos, pos + 2)

    if a == 13 then
        if b == 10 then
            return pos + 2
        end
        return pos + 1
    end

    if a == 10 then
        return pos + 1
    end

    if a == 11 then
        return pos + 1
    end

    if a == 12 then
        return pos + 1
    end

    if a == 28 or a == 29 or a == 30 then
        return pos + 1
    end

    if a == 0xC2 and b == 0x85 then
        return pos + 2
    end

    if a == 0xE2 and b == 0x80 and c == 0xA8 then
        return pos + 3
    end

    if a == 0xE2 and b == 0x80 and c == 0xA9 then
        return pos + 3
    end

    return nil
end

function M.LinesSplit(text, keep_ends)
    AssertString(text, "text")

    if keep_ends ~= nil and type(keep_ends) ~= "boolean" then
        error("keep_ends должен быть логическим значением", 2)
    end

    if text == "" then
        return {}
    end

    local result = {}
    local start_pos = 1
    local pos = 1

    while pos <= #text do
        local next_pos = LineBreakAt(text, pos)

        if next_pos then
            if keep_ends then
                result[#result + 1] = text:sub(start_pos, next_pos - 1)
            else
                result[#result + 1] = text:sub(start_pos, pos - 1)
            end

            start_pos = next_pos
            pos = next_pos
        else
            local _, char_next, err = DecodeAt(text, pos)
            if err then
                error(err, 2)
            end
            pos = char_next
        end
    end

    if start_pos <= #text then
        result[#result + 1] = text:sub(start_pos)
    end

    return result
end

function M.Insert(text, index, value)
    local length = M.Len(text)
    RequireUtf8(value, "value")
    local normalized = NormalizeIndex(index, length, 1)

    if normalized < 1 or normalized > length + 1 then
        return nil, "индекс должен быть от 1 до длины строки плюс 1"
    end

    local pos = IndexedByte(text, length, normalized)
    return text:sub(1, pos - 1) .. value .. text:sub(pos)
end

function M.RangeRemove(text, first_index, last_index)
    local length = M.Len(text)
    local first = NormalizeIndex(first_index, length, 1)
    local last = NormalizeIndex(last_index, length, first)

    if first < 1 then
        first = 1
    end

    if last > length then
        last = length
    end

    if first > length or last < 1 or first > last then
        return text
    end

    local first_byte, after_byte = IndexedRange(text, length, first, last + 1)
    return text:sub(1, first_byte - 1) .. text:sub(after_byte)
end

function M.RangeReplace(text, first_index, last_index, replacement)
    local length = M.Len(text)
    RequireUtf8(replacement, "replacement")
    local first = NormalizeIndex(first_index, length, 1)
    local last = NormalizeIndex(last_index, length, first)

    if first < 1 then
        first = 1
    end

    if last > length then
        last = length
    end

    if first > length + 1 or last < 0 or first > last + 1 then
        return nil, "недопустимый диапазон замены"
    end

    if first == length + 1 then
        return text .. replacement
    end

    local first_byte, after_byte = IndexedRange(text, length, first, last + 1)
    return text:sub(1, first_byte - 1) .. replacement .. text:sub(after_byte)
end

function M.Truncate(text, max_length, suffix)
    local length = M.Len(text)

    if type(max_length) ~= "number"
        or (max_length ~= math.floor(max_length) or max_length == math.huge or max_length == -math.huge)
        or max_length < 0 then
        error("max_length должен быть неотрицательным целым числом", 2)
    end

    suffix = suffix == nil and "…" or suffix
    local suffix_length = M.Len(suffix)
    if length <= max_length then
        return text
    end

    if max_length == 0 then
        return ""
    end

    if suffix_length >= max_length then
        return suffix:sub(1, IndexedByte(suffix, suffix_length, max_length + 1) - 1)
    end

    return text:sub(1, IndexedByte(text, length, max_length - suffix_length + 1) - 1) .. suffix
end

-- Keep implementation-to-implementation calls private: an inner validation
-- failure must unwind to the outer public boundary, never become nil data.
local public = {}
-- Forward the complete result list, including nil holes, without allocating a table.
local function ProtectedResult(name, ok, ...)
    if ok then return ... end
    local converted, message = pcall(tostring, (...))
    if not converted then message = 'Не удалось обработать объект ошибки' end
    message = message:gsub('^.-:%d+: ', '')
    return nil, 'str.' .. name .. ': ' .. message
end
for name, fn in pairs(M) do
    if type(fn) == 'function' then
        public[name] = function(...)
            return ProtectedResult(name, pcall(fn, ...))
        end
    else
        public[name] = fn
    end
end
return public
