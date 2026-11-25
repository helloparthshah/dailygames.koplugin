dofile(STUBS)
local P = dofile(PLUGDIR.."/main.lua")
local plug = P:new{ui={menu={registerToMainMenu=function() end}}}
local K = "https://krillion.io"
local calls = {}
local answers = { ["Paris"]={accepted=true,tier="plankton",score=10,answer="Paris",quip="Everyone says Paris.",receipt="r1"},
  ["Ulan Bator"]={correction="Ulaanbaatar"}, ["Ulaanbaatar"]={accepted=true,tier="rare",score=60,answer="Ulaanbaatar",receipt="r2"},
  ["zzz"]={accepted=false,rejectionReason="Not a fish.",receipt="rz"}, [""]={accepted=false,receipt="r0"} }
ROUTES[K.."/api/today"] = function() return {date="2026-11-21",dayNumber=129,resetsAt="2026-11-22T05:00:00.000Z",prompts={{id="p1",text="A"},{id="p2",text="B"},{id="p3",text="C"},{id="p4",text="D"},{id="p5",text="E"},{id="p6",text="F"},{id="p7",text="G"}}}, 200 end
ROUTES[K.."/api/submit"] = function(o) table.insert(calls, o.body); return answers[o.body.answer] or {accepted=true,tier="schooler",score=30,answer=o.body.answer,receipt="rx"}, 200 end
ROUTES[K.."/api/today/complete"] = function(o) table.insert(calls, o.body); return {betterThan=42.4}, 200 end
local function answer(txt) local d = top(); assert(d._name=="InputDialog", "expected input, got "..tostring(d._name)); d.input = txt; d.buttons[1][2].callback() end
plug:onDailyGamesKrillion()
top().ok_callback(); runq()
answer("Paris"); top().ok_callback(); runq()
answer("Ulan Bator"); assert(top().input=="Ulaanbaatar"); answer("Ulaanbaatar"); top().ok_callback(); runq()
answer("zzz"); assert(top()._name=="InputDialog")
top().buttons[1][1].callback(); top().cancel_callback()
plug:onDailyGamesKrillion(); top().ok_callback(); runq()
top().input = "zzz"; for i=1,30 do CLOCK=CLOCK+1; if #QUEUE==0 then break end; runq() end
assert(top()._name=="ConfirmBox"); top().ok_callback(); runq()
for i=5,7 do answer("x"..i); top().ok_callback(); if i<7 then runq() end end
assert(top()._name=="TextViewer"); print(top().text)
top().buttons_table[1][1].callback()
local c = calls[#calls]; print("complete record", c.record, c.score, table.concat(c.receipts, ","))
-- replay same day shows summary
plug:onDailyGamesKrillion(); assert(top()._name=="TextViewer" and top().text:find("already dove"))
-- stats
local Kr = require("dailygames/krillion"); Kr.showStats(); print(top().text)
-- reset today's dive from the summary screen: replay is allowed and not submitted again
os.date = (function(real) return function(fmt, t) if fmt == "!%Y-%m-%d" then return "2026-11-21" end return real(fmt, t) end end)(os.date)
plug:onDailyGamesKrillion(); local summary = top(); assert(summary._name == "TextViewer")
local resetBtn
for _, b in ipairs(summary.buttons_table[1]) do if b.text == "Reset today's dive" then resetBtn = b end end
assert(resetBtn, "summary has a reset button")
resetBtn.callback(); top().ok_callback()
assert(top()._name == "ConfirmBox" and top().text:find("Seven prompts"), "dive restarts after reset"); UIManager_dummy = nil
for i = #SHOWN, 1, -1 do SHOWN[i] = nil end
assert(STORE["krillion/history"]["2026-11-21"] == nil and STORE["krillion/replay_date"] == "2026-11-21")
local before = #calls
plug:onDailyGamesKrillion(); assert(top()._name == "ConfirmBox", "fresh intro after reset")
top().ok_callback(); runq()
for i = 1, 7 do answer("x" .. i); top().ok_callback(); if i < 7 then runq() end end
for _, c in ipairs(calls) do assert(c.record == nil or c ~= calls[#calls] or #calls == before, "") end
local completes = 0
for i = before + 1, #calls do if calls[i].score and calls[i].record ~= nil then completes = completes + 1 end end
assert(completes == 0, "replay must not call /api/today/complete")
assert(top()._name == "TextViewer")
-- summary: how many others gave your answer, and each prompt's top answers
local pops = 0
ROUTES[K.."/api/answer-popularity?date=2026-11-21"] = function()
    pops = pops + 1
    return { date = "2026-11-21", asOf = "x", prompts = {
        p1 = { x1 = 5, Rugby = 700, Volleyball = 200, Kickball = 95 },
        p2 = { x2 = 1, Canada = 99 } } }, 200
end
for i = #SHOWN, 1, -1 do SHOWN[i] = nil end
plug:onDailyGamesKrillion(); local st = top().text
assert(st:find("4 other divers chose this", 1, true), st)
assert(st:find("Top: Rugby 70% · Volleyball 20% · Kickball 10% · x1 <1%", 1, true), st)
assert(st:find("0 other divers chose this", 1, true), "only you gave x2")
plug:onDailyGamesKrillion(); assert(pops == 1, "popularity is cached")
print("KRILLION PASSED")
