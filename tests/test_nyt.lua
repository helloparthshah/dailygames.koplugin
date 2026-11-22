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
for _,k in ipairs{"S","L","A","T","E","ENTER"} do app:onKey(k) end
assert(#app.state.guesses==1)
local ks = app:keyStates(); assert(ks.A=="correct" and ks.S=="absent" and ks.E=="correct", "key states")
app:onKey("ENTER"); assert(app.status=="Not enough letters")

for _,k in ipairs{"C","R","A","N","X","DEL","E","ENTER"} do app:onKey(k) end
assert(app:isWon()); print("wordle status:", app.status)
assert(STORE["progress/wordle"].state.guesses[2]=="CRANE")
app:onClose()
-- relaunch restores
plug:onDailyGamesWordle(); assert(top():isWon()); top():onClose()

-- CONNECTIONS
local cats = {}
local words = {{"A1","A2","A3","LONG WORD THAT MUST WRAP"},{"B1","B2","B3","B4"},{"C1","C2","C3","C4"},{"D1","D2","D3","D4"}}
local pos = 0
for i, ws in ipairs(words) do local cards = {}; for _, w in ipairs(ws) do cards[#cards+1]={content=w, position=(pos*7)%16}; pos=pos+1 end; cats[i]={title="T"..i, cards=cards} end
ROUTES[N.."/connections/v2/"..d..".json"] = function() return {categories=cats, id=5}, 200 end
plug:onDailyGamesConnections(); app = top(); assert(app._name=="connections_app")
assert(#app.state.remaining==16)
for _,w in ipairs{"A1","A2","A3","LONG WORD THAT MUST WRAP"} do app:toggle(w) end
press(app, "Submit (4/4)"); assert(#app.state.solved==1 and #app.state.remaining==12)
for _,w in ipairs{"B1","B2","B3","C1"} do app:toggle(w) end; press(app, "Submit (4/4)")
assert(app.state.mistakes==1 and app.status=="One away…", app.status)
for _,w in ipairs{"B1","B2","B3","C1"} do app:toggle(w) end; press(app, "Submit (4/4)"); assert(app.status=="Already guessed!" and app.state.mistakes==1); press(app, "Deselect")
for i=1,3 do for _,w in ipairs{"B1","B2","C2","D"..i} do app:toggle(w) end; press(app, "Submit (4/4)") end
assert(app:isOver() and #app.state.solved==4 and #app.state.remaining==0); print("conn:", app.status)
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
app:tapCell(1,1); app:tapCell(1,2); app:tapCell(1,3); press(app, "Undo"); assert(#app.state.path==2)
app:tapCell(1,3); app:tapCell(1,1); assert(#app.state.path==1, "tap earlier letter backs up") ; app:tapCell(1,2)
app:tapCell(3,4); assert(#app.state.path==1) -- non adjacent restarts
app:clearPath()
for c=1,4 do app:tapCell(1,c) end; assert(app:pathWord()=="CATS"); app:tapCell(1,4) -- tap last letter again submits
assert(#app.state.found==1)
press(app, "Hint"); assert(app.state.hint=="DOGS")
local marks = app:cellMarks(); assert(marks["1:1"]=="theme" and marks["2:1"]=="hint")
-- wrong path spelling DOGS? use diagonal path not matching coords: D(2,1) O(2,2) G(2,3) S(1,4) -> S at row1 col4 adjacent to G(2,3)
app:tapCell(2,1); app:tapCell(2,2); app:tapCell(2,3); app:tapCell(1,4); assert(app:pathWord()=="DOGS"); press(app,"Submit"); assert(#app.state.found==1, "wrong cells must not count"); assert(app.status:find("isn"))
for c=1,4 do app:tapCell(2,c) end; press(app,"Submit"); assert(app:isOver()); print("strands:", app.status)
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
app:onKey("C"); app:onKey("A"); assert(app.state.cursor==3)
app:onKey("X"); assert(app.state.entries[3]=="X" and app.state.cursor==7, "full word jumps to next clue")
app.state.cursor = 3; app:onKey("DEL"); assert(not app.state.entries[3]); app:onKey("T")
assert(app:currentClue().text=="Web" and app.state.cursor==7)
press(app,"‹"); assert(app:currentClue().text=="Pet"); press(app,"›"); assert(app:currentClue().text=="Web")
press(app,"Across"); assert(app.state.direction=="Down" and app:currentClue().text=="Moo")
-- tap cells through the drawn grid
local grid
local function findGrid(w) if type(w)~="table" then return end if w.cell and w.app then return w end for _, ch in ipairs(w) do local g = findGrid(ch) if g then return g end end end
grid = findGrid(app)
assert(grid, "grid board")
local function tapCell(idx) local r = math.floor((idx-1)/3); local c = (idx-1)%3; grid:tapAt(grid.ox + c*grid.cell + 1, grid.oy + r*grid.cell + 1) end
app.state.cursor = 2; tapCell(5); assert(app.state.cursor==2, "block ignored")
grid = nil; grid = findGrid(app)
tapCell(9); assert(app.state.cursor==9)
grid = findGrid(app)
tapCell(9); assert(app.state.direction=="Across", "second tap toggles")
app.state.entries[4]="O"; app.state.entries[6]="O"; app.state.entries[7]="W"; app.state.entries[8]="Q"; app.state.cursor=9
app:onKey("B"); assert(not app:isSolved() and app.status=="Not quite. Try Check.", app.status)
press(app,"Check"); assert(app.wrong[8] and app.status=="1 wrong letter marked", app.status)
app.state.cursor=8; app.state.direction="Across"; app:onKey("E"); assert(app:isSolved() and not app.wrong[8]); print("mini:", app.status)
press(app,"Clues"); local menu = top(); assert(menu._name=="Menu" and #menu.item_table==5); print(menu.item_table[3].text); menu.item_table[5].callback()
assert(app:currentClue().text=="Tob")
app:onClose(); assert(STORE["progress/crossword_mini"].date=="2026-11-22")
-- daily without cookie fails with hint
ROUTES[N.."/crosswords/v6/puzzle/daily.json"] = function(o) assert(o.headers and o.headers.Cookie=="NYT-S=abc"); return {body={body}, publicationDate="2026-11-22"}, 200 end
STORE.nyt_s_cookie="abc"; plug:onDailyGamesCrossword(); assert(top()._name=="crossword_app"); top():onClose()

-- HUB
plug:onDailyGamesHub(); local hub=top(); assert(hub._name=="ButtonDialog" and #hub.buttons==8); hub.buttons[8][1].callback()
-- COSTCODLE
local C = require("dailygames/costcodle")
assert(C.gameNumber("2026-11-22") == 1160 and C.productId(1160) == 1220 and C.productId(100) == 100)
local j = C.judge(5.80, 5.99); assert(j.closeness == "win")
j = C.judge(5.00, 5.99); assert(j.closeness == "near" and j.direction == "higher")
j = C.judge(12, 5.99); assert(j.closeness == "far" and j.direction == "lower")
ROUTES["https://costcodle.com/games.json"] = function() return { ["game-" .. C.productId(C.gameNumber(d))] = { name = "Chicken Thighs", price = "$5.99" } }, 200 end
plug:onDailyGamesCostcodle(); app = top(); assert(app._name == "costcodle_app", tostring(app._name))
for _, k in ipairs { "1", "2", "ENTER" } do app:onKey(k) end
assert(#app.state.guesses == 1 and app.state.guesses[1] == 12)
for _, k in ipairs { "5", ".", ".", "9", "9", "9", "ENTER" } do app:onKey(k) end
assert(app.state.guesses[2] == 5.99 and app:isWon(), tostring(app.state.guesses[2]))
print("costcodle:", app.status)
app:onClose()
print("ALL NYT TESTS PASSED")
