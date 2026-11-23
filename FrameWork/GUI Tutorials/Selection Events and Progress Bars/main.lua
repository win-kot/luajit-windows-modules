-- 11. Selection Events and Progress Bars
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("11. Selection Events and Progress Bars", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.ComboBox("comboBox1", 20, 20, 300, 160)
gui.ComboItemsSet("comboBox1", {"Start", "Middle", "End"})
gui.ProgressBar("progressBar1", 20, 85, 400, 25, 0, 100, 0)
gui.OnSelect("comboBox1", function()
    local index = gui.ComboSelectedGet("comboBox1")
    gui.ProgressSet("progressBar1", (index - 1) * 50)
end)

assert(gui.Run())
