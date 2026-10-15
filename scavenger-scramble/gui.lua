-- Message boxes and list boxes.

local config = require("custom.scavenger-scramble.config")
local util = require("custom.scavenger-scramble.util")
local state = require("custom.scavenger-scramble.state")
local locations = require("custom.scavenger-scramble.locations")
local scoring = require("custom.scavenger-scramble.scoring")

local gui = {}

function gui.showObjectives(pid)
    local current = state.current
    if current.phase == "idle" or not util.isOnline(pid) then return end
    local lines = { "Scavenger Scramble - " .. tostring(current.locationName), "" }
    for _, line in ipairs(Scramble.round.objectiveLines()) do
        table.insert(lines, line)
    end
    table.insert(lines, "")
    if current.phase == "scramble" then
        table.insert(lines, "Time: " .. tostring(current.lengthMinutes) .. " minutes. Hold your finds when time runs out.")
        table.insert(lines, "Stay inside " .. tostring(current.locationName) .. ".")
    else
        table.insert(lines, "Drop your finds here and type /scramble done.")
    end
    tes3mp.CustomMessageBox(pid, config.gui.objectives, table.concat(lines, "\n"), "Ok")
end

function gui.showScoreboard(pid, rows, objectiveList, locationName)
    if not util.isOnline(pid) then return end
    local lines = { "Scavenger Scramble results - " .. tostring(locationName), "" }
    for i, objective in ipairs(objectiveList) do
        table.insert(lines, tostring(i) .. ". " .. objective.name)
    end
    table.insert(lines, "")
    for _, row in ipairs(rows) do
        table.insert(lines, string.format("#%d  %s", row.rank, scoring.describeRow(row, objectiveList)))
    end
    if #rows == 0 then
        table.insert(lines, "No participants.")
    end
    tes3mp.CustomMessageBox(pid, config.gui.scoreboard, table.concat(lines, "\n"), "Ok")
end

function gui.showLocationList(pid)
    if not util.isOnline(pid) then return end
    local items = {}
    for i, key in ipairs(locations.orderedKeys) do
        local entry = locations.byKey[key]
        local marker = ""
        if state.current.nextLocation == key then marker = " [next]" end
        table.insert(items, string.format("%d. %s (%d interiors)%s", i, entry.name or key, entry.interiors or 0, marker))
    end
    table.insert(items, "Random")
    tes3mp.ListBox(pid, config.gui.locationList, "Choose the next Scramble location", table.concat(items, "\n"))
end

function gui.showStatus(pid)
    if not util.isOnline(pid) then return end
    local current = state.current
    local lines = {}
    if current.phase == "idle" then
        table.insert(lines, "No round running.")
        local nextKey = current.nextLocation
        if nextKey == nil or nextKey == "random" then
            table.insert(lines, "Next location: random")
        else
            table.insert(lines, "Next location: " .. locations.nameOf(nextKey))
        end
        if current.lastResults ~= nil then
            table.insert(lines, "Last round: " .. tostring(current.lastResults.location))
            for _, row in ipairs(current.lastResults.rows or {}) do
                table.insert(lines, string.format("  #%d %s - %d pts", row.rank, row.name, row.score))
            end
        end
    else
        table.insert(lines, "Phase: " .. current.phase .. " in " .. tostring(current.locationName))
        table.insert(lines, "Time left: " .. util.formatDuration(Scramble.round.timeLeft()))
        table.insert(lines, "Participants:")
        for account, participant in pairs(current.participants) do
            local online = util.pidOfAccount(account) ~= nil and "" or " (offline)"
            local done = ""
            if current.phase == "showcase" then
                done = participant.done and " done" or " placing"
            end
            table.insert(lines, "  " .. (participant.name or account) .. online .. done)
        end
    end
    for _, line in ipairs(lines) do util.say(pid, line) end
end

function gui.onGUIAction(eventStatus, pid, idGui, data)
    if idGui == config.gui.locationList then
        if not util.hasControl(pid) then return end
        local index = tonumber(data)
        if index == nil or index < 0 then return end
        index = index + 1
        if index == #locations.orderedKeys + 1 then
            state.current.nextLocation = "random"
            state.save()
            util.sayAll("Next Scramble location: random.")
        elseif locations.orderedKeys[index] ~= nil then
            local key = locations.orderedKeys[index]
            state.current.nextLocation = key
            state.save()
            util.sayAll("Next Scramble location: " .. locations.nameOf(key) .. ".")
        end
    elseif idGui == config.gui.minutesInput then
        if not util.hasControl(pid) then return end
        local minutes = tonumber(data)
        if minutes ~= nil and minutes >= 1 then
            config.roundMinutes = math.floor(minutes)
            util.sayAll("Default round length set to " .. config.roundMinutes .. " minutes.")
        else
            util.say(pid, "Not a valid number of minutes.")
        end
    end
end

return gui
