-- Location data access: generated city data, spawn points, bounds tests and cell resets.
--
-- Generated data is sharded: data/locations/index.lua lists every location,
-- data/locations/<key>.lua holds one location each and is loaded on demand.
-- (TES3MP embeds LuaJIT, which refuses a single chunk with more than 65536 constants.)

local config = require("custom.scavenger-scramble.config")
local util = require("custom.scavenger-scramble.util")

local locations = {}

locations.index = {}         -- array of { key, name, source, exteriors, interiors, knownItems }
locations.byKey = {}         -- key -> index entry
locations.orderedKeys = {}
locations.loaded = {}        -- key -> full location table (cache)
locations.overrides = {}

local function safeRequire(moduleName)
    local ok, result = pcall(require, moduleName)
    if ok and type(result) == "table" then
        return result
    end
    util.warn("Could not load " .. moduleName .. ": " .. tostring(result))
    return nil
end

function locations.load()
    locations.index = safeRequire("custom.scavenger-scramble.data.locations.index") or {}
    locations.overrides = safeRequire("custom.scavenger-scramble.data.spawn_overrides") or {}
    locations.byKey = {}
    locations.orderedKeys = {}
    locations.loaded = {}

    table.sort(locations.index, function(a, b) return (a.name or a.key) < (b.name or b.key) end)
    for _, entry in ipairs(locations.index) do
        locations.byKey[entry.key] = entry
        table.insert(locations.orderedKeys, entry.key)
    end

    util.log("Loaded index of " .. #locations.orderedKeys .. " locations")
end

local function prepare(key, loc)
    loc.key = key
    loc.exteriorSet = {}
    for _, desc in ipairs(loc.exteriors or {}) do
        loc.exteriorSet[desc] = true
    end
    loc.interiorSet = {}
    for _, desc in ipairs(loc.interiors or {}) do
        loc.interiorSet[desc] = true
    end
    loc.knownItems = loc.knownItems or {}
    return loc
end

-- Full location table, loaded from its shard on first use.
function locations.get(key)
    if key == nil then return nil end
    local cached = locations.loaded[key]
    if cached ~= nil then return cached end
    if locations.byKey[key] == nil then return nil end
    local loc = safeRequire("custom.scavenger-scramble.data.locations." .. key)
    if loc == nil then return nil end
    locations.loaded[key] = prepare(key, loc)
    return locations.loaded[key]
end

function locations.nameOf(key)
    local entry = locations.byKey[key]
    if entry ~= nil then return entry.name or key end
    return key
end

-- Resolve a user-typed name or number to a location key.
function locations.resolve(text)
    if text == nil then return nil end
    local index = tonumber(text)
    if index ~= nil then
        return locations.orderedKeys[index]
    end
    local typed = util.lower(text)
    local asKey = string.gsub(typed, "[%s%-']", "_")
    if locations.byKey[asKey] ~= nil then return asKey end
    for _, key in ipairs(locations.orderedKeys) do
        if util.lower(locations.nameOf(key)) == typed then return key end
    end
    -- Prefer names that start with the text, then names or keys that contain it.
    for _, key in ipairs(locations.orderedKeys) do
        if string.find(util.lower(locations.nameOf(key)), typed, 1, true) == 1 or string.find(key, asKey, 1, true) == 1 then
            return key
        end
    end
    for _, key in ipairs(locations.orderedKeys) do
        if string.find(util.lower(locations.nameOf(key)), typed, 1, true) or string.find(key, asKey, 1, true) then
            return key
        end
    end
    return nil
end

function locations.isExcluded(key)
    for _, excluded in ipairs(config.excludedLocations) do
        if excluded == key then return true end
    end
    return false
end

function locations.randomKey()
    local pool = {}
    if #config.randomLocationPool > 0 then
        for _, key in ipairs(config.randomLocationPool) do
            if locations.byKey[key] ~= nil and not locations.isExcluded(key) then
                table.insert(pool, key)
            end
        end
    else
        for _, key in ipairs(locations.orderedKeys) do
            local entry = locations.byKey[key]
            if not locations.isExcluded(key) and entry.spawnGuess ~= true
                and (entry.interiors or 0) >= (config.randomMinInteriors or 0) then
                table.insert(pool, key)
            end
        end
    end
    return util.pick(pool)
end

function locations.spawnOf(key)
    local override = locations.overrides[key]
    if override ~= nil and override.cell ~= nil then
        return override
    end
    local loc = locations.get(key)
    if loc == nil then return nil end
    return loc.spawn
end

-- True when the cell is part of the location (or within the padding ring of its exteriors).
function locations.isInBounds(key, cellDescription)
    local loc = locations.get(key)
    if loc == nil or cellDescription == nil then return true end
    if loc.interiorSet[cellDescription] or loc.exteriorSet[cellDescription] then
        return true
    end
    local x, y = util.parseExterior(cellDescription)
    if x == nil then
        return false
    end
    local padding = config.boundsPadding or 0
    if padding <= 0 then return false end
    for dx = -padding, padding do
        for dy = -padding, padding do
            if loc.exteriorSet[util.exteriorDescription(x + dx, y + dy)] then
                return true
            end
        end
    end
    return false
end

function locations.allCells(key)
    local loc = locations.get(key)
    local cells = {}
    if loc == nil then return cells end
    for _, desc in ipairs(loc.exteriors or {}) do table.insert(cells, desc) end
    for _, desc in ipairs(loc.interiors or {}) do table.insert(cells, desc) end
    return cells
end

-- Reset a list of cells to pristine. Mirrors logicHandler.ResetCell
-- (CoreScripts 0.8.1) but without per-cell chat spam and with one reset packet.
function locations.resetCellList(cells, label)
    local resetCount = 0
    local anyPid = util.anyPid()

    if anyPid ~= nil then
        tes3mp.ClearCellsToReset()
    end

    for _, cellDescription in ipairs(cells) do
        local wasLoaded = LoadedCells[cellDescription] ~= nil
        local hasEntry = wasLoaded or Cell(cellDescription):HasEntry()

        if hasEntry then
            if not wasLoaded then
                logicHandler.LoadCell(cellDescription)
            end

            local cell = LoadedCells[cellDescription]
            cell.isResetting = true
            cell.data.objectData = {}
            cell.data.packets = {}
            cell:EnsurePacketTables()
            cell.data.loadState.hasFullActorList = false
            cell.data.loadState.hasFullContainerData = false
            cell:ClearRecordLinks()

            if not wasLoaded then
                logicHandler.UnloadCell(cellDescription)
            else
                cell:QuicksaveToDrive()
            end

            if anyPid ~= nil then
                tes3mp.AddCellToReset(cellDescription)
            end
            resetCount = resetCount + 1
        end
    end

    if anyPid ~= nil and resetCount > 0 then
        tes3mp.SendCellReset(anyPid, true)
    end

    for _, cellDescription in ipairs(cells) do
        if LoadedCells[cellDescription] ~= nil then
            LoadedCells[cellDescription].isResetting = false
        end
    end

    util.log("Reset " .. resetCount .. " of " .. #cells .. " cells for " .. tostring(label))
    return resetCount
end

-- Reset every cell of a location.
function locations.resetCells(key)
    return locations.resetCellList(locations.allCells(key), key)
end

function locations.describe(key)
    local loc = locations.get(key)
    if loc == nil then return "unknown location" end
    return string.format("%s (%d exterior cells, %d interiors, %d known items)",
        loc.name or key, #(loc.exteriors or {}), #(loc.interiors or {}), util.count(loc.knownItems or {}))
end

return locations
