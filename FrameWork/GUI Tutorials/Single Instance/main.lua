local source = debug.getinfo(1, "S").source
local dir = source:sub(2):match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
require("single_instance")

local gui = require("gui")
assert(gui.WindowClient("Single Instance", 420, 180, "fixed", "center"))
assert(gui.Label("info", "Run this example again to see the single-instance guard in action.", 20, 20, 380, 55))
assert(gui.Button("close", "Close", 130, 100, 160, 36))
assert(gui.OnClick("close", function() assert(gui.Close()) end))
gui.Run()
