local _source = debug.getinfo(1, 'S').source
local _dir = _source:sub(2):match('^(.*)[/\\]') or '.'
local Bootstrap = loadfile(_dir .. '/_bootstrap.lua') or loadfile(_dir .. '/../_bootstrap.lua')
assert(Bootstrap, 'Keep this example with the FrameWork directory and the included _bootstrap.lua file')
Bootstrap()

local env = require('env')
local key = 'FRAMEWORK_REFERENCE_' .. require('process').IdGet()
local previous = env.Get(key)
assert(env.Set(key, 'Привет'))
assert(env.Get(key) == 'Привет')
print(assert(env.Expand('%' .. key .. '%')))
if previous ~= nil then assert(env.Set(key, previous)) else assert(env.Unset(key)) end
