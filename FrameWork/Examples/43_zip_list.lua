local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local zip = require("zip")

for _, entry in ipairs(assert(zip.List(assert(arg[1], "Pass a ZIP path")))) do
    print(entry.isDir and "dir" or "file", entry.size, entry.compressedSize, entry.name)
end
