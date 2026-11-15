local addonName, addon = ...

-- Immersive Controller UI - UI visibility and fade handling.
-- This file owns frame alpha changes and the minimap's fade-then-hide logic.

local UPDATE_INTERVAL = 0.05
local ALPHA_EPSILON = 0.005

local ui = {
    coreOpacity = 0,
    fullUIVisible = false,

    coreFrames = {
        "GamepadMainActionBarFrame",
        "PlayerFrame",
        "PetFrame",
        "FlareUI_Pet",
        "TargetFrame",
        "FocusFrame",
        "FlareUI_UF_Player",
        "FlareUI_UF_Pet",
        "FlareUI_Totems",
        "BuffFrame",
        "DebuffFrame",
        "TemporaryEnchantFrame",
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
            "FlareUI_XPBar",
        },
        microMenu = {
            "MicroMenuContainer",
        },
        bags = {
            "BagsBar",
        },
    },

    frameStates = {},

    -- These temporary reveals are independent of fullUIVisible.
    -- Quest tracker focus reveals only the quest tracker; gamepad HUD/menu
    -- navigation reveals only the minimap.
    controllerReveals = {
        questTracker = false,
        minimap = false,
    },
}

local updater = CreateFrame("Frame")
local updateElapsed = 0

-- The tracking button must remain shown so Gamepad Mode can open its menu.
-- The Minimap render frame itself is handled separately below because its
-- game-rendered map, markers, and player arrow do not reliably inherit alpha.
local MINIMAP_IDLE_ALPHA = 0
local minimapRenderOriginalShown = nil
local minimapRenderHiddenByICUI = false

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

local function CanAccessObject(object)
    if IsSecret(object) or (type(object) ~= "table" and type(object) ~= "userdata") then
        return false
    end

    local ok, isForbidden = pcall(function()
        return object.IsForbidden
    end)

    if ok and type(isForbidden) == "function"
        and ReadBoolean(isForbidden, object) ~= false then
        return false
    end

    local accessOK, canAccess = pcall(function()
        return object.CanBeAccessedInContext
    end)

    if accessOK and type(canAccess) == "function"
        and ReadBoolean(canAccess, object) ~= true then
        return false
    end

    return true
end

local function IsObjectShown(object)
    return CanAccessObject(object)
        and ReadBoolean(object.IsShown, object) == true
end

local function IsInsideFrame(candidate, root)
    if not CanAccessObject(root) then
        return false
    end

    local current = candidate

    for _ = 1, 16 do
        if not CanAccessObject(current) then
            return false
        end

        if current == root then
            return true
        end

        local parentMethod
        local ok = pcall(function()
            parentMethod = current.GetParent
        end)

        if not ok or type(parentMethod) ~= "function" then
            return false
        end

        local parentOK, parent = pcall(parentMethod, current)

        if not parentOK or parent == nil or IsSecret(parent) or parent == current then
            return false
        end

        current = parent
    end

    return false
end

local function AddFocusCandidate(candidates, owner, methodName)
    if not CanAccessObject(owner) then
        return
    end

    local method
    local ok = pcall(function()
        method = owner[methodName]
    end)

    if not ok or type(method) ~= "function" then
        return
    end

    local callOK, frame = pcall(method, owner)

    if callOK and CanAccessObject(frame) then
        candidates[#candidates + 1] = frame
    end
end

local function GetControllerFocusCandidates()
    local candidates = {}
    local manager = GamepadMode and GamepadMode.FrameControlsManager

    if CanAccessObject(manager) then
        local focused
        local ok = pcall(function()
            focused = manager.isUIFocused
        end)

        if ok and not IsSecret(focused) and focused == false then
            return candidates
        end

        if type(manager.GetShownFrameCount) == "function" then
            local countOK, count = pcall(manager.GetShownFrameCount, manager)

            if countOK and type(count) == "number" and not IsSecret(count) and count == 0 then
                return candidates
            end
        end

        -- A context menu can become active while the HUD element remains
        -- suspended. Inspect both, as FableUI does.
        AddFocusCandidate(candidates, manager, "GetActiveFrame")
        AddFocusCandidate(candidates, manager, "GetSuspendedFrame")
    end

    AddFocusCandidate(candidates, SmartNavigation, "GetActiveFrame")
    AddFocusCandidate(candidates, SmartNavigation, "GetCurrentButton")

    return candidates
end

local function IsControllerFocusedWithin(roots)
    if not IsGamepadActive() then
        return false
    end

    local candidates = GetControllerFocusCandidates()

    for _, candidate in ipairs(candidates) do
        for _, root in ipairs(roots) do
            if IsInsideFrame(candidate, root) then
                return true
            end
        end
    end

    return false
end

local function IsQuestTrackerControllerFocused()
    local trackerRoots = {}

    -- Support both Blizzard's standard tracker and the alternate IF tracker.
    for _, name in ipairs({ "ObjectiveTrackerFrame", "IFObjectiveTrackerFrame" }) do
        local tracker = _G[name]

        if CanAccessObject(tracker) then
            trackerRoots[#trackerRoots + 1] = tracker

            -- The native controller footer indicates direct tracker focus.
            local footer
            pcall(function()
                footer = tracker.gamepadFooter
            end)

            if type(footer) == "table" then
                local shown
                local ok = pcall(function()
                    shown = footer.isShown
                end)

                if ok and not IsSecret(shown) and shown == true then
                    return true
                end
            end
        end
    end

    return #trackerRoots > 0
        and IsControllerFocusedWithin(trackerRoots)
end

local function IsMinimapTrackingMenuOpen()
    local cluster = CanAccessObject(MinimapCluster) and MinimapCluster or nil
    local tracking
    local button

    if cluster then
        pcall(function()
            tracking = cluster.Tracking
            button = tracking and tracking.Button
        end)
    end

    return CanAccessObject(button)
        and ReadBoolean(button.IsMenuOpen, button) == true
end

local function IsMinimapControllerFocused()
    local roots = {}
    local seen = {}

    local function AddRoot(frame)
        if CanAccessObject(frame) and not seen[frame] then
            seen[frame] = true
            roots[#roots + 1] = frame
        end
    end

    local cluster = CanAccessObject(MinimapCluster) and MinimapCluster or nil
    AddRoot(cluster)

    if cluster then
        local container, trackingButton
        pcall(function()
            container = cluster.MinimapContainer
            trackingButton = cluster.Tracking and cluster.Tracking.Button
        end)
        AddRoot(container)
        AddRoot(trackingButton)
    end

    AddRoot(CanAccessObject(Minimap) and Minimap or nil)

    return IsControllerFocusedWithin(roots)
end

local function RefreshControllerReveals()
    local gamepadActive = IsGamepadActive()

    if not gamepadActive then
        ui.controllerReveals.questTracker = false
        ui.controllerReveals.minimap = false
        return
    end

    -- Keep the minimap visible while the native gamepad HUD/radial menu is
    -- open, allowing the player to reach its tracking options.
    local minimapReveal = IsObjectShown(GamepadHudMode)
        or IsMinimapTrackingMenuOpen()
        or IsMinimapControllerFocused()

    local questTrackerReveal = IsQuestTrackerControllerFocused()

    ui.controllerReveals.minimap = minimapReveal
    ui.controllerReveals.questTracker = questTrackerReveal
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

local function GetDesiredOpacity(originalAlpha, group, revealKey)
    if not IsGamepadActive() then
        return originalAlpha
    end

    if ui.fullUIVisible then
        return originalAlpha
    end

    if group == "core" then
        return originalAlpha * ui.coreOpacity
    end

    if revealKey and ui.controllerReveals[revealKey] then
        return originalAlpha
    end

    -- Fade minimap frames to their idle opacity. The map render frame is hidden
    -- only after its fade-out completes, to remove game-rendered details that
    -- may not fully respect alpha.
    if revealKey == "minimap" then
        return originalAlpha * MINIMAP_IDLE_ALPHA
    end

    return 0
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

-- The Minimap frame renders map artwork, markers, and the player arrow
-- outside the normal parent-alpha behavior. Fade the other active UI frames
-- first, then hide Minimap only after those fades have completed. Keep
-- MinimapCluster shown so its tracking button remains available to Gamepad Mode.
local function AddFrameByName(frames, seen, name, revealKey)
    local frame = _G[name]

    if frame and not seen[frame] then
        seen[frame] = true
        frames[#frames + 1] = {
            frame = frame,
            revealKey = revealKey,
        }
    end
end

local function AddChatFrame(frames, seen, name)
    AddFrameByName(frames, seen, name, "chat")
    AddFrameByName(frames, seen, name .. "Tab", "chat")
    AddFrameByName(frames, seen, name .. "Minimized", "chat")
    AddFrameByName(frames, seen, name .. "EditBox", "chat")

    for _, suffix in ipairs(CHAT_EDITBOX_PARTS) do
        AddFrameByName(frames, seen, name .. suffix, "chat")
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
                AddFrameByName(frames, seen, name, optionKey)
            end
        end
    end

    -- Chat is opt-in and disabled by default.
    if IsOptionalUIEnabled("chat") then
        AddFrameByName(frames, seen, "GeneralDockManager", "chat")
        AddFrameByName(frames, seen, "ChatFrameChannelButton", "chat")

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

-- The map render frame itself cannot be trusted to visually follow alpha.
-- Keep it shown while the rest of ICUI fades, then hide it after every other
-- active frame targeting zero has completed its fade. On reveal, show it again
-- immediately so the tracking button and map interaction are available.
local function PrepareMinimapRenderFrame(shouldReveal)
    local frame = CanAccessObject(Minimap) and Minimap or nil

    if not frame or type(frame.IsShown) ~= "function" then
        return frame
    end

    if minimapRenderOriginalShown == nil then
        minimapRenderOriginalShown = ReadBoolean(frame.IsShown, frame)
    end

    if minimapRenderOriginalShown ~= true then
        return frame
    end

    if shouldReveal and minimapRenderHiddenByICUI then
        if CanChangeProtectedState(frame) then
            local ok = pcall(frame.Show, frame)
            if ok then
                minimapRenderHiddenByICUI = false
            end
        end
    end

    return frame
end

local function AreOtherFrameFadesComplete(activeFrames)
    for otherFrame in pairs(activeFrames) do
        local state = ui.frameStates[otherFrame]

        if state
            and state.targetAlpha <= ALPHA_EPSILON
            and state.currentAlpha > ALPHA_EPSILON then
            return false
        end
    end

    return true
end

local function FinalizeMinimapRenderFrame(frame, shouldHide, activeFrames)
    if not shouldHide
        or not frame
        or minimapRenderOriginalShown ~= true
        or minimapRenderHiddenByICUI then
        return
    end

    -- Wait for the core HUD, optional elements, and MinimapCluster to finish
    -- their fade-outs before hiding the game-rendered map itself.
    if not AreOtherFrameFadesComplete(activeFrames) then
        return
    end

    if not IsObjectShown(frame) or not CanChangeProtectedState(frame) then
        return
    end

    local ok = pcall(frame.Hide, frame)
    if ok then
        minimapRenderHiddenByICUI = true
    end
end

local function UpdateFrameAlpha(frame, group, revealKey, elapsed, activeFrames)
    if not CanAccessObject(frame) then
        return
    end

    local state = GetOrCreateFrameState(frame)

    if not state then
        return
    end

    activeFrames[frame] = true

    local targetAlpha = GetDesiredOpacity(state.originalAlpha, group, revealKey)
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
        if CanAccessObject(frame) and not seen[frame] then
            seen[frame] = true
            frames[#frames + 1] = frame
        end
    end

    -- Only fade the cluster (tracking button, border and decorations).
    -- The rendered map is hidden separately after all active UI fades finish.
    Add(MinimapCluster)

    return frames
end

local function UpdateFrameVisibility(elapsed)
    RefreshControllerReveals()

    local gamepadActive = IsGamepadActive()
    local minimapEnabled = IsOptionalUIEnabled("minimap")
    local minimapShouldHide = minimapEnabled
        and gamepadActive
        and not ui.fullUIVisible
        and not ui.controllerReveals.minimap

    -- If a previous idle fade completed and hid Minimap, show it at its
    -- current alpha before starting a new fade-in. If the setting is disabled
    -- or Gamepad Mode is inactive, restore it as well.
    local minimapRenderFrame = PrepareMinimapRenderFrame(not minimapShouldHide)

    local activeFrames = {}

    for _, name in ipairs(ui.coreFrames) do
        UpdateFrameAlpha(_G[name], "core", nil, elapsed, activeFrames)
    end

    local additionalFrames = GetAdditionalFrameList()

    for _, entry in ipairs(additionalFrames) do
        UpdateFrameAlpha(
            entry.frame,
            "additional",
            entry.revealKey,
            elapsed,
            activeFrames
        )
    end

    -- Fade the minimap cluster and its controls normally. The rendered map
    -- cannot be relied on to obey alpha, so keep it shown until all other
    -- active frames have completed their fade-out, then hide it.
    if minimapEnabled then
        for _, frame in ipairs(GetMinimapFrames()) do
            UpdateFrameAlpha(frame, "additional", "minimap", elapsed, activeFrames)
        end
    end

    FinalizeMinimapRenderFrame(
        minimapRenderFrame,
        minimapShouldHide,
        activeFrames
    )

    RestoreInactiveFrameStates(elapsed, activeFrames)
end

function addon:ApplyUIVisibility(coreOpacity, fullUIVisible)
    ui.coreOpacity = Clamp(coreOpacity or 0, 0, 1)
    ui.fullUIVisible = fullUIVisible == true

    -- Controller reveal state and alpha transitions are refreshed by the
    -- existing 0.05-second updater. No minimap Hide()/Show() calls are needed.
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

-- Expose current visual state for optional-element focus behavior.
addon.UI = ui
