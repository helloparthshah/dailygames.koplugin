--[[
Brandle (capitalle.app/brandle): guess today's brand from a blurred logo in
8 tries. The logo sharpens with every guess, and each guess shows whether the
brand's industry and country match, whether it was founded earlier or later
(within 10 years = close), and whether its revenue band is higher or lower.

Data: the brand list and logo paths live in one of the page's script chunks
(an array of {id, name, industry, country, founded, revenue, domain}). The
site picks the day's brand in the browser; Brandle.pick() follows the same
schedule (day = days since 2025-01-01 UTC): a seeded shuffle per cycle before
2026-11-01, and a cycle that avoids repeats within half a list after it.
]]

local bit = require("bit")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local DataStorage = require("datastorage")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local Http = require("dailygames/http")
local Store = require("dailygames/store")
local UI = require("dailygames/ui")

local SITE = "https://capitalle.app"
local MAX_GUESSES = 8
local REVENUE = { Small = 1, Medium = 2, Large = 3, Mega = 4 }
-- blur in px on the site's 96 px logo, by number of guesses made
local BLUR = { 28, 22, 17, 13, 9, 6, 3, 1, 0 }

local Brandle = {}

-- 32-bit arithmetic matching JavaScript --------------------------------------

local tobit, band, bor, bxor, rshift, lshift = bit.tobit, bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local function imul(a, b)
    a, b = tobit(a), tobit(b)
    local ah, al = rshift(a, 16), band(a, 0xffff)
    local bh, bl = rshift(b, 16), band(b, 0xffff)
    return tobit(al * bl + lshift(tobit(ah * bl + al * bh), 16))
end

local function u32(x)
    x = tobit(x)
    return x < 0 and x + 4294967296 or x
end

-- schedule --------------------------------------------------------------------

local EPOCH = os.time { year = 2025, month = 1, day = 1, hour = 12 }
local SALT = 20250101

--- Days since 2025-01-01 for a "YYYY-MM-DD" date.
function Brandle.dayIndex(date)
    local y, m, d = date:match("^(%d+)-(%d+)-(%d+)$")
    local t = os.time { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
    return math.floor((t - EPOCH) / 86400 + 0.5)
end

local CYCLE_START = Brandle.dayIndex("2026-11-01")

-- Before CYCLE_START: the list shuffled with an LCG seeded per cycle.
local function legacy(list, day)
    local n = #list
    local o = u32(SALT + math.floor(day / n))
    local function rnd()
        o = u32(imul(1664525, o) + 1013904223)
        return o / 4294967296
    end
    local a = {}
    for i = 1, n do a[i] = list[i] end
    for e = n - 1, 1, -1 do
        local j = math.floor(rnd() * (e + 1))
        a[e + 1], a[j + 1] = a[j + 1], a[e + 1]
    end
    return a[day % n + 1]
end

local function shuffledIndexes(n, seed)
    local t = seed
    local function rnd()
        t = t + 1831565813
        local e = imul(bxor(tobit(t), rshift(tobit(t), 15)), bor(1, tobit(t)))
        e = bxor(e, tobit(e + imul(bxor(e, rshift(e, 7)), bor(61, e))))
        return u32(bxor(e, rshift(e, 14))) / 4294967296
    end
    local s = {}
    for i = 1, n do s[i] = i - 1 end
    for k = n - 1, 1, -1 do
        local j = math.floor(rnd() * (k + 1))
        s[k + 1], s[j + 1] = s[j + 1], s[k + 1]
    end
    return s
end

--- The brand for day index `day` (see Brandle.dayIndex).
function Brandle.pick(list, day)
    local n = #list
    if day < CYCLE_START then return legacy(list, day) end
    local min_gap = math.min(n, math.max(2, math.ceil(n / 2)))
    local offset = day - CYCLE_START
    local want = math.floor(offset / n)
    local cycles = {}
    for c = 0, want do
        local start = CYCLE_START + c * n
        local last_used = {}
        if c > 0 then
            for pos, idx in ipairs(cycles[c]) do last_used[idx] = start - n + pos - 1 end
        else
            for d = start - min_gap + 1, start - 1 do
                local b = legacy(list, d)
                for i, x in ipairs(list) do
                    if x == b then last_used[i - 1] = d break end
                end
            end
        end
        local seed = tobit(imul(bxor(tobit(2654435769), SALT), 31) + imul(c + 1, 2246822507))
        local pool = shuffledIndexes(n, seed)
        local order = {}
        for e = 0, n - 1 do
            local d = start + e
            local pick = 1
            for k, idx in ipairs(pool) do
                if last_used[idx] == nil or d - last_used[idx] >= min_gap then pick = k break end
            end
            table.insert(order, table.remove(pool, pick))
        end
        cycles[c + 1] = order
    end
    return list[cycles[want + 1][offset % n + 1] + 1]
end

-- data -------------------------------------------------------------------------

local function unescape(s)
    s = s:gsub("\\x(%x%x)", function(h)
        local c = tonumber(h, 16)
        if c < 0x80 then return string.char(c) end
        return string.char(0xC0 + math.floor(c / 64), 0x80 + c % 64)
    end)
    return (s:gsub("\\(.)", "%1"))
end

--- Parses the brand list and logo paths out of a script chunk.
-- Returns { brands = {...}, logos = { [domain] = path } } or nil.
function Brandle.parseChunk(js)
    local brands = {}
    for id, name, industry, country, founded, revenue, domain in js:gmatch(
        '{id:(%d+),name:"(.-)",industry:"(.-)",country:"(.-)",founded:([%d%.e]+),revenue:"(.-)",domain:"(.-)"}') do
        table.insert(brands, {
            id = tonumber(id), name = unescape(name), industry = unescape(industry),
            country = unescape(country), founded = math.floor(tonumber(founded) or 0),
            revenue = revenue, domain = domain,
        })
    end
    if #brands < 50 then return nil end
    local logos = {}
    for domain, path in js:gmatch('"([%w%.%-]+)":"(/brandle%-logos/[^"]+)"') do logos[domain] = path end
    return { brands = brands, logos = logos }
end

--- Compares a guess with the answer (same rules as the site).
function Brandle.judge(guess, answer)
    local dy = guess.founded - answer.founded
    local year
    if dy == 0 then year = "correct"
    elseif math.abs(dy) <= 10 then year = dy > 0 and "close-earlier" or "close-later"
    else year = dy > 0 and "earlier" or "later" end
    local gr, ar = REVENUE[guess.revenue] or 0, REVENUE[answer.revenue] or 0
    return {
        correct = guess.id == answer.id,
        industry = guess.industry == answer.industry,
        country = guess.country == answer.country,
        year = year,
        revenue = gr == ar and "correct" or gr < ar and "higher" or "lower",
    }
end

function Brandle.suggest(brands, typed, exclude, limit)
    typed = typed:lower()
    if typed == "" then return {} end
    local out = {}
    for _, b in ipairs(brands) do
        if not (exclude and exclude[b.id]) then
            local name = b.name:lower()
            local hit = name:sub(1, #typed) == typed
            if not hit then
                for word in name:gmatch("[^%s%-&]+") do
                    if word:sub(1, #typed) == typed then hit = true break end
                end
            end
            if hit then table.insert(out, b) end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    local limited = {}
    for i = 1, math.min(limit or 3, #out) do limited[i] = out[i] end
    return limited
end

-- logo ---------------------------------------------------------------------------

--- Logo drawn as a coarse grid of gray squares (e-ink stand-in for the
-- site's blur), sharpening as guesses are made.
local Logo = UI.Board:extend {}

function Logo:setup()
    local blur = BLUR[math.min(#self.app.state.guesses + 1, #BLUR)]
    if self.app:isOver() then blur = 0 end
    local src = self.app:logoSource(math.min(self.width, self.height))
    if not src then return end
    local sw, sh = src:getWidth(), src:getHeight()
    if blur <= 1 then
        self.bb = src:copy()
        return
    end
    local cells = math.max(3, math.floor(96 / (blur * 1.15)))
    local cell = math.max(1, math.ceil(math.max(sw, sh) / cells))
    -- average each square (sampled on a grid) so thin strokes still show,
    -- then stretch the contrast: averaging washes logos out on e-ink
    local avgs, lo, hi = {}, 255, 0
    for cy = 0, sh - 1, cell do
        for cx = 0, sw - 1, cell do
            local cw, ch = math.min(cell, sw - cx), math.min(cell, sh - cy)
            local step = math.max(1, math.floor(cell / 12))
            local sum, count = 0, 0
            for py = cy, cy + ch - 1, step do
                for px = cx, cx + cw - 1, step do
                    sum = sum + src:getPixel(px, py):getColor8().a
                    count = count + 1
                end
            end
            local v = sum / math.max(count, 1)
            avgs[#avgs + 1] = { cx, cy, cw, ch, v }
            lo, hi = math.min(lo, v), math.max(hi, v)
        end
    end
    local bb = Blitbuffer.new(sw, sh, Blitbuffer.TYPE_BB8)
    bb:fill(Blitbuffer.COLOR_WHITE)
    for _, a in ipairs(avgs) do
        local v = a[5]
        if hi - lo > 8 then v = (v - lo) / (hi - lo) * 255 end
        bb:paintRect(a[1], a[2], a[3], a[4], Blitbuffer.Color8(math.floor(v + 0.5)))
    end
    self.bb = bb
end

function Logo:draw(bb, x, y)
    if not self.bb then
        UI.drawText(bb, UI.fitFace({ "(logo unavailable)" }, self.width * 0.8, UI.px(30)), "(logo unavailable)",
            x, y, self.width, self.height, UI.MID)
        return
    end
    local w, h = self.bb:getWidth(), self.bb:getHeight()
    bb:blitFrom(self.bb, x + math.floor((self.width - w) / 2), y + math.floor((self.height - h) / 2), 0, 0, w, h)
end

function Logo:free()
    if self.bb then self.bb:free() self.bb = nil end
end

-- guess table --------------------------------------------------------------------------

local Table = UI.Board:extend {}

local SHADE = {
    yes = { bg = UI.BLACK, fg = UI.WHITE },
    close = { bg = UI.MID, fg = UI.BLACK },
    no = { bg = UI.WHITE, fg = UI.BLACK },
}

local SHORT = { ["Media & Entertainment"] = "Media", ["Food & Beverage"] = "Food & Drink",
    ["Fashion & Apparel"] = "Fashion", ["Sport & Fitness"] = "Sport", ["Cosmetics & Beauty"] = "Beauty",
    Telecommunications = "Telecom" }

--- Cells for one guess: { text, shade }.
function Brandle.cells(brand, j)
    local arrow = { later = " ▲", ["close-later"] = " ▲", earlier = " ▼", ["close-earlier"] = " ▼" }
    return {
        { brand.name, j.correct and "yes" or "no" },
        { SHORT[brand.industry] or brand.industry, j.industry and "yes" or "no" },
        { brand.country, j.country and "yes" or "no" },
        { tostring(brand.founded) .. (arrow[j.year] or ""),
          j.year == "correct" and "yes" or j.year:find("^close") and "close" or "no" },
        { brand.revenue .. (j.revenue == "higher" and " ▲" or j.revenue == "lower" and " ▼" or ""),
          j.revenue == "correct" and "yes" or "no" },
    }
end

local HEADS = { "Brand", "Industry", "Country", "Founded", "Revenue" }

function Table:setup()
    self.gap = UI.px(3)
    self.head_h = UI.px(30)
    self.row_h = math.max(UI.px(36), math.floor((self.height - self.head_h) / MAX_GUESSES) - self.gap)
    self.cell_w = math.floor((self.width - self.gap * 4) / 5)
    self.head_face = UI.fitFace({ "Industry" }, self.cell_w * 0.9, self.head_h * 0.6, { bold = true })
end

function Table:draw(bb, x, y)
    for i, h in ipairs(HEADS) do
        UI.drawText(bb, self.head_face, h, x + (i - 1) * (self.cell_w + self.gap), y, self.cell_w, self.head_h, UI.BLACK, true)
    end
    local app = self.app
    for r, id in ipairs(app.state.guesses) do
        local brand = app.by_id[id]
        if brand then
            local ry = y + self.head_h + (r - 1) * (self.row_h + self.gap)
            for i, cell in ipairs(Brandle.cells(brand, Brandle.judge(brand, app.answer))) do
                local cx = x + (i - 1) * (self.cell_w + self.gap)
                local st = SHADE[cell[2]]
                bb:paintRect(cx, ry, self.cell_w, self.row_h, st.bg)
                UI.drawBorder(bb, cx, ry, self.cell_w, self.row_h, UI.px(2), UI.BLACK)
                local f, lines = UI.fitLines(cell[1], self.cell_w * 0.9, self.row_h * 0.86, 2, { bold = i == 1, min = 7 })
                local lh = math.min(math.floor(self.row_h * 0.86 / math.max(#lines, 1)), math.floor(self.row_h / 1.6))
                local top = ry + math.floor((self.row_h - lh * #lines) / 2)
                for li, line in ipairs(lines) do
                    UI.drawText(bb, f, line, cx, top + (li - 1) * lh, self.cell_w, lh, st.fg, i == 1)
                end
            end
        end
    end
end

-- app ------------------------------------------------------------------------------------

local App = UI.FullscreenApp:extend {
    name = "brandle_app",
    help_text = [[Guess today's brand from its logo in 8 tries. The logo starts as a few big squares and gets sharper with every guess.

Type a brand and tap it to guess. Each guess shows:
Industry, Country: black = same as the answer.
Founded: black = same year, gray = within 10 years. ▲ the answer is newer, ▼ older.
Revenue: black = same band (Small, Medium, Large, Mega). ▲ the answer is bigger, ▼ smaller.]],
}

function App:setup()
    self.state = self.state or { guesses = {} }
    self.input = ""
    self.by_id = {}
    for _, b in ipairs(self.brands) do self.by_id[b.id] = b end
    if self:isOver() then self.status = self:resultText() end
end

function App:progressKey() return "brandle" end

function App:getTitle() return "Brandle" end

function App:isWon()
    local last = self.state.guesses[#self.state.guesses]
    return last ~= nil and last == self.answer.id
end

function App:isOver()
    return self:isWon() or #self.state.guesses >= MAX_GUESSES
end

function App:resultText()
    if self:isWon() then
        return string.format("Got it in %d! It's %s.", #self.state.guesses, self.answer.name)
    end
    return "It was " .. self.answer.name .. "."
end

function App:buildBody(width, height)
    local w = math.floor(width * 0.96)
    local bottom = VerticalGroup:new { align = "center" }
    if not self:isOver() then
        local tried = {}
        for _, id in ipairs(self.state.guesses) do tried[id] = true end
        local row = {}
        for _, b in ipairs(Brandle.suggest(self.brands, self.input, tried, 3)) do
            table.insert(row, { text = b.name, callback = function() self:guess(b) end })
        end
        if #row == 0 then
            table.insert(row, { text = self.input == "" and "Type a brand…" or "No match", enabled = false })
        end
        table.insert(bottom, ButtonTable:new { width = w, buttons = { row }, show_parent = self })
        table.insert(bottom, UI.span(6))
        table.insert(bottom, UI.Keyboard:new {
            width = w,
            height = UI.px(56) * 3,
            rows = {
                UI.QWERTY[1], UI.QWERTY[2],
                { "Z", "X", "C", "V", "B", "N", "M", { label = "␣", value = " " }, { label = "⌫", value = "DEL", width = 1.5 } },
            },
            on_key = function(k) self:onKey(k) end,
        })
    end
    local info = UI.text(self:isOver() and string.format("%d of %d guesses", #self.state.guesses, MAX_GUESSES)
        or string.format("Guess %d of %d", #self.state.guesses + 1, MAX_GUESSES),
        w, { face = "smallinfofont" })
    local typed = UI.text(self.input ~= "" and self.input or " ", w, { bold = true, face = "infofont" })
    local status = self:statusLine(w)
    local avail = height - bottom:getSize().h - info:getSize().h - typed:getSize().h - status:getSize().h - UI.px(24)
    local table_h = math.floor(avail * 0.55)
    local logo_h = math.max(UI.px(80), avail - table_h)
    if self.logo then self.logo:free() end
    self.logo = Logo:new { width = w, height = logo_h, app = self }
    local grid = Table:new { width = w, height = table_h, app = self }
    local top = VerticalGroup:new { align = "center", self.logo, UI.span(4), info, grid, status, typed }
    return top, bottom
end

function App:onKey(k)
    if k == "DEL" then
        self.input = self.input:sub(1, -2)
    elseif #self.input < 24 and not (k == " " and (self.input == "" or self.input:sub(-1) == " ")) then
        self.input = self.input .. (k == " " and " " or k:lower())
    end
    self:refresh()
end

function App:guess(brand)
    if self:isOver() then return end
    table.insert(self.state.guesses, brand.id)
    self.input = ""
    Store.saveProgress(self:storeKey(), self.date, self:markDone())
    self.status = self:isOver() and self:resultText() or ""
    self:refresh()
end

function App:menuItems()
    local items = { { text = "About the answer", callback = function()
        if not self:isOver() then
            return UIManager:show(InfoMessage:new { text = "Finish the puzzle first." })
        end
        local a = self.answer
        UIManager:show(InfoMessage:new { text = string.format("%s\n\n%s · %s\nFounded %d · %s revenue",
            a.name, a.industry, a.country, a.founded, a.revenue) })
    end } }
    if self:isOver() then
        table.insert(items, { text = "Copy share text", callback = function() self:copyShare() end })
    end
    return items
end

function App:copyShare()
    local y, m, d = self.date:match("^(%d+)-(%d+)-(%d+)$")
    local lines = { string.format("Brandle %s/%s/%s %s/%d", d, m, y,
        self:isWon() and #self.state.guesses or "X", MAX_GUESSES) }
    for _, id in ipairs(self.state.guesses) do
        local b = self.by_id[id]
        if b then
            local row = {}
            for i, cell in ipairs(Brandle.cells(b, Brandle.judge(b, self.answer))) do
                if i > 1 then
                    row[#row + 1] = cell[2] == "yes" and "🟩" or cell[2] == "close" and "🟨" or "⬜"
                end
            end
            lines[#lines + 1] = table.concat(row)
        end
    end
    lines[#lines + 1] = SITE .. "/brandle"
    UI.copy(table.concat(lines, "\n"))
end

function App:onExit()
    if self.logo then self.logo:free() end
    if self.logo_src then self.logo_src:free() self.logo_src = nil end
end

--- The logo as an 8-bit gray buffer on white, rendered once per size and
-- owned by the app (ImageWidget's own buffer may be cached and freed).
function App:logoSource(size)
    if self.logo_src and self.logo_src_size == size then return self.logo_src end
    if self.logo_src then self.logo_src:free() self.logo_src = nil end
    if not self.logo_path then return nil end
    local img = ImageWidget:new { file = self.logo_path, width = size, height = size, scale_factor = 0, alpha = true }
    img:getSize()
    local src = img._bb
    if src then
        local w, h = src:getWidth(), src:getHeight()
        local bb = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)
        bb:fill(Blitbuffer.COLOR_WHITE)
        local t = src:getType()
        if t == Blitbuffer.TYPE_BBRGB32 or t == Blitbuffer.TYPE_BB8A then
            bb:alphablitFrom(src, 0, 0, 0, 0, w, h)
        else
            bb:blitFrom(src, 0, 0, 0, 0, w, h)
        end
        self.logo_src, self.logo_src_size = bb, size
    end
    img:free()
    return self.logo_src
end

-- loading -------------------------------------------------------------------------

--- Brand list: cached by script-chunk URL; refetched when the site changes.
local function loadData()
    local html, code, err = Http.request { url = SITE .. "/brandle", raw = true }
    if code ~= 200 or type(html) ~= "string" then return nil, err or ("HTTP " .. tostring(code)) end
    local chunks = {}
    for path in html:gmatch('"(/_next/static/chunks/[%w%-/]+%.js)"') do
        if not chunks[path] then
            chunks[path] = true
            table.insert(chunks, path)
        end
    end
    local cached = Store.get("brandle/data")
    if type(cached) == "table" and cached.chunk and chunks[cached.chunk] and type(cached.brands) == "table" then
        return cached
    end
    -- the list sits in a shared numbered chunk; try those first
    table.sort(chunks, function(a, b)
        local na, nb = a:match("/chunks/%d") and 0 or 1, b:match("/chunks/%d") and 0 or 1
        if na ~= nb then return na < nb end
        return a < b
    end)
    for _, path in ipairs(chunks) do
        local js, c = Http.request { url = SITE .. path, raw = true }
        if c == 200 and type(js) == "string" and js:find('industry:"', 1, true) then
            local data = Brandle.parseChunk(js)
            if data then
                data.chunk = path
                Store.set("brandle/data", data)
                return data
            end
        end
    end
    return nil, "couldn't find the brand list"
end

local function logoPath(data, brand)
    local cache = DataStorage:getDataDir() .. "/cache"
    local path = string.format("%s/brandle-%d.png", cache, brand.id)
    local f = io.open(path, "rb")
    if f then f:close() return path end
    os.execute("mkdir -p '" .. cache .. "'")
    os.execute("rm -f '" .. cache .. "'/brandle-*.png")
    local rel = data.logos and data.logos[brand.domain]
    local url = rel and SITE .. rel or SITE .. "/api/logo?domain=" .. brand.domain
    if Http.download(url, path) then return path end
end

function Brandle.launch()
    local date = os.date("!%Y-%m-%d")
    local result, err, crash = UI.withBusy("Loading Brandle…", function()
        local data, e = loadData()
        if not data then return nil, e end
        local answer = Brandle.pick(data.brands, Brandle.dayIndex(date))
        return { data = data, answer = answer, logo = logoPath(data, answer) }
    end)
    if not result then return UI.error("Couldn't load Brandle.\n" .. tostring(err or crash)) end
    UIManager:show(App:new {
        date = date,
        brands = result.data.brands,
        answer = result.answer,
        logo_path = result.logo,
        state = Store.loadProgress("brandle", date),
    })
end

return Brandle
