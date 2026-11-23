local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local path = require("path")

local base = [[D:\Проекты\Документы]]
local report = path.Join(base, "2026", "Отчёт 語.csv")
print("Full path", report)
print("Relative path", assert(path.GetRelative(report, base)))
print("Archive", path.ChangeExtension(report, ".zip"))
assert(path.GetRelative([[D:\Strasse\отчёт]], [[D:\Straße]]) == [[..\Strasse\отчёт]])
print("UNC root", path.GetRoot([[\\server\share\отчёты\итог.csv]]))
