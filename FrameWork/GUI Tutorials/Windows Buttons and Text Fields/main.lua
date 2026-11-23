-- 01. Window, Button, Label, and Edit
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("01. Window, Button, Label, and Edit", 480, 310, "resizable", "center"))
gui.DefaultFontSet("Segoe UI", 12)

-- Label displays text, Edit accepts input, and Button handles clicks.
gui.Label("label1", "Enter a name", 20, 20, 420, 30)
gui.Edit("edit1", "Anna", 20, 60, 250, 30)
gui.Button("button1", "Greeting", 20, 105, 180, 35)

gui.OnClick("button1", function()
    local name = gui.TextGet("edit1")
    gui.TextSet("label1", "Hello, " .. name)
end)

assert(gui.Run())
