package.path = PLUGDIR .. "/?.lua;" .. package.path
unpack = unpack or table.unpack
local realtime=os.time; CLOCK=1000000; os.time=function(t) if t then return realtime(t) end return CLOCK end
SHOWN, QUEUE, LOG = {}, {}, {}
local function class(name, base)
  local c = setmetatable({}, {__index = base}); c.__index = c; c._name = name
  function c:extend(o) o = o or {}; o.__index = o; o._name = o.name or name; return setmetatable(o, {__index = self}) end
  function c:new(o) o = o or {}; setmetatable(o, self); if o._init then o:_init() end; if o.init then o:init() end; return o end
  function c:free() for _, ch in ipairs(self) do if type(ch)=="table" and ch.free then ch:free() end end; self._freed=true end
  function c:getSize() return {w=100,h=40} end
  return c
end
local Widget = class("Widget")
local function W(name) return class(name, Widget) end
local UIManager = {}
function UIManager:show(w) table.insert(SHOWN, w); if w.onShow then w:onShow() end; table.insert(LOG, "show "..(w._name or "?")..": "..tostring(w.text or w.title or (w.getTitle and w:getTitle()))) end
function UIManager:close(w) for i,x in ipairs(SHOWN) do if x==w then table.remove(SHOWN,i) end end; if w.onCloseWidget then w:onCloseWidget() end end
function UIManager:forceRePaint() end
DIRTY = {}
function UIManager:setDirty(w, f) local t = type(f) == "function" and f() or f; table.insert(DIRTY, { w = w, type = t }) end
function UIManager:scheduleIn(t, f) table.insert(QUEUE, f) end
function UIManager:nextTick(f) table.insert(QUEUE, f) end
function UIManager:unschedule(f) for i=#QUEUE,1,-1 do if QUEUE[i]==f then table.remove(QUEUE,i) end end end
local InputDialog = W("InputDialog")
function InputDialog:init() self.title_bar = {setTitle=function(tb, t) table.insert(LOG, "title "..t) end} end
function InputDialog:getInputText() return self.input end
function InputDialog:setInputText(t) self.input = t end
function InputDialog:onShowKeyboard() end
local store = {}
local LS = {}; LS.__index = LS
function LS:open() return setmetatable({d=store}, LS) end
function LS:readSetting(k) return self.d[k] end
function LS:saveSetting(k,v) self.d[k]=v end
function LS:delSetting(k) self.d[k]=nil end
function LS:flush() FLUSHES=(FLUSHES or 0)+1 end
STORE = store
local Color = {COLOR_WHITE="W",COLOR_BLACK="B",COLOR_GRAY="G",COLOR_LIGHT_GRAY="LG",COLOR_DARK_GRAY="DG",COLOR_GRAY_5="G5",COLOR_GRAY_9="G9",COLOR_GRAY_B="GB",COLOR_GRAY_E="GE"}
local M = {
 ["ui/widget/confirmbox"]=W("ConfirmBox"), ["ui/widget/infomessage"]=W("InfoMessage"), ["ui/widget/inputdialog"]=InputDialog,
 ["ui/widget/textviewer"]=W("TextViewer"), ["ui/widget/container/widgetcontainer"]=W("WidgetContainer"),
 ["ui/widget/container/inputcontainer"]=W("InputContainer"), ["ui/widget/container/centercontainer"]=W("CenterContainer"),
 ["ui/widget/container/framecontainer"]=W("FrameContainer"), ["ui/widget/overlapgroup"]=W("OverlapGroup"),
 ["ui/widget/textboxwidget"]=W("TextBoxWidget"), ["ui/widget/textwidget"]=W("TextWidget"), ["ui/widget/titlebar"]=W("TitleBar"),
 ["ui/widget/verticalgroup"]=W("VerticalGroup"), ["ui/widget/horizontalgroup"]=W("HorizontalGroup"),
 ["ui/widget/verticalspan"]=W("VerticalSpan"), ["ui/widget/horizontalspan"]=W("HorizontalSpan"),
 ["ui/widget/buttontable"]=W("ButtonTable"), ["ui/widget/buttondialog"]=W("ButtonDialog"), ["ui/widget/menu"]=W("Menu"), ["ui/widget/imagewidget"]=W("ImageWidget"),
 ["ui/widget/notification"]={notify=function(_, t) table.insert(LOG, "notify "..t) end},
 ["ui/gesturerange"]=W("GestureRange"),
 ["ui/geometry"]={new=function(_, t) return t end}, ["ui/size"]={border={thin=1,default=2,thick=3}},
 ["ui/rendertext"]={sizeUtf8Text=function(_, x, w, face, text) local sz=(face and face[2]) or 10; return {x=#text*sz*0.6, y_top=sz*0.7, y_bottom=sz*0.2} end, renderUtf8Text=function() end},
 ["ui/font"]={getFace=function(_, n, s) return {n,s} end},
 ["ffi/blitbuffer"]=Color,
 ["datastorage"]={getSettingsDir=function() return "/x" end, getDataDir=function() return "/tmp/dgtest" end},
 ["device"]={screen={getWidth=function() return 1072 end,getHeight=function() return 1448 end,scaleBySize=function(_,x) return x end, getDPI=function() return 300 end},
   hasKeys=function() return false end, input={setClipboardText=function(t) table.insert(LOG,"clip "..t) end}},
 ["dispatcher"]={registerAction=function(_, id, t) ACTIONS=ACTIONS or {}; ACTIONS[id]=t end},
 ["luasettings"]=LS, ["ui/network/manager"]={runWhenOnline=function(_, f) f() end}, ["ui/uimanager"]=UIManager,
 ["logger"]={warn=print}, ["gettext"]=function(s) return s end,
}
for k,v in pairs(M) do package.loaded[k]=v end
package.loaded["json"] = dofile(PLUGDIR .. "/tests/vendor/json.lua")
-- fake HTTP: route by url
ROUTES = {}
package.loaded["dailygames/http"] = {
  request=function(o) local f = ROUTES[o.url]; if not f then return nil, nil, "no route "..o.url end; return f(o) end,
  getJson=function(url, h) local f = ROUTES[url]; if not f then return nil, "no route" end; local d, c = f({url=url, headers=h}); if c ~= 200 then return nil, "HTTP "..tostring(c) end; return d end,
}
function top() return SHOWN[#SHOWN] end
function runq(n) for i=1,(n or 1) do local q=QUEUE; QUEUE={}; for _,f in ipairs(q) do f() end end end
-- find buttons by text in widget tree
function findButtons(w, out)
  out = out or {}
  if type(w) ~= "table" then return out end
  if w.buttons then for _, row in ipairs(w.buttons) do for _, b in ipairs(row) do table.insert(out, b) end end end
  for _, ch in ipairs(w) do findButtons(ch, out) end
  return out
end
function press(app, text)
  for _, b in ipairs(findButtons(app)) do if b.text == text then assert(b.enabled ~= false, "disabled: "..text); b.callback(); return end end
  error("no button "..text)
end
function findAll(w, name, out)
  out = out or {}; if type(w)~="table" then return out end
  if w._name == name then table.insert(out, w) end
  for _, ch in ipairs(w) do findAll(ch, name, out) end; return out
end
