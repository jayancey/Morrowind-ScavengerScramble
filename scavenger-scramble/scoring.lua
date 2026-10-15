-- Scoring: checklist points plus a best-in-category bonus.
--
-- Input per player: the list of displayed items { refId, count, value }.
-- Each displayed item instance can be credited to at most one objective.
-- The assignment that satisfies the most objectives wins; ties prefer the
-- assignment with the highest total credited value.

local objectives = require("custom.scavenger-scramble.objectives")
local util = require("custom.scavenger-scramble.util")

local scoring = {}

-- Expand stacks into individual instances so a stack of 5 arrows can serve
-- several objectives if needed.
local function expand(displayed)
    local instances = {}
    for _, entry in ipairs(displayed) do
        local count = math.min(entry.count or 1, 20)
        for _ = 1, count do
            table.insert(instances, { refId = util.lower(entry.refId), value = entry.value or objectives.itemValue(entry.refId) })
        end
    end
    return instances
end

-- Backtracking search over objective -> instance assignments.
local function bestAssignment(objectiveList, instances)
    local best = { satisfied = 0, value = 0, credited = {} }
    local used = {}
    local credited = {}

    local function better(satisfied, value)
        if satisfied > best.satisfied then return true end
        if satisfied == best.satisfied and value > best.value then return true end
        return false
    end

    local function recurse(index, satisfied, value)
        if index > #objectiveList then
            if better(satisfied, value) then
                best.satisfied = satisfied
                best.value = value
                best.credited = {}
                for k, v in pairs(credited) do best.credited[k] = v end
            end
            return
        end
        -- Upper bound pruning.
        local remaining = #objectiveList - index + 1
        if satisfied + remaining < best.satisfied then return end

        local objective = objectiveList[index]
        local seen = {}
        for i, instance in ipairs(instances) do
            if not used[i] and not seen[instance.refId] and objectives.matches(objective, instance.refId) then
                seen[instance.refId] = true
                used[i] = true
                credited[index] = { refId = instance.refId, value = instance.value }
                recurse(index + 1, satisfied + 1, value + instance.value)
                credited[index] = nil
                used[i] = false
            end
        end
        -- Skip this objective.
        recurse(index + 1, satisfied, value)
    end

    recurse(1, 0, 0)
    return best
end

-- participants: { [account] = { name = "...", displayed = { {refId, count, value}, ... }, doneAt = os.time or nil } }
-- Returns an array of result rows sorted best first.
function scoring.compute(objectiveList, participants)
    local rows = {}

    for account, participant in pairs(participants) do
        local assignment = bestAssignment(objectiveList, expand(participant.displayed or {}))
        local row = {
            account = account,
            name = participant.name or account,
            credited = assignment.credited,
            points = assignment.satisfied,
            bonus = 0,
            bonusFor = {},
            totalValue = assignment.value,
            doneAt = participant.doneAt,
        }
        table.insert(rows, row)
    end

    -- Best-in-category bonus.
    for index, objective in ipairs(objectiveList) do
        if objective.kind == "category" then
            local bestValue = nil
            for _, row in ipairs(rows) do
                local credit = row.credited[index]
                if credit ~= nil and (bestValue == nil or credit.value > bestValue) then
                    bestValue = credit.value
                end
            end
            if bestValue ~= nil then
                for _, row in ipairs(rows) do
                    local credit = row.credited[index]
                    if credit ~= nil and credit.value == bestValue then
                        row.bonus = row.bonus + 1
                        table.insert(row.bonusFor, index)
                    end
                end
            end
        end
    end

    for _, row in ipairs(rows) do
        row.score = row.points + row.bonus
    end

    table.sort(rows, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.totalValue ~= b.totalValue then return a.totalValue > b.totalValue end
        local aDone = a.doneAt or math.huge
        local bDone = b.doneAt or math.huge
        if aDone ~= bDone then return aDone < bDone end
        return a.name < b.name
    end)

    for i, row in ipairs(rows) do
        row.rank = i
        row.tiedWithWinner = (i > 1 and row.score == rows[1].score
            and row.totalValue == rows[1].totalValue and (row.doneAt or math.huge) == (rows[1].doneAt or math.huge))
    end

    return rows
end

-- Human-readable summary lines for a result row.
function scoring.describeRow(row, objectiveList)
    local parts = {}
    for index, objective in ipairs(objectiveList) do
        local credit = row.credited[index]
        local mark
        if credit ~= nil then
            mark = objectives.itemName(credit.refId) .. " (" .. tostring(credit.value) .. "g)"
            for _, bonusIndex in ipairs(row.bonusFor) do
                if bonusIndex == index then mark = mark .. " +best" end
            end
        else
            mark = "missed"
        end
        table.insert(parts, string.format("%d: %s", index, mark))
    end
    return string.format("%s - %d pts (%d found, %d bonus) | %s",
        row.name, row.score, row.points, row.bonus, table.concat(parts, "; "))
end

return scoring
