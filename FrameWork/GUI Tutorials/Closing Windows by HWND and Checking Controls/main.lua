-- 29. Close a Window by HWND and Check a Control ID
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("29. Close a Window by HWND and Check a Control ID", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.Label("label1", "", 20, 20, 420, 80)
local hwnd = gui.HandleGet("label1")
local valid = gui.IsValidControlId("label1")
gui.TextSet("label1", "HWND: " .. tostring(hwnd) .. "\r\nValid ID: " .. tostring(valid))
gui.OnClose(function()
    print("Closing the window")
    return true
end)

assert(gui.Run())
