local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local sys, shell, fs = require("sys"), require("shell"), require("fs")
local cpu = assert(sys.GetProcessorInfo())
print(cpu.name or cpu.architecture, cpu.logicalProcessors)
print("Last input (ms)", assert(sys.GetIdleTime()))
print("Locale", assert(sys.GetLocale()))

local temp = assert(fs.TempDirCreate())
local linkPath = assert(fs.PathJoin(temp, "Ярлык 語.lnk"))
local ok, err = xpcall(function()
    assert(shell.CreateShortcut(linkPath, assert(require("system").ExePathGet()), {
        arguments = '"Тест 語"', description = "LuaJIT Example"
    }))
    local link = assert(shell.ReadShortcut(linkPath))
    print(link.target, link.arguments, link.description)
end, debug.traceback)
assert(fs.DirDelete(temp, true))
assert(ok, err)
