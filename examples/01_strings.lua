local source = debug.getinfo(1, "S").source:sub(2)
local dir = source:match("^(.*)[/\\][^/\\]+$") or "."
dofile(dir .. "/../setup_paths.lua")

local strings = require("strings")
local uio = require("unicode_io")
local timer = require("timer")

-- U+00E9 uses two UTF-8 bytes but counts as one code point.
local text = "caf\195\169"
assert(strings.len(text) == 4)
assert(strings.byte_len(text) == 5)
uio.print("Text:", text)
uio.print("Uppercase:", strings.upper(text))
uio.print("First three code points:", strings.sub(text, 1, 3))

timer.start(3)
local upper = strings.upper(text)
print("Case conversion time (ms):", assert(timer.stop()))
assert(upper == "CAF\195\137")
