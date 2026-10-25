-- Internal synchronous Windows backend. Only Windows system DLLs are used.
local ffi = require('ffi')
local bit = require('bit')
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
local codes = {[2]='ENOENT',[3]='ENOENT',[5]='EACCES',[17]='EXDEV',
  [32]='EBUSY',[80]='EEXIST',[87]='EINVAL',[123]='ENOENT',[145]='ENOTEMPTY',
  [183]='EEXIST',[203]='ENOENT',[206]='ENAMETOOLONG',[267]='ENOTDIR'}
local function failure(op, code)
  code = tonumber(code or C.GetLastError())
  local name = codes[code] or 'EIO'
  return nil, name .. ': ' .. op .. ' failed (Win32 error ' .. code .. ')', name
end
local function wide(s)
  if type(s) ~= 'string' or s:find('\0',1,true) then return nil, 'expected UTF-8 string without NUL', 'EINVAL' end
  if s == '' then return ffi.new('unsigned short[1]') end
  local n = C.MultiByteToWideChar(65001,8,s,#s,nil,0)
  if n == 0 then return nil, 'invalid UTF-8', 'EINVAL' end
  local w = ffi.new('unsigned short[?]',n+1)
  if C.MultiByteToWideChar(65001,8,s,#s,w,n) ~= n then return failure('MultiByteToWideChar') end
  return w
end
local function utf8(w,n)
  if n == nil then n=0; while w[n] ~= 0 do n=n+1 end end
  if n == 0 then return '' end
  local size = C.WideCharToMultiByte(65001,128,w,n,nil,0,nil,nil)
  if size == 0 then return failure('WideCharToMultiByte') end
  local b = ffi.new('char[?]',size)
  if C.WideCharToMultiByte(65001,128,w,n,b,size,nil,nil) ~= size then return failure('WideCharToMultiByte') end
  return ffi.string(b,size)
end
local function ordinary_path(p)
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
local function fullpath(s)
  local w,e,c=wide(s); if not w then return nil,e,c end
  local capacity=tonumber(C.GetFullPathNameW(w,0,nil,nil))
  if capacity == 0 then return failure('GetFullPathNameW') end
  while true do
    local b=ffi.new('unsigned short[?]',capacity)
    local n=tonumber(C.GetFullPathNameW(w,capacity,b,nil))
    if n == 0 then return failure('GetFullPathNameW') end
    if n < capacity then return utf8(b,n) end
    capacity=n+1
  end
end
local function pathwide(s)
  if type(s) ~= 'string' or s == '' then return nil,'empty or invalid path','EINVAL' end
  -- An explicit Windows namespace path is already absolute. GetFullPathNameW
  -- would strip significant trailing dots/spaces from its last component.
  if s:sub(1,4) == '\\\\?\\' or s:sub(1,4) == '\\\\.\\' then return wide(s) end
  local p,e,c=fullpath(s); if not p then return nil,e,c end
  p=p:gsub('/','\\')
  if p:sub(1,4) ~= '\\\\?\\' and p:sub(1,4) ~= '\\\\.\\' then
    if p:sub(1,2) == '\\\\' then p='\\\\?\\UNC\\'..p:sub(3)
    else p='\\\\?\\'..p end
  end
  return wide(p)
end
-- Shared filesystem path conversion for the high-level I/O module.
M.pathwide = pathwide
function M.os_getenv(name)
  local w,e,c=wide(name); if not w then return nil,e,c end
  local capacity=256
  while true do
    local b=ffi.new('unsigned short[?]',capacity)
    C.SetLastError(0)
    local n=tonumber(C.GetEnvironmentVariableW(w,b,capacity))
    if n == 0 then
      local code=tonumber(C.GetLastError())
      if code == 0 then return '' end
      return failure('GetEnvironmentVariableW',code)
    end
    if n < capacity then return utf8(b,n) end
    capacity=n
  end
end
function M.os_setenv(name,value)
  local w,e,c=wide(name); if not w then return nil,e,c end
  local v
  if value ~= nil then v,e,c=wide(value); if not v then return nil,e,c end end
  if C.SetEnvironmentVariableW(w,v) == 0 then return failure('SetEnvironmentVariableW') end
  return true
end
function M.os_unsetenv(name) return M.os_setenv(name,nil) end
function M.os_getpid() return tonumber(C.GetCurrentProcessId()) end
function M.sleep(ms) C.Sleep(ms) end
function M.uptime() return tonumber(C.GetTickCount64())/1000 end
function M.cwd()
  local capacity=tonumber(C.GetCurrentDirectoryW(0,nil))
  if capacity == 0 then return failure('GetCurrentDirectoryW') end
  while true do
    local b=ffi.new('unsigned short[?]',capacity)
    local n=tonumber(C.GetCurrentDirectoryW(capacity,b))
    if n == 0 then return failure('GetCurrentDirectoryW') end
    if n < capacity then
      local p,e,c=utf8(b,n)
      if not p then return nil,e,c end
      return ordinary_path(p)
    end
    capacity=n+1
  end
end
function M.chdir(path)
  local w,e,c=pathwide(path); if not w then return nil,e,c end
  local p; p,e,c=utf8(w); if not p then return nil,e,c end
  p=ordinary_path(p)
  local expected,previous
  if p:sub(1,4) == '\\\\?\\' or p:sub(1,4) == '\\\\.\\' then
    expected,e,c=M.fs_realpath(path); if not expected then return nil,e,c end
    previous,e,c=M.cwd(); if not previous then return nil,e,c end
  end
  -- SetCurrentDirectoryW still normalizes a final literal component unless
  -- it is followed by a separator, even with an explicit namespace prefix.
  if (p:sub(1,4) == '\\\\?\\' or p:sub(1,4) == '\\\\.\\') and p:sub(-1) ~= '\\' then
    p=p..'\\'
  end
  w,e,c=wide(p); if not w then return nil,e,c end
  -- Do not expose the extended prefix in the process CWD for short paths:
  -- CMD treats it as UNC and Lua's module search treats '?' as a placeholder.
  if ffi.sizeof(w)/2 > 248 then w,e,c=pathwide(p); if not w then return nil,e,c end end
  if C.SetCurrentDirectoryW(w) == 0 then return failure('SetCurrentDirectoryW') end
  local current; current,e,c=M.cwd(); if not current then return nil,e,c end
  -- Windows can normalize literal names even after a successful chdir.
  -- Never report success while relative I/O addresses a different directory.
  if expected then
    local actual; actual,e,c=M.fs_realpath(current)
    if actual ~= expected then
      local restore; restore,e,c=wide(previous)
      if not restore then return nil,e,c end
      if C.SetCurrentDirectoryW(restore) == 0 then return failure('SetCurrentDirectoryW (restore)') end
      return nil,'SetCurrentDirectoryW did not preserve the literal directory; previous directory restored','EINVAL'
    end
  end
  -- Keep Windows drive-relative paths (C:filename) in sync with chdir.
  local drive=current:match('^(%a):') or current:match('^\\\\%?\\(%a):')
  if drive then
    local name=wide('='..drive:upper()..':')
    local value=wide(current)
    if C.SetEnvironmentVariableW(name,value) == 0 then return failure('SetEnvironmentVariableW (drive CWD)') end
  end
  return true
end
function M.exepath()
  local capacity=256
  while capacity <= 65536 do
    local b=ffi.new('unsigned short[?]',capacity)
    local n=tonumber(C.GetModuleFileNameW(nil,b,capacity))
    if n == 0 then return failure('GetModuleFileNameW') end
    if n < capacity then return utf8(b,n) end
    capacity=capacity*2
  end
  return nil,'executable path is too long','ENAMETOOLONG'
end
function M.os_tmpdir()
  -- GetTempPathW can hang on some Windows builds with a long TMP value.
  -- Resolve its documented environment precedence without calling it.
  for _,name in ipairs({'TMP','TEMP','USERPROFILE'}) do
    local p,e,c=M.os_getenv(name)
    if p and p ~= '' then
      if p:sub(1,4) == '\\\\?\\' or p:sub(1,4) == '\\\\.\\' then
        local w; w,e,c=wide(p)
        if not w then return nil,e,c end
        return p
      end
      return fullpath(p)
    end
    if not p and c ~= 'ENOENT' then return nil,e,c end
  end
  local b=ffi.new('unsigned short[32768]')
  local n=tonumber(C.GetWindowsDirectoryW(b,32768))
  if n == 0 or n >= 32768 then return failure('GetWindowsDirectoryW') end
  return utf8(b,n)
end
function M.fs_lstat(path)
  local w,e,c=pathwide(path); if not w then return nil,e,c end
  local a=tonumber(C.GetFileAttributesW(w))
  if a == 4294967295 then return failure('GetFileAttributesW') end
  return {type=bit.band(a,1024) ~= 0 and 'link' or bit.band(a,16) ~= 0 and 'directory' or 'file'}
end
function M.fs_stat(path)
  local w,e,c=pathwide(path); if not w then return nil,e,c end
  -- Opening follows symbolic links, unlike the attribute query in lstat.
  local h=C.CreateFileW(w,0,7,nil,3,0x02000000,nil)
  if h == INVALID then return failure('CreateFileW (stat)') end
  local info=ffi.new('wn_HANDLE_INFO[1]')
  local ok=C.GetFileInformationByHandle(h,info)
  local code=C.GetLastError(); C.CloseHandle(h)
  if ok == 0 then return failure('GetFileInformationByHandle',code) end
  return {type=bit.band(info[0].attr,16) ~= 0 and 'directory' or 'file'}
end
local function unary(api,path)
  local w,e,c=pathwide(path); if not w then return nil,e,c end
  if C[api](w) == 0 then return failure(api) end
  return true
end
function M.fs_mkdir(path)
  local w,e,c=pathwide(path); if not w then return nil,e,c end
  if C.CreateDirectoryW(w,nil) == 0 then return failure('CreateDirectoryW') end
  return true
end
function M.fs_rmdir(path) return unary('RemoveDirectoryW',path) end
function M.fs_unlink(path) return unary('DeleteFileW',path) end
function M.fs_copyfile(from,to,flags)
  local a,e,c=pathwide(from); if not a then return nil,e,c end
  local b; b,e,c=pathwide(to); if not b then return nil,e,c end
  if C.CopyFileW(a,b,flags and flags.excl and 1 or 0) == 0 then return failure('CopyFileW') end
  return true
end
function M.fs_rename(from,to)
  local a,e,c=pathwide(from); if not a then return nil,e,c end
  local b; b,e,c=pathwide(to); if not b then return nil,e,c end
  if C.MoveFileExW(a,b,1) == 0 then return failure('MoveFileExW') end
  return true
end
function M.fs_scandir(path)
  -- Resolve drive-relative forms before adding a separator: C: means the
  -- drive's current directory, whereas C:\* means the drive root.
  local absolute,e,c
  if type(path)=='string' and (path:sub(1,4)=='\\\\?\\' or path:sub(1,4)=='\\\\.\\') then
    absolute=path
  else
    absolute,e,c=fullpath(path); if not absolute then return nil,e,c end
  end
  local info; info,e,c=M.fs_stat(absolute); if not info then return nil,e,c end
  if info.type ~= 'directory' then return nil,'not a directory','ENOTDIR' end
  local w; w,e,c=pathwide(absolute:gsub('[\\/]+$','')..'\\*'); if not w then return nil,e,c end
  local data=ffi.new('wn_FIND_DATA[1]')
  local h=C.FindFirstFileW(w,data)
  if h == INVALID then
    local code=tonumber(C.GetLastError())
    if code == 2 then return {items={},index=0} end
    return failure('FindFirstFileW',code)
  end
  local items={}
  while true do
    local name,err= utf8(data[0].name)
    if not name then C.FindClose(h); return nil,err end
    if name ~= '.' and name ~= '..' then items[#items+1]=name end
    if C.FindNextFileW(h,data) == 0 then
      local code=tonumber(C.GetLastError()); C.FindClose(h)
      if code ~= 18 then return failure('FindNextFileW',code) end
      break
    end
  end
  table.sort(items)
  return {items=items,index=0}
end
function M.fs_scandir_next(request)
  request.index=request.index+1
  return request.items[request.index]
end
function M.fs_realpath(path)
  local w,e,c=pathwide(path); if not w then return nil,e,c end
  local h=C.CreateFileW(w,0,7,nil,3,0x02000000,nil)
  if h == INVALID then return failure('CreateFileW (realpath)') end
  local capacity=512
  while true do
    local b=ffi.new('unsigned short[?]',capacity)
    local n=tonumber(C.GetFinalPathNameByHandleW(h,b,capacity,0))
    if n == 0 then local code=C.GetLastError(); C.CloseHandle(h); return failure('GetFinalPathNameByHandleW',code) end
    if n < capacity then
      C.CloseHandle(h)
      local p,err= utf8(b,n); if not p then return nil,err end
      -- Keep the exact, reopenable namespace path, including literal names.
      return p
    end
    capacity=n+1
  end
end
local function open(path,access,disposition)
  local w,e,c=pathwide(path); if not w then return nil,e,c end
  local h=C.CreateFileW(w,access,7,nil,disposition,128,nil)
  if h == INVALID then return failure('CreateFileW') end
  return ffi.gc(h,C.CloseHandle)
end
function M.fs_open(path,mode)
  if mode == 'r' then return open(path,0x80000000,3) end
  if mode == 'w' then return open(path,0x40000000,2) end
  if mode == 'a' then return open(path,4,4) end -- FILE_APPEND_DATA: atomic append
  return nil,'unsupported internal file mode','EINVAL'
end
function M.fs_close(h)
  if C.CloseHandle(h) == 0 then return failure('CloseHandle') end
  ffi.gc(h,nil)
  return true
end
function M.fs_read(h,count,offset)
  if offset and offset >= 0 and C.SetFilePointerEx(h,offset,nil,0) == 0 then return failure('SetFilePointerEx') end
  local b,n=ffi.new('char[?]',count),ffi.new('unsigned long[1]')
  if C.ReadFile(h,b,count,n,nil) == 0 then return failure('ReadFile') end
  return ffi.string(b,n[0])
end
function M.fs_write(h,data,offset)
  if offset and offset >= 0 and C.SetFilePointerEx(h,offset,nil,0) == 0 then return failure('SetFilePointerEx') end
  local n=ffi.new('unsigned long[1]')
  local count=math.min(#data,0x7fffffff)
  if C.WriteFile(h,data,count,n,nil) == 0 then return failure('WriteFile') end
  return tonumber(n[0])
end
function M.fs_fsync(h)
  if C.FlushFileBuffers(h) == 0 then return failure('FlushFileBuffers') end
  return true
end
function M.fs_mkstemp(template)
  if template:sub(-6) ~= 'XXXXXX' then return nil,'invalid temporary file template','EINVAL' end
  for _=1,128 do
    local random=ffi.new('unsigned char[16]')
    local status=bcrypt.BCryptGenRandom(nil,random,16,2)
    if status < 0 then return nil,'BCryptGenRandom failed: '..tonumber(status),'EIO' end
    local suffix={}
    for i=0,15 do suffix[#suffix+1]=string.format('%02x',random[i]) end
    local name=template:sub(1,-7)..table.concat(suffix)
    local h,e,c=open(name,0xc0000000,1) -- CREATE_NEW is exclusive
    if h then return h,name end
    if c ~= 'EEXIST' then return nil,e,c end
  end
  return nil,'cannot allocate unique temporary file','EEXIST'
end
return M
