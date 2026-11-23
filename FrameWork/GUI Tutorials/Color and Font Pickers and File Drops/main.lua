-- 28. Choose Colors and Fonts and Accept File Drops
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("28. Choose Colors and Fonts and Accept File Drops", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.Label("label1", "Drop files onto the window", 20, 20, 420, 90)
gui.Button("button1", "Choose color", 20, 130, 200, 35)
gui.Button("button2", "Choose font", 240, 130, 200, 35)
gui.OnClick("button1", function()
    local color, err = gui.ColorChoose(0x0000ff)
    gui.TextSet("label1", color and string.format("COLORREF: 0x%06X", color) or err or "Cancel")
end)
gui.OnClick("button2", function()
    -- The table holds the name, size, bold and italic flags, and COLORREF.
    local font, err = gui.FontChoose()
    if font then
        gui.FontSet("label1", font[1], font[2], font[3], font[4])
    else
        gui.TextSet("label1", err or "Cancel")
    end
end)
gui.OnDropFiles(function(paths)
    gui.TextSet("label1", table.concat(paths, "\r\n"))
end)

assert(gui.Run())
