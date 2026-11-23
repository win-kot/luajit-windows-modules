local _source = debug.getinfo(1, 'S').source
local _dir = _source:sub(2):match('^(.*)[/\\]') or '.'
local Bootstrap = loadfile(_dir .. '/_bootstrap.lua') or loadfile(_dir .. '/../_bootstrap.lua')
assert(Bootstrap, 'Keep this example with the FrameWork directory and the included _bootstrap.lua file')
Bootstrap(false)

local a = require('argv')
print('Program:', assert(a.Program()))
print('Script:', assert(require("app").GetInfo()).L_ScriptPath)
for i, value in ipairs(assert(a.Get())) do print(i, value) end
