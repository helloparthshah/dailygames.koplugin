--[[
Sabacc: Corellian Spike, played offline against three computer players.
Unlike the other games it needs no network and is not a daily puzzle: play as
many hands as you like; credits and the Sabacc Pot carry over.

Rules: the Outer Rim Sabacc League (ORSL) rules, as given in "Sabacc:
Corellian Spike" v1.1 by Ender Smith (CC-BY-SA 2.0), page 2, with the ORSL
winning hands from page 5.

  Deck: +1..+10 and -1..-10 three times each, plus two sylops (0); 62 cards.
  Ante: 20 to the Pot and 10 to the Sabacc Pot. The Pot goes to the winner of
    the hand; the Sabacc Pot rides until someone wins with a hand of exactly 0.
  Deal: 2 cards each, top card of the deck face up as the discard pile.
  Three rounds, each with three phases, starting at the dealer's left:
    Trading: buy from the deck (10), buy from the discard (20; if the discard
      pile is empty, the top card of the deck is discarded first), trade from
      the deck (free: discard one, draw one), trade from the discard (free:
      take the top discard, discard one), or stand.
    Betting: the bet starts at 0. Check (if no one has raised), raise, call, or
      junk (fold: hand to the junk pile and a 10 penalty into the Pot; you must
      junk if you can't call). It goes round until everyone has matched the bet
      or junked. If only one player remains, they win at once.
    Spike: two dice are rolled; on doubles every player discards their hand and
      is dealt a new hand of the same size.
  After 3 rounds the best hand wins (see Sabacc.evaluate).

The engine is plain data (saved with Store) and is tested without the UI.
Raises are offered in steps of 10 and 20, and at most three raises are allowed
per betting phase, so hands keep moving on an e-reader.
]]

local UIManager = require("ui/uimanager")

local Store = require("dailygames/store")
local UI = require("dailygames/ui")

local Sabacc = {}

local POT_ANTE, SABACC_ANTE = 20, 10
local BUY_DECK, BUY_DISCARD = 10, 20
local JUNK_PENALTY = 10
local RAISES = { 10, 20 } -- what the computer players raise by
local STEP = 10 -- your raise picker moves in steps of this
local ROUNDS, START = 3, 300
local SEATS = 4
local SAVE_KEY = "sabacc/orsl"

Sabacc.POT_ANTE, Sabacc.SABACC_ANTE, Sabacc.BUY_DECK, Sabacc.BUY_DISCARD = POT_ANTE, SABACC_ANTE, BUY_DECK, BUY_DISCARD
Sabacc.JUNK_PENALTY, Sabacc.RAISES, Sabacc.ROUNDS, Sabacc.START = JUNK_PENALTY, RAISES, ROUNDS, START

-- The regulars: each new table seats three of them at random, and a player
-- who runs out of credits leaves and a newcomer takes the seat.
-- bold: how readily a player raises (cautious 0.25 .. reckless 0.8)
local ROSTER = {
    { name = "Tal Merrow", title = "Smuggler", bold = 0.65,
        story = "Swears every cargo he flies is legitimate. Learned sabacc in a freighter hold, where the loser scrubbed the engines.",
        style = "Bold: bets strong hands hard and bluffs now and then." },
    { name = "K-7 Unit", title = "Protocol droid", bold = 0.35,
        story = "Its owner lost it in a card game. It has been trying to win itself back ever since, one cautious hand at a time.",
        style = "Cautious: plays the odds to the decimal and rarely bluffs." },
    { name = "Old Jessa", title = "Cantina owner", bold = 0.5,
        story = "Runs the cantina where this table sits. She has seen every trick in the galaxy and still charges for the drinks.",
        style = "Steady: plays her cards straight and calls fair bets." },
    { name = "Varro Quill", title = "Bounty hunter", bold = 0.8,
        story = "Between contracts and bored. He plays the way he hunts: patient, until suddenly he isn't.",
        style = "Reckless: raises big and often; easy to provoke, hard to read." },
    { name = "Nessa Dray", title = "Freighter pilot", bold = 0.55,
        story = "Saving for a ship of her own. Every pot she wins is another part for the hyperdrive.",
        style = "Balanced: takes calculated risks when the pot is worth it." },
    { name = "Brakk", title = "Mercenary", bold = 0.75,
        story = "More scars than credits, and proud of both. Treats every hand like a firefight.",
        style = "Aggressive: pushes chips forward and dares you to follow." },
    { name = "Ilsa Venn", title = "Card shark", bold = 0.6,
        story = "Works the high-stakes tables from system to system. Her smile is the same with Pure Sabacc or nothing at all.",
        style = "Tricky: the likeliest to bluff when the table goes quiet." },
    { name = "B3-L Unit", title = "Croupier droid", bold = 0.3,
        story = "Dealt cards at a casino for forty years. Still adjusting to the idea that it is no longer the house.",
        style = "Careful: folds weak hands fast and bets only on strength." },
    { name = "Doran Pike", title = "Moisture farmer", bold = 0.25,
        story = "In town for supplies, with a little left over. Every credit he bets is one the farm will miss.",
        style = "Very cautious: hardly ever raises. When he does, believe him." },
    { name = "Mira Sol", title = "Senator's aide", bold = 0.45,
        story = "Says she plays to relax. Keeps very detailed notes on everyone at the table, just in case.",
        style = "Watchful: calls when she smells a bluff, bets when she's sure." },
}
Sabacc.ROSTER = ROSTER

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
    return c.v == 0 and "a sylop" or signed(c.v)
end

-- hands ------------------------------------------------------------------------

local function sortedValues(hand)
    local vs = {}
    for _, c in ipairs(hand) do vs[#vs + 1] = c.v end
    table.sort(vs)
    return vs
end

local function exactly(vs, list)
    if #vs ~= #list then return false end
    table.sort(list)
    for i = 1, #vs do if vs[i] ~= list[i] then return false end end
    return true
end

--- Ranks a hand under the ORSL winning hands. Returns
-- { zero, sum, rank, name, key }: lower rank wins, then the lower key
-- (compared item by item; see Sabacc.compare).
--   1 Pure Sabacc       two sylops, nothing else
--   2 Full Sabacc       −10 −10 0 +10 +10
--   3 Yee-Haa           zero with a pair and a sylop (lowest pair wins)
--   4 Rhylet            zero, five cards: three of a kind of one sign and a
--                       pair of the other (lowest three of a kind wins)
--   5 Straight Staves   +7 −8 −9 +10, or the inverse
--   6 Squadron          zero with four of a kind (lowest wins)
--   7 Gee Whiz          +1 +2 +3 +4 −10, or the inverse
--   8 Straight Khyron   zero, a run of four (lowest run wins)
--   9 Rule of Two       zero with two pairs (lowest pairs win)
--  10 Sabacc            zero with one pair (lowest pair wins)
--  11 Sabacc            any other zero
--  12 Nulrhek           not zero
-- "Of a kind", pairs and runs go by a card's number, whatever its sign.
-- Then the tiebreaks: a Sabacc with most cards, highest positive sum, highest
-- positive card; a Nulrhek closest to zero, positive sum, most cards, highest
-- positive sum, highest positive card. Still tied: a blind card draw.
function Sabacc.evaluate(hand)
    local n, sum, possum, maxpos, syl = #hand, 0, 0, 0, 0
    local count, signs = {}, {}
    for _, c in ipairs(hand) do
        sum = sum + c.v
        if c.v > 0 then
            possum = possum + c.v
            if c.v > maxpos then maxpos = c.v end
        end
        if c.v == 0 then
            syl = syl + 1
        else
            local a = math.abs(c.v)
            count[a] = (count[a] or 0) + 1
            signs[a] = signs[a] or {}
            signs[a][c.v > 0 and "pos" or "neg"] = (signs[a][c.v > 0 and "pos" or "neg"] or 0) + 1
        end
    end
    local generic = { -n, -possum, -maxpos }
    local function result(rank, name, key)
        key = key or {}
        if rank <= 11 then
            for _, k in ipairs(generic) do key[#key + 1] = k end
        end
        return { zero = sum == 0, sum = sum, rank = rank, name = name, key = key }
    end
    if sum ~= 0 then
        return result(12, "Nulrhek " .. signed(sum), { math.abs(sum), sum > 0 and 0 or 1, -n, -possum, -maxpos })
    end
    local vs = sortedValues(hand)
    local pairs_, fours, kinds = {}, {}, {}
    for a, k in pairs(count) do
        kinds[#kinds + 1] = a
        if k >= 2 then pairs_[#pairs_ + 1] = a end
        if k >= 4 then fours[#fours + 1] = a end
    end
    table.sort(pairs_); table.sort(fours); table.sort(kinds)
    if n == 2 and syl == 2 then return result(1, "Pure Sabacc") end
    if exactly(vs, { -10, -10, 0, 10, 10 }) then return result(2, "Full Sabacc") end
    if syl >= 1 and #pairs_ >= 1 then return result(3, "Yee-Haa", { pairs_[1] }) end
    if n == 5 and syl == 0 and #kinds == 2 then
        for _, a in ipairs(kinds) do
            local b = kinds[1] == a and kinds[2] or kinds[1]
            local sa, sb = signs[a], signs[b]
            if count[a] == 3 and count[b] == 2
                and ((sa.pos == 3 and sb.neg == 2) or (sa.neg == 3 and sb.pos == 2)) then
                return result(4, "Rhylet", { a })
            end
        end
    end
    if exactly(vs, { 7, -8, -9, 10 }) or exactly(vs, { -7, 8, 9, -10 }) then return result(5, "Straight Staves") end
    if #fours >= 1 then return result(6, "Squadron", { fours[1] }) end
    if exactly(vs, { 1, 2, 3, 4, -10 }) or exactly(vs, { -1, -2, -3, -4, 10 }) then return result(7, "Gee Whiz") end
    if n == 4 and syl == 0 and #kinds == 4 and kinds[4] - kinds[1] == 3 then
        return result(8, "Straight Khyron", { kinds[1] })
    end
    if #pairs_ >= 2 then return result(9, "Rule of Two", { pairs_[1], pairs_[2] }) end
    if #pairs_ == 1 then return result(10, "Sabacc", { pairs_[1] }) end
    return result(11, "Sabacc")
end

--- -1 if hand evaluation a beats b, 1 if b beats a, 0 if tied.
function Sabacc.compare(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank and -1 or 1 end
    for i = 1, math.max(#a.key, #b.key) do
        local x, y = a.key[i] or 0, b.key[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
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
local function nextSeat(seat) return seat % SEATS + 1 end

local function active(g)
    local list = {}
    for _, p in ipairs(g.players) do
        if not p.out then list[#list + 1] = p end
    end
    return list
end

function Sabacc.owe(g, p)
    p = p or you(g)
    return (g.bet or 0) - (p.paid or 0)
end

--- A random regular who isn't already at the table.
local function newcomer(g)
    local seated, free = {}, {}
    for _, p in ipairs(g.players) do seated[p.name] = true end
    for _, r in ipairs(ROSTER) do
        if not seated[r.name] then free[#free + 1] = r end
    end
    local r = free[math.random(#free)]
    return { name = r.name, title = r.title, bold = r.bold, ai = true, credits = START }
end

--- A new table with three regulars picked at random; `credits` (optional) is
-- a list of starting credits per seat.
function Sabacc.newTable(credits)
    local g = { players = { { name = "You", credits = credits and credits[1] or START } },
        hand_no = 0, sabacc_pot = 0, dealer = SEATS }
    for i = 2, SEATS do
        g.players[i] = newcomer(g)
        if credits then g.players[i].credits = credits[i] end
    end
    Sabacc.newHand(g, true)
    return g
end

local startTrading, advance

--- Deals a new hand; the dealer button moves one seat to the left.
function Sabacc.newHand(g, first)
    g.hand_no = g.hand_no + 1
    if not first then g.dealer = nextSeat(g.dealer) end
    g.deck, g.discard, g.junk = Sabacc.newDeck(), {}, {}
    g.pot, g.round, g.dice, g.winners, g.new, g.log = 0, 1, nil, nil, nil, {}
    g.phase = "busy" -- the engine is running; "trade" / "bet" mean it's your move
    local arrivals = {}
    for i, p in ipairs(g.players) do
        local fresh = false
        if p.ai and p.credits < POT_ANTE + SABACC_ANTE + 40 then
            -- out of credits: they leave, and a newcomer takes the seat
            local q = newcomer(g)
            arrivals[#arrivals + 1] = string.format("%s leaves the table; %s sits down.", p.name, q.name)
            g.players[i], p, fresh = q, q, true
        end
        p.out, p.hand, p.last, p.paid, p.acted = false, {}, fresh and "Just sat down." or "", 0, false
    end
    if you(g).credits < POT_ANTE + SABACC_ANTE then
        g.phase = "broke"
        g.msg = "You can't cover the ante. Start a new table to keep playing."
        return g
    end
    for _, p in ipairs(g.players) do
        p.credits = p.credits - POT_ANTE - SABACC_ANTE
        g.pot = g.pot + POT_ANTE
        g.sabacc_pot = g.sabacc_pot + SABACC_ANTE
        p.hand = { draw(g), draw(g) }
    end
    g.discard[#g.discard + 1] = draw(g)
    local dealer = g.dealer == 1 and "You deal" or (g.players[g.dealer].name .. " deals")
    g.log = {}
    g.log[1] = string.format("Hand %d. %s. Everyone antes %d to the Pot and %d to the Sabacc Pot.",
        g.hand_no, dealer, POT_ANTE, SABACC_ANTE)
    for _, t in ipairs(arrivals) do g.log[#g.log + 1] = t end
    startTrading(g)
    return g
end

-- moves (shared by you and the computer players) ---------------------------------

local function takeDiscard(g)
    if #g.discard == 0 then g.discard[1] = draw(g) end
    return table.remove(g.discard)
end

--- Applies a trading move for player p. Returns a description, or nil if the
-- move isn't allowed. i is the hand card to give up for the two trades.
local function applyTrade(g, p, kind, i)
    if kind == "buy_deck" then
        if p.credits < BUY_DECK then return end
        p.credits, g.pot = p.credits - BUY_DECK, g.pot + BUY_DECK
        local c = draw(g)
        p.hand[#p.hand + 1] = c
        return "bought from the deck", #p.hand, c
    elseif kind == "buy_discard" then
        if p.credits < BUY_DISCARD then return end
        p.credits, g.pot = p.credits - BUY_DISCARD, g.pot + BUY_DISCARD
        local c = takeDiscard(g)
        p.hand[#p.hand + 1] = c
        return "bought " .. cardName(c) .. " from the discard", #p.hand, c
    elseif kind == "trade_deck" then
        if not (i and p.hand[i]) then return end
        local old = table.remove(p.hand, i)
        g.discard[#g.discard + 1] = old
        local c = draw(g)
        table.insert(p.hand, i, c)
        return "traded " .. cardName(old) .. " for a card from the deck", i, c
    elseif kind == "trade_discard" then
        if not (i and p.hand[i]) then return end
        local c = takeDiscard(g)
        local old = p.hand[i]
        p.hand[i] = c
        g.discard[#g.discard + 1] = old
        return "traded " .. cardName(old) .. " for " .. cardName(c) .. " from the discard", i, c
    elseif kind == "stand" then
        return "stood"
    end
end

local function pay(g, p, amount)
    p.credits = p.credits - amount
    p.paid = p.paid + amount
    g.pot = g.pot + amount
end

local function junk(g, p)
    p.out = true
    for _, c in ipairs(p.hand) do g.junk[#g.junk + 1] = c end
    p.hand = {}
    local fee = math.min(JUNK_PENALTY, p.credits)
    p.credits, g.pot = p.credits - fee, g.pot + fee
    p.acted = true
end

--- Applies a betting move for player p ("check", "call", "raise" by amount,
--- "junk"). Returns a description, or nil if it isn't allowed.
local function applyBet(g, p, kind, amount)
    local owe = Sabacc.owe(g, p)
    if kind == "check" then
        if owe ~= 0 then return end
        p.acted = true
        return "checked"
    elseif kind == "call" then
        if owe <= 0 or p.credits < owe then return end
        pay(g, p, owe)
        p.acted = true
        return "called " .. owe
    elseif kind == "raise" then
        if not amount or amount <= 0 or p.credits < owe + amount then return end
        pay(g, p, owe + amount)
        g.bet = g.bet + amount
        g.raises = g.raises + 1
        for _, q in ipairs(g.players) do q.acted = false end
        p.acted = true
        return "raised the bet to " .. g.bet
    elseif kind == "junk" then
        junk(g, p)
        return "junked"
    end
end

-- computer players ----------------------------------------------------------------

--- How good a hand looks, 0..1.
local function strength(hand)
    local e = Sabacc.evaluate(hand)
    if e.zero then return 1 - (e.rank - 1) * 0.03 end
    return math.max(0, 0.6 - math.abs(e.sum) * 0.07 + (e.sum > 0 and 0.02 or 0))
end

local function sampleDeck(g, k)
    local out = {}
    for _ = 1, k do
        if #g.deck == 0 then break end
        out[#out + 1] = g.deck[math.random(#g.deck)]
    end
    return out
end

local function aiTrade(g, p)
    local opts = { { k = "stand", s = strength(p.hand) } }
    local top = g.discard[#g.discard]
    local samples = sampleDeck(g, 12)
    local function avg(fn)
        if #samples == 0 then return -1 end
        local t = 0
        for _, c in ipairs(samples) do t = t + fn(c) end
        return t / #samples
    end
    for i = 1, #p.hand do
        if top then
            local h = { unpack(p.hand) }
            h[i] = top
            opts[#opts + 1] = { k = "trade_discard", i = i, s = strength(h) }
        end
        opts[#opts + 1] = { k = "trade_deck", i = i, s = avg(function(c)
            local h = { unpack(p.hand) }
            h[i] = c
            return strength(h)
        end) }
    end
    local reserve = 60
    if #p.hand < 6 then
        if top and p.credits >= BUY_DISCARD + reserve then
            local h = { unpack(p.hand) }
            h[#h + 1] = top
            opts[#opts + 1] = { k = "buy_discard", s = strength(h) - 0.12 }
        end
        if p.credits >= BUY_DECK + reserve then
            opts[#opts + 1] = { k = "buy_deck", s = avg(function(c)
                local h = { unpack(p.hand) }
                h[#h + 1] = c
                return strength(h)
            end) - 0.06 }
        end
    end
    table.sort(opts, function(a, b) return a.s > b.s end)
    local o = (math.random() < 0.15 and opts[2]) or opts[1]
    local text = applyTrade(g, p, o.k, o.i)
    p.last = text:sub(1, 1):upper() .. text:sub(2) .. "."
end

-- How a computer player bets, after poker AIs:
--  * equity: its chance of winning, from quick simulations of the rest of the
--    hand using only cards it can't see (hidden hands, deck, junk), the trades
--    still to come and the chance of a Sabacc Shift;
--  * pot odds: it calls when equity is worth the price (call 100 into a pot
--    of 300 needs about 25%), so a big raise doesn't scare off a good hand;
--  * defence: borderline hands sometimes call anyway, so raising big can't
--    simply steal every pot;
--  * bet sizing in proportion to the pot, value bets with strong hands and
--    the odd bluff, by personality (bold);
--  * respect for big raises: a raise that's large against the pot usually
--    means a strong hand, so equity is discounted by the raise's size;
--  * a read on you: the more often you raise, the less it believes you.

--- The cards player p can't see: the deck, other hands, the junk pile and the
--- discard pile under the top card.
local function unseenBy(g, p)
    local pool = {}
    for _, c in ipairs(g.deck) do pool[#pool + 1] = c end
    for _, q in ipairs(g.players) do
        if q ~= p then for _, c in ipairs(q.hand) do pool[#pool + 1] = c end end
    end
    for _, c in ipairs(g.junk) do pool[#pool + 1] = c end
    for i = 1, #g.discard - 1 do pool[#pool + 1] = g.discard[i] end
    return pool
end

--- The best hand after taking card c (keep, swap one card, or add it).
local function improve(hand, c)
    local best, be = hand, Sabacc.evaluate(hand)
    local function try(h)
        local e = Sabacc.evaluate(h)
        if Sabacc.compare(e, be) < 0 then best, be = h, e end
    end
    for i = 1, #hand do
        local h = { unpack(hand) }
        h[i] = c
        try(h)
    end
    if #hand < 5 then
        local h = { unpack(hand) }
        h[#h + 1] = c
        try(h)
    end
    return best
end

--- Player p's chance of winning the hand (0..1), by simulation.
function Sabacc.equity(g, p, sims)
    sims = sims or 80
    local sizes = {}
    for _, q in ipairs(g.players) do
        if q ~= p and not q.out then sizes[#sizes + 1] = #q.hand end
    end
    if #sizes == 0 then return 1 end
    local pool = unseenBy(g, p)
    local spikes = ROUNDS - g.round + 1 -- this round's spike dice and later ones
    local won = 0
    for _ = 1, sims do
        local n = #pool
        local function take()
            if n == 0 then return nil end
            local j = math.random(n)
            pool[j], pool[n] = pool[n], pool[j]
            n = n - 1
            return pool[n + 1]
        end
        local hands = { { unpack(p.hand) } }
        for k, size in ipairs(sizes) do
            local h = {}
            for _ = 1, size do h[#h + 1] = take() end
            hands[k + 1] = h
        end
        for step = 1, spikes do
            if math.random(6) == math.random(6) then -- a Sabacc Shift
                for _, h in ipairs(hands) do
                    for i = 1, #h do h[i] = take() or h[i] end
                end
            end
            if step < spikes then -- another trading phase: everyone improves
                for k, h in ipairs(hands) do
                    local c = take()
                    if c then hands[k] = improve(h, c) end
                end
            end
        end
        local mine, best, ties = Sabacc.evaluate(hands[1]), true, 1
        for k = 2, #hands do
            local c = Sabacc.compare(mine, Sabacc.evaluate(hands[k]))
            if c > 0 then best = false; break end
            if c == 0 then ties = ties + 1 end
        end
        if best then won = won + 1 / ties end
    end
    return won / sims
end

local function aiBet(g, p)
    -- equity is worked out once per betting phase (the hand doesn't change)
    local key = g.hand_no * 10 + g.round
    if p.eq_key ~= key then p.eq, p.eq_key = Sabacc.equity(g, p), key end
    local e = p.eq
    local owe, pot, b = Sabacc.owe(g, p), g.pot, p.bold
    local others = 0
    for _, q in ipairs(g.players) do
        if q ~= p and not q.out then others = others + 1 end
    end
    local fair = 1 / (others + 1) -- an even share of the pot
    local keen = 0.5 ^ g.raises -- each raise this phase halves the urge to raise again
    local function size(frac)
        local amt = math.max(10, math.floor(pot * frac / 10 + 0.5) * 10)
        -- mind the stake: only a near-certain hand risks most of its credits
        -- (even a perfect hand can be lost to a Sabacc Shift)
        local share = e >= 0.85 and 1 or (0.15 + 0.45 * e)
        local cap = math.max(10, math.floor(p.credits * share / 10) * 10)
        return math.min(amt, cap, math.floor((p.credits - owe) / 10) * 10)
    end
    local text
    if owe == 0 then
        if e > fair * (1.6 - b * 0.6) and math.random() < (0.4 + b * 0.5) * keen then
            text = applyBet(g, p, "raise", size(0.3 + e * 0.7)) -- value bet
        elseif e < fair * 0.6 and g.round < ROUNDS and math.random() < b * 0.2 * keen then
            text = applyBet(g, p, "raise", size(0.5)) -- bluff
        end
        text = text or applyBet(g, p, "check")
    else
        local need = owe / (pot + owe) -- pot odds
        -- a big raise says the raiser is probably strong: discount equity by
        -- the raise's size against the pot, less so against a frequent raiser
        local big = math.min(1, owe / math.max(10, pot - owe))
        e = e - 0.35 * big * fair * (1 - 2 * (g.read or 0))
        local luck = (math.random() - 0.5) * 0.08
        if e + luck >= need then
            if e > math.max(0.5, fair * 2) and math.random() < b * keen then
                text = applyBet(g, p, "raise", size(0.4 + e * 0.6)) -- re-raise a strong hand
            end
            text = text or applyBet(g, p, "call")
        elseif e + luck >= need * 0.75 and math.random() < 0.15 + b * 0.3 then
            text = applyBet(g, p, "call") -- defend: don't let big raises steal every pot
        end
        text = text or applyBet(g, p, "junk")
    end
    p.last = text:sub(1, 1):upper() .. text:sub(2) .. "."
    if text == "junked" or text:find("^raised") then g.log[#g.log + 1] = p.name .. " " .. text .. "." end
end

-- hand flow ------------------------------------------------------------------------

local function award(g, w, how)
    local seat
    for i, p in ipairs(g.players) do if p == w then seat = i end end
    local won = g.pot
    w.credits = w.credits + g.pot
    g.pot = 0
    local e = #w.hand > 0 and Sabacc.evaluate(w.hand) or nil
    local extra = ""
    if e and e.zero and g.sabacc_pot > 0 then
        w.credits = w.credits + g.sabacc_pot
        extra = string.format(" and the Sabacc Pot of %d", g.sabacc_pot)
        g.sabacc_pot = 0
    end
    local who = w.ai and w.name or "You"
    local before = #g.log > 0 and (table.concat(g.log, " ") .. " ") or ""
    g.log = {}
    g.msg = before .. string.format("%s %s %s the Pot of %d%s%s.", how, who, w.ai and "wins" or "win", won, extra,
        e and how:find("Showdown") and (" with " .. e.name) or "")
    g.winners = { seat }
    g.phase = "done"
end

local function showdown(g)
    local best, tied = nil, {}
    for _, p in ipairs(active(g)) do
        local e = Sabacc.evaluate(p.hand)
        local c = best and Sabacc.compare(e, best) or -1
        if c < 0 then best, tied = e, { p }
        elseif c == 0 then tied[#tied + 1] = p end
    end
    local how = "Showdown:"
    -- still tied: a single blind card draw, highest card wins
    local guard = 0
    while #tied > 1 and guard < 10 do
        guard = guard + 1
        local top, next_tied = nil, {}
        for _, p in ipairs(tied) do
            local c = draw(g)
            g.discard[#g.discard + 1] = c
            if not top or c.v > top then top, next_tied = c.v, { p }
            elseif c.v == top then next_tied[#next_tied + 1] = p end
        end
        tied = next_tied
        how = "Showdown, settled by a blind card draw:"
    end
    award(g, tied[1], how)
end

local function onlyOneLeft(g)
    local left = active(g)
    if #left == 1 then
        award(g, left[1], "Everyone else junked.")
        return true
    end
end

local function spike(g)
    local a, b = math.random(6), math.random(6)
    g.dice = { a, b }
    local text = string.format("Spike dice: %d and %d.", a, b)
    if a == b then
        text = text .. " Doubles: a Sabacc Shift deals everyone a new hand."
        for _, p in ipairs(active(g)) do
            local e = Sabacc.evaluate(p.hand)
            if e.zero then -- say what the shift took
                text = text .. (p.ai and (" It took " .. p.name .. "'s ") or " It took your ") .. e.name .. "."
            end
        end
        for _, p in ipairs(active(g)) do
            local n = #p.hand
            for _, c in ipairs(p.hand) do g.discard[#g.discard + 1] = c end
            p.hand = {}
            for _ = 1, n do p.hand[#p.hand + 1] = draw(g) end
        end
        g.new = nil
    end
    g.round = g.round + 1
    g.log[#g.log + 1] = text
    if g.round > ROUNDS then return showdown(g) end
    startTrading(g)
end

local function startBetting(g)
    g.stage = "bet"
    g.bet, g.raises = 0, 0
    for _, p in ipairs(g.players) do p.paid, p.acted = 0, false end
    g.cur = nextSeat(g.dealer)
    advance(g)
end

function startTrading(g)
    g.stage = "trade"
    g.cur = nextSeat(g.dealer)
    g.traded = 0
    advance(g)
end

--- Runs the computer players until it's your move (or the hand ends).
function advance(g)
    for _ = 1, 5000 do
        if g.phase == "done" or g.phase == "broke" then return end
        if onlyOneLeft(g) then return end
        if g.stage == "trade" then
            if g.traded >= SEATS then return startBetting(g) end
            local p = g.players[g.cur]
            if p.out then
                g.traded, g.cur = g.traded + 1, nextSeat(g.cur)
            elseif not p.ai then
                g.phase = "trade"
                g.log[#g.log + 1] = string.format("Round %d: your trade.", g.round)
                g.msg = table.concat(g.log, " ")
                g.log = {}
                return
            else
                aiTrade(g, p)
                g.traded, g.cur = g.traded + 1, nextSeat(g.cur)
            end
        else
            local done = true
            for _, q in ipairs(active(g)) do
                if not q.acted or q.paid ~= g.bet then done = false end
            end
            if done then return spike(g) end
            local p = g.players[g.cur]
            if p.out or (p.acted and p.paid == g.bet) then
                g.cur = nextSeat(g.cur)
            elseif not p.ai then
                g.phase = "bet"
                local owe = Sabacc.owe(g, p)
                g.log[#g.log + 1] = owe == 0 and string.format("Round %d betting: check, raise or junk.", g.round)
                    or string.format("The bet is %d; you owe %d.", g.bet, owe)
                    .. (p.credits < owe and " You can't cover it, so you must junk." or "")
                g.msg = table.concat(g.log, " ")
                g.log = {}
                return
            else
                aiBet(g, p)
                g.cur = nextSeat(g.cur)
            end
        end
    end
end

--- Your trading move: "buy_deck", "buy_discard", "trade_deck" (card i),
-- "trade_discard" (card i) or "stand". Returns false if it isn't allowed.
function Sabacc.trade(g, kind, i)
    if g.phase ~= "trade" then return false end
    local me = you(g)
    local text, at = applyTrade(g, me, kind, i)
    if not text then return false end
    me.last = "You " .. text .. "."
    g.new = at
    g.log[#g.log + 1] = me.last
    g.traded, g.cur = g.traded + 1, nextSeat(g.cur)
    g.phase = "busy"
    advance(g)
    return true
end

--- Your betting move: "check", "call", "raise" (with amount) or "junk".
function Sabacc.bet(g, kind, amount)
    if g.phase ~= "bet" then return false end
    local me = you(g)
    local text = applyBet(g, me, kind, amount)
    if not text then return false end
    -- the table's read on you: how much more often than usual you raise
    g.your_turns = (g.your_turns or 0) + 1
    if kind == "raise" then g.your_raises = (g.your_raises or 0) + 1 end
    if g.your_turns >= 5 then
        g.read = math.max(0, math.min(0.3, (g.your_raises or 0) / g.your_turns - 0.2))
    end
    me.last = "You " .. text .. "."
    g.log[#g.log + 1] = me.last
    g.cur = nextSeat(g.cur)
    g.phase = "busy"
    advance(g)
    return true
end

Sabacc._aiBet = function(g, p) return aiBet(g, p) end -- for tests

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
local SHOWN = 5 -- cards that fit side by side; larger hands overlap
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
    local max_w = math.floor((W - 2 * self.pad - gap * (SHOWN - 1)) / SHOWN)
    if cw > max_w then cw = max_w; ch = math.floor(cw / 0.7) end
    self.card_w, self.card_h, self.card_gap = cw, ch, gap

    self.opp_w = math.floor((W - 2 * self.pad - 2 * self.pad) / 3)
    local inner = self.opp_w - 2 * self.pad
    self.mini_w = math.floor(inner / (SHOWN + (SHOWN - 1) * 0.1))
    self.mini_h = math.floor(self.mini_w * 1.42)

    self.pile_h = math.floor(self.tab_h * 0.62)
    self.pile_w = math.floor(self.pile_h * 0.7)
    self.die = math.floor(self.pile_h * 0.46)

    local mono = { font = MONO }
    local monob = { font = MONO, bold = true }
    self.face_title = UI.fitFace({ "S A B A C C" }, W * 0.4, self.head_h * 0.42, monob)
    self.face_info = UI.fitFace({ "HAND 999  //  CORELLIAN SPIKE" }, W * 0.6, self.info_h * 0.5, mono)
    self.face_name = UI.fitFace({ "VARRO QUILL", "TAL MERROW", "DORAN PIKE" }, inner * 0.72, self.opp_h * 0.1, monob)
    self.face_small = UI.fitFace({ "DISCARDED A SYLOP", "CANTINA OWNER" }, inner, self.opp_h * 0.075, mono)
    self.face_label = UI.fitFace({ "SPIKE DICE", "DISCARD" }, self.pile_w * 1.5, self.tab_h * 0.075, mono)
    self.face_msg = UI.fitFace({ "Everyone checks. Spike dice: 2 and 3." }, W * 0.8, self.msg_h * 0.3)
    self.face_foot = UI.fitFace({ "BANTHAS WILD" }, W * 0.32, self.foot_h * 0.42, monob)
    self.face_tag = UI.fitFace({ "DEALER" }, W * 0.12, self.opp_h * 0.07, { font = MONO, bold = true })
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
    if g.dealer == seat then self:dealerTag(bb, bx + bw - pad, ly, lh, not win) end
    local cy = ly + lh + math.floor(bh * 0.03)
    local step = math.floor(self.mini_w * 1.1)
    if #p.hand > SHOWN then step = math.floor((bw - 2 * pad - self.mini_w) / (#p.hand - 1)) end
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

--- A small "DEALER" tag, right-aligned at rx (or left-aligned when right is false).
function Screen:dealerTag(bb, rx, y, h, inverted, left)
    local f = self.face_tag
    local label = "DEALER"
    local tw = UI.measure(f, label) + math.floor(2 * self.u)
    local th = math.floor(h * 0.6)
    local tx = left and rx or rx - tw
    local ty = y + math.floor((h - th) / 2)
    fillPoly(bb, cutPts(tx, ty, tw, th, math.floor(th * 0.3)), inverted and UI.BLACK or UI.WHITE)
    UI.drawText(bb, f, label, tx, ty, tw, th, inverted and UI.WHITE or UI.BLACK, true)
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
        -- empty: the rules say a buy or trade from it takes the top card of the deck
        frame(bb, hexPts, px, top, self.pile_w, self.pile_h, 2, UI.MID, UI.PALE)
        local ef = UI.fitFace({ "EMPTY" }, self.pile_w * 0.7, self.pile_h * 0.12, { font = MONO, bold = true })
        UI.drawText(bb, ef, "EMPTY", px, top, self.pile_w, self.pile_h, UI.DARK, true)
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
    -- six curved edge inserts that follow the rim, like a real chip
    local function arcSeg(a0, a1, r0, r1)
        local pts, steps = {}, 8
        for i = 0, steps do
            local a = a0 + (a1 - a0) * i / steps
            pts[#pts + 1] = { cx + math.cos(a) * r1, cy + math.sin(a) * r1 }
        end
        for i = steps, 0, -1 do
            local a = a0 + (a1 - a0) * i / steps
            pts[#pts + 1] = { cx + math.cos(a) * r0, cy + math.sin(a) * r0 }
        end
        return pts
    end
    local half = math.pi / 6 * 0.42
    for k = 0, 5 do
        local a = k * math.pi / 3 - math.pi / 2
        fillPoly(bb, arcSeg(a - half, a + half, r * 0.76, r * 0.93), UI.WHITE)
    end
    UI.fillCircle(bb, cx, cy, math.floor(r * 0.66), UI.WHITE)
    UI.ringCircle(bb, cx, cy, math.floor(r * 0.58), math.max(2, math.floor(r * 0.04)), UI.BLACK)
    local pf = UI.fitFace({ tostring(g.pot), "88" }, r * 0.86, r * 0.46, { font = MONO, bold = true })
    UI.drawText(bb, pf, tostring(g.pot), cx - r, cy - math.floor(r * 0.42), 2 * r, math.floor(r * 0.6), UI.BLACK, true)
    UI.drawText(bb, self.face_label, "POT", cx - r, cy + math.floor(r * 0.12), 2 * r, math.floor(r * 0.3), UI.DARK)
    UI.drawText(bb, self.face_label, "SABACC POT " .. g.sabacc_pot, cx - 3 * r, top + self.pile_h, 6 * r, label_h, UI.BLACK, true)
end

function Screen:drawMessage(bb, x, y)
    local g, W, pad, u, h = self.app.game, self.width, self.pad, self.u, self.msg_h
    -- corner brackets
    local bl, bt = math.floor(3 * u), math.max(2, math.floor(u * 0.35))
    local x0, x1, y0, y1 = x + pad, x + W - pad, y + math.floor(h * 0.1), y + h - math.floor(h * 0.1)
    bb:paintRect(x0, y0, bl, bt, UI.BLACK); bb:paintRect(x0, y0, bt, bl, UI.BLACK)
    bb:paintRect(x1 - bl, y1 - bt, bl, bt, UI.BLACK); bb:paintRect(x1 - bt, y1 - bl, bt, bl, UI.BLACK)
    local f, lines = UI.fitLines(g.msg or "", W - 2 * pad - 6 * u, math.floor(h * 0.8), 3)
    local lh = math.floor(h * 0.8 / math.max(2, #lines))
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
    local step = self.card_w + self.card_gap
    if n > SHOWN then step = math.floor((W - 2 * self.pad - self.card_w) / (n - 1)) end
    local total = (n - 1) * step + self.card_w
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
        -- overlapped cards are tapped on their visible strip
        local hw = i < n and math.min(step, self.card_w) or self.card_w
        self.hits[#self.hits + 1] = { x = cx - self.x0, y = y - self.y0, w = hw, h = self.hand_h, card = i }
        cx = cx + step
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
    if g.dealer == 1 then self:dealerTag(bb, x + pad + UI.measure(self.face_foot_small, me.credits .. " CR") + math.floor(2 * u), y, h, true, true) end
    local hint
    if g.phase == "trade" then hint = self.app.sel and "PICK HOW TO TRADE" or "TAP A CARD TO TRADE"
    elseif g.phase == "bet" then
        local owe = Sabacc.owe(g)
        if self.app.raise_by then hint = "SET YOUR RAISE"
        else hint = owe > 0 and ("YOU OWE " .. owe) or (g.bet > 0 and ("BET " .. g.bet) or "NO BET YET") end
    end
    if hint then
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
        local fg = not enabled and UI.LIGHT or (b.primary and UI.WHITE or UI.BLACK)
        local label = b.text:upper()
        if b.sub then
            local f = UI.fitFace({ label }, bw * 0.84, h * 0.28, { font = MONO, bold = true })
            UI.drawText(bb, f, label, bx, y + math.floor(h * 0.12), bw, math.floor(h * 0.46), fg, true)
            local fs = UI.fitFace({ b.sub:upper() }, bw * 0.8, h * 0.2, { font = MONO })
            UI.drawText(bb, fs, b.sub:upper(), bx, y + math.floor(h * 0.56), bw, math.floor(h * 0.3),
                not enabled and UI.LIGHT or (b.primary and UI.LIGHT or UI.DARK))
        else
            local f = UI.fitFace({ label }, bw * 0.84, h * 0.34, { font = MONO, bold = true })
            UI.drawText(bb, f, label, bx, y, bw, h, fg, true)
        end
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

-- winning hands chart ------------------------------------------------------------------

local function ex(...)
    local suits = { 1, 2, 3, 1, 2 }
    local h = {}
    for i, v in ipairs { ... } do h[i] = { v = v, s = v == 0 and 0 or suits[i] } end
    return h
end

-- The ORSL hands, best first, each with an example.
local HAND_CHART = {
    { "Pure Sabacc", "Two sylops, nothing else", ex(0, 0) },
    { "Full Sabacc", "−10 −10 0 +10 +10 exactly", ex(-10, -10, 0, 10, 10) },
    { "Yee-Haa", "Zero with a pair and a sylop", ex(0, 4, -4) },
    { "Rhylet", "Three of a kind and a pair of the other sign", ex(2, 2, 2, -3, -3) },
    { "Straight Staves", "+7 −8 −9 +10, or the inverse", ex(7, -8, -9, 10) },
    { "Squadron", "Zero with four of a kind", ex(5, 5, -5, -5) },
    { "Gee Whiz", "+1 +2 +3 +4 −10, or the inverse", ex(1, 2, 3, 4, -10) },
    { "Straight Khyron", "Zero with a run of four", ex(1, -2, -3, 4) },
    { "Rule of Two", "Zero with two pairs", ex(3, -3, 2, -2) },
    { "Sabacc", "Zero with one pair", ex(5, -5) },
    { "Sabacc", "Any other zero", ex(1, 2, -3) },
    { "Nulrhek", "Not zero: closest to zero wins", ex(4, -1) },
}
Sabacc.HAND_CHART = HAND_CHART

local Chart = UI.Board:extend {}

function Chart:setup()
    local W, H = self.width, self.height
    local u = W / 100
    self.u, self.pad = u, math.floor(2 * u)
    self.head_h = math.floor(H * 0.075)
    self.foot_h = math.floor(H * 0.07)
    self.row_h = math.floor((H - self.head_h - self.foot_h - self.pad) / #HAND_CHART)
    self.mini_h = math.floor(self.row_h * 0.8)
    self.mini_w = math.floor(self.mini_h / 1.42)
    local text_w = W - 2 * self.pad - 5 * (self.mini_w + math.floor(u)) - math.floor(10 * u)
    self.text_w = text_w
    self.face_title = UI.fitFace({ "W I N N I N G   H A N D S" }, W * 0.7, self.head_h * 0.4, { font = MONO, bold = true })
    self.face_rank = UI.fitFace({ "12" }, 7 * u, self.row_h * 0.4, { font = MONO, bold = true })
    self.face_name = UI.fitFace({ "STRAIGHT KHYRON" }, text_w, self.row_h * 0.26, { font = MONO, bold = true })
    self.face_desc = UI.fitFace({ "Three of a kind and a pair of the" }, text_w, self.row_h * 0.2)
    self.face_foot = UI.fitFace({ "Pairs, kinds and runs go by number, whatever the sign." }, W * 0.92, self.foot_h * 0.26)
    self.faces_mini = { num = UI.fitFace({ "+10", "−10" }, self.mini_w * 0.52, self.mini_h * 0.17 * 0.85, { font = MONO, bold = true }) }
end

function Chart:draw(bb, x, y)
    local W, u, pad = self.width, self.u, self.pad
    -- header band with a close cross
    local hh = self.head_h
    fillPoly(bb, { { x, y }, { x + W, y }, { x + W, y + hh * 0.8 }, { x + W * 0.7, y + hh * 0.8 }, { x + W * 0.67, y + hh },
        { x + W * 0.33, y + hh }, { x + W * 0.3, y + hh * 0.8 }, { x, y + hh * 0.8 } }, UI.BLACK)
    UI.drawText(bb, self.face_title, "W I N N I N G   H A N D S", x, y, W, math.floor(hh * 0.8), UI.WHITE, true)
    local cx, cy, d, t = x + W - math.floor(5.5 * u), y + math.floor(hh * 0.4), math.floor(2.2 * u), math.max(2, math.floor(u * 0.5)) + 1
    UI.drawLine(bb, cx - d, cy - d, cx + d, cy + d, t, UI.WHITE)
    UI.drawLine(bb, cx - d, cy + d, cx + d, cy - d, t, UI.WHITE)
    UI.drawTextLeft(bb, self.face_foot, "BEST", x + pad, y + hh, math.floor(pad * 1.6), UI.DARK, true)
    -- rows, best first
    local ry = y + hh + pad
    for i, row in ipairs(HAND_CHART) do
        local rh = self.row_h
        if i % 2 == 0 then bb:paintRect(x + pad, ry, W - 2 * pad, rh, UI.PALE) end
        UI.drawText(bb, self.face_rank, tostring(i), x + pad, ry, math.floor(7 * u), rh, i <= 2 and UI.BLACK or UI.DARK, true)
        local tx = x + pad + math.floor(8 * u)
        UI.drawTextLeft(bb, self.face_name, row[1]:upper(), tx, ry + math.floor(rh * 0.14), math.floor(rh * 0.36), UI.BLACK, true)
        local f, lines = UI.fitLines(row[2], self.text_w, math.floor(rh * 0.4), 2)
        local lh = math.floor(rh * 0.4 / 2)
        for li, l in ipairs(lines) do
            UI.drawTextLeft(bb, f, l, tx, ry + math.floor(rh * 0.5) + (li - 1) * lh, lh, UI.DARK)
        end
        local hand = row[3]
        local step = self.mini_w + math.floor(u)
        local cxs = x + W - pad - math.floor(u) - #hand * step
        for j, c in ipairs(hand) do
            drawCard(bb, c, cxs + (j - 1) * step, ry + math.floor((rh - self.mini_h) / 2), self.mini_w, self.mini_h, self.faces_mini, true)
        end
        ry = ry + rh
    end
    -- footer: how pairs and ties work
    local fy = y + self.height - self.foot_h
    bb:paintRect(x + pad, fy, W - 2 * pad, 1, UI.LIGHT)
    local lh = math.floor(self.foot_h / 3)
    UI.drawText(bb, self.face_foot, "Pairs, kinds and runs go by number, whatever the sign.", x, fy + math.floor(lh * 0.3), W, lh, UI.BLACK)
    UI.drawText(bb, self.face_foot, "Ties: lower pair or run, then most cards, then highest positive total.", x, fy + math.floor(lh * 1.3), W, lh, UI.DARK)
end

function Chart:tapAt()
    self.app:onClose() -- tap anywhere to go back to the table
end

local ChartApp = UI.FullscreenApp:extend { name = "sabacc_hands", title = "Winning hands" }

function ChartApp:rebuild()
    if self[1] then self[1]:free() end
    self[1] = Chart:new { width = self.dimen.w, height = self.dimen.h, app = self }
end

-- the regulars -------------------------------------------------------------------------

local PER_PAGE = 5
local Regulars = UI.Board:extend {}

function Regulars:setup()
    local W, H = self.width, self.height
    local u = W / 100
    self.u, self.pad = u, math.floor(2 * u)
    self.page = self.page or 1
    self.head_h = math.floor(H * 0.075)
    self.foot_h = math.floor(H * 0.07)
    self.row_h = math.floor((H - self.head_h - self.foot_h - 2 * self.pad) / PER_PAGE)
    local mono = { font = MONO, bold = true }
    self.face_title = UI.fitFace({ "T H E   R E G U L A R S" }, W * 0.7, self.head_h * 0.4, mono)
    self.face_name = UI.fitFace({ "VARRO QUILL" }, W * 0.4, self.row_h * 0.15, mono)
    self.face_title2 = UI.fitFace({ "FREIGHTER PILOT" }, W * 0.3, self.row_h * 0.11, { font = MONO })
    self.face_tag = UI.fitFace({ "AT YOUR TABLE" }, W * 0.2, self.row_h * 0.09, mono)
    self.face_page = UI.fitFace({ "‹ PREV", "NEXT ›", "1 / 2" }, W * 0.25, self.foot_h * 0.36, mono)
end

function Regulars:draw(bb, x, y)
    local W, u, pad = self.width, self.u, self.pad
    local hh = self.head_h
    self.hits = {}
    -- header band with a close cross
    fillPoly(bb, { { x, y }, { x + W, y }, { x + W, y + hh * 0.8 }, { x + W * 0.7, y + hh * 0.8 }, { x + W * 0.67, y + hh },
        { x + W * 0.33, y + hh }, { x + W * 0.3, y + hh * 0.8 }, { x, y + hh * 0.8 } }, UI.BLACK)
    UI.drawText(bb, self.face_title, "T H E   R E G U L A R S", x, y, W, math.floor(hh * 0.8), UI.WHITE, true)
    local cx, cy, d, t = x + W - math.floor(5.5 * u), y + math.floor(hh * 0.4), math.floor(2.2 * u), math.max(2, math.floor(u * 0.5)) + 1
    UI.drawLine(bb, cx - d, cy - d, cx + d, cy + d, t, UI.WHITE)
    UI.drawLine(bb, cx - d, cy + d, cx + d, cy - d, t, UI.WHITE)
    self.hits[#self.hits + 1] = { x = W - math.floor(14 * u), y = 0, w = math.floor(14 * u), h = hh, act = "close" }
    -- who's at your table now
    local seated = {}
    for _, p in ipairs(self.game and self.game.players or {}) do seated[p.name] = true end
    -- five profiles per page
    local first = (self.page - 1) * PER_PAGE + 1
    local ry = y + hh + pad
    for i = first, math.min(#ROSTER, first + PER_PAGE - 1) do
        local r = ROSTER[i]
        local rh = self.row_h - pad
        panel(bb, x + pad, ry, W - 2 * pad, rh, math.floor(3 * u), math.max(2, math.floor(u * 0.3)), UI.BLACK, UI.WHITE)
        local sh = math.floor(rh * 0.24)
        fillPoly(bb, cutPts(x + pad, ry, W - 2 * pad, sh, math.floor(3 * u)), UI.BLACK)
        local tx = x + pad + math.floor(4 * u)
        UI.drawTextLeft(bb, self.face_name, r.name:upper(), tx, ry, sh, UI.WHITE, true)
        local nw = UI.measure(self.face_name, r.name:upper())
        UI.drawTextLeft(bb, self.face_title2, r.title:upper(), tx + nw + math.floor(2.5 * u), ry, sh, UI.LIGHT)
        if seated[r.name] then
            local tag = "AT YOUR TABLE"
            local tw = UI.measure(self.face_tag, tag) + math.floor(2 * u)
            local th = math.floor(sh * 0.6)
            local tgx = x + W - pad - math.floor(2 * u) - tw
            fillPoly(bb, cutPts(tgx, ry + math.floor((sh - th) / 2), tw, th, math.floor(th * 0.3)), UI.WHITE)
            UI.drawText(bb, self.face_tag, tag, tgx, ry + math.floor((sh - th) / 2), tw, th, UI.BLACK, true)
        end
        -- boldness meter: five slanted slots
        local my = ry + sh + math.floor(rh * 0.06)
        local mh = math.floor(rh * 0.1)
        UI.drawTextLeft(bb, self.face_tag, "BOLDNESS", tx, my, mh, UI.DARK, true)
        local filled = math.max(1, math.min(5, math.floor(r.bold / 0.8 * 5 + 0.5)))
        local sx = tx + UI.measure(self.face_tag, "BOLDNESS") + math.floor(2 * u)
        local sw = math.floor(3.2 * u)
        for k = 1, 5 do
            local px = sx + (k - 1) * (sw + math.floor(u))
            local pts = { { px + mh * 0.5, my }, { px + sw, my }, { px + sw - mh * 0.5, my + mh }, { px, my + mh } }
            fillPoly(bb, pts, k <= filled and UI.BLACK or UI.LIGHT)
        end
        -- backstory and play style
        local tw = W - 2 * pad - math.floor(12 * u) -- clear of the cut corner
        local sy = my + mh + math.floor(rh * 0.06)
        local bh = math.floor(rh * 0.3)
        local f, lines = UI.fitLines(r.story, tw, bh, 2)
        local lh = math.floor(bh / 2)
        for li, l in ipairs(lines) do UI.drawTextLeft(bb, f, l, tx, sy + (li - 1) * lh, lh, UI.BLACK) end
        local f2, lines2 = UI.fitLines(r.style, tw, math.floor(rh * 0.14), 1, { font = MONO })
        UI.drawTextLeft(bb, f2, lines2[1], tx, sy + bh + math.floor(rh * 0.04), math.floor(rh * 0.14), UI.DARK, true)
        ry = ry + self.row_h
    end
    -- footer: page turning
    local pages = math.ceil(#ROSTER / PER_PAGE)
    local fy = y + self.height - self.foot_h
    bb:paintRect(x + pad, fy, W - 2 * pad, 1, UI.LIGHT)
    UI.drawText(bb, self.face_page, self.page .. " / " .. pages, x, fy, W, self.foot_h, UI.DARK)
    if self.page > 1 then
        UI.drawTextLeft(bb, self.face_page, "‹ PREV", x + pad, fy, self.foot_h, UI.BLACK, true)
        self.hits[#self.hits + 1] = { x = 0, y = fy - y, w = math.floor(W / 3), h = self.foot_h, act = "prev" }
    end
    if self.page < pages then
        local nw = UI.measure(self.face_page, "NEXT ›")
        UI.drawTextLeft(bb, self.face_page, "NEXT ›", x + W - pad - nw, fy, self.foot_h, UI.BLACK, true)
        self.hits[#self.hits + 1] = { x = W - math.floor(W / 3), y = fy - y, w = math.floor(W / 3), h = self.foot_h, act = "next" }
    end
end

function Regulars:tapAt(lx, ly)
    for _, h in ipairs(self.hits or {}) do
        if lx >= h.x and lx < h.x + h.w and ly >= h.y and ly < h.y + h.h then
            if h.act == "close" then return self.app:onClose() end
            self.app:turn(h.act == "next" and 1 or -1)
            return
        end
    end
end

local RegularsApp = UI.FullscreenApp:extend { name = "sabacc_regulars", title = "The regulars" }

function RegularsApp:rebuild()
    if self[1] then self[1]:free() end
    self[1] = Regulars:new { width = self.dimen.w, height = self.dimen.h, app = self, page = self.page, game = self.game }
end

function RegularsApp:turn(delta)
    self.page = math.max(1, math.min(math.ceil(#ROSTER / PER_PAGE), (self.page or 1) + delta))
    self:refresh()
end

-- app ---------------------------------------------------------------------------------

local HELP = [[Corellian Spike, played by the Outer Rim Sabacc League (ORSL) rules, against three computer players picked at random from ten regulars (smugglers, droids, a bounty hunter and more). When one runs out of credits they leave and someone new sits down. They bet like poker players: each one estimates its chance of winning and weighs it against the price of calling, bets big with strong hands, bluffs now and then, and reads how often you raise. Bolder regulars raise and bluff more. ☰ > The regulars has everyone's story and play style. It works offline; play as many hands as you like. Credits and the Sabacc Pot carry over between hands.

GOAL
Have the best hand at the end of 3 rounds, as close to zero as possible. ☰ > Winning hands shows every hand in order of strength, with examples.

THE CARDS
62 cards: +1 to +10 and −1 to −10, three of each, plus two sylops worth 0.
• The number is in the top band; the bottom band has one dot per point.
• Positive cards are black, negative cards dark gray (the number keeps its sign too).
• 1 to 6 show that many suit symbols (circles, triangles or squares). 7 to 10 are solid face cards with an ornate design. The sylop is a black card with a ringed hexagon.

EACH HAND
• Everyone antes 20 to the Pot and 10 to the Sabacc Pot, and is dealt 2 cards. The top card of the deck is turned face up as the discard pile.
• The dealer (marked DEALER) moves one seat to the left each hand. Play starts at the dealer's left.
• A hand is 3 rounds. Each round has three phases:

1. TRADING. Do one of these:
• Buy deck (10 credits): add the top card of the deck to your hand.
• Buy discard (20 credits): add the face-up discard to your hand. If the discard pile is empty, the top card of the deck is discarded first.
• Trade with deck (free): give up one of your cards to the discard pile and draw the top card of the deck in its place.
• Trade with discard (free): take the face-up discard and give up one of your cards in its place.
• Stand: do nothing.

2. BETTING. The bet starts at 0. Going round from the dealer's left, each player can:
• Check, if no one has raised.
• Raise the bet by any amount you can afford.
• Call: pay what you owe to match the bet.
• Junk: fold. Your cards go to the junk pile and you pay a 10 penalty into the Pot. If you can't cover the bet, you must junk.
Betting goes round until everyone still in has matched the bet. If only one player is left, they win the hand at once.

3. SPIKE DICE. Two dice are rolled. On doubles (a Sabacc Shift) every player discards their hand and is dealt a new hand of the same size.

WINNING
After round 3 the best hand takes the Pot. If that hand totals exactly zero, it also takes the Sabacc Pot; otherwise the Sabacc Pot rides on to the next hand.

WINNING HANDS, best first
1. Pure Sabacc: 0 0
2. Full Sabacc: −10 −10 0 +10 +10
3. Yee-Haa: zero with a pair and a sylop
4. Rhylet: zero with three of a kind of one sign and a pair of the other (five cards)
5. Straight Staves: +7 −8 −9 +10, or the inverse
6. Squadron: zero with four of a kind
7. Gee Whiz: +1 +2 +3 +4 −10, or the inverse
8. Straight Khyron: zero with a run of four (four cards)
9. Rule of Two: zero with two pairs
10. Sabacc: zero with one pair
11. Sabacc: any other hand totalling zero
12. Nulrhek: any hand that isn't zero
Pairs, kinds and runs go by a card's number, whatever its sign (+5 and −5 are a pair).

TIES
• Same named hand: the lower pair, kind or run wins.
• Then, for a Sabacc: most cards, then highest positive sum, then highest positive card.
• For a Nulrhek: closest to zero, then a positive total beats a negative one, then most cards, then highest positive sum, then highest positive card.
• Still tied: a blind card draw; the highest card wins.

CONTROLS
• The buttons at the bottom are the moves you can make right now; each shows its cost underneath. Greyed-out buttons are ones you can't afford.
• To raise, tap Raise, set the amount with −10 and +10 (up to everything you have), then tap Raise to. Cancel goes back.
• To trade, tap one of your cards first (it lifts up). The buttons change to Trade with deck, Trade with discard and Cancel. Tap the card again to put it back.
• The line above the buttons on the right tells you what to do: TAP A CARD TO TRADE, YOU OWE 10 and so on.
• The message in the middle sums up what happened since your last move: raises, who junked, the spike dice and the result.
• Each opponent's panel shows their credits, how many cards they hold and their last move. At the showdown their cards are turned up and the winner's panel turns black with a star.
• The table shows the deck, the discard pile, the Pot, the Sabacc Pot and the spike dice.
• Hands of more than five cards overlap; tap the visible edge of a card to pick it.
• ☰ (top left) opens this menu; ✕ (top right) or the Back key closes the game. Your table is saved, so you can come back to it.

HOUSE CHOICES
Where the rules leave something open, this game does the following:
• Your raise picker moves in steps of 10. There is no limit on how many times the bet can be raised.
• Everyone starts with 300 credits. A computer player who runs low leaves the table, and a random regular sits down with 300. If you can't cover the ante, start a new table from this menu.
• The ORSL hand list is used, so Fleet, Prime Sabacc, Idiot's Array and similar hands from other tables count only as the plain hands they also are.

SOURCE
Rules adapted from "Sabacc: Corellian Spike" v1.1 by Ender Smith (CC-BY-SA 2.0), Outer Rim Sabacc League rules and winning hands. This is an unofficial fan game.]]

local App = UI.FullscreenApp:extend {
    name = "sabacc_app",
    title = "Sabacc",
}

--- How to play, in a scrollable viewer (too long for a popup).
function App:showHelp()
    local TextViewer = require("ui/widget/textviewer")
    UIManager:show(TextViewer:new { title = "How to play Sabacc", text = HELP })
end

function App:setup()
    if not self.game then
        local saved = Store.get(SAVE_KEY)
        if type(saved) == "table" and type(saved.players) == "table" and #saved.players == SEATS
                and saved.sabacc_pot then
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
    if self.game.phase ~= "trade" then return end
    self.sel = self.sel ~= i and i or nil
    self:refresh()
end

function App:doTrade(kind)
    if Sabacc.trade(self.game, kind, self.sel) then
        self.sel = nil
        self:save()
    end
    self:refresh()
end

function App:doBet(kind, amount)
    self.raise_by = nil
    if Sabacc.bet(self.game, kind, amount) then self:save() end
    self:refresh()
end

--- Raise picker: change the raise by `delta` (a multiple of STEP), within your credits.
function App:stepRaise(delta)
    local g, me = self.game, self.game.players[1]
    local max = math.floor((me.credits - Sabacc.owe(g)) / STEP) * STEP
    self.raise_by = math.max(STEP, math.min(max, (self.raise_by or STEP) + delta))
    self:refresh()
end

function App:newTable()
    self.game = Sabacc.newTable()
    self.sel = nil
    self:save()
    self:rebuild()
    UIManager:setDirty(self, function() return "full", self.dimen end)
end

--- Buttons for the current moment. `sub` is a small second line (costs).
function App:buttonRow()
    local g, me = self.game, self.game.players[1]
    if g.phase == "trade" then
        if self.sel then
            return {
                { text = "Trade with deck", sub = "free", primary = true, callback = function() self:doTrade("trade_deck") end },
                { text = "Trade with discard", sub = #g.discard == 0 and "free · top deck card" or "free", callback = function() self:doTrade("trade_discard") end },
                { text = "Cancel", callback = function() self:pick(self.sel) end },
            }
        end
        return {
            { text = "Buy deck", sub = BUY_DECK .. " cr", enabled = me.credits >= BUY_DECK,
                callback = function() self:doTrade("buy_deck") end },
            { text = "Buy discard", sub = BUY_DISCARD .. " cr" .. (#g.discard == 0 and " · top deck card" or ""), enabled = me.credits >= BUY_DISCARD,
                callback = function() self:doTrade("buy_discard") end },
            { text = "Stand", primary = true, callback = function() self:doTrade("stand") end },
        }
    elseif g.phase == "bet" then
        local owe = Sabacc.owe(g)
        local row = {}
        if owe == 0 then
            row[1] = { text = "Check", primary = true, callback = function() self:doBet("check") end }
        else
            row[1] = { text = "Call " .. owe, primary = true, enabled = me.credits >= owe,
                callback = function() self:doBet("call") end }
        end
        local can_raise = me.credits >= owe + STEP
        if self.raise_by then
            -- raise picker: step the amount, then confirm
            local by = self.raise_by
            return {
                { text = "−" .. STEP, enabled = by > STEP, callback = function() self:stepRaise(-STEP) end },
                { text = "Raise to " .. (g.bet + by), sub = "pay " .. (owe + by) .. " cr", primary = true,
                    callback = function() self.raise_by = nil; self:doBet("raise", by) end },
                { text = "+" .. STEP, enabled = me.credits >= owe + by + STEP, callback = function() self:stepRaise(STEP) end },
                { text = "Cancel", callback = function() self.raise_by = nil; self:refresh() end },
            }
        end
        row[#row + 1] = { text = "Raise", sub = can_raise and "choose amount" or "can't raise",
            enabled = can_raise, callback = function() self.raise_by = STEP; self:refresh() end }
        row[#row + 1] = { text = "Junk", sub = "fold · " .. JUNK_PENALTY .. " cr", callback = function() self:doBet("junk") end }
        return row
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
    return {
        { text = "Winning hands", callback = function() UIManager:show(ChartApp:new {}) end },
        { text = "The regulars", callback = function() UIManager:show(RegularsApp:new { game = self.game, page = 1 }) end },
        { text = "How to play", callback = function() self:showHelp() end },
        { text = "New table (reset credits)", callback = function() self:newTable() end },
    }
end

function Sabacc.launch()
    UIManager:show(App:new {})
end

Sabacc.App = App -- exposed for tests

return Sabacc
