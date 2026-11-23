local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local eventlog = require("eventlog")
local channel = arg[1] or "System"
local limit = arg[2] and assert(tonumber(arg[2]), "COUNT must be a number") or 5
local records, timedOut = eventlog.Read(channel, {limit = limit, query = arg[3]})
assert(records, timedOut)
for _, record in ipairs(records) do
    print(record.timeUtc, record.eventId, record.level, record.provider)
end
if timedOut then print("Timed out waiting for the next batch of records") end
