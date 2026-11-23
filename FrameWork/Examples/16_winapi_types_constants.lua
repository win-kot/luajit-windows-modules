local _source = debug.getinfo(1, 'S').source
local _dir = _source:sub(2):match('^(.*)[/\\]') or '.'
local Bootstrap = assert(loadfile(_dir .. '/_bootstrap.lua'))
Bootstrap()

-- win_constants loads win_types and returns the same ffi object.
local ffi = require('win_constants')
local bit = require('bit')
ffi.cdef[[DWORD __stdcall GetCurrentProcessId(void);]]
local kernel32 = ffi.load('kernel32')
print('PID:', tonumber(kernel32.GetCurrentProcessId()))
print('WS_CHILD | WS_VISIBLE:', bit.tohex(bit.bor(ffi.C.WS_CHILD, ffi.C.WS_VISIBLE)))
print('CP_UTF8:', ffi.C.CP_UTF8)
local point = ffi.new('POINT', {x=10, y=20})
print('POINT:', tonumber(point.x), tonumber(point.y))
local size = ffi.new('ULARGE_INTEGER', {QuadPart=4294967297ULL})
print('ULARGE_INTEGER:', tonumber(size.LowPart), tonumber(size.u.HighPart))