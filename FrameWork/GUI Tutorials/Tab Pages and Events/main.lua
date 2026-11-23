-- 14. Tab Pages and Events
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("14. Tab Pages and Events", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.Tab("tab1", 20, 20, 400, 170)
gui.TabAdd("tab1", "Name")
gui.TabAdd("tab1", "City")
gui.Edit("edit1", "Anna", 40, 70, 330, 30)
gui.Edit("edit2", "Moscow", 40, 70, 330, 30)
-- Each table contains the names of the controls on its page.
gui.TabPage("tab1", 1, {"edit1"})
gui.TabPage("tab1", 2, {"edit2"})
gui.Label("label1", "Opened tab 2", 20, 215, 400, 30)
gui.OnTabChange("tab1", function()
    gui.TextSet("label1", "Opened tab " .. gui.TabSelectedGet("tab1"))
end)
gui.TabSelectedSet("tab1", 2)

assert(gui.Run())
