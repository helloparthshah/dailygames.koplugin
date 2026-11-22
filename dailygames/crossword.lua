--[[
Crossword (NYT Mini or Daily).

Tap a square to select it; tap it again to switch Across/Down. The current
word is shaded gray, the selected square is black. Type with the keyboard;
letters advance through the word. "Check" marks wrong letters with a black
corner triangle. Tap the clue bar to switch direction; ‹ › jump between clues.
]]

local ButtonTable = require("ui/widget/buttontable")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local Amuse = require("dailygames/amuse")
local NYT = require("dailygames/nyt")
local Store = require("dailygames/store")
local UI = require("dailygames/ui")

local Screen = UI.Screen

-- grid -----------------------------------------------------------------------

local Grid = UI.Board:extend {}

function Grid:setup()
    local app = self.app
    self.cell = math.floor(math.min(self.width / app.width, self.height / app.height))
    self.ox = math.floor((self.width - self.cell * app.width) / 2)
    self.oy = 0
    self.height = self.cell * app.height
    self.dimen.h, self.paint_rect.h = self.height, self.height
    self.letter_face = UI.fitFace({ "W", "M" }, self.cell * 0.7, self.cell * 0.55, { bold = true, caps = true })
    self.label_face = UI.fitFace({ "88" }, self.cell * 0.4, self.cell * 0.26)
end

function Grid:draw(bb, x, y)
    local app = self.app
    local st = app.state
    local in_word = {}
    local clue = app:currentClue()
    for _, idx in ipairs(clue and clue.cells or {}) do in_word[idx] = true end
    local line = math.max(1, UI.px(1))
    local s = self.cell
    for r = 1, app.height do
        for c = 1, app.width do
            local idx = (r - 1) * app.width + c
            local cell = app.cells[idx] or {}
            local cx, cy = x + self.ox + (c - 1) * s, y + self.oy + (r - 1) * s
            if not cell.answer then
                bb:paintRect(cx, cy, s, s, UI.BLACK)
            else
                local bg, fg = UI.WHITE, UI.BLACK
                if idx == st.cursor then
                    bg, fg = UI.BLACK, UI.WHITE
                elseif in_word[idx] then
                    bg = UI.LIGHT
                end
                bb:paintRect(cx, cy, s, s, bg)
                UI.drawBorder(bb, cx, cy, s + line, s + line, line, UI.MID)
                if cell.label then
                    local pad = math.max(1, math.floor(s * 0.06))
                    UI.drawTextLeft(bb, self.label_face, cell.label, cx + pad, cy + pad,
                        math.floor(s * 0.28), fg, false)
                end
                local letter = st.entries[idx]
                if letter then
                    UI.drawText(bb, self.letter_face, letter, cx, cy + math.floor(s * 0.12), s,
                        s - math.floor(s * 0.12), fg, true)
                end
                if app.wrong[idx] then
                    UI.cornerMark(bb, cx, cy, s, math.floor(s * 0.3), idx == st.cursor and UI.WHITE or UI.BLACK)
                end
            end
        end
    end
    UI.drawBorder(bb, x + self.ox, y + self.oy, s * app.width + line, s * app.height + line, UI.px(2), UI.BLACK)
end

function Grid:tapAt(lx, ly)
    local c = math.floor((lx - self.ox) / self.cell) + 1
    local r = math.floor((ly - self.oy) / self.cell) + 1
    local app = self.app
    if r >= 1 and r <= app.height and c >= 1 and c <= app.width then
        app:onCellTap((r - 1) * app.width + c)
    end
end

-- clue bar (tap to switch direction) -------------------------------------------

local ClueBar = UI.Board:extend {}

function ClueBar:setup()
    self.face = UI.fitFace({ "Mg" }, self.width, self.height * 0.36)
    self.head_face = UI.fitFace({ "Mg" }, self.width, self.height * 0.3, { bold = true })
end

function ClueBar:draw(bb, x, y)
    local app = self.app
    local clue = app:currentClue()
    bb:paintRect(x, y, self.width, self.height, UI.PALE)
    UI.drawBorder(bb, x, y, self.width, self.height, UI.px(2), UI.BLACK)
    if not clue then return end
    local pad = UI.px(10)
    local head = string.format("%s %s", clue.label, clue.dir)
    local head_h = math.floor(self.height * 0.34)
    UI.drawTextLeft(bb, self.head_face, head, x + pad, y + UI.px(4), head_h, UI.BLACK, true)
    local lines = UI.wrap2(self.face, clue.text, self.width - 2 * pad)
    local lh = math.floor((self.height - head_h - UI.px(8)) / 2)
    for i, l in ipairs(lines) do
        if i > 2 then break end
        UI.drawTextLeft(bb, self.face, l, x + pad, y + head_h + UI.px(2) + (i - 1) * lh, lh, UI.BLACK)
    end
end

function ClueBar:tapAt()
    self.app:toggleDirection()
    self.app:refresh()
end

-- app ------------------------------------------------------------------------

local Crossword = UI.FullscreenApp:extend {
    name = "crossword_app",
    help_text = [[Tap a square to select it. Tap it again (or the clue bar) to switch between Across and Down.

The selected square is black; the rest of the current word is gray. Letters move forward through the word as you type.

‹ and › jump to the previous or next clue. Check marks wrong letters with a black corner triangle; they clear when you change them.]],
}

function Crossword:setup()
    local first
    for i, c in ipairs(self.cells) do
        if c.answer then first = i; break end
    end
    self.state = self.state or { entries = {}, cursor = first or 1, direction = "Across" }
    local entries = {}
    for k, v in pairs(self.state.entries) do entries[tonumber(k)] = v end
    self.state.entries = entries
    self.wrong = {}
    if self:isSolved() then self.status = "Solved!" end
end

local TITLES = { mini = "The Mini", daily = "Daily Crossword", atlantic = "The Atlantic" }

function Crossword:getTitle()
    return (TITLES[self.kind] or "Crossword") .. " · " .. self.date
end

function Crossword:progressKey() return "crossword_" .. self.kind end

function Crossword:save(defer)
    Store.saveProgress("crossword_" .. self.kind, self.date, self.state, defer)
end

function Crossword:onExit()
    self:save()
end

-- navigation -----------------------------------------------------------------

function Crossword:isOpen(idx)
    local c = self.cells[idx]
    return c ~= nil and c.answer ~= nil
end

function Crossword:currentClueIndex()
    local cell = self.cells[self.state.cursor]
    if not cell then return nil end
    local fallback
    for _, ci in ipairs(cell.clues) do
        local clue = self.clues[ci]
        if clue and clue.dir == self.state.direction then return ci end
        fallback = fallback or ci
    end
    return fallback
end

function Crossword:currentClue()
    local ci = self:currentClueIndex()
    return ci and self.clues[ci]
end

function Crossword:toggleDirection()
    self.state.direction = self.state.direction == "Across" and "Down" or "Across"
end

function Crossword:jumpToClue(ci)
    local clue = self.clues[ci]
    if not clue or not clue.cells[1] then return end
    self.state.direction = clue.dir
    self.state.cursor = clue.cells[1]
    for _, idx in ipairs(clue.cells) do
        if not self.state.entries[idx] then
            self.state.cursor = idx
            break
        end
    end
end

function Crossword:stepClue(delta)
    local ci = self:currentClueIndex() or 1
    self:jumpToClue(((ci - 1 + delta) % #self.clues) + 1)
end

--- Moves within the current word; at the end of a word, jumps to the next clue.
function Crossword:advance()
    local clue = self:currentClue()
    if not clue then return end
    for i, idx in ipairs(clue.cells) do
        if idx == self.state.cursor then
            -- next empty square in this word, else stay at the end
            for j = i + 1, #clue.cells do
                if not self.state.entries[clue.cells[j]] then
                    self.state.cursor = clue.cells[j]
                    return
                end
            end
            if clue.cells[i + 1] then
                self.state.cursor = clue.cells[i + 1]
            elseif not self:isWordFull(clue) then
                return
            else
                self:stepClue(1)
            end
            return
        end
    end
end

function Crossword:isWordFull(clue)
    for _, idx in ipairs(clue.cells) do
        if not self.state.entries[idx] then return false end
    end
    return true
end

function Crossword:back()
    local clue = self:currentClue()
    if not clue then return end
    for i, idx in ipairs(clue.cells) do
        if idx == self.state.cursor and clue.cells[i - 1] then
            self.state.cursor = clue.cells[i - 1]
            return
        end
    end
end

-- editing --------------------------------------------------------------------

function Crossword:typeLetter(letter)
    local idx = self.state.cursor
    if not self:isOpen(idx) then return end
    self.state.entries[idx] = letter
    self.wrong[idx] = nil
    self:advance()
    self:save(true)
    if self:isSolved() then
        self:save()
        self.status = "Solved! Nice work."
    elseif self:isFull() then
        self.status = "Not quite. Try Check."
    else
        self.status = ""
    end
end

function Crossword:deleteLetter()
    local entries = self.state.entries
    if not entries[self.state.cursor] then self:back() end
    entries[self.state.cursor] = nil
    self.wrong[self.state.cursor] = nil
    self.status = ""
    self:save(true)
end

function Crossword:isFull()
    for idx, cell in ipairs(self.cells) do
        if cell.answer and not self.state.entries[idx] then return false end
    end
    return true
end

function Crossword:isSolved()
    for idx, cell in ipairs(self.cells) do
        if cell.answer and self.state.entries[idx] ~= cell.answer then return false end
    end
    return true
end

function Crossword:check()
    local wrong, empty = 0, 0
    self.wrong = {}
    for idx, cell in ipairs(self.cells) do
        if cell.answer then
            local v = self.state.entries[idx]
            if not v then
                empty = empty + 1
            elseif v ~= cell.answer then
                self.wrong[idx] = true
                wrong = wrong + 1
            end
        end
    end
    if wrong == 0 then
        self.status = empty == 0 and "All correct!" or ("No mistakes so far. " .. empty .. " to go.")
    else
        self.status = string.format("%d wrong letter%s marked", wrong, wrong == 1 and "" or "s")
    end
end

function Crossword:showClueList()
    local menu
    local items = {}
    for ci, clue in ipairs(self.clues) do
        local done = self:isWordFull(clue)
        table.insert(items, {
            text = string.format("%s%s  %s", clue.label, clue.dir == "Across" and "A" or "D", clue.text),
            mandatory = done and "✓" or nil,
            callback = function()
                UIManager:close(menu)
                self:jumpToClue(ci)
                self:refresh()
            end,
        })
    end
    menu = Menu:new {
        title = "Clues",
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        close_callback = function() UIManager:close(menu); self:refresh() end,
    }
    UIManager:show(menu)
end

function Crossword:onKey(key)
    if key == "DEL" then self:deleteLetter() else self:typeLetter(key) end
    self:refresh()
end

function Crossword:onCellTap(idx)
    if not self:isOpen(idx) then return end
    if idx == self.state.cursor then
        self:toggleDirection()
    else
        self.state.cursor = idx
    end
    self:refresh()
end

function Crossword:menuItems()
    return {
        { text = "Clue list", callback = function() self:showClueList() end },
        { text = "Check puzzle", callback = function() self:check(); self:refresh() end },
        { text = "Reveal current square", callback = function()
            local idx = self.state.cursor
            if self:isOpen(idx) then
                self.state.entries[idx] = self.cells[idx].answer
                self.wrong[idx] = nil
                self:save()
                self:refresh()
            end
        end },
        { text = "Clear all", callback = function()
            self.state.entries, self.wrong, self.status = {}, {}, ""
            self:save()
            self:refresh()
        end },
    }
end

-- layout ---------------------------------------------------------------------

function Crossword:buildBody(width, height)
    local w = math.floor(width * 0.96)
    -- Big grids (15x15, 21x21) get a slightly shorter keyboard and clue bar so
    -- the squares stay large enough to read and tap.
    local big = self.width >= 13
    local row_h = UI.px(big and 52 or 62)
    local nav = ButtonTable:new {
        width = w,
        show_parent = self,
        buttons = { {
            { text = "‹", callback = function() self:stepClue(-1); self:refresh() end },
            { text = self.state.direction, callback = function() self:toggleDirection(); self:refresh() end },
            { text = "›", callback = function() self:stepClue(1); self:refresh() end },
            { text = "Check", callback = function() self:check(); self:refresh() end },
            { text = "Clues", callback = function() self:showClueList() end },
        } },
    }
    local keyboard = UI.Keyboard:new {
        width = w,
        height = row_h * 3,
        rows = {
            UI.QWERTY[1],
            UI.QWERTY[2],
            { "Z", "X", "C", "V", "B", "N", "M", { label = "⌫", value = "DEL", width = 2 } },
        },
        on_key = function(k) self:onKey(k) end,
    }
    local bottom = VerticalGroup:new { align = "center", nav, UI.span(6), keyboard }
    local status = self:statusLine(w)
    local clue_h = UI.px(big and 80 or 96)
    local grid_h = height - bottom:getSize().h - clue_h - status:getSize().h - UI.px(24)
    local grid = Grid:new { width = w, height = grid_h, app = self }
    local clue = ClueBar:new { width = w, height = clue_h, app = self }
    local top = VerticalGroup:new { align = "center", grid, UI.span(8), clue, UI.span(4), status }
    return top, bottom
end

--- kind: "mini" / "daily" (NYT) or "atlantic" (Amuse Labs).
function Crossword.launch(kind, cookie)
    local data, err = UI.withBusy("Loading crossword…", function()
        if kind == "atlantic" then return Amuse.latest("atlantic", "atlantic") end
        return NYT.crossword(kind, cookie)
    end)
    if not data then
        local hint = kind == "daily"
            and "\n\nIf this keeps failing, the daily puzzle may need an NYT subscription: set your NYT-S cookie in Tools > Daily Games."
            or ""
        UI.error("Couldn't load the crossword.\n" .. tostring(err) .. hint)
        return
    end
    UIManager:show(Crossword:new {
        kind = kind,
        date = data.date,
        width = data.width,
        height = data.height,
        cells = data.cells,
        clues = data.clues,
        state = Store.loadProgress("crossword_" .. kind, data.date),
    })
end

return Crossword
