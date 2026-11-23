local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local window = require("window")
assert(arg[1], "Usage: luajit 27_window_message.lua WINDOW_TITLE")
local hwnd = assert(window.Find(arg[1]))
local result, err = window.MessageSend(hwnd, 0, 0, 0, 1000) -- WM_NULL
if result == false then
    print("The window did not respond in time")
else
    assert(result ~= nil, err)
    print("LRESULT", result)
end
