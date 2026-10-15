#!/usr/bin/env python3
"""Generate scavenger-scramble/data/items.lua (+ items/part_NN.lua) and locations/*.lua from ESM/ESP files.

Parses the TES3 binary format directly (standard library only). See docs/DATA-CONTRACT.md
for the output specification and data/README.md for regeneration instructions.

Usage:
  python tools/gen_data.py --cfg "C:/Users/me/Documents/My Games/OpenMW/openmw.cfg"
      --out scavenger-scramble/data [--skip Foo.esp ...] [--include-all]
      [--min-interiors 4] [--esmtool F:/tes3mp/esmtool.exe]
"""
from __future__ import annotations

import argparse
import datetime
import math
import os
import re
import struct
import subprocess
import sys
import time
from pathlib import Path

DEFAULT_SKIPS = ["Sky_Main.esm", "Sky_Main_Grass.esp", "Cyr_Main.esm"]

ITEM_TYPES = {b"WEAP", b"ARMO", b"CLOT", b"BOOK", b"INGR", b"ALCH", b"MISC",
              b"LOCK", b"PROB", b"REPA", b"APPA", b"LIGH"}
INVENTORY_TYPES = {b"CONT", b"NPC_", b"CREA"}
OTHER_TYPES = {b"LEVI", b"LEVC", b"DOOR"}
WANTED = ITEM_TYPES | INVENTORY_TYPES | OTHER_TYPES | {b"CELL"}
ITEM_DATA_TAGS = {b"WPDT", b"AODT", b"CTDT", b"BKDT", b"IRDT", b"ALDT", b"MCDT",
                  b"LKDT", b"PBDT", b"RIDT", b"AADT", b"LHDT"}

WEAPON_SUB = ["shortblade", "longblade", "longblade", "blunt", "blunt", "blunt", "spear",
              "axe", "axe", "bow", "crossbow", "thrown", "arrow", "bolt"]
ARMOR_SUB = ["helmet", "cuirass", "lpauldron", "rpauldron", "greaves", "boots",
             "lgauntlet", "rgauntlet", "shield", "lbracer", "rbracer"]
CLOTH_SUB = ["pants", "shoes", "shirt", "belt", "robe", "rglove", "lglove", "skirt",
             "ring", "amulet"]
APPA_SUB = ["mortar", "alembic", "calcinator", "retort"]
KEY_ID_RE = re.compile(r"(^|_)key")
KEY_NAME_RE = re.compile(r"\bkey\b")

_u32 = struct.Struct("<I").unpack_from
_i32 = struct.Struct("<i").unpack_from
_f32 = struct.Struct("<f").unpack_from
_u16 = struct.Struct("<H").unpack_from
_ii = struct.Struct("<ii").unpack_from
_rechdr = struct.Struct("<4sIII").unpack_from
_subhdr = struct.Struct("<4sI").unpack_from
_cellhdr = struct.Struct("<Iii").unpack_from
_pos6 = struct.Struct("<6f").unpack_from
_npco = struct.Struct("<i32s").unpack_from


def cstr(buf: bytes, start: int, size: int) -> str:
    raw = buf[start:start + size]
    n = raw.find(b"\0")
    if n >= 0:
        raw = raw[:n]
    return raw.decode("cp1252", errors="replace")


# --------------------------------------------------------------------------- cfg

def parse_cfg(path: Path):
    """Return (data_dirs, content_files) from an openmw.cfg."""
    data_dirs, content = [], []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        key, val = key.strip(), val.strip()
        if key == "data":
            if val.startswith('"'):
                # OpenMW quoting: "..." with & escaping the next character (&& and &").
                out, i = [], 1
                while i < len(val):
                    c = val[i]
                    if c == "&" and i + 1 < len(val):
                        out.append(val[i + 1])
                        i += 2
                        continue
                    if c == '"':
                        break
                    out.append(c)
                    i += 1
                val = "".join(out)
            data_dirs.append(val)
        elif key == "content":
            content.append(val)
    return data_dirs, content


def resolve_content(data_dirs, content):
    """Resolve content file names (case-insensitively) against data dirs; later dirs win."""
    index = {}
    for d in data_dirs:
        p = Path(d)
        if not p.is_dir():
            continue
        try:
            for name in os.listdir(p):
                index[name.lower()] = p / name
        except OSError:
            continue
    resolved, missing = [], []
    for c in content:
        f = index.get(c.lower())
        if f is not None and f.is_file():
            resolved.append((c, f))
        else:
            missing.append(c)
    return resolved, missing


# --------------------------------------------------------------------------- world state

class World:
    def __init__(self):
        self.items = {}                              # id -> parsed item dict ("_rt" = record type)
        self.cont, self.npc, self.crea = {}, {}, {}  # id -> list[(count, item id)]
        self.levi, self.levc = {}, {}                # id -> list[entry id]
        self.doors = {}                              # id -> source file
        self.cells = {}       # cellkey -> dict(name, interior, gx, gy, source, last)
        self.cellrefs = {}    # cellkey -> dict(refkey -> (id, count, owned, x, y, z, rotZ))
        self.ref_loc = {}     # refkey -> cellkey (refnums are unique per owning file)
        self.masters_of = {}  # file (lower) -> [master file names, lower]
        self.load_index = {}
        self.moved_refs = 0
        self.moved_unresolved = 0
        self._intern = {}

    def intern(self, s):
        return self._intern.setdefault(s, s)


def parse_subs(buf, start, end):
    subs = []
    pos = start
    while pos + 8 <= end:
        tag, sz = _subhdr(buf, pos)
        subs.append((tag, pos + 8, sz))
        pos += 8 + sz
    return subs


def parse_item(rt, buf, subs):
    """Return (id, record dict or None if deleted/incomplete)."""
    rid = name = enam = None
    data = None
    deleted = False
    for tag, d, sz in subs:
        if tag == b"NAME":
            if rid is None:
                rid = cstr(buf, d, sz)
        elif tag == b"FNAM":
            name = cstr(buf, d, sz)
        elif tag == b"ENAM":
            enam = cstr(buf, d, sz)
        elif tag == b"DELE":
            deleted = True
        elif tag in ITEM_DATA_TAGS:
            data = (d, sz)
    if rid is None:
        return None, None
    rid = rid.lower()
    if deleted or data is None:
        return rid, None
    d, sz = data
    flags = 0
    if rt == b"WEAP":
        w, v, wt = struct.unpack_from("<fIH", buf, d)
        t, sub = "weapon", WEAPON_SUB[wt] if wt < len(WEAPON_SUB) else "misc"
    elif rt == b"ARMO":
        at, w, v = struct.unpack_from("<ifi", buf, d)
        t, sub = "armor", ARMOR_SUB[at] if 0 <= at < len(ARMOR_SUB) else "misc"
    elif rt == b"CLOT":
        ct, w, v = struct.unpack_from("<ifH", buf, d)
        t, sub = "clothing", CLOTH_SUB[ct] if 0 <= ct < len(CLOTH_SUB) else "misc"
    elif rt == b"BOOK":
        w, v, scroll = struct.unpack_from("<fii", buf, d)
        t, sub = "book", "scroll" if scroll else "book"
    elif rt == b"INGR":
        w, v = struct.unpack_from("<fi", buf, d)
        t = sub = "ingredient"
    elif rt == b"ALCH":
        w, v = struct.unpack_from("<fi", buf, d)
        t = sub = "potion"
    elif rt == b"MISC":
        w, v = struct.unpack_from("<fi", buf, d)
        flags = _i32(buf, d + 8)[0] if sz >= 12 else 0
        t, sub = "misc", "misc"
    elif rt in (b"LOCK", b"PROB", b"REPA"):
        w, v = struct.unpack_from("<fi", buf, d)
        t = sub = {b"LOCK": "lockpick", b"PROB": "probe", b"REPA": "repair"}[rt]
    elif rt == b"APPA":
        at, _q, w, v = struct.unpack_from("<iffi", buf, d)
        t, sub = "apparatus", APPA_SUB[at] if 0 <= at < 4 else "misc"
    else:  # LIGH
        w, v = struct.unpack_from("<fi", buf, d)
        flags = _i32(buf, d + 20)[0] if sz >= 24 else 0
        t = sub = "light"
    if not math.isfinite(w):
        w = 0.0
    return rid, {"name": name or "", "type": t, "subtype": sub, "value": int(v),
                 # ALCH uses ENAM for its effect list, not an enchantment id.
                 "weight": w, "enchanted": bool(enam) and rt != b"ALCH", "flags": flags, "_rt": rt}


def parse_inventory_record(buf, subs):
    rid = None
    inv = []
    deleted = False
    for tag, d, sz in subs:
        if tag == b"NAME" and rid is None:
            rid = cstr(buf, d, sz).lower()
        elif tag == b"NPCO" and sz >= 36:
            cnt, iid = _npco(buf, d)
            inv.append((cnt, cstr(iid, 0, 32).lower()))
        elif tag == b"DELE":
            deleted = True
    return rid, (None if deleted else inv)


def parse_leveled(buf, subs, entry_tag):
    rid = None
    entries = []
    deleted = False
    for tag, d, sz in subs:
        if tag == b"NAME" and rid is None:
            rid = cstr(buf, d, sz).lower()
        elif tag == entry_tag:
            entries.append(cstr(buf, d, sz).lower())
        elif tag == b"DELE":
            deleted = True
    return rid, (None if deleted else entries)


def parse_cell(world: World, buf, start, end, fname, rec_deleted):
    """Parse one CELL record and merge its header and references into world."""
    fkey = fname.lower()
    masters = world.masters_of.get(fkey, [])
    pos = start
    name = None
    flags = gx = gy = 0
    cell_deleted = rec_deleted
    in_refs = False
    cur = None            # [refkey, id, count, owned, pos6, deleted]
    pending_move = None   # after MVRF: "?" until CNDT/CNAM, then ("ext", gx, gy) / ("int", name)
    cur_move = None
    finished = []
    intern = world.intern
    while pos + 8 <= end:
        tag, sz = _subhdr(buf, pos)
        d = pos + 8
        pos = d + sz
        if tag == b"FRMR":
            if cur is not None:
                finished.append((cur, cur_move))
            in_refs = True
            raw = _u32(buf, d)[0]
            mi = raw >> 24
            if mi == 0:
                owner_file = fkey
            elif mi - 1 < len(masters):
                owner_file = masters[mi - 1]
            else:
                owner_file = "%s#%d" % (fkey, mi)
            cur = [(owner_file, raw & 0xFFFFFF), None, 1, False, None, False]
            cur_move = pending_move
            pending_move = None
            continue
        if tag == b"MVRF":
            if cur is not None:
                finished.append((cur, cur_move))
                cur = None
            in_refs = True
            pending_move = "?"
            continue
        if cur is None:
            if pending_move == "?":
                if tag == b"CNDT" and sz >= 8:
                    pending_move = ("ext",) + _ii(buf, d)
                elif tag == b"CNAM":
                    pending_move = ("int", cstr(buf, d, sz))
                continue
            if not in_refs:
                if tag == b"NAME":
                    name = cstr(buf, d, sz)
                elif tag == b"DATA" and sz >= 12:
                    flags, gx, gy = _cellhdr(buf, d)
                elif tag == b"DELE":
                    cell_deleted = True
            continue
        if tag == b"NAME":
            cur[1] = intern(cstr(buf, d, sz).lower())
        elif tag == b"DATA" and sz >= 24:
            cur[4] = _pos6(buf, d)
        elif tag == b"NAM9" and sz >= 4:
            cur[2] = _i32(buf, d)[0]
        elif tag == b"ANAM" or tag == b"CNAM":
            if sz > 1 and buf[d] != 0:
                cur[3] = True
        elif tag == b"DELE":
            cur[5] = True
    if cur is not None:
        finished.append((cur, cur_move))

    interior = bool(flags & 1)
    ckey = ("int", (name or "").lower()) if interior else ("ext", gx, gy)
    cells, cellrefs, ref_loc = world.cells, world.cellrefs, world.ref_loc
    if cell_deleted:
        cells.pop(ckey, None)
        for rk in cellrefs.pop(ckey, {}):
            ref_loc.pop(rk, None)
        return
    meta = cells.get(ckey)
    if meta is None:
        cells[ckey] = {"name": name or "", "interior": interior, "gx": gx, "gy": gy,
                       "source": fname, "namesrc": fname, "last": fname}
        cellrefs[ckey] = {}
    else:
        if name is not None and name != meta["name"]:
            meta["name"] = name
            meta["namesrc"] = fname  # file that gave the cell its current name
        meta["last"] = fname

    for ref, move in finished:
        rk, rid, count, owned, rpos, deleted = ref
        target = ckey
        if move is not None:
            world.moved_refs += 1
            if move == "?":
                world.moved_unresolved += 1
            elif move[0] == "ext":
                target = ("ext", move[1], move[2])
            else:
                target = ("int", move[1].lower())
        old = ref_loc.get(rk)
        if old is not None:
            refs_old = cellrefs.get(old)
            if refs_old is not None:
                refs_old.pop(rk, None)
        if deleted or rid is None:
            ref_loc.pop(rk, None)
            continue
        if target not in cells:
            if target[0] == "ext":
                cells[target] = {"name": "", "interior": False, "gx": target[1], "gy": target[2],
                                 "source": fname, "namesrc": fname, "last": fname}
            else:
                cells[target] = {"name": move[1], "interior": True, "gx": 0, "gy": 0,
                                 "source": fname, "namesrc": fname, "last": fname}
            cellrefs[target] = {}
        if rpos is None:
            rpos = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        cellrefs[target][rk] = (rid, count, owned, rpos[0], rpos[1], rpos[2], rpos[5])
        ref_loc[rk] = target


def load_file(world: World, fname: str, path: Path):
    buf = path.read_bytes()
    n = len(buf)
    pos = 0
    counts = {}
    fkey = fname.lower()
    while pos + 16 <= n:
        rt, size, _h, rflags = _rechdr(buf, pos)
        start = pos + 16
        end = start + size
        pos = end
        counts[rt] = counts.get(rt, 0) + 1
        if rt == b"TES3":
            world.masters_of[fkey] = [cstr(buf, d, sz).lower()
                                      for tag, d, sz in parse_subs(buf, start, end) if tag == b"MAST"]
            continue
        if rt not in WANTED:
            continue
        rdel = bool(rflags & 0x20)
        if rt == b"CELL":
            parse_cell(world, buf, start, end, fname, rdel)
            continue
        subs = parse_subs(buf, start, end)
        if rt in ITEM_TYPES:
            rid, rec = parse_item(rt, buf, subs)
            if rid is None:
                continue
            if rdel or rec is None:
                old = world.items.get(rid)
                if old is not None and old["_rt"] == rt:
                    del world.items[rid]
            else:
                rec["source"] = fname
                world.items[rid] = rec
        elif rt in INVENTORY_TYPES:
            rid, inv = parse_inventory_record(buf, subs)
            if rid is None:
                continue
            store = world.cont if rt == b"CONT" else world.npc if rt == b"NPC_" else world.crea
            if rdel or inv is None:
                store.pop(rid, None)
            else:
                store[rid] = inv
        elif rt == b"LEVI" or rt == b"LEVC":
            rid, ent = parse_leveled(buf, subs, b"INAM" if rt == b"LEVI" else b"CNAM")
            if rid is None:
                continue
            store = world.levi if rt == b"LEVI" else world.levc
            if rdel or ent is None:
                store.pop(rid, None)
            else:
                store[rid] = ent
        elif rt == b"DOOR":
            rid, deleted = None, False
            for tag, d, sz in subs:
                if tag == b"NAME" and rid is None:
                    rid = cstr(buf, d, sz).lower()
                elif tag == b"DELE":
                    deleted = True
            if rid is not None:
                if rdel or deleted:
                    world.doors.pop(rid, None)
                else:
                    world.doors[rid] = fname
    return counts, n


# --------------------------------------------------------------------------- derivation

def finalize_items(world: World):
    out = {}
    for rid, r in world.items.items():
        if not r["name"]:
            continue
        rt = r["_rt"]
        lname = r["name"].lower()
        subtype = r["subtype"]
        if rt == b"MISC":
            if rid.startswith("gold_"):
                continue
            # Contract rule (key flag, or "key" in id/name with value 0) plus a stricter
            # heuristic: vanilla/TR keys mostly lack the flag and are worth 300 gold.
            if ((r["flags"] & 1) or KEY_ID_RE.search(rid) or KEY_NAME_RE.search(lname)
                    or (("key" in rid or "key" in lname) and r["value"] == 0)):
                continue
            if rid.startswith("misc_soulgem") or "soul gem" in lname:
                subtype = "soulgem"
        if rt == b"LIGH" and not (r["flags"] & 0x02):
            continue
        e = {"name": r["name"], "type": r["type"], "subtype": subtype, "value": r["value"],
             "weight": r["weight"], "source": r["source"]}
        if r["enchanted"]:
            e["enchanted"] = True
        if "unique" in rid or "artifact" in rid:
            e["unique"] = True
        out[rid] = e
    return out


class Resolver:
    """Expands leveled lists and inventories, memoised."""

    def __init__(self, world: World, items: dict):
        self.w = world
        self.items = items
        self.levi_cache = {}
        self.inv_cache = {}

    def levi_leaves(self, lid, stack=None):
        if lid in self.levi_cache:
            return self.levi_cache[lid]
        if stack is None:
            stack = set()
        if lid in stack:  # cycle guard
            return frozenset()
        stack.add(lid)
        leaves = set()
        for e in self.w.levi.get(lid, ()):
            if e in self.items:
                leaves.add(e)
            elif e in self.w.levi:
                leaves |= self.levi_leaves(e, stack)
        stack.discard(lid)
        res = frozenset(leaves)
        self.levi_cache[lid] = res
        return res

    def inventory(self, kind, store, oid):
        key = (kind, oid)
        if key in self.inv_cache:
            return self.inv_cache[key]
        out = {}
        for cnt, iid in store.get(oid, ()):
            if iid in self.items:
                out[iid] = out.get(iid, 0) + max(1, abs(cnt))
            elif iid in self.w.levi:
                for leaf in self.levi_leaves(iid):
                    out[leaf] = out.get(leaf, 0) + 1
        self.inv_cache[key] = out
        return out

    def levc_actors(self, cid, stack=None):
        if stack is None:
            stack = set()
        if cid in stack:
            return set()
        stack.add(cid)
        res = set()
        for e in self.w.levc.get(cid, ()):
            if e in self.w.npc or e in self.w.crea:
                res.add(e)
            elif e in self.w.levc:
                res |= self.levc_actors(e, stack)
        return res


def city_key(name):
    """Location key: valid as a file name and a Lua module name ([a-z_][a-z0-9_]*)."""
    key = re.sub(r"[^a-z0-9]", "_", name.lower())
    if not key or key[0].isdigit():
        key = "loc_" + key
    return key


def ext_desc(gx, gy):
    return "%d, %d" % (gx, gy)


def build_locations(world: World, items: dict, min_interiors: int):
    res = Resolver(world, items)
    ext_by_name = {}
    interiors = []
    for ck, m in world.cells.items():
        if m["interior"]:
            if m["name"]:
                interiors.append((ck, m))
        elif m["name"]:
            ext_by_name.setdefault(m["name"], []).append((ck, m))
    # Exterior sub-districts ("Vivec, Arena", "Old Ebonheart, Docks") belong to the parent city
    # when an exterior cell named exactly like the parent exists; they are not cities themselves.
    districts = {}
    for n in list(ext_by_name):
        parent = n.split(", ", 1)[0]
        if parent != n and parent in ext_by_name:
            districts.setdefault(parent, []).extend(ext_by_name.pop(n))
    locations = {}
    for cname, core in ext_by_name.items():
        prefix = cname + ", "
        ints = [(ck, m) for ck, m in interiors if m["name"].startswith(prefix)]
        exts = core + districts.get(cname, [])
        if len(ints) < min_interiors:
            continue
        exts.sort(key=lambda e: (e[1]["gx"], e[1]["gy"]))
        ext_descs = sorted(ext_desc(m["gx"], m["gy"]) for _, m in exts)
        ext_set = set(ext_descs)

        # ---- spawn selection
        doors, npcs = [], []
        for ck, _m in exts:
            for rid, _cnt, _owned, x, y, z, rz in world.cellrefs.get(ck, {}).values():
                if rid in world.doors:
                    doors.append((rid, x, y, z, rz))
                elif rid in world.npc:
                    npcs.append((rid, x, y, z, rz))
        m0 = min(core, key=lambda e: (e[1]["gx"], e[1]["gy"]))[1]
        if doors:
            cx = sum(d[1] for d in doors) / len(doors)
            cy = sum(d[2] for d in doors) / len(doors)
        else:
            cx, cy = m0["gx"] * 8192 + 4096, m0["gy"] * 8192 + 4096

        def ranked(lst, kind):
            out = []
            for rid, x, y, z, rz in lst:
                # Cell from the position, so the teleport cell always matches the coordinates.
                desc = ext_desc(math.floor(x / 8192), math.floor(y / 8192))
                if desc not in ext_set:
                    continue
                out.append(((x - cx) ** 2 + (y - cy) ** 2, rid, desc, x, y, z, rz, kind))
            out.sort()
            return out

        ranked_all = ranked(npcs, "npc") + ranked(doors, "door")
        cands = [{"cell": c[2], "posX": c[3], "posY": c[4], "posZ": c[5] + 20.0, "rotZ": c[6],
                  "refId": c[1], "kind": c[7]} for c in ranked_all[:8]]
        if cands:
            spawn = {k: cands[0][k] for k in ("cell", "posX", "posY", "posZ", "rotZ")}
        else:
            spawn = {"cell": ext_desc(m0["gx"], m0["gy"]), "posX": m0["gx"] * 8192 + 4096.0,
                     "posY": m0["gy"] * 8192 + 4096.0, "posZ": 1000.0, "rotZ": 0.0,
                     "spawnGuess": True}

        # ---- known items
        known = {}

        def bump(iid, field, n, owned=0):
            e = known.get(iid)
            if e is None:
                e = known[iid] = {"count": 0, "owned": 0, "direct": 0, "container": 0, "npc": 0}
            e[field] += n
            e["count"] += n
            e["owned"] += owned

        for ck, _m in exts + ints:
            for ref in world.cellrefs.get(ck, {}).values():
                rid, cnt, owned = ref[0], ref[1], ref[2]
                if rid in items:
                    n = max(1, abs(cnt))
                    bump(rid, "direct", n, n if owned else 0)
                elif rid in world.levi:
                    for leaf in res.levi_leaves(rid):
                        bump(leaf, "direct", 1, 1 if owned else 0)
                elif rid in world.cont:
                    for iid, n in res.inventory("c", world.cont, rid).items():
                        bump(iid, "container", n)
                elif rid in world.npc:
                    for iid, n in res.inventory("n", world.npc, rid).items():
                        bump(iid, "npc", n)
                elif rid in world.crea:
                    for iid, n in res.inventory("r", world.crea, rid).items():
                        bump(iid, "npc", n)
                elif rid in world.levc:
                    for actor in sorted(res.levc_actors(rid)):
                        if actor in world.npc:
                            inv = res.inventory("n", world.npc, actor)
                        else:
                            inv = res.inventory("r", world.crea, actor)
                        for iid, n in inv.items():
                            bump(iid, "npc", n)
        source = min((m["namesrc"] for _, m in core),
                     key=lambda s: world.load_index.get(s.lower(), 1 << 30))
        key = city_key(cname)
        if key in locations:  # two names that normalise identically
            n = 2
            while "%s_%d" % (key, n) in locations:
                n += 1
            print("WARNING: location key %s already used; %r written as %s_%d" % (key, cname, key, n))
            key = "%s_%d" % (key, n)
        locations[key] = {
            "name": cname, "source": source, "exteriors": ext_descs,
            "interiors": sorted(m["name"] for _, m in ints),
            "spawn": spawn, "spawnCandidates": cands, "knownItems": known,
        }
    return locations


# --------------------------------------------------------------------------- Lua output

_LUA_ESC = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\r": "\\r", "\t": "\\t"}


def lua_str(s: str) -> str:
    out = []
    for ch in s:
        e = _LUA_ESC.get(ch)
        if e is not None:
            out.append(e)
        elif ord(ch) < 32 or ord(ch) == 127:
            out.append("\\%03d" % ord(ch))
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def lua_val(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, int):
        return str(v)
    if not math.isfinite(v):
        return "0"
    r = round(v, 4)
    if r == int(r) and abs(r) < 1e15:
        return "%d.0" % int(r)
    return repr(r)


def lua_fields(d: dict, order) -> str:
    return "{ " + ", ".join("%s = %s" % (k, lua_val(d[k])) for k in order if k in d) + " }"


ITEM_ORDER = ("name", "type", "subtype", "value", "weight", "source", "enchanted", "unique")
POS_ORDER = ("cell", "posX", "posY", "posZ", "rotZ")
CAND_ORDER = ("cell", "posX", "posY", "posZ", "rotZ", "refId", "kind")
KNOWN_ORDER = ("count", "owned", "direct", "container", "npc")


def header(what, load_order, skips):
    lines = ["-- %s: generated by tools/gen_data.py. Do not edit by hand; see data/README.md." % what,
             "-- Generated: %s" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
             "-- Load order:"]
    lines += ["--   %2d. %s" % (i + 1, f) for i, f in enumerate(load_order)]
    lines.append("-- Skipped (--skip): %s" % (", ".join(skips) if skips else "(none)"))
    return "\n".join(lines) + "\n"


ITEMS_SPLIT_AT = 12000     # above this many entries, items.lua is split into parts
ITEMS_PER_PART = 6000
_MODULE_KEY_RE = re.compile(r"^[a-z_][a-z0-9_]*$")


def _clear_stale(directory: Path, keep: set):
    """Remove generated .lua files in directory that are not part of this run's output."""
    removed = []
    if directory.is_dir():
        for f in directory.glob("*.lua"):
            if f.name not in keep:
                f.unlink()
                removed.append("%s/%s" % (directory.name, f.name))
    return removed


def _items_table(items, keys) -> str:
    out = ["return {\n"]
    out.extend("  [%s] = %s,\n" % (lua_str(k), lua_fields(items[k], ITEM_ORDER)) for k in keys)
    out.append("}\n")
    return "".join(out)


def write_items(out_dir: Path, items, load_order, skips, module_prefix):
    """Write items.lua; above ITEMS_SPLIT_AT entries write items/part_NN.lua and a merging items.lua.

    Returns (part names, removed stale files)."""
    keys = sorted(items)
    parts_dir = out_dir / "items"
    hdr = header("items.lua", load_order, skips)
    if len(keys) <= ITEMS_SPLIT_AT:
        (out_dir / "items.lua").write_text(hdr + _items_table(items, keys), encoding="utf-8", newline="\n")
        removed = _clear_stale(parts_dir, set())
        if parts_dir.is_dir() and not any(parts_dir.iterdir()):
            parts_dir.rmdir()
        return [], removed
    parts_dir.mkdir(parents=True, exist_ok=True)
    names = []
    for n, i in enumerate(range(0, len(keys), ITEMS_PER_PART), 1):
        name = "part_%02d" % n
        names.append(name)
        text = header("items/%s.lua" % name, load_order, skips) + _items_table(items, keys[i:i + ITEMS_PER_PART])
        (parts_dir / (name + ".lua")).write_text(text, encoding="utf-8", newline="\n")
    removed = _clear_stale(parts_dir, {n + ".lua" for n in names})
    out = [hdr,
           "-- Split into %d parts to stay under LuaJIT's 65536-constants-per-function limit.\n" % len(names),
           "local parts = { %s }\n" % ", ".join(lua_str(n) for n in names),
           "local items = {}\n",
           "for _, part in ipairs(parts) do\n",
           "  for k, v in pairs(require(%s .. part)) do\n" % lua_str(module_prefix + ".items."),
           "    items[k] = v\n",
           "  end\n",
           "end\n",
           "return items\n"]
    (out_dir / "items.lua").write_text("".join(out), encoding="utf-8", newline="\n")
    return names, removed


def location_lua(L) -> str:
    out = ["return {\n",
           "  name = %s,\n" % lua_str(L["name"]),
           "  source = %s,\n" % lua_str(L["source"]),
           "  exteriors = { %s },\n" % ", ".join(lua_str(s) for s in L["exteriors"]),
           "  interiors = {\n"]
    out.extend("    %s,\n" % lua_str(s) for s in L["interiors"])
    out.append("  },\n")
    out.append("  spawn = %s,\n" % lua_fields(L["spawn"], POS_ORDER))
    if L["spawn"].get("spawnGuess"):
        out.append("  spawnGuess = true,\n")
    out.append("  spawnCandidates = {\n")
    out.extend("    %s,\n" % lua_fields(c, CAND_ORDER) for c in L["spawnCandidates"])
    out.append("  },\n")
    out.append("  knownItems = {\n")
    for iid in sorted(L["knownItems"]):
        out.append("    [%s] = %s,\n" % (lua_str(iid), lua_fields(L["knownItems"][iid], KNOWN_ORDER)))
    out.append("  },\n")
    out.append("}\n")
    return "".join(out)


def write_locations(out_dir: Path, locs, load_order, skips):
    """Write data/locations/index.lua plus one data/locations/<key>.lua shard per location.

    Returns the list of removed stale files."""
    loc_dir = out_dir / "locations"
    loc_dir.mkdir(parents=True, exist_ok=True)
    written = set()
    for key, L in locs.items():
        if not _MODULE_KEY_RE.match(key):
            raise ValueError("invalid location key %r" % key)
        text = header("locations/%s.lua" % key, load_order, skips) + location_lua(L)
        (loc_dir / (key + ".lua")).write_text(text, encoding="utf-8", newline="\n")
        written.add(key + ".lua")
    out = [header("locations/index.lua", load_order, skips), "return {\n"]
    for key in sorted(locs, key=lambda k: (locs[k]["name"].lower(), k)):
        L = locs[key]
        out.append("  { key = %s, name = %s, source = %s, exteriors = %d, interiors = %d, "
                   "knownItems = %d, spawnGuess = %s },\n" % (
                       lua_str(key), lua_str(L["name"]), lua_str(L["source"]), len(L["exteriors"]),
                       len(L["interiors"]), len(L["knownItems"]),
                       "true" if L["spawn"].get("spawnGuess") else "false"))
    out.append("}\n")
    (loc_dir / "index.lua").write_text("".join(out), encoding="utf-8", newline="\n")
    written.add("index.lua")
    removed = _clear_stale(loc_dir, written)
    legacy = out_dir / "locations.lua"
    if legacy.exists():  # pre-sharding monolithic file: too many constants for LuaJIT
        legacy.unlink()
        removed.append("locations.lua")
    return removed


# --------------------------------------------------------------------------- esmtool check

def esmtool_check(esmtool, files, all_counts, max_size=60_000_000):
    print("\nesmtool cross-check (WEAP, MISC record counts):")
    for fname, path in files:
        if path.stat().st_size > max_size:
            print("  %-28s skipped (larger than %d MB)" % (fname, max_size // 1_000_000))
            continue
        for rt in ("WEAP", "MISC"):
            try:
                p = subprocess.run([esmtool, "dump", "-t", rt, str(path)], capture_output=True,
                                   text=True, encoding="cp1252", errors="replace", timeout=900)
                theirs = sum(1 for ln in p.stdout.splitlines() if ln.startswith("Record: %s " % rt))
            except Exception as exc:  # noqa: BLE001
                theirs = "error: %s" % exc
            ours = all_counts[fname].get(rt.encode(), 0)
            print("  %-28s %s ours=%s esmtool=%s %s" % (
                fname, rt, ours, theirs, "ok" if theirs == ours else "MISMATCH"))


# --------------------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cfg", required=True, type=Path, help="path to openmw.cfg")
    ap.add_argument("--out", default=Path("scavenger-scramble/data"), type=Path, help="output directory")
    ap.add_argument("--skip", action="append", default=[], help="content file to skip (repeatable)")
    ap.add_argument("--include-all", action="store_true",
                    help="do not apply the default skip list (%s)" % ", ".join(DEFAULT_SKIPS))
    ap.add_argument("--min-interiors", type=int, default=4,
                    help="minimum '<City>, ...' interiors for a city to be emitted (default 4)")
    ap.add_argument("--module-prefix", default="custom.scavenger-scramble.data",
                    help="require() prefix of the data directory, used when items.lua is split")
    ap.add_argument("--esmtool", help="path to esmtool.exe; cross-checks WEAP/MISC record counts")
    args = ap.parse_args(argv)

    t0 = time.perf_counter()
    data_dirs, content = parse_cfg(args.cfg)
    skips = ([] if args.include_all else list(DEFAULT_SKIPS)) + args.skip
    skipset = {s.lower() for s in skips}
    resolved, missing = resolve_content(data_dirs, content)
    for m in missing:
        print("WARNING: content file not found in any data dir: %s" % m, file=sys.stderr)
    files = [(f, p) for f, p in resolved if f.lower() not in skipset]
    skipped = [f for f, _ in resolved if f.lower() in skipset]

    world = World()
    world.load_index = {f.lower(): i for i, (f, _) in enumerate(files)}
    all_counts = {}
    print("Loading %d content files (%d skipped):" % (len(files), len(skipped)))
    for fname, path in files:
        t1 = time.perf_counter()
        counts, size = load_file(world, fname, path)
        all_counts[fname] = counts
        print("  %-28s %7.1f MB %8d records %6.2fs  %s" % (
            fname, size / 1e6, sum(counts.values()), time.perf_counter() - t1, path))
    for s in skipped:
        print("  (skipped) %s" % s)

    items = finalize_items(world)
    locs = build_locations(world, items, args.min_interiors)
    args.out.mkdir(parents=True, exist_ok=True)
    load_order = [f for f, _ in files]
    parts, removed = write_items(args.out, items, load_order, skipped, args.module_prefix)
    removed += write_locations(args.out, locs, load_order, skipped)

    by_type = {}
    for e in items.values():
        by_type[e["type"]] = by_type.get(e["type"], 0) + 1
    print("\nItems: %d  (%s)" % (len(items), ", ".join("%s %d" % kv for kv in sorted(by_type.items()))))
    print("Locations: %d  (%s)" % (len(locs), ", ".join(sorted(locs))))
    nrefs = sum(len(r) for r in world.cellrefs.values())
    print("Cells: %d, references: %d, moved refs: %d (target unresolved: %d)" % (
        len(world.cells), nrefs, world.moved_refs, world.moved_unresolved))
    guesses = sorted(k for k, L in locs.items() if L["spawn"].get("spawnGuess"))
    if guesses:
        print("Spawn guessed (no exterior NPC or door refs): %s" % ", ".join(guesses))
    print("Wrote %s%s and %s (index + %d shards) in %.1fs" % (
        args.out / "items.lua", " (%d parts)" % len(parts) if parts else "",
        args.out / "locations", len(locs), time.perf_counter() - t0))
    if removed:
        print("Removed stale files: %s" % ", ".join(sorted(removed)))
    if args.esmtool:
        esmtool_check(args.esmtool, files, all_counts)
    return 0


if __name__ == "__main__":
    sys.exit(main())
