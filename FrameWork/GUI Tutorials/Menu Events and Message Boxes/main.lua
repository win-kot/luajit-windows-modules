-- 26. Menu Events, Removal, and Message Boxes
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("26. Menu Events, Removal, and Message Boxes", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

local bar = gui.MenuBar()
local file = gui.Menu()
gui.MenuAdd(file, 1001, "Message")
gui.MenuAdd(file, 1002, "Confirmation")
gui.MenuSubAdd(bar, file, "File")
gui.MenuSet(bar)
gui.OnMenu(1001, function()
    gui.MessageBox("Hello!", "Message", "ok", "information")
end)
gui.Label("result", "The confirmation result appears here", 20, 20, 440, 40)
gui.OnMenu(1002, function()
    local answer, err = gui.MessageBox("Continue?", "Confirmation", "yes-no", "question", 2)
    if answer == nil then error(err) end
    gui.TextSet("result", answer == gui.Answer.Yes and "Selected Yes" or "Selected No")
end)
-- You can delete a standalone menu before attaching it to a window.
local unused = gui.Menu()
gui.MenuDestroy(unused)

assert(gui.Run())
