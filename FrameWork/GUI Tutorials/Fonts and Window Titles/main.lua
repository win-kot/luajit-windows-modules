-- 22. Set a Font and Read the Window Title
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("22. Set a Font and Read the Window Title", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.Label("label1", "Large text", 20, 20, 420, 50)
assert(gui.FontSet("label1", "Segoe UI", 20, "bold", "normal"))
gui.Button("button1", "Read title", 20, 100, 300, 35)
gui.Label("label2", "", 20, 160, 420, 60)
gui.OnClick("button1", function()
    gui.TextSet("label2", gui.TitleGet())
end)

assert(gui.Run())
gui.FontsDelete() -- Runs after the window closes.
