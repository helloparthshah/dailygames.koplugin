--[[
Marveldle (marveldle.com), MCU character mode: guess today's Marvel Cinematic
Universe character. Unlimited guesses; each one compares seven attributes:
  black cell = exact match, gray = partial (some values shared), white = none.
Clues (quote, appearances, actor, name) unlock after 5 / 8 / 12 / 15 guesses.

API (https://api.marveldle.com/api, the same one the site uses; headers
sessionId + userLanguage):
  GET /config/pick-id                         today's dateId ("11/22/2026 12:00:00 AM")
  GET /session                                -> { id } (stored and reused)
  GET /characters/audiovisual                 all characters with attributes
  GET /characters/audiovisual/guess/{id}?dateId=   -> { gender = "Exact"|"Partial"|"None", ..., isExact }
  GET /characters/audiovisual/clue/{1..4}?dateId=&language=en
]]

local ButtonTable = require("ui/widget/buttontable")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local Http = require("dailygames/http")
local Store = require("dailygames/store")
local UI = require("dailygames/ui")

local API = "https://api.marveldle.com/api"
local COLUMNS = {
    { key = "gender", label = "Gender" },
    { key = "type", label = "Type" },
    { key = "species", label = "Species" },
    { key = "powerTypes", label = "Powers" },
    { key = "origin", label = "Origin" },
    { key = "affiliations", label = "Teams" },
    { key = "appearanceTypes", label = "Seen in" },
}
local CLUES = {
    { n = 1, after = 5, label = "Quote" },
    { n = 2, after = 8, label = "Appearances" },
    { n = 3, after = 12, label = "Actor" },
    { n = 4, after = 15, label = "Name" },
}

local Marveldle = {}

local function urlencode(s)
    return (tostring(s):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
end

--- Display text for an attribute: lists joined, "GuardiansOfTheGalaxy" -> "Guardians Of The Galaxy".
local function valueText(v)
    local s = type(v) == "table" and table.concat(v, ", ") or tostring(v or "")
    return (s:gsub("(%l)(%u)", "%1 %2"))
end

--- Characters whose name or a keyword starts with the typed text.
function Marveldle.suggest(characters, typed, exclude, limit)
    typed = typed:lower()
    if typed == "" then return {} end
    local out = {}
    for _, c in ipairs(characters) do
        if not (exclude and exclude[c.id]) then
            local hit = (c.name or ""):lower():sub(1, #typed) == typed
            if not hit then
                for word in (c.name or ""):lower():gmatch("%S+") do
                    if word:sub(1, #typed) == typed then hit = true break end
                end
            end
            if not hit then
                for _, k in ipairs(c.keywords or {}) do
                    if tostring(k):lower():sub(1, #typed) == typed then hit = true break end
                end
            end
            if hit then table.insert(out, c) end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    local limited = {}
    for i = 1, math.min(limit or 3, #out) do limited[i] = out[i] end
    return limited
end

-- guess table ----------------------------------------------------------------

local Table = UI.Board:extend {}

local CELL = {
    Exact = { bg = UI.BLACK, fg = UI.WHITE },
    Partial = { bg = UI.MID, fg = UI.BLACK },
    None = { bg = UI.WHITE, fg = UI.BLACK },
}

function Table:setup()
    self.cols = #COLUMNS + 1
    self.gap = UI.px(3)
    self.head_h = UI.px(34)
    self.row_h = UI.px(80)
    self.rows = math.max(1, math.floor((self.height - self.head_h) / (self.row_h + self.gap)))
    self.cell_w = math.floor((self.width - self.gap * (self.cols - 1)) / self.cols)
    self.head_face = UI.fitFace({ "Seen in" }, self.cell_w * 0.95, self.head_h * 0.6, { bold = true })
    self.face = UI.fitFace({ "Clandestine" }, self.cell_w * 0.92, self.row_h * 0.26)
end

function Table:draw(bb, x, y)
    local app = self.app
    UI.drawText(bb, self.head_face, "Name", x, y, self.cell_w, self.head_h, UI.BLACK, true)
    for i, col in ipairs(COLUMNS) do
        UI.drawText(bb, self.head_face, col.label, x + i * (self.cell_w + self.gap), y, self.cell_w, self.head_h, UI.BLACK, true)
    end
    -- newest guess first
    local guesses = app.state.guesses
    for r = 1, math.min(self.rows, #guesses) do
        local g = guesses[#guesses - r + 1]
        local char = app.by_id[g.id] or { name = g.id }
        local ry = y + self.head_h + (r - 1) * (self.row_h + self.gap)
        local cells = { { text = char.name, sim = g.sim.isExact and "Exact" or "None" } }
        for _, col in ipairs(COLUMNS) do
            table.insert(cells, { text = valueText(char[col.key]), sim = g.sim[col.key] or "None" })
        end
        for i, cell in ipairs(cells) do
            local cx = x + (i - 1) * (self.cell_w + self.gap)
            local st = CELL[cell.sim] or CELL.None
            bb:paintRect(cx, ry, self.cell_w, self.row_h, st.bg)
            UI.drawBorder(bb, cx, ry, self.cell_w, self.row_h, UI.px(2), UI.BLACK)
            -- up to three lines, shrinking the font so long value lists fit the cell
            local f, lines = UI.fitLines(cell.text, self.cell_w * 0.9, self.row_h * 0.86, 3, { bold = i == 1, min = 7 })
            local lh = math.floor(self.row_h * 0.86 / math.max(#lines, 1))
            lh = math.min(lh, math.floor(self.row_h / 2.4))
            local top = ry + math.floor((self.row_h - lh * #lines) / 2)
            for li, line in ipairs(lines) do
                UI.drawText(bb, f, line, cx, top + (li - 1) * lh, self.cell_w, lh, st.fg, i == 1)
            end
        end
    end
end

function Table:tapAt(_, ly)
    local r = math.floor((ly - self.head_h) / (self.row_h + self.gap)) + 1
    local guesses = self.app.state.guesses
    local g = guesses[#guesses - r + 1]
    if r >= 1 and g then self.app:showGuess(g) end
end

-- app ------------------------------------------------------------------------

local App = UI.FullscreenApp:extend {
    name = "marveldle_app",
    help_text = [[Guess today's Marvel Cinematic Universe character. Guesses are unlimited.

Each guess shows how its attributes compare to the answer:
black = exact match, gray = partly right (some values shared), white = no match.

Tap a row to see that guess in full. Clues unlock after 5, 8, 12 and 15 guesses.]],
}

function App:setup()
    self.state = self.state or { guesses = {}, won = false }
    self.input = ""
    self.by_id = {}
    for _, c in ipairs(self.characters) do self.by_id[c.id] = c end
    if self.state.won then self.status = "You got it!" end
end

function App:isComplete() return self.state.won end

function App:progressKey() return "marveldle" end

function App:getTitle()
    return "Marveldle · MCU"
end

function App:buildBody(width, height)
    local w = math.floor(width * 0.96)
    local bottom = VerticalGroup:new { align = "center" }
    if not self.state.won then
        local tried = {}
        for _, g in ipairs(self.state.guesses) do tried[g.id] = true end
        local row = {}
        for _, c in ipairs(Marveldle.suggest(self.characters, self.input, tried, 3)) do
            table.insert(row, { text = c.name, callback = function() self:guess(c) end })
        end
        if #row == 0 then
            table.insert(row, { text = self.input == "" and "Type a character…" or "No match", enabled = false })
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
    local n = #self.state.guesses
    local next_clue
    for _, c in ipairs(CLUES) do
        if n < c.after then next_clue = c break end
    end
    local info = UI.text(string.format("%d guess%s%s", n, n == 1 and "" or "es",
        next_clue and string.format(" · next clue after %d", next_clue.after) or ""), w, { face = "smallinfofont" })
    local actions = ButtonTable:new { width = w, show_parent = self, buttons = { {
        { text = "Clues", callback = function() self:showClues() end },
    } } }
    local typed = UI.text(self.input ~= "" and self.input or " ", w, { bold = true, face = "infofont" })
    local status = self:statusLine(w)
    local fixed = bottom:getSize().h + info:getSize().h + actions:getSize().h + typed:getSize().h
        + status:getSize().h + UI.px(30)
    local grid = Table:new { width = w, height = math.max(UI.px(120), height - fixed), app = self }
    local top = VerticalGroup:new { align = "center", grid, UI.span(4), info, actions, status, typed }
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

function App:api(path, raw)
    return Http.request {
        url = API .. path,
        raw = raw,
        headers = { sessionId = self.session, userLanguage = "en", Origin = "https://marveldle.com" },
    }
end

local function stripHtml(s)
    s = tostring(s or ""):gsub("<br%s*/?>", "\n"):gsub("</li>", "\n"):gsub("<[^>]+>", "")
    s = s:gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function App:guess(char)
    local sim, code, err = UI.withBusy("Checking…", function()
        return self:api(string.format("/characters/audiovisual/guess/%s?dateId=%s", urlencode(char.id), urlencode(self.date_id)))
    end)
    if code == 205 then
        return self:setStatus("Today's character changed. Close and reopen the game.")
    end
    if code ~= 200 or type(sim) ~= "table" then
        return self:setStatus("Couldn't check (" .. tostring(err or code) .. ")")
    end
    table.insert(self.state.guesses, { id = char.id, sim = sim })
    self.input = ""
    if sim.isExact or sim.id == "Exact" then
        self.state.won = true
        self.status = string.format("You got it in %d! It's %s.", #self.state.guesses, char.name)
    else
        local all = true
        for _, col in ipairs(COLUMNS) do if sim[col.key] ~= "Exact" then all = false end end
        self.status = all and "All correct, but it's not this character!" or ""
    end
    Store.saveProgress("marveldle", self.date, self:markDone())
    self:refresh()
end

function App:showGuess(g)
    local char = self.by_id[g.id] or { name = g.id }
    local mark = { Exact = "✓", Partial = "~", None = "✗" }
    local lines = { char.name, "" }
    for _, col in ipairs(COLUMNS) do
        table.insert(lines, string.format("%s %s: %s", mark[g.sim[col.key]] or "✗", col.label, valueText(char[col.key])))
    end
    UIManager:show(InfoMessage:new { text = table.concat(lines, "\n") })
end

function App:showClues()
    local n = #self.state.guesses
    local lines = {}
    for _, c in ipairs(CLUES) do
        if n >= c.after or self.state.won then
            -- clues come back as a small HTML snippet
            local body, code = self:api(string.format("/characters/audiovisual/clue/%d?dateId=%s&language=en",
                c.n, urlencode(self.date_id)), true)
            local text = code == 200 and stripHtml(body) or nil
            table.insert(lines, c.label .. ": " .. ((text and text ~= "") and text or "(unavailable)"))
        else
            table.insert(lines, string.format("%s: unlocks after %d guesses", c.label, c.after))
        end
    end
    UIManager:show(InfoMessage:new { text = table.concat(lines, "\n\n") })
end

function Marveldle.launch()
    local data, err = UI.withBusy("Loading Marveldle…", function()
        local pick, code = Http.request { url = API .. "/config/pick-id", raw = true }
        if code ~= 200 or not pick or pick == "" then return nil, "couldn't get today's character" end
        local date_id = pick:gsub('^"', ""):gsub('"$', "")
        local session = Store.get("marveldle/session")
        if not session then
            local s = Http.request { url = API .. "/session", headers = { userLanguage = "en" } }
            session = type(s) == "table" and s.id
            if session then Store.set("marveldle/session", session) end
        end
        local chars = Http.request { url = API .. "/characters/audiovisual",
            headers = { sessionId = session, userLanguage = "en" } }
        if type(chars) ~= "table" or #chars == 0 then return nil, "couldn't load characters" end
        return { date_id = date_id, session = session, characters = chars }
    end)
    if not data then
        UI.error("Couldn't load Marveldle.\n" .. tostring(err))
        return
    end
    local m, d, y = data.date_id:match("(%d+)/(%d+)/(%d+)")
    local date = y and string.format("%04d-%02d-%02d", tonumber(y), tonumber(m), tonumber(d)) or os.date("!%Y-%m-%d")
    UIManager:show(App:new {
        date = date,
        date_id = data.date_id,
        session = data.session,
        characters = data.characters,
        state = Store.loadProgress("marveldle", date),
    })
end

return Marveldle
