-- 10. Read a List Box Selection
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("10. Read a List Box Selection", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.ListBox("listBox1", 20, 20, 300, 130)
gui.ListItemsSet("listBox1", {"Moscow", "Kazan", "Tula"})
gui.ListSelectedSet("listBox1", 2)
gui.Button("button1", "Read selection", 20, 165, 230, 35)
gui.Label("label1", "", 20, 215, 420, 30)
gui.OnClick("button1", function()
    local index = gui.ListSelectedGet("listBox1")
    local text = gui.ListSelectedTextGet("listBox1")
    gui.TextSet("label1", tostring(index) .. ": " .. tostring(text))
end)

assert(gui.Run())
