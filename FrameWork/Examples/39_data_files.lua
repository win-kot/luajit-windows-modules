local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local fs, json, ini, csv = require("fs"), require("json"), require("ini"), require("csv")

local config = assert(json.Decode([[{"language":"русский","enabled":true}]]))
print(assert(json.Encode(config)))
local path = require("path")
local iniPath = assert(path.GetTempFile("Настройки-"))
local csvPath
local ok, err = xpcall(function()
    assert(ini.Write(iniPath, "app", "language", config.language))
    print(assert(ini.Read(iniPath, "app", "language")))
    csvPath = assert(path.GetTempFile("Отчёт-"))
    local label = "\239\187\191language" -- U+FEFF belongs to the first field.
    assert(csv.Write(csvPath, {{label, config.language}}))
    local rows = assert(csv.Read(csvPath))
    assert(rows[1][1] == label and rows[1][2] == config.language)
end, debug.traceback)
assert(fs.FileDelete(iniPath))
if csvPath then assert(fs.FileDelete(csvPath)) end
assert(ok, err)
