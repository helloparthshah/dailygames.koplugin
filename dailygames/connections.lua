--[[
Connections: find four groups of four. Four mistakes allowed.
Solved groups are shaded light (easiest) to black (trickiest).
]]

local ButtonTable = require("ui/widget/buttontable")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local NYT = require("dailygames/nyt")
local Store = require("dailygames/store")
local UI = require("dailygames/ui")

local Color = UI.Color
local GROUP_SIZE, MAX_MISTAKES = 4, 4

local LEVELS = {
    { name = "Easy", bg = Color.COLOR_LIGHT_GRAY, fg = Color.COLOR_BLACK },
    { name = "Medium", bg = Color.COLOR_GRAY, fg = Color.COLOR_BLACK },
    { name = "Hard", bg = Color.COLOR_DARK_GRAY, fg = Color.COLOR_WHITE },
    { name = "Tricky", bg = Color.COLOR_BLACK, fg = Color.COLOR_WHITE },
}

local function count(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end

local Connections = UI.FullscreenApp:extend {
    name = "connections_app",
}

function Connections:setup()
    self.by_title = {}
    for _, cat in ipairs(self.categories) do
        self.by_title[cat.title] = cat
    end
    self.state = self.state or {
        remaining = self.board, -- words still on the board, in display order
        selected = {},          -- word -> true
        solved = {},            -- list of { title = ..., revealed = bool }
        mistakes = 0,
        guesses = {},           -- sorted-word keys already tried
    }
end

function Connections:getTitle()
    return "Connections · " .. self.date
end

function Connections:isOver()
    return #self.state.remaining == 0 or self.state.mistakes >= MAX_MISTAKES
end

function Connections:buildSolved(width)
    local group = VerticalGroup:new { align = "center" }
    for _, entry in ipairs(self.state.solved) do
        local cat = self.by_title[entry.title]
        local style = LEVELS[cat.level] or LEVELS[1]
        table.insert(group, UI.banner({
            { text = style.name:upper() .. ": " .. cat.title, bold = true },
            { text = table.concat(cat.words, ", "), face = "xx_smallinfofont" },
        }, width, { bg = style.bg, fg = style.fg }))
        table.insert(group, UI.span(3))
    end
    return group
end

function Connections:buildGrid(width)
    local st = self.state
    local rows, row = {}, {}
    for _, word in ipairs(st.remaining) do
        table.insert(row, {
            text = st.selected[word] and ("■ " .. word) or word,
            callback = function() self:toggle(word) end,
        })
        if #row == GROUP_SIZE then
            table.insert(rows, row)
            row = {}
        end
    end
    if #row > 0 then table.insert(rows, row) end

    local n = count(st.selected)
    local over = self:isOver()
    table.insert(rows, {
        { text = "Shuffle", enabled = not over, callback = function() self:shuffle() end },
        { text = "Deselect", enabled = n > 0, callback = function() st.selected = {}; self:refresh() end },
        { text = string.format("Submit (%d/%d)", n, GROUP_SIZE), enabled = n == GROUP_SIZE and not over,
          callback = function() self:submit() end },
    })
    return ButtonTable:new { width = width, buttons = rows, zero_sep = true, show_parent = self }
end

function Connections:statusText()
    local st = self.state
    if #st.remaining == 0 and st.mistakes < MAX_MISTAKES then
        return "Solved! Mistakes: " .. st.mistakes
    elseif st.mistakes >= MAX_MISTAKES then
        return "Out of mistakes. Groups revealed."
    end
    local left = MAX_MISTAKES - st.mistakes
    return "Mistakes remaining: " .. string.rep("● ", left) .. string.rep("○ ", st.mistakes)
end

function Connections:buildBody(width)
    local w = math.floor(width * 0.94)
    local body = VerticalGroup:new { align = "center" }
    table.insert(body, self:buildSolved(w))
    if #self.state.remaining > 0 then
        table.insert(body, UI.span(4))
        table.insert(body, self:buildGrid(w))
    end
    table.insert(body, UI.span(8))
    table.insert(body, UI.text(self:statusText(), w))
    return body
end

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
    end
    self:refresh()
end

function Connections:shuffle()
    local w = self.state.remaining
    for i = #w, 2, -1 do
        local j = math.random(i)
        w[i], w[j] = w[j], w[i]
    end
    self:save()
    self:refresh()
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
        if g == key then
            UI.notify("Already guessed!", 1)
            return
        end
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
            self:refresh()
            if #st.remaining == 0 then
                UI.notify(self:statusText(), 3)
            end
            return
        end
        best = math.max(best, hits)
    end

    st.mistakes = st.mistakes + 1
    st.selected = {}
    if st.mistakes >= MAX_MISTAKES then
        self:revealRest()
    end
    self:save()
    self:refresh()
    if st.mistakes >= MAX_MISTAKES then
        UI.notify("Out of mistakes!", 2)
    elseif best == GROUP_SIZE - 1 then
        UI.notify("One away…", 1.5)
    else
        UI.notify("Not a group.", 1.2)
    end
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
        categories = data.categories,
        board = data.board,
        state = Store.loadProgress("connections", date),
    })
end

return Connections
