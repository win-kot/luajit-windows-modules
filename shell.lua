local ffi = require("ffi")

ffi.cdef [[
int __stdcall MultiByteToWideChar(
    uint32_t CodePage,
    uint32_t dwFlags,
    const char *lpMultiByteStr,
    int cbMultiByte,
    uint16_t *lpWideCharStr,
    int cchWideChar
);

void * __stdcall ShellExecuteW(
    void *hwnd,
    const uint16_t *lpOperation,
    const uint16_t *lpFile,
    const uint16_t *lpParameters,
    const uint16_t *lpDirectory,
    int nShowCmd
);

typedef struct {
    const uint16_t *pcszFile;
    const uint16_t *pcszClass;
    uint32_t oaifInFlags;
} LJ_SHELL_OPENASINFO;

int32_t __stdcall SHOpenWithDialog(
    void *hwndParent,
    const LJ_SHELL_OPENASINFO *poainfo
);
]]

local kernel32 = ffi.load("kernel32")
local shell32 = ffi.load("shell32")

local shell = {}

local CP_UTF8 = 65001
local MB_ERR_INVALID_CHARS = 0x00000008

local SW_HIDE = 0
local SW_SHOWNORMAL = 1
local SW_SHOWMINIMIZED = 2
local SW_SHOWMAXIMIZED = 3
local SW_SHOWNOACTIVATE = 4
local SW_SHOW = 5
local SW_SHOWMINNOACTIVE = 7
local SW_SHOWDEFAULT = 10

local OAIF_EXEC = 0x00000004


-- ============================================================
-- UTF-8 -> UTF-16
-- ============================================================

local function utf8_to_wide(text)
    if text == nil then
        return nil
    end

    text = tostring(text)

    if text:find("\0", 1, true) then
        return nil
    end

    if text == "" then
        local wideBuf = ffi.new("uint16_t[1]")
        wideBuf[0] = 0

        return wideBuf
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
        return nil
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
        return nil
    end

    wideBuf[wideLength] = 0

    return wideBuf
end


-- ============================================================
-- Quote Windows argument
-- ============================================================

function shell.quoteArg(value)
    local text = tostring(value)

    if text:find("\0", 1, true) then
        error("argument contains NUL character", 2)
    end

    if text == "" then
        return '""'
    end

    if not text:find('[%s"]') then
        return text
    end

    local parts = { '"' }
    local slashCount = 0

    for index = 1, #text do
        local char = text:sub(index, index)

        if char == "\\" then
            slashCount = slashCount + 1
        elseif char == '"' then
            if slashCount > 0 then
                parts[#parts + 1] =
                    string.rep("\\", slashCount * 2)
            end

            parts[#parts + 1] = '\\"'

            slashCount = 0
        else
            if slashCount > 0 then
                parts[#parts + 1] =
                    string.rep("\\", slashCount)

                slashCount = 0
            end

            parts[#parts + 1] = char
        end
    end

    if slashCount > 0 then
        parts[#parts + 1] =
            string.rep("\\", slashCount * 2)
    end

    parts[#parts + 1] = '"'

    return table.concat(parts)
end

-- ============================================================
-- Build parameter string
-- ============================================================

function shell.parameters(args)
    if args == nil then
        return nil
    end

    if type(args) == "string" then
        if args:find("\0", 1, true) then
            error("parameters contain NUL character", 2)
        end

        return args
    end

    if type(args) ~= "table" then
        error(
            "parameters must be string, table or nil",
            2
        )
    end

    local parts = {}

    for index = 1, #args do
        parts[#parts + 1] =
            shell.quoteArg(args[index])
    end

    return table.concat(parts, " ")
end

-- ============================================================
-- Show mode
-- ============================================================

local function get_show_mode(showMode)
    if showMode == nil then
        return SW_SHOWNORMAL
    end

    if type(showMode) == "number" then
        return math.floor(showMode)
    end

    local name =
        tostring(showMode):lower()

    if name == "hide"
        or name == "hidden"
    then
        return SW_HIDE
    end

    if name == "normal" then
        return SW_SHOWNORMAL
    end

    if name == "min"
        or name == "minimized"
    then
        return SW_SHOWMINIMIZED
    end

    if name == "max"
        or name == "maximized"
    then
        return SW_SHOWMAXIMIZED
    end

    if name == "noactivate" then
        return SW_SHOWNOACTIVATE
    end

    if name == "show" then
        return SW_SHOW
    end

    if name == "minnoactive" then
        return SW_SHOWMINNOACTIVE
    end

    if name == "default" then
        return SW_SHOWDEFAULT
    end

    return nil
end


-- ============================================================
-- ShellExecute error
-- ============================================================

local shellErrors = {
    [0] = "Windows could not execute the operation",
    [2] = "file not found",
    [3] = "path not found",
    [5] = "access denied",
    [8] = "not enough memory",
    [26] = "sharing violation",
    [27] = "file association is incomplete",
    [28] = "DDE operation timed out",
    [29] = "DDE operation failed",
    [30] = "DDE operation is busy",
    [31] = "no application is associated with this file type",
    [32] = "required DLL was not found"
}


function shell.errorText(code)
    code = tonumber(code)

    return shellErrors[code]
        or ("ShellExecute error " .. tostring(code))
end

-- ============================================================
-- Execute shell operation
-- ============================================================

function shell.execute(
    verb,
    target,
    args,
    directory,
    showMode
)
    if target == nil
        or tostring(target) == ""
    then
        return nil, "target cannot be empty"
    end

    local targetWide =
        utf8_to_wide(target)

    if targetWide == nil then
        return nil,
            "target is not valid UTF-8"
    end

    local verbWide = nil

    if verb ~= nil then
        verbWide =
            utf8_to_wide(verb)

        if verbWide == nil then
            return nil,
                "verb is not valid UTF-8"
        end
    end

    local parameterText

    local ok, result =
        pcall(
            shell.parameters,
            args
        )

    if not ok then
        return nil, result
    end

    parameterText = result

    local parametersWide = nil

    if parameterText ~= nil then
        parametersWide =
            utf8_to_wide(parameterText)

        if parametersWide == nil then
            return nil,
                "parameters are not valid UTF-8"
        end
    end

    local directoryWide = nil

    if directory ~= nil then
        directoryWide =
            utf8_to_wide(directory)

        if directoryWide == nil then
            return nil,
                "directory is not valid UTF-8"
        end
    end

    local show =
        get_show_mode(showMode)

    if show == nil then
        return nil,
            "invalid show mode"
    end

    local execResult =
        shell32.ShellExecuteW(
            nil,
            verbWide,
            targetWide,
            parametersWide,
            directoryWide,
            show
        )

    local resultCode =
        tonumber(
            ffi.cast(
                "uintptr_t",
                execResult
            )
        )

    if resultCode <= 32 then
        return nil,
            shell.errorText(resultCode),
            resultCode
    end

    return true
end

-- ============================================================
-- Open file, folder or URL
-- ============================================================

function shell.open(
    target,
    args,
    directory,
    showMode
)
    return shell.execute(
        "open",
        target,
        args,
        directory,
        showMode
    )
end

-- ============================================================
-- Run executable
-- ============================================================

function shell.run(
    exePath,
    args,
    directory,
    showMode
)
    return shell.execute(
        "open",
        exePath,
        args,
        directory,
        showMode
    )
end

-- ============================================================
-- Run as Administrator
-- ============================================================

function shell.runAs(
    exePath,
    args,
    directory,
    showMode
)
    return shell.execute(
        "runas",
        exePath,
        args,
        directory,
        showMode
    )
end

-- ============================================================
-- Open URL
-- ============================================================

function shell.openUrl(url)
    return shell.execute(
        "open",
        url
    )
end

-- ============================================================
-- Open folder
-- ============================================================

function shell.openFolder(path)
    return shell.execute(
        "open",
        path
    )
end

-- ============================================================
-- Explore folder
-- ============================================================

function shell.explore(path)
    return shell.execute(
        "explore",
        path
    )
end

-- ============================================================
-- Open With...
-- ============================================================

function shell.openWith(path)
    if path == nil
        or tostring(path) == ""
    then
        return nil,
            "path cannot be empty"
    end

    local pathWide =
        utf8_to_wide(path)

    if pathWide == nil then
        return nil,
            "path is not valid UTF-8"
    end

    local info =
        ffi.new("LJ_SHELL_OPENASINFO")

    info.pcszFile = pathWide
    info.pcszClass = nil
    info.oaifInFlags = OAIF_EXEC

    local hr =
        tonumber(
            shell32.SHOpenWithDialog(
                nil,
                info
            )
        )

    if hr < 0 then
        local unsignedHr =
            hr + 4294967296

        return nil,
            string.format(
                "SHOpenWithDialog failed (HRESULT 0x%08X)",
                unsignedHr
            ),
            unsignedHr
    end

    return true
end

-- ============================================================
-- Edit
-- ============================================================

function shell.edit(path)
    return shell.execute(
        "edit",
        path
    )
end

-- ============================================================
-- Explorer: select file
-- ============================================================

function shell.select(path)
    if path == nil
        or tostring(path) == ""
    then
        return nil,
            "path cannot be empty"
    end

    local params =
        "/select,"
        .. shell.quoteArg(path)

    return shell.execute(
        "open",
        "explorer.exe",
        params
    )
end

return shell
