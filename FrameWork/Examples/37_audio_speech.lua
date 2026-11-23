local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
assert(loadfile(dir .. "/_bootstrap.lua"))(false)
local audio, speech = require("audio"), require("speech")

for _, device in ipairs(assert(audio.ListDevices())) do
    print(device.name, device.id, device.state)
end
for _, voice in ipairs(assert(speech.ListVoices())) do
    print(voice.name, voice.id)
end

if arg[1] == "speak" then
    assert(speech.Speak(assert(arg[2], "Pass the text as the second argument")))
elseif arg[1] == "play" then
    local player = assert(audio.Play(assert(arg[2], "Pass the audio path as the second argument"), {wait = true}))
    assert(player:Close())
end
