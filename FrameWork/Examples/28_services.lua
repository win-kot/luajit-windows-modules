local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local service = require("service")
for _, entry in ipairs(assert(service.ListGet())) do
    print(entry.name, entry.state, entry.pid, entry.displayName)
end
