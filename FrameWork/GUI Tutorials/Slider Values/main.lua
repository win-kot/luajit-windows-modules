-- 12. Set and Read a Slider Value
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("12. Set and Read a Slider Value", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.Slider("slider1", 20, 20, 400, 40, 0, 100, 20)
gui.SliderSet("slider1", 30)
gui.ProgressBar("progressBar1", 20, 85, 400, 25, 0, 100, 30)
gui.Label("label1", "30", 20, 130, 400, 30)
gui.OnChange("slider1", function()
    local value = gui.SliderGet("slider1")
    gui.ProgressSet("progressBar1", value)
    gui.TextSet("label1", tostring(value))
end)

assert(gui.Run())
