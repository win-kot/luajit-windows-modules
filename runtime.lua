local ffi = require("ffi")

ffi.cdef [[
unsigned long __stdcall GetCurrentDirectoryW(
    unsigned long nBufferLength,
    unsigned short *lpBuffer
);
unsigned long __stdcall GetFullPathNameW(
    const unsigned short *, unsigned long, unsigned short *, unsigned short **
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
]]

local C = ffi.C

local M = {}

local function utf16_to_utf8(w, length)
    if length == 0 then
        return ""
    end

    local size = C.WideCharToMultiByte(
        65001,
        0,
        w,
        length,
        nil,
        0,
        nil,
        nil
    )

    if size == 0 then
        return nil, "WideCharToMultiByte failed"
    end

    local out = ffi.new("char[?]", size)

    if C.WideCharToMultiByte(
        65001,
        0,
        w,
        length,
        out,
        size,
        nil,
        nil
    ) ~= size then
        return nil, "WideCharToMultiByte failed"
    end

    return ffi.string(out, size)
end

local function get_working_dir()
    local size = C.GetCurrentDirectoryW(0, nil)

    if size == 0 then
        return nil, "GetCurrentDirectoryW failed"
    end

    local buf = ffi.new("unsigned short[?]", size)
    local length = C.GetCurrentDirectoryW(size, buf)

    if length == 0 or length >= size then
        return nil, "GetCurrentDirectoryW failed"
    end

    return utf16_to_utf8(buf, length)
end

local function normalize(path)
    return path:gsub("/", "\\")
end

local function dirname(path)
    path = normalize(path)
    local parent = path:match("^(.*)\\[^\\]*$") or "."
    if parent:match("^%a:$") then parent = parent .. "\\" end
    return parent
end

local function basename(path)
    path = normalize(path)

    return path:match("([^\\]+)$") or path
end

local function absolute_path(path)
    path = normalize(path)
    if path:find("\0", 1, true) then error("script path contains NUL") end
    local size = C.MultiByteToWideChar(65001, 8, path, #path, nil, 0)
    if size == 0 then error("script path is not valid UTF-8") end
    local wide = ffi.new("unsigned short[?]", size + 1)
    if C.MultiByteToWideChar(65001, 8, path, #path, wide, size) ~= size then
        error("MultiByteToWideChar failed")
    end
    -- Explicit namespace paths already identify an absolute literal path.
    if path:sub(1, 4) == '\\\\?\\' or path:sub(1, 4) == '\\\\.\\' then
        return path
    end
    local capacity = C.GetFullPathNameW(wide, 0, nil, nil)
    if capacity == 0 then error("GetFullPathNameW failed") end
    local out = ffi.new("unsigned short[?]", capacity)
    local length = C.GetFullPathNameW(wide, capacity, out, nil)
    if length == 0 or length >= capacity then error("GetFullPathNameW failed") end
    return assert(utf16_to_utf8(out, length))
end

local working_dir, err = get_working_dir()

if not working_dir then
    error(err)
end

working_dir = normalize(working_dir)

-- The Unicode-enabled LuaJIT build creates arg[] directly from the original
-- UTF-16 Windows command line, so arg[0] is already a UTF-8 script path.
-- No CommandLineToArgvW recovery layer is needed here anymore.
if type(arg) ~= "table" or type(arg[0]) ~= "string" or arg[0] == "" then
    error("runtime requires a non-empty script path in arg[0]; run a script file or set arg[0] explicitly in an embedded host", 2)
end
local script_arg = arg[0]

local script_path = absolute_path(script_arg)

M.L_ScriptPath = script_path
M.L_ScriptDir = dirname(script_path)
M.L_ScriptName = basename(script_path)
M.L_WorkingDir = working_dir

return M
