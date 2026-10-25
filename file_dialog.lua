local ffi = require("win_types")
local bit = require("bit")
-- Modal COM dialogs can synchronously re-enter Lua through the owner WNDPROC.
require("jit").off(true, true)

local M = {}

M.VERSION = "1.0-standalone"

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

local function guid(text)
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

CLSID_FileOpenDialog = guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")
CLSID_FileSaveDialog = guid("C0B4E2F3-BA21-4773-8DBA-335EC946EB8B")
IID_IFileOpenDialog = guid("D57C7288-D4AD-4768-BE02-9D969532D960")
IID_IFileSaveDialog = guid("84BCCD23-5FDE-4CDB-AEA4-AF64B83D78AB")
IID_IShellItem = guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")

local function hresult_u32(hr)
    return tonumber(ffi.cast("uint32_t", hr))
end

local function hresult_text(hr)
    return string.format("0x%08X", hresult_u32(hr))
end

local function failed(hr)
    return tonumber(hr) < 0
end

local function is_cancelled(hr)
    return hresult_u32(hr) == ERROR_CANCELLED_HRESULT
end

local function check_string(value, name)
    if value ~= nil and type(value) ~= "string" then
        error((name or "value") .. " must be a string", 3)
    end
end

local function utf8_to_wide(text)
    check_string(text, "text")
    if text:find("\0", 1, true) then error("text contains NUL character", 3) end

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
        error("invalid UTF-8 string", 3)
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
        error("UTF-8 to UTF-16 conversion failed", 3)
    end

    wide[written] = 0

    return wide
end

local function wide_to_utf8(wide)
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
        error("UTF-16 to UTF-8 conversion failed", 3)
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
        error("UTF-16 to UTF-8 conversion failed", 3)
    end

    return ffi.string(output, written)
end

local function release_unknown(ptr)
    if ptr == nil then
        return
    end

    local release = ffi.cast(
        "ULONG (__stdcall *)(void *)",
        ptr.lpVtbl[2]
    )

    release(ptr)
end

local function get_method(ptr, index, ctype)
    return ffi.cast(ctype, ptr.lpVtbl[index])
end

local function create_dialog(kind)
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

    if failed(hr) then
        error("CoCreateInstance failed: " .. hresult_text(hr), 3)
    end

    return ffi.cast("IFileDialog *", out[0])
end

local function set_title(dialog, title)
    if title == nil then
        return
    end

    check_string(title, "title")

    local wide = utf8_to_wide(title)

    local method = get_method(
        dialog,
        17,
        "HRESULT (__stdcall *)(void *, const WCHAR *)"
    )

    local hr = method(dialog, wide)

    if failed(hr) then
        error("IFileDialog.SetTitle failed: " .. hresult_text(hr), 3)
    end
end

local function set_file_name(dialog, file_name)
    if file_name == nil then
        return
    end

    check_string(file_name, "fileName")

    local wide = utf8_to_wide(file_name)

    local method = get_method(
        dialog,
        15,
        "HRESULT (__stdcall *)(void *, const WCHAR *)"
    )

    local hr = method(dialog, wide)

    if failed(hr) then
        error("IFileDialog.SetFileName failed: " .. hresult_text(hr), 3)
    end
end

local function set_default_extension(dialog, extension)
    if extension == nil then
        return
    end

    check_string(extension, "defaultExtension")

    if extension:sub(1, 1) == "." then
        extension = extension:sub(2)
    end

    local wide = utf8_to_wide(extension)

    local method = get_method(
        dialog,
        22,
        "HRESULT (__stdcall *)(void *, const WCHAR *)"
    )

    local hr = method(dialog, wide)

    if failed(hr) then
        error("IFileDialog.SetDefaultExtension failed: " .. hresult_text(hr), 3)
    end
end

local function set_options(dialog, add_flags)
    local current = ffi.new("DWORD[1]")

    local get_options = get_method(
        dialog,
        10,
        "HRESULT (__stdcall *)(void *, DWORD *)"
    )

    local hr = get_options(dialog, current)

    if failed(hr) then
        error("IFileDialog.GetOptions failed: " .. hresult_text(hr), 3)
    end

    local new_options = bit.bor(tonumber(current[0]), add_flags)

    local set_options_method = get_method(
        dialog,
        9,
        "HRESULT (__stdcall *)(void *, DWORD)"
    )

    hr = set_options_method(dialog, new_options)

    if failed(hr) then
        error("IFileDialog.SetOptions failed: " .. hresult_text(hr), 3)
    end
end

local function create_shell_item(path)
    check_string(path, "initialFolder")

    local wide = utf8_to_wide(path)
    local out = ffi.new("void *[1]")

    local hr = shell32.SHCreateItemFromParsingName(
        wide,
        nil,
        IID_IShellItem,
        out
    )

    if failed(hr) then
        error("SHCreateItemFromParsingName failed for [" .. path .. "]: " .. hresult_text(hr), 3)
    end

    return ffi.cast("IShellItem *", out[0])
end

local function set_initial_folder(dialog, path)
    if path == nil then
        return
    end

    local shell_item = create_shell_item(path)

    local ok, err = pcall(function()
        local method = get_method(
            dialog,
            12,
            "HRESULT (__stdcall *)(void *, IShellItem *)"
        )

        local hr = method(dialog, shell_item)

        if failed(hr) then
            error("IFileDialog.SetFolder failed: " .. hresult_text(hr), 2)
        end
    end)

    release_unknown(shell_item)

    if not ok then
        error(err, 3)
    end
end

local function set_filters(dialog, filters, filter_index)
    if filters == nil then
        return nil
    end

    if type(filters) ~= "table" then
        error("filters must be a table", 3)
    end

    if #filters == 0 then
        return nil
    end

    local specs = ffi.new("COMDLG_FILTERSPEC[?]", #filters)
    local keep_alive = {}

    for i = 1, #filters do
        local entry = filters[i]

        if type(entry) ~= "table" then
            error("filters[" .. i .. "] must be a table", 3)
        end

        local name = entry[1] or entry.name
        local pattern = entry[2] or entry.pattern

        if type(name) ~= "string" then
            error("filters[" .. i .. "] name must be a string", 3)
        end

        if type(pattern) ~= "string" then
            error("filters[" .. i .. "] pattern must be a string", 3)
        end

        local wide_name = utf8_to_wide(name)
        local wide_pattern = utf8_to_wide(pattern)

        keep_alive[#keep_alive + 1] = wide_name
        keep_alive[#keep_alive + 1] = wide_pattern

        specs[i - 1].pszName = wide_name
        specs[i - 1].pszSpec = wide_pattern
    end

    local method = get_method(
        dialog,
        4,
        "HRESULT (__stdcall *)(void *, UINT, const COMDLG_FILTERSPEC *)"
    )

    local hr = method(dialog, #filters, specs)

    if failed(hr) then
        error("IFileDialog.SetFileTypes failed: " .. hresult_text(hr), 3)
    end

    if filter_index ~= nil then
        if type(filter_index) ~= "number" or filter_index ~= math.floor(filter_index) then
            error("filterIndex must be an integer", 3)
        end

        if filter_index < 1 or filter_index > #filters then
            error("filterIndex is out of range", 3)
        end

        local set_index = get_method(
            dialog,
            5,
            "HRESULT (__stdcall *)(void *, UINT)"
        )

        hr = set_index(dialog, filter_index)

        if failed(hr) then
            error("IFileDialog.SetFileTypeIndex failed: " .. hresult_text(hr), 3)
        end
    end

    return {
        specs = specs,
        strings = keep_alive
    }
end

local function owner_ptr(owner)
    if owner == nil or owner == 0 then
        return nil
    end

    if type(owner) == "number" then
        return ffi.cast("void *", ffi.cast("uintptr_t", owner))
    end

    return ffi.cast("void *", owner)
end

local function show_dialog(dialog, owner)
    local method = get_method(
        dialog,
        3,
        "HRESULT (__stdcall *)(void *, void *)"
    )

    return method(dialog, owner_ptr(owner))
end

local function get_result_path(dialog)
    local item_out = ffi.new("IShellItem *[1]")

    local get_result = get_method(
        dialog,
        20,
        "HRESULT (__stdcall *)(void *, IShellItem **)"
    )

    local hr = get_result(dialog, item_out)

    if failed(hr) then
        error("IFileDialog.GetResult failed: " .. hresult_text(hr), 3)
    end

    local item = item_out[0]

    if item == nil then
        error("IFileDialog.GetResult returned no item", 3)
    end

    local path_ptr = ffi.new("WCHAR *[1]")

    local ok, result = pcall(function()
        local get_display_name = get_method(
            item,
            5,
            "HRESULT (__stdcall *)(void *, uint32_t, WCHAR **)"
        )

        local display_hr = get_display_name(
            item,
            SIGDN_FILESYSPATH,
            path_ptr
        )

        if failed(display_hr) then
            error("IShellItem.GetDisplayName failed: " .. hresult_text(display_hr), 2)
        end

        return wide_to_utf8(path_ptr[0])
    end)

    if path_ptr[0] ~= nil then
        ole32.CoTaskMemFree(path_ptr[0])
    end

    release_unknown(item)

    if not ok then
        error(result, 3)
    end

    return result
end

local function run_dialog(kind, options)
    if options == nil then
        options = {}
    end

    if type(options) ~= "table" then
        error("options must be a table", 3)
    end

    local coinit_hr = ole32.CoInitializeEx(
        nil,
        bit.bor(COINIT_APARTMENTTHREADED, COINIT_DISABLE_OLE1DDE)
    )

    local must_uninitialize = false

    if failed(coinit_hr) then
        if hresult_u32(coinit_hr) ~= RPC_E_CHANGED_MODE then
            return nil, "CoInitializeEx failed: " .. hresult_text(coinit_hr)
        end
    else
        must_uninitialize = true
    end

    local dialog
    local filter_resources

    local ok, result = pcall(function()
        dialog = create_dialog(kind)

        if kind == "folder" then
            set_options(
                dialog,
                bit.bor(
                    FOS_PICKFOLDERS,
                    FOS_FORCEFILESYSTEM,
                    FOS_PATHMUSTEXIST
                )
            )
        elseif kind == "save" then
            set_options(
                dialog,
                bit.bor(
                    FOS_FORCEFILESYSTEM,
                    FOS_PATHMUSTEXIST,
                    FOS_OVERWRITEPROMPT
                )
            )
        else
            set_options(
                dialog,
                bit.bor(
                    FOS_FORCEFILESYSTEM,
                    FOS_PATHMUSTEXIST,
                    FOS_FILEMUSTEXIST
                )
            )
        end

        set_title(dialog, options.title)
        set_initial_folder(dialog, options.initialFolder)

        if kind ~= "folder" then
            filter_resources = set_filters(dialog, options.filters, options.filterIndex)
            set_file_name(dialog, options.fileName)

            if kind == "save" then
                set_default_extension(dialog, options.defaultExtension)
            end
        end

        local show_hr = show_dialog(dialog, options.owner)

        if is_cancelled(show_hr) then
            return nil
        end

        if failed(show_hr) then
            error("IFileDialog.Show failed: " .. hresult_text(show_hr), 2)
        end

        return get_result_path(dialog)
    end)

    if dialog ~= nil then
        release_unknown(dialog)
    end

    if must_uninitialize then
        ole32.CoUninitialize()
    end

    if not ok then
        return nil, result
    end

    return result
end

function M.open(options)
    return run_dialog("open", options)
end

function M.save(options)
    return run_dialog("save", options)
end

function M.selectFolder(options)
    return run_dialog("folder", options)
end

return M
