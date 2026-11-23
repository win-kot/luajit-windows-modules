local str = require("str")
local fs = require("fs")
local encoding = require("encoding")
local csv = {}
local marks = {utf8="\239\187\191", utf16le="\255\254", utf16be="\254\255"}
local numericEncodings = {[65001]="utf8", [1200]="utf16le", [1201]="utf16be"}

local function settings(opts, writing)
    if opts ~= nil and type(opts) ~= "table" then return nil, "Параметры CSV должны быть таблицей" end
    opts = opts or {}
    for name in pairs(opts) do
        if not (name == "delimiter" or name == "encoding" or
            (writing and (name == "bom" or name == "newline" or name == "allowLossy"))) then
            return nil, "Неизвестный параметр CSV"
        end
    end
    local delimiter = opts.delimiter == nil and "," or opts.delimiter
    if not (type(delimiter) == "string" and #delimiter == 1 and
        (delimiter == "\t" or (delimiter:byte() >= 32 and delimiter:byte() <= 126)) and delimiter ~= '"') then
        return nil, "Разделитель CSV должен быть табуляцией или одним печатным символом ASCII, кроме кавычки"
    end
    local textEncoding = opts.encoding
    if textEncoding ~= nil then
        if not (type(textEncoding) == "string" or (type(textEncoding) == "number" and textEncoding % 1 == 0)) then
            return nil, "Недопустимая кодировка CSV"
        end
        if type(textEncoding) == "string" then
            textEncoding = textEncoding:lower()
            textEncoding = tonumber(textEncoding:match("^cp(%d+)$")) or textEncoding
        end
        textEncoding = numericEncodings[textEncoding] or textEncoding
    end
    return delimiter, textEncoding, opts
end

local function parse(data, delimiter)
    if data:find("\0", 1, true) then return nil, "CSV contains NUL" end
    local rows, pos, size = {}, 1, #data
    local special = "[" .. delimiter:gsub("([%%%]%^%-])", "%%%1") .. '"\r\n]'
    while pos <= size do
        local row = {}
        while true do
            local field
            if data:sub(pos, pos) == '"' then
                local pieces = {}
                pos = pos + 1
                while true do
                    local quote = data:find('"', pos, true)
                    if not quote then return nil, "unclosed CSV quote at byte " .. pos end
                    pieces[#pieces + 1] = data:sub(pos, quote - 1)
                    pos = quote + 1
                    if data:sub(pos, pos) ~= '"' then break end
                    pieces[#pieces + 1] = '"'
                    pos = pos + 1
                end
                field = table.concat(pieces)
            else
                local stop = data:find(special, pos) or size + 1
                field = data:sub(pos, stop - 1)
                pos = stop
            end
            row[#row + 1] = field
            local nextByte = data:sub(pos, pos)
            if nextByte == delimiter then
                pos = pos + 1
            else
                if nextByte == "\r" then
                    pos = pos + (data:sub(pos + 1, pos + 1) == "\n" and 2 or 1)
                elseif nextByte == "\n" then
                    pos = pos + 1
                elseif nextByte ~= "" then
                    return nil, "unexpected CSV character at byte " .. pos
                end
                break
            end
        end
        rows[#rows + 1] = row
    end
    return rows
end

function csv.Read(path, opts)
    local delimiter, requested = settings(opts, false)
    if not delimiter then return nil, requested end
    local data, err, code = fs.FileRead(path, "BINARY")
    if not data then return nil, err, code end
    local bom = encoding.DetectBom(data)
    -- UTF-16LE followed by a NUL code unit also starts with the UTF-32LE BOM.
    if bom == "utf32le" and requested == "utf16le" then bom = requested end
    if bom then
        if not marks[bom] then return nil, "unsupported CSV BOM encoding: " .. bom end
        if requested and requested ~= bom then return nil, "CSV BOM does not match requested encoding" end
        data = data:sub(#marks[bom] + 1)
    end
    local source = requested or bom or "utf8"
    if source ~= "utf8" then
        data, err, code = encoding.Convert(data, source, "utf8")
        if not data then return nil, err, code end
    elseif not str.IsValidUtf8(data) then
        return nil, "CSV is not valid UTF-8"
    end
    return parse(data, delimiter)
end

local function arrayLength(array, name)
    if type(array) ~= "table" then return nil, "Требуется массив " .. name end
    local length, count = #array, 0
    for key in next, array do
        if not (type(key) == "number" and key % 1 == 0 and key >= 1 and key <= length) then
            return nil, "Массив " .. name .. " должен быть без пропусков"
        end
        count = count + 1
    end
    if count ~= length then return nil, "Массив " .. name .. " должен быть без пропусков" end
    return length
end

function csv.Write(path, rows, opts)
    local delimiter, target
    delimiter, target, opts = settings(opts, true)
    if not delimiter then return nil, target end
    target = target or "utf8"
    local newline = opts.newline == nil and "\r\n" or opts.newline
    if not (newline == "\r\n" or newline == "\n") then return nil, "Конец строки CSV должен быть CRLF или LF" end
    if not (opts.bom == nil or type(opts.bom) == "boolean") then return nil, "Параметр bom должен быть логическим" end
    if not (opts.allowLossy == nil or type(opts.allowLossy) == "boolean") then return nil, "Параметр allowLossy должен быть логическим" end
    if opts.bom and not marks[target] then return nil, "CSV BOM requires a Unicode encoding" end
    local records = {}
    local count, detail = arrayLength(rows, "строк")
    if not count then return nil, detail end
    for i = 1, count do
        local row, fields = rawget(rows, i), {}
        local length, detail = arrayLength(row, "полей")
        if not length then return nil, detail end
        if length == 0 then return nil, "Строка CSV должна содержать хотя бы одно поле" end
        for j = 1, length do
            local value = rawget(row, j)
            local kind = type(value)
            if not (kind == "string" or kind == "number" or kind == "boolean") then return nil, "В поле CSV допустимы строка, число или логическое значение" end
            local field = tostring(value)
            if not str.IsValidUtf8(field) or field:find("\0", 1, true) then return nil, "invalid CSV field text" end
            if field:find(delimiter, 1, true) or field:find('["\r\n]') or
                (i == 1 and j == 1 and field:sub(1, 3) == marks.utf8) then
                field = '"' .. field:gsub('"', '""') .. '"'
            end
            fields[j] = field
        end
        records[i] = table.concat(fields, delimiter)
    end
    records[count + 1] = ""
    local data = table.concat(records, newline)
    if target ~= "utf8" then
        local err, code
        data, err, code = encoding.Convert(data, "utf8", target, {allowLossy=opts.allowLossy})
        if not data then return nil, err, code end
    end
    if opts.bom then data = marks[target] .. data end
    return fs.FileWriteBytes(path, data)
end

return csv
