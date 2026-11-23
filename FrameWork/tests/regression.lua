-- From the package root: luajit tests/regression.lua [all|core|sqlite|zip]
local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
dofile(dir .. "/../FrameWork/setup_paths.lua")
local fs = require("fs")
local native = require("_win_native")
local suite = arg[1] or "all"
assert(suite == "all" or suite == "core" or suite == "sqlite" or suite == "zip",
    "expected all, core, sqlite or zip")

local function core(folder)
    local app, path = require("app"), require("path")
    local original = assert(app.GetInfo())
    local candidate = fs.PathJoin(folder, "Главный 語.lua")
    assert(app.ScriptPathSet(candidate))
    local info = assert(app.GetInfo())
    assert(info.L_ScriptPath == candidate and info.L_ScriptName == "Главный 語.lua")
    assert(app.ScriptPathSet("bad\0path") == nil)
    assert(assert(app.GetInfo()).L_ScriptPath == candidate)
    local ok, err = xpcall(function()
        assert(app.WorkingDirSet())
        assert(app.L_WorkingDir == info.L_ScriptDir)
        assert(app.L_ScriptPath == candidate)
    end, debug.traceback)
    assert(app.WorkingDirSet(original.L_WorkingDir))
    assert(app.ScriptPathSet(original.L_ScriptPath))
    assert(ok, err)
    assert(path.GetRelative([[C:\Strasse\a]], [[C:\Straße]]) == [[..\Strasse\a]])
    assert(path.GetRelative([[C:\ПАПКА\a]], [[c:\папка]]) == "a")
    assert(path.IsAbsolute([[\\?\]]) == false)

    assert(fs.PathBaseName([[\\?\unc\host\share]]) == "")
    assert(path.IsUNC([[\\.\UNC\host\share\file]]))

    local csv, ini, enc = require("csv"), require("ini"), require("encoding")
    local file = fs.PathJoin(folder, "Таблица 日本.csv")
    local marker = "\239\187\191"
    local input = {{marker .. "Имя", 'a,"b"', "строка\r\n二"}, {""}}
    for _, codec in ipairs({"utf8", "utf16le", "utf16be"}) do
        for _, bom in ipairs({false, true}) do
            assert(csv.Write(file, input, {encoding = codec, bom = bom}))
            local result = assert(csv.Read(file, {encoding = codec}))
            assert(#result == 2 and #result[1] == 3 and result[2][1] == "")
            for i, field in ipairs(input[1]) do assert(result[1][i] == field) end
        end
    end
    local previous = assert(fs.FileRead(file, "BINARY"))
    assert(csv.Write(file, {{"ok"}, [4] = {"hole"}}) == nil)
    assert(csv.Write(file, {{[2] = "hole"}}) == nil)
    assert(fs.FileRead(file, "BINARY") == previous)
    assert(enc.Convert("\0", "utf16le", "utf8") == nil)
    assert(enc.Convert("\0\216", "utf16le", "utf8") == nil)
    local utf7 = assert(enc.Convert("Hi + 語", "utf8", 65000))
    assert(enc.Convert(utf7, 65000, "utf8") == "Hi + 語")
    local bytes = assert(enc.Convert("A\0語", "utf8", "utf16be"))
    assert(enc.Convert(bytes, "utf16be", "utf8") == "A\0語")

    local settings = fs.PathJoin(folder, "Тест.ini")
    local value = "a" .. string.rep(" ", 20000) .. "b"
    assert(fs.FileWriteBytes(settings, marker .. ";keep\r\n[s]\r\nx=old\r\n[s]\nx=new"))
    assert(ini.Read(settings, "s", "x") == "new")
    assert(ini.Write(settings, "s", "x", value))
    assert(ini.Read(settings, "s", "x") == value)
    assert(fs.FileRead(settings, "BINARY") == marker .. ";keep\r\n[s]\r\nx=old\r\n[s]\nx=" .. value)
    assert(ini.Delete(settings, "s", "x"))
    assert(ini.Read(settings, "s", "x") == nil)
    assert(fs.DirCreate(fs.PathJoin(folder, "Подпапка")))
    assert(#assert(fs.DirListFiles(folder, "*.csv")) == 1)
    assert(#assert(fs.DirListFolders(folder)) == 1)

    local watch = assert(fs.DirWatchOpen(folder, false, fs.watchFlags.file_name))
    local watched, watchError = xpcall(function()
        local pending = {}
        for i = 1, 12 do
            local name = "event-" .. i
            pending[name] = true
            assert(fs.FileWriteBytes(fs.PathJoin(folder, name), ""))
        end
        for _ = 1, 12 do
            local change = assert(fs.DirWatchNext(watch, 2000))
            assert(change.action == fs.watchActions.added and pending[change.name])
            pending[change.name] = nil
        end
        assert(next(pending) == nil)
        assert(fs.DirWatchNext(watch, 0) == false)
    end, debug.traceback)
    assert(fs.DirWatchClose(watch))
    assert(watched, watchError)

    local hidden = fs.PathJoin(folder, "hidden.dat")
    assert(fs.FileWriteBytes(hidden, "previous"))
    assert(fs.PathHiddenAttrSet(hidden, true))
    for _, mode in ipairs({"w", "w+"}) do
        local handle = assert(fs.Open(hidden, mode))
        assert(handle:GetSize() == 0)
        assert(handle:Write("new") == 3)
        assert(handle:Close())
        assert(assert(fs.FileGetInfo(hidden)).hidden)
    end

    local crypto = require("crypto")
    for _, pair in ipairs({{"", ""}, {"f", "Zg=="}, {"fo", "Zm8="}, {"foo", "Zm9v"}, {"\0\255", "AP8="}}) do
        assert(crypto.Base64Encode(pair[1]) == pair[2])
        assert(crypto.Base64Decode(pair[2]) == pair[1])
    end
    for _, bad in ipairs({"A===", "Zm=v", "Zg", "Zm9v ", "!!!!", "Zg==junk"}) do
        assert(crypto.Base64Decode(bad) == nil)
    end
    local originalRead = native.FsRead
    native.FsRead = function() return nil, "test read error" end
    local called, result, message, code = pcall(crypto.DecryptFile, settings, file, "pass")
    native.FsRead = originalRead
    assert(called and result == nil and message == "test read error" and code == nil)
    assert(fs.FileRead(file, "BINARY") == previous)
end

local function sqlite()
    local sql = require("sqlite")
    local db = assert(sql.Open(":memory:"))
    local ok, err = xpcall(function()
        assert(db:Exec("CREATE TABLE t (value BLOB)") == 0)
        assert(db:Exec("INSERT INTO t VALUES (?)", {assert(sql.Blob("\0\255"))}) == 1)
        assert(db:Exec("INSERT INTO t VALUES (?)", {sql.NULL}) == 1)
        local rows = assert(db:Query("SELECT value FROM t ORDER BY rowid; \r\n"))
        assert(#rows == 2 and rows[1].value == "\0\255" and rows[2].value == sql.NULL)
        assert(db:Exec("DELETE FROM t; SELECT 1") == nil)
        assert(assert(db:Query("SELECT COUNT(*) AS n FROM t"))[1].n == 2)
        assert(db:Query("SELECT ?, ?", {1}) == nil)
    end, debug.traceback)
    assert(db:Close())
    assert(ok, err)
end

local function zip(folder)
    local zip = require("zip")
    local source = fs.PathJoin(folder, "O’Neil")
    local name = "‘отчёт’ №1.txt"
    local archive = fs.PathJoin(folder, "Пакет.zip")
    local dest = fs.PathJoin(folder, "Копия")
    assert(fs.DirCreate(source))
    assert(fs.FileWriteBytes(fs.PathJoin(source, name), "abc\0"))
    assert(fs.FileWriteBytes(fs.PathJoin(source, "other.txt"), "other"))
    assert(zip.Create(source, archive, false, "include", {name}))
    local rows = assert(zip.List(archive))
    assert(#rows == 2)
    local found = false
    for _, row in ipairs(rows) do
        if row.name == "O’Neil/" .. name then found = row.size == 4 and row.isDir == false end
    end
    assert(found)
    assert(zip.Extract(archive, dest, {include = {}}))
    assert(fs.DirExists(dest) == false)
    assert(zip.Extract(archive, dest))
    assert(fs.FileRead(fs.PathJoin(dest, "O’Neil", name), "BINARY") == "abc\0")
    assert(fs.FileExists(fs.PathJoin(dest, "O’Neil", "other.txt")) == false)
    assert(zip.Extract(archive, dest) == nil)
    assert(zip.Extract(archive, dest, {overwrite = true}))
end

local folder = assert(fs.TempDirCreate())
local ok, problem = xpcall(function()
    if suite == "all" or suite == "core" then core(folder); print("core OK") end
    if suite == "all" or suite == "sqlite" then sqlite(); print("sqlite OK") end
    if suite == "all" or suite == "zip" then zip(folder); print("zip OK") end
end, debug.traceback)
local cleaned, cleanupError = fs.DirDelete(folder, true)
if not cleaned then io.stderr:write(tostring(cleanupError), "\n") end
assert(ok, problem)
assert(cleaned, cleanupError)
