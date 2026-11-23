-- 31. Custom Event Handlers and Shutdown
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("31. Custom Event Handlers and Shutdown", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.Label("label1", "Click the button", 20, 20, 420, 30)
gui.Button("button1", "Call handler", 20, 75, 300, 35)
gui.Button("button2", "Close", 20, 130, 300, 35)
local handlers = {}
gui.HandlerSet(handlers, 5001, function()
    gui.TextSet("label1", "Custom handler ran")
end)
gui.OnClick("button1", function()
    gui.HandlerDispatch(handlers, 5001)
end)
gui.OnClick("button2", function()
    gui.Close()
end)

assert(gui.Run())
