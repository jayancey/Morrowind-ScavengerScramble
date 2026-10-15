-- Behavioural tests for Scavenger Scramble, run by tests/run_tests.py under LuaJIT.
-- Globals provided by the runner: ROOT (repo path), stubs (tests/stubs.lua).

local passed, failed = 0, 0
local failures = {}

local function check(condition, message)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        table.insert(failures, message or "assertion failed")
        io.write("FAIL: " .. tostring(message or "assertion failed") .. "\n")
    end
end

local function eq(actual, expected, message)
    check(actual == expected, (message or "") .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
end

local function section(name)
    io.write("\n== " .. name .. "\n")
end

-- Fresh module instances for every scenario.
local function reloadMod()
    for name in pairs(package.loaded) do
        if string.find(name, "^custom%.scavenger%-scramble") then
            package.loaded[name] = nil
        end
    end
    Scramble = nil
    customEventHooks.handlers = {}
    customCommandHooks.commands = {}
    Players = {}
    LoadedCells = {}
    stubs.jsonStore = {}
    stubs.cellEntries = {}
    stubs.reset()
    stubs.clearTimers()
    local mod = require("custom.scavenger-scramble.main")
    customEventHooks.fire("OnServerPostInit")
    return mod
end

-------------------------------------------------------------------------------
section("module loads and registers")
do
    local mod = reloadMod()
    check(mod ~= nil and mod.round ~= nil, "main returns the registry")
    check(customCommandHooks.commands["scramble"] ~= nil, "/scramble registered")
    check(customEventHooks.handlers["OnObjectPlace"] ~= nil, "OnObjectPlace handler registered")
    eq(#mod.locations.orderedKeys, 2, "two fixture locations indexed")
    eq(mod.state.phase(), "idle", "starts idle")
    eq(mod.objectives.item("Steel Dagger").value, 30, "item lookup is case-insensitive")
end

-------------------------------------------------------------------------------
section("objective matching and rolling")
do
    local mod = reloadMod()
    local objectives = mod.objectives
    check(objectives.matches({ kind = "item", refId = "steel dagger" }, "Steel Dagger"), "exact item matches ignoring case")
    check(not objectives.matches({ kind = "item", refId = "steel dagger" }, "iron dagger"), "exact item rejects other")
    check(objectives.matches({ kind = "category", id = "shortblade" }, "iron dagger"), "category matches")
    check(not objectives.matches({ kind = "category", id = "shortblade" }, "steel longsword"), "category rejects")
    check(objectives.matches({ kind = "category", id = "worth500" }, "exquisite_ring_01"), "value tier matches")
    check(objectives.matches({ kind = "category", id = "enchanted" }, "ring_of_fire"), "enchanted matches")
    check(not objectives.matches({ kind = "category", id = "enchanted" }, "unknown_item"), "unknown item never matches")

    local location = mod.locations.get("testville")
    check(location ~= nil and location.exteriorSet["-3, -2"], "shard loaded with exterior set")

    for trial = 1, 25 do
        local rolled = objectives.roll(location, 3, 1)
        eq(#rolled, 3, "roll gives 3 objectives")
        local exacts, categories, ids = 0, 0, {}
        for _, objective in ipairs(rolled) do
            if objective.kind == "item" then
                exacts = exacts + 1
                check(location.knownItems[objective.refId] ~= nil, "exact item exists in location")
                check(location.knownItems[objective.refId].count <= mod.config.exactItemMaxInstances, "exact item not too common")
                check(objective.refId ~= "iron arrow", "arrows never exact")
                check(objective.refId ~= "ingred_bread_01", "cheap items never exact")
            else
                categories = categories + 1
                check(not ids[objective.id], "no duplicate categories")
                ids[objective.id] = true
            end
        end
        eq(exacts, 1, "one exact item")
        eq(categories, 2, "two categories")
    end

    local empty = mod.locations.get("emptyton")
    eq(#objectives.roll(empty, 3, 1), 0, "empty location rolls nothing")
end

-------------------------------------------------------------------------------
section("scoring")
do
    local mod = reloadMod()
    local scoring = mod.scoring
    local objectiveList = {
        { kind = "item", refId = "steel dagger", name = "Steel Dagger" },
        { kind = "category", id = "shortblade", name = "Any short blade" },
        { kind = "category", id = "ring", name = "Any ring" },
    }
    local participants = {
        alice = { name = "Alice", displayed = {
            { refId = "steel dagger", count = 1, value = 30 },
            { refId = "iron dagger", count = 1, value = 10 },
            { refId = "common_ring_01", count = 1, value = 5 },
        }, doneAt = 100 },
        bob = { name = "Bob", displayed = {
            { refId = "glass dagger", count = 1, value = 1000 },
            { refId = "exquisite_ring_01", count = 1, value = 5000 },
        }, doneAt = 90 },
        carol = { name = "Carol", displayed = {}, doneAt = nil },
    }
    local rows = scoring.compute(objectiveList, participants)
    eq(#rows, 3, "three rows")
    local byName = {}
    for _, row in ipairs(rows) do byName[row.name] = row end
    eq(byName.Alice.points, 3, "Alice satisfies all three")
    eq(byName.Alice.bonus, 0, "Alice gets no bonus")
    eq(byName.Bob.points, 2, "Bob satisfies two")
    eq(byName.Bob.bonus, 2, "Bob best in both categories")
    eq(byName.Bob.score, 4, "Bob total 4")
    eq(byName.Alice.score, 3, "Alice total 3")
    eq(rows[1].name, "Bob", "Bob wins")
    eq(rows[3].name, "Carol", "Carol last")
    eq(byName.Carol.score, 0, "Carol scores zero")
    check(byName.Alice.credited[1].refId == "steel dagger", "exact objective credited with the steel dagger")
    check(byName.Alice.credited[2].refId == "iron dagger", "short blade credited with the other dagger")

    -- One item cannot serve two objectives.
    local rows2 = scoring.compute(objectiveList, { dave = { name = "Dave", displayed = { { refId = "steel dagger", count = 1, value = 30 } } } })
    eq(rows2[1].points, 1, "a single dagger counts once")

    -- A stack can serve two objectives.
    local rows3 = scoring.compute(objectiveList, { eve = { name = "Eve", displayed = { { refId = "steel dagger", count = 2, value = 30 } } } })
    eq(rows3[1].points, 2, "two daggers count twice")

    -- Tie: same score and value, earlier done wins; equal everything ties.
    local tieObjectives = { { kind = "category", id = "potion", name = "Any potion" } }
    local tieRows = scoring.compute(tieObjectives, {
        x = { name = "X", displayed = { { refId = "p_restore_health_c", count = 1, value = 15 } }, doneAt = 50 },
        y = { name = "Y", displayed = { { refId = "p_restore_health_c", count = 1, value = 15 } }, doneAt = 40 },
    })
    eq(tieRows[1].name, "Y", "earlier done breaks ties")
    check(tieRows[1].bonus == 1 and tieRows[2].bonus == 1, "shared best-value bonus")
    local tieRows2 = scoring.compute(tieObjectives, {
        x = { name = "X", displayed = { { refId = "p_restore_health_c", count = 1, value = 15 } }, doneAt = 50 },
        y = { name = "Y", displayed = { { refId = "p_restore_health_c", count = 1, value = 15 } }, doneAt = 50 },
    })
    check(tieRows2[2].tiedWithWinner, "identical rows tie with the winner")
end

-------------------------------------------------------------------------------
section("full round flow")
do
    local mod = reloadMod()
    local state = mod.state
    stubs.addPlayer(0, "Admin", 2, { { refId = "gold_001", count = 50 }, { refId = "iron dagger", count = 1 } })
    stubs.addPlayer(1, "Bob", 0, {})
    stubs.addPlayer(2, "Carol", 0, {})
    stubs.cellEntries["Testville, Hut"] = true
    stubs.cellEntries["-3, -2"] = true
    stubs.cellEntries["Balmora, Nerano Manor"] = true

    customCommandHooks.run(1, "scramble start")
    eq(state.phase(), "idle", "non-staff cannot start")
    check(#stubs.chatContaining("staff rank") == 1, "non-staff told about rank")

    customCommandHooks.run(0, "scramble location testville")
    eq(state.current.nextLocation, "testville", "location chosen")
    customCommandHooks.run(0, "scramble start 2")
    eq(state.phase(), "scramble", "round started")
    eq(state.current.locationKey, "testville", "round uses chosen location")
    eq(state.current.lengthMinutes, 2, "length from argument")
    eq(#state.current.objectives, 3, "objectives rolled")
    eq(state.participantCount(), 3, "all online players participate")
    for pid = 0, 2 do
        local tp = stubs.lastTeleport(pid)
        check(tp ~= nil and tp.cell == "-3, -2" and tp.x == -20000, "player " .. pid .. " teleported to spawn")
    end
    eq(#stubs.timersNamed("Scramble_OnRoundEnd"), 1, "round end timer armed")
    check(#stubs.timersNamed("Scramble_OnCountdown") >= 2, "countdown timers armed")
    eq(stubs.cellReset.sent, 1, "one cell reset packet sent")
    eq(#stubs.cellReset.added, 2, "two cells with entries were reset")
    check(#stubs.boxes >= 3, "objective boxes shown")
    check(state.participant("Admin").startInventory["iron dagger"] == 1, "start inventory snapshotted")
    check(stubs.jsonStore["custom/scavenger_state.json"] ~= nil, "state persisted")

    -- Bounds: Bob wanders out.
    stubs.reset()
    customEventHooks.fire("OnPlayerCellChange", 1, { location = { cell = "Testville, Hut" } }, "-3, -2")
    eq(#stubs.timersNamed("Scramble_OnGraceExpired"), 0, "interior in bounds")
    customEventHooks.fire("OnPlayerCellChange", 1, { location = { cell = "-4, -3" } }, "-3, -2")
    eq(#stubs.timersNamed("Scramble_OnGraceExpired"), 0, "padded exterior in bounds")
    customEventHooks.fire("OnPlayerCellChange", 1, { location = { cell = "5, 5" } }, "-3, -2")
    eq(#stubs.timersNamed("Scramble_OnGraceExpired"), 1, "far exterior starts grace")
    customEventHooks.fire("OnPlayerCellChange", 1, { location = { cell = "Caldera, Guild of Mages" } }, "5, 5")
    eq(#stubs.timersNamed("Scramble_OnGraceExpired"), 1, "no duplicate grace timer")
    customEventHooks.fire("OnPlayerCellChange", 1, { location = { cell = "-3, -3" } }, "Caldera, Guild of Mages")
    eq(#stubs.timersNamed("Scramble_OnGraceExpired"), 0, "returning cancels grace")
    customEventHooks.fire("OnPlayerCellChange", 1, { location = { cell = "5, 5" } }, "-3, -3")
    stubs.playerCells[1] = "5, 5"
    stubs.fireTimers("Scramble_OnGraceExpired")
    local tp = stubs.lastTeleport(1)
    check(tp ~= nil and tp.cell == "-3, -2", "grace expiry teleports back")

    -- Late joiner.
    stubs.addPlayer(3, "Dave", 0, {})
    customEventHooks.fire("OnPlayerAuthentified", 3)
    eq(state.participantCount(), 4, "late joiner added")
    check(stubs.lastTeleport(3) ~= nil, "late joiner teleported")

    -- Death during the round.
    stubs.reset()
    customEventHooks.fire("OnPlayerResurrect", 2)
    eq(#stubs.timersNamed("Scramble_OnRespawnReturn"), 1, "respawn return timer armed")
    stubs.fireTimers("Scramble_OnRespawnReturn")
    check(stubs.lastTeleport(2) ~= nil and stubs.lastTeleport(2).cell == "-3, -2", "dead player returned to spawn")

    -- Players loot. Admin already had an iron dagger: only new ones count.
    stubs.giveItem(0, "Iron Dagger", 1)
    stubs.giveItem(0, "steel dagger", 1)
    stubs.giveItem(1, "glass dagger", 1)
    stubs.giveItem(1, "exquisite_ring_01", 1)
    stubs.giveItem(2, "misc_com_bottle_01", 3)

    -- Carol disconnects before the end.
    stubs.removePlayer(2)

    stubs.reset()
    stubs.cellReset = { cleared = 0, added = {}, sent = 0 }
    stubs.fireTimers("Scramble_OnRoundEnd")
    eq(#stubs.cellReset.added, 1, "showcase cell reset at showcase start")
    eq(stubs.cellReset.added[1], "Balmora, Nerano Manor", "reset targets the showcase cell")
    eq(state.phase(), "showcase", "showcase phase after timer")
    eq(state.participant("Admin").acquired["iron dagger"], 1, "only the new iron dagger counts")
    eq(state.participant("Admin").acquired["steel dagger"], 1, "steel dagger acquired")
    eq(state.participant("Admin").acquired["gold_001"], nil, "pre-owned gold ignored")
    eq(state.participant("Bob").acquired["glass dagger"], 1, "Bob's dagger acquired")
    check(next(state.participant("Carol").acquired) == nil, "offline participant has nothing")
    for _, pid in ipairs({ 0, 1, 3 }) do
        local t = stubs.lastTeleport(pid)
        check(t ~= nil and t.cell == mod.config.showcase.cell, "player " .. pid .. " moved to showcase")
    end
    eq(#stubs.timersNamed("Scramble_OnShowcaseTimeout"), 1, "showcase timeout armed")

    -- Showcase placements.
    local showcaseCell = mod.config.showcase.cell
    customEventHooks.fire("OnObjectPlace", 0, showcaseCell, { ["0-1"] = { refId = "Steel Dagger", count = 1, droppedByPlayer = true } }, {})
    check(state.participant("Admin").displayed["0-1"] ~= nil, "placed item credited")
    customEventHooks.fire("OnObjectPlace", 0, showcaseCell, { ["0-2"] = { refId = "gold_001", count = 10 } }, {})
    check(state.participant("Admin").displayed["0-2"] == nil, "pre-owned item not credited")
    check(#stubs.chatContaining("not acquired") == 1, "player told the item does not count")
    customEventHooks.fire("OnObjectPlace", 0, "Balmora, Guild of Mages", { ["0-3"] = { refId = "iron dagger", count = 1 } }, {})
    check(state.participant("Admin").displayed["0-3"] == nil, "drops outside the showcase cell ignored")
    customEventHooks.fire("OnObjectPlace", 0, showcaseCell, { ["0-4"] = { refId = "iron dagger", count = 1 } }, {})
    customEventHooks.fire("OnObjectPlace", 0, showcaseCell, { ["0-5"] = { refId = "iron dagger", count = 1 } }, {})
    check(state.participant("Admin").displayed["0-4"] ~= nil and state.participant("Admin").displayed["0-5"] == nil, "cannot display more than acquired")

    customEventHooks.fire("OnObjectPlace", 1, showcaseCell, { ["0-6"] = { refId = "glass dagger", count = 1 } }, {})
    customEventHooks.fire("OnObjectPlace", 1, showcaseCell, { ["0-7"] = { refId = "exquisite_ring_01", count = 1 } }, {})
    -- Admin steals Bob's ring from the display.
    customEventHooks.fire("OnObjectDelete", 0, showcaseCell, { ["0-7"] = { refId = "exquisite_ring_01" } }, {})
    check(state.participant("Bob").displayed["0-7"] == nil, "picked-up item removed from display")
    check(#stubs.chatContaining("took") >= 1, "theft announced to everyone")

    customCommandHooks.run(1, "scramble done")
    eq(state.phase(), "showcase", "still waiting for others")
    customCommandHooks.run(3, "scramble pass")
    eq(state.phase(), "showcase", "still waiting for admin")
    customCommandHooks.run(0, "scramble done")
    eq(state.phase(), "idle", "all done triggers scoring and reset")
    check(#stubs.chatContaining("results for Testville") >= 1, "results announced")
    eq(state.history.rounds, 1, "history recorded")
    check(state.current.lastResults ~= nil and #state.current.lastResults.rows == 4, "last results kept")
    local winner = state.current.lastResults.rows[1]
    check(winner.name == "Admin" or winner.name == "Bob", "winner is a real player")
    eq(#stubs.timersNamed("Scramble_OnShowcaseTimeout"), 0, "showcase timer cleared")
    eq(stubs.freeTimerCalls, 0, "FreeTimer never called during a round")

    -- A second round must reuse the timers of the first instead of creating new ones.
    stubs.reset()
    local createdRoundEnd = stubs.timersCreated("Scramble_OnRoundEnd")
    local createdCountdown = stubs.timersCreated("Scramble_OnCountdown")
    local createdShowcase = stubs.timersCreated("Scramble_OnShowcaseTimeout")
    local createdGrace = stubs.timersCreated("Scramble_OnGraceExpired")
    eq(createdShowcase, 1, "showcase timer created once, before the round-end callback")
    customCommandHooks.run(0, "scramble start 2")
    eq(state.phase(), "scramble", "second round started")
    eq(#stubs.timersNamed("Scramble_OnRoundEnd"), 1, "round end timer re-armed")
    eq(stubs.timersCreated("Scramble_OnRoundEnd"), createdRoundEnd, "round end timer reused")
    eq(stubs.timersCreated("Scramble_OnCountdown"), createdCountdown, "countdown timers reused")
    customEventHooks.fire("OnPlayerCellChange", 1, { location = { cell = "5, 5" } }, "-3, -2")
    eq(#stubs.timersNamed("Scramble_OnGraceExpired"), 1, "grace timer re-armed in second round")
    eq(stubs.timersCreated("Scramble_OnGraceExpired"), createdGrace, "grace timer for the slot reused")
    customEventHooks.fire("OnPlayerDisconnect", 1)
    eq(#stubs.timersNamed("Scramble_OnGraceExpired"), 0, "disconnect stops the grace timer")
    customEventHooks.fire("OnPlayerResurrect", 0)
    customEventHooks.fire("OnPlayerDisconnect", 0)
    eq(#stubs.timersNamed("Scramble_OnRespawnReturn"), 0, "disconnect stops the respawn return timer")
    stubs.fireTimers("Scramble_OnRoundEnd")
    eq(state.phase(), "showcase", "second round reaches the showcase")
    eq(#stubs.timersNamed("Scramble_OnShowcaseTimeout"), 1, "showcase timeout re-armed")
    eq(stubs.timersCreated("Scramble_OnShowcaseTimeout"), createdShowcase, "showcase timer reused")
    eq(stubs.freeTimerCalls, 0, "FreeTimer never called across rounds")
end

-------------------------------------------------------------------------------
section("stop, resume and random location")
do
    local mod = reloadMod()
    local state = mod.state
    stubs.addPlayer(0, "Admin", 2, {})
    customCommandHooks.run(0, "scramble location random")
    customCommandHooks.run(0, "scramble start")
    eq(state.phase(), "scramble", "random start works")
    eq(state.current.locationKey, "testville", "random avoids guessed spawns")
    eq(state.current.lengthMinutes, mod.config.roundMinutes, "default length used")

    -- Simulate a server restart mid-round: reload modules, state comes back from json.
    local saved = stubs.jsonStore["custom/scavenger_state.json"]
    check(saved ~= nil and saved.phase == "scramble", "state saved mid-round")
    for name in pairs(package.loaded) do
        if string.find(name, "^custom%.scavenger%-scramble") then package.loaded[name] = nil end
    end
    Scramble = nil
    customEventHooks.handlers = {}
    customCommandHooks.commands = {}
    stubs.reset()
    stubs.clearTimers()
    local mod2 = require("custom.scavenger-scramble.main")
    customEventHooks.fire("OnServerPostInit")
    eq(mod2.state.phase(), "scramble", "phase resumed after restart")
    eq(#stubs.timersNamed("Scramble_OnRoundEnd"), 1, "round timer re-armed after restart")
    customEventHooks.fire("OnPlayerAuthentified", 0)
    check(stubs.lastTeleport(0) ~= nil and stubs.lastTeleport(0).cell == "-3, -2", "returning participant teleported back in")

    customCommandHooks.run(0, "scramble stop")
    eq(mod2.state.phase(), "idle", "stop resets phase")
    eq(#stubs.timersNamed("Scramble_OnRoundEnd"), 0, "stop clears timers")
    check(stubs.lastTeleport(0).cell == mod2.config.showcase.cell, "stop sends players to showcase")

    customCommandHooks.run(0, "scramble status")
    check(#stubs.chatContaining("No round running") == 1, "status when idle")
    customCommandHooks.run(0, "scramble here")
    check(#stubs.chatContaining("posX") == 1, "here prints a spawn line")
    stubs.playerCells[0] = "Pelagiad, Halfway Tavern"
    customCommandHooks.run(0, "scramble showcase")
    eq(mod2.round.showcaseSpot().cell, "Pelagiad, Halfway Tavern", "showcase override set from position")
    check(stubs.jsonStore["custom/scavenger_state.json"].showcase.cell == "Pelagiad, Halfway Tavern", "showcase override persisted")
    mod2.state.reset()
    eq(mod2.round.showcaseSpot().cell, "Pelagiad, Halfway Tavern", "showcase override survives reset")
    customCommandHooks.run(0, "scramble location")
    check(stubs.boxes[#stubs.boxes].kind == "list", "location list box shown")
    customEventHooks.fire("OnGUIAction", 0, mod2.config.gui.locationList, "0")
    eq(mod2.state.current.nextLocation, "emptyton", "list box selection picks first alphabetical location")
    customEventHooks.fire("OnGUIAction", 0, mod2.config.gui.locationList, "2")
    eq(mod2.state.current.nextLocation, "random", "last row is random")
    eq(mod2.locations.resolve("Test Ville"), nil, "resolve rejects nonsense")
    eq(mod2.locations.resolve("testv"), "testville", "resolve by prefix")
    eq(mod2.locations.resolve("2"), "testville", "resolve by number")
end

-------------------------------------------------------------------------------
io.write(string.format("\n%d passed, %d failed\n", passed, failed))
for _, message in ipairs(failures) do
    io.write("FAIL: " .. message .. "\n")
end
if failed > 0 then error("tests failed") end
