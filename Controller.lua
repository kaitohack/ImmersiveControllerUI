
--==============================================================
-- Immersive Controller UI
-- Controller.lua
-- Hybrid native and mapped controller detection
--==============================================================

local addonName, addon = ...

addon.controller = {
    leftTriggerDown = false,
    rightTriggerDown = false,
    leftShoulderDown = false,
    rightShoulderDown = false,

    bothTriggersDown = false,
    bothShouldersDown = false,

    gamepadActive = false,
    liveDiagnostics = false,
}

local controller = addon.controller

local CHECK_INTERVAL = 0.05
local checkElapsed = 0

--==============================================================
-- SAFE API HELPERS
--==============================================================

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function ReadBoolean(callback, ...)
    if type(callback) ~= "function" then
        return nil
    end

    local ok, value = pcall(callback, ...)

    if ok and type(value) == "boolean" and not IsSecret(value) then
        return value
    end

    return nil
end

--==============================================================
-- DETECT GAMEPAD MODE
--==============================================================

local function IsGamepadActive()

    if C_InputInterfaceStyle
        and type(C_InputInterfaceStyle.GetCurrentStyle) == "function"
        and Enum
        and Enum.InputDeviceInterfaceType then

        local ok, style = pcall(
            C_InputInterfaceStyle.GetCurrentStyle
        )

        if ok and not IsSecret(style) then
            return style == Enum.InputDeviceInterfaceType.Gamepad
        end
    end

    if InputUtil
        and type(InputUtil.IsGamepadUIEnabled) == "function" then

        return ReadBoolean(InputUtil.IsGamepadUIEnabled) == true
    end

    return false
end

--==============================================================
-- MAPPED BUTTON STATE
--==============================================================

local function ReadMappedButton(buttonIndex)

    if not C_GamePad
        or type(C_GamePad.GetDeviceMappedState) ~= "function" then
        return false
    end

    local deviceID = nil

    if type(C_GamePad.GetActiveDeviceID) == "function" then
        local ok, result = pcall(C_GamePad.GetActiveDeviceID)

        if ok then
            deviceID = result
        end
    end

    local ok, state = pcall(function()
        return C_GamePad.GetDeviceMappedState(deviceID)
    end)

    if not ok or not state or not state.buttons then
        return false
    end

    local value = state.buttons[buttonIndex]

    return value == true and not IsSecret(value)
end

--==============================================================
-- CONTROLLER INPUT ABSTRACTION
--==============================================================

local function IsLTDown()
    return ReadBoolean(GamepadMode.IsLeftModifierDown) == true
end

local function IsRTDown()
    return ReadBoolean(GamepadMode.IsRightModifierDown) == true
end

local function IsLBDown()
    return ReadBoolean(IsKeyDown, "PADLSHOULDER") == true
end

local function IsRBDown()
    return ReadBoolean(IsKeyDown, "PADRSHOULDER") == true
end

--==============================================================
-- REFRESH CONTROLLER STATE
--==============================================================

function addon.controller:Refresh()

    local previous = {
        leftTrigger = self.leftTriggerDown,
        rightTrigger = self.rightTriggerDown,
        leftShoulder = self.leftShoulderDown,
        rightShoulder = self.rightShoulderDown,
    }

    self.gamepadActive = IsGamepadActive()

    if self.gamepadActive then

        self.leftTriggerDown = IsLTDown()
        self.rightTriggerDown = IsRTDown()

        self.leftShoulderDown = IsLBDown()
        self.rightShoulderDown = IsRBDown()

    else

        self.leftTriggerDown = false
        self.rightTriggerDown = false
        self.leftShoulderDown = false
        self.rightShoulderDown = false

    end

    self.bothTriggersDown =
        self.leftTriggerDown and self.rightTriggerDown

    self.bothShouldersDown =
        self.leftShoulderDown and self.rightShoulderDown

    --==============================================================
    -- VISIBILITY CONDITIONS
    --==============================================================

    local inCombat = InCombatLockdown()

    -- Core UI:
    -- LT OR RT OR LB + RB

    local coreReveal =
        self.leftTriggerDown
        or self.rightTriggerDown
        or self.bothShouldersDown

    addon:SetVisibilityCondition(
        "coreControllerModifier",
        coreReveal
    )

    -- Full UI: LT + LB
    local ltLbReveal =
        self.leftTriggerDown
        and self.leftShoulderDown
        and (addon.db.ltLbFullUIEnabled ~= false)

    -- Full UI: LT + RT
    local ltRtBehavior = addon.db.ltRtFullUIBehavior or "outOfCombat"

    local ltRtReveal = self.bothTriggersDown
        and (
            ltRtBehavior == "always"
            or (ltRtBehavior == "outOfCombat" and not inCombat)
        )

    -- Combine full UI triggers.
    local fullUIReveal = ltLbReveal or ltRtReveal

    addon:SetVisibilityCondition(
        "fullUIReveal",
        fullUIReveal
    )

    --==========================================================
    -- DIAGNOSTICS
    --==========================================================

    if self.liveDiagnostics then

        if previous.leftTrigger ~= self.leftTriggerDown then
            addon:Print(
                "LT: " ..
                (self.leftTriggerDown and "PRESSED" or "RELEASED")
            )
        end

        if previous.rightTrigger ~= self.rightTriggerDown then
            addon:Print(
                "RT: " ..
                (self.rightTriggerDown and "PRESSED" or "RELEASED")
            )
        end

        if previous.leftShoulder ~= self.leftShoulderDown then
            addon:Print(
                "LB: " ..
                (self.leftShoulderDown and "PRESSED" or "RELEASED")
            )
        end

        if previous.rightShoulder ~= self.rightShoulderDown then
            addon:Print(
                "RB: " ..
                (self.rightShoulderDown and "PRESSED" or "RELEASED")
            )
        end

    end
end

--==============================================================
-- INSPECT NATIVE CONTROLLER APIS
--==============================================================

function addon:InspectControllerAPIs()

    self:Print("[Controller] Inspecting APIs...")

    self:Print("GamepadMode: " .. type(GamepadMode))
    self:Print("C_GamePad: " .. type(C_GamePad))

    if type(GamepadMode) == "table" then

        self:Print(
            "IsLeftModifierDown: " ..
            type(GamepadMode.IsLeftModifierDown)
        )

        self:Print(
            "IsRightModifierDown: " ..
            type(GamepadMode.IsRightModifierDown)
        )

    end

    if type(C_GamePad) == "table" then

        self:Print(
            "GetDeviceMappedState: " ..
            type(C_GamePad.GetDeviceMappedState)
        )

    end

    self.controller.liveDiagnostics =
        not self.controller.liveDiagnostics

    self.controller:Refresh()

    self:Print(
        "Gamepad active: " ..
        tostring(self.controller.gamepadActive)
    )

    self:Print(
        "Live diagnostics: " ..
        (self.controller.liveDiagnostics and "ON" or "OFF")
    )
end

--==============================================================
-- CONTROLLER POLLING
--==============================================================

local controllerFrame = CreateFrame("Frame")

controllerFrame:SetScript("OnUpdate", function(self, elapsed)

    checkElapsed = checkElapsed + elapsed

    if checkElapsed < CHECK_INTERVAL then
        return
    end

    checkElapsed = 0

    controller:Refresh()
end)

--==============================================================
-- INITIALIZATION
--==============================================================

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function()

    controller:Refresh()

    addon:Print(
        "[Controller] Native controller detection initialized."
    )
end)
