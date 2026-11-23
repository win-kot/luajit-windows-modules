-- 19. Tree View Child Nodes and Expansion
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("19. Tree View Child Nodes and Expansion", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.TreeView("treeView1", 20, 20, 420, 210)
local root = gui.TreeRootAdd("treeView1", "Documents")
gui.TreeChildAdd("treeView1", root, "Work")
gui.TreeInsert("treeView1", "Study", root)
gui.TreeExpand("treeView1", root)

assert(gui.Run())
