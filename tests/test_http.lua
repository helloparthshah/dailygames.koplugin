package.path = PLUGDIR .. "/?.lua;" .. package.path
for _, f in ipairs{"main","_meta","dailygames/http","dailygames/store","dailygames/ui","dailygames/nyt","dailygames/wordle","dailygames/connections","dailygames/strands","dailygames/crossword","dailygames/krillion"} do assert(loadfile(PLUGDIR.."/"..f..".lua")) end
local last
package.loaded["json"] = {encode=function(t) return "{json}" end, decode=function(s) return {ok=true} end}
package.loaded["ltn12"] = {sink={table=function(t) return function(c) if c then t[#t+1]=c end return 1 end end}, source={string=function(s) return s end}}
package.loaded["socket"] = {skip=function(n, ...) return select(n+1, ...) end}
local mode = "ok"
package.loaded["socket.http"] = {request=function(req) last=req; if mode=="down" then return nil, "host not found" end; req.sink('{"ok":1}'); return 1, mode=="404" and 404 or 200, {}, "x" end}
package.loaded["socketutil"] = {set_timeout=function() end, reset_timeout=function() end}
local Http = require("dailygames/http")
assert(Http.getJson("https://x/a").ok); assert(last.method=="GET")
local d, code = Http.request{url="https://x/b", method="POST", body={a=1}, headers={Cookie="NYT-S=1"}}
assert(code==200 and last.headers["Content-Type"]=="application/json" and last.headers.Cookie=="NYT-S=1" and last.headers["Content-Length"]=="6")
mode="404"; print(Http.getJson("https://x/a")); mode="down"; print(Http.getJson("https://x/a"))
print("HTTP PASSED")
