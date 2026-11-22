--[[
Wordle: six tries to guess a five-letter word.

Tiles:  black = right letter, right spot
        gray  = in the word, wrong spot
        white = not in the word
]]

local ButtonTable = require("ui/widget/buttontable")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local NYT = require("dailygames/nyt")
local Store = require("dailygames/store")
local UI = require("dailygames/ui")

local Color = UI.Color
local WORD_LEN, MAX_GUESSES = 5, 6

local KEYBOARD = {
    { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
    { "A", "S", "D", "F", "G", "H", "J", "K", "L" },
    { "DEL", "Z", "X", "C", "V", "B", "N", "M", "ENTER" },
}

local RANK = { absent = 1, present = 2, correct = 3 }

--- Two-pass evaluation so repeated letters are scored like NYT does.
local function evaluate(guess, solution)
    local result, remaining = {}, {}
    for i = 1, WORD_LEN do
        result[i] = "absent"
        local ch = solution:sub(i, i)
        remaining[ch] = (remaining[ch] or 0) + 1
    end
    for i = 1, WORD_LEN do
        local ch = guess:sub(i, i)
        if ch == solution:sub(i, i) then
            result[i] = "correct"
            remaining[ch] = remaining[ch] - 1
        end
    end
    for i = 1, WORD_LEN do
        local ch = guess:sub(i, i)
        if result[i] ~= "correct" and (remaining[ch] or 0) > 0 then
            result[i] = "present"
            remaining[ch] = remaining[ch] - 1
        end
    end
    return result
end

local TILE_STYLE = {
    correct = { bg = Color.COLOR_BLACK, fg = Color.COLOR_WHITE, border_color = Color.COLOR_BLACK },
    present = { bg = Color.COLOR_LIGHT_GRAY, fg = Color.COLOR_BLACK, border_color = Color.COLOR_BLACK },
    absent = { bg = Color.COLOR_WHITE, fg = Color.COLOR_DARK_GRAY, border_color = Color.COLOR_GRAY },
    empty = { bg = Color.COLOR_WHITE, fg = Color.COLOR_BLACK, border_color = Color.COLOR_GRAY },
    active = { bg = Color.COLOR_WHITE, fg = Color.COLOR_BLACK, border_color = Color.COLOR_BLACK },
}

local KEY_LABEL = {
    correct = function(k) return "■" .. k end,
    present = function(k) return "[" .. k .. "]" end,
    absent = function(k) return "·" .. k .. "·" end,
}

local Wordle = UI.FullscreenApp:extend {
    name = "wordle_app",
}

function Wordle:setup()
    self.state = self.state or { guesses = {}, current = "" }
end

function Wordle:getTitle()
    return "Wordle · " .. self.date
end

function Wordle:isWon()
    return self.state.guesses[#self.state.guesses] == self.solution
end

function Wordle:isOver()
    return self:isWon() or #self.state.guesses >= MAX_GUESSES
end

function Wordle:keyStates()
    local states = {}
    for _, guess in ipairs(self.state.guesses) do
        local eval = evaluate(guess, self.solution)
        for i = 1, WORD_LEN do
            local ch = guess:sub(i, i)
            if not states[ch] or RANK[eval[i]] > RANK[states[ch]] then
                states[ch] = eval[i]
            end
        end
    end
    return states
end

function Wordle:buildBoard(tile_size)
    local board = VerticalGroup:new { align = "center" }
    local active_row = #self.state.guesses + 1
    for r = 1, MAX_GUESSES do
        local guess = self.state.guesses[r]
        local eval = guess and evaluate(guess, self.solution)
        local row = HorizontalGroup:new { align = "center" }
        for c = 1, WORD_LEN do
            local text, style, border = " ", TILE_STYLE.empty, Size.border.thin
            if guess then
                text, style, border = guess:sub(c, c), TILE_STYLE[eval[c]], Size.border.thick
            elseif r == active_row and not self:isOver() then
                text, style, border = self.state.current:sub(c, c), TILE_STYLE.active, Size.border.thick
            end
            table.insert(row, UI.tile {
                size = tile_size, text = text, bold = true, border = border,
                bg = style.bg, fg = style.fg, border_color = style.border_color,
            })
            if c < WORD_LEN then
                table.insert(row, UI.hspan(3))
            end
        end
        table.insert(board, row)
        table.insert(board, UI.span(3))
    end
    return board
end

function Wordle:buildKeyboard(width)
    local states = self:keyStates()
    local rows = {}
    for _, key_row in ipairs(KEYBOARD) do
        local row = {}
        for _, key in ipairs(key_row) do
            local label = key
            if #key == 1 and states[key] then
                label = KEY_LABEL[states[key]](key)
            end
            table.insert(row, {
                text = label,
                enabled = not self:isOver(),
                callback = function() self:onKey(key) end,
            })
        end
        table.insert(rows, row)
    end
    return ButtonTable:new {
        width = width,
        buttons = rows,
        zero_sep = true,
        show_parent = self,
    }
end

function Wordle:statusText()
    local n = #self.state.guesses
    if self:isWon() then
        return string.format("Solved in %d/%d!", n, MAX_GUESSES)
    elseif self:isOver() then
        return "Out of guesses. The word was " .. self.solution
    end
    return string.format("Guess %d of %d", n + 1, MAX_GUESSES)
end

function Wordle:buildBody(width, height)
    local tile_size = math.floor(math.min(width / 7, height / 13))
    return VerticalGroup:new {
        align = "center",
        UI.text("Black: right spot  ·  Gray: wrong spot  ·  White: not in word", width * 0.92,
            { face = "xx_smallinfofont" }),
        UI.span(6),
        self:buildBoard(tile_size),
        UI.span(4),
        UI.text(self:statusText(), width * 0.92, { bold = true }),
        UI.span(6),
        self:buildKeyboard(math.floor(width * 0.96)),
    }
end

function Wordle:save()
    Store.saveProgress("wordle", self.date, self.state)
end

function Wordle:onKey(key)
    if self:isOver() then return end
    local st = self.state
    if key == "DEL" then
        if #st.current == 0 then return end
        st.current = st.current:sub(1, -2)
    elseif key == "ENTER" then
        if #st.current ~= WORD_LEN then
            UI.notify("Not enough letters.", 1)
            return
        end
        table.insert(st.guesses, st.current)
        st.current = ""
        self:save()
    else
        if #st.current >= WORD_LEN then return end
        st.current = st.current .. key
    end
    self:refresh()
    if key == "ENTER" and self:isOver() then
        UI.notify(self:statusText(), 3)
    end
end

function Wordle.launch(date)
    local data, err = UI.withBusy("Loading Wordle…", function() return NYT.wordle(date) end)
    if not data then
        UI.error("Couldn't load Wordle.\n" .. tostring(err))
        return
    end
    UIManager:show(Wordle:new {
        date = date,
        solution = data.solution,
        state = Store.loadProgress("wordle", date),
    })
end

Wordle.evaluate = evaluate -- exposed for tests

return Wordle
