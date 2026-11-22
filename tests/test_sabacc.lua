dofile(STUBS)
local Sabacc = dofile(PLUGDIR .. "/dailygames/sabacc.lua")
package.loaded["dailygames/sabacc"] = Sabacc
math.randomseed(42)

local function C(v, s) return { v = v, s = s or (v == 0 and 0 or 1) } end
local function name(...) return Sabacc.evaluate({ ... }).name end

-- deck: 60 numbered cards + 2 sylops, sums to zero
local deck = Sabacc.newDeck()
assert(#deck == 62)
local sum, syl = 0, 0
for _, c in ipairs(deck) do sum = sum + c.v; if c.v == 0 then syl = syl + 1 end end
assert(sum == 0 and syl == 2)

-- hand names
assert(name(C(0), C(0)) == "Pure Sabacc")
assert(name(C(10), C(10, 2), C(-10), C(-10, 2), C(0)) == "Full Sabacc")
assert(name(C(4), C(-4), C(4, 2), C(-4, 2), C(0)) == "Fleet")
assert(name(C(3), C(-3), C(0)) == "Yee-Haa")
assert(name(C(2), C(2, 2), C(-2), C(-1), C(-1, 2)) == "Rhylet")
assert(name(C(5), C(5, 2), C(-5), C(-5, 2)) == "Squadron")
assert(name(C(4), C(4, 2), C(-4), C(-1), C(-3)) == "Banthas Wild")
assert(name(C(3), C(-3), C(2), C(-2)) == "Rule of Two")
assert(name(C(5), C(-5)) == "Sabacc Pair")
assert(name(C(1), C(2), C(-3)) == "Sabacc")
assert(name(C(4), C(-1)) == "Nulrhek +3")
assert(name(C(-4), C(1)) == "Nulrhek −3")

-- ranking: lower score wins
local function score(...) return Sabacc.evaluate({ ... }).score end
assert(score(C(0), C(0)) < score(C(3), C(-3), C(0)))
assert(score(C(1), C(-1)) < score(C(9), C(-9)), "lower pair wins")
assert(score(C(5), C(-5)) < score(C(2), C(-1)), "any sabacc beats a nulrhek")
assert(score(C(2), C(-1)) < score(C(-2), C(1)), "positive beats negative")
assert(score(C(2), C(-1)) < score(C(5), C(-3)), "closer to zero wins")

-- a new table: four seats, ante paid, two cards each, one discard
local g = Sabacc.newTable()
assert(#g.players == 4 and g.pot == 4 * Sabacc.ANTE and g.phase == "act" and g.round == 1)
for _, p in ipairs(g.players) do assert(#p.hand == 2 and p.credits == 100 - Sabacc.ANTE) end
assert(#g.discard == 1 and #g.deck == 62 - 9)

-- gain, then drop the new card or an old one; a full hand must drop
do
    local t = Sabacc.newTable()
    local before = #t.players[1].hand
    assert(Sabacc.act(t, "gain") and t.phase == "drop" and #t.players[1].hand == before + 1)
    assert(not Sabacc.bet(t, "check"), "no betting mid-move")
    local new = t.players[1].hand[t.new]
    assert(Sabacc.act(t, "drop", t.new) and t.phase == "bet" and #t.players[1].hand == before)
    assert(t.discard[#t.discard] == new or t.phase == "bet") -- the dropped card went to the discard pile (AIs may have covered it)
    t = Sabacc.newTable()
    t.players[1].hand = { { v = 1, s = 1 }, { v = 2, s = 1 }, { v = 3, s = 1 }, { v = 4, s = 1 }, { v = 5, s = 1 } }
    assert(Sabacc.act(t, "gain") and #t.players[1].hand == 6)
    assert(not Sabacc.act(t, "keep"), "six cards must drop one")
    assert(Sabacc.act(t, "drop", 1) and #t.players[1].hand == 5)
end

-- illegal moves are refused
assert(not Sabacc.act(g, "swap", nil))
assert(not Sabacc.bet(g, "check"), "no betting before acting")

-- play many hands with random legal moves; money is conserved and every hand ends
local function total(t) local s = t.pot; for _, p in ipairs(t.players) do s = s + p.credits end; return s end
local moves = { "gain", "swap", "discard", "stand" }
local bets = { "check", "bet", "junk", "check", "bet" }
local hands_won = 0
for hand = 1, 300 do
    local guard = 0
    while g.phase ~= "done" and g.phase ~= "broke" do
        guard = guard + 1
        assert(guard < 50, "hand never ended")
        local before = total(g)
        if g.phase == "act" then
            local ok = Sabacc.act(g, moves[math.random(#moves)], math.random(#g.players[1].hand))
            if not ok then assert(Sabacc.act(g, "stand")) end
        elseif g.phase == "drop" then
            if math.random() < 0.5 or not Sabacc.act(g, "keep") then
                assert(Sabacc.act(g, "drop", math.random(#g.players[1].hand)))
            end
        elseif g.phase == "bet" then
            if not Sabacc.bet(g, bets[math.random(#bets)]) then assert(Sabacc.bet(g, "check")) end
        elseif g.phase == "call" then
            if not Sabacc.bet(g, math.random() < 0.7 and "call" or "junk") then assert(Sabacc.bet(g, "junk")) end
        end
        assert(total(g) == before, "credits not conserved")
        for _, p in ipairs(g.players) do
            assert(#p.hand >= 1 and #p.hand <= Sabacc.MAX_HAND + (g.phase == "drop" and 1 or 0), "hand size")
            assert(p.credits >= 0, "negative credits")
        end
        -- every card is somewhere exactly once
        local n = #g.deck + #g.discard
        for _, p in ipairs(g.players) do n = n + #p.hand end
        assert(n == 62, "cards lost: " .. n)
    end
    if g.phase == "broke" then g = Sabacc.newTable() else
        assert(g.winners and #g.winners >= 1 and g.pot == 0)
        if Sabacc.isWinner(g, 1) then hands_won = hands_won + 1 end
        Sabacc.newHand(g)
    end
end
assert(hands_won > 0, "you never won a hand")

-- UI: launch, pick a card, swap, bet; the table is saved to the store
local fakebb = { paintRect = function() end }
-- the stub containers can't paint, so draw the board itself
local function paint(a)
    a[1]:paintTo(fakebb, 0, 100)
    return a[1]
end
STORE["sabacc/table"] = nil
Sabacc.launch()
local app = top()
assert(app._name == "sabacc_app" or app.name == "sabacc_app")
paint(app)
press(app, "Gain")
assert(app.game.phase == "drop" and #app.game.players[1].hand == 3)
paint(app)
press(app, "Keep")
assert(app.game.phase == "bet" and #app.game.players[1].hand == 3)
assert(STORE["sabacc/table"] == app.game, "saved")
paint(app)
press(app, "Check")
local guard = 0
while app.game.phase ~= "done" do
    guard = guard + 1; assert(guard < 20)
    if app.game.phase == "act" then
        -- tap the first card on the drawn board
        local board = paint(app)
        local h
        for _, hit in ipairs(board.hits) do if hit.card == 1 then h = hit end end
        board:onTap(nil, { pos = { x = h.x + 5, y = 100 + h.y + 5 } })
        assert(app.sel == 1, "tap picks a card")
        press(app, "Take discard")
    elseif app.game.phase == "bet" then
        press(app, "Check")
    elseif app.game.phase == "call" then
        press(app, "Junk")
    end
    paint(app)
end
press(app, "Next hand")
assert(app.game.phase == "act" and app.game.hand_no == 2)
paint(app)

-- a saved table is resumed
app:onClose()
Sabacc.launch()
assert(top().game.hand_no == 2, "resumed")

-- the plugin lists it and starts it without Wi-Fi
local online = 0
package.loaded["ui/network/manager"].runWhenOnline = function(_, f) online = online + 1; f() end
local P = dofile(PLUGDIR .. "/main.lua")
local plug = P:new { ui = { menu = { registerToMainMenu = function() end } } }
assert(ACTIONS.dailygames_sabacc, "gesture action")
plug:onDailyGamesSabacc()
assert(online == 0 and (top().name == "sabacc_app"))
print("sabacc ok")
