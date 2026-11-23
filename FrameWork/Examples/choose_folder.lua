local source = debug.getinfo(1, "S").source:sub(2)
local dir = source:match("^(.*)[/\\\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))()

local gui = require("gui")
local fd = require("file_dialog")

gui.WindowClient("Folder and File Selection", 260, 150, "fixed", "center")
gui.DefaultFontSet("Segoe UI", 9)

gui.Button("btnFolder", "Select folder", 20, 16, 220, 28)
gui.Button("btnOpen", "Open file", 20, 60, 220, 28)
gui.Button("btnSave", "Save file", 20, 104, 220, 28)

local function ShowResult(path, err)
    if path then
        print("Selected path: " .. path)
    elseif err then
        print("Error: " .. err)
    end
end

gui.OnClick("btnFolder", function()
    ShowResult(fd.FolderSelect({
        title = "Select a folder"
    }))
end)

gui.OnClick("btnOpen", function()
    ShowResult(fd.Open({
        title = "Open file",
        filters = {
            { "Lua files", "*.lua" },
            { "All files", "*.*" }
        }
    }))
end)

gui.OnClick("btnSave", function()
    ShowResult(fd.Save({
        title = "Save file",
        fileName = "script.lua",
        defaultExtension = "lua",
        filters = {
            { "Lua files", "*.lua" },
            { "All files", "*.*" }
        }
    }))
end)

gui.Run()
