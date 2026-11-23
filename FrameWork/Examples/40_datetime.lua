local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local datetime = require("datetime")

local now = assert(datetime.Now())
print("Now", assert(datetime.Format(now)), "UTC offset (minutes)", now.offsetMinutes)

local start = assert(datetime.Parse("2024-01-31T09:30:00Z"))
local finish = assert(datetime.Add(start, "month", 1))
print("One month from now", assert(datetime.Format(finish, "%Y-%m-%dT%H:%M:%SZ")))
print("Days elapsed", assert(datetime.Diff(finish, start, "days")))
