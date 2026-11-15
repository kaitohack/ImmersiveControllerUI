local addonName, addon = ...

-- Immersive Controller UI - UI visibility and fade handling.
-- This file owns frame alpha changes and the minimap's special Hide/Show logic.

local UPDATE_INTERVAL = 0.05
local ALPHA_EPSILON = 0.005

local ui = {
    coreOpacity = 0,
    fullUIVisible = false,

    coreFrames = {
        "GamepadMainActionBarFrame",
        "PlayerFrame",
        "PetFrame",
        "TargetFrame",
        "FocusFrame",
        "BuffFrame",
        "DebuffFrame",
        "TemporaryEnchantFrame",
        "FlareUI_UF_Player",
        "FlareUI_Totems",
    },

    -- Additional elements are enabled individually through addon.db.optionalUI.
    -- Buffs are core HUD elements; the legacy optionalUI.buffs key is ignored.
    additionalFrameGroups = {
        questTracker = {
            "ObjectiveTrackerFrame",
            "IFObjectiveTrackerFrame",
        },
        xpBar = {
            "StatusTrackingBarManager",
            "FlareUI_XPBar"
        },
        microMenu = {
            "MicroMenuContainer",
        },
        bags = {
            "BagsBar",
        },
    },

    frameStates = {},
}

local updater = CreateFrame("Frame")
local updateElapsed = 0

-- Minimap frames must be hidden, not merely assigned alpha 0, because some
-- map markers are rendered independently of the normal frame alpha.
local minimapHiddenState = {}
local minimapHideApplied = {}

local CHAT_EDITBOX_PARTS = {
    "EditBoxLeft",
    "EditBoxMid",
    "EditBoxRight",
    "EditBoxFocusLeft",
    "EditBoxFocusMid",
    "EditBoxFocusRight",
    "EditBoxLanguage",
    "EditBoxHeader",
    "EditBoxHeaderSuffix",
}

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue

    if value < minValue then
        return minValue
    elseif value > maxValue then
        return maxValue
    end

    return value
end

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
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

    if InputUtil and type(InputUtil.IsGamepadUIEnabled) == "function" then
        return ReadBoolean(InputUtil.IsGamepadUIEnabled) == true
    end

    return false
end

local function GetFadeDuration(fromAlpha, toAlpha)
    local db = addon.db or {}
    local duration

    if toAlpha > fromAlpha then
        duration = db.fadeInDuration
    else
        duration = db.fadeOutDuration
    end

    duration = tonumber(duration)

    if not duration or duration < 0 then
        duration = 0.25
    end

    return duration
end

local function GetDesiredOpacity(originalAlpha, group)
    if not IsGamepadActive() then
        return originalAlpha
    end

    if ui.fullUIVisible then
        return originalAlpha
    end

    if group == "core" then
        return originalAlpha * ui.coreOpacity
    end

    return 0
end

local function CanAccessObject(object)
    if IsSecret(object) or not object then
        return false
    end

    if type(object) ~= "table" and type(object) ~= "userdata" then
        return false
    end

    if object.IsForbidden
        and ReadBoolean(object.IsForbidden, object) ~= false then
        return false
    end

    if object.CanBeAccessedInContext
        and ReadBoolean(object.CanBeAccessedInContext, object) ~= true then
        return false
    end

    return true
end

local function CanChangeProtectedState(object)
    if not CanAccessObject(object) then
        return false
    end

    if not InCombatLockdown or not InCombatLockdown() then
        return true
    end

    if type(object.IsProtected) ~= "function" then
        return true
    end

    return ReadBoolean(object.IsProtected, object) == false
end

local function AddFrameByName(frames, seen, name)
    local frame = _G[name]

    if frame and not seen[frame] then
        seen[frame] = true
        frames[#frames + 1] = frame
    end
end

local function AddChatFrame(frames, seen, name)
    AddFrameByName(frames, seen, name)
    AddFrameByName(frames, seen, name .. "Tab")
    AddFrameByName(frames, seen, name .. "Minimized")
    AddFrameByName(frames, seen, name .. "EditBox")

    for _, suffix in ipairs(CHAT_EDITBOX_PARTS) do
        AddFrameByName(frames, seen, name .. suffix)
    end
end

local function IsOptionalUIEnabled(key)
    local optionalUI = addon.db and addon.db.optionalUI

    -- Treat an unset option as enabled for backwards compatibility, except chat.
    if not optionalUI then
        return key ~= "chat"
    end

    if optionalUI[key] == nil then
        return key ~= "chat"
    end

    return optionalUI[key] == true
end

local function GetAdditionalFrameList()
    local frames = {}
    local seen = {}

    for optionKey, names in pairs(ui.additionalFrameGroups) do
        if IsOptionalUIEnabled(optionKey) then
            for _, name in ipairs(names) do
                AddFrameByName(frames, seen, name)
            end
        end
    end

    -- Chat is opt-in and disabled by default.
    if IsOptionalUIEnabled("chat") then
        AddFrameByName(frames, seen, "GeneralDockManager")
        AddFrameByName(frames, seen, "ChatFrameChannelButton")

        AddChatFrame(frames, seen, "ChatFrame1")

        if type(CHAT_FRAMES) == "table" then
            for _, name in ipairs(CHAT_FRAMES) do
                AddChatFrame(frames, seen, name)
            end
        elseif type(NUM_CHAT_WINDOWS) == "number" then
            for index = 1, NUM_CHAT_WINDOWS do
                AddChatFrame(frames, seen, "ChatFrame" .. index)
            end
        end
    end

    return frames
end

local function StartFrameFade(frame, state, targetAlpha)
    targetAlpha = Clamp(targetAlpha, 0, 1)

    if math.abs((state.targetAlpha or state.currentAlpha) - targetAlpha) <= ALPHA_EPSILON then
        return
    end

    state.startAlpha = state.currentAlpha
    state.targetAlpha = targetAlpha
    state.elapsed = 0
    state.duration = GetFadeDuration(state.currentAlpha, targetAlpha)

    if state.duration <= 0 then
        state.currentAlpha = targetAlpha
        state.startAlpha = targetAlpha
        state.elapsed = 0
    end
end

local function GetOrCreateFrameState(frame)
    local state = ui.frameStates[frame]

    if state then
        return state
    end

    if not CanAccessObject(frame) or type(frame.GetAlpha) ~= "function" then
        return nil
    end

    local ok, alpha = pcall(frame.GetAlpha, frame)

    if not ok or type(alpha) ~= "number" then
        return nil
    end

    alpha = Clamp(alpha, 0, 1)

    state = {
        originalAlpha = alpha,
        currentAlpha = alpha,
        startAlpha = alpha,
        targetAlpha = alpha,
        elapsed = 0,
        duration = 0,
    }

    ui.frameStates[frame] = state

    return state
end

local function UpdateFrameAlpha(frame, group, elapsed, activeFrames)
    if not CanAccessObject(frame) then
        return
    end

    local state = GetOrCreateFrameState(frame)

    if not state then
        return
    end

    activeFrames[frame] = true

    local targetAlpha = GetDesiredOpacity(state.originalAlpha, group)
    StartFrameFade(frame, state, targetAlpha)

    if state.currentAlpha ~= state.targetAlpha then
        state.elapsed = state.elapsed + elapsed

        local progress

        if state.duration <= 0 then
            progress = 1
        else
            progress = Clamp(state.elapsed / state.duration, 0, 1)
        end

        state.currentAlpha = state.startAlpha
            + (state.targetAlpha - state.startAlpha) * progress
    end

    if type(frame.SetAlpha) == "function" then
        pcall(frame.SetAlpha, frame, state.currentAlpha)
    end
end

local function RestoreInactiveFrameStates(elapsed, activeFrames)
    for frame, state in pairs(ui.frameStates) do
        if not activeFrames[frame] then
            StartFrameFade(frame, state, state.originalAlpha)

            if state.currentAlpha ~= state.targetAlpha then
                state.elapsed = state.elapsed + elapsed

                local progress

                if state.duration <= 0 then
                    progress = 1
                else
                    progress = Clamp(state.elapsed / state.duration, 0, 1)
                end

                state.currentAlpha = state.startAlpha
                    + (state.targetAlpha - state.startAlpha) * progress
            end

            if CanAccessObject(frame) and type(frame.SetAlpha) == "function" then
                pcall(frame.SetAlpha, frame, state.currentAlpha)
            end

            if math.abs(state.currentAlpha - state.originalAlpha) <= ALPHA_EPSILON then
                if CanAccessObject(frame) and type(frame.SetAlpha) == "function" then
                    pcall(frame.SetAlpha, frame, state.originalAlpha)
                end

                ui.frameStates[frame] = nil
            end
        end
    end
end

local function GetMinimapFrames()
    local frames = {}
    local seen = {}

    local function Add(frame)
        if frame and not seen[frame] then
            seen[frame] = true
            frames[#frames + 1] = frame
        end
    end

    local cluster = CanAccessObject(MinimapCluster) and MinimapCluster or nil
    Add(cluster)

    if cluster then
        Add(cluster.MinimapContainer)
    end

    Add(CanAccessObject(Minimap) and Minimap or nil)

    return frames
end

local function RefreshMinimapVisibility(shouldHide)
    local frames = GetMinimapFrames()

    if shouldHide then
        -- Remember original shown state before changing anything.
        for _, frame in ipairs(frames) do
            if CanAccessObject(frame) and minimapHiddenState[frame] == nil then
                local shown = ReadBoolean(frame.IsShown, frame)

                if shown ~= nil then
                    minimapHiddenState[frame] = shown
                end
            end
        end

        -- Hide each layer separately. This also suppresses game-rendered markers.
        for _, frame in ipairs(frames) do
            if CanChangeProtectedState(frame)
                and minimapHiddenState[frame] ~= nil
                and (not minimapHideApplied[frame]
                    or ReadBoolean(frame.IsShown, frame) == true) then

                local ok = pcall(frame.Hide, frame)

                if ok then
                    minimapHideApplied[frame] = true
                end
            end
        end
    else
        -- Restore exactly the visibility each frame had before ICUI hid it.
        for frame, wasShown in pairs(minimapHiddenState) do
            if CanChangeProtectedState(frame) then
                local callback = wasShown and frame.Show or frame.Hide
                local ok = pcall(callback, frame)

                if ok then
                    minimapHiddenState[frame] = nil
                    minimapHideApplied[frame] = nil
                end
            end
        end
    end
end

local function UpdateFrameVisibility(elapsed)
    local activeFrames = {}

    for _, name in ipairs(ui.coreFrames) do
        UpdateFrameAlpha(_G[name], "core", elapsed, activeFrames)
    end

    local additionalFrames = GetAdditionalFrameList()

    for _, frame in ipairs(additionalFrames) do
        UpdateFrameAlpha(frame, "additional", elapsed, activeFrames)
    end

    RestoreInactiveFrameStates(elapsed, activeFrames)

    local minimapEnabled = IsOptionalUIEnabled("minimap")
    local shouldHideMinimap = minimapEnabled
        and IsGamepadActive()
        and not ui.fullUIVisible

    RefreshMinimapVisibility(shouldHideMinimap)
end

function addon:ApplyUIVisibility(coreOpacity, fullUIVisible)
    ui.coreOpacity = Clamp(coreOpacity or 0, 0, 1)
    ui.fullUIVisible = fullUIVisible == true

    -- Apply the minimap transition immediately rather than waiting for OnUpdate.
    local shouldHideMinimap = IsOptionalUIEnabled("minimap")
        and IsGamepadActive()
        and not ui.fullUIVisible

    RefreshMinimapVisibility(shouldHideMinimap)
end

updater:SetScript("OnUpdate", function(_, elapsed)
    updateElapsed = updateElapsed + elapsed

    if updateElapsed < UPDATE_INTERVAL then
        return
    end

    local step = updateElapsed
    updateElapsed = 0

    UpdateFrameVisibility(step)
end)

-- Expose the current visual state for debugging or future UI-specific reveal logic.
addon.UI = ui
