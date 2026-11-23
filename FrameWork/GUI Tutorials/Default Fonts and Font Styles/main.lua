-- 23. Font Styles, Default Font, and Reset
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("23. Font Styles, Default Font, and Reset", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.Label("label1", "Default font: 12 pt", 20, 20, 420, 40)
gui.FontSet("label1", "Consolas", 16, "bold", "normal")
gui.Button("button1", "Standard button", 20, 90, 300, 35)

assert(gui.Run())
gui.FontsDelete() -- Runs after the window closes.
