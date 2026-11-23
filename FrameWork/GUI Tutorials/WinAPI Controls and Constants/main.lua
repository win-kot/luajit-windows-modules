-- 30. Low-Level WinAPI Features
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local ffi = require("win_constants")
local bit = require("bit")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("30. Low-Level WinAPI Features", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

-- WS_CHILD and WS_VISIBLE create a visible child control.
gui.ControlCreate("createControl1", "STATIC", "Label created using a WinAPI class", bit.bor(ffi.C.WS_CHILD, ffi.C.WS_VISIBLE), 20, 20, 420, 40)
-- These two functions are for direct WinAPI calls.
local wide = gui.WideTextMake("UTF-16 text")
print("UTF-16 buffer:", wide)
-- WM_NULL (0) is a no-op suitable for this example.
gui.WndProc(window, ffi.C.WM_NULL, 0, 0)

assert(gui.Run())
