local source = debug.getinfo(1, "S").source
local dir = source:sub(2):match("^(.*)[/\\]") or "."
dofile(dir .. "/../../FrameWork/setup_paths.lua")
local gui = require("gui")
assert(gui.WindowClient("Message Box Buttons and Icons", 620, 470, "fixed", "center"))
assert(gui.DefaultFontSet("Segoe UI", 11))
assert(gui.Label("info", "Move the window and choose an example to open a centered message box.", 20, 15, 580, 45))
local cases = {
    {"OK (information)", "ok", "information", 1},
    {"OK / Cancel (warning)", "ok-cancel", "warning", 2},
    {"Yes / No (question)", "yes-no", "question", 2},
    {"Yes / No / Cancel (no icon)", "yes-no-cancel", "none", 3},
    {"Retry / Cancel (error)", "retry-cancel", "error", 2},
    {"Abort / Retry / Ignore", "abort-retry-ignore", "warning", 2},
    {"Cancel / Try Again / Continue", "cancel-try-continue", "information", 1}
}
local names = {
    [gui.Answer.Ok] = "OK",
    [gui.Answer.Cancel] = "Cancel",
    [gui.Answer.Abort] = "Abort",
    [gui.Answer.Retry] = "Retry",
    [gui.Answer.Ignore] = "Ignore",
    [gui.Answer.Yes] = "Yes",
    [gui.Answer.No] = "No",
    [gui.Answer.TryAgain] = "Try again",
    [gui.Answer.Continue] = "Continue",
}
for index, row in ipairs(cases) do
    local spec = row
    local id = "message" .. index
    assert(gui.Button(id, spec[1], 20, 60 + (index - 1) * 44, 580, 36))
    assert(gui.OnClick(id, function()
        local answer, err = gui.MessageBox("Example: " .. spec[1], "Standard message box", spec[2], spec[3], spec[4])
        if answer == nil then
            assert(gui.TextSet("result", err))
        else
            assert(gui.TextSet("result", "Clicked: " .. names[answer] .. "; ID=" .. answer))
            -- Compare the result with gui.Answer.Yes to check for confirmation.
            if answer == gui.Answer.Yes then print("Confirmed") end
        end
    end))
end
assert(gui.Label("result", "The result appears here", 20, 385, 580, 30))
assert(gui.Button("close", "Close", 440, 425, 160, 32))
assert(gui.OnClick("close", function() assert(gui.Close()) end))
gui.Run()
