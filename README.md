# Project Zomboid — Vehicle Finder

Find your favourite car.

A Build 42 mod for locating vehicles around you: one floating car button (drag
it anywhere) opens a list of every vehicle loaded near the player — name,
colour, distance and compass direction, nearest first. Click a row to track it:
the button then shows a direction pip and the distance even with the window
closed.

Author: **12enxx**

## Why the button is standalone instead of docked into the vanilla sidebar

The left sidebar (Inventory / Health / Crafting / …) is driven by vanilla's
`MainScreen.lua`. A mod that injects a button into that file breaks on every
Build 42 update — and that is exactly where the `require(...)` errors in the
earlier crash logs came from. So the button is standalone and registers itself
straight with the UI manager.

The difference from the first version: it is no longer just "not glued to
vanilla", it is designed not to collide with other mods either.

| Risk | How this mod avoids it |
| --- | --- |
| Patching vanilla files | Zero patches. No `require` of any vanilla file; the new UI classes are built inside an event (`OnGameStart`), after vanilla Lua has finished loading. That is why the earlier `require(...)` error cannot happen again. |
| Clashing with another mod's globals | Exactly **one** global: `VehicleFinder`. Every function and class lives inside it. |
| Overwriting vanilla or other mods' functions | Not a single vanilla function or table is overridden. The mod only calls `Events.*.Add` and builds its own UI. |
| Button landing on another mod's HUD | On first run the button position is picked automatically: candidate slots are probed against `UIManager.getUI()` and occupied ones are skipped. After that you can drag it and the position is saved. |
| Fighting over F8 | F8 is only the **default**. It is registered in Options → Key bindings (deduplicated, never overwriting another mod's binding), so you can rebind it if it clashes. The hotkey is also ignored while you are typing in chat or in the search field. |
| Vehicle mods (Filibuster, Autotsar, …) | The vehicle list is read read-only from `getCell():getVehicles()`. Modded vehicles with no `IGUI_VehicleName...` translation still show a readable name (`SuperTruck` → `Super Truck`) and are marked with `*`. Colours or IDs a given mod script does not expose are skipped rather than raising an error. |
| API changes in a future build | Every call into the game API is wrapped (`VF.safe`). If an API disappears, that feature goes dark — the UI does not crash with it. |

## Usage

- Clicking the car button does exactly what pressing **F8** does (open/close the
  window).
- **Drag** the button to move it; the position is saved.
- **Right-click** the button: open/close, button size (32–56 px), reset
  position, or hide the button (the hotkey still opens it).
- Type in the search field to filter by vehicle name.
- Click a row to track that vehicle, "Clear target" to stop.
- Every row shows the **map coordinates** (`10723, 9481`) next to the distance
  and compass direction. If you narrow the window the coordinates are hidden
  automatically so the name is not truncated.
- Two toggles under the search field:
  - **Range: nearby / all known** — extends the search to vehicles you have
    seen before (see below).
  - **Burnt: shown / hidden** — hides burnt wrecks without needing a new world.
    This overrides the sandbox option for this player.

## Dots on the world map

Open the world map (M) and vehicles appear as dots.

**A writing tool is required.** Dots only show while you are carrying a **pen or
pencil** (Pen, Pencil, RedPen, BluePen, GreenPen) — the same rule vanilla uses
for annotating the map by hand. Carry nothing and there are no dots, and the
window footer says `map dots need a pen` so the reason is visible. The dot
colour follows the pen you carry (coloured pens win, for legibility).

| Dot | Meaning |
| --- | --- |
| Filled square | loaded right now |
| Hollow square | from history, last seen there |
| Amber square + name | the vehicle you are tracking |

History dots only appear while **Range: all known** is on.

**Double-clicking** a row tracks the vehicle **and** opens the map centred on
its position.

Dots can be turned off from the car button's right-click menu → **Dots on the
world map**.

How it works: the mod puts its own transparent panel on top of the open map and
draws the dots itself. No symbols are injected into the map's symbol list (which
would mean managing symbol lifetimes and competing with other mods), and no
vanilla map function is hooked. Exactly one thing is borrowed from the map: the
world-to-map-pixel coordinate conversion.

Two things made the first version invisible:

1. Polling was attached to `OnTick`. Opening the map **pauses the game** in
   single player, and a paused game stops ticking — so the overlay was never
   built. It now uses `OnRenderTick` (per drawn frame, which keeps running while
   paused).
2. The correct map singleton is the global `ISWorldMap_instance` (set by
   `ISWorldMap.ShowWorldMap`); `ISWorldMap.instance` is only filled in later by
   the map's prerender. Both are checked now.

The coordinate conversion is `worldToUIX(x, y)` — two arguments, matching the
vanilla source. The single-argument form is still supported as a fallback, and
the mod records which one it used in `console.txt`:

```
[VehicleFinder] map projection: worldToUIX(x, y)
```

If neither exists, dots disable themselves and the rest of the mod keeps
working.

## Advanced search: vehicles you have seen

The hard limit: a vehicle only exists as an object while its chunk is loaded by
the game. There is no way to make a live scan reach past that — Lua cannot read
save data for a chunk that has not been loaded.

What is possible is **remembering**. Every vehicle that has come into range is
recorded (name, coordinates, burnt or not, and when it was last seen). Press
**Range: all known** and the list becomes a merge of the two:

| | Marked by | Contains |
| --- | --- | --- |
| Live | filled colour swatch | vehicles loaded right now |
| From history | hollow swatch + age (`2d`) + dimmer text | last seen at those coordinates |

Distance and compass direction for history entries are computed from the stored
coordinates, so they can be tracked like any other row — the car button keeps
pointing at them even when the vehicle is far out of range.

Technical notes:

- History lives in the **save's ModData**, so it belongs to that world and is
  deleted with it. Saves never mix.
- In multiplayer that ModData table is server-global, so there history is only
  kept in memory for the session.
- Capped at 500 entries; the longest-unseen ones are dropped first.
- If a vehicle comes back into range the live data wins — no duplicates.
- If a car has since been moved, the recorded coordinates can be stale. The
  sighting age (`2d`, `5h`) is on every row so you can judge how much to trust
  it.

## Sandbox option: burnt cars

Burnt cars cannot be driven — they are only good for parts. If you are looking
for something to drive, those wrecks are just noise in the list.

There is one sandbox option for it:

| Option | Default | Effect |
| --- | --- | --- |
| **Vehicle Finder → List burnt vehicles** | `on` | `off` = every burnt wreck is dropped from the results |

To set it: when creating a new world pick **Sandbox** (not an Apocalypse /
Survivor preset directly) → find the **Vehicle Finder** page in the category
list on the left.

Important: sandbox options are **per-world**, stored in the save and chosen at
world creation, so an existing save cannot change them from inside the game.
That is what the in-window **Burnt: shown / hidden** toggle is for — it
overrides the sandbox value for this player, on any save.

Burnt detection reads the vehicle script name (`...Burnt`), so wrecks from other
vehicle mods that follow the vanilla naming are filtered too. If the build
provides `isBurnt()`, that is used as a fallback. While the filter is active the
window footer says `burnt hidden`, so it is clear why a car is missing.

Search coverage is the area the game has loaded (the chunks around the player).
This mod does not read the save file or the map, so it knows nothing about
vehicles that have never been loaded.

## Icon

The icon was drawn for this mod — a 32×32 pixel-art car in a Project
Zomboid-ish palette (dark outline, dull brick-red body, blue-grey glass, flat
black tyres). The source is `tools/generate_icons.py` (the pixel grid is written
out by hand there); to regenerate:

```bash
pip install pillow
python3 tools/generate_icons.py
```

Output: `Contents/mods/VehicleFinder/42/media/textures/VehicleFinder_Car.png`,
`poster.png` and `preview.png`. If the texture fails to load for any reason the
button draws a simplified car with `drawRect`, so it never becomes an empty box.

## Install

What gets copied into the game is **the `VehicleFinder` folder only** — not the
repo folder, not the `Contents` folder. Destination:

```
Windows : %USERPROFILE%\Zomboid\mods\VehicleFinder\
Linux   : ~/Zomboid/mods/VehicleFinder/
```

The layout has to be exactly this — it is the Build 42 mod structure, which
differs from Build 41:

```
Zomboid/mods/VehicleFinder/
    common/                  <- must exist, and is meant to be empty
    42/
        mod.info             <- inside the 42 folder, not at the root
        poster.png
        media/
            lua/client/VehicleFinder/*.lua
            lua/shared/Translate/EN/IG_UI_EN.txt
            textures/VehicleFinder_Car.png
```

Two things keep a mod out of the Mods menu even when the folder is right:

1. `mod.info` placed at the mod root (Build 41 style) — in B42 it must be inside
   the `42/` version folder.
2. A missing `common/` folder — B42 silently skips the mod, with no error in
   `console.txt`.

Then enable it from the in-game **Mods** menu.

### If the mod still does not show up in the Mods menu

The most common remaining cause is one folder level too many.

| Wrong | Why |
| --- | --- |
| `Zomboid\mods\Project-Zomboid-Vehicle-Finder-...\Contents\mods\VehicleFinder\` | the repo/ZIP folder was copied too |
| `Zomboid\mods\Contents\mods\VehicleFinder\` | the `Contents` folder was copied too |
| `Zomboid\mods\VehicleFinder\VehicleFinder\` | Windows created a doubled folder on extract |
| `Zomboid\Workshop\...` | that folder is for Workshop uploads, not local mods |

The rule of thumb: **`...\Zomboid\mods\VehicleFinder\42\mod.info` must exist.**
If that path is right and it is still not read, try deleting
`Zomboid\mods\reset-mods-42_00.txt` (it caches the active mod list and sometimes
gets stuck), then check `%USERPROFILE%\Zomboid\console.txt`.

UI settings (button position and size, window geometry) are stored in
`Zomboid/VehicleFinder_settings.ini`, not in the save game — so they do not
affect multiplayer and do not mix with other mods' ModData.

## Structure

```
Contents/mods/VehicleFinder/
  common/                            required by B42, intentionally empty
  42/
    mod.info
    poster.png
    media/
      lua/client/VehicleFinder/
        VehicleFinder_01_Core.lua      namespace, settings, helpers, free-slot search
        VehicleFinder_02_Vehicles.lua  vehicle scan (safe for modded vehicles)
        VehicleFinder_03_Icon.lua      texture loader + fallback drawing
        VehicleFinder_04_Button.lua    floating button (drag, click, right-click)
        VehicleFinder_05_Window.lua    main window (search, list, tracking)
        VehicleFinder_06_Main.lua      key binding + events, the only entry point
        VehicleFinder_07_History.lua   record of vehicles seen before
        VehicleFinder_08_Map.lua       dots on the world map
      lua/shared/Translate/EN/IG_UI_EN.txt
      lua/shared/Translate/EN/Sandbox_EN.txt
      sandbox-options.txt              the "List burnt vehicles" sandbox option
      textures/VehicleFinder_Car.png
tests/                               PZ API stub + tests
tools/                               icon generator + test runner
```

Files are number-prefixed so the load order is deterministic (Core first).

## Tests

The mod runs outside the game: there is a small stub of the Project Zomboid API,
and the mod is driven through real scenarios (game start, hotkey, clicking and
dragging the button, search, tracking, resize, resolution change, quit to main
menu).

```bash
pip install lupa
python3 tools/run_tests.py
```

The tests also fail on any warning quietly raised by `VF.safe`, so a misspelled
API is caught without opening the game.
