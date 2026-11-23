local source = debug.getinfo(1, "S").source
local dir = source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))()

local g = require('gui')
local window = assert(g.WindowClient('Project path', 500, 185, "fixed"))
assert(g.Label("label1", 'Drag a folder from File Explorer into the field:', 20, 18, 455, 25))
assert(g.Edit("edit1", '', 20, 48, 450, 26))
assert(g.Button("button1", 'Show a long path', 20, 100, 200, 30))

-- On drop, show the end of the full path without a blinking caret.
assert(g.OnDropFiles("edit1", function(paths)
    if paths[1] then
        assert(g.TextEndSet("edit1", paths[1]))
    end
end))

-- Demonstrate the text field without drag and drop.
assert(g.OnClick("button1", function()
    assert(g.TextEndSet("edit1", 'C:\\Проекты 文 日本\\Очень длинное название папки\\Исходный код\\MyProject'))
end))

assert(g.Run())
