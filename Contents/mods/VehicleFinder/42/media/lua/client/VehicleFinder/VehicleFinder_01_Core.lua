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
