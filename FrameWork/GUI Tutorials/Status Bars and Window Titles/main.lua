-- 21. Status Bar and Window Title
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("21. Status Bar and Window Title", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.StatusBar("statusBar1", "Done", 0, 240, 480, 25)
gui.Button("button1", "Refresh", 20, 20, 200, 35)
gui.OnClick("button1", function()
    gui.StatusTextSet("statusBar1", "Data refreshed")
    gui.TitleSet("New window title")
end)

assert(gui.Run())
