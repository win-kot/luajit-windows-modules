local ffi = require("ffi")
local native = require("_win_native")
local errors = require("_errors")

ffi.cdef [[
typedef struct {
    uint32_t dwOSVersionInfoSize;
    uint32_t dwMajorVersion;
    uint32_t dwMinorVersion;
    uint32_t dwBuildNumber;
    uint32_t dwPlatformId;
    uint16_t szCSDVersion[128];
} LJ_SYSTEM_OSVERSIONINFO;

typedef struct {
    uint32_t dwLength;
    uint32_t dwMemoryLoad;
    uint64_t ullTotalPhys;
    uint64_t ullAvailPhys;
    uint64_t ullTotalPageFile;
    uint64_t ullAvailPageFile;
    uint64_t ullTotalVirtual;
    uint64_t ullAvailVirtual;
    uint64_t ullAvailExtendedVirtual;
} LJ_SYSTEM_MEMORYSTATUSEX;



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
int __stdcall Beep(uint32_t dwFreq, uint32_t dwDuration);

uint32_t __stdcall FormatMessageW(
    uint32_t dwFlags,
    const void *lpSource,
    uint32_t dwMessageId,
    uint32_t dwLanguageId,
    uint16_t *lpBuffer,
    uint32_t nSize,
    void *Arguments
);

int __stdcall GetUserNameW(
    uint16_t *lpBuffer,
    uint32_t *pcbBuffer
);

int __stdcall GetComputerNameW(
    uint16_t *lpBuffer,
    uint32_t *nSize
);


int __stdcall GlobalMemoryStatusEx(
    LJ_SYSTEM_MEMORYSTATUSEX *lpBuffer
);

int __stdcall GetSystemMetrics(
    int nIndex
);

uint32_t __stdcall GetDpiForSystem(void);
void * __stdcall GetDC(void *);
int __stdcall ReleaseDC(void *, void *);
int __stdcall GetDeviceCaps(void *, int);


int32_t __stdcall RtlGetVersion(
    LJ_SYSTEM_OSVERSIONINFO *lpVersionInformation
);

]]

local kernel32 = ffi.load("kernel32")
local advapi32 = ffi.load("advapi32")
local user32 = ffi.load("user32")
local gdi32 = ffi.load("gdi32")
local hasDpi, getDpi = pcall(function() return user32.GetDpiForSystem end)
local ntdll = ffi.load("ntdll")

local system = {}

local CP_UTF8 = 65001
local MB_ERR_INVALID_CHARS = 0x00000008

local FORMAT_MESSAGE_IGNORE_INSERTS = 0x00000200
local FORMAT_MESSAGE_FROM_SYSTEM = 0x00001000

local SM_CXSCREEN = 0
local SM_CYSCREEN = 1
local SM_XVIRTUALSCREEN = 76
local SM_YVIRTUALSCREEN = 77
local SM_CXVIRTUALSCREEN = 78
local SM_CYVIRTUALSCREEN = 79
local SM_CMONITORS = 80

local function WideToUtf8(
    widePtr,
    wideLength
)
    if widePtr == nil then
        return ""
    end

    if wideLength == nil then
        local index = 0

        while widePtr[index] ~= 0 do
            index = index + 1
        end

        wideLength = index
    end

    if wideLength == 0 then
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
        return errors.Win32("WideCharToMultiByte", tonumber(kernel32.GetLastError()))
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
        return errors.Win32("WideCharToMultiByte", tonumber(kernel32.GetLastError()))
    end

    return ffi.string(
        utf8Buf,
        utf8Length
    )
end


-- ============================================================
-- Errors
-- ============================================================

local WinError = require("_errors").Win32

function system.UserNameGet()
    local sizeBuf = ffi.new("uint32_t[1]", 256)
    local nameBuf = ffi.new("uint16_t[256]")
    local result = advapi32.GetUserNameW(nameBuf, sizeBuf)
    -- Keep buffers private to the call and grow within the previous limit.
    if result == 0 and sizeBuf[0] > 256 and sizeBuf[0] <= 32768 then
        nameBuf = ffi.new("uint16_t[?]", sizeBuf[0])
        result = advapi32.GetUserNameW(nameBuf, sizeBuf)
    end
    if result == 0 then return WinError("GetUserNameW failed") end
    local length = tonumber(sizeBuf[0])
    if length > 0 then length = length - 1 end
    return WideToUtf8(nameBuf, length)
end

-- ============================================================
-- Computer name
-- ============================================================

function system.ComputerNameGet()
    local sizeBuf = ffi.new("uint32_t[1]", 256)
    local nameBuf = ffi.new("uint16_t[256]")
    local result = kernel32.GetComputerNameW(nameBuf, sizeBuf)
    -- Keep buffers private to the call and grow within the previous limit.
    if result == 0 and sizeBuf[0] > 256 and sizeBuf[0] <= 32768 then
        nameBuf = ffi.new("uint16_t[?]", sizeBuf[0])
        result = kernel32.GetComputerNameW(nameBuf, sizeBuf)
    end
    if result == 0 then return WinError("GetComputerNameW failed") end
    local length = tonumber(sizeBuf[0])
    return WideToUtf8(nameBuf, length)
end

-- ============================================================
-- Windows version
-- ============================================================

function system.WindowsVersionGet()
    local versionObj =
        ffi.new(
            "LJ_SYSTEM_OSVERSIONINFO[1]"
        )

    versionObj[0].dwOSVersionInfoSize =
        ffi.sizeof(
            "LJ_SYSTEM_OSVERSIONINFO"
        )

    local status =
        ntdll.RtlGetVersion(
            versionObj
        )

    if status ~= 0 then
        return errors.Status("RtlGetVersion", "NTSTATUS", tonumber(status))
    end

    local major =
        tonumber(
            versionObj[0].dwMajorVersion
        )

    local minor =
        tonumber(
            versionObj[0].dwMinorVersion
        )

    local build =
        tonumber(
            versionObj[0].dwBuildNumber
        )

    local name

    if major == 10
        and build >= 22000
    then
        name = "Windows 11"
    elseif major == 10 then
        name = "Windows 10"
    else
        name =
            "Windows "
            .. tostring(major)
            .. "."
            .. tostring(minor)
    end

    local servicePack, err, code =
        WideToUtf8(
            versionObj[0].szCSDVersion
        )
    if servicePack == nil then return nil, err, code end

    return {
        name = name,

        major = major,
        minor = minor,
        build = build,

        version =
            tostring(major)
            .. "."
            .. tostring(minor)
            .. "."
            .. tostring(build),

        servicePack = servicePack
    }
end

-- ============================================================
-- Executable path
-- ============================================================

function system.ExePathGet()
    return native.ExePath()
end

-- ============================================================
-- Windows directory
-- ============================================================

function system.MemoryGet()
    local memoryObj =
        ffi.new(
            "LJ_SYSTEM_MEMORYSTATUSEX[1]"
        )

    memoryObj[0].dwLength =
        ffi.sizeof(
            "LJ_SYSTEM_MEMORYSTATUSEX"
        )

    if kernel32.GlobalMemoryStatusEx(
            memoryObj
        ) == 0 then
        return WinError(
                "GlobalMemoryStatusEx failed"
            )
    end

    return {
        load =
            tonumber(
                memoryObj[0].dwMemoryLoad
            ),

        totalPhysical =
            tonumber(
                memoryObj[0].ullTotalPhys
            ),

        availablePhysical =
            tonumber(
                memoryObj[0].ullAvailPhys
            ),

        usedPhysical =
            tonumber(
                memoryObj[0].ullTotalPhys
            )
            - tonumber(
                memoryObj[0].ullAvailPhys
            ),

        totalPageFile =
            tonumber(
                memoryObj[0].ullTotalPageFile
            ),

        availablePageFile =
            tonumber(
                memoryObj[0].ullAvailPageFile
            ),

        totalVirtual =
            tonumber(
                memoryObj[0].ullTotalVirtual
            ),

        availableVirtual =
            tonumber(
                memoryObj[0].ullAvailVirtual
            )
    }
end

-- ============================================================
-- Screen
-- ============================================================

function system.ScreenGet()
    local dpi, err = system.DpiGet()
    if not dpi then return nil, err end

    return {
        width =
            user32.GetSystemMetrics(
                SM_CXSCREEN
            ),

        height =
            user32.GetSystemMetrics(
                SM_CYSCREEN
            ),

        virtualX =
            user32.GetSystemMetrics(
                SM_XVIRTUALSCREEN
            ),

        virtualY =
            user32.GetSystemMetrics(
                SM_YVIRTUALSCREEN
            ),

        virtualWidth =
            user32.GetSystemMetrics(
                SM_CXVIRTUALSCREEN
            ),

        virtualHeight =
            user32.GetSystemMetrics(
                SM_CYVIRTUALSCREEN
            ),

        monitors =
            user32.GetSystemMetrics(
                SM_CMONITORS
            ),

        dpi = dpi,

        scale =
            dpi / 96
    }
end

-- ============================================================
-- DPI
-- ============================================================

function system.DpiGet()
    if hasDpi then return tonumber(getDpi()) end
    local dc = user32.GetDC(nil)
    if dc == nil then return nil, "GetDC failed" end
    local dpi = tonumber(gdi32.GetDeviceCaps(dc, 88)) -- LOGPIXELSX
    user32.ReleaseDC(nil, dc)
    if dpi <= 0 then return nil, "GetDeviceCaps failed" end
    return dpi
end

function system.ScaleGet()
    local dpi, err = system.DpiGet()
    if not dpi then return nil, err end
    return dpi / 96
end

-- ============================================================
-- Uptime
-- ============================================================

function system.UptimeGet()
    local seconds, err = native.Uptime()
    if not seconds then return nil, err end
    local milliseconds = seconds * 1000

    return {
        milliseconds =
            milliseconds,

        seconds =
            milliseconds / 1000,

        minutes =
            milliseconds / 60000,

        hours =
            milliseconds / 3600000,

        days =
            milliseconds / 86400000
    }
end

-- Synchronous tone: frequency in Hz, duration in milliseconds.
function system.Beep(freq, duration)
    if type(freq) ~= "number" or freq ~= math.floor(freq)
        or freq < 37 or freq > 32767 then
        return nil, "frequency must be an integer from 37 to 32767 Hz"
    end
    if type(duration) ~= "number" or duration ~= math.floor(duration)
        or duration < 0 or duration > 4294967295 then
        return nil, "duration must be an integer from 0 to 4294967295 ms"
    end
    if kernel32.Beep(freq, duration) == 0 then
        return WinError("Beep failed")
    end
    return true
end

do
    local win = require("_win_extension")
    ffi.cdef[[
    typedef struct {
        uint8_t ac, flags, percent, saver;
        uint32_t lifeSeconds, fullLifeSeconds;
    } fw_power_status;
    int __stdcall GetSystemPowerStatus(fw_power_status *);
    ]]
    function system.PowerStatusGet()
        local data = ffi.new("fw_power_status[1]")
        if kernel32.GetSystemPowerStatus(data) == 0 then return win.Error("GetSystemPowerStatus") end
        local power = data[0]
        local status = {
            ac = ({[0] = "offline", [1] = "online"})[power.ac] or "unknown",
            battery = power.flags == 255 and "unknown" or (power.flags >= 128 and "absent" or "present"),
            batterySaver = power.saver ~= 0
        }
        if power.flags ~= 255 then status.batteryFlags = power.flags end
        if power.percent <= 100 then status.percent = power.percent end
        if power.lifeSeconds ~= 0xFFFFFFFF then status.lifeSeconds = power.lifeSeconds end
        if power.fullLifeSeconds ~= 0xFFFFFFFF then status.fullLifeSeconds = power.fullLifeSeconds end
        return status
    end
end

return system
