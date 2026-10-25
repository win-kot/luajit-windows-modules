local source = debug.getinfo(1, "S").source:sub(2)
local dir = source:match("^(.*)[/\\][^/\\]+$") or "."
dofile(dir .. "/../setup_paths.lua")

local env = require("env")
local uio = require("unicode_io")

uio.print("Windows directory:", assert(env.get("SystemRoot")))
uio.print("Expanded path:", assert(env.expand("%SystemRoot%\\System32")))

-- Changes affect only this process and children launched afterward.
local name = "LUAJIT_WINDOWS_MODULES_EXAMPLE"
local previous, err = env.get(name)
assert(err == nil, err)
local ok, failure = pcall(function()
    assert(env.set(name, "example value"))
    assert(env.get(name) == "example value")
    print("Temporary environment variable:", env.get(name))
end)
if previous == nil then
    assert(env.unset(name))
else
    assert(env.set(name, previous))
end
assert(ok, failure)
