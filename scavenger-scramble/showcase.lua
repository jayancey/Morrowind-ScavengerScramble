-- Showcase phase: detect items dropped in the showcase cell and credit them.

local config = require("custom.scavenger-scramble.config")
local util = require("custom.scavenger-scramble.util")
local state = require("custom.scavenger-scramble.state")
local objectives = require("custom.scavenger-scramble.objectives")

local showcase = {}

-- uniqueIndex -> { account, refId, count }, for picking items back up.
showcase.placed = {}

local function displayedCount(participant, refId)
    local total = 0
    for _, entry in pairs(participant.displayed or {}) do
        if entry.refId == refId then total = total + (entry.count or 1) end
    end
    return total
end

local function matchingObjectives(refId)
    local names = {}
    for i, objective in ipairs(state.current.objectives) do
        if objectives.matches(objective, refId) then
            table.insert(names, tostring(i))
        end
    end
    return names
end

function showcase.onObjectPlace(eventStatus, pid, cellDescription, objects, targetPlayers)
    local current = state.current
    if current.phase ~= "showcase" then return end
    if cellDescription ~= Scramble.round.showcaseSpot().cell then return end

    local participant = state.participantOf(pid)
    if participant == nil then return end

    for uniqueIndex, object in pairs(objects) do
        local refId = util.lower(object.refId)
        local count = tonumber(object.count) or 1
        local acquired = (participant.acquired or {})[refId] or 0
        local already = displayedCount(participant, refId)
        local creditable = math.min(count, acquired - already)

        if creditable > 0 then
            participant.displayed = participant.displayed or {}
            participant.displayed[uniqueIndex] = { refId = refId, count = creditable }
            showcase.placed[uniqueIndex] = { account = participant.account, refId = refId, count = creditable }

            local matches = matchingObjectives(refId)
            local note = ""
            if #matches > 0 then
                note = " (counts for objective " .. table.concat(matches, ", ") .. ")"
            else
                note = " (matches no objective)"
            end
            util.say(pid, "Displayed " .. objectives.itemName(refId) .. " x" .. creditable .. note)
            if #matches > 0 then
                util.sayAll(util.displayName(pid) .. " displays " .. objectives.itemName(refId) .. ".")
            end
            state.save()
        elseif acquired == 0 then
            util.say(pid, objectives.itemName(refId) .. " was not acquired during the round, so it does not count.")
        else
            util.say(pid, "You have already displayed all of your " .. objectives.itemName(refId) .. ".")
        end
    end
end

function showcase.onObjectDelete(eventStatus, pid, cellDescription, objects, targetPlayers)
    local current = state.current
    if current.phase ~= "showcase" then return end
    if cellDescription ~= Scramble.round.showcaseSpot().cell then return end

    for uniqueIndex in pairs(objects) do
        local placed = showcase.placed[uniqueIndex]
        if placed ~= nil then
            showcase.placed[uniqueIndex] = nil
            local owner = state.participant(placed.account)
            if owner ~= nil and owner.displayed ~= nil then
                owner.displayed[uniqueIndex] = nil
            end
            local taker = util.displayName(pid)
            if owner ~= nil and placed.account ~= util.accountOf(pid) then
                util.sayAll(taker .. " took " .. objectives.itemName(placed.refId) .. " from " .. (owner.name or placed.account) .. "'s display!")
            else
                util.say(pid, objectives.itemName(placed.refId) .. " removed from your display.")
            end
            state.save()
        end
    end
end

function showcase.allDone()
    local current = state.current
    local anyOnline = false
    for account, participant in pairs(current.participants) do
        local pid = util.pidOfAccount(account)
        if pid ~= nil then
            anyOnline = true
            if not participant.done then return false end
        end
    end
    return anyOnline
end

function showcase.markDone(pid, passed)
    local current = state.current
    if current.phase ~= "showcase" then
        return "There is no showcase in progress."
    end
    local participant = state.participantOf(pid)
    if participant == nil then
        return "You did not take part in this round."
    end
    if participant.done then
        return "You are already marked as done."
    end
    participant.done = true
    participant.doneAt = os.time()
    state.save()

    if passed then
        util.sayAll(util.displayName(pid) .. " passes.")
    else
        util.sayAll(util.displayName(pid) .. " is done displaying.")
    end

    if showcase.allDone() then
        util.sayAll("Everyone is done. Scoring...")
        Scramble.round.finishShowcase()
    end
    return nil
end

function showcase.reset()
    showcase.placed = {}
end

return showcase
