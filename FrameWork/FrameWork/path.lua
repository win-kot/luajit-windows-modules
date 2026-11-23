local native = require("_win_native")
local fs = require("fs")
local win = require("_win_extension")
local str = require("str")
local M = {}

local function checked(value)
    if type(value) ~= "string" or value:find("\0", 1, true) or not str.IsValidUtf8(value) then
        return nil, "Требуется путь в UTF-8 без нулевого байта"
    end
    if value:sub(1, 4) == "\\\\?\\" or value:sub(1, 4) == "\\\\.\\" then return value end
    return (value:gsub("/", "\\"))
end

local function split_root(path)
    local prefix = path:sub(1, 4)
    if prefix == "\\\\?\\" or prefix == "\\\\.\\" then
        if #path == 4 or path:sub(5):upper() == "UNC" then return path, "", false end
        if path:sub(5, 8):upper() == "UNC\\" then
            local root, tail = path:match("^(........[^\\]+\\[^\\]+)\\*(.*)$")
            if root then return root .. "\\", tail, true end
            return path, "", false
        end
        if path:match("^....%a:") and path:sub(7, 7) ~= "\\" then return path, "", false end
        local root, tail = path:match("^(....[^\\]+)\\*(.*)$")
        return root and root .. "\\" or path, tail or "", true
    end
    local share, tail = path:match("^(\\\\[^\\]+\\[^\\]+)\\*(.*)$")
    if share and not share:match("\\%.%.?$") then return share .. "\\", tail, true end
    if path:sub(1, 2) == "\\\\" then return path, "", false end
    local drive = path:match("^([A-Za-z]:)")
    if drive then
        if path:sub(3, 3) == "\\" then return drive .. "\\", path:sub(4), true end
        return drive, path:sub(3), false
    end
    if path:sub(1, 1) == "\\" then return "\\", path:gsub("^\\+", ""), false end
    return "", path, false
end

function M.IsAbsolute(value)
    local path, err = checked(value); if not path then return nil, err end
    local _, _, absolute = split_root(path)
    return absolute
end

function M.GetRoot(value)
    local path, err = checked(value); if not path then return nil, err end
    return (split_root(path))
end

function M.GetTempFile(prefix)
    if prefix == nil then prefix = "fw-" end
    if not (type(prefix) == "string" and str.IsValidUtf8(prefix) and #prefix <= 100 and
        not prefix:find('[%z\1-\31<>:"/\\|?*]')) then return nil, "Недопустимый префикс временного файла" end
    local dir, err, code = native.OsTmpDir()
    if not dir then return nil, err, code end
    local file, name
    file, name, code = native.FsMkstemp(M.Join(dir, prefix .. "XXXXXX"))
    if not file then return nil, name, code end
    local ok
    ok, err, code = native.FsClose(file)
    if not ok then native.FsUnlink(name); return nil, err, code end
    return name
end

function M.IsUNC(value)
    local path, err = checked(value); if not path then return nil, err end
    local _, _, absolute = split_root(path)
    local prefix = path:sub(1, 4)
    return absolute and (((prefix == "\\\\?\\" or prefix == "\\\\.\\") and path:sub(5, 8):upper() == "UNC\\") or
        (path:sub(1, 2) == "\\\\" and path:sub(1, 4) ~= "\\\\?\\" and path:sub(1, 4) ~= "\\\\.\\"))
end

function M.Normalize(value)
    local path, err = checked(value); if not path then return nil, err end
    if path:sub(1, 4) == "\\\\?\\" or path:sub(1, 4) == "\\\\.\\" then return path end
    local root, rest = split_root(path)
    local anchored = root:sub(-1) == "\\"
    local parts = {}
    for part in rest:gmatch("[^\\]+") do
        if part == ".." then
            if #parts > 0 and parts[#parts] ~= ".." then
                parts[#parts] = nil
            elseif not anchored then
                parts[#parts + 1] = part
            end
        elseif part ~= "." then
            parts[#parts + 1] = part
        end
    end
    local result = root .. table.concat(parts, "\\")
    return result == "" and "." or result
end

function M.Join(...)
    local result = ""
    for i = 1, select("#", ...) do
        local part = select(i, ...)
        if part ~= "" then
            local detail; part, detail = checked(part); if not part then return nil, detail end
            local root = split_root(part)
            if root == "\\" and result ~= "" then
                local base = split_root(result)
                result = base:gsub("\\+$", "") .. part
            elseif root ~= "" or result == "" then
                result = part
            else
                local base, tail = split_root(result)
                local needs_separator = result:sub(-1) ~= "\\" and not (base:sub(-1) == ":" and tail == "")
                result = result .. (needs_separator and "\\" or "") .. part
            end
        end
    end
    return result == "" and "." or M.Normalize(result)
end

function M.Split(value)
    local path, err = checked(value); if not path then return nil, err end
    local root, rest = split_root(path)
    rest = rest:gsub("\\+$", "")
    local dir, name = rest:match("^(.*)\\([^\\]+)$")
    if dir then return root .. dir, name end
    return root, rest
end

function M.GetName(value)
    local dir, name = M.Split(value)
    if dir == nil then return nil, name end
    return name
end
function M.GetDir(value)
    local dir, second = M.Split(value)
    if dir == nil then return nil, second end
    return dir
end

function M.GetExtension(value)
    local name, err = M.GetName(value); if name == nil then return nil, err end
    local stem, extension = name:match("^(.*)(%.[^.]*)$")
    return stem and stem ~= "" and extension or ""
end

function M.ChangeExtension(value, extension)
    local dir, name = M.Split(value)
    if dir == nil then return nil, name end
    if type(extension) ~= "string" or extension:find('[%z\1-\31<>:"/\\|?*]') or not str.IsValidUtf8(extension) then
        return nil, "Недопустимое расширение файла"
    end
    if name == "" then return nil, "Путь не содержит имени файла" end
    local old = M.GetExtension(value)
    if #old > 0 then name = name:sub(1, #name - #old) end
    if extension ~= "" and extension:sub(1, 1) ~= "." then extension = "." .. extension end
    if dir == "" or dir:sub(-1) == "\\" or dir:match("^%a:$") then
        return dir .. name .. extension
    end
    return dir .. "\\" .. name .. extension
end

function M.GetAbsolute(value, base)
    local detail; value, detail = checked(value); if not value then return nil, detail end
    if value:sub(1, 2) == "\\\\" and not M.IsAbsolute(value) then
        return nil, "incomplete Windows namespace or UNC path", 87
    end
    if base and not M.IsAbsolute(value) then
        local absolute, err, code = M.GetAbsolute(base)
        if not absolute then return nil, err, code end
        local root, rest = split_root(value)
        if root:match("^%a:$") then
            local drive = absolute:match("^(%a:)") or absolute:match("^....(%a:)")
            if not drive or root:upper() ~= drive:upper() then
                return nil, "drive-relative path does not match the base drive", 87
            end
            value = M.Join(absolute, rest)
        else
            value = M.Join(absolute, value)
        end
    end
    return fs.PathAbsolute(value == "" and "." or value)
end

-- NT path components use ordinal case comparison, without Unicode expansions.
local function sameComponent(left, right)
    if left == right then return true end
    local a, an, code = win.ToWide(left)
    if not a then return nil, an, code end
    local b, bn
    b, bn, code = win.ToWide(right)
    if not b then return nil, bn, code end
    if an ~= bn then return false end
    local result = win.kernel.CompareStringOrdinal(a, an, b, bn, 1)
    if result == 0 then return win.Error("CompareStringOrdinal") end
    return result == 2
end

function M.GetRelative(value, base)
    local target, err, code = M.GetAbsolute(value)
    if not target then return nil, err, code end
    local origin
    origin, err, code = M.GetAbsolute(base == nil and "." or base)
    if not origin then return nil, err, code end
    local targetRoot, targetTail = split_root(target)
    local baseRoot, baseTail = split_root(origin)
    -- A relative path cannot carry the literal semantics of a Windows namespace.
    if target:sub(1, 4) == "\\\\?\\" or target:sub(1, 4) == "\\\\.\\" or
        origin:sub(1, 4) == "\\\\?\\" or origin:sub(1, 4) == "\\\\.\\" then
        if target == origin then return "." end
        return target
    end
    local same; same, err, code = sameComponent(targetRoot, baseRoot)
    if same == nil then return nil, err, code end
    if not same then return target end
    local left, right = {}, {}
    for part in targetTail:gmatch("[^\\]+") do left[#left + 1] = part end
    for part in baseTail:gmatch("[^\\]+") do right[#right + 1] = part end
    local i = 1
    while left[i] and right[i] do
        same, err, code = sameComponent(left[i], right[i])
        if same == nil then return nil, err, code end
        if not same then break end
        i = i + 1
    end
    local result = {}
    for _ = i, #right do result[#result + 1] = ".." end
    for j = i, #left do result[#result + 1] = left[j] end
    return #result == 0 and "." or table.concat(result, "\\")
end

return M
