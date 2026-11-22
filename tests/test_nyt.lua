dofile(STUBS)
local P = dofile(PLUGDIR.."/main.lua")
local plug = P:new{ui={menu={registerToMainMenu=function() end}}}
local mi = {}; plug:addToMainMenu(mi); assert(mi.daily_games and #mi.daily_games.sub_item_table >= 7)
assert(ACTIONS.dailygames_hub and ACTIONS.dailygames_krillion and ACTIONS.dailygames_wordle.title=="Daily Games: Wordle")
assert(P.onDailyGamesStrands)
local d = os.date("%Y-%m-%d")
local N = "https://www.nytimes.com/svc"
-- WORDLE
local W = require("dailygames/wordle")
local e = W.evaluate("SPEED", "ABIDE"); assert(e[1]=="absent" and e[3]=="present" and e[4]=="absent" and e[5]=="present", table.concat(e,","))
e = W.evaluate("EERIE", "THREE"); print("EERIE/THREE", table.concat(e,","))
ROUTES[N.."/wordle/v2/"..d..".json"] = function() return {solution="crane", days_since_launch=1600}, 200 end
plug:onDailyGamesWordle()
local app = top(); assert(app._name=="wordle_app", app._name)
for _,k in ipairs{"S","L","A","T","E","ENTER"} do press(app, k) end
assert(#app.state.guesses==1)
local labels = {}; for _,b in ipairs(findButtons(app)) do labels[b.text]=true end
assert(labels["■A"] and labels["·S·"] and labels["■E"], "key labels")
for _,k in ipairs{"C","R","A","N","X","DEL","E","ENTER"} do app:onKey(k) end
assert(app:isWon()); print("wordle status:", app:statusText())
assert(STORE["progress/wordle"].state.guesses[2]=="CRANE")
app:onClose()
-- relaunch restores
plug:onDailyGamesWordle(); assert(top():isWon()); top():onClose()

-- CONNECTIONS
local cats = {}
local words = {{"A1","A2","A3","A4"},{"B1","B2","B3","B4"},{"C1","C2","C3","C4"},{"D1","D2","D3","D4"}}
local pos = 0
for i, ws in ipairs(words) do local cards = {}; for _, w in ipairs(ws) do cards[#cards+1]={content=w, position=(pos*7)%16}; pos=pos+1 end; cats[i]={title="T"..i, cards=cards} end
ROUTES[N.."/connections/v2/"..d..".json"] = function() return {categories=cats, id=5}, 200 end
plug:onDailyGamesConnections(); app = top(); assert(app._name=="connections_app")
assert(#app.state.remaining==16)
for _,w in ipairs{"A1","A2","A3","A4"} do press(app, w) end
press(app, "Submit (4/4)"); assert(#app.state.solved==1 and #app.state.remaining==12)
for _,w in ipairs{"B1","B2","B3","C1"} do press(app, w) end; press(app, "Submit (4/4)")
assert(app.state.mistakes==1); print(LOG[#LOG])
for _,w in ipairs{"B1","B2","B3","C1"} do press(app, w) end; press(app, "Submit (4/4)"); print(LOG[#LOG]); assert(app.state.mistakes==1); press(app, "Deselect")
for i=1,3 do for _,w in ipairs{"B1","B2","C2","D"..i} do press(app, w) end; press(app, "Submit (4/4)") end
assert(app:isOver() and #app.state.solved==4 and #app.state.remaining==0); print("conn:", app:statusText())
app:onClose()

-- STRANDS
ROUTES[N.."/strands/v2/"..d..".json"] = function() return {clue="Pets", startingBoard={"CATX","DOGX","XXXX"},
  themeWords={"CAT"}, spangram="DOGS", themeCoords={CAT={{0,0},{0,1},{0,2}}}, spangramCoords={{1,0},{1,1},{1,2}} }, 200 end
plug:onDailyGamesStrands(); app = top(); assert(app._name=="strands_app")
-- note CAT 3 letters < 4: test "too short", then add a 4 letter word board
app:onClose()
ROUTES[N.."/strands/v2/"..d..".json"] = function() return {clue="Pets", startingBoard={"CATS","DOGS","XXXX"},
  themeWords={"CATS"}, spangram="DOGS", themeCoords={CATS={{0,0},{0,1},{0,2},{0,3}}}, spangramCoords={{1,0},{1,1},{1,2},{1,3}} }, 200 end
STORE["progress/strands"] = nil
plug:onDailyGamesStrands(); app = top()
app:tapCell(1,1); app:tapCell(1,2); app:tapCell(1,3); app:tapCell(1,3); assert(#app.state.path==2) -- undo
app:tapCell(3,4); assert(#app.state.path==1) -- non adjacent restarts
app:clearPath()
for c=1,4 do app:tapCell(1,c) end; assert(app:pathWord()=="CATS"); press(app, "Submit")
assert(#app.state.found==1)
press(app, "Hint"); assert(app.state.hint=="DOGS")
local lbl={}; for _,b in ipairs(findButtons(app)) do lbl[b.text]=true end; assert(lbl["(C)"] and lbl["{D}"])
-- wrong path spelling DOGS? use diagonal path not matching coords: D(2,1) O(2,2) G(2,3) S(1,4) -> S at row1 col4 adjacent to G(2,3)
app:tapCell(2,1); app:tapCell(2,2); app:tapCell(2,3); app:tapCell(1,4); assert(app:pathWord()=="DOGS"); press(app,"Submit"); assert(#app.state.found==1, "wrong cells must not count")
for c=1,4 do app:tapCell(2,c) end; press(app,"Submit"); assert(app:isOver()); print(LOG[#LOG])
app:onClose()

-- CROSSWORD (3x3 with one block)
local function cell(a, l, clues) return {answer=a, label=l, clues=clues} end
local body = {dimensions={width=3,height=3}, cells={
  cell("C","1",{0,2}), cell("A","2",{0,3}), cell("T","3",{0,4}),
  cell("O",nil,{1,2}), {}, cell("O",nil,{1,4}),
  cell("W","4",{1,2}), cell("E",nil,{1,3}), cell("B",nil,{1,4})},
  clues={ {label="1",direction="Across",text={{plain="Pet"}},cells={0,1,2}}, {label="4",direction="Across",text={{plain="Web"}},cells={6,7,8}},
          {label="1",direction="Down",text={{plain="Moo"}},cells={0,3,6}}, {label="2",direction="Down",text={{plain="AE"}},cells={1,7}},
          {label="3",direction="Down",text={{plain="Tob"}},cells={2,5,8}} }}
-- fix: 2 Down cells {1,4?} grid index 4 is block; use cells 1 and 7 isn't contiguous but fine for test
ROUTES[N.."/crosswords/v6/puzzle/mini.json"] = function(o) return {body={body}, publicationDate="2026-11-22"}, 200 end
plug:onDailyGamesMini(); app = top(); assert(app._name=="crossword_app", tostring(app._name))
assert(app:currentClue().text=="Pet")
for _,k in ipairs{"C","A","X"} do press(app,k) end
assert(app.state.entries[3]=="X" and app.state.cursor==3)
press(app,"DEL"); assert(not app.state.entries[3]); press(app,"T")
press(app,"Next ›"); assert(app:currentClue().text=="Web" and app.state.cursor==7)
press(app,"Across"); assert(app.state.direction=="Down" and app:currentClue().text=="Moo")
press(app,"▲"); assert(app.state.cursor==4); press(app,"▲"); assert(app.state.cursor==1)
press(app,"▶"); assert(app.state.direction=="Across" and app.state.cursor==1); press(app,"▶"); assert(app.state.cursor==2)
-- tap cell
local cells = findAll(app, "InputContainer"); assert(#cells==9, #cells)
cells[5]:onTap(); assert(app.state.cursor==2) -- block ignored
cells[9]:onTap(); assert(app.state.cursor==9)
cells[9]:onTap(); assert(app.state.direction=="Down")
app.state.entries[4]="O"; app.state.entries[6]="O"; app.state.entries[7]="W"; app.state.entries[8]="Q"; app.state.cursor=9
press(app,"B"); assert(not app:isSolved())
press(app,"Check"); local cb = top(); assert(cb._name=="ConfirmBox", cb._name); print(cb.text); cb.ok_callback(); assert(not app.state.entries[8])
app.state.cursor=8; app.state.direction="Across"; press(app,"E"); assert(app:isSolved()); print(LOG[#LOG])
press(app,"Clues"); local menu = top(); assert(menu._name=="Menu" and #menu.item_table==5); print(menu.item_table[3].text); menu.item_table[5].callback()
assert(app:currentClue().text=="Tob")
app:onClose(); assert(STORE["progress/crossword_mini"].date=="2026-11-22")
-- daily without cookie fails with hint
ROUTES[N.."/crosswords/v6/puzzle/daily.json"] = function(o) assert(o.headers and o.headers.Cookie=="NYT-S=abc"); return {body={body}, publicationDate="2026-11-22"}, 200 end
STORE.nyt_s_cookie="abc"; plug:onDailyGamesCrossword(); assert(top()._name=="crossword_app"); top():onClose()

-- HUB
plug:onDailyGamesHub(); local hub=top(); assert(hub._name=="ButtonDialog" and #hub.buttons==7); hub.buttons[7][1].callback()
print("ALL NYT TESTS PASSED")
