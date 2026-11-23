-- 02. Change Events, Focus, and Tooltips
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens at screen coordinates X=200, Y=150 in pixels.
local window = assert(gui.WindowClient("02. Change Events, Focus, and Tooltips", 480, 310, "fixed", 200, 150))
gui.DefaultFontSet("Segoe UI", 12)

gui.Label("label1", "Start typing", 20, 20, 420, 30)
gui.Edit("edit1", "", 20, 65, 300, 30)
gui.ToolTip("edit1", "Enter any text")
gui.OnChange("edit1", function()
    gui.TextSet("label1", gui.TextGet("edit1"))
end)
gui.FocusSet("edit1")

assert(gui.Run())
