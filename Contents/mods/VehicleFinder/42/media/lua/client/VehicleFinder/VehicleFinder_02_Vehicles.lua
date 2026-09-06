--[[
    Vehicle Finder - reading the vehicles that exist around the player.

    Everything here is read only and defensive on purpose: vehicles added by
    other mods do not always ship translations, colours or a "Base." module
    prefix, and they must never be able to break the list.
]]

VehicleFinder = VehicleFinder or {}
local VF = VehicleFinder

--- "SportsCar" -> "Sports Car", used when a vehicle has no translation.
function VF.prettifyName(name)
    local out = tostring(name)
    out = string.gsub(out, "_", " ")
    out = string.gsub(out, "(%l)(%u)", "%1 %2")
    out = string.gsub(out, "(%a)(%d)", "%1 %2")
    out = string.gsub(out, "(%d)(%u)", "%1 %2")
    return out
end

--- Display name for a vehicle: translation first, then a readable fallback
--- built from the script name (mod vehicles frequently lack IGUI entries).
function VF.vehicleName(vehicle)
    local result
    VF.safe(function()
        local script = vehicle:getScript()
        if not script then return end
        local raw = script:getName()
        if not raw then return end
        raw = tostring(raw)
        local short = string.match(raw, "([^%.]+)$") or raw
        if getTextOrNull then
            local t = getTextOrNull("IGUI_VehicleName" .. short)
            if (not t or t == "") and short ~= raw then
                t = getTextOrNull("IGUI_VehicleName" .. raw)
            end
            if t and t ~= "" then result = t end
        end
        if not result then result = VF.prettifyName(short) end
    end)
    return result or VF.text("IGUI_VehicleFinder_Unknown", "Unknown vehicle")
end

--- Module a vehicle script comes from ("Base" for vanilla, mod id otherwise).
function VF.vehicleModule(vehicle)
    local module
    VF.safe(function()
        local script = vehicle:getScript()
        if not script then return end
        local full
        if script.getFullName then full = script:getFullName() end
        if not full and script.getName then full = script:getName() end
        if not full then return end
        module = string.match(tostring(full), "^([^%.]+)%.")
    end)
    return module
end

--- Body colour as 0..1 rgb, or nil when the build/mod does not expose it.
function VF.vehicleColor(vehicle)
    local r, g, b
    VF.safe(function()
        if not vehicle.getColorRed then return end
        r, g, b = vehicle:getColorRed(), vehicle:getColorGreen(), vehicle:getColorBlue()
    end)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end
    if r > 1 or g > 1 or b > 1 then r, g, b = r / 255, g / 255, b / 255 end
    return VF.clamp(r, 0, 1), VF.clamp(g, 0, 1), VF.clamp(b, 0, 1)
end

--- Stable identifier so a tracked vehicle survives list refreshes.
function VF.vehicleId(vehicle)
    local id
    VF.safe(function()
        if vehicle.getId then id = vehicle:getId() end
        if id == nil and vehicle.getSqlId then id = vehicle:getSqlId() end
    end)
    if id == nil then
        local ok, key = VF.safe(function()
            return math.floor(vehicle:getX()) .. ":" .. math.floor(vehicle:getY())
        end)
        id = ok and key or nil
    end
    return id and tostring(id) or nil
end

--- Builds the description used by the list and the tracker.
function VF.describe(vehicle, px, py)
    local entry
    VF.safe(function()
        local x, y = vehicle:getX(), vehicle:getY()
        if type(x) ~= "number" or type(y) ~= "number" then return end
        local dx, dy = x - px, y - py
        local dir = VF.compass(dx, dy)
        entry = {
            vehicle = vehicle,
            id = VF.vehicleId(vehicle),
            name = VF.vehicleName(vehicle),
            module = VF.vehicleModule(vehicle),
            x = x,
            y = y,
            dx = dx,
            dy = dy,
            dist = math.sqrt(dx * dx + dy * dy),
            dir = dir,
        }
        entry.modded = entry.module ~= nil and entry.module ~= "Base"
        entry.r, entry.g, entry.b = VF.vehicleColor(vehicle)
    end)
    return entry
end

--- Every vehicle currently loaded around the player, nearest first.
--- Only loaded chunks contain vehicles, which is exactly the range the game
--- itself simulates - no map or save file is read.
function VF.scanVehicles()
    local result = {}
    local player = getSpecificPlayer(0)
    if not player then return result end
    local ok, px = VF.safe(function() return player:getX() end)
    local ok2, py = VF.safe(function() return player:getY() end)
    if not ok or not ok2 then return result end

    VF.safe(function()
        local cell = getCell()
        if not cell or not cell.getVehicles then return end
        local vehicles = VF.toTable(cell:getVehicles())
        for i = 1, #vehicles do
            local entry = VF.describe(vehicles[i], px, py)
            if entry then table.insert(result, entry) end
        end
    end)

    table.sort(result, function(a, b) return a.dist < b.dist end)
    return result
end

--- Refreshes VF.trackedInfo (distance/direction of the tracked vehicle).
--- Returns the tracked entry, or nil when it is gone or out of loaded range.
function VF.updateTracked(entries)
    if not VF.trackedId then
        VF.trackedInfo = nil
        return nil
    end
    entries = entries or VF.scanVehicles()
    for i = 1, #entries do
        if entries[i].id == VF.trackedId then
            VF.trackedInfo = entries[i]
            return entries[i]
        end
    end
    VF.trackedInfo = nil
    return nil
end

function VF.setTracked(entry)
    if entry then
        VF.trackedId = entry.id
        VF.trackedName = entry.name
        VF.trackedInfo = entry
    else
        VF.trackedId = nil
        VF.trackedName = nil
        VF.trackedInfo = nil
    end
end
