-- Small helpers shared by every Scavenger Scramble module.

local config = require("custom.scavenger-scramble.config")

local util = {}

function util.log(message)
    tes3mp.LogMessage(enumerations.log.INFO, "[Scramble] " .. tostring(message))
end

function util.warn(message)
    tes3mp.LogMessage(enumerations.log.WARN, "[Scramble] " .. tostring(message))
end

function util.lower(s)
    if s == nil then return nil end
    return string.lower(s)
end

-- Players currently logged in, as an array of pids.
function util.onlinePids()
    local pids = {}
    for pid, player in pairs(Players) do
        if player ~= nil and player:IsLoggedIn() then
            table.insert(pids, pid)
        end
    end
    table.sort(pids)
    return pids
end

function util.anyPid()
    local pids = util.onlinePids()
    return pids[1]
end

function util.isOnline(pid)
    return pid ~= nil and Players[pid] ~= nil and Players[pid]:IsLoggedIn()
end

function util.accountOf(pid)
    if Players[pid] == nil then return nil end
    return Players[pid].accountName
end

function util.pidOfAccount(accountName)
    for pid, player in pairs(Players) do
        if player ~= nil and player:IsLoggedIn() and player.accountName == accountName then
            return pid
        end
    end
    return nil
end

function util.displayName(pid)
    if Players[pid] == nil then return "?" end
    local ok, name = pcall(tes3mp.GetName, pid)
    if ok and name ~= nil and name ~= "" then return name end
    return Players[pid].accountName or tostring(pid)
end

function util.hasControl(pid)
    local player = Players[pid]
    if player == nil then return false end
    local rank = 0
    if player.data ~= nil and player.data.settings ~= nil then
        rank = player.data.settings.staffRank or 0
    end
    return rank >= config.controlRank
end

function util.say(pid, message)
    if not util.isOnline(pid) then return end
    tes3mp.SendMessage(pid, color.Orange .. config.chatPrefix .. color.White .. message .. "\n", false)
end

function util.sayAll(message)
    for _, pid in ipairs(util.onlinePids()) do
        util.say(pid, message)
    end
end

function util.sayPids(pids, message)
    for _, pid in ipairs(pids) do
        util.say(pid, message)
    end
end

-- Move a player to a cell and position. The client answers with a cell change
-- packet, which keeps the server's copy of their location in sync.
function util.teleport(pid, cell, posX, posY, posZ, rotZ)
    if not util.isOnline(pid) then return end
    tes3mp.SetCell(pid, cell)
    tes3mp.SendCell(pid)
    tes3mp.SetPos(pid, posX or 0, posY or 0, posZ or 0)
    tes3mp.SetRot(pid, 0, rotZ or 0)
    tes3mp.SendPos(pid)
end

function util.teleportToSpot(pid, spot)
    util.teleport(pid, spot.cell, spot.posX, spot.posY, spot.posZ, spot.rotZ)
end

function util.formatDuration(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    local minutes = math.floor(seconds / 60)
    local rest = seconds - minutes * 60
    if minutes > 0 and rest > 0 then
        return string.format("%dm %02ds", minutes, rest)
    elseif minutes > 0 then
        return string.format("%dm", minutes)
    end
    return string.format("%ds", rest)
end

-- Snapshot a player's inventory as refId (lower-case) -> total count.
function util.inventoryCounts(pid)
    local counts = {}
    local player = Players[pid]
    if player == nil or player.data == nil or player.data.inventory == nil then
        return counts
    end
    for _, item in pairs(player.data.inventory) do
        if item ~= nil and item.refId ~= nil then
            local refId = util.lower(item.refId)
            local count = tonumber(item.count) or 1
            if count > 0 then
                counts[refId] = (counts[refId] or 0) + count
            end
        end
    end
    return counts
end

-- Items gained between two snapshots: refId -> count (only positive deltas).
function util.inventoryDelta(before, after)
    local delta = {}
    for refId, count in pairs(after) do
        local gained = count - (before[refId] or 0)
        if gained > 0 then
            delta[refId] = gained
        end
    end
    return delta
end

function util.parseExterior(cellDescription)
    local x, y = string.match(cellDescription or "", "^%s*(-?%d+)%s*,%s*(-?%d+)%s*$")
    if x == nil then return nil end
    return tonumber(x), tonumber(y)
end

function util.exteriorDescription(x, y)
    return tostring(x) .. ", " .. tostring(y)
end

function util.keys(t)
    local out = {}
    for k in pairs(t) do table.insert(out, k) end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

function util.count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function util.pick(array)
    if #array == 0 then return nil end
    return array[math.random(#array)]
end

-- Weighted pick: entries are { value = x, weight = w }.
function util.pickWeighted(entries)
    local total = 0
    for _, e in ipairs(entries) do total = total + e.weight end
    if total <= 0 then return nil end
    local roll = math.random() * total
    for _, e in ipairs(entries) do
        roll = roll - e.weight
        if roll <= 0 then return e.value end
    end
    return entries[#entries].value
end

-- Timers -----------------------------------------------------------------------
--
-- Never call tes3mp.FreeTimer. In TES3MP 0.8.1 (and the 0.51 port, which keeps
-- the same TimerAPI) FreeTimer leaves a null slot in the timer table, and every
-- CreateTimer made afterwards returns that slot's id while the real timer leaks.
-- StartTimer on it logs "Timer N not found!" and the timer never fires. That
-- silently kills our showcase timeout and CoreScripts' own death timer. So timers
-- are created once, stopped with StopTimer and re-armed with RestartTimer.

function util.stopTimer(id)
    if id == nil then return end
    pcall(tes3mp.StopTimer, id)
end

-- Arm a timer for `ms` milliseconds. Reuses `id` when it exists (RestartTimer),
-- otherwise creates one for `callback`, optionally with CreateTimerEx arguments
-- (`argTypes` is the TES3MP type string such as "i"). Returns the timer id.
-- Prefer to create timers outside timer callbacks: inserting into the timer table
-- while it is being ticked is not safe, re-arming an existing timer is.
function util.armTimer(id, callback, ms, argTypes, ...)
    ms = math.max(1, math.floor(ms))
    if id ~= nil then
        tes3mp.RestartTimer(id, ms)
        return id
    end
    if argTypes ~= nil then
        id = tes3mp.CreateTimerEx(callback, ms, argTypes, ...)
    else
        id = tes3mp.CreateTimer(callback, ms)
    end
    tes3mp.StartTimer(id)
    return id
end

-- Create a timer in the stopped state so a later armTimer only has to restart it.
function util.createStoppedTimer(callback, argTypes, ...)
    if argTypes ~= nil then
        return tes3mp.CreateTimerEx(callback, 1, argTypes, ...)
    end
    return tes3mp.CreateTimer(callback, 1)
end

return util
