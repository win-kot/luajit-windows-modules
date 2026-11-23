-- 16. List View Columns and Rows
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("16. List View Columns and Rows", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.ListView("listView1", 20, 20, 420, 130)
gui.ListViewColumnAdd("listView1", "Name", 200)
gui.ListViewColumnAdd("listView1", "City", 200)
gui.ListViewAdd("listView1", {"Anna", "Moscow"})
gui.ListViewAdd("listView1", {"Ivan", "Tula"})
gui.Button("button1", "Row number", 20, 170, 230, 35)
gui.Label("label1", "", 20, 220, 420, 30)
gui.OnClick("button1", function()
    gui.TextSet("label1", tostring(gui.ListViewSelectedGet("listView1")))
end)

assert(gui.Run())
