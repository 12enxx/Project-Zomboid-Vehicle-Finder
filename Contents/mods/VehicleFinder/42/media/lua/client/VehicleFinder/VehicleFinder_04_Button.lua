--[[
    Vehicle Finder - the floating toggle button.

    The button is a standalone ISPanel added straight to the UI manager. It is
    deliberately NOT injected into the vanilla sidebar (MainScreen.lua): that
    file changes between builds, and patching it is what breaks mods on every
    Build 42 update. Nothing here depends on the internals of another UI.

    The class is built the first time it is needed, i.e. from inside a game
    event, so the mod never has to `require` a vanilla Lua file at load time.
]]

VehicleFinder = VehicleFinder or {}
local VF = VehicleFinder

local DRAG_THRESHOLD = 3   -- px of movement before a click becomes a drag

function VF.buildButtonClass()
    if VF.ButtonClass then return VF.ButtonClass end
    if not ISPanel then
        VF.warn("ISPanel is not loaded yet, button postponed")
        return nil
    end

    local Button = ISPanel:derive("VehicleFinder_ToggleButton")

    function Button:new(x, y, size)
        local o = ISPanel:new(x, y, size, size)
        setmetatable(o, self)
        self.__index = self
        o.iconSize = size
        o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.0 }
        o.borderColor = { r = 0, g = 0, b = 0, a = 0.0 }
        o.moveWithMouse = false
        o.hovered = false
        o.pressed = false
        o.dragged = false
        o.anchorLeft = true
        o.anchorTop = true
        o.anchorRight = false
        o.anchorBottom = false
        return o
    end

    function Button:onMouseDown(x, y)
        self.pressed = true
        self.dragged = false
        self.dragDist = 0
        self:setCapture(true)
        return true
    end

    function Button:onMouseMove(dx, dy)
        self.hovered = true
        if not self.pressed then return end
        self.dragDist = (self.dragDist or 0) + math.abs(dx) + math.abs(dy)
        if not self.dragged and self.dragDist > DRAG_THRESHOLD then
            self.dragged = true
        end
        if self.dragged then
            self:setX(self:getX() + dx)
            self:setY(self:getY() + dy)
            self:clampToScreen()
        end
    end

    function Button:onMouseMoveOutside(dx, dy)
        self.hovered = false
        if self.pressed then self:onMouseMove(dx, dy) end
    end

    function Button:onMouseUp(x, y)
        if not self.pressed then return end
        self.pressed = false
        self:setCapture(false)
        if self.dragged then
            self:savePosition()
        else
            VF.toggleWindow()
        end
        self.dragged = false
        return true
    end

    function Button:onMouseUpOutside(x, y)
        if not self.pressed then return end
        self.pressed = false
        self:setCapture(false)
        if self.dragged then self:savePosition() end
        self.dragged = false
    end

    function Button:onRightMouseUp(x, y)
        VF.safe(function() self:showContextMenu(x, y) end)
        return true
    end

    function Button:showContextMenu(x, y)
        local menu = ISContextMenu.get(0, self:getAbsoluteX() + x, self:getAbsoluteY() + y)
        if not menu then return end
        local open = VF.isWindowOpen()
        menu:addOption(open and VF.text("IGUI_VehicleFinder_Close", "Close Vehicle Finder")
                            or VF.text("IGUI_VehicleFinder_Open", "Open Vehicle Finder"),
                       self, function() VF.toggleWindow() end)
        if VF.trackedId then
            menu:addOption(VF.text("IGUI_VehicleFinder_ClearTarget", "Clear tracked vehicle"),
                           self, function() VF.setTracked(nil) end)
        end

        local sizeOption = menu:addOption(VF.text("IGUI_VehicleFinder_ButtonSize", "Button size"), self, nil)
        local sizeMenu = ISContextMenu.getNew(menu)
        menu:addSubMenu(sizeOption, sizeMenu)
        local sizes = { 32, 40, 48, 56 }
        for i = 1, #sizes do
            local px = sizes[i]
            local option = sizeMenu:addOption(px .. " px", self, function() VF.setButtonSize(px) end)
            if VF.config.buttonSize == px then
                sizeMenu:setOptionChecked(option, true)
            end
        end

        local markers = menu:addOption(VF.text("IGUI_VehicleFinder_MapDots", "Dots on the world map"),
                                       self, function() VF.setMapMarkers(not VF.config.mapMarkers) end)
        menu:setOptionChecked(markers, VF.config.mapMarkers == true)

        menu:addOption(VF.text("IGUI_VehicleFinder_ResetPos", "Reset button position"),
                       self, function() VF.resetButtonPosition() end)
        menu:addOption(VF.text("IGUI_VehicleFinder_HideButton", "Hide button (keyboard only)"),
                       self, function() VF.setButtonVisible(false) end)
    end

    function Button:clampToScreen()
        local sw, sh = VF.screenWidth(), VF.screenHeight()
        self:setX(VF.clamp(self:getX(), 0, math.max(0, sw - self:getWidth())))
        self:setY(VF.clamp(self:getY(), 0, math.max(0, sh - self:getHeight())))
    end

    function Button:savePosition()
        VF.config.buttonX = self:getX()
        VF.config.buttonY = self:getY()
        VF.saveConfig()
    end

    function Button:prerender()
        local size = self.iconSize
        local hovered = self.hovered or self.pressed
        local open = VF.isWindowOpen()

        -- plate
        self:drawRect(0, 0, size, size, hovered and 0.80 or 0.62, 0.09, 0.09, 0.10)
        -- border: amber while the window is open, lighter on hover
        if open then
            self:drawRectBorder(0, 0, size, size, 0.95, 0.78, 0.60, 0.26)
        elseif hovered then
            self:drawRectBorder(0, 0, size, size, 0.90, 0.72, 0.72, 0.68)
        else
            self:drawRectBorder(0, 0, size, size, 0.75, 0.38, 0.37, 0.35)
        end

        local pad = math.max(2, math.floor(size * 0.10))
        VF.drawIcon(self, pad, pad, size - pad * 2, hovered and 1.0 or 0.88)

        self:renderTracker(size)

        if hovered and not self.pressed then
            self:renderTooltip(size)
        end
    end

    --- Small pip on the button edge pointing at the tracked vehicle, plus the
    --- distance in tiles. No rotated textures, so it works on every build.
    function Button:renderTracker(size)
        local info = VF.trackedInfo
        if not info then return end
        local nx, ny = VF.worldToScreenDir(info.dx, info.dy)
        local radius = size / 2 - 3
        local cx, cy = size / 2, size / 2
        local px = cx + nx * radius - 2
        local py = cy + ny * radius - 2
        self:drawRect(px - 1, py - 1, 6, 6, 0.85, 0.05, 0.05, 0.05)
        self:drawRect(px, py, 4, 4, 1.0, 0.95, 0.78, 0.28)

        local label = tostring(math.floor(info.dist))
        local font = UIFont.Small
        local w = getTextManager():MeasureStringX(font, label)
        self:drawRect(size - w - 6, size - 14, w + 6, 14, 0.75, 0.05, 0.05, 0.05)
        self:drawText(label, size - w - 3, size - 15, 0.95, 0.80, 0.30, 1, font)
    end

    function Button:renderTooltip(size)
        local key = VF.getToggleKeyName()
        local label = VF.text("IGUI_VehicleFinder_Title", "Vehicle Finder")
        if key then label = label .. "  [" .. key .. "]" end
        local font = UIFont.Small
        local w = getTextManager():MeasureStringX(font, label) + 10
        local h = getTextManager():getFontHeight(font) + 6
        local x = size + 6
        if self:getX() + size + 6 + w > VF.screenWidth() then x = -w - 6 end
        local y = (size - h) / 2
        self:drawRect(x, y, w, h, 0.85, 0.05, 0.05, 0.05)
        self:drawRectBorder(x, y, w, h, 0.8, 0.45, 0.44, 0.40)
        self:drawText(label, x + 5, y + 3, 0.92, 0.92, 0.88, 1, font)
    end

    function Button:update()
        -- hide the button whenever there is no live player (death, main menu)
        local player = getSpecificPlayer(0)
        local alive = player ~= nil
        if alive then
            local ok, dead = VF.safe(function() return player:isDead() end)
            if ok and dead then alive = false end
        end
        if not alive and self:getIsVisible() then
            self:setVisible(false)
        elseif alive and not self:getIsVisible() and VF.config.buttonVisible then
            self:setVisible(true)
        end
        if not self.pressed then self.hovered = self:isMouseOver() end
        VF.updateTrackerIfNeeded()
    end

    VF.ButtonClass = Button
    return Button
end
