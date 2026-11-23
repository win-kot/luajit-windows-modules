-- 24. Create a Menu
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("24. Create a Menu", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

local bar = gui.MenuBar()
local menu = gui.Menu()
gui.MenuAdd(menu, 1001, "Menu item")
gui.MenuSubAdd(bar, menu, "File")
gui.MenuSet(bar)
gui.Label("label1", "Open the File menu", 20, 30, 420, 40)

assert(gui.Run())
