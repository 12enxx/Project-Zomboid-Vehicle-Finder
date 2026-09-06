#!/usr/bin/env python3
"""
Runs the Vehicle Finder client Lua against a stubbed Project Zomboid API.

    pip install lupa && python3 tools/run_tests.py

It checks that every file parses as Lua 5.1 (the dialect the game uses) and
then drives the mod through a fake game: startup, hotkey, button clicks and
drags, searching, tracking, resizing and teardown.
"""

import glob
import os
import sys

try:
    from lupa import lua51 as lua
except ImportError:  # pragma: no cover - depends on the lupa build
    import lupa as lua

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD_LUA = os.path.join(ROOT, "Contents", "mods", "VehicleFinder", "42",
                       "media", "lua")


def mod_files():
    pattern = os.path.join(MOD_LUA, "**", "*.lua")
    return sorted(glob.glob(pattern, recursive=True))


def main():
    runtime = lua.LuaRuntime(unpack_returned_tuples=True)
    if runtime.eval("_VERSION") != "Lua 5.1":
        print("warning: not running Lua 5.1, results may differ from the game")

    files = mod_files()
    if not files:
        print("no lua files found under", MOD_LUA)
        return 1

    runtime.execute(open(os.path.join(ROOT, "tests", "pz_stub.lua")).read())

    print("loading %d mod files" % len(files))
    for path in files:
        rel = os.path.relpath(path, ROOT)
        try:
            runtime.execute(open(path).read())
        except lua.LuaError as exc:
            print("  FAIL %s\n    %s" % (rel, exc))
            return 1
        print("  ok   %s" % rel)
    print()

    failed = runtime.execute(open(
        os.path.join(ROOT, "tests", "test_vehiclefinder.lua")).read())
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
