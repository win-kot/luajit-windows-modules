local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local window = require("window")
assert(arg[1] and arg[2], "Usage: luajit 29_copydata_send.lua WINDOW_TITLE TEXT [DATA_ID]")
local id = arg[3] and assert(tonumber(arg[3]), "DATA_ID must be a number") or 0
local hwnd = assert(window.Find(arg[1]))
local result, err = window.CopyDataSend(hwnd, arg[2], id, 1000)
if result == false then
    print("Timed out waiting for a response")
else
    assert(result ~= nil, err)
    print("LRESULT", result)
end
