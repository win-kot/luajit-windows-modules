local source = debug.getinfo(1, "S").source
local dir = source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))()
local g = require('gui')
assert(g.WindowClient('Always-on-Top Window', 400, 150, 'fixed', 'center'))
assert(g.CheckBox('topmost', 'Always on top', 20, 20, 250, 28))
assert(g.CheckedSet('topmost', true))
assert(g.WindowTopmostSet(true))
assert(g.OnClick('topmost', function()
    assert(g.WindowTopmostSet(g.IsChecked('topmost')))
end))
assert(g.Run())
