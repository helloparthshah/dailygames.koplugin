--[[
Connections: find four groups of four. Four mistakes allowed.

Tap cards to select them (selected cards turn black). Solved groups move to
the top as banners, shaded from light (easiest) to black (trickiest).
]]

local ButtonTable = require("ui/widget/buttontable")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local NYT = require("dailygames/nyt")
local Store = require("dailygames/store")
local UI = require("dailygames/ui")

local GROUP_SIZE, MAX_MISTAKES = 4, 4

local LEVELS = {
    { name = "Easiest", bg = UI.PALE, fg = UI.BLACK },
    { name = "Medium", bg = UI.LIGHT, fg = UI.BLACK },
    { name = "Hard", bg = UI.MID, fg = UI.BLACK },
    { name = "Trickiest", bg = UI.BLACK, fg = UI.WHITE },
}

local function count(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end

-- board: solved banners on top, then the remaining cards in rows of four --------

local Board = UI.Board:extend {}

function Board:setup()
    self.gap = UI.px(8)
    self.rows = GROUP_SIZE
    self.card_h = math.floor((self.height - self.gap * (self.rows - 1)) / self.rows)
    self.card_w = math.floor((self.width - self.gap * (GROUP_SIZE - 1)) / GROUP_SIZE)
    self.title_face = UI.fitFace({ "MMMMMMMMMMMMMMMMMMMM" }, self.width * 0.9, self.card_h * 0.32, { bold = true })
    self.words_face = UI.fitFace({ "MMMMMMMMMMMMMMMMMMMMMMMMM" }, self.width * 0.9, self.card_h * 0.26)
    -- One face for every card, big enough for short words, small enough that
    -- every word fits in at most two lines.
    local inner_w, inner_h = self.card_w * 0.88, self.card_h * 0.34
    local base = UI.fitFace({ "MMMMM" }, inner_w, inner_h, { bold = true })
    local lines = { "MMMMM" }
    for _, cat in ipairs(self.app.categories) do
        for _, w in ipairs(cat.words) do
            for _, line in ipairs(UI.wrap2(base, w, inner_w, true)) do table.insert(lines, line) end
        end
    end
    self.card_face = UI.fitFace(lines, inner_w, inner_h, { bold = true })
end

function Board:cardRect(i)
    local solved = #self.app.state.solved
    local row = solved + math.floor((i - 1) / GROUP_SIZE)
    local col = (i - 1) % GROUP_SIZE
    return col * (self.card_w + self.gap), row * (self.card_h + self.gap), self.card_w, self.card_h
end

function Board:draw(bb, x, y)
    local app = self.app
    local st = app.state
    -- solved banners
    for r, entry in ipairs(st.solved) do
        local cat = app.by_title[entry.title]
        local style = LEVELS[cat.level] or LEVELS[1]
        local by = y + (r - 1) * (self.card_h + self.gap)
        bb:paintRect(x, by, self.width, self.card_h, style.bg)
        UI.drawBorder(bb, x, by, self.width, self.card_h, UI.px(2), UI.BLACK)
        local half = math.floor(self.card_h / 2)
        UI.drawText(bb, self.title_face, cat.title:upper(), x, by + UI.px(4), self.width, half, style.fg, true)
        UI.drawText(bb, self.words_face, table.concat(cat.words, ", "), x, by + half - UI.px(4), self.width, half, style.fg)
    end
    -- cards
    local inner_w = self.card_w * 0.88
    for i, word in ipairs(st.remaining) do
        local cx, cy, cw, ch = self:cardRect(i)
        cx, cy = x + cx, y + cy
        local selected = st.selected[word]
        bb:paintRect(cx, cy, cw, ch, selected and UI.BLACK or UI.PALE)
        UI.drawBorder(bb, cx, cy, cw, ch, UI.px(2), UI.BLACK)
        local lines = UI.wrap2(self.card_face, word, inner_w, true)
        local fg = selected and UI.WHITE or UI.BLACK
        if #lines == 1 then
            UI.drawText(bb, self.card_face, word, cx, cy, cw, ch, fg, true)
        else
            local lh = math.floor(ch * 0.36)
            local top = cy + math.floor((ch - 2 * lh) / 2)
            UI.drawText(bb, self.card_face, lines[1], cx, top, cw, lh, fg, true)
            UI.drawText(bb, self.card_face, lines[2], cx, top + lh, cw, lh, fg, true)
        end
    end
end

function Board:tapAt(lx, ly)
    for i, word in ipairs(self.app.state.remaining) do
        local cx, cy, cw, ch = self:cardRect(i)
        if lx >= cx and lx < cx + cw + self.gap and ly >= cy and ly < cy + ch + self.gap then
            self.app:toggle(word)
            return
        end
    end
end

-- app ------------------------------------------------------------------------

local Connections = UI.FullscreenApp:extend {
    name = "connections_app",
    help_text = [[Find groups of four words that share something.

Tap four words to select them (they turn black), then tap Submit.
Solved groups move to the top, shaded from light (easiest) to black (trickiest).

You can make 4 mistakes. "One away" means three of your four are right.]],
}

function Connections:setup()
    self.by_title = {}
    for _, cat in ipairs(self.categories) do
        self.by_title[cat.title] = cat
    end
    self.state = self.state or {
        remaining = { unpack(self.board) }, -- words still on the board, in display order
        selected = {},          -- word -> true
        solved = {},            -- list of { title = ..., revealed = bool }
        mistakes = 0,
        guesses = {},           -- sorted-word keys already tried
    }
    if self:isOver() then self.status = self:resultText() end
end

function Connections:getTitle()
    return "Connections" .. (self.number and (" #" .. self.number) or "")
end

function Connections:isOver()
    return #self.state.remaining == 0 or self.state.mistakes >= MAX_MISTAKES
end

function Connections:resultText()
    if self.state.mistakes >= MAX_MISTAKES then
        return "Out of mistakes. Here are the groups."
    end
    local m = self.state.mistakes
    return m == 0 and "Perfect! No mistakes." or string.format("Solved with %d mistake%s.", m, m == 1 and "" or "s")
end

function Connections:mistakesText()
    local left = MAX_MISTAKES - self.state.mistakes
    return "Mistakes left: " .. string.rep("●", left) .. string.rep("○", self.state.mistakes)
end

function Connections:buildBody(width, height)
    local w = math.floor(width * 0.94)
    local st = self.state
    local n = count(st.selected)
    local over = self:isOver()
    local buttons = ButtonTable:new {
        width = w,
        show_parent = self,
        buttons = { {
            { text = "Shuffle", enabled = not over, callback = function() self:shuffle() end },
            { text = "Deselect", enabled = n > 0 and not over, callback = function() st.selected = {}; self:setStatus("") end },
            { text = string.format("Submit (%d/4)", n), enabled = n == GROUP_SIZE and not over,
              callback = function() self:submit() end },
        } },
    }
    local mistakes = UI.text(self:mistakesText(), w, { face = "infofont" })
    local status = self:statusLine(w)
    local bottom = VerticalGroup:new { align = "center", status, UI.span(4), mistakes, UI.span(8), buttons }
    local board_h = math.min(height - bottom:getSize().h - UI.px(16), w * 0.95)
    local board = Board:new { width = w, height = board_h, app = self }
    return board, bottom
end

function Connections:progressKey() return "connections" end

function Connections:save()
    Store.saveProgress("connections", self.date, self.state)
end

function Connections:toggle(word)
    if self:isOver() then return end
    local sel = self.state.selected
    if sel[word] then
        sel[word] = nil
    elseif count(sel) < GROUP_SIZE then
        sel[word] = true
    else
        return self:setStatus("Four already selected. Submit or deselect.")
    end
    self:setStatus("")
end

function Connections:shuffle()
    local w = self.state.remaining
    for i = #w, 2, -1 do
        local j = math.random(i)
        w[i], w[j] = w[j], w[i]
    end
    self:save()
    self:setStatus("")
end

function Connections:removeFromBoard(words)
    local drop = {}
    for _, w in ipairs(words) do drop[w] = true end
    local kept = {}
    for _, w in ipairs(self.state.remaining) do
        if not drop[w] then table.insert(kept, w) end
    end
    self.state.remaining = kept
end

function Connections:submit()
    local st = self.state
    if count(st.selected) ~= GROUP_SIZE or self:isOver() then return end

    local picked = {}
    for w in pairs(st.selected) do table.insert(picked, w) end
    table.sort(picked)
    local key = table.concat(picked, "|")
    for _, g in ipairs(st.guesses) do
        if g == key then return self:setStatus("Already guessed!") end
    end
    table.insert(st.guesses, key)

    local best = 0
    for _, cat in ipairs(self.categories) do
        local hits = 0
        for _, w in ipairs(cat.words) do
            if st.selected[w] then hits = hits + 1 end
        end
        if hits == GROUP_SIZE then
            table.insert(st.solved, { title = cat.title })
            self:removeFromBoard(cat.words)
            st.selected = {}
            self:save()
            return self:setStatus(#st.remaining == 0 and self:resultText() or ("Solved: " .. cat.title))
        end
        best = math.max(best, hits)
    end

    st.mistakes = st.mistakes + 1
    st.selected = {}
    if st.mistakes >= MAX_MISTAKES then
        self:revealRest()
        self:save()
        return self:setStatus(self:resultText())
    end
    self:save()
    self:setStatus(best == GROUP_SIZE - 1 and "One away…" or "Not a group.")
end

function Connections:revealRest()
    local done = {}
    for _, e in ipairs(self.state.solved) do done[e.title] = true end
    for _, cat in ipairs(self.categories) do
        if not done[cat.title] then
            table.insert(self.state.solved, { title = cat.title, revealed = true })
        end
    end
    self.state.remaining = {}
end

function Connections.launch(date)
    local data, err = UI.withBusy("Loading Connections…", function() return NYT.connections(date) end)
    if not data then
        UI.error("Couldn't load Connections.\n" .. tostring(err))
        return
    end
    UIManager:show(Connections:new {
        date = date,
        number = data.number,
        categories = data.categories,
        board = data.board,
        state = Store.loadProgress("connections", date),
    })
end

return Connections
