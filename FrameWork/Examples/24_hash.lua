local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local crypto = require("crypto")
if arg[1] then
    print(assert(crypto.FileHash(arg[1], "SHA-256")))
else
    print(assert(crypto.Hash("Привет, Windows", "SHA-256")))
end
