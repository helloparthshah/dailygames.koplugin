--[[
Strands: find the theme words hidden in the letter grid, plus the spangram
(a word that spans the board from one side to the other).

Tap letters to build a word; each letter must touch the previous one
(diagonals count). Selected letters turn black and are joined by a line.
Tap the last letter again (or Submit) to check the word. Tap a letter that
isn't next to your path to start over from there.

Found theme words are shaded gray; the spangram is dark with white letters.
]]

local ButtonTable = require("ui/widget/buttontable")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local NYT = require("dailygames/nyt")
local Store = require("dailygames/store")
local UI = require("dailygames/ui")

local function cellKey(r, c)
    return r .. ":" .. c
end

local function isAdjacent(a, b)
    return math.abs(a[1] - b[1]) <= 1 and math.abs(a[2] - b[2]) <= 1 and not (a[1] == b[1] and a[2] == b[2])
end

-- board ----------------------------------------------------------------------

local Board = UI.Board:extend {}

function Board:setup()
    local app = self.app
    self.rows, self.cols = #app.board, #app.board[1]
    self.cell = math.floor(math.min(self.width / self.cols, self.height / self.rows))
    self.ox = math.floor((self.width - self.cell * self.cols) / 2)
    self.oy = math.floor((self.height - self.cell * self.rows) / 2)
    self.r = math.floor(self.cell * 0.4)
    self.face = UI.fitFace({ "W", "M" }, self.r * 1.25, self.r * 1.0, { bold = true, caps = true })
end

function Board:center(r, c)
    return self.ox + (c - 1) * self.cell + math.floor(self.cell / 2),
        self.oy + (r - 1) * self.cell + math.floor(self.cell / 2)
end

local function drawPath(self, bb, x, y, cells, base, t, color)
    for i = 2, #cells do
        local x1, y1 = self:center(cells[i - 1][1] + base, cells[i - 1][2] + base)
        local x2, y2 = self:center(cells[i][1] + base, cells[i][2] + base)
        UI.drawLine(bb, x + x1, y + y1, x + x2, y + y2, t, color)
    end
end

function Board:draw(bb, x, y)
    local app = self.app
    local marks = app:cellMarks()
    local selected = {}
    for _, p in ipairs(app.state.path) do selected[cellKey(p[1], p[2])] = true end

    -- lines first, so letters sit on top
    for _, w in ipairs(app.state.found) do
        local coords = app.coords[w]
        if coords then
            drawPath(self, bb, x, y, coords, 1, math.floor(self.r * 0.9),
                app.targets[w] == "spangram" and UI.DARK or UI.LIGHT)
        end
    end
    drawPath(self, bb, x, y, app.state.path, 0, math.floor(self.r * 0.5), UI.BLACK)

    for r = 1, self.rows do
        for c = 1, self.cols do
            local cx, cy = self:center(r, c)
            cx, cy = x + cx, y + cy
            local key = cellKey(r, c)
            local kind = selected[key] and "selected" or marks[key]
            local fg = UI.BLACK
            if kind == "selected" then
                UI.fillCircle(bb, cx, cy, self.r, UI.BLACK)
                fg = UI.WHITE
            elseif kind == "spangram" then
                UI.fillCircle(bb, cx, cy, self.r, UI.DARK)
                fg = UI.WHITE
            elseif kind == "theme" then
                UI.fillCircle(bb, cx, cy, self.r, UI.LIGHT)
            elseif kind == "hint" then
                UI.ringCircle(bb, cx, cy, self.r, UI.px(4), UI.BLACK)
            end
            UI.drawText(bb, self.face, app:letterAt(r, c), cx - self.r, cy - self.r, 2 * self.r, 2 * self.r, fg, true)
        end
    end
end

function Board:tapAt(lx, ly)
    local c = math.floor((lx - self.ox) / self.cell) + 1
    local r = math.floor((ly - self.oy) / self.cell) + 1
    if r >= 1 and r <= self.rows and c >= 1 and c <= self.cols then
        self.app:tapCell(r, c)
    end
end

-- app ------------------------------------------------------------------------

local Strands = UI.FullscreenApp:extend {
    name = "strands_app",
    help_text = [[Find the theme words hidden in the grid.

Tap letters one by one; each must touch the last (diagonals count). Selected letters turn black and are joined by a line.

Tap the last letter again, or Submit, to check the word. Tap a letter away from your path to start over.

Found words turn gray. The spangram, which crosses the whole board, turns dark. Hint circles the letters of a word you haven't found.]],
}

function Strands:setup()
    self.state = self.state or { path = {}, found = {}, hint = nil }
    self.targets = {}
    for _, w in ipairs(self.theme_words) do self.targets[w] = "theme" end
    if self.spangram ~= "" then self.targets[self.spangram] = "spangram" end
    if self:isOver() then self.status = "All words found!" end
end

function Strands:getTitle()
    return "Strands"
end

function Strands:totalWords()
    local n = 0
    for _ in pairs(self.targets) do n = n + 1 end
    return n
end

function Strands:isFound(word)
    for _, w in ipairs(self.state.found) do
        if w == word then return true end
    end
    return false
end

function Strands:isOver()
    return #self.state.found >= self:totalWords()
end

function Strands:letterAt(r, c)
    return self.board[r]:sub(c, c)
end

function Strands:pathWord()
    local letters = {}
    for _, p in ipairs(self.state.path) do
        table.insert(letters, self:letterAt(p[1], p[2]))
    end
    return table.concat(letters)
end

--- cellKey -> "theme" / "spangram" / "hint" for cells to shade.
function Strands:cellMarks()
    local marks = {}
    local function mark(word, kind)
        for _, rc in ipairs(self.coords[word] or {}) do
            marks[cellKey(rc[1] + 1, rc[2] + 1)] = kind
        end
    end
    if self.state.hint and not self:isFound(self.state.hint) then mark(self.state.hint, "hint") end
    for _, w in ipairs(self.state.found) do mark(w, self.targets[w]) end
    return marks
end

function Strands:buildBody(width, height)
    local w = math.floor(width * 0.94)
    local has_path = #self.state.path > 0
    local over = self:isOver()
    local theme = UI.text("Theme: " .. self.clue, w, { bold = true, face = "infofont" })
    local progress = UI.text(string.format("%d of %d words found", #self.state.found, self:totalWords()), w,
        { face = "smallinfofont" })
    local word = UI.text(has_path and self:pathWord() or " ", w, { bold = true, face = "infofont", size = 28 })
    local top_info = VerticalGroup:new { align = "center", theme, UI.span(2), progress }

    local buttons = ButtonTable:new {
        width = w,
        show_parent = self,
        buttons = { {
            { text = "Undo", enabled = has_path, callback = function() self:undo() end },
            { text = "Clear", enabled = has_path, callback = function() self:clearPath() end },
            { text = "Hint", enabled = not over, callback = function() self:giveHint() end },
            { text = "Submit", enabled = has_path, callback = function() self:submit() end },
        } },
    }
    local bottom = VerticalGroup:new { align = "center", self:statusLine(w), UI.span(8), buttons }
    local board_h = height - top_info:getSize().h - word:getSize().h - bottom:getSize().h - UI.px(28)
    local board = Board:new { width = w, height = board_h, app = self }
    local top = VerticalGroup:new { align = "center", top_info, UI.span(6), word, UI.span(6), board }
    return top, bottom
end

function Strands:progressKey() return "strands" end

function Strands:save()
    Store.saveProgress("strands", self.date, self:markDone())
end

function Strands:tapCell(r, c)
    if self:isOver() then return end
    local path = self.state.path
    local last = path[#path]
    if last and last[1] == r and last[2] == c then
        return self:submit() -- tapping the last letter again checks the word
    end
    for i, p in ipairs(path) do
        if p[1] == r and p[2] == c then
            -- tapping an earlier letter of the path backs up to it
            for _ = #path, i + 1, -1 do table.remove(path) end
            return self:setStatus("")
        end
    end
    if last and not isAdjacent(last, { r, c }) then
        self.state.path = { { r, c } }
    else
        table.insert(path, { r, c })
    end
    self:setStatus("")
end

function Strands:undo()
    table.remove(self.state.path)
    self:setStatus("")
end

function Strands:clearPath()
    self.state.path = {}
    self:setStatus("")
end

--- True if the current path is exactly where `word` sits on the board.
function Strands:pathMatches(word)
    local coords = self.coords[word]
    if not coords then return true end -- no coordinates in data: accept by spelling
    if #coords ~= #self.state.path then return false end
    local wanted = {}
    for _, rc in ipairs(coords) do wanted[cellKey(rc[1] + 1, rc[2] + 1)] = true end
    for _, p in ipairs(self.state.path) do
        if not wanted[cellKey(p[1], p[2])] then return false end
    end
    return true
end

function Strands:submit()
    local word = self:pathWord()
    if #word < 4 then return self:setStatus("Too short") end
    local kind = self.targets[word]
    local matches = kind and self:pathMatches(word)
    self.state.path = {}

    if kind and self:isFound(word) then
        return self:setStatus("Already found")
    elseif matches then
        table.insert(self.state.found, word)
        if self.state.hint == word then self.state.hint = nil end
        self:save()
        if self:isOver() then return self:setStatus("All words found!") end
        return self:setStatus(kind == "spangram" and ("SPANGRAM! " .. word) or ("Found " .. word))
    end
    self:setStatus(word .. " isn't a theme word")
end

--- Circles the letters of an unfound theme word (spangram last).
function Strands:giveHint()
    local order = {}
    for _, w in ipairs(self.theme_words) do table.insert(order, w) end
    if self.spangram ~= "" then table.insert(order, self.spangram) end
    for _, w in ipairs(order) do
        if not self:isFound(w) then
            self.state.hint = w
            self:save()
            if self.coords[w] then
                return self:setStatus("Hint: the circled letters spell a theme word")
            end
            return self:setStatus(string.format("Hint: %d letters, starts with %s…", #w, w:sub(1, 2)))
        end
    end
end

function Strands.launch(date)
    local data, err = UI.withBusy("Loading Strands…", function() return NYT.strands(date) end)
    if not data then
        UI.error("Couldn't load Strands.\n" .. tostring(err))
        return
    end
    UIManager:show(Strands:new {
        date = date,
        clue = data.clue,
        board = data.board,
        theme_words = data.theme_words,
        spangram = data.spangram,
        coords = data.coords,
        state = Store.loadProgress("strands", date),
    })
end

return Strands
