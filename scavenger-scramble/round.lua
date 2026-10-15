-- Round flow: start, scramble phase, showcase phase, results.

local config = require("custom.scavenger-scramble.config")
local util = require("custom.scavenger-scramble.util")
local state = require("custom.scavenger-scramble.state")
local locations = require("custom.scavenger-scramble.locations")
local objectives = require("custom.scavenger-scramble.objectives")
local scoring = require("custom.scavenger-scramble.scoring")

local round = {}

-- Timer ids are created once and reused for the life of the server (see
-- util.armTimer for why they are never freed).
--   roundEnd, showcase: single timers
--   countdowns[mark]:   one timer per countdown mark
--   respawn[pid]:       one timer per player slot
round.timers = { roundEnd = nil, countdowns = {}, showcase = nil, respawn = {} }

local function clearTimers()
    util.stopTimer(round.timers.roundEnd)
    for _, id in pairs(round.timers.countdowns) do util.stopTimer(id) end
    util.stopTimer(round.timers.showcase)
end

local function armScrambleTimers(secondsLeft)
    clearTimers()
    round.timers.roundEnd = util.armTimer(round.timers.roundEnd, "Scramble_OnRoundEnd", secondsLeft * 1000)

    for _, mark in ipairs(config.countdownMarks) do
        if mark < secondsLeft then
            round.timers.countdowns[mark] = util.armTimer(round.timers.countdowns[mark], "Scramble_OnCountdown",
                (secondsLeft - mark) * 1000, "i", mark)
        end
    end

    -- The showcase timer is armed from inside the round-end callback, so make sure
    -- it already exists now, while no timer is being ticked.
    if round.timers.showcase == nil then
        round.timers.showcase = util.createStoppedTimer("Scramble_OnShowcaseTimeout")
    end
end

local function armShowcaseTimer(secondsLeft)
    util.stopTimer(round.timers.showcase)
    round.timers.showcase = util.armTimer(round.timers.showcase, "Scramble_OnShowcaseTimeout", secondsLeft * 1000)
end

function round.timeLeft()
    local current = state.current
    if current.phase == "scramble" and current.endsAt ~= nil then
        return math.max(0, current.endsAt - os.time())
    elseif current.phase == "showcase" and current.showcaseEndsAt ~= nil then
        return math.max(0, current.showcaseEndsAt - os.time())
    end
    return 0
end

function round.spawn()
    return locations.spawnOf(state.current.locationKey)
end

-- Showcase spot: a staff override saved with the state wins over config.lua.
function round.showcaseSpot()
    local override = state.current.showcase
    if override ~= nil and override.cell ~= nil then
        return override
    end
    return config.showcase
end

function round.objectiveLines()
    local lines = {}
    for i, objective in ipairs(state.current.objectives) do
        table.insert(lines, objectives.describe(objective, i))
    end
    return lines
end

function round.sendObjectives(pid)
    local current = state.current
    if current.phase == "idle" then
        util.say(pid, "No round is running.")
        return
    end
    util.say(pid, "Objectives in " .. tostring(current.locationName) .. ":")
    for _, line in ipairs(round.objectiveLines()) do
        util.say(pid, "  " .. line)
    end
    if current.phase == "scramble" then
        util.say(pid, "Time left: " .. util.formatDuration(round.timeLeft()))
    end
end

function round.teleportToSpawn(pid)
    local spot = round.spawn()
    if spot == nil then
        util.warn("No spawn for location " .. tostring(state.current.locationKey))
        return
    end
    util.teleportToSpot(pid, spot)
end

function round.teleportToShowcase(pid)
    util.teleportToSpot(pid, round.showcaseSpot())
end

function round.joinScramble(pid)
    local participant = state.addParticipant(pid)
    if participant == nil then return end
    round.teleportToSpawn(pid)
    round.sendObjectives(pid)
    Scramble.gui.showObjectives(pid)
    state.save()
end

-- /scramble start
function round.start(pid, minutes)
    local current = state.current
    if current.phase ~= "idle" then
        return "A round is already running (" .. current.phase .. "). Use /scramble stop first."
    end

    local pids = util.onlinePids()
    if #pids == 0 then
        return "Nobody is online."
    end

    local key = current.nextLocation
    if key == nil or key == "random" then
        key = locations.randomKey()
    end
    local location = locations.get(key)
    if location == nil then
        return "No location is available. Generate data/locations.lua first."
    end

    minutes = tonumber(minutes) or config.roundMinutes
    if minutes < 1 then minutes = 1 end

    local rolled = objectives.roll(location)
    if #rolled == 0 then
        return "Could not roll objectives for " .. tostring(location.name) .. "."
    end

    util.sayAll("A Scavenger Scramble is starting in " .. tostring(location.name) .. "!")

    if config.resetCellsOnStart then
        local okReset, err = pcall(locations.resetCells, key)
        if not okReset then
            util.warn("Cell reset failed: " .. tostring(err))
            util.sayAll("Warning: the cell reset failed, loot may not be pristine.")
        end
    end

    current.phase = "scramble"
    current.locationKey = key
    current.locationName = location.name or key
    current.objectives = rolled
    current.lengthMinutes = minutes
    current.startedAt = os.time()
    current.endsAt = current.startedAt + minutes * 60
    current.showcaseEndsAt = nil
    current.participants = {}

    for _, playerPid in ipairs(pids) do
        state.addParticipant(playerPid)
    end
    state.save()

    armScrambleTimers(minutes * 60)

    for _, playerPid in ipairs(pids) do
        round.teleportToSpawn(playerPid)
    end

    util.sayAll(string.format("You have %d minutes. Hold your finds in your inventory when time runs out.", minutes))
    util.sayAll("Objectives:")
    for _, line in ipairs(round.objectiveLines()) do
        util.sayAll("  " .. line)
    end
    util.sayAll("Type /scramble objectives to see them again, /scramble status for the time left.")

    for _, playerPid in ipairs(pids) do
        Scramble.gui.showObjectives(playerPid)
    end

    util.log("Round started in " .. key .. " for " .. minutes .. " minutes with " .. #pids .. " players")
    return nil
end

-- /scramble stop
function round.stop(pid)
    local current = state.current
    if current.phase == "idle" then
        return "No round is running."
    end
    clearTimers()
    local who = pid ~= nil and util.displayName(pid) or "the server"
    util.sayAll("The round was stopped by " .. who .. ". Returning everyone to the showcase.")
    for _, playerPid in ipairs(state.participantPids()) do
        round.teleportToShowcase(playerPid)
    end
    state.reset()
    return nil
end

-- Timer: scramble phase over. Snapshot inventories and move to the showcase.
function round.finishScramble()
    local current = state.current
    if current.phase ~= "scramble" then return end

    clearTimers()
    util.sayAll("Time is up! Hands off the loot.")

    for account, participant in pairs(current.participants) do
        local playerPid = util.pidOfAccount(account)
        if playerPid ~= nil then
            participant.name = util.displayName(playerPid)
            participant.acquired = util.inventoryDelta(participant.startInventory or {}, util.inventoryCounts(playerPid))
        else
            participant.acquired = participant.acquired or {}
        end
        participant.displayed = {}
        participant.done = false
        participant.doneAt = nil

        local found = 0
        for _ in pairs(participant.acquired) do found = found + 1 end
        util.log("Participant " .. account .. " acquired " .. found .. " distinct items")
    end

    current.phase = "showcase"
    current.showcaseEndsAt = os.time() + config.showcaseMinutes * 60
    state.save()

    armShowcaseTimer(config.showcaseMinutes * 60)

    if config.resetShowcaseCell then
        local okReset, err = pcall(locations.resetCellList, { round.showcaseSpot().cell }, "showcase")
        if not okReset then
            util.warn("Showcase cell reset failed: " .. tostring(err))
        end
    end

    for _, playerPid in ipairs(state.participantPids()) do
        round.teleportToShowcase(playerPid)
    end

    util.sayAll(string.format("Welcome to the showcase at %s. Drop the items you found to display them.", round.showcaseSpot().cell))
    util.sayAll(string.format("Type /scramble done when your display is complete (or /scramble pass). Scoring in %d minutes regardless.",
        config.showcaseMinutes))
    for _, line in ipairs(round.objectiveLines()) do
        util.sayAll("  " .. line)
    end
end

-- Showcase over (everyone done or timeout). Score and announce.
function round.finishShowcase()
    local current = state.current
    if current.phase ~= "showcase" then return end
    clearTimers()

    local participants = {}
    for account, participant in pairs(current.participants) do
        local displayed = {}
        for _, entry in pairs(participant.displayed or {}) do
            table.insert(displayed, { refId = entry.refId, count = entry.count, value = objectives.itemValue(entry.refId) })
        end
        participants[account] = { name = participant.name, displayed = displayed, doneAt = participant.doneAt }
    end

    local rows = scoring.compute(current.objectives, participants)

    util.sayAll("Scavenger Scramble results for " .. tostring(current.locationName) .. ":")
    for _, row in ipairs(rows) do
        util.sayAll(string.format("  #%d %s", row.rank, scoring.describeRow(row, current.objectives)))
    end

    if #rows > 0 then
        local winners = { rows[1].name }
        for i = 2, #rows do
            if rows[i].tiedWithWinner then table.insert(winners, rows[i].name) end
        end
        if #winners == 1 then
            util.sayAll(color.Yellow .. winners[1] .. " wins the Scramble!")
        else
            util.sayAll(color.Yellow .. "It's a tie between " .. table.concat(winners, " and ") .. "!")
        end
    end

    state.recordResults(rows)
    for _, playerPid in ipairs(util.onlinePids()) do
        Scramble.gui.showScoreboard(playerPid, rows, current.objectives, current.locationName)
    end

    util.log("Round finished in " .. tostring(current.locationKey))
    state.reset()
end

-- Events --------------------------------------------------------------------

function round.onAuthentified(pid)
    local current = state.current
    if current.phase == "idle" then return end

    local participant = state.participantOf(pid)
    if current.phase == "scramble" then
        if participant ~= nil then
            participant.name = util.displayName(pid)
            round.teleportToSpawn(pid)
            round.sendObjectives(pid)
            util.say(pid, "Welcome back, the round is still running.")
        elseif config.allowLateJoin then
            round.joinScramble(pid)
            util.sayAll(util.displayName(pid) .. " joined the Scramble late.")
        else
            util.say(pid, "A Scramble is running without you. Wait for the next one.")
        end
    elseif current.phase == "showcase" then
        round.teleportToShowcase(pid)
        if participant ~= nil then
            util.say(pid, "The showcase is in progress. Drop your finds and type /scramble done.")
        end
    end
end

function round.onResurrect(pid)
    local current = state.current
    if current.phase == "idle" then return end
    if state.participantOf(pid) == nil then return end
    round.timers.respawn[pid] = util.armTimer(round.timers.respawn[pid], "Scramble_OnRespawnReturn",
        config.respawnReturnSeconds * 1000, "i", pid)
    util.say(pid, "You died. Returning you to the round shortly.")
end

-- A player slot is being vacated: make sure no pending return teleport hits
-- whoever gets the slot next.
function round.onDisconnect(pid)
    util.stopTimer(round.timers.respawn[pid])
end

-- Called on server start to resume a persisted round.
function round.resume()
    local current = state.current
    if current.phase == "scramble" then
        local left = round.timeLeft()
        if left < 10 then left = 10 end
        armScrambleTimers(left)
        util.log("Resumed scramble phase with " .. left .. "s left")
    elseif current.phase == "showcase" then
        local left = round.timeLeft()
        if left < 30 then left = 30 end
        armShowcaseTimer(left)
        util.log("Resumed showcase phase with " .. left .. "s left")
    end
end

-- Global timer callbacks (the timer API only accepts global function names).

function Scramble_OnRoundEnd()
    local ok, err = pcall(round.finishScramble)
    if not ok then util.warn("finishScramble failed: " .. tostring(err)) end
end

function Scramble_OnCountdown(secondsLeft)
    if state.current.phase ~= "scramble" then return end
    util.sayAll(util.formatDuration(secondsLeft) .. " left!")
end

function Scramble_OnShowcaseTimeout()
    local ok, err = pcall(round.finishShowcase)
    if not ok then util.warn("finishShowcase failed: " .. tostring(err)) end
end

function Scramble_OnRespawnReturn(pid)
    if not util.isOnline(pid) then return end
    local current = state.current
    if current.phase == "scramble" then
        round.teleportToSpawn(pid)
    elseif current.phase == "showcase" then
        round.teleportToShowcase(pid)
    end
end

return round
