local _source = debug.getinfo(1, 'S').source
local _dir = _source:sub(2):match('^(.*)[/\\]') or '.'
local Bootstrap = loadfile(_dir .. '/_bootstrap.lua') or loadfile(_dir .. '/../_bootstrap.lua')
assert(Bootstrap, 'Keep this example with FrameWork and _bootstrap.lua')
Bootstrap()

local zip = require('zip')
local fs = require('fs')
local folder = assert(fs.TempDirCreate())
local source = fs.PathJoin(folder, 'Исходники 日本')
local archive = fs.PathJoin(folder, 'Отчёт O’Neil.zip')
local destination = fs.PathJoin(folder, 'Распаковано 日本')

assert(fs.DirCreate(fs.PathJoin(source, 'cache')))
assert(fs.DirCreate(fs.PathJoin(source, 'пустая')))
assert(fs.FileWrite(fs.PathJoin(source, 'Привет.txt'), 'Привет, 日本!'))
assert(fs.FileWrite(fs.PathJoin(source, 'debug.log'), 'Log'))
assert(fs.FileWrite(fs.PathJoin(source, 'cache', 'data.txt'), 'Cache'))

local ok, err = zip.Create(source, archive)
assert(ok, err)
local entries = assert(zip.List(archive))
assert(#entries > 0)
ok, err = zip.Extract(archive, destination)
assert(ok, err)
local restored = fs.PathJoin(destination, 'Исходники 日本')
assert(fs.FileRead(fs.PathJoin(restored, 'Привет.txt')) == 'Привет, 日本!')
assert(fs.FileExists(fs.PathJoin(restored, 'debug.log')))
assert(fs.DirExists(fs.PathJoin(restored, 'cache')))
assert(fs.DirExists(fs.PathJoin(restored, 'пустая')))

-- Select one file and retain its path relative to the ZIP root.
local single = fs.PathJoin(folder, 'Один файл 日本')
ok, err = zip.Extract(archive, single, {include = {'Исходники 日本/Привет.txt'}})
assert(ok, err)
assert(fs.FileRead(fs.PathJoin(single, 'Исходники 日本', 'Привет.txt')) == 'Привет, 日本!')

-- Select the directory contents, then exclude logs and the cache directory.
local batch = fs.PathJoin(folder, 'Выбранные файлы 日本')
ok, err = zip.Extract(archive, batch, {
    include = {'Исходники 日本/'},
    exclude = {'*.log', 'Исходники 日本/cache/'},
    overwrite = true
})
assert(ok, err)
local selected = fs.PathJoin(batch, 'Исходники 日本')
assert(fs.FileRead(fs.PathJoin(selected, 'Привет.txt')) == 'Привет, 日本!')
assert(not fs.FileExists(fs.PathJoin(selected, 'debug.log')))
assert(not fs.DirExists(fs.PathJoin(selected, 'cache')))
assert(fs.DirExists(fs.PathJoin(selected, 'пустая')))
print('Batch directory: ' .. batch)
print('Single file directory: ' .. single)
print('ZIP: ' .. archive)
print('Extracted: ' .. destination)
-- For selective archiving, use literal paths relative to source.
-- A listed directory is included in full, including nested files.
local selectedZip = fs.PathJoin(folder, 'Выбранное.zip')
ok, err = zip.Create(source, selectedZip, true, 'include', {'Привет.txt', 'пустая'})
assert(ok, err)
-- To exclude files explicitly, call zip.Create(source, archive, true, 'exclude', {'*.log'}).
-- The files remain in the Windows temporary folder for inspection.
