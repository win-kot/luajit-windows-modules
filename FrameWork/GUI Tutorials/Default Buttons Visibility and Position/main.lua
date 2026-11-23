-- 06. Default Button, Enabled State, Visibility, and Position
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("06. Default Button, Enabled State, Visibility, and Position", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.Edit("edit1", "Text field", 20, 20, 300, 30)
gui.Label("label1", "This label will be hidden", 20, 65, 400, 30)
gui.DefaultButton("defaultButton1", "Update controls", 20, 110, 250, 35)
gui.OnClick("defaultButton1", function()
    gui.Enable("edit1", false)
    gui.Show("label1", false)
    gui.Move("defaultButton1", 180, 170, 250, 35)
end)

assert(gui.Run())
