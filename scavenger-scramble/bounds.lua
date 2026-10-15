-- Keeps participants inside the location during the scramble phase.

local config = require("custom.scavenger-scramble.config")
local util = require("custom.scavenger-scramble.util")
local state = require("custom.scavenger-scramble.state")
local locations = require("custom.scavenger-scramble.locations")

local bounds = {}

bounds.graceTimers = {}   -- [pid] = timer id, kept for reuse (timers are never freed)
bounds.pending = {}       -- [pid] = true while a grace period is running

local function cancelGrace(pid)
    if bounds.pending[pid] then
        util.stopTimer(bounds.graceTimers[pid])
        bounds.pending[pid] = nil
    end
end

function bounds.isInBounds(pid, cellDescription)
    local current = state.current
    if current.phase ~= "scramble" then return true end
    return locations.isInBounds(current.locationKey, cellDescription or tes3mp.GetCell(pid))
end

function bounds.onCellChange(eventStatus, pid, playerPacket, previousCellDescription)
    local current = state.current
    if current.phase ~= "scramble" then return end
    if state.participantOf(pid) == nil then return end

    local cell = nil
    if playerPacket ~= nil and playerPacket.location ~= nil then
        cell = playerPacket.location.cell
    end
    if cell == nil then cell = tes3mp.GetCell(pid) end

    if locations.isInBounds(current.locationKey, cell) then
        if bounds.pending[pid] then
            cancelGrace(pid)
            util.say(pid, "Back in bounds.")
        end
        return
    end

    if not bounds.pending[pid] then
        util.say(pid, string.format("%s is outside %s! Return within %d seconds or you will be sent back.",
            tostring(cell), tostring(current.locationName), config.boundsGraceSeconds))
        bounds.graceTimers[pid] = util.armTimer(bounds.graceTimers[pid], "Scramble_OnGraceExpired",
            config.boundsGraceSeconds * 1000, "i", pid)
        bounds.pending[pid] = true
    end
end

function bounds.onDisconnect(pid)
    cancelGrace(pid)
end

function bounds.clearAll()
    for pid in pairs(bounds.pending) do
        cancelGrace(pid)
    end
end

function Scramble_OnGraceExpired(pid)
    bounds.pending[pid] = nil
    if not util.isOnline(pid) then return end
    local current = state.current
    if current.phase ~= "scramble" then return end
    if state.participantOf(pid) == nil then return end

    local cell = tes3mp.GetCell(pid)
    if locations.isInBounds(current.locationKey, cell) then return end

    util.say(pid, "Out of bounds too long. Sending you back to the start.")
    util.sayAll(util.displayName(pid) .. " wandered off and was sent back to " .. tostring(current.locationName) .. ".")
    Scramble.round.teleportToSpawn(pid)
end

return bounds
