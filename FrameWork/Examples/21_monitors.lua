local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local monitor = require("monitor")
for _, screen in ipairs(assert(monitor.ListGet())) do
    local r = screen.rect
    local dpi = assert(monitor.DpiGet(screen.id))
    print(screen.deviceName, screen.primary, r.left, r.top, r.right, r.bottom, dpi.x, dpi.y)
end
