local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local clipboard = require("clipboard")
-- Copy one or more files in File Explorer.
if clipboard.FilesExists() then
    for _, path in ipairs(assert(clipboard.FilesGet())) do print(path) end
else
    print("The clipboard contains no file list")
end
