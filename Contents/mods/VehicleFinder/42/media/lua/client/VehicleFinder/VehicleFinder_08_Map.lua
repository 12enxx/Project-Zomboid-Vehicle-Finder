--[[
    Vehicle Finder - dots on the world map.

    Rather than pushing symbols into the map's own symbol list (which would
    mean owning their lifetime and fighting other mods over the same list),
    the mod puts its own transparent panel on top of the open map and draws
    the dots itself. Nothing in the vanilla map UI is hooked or replaced; the
    only thing borrowed from it is the world-to-screen conversion.

    Marking vehicles needs something to write with, exactly like drawing on
    the map by hand does: the dots only appear while the player carries a pen
    or a pencil, and they are drawn in that pen's colour.

    The poll runs on OnRenderTick, not OnTick: opening the map pauses the game
    in single player, and a paused game stops ticking.
]]

VehicleFinder = VehicleFinder or {}
local VF = VehicleFinder

VF.map = VF.map or {}
local M = VF.map

local POLL_MS = 250        -- how often we look for an open map
local REFRESH_MS = 1000    -- how often the dot list is rebuilt

-- ------------------------------------------------------------ projection ---

--- The open world map UI, or nil. ShowWorldMap keeps the singleton in the
--- global ISWorldMap_instance; ISWorldMap.instance is set later, from the
--- map's own prerender, so both are worth looking at.
function M.getMapUI()
    local ui
    VF.safe(function()
        local candidate = ISWorldMap_instance
        if not candidate and ISWorldMap then candidate = ISWorldMap.instance end
        if candidate and candidate.getIsVisible and candidate:getIsVisible()
            and candidate.mapAPI then
            ui = candidate
        end
    end)
    return ui
end

--- Centres the open (or about to open) world map on a vehicle.
function VF.showOnMap(entry)
    if not entry or type(entry.x) ~= "number" then return false end
    local shown = false
    VF.safe(function()
        if not ISWorldMap or not ISWorldMap.ShowWorldMap then return end
        if ISWorldMap.IsAllowed and not ISWorldMap.IsAllowed() then return end
        ISWorldMap.ShowWorldMap(0, entry.x, entry.y, 50)
        shown = true
    end)
    if not shown then
        VF.warn("could not open the world map on this build")
    end
    return shown
end

--- Builds world -> map-pixel conversion for this build, once.
function M.makeProjector(api)
    if not api or not api.worldToUIX or not api.worldToUIY then
        VF.warn("the map API has no worldToUIX/worldToUIY, dots are off")
        return nil
    end
    if pcall(function() return api:worldToUIX(0, 0) end) then
        VF.log("map projection: worldToUIX(x, y)")
        return function(x, y) return api:worldToUIX(x, y), api:worldToUIY(x, y) end
    end
    if pcall(function() return api:worldToUIX(0) end) then
        VF.log("map projection: worldToUIX(x)")
        return function(x, y) return api:worldToUIX(x), api:worldToUIY(y) end
    end
    VF.warn("could not work out the map projection, dots are off")
    return nil
end

function M.projector(mapUI)
    if M.projectorFn ~= nil then return M.projectorFn or nil end
    local api
    VF.safe(function() api = mapUI.mapAPI end)
    M.projectorFn = M.makeProjector(api) or false
    return M.projectorFn or nil
end

-- -------------------------------------------------------------- overlay ---

function M.buildClass()
    if M.OverlayClass then return M.OverlayClass end
    if not ISPanel then return nil end

    local Overlay = ISPanel:derive("VehicleFinder_MapOverlay")

    function Overlay:new(x, y, w, h)
        local o = ISPanel:new(x, y, w, h)
        setmetatable(o, self)
        self.__index = self
        o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        o.entries = {}
        return o
    end

    function Overlay:createChildren()
        -- clicks belong to the map underneath, never to this panel
        if self.setConsumeMouseEvents then
            VF.safe(function() self:setConsumeMouseEvents(false) end)
        elseif self.javaObject and self.javaObject.setConsumeMouseEvents then
            VF.safe(function() self.javaObject:setConsumeMouseEvents(false) end)
        end
    end

    function Overlay:drawDot(px, py, entry, tracked)
        local size = tracked and 7 or 5
        local half = math.floor(size / 2)
        local x, y = px - half, py - half
        if x < -size or y < -size or x > self.width or y > self.height then return end

        local tool = M.tool or { r = 0.78, g = 0.12, b = 0.12 }
        if entry.remembered then
            -- outline only: drawn from the log, not seen right now
            self:drawRectBorder(x - 1, y - 1, size + 2, size + 2, 0.85, 0.05, 0.05, 0.05)
            self:drawRectBorder(x, y, size, size, 0.95, tool.r, tool.g, tool.b)
        else
            self:drawRect(x - 1, y - 1, size + 2, size + 2, 0.85, 0.05, 0.05, 0.05)
            self:drawRect(x, y, size, size, 1, tool.r, tool.g, tool.b)
        end

        if tracked then
            self:drawRectBorder(x - 4, y - 4, size + 8, size + 8, 0.95, 0.95, 0.78, 0.28)
            local font = UIFont.Small
            local label = entry.name or ""
            local w = getTextManager():MeasureStringX(font, label)
            self:drawRect(px - w / 2 - 3, y - 20, w + 6, 15, 0.75, 0.05, 0.05, 0.05)
            self:drawText(label, px - w / 2, y - 19, 0.95, 0.80, 0.30, 1, font)
        end
    end

    function Overlay:render()
        local project = M.projectFn
        if not project then return end
        local entries = self.entries or {}
        for i = 1, #entries do
            local entry = entries[i]
            local point
            VF.safe(function()
                local ux, uy = project(entry.x, entry.y)
                if type(ux) == "number" and type(uy) == "number" then point = { ux, uy } end
            end)
            if point then
                local tracked = VF.trackedId ~= nil and entry.id == VF.trackedId
                self:drawDot(point[1], point[2], entry, tracked)
            end
        end
    end

    M.OverlayClass = Overlay
    return Overlay
end

-- ----------------------------------------------------------- life cycle ---

function M.destroy()
    if not M.overlay then return end
    VF.safe(function() M.overlay:removeFromUIManager() end)
    M.overlay = nil
end

function M.refreshEntries()
    local now = getTimestampMs()
    if now - (M.lastRefresh or 0) < REFRESH_MS and M.entries then return M.entries end
    M.lastRefresh = now
    M.entries = VF.searchEntries(VF.config and VF.config.searchAll)
    return M.entries
end

--- Called on a timer: shows the overlay while the map is open, hides it
--- otherwise. No hook into the map UI, so nothing to clean up if another mod
--- replaces it.
function M.onTick()
    local now = getTimestampMs()
    if now - (M.lastPoll or 0) < POLL_MS then return end
    M.lastPoll = now

    if not VF.config or not VF.config.mapMarkers then
        M.destroy()
        return
    end

    -- no pen, no marks: same rule the vanilla map annotations follow
    local tool = VF.writingTool()
    if not tool then
        M.destroy()
        return
    end
    M.tool = tool

    local mapUI = M.getMapUI()
    if not mapUI then
        M.destroy()
        return
    end

    M.projectFn = M.projector(mapUI)
    if not M.projectFn then
        M.destroy()
        return
    end

    if not M.overlay then
        local class = M.buildClass()
        if not class then return end
        M.overlay = class:new(0, 0, 10, 10)
        M.overlay:initialise()
        M.overlay:instantiate()
        M.overlay:addToUIManager()
    end

    -- keep the overlay exactly on top of the map
    VF.safe(function()
        M.overlay:setX(mapUI:getX())
        M.overlay:setY(mapUI:getY())
        M.overlay:setWidth(mapUI:getWidth())
        M.overlay:setHeight(mapUI:getHeight())
    end)
    M.overlay:setVisible(true)
    M.overlay.entries = M.refreshEntries()
end

if not M.tickBound then
    M.tickBound = true
    -- the world map pauses the game, so OnTick stops firing while it is open
    if not VF.addEvent("OnRenderTick", M.onTick) then
        VF.addEvent("OnTick", M.onTick)
    end
end
