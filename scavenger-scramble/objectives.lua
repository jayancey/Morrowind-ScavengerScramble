-- Objective rolling and item matching.
--
-- An objective is either
--   { kind = "item", refId = "steel dagger", name = "Steel Dagger", value = 30 }
-- or
--   { kind = "category", id = "shortblade", name = "Any short blade" }

local config = require("custom.scavenger-scramble.config")
local util = require("custom.scavenger-scramble.util")

local objectives = {}

objectives.items = {}
objectives.categories = {}
objectives.categoryById = {}

function objectives.load()
    local ok, items = pcall(require, "custom.scavenger-scramble.data.items")
    if ok and type(items) == "table" then
        objectives.items = items
    else
        objectives.items = {}
        util.warn("Could not load data/items.lua: " .. tostring(items))
    end

    local okCat, categories = pcall(require, "custom.scavenger-scramble.data.categories")
    if okCat and type(categories) == "table" then
        objectives.categories = categories
    else
        objectives.categories = {}
        util.warn("Could not load data/categories.lua: " .. tostring(categories))
    end

    objectives.categoryById = {}
    for _, category in ipairs(objectives.categories) do
        objectives.categoryById[category.id] = category
    end

    util.log("Loaded " .. util.count(objectives.items) .. " items and " .. #objectives.categories .. " categories")
end

function objectives.item(refId)
    return objectives.items[util.lower(refId)]
end

function objectives.itemName(refId)
    local item = objectives.item(refId)
    if item ~= nil and item.name ~= nil and item.name ~= "" then
        return item.name
    end
    return refId
end

function objectives.itemValue(refId)
    local item = objectives.item(refId)
    if item == nil then return 0 end
    return item.value or 0
end

-- Does a given item refId satisfy an objective?
function objectives.matches(objective, refId)
    refId = util.lower(refId)
    if objective.kind == "item" then
        return refId == objective.refId
    end
    local item = objectives.items[refId]
    if item == nil then return false end
    local category = objectives.categoryById[objective.id]
    if category == nil then return false end
    return category.match(item) == true
end

local function exactCandidates(location)
    local candidates = {}
    for refId, known in pairs(location.knownItems or {}) do
        local item = objectives.items[refId]
        if item ~= nil
            and (item.value or 0) >= config.exactItemMinValue
            and (known.count or 0) >= 1
            and (known.count or 0) <= config.exactItemMaxInstances
            and config.exactItemExcludedTypes[item.type] ~= true
            and config.exactItemExcludedSubtypes[item.subtype] ~= true
            and item.name ~= nil and item.name ~= "" then
            -- Rarer items weigh more, but a single instance is weighted below
            -- two or three so most hunts stay findable.
            local count = known.count
            local weight = 1 / count
            if count == 1 then weight = 0.6 end
            table.insert(candidates, { value = refId, weight = weight })
        end
    end
    return candidates
end

local function categoryCandidates(location)
    local candidates = {}
    for _, category in ipairs(objectives.categories) do
        local instances = 0
        for refId, known in pairs(location.knownItems or {}) do
            local item = objectives.items[refId]
            if item ~= nil and category.match(item) then
                instances = instances + (known.count or 0)
            end
        end
        if instances >= config.categoryMinInstances then
            table.insert(candidates, { value = category.id, weight = 1 })
        end
    end
    return candidates
end

-- Roll a full objective list for a location. Returns an array of objectives.
function objectives.roll(location, objectiveCount, exactItemCount)
    objectiveCount = objectiveCount or config.objectiveCount
    exactItemCount = math.min(exactItemCount or config.exactItemCount, objectiveCount)

    local rolled = {}
    local usedCategories = {}

    local exacts = exactCandidates(location)
    for _ = 1, exactItemCount do
        local refId = util.pickWeighted(exacts)
        if refId == nil then break end
        for i = #exacts, 1, -1 do
            if exacts[i].value == refId then table.remove(exacts, i) end
        end
        table.insert(rolled, {
            kind = "item",
            refId = refId,
            name = objectives.itemName(refId),
            value = objectives.itemValue(refId),
        })
    end

    local categories = categoryCandidates(location)
    while #rolled < objectiveCount and #categories > 0 do
        local categoryId = util.pickWeighted(categories)
        for i = #categories, 1, -1 do
            if categories[i].value == categoryId then table.remove(categories, i) end
        end
        if not usedCategories[categoryId] then
            usedCategories[categoryId] = true
            table.insert(rolled, {
                kind = "category",
                id = categoryId,
                name = objectives.categoryById[categoryId].name,
            })
        end
    end

    -- If categories ran dry, fill with more exact items.
    while #rolled < objectiveCount and #exacts > 0 do
        local refId = util.pickWeighted(exacts)
        for i = #exacts, 1, -1 do
            if exacts[i].value == refId then table.remove(exacts, i) end
        end
        table.insert(rolled, {
            kind = "item",
            refId = refId,
            name = objectives.itemName(refId),
            value = objectives.itemValue(refId),
        })
    end

    return rolled
end

function objectives.describe(objective, index)
    local prefix = ""
    if index ~= nil then prefix = tostring(index) .. ". " end
    if objective.kind == "item" then
        return string.format("%s%s (exact item, worth %d gold)", prefix, objective.name, objective.value or 0)
    end
    return prefix .. objective.name
end

return objectives
