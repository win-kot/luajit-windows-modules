-- 04. Set and Read a Checkbox
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("04. Set and Read a Checkbox", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.CheckBox("checkBox1", "Receive notifications", 20, 20, 350, 30)
gui.CheckedSet("checkBox1", true)
gui.Label("label1", "Toggle the checkbox", 20, 70, 400, 30)
gui.OnClick("checkBox1", function()
    local checked = gui.IsChecked("checkBox1")
    gui.TextSet("label1", "Checked: " .. tostring(checked))
end)

assert(gui.Run())
