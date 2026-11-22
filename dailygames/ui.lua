--[[
Shared UI building blocks:

  UI.FullscreenApp  base class for full-screen games (title bar, close, rebuild/refresh)
  UI.tile           fixed-size letter square (borders never change its size)
  UI.text / banner  wrapped text and shaded text boxes
  UI.notify / error / withBusy  message helpers
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
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

-- messages -------------------------------------------------------------------

function UI.notify(text, timeout)
    UIManager:show(InfoMessage:new { text = text, timeout = timeout or 1.5 })
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

-- widgets --------------------------------------------------------------------

function UI.span(px)
    return VerticalSpan:new { width = Screen:scaleBySize(px or 4) }
end

function UI.hspan(px)
    return HorizontalSpan:new { width = Screen:scaleBySize(px or 4) }
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
        fgcolor = opts.fg or Blitbuffer.COLOR_BLACK,
        bgcolor = opts.bg or Blitbuffer.COLOR_WHITE,
    }
end

--- Shaded box with one or more lines of wrapped text.
-- lines: list of { text, bold?, face? }
function UI.banner(lines, width, opts)
    opts = opts or {}
    local bg = opts.bg or Blitbuffer.COLOR_LIGHT_GRAY
    local fg = opts.fg or Blitbuffer.COLOR_BLACK
    local padding = Screen:scaleBySize(6)
    local border = opts.border or Size.border.default
    local inner_w = width - 2 * (padding + border)
    local group = VerticalGroup:new { align = "center" }
    for _, line in ipairs(lines) do
        table.insert(group, UI.text(line.text, inner_w, {
            face = line.face, bold = line.bold, fg = fg, bg = bg,
        }))
    end
    return FrameContainer:new {
        background = bg,
        bordersize = border,
        padding = padding,
        margin = 0,
        group,
    }
end

--- Fixed-size letter tile. Total size is always `size` x `size`.
-- o: size, text, bg, fg, border, border_color, label (small corner text), bold
function UI.tile(o)
    local size = o.size
    local border = o.border or Size.border.thin
    local inner = size - 2 * border
    local letter = CenterContainer:new {
        dimen = Geom:new { w = inner, h = inner },
        TextWidget:new {
            text = (o.text == nil or o.text == "") and " " or o.text,
            fgcolor = o.fg or Blitbuffer.COLOR_BLACK,
            bold = o.bold,
            face = Font:getFace("cfont", math.max(8, math.floor(inner * (o.font_ratio or 0.5)))),
        },
    }
    local content = letter
    if o.label then
        content = OverlapGroup:new {
            dimen = Geom:new { w = inner, h = inner },
            letter,
            TextWidget:new {
                text = o.label,
                fgcolor = o.label_fg or o.fg or Blitbuffer.COLOR_BLACK,
                face = Font:getFace("cfont", math.max(7, math.floor(inner * 0.26))),
                overlap_offset = { Screen:scaleBySize(1), 0 },
            },
        }
    end
    return FrameContainer:new {
        background = o.bg or Blitbuffer.COLOR_WHITE,
        bordersize = border,
        color = o.border_color or Blitbuffer.COLOR_DARK_GRAY,
        margin = 0,
        padding = 0,
        content,
    }
end

-- full-screen app base -------------------------------------------------------

local FullscreenApp = InputContainer:extend {
    covers_fullscreen = true,
    title = "",
}

function FullscreenApp:init()
    self.dimen = Geom:new { x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    if self.setup then
        self:setup()
    end
    self:rebuild()
end

--- Override: return the widget shown under the title bar.
function FullscreenApp:buildBody(width, height) -- luacheck: ignore
    return UI.text("", width)
end

function FullscreenApp:getTitle()
    return self.title
end

function FullscreenApp:rebuild()
    if self[1] then
        self[1]:free()
    end
    local sw, sh = self.dimen.w, self.dimen.h
    local title_bar = TitleBar:new {
        width = sw,
        fullscreen = true,
        align = "center",
        title = self:getTitle(),
        with_bottom_line = true,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
    local body_h = sh - title_bar:getSize().h
    self[1] = FrameContainer:new {
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        VerticalGroup:new {
            align = "center",
            title_bar,
            CenterContainer:new {
                dimen = Geom:new { w = sw, h = body_h },
                self:buildBody(sw, body_h),
            },
        },
    }
end

function FullscreenApp:refresh()
    self:rebuild()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function FullscreenApp:onClose()
    if self.onExit then
        self:onExit()
    end
    UIManager:close(self, "flashui")
    return true
end

UI.FullscreenApp = FullscreenApp

return UI
