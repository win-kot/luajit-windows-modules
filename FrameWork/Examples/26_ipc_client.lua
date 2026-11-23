local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local ipc, sync = require("ipc"), require("sync")
local name = "FrameWork example"
local ready = assert(sync.EventOpen(name))
assert(sync.EventWait(ready, 5000), "The server did not signal")
local client = assert(ipc.PipeConnect(name, 5000))
assert(ipc.PipeWrite(client, "Привет 語"))
print(assert(ipc.PipeRead(client, 5000)))
assert(ipc.PipeWrite(client, "OK"))
assert(ipc.PipeClose(client))
assert(sync.EventClose(ready))
