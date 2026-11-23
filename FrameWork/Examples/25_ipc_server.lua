local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local ipc, sync = require("ipc"), require("sync")
local name = "FrameWork example"
local server = assert(ipc.PipeServerCreate(name))
local ready, created = sync.EventCreate(name, true)
assert(ready, created)
assert(created, "An example server is already running")
assert(sync.EventSet(ready))
print("Server ready")
assert(ipc.PipeAccept(server, 30000), "The client did not connect within 30 seconds")
local text = assert(ipc.PipeRead(server, 5000))
print(text)
assert(ipc.PipeWrite(server, "Received: " .. text))
-- Wait for delivery acknowledgment before closing the channel.
assert(ipc.PipeRead(server, 5000) == "OK")
assert(ipc.PipeClose(server))
assert(sync.EventClose(ready))
