--[[
Amuse Labs PuzzleMe crosswords (used by The Atlantic).

  date picker: https://cdn3.amuselabs.com/<site>/date-picker?set=<set>
               -> <script id="params">{ "streakInfo": [ { "puzzleDetails": { "puzzleId" } } ] }
  puzzle page: https://cdn3.amuselabs.com/<site>/crossword?id=<id>&set=<set>
               -> <script id="params">{ "rawc": "<scrambled base64 JSON>" }

rawc is unscrambled with the same fixed segment reversals as Yf() in the
player's c-min.js (build 22d01b0), then base64 and JSON decoded. If Amuse
changes the scramble, update PASSES below. Decoded fields:
  w, h; box[x][y] (column-major; "\0" = block); clueNums[x][y];
  placedWords[] = { clueNum, clue = { clue }, x, y, acrossNotDown, nBoxes }
]]


local Http = require("dailygames/http")

local Amuse = {}

-- { first start, gap after each group, segment lengths } (from c-min.js Yf)
local PASSES = {
    { 33, 33, { 5, 15, 4 } },
    { 12, 36, { 17, 4 } },
    { 0, 45, { 6, 6 } },
}

function Amuse.unscramble(t)
    local L = #t
    local a = {}
    for i = 1, L do a[i - 1] = t:sub(i, i) end
    local function rev(lo, hi)
        for k = L, hi do if a[k] == nil then a[k] = "" end end
        while lo < hi do
            a[lo], a[hi] = a[hi], a[lo]
            lo, hi = lo + 1, hi - 1
        end
    end
    for _, pass in ipairs(PASSES) do
        local n = pass[1]
        while n < L do
            local s = n
            for _, k in ipairs(pass[3]) do
                local c = (s + k - 1 < L) and k or (L - s + 1)
                rev(s, s + c - 1)
                s = s + c
            end
            n = s + pass[2]
        end
    end
    local out, i = {}, 0
    while a[i] ~= nil do
        out[#out + 1] = a[i]
        i = i + 1
    end
    return table.concat(out)
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, #B64 do B64_INDEX[B64:byte(i)] = i - 1 end

function Amuse.base64(s)
    local out, bits, nbits = {}, 0, 0
    for i = 1, #s do
        local v = B64_INDEX[s:byte(i)]
        if v then
            bits = bits * 64 + v
            nbits = nbits + 6
            if nbits >= 8 then
                nbits = nbits - 8
                local byte = math.floor(bits / 2 ^ nbits)
                out[#out + 1] = string.char(byte)
                bits = bits - byte * 2 ^ nbits
            end
        end
    end
    return table.concat(out)
end

local function params(html)
    local raw = html and html:match('<script[^>]-id="params"[^>]*>(.-)</script>')
    if not raw then return nil end
    local data = Http.decode(raw)
    return type(data) == "table" and data or nil
end

--- Decodes rawc into the puzzle table (or nil).
function Amuse.decode(rawc)
    for _, candidate in ipairs { Amuse.unscramble(rawc), rawc } do
        local data = Http.decode(Amuse.base64(candidate))
        if type(data) == "table" and data.box then return data end
    end
end

local function plain(text)
    text = tostring(text or ""):gsub("<[^>]+>", "")
    text = text:gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&apos;", "'")
        :gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&nbsp;", " "):gsub("&amp;", "&")
    return text
end

--- Converts a decoded puzzle to the format crossword.lua uses.
function Amuse.toCrossword(p)
    local w, h = p.w, p.h
    local cells = {}
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local idx = y * w + x + 1
            local ans = p.box[x + 1] and p.box[x + 1][y + 1]
            local num = p.clueNums and p.clueNums[x + 1] and p.clueNums[x + 1][y + 1]
            if type(ans) == "string" and ans ~= "" and ans ~= "\0" then
                -- rebus squares: accept the first letter
                local label = (type(num) == "string" or type(num) == "number") and tostring(num) or nil
                cells[idx] = { answer = ans:sub(1, 1):upper(), label = label, clues = {} }
            else
                cells[idx] = { clues = {} }
            end
        end
    end
    local words = {}
    for _, pw in ipairs(p.placedWords or {}) do table.insert(words, pw) end
    table.sort(words, function(a, b)
        if a.acrossNotDown ~= b.acrossNotDown then return a.acrossNotDown end
        return (tonumber(a.clueNum) or 0) < (tonumber(b.clueNum) or 0)
    end)
    local clues = {}
    for _, pw in ipairs(words) do
        local clue = {
            label = tostring(pw.clueNum or "?"),
            dir = pw.acrossNotDown and "Across" or "Down",
            text = plain(type(pw.clue) == "table" and pw.clue.clue or pw.clue),
            cells = {},
        }
        for k = 0, (pw.nBoxes or 0) - 1 do
            local x = pw.x + (pw.acrossNotDown and k or 0)
            local y = pw.y + (pw.acrossNotDown and 0 or k)
            table.insert(clue.cells, y * w + x + 1)
        end
        table.insert(clues, clue)
        for _, idx in ipairs(clue.cells) do
            if cells[idx] then table.insert(cells[idx].clues, #clues) end
        end
    end
    return { width = w, height = h, cells = cells, clues = clues, title = p.title, author = p.author }
end

local function fetchText(url)
    local data, code, err = Http.request { url = url, raw = true }
    if not code then return nil, err end
    if code ~= 200 then return nil, "HTTP " .. tostring(code) end
    return data
end

--- Fetches the newest published puzzle of a series.
-- site: e.g. "atlantic"; set: e.g. "atlantic". Returns crossword data or nil + error.
function Amuse.latest(site, set)
    local base = "https://cdn3.amuselabs.com/" .. site
    local picker, err = fetchText(base .. "/date-picker?set=" .. set)
    if not picker then return nil, err end
    local pp = params(picker)
    local ids = {}
    for _, s in ipairs(pp and pp.streakInfo or {}) do
        local id = s.puzzleDetails and s.puzzleDetails.puzzleId
        if id then table.insert(ids, id) end
    end
    if #ids == 0 then return nil, "no puzzles listed" end
    for i = 1, math.min(2, #ids) do
        local page = fetchText(base .. "/crossword?id=" .. ids[i] .. "&set=" .. set)
        local q = params(page)
        if q and q.rawc then
            local puzzle = Amuse.decode(q.rawc)
            if puzzle then
                local data = Amuse.toCrossword(puzzle)
                data.id = ids[i]
                data.date = ids[i]:match("(%d%d%d%d)(%d%d)(%d%d)$")
                    and ids[i]:gsub("^.-(%d%d%d%d)(%d%d)(%d%d)$", "%1-%2-%3") or os.date("%Y-%m-%d")
                return data
            end
        end
    end
    return nil, "couldn't decode the puzzle"
end

return Amuse
