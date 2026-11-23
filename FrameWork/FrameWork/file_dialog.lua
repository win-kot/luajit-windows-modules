local ffi = require("win_types")
local errors = require("_errors")
local bit = require("bit")
-- Modal COM dialogs can synchronously re-enter Lua through the owner WNDPROC.
require("jit").off(true, true)

local M = {}

ffi.cdef[[
typedef int32_t HRESULT;
typedef uint32_t DWORD;
typedef uint32_t UINT;
typedef uint32_t ULONG;
typedef uint16_t WCHAR;


typedef struct COMDLG_FILTERSPEC {
    const WCHAR *pszName;
    const WCHAR *pszSpec;
} COMDLG_FILTERSPEC;

typedef struct IFileDialog {
    void **lpVtbl;
} IFileDialog;

typedef struct IShellItem {
    void **lpVtbl;
} IShellItem;

HRESULT __stdcall CoInitializeEx(void *pvReserved, DWORD dwCoInit);
void __stdcall CoUninitialize(void);

HRESULT __stdcall CoCreateInstance(
    const GUID *rclsid,
    void *pUnkOuter,
    DWORD dwClsContext,
    const GUID *riid,
    void **ppv
);

void __stdcall CoTaskMemFree(void *pv);

HRESULT __stdcall SHCreateItemFromParsingName(
    const WCHAR *pszPath,
    void *pbc,
    const GUID *riid,
    void **ppv
);

int __stdcall MultiByteToWideChar(
    UINT CodePage,
    DWORD dwFlags,
    const char *lpMultiByteStr,
    int cbMultiByte,
    WCHAR *lpWideCharStr,
    int cchWideChar
);

int __stdcall WideCharToMultiByte(
    UINT CodePage,
    DWORD dwFlags,
    const WCHAR *lpWideCharStr,
    int cchWideChar,
    char *lpMultiByteStr,
    int cbMultiByte,
    const char *lpDefaultChar,
    int *lpUsedDefaultChar
);
]]

local ole32 = ffi.load("ole32")
local shell32 = ffi.load("shell32")
local kernel32 = ffi.load("kernel32")

local CP_UTF8 = 65001
local MB_ERR_INVALID_CHARS = 0x00000008
local WC_ERR_INVALID_CHARS = 0x00000080

local COINIT_APARTMENTTHREADED = 0x2
local COINIT_DISABLE_OLE1DDE = 0x4
local CLSCTX_INPROC_SERVER = 0x1

local FOS_OVERWRITEPROMPT = 0x00000002
local FOS_PICKFOLDERS = 0x00000020
local FOS_FORCEFILESYSTEM = 0x00000040
local FOS_PATHMUSTEXIST = 0x00000800
local FOS_FILEMUSTEXIST = 0x00001000

local SIGDN_FILESYSPATH = 0x80058000

local ERROR_CANCELLED_HRESULT = 0x800704C7
local RPC_E_CHANGED_MODE = 0x80010106

local CLSID_FileOpenDialog
local CLSID_FileSaveDialog
local IID_IFileOpenDialog
local IID_IFileSaveDialog
local IID_IShellItem

local function Guid(text)
    local hex = text:gsub("[{}%-]", "")

    if #hex ~= 32 or not hex:match("^%x+$") then
        error("invalid GUID: " .. tostring(text), 2)
    end

    local value = ffi.new("GUID")

    value.Data1 = tonumber(hex:sub(1, 8), 16)
    value.Data2 = tonumber(hex:sub(9, 12), 16)
    value.Data3 = tonumber(hex:sub(13, 16), 16)

    for i = 0, 7 do
        local pos = 17 + i * 2
        value.Data4[i] = tonumber(hex:sub(pos, pos + 1), 16)
    end

    return value
end

CLSID_FileOpenDialog = Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")
CLSID_FileSaveDialog = Guid("C0B4E2F3-BA21-4773-8DBA-335EC946EB8B")
IID_IFileOpenDialog = Guid("D57C7288-D4AD-4768-BE02-9D969532D960")
IID_IFileSaveDialog = Guid("84BCCD23-5FDE-4CDB-AEA4-AF64B83D78AB")
IID_IShellItem = Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")

local function HresultU32(hr)
    return tonumber(ffi.cast("uint32_t", hr))
end

local marker = {}
local function Raise(_, message, code)
    error({marker = marker, message = message, code = code}, 0)
end

local function HresultError(operation, hr, context)
    local code = tonumber(hr)
    local _, message = errors.Status(operation, "HRESULT", ("0x%08X"):format(HresultU32(hr)), context)
    return nil, message, code
end

local function Failed(hr)
    return tonumber(hr) < 0
end

local function IsCancelled(hr)
    return HresultU32(hr) == ERROR_CANCELLED_HRESULT
end

local function CheckString(value, name)
    if value ~= nil and type(value) ~= "string" then
        Raise(nil, "Ожидается строка: " .. (name or "value"))
    end
end

local function Utf8ToWide(text)
    CheckString(text, "text")
    if text:find("\0", 1, true) then Raise(nil, "Нулевой байт в тексте диалога недопустим") end

    if text == "" then
        return ffi.new("WCHAR[1]", 0)
    end

    local needed = kernel32.MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        text,
        #text,
        nil,
        0
    )

    if needed == 0 then
        Raise(errors.Win32("MultiByteToWideChar"))
    end

    local wide = ffi.new("WCHAR[?]", needed + 1)

    local written = kernel32.MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        text,
        #text,
        wide,
        needed
    )

    if written == 0 then
        Raise(errors.Win32("MultiByteToWideChar"))
    end

    wide[written] = 0

    return wide
end

local function WideToUtf8(wide)
    if wide == nil then
        return nil
    end

    local length = 0

    while wide[length] ~= 0 do
        length = length + 1
    end

    if length == 0 then
        return ""
    end

    local needed = kernel32.WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        wide,
        length,
        nil,
        0,
        nil,
        nil
    )

    if needed == 0 then
        Raise(errors.Win32("WideCharToMultiByte"))
    end

    local output = ffi.new("char[?]", needed)

    local written = kernel32.WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        wide,
        length,
        output,
        needed,
        nil,
        nil
    )

    if written == 0 then
        Raise(errors.Win32("WideCharToMultiByte"))
    end

    return ffi.string(output, written)
end

local function ReleaseUnknown(ptr)
    if ptr == nil then
        return
    end

    local release = ffi.cast(
        "ULONG (__stdcall *)(void *)",
        ptr.lpVtbl[2]
    )

    release(ptr)
end

local function GetMethod(ptr, index, ctype)
    return ffi.cast(ctype, ptr.lpVtbl[index])
end

local function CreateDialog(kind)
    local class_id
    local interface_id

    if kind == "save" then
        class_id = CLSID_FileSaveDialog
        interface_id = IID_IFileSaveDialog
    else
        class_id = CLSID_FileOpenDialog
        interface_id = IID_IFileOpenDialog
    end

    local out = ffi.new("void *[1]")

    local hr = ole32.CoCreateInstance(
        class_id,
        nil,
        CLSCTX_INPROC_SERVER,
        interface_id,
        out
    )

    if Failed(hr) then
        Raise(HresultError("CoCreateInstance", hr))
    end

    return ffi.cast("IFileDialog *", out[0])
end

local function SetTitle(dialog, title)
    if title == nil then
        return
    end

    CheckString(title, "title")

    local wide = Utf8ToWide(title)

    local method = GetMethod(
        dialog,
        17,
        "HRESULT (__stdcall *)(void *, const WCHAR *)"
    )

    local hr = method(dialog, wide)

    if Failed(hr) then
        Raise(HresultError("IFileDialog.SetTitle", hr))
    end
end

local function SetFileName(dialog, file_name)
    if file_name == nil then
        return
    end

    CheckString(file_name, "fileName")

    local wide = Utf8ToWide(file_name)

    local method = GetMethod(
        dialog,
        15,
        "HRESULT (__stdcall *)(void *, const WCHAR *)"
    )

    local hr = method(dialog, wide)

    if Failed(hr) then
        Raise(HresultError("IFileDialog.SetFileName", hr))
    end
end

local function SetDefaultExtension(dialog, extension)
    if extension == nil then
        return
    end

    CheckString(extension, "defaultExtension")

    if extension:sub(1, 1) == "." then
        extension = extension:sub(2)
    end

    local wide = Utf8ToWide(extension)

    local method = GetMethod(
        dialog,
        22,
        "HRESULT (__stdcall *)(void *, const WCHAR *)"
    )

    local hr = method(dialog, wide)

    if Failed(hr) then
        Raise(HresultError("IFileDialog.SetDefaultExtension", hr))
    end
end

local function SetOptions(dialog, add_flags)
    local current = ffi.new("DWORD[1]")

    local get_options = GetMethod(
        dialog,
        10,
        "HRESULT (__stdcall *)(void *, DWORD *)"
    )

    local hr = get_options(dialog, current)

    if Failed(hr) then
        Raise(HresultError("IFileDialog.GetOptions", hr))
    end

    local new_options = bit.bor(tonumber(current[0]), add_flags)

    local set_options_method = GetMethod(
        dialog,
        9,
        "HRESULT (__stdcall *)(void *, DWORD)"
    )

    hr = set_options_method(dialog, new_options)

    if Failed(hr) then
        Raise(HresultError("IFileDialog.SetOptions", hr))
    end
end

local function CreateShellItem(path)
    CheckString(path, "initialFolder")

    local wide = Utf8ToWide(path)
    local out = ffi.new("void *[1]")

    local hr = shell32.SHCreateItemFromParsingName(
        wide,
        nil,
        IID_IShellItem,
        out
    )

    if Failed(hr) then
        Raise(HresultError("SHCreateItemFromParsingName", hr, path))
    end

    return ffi.cast("IShellItem *", out[0])
end

local function SetInitialFolder(dialog, path)
    if path == nil then
        return
    end

    local shell_item = CreateShellItem(path)

    local ok, err = pcall(function()
        local method = GetMethod(
            dialog,
            12,
            "HRESULT (__stdcall *)(void *, IShellItem *)"
        )

        local hr = method(dialog, shell_item)

        if Failed(hr) then
            Raise(HresultError("IFileDialog.SetFolder", hr))
        end
    end)

    ReleaseUnknown(shell_item)

    if not ok then
        error(err, 0)
    end
end

local function SetFilters(dialog, filters, filter_index)
    if filters == nil then
        return nil
    end

    if type(filters) ~= "table" then
        Raise(nil, "filters должен быть таблицей")
    end

    if #filters == 0 then
        return nil
    end

    local specs = ffi.new("COMDLG_FILTERSPEC[?]", #filters)
    local keep_alive = {}

    for i = 1, #filters do
        local entry = filters[i]

        if type(entry) ~= "table" then
            Raise(nil, "Элемент filters[" .. i .. "] должен быть таблицей")
        end

        local name = entry[1] or entry.name
        local pattern = entry[2] or entry.pattern

        if type(name) ~= "string" then
            Raise(nil, "Для filters[" .. i .. "] требуется строковое описание")
        end

        if type(pattern) ~= "string" then
            Raise(nil, "Для filters[" .. i .. "] требуется строковый шаблон")
        end

        local wide_name = Utf8ToWide(name)
        local wide_pattern = Utf8ToWide(pattern)

        keep_alive[#keep_alive + 1] = wide_name
        keep_alive[#keep_alive + 1] = wide_pattern

        specs[i - 1].pszName = wide_name
        specs[i - 1].pszSpec = wide_pattern
    end

    local method = GetMethod(
        dialog,
        4,
        "HRESULT (__stdcall *)(void *, UINT, const COMDLG_FILTERSPEC *)"
    )

    local hr = method(dialog, #filters, specs)

    if Failed(hr) then
        Raise(HresultError("IFileDialog.SetFileTypes", hr))
    end

    if filter_index ~= nil then
        if type(filter_index) ~= "number" or filter_index ~= math.floor(filter_index) then
            Raise(nil, "filterIndex должен быть целым числом")
        end

        if filter_index < 1 or filter_index > #filters then
            Raise(nil, "filterIndex выходит за диапазон фильтров")
        end

        local set_index = GetMethod(
            dialog,
            5,
            "HRESULT (__stdcall *)(void *, UINT)"
        )

        hr = set_index(dialog, filter_index)

        if Failed(hr) then
            Raise(HresultError("IFileDialog.SetFileTypeIndex", hr))
        end
    end

    return {
        specs = specs,
        strings = keep_alive
    }
end

local function OwnerPtr(owner)
    if owner == nil or owner == 0 then
        return nil
    end

    if type(owner) == "number" then
        return ffi.cast("void *", ffi.cast("uintptr_t", owner))
    end

    return ffi.cast("void *", owner)
end

local function ShowDialog(dialog, owner)
    local method = GetMethod(
        dialog,
        3,
        "HRESULT (__stdcall *)(void *, void *)"
    )

    return method(dialog, OwnerPtr(owner))
end

local function GetResultPath(dialog)
    local item_out = ffi.new("IShellItem *[1]")

    local get_result = GetMethod(
        dialog,
        20,
        "HRESULT (__stdcall *)(void *, IShellItem **)"
    )

    local hr = get_result(dialog, item_out)

    if Failed(hr) then
        Raise(HresultError("IFileDialog.GetResult", hr))
    end

    local item = item_out[0]

    if item == nil then
        Raise(nil, "IFileDialog.GetResult не вернул выбранный объект")
    end

    local path_ptr = ffi.new("WCHAR *[1]")

    local ok, result = pcall(function()
        local get_display_name = GetMethod(
            item,
            5,
            "HRESULT (__stdcall *)(void *, uint32_t, WCHAR **)"
        )

        local display_hr = get_display_name(
            item,
            SIGDN_FILESYSPATH,
            path_ptr
        )

        if Failed(display_hr) then
            Raise(HresultError("IShellItem.GetDisplayName", display_hr))
        end

        return WideToUtf8(path_ptr[0])
    end)

    if path_ptr[0] ~= nil then
        ole32.CoTaskMemFree(path_ptr[0])
    end

    ReleaseUnknown(item)

    if not ok then
        error(result, 0)
    end

    return result
end

local function RunDialog(kind, options)
    if options == nil then
        options = {}
    end

    if type(options) ~= "table" then
        return nil, "Параметры диалога должны быть таблицей"
    end

    local coinit_hr = ole32.CoInitializeEx(
        nil,
        bit.bor(COINIT_APARTMENTTHREADED, COINIT_DISABLE_OLE1DDE)
    )

    local must_uninitialize = false

    if Failed(coinit_hr) then
        if HresultU32(coinit_hr) ~= RPC_E_CHANGED_MODE then
            return HresultError("CoInitializeEx", coinit_hr)
        end
    else
        must_uninitialize = true
    end

    local dialog
    local filter_resources

    local ok, result = pcall(function()
        dialog = CreateDialog(kind)

        if kind == "folder" then
            SetOptions(
                dialog,
                bit.bor(
                    FOS_PICKFOLDERS,
                    FOS_FORCEFILESYSTEM,
                    FOS_PATHMUSTEXIST
                )
            )
        elseif kind == "save" then
            SetOptions(
                dialog,
                bit.bor(
                    FOS_FORCEFILESYSTEM,
                    FOS_PATHMUSTEXIST,
                    FOS_OVERWRITEPROMPT
                )
            )
        else
            SetOptions(
                dialog,
                bit.bor(
                    FOS_FORCEFILESYSTEM,
                    FOS_PATHMUSTEXIST,
                    FOS_FILEMUSTEXIST
                )
            )
        end

        SetTitle(dialog, options.title)
        SetInitialFolder(dialog, options.initialFolder)

        if kind ~= "folder" then
            filter_resources = SetFilters(dialog, options.filters, options.filterIndex)
            SetFileName(dialog, options.fileName)

            if kind == "save" then
                SetDefaultExtension(dialog, options.defaultExtension)
            end
        end

        local show_hr = ShowDialog(dialog, options.owner)

        if IsCancelled(show_hr) then
            return nil
        end

        if Failed(show_hr) then
            Raise(HresultError("IFileDialog.Show", show_hr))
        end

        return GetResultPath(dialog)
    end)

    if dialog ~= nil then
        ReleaseUnknown(dialog)
    end

    if must_uninitialize then
        ole32.CoUninitialize()
    end

    if not ok then
        if type(result) == "table" and result.marker == marker then
            return nil, result.message, result.code
        end
        error(result, 0)
    end

    return result
end

function M.Open(options)
    return RunDialog("open", options)
end

function M.Save(options)
    return RunDialog("save", options)
end

function M.FolderSelect(options)
    return RunDialog("folder", options)
end

return M
