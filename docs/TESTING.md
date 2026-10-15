# Scavenger Scramble: playtest script

Follow the steps in order. Each test has **Do**, **Expect** and **Record**. Mark every test PASS, FAIL or PARTIAL in the report template at the end, and write down anything unexpected even if the test passed. Copy chat lines exactly when they differ from what is expected.

Testers needed: 2 clients minimum (3 is better). One is the **Host** (staff), the others are **P2** and **P3**. Keep rounds short (2 minutes) so the whole script fits in about an hour.

## 0. Setup (Host, once)

1. Make sure nobody is connected and `tes3mp-server.exe` is not running.
2. Give yourself staff rank. Open `F:\tes3mp.Win64.release.0.8.1\server\data\player\<YourAccountName>.json` in a text editor, find `"staffRank": 0` under `settings`, change it to `"staffRank": 2`, save.
3. Start the server (`tes3mp-server.exe` or `tes3mp-server-autorestart.bat`).
4. Watch the console. Within a few seconds it must print, in this order:
   ```
   [Scramble] Loaded 12790 items and 37 categories
   [Scramble] Loaded index of 135 locations
   [Scramble] Scavenger Scramble ready. Phase: idle
   ```
5. Everyone connects by launching `F:\tes3mp.Win64.release.0.8.1\tes3mp.exe` (the TES3MP client, not `openmw-launcher.exe`) and choosing Join Server from the main menu. The client reads `tes3mp-client-default.cfg` next to it for the address, port and password:
   - Host on the same PC: `destinationAddress = localhost`, `port = 25564`, `password = <the server password from tes3mp-server-default.cfg>`.
   - Other testers: same file on their PC with `destinationAddress` set to the host's IP, and the same 18 plugins in the same order as the host's `openmw.cfg`, including the same version of Tamriel Rebuilt. A mismatch is reported as `Your plugins or their load order don't match the server's.` in the client log.
   All testers should be somewhere other than Balmora before test 4, so that teleports are obvious.
6. **Record**: the three lines above appeared (yes/no), and any line containing `ERROR`, `error`, `Timer` or `[Scramble]` that is not listed above. `Timer <n> not found!` in particular means a timer was created dead and will never fire; it must not appear at any point during the session.

The server log for the session is saved as `tes3mp-server-<date>.log` in your OpenMW user folder, which on this PC is `C:\Users\jonat\OneDrive\Documents\My Games\OpenMW`. The client writes `tes3mp-client-<date>.log` to the same folder. Attach the server log, and any client log from a session where something went wrong, with your report.

## 1. Help and permissions

- **Do (P2)**: type `/scramble` then `/scramble start`.
- **Expect**: `/scramble` prints the player command list (objectives, status, done, pass, results, leaderboard) and nothing about start/stop. `/scramble start` answers `You need staff rank 1 to do that.` No round starts.
- **Do (Host)**: type `/scramble help`.
- **Expect**: the list now also shows start, stop, location, minutes, here, showcase, score, reset.
- **Record**: PASS/FAIL, and whether `/ss help` gives the same output.

## 2. Status when idle

- **Do (anyone)**: `/scramble status`.
- **Expect**: `No round running.` and `Next location: random`.
- **Record**: PASS/FAIL.

## 3. Choosing the location

- **Do (Host)**: `/scramble location` with no argument.
- **Expect**: a list box opens with 135 numbered cities, "Balmora (42 interiors)" among them, and "Random" as the last row. Pick Balmora.
- **Expect**: everyone sees `Next Scramble location: Balmora.`
- **Do (Host)**: `/scramble location old eb`, then `/scramble location list`, then `/scramble location balmora`.
- **Expect**: the first resolves to Old Ebonheart (chat confirms and prints its cell counts). The list prints 135 lines. The last sets Balmora again.
- **Record**: PASS/FAIL. Did the list box fit on screen or need scrolling? Was any city name wrong or missing that you expected (vanilla or Tamriel Rebuilt)?

## 4. Starting a round

- **Do (Host)**: `/scramble start 2`.
- **Expect, in this order**:
  1. Chat: `A Scavenger Scramble is starting in Balmora!`
  2. Every connected player is teleported to Balmora's exterior near the Hlaalu guard by the south-west entrance (cell -3, -2). Players already standing in Balmora may see their cell reload.
  3. Chat: `You have 2 minutes. Hold your finds in your inventory when time runs out.`, then `Objectives:` and three numbered lines. Line 1 is an exact item with a gold value. Lines 2 and 3 are categories such as `Any helmet`.
  4. A message box with the same objectives and an Ok button.
- **Record**: PASS/FAIL. Write down the three objectives exactly. Did anyone fail to teleport, spawn inside geometry, under the terrain, or in water? Did the box appear for everyone? How long did the start take from the command to being in Balmora?
- **Do (anyone)**: `/scramble objectives` and `/scramble status`.
- **Expect**: objectives again plus `Time left:` and a participant list showing everyone.

## 5. Bounds

- **Do (P2)**: enter any Balmora interior (a shop), come back out, then walk out of town along the road south toward Pelagiad until you cross roughly two cells (about one minute of running). Keep an eye on chat.
- **Expect**: no warning inside shops or in the cells right next to town. After crossing further out: `<cell> is outside Balmora! Return within 30 seconds or you will be sent back.` If you do not come back within 30 seconds: `Out of bounds too long. Sending you back to the start.`, everyone sees `<name> wandered off and was sent back to Balmora.`, and you are teleported to the start point.
- **Do (P3)**: trigger the warning, then walk back toward town before 30 seconds pass.
- **Expect**: `Back in bounds.` and no teleport.
- **Record**: PASS/FAIL. Where exactly did the warning first fire (note the cell coordinates it printed)? Did it fire anywhere inside town that it should not have? Is 1 cell of padding and 30 seconds grace too tight, too loose, or right?

Note: the round is only 2 minutes. If time ends during this test, start a new round with `/scramble start 3` after the showcase finishes (or `/scramble stop` to skip it) and continue.

## 6. Death during the round

- **Do (P2)**: get killed (attack a guard, or have the Host kill you). Wait for the respawn.
- **Expect**: after respawning at the temple or shrine: `You died. Returning you to the round shortly.`, then about 4 seconds later a teleport back to the Balmora start point. Your inventory is unchanged.
- **Record**: PASS/FAIL. How many seconds between respawn and teleport? Did anything in the respawn flow look wrong? Did the console print `Timer <n> not found!` when you died (it must not)?

## 7. Countdown and time end

- **Do (all)**: grab things. Each player should pick up at least one item that matches an objective and one that does not. One player should also pick up an item they already owned a copy of before the round started (for test 8).
- **Expect**: chat shows `2m left!` right away is not expected; the marks are 10, 5, 2, 1 minutes and 30, 10 seconds, so on a 2-minute round you should see `1m left!`, `30s left!`, `10s left!`. At zero: `Time is up! Hands off the loot.`, then everyone is teleported into Balmora, Nerano Manor, and chat explains the showcase with the objectives repeated. The manor is reset first: only its original occupants are present, and items from any earlier showcase are gone.
- **Record**: PASS/FAIL. Were the countdown marks on time (compare against a phone timer)? Did the teleport into Nerano Manor put anyone inside a wall or on top of Ondres Nerano? Note the exact spot and whether it is acceptable. Was anything hostile or left over from a previous session inside the manor?

## 8. Showcase placement rules

- **Do (P2)**: drop an item you found during the round that matches an objective.
- **Expect**: `Displayed <item> x1 (counts for objective N)` to you, and `<name> displays <item>.` to everyone.
- **Do (P2)**: drop an item you found that matches no objective.
- **Expect**: `Displayed <item> x1 (matches no objective)`.
- **Do (P2)**: drop an item you already owned before the round (gold works: drop 10 gold).
- **Expect**: `<item> was not acquired during the round, so it does not count.`
- **Do (P3)**: drop two copies of an item of which you only found one during the round (if you had none before, drop one, pick it up, drop it again instead).
- **Expect**: the second drop says `You have already displayed all of your <item>.` (Pick-up then re-drop: the pick-up says `<item> removed from your display.`, the re-drop counts again.)
- **Record**: PASS/FAIL for each of the four cases. Did any drop give no message at all?

## 9. Stealing from a display

- **Do (Host)**: pick up one item from P2's display.
- **Expect**: everyone sees `<Host> took <item> from <P2>'s display!` and it no longer counts for P2.
- **Do (Host)**: drop it back. **Expect**: it counts for the Host only if the Host also acquired that item during the round; otherwise `was not acquired` and P2 has to pick it up and drop it again.
- **Record**: PASS/FAIL. Is this rule fun or annoying?

## 10. Finishing and scoring

- **Do (P2)**: `/scramble done`. **Expect**: `<P2> is done displaying.` to everyone. Nothing else happens yet.
- **Do (P3)**: `/scramble pass`. **Expect**: `<P3> passes.`
- **Do (Host)**: `/scramble done`.
- **Expect**: `Everyone is done. Scoring...`, then `Scavenger Scramble results for Balmora:` with one line per player in rank order, e.g. `#1 Host - 3 pts (2 found, 1 bonus) | 1: Steel Dagger (20g); 2: missed; 3: Iron Helmet (40g) +best`. Then `<name> wins the Scramble!` in yellow, and a scoreboard message box for everyone.
- **Check the arithmetic**: points = number of objectives credited; bonus = +1 for the most valuable item in each category objective; `+best` marks which items earned it. Ties on score break on total gold value, then on who typed done first.
- **Record**: PASS/FAIL. Copy every results line verbatim. Was the scoring correct by your own reckoning? Was anything credited to the wrong objective?

## 11. Results and leaderboard afterward

- **Do (anyone)**: `/scramble results`, `/scramble leaderboard`, `/scramble status`.
- **Expect**: last results with scores; leaderboard with `1 wins / 1 played` for the winner; status back to `No round running.` with the last round summary.
- **Record**: PASS/FAIL.

## 12. Late join and reconnect

- **Do (Host)**: `/scramble start 3`. Then **P3** disconnects and reconnects while the round is running. Then a player who was not online at start (or P3 again after a second disconnect, if you only have three) joins.
- **Expect**: the reconnecting participant is teleported back to the start point with `Welcome back, the round is still running.` A brand-new joiner gets `<name> joined the Scramble late.`, the objectives, and the teleport.
- **Do (P2)**: disconnect before time ends and stay offline through the showcase.
- **Expect**: scoring is not blocked by the offline player. When Host and P3 are done, results print and the offline player appears with 0 points.
- **Record**: PASS/FAIL. Note any teleport that failed after reconnecting.

## 13. Server restart mid-round

- **Do (Host)**: `/scramble start 4`. After about one minute, stop the server (close the console), wait 10 seconds, start it again, and reconnect everyone.
- **Expect**: console prints `[Scramble] Resumed scramble phase with <n>s left` and `Phase: scramble`. Each reconnecting participant is teleported back into Balmora. The round ends at about the original time.
- **Record**: PASS/FAIL. How many seconds were left on resume versus what you expected?

## 14. Stop and reset

- **Do (Host)**: `/scramble start 2`, wait 20 seconds, `/scramble stop`.
- **Expect**: `The round was stopped by <Host>. Returning everyone to the showcase.` and everyone lands in Nerano Manor. No results, no leaderboard change.
- **Do (Host)**: `/scramble reset`. **Expect**: `Round state cleared.` with nothing broken afterward.
- **Record**: PASS/FAIL.

## 15. Showcase spot and spawn overrides

- **Do (Host)**: stand somewhere nicer inside Nerano Manor (or any interior you prefer) and type `/scramble showcase`.
- **Expect**: `Showcase spot set to <cell> by <Host>.` Run a 1-minute round (`/scramble start 1`) and confirm time-end teleports everyone to the new spot. Restart the server later and confirm the spot is still used.
- **Do (Host)**: stand at a good Balmora start point and type `/scramble here`.
- **Expect**: a line like `{ cell = "-3, -2", posX = ..., posY = ..., posZ = ..., rotZ = ... },` in chat and in the server log.
- **Record**: PASS/FAIL. Paste the `/scramble here` line if you think the generated Balmora spawn should change.

## 16. A Tamriel Rebuilt city

- **Do (Host)**: `/scramble location old ebonheart`, then `/scramble start 5`. Play it properly.
- **Expect**: teleport to Old Ebonheart's docks area (cell 7, -19), objectives that make sense for that city, bounds that cover the whole walled city and docks, showcase and scoring as before.
- **Record**: PASS/FAIL. The objectives rolled. Was the exact item findable (did anyone find it, and where)? Did the bounds warning fire anywhere inside the city? How did the spawn point feel?

## 17. Judgement calls (after everything else)

Answer briefly:

1. Is 1 exact item + 2 categories the right mix? Would you rather have 2 + 1, or 4 objectives?
2. Do the exact items feel findable but hard, or hopeless? Give examples from your rounds.
3. Did any category feel trivial (for example "Any potion" in a town with an alchemist)? Which should be removed or made rarer?
4. Is the best-in-category bonus changing how you play?
5. Round length that felt best.
6. Anything you expected the mode to do that it did not.

---

## Report template

Copy this, fill it in, and send it back together with the server log file.

```
Date:
Testers (Host / P2 / P3):
Server build: tes3mp 0.8.1 local  |  dfashbaugh 0.51 port  (circle one)

0  Setup                  PASS / FAIL / PARTIAL   notes:
1  Help and permissions   PASS / FAIL / PARTIAL   notes:
2  Status idle            PASS / FAIL / PARTIAL   notes:
3  Location choice        PASS / FAIL / PARTIAL   notes:
4  Round start            PASS / FAIL / PARTIAL   objectives rolled:
                                                  notes:
5  Bounds                 PASS / FAIL / PARTIAL   first warning cell:   notes:
6  Death                  PASS / FAIL / PARTIAL   seconds to return:    notes:
7  Countdown / time end   PASS / FAIL / PARTIAL   notes:
8  Placement rules        a: PASS/FAIL  b: PASS/FAIL  c: PASS/FAIL  d: PASS/FAIL   notes:
9  Stealing               PASS / FAIL / PARTIAL   notes:
10 Scoring                PASS / FAIL / PARTIAL   results lines (verbatim):
                                                  arithmetic correct? notes:
11 Results / leaderboard  PASS / FAIL / PARTIAL   notes:
12 Late join / reconnect  PASS / FAIL / PARTIAL   notes:
13 Restart mid-round      PASS / FAIL / PARTIAL   seconds left on resume:   notes:
14 Stop / reset           PASS / FAIL / PARTIAL   notes:
15 Showcase / here        PASS / FAIL / PARTIAL   /scramble here line:
16 TR city                PASS / FAIL / PARTIAL   objectives rolled:   notes:
17 Judgement calls        (answers 1-6)

Crashes or script errors (paste the console lines):
Anything else:
```
