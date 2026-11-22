--[[
FoodGuessr (foodguessr.com): three dishes a day; guess the country each
comes from. Five guesses per dish. Each wrong guess shows how far away it is
and which way to go; closer guesses earn more points.

Data: GET https://www.foodguessr.com/api/trpc/daily.today (tRPC batch), the
same endpoint the site uses. It includes precomputed distances and bearings
between the answers and every region (v2Distances.pairs, keyed by the two
codes in sorted order: "A-B" -> { km, bearing A->B, bearing B->A }).
Scoring follows the site's V2 rules: 5,000 points per dish.
]]

local ButtonTable = require("ui/widget/buttontable")
local DataStorage = require("datastorage")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local Http = require("dailygames/http")
local Store = require("dailygames/store")
local UI = require("dailygames/ui")
local REGIONS = require("dailygames/data_foodguessr_regions")

local MAX_GUESSES = 5
local TODAY_URL = "https://www.foodguessr.com/api/trpc/daily.today?batch=1&input=%7B%220%22%3A%7B%22json%22%3Anull%7D%7D"
local IMAGE_URL = "https://r2.foodguessr.com/f/ir/%s/800w.webp"

local NAME = {}
for _, r in ipairs(REGIONS) do NAME[r[1]] = r[2] end

local FoodGuessr = {}

-- helpers --------------------------------------------------------------------

--- Lowercase ASCII-ish search key ("Åland" -> "aland", "Côte" -> "cote").
local function fold(s)
    s = s:lower()
    local map = { ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["å"] = "a", ["ã"] = "a",
        ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["í"] = "i", ["î"] = "i", ["ï"] = "i",
        ["ó"] = "o", ["ô"] = "o", ["ö"] = "o", ["õ"] = "o", ["ú"] = "u", ["ü"] = "u", ["ç"] = "c",
        ["ñ"] = "n", ["Å"] = "a", ["É"] = "e" }
    for k, v in pairs(map) do s = s:gsub(k, v) end
    return s
end

--- Regions whose name (or any word in it) starts with the typed text.
function FoodGuessr.suggest(typed, exclude, limit)
    typed = fold(typed)
    if typed == "" then return {} end
    local starts, words = {}, {}
    for _, r in ipairs(REGIONS) do
        local code, key = r[1], fold(r[2])
        if not (exclude and exclude[code]) then
            if key:sub(1, #typed) == typed then
                table.insert(starts, code)
            elseif key:find(" " .. typed, 1, true) or key:find("-" .. typed, 1, true) then
                table.insert(words, code)
            end
        end
    end
    for _, c in ipairs(words) do table.insert(starts, c) end
    local out = {}
    for i = 1, math.min(limit or 4, #starts) do out[i] = starts[i] end
    return out
end

local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local function compass(bearing)
    return COMPASS[math.floor(((bearing % 360) + 22.5) / 45) % 8 + 1]
end

--- Distance (km) and bearing from region a toward region b, from the site's table.
function FoodGuessr.distance(pairs, a, b)
    if a == b then return 0, 0 end
    local key = a < b and (a .. "-" .. b) or (b .. "-" .. a)
    local p = pairs and pairs[key]
    if not p then return nil end
    return p[1], a < b and p[2] or p[3]
end

local function nearMiss(km)
    return math.ceil(math.max(3000 - 0.001 * km * km, 0))
end

--- Evaluates a guess against a round: { correct, km, bearing, score }.
function FoodGuessr.judge(round, pairs, code)
    local best
    for _, c in ipairs(round.answers) do
        if c == code then return { correct = true, km = 0, score = 5000 } end
        local km, bearing = FoodGuessr.distance(pairs, code, c)
        if km and (not best or km < best.km) then best = { km = km, bearing = bearing } end
    end
    if not best then return { correct = false } end
    return { correct = false, km = best.km, bearing = best.bearing, score = nearMiss(best.km) }
end

--- V2 score for a finished round.
function FoodGuessr.roundScore(round, pairs, guesses)
    local total, correct = 0, false
    for _, g in ipairs(guesses) do
        local j = FoodGuessr.judge(round, pairs, g)
        if j.correct then
            correct = true
        elseif j.score then
            total = total + math.floor(1000 * math.min(j.score, 5000) / 5000 + 0.5)
        end
    end
    if correct then total = total + 1000 + 1000 * (MAX_GUESSES - #guesses) end
    return total
end

local function commas(n)
    local s = tostring(math.floor(n))
    while true do
        local r, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        s = r
        if k == 0 then return s end
    end
end

-- app ------------------------------------------------------------------------

local App = UI.FullscreenApp:extend {
    name = "foodguessr_app",
    help_text = [[Three dishes a day. Guess which country each one comes from.

Type a few letters, then tap a country to guess. You have 5 guesses per dish.

Wrong guesses show the distance and the direction to go. Closer guesses earn points; the right country on the first try earns the full 5,000.

Stuck? The hint buttons show the dish's name, ingredients and a description.]],
}

function App:setup()
    self.state = self.state or { round = 1, rounds = {} }
    for i = 1, #self.rounds do
        self.state.rounds[i] = self.state.rounds[i] or { guesses = {}, hints = {} }
    end
    self.input = ""
end

function App:isComplete()
    for i = 1, #self.rounds do
        if not self:roundOver(i) then return false end
    end
    return true
end

function App:progressKey() return "foodguessr" end

function App:getTitle()
    return string.format("FoodGuessr · Dish %d of %d", self.state.round, #self.rounds)
end

function App:current()
    return self.rounds[self.state.round], self.state.rounds[self.state.round]
end

function App:roundOver(i)
    local round, st = self.rounds[i], self.state.rounds[i]
    if #st.guesses >= MAX_GUESSES then return true end
    for _, g in ipairs(st.guesses) do
        if FoodGuessr.judge(round, self.pairs, g).correct then return true end
    end
    return false
end

function App:totalScore()
    local total = 0
    for i, st in ipairs(self.state.rounds) do
        if self:roundOver(i) then total = total + FoodGuessr.roundScore(self.rounds[i], self.pairs, st.guesses) end
    end
    return total
end

function App:answerNames(round)
    local names = {}
    for _, c in ipairs(round.answer_names) do table.insert(names, c) end
    return table.concat(names, " or ")
end

function App:guessLines()
    local round, st = self:current()
    local lines = {}
    for _, g in ipairs(st.guesses) do
        local j = FoodGuessr.judge(round, self.pairs, g)
        if j.correct then
            table.insert(lines, "✓ " .. (NAME[g] or g) .. " — correct!")
        elseif j.km then
            table.insert(lines, string.format("✗ %s — %s km %s · %s pts", NAME[g] or g, commas(j.km),
                compass(j.bearing), commas(j.score)))
        else
            table.insert(lines, "✗ " .. (NAME[g] or g))
        end
    end
    return lines
end

function App:buildBody(width, height)
    local w = math.floor(width * 0.94)
    local round, st = self:current()
    local over = self:roundOver(self.state.round)
    local parts = {}

    -- bottom: suggestions + keyboard, or next/finish
    local bottom = VerticalGroup:new { align = "center" }
    if not over then
        local tried = {}
        for _, g in ipairs(st.guesses) do tried[g] = true end
        local row = {}
        for _, code in ipairs(FoodGuessr.suggest(self.input, tried, 3)) do
            table.insert(row, { text = NAME[code], callback = function() self:guess(code) end })
        end
        if #row == 0 then
            table.insert(row, { text = self.input == "" and "Type a country…" or "No match", enabled = false })
        end
        table.insert(bottom, ButtonTable:new { width = w, buttons = { row }, show_parent = self })
        table.insert(bottom, UI.span(6))
        table.insert(bottom, UI.Keyboard:new {
            width = w,
            height = UI.px(56) * 3,
            rows = {
                UI.QWERTY[1], UI.QWERTY[2],
                { "Z", "X", "C", "V", "B", "N", "M", { label = "⌫", value = "DEL", width = 2 } },
            },
            on_key = function(k) self:onKey(k) end,
        })
    else
        local last = self.state.round >= #self.rounds
        table.insert(bottom, ButtonTable:new {
            width = w,
            show_parent = self,
            buttons = { {
                { text = "About this dish", callback = function() self:showInfo() end },
                { text = last and "Final score" or "Next dish ›", callback = function() self:nextRound() end },
            } },
        })
    end

    -- top: photo, hints, guesses
    local hint_row = {
        { text = st.hints.name and round.name or "Name", callback = function() self:hint("name") end },
        { text = "Ingredients", callback = function() self:hint("ingredients") end },
        { text = "Description", callback = function() self:hint("description") end },
    }
    local hints = ButtonTable:new { width = w, buttons = { hint_row }, show_parent = self }
    local typed = UI.text(over and ("Answer: " .. self:answerNames(round)) or
        (self.input ~= "" and self.input or " "), w, { bold = true, face = "infofont" })
    local lines = self:guessLines()
    local guesses = UI.text(#lines > 0 and table.concat(lines, "\n") or
        string.format("%d guesses left", MAX_GUESSES - #st.guesses), w, { face = "smallinfofont", alignment = "left" })
    local fixed = bottom:getSize().h + hints:getSize().h + typed:getSize().h + UI.px(5 * 22) * 1 + UI.px(40)
    local img_h = math.max(UI.px(120), height - fixed)
    if round.image_path then
        table.insert(parts, ImageWidget:new { file = round.image_path, width = w, height = img_h, scale_factor = 0 })
    else
        table.insert(parts, UI.text("(photo unavailable)", w))
    end
    table.insert(parts, UI.span(4))
    table.insert(parts, hints)
    table.insert(parts, UI.span(4))
    table.insert(parts, typed)
    table.insert(parts, guesses)
    local top = VerticalGroup:new { align = "center" }
    for _, p in ipairs(parts) do table.insert(top, p) end
    return top, bottom
end

function App:onKey(k)
    if k == "DEL" then
        self.input = self.input:sub(1, -2)
    elseif #self.input < 24 then
        self.input = self.input .. k
    end
    self:refresh()
end

function App:save()
    Store.saveProgress("foodguessr", self.date, self:markDone())
end

function App:guess(code)
    local _, st = self:current()
    table.insert(st.guesses, code)
    self.input = ""
    self:save()
    self:refresh()
end

function App:hint(kind)
    local round, st = self:current()
    st.hints[kind] = true
    self:save()
    local text = kind == "name" and round.name
        or kind == "ingredients" and round.ingredients
        or round.description
    UIManager:show(InfoMessage:new { text = (text ~= "" and text) or "No hint for this dish." })
    if kind == "name" then self:refresh() end
end

function App:showInfo()
    local round = self:current()
    UIManager:show(InfoMessage:new {
        text = string.format("%s\n%s\n\n%s", round.name, self:answerNames(round), round.info or ""),
    })
end

function App:nextRound()
    if self.state.round < #self.rounds then
        self.state.round = self.state.round + 1
        self.input = ""
        self:save()
        return self:refresh()
    end
    UIManager:show(InfoMessage:new {
        text = string.format("FoodGuessr complete!\n\nScore: %s / %s", commas(self:totalScore()),
            commas(5000 * #self.rounds)),
    })
end

-- loading --------------------------------------------------------------------

local function parseRounds(today, cache)
    local rounds = {}
    for i, r in ipairs(today.rounds or {}) do
        local food = r.food or {}
        local answers, names = {}, {}
        for _, c in ipairs(food.countriesV2 or {}) do
            table.insert(answers, c.countryCode)
            table.insert(names, c.name or NAME[c.countryCode] or c.countryCode)
        end
        local image = food.images and food.images[1]
        local path
        if image and image.key then
            local base = image.key:gsub("%.%w+$", "")
            path = string.format("%s/foodguessr-%s.webp", cache, base)
            local f = io.open(path, "rb")
            if f then
                f:close()
            elseif not Http.download(string.format(IMAGE_URL, base), path) then
                path = nil
            end
        end
        table.insert(rounds, {
            name = food.name or "?",
            ingredients = food.ingredients or "",
            description = food.informationHint or "",
            info = food.informationWin or "",
            answers = answers,
            answer_names = names,
            image_path = path,
        })
    end
    return rounds
end

function FoodGuessr.launch()
    local cache = DataStorage:getDataDir() .. "/cache"
    local result, err = UI.withBusy("Loading FoodGuessr…", function()
        local data, e = Http.getJson(TODAY_URL)
        if not data then return nil, e end
        local today = data[1] and data[1].result and data[1].result.data and data[1].result.data.json
        if type(today) ~= "table" or type(today.rounds) ~= "table" then return nil, "unexpected data" end
        os.execute("mkdir -p '" .. cache .. "'")
        local rounds = parseRounds(today, cache)
        -- keep only today's photos
        local keep = {}
        for _, r in ipairs(rounds) do if r.image_path then keep[r.image_path] = true end end
        local ok, lfs = pcall(require, "libs/libkoreader-lfs")
        if ok and lfs then
            for name in lfs.dir(cache) do
                local path = cache .. "/" .. name
                if name:match("^foodguessr%-") and not keep[path] then os.remove(path) end
            end
        end
        return { today = today, rounds = rounds }
    end)
    if not result then
        UI.error("Couldn't load FoodGuessr.\n" .. tostring(err))
        return
    end
    local date = tostring(result.today.date or os.date("!%Y-%m-%d")):sub(1, 10)
    UIManager:show(App:new {
        date = date,
        rounds = result.rounds,
        pairs = result.today.v2Distances and result.today.v2Distances.pairs or {},
        state = Store.loadProgress("foodguessr", date),
    })
end

FoodGuessr.compass = compass
FoodGuessr.nearMiss = nearMiss

return FoodGuessr
