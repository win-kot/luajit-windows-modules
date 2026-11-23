local ffi = require("ffi")
local win = require("_win_extension")
local options = require("_options")
local errors = require("_errors")
local M = {}
local actions = {"created", "deleted", "modified"}

local function invoke(callback, event)
    local ok, err = pcall(callback, event)
    if not ok then return errors.Callback("Subscription callback", err) end
    return 1
end

function M.FileSystem(fs)
    function fs.Watch(path, callback, opts)
        if type(callback) ~= "function" then return nil, "Требуется функция обратного вызова" end
        local optionError
        opts, optionError = options(opts, {recursive = "boolean", filter = "number"})
        if not opts then return nil, optionError end
        local watch, err, code = fs.DirWatchOpen(path, opts.recursive == true, opts.filter)
        if not watch then return nil, err, code end
        local pending
        local function close()
            if watch then
                local ok, reason, status = fs.DirWatchClose(watch)
                if not ok then return nil, reason, status end
                watch = nil
            end
            return true
        end
        local guard = ffi.gc(ffi.new("uint8_t[1]"), close)
        return {
            Close = function()
                local ok, reason, status = close()
                if ok and guard then ffi.gc(guard, nil); guard = nil end
                return ok, reason, status
            end,
            Poll = function(_, timeoutMs)
                if not guard then return win.Error("Directory subscription is closed", 6) end
                local row, reason, status = fs.DirWatchNext(watch, timeoutMs)
                if row == false then return 0 end
                if row == nil then
                    if status == 1022 then pending = nil; return invoke(callback, {action = "overflow"}) end
                    return nil, reason, status
                end
                if row.action == 4 then pending = row.full_path; return 0 end
                local event = {action = actions[row.action] or "renamed", path = row.full_path}
                if row.action == 5 then event.oldPath = pending end
                pending = nil
                return invoke(callback, event)
            end
        }
    end
end

return M
