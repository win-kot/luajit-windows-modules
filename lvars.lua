local ffi = require("ffi")

ffi.cdef [[
typedef struct {
    unsigned short wYear;
    unsigned short wMonth;
    unsigned short wDayOfWeek;
    unsigned short wDay;
    unsigned short wHour;
    unsigned short wMinute;
    unsigned short wSecond;
    unsigned short wMilliseconds;
} LVAR_SYSTEMTIME;

unsigned long __stdcall GetCurrentDirectoryW(
    unsigned long nBufferLength,
    unsigned short *lpBuffer
);

int __stdcall SetCurrentDirectoryW(
    const unsigned short *lpPathName
);

int __stdcall MultiByteToWideChar(
    unsigned int CodePage,
    unsigned long dwFlags,
    const char *lpMultiByteStr,
    int cbMultiByte,
    unsigned short *lpWideCharStr,
    int cchWideChar
);

int __stdcall WideCharToMultiByte(
    unsigned int CodePage,
    unsigned long dwFlags,
    const unsigned short *lpWideCharStr,
    int cchWideChar,
    char *lpMultiByteStr,
    int cbMultiByte,
    const char *lpDefaultChar,
    int *lpUsedDefaultChar
);

unsigned long __stdcall GetLastError(void);
void __stdcall GetLocalTime(LVAR_SYSTEMTIME *lpSystemTime);
void __stdcall GetSystemTime(LVAR_SYSTEMTIME *lpSystemTime);
unsigned long long __stdcall GetTickCount64(void);

unsigned long __stdcall GetModuleFileNameW(
    void *hModule,
    unsigned short *lpFilename,
    unsigned long nSize
);

int __stdcall GetDateFormatEx(
    const unsigned short *lpLocaleName,
    unsigned long dwFlags,
    const LVAR_SYSTEMTIME *lpDate,
    const unsigned short *lpFormat,
    unsigned short *lpDateStr,
    int cchDate,
    const unsigned short *lpCalendar
);

int __stdcall LCMapStringEx(
    const unsigned short *lpLocaleName,
    unsigned long dwMapFlags,
    const unsigned short *lpSrcStr,
    int cchSrc,
    unsigned short *lpDestStr,
    int cchDest,
    void *lpVersionInformation,
    void *lpReserved,
    intptr_t sortHandle
);

]]

local kernel32 = ffi.load("kernel32")

local M = {}
local static_values = {}

local CP_UTF8 = 65001
local MAX_PATH_CHARS = 32768

local function win32_error(operation_name)
    return operation_name .. " failed (Win32 error " .. tostring(tonumber(kernel32.GetLastError())) .. ")"
end

local function utf8_to_utf16(text_value)
    if type(text_value) ~= "string" then
        return nil, "string expected"
    end
    if text_value:find("\0", 1, true) then
        return nil, "string must not contain NUL"
    end

    if text_value == "" then
        local empty_wide = ffi.new("unsigned short[1]")
        empty_wide[0] = 0
        return empty_wide
    end

    local needed = kernel32.MultiByteToWideChar(
        CP_UTF8,
        8,
        text_value,
        #text_value,
        nil,
        0
    )

    if needed == 0 then
        return nil, win32_error("MultiByteToWideChar")
    end

    local wide_buf = ffi.new("unsigned short[?]", needed + 1)

    local written = kernel32.MultiByteToWideChar(
        CP_UTF8,
        8,
        text_value,
        #text_value,
        wide_buf,
        needed
    )

    if written ~= needed then
        return nil, win32_error("MultiByteToWideChar")
    end

    wide_buf[needed] = 0
    return wide_buf
end

local function utf16_to_utf8(wide_text, wide_length)
    if wide_length == 0 then
        return ""
    end

    local needed = kernel32.WideCharToMultiByte(
        CP_UTF8,
        0,
        wide_text,
        wide_length,
        nil,
        0,
        nil,
        nil
    )

    if needed == 0 then
        return nil, win32_error("WideCharToMultiByte")
    end

    local utf8_buf = ffi.new("char[?]", needed)

    local written = kernel32.WideCharToMultiByte(
        CP_UTF8,
        0,
        wide_text,
        wide_length,
        utf8_buf,
        needed,
        nil,
        nil
    )

    if written ~= needed then
        return nil, win32_error("WideCharToMultiByte")
    end

    return ffi.string(utf8_buf, needed)
end

local function normalize_path(path_value)
    return path_value:gsub("/", "\\")
end

local function get_working_dir()
    local needed = kernel32.GetCurrentDirectoryW(0, nil)

    if needed == 0 then
        return nil, win32_error("GetCurrentDirectoryW")
    end

    local wide_buf = ffi.new("unsigned short[?]", needed)
    local written = kernel32.GetCurrentDirectoryW(needed, wide_buf)

    if written == 0 or written >= needed then
        return nil, win32_error("GetCurrentDirectoryW")
    end

    return utf16_to_utf8(wide_buf, written)
end

local function set_working_dir(path_value)
    if type(path_value) ~= "string" or path_value == "" then
        return nil, "SetWorkingDir: non-empty path expected"
    end

    local wide_path, convert_err = utf8_to_utf16(path_value)

    if not wide_path then
        return nil, convert_err
    end

    -- Share literal-path handling and drive-relative CWD synchronization.
    local ok, err = require("win_native").chdir(path_value)
    if not ok then return nil, err end
    return true
end

local function get_executable_path()
    local buf_size = 512

    while buf_size <= MAX_PATH_CHARS do
        local wide_buf = ffi.new("unsigned short[?]", buf_size)
        local written = kernel32.GetModuleFileNameW(nil, wide_buf, buf_size)

        if written == 0 then
            return nil, win32_error("GetModuleFileNameW")
        end

        if written < buf_size then
            return utf16_to_utf8(wide_buf, written)
        end

        buf_size = buf_size * 2
    end

    return nil, "GetModuleFileNameW failed: executable path is too long"
end

local function get_script_args()
    local values = {}

    -- The Unicode-enabled LuaJIT build already exposes Windows arguments
    -- in arg[] as UTF-8. Positive indices are the script arguments.
    if type(arg) ~= "table" then
        return values
    end

    local index = 1

    while type(arg[index]) == "string" do
        values[index] = arg[index]
        index = index + 1
    end

    return values
end

local function get_local_time()
    local time_buf = ffi.new("LVAR_SYSTEMTIME[1]")
    kernel32.GetLocalTime(time_buf)
    return time_buf
end

local function get_utc_time()
    local time_buf = ffi.new("LVAR_SYSTEMTIME[1]")
    kernel32.GetSystemTime(time_buf)
    return time_buf
end

local function is_leap_year(year_value)
    return year_value % 4 == 0 and (year_value % 100 ~= 0 or year_value % 400 == 0)
end

local function day_of_year(year_value, month_value, day_value)
    local month_days = {
        31, 28, 31, 30, 31, 30,
        31, 31, 30, 31, 30, 31
    }

    if is_leap_year(year_value) then
        month_days[2] = 29
    end

    local result = day_value

    for month_index = 1, month_value - 1 do
        result = result + month_days[month_index]
    end

    return result
end

local function iso_weekday(year_value, month_value, day_value)
    local offsets = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
    local adjusted_year = year_value

    if month_value < 3 then
        adjusted_year = adjusted_year - 1
    end

    local sunday_zero = (
        adjusted_year
        + math.floor(adjusted_year / 4)
        - math.floor(adjusted_year / 100)
        + math.floor(adjusted_year / 400)
        + offsets[month_value]
        + day_value
    ) % 7

    if sunday_zero == 0 then
        return 7
    end

    return sunday_zero
end

local function iso_weeks_in_year(year_value)
    local january_first = iso_weekday(year_value, 1, 1)

    if january_first == 4 then
        return 53
    end

    if january_first == 3 and is_leap_year(year_value) then
        return 53
    end

    return 52
end

local function iso_year_week(year_value, month_value, day_value)
    local yday_value = day_of_year(year_value, month_value, day_value)
    local weekday_value = iso_weekday(year_value, month_value, day_value)
    local week_value = math.floor((yday_value - weekday_value + 10) / 7)
    local iso_year_value = year_value

    if week_value < 1 then
        iso_year_value = year_value - 1
        week_value = iso_weeks_in_year(iso_year_value)
    elseif week_value > iso_weeks_in_year(year_value) then
        iso_year_value = year_value + 1
        week_value = 1
    end

    return iso_year_value, week_value
end

local function locale_date_text(time_buf, format_text)
    local wide_format, convert_err = utf8_to_utf16(format_text)

    if not wide_format then
        return nil, convert_err
    end

    local needed = kernel32.GetDateFormatEx(
        nil,
        0,
        time_buf,
        wide_format,
        nil,
        0,
        nil
    )

    if needed == 0 then
        return nil, win32_error("GetDateFormatEx")
    end

    local wide_buf = ffi.new("unsigned short[?]", needed)
    local written = kernel32.GetDateFormatEx(
        nil,
        0,
        time_buf,
        wide_format,
        wide_buf,
        needed,
        nil
    )

    if written == 0 then
        return nil, win32_error("GetDateFormatEx")
    end

    return utf16_to_utf8(wide_buf, written - 1)
end

local function utf8_first_char_length(text_value)
    local first_byte = text_value:byte(1)

    if not first_byte then
        return 0
    end

    if first_byte < 0x80 then
        return 1
    end

    if first_byte < 0xE0 then
        return 2
    end

    if first_byte < 0xF0 then
        return 3
    end

    return 4
end

local function capitalize_locale_text(text_value)
    if text_value == "" then
        return text_value
    end

    local first_length = utf8_first_char_length(text_value)
    local first_text = text_value:sub(1, first_length)
    local wide_first, convert_err = utf8_to_utf16(first_text)

    if not wide_first then
        return nil, convert_err
    end

    local wide_result = ffi.new("unsigned short[4]")
    local mapped = kernel32.LCMapStringEx(
        nil,
        0x00000200,
        wide_first,
        -1,
        wide_result,
        4,
        nil,
        nil,
        0
    )

    if mapped == 0 then
        return nil, win32_error("LCMapStringEx")
    end

    local first_upper, upper_err = utf16_to_utf8(wide_result, mapped - 1)

    if not first_upper then
        return nil, upper_err
    end

    return first_upper .. text_value:sub(first_length + 1)
end

local function locale_label(time_buf, format_text, short_value)
    local text_value, text_err = locale_date_text(time_buf, format_text)

    if not text_value then
        return nil, text_err
    end

    if short_value then
        text_value = text_value:gsub("%.$", "")
    end

    return capitalize_locale_text(text_value)
end

local initial_working_dir, initial_err = get_working_dir()

if not initial_working_dir then
    error(initial_err)
end

local rt = require("runtime")
local jit_info = require("jit")
local executable_path = get_executable_path()

static_values.L_Args = get_script_args()
static_values.L_InitialWorkingDir = initial_working_dir
static_values.L_ScriptDir = rt.L_ScriptDir
static_values.L_ScriptName = rt.L_ScriptName
static_values.L_ScriptPath = rt.L_ScriptPath
static_values.L_ScriptFullPath = rt.L_ScriptPath
static_values.L_LuaJITVersion = jit_info.version
static_values.L_LuaJITPath = executable_path

function M.SetWorkingDir(path_value)
    return set_working_dir(path_value)
end

local function get_dynamic_value(key_value)
    if key_value == "L_WorkingDir" then
        local working_dir, get_err = get_working_dir()

        if not working_dir then
            error(get_err, 3)
        end

        return working_dir
    end

    if key_value == "L_TickCount" then
        return tonumber(kernel32.GetTickCount64())
    end

    local time_buf = get_local_time()
    local time_value = time_buf[0]
    local year_value = tonumber(time_value.wYear)
    local month_value = tonumber(time_value.wMonth)
    local day_value = tonumber(time_value.wDay)

    if key_value == "L_YYYY" or key_value == "L_Year" then
        return string.format("%04d", year_value)
    end

    if key_value == "L_MM" then
        return string.format("%02d", month_value)
    end

    if key_value == "L_DD" then
        return string.format("%02d", day_value)
    end

    if key_value == "L_Month" then
        local text_value, text_err = locale_label(time_buf, "MMMM", false)

        if not text_value then
            error(text_err, 3)
        end

        return text_value
    end

    if key_value == "L_MonthShort" then
        local text_value, text_err = locale_label(time_buf, "MMM", true)

        if not text_value then
            error(text_err, 3)
        end

        return text_value
    end

    if key_value == "L_Day" then
        local text_value, text_err = locale_label(time_buf, "dddd", false)

        if not text_value then
            error(text_err, 3)
        end

        return text_value
    end

    if key_value == "L_DayShort" then
        local text_value, text_err = locale_label(time_buf, "ddd", true)

        if not text_value then
            error(text_err, 3)
        end

        return text_value
    end

    if key_value == "L_WDay" then
        local windows_wday = tonumber(time_value.wDayOfWeek)

        if windows_wday == 0 then
            return 7
        end

        return windows_wday
    end

    if key_value == "L_YDay" then
        return day_of_year(year_value, month_value, day_value)
    end

    if key_value == "L_Week" then
        local _, week_value = iso_year_week(
            year_value,
            month_value,
            day_value
        )

        return week_value
    end

    if key_value == "L_Hour" then
        return string.format("%02d", tonumber(time_value.wHour))
    end

    if key_value == "L_Min" then
        return string.format("%02d", tonumber(time_value.wMinute))
    end

    if key_value == "L_Sec" then
        return string.format("%02d", tonumber(time_value.wSecond))
    end

    if key_value == "L_MSec" then
        return tonumber(time_value.wMilliseconds)
    end

    if key_value == "L_Now" then
        return string.format(
            "%04d%02d%02d%02d%02d%02d",
            year_value,
            month_value,
            day_value,
            tonumber(time_value.wHour),
            tonumber(time_value.wMinute),
            tonumber(time_value.wSecond)
        )
    end

    if key_value == "L_NowUTC" then
        local utc_buf = get_utc_time()
        local utc_value = utc_buf[0]

        return string.format(
            "%04d%02d%02d%02d%02d%02d",
            tonumber(utc_value.wYear),
            tonumber(utc_value.wMonth),
            tonumber(utc_value.wDay),
            tonumber(utc_value.wHour),
            tonumber(utc_value.wMinute),
            tonumber(utc_value.wSecond)
        )
    end

    return nil
end

setmetatable(M, {
    __index = function(_, key_value)
        local static_value = static_values[key_value]

        if static_value ~= nil then
            return static_value
        end

        return get_dynamic_value(key_value)
    end,

    __newindex = function(_, key_value, new_value)
        if key_value == "L_WorkingDir" then
            local ok, set_err = set_working_dir(new_value)

            if not ok then
                error(set_err, 2)
            end

            return
        end

        if type(key_value) == "string" and key_value:sub(1, 2) == "L_" then
            error(key_value .. " is read-only", 2)
        end

        rawset(M, key_value, new_value)
    end
})

return M
