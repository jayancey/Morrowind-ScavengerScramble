-- Round state and persistence. The state survives server restarts so a round
-- in progress can be resumed with its remaining time.

local config = require("custom.scavenger-scramble.config")
local util = require("custom.scavenger-scramble.util")

local state = {}

local function freshState()
    return {
        phase = "idle",            -- idle | scramble | showcase
        nextLocation = nil,        -- key chosen for the next round, nil = random
        locationKey = nil,
        locationName = nil,
        objectives = {},
        lengthMinutes = nil,
        startedAt = nil,
        endsAt = nil,
        showcaseEndsAt = nil,
        participants = {},         -- [account] = participant
        lastResults = nil,
        showcase = nil,            -- staff override of config.showcase, set with /scramble showcase
    }
end

state.current = freshState()
state.history = { rounds = 0, wins = {}, played = {} }

function state.reset()
    local keepLocation = state.current.nextLocation
    local keepResults = state.current.lastResults
    local keepShowcase = state.current.showcase
    state.current = freshState()
    state.current.nextLocation = keepLocation
    state.current.lastResults = keepResults
    state.current.showcase = keepShowcase
    state.save()
end

function state.save()
    local ok, err = pcall(jsonInterface.save, config.stateFile, state.current)
    if not ok then util.warn("Could not save state: " .. tostring(err)) end
end

local function fileExists(fileName)
    local ok, exists = pcall(tes3mp.DoesFileExist, tes3mp.GetDataPath() .. "/" .. fileName)
    return ok and exists == true
end

function state.load()
    local ok, loaded = false, nil
    if fileExists(config.stateFile) then
        ok, loaded = pcall(jsonInterface.load, config.stateFile)
    end
    if ok and type(loaded) == "table" and loaded.phase ~= nil then
        state.current = loaded
        state.current.participants = state.current.participants or {}
        state.current.objectives = state.current.objectives or {}
    else
        state.current = freshState()
    end

    local okHistory, history = false, nil
    if fileExists(config.historyFile) then
        okHistory, history = pcall(jsonInterface.load, config.historyFile)
    end
    if okHistory and type(history) == "table" then
        state.history = history
        state.history.wins = state.history.wins or {}
        state.history.played = state.history.played or {}
        state.history.rounds = state.history.rounds or 0
    end
end

function state.saveHistory()
    local ok, err = pcall(jsonInterface.save, config.historyFile, state.history)
    if not ok then util.warn("Could not save history: " .. tostring(err)) end
end

function state.phase()
    return state.current.phase
end

function state.participant(account)
    if account == nil then return nil end
    return state.current.participants[account]
end

function state.participantOf(pid)
    return state.participant(util.accountOf(pid))
end

function state.addParticipant(pid)
    local account = util.accountOf(pid)
    if account == nil then return nil end
    local participant = state.current.participants[account]
    if participant == nil then
        participant = {
            account = account,
            name = util.displayName(pid),
            startInventory = util.inventoryCounts(pid),
            acquired = {},
            displayed = {},
            done = false,
            doneAt = nil,
            joinedAt = os.time(),
        }
        state.current.participants[account] = participant
    end
    participant.name = util.displayName(pid)
    return participant
end

-- Pids of participants who are online right now.
function state.participantPids()
    local pids = {}
    for account in pairs(state.current.participants) do
        local pid = util.pidOfAccount(account)
        if pid ~= nil then table.insert(pids, pid) end
    end
    table.sort(pids)
    return pids
end

function state.participantCount()
    return util.count(state.current.participants)
end

function state.recordResults(rows)
    state.history.rounds = (state.history.rounds or 0) + 1
    for _, row in ipairs(rows) do
        state.history.played[row.account] = (state.history.played[row.account] or 0) + 1
        if row.rank == 1 or row.tiedWithWinner then
            state.history.wins[row.account] = (state.history.wins[row.account] or 0) + 1
        end
    end
    state.saveHistory()

    local summary = {}
    for _, row in ipairs(rows) do
        table.insert(summary, { name = row.name, account = row.account, score = row.score,
            points = row.points, bonus = row.bonus, totalValue = row.totalValue, rank = row.rank })
    end
    state.current.lastResults = {
        location = state.current.locationName,
        objectives = state.current.objectives,
        rows = summary,
        finishedAt = os.time(),
    }
end

return state
