-- Amuse Labs decoder: round-trip a synthetic puzzle through the same
-- scramble + base64 the PuzzleMe player uses, then convert it.
package.path = PLUGDIR .. "/?.lua;" .. PLUGDIR .. "/tests/vendor/?.lua;" .. package.path
package.loaded["json"] = require("json") -- rxi/json.lua stands in for KOReader's json
package.loaded["dailygames/http"] = { decode = function(raw)
    local ok, d = pcall(package.loaded["json"].decode, raw); return ok and d or nil end }
local JSON = package.loaded["json"]
local A = require("dailygames/amuse")

-- inverse of Amuse.unscramble: the same reversal passes, applied in reverse order
local function scramble(t)
    local PASSES = { { 0, 45, { 6, 6 } }, { 12, 36, { 17, 4 } }, { 33, 33, { 5, 15, 4 } } }
    local L, a = #t, {}
    for i = 1, L do a[i - 1] = t:sub(i, i) end
    local function rev(lo, hi)
        for k = L, hi do if a[k] == nil then a[k] = "" end end
        while lo < hi do a[lo], a[hi] = a[hi], a[lo]; lo, hi = lo + 1, hi - 1 end
    end
    for _, pass in ipairs(PASSES) do
        local n = pass[1]
        while n < L do
            local s = n
            for _, k in ipairs(pass[3]) do
                local c = (s + k - 1 < L) and k or (L - s + 1)
                rev(s, s + c - 1); s = s + c
            end
            n = s + pass[2]
        end
    end
    local out, i = {}, 0
    while a[i] ~= nil do out[#out + 1] = a[i]; i = i + 1 end
    return table.concat(out)
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64encode(s)
    return ((s:gsub(".", function(x)
        local r, b = "", x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0") end
        return r
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
        if #x < 6 then return "" end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
        return B64:sub(c + 1, c + 1)
    end) .. ({ "", "==", "=" })[#s % 3 + 1])
end

assert(A.base64(b64encode("hello, world!")) == "hello, world!")
for _, n in ipairs { 1, 50, 99, 100, 777 } do
    local s = string.rep("abcdefghij", 80):sub(1, n)
    assert(A.unscramble(scramble(s)) == s, "unscramble inverts scramble for length " .. n)
end

-- 3x3: CAT / O#O / WEB, with HTML in a clue and a null clue number
local puzzle = {
    w = 3, h = 3, title = "Test",
    box = { { "C", "O", "W" }, { "A", "\0", "E" }, { "T", "O", "B" } }, -- box[x][y]
    clueNums = { { "1", JSON.null or "", "4" }, { "2", "", "" }, { "3", "", "" } },
    placedWords = {
        { clueNum = "4", clue = { clue = "Spider's <i>home</i>" }, x = 0, y = 2, acrossNotDown = true, nBoxes = 3 },
        { clueNum = "1", clue = { clue = "Pet &amp; friend" }, x = 0, y = 0, acrossNotDown = true, nBoxes = 3 },
        { clueNum = "1", clue = { clue = "Moo" }, x = 0, y = 0, acrossNotDown = false, nBoxes = 3 },
    },
}
local rawc = scramble(b64encode(JSON.encode(puzzle)))
local decoded = assert(A.decode(rawc), "decode")
local d = A.toCrossword(decoded)
assert(d.width == 3 and d.height == 3)
assert(d.cells[5].answer == nil, "block")
assert(d.cells[1].answer == "C" and d.cells[1].label == "1" and d.cells[7].label == "4")
assert(d.clues[1].label == "1" and d.clues[1].dir == "Across" and d.clues[1].text == "Pet & friend")
assert(d.clues[2].label == "4" and d.clues[2].text == "Spider's home")
assert(d.clues[3].dir == "Down" and table.concat(d.clues[3].cells, ",") == "1,4,7")
assert(#d.cells[1].clues == 2)
assert(A.idDate("atlantic_20261120") == "2026-11-20" and A.idDate("x") == nil)

-- list + fetch over a stubbed HTTP layer
local pages = {
    ["https://cdn3.amuselabs.com/atlantic/date-picker?set=atlantic"] = '<script id="params">'
        .. JSON.encode { streakInfo = { { puzzleDetails = { puzzleId = "atlantic_20261122" } },
            { puzzleDetails = { puzzleId = "atlantic_20261121" } } } } .. '</script>',
    ["https://cdn3.amuselabs.com/atlantic/crossword?id=atlantic_20261121&set=atlantic"] =
        '<script id="params">' .. JSON.encode { rawc = rawc } .. '</script>',
}
package.loaded["dailygames/http"].request = function(req)
    local body = pages[req.url]
    if body then return body, 200 end
    return nil, 404
end
local ids = assert(A.list("atlantic", "atlantic"))
assert(#ids == 2 and ids[2] == "atlantic_20261121")
local f = assert(A.fetch("atlantic", "atlantic", "atlantic_20261121"))
assert(f.date == "2026-11-21" and f.width == 3)
assert(A.fetch("atlantic", "atlantic", "atlantic_20261122") == nil)
assert(A.latest("atlantic", "atlantic").date == "2026-11-21", "latest falls back to the second puzzle")
print("AMUSE PASSED")
