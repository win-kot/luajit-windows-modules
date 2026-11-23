local _source = debug.getinfo(1, 'S').source
local _dir = _source:sub(2):match('^(.*)[/\\]') or '.'
local Bootstrap = loadfile(_dir .. '/_bootstrap.lua') or loadfile(_dir .. '/../_bootstrap.lua')
assert(Bootstrap, 'Keep this example with the FrameWork directory and the included _bootstrap.lua file')
Bootstrap()

local kb = require('keyboard')
local mouse = require('mouse')
print('VK CTRL:', assert(kb.KeyCode('CTRL')))
print('Mouse position:', mouse.PositionGet())
