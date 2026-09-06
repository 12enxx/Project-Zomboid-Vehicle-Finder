--[[
    Vehicle Finder - bootstrap.

    Hooks nothing but events: OnGameStart / OnKeyPressed / OnResolutionChange
    and friends. No vanilla file is required, patched or replaced anywhere in
    this mod, which is what keeps it alive across Build 42 updates and out of
    the way of other mods (vehicle mods included).
]]

VehicleFinder = VehicleFinder or {}
local VF = VehicleFinder

local TRACK_REFRESH_MS = 500

-- ------------------------------------------------------------ messaging ---

function VF.notify(message)
    local shown = false
    VF.safe(function()
        local player = getSpecificPlayer(0)
        if player and HaloTextHelper then
            HaloTextHelper.addText(player, message, HaloTextHelper.getColorGreen())
            shown = true
        end
    end)
    if not shown then VF.log(message) end
end

-- ----------------------------------------------------------- key binding ---

--- Registers a rebindable key in Options > Key bindings. Additive and
--- deduplicated: it never touches bindings owned by another mod, and the
--- player can move it if F8 clashes with something they already use.
function VF.registerKeyBinding()
    if VF.keyBindingRegistered then return true end
    if type(keyBinding) ~= "table" then return false end
    for i = 1, #keyBinding do
        if keyBinding[i] and keyBinding[i].value == VF.KEY_TOGGLE then
            VF.keyBindingRegistered = true
            return true
        end
    end
    table.insert(keyBinding, { value = "[Vehicle Finder]" })
    table.insert(keyBinding, { value = VF.KEY_TOGGLE, key = Keyboard.KEY_F8 })
    VF.keyBindingRegistered = true
    return true
end

function VF.getToggleKey()
    local ok, key = VF.safe(function() return getCore():getKey(VF.KEY_TOGGLE) end)
    if ok and type(key) == "number" and key > 0 then return key end
    return Keyboard.KEY_F8
end

function VF.getToggleKeyName()
    local key = VF.getToggleKey()
    local ok, name = VF.safe(function()
        if getKeyName then return getKeyName(key) end
        if Keyboard and Keyboard.getKeyName then return Keyboard.getKeyName(key) end
        return nil
    end)
    if ok and name and name ~= "" then return tostring(name) end
    return "F8"
end

--- True while the player is typing somewhere, so the hotkey never eats a
--- keystroke meant for the chat box or another mod's search field.
function VF.isTyping()
    if VF.window and VF.window.isSearchFocused and VF.window:isSearchFocused() then
        return true
    end
    local ok, chatting = VF.safe(function()
        return ISChat ~= nil and ISChat.instance ~= nil
            and ISChat.instance.textEntry ~= nil
            and ISChat.instance.textEntry:isFocused() == true
    end)
    return (ok and chatting) == true
end

-- ----------------------------------------------------------------- state ---

function VF.isWindowOpen()
    if not VF.window then return false end
    local ok, visible = VF.safe(function() return VF.window:getIsVisible() end)
    return ok and visible == true
end

function VF.openWindow()
    if not VF.buildWindowClass() then return end
    if VF.window then
        VF.window:setVisible(true)
        VF.safe(function() VF.window:addToUIManager() end)
        return VF.window
    end

    local w = VF.config.windowW or VF.defaults.windowW
    local h = VF.config.windowH or VF.defaults.windowH
    local sw, sh = VF.screenWidth(), VF.screenHeight()
    w = VF.clamp(w, 280, sw)
    h = VF.clamp(h, 220, sh)
    local x, y = VF.config.windowX, VF.config.windowY
    if not x or not y or x < 0 or y < 0 then
        x = math.floor((sw - w) / 2)
        y = math.floor((sh - h) / 2)
    end
    x = VF.clamp(x, 0, math.max(0, sw - w))
    y = VF.clamp(y, 0, math.max(0, sh - h))

    VF.window = VF.WindowClass:new(x, y, w, h)
    VF.window:initialise()
    VF.window:instantiate()
    VF.window:addToUIManager()
    VF.window:setVisible(true)
    return VF.window
end

function VF.closeWindow()
    if not VF.window then return end
    VF.safe(function() VF.window:close() end)
    VF.window = nil
end

function VF.toggleWindow()
    if VF.isWindowOpen() then
        VF.closeWindow()
    else
        VF.openWindow()
    end
end

--- Keeps the tracked vehicle's distance/direction fresh while the window is
--- closed, so the pip on the toggle button stays correct. Throttled.
function VF.updateTrackerIfNeeded()
    if not VF.trackedId then return end
    if VF.isWindowOpen() then return end
    local now = getTimestampMs()
    if now - (VF._lastTrack or 0) < TRACK_REFRESH_MS then return end
    VF._lastTrack = now
    VF.updateTracked()
end

-- ---------------------------------------------------------------- button ---

function VF.createButton()
    if VF.button then
        VF.button:setVisible(true)
        return VF.button
    end
    if not VF.buildButtonClass() then return nil end

    local size = VF.config.buttonSize or VF.defaults.buttonSize
    local x, y = VF.config.buttonX, VF.config.buttonY
    if not x or not y or x < 0 or y < 0 then
        x, y = VF.pickButtonPosition(size, size)
        VF.config.buttonX, VF.config.buttonY = x, y
        VF.saveConfig()
    end
    x = VF.clamp(x, 0, math.max(0, VF.screenWidth() - size))
    y = VF.clamp(y, 0, math.max(0, VF.screenHeight() - size))

    VF.button = VF.ButtonClass:new(x, y, size)
    VF.button:initialise()
    VF.button:instantiate()
    VF.button:addToUIManager()
    return VF.button
end

function VF.destroyButton()
    if not VF.button then return end
    VF.safe(function() VF.button:removeFromUIManager() end)
    VF.button = nil
end

function VF.setButtonVisible(visible)
    VF.config.buttonVisible = visible and true or false
    VF.saveConfig()
    if visible then
        VF.createButton()
    else
        VF.destroyButton()
        VF.notify(string.format(
            VF.text("IGUI_VehicleFinder_HiddenHint", "Vehicle Finder button hidden - press %s to open the window"),
            VF.getToggleKeyName()))
    end
end

function VF.setButtonSize(size)
    VF.config.buttonSize = size
    VF.saveConfig()
    VF.destroyButton()
    VF.createButton()
end

function VF.resetButtonPosition()
    VF.config.buttonX, VF.config.buttonY = -1, -1
    VF.saveConfig()
    VF.destroyButton()
    VF.createButton()
end

-- ----------------------------------------------------------- life cycle ---

function VF.ensureUI()
    if not VF.config or VF.config.buttonSize == nil then VF.loadConfig() end
    if VF.config.buttonVisible then VF.createButton() end
end

function VF.setMapMarkers(enabled)
    VF.config.mapMarkers = enabled and true or false
    VF.saveConfig()
    if not VF.config.mapMarkers and VF.map and VF.map.destroy then VF.map.destroy() end
end

function VF.teardown()
    VF.closeWindow()
    VF.destroyButton()
    VF.setTracked(nil)
    if VF.map and VF.map.destroy then VF.map.destroy() end
    if VF.history and VF.history.reset then VF.history.reset() end
end

local function onGameStart()
    VF.safe(function()
        VF.loadConfig()
        VF.registerKeyBinding()
        VF.ensureUI()
        VF.log("ready, toggle key = " .. VF.getToggleKeyName())
    end)
end

local function onKeyPressed(key)
    if key ~= VF.getToggleKey() then return end
    if not getSpecificPlayer(0) then return end
    if VF.isTyping() then return end
    VF.safe(function()
        VF.ensureUI()
        VF.toggleWindow()
    end)
end

local function onResolutionChange()
    VF.safe(function()
        if VF.button then
            VF.button:clampToScreen()
            VF.button:savePosition()
        end
        if VF.window then
            local sw, sh = VF.screenWidth(), VF.screenHeight()
            VF.window:setX(VF.clamp(VF.window:getX(), 0, math.max(0, sw - VF.window:getWidth())))
            VF.window:setY(VF.clamp(VF.window:getY(), 0, math.max(0, sh - VF.window:getHeight())))
        end
    end)
end

local function onPlayerDeath(player)
    if player ~= getSpecificPlayer(0) then return end
    VF.safe(function() VF.closeWindow() end)
    VF.setTracked(nil)
end

-- Bind once, even if this file is loaded twice. That happens when the same
-- mod is installed in two places at the same time (a local copy in
-- Zomboid/mods and a Workshop copy, for instance): without this guard every
-- handler would run twice and the hotkey would open and close the window in
-- the same keystroke.
if not VF.eventsBound then
    VF.eventsBound = true
    VF.registerKeyBinding()
    VF.addEvent("OnGameBoot", VF.registerKeyBinding)
    VF.addEvent("OnGameStart", onGameStart)
    VF.addEvent("OnKeyPressed", onKeyPressed)
    VF.addEvent("OnResolutionChange", onResolutionChange)
    VF.addEvent("OnPlayerDeath", onPlayerDeath)
    VF.addEvent("OnMainMenuEnter", VF.teardown)
else
    VF.log("already loaded, skipping the second registration")
end
