--[[
Shared UI for the full-screen games, designed for black-and-white e-ink.

  UI.FullscreenApp  base screen: title bar (menu + close), top content,
                    inline status line, controls pinned to the bottom.
                    Paints a white background and does a full refresh on close.
  UI.Board          base for custom-drawn boards (grids, cards, keyboards):
                    one tap area, tap -> local coordinates.
  UI.Keyboard       drawn on-screen keyboard with per-key black/gray/white states.
  UI.draw*          drawing helpers (centered text, lines, circles, corner marks).
  UI.fitFace        largest font size whose text fits a box.

Visual language used by every game:
  black fill + white text  = selected / correct / active
  gray fill                = partly right / found / current word
  white + faded text       = ruled out
  thick black border       = where your input goes
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local RenderText = require("ui/rendertext")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")

local Screen = Device.screen

local UI = {
    Screen = Screen,
    Color = Blitbuffer,
}

-- Shades used across games (darkest to lightest).
UI.BLACK = Blitbuffer.COLOR_BLACK
UI.DARK = Blitbuffer.COLOR_GRAY_5
UI.MID = Blitbuffer.COLOR_GRAY_9
UI.LIGHT = Blitbuffer.COLOR_GRAY_B
UI.PALE = Blitbuffer.COLOR_GRAY_E
UI.WHITE = Blitbuffer.COLOR_WHITE

function UI.px(n)
    return Screen:scaleBySize(n)
end

-- messages -------------------------------------------------------------------

function UI.notify(text, timeout)
    UIManager:show(InfoMessage:new { text = text, timeout = timeout or 1.5 })
end

--- Copies text to the clipboard (where supported) and confirms.
function UI.copy(text)
    if Device.input and Device.input.setClipboardText then
        Device.input.setClipboardText(text)
        UI.notify("Copied to clipboard.", 1.5)
    else
        UI.notify(text, 10)
    end
end

function UI.error(text)
    UIManager:show(InfoMessage:new { text = text })
end

--- Shows `text` while running fn() (blocking network calls); returns fn's results.
function UI.withBusy(text, fn)
    local msg = InfoMessage:new { text = text, dismissable = false }
    UIManager:show(msg)
    UIManager:forceRePaint()
    local ok, a, b, c = pcall(fn)
    UIManager:close(msg)
    if not ok then
        logger.warn("DailyGames:", a)
        return nil, nil, tostring(a)
    end
    return a, b, c
end

-- text -----------------------------------------------------------------------

local face_cache = {}

-- Bold is synthesized by RenderText (the `bold` flag), so one face per size.
local function face(size)
    if not face_cache[size] then
        face_cache[size] = Font:getFace("cfont", size)
    end
    return face_cache[size]
end

local function measure(f, text, bold)
    local m = RenderText:sizeUtf8Text(0, Screen:getWidth() * 4, f, text, true, bold)
    return m.x, m.y_top + m.y_bottom, m
end

--- Largest face such that every string in `samples` fits w x h.
-- opts: bold, min, caps (single capitals: only cap height must fit, so the
-- face can be much larger than the box height suggests).
-- Results are cached: boards rebuild on every tap.
local fit_cache = {}
function UI.fitFace(samples, w, h, opts)
    opts = opts or {}
    w, h = math.floor(w), math.floor(h)
    local key = table.concat(samples, "\1") .. "|" .. w .. "|" .. h .. "|"
        .. tostring(opts.bold) .. tostring(opts.caps) .. tostring(opts.min)
    if fit_cache[key] then return fit_cache[key] end
    local bold = opts.bold
    local scale = math.max(0.5, Screen:scaleBySize(100) / 100)
    local size = math.max(6, math.floor(h / scale * (opts.caps and 1.8 or 1.1)))
    local min = opts.min or 6
    local found
    while size > min do
        local f = face(size)
        local ok = true
        for _, s in ipairs(samples) do
            local tw, th, m = measure(f, s, bold)
            if opts.caps then th = m.y_top * 0.75 end
            if tw > w or th > h then ok = false; break end
        end
        if ok then found = f; break end
        size = size - 1
    end
    found = found or face(min)
    fit_cache[key] = found
    return found
end

UI.measure = measure

--- Draws text centered in the box (x, y, w, h).
function UI.drawText(bb, f, text, x, y, w, h, color, bold)
    if not text or text == "" then return end
    local tw, _, m = measure(f, text, bold)
    local tx = x + math.floor((w - tw) / 2)
    local baseline = y + math.floor((h + m.y_top - m.y_bottom) / 2)
    RenderText:renderUtf8Text(bb, tx, baseline, f, text, true, bold, color or UI.BLACK)
end

--- Draws text left-aligned at x, vertically centered in (y, h).
function UI.drawTextLeft(bb, f, text, x, y, h, color, bold)
    if not text or text == "" then return end
    local _, _, m = measure(f, text, bold)
    local baseline = y + math.floor((h + m.y_top - m.y_bottom) / 2)
    RenderText:renderUtf8Text(bb, x, baseline, f, text, true, bold, color or UI.BLACK)
end

--- Splits text into at most two balanced lines for width w (no split if it fits).
function UI.wrap2(f, text, w, bold)
    if (measure(f, text, bold)) <= w then return { text } end
    local best
    for i = 1, #text do
        local ch = text:sub(i, i)
        if ch == " " or ch == "-" or ch == "/" then
            local a = text:sub(1, i):gsub("%s+$", "")
            local b = text:sub(i + 1):gsub("^%s+", "")
            -- parentheses keep only the width (measure returns w, h, metrics)
            local worst = math.max((measure(f, a, bold)), (measure(f, b, bold)))
            if not best or worst < best.worst then best = { a, b, worst = worst } end
        end
    end
    if best then return { best[1], best[2] } end
    return { text }
end

--- Greedy word wrap of `text` into lines no wider than w (words longer than
-- w are kept whole; callers shrink the font until they fit).
local function wrapLines(f, text, w, bold)
    local lines, line = {}, ""
    for word in tostring(text):gmatch("%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if line ~= "" and (measure(f, try, bold)) > w then
            table.insert(lines, line)
            line = word
        else
            line = try
        end
    end
    if line ~= "" then table.insert(lines, line) end
    return lines
end

--- Largest face (and the wrapped lines) so `text` fits w x h in at most
-- max_lines lines. Long text may end up small; the last resort cuts it with "…".
local lines_cache = {}
function UI.fitLines(text, w, h, max_lines, opts)
    opts = opts or {}
    w, h = math.floor(w), math.floor(h)
    local key = tostring(text) .. "|" .. w .. "|" .. h .. "|" .. max_lines .. tostring(opts.bold)
    if lines_cache[key] then return lines_cache[key][1], lines_cache[key][2] end
    local scale = math.max(0.5, Screen:scaleBySize(100) / 100)
    local size = math.max(6, math.floor(h / max_lines / scale * 0.95))
    local min = opts.min or 7
    local f, lines
    while size >= min do
        f = face(size)
        lines = wrapLines(f, text, w, opts.bold)
        local ok = #lines <= max_lines
        if ok then
            for _, l in ipairs(lines) do
                local lw, lh = measure(f, l, opts.bold)
                if lw > w or lh * #lines > h then ok = false break end
            end
        end
        if ok then break end
        size = size - 1
    end
    -- still too long at the minimum size: keep max_lines lines, end with an ellipsis
    if #lines > max_lines then
        local kept = {}
        for i = 1, max_lines do kept[i] = lines[i] end
        kept[max_lines] = kept[max_lines] .. "…"
        lines = kept
    end
    lines_cache[key] = { f, lines }
    return f, lines
end

-- shapes ---------------------------------------------------------------------

function UI.drawBorder(bb, x, y, w, h, t, color)
    bb:paintRect(x, y, w, t, color)
    bb:paintRect(x, y + h - t, w, t, color)
    bb:paintRect(x, y, t, h, color)
    bb:paintRect(x + w - t, y, t, h, color)
end

--- Thick line between two points (stamped squares; fine for short board lines).
function UI.drawLine(bb, x1, y1, x2, y2, t, color)
    local dx, dy = x2 - x1, y2 - y1
    local steps = math.max(math.abs(dx), math.abs(dy), 1)
    local half = math.floor(t / 2)
    local stride = math.max(1, math.floor(t / 3))
    for i = 0, steps, stride do
        bb:paintRect(math.floor(x1 + dx * i / steps) - half, math.floor(y1 + dy * i / steps) - half, t, t, color)
    end
    bb:paintRect(x2 - half, y2 - half, t, t, color)
end

function UI.fillCircle(bb, cx, cy, r, color)
    for dy = -r, r do
        local half = math.floor(math.sqrt(r * r - dy * dy))
        bb:paintRect(cx - half, cy + dy, 2 * half + 1, 1, color)
    end
end

function UI.ringCircle(bb, cx, cy, r, t, color)
    local inner = r - t
    for dy = -r, r do
        local outer_half = math.floor(math.sqrt(r * r - dy * dy))
        if math.abs(dy) > inner then
            bb:paintRect(cx - outer_half, cy + dy, 2 * outer_half + 1, 1, color)
        else
            local inner_half = math.floor(math.sqrt(inner * inner - dy * dy))
            bb:paintRect(cx - outer_half, cy + dy, outer_half - inner_half, 1, color)
            bb:paintRect(cx + inner_half + 1, cy + dy, outer_half - inner_half, 1, color)
        end
    end
end

--- Filled triangle in the top-right corner of a box (used for "wrong").
function UI.cornerMark(bb, x, y, w, size, color)
    for i = 0, size - 1 do
        bb:paintRect(x + w - (size - i), y + i, size - i, 1, color)
    end
end

-- widgets --------------------------------------------------------------------

function UI.span(px)
    return VerticalSpan:new { width = Screen:scaleBySize(px or 4) }
end

--- Wrapped, centered text.
function UI.text(text, width, opts)
    opts = opts or {}
    return TextBoxWidget:new {
        text = text,
        width = width,
        face = Font:getFace(opts.face or "smallinfofont", opts.size),
        bold = opts.bold,
        alignment = opts.alignment or "center",
        fgcolor = opts.fg or UI.BLACK,
        bgcolor = opts.bg or UI.WHITE,
    }
end

--- A photo scaled to fit max_w x max_h, keeping its shape. The widget is
-- exactly the picture's size (centred horizontally): KOReader's night mode
-- re-inverts an image widget's whole box, so any padding inside the box would
-- show up as bright bars.
function UI.photo(path, max_w, max_h)
    max_w, max_h = math.floor(max_w), math.floor(max_h)
    if not path then return UI.text("(photo unavailable)", max_w) end
    -- measure the fitted size with a throwaway widget (it computes its own
    -- centring offsets on render, so it can't simply be shrunk afterwards)
    local probe = ImageWidget:new { file = path, width = max_w, height = max_h, scale_factor = 0 }
    probe:getSize()
    local bw, bh = max_w, max_h
    if probe._bb then bw, bh = probe._bb:getWidth(), probe._bb:getHeight() end
    probe:free()
    local img = ImageWidget:new { file = path, width = bw, height = bh, scale_factor = 0 }
    return CenterContainer:new { dimen = Geom:new { w = max_w, h = bh }, img }
end

-- Board: custom-drawn widget with one tap area ---------------------------------

local Board = InputContainer:extend {
    width = nil,
    height = nil,
}

function Board:init()
    self.width, self.height = math.floor(self.width), math.floor(self.height)
    self.dimen = Geom:new { x = 0, y = 0, w = self.width, h = self.height }
    self.paint_rect = Geom:new { x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        Tap = { GestureRange:new { ges = "tap", range = function() return self.paint_rect end } },
    }
    if self.setup then self:setup() end
end

function Board:getSize()
    return Geom:new { w = self.width, h = self.height }
end

function Board:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    self.paint_rect = Geom:new { x = x, y = y, w = self.width, h = self.height }
    bb:paintRect(x, y, self.width, self.height, UI.WHITE)
    self:draw(bb, x, y)
end

function Board:draw(bb, x, y) end -- luacheck: ignore

function Board:onTap(_, ges)
    if not (ges and ges.pos) then return false end
    local lx, ly = ges.pos.x - self.paint_rect.x, ges.pos.y - self.paint_rect.y
    if lx < 0 or ly < 0 or lx >= self.width or ly >= self.height then return false end
    if self.tapAt then self:tapAt(lx, ly) end
    return true
end

UI.Board = Board

-- Keyboard: drawn keys with states ---------------------------------------------

--[[
rows: list of lists of keys. A key is a string (label == value) or
{ label = "⌫", value = "DEL", width = 1.5 }.
state_func(value) -> "correct" | "present" | "absent" | nil (Wordle-style shading).
on_key(value)
]]
local Keyboard = Board:extend {
    rows = nil,
    state_func = nil,
    on_key = nil,
    enabled = true,
}

function Keyboard:setup()
    self.gap = UI.px(4)
    self.row_h = math.floor((self.height - self.gap * (#self.rows - 1)) / #self.rows)
    local function units(row)
        local u = 0
        for _, k in ipairs(row) do u = u + (type(k) == "table" and k.width or 1) end
        return u
    end
    -- min_units keeps letter keys the same width on every keyboard; a keypad
    -- with few keys per row sets it lower so its keys can be wider.
    local max_units = self.min_units or 10
    for _, row in ipairs(self.rows) do max_units = math.max(max_units, units(row)) end
    local unit = (self.width - self.gap * (max_units - 1)) / max_units
    self.keys = {}
    for r, row in ipairs(self.rows) do
        local row_w = units(row) * unit + (#row - 1) * self.gap
        local x = (self.width - row_w) / 2
        local y = (r - 1) * (self.row_h + self.gap)
        for _, k in ipairs(row) do
            local spec = type(k) == "table" and k or { label = k, value = k }
            local w = (spec.width or 1) * unit
            table.insert(self.keys, {
                x = math.floor(x), y = y, w = math.floor(w), h = self.row_h,
                label = spec.label, value = spec.value or spec.label,
            })
            x = x + w + self.gap
        end
    end
    self.face = UI.fitFace({ "W", "M", "Q" }, unit * 0.65, self.row_h * 0.45, { bold = true, caps = true })
    local long = {}
    for _, k in ipairs(self.keys) do
        if #k.label > 1 then table.insert(long, k) end
    end
    self.small_faces = {}
    for _, k in ipairs(long) do
        self.small_faces[k] = UI.fitFace({ k.label }, k.w * 0.85, self.row_h * 0.42, { bold = true })
    end
end

local KEY_STYLE = {
    correct = { bg = UI.BLACK, fg = UI.WHITE, border = UI.BLACK },
    present = { bg = UI.MID, fg = UI.BLACK, border = UI.BLACK },
    absent = { bg = UI.WHITE, fg = UI.LIGHT, border = UI.LIGHT },
    normal = { bg = UI.WHITE, fg = UI.BLACK, border = UI.BLACK },
}

function Keyboard:draw(bb, x, y)
    local t = math.max(1, Size.border.thin)
    for _, k in ipairs(self.keys) do
        local state = self.state_func and self.state_func(k.value) or nil
        local st = KEY_STYLE[state or "normal"]
        if not self.enabled then st = KEY_STYLE.absent end
        bb:paintRect(x + k.x, y + k.y, k.w, k.h, st.bg)
        UI.drawBorder(bb, x + k.x, y + k.y, k.w, k.h, t, st.border)
        UI.drawText(bb, self.small_faces[k] or self.face, k.label, x + k.x, y + k.y, k.w, k.h, st.fg, true)
    end
end

function Keyboard:tapAt(lx, ly)
    if not self.enabled then return end
    local half = self.gap / 2 + 1
    for _, k in ipairs(self.keys) do
        if lx >= k.x - half and lx < k.x + k.w + half and ly >= k.y - half and ly < k.y + k.h + half then
            if self.on_key then self.on_key(k.value) end
            return
        end
    end
end

UI.Keyboard = Keyboard

UI.QWERTY = {
    { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
    { "A", "S", "D", "F", "G", "H", "J", "K", "L" },
}

-- Full-screen app base -------------------------------------------------------------

local FullscreenApp = InputContainer:extend {
    covers_fullscreen = true,
    title = "",
    help_text = nil, -- shown from the menu as "How to play"
}

function FullscreenApp:init()
    self.dimen = Geom:new { x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self.status = self.status or ""
    if self.setup then self:setup() end
    self:rebuild()
end

function FullscreenApp:getTitle()
    return self.title
end

--- Override: return top content and bottom controls (either may be nil).
-- `width`, `height` describe the space below the title bar.
function FullscreenApp:buildBody(width, height) -- luacheck: ignore
    return nil, nil
end

--- Override to add game-specific menu entries: list of { text = ..., callback = ... }.
function FullscreenApp:menuItems()
    return {}
end

function FullscreenApp:showMenu()
    local dialog
    local buttons = {}
    for _, item in ipairs(self:menuItems()) do
        table.insert(buttons, { {
            text = item.text,
            callback = function() UIManager:close(dialog); item.callback() end,
        } })
    end
    if self:progressKey() then
        table.insert(buttons, { {
            text = "Restart puzzle",
            callback = function()
                UIManager:close(dialog)
                UIManager:show(ConfirmBox:new {
                    text = "Restart today's puzzle? Your progress will be cleared.",
                    ok_text = "Restart",
                    ok_callback = function() self:restart() end,
                })
            end,
        } })
    end
    if self.help_text then
        table.insert(buttons, { {
            text = "How to play",
            callback = function()
                UIManager:close(dialog)
                UIManager:show(InfoMessage:new { text = self.help_text })
            end,
        } })
    end
    table.insert(buttons, { {
        text = "Close game",
        callback = function() UIManager:close(dialog); self:onClose() end,
    } })
    dialog = ButtonDialog:new { title = self:getTitle(), buttons = buttons }
    UIManager:show(dialog)
end

--- Override: true once today's puzzle is finished (won or lost). Saved as
-- state.done so the hub can show a tick without loading the game.
function FullscreenApp:isComplete()
    return self.isOver and self:isOver() or false
end

--- Records completion in the state and returns it (use when saving).
function FullscreenApp:markDone()
    self.state.done = self:isComplete() and true or nil
    return self.state
end

--- Override: the Store progress key for this game (enables "Restart puzzle").
function FullscreenApp:progressKey()
    return nil
end

--- Clears today's saved progress and starts the puzzle over.
function FullscreenApp:restart()
    local Store = require("dailygames/store")
    Store.clearProgress(self:progressKey())
    self.state = nil
    self.status = ""
    if self.setup then self:setup() end
    self:rebuild()
    UIManager:setDirty(self, function() return "full", self.dimen end)
end

--- Sets the message line under the board (instead of a popup) and redraws.
function FullscreenApp:setStatus(text)
    self.status = text or ""
    self:refresh()
end

--- Status line widget; reserve its space even when empty so the layout doesn't jump.
function FullscreenApp:statusLine(width)
    return UI.text(self.status ~= "" and self.status or " ", width, { bold = true, face = "infofont" })
end

function FullscreenApp:rebuild()
    if self[1] then self[1]:free() end
    local sw, sh = self.dimen.w, self.dimen.h
    local title_bar = TitleBar:new {
        width = sw,
        fullscreen = true,
        align = "center",
        title = self:getTitle(),
        with_bottom_line = true,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:showMenu() end,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
    local margin = UI.px(8)
    local body_h = sh - title_bar:getSize().h - 2 * margin
    local top, bottom = self:buildBody(sw, body_h)
    local group = VerticalGroup:new { align = "center", title_bar, VerticalSpan:new { width = margin } }
    local used = 0
    if top then
        table.insert(group, top)
        used = used + top:getSize().h
    end
    if bottom then
        table.insert(group, VerticalSpan:new { width = math.max(0, body_h - used - bottom:getSize().h) })
        table.insert(group, bottom)
    end
    self[1] = group
end

function FullscreenApp:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, UI.WHITE)
    if self[1] then self[1]:paintTo(bb, x, y) end
end

--- UIManager:show() only repaints into memory; ask the e-ink panel to refresh,
-- with a full flash so nothing of the previous screen (e.g. the ZenOS
-- launcher) is left behind.
function FullscreenApp:onShow()
    UIManager:setDirty(self, function() return "full", self.dimen end)
    return true
end

function FullscreenApp:refresh()
    self:rebuild()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function FullscreenApp:onClose()
    if self.closed then return true end
    self.closed = true
    if self.onExit then self:onExit() end
    UIManager:close(self)
    -- Repaint and flash everything underneath so no part of the board is left
    -- behind (seen on the ZenOS home screen).
    UIManager:setDirty("all", "full")
    return true
end

UI.FullscreenApp = FullscreenApp

return UI
