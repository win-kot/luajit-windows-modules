local source = debug.getinfo(1, "S").source:sub(2)
local dir = source:match("^(.*)[/\\][^/\\]+$") or "."
dofile(dir .. "/../setup_paths.lua")

local mouse = require("mouse")
local keyboard = require("keyboard")

local x, y = mouse.getPosition()
assert(x ~= nil, y)
print("Pointer position:", x, y)
local pressed, err = keyboard.isDown("SHIFT")
assert(pressed ~= nil, err)
print("Shift is down:", pressed)
-- State inspection only: no keys, clicks, or movement are sent.
