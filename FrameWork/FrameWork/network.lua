local ffi = require("ffi")
local bit = require("bit")
local win = require("_win_extension")
local M = {}

ffi.cdef[[
typedef union {
    uint16_t family;
    struct { uint16_t family, port; uint8_t address[4], padding[8]; } ipv4;
    struct { uint16_t family, port; uint32_t flow; uint8_t address[16]; uint32_t scope; } ipv6;
} fw_net_sockaddr;
typedef struct { const fw_net_sockaddr *pointer; int32_t length; } fw_net_socket_address;
typedef struct fw_net_address {
    uint32_t length, flags;
    struct fw_net_address *next;
    fw_net_socket_address address;
} fw_net_address;
typedef struct fw_net_unicast {
    uint32_t length, flags;
    struct fw_net_unicast *next;
    fw_net_socket_address address;
    uint32_t prefixOrigin, suffixOrigin, dadState, validLifetime, preferredLifetime, leaseLifetime;
    uint8_t prefixLength;
} fw_net_unicast;
typedef struct fw_net_adapter {
    uint32_t length, ipv4Index;
    struct fw_net_adapter *next;
    const char *id;
    fw_net_unicast *unicast;
    void *anycast, *multicast;
    fw_net_address *dns;
    const uint16_t *dnsSuffix, *description, *name;
    uint8_t physicalAddress[8];
    uint32_t physicalAddressLength, flags, mtu, type, operStatus, ipv6Index;
    uint32_t zoneIndices[16];
    void *firstPrefix;
    uint64_t transmitBps, receiveBps;
    void *wins;
    fw_net_address *gateways;
    uint32_t ipv4Metric, ipv6Metric;
} fw_net_adapter;
typedef struct {
    uint64_t luid;
    uint32_t index;
    uint8_t interfaceGuid[16];
    uint16_t name[257], description[257];
    uint32_t macLength;
    uint8_t mac[32], permanentMac[32];
    uint32_t mtu, type, tunnelType, mediaType, physicalMediumType, accessType, directionType;
    uint8_t statusFlags;
    uint32_t operStatus, adminStatus, mediaConnectState;
    uint8_t networkGuid[16];
    uint32_t connectionType;
    uint64_t transmitBps, receiveBps;
    uint64_t receivedBytes, receivedUnicastPackets, receivedNonUnicastPackets, receivedDiscards,
        receivedErrors, receivedUnknownProtocols, receivedUnicastBytes, receivedMulticastBytes,
        receivedBroadcastBytes, sentBytes, sentUnicastPackets, sentNonUnicastPackets,
        sentDiscards, sentErrors, sentUnicastBytes, sentMulticastBytes, sentBroadcastBytes, outputQueueLength;
} fw_net_interface;
typedef struct { fw_net_sockaddr address; uint8_t length; } fw_net_prefix;
typedef struct {
    uint64_t luid;
    uint32_t index;
    fw_net_prefix destination;
    fw_net_sockaddr nextHop;
    uint8_t sitePrefixLength;
    uint32_t validLifetime, preferredLifetime, metric, protocol;
    uint8_t loopback, autoconfigureAddress, publish, immortal;
    uint32_t age, origin;
} fw_net_route;
typedef struct { int32_t autoDetect; uint16_t *pacUrl, *proxy, *bypass; } fw_net_proxy;

uint32_t __stdcall GetAdaptersAddresses(uint32_t, uint32_t, void *, fw_net_adapter *, uint32_t *);
uint32_t __stdcall GetIfEntry2(fw_net_interface *);
uint32_t __stdcall GetBestInterfaceEx(const fw_net_sockaddr *, uint32_t *);
uint32_t __stdcall GetBestRoute2(const uint64_t *, uint32_t, const fw_net_sockaddr *,
    const fw_net_sockaddr *, uint32_t, fw_net_route *, fw_net_sockaddr *);
const uint16_t *__stdcall InetNtopW(int, const void *, uint16_t *, size_t);
int __stdcall InetPtonW(int, const uint16_t *, void *);
int __stdcall WSAGetLastError(void);
int __stdcall WinHttpGetIEProxyConfigForCurrentUser(fw_net_proxy *);
void *__stdcall GlobalFree(void *);
]]

local AF_INET, AF_INET6 = 2, 23
local statusNames = {"up", "down", "testing", "unknown", "dormant", "notPresent", "lowerLayerDown"}

local function addressInfo(ws, sockaddr)
    local family = sockaddr.family
    local ipv6 = family == AF_INET6
    local buffer = ffi.new("uint16_t[46]")
    local bytes = ipv6 and sockaddr.ipv6.address or sockaddr.ipv4.address
    if ws.InetNtopW(family, bytes, buffer, 46) == nil then
        return win.Error("InetNtopW", ws.WSAGetLastError())
    end
    local text, err, code = win.FromWide(buffer)
    if not text then return nil, err, code end
    return {address = text, family = ipv6 and 6 or 4, scopeId = ipv6 and sockaddr.ipv6.scope or nil}
end

local function addressList(ws, first, unicast)
    local result = {}
    local item = first
    while item ~= nil do
        local socket = item.address
        if socket.pointer ~= nil and socket.length >= 2 then
            local family = socket.pointer.family
            if (family == AF_INET and socket.length >= 16) or (family == AF_INET6 and socket.length >= 28) then
                local info, err, code = addressInfo(ws, socket.pointer)
                if not info then return nil, err, code end
                if unicast and item.length > ffi.offsetof("fw_net_unicast", "prefixLength") then
                    local prefix = tonumber(item.prefixLength)
                    if prefix <= (family == AF_INET and 32 or 128) then info.prefixLength = prefix end
                end
                result[#result + 1] = info
            end
        end
        item = item.next
    end
    return result
end

local function wideField(ptr)
    if ptr == nil then return "" end
    return win.FromWide(ptr)
end

local function adapterInfo(ws, row)
    local name, err, code = wideField(row.name)
    if not name then return nil, err, code end
    local description
    description, err, code = wideField(row.description)
    if not description then return nil, err, code end
    local suffix
    suffix, err, code = wideField(row.dnsSuffix)
    if not suffix then return nil, err, code end
    local addresses
    addresses, err, code = addressList(ws, row.unicast, true)
    if not addresses then return nil, err, code end
    local dns
    dns, err, code = addressList(ws, row.dns)
    if not dns then return nil, err, code end
    local gateways
    gateways, err, code = addressList(ws, row.gateways)
    if not gateways then return nil, err, code end
    local mac = {}
    for i = 0, math.min(row.physicalAddressLength, 8) - 1 do
        mac[#mac + 1] = ("%02X"):format(row.physicalAddress[i])
    end
    return {
        id = row.id ~= nil and ffi.string(row.id) or "", name = name, description = description,
        ipv4Index = row.ipv4Index, ipv6Index = row.ipv6Index,
        ipv4Metric = row.ipv4Metric, ipv6Metric = row.ipv6Metric,
        status = statusNames[row.operStatus] or "unknown", statusCode = row.operStatus,
        type = row.type, mtu = row.mtu, mac = #mac > 0 and table.concat(mac, ":") or nil,
        dhcpV4 = bit.band(row.flags, 4) ~= 0, transmitBps = win.Exact(row.transmitBps),
        receiveBps = win.Exact(row.receiveBps), dnsSuffix = suffix,
        addresses = addresses, dnsServers = dns, gateways = gateways
    }
end

function M.AdaptersGet()
    local ip, err, code = win.Library("iphlpapi")
    if not ip then return nil, err, code end
    local ws
    ws, err, code = win.Library("ws2_32")
    if not ws then return nil, err, code end
    local size = ffi.new("uint32_t[1]", 15 * 1024)
    for _ = 1, 4 do
        local capacity = size[0]
        local buffer = ffi.new("uint8_t[?]", capacity)
        local first = ffi.cast("fw_net_adapter *", buffer)
        local status = ip.GetAdaptersAddresses(0, 0x186, nil, first, size)
        if status == 232 then return {} end -- ERROR_NO_DATA
        if status == 0 then
            local result = {}
            local row = first
            while row ~= nil do
                if row.length < ffi.sizeof("fw_net_adapter") then
                    return win.Error("Unexpected IP_ADAPTER_ADDRESSES layout", 13)
                end
                local item
                item, err, code = adapterInfo(ws, row)
                if not item then return nil, err, code end
                result[#result + 1] = item
                row = row.next
            end
            return result
        end
        if status ~= 111 or size[0] <= capacity or size[0] > 64 * 1024 * 1024 then
            return win.Error("GetAdaptersAddresses", status)
        end
    end
    return win.Error("GetAdaptersAddresses changed during enumeration", 111)
end
-- Keep the variable-sized FFI buffer reachable while following its internal pointers.
jit.off(M.AdaptersGet, true)

local stats = {"transmitBps", "receiveBps", "receivedBytes", "sentBytes", "receivedUnicastPackets",
    "sentUnicastPackets", "receivedNonUnicastPackets", "sentNonUnicastPackets",
    "receivedErrors", "sentErrors", "receivedDiscards", "sentDiscards"}

function M.InterfaceStatsGet(index)
    if not win.Integer(index, 1, 0xFFFFFFFF) then return win.Error("Invalid interface index", 87) end
    local ip, err, code = win.Library("iphlpapi")
    if not ip then return nil, err, code end
    local row = ffi.new("fw_net_interface[1]")
    row[0].index = index
    local status = ip.GetIfEntry2(row)
    if status ~= 0 then return win.Error("GetIfEntry2", status) end
    local name
    name, err, code = win.FromWide(row[0].name)
    if not name then return nil, err, code end
    local data = {index = row[0].index, name = name, mtu = row[0].mtu, type = row[0].type,
        status = statusNames[row[0].operStatus] or "unknown", statusCode = row[0].operStatus}
    for _, field in ipairs(stats) do data[field] = win.Exact(row[0][field]) end
    return data
end

local function parseAddress(ws, text)
    if type(text) ~= "string" or #text > 60 then return win.Error("Expected an IP address literal", 87) end
    local raw, scope = text:match("^([^%%]+)%%(%d+)$")
    scope = scope and tonumber(scope) or 0
    if not win.Integer(scope, 0, 0xFFFFFFFF) or (raw and not raw:find(":", 1, true)) then
        return win.Error("Invalid IPv6 zone index", 87)
    end
    raw = raw or text
    local wide, err, code = win.ToWide(raw)
    if not wide then return nil, err, code end
    local target = ffi.new("fw_net_sockaddr[1]")
    local ipv6 = raw:find(":", 1, true) ~= nil
    local family = ipv6 and AF_INET6 or AF_INET
    local output = ipv6 and target[0].ipv6.address or target[0].ipv4.address
    local status = ws.InetPtonW(family, wide, output)
    if status ~= 1 then
        if status < 0 then return win.Error("InetPtonW", ws.WSAGetLastError()) end
        return win.Error("Invalid IPv4 or IPv6 literal", 87)
    end
    target[0].family = family
    if ipv6 then target[0].ipv6.scope = scope end
    return target
end

function M.BestRouteGet(address)
    local ws, err, code = win.Library("ws2_32")
    if not ws then return nil, err, code end
    local target
    target, err, code = parseAddress(ws, address)
    if not target then return nil, err, code end
    local ip
    ip, err, code = win.Library("iphlpapi")
    if not ip then return nil, err, code end
    local index = ffi.new("uint32_t[1]", target[0].family == AF_INET6 and target[0].ipv6.scope or 0)
    if index[0] == 0 then
        local status = ip.GetBestInterfaceEx(target, index)
        if status ~= 0 then return win.Error("GetBestInterfaceEx", status) end
    end
    local route, source = ffi.new("fw_net_route[1]"), ffi.new("fw_net_sockaddr[1]")
    local status = ip.GetBestRoute2(nil, index[0], nil, target, 0, route, source)
    if status ~= 0 then return win.Error("GetBestRoute2", status) end
    local row = route[0]
    local prefix
    prefix, err, code = addressInfo(ws, row.destination.address)
    if not prefix then return nil, err, code end
    prefix.prefixLength = row.destination.length
    local hop, localAddress
    if row.nextHop.family ~= 0 then
        hop, err, code = addressInfo(ws, row.nextHop)
        if not hop then return nil, err, code end
    end
    if source[0].family ~= 0 then
        localAddress, err, code = addressInfo(ws, source[0])
        if not localAddress then return nil, err, code end
    end
    return {index = row.index, destinationPrefix = prefix, source = localAddress, nextHop = hop,
        onLink = not hop or hop.address == "0.0.0.0" or hop.address == "::",
        metric = row.metric, protocol = row.protocol}
end

function M.ProxyGet()
    local dll, err, code = win.Library("winhttp")
    if not dll then return nil, err, code end
    local config = ffi.new("fw_net_proxy[1]")
    local ok = dll.WinHttpGetIEProxyConfigForCurrentUser(config)
    if ok == 0 then code = win.kernel.GetLastError() end
    local result = {autoDetect = config[0].autoDetect ~= 0}
    for _, field in ipairs({"pacUrl", "proxy", "bypass"}) do
        local pointer = config[0][field]
        if pointer ~= nil then
            if ok ~= 0 and not err then
                local message, status
                result[field], message, status = win.FromWide(pointer)
                if message then err, code = message, status end
            end
            win.kernel.GlobalFree(pointer)
        end
    end
    if ok == 0 then return win.Error("WinHttpGetIEProxyConfigForCurrentUser", code) end
    if err then return nil, err, code end
    return result
end

return M
