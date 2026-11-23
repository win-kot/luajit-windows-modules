local ffi = require("ffi")
local native = require("_win_native")
local errors = require("_errors")
local M = {}
ffi.cdef[[
unsigned long __stdcall GetLastError(void);
void __stdcall SetLastError(unsigned long);
int __stdcall CloseHandle(void *);
void *__stdcall CreateEventW(void *, int, int, const uint16_t *);
unsigned long __stdcall WaitForSingleObject(void *, unsigned long);
void *__stdcall LocalFree(void *);
typedef struct { unsigned long size; void *descriptor; int inherit; } fw_security_attributes;
void *__stdcall GetCurrentProcess(void);
int __stdcall OpenProcessToken(void *, unsigned long, void **);
int __stdcall GetTokenInformation(void *, int, void *, unsigned long, unsigned long *);
int __stdcall ConvertSidToStringSidW(void *, uint16_t **);
int __stdcall ConvertStringSecurityDescriptorToSecurityDescriptorW(const uint16_t *, unsigned long, void **, unsigned long *);
]]
local k = ffi.load("kernel32")
M.kernel = k
M.invalidHandle = ffi.cast("void *", -1)

function M.FromWide(wide, count)
    if count == nil then
        count = 0
        while wide[count] ~= 0 do count = count + 1 end
    end
    if count == 0 then return "" end
    local size = k.WideCharToMultiByte(65001, 128, wide, count, nil, 0, nil, nil)
    if size == 0 then return errors.Win32("WideCharToMultiByte") end
    local bytes = ffi.new("char[?]", size)
    if k.WideCharToMultiByte(65001, 128, wide, count, bytes, size, nil, nil) == 0 then
        return errors.Win32("WideCharToMultiByte")
    end
    return ffi.string(bytes, size)
end

M.Error = errors.Win32

function M.ToWide(text)
    if type(text) ~= "string" or #text > 0x7FFFFFFF or text:find("\0", 1, true) then
        return M.Error("Expected UTF-8 string without NUL", 87)
    end
    if text == "" then return ffi.new("uint16_t[1]"), 0 end
    local count = k.MultiByteToWideChar(65001, 8, text, #text, nil, 0)
    if count == 0 then return M.Error("MultiByteToWideChar") end
    local wide = ffi.new("uint16_t[?]", count + 1)
    if k.MultiByteToWideChar(65001, 8, text, #text, wide, count) == 0 then
        return M.Error("MultiByteToWideChar")
    end
    return wide, count
end

function M.PathWide(path)
    -- Keep the established ERROR_INVALID_PARAMETER validation result here.
    if type(path) ~= "string" or path == "" or path:find("\0", 1, true) then
        return M.Error("проверку пути", 87)
    end
    return native.PathWide(path)
end

function M.Integer(value, minimum, maximum)
    return type(value) == "number" and value >= minimum and value <= maximum and value % 1 == 0
end

function M.Timeout(value, default)
    if value == nil then return default end
    if M.Integer(value, 0, 0xFFFFFFFE) then return value end
    return M.Error("timeoutMs must be an integer in [0, 4294967294]", 87)
end

function M.Close(handle)
    if k.CloseHandle(handle) == 0 then return M.Error("CloseHandle") end
    ffi.gc(handle, nil)
    return true
end

function M.Own(handle)
    return ffi.gc(handle, k.CloseHandle)
end

function M.Exact(value)
    local number = tonumber(value)
    if number >= -9007199254740991 and number <= 9007199254740991 then return number end
    return (tostring(value):gsub("ULL$", ""):gsub("LL$", ""))
end

function M.Symbol(dll, name)
    local ok, symbol = pcall(function() return dll[name] end)
    if ok then return symbol end
end

function M.Library(name)
    local ok, dll = pcall(ffi.load, name)
    if ok then return dll end
    return nil, "Не удалось загрузить библиотеку " .. name .. ": " .. tostring(dll)
end

function M.UserSid()
    local adv, err, code = M.Library("advapi32")
    if not adv then return nil, err, code end
    local token = ffi.new("void *[1]")
    if adv.OpenProcessToken(k.GetCurrentProcess(), 8, token) == 0 then return M.Error("OpenProcessToken") end
    local size = ffi.new("unsigned long[1]")
    local ok = adv.GetTokenInformation(token[0], 1, nil, 0, size)
    code = ok == 0 and tonumber(k.GetLastError())
    if code ~= 122 then
        k.CloseHandle(token[0])
        return M.Error("GetTokenInformation(TokenUser)", code or 13)
    end
    local buffer = ffi.new("uint8_t[?]", size[0])
    ok = adv.GetTokenInformation(token[0], 1, buffer, size[0], size)
    code = ok == 0 and tonumber(k.GetLastError())
    k.CloseHandle(token[0])
    if ok == 0 then return M.Error("GetTokenInformation(TokenUser)", code) end
    local str = ffi.new("uint16_t *[1]")
    if adv.ConvertSidToStringSidW(ffi.cast("void **", buffer)[0], str) == 0 then
        return M.Error("ConvertSidToStringSidW")
    end
    local sid, message, status = M.FromWide(str[0])
    k.LocalFree(str[0])
    return sid, message, status
end

function M.UserAcl()
    local sid, err, code = M.UserSid()
    if not sid then return nil, err, code end
    local adv = ffi.load("advapi32")
    local sddl = M.ToWide("D:P(A;;GA;;;SY)(A;;GA;;;" .. sid .. ")")
    local descriptor = ffi.new("void *[1]")
    if adv.ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, 1, descriptor, nil) == 0 then
        return M.Error("ConvertStringSecurityDescriptorToSecurityDescriptorW")
    end
    local attrs = ffi.new("fw_security_attributes[1]")
    attrs[0].size = ffi.sizeof(attrs[0])
    attrs[0].descriptor = descriptor[0]
    return attrs
end

function M.Named(name, prefix)
    if type(name) ~= "string" or name == "" or name:find("[/\\]") then
        return M.Error("Expected a short logical name without slashes", 87)
    end
    local wide, count, code = M.ToWide(prefix .. name)
    if not wide then return nil, count, code end
    if count > 255 then return M.Error("Object name exceeds 255 UTF-16 units", 206) end
    return wide
end

return M
