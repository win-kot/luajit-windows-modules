-- 03. Three Edit Control Styles
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("03. Three Edit Control Styles", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.EditMulti("editMulti1", "First line\r\nSecond line", 20, 20, 400, 90)
gui.EditReadOnly("editReadOnly1", "This text is read-only", 20, 130, 400, 30)
gui.EditPassword("editPassword1", "secret", 20, 180, 250, 30)

assert(gui.Run())
