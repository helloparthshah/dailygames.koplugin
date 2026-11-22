--[[
Strands: find the theme words hidden in the letter grid, plus the spangram.

Tap letters to build a path; each tap must touch the previous letter
(including diagonals). Tap the last letter again to undo it, or tap a
non-adjacent letter to start a new path.

Labels: [A] selected   (A) theme word found   *A* spangram   {A} hint
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

local Strands = UI.FullscreenApp:extend {
    name = "strands_app",
}

function Strands:setup()
    self.state = self.state or {
        path = {},   -- list of {row, col} (1-based)
        found = {},  -- list of words
        hint = nil,  -- word currently hinted
    }
    self.targets = {}
    for _, w in ipairs(self.theme_words) do
        self.targets[w] = "theme"
    end
    if self.spangram ~= "" then
        self.targets[self.spangram] = "spangram"
    end
end

function Strands:getTitle()
    return "Strands · " .. self.date
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

--- Map of cellKey -> "theme" / "spangram" / "hint" for cells to decorate.
function Strands:cellMarks()
    local marks = {}
    local function mark(word, kind)
        for _, rc in ipairs(self.coords[word] or {}) do
            marks[cellKey(rc[1] + 1, rc[2] + 1)] = kind
        end
    end
    for _, w in ipairs(self.state.found) do
        mark(w, self.targets[w])
    end
    if self.state.hint and not self:isFound(self.state.hint) then
        mark(self.state.hint, "hint")
    end
    return marks
end

local LABEL = {
    selected = function(ch) return "[" .. ch .. "]" end,
    theme = function(ch) return "(" .. ch .. ")" end,
    spangram = function(ch) return "*" .. ch .. "*" end,
    hint = function(ch) return "{" .. ch .. "}" end,
}

function Strands:buildGrid(width)
    local selected = {}
    for _, p in ipairs(self.state.path) do
        selected[cellKey(p[1], p[2])] = true
    end
    local marks = self:cellMarks()

    local rows = {}
    for r, line in ipairs(self.board) do
        local row = {}
        for c = 1, #line do
            local ch = line:sub(c, c)
            local key = cellKey(r, c)
            local kind = selected[key] and "selected" or marks[key]
            table.insert(row, {
                text = kind and LABEL[kind](ch) or ch,
                callback = function() self:tapCell(r, c) end,
            })
        end
        table.insert(rows, row)
    end
    local has_path = #self.state.path > 0
    table.insert(rows, {
        { text = "Clear", enabled = has_path, callback = function() self:clearPath() end },
        { text = "Hint", enabled = not self:isOver(), callback = function() self:giveHint() end },
        { text = "Submit", enabled = has_path, callback = function() self:submit() end },
    })
    return ButtonTable:new { width = width, buttons = rows, zero_sep = true, show_parent = self }
end

function Strands:buildBody(width)
    local w = math.floor(width * 0.94)
    local current = #self.state.path > 0 and self:pathWord() or "Tap adjacent letters to spell a word"
    return VerticalGroup:new {
        align = "center",
        UI.banner({ { text = "Theme: " .. self.clue, bold = true } }, w),
        UI.span(4),
        UI.text(string.format("%d of %d words found", #self.state.found, self:totalWords()), w,
            { face = "xx_smallinfofont" }),
        UI.span(2),
        UI.text(current, w, { bold = #self.state.path > 0 }),
        UI.span(4),
        self:buildGrid(w),
        UI.span(4),
        UI.text("[A] selected  (A) found  *A* spangram  {A} hint", w, { face = "xx_smallinfofont" }),
    }
end

function Strands:save()
    Store.saveProgress("strands", self.date, self.state)
end

function Strands:tapCell(r, c)
    if self:isOver() then return end
    local path = self.state.path
    local cell = { r, c }
    local last = path[#path]

    if last and last[1] == r and last[2] == c then
        table.remove(path) -- undo last letter
    else
        for _, p in ipairs(path) do
            if p[1] == r and p[2] == c then return end -- already in path
        end
        if last and not isAdjacent(last, cell) then
            self.state.path = { cell } -- start over from here
        else
            table.insert(path, cell)
        end
    end
    self:refresh()
end

function Strands:clearPath()
    self.state.path = {}
    self:refresh()
end

--- True if the current path is exactly where `word` sits on the board.
function Strands:pathMatches(word)
    local coords = self.coords[word]
    if not coords then return true end -- no coordinates in data: accept by spelling
    if #coords ~= #self.state.path then return false end
    local wanted = {}
    for _, rc in ipairs(coords) do
        wanted[cellKey(rc[1] + 1, rc[2] + 1)] = true
    end
    for _, p in ipairs(self.state.path) do
        if not wanted[cellKey(p[1], p[2])] then return false end
    end
    return true
end

function Strands:submit()
    local word = self:pathWord()
    if #word < 4 then
        UI.notify("Too short.", 1)
        return
    end
    local kind = self.targets[word]
    local matches = kind and self:pathMatches(word)
    self.state.path = {}

    if kind and self:isFound(word) then
        UI.notify("Already found.", 1)
    elseif matches then
        table.insert(self.state.found, word)
        if self.state.hint == word then self.state.hint = nil end
        self:save()
        self:refresh()
        if self:isOver() then
            UI.notify("Strands complete!", 3)
        elseif kind == "spangram" then
            UI.notify("SPANGRAM: " .. word, 2)
        else
            UI.notify("Found " .. word, 1)
        end
        return
    else
        UI.notify("\"" .. word .. "\" is not a theme word.", 1.2)
    end
    self:refresh()
end

--- Highlights the letters of an unfound theme word (spangram last).
function Strands:giveHint()
    local order = {}
    for _, w in ipairs(self.theme_words) do table.insert(order, w) end
    if self.spangram ~= "" then table.insert(order, self.spangram) end
    for _, w in ipairs(order) do
        if not self:isFound(w) then
            self.state.hint = w
            self:save()
            self:refresh()
            if not self.coords[w] then
                UI.notify(string.format("Hint: %d letters, starts with %s…", #w, w:sub(1, 2)), 2)
            end
            return
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
