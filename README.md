# Scavenger Scramble

A scavenger-hunt game mode for [TES3MP](https://github.com/TES3MP/TES3MP) (Morrowind multiplayer), built for the 0.8.1 CoreScripts API and dfashbaugh's OpenMW 0.51 port. Tamriel Rebuilt cities are supported out of the box because every location and item pool is generated from the server's real load order.

## How a round works

1. A staff member runs `/scramble start` (optionally with a length in minutes). Everyone online is teleported to the chosen city, its cells are reset to pristine, and three objectives are announced: by default one exact item that is known to exist in that city plus two categories such as "any dagger" or "any item worth 500+ gold".
2. Players scramble. Buying, stealing, pickpocketing, looting corpses and robbing each other are all fair. Leaving the city gives a warning and a short grace period, then a teleport back.
3. When the real-time timer ends, inventories are checked. Only items gained during the round count.
4. The showcase cell (Nerano Manor by default) is reset to pristine, which clears earlier displays and anything that was spawned or killed there, and everyone is moved into it. Players drop their finds to display them, then type `/scramble done`.
5. Scoring: 1 point per objective satisfied, plus 1 bonus point for the most valuable item in each category. Ties break on total value, then on who finished displaying first. Results are announced in chat and a scoreboard, and wins are tracked across rounds.

## Commands

| Command | Who | Effect |
| --- | --- | --- |
| `/scramble start [minutes]` | staff | Start a round at the next location |
| `/scramble stop` | staff | Abort the round |
| `/scramble location [name, number, random, list]` | staff | Pick the next location (no argument opens a list box) |
| `/scramble minutes <n>` | staff | Default round length |
| `/scramble score` | staff | End the showcase early and score |
| `/scramble reset` | staff | Clear a stuck round without scoring |
| `/scramble here` | staff | Print your position as a spawn override line |
| `/scramble showcase` | staff | Make where you stand the showcase spot (persists across restarts) |
| `/scramble objectives` | all | Show the objectives again |
| `/scramble status` | all | Phase, time left, participants |
| `/scramble done` / `pass` | all | Finish your showcase display |
| `/scramble results` / `leaderboard` | all | Last results and all-time wins |

`/ss` is an alias for `/scramble`. Staff means CoreScripts staff rank 1 or higher (see `config.controlRank`).

## Setup

1. Generate the data from your game's load order (needs Python 3.10+, no extra packages):

   ```
   python tools\gen_data.py --cfg "C:\Users\<you>\Documents\My Games\OpenMW\openmw.cfg" --out scavenger-scramble\data
   ```

   See `scavenger-scramble/data/README.md` for options such as skipping plugins.

2. Deploy into the server (backs up any older copy, mirrors the folder, adds the require line to `customScripts.lua`):

   ```
   powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -ServerRoot "F:\tes3mp.Win64.release.0.8.1"
   ```

3. Restart `tes3mp-server.exe`. The server log prints `[Scramble] Scavenger Scramble ready`.

4. Tune `scavenger-scramble/config.lua`: round length, objective mix, showcase cell and position, bounds padding, grace time. Hand-picked spawn points go in `data/spawn_overrides.lua` (use `/scramble here` in game to get the line).

## Tests

```
python -m pip install lupa
python tests\run_tests.py          # LuaJIT 2.1, the same Lua the server embeds
python tests\run_tests.py --lua51  # plain Lua 5.1
```

The tests run the real modules against a stubbed TES3MP API with fixture data in `tests/fixtures`.

## Layout

```
scavenger-scramble/   the mod (deployed to server/scripts/custom/scavenger-scramble)
  main.lua            entry point, event hooks
  config.lua          tunables
  round.lua           start, timer, showcase hand-off, results
  objectives.lua      rolling and matching
  scoring.lua         checklist + best-in-category bonus
  bounds.lua          out-of-bounds warning and teleport-back
  showcase.lua        drop detection in the showcase cell
  locations.lua       location index, bounds sets, cell reset
  gui.lua, commands.lua, state.lua, util.lua
  data/               generated items and per-location shards, hand-written categories
tools/gen_data.py     ESM/ESP parser that generates data/
tools/deploy.ps1      copy to the server
tests/                LuaJIT test harness
docs/                 plan and data contract
```
