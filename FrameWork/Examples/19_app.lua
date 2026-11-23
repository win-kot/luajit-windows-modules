local source = debug.getinfo(1, "S").source
local dir = source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))()
local app = require("app")

-- On first load, require resolves the entry script path from arg[0].
local info = assert(app.GetInfo())
print("Script:", info.L_ScriptPath)
print("Script directory:", info.L_ScriptDir)
print("Working directory:", info.L_WorkingDir)

-- Absolute path to a file beside the script:
print("Config path:", assert(require("fs").PathJoin(info.L_ScriptDir, "settings.ini")))

-- Set the working directory to the script directory, then restore the previous directory.
assert(app.WorkingDirSet())
print("New working directory:", assert(app.WorkingDirGet()))
assert(app.WorkingDirSet(info.L_WorkingDir))

-- Call ScriptPathSet if the host application did not set arg[0].
-- The function stores the path. It leaves the file and the working directory as they are.
assert(app.ScriptPathSet(info.L_ScriptPath))
assert(app.ScriptPathSet("") == nil)
assert(app.L_ScriptPath == info.L_ScriptPath)
print("Explicit path:", assert(app.GetInfo()).L_ScriptPath)
