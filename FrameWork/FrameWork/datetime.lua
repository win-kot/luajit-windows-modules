local datetime = {}
local defaultFormat = "%Y-%m-%d %H:%M:%S"
local fields = {"year", "month", "day", "hour", "min", "sec"}
local elapsed = {second=1, minute=60, hour=3600, day=86400, week=604800}
local monthLengths = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}

local function toInteger(value)
    if type(value) == "number" and math.abs(value) <= 9007199254740991 and value % 1 == 0 then
        return value
    end
end

local function daysInMonth(year, month)
    if month == 2 then
        return (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)) and 29 or 28
    end
    return monthLengths[month]
end

-- Gregorian calendar day number relative to 1970-01-01.
local function dayNumber(year, month, day)
    if month <= 2 then year = year - 1 end
    local era = math.floor(year / 400)
    local within = year % 400
    local shifted = month > 2 and month - 3 or month + 9
    return era * 146097 + within * 365 + math.floor(within / 4) - math.floor(within / 100) +
        math.floor((153 * shifted + 2) / 5) + day - 719469
end

local function wallSeconds(value)
    return dayNumber(value.year, value.month, value.day) * 86400 +
        value.hour * 3600 + value.min * 60 + value.sec
end

local function readDate(timestamp, utc)
    if not toInteger(timestamp) then return nil, "timestamp outside supported range" end
    local ok, value = pcall(os.date, utc and "!*t" or "*t", timestamp)
    if not ok then return nil, value end
    if not value then return nil, "timestamp outside supported range" end
    value.timestamp = timestamp
    value.offsetMinutes = utc and 0 or math.floor((wallSeconds(value) - timestamp) / 60)
    if utc then value.utc = true end
    return value
end

local function localTimestamp(value)
    local copy = {}
    for _, name in ipairs(fields) do copy[name] = value[name] end
    copy.isdst = value.isdst
    local ok, result = pcall(os.time, copy)
    if not ok then return nil, result end
    if result == nil then return nil, "local date outside supported range" end
    return result
end

local function dateTimestamp(value)
    if type(value) ~= "table" then return nil, "Требуется таблица даты" end
    if value.timestamp ~= nil then
        if not toInteger(value.timestamp) then return nil, "timestamp должен быть целым числом" end
        return toInteger(value.timestamp)
    end
    local date = {hour=0, min=0, sec=0, isdst=value.isdst}
    for _, field in ipairs(fields) do
        if value[field] ~= nil then date[field] = toInteger(value[field]) end
    end
    local year, month, day = date.year, date.month, date.day
    if not year or year < 1 or year > 9999 or not month or not day or
        day < 1 or day > (daysInMonth(year, month) or 0) or
        not date.hour or date.hour < 0 or date.hour > 23 or
        not date.min or date.min < 0 or date.min > 59 or
        not date.sec or date.sec < 0 or date.sec > 59 then
        return nil, "invalid calendar date or time"
    end
    if value.utc == true then return wallSeconds(date) end
    local timestamp, err = localTimestamp(date)
    if not timestamp then return nil, err end
    local result
    result, err = readDate(timestamp, false)
    if not result then return nil, err end
    if wallSeconds(result) ~= wallSeconds(date) then return nil, "invalid local time" end
    return timestamp
end

function datetime.Now()
    return readDate(os.time(), false)
end

function datetime.Format(value, format)
    if type(value) ~= "table" then return nil, "Требуется таблица даты" end
    if format ~= nil and (type(format) ~= "string" or format == "*t" or format == "!*t") then return nil, "Требуется строковый формат даты" end
    local timestamp, err = dateTimestamp(value)
    if not timestamp then return nil, err end
    local date
    date, err = readDate(timestamp, value.utc == true)
    if not date then return nil, err end
    format = format or defaultFormat
    if value.utc and format:sub(1, 1) ~= "!" then format = "!" .. format end
    local ok, result = pcall(os.date, format, timestamp)
    if not ok then return nil, result end
    return result
end

local directives = {Y="year", m="month", d="day", H="hour", M="min", S="sec"}
local function parsePattern(format)
    local pattern, names, seen = {"^"}, {}, {}
    local i = 1
    while i <= #format do
        local ch = format:sub(i, i)
        if ch == "%" then
            i = i + 1
            local code = format:sub(i, i)
            local name = directives[code]
            if code == "%" then
                pattern[#pattern + 1] = "%%"
            elseif name and not seen[name] then
                seen[name] = true
                names[#names + 1] = name
                pattern[#pattern + 1] = code == "Y" and "([0-9][0-9][0-9][0-9])" or "([0-9][0-9])"
            else
                return nil, "invalid or repeated date format directive: %" .. code
            end
        else
            if ch:find("[%^%$%(%)%.%[%]%*%+%-%?]") then ch = "%" .. ch end
            pattern[#pattern + 1] = ch
        end
        i = i + 1
    end
    if not (seen.year and seen.month and seen.day) then return nil, "format must include year, month and day" end
    pattern[#pattern + 1] = "$"
    return table.concat(pattern), names
end

function datetime.Parse(text, format)
    if type(text) ~= "string" then return nil, "Дата должна быть строкой" end
    if format ~= nil and type(format) ~= "string" then return nil, "Формат даты должен быть строкой" end
    if format == nil then
        format = #text == 10 and "%Y-%m-%d" or
            (text:sub(-1) == "Z" and "!%Y-%m-%dT%H:%M:%SZ") or
            (text:sub(11, 11) == "T" and "%Y-%m-%dT%H:%M:%S") or defaultFormat
    end
    local utc = format:sub(1, 1) == "!"
    local pattern, names = parsePattern(utc and format:sub(2) or format)
    if not pattern then return nil, names end
    local values = {text:match(pattern)}
    if #values == 0 then return nil, "date does not match format" end
    local value = {hour=0, min=0, sec=0}
    for i, name in ipairs(names) do value[name] = tonumber(values[i]) end
    local days = daysInMonth(value.year, value.month)
    if value.year < 1 or not days or value.day < 1 or value.day > days or
        value.hour > 23 or value.min > 59 or value.sec > 59 then
        return nil, "invalid calendar date or time"
    end
    local timestamp, err
    if utc then timestamp = wallSeconds(value)
    else timestamp, err = localTimestamp(value) end
    if not timestamp then return nil, err end
    local result
    result, err = readDate(timestamp, utc)
    if not result then return nil, err end
    for _, name in ipairs(fields) do
        if result[name] ~= value[name] then return nil, "invalid local time" end
    end
    return result
end

local function normalizeUnit(unit)
    if type(unit) ~= "string" then return nil end
    return (unit:gsub("s$", ""))
end

function datetime.Add(value, unit, amount)
    unit = normalizeUnit(unit)
    if type(amount) ~= "number" or not toInteger(amount) then return nil, "Ожидается целое число единиц времени" end
    amount = toInteger(amount)
    local timestamp, err = dateTimestamp(value)
    if not timestamp then return nil, err end
    local utc = value.utc == true
    local seconds = elapsed[unit]
    if not seconds and unit ~= "year" and unit ~= "month" then return nil, "Неизвестная единица времени" end
    if seconds and unit ~= "day" and unit ~= "week" then
        return readDate(timestamp + amount * (seconds + 0.0), utc)
    end
    if amount < -10000000 or amount > 10000000 then return nil, "calendar amount outside supported range" end
    local date
    date, err = readDate(timestamp, utc)
    if not date then return nil, err end
    if unit == "day" or unit == "week" then
        date.day = date.day + amount * (unit == "week" and 7 or 1)
    else
        local months = date.year * 12 + date.month - 1 + amount * (unit == "year" and 12 or 1)
        date.year, date.month = math.floor(months / 12), months % 12 + 1
        date.day = math.min(date.day, daysInMonth(date.year, date.month))
    end
    if utc then
        timestamp = wallSeconds(date)
    else
        date.isdst = nil
        timestamp, err = localTimestamp(date)
    end
    if not timestamp then return nil, err end
    local result
    result, err = readDate(timestamp, utc)
    if not result then return nil, err end
    if wallSeconds(result) ~= wallSeconds(date) then return nil, "invalid local time after calendar addition" end
    return result
end

function datetime.Diff(left, right, unit)
    local seconds = elapsed[normalizeUnit(unit or "seconds")]
    if not seconds then return nil, "Допустимы секунды, минуты, часы, дни или недели" end
    local a, err = dateTimestamp(left)
    if not a then return nil, err end
    local b
    b, err = dateTimestamp(right)
    if not b then return nil, err end
    return os.difftime(a, b) / seconds
end

return datetime
