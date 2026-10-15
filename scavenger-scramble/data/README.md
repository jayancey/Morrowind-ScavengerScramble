# Generated data

`tools/gen_data.py` generates these files from the game's ESM/ESP files. Do not edit them by hand; regenerate instead. The format is specified in `docs/DATA-CONTRACT.md`.

```
items.lua                 refId -> item; a small loader when split (see below)
items/part_NN.lua         item parts, written only when there are more than 12,000 items
locations/index.lua       array of { key, name, source, exteriors, interiors, knownItems, spawnGuess } (counts), sorted by name
locations/<key>.lua       one full location table per city
```

The output is sharded because the server's LuaJIT 2.1 rejects any file with more than 65536 constants ("main function has more than 65536 constants"). A single `locations.lua` exceeds that limit.
- Load a location with `require("custom.scavenger-scramble.data.locations." .. key)`.
- Load the items with `require("custom.scavenger-scramble.data.items")`; when the items are split, `items.lua` requires `items.part_NN` and merges them.

`categories.lua` and `spawn_overrides.lua` are hand-written and are never touched by the generator. Do not put hand-written files in `items/` or `locations/`: each run deletes any `.lua` there that it did not write, and it also deletes the old monolithic `locations.lua`.

## Regenerate

From the repository root (Python 3.13, standard library only):

```
python tools/gen_data.py --cfg "C:\Users\jonat\Documents\My Games\OpenMW\openmw.cfg" --out scavenger-scramble/data
```

This takes about 6 seconds. Regenerate whenever the load order changes (a plugin is added, removed or updated), then redeploy the mod to the server.

| Option | Effect |
| --- | --- |
| `--cfg PATH` | `openmw.cfg` to read `data=` and `content=` lines from (required). Content files load in `content=` order. Each file is looked up across the `data=` directories, and a later directory wins when several contain the same file. |
| `--out DIR` | Output directory (default `scavenger-scramble/data`). |
| `--skip FILE` | Leave a content file out (repeatable). |
| `--include-all` | Do not apply the default skips. By default `Sky_Main.esm`, `Sky_Main_Grass.esp` and `Cyr_Main.esm` (the Skyrim and Cyrodiil province mods) are skipped. |
| `--min-interiors N` | Only emit cities with at least N interior cells named `<City>, ...` (default 4). |
| `--module-prefix P` | `require` prefix of this directory, used by the split `items.lua` (default `custom.scavenger-scramble.data`). |
| `--esmtool PATH` | After generating, compare WEAP and MISC record counts per file against `esmtool.exe dump -t` output (files over 60 MB are skipped). |

Each generated file starts with a header comment recording the generation time, the load order and the skipped files. The generator prints the path each content file was loaded from.

To check that the output loads under LuaJIT, run `pip install lupa`, then load each file with `lupa.luajit21.LuaRuntime()`.

## How the data is derived (summary; details in the contract)

- Records from later content files replace earlier records with the same id. Deleted records (record flag 0x20 or a `DELE` subrecord) are removed.
- Cell references are merged across files by reference number (owning master file + index), so a plugin that re-declares a cell can add, change or delete (`DELE`) references. A ref's stack count comes from `NAM9`. Moved-reference blocks (`MVRF` + `CNDT`) move the ref to the target exterior cell; the current load order contains none.
- A city's `exteriors` are the exterior cells named exactly like the city, plus exterior sub-districts named `<City>, ...` (Vivec's cantons, `Old Ebonheart, Docks` ...), so the whole walkable city is in bounds.
- A city's `source` is the earliest file that gave its exterior cells their name. For Tamriel Rebuilt cities that is `TR_Mainland.esm`.
- Spawn: the exterior NPC ref closest to the centroid of the exterior door refs, `posZ + 20`. `spawnCandidates` lists up to 8 entries: ranked NPCs, then doors, with the chosen spawn first. Override a spawn in `spawn_overrides.lua`.
- Keys are excluded by the key flag, a `key_` / `_key` id, or the word "key" in the name, because most vanilla and Tamriel Rebuilt keys do not set the flag. Potions are never `enchanted`, because ALCH `ENAM` is the effect list.
- `knownItems`: leveled item lists are expanded recursively (1 per possible outcome). Leveled creature lists are expanded to their NPCs and creatures, whose inventories count under `npc`. `owned` counts instances, so `owned <= direct`.
