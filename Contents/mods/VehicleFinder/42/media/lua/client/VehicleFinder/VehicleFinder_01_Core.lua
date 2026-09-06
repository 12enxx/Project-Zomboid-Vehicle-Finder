--[[
    Vehicle Finder - core namespace, settings and helpers.

    Design rules for this mod (see README):
      * exactly one global (VehicleFinder), everything else lives inside it,
      * no `require` of vanilla files - vanilla classes are only touched from
        inside events, when the game has finished loading its own Lua,
      * no vanilla function or table is ever overwritten or patched,
      * every call into a game API is wrapped, so a renamed/removed API in a
        future build degrades the feature instead of crashing the UI.
]]

VehicleFinder = VehicleFinder or {}
local VF = VehicleFinder

VF.MOD_ID = "VehicleFinder"
VF.VERSION = "1.0.0"
VF.SETTINGS_FILE = "VehicleFinder_settings.ini"
VF.KEY_TOGGLE = "Vehicle Finder: toggle window"

-- ------------------------------------------------------------------ log ---

function VF.log(msg)
    print("[VehicleFinder] " .. tostring(msg))
end

function VF.warn(msg)
    print("[VehicleFinder][warn] " .. tostring(msg))
end

--- pcall wrapper: never lets a broken game API take the UI down with it.
--- @return boolean ok, any result
function VF.safe(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    local ok, res = pcall(fn, ...)
    if not ok then
        VF.warn(res)
        return false, nil
    end
    return true, res
end

--- Reads a translation key, falling back to plain English when the key is
--- missing, so the UI stays readable even without the Translate files.
function VF.text(key, fallback)
    local ok, t = pcall(getText, key)
    if ok and t and t ~= "" and t ~= key then return t end
    return fallback
end

--- Adds an event listener only if that event exists in this build.
function VF.addEvent(name, fn)
    local ev = Events and Events[name]
    if ev and ev.Add then
        ev.Add(fn)
        return true
    end
    VF.warn("event " .. tostring(name) .. " is not available in this build")
    return false
end

-- ------------------------------------------------------------- settings ---

VF.defaults = {
    buttonX = -1,           -- -1 = pick a free spot on first run
    buttonY = -1,
    buttonSize = 40,
    buttonVisible = true,
    windowX = -1,
    windowY = -1,
    windowW = 360,
    windowH = 400,
    showBurnt = -1,         -- -1 follow the sandbox option, 0 hide, 1 show
    searchAll = false,      -- also list vehicles remembered from earlier
    mapMarkers = true,      -- draw dots on the world map
}

VF.config = VF.config or {}

local function copyDefaults()
    local t = {}
    for k, v in pairs(VF.defaults) do t[k] = v end
    return t
end

function VF.loadConfig()
    VF.config = copyDefaults()
    VF.safe(function()
        local reader = getFileReader(VF.SETTINGS_FILE, false)
        if not reader then return end
        local line = reader:readLine()
        while line do
            local key, value = string.match(line, "^%s*([%w_]+)%s*=%s*(.-)%s*$")
            local default = key and VF.defaults[key]
            if default ~= nil then
                if type(default) == "number" then
                    VF.config[key] = tonumber(value) or default
                elseif type(default) == "boolean" then
                    VF.config[key] = (value == "true")
                else
                    VF.config[key] = value
                end
            end
            line = reader:readLine()
        end
        reader:close()
    end)
    return VF.config
end

function VF.saveConfig()
    VF.safe(function()
        local writer = getFileWriter(VF.SETTINGS_FILE, true, false)
        if not writer then return end
        writer:write("# Vehicle Finder " .. VF.VERSION .. "\r\n")
        for key, _ in pairs(VF.defaults) do
            writer:write(key .. "=" .. tostring(VF.config[key]) .. "\r\n")
        end
        writer:close()
    end)
end

-- -------------------------------------------------------------- helpers ---

function VF.screenWidth()
    local ok, w = VF.safe(function() return getCore():getScreenWidth() end)
    return (ok and w) or 1920
end

function VF.screenHeight()
    local ok, h = VF.safe(function() return getCore():getScreenHeight() end)
    return (ok and h) or 1080
end

function VF.clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

--- Kahlua does not guarantee math.atan2, so provide our own.
function VF.atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 then
        if y >= 0 then return math.atan(y / x) + math.pi end
        return math.atan(y / x) - math.pi
    end
    if y > 0 then return math.pi / 2 end
    if y < 0 then return -math.pi / 2 end
    return 0
end

VF.COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

--- World space compass label. In Project Zomboid north is -Y and east is +X.
function VF.compass(dx, dy)
    local angle = math.deg(VF.atan2(dx, -dy))
    if angle < 0 then angle = angle + 360 end
    local index = math.floor((angle + 22.5) / 45) % 8 + 1
    return VF.COMPASS[index], angle
end

--- Converts a world offset into a screen-space direction (isometric camera:
--- +X goes down-right, +Y goes down-left). Returned vector is normalised.
function VF.worldToScreenDir(dx, dy)
    local sx = dx - dy
    local sy = (dx + dy) * 0.5
    local len = math.sqrt(sx * sx + sy * sy)
    if len < 0.0001 then return 0, 0 end
    return sx / len, sy / len
end

--- Cuts text down to maxWidth, ending in "..." when something was removed.
function VF.truncate(text, font, maxWidth)
    text = tostring(text or "")
    local ok, result = VF.safe(function()
        local manager = getTextManager()
        if manager:MeasureStringX(font, text) <= maxWidth then return text end
        local cut = text
        while #cut > 1 and manager:MeasureStringX(font, cut .. "...") > maxWidth do
            cut = string.sub(cut, 1, #cut - 1)
        end
        return cut .. "..."
    end)
    if ok and result then return result end
    return text
end

-- ----------------------------------------------------- writing tools ---

-- Same items the vanilla map annotation UI accepts, with the colours it draws
-- them in. Marking vehicles on the map needs one of these in the inventory,
-- exactly like drawing on the map by hand does.
VF.WRITING_TOOLS = {
    { item = "RedPen",   r = 0.78, g = 0.12, b = 0.12 },
    { item = "BluePen",  r = 0.25, g = 0.32, b = 0.72 },
    { item = "GreenPen", r = 0.14, g = 0.58, b = 0.26 },
    { item = "Pen",      r = 0.40, g = 0.40, b = 0.42 },
    { item = "Pencil",   r = 0.48, g = 0.48, b = 0.46 },
}

--- The colour the player can mark the map in, or nil when they carry nothing
--- to write with. Coloured pens come first so the dots stay readable.
function VF.writingTool(player)
    player = player or getSpecificPlayer(0)
    if not player then return nil end
    local inventory
    VF.safe(function() inventory = player:getInventory() end)
    if not inventory then return nil end

    for i = 1, #VF.WRITING_TOOLS do
        local tool = VF.WRITING_TOOLS[i]
        local found = false
        VF.safe(function()
            if inventory.containsTypeRecurse then
                found = inventory:containsTypeRecurse(tool.item) == true
            end
        end)
        if not found then
            -- modded pens carry the vanilla tag instead of the vanilla type
            VF.safe(function()
                if inventory.containsTagRecurse and ItemTag and ResourceLocation then
                    found = inventory:containsTagRecurse(
                        ItemTag.get(ResourceLocation.of(tool.item))) == true
                end
            end)
        end
        if found then return tool end
    end
    return nil
end

-- ------------------------------------------------------ sandbox options ---

--- Sandbox option VehicleFinder.ShowBurnt: whether burnt wrecks belong in the
--- search results. They cannot be driven, only dismantled, so a player looking
--- for a car usually wants them out of the way.
---
--- Defaults to true when the option is missing - in the main menu, or in a
--- save created before the option existed.
function VF.sandboxShowBurnt()
    local ok, value = VF.safe(function()
        if SandboxVars and SandboxVars.VehicleFinder then
            return SandboxVars.VehicleFinder.ShowBurnt
        end
        return nil
    end)
    if ok and type(value) == "boolean" then return value end
    return true
end

--- Effective setting. The sandbox option decides a world's starting point, but
--- sandbox options are locked once a world exists, so the in-window toggle can
--- override it per player. -1 in the config means "whatever the sandbox says".
function VF.showBurnt()
    local override = VF.config and VF.config.showBurnt
    if override == 0 then return false end
    if override == 1 then return true end
    return VF.sandboxShowBurnt()
end

--- nil restores the sandbox option, true/false pins the choice.
function VF.setShowBurnt(value)
    if value == nil then
        VF.config.showBurnt = -1
    else
        VF.config.showBurnt = value and 1 or 0
    end
    VF.saveConfig()
end

-- ---------------------------------------------- java collections (B42) ---

--- Copies a Java collection into a Lua array, whatever its concrete type.
---
--- IsoCell:getVehicles() returns an ArrayList up to 42.16 and a Set from
--- 42.17 on. A Set has no get(i), so indexing it throws - and Kahlua prints
--- the whole stack trace to console.txt even when the call is wrapped in
--- pcall. So the access pattern is chosen by looking at the object, never by
--- letting a call fail.
function VF.toTable(collection)
    local out = {}
    if not collection then return out end

    -- both ArrayList and Set expose iterator(), so try it first
    if collection.iterator then
        local ok, items = pcall(function()
            local list, iterator = {}, collection:iterator()
            while iterator:hasNext() do
                local value = iterator:next()
                if value then list[#list + 1] = value end
            end
            return list
        end)
        if ok and items then return items end
    end

    -- indexed access (Build 41 and Build 42 up to 42.16)
    if collection.size and collection.get then
        local ok, items = pcall(function()
            local list = {}
            for i = 0, collection:size() - 1 do
                local value = collection:get(i)
                if value then list[#list + 1] = value end
            end
            return list
        end)
        if ok and items then return items end
    end

    VF.warn("this build returns a vehicle collection we cannot iterate")
    return out
end

-- --------------------------------------------------- placement (no-clash) ---

--- True when the rectangle does not overlap any other visible UI element.
--- Used once, on first run, so the toggle button does not land on top of a
--- HUD element added by another mod.
function VF.isSpotFree(x, y, w, h)
    local ok, free = VF.safe(function()
        local list = UIManager.getUI()
        if not list then return true end
        local sw, sh = VF.screenWidth(), VF.screenHeight()
        local margin = 6
        for i = 0, list:size() - 1 do
            local e = list:get(i)
            local visible = e and e:isVisible()
            if visible then
                local ew, eh = e:getWidth(), e:getHeight()
                -- ignore full screen containers, they would block every spot
                if ew > 8 and eh > 8 and ew < sw * 0.6 and eh < sh * 0.7 then
                    local ex, ey = e:getX(), e:getY()
                    if x < ex + ew + margin and x + w + margin > ex
                        and y < ey + eh + margin and y + h + margin > ey then
                        return false
                    end
                end
            end
        end
        return true
    end)
    if not ok then return true end
    return free
end

--- Candidate positions, in preference order, for the toggle button.
local function candidatePositions(w, h)
    local sw, sh = VF.screenWidth(), VF.screenHeight()
    local spots = {}
    local bottom = sh - h - 16
    -- left column, below the vanilla sidebar, walking up from the bottom
    for y = bottom, math.floor(sh * 0.40), -(h + 8) do
        table.insert(spots, { x = 12, y = y })
    end
    -- bottom edge, walking right (chat window lives at the very bottom left)
    for x = 12 + w + 8, math.floor(sw * 0.6), (w + 8) do
        table.insert(spots, { x = x, y = bottom })
    end
    -- right column as the last resort
    for y = bottom, math.floor(sh * 0.35), -(h + 8) do
        table.insert(spots, { x = sw - w - 12, y = y })
    end
    return spots
end

--- Picks the first free candidate position; falls back to the bottom left.
function VF.pickButtonPosition(w, h)
    local spots = candidatePositions(w, h)
    for i = 1, #spots do
        if VF.isSpotFree(spots[i].x, spots[i].y, w, h) then
            return spots[i].x, spots[i].y
        end
    end
    return 12, VF.screenHeight() - h - 16
end

-- ---------------------------------------------------------------- state ---

VF.trackedId = VF.trackedId or nil     -- vehicle id currently tracked
VF.trackedName = VF.trackedName or nil
VF.trackedInfo = VF.trackedInfo or nil -- refreshed by the window/button update
