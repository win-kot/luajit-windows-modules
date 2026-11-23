local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local ipc, sync = require("ipc"), require("sync")
local name = "FrameWork shared example"
if arg[1] == "write" then
    local memory, created = ipc.SharedMemoryCreate(name, 65536)
    assert(memory, created)
    assert(created, "This example is already running")
    local done = assert(sync.EventCreate(name .. " read", true))
    assert(ipc.SharedMemoryWrite(memory, arg[2] or "Привет 語"))
    print("Buffer ready. Run this example with the read argument in another CMD window.")
    assert(sync.EventWait(done, 30000), "The reader did not respond within 30 seconds")
    assert(sync.EventClose(done))
    assert(ipc.SharedMemoryClose(memory))
elseif arg[1] == "read" then
    local memory = assert(ipc.SharedMemoryOpen(name))
    local done = assert(sync.EventOpen(name .. " read"))
    local text = assert(ipc.SharedMemoryRead(memory))
    print(text)
    assert(ipc.SharedMemoryClose(memory))
    assert(sync.EventSet(done))
    assert(sync.EventClose(done))
else
    error("Usage: luajit 30_shared_memory.lua write [TEXT] | read")
end
