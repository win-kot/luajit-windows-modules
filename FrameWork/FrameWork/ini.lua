local str = require("str")
local fs = require("fs")
local native = require("_win_native")
local ini = {}
local bom = "\239\187\191"

local function trim(text)
    local first = text:find("[^ \t]")
    if not first then return "" end
    local last = #text
    while text:byte(last) == 32 or text:byte(last) == 9 do last = last - 1 end
    return text:sub(first, last)
end

local function validate(section, key)
    if section ~= nil then
        if not (type(section) == "string" and str.IsValidUtf8(section) and
            not section:find("[%z\r\n%[%]]") and trim(section) == section) then return nil, "Недопустимое имя секции INI" end
    end
    if key ~= nil then
        if not (type(key) == "string" and key ~= "" and str.IsValidUtf8(key) and
            not key:find("[%z\r\n=]") and not key:match("^[;#%[]") and trim(key) == key) then return nil, "Недопустимый ключ INI" end
    end
    return true
end

local function parse(text)
    local prefix = ""
    if text:sub(1, 3) == bom then prefix, text = bom, text:sub(4) end
    if not str.IsValidUtf8(text) or text:find("\0", 1, true) then return nil, "INI file must be UTF-8" end
    local rows, section, ending, pos = {}, "", nil, 1
    while pos <= #text do
        local split = text:find("[\r\n]", pos)
        local line = text:sub(pos, split and split - 1 or #text)
        local eol = ""
        if split then
            eol = text:sub(split, split + 1) == "\r\n" and "\r\n" or text:sub(split, split)
            ending = ending or eol
        end
        local clean = trim(line)
        local heading = clean:match("^%[([^%[%]]+)%][ \t]*[;#].*$") or clean:match("^%[([^%[%]]+)%]$")
        local key, value
        if heading then
            section = trim(heading)
        elseif not clean:match("^[;#%[]") then
            key, value = clean:match("^([^=]+)=(.*)$")
            if key then
                key, value = trim(key), trim(value)
                if key == "" then key = nil end
            end
        end
        rows[#rows + 1] = {line=line, eol=eol, section=section, heading=heading ~= nil, key=key, value=value}
        pos = split and split + #eol or #text + 1
    end
    return rows, prefix, ending or "\r\n"
end

local function read(path, allowMissing)
    local text, err, code = fs.FileRead(path, "BINARY")
    if not text then
        if not allowMissing or (code ~= 2 and code ~= 3) then return nil, err, code end
        text = ""
    end
    return parse(text)
end

function ini.Read(path, section, key)
    local valid, validationError = validate(section, key)
    if not valid then return nil, validationError end
    local rows, err, code = read(path)
    if not rows then return nil, err, code end
    if key ~= nil then
        section = section or ""
        for i = #rows, 1, -1 do
            local row = rows[i]
            if row.section == section and row.key == key then return row.value end
        end
        return nil
    end
    local values = {[""] = {}}
    for _, row in ipairs(rows) do
        local group = values[row.section] or {}
        values[row.section] = group
        if row.key then group[row.key] = row.value end
    end
    if section ~= nil then return values[section] end
    return values
end

local function save(path, rows, prefix)
    local chunks = {prefix}
    for _, row in ipairs(rows) do chunks[#chunks + 1] = row.line .. row.eol end
    local file, temp, code = native.FsMkstemp(fs.PathJoin(fs.PathDirName(path), ".fw-ini-XXXXXX"))
    if not file then return nil, temp, code end
    local data = table.concat(chunks)
    local written, err, code = native.FsWrite(file, data)
    local closed, closeError, closeCode = native.FsClose(file)
    if written ~= #data or not closed then
        native.FsUnlink(temp)
        if written ~= #data then return nil, err or "Incomplete INI write", code end
        return nil, closeError, closeCode
    end
    local ok
    ok, err, code = fs.FileMove(temp, path, true)
    if not ok then native.FsUnlink(temp) end
    return ok, err, code
end

function ini.Write(path, section, key, value)
    local valid, validationError = validate(section, key)
    if not valid then return nil, validationError end
    if key == nil then return nil, "Требуется ключ INI" end
    local kind = type(value)
    if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then return nil, "Недопустимое значение INI" end
    value = tostring(value)
    if not str.IsValidUtf8(value) or value:find("[%z\r\n]") or trim(value) ~= value then return nil, "Недопустимый текст значения INI" end
    local target, err, code = fs.PathAbsolute(path)
    if not target then return nil, err, code end
    local rows, prefix, ending = read(target, true)
    if not rows then return nil, prefix, ending end
    section = section or ""
    local location, match = section == "" and 0 or nil, nil
    for index, row in ipairs(rows) do
        if row.section == section then
            location = index
            if row.key == key then match = index end
        end
    end
    local line = key .. "=" .. value
    if match then
        rows[match].line = line
    else
        if not location then
            local last = rows[#rows]
            if last and last.eol == "" then last.eol = ending end
            rows[#rows + 1] = {line="[" .. section .. "]", eol=ending}
            location = #rows
        end
        if location > 0 and rows[location].eol == "" then rows[location].eol = ending end
        table.insert(rows, location + 1, {line=line, eol=ending})
    end
    return save(target, rows, prefix)
end

function ini.Delete(path, section, key)
    local valid, validationError = validate(section, key)
    if not valid then return nil, validationError end
    local target, err, code = fs.PathAbsolute(path)
    if not target then return nil, err, code end
    local rows, prefix, ending = read(target)
    if not rows then
        if ending == 2 or ending == 3 then return true end
        return nil, prefix, ending
    end
    local kept = {}
    for _, row in ipairs(rows) do
        if row.section ~= (section or "") or (key ~= nil and row.key ~= key) then
            kept[#kept + 1] = row
        end
    end
    if #kept == #rows then return true end
    return save(target, kept, prefix)
end

return ini
