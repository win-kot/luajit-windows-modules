local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local crypto = require("crypto")
local fs = require("fs")

local demo = assert(fs.TempDirCreate())
local source = fs.PathJoin(demo, "файл.bin")
local encrypted = fs.PathJoin(demo, "файл.enc")
local restored = fs.PathJoin(demo, "копия.bin")
local password = "учебный пароль"

local ok, err = pcall(function()
    assert(fs.FileWriteBytes(source, "Пример\0\255"))
    assert(crypto.EncryptFile(source, encrypted, password))
    assert(crypto.DecryptFile(encrypted, restored, password))
    assert(assert(crypto.FileHash(source)) == assert(crypto.FileHash(restored)))
    print("The file was encrypted and recovered. The SHA-256 hashes match.")
end)
assert(fs.DirDelete(demo, true))
assert(ok, err)
