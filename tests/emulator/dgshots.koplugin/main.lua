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

local function typeWord(app, word)
    for ch in word:gmatch(".") do app:onKey(ch) end
    app:onKey("ENTER")
end

local STEPS = {
    function() shot("home") end,
    function() plugin():open() end,
    function() shot("hub") end,
    function() closeTop() end,

    -- Wordle: one miss, then a partial, then the answer
    function() mod("wordle").launch(today) end,
    function() shot("wordle_start") end,
    function() local app = top(); typeWord(app, "SLATE"); typeWord(app, "CRONY"); for _, k in ipairs { "B", "R" } do app:onKey(k) end end,
    function() shot("wordle_guesses") end,
    function() local app = top(); app:onKey("DEL"); app:onKey("DEL"); typeWord(app, app.solution) end,
    function() shot("wordle_solved") end,
    function() top():showMenu() end,
    function() shot("wordle_menu") end,
    function() closeTop() end,
    function() closeAllGames() end,
    function() shot("after_wordle") end,

    -- Connections: select a real group, submit, then a wrong guess
    function() mod("connections").launch(today) end,
    function() shot("connections_start") end,
    function() local app = top(); for _, w in ipairs(app.categories[1].words) do app:toggle(w) end end,
    function() shot("connections_selected") end,
    function() top():submit() end,
    function() shot("connections_solved_one") end,
    function()
        local app = top()
        local a, b = app.categories[2].words, app.categories[3].words
        for _, w in ipairs { a[1], a[2], a[3], b[1] } do app:toggle(w) end
        app:submit()
    end,
    function() shot("connections_one_away") end,
    function() closeAllGames() end,

    -- Strands: find the first theme word, then start a path, then a hint
    function() mod("strands").launch(today) end,
    function() shot("strands_start") end,
    function()
        local app = top()
        local w = app.theme_words[1]
        for _, rc in ipairs(app.coords[w] or {}) do app:tapCell(rc[1] + 1, rc[2] + 1) end
        local last = (app.coords[w] or {})[#(app.coords[w] or {})]
        if last then app:tapCell(last[1] + 1, last[2] + 1) end
    end,
    function() shot("strands_found") end,
    function() local app = top(); app:tapCell(8, 1); app:tapCell(7, 1); app:tapCell(7, 2) end,
    function() shot("strands_path") end,
    function() top():giveHint() end,
    function() shot("strands_hint") end,
    function() closeAllGames() end,

    -- Mini crossword
    function() mod("crossword").launch("mini", "") end,
    function() shot("mini_start") end,
    function() local app = top(); for _, k in ipairs { "A", "B", "C" } do app:onKey(k) end end,
    function() shot("mini_typed") end,
    function() local app = top(); app:toggleDirection(); app:refresh() end,
    function() shot("mini_down") end,
    function() local app = top(); app:check(); app:refresh() end,
    function() shot("mini_check") end,
    function() top():showClueList() end,
    function() shot("mini_clues") end,
    function() closeTop() end,
    function() closeAllGames() end,
    function() shot("after_mini") end,

    -- Daily crossword
    function() mod("crossword").launch("daily", "") end,
    function() shot("daily_crossword") end,
    function() closeAllGames() end,

    -- The Atlantic crossword
    function() mod("crossword").launch("atlantic") end,
    function() shot("atlantic_start") end,
    function() local app = top(); for _, k in ipairs { "P", "I" } do app:onKey(k) end end,
    function() shot("atlantic_typed") end,
    function() closeAllGames() end,

    -- FoodGuessr: type, then guess a wrong country
    function() mod("foodguessr").launch() end,
    function() shot("foodguessr_start") end,
    function() local app = top(); for _, k in ipairs { "J", "A", "P" } do app:onKey(k) end end,
    function() shot("foodguessr_typed") end,
    function() top():guess("JP") end,
    function() shot("foodguessr_guess") end,
    function() closeAllGames() end,

    -- More/Less (start screen only, so CI doesn't send guesses)
    function() mod("moreless").launch() end,
    function() shot("moreless_start") end,
    function() closeAllGames() end,

    -- Marveldle: two guesses so the attribute table shows
    function() mod("marveldle").launch() end,
    function() local app = top(); for _, c in ipairs(app.characters) do
        if c.name == "Thor" or c.name == "Loki" then app:guess(c) end end
        for _, k in ipairs { "W", "A" } do app:onKey(k) end end,
    function() shot("marveldle_typed") end,
    function() closeAllGames() end,

    -- WhereTaken: a wrong guess, then the right one, then the landmark bonus
    function() mod("wheretaken").launch(today) end,
    function() shot("wheretaken_start") end,
    function() local app = top(); app:guess(app.answer == "FR" and "DE" or "FR"); for _, k in ipairs { "S", "P" } do app:onKey(k) end end,
    function() shot("wheretaken_guess") end,
    function() local app = top(); app:guess(app.answer); app:nextPhase() end,
    function() shot("wheretaken_bonus") end,
    function() closeAllGames() end,

    -- FoodGuessr Cuisine Match and Plate-Off (answers are checked locally)
    function() mod("foodmodes").launchCuisineMatch() end,
    function() shot("cuisinematch_start") end,
    function() local app = top(); local r = app.rounds[1]; app:pick(((r.correctFoodIndex + 1) % 3) + 1) end,
    function() shot("cuisinematch_second") end,
    function() closeAllGames() end,
    function() mod("foodmodes").launchPlateOff() end,
    function() shot("plateoff_start") end,
    function() top():pick("left") end,
    function() shot("plateoff_result") end,
    function() closeAllGames() end,

    -- Costcodle: one high guess, then a close one
    function() mod("costcodle").launch(today) end,
    function() shot("costcodle_start") end,
    function() local app = top(); for _, k in ipairs { "9", "9", "ENTER" } do app:onKey(k) end
        local p = string.format("%.2f", app.price * 0.85)
        for ch in p:gmatch(".") do app:onKey(ch) end; app:onKey("ENTER")
        for ch in ("12"):gmatch(".") do app:onKey(ch) end end,
    function() shot("costcodle_guesses") end,
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
