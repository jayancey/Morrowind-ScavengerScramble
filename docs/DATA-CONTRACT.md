# Data contract: generator output consumed by the Lua mod

The TES3MP server cannot read ESM/ESP files. `tools/gen_data.py` parses the game's content files offline and writes Lua modules into `scavenger-scramble/data/`. The Lua mod only ever reads these files; it never touches ESMs.

## File layout

The server embeds LuaJIT 2.1, which allows at most 65536 constants per function (a whole file is one function). A single `locations.lua` exceeds that, so the output is sharded:

```
data/items.lua                 all items, or a loader that merges data/items/part_NN.lua (see below)
data/items/part_01.lua ...     only when there are more than 12,000 items; 6,000 entries per part
data/locations/index.lua       array of location summaries, sorted by name
data/locations/<key>.lua       one full location table per location
```

- `items.lua`: with 12,000 entries or fewer it is a single `return { ... }` table. Above that, the entries go to `data/items/part_01.lua`, `part_02.lua` ... (each a plain `return { ... }`), and `items.lua` becomes a small loader that `require`s each part as `custom.scavenger-scramble.data.items.part_NN` (prefix configurable with `--module-prefix`) and returns the merged table. Either way, `require("custom.scavenger-scramble.data.items")` returns the same refId -> item map. The current load order (12,790 items) produces 3 parts.
- `locations/index.lua` returns an array sorted by name: `{ { key = "balmora", name = "Balmora", source = "Morrowind.esm", exteriors = 4, interiors = 42, knownItems = 1237, spawnGuess = false }, ... }`. The three numbers are counts, not lists.
- `locations/<key>.lua` returns the full location table described below (no outer key). Load it with `require("custom.scavenger-scramble.data.locations." .. key)`.
- Location keys match `^[a-z_][a-z0-9_]*$`, so they are valid file names and Lua module names: the city name lower-cased, every character other than `a-z0-9` replaced by `_`, prefixed with `loc_` if it would start with a digit. If two names normalise to the same key, the later one gets `_2`, `_3` ... and the generator prints a warning.
- Each run deletes `.lua` files in `data/locations/` and `data/items/` that it did not write, and removes the old monolithic `data/locations.lua`. Nothing hand-written may live in those two directories. `data/categories.lua` and `data/spawn_overrides.lua` are hand-written and never touched.

## Conventions

All generated files are plain Lua 5.1 modules (`return { ... }`) that also load under LuaJIT 2.1. Every refId key and every refId appearing in a value is lower-cased, because TES3MP refIds are case-insensitive and dfashbaugh's OpenMW 0.51 port may change casing on the wire. Cell descriptions keep their original casing (TES3MP matches cell names as the game stores them). Exterior cells use TES3MP's description format `"x, y"` with a single space after the comma, e.g. `"-3, -2"`.

Load order: the generator takes the `content=` lines of an `openmw.cfg` in order and resolves each file against that cfg's `data=` directories (later data dirs win). Records from later content files override earlier ones with the same id. Deleted records are removed. A `--skip` list lets the user drop total-conversion plugins.

## `data/items.lua`

```lua
return {
  ["steel dagger"] = { name = "Steel Dagger", type = "weapon", subtype = "shortblade", value = 20, weight = 3, source = "Morrowind.esm" },
  ["t_de_fur_shoes_01"] = { name = "...", type = "clothing", subtype = "shoes", value = 2, weight = 1, source = "Tamriel_Data.esm" },
  ...
}
```

Fields: `name` (display name, may be empty string for nameless records; records with empty names are dropped), `type`, `subtype`, `value` (integer gold), `weight` (number), `source` (content file that last defined it), `enchanted = true` only when the record has an enchantment id (`ENAM`; potions are never enchanted, because in ALCH records `ENAM` is the effect list), `unique = true` when the id contains `unique` or `artifact` (heuristic, used for rarity weighting only).

`type` and `subtype` values:

| type | record | subtype values |
| --- | --- | --- |
| `weapon` | WEAP | `shortblade`, `longblade`, `blunt`, `axe`, `spear`, `bow`, `crossbow`, `thrown`, `arrow`, `bolt` (two-hand variants fold into the one-hand name: Long Blade Two Close -> `longblade`, Blunt Two Close/Wide -> `blunt`, Axe Two Hand -> `axe`) |
| `armor` | ARMO | `helmet`, `cuirass`, `lpauldron`, `rpauldron`, `greaves`, `boots`, `lgauntlet`, `rgauntlet`, `shield`, `lbracer`, `rbracer` |
| `clothing` | CLOT | `pants`, `shoes`, `shirt`, `belt`, `robe`, `rglove`, `lglove`, `skirt`, `ring`, `amulet` |
| `book` | BOOK | `book` or `scroll` |
| `ingredient` | INGR | `ingredient` |
| `potion` | ALCH | `potion` |
| `misc` | MISC | `soulgem` (id starts with `misc_soulgem` or name contains "Soul Gem"), otherwise `misc`. Keys are **excluded**: key flag set; or id/name containing "key" with value 0; or id matching `(^|_)key` (`key_arobarmanor_01`, `tr_key_divayth01`); or the whole word "key" in the name (`\bkey\b`, case-insensitive, e.g. "Necrom Temple Key 'A'"). The last two rules exist because most vanilla and Tamriel Rebuilt keys do not set the key flag and are worth 300 gold. Gold (`gold_001` etc.) is excluded. |
| `lockpick` | LOCK | `lockpick` |
| `probe` | PROB | `probe` |
| `repair` | REPA | `repair` |
| `apparatus` | APPA | `mortar`, `alembic`, `calcinator`, `retort` |
| `light` | LIGH | `light`, **only** when the CanCarry flag (0x02) is set |

## `data/locations/<key>.lua`

```lua
return {
  name = "Balmora",
  source = "Morrowind.esm",
  exteriors = { "-2, -2", "-3, -2", "-3, -3", "-4, -2" },
  interiors = { "Balmora, Guild of Mages", "Balmora, Nerano Manor", ... },
  spawn = { cell = "-3, -2", posX = -20190.7988, posY = -13064.7422, posZ = 189.6947, rotZ = 4.0832 },
  spawnCandidates = {
    { cell = "-3, -2", posX = -20190.7988, posY = -13064.7422, posZ = 189.6947, rotZ = 4.0832, refId = "hlaalu guard_outside", kind = "npc" },
    ...
  },
  knownItems = {
    ["steel dagger"] = { count = 3, owned = 1, direct = 1, container = 1, npc = 1 },
    ...
  },
}
```

- Key (the file name): see File layout.
- `name`: the city name exactly as the exterior cells are named (e.g. `Old Ebonheart`, `Ald-ruhn`).
- `source`: the earliest content file (in load order) that gave one of the city's exterior cells its current name. For Tamriel Rebuilt cities this is `TR_Mainland.esm`, even though the bare grid cells already exist in `Morrowind.esm`.
- `exteriors`: every exterior cell whose Name equals the city name, **plus exterior sub-districts** whose Name is `<city name>, ...`, provided an exterior cell named exactly `<city name>` exists. This covers Vivec's cantons (`Vivec, Arena`, `Vivec, Foreign Quarter` ...) and also `Old Ebonheart, Docks`, `Andothren, Docks`, `Necrom, Waterfront` and `Akamora, Mines`. Sub-districts are then never emitted as locations of their own. Written as `"x, y"` descriptions, sorted. Without this rule Vivec would have 3 exteriors, and players walking between cantons would leave bounds.
- `interiors`: every interior cell whose Name starts with `<city name>, ` (comma and space), sorted. Only cities with at least `--min-interiors` (default 4) interiors are emitted.
- `spawn`: among NPC references placed in the city's exterior cells (an NPC ref stands on walkable ground), the one closest (2D distance) to the centroid of all exterior door references in those cells. `posZ` is the ref's z plus 20; `rotZ` is the ref's z rotation. If there are no exterior NPC refs, the exterior door ref closest to the centroid is used instead, also with `posZ + 20`. The spawn always equals `spawnCandidates[1]` without `refId` and `kind`. If the city has neither NPC nor door refs, use the centre of the first exterior cell (`gx*8192 + 4096`, `gy*8192 + 4096`, `posZ = 1000`) and set `spawnGuess = true` at the top level of the location table. The index's `spawnGuess` field mirrors it.
- `spawnCandidates`: up to 8 entries, with the chosen spawn first. Ranking: exterior NPC refs by distance to the door centroid, then exterior door refs by the same distance (so doors only appear when there are fewer than 8 NPCs). Each candidate's `cell` is derived from its position (`floor(x/8192), floor(y/8192)`) so the teleport cell always matches the coordinates; refs whose derived cell is not in `exteriors` are dropped. `kind` is `"npc"` or `"door"`; `refId` is the lower-cased base id. Pick a different one via `data/spawn_overrides.lua`.
- `knownItems`: every item refId (present in `items.lua`) that can be obtained inside the city's exterior and interior cells, with how many instances were found:
  - `direct`: item references placed in those cells, each counting its stack size (the reference's `NAM9`, else 1; `INTV` in a reference is health/uses, not a count). A placed leveled-item reference (LEVI) counts 1 per possible outcome.
  - `container`: items from the inventories of CONT records referenced in those cells. A plain inventory entry counts `abs(count)` (negative counts are restocking merchant stock). A leveled list (LEVI) entry counts 1 per possible outcome, not multiplied by the entry's count. Nested leveled lists are resolved recursively with a cycle guard.
  - `npc`: the same for the inventories of NPC_ and CREA records referenced in those cells. Leveled creature references (LEVC) are expanded recursively to every NPC_/CREA they can produce, and each of those inventories counts.
  - `count = direct + container + npc`.
  - `owned`: number of `direct` **instances** (same unit as `direct`, so `owned <= direct`) whose reference has an owner (ANAM) or faction owner (CNAM), i.e. taking them is theft.
- Items with no entry in `items.lua` (keys, gold, non-carryable lights, statics) are not listed.

## Binary ESM notes for the generator

The ESM/ESP format is a flat sequence of records. Each record: 4-byte type, uint32 size, uint32 header flags (unused), uint32 flags (bit 0x20 = deleted... check `DELE` subrecord too), then `size` bytes of subrecords. Each subrecord: 4-byte type, uint32 size, data. Strings are null-terminated, win-1252. Relevant subrecords:

- All item records: `NAME` id, `FNAM` display name, `ENAM` enchantment id, `SCRI` script.
- `WEAP.WPDT`: f32 weight, u32 value, u16 type, u16 health, f32 speed, f32 reach, u16 enchant, u8 chopMin, chopMax, slashMin, slashMax, thrustMin, thrustMax, u32 flags. Types 0..13: ShortBladeOneHand, LongBladeOneHand, LongBladeTwoClose, BluntOneHand, BluntTwoClose, BluntTwoWide, SpearTwoWide, AxeOneHand, AxeTwoHand, MarksmanBow, MarksmanCrossbow, MarksmanThrown, Arrow, Bolt.
- `ARMO.AODT`: i32 type, f32 weight, i32 value, i32 health, i32 enchant, i32 armor. Types 0..10: Helmet, Cuirass, LPauldron, RPauldron, Greaves, Boots, LGauntlet, RGauntlet, Shield, LBracer, RBracer.
- `CLOT.CTDT`: i32 type, f32 weight, u16 value, u16 enchant. Types 0..9: Pants, Shoes, Shirt, Belt, Robe, RGlove, LGlove, Skirt, Ring, Amulet.
- `BOOK.BKDT`: f32 weight, i32 value, i32 isScroll, i32 skill, i32 enchant.
- `INGR.IRDT`: f32 weight, i32 value, then effects.
- `ALCH.ALDT`: f32 weight, i32 value, i32 autocalc.
- `MISC.MCDT`: f32 weight, i32 value, i32 flags (bit 0 = key).
- `LOCK.LKDT` / `PROB.PBDT`: f32 weight, i32 value, f32 quality, i32 uses.
- `REPA.RIDT`: f32 weight, i32 value, i32 uses, f32 quality.
- `APPA.AADT`: i32 type (0 Mortar, 1 Alembic, 2 Calcinator, 3 Retort), f32 quality, f32 weight, i32 value.
- `LIGH.LHDT`: f32 weight, i32 value, i32 time, i32 radius, u32 colour, i32 flags (0x02 = CanCarry).
- `CELL`: `NAME` name (empty for wilderness exteriors), `DATA` u32 flags (0x01 interior), i32 gridX, i32 gridY, `RGNN` region. References follow: each starts with `FRMR` u32 refnum, then `NAME` id, optional `ANAM` owner, `CNAM` faction owner, `INTV`/`NAM9` count, `DATA` 6 x f32 (posX, posY, posZ, rotX, rotY, rotZ), `DELE` deleted marker. The count is read from `NAM9` only (`INTV` in a reference is health/uses). `MVRF` introduces a moved-reference block (`MVRF` refnum, `CNDT` target grid, then the `FRMR` ref); the generator moves that ref to the target exterior cell. No file in the current load order contains one. Note: Tribunal and later plugins may re-declare a cell to add refs, so merge references per cell across files, keyed by (file, refnum) and respecting `DELE`. The owning file comes from the FRMR high byte (0 = the current file, n = the plugin's n-th `MAST`); the low 24 bits are the index. A ref that reappears in another cell is moved there.
- `CONT`: `NAME`, `NPCO` entries: i32 count, char[32] item id. `NPC_` and `CREA`: same `NPCO` entries.
- `LEVI`: `NAME`, `DATA` flags, `NNAM` chanceNone, `INDX` count, then pairs `INAM` item id, `INTV` level.
- `LEVC`: same layout with `CNAM` creature/NPC ids instead of `INAM`.
- `DOOR`: just note the id so door refs in exterior cells can be recognised. `NPC_` ids likewise for spawn candidates.

Validation: `esmtool.exe` from the TES3MP install (`F:\tes3mp.Win64.release.0.8.1\esmtool.exe dump -t WEAP file`) can be used to cross-check record counts and a few sample values.
