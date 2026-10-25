-- Load explicitly: dofile('C:/path/to/library/setup_paths.lua').
-- Use an absolute path when the current directory differs from the library.
local source = debug.getinfo(1, 'S').source
assert(source:sub(1, 1) == '@', 'setup_paths must be loaded from a file')
local dir = source:sub(2):match('^(.*)[/\\][^/\\]+$') or '.'
local lua_prefix, dll_prefix = dir .. '/?.lua;', dir .. '/?.dll;'
if package.path:sub(1, #lua_prefix) ~= lua_prefix then
    package.path = lua_prefix .. package.path
end
if package.cpath:sub(1, #dll_prefix) ~= dll_prefix then
    package.cpath = dll_prefix .. package.cpath
end
return dir
