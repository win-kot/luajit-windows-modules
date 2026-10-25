local source = debug.getinfo(1, "S").source:sub(2)
local dir = source:match("^(.*)[/\\][^/\\]+$") or "."
dofile(dir .. "/../setup_paths.lua")

local system = require("system")
local uio = require("unicode_io")

uio.print("Computer:", assert(system.getComputerName()))
uio.print("User:", assert(system.getUserName()))
uio.print("Executable:", assert(system.getExePath()))
uio.print("Current directory:", assert(system.getCurrentDirectory()))
uio.print("Temporary directory:", assert(system.getTempPath()))
local memory = assert(system.getMemory())
print("Physical memory (MiB):", math.floor(memory.totalPhysical / 1024 / 1024))
print("Available memory (MiB):", math.floor(memory.availablePhysical / 1024 / 1024))
