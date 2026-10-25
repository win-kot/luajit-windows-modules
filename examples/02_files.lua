local source = debug.getinfo(1, "S").source:sub(2)
local dir = source:match("^(.*)[/\\][^/\\]+$") or "."
dofile(dir .. "/../setup_paths.lua")

local uio = require("unicode_io")

-- Optional argument: output directory. The default is next to this script.
local output = arg[1] or (dir .. "/output")
assert(uio.makedirs(output))
local path = uio.join(output, "caf\195\169.txt")
local exists, err = uio.exists(path)
assert(exists ~= nil, err)
assert(not exists, "Example file already exists; choose another output directory")
assert(uio.write_file(path, "Hello from LuaJIT!\n", "UTF-8"))
local text = assert(uio.read_file(path, "UTF-8"))
assert(text == "Hello from LuaJIT!\n")
uio.print("Created:", path)
uio.print("Contents:", text)
-- The file is left in place so you can inspect it.
