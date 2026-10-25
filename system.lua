local ffi = require("ffi")
local native = require("win_native")

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

typedef struct {
    uint32_t Data1;
    uint16_t Data2;
    uint16_t Data3;
    uint8_t Data4[8];
} LJ_SYSTEM_GUID;

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


uint32_t __stdcall GetWindowsDirectoryW(
    uint16_t *lpBuffer,
    uint32_t uSize
);

uint32_t __stdcall GetSystemDirectoryW(
    uint16_t *lpBuffer,
    uint32_t uSize
);



uint32_t __stdcall GetLogicalDrives(void);

uint32_t __stdcall GetDriveTypeW(
    const uint16_t *lpRootPathName
);

int __stdcall GetDiskFreeSpaceExW(
    const uint16_t *lpDirectoryName,
    uint64_t *lpFreeBytesAvailableToCaller,
    uint64_t *lpTotalNumberOfBytes,
    uint64_t *lpTotalNumberOfFreeBytes
);

int __stdcall GetVolumeInformationW(
    const uint16_t *lpRootPathName,
    uint16_t *lpVolumeNameBuffer,
    uint32_t nVolumeNameSize,
    uint32_t *lpVolumeSerialNumber,
    uint32_t *lpMaximumComponentLength,
    uint32_t *lpFileSystemFlags,
    uint16_t *lpFileSystemNameBuffer,
    uint32_t nFileSystemNameSize
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

int32_t __stdcall SHGetKnownFolderPath(
    const LJ_SYSTEM_GUID *rfid,
    uint32_t dwFlags,
    void *hToken,
    uint16_t **ppszPath
);

void __stdcall CoTaskMemFree(
    void *pv
);
]]

local kernel32 = ffi.load("kernel32")
local advapi32 = ffi.load("advapi32")
local user32 = ffi.load("user32")
local gdi32 = ffi.load("gdi32")
local hasDpi, getDpi = pcall(function() return user32.GetDpiForSystem end)
local ntdll = ffi.load("ntdll")
local shell32 = ffi.load("shell32")
local ole32 = ffi.load("ole32")

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

local DRIVE_UNKNOWN = 0
local DRIVE_NO_ROOT_DIR = 1
local DRIVE_REMOVABLE = 2
local DRIVE_FIXED = 3
local DRIVE_REMOTE = 4
local DRIVE_CDROM = 5
local DRIVE_RAMDISK = 6

local DRIVE_TYPES = {
    [DRIVE_UNKNOWN] = "unknown",
    [DRIVE_NO_ROOT_DIR] = "no_root",
    [DRIVE_REMOVABLE] = "removable",
    [DRIVE_FIXED] = "fixed",
    [DRIVE_REMOTE] = "network",
    [DRIVE_CDROM] = "cdrom",
    [DRIVE_RAMDISK] = "ramdisk"
}


-- ============================================================
-- Unicode
-- ============================================================

local function utf8_to_wide(text)
    if text == nil then
        return nil
    end

    text = tostring(text)

    if text == "" then
        return ffi.new("uint16_t[1]")
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
        return nil
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
        return nil
    end

    wideBuf[wideLength] = 0

    return wideBuf
end


local function wide_to_utf8(
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
-- Errors
-- ============================================================

local function error_message(errorCode)
    errorCode =
        errorCode
        or tonumber(
            kernel32.GetLastError()
        )

    local errorBuf =
        ffi.new(
            "uint16_t[2048]"
        )

    local length =
        kernel32.FormatMessageW(
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

    local text =
        wide_to_utf8(
            errorBuf,
            tonumber(length)
        )

    if not text then
        return "Win32 error "
            .. tostring(errorCode)
    end

    text =
        text:gsub(
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
-- GUID
-- ============================================================

local function make_guid(
    data1,
    data2,
    data3,
    b1,
    b2,
    b3,
    b4,
    b5,
    b6,
    b7,
    b8
)
    local guidObj =
        ffi.new(
            "LJ_SYSTEM_GUID[1]"
        )

    guidObj[0].Data1 = data1
    guidObj[0].Data2 = data2
    guidObj[0].Data3 = data3

    guidObj[0].Data4[0] = b1
    guidObj[0].Data4[1] = b2
    guidObj[0].Data4[2] = b3
    guidObj[0].Data4[3] = b4
    guidObj[0].Data4[4] = b5
    guidObj[0].Data4[5] = b6
    guidObj[0].Data4[6] = b7
    guidObj[0].Data4[7] = b8

    return guidObj
end


-- ============================================================
-- Known folder GUIDs
-- ============================================================

local KNOWN_FOLDERS = {
    desktop = make_guid(
        0xB4BFCC3A,
        0xDB2C,
        0x424C,
        0xB0,
        0x29,
        0x7F,
        0xE9,
        0x9A,
        0x87,
        0xC6,
        0x41
    ),

    documents = make_guid(
        0xFDD39AD0,
        0x238F,
        0x46AF,
        0xAD,
        0xB4,
        0x6C,
        0x85,
        0x48,
        0x03,
        0x69,
        0xC7
    ),

    downloads = make_guid(
        0x374DE290,
        0x123F,
        0x4565,
        0x91,
        0x64,
        0x39,
        0xC4,
        0x92,
        0x5E,
        0x46,
        0x7B
    ),

    profile = make_guid(
        0x5E6C858F,
        0x0E22,
        0x4760,
        0x9A,
        0xFE,
        0xEA,
        0x33,
        0x17,
        0xB6,
        0x71,
        0x73
    ),

    appdata = make_guid(
        0x3EB685DB,
        0x65F9,
        0x4CF6,
        0xA0,
        0x3A,
        0xE3,
        0xEF,
        0x65,
        0x72,
        0x9F,
        0x3D
    ),

    localappdata = make_guid(
        0xF1B32785,
        0x6FBA,
        0x4FCF,
        0x9D,
        0x55,
        0x7B,
        0x8E,
        0x7F,
        0x15,
        0x70,
        0x91
    ),

    programdata = make_guid(
        0x62AB5D82,
        0xFDC1,
        0x4DC3,
        0xA9,
        0xDD,
        0x07,
        0x0D,
        0x1D,
        0x49,
        0x5D,
        0x97
    ),

    programfiles = make_guid(
        0x905E63B6,
        0xC1BF,
        0x494E,
        0xB2,
        0x9C,
        0x65,
        0xB7,
        0x32,
        0xD3,
        0xD2,
        0x1A
    ),

    programfilesx86 = make_guid(
        0x7C5A40EF,
        0xA0FB,
        0x4BFC,
        0x87,
        0x4A,
        0xC0,
        0xF2,
        0xE0,
        0xB9,
        0xFA,
        0x8E
    )
}


-- ============================================================
-- User name
-- ============================================================

function system.getUserName()
    local sizeBuf =
        ffi.new(
            "uint32_t[1]",
            32768
        )

    local nameBuf =
        ffi.new(
            "uint16_t[32768]"
        )

    if advapi32.GetUserNameW(
            nameBuf,
            sizeBuf
        ) == 0 then
        return nil,
            win_error(
                "GetUserNameW failed"
            )
    end

    local length =
        tonumber(sizeBuf[0])

    if length > 0 then
        length = length - 1
    end

    return wide_to_utf8(
        nameBuf,
        length
    )
end

-- ============================================================
-- Computer name
-- ============================================================

function system.getComputerName()
    local sizeBuf =
        ffi.new(
            "uint32_t[1]",
            32768
        )

    local nameBuf =
        ffi.new(
            "uint16_t[32768]"
        )

    if kernel32.GetComputerNameW(
            nameBuf,
            sizeBuf
        ) == 0 then
        return nil,
            win_error(
                "GetComputerNameW failed"
            )
    end

    return wide_to_utf8(
        nameBuf,
        tonumber(sizeBuf[0])
    )
end

-- ============================================================
-- Windows version
-- ============================================================

function system.getWindowsVersion()
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
        return nil,
            "RtlGetVersion failed: "
            .. tostring(status)
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

    local servicePack =
        wide_to_utf8(
            versionObj[0].szCSDVersion
        )

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

        servicePack =
            servicePack or ""
    }
end

-- ============================================================
-- Executable path
-- ============================================================

function system.getExePath()
    return native.exepath()
end

-- ============================================================
-- Windows directory
-- ============================================================

function system.getWindowsPath()
    local pathBuf =
        ffi.new(
            "uint16_t[32768]"
        )

    local length =
        kernel32.GetWindowsDirectoryW(
            pathBuf,
            32768
        )

    if length == 0
        or length >= 32768
    then
        return nil,
            win_error(
                "GetWindowsDirectoryW failed"
            )
    end

    return wide_to_utf8(
        pathBuf,
        tonumber(length)
    )
end

-- ============================================================
-- System32 directory
-- ============================================================

function system.getSystemPath()
    local pathBuf =
        ffi.new(
            "uint16_t[32768]"
        )

    local length =
        kernel32.GetSystemDirectoryW(
            pathBuf,
            32768
        )

    if length == 0
        or length >= 32768
    then
        return nil,
            win_error(
                "GetSystemDirectoryW failed"
            )
    end

    return wide_to_utf8(
        pathBuf,
        tonumber(length)
    )
end

-- ============================================================
-- Temporary directory
-- ============================================================

function system.getTempPath()
    local path, err = native.os_tmpdir()
    if not path then return nil, err end
    return path:gsub('[\\/]+$', '') .. '\\'
end

-- ============================================================
-- Current directory
-- ============================================================

function system.getCurrentDirectory()
    return native.cwd()
end

-- ============================================================
-- Known folder
-- ============================================================

function system.getKnownFolder(name)
    if name == nil then
        return nil,
            "folder name cannot be nil"
    end

    local folderName =
        tostring(name):lower()

    local folderGuid =
        KNOWN_FOLDERS[folderName]

    if folderGuid == nil then
        return nil,
            "unknown known folder: "
            .. tostring(name)
    end

    local pathPtr =
        ffi.new(
            "uint16_t *[1]"
        )

    local result =
        shell32.SHGetKnownFolderPath(
            folderGuid,
            0,
            nil,
            pathPtr
        )

    local allocatedPtr =
        pathPtr[0]

    if result ~= 0 then
        if allocatedPtr ~= nil
            and allocatedPtr ~= ffi.NULL
        then
            ole32.CoTaskMemFree(
                allocatedPtr
            )
        end

        return nil,
            string.format(
                "SHGetKnownFolderPath failed: 0x%08X",
                tonumber(
                    ffi.cast(
                        "uint32_t",
                        result
                    )
                )
            )
    end

    local path =
        wide_to_utf8(
            allocatedPtr
        )

    ole32.CoTaskMemFree(
        allocatedPtr
    )

    return path
end

function system.getDesktopPath()
    return system.getKnownFolder(
        "desktop"
    )
end

function system.getDocumentsPath()
    return system.getKnownFolder(
        "documents"
    )
end

function system.getDownloadsPath()
    return system.getKnownFolder(
        "downloads"
    )
end

function system.getProfilePath()
    return system.getKnownFolder(
        "profile"
    )
end

function system.getAppDataPath()
    return system.getKnownFolder(
        "appdata"
    )
end

function system.getLocalAppDataPath()
    return system.getKnownFolder(
        "localappdata"
    )
end

function system.getProgramDataPath()
    return system.getKnownFolder(
        "programdata"
    )
end

function system.getProgramFilesPath()
    return system.getKnownFolder(
        "programfiles"
    )
end

function system.getProgramFilesX86Path()
    return system.getKnownFolder(
        "programfilesx86"
    )
end

-- ============================================================
-- Disk information
-- ============================================================

local function get_drive_info(rootPath)
    local rootWide =
        utf8_to_wide(
            rootPath
        )

    if rootWide == nil then
        return nil,
            "invalid drive path"
    end

    local driveTypeId =
        tonumber(
            kernel32.GetDriveTypeW(
                rootWide
            )
        )

    local driveInfo = {
        path = rootPath,

        type =
            DRIVE_TYPES[driveTypeId]
            or "unknown",

        typeId = driveTypeId
    }

    local freeAvailable =
        ffi.new("uint64_t[1]")

    local totalBytes =
        ffi.new("uint64_t[1]")

    local totalFree =
        ffi.new("uint64_t[1]")

    if kernel32.GetDiskFreeSpaceExW(
            rootWide,
            freeAvailable,
            totalBytes,
            totalFree
        ) ~= 0 then
        driveInfo.total =
            tonumber(
                totalBytes[0]
            )

        driveInfo.free =
            tonumber(
                totalFree[0]
            )

        driveInfo.available =
            tonumber(
                freeAvailable[0]
            )

        driveInfo.used =
            driveInfo.total
            - driveInfo.free
    end

    local volumeBuf =
        ffi.new(
            "uint16_t[1024]"
        )

    local fsBuf =
        ffi.new(
            "uint16_t[256]"
        )

    local serialBuf =
        ffi.new(
            "uint32_t[1]"
        )

    local maxComponentBuf =
        ffi.new(
            "uint32_t[1]"
        )

    local flagsBuf =
        ffi.new(
            "uint32_t[1]"
        )

    if kernel32.GetVolumeInformationW(
            rootWide,
            volumeBuf,
            1024,
            serialBuf,
            maxComponentBuf,
            flagsBuf,
            fsBuf,
            256
        ) ~= 0 then
        driveInfo.label =
            wide_to_utf8(
                volumeBuf
            )

        driveInfo.fileSystem =
            wide_to_utf8(
                fsBuf
            )

        driveInfo.serial =
            tonumber(
                serialBuf[0]
            )
    end

    return driveInfo
end


function system.getDrives()
    local mask =
        tonumber(
            kernel32.GetLogicalDrives()
        )

    if mask == 0 then
        return nil,
            win_error(
                "GetLogicalDrives failed"
            )
    end

    local result = {}

    for index = 0, 25 do
        local power =
            2 ^ index

        if mask % (power * 2) >= power then
            local letter =
                string.char(
                    string.byte("A")
                    + index
                )

            local rootPath =
                letter .. ":\\"

            local driveInfo =
                get_drive_info(
                    rootPath
                )

            result[#result + 1] =
                driveInfo
        end
    end

    return result
end

function system.getDrive(path)
    if path == nil then
        return nil,
            "path cannot be nil"
    end

    local text =
        tostring(path)

    local letter =
        text:match(
            "^([A-Za-z]):"
        )

    if not letter then
        return nil,
            "path does not contain a drive letter"
    end

    return get_drive_info(
        letter:upper()
        .. ":\\"
    )
end

-- ============================================================
-- Memory
-- ============================================================

function system.getMemory()
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
        return nil,
            win_error(
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

function system.getScreen()
    local dpi, err = system.getDpi()
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

function system.getDpi()
    if hasDpi then return tonumber(getDpi()) end
    local dc = user32.GetDC(nil)
    if dc == nil then return nil, "GetDC failed" end
    local dpi = tonumber(gdi32.GetDeviceCaps(dc, 88)) -- LOGPIXELSX
    user32.ReleaseDC(nil, dc)
    if dpi <= 0 then return nil, "GetDeviceCaps failed" end
    return dpi
end

function system.getScale()
    local dpi, err = system.getDpi()
    if not dpi then return nil, err end
    return dpi / 96
end

-- ============================================================
-- Uptime
-- ============================================================

function system.getUptime()
    local seconds, err = native.uptime()
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

return system
