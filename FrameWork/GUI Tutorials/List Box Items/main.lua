-- 09. Add List Box Items
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("09. Add List Box Items", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.ListBox("listBox1", 20, 20, 350, 170)
gui.ListItemsSet("listBox1", {"Moscow", "Kazan"})
gui.ListAdd("listBox1", "Tula")

assert(gui.Run())
