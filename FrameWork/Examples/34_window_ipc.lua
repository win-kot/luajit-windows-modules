local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local commands = require("ipc")
local name = "FrameWork window IPC example"

if arg[1] == "send" then
    assert(commands.CommandPost(name, 1, 42))
    return
end
assert(arg[1] == "listen", "Usage: 34_window_ipc.lua listen | send")

local gui = require("gui")
assert(gui.WindowClient("Interprocess Commands", 420, 130, "fixed", "center"))
assert(gui.Label("status", "Waiting for a command...", 20, 25, 375, 35))
assert(commands.CommandListen(name, function(command, value)
    if command == 1 then
        assert(gui.TextSet("status", "Received value: " .. value))
    end
end))
local result, message = gui.Run()
assert(commands.CommandClose())
assert(result, message)
