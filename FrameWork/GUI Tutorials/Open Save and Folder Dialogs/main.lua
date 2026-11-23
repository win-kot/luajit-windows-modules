-- 27. File and Folder Dialogs
-- Run run.cmd in this directory.
local script = debug.getinfo(1, "S").source:sub(2)
local dir = script:match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")

-- The window opens centered in the monitor's work area.
local window = assert(gui.WindowClient("27. File and Folder Dialogs", 480, 310, "fixed", "center"))
gui.DefaultFontSet("Segoe UI", 12)

gui.Button("button1", "Open file", 20, 20, 240, 35)
gui.Button("button2", "Save as", 20, 70, 240, 35)
gui.Button("button3", "Select folder", 20, 120, 240, 35)
gui.Label("label1", "", 20, 175, 420, 75)
gui.OnClick("button1", function()
    local path, err = gui.FileOpen("Open file", {{"Lua and Text", "*.lua;*.txt"}, {"All files", "*.*"}})
    gui.TextSet("label1", path or err or "Cancel")
end)
gui.OnClick("button2", function()
    local path, err = gui.FileSave("Save as", {{"Lua and Text", "*.lua;*.txt"}, {"All files", "*.*"}})
    gui.TextSet("label1", path or err or "Cancel")
end)
gui.OnClick("button3", function()
    local path, err = gui.FolderChoose("Select a folder")
    gui.TextSet("label1", path or err or "Cancel")
end)

assert(gui.Run())
