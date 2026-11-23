dofile(STUBS)
local UIManager = require("ui/uimanager")
local Sabacc = dofile(PLUGDIR .. "/dailygames/sabacc.lua")
package.loaded["dailygames/sabacc"] = Sabacc
math.randomseed(42)

local function C(v, s) return { v = v, s = s or (v == 0 and 0 or 1) } end
local function H(...) local h = {}; for _, v in ipairs { ... } do h[#h + 1] = C(v) end; return h end
local function name(...) return Sabacc.evaluate(H(...)).name end
local function beats(a, b) return Sabacc.compare(Sabacc.evaluate(a), Sabacc.evaluate(b)) < 0 end

-- deck: 60 numbered cards + 2 sylops, sums to zero
local deck = Sabacc.newDeck()
assert(#deck == 62)
local sum, syl = 0, 0
for _, c in ipairs(deck) do sum = sum + c.v; if c.v == 0 then syl = syl + 1 end end
assert(sum == 0 and syl == 2)

-- ORSL winning hands
assert(name(0, 0) == "Pure Sabacc")
assert(name(-10, -10, 0, 10, 10) == "Full Sabacc")
assert(name(0, 4, -4) == "Yee-Haa")
assert(name(0, 3, 3, -6) == "Yee-Haa")
assert(name(2, 2, 2, -3, -3) == "Rhylet")
assert(name(-2, -2, -2, 3, 3) == "Rhylet", "inverse")
assert(name(7, -8, -9, 10) == "Straight Staves")
assert(name(-7, 8, 9, -10) == "Straight Staves", "inverse")
assert(name(5, 5, -5, -5) == "Squadron")
assert(name(1, 2, 3, 4, -10) == "Gee Whiz")
assert(name(-1, -2, -3, -4, 10) == "Gee Whiz", "inverse")
assert(name(1, -2, -3, 4) == "Straight Khyron")
assert(name(3, -3, 2, -2) == "Rule of Two")
assert(name(5, -5) == "Sabacc")
assert(name(1, 2, -3) == "Sabacc")
assert(name(4, -1) == "Nulrhek +3")
assert(name(-4, 1) == "Nulrhek −3")
-- hands left out of the ORSL list are just Sabacc
assert(name(0, -10, 10) == "Yee-Haa", "Prime Sabacc isn't an ORSL hand; a 10 pair and a sylop is a Yee-Haa")
assert(name(0, 2, 3, -5) == "Sabacc", "no Idiot's Array in ORSL")

-- ranking order and tiebreaks
assert(beats(H(0, 0), H(-10, -10, 0, 10, 10)))
assert(beats(H(-10, -10, 0, 10, 10), H(0, 1, -1)))
assert(beats(H(0, 1, -1), H(0, 2, -2)), "lowest pair wins a Yee-Haa")
assert(beats(H(5, -5), H(1, 2, -3)), "a pair beats an unpaired zero")
assert(beats(H(1, -1), H(9, -9)), "lower pair wins")
assert(beats(H(1, 2, 3, -6), H(1, 5, -6)), "unpaired Sabacc: most cards")
assert(beats(H(2, 7, -9), H(4, 5, -9)), "same count and positive sum: highest positive card")
assert(beats(H(3, 6, -9), H(4, 5, -9)), "highest positive card")
assert(beats(H(5, -5), H(4, -1)), "any Sabacc beats a Nulrhek")
assert(beats(H(2, -1), H(-2, 1)), "positive Nulrhek beats negative")
assert(beats(H(2, -1), H(5, -3)), "closer to zero wins")
assert(beats(H(3, 1, -3), H(2, -1)), "Nulrhek: most cards")

-- the Winning hands chart: each example is the hand it illustrates, in rank order
for i, row in ipairs(Sabacc.HAND_CHART) do
    local e = Sabacc.evaluate(row[3])
    assert(e.rank == i and e.name:sub(1, #row[1]) == row[1], "chart row " .. i .. ": " .. e.name .. " rank " .. e.rank)
end

-- a new table: four seats, antes in both pots, two cards each, one discard
local g = Sabacc.newTable()
assert(#g.players == 4 and g.pot == 80 and g.sabacc_pot == 40)
for _, p in ipairs(g.players) do assert(#p.hand == 2 and p.credits == Sabacc.START - 30) end
assert(#g.discard >= 1)
assert(g.phase == "trade", "you sit at the dealer's left in the first hand")

-- trading moves
local credits = g.players[1].credits
assert(not Sabacc.trade(g, "trade_deck", nil), "trading needs a card")
assert(not Sabacc.bet(g, "check"), "no betting while trading")
assert(Sabacc.trade(g, "buy_deck"))
assert(#g.players[1].hand == 3 and g.players[1].credits == credits - 10)

-- official rule: buying from an empty discard pile discards the top deck card first, then takes it
do
    local t = Sabacc.newTable()
    t.discard = {}
    local top_card = t.deck[#t.deck]
    local me = t.players[1]
    assert(Sabacc.trade(t, "buy_discard"))
    assert(me.hand[#me.hand] == top_card, "took the top card of the deck")
end

-- opponents: three different regulars per table, picked at random
do
    local pool, seen = {}, {}
    for _, r in ipairs(Sabacc.ROSTER) do pool[r.name] = true end
    assert(#Sabacc.ROSTER >= 6)
    for _ = 1, 60 do
        local t = Sabacc.newTable()
        local names = {}
        for i = 2, 4 do
            local n = t.players[i].name
            assert(pool[n] and not names[n], "a regular, seated once")
            names[n], seen[n] = true, true
        end
    end
    local distinct = 0
    for _ in pairs(seen) do distinct = distinct + 1 end
    assert(distinct >= 8, "tables vary: " .. distinct)
    -- a player out of credits leaves; a newcomer takes the seat
    local t = Sabacc.newTable()
    local gone = t.players[3].name
    t.players[3].credits = 5
    t.phase = "done"
    Sabacc.newHand(t)
    local new = t.players[3]
    assert(new.name ~= gone and new.ai and pool[new.name], "replaced by a regular")
    for i = 2, 4 do if i ~= 3 then assert(t.players[i].name ~= new.name, "not already seated") end end
    assert(new.credits <= Sabacc.START - 30 and new.credits >= Sabacc.START - 50, "newcomer brings fresh credits")
    assert((t.msg or ""):find(gone .. " leaves the table") or t.phase ~= "trade", "announced")
end

-- play many hands with random legal moves; credits and cards are conserved
local function total(t)
    local s = t.pot + t.sabacc_pot
    for _, p in ipairs(t.players) do s = s + p.credits end
    return s
end
local function cards(t)
    local n = #t.deck + #t.discard + #t.junk
    for _, p in ipairs(t.players) do n = n + #p.hand end
    return n
end
local trades = { "buy_deck", "buy_discard", "trade_deck", "trade_discard", "stand", "stand" }
local hands_won, sabacc_pots = 0, 0
for _ = 1, 300 do
    local guard = 0
    while g.phase ~= "done" and g.phase ~= "broke" do
        guard = guard + 1
        assert(guard < 60, "hand never ended")
        local before = total(g)
        if g.phase == "trade" then
            if not Sabacc.trade(g, trades[math.random(#trades)], math.random(#g.players[1].hand)) then
                assert(Sabacc.trade(g, "stand"))
            end
        elseif g.phase == "bet" then
            local r = math.random()
            local ok
            if r < 0.15 then ok = Sabacc.bet(g, "raise", Sabacc.RAISES[math.random(2)])
            elseif r < 0.25 then ok = Sabacc.bet(g, "junk")
            else ok = Sabacc.bet(g, Sabacc.owe(g) > 0 and "call" or "check") end
            if not ok then assert(Sabacc.bet(g, "junk")) end
        else
            error("stuck in phase " .. tostring(g.phase))
        end
        assert(total(g) == before, "credits not conserved")
        assert(cards(g) == 62, "cards lost: " .. cards(g))
        for _, p in ipairs(g.players) do assert(p.credits >= 0, "negative credits") end
    end
    if g.phase == "broke" then g = Sabacc.newTable() else
        assert(g.winners and #g.winners == 1 and g.pot == 0, "phase=" .. tostring(g.phase) .. " pot=" .. tostring(g.pot) .. " w=" .. tostring(g.winners and #g.winners) .. " msg=" .. tostring(g.msg))
        if Sabacc.isWinner(g, 1) then hands_won = hands_won + 1 end
        if g.sabacc_pot == 0 then sabacc_pots = sabacc_pots + 1 end
        local dealer = g.dealer
        Sabacc.newHand(g)
        assert(g.phase == "broke" or g.dealer == dealer % 4 + 1, "dealer moves left")
    end
end
assert(hands_won > 0, "you never won a hand")
assert(sabacc_pots > 0, "nobody ever won the Sabacc Pot")

-- UI: launch, pick a card, trade it, bet; the table is saved to the store
local fakebb = { paintRect = function() end }
local function paint(a)
    a[1]:paintTo(fakebb, 0, 100)
    return a[1]
end
STORE["sabacc/orsl"] = nil
math.randomseed(7)
Sabacc.launch()
local app = top()
assert(app.name == "sabacc_app")
local guard = 0
while app.game.phase ~= "trade" do
    guard = guard + 1; assert(guard < 10)
    press(app, "Next hand")
end
paint(app)
press(app, "Buy deck")
assert(STORE["sabacc/orsl"] == app.game, "saved")
guard = 0
while app.game.phase ~= "done" do
    guard = guard + 1; assert(guard < 30)
    local board = paint(app)
    if app.game.phase == "trade" then
        -- tap the first card on the drawn board, then trade it with the discard
        local h
        for _, hit in ipairs(board.hits) do if hit.card == 1 then h = hit end end
        board:onTap(nil, { pos = { x = h.x + 5, y = 100 + h.y + 5 } })
        assert(app.sel == 1, "tap picks a card")
        press(app, "Trade with discard")
    elseif app.game.phase == "bet" then
        if Sabacc.owe(app.game) == 0 then press(app, "Check")
        elseif app.game.players[1].credits >= Sabacc.owe(app.game) then press(app, "Call " .. Sabacc.owe(app.game))
        else press(app, "Junk") end
    end
end
paint(app)
press(app, "Next hand")
assert(app.game.hand_no >= 2)
paint(app)

-- Winning hands opens the drawn chart; a tap goes back to the table
for _, item in ipairs(app:menuItems()) do if item.text == "Winning hands" then item.callback() end end
local chart = top()
assert(chart.name == "sabacc_hands")
chart[1]:paintTo(fakebb, 0, 0)
chart[1]:onTap(nil, { pos = { x = 10, y = 10 } })
assert(top() == app, "tap closes the chart")

-- How to play opens a scrollable viewer with the full rules
app:showHelp()
assert(top()._name == "TextViewer" and top().text:find("Outer Rim Sabacc League") and top().text:find("Straight Khyron")
    and top().text:find("CONTROLS") and top().text:find("HOUSE CHOICES"))
UIManager:close(top())

-- a saved table is resumed
local hand_no = app.game.hand_no
app:onClose()
Sabacc.launch()
assert(top().game.hand_no == hand_no, "resumed")

-- the plugin lists it and starts it without Wi-Fi
local online = 0
package.loaded["ui/network/manager"].runWhenOnline = function(_, f) online = online + 1; f() end
local P = dofile(PLUGDIR .. "/main.lua")
local plug = P:new { ui = { menu = { registerToMainMenu = function() end } } }
assert(ACTIONS.dailygames_sabacc, "gesture action")
plug:onDailyGamesSabacc()
assert(online == 0 and (top().name == "sabacc_app"))
print("sabacc ok")
