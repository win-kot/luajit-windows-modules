-- Windows x64 types for LuaJIT FFI.
-- This module intentionally contains NO enums, constants or DLL function declarations.
-- Windows 10/11 x64. Load with: local ffi = require("win_types")
local ffi = require("ffi")

ffi.cdef[[
  typedef signed char CHAR;
  typedef unsigned char BYTE;
  typedef unsigned char UCHAR;
  typedef short SHORT;
  typedef unsigned short USHORT;
  typedef int INT;
  typedef unsigned int UINT;
  typedef long LONG;
  typedef unsigned long ULONG;
  typedef long long LONGLONG;
  typedef unsigned long long ULONGLONG;
  typedef int BOOL;
  typedef unsigned char BOOLEAN;
  typedef unsigned short WORD;
  typedef unsigned long DWORD;
  typedef long HRESULT;
  typedef long NTSTATUS;
  typedef unsigned long COLORREF;
  typedef unsigned long LCID;
  typedef unsigned long LCTYPE;
  typedef unsigned short LANGID;
  typedef unsigned short ATOM;
  typedef wchar_t WCHAR;
  typedef CHAR* PCHAR;
  typedef CHAR* LPSTR;
  typedef const CHAR* LPCSTR;
  typedef WCHAR* PWCHAR;
  typedef WCHAR* LPWSTR;
  typedef const WCHAR* LPCWSTR;
  typedef void VOID;
  typedef void* PVOID;
  typedef const void* LPCVOID;
  typedef void* LPVOID;
  typedef void* HANDLE;
  typedef HANDLE HWND;
  typedef HANDLE HINSTANCE;
  typedef HANDLE HMODULE;
  typedef HANDLE HICON;
  typedef HANDLE HCURSOR;
  typedef HANDLE HBRUSH;
  typedef HANDLE HFONT;
  typedef HANDLE HDC;
  typedef HANDLE HMENU;
  typedef HANDLE HBITMAP;
  typedef HANDLE HGDIOBJ;
  typedef HANDLE HKEY;
  typedef HANDLE HGLOBAL;
  typedef HANDLE HLOCAL;
  typedef HANDLE HMONITOR;
  typedef HANDLE HACCEL;
  typedef HANDLE HRSRC;
  typedef HANDLE HHOOK;
  typedef HANDLE HDESK;
  typedef HANDLE HWINSTA;
  typedef HANDLE HPALETTE;
  typedef HANDLE HPEN;
  typedef HANDLE HRGN;
  typedef HANDLE HENHMETAFILE;
  typedef int HFILE;
  typedef void* PSID;
  typedef unsigned long* LPDWORD;
  typedef DWORD* PDWORD;
  typedef BOOL* LPBOOL;
  typedef BYTE* LPBYTE;
  typedef WORD* LPWORD;
  typedef UINT* PUINT;
  typedef LONG* PLONG;
  typedef HANDLE* PHANDLE;
  typedef HWND* PHWND;
  typedef unsigned long long DWORDLONG;
  typedef unsigned long long ULONG64;
  typedef long long LONG64;
  typedef unsigned long long UINT64;
  typedef long long INT64;
  typedef unsigned long long ULONG_PTR;
  typedef long long LONG_PTR;
  typedef unsigned long long UINT_PTR;
  typedef long long INT_PTR;
  typedef unsigned long long DWORD_PTR;
  typedef unsigned long long SIZE_T;
  typedef long long SSIZE_T;
  typedef LONG_PTR LPARAM;
  typedef UINT_PTR WPARAM;
  typedef LONG_PTR LRESULT;
  typedef UINT_PTR SOCKET;
  typedef unsigned short INTERNET_PORT;
  typedef struct _FILETIME {
      DWORD dwLowDateTime;
      DWORD dwHighDateTime;
  } FILETIME, *PFILETIME, *LPFILETIME;
  typedef struct _SYSTEMTIME {
      WORD wYear;
      WORD wMonth;
      WORD wDayOfWeek;
      WORD wDay;
      WORD wHour;
      WORD wMinute;
      WORD wSecond;
      WORD wMilliseconds;
  } SYSTEMTIME, *PSYSTEMTIME, *LPSYSTEMTIME;
  typedef struct tagPOINT { LONG x; LONG y; } POINT, *PPOINT, *LPPOINT;
  typedef struct tagSIZE { LONG cx; LONG cy; } SIZE, *PSIZE, *LPSIZE;
  typedef struct tagRECT {
      LONG left; LONG top; LONG right; LONG bottom;
  } RECT, *PRECT, *LPRECT;
  typedef union _LARGE_INTEGER {
      struct { DWORD LowPart; LONG HighPart; };
      struct { DWORD LowPart; LONG HighPart; } u;
      LONGLONG QuadPart;
  } LARGE_INTEGER, *PLARGE_INTEGER;
  typedef union _ULARGE_INTEGER {
      struct { DWORD LowPart; DWORD HighPart; };
      struct { DWORD LowPart; DWORD HighPart; } u;
      ULONGLONG QuadPart;
  } ULARGE_INTEGER, *PULARGE_INTEGER;
  typedef struct _GUID {
      unsigned long Data1;
      unsigned short Data2;
      unsigned short Data3;
      unsigned char Data4[8];
  } GUID, *LPGUID;
  typedef const GUID* REFGUID;
  typedef const GUID* REFIID;
  typedef const GUID* REFCLSID;
]]

return ffi
