-- Scavenger Scramble configuration.
-- Edit freely; every value here is read at server start.

local config = {}

-- Chat prefix used for every message the mode sends.
config.chatPrefix = "[Scramble] "

-- Minimum staff rank needed to control rounds (0 player, 1 moderator, 2 admin, 3 owner).
config.controlRank = 1

-- Default round length in real-time minutes. "/scramble start <minutes>" overrides it.
config.roundMinutes = 20

-- Seconds-left marks at which a countdown warning is broadcast.
config.countdownMarks = { 600, 300, 120, 60, 30, 10 }

-- How many objectives a round has, and how many of them are exact items.
-- The rest are category objectives ("any dagger").
config.objectiveCount = 3
config.exactItemCount = 1

-- Exact-item candidates must be worth at least this much gold and have at most
-- this many known instances in the location (rarer items make better hunts).
config.exactItemMinValue = 10
config.exactItemMaxInstances = 8

-- A category is only offered when the location has at least this many matching instances.
config.categoryMinInstances = 2

-- Item types that are never used as exact-item objectives.
config.exactItemExcludedTypes = { misc = false, light = true, lockpick = true, probe = true, repair = true }
config.exactItemExcludedSubtypes = { arrow = true, bolt = true, thrown = true }

-- Showcase cell and where players appear in it. Any interior works.
-- "/scramble showcase" in game overrides this and persists the new spot.
-- Default: the main hall of Nerano Manor, next to where Ondres Nerano stands.
config.showcase = {
    cell = "Balmora, Nerano Manor",
    posX = 915, posY = -70, posZ = 30, rotZ = 0,
}

-- Minutes allowed for laying out items before scoring runs regardless.
config.showcaseMinutes = 10

-- Bounds: seconds a player may be outside the location before being teleported back.
config.boundsGraceSeconds = 30

-- Exterior cells within this many grid cells of a named city cell count as in bounds.
-- Interiors outside the city are always out of bounds.
config.boundsPadding = 1

-- Reset the location's cells (loot, NPCs, containers) to pristine before each round.
config.resetCellsOnStart = true

-- Reset the showcase cell to pristine when the showcase phase begins, so
-- earlier displays and anything spawned there (hostile or not) are gone.
config.resetShowcaseCell = true

-- Players joining mid-round take part (true) or wait in the showcase cell (false).
config.allowLateJoin = true

-- Seconds after a resurrection before a dead player is returned to the round.
config.respawnReturnSeconds = 4

-- Locations that may be picked by "/scramble location random". Empty list = every generated
-- location with at least randomMinInteriors interiors (keeps camps, forts and ruins out of
-- random picks while still allowing them by name).
config.randomLocationPool = {}
config.randomMinInteriors = 8

-- Locations that are never picked (keys from data/locations.lua).
config.excludedLocations = {}

-- GUI ids (must not collide with other scripts).
config.gui = {
    objectives = 48101,
    scoreboard = 48102,
    locationList = 48103,
    minutesInput = 48104,
    status = 48105,
}

-- Files written under the server's data folder.
config.stateFile = "custom/scavenger_state.json"
config.historyFile = "custom/scavenger_history.json"

return config
