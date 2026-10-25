local source = debug.getinfo(1, "S").source:sub(2)
local dir = source:match("^(.*)[/\\][^/\\]+$") or "."
dofile(dir .. "/../setup_paths.lua")

require("single_instance")
local native = require("win_native")

print("This instance will stay alive for 10 seconds")
print("Start this same script in another CMD window to try the instance guard")
native.sleep(10000)
print("Done")
-- The second instance exits during require("single_instance").
