--[[
Krillion daily dive (krillion.io): seven prompts, 25 seconds each, rarer
answers score more. Answers are checked and scored by krillion.io using the
same API as the web game:

  GET  /api/today           -> { date, dayNumber, resetsAt, prompts = { {id, text}, ... } }
  POST /api/submit          { date, promptId, answer, previewCorrection, playerId, runId }
                            -> { accepted, tier, score, answer, quip, receipt, correction, rejectionReason }
  POST /api/today/complete  { date, playerId, score, record, runId, receipts } -> { betterThan, ... }

The game runs as a sequence of dialogs (prompt preview, answer box with a
countdown, result), so it works well with the on-screen keyboard.
]]

local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")

local Http = require("dailygames/http")
local Store = require("dailygames/store")
local UI = require("dailygames/ui")

local BASE_URL = "https://krillion.io"
local ROUNDS = 7
local ANSWER_SECS = 25
local PREVIEW_SECS = 3
local MAX_ANSWER_LENGTH = 256

local TIERS = {
    plankton = { name = "Plankton", score = 10, emoji = "🫧" },
    tooclever = { name = "Too Clever", score = 15, emoji = "🤡" },
    schooler = { name = "Schooler", score = 30, emoji = "🐟" },
    rare = { name = "Rare", score = 60, emoji = "🦑" },
    deepcut = { name = "Deep Cut", score = 85, emoji = "🏮" },
    krillion = { name = "One in a Krillion", score = 100, emoji = "🌟" },
}
local MISS_EMOJI = "⬛"

local SCORE_BANDS = {
    { min = 450, text = "One in a krillion. Trench dweller. Absurd." },
    { min = 351, text = "Deep cut. Seriously deep dive." },
    { min = 251, text = "Rare. Below the thermocline. Nice." },
    { min = 151, text = "Schooler. Swimming with the school." },
    { min = 0, text = "Plankton. Plenty of ocean left down there." },
}

-- helpers --------------------------------------------------------------------

local function trim(s)
    return ((s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function uuid4()
    local b = {}
    for i = 1, 16 do b[i] = math.random(0, 255) end
    b[7] = (b[7] % 16) + 64
    b[9] = (b[9] % 64) + 128
    return string.format("%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x", unpack(b))
end

local function dateToTime(d)
    local y, m, day = (d or ""):match("^(%d+)-(%d+)-(%d+)$")
    if not y then return nil end
    return os.time { year = tonumber(y), month = tonumber(m), day = tonumber(day), hour = 12 }
end

local function sumScore(results)
    local s = 0
    for _, r in ipairs(results) do s = s + (r.score or 0) end
    return s
end

local function bandFor(score)
    for _, b in ipairs(SCORE_BANDS) do
        if score >= b.min then return b.text end
    end
end

local function tierLabel(r)
    if r.tier == "miss" then return "Miss" end
    return TIERS[r.tier] and TIERS[r.tier].name or tostring(r.tier)
end

local function toast(text)
    local ok, Notification = pcall(require, "ui/widget/notification")
    if ok and Notification and Notification.notify then
        Notification:notify(text)
    else
        UI.notify(text, 2)
    end
end

-- api ------------------------------------------------------------------------

local Api = {}

function Api.today()
    local data, code, err = Http.request { url = BASE_URL .. "/api/today" }
    if not code then return nil, err end
    if code ~= 200 or not data or type(data.prompts) ~= "table" then
        return nil, (data and data.error) or ("HTTP " .. tostring(code))
    end
    return data
end

function Api.submit(p)
    return Http.request {
        url = BASE_URL .. "/api/submit",
        method = "POST",
        timeout = 8,
        body = {
            date = p.date, promptId = p.promptId, answer = p.answer,
            previewCorrection = p.previewCorrection and true or false,
            playerId = p.playerId, runId = p.runId,
        },
    }
end

--- How many divers gave each answer today (only today's is public).
-- Returns { [promptId] = { [answer] = count } } or nil.
function Api.popularity(date)
    local data, code = Http.request { url = BASE_URL .. "/api/answer-popularity?date=" .. date, timeout = 20 }
    if code == 200 and type(data) == "table" and data.date == date and type(data.prompts) == "table" then
        return data.prompts
    end
end

function Api.complete(p)
    local body = { date = p.date, playerId = p.playerId, score = p.score, record = p.record and true or false }
    if p.record then
        body.runId = p.runId
        body.receipts = p.receipts
    end
    return Http.request { url = BASE_URL .. "/api/today/complete", method = "POST", body = body }
end

-- game -----------------------------------------------------------------------

local Krillion = {}

function Krillion.timedRounds()
    return Store.get("krillion/timed", true)
end

function Krillion.setTimedRounds(on)
    Store.set("krillion/timed", on)
end

function Krillion.playerId()
    local id = Store.get("krillion/player_id")
    if not id then
        id = uuid4()
        Store.set("krillion/player_id", id)
    end
    return id
end

function Krillion.history()
    return Store.get("krillion/history", {})
end

local Game = {}
Game.__index = Game

function Krillion.play()
    local today, err = UI.withBusy("Diving to krillion.io…", Api.today)
    if not today then
        UI.error("Couldn't load today's Krillion.\n" .. tostring(err))
        return
    end
    local self = setmetatable({ today = today }, Game)
    self:start()
end

function Game:save()
    Store.set("krillion/current", self.run)
end

function Game:start()
    local today = self.today
    local done = Krillion.history()[today.date]
    if done then
        Krillion.showSummary(today.date, done, today.resetsAt, true)
        return
    end

    local run = Store.get("krillion/current")
    if not (type(run) == "table" and run.date == today.date and type(run.results) == "table") then
        run = { date = today.date, dayNumber = today.dayNumber, runId = uuid4(), results = {} }
    end
    self.run = run

    -- A round left open last time: resume if time remains (or untimed), else it's a miss.
    if run.active_round then
        local i = run.active_round
        if not run.deadline or os.time() < run.deadline then
            UIManager:show(ConfirmBox:new {
                text = string.format("Resume round %d of %d?", i, ROUNDS),
                ok_text = "Resume",
                ok_callback = function() self:openAnswer(i, run.deadline) end,
            })
            return
        end
        self:record(self:miss(i, run.draft), true)
    end

    if #run.results >= ROUNDS then
        self:finish()
        return
    end

    local nxt = #run.results + 1
    local text
    if nxt == 1 then
        text = string.format("Krillion #%s\n\nSeven prompts, %d seconds each.\n"
            .. "Name anything that fits. Rarer answers dive deeper and score more.\n\nReady?",
            tostring(today.dayNumber), ANSWER_SECS)
    else
        text = string.format("Krillion #%s\n\nContinue from round %d of %d?\nScore so far: %d",
            tostring(today.dayNumber), nxt, ROUNDS, sumScore(run.results))
    end
    UIManager:show(ConfirmBox:new {
        text = text,
        ok_text = nxt == 1 and "Dive" or "Continue",
        ok_callback = function() self:startRound(nxt) end,
    })
end

function Game:startRound(i)
    local prompt = self.today.prompts[i]
    if not prompt then return end

    local opened = false
    local function open()
        if opened then return end
        opened = true
        local deadline = Krillion.timedRounds() and (os.time() + ANSWER_SECS) or nil
        self.run.active_round, self.run.deadline, self.run.draft = i, deadline, nil
        self:save()
        self:openAnswer(i, deadline)
    end

    UIManager:show(InfoMessage:new {
        text = string.format("Round %d of %d\n\n%s", i, ROUNDS, prompt.text),
        timeout = PREVIEW_SECS,
        dismiss_callback = open,
    })
    UIManager:scheduleIn(PREVIEW_SECS + 0.5, open)
end

local function roundTitle(i, deadline)
    if not deadline then
        return string.format("Round %d of %d", i, ROUNDS)
    end
    return string.format("Round %d of %d  ·  %d s", i, ROUNDS, math.max(0, deadline - os.time()))
end

function Game:openAnswer(i, deadline)
    local prompt = self.today.prompts[i]
    local dialog, tick
    local busy, closed = false, false

    local function closeDialog()
        if closed then return end
        closed = true
        if tick then UIManager:unschedule(tick) end
        dialog._round_finished = true
        UIManager:close(dialog)
    end

    local function submit(final)
        if busy or closed then return end
        local text = trim(dialog:getInputText()):sub(1, MAX_ANSWER_LENGTH)
        if text == "" then
            if final then
                closeDialog()
                self:record(self:miss(i))
            else
                toast("Type an answer first.")
            end
            return
        end

        busy = true
        local res, code, err = UI.withBusy("Sonar ping…", function()
            return Api.submit {
                date = self.today.date, promptId = prompt.id, answer = text,
                previewCorrection = not final, playerId = Krillion.playerId(), runId = self.run.runId,
            }
        end)
        busy = false
        local expired = deadline and os.time() >= deadline

        if code == 403 then
            closeDialog()
            UI.error("krillion.io refused the request (403). Try again later.")
        elseif not res or code ~= 200 then
            if final or expired then
                closeDialog()
                self:record(self:miss(i, text, nil, "Signal lost."))
            else
                toast("Signal lost (" .. tostring(err or code) .. "). Resend.")
            end
        elseif res.correction and not final and not expired then
            dialog:setInputText(res.correction)
            toast("Did you mean \"" .. res.correction .. "\"? Submit again to confirm.")
        elseif res.accepted and res.tier then
            closeDialog()
            local tier = TIERS[res.tier]
            self:record {
                promptId = prompt.id, promptText = prompt.text, rawAnswer = text,
                answer = res.answer or text, tier = res.tier,
                score = res.score or (tier and tier.score) or 0,
                quip = res.quip, receipt = res.receipt,
            }
        elseif final or expired then
            closeDialog()
            self:record(self:miss(i, text, res.receipt, res.rejectionReason))
        else
            toast((res.rejectionReason or ("\"" .. text .. "\": no echo.")) .. " Try again.")
        end
    end

    dialog = InputDialog:new {
        title = roundTitle(i, deadline),
        description = prompt.text,
        input = self.run.draft or "",
        input_hint = "Your answer",
        buttons = { {
            { text = "Pass", callback = function() closeDialog(); self:record(self:miss(i)) end },
            { text = "Submit", is_enter_default = true, callback = function() submit(false) end },
        } },
    }

    -- Leaving the dialog any other way keeps the round open (it resumes or misses next time).
    local orig_close = dialog.onCloseWidget
    dialog.onCloseWidget = function(this, ...)
        closed = true
        if tick then UIManager:unschedule(tick) end
        if not this._round_finished and self.run.active_round == i then
            local ok, txt = pcall(this.getInputText, this)
            if ok then
                self.run.draft = txt
                self:save()
            end
        end
        if orig_close then return orig_close(this, ...) end
    end

    if deadline then
        tick = function()
            if closed then return end
            local left = deadline - os.time()
            if left <= 0 then
                if busy then UIManager:scheduleIn(0.5, tick) else submit(true) end
                return
            end
            -- Update the countdown every 5 s, then every second near the end (e-ink friendly).
            if dialog.title_bar and dialog.title_bar.setTitle and (left <= 10 or left % 5 == 0) then
                pcall(dialog.title_bar.setTitle, dialog.title_bar, roundTitle(i, deadline))
            end
            UIManager:scheduleIn(1, tick)
        end
        UIManager:scheduleIn(1, tick)
    end

    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Game:miss(i, answer, receipt, reason)
    local prompt = self.today.prompts[i]
    return {
        promptId = prompt.id, promptText = prompt.text, rawAnswer = answer, answer = answer,
        tier = "miss", score = 0, receipt = receipt, rejectionReason = reason,
    }
end

function Game:record(result, silent)
    local run = self.run
    if #run.results >= ROUNDS then return end
    for _, r in ipairs(run.results) do
        if r.promptId == result.promptId then return end -- one result per round
    end
    table.insert(run.results, result)
    run.active_round, run.deadline, run.draft = nil, nil, nil
    self:save()
    if silent then return end

    local total = sumScore(run.results)
    local lines = {}
    if result.tier == "miss" then
        table.insert(lines, "No echo. 0 points.")
        if result.answer and result.answer ~= "" then
            table.insert(lines, "Your answer: " .. result.answer)
        end
        if result.rejectionReason then table.insert(lines, result.rejectionReason) end
    else
        table.insert(lines, result.answer)
        table.insert(lines, string.format("%s  +%d", tierLabel(result), result.score))
        if result.quip and result.quip ~= "" then
            table.insert(lines, "")
            table.insert(lines, result.quip)
        end
    end
    table.insert(lines, "")
    table.insert(lines, string.format("Score %d  ·  depth %d m", total, total * 10))

    local is_last = #run.results >= ROUNDS
    UIManager:show(ConfirmBox:new {
        text = table.concat(lines, "\n"),
        ok_text = is_last and "Surface" or "Next prompt",
        cancel_text = "Later",
        ok_callback = function()
            if is_last then self:finish() else self:startRound(#run.results + 1) end
        end,
        cancel_callback = function()
            if is_last then self:finish() end
        end,
    })
end

--- Reports the finished day (with receipts, so it counts on the leaderboard) and saves it.
function Game:finish()
    local run = self.run
    local score = sumScore(run.results)
    local player = Krillion.playerId()

    -- A replay after "Reset today's dive" is kept local: the first result
    -- already counted on krillion.io.
    local replay = Store.get("krillion/replay_date") == run.date
    local resp = not replay and UI.withBusy("Surfacing…", function()
        local receipts, complete = {}, true
        for idx, r in ipairs(run.results) do
            if not r.receipt and r.score == 0 then
                -- Rounds that never reached the server need a zero-score receipt.
                local res, code = Api.submit {
                    date = run.date, promptId = r.promptId, answer = "",
                    previewCorrection = false, playerId = player, runId = run.runId,
                }
                if code == 200 and res and not res.accepted then r.receipt = res.receipt end
            end
            receipts[idx] = r.receipt
            if not r.receipt then complete = false end
        end
        local record = complete and #receipts == ROUNDS
        local res, code = Api.complete {
            date = run.date, playerId = player, score = score,
            record = record, runId = run.runId, receipts = receipts,
        }
        if (not res or code ~= 200) and record then
            res, code = Api.complete { date = run.date, playerId = player, score = score, record = false }
        end
        return code == 200 and res or nil
    end)

    local tiers = {}
    for _, r in ipairs(run.results) do table.insert(tiers, r.tier) end
    local entry = {
        dayNumber = run.dayNumber,
        score = score,
        tiers = tiers,
        results = run.results,
        betterThan = resp and type(resp.betterThan) == "number" and resp.betterThan or nil,
    }
    local history = Krillion.history()
    history[run.date] = entry
    Store.set("krillion/history", history, true)
    Store.set("krillion/last_date", run.date, true)
    Store.set("krillion/current", nil)

    Krillion.showSummary(run.date, entry, self.today.resetsAt, false)
end

-- views ----------------------------------------------------------------------

function Krillion.shareText(entry)
    local em = {}
    for _, t in ipairs(entry.tiers or {}) do
        table.insert(em, TIERS[t] and TIERS[t].emoji or MISS_EMOJI)
    end
    return string.format("Krillion #%s 🦐\n%d\n\n%s\n\nhttps://krillion.io",
        tostring(entry.dayNumber), entry.score or 0, table.concat(em))
end

local TOP_ANSWERS = 5

--- Per prompt: total answers, the top few, and how many others gave your answer.
-- Kept in settings (the full list is a couple of MB) and refreshed every 15 min
-- while it's still today's dive.
function Krillion.answerStats(date, entry)
    local cached = Store.get("krillion/popularity")
    local fresh = type(cached) == "table" and cached.date == date
    if fresh and (date ~= Krillion.today() or os.time() - (cached.fetched or 0) < 15 * 60) then
        return cached.prompts
    end
    if date ~= Krillion.today() then return nil end
    local prompts = UI.withBusy("Loading top answers…", function() return Api.popularity(date) end)
    if not prompts then return fresh and cached.prompts or nil end
    local mine = {}
    for _, r in ipairs(entry.results or {}) do mine[r.promptId] = r.answer end
    local stats = {}
    for pid, counts in pairs(prompts) do
        local total, list = 0, {}
        for name, n in pairs(counts) do
            if type(n) == "number" and n > 0 then
                total = total + n
                list[#list + 1] = { name, n }
            end
        end
        table.sort(list, function(x, y) return x[2] > y[2] end)
        local top = {}
        for i = 1, math.min(TOP_ANSWERS, #list) do top[i] = list[i] end
        local own = mine[pid] and counts[mine[pid]]
        stats[pid] = { total = total, top = top, mine = type(own) == "number" and own or 0, mine_answer = mine[pid] }
    end
    Store.set("krillion/popularity", { date = date, fetched = os.time(), prompts = stats })
    return stats
end

local function commas(n)
    local s = tostring(math.floor(n))
    while true do
        local r, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        s = r
        if k == 0 then return s end
    end
end

local function percent(n, total)
    local p = n / math.max(total, 1) * 100
    return p >= 1 and string.format("%d%%", math.floor(p + 0.5)) or "<1%"
end

function Krillion.showSummary(date, entry, resets_at, already)
    local lines = {}
    if already then
        table.insert(lines, "You already dove today. Come back after the reset.")
        table.insert(lines, "")
    end
    table.insert(lines, string.format("Krillion #%s  ·  %s", tostring(entry.dayNumber), date))
    table.insert(lines, string.format("Score: %d / 700   Depth: %d m", entry.score, entry.score * 10))
    table.insert(lines, bandFor(entry.score))
    if entry.betterThan then
        table.insert(lines, string.format("Deeper than %d%% of divers today.", math.floor(entry.betterThan + 0.5)))
    end
    local stats = Krillion.answerStats(date, entry)
    table.insert(lines, "")
    table.insert(lines, "Dive log")
    for idx, r in ipairs(entry.results or {}) do
        table.insert(lines, string.format("%d. %s", idx, r.promptText or r.promptId))
        if r.tier == "miss" then
            local a = (r.answer and r.answer ~= "") and (r.answer .. "  ·  ") or ""
            table.insert(lines, "   " .. a .. "miss, 0")
        else
            table.insert(lines, string.format("   %s  ·  %s, %d", r.answer or "", tierLabel(r), r.score or 0))
        end
        local st = stats and stats[r.promptId]
        if st then
            if r.tier ~= "miss" and r.answer and r.answer ~= "" and st.mine_answer == r.answer then
                -- like the site: everyone else who gave the same answer
                local others = math.max(0, st.mine - 1)
                table.insert(lines, string.format("   %s other %s chose this", commas(others),
                    others == 1 and "diver" or "divers"))
            end
            local top = {}
            for _, t in ipairs(st.top) do top[#top + 1] = t[1] .. " " .. percent(t[2], st.total) end
            if #top > 0 then table.insert(lines, "   Top: " .. table.concat(top, " · ")) end
        end
    end
    local share = Krillion.shareText(entry)
    table.insert(lines, "")
    table.insert(lines, "Share text:")
    table.insert(lines, share)
    if resets_at then
        local when = resets_at:gsub("T", " "):gsub("%.%d+Z$", "")
        table.insert(lines, "")
        table.insert(lines, "Next dive: " .. when .. " (UTC)")
    end

    local viewer
    local row = { {
        text = "Copy share text",
        callback = function()
            if Device.input and Device.input.setClipboardText then
                Device.input.setClipboardText(share)
                toast("Copied.")
            end
        end,
    } }
    if date == Krillion.today() then
        table.insert(row, {
            text = "Reset today's dive",
            callback = function()
                Krillion.resetToday(function()
                    UIManager:close(viewer)
                    Krillion.play()
                end)
            end,
        })
    end
    viewer = TextViewer:new {
        title = "Krillion",
        text = table.concat(lines, "\n"),
        add_default_buttons = true,
        buttons_table = { row },
    }
    UIManager:show(viewer)
end

--- Today's puzzle date as krillion.io counts it (new dive at midnight US Eastern,
-- approximated as 05:00 UTC).
function Krillion.today()
    return os.date("!%Y-%m-%d", os.time() - 5 * 3600)
end

--- Clears today's dive so it can be played again (the replay isn't submitted).
--- on_done (optional) runs after a successful reset, e.g. to start the dive again.
function Krillion.resetToday(on_done)
    UIManager:show(ConfirmBox:new {
        text = "Reset today's dive?\n\nYou can play it again here; the new score stays on this device and isn't sent to krillion.io.",
        ok_text = "Reset",
        ok_callback = function()
            local date = Krillion.today()
            local history = Krillion.history()
            local current = Store.get("krillion/current")
            local has_current = type(current) == "table" and current.date == date
            if not history[date] and not has_current then
                return UI.notify("Nothing to reset yet today.", 1.5)
            end
            history[date] = nil
            Store.set("krillion/history", history, true)
            Store.set("krillion/replay_date", date, true)
            Store.set("krillion/current", nil)
            if on_done then
                on_done()
            else
                UI.notify("Today's dive was reset.", 1.5)
            end
        end,
    })
end

function Krillion.showLastResult()
    local date = Store.get("krillion/last_date")
    local entry = date and Krillion.history()[date]
    if not entry then
        UI.error("No finished dives yet.")
        return
    end
    Krillion.showSummary(date, entry, nil, false)
end

function Krillion.showStats()
    local history = Krillion.history()
    local dates = {}
    for d in pairs(history) do
        if dateToTime(d) then table.insert(dates, d) end
    end
    table.sort(dates)

    local total, best, streak, longest, prev = 0, 0, 0, 0, nil
    for _, d in ipairs(dates) do
        local s = history[d].score or 0
        total = total + s
        best = math.max(best, s)
        local t = dateToTime(d)
        if prev and math.floor((t - prev) / 86400 + 0.5) == 1 then
            streak = streak + 1
        else
            streak = 1
        end
        longest = math.max(longest, streak)
        prev = t
    end
    -- The current streak only counts if the last dive was today or yesterday.
    local current = (prev and os.time() - prev <= 2 * 86400) and streak or 0
    local played = #dates

    UIManager:show(InfoMessage:new {
        text = string.format("Krillion\n\nDives: %d\nAverage score: %d\nBest score: %d\nCurrent streak: %d\nLongest streak: %d",
            played, played > 0 and math.floor(total / played + 0.5) or 0, best, current, longest),
    })
end

function Krillion.showHelp()
    UIManager:show(InfoMessage:new {
        text = [[Krillion: a daily dive of seven prompts.

Each prompt shows for 3 seconds, then you have 25 seconds to name anything that fits. Common answers score little, rare ones score big:

Plankton 10 · Too Clever 15 · Schooler 30
Rare 60 · Deep Cut 85 · One in a Krillion 100

Max 700 points (7,000 m). Invalid answers can be retried while time remains. When time runs out, whatever you typed is submitted.

Puzzles and scoring come from krillion.io.]],
    })
end

Krillion._Api = Api -- exposed for tests

return Krillion
