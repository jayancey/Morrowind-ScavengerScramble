"""Run the Scavenger Scramble Lua tests under LuaJIT 2.1 (what the TES3MP server embeds).

Usage: python tests/run_tests.py [--lua51]
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD_DIR = ROOT / "scavenger-scramble"
FIXTURES = ROOT / "tests" / "fixtures"

try:
    if "--lua51" in sys.argv:
        from lupa import lua51 as lupa_mod
    else:
        from lupa import luajit21 as lupa_mod
except ImportError:
    print("lupa is required: python -m pip install lupa")
    sys.exit(2)

lua = lupa_mod.LuaRuntime(unpack_returned_tuples=True)


def resolve_module(name):
    """Map custom.scavenger-scramble.X to a file, preferring test fixtures for data modules."""
    prefix = "custom.scavenger-scramble."
    if not name.startswith(prefix):
        return None
    rel = name[len(prefix):].replace(".", "/") + ".lua"
    fixture = FIXTURES / rel
    if rel.startswith("data/") and fixture.exists():
        return str(fixture).replace("\\", "/")
    candidate = MOD_DIR / rel
    if candidate.exists():
        return str(candidate).replace("\\", "/")
    return None


g = lua.globals()
g.ROOT = str(ROOT).replace("\\", "/")
g.resolve_module = resolve_module

lua.execute(r"""
local searcher = function(name)
    local path = resolve_module(name)
    if path == nil then
        return "\n\tno scavenger module '" .. name .. "'"
    end
    local chunk, err = loadfile(path)
    if chunk == nil then error(err) end
    return chunk
end
local list = package.loaders or package.searchers
table.insert(list, 2, searcher)

stubs = dofile(ROOT .. "/tests/stubs.lua")
""")

print("Lua runtime:", lua.eval("_VERSION"), "(%s)" % lupa_mod.__name__)
try:
    lua.execute('dofile(ROOT .. "/tests/spec.lua")')
except Exception as exc:  # noqa: BLE001
    print(str(exc))
    sys.exit(1)
