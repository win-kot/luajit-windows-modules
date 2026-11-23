local str = require("str")
local json = {}
local null = setmetatable({}, {__tostring = function() return "null" end})
local array = {}
json.null = null

function json.Array(values)
    if type(values) ~= "table" or values == null then return nil, "Требуется таблица массива" end
    return setmetatable(values, array)
end

local function settings(opts)
    local optionError
    opts, optionError = require("_options")(opts, {maxDepth = "number"})
    if not opts then return nil, optionError end
    local limit = opts.maxDepth or 128
    if limit % 1 ~= 0 or limit < 1 or limit > 256 then return nil, "maxDepth должен быть целым числом от 1 до 256" end
    return limit
end

local escaped = {['"']='\\"', ['\\']='\\\\', ['\n']='\\n', ['\r']='\\r',
    ['\t']='\\t', ['\b']='\\b', ['\f']='\\f'}
local function quote(value)
    if not str.IsValidUtf8(value) then error("string is not UTF-8", 0) end
    return '"' .. value:gsub('[%z\1-\31"\\]', function(ch)
        return escaped[ch] or string.format("\\u%04X", ch:byte())
    end) .. '"'
end

function json.Encode(value, opts)
    local limit, optionError = settings(opts)
    if not limit then return nil, optionError end
    local visiting = {}
    local function encode(item, depth)
        local kind = type(item)
        if item == null or kind == "nil" then return "null" end
        if kind == "boolean" then return tostring(item) end
        if kind == "string" then return quote(item) end
        if kind == "number" then
            if item ~= item or math.abs(item) == math.huge then error("non-finite number", 0) end
            return (string.format("%.17g", item):gsub(",", "."))
        end
        if kind ~= "table" then error("unsupported JSON type: " .. kind, 0) end
        if depth >= limit then error("maximum JSON depth exceeded", 0) end
        if visiting[item] then error("cyclic table", 0) end
        visiting[item] = true
        local count, highest, keys = 0, 0, {}
        for key in next, item do
            if type(key) == "string" then
                keys[#keys + 1] = key
            elseif type(key) == "number" and key % 1 == 0 and key > 0 then
                count, highest = count + 1, math.max(highest, key)
            else
                error("invalid JSON table key", 0)
            end
        end
        local result, open, close = {}, "{", "}"
        if count > 0 or getmetatable(item) == array then
            if count ~= highest or #keys > 0 then error("expected dense JSON array", 0) end
            open, close = "[", "]"
            for i = 1, count do result[i] = encode(rawget(item, i), depth + 1) end
        else
            table.sort(keys)
            for i, key in ipairs(keys) do
                result[i] = quote(key) .. ":" .. encode(rawget(item, key), depth + 1)
            end
        end
        visiting[item] = nil
        return open .. table.concat(result, ",") .. close
    end
    local ok, result = pcall(encode, value, 0)
    if not ok then return nil, result end
    return result
end

local unescape = {['"']='"', ['\\']='\\', ['/']='/', b='\b', f='\f', n='\n', r='\r', t='\t'}
function json.Decode(text, opts)
    if type(text) ~= "string" then return nil, "Требуется строка JSON" end
    local limit, optionError = settings(opts)
    if not limit then return nil, optionError end
    local pos = text:sub(1, 3) == "\239\187\191" and 4 or 1
    local function fail(message) error(message .. " at byte " .. pos, 0) end
    local function whitespace()
        pos = select(2, text:find("^[ \r\n\t]*", pos)) + 1
    end
    local function unit()
        local hex = text:sub(pos, pos + 3)
        if #hex ~= 4 or not hex:match("^[0-9A-Fa-f]+$") then fail("invalid Unicode escape") end
        pos = pos + 4
        return tonumber(hex, 16)
    end
    local function readString()
        local out = {}
        pos = pos + 1
        while true do
            local first = text:find('[%z\1-\31"\\]', pos)
            if not first then fail("unterminated string") end
            out[#out + 1] = text:sub(pos, first - 1)
            local ch = text:sub(first, first)
            pos = first + 1
            if ch == '"' then break end
            if ch ~= '\\' then fail("unescaped control character") end
            ch = text:sub(pos, pos)
            pos = pos + 1
            if ch == "u" then
                local cp = unit()
                if cp >= 0xD800 and cp <= 0xDBFF then
                    if text:sub(pos, pos + 1) ~= "\\u" then fail("missing low surrogate") end
                    pos = pos + 2
                    local low = unit()
                    if low < 0xDC00 or low > 0xDFFF then fail("invalid low surrogate") end
                    cp = 0x10000 + (cp - 0xD800) * 1024 + low - 0xDC00
                elseif cp >= 0xDC00 and cp <= 0xDFFF then
                    fail("unexpected low surrogate")
                end
                out[#out + 1] = str.Char(cp)
            else
                out[#out + 1] = unescape[ch] or fail("invalid string escape")
            end
        end
        local result = table.concat(out)
        if not str.IsValidUtf8(result) then fail("string is not UTF-8") end
        return result
    end
    local function readNumber()
        local start = pos
        local whole = text:match("^-?[0-9]+", pos)
        if not whole or whole:match("^-?0[0-9]") then fail("invalid JSON number") end
        pos = pos + #whole
        if text:sub(pos, pos) == "." then
            local fraction = text:match("^%.[0-9]+", pos) or fail("missing fraction")
            pos = pos + #fraction
        end
        if text:sub(pos, pos):match("[eE]") then
            local exponent = text:match("^[eE][+-]?[0-9]+", pos) or fail("missing exponent")
            pos = pos + #exponent
        end
        local result = tonumber(text:sub(start, pos - 1))
        if not result or math.abs(result) == math.huge then fail("number out of range") end
        return result
    end
    local function readValue(depth)
        whitespace()
        local ch = text:sub(pos, pos)
        if ch == '"' then return readString() end
        if ch == "t" and text:sub(pos, pos + 3) == "true" then pos = pos + 4; return true end
        if ch == "f" and text:sub(pos, pos + 4) == "false" then pos = pos + 5; return false end
        if ch == "n" and text:sub(pos, pos + 3) == "null" then pos = pos + 4; return null end
        if ch:match("[-0-9]") then return readNumber() end
        if ch ~= "[" and ch ~= "{" then fail("expected JSON value") end
        if depth >= limit then fail("maximum JSON depth exceeded") end
        local object = ch == "{"
        local close = object and "}" or "]"
        local out = object and {} or json.Array({})
        pos = pos + 1
        whitespace()
        if text:sub(pos, pos) == close then pos = pos + 1; return out end
        repeat
            if object then
                if text:sub(pos, pos) ~= '"' then fail("expected object key") end
                local key = readString()
                if out[key] ~= nil then fail("duplicate object key") end
                whitespace()
                if text:sub(pos, pos) ~= ":" then fail("expected colon") end
                pos = pos + 1
                out[key] = readValue(depth + 1)
            else
                out[#out + 1] = readValue(depth + 1)
            end
            whitespace()
            ch = text:sub(pos, pos)
            if ch ~= close and ch ~= "," then fail("expected comma or " .. close) end
            pos = pos + 1
            whitespace()
        until ch == close
        return out
    end
    local ok, result = pcall(readValue, 0)
    if not ok then return nil, result end
    whitespace()
    if pos <= #text then return nil, "trailing content at byte " .. pos end
    return result
end

return json
