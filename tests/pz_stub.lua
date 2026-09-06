--[[
    Minimal stand-in for the Project Zomboid Lua API, used by tools/run_tests.py
    to exercise the mod outside the game. It is intentionally shallow: it only
    implements what Vehicle Finder actually calls, which is the point - if the
    mod starts calling something else, the tests notice.
]]

Stub = { drawCalls = {}, files = {}, time = 0 }

-- ------------------------------------------------------------------ core ---

local screenW, screenH = 1920, 1080

function getCore()
    return {
        getScreenWidth = function() return screenW end,
        getScreenHeight = function() return screenH end,
        getKey = function(_, name) return Stub.keys[name] or 0 end,
    }
end

function Stub.setResolution(w, h) screenW, screenH = w, h end

Keyboard = { KEY_F8 = 66, KEY_F9 = 67 }
keyBinding = {}
Stub.keys = {}

function getKeyName(code)
    if code == Keyboard.KEY_F8 then return "F8" end
    return "KEY" .. tostring(code)
end

function getTimestampMs() return Stub.time end

-- in-game clock, in hours since the world started
Stub.worldHours = 0

function getGameTime()
    return { getWorldAgeHours = function() return Stub.worldHours end }
end

-- per-save storage, where the "seen earlier" log lives
Stub.modData = {}

ModData = {
    getOrCreate = function(name)
        Stub.modData[name] = Stub.modData[name] or {}
        return Stub.modData[name]
    end,
}

Stub.multiplayer = false
function isClient() return Stub.multiplayer end

UIFont = { Small = "Small", Medium = "Medium" }

function getTextManager()
    return {
        MeasureStringX = function(_, _, str) return #tostring(str) * 6 end,
        getFontHeight = function() return 12 end,
    }
end

-- ------------------------------------------------------------ translation ---

Stub.translations = {
    IGUI_VehicleNameCarNormal = "Chevalier Cerise",
}

function getText(key, ...)
    return Stub.translations[key] or key
end

function getTextOrNull(key)
    return Stub.translations[key]
end

-- ------------------------------------------------------------------ files ---

function getFileReader(name, create)
    local content = Stub.files[name]
    if not content then
        if not create then return nil end
        content = ""
    end
    local lines, pos = {}, 0
    for line in string.gmatch(content, "[^\r\n]+") do table.insert(lines, line) end
    return {
        readLine = function() pos = pos + 1 return lines[pos] end,
        close = function() end,
    }
end

function getFileWriter(name, create, append)
    if not append then Stub.files[name] = "" end
    return {
        write = function(_, text) Stub.files[name] = (Stub.files[name] or "") .. text end,
        close = function() end,
    }
end

-- ----------------------------------------------------------------- events ---

Events = {}
local EVENT_NAMES = {
    "OnGameBoot", "OnGameStart", "OnKeyPressed", "OnResolutionChange",
    "OnPlayerDeath", "OnMainMenuEnter", "OnTick", "OnRenderTick",
}
for _, name in ipairs(EVENT_NAMES) do
    Events[name] = {
        listeners = {},
        Add = function(fn) table.insert(Events[name].listeners, fn) end,
        Remove = function(fn) end,
    }
end

function Stub.fire(name, ...)
    local ev = Events[name]
    if not ev then return end
    for _, fn in ipairs(ev.listeners) do fn(...) end
end

-- --------------------------------------------------------------- vehicles ---

local function makeScript(fullName)
    return {
        getName = function() return fullName end,
        getFullName = function() return fullName end,
    }
end

SandboxVars = { VehicleFinder = { ShowBurnt = true } }

function Stub.makeVehicle(id, fullName, x, y, color, burnt)
    local v = {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return 0 end,
        getId = function() return id end,
        getScript = function() return makeScript(fullName) end,
    }
    if color then
        v.getColorRed = function() return color[1] end
        v.getColorGreen = function() return color[2] end
        v.getColorBlue = function() return color[3] end
    end
    if burnt ~= nil then
        v.isBurnt = function() return burnt end
    end
    return v
end

-- ArrayList: Build 41 and Build 42 up to 42.16
local function javaList(items)
    return {
        size = function() return #items end,
        get = function(_, i) return items[i + 1] end,
    }
end

-- Set: what IsoCell:getVehicles() returns from 42.17 on. No get(i) at all -
-- indexing it is exactly what crashed the mod in 42.20.4.
local function javaSet(items)
    return {
        size = function() return #items end,
        isEmpty = function() return #items == 0 end,
        iterator = function()
            local index = 0
            return {
                hasNext = function() return index < #items end,
                next = function()
                    index = index + 1
                    return items[index]
                end,
            }
        end,
    }
end

Stub.vehicles = {}
Stub.player = nil

-- "set" mirrors 42.17+, "list" mirrors 42.16 and Build 41
Stub.vehicleCollection = "set"

function getCell()
    return {
        getVehicles = function()
            if Stub.vehicleCollection == "list" then
                return javaList(Stub.vehicles)
            end
            return javaSet(Stub.vehicles)
        end,
    }
end

function getSpecificPlayer(index)
    if index ~= 0 then return nil end
    return Stub.player
end

function getPlayer() return Stub.player end

-- item types the player is carrying, e.g. { "RedPen" }
Stub.inventory = {}

function Stub.setPlayer(x, y)
    Stub.player = {
        getX = function() return x end,
        getY = function() return y end,
        isDead = function() return false end,
        getInventory = function()
            return {
                containsTypeRecurse = function(_, item)
                    for _, held in ipairs(Stub.inventory) do
                        if held == item then return true end
                    end
                    return false
                end,
            }
        end,
    }
end

-- ------------------------------------------------------------- ui manager ---

Stub.uiElements = {}

UIManager = {
    getUI = function()
        return javaList(Stub.uiElements)
    end,
}

function Stub.addFakeUI(x, y, w, h)
    table.insert(Stub.uiElements, {
        isVisible = function() return true end,
        getX = function() return x end,
        getY = function() return y end,
        getWidth = function() return w end,
        getHeight = function() return h end,
    })
end

-- --------------------------------------------------------------- textures ---

Stub.textures = { ["media/textures/VehicleFinder_Car.png"] = { name = "car" } }

function getTexture(path)
    local tex = Stub.textures[path]
    if not tex then error("texture not found: " .. tostring(path)) end
    return tex
end

-- -------------------------------------------------------------- ui widgets ---

ISUIElement = {}

function ISUIElement:derive(name)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.Type = name
    return o
end

function ISUIElement:new(x, y, w, h)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.x, o.y, o.width, o.height = x or 0, y or 0, w or 0, h or 0
    o.children = {}
    o.visible = true
    return o
end

function ISUIElement:initialise() end
function ISUIElement:instantiate() self:createChildren() end  -- as vanilla does
function ISUIElement:createChildren() end
function ISUIElement:update() end
function ISUIElement:prerender() end
function ISUIElement:render() end
function ISUIElement:addChild(child) table.insert(self.children, child) child.parent = self end
function ISUIElement:addToUIManager() Stub.registerUI(self) end
function ISUIElement:removeFromUIManager() Stub.unregisterUI(self) end
function ISUIElement:setVisible(v) self.visible = v end
function ISUIElement:getIsVisible() return self.visible end
function ISUIElement:isVisible() return self.visible end
function ISUIElement:getX() return self.x end
function ISUIElement:getY() return self.y end
function ISUIElement:setX(x) self.x = x end
function ISUIElement:setY(y) self.y = y end
function ISUIElement:getAbsoluteX() return self.x end
function ISUIElement:getAbsoluteY() return self.y end
function ISUIElement:getWidth() return self.width end
function ISUIElement:getHeight() return self.height end
function ISUIElement:setWidth(w) self.width = w end
function ISUIElement:setHeight(h) self.height = h end
function ISUIElement:setCapture(v) self.captured = v end
function ISUIElement:isMouseOver() return self.mouseOver == true end
function ISUIElement:getYScroll() return self.yScroll or 0 end
function ISUIElement:setYScroll(v) self.yScroll = v end
function ISUIElement:bringToTop() end

local function record(kind, ...)
    table.insert(Stub.drawCalls, { kind = kind, n = select("#", ...) })
end

function ISUIElement:drawRect(...) record("rect", ...) end
function ISUIElement:drawRectBorder(...) record("border", ...) end
function ISUIElement:drawText(text, x, y, r, g, b, a, font)
    assert(type(text) == "string", "drawText needs a string")
    assert(type(x) == "number" and type(y) == "number", "drawText needs numbers")
    assert(type(a) == "number", "drawText alpha must be a number")
    record("text")
end
function ISUIElement:drawTextureScaled(tex, x, y, w, h, a, r, g, b)
    assert(tex ~= nil, "drawTextureScaled needs a texture")
    assert(type(w) == "number" and type(h) == "number", "bad texture size")
    record("texture")
end

Stub.uiStack = {}
function Stub.registerUI(e)
    for i, v in ipairs(Stub.uiStack) do if v == e then return end end
    table.insert(Stub.uiStack, e)
end
function Stub.unregisterUI(e)
    for i, v in ipairs(Stub.uiStack) do
        if v == e then table.remove(Stub.uiStack, i) return end
    end
end

ISPanel = ISUIElement:derive("ISPanel")
function ISPanel:new(x, y, w, h)
    local o = ISUIElement.new(self, x, y, w, h)
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 1 }
    o.borderColor = { r = 1, g = 1, b = 1, a = 1 }
    return o
end

ISCollapsableWindow = ISPanel:derive("ISCollapsableWindow")
function ISCollapsableWindow:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.title = ""
    return o
end
function ISCollapsableWindow:titleBarHeight() return 16 end
function ISCollapsableWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
end

ISScrollingListBox = ISPanel:derive("ISScrollingListBox")
function ISScrollingListBox:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.items = {}
    o.selected = 0
    o.itemheight = 20
    return o
end
function ISScrollingListBox:clear() self.items = {} end
function ISScrollingListBox:addItem(name, item)
    local entry = { text = name, item = item, index = #self.items + 1 }
    table.insert(self.items, entry)
    return entry
end
function ISScrollingListBox:size() return #self.items end
function ISScrollingListBox:setOnMouseDownFunction(target, fn)
    self.target, self.onmousedown = target, fn
end
function ISScrollingListBox:setOnMouseDoubleClick(target, fn)
    self.target, self.onmousedblclick = target, fn
end
function ISScrollingListBox:doubleClickRow(index)
    self.selected = index
    local entry = self.items[index]
    if entry and self.onmousedblclick then self.onmousedblclick(self.target, entry.item) end
end
function ISScrollingListBox:clickRow(index)
    self.selected = index
    local entry = self.items[index]
    if entry and self.onmousedown then self.onmousedown(self.target, entry.item) end
end
function ISScrollingListBox:drawAll()
    local y = 0
    for i, entry in ipairs(self.items) do
        y = self:doDrawItem(y, entry, i % 2 == 0)
    end
    return y
end

ISTextEntryBox = ISPanel:derive("ISTextEntryBox")
function ISTextEntryBox:new(text, x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.text = text or ""
    return o
end
function ISTextEntryBox:getInternalText() return self.text end
function ISTextEntryBox:setText(t) self.text = t end
function ISTextEntryBox:isFocused() return self.focused == true end
function ISTextEntryBox:setClearButton(v) self.clearButton = v end

ISButton = ISPanel:derive("ISButton")
function ISButton:new(x, y, w, h, title, target, onclick)
    local o = ISPanel.new(self, x, y, w, h)
    o.title, o.target, o.onclick = title, target, onclick
    return o
end
function ISButton:setTitle(title) self.title = title end
function ISButton:click() if self.onclick then self.onclick(self.target, self) end end

-- World map. Stub.mapProjection picks which conversion the build offers:
-- "xy" = worldToUIX(x, y), "x" = worldToUIX(x).
Stub.mapProjection = "xy"
Stub.mapOpen = false

ISWorldMap = {}

local function mapAPI()
    local api = {}
    if Stub.mapProjection == "xy" then
        api.worldToUIX = function(_, x, y)
            assert(type(y) == "number", "worldToUIX(x, y) needs two numbers")
            return (x - 10000) * 0.5
        end
        api.worldToUIY = function(_, x, y)
            assert(type(y) == "number", "worldToUIY(x, y) needs two numbers")
            return (y - 9000) * 0.5
        end
    else
        api.worldToUIX = function(_, x, y)
            assert(y == nil, "this build only takes worldToUIX(x)")
            return (x - 10000) * 0.5
        end
        api.worldToUIY = function(_, y, extra)
            assert(extra == nil, "this build only takes worldToUIY(y)")
            return (y - 9000) * 0.5
        end
    end
    return api
end

Stub.mapCentredOn = nil

function ISWorldMap.IsAllowed() return true end

function ISWorldMap.ShowWorldMap(playerNum, centerX, centerY, zoom)
    Stub.mapCentredOn = { player = playerNum, x = centerX, y = centerY, zoom = zoom }
    Stub.openMap(0, 0, 800, 600)
end

function Stub.openMap(x, y, w, h)
    ISWorldMap.instance = {
        mapAPI = mapAPI(),
        getIsVisible = function() return Stub.mapOpen end,
        getX = function() return x or 0 end,
        getY = function() return y or 0 end,
        getWidth = function() return w or 800 end,
        getHeight = function() return h or 600 end,
    }
    Stub.mapOpen = true
    ISWorldMap_instance = ISWorldMap.instance
end

function Stub.closeMap()
    Stub.mapOpen = false
    ISWorldMap_instance = nil
end

ISContextMenu = { options = {} }
function ISContextMenu.get(player, x, y)
    local menu = { options = {}, submenus = {} }
    function menu:addOption(name, target, fn, ...)
        local option = { name = name, target = target, fn = fn }
        table.insert(self.options, option)
        return option
    end
    function menu:addSubMenu(option, sub) table.insert(self.submenus, sub) end
    function menu:setOptionChecked(option, checked) option.checked = checked end
    ISContextMenu.last = menu
    return menu
end
function ISContextMenu.getNew(parent) return ISContextMenu.get(0, 0, 0) end
