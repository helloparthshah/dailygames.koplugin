--[[
Sabacc: an offline card game (simplified Corellian Spike rules) against three
computer players. Unlike the other games it needs no network and is not a
daily puzzle: you can play as many hands as you like, and credits carry over.

Rules
  Deck: +1..+10 and -1..-10 in three suits (circle, triangle, square), plus two
  sylops worth 0. A hand totalling exactly 0 is a Sabacc; anything else is a
  Nulrhek, and the one closest to zero wins (positive beats negative).
  Each hand: everyone antes, gets two cards, then plays three rounds. In a
  round you Gain (draw), Swap (take the face-up discard for one of yours),
  Discard, or Stand; then bet: check, bet 10, or junk (fold). After betting
  two spike dice roll; doubles cause a Sabacc Shift: every hand is replaced
  with the same number of new cards.

On e-ink: positive cards are black, negative dark gray; 7-10 and sylops are solid face cards.
The screen is drawn as a starship console: cut-corner panels, monospaced labels.

The engine (Sabacc.newTable, Sabacc.act, Sabacc.bet, ...) is plain data so it
can be saved with Store and tested without the UI.
]]

local UIManager = require("ui/uimanager")

local Store = require("dailygames/store")
local UI = require("dailygames/ui")

local Sabacc = {}

local ANTE, RAISE, ROUNDS, MAX_HAND, START = 5, 10, 3, 5, 100
local SAVE_KEY = "sabacc/table"

Sabacc.ANTE, Sabacc.RAISE, Sabacc.ROUNDS, Sabacc.MAX_HAND = ANTE, RAISE, ROUNDS, MAX_HAND

-- bold: how often a player raises with a strong hand
local ROSTER = {
    { name = "Tal Merrow", title = "Smuggler", bold = 0.65 },
    { name = "K-7 Unit", title = "Droid", bold = 0.35 },
    { name = "Old Jessa", title = "Cantina owner", bold = 0.5 },
}

-- cards ------------------------------------------------------------------------

-- A card is { v = -10..10, s = suit 1..3 (0 for sylops) }.

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

function Sabacc.newDeck()
    local d = {}
    for s = 1, 3 do
        for v = 1, 10 do
            d[#d + 1] = { v = v, s = s }
            d[#d + 1] = { v = -v, s = s }
        end
    end
    d[#d + 1] = { v = 0, s = 0 }
    d[#d + 1] = { v = 0, s = 0 }
    return shuffle(d)
end

local function signed(n)
    return n > 0 and ("+" .. n) or n < 0 and ("−" .. -n) or "0"
end

function Sabacc.cardText(c)
    return signed(c.v)
end

local function cardName(c)
    return c.v == 0 and "a sylop" or Sabacc.cardText(c)
end

--- Ranks a hand. Lower score is better.
-- Returns { sabacc, sum, name, score }.
function Sabacc.evaluate(hand)
    local sum, n = 0, #hand
    for _, c in ipairs(hand) do sum = sum + c.v end
    if sum ~= 0 then
        return {
            sabacc = false, sum = sum,
            name = "Nulrhek " .. signed(sum),
            score = 20 + math.abs(sum) + (sum < 0 and 0.5 or 0) - n * 0.01,
        }
    end
    local syl, count = 0, {}
    for _, c in ipairs(hand) do
        if c.v == 0 then
            syl = syl + 1
        else
            local a = math.abs(c.v)
            count[a] = (count[a] or 0) + 1
        end
    end
    local groups = {}
    for v, k in pairs(count) do groups[#groups + 1] = { v = v, n = k } end
    table.sort(groups, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.v < b.v
    end)
    local top = groups[1]
    local c1, c2 = top and top.n or 0, groups[2] and groups[2].n or 0
    local r, name
    if syl == 2 and n == 2 then r, name = 1, "Pure Sabacc"
    elseif syl == 1 and n == 5 and top and top.v == 10 and c1 == 4 then r, name = 2, "Full Sabacc"
    elseif syl >= 1 and c1 == 4 then r, name = 3, "Fleet"
    elseif syl == 1 and n == 3 and c1 == 2 then r, name = 4, "Yee-Haa"
    elseif c1 == 3 and c2 == 2 then r, name = 5, "Rhylet"
    elseif c1 == 4 then r, name = 6, "Squadron"
    elseif c1 == 3 then r, name = 7, "Banthas Wild"
    elseif c1 == 2 and c2 == 2 then r, name = 8, "Rule of Two"
    elseif c1 == 2 then r, name = 9, "Sabacc Pair"
    else r, name = 10, "Sabacc" end
    return { sabacc = true, sum = 0, name = name, score = r + (top and top.v or 0) / 100 + n / 1000 }
end

-- table state --------------------------------------------------------------------

local function draw(g)
    if #g.deck == 0 then
        local top = table.remove(g.discard)
        g.deck = shuffle(g.discard)
        g.discard = { top }
    end
    return table.remove(g.deck)
end

local function you(g) return g.players[1] end

local function active(g)
    local list = {}
    for _, p in ipairs(g.players) do
        if not p.out then list[#list + 1] = p end
    end
    return list
end

local function activeAIs(g)
    local list = {}
    for _, p in ipairs(g.players) do
        if p.ai and not p.out then list[#list + 1] = p end
    end
    return list
end

--- A new table; `credits` (optional) is a list of starting credits per seat.
function Sabacc.newTable(credits)
    local g = { players = { { name = "You", credits = credits and credits[1] or START } }, hand_no = 0 }
    for i, r in ipairs(ROSTER) do
        g.players[i + 1] = { name = r.name, title = r.title, bold = r.bold, ai = true,
            credits = credits and credits[i + 1] or START }
    end
    Sabacc.newHand(g)
    return g
end

function Sabacc.newHand(g)
    g.hand_no = g.hand_no + 1
    g.deck, g.discard = Sabacc.newDeck(), {}
    g.pot, g.round, g.phase = 0, 1, "act"
    g.dice, g.winners, g.new = nil, nil, nil
    for _, p in ipairs(g.players) do
        p.out, p.hand, p.last = false, {}, ""
        if p.ai and p.credits < ANTE + RAISE then
            p.credits = START
            p.last = "Bought back in."
        end
    end
    if you(g).credits < ANTE then
        g.phase = "broke"
        g.msg = "You're out of credits. Start a new table to keep playing."
        return g
    end
    for _, p in ipairs(g.players) do
        p.credits = p.credits - ANTE
        g.pot = g.pot + ANTE
        p.hand = { draw(g), draw(g) }
    end
    g.discard[#g.discard + 1] = draw(g)
    g.msg = string.format("Hand %d. Everyone antes %d. Get your hand as close to zero as you can.", g.hand_no, ANTE)
    return g
end

-- computer players ----------------------------------------------------------------

--- 0..1, how good a hand looks.
local function strength(p)
    local e = Sabacc.evaluate(p.hand)
    if e.sabacc then return 1 - (e.score - 1) / 12 * 0.4 end
    return math.max(0, 0.55 - math.abs(e.sum) * 0.07)
end

local function aiAct(g, p)
    local opts = { { k = "stand", s = Sabacc.evaluate(p.hand).score } }
    local top = g.discard[#g.discard]
    if top then
        for i = 1, #p.hand do
            local h = { unpack(p.hand) }
            h[i] = top
            opts[#opts + 1] = { k = "swap", i = i, s = Sabacc.evaluate(h).score }
        end
    end
    if #p.hand > 1 then
        for i = 1, #p.hand do
            local h = {}
            for j, c in ipairs(p.hand) do if j ~= i then h[#h + 1] = c end end
            opts[#opts + 1] = { k = "discard", i = i, s = Sabacc.evaluate(h).score + 0.3 }
        end
    end
    if #g.deck > 0 then
        -- expected result of a draw (keeping the best hand after an optional
        -- drop), from a sample of what's left in the deck
        local total = 0
        for _ = 1, 12 do
            local h = { unpack(p.hand) }
            h[#h + 1] = g.deck[math.random(#g.deck)]
            total = total + Sabacc.evaluate(h).score
        end
        opts[#opts + 1] = { k = "gain", s = total / 12 - 1.5 }
    end
    table.sort(opts, function(a, b) return a.s < b.s end)
    local o = (math.random() < 0.15 and opts[2]) or opts[1]
    if o.k == "gain" then
        p.hand[#p.hand + 1] = draw(g)
        -- keep it, or drop whichever card leaves the best hand
        local best, drop = #p.hand <= MAX_HAND and Sabacc.evaluate(p.hand).score or math.huge, nil
        for i = 1, #p.hand do
            local h = {}
            for j, c in ipairs(p.hand) do if j ~= i then h[#h + 1] = c end end
            local sc = Sabacc.evaluate(h).score + 0.1
            if sc < best then best, drop = sc, i end
        end
        if drop then
            local c = table.remove(p.hand, drop)
            g.discard[#g.discard + 1] = c
            p.last = "Gained a card, dropped " .. cardName(c) .. "."
        else
            p.last = "Gained a card."
        end
    elseif o.k == "swap" then
        local c = table.remove(g.discard)
        g.discard[#g.discard + 1] = p.hand[o.i]
        p.hand[o.i] = c
        p.last = "Swapped for " .. cardName(c) .. "."
    elseif o.k == "discard" then
        local c = table.remove(p.hand, o.i)
        g.discard[#g.discard + 1] = c
        p.last = "Discarded " .. cardName(c) .. "."
    else
        p.last = "Stood."
    end
end

local function aiCalls(g, p)
    if p.credits < RAISE then return false end
    return strength(p) + math.random() * 0.35 + (g.round < ROUNDS and 0.12 or 0) > 0.5
end

local function pay(g, p)
    p.credits = p.credits - RAISE
    g.pot = g.pot + RAISE
end

-- hand flow ------------------------------------------------------------------------

local function award(g, winners, prefix)
    local share = math.floor(g.pot / #winners)
    local names, idx = {}, {}
    -- an odd credit from a split pot goes to the first winner
    winners[1].credits = winners[1].credits + g.pot - share * #winners
    for _, w in ipairs(winners) do
        w.credits = w.credits + share
        names[#names + 1] = w.ai and w.name or "You"
        for i, p in ipairs(g.players) do if p == w then idx[#idx + 1] = i end end
    end
    local contested = #active(g) > 1
    local solo_you = #winners == 1 and not winners[1].ai
    g.msg = string.format("%s %s %s %d credits%s.", prefix, table.concat(names, " and "),
        solo_you and "win" or "wins", share,
        contested and (" with " .. Sabacc.evaluate(winners[1].hand).name) or "")
    g.winners = idx -- seat numbers, so the saved table stays plain data
    g.pot, g.phase = 0, "done"
end

local function showdown(g, prefix)
    local best, winners = math.huge, {}
    for _, p in ipairs(active(g)) do
        local s = Sabacc.evaluate(p.hand).score
        if s < best - 1e-9 then
            best, winners = s, { p }
        elseif math.abs(s - best) < 1e-9 then
            winners[#winners + 1] = p
        end
    end
    award(g, winners, prefix .. " Showdown:")
end

--- Rolls the spike dice (doubles: Sabacc Shift) and moves to the next round.
local function rollDice(g, prefix, quiet)
    local a, b = math.random(6), math.random(6)
    g.dice = { a, b }
    local text = string.format("%s Spike dice: %d and %d.", prefix, a, b)
    if a == b then
        text = text .. " Doubles! Sabacc Shift: every hand is replaced."
        for _, p in ipairs(active(g)) do
            local n = #p.hand
            for _, c in ipairs(p.hand) do g.discard[#g.discard + 1] = c end
            p.hand = {}
            for _ = 1, n do p.hand[#p.hand + 1] = draw(g) end
        end
        g.new = nil
    end
    g.round = g.round + 1
    if quiet then return end
    if g.round > ROUNDS then return showdown(g, text) end
    g.phase = "act"
    g.msg = string.format("%s Round %d of %d.", text, g.round, ROUNDS)
end

local function endBetting(g, prefix)
    local left = active(g)
    if #left == 1 then return award(g, left, prefix .. " Everyone else junked.") end
    rollDice(g, prefix)
end

--- After you junk: the computer players finish the hand on their own.
local function finishWithoutYou(g)
    while g.round <= ROUNDS and #active(g) > 1 do
        for _, p in ipairs(activeAIs(g)) do aiAct(g, p) end
        rollDice(g, "", true)
    end
    local left = active(g)
    if #left == 1 then return award(g, left, "You junked.") end
    showdown(g, "You junked.")
end

--- Your move in a round: "gain", "swap" (card i), "discard" (card i) or "stand".
-- The computer players then move. Returns false if the move isn't allowed.
function Sabacc.act(g, kind, i)
    local me = you(g)
    local text
    if g.phase == "drop" then
        -- after gaining: keep everything, or drop one card (the new one included)
        if kind == "keep" then
            if #me.hand > MAX_HAND then return false end
            text = "You gain " .. cardName(me.hand[g.new]) .. " and keep it."
        elseif kind == "drop" then
            if not (i and me.hand[i]) then return false end
            local gained = me.hand[g.new]
            local c = table.remove(me.hand, i)
            g.discard[#g.discard + 1] = c
            text = i == g.new and ("You gain " .. cardName(c) .. " and drop it.")
                or ("You gain " .. cardName(gained) .. " and drop " .. cardName(c) .. ".")
            g.new = nil
            for j, card in ipairs(me.hand) do if card == gained then g.new = j end end
        else
            return false
        end
        return Sabacc.endTurn(g, text)
    end
    if g.phase ~= "act" then return false end
    if kind == "gain" then
        -- draw from the deck; then keep it or drop a card (see the "drop" phase)
        local c = draw(g)
        me.hand[#me.hand + 1] = c
        g.new = #me.hand
        g.phase = "drop"
        g.msg = "You draw " .. cardName(c) .. ". Keep it, or tap a card to drop."
            .. (#me.hand > MAX_HAND and " Your hand is full, so you must drop one." or "")
        return true
    elseif kind == "swap" then
        if not (i and me.hand[i] and #g.discard > 0) then return false end
        local c = table.remove(g.discard)
        g.discard[#g.discard + 1] = me.hand[i]
        me.hand[i] = c
        g.new = i
        text = "You take " .. cardName(c) .. " from the discard pile."
    elseif kind == "discard" then
        if not (i and me.hand[i] and #me.hand > 1) then return false end
        local c = table.remove(me.hand, i)
        g.discard[#g.discard + 1] = c
        g.new = nil
        text = "You discard " .. cardName(c) .. "."
    elseif kind == "stand" then
        g.new = nil
        text = "You stand."
    else
        return false
    end
    return Sabacc.endTurn(g, text)
end

--- Your move is done: the computer players move, then betting starts.
function Sabacc.endTurn(g, text)
    you(g).last = text
    for _, p in ipairs(activeAIs(g)) do aiAct(g, p) end
    g.phase = "bet"
    g.msg = text .. " Now bet: check, bet " .. RAISE .. ", or junk your hand."
    return true
end

--- Your bet: "check", "bet", "call" (after a raise) or "junk".
function Sabacc.bet(g, kind)
    local me = you(g)
    if kind == "junk" and (g.phase == "bet" or g.phase == "call") then
        me.out = true
        finishWithoutYou(g)
        return true
    end
    if kind == "call" and g.phase == "call" then
        if me.credits < RAISE then return false end
        pay(g, me)
        endBetting(g, "You call " .. RAISE .. ".")
        return true
    end
    if g.phase ~= "bet" then return false end
    if kind == "bet" then
        if me.credits < RAISE then return false end
        pay(g, me)
        for _, p in ipairs(activeAIs(g)) do
            if aiCalls(g, p) then
                pay(g, p)
                p.last = "Called " .. RAISE .. "."
            else
                p.out = true
                p.last = "Junked."
            end
        end
        endBetting(g, "You bet " .. RAISE .. ".")
        return true
    end
    if kind ~= "check" then return false end
    -- you check: a computer player with a strong hand may raise
    local raiser
    for _, p in ipairs(activeAIs(g)) do
        p.last = "Checked."
        if not raiser and p.credits >= RAISE and strength(p) > 0.72 and math.random() < p.bold then
            raiser = p
        end
    end
    if not raiser then
        endBetting(g, "Everyone checks.")
        return true
    end
    pay(g, raiser)
    raiser.last = "Raised " .. RAISE .. "."
    for _, p in ipairs(activeAIs(g)) do
        if p ~= raiser then
            if aiCalls(g, p) then
                pay(g, p)
                p.last = "Called " .. RAISE .. "."
            else
                p.out = true
                p.last = "Junked."
            end
        end
    end
    g.phase = "call"
    g.msg = string.format("%s raises %d. Call or junk?", raiser.name, RAISE)
        .. (me.credits < RAISE and " You can't cover it, so junk." or "")
    return true
end

function Sabacc.isWinner(g, seat)
    for _, i in ipairs(g.winners or {}) do
        if i == seat then return true end
    end
    return false
end

-- drawing ---------------------------------------------------------------------------
--[[
The look: a starship console in black and white. Panels have cut corners,
labels are monospaced capitals, the header is a black band with an angled tab,
and cards follow the Corellian Spike deck: coffin-shaped, with the value
(number and bar marks) in a band at the top and bottom and pips between.
]]

local MONO = "scfont" -- KOReader's monospace face (Droid Sans Mono)

--- Scanline fill of a polygon given as { {x, y}, ... }.
local function fillPoly(bb, pts, color)
    local miny, maxy = math.huge, -math.huge
    for _, p in ipairs(pts) do
        if p[2] < miny then miny = p[2] end
        if p[2] > maxy then maxy = p[2] end
    end
    local n = #pts
    for yy = math.floor(miny), math.ceil(maxy) - 1 do
        local sy = yy + 0.5
        local xs = {}
        for i = 1, n do
            local a, b = pts[i], pts[i % n + 1]
            if (a[2] <= sy and b[2] > sy) or (b[2] <= sy and a[2] > sy) then
                xs[#xs + 1] = a[1] + (sy - a[2]) * (b[1] - a[1]) / (b[2] - a[2])
            end
        end
        table.sort(xs)
        for k = 1, #xs - 1, 2 do
            local x0, x1 = math.floor(xs[k] + 0.5), math.floor(xs[k + 1] + 0.5)
            if x1 > x0 then bb:paintRect(x0, yy, x1 - x0, 1, color) end
        end
    end
end

--- Card outline: a hexagon pointed at the sides, flat at top and bottom.
local function hexPts(x, y, w, h)
    return { { x + w * 0.2, y }, { x + w * 0.8, y }, { x + w, y + h / 2 },
        { x + w * 0.8, y + h }, { x + w * 0.2, y + h }, { x, y + h / 2 } }
end

--- Console panel: top-left and bottom-right corners cut.
local function cutPts(x, y, w, h, c)
    return { { x + c, y }, { x + w, y }, { x + w, y + h - c }, { x + w - c, y + h }, { x, y + h }, { x, y + c } }
end

--- Filled shape with an edge of thickness t (shape(x, y, w, h, ...) -> points).
local function frame(bb, shape, x, y, w, h, t, edge, fill, c)
    fillPoly(bb, shape(x, y, w, h, c), edge)
    if fill then
        fillPoly(bb, shape(x + t, y + t, w - 2 * t, h - 2 * t, c and math.max(1, c - t * 0.4)), fill)
    end
end

local function panel(bb, x, y, w, h, c, t, edge, fill)
    frame(bb, cutPts, x, y, w, h, t, edge, fill, c)
end

local function star(cx, cy, r, points, inner)
    local pts = {}
    for k = 0, 2 * points - 1 do
        local a = k * math.pi / points - math.pi / 2
        local rr
        if k % 2 == 1 then rr = r * inner
        elseif (k / 2) % 2 == 0 then rr = r
        else rr = r * 0.62 end
        pts[#pts + 1] = { cx + math.cos(a) * rr, cy + math.sin(a) * rr }
    end
    return pts
end

--- Decorative script: each character becomes a small glyph built from strokes.
-- (Console flavour only; it encodes nothing a player needs.)
local function drawScript(bb, text, x, y, h, color)
    local gw, gap = math.floor(h * 0.62), math.floor(h * 0.32)
    local t = math.max(1, math.floor(h / 6))
    local cx = x
    for i = 1, #text do
        local b = text:byte(i)
        if b == 32 then
            cx = cx + gw
        else
            local k = (b * 7 + i * 3) % 8
            local function H(fy) bb:paintRect(cx, y + math.floor((h - t) * fy), gw, t, color) end
            local function V(fx) bb:paintRect(cx + math.floor((gw - t) * fx), y, t, h, color) end
            if k == 0 then H(0); V(0)
            elseif k == 1 then H(0); H(0.5); H(1)
            elseif k == 2 then V(0.5); H(1)
            elseif k == 3 then V(1); H(1); bb:paintRect(cx, y, t, t, color)
            elseif k == 4 then H(0); UI.drawLine(bb, cx, y + h - 1, cx + gw - 1, y, t, color)
            elseif k == 5 then H(0); H(1); V(0)
            elseif k == 6 then V(0); V(1); H(0.5)
            else H(0); H(1); UI.drawLine(bb, cx + gw - 1, y, cx, y + h - 1, t, color) end
            cx = cx + gw + gap
        end
    end
    return cx - x
end

-- Positive cards are green and negative red in the real deck; here they are
-- black and dark gray (the number keeps its sign too).
local INK = { pos = UI.BLACK, neg = UI.DARK, syl = UI.BLACK }

--- One suit pip (circle, triangle, square) centred on cx, cy with radius r.
local function pip(bb, s, cx, cy, r, color, down)
    if s == 1 then
        UI.fillCircle(bb, math.floor(cx), math.floor(cy), math.floor(r), color)
    elseif s == 2 then
        local d = down and -1 or 1
        fillPoly(bb, { { cx, cy - d * r }, { cx + r * 1.1, cy + d * r * 0.8 }, { cx - r * 1.1, cy + d * r * 0.8 } }, color)
    else
        local q = math.floor(r * 0.9)
        bb:paintRect(math.floor(cx) - q, math.floor(cy) - q, 2 * q, 2 * q, color)
    end
end

-- Pip patterns for 1..6, as in the deck: x, y in -1..1, and whether a triangle points down.
local PATTERN = {
    { { 0, 0 } },
    { { 0, -0.55 }, { 0, 0.55, true } },
    { { 0, -0.6 }, { -0.55, 0.45 }, { 0.55, 0.45 } },
    { { 0, -0.75 }, { -0.62, 0 }, { 0.62, 0 }, { 0, 0.75, true } },
    { { 0, -0.75 }, { -0.62, 0 }, { 0, 0 }, { 0.62, 0 }, { 0, 0.75, true } },
    { { 0, -0.8 }, { -0.62, -0.38 }, { 0.62, -0.38 }, { -0.62, 0.38, true }, { 0.62, 0.38, true }, { 0, 0.8, true } },
}

--- Face cards (7-10) and the sylop: white designs on a solid card.
local function ornament(bb, n, s, cx, cy, R, fg, bg)
    local t = math.max(2, math.floor(R * 0.08))
    if n == 0 then -- sylop: ringed hexagon around a disc
        UI.ringCircle(bb, cx, cy, R, t, fg)
        fillPoly(bb, hexPts(cx - R * 0.72, cy - R * 0.62, R * 1.44, R * 1.24), fg)
        fillPoly(bb, hexPts(cx - R * 0.72 + t, cy - R * 0.62 + t, R * 1.44 - 2 * t, R * 1.24 - 2 * t), bg)
        UI.fillCircle(bb, cx, cy, math.floor(R * 0.36), fg)
        bb:paintRect(cx - math.floor(R * 0.5), cy - math.floor(t / 2), math.floor(R), t, bg)
    elseif n == 7 then -- starburst
        fillPoly(bb, star(cx, cy, R, 8, 0.34), fg)
        UI.fillCircle(bb, cx, cy, math.floor(R * 0.36), bg)
        pip(bb, s, cx, cy, R * 0.2, fg)
    elseif n == 8 then -- wheel of pips
        UI.ringCircle(bb, cx, cy, math.floor(R * 0.62), t, fg)
        for k = 0, 7 do
            local a = k * math.pi / 4
            pip(bb, s, cx + math.cos(a) * R * 0.86, cy + math.sin(a) * R * 0.86, R * 0.13, fg)
        end
        pip(bb, s, cx, cy, R * 0.3, fg)
    elseif n == 9 then -- spine with chevrons
        bb:paintRect(cx - math.floor(t / 2), math.floor(cy - R), t, math.floor(2 * R), fg)
        for _, d in ipairs { -1, 1 } do
            local y0 = cy + d * R * 0.55
            fillPoly(bb, { { cx - R * 0.7, y0 }, { cx, y0 + d * R * 0.4 }, { cx + R * 0.7, y0 }, { cx + R * 0.7, y0 - d * R * 0.2 },
                { cx, y0 + d * R * 0.2 }, { cx - R * 0.7, y0 - d * R * 0.2 } }, fg)
        end
        UI.fillCircle(bb, cx, cy, math.floor(R * 0.34), fg)
        UI.fillCircle(bb, cx, cy, math.floor(R * 0.34) - t, bg)
        pip(bb, s, cx, cy, R * 0.18, fg)
    else -- 10: framed diamond with four pips
        local d = R * 0.62
        fillPoly(bb, { { cx, cy - d }, { cx + d, cy }, { cx, cy + d }, { cx - d, cy } }, fg)
        d = d - t * 1.6
        fillPoly(bb, { { cx, cy - d }, { cx + d, cy }, { cx, cy + d }, { cx - d, cy } }, bg)
        for _, o in ipairs { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } } do
            pip(bb, s, cx + o[1] * R * 0.88, cy + o[2] * R * 0.88, R * 0.14, fg, o[2] > 0)
        end
        pip(bb, s, cx, cy, R * 0.24, fg)
    end
end

--- A card face, after the Corellian Spike deck: number band on top, value dots
-- on the bottom band, pips (1-6) or an ornate design (7-10, sylop) between.
local function drawCard(bb, c, x, y, w, h, faces, mini)
    local kind = c.v == 0 and "syl" or c.v < 0 and "neg" or "pos"
    local ink = INK[kind]
    local n = math.abs(c.v)
    local solid = n == 0 or n >= 7
    local t = math.max(2, math.floor(w / (mini and 24 or 40)))
    fillPoly(bb, hexPts(x, y, w, h), ink)
    local face = solid and ink or UI.WHITE
    local fg = solid and UI.WHITE or ink
    fillPoly(bb, hexPts(x + t, y + t, w - 2 * t, h - 2 * t), face)
    if solid then -- a light inner outline, like the printed border
        local i = math.floor(w * 0.07)
        fillPoly(bb, hexPts(x + i, y + i, w - 2 * i, h - 2 * i), UI.LIGHT)
        fillPoly(bb, hexPts(x + i + 1, y + i + 1, w - 2 * i - 2, h - 2 * i - 2), face)
    end
    -- bands across the flat top and bottom
    local bx, bw = x + math.floor(w * 0.22), math.floor(w * 0.56)
    local bh = math.floor(h * (mini and 0.17 or 0.11))
    local band, band_fg = solid and UI.WHITE or ink, solid and ink or UI.WHITE
    local top = y + t + math.floor(h * 0.015)
    bb:paintRect(bx, top, bw, bh, band)
    UI.drawText(bb, faces.num, Sabacc.cardText(c), bx, top, bw, bh, band_fg, true)
    if not mini then
        local lt = math.max(1, math.floor(t / 2))
        bb:paintRect(bx, top + bh + lt * 2, bw, lt, band)
        local bot = y + h - t - math.floor(h * 0.015) - bh
        bb:paintRect(bx, bot, bw, bh, band)
        bb:paintRect(bx, bot - lt * 3, bw, lt, band)
        -- one dot per point of value (a diamond for the sylop)
        local dr = math.max(2, math.floor(bh * 0.17))
        if n == 0 then
            local cx, cy = bx + bw / 2, bot + bh / 2
            fillPoly(bb, { { cx, cy - 2 * dr }, { cx + 2 * dr, cy }, { cx, cy + 2 * dr }, { cx - 2 * dr, cy } }, band_fg)
        else
            local step = math.min(bw * 0.9 / n, dr * 3)
            local dx = bx + (bw - step * (n - 1)) / 2
            for k = 0, n - 1 do
                UI.fillCircle(bb, math.floor(dx + k * step), bot + math.floor(bh / 2), dr, band_fg)
            end
        end
    end
    local cx = x + math.floor(w / 2)
    local cy = mini and y + math.floor((h + bh) / 2) or y + math.floor(h / 2)
    if mini then
        if solid then ornament(bb, n, c.s, cx, cy, math.floor(w * 0.24), fg, face)
        else pip(bb, c.s, cx, cy, math.floor(w * 0.13), fg) end
        return
    end
    if solid then
        ornament(bb, n, c.s, cx, cy, math.floor(w * 0.3), fg, face)
    else
        local rx, ry = w * 0.27, h * 0.21
        local r = w * (n <= 2 and 0.1 or n <= 3 and 0.085 or 0.072)
        for _, p in ipairs(PATTERN[n]) do
            pip(bb, c.s, cx + p[1] * rx, cy + p[2] * ry, r, fg, p[3])
        end
    end
end

--- A face-down card: dark hexagon with nested outlines and a diamond.
local function drawBack(bb, x, y, w, h, faded)
    local t = math.max(2, math.floor(w / 32))
    local field = faded and UI.LIGHT or UI.DARK
    fillPoly(bb, hexPts(x, y, w, h), faded and UI.LIGHT or UI.BLACK)
    fillPoly(bb, hexPts(x + t, y + t, w - 2 * t, h - 2 * t), field)
    for k = 1, 2 do
        local i = math.floor(w * (0.1 + 0.1 * k))
        local lt = math.max(1, math.floor(w / 50))
        fillPoly(bb, hexPts(x + i, y + i * 1.2, w - 2 * i, h - 2.4 * i), UI.WHITE)
        fillPoly(bb, hexPts(x + i + lt, y + i * 1.2 + lt, w - 2 * i - 2 * lt, h - 2.4 * i - 2 * lt), field)
    end
    local cx, cy, d = x + w / 2, y + h / 2, w * 0.12
    fillPoly(bb, { { cx, cy - d }, { cx + d, cy }, { cx, cy + d }, { cx - d, cy } }, UI.WHITE)
end

local PIPS = {
    { 5 }, { 1, 9 }, { 1, 5, 9 }, { 1, 3, 7, 9 }, { 1, 3, 5, 7, 9 }, { 1, 3, 4, 6, 7, 9 },
}

local function drawDie(bb, n, x, y, size, doubles)
    local t = math.max(2, math.floor(size / 16))
    local c = math.floor(size * 0.22)
    if not n then
        panel(bb, x, y, size, size, c, t, UI.LIGHT, UI.PALE)
        return
    end
    panel(bb, x, y, size, size, c, t, UI.BLACK, doubles and UI.BLACK or UI.WHITE)
    local cell = size / 3.4
    local off = (size - 3 * cell) / 2
    local pr = math.max(2, math.floor(size / 12))
    for _, p in ipairs(PIPS[n]) do
        local col, row = (p - 1) % 3, math.floor((p - 1) / 3)
        UI.fillCircle(bb, x + math.floor(off + cell * (col + 0.5)), y + math.floor(off + cell * (row + 0.5)), pr,
            doubles and UI.WHITE or UI.BLACK)
    end
end

-- screen ------------------------------------------------------------------------------

-- The whole screen is drawn here, header and buttons included.
local Screen = UI.Board:extend {}

function Screen:setup()
    local W, H = self.width, self.height
    local u = W / 100
    self.u = u
    self.pad = math.floor(2 * u)
    self.head_h = math.floor(H * 0.082)
    self.info_h = math.floor(H * 0.036)
    self.opp_h = math.floor(H * 0.185)
    self.tab_h = math.floor(H * 0.185)
    self.msg_h = math.floor(H * 0.075)
    self.foot_h = math.floor(H * 0.052)
    self.btn_h = math.floor(H * 0.072)
    self.bottom = math.floor(H * 0.014)
    self.hand_h = H - self.head_h - self.info_h - self.opp_h - self.tab_h - self.msg_h
        - self.foot_h - self.btn_h - self.bottom

    -- hand cards: five must fit across
    local gap = math.floor(1.6 * u)
    self.lift = math.floor(self.hand_h * 0.08)
    local ch = math.floor((self.hand_h - self.lift) * 0.88)
    local cw = math.floor(ch * 0.7)
    local max_w = math.floor((W - 2 * self.pad - gap * (MAX_HAND - 1)) / MAX_HAND)
    if cw > max_w then cw = max_w; ch = math.floor(cw / 0.7) end
    self.card_w, self.card_h, self.card_gap = cw, ch, gap

    self.opp_w = math.floor((W - 2 * self.pad - 2 * self.pad) / 3)
    local inner = self.opp_w - 2 * self.pad
    self.mini_w = math.floor(inner / (MAX_HAND + (MAX_HAND - 1) * 0.1))
    self.mini_h = math.floor(self.mini_w * 1.42)

    self.pile_h = math.floor(self.tab_h * 0.62)
    self.pile_w = math.floor(self.pile_h * 0.7)
    self.die = math.floor(self.pile_h * 0.46)

    local mono = { font = MONO }
    local monob = { font = MONO, bold = true }
    self.face_title = UI.fitFace({ "S A B A C C" }, W * 0.4, self.head_h * 0.42, monob)
    self.face_info = UI.fitFace({ "HAND 999  //  CORELLIAN SPIKE" }, W * 0.6, self.info_h * 0.5, mono)
    self.face_name = UI.fitFace({ "TAL MERROW", "OLD JESSA" }, inner, self.opp_h * 0.1, monob)
    self.face_small = UI.fitFace({ "DISCARDED A SYLOP", "CANTINA OWNER" }, inner, self.opp_h * 0.075, mono)
    self.face_label = UI.fitFace({ "SPIKE DICE", "DISCARD" }, self.pile_w * 1.5, self.tab_h * 0.075, mono)
    self.face_pot = UI.fitFace({ "999" }, self.pile_w * 0.8, self.pile_h * 0.24, monob)
    self.face_msg = UI.fitFace({ "Everyone checks. Spike dice: 2 and 3." }, W * 0.8, self.msg_h * 0.3)
    self.face_foot = UI.fitFace({ "BANTHAS WILD" }, W * 0.32, self.foot_h * 0.42, monob)
    self.face_foot_small = UI.fitFace({ "TAP A CARD", "CREDITS 999" }, W * 0.26, self.foot_h * 0.36, mono)
    self.faces_card = { num = UI.fitFace({ "+10", "−10" }, cw * 0.5, ch * 0.11 * 0.82, { font = MONO, bold = true }) }
    self.faces_pile = { num = UI.fitFace({ "+10", "−10" }, self.pile_w * 0.5, self.pile_h * 0.11 * 0.82, { font = MONO, bold = true }) }
    self.faces_mini = { num = UI.fitFace({ "+10", "−10" }, self.mini_w * 0.52, self.mini_h * 0.17 * 0.85, { font = MONO, bold = true }) }
end

function Screen:drawHeader(bb, x, y)
    local W, h, u = self.width, self.head_h, self.u
    local band = math.floor(h * 0.72)
    fillPoly(bb, { { x, y }, { x + W, y }, { x + W, y + band }, { x + W * 0.7, y + band }, { x + W * 0.66, y + h },
        { x + W * 0.34, y + h }, { x + W * 0.3, y + band }, { x, y + band } }, UI.BLACK)
    UI.drawText(bb, self.face_title, "S A B A C C", x, y + math.floor(h * 0.06), W, math.floor(h * 0.62), UI.WHITE, true)
    -- decorative script under the title, in the tab
    local sh = math.floor(h * 0.13)
    local sw = drawScript(bb, "CORELLIAN SPIKE", -10000, y, sh, UI.BLACK) -- measure only (off screen)
    drawScript(bb, "CORELLIAN SPIKE", x + math.floor((W - sw) / 2), y + h - math.floor(h * 0.22), sh, UI.MID)
    -- menu (three bars) and close (X)
    local my = y + math.floor(band / 2)
    local bw, bt = math.floor(5 * u), math.max(2, math.floor(u * 0.5))
    for k = -1, 1 do bb:paintRect(x + math.floor(3 * u), my + k * math.floor(1.6 * u) - math.floor(bt / 2), bw, bt, UI.WHITE) end
    local cx, d = x + W - math.floor(5.5 * u), math.floor(2.2 * u)
    UI.drawLine(bb, cx - d, my - d, cx + d, my + d, bt + 1, UI.WHITE)
    UI.drawLine(bb, cx - d, my + d, cx + d, my - d, bt + 1, UI.WHITE)
    -- small console ticks along the band
    for k = 0, 5 do
        bb:paintRect(x + math.floor((11 + k * 2.2) * u), y + band - math.floor(1.6 * u), math.floor(1.2 * u), math.floor(0.6 * u), UI.MID)
        bb:paintRect(x + W - math.floor((12 + k * 2.2) * u), y + band - math.floor(1.6 * u), math.floor(1.2 * u), math.floor(0.6 * u), UI.MID)
    end
    self.hits[#self.hits + 1] = { x = 0, y = 0, w = math.floor(14 * u), h = band, act = "menu" }
    self.hits[#self.hits + 1] = { x = W - math.floor(14 * u), y = 0, w = math.floor(14 * u), h = band, act = "close" }
end

function Screen:drawInfo(bb, x, y)
    local g, W, pad, h = self.app.game, self.width, self.pad, self.info_h
    UI.drawTextLeft(bb, self.face_info, string.format("HAND %02d", g.hand_no), x + pad, y, h, UI.BLACK, true)
    -- round markers: angled slots, filled up to the current round
    local sw, sh = math.floor(3.2 * self.u), math.floor(h * 0.36)
    local sx = x + W - pad - ROUNDS * (sw + math.floor(self.u))
    for i = 1, ROUNDS do
        local px = sx + (i - 1) * (sw + math.floor(self.u))
        local py = y + math.floor((h - sh) / 2)
        local pts = { { px + sh * 0.5, py }, { px + sw, py }, { px + sw - sh * 0.5, py + sh }, { px, py + sh } }
        if i <= g.round then fillPoly(bb, pts, UI.BLACK)
        else
            fillPoly(bb, pts, UI.LIGHT)
        end
    end
    local label = "ROUND " .. math.min(g.round, ROUNDS) .. "/" .. ROUNDS
    local lw = UI.measure(self.face_info, label)
    UI.drawTextLeft(bb, self.face_info, label, sx - math.floor(self.u * 1.5) - lw, y, h, UI.DARK)
    bb:paintRect(x + pad, y + h - 1, W - 2 * pad, 1, UI.LIGHT)
end

function Screen:drawOpponent(bb, p, seat, bx, by, bw, bh)
    local g, pad, u = self.app.game, self.pad, self.u
    local win = Sabacc.isWinner(g, seat)
    local reveal = g.phase == "done" and not p.out
    local c = math.floor(3 * u)
    local edge = p.out and UI.LIGHT or UI.BLACK
    local bg = win and UI.BLACK or UI.WHITE
    local fg = win and UI.WHITE or (p.out and UI.MID or UI.BLACK)
    panel(bb, bx, by, bw, bh, c, math.max(2, math.floor(u * 0.35)), edge, bg)
    -- name strip
    local sh = math.floor(bh * 0.2)
    fillPoly(bb, cutPts(bx, by, bw, sh, c), p.out and UI.LIGHT or UI.BLACK)
    UI.drawTextLeft(bb, self.face_name, p.name:upper(), bx + c + math.floor(u * 0.6), by, sh, UI.WHITE, true)
    if win then
        -- winner: whole panel inverted, with a rule under the name and a star
        bb:paintRect(bx + c, by + sh - math.max(2, math.floor(u * 0.3)), bw - 2 * c, math.max(2, math.floor(u * 0.3)), UI.WHITE)
        local sw = UI.measure(self.face_name, "★")
        UI.drawTextLeft(bb, self.face_name, "★", bx + bw - pad - sw, by, sh, UI.WHITE, true)
    end
    local ix = bx + pad
    local ly = by + sh + math.floor(bh * 0.04)
    local lh = math.floor(bh * 0.12)
    UI.drawTextLeft(bb, self.face_small, p.credits .. " CR", ix, ly, lh, fg, true)
    local cy = ly + lh + math.floor(bh * 0.03)
    local step = math.floor(self.mini_w * 1.1)
    for j, card in ipairs(p.hand) do
        local cx = ix + (j - 1) * step
        if reveal then
            if win then fillPoly(bb, hexPts(cx - 4, cy - 3, self.mini_w + 8, self.mini_h + 6), UI.WHITE) end
            drawCard(bb, card, cx, cy, self.mini_w, self.mini_h, self.faces_mini, true)
        else
            drawBack(bb, cx, cy, self.mini_w, self.mini_h, p.out)
        end
    end
    local st
    if p.out then st = "Junked"
    elseif reveal then st = Sabacc.evaluate(p.hand).name
    else st = p.last ~= "" and p.last or p.title end
    local sy = cy + self.mini_h + math.floor(bh * 0.02)
    local f, lines = UI.fitLines(st:upper(), bw - 2 * pad, math.floor(bh * 0.09), 1, { font = MONO })
    UI.drawTextLeft(bb, f, lines[1], ix, sy, by + bh - sy - math.floor(bh * 0.03), fg, reveal)
end

function Screen:drawTable(bb, x, y)
    local g, W, pad, u = self.app.game, self.width, self.pad, self.u
    local tx, tw, th = x + pad, W - 2 * pad, self.tab_h - pad
    panel(bb, tx, y, tw, th, math.floor(4 * u), math.max(2, math.floor(u * 0.35)), UI.BLACK, UI.PALE)
    -- console ticks and a script label in the frame
    for k = 0, 9 do
        bb:paintRect(tx + math.floor((6 + k * 1.6) * u), y + math.floor(1.2 * u), math.floor(0.6 * u), math.floor(1.2 * u), UI.MID)
    end
    drawScript(bb, "TABLE SEVEN", tx + tw - math.floor(22 * u), y + math.floor(1.2 * u), math.floor(1.2 * u), UI.MID)

    local label_h = math.floor(self.tab_h * 0.12)
    local top = y + math.floor((th - self.pile_h - label_h) / 2) + math.floor(u * 0.6)
    local px = tx + math.floor(5 * u)
    drawBack(bb, px, top, self.pile_w, self.pile_h)
    UI.drawText(bb, self.face_label, "DECK " .. #g.deck, px - pad, top + self.pile_h, self.pile_w + 2 * pad, label_h, UI.DARK)
    px = px + self.pile_w + math.floor(3 * u)
    local d = g.discard[#g.discard]
    if d then
        drawCard(bb, d, px, top, self.pile_w, self.pile_h, self.faces_pile)
    else
        frame(bb, hexPts, px, top, self.pile_w, self.pile_h, 2, UI.LIGHT, UI.PALE)
    end
    UI.drawText(bb, self.face_label, "DISCARD", px - pad, top + self.pile_h, self.pile_w + 2 * pad, label_h, UI.DARK)

    local ds = self.die
    local dx = tx + tw - math.floor(5 * u) - 2 * ds - math.floor(1.5 * u)
    local dy = top + math.floor((self.pile_h - ds) / 2)
    local doubles = g.dice and g.dice[1] == g.dice[2]
    drawDie(bb, g.dice and g.dice[1], dx, dy, ds, doubles)
    drawDie(bb, g.dice and g.dice[2], dx + ds + math.floor(1.5 * u), dy, ds, doubles)
    UI.drawText(bb, self.face_label, doubles and "SABACC SHIFT" or "SPIKE DICE", dx - pad, top + self.pile_h,
        2 * ds + math.floor(1.5 * u) + 2 * pad, label_h, UI.DARK, doubles)

    -- the pot: a notched chip between the piles and the dice
    local left, right = px + self.pile_w, dx
    local r = math.floor(math.min(self.pile_h * 0.44, (right - left) * 0.4))
    local cx, cy = math.floor((left + right) / 2), top + math.floor(self.pile_h / 2)
    UI.fillCircle(bb, cx, cy, r, UI.BLACK)
    for k = 0, 7 do
        local a = k * math.pi / 4 + math.pi / 8
        local nx, ny = cx + math.cos(a) * r * 0.86, cy + math.sin(a) * r * 0.86
        local q = r * 0.13
        fillPoly(bb, { { nx - q, ny - q }, { nx + q, ny - q }, { nx + q, ny + q }, { nx - q, ny + q } }, UI.WHITE)
    end
    UI.fillCircle(bb, cx, cy, math.floor(r * 0.68), UI.WHITE)
    UI.ringCircle(bb, cx, cy, math.floor(r * 0.6), math.max(2, math.floor(r * 0.05)), UI.BLACK)
    UI.drawText(bb, self.face_pot, tostring(g.pot), cx - r, cy - math.floor(r * 0.42), 2 * r, math.floor(r * 0.6), UI.BLACK, true)
    UI.drawText(bb, self.face_label, "POT", cx - r, cy + math.floor(r * 0.12), 2 * r, math.floor(r * 0.3), UI.DARK)
end

function Screen:drawMessage(bb, x, y)
    local g, W, pad, u, h = self.app.game, self.width, self.pad, self.u, self.msg_h
    -- corner brackets
    local bl, bt = math.floor(3 * u), math.max(2, math.floor(u * 0.35))
    local x0, x1, y0, y1 = x + pad, x + W - pad, y + math.floor(h * 0.1), y + h - math.floor(h * 0.1)
    bb:paintRect(x0, y0, bl, bt, UI.BLACK); bb:paintRect(x0, y0, bt, bl, UI.BLACK)
    bb:paintRect(x1 - bl, y1 - bt, bl, bt, UI.BLACK); bb:paintRect(x1 - bt, y1 - bl, bt, bl, UI.BLACK)
    local f, lines = UI.fitLines(g.msg or "", W - 2 * pad - 6 * u, math.floor(h * 0.66), 2)
    local lh = math.floor(h * 0.66 / 2)
    local start = y + math.floor((h - lh * #lines) / 2)
    for li, l in ipairs(lines) do
        UI.drawText(bb, f, l, x, start + (li - 1) * lh, W, lh, UI.BLACK)
    end
end

function Screen:drawHand(bb, x, y)
    local g, W = self.app.game, self.width
    local me = g.players[1]
    local reveal = g.phase == "done"
    if me.out and not reveal then
        UI.drawText(bb, self.face_foot, "HAND JUNKED", x, y, W, self.hand_h, UI.MID, true)
        return
    end
    local n = #me.hand
    local total = n * self.card_w + (n - 1) * self.card_gap
    local cx = x + math.floor((W - total) / 2)
    local base = y + self.lift + math.floor((self.hand_h - self.lift - self.card_h) / 2)
    for i, c in ipairs(me.hand) do
        local sel = self.app.sel == i
        local cy = sel and base - self.lift or base
        if sel then
            local o = math.floor(self.u * 0.6)
            frame(bb, hexPts, cx - 2 * o, cy - 2 * o, self.card_w + 4 * o, self.card_h + 4 * o, o, UI.BLACK, UI.WHITE)
        end
        drawCard(bb, c, cx, cy, self.card_w, self.card_h, self.faces_card)
        if g.new == i and not reveal then
            local mw = math.floor(self.card_w * 0.3)
            fillPoly(bb, { { cx + self.card_w / 2 - mw / 2, base + self.card_h + self.u }, { cx + self.card_w / 2 + mw / 2, base + self.card_h + self.u },
                { cx + self.card_w / 2, base + self.card_h + 2.4 * self.u } }, UI.BLACK)
        end
        self.hits[#self.hits + 1] = { x = cx - self.x0, y = y - self.y0, w = self.card_w, h = self.hand_h, card = i }
        cx = cx + self.card_w + self.card_gap
    end
end

function Screen:drawFooter(bb, x, y)
    local g, W, pad, u, h = self.app.game, self.width, self.pad, self.u, self.foot_h
    local me = g.players[1]
    bb:paintRect(x + pad, y, W - 2 * pad, 1, UI.LIGHT)
    UI.drawTextLeft(bb, self.face_foot_small, me.credits .. " CR", x + pad, y, h, UI.BLACK, true)
    local name = (me.out and "JUNKED" or Sabacc.evaluate(me.hand).name:upper())
    if Sabacc.isWinner(g, 1) then name = "★ " .. name end
    local nw = UI.measure(self.face_foot, name) + math.floor(6 * u)
    local nx = x + math.floor((W - nw) / 2)
    local ny, nh = y + math.floor(h * 0.14), math.floor(h * 0.72)
    fillPoly(bb, cutPts(nx, ny, nw, nh, math.floor(nh * 0.35)), UI.BLACK)
    UI.drawText(bb, self.face_foot, name, nx, ny, nw, nh, UI.WHITE, true)
    if g.phase == "act" or g.phase == "drop" then
        local hint = self.app.sel and "CARD PICKED" or (g.phase == "drop" and "TAP TO DROP" or "TAP A CARD")
        local tw = UI.measure(self.face_foot_small, hint)
        UI.drawTextLeft(bb, self.face_foot_small, hint, x + W - pad - tw, y, h, UI.DARK)
    end
end

function Screen:drawButtons(bb, x, y)
    local W, pad, u = self.width, self.pad, self.u
    local row = self.buttons[1]
    local gap = math.floor(1.6 * u)
    local bw = math.floor((W - 2 * pad - gap * (#row - 1)) / #row)
    local h = self.btn_h
    for k, b in ipairs(row) do
        local bx = x + pad + (k - 1) * (bw + gap)
        local enabled = b.enabled ~= false
        local c = math.floor(h * 0.3)
        local t = math.max(2, math.floor(u * 0.4))
        if not enabled then
            panel(bb, bx, y, bw, h, c, t, UI.LIGHT, UI.WHITE)
        elseif b.primary then
            panel(bb, bx, y, bw, h, c, t, UI.BLACK, UI.BLACK)
        else
            panel(bb, bx, y, bw, h, c, t, UI.BLACK, UI.WHITE)
        end
        local f = UI.fitFace({ b.text:upper() }, bw * 0.84, h * 0.34, { font = MONO, bold = true })
        UI.drawText(bb, f, b.text:upper(), bx, y, bw, h,
            not enabled and UI.LIGHT or (b.primary and UI.WHITE or UI.BLACK), true)
        if enabled then
            self.hits[#self.hits + 1] = { x = bx - self.x0, y = y - self.y0, w = bw, h = h, button = b }
        end
    end
end

function Screen:draw(bb, x, y)
    self.x0, self.y0 = x, y
    self.hits = {}
    self.buttons = { self.app:buttonRow() }
    local g = self.app.game
    self:drawHeader(bb, x, y)
    local cy = y + self.head_h
    self:drawInfo(bb, x, cy); cy = cy + self.info_h
    local oy = cy + math.floor(self.pad * 0.6)
    for k = 2, #g.players do
        self:drawOpponent(bb, g.players[k], k, x + self.pad + (k - 2) * (self.opp_w + self.pad), oy,
            self.opp_w, self.opp_h - self.pad)
    end
    cy = cy + self.opp_h
    self:drawTable(bb, x, cy); cy = cy + self.tab_h
    self:drawMessage(bb, x, cy); cy = cy + self.msg_h
    self:drawHand(bb, x, cy); cy = cy + self.hand_h
    self:drawFooter(bb, x, cy); cy = cy + self.foot_h
    self:drawButtons(bb, x, cy)
end

function Screen:tapAt(lx, ly)
    for _, h in ipairs(self.hits or {}) do
        if lx >= h.x and lx < h.x + h.w and ly >= h.y and ly < h.y + h.h then
            if h.card then return self.app:pick(h.card) end
            if h.button then return h.button.callback() end
            if h.act == "menu" then return self.app:showMenu() end
            if h.act == "close" then return self.app:onClose() end
        end
    end
end

-- app ---------------------------------------------------------------------------------

local HELP = [[Get your hand to exactly zero.

The deck has +1 to +10 and -1 to -10 in three suits, plus two sylops worth 0. Each card shows its number in the top band and one dot per point in the bottom band. Cards 1 to 6 show that many suit symbols (circles, triangles or squares); 7 to 10 are solid face cards with an ornate design. Positive cards are black, negative cards dark gray. The sylop is a black card with a ringed hexagon.

Each hand has three rounds. In a round you can:
• Gain: draw from the deck, then keep it or drop any one card (the new one too). A full hand of 5 must drop one.
• Take discard: tap one of your cards, then take the face-up discard in its place
• Discard: tap a card and drop it
• Stand: keep your hand

Then bet: check, bet 10 or junk (fold). Two spike dice roll after betting. On doubles, a Sabacc Shift replaces every hand with new cards.

A hand totalling zero is a Sabacc. Best first: Pure Sabacc (two sylops), Full Sabacc (+10 +10 -10 -10 and a sylop), Fleet (four of a kind and a sylop), Yee-Haa (pair and a sylop), Rhylet (three of a kind and a pair), Squadron (four of a kind), Banthas Wild (three of a kind), Rule of Two (two pairs), Sabacc Pair (like +5 -5), any other Sabacc.

Otherwise the hand closest to zero wins, positive beating negative. The winner takes the pot.]]

local App = UI.FullscreenApp:extend {
    name = "sabacc_app",
    title = "Sabacc",
    help_text = HELP,
}

function App:setup()
    if not self.game then
        local saved = Store.get(SAVE_KEY)
        if type(saved) == "table" and type(saved.players) == "table" and #saved.players == #ROSTER + 1 then
            self.game = saved
        else
            self.game = Sabacc.newTable()
        end
    end
    self.sel = nil
end

function App:save()
    Store.set(SAVE_KEY, self.game)
end

function App:pick(i)
    if self.game.phase ~= "act" and self.game.phase ~= "drop" then return end
    self.sel = self.sel ~= i and i or nil
    self:refresh()
end

function App:doAct(kind)
    if Sabacc.act(self.game, kind, self.sel) then
        self.sel = nil
        self:save()
    end
    self:refresh()
end

function App:doBet(kind)
    if Sabacc.bet(self.game, kind) then self:save() end
    self:refresh()
end

function App:newTable()
    self.game = Sabacc.newTable()
    self.sel = nil
    self:save()
    self:rebuild()
    UIManager:setDirty(self, function() return "full", self.dimen end)
end

function App:buttonRow()
    local g, me = self.game, self.game.players[1]
    if g.phase == "act" then
        return {
            { text = "Gain", callback = function() self:doAct("gain") end },
            { text = "Take discard", enabled = self.sel ~= nil and #g.discard > 0, callback = function() self:doAct("swap") end },
            { text = "Discard", enabled = self.sel ~= nil and #me.hand > 1, callback = function() self:doAct("discard") end },
            { text = "Stand", primary = true, callback = function() self:doAct("stand") end },
        }
    elseif g.phase == "drop" then
        return {
            { text = "Keep", primary = true, enabled = #me.hand <= MAX_HAND, callback = function() self:doAct("keep") end },
            { text = "Drop", enabled = self.sel ~= nil, callback = function() self:doAct("drop") end },
        }
    elseif g.phase == "bet" then
        return {
            { text = "Check", primary = true, callback = function() self:doBet("check") end },
            { text = "Bet " .. RAISE, enabled = me.credits >= RAISE, callback = function() self:doBet("bet") end },
            { text = "Junk", callback = function() self:doBet("junk") end },
        }
    elseif g.phase == "call" then
        return {
            { text = "Call " .. RAISE, primary = true, enabled = me.credits >= RAISE, callback = function() self:doBet("call") end },
            { text = "Junk", callback = function() self:doBet("junk") end },
        }
    elseif g.phase == "done" then
        return { { text = "Next hand", primary = true, callback = function()
            Sabacc.newHand(g)
            self:save()
            self:refresh()
        end } }
    end
    return { { text = "New table", primary = true, callback = function() self:newTable() end } }
end

--- The whole screen is one drawn console (no stock title bar or buttons).
function App:rebuild()
    if self[1] then self[1]:free() end
    self[1] = Screen:new { width = self.dimen.w, height = self.dimen.h, app = self }
    -- expose the current buttons (tests and the emulator driver press them by text)
    self[1].buttons = { self:buttonRow() }
end

function App:menuItems()
    return { { text = "New table (reset credits)", callback = function() self:newTable() end } }
end

function Sabacc.launch()
    UIManager:show(App:new {})
end

Sabacc.App = App -- exposed for tests

return Sabacc
