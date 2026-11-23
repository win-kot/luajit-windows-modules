-- 13. Create Tabs
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("13. Create Tabs", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.Tab("tab1", 20, 20, 400, 130)
gui.TabAdd("tab1", "First")
gui.TabAdd("tab1", "Second")
gui.Button("button1", "Tab number", 20, 175, 230, 35)
gui.Label("label1", "", 20, 225, 400, 30)
gui.OnClick("button1", function()
    gui.TextSet("label1", tostring(gui.TabSelectedGet("tab1")))
end)

assert(gui.Run())
