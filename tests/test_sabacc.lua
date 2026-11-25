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

-- no limit on raises (official rules): a fourth, fifth... raise is allowed
do
    local t
    for _ = 1, 50 do
        t = Sabacc.newTable()
        while t.phase == "trade" do Sabacc.trade(t, "stand") end
        if t.phase == "bet" then break end
    end
    assert(t.phase == "bet", "reached betting")
    t.raises = 7
    local before = t.bet
    assert(Sabacc.bet(t, "raise", 10), "raise after seven raises")
    assert(t.raises >= 8 and (t.bet >= before + 10 or t.phase ~= "bet"))
end
-- betting always ends, even when you raise every time you can
do
    for _ = 1, 100 do
        local t = Sabacc.newTable()
        for i = 2, 4 do t.players[i].bold = 1 end -- the most reckless table possible
        for _ = 1, 400 do
            if t.phase == "done" or t.phase == "broke" then break end
            if t.phase == "trade" then Sabacc.trade(t, "stand")
            elseif not Sabacc.bet(t, "raise", 10) then
                if not Sabacc.bet(t, Sabacc.owe(t) > 0 and "call" or "check") then Sabacc.bet(t, "junk") end
            end
        end
        assert(t.phase == "done" or t.phase == "broke", "hand finished")
    end
end

-- poker-style betting: a strong hand calls a big raise, a hopeless one mostly folds
do
    local strong, weak, spots = 0, 0, 0
    for _ = 1, 80 do
        local t = Sabacc.newTable()
        for _ = 1, 10 do
            if t.phase ~= "trade" then break end
            Sabacc.trade(t, "stand")
        end
        if t.phase == "bet" and Sabacc.owe(t) == 0 then
            spots = spots + 1
            t.players[1].credits = 500
            t.players[2].hand = { { v = 0, s = 0 }, { v = 0, s = 0 } }      -- Pure Sabacc
            t.players[3].hand = { { v = 9, s = 1 }, { v = 8, s = 2 } }      -- Nulrhek +17
            t.players[2].eq_key, t.players[3].eq_key = nil, nil
            Sabacc.bet(t, "raise", 150)
            if not t.players[2].out then strong = strong + 1 end
            if not t.players[3].out then weak = weak + 1 end
        end
    end
    assert(spots >= 20, "found betting spots")
    assert(strong == spots, "Pure Sabacc always calls a big raise")
    assert(weak < spots * 0.5, "a hopeless hand mostly folds to a big raise: " .. weak .. "/" .. spots)
    -- equity is a probability, about a fair share for a random hand
    local t, total = Sabacc.newTable(), 0
    for i = 2, 4 do
        local e = Sabacc.equity(t, t.players[i], 60)
        assert(e >= 0 and e <= 1)
        total = total + e
    end
    assert(total > 0.3 and total < 1.2, "equities look sane: " .. total)
end

-- stake sizing: a 50% hand doesn't bet its whole stack, even into a huge pot
do
    local t = Sabacc.newTable()
    for _ = 1, 10 do if t.phase == "trade" then Sabacc.trade(t, "stand") end end
    local p = t.players[2]
    t.bet, t.raises, p.paid, p.out = 0, 0, 0, false
    t.pot, p.credits, p.bold = 2000, 300, 1
    p.eq, p.eq_key = 0.5, t.hand_no * 10 + t.round
    local raised
    for _ = 1, 200 do
        t.bet, t.raises, p.paid, p.credits, t.pot = 0, 0, 0, 300, 2000
        Sabacc._aiBet(t, p)
        if p.paid > 0 then raised = math.max(raised or 0, p.paid) end
    end
    assert(raised and raised <= 300 * (0.15 + 0.45 * 0.5) + 10, "kept most of its credits: " .. tostring(raised))
    p.eq = 0.95 -- near-certain: may go all in
    local all_in = false
    for _ = 1, 200 do
        t.bet, t.raises, p.paid, p.credits, t.pot = 0, 0, 0, 300, 2000
        Sabacc._aiBet(t, p)
        if p.paid == 300 then all_in = true end
    end
    assert(all_in, "a near-certain hand can risk everything")
end
-- a Sabacc Shift names the zero hands it took
do
    local real = math.random
    math.random = function(a, b) -- the spike dice always roll doubles
        if a == 6 and not b then return 3 end
        if b then return real(a, b) elseif a then return real(a) end
        return real()
    end
    local t = Sabacc.newTable()
    local said = false
    for _ = 1, 30 do
        if t.phase == "trade" then
            t.players[1].hand = { { v = 5, s = 1 }, { v = -5, s = 2 } }
            Sabacc.trade(t, "stand")
        elseif t.phase == "bet" then
            if not Sabacc.bet(t, Sabacc.owe(t) > 0 and "call" or "check") then Sabacc.bet(t, "junk") end
        end
        if (t.msg or ""):find("It took your Sabacc") then said = true break end
        if t.phase == "done" or t.phase == "broke" then break end
    end
    math.random = real
    assert(said, "the shift message names your lost Sabacc")
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
    guard = guard + 1; assert(guard < 40)
    press(app, app.game.phase == "watch" and "Next ›" or "Next hand")
end
paint(app)
press(app, "Buy deck")
assert(STORE["sabacc/orsl"] == app.game, "saved")
guard = 0
while app.game.phase ~= "done" do
    guard = guard + 1; assert(guard < 120)
    local board = paint(app)
    if app.game.phase == "watch" then
        press(app, "Next ›") -- an opponent's move or the dice, one at a time
    elseif app.game.phase == "trade" then
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

-- watching: opponents' moves pause one at a time; Next, Skip and the timer move on
do
    local g = app.game
    assert(g.watch == true, "shown one at a time by default")
    local seen_watch, seen_dice, guard = 0, false, 0
    while g.phase ~= "done" and guard < 200 do
        guard = guard + 1
        if g.phase == "watch" then
            seen_watch = seen_watch + 1
            if g.actor == "dice" then seen_dice = true
            else assert(g.players[g.actor].ai and g.msg:find(g.players[g.actor].name, 1, true), "says who moved") end
            paint(app)
            if seen_watch % 3 == 0 then runq() -- the timer moves on by itself
            else press(app, "Next ›") end
        elseif g.phase == "trade" then press(app, "Stand")
        elseif g.phase == "bet" then press(app, Sabacc.owe(g) > 0 and "Junk" or "Check") end
        if g.phase == "done" then break end
        g = app.game
    end
    assert(seen_watch > 0 and seen_dice, "saw opponents' moves and the dice")
    -- Skip jumps straight to your move
    press(app, "Next hand")
    guard = 0
    while app.game.phase == "watch" and guard < 5 do guard = guard + 1; press(app, "Skip to my turn") end
    assert(app.game.phase == "trade" or app.game.phase == "bet" or app.game.phase == "done")
    -- the ☰ setting turns it off: no more pauses
    app:togglePace()
    assert(app.game.watch == false and STORE["sabacc/pace"] == "instant")
    guard = 0
    while app.game.phase ~= "done" and guard < 40 do
        guard = guard + 1
        assert(app.game.phase ~= "watch", "no pauses when instant")
        if app.game.phase == "trade" then press(app, "Stand") else press(app, Sabacc.owe(app.game) > 0 and "Junk" or "Check") end
    end
    app:togglePace()
    assert(app.game.watch == true)
    while top() ~= app do UIManager:close(top()) end -- the confirmation toasts
end

-- Winning hands opens the drawn chart; a tap goes back to the table
for _, item in ipairs(app:menuItems()) do if item.text == "Winning hands" then item.callback() end end
local chart = top()
assert(chart.name == "sabacc_hands")
chart[1]:paintTo(fakebb, 0, 0)
chart[1]:onTap(nil, { pos = { x = 10, y = 10 } })
assert(top() == app, "tap closes the chart")

-- The regulars: profiles of all ten, two pages, the ones at your table tagged
for _, item in ipairs(app:menuItems()) do if item.text == "The regulars" then item.callback() end end
local regs = top()
assert(regs.name == "sabacc_regulars" and regs.page == 1)
regs[1]:paintTo(fakebb, 0, 0)
for _, r in ipairs(Sabacc.ROSTER) do assert(r.story and r.style and #r.story > 20, r.name) end
regs:turn(1); assert(regs.page == 2); regs[1]:paintTo(fakebb, 0, 0)
regs:turn(1); assert(regs.page == 2, "no page 3")
regs:onClose()
assert(top() == app)

-- How to play opens a scrollable viewer with the full rules
app:showHelp()
assert(top()._name == "TextViewer" and top().text:find("Outer Rim Sabacc League") and top().text:find("Straight Khyron")
    and top().text:find("CONTROLS") and top().text:find("HOUSE CHOICES"))
UIManager:close(top())

-- raise picker: Raise opens it, −10 / +10 set the amount (capped at your credits), Raise to confirms
do
    local guard = 0
    while app.game.phase ~= "bet" do
        guard = guard + 1; assert(guard < 40, "never reached betting")
        if app.game.phase == "watch" then press(app, "Skip to my turn")
        elseif app.game.phase == "trade" then press(app, "Stand")
        elseif app.game.phase == "done" or app.game.phase == "broke" then
            press(app, app.game.phase == "done" and "Next hand" or "New table")
        end
    end
    local g, me = app.game, app.game.players[1]
    me.credits = 75
    local owe, bet = Sabacc.owe(g), g.bet
    press(app, "Raise")
    assert(app.raise_by == 10)
    press(app, "+10"); press(app, "+10")
    assert(app.raise_by == 30)
    press(app, "−10")
    assert(app.raise_by == 20)
    for _ = 1, 10 do app:stepRaise(10) end
    assert(app.raise_by == math.floor((75 - owe) / 10) * 10, "capped at what you can afford")
    press(app, "Cancel")
    assert(app.raise_by == nil and g.bet == bet, "cancel leaves the bet alone")
    press(app, "Raise"); press(app, "+10")
    local before = me.credits
    press(app, "Raise to " .. (bet + 20))
    assert(app.raise_by == nil and before - me.credits == owe + 20, "paid what you owed plus the raise")
end

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
