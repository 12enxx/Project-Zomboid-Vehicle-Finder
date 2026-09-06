--[[
    Vehicle Finder - the main window.

    Standalone ISCollapsableWindow, built at runtime (no `require`), added to
    the UI manager on its own. It only reads vehicles, it never hooks or
    replaces any vanilla or third party UI.
]]

VehicleFinder = VehicleFinder or {}
local VF = VehicleFinder

local REFRESH_MS = 500      -- vehicle rescan interval
local ROW_HEIGHT = 22
local PAD = 8
local SEARCH_H = 22
local TOGGLE_H = 20
local HEADER_H = SEARCH_H + 4 + TOGGLE_H + 4   -- search row + toggle row
local FOOTER_H = 46                            -- tracked line + count line

function VF.buildWindowClass()
    if VF.WindowClass then return VF.WindowClass end
    if not ISCollapsableWindow or not ISScrollingListBox or not ISTextEntryBox then
        VF.warn("vanilla UI classes are not loaded yet, window postponed")
        return nil
    end

    local Window = ISCollapsableWindow:derive("VehicleFinder_Window")

    function Window:new(x, y, w, h)
        local o = ISCollapsableWindow:new(x, y, w, h)
        setmetatable(o, self)
        self.__index = self
        o.title = VF.text("IGUI_VehicleFinder_Title", "Vehicle Finder")
        o.resizable = true
        o.drawFrame = true
        o.minimumWidth = 340       -- below this the two toggles start to collide
        o.minimumHeight = 220
        o.entries = {}
        o.searchText = ""
        o.lastRefresh = 0
        o.lastWidth = w
        o.lastHeight = h
        return o
    end

    function Window:createChildren()
        ISCollapsableWindow.createChildren(self)
        local th = self:titleBarHeight()

        self.searchEntry = ISTextEntryBox:new("", PAD, th + PAD, self.width - PAD * 2, 22)
        self.searchEntry:initialise()
        self.searchEntry:instantiate()
        self.searchEntry.font = UIFont.Small
        VF.safe(function() self.searchEntry:setClearButton(true) end)
        self:addChild(self.searchEntry)

        self.rangeButton = ISButton:new(PAD, th + PAD + SEARCH_H + 4, 10, TOGGLE_H,
                                        "", self, Window.onToggleRange)
        self.rangeButton:initialise()
        self.rangeButton:instantiate()
        self.rangeButton.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
        self:addChild(self.rangeButton)

        self.burntButton = ISButton:new(PAD, th + PAD + SEARCH_H + 4, 10, TOGGLE_H,
                                        "", self, Window.onToggleBurnt)
        self.burntButton:initialise()
        self.burntButton:instantiate()
        self.burntButton.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
        self:addChild(self.burntButton)

        self.list = ISScrollingListBox:new(PAD, th + PAD + HEADER_H,
                                           self.width - PAD * 2,
                                           self.height - th - PAD - HEADER_H - FOOTER_H)
        self.list:initialise()
        self.list:instantiate()
        self.list.itemheight = ROW_HEIGHT
        self.list.selected = 0
        self.list.font = UIFont.Small
        self.list.drawBorder = true
        self.list.doDrawItem = function(list, y, item, alt)
            return self:drawRow(list, y, item, alt)
        end
        if self.list.setOnMouseDownFunction then
            self.list:setOnMouseDownFunction(self, Window.onRowClicked)
        else
            self.list.target = self
            self.list.onmousedown = Window.onRowClicked
        end
        if self.list.setOnMouseDoubleClick then
            self.list:setOnMouseDoubleClick(self, Window.onRowDoubleClicked)
        else
            self.list.target = self
            self.list.onmousedblclick = Window.onRowDoubleClicked
        end
        self:addChild(self.list)

        self.clearButton = ISButton:new(self.width - PAD - 96,
                                        self.height - PAD - 20, 96, 20,
                                        VF.text("IGUI_VehicleFinder_ClearTarget", "Clear target"),
                                        self, Window.onClearTarget)
        self.clearButton:initialise()
        self.clearButton:instantiate()
        self.clearButton.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
        self:addChild(self.clearButton)

        self:layout()
        self:refreshToggles()
        self:refreshList()
    end

    --- Re-lays out the children; called whenever the window is resized.
    function Window:layout()
        local th = self:titleBarHeight()
        local inner = self.width - PAD * 2
        if self.searchEntry then
            self.searchEntry:setWidth(inner)
        end
        if self.rangeButton and self.burntButton then
            local half = math.floor((inner - 6) / 2)
            self.rangeButton:setWidth(half)
            self.burntButton:setX(PAD + half + 6)
            self.burntButton:setWidth(inner - half - 6)
        end
        if self.list then
            self.list:setWidth(inner)
            self.list:setHeight(math.max(40, self.height - th - PAD - HEADER_H - FOOTER_H))
        end
        if self.clearButton then
            self.clearButton:setX(self.width - PAD - self.clearButton:getWidth())
            self.clearButton:setY(self.height - PAD - 20)
        end
    end

    --- Toggle labels always show the state they are currently in.
    --- Long label when it fits the button, short one when it does not.
    local function fitTitle(button, long, short)
        if not button then return long end
        local ok, fits = VF.safe(function()
            return getTextManager():MeasureStringX(UIFont.Small, long) + 12
                <= button:getWidth()
        end)
        if ok and fits == false then return short end
        return long
    end

    function Window:refreshToggles()
        if self.rangeButton then
            local title
            if VF.config.searchAll then
                title = fitTitle(self.rangeButton,
                    VF.text("IGUI_VehicleFinder_RangeAll", "Range: all known"),
                    VF.text("IGUI_VehicleFinder_RangeAllShort", "All known"))
            else
                title = fitTitle(self.rangeButton,
                    VF.text("IGUI_VehicleFinder_RangeNear", "Range: nearby"),
                    VF.text("IGUI_VehicleFinder_RangeNearShort", "Nearby"))
            end
            VF.safe(function() self.rangeButton:setTitle(title) end)
        end
        if self.burntButton then
            local title
            if VF.showBurnt() then
                title = fitTitle(self.burntButton,
                    VF.text("IGUI_VehicleFinder_BurntShown", "Burnt: shown"),
                    VF.text("IGUI_VehicleFinder_BurntShownShort", "Burnt: on"))
            else
                title = fitTitle(self.burntButton,
                    VF.text("IGUI_VehicleFinder_BurntHiddenBtn", "Burnt: hidden"),
                    VF.text("IGUI_VehicleFinder_BurntHiddenShort", "Burnt: off"))
            end
            VF.safe(function() self.burntButton:setTitle(title) end)
        end
    end

    function Window:onToggleRange()
        VF.config.searchAll = not VF.config.searchAll
        VF.saveConfig()
        self:layout()
        self:refreshToggles()
        self:refreshList()
    end

    function Window:onToggleBurnt()
        VF.setShowBurnt(not VF.showBurnt())
        self:layout()
        self:refreshToggles()
        self:refreshList()
    end

    -- ------------------------------------------------------------- data ---

    function Window:currentSearch()
        local text
        VF.safe(function()
            if self.searchEntry.getInternalText then
                text = self.searchEntry:getInternalText()
            elseif self.searchEntry.getText then
                text = self.searchEntry:getText()
            end
        end)
        return text or ""
    end

    function Window:refreshList()
        local scroll
        VF.safe(function() scroll = self.list:getYScroll() end)
        VF.safe(function()
            self.entries = VF.searchEntries(VF.config.searchAll)
            VF.updateTracked(self.entries)

            local filter = string.lower(self.searchText or "")
            self.list:clear()
            self.shown = 0
            for i = 1, #self.entries do
                local entry = self.entries[i]
                if filter == "" or string.find(string.lower(entry.name), filter, 1, true) then
                    local item = self.list:addItem(entry.name, entry)
                    self.shown = self.shown + 1
                    if VF.trackedId and entry.id == VF.trackedId then
                        self.list.selected = item.index or self.shown
                    end
                end
            end
        end)
        if scroll then VF.safe(function() self.list:setYScroll(scroll) end) end
    end

    function Window:onRowClicked(item)
        if not item then return end
        VF.setTracked(item)
    end

    --- Double click: track it and open the world map centred on it.
    function Window:onRowDoubleClicked(item)
        if not item then return end
        VF.setTracked(item)
        VF.showOnMap(item)
    end

    function Window:onClearTarget()
        VF.setTracked(nil)
        self.list.selected = 0
    end

    -- ------------------------------------------------------------ paint ---

    function Window:drawRow(list, y, item, alt)
        local entry = item.item
        local height = list.itemheight
        if not entry then return y + height end
        local width = list:getWidth()

        if VF.trackedId and entry.id == VF.trackedId then
            list:drawRect(0, y, width, height, 0.30, 0.85, 0.68, 0.22)
        elseif list.selected == item.index then
            list:drawRect(0, y, width, height, 0.25, 0.7, 0.7, 0.7)
        elseif alt then
            list:drawRect(0, y, width, height, 0.08, 1, 1, 1)
        end
        list:drawRectBorder(0, y, width, height, 0.10, 0.6, 0.6, 0.6)

        local font = UIFont.Small
        local manager = getTextManager()
        local x = 4
        if entry.r then
            list:drawRect(x, y + 6, 10, 10, 1, entry.r, entry.g, entry.b)
            list:drawRectBorder(x, y + 6, 10, 10, 0.8, 0.1, 0.1, 0.1)
            x = x + 16
        elseif entry.remembered then
            -- hollow swatch: this one is from the log, not in front of you
            list:drawRectBorder(x, y + 6, 10, 10, 0.55, 0.6, 0.6, 0.55)
            x = x + 16
        end

        -- right column: distance and compass direction
        local right = string.format("%d  %s", math.floor(entry.dist), entry.dir or "")
        local rw = manager:MeasureStringX(font, right)

        -- middle column: map coordinates, and how old the sighting is
        local middle = string.format("%d, %d", math.floor(entry.x or 0), math.floor(entry.y or 0))
        if entry.remembered and VF.history then
            middle = VF.history.formatAge(entry.ageHours) .. "  " .. middle
        end
        local mw = manager:MeasureStringX(font, middle)

        local nameSpace = width - rw - mw - x - 24
        if nameSpace < 70 then          -- window too narrow, drop the coordinates
            middle, mw, nameSpace = nil, 0, width - rw - x - 14
        end

        local name = entry.name
        if entry.modded then name = name .. "  *" end
        local dim = entry.remembered and 0.72 or 1
        list:drawText(VF.truncate(name, font, nameSpace), x, y + 3,
                      0.92 * dim, 0.92 * dim, 0.88 * dim, 1, font)
        if middle then
            list:drawText(middle, width - rw - mw - 14, y + 3,
                          0.62, 0.66, 0.60, 1, font)
        end
        list:drawText(right, width - rw - 6, y + 3,
                      0.75 * dim, 0.78 * dim, 0.72 * dim, 1, font)

        return y + height
    end

    function Window:prerender()
        ISCollapsableWindow.prerender(self)
        local font = UIFont.Small
        local y = self.height - PAD - 18
        local total = #(self.entries or {})
        local shown = self.shown or total
        local label
        if total == 0 then
            label = VF.config.searchAll
                and VF.text("IGUI_VehicleFinder_NoneKnown", "No vehicles seen yet")
                or VF.text("IGUI_VehicleFinder_None", "No vehicles in the loaded area")
        elseif shown == total then
            label = string.format(VF.text("IGUI_VehicleFinder_Count", "%d vehicles nearby"), total)
        else
            label = string.format(VF.text("IGUI_VehicleFinder_Filtered", "%d of %d vehicles"), shown, total)
        end
        if VF.config.searchAll then
            local remembered = 0
            for i = 1, total do
                if self.entries[i].remembered then remembered = remembered + 1 end
            end
            if remembered > 0 then
                label = label .. " - " .. string.format(
                    VF.text("IGUI_VehicleFinder_Remembered", "%d remembered"), remembered)
            end
        end
        if not VF.showBurnt() then
            label = label .. " - " .. VF.text("IGUI_VehicleFinder_BurntHidden", "burnt hidden")
        end
        if VF.config.mapMarkers and not VF.writingTool() then
            label = label .. " - " .. VF.text("IGUI_VehicleFinder_NeedPen", "map dots need a pen")
        end
        self:drawText(label, PAD, y, 0.75, 0.78, 0.72, 1, font)

        if VF.trackedInfo then
            local info = VF.trackedInfo
            local tracked = string.format("%s - %d %s - %d, %d", info.name,
                                          math.floor(info.dist), info.dir or "",
                                          math.floor(info.x or 0), math.floor(info.y or 0))
            if info.remembered and VF.history then
                tracked = tracked .. " - " .. VF.history.formatAge(info.ageHours)
            end
            local tw = getTextManager():MeasureStringX(font, tracked)
            self:drawText(tracked, math.max(PAD, self.width - PAD - 100 - tw - 8),
                          y - 18, 0.95, 0.80, 0.30, 1, font)
        elseif VF.trackedId then
            self:drawText(VF.text("IGUI_VehicleFinder_OutOfRange", "Tracked vehicle is out of loaded range"),
                          PAD, y - 18, 0.85, 0.55, 0.35, 1, font)
        end
    end

    -- ----------------------------------------------------------- update ---

    function Window:update()
        if ISCollapsableWindow.update then ISCollapsableWindow.update(self) end

        if self.width ~= self.lastWidth or self.height ~= self.lastHeight then
            self.lastWidth, self.lastHeight = self.width, self.height
            self:layout()
            self:refreshToggles()
            self.geometryDirty = true
        end

        -- polling the search box instead of hooking onTextChange keeps this
        -- working across builds where that callback was renamed
        local text = self:currentSearch()
        if text ~= self.searchText then
            self.searchText = text
            self:refreshList()
            self.lastRefresh = getTimestampMs()
            return
        end

        local now = getTimestampMs()
        if now - (self.lastRefresh or 0) >= REFRESH_MS then
            self.lastRefresh = now
            self:refreshList()
        end
    end

    function Window:isSearchFocused()
        local ok, focused = VF.safe(function()
            return self.searchEntry and self.searchEntry:isFocused()
        end)
        return ok and focused == true
    end

    function Window:saveGeometry()
        VF.config.windowX = self:getX()
        VF.config.windowY = self:getY()
        VF.config.windowW = self:getWidth()
        VF.config.windowH = self:getHeight()
        VF.saveConfig()
    end

    function Window:close()
        self:saveGeometry()
        ISCollapsableWindow.close(self)
        VF.window = nil
    end

    VF.WindowClass = Window
    return Window
end
