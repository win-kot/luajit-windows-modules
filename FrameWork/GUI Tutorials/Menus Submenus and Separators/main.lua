-- 25. Add a Submenu and Separator
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("25. Add a Submenu and Separator", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

local bar = gui.MenuBar()
local file = gui.Menu()
local recent = gui.Menu()
gui.MenuAdd(recent, 1001, "Document 1")
gui.MenuSubAdd(file, recent, "Recent")
gui.MenuSeparator(file)
gui.MenuAdd(file, 1002, "Another item")
gui.MenuSubAdd(bar, file, "File")
gui.MenuSet(bar)

assert(gui.Run())
