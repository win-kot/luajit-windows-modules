-- 17. List View Text and Column Count
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("17. List View Text and Column Count", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.ListView("listView1", 20, 20, 420, 130)
gui.ListViewColumnAdd("listView1", "Name", 200)
gui.ListViewColumnAdd("listView1", "City", 200)
gui.ListViewColumnCountSet("listView1", 2)
gui.ListViewAdd("listView1", {"Anna", "Moscow"})
gui.Button("button1", "Read table", 20, 170, 250, 35)
gui.Label("label1", "", 20, 220, 420, 30)
gui.OnClick("button1", function()
    local text = gui.ListViewTextGet("listView1", 1, 2)
    local count = gui.ListViewColumnCountGet("listView1")
    gui.TextSet("label1", text .. "; columns: " .. count)
end)

assert(gui.Run())
