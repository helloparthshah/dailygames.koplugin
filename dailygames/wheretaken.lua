--[[
WhereTaken (wheretaken.teuteuf.fr): where was this photo taken?

Main round: guess the country in 6 tries. Each wrong guess shows the
distance, the direction to go, and how close it was (%).
Bonus rounds (one star each): name the landmark, pick the capital, and
identify a city from its photo.

Data: https://cdn-assets.teuteuf.fr/data/ (same files the site uses)
  wheretaken-classic/games/YYYY/YYYY-MM-DD.json -> { countryCode, photoCode,
      landmarkData = { landmarkCode, imageCode }, cityData = { cityCode, imageCode } }
  common/countries.json, common/landmarks.json, common/cities.json
  common/country-images/<cc>/<photo>.jpg, common/landmarks/<code>/<img>.jpg,
  common/cities/<code>/<img>.jpg
Distance/bearing/percentage follow the site (haversine, R = 6371 km;
percentage = floor(100 - 100 * km / 21000)).
]]

local ButtonTable = require("ui/widget/buttontable")
local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local Http = require("dailygames/http")
local Store = require("dailygames/store")
local UI = require("dailygames/ui")

local CDN = "https://cdn-assets.teuteuf.fr/data/"
local MAX_GUESSES = 6
local BONUS_TRIES = 2
local CACHE_DAYS = 7
local EPOCH = os.time { year = 2023, month = 2, day = 27, hour = 12 }

local WhereTaken = {}

-- math -----------------------------------------------------------------------

local R = 6371

function WhereTaken.distance(lat1, lon1, lat2, lon2)
    local rad = math.pi / 180
    local dlat, dlon = (lat2 - lat1) * rad, (lon2 - lon1) * rad
    local a = math.sin(dlat / 2) ^ 2 + math.cos(lat1 * rad) * math.cos(lat2 * rad) * math.sin(dlon / 2) ^ 2
    return math.floor(2 * R * math.atan2(math.sqrt(a), math.sqrt(1 - a)) + 0.5)
end

--- Initial bearing (degrees) from point 1 toward point 2.
function WhereTaken.bearing(lat1, lon1, lat2, lon2)
    local rad = math.pi / 180
    local y = math.sin((lon2 - lon1) * rad) * math.cos(lat2 * rad)
    local x = math.cos(lat1 * rad) * math.sin(lat2 * rad) - math.sin(lat1 * rad) * math.cos(lat2 * rad) * math.cos((lon2 - lon1) * rad)
    return (math.atan2(y, x) / rad + 360) % 360
end

function WhereTaken.percentage(km)
    return math.max(0, math.floor(100 - 100 * km / 21000))
end

local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local function compass(b) return COMPASS[math.floor((b + 22.5) / 45) % 8 + 1] end

--- Deterministic shuffle seeded by a string (same choices all day).
local function seededShuffle(list, seed)
    local h = 5381
    for i = 1, #seed do h = (h * 33 + seed:byte(i)) % 2147483647 end
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    for i = #out, 2, -1 do
        h = (h * 48271) % 2147483647
        local j = h % i + 1
        out[i], out[j] = out[j], out[i]
    end
    return out
end
WhereTaken.seededShuffle = seededShuffle

local function fold(s)
    s = s:lower()
    for k, v in pairs { ["é"] = "e", ["è"] = "e", ["ô"] = "o", ["ç"] = "c", ["å"] = "a", ["ã"] = "a", ["í"] = "i", ["ü"] = "u" } do
        s = s:gsub(k, v)
    end
    return s
end

local function commas(n)
    local s = tostring(math.floor(n))
    repeat local k; s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end

local function enName(x)
    return (type(x.names) == "table" and x.names.en) or x.name or "?"
end

-- data -----------------------------------------------------------------------

local cache_dir = DataStorage:getDataDir() .. "/cache"

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

--- Reference JSON from the CDN, cached on the device for a week.
local function cachedJson(name)
    local path = cache_dir .. "/wheretaken-" .. name:gsub("/", "_")
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    local mtime = ok and lfs.attributes(path, "modification")
    local fresh = mtime and (os.time() - mtime) < CACHE_DAYS * 86400
    if not fresh then
        os.execute("mkdir -p '" .. cache_dir .. "'")
        Http.download(CDN .. name, path)
    end
    local raw = readFile(path)
    if not raw then return nil end
    return Http.decode(raw)
end

local function image(path_on_cdn, local_name)
    local path = cache_dir .. "/wheretaken-img-" .. local_name
    if readFile(path) then return path end
    os.execute("mkdir -p '" .. cache_dir .. "'")
    if Http.download(CDN .. path_on_cdn, path) then return path end
end

-- app ------------------------------------------------------------------------

local App = UI.FullscreenApp:extend {
    name = "wheretaken_app",
    help_text = [[Where was this photo taken?

Type a few letters and tap a country. You have 6 guesses. Wrong guesses show the distance, the direction to go and how close you were.

Then three bonus rounds, two tries each: name the landmark, pick the capital, and say which city is in the photo. Each round you win earns a star.]],
}

function App:setup()
    self.state = self.state or { phase = "main", guesses = {}, bonus = {}, stars = {} }
    self.input = ""
end

function App:isComplete() return self.state.phase == "done" end

function App:progressKey() return "wheretaken" end

function App:getTitle()
    return "WhereTaken #" .. self.number
end

function App:country(code) return self.countries[code] end

function App:judge(code)
    local a, g = self:country(self.answer), self:country(code)
    if code == self.answer then return { correct = true, km = 0, pct = 100 } end
    if not (a and g) then return { correct = false } end
    local km = WhereTaken.distance(g.latitude, g.longitude, a.latitude, a.longitude)
    return { correct = false, km = km, pct = WhereTaken.percentage(km),
             dir = compass(WhereTaken.bearing(g.latitude, g.longitude, a.latitude, a.longitude)) }
end

function App:mainOver()
    local g = self.state.guesses
    return #g >= MAX_GUESSES or g[#g] == self.answer
end

function App:suggest()
    local typed = fold(self.input)
    if typed == "" then return {} end
    local tried, out = {}, {}
    for _, g in ipairs(self.state.guesses) do tried[g] = true end
    for _, c in ipairs(self.country_list) do
        local n = fold(c.name)
        if not tried[c.code] and (n:sub(1, #typed) == typed or n:find(" " .. typed, 1, true)) then
            table.insert(out, c)
            if #out == 3 then break end
        end
    end
    return out
end

--- The current bonus question: { title, prompt, image, choices = { {label, correct} } }
function App:bonusQuestion(phase)
    local cc = self.answer
    if phase == "landmark" and self.landmark then
        local names = { { label = enName(self.landmark), correct = true } }
        for _, l in ipairs(seededShuffle(self.landmarks, self.date .. "lm")) do
            if #names >= 4 then break end
            if l.landmarkCode ~= self.landmark.landmarkCode then table.insert(names, { label = enName(l) }) end
        end
        return { title = "Bonus 1 of 3 · Landmark", prompt = "Which landmark is this?",
                 image = self.landmark_image, choices = seededShuffle(names, self.date .. "lm2") }
    elseif phase == "capital" then
        local cities, capital = {}, nil
        for _, c in ipairs(self.cities) do
            if c.countryCode == cc then
                if c.capital and not capital then capital = c else table.insert(cities, c) end
            end
        end
        if not capital then return nil end
        local choices = { { label = enName(capital), correct = true } }
        for _, c in ipairs(seededShuffle(cities, self.date .. "cap")) do
            if #choices >= 4 then break end
            table.insert(choices, { label = enName(c) })
        end
        if #choices < 2 then return nil end
        return { title = "Bonus 2 of 3 · Capital", prompt = "What is the capital of " .. self:country(cc).name .. "?",
                 choices = seededShuffle(choices, self.date .. "cap2") }
    elseif phase == "city" and self.city then
        local choices = { { label = enName(self.city), correct = true } }
        for _, c in ipairs(seededShuffle(self.cities, self.date .. "city")) do
            if #choices >= 6 then break end
            if c.countryCode == cc and c.index ~= self.city.index then table.insert(choices, { label = enName(c) }) end
        end
        if #choices < 3 then return nil end
        return { title = "Bonus 3 of 3 · City", prompt = "Which city is this?",
                 image = self.city_image, choices = seededShuffle(choices, self.date .. "city2") }
    end
end

local PHASES = { "main", "landmark", "capital", "city", "done" }

function App:nextPhase()
    local i
    for k, p in ipairs(PHASES) do if p == self.state.phase then i = k end end
    repeat
        i = i + 1
    until PHASES[i] == "done" or self:bonusQuestion(PHASES[i])
    self.state.phase = PHASES[i]
    self.status = ""
    self:save()
    self:refresh()
end

function App:save()
    Store.saveProgress("wheretaken", self.date, self:markDone())
end

local function photo(path, w, h)
    if path then return UI.photo(path, w, h) end
    return UI.text("(photo unavailable)", w)
end

function App:buildMain(w, height)
    local over = self:mainOver()
    local bottom = VerticalGroup:new { align = "center" }
    if not over then
        local row = {}
        for _, c in ipairs(self:suggest()) do
            table.insert(row, { text = c.name, callback = function() self:guess(c.code) end })
        end
        if #row == 0 then table.insert(row, { text = self.input == "" and "Type a country…" or "No match", enabled = false }) end
        table.insert(bottom, ButtonTable:new { width = w, buttons = { row }, show_parent = self })
        table.insert(bottom, UI.span(6))
        table.insert(bottom, UI.Keyboard:new {
            width = w, height = UI.px(56) * 3,
            rows = { UI.QWERTY[1], UI.QWERTY[2],
                { "Z", "X", "C", "V", "B", "N", "M", { label = "␣", value = " " }, { label = "⌫", value = "DEL", width = 1.5 } } },
            on_key = function(k) self:onKey(k) end,
        })
    else
        table.insert(bottom, ButtonTable:new { width = w, show_parent = self, buttons = { {
            { text = "Bonus rounds ›", callback = function() self:nextPhase() end } } } })
    end
    local lines = {}
    for _, g in ipairs(self.state.guesses) do
        local j = self:judge(g)
        local name = self:country(g) and self:country(g).name or g
        if j.correct then
            table.insert(lines, "✓ " .. name .. " — correct!")
        elseif j.km then
            table.insert(lines, string.format("✗ %s — %s km %s · %d%%", name, commas(j.km), j.dir, j.pct))
        end
    end
    if over and self.state.guesses[#self.state.guesses] ~= self.answer then
        table.insert(lines, "It was " .. self:country(self.answer).name)
    end
    local list = UI.text(#lines > 0 and table.concat(lines, "\n") or
        string.format("%d guesses left", MAX_GUESSES - #self.state.guesses), w, { face = "smallinfofont", alignment = "left" })
    local typed = UI.text(self.input ~= "" and self.input or " ", w, { bold = true, face = "infofont" })
    local fixed = bottom:getSize().h + typed:getSize().h + UI.px(6 * 26) + UI.px(20)
    local top = VerticalGroup:new { align = "center",
        photo(self.photo, w, math.max(UI.px(120), height - fixed)), UI.span(4), typed, list }
    return top, bottom
end

function App:buildBonus(w, height)
    local q = self:bonusQuestion(self.state.phase)
    local st = self.state.bonus[self.state.phase] or { tries = 0 }
    self.state.bonus[self.state.phase] = st
    local done = st.solved or st.tries >= BONUS_TRIES
    local rows, row = {}, {}
    for _, c in ipairs(q.choices) do
        local label = c.label
        if done and c.correct then label = "✓ " .. label end
        if st.wrong and st.wrong[c.label] then label = "✗ " .. label end
        table.insert(row, { text = label, enabled = not done and not (st.wrong and st.wrong[c.label]),
            callback = function() self:answerBonus(c) end })
        if #row == 2 then table.insert(rows, row); row = {} end
    end
    if #row > 0 then table.insert(rows, row) end
    if done then
        table.insert(rows, { { text = "Continue ›", callback = function() self:nextPhase() end } })
    end
    local bottom = VerticalGroup:new { align = "center", self:statusLine(w), UI.span(6),
        ButtonTable:new { width = w, buttons = rows, show_parent = self } }
    local prompt = UI.text(q.title .. "\n" .. q.prompt, w, { bold = true, face = "infofont" })
    local top = VerticalGroup:new { align = "center", prompt, UI.span(6) }
    if q.image then
        table.insert(top, photo(q.image, w, math.max(UI.px(120), height - bottom:getSize().h - prompt:getSize().h - UI.px(30))))
    end
    return top, bottom
end

function App:buildDone(w)
    local stars = 0
    for _, v in pairs(self.state.stars) do if v then stars = stars + 1 end end
    local text = string.format("WhereTaken #%d\n\n%s\n%d of 4 stars\n\nThe photo was taken in %s.", self.number,
        string.rep("★", stars) .. string.rep("☆", 4 - stars), stars, self:country(self.answer).name)
    return UI.text(text, w, { face = "infofont" }), ButtonTable:new { width = w, show_parent = self,
        buttons = { { { text = "Copy share text", callback = function() self:copyShare(stars) end } } } }
end

function App:buildBody(width, height)
    local w = math.floor(width * 0.94)
    if self.state.phase == "main" then return self:buildMain(w, height) end
    if self.state.phase == "done" then return self:buildDone(w) end
    return self:buildBonus(w, height)
end

function App:onKey(k)
    if k == "DEL" then
        self.input = self.input:sub(1, -2)
    elseif #self.input < 24 and not (k == " " and (self.input == "" or self.input:sub(-1) == " ")) then
        self.input = self.input .. (k == " " and " " or k:lower())
    end
    self:refresh()
end

function App:guess(code)
    table.insert(self.state.guesses, code)
    self.input = ""
    if code == self.answer then self.state.stars.main = true end
    self:save()
    self:refresh()
end

function App:answerBonus(choice)
    local st = self.state.bonus[self.state.phase]
    st.tries = st.tries + 1
    if choice.correct then
        st.solved = true
        self.state.stars[self.state.phase] = true
        self.status = "Correct! ★"
    else
        st.wrong = st.wrong or {}
        st.wrong[choice.label] = true
        self.status = st.tries >= BONUS_TRIES and "Out of tries." or "Not quite, one more try."
    end
    self:save()
    self:refresh()
end

function App:copyShare(stars)
    local rows = {}
    for _, g in ipairs(self.state.guesses) do
        local j = self:judge(g)
        table.insert(rows, j.correct and "🎉" or string.format("%d%% %s", j.pct or 0, j.dir or ""))
    end
    UI.copy(string.format("#WhereTaken #%d (%s)\n%s\n%s\nhttps://wheretaken.teuteuf.fr",
        self.number, self.date, table.concat(rows, "\n"), string.rep("⭐", stars)))
end

function WhereTaken.launch(date)
    local data, err = UI.withBusy("Loading WhereTaken…", function()
        local game = Http.getJson(string.format("%swheretaken-classic/games/%s/%s.json", CDN, date:sub(1, 4), date))
        if type(game) ~= "table" or not game.countryCode then return nil, "no game for " .. date end
        local countries = cachedJson("common/countries.json")
        if type(countries) ~= "table" then return nil, "couldn't load the country list" end
        local landmarks = cachedJson("common/landmarks.json") or {}
        local cities = cachedJson("common/cities.json") or {}
        -- keep only today's photos
        local ok, lfs = pcall(require, "libs/libkoreader-lfs")
        if ok and lfs and lfs.attributes(cache_dir, "mode") == "directory" then
            for name in lfs.dir(cache_dir) do
                if name:match("^wheretaken%-img%-") and not name:find(date, 1, true) then
                    os.remove(cache_dir .. "/" .. name)
                end
            end
        end
        local cc = game.countryCode:lower()
        local d = {
            game = game, countries = countries, landmarks = landmarks, cities = cities,
            photo = image(string.format("common/country-images/%s/%s.jpg", cc, game.photoCode), date .. "-photo.jpg"),
        }
        local lm = game.landmarkData
        if lm then
            for _, l in ipairs(landmarks) do
                if l.landmarkCode == lm.landmarkCode then d.landmark = l end
            end
            d.landmark_image = image(string.format("common/landmarks/%s/%s.jpg", lm.landmarkCode, lm.imageCode),
                date .. "-landmark.jpg")
        end
        local cd = game.cityData
        if cd then
            for _, c in ipairs(cities) do
                if c.index == cd.cityCode then d.city = c end
            end
            d.city_image = image(string.format("common/cities/%s/%s.jpg", cd.cityCode, cd.imageCode), date .. "-city.jpg")
        end
        return d
    end)
    if not data then
        UI.error("Couldn't load WhereTaken.\n" .. tostring(err))
        return
    end
    local by_code, list = {}, {}
    for _, c in ipairs(data.countries) do
        by_code[c.code] = c
        table.insert(list, c)
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    local y, m, dd = date:match("^(%d+)-(%d+)-(%d+)$")
    local number = math.floor((os.time { year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 12 } - EPOCH) / 86400 + 0.5) + 1
    UIManager:show(App:new {
        date = date,
        number = number,
        answer = data.game.countryCode,
        countries = by_code,
        country_list = list,
        landmarks = data.landmarks,
        cities = data.cities,
        landmark = data.landmark,
        city = data.city,
        photo = data.photo,
        landmark_image = data.landmark_image,
        city_image = data.city_image,
        state = Store.loadProgress("wheretaken", date),
    })
end

return WhereTaken
