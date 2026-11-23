local win = require("_win_extension")
local desktop = require("_desktop")
local fs = require("fs")

return function(shell)
    function shell.Recycle(path)
        if type(path) ~= "string" or path == "" or path:find('[<>|"*?%c]') then
            return win.Error("Expected a single file or directory path", 87)
        end
        for component in path:gsub("^%a:", ""):gmatch("[^/\\]+") do
            if component:find(":", 1, true) or
                (component ~= "." and component ~= ".." and component:find("[ .]$")) then
                return win.Error("Invalid file or directory path", 87)
            end
        end
        local absolute, err, code = fs.PathAbsolute(path)
        if not absolute then return nil, err, code end
        absolute = absolute:gsub("\\+$", "")
        if not absolute:match("^%a:\\.") then return win.Error("Expected a local file or directory path", 87) end
        local wide
        wide, err, code = win.ToWide(absolute)
        if not wide then return nil, err, code end
        return desktop.Com(function()
            local recycle, message, status = desktop.Symbol("fw_recycle", "int32_t (*)(const uint16_t *)")
            if not recycle then return nil, message, status end
            return desktop.Error("Move to Recycle Bin", recycle(wide))
        end)
    end
end
