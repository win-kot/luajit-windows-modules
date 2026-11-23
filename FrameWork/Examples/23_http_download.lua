local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local http = require("http")
assert(arg[1] and arg[2], "Usage: luajit 23_http_download.lua URL DESTINATION")
local lastPercent = -1
local response = assert(http.Download(arg[1], arg[2], {
    overwrite = false,
    onProgress = function(bytes, total)
        if total and total > 0 then
            local percent = math.floor(bytes / total * 100)
            if percent ~= lastPercent then
                io.write(("\rDownloading %d%%"):format(percent))
                lastPercent = percent
            end
        end
    end
}))
if lastPercent >= 0 then io.write("\n") end
if not response.path then
    io.stderr:write(("File was not saved (HTTP %d).\n"):format(response.status))
    os.exit(1)
end
print("HTTP", response.status, response.path, response.bytes)
