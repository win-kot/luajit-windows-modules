-- unicode_io 3.4-standalone - LuaJIT / Windows Unicode library.
-- Internal convention: Lua text and paths are UTF-8; Windows boundaries use UTF-16.
--
-- IMPORTANT: require("unicode_io") DOES NOT patch io, os, loadfile, dofile,
-- package.path, package.cpath, package.loadlib or any other standard Lua function.
-- Use this module explicitly through the returned table.
--
-- High-level text helpers use UTF-8 by default when encoding is omitted.
-- Use encoding "BINARY" explicitly when raw bytes are required.

-- Keep one module instance even if package.loaded["unicode_io"] is cleared manually.
local singleton_key = '__unicode_io_standalone_v1'
local existing = package.loaded[singleton_key]
if type(existing) == 'table' then
  return existing
end

local ffi = require('ffi')
local bit = require('bit')
local native = require('win_native')
local pathwide = native.pathwide
local original = { io = {}, os = {}, loadfile = loadfile, dofile = dofile, arg = rawget(_G, 'arg') }
for k, v in pairs(io) do original.io[k] = v end
for k, v in pairs(os) do original.os[k] = v end
assert(ffi.os == 'Windows', 'unicode_io requires Windows')
ffi.cdef [[
typedef struct unicode_io_FILE unicode_io_FILE;
unicode_io_FILE *_wfopen(const unsigned short *, const unsigned short *);
int fclose(unicode_io_FILE *);
size_t fread(void *, size_t, size_t, unicode_io_FILE *);
size_t fwrite(const void *, size_t, size_t, unicode_io_FILE *);
int fgetc(unicode_io_FILE *);
int ungetc(int, unicode_io_FILE *);
int ferror(unicode_io_FILE *);
int fflush(unicode_io_FILE *);
int _fseeki64(unicode_io_FILE *, int64_t, int);
int fgetpos(unicode_io_FILE *, int64_t *);
int *_errno(void);
int fscanf(unicode_io_FILE *, const char *, ...);
int setvbuf(unicode_io_FILE *, char *, int, size_t);
int _wsystem(const unsigned short *);
int _open_osfhandle(intptr_t,int);
unicode_io_FILE *_fdopen(int,const char *);
int _close(int);
typedef struct { unsigned long nLength; void *lpSecurityDescriptor; int bInheritHandle; } uio_SECURITY_ATTRIBUTES;
typedef struct {
  unsigned long cb; unsigned short *lpReserved,*lpDesktop,*lpTitle;
  unsigned long dwX,dwY,dwXSize,dwYSize,dwXCountChars,dwYCountChars,dwFillAttribute,dwFlags;
  unsigned short wShowWindow,cbReserved2; unsigned char *lpReserved2;
  void *hStdInput,*hStdOutput,*hStdError;
} uio_STARTUPINFOW;
typedef struct { void *hProcess,*hThread; unsigned long dwProcessId,dwThreadId; } uio_PROCESS_INFORMATION;
int __stdcall CreatePipe(void **,void **,void *,unsigned long);
int __stdcall SetHandleInformation(void *,unsigned long,unsigned long);
void *__stdcall GetCurrentProcess(void);
int __stdcall DuplicateHandle(void *,void *,void *,void **,unsigned long,int,unsigned long);
int __stdcall CreateProcessW(const unsigned short *,unsigned short *,void *,void *,int,unsigned long,void *,const unsigned short *,void *,void *);
int __stdcall CloseHandle(void *);
unsigned long __stdcall WaitForSingleObject(void *,unsigned long);
int __stdcall GetExitCodeProcess(void *,unsigned long *);
void __stdcall SetLastError(unsigned long);
unsigned long __stdcall GetFullPathNameW(const unsigned short *, unsigned long, unsigned short *, unsigned short **);
int __stdcall CompareStringOrdinal(const unsigned short *, int, const unsigned short *, int, int);
void *__stdcall CreateFileW(const unsigned short *, unsigned long, unsigned long, void *, unsigned long, unsigned long, void *);
typedef struct { unsigned long dwLowDateTime, dwHighDateTime; } uio_FILETIME;
typedef struct {
  unsigned long dwFileAttributes;
  uio_FILETIME ftCreationTime, ftLastAccessTime, ftLastWriteTime;
  unsigned long nFileSizeHigh, nFileSizeLow;
} uio_WIN32_FILE_ATTRIBUTE_DATA;
unsigned long __stdcall GetFileAttributesW(const unsigned short *);
int __stdcall GetFileAttributesExW(const unsigned short *, int, uio_WIN32_FILE_ATTRIBUTE_DATA *);
int __stdcall SetFileAttributesW(const unsigned short *, unsigned long);
int __stdcall MoveFileExW(const unsigned short *, const unsigned short *, unsigned long);
void *__stdcall LoadLibraryW(const unsigned short *);
void *__stdcall GetProcAddress(void *, const char *);
int __stdcall MultiByteToWideChar(unsigned int, unsigned long, const char *, int, unsigned short *, int);
int __stdcall WideCharToMultiByte(unsigned int, unsigned long, const unsigned short *, int, char *, int, const char *, int *);
unsigned long __stdcall GetLastError(void);
void *__stdcall GetStdHandle(unsigned long);
int __stdcall GetConsoleMode(void *, unsigned long *);
int __stdcall ReadConsoleW(void *, void *, unsigned long, unsigned long *, void *);
int __stdcall WriteConsoleW(void *, const void *, unsigned long, unsigned long *, void *);
const unsigned short *__stdcall GetCommandLineW(void);
unsigned short **__stdcall CommandLineToArgvW(const unsigned short *, int *);
void *__stdcall LocalFree(void *);
unsigned int __stdcall GetACP(void);
unsigned int __stdcall GetOEMCP(void);
int __stdcall IsValidCodePage(unsigned int);
int __stdcall PathMatchSpecW(const unsigned short *, const unsigned short *);
]]
-- All FILE operations use the SAME runtime. Never pass these FILEs to Lua's CRT.
local crt = ffi.load('msvcrt')
local shell32 = ffi.load('shell32')
local shlwapi = ffi.load('shlwapi')
local C = ffi.C
local M, File = {}, {}


File.__index = File
File.__tostring = function(self)
  return self._fp ~= nil and 'file (unicode_io)' or 'file (closed)'
end
local function failure(op)
  local code = tonumber(crt._errno()[0])
  return nil, op .. ' failed (CRT errno ' .. code .. ')', code
end
local function winerror(op, code)
  code = tonumber(code or C.GetLastError())
  return nil, op .. ' failed (Win32 error ' .. code .. ')', code
end
local function winfailure(op)
  return winerror(op, C.GetLastError())
end
local function wide(s, allow_empty)
  if type(s) ~= 'string' then return nil, 'expected a UTF-8 string' end
  if s:find('\0', 1, true) then return nil, 'embedded NUL is not allowed' end
  if s == '' then
    if allow_empty then return ffi.new('unsigned short[1]'), 0 end
    return nil, 'empty path is not allowed'
  end
  local n = C.MultiByteToWideChar(65001, 8, s, #s, nil, 0)
  if n == 0 then return nil, 'invalid UTF-8 (or string too large)' end
  local w = ffi.new('unsigned short[?]', n + 1)
  if C.MultiByteToWideChar(65001, 8, s, #s, w, n) ~= n then return winfailure('UTF-8 decode') end
  return w, n
end
local function utf8(w, n)
  if n == 0 then return '' end
  local size = C.WideCharToMultiByte(65001, 128, w, n, nil, 0, nil, nil)
  if size == 0 then return winfailure('UTF-16 decode') end
  local b = ffi.new('char[?]', size)
  if C.WideCharToMultiByte(65001, 128, w, n, b, size, nil, nil) ~= size then
    return winfailure('UTF-16 decode')
  end
  return ffi.string(b, size)
end
local function wlen(w)
  local n = 0
  while w[n] ~= 0 do n = n + 1 end
  return n
end
local function codepage_number(codepage, default_codepage)
  if codepage == nil then codepage = default_codepage end
  if type(codepage) ~= 'number' or codepage ~= math.floor(codepage) or codepage < 0 or codepage > 4294967295 then
    return nil, 'invalid Windows code page'
  end
  if codepage == 0 then codepage = tonumber(C.GetACP()) end
  if codepage == 1 then codepage = tonumber(C.GetOEMCP()) end
  if C.IsValidCodePage(codepage) == 0 then return nil, 'unsupported Windows code page ' .. tostring(codepage) end
  return codepage
end
local function multibyte_wide(text, codepage)
  if type(text) ~= 'string' then return nil, 'expected a byte string' end
  if #text > 2147483647 then return nil, 'string is too large' end
  if text == '' then return ffi.new('unsigned short[1]'), 0 end
  local flags = (codepage == 65001 or codepage == 54936) and 8 or 0
  C.SetLastError(0)
  local n = C.MultiByteToWideChar(codepage, flags, text, #text, nil, 0)
  if n == 0 then return winfailure('MultiByteToWideChar') end
  local w = ffi.new('unsigned short[?]', n + 1)
  if C.MultiByteToWideChar(codepage, flags, text, #text, w, n) ~= n then return winfailure('MultiByteToWideChar') end
  return w, n
end
local function zero_flag_codepage(codepage)
  return codepage == 42 or codepage == 65000
      or codepage == 50220 or codepage == 50221 or codepage == 50222
      or codepage == 50225 or codepage == 50227 or codepage == 50229
      or (codepage >= 57002 and codepage <= 57011)
end

local function same_wide(a, an, b, bn)
  if an ~= bn then return false end
  if an == 0 then return true end
  return ffi.string(a, an * 2) == ffi.string(b, bn * 2)
end

local function wide_multibyte(w, n, codepage, allow_lossy)
  if n == 0 then return '' end

  local strict = not allow_lossy
  local flags = 0
  local used_default
  local needs_roundtrip = false

  if codepage == 65001 or codepage == 54936 then
    -- UTF-8 / GB18030: lpUsedDefaultChar must be NULL. Both can use
    -- WC_ERR_INVALID_CHARS (0x80) for strict input validation.
    if strict then flags = 128 end
  elseif zero_flag_codepage(codepage) then
    -- These Windows code pages require dwFlags == 0. Some also reject
    -- lpUsedDefaultChar, so strict loss detection is done by round-trip.
    if strict then needs_roundtrip = true end
  else
    -- Prevent best-fit substitutions such as mapping a visually similar
    -- Unicode character to a different legacy-codepage character.
    if strict then flags = 1024 end -- WC_NO_BEST_FIT_CHARS
    used_default = ffi.new('int[1]')
  end

  C.SetLastError(0)
  local size = C.WideCharToMultiByte(codepage, flags, w, n, nil, 0, nil, used_default)
  if size == 0 then return winfailure('WideCharToMultiByte') end
  local out = ffi.new('char[?]', size)
  if used_default then used_default[0] = 0 end
  if C.WideCharToMultiByte(codepage, flags, w, n, out, size, nil, used_default) ~= size then
    return winfailure('WideCharToMultiByte')
  end

  if strict and used_default and used_default[0] ~= 0 then
    return nil, 'text cannot be represented in Windows code page ' .. tostring(codepage)
  end

  if strict and needs_roundtrip then
    local back, back_n = multibyte_wide(ffi.string(out, size), codepage)
    if not back then return nil, back_n end
    if not same_wide(w, n, back, back_n) then
      return nil, 'text cannot be represented in Windows code page ' .. tostring(codepage)
    end
  end

  return ffi.string(out, size)
end
function M.acp() return tonumber(C.GetACP()) end

function M.oemcp() return tonumber(C.GetOEMCP()) end

function M.codepage_to_utf8(text, codepage)
  local cp, err = codepage_number(codepage, M.acp())
  if not cp then return nil, err end
  local w, n = multibyte_wide(text, cp)
  if not w then return nil, n end
  return utf8(w, n)
end

function M.utf8_to_codepage(text, codepage, allow_lossy)
  local cp, err = codepage_number(codepage, M.acp())
  if not cp then return nil, err end
  local w, n = multibyte_wide(text, 65001)
  if not w then return nil, n end
  return wide_multibyte(w, n, cp, allow_lossy == true)
end

function M.ansi_to_utf8(text, codepage)
  if codepage == nil then codepage = M.acp() end
  return M.codepage_to_utf8(text, codepage)
end

function M.utf8_to_ansi(text, codepage, allow_lossy)
  if codepage == nil then codepage = M.acp() end
  return M.utf8_to_codepage(text, codepage, allow_lossy)
end

function M.oem_to_utf8(text, codepage)
  if codepage == nil then codepage = M.oemcp() end
  return M.codepage_to_utf8(text, codepage)
end

function M.utf8_to_oem(text, codepage, allow_lossy)
  if codepage == nil then codepage = M.oemcp() end
  return M.utf8_to_codepage(text, codepage, allow_lossy)
end

local function process_argv()
  local command = C.GetCommandLineW()
  if command == nil then return winfailure('GetCommandLineW') end
  local argc = ffi.new('int[1]')
  C.SetLastError(0)
  local argv = shell32.CommandLineToArgvW(command, argc)
  if argv == nil then return winfailure('CommandLineToArgvW') end
  local count = tonumber(argc[0])
  local result = {}
  local decode_error
  for i = 0, count - 1 do
    local value, err = utf8(argv[i], wlen(argv[i]))
    if not value then
      decode_error = err; break
    end
    result[i + 1] = value
  end
  C.LocalFree(argv)
  if decode_error then return nil, decode_error end
  return result
end
local function arg_numeric_range(tbl)
  local first, last, count
  for key in pairs(tbl) do
    if type(key) == 'number' and key == math.floor(key) then
      first = first and math.min(first, key) or key
      last = last and math.max(last, key) or key
      count = (count or 0) + 1
    end
  end
  return first, last, count or 0
end
function M.argv_raw()
  return process_argv()
end

function M.argv()
  local values, err, code = process_argv()
  if not values then return nil, err, code end
  local template = original.arg
  if type(template) ~= 'table' then return nil, 'global Lua arg table is unavailable' end
  local first, last, count = arg_numeric_range(template)
  if count ~= #values or not first or last - first + 1 ~= count then
    return nil, 'cannot map the Windows Unicode command line to Lua arg indices'
  end
  local result = {}
  for key, value in pairs(template) do
    if type(key) ~= 'number' or key ~= math.floor(key) then result[key] = value end
  end
  for i = 1, #values do result[first + i - 1] = values[i] end
  return result
end

function M.refresh_argv()
  local values, err, code = M.argv()
  if not values then return nil, err, code end
  _G.arg = values
  return values
end

local function handle(self)
  assert(self._fp ~= nil, 'attempt to use a closed file')
  return self._fp
end
local modes = {
  r = true,
  w = true,
  a = true,
  rb = true,
  wb = true,
  ab = true,
  ['r+'] = true,
  ['w+'] = true,
  ['a+'] = true,
  ['r+b'] = true,
  ['w+b'] = true,
  ['a+b'] = true,
  ['rb+'] = true,
  ['wb+'] = true,
  ['ab+'] = true
}
function M.open(path, mode)
  mode = mode or 'r'
  if not modes[mode] then return nil, 'unsupported file mode' end
  local w, err = pathwide(path)
  if not w then return nil, err end
  -- Microsoft CRT extension: N maps to _O_NOINHERIT. Ordinary files opened
  -- by this module are therefore not leaked into children created by popen().
  local wm = wide(mode .. 'N')
  local fp = crt._wfopen(w, wm)
  if fp == nil then return failure('open "' .. path .. '"') end
  return setmetatable({ _fp = ffi.gc(fp, function(p) crt.fclose(p) end), _path = path }, File)
end

function File:close()
  local fp = handle(self)
  ffi.gc(fp, nil)
  self._fp = nil
  if self._process then
    local closed = crt.fclose(fp)
    local close_errno = closed ~= 0 and tonumber(crt._errno()[0]) or nil
    local waited = C.WaitForSingleObject(self._process, 4294967295)
    local wait_error = waited == 4294967295 and tonumber(C.GetLastError()) or nil
    local result = ffi.new('unsigned long[1]')
    local ok = C.GetExitCodeProcess(self._process, result)
    local exit_error = ok == 0 and tonumber(C.GetLastError()) or nil
    C.CloseHandle(self._process); self._process = nil
    if close_errno then return nil, 'close pipe failed (CRT errno ' .. close_errno .. ')', close_errno end
    if wait_error then return winerror('WaitForSingleObject', wait_error) end
    if waited ~= 0 then return nil, 'WaitForSingleObject returned unexpected status ' .. tonumber(waited) end
    if exit_error then return winerror('GetExitCodeProcess', exit_error) end
    local status = tonumber(result[0])
    return status == 0 and true or nil, 'exit', status
  end
  if crt.fclose(fp) ~= 0 then return failure('close') end
  return true
end

function File:flush()
  if crt.fflush(handle(self)) ~= 0 then return failure('flush') end
  return true
end

function File:write(...)
  local fp = handle(self)
  for i = 1, select('#', ...) do
    local s = select(i, ...)
    assert(type(s) == 'string' or type(s) == 'number', 'write expects strings or numbers')
    s = tostring(s)
    if tonumber(crt.fwrite(s, 1, #s, fp)) ~= #s then return failure('write') end
  end
  return self
end

function File:seek(whence, offset)
  local origin = ({ set = 0, cur = 1, ['end'] = 2 })[whence or 'cur']
  assert(origin, 'invalid seek origin')
  offset = offset or 0
  assert(type(offset) == 'number' and offset == math.floor(offset)
    and math.abs(offset) <= 9007199254740991, 'invalid seek offset')
  local fp = handle(self)
  if crt._fseeki64(fp, offset, origin) ~= 0 then return failure('seek') end
  local position = ffi.new('int64_t[1]')
  if crt.fgetpos(fp, position) ~= 0 then return failure('tell') end
  local pos = position[0]
  if pos > 9007199254740991 then return nil, 'position exceeds exact Lua number range' end
  return tonumber(pos)
end

local read_buffer = ffi.new('char[65536]')

local function normalize_read_format(format)
  if type(format) ~= 'string' then return format end

  if format == 'a' or format == 'all' or format == '*a' or format == '*all' then
    return '*a'
  end

  if format == 'l' or format == 'line' or format == '*l' or format == '*line' then
    return '*l'
  end

  if format == 'L' or format == '*L' then
    return '*L'
  end

  if format == 'n' or format == 'number' or format == '*n' or format == '*number' then
    return '*n'
  end

  return format
end

local function read_one(fp, format)
  format = normalize_read_format(format)

  if format == '*n' then
    local value = ffi.new('double[1]')
    if crt.fscanf(fp, '%lf', value) == 1 then return tonumber(value[0]) end
    if crt.ferror(fp) ~= 0 then return failure('read') end
    return nil
  end
  if format == '*l' or format == '*L' then
    local chunks, bytes = {}, {}
    while true do
      local c = crt.fgetc(fp)
      if c == -1 then
        if crt.ferror(fp) ~= 0 then return failure('read') end
        if #chunks == 0 and #bytes == 0 then return nil end
        break
      end
      if c == 10 then
        if format == '*L' then
          bytes[#bytes + 1] = '\n'
        else
          -- For *l / line remove the complete Windows CRLF terminator.
          -- CR may be either in the current byte buffer or at the end of
          -- the previous 4096-byte chunk.
          if #bytes > 0 and bytes[#bytes] == '\r' then
            bytes[#bytes] = nil
          elseif #bytes == 0 and #chunks > 0 and chunks[#chunks]:sub(-1) == '\r' then
            chunks[#chunks] = chunks[#chunks]:sub(1, -2)
          end
        end
        break
      end
      bytes[#bytes + 1] = string.char(c)
      if #bytes == 4096 then
        chunks[#chunks + 1] = table.concat(bytes); bytes = {}
      end
    end
    chunks[#chunks + 1] = table.concat(bytes)
    return table.concat(chunks)
  end
  if format == '*a' or type(format) == 'number' then
    local all = format == '*a'
    local remaining = math.huge
    if type(format) == 'number' then
      assert(format >= 0 and format <= 9007199254740991 and format == math.floor(format), 'invalid byte count')
      if format == 0 then
        local c = crt.fgetc(fp)
        if c == -1 then
          if crt.ferror(fp) ~= 0 then return failure('read') end
          return nil
        end
        if crt.ungetc(c, fp) == -1 then return failure('ungetc') end
        return ''
      end
      remaining = format
    end
    local chunks = {}
    while remaining > 0 do
      local wanted = math.min(remaining, 65536)
      local n = tonumber(crt.fread(read_buffer, 1, wanted, fp))
      if n > 0 then
        chunks[#chunks + 1] = ffi.string(read_buffer, n); remaining = remaining - n
      end
      if n < wanted then
        if crt.ferror(fp) ~= 0 then return failure('read') end
        break
      end
    end
    if not all and #chunks == 0 then return nil end
    return table.concat(chunks)
  end
  error('supported read formats: a/all/*a/*all, l/line/*l/*line, L/*L, n/number/*n/*number, or byte count', 3)
end
function File:read(...)
  local fp = handle(self)
  local n = select('#', ...)
  if n == 0 then return read_one(fp, '*l') end
  local values = {}
  for i = 1, n do
    local value, err, code = read_one(fp, select(i, ...))
    if err then return nil, err, code end
    values[i] = value
    if value == nil then return unpack(values, 1, i) end
  end
  return unpack(values, 1, n)
end

local function iterator(file, autoclose, ...)
  local formats, n, done = { ... }, select('#', ...), false
  return function()
    if done then return nil end
    local values = { file:read(unpack(formats, 1, n)) }
    if values[1] == nil then
      done = true
      if autoclose then
        local ok, err = file:close()
        if not ok then error(err, 2) end
      end
      if values[2] then error(values[2], 2) end
      return nil
    end
    return unpack(values, 1, math.max(n, 1))
  end
end
function File:lines(...) return iterator(self, false, ...) end

function M.lines(path, ...)
  if path == nil then return M.input():lines(...) end
  return iterator(assert(M.open(path, 'r')), true, ...)
end

function M.rename(from, to)
  local a, err = pathwide(from); if not a then return nil, err end
  local b; b, err = pathwide(to); if not b then return nil, err end
  if C.MoveFileExW(a, b, 0) == 0 then return winfailure('MoveFileExW') end
  return true
end

---@param path string
---@param mode? string
---@param env? table
function M.loadfile(path, mode, env)
  if path == nil then
    return nil, 'path is required; use the standard loadfile() to read stdin'
  end
  local source, err = M.read_file(path, 'BINARY')
  if source == nil then return nil, err end
  if source:sub(1, 3) == '\239\187\191' then source = source:sub(4) end
  if source:sub(1, 1) == '#' then source = source:gsub('^[^\n]*', '', 1) end
  return load(source, '@' .. path, mode or 'bt', env)
end

function M.dofile(path) return assert(M.loadfile(path))() end

-- No guessed encoding for redirected stdin/stdout: return an explicit error.
local function console(id)
  local h = C.GetStdHandle(id)
  local mode = ffi.new('unsigned long[1]')
  if h == nil or h == ffi.cast('void *', -1) or C.GetConsoleMode(h, mode) == 0 then
    return nil, 'stream is not a Windows console (possibly redirected); read/write it with an explicit encoding'
  end
  return h, tonumber(mode[0])
end
function M.console_write(text)
  local w, n = wide(text, true)
  if not w then return nil, n end
  local h, err = console(4294967285) -- STD_OUTPUT_HANDLE = -11
  if not h then return nil, err end
  local written, offset = ffi.new('unsigned long[1]'), 0
  while offset < n do
    local count = math.min(8192, n - offset)
    local last = tonumber(w[offset + count - 1])
    if last >= 55296 and last <= 56319 and offset + count < n then count = count - 1 end
    if C.WriteConsoleW(h, w + offset, count, written, nil) == 0 then return winfailure('WriteConsoleW') end
    if written[0] == 0 then return nil, 'WriteConsoleW made no progress' end
    offset = offset + tonumber(written[0])
  end
  return true
end

function M.print(...)
  local parts = {}
  for i = 1, select('#', ...) do
    parts[i] = tostring(select(i, ...))
  end
  return M.console_write(table.concat(parts, '\t') .. '\r\n')
end

function M.console_readline(prompt)
  local h, mode = console(4294967286) -- STD_INPUT_HANDLE = -10
  if not h then return nil, mode end
  if math.floor(mode / 2) % 2 == 0 then return nil, 'console line-input mode must be enabled' end
  if prompt then
    local ok, err = M.console_write(prompt)
    if not ok then return nil, err end
  end
  local b, count, chunks = ffi.new('unsigned short[4096]'), ffi.new('unsigned long[1]'), {}
  while true do
    if C.ReadConsoleW(h, b, 4096, count, nil) == 0 then return winfailure('ReadConsoleW') end
    local n = tonumber(count[0])
    if n == 0 then return nil end
    chunks[#chunks + 1] = ffi.string(b, n * 2)
    if b[n - 1] == 10 then break end
  end
  local raw = table.concat(chunks)
  local w = ffi.new('unsigned short[?]', #raw / 2)
  ffi.copy(w, raw, #raw)
  local result, err = utf8(w, #raw / 2)
  if not result then return nil, err end
  return (result:gsub('\r?\n$', ''))
end

function File:setvbuf(mode, size)
  local code = ({ no = 4, full = 0, line = 64 })[mode]
  assert(code, 'invalid buffering mode')
  size = size or 8192
  assert(type(size) == 'number' and size >= 2 and size <= 2147483647 and size == math.floor(size), 'invalid buffer size')
  if crt.setvbuf(handle(self), nil, code, size) ~= 0 then return failure('setvbuf') end
  return true
end

local default_input, default_output = original.io.input(), original.io.output()
function M.type(file)
  if getmetatable(file) == File then return file._fp and 'file' or 'closed file' end
  return original.io.type(file)
end

local function default_file(value, current, mode)
  if value == nil then return current end
  if type(value) == 'string' then return assert(M.open(value, mode)) end
  assert(M.type(value) == 'file', 'expected an open file or UTF-8 path')
  return value
end
function M.input(value)
  default_input = default_file(value, default_input, 'r'); return default_input
end

function M.output(value)
  default_output = default_file(value, default_output, 'w'); return default_output
end

function M.read(...) return default_input:read(...) end

function M.write(...) return default_output:write(...) end

function M.flush() return default_output:flush() end

function M.close(file) return (file or default_output):close() end

local function has_attr(attributes, flag)
  return bit.band(attributes, flag) ~= 0
end
local function missing_path_error(code)
  return code == 2 or code == 3
end
local function attributes(path)
  local w, err = pathwide(path); if not w then return nil, err end
  C.SetLastError(0)
  local value = tonumber(C.GetFileAttributesW(w))
  if value == 4294967295 then
    local code = tonumber(C.GetLastError())
    if missing_path_error(code) then return false, nil, code end
    return winerror('GetFileAttributesW', code)
  end
  return value
end
-- Convert Windows FILETIME (100 ns ticks since 1601-01-01) without first
-- collapsing the full 64-bit tick count into a Lua double. Keeping the large
-- arithmetic in uint64_t preserves the sub-second part; only the final seconds
-- and remainder are converted to Lua numbers.
local U64 = ffi.typeof('uint64_t')
local FILETIME_TICKS_PER_SECOND = U64(10000000)
local FILETIME_EPOCH_SECONDS = U64(11644473600)
local FILETIME_EPOCH_TICKS = FILETIME_EPOCH_SECONDS * FILETIME_TICKS_PER_SECOND
local FILETIME_TWO32 = U64(4294967296)

local function filetime_to_unix(value)
  local high = U64(value.dwHighDateTime)
  local low = U64(value.dwLowDateTime)
  local ticks = high * FILETIME_TWO32 + low

  if ticks >= FILETIME_EPOCH_TICKS then
    local delta = ticks - FILETIME_EPOCH_TICKS
    local seconds = delta / FILETIME_TICKS_PER_SECOND
    local remainder = delta % FILETIME_TICKS_PER_SECOND
    return tonumber(seconds) + tonumber(remainder) / 10000000
  end

  local delta = FILETIME_EPOCH_TICKS - ticks
  local seconds = delta / FILETIME_TICKS_PER_SECOND
  local remainder = delta % FILETIME_TICKS_PER_SECOND
  return -(tonumber(seconds) + tonumber(remainder) / 10000000)
end
function M.getcwd()
  return native.cwd()
end

function M.chdir(path)
  local w, err = wide(path); if not w then return nil, err end
  local ok; ok, err = native.chdir(path)
  if not ok then return nil, err end
  return true
end

function M.abspath(path)
  local w, err = wide(path); if not w then return nil, err end
  -- Namespace paths are already absolute and preserve literal components.
  -- Canonicalizing them can redirect atomic writes or recursive removal to
  -- a different sibling whose name lacks the final dots/spaces.
  if path:sub(1, 4) == '\\\\?\\' or path:sub(1, 4) == '\\\\.\\' then return path end
  local n = C.GetFullPathNameW(w, 0, nil, nil)
  if n == 0 then return winfailure('GetFullPathNameW') end
  local b = ffi.new('unsigned short[?]', n)
  local len = C.GetFullPathNameW(w, n, b, nil)
  if len == 0 or len >= n then return winfailure('GetFullPathNameW') end
  return utf8(b, len)
end

function M.getenv(name)
  local w, err = wide(name); if not w then return nil, err end
  local value, msg, code = native.os_getenv(name)
  if code == 'ENOENT' then return nil end
  return value, msg
end

function M.setenv(name, value)
  local w, err = wide(name); if not w then return nil, err end
  if value ~= nil then
    w, err = wide(value, true); if not w then return nil, err end
  end
  local ok
  if value == nil then ok, err = native.os_unsetenv(name)
  else ok, err = native.os_setenv(name, value) end
  if not ok then return nil, err end
  return true
end

local function path_status(path)
  local w, err = wide(path); if not w then return nil, err end
  local info, msg, code = native.fs_lstat(path)
  if code == 'ENOENT' or code == 'ENOTDIR' then return false end
  if not info then return nil, msg end
  return info
end

function M.exists(path)
  local info, err = path_status(path)
  if info == nil then return nil, err end
  return info ~= false
end

function M.isfile(path)
  local info, err = path_status(path)
  if info == nil then return nil, err end
  if info == false then return false end
  if info.type == 'link' then
    local attr; attr, err = attributes(path)
    if attr == nil then return nil, err end
    return attr ~= false and not has_attr(attr, 16)
  end
  return info.type ~= 'directory'
end

function M.isdir(path)
  local info, err = path_status(path)
  if info == nil then return nil, err end
  if info == false then return false end
  if info.type == 'link' then
    local attr; attr, err = attributes(path)
    if attr == nil then return nil, err end
    return attr ~= false and has_attr(attr, 16)
  end
  return info.type == 'directory'
end

function M.stat(path)
  local w, err = pathwide(path); if not w then return nil, err end
  local data = ffi.new('uio_WIN32_FILE_ATTRIBUTE_DATA[1]')
  if C.GetFileAttributesExW(w, 0, data) == 0 then return winfailure('GetFileAttributesExW') end
  local info = data[0]
  local attr = tonumber(info.dwFileAttributes)
  local high, low = tonumber(info.nFileSizeHigh), tonumber(info.nFileSizeLow)
  local size = high * 4294967296 + low
  return {
    size = size,
    size_high = high,
    size_low = low,
    size_exact = size <= 9007199254740991,
    is_file = not has_attr(attr, 16),
    is_dir = has_attr(attr, 16),
    readonly = has_attr(attr, 1),
    hidden = has_attr(attr, 2),
    system = has_attr(attr, 4),
    archive = has_attr(attr, 32),
    temporary = has_attr(attr, 256),
    reparse_point = has_attr(attr, 1024),
    compressed = has_attr(attr, 2048),
    offline = has_attr(attr, 4096),
    not_content_indexed = has_attr(attr, 8192),
    encrypted = has_attr(attr, 16384),
    attributes = attr,
    creation_time = filetime_to_unix(info.ftCreationTime),
    access_time = filetime_to_unix(info.ftLastAccessTime),
    write_time = filetime_to_unix(info.ftLastWriteTime)
  }
end

local function set_attribute_flag(path, flag, enabled)
  if type(enabled) ~= 'boolean' then return nil, 'enabled must be boolean' end
  local attr, err, code = attributes(path)
  if attr == false then return nil, 'path does not exist', code end
  if attr == nil then return nil, err, code end

  local new_attr = attr
  local present = has_attr(attr, flag)
  if enabled and not present then
    if attr == 128 then new_attr = flag else new_attr = attr + flag end
  elseif not enabled and present then
    new_attr = attr - flag
    if new_attr == 0 then new_attr = 128 end
  else
    return true
  end

  local w, wide_err = pathwide(path); if not w then return nil, wide_err end
  if C.SetFileAttributesW(w, new_attr) == 0 then return winfailure('SetFileAttributesW') end
  return true
end

function M.set_readonly(path, enabled)
  return set_attribute_flag(path, 1, enabled)
end

function M.set_hidden(path, enabled)
  return set_attribute_flag(path, 2, enabled)
end

function M.set_archive(path, enabled)
  return set_attribute_flag(path, 32, enabled)
end

function M.mkdir(path)
  local w, err = wide(path); if not w then return nil, err end
  local ok; ok, err = native.fs_mkdir(path, 511)
  if not ok then return nil, err end
  return true
end

function M.rmdir(path)
  local w, err = wide(path); if not w then return nil, err end
  local ok; ok, err = native.fs_rmdir(path)
  if not ok then return nil, err end
  return true
end

local function drive_root(path)
  if #path == 3 and path:sub(2, 3) == ':\\' and path:sub(1, 1):match('%a') then return true end
  return #path == 7 and path:sub(1, 4) == '\\\\?\\' and path:sub(6, 7) == ':\\' and path:sub(5, 5):match('%a') ~= nil
end
local function unc_root(path)
  local rest
  if path:sub(1, 8) == '\\\\?\\UNC\\' then
    rest = path:sub(9)
  elseif path:sub(1, 2) == '\\\\' then
    rest = path:sub(3)
  else
    return false
  end
  local first = rest:find('\\', 1, true)
  if not first or first == 1 or first == #rest then return false end
  return rest:find('\\', first + 1, true) == nil
end
local function normalized_absolute(path)
  local absolute, err, code = M.abspath(path)
  if not absolute then return nil, err, code end
  absolute = absolute:gsub('/', '\\')
  if drive_root(absolute) then return absolute end
  absolute = absolute:gsub('\\+$', '')
  return absolute
end

-- Compare normalized Windows paths using Windows' Unicode ordinal
-- case-insensitive rules. Lua string.lower() only handles ASCII reliably.
local function path_is_same_or_child(parent, candidate)
  local parent_w, parent_n = wide(parent)
  if not parent_w then return nil, parent_n end
  local candidate_w, candidate_n = wide(candidate)
  if not candidate_w then return nil, candidate_n end
  if candidate_n < parent_n then return false end

  C.SetLastError(0)
  local compared = C.CompareStringOrdinal(parent_w, parent_n, candidate_w, parent_n, 1)
  if compared == 0 then return winfailure('CompareStringOrdinal') end
  if compared ~= 2 then return false end -- CSTR_EQUAL = 2
  if candidate_n == parent_n then return true end

  -- A drive root already ends in a separator (for example C:\).
  if parent_w[parent_n - 1] == 92 then return true end
  return candidate_w[parent_n] == 92
end
local function parent_path(path)
  if drive_root(path) or unc_root(path) then return nil end
  local pos
  for i = #path, 1, -1 do
    if path:sub(i, i) == '\\' then
      pos = i; break
    end
  end
  if not pos then return nil end
  local parent = path:sub(1, pos - 1)
  if #parent == 2 and parent:sub(2, 2) == ':' then parent = parent .. '\\' end
  if #parent == 6 and parent:sub(1, 4) == '\\\\?\\' and parent:sub(6, 6) == ':' then parent = parent .. '\\' end
  return parent ~= '' and parent or nil
end

-- Lexical Windows path helpers. They do not require the path to exist.
local function trim_trailing_separators(path)
  local value = path:gsub('/', '\\')
  while #value > 1 and value:sub(-1) == '\\' and not drive_root(value) and not unc_root(value) do
    value = value:sub(1, -2)
  end
  return value
end

function M.basename(path)
  if type(path) ~= 'string' then return nil, 'path must be a string' end
  local value = trim_trailing_separators(path)
  if value == '' or value == '\\' or drive_root(value) or unc_root(value) then return '' end
  local pos
  for i = #value, 1, -1 do
    if value:sub(i, i) == '\\' then
      pos = i; break
    end
  end
  return pos and value:sub(pos + 1) or value
end

function M.dirname(path)
  if type(path) ~= 'string' then return nil, 'path must be a string' end
  local value = trim_trailing_separators(path)
  if value == '' then return '.' end
  if value == '\\' or drive_root(value) or unc_root(value) then return value end
  local pos
  for i = #value, 1, -1 do
    if value:sub(i, i) == '\\' then
      pos = i; break
    end
  end
  if not pos then return '.' end
  local parent = value:sub(1, pos - 1)
  if parent == '' then return '\\' end
  if #parent == 2 and parent:sub(2, 2) == ':' then return parent .. '\\' end
  if #parent == 6 and parent:sub(1, 4) == '\\\\?\\' and parent:sub(6, 6) == ':' then return parent .. '\\' end
  return parent
end

function M.extension(path)
  local name, err = M.basename(path)
  if name == nil then return nil, err end
  local dot
  for i = #name, 1, -1 do
    if name:sub(i, i) == '.' then
      dot = i; break
    end
  end
  if not dot or dot == 1 or dot == #name then return '' end
  return name:sub(dot)
end

function M.stem(path)
  local name, err = M.basename(path)
  if name == nil then return nil, err end
  local ext, ext_err = M.extension(name)
  if ext == nil then return nil, ext_err end
  if ext == '' then return name end
  return name:sub(1, #name - #ext)
end

-- Join Windows path components without aggressively normalizing the whole path.
-- Absolute components are only accepted as the first component.
function M.join(...)
  local count = select('#', ...)
  if count == 0 then return '' end
  local result = ''
  for i = 1, count do
    local part = select(i, ...)
    if type(part) ~= 'string' then return nil, 'path component must be a string' end
    part = part:gsub('/', '\\')
    if part ~= '' then
      if result == '' then
        result = part
      else
        local absolute_drive = #part >= 3 and part:sub(2, 3) == ':\\' and part:sub(1, 1):match('%a') ~= nil
        if absolute_drive or part:sub(1, 2) == '\\\\' then
          return nil, 'absolute path component is only allowed first'
        end
        local left = result:gsub('\\+$', '')
        if left == '' and result:match('^\\+$') then left = '\\' end
        local right = part:gsub('^\\+', '')
        if right ~= '' then
          if left:sub(-1) == '\\' then result = left .. right else result = left .. '\\' .. right end
        end
      end
    end
  end
  return result
end

function M.makedirs(path)
  local absolute, err = normalized_absolute(path)
  if not absolute then return nil, err end
  local function ensure(current)
    local info, msg, code = native.fs_stat(current)
    if info then
      if info.type == 'directory' then return true end
      return nil, 'makedirs failed: path exists and is not a directory'
    end
    if code ~= 'ENOENT' then return nil, msg end
    local parent = parent_path(current)
    if parent then
      local ok; ok, msg = ensure(parent)
      if not ok then return nil, msg end
    end
    local ok; ok, msg, code = native.fs_mkdir(current, 511)
    if ok then return true end
    if code == 'EEXIST' then
      info = native.fs_stat(current)
      if info and info.type == 'directory' then return true end
    end
    return nil, msg
  end
  return ensure(absolute)
end

function M.listdir(path)
  local w, err = wide(path); if not w then return nil, err end
  local request; request, err = native.fs_scandir(path)
  if not request then return nil, err end
  local items = {}
  while true do
    local name, kind = native.fs_scandir_next(request)
    if not name then
      if kind then return nil, kind end
      break
    end
    items[#items + 1] = name
  end
  return items
end



local function glob_name_matches(name, mask)
  local wn, err = wide(name)
  if not wn then return nil, err end
  local wm; wm, err = wide(mask)
  if not wm then return nil, err end
  return shlwapi.PathMatchSpecW(wn, wm) ~= 0
end

local function namespace_path(absolute)
  if absolute:sub(1,4) == '\\\\?\\' or absolute:sub(1,4) == '\\\\.\\' then return absolute end
  if absolute:sub(1,2) == '\\\\' then return '\\\\?\\UNC\\' .. absolute:sub(3) end
  return '\\\\?\\' .. absolute
end

-- Enumerated names are literal. Preserve ordinary result paths unless Win32
-- normalization would change the child name; resolve bare C: before joining.
local function enumerated_child(dir, name)
  if dir:match('^%a:$') then
    local absolute, err = M.abspath(dir)
    if not absolute then return nil, err end
    dir = absolute
  end
  local stem = (name:match('^[^.]+') or ''):upper()
  if name:find('[ .]$') or stem == 'CON' or stem == 'PRN'
    or stem == 'AUX' or stem == 'NUL' or stem:match('^COM[1-9]$')
    or stem:match('^LPT[1-9]$') then
    local absolute, err = M.abspath(dir)
    if not absolute then return nil, err end
    dir = namespace_path(absolute)
  end
  return M.join(dir, name)
end

local function glob_files_in_dir(dir, mask, result)
  local names, err = M.listdir(dir)
  if not names then return nil, err end
  for _, name in ipairs(names) do
    local full; full, err = enumerated_child(dir, name)
    if not full then return nil, err end
    local info; info, err = M.stat(full)
    if not info then return nil, err end
    if info.is_file then
      local matched; matched, err = glob_name_matches(name, mask)
      if matched == nil then return nil, err end
      if matched then result[#result + 1] = full end
    end
  end
  return true
end

local function glob_subdirs(dir, result)
  local names, err = M.listdir(dir)
  if not names then return nil, err end
  for _, name in ipairs(names) do
    local full; full, err = enumerated_child(dir, name)
    if not full then return nil, err end
    local info; info, err = M.stat(full)
    if not info then return nil, err end
    if info.is_dir and not info.reparse_point then result[#result + 1] = full end
  end
  return true
end

-- Return matching files as paths. Wildcards are supported in the final component.
-- With recursive=true, matching files in subdirectories are included.
function M.glob(pattern, recursive)
  if type(pattern) ~= 'string' then return nil, 'glob pattern must be a string' end
  if recursive ~= nil and type(recursive) ~= 'boolean' then return nil, 'recursive must be boolean' end
  pattern = pattern:gsub('/', '\\')
  local pos
  for i = #pattern, 1, -1 do
    if pattern:sub(i, i) == '\\' then
      pos = i; break
    end
  end
  local dir, mask
  local implicit_current = not pos
  if pos then
    dir = pattern:sub(1, pos - 1)
    mask = pattern:sub(pos + 1)
    if dir == '' then dir = '\\' end
    if #dir == 2 and dir:sub(2, 2) == ':' then dir = dir .. '\\' end
    if #dir == 6 and dir:sub(1, 4) == '\\\\?\\' and dir:sub(6, 6) == ':' then dir = dir .. '\\' end
  else
    dir = '.'
    mask = pattern
  end
  if mask == '' then return nil, 'glob pattern must include a final name or wildcard' end
  -- The '?' in the extended-length prefix \\?\ is not a wildcard.
  -- Check only the directory portion after a Win32 device/extended prefix.
  local wildcard_dir = dir
  if wildcard_dir:sub(1, 4) == '\\\\?\\' or wildcard_dir:sub(1, 4) == '\\\\.\\' then
    wildcard_dir = wildcard_dir:sub(5)
  end
  if wildcard_dir:find('*', 1, true) or wildcard_dir:find('?', 1, true) then
    return nil, 'wildcards in directory components are not supported'
  end
  local isdir, err, code = M.isdir(dir)
  if isdir == nil then return nil, err, code end
  if not isdir then return {} end
  local result = {}
  local function scan(current)
    local ok, scan_err, scan_code = glob_files_in_dir(current, mask, result)
    if not ok then return nil, scan_err, scan_code end
    if recursive then
      local dirs = {}
      ok, scan_err, scan_code = glob_subdirs(current, dirs)
      if not ok then return nil, scan_err, scan_code end
      for _, child in ipairs(dirs) do
        ok, scan_err, scan_code = scan(child)
        if not ok then return nil, scan_err, scan_code end
      end
    end
    return true
  end
  local ok, scan_err, scan_code = scan(dir)
  if not ok then return nil, scan_err, scan_code end
  if implicit_current then
    for i = 1, #result do
      if result[i]:sub(1, 2) == '.\\' then result[i] = result[i]:sub(3) end
    end
  end
  table.sort(result)
  return result
end

local function clear_readonly_for_delete(w, attr, force)
  if not force or has_attr(attr, 16) or not has_attr(attr, 1) then return false end
  if C.SetFileAttributesW(w, attr - 1) == 0 then return winfailure('SetFileAttributesW') end
  return true
end

function M.remove(path, force)
  if force ~= nil and type(force) ~= 'boolean' then return nil, 'force must be boolean' end
  local w, err = pathwide(path); if not w then return nil, err end
  local attr, attr_err, attr_code = attributes(path)
  if attr == false then return nil, 'remove failed (Win32 error ' .. tostring(attr_code) .. ')', attr_code end
  if attr == nil then return nil, attr_err, attr_code end
  if has_attr(attr, 1) and not has_attr(attr, 16) and not force then return nil, 'remove failed: file is readonly' end
  local cleared, clear_err, clear_code = clear_readonly_for_delete(w, attr, force == true)
  if cleared == nil then return nil, clear_err, clear_code end
  local ok
  local delete_err
  if has_attr(attr, 16) then ok, delete_err = native.fs_rmdir(path) else ok, delete_err = native.fs_unlink(path) end
  if not ok then
    if cleared then C.SetFileAttributesW(w, attr) end
    return nil, delete_err
  end
  return true
end

local function ensure_parent_directory(path)
  local absolute, err, code = M.abspath(path)
  if not absolute then return nil, err, code end
  absolute = absolute:gsub('/', '\\')
  local parent = parent_path(absolute)
  if not parent then return true end
  return M.makedirs(parent)
end

function M.copy(from, to, overwrite)
  -- Validate the source before creating any destination directories.
  local source_info, source_err, source_code = M.stat(from)
  if not source_info then return nil, source_err, source_code end
  if not source_info.is_file then return nil, 'copy source is not a file: ' .. from, 267 end
  local a, err = wide(from); if not a then return nil, err end
  local ok, dir_err, dir_code = ensure_parent_directory(to)
  if not ok then return nil, dir_err, dir_code end
  local b; b, err = wide(to); if not b then return nil, err end
  local copied, copy_err = native.fs_copyfile(from, to, { excl = not overwrite })
  if not copied then return nil, copy_err end
  return true
end

function M.move(from, to, overwrite)
  -- MoveFileExW supports files and directories, so only existence is checked.
  local source_info, source_err, source_code = M.stat(from)
  if not source_info then return nil, source_err, source_code end
  local a, err = pathwide(from); if not a then return nil, err end
  local ok, dir_err, dir_code = ensure_parent_directory(to)
  if not ok then return nil, dir_err, dir_code end
  local b; b, err = pathwide(to); if not b then return nil, err end
  -- Replacement uses MoveFileExW. The no-replace variant below must
  -- remain atomic; a stat-then-rename check would have a race.
  if overwrite then
    local moved, move_err, move_code = native.fs_rename(from, to)
    if moved then return true end
    if move_code ~= 'EXDEV' then return nil, move_err end
    -- MOVEFILE_COPY_ALLOWED retains Windows cross-volume copy/delete behavior.
  end
  local flags = 2
  if overwrite then flags = flags + 1 end
  if C.MoveFileExW(a, b, flags) == 0 then
    local _, msg, code = winfailure('MoveFileExW "' .. from .. '" -> "' .. to .. '"')
    return nil, msg, code
  end
  return true
end

-- Recursively enumerate all children under path. The root itself is not
-- included. Directory reparse points are returned but never traversed.
function M.walk(path)
  local isdir, err, code = M.isdir(path)
  if isdir == nil then return nil, err, code end
  if not isdir then return nil, 'walk failed: path is not a directory', 267 end

  local result = {}
  local function scan(current)
    local names, list_err, list_code = M.listdir(current)
    if not names then return nil, list_err, list_code end
    table.sort(names)
    for _, name in ipairs(names) do
      local full, join_err = enumerated_child(current, name)
      if not full then return nil, join_err end
      local info, stat_err, stat_code = M.stat(full)
      if not info then return nil, stat_err, stat_code end
      result[#result + 1] = {
        path = full,
        name = name,
        is_file = info.is_file,
        is_dir = info.is_dir,
        size = info.size,
        readonly = info.readonly,
        hidden = info.hidden,
        reparse_point = info.reparse_point
      }
      if info.is_dir and not info.reparse_point then
        local ok, scan_err, scan_code = scan(full)
        if not ok then return nil, scan_err, scan_code end
      end
    end
    return true
  end

  local ok, scan_err, scan_code = scan(path)
  if not ok then return nil, scan_err, scan_code end
  return result
end

-- Recursively copy a directory tree. Destination directories are created
-- automatically. Reparse points are refused because this library does not
-- create equivalent links/junctions and must not silently follow them.
function M.copy_tree(from, to, overwrite)
  local source_info, err, code = M.stat(from)
  if not source_info then return nil, err, code end
  if not source_info.is_dir then return nil, 'copyTree source is not a directory', 267 end
  if source_info.reparse_point then return nil, 'copyTree source must not be a reparse point' end

  local source_abs; source_abs, err, code = normalized_absolute(from)
  if not source_abs then return nil, err, code end
  local destination_abs; destination_abs, err, code = normalized_absolute(to)
  if not destination_abs then return nil, err, code end
  -- Enumerated child names are literal, even when the caller used an ordinary
  -- root path. Preserve their spelling throughout recursion and metadata calls.
  from, to = namespace_path(source_abs), namespace_path(destination_abs)
  -- Resolve aliases (extended paths, short names and junction ancestors),
  -- including the existing ancestor of a not-yet-created destination.
  local function resolved(path)
    local suffix = ''
    while path do
      local real, real_err, real_code = native.fs_realpath(path)
      if real then return (real:gsub('\\+$', '')) .. suffix end
      if real_code ~= 'ENOENT' then return nil, real_err end
      local parent = parent_path(path)
      if not parent then return nil, real_err end
      suffix = '\\' .. path:sub(#parent + 1):gsub('^\\+', '') .. suffix
      path = parent
    end
  end
  source_abs, err = resolved(source_abs)
  if not source_abs then return nil, err end
  destination_abs, err = resolved(destination_abs)
  if not destination_abs then return nil, err end
  local same_or_child, compare_err, compare_code = path_is_same_or_child(source_abs, destination_abs)
  if same_or_child == nil then return nil, compare_err, compare_code end
  if same_or_child then
    return nil, 'copyTree destination must not be the source directory or a child of it'
  end

  local ok, dir_err, dir_code = M.makedirs(to)
  if not ok then return nil, dir_err, dir_code end

  local function copy_dir(source, destination)
    local attr, attr_err = attributes(destination)
    if attr == nil then return nil, attr_err end
    if attr ~= false and has_attr(attr, 1024) then
      return nil, 'copyTree destination must not be a reparse point: ' .. destination
    end
    local names, list_err, list_code = M.listdir(source)
    if not names then return nil, list_err, list_code end
    table.sort(names)
    for _, name in ipairs(names) do
      local source_child, join_err = M.join(source, name)
      if not source_child then return nil, join_err end
      local destination_child; destination_child, join_err = M.join(destination, name)
      if not destination_child then return nil, join_err end
      local destination_attr, destination_err = attributes(destination_child)
      if destination_attr == nil then return nil, destination_err end
      if destination_attr ~= false and has_attr(destination_attr, 1024) then
        return nil, 'copyTree destination must not be a reparse point: ' .. destination_child
      end
      local info, stat_err, stat_code = M.stat(source_child)
      if not info then return nil, stat_err, stat_code end
      if info.reparse_point then
        return nil, 'copyTree does not support reparse point: ' .. source_child
      elseif info.is_dir then
        local made, made_err, made_code = M.makedirs(destination_child)
        if not made then return nil, made_err, made_code end
        local copied, copy_err, copy_code = copy_dir(source_child, destination_child)
        if not copied then return nil, copy_err, copy_code end
      else
        local copied, copy_err, copy_code = M.copy(source_child, destination_child, overwrite)
        if not copied then return nil, copy_err, copy_code end
      end
    end
    return true
  end

  return copy_dir(from, to)
end

-- Recursively remove a file or directory tree. Directory reparse points are
-- removed as links and are never traversed. Drive/UNC roots are refused.
function M.remove_all(path, force)
  if force ~= nil and type(force) ~= 'boolean' then return nil, 'force must be boolean' end
  local absolute, err, code = normalized_absolute(path)
  if not absolute then return nil, err, code end
  if drive_root(absolute) or unc_root(absolute) then
    return nil, 'removeAll refuses to remove a drive or UNC root'
  end
  absolute = namespace_path(absolute)
  local attr; attr, err, code = attributes(absolute)
  if attr == false then return nil, 'removeAll failed (Win32 error ' .. tostring(code) .. ')', code end
  if attr == nil then return nil, err, code end
  if not has_attr(attr, 16) or has_attr(attr, 1024) then return M.remove(absolute, force) end
  local items; items, err, code = M.listdir(absolute)
  if not items then return nil, err, code end
  for _, name in ipairs(items) do
    local child, join_err = M.join(absolute, name)
    if not child then return nil, join_err end
    local child_attr; child_attr, err, code = attributes(child)
    if child_attr == nil then return nil, err, code end
    local ok
    if child_attr ~= false and has_attr(child_attr, 16) and not has_attr(child_attr, 1024) then
      ok, err, code = M.remove_all(child, force)
    else
      ok, err, code = M.remove(child, force)
    end
    if not ok then return nil, err, code end
  end
  return M.rmdir(absolute)
end

local function read_raw_file(path, limit)
  local w, err = wide(path); if not w then return nil, err end
  local fd; fd, err = native.fs_open(path, 'r', 438)
  if not fd then return nil, err end
  local chunks, offset = {}, 0
  while not limit or offset < limit do
    local data; data, err = native.fs_read(fd, math.min(65536, limit and limit - offset or 65536), offset)
    if not data or #data == 0 then break end
    chunks[#chunks + 1] = data
    offset = offset + #data
  end
  local closed, close_err = native.fs_close(fd)
  if err then return nil, err end
  if not closed then return nil, close_err end
  return table.concat(chunks)
end

local function encoding_info(encoding)
  if encoding == nil then return { kind = 'utf8', name = 'UTF-8' } end
  if type(encoding) == 'number' then
    if encoding == 65001 then return { kind = 'utf8', name = 'UTF-8' } end
    local cp, err = codepage_number(encoding, M.acp())
    if not cp then return nil, err end
    return { kind = 'codepage', codepage = cp, name = 'CP' .. tostring(cp) }
  end
  if type(encoding) ~= 'string' then return nil, 'encoding must be a string, code page number, or nil' end

  local name = encoding:upper():gsub('^%s+', ''):gsub('%s+$', '')
  local compact = name:gsub('[%s_%-]', '')

  if compact == 'BINARY' or compact == 'RAW' or compact == 'BYTES' then
    return { kind = 'binary', name = 'BINARY' }
  end
  if compact == 'UTF8' then
    return { kind = 'utf8', name = 'UTF-8' }
  end
  if compact == 'UTF8BOM' then
    return { kind = 'utf8bom', name = 'UTF-8-BOM' }
  end
  if compact == 'UTF16LE' then
    return { kind = 'utf16le', name = 'UTF-16LE' }
  end
  if compact == 'UTF16BE' then
    return { kind = 'utf16be', name = 'UTF-16BE' }
  end
  if compact == 'ANSI' or compact == 'ACP' then
    return { kind = 'codepage', codepage = M.acp(), name = 'ANSI' }
  end
  if compact == 'OEM' or compact == 'OEMCP' then
    return { kind = 'codepage', codepage = M.oemcp(), name = 'OEM' }
  end

  local cp_text = compact:match('^CP(%d+)$') or compact:match('^WINDOWS(%d+)$')
  if cp_text then
    local cp_number = tonumber(cp_text)
    if cp_number == 65001 then return { kind = 'utf8', name = 'UTF-8' } end
    local cp, err = codepage_number(cp_number, M.acp())
    if not cp then return nil, err end
    return { kind = 'codepage', codepage = cp, name = 'CP' .. tostring(cp) }
  end
  return nil, 'unsupported encoding: ' .. encoding
end

local UTF8_BOM = '\239\187\191'
local UTF16LE_BOM = '\255\254'
local UTF16BE_BOM = '\254\255'

local function validate_utf8_text(text)
  local w, err = multibyte_wide(text, 65001)
  if not w then return nil, err end
  return true
end

local function decode_utf16(text, big_endian)
  if #text % 2 ~= 0 then return nil, 'invalid UTF-16 byte length' end
  local count = #text / 2
  if count == 0 then return '' end
  local w = ffi.new('unsigned short[?]', count)
  if big_endian then
    local bytes = ffi.new('unsigned char[?]', #text)
    ffi.copy(bytes, text, #text)
    for i = 0, count - 1 do
      w[i] = tonumber(bytes[i * 2]) * 256 + tonumber(bytes[i * 2 + 1])
    end
  else
    ffi.copy(w, text, #text)
  end
  return utf8(w, count)
end

local function decode_text(content, encoding)
  local info, err = encoding_info(encoding)
  if not info then return nil, err end
  if info.kind == 'binary' then return content end
  if info.kind == 'utf8bom' or info.kind == 'utf8' then
    if content:sub(1, 3) == UTF8_BOM then content = content:sub(4) end
    local ok, utf8_err = validate_utf8_text(content)
    if not ok then return nil, utf8_err end
    return content
  end
  if info.kind == 'utf16le' then
    if content:sub(1, 2) == UTF16BE_BOM then return nil, 'encoding mismatch: file has UTF-16BE BOM' end
    if content:sub(1, 2) == UTF16LE_BOM then content = content:sub(3) end
    return decode_utf16(content, false)
  end
  if info.kind == 'utf16be' then
    if content:sub(1, 2) == UTF16LE_BOM then return nil, 'encoding mismatch: file has UTF-16LE BOM' end
    if content:sub(1, 2) == UTF16BE_BOM then content = content:sub(3) end
    return decode_utf16(content, true)
  end
  return M.codepage_to_utf8(content, info.codepage)
end

local function encode_utf16(text, big_endian, include_bom)
  local w, n = multibyte_wide(text, 65001)
  if not w then return nil, n end
  if not big_endian then
    local body = ffi.string(w, n * 2)
    return (include_bom and UTF16LE_BOM or '') .. body
  end
  local extra = include_bom and 2 or 0
  local out = ffi.new('unsigned char[?]', n * 2 + extra)
  local offset = 0
  if include_bom then
    out[0] = 254; out[1] = 255; offset = 2
  end
  for i = 0, n - 1 do
    local value = tonumber(w[i])
    out[offset + i * 2] = math.floor(value / 256)
    out[offset + i * 2 + 1] = value % 256
  end
  return ffi.string(out, n * 2 + extra)
end

local function encode_text(content, encoding, include_bom, allow_lossy)
  if type(content) ~= 'string' and type(content) ~= 'number' then return nil, 'content must be a string or number' end
  content = tostring(content)
  local info, err = encoding_info(encoding)
  if not info then return nil, err end
  if info.kind == 'binary' then return content end
  if info.kind == 'utf8bom' or info.kind == 'utf8' then
    local ok, utf8_err = validate_utf8_text(content)
    if not ok then return nil, utf8_err end
    if info.kind == 'utf8bom' and include_bom then return UTF8_BOM .. content end
    return content
  end
  if info.kind == 'utf16le' then return encode_utf16(content, false, include_bom) end
  if info.kind == 'utf16be' then return encode_utf16(content, true, include_bom) end
  return M.utf8_to_codepage(content, info.codepage, allow_lossy == true)
end

local function read_file_prefix(path, count)
  return read_raw_file(path, count)
end

local function write_raw_file(path, content, mode)
  local w, err = wide(path); if not w then return nil, err end
  local fd; fd, err = native.fs_open(path, mode == 'ab' and 'a' or 'w', 438)
  if not fd then return nil, err end
  local offset = 0
  while offset < #content do
    local n; n, err = native.fs_write(fd, content:sub(offset + 1), -1)
    if not n then break end
    if n == 0 then err = 'write made no progress'; break end
    offset = offset + n
  end
  if not err then local ok; ok, err = native.fs_fsync(fd) end
  local closed, close_err = native.fs_close(fd)
  if err then return nil, err end
  if not closed then return nil, close_err end
  return true
end

-- Create a temporary file in the destination directory so the final rename is
-- on the same volume. The temporary file is removed on every handled error path.
local function temporary_path_for(path)
  local absolute, err = M.abspath(path)
  if not absolute then return nil, err end
  local fd, name = native.fs_mkstemp(M.join(M.dirname(absolute), 'uioXXXXXX'))
  if not fd then return nil, name end
  local ok; ok, err = native.fs_close(fd)
  if not ok then native.fs_unlink(name); return nil, err end
  return name
end

local function atomic_write_raw(path, content)
  local absolute, err, code = M.abspath(path)
  if not absolute then return nil, err, code end
  local ok; ok, err, code = ensure_parent_directory(absolute)
  if not ok then return nil, err, code end

  local temp; temp, err, code = temporary_path_for(absolute)
  if not temp then return nil, err, code end

  local written, write_err, write_code = write_raw_file(temp, content, 'wb')
  if not written then
    M.remove(temp, true)
    return nil, write_err, write_code
  end

  local wtemp, wide_err = pathwide(temp)
  if not wtemp then
    M.remove(temp, true); return nil, wide_err
  end
  local wtarget; wtarget, wide_err = pathwide(absolute)
  if not wtarget then
    M.remove(temp, true); return nil, wide_err
  end

  -- MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH.
  if C.MoveFileExW(wtemp, wtarget, 9) == 0 then
    local move_code = tonumber(C.GetLastError())
    M.remove(temp, true)
    return winerror('atomic replace "' .. path .. '"', move_code)
  end
  return true
end

function M.read_file(path, encoding)
  local content, err, code = read_raw_file(path)
  if content == nil then return nil, err, code end
  local decoded, decode_err = decode_text(content, encoding)
  if decoded == nil then return nil, decode_err end
  return decoded
end

function M.write_file(path, content, encoding, allow_lossy)
  local data, encode_err = encode_text(content, encoding, true, allow_lossy)
  if data == nil then return nil, encode_err end
  return atomic_write_raw(path, data)
end

local function detected_bom(prefix)
  if prefix:sub(1, 3) == UTF8_BOM then return 'UTF-8-BOM' end
  if prefix:sub(1, 2) == UTF16LE_BOM then return 'UTF-16LE' end
  if prefix:sub(1, 2) == UTF16BE_BOM then return 'UTF-16BE' end
  return nil
end

local function bom_matches_encoding(bom, info)
  if bom == nil or info.kind == 'binary' then return true end
  if bom == 'UTF-8-BOM' then return info.kind == 'utf8' or info.kind == 'utf8bom' end
  if bom == 'UTF-16LE' then return info.kind == 'utf16le' end
  if bom == 'UTF-16BE' then return info.kind == 'utf16be' end
  return false
end

function M.append_file(path, content, encoding, allow_lossy)
  local info, info_err = encoding_info(encoding)
  if not info then return nil, info_err end

  local exists, exists_err, exists_code = M.exists(path)
  if exists == nil then return nil, exists_err, exists_code end

  local include_bom = false
  if not exists then
    include_bom = info.kind == 'utf8bom' or info.kind == 'utf16le' or info.kind == 'utf16be'
  else
    local stat, stat_err, stat_code = M.stat(path)
    if not stat then return nil, stat_err, stat_code end
    if stat.size == 0 then
      include_bom = info.kind == 'utf8bom' or info.kind == 'utf16le' or info.kind == 'utf16be'
    elseif info.kind ~= 'binary' then
      local prefix, read_err, read_code = read_file_prefix(path, 3)
      if prefix == nil then return nil, read_err, read_code end
      local bom = detected_bom(prefix)
      if info.kind == 'utf8bom' and bom == nil then
        local existing, read_err = M.read_file(path, encoding)
        if existing == nil then return nil, read_err end
        if type(content) ~= 'string' and type(content) ~= 'number' then
          return nil, 'content must be a string or number'
        end
        return M.write_file(path, existing .. tostring(content), encoding, allow_lossy)
      end
      if bom and not bom_matches_encoding(bom, info) then
        return nil, 'encoding mismatch: existing file has ' .. bom .. ' BOM'
      end
    end
  end

  local encoded, err = encode_text(content, encoding, include_bom, allow_lossy)
  if encoded == nil then return nil, err end
  local ok, parent_err, parent_code = ensure_parent_directory(path)
  if not ok then return nil, parent_err, parent_code end
  return write_raw_file(path, encoded, 'ab')
end

-- Read text for an in-place line edit and remember whether the existing file
-- physically has the BOM appropriate for the selected encoding. Line edits use
-- this bit when rewriting so changing a line never adds or removes a BOM.
local function read_text_for_line_edit(path, encoding)
  local raw, err, code = read_raw_file(path)
  if raw == nil then return nil, err, code end
  local info, info_err = encoding_info(encoding)
  if not info then return nil, info_err end

  local had_bom = false
  if info.kind == 'utf8' or info.kind == 'utf8bom' then
    had_bom = raw:sub(1, 3) == UTF8_BOM
  elseif info.kind == 'utf16le' then
    had_bom = raw:sub(1, 2) == UTF16LE_BOM
  elseif info.kind == 'utf16be' then
    had_bom = raw:sub(1, 2) == UTF16BE_BOM
  end

  local decoded, decode_err = decode_text(raw, encoding)
  if decoded == nil then return nil, decode_err end
  return decoded, nil, nil, had_bom
end

local function rewrite_text_preserving_bom(path, content, encoding, had_bom, allow_lossy)
  local info, info_err = encoding_info(encoding)
  if not info then return nil, info_err end
  local output_encoding = encoding
  if had_bom and info.kind == 'utf8' then output_encoding = 'UTF-8-BOM' end
  local data, encode_err = encode_text(content, output_encoding, had_bom, allow_lossy)
  if data == nil then return nil, encode_err end
  return atomic_write_raw(path, data)
end

-- Text line helpers. These operate on decoded UTF-8 Lua strings and rewrite the
-- complete file for replace/insert operations. Existing line separators are
-- preserved for untouched lines. Line numbers are 1-based.
local function parse_text_lines(text)
  local lines = {}
  local pos = 1
  local len = #text

  if len == 0 then return lines end

  while pos <= len do
    local start = pos
    while pos <= len do
      local byte = text:byte(pos)
      if byte == 10 or byte == 13 then break end
      pos = pos + 1
    end

    local value = text:sub(start, pos - 1)
    local separator = ''

    if pos <= len then
      local byte = text:byte(pos)
      if byte == 13 and pos < len and text:byte(pos + 1) == 10 then
        separator = '\r\n'
        pos = pos + 2
      elseif byte == 13 then
        separator = '\r'
        pos = pos + 1
      else
        separator = '\n'
        pos = pos + 1
      end
    end

    lines[#lines + 1] = { text = value, sep = separator }
  end

  return lines
end

local function preferred_newline(lines)
  for i = 1, #lines do
    if lines[i].sep ~= '' then return lines[i].sep end
  end
  return '\r\n'
end

local function build_text_lines(lines)
  local out = {}
  for i = 1, #lines do
    out[#out + 1] = lines[i].text
    out[#out + 1] = lines[i].sep
  end
  return table.concat(out)
end

local function validate_line_number(line_number)
  if type(line_number) ~= 'number' or line_number ~= math.floor(line_number) or line_number < 1 then
    return nil, 'line number must be a positive integer'
  end
  return true
end

local function validate_line_text(text)
  if type(text) ~= 'string' and type(text) ~= 'number' then
    return nil, 'line text must be a string or number'
  end
  text = tostring(text)
  if text:find('\r', 1, true) or text:find('\n', 1, true) then
    return nil, 'line text must not contain CR or LF; use writeFile() for multi-line text'
  end
  return text
end

-- Return all logical lines as a Lua table without CR/LF terminators.
-- Empty file -> {}. Line numbering for readLine/writeLine/insertLine is 1-based.
function M.read_lines(path, encoding)
  local text, err, code = M.read_file(path, encoding)
  if text == nil then return nil, err, code end
  local records = parse_text_lines(text)
  local lines = {}
  for i = 1, #records do lines[i] = records[i].text end
  return lines
end

function M.line_count(path, encoding)
  local lines, err, code = M.read_lines(path, encoding)
  if not lines then return nil, err, code end
  return #lines
end

function M.read_line(path, line_number, encoding)
  local ok, number_err = validate_line_number(line_number)
  if not ok then return nil, number_err end
  local text, err, code = M.read_file(path, encoding)
  if text == nil then return nil, err, code end
  local records = parse_text_lines(text)
  if line_number > #records then
    return nil
  end
  return records[line_number].text
end

-- Replace an existing line. The number of lines does not change.
function M.write_line(path, line_number, text, encoding, allow_lossy)
  local ok, number_err = validate_line_number(line_number)
  if not ok then return nil, number_err end
  local value, text_err = validate_line_text(text)
  if value == nil then return nil, text_err end

  local content, err, code, had_bom = read_text_for_line_edit(path, encoding)
  if content == nil then return nil, err, code end
  local records = parse_text_lines(content)
  if line_number > #records then
    return nil, 'line ' .. tostring(line_number) .. ' does not exist'
  end

  records[line_number].text = value
  return rewrite_text_preserving_bom(path, build_text_lines(records), encoding, had_bom, allow_lossy)
end

-- Insert a new line BEFORE line_number and shift that line and all following
-- lines down by one. line_number may also be #lines + 1 to append a line.
function M.insert_line(path, line_number, text, encoding, allow_lossy)
  local ok, number_err = validate_line_number(line_number)
  if not ok then return nil, number_err end
  local value, text_err = validate_line_text(text)
  if value == nil then return nil, text_err end

  local content, err, code, had_bom = read_text_for_line_edit(path, encoding)
  if content == nil then return nil, err, code end
  local records = parse_text_lines(content)
  local count = #records

  if line_number > count + 1 then
    return nil, 'line ' .. tostring(line_number) .. ' is beyond insertion position ' .. tostring(count + 1)
  end

  if count == 0 then
    records[1] = { text = value, sep = '' }
  elseif line_number <= count then
    local newline = preferred_newline(records)
    table.insert(records, line_number, { text = value, sep = newline })
  else
    local newline = preferred_newline(records)
    local had_final_newline = records[count].sep ~= ''
    if records[count].sep == '' then records[count].sep = newline end
    records[#records + 1] = { text = value, sep = had_final_newline and newline or '' }
  end

  return rewrite_text_preserving_bom(path, build_text_lines(records), encoding, had_bom, allow_lossy)
end

-- Append one logical line to the end of a text file. If the file does not
-- exist it is created. The appended line itself is left without a trailing
-- newline unless the existing file already ended with one.
function M.append_line(path, text, encoding, allow_lossy)
  local value, text_err = validate_line_text(text)
  if value == nil then return nil, text_err end

  local exists, exists_err, exists_code = M.exists(path)
  if exists == nil then return nil, exists_err, exists_code end
  if not exists then return M.write_file(path, value, encoding, allow_lossy) end

  local content, err, code, had_bom = read_text_for_line_edit(path, encoding)
  if content == nil then return nil, err, code end
  if content == '' then return rewrite_text_preserving_bom(path, value, encoding, had_bom, allow_lossy) end

  local records = parse_text_lines(content)
  local count = #records
  local newline = preferred_newline(records)
  local had_final_newline = records[count].sep ~= ''
  if records[count].sep == '' then records[count].sep = newline end
  records[#records + 1] = { text = value, sep = had_final_newline and newline or '' }

  return rewrite_text_preserving_bom(path, build_text_lines(records), encoding, had_bom, allow_lossy)
end

function M.tmpname()
  local dir, err = native.os_tmpdir()
  if not dir then return nil, err end
  local fd, name = native.fs_mkstemp(M.join(dir, 'ljuXXXXXX'))
  if not fd then return nil, name end
  local ok; ok, err = native.fs_close(fd)
  if not ok then native.fs_unlink(name); return nil, err end
  return name
end

function M.tmpfile()
  local path, err, code = M.tmpname()
  if not path then return nil, err, code end
  local w, wm = wide(path), wide('w+bDN') -- Delete-on-close and non-inheritable.
  local fp = crt._wfopen(w, wm)
  if fp == nil then
    local _, err, code = failure('tmpfile'); M.remove(path); return nil, err, code
  end
  return setmetatable({ _fp = ffi.gc(fp, function(p) crt.fclose(p) end) }, File)
end

local invalid_handle = ffi.cast('void *', -1)
local function duplicate_inheritable_handle(source)
  if source == nil or source == invalid_handle then return nil end
  local target = ffi.new('void *[1]')
  local process = C.GetCurrentProcess()
  if C.DuplicateHandle(process, source, process, target, 0, 1, 2) == 0 then
    return winfailure('DuplicateHandle')
  end
  return target[0]
end

-- STARTF_USESTDHANDLES requires valid inheritable handles. GUI/detached
-- processes can have no standard handles, so use NUL for the missing ones.
local function inheritable_null_handle(for_input)
  local name, err = wide('NUL')
  if not name then return nil, err end
  local sa = ffi.new('uio_SECURITY_ATTRIBUTES')
  ---@cast sa any
  sa.nLength = ffi.sizeof(sa)
  sa.bInheritHandle = 1
  local access = for_input and 2147483648 or 1073741824     -- GENERIC_READ / GENERIC_WRITE
  C.SetLastError(0)
  local h = C.CreateFileW(name, access, 3, sa, 3, 128, nil) -- FILE_SHARE_READ|WRITE, OPEN_EXISTING
  if h == invalid_handle then return winfailure('CreateFileW("NUL")') end
  return h
end

function M.popen(command, mode)
  mode = mode or 'r'
  if mode ~= 'r' and mode ~= 'w' and mode ~= 'rb' and mode ~= 'wb' then return nil, 'invalid popen mode' end
  local validated, err = wide(command); if not validated then return nil, err end
  local shell = M.getenv('COMSPEC') or 'C:\\Windows\\System32\\cmd.exe'
  local app; app, err = wide(shell); if not app then return nil, err end
  local cmdline; cmdline, err = wide('"' .. shell .. '" /d /s /c "' .. command .. '"')
  if not cmdline then return nil, err end
  local ends = ffi.new('void *[2]')
  local sa = ffi.new('uio_SECURITY_ATTRIBUTES')
  ---@cast sa any
  sa.nLength = ffi.sizeof(sa); sa.bInheritHandle = 1
  if C.CreatePipe(ends, ends + 1, sa, 0) == 0 then return winfailure('CreatePipe') end
  local reading = mode:sub(1, 1) == 'r'
  local parent = ends[reading and 0 or 1]
  local child = ends[reading and 1 or 0]
  if C.SetHandleInformation(parent, 1, 0) == 0 then
    local _, msg, code = winfailure('SetHandleInformation'); C.CloseHandle(parent); C.CloseHandle(child)
    return nil, msg, code
  end
  -- Attach the parent end to this module's CRT before starting the child.
  local flags = (reading and 0 or 1) + (mode:find('b', 1, true) and 32768 or 16384)
  local fd = crt._open_osfhandle(ffi.cast('intptr_t', parent), flags)
  if fd == -1 then
    local _, msg, code = failure('open pipe'); C.CloseHandle(parent); C.CloseHandle(child); return nil, msg, code
  end
  local fp = crt._fdopen(fd, mode)
  if fp == nil then
    local _, msg, code = failure('fdopen'); crt._close(fd); C.CloseHandle(child); return nil, msg, code
  end

  local dup_input, dup_output, dup_error
  local function duplicate_std(id, for_input)
    local h = C.GetStdHandle(id)
    if h == nil or h == invalid_handle then return inheritable_null_handle(for_input) end
    return duplicate_inheritable_handle(h)
  end
  local function close_duplicates()
    if dup_input ~= nil then
      C.CloseHandle(dup_input); dup_input = nil
    end
    if dup_output ~= nil then
      C.CloseHandle(dup_output); dup_output = nil
    end
    if dup_error ~= nil then
      C.CloseHandle(dup_error); dup_error = nil
    end
  end
  local function duplicate_or_fail(id, for_input)
    local h, msg, code = duplicate_std(id, for_input)
    if msg then return nil, msg, code end
    return h
  end

  local msg, code
  if reading then
    dup_input, msg, code = duplicate_or_fail(4294967286, true)
    if msg then
      C.CloseHandle(child); crt.fclose(fp); return nil, msg, code
    end
  else
    dup_output, msg, code = duplicate_or_fail(4294967285, false)
    if msg then
      C.CloseHandle(child); crt.fclose(fp); return nil, msg, code
    end
  end
  dup_error, msg, code = duplicate_or_fail(4294967284, false)
  if msg then
    close_duplicates(); C.CloseHandle(child); crt.fclose(fp); return nil, msg, code
  end

  local si = ffi.new('uio_STARTUPINFOW')
  ---@cast si any
  si.cb = ffi.sizeof(si); si.dwFlags = 256
  if reading then
    si.hStdInput = dup_input
    si.hStdOutput = child
  else
    si.hStdInput = child
    si.hStdOutput = dup_output
  end
  si.hStdError = dup_error
  local pi = ffi.new('uio_PROCESS_INFORMATION')
  ---@cast pi any
  local success = C.CreateProcessW(app, cmdline, nil, nil, 1, 134217728, nil, nil, si, pi)
  local create_msg, create_code
  if success == 0 then
    local ignored
    ignored, create_msg, create_code = winfailure('CreateProcessW')
  end
  C.CloseHandle(child)
  close_duplicates()
  if success == 0 then
    crt.fclose(fp); return nil, create_msg, create_code
  end
  C.CloseHandle(pi.hThread)
  local process = pi.hProcess
  return setmetatable({
    _process = process,
    _fp = ffi.gc(fp, function(p)
      crt.fclose(p); C.CloseHandle(process)
    end)
  }, File)
end

function M.execute(command)
  if command == nil then return crt._wsystem(nil) ~= 0 end
  local w, err = wide(command); if not w then return nil, err end
  local status = crt._wsystem(w)
  if status == -1 then return failure('execute') end
  return status -- LuaJIT's default Lua 5.1 convention.
end

function M.searchpath(name, path, sep, rep)
  assert(type(name) == 'string' and type(path) == 'string', 'name and path must be strings')
  sep, rep = sep or '.', rep or '\\'
  local mapped = name
  if sep ~= '' then mapped = name:gsub(sep:gsub('(%W)', '%%%1'), function() return rep end) end
  local errors = {}
  for template in path:gmatch('[^;]+') do
    local candidate = template:gsub('%?', function() return mapped end)
    local f = M.open(candidate, 'rb')
    if f then
      f:close(); return candidate
    end
    errors[#errors + 1] = "\n\tno file '" .. candidate .. "'"
  end
  return nil, table.concat(errors)
end

-- Explicit typed DLL access for FFI; retain DLLs until process exit so function
-- pointers cannot outlive their code. This is not a replacement ffi namespace.
local dlls = {}
function M.load_library(path)
  local w, err = wide(path); if not w then return nil, err end
  local h = dlls[path]
  if not h then
    h = C.LoadLibraryW(w)
    if h == nil then return winfailure('LoadLibraryW') end
    dlls[path] = h
  end
  return {
    symbol = function(_, name, ctype)
      assert(type(name) == 'string' and not name:find('\0', 1, true), 'invalid symbol name')
      local address = C.GetProcAddress(h, name)
      if address == nil then return winfailure('GetProcAddress') end
      return ffi.cast(ctype, address)
    end
  }
end

-- Friendly aliases for the extra fs API. These do not replace standard Lua names.
M.loadLibrary = M.load_library
M.dir = M.listdir
M.fileExists = M.isfile
M.dirExists = M.isdir
M.createDir = M.makedirs
M.removeDir = M.rmdir
M.copyFile = M.copy
M.getCurrentDir = M.getcwd
M.setCurrentDir = M.chdir
M.removeAll = M.remove_all
M.copyTree = M.copy_tree
M.setReadonly = M.set_readonly
M.setHidden = M.set_hidden
M.setArchive = M.set_archive
---@param path string
---@param encoding? string|number
---@return string|nil, string|nil, number|nil
function M.readFile(path, encoding)
  local value, err, code = M.read_file(path, encoding)
  ---@cast value string|nil
  ---@cast err string|nil
  ---@cast code number|nil
  return value, err, code
end

---@param path string
---@param content string|number
---@param encoding? string|number
---@param allow_lossy? boolean
---@return boolean|nil, string|nil, number|nil
function M.writeFile(path, content, encoding, allow_lossy)
  local ok, err, code = M.write_file(path, content, encoding, allow_lossy)
  ---@cast ok boolean|nil
  ---@cast err string|nil
  ---@cast code number|nil
  return ok, err, code
end

---@param path string
---@param content string|number
---@param encoding? string|number
---@param allow_lossy? boolean
---@return boolean|nil, string|nil, number|nil
function M.appendFile(path, content, encoding, allow_lossy)
  local ok, err, code = M.append_file(path, content, encoding, allow_lossy)
  ---@cast ok boolean|nil
  ---@cast err string|nil
  ---@cast code number|nil
  return ok, err, code
end

M.size = function(path)
  local info, err, code = M.stat(path)
  if not info then return nil, err, code end
  return info.size
end
M.fileSize = M.size
M.pathType = function(path)
  local attr, err, code = attributes(path)
  if attr == false then return nil end
  if attr == nil then return nil, err, code end
  return has_attr(attr, 16) and 'directory' or 'file'
end

-- Friendly aliases for text helpers.
M.readLines = M.read_lines
M.readLine = M.read_line
M.writeLine = M.write_line
M.insertLine = M.insert_line
M.appendLine = M.append_line
M.lineCount = M.line_count

M.version = '3.4-standalone'
M.default_encoding = 'UTF-8'
package.loaded[singleton_key] = M
return M
