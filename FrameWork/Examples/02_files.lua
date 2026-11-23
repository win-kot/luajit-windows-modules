local _source = debug.getinfo(1, 'S').source
local _dir = _source:sub(2):match('^(.*)[/\\]') or '.'
local Bootstrap = loadfile(_dir .. '/_bootstrap.lua') or loadfile(_dir .. '/../_bootstrap.lua')
assert(Bootstrap, 'Keep this example with the FrameWork directory and the included _bootstrap.lua file')
Bootstrap()

local fs = require('fs')
local filename = assert(require('path').GetTempFile('пример-'))
local ok, err = xpcall(function()
    assert(fs.FileWrite(filename, 'Привет\n日本'))
    local text = assert(fs.FileRead(filename))
    assert(text == 'Привет\n日本')
    -- A CRLF pair counts as one line break.
    assert(fs.FileLineCount(filename) == 2)
    print(text)
    for line in fs.FileReadLine(filename, 'UTF-8') do print(line) end
end, debug.traceback)
assert(fs.FileDelete(filename))
assert(ok, err)
