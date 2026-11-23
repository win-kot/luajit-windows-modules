local _source = debug.getinfo(1, 'S').source
local _dir = _source:sub(2):match('^(.*)[/\\]') or '.'
local Bootstrap = loadfile(_dir .. '/_bootstrap.lua') or loadfile(_dir .. '/../_bootstrap.lua')
assert(Bootstrap, 'Keep this example with the FrameWork directory and the included _bootstrap.lua file')
Bootstrap()

local timer = require('timer')
timer.Start(3)
local total = 0
for i = 1, 100000 do total = total + i end
print(total, assert(timer.Stop()), 'ms')
