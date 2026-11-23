local errors = require("_errors")
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

local function Utf8ToWide(text)
    if text == nil then
        return nil
    end

    text = tostring(text)

    if text:find("\0", 1, true) then
        return nil, "Нулевой байт в строке недопустим"
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
        return errors.Win32("MultiByteToWideChar")
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
        return errors.Win32("MultiByteToWideChar")
    end

    wideBuf[wideLength] = 0

    return wideBuf
end


-- ============================================================
-- Quote Windows argument
-- ============================================================

local QuoteArgument = require('_win_quote')
function shell.ArgQuote(value)
    local text = tostring(value)
    if text:find("\0", 1, true) then
        return nil, "Нулевой байт в аргументе недопустим"
    end
    return QuoteArgument(text)
end

function shell.Parameters(args)
    if args == nil then
        return nil
    end

    if type(args) == "string" then
        if args:find("\0", 1, true) then
            return nil, "Нулевой байт в параметрах недопустим"
        end

        return args
    end

    if type(args) ~= "table" then
        return nil, "Параметры должны быть строкой, таблицей или nil"
    end

    local parts = {}

    for index = 1, #args do
        local quoted, err = shell.ArgQuote(args[index])
        if not quoted then return nil, err end
        parts[#parts + 1] = quoted
    end

    return table.concat(parts, " ")
end

-- ============================================================
-- Show mode
-- ============================================================

local function GetShowMode(showMode)
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
    [0] = "Не удалось запустить приложение",
    [2] = "Файл не найден",
    [3] = "Путь не найден",
    [5] = "Отказано в доступе",
    [8] = "Недостаточно памяти",
    [26] = "Объект используется другим процессом",
    [27] = "Неполная ассоциация файла",
    [28] = "Истекло время ожидания DDE",
    [29] = "Сбой DDE",
    [30] = "DDE занят",
    [31] = "С этим типом файла не связано приложение",
    [32] = "Требуемая DLL не найдена"
}

function shell.ErrorText(code)
    code = tonumber(code)

    return shellErrors[code]
        or ("ShellExecute error " .. tostring(code))
end

-- ============================================================
-- Execute shell operation
-- ============================================================

function shell.Execute(
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

    local targetWide, detail, code = Utf8ToWide(target)
    if not targetWide then return errors.Context("Недопустимая цель ShellExecuteW", detail, code) end

    local verbWide = nil

    if verb ~= nil then
        verbWide, detail, code = Utf8ToWide(verb)
        if not verbWide then return errors.Context("Ошибка преобразования действия", detail, code) end
    end

    local parameterText, err = shell.Parameters(args)
    if err then return nil, err end

    local parametersWide = nil

    if parameterText ~= nil then
        parametersWide, detail, code = Utf8ToWide(parameterText)
        if not parametersWide then return errors.Context("Ошибка преобразования параметров", detail, code) end
    end

    local directoryWide = nil

    if directory ~= nil then
        directoryWide, detail, code = Utf8ToWide(directory)
        if not directoryWide then return errors.Context("Ошибка преобразования рабочей папки", detail, code) end
    end

    local show =
        GetShowMode(showMode)

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
            ("ShellExecuteW: %s (Shell: %d)"):format(shell.ErrorText(resultCode), resultCode),
            resultCode
    end

    return true
end

-- ============================================================
-- Open file, folder or URL
-- ============================================================

function shell.Open(
    target,
    args,
    directory,
    showMode
)
    return shell.Execute(
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

function shell.Run(
    exePath,
    args,
    directory,
    showMode
)
    return shell.Execute(
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

function shell.RunAs(
    exePath,
    args,
    directory,
    showMode
)
    return shell.Execute(
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

function shell.UrlOpen(url)
    return shell.Execute(
        "open",
        url
    )
end

-- ============================================================
-- Open folder
-- ============================================================

function shell.FolderOpen(path)
    return shell.Execute(
        "open",
        path
    )
end

-- ============================================================
-- Explore folder
-- ============================================================

function shell.Explore(path)
    return shell.Execute(
        "explore",
        path
    )
end

-- ============================================================
-- Open With...
-- ============================================================

function shell.OpenWith(path)
    if path == nil
        or tostring(path) == ""
    then
        return nil,
            "path cannot be empty"
    end

    local pathWide, message, code = Utf8ToWide(path)
    if not pathWide then return nil, message, code end

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

function shell.Edit(path)
    return shell.Execute(
        "edit",
        path
    )
end

-- ============================================================
-- Explorer: select file
-- ============================================================

function shell.Select(path)
    if path == nil
        or tostring(path) == ""
    then
        return nil,
            "path cannot be empty"
    end

    local quoted, err, code = shell.ArgQuote(path)
    if quoted == nil then return nil, err, code end
    local params = "/select," .. quoted

    return shell.Execute(
        "open",
        "explorer.exe",
        params
    )
end

require("_shell_link")(shell)
require("_shell_recycle")(shell)
return shell
