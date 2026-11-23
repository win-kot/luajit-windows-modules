-- 07. Add Combo Box Items
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("07. Add Combo Box Items", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.ComboBox("comboBox1", 20, 20, 300, 160)
gui.ComboItemsSet("comboBox1", {"Red", "Green"})
gui.ComboAdd("comboBox1", "Blue")

assert(gui.Run())
