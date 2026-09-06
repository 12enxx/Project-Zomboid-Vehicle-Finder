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
check("colour read when available", entries[1].r ~= nil)
check("missing colour tolerated", entries[2].r == nil)
check("direction", entries[1].dir == "E" and entries[2].dir == "N")
noWarnings("scan")

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

print("window resize + geometry persistence")
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
