-- 15. Refresh Tab Pages, Tab Buttons, and List Views
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("15. Refresh Tab Pages, Tab Buttons, and List Views", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.TabButtons("tabButtons1", 20, 20, 400, 190)
gui.TabAdd("tabButtons1", "Table")
gui.TabAdd("tabButtons1", "Text")
gui.ListView("listView1", 35, 65, 365, 125)
gui.ListViewColumnAdd("listView1", "Name", 220)
gui.ListViewAdd("listView1", {"Anna"})
gui.Label("label1", "Another page", 35, 65, 350, 30)
gui.TabPage("tabButtons1", 1, {"listView1"})
gui.TabPage("tabButtons1", 2, {"label1"})
gui.TabPagesUpdate("tabButtons1")

assert(gui.Run())
