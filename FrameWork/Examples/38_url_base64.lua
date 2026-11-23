local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local url, crypto = require("url"), require("crypto")

local text = arg[1] or "Привет 語 +"
local address = "https://example.com/search?q=" .. url.Encode(text) .. "#results"
local parts = assert(url.Parse(address))
print(address)
print(parts.host, parts.path, assert(url.Decode(parts.query:sub(3))))
assert(url.Decode(parts.query:sub(3)) == text)

local bytes = "\0\255LuaJIT"
local encoded = assert(crypto.Base64Encode(bytes))
print(encoded)
assert(crypto.Base64Decode(encoded) == bytes)
