local _source = debug.getinfo(1, 'S').source
local _dir = _source:sub(2):match('^(.*)[/\\]') or '.'
local Bootstrap = loadfile(_dir .. '/_bootstrap.lua') or loadfile(_dir .. '/../_bootstrap.lua')
assert(Bootstrap, 'Keep this example with the FrameWork directory and the included _bootstrap.lua file')
Bootstrap()

local p = require('process')
local out, errout, code, pid, timed = p.RunCapture('cmd.exe /d /c echo OK', {timeout=5})
assert(out, errout)
assert(code == 0 and not timed)
print(out, 'PID:', pid)
