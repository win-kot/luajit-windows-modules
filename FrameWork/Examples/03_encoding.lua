local _source = debug.getinfo(1, 'S').source
local _dir = _source:sub(2):match('^(.*)[/\\]') or '.'
local Bootstrap = loadfile(_dir .. '/_bootstrap.lua') or loadfile(_dir .. '/../_bootstrap.lua')
assert(Bootstrap, 'Keep this example with the FrameWork directory and the included _bootstrap.lua file')
Bootstrap()

local fs = require('fs')
local filename = assert(require('path').GetTempFile('кодировка-'))
local ok, err = xpcall(function()
    assert(fs.FileWrite(filename, 'Привет, 日本', 'UTF-16LE'))
    assert(fs.FileRead(filename, 'UTF-16LE') == 'Привет, 日本')
end, debug.traceback)
assert(fs.FileDelete(filename))
assert(ok, err)
print('UTF-16LE: OK')
