--[[
Crossword (NYT Mini or Daily).

Tap a square to move there; tap it again to switch Across/Down.
Arrow keys move between squares (the first press in a new direction just
switches direction, like the NYT app). Letters auto-advance through the word.
]]

local ButtonTable = require("ui/widget/buttontable")
local ConfirmBox = require("ui/widget/confirmbox")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local NYT = require("dailygames/nyt")
local Store = require("dailygames/store")
local UI = require("dailygames/ui")

local Color = UI.Color
local Screen = UI.Screen

local LETTER_ROWS = {
    { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
    { "A", "S", "D", "F", "G", "H", "J", "K", "L" },
    { "Z", "X", "C", "V", "B", "N", "M", "DEL" },
}

-- A tappable grid square.
local Cell = InputContainer:extend {
    idx = nil,
    size = nil,
    on_tap = nil,
}

function Cell:init()
    self.dimen = Geom:new { x = 0, y = 0, w = self.size, h = self.size }
    self.ges_events = {
        Tap = { GestureRange:new { ges = "tap", range = function() return self.dimen end } },
    }
end

function Cell:onTap()
    if self.on_tap then self.on_tap(self.idx) end
    return true
end

local Crossword = UI.FullscreenApp:extend {
    name = "crossword_app",
}

function Crossword:setup()
    local first
    for i, c in ipairs(self.cells) do
        if c.answer then first = i; break end
    end
    self.state = self.state or { entries = {}, cursor = first or 1, direction = "Across" }
    -- LuaSettings round-trips numeric keys as numbers, but be safe with strings.
    local entries = {}
    for k, v in pairs(self.state.entries) do entries[tonumber(k)] = v end
    self.state.entries = entries
end

function Crossword:getTitle()
    return (self.kind == "mini" and "Mini Crossword" or "Daily Crossword") .. " · " .. self.date
end

function Crossword:storeKey()
    return "crossword_" .. self.kind
end

function Crossword:save(defer)
    Store.saveProgress(self:storeKey(), self.date, self.state, defer)
end

function Crossword:onExit()
    self:save()
end

-- navigation -----------------------------------------------------------------

function Crossword:isOpen(idx)
    local c = self.cells[idx]
    return c ~= nil and c.answer ~= nil
end

--- Clue index for the cursor in the current direction (falls back to the other one).
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

function Crossword:move(dr, dc)
    local dir = (dc ~= 0) and "Across" or "Down"
    if self.state.direction ~= dir then
        self.state.direction = dir
        return
    end
    local w, h = self.width, self.height
    local r = math.floor((self.state.cursor - 1) / w)
    local c = (self.state.cursor - 1) % w
    while true do
        r, c = r + dr, c + dc
        if r < 0 or r >= h or c < 0 or c >= w then return end
        local idx = r * w + c + 1
        if self:isOpen(idx) then
            self.state.cursor = idx
            return
        end
    end
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

--- Moves within the current word by `delta` squares (stays put at the ends).
function Crossword:stepInWord(delta)
    local clue = self:currentClue()
    if not clue then return end
    for i, idx in ipairs(clue.cells) do
        if idx == self.state.cursor then
            local nxt = clue.cells[i + delta]
            if nxt then self.state.cursor = nxt end
            return
        end
    end
end

-- editing --------------------------------------------------------------------

function Crossword:typeLetter(letter)
    if not self:isOpen(self.state.cursor) then return end
    self.state.entries[self.state.cursor] = letter
    self:stepInWord(1)
    self:save(true)
    if self:isSolved() then
        self:save()
        UI.notify("Solved! Nice work.", 3)
    end
end

function Crossword:deleteLetter()
    local entries = self.state.entries
    if entries[self.state.cursor] then
        entries[self.state.cursor] = nil
    else
        self:stepInWord(-1)
        entries[self.state.cursor] = nil
    end
    self:save(true)
end

function Crossword:isSolved()
    for idx, cell in ipairs(self.cells) do
        if cell.answer and self.state.entries[idx] ~= cell.answer then
            return false
        end
    end
    return true
end

function Crossword:check()
    local wrong, empty = {}, 0
    for idx, cell in ipairs(self.cells) do
        if cell.answer then
            local v = self.state.entries[idx]
            if not v then
                empty = empty + 1
            elseif v ~= cell.answer then
                table.insert(wrong, idx)
            end
        end
    end
    if #wrong == 0 then
        UI.notify(empty == 0 and "All correct!" or ("No mistakes so far. " .. empty .. " squares left."), 2)
        return
    end
    UIManager:show(ConfirmBox:new {
        text = string.format("%d wrong letter%s. Clear them?", #wrong, #wrong == 1 and "" or "s"),
        ok_text = "Clear",
        ok_callback = function()
            for _, idx in ipairs(wrong) do self.state.entries[idx] = nil end
            self:save()
            self:refresh()
        end,
    })
end

function Crossword:showClueList()
    local menu
    local items = {}
    for ci, clue in ipairs(self.clues) do
        table.insert(items, {
            text = string.format("%s%s. %s", clue.label, clue.dir == "Across" and "A" or "D", clue.text),
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
    }
    UIManager:show(menu)
end

function Crossword:onAction(action)
    if action == "LEFT" then self:move(0, -1)
    elseif action == "RIGHT" then self:move(0, 1)
    elseif action == "UP" then self:move(-1, 0)
    elseif action == "DOWN" then self:move(1, 0)
    elseif action == "TOGGLE" then
        self.state.direction = self.state.direction == "Across" and "Down" or "Across"
    elseif action == "PREV" then self:stepClue(-1)
    elseif action == "NEXT" then self:stepClue(1)
    elseif action == "CLUES" then return self:showClueList()
    elseif action == "CHECK" then return self:check()
    elseif action == "DEL" then self:deleteLetter()
    else self:typeLetter(action)
    end
    self:refresh()
end

function Crossword:onCellTap(idx)
    if not self:isOpen(idx) then return end
    if idx == self.state.cursor then
        self.state.direction = self.state.direction == "Across" and "Down" or "Across"
    else
        self.state.cursor = idx
    end
    self:refresh()
end

-- rendering ------------------------------------------------------------------

function Crossword:buildGrid(cell_size)
    local in_word = {}
    local clue = self:currentClue()
    for _, idx in ipairs(clue and clue.cells or {}) do in_word[idx] = true end

    local grid = VerticalGroup:new { align = "center" }
    for r = 1, self.height do
        local row = HorizontalGroup:new { align = "center" }
        for c = 1, self.width do
            local idx = (r - 1) * self.width + c
            local cell = self.cells[idx] or {}
            local tile
            if not cell.answer then
                tile = UI.tile { size = cell_size, bg = Color.COLOR_BLACK, border_color = Color.COLOR_BLACK }
            else
                local bg, fg, border = Color.COLOR_WHITE, Color.COLOR_BLACK, Size.border.thin
                if idx == self.state.cursor then
                    bg, fg, border = Color.COLOR_DARK_GRAY, Color.COLOR_WHITE, Size.border.thick
                elseif in_word[idx] then
                    bg = Color.COLOR_LIGHT_GRAY
                end
                tile = UI.tile {
                    size = cell_size, text = self.state.entries[idx], label = cell.label,
                    bg = bg, fg = fg, border = border, bold = true, font_ratio = 0.55,
                }
            end
            table.insert(row, Cell:new {
                idx = idx, size = cell_size,
                on_tap = function(i) self:onCellTap(i) end,
                tile,
            })
        end
        table.insert(grid, row)
    end
    return grid
end

function Crossword:buildKeyboard(width)
    local function btn(text, action)
        return { text = text, callback = function() self:onAction(action) end }
    end
    local rows = {
        { btn("◀", "LEFT"), btn("▲", "UP"), btn("▼", "DOWN"), btn("▶", "RIGHT"),
          btn(self.state.direction == "Across" and "Across" or "Down", "TOGGLE") },
        { btn("‹ Prev", "PREV"), btn("Clues", "CLUES"), btn("Check", "CHECK"), btn("Next ›", "NEXT") },
    }
    for _, letters in ipairs(LETTER_ROWS) do
        local row = {}
        for _, k in ipairs(letters) do table.insert(row, btn(k, k)) end
        table.insert(rows, row)
    end
    return ButtonTable:new { width = width, buttons = rows, zero_sep = true, show_parent = self }
end

function Crossword:buildBody(width, height)
    local cell_size = math.floor(math.min((width * 0.92) / self.width, (height * 0.42) / self.height))
    local clue = self:currentClue()
    local clue_text = clue and string.format("%s%s  %s", clue.label, clue.dir == "Across" and "A" or "D", clue.text)
        or "Tap a square"
    local w = math.floor(width * 0.95)
    return VerticalGroup:new {
        align = "center",
        self:buildGrid(cell_size),
        UI.span(6),
        UI.banner({ { text = clue_text } }, w),
        UI.span(6),
        self:buildKeyboard(w),
    }
end

function Crossword.launch(kind, cookie)
    local data, err = UI.withBusy("Loading crossword…", function() return NYT.crossword(kind, cookie) end)
    if not data then
        local hint = kind == "daily"
            and "\n\nThe daily crossword needs an NYT subscription. Set your NYT-S cookie in Tools > Daily Games."
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
