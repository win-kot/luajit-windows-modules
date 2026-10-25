local source = debug.getinfo(1, "S").source:sub(2)
local dir = source:match("^(.*)[/\\][^/\\]+$") or "."
dofile(dir .. "/../setup_paths.lua")

local runtime = require("runtime")
local argv = require("argv")
local lvars = require("lvars")
local uio = require("unicode_io")

uio.print("Script path:", runtime.L_ScriptPath)
uio.print("Script directory:", runtime.L_ScriptDir)
uio.print("Initial working directory:", runtime.L_WorkingDir)
uio.print("Current working directory:", lvars.L_WorkingDir)
uio.print("Original command line:", assert(argv.commandLine()))
for index, value in ipairs(assert(argv.get())) do
    uio.print("Windows argument " .. index .. ":", value)
end
-- argv.get()[1] is the interpreter/executable; it includes the script argument.
-- For the script's own user arguments, use arg[1], arg[2], etc.
