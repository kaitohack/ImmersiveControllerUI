
--==============================================================
-- Immersive Controller UI
-- Visibility.lua
-- Core HUD and full interface visibility management
--==============================================================

local addonName, addon = ...

local visibility = {
    coreState = nil,
    fullUIVisible = false,

    conditions = {
        inCombat = false,
        hardTarget = false,
        softTarget = false,

        coreControllerModifier = false,

        fullUIReveal = false,
    },

    fullUIHoldUntil = 0,

    testOverride = nil,
}

addon.visibility = visibility

local conditions = visibility.conditions

local CHECK_INTERVAL = 0.05
local checkElapsed = 0

-- Last known cursor position, used to detect real mouse movement.
local lastCursorX = nil
local lastCursorY = nil

--==============================================================
-- SAFE HELPERS
--==============================================================

local function IsSecret(value)

    return issecretvalue and issecretvalue(value)

end

local function SafeBoolean(callback, ...)

    if type(callback) ~= "function" then
        return false
    end

    local ok, value = pcall(callback, ...)

    if ok and type(value) == "boolean" and not IsSecret(value) then
        return value
    end

    return false
end

local function GetCurrentTime()

    if type(GetTime) == "function" then
        return GetTime()
    end

    return 0
end

-- Match FaderGP's gamepad-mode detection so mouse movement only reveals
-- the UI while the player is using the gamepad interface.
local function IsGamepadActive()

    if C_InputInterfaceStyle
        and type(C_InputInterfaceStyle.GetCurrentStyle) == "function"
        and Enum
        and Enum.InputDeviceInterfaceType then

        local ok, style = pcall(C_InputInterfaceStyle.GetCurrentStyle)

        if ok and not IsSecret(style) then
            return style == Enum.InputDeviceInterfaceType.Gamepad
        end
    end

    return InputUtil
        and SafeBoolean(InputUtil.IsGamepadUIEnabled)
        or false
end

local function GetHoldDuration()

    local duration = addon.db
        and addon.db.fullOpacityHoldDuration

    if type(duration) ~= "number" then
        duration = 3
    end

    return math.max(0, duration)
end

local function GetSoftTargetOpacity()

    local opacity = addon.db
        and addon.db.softTargetOpacity

    if type(opacity) ~= "number" then
        opacity = 0.25
    end

    return math.max(0, math.min(1, opacity))
end

--==============================================================
-- MOUSE MOVEMENT DETECTION
--==============================================================

local function ReadCursorPosition()

    if type(GetCursorPosition) ~= "function" then
        return nil, nil
    end

    local ok, x, y = pcall(GetCursorPosition)

    if not ok
        or type(x) ~= "number"
        or type(y) ~= "number"
        or IsSecret(x)
        or IsSecret(y) then

        return nil, nil
    end

    return x, y
end

local function ResetCursorTracking()

    lastCursorX = nil
    lastCursorY = nil
end

local function CheckForMouseMovement()

    -- The setting defaults to enabled when it is absent from saved data.
    if addon.db and addon.db.mouseMovementReveal == false then
        ResetCursorTracking()
        return false
    end

    -- Do not let ordinary desktop mouse movement reveal the HUD.
    if not IsGamepadActive() then
        ResetCursorTracking()
        return false
    end

    local x, y = ReadCursorPosition()

    if x == nil or y == nil then
        ResetCursorTracking()
        return false
    end

    -- The first sample establishes a baseline; it is not movement.
    if lastCursorX == nil or lastCursorY == nil then
        lastCursorX = x
        lastCursorY = y
        return false
    end

    local moved = x ~= lastCursorX or y ~= lastCursorY

    lastCursorX = x
    lastCursorY = y

    if moved then
        -- Share the existing full-UI hold timer. This does not start a
        -- separate core-HUD hold and does not modify controller conditions.
        visibility.fullUIHoldUntil =
            GetCurrentTime() + GetHoldDuration()
    end

    return moved
end

--==============================================================
-- TARGET DETECTION
--==============================================================

local function HasSoftTarget()

    local softEnemyExists =
        SafeBoolean(UnitExists, "softenemy")

    local softEnemyAttackable = false

    if softEnemyExists then

        softEnemyAttackable =
            SafeBoolean(UnitCanAttack, "player", "softenemy")

    end

    local softFriendExists =
        SafeBoolean(UnitExists, "softfriend")

    return softEnemyAttackable or softFriendExists
end

--==============================================================
-- CORE VISIBILITY REQUIREMENTS
--==============================================================

local function IsCoreFullRequired()

    return visibility.testOverride == "full"
        or conditions.inCombat
        or conditions.hardTarget
        or conditions.coreControllerModifier
        or conditions.fullUIReveal
end

local function IsCoreSoftRequired()

    if visibility.testOverride ~= nil then
        return visibility.testOverride == "soft"
    end

    return conditions.softTarget
end

--==============================================================
-- FULL UI VISIBILITY REQUIREMENTS
--==============================================================

local function IsFullUIRequired()

    return conditions.fullUIReveal
end

--==============================================================
-- CALCULATE CORE HUD STATE
--==============================================================

local function CalculateCoreState(fullUIVisible)

    if IsCoreFullRequired() or fullUIVisible then
        return "full"
    end

    if IsCoreSoftRequired() then
        return "soft"
    end

    return "hidden"
end

--==============================================================
-- CALCULATE FULL UI VISIBILITY
--==============================================================

local function CalculateFullUIVisibility()

    local now = GetCurrentTime()

    local fullRequired = IsFullUIRequired()

    if fullRequired then

        visibility.fullUIHoldUntil =
            now + GetHoldDuration()

    end

    return fullRequired
        or now < visibility.fullUIHoldUntil
end

--==============================================================
-- APPLY VISIBILITY
--==============================================================

function addon:UpdateVisibility()

    local newFullUIVisible = CalculateFullUIVisibility()
    local newCoreState = CalculateCoreState(newFullUIVisible)

    visibility.coreState = newCoreState
    visibility.fullUIVisible = newFullUIVisible

    local coreOpacity = 0

    if newCoreState == "full" then

        coreOpacity = 1

    elseif newCoreState == "soft" then

        coreOpacity = GetSoftTargetOpacity()

    end

    if type(self.ApplyUIVisibility) == "function" then

        self:ApplyUIVisibility(
            coreOpacity,
            newFullUIVisible
        )
    end
end

--==============================================================
-- PUBLIC CONDITION API
--==============================================================

function addon:SetVisibilityCondition(condition, value)

    if conditions[condition] == nil then

        self:Print(
            "[Visibility] Unknown condition: " ..
            tostring(condition)
        )

        return
    end

    value = value == true

    if conditions[condition] == value then
        return
    end

    conditions[condition] = value

    self:UpdateVisibility()
end

--==============================================================
-- REFRESH GAME CONDITIONS
--==============================================================

function addon:RefreshGameConditions()

    if visibility.testOverride ~= nil then
        return
    end

    conditions.inCombat =
        SafeBoolean(InCombatLockdown)

    conditions.hardTarget =
        SafeBoolean(UnitExists, "target")

    conditions.softTarget =
        HasSoftTarget()

    self:UpdateVisibility()
end

--==============================================================
-- DEBUG / TEST OVERRIDES
--==============================================================

function addon:SetVisibilityTest(mode)

    if mode == "real" or mode == nil then

        visibility.testOverride = nil

        visibility.fullUIHoldUntil = 0

        self:RefreshGameConditions()

        self:Print(
            "[Visibility] Returning to real game conditions."
        )

        return
    end

    if mode ~= "full"
        and mode ~= "soft"
        and mode ~= "idle" then

        self:Print(
            "[Visibility] Invalid test mode. Use full, soft, idle, or real."
        )

        return
    end

    visibility.testOverride = mode

    visibility.fullUIHoldUntil = 0

    self:UpdateVisibility()

    self:Print(
        "[Visibility] Test mode: " .. mode
    )
end

--==============================================================
-- GAME EVENTS
--==============================================================

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

eventFrame:RegisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
eventFrame:RegisterEvent("PLAYER_SOFT_FRIEND_CHANGED")
eventFrame:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event)

    addon:RefreshGameConditions()
end)

--==============================================================
-- HIDE GAMEPAD CENTER DOT
--==============================================================

local function HideGamepadCenterDot()

    -- GamepadReticle may not exist immediately after login, so this
    -- function safely retries through ICUI's existing polling loop.
    local reticle = GamepadReticle

    if not reticle or IsSecret(reticle) then
        return
    end

    local icons
    local ok = pcall(function()
        icons = reticle.Icons
    end)

    if not ok then
        icons = nil
    end

    local dot

    if icons and not IsSecret(icons) then
        pcall(function()
            dot = icons.StandardIcon
        end)
    end

    -- Older clients expose StandardIcon directly on GamepadReticle.
    if not dot then
        pcall(function()
            dot = reticle.StandardIcon
        end)
    end

    if not dot or IsSecret(dot) then
        return
    end

    if type(dot.SetAlpha) ~= "function" then
        return
    end

    -- Avoid repeatedly writing alpha when it is already zero.
    if type(dot.GetAlpha) == "function" then

        local alphaOK, alpha = pcall(dot.GetAlpha, dot)

        if alphaOK
            and type(alpha) == "number"
            and not IsSecret(alpha)
            and alpha == 0 then
            return
        end
    end

    pcall(dot.SetAlpha, dot, 0)
end

--==============================================================
-- HOLD TIMER AND MOUSE POLLING
--==============================================================

local updateFrame = CreateFrame("Frame")

updateFrame:SetScript("OnUpdate", function(self, elapsed)

    checkElapsed = checkElapsed + elapsed

    if checkElapsed < CHECK_INTERVAL then
        return
    end

    checkElapsed = 0

    -- Keep the center dot hidden without affecting the swing timer.
    HideGamepadCenterDot()

    -- Mouse movement may reveal the full UI, but opening an interface
    -- window no longer reveals the entire interface automatically.
    if visibility.testOverride == nil then
        CheckForMouseMovement()
    else
        ResetCursorTracking()
    end

    addon:UpdateVisibility()
end)

--==============================================================
-- INITIALIZATION
--==============================================================

