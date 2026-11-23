local url = {}

function url.Encode(text)
    if type(text) ~= "string" then return nil, "Требуется строка" end
    return (text:gsub("[^A-Za-z0-9._~%-]", function(byte)
        return string.format("%%%02X", byte:byte())
    end))
end

local function validateEscapes(text)
    local pos = 1
    while true do
        pos = text:find("%", pos, true)
        if not pos then break end
        if not text:find("^[0-9A-Fa-f][0-9A-Fa-f]", pos + 1) then
            return nil, "invalid percent escape at byte " .. pos
        end
        pos = pos + 3
    end
    return true
end

function url.Decode(text)
    if type(text) ~= "string" then return nil, "Требуется строка" end
    local ok, err = validateEscapes(text)
    if not ok then return nil, err end
    return (text:gsub("%%([0-9A-Fa-f][0-9A-Fa-f])", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local unescaped = "A-Za-z0-9._~!$&'()*+,;=%-"
local atom = unescaped .. "%%"

local function ipv4(value)
    local a, b, c, d = value:match("^([0-9]+)%.([0-9]+)%.([0-9]+)%.([0-9]+)$")
    if not a then return false end
    for _, octet in ipairs({a, b, c, d}) do
        if #octet > 3 or (#octet > 1 and octet:sub(1, 1) == "0") or tonumber(octet) > 255 then
            return false
        end
    end
    return true
end

local function ipv6Groups(part, ipv4Allowed)
    if part == "" then return 0 end
    local count, pos = 0, 1
    while true do
        local colon = part:find(":", pos, true)
        local group = part:sub(pos, colon and colon - 1 or -1)
        if #group <= 4 and group:match("^[0-9A-Fa-f]+$") then
            count = count + 1
        elseif not colon and ipv4Allowed and ipv4(group) then
            count = count + 2
        else
            return nil
        end
        if not colon then return count end
        pos = colon + 1
    end
end

local function ipLiteral(host)
    if host:match("^[vV][0-9A-Fa-f]+%.[" .. unescaped .. ":]+$") then return true end
    local compression = host:find("::", 1, true)
    if not compression then return ipv6Groups(host, true) == 8 end
    local left = ipv6Groups(host:sub(1, compression - 1), false)
    local right = ipv6Groups(host:sub(compression + 2), true)
    return left and right and left + right < 8
end

local function parseAuthority(authority, result)
    local credentials, hostPort = authority:match("^([^@]*)@(.*)$")
    if credentials then
        if credentials:find("[^" .. atom .. ":]") then return nil, "invalid URI userinfo" end
        result.userinfo = credentials
    else
        hostPort = authority
    end
    local host, suffix
    if hostPort:sub(1, 1) == "[" then
        host, suffix = hostPort:match("^%[([^%]]+)%](.*)$")
        if not host or not ipLiteral(host) then return nil, "invalid URI IP literal" end
        result.ipLiteral = true
    else
        host, suffix = hostPort:match("^([^:]*)(.*)$")
        if host:find("[^" .. atom .. "]") then return nil, "invalid URI host" end
    end
    result.host = host
    if suffix ~= "" then
        local digits = suffix:match("^:([0-9]+)$")
        if not digits then return nil, "invalid URI port" end
        local port = tonumber(digits)
        if not port or port > 65535 then return nil, "URI port outside 0..65535" end
        result.port = port
    end
    return true
end

function url.Parse(value)
    if type(value) ~= "string" then return nil, "Требуется строка URI" end
    local ok, err = validateEscapes(value)
    if not ok then return nil, err end
    local result = {}
    local rest, fragment = value:match("^([^#]*)#(.*)$")
    rest = rest or value
    local pathPart, query = rest:match("^([^?]*)%?(.*)$")
    rest = pathPart or rest
    local scheme, tail = rest:match("^([A-Za-z][A-Za-z0-9+%.%-]*):(.*)$")
    if scheme then
        result.scheme, rest = scheme:lower(), tail
    elseif rest:match("^[^/]*:") then
        return nil, "invalid URI scheme or relative path"
    end
    if rest:sub(1, 2) == "//" then
        local authority
        authority, rest = rest:match("^//([^/]*)(.*)$")
        result.authority = authority
        ok, err = parseAuthority(authority, result)
        if not ok then return nil, err end
    end
    if rest:find("[^" .. atom .. ":@/]") or
        (query and query:find("[^" .. atom .. ":@/?]")) or
        (fragment and fragment:find("[^" .. atom .. ":@/?]")) then
        return nil, "invalid URI component character"
    end
    result.path, result.query, result.fragment = rest, query, fragment
    return result
end

return url
