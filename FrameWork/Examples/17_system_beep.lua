local source = debug.getinfo(1, 'S').source
local dir = source:sub(2):match('^(.*)[/\\]') or '.'
assert(loadfile(dir .. '/_bootstrap.lua'))()

local system = require('system')
-- Frequency in Hz, duration in milliseconds. The call waits until finished.
local ok, err = system.Beep(880, 150)
assert(ok, err)
print('system.Beep: OK')
