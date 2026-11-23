local ffi = require("ffi")
local win = require("_win_extension")
local desktop = require("_desktop")
local options = require("_options")
local fs = require("fs")
local signatures = {
    link_write = "int32_t (*)(const uint16_t *, const uint16_t *, const uint16_t *, const uint16_t *, const uint16_t *, const uint16_t *, int)",
    link_read = "int32_t (*)(const uint16_t *, uint16_t *, uint16_t *, uint16_t *, uint16_t *, uint16_t *, int *, int)"
}

return function(shell)
    function shell.CreateShortcut(linkPath, target, opts)
        local optionError
        opts, optionError = options(opts, {arguments = "string", workingDir = "string", description = "string",
            iconPath = "string", iconIndex = "number"})
        if not opts then return nil, optionError end
        if not win.Integer(opts.iconIndex or 0, -2147483648, 2147483647) then return nil, "Недопустимый индекс значка" end
        local link, err, code = fs.PathAbsolute(linkPath)
        if not link then return nil, err, code end
        if link:sub(-4):lower() ~= ".lnk" then return win.Error("Expected a .lnk path", 87) end
        return desktop.Com(function()
            local api, message, status = desktop.Functions(signatures)
            if not api then return nil, message, status end
            local values = {link, target, opts.arguments, opts.workingDir, opts.description, opts.iconPath}
            local wide = {}
            for i = 1, 6 do
                if values[i] ~= nil or i <= 2 then
                    wide[i], message, status = win.ToWide(values[i])
                    if not wide[i] then return nil, message, status end
                end
            end
            if target == "" then return win.Error("Shortcut target is empty", 87) end
            return desktop.Error("IShellLinkW save", api.link_write(wide[1], wide[2], wide[3], wide[4],
                wide[5], wide[6], opts.iconIndex or 0))
        end)
    end

    function shell.ReadShortcut(linkPath)
        local link, err, code = fs.PathAbsolute(linkPath)
        if not link then return nil, err, code end
        local wide
        wide, err, code = win.ToWide(link)
        if not wide then return nil, err, code end
        return desktop.Com(function()
            local api, message, status = desktop.Functions(signatures)
            if not api then return nil, message, status end
            local size = 32768
            local fields = {"target", "arguments", "workingDir", "description", "iconPath"}
            local buffers = {}
            for i = 1, #fields do buffers[i] = ffi.new("uint16_t[?]", size) end
            local index = ffi.new("int[1]")
            status = api.link_read(wide, buffers[1], buffers[2], buffers[3], buffers[4], buffers[5], index, size)
            if status < 0 then return desktop.Error("IShellLinkW load", status) end
            local result = {iconIndex = index[0]}
            for i, name in ipairs(fields) do
                result[name], message, status = win.FromWide(buffers[i])
                if not result[name] then return nil, message, status end
            end
            return result
        end)
    end
end
