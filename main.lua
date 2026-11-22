--[[
Daily Games for KOReader: NYT Wordle, Connections, Strands, Mini and Daily
Crossword, plus Krillion.

Entry points:
  * Main menu: Tools > Daily Games
  * Dispatcher actions (gestures): "Daily Games hub" and one per game
  * ZenOS App Launcher: an entry is added on first start (see dailygames/zenos.lua).
    The launcher calls DailyGames:open().

Each game lives in dailygames/<game>.lua and exposes launch(...).
]]

local ButtonDialog = require("ui/widget/buttondialog")
local Dispatcher = require("dispatcher")
local InputDialog = require("ui/widget/inputdialog")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

-- Plugin-local modules must be required at load time (KOReader only adds the
-- plugin folder to package.path while loading main.lua).
local Connections = require("dailygames/connections")
local Costcodle = require("dailygames/costcodle")
local Crossword = require("dailygames/crossword")
local Krillion = require("dailygames/krillion")
local Store = require("dailygames/store")
local Strands = require("dailygames/strands")
local UI = require("dailygames/ui")
local Wordle = require("dailygames/wordle")
local ZenOS = require("dailygames/zenos")

local function today()
    return os.date("%Y-%m-%d")
end

local function nytCookie()
    return Store.get("nyt_s_cookie", "")
end

-- id is used for Dispatcher action names; event is the handler name suffix.
local GAMES = {
    { id = "wordle", event = "Wordle", text = _("Wordle"), launch = function() Wordle.launch(today()) end },
    { id = "connections", event = "Connections", text = _("Connections"),
      launch = function() Connections.launch(today()) end },
    { id = "strands", event = "Strands", text = _("Strands"), launch = function() Strands.launch(today()) end },
    { id = "mini", event = "Mini", text = _("The Mini Crossword"),
      launch = function() Crossword.launch("mini", nytCookie()) end },
    { id = "crossword", event = "Crossword", text = _("Daily Crossword"),
      launch = function() Crossword.launch("daily", nytCookie()) end },
    { id = "atlantic", event = "Atlantic", text = _("The Atlantic Crossword"),
      launch = function() Crossword.launch("atlantic") end },
    { id = "costcodle", event = "Costcodle", text = _("Costcodle"), launch = function() Costcodle.launch(today()) end },
    -- Krillion stays last (it has its own submenu).
    { id = "krillion", event = "Krillion", text = _("Krillion"), launch = function() Krillion.play() end },
}

local KRILLION = GAMES[#GAMES]

local DailyGames = WidgetContainer:extend {
    name = "dailygames",
    is_doc_only = false,
}

function DailyGames:init()
    math.randomseed(os.time() + math.floor((os.clock() * 1e6) % 1e6))
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    -- Wait a tick so ZenOS (which may load after us) is initialized.
    UIManager:nextTick(function() self:addToZenOSLauncher() end)
end

--- Adds "Daily Games" to the ZenOS App Launcher once. If the user removes it
-- later it stays removed. Retried on later starts until ZenOS is found.
function DailyGames:addToZenOSLauncher()
    ZenOS.repairLauncherEntries(self.name, self, "open", _("Daily Games"), "quick_puzzle")
    if Store.get("zenos_launcher_added") then return end
    local result = ZenOS.addLauncherEntry {
        key = self.name,
        method = "open",
        label = _("Daily Games"),
        icon = "quick_puzzle",
    }
    if result then
        Store.set("zenos_launcher_added", true)
    end
end

--- Entry point for the ZenOS App Launcher (and anything else that opens plugins).
function DailyGames:open()
    self:showHub()
end

-- Alias kept for launcher entries saved by v1.0.0, which used "launch".
DailyGames.launch = DailyGames.open

function DailyGames:onDispatcherRegisterActions()
    Dispatcher:registerAction("dailygames_hub", {
        category = "none",
        event = "DailyGamesHub",
        title = _("Daily Games hub"),
        general = true,
    })
    for __, game in ipairs(GAMES) do
        Dispatcher:registerAction("dailygames_" .. game.id, {
            category = "none",
            event = "DailyGames" .. game.event,
            title = _("Daily Games: ") .. game.text,
            general = true,
        })
    end
end

--- Starts a game once Wi-Fi is up. (Not named "launch": ZenOS treats
-- launch/open/show methods as the plugin's entry point.)
function DailyGames:launchGame(game)
    NetworkMgr:runWhenOnline(game.launch)
end

function DailyGames:onDailyGamesHub()
    self:showHub()
    return true
end

for __, game in ipairs(GAMES) do
    DailyGames["onDailyGames" .. game.event] = function(self)
        self:launchGame(game)
        return true
    end
end

function DailyGames:showHub()
    local dialog
    local buttons = {}
    for __, game in ipairs(GAMES) do
        table.insert(buttons, { {
            text = game.text,
            callback = function()
                UIManager:close(dialog)
                self:launchGame(game)
            end,
        } })
    end
    table.insert(buttons, { { text = _("Close"), callback = function() UIManager:close(dialog) end } })
    dialog = ButtonDialog:new { title = _("Daily Games") .. " · " .. today(), buttons = buttons }
    UIManager:show(dialog)
end

function DailyGames:editNytCookie()
    local dialog
    dialog = InputDialog:new {
        title = _("NYT-S cookie"),
        description = _("Needed only for the Daily Crossword (NYT subscription). Copy the value of the NYT-S cookie from a browser where you're logged in to nytimes.com."),
        input = nytCookie(),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Clear"), callback = function()
                Store.set("nyt_s_cookie", nil)
                UIManager:close(dialog)
            end },
            { text = _("Save"), is_enter_default = true, callback = function()
                Store.set("nyt_s_cookie", (dialog:getInputText():gsub("%s", "")))
                UIManager:close(dialog)
                UI.notify(_("Saved."), 1)
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function DailyGames:addToMainMenu(menu_items)
    local games_menu = {
        { text = _("Open hub"), callback = function() self:showHub() end, separator = true },
    }
    for __, game in ipairs(GAMES) do
        if game ~= KRILLION then
            table.insert(games_menu, { text = game.text, callback = function() self:launchGame(game) end })
        end
    end

    table.insert(games_menu, {
        text = _("Krillion"),
        separator = true,
        sub_item_table = {
            { text = _("Play today's dive"), callback = function() self:launchGame(KRILLION) end },
            { text = _("Statistics"), keep_menu_open = true, callback = Krillion.showStats },
            { text = _("Last result / share text"), keep_menu_open = true, callback = Krillion.showLastResult },
            {
                text = _("Timed rounds (25 s)"),
                help_text = _("When off, rounds have no time limit. The official game uses 25 seconds."),
                checked_func = Krillion.timedRounds,
                callback = function() Krillion.setTimedRounds(not Krillion.timedRounds()) end,
            },
            { text = _("How to play"), keep_menu_open = true, callback = Krillion.showHelp },
            { text = _("Reset today's dive"), keep_menu_open = true, callback = Krillion.resetToday },
        },
    })

    table.insert(games_menu, {
        text = _("NYT-S cookie (Daily Crossword)"),
        keep_menu_open = true,
        callback = function() self:editNytCookie() end,
    })

    menu_items.daily_games = {
        text = _("Daily Games"),
        sorting_hint = "tools",
        sub_item_table = games_menu,
    }
end

return DailyGames
