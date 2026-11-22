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
-- opening a game must ask the e-ink panel for a full refresh (not just repaint memory)
local refreshed = false
for _, d in ipairs(DIRTY) do if d.w == app and d.type == "full" then refreshed = true end end
assert(refreshed, "game requested a full refresh when shown")
for _,k in ipairs{"S","L","A","T","E","ENTER"} do app:onKey(k) end
assert(#app.state.guesses==1)
local ks = app:keyStates(); assert(ks.A=="correct" and ks.S=="absent" and ks.E=="correct", "key states")
app:onKey("ENTER"); assert(app.status=="Not enough letters")
assert(W.isWord("CRANE") and W.isWord("SLATE") and not W.isWord("ZZZZZ") and not W.isWord("XQJVK"))
for _,k in ipairs{"X","Q","J","V","K","ENTER"} do app:onKey(k) end
assert(app.status=="Not in word list" and #app.state.guesses==1 and app.state.current=="XQJVK")
for _=1,5 do app:onKey("DEL") end

for _,k in ipairs{"C","R","A","N","X","DEL","E","ENTER"} do app:onKey(k) end
assert(app:isWon()); print("wordle status:", app.status)
assert(STORE["progress/wordle"].state.guesses[2]=="CRANE")
app:onClose()
-- relaunch restores
plug:onDailyGamesWordle(); assert(top():isWon())
-- Restart puzzle from the menu clears today's progress
app = top(); app:showMenu(); local menu = top(); assert(menu._name == "ButtonDialog")
local restart
for _, row in ipairs(menu.buttons) do if row[1].text == "Restart puzzle" then restart = row[1] end end
assert(restart, "menu has Restart puzzle"); restart.callback(); top().ok_callback()
assert(#app.state.guesses == 0 and not app:isOver() and STORE["progress/wordle"] == nil)
app:onKey("A"); app:onKey("B"); assert(app.state.current == "AB")
app:onClose()
-- a saved game from another day is ignored
STORE["progress/wordle"] = { date = "2000-01-01", state = { guesses = { "CRANE" }, current = "" } }
plug:onDailyGamesWordle(); assert(#top().state.guesses == 0, "yesterday's game is not loaded"); top():onClose()

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

-- HUB: ticks for finished games, "…" for started ones
local function hubLabel(id)
    plug:onDailyGamesHub(); local hub = top()
    for _, row in ipairs(hub.buttons) do
        if row[1].text:find(id, 1, true) then local t = row[1].text; UIManager_close = hub; return t end
    end
end
CLOCK = os.time(os.date("*t")) -- the stubs fake os.time(); use the real time here
STORE["progress/wordle"] = { date = d, state = { guesses = { "CRANE" }, current = "", done = true } }
STORE["progress/connections"] = { date = d, state = { remaining = {}, mistakes = 1 } }
STORE["progress/strands"] = { date = "2000-01-01", state = { done = true } }
plug:onDailyGamesHub(); local hubd = top(); local labels = {}
for _, row in ipairs(hubd.buttons) do labels[#labels + 1] = row[1].text end
local joined = table.concat(labels, "|")
assert(joined:find("Wordle  ✓", 1, true), joined)
assert(joined:find("Connections  …", 1, true), joined)
assert(joined:find("|Strands|", 1, true), "yesterday's finished game has no tick: " .. joined)
hubd.buttons[#hubd.buttons][1].callback()
-- a finished game records done when saved
plug:onDailyGamesConnections(); local capp = top(); capp:revealRest(); capp:save()
assert(STORE["progress/connections"].state.done == true, "connections marks done"); capp:onClose()

-- HUB
plug:onDailyGamesHub(); local hub=top(); assert(hub._name=="ButtonDialog" and #hub.buttons==15); hub.buttons[15][1].callback()
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
-- FOODGUESSR
local F = require("dailygames/foodguessr")
local sug = F.suggest("mex"); assert(sug[1] == "MX", tostring(sug[1]))
sug = F.suggest("states"); assert(sug[1] == "US-48", "word match: " .. tostring(sug[1]))
assert(F.suggest("aland")[1] == "AX", "accent folding")
assert(F.compass(0) == "N" and F.compass(44) == "NE" and F.compass(181) == "S" and F.compass(350) == "N")
local pairsT = { ["CL-MX"] = { 6600, 150, 330 }, ["MX-PE"] = { 4300, 140, 320 }, ["AR-MX"] = { 7400, 145, 325 } }
-- pairs["CL-MX"] = { km, bearing CL->MX, bearing MX->CL }
local km, b = F.distance(pairsT, "CL", "MX"); assert(km == 6600 and b == 150)
km, b = F.distance(pairsT, "MX", "CL"); assert(km == 6600 and b == 330)
ROUTES["https://www.foodguessr.com/api/trpc/daily.today?batch=1&input=%7B%220%22%3A%7B%22json%22%3Anull%7D%7D"] = function()
    return { { result = { data = { json = { date = d .. "T00:00:00.000Z", v2Distances = { pairs = pairsT },
        rounds = { { food = { name = "Cuchufli", ingredients = "dough", informationHint = "sweet", countriesV2 = {
            { countryCode = "CL", name = "Chile" }, { countryCode = "AR", name = "Argentina" } } } },
          { food = { name = "Taco", countriesV2 = { { countryCode = "MX", name = "Mexico" } } } } } } } } } }, 200
end
plug:onDailyGamesFoodGuessr(); app = top(); assert(app._name == "foodguessr_app", tostring(app._name))
app:onKey("M"); app:onKey("E"); assert(app.input == "ME")
app:guess("MX")
local j = F.judge(app.rounds[1], app.pairs, "MX"); assert(not j.correct and j.km == 6600 and j.score == F.nearMiss(6600))
assert(app:guessLines()[1]:find("6,600 km"), app:guessLines()[1])
app:guess("AR"); assert(app:roundOver(1))
assert(F.roundScore(app.rounds[1], app.pairs, { "MX", "AR" }) == 1000 + 3000 + 0)
assert(F.roundScore(app.rounds[1], app.pairs, { "CL" }) == 5000)
app:nextRound(); assert(app.state.round == 2)
app:onClose()
plug:onDailyGamesFoodGuessr(); assert(top().state.round == 2, "progress restored"); top():onClose()
-- MORE/LESS
local ML = require("dailygames/moreless")
assert(ML.dayNumber("2026-11-21") == 450)
assert(ML.formatStat(3, "65000000000") == "$65,000,000,000" and ML.formatStat(2, "8.2") == "8.2" and ML.formatStat(0, "3350000") == "3,350,000")
local items = {}
for c = 0, 4 do for r = 1, 6 do items[#items + 1] = string.format('{"roundNumber":%d,"image":null,"title":"C%dR%d","description":null,"categoryId":%d}', r, c, r, c) end end
local payload = '{"rounds":[' .. table.concat(items, ",") .. '],"date":"2026-11-21"}'
local escaped = payload:gsub('\\', '\\\\'):gsub('"', '\\"')
local html = '<script>self.__next_f.push([1,"0:junk\\n"])</script><script>self.__next_f.push([1,"5:' .. escaped .. '"])</script>'
local parsed = ML.parsePage(html); assert(parsed and parsed.date == "2026-11-21" and #parsed.rounds == 30, "parse flight data")
ROUTES["https://lessgames.com/moreless"] = function(o) assert(o.raw); return html, 200 end
local guesses = 0
ROUTES["https://api.lessgames.com/moreless/guess"] = function(o)
    guesses = guesses + 1
    local r = o.body.roundIndex + 1
    return { correct = o.body.direction == "left", stats = { [tostring(r)] = "200", [tostring(r + 1)] = "100" } }, 200
end
plug:onDailyGamesMoreLess(); app = top(); assert(app._name == "moreless_app", tostring(app._name))
assert(app:items().title == "C0R1")
app:pick("left"); assert(app.state.revealed and app.state.results["0"][1] == true and app:statFor(2) == "100")
app:advance(); assert(app.state.round == 2 and app:items().title == "C0R2")
for c = 0, 4 do for r = (c == 0 and 2 or 1), 5 do app:pick(r % 2 == 0 and "right" or "left"); app:advance() end end
assert(app:isOver() and guesses == 25, "all rounds played: " .. guesses)
print("moreless score:", app:score())
app:onClose()
-- text fitting: long lists wrap into at most N lines that fit the width
do
    local UIm = require("dailygames/ui")
    local f, lines = UIm.fitLines("Strength, Resistance, Regeneration, Elemental", 120, 60, 3)
    assert(#lines >= 2 and #lines <= 3, #lines)
    for _, l in ipairs(lines) do assert(UIm.measure(f, l) <= 120, l) end
end
-- MARVELDLE
local MV = require("dailygames/marveldle")
local A = "https://api.marveldle.com/api"
local chars = {
    { id = "thor", name = "Thor", keywords = { "god of thunder" }, gender = "Male", type = "Hero", species = { "Asgardian" },
      powerTypes = { "Superhuman" }, origin = "Asgard", affiliations = { "Avengers" }, appearanceTypes = { "Movie" } },
    { id = "loki", name = "Loki", keywords = {}, gender = "Male", type = "Villain", species = { "Frost Giant" },
      powerTypes = { "Magic" }, origin = "Jotunheim", affiliations = { "None" }, appearanceTypes = { "Movie", "Series" } },
    { id = "tonystark", name = "Tony Stark", keywords = { "iron man" }, gender = "Male", type = "Hero", species = { "Human" },
      powerTypes = { "Technology" }, origin = "Earth", affiliations = { "Avengers" }, appearanceTypes = { "Movie" } },
}
assert(MV.suggest(chars, "sta")[1].id == "tonystark", "word in name")
assert(MV.suggest(chars, "iron")[1].id == "tonystark", "keyword")
ROUTES[A .. "/config/pick-id"] = function(o) assert(o.raw); return "11/22/2026 12:00:00 AM", 200 end
ROUTES[A .. "/session"] = function() return { id = "sess-1" }, 200 end
ROUTES[A .. "/characters/audiovisual"] = function(o) assert(o.headers.sessionId == "sess-1"); return chars, 200 end
ROUTES[A .. "/characters/audiovisual/guess/loki?dateId=11%2F22%2F2026%2012%3A00%3A00%20AM"] = function()
    return { gender = "Exact", type = "None", species = "None", powerTypes = "None", origin = "None", affiliations = "None",
             appearanceTypes = "Partial", id = "None", isExact = false }, 200 end
ROUTES[A .. "/characters/audiovisual/guess/thor?dateId=11%2F22%2F2026%2012%3A00%3A00%20AM"] = function()
    return { gender = "Exact", type = "Exact", species = "Exact", powerTypes = "Exact", origin = "Exact", affiliations = "Exact",
             appearanceTypes = "Exact", id = "Exact", isExact = true }, 200 end
plug:onDailyGamesMarveldle(); app = top(); assert(app._name == "marveldle_app" and app.date == "2026-11-22", tostring(app.date))
assert(STORE["marveldle/session"] == "sess-1")
for _, k in ipairs { "L", "O" } do app:onKey(k) end; assert(app.input == "lo")
app:guess(chars[2]); assert(#app.state.guesses == 1 and not app.state.won and app.input == "")
for i = 1, 4 do app.state.guesses[#app.state.guesses + 1] = { id = "loki", sim = {} } end
ROUTES[A .. "/characters/audiovisual/clue/1?dateId=11%2F22%2F2026%2012%3A00%3A00%20AM&language=en"] = function(o)
    assert(o.raw); return '<span>"Brother!"</span>', 200 end
app:showClues(); assert(top().text:find('Quote: "Brother!"', 1, true), top().text); UIManager_close_top = top()
for i = 1, 4 do table.remove(app.state.guesses) end
app:guess(chars[1]); assert(app.state.won and app.status:find("Thor"), app.status)
app:onClose()
plug:onDailyGamesMarveldle(); assert(top().state.won, "progress restored"); top():onClose()
-- WHERETAKEN
local WT = require("dailygames/wheretaken")
assert(WT.distance(48.8566, 2.3522, 51.5074, -0.1278) == 344, "Paris-London " .. WT.distance(48.8566, 2.3522, 51.5074, -0.1278))
local brg = WT.bearing(48.8566, 2.3522, 51.5074, -0.1278); assert(brg > 320 and brg < 340, brg)
assert(WT.percentage(0) == 100 and WT.percentage(21000) == 0 and WT.percentage(2100) == 90)
local sh1 = WT.seededShuffle({ 1, 2, 3, 4, 5 }, "2026-11-22"); local sh2 = WT.seededShuffle({ 1, 2, 3, 4, 5 }, "2026-11-22")
assert(table.concat(sh1) == table.concat(sh2), "seeded shuffle is deterministic")
local CDN = "https://cdn-assets.teuteuf.fr/data/"
ROUTES[CDN .. "wheretaken-classic/games/" .. d:sub(1, 4) .. "/" .. d .. ".json"] = function()
    return { countryCode = "BA", photoCode = 8, landmarkData = { landmarkCode = 137, imageCode = 2 },
             cityData = { cityCode = 907, imageCode = 2 } }, 200 end
-- reference files are read from the cache; write them where the game expects
os.execute("mkdir -p /tmp/dgtest/cache")
local J = package.loaded["json"]
local function put(name, v) local f = io.open("/tmp/dgtest/cache/wheretaken-common_" .. name, "w"); f:write(J.encode(v)); f:close() end
put("countries.json", { { code = "BA", name = "Bosnia and Herzegovina", latitude = 43.9, longitude = 17.7 },
    { code = "HR", name = "Croatia", latitude = 45.1, longitude = 15.2 }, { code = "FR", name = "France", latitude = 46.2, longitude = 2.2 } })
put("landmarks.json", { { landmarkCode = 137, countryCode = "BA", names = { en = "Mostar Old Bridge" } },
    { landmarkCode = 1, countryCode = "FR", names = { en = "Eiffel Tower" } }, { landmarkCode = 2, countryCode = "HR", names = { en = "Dubrovnik Walls" } } })
put("cities.json", { { index = 1, countryCode = "BA", names = { en = "Sarajevo" }, capital = true },
    { index = 907, countryCode = "BA", names = { en = "Mostar" } }, { index = 3, countryCode = "BA", names = { en = "Tuzla" } },
    { index = 4, countryCode = "BA", names = { en = "Zenica" } } })
package.loaded["dailygames/http"].download = function() return nil end
package.loaded["libs/libkoreader-lfs"] = { attributes = function(path, what) if what == "modification" then return os.time() end if what == "mode" then return "directory" end end, dir = function() return function() end end }
plug:onDailyGamesWhereTaken(); app = top(); assert(app._name == "wheretaken_app", tostring(app._name))
app:onKey("C"); app:onKey("R"); assert(app:suggest()[1].code == "HR")
app:guess("HR"); local jj = app:judge("HR"); assert(not jj.correct and jj.km > 0 and jj.dir, "judge")
app:guess("BA"); assert(app:mainOver() and app.state.stars.main)
app:nextPhase(); assert(app.state.phase == "landmark", app.state.phase)
local q = app:bonusQuestion("landmark"); local right
for _, c in ipairs(q.choices) do if c.correct then right = c end end
assert(right.label == "Mostar Old Bridge" and #q.choices == 3)
app:answerBonus(right); assert(app.state.stars.landmark)
app:nextPhase(); assert(app.state.phase == "capital")
q = app:bonusQuestion("capital"); local wrong
for _, c in ipairs(q.choices) do if not c.correct then wrong = c end end
app:answerBonus(wrong); app:answerBonus(wrong); assert(not app.state.stars.capital and app.state.bonus.capital.tries == 2)
app:nextPhase(); assert(app.state.phase == "city")
app:nextPhase(); assert(app.state.phase == "done")
app:onClose()
-- FOODGUESSR MODES
local FM = require("dailygames/foodmodes")
local u = FM.url("cuisineMatch.today", 1795330000)
assert(u:find("cuisineMatch.today?batch=1&input=", 1, true) and u:find("1795305600000", 1, true), u)
local function food(name, country) return { name = name, ingredients = "x", countries = { { name = country } } } end
ROUTES[FM.url("cuisineMatch.today")] = function()
    return { { result = { data = { json = { date = d .. "T00:00:00.000Z", rounds = {
        { country = { name = "Zimbabwe" }, correctFoodIndex = 1, foods = { food("Bush Coconut", "Australia"), food("Boerewors", "Zimbabwe"), food("Cappon Magro", "Italy") } },
        { country = { name = "Japan" }, correctFoodIndex = 0, foods = { food("Natto", "Japan"), food("Tacos", "Mexico"), food("Pho", "Vietnam") } },
    } } } } } }, 200 end
plug:onDailyGamesCuisineMatch(); app = top(); assert(app._name == "cuisinematch_app", tostring(app._name))
app:pick(1); assert(app.status == "One more chance!" and not app:result(1).done)
app:pick(2); assert(app:result(1).points == 2000)
app:advance(); app:pick(1); assert(app:result(2).points == 5000 and app:score() == 7000)
app:advance(); assert(app:isOver()); app:onClose()
ROUTES[FM.url("plateOff.today")] = function()
    return { { result = { data = { json = { date = d .. "T00:00:00.000Z", rounds = {
        { leftFood = { name = "Bitterballen", yumCount = 2289, yuckCount = 279 }, rightFood = { name = "Lihapiirakka", yumCount = 2647, yuckCount = 473 } },
        { leftFood = { name = "A***", yumCount = 10, yuckCount = 10 }, rightFood = { name = "B", yumCount = 5, yuckCount = 5 } },
    } } } } } }, 200 end
plug:onDailyGamesPlateOff(); app = top(); assert(app._name == "plateoff_app")
assert(FM.plateOffCorrect(app.rounds[1], "left") and not FM.plateOffCorrect(app.rounds[1], "right"))
assert(FM.plateOffCorrect(app.rounds[2], "right"), "ties count as right")
app:pick("right"); assert(app.status:find("Nope")); app:advance(); app:pick("left"); app:advance()
assert(app:isOver() and app:score() == 1); app:onClose()
print("ALL NYT TESTS PASSED")
