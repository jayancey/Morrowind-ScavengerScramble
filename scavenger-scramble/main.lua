-- Scavenger Scramble: a scavenger-hunt game mode for TES3MP.
--
-- Load it from scripts/customScripts.lua with:
--   require("custom.scavenger-scramble.main")

Scramble = Scramble or {}

local config = require("custom.scavenger-scramble.config")
local util = require("custom.scavenger-scramble.util")

Scramble.config = config
Scramble.util = util
Scramble.state = require("custom.scavenger-scramble.state")
Scramble.locations = require("custom.scavenger-scramble.locations")
Scramble.objectives = require("custom.scavenger-scramble.objectives")
Scramble.scoring = require("custom.scavenger-scramble.scoring")
Scramble.round = require("custom.scavenger-scramble.round")
Scramble.bounds = require("custom.scavenger-scramble.bounds")
Scramble.showcase = require("custom.scavenger-scramble.showcase")
Scramble.gui = require("custom.scavenger-scramble.gui")
Scramble.commands = require("custom.scavenger-scramble.commands")

math.randomseed(os.time())

local function onServerPostInit(eventStatus)
    Scramble.objectives.load()
    Scramble.locations.load()
    Scramble.state.load()
    Scramble.round.resume()
    util.log("Scavenger Scramble ready. Phase: " .. Scramble.state.phase())
end

local function onPlayerAuthentified(eventStatus, pid)
    local ok, err = pcall(Scramble.round.onAuthentified, pid)
    if not ok then util.warn("onAuthentified failed: " .. tostring(err)) end
end

local function onPlayerDisconnect(eventStatus, pid)
    Scramble.bounds.onDisconnect(pid)
    Scramble.round.onDisconnect(pid)
end

local function onPlayerResurrect(eventStatus, pid)
    local ok, err = pcall(Scramble.round.onResurrect, pid)
    if not ok then util.warn("onResurrect failed: " .. tostring(err)) end
end

local function onPlayerCellChange(eventStatus, pid, playerPacket, previousCellDescription)
    local ok, err = pcall(Scramble.bounds.onCellChange, eventStatus, pid, playerPacket, previousCellDescription)
    if not ok then util.warn("onCellChange failed: " .. tostring(err)) end
end

local function onObjectPlace(eventStatus, pid, cellDescription, objects, targetPlayers)
    local ok, err = pcall(Scramble.showcase.onObjectPlace, eventStatus, pid, cellDescription, objects, targetPlayers)
    if not ok then util.warn("onObjectPlace failed: " .. tostring(err)) end
end

local function onObjectDelete(eventStatus, pid, cellDescription, objects, targetPlayers)
    local ok, err = pcall(Scramble.showcase.onObjectDelete, eventStatus, pid, cellDescription, objects, targetPlayers)
    if not ok then util.warn("onObjectDelete failed: " .. tostring(err)) end
end

local function onGUIAction(eventStatus, pid, idGui, data)
    local ok, err = pcall(Scramble.gui.onGUIAction, eventStatus, pid, idGui, data)
    if not ok then util.warn("onGUIAction failed: " .. tostring(err)) end
end

customEventHooks.registerHandler("OnServerPostInit", onServerPostInit)
customEventHooks.registerHandler("OnPlayerAuthentified", onPlayerAuthentified)
customEventHooks.registerHandler("OnPlayerDisconnect", onPlayerDisconnect)
customEventHooks.registerHandler("OnPlayerResurrect", onPlayerResurrect)
customEventHooks.registerHandler("OnPlayerCellChange", onPlayerCellChange)
customEventHooks.registerHandler("OnObjectPlace", onObjectPlace)
customEventHooks.registerHandler("OnObjectDelete", onObjectDelete)
customEventHooks.registerHandler("OnGUIAction", onGUIAction)

Scramble.commands.register()

return Scramble
