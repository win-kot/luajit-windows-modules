-- 05. Radio Buttons and Group Boxes
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("05. Radio Buttons and Group Boxes", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.GroupBox("groupBox1", "Size", 20, 20, 400, 100)
-- Pass true to the first RadioButton to start a new group.
gui.RadioButton("radioButton1", "Small", 35, 55, 170, 30, true)
gui.RadioButton("radioButton2", "Large", 220, 55, 170, 30, false)
gui.CheckedSet("radioButton1", true)
gui.Label("label1", "Small", 20, 160, 400, 30)
gui.OnClick("radioButton1", function()
    gui.TextSet("label1", "Small")
end)
gui.OnClick("radioButton2", function()
    gui.TextSet("label1", "Large")
end)

assert(gui.Run())
