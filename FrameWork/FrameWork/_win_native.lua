-- Internal synchronous Windows backend. Only Windows system DLLs are used.
local ffi = require('ffi')
local bit = require('bit')
local errors = require('_errors')
assert(ffi.os == 'Windows', 'win_native requires Windows')
ffi.cdef[[
typedef struct { unsigned long low, high; } wn_FILETIME;
typedef struct {
  unsigned long attr; wn_FILETIME created, accessed, written;
  unsigned long size_high, size_low, reserved0, reserved1;
  unsigned short name[260], alternate[14];
} wn_FIND_DATA;
typedef struct { unsigned long attr; wn_FILETIME created,accessed,written;
  unsigned long volume,size_high,size_low,links,index_high,index_low; } wn_HANDLE_INFO;
int __stdcall GetFileInformationByHandle(void *,wn_HANDLE_INFO *);
unsigned long __stdcall GetLastError(void);
void __stdcall SetLastError(unsigned long);
int __stdcall MultiByteToWideChar(unsigned int,unsigned long,const char *,int,unsigned short *,int);
int __stdcall WideCharToMultiByte(unsigned int,unsigned long,const unsigned short *,int,char *,int,const char *,int *);
unsigned long __stdcall GetEnvironmentVariableW(const unsigned short *,unsigned short *,unsigned long);
int __stdcall SetEnvironmentVariableW(const unsigned short *,const unsigned short *);
unsigned long __stdcall GetCurrentDirectoryW(unsigned long,unsigned short *);
int __stdcall SetCurrentDirectoryW(const unsigned short *);
unsigned long __stdcall GetModuleFileNameW(void *,unsigned short *,unsigned long);
unsigned long __stdcall GetWindowsDirectoryW(unsigned short *,unsigned long);
unsigned long __stdcall GetFullPathNameW(const unsigned short *,unsigned long,unsigned short *,unsigned short **);
unsigned long __stdcall GetCurrentProcessId(void);
uint64_t __stdcall GetTickCount64(void);
void __stdcall Sleep(unsigned long);
unsigned long __stdcall GetFileAttributesW(const unsigned short *);
int __stdcall CreateDirectoryW(const unsigned short *,void *);
int __stdcall RemoveDirectoryW(const unsigned short *);
int __stdcall DeleteFileW(const unsigned short *);
int __stdcall CopyFileW(const unsigned short *,const unsigned short *,int);
int __stdcall MoveFileExW(const unsigned short *,const unsigned short *,unsigned long);
void *__stdcall FindFirstFileW(const unsigned short *,wn_FIND_DATA *);
int __stdcall FindNextFileW(void *,wn_FIND_DATA *);
int __stdcall FindClose(void *);
void *__stdcall CreateFileW(const unsigned short *,unsigned long,unsigned long,void *,unsigned long,unsigned long,void *);
int __stdcall CloseHandle(void *);
int __stdcall SetEndOfFile(void *);
int __stdcall ReadFile(void *,void *,unsigned long,unsigned long *,void *);
int __stdcall WriteFile(void *,const void *,unsigned long,unsigned long *,void *);
int __stdcall SetFilePointerEx(void *,int64_t,int64_t *,unsigned long);
int __stdcall FlushFileBuffers(void *);
unsigned long __stdcall GetFinalPathNameByHandleW(void *,unsigned short *,unsigned long,unsigned long);
long __stdcall BCryptGenRandom(void *,unsigned char *,unsigned long,unsigned long);
]]
local C = ffi.load('kernel32')
local bcrypt = ffi.load('bcrypt')
local M = {}
local INVALID = ffi.cast('void *', -1)
local Failure = errors.Win32
local function Wide(s)
  if type(s) ~= 'string' or s:find('\0',1,true) then return nil, 'Требуется строка UTF-8 без нулевого байта' end
  if s == '' then return ffi.new('unsigned short[1]') end
  local n = C.MultiByteToWideChar(65001,8,s,#s,nil,0)
  if n == 0 then return Failure('MultiByteToWideChar') end
  local w = ffi.new('unsigned short[?]',n+1)
  if C.MultiByteToWideChar(65001,8,s,#s,w,n) ~= n then return Failure('MultiByteToWideChar') end
  return w
end
local function Utf8(w,n)
  if n == nil then n=0; while w[n] ~= 0 do n=n+1 end end
  if n == 0 then return '' end
  local size = C.WideCharToMultiByte(65001,128,w,n,nil,0,nil,nil)
  if size == 0 then return Failure('WideCharToMultiByte') end
  local b = ffi.new('char[?]',size)
  if C.WideCharToMultiByte(65001,128,w,n,b,size,nil,nil) ~= size then return Failure('WideCharToMultiByte') end
  return ffi.string(b,size)
end
local function OrdinaryPath(p)
  if not p then return p end
  -- Removing the namespace prefix must not change the object being named.
  for component in p:sub(5):gmatch('[^\\]+') do
    local stem=(component:match('^[^.]+') or ''):upper()
    if component:find('[ .]$') or stem == 'CON' or stem == 'PRN'
      or stem == 'AUX' or stem == 'NUL' or stem:match('^COM[1-9]$')
      or stem:match('^LPT[1-9]$') then return p end
  end
  if p:sub(1,8) == '\\\\?\\UNC\\' then return '\\\\'..p:sub(9) end
  if p:match('^\\\\%?\\%a:\\') then return p:sub(5) end
  return p
end
local function Fullpath(s)
  local w,e,c=Wide(s); if not w then return nil,e,c end
  local capacity=tonumber(C.GetFullPathNameW(w,0,nil,nil))
  if capacity == 0 then return Failure('GetFullPathNameW') end
  while true do
    local b=ffi.new('unsigned short[?]',capacity)
    local n=tonumber(C.GetFullPathNameW(w,capacity,b,nil))
    if n == 0 then return Failure('GetFullPathNameW') end
    if n < capacity then return Utf8(b,n) end
    capacity=n+1
  end
end
local function PathWide(s)
  if type(s) ~= 'string' or s == '' then return nil,'Требуется непустой путь' end
  -- An explicit Windows namespace path is already absolute. GetFullPathNameW
  -- would strip significant trailing dots/spaces from its last component.
  if s:sub(1,4) == '\\\\?\\' or s:sub(1,4) == '\\\\.\\' then return Wide(s) end
  local p,e,c=Fullpath(s); if not p then return nil,e,c end
  p=p:gsub('/','\\')
  if p:sub(1,4) ~= '\\\\?\\' and p:sub(1,4) ~= '\\\\.\\' then
    if p:sub(1,2) == '\\\\' then p='\\\\?\\UNC\\'..p:sub(3)
    else p='\\\\?\\'..p end
  end
  return Wide(p)
end
-- Shared filesystem path conversion for the high-level I/O module.
M.PathWide = PathWide
function M.CodePageRequiresZeroFlags(codepage)
  return codepage == 42 or codepage == 65000
      or codepage == 50220 or codepage == 50221 or codepage == 50222
      or codepage == 50225 or codepage == 50227 or codepage == 50229
      or (codepage >= 57002 and codepage <= 57011)
end
function M.OsGetEnv(name)
  local w,e,c=Wide(name); if not w then return nil,e,c end
  return M.OsGetEnvWide(w)
end
-- Internal entry points for callers that already validated/converted UTF-16.
function M.OsGetEnvWide(w)
  local capacity=256
  while true do
    local b=ffi.new('unsigned short[?]',capacity)
    C.SetLastError(0)
    local n=tonumber(C.GetEnvironmentVariableW(w,b,capacity))
    if n == 0 then
      local code=tonumber(C.GetLastError())
      if code == 0 then return '' end
      return Failure('GetEnvironmentVariableW',code)
    end
    if n < capacity then return Utf8(b,n) end
    capacity=n
  end
end
function M.OsSetEnv(name,value)
  local w,e,c=Wide(name); if not w then return nil,e,c end
  local v
  if value ~= nil then v,e,c=Wide(value); if not v then return nil,e,c end end
  return M.OsSetEnvWide(w,v)
end
function M.OsSetEnvWide(w,v)
  if C.SetEnvironmentVariableW(w,v) == 0 then return Failure('SetEnvironmentVariableW') end
  return true
end
function M.OsUnsetEnv(name) return M.OsSetEnv(name,nil) end
function M.OsGetpid() return tonumber(C.GetCurrentProcessId()) end
function M.Sleep(ms)
  ms = ms == nil and 0 or tonumber(ms)
  if not ms or ms ~= ms or ms == -math.huge or ms >= 4294967295 then
    return nil, "sleep duration must be finite and below 4294967295 ms"
  end
  if ms < 0 then ms = 0 end
  C.Sleep(math.floor(ms))
end
function M.Uptime() return tonumber(C.GetTickCount64())/1000 end
function M.Cwd()
  local capacity=tonumber(C.GetCurrentDirectoryW(0,nil))
  if capacity == 0 then return Failure('GetCurrentDirectoryW') end
  while true do
    local b=ffi.new('unsigned short[?]',capacity)
    local n=tonumber(C.GetCurrentDirectoryW(capacity,b))
    if n == 0 then return Failure('GetCurrentDirectoryW') end
    if n < capacity then
      local p,e,c=Utf8(b,n)
      if not p then return nil,e,c end
      return OrdinaryPath(p)
    end
    capacity=n+1
  end
end
function M.Chdir(path)
  local w,e,c=PathWide(path); if not w then return nil,e,c end
  local p; p,e,c=Utf8(w); if not p then return nil,e,c end
  p=OrdinaryPath(p)
  local expected,previous
  if p:sub(1,4) == '\\\\?\\' or p:sub(1,4) == '\\\\.\\' then
    expected,e,c=M.FsRealpath(path); if not expected then return nil,e,c end
    previous,e,c=M.Cwd(); if not previous then return nil,e,c end
  end
  -- SetCurrentDirectoryW still normalizes a final literal component unless
  -- it is followed by a separator, even with an explicit namespace prefix.
  if (p:sub(1,4) == '\\\\?\\' or p:sub(1,4) == '\\\\.\\') and p:sub(-1) ~= '\\' then
    p=p..'\\'
  end
  w,e,c=Wide(p); if not w then return nil,e,c end
  -- Do not expose the extended prefix in the process CWD for short paths:
  -- CMD treats it as UNC and Lua's module search treats '?' as a placeholder.
  if ffi.sizeof(w)/2 > 248 then w,e,c=PathWide(p); if not w then return nil,e,c end end
  if C.SetCurrentDirectoryW(w) == 0 then return Failure('SetCurrentDirectoryW',nil,path) end
  local current; current,e,c=M.Cwd(); if not current then return errors.Context('Рабочая папка уже изменена',e,c) end
  -- Windows can normalize literal names even after a successful chdir.
  -- Never report success while relative I/O addresses a different directory.
  if expected then
    local actual; actual,e,c=M.FsRealpath(current)
    if actual ~= expected then
      local restore; restore,e,c=Wide(previous)
      if not restore then return nil,e,c end
      if C.SetCurrentDirectoryW(restore) == 0 then return Failure('SetCurrentDirectoryW (restore)') end
      return nil,'Windows изменила буквальное имя папки; прежняя рабочая папка восстановлена'
    end
  end
  -- Keep Windows drive-relative paths (C:filename) in sync with chdir.
  local drive=current:match('^(%a):') or current:match('^\\\\%?\\(%a):')
  if drive then
    local name=Wide('='..drive:upper()..':')
    local value=Wide(current)
    if C.SetEnvironmentVariableW(name,value) == 0 then return Failure('SetEnvironmentVariableW после смены рабочей папки',nil,path) end
  end
  return true
end
function M.ExePath()
  local capacity=256
  while capacity <= 65536 do
    local b=ffi.new('unsigned short[?]',capacity)
    local n=tonumber(C.GetModuleFileNameW(nil,b,capacity))
    if n == 0 then return Failure('GetModuleFileNameW') end
    if n < capacity then return Utf8(b,n) end
    capacity=capacity*2
  end
  return nil,'Слишком длинный путь к исполняемому файлу'
end
function M.OsTmpDir()
  -- GetTempPathW can hang on some Windows builds with a long TMP value.
  -- Resolve its documented environment precedence without calling it.
  for _,name in ipairs({'TMP','TEMP','USERPROFILE'}) do
    local p,e,c=M.OsGetEnv(name)
    if p and p ~= '' then
      if p:sub(1,4) == '\\\\?\\' or p:sub(1,4) == '\\\\.\\' then
        local w; w,e,c=Wide(p)
        if not w then return nil,e,c end
        return p
      end
      return Fullpath(p)
    end
    if not p and c ~= 203 then return nil,e,c end
  end
  local b=ffi.new('unsigned short[32768]')
  local n=tonumber(C.GetWindowsDirectoryW(b,32768))
  if n == 0 or n >= 32768 then return Failure('GetWindowsDirectoryW') end
  return Utf8(b,n)
end
function M.FsLstat(path)
  local w,e,c=PathWide(path); if not w then return nil,e,c end
  local a=tonumber(C.GetFileAttributesW(w))
  if a == 4294967295 then return Failure('GetFileAttributesW',nil,path) end
  return {type=bit.band(a,1024) ~= 0 and 'link' or bit.band(a,16) ~= 0 and 'directory' or 'file'}
end
function M.FsStat(path)
  local w,e,c=PathWide(path); if not w then return nil,e,c end
  -- Opening follows symbolic links, unlike the attribute query in lstat.
  local h=C.CreateFileW(w,0,7,nil,3,0x02000000,nil)
  if h == INVALID then return Failure('CreateFileW (stat)',nil,path) end
  local info=ffi.new('wn_HANDLE_INFO[1]')
  local ok=C.GetFileInformationByHandle(h,info)
  local code=C.GetLastError()
  local closed=C.CloseHandle(h)
  if ok == 0 then return Failure('GetFileInformationByHandle',code,path) end
  if closed == 0 then return Failure('CloseHandle',nil,path) end
  return {type=bit.band(info[0].attr,16) ~= 0 and 'directory' or 'file'}
end
local function Unary(api,path)
  local w,e,c=PathWide(path); if not w then return nil,e,c end
  if C[api](w) == 0 then return Failure(api,nil,path) end
  return true
end
function M.FsMkdir(path)
  local w,e,c=PathWide(path); if not w then return nil,e,c end
  if C.CreateDirectoryW(w,nil) == 0 then return Failure('CreateDirectoryW',nil,path) end
  return true
end
function M.FsRmdir(path) return Unary('RemoveDirectoryW',path) end
function M.FsUnlink(path) return Unary('DeleteFileW',path) end
function M.FsCopyfile(from,to,flags)
  local a,e,c=PathWide(from); if not a then return nil,e,c end
  local b; b,e,c=PathWide(to); if not b then return nil,e,c end
  if C.CopyFileW(a,b,flags and flags.excl and 1 or 0) == 0 then return Failure('CopyFileW',nil,from..' -> '..to) end
  return true
end
function M.FsRename(from,to)
  local a,e,c=PathWide(from); if not a then return nil,e,c end
  local b; b,e,c=PathWide(to); if not b then return nil,e,c end
  if C.MoveFileExW(a,b,1) == 0 then return Failure('MoveFileExW',nil,from..' -> '..to) end
  return true
end
function M.FsScandir(path, include_metadata)
  -- Resolve drive-relative forms before adding a separator: C: means the
  -- drive's current directory, whereas C:\* means the drive root.
  local absolute,e,c
  if type(path)=='string' and (path:sub(1,4)=='\\\\?\\' or path:sub(1,4)=='\\\\.\\') then
    absolute=path
  else
    absolute,e,c=Fullpath(path); if not absolute then return nil,e,c end
  end
  local info; info,e,c=M.FsStat(absolute); if not info then return nil,e,c end
  if info.type ~= 'directory' then return nil,'Указанный объект не является папкой: ' .. path end
  local w; w,e,c=PathWide(absolute:gsub('[\\/]+$','')..'\\*'); if not w then return nil,e,c end
  local data=ffi.new('wn_FIND_DATA[1]')
  local h=C.FindFirstFileW(w,data)
  if h == INVALID then
    local code=tonumber(C.GetLastError())
    if code == 2 then return {items={},index=0} end
    return Failure('FindFirstFileW',code,path)
  end
  local items={}
  local metadata=include_metadata and {} or nil
  while true do
    local name,err,code= Utf8(data[0].name)
    if not name then C.FindClose(h); return nil,err,code end
    if name ~= '.' and name ~= '..' then
      items[#items+1]=name
      if metadata then
        local attr=tonumber(data[0].attr)
        local is_dir=bit.band(attr,16) ~= 0
        metadata[name]={
          is_file=not is_dir, is_dir=is_dir,
          size=tonumber(data[0].size_high)*4294967296+tonumber(data[0].size_low),
          readonly=bit.band(attr,1) ~= 0, hidden=bit.band(attr,2) ~= 0,
          reparse_point=bit.band(attr,1024) ~= 0
        }
      end
    end
    if C.FindNextFileW(h,data) == 0 then
      local code=tonumber(C.GetLastError())
      local closed=C.FindClose(h)
      if code ~= 18 then return Failure('FindNextFileW',code,path) end
      if closed == 0 then return Failure('FindClose',nil,path) end
      break
    end
  end
  table.sort(items)
  return {items=items,index=0,metadata=metadata}
end
function M.FsScandirNext(request)
  request.index=request.index+1
  return request.items[request.index]
end
function M.FsRealpath(path)
  local w,e,c=PathWide(path); if not w then return nil,e,c end
  local h=C.CreateFileW(w,0,7,nil,3,0x02000000,nil)
  if h == INVALID then return Failure('CreateFileW (realpath)',nil,path) end
  local capacity=512
  while true do
    local b=ffi.new('unsigned short[?]',capacity)
    local n=tonumber(C.GetFinalPathNameByHandleW(h,b,capacity,0))
    if n == 0 then local code=C.GetLastError(); C.CloseHandle(h); return Failure('GetFinalPathNameByHandleW',code) end
    if n < capacity then
      if C.CloseHandle(h) == 0 then return Failure('CloseHandle',nil,path) end
      local p,err,code= Utf8(b,n); if not p then return nil,err,code end
      -- Keep the exact, reopenable namespace path, including literal names.
      return p
    end
    capacity=n+1
  end
end
local function Open(path,access,disposition)
  local w,e,c=PathWide(path); if not w then return nil,e,c end
  local h=C.CreateFileW(w,access,7,nil,disposition,128,nil)
  if h == INVALID then return Failure('CreateFileW',nil,path) end
  return ffi.gc(h,C.CloseHandle)
end
function M.FsOpen(path,mode)
  if mode == 'r' then return Open(path,0x80000000,3) end
  if mode == 'w' then
    -- Open/create, then truncate only the selected data stream. CREATE_ALWAYS
    -- can discard other NTFS streams and rejects existing Hidden/System files.
    local h,e,c=Open(path,0x40000000,4)
    if not h then return nil,e,c end
    if C.SetEndOfFile(h) == 0 then
      local code=C.GetLastError(); C.CloseHandle(h); ffi.gc(h,nil)
      return Failure('SetEndOfFile',code)
    end
    return h
  end
  if mode == 'a' then return Open(path,4,4) end -- FILE_APPEND_DATA: atomic append
  return nil,'Неподдерживаемый режим открытия файла'
end
function M.FsClose(h)
  if C.CloseHandle(h) == 0 then return Failure('CloseHandle') end
  ffi.gc(h,nil)
  return true
end
function M.FsRead(h,count,offset)
  if offset and offset >= 0 and C.SetFilePointerEx(h,offset,nil,0) == 0 then return Failure('SetFilePointerEx') end
  local b,n=ffi.new('char[?]',count),ffi.new('unsigned long[1]')
  if C.ReadFile(h,b,count,n,nil) == 0 then return Failure('ReadFile') end
  return ffi.string(b,n[0])
end
function M.FsWrite(h,data,offset)
  if offset and offset >= 0 and C.SetFilePointerEx(h,offset,nil,0) == 0 then return Failure('SetFilePointerEx') end
  local n=ffi.new('unsigned long[1]')
  local count=math.min(#data,0x7fffffff)
  if C.WriteFile(h,data,count,n,nil) == 0 then return Failure('WriteFile') end
  return tonumber(n[0])
end
function M.FsFsync(h)
  if C.FlushFileBuffers(h) == 0 then return Failure('FlushFileBuffers') end
  return true
end
local function ReserveTemp(template, create)
  if template:sub(-6) ~= 'XXXXXX' then return nil,'Неверный шаблон имени временного объекта' end
  for _=1,128 do
    local random=ffi.new('unsigned char[16]')
    local status=bcrypt.BCryptGenRandom(nil,random,16,2)
    if status < 0 then return errors.Status('BCryptGenRandom', 'NTSTATUS', tonumber(status)) end
    local suffix={}
    for i=0,15 do suffix[#suffix+1]=string.format('%02x',random[i]) end
    local name=template:sub(1,-7)..table.concat(suffix)
    local result,e,c=create(name)
    if result then return result,name end
    if not errors.AlreadyExists(c) then return nil,e,c end
  end
  return nil,'Не удалось подобрать свободное имя временного объекта'
end
function M.FsMkstemp(template)
  return ReserveTemp(template, function(name) return Open(name,0xc0000000,1) end)
end
function M.FsMkdtemp(template)
  local created, name, code = ReserveTemp(template, M.FsMkdir)
  if not created then return nil, name, code end
  return name
end
return M
