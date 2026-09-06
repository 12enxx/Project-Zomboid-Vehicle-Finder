--[[ Headless behaviour tests for Vehicle Finder. Run: python3 tools/run_tests.py ]]

local VF = VehicleFinder
local passed, failed = 0, 0
local warnings = {}

-- capture warnings; VF.safe swallows errors, so a silent warning is a failure
local originalWarn = VF.warn
VF.warn = function(msg) table.insert(warnings, tostring(msg)) end

local function check(name, ok, detail)
    if ok then
        passed = passed + 1
        print("  ok   " .. name)
    else
        failed = failed + 1
        print("  FAIL " .. name .. (detail and ("  -> " .. tostring(detail)) or ""))
    end
end

local function noWarnings(label)
    if #warnings > 0 then
        check(label .. " (no warnings)", false, table.concat(warnings, " | "))
        warnings = {}
    else
        check(label .. " (no warnings)", true)
    end
end

local function inStack(element)
    for _, e in ipairs(Stub.uiStack) do if e == element then return true end end
    return false
end

print("compass + geometry")
check("north", VF.compass(0, -10) == "N", VF.compass(0, -10))
check("east", VF.compass(10, 0) == "E", VF.compass(10, 0))
check("south west", VF.compass(-10, 10) == "SW", VF.compass(-10, 10))
local sx, sy = VF.worldToScreenDir(1, 0)
check("iso projection normalised", math.abs(sx * sx + sy * sy - 1) < 0.001)
check("clamp", VF.clamp(50, 0, 10) == 10 and VF.clamp(-5, 0, 10) == 0)

print("settings round trip")
VF.loadConfig()
check("defaults applied", VF.config.buttonSize == 40 and VF.config.buttonVisible == true)
VF.config.buttonX, VF.config.buttonY, VF.config.buttonSize = 111, 222, 48
VF.saveConfig()
VF.loadConfig()
check("saved values reloaded",
      VF.config.buttonX == 111 and VF.config.buttonY == 222 and VF.config.buttonSize == 48)
VF.config.buttonX, VF.config.buttonY, VF.config.buttonSize = -1, -1, 40
VF.saveConfig()

print("key binding is additive and deduplicated")
VF.keyBindingRegistered = false
VF.registerKeyBinding()
VF.keyBindingRegistered = false
VF.registerKeyBinding()
local count = 0
for _, entry in ipairs(keyBinding) do
    if entry.value == VF.KEY_TOGGLE then count = count + 1 end
end
check("registered exactly once", count == 1, count)
check("default key is F8", VF.getToggleKey() == Keyboard.KEY_F8)
Stub.keys[VF.KEY_TOGGLE] = Keyboard.KEY_F9
check("respects a rebind", VF.getToggleKey() == Keyboard.KEY_F9)
Stub.keys[VF.KEY_TOGGLE] = Keyboard.KEY_F8

print("world setup")
Stub.setPlayer(100, 100)
Stub.vehicles = {
    Stub.makeVehicle(1, "Base.CarNormal", 110, 100, { 0.5, 0.2, 0.2 }),
    Stub.makeVehicle(2, "Base.PickUpTruck", 100, 80),
    Stub.makeVehicle(3, "AwesomeCarMod.SuperTruck", 160, 160),
}
-- the collection type changed in 42.17 (ArrayList -> Set); both must work
for _, style in ipairs({ "set", "list" }) do
    Stub.vehicleCollection = style
    local found = VF.scanVehicles()
    check("vehicles read from a " .. style .. " collection", #found == 3, #found)
end
Stub.vehicleCollection = "set"
local entries = VF.scanVehicles()
check("all vehicles found", #entries == 3, #entries)
check("sorted by distance", entries[1].dist < entries[2].dist and entries[2].dist < entries[3].dist)
check("translated name", entries[1].name == "Chevalier Cerise", entries[1].name)
check("vanilla not flagged as modded", entries[1].modded == false)
local modded
for _, e in ipairs(entries) do if e.id == "3" then modded = e end end
check("mod vehicle detected", modded ~= nil and modded.modded == true)
check("mod vehicle name falls back to a readable name",
      modded ~= nil and modded.name == "Super Truck", modded and modded.name)
check("name splits letters, digits and words",
      VF.prettifyName("SmallCar02Burnt") == "Small Car 02 Burnt",
      VF.prettifyName("SmallCar02Burnt"))
check("colour read when available", entries[1].r ~= nil)
check("missing colour tolerated", entries[2].r == nil)
check("direction", entries[1].dir == "E" and entries[2].dir == "N")
noWarnings("scan")

print("burnt wrecks follow the sandbox option")
local savedVehicles = Stub.vehicles
Stub.vehicles = {
    Stub.makeVehicle(1, "Base.CarNormal", 110, 100),
    Stub.makeVehicle(9, "Base.SmallCar02Burnt", 105, 100),
    Stub.makeVehicle(10, "SomeCarMod.RustyThing", 106, 100, nil, true),
}
SandboxVars.VehicleFinder.ShowBurnt = true
check("burnt listed when the option is on", #VF.scanVehicles() == 3, #VF.scanVehicles())
SandboxVars.VehicleFinder.ShowBurnt = false
local drivable = VF.scanVehicles()
check("burnt dropped when the option is off", #drivable == 1, #drivable)
check("the drivable one survives", drivable[1] ~= nil and drivable[1].name == "Chevalier Cerise",
      drivable[1] and drivable[1].name)
check("detected from the script name", VF.isBurntVehicle(Stub.vehicles[2]) == true)
check("detected from isBurnt() when a build exposes it",
      VF.isBurntVehicle(Stub.vehicles[3]) == true)
check("a normal car is not flagged", VF.isBurntVehicle(Stub.vehicles[1]) == false)
local savedSandbox = SandboxVars.VehicleFinder
SandboxVars.VehicleFinder = nil
check("missing sandbox option lists everything", #VF.scanVehicles() == 3, #VF.scanVehicles())
SandboxVars.VehicleFinder = savedSandbox
SandboxVars.VehicleFinder.ShowBurnt = true
Stub.vehicles = savedVehicles
noWarnings("burnt filter")

print("button lives on its own, away from other mods' HUD")
-- occupy the first candidate slot with a fake element from "another mod"
Stub.addFakeUI(12, 1080 - 40 - 16, 40, 40)
Stub.fire("OnGameStart")
check("button created", VF.button ~= nil)
check("button added to UI manager", VF.button ~= nil and inStack(VF.button))
check("button avoided the occupied spot",
      VF.button ~= nil and not (VF.button:getX() == 12 and VF.button:getY() == 1024),
      VF.button and (VF.button:getX() .. "," .. VF.button:getY()))
check("button inside the screen",
      VF.button:getX() >= 0 and VF.button:getY() >= 0
      and VF.button:getX() + VF.button:getWidth() <= 1920
      and VF.button:getY() + VF.button:getHeight() <= 1080)
noWarnings("startup")

print("button paints")
Stub.drawCalls = {}
VF.button:prerender()
local drewTexture = false
for _, call in ipairs(Stub.drawCalls) do if call.kind == "texture" then drewTexture = true end end
check("car texture drawn", drewTexture)
VF.button.mouseOver = true
VF.button:update()
VF.button:prerender()
check("hover tooltip drawn", #Stub.drawCalls > 0)
VF.button.mouseOver = false
noWarnings("button paint")

print("fallback icon when the texture is missing")
local savedTextures = Stub.textures
Stub.textures = {}
VF._iconResolved, VF._icon = false, nil
Stub.drawCalls = {}
VF.button:prerender()
local rects = 0
for _, call in ipairs(Stub.drawCalls) do if call.kind == "rect" then rects = rects + 1 end end
check("fallback car drawn with rectangles", rects >= 10, rects)
warnings = {}   -- the "texture not found" warning is expected here
Stub.textures = savedTextures
VF._iconResolved, VF._icon = false, nil

print("click opens the window, drag does not")
VF.button:onMouseDown(5, 5)
VF.button:onMouseUp(5, 5)
check("window opened by click", VF.isWindowOpen())
check("window in UI manager", inStack(VF.window))
VF.button:onMouseDown(5, 5)
VF.button:onMouseUp(5, 5)
check("second click closes", not VF.isWindowOpen())
check("window removed from UI manager", VF.window == nil)

local startX, startY = VF.button:getX(), VF.button:getY()
VF.button:onMouseDown(5, 5)
VF.button:onMouseMove(30, -40)
VF.button:onMouseUp(5, 5)
check("drag moved the button", VF.button:getX() == startX + 30 and VF.button:getY() == startY - 40)
check("drag did not toggle the window", not VF.isWindowOpen())
check("dragged position persisted", VF.config.buttonX == VF.button:getX())

VF.button:onMouseDown(5, 5)
VF.button:onMouseMove(9000, 9000)
VF.button:onMouseUp(5, 5)
check("drag clamped to the screen",
      VF.button:getX() + VF.button:getWidth() <= 1920
      and VF.button:getY() + VF.button:getHeight() <= 1080)
noWarnings("button interaction")

print("hotkey")
Stub.fire("OnKeyPressed", Keyboard.KEY_F8)
check("hotkey opened the window", VF.isWindowOpen())
Stub.fire("OnKeyPressed", Keyboard.KEY_F9)
check("other keys ignored", VF.isWindowOpen())
VF.window.searchEntry.focused = true
Stub.fire("OnKeyPressed", Keyboard.KEY_F8)
check("hotkey ignored while typing in the search box", VF.isWindowOpen())
VF.window.searchEntry.focused = false
noWarnings("hotkey")

print("window list")
local window = VF.window
check("list populated", window.list:size() == 3, window.list:size())
Stub.drawCalls = {}
window.list:drawAll()
check("rows painted", #Stub.drawCalls > 0)

window.searchEntry:setText("truck")
Stub.time = Stub.time + 1000
window:update()
check("search filters the list", window.list:size() == 2, window.list:size())
window.searchEntry:setText("chevalier")
Stub.time = Stub.time + 1000
window:update()
check("search matches translated names", window.list:size() == 1, window.list:size())
window.searchEntry:setText("")
Stub.time = Stub.time + 1000
window:update()
check("clearing the search restores the list", window.list:size() == 3)
noWarnings("window list")

print("tracking")
window.list:clickRow(1)
check("row click tracks the vehicle", VF.trackedId == "1", VF.trackedId)
check("tracked info available", VF.trackedInfo ~= nil and VF.trackedInfo.dir == "E")
Stub.drawCalls = {}
VF.button:prerender()
check("tracker pip drawn on the button", #Stub.drawCalls > 4)
Stub.drawCalls = {}
window:prerender()
check("window footer drawn", #Stub.drawCalls > 0)

-- tracked vehicle leaves the loaded area
local kept = Stub.vehicles
Stub.vehicles = { kept[2], kept[3] }
Stub.time = Stub.time + 1000
window:update()
check("out of range target handled", VF.trackedInfo == nil and VF.trackedId == "1")
Stub.drawCalls = {}
window:prerender()
VF.button:prerender()
check("out of range still paints", #Stub.drawCalls > 0)
Stub.vehicles = kept
Stub.time = Stub.time + 1000
window:update()
check("target recovered when back in range", VF.trackedInfo ~= nil)
window.clearButton:click()
check("clear button clears the target", VF.trackedId == nil)
noWarnings("tracking")

print("coordinates are part of every entry")
check("live entry carries map coordinates",
      entries[1].x == 110 and entries[1].y == 100,
      entries[1].x .. "," .. entries[1].y)

print("advanced search: vehicles remembered from earlier")
local function wipeHistory()
    VF.history.reset()
    VF.history.clear()
end
wipeHistory()
Stub.worldHours = 100
Stub.vehicles = {
    Stub.makeVehicle(1, "Base.CarNormal", 110, 100, { 0.5, 0.2, 0.2 }),
    Stub.makeVehicle(2, "Base.PickUpTruck", 100, 80),
}
VF.scanVehicles()                       -- walks past them, writing the log
check("sightings written to the log", VF.history.count() == 2, VF.history.count())

Stub.vehicles = {}                      -- drive away, chunks unload
Stub.worldHours = 148                   -- two in-game days later
check("nearby search sees nothing now", #VF.searchEntries(false) == 0)
local known = VF.searchEntries(true)
check("wider search finds them again", #known == 2, #known)
check("remembered entries are flagged", known[1].remembered == true)
check("distance recomputed from the stored spot",
      math.floor(known[1].dist) == 10, known[1].dist)
check("direction recomputed", known[1].dir == "E", known[1].dir)
check("age of the sighting", VF.history.formatAge(known[1].ageHours) == "2d",
      VF.history.formatAge(known[1].ageHours))

Stub.vehicles = { Stub.makeVehicle(1, "Base.CarNormal", 111, 100) }
local mixed = VF.searchEntries(true)
check("a vehicle back in range is listed live, not twice", #mixed == 2, #mixed)
for _, e in ipairs(mixed) do
    if e.id == "1" then
        check("the live sighting wins over the logged one", e.remembered == nil)
    end
end

wipeHistory()
Stub.multiplayer = true
VF.history.reset()          -- a session decides where the log lives when it loads
Stub.vehicles = { Stub.makeVehicle(7, "Base.CarNormal", 120, 100) }
VF.scanVehicles()
local saved, inSave = Stub.modData.VehicleFinder_Seen, 0
if saved and saved.vehicles then
    for _ in pairs(saved.vehicles) do inSave = inSave + 1 end
end
check("multiplayer keeps the log in memory, not in the save",
      VF.history.count() == 1 and inSave == 0, VF.history.count() .. "/" .. inSave)
Stub.multiplayer = false
VF.history.reset()
noWarnings("history")

print("burnt toggle inside the window")
local win
Stub.vehicles = {
    Stub.makeVehicle(1, "Base.CarNormal", 110, 100),
    Stub.makeVehicle(9, "Base.SmallCar02Burnt", 105, 100),
}
VF.openWindow()
win = VF.window
Stub.time = Stub.time + 1000
win:update()
check("both listed to start with", win.list:size() == 2, win.list:size())
win.burntButton:click()
check("toggle hides the wrecks", win.list:size() == 1, win.list:size())
check("button says what it did", win.burntButton.title == "Burnt: hidden", win.burntButton.title)
check("the toggle overrides the sandbox option", VF.showBurnt() == false)
win.burntButton:click()
check("toggling back brings them home", win.list:size() == 2, win.list:size())
VF.setShowBurnt(nil)
check("clearing the override follows the sandbox option again",
      VF.config.showBurnt == -1 and VF.showBurnt() == true)

print("range toggle inside the window")
wipeHistory()
Stub.worldHours = 200
VF.scanVehicles()
Stub.vehicles = {}
Stub.time = Stub.time + 1000
win:update()
check("nearby mode empties out", win.list:size() == 0, win.list:size())
win.rangeButton:click()
check("range toggle brings back the remembered ones", win.list:size() == 2, win.list:size())
check("range button label", win.rangeButton.title == "Range: all known", win.rangeButton.title)
check("mode is remembered in the config", VF.config.searchAll == true)
Stub.drawCalls = {}
win.list:drawAll()
win:prerender()
check("remembered rows and footer paint", #Stub.drawCalls > 0)

win.rangeButton:click()
wipeHistory()
Stub.vehicles = kept
Stub.time = Stub.time + 1000
win:update()
noWarnings("toggles")

print("toggles are laid out the moment the window opens")
VF.closeWindow()
VF.config.windowW, VF.config.windowH = 360, 400
VF.openWindow()
local fresh = VF.window
check("range button is sized without waiting for a resize",
      fresh.rangeButton:getWidth() > 100, fresh.rangeButton:getWidth())
check("the two toggles do not overlap",
      fresh.burntButton:getX() >= fresh.rangeButton:getX() + fresh.rangeButton:getWidth(),
      fresh.rangeButton:getX() .. "+" .. fresh.rangeButton:getWidth()
      .. " vs " .. fresh.burntButton:getX())
check("both toggles stay inside the window",
      fresh.burntButton:getX() + fresh.burntButton:getWidth() <= fresh.width - 8)
check("long labels fit at the minimum width",
      fresh.rangeButton.title == "Range: nearby", fresh.rangeButton.title)
fresh:setWidth(200)          -- narrower than the mod allows, but be safe anyway
fresh:update()
check("labels shorten when there is no room",
      fresh.rangeButton.title == "Nearby", fresh.rangeButton.title)
fresh:setWidth(360)
fresh:update()
noWarnings("toggle layout")

print("window resize + geometry persistence")
window = VF.window          -- the sections above reopened it
window:setWidth(500)
window:setHeight(600)
window:update()
check("list resized with the window", window.list:getWidth() == 500 - 16, window.list:getWidth())
window:setX(300)
window:setY(200)
VF.closeWindow()
check("geometry saved on close", VF.config.windowX == 300 and VF.config.windowW == 500)
VF.openWindow()
check("geometry restored", VF.window:getX() == 300 and VF.window:getWidth() == 500)
noWarnings("resize")

print("dots on the world map")
Stub.vehicles = {
    Stub.makeVehicle(1, "Base.CarNormal", 10100, 9100, { 0.5, 0.2, 0.2 }),
    Stub.makeVehicle(2, "Base.PickUpTruck", 10200, 9200),
}
Stub.setPlayer(10100, 9100)
VF.config.mapMarkers = true
VF.map.projectorFn = nil
Stub.time = Stub.time + 1000
VF.map.onTick()
check("no overlay while the map is closed", VF.map.overlay == nil)

Stub.openMap(0, 0, 800, 600)
Stub.inventory = {}
Stub.time = Stub.time + 1000
VF.map.lastRefresh = 0
VF.map.onTick()
check("no dots without something to write with", VF.map.overlay == nil)

Stub.inventory = { "RedPen" }
Stub.time = Stub.time + 1000
VF.map.lastRefresh = 0
VF.map.onTick()
check("overlay appears with the map", VF.map.overlay ~= nil)
check("dots take the pen's colour", VF.map.tool ~= nil and VF.map.tool.item == "RedPen",
      VF.map.tool and VF.map.tool.item)
check("overlay covers the map", VF.map.overlay ~= nil
      and VF.map.overlay:getWidth() == 800 and VF.map.overlay:getHeight() == 600)
check("dot list built", #(VF.map.overlay.entries or {}) == 2,
      #(VF.map.overlay.entries or {}))
Stub.drawCalls = {}
VF.map.overlay:render()
check("dots painted", #Stub.drawCalls >= 4, #Stub.drawCalls)

VF.setTracked(VF.map.overlay.entries[1])
Stub.drawCalls = {}
VF.map.overlay:render()
local texts = 0
for _, call in ipairs(Stub.drawCalls) do if call.kind == "text" then texts = texts + 1 end end
check("tracked vehicle gets a label on the map", texts == 1, texts)
VF.setTracked(nil)

-- the other projection shape, for builds that take one argument
Stub.closeMap()
Stub.time = Stub.time + 1000
VF.map.onTick()
check("overlay removed when the map closes", VF.map.overlay == nil)

VF.map.projectorFn = nil
Stub.mapProjection = "x"
Stub.openMap(0, 0, 800, 600)
Stub.time = Stub.time + 1000
VF.map.lastRefresh = 0
VF.map.onTick()
check("works with the one argument projection", VF.map.overlay ~= nil)
Stub.drawCalls = {}
if VF.map.overlay then VF.map.overlay:render() end
check("dots painted on that build too", #Stub.drawCalls >= 4, #Stub.drawCalls)
warnings = {}   -- probing the wrong shape logs once, on purpose

VF.setMapMarkers(false)
Stub.time = Stub.time + 1000
VF.map.onTick()
check("turning the dots off removes the overlay", VF.map.overlay == nil)
VF.setMapMarkers(true)

print("double click shows a vehicle on the map")
Stub.mapCentredOn = nil
Stub.vehicles = { Stub.makeVehicle(1, "Base.CarNormal", 10100, 9100) }
Stub.time = Stub.time + 1000
win = VF.window or VF.openWindow()
win:update()
win.list:doubleClickRow(1)
check("double click tracks the vehicle", VF.trackedId == "1", VF.trackedId)
check("double click centres the map on it",
      Stub.mapCentredOn ~= nil and Stub.mapCentredOn.x == 10100
      and Stub.mapCentredOn.y == 9100,
      Stub.mapCentredOn and (Stub.mapCentredOn.x .. "," .. Stub.mapCentredOn.y))
VF.setTracked(nil)

Stub.closeMap()
Stub.mapProjection = "xy"
VF.map.projectorFn = nil
Stub.setPlayer(100, 100)
Stub.vehicles = kept
noWarnings("map dots")

print("context menu")
VF.button:onRightMouseUp(1, 1)
local menu = ISContextMenu.last
check("context menu built", menu ~= nil and #menu.options >= 3, menu and #menu.options)
noWarnings("context menu")

print("hiding the button leaves the hotkey working")
VF.setButtonVisible(false)
check("button removed", VF.button == nil)
Stub.fire("OnKeyPressed", Keyboard.KEY_F8)
check("hotkey still toggles", not VF.isWindowOpen())
VF.setButtonVisible(true)
check("button restored", VF.button ~= nil and inStack(VF.button))
noWarnings("hide/show")

print("resolution change")
VF.button:setX(1900)
VF.button:setY(1050)
Stub.setResolution(1280, 720)
Stub.fire("OnResolutionChange", 1920, 1080, 1280, 720)
check("button pulled back on screen",
      VF.button:getX() + VF.button:getWidth() <= 1280
      and VF.button:getY() + VF.button:getHeight() <= 720,
      VF.button:getX() .. "," .. VF.button:getY())
Stub.setResolution(1920, 1080)
noWarnings("resolution change")

print("teardown")
Stub.fire("OnMainMenuEnter")
check("everything removed on leaving the game", VF.button == nil and VF.window == nil)
check("nothing left in the UI manager", #Stub.uiStack == 0, #Stub.uiStack)
noWarnings("teardown")

VF.warn = originalWarn
print(string.format("\n%d passed, %d failed", passed, failed))
return failed
