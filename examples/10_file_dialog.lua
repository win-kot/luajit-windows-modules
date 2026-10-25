local source = debug.getinfo(1, "S").source:sub(2)
local dir = source:match("^(.*)[/\\][^/\\]+$") or "."
dofile(dir .. "/../setup_paths.lua")

local dialog = require("file_dialog")
local uio = require("unicode_io")

local path, err = dialog.open({
    title = "Select a text file",
    filters = {
        {"Text files", "*.txt"},
        {"All files", "*.*"},
    },
    filterIndex = 1,
})
if path then
    uio.print("Selected:", path)
elseif err then
    error(err)
else
    print("Selection cancelled")
end
-- Selecting a path does not read or modify the file.
-- Use dialog.save(options) or dialog.selectFolder(options) for other dialogs.
