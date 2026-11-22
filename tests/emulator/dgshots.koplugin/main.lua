--[[
CI-only driver (not shipped). Opens every Daily Games game in the KOReader
emulator, performs a few actions and saves screenshots to $DG_SHOTS.
Krillion is only opened, never answered, so nothing is submitted.
]]
local Device = require("device")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local Screen = Device.screen
local OUT = os.getenv("DG_SHOTS") or "/tmp/dgshots"

local function log(line)
    local f = io.open(OUT .. "/log.txt", "a")
    if f then f:write(os.date("!%H:%M:%S "), line, "\n"); f:close() end
    logger.info("DGSHOTS", line)
end

local function top()
    local stack = UIManager._window_stack
    return stack[#stack] and stack[#stack].widget
end

local function describe(w)
    if not w then return "nil" end
    return tostring(w.name or "?") .. " | " .. tostring(w.title or (w.getTitle and w:getTitle()) or "")
        .. " | " .. tostring(w.text or ""):sub(1, 200):gsub("\n", " / ")
end

local function closeTop()
    local w = top()
    if not w then return end
    if w.onClose and w.covers_fullscreen then w:onClose() else UIManager:close(w) end
end

local function closeAllGames()
    for _ = 1, 6 do
        local w = top()
        if not w or w.name == "filemanager" or (w.name == nil and w.root_path) then break end
        closeTop()
    end
end

local function mod(name) return package.loaded["dailygames/" .. name] end
local function plugin()
    local FM = package.loaded["apps/filemanager/filemanager"]
    return FM and FM.instance and FM.instance.dailygames
end

local function findButton(w, text, seen)
    seen = seen or {}
    if type(w) ~= "table" or seen[w] then return end
    seen[w] = true
    if w.text == text and type(w.callback) == "function" then return w end
    if type(w.buttons) == "table" then
        for _, row in ipairs(w.buttons) do
            for _, b in ipairs(row) do
                if b.text == text and b.callback then return b end
            end
        end
    end
    for _, child in ipairs(w) do
        local found = findButton(child, text, seen)
        if found then return found end
    end
    for _, k in ipairs { "dialog", "movable", "button_table", "buttontable", "layout" } do
        local found = findButton(w[k], text, seen)
        if found then return found end
    end
end

local today = os.date("%Y-%m-%d")
local n = 0
local function shot(label)
    n = n + 1
    local name = string.format("%02d_%s", n, label)
    UIManager:forceRePaint()
    Screen:shot(OUT .. "/" .. name .. ".png")
    log("SHOT " .. name .. " top=" .. describe(top()))
end

local STEPS = {
    function() shot("home") end,
    function() plugin():open() end,
    function() shot("hub") end,
    function() closeTop() end,

    -- Wordle
    function() mod("wordle").launch(today) end,
    function() shot("wordle_start") end,
    function() local app = top(); for _, k in ipairs { "S", "L", "A", "T", "E", "ENTER", "C", "R" } do app:onKey(k) end end,
    function() shot("wordle_guess") end,
    function() closeAllGames() end,
    function() shot("after_wordle") end,

    -- Connections
    function() mod("connections").launch(today) end,
    function() shot("connections_start") end,
    function() local app = top(); for i = 1, 4 do app:toggle(app.state.remaining[i]) end end,
    function() shot("connections_selected") end,
    function() top():submit() end,
    function() shot("connections_after_submit") end,
    function() closeAllGames() end,

    -- Strands
    function() mod("strands").launch(today) end,
    function() shot("strands_start") end,
    function() local app = top(); app:tapCell(1, 1); app:tapCell(1, 2); app:tapCell(2, 2) end,
    function() shot("strands_path") end,
    function() top():giveHint() end,
    function() shot("strands_hint") end,
    function() closeAllGames() end,

    -- Mini crossword
    function() mod("crossword").launch("mini", "") end,
    function() shot("mini_start") end,
    function() local app = top(); for _, k in ipairs { "A", "B", "C" } do app:onAction(k) end end,
    function() shot("mini_typed") end,
    function() local app = top(); app:onAction("DOWN"); app:onAction("DOWN") end,
    function() shot("mini_down") end,
    function() top():onAction("CLUES") end,
    function() shot("mini_clues") end,
    function() closeTop() end,
    function() shot("mini_after_clues") end,
    function() closeAllGames() end,
    function() shot("after_mini") end,

    -- Daily crossword (no cookie: expect an explanation)
    function() mod("crossword").launch("daily", "") end,
    function() shot("daily_crossword") end,
    function() closeAllGames() end,

    -- Krillion (open only)
    function() mod("krillion").play() end,
    function() shot("krillion_intro") end,
    function() local w = top(); if w.ok_callback then UIManager:close(w); w.ok_callback() end end,
    function() shot("krillion_preview") end,
    function() end, function() end, function() end,
    function() shot("krillion_answer") end,
    function() closeAllGames() end,
    function() shot("end") end,
}

local Shots = WidgetContainer:extend { name = "dgshots", is_doc_only = false }

function Shots:init()
    if Shots.started then return end
    Shots.started = true
    os.execute("mkdir -p '" .. OUT .. "'")
    log("screen " .. Screen:getWidth() .. "x" .. Screen:getHeight() .. " dpi " .. tostring(Screen:getDPI()))
    local i = 0
    local function step()
        i = i + 1
        local fn = STEPS[i]
        if not fn then
            log("DONE")
            UIManager:quit()
            return
        end
        local ok, err = xpcall(fn, debug.traceback)
        if not ok then log("ERROR step " .. i .. ": " .. tostring(err)) end
        UIManager:scheduleIn(2, step)
    end
    UIManager:scheduleIn(5, step)
end

return Shots
