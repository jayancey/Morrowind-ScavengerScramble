-- /scramble command family.

local config = require("custom.scavenger-scramble.config")
local util = require("custom.scavenger-scramble.util")
local state = require("custom.scavenger-scramble.state")
local locations = require("custom.scavenger-scramble.locations")

local commands = {}

local function needControl(pid)
    if util.hasControl(pid) then return true end
    util.say(pid, "You need staff rank " .. config.controlRank .. " to do that.")
    return false
end

local function help(pid)
    util.say(pid, "Commands:")
    util.say(pid, "  /scramble objectives - current objectives")
    util.say(pid, "  /scramble status - phase, time left, participants")
    util.say(pid, "  /scramble done | pass - finish your showcase display")
    util.say(pid, "  /scramble results | leaderboard")
    if util.hasControl(pid) then
        util.say(pid, "  /scramble start [minutes] - start a round at the next location")
        util.say(pid, "  /scramble stop - abort the round")
        util.say(pid, "  /scramble location [name|number|random] - pick the next location")
        util.say(pid, "  /scramble minutes <n> - default round length")
        util.say(pid, "  /scramble here - print your position as a spawn override line")
        util.say(pid, "  /scramble showcase - make where you stand the showcase spot")
        util.say(pid, "  /scramble score - end the showcase now and score")
        util.say(pid, "  /scramble reset - clear a stuck round without scoring")
    end
end

local function leaderboard(pid)
    local history = state.history
    local accounts = util.keys(history.played or {})
    if #accounts == 0 then
        util.say(pid, "No rounds played yet.")
        return
    end
    table.sort(accounts, function(a, b)
        local wa, wb = history.wins[a] or 0, history.wins[b] or 0
        if wa ~= wb then return wa > wb end
        return a < b
    end)
    util.say(pid, string.format("Leaderboard after %d rounds:", history.rounds or 0))
    for i, account in ipairs(accounts) do
        util.say(pid, string.format("  %d. %s - %d wins / %d played", i, account, history.wins[account] or 0, history.played[account] or 0))
    end
end

local function results(pid)
    local last = state.current.lastResults
    if last == nil then
        util.say(pid, "No results yet.")
        return
    end
    util.say(pid, "Last round in " .. tostring(last.location) .. ":")
    for _, row in ipairs(last.rows or {}) do
        util.say(pid, string.format("  #%d %s - %d pts (%d found, %d bonus)", row.rank, row.name, row.score, row.points, row.bonus))
    end
end

local function chooseLocation(pid, text)
    if text == nil then
        Scramble.gui.showLocationList(pid)
        return
    end
    if util.lower(text) == "list" then
        for i, key in ipairs(locations.orderedKeys) do
            util.say(pid, string.format("  %d. %s", i, locations.nameOf(key)))
        end
        return
    end
    if util.lower(text) == "random" then
        state.current.nextLocation = "random"
        state.save()
        util.sayAll("Next Scramble location: random.")
        return
    end
    local key = locations.resolve(text)
    if key == nil then
        util.say(pid, "Unknown location. Try /scramble location list.")
        return
    end
    state.current.nextLocation = key
    state.save()
    util.sayAll("Next Scramble location: " .. locations.nameOf(key) .. ".")
    util.say(pid, locations.describe(key))
end

local function setShowcaseHere(pid)
    local spot = {
        cell = tes3mp.GetCell(pid),
        posX = tes3mp.GetPosX(pid), posY = tes3mp.GetPosY(pid), posZ = tes3mp.GetPosZ(pid),
        rotZ = tes3mp.GetRotZ(pid),
    }
    state.current.showcase = spot
    state.save()
    util.sayAll("Showcase spot set to " .. spot.cell .. " by " .. util.displayName(pid) .. ".")
end

local function here(pid)
    local cell = tes3mp.GetCell(pid)
    local line = string.format('{ cell = "%s", posX = %.1f, posY = %.1f, posZ = %.1f, rotZ = %.3f },',
        cell, tes3mp.GetPosX(pid), tes3mp.GetPosY(pid), tes3mp.GetPosZ(pid), tes3mp.GetRotZ(pid))
    util.say(pid, line)
    util.log("Position of " .. util.displayName(pid) .. ": " .. line)
end

function commands.scramble(pid, cmd)
    local sub = util.lower(cmd[2] or "help")
    local arg = cmd[3]
    if cmd[4] ~= nil then
        arg = table.concat(cmd, " ", 3)
    end

    if sub == "help" then
        help(pid)
    elseif sub == "objectives" or sub == "list" then
        Scramble.round.sendObjectives(pid)
        Scramble.gui.showObjectives(pid)
    elseif sub == "status" then
        Scramble.gui.showStatus(pid)
    elseif sub == "done" then
        local err = Scramble.showcase.markDone(pid, false)
        if err then util.say(pid, err) end
    elseif sub == "pass" then
        local err = Scramble.showcase.markDone(pid, true)
        if err then util.say(pid, err) end
    elseif sub == "results" then
        results(pid)
    elseif sub == "leaderboard" then
        leaderboard(pid)
    elseif sub == "start" then
        if needControl(pid) then
            local err = Scramble.round.start(pid, arg)
            if err then util.say(pid, err) end
        end
    elseif sub == "stop" then
        if needControl(pid) then
            local err = Scramble.round.stop(pid)
            if err then util.say(pid, err) end
        end
    elseif sub == "location" or sub == "loc" then
        if needControl(pid) then chooseLocation(pid, arg) end
    elseif sub == "minutes" then
        if needControl(pid) then
            local minutes = tonumber(arg)
            if minutes == nil then
                tes3mp.InputDialog(pid, config.gui.minutesInput, "Default round length in minutes", tostring(config.roundMinutes))
            elseif minutes >= 1 then
                config.roundMinutes = math.floor(minutes)
                util.sayAll("Default round length set to " .. config.roundMinutes .. " minutes.")
            end
        end
    elseif sub == "here" then
        if needControl(pid) then here(pid) end
    elseif sub == "showcase" then
        if needControl(pid) then setShowcaseHere(pid) end
    elseif sub == "score" then
        if needControl(pid) then
            if state.current.phase ~= "showcase" then
                util.say(pid, "There is no showcase to score.")
            else
                util.sayAll("Scoring now by staff request.")
                Scramble.round.finishShowcase()
            end
        end
    elseif sub == "reset" then
        if needControl(pid) then
            Scramble.round.stop(pid)
            Scramble.showcase.reset()
            Scramble.bounds.clearAll()
            state.reset()
            util.say(pid, "Round state cleared.")
        end
    else
        util.say(pid, "Unknown subcommand. Try /scramble help.")
    end
end

function commands.register()
    customCommandHooks.registerCommand("scramble", commands.scramble)
    customCommandHooks.registerCommand("ss", commands.scramble)
end

return commands
