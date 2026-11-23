-- GUI library for LuaJIT FFI / Win32
-- 2026-10-23: resize modes "resizable"/"fixed"; modern folder picker via file_dialog.
-- 2026-10-23: screen/taskbar metrics, font size, Label alignment; preserve Window API.
-- 2026-10-21: erase GroupBox backgrounds after minimize/restore; preserve tab surfaces.
--
-- Minimum requirements:
--   Windows 10 version 1607 (build 14393) or newer
--   Per-Monitor DPI Awareness V2 is used on Windows 10 1703+; 1607 falls back to Per-Monitor V1
--   64-bit Windows
--   64-bit LuaJIT with FFI support
--
-- This library intentionally does not support x86 LuaJIT or Windows 7/8/8.1.
-- It uses SetWindowLongPtrW and GetDpiForWindow directly.
-- Font styles accept only "bold"/"normal" and "italic"/"normal" respectively.
-- Boolean-style parameters accept true or a non-zero number as enabled.
-- nil, false and 0 mean disabled.
-- For radio buttons, pass groupStart=true on the first button of each group.
-- Mark the first control after a radio group with WS_GROUP to end arrow navigation.
-- Menu command IDs 1 and 2 are reserved for dialog IDOK/IDCANCEL; use 3..65535.
-- FileOpen(title, filters, initialDir) / FileSave(title, filters, initialDir):
--   filters = {{"Lua files", "*.lua"}, {"All files", "*.*"}}; nil keeps no filter.
--   Multiple patterns: "*.lua;*.txt". The first filter is selected initially.
--   initialDir is an optional UTF-8 folder path passed to lpstrInitialDir.
--   Windows may prefer a previously visited folder according to its dialog policy.
--   Existing title-only calls and path/nil/nil,error results are unchanged.

---@class GuiFFI: ffilib
---@field NULL nil LuaJIT null pointers compare equal to nil; this legacy lookup is nil.
---@class GuiRect: ffi.cdata*
---@field left integer
---@field top integer
---@field right integer
---@field bottom integer
---@class GuiNotifyHeader: ffi.cdata*
---@field idFrom integer
---@field code integer
---@class GuiListNotify: ffi.cdata*
---@field uChanged integer
---@field uOldState integer
---@field uNewState integer

local ffi = require("win_types")
---@cast ffi GuiFFI
local bit = require("bit")
local jit = require("jit")
-- Every native call below may synchronously re-enter Lua through WNDPROC.
jit.off(true, true)

if ffi.os ~= "Windows" then
    error("gui_luajit_v2 requires Windows 10/11 x64", 2)
end

if not ffi.abi("64bit") then
    error("gui_luajit_v2 requires 64-bit LuaJIT on 64-bit Windows", 2)
end

ffi.cdef[[
typedef unsigned char BYTE;
typedef unsigned short WORD;
typedef unsigned short WCHAR;
typedef int BOOL;
typedef int INT;
typedef unsigned int UINT;
typedef unsigned long DWORD;
typedef unsigned long COLORREF;
typedef uintptr_t UINT_PTR;
typedef uintptr_t WPARAM;
typedef intptr_t LPARAM;
typedef intptr_t LRESULT;
typedef intptr_t LONG_PTR;

typedef void* HANDLE;
typedef HANDLE HWND;
typedef HANDLE HINSTANCE;
typedef HANDLE HMENU;
typedef HANDLE HFONT;
typedef HANDLE HGDIOBJ;
typedef HANDLE HDC;
typedef HANDLE HICON;
typedef HANDLE HCURSOR;
typedef HANDLE HBRUSH;
typedef HANDLE HTREEITEM;
typedef HANDLE HDROP;
typedef HANDLE HGLOBAL;
typedef HANDLE PIDLIST_ABSOLUTE;
typedef long HRESULT;
typedef unsigned long ULONG;
typedef unsigned short CLIPFORMAT;


typedef struct {
    CLIPFORMAT cfFormat;
    void* ptd;
    DWORD dwAspect;
    long lindex;
    DWORD tymed;
} FORMATETC;

typedef union {
    HGLOBAL hGlobal;
    void* ptr;
} STGMEDIUM_UNION;

typedef struct {
    DWORD tymed;
    STGMEDIUM_UNION u;
    void* pUnkForRelease;
} STGMEDIUM;

typedef struct IDataObject IDataObject;
typedef struct IDataObjectVtbl IDataObjectVtbl;

struct IDataObject {
    IDataObjectVtbl* lpVtbl;
};

struct IDataObjectVtbl {
    HRESULT (__stdcall *QueryInterface)(IDataObject*, const GUID*, void**);
    ULONG (__stdcall *AddRef)(IDataObject*);
    ULONG (__stdcall *Release)(IDataObject*);
    HRESULT (__stdcall *GetData)(IDataObject*, FORMATETC*, STGMEDIUM*);
    HRESULT (__stdcall *GetDataHere)(IDataObject*, FORMATETC*, STGMEDIUM*);
    HRESULT (__stdcall *QueryGetData)(IDataObject*, FORMATETC*);
};

typedef struct IDropTarget IDropTarget;
typedef struct IDropTargetVtbl IDropTargetVtbl;

struct IDropTarget {
    IDropTargetVtbl* lpVtbl;
};

struct IDropTargetVtbl {
    HRESULT (__stdcall *QueryInterface)(IDropTarget*, const GUID*, void**);
    ULONG (__stdcall *AddRef)(IDropTarget*);
    ULONG (__stdcall *Release)(IDropTarget*);
    HRESULT (__stdcall *DragEnter)(IDropTarget*, IDataObject*, DWORD, int64_t, DWORD*);
    HRESULT (__stdcall *DragOver)(IDropTarget*, DWORD, int64_t, DWORD*);
    HRESULT (__stdcall *DragLeave)(IDropTarget*);
    HRESULT (__stdcall *Drop)(IDropTarget*, IDataObject*, DWORD, int64_t, DWORD*);
};

typedef struct {
    IDropTargetVtbl* lpVtbl;
    ULONG refCount;
    HWND hwnd;
    int controlId;
    BOOL isMain;
    BOOL canDrop;
} LuaDropTarget;
// POINTL is 8 bytes passed as an integer on Windows x64. LuaJIT cannot
// implement callbacks with by-value struct arguments, so int64_t is ABI-equivalent.


typedef const WCHAR* LPCWSTR;
typedef WCHAR* LPWSTR;

typedef uintptr_t DWORD_PTR;
typedef LRESULT (__stdcall *GUI_GROUP_SUBCLASSPROC)(HWND, UINT, WPARAM, LPARAM, UINT_PTR, DWORD_PTR);
BOOL SetWindowSubclass(HWND, GUI_GROUP_SUBCLASSPROC, UINT_PTR, DWORD_PTR);
BOOL RemoveWindowSubclass(HWND, GUI_GROUP_SUBCLASSPROC, UINT_PTR);
LRESULT DefSubclassProc(HWND, UINT, WPARAM, LPARAM);
HWND GetWindow(HWND, UINT);
BOOL IsWindowVisible(HWND);
int ExcludeClipRect(HDC, int, int, int, int);
typedef LRESULT (__stdcall *WNDPROC)(HWND, UINT, WPARAM, LPARAM);



typedef struct {
    DWORD cbSize;
    RECT rcMonitor;
    RECT rcWork;
    DWORD dwFlags;
} MONITORINFO;

// TASKBAR: primary Windows shell appbar information.
typedef struct {
    DWORD cbSize;
    HWND hWnd;
    UINT uCallbackMessage;
    UINT uEdge;
    RECT rc;
    LPARAM lParam;
} APPBARDATA;

typedef struct {
    HWND hwnd;
    UINT message;
    WPARAM wParam;
    LPARAM lParam;
    DWORD time;
    POINT pt;
    DWORD lPrivate;
} MSG;

typedef struct {
    HWND hwndFrom;
    UINT_PTR idFrom;
    UINT code;
} NMHDR;

typedef struct {
    NMHDR hdr;
    int iItem;
    int iSubItem;
    UINT uNewState;
    UINT uOldState;
    UINT uChanged;
    POINT ptAction;
    LPARAM lParam;
} NMLISTVIEW;

typedef struct {
    UINT mask;
    DWORD dwState;
    DWORD dwStateMask;
    LPWSTR pszText;
    int cchTextMax;
    int iImage;
    LPARAM lParam;
} TCITEMW;

typedef struct {
    UINT mask;
    int fmt;
    int cx;
    LPWSTR pszText;
    int cchTextMax;
    int iSubItem;
    int iImage;
    int iOrder;
    int cxMin;
    int cxDefault;
    int cxIdeal;
} LVCOLUMNW;

typedef struct {
    UINT mask;
    int iItem;
    int iSubItem;
    UINT state;
    UINT stateMask;
    LPWSTR pszText;
    int cchTextMax;
    int iImage;
    LPARAM lParam;
    int iIndent;
    int iGroupId;
    UINT cColumns;
    UINT* puColumns;
    int* piColFmt;
    int iGroup;
} LVITEMW;

typedef struct {
    UINT mask;
    HTREEITEM hItem;
    UINT state;
    UINT stateMask;
    LPWSTR pszText;
    int cchTextMax;
    int iImage;
    int iSelectedImage;
    int cChildren;
    LPARAM lParam;
    int iIntegral;
    UINT uStateEx;
    HWND hwnd;
    int iExpandedImage;
    int iReserved;
} TVITEMEXW;

typedef struct {
    HTREEITEM hParent;
    HTREEITEM hInsertAfter;
    TVITEMEXW item;
} TVINSERTSTRUCTW;

typedef struct {
    UINT cbSize;
    UINT uFlags;
    HWND hwnd;
    UINT_PTR uId;
    int rectLeft;
    int rectTop;
    int rectRight;
    int rectBottom;
    HINSTANCE hinst;
    LPWSTR lpszText;
    LPARAM lParam;
    void* lpReserved;
} TTTOOLINFOW;

typedef struct {
    DWORD lStructSize;
    HWND hwndOwner;
    HINSTANCE hInstance;
    LPCWSTR lpstrFilter;
    LPWSTR lpstrCustomFilter;
    DWORD nMaxCustFilter;
    DWORD nFilterIndex;
    LPWSTR lpstrFile;
    DWORD nMaxFile;
    LPWSTR lpstrFileTitle;
    DWORD nMaxFileTitle;
    LPCWSTR lpstrInitialDir;
    LPCWSTR lpstrTitle;
    DWORD Flags;
    WORD nFileOffset;
    WORD nFileExtension;
    LPCWSTR lpstrDefExt;
    LPARAM lCustData;
    void* lpfnHook;
    LPCWSTR lpTemplateName;
    void* pvReserved;
    DWORD dwReserved;
    DWORD FlagsEx;
} OPENFILENAMEW;


typedef struct {
    DWORD lStructSize;
    HWND hwndOwner;
    HWND hInstance;
    COLORREF rgbResult;
    COLORREF* lpCustColors;
    DWORD Flags;
    LPARAM lCustData;
    void* lpfnHook;
    LPCWSTR lpTemplateName;
} CHOOSECOLORW;

typedef struct {
    int lfHeight;
    int lfWidth;
    int lfEscapement;
    int lfOrientation;
    int lfWeight;
    BYTE lfItalic;
    BYTE lfUnderline;
    BYTE lfStrikeOut;
    BYTE lfCharSet;
    BYTE lfOutPrecision;
    BYTE lfClipPrecision;
    BYTE lfQuality;
    BYTE lfPitchAndFamily;
    WCHAR lfFaceName[32];
} LOGFONTW;

typedef struct {
    DWORD lStructSize;
    HWND hwndOwner;
    HDC hDC;
    LOGFONTW* lpLogFont;
    INT iPointSize;
    DWORD Flags;
    COLORREF rgbColors;
    LPARAM lCustData;
    void* lpfnHook;
    LPCWSTR lpTemplateName;
    HINSTANCE hInstance;
    LPWSTR lpszStyle;
    WORD nFontType;
    WORD ___MISSING_ALIGNMENT__;
    INT nSizeMin;
    INT nSizeMax;
} CHOOSEFONTW;

int MultiByteToWideChar(UINT CodePage, DWORD dwFlags, const char* lpMultiByteStr, int cbMultiByte, WCHAR* lpWideCharStr, int cchWideChar);
int WideCharToMultiByte(UINT CodePage, DWORD dwFlags, const WCHAR* lpWideCharStr, int cchWideChar, char* lpMultiByteStr, int cbMultiByte, const char* lpDefaultChar, BOOL* lpUsedDefaultChar);

HINSTANCE GetModuleHandleW(LPCWSTR lpModuleName);
int MulDiv(int nNumber, int nNumerator, int nDenominator);

HWND CreateWindowExW(DWORD dwExStyle, LPCWSTR lpClassName, LPCWSTR lpWindowName, DWORD dwStyle,
    int X, int Y, int nWidth, int nHeight, HWND hWndParent, HMENU hMenu,
    HINSTANCE hInstance, void* lpParam);
BOOL ShowWindow(HWND hWnd, int nCmdShow);
BOOL UpdateWindow(HWND hWnd);
BOOL DestroyWindow(HWND hWnd);
BOOL DestroyMenu(HMENU hMenu);
BOOL IsWindow(HWND hWnd);
BOOL IsMenu(HMENU hMenu);
BOOL IsWindowEnabled(HWND hWnd);
HWND GetFocus(void);
BOOL GetWindowRect(HWND hWnd, RECT* rect);
int GetSystemMetrics(int nIndex);
typedef LRESULT (__stdcall *GuiMessageBoxHookProc)(int, WPARAM, LPARAM);
HANDLE SetWindowsHookExW(int, GuiMessageBoxHookProc, HINSTANCE, DWORD);
BOOL UnhookWindowsHookEx(HANDLE);
LRESULT CallNextHookEx(HANDLE, int, WPARAM, LPARAM);
DWORD GetCurrentThreadId(void);
int GetClassNameW(HWND, LPWSTR, int);
HANDLE MonitorFromWindow(HWND hwnd, DWORD dwFlags);
BOOL GetMonitorInfoW(HANDLE hMonitor, MONITORINFO* lpmi);
BOOL AdjustWindowRectExForDpi(RECT* lpRect, DWORD dwStyle, BOOL bMenu, DWORD dwExStyle, UINT dpi);
BOOL PeekMessageW(MSG* msg, HWND hwnd, UINT min, UINT max, UINT remove);
BOOL SetDialogDpiChangeBehavior(HWND hwnd, int mask, int values);
BOOL SetDialogControlDpiChangeBehavior(HWND hwnd, int mask, int values);
DWORD GetObjectType(HGDIOBJ object);
int GetObjectW(HGDIOBJ object, int size, void* data);
DWORD GetLastError(void);
void SetLastError(DWORD code);
DWORD CommDlgExtendedError(void);
LONG_PTR SetWindowLongPtrW(HWND hWnd, int nIndex, LONG_PTR dwNewLong);
LRESULT CallWindowProcW(WNDPROC lpPrevWndFunc, HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam);
LRESULT DefWindowProcW(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam);
int GetMessageW(MSG* lpMsg, HWND hWnd, UINT wMsgFilterMin, UINT wMsgFilterMax);
BOOL IsDialogMessageW(HWND hDlg, MSG* lpMsg);
BOOL TranslateMessage(const MSG* lpMsg);
LRESULT DispatchMessageW(const MSG* lpMsg);
void PostQuitMessage(int nExitCode);
void* OpenThemeData(HWND hwnd, const WCHAR* pszClassList);
long CloseThemeData(void* hTheme);
long DrawThemeBackground(void* hTheme, HDC hdc, int iPartId, int iStateId, const RECT* pRect, const RECT* pClipRect);
BOOL IsThemeActive(void);
int SaveDC(HDC hdc);
BOOL RestoreDC(HDC hdc, int nSavedDC);
int IntersectClipRect(HDC hdc, int left, int top, int right, int bottom);
BOOL SetWindowTextW(HWND hWnd, LPCWSTR lpString);
int GetWindowTextLengthW(HWND hWnd);
int GetWindowTextW(HWND hWnd, LPWSTR lpString, int nMaxCount);
int GetDlgCtrlID(HWND hWnd);
BOOL EnableWindow(HWND hWnd, BOOL bEnable);
BOOL MoveWindow(HWND hWnd, int X, int Y, int nWidth, int nHeight, BOOL bRepaint);
BOOL SetWindowPos(HWND hWnd, HWND hWndInsertAfter, int X, int Y, int cx, int cy, UINT uFlags);
BOOL SetProcessDpiAwarenessContext(void* value);
void* SetThreadDpiAwarenessContext(void* dpiContext);
void* GetThreadDpiAwarenessContext(void);
BOOL AreDpiAwarenessContextsEqual(void* dpiContextA, void* dpiContextB);
HWND SetFocus(HWND hWnd);
int MessageBoxW(HWND hWnd, LPCWSTR lpText, LPCWSTR lpCaption, UINT uType);
HMENU CreateMenu(void);
HMENU CreatePopupMenu(void);
BOOL AppendMenuW(HMENU hMenu, UINT uFlags, UINT_PTR uIDNewItem, LPCWSTR lpNewItem);
BOOL SetMenu(HWND hWnd, HMENU hMenu);
BOOL DrawMenuBar(HWND hWnd);
LRESULT SendMessageW(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam);
UINT GetDpiForWindow(HWND hwnd);
HDC GetDC(HWND hwnd);
BOOL GetClientRect(HWND hWnd, RECT* rect);
BOOL ClientToScreen(HWND hWnd, POINT* point);
int FillRect(HDC hdc, const RECT* lprc, HBRUSH hbr);
HBRUSH GetSysColorBrush(int nIndex);
DWORD GetSysColor(int nIndex);
int ReleaseDC(HWND hwnd, HDC dc);
int GetDeviceCaps(HDC dc, int index);

HGDIOBJ GetStockObject(int i);
COLORREF SetBkColor(HDC hdc, COLORREF color);
COLORREF SetTextColor(HDC hdc, COLORREF color);
int SetBkMode(HDC hdc, int mode);
HFONT CreateFontW(int cHeight, int cWidth, int cEscapement, int cOrientation, int cWeight,
    DWORD bItalic, DWORD bUnderline, DWORD bStrikeOut, DWORD iCharSet,
    DWORD iOutPrecision, DWORD iClipPrecision, DWORD iQuality,
    DWORD iPitchAndFamily, LPCWSTR pszFaceName);
BOOL DeleteObject(HGDIOBJ ho);

typedef struct {
    DWORD dwSize;
    DWORD dwICC;
} INITCOMMONCONTROLSEX;

void InitCommonControls(void);
BOOL InitCommonControlsEx(const INITCOMMONCONTROLSEX* picce);

BOOL InvalidateRect(HWND hWnd, const void* lpRect, BOOL bErase);

BOOL GetOpenFileNameW(OPENFILENAMEW* ofn);
BOOL GetSaveFileNameW(OPENFILENAMEW* ofn);
BOOL ChooseColorW(CHOOSECOLORW* cc);
BOOL ChooseFontW(CHOOSEFONTW* cf);

UINT DragQueryFileW(HDROP hDrop, UINT iFile, LPWSTR lpszFile, UINT cch);
UINT_PTR SHAppBarMessage(DWORD dwMessage, APPBARDATA* pData);

void CoTaskMemFree(void* pv);
long OleInitialize(void* pvReserved);
void OleUninitialize(void);
HRESULT RegisterDragDrop(HWND hwnd, IDropTarget* pDropTarget);
HRESULT RevokeDragDrop(HWND hwnd);
void ReleaseStgMedium(STGMEDIUM* pmedium);
]]

local user32 = ffi.load("user32")
local kernel32 = ffi.load("kernel32")
local gdi32 = ffi.load("gdi32")
local hasWindowDpi, getWindowDpi = pcall(function() return user32.GetDpiForWindow end)
local hasSetProcessDpi, setProcessDpi = pcall(function() return user32.SetProcessDpiAwarenessContext end)
local hasSetThreadDpi, setThreadDpi = pcall(function() return user32.SetThreadDpiAwarenessContext end)
local hasGetThreadDpi, getThreadDpi = pcall(function() return user32.GetThreadDpiAwarenessContext end)
local hasCompareDpi, compareDpi = pcall(function() return user32.AreDpiAwarenessContextsEqual end)
local hasDialogDpi, setDialogDpi = pcall(function() return user32.SetDialogDpiChangeBehavior end)
local hasControlDpi, setControlDpi = pcall(function() return user32.SetDialogControlDpiChangeBehavior end)
local comctl32 = ffi.load("comctl32")
local comdlg32 = ffi.load("comdlg32")
local shell32 = ffi.load("shell32")
local ole32 = ffi.load("ole32")
local uxtheme = ffi.load("uxtheme")

local CP_UTF8 = 65001
local C = {} -- Win32 constants: avoid LuaJIT's 200-local limit

C.CF_HDROP = 15
C.DVASPECT_CONTENT = 1
C.TYMED_HGLOBAL = 1
C.DROPEFFECT_NONE = 0
C.DROPEFFECT_COPY = 1
C.S_OK = 0
C.E_NOINTERFACE = -2147467262
C.E_POINTER = -2147467261

C.WM_DESTROY = 2
C.WM_CLOSE = 16
C.WM_NCDESTROY = 130
C.WM_SETFONT = 48
C.WM_COMMAND = 273
C.WM_HSCROLL = 276
C.EM_SETSEL = 0x00B1
C.EM_SCROLLCARET = 0x00B7
C.WM_NOTIFY = 78
C.WM_ERASEBKGND = 0x0014
C.WM_PRINTCLIENT = 0x0318
C.COLOR_BTNFACE = 15
C.WM_CTLCOLORBTN = 0x0135
C.WM_CTLCOLORSTATIC = 0x0138
C.COLOR_WINDOW = 5
C.WM_THEMECHANGED = 0x031A
C.TCM_ADJUSTRECT = 4904 -- TCM_FIRST + 40
C.TABP_PANE = 9
C.NULL_BRUSH = 5
C.TRANSPARENT = 1
C.WM_DPICHANGED = 736

C.DEFAULT_DPI = 96
C.DPI_CONTEXT_PER_MONITOR_AWARE = ffi.cast("void*", ffi.cast("intptr_t", -3))
C.DPI_CONTEXT_PER_MONITOR_AWARE_V2 = ffi.cast("void*", ffi.cast("intptr_t", -4))

C.MF_STRING = 0
C.MF_SEPARATOR = 2048
C.MF_POPUP = 16

C.SB_SETTEXTW = 1035
C.TTM_ADDTOOLW = 1074
C.TTM_UPDATETIPTEXTW = 1081
C.TTF_IDISHWND = 1
C.TTF_SUBCLASS = 16

C.OFN_OVERWRITEPROMPT = 2
C.OFN_HIDEREADONLY = 4
C.OFN_NOCHANGEDIR = 8
C.OFN_PATHMUSTEXIST = 2048
C.OFN_FILEMUSTEXIST = 4096
C.OFN_EXPLORER = 524288

C.CC_RGBINIT = 1
C.CC_FULLOPEN = 2

C.BIF_RETURNONLYFSDIRS = 1
C.BIF_NEWDIALOGSTYLE = 64

C.MB_OK = 0
C.MB_ICONINFORMATION = 64

C.TCN_SELCHANGE = -551
C.LVN_ITEMCHANGED = -101
C.TVN_SELCHANGEDW = -451

C.TCM_GETITEMCOUNT = 4868
C.TCM_GETCURSEL = 4875
C.TCM_SETCURSEL = 4876
C.TCM_INSERTITEMW = 4926
C.TCIF_TEXT = 1

C.LVM_GETITEMCOUNT = 4100
C.LVM_GETNEXTITEM = 4108
C.LVM_SETEXTENDEDLISTVIEWSTYLE = 4150
C.LVM_INSERTITEMW = 4173
C.LVM_INSERTCOLUMNW = 4193
C.LVM_SETCOLUMNWIDTH = 4126
C.LVM_GETITEMTEXTW = 4211
C.LVM_SETITEMTEXTW = 4212
C.LVIF_TEXT = 1
C.LVIF_STATE = 8
C.LVIS_SELECTED = 2
C.LVCF_FMT = 1
C.LVCF_WIDTH = 2
C.LVCF_TEXT = 4
C.LVCF_SUBITEM = 8
C.LVNI_SELECTED = 2
C.LVS_EX_GRIDLINES = 1
C.LVS_EX_FULLROWSELECT = 32

C.TVM_EXPAND = 4354
C.TVM_GETNEXTITEM = 4362
C.TVM_INSERTITEMW = 4402
C.TVM_GETITEMW = 4414
C.TVIF_TEXT = 1
C.TVGN_CARET = 9
C.TVE_EXPAND = 2

C.BM_GETCHECK = 240
C.BM_SETCHECK = 241
C.BST_CHECKED = 1

C.BN_CLICKED = 0
C.CBN_SELCHANGE = 1
C.EN_CHANGE = 768

C.CB_ADDSTRING = 323
C.CB_GETCURSEL = 327
C.CB_GETLBTEXT = 328
C.CB_GETLBTEXTLEN = 329
C.CB_RESETCONTENT = 331
C.CB_SETCURSEL = 334

C.LB_ADDSTRING = 384
C.LB_RESETCONTENT = 388
C.LB_SETCURSEL = 390
C.LB_GETCURSEL = 392
C.LB_GETTEXT = 393
C.LB_GETTEXTLEN = 394

C.PBM_SETPOS = 1026
C.PBM_SETRANGE32 = 1030

C.TBM_GETPOS = 1024
C.TBM_SETPOS = 1029
C.TBM_SETRANGEMIN = 1031
C.TBM_SETRANGEMAX = 1032

C.GWLP_WNDPROC = -4

C.SW_HIDE = 0
C.SW_SHOW = 5

C.SWP_NOZORDER = 0x0004
C.SWP_NOACTIVATE = 0x0010

C.WS_OVERLAPPEDWINDOW = 0x00CF0000
C.WS_THICKFRAME = 0x00040000
C.WS_MAXIMIZEBOX = 0x00010000
C.WS_GROUP = 0x00020000
C.WS_CLIPCHILDREN = 0x02000000
C.WS_CLIPSIBLINGS = 0x04000000

C.STYLE_LABEL = 0x50000000
C.STYLE_BUTTON = 0x50010000
C.STYLE_EDIT = 0x50810080
C.ES_MULTILINE = 0x0004
C.ES_PASSWORD = 0x0020
C.ES_AUTOVSCROLL = 0x0040
C.ES_READONLY = 0x0800
C.ES_WANTRETURN = 0x1000
C.WS_VSCROLL = 0x00200000
-- STYLE_EDIT includes ES_AUTOHSCROLL.  Remove it for normal multiline
-- wrapping before adding the multiline-specific styles.
C.STYLE_EDIT_MULTILINE = C.STYLE_EDIT - 0x80 + C.ES_MULTILINE + C.ES_AUTOVSCROLL + C.ES_WANTRETURN + C.WS_VSCROLL
C.STYLE_EDIT_READONLY = C.STYLE_EDIT + C.ES_READONLY
C.STYLE_EDIT_PASSWORD = C.STYLE_EDIT + C.ES_PASSWORD
C.STYLE_DEFAULT_BUTTON = C.STYLE_BUTTON + 1
C.STYLE_CHECKBOX = 0x50010003
C.STYLE_RADIO = 0x50010009
C.STYLE_GROUPBOX = 0x50000007
C.STYLE_COMBOBOX = 0x50210003
C.STYLE_LISTBOX = 0x50A10001
C.STYLE_PROGRESS = 0x50000000
C.STYLE_SLIDER = 0x50010001
C.STYLE_TAB = 0x50018000 + C.WS_CLIPSIBLINGS
C.TCS_BUTTONS = 0x0100
C.STYLE_TAB_BUTTONS = C.STYLE_TAB + C.TCS_BUTTONS
C.STYLE_LISTVIEW = 0x50810009
C.STYLE_TREEVIEW = 0x50810027
-- Explicit coordinates: CCS_NOMOVEY | CCS_NORESIZE | CCS_NOPARENTALIGN.
C.STYLE_STATUSBAR = 0x5000000E
C.WS_POPUP = 0x80000000
C.STYLE_TOOLTIP = 0x80000003
C.WS_EX_TOPMOST = 8

C.CF_SCREENFONTS = 1
C.CF_EFFECTS = 256

local gMainHwnd = nil
local gOldWndProc = nil
local gControlList = {}
local ControlPublicName = function(id) return id end
local gLabelStyles = {} -- Label ID -> {hwnd, color}; nil color uses the system default.
local gClickHandlers = {}
local gChangeHandlers = {}
local gSelectHandlers = {}
local gFontList = {}
local gDpiAutoFonts = {}
local gFontSpecs = {}
local gFontCreatedDpi = {}
local gDefaultFontSpec = nil
local gControlFontSpecs = {}
local gControlExternalFonts = {}
-- Internal DPI-adapted copies are reused while the same font is assigned to
-- the same control, avoiding one HFONT allocation per FontSet call.
local gControlAutoFonts = {}
-- Font handles reused when FontSizeSet changes a control during runtime.
local gSizedFontCache = {}
local gControlRects = {}
local gListViewColumnCounts = {}
local gListViewColumnWidths = {}
local gCurrentDpi = C.DEFAULT_DPI
local gTabPages = {}
-- Background of text controls must match the light tab page, not dialog gray.
local gTabPageControls = {} -- control ID -> tab ID
local gTextBackgroundControls = {} -- STATIC, checkbox, radio, groupbox
local gTabThemes = {} -- tab ID -> cached HTHEME for themed tab pane
local gMenuHandlers = {}
local GCloseHandler = nil
local GDropFilesHandler = nil
local gDropFilesHandlers = {}
local gDropTargets = {} -- registrations, indexed by HWND
local gDropObjects = {} -- strong roots until COM reference count reaches zero
local gDropCallbackDepth = 0
local gOleShutdownPending = false
local RescaleFontsForDpi
local ForgetDestroyedControl
local gDropTargetVTable = nil
local gDropComCallbacks = {}
local gOleDropInitialized = false
local gOleDropShouldUninitialize = false
local gTooltipHwnd = nil
local gTooltipTexts = {}
local GWndProcCallback = nil
-- A single rooted CBT callback is reused; each native hook is thread-local.
local gMessageBoxCenter = {stack = {}, pending = {}}
local GGroupBoxBackgroundCallback = nil
local gGroupBoxControls = {}
local gMenus = {}
local gAttachedMenu = nil
local gQuitPending = false
local gWindowLogicalSize = nil
local gUserResized = false
local gClosing = false
local gIconManager

local gInstanceHnd = kernel32.GetModuleHandleW(nil)

local function TrySetDpiContext(dpiContext)
    if hasSetProcessDpi and setProcessDpi(dpiContext) ~= 0 then
        return true
    end

    if hasGetThreadDpi and hasCompareDpi then
        local currentContext = getThreadDpi()
        if currentContext ~= nil and currentContext ~= ffi.NULL and compareDpi(currentContext, dpiContext) ~= 0 then
            return true
        end
    end

    if hasSetThreadDpi then
        local oldContext = setThreadDpi(dpiContext)
        if oldContext ~= nil and oldContext ~= ffi.NULL then
            return true
        end
    end

    return false
end

-- Awareness is established before creating a window, not as a require() side effect.
local gPerMonitorV2 = false

local gStockFontHnd = ffi.cast("HFONT", gdi32.GetStockObject(17))
local gDefaultFontHnd = gStockFontHnd

local commonControlsData = ffi.new("INITCOMMONCONTROLSEX[1]")
commonControlsData[0].dwSize = ffi.sizeof("INITCOMMONCONTROLSEX")
commonControlsData[0].dwICC = 0x000000FF

if comctl32.InitCommonControlsEx(commonControlsData) == 0 then
    comctl32.InitCommonControls()
end

local dialogErrors = require("_errors")
local dialogWin = require("_win_extension")
local function DialogFailure()
    local code = tonumber(comdlg32.CommDlgExtendedError())
    if code == 0 then return nil end
    local _, message = dialogErrors.Status("системный диалог", "Common Dialog", ("0x%08X"):format(code))
    return nil, message, code
end

local function IsNull(value)
    return value == nil or value == ffi.NULL
end

local function GetScreenDpi()
    local screenDc = user32.GetDC(nil)
    if IsNull(screenDc) then
        return C.DEFAULT_DPI
    end

    local dpiValue = tonumber(gdi32.GetDeviceCaps(screenDc, 88))
    user32.ReleaseDC(nil, screenDc)

    if dpiValue == nil or dpiValue <= 0 then
        return C.DEFAULT_DPI
    end

    return dpiValue
end

local function GetWindowDpiValue()
    if not IsNull(gMainHwnd) then return gCurrentDpi end
    if gCurrentDpi ~= nil and gCurrentDpi > 0 then
        return gCurrentDpi
    end

    return GetScreenDpi()
end

local function ScaleLogical(nValue, dpiValue)
    if nValue == nil then
        return 0
    end

    if type(nValue) ~= "number" or nValue ~= nValue or math.abs(nValue) > 10000000 then
        error("logical coordinate must be a finite number within +/-10000000", 2)
    end
    local scaled = nValue * (dpiValue or GetWindowDpiValue()) / C.DEFAULT_DPI
    return scaled < 0 and math.ceil(scaled - 0.5) or math.floor(scaled + 0.5)
end

local function FontHandleKey(fontHnd)
    if IsNull(fontHnd) then
        return nil
    end

    return tostring(ffi.cast("uintptr_t", fontHnd))
end

local function CopyFontSpec(specData)
    if specData == nil then
        return nil
    end

    return {
        name = specData.name,
        size = specData.size,
        bold = specData.bold,
        italic = specData.italic
    }
end

local function FontSpecCacheKey(specData)
    return table.concat({
        tostring(specData.name),
        tostring(specData.size),
        specData.bold and "1" or "0",
        specData.italic and "1" or "0"
    }, "\0")
end

local function ToWide(textValue)
    local textData = tostring(textValue or "")

    if textData:find("\0", 1, true) then error("text contains NUL character", 2) end
    if #textData == 0 then
        return ffi.new("WCHAR[1]", 0)
    end

    local wideLength = kernel32.MultiByteToWideChar(CP_UTF8, 8, textData, #textData, nil, 0)

    if wideLength <= 0 then
        error("invalid UTF-8 text", 2)
    end

    local wideData = ffi.new("WCHAR[?]", wideLength + 1)
    if kernel32.MultiByteToWideChar(CP_UTF8, 8, textData, #textData, wideData, wideLength) ~= wideLength then
        error("MultiByteToWideChar failed", 2)
    end
    wideData[wideLength] = 0

    return wideData
end

local function FromWide(wideData)
    if IsNull(wideData) then
        return ""
    end

    local byteLength = kernel32.WideCharToMultiByte(CP_UTF8, 128, wideData, -1, nil, 0, nil, nil)
    if byteLength == 0 then error("WideCharToMultiByte failed", 2) end

    if byteLength <= 1 then
        return ""
    end

    local textData = ffi.new("char[?]", byteLength)
    if kernel32.WideCharToMultiByte(CP_UTF8, 128, wideData, -1, textData, byteLength, nil, nil) ~= byteLength then
        error("WideCharToMultiByte failed", 2)
    end

    return ffi.string(textData, byteLength - 1)
end

local function PtrToWParam(ptrValue)
    return ffi.cast("WPARAM", ffi.cast("uintptr_t", ptrValue))
end

local function PtrToLParam(ptrValue)
    return ffi.cast("LPARAM", ffi.cast("intptr_t", ptrValue))
end

local function LResultToPtr(typeName, resultValue)
    return ffi.cast(typeName, ffi.cast("intptr_t", resultValue))
end

local function SignedNotifyCode(codeValue)
    local codeNumber = tonumber(codeValue)

    if codeNumber >= 2147483648 then
        codeNumber = codeNumber - 4294967296
    end

    return codeNumber
end

local function IsEnabledFlag(flagValue)
    return flagValue == true or (type(flagValue) == "number" and flagValue ~= 0)
end

local function ValidateControlId(IdValue, requireUnused)
    if type(IdValue) ~= "number" then
        return nil, "control ID must be a number"
    end

    if IdValue ~= IdValue or IdValue == math.huge or IdValue == -math.huge then
        return nil, "control ID must be a finite integer"
    end

    if IdValue ~= math.floor(IdValue) then
        return nil, "control ID must be an integer"
    end

    if IdValue < 1 or IdValue > 65535 then
        return nil, "control ID must be in range 1..65535"
    end

    if requireUnused and gControlList[IdValue] ~= nil then
        return nil, "control ID already exists: " .. tostring(IdValue)
    end

    return true
end

-- Never let an error reporter unwind through a native callback.
local function SafeErrorText(value)
    local ok, text = pcall(tostring, value)
    return ok and text or "Не удалось преобразовать объект ошибки в строку"
end
local guiErrorHandler, guiReporting, guiLastError
local guiErrorCount = 0
local function ReportGuiError(message, context)
    message = SafeErrorText(message):gsub('%s+$', '')
    guiErrorCount = guiErrorCount + 1
    guiLastError = {message=message, context=context or 'GUI', sequence=guiErrorCount}
    if guiErrorHandler and not guiReporting then
        guiReporting = true
        local ok, err = pcall(guiErrorHandler, message, guiLastError.context)
        guiReporting = false
        if not ok then
            if not guiLastError then
                guiLastError = {message=message, context=context or 'GUI', sequence=guiErrorCount}
            end
            guiLastError.reporter_error = SafeErrorText(err)
        end
    end
end
local function ErrorHandlerSet(handler)
    if handler ~= nil and type(handler) ~= 'function' then
        return nil, 'ErrorHandlerSet: требуется функция или nil'
    end
    guiErrorHandler = handler
    return true
end
local function ErrorGet(clear)
    local result = guiLastError
    if clear then guiLastError = nil end
    if result then return result.message, result.context, result.sequence, result.reporter_error end
end

local function CallHandler(handlerValue, idValue)
    local targetHandler = handlerValue

    if type(targetHandler) == "string" then
        targetHandler = _G[targetHandler]

        if type(targetHandler) ~= "function" then
            ReportGuiError("GUI handler not found: " .. SafeErrorText(handlerValue) .. "\n")
            return 0
        end
    elseif type(targetHandler) ~= "function" then
        ReportGuiError("GUI handler must be a function or global function name\n")
        return 0
    end

    local okValue, errorText = pcall(targetHandler, idValue)

    if not okValue then
        ReportGuiError("GUI handler error: " .. SafeErrorText(errorText) .. "\n")
        return 0
    end

    return 1
end

local function CallCloseHandler(HandlerValue)
    local TargetHandler = HandlerValue
    if type(TargetHandler) == "string" then
        TargetHandler = _G[TargetHandler]
        if type(TargetHandler) ~= "function" then
            ReportGuiError("GUI handler not found: " .. SafeErrorText(HandlerValue) .. "\n")
            return true
        end
    elseif type(TargetHandler) ~= "function" then
        ReportGuiError("GUI handler must be a function or global function name\n")
        return true
    end
    local okValue, resultValue = pcall(TargetHandler, 0)
    if not okValue then
        ReportGuiError("GUI handler error: " .. SafeErrorText(resultValue) .. "\n")
        return true
    end
    return resultValue ~= false
end

local function CallDropFilesHandler(HandlerValue, pathList)
    local TargetHandler = HandlerValue

    if type(TargetHandler) == "string" then
        TargetHandler = _G[TargetHandler]

        if type(TargetHandler) ~= "function" then
            ReportGuiError("GUI drop handler not found: " .. SafeErrorText(HandlerValue) .. "\n")
            return 0
        end
    elseif type(TargetHandler) ~= "function" then
        ReportGuiError("GUI drop handler must be a function or global function name\n")
        return 0
    end

    local okValue, errorText = pcall(TargetHandler, pathList)

    if not okValue then
        ReportGuiError("GUI drop handler error: " .. SafeErrorText(errorText) .. "\n")
        return 0
    end

    return 1
end

local function ReadDropPaths(dropHnd)
    local pathList = {}
    local fileCount = tonumber(shell32.DragQueryFileW(dropHnd, 0xFFFFFFFF, nil, 0))

    for fileIndex = 0, fileCount - 1 do
        local pathLength = tonumber(shell32.DragQueryFileW(dropHnd, fileIndex, nil, 0))
        local pathWide = ffi.new("WCHAR[?]", pathLength + 1)
        local copiedLength = tonumber(shell32.DragQueryFileW(dropHnd, fileIndex, pathWide, pathLength + 1))

        if pathLength == 0 or copiedLength ~= pathLength then error("DragQueryFileW failed") end
        pathList[#pathList + 1] = FromWide(pathWide)
    end

    return pathList
end

local function MakeDropFormat()
    local formatData = ffi.new("FORMATETC[1]")
    formatData[0].cfFormat = C.CF_HDROP
    formatData[0].ptd = nil
    formatData[0].dwAspect = C.DVASPECT_CONTENT
    formatData[0].lindex = -1
    formatData[0].tymed = C.TYMED_HGLOBAL
    return formatData
end

local function DataObjectSupportsFiles(dataObjectPtr)
    if IsNull(dataObjectPtr) then
        return false
    end

    local formatData = MakeDropFormat()
    local QueryMethod = dataObjectPtr[0].lpVtbl[0].QueryGetData

    if QueryMethod == nil then
        return false
    end

    return tonumber(QueryMethod(dataObjectPtr, formatData)) == C.S_OK
end

local function ReadDataObjectPaths(dataObjectPtr)
    local pathList = {}

    if IsNull(dataObjectPtr) then
        return pathList
    end

    local formatData = MakeDropFormat()
    local mediumData = ffi.new("STGMEDIUM[1]")
    local GetDataMethod = dataObjectPtr[0].lpVtbl[0].GetData

    if GetDataMethod == nil then
        return pathList
    end

    local resultValue = tonumber(GetDataMethod(dataObjectPtr, formatData, mediumData))

    if resultValue < 0 then
        return pathList
    end

    local okValue, readResult = pcall(function()
        if tonumber(mediumData[0].tymed) ~= C.TYMED_HGLOBAL or IsNull(mediumData[0].u.hGlobal) then
            return {}
        end

        return ReadDropPaths(ffi.cast("HDROP", mediumData[0].u.hGlobal))
    end)

    ole32.ReleaseStgMedium(mediumData)

    if not okValue then
        ReportGuiError("GUI drop data error: " .. SafeErrorText(readResult) .. "\n")
        return pathList
    end

    return readResult
end

local function GuidMatches(guidPtr, data1Value)
    if guidPtr == nil then
        return false
    end

    local guidValue = guidPtr[0]

    if tonumber(guidValue.Data1) ~= data1Value or tonumber(guidValue.Data2) ~= 0 or tonumber(guidValue.Data3) ~= 0 then
        return false
    end

    return tonumber(guidValue.Data4[0]) == 0xC0
        and tonumber(guidValue.Data4[1]) == 0
        and tonumber(guidValue.Data4[2]) == 0
        and tonumber(guidValue.Data4[3]) == 0
        and tonumber(guidValue.Data4[4]) == 0
        and tonumber(guidValue.Data4[5]) == 0
        and tonumber(guidValue.Data4[6]) == 0
        and tonumber(guidValue.Data4[7]) == 0x46
end

local function DropTargetKey(hwndValue)
    return tostring(ffi.cast("uintptr_t", hwndValue))
end

local function GetDropHandlerForTarget(targetPtr)
    local record = gDropTargets[DropTargetKey(targetPtr[0].hwnd)]
    if not record or ffi.cast("LuaDropTarget*", record.data) ~= targetPtr or
        user32.IsWindowEnabled(targetPtr[0].hwnd) == 0 then return nil end
    if targetPtr[0].isMain ~= 0 then
        return GDropFilesHandler
    end

    local controlId = tonumber(targetPtr[0].controlId)
    local override = gDropFilesHandlers[controlId]
    if override ~= nil then return override or nil end
    return GDropFilesHandler
end

local function SetDropEffect(effectPtr, allowCopy, keyState)
    if effectPtr == nil then
        return false
    end

    local sourceEffects = tonumber(effectPtr[0])
    ---@cast sourceEffects integer

    -- This API delivers paths; it never moves/deletes source files or creates links.
    -- Explicit Shift/Alt requests cannot be honored as copy operations.
    local unsupportedModifier = bit.band(tonumber(keyState or 0) --[[@as integer]], 4 + 32) ~= 0
    if allowCopy and not unsupportedModifier and bit.band(sourceEffects, C.DROPEFFECT_COPY) ~= 0 then
        effectPtr[0] = C.DROPEFFECT_COPY
        return true
    end

    effectPtr[0] = C.DROPEFFECT_NONE
    return false
end

local function EnsureOleDropInitialized()
    if gOleDropInitialized then
        return true
    end

    local resultValue = tonumber(ole32.OleInitialize(nil))

    if resultValue < 0 then
        return nil, "OleInitialize failed for drag-and-drop (HRESULT " .. tostring(resultValue) .. ")"
    end

    gOleDropInitialized = true
    gOleDropShouldUninitialize = true
    return true
end

local function DropQueryInterfaceBody(selfPtr, iidPtr, objectPtr)
    if objectPtr == nil then
        return C.E_POINTER
    end

    objectPtr[0] = nil

    if GuidMatches(iidPtr, 0) or GuidMatches(iidPtr, 0x00000122) then
        objectPtr[0] = ffi.cast("void*", selfPtr)
        local targetPtr = ffi.cast("LuaDropTarget*", selfPtr)
        targetPtr[0].refCount = targetPtr[0].refCount + 1
        return C.S_OK
    end

    return C.E_NOINTERFACE
end

local function DropAddRefBody(selfPtr)
    local targetPtr = ffi.cast("LuaDropTarget*", selfPtr)
    targetPtr[0].refCount = targetPtr[0].refCount + 1
    return tonumber(targetPtr[0].refCount)
end

local function DropReleaseBody(selfPtr)
    local targetPtr = ffi.cast("LuaDropTarget*", selfPtr)

    if targetPtr[0].refCount > 0 then
        targetPtr[0].refCount = targetPtr[0].refCount - 1
    end

    local count = tonumber(targetPtr[0].refCount)
    if count == 0 then gDropObjects[DropTargetKey(selfPtr)] = nil end
    return count
end

local function DropDragEnterBody(selfPtr, dataObjectPtr, keyState, pointValue, effectPtr)
    if effectPtr == nil then
        return C.E_POINTER
    end

    local targetPtr = ffi.cast("LuaDropTarget*", selfPtr)
    local TargetHandler = GetDropHandlerForTarget(targetPtr)
    local canDrop = TargetHandler ~= nil and DataObjectSupportsFiles(dataObjectPtr)

    targetPtr[0].canDrop = canDrop and 1 or 0
    SetDropEffect(effectPtr, canDrop, keyState)
    return C.S_OK
end

local function DropDragOverBody(selfPtr, keyState, pointValue, effectPtr)
    if effectPtr == nil then
        return C.E_POINTER
    end

    local targetPtr = ffi.cast("LuaDropTarget*", selfPtr)
    local TargetHandler = GetDropHandlerForTarget(targetPtr)
    local canDrop = targetPtr[0].canDrop ~= 0 and TargetHandler ~= nil

    SetDropEffect(effectPtr, canDrop, keyState)
    return C.S_OK
end

local function DropDragLeaveBody(selfPtr)
    ffi.cast("LuaDropTarget*", selfPtr)[0].canDrop = 0
    return C.S_OK
end

local function DropDropBody(selfPtr, dataObjectPtr, keyState, pointValue, effectPtr)
    if effectPtr == nil then
        return C.E_POINTER
    end

    local targetPtr = ffi.cast("LuaDropTarget*", selfPtr)
    local TargetHandler = GetDropHandlerForTarget(targetPtr)
    local canDrop = TargetHandler ~= nil and DataObjectSupportsFiles(dataObjectPtr)
    targetPtr[0].canDrop = 0

    if not canDrop or not SetDropEffect(effectPtr, true, keyState) then
        effectPtr[0] = C.DROPEFFECT_NONE
        return C.S_OK
    end

    local pathList = ReadDataObjectPaths(dataObjectPtr)

    if #pathList == 0 or CallDropFilesHandler(TargetHandler, pathList) == 0 then
        effectPtr[0] = C.DROPEFFECT_NONE
        return C.S_OK
    end

    effectPtr[0] = C.DROPEFFECT_COPY
    return C.S_OK
end

local function SafeDropCallback(callbackName, CallbackBody, ...)
    gDropCallbackDepth = gDropCallbackDepth + 1
    local ok, result = pcall(CallbackBody, ...)
    gDropCallbackDepth = gDropCallbackDepth - 1
    if ok then return result end
    -- Never report successful negotiation after an exception.
    if callbackName == "DragEnter" or callbackName == "Drop" then
        local effect = select(5, ...)
        if not IsNull(effect) then effect[0] = C.DROPEFFECT_NONE end
    elseif callbackName == "DragOver" then
        local effect = select(4, ...)
        if not IsNull(effect) then effect[0] = C.DROPEFFECT_NONE end
    end
    ReportGuiError("GUI " .. callbackName .. " error: " .. SafeErrorText(result) .. "\n")
    return -2147418113 -- E_UNEXPECTED
end

gDropComCallbacks.QueryInterface = ffi.cast(
    "HRESULT (__stdcall *)(IDropTarget*, const GUID*, void**)",
    function(selfPtr, iidPtr, objectPtr)
        return SafeDropCallback("QueryInterface", DropQueryInterfaceBody, selfPtr, iidPtr, objectPtr)
    end
)

gDropComCallbacks.AddRef = ffi.cast(
    "ULONG (__stdcall *)(IDropTarget*)",
    function(selfPtr)
        local okValue, resultValue = pcall(DropAddRefBody, selfPtr)
        if okValue then return resultValue end
        ReportGuiError("GUI AddRef error: " .. SafeErrorText(resultValue) .. "\n")
        return 1
    end
)

gDropComCallbacks.Release = ffi.cast(
    "ULONG (__stdcall *)(IDropTarget*)",
    function(selfPtr)
        local okValue, resultValue = pcall(DropReleaseBody, selfPtr)
        if okValue then return resultValue end
        ReportGuiError("GUI Release error: " .. SafeErrorText(resultValue) .. "\n")
        return 1
    end
)

gDropComCallbacks.DragEnter = ffi.cast(
    "HRESULT (__stdcall *)(IDropTarget*, IDataObject*, DWORD, int64_t, DWORD*)",
    function(selfPtr, dataObjectPtr, keyState, pointValue, effectPtr)
        return SafeDropCallback("DragEnter", DropDragEnterBody, selfPtr, dataObjectPtr, keyState, pointValue, effectPtr)
    end
)

gDropComCallbacks.DragOver = ffi.cast(
    "HRESULT (__stdcall *)(IDropTarget*, DWORD, int64_t, DWORD*)",
    function(selfPtr, keyState, pointValue, effectPtr)
        return SafeDropCallback("DragOver", DropDragOverBody, selfPtr, keyState, pointValue, effectPtr)
    end
)

gDropComCallbacks.DragLeave = ffi.cast(
    "HRESULT (__stdcall *)(IDropTarget*)",
    function(selfPtr)
        return SafeDropCallback("DragLeave", DropDragLeaveBody, selfPtr)
    end
)

gDropComCallbacks.Drop = ffi.cast(
    "HRESULT (__stdcall *)(IDropTarget*, IDataObject*, DWORD, int64_t, DWORD*)",
    function(selfPtr, dataObjectPtr, keyState, pointValue, effectPtr)
        return SafeDropCallback("Drop", DropDropBody, selfPtr, dataObjectPtr, keyState, pointValue, effectPtr)
    end
)

gDropTargetVTable = ffi.new("IDropTargetVtbl[1]")
gDropTargetVTable[0].QueryInterface = gDropComCallbacks.QueryInterface
gDropTargetVTable[0].AddRef = gDropComCallbacks.AddRef
gDropTargetVTable[0].Release = gDropComCallbacks.Release
gDropTargetVTable[0].DragEnter = gDropComCallbacks.DragEnter
gDropTargetVTable[0].DragOver = gDropComCallbacks.DragOver
gDropTargetVTable[0].DragLeave = gDropComCallbacks.DragLeave
gDropTargetVTable[0].Drop = gDropComCallbacks.Drop

local function RegisterDropTarget(hwndValue, ControlId, isMainTarget)
    if IsNull(hwndValue) then
        return nil, "drop target window is not available"
    end

    local initOk, initError = EnsureOleDropInitialized()
    if not initOk then
        return nil, initError
    end

    local targetKey = DropTargetKey(hwndValue)
    local existingTarget = gDropTargets[targetKey]

    if existingTarget ~= nil then
        existingTarget.data[0].controlId = ControlId or 0
        existingTarget.data[0].isMain = isMainTarget and 1 or 0
        return true
    end

    local targetData = ffi.new("LuaDropTarget[1]")
    targetData[0].lpVtbl = gDropTargetVTable
    targetData[0].refCount = 1
    targetData[0].hwnd = hwndValue
    targetData[0].controlId = ControlId or 0
    targetData[0].isMain = isMainTarget and 1 or 0
    targetData[0].canDrop = 0

    local objectKey = DropTargetKey(targetData)
    gDropObjects[objectKey] = targetData
    local resultValue = tonumber(ole32.RegisterDragDrop(hwndValue, ffi.cast("IDropTarget*", targetData)))

    if resultValue < 0 then
        DropReleaseBody(ffi.cast("IDropTarget*", targetData))
        return nil, "RegisterDragDrop failed (HRESULT " .. tostring(resultValue) .. ")"
    end

    gDropTargets[targetKey] = {data = targetData, hwnd = hwndValue}
    return true
end

local function UnregisterDropTarget(hwndValue)
    if IsNull(hwndValue) then
        return true
    end

    local targetKey = DropTargetKey(hwndValue)
    if gDropTargets[targetKey] == nil then
        return true
    end

    local record = gDropTargets[targetKey]
    local resultValue = tonumber(ole32.RevokeDragDrop(hwndValue))
    -- If the child HWND was destroyed by its owner, USER32/OLE may already
    -- have discarded the registration and RevokeDragDrop reports either
    -- DRAGDROP_E_NOTREGISTERED or DRAGDROP_E_INVALIDHWND.  Both are terminal
    -- for this record; retaining it would make the parent window impossible
    -- to close and would keep the COM root alive forever.
    if resultValue < 0 and resultValue ~= -2147221248 and resultValue ~= -2147221246 then
        return nil, "RevokeDragDrop failed (HRESULT " .. tostring(resultValue) .. ")"
    end
    gDropTargets[targetKey] = nil
    record.data[0].canDrop = 0
    DropReleaseBody(ffi.cast("IDropTarget*", record.data)) -- release our initial reference
    return true
end

local function UnregisterAllDropTargets()
    local targetList = {}

    for _, targetInfo in pairs(gDropTargets) do
        targetList[#targetList + 1] = targetInfo.hwnd
    end

    local firstError
    for indexValue = 1, #targetList do
        local ok, err = UnregisterDropTarget(targetList[indexValue])
        if not ok then firstError = firstError or err end
    end
    if firstError then return nil, firstError end
    return true
end

local function SyncDropTargets()
    if IsNull(gMainHwnd) then
        return true
    end

    if GDropFilesHandler ~= nil then
        local okValue, errorText = RegisterDropTarget(gMainHwnd, 0, true)
        if not okValue then return nil, errorText end
    else
        local okValue, errorText = UnregisterDropTarget(gMainHwnd)
        if not okValue then return nil, errorText end
    end

    for controlId, controlHwnd in pairs(gControlList) do
        if gDropFilesHandlers[controlId] ~= nil or GDropFilesHandler ~= nil then
            local okValue, errorText = RegisterDropTarget(controlHwnd, controlId, false)
            if not okValue then return nil, errorText end
        else
            local okValue, errorText = UnregisterDropTarget(controlHwnd)
            if not okValue then return nil, errorText end
        end
    end

    return true
end

local function ShutdownOleDrop()
    local ok, err = UnregisterAllDropTargets()
    if not ok then return nil, err end
    if gDropCallbackDepth > 0 then
        gOleShutdownPending = true
        return true
    end
    if gOleDropShouldUninitialize then ole32.OleUninitialize() end
    gOleDropInitialized = false
    gOleDropShouldUninitialize = false
    gOleShutdownPending = false
    return true
end

-- Windows theme handles must be closed when the window/theme changes.
local function ReleaseTabThemes()
    for id, themeHnd in pairs(gTabThemes) do
        uxtheme.CloseThemeData(themeHnd)
        gTabThemes[id] = nil
    end
end

-- Draw the *actual TABP_PANE surface* at the same coordinates as the tab.
-- Unlike a guessed COLOR_WINDOW brush, this also handles themed page colors
-- and gradient backgrounds, and fully redraws behind changing label text.
local function PaintTabBackground(tabId, tabHwnd, controlHwnd, targetDc)
    if uxtheme.IsThemeActive() == 0 then return false end
    local themeHnd = gTabThemes[tabId]
    if IsNull(themeHnd) then
        themeHnd = uxtheme.OpenThemeData(tabHwnd, ToWide("TAB"))
        if IsNull(themeHnd) then return false end
        gTabThemes[tabId] = themeHnd
    end
    local tabBounds, controlBounds, pane = ffi.new("RECT[1]"), ffi.new("RECT[1]"), ffi.new("RECT[1]")
    if user32.GetWindowRect(tabHwnd, tabBounds) == 0 or
       user32.GetWindowRect(controlHwnd, controlBounds) == 0 or
       user32.GetClientRect(tabHwnd, pane) == 0 then
        return false
    end
    -- This determines where the themed *page*, not its tab headers, begins.
    user32.SendMessageW(tabHwnd, C.TCM_ADJUSTRECT, 0, PtrToLParam(pane))
    local inset = math.max(2, ScaleLogical(3, gCurrentDpi))
    local dx = tabBounds[0].left - controlBounds[0].left
    local dy = tabBounds[0].top - controlBounds[0].top
    pane[0].left = pane[0].left + dx - inset
    pane[0].top = pane[0].top + dy - inset
    pane[0].right = pane[0].right + dx + inset
    pane[0].bottom = pane[0].bottom + dy + inset
    -- An explicit light base also covers transparent regions of the theme part.
    local childRect = ffi.new("RECT[1]")
    if user32.GetClientRect(controlHwnd, childRect) == 0 then return false end
    -- WM_CTLCOLOR can supply a DC whose clip extends beyond this child.
    -- TABP_PANE spans the whole page: restrict it before drawing so repainting
    -- one label/groupbox cannot erase neighbouring controls. Restore the DC
    -- before the native control continues painting its text and border.
    local savedDc = gdi32.SaveDC(targetDc)
    if savedDc == 0 then return false end
    if gdi32.IntersectClipRect(targetDc, childRect[0].left, childRect[0].top,
                             childRect[0].right, childRect[0].bottom) == 0 then
        gdi32.RestoreDC(targetDc, savedDc)
        return false
    end
    user32.FillRect(targetDc, childRect, user32.GetSysColorBrush(C.COLOR_WINDOW))
    local result = uxtheme.DrawThemeBackground(themeHnd, targetDc, C.TABP_PANE, 0, pane, nil)
    gdi32.RestoreDC(targetDc, savedDc)
    return tonumber(result) >= 0
end

-- The themed BS_GROUPBOX control can ignore WM_CTLCOLORSTATIC.
-- To paint the background behind its caption it asks its parent to draw
-- through DrawThemeParentBackground (WM_ERASEBKGND / WM_PRINTCLIENT).
-- Recreate both the dialog surface and the page surfaces in *parent*
-- coordinates.  This avoids the old COLOR_BTNFACE rectangle under GroupBox.
local function PaintDialogAndTabPages(targetDc)
    if IsNull(gMainHwnd) or IsNull(targetDc) then return false end
    local clientRect = ffi.new("RECT[1]")
    if user32.GetClientRect(gMainHwnd, clientRect) == 0 then return false end
    user32.FillRect(targetDc, clientRect, user32.GetSysColorBrush(C.COLOR_BTNFACE))

    if uxtheme.IsThemeActive() == 0 then return true end
    local parentOrigin = ffi.new("POINT[1]")
    if user32.ClientToScreen(gMainHwnd, parentOrigin) == 0 then return true end

    for tabId in pairs(gTabPages) do
        local tabHwnd = gControlList[tabId]
        if not IsNull(tabHwnd) and user32.IsWindow(tabHwnd) ~= 0 then
            local themeHnd = gTabThemes[tabId]
            if IsNull(themeHnd) then
                themeHnd = uxtheme.OpenThemeData(tabHwnd, ToWide("TAB"))
                if not IsNull(themeHnd) then gTabThemes[tabId] = themeHnd end
            end
            if not IsNull(themeHnd) then
                local tabRect = ffi.new("RECT[1]")
                local tabOrigin = ffi.new("POINT[1]")
                if user32.GetClientRect(tabHwnd, tabRect) ~= 0 and
                    user32.ClientToScreen(tabHwnd, tabOrigin) ~= 0 then
                    user32.SendMessageW(tabHwnd, C.TCM_ADJUSTRECT, 0, PtrToLParam(tabRect))
                    local inset = math.max(2, ScaleLogical(3, gCurrentDpi))
                    local dx = tabOrigin[0].x - parentOrigin[0].x
                    local dy = tabOrigin[0].y - parentOrigin[0].y
                    tabRect[0].left = tabRect[0].left + dx - inset
                    tabRect[0].top = tabRect[0].top + dy - inset
                    tabRect[0].right = tabRect[0].right + dx + inset
                    tabRect[0].bottom = tabRect[0].bottom + dy + inset
                    uxtheme.DrawThemeBackground(themeHnd, targetDc, C.TABP_PANE, 0, tabRect, nil)
                end
            end
        end
    end
    return true
end

-- WS_CLIPCHILDREN excludes the entire GroupBox from the parent's paint DC.
-- BS_GROUPBOX does not erase its interior itself, so restore can expose black
-- pixels. Erase on the child's DC before native border/caption painting.
GGroupBoxBackgroundCallback = ffi.cast("GUI_GROUP_SUBCLASSPROC", function(hwnd, msg, wp, lp, subclassId, controlId)
    if msg == 0x0082 then -- WM_NCDESTROY: detach while the shared callback remains rooted.
        comctl32.RemoveWindowSubclass(hwnd, GGroupBoxBackgroundCallback, subclassId)
        if gGroupBoxControls[tonumber(controlId)] == hwnd then gGroupBoxControls[tonumber(controlId)] = nil end
        return comctl32.DefSubclassProc(hwnd, msg, wp, lp)
    end
    if msg == C.WM_ERASEBKGND then
        local ok, painted = pcall(function()
            local hdc = ffi.cast("HDC", wp)
            if IsNull(hdc) then return false end
            local rect, bounds = ffi.new("RECT[1]"), ffi.new("RECT[1]")
            if user32.GetClientRect(hwnd, rect) == 0 or user32.GetWindowRect(hwnd, bounds) == 0 then return false end
            local savedDc = gdi32.SaveDC(hdc)
            if savedDc == 0 then return false end
            local drawnOk, result = pcall(function()
                gdi32.IntersectClipRect(hdc, rect[0].left, rect[0].top, rect[0].right, rect[0].bottom)
                -- Erase/print DCs need not carry the normal sibling clip.
                -- GroupBox frames overlap sibling labels, edits and buttons.
                local sibling = user32.GetWindow(hwnd, 3) -- GW_HWNDPREV: only siblings above this frame.
                local siblingRect = ffi.new("RECT[1]")
                while not IsNull(sibling) do
                    if user32.IsWindowVisible(sibling) ~= 0 and user32.GetWindowRect(sibling, siblingRect) ~= 0 then
                        gdi32.ExcludeClipRect(hdc,
                            siblingRect[0].left - bounds[0].left, siblingRect[0].top - bounds[0].top,
                            siblingRect[0].right - bounds[0].left, siblingRect[0].bottom - bounds[0].top)
                    end
                    sibling = user32.GetWindow(sibling, 3)
                end
                local tabId = gTabPageControls[tonumber(controlId)]
                local tabHwnd = tabId and gControlList[tabId]
                if not IsNull(tabHwnd) and user32.IsWindow(tabHwnd) ~= 0 and
                   PaintTabBackground(tabId, tabHwnd, hwnd, hdc) then
                    return true
                end
                return user32.FillRect(hdc, rect, user32.GetSysColorBrush(C.COLOR_BTNFACE)) ~= 0
            end)
            gdi32.RestoreDC(hdc, savedDc)
            if not drawnOk then error(result) end
            return result
        end)
        if ok and painted then return 1 end
        if not ok then ReportGuiError("GroupBox background error: " .. SafeErrorText(painted) .. "\n") end
    end
    return comctl32.DefSubclassProc(hwnd, msg, wp, lp)
end)
function WideTextMake(cText)
    return ToWide(cText)
end

-- nil loads embedded EXE resource 1; a UTF-8 string loads an external ICO.
function IconSet(source)
    gIconManager = gIconManager or require('app_icon')
    return gIconManager.Set(gMainHwnd, source)
end

-- Sets the exact client-area size, accounting for the actual DPI,
-- current frame, title bar, and menu. Sizes use 96-DPI units.
local function FitWindowToClient(hwnd, logicalWidth, logicalHeight)
    local desiredW = ScaleLogical(logicalWidth, gCurrentDpi)
    local desiredH = ScaleLogical(logicalHeight, gCurrentDpi)
    local outer = ffi.new("RECT[1]")
    local client = ffi.new("RECT[1]")

    for attempt = 1, 4 do
        if user32.GetWindowRect(hwnd, outer) == 0 or user32.GetClientRect(hwnd, client) == 0 then
            return nil, "Failed to measure window and client areas"
        end

        local currentW = client[0].right - client[0].left
        local currentH = client[0].bottom - client[0].top
        if currentW == desiredW and currentH == desiredH then
            return true
        end

        -- Three corrections, followed by one final measurement.
        if attempt == 4 then break end

        local newW = outer[0].right - outer[0].left + desiredW - currentW
        local newH = outer[0].bottom - outer[0].top + desiredH - currentH
        if newW <= 0 or newH <= 0 then
            return nil, "Invalid outer window size for requested client area"
        end

        -- SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE
        if user32.SetWindowPos(hwnd, nil, 0, 0, newW, newH, 0x0016) == 0 then
            return nil, "SetWindowPos failed while setting client area"
        end
    end

    return nil, "Could not achieve the requested client area size"
end

-- Window(title, width, height, resizable, position)
-- position: "center" or "bottom-left". nil/false retains the default position.
-- Resize mode: "resizable" (default) or "fixed"; boolean resize flags are rejected.
-- Position still accepts center flags or absolute physical X,Y coordinates.
-- Window sizes use 96-DPI logical coordinates.
function Window(cTitle, nWidth, nHeight, resizable, position, nY, clientSize)
    if resizable == nil then resizable = "resizable" end
    if resizable ~= "resizable" and resizable ~= "fixed" then
        return nil, 'window resize mode must be "resizable" or "fixed"'
    end
    if gOleShutdownPending then
        if gDropCallbackDepth > 0 then return nil, "recreate the GUI after the drop callback returns" end
        local ok, err = ShutdownOleDrop()
        if not ok then return nil, err end
    end
    if not IsNull(gMainHwnd) then return nil, "GUI window already exists" end
    if type(nWidth) ~= "number" or type(nHeight) ~= "number" or nWidth <= 0 or nHeight <= 0 then
        return nil, "window dimensions must be positive numbers"
    end
    ScaleLogical(nWidth, 96); ScaleLogical(nHeight, 96)

    local positionX, positionY
    if nY ~= nil then
        if type(position) ~= "number" or type(nY) ~= "number" then
            return nil, "window coordinates X and Y must be numbers"
        end
        positionX = ScaleLogical(position, 96)
        positionY = ScaleLogical(nY, 96)
    elseif position == nil or position == false or position == 0 then
        position = "default" -- preserve the previous non-centered default
    elseif IsEnabledFlag(position) then
        position = "center"
    elseif position ~= "center" and position ~= "bottom-left" then
        return nil, 'window position must be "center", "bottom-left", a boolean, or X and Y'
    end

    gPerMonitorV2 = TrySetDpiContext(C.DPI_CONTEXT_PER_MONITOR_AWARE_V2)
    if not gPerMonitorV2 and not TrySetDpiContext(C.DPI_CONTEXT_PER_MONITOR_AWARE) then
        return nil, "Cannot establish per-monitor DPI awareness"
    end
    if not hasWindowDpi then return nil, "Windows 10 1607 or newer is required" end
    if gQuitPending then
        local message = ffi.new("MSG[1]")
        user32.PeekMessageW(message, nil, 0x12, 0x12, 1)
        gQuitPending = false
    end
    local titleWide = ToWide(cTitle)
    local classWide = ToWide("#32770")
    -- Background erasure must not draw over existing child windows.
    local windowStyle = bit.bor(C.WS_OVERLAPPEDWINDOW, C.WS_CLIPCHILDREN)

    if resizable == "fixed" then
        windowStyle = bit.band(windowStyle, bit.bnot(C.WS_THICKFRAME + C.WS_MAXIMIZEBOX))
    end

    gCurrentDpi = GetScreenDpi()

    local mainHwnd = user32.CreateWindowExW(
        0,
        classWide,
        titleWide,
        windowStyle,
        ScaleLogical(100, gCurrentDpi),
        ScaleLogical(100, gCurrentDpi),
        ScaleLogical(nWidth, gCurrentDpi),
        ScaleLogical(nHeight, gCurrentDpi),
        nil,
        nil,
        gInstanceHnd,
        nil
    )

    if IsNull(mainHwnd) then
        return nil, "CreateWindowExW failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")"
    end

    gMainHwnd = mainHwnd
    gWindowLogicalSize = {width = nWidth, height = nHeight, client = clientSize == true}
    if hasDialogDpi and setDialogDpi(mainHwnd, 1, 1) == 0 then
        user32.DestroyWindow(mainHwnd); gMainHwnd = nil
        return nil, "SetDialogDpiChangeBehavior failed"
    end

    if hasWindowDpi then
        local actualDpi = tonumber(getWindowDpi(gMainHwnd))
        if actualDpi ~= nil and actualDpi > 0 then
            gCurrentDpi = actualDpi
        end
    end

    kernel32.SetLastError(0)
    local oldProcValue = user32.SetWindowLongPtrW(
        gMainHwnd,
        C.GWLP_WNDPROC,
        ffi.cast("LONG_PTR", GWndProcCallback)
    )

    if oldProcValue == 0 and kernel32.GetLastError() ~= 0 then
        local err = "SetWindowLongPtrW failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")"
        user32.DestroyWindow(gMainHwnd)
        gMainHwnd = nil
        return nil, err
    end

    gOldWndProc = oldProcValue ~= 0 and ffi.cast("WNDPROC", oldProcValue) or nil
    if clientSize == true then
        local fitOk, fitError = FitWindowToClient(mainHwnd, nWidth, nHeight)
        if not fitOk then
            user32.DestroyWindow(mainHwnd)
            return nil, fitError
        end
    elseif user32.SetWindowPos(mainHwnd, nil, 0, 0, ScaleLogical(nWidth), ScaleLogical(nHeight), 0x16) == 0 then
        user32.DestroyWindow(mainHwnd)
        return nil, "SetWindowPos failed"
    end

    if not gDefaultFontSpec then
        gDefaultFontSpec = {name = "Segoe UI", size = 9, bold = false, italic = false}
    end
    local fontOk, fontError = RescaleFontsForDpi()
    if not fontOk then user32.DestroyWindow(gMainHwnd); return nil, fontError end

    if positionX ~= nil then
        if user32.SetWindowPos(gMainHwnd, nil, positionX, positionY, 0, 0, 0x0015) == 0 then
            user32.DestroyWindow(gMainHwnd)
            return nil, "Failed to position GUI window"
        end
    elseif position ~= "default" then
        -- Work area already excludes the taskbar, irrespective of its edge.
        -- Use the real outer dimensions after fitting the client area.
        local isBottomLeft = position == "bottom-left"
        local monitorHnd = isBottomLeft
            and user32.MonitorFromWindow(nil, 1) -- MONITOR_DEFAULTTOPRIMARY
            or user32.MonitorFromWindow(gMainHwnd, 2) -- MONITOR_DEFAULTTONEAREST
        local monitorInfo = ffi.new("MONITORINFO[1]")
        monitorInfo[0].cbSize = ffi.sizeof("MONITORINFO")
        local windowRect = ffi.new("RECT[1]")

        if IsNull(monitorHnd)
            or user32.GetMonitorInfoW(monitorHnd, monitorInfo) == 0
            or user32.GetWindowRect(gMainHwnd, windowRect) == 0 then
            user32.DestroyWindow(gMainHwnd)
            return nil, "Failed to calculate GUI window position"
        end

        local workArea = monitorInfo[0].rcWork
        local widthPx = windowRect[0].right - windowRect[0].left
        local heightPx = windowRect[0].bottom - windowRect[0].top
        local x, y

        if isBottomLeft then
            if widthPx > workArea.right - workArea.left or heightPx > workArea.bottom - workArea.top then
                user32.DestroyWindow(gMainHwnd)
                return nil, "GUI window is larger than the monitor work area"
            end
            x = tonumber(workArea.left)
            y = tonumber(workArea.bottom - heightPx)
        else
            x = math.floor((workArea.left + workArea.right - widthPx) / 2)
            y = math.floor((workArea.top + workArea.bottom - heightPx) / 2)
        end

        -- SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE; before ShowWindow.
        if user32.SetWindowPos(gMainHwnd, nil, x, y, 0, 0, 0x0015) == 0 then
            user32.DestroyWindow(gMainHwnd)
            return nil, "Failed to position GUI window"
        end
    end

    local dropOk, dropError = SyncDropTargets()
    if not dropOk then user32.DestroyWindow(gMainHwnd); return nil, dropError end

    user32.ShowWindow(gMainHwnd, C.SW_SHOW)
    user32.UpdateWindow(gMainHwnd)

    return gMainHwnd
end

-- WindowClient(title, width, height, resizable, position)
-- position: "center" or "bottom-left"; legacy center and x,y are also supported.
-- Width and height describe the client area used for control coordinates.
function WindowClient(cTitle, nWidth, nHeight, resizable, position, nY)
    return Window(cTitle, nWidth, nHeight, resizable, position, nY, true)
end

-- Desktop dimensions are returned in physical pixels, independent of scaling.
-- As in Window(), establish Per-Monitor DPI awareness before querying metrics.
local function EnsureScreenDpiAwareness()
    if not IsNull(gMainHwnd) then return true end
    if TrySetDpiContext(C.DPI_CONTEXT_PER_MONITOR_AWARE_V2) or
       TrySetDpiContext(C.DPI_CONTEXT_PER_MONITOR_AWARE) then
        return true
    end
    return nil, "Cannot establish per-monitor DPI awareness"
end

-- ScreenSizeGet() -> width, height (primary monitor, physical pixels).
function ScreenSizeGet()
    local ok, err = EnsureScreenDpiAwareness()
    if not ok then return nil, err end
    return tonumber(user32.GetSystemMetrics(0)), tonumber(user32.GetSystemMetrics(1))
end

-- TaskbarHeightGet() -> taskbar thickness in the vertical direction.
-- If the taskbar is attached to the left/right edge, it takes no vertical space.
-- The height is its actual size, including when auto-hide is enabled.
function TaskbarHeightGet()
    local ok, err = EnsureScreenDpiAwareness()
    if not ok then return nil, err end

    local data = ffi.new("APPBARDATA[1]")
    data[0].cbSize = ffi.sizeof("APPBARDATA")
    if shell32.SHAppBarMessage(5, data) == 0 then -- ABM_GETTASKBARPOS
        return nil, "Cannot determine the Windows taskbar position"
    end
    if data[0].uEdge == 1 or data[0].uEdge == 3 then -- ABE_TOP, ABE_BOTTOM
        return tonumber(data[0].rc.bottom - data[0].rc.top)
    end
    return 0 -- ABE_LEFT, ABE_RIGHT
end

-- ScreenInfoGet() -> screenWidth, screenHeight, taskbarHeight.
function ScreenInfoGet()
    local width, height = ScreenSizeGet()
    if not width then return nil, height end
    local taskbarHeight, err = TaskbarHeightGet()
    if taskbarHeight == nil then return nil, err end
    return width, height, taskbarHeight
end

function ControlCreate(nId, cClassName, cText, nStyle, nX, nY, nWidth, nHeight)
    if IsNull(gMainHwnd) then
        return nil, "GUI window is not created"
    end
    if type(nId) ~= "number" or nId ~= math.floor(nId) or nId < 1 or nId > 65535 then
        return nil, "control ID must be an integer from 1 to 65535"
    end
    if gControlList[nId] ~= nil then
        return nil, "control ID is already in use"
    end

    if type(nWidth) ~= "number" or type(nHeight) ~= "number" or nWidth < 0 or nHeight < 0 then
        return nil, "control dimensions must be nonnegative numbers"
    end
    local isGroupBox = cClassName == "BUTTON" and bit.band(nStyle, 0x000F) == 7
    if isGroupBox then nStyle = bit.bor(nStyle, C.WS_CLIPSIBLINGS) end
    local classWide = ToWide(cClassName)
    local textWide = ToWide(cText)
    local controlMenu = ffi.cast("HMENU", ffi.cast("uintptr_t", nId))
    local dpiValue = GetWindowDpiValue()

    local targetHwnd = user32.CreateWindowExW(
        0,
        classWide,
        textWide,
        nStyle,
        ScaleLogical(nX, dpiValue),
        ScaleLogical(nY, dpiValue),
        ScaleLogical(nWidth, dpiValue),
        ScaleLogical(nHeight, dpiValue),
        gMainHwnd,
        controlMenu,
        gInstanceHnd,
        nil
    )

    if IsNull(targetHwnd) then
        return nil, "CreateWindowExW failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")"
    end

    if hasControlDpi and setControlDpi(targetHwnd, 3, 3) == 0 then
        user32.DestroyWindow(targetHwnd)
        return nil, "SetDialogControlDpiChangeBehavior failed"
    end
    -- GroupBox is a frame behind sibling controls, not their Win32 parent.
    if isGroupBox and user32.SetWindowPos(targetHwnd, ffi.cast("HWND", 1), 0, 0, 0, 0, 0x0013) == 0 then
        user32.DestroyWindow(targetHwnd)
        return nil, "Failed to position GroupBox behind controls"
    end
    if isGroupBox and comctl32.SetWindowSubclass(targetHwnd, GGroupBoxBackgroundCallback, 1, nId) == 0 then
        user32.DestroyWindow(targetHwnd)
        return nil, "SetWindowSubclass failed for GroupBox background"
    end
    gControlList[nId] = targetHwnd
    if isGroupBox then gGroupBoxControls[nId] = targetHwnd end
    -- New child windows can be inserted below existing siblings.
    for _, groupHwnd in pairs(gGroupBoxControls) do
        user32.SetWindowPos(groupHwnd, ffi.cast("HWND", 1), 0, 0, 0, 0, 0x0013)
    end
    -- Tab panes must remain beneath the frames and their page controls.
    if next(gGroupBoxControls) ~= nil then
        for tabId in pairs(gTabPages) do
            local tabHwnd = gControlList[tabId]
            if not IsNull(tabHwnd) then
                user32.SetWindowPos(tabHwnd, ffi.cast("HWND", 1), 0, 0, 0, 0, 0x0013)
            end
        end
    end
    -- Do not recolor EDIT controls or ordinary pushbuttons.
    if cClassName == "STATIC" then
        gTextBackgroundControls[nId] = true
    elseif cClassName == "BUTTON" then
        local buttonType = bit.band(nStyle, 0x000F)
        if buttonType == 3 or buttonType == 7 or buttonType == 9 then
            gTextBackgroundControls[nId] = true
        end
    end
    gControlRects[nId] = {
        x = nX,
        y = nY,
        width = nWidth,
        height = nHeight
    }

    user32.SendMessageW(
        targetHwnd,
        C.WM_SETFONT,
        PtrToWParam(gDefaultFontHnd),
        1
    )

    if GDropFilesHandler ~= nil then
        local dropOk, dropError = RegisterDropTarget(targetHwnd, nId, false)
        if not dropOk then
            user32.DestroyWindow(targetHwnd)
            gControlList[nId] = nil; gControlRects[nId] = nil
            return nil, dropError
        end
    end

    return targetHwnd
end

local function CreateFontAtDpi(specData, dpiValue, autoFont)
    local fontHeight = -math.max(1, math.floor(specData.size * dpiValue / 72 + 0.5))
    local fontWeight = specData.bold and 700 or 400
    local italicFlag = specData.italic and 1 or 0
    local fontNameWide = ToWide(specData.name)

    local fontHnd = gdi32.CreateFontW(
        fontHeight,
        0,
        0,
        0,
        fontWeight,
        italicFlag,
        0,
        0,
        1,
        0,
        0,
        5,
        0,
        fontNameWide
    )

    if IsNull(fontHnd) then
        return nil, "CreateFontW failed"
    end

    local keyValue = FontHandleKey(fontHnd)
    ---@cast keyValue string
    gFontSpecs[keyValue] = CopyFontSpec(specData)
    gFontCreatedDpi[keyValue] = dpiValue

    if autoFont then
        gDpiAutoFonts[#gDpiAutoFonts + 1] = fontHnd
    else
        gFontList[#gFontList + 1] = fontHnd
    end

    return fontHnd
end

local function DeleteDpiAutoFonts(fontList)
    local failed = {}
    for _, h in ipairs(fontList) do
        if not IsNull(h) then
            if gdi32.DeleteObject(h) ~= 0 then
                local key = FontHandleKey(h)
                ---@cast key string
                gFontSpecs[key] = nil; gFontCreatedDpi[key] = nil
            else
                failed[#failed + 1] = h
            end
        end
    end
    for i = #fontList, 1, -1 do fontList[i] = nil end
    for i, h in ipairs(failed) do fontList[i] = h end
    if #failed > 0 then return nil, "DeleteObject failed; font ownership retained for retry" end
    return true
end

function FontCreate(cFontName, nSize, nBold, nItalic)
    if nBold ~= nil and nBold ~= "bold" and nBold ~= "normal" then
        return nil, 'bold style must be "bold" or "normal"'
    end
    if nItalic ~= nil and nItalic ~= "italic" and nItalic ~= "normal" then
        return nil, 'italic style must be "italic" or "normal"'
    end
    if type(nSize) ~= "number" or nSize ~= nSize or nSize <= 0 or nSize > 10000 then
        return nil, "font size must be finite and in (0, 10000]"
    end

    local specData = {
        name = cFontName,
        size = nSize,
        bold = nBold == "bold",
        italic = nItalic == "italic"
    }

    return CreateFontAtDpi(specData, GetWindowDpiValue(), false)
end

local function ApplyControlFont(nId, pFontHnd)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) or IsNull(pFontHnd) then
        return nil, "SetFont failed"
    end

    local fontInfo = ffi.new("LOGFONTW[1]")
    if gdi32.GetObjectType(ffi.cast("HGDIOBJ", pFontHnd)) ~= 6 or
        gdi32.GetObjectW(pFontHnd, ffi.sizeof(fontInfo), fontInfo) == 0 then
        return nil, "SetFont requires a live HFONT"
    end
    local keyValue = FontHandleKey(pFontHnd)
    local specData = gFontSpecs[keyValue]
    local appliedHnd = pFontHnd

    if specData ~= nil then
        local createdDpi = gFontCreatedDpi[keyValue]
        local currentDpi = GetWindowDpiValue()

        if createdDpi ~= currentDpi then
            local cachedHnd = gControlAutoFonts[nId]
            local cachedKey = FontHandleKey(cachedHnd)
            local cachedSpec = cachedKey and gFontSpecs[cachedKey]
            local cachedDpi = cachedKey and gFontCreatedDpi[cachedKey]
            if cachedHnd and cachedSpec and cachedDpi == currentDpi and
                FontSpecCacheKey(cachedSpec) == FontSpecCacheKey(specData) then
                appliedHnd = cachedHnd
            else
                local scaledHnd, fontErr = CreateFontAtDpi(specData, currentDpi, true)
                if IsNull(scaledHnd) then
                    return nil, fontErr
                end
                appliedHnd = scaledHnd
            end
            gControlAutoFonts[nId] = appliedHnd
        else
            gControlAutoFonts[nId] = nil
        end
        gControlFontSpecs[nId] = CopyFontSpec(specData)
        gControlExternalFonts[nId] = nil
    else
        gControlFontSpecs[nId] = nil
        gControlExternalFonts[nId] = pFontHnd
        gControlAutoFonts[nId] = nil
    end

    user32.SendMessageW(targetHwnd, C.WM_SETFONT, PtrToWParam(appliedHnd), 1)
    return true
end

-- FontSet(id, fontName, size, bold, italic).
function FontSet(nId, cFontName, nSize, nBold, nItalic)
    if type(cFontName) ~= "string" then return nil, "font name must be a string" end
    if IsNull(HandleGet(nId)) then return nil, "control does not exist" end
    local fontHnd, fontErr = FontCreate(cFontName, nSize, nBold, nItalic)

    if IsNull(fontHnd) then
        return nil, fontErr
    end

    local setValue, setErr = ApplyControlFont(nId, fontHnd)
    if not setValue then
        return nil, setErr
    end

    return fontHnd
end

FontStyleSet = FontSet

-- Change only the point size; keep the control's family, bold and italic style.
-- Works after the window has started, without creating an HFONT on every toggle.
function FontSizeSet(nId, nSize)
    if IsNull(HandleGet(nId)) then return nil, "control does not exist" end
    if type(nSize) ~= "number" or nSize ~= nSize or nSize <= 0 or nSize > 10000 then
        return nil, "font size must be finite and in (0, 10000]"
    end
    if gControlExternalFonts[nId] ~= nil then
        return nil, "SetFontSize cannot modify an external HFONT; use SetFontStyle"
    end

    local currentSpec = gControlFontSpecs[nId] or gDefaultFontSpec
    if currentSpec == nil then
        currentSpec = {name = "Segoe UI", size = 9, bold = false, italic = false}
    end
    if gControlFontSpecs[nId] ~= nil and currentSpec.size == nSize then
        return true
    end

    local newSpec = CopyFontSpec(currentSpec)
    newSpec.size = nSize
    local dpi = GetWindowDpiValue()
    local key = FontSpecCacheKey(newSpec) .. "\0" .. tostring(dpi)
    local fontHnd = gSizedFontCache[key]
    if IsNull(fontHnd) then
        local err
        fontHnd, err = CreateFontAtDpi(newSpec, dpi, false)
        if IsNull(fontHnd) then return nil, err end
        gSizedFontCache[key] = fontHnd
    end
    return ApplyControlFont(nId, fontHnd)
end

function DefaultFontSet(cFontName, nSize, nBold, nItalic)
    local fontHnd, fontErr = FontCreate(cFontName, nSize, nBold, nItalic)

    if IsNull(fontHnd) then
        return nil, fontErr
    end

    ---@cast fontHnd ffi.cdata*
    gDefaultFontHnd = fontHnd
    gDefaultFontSpec = CopyFontSpec(gFontSpecs[FontHandleKey(fontHnd)])
    for controlId, targetHwnd in pairs(gControlList) do
        if not gControlFontSpecs[controlId] and not gControlExternalFonts[controlId] then
            user32.SendMessageW(targetHwnd, C.WM_SETFONT, PtrToWParam(gDefaultFontHnd), 1)
        end
    end

    return fontHnd
end

RescaleFontsForDpi = function()
    local oldAutoFonts = gDpiAutoFonts
    gDpiAutoFonts = {}
    local cache, replacements = {}, {}
    local function Scaled(spec)
        if not spec then return gStockFontHnd end
        local key = FontSpecCacheKey(spec)
        if cache[key] then return cache[key] end
        local h, err = CreateFontAtDpi(spec, gCurrentDpi, true)
        if not h then error(err) end
        cache[key] = h
        return h
    end
    local ok, newDefault = pcall(function()
        local default = Scaled(gDefaultFontSpec)
        for id in pairs(gControlList) do
            replacements[id] = gControlFontSpecs[id] and Scaled(gControlFontSpecs[id])
                or gControlExternalFonts[id] or default
        end
        return default
    end)
    if not ok then
        DeleteDpiAutoFonts(gDpiAutoFonts)
        for _, h in ipairs(gDpiAutoFonts) do oldAutoFonts[#oldAutoFonts + 1] = h end
        gDpiAutoFonts = oldAutoFonts
        return nil, tostring(newDefault)
    end
    gDefaultFontHnd = newDefault
    for id, h in pairs(replacements) do
        local hwnd = HandleGet(id)
        if hwnd then
            user32.SendMessageW(hwnd, C.WM_SETFONT, PtrToWParam(h), 1)
            gControlAutoFonts[id] = gControlFontSpecs[id] and h or nil
        end
    end
    local deleted, err = DeleteDpiAutoFonts(oldAutoFonts)
    for _, h in ipairs(oldAutoFonts) do gDpiAutoFonts[#gDpiAutoFonts + 1] = h end
    if not deleted then return nil, err end
    return true
end

function FontsDelete()
    if not IsNull(gMainHwnd) then
        for _, targetHwnd in pairs(gControlList) do
            if not IsNull(targetHwnd) then
                user32.SendMessageW(targetHwnd, C.WM_SETFONT, PtrToWParam(gStockFontHnd), 1)
            end
        end
    end

    gDefaultFontHnd = gStockFontHnd
    gDefaultFontSpec = nil
    gControlFontSpecs = {}
    gControlExternalFonts = {}
    gControlAutoFonts = {}
    gSizedFontCache = {}

    local ok1, err1 = DeleteDpiAutoFonts(gDpiAutoFonts)
    local ok2, err2 = DeleteDpiAutoFonts(gFontList)
    if not ok1 or not ok2 then return nil, err1 or err2 end
    return true
end

function Label(nId, cText, nX, nY, nWidth, nHeight, cAlign, cVAlign)
    local style = C.STYLE_LABEL

    if cAlign == "center" then
        style = style + 0x0001 -- SS_CENTER
    elseif cAlign == "right" then
        style = style + 0x0002 -- SS_RIGHT
    end

    if cVAlign == "center" then
        style = style + 0x0200 -- SS_CENTERIMAGE: vertical centering of single-line text
    end

    local hwnd, err = ControlCreate(nId, "STATIC", cText, style, nX, nY, nWidth, nHeight)
    if not hwnd then return nil, err end
    gLabelStyles[nId] = {hwnd = hwnd}
    return hwnd
end

-- Named values follow the usual HTML/CSS palette; Green is 0x008000, Lime is 0x00FF00.
local labelColorNames = {
    black = 0x000000, white = 0xFFFFFF, red = 0xFF0000,
    green = 0x008000, lime = 0x00FF00, blue = 0x0000FF,
    yellow = 0xFFFF00, cyan = 0x00FFFF, aqua = 0x00FFFF,
    magenta = 0xFF00FF, fuchsia = 0xFF00FF, gray = 0x808080,
    grey = 0x808080, silver = 0xC0C0C0, maroon = 0x800000,
    olive = 0x808000, navy = 0x000080, teal = 0x008080,
    purple = 0x800080, orange = 0xFFA500, pink = 0xFFC0CB,
    brown = 0xA52A2A, gold = 0xFFD700, darkgray = 0xA9A9A9,
    darkgrey = 0xA9A9A9, lightgray = 0xD3D3D3, lightgrey = 0xD3D3D3,
    darkred = 0x8B0000, darkgreen = 0x006400, darkblue = 0x00008B
}

local function ParseLabelColor(value)
    local rgb = value
    if type(value) == "string" then
        local name = value:match("^%s*(.-)%s*$"):lower()
        rgb = labelColorNames[name]
        if rgb == nil then
            local hex = name:match("^#(%x%x%x%x%x%x)$") or name:match("^0x(%x+)$")
            if hex and #hex <= 6 then rgb = tonumber(hex, 16)
            elseif name:match("^%d+$") then rgb = tonumber(name) end
        end
    end
    if type(rgb) ~= "number" or rgb < 0 or rgb > 0xFFFFFF or rgb ~= math.floor(rgb) then
        return nil, "color must be a supported name, #RRGGBB, or an integer from 0 to 0xFFFFFF"
    end
    -- The public number is 0xRRGGBB; WinAPI COLORREF is 0xBBGGRR.
    local red = math.floor(rgb / 65536)
    local green = math.floor(rgb / 256) % 256
    local blue = rgb % 256
    return red + green * 256 + blue * 65536
end

-- Label only: RGB triplet, one 0xRRGGBB number, a name/HEX string, or nil to reset.
function TextColorSet(nId, red, green, blue)
    local hwnd = HandleGet(nId)
    local style = gLabelStyles[nId]
    if IsNull(hwnd) or not style or style.hwnd ~= hwnd then
        return nil, "SetTextColor requires an existing Label"
    end
    local color
    if green ~= nil or blue ~= nil then
        local components = {red, green, blue}
        for index = 1, 3 do
            local component = components[index]
            if type(component) ~= "number" or component < 0 or component > 255 or component ~= math.floor(component) then
                return nil, "RGB components must be integers from 0 to 255"
            end
        end
        color = red + green * 256 + blue * 65536
    elseif red ~= nil then
        local err
        color, err = ParseLabelColor(red)
        if color == nil then return nil, err end
    end
    style.color = color
    if user32.InvalidateRect(hwnd, nil, 1) == 0 then return nil, "InvalidateRect failed" end
    return true
end

function Button(nId, cText, nX, nY, nWidth, nHeight)
    return ControlCreate(nId, "BUTTON", cText, C.STYLE_BUTTON, nX, nY, nWidth, nHeight)
end

function DefaultButton(nId, cText, nX, nY, nWidth, nHeight)
    local hwnd, err = ControlCreate(nId, "BUTTON", cText, C.STYLE_DEFAULT_BUTTON, nX, nY, nWidth, nHeight)
    if not hwnd then return nil, err end
    user32.SendMessageW(gMainHwnd, 1025, nId, 0) -- DM_SETDEFID: Enter activates this ID
    return hwnd
end

function Edit(nId, cText, nX, nY, nWidth, nHeight)
    return ControlCreate(nId, "EDIT", cText, C.STYLE_EDIT, nX, nY, nWidth, nHeight)
end

function EditMulti(nId, cText, nX, nY, nWidth, nHeight)
    return ControlCreate(nId, "EDIT", cText, C.STYLE_EDIT_MULTILINE, nX, nY, nWidth, nHeight)
end

function EditReadOnly(nId, cText, nX, nY, nWidth, nHeight)
    return ControlCreate(nId, "EDIT", cText, C.STYLE_EDIT_READONLY, nX, nY, nWidth, nHeight)
end

function EditPassword(nId, cText, nX, nY, nWidth, nHeight)
    return ControlCreate(nId, "EDIT", cText, C.STYLE_EDIT_PASSWORD, nX, nY, nWidth, nHeight)
end

function CheckBox(nId, cText, nX, nY, nWidth, nHeight)
    return ControlCreate(nId, "BUTTON", cText, C.STYLE_CHECKBOX, nX, nY, nWidth, nHeight)
end

function RadioButton(nId, cText, nX, nY, nWidth, nHeight, groupStart)
    local radioStyle = C.STYLE_RADIO

    if IsEnabledFlag(groupStart) then
        radioStyle = radioStyle + C.WS_GROUP
    end

    return ControlCreate(nId, "BUTTON", cText, radioStyle, nX, nY, nWidth, nHeight)
end

function GroupBox(nId, cText, nX, nY, nWidth, nHeight)
    return ControlCreate(nId, "BUTTON", cText, C.STYLE_GROUPBOX, nX, nY, nWidth, nHeight)
end

function ComboBox(nId, nX, nY, nWidth, nHeight)
    return ControlCreate(nId, "COMBOBOX", "", C.STYLE_COMBOBOX, nX, nY, nWidth, nHeight)
end

function ComboAdd(nId, cText)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "ComboAdd failed"
    end

    local textWide = ToWide(cText)
    local resultValue = tonumber(user32.SendMessageW(targetHwnd, C.CB_ADDSTRING, 0, PtrToLParam(textWide)))

    if resultValue < 0 then
        return nil, "ComboAdd failed"
    end

    return resultValue + 1
end

function ComboItemsSet(nId, aItems)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "ComboSetItems failed"
    end

    local wideItems = {}
    for i = 1, #aItems do wideItems[i] = ToWide(aItems[i]) end
    user32.SendMessageW(targetHwnd, C.CB_RESETCONTENT, 0, 0)

    for indexValue = 1, #wideItems do
        -- SendMessageW can re-enter Lua; resolve the control again as ComboAdd
        -- does, in case a previous insertion destroyed or replaced it.
        targetHwnd = HandleGet(nId)
        if IsNull(targetHwnd) then return nil, "ComboAdd failed" end
        local value = tonumber(user32.SendMessageW(targetHwnd, C.CB_ADDSTRING, 0, PtrToLParam(wideItems[indexValue])))
        if value < 0 then return nil, "ComboAdd failed" end
    end

    return true
end

function ComboSelectedSet(nId, nIndex)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "ComboSetSelected failed"
    end

    if type(nIndex) ~= "number" or nIndex ~= math.floor(nIndex) or nIndex < 1 or nIndex > 2147483647 then
        return nil, "selection index must be a positive integer"
    end
    local resultValue = tonumber(user32.SendMessageW(targetHwnd, C.CB_SETCURSEL, nIndex - 1, 0))

    if resultValue < 0 then
        return nil, "ComboSetSelected failed"
    end

    return true
end

function ComboSelectedGet(nId)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil
    end

    local winIndex = tonumber(user32.SendMessageW(targetHwnd, C.CB_GETCURSEL, 0, 0))

    if winIndex < 0 then
        return nil
    end

    return winIndex + 1
end

function ComboSelectedTextGet(nId)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil
    end

    local indexValue = ComboSelectedGet(nId)

    if indexValue == nil then
        return nil
    end

    local winIndex = indexValue - 1
    local textLength = tonumber(user32.SendMessageW(targetHwnd, C.CB_GETLBTEXTLEN, winIndex, 0))

    if textLength < 0 then
        return nil
    end

    local textData = ffi.new("WCHAR[?]", textLength + 1)
    user32.SendMessageW(targetHwnd, C.CB_GETLBTEXT, winIndex, PtrToLParam(textData))

    return FromWide(textData)
end

function ListBox(nId, nX, nY, nWidth, nHeight)
    return ControlCreate(nId, "LISTBOX", "", C.STYLE_LISTBOX, nX, nY, nWidth, nHeight)
end

function ListAdd(nId, cText)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "ListAdd failed"
    end

    local textWide = ToWide(cText)
    local resultValue = tonumber(user32.SendMessageW(targetHwnd, C.LB_ADDSTRING, 0, PtrToLParam(textWide)))

    if resultValue < 0 then
        return nil, "ListAdd failed"
    end

    return resultValue + 1
end

function ListItemsSet(nId, aItems)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "ListSetItems failed"
    end

    local wideItems = {}
    for i = 1, #aItems do wideItems[i] = ToWide(aItems[i]) end
    user32.SendMessageW(targetHwnd, C.LB_RESETCONTENT, 0, 0)

    for indexValue = 1, #wideItems do
        targetHwnd = HandleGet(nId)
        if IsNull(targetHwnd) then return nil, "ListAdd failed" end
        local value = tonumber(user32.SendMessageW(targetHwnd, C.LB_ADDSTRING, 0, PtrToLParam(wideItems[indexValue])))
        if value < 0 then return nil, "ListAdd failed" end
    end

    return true
end

function ListSelectedSet(nId, nIndex)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "ListSetSelected failed"
    end

    if type(nIndex) ~= "number" or nIndex ~= math.floor(nIndex) or nIndex < 1 or nIndex > 2147483647 then
        return nil, "selection index must be a positive integer"
    end
    local resultValue = tonumber(user32.SendMessageW(targetHwnd, C.LB_SETCURSEL, nIndex - 1, 0))

    if resultValue < 0 then
        return nil, "ListSetSelected failed"
    end

    return true
end

function ListSelectedGet(nId)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil
    end

    local winIndex = tonumber(user32.SendMessageW(targetHwnd, C.LB_GETCURSEL, 0, 0))

    if winIndex < 0 then
        return nil
    end

    return winIndex + 1
end

function ListSelectedTextGet(nId)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil
    end

    local indexValue = ListSelectedGet(nId)

    if indexValue == nil then
        return nil
    end

    local winIndex = indexValue - 1
    local textLength = tonumber(user32.SendMessageW(targetHwnd, C.LB_GETTEXTLEN, winIndex, 0))

    if textLength < 0 then
        return nil
    end

    local textData = ffi.new("WCHAR[?]", textLength + 1)
    user32.SendMessageW(targetHwnd, C.LB_GETTEXT, winIndex, PtrToLParam(textData))

    return FromWide(textData)
end

function ProgressBar(nId, nX, nY, nWidth, nHeight, nMin, nMax, nValue)
    for _, value in ipairs({nMin, nMax, nValue}) do
        if type(value) ~= "number" or value ~= math.floor(value) or value < -2147483648 or value > 2147483647 then
            return nil, "progress range and value must be signed 32-bit integers"
        end
    end
    if nMin == nil or nMax == nil or nValue == nil or nMin > nMax then return nil, "invalid progress range" end
    local targetHwnd, createErr = ControlCreate(nId, "msctls_progress32", "", C.STYLE_PROGRESS, nX, nY, nWidth, nHeight)

    if IsNull(targetHwnd) then
        return nil, createErr
    end

    user32.SendMessageW(targetHwnd, C.PBM_SETRANGE32, nMin, nMax)
    user32.SendMessageW(targetHwnd, C.PBM_SETPOS, nValue, 0)

    return targetHwnd
end

function ProgressSet(nId, nValue)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "SetProgress failed"
    end

    user32.SendMessageW(targetHwnd, C.PBM_SETPOS, nValue, 0)
    return true
end

function Slider(nId, nX, nY, nWidth, nHeight, nMin, nMax, nValue)
    for _, value in ipairs({nMin, nMax, nValue}) do
        if type(value) ~= "number" or value ~= math.floor(value) or value < -2147483648 or value > 2147483647 then
            return nil, "slider range and value must be signed 32-bit integers"
        end
    end
    if nMin == nil or nMax == nil or nValue == nil or nMin > nMax then return nil, "invalid slider range" end
    local targetHwnd, createErr = ControlCreate(nId, "msctls_trackbar32", "", C.STYLE_SLIDER, nX, nY, nWidth, nHeight)

    if IsNull(targetHwnd) then
        return nil, createErr
    end

    user32.SendMessageW(targetHwnd, C.TBM_SETRANGEMIN, 1, nMin)
    user32.SendMessageW(targetHwnd, C.TBM_SETRANGEMAX, 1, nMax)
    user32.SendMessageW(targetHwnd, C.TBM_SETPOS, 1, nValue)

    return targetHwnd
end

function SliderSet(nId, nValue)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "SetSlider failed"
    end

    user32.SendMessageW(targetHwnd, C.TBM_SETPOS, 1, nValue)
    return true
end

function SliderGet(nId)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil
    end

    return tonumber(user32.SendMessageW(targetHwnd, C.TBM_GETPOS, 0, 0))
end

function Tab(nId, nX, nY, nWidth, nHeight)
    local targetHwnd, createErr = ControlCreate(nId, "SysTabControl32", "", C.STYLE_TAB, nX, nY, nWidth, nHeight)

    if IsNull(targetHwnd) then
        return nil, createErr
    end

    user32.ShowWindow(targetHwnd, C.SW_SHOW)
    user32.UpdateWindow(targetHwnd)

    return targetHwnd
end

function TabButtons(nId, nX, nY, nWidth, nHeight)
    return ControlCreate(nId, "SysTabControl32", "", C.STYLE_TAB_BUTTONS, nX, nY, nWidth, nHeight)
end

function TabAdd(nId, cText)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "TabAdd failed"
    end

    local itemCount = tonumber(user32.SendMessageW(targetHwnd, C.TCM_GETITEMCOUNT, 0, 0))
    local itemData = ffi.new("TCITEMW[1]")
    local textWide = ToWide(cText)

    itemData[0].mask = C.TCIF_TEXT
    itemData[0].pszText = textWide

    local resultValue = tonumber(user32.SendMessageW(targetHwnd, C.TCM_INSERTITEMW, itemCount, PtrToLParam(itemData)))

    if resultValue < 0 then
        return nil, "TabAdd failed"
    end

    user32.InvalidateRect(targetHwnd, nil, 1)
    user32.UpdateWindow(targetHwnd)

    return resultValue + 1
end

function TabSelectedGet(NId)
    local targetHwnd = HandleGet(NId)

    if IsNull(targetHwnd) then
        return nil
    end

    local winIndex = tonumber(user32.SendMessageW(targetHwnd, C.TCM_GETCURSEL, 0, 0))

    if winIndex < 0 then
        return nil
    end

    return winIndex + 1
end

function TabSelectedSet(nId, nIndex)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "TabSetSelected failed"
    end

    local count = tonumber(user32.SendMessageW(targetHwnd, C.TCM_GETITEMCOUNT, 0, 0))
    if type(nIndex) ~= "number" or nIndex ~= math.floor(nIndex) or nIndex < 1 or nIndex > count then
        return nil, "tab index is out of range"
    end
    user32.SendMessageW(targetHwnd, C.TCM_SETCURSEL, nIndex - 1, 0)
    TabPagesUpdate(nId)

    return true
end

function OnTabChange(nId, CHandlerName)
    return HandlerSet(gSelectHandlers, nId, CHandlerName)
end

function TabPage(NTabId, nPageIndex, aControlIds)
    local tab = HandleGet(NTabId)
    if not tab or type(nPageIndex) ~= "number" or nPageIndex ~= math.floor(nPageIndex) or
        nPageIndex < 1 or nPageIndex > tonumber(user32.SendMessageW(tab, C.TCM_GETITEMCOUNT, 0, 0)) then
        return nil, "tab page does not exist"
    end
    local copy = {}
    for i, id in ipairs(aControlIds) do
        if id == NTabId or not HandleGet(id) then return nil, "invalid page control" end
        for otherTabId, pages in pairs(gTabPages) do
            for page, ids in pairs(pages) do
                if otherTabId ~= NTabId or page ~= nPageIndex then
                    for _, oldId in ipairs(ids) do
                        if oldId == id then return nil, "control already belongs to another tab page" end
                    end
                end
            end
        end
        copy[i] = id
    end
    if gTabPages[NTabId] == nil then
        gTabPages[NTabId] = {}
    end

    -- Page controls are siblings; keep the tab behind them for WS_CLIPSIBLINGS.
    if user32.SetWindowPos(tab, ffi.cast("HWND", 1), 0, 0, 0, 0, 0x0013) == 0 then
        return nil, "Failed to position tab behind page controls"
    end

    local previous = gTabPages[NTabId][nPageIndex]
    if previous then
        for _, oldId in ipairs(previous) do
            gTabPageControls[oldId] = nil
        end
    end
    gTabPages[NTabId][nPageIndex] = copy
    for _, controlId in ipairs(copy) do
        gTabPageControls[controlId] = NTabId
        -- Force a repaint when an already visible label acquires tab background.
        local controlHwnd = HandleGet(controlId)
        if controlHwnd then user32.InvalidateRect(controlHwnd, nil, 1) end
    end
    TabPagesUpdate(NTabId)

    return true
end

function TabPagesUpdate(NTabId)
    local selectedPage = TabSelectedGet(NTabId)

    if selectedPage == nil then
        return nil, "TabUpdatePages failed"
    end

    local tabData = gTabPages[NTabId]

    if tabData == nil then
        return true
    end

    for pageIndex, controlIds in pairs(tabData) do
        local showMode = C.SW_HIDE

        if pageIndex == selectedPage then
            showMode = C.SW_SHOW
        end

        for controlIndex = 1, #controlIds do
            local targetHwnd = HandleGet(controlIds[controlIndex])

            if not IsNull(targetHwnd) then
                user32.ShowWindow(targetHwnd, showMode)
            end
        end
    end

    return true
end

function ListView(nId, nX, nY, nWidth, nHeight)
    local targetHwnd, createErr = ControlCreate(nId, "SysListView32", "", C.STYLE_LISTVIEW, nX, nY, nWidth, nHeight)

    if IsNull(targetHwnd) then
        return nil, createErr
    end

    local exStyle = C.LVS_EX_GRIDLINES + C.LVS_EX_FULLROWSELECT
    user32.SendMessageW(targetHwnd, C.LVM_SETEXTENDEDLISTVIEWSTYLE, 0, exStyle)
    ListViewColumnCountSet(nId, 0)

    return targetHwnd
end

function ListViewColumnAdd(nId, cText, nWidth)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "ListViewAddColumn failed"
    end
    if nWidth ~= nil and (type(nWidth) ~= "number" or nWidth < 0) then
        return nil, "column width must be a nonnegative number or nil"
    end

    local columnIndex = ListViewColumnCountGet(nId)
    local columnData = ffi.new("LVCOLUMNW[1]")
    local textWide = ToWide(cText)

    columnData[0].mask = C.LVCF_FMT + C.LVCF_WIDTH + C.LVCF_TEXT + C.LVCF_SUBITEM
    columnData[0].fmt = 0
    columnData[0].cx = ScaleLogical(nWidth, GetWindowDpiValue())
    columnData[0].pszText = textWide
    columnData[0].iSubItem = columnIndex

    local resultValue = tonumber(user32.SendMessageW(targetHwnd, C.LVM_INSERTCOLUMNW, columnIndex, PtrToLParam(columnData)))

    if resultValue < 0 then
        return nil, "ListViewAddColumn failed"
    end

    ListViewColumnCountSet(nId, columnIndex + 1)
    gListViewColumnWidths[nId] = gListViewColumnWidths[nId] or {}
    gListViewColumnWidths[nId][columnIndex + 1] = nWidth or 0
    return resultValue + 1
end

function ListViewAdd(nId, aValues)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) or #aValues == 0 then
        return nil, "ListViewAdd failed"
    end

    local wideValues = {}
    for i = 1, #aValues do wideValues[i] = ToWide(aValues[i]) end
    local rowIndex = tonumber(user32.SendMessageW(targetHwnd, C.LVM_GETITEMCOUNT, 0, 0))
    local itemData = ffi.new("LVITEMW[1]")
    local firstText = wideValues[1]

    itemData[0].mask = C.LVIF_TEXT
    itemData[0].iItem = rowIndex
    itemData[0].iSubItem = 0
    itemData[0].pszText = firstText

    local insertedIndex = tonumber(user32.SendMessageW(targetHwnd, C.LVM_INSERTITEMW, 0, PtrToLParam(itemData)))

    if insertedIndex < 0 then
        return nil, "ListViewAdd failed"
    end

    for columnIndex = 2, #aValues do
        local subItem = ffi.new("LVITEMW[1]")
        local subText = wideValues[columnIndex]

        subItem[0].iSubItem = columnIndex - 1
        subItem[0].pszText = subText

        if user32.SendMessageW(targetHwnd, C.LVM_SETITEMTEXTW, insertedIndex, PtrToLParam(subItem)) == 0 then
            user32.SendMessageW(targetHwnd, 4104, insertedIndex, 0) -- LVM_DELETEITEM rollback
            return nil, "LVM_SETITEMTEXTW failed"
        end
    end

    return insertedIndex + 1
end

function ListViewSelectedGet(nId)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil
    end

    local selectedIndex = tonumber(user32.SendMessageW(targetHwnd, C.LVM_GETNEXTITEM, -1, C.LVNI_SELECTED))

    if selectedIndex < 0 then
        return nil
    end

    return selectedIndex + 1
end

function ListViewTextGet(nId, nRow, nColumn)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) or nRow <= 0 or nColumn <= 0 then
        return nil
    end

    if nRow ~= math.floor(nRow) or nColumn ~= math.floor(nColumn) or
        nRow > tonumber(user32.SendMessageW(targetHwnd, C.LVM_GETITEMCOUNT, 0, 0)) or
        nColumn > ListViewColumnCountGet(nId) then return nil end
    local capacity = 1024
    while true do
        local textData = ffi.new("WCHAR[?]", capacity)
        local itemData = ffi.new("LVITEMW[1]")
        itemData[0].iSubItem = nColumn - 1
        itemData[0].pszText = textData
        itemData[0].cchTextMax = capacity
        local copied = tonumber(user32.SendMessageW(targetHwnd, C.LVM_GETITEMTEXTW, nRow - 1, PtrToLParam(itemData)))
        if copied < capacity - 1 then return FromWide(textData) end
        capacity = capacity * 2
    end
end

function ListViewColumnCountGet(nId)
    return gListViewColumnCounts[nId] or 0
end

function ListViewColumnCountSet(nId, nCount)
    if not HandleGet(nId) or type(nCount) ~= "number" or nCount ~= math.floor(nCount) or nCount < 0 or nCount > 65535 then
        return nil, "invalid ListView ID or column count"
    end
    gListViewColumnCounts[nId] = nCount
    if nCount == 0 then
        gListViewColumnWidths[nId] = {}
    end
    return true
end

function OnListViewSelect(nId, CHandlerName)
    return HandlerSet(gSelectHandlers, nId, CHandlerName)
end

function TreeView(nId, nX, nY, nWidth, nHeight)
    return ControlCreate(nId, "SysTreeView32", "", C.STYLE_TREEVIEW, nX, nY, nWidth, nHeight)
end

function TreeRootAdd(nId, cText)
    return TreeInsert(nId, cText, nil)
end

function TreeChildAdd(nId, pParentItem, cText)
    return TreeInsert(nId, cText, pParentItem)
end

function TreeInsert(nId, cText, pParentItem)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "TreeView does not exist"
    end

    local insertData = ffi.new("TVINSERTSTRUCTW[1]")
    local textWide = ToWide(cText)

    insertData[0].hParent = pParentItem or nil
    insertData[0].hInsertAfter = ffi.cast("HTREEITEM", ffi.cast("intptr_t", -65534))
    insertData[0].item.mask = C.TVIF_TEXT
    insertData[0].item.pszText = textWide

    local resultValue = user32.SendMessageW(targetHwnd, C.TVM_INSERTITEMW, 0, PtrToLParam(insertData))
    local itemHnd = LResultToPtr("HTREEITEM", resultValue)

    if IsNull(itemHnd) then
        return nil, "TVM_INSERTITEMW failed"
    end

    return itemHnd
end

function TreeSelectedGet(nId)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil
    end

    local resultValue = user32.SendMessageW(targetHwnd, C.TVM_GETNEXTITEM, C.TVGN_CARET, 0)
    local itemHnd = LResultToPtr("HTREEITEM", resultValue)

    if IsNull(itemHnd) then
        return nil
    end

    return itemHnd
end

function TreeTextGet(nId, pItemHnd)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) or IsNull(pItemHnd) then
        return nil
    end

    local capacity = 1024
    while true do
        local textData = ffi.new("WCHAR[?]", capacity)
        local itemData = ffi.new("TVITEMEXW[1]")
        itemData[0].mask = C.TVIF_TEXT
        itemData[0].hItem = pItemHnd
        itemData[0].pszText = textData
        itemData[0].cchTextMax = capacity
        if user32.SendMessageW(targetHwnd, C.TVM_GETITEMW, 0, PtrToLParam(itemData)) == 0 then
            return nil, "TVM_GETITEMW failed"
        end
        local count = 0
        while count < capacity and textData[count] ~= 0 do count = count + 1 end
        if count < capacity - 1 then return FromWide(textData) end
        capacity = capacity * 2
    end
end

function TreeExpand(nId, pItemHnd)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) or IsNull(pItemHnd) then
        return nil, "TreeExpand failed"
    end

    return user32.SendMessageW(targetHwnd, C.TVM_EXPAND, C.TVE_EXPAND, PtrToLParam(pItemHnd)) ~= 0
end

function OnTreeSelect(nId, CHandlerName)
    return HandlerSet(gSelectHandlers, nId, CHandlerName)
end

function StatusBar(nId, cText, nX, nY, nWidth, nHeight)
    local targetHwnd, createErr = ControlCreate(nId, "msctls_statusbar32", "", C.STYLE_STATUSBAR, nX, nY, nWidth, nHeight)

    if IsNull(targetHwnd) then
        return nil, createErr
    end

    local ok, err = StatusTextSet(nId, cText)
    if not ok then
        ForgetDestroyedControl(nId, targetHwnd)
        user32.DestroyWindow(targetHwnd)
        return nil, err
    end
    return targetHwnd
end

function StatusTextSet(nId, cText)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "StatusSetText failed"
    end

    local textWide = ToWide(cText)
    if user32.SendMessageW(targetHwnd, C.SB_SETTEXTW, 0, PtrToLParam(textWide)) == 0 then
        return nil, "SB_SETTEXTW failed"
    end

    return true
end

function ToolTip(nId, cText)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "ToolTip failed"
    end

    if IsNull(gTooltipHwnd) then
        local classWide = ToWide("tooltips_class32")
        local emptyWide = ToWide("")

        gTooltipHwnd = user32.CreateWindowExW(
            C.WS_EX_TOPMOST,
            classWide,
            emptyWide,
            C.STYLE_TOOLTIP,
            0,
            0,
            0,
            0,
            gMainHwnd,
            nil,
            gInstanceHnd,
            nil
        )

        if IsNull(gTooltipHwnd) then
            return nil, "ToolTip failed"
        end
    end

    local toolData = ffi.new("TTTOOLINFOW[1]")
    local textWide = ToWide(cText)

    local oldText = gTooltipTexts[nId]

    -- V2 size works with the default Common Controls v5 and manifest-enabled v6.
    toolData[0].cbSize = ffi.offsetof("TTTOOLINFOW", "lpReserved")
    toolData[0].uFlags = C.TTF_IDISHWND + C.TTF_SUBCLASS
    toolData[0].hwnd = gMainHwnd
    toolData[0].uId = ffi.cast("UINT_PTR", ffi.cast("uintptr_t", targetHwnd))
    toolData[0].lpszText = textWide

    if oldText ~= nil then
        user32.SendMessageW(gTooltipHwnd, C.TTM_UPDATETIPTEXTW, 0, PtrToLParam(toolData))
        gTooltipTexts[nId] = textWide
        return true
    end
    local resultValue = tonumber(user32.SendMessageW(gTooltipHwnd, C.TTM_ADDTOOLW, 0, PtrToLParam(toolData)))

    if resultValue == 0 then
        return nil, "ToolTip failed"
    end

    gTooltipTexts[nId] = textWide
    return true
end

local function MenuRecord(h)
    if IsNull(h) then return nil end
    local r = gMenus[FontHandleKey(h)]
    if not r or user32.IsMenu(h) == 0 then return nil end
    return r
end

local function ForgetMenu(h)
    local key = FontHandleKey(h)
    ---@cast key string
    local r = gMenus[key]
    if r then
        for _, child in ipairs(r.children) do ForgetMenu(child) end
        gMenus[key] = nil
    end
end

function MenuBar()
    local h = user32.CreateMenu()
    if IsNull(h) then return nil, "CreateMenu failed" end
    gMenus[FontHandleKey(h)] = {handle = h, children = {}}
    return h
end

function Menu()
    local h = user32.CreatePopupMenu()
    if IsNull(h) then return nil, "CreatePopupMenu failed" end
    gMenus[FontHandleKey(h)] = {handle = h, children = {}}
    return h
end

function MenuDestroy(pMenuHnd)
    local r = MenuRecord(pMenuHnd)
    if not r then return nil, "menu is not a live library-owned menu" end
    if r.parent then return nil, "submenu belongs to its parent; destroy the root menu" end
    if gAttachedMenu == pMenuHnd then
        if user32.SetMenu(gMainHwnd, nil) == 0 then return nil, "SetMenu detach failed" end
        gAttachedMenu = nil
        user32.DrawMenuBar(gMainHwnd)
    end
    if user32.DestroyMenu(pMenuHnd) == 0 then return nil, "DestroyMenu failed" end
    ForgetMenu(pMenuHnd)
    return true
end

function MenuAdd(pMenuHnd, nId, cText)
    if not MenuRecord(pMenuHnd) then return nil, "invalid menu" end
    if type(nId) ~= "number" or nId ~= math.floor(nId) or nId < 1 or nId > 65535 then
        return nil, "menu ID must be in 1..65535"
    end
    if nId == 1 or nId == 2 then
        return nil, "menu IDs 1 and 2 are reserved (IDOK/IDCANCEL)"
    end

    local textWide = ToWide(cText)
    local resultValue = user32.AppendMenuW(pMenuHnd, C.MF_STRING, nId, textWide)

    if resultValue == 0 then return nil, "MenuAdd failed" end
    return true
end

function MenuSubAdd(pMenuHnd, pSubMenuHnd, cText)
    local parent, child = MenuRecord(pMenuHnd), MenuRecord(pSubMenuHnd)
    if not parent or not child then return nil, "invalid menu" end
    if child.parent or gAttachedMenu == pSubMenuHnd then return nil, "submenu already has an owner" end
    local ancestor = pMenuHnd
    while ancestor do
        if ancestor == pSubMenuHnd then return nil, "menu ownership cycle" end
        ancestor = MenuRecord(ancestor).parent
    end

    local textWide = ToWide(cText)
    local subMenuId = ffi.cast("UINT_PTR", ffi.cast("uintptr_t", pSubMenuHnd))
    local resultValue = user32.AppendMenuW(pMenuHnd, C.MF_POPUP, subMenuId, textWide)

    if resultValue == 0 then return nil, "MenuAddSub failed" end
    child.parent = pMenuHnd
    parent.children[#parent.children + 1] = pSubMenuHnd
    return true
end

function MenuSeparator(pMenuHnd)
    if not MenuRecord(pMenuHnd) then return nil, "invalid menu" end

    local resultValue = user32.AppendMenuW(pMenuHnd, C.MF_SEPARATOR, 0, nil)
    if resultValue == 0 then return nil, "MenuSeparator failed" end
    return true
end

function MenuSet(pMenuHnd)
    if IsNull(gMainHwnd) or IsNull(pMenuHnd) then
        return nil, "MenuSet failed"
    end

    local r = MenuRecord(pMenuHnd)
    if not r or r.parent then return nil, "expected a live root menu" end
    local resultValue = user32.SetMenu(gMainHwnd, pMenuHnd)
    user32.DrawMenuBar(gMainHwnd)

    if resultValue == 0 then return nil, "MenuSet failed" end
    gAttachedMenu = pMenuHnd
    if gWindowLogicalSize and gWindowLogicalSize.client then
        local ok, err = FitWindowToClient(gMainHwnd, gWindowLogicalSize.width, gWindowLogicalSize.height)
        if not ok then return nil, err end
    end
    return true
end

function OnMenu(nId, CHandlerName)
    if nId == 1 or nId == 2 then
        return nil, "menu IDs 1 and 2 are reserved (IDOK/IDCANCEL)"
    end
    return HandlerSet(gMenuHandlers, nId, CHandlerName)
end

local function MakeFileDialogFilter(filters)
    if filters == nil then return nil end
    if type(filters) ~= "table" or #filters == 0 then
        return nil, "filters должен быть непустым массивом пар {описание, шаблон}"
    end
    local parts, units = {}, 1
    for key in pairs(filters) do
        if type(key) ~= "number" or key ~= math.floor(key) or key < 1 or key > #filters then
            return nil, "В массиве filters не должно быть пропусков"
        end
    end
    for index = 1, #filters do
        local pair = filters[index]
        if type(pair) ~= "table" or type(pair[1]) ~= "string" or pair[1] == "" or
            type(pair[2]) ~= "string" or pair[2] == "" then
            return nil, "Для каждого фильтра нужны непустые описание и шаблон"
        end
        for field = 1, 2 do
            local wide, err, code = dialogWin.ToWide(pair[field])
            if not wide then return nil, err, code end
            local length = ffi.sizeof(wide) / ffi.sizeof("WCHAR")
            parts[#parts + 1] = {wide = wide, units = length}
            units = units + length
        end
    end
    local buffer = ffi.new("WCHAR[?]", units)
    local offset = 0
    for _, part in ipairs(parts) do
        ffi.copy(buffer + offset, part.wide, part.units * ffi.sizeof("WCHAR"))
        offset = offset + part.units
    end
    -- Each string includes its terminator; the zero-initialized extra WCHAR
    -- supplies the second NUL required at the end of the filter list.
    return buffer
end

function FileOpen(cTitle, filters, initialDir)
    local dialogData = ffi.new("OPENFILENAMEW[1]")
    local pathData = ffi.new("WCHAR[32768]")
    local titleWide, err, code = dialogWin.ToWide(tostring(cTitle or ""))
    if not titleWide then return nil, err, code end
    local filterWide; filterWide, err, code = MakeFileDialogFilter(filters)
    if err then return nil, err, code end
    if initialDir ~= nil and (type(initialDir) ~= "string" or initialDir == "") then
        return nil, "initialDir должен быть непустым путём к папке"
    end
    local initialDirWide
    if initialDir ~= nil then
        initialDirWide, err, code = dialogWin.ToWide(initialDir)
        if not initialDirWide then return nil, err, code end
    end

    dialogData[0].lStructSize = ffi.sizeof("OPENFILENAMEW")
    dialogData[0].hwndOwner = gMainHwnd
    dialogData[0].hInstance = gInstanceHnd
    dialogData[0].lpstrFile = pathData
    dialogData[0].nMaxFile = 32768
    dialogData[0].lpstrTitle = titleWide
    dialogData[0].lpstrFilter = filterWide
    dialogData[0].nFilterIndex = filterWide ~= nil and 1 or 0
    dialogData[0].lpstrInitialDir = initialDirWide
    dialogData[0].Flags = C.OFN_EXPLORER + C.OFN_HIDEREADONLY + C.OFN_NOCHANGEDIR + C.OFN_PATHMUSTEXIST + C.OFN_FILEMUSTEXIST

    if comdlg32.GetOpenFileNameW(dialogData) == 0 then
        return DialogFailure()
    end

    return dialogWin.FromWide(pathData)
end

function FileSave(cTitle, filters, initialDir)
    local dialogData = ffi.new("OPENFILENAMEW[1]")
    local pathData = ffi.new("WCHAR[32768]")
    local titleWide, err, code = dialogWin.ToWide(tostring(cTitle or ""))
    if not titleWide then return nil, err, code end
    local filterWide; filterWide, err, code = MakeFileDialogFilter(filters)
    if err then return nil, err, code end
    if initialDir ~= nil and (type(initialDir) ~= "string" or initialDir == "") then
        return nil, "initialDir должен быть непустым путём к папке"
    end
    local initialDirWide
    if initialDir ~= nil then
        initialDirWide, err, code = dialogWin.ToWide(initialDir)
        if not initialDirWide then return nil, err, code end
    end

    dialogData[0].lStructSize = ffi.sizeof("OPENFILENAMEW")
    dialogData[0].hwndOwner = gMainHwnd
    dialogData[0].hInstance = gInstanceHnd
    dialogData[0].lpstrFile = pathData
    dialogData[0].nMaxFile = 32768
    dialogData[0].lpstrTitle = titleWide
    dialogData[0].lpstrFilter = filterWide
    dialogData[0].nFilterIndex = filterWide ~= nil and 1 or 0
    dialogData[0].lpstrInitialDir = initialDirWide
    dialogData[0].Flags = C.OFN_EXPLORER + C.OFN_NOCHANGEDIR + C.OFN_PATHMUSTEXIST + C.OFN_OVERWRITEPROMPT

    if comdlg32.GetSaveFileNameW(dialogData) == 0 then
        return DialogFailure()
    end

    return dialogWin.FromWide(pathData)
end

-- Modern Common Item Dialog (IFileOpenDialog + FOS_PICKFOLDERS).
-- Keep the main HWND as modal owner and preserve path / nil / nil,error results.
function FolderChoose(cTitle)
    local title = tostring(cTitle or "")
    local wide, err, code = dialogWin.ToWide(title)
    if not wide then return nil, err, code end
    return require("file_dialog").FolderSelect({title = title, owner = gMainHwnd})
end

function ColorChoose(nInitialColor)
    local colorData = ffi.new("CHOOSECOLORW[1]")
    local customColors = ffi.new("COLORREF[16]")

    colorData[0].lStructSize = ffi.sizeof("CHOOSECOLORW")
    colorData[0].hwndOwner = gMainHwnd
    colorData[0].rgbResult = type(nInitialColor) == "number" and nInitialColor or 0
    colorData[0].lpCustColors = customColors
    colorData[0].Flags = C.CC_RGBINIT + C.CC_FULLOPEN

    if comdlg32.ChooseColorW(colorData) == 0 then
        return DialogFailure()
    end

    return tonumber(colorData[0].rgbResult)
end

function Enable(nId, nState)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "Enable failed"
    end

    user32.EnableWindow(targetHwnd, IsEnabledFlag(nState) and 1 or 0)
    return true
end

function Show(nId, nState)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "Show failed"
    end

    local showMode = C.SW_HIDE

    if IsEnabledFlag(nState) then
        showMode = C.SW_SHOW
    end

    user32.ShowWindow(targetHwnd, showMode)
    return true
end

function Move(nId, nX, nY, nWidth, nHeight)
    if type(nWidth) ~= "number" or type(nHeight) ~= "number" or nWidth < 0 or nHeight < 0 then
        return nil, "control dimensions must be nonnegative numbers"
    end
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "Move failed"
    end

    local dpiValue = GetWindowDpiValue()
    local resultValue = user32.MoveWindow(
        targetHwnd,
        ScaleLogical(nX, dpiValue),
        ScaleLogical(nY, dpiValue),
        ScaleLogical(nWidth, dpiValue),
        ScaleLogical(nHeight, dpiValue),
        1
    )

    if resultValue == 0 then return nil, "Move failed" end

    gControlRects[nId] = {
        x = nX,
        y = nY,
        width = nWidth,
        height = nHeight
    }

    return true
end

function FocusSet(nId)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "SetFocus failed"
    end

    user32.SetFocus(targetHwnd)
    if user32.GetFocus() ~= targetHwnd then return nil, "SetFocus failed" end
    return true
end

-- Keep the main window above non-topmost windows without moving or activating it.
-- true/non-zero enables; false/nil/0 disables. Call after Window/WindowClient.
function WindowTopmostSet(nState)
    if IsNull(gMainHwnd) or user32.IsWindow(gMainHwnd) == 0 then
        return nil, "WindowTopmostSet: GUI window does not exist"
    end

    local insertAfter = ffi.cast("HWND", ffi.cast("intptr_t", IsEnabledFlag(nState) and -1 or -2))
    -- SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE; allow the Z-order change.
    if user32.SetWindowPos(gMainHwnd, insertAfter, 0, 0, 0, 0, 0x0013) == 0 then
        return nil, "WindowTopmostSet: SetWindowPos failed (" .. tonumber(kernel32.GetLastError()) .. ")"
    end
    return true
end

function TitleSet(cTitle)
    if IsNull(gMainHwnd) then
        return nil, "SetTitle failed"
    end

    local titleWide = ToWide(cTitle)
    local resultValue = user32.SetWindowTextW(gMainHwnd, titleWide)

    if resultValue == 0 then return nil, "SetTitle failed" end
    return true
end

local function ReadWindowText(hwnd)
    kernel32.SetLastError(0)
    local length = user32.GetWindowTextLengthW(hwnd)
    if length == 0 and kernel32.GetLastError() ~= 0 then return nil, "GetWindowTextLengthW failed" end
    local data = ffi.new("WCHAR[?]", length + 1)
    kernel32.SetLastError(0)
    if user32.GetWindowTextW(hwnd, data, length + 1) == 0 and kernel32.GetLastError() ~= 0 then
        return nil, "GetWindowTextW failed"
    end
    return FromWide(data)
end

function TitleGet()
    if IsNull(gMainHwnd) then return nil end
    return ReadWindowText(gMainHwnd)
end

-- Native MessageBox does not guarantee owner-relative placement.
local function ShowCenteredMessageBox(owner, textWide, titleWide, flags)
    if IsNull(owner) then return user32.MessageBoxW(nil, textWide, titleWide, flags) end
    local state = gMessageBoxCenter
    -- A failed unhook must never leave a freed Lua callback in the native chain.
    for i = #state.pending, 1, -1 do
        if user32.UnhookWindowsHookEx(state.pending[i]) == 0 then
            return nil, "Could not remove the previous MessageBox positioning hook"
        end
        table.remove(state.pending, i)
    end
    if state.Callback == nil then
        local CallNext = user32.CallNextHookEx
        state.Callback = ffi.cast("GuiMessageBoxHookProc", function(code, wparam, lparam)
            local frame = state.stack[#state.stack]
            if code == 5 and frame and not frame.positioned then -- HCBT_ACTIVATE
                local ok, err = pcall(function()
                    local dialog = ffi.cast("HWND", wparam)
                    if user32.GetWindow(dialog, 4) ~= frame.owner then return end -- GW_OWNER
                    local className = ffi.new("WCHAR[16]")
                    if user32.GetClassNameW(dialog, className, 16) ~= 6 or FromWide(className) ~= "#32770" then return end
                    frame.positioned = true -- preserve later user movement and activation
                    local parentRect, dialogRect = ffi.new("RECT[1]"), ffi.new("RECT[1]")
                    if user32.GetWindowRect(frame.owner, parentRect) == 0 or user32.GetWindowRect(dialog, dialogRect) == 0 then
                        error("Could not measure the MessageBox or its owner")
                    end
                    local width = tonumber(dialogRect[0].right - dialogRect[0].left)
                    local height = tonumber(dialogRect[0].bottom - dialogRect[0].top)
                    local x = math.floor((parentRect[0].left + parentRect[0].right - width) / 2)
                    local y = math.floor((parentRect[0].top + parentRect[0].bottom - height) / 2)
                    local monitor = user32.MonitorFromWindow(frame.owner, 2)
                    local info = ffi.new("MONITORINFO[1]")
                    info[0].cbSize = ffi.sizeof("MONITORINFO")
                    if IsNull(monitor) or user32.GetMonitorInfoW(monitor, info) == 0 then
                        error("Could not determine the owner monitor work area")
                    end
                    local work = info[0].rcWork
                    x = math.max(tonumber(work.left), math.min(x, tonumber(work.right) - width))
                    y = math.max(tonumber(work.top), math.min(y, tonumber(work.bottom) - height))
                    if user32.SetWindowPos(dialog, nil, x, y, 0, 0, 0x0015) == 0 then -- NOSIZE|NOZORDER|NOACTIVATE
                        error("Could not center the MessageBox on its owner")
                    end
                end)
                if not ok then frame.error = tostring(err) end
            end
            return CallNext(nil, code, wparam, lparam)
        end)
    end
    local frame = {owner = owner}
    state.stack[#state.stack + 1] = frame
    local hook = user32.SetWindowsHookExW(5, state.Callback, nil, kernel32.GetCurrentThreadId())
    if IsNull(hook) then
        state.stack[#state.stack] = nil
        return nil, "SetWindowsHookExW failed for MessageBox positioning"
    end
    -- MessageBoxW may re-enter Lua; cleanup is required even on a Lua/FFI error.
    local ok, result = pcall(user32.MessageBoxW, owner, textWide, titleWide, flags)
    local nativeError = ok and result == 0 and tonumber(kernel32.GetLastError()) or nil
    local removed = user32.UnhookWindowsHookEx(hook) ~= 0
    state.stack[#state.stack] = nil
    if not removed then
        state.pending[#state.pending + 1] = hook
        return nil, "UnhookWindowsHookEx failed after MessageBox"
    end
    if not ok then return nil, tostring(result) end
    if nativeError then return nil, "MessageBoxW failed (Win32 error " .. nativeError .. ")" end
    if frame.error then return nil, frame.error end
    return result
end

-- Optional string button/icon modes; compare results with gui.Answer.Yes, etc.
-- Native numeric result IDs and nil, error returns are unchanged.
function MessageBox(cText, cTitle, buttons, icon, defaultButton)
    if buttons == nil then buttons = "ok" end
    if icon == nil then icon = "information" end
    if defaultButton == nil then defaultButton = 1 end
    local sets = {
        ["ok"] = {0, 1}, ["ok-cancel"] = {1, 2},
        ["abort-retry-ignore"] = {2, 3}, ["yes-no-cancel"] = {3, 3},
        ["yes-no"] = {4, 2}, ["retry-cancel"] = {5, 2},
        ["cancel-try-continue"] = {6, 3}
    }
    local icons = {none = 0, error = 0x10, question = 0x20, warning = 0x30, information = 0x40}
    if type(buttons) ~= "string" or not sets[buttons] then
        return nil, "unknown MessageBox button set"
    end
    if type(icon) ~= "string" or icons[icon] == nil then
        return nil, "unknown MessageBox icon"
    end
    local selected = sets[buttons]
    if type(defaultButton) ~= "number" or defaultButton ~= math.floor(defaultButton) or
       defaultButton < 1 or defaultButton > selected[2] then
        return nil, "MessageBox default button must be an integer from 1 to " .. selected[2]
    end
    local textWide = ToWide(cText)
    local titleWide = ToWide(cTitle)
    local flags = bit.bor(selected[1], icons[icon], (defaultButton - 1) * 0x100)
    local result, centerError = ShowCenteredMessageBox(gMainHwnd, textWide, titleWide, flags)
    if result == nil then return nil, centerError end
    if result == 0 then
        return nil, "MessageBoxW failed (Win32 error " .. tonumber(kernel32.GetLastError()) .. ")"
    end
    return result
end

function OnClose(CHandlerName)
    if CHandlerName ~= nil and type(CHandlerName) ~= "function" and type(CHandlerName) ~= "string" then
        return nil, "handler must be a function, global name or nil"
    end
    GCloseHandler = CHandlerName
    return true
end

function OnDropFiles(NIdOrHandler, CHandlerName)
    if type(NIdOrHandler) == "number" then
        local Id, hwnd = NIdOrHandler, HandleGet(NIdOrHandler)
        if not hwnd then return nil, "OnDropFiles: control does not exist" end
        if CHandlerName ~= nil and CHandlerName ~= false and type(CHandlerName) ~= "function" and type(CHandlerName) ~= "string" then
            return nil, "handler must be a function, global name, nil (inherit), or false (disable)"
        end
        local old = gDropFilesHandlers[Id]
        gDropFilesHandlers[Id] = CHandlerName
        local ok, err
        if CHandlerName ~= nil or GDropFilesHandler ~= nil then
            ok, err = RegisterDropTarget(hwnd, Id, false)
        else
            ok, err = UnregisterDropTarget(hwnd)
        end
        if not ok then gDropFilesHandlers[Id] = old; return nil, err end
        return true
    end
    if NIdOrHandler ~= nil and type(NIdOrHandler) ~= "function" and type(NIdOrHandler) ~= "string" then
        return nil, "handler must be a function, global name or nil"
    end
    local Old = GDropFilesHandler
    GDropFilesHandler = NIdOrHandler
    local ok, err = SyncDropTargets()
    if not ok then
        GDropFilesHandler = Old
        local restored, restoreErr = SyncDropTargets()
        return nil, err .. (not restored and ("; rollback: " .. restoreErr) or "")
    end
    return true
end

function Close()
    if IsNull(gMainHwnd) then
        return nil, "Close failed"
    end

    local dropOk, dropErr = UnregisterAllDropTargets()
    if not dropOk then return nil, dropErr end
    local resultValue = user32.DestroyWindow(gMainHwnd)
    if resultValue == 0 then return nil, "Close failed" end
    return true
end

function FontChoose()
    local logFontData = ffi.new("LOGFONTW[1]")
    local chooseData = ffi.new("CHOOSEFONTW[1]")

    chooseData[0].lStructSize = ffi.sizeof("CHOOSEFONTW")
    chooseData[0].hwndOwner = gMainHwnd
    chooseData[0].lpLogFont = logFontData
    chooseData[0].Flags = C.CF_SCREENFONTS + C.CF_EFFECTS
    chooseData[0].rgbColors = 0

    if comdlg32.ChooseFontW(chooseData) == 0 then
        return DialogFailure()
    end

    local fontName = FromWide(logFontData[0].lfFaceName)
    local fontSize = tonumber(chooseData[0].iPointSize) / 10
    local fontWeight = tonumber(logFontData[0].lfWeight)
    local italicValue = tonumber(logFontData[0].lfItalic)
    local colorValue = tonumber(chooseData[0].rgbColors)

    return {
        fontName,
        fontSize,
        fontWeight >= 700 and "bold" or "normal",
        italicValue ~= 0 and "italic" or "normal",
        colorValue
    }
end

function OnClick(nId, CHandlerName)
    return HandlerSet(gClickHandlers, nId, CHandlerName)
end

function OnChange(nId, CHandlerName)
    return HandlerSet(gChangeHandlers, nId, CHandlerName)
end

function OnSelect(nId, CHandlerName)
    return HandlerSet(gSelectHandlers, nId, CHandlerName)
end

function HandlerSet(aHandlers, nId, CHandlerName)
    if type(aHandlers) ~= "table" then return nil, "handlers must be a table" end
    if type(nId) ~= "number" or nId ~= math.floor(nId) or nId < 1 or nId > 65535 then
        return nil, "handler ID must be in 1..65535"
    end
    if CHandlerName ~= nil and type(CHandlerName) ~= "function" and type(CHandlerName) ~= "string" then
        return nil, "handler must be a function, global name or nil"
    end
    aHandlers[nId] = CHandlerName
    return true
end

function HandlerDispatch(aHandlers, nId)
    if type(aHandlers) ~= "table" then return nil, "handlers must be a table" end
    local handlerValue = aHandlers[nId]

    if handlerValue == nil then
        return 0
    end

    return CallHandler(handlerValue, ControlPublicName(nId))
end

local function RescaleControlsForDpi()
    for controlId, rectData in pairs(gControlRects) do
        local targetHwnd = gControlList[controlId]
        if not IsNull(targetHwnd) then
            user32.MoveWindow(
                targetHwnd,
                ScaleLogical(rectData.x, gCurrentDpi),
                ScaleLogical(rectData.y, gCurrentDpi),
                ScaleLogical(rectData.width, gCurrentDpi),
                ScaleLogical(rectData.height, gCurrentDpi),
                1
            )
        end
    end
end

local function RescaleListViewColumnsForDpi()
    for controlId, columnWidths in pairs(gListViewColumnWidths) do
        local targetHwnd = gControlList[controlId]
        if not IsNull(targetHwnd) then
            for columnIndex, logicalWidth in ipairs(columnWidths) do
                user32.SendMessageW(
                    targetHwnd,
                    C.LVM_SETCOLUMNWIDTH,
                    columnIndex - 1,
                    ScaleLogical(logicalWidth, gCurrentDpi)
                )
            end
        end
    end
end

local function ResetGuiState()
    ReleaseTabThemes()
    if gIconManager then gIconManager.Release(gMainHwnd, true) end
    local dropOk, dropErr = ShutdownOleDrop()
    if not dropOk then ReportGuiError(dropErr .. "\n") end
    gMainHwnd = nil
    local fontsOk, fontsErr = FontsDelete()
    if not fontsOk then ReportGuiError(fontsErr .. "\n") end
    gControlList = {}
    gLabelStyles = {}
    gControlRects = {}
    gControlFontSpecs = {}
    gControlExternalFonts = {}
    gControlAutoFonts = {}
    gClickHandlers = {}
    gChangeHandlers = {}
    gSelectHandlers = {}
    gListViewColumnCounts = {}
    gListViewColumnWidths = {}
    gCurrentDpi = C.DEFAULT_DPI
    gTabPages = {}
    gTabPageControls = {}
    gTabThemes = {}
    gTextBackgroundControls = {}
    gGroupBoxControls = {}
    gMenuHandlers = {}
    GCloseHandler = nil
    GDropFilesHandler = nil
    gDropFilesHandlers = {}
    -- Failed revocations and externally referenced COM objects must retain their roots.
    gTooltipHwnd = nil
    gTooltipTexts = {}
    gOldWndProc = nil
    gWindowLogicalSize = nil
    gUserResized = false
    gClosing = false
end

function WndProc(pHwnd, nMsg, cWParam, pLParam)
    -- GroupBox (BS_GROUPBOX) does not always honor WM_CTLCOLORSTATIC with
    -- visual styles.  Its transparent themed caption instead samples parent
    -- background via these two messages.  Paint the actual TABP_PANE there.
    if nMsg == C.WM_PRINTCLIENT or nMsg == C.WM_ERASEBKGND then
        if PaintDialogAndTabPages(ffi.cast("HDC", cWParam)) then
            return 1
        end
    end
    if nMsg == 0x214 then gUserResized = true end -- WM_SIZING
    if nMsg == 0x232 and gUserResized and gWindowLogicalSize then -- WM_EXITSIZEMOVE
        local r = ffi.new("RECT[1]")
        local measured
        if gWindowLogicalSize.client then
            measured = user32.GetClientRect(pHwnd, r)
        else
            measured = user32.GetWindowRect(pHwnd, r)
        end
        if measured ~= 0 then
            gWindowLogicalSize.width = (r[0].right - r[0].left) * 96 / gCurrentDpi
            gWindowLogicalSize.height = (r[0].bottom - r[0].top) * 96 / gCurrentDpi
        end
        gUserResized = false
    end
    if nMsg == 0x2E4 and pLParam ~= 0 and gWindowLogicalSize and not gUserResized then
        if gWindowLogicalSize.client then return 0 end
        local size = ffi.cast("long*", pLParam) -- SIZE { LONG cx, cy }
        size[0] = ScaleLogical(gWindowLogicalSize.width, tonumber(cWParam))
        size[1] = ScaleLogical(gWindowLogicalSize.height, tonumber(cWParam))
        return 1
    end
    if nMsg == C.WM_DPICHANGED then
        ReleaseTabThemes()
        local dpiPacked = tonumber(cWParam)
        ---@cast dpiPacked integer
        local newDpi = bit.band(dpiPacked, 0xFFFF)

        if newDpi > 0 then
            gCurrentDpi = newDpi
        end

        if pLParam ~= 0 then
            local suggestedRect = ffi.cast("RECT*", pLParam)
            ---@cast suggestedRect GuiRect
            user32.SetWindowPos(
                pHwnd,
                nil,
                suggestedRect.left,
                suggestedRect.top,
                suggestedRect.right - suggestedRect.left,
                suggestedRect.bottom - suggestedRect.top,
                C.SWP_NOZORDER + C.SWP_NOACTIVATE
            )
        end

        if gWindowLogicalSize and gWindowLogicalSize.client and not gUserResized then
            local ok, err = FitWindowToClient(pHwnd, gWindowLogicalSize.width, gWindowLogicalSize.height)
            if not ok then ReportGuiError("DPI client area: " .. err .. "\n") end
        end

        RescaleControlsForDpi()
        RescaleListViewColumnsForDpi()
        local ok, err = RescaleFontsForDpi()
        if not ok then ReportGuiError("DPI fonts: " .. err .. "\n") end
        return 0
    end

    -- With visual styles the tab page may differ from dialog gray.
    -- WM_CTLCOLORSTATIC supplies the actual child DC: painting the themed TABP_PANE
    -- and returning NULL_BRUSH prevents a later background brush from covering it.
    if nMsg == C.WM_CTLCOLORSTATIC or nMsg == C.WM_CTLCOLORBTN then
        if pLParam ~= 0 then
            local controlHwnd = ffi.cast("HWND", pLParam)
            local controlId = tonumber(user32.GetDlgCtrlID(controlHwnd))
            local labelStyle = gLabelStyles[controlId]
            local isLabel = nMsg == C.WM_CTLCOLORSTATIC and labelStyle and labelStyle.hwnd == controlHwnd
            local labelColor = isLabel and labelStyle.color or nil
            local labelDefaultResult
            if isLabel then
                -- Establish system text defaults even for a shared/printing DC.
                if gOldWndProc ~= nil then
                    labelDefaultResult = user32.CallWindowProcW(gOldWndProc, pHwnd, nMsg, cWParam, pLParam)
                else
                    labelDefaultResult = user32.DefWindowProcW(pHwnd, nMsg, cWParam, pLParam)
                end
            end
            local tabId = gTabPageControls[controlId]
            if tabId ~= nil and gTextBackgroundControls[controlId] then
                local tabHwnd = gControlList[tabId]
                local hdc = ffi.cast("HDC", cWParam)
                if not IsNull(tabHwnd) and user32.IsWindow(tabHwnd) ~= 0 and
                    PaintTabBackground(tabId, tabHwnd, controlHwnd, hdc) then
                    gdi32.SetBkMode(hdc, C.TRANSPARENT)
                    if labelColor ~= nil then gdi32.SetTextColor(hdc, labelColor) end
                    return PtrToLParam(gdi32.GetStockObject(C.NULL_BRUSH))
                end
                -- System-color fallback for disabled themes or unavailable TAB parts.
                gdi32.SetBkColor(hdc, user32.GetSysColor(C.COLOR_WINDOW))
                if labelColor ~= nil then gdi32.SetTextColor(hdc, labelColor) end
                return PtrToLParam(user32.GetSysColorBrush(C.COLOR_WINDOW))
            end
            if isLabel then
                if labelColor ~= nil then gdi32.SetTextColor(ffi.cast("HDC", cWParam), labelColor) end
                return labelDefaultResult
            end
        end
    end

    if nMsg == C.WM_THEMECHANGED then
        ReleaseTabThemes()
        for controlId, tabId in pairs(gTabPageControls) do
            local hwnd = gControlList[controlId]
            if not IsNull(hwnd) then user32.InvalidateRect(hwnd, nil, 1) end
        end
    end

    if nMsg == C.WM_COMMAND then
        local commandValue = tonumber(cWParam)
        local controlId = commandValue % 65536
        local notifyCode = math.floor(commandValue / 65536) % 65536

        if pLParam == 0 then
            if HandlerDispatch(gMenuHandlers, controlId) ~= 0 then
                return 0
            end
        else
            if notifyCode == C.BN_CLICKED then
                if HandlerDispatch(gClickHandlers, controlId) ~= 0 then
                    return 0
                end
            end

            if notifyCode == C.EN_CHANGE then
                if HandlerDispatch(gChangeHandlers, controlId) ~= 0 then
                    return 0
                end
            end

            if notifyCode == C.CBN_SELCHANGE then
                if HandlerDispatch(gSelectHandlers, controlId) ~= 0 then
                    return 0
                end
            end
        end
    end

    if nMsg == C.WM_NOTIFY then
        if pLParam ~= 0 then
            local headerData = ffi.cast("NMHDR*", pLParam)
            ---@cast headerData GuiNotifyHeader
            local controlId = tonumber(headerData.idFrom)
            local notifyCode = SignedNotifyCode(headerData.code)

            if notifyCode == C.TCN_SELCHANGE then
                TabPagesUpdate(controlId)

                if HandlerDispatch(gSelectHandlers, controlId) ~= 0 then
                    return 0
                end
            end

            if notifyCode == C.LVN_ITEMCHANGED then
                local listData = ffi.cast("NMLISTVIEW*", pLParam)
                ---@cast listData GuiListNotify
                local stateChanged = bit.band(tonumber(listData.uChanged) --[[@as integer]], C.LVIF_STATE) ~= 0
                local wasSelected = bit.band(tonumber(listData.uOldState) --[[@as integer]], C.LVIS_SELECTED) ~= 0
                local isSelected = bit.band(tonumber(listData.uNewState) --[[@as integer]], C.LVIS_SELECTED) ~= 0

                if stateChanged and not wasSelected and isSelected then
                    if HandlerDispatch(gSelectHandlers, controlId) ~= 0 then
                        return 0
                    end
                end
            end

            if notifyCode == C.TVN_SELCHANGEDW then
                if HandlerDispatch(gSelectHandlers, controlId) ~= 0 then
                    return 0
                end
            end
        end
    end

    if nMsg == C.WM_HSCROLL then
        if pLParam ~= 0 then
            local controlHwnd = ffi.cast("HWND", pLParam)
            local controlId = user32.GetDlgCtrlID(controlHwnd)

            if controlId > 0 then
                if HandlerDispatch(gChangeHandlers, controlId) ~= 0 then
                    return 0
                end
            end
        end
    end

    if nMsg == C.WM_CLOSE then
        if gClosing then return 0 end
        gClosing = true
        if GCloseHandler ~= nil then
            if not CallCloseHandler(GCloseHandler) then
                gClosing = false
                return 0
            end
        end

        if user32.IsWindow(pHwnd) ~= 0 then
            local ok, err = Close()
            if not ok then gClosing = false; ReportGuiError(err .. "\n") end
        end
        return 0
    end

    if nMsg == C.WM_DESTROY then
        local revoked, revokeErr = UnregisterAllDropTargets()
        if not revoked then ReportGuiError(revokeErr .. "\n") end
        local roots = {}
        for _, r in pairs(gMenus) do
            if not r.parent then roots[#roots + 1] = r.handle end
        end
        for _, h in ipairs(roots) do
            local ok, err = MenuDestroy(h)
            if not ok then ReportGuiError("Menu cleanup: " .. err .. "\n") end
        end
        gQuitPending = true
        user32.PostQuitMessage(0)
        return 0
    end

    if nMsg == C.WM_NCDESTROY then
        local oldProcValue = gOldWndProc
        local resultValue

        if oldProcValue ~= nil then
            resultValue = user32.CallWindowProcW(oldProcValue, pHwnd, nMsg, cWParam, pLParam)
        else
            resultValue = user32.DefWindowProcW(pHwnd, nMsg, cWParam, pLParam)
        end

        ResetGuiState()
        return resultValue
    end

    if gOldWndProc ~= nil then
        return user32.CallWindowProcW(gOldWndProc, pHwnd, nMsg, cWParam, pLParam)
    end

    return user32.DefWindowProcW(pHwnd, nMsg, cWParam, pLParam)
end

ForgetDestroyedControl = function(NId, hwnd)
    if not IsNull(hwnd) then
        local ok, err = UnregisterDropTarget(hwnd)
        if not ok then ReportGuiError(err .. "\n") end
    end
    gControlList[NId] = nil
    gLabelStyles[NId] = nil
    gControlRects[NId] = nil
    gTabPageControls[NId] = nil
    if gTabThemes[NId] then
        uxtheme.CloseThemeData(gTabThemes[NId])
        gTabThemes[NId] = nil
    end
    gTextBackgroundControls[NId] = nil
    gClickHandlers[NId] = nil
    gChangeHandlers[NId] = nil
    gSelectHandlers[NId] = nil
    gDropFilesHandlers[NId] = nil
    gControlFontSpecs[NId] = nil
    gControlExternalFonts[NId] = nil
    gControlAutoFonts[NId] = nil
    gListViewColumnCounts[NId] = nil
    gListViewColumnWidths[NId] = nil
    gTooltipTexts[NId] = nil
end

function HandleGet(NId)
    local hwnd = gControlList[NId]
    if IsNull(hwnd) then return nil end
    if user32.IsWindow(hwnd) == 0 then
        ForgetDestroyedControl(NId, hwnd)
        return nil
    end
    return hwnd
end

function IsValidControlId(NId)
    local okValue = ValidateControlId(NId, false)
    return okValue == true
end

function TextSet(nId, cText)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "SetText failed"
    end

    local textWide = ToWide(cText)
    local resultValue = user32.SetWindowTextW(targetHwnd, textWide)

    if resultValue == 0 then return nil, "SetText failed" end
    return true
end

-- Set Edit text, scroll horizontally to show its end and hide a focused caret.
-- This does not change focus if another control already has it.
function TextEndSet(nId, cText)
    local targetHwnd = HandleGet(nId)
    if IsNull(targetHwnd) then
        return nil, "SetTextEnd: control does not exist"
    end

    local ok, err = TextSet(nId, cText)
    if not ok then return nil, err end

    local length = user32.GetWindowTextLengthW(targetHwnd)
    user32.SendMessageW(targetHwnd, C.EM_SETSEL, length, length)
    user32.SendMessageW(targetHwnd, C.EM_SCROLLCARET, 0, 0)

    if user32.GetFocus() == targetHwnd and not IsNull(gMainHwnd) then
        user32.SetFocus(gMainHwnd)
    end

    return true
end

function TextGet(nId)
    local hwnd = HandleGet(nId)
    if not hwnd then return nil, "control does not exist" end
    return ReadWindowText(hwnd)
end

function IsChecked(nId)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return false
    end

    local checkValue = tonumber(user32.SendMessageW(targetHwnd, C.BM_GETCHECK, 0, 0))

    if checkValue == C.BST_CHECKED then
        return true
    end

    return false
end

function CheckedSet(nId, nState)
    local targetHwnd = HandleGet(nId)

    if IsNull(targetHwnd) then
        return nil, "SetChecked failed"
    end

    local checkState = 0

    if IsEnabledFlag(nState) then
        checkState = 1
    end

    user32.SendMessageW(targetHwnd, C.BM_SETCHECK, checkState, 0)
    return true
end

function Run()
    local messageData = ffi.new("MSG[1]")
    local clipboardUpdate = require("_clipboard_watch").Dispatch

    while true do
        if gOleShutdownPending and gDropCallbackDepth == 0 then
            local ok, err = ShutdownOleDrop()
            if not ok then return nil, err end
        end
        local messageResult = user32.GetMessageW(messageData, nil, 0, 0)

        if messageResult == -1 then return nil, "GetMessageW failed" end
        if messageResult == 0 then gQuitPending = false; return tonumber(messageData[0].wParam) end

        if not clipboardUpdate(messageData[0].hwnd, messageData[0].message)
            and (IsNull(gMainHwnd) or user32.IsDialogMessageW(gMainHwnd, messageData) == 0) then
            user32.TranslateMessage(messageData)
            user32.DispatchMessageW(messageData)
        end
    end
end

GWndProcCallback = ffi.cast("WNDPROC", function(pHwnd, nMsg, cWParam, pLParam)
    local okValue, resultValue = pcall(WndProc, pHwnd, nMsg, cWParam, pLParam)

    if okValue then
        return resultValue
    end

    ReportGuiError("WndProc error: " .. SafeErrorText(resultValue) .. "\n")

    if gOldWndProc ~= nil then
        return user32.CallWindowProcW(gOldWndProc, pHwnd, nMsg, cWParam, pLParam)
    end

    return user32.DefWindowProcW(pHwnd, nMsg, cWParam, pLParam)
end)

local api = {
    Window = Window,
    WindowClient = WindowClient,
    WindowTopmostSet = WindowTopmostSet,
    ScreenSizeGet = ScreenSizeGet,
    TaskbarHeightGet = TaskbarHeightGet,
    ScreenInfoGet = ScreenInfoGet,
    ControlCreate = ControlCreate,
    IconSet = IconSet,
    FontCreate = FontCreate,
    FontSet = FontSet,
    FontStyleSet = FontStyleSet,
    FontSizeSet = FontSizeSet,
    DefaultFontSet = DefaultFontSet,
    FontsDelete = FontsDelete,
    Label = Label,
    TextColorSet = TextColorSet,
    Button = Button,
    DefaultButton = DefaultButton,
    Edit = Edit,
    EditMulti = EditMulti,
    EditReadOnly = EditReadOnly,
    EditPassword = EditPassword,
    CheckBox = CheckBox,
    RadioButton = RadioButton,
    GroupBox = GroupBox,
    ComboBox = ComboBox,
    ComboAdd = ComboAdd,
    ComboItemsSet = ComboItemsSet,
    ComboSelectedSet = ComboSelectedSet,
    ComboSelectedGet = ComboSelectedGet,
    ComboSelectedTextGet = ComboSelectedTextGet,
    ListBox = ListBox,
    ListAdd = ListAdd,
    ListItemsSet = ListItemsSet,
    ListSelectedSet = ListSelectedSet,
    ListSelectedGet = ListSelectedGet,
    ListSelectedTextGet = ListSelectedTextGet,
    ProgressBar = ProgressBar,
    ProgressSet = ProgressSet,
    Slider = Slider,
    SliderSet = SliderSet,
    SliderGet = SliderGet,
    Tab = Tab,
    TabButtons = TabButtons,
    TabAdd = TabAdd,
    TabSelectedGet = TabSelectedGet,
    TabSelectedSet = TabSelectedSet,
    OnTabChange = OnTabChange,
    TabPage = TabPage,
    TabPagesUpdate = TabPagesUpdate,
    ListView = ListView,
    ListViewColumnAdd = ListViewColumnAdd,
    ListViewAdd = ListViewAdd,
    ListViewSelectedGet = ListViewSelectedGet,
    ListViewTextGet = ListViewTextGet,
    ListViewColumnCountGet = ListViewColumnCountGet,
    ListViewColumnCountSet = ListViewColumnCountSet,
    OnListViewSelect = OnListViewSelect,
    TreeView = TreeView,
    TreeRootAdd = TreeRootAdd,
    TreeChildAdd = TreeChildAdd,
    TreeInsert = TreeInsert,
    TreeSelectedGet = TreeSelectedGet,
    TreeTextGet = TreeTextGet,
    TreeExpand = TreeExpand,
    OnTreeSelect = OnTreeSelect,
    StatusBar = StatusBar,
    StatusTextSet = StatusTextSet,
    ToolTip = ToolTip,
    MenuDestroy = MenuDestroy,
    MenuBar = MenuBar,
    Menu = Menu,
    MenuAdd = MenuAdd,
    MenuSubAdd = MenuSubAdd,
    MenuSeparator = MenuSeparator,
    MenuSet = MenuSet,
    OnMenu = OnMenu,
    FileOpen = FileOpen,
    FileSave = FileSave,
    FolderChoose = FolderChoose,
    ColorChoose = ColorChoose,
    Enable = Enable,
    Show = Show,
    Move = Move,
    FocusSet = FocusSet,
    TitleSet = TitleSet,
    TitleGet = TitleGet,
    MessageBox = MessageBox,
    -- Named MessageBox results; values match the native Win32 IDs.
    Answer = {
        Ok = 1, Cancel = 2, Abort = 3, Retry = 4, Ignore = 5,
        Yes = 6, No = 7, TryAgain = 10, Continue = 11
    },
    OnClose = OnClose,
    OnDropFiles = OnDropFiles,
    Close = Close,
    FontChoose = FontChoose,
    OnClick = OnClick,
    OnChange = OnChange,
    OnSelect = OnSelect,
    ErrorHandlerSet = ErrorHandlerSet,
    ErrorGet = ErrorGet,
    HandlerSet = HandlerSet,
    HandlerDispatch = HandlerDispatch,
    WndProc = WndProc,
    HandleGet = HandleGet,
    IsValidControlId = IsValidControlId,
    TextSet = TextSet,
    TextEndSet = TextEndSet,
    WideTextMake = WideTextMake,
    TextGet = TextGet,
    IsChecked = IsChecked,
    CheckedSet = CheckedSet,
    Run = Run
}

local function PackResults(...)
    return {n = select("#", ...), ...}
end
for name, fn in pairs(api) do
    if type(fn) == "function" then jit.off(fn, true) end
    if type(fn) == "function" and name ~= "WndProc" and name ~= "HandlerDispatch" then
        local original = fn
        local function Checked(...)
            local results = PackResults(pcall(original, ...))
            if not results[1] then return nil, dialogErrors.Message(results[2]) end
            return unpack(results, 2, results.n)
        end
        jit.off(Checked, true)
        api[name] = Checked
        _G[name] = Checked
    end
end
-- Names are resolved only at the public boundary; WinAPI/DLL IDs stay numeric.
local function InstallNamedControls(api)
    local byName, byId, menuIds = {}, {}, {}
    local RawGetHandle = api.HandleGet
    local function Reset()
        byName, byId, menuIds = {}, {}, {}
    end
    local function Resolve(Ref)
        if type(Ref) ~= 'string' then return Ref end
        local record = byName[Ref]
        if record and RawGetHandle(record.id) == record.hwnd then return record.id end
        if record then byName[Ref], byId[record.id] = nil, nil end
        return nil, 'unknown control name: ' .. Ref
    end
    local function PublicName(id) return byId[id] or id end
    local creators = {
        'ControlCreate','Label','Button','DefaultButton','Edit','EditMulti',
        'EditReadOnly','EditPassword','CheckBox','RadioButton','GroupBox',
        'ComboBox','ListBox','ProgressBar','Slider','Tab','TabButtons',
        'ListView','TreeView','StatusBar'
    }
    for _, name in ipairs(creators) do
        local Original = api[name]
        if Original then
            api[name] = function(ref, ...)
                if type(ref) ~= 'string' then return Original(ref, ...) end
                if ref == '' or ref:find('\0', 1, true) then
                    return nil, 'control name must be nonempty and contain no NUL'
                end
                if Resolve(ref) then return nil, 'duplicate control name: ' .. ref end
                local id = 100
                while id <= 65535 and (RawGetHandle(id) or byId[id] or menuIds[id]) do id = id + 1 end
                if id > 65535 then return nil, 'no free control IDs' end
                local result, err = Original(id, ...)
                if not result then return nil, err end
                local hwnd = RawGetHandle(id)
                if not hwnd then return nil, 'created control has no live handle' end
                byName[ref], byId[id] = {id=id, hwnd=hwnd}, ref
                return result
            end
        end
    end
    local operations = {
        'HandleGet','FontSet','FontStyleSet','FontSizeSet','TextColorSet','ComboAdd','ComboItemsSet',
        'ComboSelectedSet','ComboSelectedGet','ComboSelectedTextGet','ListAdd',
        'ListItemsSet','ListSelectedSet','ListSelectedGet','ListSelectedTextGet',
        'ProgressSet','SliderSet','SliderGet','TabAdd','TabSelectedGet','TabSelectedSet',
        'OnTabChange','TabPagesUpdate','ListViewColumnAdd','ListViewAdd',
        'ListViewSelectedGet','ListViewTextGet','ListViewColumnCountGet',
        'ListViewColumnCountSet','OnListViewSelect','TreeRootAdd','TreeChildAdd',
        'TreeInsert','TreeSelectedGet','TreeTextGet','TreeExpand','OnTreeSelect',
        'StatusTextSet','ToolTip','Enable','Show','Move','FocusSet','OnClick',
        'OnChange','OnSelect','TextSet','TextEndSet','TextGet','IsChecked',
        'CheckedSet','DropEnable','OnDrop'
    }
    for _, name in ipairs(operations) do
        local Original = api[name]
        if Original then
            api[name] = function(ref, ...)
                local Id, err = Resolve(ref)
                if Id == nil then return nil, err or 'control reference is required' end
                return Original(Id, ...)
            end
        end
    end
    if api.IsValidControlId then
        local Original = api.IsValidControlId
        api.IsValidControlId = function(Ref)
            local Id = Resolve(Ref)
            return Id ~= nil and Original(Id) or false
        end
    end
    if api.TabPage then
        local Original = api.TabPage
        api.TabPage = function(Ref, page, controls)
            local Id, err = Resolve(Ref)
            if Id == nil then return nil, err end
            if type(controls) ~= 'table' then return nil, 'page controls must be a table' end
            local ids = {}
            for i, control in ipairs(controls) do
                local Value, controlErr = Resolve(control)
                if Value == nil then return nil, controlErr end
                ids[i] = Value
            end
            return Original(Id, page, ids)
        end
    end
    for _, name in ipairs({'HandlerSet','HandlerDispatch'}) do
        local Original = api[name]
        if Original then
            api[name] = function(handlers, ref, ...)
                local Id, err = Resolve(ref)
                if Id == nil then return nil, err end
                return Original(handlers, Id, ...)
            end
        end
    end
    if api.OnDropFiles then
        local Original = api.OnDropFiles
        api.OnDropFiles = function(Ref, ...)
            -- One string keeps its existing meaning: global window handler.
            -- A named control always uses two arguments, including explicit nil.
            if type(Ref) == 'string' and select('#', ...) > 0 then
                local Id, err = Resolve(Ref)
                if Id == nil then return nil, err end
                return Original(Id, ...)
            end
            return Original(Ref, ...)
        end
    end
    if api.MenuAdd then
        local Original = api.MenuAdd
        api.MenuAdd = function(menu, id, ...)
            if byId[id] then return nil, 'menu ID is already used by a named control' end
            local result, err = Original(menu, id, ...)
            if result then menuIds[id] = true end
            return result, err
        end
    end
    for _, name in ipairs({'Window','WindowClient','Close'}) do
        local Original = api[name]
        if Original then
            api[name] = function(...)
                local result, err = Original(...)
                if result then Reset() end
                return result, err
            end
        end
    end
    return PublicName
end

ControlPublicName = InstallNamedControls(api)

for name, fn in pairs(api) do
    if type(fn) == "function" then jit.off(fn, true); _G[name] = fn end
end
return api
