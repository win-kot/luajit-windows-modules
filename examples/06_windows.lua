local source = debug.getinfo(1, "S").source:sub(2)
local dir = source:match("^(.*)[/\\][^/\\]+$") or "."
dofile(dir .. "/../setup_paths.lua")

local window = require("window")
local uio = require("unicode_io")

-- Optional argument: part of a window title. An empty string matches all titles.
local handles, err = window.findAll(arg[1] or "", false)
assert(handles ~= nil, err)
print("Matching visible windows:", #handles)
for index, hwnd in ipairs(handles) do
    local title, titleErr = window.getTitle(hwnd)
    if title then
        uio.print(index, title)
    else
        print(index, "Window no longer available:", titleErr)
    end
end
-- This example only lists windows; it does not activate, move, or close them.
