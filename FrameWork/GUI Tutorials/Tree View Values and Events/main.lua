-- 20. Read Tree View Values and Handle Events
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("20. Read Tree View Values and Handle Events", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.TreeView("treeView1", 20, 20, 420, 170)
local root = gui.TreeRootAdd("treeView1", "Documents")
gui.TreeChildAdd("treeView1", root, "Work")
gui.TreeExpand("treeView1", root)
gui.Label("label1", "Select a node", 20, 215, 420, 30)
gui.OnTreeSelect("treeView1", function()
    local item = gui.TreeSelectedGet("treeView1")
    local text = gui.TreeTextGet("treeView1", item)
    gui.TextSet("label1", text)
end)

assert(gui.Run())
