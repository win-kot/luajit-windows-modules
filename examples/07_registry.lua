local source = debug.getinfo(1, "S").source:sub(2)
local dir = source:match("^(.*)[/\\][^/\\]+$") or "."
dofile(dir .. "/../setup_paths.lua")

local registry = require("registry")
local uio = require("unicode_io")

-- Read an existing value without changing the registry.
local value, valueType, code = registry.read(
    "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion",
    "ProductName"
)
if value == nil then
    if valueType ~= nil then error(tostring(valueType) .. " (" .. tostring(code) .. ")") end
    print("The registry value is not present on this system")
else
    uio.print("ProductName:", value)
    print("Registry type:", valueType)
end
-- ProductName is the stored registry text, not a reliable OS version detector.
