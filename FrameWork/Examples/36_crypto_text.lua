local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local crypto = require("crypto")
local password = "учебный пароль"
local encrypted = assert(crypto.EncryptText("Привет, 日本!", password))
print(encrypted)
print(assert(crypto.DecryptText(encrypted, password)))
