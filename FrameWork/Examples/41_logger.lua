local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local logger = require("logger")

local path = arg[1]
if path then
    assert(logger.SetFile(path))
    assert(logger.Rotate({maxBytes = 1024 * 1024}))
end
assert(logger.SetLevel("info"))
assert(logger.Write("debug", "Hidden debug entry"))
assert(logger.Write("info", "Log verification", {script = "41_logger.lua", ok = true}))
