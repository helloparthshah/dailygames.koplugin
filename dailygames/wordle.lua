--[[
Wordle: six tries to guess a five-letter word.

Tiles and keys use the same three shades:
  black, white letter  = right letter, right spot
  gray, black letter   = in the word, wrong spot
  white, faded letter  = not in the word
The row you're typing in has a thick black border.
]]

local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local Archive = require("dailygames/archive")
local Http = require("dailygames/http")
local NYT = require("dailygames/nyt")
local WORDS_DATA = require("dailygames/data_words5")
local Store = require("dailygames/store")
local UI = require("dailygames/ui")

local WORD_LEN, MAX_GUESSES = 5, 6

-- Valid guesses: NYT's own list (from its Wordle page script, cached on the
-- device and rechecked weekly), or the bundled ENABLE list if that can't be had.
local PAGE_URL = "https://www.nytimes.com/games/wordle/index.html"
local WORDS_FILE = DataStorage:getDataDir() .. "/cache/nyt-wordle-words.txt"
local RECHECK = 7 * 86400

local word_set, word_source

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function toSet(text, pattern)
    local set, n = {}, 0
    for w in text:gmatch(pattern) do
        set[w:upper()] = true
        n = n + 1
    end
    return set, n
end

--- The guess list inside NYT's script: the longest array of five-letter words.
local function parseWordList(js)
    local best, best_n = nil, 0
    for arr in js:gmatch('%[("%l%l%l%l%l"[,"%l]*)%]') do
        local _, n = arr:gsub('"%l%l%l%l%l"', "")
        if n > best_n then best, best_n = arr, n end
    end
    if best_n < 5000 then return nil end
    local words = {}
    for w in best:gmatch('"(%l%l%l%l%l)"') do words[#words + 1] = w end
    return words
end

--- Downloads NYT's guess list (tries the script that had it last time first).
local function fetchWordList()
    local page, code = Http.request { url = PAGE_URL, raw = true }
    if code ~= 200 or type(page) ~= "string" then return nil end
    local scripts, last = {}, Store.get("wordle/words_script")
    for src in page:gmatch('src="(https://www%.nytimes%.com/games%-assets/v2/[%w%.]+%.js)"') do
        local chunk = src:match("/(%d+)%.[%w]+%.js$")
        if chunk and chunk == last then table.insert(scripts, 1, src) else scripts[#scripts + 1] = src end
    end
    for _, src in ipairs(scripts) do
        local js, c = Http.request { url = src, raw = true, timeout = 20 }
        if c == 200 and type(js) == "string" and js:find('"aahed"', 1, true) then
            local words = parseWordList(js)
            if words then
                Store.set("wordle/words_script", src:match("/(%d+)%.[%w]+%.js$"))
                return words
            end
        end
    end
end

--- Refreshes the cached NYT list if it's missing or a week old (call with Wi-Fi on).
local function updateWordList()
    if os.time() - (Store.get("wordle/words_checked") or 0) < RECHECK and readFile(WORDS_FILE) then return end
    local words = fetchWordList()
    Store.set("wordle/words_checked", os.time())
    if not words then return end
    os.execute("mkdir -p '" .. DataStorage:getDataDir() .. "/cache'")
    local f = io.open(WORDS_FILE, "wb")
    if f then
        f:write(table.concat(words, "\n"))
        f:close()
        word_set = nil -- reload
    end
end

local function loadWords()
    local cached = readFile(WORDS_FILE)
    if cached then
        local set, n = toSet(cached, "%l%l%l%l%l")
        if n >= 5000 then return set, "nyt" end
    end
    return (toSet(WORDS_DATA, "%u%u%u%u%u")), "enable"
end

--- True if `word` is a valid guess.
local function isWord(word)
    if not word_set then word_set, word_source = loadWords() end
    return word_set[word] == true
end

local function wordSource()
    if not word_set then word_set, word_source = loadWords() end
    return word_source
end
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

-- board ----------------------------------------------------------------------

local TILE = {
    correct = { bg = UI.BLACK, fg = UI.WHITE, border = UI.BLACK, t = 3 },
    present = { bg = UI.MID, fg = UI.BLACK, border = UI.BLACK, t = 3 },
    absent = { bg = UI.WHITE, fg = UI.MID, border = UI.LIGHT, t = 2 },
    empty = { bg = UI.WHITE, fg = UI.BLACK, border = UI.LIGHT, t = 2 },
    active = { bg = UI.WHITE, fg = UI.BLACK, border = UI.BLACK, t = 4 },
}

local Board = UI.Board:extend {}

function Board:setup()
    self.gap = UI.px(6)
    self.tile = math.floor(math.min(
        (self.width - self.gap * (WORD_LEN - 1)) / WORD_LEN,
        (self.height - self.gap * (MAX_GUESSES - 1)) / MAX_GUESSES))
    self.ox = math.floor((self.width - (self.tile * WORD_LEN + self.gap * (WORD_LEN - 1))) / 2)
    self.face = UI.fitFace({ "W", "M" }, self.tile * 0.7, self.tile * 0.55, { bold = true, caps = true })
end

function Board:draw(bb, x, y)
    local app = self.app
    local guesses, current = app.state.guesses, app.state.current
    for r = 1, MAX_GUESSES do
        local guess = guesses[r]
        local eval = guess and evaluate(guess, app.solution)
        local active = r == #guesses + 1 and not app:isOver()
        for c = 1, WORD_LEN do
            local letter, st = "", TILE.empty
            if guess then
                letter, st = guess:sub(c, c), TILE[eval[c]]
            elseif active then
                letter, st = current:sub(c, c), TILE.active
            end
            local tx = x + self.ox + (c - 1) * (self.tile + self.gap)
            local ty = y + (r - 1) * (self.tile + self.gap)
            bb:paintRect(tx, ty, self.tile, self.tile, st.bg)
            UI.drawBorder(bb, tx, ty, self.tile, self.tile, UI.px(st.t), st.border)
            UI.drawText(bb, self.face, letter, tx, ty, self.tile, self.tile, st.fg, true)
        end
    end
end

-- app ------------------------------------------------------------------------

local Wordle = UI.FullscreenApp:extend {
    name = "wordle_app",
    help_text = [[Guess the 5-letter word in 6 tries.

Black tile: right letter, right spot.
Gray tile: in the word, wrong spot.
White tile: not in the word.

The keyboard is shaded the same way, so you can see which letters are left.]],
}

function Wordle:setup()
    self.state = self.state or { guesses = {}, current = "" }
    if self:isOver() then self.status = self:resultText() end
end

function Wordle:getTitle()
    return "Wordle" .. (self.number and (" #" .. self.number) or "")
end

function Wordle:isWon()
    return self.state.guesses[#self.state.guesses] == self.solution
end

function Wordle:isOver()
    return self:isWon() or #self.state.guesses >= MAX_GUESSES
end

function Wordle:resultText()
    if self:isWon() then
        local words = { "Genius!", "Magnificent!", "Impressive!", "Splendid!", "Great!", "Phew!" }
        return string.format("%s Solved in %d/%d.", words[#self.state.guesses] or "Solved!", #self.state.guesses, MAX_GUESSES)
    end
    return "The word was " .. self.solution .. "."
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

function Wordle:buildBody(width, height)
    local w = math.floor(width * 0.94)
    local kb_h = math.floor(math.min(height * 0.3, UI.px(70) * 3))
    local states = self:keyStates()
    local keyboard = UI.Keyboard:new {
        width = w,
        height = kb_h,
        rows = {
            UI.QWERTY[1],
            UI.QWERTY[2],
            { { label = "Enter", value = "ENTER", width = 1.5 }, "Z", "X", "C", "V", "B", "N", "M",
              { label = "⌫", value = "DEL", width = 1.5 } },
        },
        state_func = function(k) return states[k] end,
        enabled = not self:isOver(),
        on_key = function(k) self:onKey(k) end,
    }
    local status = self:statusLine(w)
    local board_h = height - kb_h - status:getSize().h - UI.px(24)
    local board = Board:new { width = w, height = board_h, app = self }
    local top = VerticalGroup:new { align = "center", board, UI.span(8), status }
    return top, keyboard
end

function Wordle:menuItems()
    if not self:isOver() then return {} end
    return { { text = "Copy share text", callback = function() self:copyShare() end } }
end

--- Copies the usual emoji grid to the clipboard (Kindle fonts can't draw it).
function Wordle:copyShare()
    local lines = { string.format("Wordle %s %s/6", tostring(self.number or ""),
        self:isWon() and #self.state.guesses or "X") }
    for _, g in ipairs(self.state.guesses) do
        local row = {}
        for _, e in ipairs(evaluate(g, self.solution)) do
            table.insert(row, e == "correct" and "🟩" or e == "present" and "🟨" or "⬜")
        end
        table.insert(lines, table.concat(row))
    end
    UI.copy(table.concat(lines, "\n"))
end

function Wordle:progressKey() return "wordle" end

function Wordle:save()
    Store.saveProgress(self:storeKey(), self.date, self:markDone())
end

function Wordle:onKey(key)
    if self:isOver() then return end
    local st = self.state
    if key == "DEL" then
        st.current = st.current:sub(1, -2)
        self.status = ""
    elseif key == "ENTER" then
        if #st.current ~= WORD_LEN then
            self:setStatus("Not enough letters")
            return
        end
        if st.current ~= self.solution and not isWord(st.current) then
            self:setStatus("Not in word list")
            return
        end
        table.insert(st.guesses, st.current)
        st.current = ""
        self:save()
        self.status = self:isOver() and self:resultText() or ""
    elseif #st.current < WORD_LEN then
        st.current = st.current .. key
        self.status = ""
    else
        return
    end
    self:refresh()
end

--- opts (endless mode): { state, on_next }; otherwise today's saved progress is used.
function Wordle.launch(date, opts)
    local data, err, crash = UI.withBusy("Loading Wordle…", function()
        pcall(updateWordList)
        return NYT.wordle(date)
    end)
    if not data then
        UI.error("Couldn't load Wordle.\n" .. tostring(err or crash))
        return
    end
    UIManager:show(Wordle:new {
        date = date,
        number = data.number,
        solution = data.solution,
        state = opts and opts.state or not opts and Store.loadProgress("wordle", date) or nil,
        on_next = opts and opts.on_next,
    })
end

--- Endless: a random past NYT Wordle (the archive is open back to the first one).
function Wordle.launchEndless(today)
    Archive.play("wordle", "2021-06-19", today, Wordle.launch)
end

Wordle.evaluate = evaluate -- exposed for tests
Wordle.isWord = isWord
Wordle.parseWordList = parseWordList
Wordle.updateWordList = updateWordList
Wordle.wordSource = wordSource
function Wordle.resetWords() word_set, word_source = nil, nil end

return Wordle
