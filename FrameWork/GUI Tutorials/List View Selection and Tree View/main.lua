-- 18. List View Selection and Tree View
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("18. List View Selection and Tree View", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.ListView("listView1", 20, 20, 210, 150)
gui.ListViewColumnAdd("listView1", "Name", 180)
gui.ListViewAdd("listView1", {"Anna"})
gui.ListViewAdd("listView1", {"Ivan"})
gui.TreeView("treeView1", 250, 20, 190, 150)
gui.TreeRootAdd("treeView1", "Documents")
gui.Label("label1", "Select a row", 20, 200, 420, 30)
gui.OnListViewSelect("listView1", function()
    gui.TextSet("label1", "Row: " .. gui.ListViewSelectedGet("listView1"))
end)

assert(gui.Run())
