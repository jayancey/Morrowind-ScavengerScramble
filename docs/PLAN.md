# Scavenger Scramble: implementation plan

## Context

Scavenger Scramble is a round-based multiplayer game mode for TES3MP. Players are dropped into a city, given a short list of objectives (exact items or item categories), and race to hold qualifying items in their inventory when the real-time timer ends. Everyone is then teleported to a showcase cell, lays out their finds, and the mod scores and announces a winner.

The group has played this manually (meet at an unvisited town, roll random item IDs, agree categories, set a timer, reconvene at Nerano Manor). An earlier Lua prototype exists on the server (`F:\tes3mp.Win64.release.0.8.1\server\scripts\custom\scavenger-scramble - Copy`) but only rolls one vanilla item, runs a fixed timer and teleports to placeholder coordinates. This project replaces it.

Target runtime: dfashbaugh's TES3MP fork (`openmw-51-port-v1`), which is a parity port of TES3MP 0.8.1 onto OpenMW 0.51 using stock CoreScripts. There is no new Lua API, so the mod is written against the 0.8.1 CoreScripts API and tested on the local 0.8.1 server. The one fork caveat that matters: refIds may arrive with different casing, so all refId comparisons are lower-cased.

Decisions already made with the user:

| Topic | Decision |
| --- | --- |
| Scoring | 1 point per objective met, plus 1 bonus point for the most valuable item in each category objective |
| Timer | Real-time minutes, configurable, with chat countdown warnings |
| Bounds | Warn on leaving the location, short grace period, then teleport back |
| Showcase | Players drop items themselves in the showcase cell; the mod detects placements; scoring runs when everyone is done |
| Tamriel Rebuilt | Fully supported: locations and item pools come from the actual load order |

Assumptions (stated, not asked):

- Players use their persistent characters. Inventories are snapshotted at round start and only items acquired during the round count, so pre-owned items do not help.
- The location's cells are reset to pristine before each round (configurable, default on), matching the "unvisited town" rule of the manual games.
- Default showcase cell is `Balmora, Nerano Manor`. Any interior works.
- Rounds are controlled by an admin via chat commands; non-admins can only ready up, view objectives and mark themselves done.
- Items that cannot be legitimately "found" are excluded from objectives: keys, gold, zero-value junk, and anything with no instance in the chosen location.

## Design in one paragraph

The core tension is greed versus security. A category objective is satisfied by the first matching item you touch, but the bonus point goes to whoever brings the most valuable example, so every player keeps choosing between banking what they have and risking time, bounty and other players to upgrade. Exact-item objectives are rolled only from items that actually exist in the chosen city (placed refs, container contents, merchant and NPC inventories, leveled lists resolved to their possible outcomes), weighted toward uncommon instances, so the hunt is hard but never impossible. Theft, pickpocketing, killing NPCs and robbing other players are all valid; the mod never judges how an item was obtained.

## Architecture

```
E:\Morrowind-ScavengerScramble\
  tools\
    gen_data.py            offline generator: esmtool dump -> Lua data tables
    deploy.ps1             copies the mod into the server's custom scripts folder
  scavenger-scramble\      the Lua mod (deployed as scripts/custom/scavenger-scramble)
    main.lua               entry point; requires modules, registers hooks and commands
    config.lua             tunables (round length, objective mix, showcase cell, grace time, GUI ids)
    state.lua              round state machine + persistence to data/custom/scavenger_state.json
    data/items.lua         generated: refId -> {name, type, subtype, value, weight, flags}
    data/locations.lua     generated: city -> {exterior cells, interior cells, spawn, knownItems}
    data/categories.lua    hand-written category definitions and matchers
    objectives.lua         rolls objectives for a location; matches items against objectives
    locations.lua          location selection, bounds test, cell reset, spawn points
    round.lua              start/end flow, inventory snapshots, timers, countdown messages
    bounds.lua             OnPlayerCellChange watcher with grace timer and teleport-back
    showcase.lua           OnObjectPlace tracking in the showcase cell, done/pass handling
    scoring.lua            checklist + best-in-category bonus, tiebreaks, results history
    gui.lua                objective list, scoreboard, admin list boxes
    commands.lua           /scramble command family
  docs\PLAN.md
```

### 1. Data generator (`tools/gen_data.py`)

The server cannot read ESM files at runtime, so item and location data is produced offline.

- Runs `esmtool.exe dump -C` (from the TES3MP install) over the content files listed in the OpenMW load order (`Morrowind.esm`, `Tribunal.esm`, `Bloodmoon.esm`, `Tamriel_Data.esm`, `TR_Mainland.esm`, plus any esps), later files overriding earlier ones. Output is parsed from esmtool's text format, which was verified to include item records, cell records with coordinates, cell references with owner, container inventories, NPC inventories and leveled lists.
- `items.lua`: every carryable record type (WEAP, ARMO, CLOT, BOOK, INGR, ALCH, MISC, LOCK, PROB, REPA, APPA, LIGH) with name, type, subtype (weapon class, armor slot, clothing slot, apparatus kind, scroll flag), value, weight. All ids lower-cased.
- `locations.lua`: for each city name (vanilla and TR), the exterior grid cells whose name equals the city, the interior cells named `City, ...`, a spawn point, and `knownItems`: a map of item refId to instance count and an `owned` flag, built from direct references, container contents (recursively through leveled lists), and NPC inventories in those cells. Cities below a minimum interior count are skipped. Spawn points default to the first exterior cell's center and can be overridden by a hand-edited `data/spawn_overrides.lua`.
- `categories.lua` (hand-written): category objectives such as any dagger, any long blade, any bow, any helmet, any cuirass, any ring, any amulet, any robe, any scroll, any book, any potion, any ingredient, any soul gem, any lockpick or probe, any repair hammer, any alchemy apparatus, an item worth 100+ / 500+ gold. Each has a matcher over the item table. The roller checks that a category has at least one known instance in the location before offering it.

### 2. Round flow (`state.lua`, `round.lua`)

States: `idle -> lobby -> scramble -> showcase -> results -> idle`.

- `/scramble start [minutes]` (admin): picks the location (current selection or random), resets its cells, rolls objectives, snapshots every online player's inventory as refId -> count, teleports everyone to the spawn point, starts the main timer and countdown timers (`tes3mp.CreateTimerEx` with global callback functions, the only kind the timer API accepts), announces the objectives in chat and in a message box.
- During the round: `/scramble objectives` re-shows the list; `/scramble status` shows time left; players who die are returned to the spawn point after resurrect; players who join late get the objectives and are teleported in (configurable).
- At time-end: a second inventory snapshot per player; `acquired = final - start` per refId; the mod records which objectives each player satisfied and with which item, then teleports everyone to the showcase cell.

### 3. Bounds (`bounds.lua`)

`OnPlayerCellChange` handler. If a round is active and the new cell is not in the location's exterior or interior set, send a warning and start a per-player grace timer. On expiry, if the player is still out of bounds, teleport them to the spawn point. Re-entering bounds cancels the timer.

### 4. Showcase (`showcase.lua`)

In the showcase cell the mod listens to `OnObjectPlace`. When the placing player drops an item whose refId is in their acquired list, it is marked displayed and credited toward whichever objective it satisfies, with chat feedback. `/scramble done` marks a player finished; `/scramble pass` marks them finished with nothing. When every participant is done, or the showcase timeout elapses, scoring runs. Only displayed items count, so the ritual is preserved and the inventory check at time-end prevents last-second cheating.

### 5. Scoring (`scoring.lua`, `gui.lua`)

- 1 point per objective satisfied.
- For each category objective, +1 to the player whose credited item has the highest gold value (ties share).
- Tiebreak: total value of displayed credited items, then earliest `/scramble done`.
- Results are broadcast in chat and shown as a scoreboard message box listing each player's items and points. A history file tracks wins per account for `/scramble leaderboard`.

### 6. Commands

| Command | Who | Effect |
| --- | --- | --- |
| `/scramble start [minutes]` | admin | start a round at the current location |
| `/scramble stop` | admin | abort the round and return everyone to the showcase cell |
| `/scramble location [name or number]` | admin | list or choose the next location via list box |
| `/scramble config` | admin | list box for round length, objective count and mix |
| `/scramble objectives` | all | show current objectives |
| `/scramble status` | all | time left, location, who is done |
| `/scramble done` / `pass` | all | finish showcase placement |
| `/scramble leaderboard` | all | historical wins |

### 7. Deployment

`tools/deploy.ps1` moves the old prototype folders to `custom\backup\` and copies `scavenger-scramble\` into `server\scripts\custom\`. The existing `require('custom.scavenger-scramble.main')` line in `customScripts.lua` stays as is.

## Verification

1. Run `gen_data.py` against `E:\Morrowind\Data Files` and the load order from `openmw.cfg`; check that Balmora, Vivec, Old Ebonheart and Andothren appear with sensible cell lists and non-empty known item sets.
2. Unit-test `objectives.lua` and `scoring.lua` matchers with a standalone Lua run (stubbed `tes3mp` table), covering exact match, category match, bonus and tiebreak cases.
3. Start the local 0.8.1 server with the mod deployed and confirm no script errors in the server log.
4. Playtest with two clients: start a round in Balmora, confirm teleport, objectives message, bounds warning and teleport-back, timer end, showcase detection on drop, scoring announcement. Repeat once in a TR city.
5. Flag for the fork: lower-cased refId comparisons and no use of cell record overrides.

## Out of scope for the first version

- Voting for locations or objectives (admin picks).
- Custom showcase cell geometry or real display cases.
- Server restart recovery mid-round beyond persisting the state file.
