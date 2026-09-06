--[[
    Vehicle Finder - vehicles remembered from earlier.

    A vehicle only exists as an object while its chunk is loaded, so a live
    scan can never see further than the game itself simulates. What the mod
    can do is remember: every vehicle that has been in range is written down
    with its coordinates and the moment it was seen, and the window can then
    search that log as well.

    The log lives in the save's ModData, so it belongs to that world and is
    deleted with it. In multiplayer that table is server side global data, so
    there the log is kept in memory for the session only.
]]

VehicleFinder = VehicleFinder or {}
local VF = VehicleFinder

VF.history = VF.history or {}
local H = VF.history

local MOD_DATA_KEY = "VehicleFinder_Seen"
local MAX_ENTRIES = 500

H.entries = H.entries or {}
H.loaded = H.loaded or false

--- Hours since the world started; the clock the log is stamped with.
function H.worldHours()
    local ok, hours = VF.safe(function()
        local time = getGameTime()
        if time and time.getWorldAgeHours then return time:getWorldAgeHours() end
        return nil
    end)
    if ok and type(hours) == "number" then return hours end
    return 0
end

local function modData()
    local multiplayer = false
    VF.safe(function() multiplayer = isClient and isClient() == true end)
    if multiplayer then return nil end
    local ok, data = VF.safe(function()
        if not ModData or not ModData.getOrCreate then return nil end
        return ModData.getOrCreate(MOD_DATA_KEY)
    end)
    return ok and data or nil
end

function H.load()
    if H.loaded then return H.entries end
    H.loaded = true
    local data = modData()
    if data then
        if type(data.vehicles) ~= "table" then data.vehicles = {} end
        H.entries = data.vehicles     -- mutated in place, saved with the world
    else
        H.entries = {}
    end
    return H.entries
end

function H.reset()
    H.loaded = false
    H.entries = {}
end

function H.count()
    H.load()
    local n = 0
    for _ in pairs(H.entries) do n = n + 1 end
    return n
end

--- Drops the oldest sightings once the log grows past MAX_ENTRIES.
function H.prune()
    local list = {}
    for _, entry in pairs(H.entries) do list[#list + 1] = entry end
    if #list <= MAX_ENTRIES then return end
    table.sort(list, function(a, b) return (a.at or 0) > (b.at or 0) end)
    for i = MAX_ENTRIES + 1, #list do
        H.entries[list[i].id] = nil
    end
end

--- Writes down everything the live scan just saw.
function H.record(entries)
    if not entries or #entries == 0 then return end
    H.load()
    local now = H.worldHours()
    for i = 1, #entries do
        local e = entries[i]
        if e.id and not e.remembered then
            H.entries[e.id] = {
                id = e.id,
                name = e.name,
                x = e.x,
                y = e.y,
                module = e.module,
                burnt = e.burnt,
                at = now,
            }
        end
    end
    H.prune()
end

function H.forget(id)
    H.load()
    if id then H.entries[id] = nil end
end

function H.clear()
    H.load()
    for id in pairs(H.entries) do H.entries[id] = nil end
end

--- "3h" / "2d", how long ago a vehicle was last seen.
function H.formatAge(hours)
    hours = math.max(0, math.floor(hours or 0))
    if hours < 1 then return "now" end
    if hours < 24 then return hours .. "h" end
    return math.floor(hours / 24) .. "d"
end

--- Remembered vehicles that the live scan cannot see right now.
function H.remembered(px, py, liveIds)
    H.load()
    local out = {}
    local now = H.worldHours()
    for id, entry in pairs(H.entries) do
        local skip = liveIds and liveIds[id]
        if not skip and type(entry.x) == "number" and type(entry.y) == "number" then
            local dx, dy = entry.x - px, entry.y - py
            out[#out + 1] = {
                id = id,
                name = entry.name or VF.text("IGUI_VehicleFinder_Unknown", "Unknown vehicle"),
                module = entry.module,
                burnt = entry.burnt,
                x = entry.x,
                y = entry.y,
                dx = dx,
                dy = dy,
                dist = math.sqrt(dx * dx + dy * dy),
                dir = VF.compass(dx, dy),
                remembered = true,
                ageHours = math.max(0, now - (entry.at or now)),
            }
        end
    end
    return out
end

--- The list the window shows: live vehicles, plus remembered ones when the
--- wider search is on. Sorted nearest first either way.
function VF.searchEntries(includeRemembered)
    local live = VF.scanVehicles()
    if not includeRemembered then return live end

    local player = getSpecificPlayer(0)
    if not player then return live end
    local ok, px = VF.safe(function() return player:getX() end)
    local ok2, py = VF.safe(function() return player:getY() end)
    if not ok or not ok2 then return live end

    local liveIds = {}
    for i = 1, #live do
        if live[i].id then liveIds[live[i].id] = true end
    end

    local showBurnt = VF.showBurnt()
    local remembered = H.remembered(px, py, liveIds)
    for i = 1, #remembered do
        if showBurnt or not remembered[i].burnt then
            live[#live + 1] = remembered[i]
        end
    end
    table.sort(live, function(a, b) return a.dist < b.dist end)
    return live
end
