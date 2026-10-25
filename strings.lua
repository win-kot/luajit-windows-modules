local ffi = require("ffi")

local M = {
    version = "2.1-unicode"
}

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

local function pack(...)
    return { n = select("#", ...), ... }
end

local function assert_string(value, arg_name)
    if type(value) ~= "string" then
        error((arg_name or "value") .. " must be a string", 3)
    end
end

local function is_continuation(value)
    return value ~= nil and value >= 0x80 and value <= 0xBF
end

local function decode_at(text, pos)
    local a, b, c, d = text:byte(pos, pos + 3)

    if a == nil then
        return nil, pos, "unexpected end of string"
    end

    if a <= 0x7F then
        return a, pos + 1
    end

    if a >= 0xC2 and a <= 0xDF and is_continuation(b) then
        return (a - 0xC0) * 0x40 + (b - 0x80), pos + 2
    end

    if a == 0xE0 and b ~= nil and b >= 0xA0 and b <= 0xBF and is_continuation(c) then
        return (a - 0xE0) * 0x1000 + (b - 0x80) * 0x40 + (c - 0x80), pos + 3
    end

    if a >= 0xE1 and a <= 0xEC and is_continuation(b) and is_continuation(c) then
        return (a - 0xE0) * 0x1000 + (b - 0x80) * 0x40 + (c - 0x80), pos + 3
    end

    if a == 0xED and b ~= nil and b >= 0x80 and b <= 0x9F and is_continuation(c) then
        return (a - 0xE0) * 0x1000 + (b - 0x80) * 0x40 + (c - 0x80), pos + 3
    end

    if a >= 0xEE and a <= 0xEF and is_continuation(b) and is_continuation(c) then
        return (a - 0xE0) * 0x1000 + (b - 0x80) * 0x40 + (c - 0x80), pos + 3
    end

    if a == 0xF0 and b ~= nil and b >= 0x90 and b <= 0xBF and is_continuation(c) and is_continuation(d) then
        return (a - 0xF0) * 0x40000 + (b - 0x80) * 0x1000 + (c - 0x80) * 0x40 + (d - 0x80), pos + 4
    end

    if a >= 0xF1 and a <= 0xF3 and is_continuation(b) and is_continuation(c) and is_continuation(d) then
        return (a - 0xF0) * 0x40000 + (b - 0x80) * 0x1000 + (c - 0x80) * 0x40 + (d - 0x80), pos + 4
    end

    if a == 0xF4 and b ~= nil and b >= 0x80 and b <= 0x8F and is_continuation(c) and is_continuation(d) then
        return (a - 0xF0) * 0x40000 + (b - 0x80) * 0x1000 + (c - 0x80) * 0x40 + (d - 0x80), pos + 4
    end

    return nil, pos, "invalid UTF-8 at byte " .. pos
end

local function validate_utf8(text)
    local pos = 1

    while pos <= #text do
        local _, next_pos, err = decode_at(text, pos)
        if err then
            return false, pos, err
        end
        pos = next_pos
    end

    return true
end

local function require_utf8(text, arg_name)
    assert_string(text, arg_name)

    local ok, _, err = validate_utf8(text)
    if not ok then
        error((arg_name or "string") .. ": " .. err, 3)
    end
end

local function build_offsets(text)
    local offsets = {}
    local codepoints = {}
    local pos = 1
    local count = 0

    while pos <= #text do
        local codepoint, next_pos, err = decode_at(text, pos)
        if err then
            error(err, 3)
        end

        count = count + 1
        offsets[count] = pos
        codepoints[count] = codepoint
        pos = next_pos
    end

    offsets[count + 1] = #text + 1
    return offsets, codepoints, count
end

local function normalize_index(index, length, default_value)
    if index == nil then
        index = default_value
    end

    if type(index) ~= "number" or index ~= math.floor(index) then
        error("index must be an integer", 3)
    end

    if index < 0 then
        index = length + index + 1
    end

    return index
end

local function normalize_search_index(index, length)
    index = normalize_index(index, length, 1)

    if index < 1 then
        return 1
    end

    if index > length + 1 then
        return length + 1
    end

    return index
end

local function is_boundary(text, byte_pos)
    if byte_pos == 1 or byte_pos == #text + 1 then
        return true
    end

    if byte_pos < 1 or byte_pos > #text + 1 then
        return false
    end

    local value = text:byte(byte_pos)
    return value == nil or value < 0x80 or value > 0xBF
end

local function byte_to_char_index(text, byte_pos)
    if byte_pos == #text + 1 then
        return M.len(text) + 1
    end

    local pos = 1
    local index = 1

    while pos <= #text do
        if pos == byte_pos then
            return index
        end

        local _, next_pos, err = decode_at(text, pos)
        if err then
            return nil
        end

        pos = next_pos
        index = index + 1
    end

    return nil
end

local function utf8_to_wide(text)
    if text == "" then
        return ffi.new("su_wchar_t[1]", 0), 0
    end

    if #text > 2147483647 then
        return nil, nil, "string is too large"
    end

    local needed = kernel32.MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, #text, nil, 0)
    if needed == 0 then
        return nil, nil, "MultiByteToWideChar failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")"
    end

    local wide = ffi.new("su_wchar_t[?]", needed)
    local written = kernel32.MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, #text, wide, needed)
    if written == 0 then
        return nil, nil, "MultiByteToWideChar failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")"
    end

    return wide, written
end

local function wide_to_utf8(wide, wide_len)
    if wide_len == 0 then
        return ""
    end

    local needed = kernel32.WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, wide_len, nil, 0, nil, nil)
    if needed == 0 then
        return nil, "WideCharToMultiByte failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")"
    end

    local bytes = ffi.new("char[?]", needed)
    local written = kernel32.WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, wide_len, bytes, needed, nil, nil)
    if written == 0 then
        return nil, "WideCharToMultiByte failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")"
    end

    return ffi.string(bytes, written)
end

local function map_case(text, flags)
    require_utf8(text, "text")

    if text == "" then
        return ""
    end

    local wide, wide_len, err = utf8_to_wide(text)
    if not wide then
        return nil, err
    end

    local needed = kernel32.LCMapStringEx(invariant_locale, flags, wide, wide_len, nil, 0, nil, nil, 0)
    if needed == 0 then
        return nil, "LCMapStringEx failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")"
    end

    local mapped = ffi.new("su_wchar_t[?]", needed)
    local written = kernel32.LCMapStringEx(invariant_locale, flags, wide, wide_len, mapped, needed, nil, nil, 0)
    if written == 0 then
        return nil, "LCMapStringEx failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")"
    end

    return wide_to_utf8(mapped, written)
end

local function encode_codepoint(codepoint)
    if type(codepoint) ~= "number" or codepoint ~= math.floor(codepoint) then
        error("codepoint must be an integer", 3)
    end

    if codepoint < 0 or codepoint > 0x10FFFF or (codepoint >= 0xD800 and codepoint <= 0xDFFF) then
        error("invalid Unicode codepoint", 3)
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

local function is_unicode_space(codepoint)
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

local function repeat_to_length(pad, count)
    if count <= 0 then
        return ""
    end

    require_utf8(pad, "pad")
    local pad_len = M.len(pad)

    if pad_len == 0 then
        error("pad must not be empty", 3)
    end

    local full = math.floor(count / pad_len)
    local rest = count % pad_len
    return string.rep(pad, full) .. M.sub(pad, 1, rest)
end

function M.is_valid_utf8(text)
    assert_string(text, "text")
    return validate_utf8(text)
end

function M.byte_len(text)
    assert_string(text, "text")
    return #text
end

function M.len(text)
    require_utf8(text, "text")

    local pos = 1
    local count = 0

    while pos <= #text do
        local _, next_pos = decode_at(text, pos)
        count = count + 1
        pos = next_pos
    end

    return count
end

function M.sub(text, first_index, last_index)
    require_utf8(text, "text")

    local offsets, _, length = build_offsets(text)
    local first = normalize_index(first_index, length, 1)
    local last = normalize_index(last_index, length, -1)

    if first < 1 then
        first = 1
    end

    if last > length then
        last = length
    end

    if first > length or last < 1 or first > last then
        return ""
    end

    return text:sub(offsets[first], offsets[last + 1] - 1)
end

function M.reverse(text)
    require_utf8(text, "text")

    local offsets, _, length = build_offsets(text)
    local result = {}

    for index = length, 1, -1 do
        result[#result + 1] = text:sub(offsets[index], offsets[index + 1] - 1)
    end

    return table.concat(result)
end

function M.codepoint(text, first_index, last_index)
    require_utf8(text, "text")

    local _, codepoints, length = build_offsets(text)
    local first = normalize_index(first_index, length, 1)
    local last = normalize_index(last_index, length, first)

    if first < 1 then
        first = 1
    end

    if last > length then
        last = length
    end

    if first > length or last < 1 or first > last then
        return nil
    end

    return unpack(codepoints, first, last)
end

function M.char(...)
    local count = select("#", ...)
    local result = {}

    for index = 1, count do
        result[index] = encode_codepoint(select(index, ...))
    end

    return table.concat(result)
end

function M.chars(text)
    require_utf8(text, "text")

    local pos = 1

    return function()
        if pos > #text then
            return nil
        end

        local current = pos
        local _, next_pos = decode_at(text, pos)
        pos = next_pos
        return text:sub(current, next_pos - 1)
    end
end

function M.codes(text)
    require_utf8(text, "text")

    local pos = 1
    local index = 0

    return function()
        if pos > #text then
            return nil
        end

        local codepoint, next_pos = decode_at(text, pos)
        index = index + 1
        pos = next_pos
        return index, codepoint
    end
end

function M.lower(text)
    return map_case(text, LCMAP_LOWERCASE)
end

function M.upper(text)
    return map_case(text, LCMAP_UPPERCASE)
end

function M.capitalize(text)
    require_utf8(text, "text")

    if text == "" then
        return ""
    end

    local first = M.sub(text, 1, 1)
    local rest = M.sub(text, 2)
    local mapped, err = M.upper(first)

    if not mapped then
        return nil, err
    end

    return mapped .. rest
end

function M.normalize(text, form)
    require_utf8(text, "text")

    form = form or "NFC"
    form = string.upper(form)

    local norm_form = NORMALIZATION_FORMS[form]
    if not norm_form then
        return nil, "normalization form must be NFC, NFD, NFKC or NFKD"
    end

    if not normaliz_ok then
        return nil, "Normaliz.dll is not available"
    end

    if text == "" then
        return ""
    end

    local wide, wide_len, err = utf8_to_wide(text)
    if not wide then
        return nil, err
    end

    local needed = normaliz.NormalizeString(norm_form, wide, wide_len, nil, 0)
    if needed <= 0 then
        return nil, "NormalizeString failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")"
    end

    for _ = 1, 4 do
        local normalized = ffi.new("su_wchar_t[?]", needed)
        local written = normaliz.NormalizeString(norm_form, wide, wide_len, normalized, needed)

        if written > 0 then
            return wide_to_utf8(normalized, written)
        end

        local win_error = tonumber(kernel32.GetLastError())
        if win_error ~= ERROR_INSUFFICIENT_BUFFER then
            return nil, "NormalizeString failed (Win32 error " .. win_error .. ")"
        end

        if written < 0 then
            needed = -written
        else
            needed = needed * 2
        end
    end

    return nil, "NormalizeString failed: destination size could not be determined"
end

function M.nfc(text)
    return M.normalize(text, "NFC")
end

function M.nfd(text)
    return M.normalize(text, "NFD")
end

function M.nfkc(text)
    return M.normalize(text, "NFKC")
end

function M.nfkd(text)
    return M.normalize(text, "NFKD")
end

function M.starts_with(text, prefix)
    require_utf8(text, "text")
    require_utf8(prefix, "prefix")
    return text:sub(1, #prefix) == prefix
end

function M.ends_with(text, suffix)
    require_utf8(text, "text")
    require_utf8(suffix, "suffix")
    return suffix == "" or text:sub(-#suffix) == suffix
end

function M.contains(text, needle)
    return M.find_plain(text, needle) ~= nil
end

function M.equals_ignore_case(left, right)
    require_utf8(left, "left")
    require_utf8(right, "right")

    local left_lower, left_err = M.lower(left)
    if not left_lower then
        return nil, left_err
    end

    local right_lower, right_err = M.lower(right)
    if not right_lower then
        return nil, right_err
    end

    return left_lower == right_lower
end

function M.find_plain(text, needle, init)
    require_utf8(text, "text")
    require_utf8(needle, "needle")

    local offsets, _, length = build_offsets(text)
    local start_index = normalize_search_index(init, length)

    if needle == "" then
        return start_index, start_index - 1
    end

    if start_index == length + 1 then
        return nil
    end

    local byte_init = offsets[start_index]
    local first_byte, last_byte = string.find(text, needle, byte_init, true)

    if not first_byte then
        return nil
    end

    local first_char = byte_to_char_index(text, first_byte)
    local after_char = byte_to_char_index(text, last_byte + 1)

    if not first_char or not after_char then
        return nil, "literal search ended inside a UTF-8 character"
    end

    return first_char, after_char - 1
end

function M.rfind(text, needle, init)
    require_utf8(text, "text")
    require_utf8(needle, "needle")

    local length = M.len(text)
    local limit = normalize_index(init, length, length)

    if limit < 1 then
        return nil
    end

    if limit > length then
        limit = length
    end

    if needle == "" then
        return limit + 1, limit
    end

    local last_first, last_last
    local search = 1

    while true do
        local first_index, last_index = M.find_plain(text, needle, search)
        if not first_index or first_index > limit then
            break
        end

        last_first = first_index
        last_last = last_index
        search = first_index + 1
    end

    return last_first, last_last
end

function M.find(text, pattern, init, plain)
    require_utf8(text, "text")
    require_utf8(pattern, "pattern")

    if plain then
        return M.find_plain(text, pattern, init)
    end

    local offsets, _, length = build_offsets(text)
    local start_index = normalize_search_index(init, length)
    local byte_init = offsets[start_index]
    local result = pack(string.find(text, pattern, byte_init, false))

    if result.n == 0 or result[1] == nil then
        return nil
    end

    local first_byte = result[1]
    local last_byte = result[2]

    if not is_boundary(text, first_byte) or not is_boundary(text, last_byte + 1) then
        return nil, "Lua patterns are byte-based and this pattern matched inside a UTF-8 character; use find_plain() for literal Unicode search"
    end

    local first_char = byte_to_char_index(text, first_byte)
    local after_char = byte_to_char_index(text, last_byte + 1)
    for index = 3, result.n do
        if type(result[index]) == "string" and not validate_utf8(result[index]) then
            return nil, "Lua patterns are byte-based and produced a partial UTF-8 character"
        end
    end
    result[1] = first_char
    result[2] = after_char - 1

    return unpack(result, 1, result.n)
end

function M.match(text, pattern, init)
    require_utf8(text, "text")
    require_utf8(pattern, "pattern")

    local offsets, _, length = build_offsets(text)
    local start_index = normalize_search_index(init, length)
    local result = pack(string.match(text, pattern, offsets[start_index]))

    if result.n == 0 or result[1] == nil then
        return nil
    end

    for index = 1, result.n do
        if type(result[index]) == "string" then
            local ok = validate_utf8(result[index])
            if not ok then
                return nil, "Lua patterns are byte-based and produced a partial UTF-8 character"
            end
        end
    end

    return unpack(result, 1, result.n)
end

function M.gmatch(text, pattern)
    require_utf8(text, "text")
    require_utf8(pattern, "pattern")

    local iterator = string.gmatch(text, pattern)

    return function()
        local result = pack(iterator())

        if result.n == 0 or result[1] == nil then
            return nil
        end

        for index = 1, result.n do
            if type(result[index]) == "string" then
                local ok = validate_utf8(result[index])
                if not ok then
                    error("Lua patterns are byte-based and produced a partial UTF-8 character; use chars() for Unicode character iteration", 2)
                end
            end
        end

        return unpack(result, 1, result.n)
    end
end

function M.gsub(text, pattern, replacement, limit)
    require_utf8(text, "text")
    require_utf8(pattern, "pattern")

    local result, count

    if limit == nil then
        result, count = string.gsub(text, pattern, replacement)
    else
        result, count = string.gsub(text, pattern, replacement, limit)
    end

    local ok = validate_utf8(result)
    if not ok then
        return nil, "Lua pattern replacement produced invalid UTF-8; use replace() for literal Unicode replacement"
    end

    return result, count
end

function M.replace(text, old_text, new_text, limit)
    require_utf8(text, "text")
    require_utf8(old_text, "old_text")
    require_utf8(new_text, "new_text")

    if old_text == "" then
        return nil, "old_text must not be empty"
    end

    if limit ~= nil and (type(limit) ~= "number" or limit ~= math.floor(limit) or limit < 0) then
        return nil, "limit must be a non-negative integer"
    end

    local result = {}
    local byte_pos = 1
    local count = 0

    while byte_pos <= #text do
        if limit ~= nil and count >= limit then
            break
        end

        local first_byte, last_byte = string.find(text, old_text, byte_pos, true)
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

function M.count(text, needle)
    require_utf8(text, "text")
    require_utf8(needle, "needle")

    if needle == "" then
        return nil, "needle must not be empty"
    end

    local count = 0
    local byte_pos = 1

    while byte_pos <= #text do
        local first_byte, last_byte = string.find(text, needle, byte_pos, true)
        if not first_byte then
            break
        end

        count = count + 1
        byte_pos = last_byte + 1
    end

    return count
end

function M.ltrim(text)
    require_utf8(text, "text")

    local offsets, codepoints, length = build_offsets(text)
    local first = 1

    while first <= length and is_unicode_space(codepoints[first]) do
        first = first + 1
    end

    if first > length then
        return ""
    end

    return text:sub(offsets[first])
end

function M.rtrim(text)
    require_utf8(text, "text")

    local offsets, codepoints, length = build_offsets(text)
    local last = length

    while last >= 1 and is_unicode_space(codepoints[last]) do
        last = last - 1
    end

    if last < 1 then
        return ""
    end

    return text:sub(1, offsets[last + 1] - 1)
end

function M.trim(text)
    return M.rtrim(M.ltrim(text))
end

-- sep is a literal set of Unicode characters. Empty fields are skipped.
function M.split(text, sep)
    require_utf8(text, "text")

    sep = sep or " "
    require_utf8(sep, "sep")

    if text == "" then
        return {}
    end

    local delimiters = {}
    for character in M.chars(sep) do
        delimiters[character] = true
    end

    local result = {}
    local current = {}

    for character in M.chars(text) do
        if delimiters[character] then
            if #current > 0 then
                result[#result + 1] = table.concat(current)
                current = {}
            end
        else
            current[#current + 1] = character
        end
    end

    if #current > 0 then
        result[#result + 1] = table.concat(current)
    end

    return result
end

-- Literal separator string. Empty fields are preserved.
function M.split_str(text, sep)
    require_utf8(text, "text")
    require_utf8(sep, "sep")

    if sep == "" then
        return { text }
    end

    local result = {}
    local byte_pos = 1

    while true do
        local first_byte, last_byte = string.find(text, sep, byte_pos, true)

        if not first_byte then
            result[#result + 1] = text:sub(byte_pos)
            break
        end

        result[#result + 1] = text:sub(byte_pos, first_byte - 1)
        byte_pos = last_byte + 1
    end

    return result
end

function M.join(values, sep)
    if type(values) ~= "table" then
        error("values must be a table", 2)
    end

    sep = sep or ""
    require_utf8(sep, "sep")

    local result = {}

    for index = 1, #values do
        local value = tostring(values[index])
        require_utf8(value, "values[" .. index .. "]")
        result[index] = value
    end

    return table.concat(result, sep)
end

function M.rep(text, count, separator)
    require_utf8(text, "text")

    if type(count) ~= "number" or count ~= math.floor(count) or count < 0 then
        error("count must be a non-negative integer", 2)
    end

    if separator == nil or separator == "" or count <= 1 then
        return string.rep(text, count)
    end

    require_utf8(separator, "separator")

    local result = {}
    for index = 1, count do
        result[index] = text
    end

    return table.concat(result, separator)
end

function M.pad_left(text, width, pad)
    require_utf8(text, "text")

    if type(width) ~= "number" or width ~= math.floor(width) or width < 0 then
        error("width must be a non-negative integer", 2)
    end

    pad = pad or " "
    local missing = width - M.len(text)

    if missing <= 0 then
        return text
    end

    return repeat_to_length(pad, missing) .. text
end

function M.pad_right(text, width, pad)
    require_utf8(text, "text")

    if type(width) ~= "number" or width ~= math.floor(width) or width < 0 then
        error("width must be a non-negative integer", 2)
    end

    pad = pad or " "
    local missing = width - M.len(text)

    if missing <= 0 then
        return text
    end

    return text .. repeat_to_length(pad, missing)
end

function M.center(text, width, pad)
    require_utf8(text, "text")

    if type(width) ~= "number" or width ~= math.floor(width) or width < 0 then
        error("width must be a non-negative integer", 2)
    end

    pad = pad or " "
    local missing = width - M.len(text)

    if missing <= 0 then
        return text
    end

    local left = math.floor(missing / 2)
    local right = missing - left
    return repeat_to_length(pad, left) .. text .. repeat_to_length(pad, right)
end

local function format_string_value(value, flags, width_text, precision_text)
    local text = tostring(value)
    require_utf8(text, "format value")

    if precision_text ~= "" then
        local precision = tonumber(precision_text:sub(2)) or 0
        text = M.sub(text, 1, precision)
    end

    local width = tonumber(width_text) or 0
    local text_len = M.len(text)

    if width > text_len then
        local padding = string.rep(" ", width - text_len)
        if flags:find("%-", 1, false) then
            text = text .. padding
        else
            text = padding .. text
        end
    end

    return text
end

function M.format(format_text, ...)
    require_utf8(format_text, "format")

    local args = pack(...)
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
                error("invalid format: unfinished conversion", 2)
            end

            if not conversion:match("[cdiouxXeEfgGqs]") then
                error("invalid format conversion %" .. conversion, 2)
            end

            if arg_index > args.n then
                error("not enough arguments for format", 2)
            end

            local value = args[arg_index]
            arg_index = arg_index + 1
            local spec = format_text:sub(percent, cursor)

            if conversion == "s" then
                result[#result + 1] = format_string_value(value, flags, width_text, precision_text)
            elseif conversion == "c" then
                local character = M.char(value)
                local width = tonumber(width_text) or 0

                if width > 1 then
                    if flags:find("%-", 1, false) then
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
        error("too many arguments for format", 2)
    end

    return table.concat(result)
end

function M.dump(func)
    return string.dump(func)
end

-- Extra high-level string helpers inspired by Python, C#, Java, Kotlin and Rust.

function M.is_empty(text)
    require_utf8(text, "text")
    return text == ""
end

function M.is_blank(text)
    require_utf8(text, "text")
    return M.trim(text) == ""
end

function M.char_at(text, index)
    require_utf8(text, "text")

    local length = M.len(text)
    local normalized = normalize_index(index, length, nil)

    if normalized < 1 or normalized > length then
        return nil
    end

    return M.sub(text, normalized, normalized)
end

function M.contains_ignore_case(text, needle)
    require_utf8(text, "text")
    require_utf8(needle, "needle")

    local left, left_err = M.lower(text)
    if not left then
        return nil, left_err
    end

    local right, right_err = M.lower(needle)
    if not right then
        return nil, right_err
    end

    return M.contains(left, right)
end

function M.starts_with_ignore_case(text, prefix)
    require_utf8(text, "text")
    require_utf8(prefix, "prefix")

    local left, left_err = M.lower(text)
    if not left then
        return nil, left_err
    end

    local right, right_err = M.lower(prefix)
    if not right then
        return nil, right_err
    end

    return M.starts_with(left, right)
end

function M.ends_with_ignore_case(text, suffix)
    require_utf8(text, "text")
    require_utf8(suffix, "suffix")

    local left, left_err = M.lower(text)
    if not left then
        return nil, left_err
    end

    local right, right_err = M.lower(suffix)
    if not right then
        return nil, right_err
    end

    return M.ends_with(left, right)
end

function M.remove_prefix(text, prefix)
    require_utf8(text, "text")
    require_utf8(prefix, "prefix")

    if prefix == "" or not M.starts_with(text, prefix) then
        return text
    end

    return text:sub(#prefix + 1)
end

function M.remove_suffix(text, suffix)
    require_utf8(text, "text")
    require_utf8(suffix, "suffix")

    if suffix == "" or not M.ends_with(text, suffix) then
        return text
    end

    return text:sub(1, #text - #suffix)
end

function M.partition(text, separator)
    require_utf8(text, "text")
    require_utf8(separator, "separator")

    if separator == "" then
        return nil, "separator must not be empty"
    end

    local first, last = M.find_plain(text, separator)
    if not first then
        return text, "", ""
    end

    return M.sub(text, 1, first - 1), separator, M.sub(text, last + 1)
end

function M.rpartition(text, separator)
    require_utf8(text, "text")
    require_utf8(separator, "separator")

    if separator == "" then
        return nil, "separator must not be empty"
    end

    local first, last = M.rfind(text, separator)
    if not first then
        return "", "", text
    end

    return M.sub(text, 1, first - 1), separator, M.sub(text, last + 1)
end

function M.words(text)
    require_utf8(text, "text")

    local offsets, codepoints, length = build_offsets(text)
    local result = {}
    local first = nil

    for index = 1, length do
        if is_unicode_space(codepoints[index]) then
            if first then
                result[#result + 1] = text:sub(offsets[first], offsets[index] - 1)
                first = nil
            end
        elseif not first then
            first = index
        end
    end

    if first then
        result[#result + 1] = text:sub(offsets[first], offsets[length + 1] - 1)
    end

    return result
end

function M.collapse_whitespace(text, replacement)
    require_utf8(text, "text")

    replacement = replacement == nil and " " or replacement
    require_utf8(replacement, "replacement")

    return M.join(M.words(text), replacement)
end

local function line_break_at(text, pos)
    local a, b, c = text:byte(pos, pos + 2)

    if a == 13 then
        if b == 10 then
            return pos + 2, "\r\n"
        end
        return pos + 1, "\r"
    end

    if a == 10 then
        return pos + 1, "\n"
    end

    if a == 11 then
        return pos + 1, "\v"
    end

    if a == 12 then
        return pos + 1, "\f"
    end

    if a == 28 or a == 29 or a == 30 then
        return pos + 1, string.char(a)
    end

    if a == 0xC2 and b == 0x85 then
        return pos + 2, "\194\133"
    end

    if a == 0xE2 and b == 0x80 and c == 0xA8 then
        return pos + 3, "\226\128\168"
    end

    if a == 0xE2 and b == 0x80 and c == 0xA9 then
        return pos + 3, "\226\128\169"
    end

    return nil
end

function M.split_lines(text, keep_ends)
    require_utf8(text, "text")

    if keep_ends ~= nil and type(keep_ends) ~= "boolean" then
        error("keep_ends must be boolean", 2)
    end

    if text == "" then
        return {}
    end

    local result = {}
    local start_pos = 1
    local pos = 1

    while pos <= #text do
        local next_pos, separator = line_break_at(text, pos)

        if next_pos then
            if keep_ends then
                result[#result + 1] = text:sub(start_pos, next_pos - 1)
            else
                result[#result + 1] = text:sub(start_pos, pos - 1)
            end

            start_pos = next_pos
            pos = next_pos
        else
            local _, char_next, err = decode_at(text, pos)
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

function M.insert(text, index, value)
    require_utf8(text, "text")
    require_utf8(value, "value")

    local length = M.len(text)
    local normalized = normalize_index(index, length, 1)

    if normalized < 1 or normalized > length + 1 then
        return nil, "index must be from 1 to string length + 1"
    end

    return M.sub(text, 1, normalized - 1) .. value .. M.sub(text, normalized)
end

function M.remove_range(text, first_index, last_index)
    require_utf8(text, "text")

    local length = M.len(text)
    local first = normalize_index(first_index, length, 1)
    local last = normalize_index(last_index, length, first)

    if first < 1 then
        first = 1
    end

    if last > length then
        last = length
    end

    if first > length or last < 1 or first > last then
        return text
    end

    return M.sub(text, 1, first - 1) .. M.sub(text, last + 1)
end

function M.replace_range(text, first_index, last_index, replacement)
    require_utf8(text, "text")
    require_utf8(replacement, "replacement")

    local length = M.len(text)
    local first = normalize_index(first_index, length, 1)
    local last = normalize_index(last_index, length, first)

    if first < 1 then
        first = 1
    end

    if last > length then
        last = length
    end

    if first > length + 1 or last < 0 or first > last + 1 then
        return nil, "invalid replacement range"
    end

    if first == length + 1 then
        return text .. replacement
    end

    return M.sub(text, 1, first - 1) .. replacement .. M.sub(text, last + 1)
end

function M.truncate(text, max_length, suffix)
    require_utf8(text, "text")

    if type(max_length) ~= "number"
        or max_length ~= math.floor(max_length)
        or max_length < 0 then
        error("max_length must be a non-negative integer", 2)
    end

    suffix = suffix == nil and "…" or suffix
    require_utf8(suffix, "suffix")

    local length = M.len(text)
    if length <= max_length then
        return text
    end

    if max_length == 0 then
        return ""
    end

    local suffix_length = M.len(suffix)
    if suffix_length >= max_length then
        return M.sub(suffix, 1, max_length)
    end

    return M.sub(text, 1, max_length - suffix_length) .. suffix
end

-- Unicode-oriented aliases. M.byte() returns Unicode code points, not raw UTF-8 bytes.
M.byte = M.codepoint

-- Explicit raw byte operations for binary data or protocol work.
M.raw_byte = string.byte
M.raw_char = string.char
M.raw_len = string.len
M.raw_sub = string.sub
M.raw_find = string.find
M.raw_match = string.match
M.raw_gmatch = string.gmatch
M.raw_gsub = string.gsub
M.raw_lower = string.lower
M.raw_upper = string.upper
M.raw_reverse = string.reverse
M.raw_rep = string.rep
M.raw_format = string.format

-- Capacity is in bytes, including the terminating NUL; this is a char buffer, not a WCHAR buffer.
function M.create_buffer(size)
    if type(size) ~= "number" or size ~= math.floor(size) or size < 1 or size > 2147483647 then
        return nil, "buffer size must be an integer from 1 to 2147483647"
    end

    local ok, data = pcall(ffi.new, "char[?]", size)
    if not ok then
        return nil, tostring(data)
    end

    return {
        data = data,
        size = size,

        set = function(self, text)
            if type(text) ~= "string" then
                return nil, "expected a string"
            end

            if text:find("\0", 1, true) then
                return nil, "embedded NUL is not allowed in a C string"
            end

            if #text >= size then
                return nil, "string does not fit in buffer (including NUL)"
            end

            ffi.copy(data, text, #text)
            data[#text] = 0
            return self
        end,

        tostring = function(self)
            local text = ffi.string(data, size)
            local nul = text:find("\0", 1, true)

            if not nul then
                return nil, "buffer is not NUL-terminated"
            end

            return text:sub(1, nul - 1)
        end
    }
end

return M
