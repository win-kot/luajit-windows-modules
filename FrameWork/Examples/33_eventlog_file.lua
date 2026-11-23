local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local log = require("eventlog")
local path = assert(arg[1], "Usage: luajit 33_eventlog_file.lua DESTINATION.evtx [CHANNEL]")
local channel = arg[2] or "System"
local newest, err = log.Read(channel, {limit = 1})
assert(newest, err)
local event = assert(newest[1], "The channel contains no records")
local filter = ("*[System[EventRecordID=%s]]"):format(event.recordId)
local exported, warning = log.Export(channel, path, {query = filter})
assert(exported, warning)
if warning then io.stderr:write(warning, "\n") end
local file = assert(log.FileInfoGet(path))
print("Records in the file", file.recordCount)
for _, record in ipairs(assert(log.FileRead(path))) do
    print(record.timeUtc, record.eventId, record.provider)
end
