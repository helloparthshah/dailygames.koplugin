--[[
More/Less (lessgames.com/moreless): which has more? Five categories (Google
searches, Spotify streams, movie ratings, prices, trivia), five rounds each.
Every round compares two items; tap the one with the bigger number. The
winner of each round becomes the top card of the next. Score out of 25.

Data: the day's items are in the page (Next.js flight data: a
{"rounds":[...],"date":...} object). Answers come from the site's API:
POST https://api.lessgames.com/moreless/guess
  { challengeDate, categoryId, roundIndex, direction = "left"|"right" }
  -> { correct, stats = { [roundNumber] = value, ... } }
]]

local ButtonTable = require("ui/widget/buttontable")
local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local JSON = require("json")

local Http = require("dailygames/http")
local Store = require("dailygames/store")
local UI = require("dailygames/ui")

local PAGE_URL = "https://lessgames.com/moreless"
local GUESS_URL = "https://api.lessgames.com/moreless/guess"
local ROUNDS = 5
local START_DATE = os.time { year = 2025, month = 8, day = 29, hour = 12 }

local CATEGORIES = {
    [0] = { name = "Google Searches", format = "integer", unit = "searches" },
    [1] = { name = "Spotify Streams", format = "integer", unit = "streams" },
    [2] = { name = "Movie Ratings", format = "decimal", unit = "rating" },
    [3] = { name = "Prices", format = "integer", prefix = "$" },
    [4] = { name = "Trivia", format = "auto" },
}

local MoreLess = {}

-- data -----------------------------------------------------------------------

--- Extracts the {"rounds":[...],"date":"..."} object from the page's flight data.
function MoreLess.parsePage(html)
    local parts = {}
    for chunk in html:gmatch('self%.__next_f%.push%(%[1,"(.-[^\\])"%]%)') do
        -- decode the JS string literal (wrapped in an array: some JSON
        -- decoders reject a bare top-level string)
        local ok, arr = pcall(JSON.decode, '["' .. chunk .. '"]')
        if ok and type(arr) == "table" and type(arr[1]) == "string" then parts[#parts + 1] = arr[1] end
    end
    local text = table.concat(parts)
    local start = text:find('{"rounds":', 1, true)
    if not start then return nil end
    local depth, in_str, esc = 0, false, false
    for i = start, #text do
        local ch = text:sub(i, i)
        if in_str then
            if esc then esc = false
            elseif ch == "\\" then esc = true
            elseif ch == '"' then in_str = false end
        elseif ch == '"' then in_str = true
        elseif ch == "{" then depth = depth + 1
        elseif ch == "}" then
            depth = depth - 1
            if depth == 0 then
                return Http.decode(text:sub(start, i))
            end
        end
    end
end

--- Groups items by category: cats[categoryId][roundNumber] = item.
function MoreLess.byCategory(data)
    local cats = {}
    for _, item in ipairs(data.rounds or {}) do
        local id = tonumber(item.categoryId)
        cats[id] = cats[id] or {}
        cats[id][tonumber(item.roundNumber)] = item
    end
    return cats
end

local function commas(n)
    local s = tostring(n)
    local int, frac = s:match("^(%-?%d+)(%.?%d*)$")
    if not int then return s end
    while true do
        local r, k = int:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
        int = r
        if k == 0 then break end
    end
    return int .. frac
end

function MoreLess.formatStat(category, value)
    local cat = CATEGORIES[category] or {}
    local n = tonumber(value)
    if not n then return tostring(value) end
    local s
    if cat.format == "decimal" then
        s = string.format("%.1f", n)
    elseif cat.format == "integer" or math.floor(n) == n then
        s = commas(string.format("%d", n))
    else
        s = commas(string.format("%.2f", n):gsub("0+$", ""):gsub("%.$", ""))
    end
    return (cat.prefix or "") .. s
end

function MoreLess.dayNumber(date)
    local y, m, d = date:match("^(%d+)-(%d+)-(%d+)$")
    local t = os.time { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
    return math.floor((t - START_DATE) / 86400 + 0.5) + 1
end

-- card -----------------------------------------------------------------------

local function card(app, item, width, height, stat, mark, on_tap)
    local inner = VerticalGroup:new { align = "center" }
    local title = UI.text(item.title or "?", width, { bold = true, face = "infofont" })
    local desc = item.description and item.description ~= "" and
        UI.text(item.description, width, { face = "smallinfofont" }) or nil
    local value = UI.text(stat and ((mark or "") .. stat) or "?", width, { bold = true, face = "tfont" })
    local text_h = title:getSize().h + (desc and desc:getSize().h or 0) + value:getSize().h + UI.px(16)
    local img_h = math.max(UI.px(60), height - text_h)
    local path = app:imagePath(item)
    if path then
        table.insert(inner, UI.photo(path, width, img_h))
    end
    table.insert(inner, UI.span(4))
    table.insert(inner, title)
    if desc then table.insert(inner, desc) end
    table.insert(inner, value)
    return inner
end

-- app ------------------------------------------------------------------------

local App = UI.FullscreenApp:extend {
    name = "moreless_app",
    help_text = [[Which has more?

Each round shows two things. Tap the one with the bigger number (searches, streams, rating, price or trivia amount).

The answer is revealed after each pick, and the second card moves up for the next round. 5 categories × 5 rounds = 25 points.]],
}

function App:setup()
    self.state = self.state or { cat = 0, round = 1, results = {}, stats = {}, revealed = false }
    self.cache = DataStorage:getDataDir() .. "/cache"
end

function App:progressKey() return "moreless" end

function App:getTitle()
    return "More/Less #" .. MoreLess.dayNumber(self.date)
end

function App:isOver()
    return self.state.cat > 4
end

function App:score()
    local n = 0
    for _, list in pairs(self.state.results) do
        for _, ok in ipairs(list) do if ok then n = n + 1 end end
    end
    return n
end

function App:imagePath(item)
    if not item or not item.image then return nil end
    local name = "moreless-" .. item.image:gsub("^.*/", ""):gsub("[^%w%.%-_]", "_")
    local path = self.cache .. "/" .. name
    local f = io.open(path, "rb")
    if f then f:close() return path end
    os.execute("mkdir -p '" .. self.cache .. "'")
    if Http.download(item.image, path) then return path end
end

function App:items()
    local cat = self.cats[self.state.cat] or {}
    return cat[self.state.round], cat[self.state.round + 1]
end

function App:statFor(roundNumber)
    local s = self.state.stats[tostring(self.state.cat)]
    return s and s[tostring(roundNumber)]
end

function App:buildBody(width, height)
    local w = math.floor(width * 0.94)
    if self:isOver() then
        local lines = { string.format("Score: %d / %d", self:score(), 5 * ROUNDS), "" }
        for c = 0, 4 do
            local row = {}
            for _, ok in ipairs(self.state.results[tostring(c)] or {}) do table.insert(row, ok and "✓" or "✗") end
            table.insert(lines, (CATEGORIES[c].name) .. ": " .. table.concat(row, " "))
        end
        local summary = UI.text(table.concat(lines, "\n"), w, { face = "infofont" })
        local share = ButtonTable:new { width = w, show_parent = self,
            buttons = { { { text = "Copy share text", callback = function() self:copyShare() end } } } }
        return summary, share
    end

    local cat = CATEGORIES[self.state.cat]
    local left, right = self:items()
    local results = self.state.results[tostring(self.state.cat)] or {}
    local header = UI.text(string.format("%s · round %d of %d · score %d", cat.name, self.state.round, ROUNDS,
        self:score()), w, { bold = true })
    local buttons
    if self.state.revealed then
        local last = self.state.round >= ROUNDS
        buttons = ButtonTable:new { width = w, show_parent = self, buttons = { {
            { text = last and (self.state.cat >= 4 and "See results" or "Next category ›") or "Next round ›",
              callback = function() self:advance() end },
        } } }
    else
        -- before picking, the cards themselves are the buttons
        buttons = UI.text("Tap the one with more", w, { bold = true, face = "infofont" })
    end
    local status = self:statusLine(w)
    local bottom = VerticalGroup:new { align = "center", status, UI.span(6), buttons }
    local card_h = math.floor((height - header:getSize().h - bottom:getSize().h - UI.px(40)) / 2)
    local verdict = results[self.state.round]
    local left_stat = (self.state.round > 1 or self.state.revealed) and self:statFor(self.state.round)
    local right_stat = self.state.revealed and self:statFor(self.state.round + 1)
    local top = VerticalGroup:new {
        align = "center",
        header, UI.span(6),
        self:pickable(card(self, left, w, card_h, left_stat and MoreLess.formatStat(self.state.cat, left_stat)), "left"),
        UI.text("— or —", w, { face = "smallinfofont" }),
        self:pickable(card(self, right, w, card_h, right_stat and MoreLess.formatStat(self.state.cat, right_stat),
            self.state.revealed and (verdict and "✓ " or "✗ ") or nil), "right"),
    }
    return top, bottom
end

--- Tapping a card picks it (until the answer is revealed).
function App:pickable(widget, side)
    if self.state.revealed then return widget end
    return UI.tappable(widget, function() self:pick(side) end)
end

function App:save()
    Store.saveProgress("moreless", self.date, self:markDone())
end

function App:pick(direction)
    local res, code, err = UI.withBusy("Checking…", function()
        return Http.request {
            url = GUESS_URL,
            method = "POST",
            headers = { ["Origin"] = "https://lessgames.com" },
            body = { challengeDate = self.date, categoryId = self.state.cat,
                     roundIndex = self.state.round - 1, direction = direction },
        }
    end)
    if code ~= 200 or type(res) ~= "table" then
        return self:setStatus("Couldn't check (" .. tostring(err or code) .. "). Try again.")
    end
    local key = tostring(self.state.cat)
    self.state.stats[key] = self.state.stats[key] or {}
    for k, v in pairs(res.stats or {}) do self.state.stats[key][tostring(k)] = v end
    self.state.results[key] = self.state.results[key] or {}
    self.state.results[key][self.state.round] = res.correct and true or false
    self.state.revealed = true
    self:save()
    self:setStatus(res.correct and "Correct!" or "Not quite.")
end

function App:advance()
    self.state.revealed = false
    if self.state.round >= ROUNDS then
        self.state.cat = self.state.cat + 1
        self.state.round = 1
    else
        self.state.round = self.state.round + 1
    end
    self.status = ""
    self:save()
    self:refresh()
end

function App:copyShare()
    local lines = { string.format("More/Less #%d — %d/%d", MoreLess.dayNumber(self.date), self:score(), 5 * ROUNDS), "" }
    for c = 0, 4 do
        local row = {}
        for _, ok in ipairs(self.state.results[tostring(c)] or {}) do table.insert(row, ok and "🟩" or "🟥") end
        table.insert(lines, table.concat(row) .. " " .. CATEGORIES[c].name)
    end
    table.insert(lines, "")
    table.insert(lines, "Play Today's Game: https://less.gg/moreless")
    UI.copy(table.concat(lines, "\n"))
end

function MoreLess.launch()
    local data, err = UI.withBusy("Loading More/Less…", function()
        local html, code, e = Http.request { url = PAGE_URL, raw = true }
        if code ~= 200 then return nil, e or ("HTTP " .. tostring(code)) end
        local parsed = MoreLess.parsePage(html)
        if not parsed or not parsed.date then return nil, "couldn't read today's game" end
        return parsed
    end)
    if not data then
        UI.error("Couldn't load More/Less.\n" .. tostring(err))
        return
    end
    UIManager:show(App:new {
        date = data.date,
        cats = MoreLess.byCategory(data),
        state = Store.loadProgress("moreless", data.date),
    })
end

return MoreLess
