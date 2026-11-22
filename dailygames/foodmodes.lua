--[[
FoodGuessr's extra daily modes (foodguessr.com):

  Cuisine Match: 8 rounds. "Which dish belongs in <country>'s cuisine?"
    Three dishes; two chances. 5,000 points first try, 2,000 second try.
  Plate-Off: 10 rounds. "Which dish did the community like more?"
    Two dishes; 1 point per right pick (ties count as right).

Data: tRPC cuisineMatch.today / plateOff.today with input
{"0":{"json":{"date":<UTC midnight, ms>,"intent":"play"}}}. Answers are in the
data (correctFoodIndex; yumCount/yuckCount), checked here like the site does.
]]

local ButtonTable = require("ui/widget/buttontable")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local Http = require("dailygames/http")
local Store = require("dailygames/store")
local UI = require("dailygames/ui")

local IMAGE_URL = "https://r2.foodguessr.com/f/ir/%s/%s.webp"
local cache_dir = DataStorage:getDataDir() .. "/cache"

local FoodModes = {}

local function urlencode(s)
    return (s:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
end

--- tRPC URL for a FoodGuessr daily procedure (date = today's UTC midnight).
function FoodModes.url(proc, now)
    now = now or os.time()
    local midnight = now - now % 86400
    local input = string.format('{"0":{"json":{"date":%d000,"intent":"play"}}}', midnight)
    return "https://www.foodguessr.com/api/trpc/" .. proc .. "?batch=1&input=" .. urlencode(input)
end

local function clean(name)
    return (tostring(name or "?"):gsub("%*%*%*", ""))
end

--- Country list; with `limit`, "A, B, C +22 more" so captions stay one or two lines.
local function countryNames(food, limit)
    local names = {}
    for _, c in ipairs(food.countries or {}) do table.insert(names, c.name) end
    if limit and #names > limit then
        local more = #names - limit
        for i = #names, limit + 1, -1 do names[i] = nil end
        return table.concat(names, ", ") .. string.format(" +%d more", more)
    end
    return table.concat(names, ", ")
end

--- Downloads a dish photo (480w, or the largest smaller size listed).
local function photo(food)
    local img = food.images and food.images[1]
    if not (img and img.key) then return nil end
    local key = (img.editedKey or img.key):gsub("%.%w+$", "")
    local size = "480w"
    local sizes = {}
    for _, s in ipairs(img.sizes or {}) do sizes[s] = true end
    if next(sizes) and not sizes[size] then
        for _, s in ipairs { "640w", "320w", "800w", "200w" } do
            if sizes[s] then size = s break end
        end
    end
    local path = cache_dir .. "/foodmode-" .. key .. ".webp"
    local f = io.open(path, "rb")
    if f then f:close() return path end
    os.execute("mkdir -p '" .. cache_dir .. "'")
    if Http.download(string.format(IMAGE_URL, key, size), path) then return path end
end

local function details(food, reveal)
    local lines = {}
    if reveal then
        table.insert(lines, clean(food.name))
        table.insert(lines, "From " .. countryNames(food))
        table.insert(lines, "")
    end
    if food.ingredients and food.ingredients ~= "" then table.insert(lines, "Ingredients: " .. food.ingredients) end
    if food.informationHint and food.informationHint ~= "" then table.insert(lines, "\n" .. food.informationHint) end
    UIManager:show(InfoMessage:new { text = #lines > 0 and table.concat(lines, "\n") or "No details for this dish." })
end

local function commas(n)
    local s = tostring(math.floor(n))
    repeat local k; s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end

local function dish(path, w, h)
    if path then return UI.photo(path, w, h) end
    return UI.text("(photo unavailable)", w)
end

-- Cuisine Match --------------------------------------------------------------

local CuisineMatch = UI.FullscreenApp:extend {
    name = "cuisinematch_app",
    help_text = [[Three dishes, one country.

Which dish belongs in the country's cuisine? Tap Details to see a dish's ingredients and a hint, then Pick.

You get two chances: 5,000 points for the first try, 2,000 for the second. 8 rounds, 40,000 points max.]],
}

function CuisineMatch:setup()
    self.state = self.state or { round = 1, picks = {} }
end

function CuisineMatch:progressKey() return "cuisinematch" end

function CuisineMatch:getTitle()
    return string.format("Cuisine Match · %d of %d", math.min(self.state.round, #self.rounds), #self.rounds)
end

function CuisineMatch:isOver() return self.state.round > #self.rounds end
function CuisineMatch:isComplete() return self:isOver() or self:result(#self.rounds).done end

--- Result of round i: { done, correct, points, picks }
function CuisineMatch:result(i)
    local picks = self.state.picks[i] or {}
    local right = self.rounds[i].correctFoodIndex + 1
    if picks[1] == right then return { done = true, correct = true, points = 5000, guess = 1 } end
    if picks[2] then
        return { done = true, correct = picks[2] == right, points = picks[2] == right and 2000 or 0, guess = 2 }
    end
    return { done = false }
end

function CuisineMatch:score()
    local total = 0
    for i = 1, #self.rounds do
        local r = self:result(i)
        if r.done then total = total + r.points end
    end
    return total
end

function CuisineMatch:buildBody(width, height)
    local w = math.floor(width * 0.94)
    if self:isOver() then
        local marks = {}
        for i = 1, #self.rounds do
            local r = self:result(i)
            table.insert(marks, r.correct and (r.guess == 1 and "✓" or "½") or "✗")
        end
        local text = string.format("Cuisine Match complete!\n\nScore: %s / 40,000\n%s\n\n✓ first try · ½ second try · ✗ missed",
            commas(self:score()), table.concat(marks, " "))
        return UI.text(text, w, { face = "infofont" }), ButtonTable:new { width = w, show_parent = self,
            buttons = { { { text = "Copy share text", callback = function() self:copyShare() end } } } }
    end
    local i = self.state.round
    local round = self.rounds[i]
    local res = self:result(i)
    local picks = self.state.picks[i] or {}
    local prompt = UI.text(string.format("Which dish belongs in %s's cuisine?", round.country.name), w,
        { bold = true, face = "infofont" })
    local bottom = VerticalGroup:new { align = "center", self:statusLine(w) }
    if res.done then
        table.insert(bottom, ButtonTable:new { width = w, show_parent = self, buttons = { {
            { text = i >= #self.rounds and "See results" or "Next round ›", callback = function() self:advance() end } } } })
    end
    local each = math.floor((height - prompt:getSize().h - bottom:getSize().h - UI.px(20)) / #round.foods)
    local top = VerticalGroup:new { align = "center", prompt, UI.span(4) }
    for k, food in ipairs(round.foods) do
        local label
        if res.done then
            label = (k == round.correctFoodIndex + 1 and "✓ " or "") .. clean(food.name) .. " · " .. countryNames(food, 3)
        elseif picks[1] == k then
            label = "✗ Not from " .. round.country.name
        end
        local row = {
            { text = "Details", callback = function() details(food, res.done) end },
        }
        if not res.done and picks[1] ~= k then
            table.insert(row, { text = "Pick this dish", callback = function() self:pick(k) end })
        end
        local buttons = ButtonTable:new { width = w, buttons = { row }, show_parent = self }
        local caption = label and UI.text(label, w, { bold = true }) or nil
        local img_h = each - buttons:getSize().h - (caption and caption:getSize().h or 0) - UI.px(6)
        table.insert(top, dish(round.paths[k], w, math.max(UI.px(60), img_h)))
        if caption then table.insert(top, caption) end
        table.insert(top, buttons)
    end
    return top, bottom
end

function CuisineMatch:pick(k)
    local i = self.state.round
    self.state.picks[i] = self.state.picks[i] or {}
    table.insert(self.state.picks[i], k)
    local res = self:result(i)
    if res.done then
        self.status = res.correct and string.format("Correct! +%s", commas(res.points)) or "Not this time."
    else
        self.status = "One more chance!"
    end
    Store.saveProgress("cuisinematch", self.date, self:markDone())
    self:refresh()
end

function CuisineMatch:advance()
    self.state.round = self.state.round + 1
    self.status = ""
    Store.saveProgress("cuisinematch", self.date, self:markDone())
    self:refresh()
end

function CuisineMatch:copyShare()
    local marks = {}
    for i = 1, #self.rounds do
        local r = self:result(i)
        table.insert(marks, r.correct and (r.guess == 1 and "✅" or "🟨") or "❌")
    end
    UI.copy(string.format("I got %s on today's FoodGuessr Cuisine Match!\n\n%s\n\n%s\nPlay here: https://www.foodguessr.com/game/cuisine-match/daily",
        commas(self:score()), table.concat(marks), os.date("!%A, %b %d, %Y")))
end

-- Plate-Off ------------------------------------------------------------------

local PlateOff = UI.FullscreenApp:extend {
    name = "plateoff_app",
    help_text = [[Which dish did the community like more?

Two dishes per round. Tap Details for ingredients and a hint, then pick the one you think more players liked. 10 rounds, 1 point each.]],
}

function PlateOff:setup()
    self.state = self.state or { round = 1, picks = {} }
end

function PlateOff:progressKey() return "plateoff" end

function PlateOff:getTitle()
    return string.format("Plate-Off · %d of %d", math.min(self.state.round, #self.rounds), #self.rounds)
end

function PlateOff:isOver() return self.state.round > #self.rounds end
function PlateOff:isComplete() return self:isOver() or self.state.picks[#self.rounds] ~= nil end

local function ratio(food) return (food.yumCount or 0) / math.max(food.yuckCount or 0, 1) end
local function liked(food)
    local yum, yuck = food.yumCount or 0, food.yuckCount or 0
    return yum + yuck > 0 and string.format("%.1f%% liked it", yum / (yum + yuck) * 100) or "no votes"
end

--- True if `side` ("left"/"right") was the more-liked dish (ties count as right).
function FoodModes.plateOffCorrect(round, side)
    local l, r = ratio(round.leftFood), ratio(round.rightFood)
    return l == r or side == (l > r and "left" or "right")
end

function PlateOff:score()
    local n = 0
    for i, side in pairs(self.state.picks) do
        if FoodModes.plateOffCorrect(self.rounds[i], side) then n = n + 1 end
    end
    return n
end

function PlateOff:buildBody(width, height)
    local w = math.floor(width * 0.94)
    if self:isOver() then
        local marks = {}
        for i = 1, #self.rounds do
            table.insert(marks, FoodModes.plateOffCorrect(self.rounds[i], self.state.picks[i]) and "✓" or "✗")
        end
        local text = string.format("Plate-Off complete!\n\nScore: %d / %d\n%s", self:score(), #self.rounds, table.concat(marks, " "))
        return UI.text(text, w, { face = "infofont" }), ButtonTable:new { width = w, show_parent = self,
            buttons = { { { text = "Copy share text", callback = function() self:copyShare() end } } } }
    end
    local i = self.state.round
    local round = self.rounds[i]
    local picked = self.state.picks[i]
    local prompt = UI.text("Which dish did the community like more?", w, { bold = true, face = "infofont" })
    local bottom = VerticalGroup:new { align = "center", self:statusLine(w) }
    if picked then
        table.insert(bottom, ButtonTable:new { width = w, show_parent = self, buttons = { {
            { text = i >= #self.rounds and "See results" or "Next round ›", callback = function() self:advance() end } } } })
    end
    local each = math.floor((height - prompt:getSize().h - bottom:getSize().h - UI.px(24)) / 2)
    local top = VerticalGroup:new { align = "center", prompt, UI.span(4) }
    for _, side in ipairs { "left", "right" } do
        local food = side == "left" and round.leftFood or round.rightFood
        local caption = clean(food.name) .. (picked and ("  ·  " .. liked(food)) or "")
        if picked == side then caption = "Your pick: " .. caption end
        local cap = UI.text(caption, w, { bold = true })
        local row = { { text = "Details", callback = function() details(food, picked ~= nil) end } }
        if not picked then
            table.insert(row, { text = "This one", callback = function() self:pick(side) end })
        end
        local buttons = ButtonTable:new { width = w, buttons = { row }, show_parent = self }
        local img_h = each - cap:getSize().h - buttons:getSize().h - UI.px(6)
        table.insert(top, dish(round.paths[side], w, math.max(UI.px(60), img_h)))
        table.insert(top, cap)
        table.insert(top, buttons)
    end
    return top, bottom
end

function PlateOff:pick(side)
    local i = self.state.round
    self.state.picks[i] = side
    self.status = FoodModes.plateOffCorrect(self.rounds[i], side) and "Correct!" or "Nope, the other one."
    Store.saveProgress("plateoff", self.date, self:markDone())
    self:refresh()
end

function PlateOff:advance()
    self.state.round = self.state.round + 1
    self.status = ""
    Store.saveProgress("plateoff", self.date, self:markDone())
    self:refresh()
end

function PlateOff:copyShare()
    local marks = {}
    for i = 1, #self.rounds do
        table.insert(marks, FoodModes.plateOffCorrect(self.rounds[i], self.state.picks[i]) and "✅" or "❌")
    end
    UI.copy(string.format("I got %d/%d on today's FoodGuessr Plate-Off!\n\n%s\n\n%s\nPlay here: https://www.foodguessr.com/game/plate-off/daily",
        self:score(), #self.rounds, table.concat(marks), os.date("!%A, %b %d, %Y")))
end

-- loading --------------------------------------------------------------------

--- Deletes this mode's photos older than two days (both modes share the cache).
local function prune()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not (ok and lfs and lfs.attributes(cache_dir, "mode") == "directory") then return end
    for name in lfs.dir(cache_dir) do
        local path = cache_dir .. "/" .. name
        local mtime = name:match("^foodmode%-") and lfs.attributes(path, "modification")
        if mtime and os.time() - mtime > 2 * 86400 then os.remove(path) end
    end
end

local function load(proc, label, prepare)
    return UI.withBusy("Loading " .. label .. "…", function()
        prune()
        local data, err = Http.getJson(FoodModes.url(proc))
        if not data then return nil, err end
        local today = data[1] and data[1].result and data[1].result.data and data[1].result.data.json
        if type(today) ~= "table" or type(today.rounds) ~= "table" then return nil, "unexpected data" end
        return prepare(today)
    end)
end

function FoodModes.launchCuisineMatch()
    local today, err = load("cuisineMatch.today", "Cuisine Match", function(t)
        for _, r in ipairs(t.rounds) do
            r.paths = {}
            for k, food in ipairs(r.foods or {}) do r.paths[k] = photo(food) end
        end
        return t
    end)
    if not today then return UI.error("Couldn't load Cuisine Match.\n" .. tostring(err)) end
    local date = tostring(today.date or ""):sub(1, 10)
    UIManager:show(CuisineMatch:new {
        date = date, rounds = today.rounds, state = Store.loadProgress("cuisinematch", date),
    })
end

function FoodModes.launchPlateOff()
    local today, err = load("plateOff.today", "Plate-Off", function(t)
        for _, r in ipairs(t.rounds) do
            r.paths = { left = photo(r.leftFood or {}), right = photo(r.rightFood or {}) }
        end
        return t
    end)
    if not today then return UI.error("Couldn't load Plate-Off.\n" .. tostring(err)) end
    local date = tostring(today.date or ""):sub(1, 10)
    UIManager:show(PlateOff:new {
        date = date, rounds = today.rounds, state = Store.loadProgress("plateoff", date),
    })
end

return FoodModes
