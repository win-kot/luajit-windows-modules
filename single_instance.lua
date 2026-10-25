-- Windows 10+ / LuaJIT. Put require("single_instance") at the start of the app.
-- The entry script's normalized absolute path identifies the application.
-- A duplicate exits with code 0. No arguments, GUI dependency or global exports.
local ffi = require("ffi")
if ffi.os ~= "Windows" then error("single_instance requires Windows", 2) end
ffi.cdef[[
void* __stdcall CreateMutexW(void*, int, const unsigned short*);
int __stdcall CloseHandle(void*);
unsigned long __stdcall GetLastError(void);
int __stdcall MultiByteToWideChar(unsigned int, unsigned long, const char*, int, unsigned short*, int);
unsigned long __stdcall GetFullPathNameW(const unsigned short*, unsigned long, unsigned short*, unsigned short**);
unsigned long __stdcall GetLongPathNameW(const unsigned short*, unsigned short*, unsigned long);
unsigned long __stdcall GetModuleFileNameW(void*, unsigned short*, unsigned long);
int __stdcall LCMapStringEx(const unsigned short*, unsigned long, const unsigned short*, int, unsigned short*, int, void*, void*, intptr_t);
long __stdcall BCryptOpenAlgorithmProvider(void**, const unsigned short*, const unsigned short*, unsigned long);
long __stdcall BCryptHash(void*, unsigned char*, unsigned long, unsigned char*, unsigned long, unsigned char*, unsigned long);
long __stdcall BCryptCloseAlgorithmProvider(void*, unsigned long);
]]
local k = ffi.load("kernel32")
local bcrypt = ffi.load("bcrypt")
local createMutex, getError, closeHandle = k.CreateMutexW, k.GetLastError, k.CloseHandle
local function fail(message) error("single_instance: " .. message, 2) end
local function wide(text)
    if text:find("\0", 1, true) then fail("script path contains NUL") end
    local n = k.MultiByteToWideChar(65001, 8, text, #text, nil, 0)
    if n == 0 then fail("script path is not valid UTF-8") end
    local out = ffi.new("unsigned short[?]", n + 1)
    if k.MultiByteToWideChar(65001, 8, text, #text, out, n) ~= n then
        fail("script path conversion failed")
    end
    return out
end

local entry = type(arg) == "table" and arg[0] or nil
local path = ffi.new("unsigned short[32768]")
local length
if type(entry) == "string" and entry ~= "" and entry:sub(1, 1) ~= "-" then
    length = tonumber(k.GetFullPathNameW(wide(entry), 32768, path, nil))
else
    -- A host with no entry script (embedded EXE, -e or stdin) uses its EXE path.
    length = tonumber(k.GetModuleFileNameW(nil, path, 32768))
end
if length == 0 or length >= 32768 then fail("cannot determine the application path") end

-- Expand short names and normalize the case with the invariant Windows locale.
local expanded = ffi.new("unsigned short[32768]")
length = tonumber(k.GetLongPathNameW(path, expanded, 32768))
if length == 0 or length >= 32768 then fail("cannot normalize the application path") end
-- Normal and extended DOS/UNC spellings must produce the same mutex name.
if expanded[0] == 92 and expanded[1] == 92 and expanded[2] == 63 and expanded[3] == 92 then
    if (expanded[4] == 85 or expanded[4] == 117) and (expanded[5] == 78 or expanded[5] == 110) and
       (expanded[6] == 67 or expanded[6] == 99) and expanded[7] == 92 then
        local normalized = ffi.new("unsigned short[32768]")
        normalized[0], normalized[1] = 92, 92
        ffi.copy(normalized + 2, expanded + 8, (length - 8 + 1) * 2)
        expanded, length = normalized, length - 6
    elseif expanded[5] == 58 then -- extended drive path, e.g. \\?\C:\...
        local normalized = ffi.new("unsigned short[32768]")
        ffi.copy(normalized, expanded + 4, (length - 4 + 1) * 2)
        expanded, length = normalized, length - 4
    end
end
local invariant = ffi.new("unsigned short[1]")
local n = k.LCMapStringEx(invariant, 0x100, expanded, length, nil, 0, nil, nil, 0)
if n == 0 then fail("cannot normalize path case") end
local normalized = ffi.new("unsigned short[?]", n + 1)
if k.LCMapStringEx(invariant, 0x100, expanded, length, normalized, n, nil, nil, 0) ~= n then
    fail("cannot normalize path case")
end

-- SHA-256 keeps the kernel object name short even for a long script path.
local algorithm = ffi.new("void*[1]")
if bcrypt.BCryptOpenAlgorithmProvider(algorithm, wide("SHA256"), nil, 0) < 0 then
    fail("cannot open SHA-256 provider")
end
local digest = ffi.new("unsigned char[32]")
local status = bcrypt.BCryptHash(algorithm[0], nil, 0, ffi.cast("unsigned char*", normalized), n * 2, digest, 32)
bcrypt.BCryptCloseAlgorithmProvider(algorithm[0], 0)
if status < 0 then fail("cannot hash the application path") end
local hex = {}
for i = 0, 31 do hex[#hex + 1] = string.format("%02x", digest[i]) end
local mutexName = wide("Local\\LuaJIT.SingleInstance." .. table.concat(hex))
local handle = createMutex(nil, 0, mutexName)
local code = tonumber(getError())
if handle == nil then fail("CreateMutexW failed (Win32 error " .. code .. ")") end
if code == 183 then -- ERROR_ALREADY_EXISTS
    closeHandle(handle)
    os.exit(0)
end
-- require() retains this opaque token in package.loaded until process shutdown.
return ffi.gc(handle, closeHandle)
