local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local sqlite = require("sqlite")
local db = assert(sqlite.Open(":memory:"))

local ok, err = xpcall(function()
    assert(db:Exec("CREATE TABLE notes (title TEXT, priority INTEGER)"))
    assert(db:Exec("INSERT INTO notes VALUES (?, ?)", {"Отчёт 語", 2}))
    for _, row in ipairs(assert(db:Query("SELECT title, priority FROM notes WHERE priority >= ?", {2}))) do
        print(row.title, row.priority)
    end
end, debug.traceback)
assert(db:Close())
assert(ok, err)
