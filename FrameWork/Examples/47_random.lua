local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local random = require("random")
local crypto = require("crypto")

print("Die roll:", assert(random.Integer(1, 6)))
print("Number in [0, 1):", random.Number())
print(("Cryptographically random six-digit code: %06d"):format(assert(random.SecureInteger(0, 999999))))
print("Random bytes in Base64:", assert(crypto.Base64Encode(assert(crypto.RandomBytes(16)))))
