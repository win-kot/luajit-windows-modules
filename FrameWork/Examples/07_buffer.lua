local _source = debug.getinfo(1, 'S').source
local _dir = _source:sub(2):match('^(.*)[/\\]') or '.'
local Bootstrap = loadfile(_dir .. '/_bootstrap.lua') or loadfile(_dir .. '/../_bootstrap.lua')
assert(Bootstrap, 'Keep this example with the FrameWork directory and the included _bootstrap.lua file')
Bootstrap()

local cstring_buffer = require('cstring_buffer')
local buffer = assert(cstring_buffer.New(64))
assert(buffer:Set('Привет'))
assert(buffer:ToString() == 'Привет')
print(buffer:ToString())
