local _source = debug.getinfo(1, 'S').source
local _dir = _source:sub(2):match('^(.*)[/\\]') or '.'
local Bootstrap = loadfile(_dir .. '/_bootstrap.lua') or loadfile(_dir .. '/../_bootstrap.lua')
assert(Bootstrap, 'Keep this example with the FrameWork directory and the included _bootstrap.lua file')
Bootstrap()

local ffi = require('win_types')
ffi.cdef[[DWORD __stdcall GetCurrentProcessId(void);]]
local dll = ffi.load('kernel32')
local Getpid = dll.GetCurrentProcessId
print('PID:', tonumber(Getpid()))
