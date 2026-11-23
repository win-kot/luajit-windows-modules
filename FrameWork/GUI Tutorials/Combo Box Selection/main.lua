-- 08. Read a Combo Box Selection
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("08. Read a Combo Box Selection", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.ComboBox("comboBox1", 20, 20, 300, 160)
gui.ComboItemsSet("comboBox1", {"Red", "Green", "Blue"})
gui.ComboSelectedSet("comboBox1", 2)
gui.Button("button1", "Read selection", 20, 80, 230, 35)
gui.Label("label1", "", 20, 135, 420, 30)
gui.OnClick("button1", function()
    local index = gui.ComboSelectedGet("comboBox1")
    local text = gui.ComboSelectedTextGet("comboBox1")
    gui.TextSet("label1", tostring(index) .. ": " .. tostring(text))
end)

assert(gui.Run())
