local fs = require("fs")

local M = {L_InitialWorkingDir = fs.CurrentDirGet()}
local initError, initCode

function M.ScriptPathSet(scriptPath)
    if scriptPath == nil and type(arg) == "table" then scriptPath = arg[0] end
    if type(scriptPath) ~= "string" or scriptPath == "" then
        return nil, "app.ScriptPathSet: укажите путь скрипта или arg[0]"
    end
    local absolute, err, code = fs.PathAbsolute((scriptPath:gsub("/", "\\")))
    if not absolute then return nil, err, code end

    M.L_ScriptPath = absolute
    M.L_ScriptDir = fs.PathDirName(absolute)
    M.L_ScriptName = fs.PathBaseName(absolute)
    initError, initCode = nil, nil
    return true
end

M.WorkingDirGet = fs.CurrentDirGet

function M.GetInfo()
    if initError then return nil, initError, initCode end
    local current, err, code = fs.CurrentDirGet()
    if not current then return nil, err, code end
    return {
        L_ScriptPath = M.L_ScriptPath, L_ScriptDir = M.L_ScriptDir,
        L_ScriptName = M.L_ScriptName, L_WorkingDir = current
    }
end

function M.WorkingDirSet(path)
    if path == nil then
        if initError then return nil, initError, initCode end
        path = M.L_ScriptDir
    end
    if type(path) ~= "string" or path == "" then
        return nil, "WorkingDirSet: укажите непустой путь"
    end
    return fs.CurrentDirSet(path)
end

local _, message, code = M.ScriptPathSet()
initError, initCode = message, code

return setmetatable(M, {__index = function(_, key)
    if key == "L_WorkingDir" then return (fs.CurrentDirGet()) end
end})
