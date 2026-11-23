local fs = require("fs")
local json = require("json")
local options = require("_options")
local win = require("_win_extension")

local M = {}
local levels = {trace = 1, debug = 2, info = 3, warn = 4, error = 5, fatal = 6, off = 7}
local threshold = levels.info
local filename

local function absolutePath(path)
    local wide, err, code = win.PathWide(path)
    if not wide then return nil, err, code end
    return win.FromWide(wide)
end

local function fileInfo(path)
    local info, err, code = fs.FileGetInfo(path)
    if info then
        if info.is_dir then return win.Error("Log path is a directory", 267) end
        return info
    end
    if code == 2 or code == 3 then return false end
    return nil, err, code
end

function M.SetFile(path)
    if path == nil then
        filename = nil
        return true
    end
    local absolute, err, code = absolutePath(path)
    if not absolute then return nil, err, code end
    local info
    info, err, code = fileInfo(absolute)
    if info == nil then return nil, err, code end
    filename = absolute
    return true
end

function M.SetLevel(level)
    if not levels[level] then return nil, "Неизвестный уровень журнала" end
    threshold = levels[level]
    return true
end

function M.Write(level, message, fields)
    if not levels[level] or level == "off" then return nil, "Недопустимый уровень сообщения журнала" end
    if type(message) ~= "string" then return nil, "Сообщение журнала должно быть строкой" end
    if fields ~= nil and type(fields) ~= "table" then return nil, "Поля журнала должны быть таблицей" end
    if levels[level] < threshold then return true end
    local line, err = json.Encode({
        time = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        level = level,
        message = message,
        fields = fields
    })
    if not line then return nil, err, 13 end
    line = line .. "\n"
    if not filename then
        local ok, reason, code = io.stderr:write(line)
        if not ok then return nil, reason, code end
        return true
    end
    local file, reason, code = fs.Open(filename, "a", {share = "readwrite"})
    if not file then return nil, reason, code end
    local written
    written, reason, code = file:Write(line)
    local closed, closeError, closeCode = file:Close()
    if written == nil then return nil, reason, code end
    if written ~= #line then return win.Error("Incomplete log write", 29) end
    if not closed then return nil, closeError, closeCode end
    return true
end

function M.Rotate(opts)
    local optionError
    opts, optionError = options(opts, {path = "string", maxBytes = "number"})
    if not opts then return nil, optionError end
    local limit = opts.maxBytes
    if limit ~= nil and not win.Integer(limit, 0, 9007199254740991) then return nil, "Недопустимый размер maxBytes" end
    local name, err, code = filename
    if opts.path then
        name, err, code = absolutePath(opts.path)
        if not name then return nil, err, code end
    end
    if not name then return win.Error("No log file selected", 87) end
    local info
    info, err, code = fileInfo(name)
    if info == nil then return nil, err, code end
    if info == false or info.size == 0 or (limit and info.size < limit) then return true end
    local source, target
    source, err, code = win.PathWide(name)
    if not source then return nil, err, code end
    target, err, code = win.PathWide(name .. ".1")
    if not target then return nil, err, code end
    if win.kernel.MoveFileExW(source, target, 1) == 0 then
        code = tonumber(win.kernel.GetLastError())
        if code == 2 or code == 3 then return true end
        return win.Error("MoveFileExW(log rotation)", code)
    end
    return true
end

return M
