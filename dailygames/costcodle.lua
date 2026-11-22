--[[
Costcodle (costcodle.com): guess the price of today's Costco item in 6 tries.

Each guess says Higher or Lower and is shaded by how close it was:
  black  = within 5% (you win)
  gray   = within 25% ("close")
  white  = further off
Type the price with the keypad and tap Enter.

Data: https://costcodle.com/games.json, the same catalog the web game uses
(open source: github.com/KermWasTaken/costcodle). Game numbers and the
day -> product mapping follow its scripts/main.js and scripts/daily-ids.js.
]]

local DataStorage = require("datastorage")
local ImageWidget = require("ui/widget/imagewidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local Http = require("dailygames/http")
local Store = require("dailygames/store")
local UI = require("dailygames/ui")

local MAX_GUESSES = 6
local WIN_PCT, CLOSE_PCT = 5, 25
local EPOCH = os.time { year = 2023, month = 9, day = 21, hour = 12 }
local CHECKOUT_LAUNCH_GAME = 1148

local Costcodle = {}

--- Game number for a local date (matches getGameNumber in the web app).
function Costcodle.gameNumber(date)
    local y, m, d = date:match("^(%d+)-(%d+)-(%d+)$")
    local t = os.time { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
    return math.floor((t - EPOCH) / 86400 + 0.5) + 2
end

--- Catalog id for a game number (matches classicProductId in daily-ids.js).
function Costcodle.productId(n)
    if n < CHECKOUT_LAUNCH_GAME then return n end
    return CHECKOUT_LAUNCH_GAME + (n - CHECKOUT_LAUNCH_GAME) * 6
end

local function parsePrice(s)
    return tonumber((tostring(s or ""):gsub("[^%d%.]", "")))
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

local function money(v)
    return string.format("$%.2f", v)
end

--- Feedback for a guess: { pct, closeness = "win"|"near"|"far", direction = "higher"|"lower"|nil }
function Costcodle.judge(guess, price)
    local pct = (guess - price) / price * 100
    local r = { pct = pct }
    if math.abs(pct) <= WIN_PCT then
        r.closeness = "win"
    else
        r.closeness = math.abs(pct) <= CLOSE_PCT and "near" or "far"
        r.direction = pct < 0 and "higher" or "lower"
    end
    return r
end

-- guess list -----------------------------------------------------------------

local Guesses = UI.Board:extend {}

function Guesses:setup()
    self.gap = UI.px(6)
    self.row_h = math.floor((self.height - self.gap * (MAX_GUESSES - 1)) / MAX_GUESSES)
    self.face = UI.fitFace({ "$000.00   ↑ Higher  · close" }, self.width * 0.9, self.row_h * 0.6, { bold = true })
end

local ROW = {
    win = { bg = UI.BLACK, fg = UI.WHITE },
    near = { bg = UI.MID, fg = UI.BLACK },
    far = { bg = UI.WHITE, fg = UI.BLACK },
}

function Guesses:draw(bb, x, y)
    local app = self.app
    for i = 1, MAX_GUESSES do
        local ry = y + (i - 1) * (self.row_h + self.gap)
        local g = app.state.guesses[i]
        if g then
            local j = Costcodle.judge(g, app.price)
            local st = ROW[j.closeness]
            bb:paintRect(x, ry, self.width, self.row_h, st.bg)
            UI.drawBorder(bb, x, ry, self.width, self.row_h, UI.px(2), UI.BLACK)
            local text = money(g)
            if j.direction then
                text = text .. "   " .. (j.direction == "higher" and "↑ Higher" or "↓ Lower")
                    .. (j.closeness == "near" and "  · close" or "")
            else
                text = text .. "   ✓ Got it!"
            end
            UI.drawText(bb, self.face, text, x, ry, self.width, self.row_h, st.fg, true)
        elseif i == #app.state.guesses + 1 and not app:isOver() then
            UI.drawBorder(bb, x, ry, self.width, self.row_h, UI.px(4), UI.BLACK)
            local typed = app.input ~= "" and ("$" .. app.input) or "Type a price"
            UI.drawText(bb, self.face, typed, x, ry, self.width, self.row_h,
                app.input ~= "" and UI.BLACK or UI.MID, app.input ~= "")
        else
            UI.drawBorder(bb, x, ry, self.width, self.row_h, UI.px(2), UI.LIGHT)
        end
    end
end

-- app ------------------------------------------------------------------------

local App = UI.FullscreenApp:extend {
    name = "costcodle_app",
    help_text = [[Guess the price of today's Costco item. You have 6 guesses.

Each guess tells you to go Higher or Lower.
Gray row: within 25% ("close").
Black row: within 5%, you win!

Type the price with the keypad and tap Enter.]],
}

function App:setup()
    self.state = self.state or { guesses = {} }
    self.input = ""
    if self:isOver() then self.status = self:resultText() end
end

function App:getTitle()
    return "Costcodle #" .. tostring(self.number)
end

function App:isWon()
    local last = self.state.guesses[#self.state.guesses]
    return last ~= nil and Costcodle.judge(last, self.price).closeness == "win"
end

function App:isOver()
    return self:isWon() or #self.state.guesses >= MAX_GUESSES
end

function App:resultText()
    if self:isWon() then
        return string.format("Got it in %d! Price: %s", #self.state.guesses, money(self.price))
    end
    return "The price was " .. money(self.price)
end

function App:buildBody(width, height)
    local w = math.floor(width * 0.94)
    local keypad = UI.Keyboard:new {
        width = w,
        height = UI.px(70) * 3,
        min_units = 6,
        rows = {
            { "1", "2", "3", "4", "5", { label = "⌫", value = "DEL", width = 1.5 } },
            { "6", "7", "8", "9", "0", { label = ".", value = "." } },
            { { label = "Enter", value = "ENTER", width = 6.5 } },
        },
        enabled = not self:isOver(),
        on_key = function(k) self:onKey(k) end,
    }
    local name = UI.text(self.item.name or "", w, { bold = true, face = "infofont" })
    local status = self:statusLine(w)
    local guesses_h = math.floor(height * 0.34)
    local guesses = Guesses:new { width = w, height = guesses_h, app = self }
    local fixed = keypad:getSize().h + name:getSize().h + guesses_h + status:getSize().h + UI.px(40)
    local img_h = math.max(UI.px(80), height - fixed)
    local top = VerticalGroup:new { align = "center" }
    if self.image_path then
        table.insert(top, ImageWidget:new {
            file = self.image_path,
            width = w,
            height = img_h,
            scale_factor = 0, -- fit inside, keep aspect ratio
        })
    else
        table.insert(top, UI.text("(no photo)", w))
    end
    table.insert(top, UI.span(4))
    table.insert(top, name)
    table.insert(top, UI.span(8))
    table.insert(top, guesses)
    table.insert(top, UI.span(4))
    table.insert(top, status)
    return top, keypad
end

function App:menuItems()
    if not self:isOver() then return {} end
    return { { text = "Copy share text", callback = function()
        local lines = { string.format("Costcodle #%s %s/6", tostring(self.number),
            self:isWon() and #self.state.guesses or "X") }
        for _, g in ipairs(self.state.guesses) do
            local j = Costcodle.judge(g, self.price)
            table.insert(lines, (j.closeness == "win" and "✅" or j.closeness == "near" and "🟨" or "🟥")
                .. (j.direction == "higher" and "⬆️" or j.direction == "lower" and "⬇️" or ""))
        end
        table.insert(lines, "https://costcodle.com")
        UI.copy(table.concat(lines, "\n"))
    end } }
end

function App:onKey(k)
    if self:isOver() then return end
    if k == "DEL" then
        self.input = self.input:sub(1, -2)
    elseif k == "ENTER" then
        local v = tonumber(self.input)
        if not v or v <= 0 then return self:setStatus("Type a price first") end
        table.insert(self.state.guesses, v)
        self.input = ""
        Store.saveProgress("costcodle", self.date, self.state)
        self.status = self:isOver() and self:resultText() or ""
    else
        if k == "." and self.input:find("%.") then return end
        if self.input:match("%.%d%d$") or #self.input >= 7 then return end
        self.input = self.input .. k
        self.status = ""
    end
    self:refresh()
end

function Costcodle.launch(date)
    local number = Costcodle.gameNumber(date)
    local id = Costcodle.productId(number)
    local cache = DataStorage:getDataDir() .. "/cache"
    local image_path = string.format("%s/costcodle-%d.jpg", cache, id)

    local item, err = UI.withBusy("Loading Costcodle…", function()
        local catalog, e = Http.getJson("https://costcodle.com/games.json")
        if not catalog then return nil, e end
        local entry = catalog["game-" .. id]
        if type(entry) ~= "table" or not parsePrice(entry.price) then
            return nil, "no item for game " .. number
        end
        if entry.image and not exists(image_path) then
            os.execute("mkdir -p '" .. cache .. "'")
            Http.download(entry.image, image_path)
        end
        return entry
    end)
    if not item then
        UI.error("Couldn't load Costcodle.\n" .. tostring(err))
        return
    end
    UIManager:show(App:new {
        date = date,
        number = number,
        item = item,
        price = parsePrice(item.price),
        image_path = exists(image_path) and image_path or nil,
        state = Store.loadProgress("costcodle", date),
    })
end

return Costcodle
