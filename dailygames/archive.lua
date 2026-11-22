--[[
Endless play from a game's archive of past days: pick a random earlier date
(or resume the unfinished one) and hand it to the game's launcher. Progress
is kept under "<key>_endless", away from today's puzzle.
]]

local Store = require("dailygames/store")

local Archive = {}

local function noon(date)
    local y, m, d = date:match("^(%d+)-(%d+)-(%d+)$")
    return os.time { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
end

--- A random date from `first` up to the day before `today` (both "YYYY-MM-DD").
function Archive.randomDate(first, today)
    local t0 = noon(first)
    local days = math.floor((noon(today) - t0) / 86400 + 0.5)
    return os.date("%Y-%m-%d", t0 + math.random(0, math.max(0, days - 1)) * 86400)
end

--- Plays a random past day. launch(date, opts) shows the game, where
-- opts = { state = saved state or nil, on_next = function }.
function Archive.play(key, first, today, launch)
    local slot = key .. "_endless"
    local saved = Store.get("progress/" .. slot)
    local date, state
    if type(saved) == "table" and type(saved.state) == "table" and not saved.state.done then
        date, state = saved.date, saved.state
    else
        math.randomseed(os.time())
        date = Archive.randomDate(first, today)
    end
    launch(date, {
        state = state,
        on_next = function()
            Store.clearProgress(slot)
            Archive.play(key, first, today, launch)
        end,
    })
end

return Archive
