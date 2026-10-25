local source = debug.getinfo(1, "S").source:sub(2)
local dir = source:match("^(.*)[/\\][^/\\]+$") or "."
dofile(dir .. "/../setup_paths.lua")

local process = require("process")
local env = require("env")
local uio = require("unicode_io")

local shell = assert(env.get("COMSPEC"))
-- The command is fixed; do not pass untrusted input to cmd.exe.
local command = assert(process.command(shell, {"/d", "/c", "echo LuaJIT process example"}))
local stdout, stderr, code, pid, timedOut = process.runCapture(command, {
    timeout = 5, -- seconds
    hidden = true,
})
assert(stdout ~= nil, stderr)
assert(not timedOut, "Child process timed out")
assert(code == 0, "Child process failed: " .. tostring(code))
-- Capture returns raw bytes. This fixed command produces ASCII text.
-- For other commands, decode using the code page used by that command.
assert(stdout:find("LuaJIT process example", 1, true))
uio.print("Output:", stdout)
print("Exit code:", code, "PID:", pid)
if stderr ~= "" then
    io.stderr:write(stderr)
end
