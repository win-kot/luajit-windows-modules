local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local fs = require("fs")
local path = assert(fs.TempFileReserve())
local file

local ok, err = xpcall(function()
    file = assert(fs.Open(path, "r+", {share = "readwrite"}))
    assert(file:Lock(0, 64), "The first 64 bytes are already locked")
    local text = "Done"
    assert(assert(file:Write(text)) == #text)
    assert(file:Unlock(0, 64))
    assert(file:Seek(0) == 0)
    print(assert(file:Read()))
end, debug.traceback)
if file then assert(file:Close()) end
assert(fs.FileDelete(path))
assert(ok, err)
