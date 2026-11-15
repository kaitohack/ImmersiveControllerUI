local addonName, addon = ...

--==============================================================
-- Immersive Controller UI - Settings
-- Registers a custom panel under Options -> AddOns.
-- Supports the modern Settings API and the legacy Interface Options API.
--==============================================================

local PANEL_NAME = "Immersive Controller UI"
local PANEL_WIDTH = 650
local PANEL_HEIGHT = 650

local panel
local controls = {}
local refreshing = false
local sliderCounter = 0
local checkboxCounter = 0
local buttonCounter = 0

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

local function RefreshAddon()
    if type(addon.UpdateVisibility) == "function" then
        addon:UpdateVisibility()
    end
end

local function SetValue(key, value)
    if not addon.db then
        return
    end

    addon.db[key] = value
    RefreshAddon()
end

local function SetOptionalValue(key, value)
    if not addon.db then
        return
    end

    addon.db.optionalUI = addon.db.optionalUI or {}
    addon.db.optionalUI[key] = value
    RefreshAddon()
end

local function AddRefresh(callback)
    controls[#controls + 1] = callback
end

local function RefreshControls()
    if not addon.db then
        return
    end

    refreshing = true

    for _, callback in ipairs(controls) do
        callback()
    end

    refreshing = false
end

local function CreateSection(parent, text, x, y)
    local heading = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    heading:SetText(text)
    return heading
end

local function CreateSlider(parent, label, key, x, y, minValue, maxValue, step, formatValue)
    sliderCounter = sliderCounter + 1

    local name = "ICUI_SettingsSlider" .. sliderCounter
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    slider:SetWidth(260)
    slider:SetHeight(16)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)

    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end

    local title = _G[name .. "Text"]
    local low = _G[name .. "Low"]
    local high = _G[name .. "High"]

    if title then
        title:SetText(label)
    end

    if low then
        low:SetText(formatValue(minValue))
    end

    if high then
        high:SetText(formatValue(maxValue))
    end

    local valueText = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 12, 0)

    local function GetStoredValue()
        return tonumber(addon.db and addon.db[key]) or minValue
    end

    local function UpdateLabel(value)
        valueText:SetText(formatValue(value))
    end

    slider:SetScript("OnValueChanged", function(self, value)
        value = tonumber(value) or minValue
        value = math.floor((value / step) + 0.5) * step
        value = math.max(minValue, math.min(maxValue, value))

        UpdateLabel(value)

        if not refreshing and addon.db then
            addon.db[key] = value
            RefreshAddon()
        end
    end)

    AddRefresh(function()
        local value = GetStoredValue()
        slider:SetValue(value)
        UpdateLabel(value)
    end)

    return slider
end

local function CreateCheckbox(parent, label, getter, setter, x, y, tooltip)
    checkboxCounter = checkboxCounter + 1

    local name = "ICUI_SettingsCheck" .. checkboxCounter
    local check = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    check:SetSize(24, 24)
    check:SetHitRectInsets(0, -190, 0, 0)

    local text = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", check, "RIGHT", 4, 0)
    text:SetText(label)

    if tooltip then
        check.tooltipText = tooltip
        check:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
                GameTooltip:Show()
            end
        end)
        check:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
    end

    check:SetScript("OnClick", function(self)
        if not refreshing then
            setter(self:GetChecked() == true)
        end
    end)

    AddRefresh(function()
        check:SetChecked(getter() == true)
    end)

    return check
end

local function CreateBehaviorChoice(parent, label, value, x, y)
    return CreateCheckbox(
        parent,
        label,
        function()
            return addon.db and addon.db.ltRtFullUIBehavior == value
        end,
        function(checked)
            if checked then
                SetValue("ltRtFullUIBehavior", value)
                RefreshControls()
            else
                -- Keep one choice selected at all times.
                RefreshControls()
            end
        end,
        x,
        y
    )
end

local function CreateButton(parent, label, x, y, width, callback)
    buttonCounter = buttonCounter + 1

    local button = CreateFrame("Button", "ICUI_SettingsButton" .. buttonCounter, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 150, 26)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(label)
    button:SetScript("OnClick", callback)
    return button
end

local function RestoreDefaults()
    if not addon.db or type(addon.defaults) ~= "table" then
        return
    end

    for key, value in pairs(addon.defaults) do
        addon.db[key] = CopyValue(value)
    end

    RefreshControls()
    RefreshAddon()

    if type(addon.Print) == "function" then
        addon:Print("Settings restored to defaults.")
    end
end

local function BuildPanel()
    if panel then
        return panel
    end

    panel = CreateFrame("Frame", "ImmersiveControllerUIOptionsPanel")
    panel.name = PANEL_NAME
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText(PANEL_NAME)

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("Changes are saved automatically and apply immediately.")

    -- Left column: opacity, timing, controller, and mouse behavior.
    CreateSection(panel, "Core HUD", 20, -78)

    CreateSlider(panel, "Soft-target opacity", "softTargetOpacity", 20, -108,
        0, 1, 0.05, function(value)
            return string.format("%d%%", math.floor(value * 100 + 0.5))
        end)

    CreateSection(panel, "Fade and timing", 20, -174)

    CreateSlider(panel, "Fade-in duration", "fadeInDuration", 20, -204,
        0, 2, 0.05, function(value)
            return string.format("%.2f s", value)
        end)

    CreateSlider(panel, "Fade-out duration", "fadeOutDuration", 20, -254,
        0, 2, 0.05, function(value)
            return string.format("%.2f s", value)
        end)

    CreateSlider(panel, "Full UI hold duration", "fullOpacityHoldDuration", 20, -304,
        0, 10, 0.25, function(value)
            return string.format("%.2f s", value)
        end)

    CreateSection(panel, "Controller behavior", 20, -374)

    local behaviorLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    behaviorLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -402)
    behaviorLabel:SetText("LT + RT reveals the full UI:")

    CreateBehaviorChoice(panel, "Always", "always", 20, -427)
    CreateBehaviorChoice(panel, "Only out of combat", "outOfCombat", 20, -457)

    CreateCheckbox(panel, "LT + LB reveals the full UI", function()
        return addon.db and addon.db.ltLbFullUIEnabled
    end, function(value)
        SetValue("ltLbFullUIEnabled", value)
    end, 20, -492)

    CreateCheckbox(panel, "Reveal full UI when the mouse moves", function()
        return addon.db and addon.db.mouseMovementReveal
    end, function(value)
        SetValue("mouseMovementReveal", value)
    end, 20, -527,
        "Mouse movement reveals the full UI and refreshes its hold timer.")

    -- Right column: elements controlled by ICUI.
    CreateSection(panel, "Optional UI elements", 340, -78)

    local optionalRows = {
        { "Minimap", "minimap" },
        { "Chat windows", "chat" },
        { "Quest tracker", "questTracker" },
        { "XP bar", "xpBar" },
        { "Micro menu", "microMenu" },
        { "Bags bar", "bags" },
    }

    local rowY = -110

    for _, row in ipairs(optionalRows) do
        local label = row[1]
        local key = row[2]

        CreateCheckbox(panel, label, function()
            return addon.db
                and addon.db.optionalUI
                and addon.db.optionalUI[key]
        end, function(value)
            SetOptionalValue(key, value)
        end, 340, rowY)

        rowY = rowY - 34
    end

    local optionalNote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    optionalNote:SetPoint("TOPLEFT", panel, "TOPLEFT", 368, rowY - 2)
    optionalNote:SetWidth(245)
    optionalNote:SetJustifyH("LEFT")
    optionalNote:SetText("Unchecked elements are left under normal game control. Chat is disabled by default.")

    CreateButton(panel, "Restore Defaults", 20, -580, 150, RestoreDefaults)

    local resetNote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    resetNote:SetPoint("LEFT", panel, "TOPLEFT", 184, -593)
    resetNote:SetText("Restores all ICUI settings to their defaults.")

    panel:SetScript("OnShow", RefreshControls)

    return panel
end

local function RegisterSettings()
    if not addon.db then
        if type(addon.Print) == "function" then
            addon:Print("Settings panel could not initialize: database is not ready.")
        end
        return
    end

    local optionsPanel = BuildPanel()

    if Settings and type(Settings.RegisterCanvasLayoutCategory) == "function"
        and type(Settings.RegisterAddOnCategory) == "function" then

        local category = Settings.RegisterCanvasLayoutCategory(
            optionsPanel,
            PANEL_NAME,
            PANEL_NAME
        )

        if category then
            category.ID = PANEL_NAME
            Settings.RegisterAddOnCategory(category)
        end

    elseif type(InterfaceOptions_AddCategory) == "function" then

        InterfaceOptions_AddCategory(optionsPanel)

    else

        if type(addon.Print) == "function" then
            addon:Print("This game client does not expose a supported AddOns settings API.")
        end
        return
    end

    addon.settingsPanel = optionsPanel

    if type(addon.Print) == "function" then
        addon:Print("Settings registered under Options > AddOns.")
    end
end

local registrationFrame = CreateFrame("Frame")
registrationFrame:RegisterEvent("PLAYER_LOGIN")
registrationFrame:SetScript("OnEvent", function(self, event)
    RegisterSettings()
    self:UnregisterEvent("PLAYER_LOGIN")
end)

-- Allow other addon code or slash commands to refresh the visible controls.
function addon:RefreshSettingsPanel()
    RefreshControls()
end
