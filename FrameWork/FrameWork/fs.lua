-- fs 6.12.2 - Windows files, directories, paths and text encodings.
-- Use FileRead/FileWrite for ordinary reads/writes; they open and close internally.
-- Native io.open and native file methods handle advanced streaming tasks.
-- Text helpers default to UTF-8, except FileReadLine without encoding (native io.lines).
-- No global io/os/package functions are replaced. Public functions have one name.

local ffi = require('ffi')
local bit = require('bit')
local native = require('_win_native')
local PathWide = native.PathWide
local errors = require('_errors')
assert(ffi.os == 'Windows', 'fs requires Windows')
ffi.cdef [[
typedef struct {
    uint32_t Data1;
    uint16_t Data2;
    uint16_t Data3;
    uint8_t Data4[8];
} LJ_FILES_GUID;
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

int32_t __stdcall SHGetKnownFolderPath(
    const LJ_FILES_GUID *rfid,
    uint32_t dwFlags,
    void *hToken,
    uint16_t **ppszPath
);

void __stdcall CoTaskMemFree(
    void *pv
);

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
int __stdcall CopyFileW(const unsigned short *, const unsigned short *, int);
int __stdcall DeleteFileW(const unsigned short *);
int __stdcall MultiByteToWideChar(unsigned int, unsigned long, const char *, int, unsigned short *, int);
int __stdcall WideCharToMultiByte(unsigned int, unsigned long, const unsigned short *, int, char *, int, const char *, int *);
unsigned long __stdcall GetLastError(void);
unsigned int __stdcall GetACP(void);
unsigned int __stdcall GetOEMCP(void);
int __stdcall IsValidCodePage(unsigned int);
int __stdcall PathMatchSpecW(const unsigned short *, const unsigned short *);
]]
local shlwapi = ffi.load('shlwapi')
local C = ffi.C
local M = {}

local Winerror = errors.Win32
local Winfailure = Winerror
local function Wide(s, allow_empty)
  if type(s) ~= 'string' then return nil, 'Требуется строка UTF-8' end
  if s:find('\0', 1, true) then return nil, 'Нулевой байт в строке недопустим' end
  if s == '' then
    if allow_empty then return ffi.new('unsigned short[1]'), 0 end
    return nil, 'Требуется непустой путь'
  end
  local n = C.MultiByteToWideChar(65001, 8, s, #s, nil, 0)
  if n == 0 then return Winfailure('MultiByteToWideChar') end
  local w = ffi.new('unsigned short[?]', n + 1)
  if C.MultiByteToWideChar(65001, 8, s, #s, w, n) ~= n then return Winfailure('UTF-8 decode') end
  return w, n
end
-- Validate before delegating without allocating a discarded UTF-16 buffer.
-- Keep the same argument and conversion errors as Wide(path).
local function ValidatePath(s)
  if type(s) ~= 'string' then return nil, 'Требуется строка UTF-8' end
  if s:find('\0', 1, true) then return nil, 'Нулевой байт в строке недопустим' end
  if s == '' then return nil, 'Требуется непустой путь' end
  if C.MultiByteToWideChar(65001, 8, s, #s, nil, 0) == 0 then
    return Winfailure('MultiByteToWideChar')
  end
  return true
end

local function Utf8(w, n)
  if n == 0 then return '' end
  local size = C.WideCharToMultiByte(65001, 128, w, n, nil, 0, nil, nil)
  if size == 0 then return Winfailure('UTF-16 decode') end
  local b = ffi.new('char[?]', size)
  if C.WideCharToMultiByte(65001, 128, w, n, b, size, nil, nil) ~= size then
    return Winfailure('UTF-16 decode')
  end
  return ffi.string(b, size)
end
local function Wlen(w)
  local n = 0
  while w[n] ~= 0 do n = n + 1 end
  return n
end
local function CodepageNumber(codepage, default_codepage)
  if codepage == nil then codepage = default_codepage end
  if type(codepage) ~= 'number' or codepage ~= math.floor(codepage) or codepage < 0 or codepage > 4294967295 then
    return nil, 'invalid Windows code page'
  end
  if codepage == 0 then codepage = tonumber(C.GetACP()) end
  if codepage == 1 then codepage = tonumber(C.GetOEMCP()) end
  if C.IsValidCodePage(codepage) == 0 then return nil, 'unsupported Windows code page ' .. tostring(codepage) end
  return codepage
end
local function MultibyteWide(text, codepage)
  if type(text) ~= 'string' then return nil, 'expected a byte string' end
  if #text > 2147483647 then return nil, 'string is too large' end
  if text == '' then return ffi.new('unsigned short[1]'), 0 end
  local flags = (codepage == 65001 or codepage == 54936) and 8 or 0
  C.SetLastError(0)
  local n = C.MultiByteToWideChar(codepage, flags, text, #text, nil, 0)
  if n == 0 then return Winfailure('MultiByteToWideChar') end
  local w = ffi.new('unsigned short[?]', n + 1)
  if C.MultiByteToWideChar(codepage, flags, text, #text, w, n) ~= n then return Winfailure('MultiByteToWideChar') end
  return w, n
end


local function SameWide(a, an, b, bn)
  if an ~= bn then return false end
  if an == 0 then return true end
  return ffi.string(a, an * 2) == ffi.string(b, bn * 2)
end

local function WideMultibyte(w, n, codepage, allow_lossy)
  if n == 0 then return '' end

  local strict = not allow_lossy
  local flags = 0
  local used_default
  local needs_roundtrip = false

  if codepage == 65001 or codepage == 54936 then
    -- UTF-8 / GB18030: lpUsedDefaultChar must be NULL. Both can use
    -- WC_ERR_INVALID_CHARS (0x80) for strict input validation.
    if strict then flags = 128 end
  elseif native.CodePageRequiresZeroFlags(codepage) then
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
  if size == 0 then return Winfailure('WideCharToMultiByte') end
  local out = ffi.new('char[?]', size)
  if used_default then used_default[0] = 0 end
  if C.WideCharToMultiByte(codepage, flags, w, n, out, size, nil, used_default) ~= size then
    return Winfailure('WideCharToMultiByte')
  end

  if strict and used_default and used_default[0] ~= 0 then
    return nil, 'text cannot be represented in Windows code page ' .. tostring(codepage)
  end

  if strict and needs_roundtrip then
    local back, back_n = MultibyteWide(ffi.string(out, size), codepage)
    if not back then return nil, back_n end
    if not SameWide(w, n, back, back_n) then
      return nil, 'text cannot be represented in Windows code page ' .. tostring(codepage)
    end
  end

  return ffi.string(out, size)
end
local function Acp() return tonumber(C.GetACP()) end

local function Oemcp() return tonumber(C.GetOEMCP()) end

local function CodepageToUtf8(text, codepage)
  local cp, err = CodepageNumber(codepage, Acp())
  if not cp then return nil, err end
  local w, n = MultibyteWide(text, cp)
  if not w then return nil, n end
  return Utf8(w, n)
end

local function Utf8ToCodepage(text, codepage, allow_lossy)
  local cp, err = CodepageNumber(codepage, Acp())
  if not cp then return nil, err end
  local w, n = MultibyteWide(text, 65001)
  if not w then return nil, n end
  return WideMultibyte(w, n, cp, allow_lossy == true)
end


local function HasAttr(attributes, flag)
  return bit.band(attributes, flag) ~= 0
end
local function MissingPathError(code)
  return code == 2 or code == 3
end
local function Attributes(path)
  local w, err, code = PathWide(path); if not w then return nil, err, code end
  C.SetLastError(0)
  local value = tonumber(C.GetFileAttributesW(w))
  if value == 4294967295 then
    local code = tonumber(C.GetLastError())
    if MissingPathError(code) then return false, nil, code end
    return Winerror('GetFileAttributesW', code, path)
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

local function FiletimeToUnix(value)
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
function M.CurrentDirGet()
  return native.Cwd()
end

function M.CurrentDirSet(path)
  local ok, err, code = native.Chdir(path)
  if not ok then return nil, err, code end
  return true
end

function M.PathAbsolute(path)
  local w, err, code = Wide(path); if not w then return nil, err, code end
  -- Namespace paths are already absolute and preserve literal components.
  -- Canonicalizing them can redirect atomic writes or recursive removal to
  -- a different sibling whose name lacks the final dots/spaces.
  if path:sub(1, 4) == '\\\\?\\' or path:sub(1, 4) == '\\\\.\\' then return path end
  local n = C.GetFullPathNameW(w, 0, nil, nil)
  if n == 0 then return Winfailure('GetFullPathNameW', nil, path) end
  while true do
    local b = ffi.new('unsigned short[?]', n)
    local len = C.GetFullPathNameW(w, n, b, nil)
    if len == 0 then return Winfailure('GetFullPathNameW', nil, path) end
    if len < n then return Utf8(b, len) end
    n = len + 1
  end
end

local function PathStatus(path)
  local valid, err, code = ValidatePath(path); if not valid then return nil, err, code end
  local info, msg, code = native.FsLstat(path)
  if errors.MissingPath(code) or code == 267 then return false end
  if not info then return nil, msg, code end
  return info
end

function M.PathExists(path)
  local info, err, code = PathStatus(path)
  if info == nil then return nil, err, code end
  return info ~= false
end

function M.FileExists(path)
  local info, err, code = PathStatus(path)
  if info == nil then return nil, err, code end
  if info == false then return false end
  if info.type == 'link' then
    local attr; attr, err, code = Attributes(path)
    if attr == nil then return nil, err, code end
    return attr ~= false and not HasAttr(attr, 16)
  end
  return info.type ~= 'directory'
end

function M.DirExists(path)
  local info, err, code = PathStatus(path)
  if info == nil then return nil, err, code end
  if info == false then return false end
  if info.type == 'link' then
    local attr; attr, err, code = Attributes(path)
    if attr == nil then return nil, err, code end
    return attr ~= false and HasAttr(attr, 16)
  end
  return info.type == 'directory'
end

function M.FileGetInfo(path)
  local w, err, code = PathWide(path); if not w then return nil, err, code end
  local data = ffi.new('uio_WIN32_FILE_ATTRIBUTE_DATA[1]')
  if C.GetFileAttributesExW(w, 0, data) == 0 then return Winfailure('GetFileAttributesExW', nil, path) end
  local info = data[0]
  local attr = tonumber(info.dwFileAttributes)
  local high, low = tonumber(info.nFileSizeHigh), tonumber(info.nFileSizeLow)
  local size = high * 4294967296 + low
  return {
    size = size,
    size_high = high,
    size_low = low,
    size_exact = size <= 9007199254740991,
    is_file = not HasAttr(attr, 16),
    is_dir = HasAttr(attr, 16),
    readonly = HasAttr(attr, 1),
    hidden = HasAttr(attr, 2),
    system = HasAttr(attr, 4),
    archive = HasAttr(attr, 32),
    temporary = HasAttr(attr, 256),
    reparse_point = HasAttr(attr, 1024),
    compressed = HasAttr(attr, 2048),
    offline = HasAttr(attr, 4096),
    not_content_indexed = HasAttr(attr, 8192),
    encrypted = HasAttr(attr, 16384),
    attributes = attr,
    creation_time = FiletimeToUnix(info.ftCreationTime),
    access_time = FiletimeToUnix(info.ftLastAccessTime),
    write_time = FiletimeToUnix(info.ftLastWriteTime)
  }
end

local function SetAttributeFlag(path, flag, enabled)
  if type(enabled) ~= 'boolean' then return nil, 'enabled must be boolean' end
  local attr, err, code = Attributes(path)
  if attr == false then return nil, 'path does not exist', code end
  if attr == nil then return nil, err, code end

  local new_attr = attr
  local present = HasAttr(attr, flag)
  if enabled and not present then
    if attr == 128 then new_attr = flag else new_attr = attr + flag end
  elseif not enabled and present then
    new_attr = attr - flag
    if new_attr == 0 then new_attr = 128 end
  else
    return true
  end

  local w, wide_err = PathWide(path); if not w then return nil, wide_err end
  if C.SetFileAttributesW(w, new_attr) == 0 then return Winfailure('SetFileAttributesW') end
  return true
end

function M.PathReadonlyAttrSet(path, enabled)
  return SetAttributeFlag(path, 1, enabled)
end

function M.PathHiddenAttrSet(path, enabled)
  return SetAttributeFlag(path, 2, enabled)
end

function M.PathArchiveAttrSet(path, enabled)
  return SetAttributeFlag(path, 32, enabled)
end


local function DirRemove(path)
  local w, err, code = Wide(path); if not w then return nil, err, code end
  local ok; ok, err, code = native.FsRmdir(path)
  if not ok then return nil, err, code end
  return true
end

local function DriveRoot(path)
  if #path == 3 and path:sub(2, 3) == ':\\' and path:sub(1, 1):match('%a') then return true end
  return #path == 7 and path:sub(1, 4) == '\\\\?\\' and path:sub(6, 7) == ':\\' and path:sub(5, 5):match('%a') ~= nil
end
local function UncRoot(path)
  local rest
  local prefix = path:sub(1, 4)
  if (prefix == '\\\\?\\' or prefix == '\\\\.\\') and path:sub(5, 8):upper() == 'UNC\\' then
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
local function NormalizedAbsolute(path)
  local absolute, err, code = M.PathAbsolute(path)
  if not absolute then return nil, err, code end
  absolute = absolute:gsub('/', '\\')
  if DriveRoot(absolute) then return absolute end
  absolute = absolute:gsub('\\+$', '')
  return absolute
end

-- Compare normalized Windows paths using Windows' Unicode ordinal
-- case-insensitive rules. Lua string.lower() only handles ASCII reliably.
local function PathIsSameOrChild(parent, candidate)
  local parent_w, parent_n = Wide(parent)
  if not parent_w then return nil, parent_n end
  local candidate_w, candidate_n = Wide(candidate)
  if not candidate_w then return nil, candidate_n end
  if candidate_n < parent_n then return false end

  C.SetLastError(0)
  local compared = C.CompareStringOrdinal(parent_w, parent_n, candidate_w, parent_n, 1)
  if compared == 0 then return Winfailure('CompareStringOrdinal') end
  if compared ~= 2 then return false end -- CSTR_EQUAL = 2
  if candidate_n == parent_n then return true end

  -- A drive root already ends in a separator (for example C:\).
  if parent_w[parent_n - 1] == 92 then return true end
  return candidate_w[parent_n] == 92
end
local function ParentPath(path)
  if DriveRoot(path) or UncRoot(path) then return nil end
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
local function TrimTrailingSeparators(path)
  local value = path:gsub('/', '\\')
  local last = #value
  while last > 1 and value:byte(last) == 92 do
    -- Retain the separator of an ordinary or extended drive root.
    if (last == 3 or last == 7) and DriveRoot(value:sub(1, last)) then break end
    last = last - 1
  end
  return last == #value and value or value:sub(1, last)
end

function M.PathBaseName(path)
  if type(path) ~= 'string' then return nil, 'path must be a string' end
  local value = TrimTrailingSeparators(path)
  if value == '' or value == '\\' or DriveRoot(value) or UncRoot(value) then return '' end
  local pos
  for i = #value, 1, -1 do
    if value:sub(i, i) == '\\' then
      pos = i; break
    end
  end
  return pos and value:sub(pos + 1) or value
end

function M.PathDirName(path)
  if type(path) ~= 'string' then return nil, 'path must be a string' end
  local value = TrimTrailingSeparators(path)
  if value == '' then return '.' end
  if value == '\\' or DriveRoot(value) or UncRoot(value) then return value end
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

function M.PathExtension(path)
  local name, err = M.PathBaseName(path)
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

function M.PathNameNoExt(path)
  local name, err = M.PathBaseName(path)
  if name == nil then return nil, err end
  local ext, ext_err = M.PathExtension(name)
  if ext == nil then return nil, ext_err end
  if ext == '' then return name end
  return name:sub(1, #name - #ext)
end

-- Join Windows path components without aggressively normalizing the whole path.
-- Absolute components are only accepted as the first component.
function M.PathJoin(...)
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

function M.DirCreate(path)
  local absolute, err, code = NormalizedAbsolute(path)
  if not absolute then return nil, err, code end
  local function Ensure(current)
    local info, msg, code = native.FsStat(current)
    if info then
      if info.type == 'directory' then return true end
      return nil, 'Путь занят объектом, который не является папкой: ' .. current
    end
    if not errors.MissingPath(code) then return nil, msg, code end
    local parent = ParentPath(current)
    if parent then
      local ok; ok, msg, code = Ensure(parent)
      if not ok then return nil, msg, code end
    end
    local ok; ok, msg, code = native.FsMkdir(current, 511)
    if ok then return true end
    if errors.AlreadyExists(code) then
      info = native.FsStat(current)
      if info and info.type == 'directory' then return true end
    end
    return nil, msg, code
  end
  return Ensure(absolute)
end

function M.DirList(path)
  local valid, err, code = ValidatePath(path); if not valid then return nil, err, code end
  local request; request, err, code = native.FsScandir(path)
  if not request then return nil, err, code end
  -- This request is private to the call; its sorted array can be returned
  -- directly without copying it into a second table.
  return request.items
end



local function GlobNameMatches(name, mask, wide_mask)
  local wn, err = Wide(name)
  if not wn then return nil, err end
  local wm = wide_mask
  if not wm then
    wm, err = Wide(mask)
    if not wm then return nil, err end
  end
  return shlwapi.PathMatchSpecW(wn, wm) ~= 0, nil, wm
end

local function NamespacePath(absolute)
  if absolute:sub(1,4) == '\\\\?\\' or absolute:sub(1,4) == '\\\\.\\' then return absolute end
  if absolute:sub(1,2) == '\\\\' then return '\\\\?\\UNC\\' .. absolute:sub(3) end
  return '\\\\?\\' .. absolute
end

-- Enumerated names are literal. Preserve ordinary result paths unless Win32
-- normalization would change the child name; resolve bare C: before joining.
local function EnumeratedChild(dir, name)
  if dir:match('^%a:$') then
    local absolute, err = M.PathAbsolute(dir)
    if not absolute then return nil, err end
    dir = absolute
  end
  local stem = (name:match('^[^.]+') or ''):upper()
  if name:find('[ .]$') or stem == 'CON' or stem == 'PRN'
    or stem == 'AUX' or stem == 'NUL' or stem:match('^COM[1-9]$')
    or stem:match('^LPT[1-9]$') then
    local absolute, err = M.PathAbsolute(dir)
    if not absolute then return nil, err end
    dir = NamespacePath(absolute)
  end
  return M.PathJoin(dir, name)
end

local function GlobFilesInDir(dir, mask, result, dirs)
  local names, err, code = M.DirList(dir)
  if not names then return nil, err, code end
  local wide_mask
  for _, name in ipairs(names) do
    local full; full, err = EnumeratedChild(dir, name)
    if not full then return nil, err, code end
    local info; info, err, code = M.FileGetInfo(full)
    if not info then return nil, err, code end
    if info.is_file then
      local matched; matched, err, wide_mask = GlobNameMatches(name, mask, wide_mask)
      if matched == nil then return nil, err, code end
      if matched then result[#result + 1] = full end
    elseif dirs and info.is_dir and not info.reparse_point then
      dirs[#dirs + 1] = full
    end
  end
  return true
end

-- Return matching files as paths. Wildcards are supported in the final component.
-- With recursive=true, matching files in subdirectories are included.
function M.FilesFind(pattern, recursive)
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
  local isdir, err, code = M.DirExists(dir)
  if isdir == nil then return nil, err, code end
  if not isdir then return {} end
  local result = {}
  local function Scan(current)
    local dirs = recursive and {} or nil
    local ok, scan_err, scan_code = GlobFilesInDir(current, mask, result, dirs)
    if not ok then return nil, scan_err, scan_code end
    if recursive then
      for _, child in ipairs(dirs) do
        ok, scan_err, scan_code = Scan(child)
        if not ok then return nil, scan_err, scan_code end
      end
    end
    return true
  end
  local ok, scan_err, scan_code = Scan(dir)
  if not ok then return nil, scan_err, scan_code end
  if implicit_current then
    for i = 1, #result do
      if result[i]:sub(1, 2) == '.\\' then result[i] = result[i]:sub(3) end
    end
  end
  table.sort(result)
  return result
end

local function ClearReadonlyForDelete(w, attr, force)
  if not force or HasAttr(attr, 16) or not HasAttr(attr, 1) then return false end
  if C.SetFileAttributesW(w, attr - 1) == 0 then return Winfailure('SetFileAttributesW') end
  return true
end

local function PathRemove(path, force)
  if force ~= nil and type(force) ~= 'boolean' then return nil, 'force must be boolean' end
  local w, err, code = PathWide(path); if not w then return nil, err, code end
  local attr, attr_err, attr_code = Attributes(path)
  if attr == false then return Winerror('удаление', attr_code, path) end
  if attr == nil then return nil, attr_err, attr_code end
  if HasAttr(attr, 1) and not HasAttr(attr, 16) and not force then return nil, 'remove failed: file is readonly' end
  local cleared, clear_err, clear_code = ClearReadonlyForDelete(w, attr, force == true)
  if cleared == nil then return nil, clear_err, clear_code end
  local ok
  local delete_err, delete_code
  if HasAttr(attr, 16) then ok, delete_err, delete_code = native.FsRmdir(path) else ok, delete_err, delete_code = native.FsUnlink(path) end
  if not ok then
    if cleared and C.SetFileAttributesW(w, attr) == 0 then
      local _, restore_err = Winfailure('восстановление атрибутов', nil, path)
      return nil, delete_err .. '; ' .. restore_err, delete_code
    end
    return nil, delete_err, delete_code
  end
  return true
end

local function EnsureParentDirectory(path)
  local absolute, err, code = M.PathAbsolute(path)
  if not absolute then return nil, err, code end
  absolute = absolute:gsub('/', '\\')
  local parent = ParentPath(absolute)
  if not parent then return true end
  return M.DirCreate(parent)
end

function M.FileCopy(from, to, overwrite)
  -- Validate the source before creating any destination directories.
  local source_info, source_err, source_code = M.FileGetInfo(from)
  if not source_info then return nil, source_err, source_code end
  if not source_info.is_file then return nil, 'copy source is not a file: ' .. from, 267 end
  local a, err = Wide(from); if not a then return nil, err end
  local ok, dir_err, dir_code = EnsureParentDirectory(to)
  if not ok then return nil, dir_err, dir_code end
  local b; b, err = Wide(to); if not b then return nil, err end
  local copied, copy_err, copy_code = native.FsCopyfile(from, to, { excl = not overwrite })
  if not copied then return nil, copy_err, copy_code end
  return true
end

local function PathMove(from, to, overwrite)
  local source_info, source_err, source_code = M.FileGetInfo(from)
  if not source_info then return nil, source_err, source_code end
  local a, err = PathWide(from); if not a then return nil, err end
  local ok, dir_err, dir_code = EnsureParentDirectory(to)
  if not ok then return nil, dir_err, dir_code end
  local b; b, err = PathWide(to); if not b then return nil, err end

  -- Do not use COPY_ALLOWED: it can report success without deleting the source.
  -- No-replace remains one atomic rename, without a stat-then-rename race.
  if C.MoveFileExW(a, b, overwrite and 1 or 0) ~= 0 then return true end
  local move_code = tonumber(C.GetLastError())
  if move_code ~= 17 then return Winerror('move "' .. from .. '" -> "' .. to .. '"', move_code) end
  if source_info.is_dir then return nil, 'cross-volume directory moves are not supported', 17 end

  if C.CopyFileW(a, b, overwrite and 0 or 1) == 0 then
    return Winfailure('cross-volume copy "' .. from .. '" -> "' .. to .. '"')
  end
  if C.DeleteFileW(a) == 0 then
    local code = tonumber(C.GetLastError())
    return Winerror('удаление источника ' .. from .. '; копия уже записана', code, to)
  end
  return true
end

-- Recursively enumerate all children under path. The root itself is not
-- included. Directory reparse points are returned but never traversed.
function M.TreeWalk(path)
  local isdir, err, code = M.DirExists(path)
  if isdir == nil then return nil, err, code end
  if not isdir then return nil, 'walk failed: path is not a directory', 267 end

  local result = {}
  local function Scan(current)
    -- The backend sorts once and retains regular-file metadata already
    -- returned by FindFirstFileW/FindNextFileW.
    local request, list_err, list_code = native.FsScandir(current, true)
    if not request then return nil, list_err, list_code end
    for _, name in ipairs(request.items) do
      local full, join_err = EnumeratedChild(current, name)
      if not full then return nil, join_err end
      local info = request.metadata[name]
      -- Enumeration reports zero for directory sizes on some filesystems,
      -- whereas GetFileAttributesExW can report a nonzero value. Keep stat
      -- for directories and reparse points to preserve their existing data.
      if info.is_dir or info.reparse_point then
        local stat_err, stat_code
        info, stat_err, stat_code = M.FileGetInfo(full)
        if not info then return nil, stat_err, stat_code end
      end
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
        local ok, scan_err, scan_code = Scan(full)
        if not ok then return nil, scan_err, scan_code end
      end
    end
    return true
  end

  local ok, scan_err, scan_code = Scan(path)
  if not ok then return nil, scan_err, scan_code end
  return result
end

-- Recursively copy a directory tree. Destination directories are created
-- automatically. Reparse points are refused because this library does not
-- create equivalent links/junctions and must not silently follow them.
local function CopyTree(from, to, overwrite, recursive)
  if overwrite ~= nil and type(overwrite) ~= 'boolean' then return nil, 'overwrite must be boolean' end
  local source_info, err, code = M.FileGetInfo(from)
  if not source_info then return nil, err, code end
  if not source_info.is_dir then return nil, 'copyTree source is not a directory', 267 end
  if source_info.reparse_point then return nil, 'copyTree source must not be a reparse point' end

  local source_abs; source_abs, err, code = NormalizedAbsolute(from)
  if not source_abs then return nil, err, code end
  local destination_abs; destination_abs, err, code = NormalizedAbsolute(to)
  if not destination_abs then return nil, err, code end
  -- Enumerated child names are literal, even when the caller used an ordinary
  -- root path. Preserve their spelling throughout recursion and metadata calls.
  from, to = NamespacePath(source_abs), NamespacePath(destination_abs)
  -- Resolve aliases (extended paths, short names and junction ancestors),
  -- including the existing ancestor of a not-yet-created destination.
  local function Resolved(path)
    local suffix = ''
    while path do
      local real, real_err, real_code = native.FsRealpath(path)
      if real then return (real:gsub('\\+$', '')) .. suffix end
      if not errors.MissingPath(real_code) then return nil, real_err, real_code end
      local parent = ParentPath(path)
      if not parent then return nil, real_err, real_code end
      suffix = '\\' .. path:sub(#parent + 1):gsub('^\\+', '') .. suffix
      path = parent
    end
  end
  source_abs, err, code = Resolved(source_abs)
  if not source_abs then return nil, err, code end
  destination_abs, err, code = Resolved(destination_abs)
  if not destination_abs then return nil, err, code end
  local same_or_child, compare_err, compare_code = PathIsSameOrChild(source_abs, destination_abs)
  if same_or_child == nil then return nil, compare_err, compare_code end
  if same_or_child then
    return nil, 'copyTree destination must not be the source directory or a child of it'
  end

  local ok, dir_err, dir_code = M.DirCreate(to)
  if not ok then return nil, dir_err, dir_code end

  local function CopyDir(source, destination)
    local attr, attr_err, attr_code = Attributes(destination)
    if attr == nil then return nil, attr_err, attr_code end
    if attr ~= false and HasAttr(attr, 1024) then
      return nil, 'copyTree destination must not be a reparse point: ' .. destination
    end
    local names, list_err, list_code
    if recursive == false then
      names, list_err, list_code = M.DirListFiles(source)
    else
      names, list_err, list_code = M.DirList(source)
    end
    if not names then return nil, list_err, list_code end
    for _, name in ipairs(names) do
      local source_child, join_err = M.PathJoin(source, name)
      if not source_child then return nil, join_err end
      local destination_child; destination_child, join_err = M.PathJoin(destination, name)
      if not destination_child then return nil, join_err end
      local destination_attr, destination_err, attr_code = Attributes(destination_child)
      if destination_attr == nil then return nil, destination_err, attr_code end
      if destination_attr ~= false and HasAttr(destination_attr, 1024) then
        return nil, 'copyTree destination must not be a reparse point: ' .. destination_child
      end
      local info, stat_err, stat_code = M.FileGetInfo(source_child)
      if not info then return nil, stat_err, stat_code end
      if info.reparse_point then
        return nil, 'copyTree does not support reparse point: ' .. source_child
      elseif info.is_dir then
        local made, made_err, made_code = M.DirCreate(destination_child)
        if not made then return nil, made_err, made_code end
        local copied, copy_err, copy_code = CopyDir(source_child, destination_child)
        if not copied then return nil, copy_err, copy_code end
      else
        local copied, copy_err, copy_code = M.FileCopy(source_child, destination_child, overwrite)
        if not copied then return nil, copy_err, copy_code end
      end
    end
    return true
  end

  local copied, copy_err, copy_code = CopyDir(from, to)
  if not copied then
    return errors.Context('Копирование не завершено, в папке назначения могли остаться созданные объекты [' .. to .. ']', copy_err, copy_code)
  end
  return true
end

function M.TreeCopy(from, to, overwrite)
  return CopyTree(from, to, overwrite, true)
end

-- Recursively remove a file or directory tree. Directory reparse points are
-- removed as links and are never traversed. Drive/UNC roots are refused.
local function TreeRemove(path, force)
  if force ~= nil and type(force) ~= 'boolean' then return nil, 'force must be boolean' end
  local absolute, err, code = NormalizedAbsolute(path)
  if not absolute then return nil, err, code end
  if DriveRoot(absolute) or UncRoot(absolute) then
    return nil, 'removeAll refuses to remove a drive or UNC root'
  end
  absolute = NamespacePath(absolute)
  local attr; attr, err, code = Attributes(absolute)
  if attr == false then return Winerror('удаление дерева', code, absolute) end
  if attr == nil then return nil, err, code end
  if not HasAttr(attr, 16) or HasAttr(attr, 1024) then return PathRemove(absolute, force) end
  local items; items, err, code = M.DirList(absolute)
  if not items then return nil, err, code end
  local removed = false
  local function Incomplete(message, status)
    if removed then return errors.Context('Удаление выполнено частично [' .. absolute .. ']', message, status) end
    return nil, message, status
  end
  for _, name in ipairs(items) do
    local child, join_err = M.PathJoin(absolute, name)
    if not child then return Incomplete(join_err) end
    local child_attr; child_attr, err, code = Attributes(child)
    if child_attr == nil then return Incomplete(err, code) end
    local ok
    if child_attr ~= false and HasAttr(child_attr, 16) and not HasAttr(child_attr, 1024) then
      ok, err, code = TreeRemove(child, force)
    else
      ok, err, code = PathRemove(child, force)
    end
    if not ok then return Incomplete(err, code) end
    removed = true
  end
  local ok; ok, err, code = DirRemove(absolute)
  if not ok then return Incomplete(err, code) end
  return true
end

local function ReadRawFile(path, limit)
  local valid, err, code = ValidatePath(path); if not valid then return nil, err, code end
  local fd; fd, err, code = native.FsOpen(path, 'r', 438)
  if not fd then return nil, err, code end
  local chunks, offset = {}, 0
  while not limit or offset < limit do
    local data; data, err, code = native.FsRead(fd, math.min(65536, limit and limit - offset or 65536))
    if not data or #data == 0 then break end
    chunks[#chunks + 1] = data
    offset = offset + #data
  end
  local closed, close_err, close_code = native.FsClose(fd)
  if err then return errors.Context('Чтение файла [' .. path .. ']',err,code) end
  if not closed then return errors.Context('Закрытие файла [' .. path .. ']',close_err,close_code) end
  return table.concat(chunks)
end

local function EncodingInfo(encoding)
  if encoding == nil then return { kind = 'utf8', name = 'UTF-8' } end
  if type(encoding) == 'number' then
    if encoding == 65001 then return { kind = 'utf8', name = 'UTF-8' } end
    local cp, err = CodepageNumber(encoding, Acp())
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
    return { kind = 'codepage', codepage = Acp(), name = 'ANSI' }
  end
  if compact == 'OEM' or compact == 'OEMCP' then
    return { kind = 'codepage', codepage = Oemcp(), name = 'OEM' }
  end

  local cp_text = compact:match('^CP(%d+)$') or compact:match('^WINDOWS(%d+)$')
  if cp_text then
    local cp_number = tonumber(cp_text)
    if cp_number == 65001 then return { kind = 'utf8', name = 'UTF-8' } end
    local cp, err = CodepageNumber(cp_number, Acp())
    if not cp then return nil, err end
    return { kind = 'codepage', codepage = cp, name = 'CP' .. tostring(cp) }
  end
  return nil, 'unsupported encoding: ' .. encoding
end

local UTF8_BOM = '\239\187\191'
local UTF16LE_BOM = '\255\254'
local UTF16BE_BOM = '\254\255'

local function ValidateUtf8Text(text)
  if type(text) ~= 'string' then return nil, 'expected a byte string' end
  if #text > 2147483647 then return nil, 'string is too large' end
  if text == '' then return true end
  -- The strict size query validates UTF-8 already. No UTF-16 output is needed.
  C.SetLastError(0)
  if C.MultiByteToWideChar(65001, 8, text, #text, nil, 0) == 0 then
    local _, err = Winfailure('MultiByteToWideChar')
    return nil, err
  end
  return true
end

local function DecodeUtf16(text, big_endian)
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
  return Utf8(w, count)
end

local function DecodeText(content, encoding)
  local info, err = EncodingInfo(encoding)
  if not info then return nil, err end
  if info.kind == 'binary' then return content end
  if info.kind == 'utf8bom' or info.kind == 'utf8' then
    if content:sub(1, 3) == UTF8_BOM then content = content:sub(4) end
    local ok, utf8_err = ValidateUtf8Text(content)
    if not ok then return nil, utf8_err end
    return content
  end
  if info.kind == 'utf16le' then
    if content:sub(1, 2) == UTF16BE_BOM then return nil, 'encoding mismatch: file has UTF-16BE BOM' end
    if content:sub(1, 2) == UTF16LE_BOM then content = content:sub(3) end
    return DecodeUtf16(content, false)
  end
  if info.kind == 'utf16be' then
    if content:sub(1, 2) == UTF16LE_BOM then return nil, 'encoding mismatch: file has UTF-16LE BOM' end
    if content:sub(1, 2) == UTF16BE_BOM then content = content:sub(3) end
    return DecodeUtf16(content, true)
  end
  return CodepageToUtf8(content, info.codepage)
end

local function EncodeUtf16(text, big_endian, include_bom)
  local w, n = MultibyteWide(text, 65001)
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

local function EncodeText(content, encoding, include_bom, allow_lossy)
  if type(content) ~= 'string' and type(content) ~= 'number' then return nil, 'content must be a string or number' end
  content = tostring(content)
  local info, err = EncodingInfo(encoding)
  if not info then return nil, err end
  if info.kind == 'binary' then return content end
  if info.kind == 'utf8bom' or info.kind == 'utf8' then
    local ok, utf8_err = ValidateUtf8Text(content)
    if not ok then return nil, utf8_err end
    if info.kind == 'utf8bom' and include_bom then return UTF8_BOM .. content end
    return content
  end
  if info.kind == 'utf16le' then return EncodeUtf16(content, false, include_bom) end
  if info.kind == 'utf16be' then return EncodeUtf16(content, true, include_bom) end
  return Utf8ToCodepage(content, info.codepage, allow_lossy == true)
end

local function ReadFilePrefix(path, count)
  return ReadRawFile(path, count)
end

local function WriteRawFile(path, content, mode)
  local valid, err, code = ValidatePath(path); if not valid then return nil, err, code end
  local fd; fd, err, code = native.FsOpen(path, mode == 'ab' and 'a' or 'w', 438)
  if not fd then return nil, err, code end
  local offset = 0
  while offset < #content do
    local n; n, err, code = native.FsWrite(fd, content:sub(offset + 1), -1)
    if not n then break end
    if n == 0 then err = 'Запись не продвинулась'; break end
    offset = offset + n
  end
  if not err then local ok; ok, err, code = native.FsFsync(fd) end
  local closed, close_err, close_code = native.FsClose(fd)
  if not err and not closed then err, code = close_err, close_code end
  if err then
    return errors.Context(('Файл [%s] мог измениться; записано байт: %d'):format(path, offset), err, code)
  end
  return true
end

function M.FileRead(path, encoding)
  local content, err, code = ReadRawFile(path)
  if content == nil then return nil, err, code end
  local decoded, decode_err = DecodeText(content, encoding)
  if decoded == nil then return nil, decode_err end
  return decoded
end

function M.FileWrite(path, content, encoding, allow_lossy)
  if content == nil then content = "" end
  -- Validate and encode before opening: encoding errors must not truncate data.
  local data, encode_err = EncodeText(content, encoding, true, allow_lossy)
  if data == nil then return nil, encode_err end
  local ok, err, code = EnsureParentDirectory(path)
  if not ok then return nil, err, code end
  -- Direct overwrite. I/O failures may leave an empty or partially written file.
  return WriteRawFile(path, data, 'wb')
end

local function DetectedBom(prefix)
  if prefix:sub(1, 3) == UTF8_BOM then return 'UTF-8-BOM' end
  if prefix:sub(1, 2) == UTF16LE_BOM then return 'UTF-16LE' end
  if prefix:sub(1, 2) == UTF16BE_BOM then return 'UTF-16BE' end
  return nil
end

local function BomMatchesEncoding(bom, info)
  if bom == nil or info.kind == 'binary' then return true end
  if bom == 'UTF-8-BOM' then return info.kind == 'utf8' or info.kind == 'utf8bom' end
  if bom == 'UTF-16LE' then return info.kind == 'utf16le' end
  if bom == 'UTF-16BE' then return info.kind == 'utf16be' end
  return false
end

function M.FileAppend(path, content, encoding, allow_lossy)
  local info, info_err = EncodingInfo(encoding)
  if not info then return nil, info_err end

  local exists, exists_err, exists_code = M.PathExists(path)
  if exists == nil then return nil, exists_err, exists_code end

  local include_bom = false
  if not exists then
    include_bom = info.kind == 'utf8bom' or info.kind == 'utf16le' or info.kind == 'utf16be'
  else
    local stat, stat_err, stat_code = M.FileGetInfo(path)
    if not stat then return nil, stat_err, stat_code end
    if stat.size == 0 then
      include_bom = info.kind == 'utf8bom' or info.kind == 'utf16le' or info.kind == 'utf16be'
    -- Explicit legacy code pages interpret all bytes as data, including BOM-like prefixes.
    elseif info.kind ~= 'binary' and info.kind ~= 'codepage' then
      local prefix, read_err, read_code = ReadFilePrefix(path, 3)
      if prefix == nil then return nil, read_err, read_code end
      local bom = DetectedBom(prefix)
      if info.kind == 'utf8bom' and bom == nil then
        local existing, read_err, read_code = M.FileRead(path, encoding)
        if existing == nil then return nil, read_err, read_code end
        if type(content) ~= 'string' and type(content) ~= 'number' then
          return nil, 'content must be a string or number'
        end
        return M.FileWrite(path, existing .. tostring(content), encoding, allow_lossy)
      end
      if bom and not BomMatchesEncoding(bom, info) then
        return nil, 'encoding mismatch: existing file has ' .. bom .. ' BOM'
      end
    end
  end

  local encoded, err = EncodeText(content, encoding, include_bom, allow_lossy)
  if encoded == nil then return nil, err end
  local ok, parent_err, parent_code = EnsureParentDirectory(path)
  if not ok then return nil, parent_err, parent_code end
  return WriteRawFile(path, encoded, 'ab')
end

-- Read text for an in-place line edit and remember whether the existing file
-- physically has the BOM appropriate for the selected encoding. Line edits use
-- this bit when rewriting so changing a line never adds or removes a BOM.
local function ReadTextForLineEdit(path, encoding)
  local raw, err, code = ReadRawFile(path)
  if raw == nil then return nil, err, code end
  local info, info_err = EncodingInfo(encoding)
  if not info then return nil, info_err end

  local had_bom = false
  if info.kind == 'utf8' or info.kind == 'utf8bom' then
    had_bom = raw:sub(1, 3) == UTF8_BOM
  elseif info.kind == 'utf16le' then
    had_bom = raw:sub(1, 2) == UTF16LE_BOM
  elseif info.kind == 'utf16be' then
    had_bom = raw:sub(1, 2) == UTF16BE_BOM
  end

  local decoded, decode_err = DecodeText(raw, encoding)
  if decoded == nil then return nil, decode_err end
  return decoded, nil, nil, had_bom
end

local function RewriteTextPreservingBom(path, content, encoding, had_bom, allow_lossy)
  local info, info_err = EncodingInfo(encoding)
  if not info then return nil, info_err end
  local output_encoding = encoding
  if had_bom and info.kind == 'utf8' then output_encoding = 'UTF-8-BOM' end
  local data, encode_err = EncodeText(content, output_encoding, had_bom, allow_lossy)
  if data == nil then return nil, encode_err end
  return WriteRawFile(path, data, 'wb')
end

-- Text line helpers. These operate on decoded UTF-8 Lua strings and rewrite the
-- complete file for replace/insert operations. Existing line separators are
-- preserved for untouched lines. Line numbers are 1-based.
-- Shared scanner: return text, separator and the next byte position.
-- Call only while pos <= len. No per-line tables are allocated here.
local function NextTextLine(text, pos, len)
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
  return value, separator, pos
end

local function ParseTextLines(text)
  local lines = {}
  local pos, len = 1, #text
  while pos <= len do
    local value, separator
    value, separator, pos = NextTextLine(text, pos, len)
    lines[#lines + 1] = { text = value, sep = separator }
  end
  return lines
end

local function PreferredNewline(lines)
  for i = 1, #lines do
    if lines[i].sep ~= '' then return lines[i].sep end
  end
  return '\r\n'
end

local function BuildTextLines(lines)
  local out = {}
  for i = 1, #lines do
    out[#out + 1] = lines[i].text
    local separator = lines[i].sep
    -- An empty final record needs a terminator to remain a logical line.
    if i == #lines and lines[i].text == '' and separator == '' then
      separator = PreferredNewline(lines)
    end
    out[#out + 1] = separator
  end
  return table.concat(out)
end

local function ValidateLineNumber(line_number)
  if type(line_number) ~= 'number' or line_number ~= math.floor(line_number) or line_number < 1 then
    return nil, 'line number must be a positive integer'
  end
  return true
end

local function ValidateLineText(text)
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
-- Empty file -> {}. Line numbering for FileReplaceLine/FileInsertLine is 1-based.
function M.FileReadLines(path, encoding)
  local text, err, code = M.FileRead(path, encoding)
  if text == nil then return nil, err, code end

  local lines = {}
  local pos, len, count = 1, #text, 0
  while pos <= len do
    local value, separator
    value, separator, pos = NextTextLine(text, pos, len)
    count = count + 1
    lines[count] = value
  end
  return lines
end
function M.FileLineCount(path, encoding)
  local text, err, code = M.FileRead(path, encoding)
  if text == nil then return nil, err, code end
  local pos, len, count = 1, #text, 0
  while pos <= len do
    count = count + 1
    while pos <= len do
      local byte = text:byte(pos)
      if byte == 10 or byte == 13 then break end
      pos = pos + 1
    end
    if pos <= len then
      pos = pos + ((text:byte(pos) == 13 and text:byte(pos + 1) == 10) and 2 or 1)
    end
  end
  return count
end

-- Replace an existing line. The number of lines does not change.
function M.FileReplaceLine(path, line_number, text, encoding, allow_lossy)
  local ok, number_err = ValidateLineNumber(line_number)
  if not ok then return nil, number_err end
  local value, text_err = ValidateLineText(text)
  if value == nil then return nil, text_err end

  local content, err, code, had_bom = ReadTextForLineEdit(path, encoding)
  if content == nil then return nil, err, code end
  local records = ParseTextLines(content)
  if line_number > #records then
    return nil, 'line ' .. tostring(line_number) .. ' does not exist'
  end

  records[line_number].text = value
  return RewriteTextPreservingBom(path, BuildTextLines(records), encoding, had_bom, allow_lossy)
end

-- Insert a new line BEFORE line_number and shift that line and all following
-- lines down by one. line_number may also be #lines + 1 to append a line.
function M.FileInsertLine(path, line_number, text, encoding, allow_lossy)
  local ok, number_err = ValidateLineNumber(line_number)
  if not ok then return nil, number_err end
  local value, text_err = ValidateLineText(text)
  if value == nil then return nil, text_err end

  local content, err, code, had_bom = ReadTextForLineEdit(path, encoding)
  if content == nil then return nil, err, code end
  local records = ParseTextLines(content)
  local count = #records

  if line_number > count + 1 then
    return nil, 'line ' .. tostring(line_number) .. ' is beyond insertion position ' .. tostring(count + 1)
  end

  if count == 0 then
    records[1] = { text = value, sep = '' }
  elseif line_number <= count then
    local newline = PreferredNewline(records)
    table.insert(records, line_number, { text = value, sep = newline })
  else
    local newline = PreferredNewline(records)
    local had_final_newline = records[count].sep ~= ''
    if records[count].sep == '' then records[count].sep = newline end
    records[#records + 1] = { text = value, sep = had_final_newline and newline or '' }
  end

  return RewriteTextPreservingBom(path, BuildTextLines(records), encoding, had_bom, allow_lossy)
end

-- Append one logical line to the end of a text file. If the file does not
-- exist it is created. The appended line itself is left without a trailing
-- newline unless the existing file already ended with one, or the new line
-- is empty (an empty final line always needs a terminator).
function M.FileAppendLine(path, text, encoding, allow_lossy)
  local value, text_err = ValidateLineText(text)
  if value == nil then return nil, text_err end

  local exists, exists_err, exists_code = M.PathExists(path)
  if exists == nil then return nil, exists_err, exists_code end
  if not exists then return M.FileWrite(path, value == '' and '\r\n' or value, encoding, allow_lossy) end

  local content, err, code, had_bom = ReadTextForLineEdit(path, encoding)
  if content == nil then return nil, err, code end
  if content == '' then return RewriteTextPreservingBom(path, value == '' and '\r\n' or value, encoding, had_bom, allow_lossy) end

  local records = ParseTextLines(content)
  local count = #records
  local newline = PreferredNewline(records)
  local had_final_newline = records[count].sep ~= ''
  if records[count].sep == '' then records[count].sep = newline end
  records[#records + 1] = { text = value, sep = had_final_newline and newline or '' }

  return RewriteTextPreservingBom(path, BuildTextLines(records), encoding, had_bom, allow_lossy)
end

function M.TempDirCreate()
  local dir, err, code = native.OsTmpDir()
  if not dir then return nil, err, code end
  return native.FsMkdtemp(M.PathJoin(dir, 'ljuXXXXXX'))
end

function M.TempFileReserve()
  local dir, err, code = native.OsTmpDir()
  if not dir then return nil, err, code end
  local fd, name; fd, name, code = native.FsMkstemp(M.PathJoin(dir, 'ljuXXXXXX'))
  if not fd then return nil, name, code end
  local ok; ok, err, code = native.FsClose(fd)
  if not ok then native.FsUnlink(name); return nil, err, code end
  return name
end

M.FileSize = function(path)
  local info, err, code = M.FileGetInfo(path)
  if not info then return nil, err, code end
  return info.size
end
M.PathType = function(path)
  local attr, err, code = Attributes(path)
  if attr == false then return nil end
  if attr == nil then return nil, err, code end
  return HasAttr(attr, 16) and 'directory' or 'file'
end


-- Directory locations and disk information belong to the file API.
local kernel32 = ffi.C
local shell32 = ffi.load('shell32')
local ole32 = ffi.load('ole32')
local function Utf8ToWide(text) return Wide(text) end
local function WideToUtf8(value, count) return Utf8(value, count or Wlen(value)) end
local function WinError(prefix)
  local _, err = Winfailure(prefix)
  return err
end
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

local function MakeGuid(
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
            "LJ_FILES_GUID[1]"
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
    desktop = MakeGuid(
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

    documents = MakeGuid(
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

    downloads = MakeGuid(
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

    profile = MakeGuid(
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

    appdata = MakeGuid(
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

    localappdata = MakeGuid(
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

    programdata = MakeGuid(
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

    programfiles = MakeGuid(
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

    programfilesx86 = MakeGuid(
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
function M.WindowsDirGet()
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
            WinError(
                "GetWindowsDirectoryW failed"
            )
    end

    return WideToUtf8(
        pathBuf,
        tonumber(length)
    )
end

-- ============================================================
-- System32 directory
-- ============================================================

function M.SystemDirGet()
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
            WinError(
                "GetSystemDirectoryW failed"
            )
    end

    return WideToUtf8(
        pathBuf,
        tonumber(length)
    )
end

-- ============================================================
-- Temporary directory
-- ============================================================

function M.KnownFolderGet(name)
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
        WideToUtf8(
            allocatedPtr
        )

    ole32.CoTaskMemFree(
        allocatedPtr
    )

    return path
end

local function GetDriveInfo(rootPath)
    local rootWide =
        Utf8ToWide(
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
            WideToUtf8(
                volumeBuf
            )

        driveInfo.fileSystem =
            WideToUtf8(
                fsBuf
            )

        driveInfo.serial =
            tonumber(
                serialBuf[0]
            )
    end

    return driveInfo
end


function M.DrivesGet()
    local mask =
        tonumber(
            kernel32.GetLogicalDrives()
        )

    if mask == 0 then
        return nil,
            WinError(
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
                GetDriveInfo(
                    rootPath
                )

            result[#result + 1] =
                driveInfo
        end
    end

    return result
end

function M.DriveGet(path)
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

    return GetDriveInfo(
        letter:upper()
        .. ":\\"
    )
end

-- ============================================================
function M.TempDirGet()
  return native.OsTmpDir()
end

-- FileSystem-compatible extensions. Existing fs 5.0 entry points retain their semantics.
ffi.cdef[[
int __stdcall GetFileSizeEx(void *, int64_t *);
int __stdcall SetFileTime(void *, const uio_FILETIME *, const uio_FILETIME *, const uio_FILETIME *);
int __stdcall FindStringOrdinal(unsigned long,const unsigned short *,int,const unsigned short *,int,int);
typedef unsigned long (__stdcall *fs_COPY_PROGRESS)(int64_t,int64_t,int64_t,int64_t,unsigned long,unsigned long,void *,void *,void *);
int __stdcall CopyFileExW(const unsigned short *,const unsigned short *,fs_COPY_PROGRESS,void *,int *,unsigned long);
typedef struct { uintptr_t internal, internal_high; unsigned long offset, offset_high; void *event; } fs_OVERLAPPED;
void *__stdcall CreateEventW(void *,int,int,const unsigned short *);
int __stdcall ResetEvent(void *);
unsigned long __stdcall WaitForSingleObject(void *,unsigned long);
int __stdcall ReadDirectoryChangesW(void *,void *,unsigned long,int,unsigned long,unsigned long *,fs_OVERLAPPED *,void *);
int __stdcall GetOverlappedResult(void *,fs_OVERLAPPED *,unsigned long *,int);
int __stdcall CancelIoEx(void *,fs_OVERLAPPED *);
]]
local INVALID_HANDLE = ffi.cast('void *', -1)
local function Integer(n, lo, hi)
  return type(n) == 'number' and n == math.floor(n) and n >= lo and n <= hi
end
local function OpenHandle(path, access, sharing, disposition, flags)
  local w,e,c = PathWide(path); if not w then return nil,e,c end
  local h=C.CreateFileW(w,access,sharing,nil,disposition,flags or 128,nil)
  if h == INVALID_HANDLE then return Winfailure('CreateFileW',nil,path) end
  return h
end
local function Managed(h)
  return ffi.gc(h, function(v) C.CloseHandle(v) end)
end
local function CloseHandle(obj)
  if obj.handle then
    local h=obj.handle; obj.handle=nil; ffi.gc(h,nil)
    if C.CloseHandle(h)==0 then return Winfailure('CloseHandle') end
  end
  return true
end
local function SeekHandle(h,offset)
  if C.SetFilePointerEx(h,offset,nil,0)==0 then return Winfailure('SetFilePointerEx') end
  return true
end
local function ReadHandle(h,n)
  if n==0 then return '' end
  local b=ffi.new('char[?]',n); local got=ffi.new('unsigned long[1]')
  if C.ReadFile(h,b,n,got,nil)==0 then return Winfailure('ReadFile') end
  return ffi.string(b,got[0])
end
local function WriteHandle(h,s)
  local done=0; local out=ffi.new('unsigned long[1]')
  while done<#s do
    if C.WriteFile(h,ffi.cast('const char *',s)+done,math.min(#s-done,1048576),out,nil)==0 then return Winfailure('WriteFile') end
    if out[0]==0 then return nil,'write made no progress' end
    done=done+tonumber(out[0])
  end
  return true
end
function M.FileReadBytes(path,length,offset)
  offset=offset or 0
  if not Integer(length,0,2147483647) or not Integer(offset,0,9007199254740991) then return nil,'invalid length or offset' end
  local h,e,c=OpenHandle(path,0x80000000,7,3); if not h then return nil,e,c end
  local ok; ok,e,c=SeekHandle(h,offset)
  local data; if ok then data,e,c=ReadHandle(h,length) end
  local closed=C.CloseHandle(h)
  if data==nil then return errors.Context('Чтение файла ['..path..']',e,c) end
  if closed==0 then return Winfailure('CloseHandle',nil,path) end
  return data
end
function M.FileWriteBytes(path,bytes)
  if type(bytes)~='string' then return nil,'bytes must be a string' end
  return M.FileWrite(path,bytes,'BINARY')
end
function M.FileAppendBytes(path,bytes)
  if type(bytes)~='string' then return nil,'bytes must be a string' end
  return M.FileAppend(path,bytes,'BINARY')
end
function M.FileWriteAt(path,bytes,offset,allow_extend)
  offset=offset or 0
  if type(bytes)~='string' or not Integer(offset,0,9007199254740991-#bytes) then return nil,'invalid bytes or offset' end
  if allow_extend~=nil and type(allow_extend)~='boolean' then return nil,'allow_extend must be boolean' end
  local h,e,c=OpenHandle(path,0x40000000,1,3); if not h then return nil,e,c end
  local size=ffi.new('int64_t[1]'); local ok
  if C.GetFileSizeEx(h,size)==0 then ok,e,c=Winfailure('GetFileSizeEx',nil,path)
  elseif not allow_extend and ffi.new('int64_t',offset)+#bytes>size[0] then e='Запись выходит за конец файла: '..path
  else
    ok,e,c=SeekHandle(h,offset)
    if ok then
      ok,e,c=WriteHandle(h,bytes)
      if not ok then local _; _,e,c=errors.Context('Файл мог измениться ['..path..']',e,c) end
    end
  end
  local closed=C.CloseHandle(h)
  if not ok then return nil,e,c end
  if closed==0 then return Winfailure('CloseHandle после записи',nil,path) end
  return true
end
function M.FileEquals(a,b,block_size)
  block_size=block_size or 1048576
  if not Integer(block_size,1,16777216) then return nil,'invalid block size (1..16777216)' end
  local x,e,c=OpenHandle(a,0x80000000,1,3); if not x then return nil,e,c end
  local y; y,e,c=OpenHandle(b,0x80000000,1,3); if not y then C.CloseHandle(x); return nil,e,c end
  local result=true
  while true do
    local p,q; p,e,c=ReadHandle(x,block_size)
    if p==nil then result=nil; break end
    q,e,c=ReadHandle(y,block_size); if q==nil then result=nil; break end
    if p~=q then result=false; break end
    if #p==0 then break end
  end
  local closed=C.CloseHandle(x); local closeCode=closed==0 and tonumber(C.GetLastError())
  local second=C.CloseHandle(y); if second==0 and not closeCode then closeCode=tonumber(C.GetLastError()) end
  if result==nil then return nil,e,c end
  if closeCode then return Winfailure('CloseHandle',closeCode) end
  return result
end
function M.FileDelete(path)
  local w,e,c=PathWide(path); if not w then return nil,e,c end
  if C.DeleteFileW(w)==0 then return Winfailure('DeleteFileW',nil,path) end
  return true
end
function M.FileMove(a,b,overwrite)
  local source,e,c=M.FileGetInfo(a); if not source then return nil,e,c end
  if not source.is_file then return nil,'Исходный объект не является файлом: '..a end
  return PathMove(a,b,overwrite)
end
local function ListKind(path,folders,pattern)
  if type(pattern)~='string' then return nil,'pattern must be a string' end
  local valid, err, code = ValidatePath(path)
  if not valid then return nil, err, code end
  local request; request, err, code = native.FsScandir(path, true)
  if not request then return nil, err, code end
  local result, wideMask = {}, nil
  if pattern ~= '*' then
    wideMask, err, code = Wide(pattern)
    if not wideMask then return nil, err, code end
  end
  for _, name in ipairs(request.items) do
    if request.metadata[name].is_dir == folders then
      local matches = true
      if wideMask then
        matches, err = GlobNameMatches(name, pattern, wideMask)
        if matches == nil then return nil, err end
      end
      if matches then result[#result + 1] = name end
    end
  end
  return result
end
function M.DirListFiles(path,pattern) return ListKind(path,false,pattern or '*') end
function M.DirListFolders(path) return ListKind(path,true,'*') end
function M.DirIsEmpty(path)
  local names,e,c=M.DirList(path); if not names then return nil,e,c end
  return #names==0
end
-- force=true permits deleting read-only files during recursive deletion.
function M.DirDelete(path,recursive,force)
  if recursive~=nil and type(recursive)~='boolean' then return nil,'recursive must be boolean' end
  if force~=nil and type(force)~='boolean' then return nil,'force must be boolean' end
  local info,e,code=M.FileGetInfo(path); if not info then return nil,e,code end
  if not info.is_dir then return nil,'expected a directory' end
  if recursive~=false then return TreeRemove(path,force) end
  if info.reparse_point then return nil,'expected a non-reparse directory' end
  -- Non-recursive deletion never removes contents. Let the OS reject a
  -- non-empty directory instead of deleting files before reporting failure.
  return DirRemove(path)
end
function M.DirCopy(source,destination,recursive,overwrite)
  if recursive~=nil and type(recursive)~='boolean' then return nil,'recursive must be boolean' end
  if overwrite==nil then overwrite=true end
  return CopyTree(source,destination,overwrite,recursive ~= false)
end

-- Encoded streaming line reader, bounded by the longest line plus a 64 KiB block.
-- Delimiters are found in source bytes; only complete lines are decoded to UTF-8.
-- Offsets and lengths always refer to the original file, before decoding.
local function OpenLines(path,encoding)
  local info,e=EncodingInfo(encoding); if not info then return nil,e end
  if info.kind=='codepage' then
    if info.codepage==65001 then
      info={kind='utf8',name='UTF-8'}
    else
      -- Stateful encodings cannot be decoded independently one line at a time.
      -- Other Windows code pages must represent CR and LF as ASCII bytes.
      if native.CodePageRequiresZeroFlags(info.codepage) or info.codepage==52936 then
        return nil,'encoding is not supported by the streaming line reader: '..info.name
      end
      local cr,err=Utf8ToCodepage('\r\n',info.codepage)
      if cr~='\r\n' then return nil,err or ('encoding does not use ASCII CR/LF: '..info.name) end
    end
  end
  local h,e,c=OpenHandle(path,0x80000000,1,3); if not h then return nil,e,c end
  local prefix; prefix,e,c=ReadHandle(h,4)
  if prefix==nil then C.CloseHandle(h); return nil,e,c end
  local skip=0
  -- Explicit legacy code pages treat every source byte as data, like FileRead.
  -- A leading FF FE in CP1251 can be the ordinary letters "яю", not a BOM.
  if info.kind~='binary' and info.kind~='codepage' then
    if prefix=='\0\0\254\255' or prefix=='\255\254\0\0' then
      C.CloseHandle(h); return nil,'UTF-32 is not supported by the streaming line reader'
    end
    local bom=DetectedBom(prefix)
    if bom and not BomMatchesEncoding(bom,info) then
      C.CloseHandle(h); return nil,'encoding mismatch: existing file has '..bom..' BOM'
    end
    if bom then skip=bom=='UTF-8-BOM' and 3 or 2 end
  end
  local ok; ok,e,c=SeekHandle(h,skip); if not ok then C.CloseHandle(h); return nil,e,c end
  return {handle=Managed(h),buffer='',pos=1,offset=skip,eof=false,encoding=info.name,encoding_info=info}
end
local function CloseLines(reader)
  if type(reader)~='table' then return nil,'invalid reader' end
  reader.buffer=''; reader.pos=1; reader.eof=true; return CloseHandle(reader)
end
local function LineSeparator(reader,b,first)
  local kind=reader.encoding_info.kind
  if kind~='utf16le' and kind~='utf16be' then
    local pos=b:find('[\r\n]',first)
    if pos then
      if b:byte(pos)==13 and pos==#b and not reader.eof then return nil,nil,1 end
      return pos,(b:byte(pos)==13 and b:byte(pos+1)==10) and 2 or 1
    end
    return nil,nil,0
  end
  local be=kind=='utf16be'
  for pos=first,#b-1,2 do
    local a,c=b:byte(pos,pos+1)
    local value=be and (a*256+c) or (a+c*256)
    if value==13 or value==10 then
      if value==13 then
        -- Keep CR together with a partial next code unit across block boundaries.
        if #b-pos+1<4 and not reader.eof then return nil,nil,#b-pos+1 end
        local x,y=b:byte(pos+2,pos+3)
        if y and (be and (x*256+y) or (x+y*256))==10 then return pos,4 end
      end
      return pos,2
    end
  end
  return nil,nil,(#b-first+1)%2
end
local function DecodeReaderLine(reader,raw,start)
  local info=reader.encoding_info
  if info.kind=='binary' then return raw,nil,start,#raw end
  local s,e
  if info.kind=='utf16le' or info.kind=='utf16be' then
    s,e=DecodeUtf16(raw,info.kind=='utf16be')
  elseif info.kind=='codepage' then
    s,e=CodepageToUtf8(raw,info.codepage)
  else
    local ok; ok,e=ValidateUtf8Text(raw); if ok then s=raw end
  end
  if s==nil then return nil,e end
  if s:find('\0',1,true) then return nil,'NUL in text' end
  return s,nil,start,#raw
end
local function ReadLine(reader)
  if type(reader)~='table' or not reader.handle or not reader.encoding_info then return nil,'reader is closed or invalid' end
  local chunks; local start=reader.offset
  while true do
    local b,first=reader.buffer,reader.pos
    local pos,n,keep=LineSeparator(reader,b,first)
    if pos then
      local raw=b:sub(first,pos-1)
      reader.pos=pos+n; reader.offset=reader.offset+pos+n-first
      if chunks then chunks[#chunks+1]=raw; raw=table.concat(chunks) end
      return DecodeReaderLine(reader,raw,start)
    end
    if reader.eof then
      if first>#b and not chunks then return nil end
      local raw=b:sub(first)
      reader.buffer=''; reader.pos=1; reader.offset=reader.offset+#raw
      if chunks then chunks[#chunks+1]=raw; raw=table.concat(chunks) end
      return DecodeReaderLine(reader,raw,start)
    end
    -- Keep the block and advance pos for complete lines. Copy only a partial
    -- line at the block boundary; most lines never need a chunks table.
    local available=#b-first+1-keep
    if available>0 then
      if not chunks then chunks={} end
      chunks[#chunks+1]=b:sub(first,#b-keep); reader.offset=reader.offset+available
    end
    local block,e,c=ReadHandle(reader.handle,65536); if block==nil then return nil,e,c end
    reader.buffer=keep>0 and b:sub(-keep)..block or block
    reader.pos=1; reader.eof=#block==0
  end
end
-- Streaming API with explicit error delivery and deterministic Close.
function M.FileLinesOpen(path, encoding)
  local reader, err, code = OpenLines(path, encoding == nil and 'binary' or encoding)
  if not reader then return nil, err, code end
  local object, ended, last_error, last_code = {}, false
  function object:Close()
    if not reader then return true end
    local ok, e, c = CloseLines(reader)
    reader = nil
    if not ok then last_error, last_code = e, c end
    return ok, e, c
  end
  function object:ErrorGet() return last_error, last_code end
  function object:Next()
    if ended then return nil, last_error, last_code end
    if not reader then return nil, 'Поток строк закрыт' end
    local line, e, c = ReadLine(reader)
    if line ~= nil then return line end
    ended = true
    local ok, close_err, close_code = self:Close()
    last_error, last_code = e, c
    if not e and not ok then last_error, last_code = close_err, close_code end
    return nil, last_error, last_code
  end
  return object
end
-- Without encoding return io.lines directly. With encoding use the managed
-- reader; its read errors are raised and its handle also has a GC fallback.
function M.FileReadLine(path,encoding)
  if type(path)~='string' or path=='' or path:find('\0',1,true) then
    error('path must be a non-empty file path string without NUL',2)
  end
  if encoding==nil then return io.lines(path) end
  local reader,e=OpenLines(path,encoding)
  if not reader then error(e,2) end
  return function()
    if not reader then return nil end
    local line,err=ReadLine(reader)
    if line~=nil then return line end
    local ok,close_err=CloseLines(reader)
    reader=nil
    if err then error(err,2) end
    if not ok then error(close_err,2) end
    return nil
  end
end
function M.FileGetLine(path,number)
  local ok,e=ValidateLineNumber(number); if not ok then return nil,e end
  local r,c; r,e,c=OpenLines(path); if not r then return nil,e,c end
  local s
  for _=1,number do s,e,c=ReadLine(r); if s==nil then break end end
  local closed,ce,cc=CloseLines(r)
  if e then return nil,e,c end
  if not closed then return nil,ce,cc end
  return s
end
function M.FileWriteLines(path,lines,count,eol,final_eol,with_bom)
  if type(lines)~='table' then return nil,'lines must be an array' end
  if count==nil or count==-1 then count=#lines end
  eol=eol or '\r\n'; if final_eol==nil then final_eol=true end
  if not Integer(count,0,#lines) or (eol~='\r\n' and eol~='\n' and eol~='\r') or type(final_eol)~='boolean' or (with_bom~=nil and type(with_bom)~='boolean') then return nil,'invalid line options' end
  local out={}
  for i=1,count do
    local s,e=ValidateLineText(lines[i]); if not s then return nil,e end
    if s:find('\0',1,true) then return nil,'NUL in line' end
    local ok; ok,e=ValidateUtf8Text(s); if not ok then return nil,e end
    out[i]=s
  end
  if count>0 and out[count]=='' and not final_eol then return nil,'empty final line requires final_eol' end
  return M.FileWrite(path,table.concat(out,eol)..(count>0 and final_eol and eol or ''),with_bom and 'UTF-8-BOM' or 'UTF-8')
end
function M.FileDeleteLine(path,number,encoding,allow_lossy)
  local ok,e=ValidateLineNumber(number); if not ok then return nil,e end
  local text,err,code,bom=ReadTextForLineEdit(path,encoding); if text==nil then return nil,err,code end
  local records=ParseTextLines(text); if number>#records then return nil,'line does not exist' end
  table.remove(records,number)
  return RewriteTextPreservingBom(path,BuildTextLines(records),encoding,bom,allow_lossy)
end
function M.FileIndexOpen(path)
  local r,e,c=OpenLines(path); if not r then return nil,e,c end
  local index={handle=r.handle,offsets={},lengths={},count=0}
  while true do
    local s,err,offset,length=ReadLine(r)
    if s==nil then if err then CloseLines(r); return nil,err,offset end; break end
    index.count=index.count+1; index.offsets[index.count]=offset; index.lengths[index.count]=length
  end
  r.handle=nil; return index
end
function M.FileIndexGetLine(index,number)
  if type(index)~='table' or not index.handle then return nil,'index is closed or invalid' end
  local ok,e=ValidateLineNumber(number); if not ok then return nil,e end
  if number>index.count then return nil end
  local c; ok,e,c=SeekHandle(index.handle,index.offsets[number]); if not ok then return nil,e,c end
  local s; s,e,c=ReadHandle(index.handle,index.lengths[number]); if s==nil then return nil,e,c end
  if #s~=index.lengths[number] then return nil,'indexed file was truncated' end
  return s
end
function M.FileIndexClose(index)
  if type(index)~='table' then return nil,'invalid index' end
  index.offsets={}; index.lengths={}; index.count=0; return CloseHandle(index)
end
function M.DirWalk(path,Callback,pattern,exclude,user_data)
  if type(Callback)~='function' then return nil,'callback must be a function' end
  pattern=pattern or '*'; exclude=exclude or ''
  if type(pattern)~='string' or type(exclude)~='string' then return nil,'invalid pattern or exclusions' end
  if pattern=='' or pattern=='*.*' then pattern='*' end
  local root,e,c=NormalizedAbsolute(path); if not root then return nil,e,c end
  local info; info,e,c=M.FileGetInfo(root); if not info then return nil,e,c end
  if not info.is_dir or info.reparse_point then return nil,'root must be a non-reparse directory' end
  local stack={{path=root}}
  while #stack>0 do
    local frame=stack[#stack]
    if not frame.names then frame.names,e,c=M.DirList(frame.path); frame.pos=1; if not frame.names then return nil,e,c end end
    local name=frame.names[frame.pos]; frame.pos=frame.pos+1
    if not name then table.remove(stack)
    else
      local p; p,e=EnumeratedChild(frame.path,name); if not p then return nil,e,c end
      info,e,c=M.FileGetInfo(p); if not info then return nil,e,c end
      local skip=false
      if info.is_dir then
        for mask in exclude:gmatch('[^|]+') do
          local match; match,e=GlobNameMatches(name,mask); if match==nil then return nil,e,c end
          if match then skip=true; break end
        end
      end
      local match=true
      if info.is_file then match,e=GlobNameMatches(name,pattern); if match==nil then return nil,e,c end end
      if not skip and match then
        local ok,result=pcall(Callback,p,info.is_dir and 'directory' or 'file',info.is_dir and 0 or info.size,user_data,info)
        if not ok then return errors.Callback('Directory walk callback',result) end
        if result==0 then return false end
        if result~=1 and result~=2 then return nil,'callback must return 0 (stop), 1 (continue), or 2 (skip)' end
        if info.is_dir and not info.reparse_point and result~=2 then stack[#stack+1]={path=p} end
      end
    end
  end
  return true
end
function M.DirGetStats(path,pattern,exclude)
  local s={bytes=0,files=0,folders=0,reparse_folders=0}
  local ok,e,c=M.DirWalk(path,function(_,kind,size,_,info)
    if kind=='file' then s.files=s.files+1; s.bytes=s.bytes+size
    else s.folders=s.folders+1; if info.reparse_point then s.reparse_folders=s.reparse_folders+1 end end
    return 1
  end,pattern,exclude)
  if not ok then return nil,e,c end
  return s
end
function M.DirSize(path,exclude)
  local s,e,c=M.DirGetStats(path,'*',exclude); if not s then return nil,e,c end
  return s.bytes
end
function M.FileSetAttributes(path,set_mask,clear_mask)
  clear_mask=clear_mask or 0; local allowed=bit.bor(1,2,4,32,8192)
  if not Integer(set_mask,0,4294967295) or not Integer(clear_mask,0,4294967295) or bit.band(bit.bor(set_mask,clear_mask),bit.bnot(allowed))~=0 or bit.band(set_mask,clear_mask)~=0 then return nil,'invalid attribute masks' end
  local attr,e=Attributes(path); if not attr then return nil,e or 'path does not exist' end
  local value=bit.bor(bit.band(attr,bit.bnot(bit.bor(clear_mask,128))),set_mask)
  if value==0 then value=128 end
  local w; w,e=PathWide(path); if not w then return nil,e end
  if C.SetFileAttributesW(w,value)==0 then return Winfailure('SetFileAttributesW') end
  return true
end
function M.FileSetTimes(path,created,accessed,modified)
  local values={}; local args={created,accessed,modified}
  for i=1,3 do
    local n=args[i]
    if n~=nil then
      if not Integer(n,-11644473600,253402300799) then return nil,'time must be whole Unix UTC seconds (-11644473600..253402300799), or nil to keep' end
      local ticks=(ffi.new('int64_t',n)+11644473600LL)*10000000LL
      local t=ffi.new('uio_FILETIME[1]'); t[0].dwLowDateTime=tonumber(ticks%4294967296LL); t[0].dwHighDateTime=tonumber(ticks/4294967296LL); values[i]=t
    end
  end
  local h,e=OpenHandle(path,256,7,3,0x02000000); if not h then return nil,e end
  local ok=C.SetFileTime(h,values[1],values[2],values[3]); local code=C.GetLastError(); C.CloseHandle(h)
  if ok==0 then return Winerror('SetFileTime',code) end
  return true
end
function M.FileFindLines(path,needle,ignore_case,start_line,max_matches)
  start_line=start_line or 1; max_matches=max_matches or 0
  if needle=='' then return nil,'search text must not be empty' end
  local nw,nn=Wide(needle); if not nw then return nil,nn end
  if not Integer(start_line,1,9007199254740991) or not Integer(max_matches,0,2147483647) or (ignore_case~=nil and type(ignore_case)~='boolean') then return nil,'invalid search options' end
  local r,e,c=OpenLines(path); if not r then return nil,e,c end
  local out={}; local number=0
  while true do
    local s; s,e,c=ReadLine(r); if s==nil then break end
    number=number+1
    if number>=start_line then
      local w,n=Wide(s,true); if not w then e=n; break end
      C.SetLastError(0)
      local at=tonumber(C.FindStringOrdinal(0x00400000,w,n,nw,nn,ignore_case and 1 or 0))
      if at<0 then
        local status=tonumber(C.GetLastError())
        if status~=0 then local _; _,e,c=Winerror('FindStringOrdinal',status,path); break end
      end
      if at>=0 then
        -- Preserve the documented UTF-16 column; also expose a Unicode code-point column.
        local column_codepoint, i = 1, 0
        while i < at do
          local unit = tonumber(w[i])
          if unit >= 0xD800 and unit <= 0xDBFF and i + 1 < at
              and w[i+1] >= 0xDC00 and w[i+1] <= 0xDFFF then
            i = i + 2
          else
            i = i + 1
          end
          column_codepoint = column_codepoint + 1
        end
        out[#out+1]={number=number,column=at+1,column_codepoint=column_codepoint,text=s}
        if max_matches>0 and #out>=max_matches then break end
      end
    end
  end
  local closed,ce,cc=CloseLines(r)
  if e then return nil,e,c end
  if not closed then return nil,ce,cc end
  return out
end
function M.FileCopyProgress(source,destination,Callback,user_data,overwrite)
  if Callback~=nil and type(Callback)~='function' then return nil,'callback must be a function' end
  if overwrite~=nil and type(overwrite)~='boolean' then return nil,'overwrite must be boolean' end
  local a,e,c=PathWide(source); if not a then return nil,e,c end
  local b; b,e,c=PathWide(destination); if not b then return nil,e,c end
  local Cb,callback_error,cancelled
  if Callback then Cb=ffi.cast('fs_COPY_PROGRESS',function(total,done)
    local ok,result=pcall(Callback,tonumber(done),tonumber(total),user_data)
    if not ok then callback_error=errors.Message(result); return 1 end
    if result==0 then cancelled=true; return 1 end
    if result~=1 then callback_error='callback must return 1 (continue) or 0 (cancel)'; return 1 end
    return 0
  end) end
  local ok=C.CopyFileExW(a,b,Cb,nil,nil,overwrite and 0 or 1); local code=C.GetLastError()
  if Cb then Cb:free() end
  if callback_error then return nil,callback_error,31 end
  if cancelled then return false end
  if ok==0 then return Winerror('CopyFileExW',code) end
  return true
end

-- CopyFileExW calls back into Lua; keep its invocation outside JIT traces.
if jit then jit.off(M.FileCopyProgress, true) end

M.watchFlags={file_name=1,dir_name=2,attributes=4,size=8,last_write=16,last_access=32,creation=64,security=256,default=27}
M.watchActions={added=1,removed=2,modified=3,renamed_old=4,renamed_new=5}
local function WatchArm(w)
  if C.ResetEvent(w.event)==0 then return Winfailure('ResetEvent') end
  if C.ReadDirectoryChangesW(w.handle,w.buffer,65536,w.recursive and 1 or 0,w.filter,nil,w.overlapped,nil)==0 then return Winfailure('ReadDirectoryChangesW') end
  w.pending=true; return true
end
function M.DirWatchClose(w)
  if type(w)~='table' then return nil,'invalid watcher' end
  if w.handle then
    if w.pending then
      C.CancelIoEx(w.handle,w.overlapped)
      local n=ffi.new('unsigned long[1]'); C.GetOverlappedResult(w.handle,w.overlapped,n,1); w.pending=false
    end
    C.CloseHandle(w.handle); C.CloseHandle(w.event); w.handle=nil; w.event=nil
    w.queue={}; w.buffer=nil; w.overlapped=nil
  end
  return true
end
function M.DirWatchOpen(path,recursive,filter)
  if recursive==nil then recursive=true end
  filter=filter or 27
  if type(recursive)~='boolean' or not Integer(filter,1,383) or bit.band(filter,bit.bnot(383))~=0 then return nil,'invalid watch options' end
  local p,e,c=M.PathAbsolute(path); if not p then return nil,e,c end
  local h; h,e,c=OpenHandle(p,1,7,3,0x42000000); if not h then return nil,e,c end
  local event=C.CreateEventW(nil,1,0,nil)
  if event==nil then local code=C.GetLastError(); C.CloseHandle(h); return Winerror('CreateEventW',code) end
  local w={handle=h,event=event,path=p,recursive=recursive,filter=filter,queue={},nextEvent=1,buffer=ffi.new('uint32_t[16384]'),overlapped=ffi.new('fs_OVERLAPPED[1]')}
  w.overlapped[0].event=event
  local ok; ok,e,c=WatchArm(w); if not ok then M.DirWatchClose(w); return nil,e,c end
  return w
end
function M.DirWatchNext(w,timeout)
  timeout=timeout or 0
  if type(w)~='table' or not w.handle then return nil,'watcher is closed or invalid' end
  if not Integer(timeout,0,60000) then return nil,'timeout must be 0..60000 milliseconds' end
  if w.queue[w.nextEvent] then
    local event = w.queue[w.nextEvent]
    w.queue[w.nextEvent] = nil
    w.nextEvent = w.nextEvent + 1
    return event
  end
  if not w.pending then return nil,'watcher has failed; close and reopen it' end
  local status=tonumber(C.WaitForSingleObject(w.event,timeout))
  if status==258 then return false end
  if status~=0 then return Winfailure('WaitForSingleObject') end
  local n=ffi.new('unsigned long[1]'); local ok=C.GetOverlappedResult(w.handle,w.overlapped,n,0); local code=tonumber(C.GetLastError()); w.pending=false
  if ok==0 and code~=1022 then return Winerror('GetOverlappedResult',code) end
  local queue = {}
  local overflow=ok==0 or n[0]==0
  if not overflow then
    local pos=0; local total=tonumber(n[0]); local bytes=ffi.cast('uint8_t *',w.buffer)
    if total > ffi.sizeof(w.buffer) then return nil,'malformed directory event' end
    local header = ffi.new('uint32_t[3]')
    while pos<total do
      if pos+12>total then return nil,'malformed directory event' end
      -- Some backends pack UTF-16 records on two-byte boundaries.
      ffi.copy(header, bytes + pos, 12)
      local len, next_offset = tonumber(header[2]), tonumber(header[0])
      if len%2~=0 or pos+12+len>total or (next_offset~=0 and (next_offset%2~=0 or next_offset<12+len or pos+next_offset>=total)) then return nil,'malformed directory event' end
      local name,e=Utf8(ffi.cast('unsigned short *',bytes+pos+12),len/2); if not name then return nil,e end
      queue[#queue+1]={action=tonumber(header[1]),name=name,full_path=M.PathJoin(w.path,name)}
      if next_offset==0 then break end
      pos=pos+next_offset
    end
  end
  local armed,e,c=WatchArm(w); if not armed then return nil,e,c end
  if overflow then return nil,'directory events lost; enumerate the directory again',1022 end
  w.queue, w.nextEvent = queue, 2
  return queue[1] or false
end

-- PureBasic path-part semantics; the existing PathBaseName/DirName/Extension stay unchanged.
function M.PathGetFileName(path)
  if type(path)~='string' then return nil,'path must be a string' end
  return path:match('([^/\\:]*)$')
end
function M.PathGetDir(path)
  if type(path)~='string' then return nil,'path must be a string' end
  return path:match('^(.*[/\\:])') or ''
end
function M.PathGetExtension(path)
  local name,e=M.PathGetFileName(path); if not name then return nil,e end
  return name:match('%.([^.]*)$') or ''
end


do
  local win = require("_win_extension")
  ffi.cdef[[
  unsigned long __stdcall GetFileVersionInfoSizeW(const uint16_t *, unsigned long *);
  int __stdcall GetFileVersionInfoW(const uint16_t *, unsigned long, unsigned long, void *);
  int __stdcall VerQueryValueW(const void *, const uint16_t *, void **, unsigned int *);
  ]]
  function M.FileVersionGet(path)
    local wide, err, code = win.PathWide(path)
    if not wide then return nil, err, code end
    local version
    version, err, code = win.Library("version")
    if not version then return nil, err, code end
    local size = version.GetFileVersionInfoSizeW(wide, nil)
    if size == 0 then return win.Error("GetFileVersionInfoSizeW") end
    local data = ffi.new("uint8_t[?]", size)
    if version.GetFileVersionInfoW(wide, 0, size, data) == 0 then
      return win.Error("GetFileVersionInfoW")
    end
    local info, count = ffi.new("void *[1]"), ffi.new("unsigned int[1]")
    local root = win.ToWide("\\")
    if version.VerQueryValueW(data, root, info, count) == 0 or count[0] < 52 then
      return win.Error("VS_FIXEDFILEINFO not found", 1813)
    end
    local fixed = ffi.cast("const uint32_t *", info[0])
    if fixed[0] ~= 0xFEEF04BD then return win.Error("Invalid VS_FIXEDFILEINFO", 13) end
    local result = {major = math.floor(fixed[2] / 65536), minor = fixed[2] % 65536,
      build = math.floor(fixed[3] / 65536), revision = fixed[3] % 65536}
    result.text = ("%d.%d.%d.%d"):format(result.major, result.minor, result.build, result.revision)
    return result
  end

  function M.PathRealGet(path)
    local wide, err, code = win.PathWide(path)
    if not wide then return nil, err, code end
    return native.FsRealpath(path)
  end
end

require("_fs_handle")(M)
require("_subscriptions").FileSystem(M)
return M
