--[[
Persistent settings and per-day game progress, stored in
koreader/settings/dailygames.lua.
]]

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local Store = {}

local settings

local function open()
    if not settings then
        settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/dailygames.lua")
    end
    return settings
end

function Store.get(key, default)
    local value = open():readSetting(key)
    if value == nil then
        return default
    end
    return value
end

--- Saves a value. Pass defer = true to skip writing to disk (call Store.flush later).
function Store.set(key, value, defer)
    if value == nil then
        open():delSetting(key)
    else
        open():saveSetting(key, value)
    end
    if not defer then
        open():flush()
    end
end

function Store.flush()
    open():flush()
end

--- Returns saved state for `game` if it belongs to `date`, else nil.
function Store.loadProgress(game, date)
    local entry = Store.get("progress/" .. game)
    if type(entry) == "table" and entry.date == date then
        return entry.state
    end
end

function Store.clearProgress(game)
    Store.set("progress/" .. game, nil)
end

function Store.saveProgress(game, date, state, defer)
    Store.set("progress/" .. game, { date = date, state = state }, defer)
end

return Store
