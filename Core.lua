local addonName, addon = ...

--==============================================================
-- DEFAULT CONFIGURATION
--==============================================================

addon.defaults = {
    -- Core HUD
    softTargetOpacity = 0.25,

    -- Fade timing
    fadeInDuration = 0.25,
    fadeOutDuration = 0.25,
    fullOpacityHoldDuration = 3,

    -- Controller behavior
    ltRtFullUIBehavior = "outOfCombat",
    ltLbFullUIEnabled = true,

    -- Mouse behavior
    mouseMovementReveal = true,

    -- Optional UI elements
    optionalUI = {
        minimap = true,
        chat = false,
        questTracker = true,
        xpBar = true,
        microMenu = true,
        bags = true,
    },
}

--==============================================================
-- DATABASE INITIALIZATION
--==============================================================

local function InitializeDatabase()

    if type(ImmersiveControllerUIDB) ~= "table" then
        ImmersiveControllerUIDB = {}
    end

    local db = ImmersiveControllerUIDB

    -- Migrate the previous fadeDuration setting.
    if db.fadeInDuration == nil then
        db.fadeInDuration = db.fadeDuration or addon.defaults.fadeInDuration
    end

    if db.fadeOutDuration == nil then
        db.fadeOutDuration = db.fadeDuration or addon.defaults.fadeOutDuration
    end

    -- Initialize missing settings without overwriting saved choices.
    for key, value in pairs(addon.defaults) do

        if db[key] == nil then

            if type(value) == "table" then
                db[key] = {}

                for subKey, subValue in pairs(value) do
                    db[key][subKey] = subValue
                end
            else
                db[key] = value
            end

        elseif type(value) == "table" and type(db[key]) == "table" then

            for subKey, subValue in pairs(value) do
                if db[key][subKey] == nil then
                    db[key][subKey] = subValue
                end
            end

        end
    end

    addon.db = db

end

local function CopyValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}

    for key, child in pairs(value) do
        copy[key] = CopyValue(child)
    end

    return copy
end

--==============================================================
-- CHAT OUTPUT
--==============================================================

function addon:Print(message)
    print("|cff66ccffICUI:|r " .. tostring(message))
end

--==============================================================
-- SLASH COMMANDS
--==============================================================

SLASH_IMMERSIVECONTROLLERUI1 = "/icui"

SlashCmdList["IMMERSIVECONTROLLERUI"] = function(message)

    message = (message or ""):lower():match("^%s*(.-)%s*$")

    if not addon.db then
        addon:Print("Database is not initialized.")
        return
    end

    if message == "status" then

        addon:Print("Addon is running.")
        addon:Print("Soft opacity: " ..
            math.floor(addon.db.softTargetOpacity * 100) .. "%")

        addon:Print("Fade in: " ..
            addon.db.fadeInDuration .. " seconds")
        addon:Print("Fade out: " ..
            addon.db.fadeOutDuration .. " seconds")

        addon:Print("Full opacity hold: " ..
            addon.db.fullOpacityHoldDuration .. " seconds")

        addon:Print("LT + RT behavior: " ..
            addon.db.ltRtFullUIBehavior)

        addon:Print("Mouse reveal: " ..
            tostring(addon.db.mouseMovementReveal))

        addon:Print(
            "Core HUD: " ..
            tostring(addon.visibility.coreState)
        )

        addon:Print(
            "Full UI: " ..
            tostring(addon.visibility.fullUIVisible)
        )

        addon:Print(
            "LT + RT: " ..
            tostring(addon.controller.bothTriggersDown)
        )

    elseif message == "reset" then

        -- Deep-copy nested defaults so the saved optionalUI table does not
        -- become shared with addon.defaults.
        for key, value in pairs(addon.defaults) do
            addon.db[key] = CopyValue(value)
        end

        if type(addon.UpdateVisibility) == "function" then
            addon:UpdateVisibility()
        end

        if type(addon.RefreshSettingsPanel) == "function" then
            addon:RefreshSettingsPanel()
        end

        addon:Print("Settings restored to defaults.")

    elseif message:match("^test ") then

        local mode = message:match("^test%s+(%S+)$")
        addon:SetVisibilityTest(mode)

    elseif message == "options" then

        if Settings and type(Settings.OpenToCategory) == "function" then
            Settings.OpenToCategory("Immersive Controller UI")
        elseif type(InterfaceOptionsFrame_OpenToCategory) == "function" then
            InterfaceOptionsFrame_OpenToCategory("Immersive Controller UI")
            InterfaceOptionsFrame_OpenToCategory("Immersive Controller UI")
        else
            addon:Print("Unable to open the settings panel on this client.")
        end

    else

        addon:Print("Available commands:")
        addon:Print("/icui status")
        addon:Print("/icui options")
        addon:Print("/icui reset")
        addon:Print("/icui test idle")

    end

end

--==============================================================
-- INITIALIZATION
--==============================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(self, event, loadedAddon)

    if loadedAddon ~= addonName then
        return
    end

    InitializeDatabase()

    self:UnregisterEvent("ADDON_LOADED")

end)
