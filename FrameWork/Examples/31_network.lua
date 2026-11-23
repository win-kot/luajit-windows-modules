local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local network = require("network")

for _, adapter in ipairs(assert(network.AdaptersGet())) do
    print(adapter.name, adapter.status, "MTU", adapter.mtu)
    for _, ip in ipairs(adapter.addresses) do
        local zone = ip.scopeId and ip.scopeId ~= 0 and ("%" .. ip.scopeId) or ""
        local prefix = ip.prefixLength and ("/" .. ip.prefixLength) or ""
        print("  " .. ip.address .. zone .. prefix)
    end
end

if arg[1] then
    local route = assert(network.BestRouteGet(arg[1]))
    print("Interface", route.index)
    print("Source address", route.source and route.source.address or "")
    if route.onLink then
        print("Direct route")
    else
        print("Next gateway", route.nextHop.address)
    end
    local stats = assert(network.InterfaceStatsGet(route.index))
    print("Bytes received", stats.receivedBytes)
    print("Bytes sent", stats.sentBytes)
end
