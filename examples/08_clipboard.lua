local source = debug.getinfo(1, "S").source:sub(2)
local dir = source:match("^(.*)[/\\][^/\\]+$") or "."
dofile(dir .. "/../setup_paths.lua")

local clipboard = require("clipboard")
local uio = require("unicode_io")

local hasText, err = clipboard.hasText()
assert(hasText ~= nil, err)
if hasText then
    uio.print("Clipboard text:", assert(clipboard.getText()))
else
    print("The clipboard does not contain text")
end
-- Run explicitly when you want to display your current clipboard contents.
-- This example does not replace or clear clipboard data.
