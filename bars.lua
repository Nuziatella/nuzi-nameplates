local api = require("api")

local function loadModule(name)
    local ok, mod = pcall(require, "gharka-bars/" .. name)
    if ok then
        return mod
    end
    ok, mod = pcall(require, "gharka-bars." .. name)
    if ok then
        return mod
    end
    return nil
end

local Shared = loadModule("shared")
local Helpers = loadModule("bar_helpers")
local Layout = loadModule("bars_layout")
local Role = loadModule("role")
local Compat = loadModule("compat")
local CcEffects = loadModule("cc_effects")

local Bars = {
    frames = {},
    root_window = nil,
    unit_keys = {},
    hot_unit_keys = {},
    bulk_unit_keys = {},
    active_bulk_unit_keys = {},
    unit_id_cache = {},
    render_owners = {},
    position_sources = {},
    bulk_active_cursor = 1,
    bulk_cold_cursor = 1,
    visible_bulk_cursor = 1,
    discovery_position_active_cursor = 1,
    discovery_position_cold_cursor = 1,
    hovered_unit = nil,
    target_unitframe = nil,
    watchtarget_unitframe = nil,
    targetoftarget_unitframe = nil,
    layer_mode = nil,
    owner_source_last_build_ms = 0,
    last_visible_bulk_position_ms = 0
}

local applyLayerToFrame
local setBorderVisible
local changeTarget
local hasAnyEntries
local TARGET_DEBUG_LOGGING = false

local VALID_UI_LAYERS = {
    background = true,
    game = true,
    normal = true,
    hud = true,
    questdirecting = true,
    dialog = true,
    tooltip = true,
    system = true
}

local TARGET_GLOW_COLOR = { 255, 245, 0, 255 }
local TARGET_TINT_COLOR = { 255, 245, 0, 170 }
local CC_DISPEL_BORDER_COLOR = { 180, 72, 255, 255 }
local CC_DISPEL_SLOT_COLOR = { 0.7059, 0.2824, 1, 1 }
local BLOODLUST_BUFF_ID = 1482
local HOSTILE_TEXT_COLOR = { 255, 244, 244, 255 }
local NEUTRAL_TEXT_COLOR = { 40, 28, 0, 255 }
local HP_GRADIENT_LOW_COLOR = { 255, 0, 0, 255 }
local HP_GRADIENT_HIGH_COLOR = { 46, 122, 240, 255 }
local CC_SCAN_INTERVAL_MS = 250
local CC_EXTRA_ICON_COUNT = 3
local HOT_UNIT_STATIC_REFRESH_MS = 1000
local BULK_UNIT_STATIC_REFRESH_MS = 5000
local BULK_UNIT_STATIC_JITTER_MS = 2400
local INCOMPLETE_STATIC_REFRESH_MS = 900
local FRAME_FADE_DURATION_MS = 140
local POSITION_LOSS_GRACE_MS = 64
local PLAYER_POSITION_LOSS_GRACE_MS = 96
local RECENTLY_VISIBLE_POSITION_GRACE_MS = 500
local DISTANCE_HIDE_GRACE_MS = 180
local DISTANCE_HIDE_HYSTERESIS_M = 6
local BULK_POSITION_INTERVAL_SMALL_MS = 33
local BULK_POSITION_INTERVAL_MEDIUM_MS = 50
local BULK_POSITION_INTERVAL_LARGE_MS = 66
local BULK_POSITION_INTERVAL_XL_MS = 100
local BULK_ACTIVE_DATA_BATCH_SIZE = 14
local BULK_COLD_DATA_BATCH_SIZE = 6
local BULK_DISCOVERY_BATCH_SIZE = 14
local DISCOVERY_POSITION_ACTIVE_BATCH_SIZE = 10
local DISCOVERY_POSITION_COLD_BATCH_SIZE = 12
local HOT_BLOODLUST_SCAN_INTERVAL_MS = 450
local BULK_BLOODLUST_SCAN_INTERVAL_MS = 1400
local HOT_DISTANCE_REFRESH_MS = 0
local BULK_SHOWN_DISTANCE_REFRESH_MS = 140
local BULK_HIDDEN_DISTANCE_REFRESH_MS = 260
local OWNER_SOURCE_REBUILD_INTERVAL_MS = 250
local VISIBLE_BULK_POSITION_INTERVAL_SMALL_MS = 33
local VISIBLE_BULK_POSITION_INTERVAL_MEDIUM_MS = 33
local VISIBLE_BULK_POSITION_INTERVAL_LARGE_MS = 33
local VISIBLE_BULK_POSITION_INTERVAL_XL_MS = 33
local HOVER_CLUSTER_DIM_ALPHA = 0.42
local CC_CATEGORY_STYLE_KEYS = {
    hard = "show_cc_hard",
    silence = "show_cc_silence",
    root = "show_cc_root",
    slow = "show_cc_slow",
    dot = "show_cc_dot",
    misc = "show_cc_misc"
}
local PLAYER_CC_VISIBILITY_CACHE = {
    last_scan_ms = 0,
    effects = {}
}

local function clamp(v, lo, hi, default)
    return Shared.Clamp(v, lo, hi, default)
end

local function safeUiNowMs()
    if api.Time == nil or api.Time.GetUiMsec == nil then
        return 0
    end
    local value = api.Time:GetUiMsec()
    return tonumber(value) or 0
end

local function safeCreateCcIcon(id, parent)
    if type(CreateItemIconButton) ~= "function" or parent == nil then
        return nil
    end
    local ok, icon = pcall(function()
        return CreateItemIconButton(id, parent)
    end)
    if not ok or icon == nil then
        return nil
    end
    Helpers.SafeClickable(icon, false)
    Helpers.SafeShow(icon, false)
    if icon.back ~= nil then
        pcall(function()
            if F_SLOT ~= nil and F_SLOT.ApplySlotSkin ~= nil then
                local style = DEBUFF or (SLOT_STYLE ~= nil and (SLOT_STYLE.BUFF or SLOT_STYLE.DEFAULT or SLOT_STYLE.ITEM)) or nil
                if style ~= nil then
                    F_SLOT.ApplySlotSkin(icon, icon.back, style)
                end
            end
        end)
    end
    return icon
end

local function cloneSlotStyle(style)
    if type(style) ~= "table" then
        return style
    end
    local out = {}
    for key, value in pairs(style) do
        if type(value) == "table" then
            local nested = {}
            for nestedKey, nestedValue in pairs(value) do
                nested[nestedKey] = nestedValue
            end
            out[key] = nested
        else
            out[key] = value
        end
    end
    return out
end

local function getCcSlotStyle(isDispellable)
    local base = DEBUFF or (SLOT_STYLE ~= nil and (SLOT_STYLE.BUFF or SLOT_STYLE.DEFAULT or SLOT_STYLE.ITEM)) or nil
    if not isDispellable or type(base) ~= "table" then
        return base
    end
    local styled = cloneSlotStyle(base)
    styled.color = { CC_DISPEL_SLOT_COLOR[1], CC_DISPEL_SLOT_COLOR[2], CC_DISPEL_SLOT_COLOR[3], CC_DISPEL_SLOT_COLOR[4] }
    return styled
end

local function applyCcIconStyle(icon, isDispellable)
    if icon == nil or icon.back == nil or F_SLOT == nil or F_SLOT.ApplySlotSkin == nil then
        return
    end
    local style = getCcSlotStyle(isDispellable == true)
    if style == nil then
        return
    end
    pcall(function()
        F_SLOT.ApplySlotSkin(icon, icon.back, style)
    end)
end

local function safeSetIconPath(icon, path)
    if icon == nil or type(path) ~= "string" or path == "" then
        return
    end
    pcall(function()
        if F_SLOT ~= nil and F_SLOT.SetIconBackGround ~= nil then
            F_SLOT.SetIconBackGround(icon, path)
        elseif icon.SetIconPath ~= nil then
            icon:SetIconPath(path)
        end
    end)
end

local function makeCcTimerLabel(id, parent)
    if parent == nil then
        return nil
    end
    local label = api.Interface:CreateWidget("label", id, parent)
    Helpers.SafeClickable(label, false)
    Helpers.SafeShow(label, false)
    pcall(function()
        if label.style ~= nil then
            if label.style.SetAlign ~= nil then
                label.style:SetAlign(ALIGN.CENTER)
            end
            if label.style.SetShadow ~= nil then
                label.style:SetShadow(true)
            end
        end
    end)
    return label
end

local function setCcTimerStyle(label, fontSize)
    if label == nil then
        return
    end
    local wantFont = tonumber(fontSize) or 11
    local wantKey = tostring(wantFont)
    if label.__ghb_cc_timer_style == wantKey then
        return
    end
    pcall(function()
        Helpers.SafeSetExtent(label, 56, wantFont + 6)
        if label.style ~= nil and label.style.SetFontSize ~= nil then
            label.style:SetFontSize(wantFont)
        end
    end)
    label.__ghb_cc_timer_style = wantKey
end

local function hideCcWidgets(frame)
    if frame == nil then
        return
    end
    Helpers.SafeShow(frame.ccPrimary, false)
    Helpers.SafeShow(frame.ccPrimaryTimer, false)
    for _, entry in ipairs(frame.ccExtras or {}) do
        Helpers.SafeShow(entry.icon, false)
        Helpers.SafeShow(entry.timer, false)
    end
end

local function shouldTrackCcUnit(unit, cfg)
    local key = tostring(unit or "")
    if key == "player" or key == "target" or key == "watchtarget" then
        return true
    end
    if type(cfg) ~= "table" or tostring(cfg.cc_tracking_scope or "focus") ~= "raid" then
        return false
    end
    return string.match(key, "^team%d+$") ~= nil
end

local function normalizeUnitToken(unit)
    if type(unit) ~= "string" then
        return nil
    end
    local text = tostring(unit or "")
    if text == "" then
        return nil
    end
    return text
end

local function normalizeTargetToken(unit)
    local token = normalizeUnitToken(unit)
    if token == nil then
        return nil
    end
    if token == "targetoftarget" or token == "target_of_target" then
        return "targettarget"
    end
    return token
end

local function shouldPreferUnitIdClickTarget(unit)
    local key = normalizeTargetToken(unit)
    return key == "target" or key == "watchtarget" or key == "targettarget"
end

local function isShiftDown()
    if api ~= nil and api.Input ~= nil and api.Input.IsShiftKeyDown ~= nil then
        return api.Input:IsShiftKeyDown() and true or false
    end
    return false
end

local function isCtrlDown()
    if api ~= nil and api.Input ~= nil then
        if api.Input.IsControlKeyDown ~= nil then
            return api.Input:IsControlKeyDown() and true or false
        end
    end
    return false
end

local function shouldPassThroughClick(settings)
    if isShiftDown() then
        return true
    end
    if isCtrlDown() then
        return true
    end
    return false
end

local function canClickTargetUnit(unit, settings)
    if type(settings) ~= "table" or settings.click_target ~= true then
        return false
    end
    if shouldPassThroughClick(settings) then
        return false
    end
    return unit ~= nil
end

local function setEventWindowInteraction(frame, enabled)
    if frame == nil then
        return
    end
    local interactive = enabled and true or false
    frame.__ghb_click_target = interactive
    if frame.eventWindow == nil then
        return
    end
    if frame.eventWindow.EnablePick ~= nil then
        pcall(function()
            frame.eventWindow:EnablePick(interactive)
        end)
    end
    Helpers.SafeClickable(frame.eventWindow, interactive)
    Helpers.SafeShow(frame.eventWindow, interactive)
end

local function isHotUnit(unit)
    return unit == "target" or unit == "player" or unit == "watchtarget"
end

local function getCanonicalRenderPriority(unit)
    local key = tostring(unit or "")
    if key == "player" then
        return 100000
    end
    local teamIndex = tonumber(string.match(key, "^team(%d+)$") or "")
    if teamIndex ~= nil then
        return 90000 - teamIndex
    end
    if key == "playerpet1" then
        return 80000
    end
    if key == "target" then
        return 30000
    end
    if key == "watchtarget" then
        return 20000
    end
    if key == "targettarget" or key == "target_of_target" or key == "targetoftarget" then
        return 10000
    end
    return 0
end

local function getCanonicalPositionPriority(unit)
    local key = tostring(unit or "")
    local teamIndex = tonumber(string.match(key, "^team(%d+)$") or "")
    if teamIndex ~= nil then
        return 100000 - teamIndex
    end
    if key == "player" then
        return 90000
    end
    if key == "playerpet1" then
        return 80000
    end
    if key == "target" then
        return 30000
    end
    if key == "watchtarget" then
        return 20000
    end
    if key == "targettarget" or key == "target_of_target" or key == "targetoftarget" then
        return 10000
    end
    return 0
end

local function getUnitDisplayPriority(unit)
    local key = tostring(unit or "")
    if key == "player" then
        return 500
    end
    if string.match(key, "^team%d+$") then
        return 400
    end
    if key == "watchtarget" then
        return 300
    end
    if key == "target" then
        return 200
    end
    if key == "playerpet1" then
        return 100
    end
    return 0
end

local function getUnitHash(unit)
    local text = tostring(unit or "")
    local hash = 0
    for index = 1, string.len(text) do
        hash = ((hash * 33) + string.byte(text, index)) % 104729
    end
    return hash
end

local function getStaticRefreshIntervalMs(unit)
    if isHotUnit(unit) then
        return HOT_UNIT_STATIC_REFRESH_MS
    end
    return BULK_UNIT_STATIC_REFRESH_MS
end

local function getStaticRefreshJitterMs(unit)
    if isHotUnit(unit) then
        return 0
    end
    return getUnitHash(unit) % BULK_UNIT_STATIC_JITTER_MS
end

local function getDistanceRefreshIntervalMs(unit, isShown)
    if isHotUnit(unit) then
        return HOT_DISTANCE_REFRESH_MS
    end
    if isShown then
        return BULK_SHOWN_DISTANCE_REFRESH_MS
    end
    return BULK_HIDDEN_DISTANCE_REFRESH_MS
end

local function getBloodlustScanIntervalMs(unit)
    if isHotUnit(unit) then
        return HOT_BLOODLUST_SCAN_INTERVAL_MS
    end
    return BULK_BLOODLUST_SCAN_INTERVAL_MS
end

local function getVisibleBulkPositionIntervalMs(activeCount)
    local count = tonumber(activeCount) or 0
    if count >= 36 then
        return VISIBLE_BULK_POSITION_INTERVAL_XL_MS
    end
    if count >= 24 then
        return VISIBLE_BULK_POSITION_INTERVAL_LARGE_MS
    end
    if count >= 12 then
        return VISIBLE_BULK_POSITION_INTERVAL_MEDIUM_MS
    end
    return VISIBLE_BULK_POSITION_INTERVAL_SMALL_MS
end

local function normalizeUnitId(unitId)
    if unitId == nil then
        return nil
    end
    local valueType = type(unitId)
    if valueType == "string" then
        local text = tostring(unitId)
        if text == "" then
            return nil
        end
        return text
    end
    if valueType == "number" then
        return tostring(unitId)
    end
    return nil
end

local function queryUnitId(unit)
    if api == nil or api.Unit == nil or api.Unit.GetUnitId == nil then
        return nil
    end
    unit = normalizeUnitToken(unit)
    if unit == nil then
        return nil
    end
    local unitId = api.Unit:GetUnitId(unit)
    return normalizeUnitId(unitId)
end

local function queryUnitDistance(unit)
    if api.Unit == nil or api.Unit.UnitDistance == nil then
        return nil
    end
    local distance = api.Unit:UnitDistance(unit)
    if type(distance) ~= "number" then
        return nil
    end
    return distance
end

local function getCurrentTargetUnitId()
    return queryUnitId("target")
end

local function buildRenderOwnerMap(unitIds)
    local bestByUnitId = {}
    local owners = {}
    for unit, unitId in pairs(unitIds or {}) do
        if unitId ~= nil then
            local priority = getCanonicalRenderPriority(unit)
            local current = bestByUnitId[unitId]
            if current == nil
                or priority > current.priority
                or (priority == current.priority and tostring(unit) < tostring(current.unit)) then
                bestByUnitId[unitId] = {
                    unit = unit,
                    priority = priority
                }
            end
        end
    end
    for unit, unitId in pairs(unitIds or {}) do
        if unitId ~= nil and bestByUnitId[unitId] ~= nil then
            owners[unit] = bestByUnitId[unitId].unit
        else
            owners[unit] = unit
        end
    end
    return owners
end

local function buildPositionSourceMap(unitIds)
    local bestByUnitId = {}
    local sources = {}
    for unit, unitId in pairs(unitIds or {}) do
        if unitId ~= nil then
            local priority = getCanonicalPositionPriority(unit)
            local current = bestByUnitId[unitId]
            if current == nil
                or priority > current.priority
                or (priority == current.priority and tostring(unit) < tostring(current.unit)) then
                bestByUnitId[unitId] = {
                    unit = unit,
                    priority = priority
                }
            end
        end
    end
    for unit, unitId in pairs(unitIds or {}) do
        if unitId ~= nil and bestByUnitId[unitId] ~= nil then
            sources[unit] = bestByUnitId[unitId].unit
        else
            sources[unit] = unit
        end
    end
    return sources
end

local function rebuildOwnerAndPositionMaps(nowMs)
    local mergedUnitIds = {}
    for _, unit in ipairs(Bars.unit_keys or {}) do
        local unitId = Bars.unit_id_cache[unit]
        if unitId ~= nil then
            mergedUnitIds[unit] = unitId
        end
    end
    Bars.render_owners = buildRenderOwnerMap(mergedUnitIds)
    Bars.position_sources = buildPositionSourceMap(mergedUnitIds)
    Bars.owner_source_last_build_ms = tonumber(nowMs) or 0
end

local function applyFrameCompositeAlpha(frame)
    if frame == nil or frame.cache == nil then
        return
    end
    local cache = frame.cache
    local fadeAlpha = tonumber(cache.fade_alpha)
    if fadeAlpha == nil then
        fadeAlpha = cache.shown and 1 or 0
    end
    local baseAlpha = tonumber(cache.base_alpha) or 1
    local hoverAlpha = tonumber(cache.hover_alpha_mult) or 1
    Helpers.SafeSetAlpha(frame, fadeAlpha * baseAlpha * hoverAlpha)
end

local function getStockTargetFrame()
    local cached = Bars.target_unitframe
    if cached ~= nil and cached.eventWindow ~= nil and cached.eventWindow.OnClick ~= nil then
        return cached
    end
    if ADDON == nil or ADDON.GetContent == nil or UIC == nil or UIC.TARGET_UNITFRAME == nil then
        Bars.target_unitframe = nil
        return nil
    end
    local value = nil
    pcall(function()
        value = ADDON:GetContent(UIC.TARGET_UNITFRAME)
    end)
    if value ~= nil and value.eventWindow ~= nil and value.eventWindow.OnClick ~= nil then
        Bars.target_unitframe = value
        return value
    end
    Bars.target_unitframe = nil
    return nil
end

local function getStockWatchtargetFrame()
    local cached = Bars.watchtarget_unitframe
    if cached ~= nil and cached.eventWindow ~= nil and cached.eventWindow.OnClick ~= nil then
        return cached
    end
    if ADDON == nil or ADDON.GetContent == nil or UIC == nil or UIC.WATCH_TARGET_FRAME == nil then
        Bars.watchtarget_unitframe = nil
        return nil
    end
    local value = nil
    pcall(function()
        value = ADDON:GetContent(UIC.WATCH_TARGET_FRAME)
    end)
    if value ~= nil and value.eventWindow ~= nil and value.eventWindow.OnClick ~= nil then
        Bars.watchtarget_unitframe = value
        return value
    end
    Bars.watchtarget_unitframe = nil
    return nil
end

local function getStockTargetOfTargetFrame()
    local cached = Bars.targetoftarget_unitframe
    if cached ~= nil and cached.eventWindow ~= nil and cached.eventWindow.OnClick ~= nil then
        return cached
    end
    if ADDON == nil or ADDON.GetContent == nil or UIC == nil or UIC.TARGET_OF_TARGET_FRAME == nil then
        Bars.targetoftarget_unitframe = nil
        return nil
    end
    local value = nil
    pcall(function()
        value = ADDON:GetContent(UIC.TARGET_OF_TARGET_FRAME)
    end)
    if value ~= nil and value.eventWindow ~= nil and value.eventWindow.OnClick ~= nil then
        Bars.targetoftarget_unitframe = value
        return value
    end
    Bars.targetoftarget_unitframe = nil
    return nil
end

local function getStockFrameForUnit(unit)
    local key = tostring(unit or "")
    if key == "watchtarget" then
        return getStockWatchtargetFrame(), "watchtarget"
    end
    if key == "targetoftarget" or key == "target_of_target" or key == "targettarget" then
        return getStockTargetOfTargetFrame(), "targettarget"
    end
    return getStockTargetFrame(), "target"
end

local function getStockFrameMethodCandidates(unit)
    local key = tostring(unit or "")
    if key == "watchtarget" then
        return {
            { method = "SetWatchTarget", args = { "watchtarget" }, label = "stock frame SetWatchTarget(watchtarget)" },
            { method = "SetTarget", args = { "watchtarget" }, label = "stock frame SetTarget(watchtarget)" },
            { method = "TargetChanged", args = { "watchtarget" }, label = "stock frame TargetChanged(watchtarget)" }
        }
    end
    if key == "targetoftarget" or key == "target_of_target" or key == "targettarget" then
        return {
            { method = "SetTarget", args = { "targettarget" }, label = "stock frame SetTarget(targettarget)" },
            { method = "TargetChanged", args = { "targettarget" }, label = "stock frame TargetChanged(targettarget)" }
        }
    end
    return {
        { method = "SetTarget", args = { "target" }, label = "stock frame SetTarget(target)" },
        { method = "TargetChanged", args = { "target" }, label = "stock frame TargetChanged(target)" }
    }
end

local function getTargetUnitCandidates(unit)
    local key = normalizeTargetToken(unit)
    if key == "" then
        return {}
    end
    if key == nil then
        return {}
    end
    if key == "watchtarget" then
        return { "watchtarget", "targettarget", "target_of_target", "targetoftarget" }
    end
    if key == "targetoftarget" or key == "target_of_target" or key == "targettarget" then
        return { "targettarget", "target_of_target", "targetoftarget", "watchtarget" }
    end
    return { key }
end

local function logTargetDebug(message)
    if not TARGET_DEBUG_LOGGING then
        return
    end
    if api == nil or api.Log == nil or api.Log.Info == nil then
        return
    end
    api.Log:Info("[Gharka Bars] " .. tostring(message or ""))
end

local function didTargetResolve(beforeTargetId, desiredUnitId)
    local current = getCurrentTargetUnitId()
    if desiredUnitId ~= nil then
        return current == desiredUnitId, current
    end
    if beforeTargetId == nil then
        return current ~= nil, current
    end
    return current ~= beforeTargetId, current
end

local function tryTargetCall(label, callback, beforeTargetId, desiredUnitId)
    local ok, err = pcall(callback)
    local changed, current = didTargetResolve(beforeTargetId, desiredUnitId)
    if changed then
        logTargetDebug(string.format("Target success via %s -> %s", tostring(label), tostring(current)))
        return true
    end
    if not ok then
        logTargetDebug(string.format("Target attempt failed via %s: %s", tostring(label), tostring(err)))
    else
        logTargetDebug(string.format("Target attempt no-op via %s (current=%s expected=%s)", tostring(label), tostring(current), tostring(desiredUnitId)))
    end
    return false
end

local function getGuildNameFromInfo(info)
    if type(info) ~= "table" then
        return ""
    end
    return tostring(info.expeditionName or info.guildName or info.guild or "")
end

local function getUnitInfo(unit, unitId)
    local normalizedId = normalizeUnitId(unitId)
    local normalizedUnit = normalizeUnitToken(unit)
    local liveInfo = nil
    if normalizedUnit ~= nil and api.Unit.UnitInfo ~= nil then
        liveInfo = api.Unit:UnitInfo(normalizedUnit)
    end
    local info = nil
    if normalizedId ~= nil and (type(liveInfo) ~= "table" or getGuildNameFromInfo(liveInfo) == "") then
        info = api.Unit:GetUnitInfoById(normalizedId)
    end
    if type(liveInfo) == "table" then
        if type(info) == "table" then
            for key, value in pairs(info) do
                if liveInfo[key] == nil then
                    liveInfo[key] = value
                end
            end
        end
        return liveInfo
    end
    if type(info) ~= "table" then
        return nil
    end
    return info
end

local function getUnitName(unit, unitId, info)
    local nameText = ""
    local normalizedUnit = normalizeUnitToken(unit)
    if normalizedUnit ~= nil and api.Unit.UnitName ~= nil then
        nameText = api.Unit:UnitName(normalizedUnit) or ""
    end
    if nameText == "" and type(info) == "table" then
        nameText = tostring(info.name or info.unitName or "")
    end
    local normalizedId = normalizeUnitId(unitId)
    if nameText == "" and normalizedId ~= nil then
        nameText = api.Unit:GetUnitNameById(normalizedId) or ""
    end
    return nameText
end

local function getCachedUnitStatic(frame, unit, unitId, includeRole, nowMs)
    if frame == nil or frame.cache == nil or unitId == nil then
        return nil
    end
    local cached = frame.cache.unit_static
    local refreshNeeded = true
    local includeRoleBool = includeRole and true or false
    if type(cached) == "table" and cached.unit_id == unitId then
        refreshNeeded = false
        local nextRefreshMs = tonumber(cached.next_refresh_ms) or 0
        if nowMs > 0 and nextRefreshMs > 0 and nowMs >= nextRefreshMs then
            refreshNeeded = true
        end
        if cached.info == nil or tostring(cached.name_text or "") == "" then
            refreshNeeded = true
        end
    end
    if not refreshNeeded then
        return cached
    end

    local info = getUnitInfo(unit, unitId)
    local role = type(cached) == "table" and cached.role or nil
    local roleDescriptor = type(cached) == "table" and cached.role_descriptor or nil
    local rolePending = false
    local cachedRolePending = type(cached) == "table" and cached.role_pending == true
    if includeRoleBool then
        if role == nil or cachedRolePending then
            local refreshedRole, refreshedDescriptor, pending = Role.GetRoleForUnit(unit)
            rolePending = pending and true or false
            if refreshedRole ~= nil then
                role = refreshedRole
                roleDescriptor = refreshedDescriptor
            end
        end
    else
        role = nil
        roleDescriptor = nil
    end
    local nameText = getUnitName(unit, unitId, info)
    local guildText = type(info) == "table" and tostring(info.expeditionName or info.guildName or info.guild or "") or ""
    local needsRetry = info == nil or nameText == "" or guildText == ""
    if includeRoleBool and rolePending then
        needsRetry = true
    end
    local nextRefreshMs = 0
    if nowMs > 0 and needsRetry then
        nextRefreshMs = nowMs + INCOMPLETE_STATIC_REFRESH_MS + getStaticRefreshJitterMs(unit)
    elseif nowMs > 0 and getStaticRefreshIntervalMs(unit) > 0 then
        nextRefreshMs = nowMs + getStaticRefreshIntervalMs(unit) + getStaticRefreshJitterMs(unit)
    end

    cached = {
        unit_id = unitId,
        last_refresh_ms = nowMs,
        next_refresh_ms = nextRefreshMs,
        info = info,
        name_text = nameText,
        guild_text = guildText,
        role = role,
        role_descriptor = roleDescriptor,
        role_pending = rolePending
    }
    frame.cache.unit_static = cached
    return cached
end

local function getCachedCcEffects(frame, unit)
    if frame == nil or frame.cache == nil or CcEffects == nil then
        return {}
    end
    local now = safeUiNowMs()
    local last = tonumber(frame.cache.cc_last_scan_ms) or 0
    if type(frame.cache.cc_effects) == "table" and now > 0 and last > 0 and (now - last) < CC_SCAN_INTERVAL_MS then
        return frame.cache.cc_effects
    end
    local effects = CcEffects.ScanUnit(unit)
    frame.cache.cc_effects = effects
    frame.cache.cc_last_scan_ms = now
    return effects
end

local function getCachedDistance(frame, unit, nowMs)
    if frame == nil or frame.cache == nil then
        return queryUnitDistance(unit)
    end
    local isShown = frame.cache.shown == true
    local refreshMs = getDistanceRefreshIntervalMs(unit, isShown)
    if refreshMs <= 0 then
        return queryUnitDistance(unit)
    end
    local nextRefreshMs = tonumber(frame.cache.distance_next_refresh_ms) or 0
    if frame.cache.distance_unit == unit and nowMs > 0 and nextRefreshMs > nowMs then
        return frame.cache.distance_value
    end
    local distance = queryUnitDistance(unit)
    frame.cache.distance_unit = unit
    frame.cache.distance_value = distance
    frame.cache.distance_next_refresh_ms = (tonumber(nowMs) or 0) + refreshMs
    return distance
end

local function isCcCategoryEnabled(cfg, category)
    if type(cfg) ~= "table" then
        return true
    end
    local key = CC_CATEGORY_STYLE_KEYS[tostring(category or "")]
    if key == nil then
        return true
    end
    return cfg[key] ~= false
end

local function filterCcEffects(cfg, effects)
    if type(effects) ~= "table" or #effects == 0 then
        return {}
    end
    local filtered = {}
    for _, effect in ipairs(effects) do
        if type(effect) == "table" and isCcCategoryEnabled(cfg, effect.category) then
            table.insert(filtered, effect)
        end
    end
    return filtered
end

local function getPlayerVisibilityCcEffects(nowMs)
    if CcEffects == nil then
        return {}
    end
    local last = tonumber(PLAYER_CC_VISIBILITY_CACHE.last_scan_ms) or 0
    if nowMs > 0 and last > 0 and (nowMs - last) < CC_SCAN_INTERVAL_MS then
        return PLAYER_CC_VISIBILITY_CACHE.effects
    end
    local effects = CcEffects.ScanUnit("player")
    PLAYER_CC_VISIBILITY_CACHE.effects = effects
    PLAYER_CC_VISIBILITY_CACHE.last_scan_ms = nowMs
    return effects
end

local function anchorCcWidgets(frame, cfg)
    if frame == nil or frame.ccPrimary == nil then
        return
    end
    local anchor = tostring(cfg.cc_anchor or "left")
    local iconSize = clamp(cfg.cc_icon_size, 16, 48, 28)
    local secondarySize = clamp(cfg.cc_secondary_icon_size, 10, 32, 16)
    secondarySize = math.min(secondarySize, math.max(10, iconSize - 4))
    local gap = clamp(cfg.cc_gap, 0, 12, 4)
    local offsetX = clamp(cfg.cc_offset_x, -80, 80, 0)
    local offsetY = clamp(cfg.cc_offset_y, -80, 80, 0)
    local timerFont = clamp(cfg.cc_timer_font_size, 8, 24, 11)
    local secondaryTimerFont = math.max(8, timerFont - 2)
    local host = frame.hpBar or frame
    local layoutKey = table.concat({
        tostring(anchor),
        tostring(iconSize),
        tostring(secondarySize),
        tostring(gap),
        tostring(offsetX),
        tostring(offsetY),
        tostring(timerFont),
        tostring(secondaryTimerFont),
        tostring(host)
    }, "|")
    if frame.cache ~= nil and frame.cache.cc_layout_key == layoutKey then
        return
    end
    Helpers.SafeSetExtent(frame.ccPrimary, iconSize, iconSize)
    setCcTimerStyle(frame.ccPrimaryTimer, timerFont)
    Helpers.SafeAnchor(frame.ccPrimaryTimer, "CENTER", frame.ccPrimary, "CENTER", 0, 0)

    if anchor == "right" then
        Helpers.SafeAnchor(frame.ccPrimary, "LEFT", host, "RIGHT", gap + offsetX, offsetY)
    elseif anchor == "top" then
        Helpers.SafeAnchor(frame.ccPrimary, "BOTTOMLEFT", host, "TOPLEFT", offsetX, -gap + offsetY)
    else
        Helpers.SafeAnchor(frame.ccPrimary, "RIGHT", host, "LEFT", -gap + offsetX, offsetY)
    end

    local previous = frame.ccPrimary
    for _, entry in ipairs(frame.ccExtras or {}) do
        Helpers.SafeSetExtent(entry.icon, secondarySize, secondarySize)
        setCcTimerStyle(entry.timer, secondaryTimerFont)
        Helpers.SafeAnchor(entry.timer, "CENTER", entry.icon, "CENTER", 0, 0)
        if anchor == "right" or anchor == "top" then
            Helpers.SafeAnchor(entry.icon, "LEFT", previous, "RIGHT", gap, 0)
        else
            Helpers.SafeAnchor(entry.icon, "RIGHT", previous, "LEFT", -gap, 0)
        end
        previous = entry.icon
    end
    if frame.cache ~= nil then
        frame.cache.cc_layout_key = layoutKey
    end
end

local function updateCcWidgets(frame, cfg, effects, forceShow)
    if frame == nil or frame.ccPrimary == nil then
        return
    end
    effects = filterCcEffects(cfg, effects)
    if ((not forceShow) and cfg.show_cc == false) or type(effects) ~= "table" or #effects == 0 then
        hideCcWidgets(frame)
        return
    end

    anchorCcWidgets(frame, cfg)

    local primary = effects[1]
    applyCcIconStyle(frame.ccPrimary, primary.dispellable == true)
    safeSetIconPath(frame.ccPrimary, primary.path)
    Helpers.SafeShow(frame.ccPrimary, true)
    if cfg.show_cc_timer ~= false and frame.ccPrimaryTimer ~= nil then
        Helpers.SafeSetText(frame.ccPrimaryTimer, string.format("%.1f", math.max(0, (tonumber(primary.time_left_ms) or 0) / 1000)))
        Helpers.SafeShow(frame.ccPrimaryTimer, true)
    else
        Helpers.SafeShow(frame.ccPrimaryTimer, false)
    end

    local maxIcons = clamp(cfg.cc_max_icons, 1, 4, 3)
    local extraCount = 0
    if cfg.show_cc_secondary ~= false and maxIcons > 1 then
        extraCount = math.min(#effects - 1, maxIcons - 1, #frame.ccExtras)
    end

    for index, entry in ipairs(frame.ccExtras or {}) do
        local effect = effects[index + 1]
        if index <= extraCount and effect ~= nil then
            applyCcIconStyle(entry.icon, effect.dispellable == true)
            safeSetIconPath(entry.icon, effect.path)
            Helpers.SafeShow(entry.icon, true)
            if cfg.show_cc_timer ~= false and entry.timer ~= nil then
                Helpers.SafeSetText(entry.timer, string.format("%.1f", math.max(0, (tonumber(effect.time_left_ms) or 0) / 1000)))
                Helpers.SafeShow(entry.timer, true)
            else
                Helpers.SafeShow(entry.timer, false)
            end
        else
            Helpers.SafeShow(entry.icon, false)
            Helpers.SafeShow(entry.timer, false)
        end
    end
end

local function makeBorderSet(frame, rgba255)
    local border = {
        parts = {},
        rgba = rgba255
    }
    local names = { "top", "bottom", "left", "right" }
    for _, name in ipairs(names) do
        local drawable = nil
        pcall(function()
            if frame.CreateColorDrawable ~= nil then
                drawable = frame:CreateColorDrawable(1, 1, 1, 1, "overlay")
            elseif frame.CreateImageDrawable ~= nil then
                drawable = frame:CreateImageDrawable("Textures/Defaults/White.dds", "overlay")
            end
        end)
        border.parts[name] = drawable
    end
    return border
end

setBorderVisible = function(border, enabled, rgba255)
    if type(border) ~= "table" or type(border.parts) ~= "table" then
        return
    end
    local color = Helpers.Color01(rgba255 or border.rgba, { 255, 255, 255, 255 })
    local colorKey = table.concat({
        tostring(color[1] or ""),
        tostring(color[2] or ""),
        tostring(color[3] or ""),
        tostring(color[4] or "")
    }, ",")
    local wantVisible = enabled and true or false
    if border.__ghb_visible == wantVisible and border.__ghb_color_key == colorKey then
        return
    end
    for _, drawable in pairs(border.parts) do
        if drawable ~= nil then
            pcall(function()
                if drawable.SetColor ~= nil then
                    drawable:SetColor(color[1], color[2], color[3], color[4])
                end
                if drawable.Show ~= nil then
                    drawable:Show(enabled and true or false)
                elseif drawable.SetVisible ~= nil then
                    drawable:SetVisible(enabled and true or false)
                end
            end)
        end
    end
    border.__ghb_visible = wantVisible
    border.__ghb_color_key = colorKey
end

local function anchorBorderToWidget(border, widget)
    if type(border) ~= "table" or type(border.parts) ~= "table" or widget == nil then
        return
    end
    local thickness = 2
    pcall(function()
        local top = border.parts.top
        local bottom = border.parts.bottom
        local left = border.parts.left
        local right = border.parts.right
        if top ~= nil then
            top:RemoveAllAnchors()
            top:AddAnchor("TOPLEFT", widget, -2, -2)
            top:AddAnchor("TOPRIGHT", widget, 2, -2)
            if top.SetHeight ~= nil then
                top:SetHeight(thickness)
            end
        end
        if bottom ~= nil then
            bottom:RemoveAllAnchors()
            bottom:AddAnchor("BOTTOMLEFT", widget, -2, 2)
            bottom:AddAnchor("BOTTOMRIGHT", widget, 2, 2)
            if bottom.SetHeight ~= nil then
                bottom:SetHeight(thickness)
            end
        end
        if left ~= nil then
            left:RemoveAllAnchors()
            left:AddAnchor("TOPLEFT", widget, -2, -2)
            left:AddAnchor("BOTTOMLEFT", widget, -2, 2)
            if left.SetWidth ~= nil then
                left:SetWidth(thickness)
            end
        end
        if right ~= nil then
            right:RemoveAllAnchors()
            right:AddAnchor("TOPRIGHT", widget, 2, -2)
            right:AddAnchor("BOTTOMRIGHT", widget, 2, 2)
            if right.SetWidth ~= nil then
                right:SetWidth(thickness)
            end
        end
    end)
end

local function shouldShowUnit(unit, settings)
    if unit == "target" then
        return settings.show_target and true or false
    elseif unit == "player" then
        return settings.show_player and true or false
    elseif unit == "watchtarget" then
        return settings.show_watchtarget and true or false
    elseif unit == "playerpet1" then
        return settings.show_mount and true or false
    elseif string.match(unit or "", "^team%d+$") then
        return settings.show_raid_party and true or false
    end
    return false
end

local function ensureUnitKeys()
    if #Bars.unit_keys > 0 then
        return
    end
    table.insert(Bars.hot_unit_keys, "target")
    table.insert(Bars.hot_unit_keys, "player")
    table.insert(Bars.hot_unit_keys, "watchtarget")
    for _, unit in ipairs(Bars.hot_unit_keys) do
        table.insert(Bars.unit_keys, unit)
    end
    for i = 1, 50 do
        local unit = string.format("team%d", i)
        table.insert(Bars.bulk_unit_keys, unit)
        table.insert(Bars.unit_keys, unit)
    end
    table.insert(Bars.bulk_unit_keys, "playerpet1")
    table.insert(Bars.unit_keys, "playerpet1")
end

local function rebuildActiveBulkUnitKeys()
    Bars.active_bulk_unit_keys = {}
    for _, unit in ipairs(Bars.bulk_unit_keys) do
        local frame = Bars.frames[unit]
        if frame ~= nil and frame.cache ~= nil and frame.cache.data_active then
            table.insert(Bars.active_bulk_unit_keys, unit)
        end
    end
end

local function buildLiveBulkUnitBuckets(includeRecentShown)
    local buckets = {
        active = {},
        shown = {},
        hidden = {},
        inactive = {},
    }
    local nowMs = safeUiNowMs()

    for _, unit in ipairs(Bars.bulk_unit_keys or {}) do
        local frame = Bars.frames[unit]
        local cache = frame ~= nil and frame.cache or nil
        local isActive = cache ~= nil and cache.data_active == true

        if isActive then
            buckets.active[#buckets.active + 1] = unit

            local lastVisibleMs = tonumber(cache.last_visible_ms) or 0
            local recentlyVisible = includeRecentShown
                and lastVisibleMs > 0
                and nowMs > 0
                and (nowMs - lastVisibleMs) < RECENTLY_VISIBLE_POSITION_GRACE_MS

            if cache.shown or recentlyVisible then
                buckets.shown[#buckets.shown + 1] = unit
            else
                buckets.hidden[#buckets.hidden + 1] = unit
            end
        else
            buckets.inactive[#buckets.inactive + 1] = unit
        end
    end

    return buckets
end

local function getBulkPositionIntervalMs()
    local activeCount = #Bars.active_bulk_unit_keys
    if activeCount >= 36 then
        return BULK_POSITION_INTERVAL_XL_MS
    end
    if activeCount >= 24 then
        return BULK_POSITION_INTERVAL_LARGE_MS
    end
    if activeCount >= 12 then
        return BULK_POSITION_INTERVAL_MEDIUM_MS
    end
    return BULK_POSITION_INTERVAL_SMALL_MS
end

local function ensureRootWindow()
    if Bars.root_window ~= nil then
        return Bars.root_window
    end
    local root = api.Interface:CreateEmptyWindow("gharkaBarsRoot")
    if root == nil then
        return nil
    end
    pcall(function()
        if root.SetCloseOnEscape ~= nil then
            root:SetCloseOnEscape(false)
        end
    end)
    pcall(function()
        if root.EnableHidingIsRemove ~= nil then
            root:EnableHidingIsRemove(false)
        end
    end)
    pcall(function()
        if root.RemoveAllAnchors ~= nil then
            root:RemoveAllAnchors()
        end
    end)
    pcall(function()
        if root.AddAnchor ~= nil then
            root:AddAnchor("TOPLEFT", "UIParent", "TOPLEFT", 0, 0)
            root:AddAnchor("BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", 0, 0)
        end
    end)
    pcall(function()
        if root.SetUILayer ~= nil and Bars.layer_mode ~= nil and Bars.layer_mode ~= "default" then
            root:SetUILayer(Bars.layer_mode)
        end
    end)
    Helpers.SafeClickable(root, false)
    Helpers.SafeShow(root, true)
    Bars.root_window = root
    return root
end

local function createFrameContainer(frameId)
    local root = ensureRootWindow()
    if root ~= nil then
        local frame = nil
        pcall(function()
            frame = api.Interface:CreateWidget("emptywidget", frameId, root)
        end)
        if frame ~= nil then
            frame.__ghb_top_level = false
            Helpers.SafeClickable(frame, false)
            Helpers.SafeShow(frame, false)
            return frame
        end
    end
    local frame = api.Interface:CreateEmptyWindow(frameId)
    if frame ~= nil then
        frame.__ghb_top_level = true
        pcall(function()
            if frame.SetUILayer ~= nil and Bars.layer_mode ~= nil and Bars.layer_mode ~= "default" then
                frame:SetUILayer(Bars.layer_mode)
            end
        end)
        Helpers.SafeClickable(frame, false)
        Helpers.SafeShow(frame, false)
    end
    return frame
end

local function ensureFrame(unit)
    if Bars.frames[unit] ~= nil then
        return Bars.frames[unit]
    end
    local frameId = "gharkaBars_" .. tostring(unit)
    local frame = createFrameContainer(frameId)
    if frame == nil then
        return nil
    end

    local bg = nil
    pcall(function()
        if frame.CreateNinePartDrawable ~= nil and TEXTURE_PATH ~= nil and TEXTURE_PATH.RAID ~= nil then
            bg = frame:CreateNinePartDrawable(TEXTURE_PATH.RAID, "background")
            bg:SetCoords(33, 141, 7, 7)
            bg:SetInset(3, 3, 3, 3)
            bg:SetColor(1, 1, 1, 0.72)
            bg:Show(false)
        end
    end)
    frame.bg = bg

    local targetGlow = nil
    local targetTint = nil
    pcall(function()
        targetGlow = makeBorderSet(frame, TARGET_GLOW_COLOR)
        targetTint = makeBorderSet(frame, TARGET_TINT_COLOR)
        setBorderVisible(targetGlow, false, TARGET_GLOW_COLOR)
        setBorderVisible(targetTint, false, TARGET_TINT_COLOR)
    end)
    frame.targetGlow = targetGlow
    frame.targetTint = targetTint

    local hpBar = nil
    local mpBar = nil
    pcall(function()
        if W_BAR ~= nil and W_BAR.CreateStatusBarOfRaidFrame ~= nil then
            hpBar = W_BAR.CreateStatusBarOfRaidFrame(frameId .. ".hpBar", frame)
            mpBar = W_BAR.CreateStatusBarOfRaidFrame(frameId .. ".mpBar", frame)
            if hpBar ~= nil then
                hpBar:Show(true)
                hpBar:Clickable(false)
                if hpBar.statusBar ~= nil and hpBar.statusBar.Clickable ~= nil then
                    hpBar.statusBar:Clickable(false)
                end
                if STATUSBAR_STYLE ~= nil and STATUSBAR_STYLE.HP_RAID ~= nil then
                    hpBar:ApplyBarTexture(STATUSBAR_STYLE.HP_RAID)
                end
            end
            if mpBar ~= nil then
                mpBar:Show(true)
                mpBar:Clickable(false)
                if mpBar.statusBar ~= nil and mpBar.statusBar.Clickable ~= nil then
                    mpBar.statusBar:Clickable(false)
                end
                if STATUSBAR_STYLE ~= nil and STATUSBAR_STYLE.MP_RAID ~= nil then
                    mpBar:ApplyBarTexture(STATUSBAR_STYLE.MP_RAID)
                end
            end
        end
    end)
    frame.hpBar = hpBar
    frame.mpBar = mpBar
    local function makeLabel(suffix)
        local label = api.Interface:CreateWidget("label", frameId .. "." .. suffix, frame)
        Helpers.SafeClickable(label, false)
        return label
    end

    frame.nameLabel = makeLabel("name")
    frame.guildLabel = makeLabel("guild")
    frame.roleLabel = makeLabel("role")
    frame.hpValueLabel = makeLabel("hpValue")
    frame.mpValueLabel = makeLabel("mpValue")
    frame.distanceLabel = makeLabel("distance")
    frame.ccPrimary = safeCreateCcIcon(frameId .. ".ccPrimary", frame)
    frame.ccPrimaryTimer = makeCcTimerLabel(frameId .. ".ccPrimaryTimer", frame.ccPrimary)
    frame.ccExtras = {}
    for index = 1, CC_EXTRA_ICON_COUNT do
        local icon = safeCreateCcIcon(frameId .. ".ccExtra" .. tostring(index), frame)
        local timer = makeCcTimerLabel(frameId .. ".ccExtraTimer" .. tostring(index), icon)
        table.insert(frame.ccExtras, {
            icon = icon,
            timer = timer
        })
    end
    local eventWindow = api.Interface:CreateWidget("emptywidget", frameId .. ".event", frame)
    pcall(function()
        eventWindow:AddAnchor("TOPLEFT", frame, 0, 0)
        eventWindow:AddAnchor("BOTTOMRIGHT", frame, 0, 0)
        eventWindow:Show(false)
        if eventWindow.EnablePick ~= nil then
            eventWindow:EnablePick(true)
        end
    end)
    Helpers.SafeClickable(eventWindow, false)
    local function onHoverEnter()
        Bars.hovered_unit = frame.__ghb_unit or unit
    end
    local function onHoverLeave()
        if Bars.hovered_unit == (frame.__ghb_unit or unit) then
            Bars.hovered_unit = nil
        end
    end
    if frame.SetHandler ~= nil then
        frame:SetHandler("OnEnter", onHoverEnter)
        frame:SetHandler("OnLeave", onHoverLeave)
    end
    if eventWindow ~= nil and eventWindow.SetHandler ~= nil then
        eventWindow:SetHandler("OnEnter", onHoverEnter)
        eventWindow:SetHandler("OnLeave", onHoverLeave)
        eventWindow:SetHandler("OnClick", function(_, button)
            if button == "RightButton" or button == "MiddleButton" then
                return
            end
            if frame.__ghb_click_target ~= true then
                return
            end
            local clickUnit = frame.__ghb_unit or unit
            if shouldPreferUnitIdClickTarget(clickUnit) and frame.__ghb_unit_id ~= nil then
                changeTarget(nil, frame.__ghb_unit_id)
                return
            end
            changeTarget(clickUnit, frame.__ghb_unit_id)
        end)
    end
    frame.eventWindow = eventWindow
    frame.__ghb_unit = unit
    frame.__ghb_unit_id = nil
    frame.__ghb_click_target = false
    frame.cache = {}
    setEventWindowInteraction(frame, false)
    hideCcWidgets(frame)
    applyLayerToFrame(frame)
    Bars.frames[unit] = frame
    return frame
end

local function currentLayerMode(settings)
    if type(settings) ~= "table" then
        return "default"
    end
    local mode = tostring(settings.frame_layer_mode or "default")
    if mode == "default" then
        return "default"
    end
    if VALID_UI_LAYERS[mode] then
        return mode
    end
    return "default"
end

local function applyLayerToWidget(widget)
    if widget == nil or widget.SetUILayer == nil then
        return
    end
    local mode = Bars.layer_mode or "default"
    if mode == "default" then
        return
    end
    if widget.__ghb_ui_layer == mode then
        return
    end
    pcall(function()
        widget:SetUILayer(mode)
    end)
    widget.__ghb_ui_layer = mode
end

applyLayerToFrame = function(frame)
    if frame == nil then
        return
    end
    applyLayerToWidget(frame)
    applyLayerToWidget(frame.eventWindow)
    applyLayerToWidget(frame.nameLabel)
    applyLayerToWidget(frame.guildLabel)
    applyLayerToWidget(frame.roleLabel)
    applyLayerToWidget(frame.hpValueLabel)
    applyLayerToWidget(frame.mpValueLabel)
    applyLayerToWidget(frame.distanceLabel)
    applyLayerToWidget(frame.ccPrimary)
    applyLayerToWidget(frame.ccPrimaryTimer)
    applyLayerToWidget(frame.hpBar)
    applyLayerToWidget(frame.mpBar)
    if frame.ccPrimary ~= nil then
        applyLayerToWidget(frame.ccPrimary.back)
    end
    for _, entry in ipairs(frame.ccExtras or {}) do
        applyLayerToWidget(entry.icon)
        applyLayerToWidget(entry.timer)
        if entry.icon ~= nil then
            applyLayerToWidget(entry.icon.back)
        end
    end
    if frame.hpBar ~= nil then
        applyLayerToWidget(frame.hpBar.statusBar)
    end
    if frame.mpBar ~= nil then
        applyLayerToWidget(frame.mpBar.statusBar)
    end
end

local function hasAnyFrames()
    for _ in pairs(Bars.frames) do
        return true
    end
    return false
end

local function syncLayerMode(settings)
    local mode = currentLayerMode(settings)
    if Bars.layer_mode == mode then
        return
    end
    if hasAnyFrames() then
        Bars.Unload()
    end
    Bars.layer_mode = mode
    ensureUnitKeys()
    Bars.target_unitframe = getStockTargetFrame()
    Bars.watchtarget_unitframe = getStockWatchtargetFrame()
    Bars.targetoftarget_unitframe = getStockTargetOfTargetFrame()
end

changeTarget = function(unit, unitId)
    if unit == nil and unitId == nil then
        return
    end

    local beforeTargetId = getCurrentTargetUnitId()
    local desiredUnitId = normalizeUnitId(unitId)
    local normalizedUnit = normalizeTargetToken(unit)
    local unitCandidates = getTargetUnitCandidates(normalizedUnit)
    local targetInfo = getUnitInfo(normalizedUnit, desiredUnitId)
    local targetName = getUnitName(normalizedUnit, desiredUnitId, targetInfo)
    logTargetDebug(string.format("Click target request unit=%s unitId=%s current=%s", tostring(normalizedUnit), tostring(desiredUnitId), tostring(beforeTargetId)))

    if normalizedUnit == nil and desiredUnitId == nil and (targetName == nil or targetName == "") then
        return
    end

    if normalizedUnit == "player" then
        if type(TargetUnit) == "function" then
            if tryTargetCall("TargetUnit(player)", function()
                TargetUnit("player")
            end, beforeTargetId, desiredUnitId) then
                return
            end
        end
        if api ~= nil and api.Unit ~= nil and type(api.Unit.TargetUnit) == "function" then
            if tryTargetCall("api.Unit.TargetUnit(player)", function()
                api.Unit.TargetUnit("player")
            end, beforeTargetId, desiredUnitId) then
                return
            end
            if tryTargetCall("api.Unit:TargetUnit(player)", function()
                api.Unit:TargetUnit("player")
            end, beforeTargetId, desiredUnitId) then
                return
            end
        end
        if type(X2Unit) == "table" and type(X2Unit.TargetUnit) == "function" then
            if tryTargetCall("X2Unit.TargetUnit(player)", function()
                X2Unit.TargetUnit("player")
            end, beforeTargetId, desiredUnitId) then
                return
            end
            if tryTargetCall("X2Unit:TargetUnit(player)", function()
                X2Unit:TargetUnit("player")
            end, beforeTargetId, desiredUnitId) then
                return
            end
        end
        return
    end

    if type(TargetUnit) == "function" then
        for _, candidate in ipairs(unitCandidates) do
            if tryTargetCall("TargetUnit(" .. tostring(candidate) .. ")", function()
                TargetUnit(candidate)
            end, beforeTargetId, desiredUnitId) then
                return
            end
        end
        if desiredUnitId ~= nil then
            if tryTargetCall("TargetUnit(unitId)", function()
                TargetUnit(desiredUnitId)
            end, beforeTargetId, desiredUnitId) then
                return
            end
        end
    end

    if api ~= nil and api.Unit ~= nil and type(api.Unit.TargetUnit) == "function" then
        for _, candidate in ipairs(unitCandidates) do
            if tryTargetCall("api.Unit.TargetUnit(" .. tostring(candidate) .. ")", function()
                api.Unit.TargetUnit(candidate)
            end, beforeTargetId, desiredUnitId) then
                return
            end
            if tryTargetCall("api.Unit:TargetUnit(" .. tostring(candidate) .. ")", function()
                api.Unit:TargetUnit(candidate)
            end, beforeTargetId, desiredUnitId) then
                return
            end
        end
        if desiredUnitId ~= nil then
            if tryTargetCall("api.Unit.TargetUnit(unitId)", function()
                api.Unit.TargetUnit(desiredUnitId)
            end, beforeTargetId, desiredUnitId) then
                return
            end
            if tryTargetCall("api.Unit:TargetUnit(unitId)", function()
                api.Unit:TargetUnit(desiredUnitId)
            end, beforeTargetId, desiredUnitId) then
                return
            end
        end
    end

    if type(X2Unit) == "table" and type(X2Unit.TargetUnit) == "function" then
        for _, candidate in ipairs(unitCandidates) do
            if tryTargetCall("X2Unit.TargetUnit(" .. tostring(candidate) .. ")", function()
                X2Unit.TargetUnit(candidate)
            end, beforeTargetId, desiredUnitId) then
                return
            end
            if tryTargetCall("X2Unit:TargetUnit(" .. tostring(candidate) .. ")", function()
                X2Unit:TargetUnit(candidate)
            end, beforeTargetId, desiredUnitId) then
                return
            end
        end
        if desiredUnitId ~= nil then
            if tryTargetCall("X2Unit.TargetUnit(unitId)", function()
                X2Unit.TargetUnit(desiredUnitId)
            end, beforeTargetId, desiredUnitId) then
                return
            end
            if tryTargetCall("X2Unit:TargetUnit(unitId)", function()
                X2Unit:TargetUnit(desiredUnitId)
            end, beforeTargetId, desiredUnitId) then
                return
            end
        end
    end

    if targetName ~= nil and targetName ~= "" then
        if type(TargetUnit) == "function" then
            if tryTargetCall("TargetUnit(name)", function()
                TargetUnit(targetName)
            end, beforeTargetId, desiredUnitId) then
                return
            end
        end
        if api ~= nil and api.Unit ~= nil and type(api.Unit.TargetUnit) == "function" then
            if tryTargetCall("api.Unit.TargetUnit(name)", function()
                api.Unit.TargetUnit(targetName)
            end, beforeTargetId, desiredUnitId) then
                return
            end
            if tryTargetCall("api.Unit:TargetUnit(name)", function()
                api.Unit:TargetUnit(targetName)
            end, beforeTargetId, desiredUnitId) then
                return
            end
        end
        if type(X2Unit) == "table" and type(X2Unit.TargetUnit) == "function" then
            if tryTargetCall("X2Unit.TargetUnit(name)", function()
                X2Unit.TargetUnit(targetName)
            end, beforeTargetId, desiredUnitId) then
                return
            end
            if tryTargetCall("X2Unit:TargetUnit(name)", function()
                X2Unit:TargetUnit(targetName)
            end, beforeTargetId, desiredUnitId) then
                return
            end
        end
    end

    local tu, stockUnit = getStockFrameForUnit(normalizedUnit)
    if tu == nil or tu.eventWindow == nil or tu.eventWindow.OnClick == nil then
        logTargetDebug("Matching stock frame unavailable")
        return
    end

    for _, candidate in ipairs(getStockFrameMethodCandidates(unit)) do
        local method = candidate.method
        if type(tu[method]) == "function" then
            if tryTargetCall(tostring(candidate.label), function()
                tu[method](tu, unpack(candidate.args))
                if tu.UpdateAll ~= nil then
                    tu:UpdateAll()
                end
            end, beforeTargetId, desiredUnitId) then
                return
            end
        end
    end

    if tryTargetCall("stock target frame(native)", function()
        tu.eventWindow:OnClick("LeftButton")
        if tu.ChangedTarget ~= nil then
            tu:ChangedTarget()
        end
        if tu.UpdateAll ~= nil then
            tu:UpdateAll()
        end
    end, beforeTargetId, desiredUnitId) then
        return
    end

    if tryTargetCall("stock target frame(unit)", function()
        if tu.target ~= nil then
            tu.target = stockUnit or unit
        end
        tu.eventWindow:OnClick("LeftButton")
        if tu.target ~= nil then
            tu.target = stockUnit or "target"
        end
        if tu.ChangedTarget ~= nil then
            tu:ChangedTarget()
        end
        if tu.UpdateAll ~= nil then
            tu:UpdateAll()
        end
    end, beforeTargetId, desiredUnitId) then
        return
    end

    if desiredUnitId ~= nil then
        if tryTargetCall("stock target frame(unitId)", function()
            if tu.target ~= nil then
                tu.target = desiredUnitId
            end
            tu.eventWindow:OnClick("LeftButton")
            if tu.target ~= nil then
                tu.target = stockUnit or "target"
            end
            if tu.ChangedTarget ~= nil then
                tu:ChangedTarget()
            end
            if tu.UpdateAll ~= nil then
                tu:UpdateAll()
            end
        end, beforeTargetId, desiredUnitId) then
            return
        end
    end

    logTargetDebug("All targeting paths failed")
end

local function updateCachedText(frame, key, widget, text)
    if frame.cache[key] ~= text then
        frame.cache[key] = text
        Helpers.SafeSetText(widget, text)
    end
end

local function updateCachedLabelColor(frame, key, widget, rgba, fallback)
    if frame == nil or frame.cache == nil or widget == nil then
        return
    end
    local src = type(rgba) == "table" and rgba or fallback or { 255, 255, 255, 255 }
    local cacheKey = table.concat({
        tostring(src[1] or ""),
        tostring(src[2] or ""),
        tostring(src[3] or ""),
        tostring(src[4] or "")
    }, ",")
    if frame.cache[key] == cacheKey then
        return
    end
    frame.cache[key] = cacheKey
    Helpers.SetLabelColor(widget, src, fallback)
end

local function trimText(text, maxChars)
    local raw = tostring(text or "")
    local limit = clamp(maxChars, 0, 64, 0)
    if limit <= 0 or string.len(raw) <= limit then
        return raw
    end
    return string.sub(raw, 1, limit)
end

local function readHealthValues(unit)
    local hp = tonumber(api.Unit:UnitHealth(unit))
    local hpMax = tonumber(api.Unit:UnitMaxHealth(unit))
    if hp == nil or hpMax == nil or hpMax <= 0 then
        return nil, nil
    end
    hp = clamp(hp, 0, hpMax, 0)
    return hp, hpMax
end

local function readManaValues(unit)
    local mp = tonumber(api.Unit:UnitMana(unit)) or 0
    local mpMax = tonumber(api.Unit:UnitMaxMana(unit)) or 0
    if mpMax < 0 then
        mpMax = 0
    end
    if mpMax > 0 then
        mp = clamp(mp, 0, mpMax, 0)
    elseif mp < 0 then
        mp = 0
    end
    return mp, mpMax
end

local function updateStatusBar(frame, prefix, bar, currentValue, maxValue)
    if bar == nil or bar.statusBar == nil then
        return
    end
    local currentNum = tonumber(currentValue) or 0
    local maxNum = tonumber(maxValue) or 0
    if frame.cache[prefix .. "_max"] ~= maxNum and bar.statusBar.SetMinMaxValues ~= nil then
        frame.cache[prefix .. "_max"] = maxNum
        pcall(function()
            bar.statusBar:SetMinMaxValues(0, maxNum)
        end)
    end
    if frame.cache[prefix .. "_value"] ~= currentNum and bar.statusBar.SetValue ~= nil then
        frame.cache[prefix .. "_value"] = currentNum
        pcall(function()
            bar.statusBar:SetValue(currentNum)
        end)
    end
end

local function unitHasBuff(unit, buffId)
    if api.Unit == nil or api.Unit.UnitBuffCount == nil or api.Unit.UnitBuff == nil then
        return false
    end
    local buffCount = api.Unit:UnitBuffCount(unit) or 0
    for index = 1, tonumber(buffCount) or 0 do
        local buff = api.Unit:UnitBuff(unit, index)
        if type(buff) == "table" and tonumber(buff.buff_id) == buffId then
            return true
        end
    end
    return false
end

local function isTeamUnit(unit)
    return string.match(unit or "", "^team%d+$") ~= nil
end

local function isUnitTeamMember(unit)
    if api.Unit == nil or api.Unit.UnitIsTeamMember == nil then
        return isTeamUnit(unit)
    end
    return api.Unit:UnitIsTeamMember(unit) and true or false
end

local function isBloodlustFriendlyUnit(unit, info)
    local faction = type(info) == "table" and tostring(info.faction or "") or ""
    if faction == "hostile" or faction == "neutral" then
        return false
    end
    return unitHasBuff(unit, BLOODLUST_BUFF_ID)
end

local function getCachedBloodlustState(frame, unit, unitId, info, nowMs)
    if frame == nil or frame.cache == nil or unitId == nil then
        return isBloodlustFriendlyUnit(unit, info)
    end
    local faction = type(info) == "table" and tostring(info.faction or "") or ""
    if faction == "hostile" or faction == "neutral" then
        frame.cache.bloodlust_unit_id = unitId
        frame.cache.bloodlust_active = false
        frame.cache.bloodlust_next_scan_ms = 0
        return false
    end
    local nextScanMs = tonumber(frame.cache.bloodlust_next_scan_ms) or 0
    if frame.cache.bloodlust_unit_id == unitId and nowMs > 0 and nextScanMs > nowMs then
        return frame.cache.bloodlust_active == true
    end
    local active = isBloodlustFriendlyUnit(unit, info)
    frame.cache.bloodlust_unit_id = unitId
    frame.cache.bloodlust_active = active and true or false
    frame.cache.bloodlust_next_scan_ms = (tonumber(nowMs) or 0) + getBloodlustScanIntervalMs(unit)
    return frame.cache.bloodlust_active
end

local function getBarRelation(frame, unit, unitId, info, nowMs)
    local faction = type(info) == "table" and tostring(info.faction or "") or ""
    if getCachedBloodlustState(frame, unit, unitId, info, nowMs) then
        return "bloodlust"
    end
    if faction == "hostile" then
        return "hostile"
    end
    if faction == "neutral" then
        return "neutral"
    end
    return "friendly"
end

local function blendHpGradientColor(currentValue, maxValue)
    local maxNum = tonumber(maxValue) or 0
    local pct = 1
    if maxNum > 0 then
        pct = clamp((tonumber(currentValue) or 0) / maxNum, 0, 1, 0)
    end
    local low = HP_GRADIENT_LOW_COLOR
    local high = HP_GRADIENT_HIGH_COLOR
    return {
        math.floor(low[1] + ((high[1] - low[1]) * pct) + 0.5),
        math.floor(low[2] + ((high[2] - low[2]) * pct) + 0.5),
        math.floor(low[3] + ((high[3] - low[3]) * pct) + 0.5),
        math.floor(low[4] + ((high[4] - low[4]) * pct) + 0.5)
    }
end

local function getHpBarAppearance(frame, unit, unitId, cfg, info, currentValue, maxValue, nowMs)
    local relation = getBarRelation(frame, unit, unitId, info, nowMs)
    if relation == "bloodlust" then
        if isUnitTeamMember(unit) then
            return relation, Helpers.Color01(cfg.bloodlust_team_color, { 255, 140, 40, 255 }), nil
        end
        return relation, Helpers.Color01(cfg.bloodlust_target_color, { 170, 80, 255, 255 }), nil
    end
    if relation == "hostile" then
        return relation, Helpers.Color01(cfg.hostile_bar_color, { 176, 46, 46, 255 }), HOSTILE_TEXT_COLOR
    end
    if relation == "neutral" then
        return relation, Helpers.Color01(cfg.neutral_bar_color, { 184, 148, 52, 255 }), NEUTRAL_TEXT_COLOR
    end
    if cfg.hp_color_mode == "red_blue_gradient" then
        return relation, Helpers.Color01(blendHpGradientColor(currentValue, maxValue), HP_GRADIENT_HIGH_COLOR), nil
    end
    return relation, Helpers.Color01(cfg.hp_bar_color, { 220, 46, 46, 255 }), nil
end

local function updateHpBarColor(frame, unit, unitId, cfg, info, currentValue, maxValue, nowMs)
    if frame == nil or frame.hpBar == nil or frame.hpBar.statusBar == nil then
        return
    end
    local relation, rgba, textColor = getHpBarAppearance(frame, unit, unitId, cfg, info, currentValue, maxValue, nowMs)
    local key = table.concat({
        tostring(rgba[1] or ""),
        tostring(rgba[2] or ""),
        tostring(rgba[3] or ""),
        tostring(rgba[4] or "")
    }, ",")
    if frame.cache.hp_bar_color_key ~= key then
        frame.cache.hp_bar_color_key = key
        Helpers.ApplyStatusBarColor(frame.hpBar.statusBar, rgba)
    end
    frame.cache.hp_bar_relation = relation
    if textColor ~= nil then
        updateCachedLabelColor(frame, "name_color_dynamic", frame.nameLabel, textColor, HOSTILE_TEXT_COLOR)
        updateCachedLabelColor(frame, "hp_color_dynamic", frame.hpValueLabel, textColor, HOSTILE_TEXT_COLOR)
        updateCachedLabelColor(frame, "mp_color_dynamic", frame.mpValueLabel, textColor, HOSTILE_TEXT_COLOR)
    else
        updateCachedLabelColor(frame, "name_color_dynamic", frame.nameLabel, cfg.name_color, { 255, 255, 255, 255 })
        updateCachedLabelColor(frame, "hp_color_dynamic", frame.hpValueLabel, cfg.value_color, { 255, 255, 255, 255 })
        updateCachedLabelColor(frame, "mp_color_dynamic", frame.mpValueLabel, cfg.value_color, { 255, 255, 255, 255 })
    end
end

local function hideFrame(frame)
    if frame == nil then
        return
    end
    if frame.cache ~= nil and frame.cache.data_active == false and frame.cache.shown == false then
        return
    end
    if frame.cache ~= nil then
        frame.cache.display_enabled = false
        frame.cache.data_active = false
        frame.cache.shown = false
    end
    Role.Hide(frame)
    setBorderVisible(frame.targetGlow, false, TARGET_GLOW_COLOR)
    setBorderVisible(frame.targetTint, false, TARGET_TINT_COLOR)
    hideCcWidgets(frame)
    Helpers.SafeShow(frame, false)
end

local function fadeFrame(frame, targetAlpha, nowMs)
    if frame == nil or frame.cache == nil then
        return
    end
    local cache = frame.cache
    local target = clamp(targetAlpha, 0, 1, 0)
    local current = tonumber(cache.fade_alpha)
    if current == nil then
        current = cache.shown and 1 or 0
    end
    nowMs = tonumber(nowMs) or safeUiNowMs()
    local lastMs = tonumber(cache.fade_last_ms) or nowMs
    local delta = nowMs - lastMs
    if delta < 0 then
        delta = 0
    end
    if delta > 250 then
        delta = 250
    end
    local step = FRAME_FADE_DURATION_MS > 0 and (delta / FRAME_FADE_DURATION_MS) or 1
    if step > 1 then
        step = 1
    end

    local nextAlpha = current
    if target > current then
        nextAlpha = math.min(target, current + step)
    elseif target < current then
        nextAlpha = math.max(target, current - step)
    end

    cache.fade_alpha = nextAlpha
    cache.fade_target_alpha = target
    cache.fade_last_ms = nowMs

    if nextAlpha > 0.01 then
        cache.shown = true
        cache.last_visible_ms = nowMs
        Helpers.SafeShow(frame, true)
        applyFrameCompositeAlpha(frame)
    else
        Helpers.SafeSetAlpha(frame, 0)
        if target <= 0 then
            cache.shown = false
            Role.Hide(frame)
            setBorderVisible(frame.targetGlow, false, TARGET_GLOW_COLOR)
            setBorderVisible(frame.targetTint, false, TARGET_TINT_COLOR)
            hideCcWidgets(frame)
            setEventWindowInteraction(frame, false)
            Helpers.SafeShow(frame, false)
        end
    end
end

local function showFrame(frame, nowMs)
    fadeFrame(frame, 1, nowMs)
end

local function fadeOutFrame(frame, nowMs)
    fadeFrame(frame, 0, nowMs)
end

local function setFrameDisplayEnabled(frame, enabled)
    if frame == nil or frame.cache == nil then
        return
    end
    frame.cache.display_enabled = enabled and true or false
end

local function applyTargetHighlight(frame, isCurrentTarget)
    if frame == nil then
        return
    end
    if frame.cache ~= nil then
        frame.cache.is_current_target = isCurrentTarget and true or false
    end
    setBorderVisible(frame.targetGlow, isCurrentTarget, TARGET_GLOW_COLOR)
    setBorderVisible(frame.targetTint, isCurrentTarget, TARGET_TINT_COLOR)
end

local function getScreenPosition(frame, unit, settings)
    unit = normalizeUnitToken(unit)
    if unit == nil then
        return nil, nil, nil
    end
    local cache = frame ~= nil and frame.cache or nil
    local preferredMethod = cache ~= nil and tostring(cache.position_method or "") or ""
    local function tryNametag()
        if not settings.anchor_to_nametag or api.Unit.GetUnitScreenNameTagOffset == nil then
            return nil, nil, nil
        end
        return api.Unit:GetUnitScreenNameTagOffset(unit)
    end
    local function tryScreen()
        return api.Unit:GetUnitScreenPosition(unit)
    end

    local order = {}
    if preferredMethod == "screen" then
        order = { "screen", "nametag" }
    elseif preferredMethod == "nametag" then
        order = { "nametag", "screen" }
    elseif settings.anchor_to_nametag then
        order = { "nametag", "screen" }
    else
        order = { "screen", "nametag" }
    end

    for _, method in ipairs(order) do
        local screenX, screenY, screenZ = nil, nil, nil
        if method == "nametag" then
            screenX, screenY, screenZ = tryNametag()
        else
            screenX, screenY, screenZ = tryScreen()
        end
        if screenX ~= nil and screenY ~= nil then
            if cache ~= nil then
                cache.position_method = method
            end
            return screenX, screenY, screenZ
        end
    end

    return nil, nil, nil
end

local function getPositionLossGraceMs(unit)
    if tostring(unit or "") == "player" then
        return PLAYER_POSITION_LOSS_GRACE_MS
    end
    return POSITION_LOSS_GRACE_MS
end

local function rememberValidScreenPosition(frame, screenX, screenY, screenZ, nowMs)
    if frame == nil or frame.cache == nil then
        return
    end
    frame.cache.last_valid_screen_x = tonumber(screenX)
    frame.cache.last_valid_screen_y = tonumber(screenY)
    frame.cache.last_valid_screen_z = tonumber(screenZ)
    frame.cache.last_valid_screen_ms = tonumber(nowMs) or 0
    frame.cache.invalid_screen_since_ms = nil
end

local function resolveStableScreenPosition(frame, unit, settings, nowMs, graceUnit)
    local screenX, screenY, screenZ = getScreenPosition(frame, unit, settings)
    local valid = screenX ~= nil and screenY ~= nil and (screenZ == nil or screenZ >= 0)
    if valid then
        rememberValidScreenPosition(frame, screenX, screenY, screenZ, nowMs)
        return screenX, screenY, screenZ, true
    end

    if frame == nil or frame.cache == nil then
        return nil, nil, screenZ, false
    end

    local cache = frame.cache
    if screenZ ~= nil and screenZ < 0 then
        cache.invalid_screen_since_ms = tonumber(nowMs) or 0
        return nil, nil, screenZ, false
    end

    if cache.invalid_screen_since_ms == nil then
        cache.invalid_screen_since_ms = tonumber(nowMs) or 0
    end

    local graceMs = getPositionLossGraceMs(graceUnit or unit)
    local invalidSinceMs = tonumber(cache.invalid_screen_since_ms) or 0
    local staleForMs = (tonumber(nowMs) or 0) - invalidSinceMs
    local lastX = tonumber(cache.last_valid_screen_x)
    local lastY = tonumber(cache.last_valid_screen_y)
    if lastX ~= nil and lastY ~= nil and cache.shown and staleForMs < graceMs then
        return lastX, lastY, tonumber(cache.last_valid_screen_z), false
    end

    return nil, nil, screenZ, false
end

local function shouldHideForDistance(frame, unit, distance, cfg, nowMs)
    if type(distance) ~= "number" then
        if frame ~= nil and frame.cache ~= nil then
            frame.cache.distance_out_since_ms = nil
        end
        return false
    end

    local maxDistance = clamp(cfg.max_distance, 10, 300, 130)
    if distance <= maxDistance then
        if frame ~= nil and frame.cache ~= nil then
            frame.cache.distance_out_since_ms = nil
        end
        return false
    end

    local cache = frame ~= nil and frame.cache or nil
    if cache ~= nil and cache.shown and distance <= (maxDistance + DISTANCE_HIDE_HYSTERESIS_M) then
        cache.distance_out_since_ms = nil
        return false
    end

    if cache == nil then
        return true
    end

    if cache.distance_out_since_ms == nil then
        cache.distance_out_since_ms = tonumber(nowMs) or 0
        return false
    end

    local elapsed = (tonumber(nowMs) or 0) - (tonumber(cache.distance_out_since_ms) or 0)
    if elapsed < DISTANCE_HIDE_GRACE_MS then
        return false
    end

    return true
end

local function placeFrame(frame, cfg, screenX, screenY)
    if frame == nil or frame.cache == nil then
        return
    end
    local width = tonumber(frame.cache.frame_width) or clamp(cfg.width, 80, 320, 156)
    local rawX = tonumber(screenX) or 0
    local rawY = tonumber(screenY) or 0
    local targetX = rawX + clamp(cfg.x_offset, -500, 500, 0) - (width / 2)
    local targetY = rawY - clamp(cfg.y_offset, -200, 200, 24)
    local anchorX = math.floor(targetX + 0.5)
    local anchorY = math.floor(targetY + 0.5)
    if frame.cache.shown and frame.cache.posX ~= nil and frame.cache.posY ~= nil then
        if math.abs(frame.cache.posX - anchorX) < 1 and math.abs(frame.cache.posY - anchorY) < 1 then
            return
        end
    end
    if frame.cache.posX == anchorX and frame.cache.posY == anchorY and frame.cache.shown then
        return
    end
    frame.cache.posX = anchorX
    frame.cache.posY = anchorY
    Helpers.SafeAnchor(frame, "TOPLEFT", Bars.root_window or "UIParent", "TOPLEFT", anchorX, anchorY)
end

local function getClusterConfig(mode)
    local key = tostring(mode or "split")
    if key == "off" then
        return { threshold_x = 0.8, threshold_y = 0.8, x_step = 0, y_step = 0, split = false }
    end
    if key == "light" then
        return { threshold_x = 0.82, threshold_y = 0.9, x_step = 10, y_step = 14, split = false }
    end
    if key == "medium" then
        return { threshold_x = 0.88, threshold_y = 0.95, x_step = 12, y_step = 18, split = false }
    end
    if key == "strong" then
        return { threshold_x = 0.96, threshold_y = 1.05, x_step = 14, y_step = 24, split = false }
    end
    return { threshold_x = 0.84, threshold_y = 0.92, x_step = 12, y_step = 12, split = true }
end

local function getFrameHpPct(frame)
    if frame == nil or frame.cache == nil then
        return 1
    end
    return tonumber(frame.cache.hp_pct) or 1
end

local function getClusterPriority(entry, targetUnitId, hoveredUnit)
    local frame = entry.frame
    local unit = tostring(entry.unit or "")
    local score = 0
    if hoveredUnit ~= nil and unit == hoveredUnit then
        score = score + 1000
    end
    if targetUnitId ~= nil and tostring(frame.__ghb_unit_id or "") == tostring(targetUnitId) then
        score = score + 900
    end
    if unit == "target" then
        score = score + 800
    elseif unit == "watchtarget" then
        score = score + 700
    elseif unit == "player" then
        score = score + 650
    end
    local hpPct = getFrameHpPct(frame)
    score = score + math.floor((1 - hpPct) * 300)
    local ccCount = type(frame.cache.cc_effects) == "table" and #frame.cache.cc_effects or 0
    score = score + math.min(120, ccCount * 25)
    return score
end

local function sortClusterEntries(entries, targetUnitId, hoveredUnit)
    table.sort(entries, function(a, b)
        local aScore = getClusterPriority(a, targetUnitId, hoveredUnit)
        local bScore = getClusterPriority(b, targetUnitId, hoveredUnit)
        if aScore ~= bScore then
            return aScore > bScore
        end
        local aRank = tonumber(a.frame ~= nil and a.frame.cache ~= nil and a.frame.cache.cluster_rank or 0) or 0
        local bRank = tonumber(b.frame ~= nil and b.frame.cache ~= nil and b.frame.cache.cluster_rank or 0) or 0
        if aRank ~= bRank then
            return aRank < bRank
        end
        local aHp = getFrameHpPct(a.frame)
        local bHp = getFrameHpPct(b.frame)
        if aHp ~= bHp then
            return aHp < bHp
        end
        return tostring(a.unit or "") < tostring(b.unit or "")
    end)
end

local function overlapsCluster(a, b, config)
    local maxWidth = math.max(tonumber(a.width) or 0, tonumber(b.width) or 0)
    local maxHeight = math.max(tonumber(a.height) or 0, tonumber(b.height) or 0)
    local dx = math.abs((tonumber(a.raw_x) or 0) - (tonumber(b.raw_x) or 0))
    local dy = math.abs((tonumber(a.raw_y) or 0) - (tonumber(b.raw_y) or 0))
    return dx <= (maxWidth * (config.threshold_x or 0.85)) and dy <= (maxHeight * (config.threshold_y or 0.9))
end

local function buildClusters(entries, config)
    local clusters = {}
    local visited = {}
    for index, entry in ipairs(entries) do
        if not visited[index] then
            local queue = { index }
            visited[index] = true
            local cluster = {}
            local head = 1
            while head <= #queue do
                local currentIndex = queue[head]
                head = head + 1
                local current = entries[currentIndex]
                cluster[#cluster + 1] = current
                for otherIndex = 1, #entries do
                    if not visited[otherIndex] and overlapsCluster(current, entries[otherIndex], config) then
                        visited[otherIndex] = true
                        queue[#queue + 1] = otherIndex
                    end
                end
            end
            clusters[#clusters + 1] = cluster
        end
    end
    return clusters
end

local function applyClusterLayout(cluster, config, targetUnitId, hoveredUnit, clusterId)
    if #cluster == 0 then
        return
    end
    sortClusterEntries(cluster, targetUnitId, hoveredUnit)
    local hoveredInCluster = false
    for _, entry in ipairs(cluster) do
        if hoveredUnit ~= nil and tostring(entry.unit or "") == hoveredUnit then
            hoveredInCluster = true
            break
        end
    end
    local centerIndex = math.floor((#cluster + 1) / 2)
    for index, entry in ipairs(cluster) do
        local frame = entry.frame
        if frame ~= nil and frame.cache ~= nil then
            local xOffset = 0
            local yOffset = 0
            if config.split then
                if index == 1 then
                    xOffset = 0
                    yOffset = 0
                else
                    local side = ((index - 2) % 2 == 0) and -1 or 1
                    local ring = math.floor((index - 2) / 2) + 1
                    xOffset = side * config.x_step * ring
                    yOffset = config.y_step * ring
                end
            else
                local relative = index - centerIndex
                xOffset = relative * config.x_step
                yOffset = math.abs(relative) * config.y_step
            end
            placeFrame(frame, entry.cfg, entry.screen_x + xOffset, entry.screen_y + yOffset)
            frame.cache.cluster_id = clusterId
            frame.cache.cluster_rank = index
            frame.cache.shown = true
            frame.cache.hover_alpha_mult = 1
            if hoveredInCluster and hoveredUnit ~= nil and tostring(entry.unit or "") ~= hoveredUnit then
                frame.cache.hover_alpha_mult = HOVER_CLUSTER_DIM_ALPHA
            end
            applyTargetHighlight(frame, entry.is_current_target)
            showFrame(frame, entry.now_ms)
            applyFrameCompositeAlpha(frame)
        end
    end
end

local function updateOne(unit, context)
    unit = normalizeUnitToken(unit)
    if unit == nil then
        return
    end
    local settings = context.settings
    local cfg = context.cfg
    local playerForcedCcEffects = nil
    local forceShowPlayerCc = false
    if unit == "player" then
        playerForcedCcEffects = filterCcEffects(cfg, getPlayerVisibilityCcEffects(context.nowMs))
        forceShowPlayerCc = type(playerForcedCcEffects) == "table" and #playerForcedCcEffects > 0
    end
    if not (settings.enabled and (shouldShowUnit(unit, settings) or forceShowPlayerCc)) then
        if Bars.frames[unit] ~= nil and Bars.frames[unit].cache ~= nil then
            Bars.frames[unit].cache.data_active = false
        end
        setFrameDisplayEnabled(Bars.frames[unit], false)
        fadeOutFrame(Bars.frames[unit], context.nowMs)
        return
    end

    local unitId = type(context.unitIds) == "table" and context.unitIds[unit] or queryUnitId(unit)
    local renderOwner = type(context.renderOwners) == "table" and context.renderOwners[unit] or unit
    local frame = nil
    if unitId == nil then
        frame = Bars.frames[unit]
        if frame ~= nil and frame.cache ~= nil then
            frame.cache.data_active = false
        end
        setFrameDisplayEnabled(frame, false)
        fadeOutFrame(frame, context.nowMs)
        return
    end
    if renderOwner ~= nil and renderOwner ~= unit then
        frame = Bars.frames[unit]
        if frame ~= nil and frame.cache ~= nil then
            frame.cache.data_active = false
        end
        setFrameDisplayEnabled(frame, false)
        fadeOutFrame(frame, context.nowMs)
        return
    end
    frame = ensureFrame(unit)
    if frame == nil then
        return
    end

    local distance = getCachedDistance(frame, unit, context.nowMs)
    if shouldHideForDistance(frame, unit, distance, cfg, context.nowMs) then
        frame.cache.data_active = true
        setFrameDisplayEnabled(frame, false)
        fadeOutFrame(frame, context.nowMs)
        return
    end

    local hp, hpMax = readHealthValues(unit)
    if hp == nil or hpMax == nil then
        frame.cache.data_active = true
        setFrameDisplayEnabled(frame, false)
        fadeOutFrame(frame, context.nowMs)
        return
    end
    local mp, mpMax = readManaValues(unit)

    local isCurrentTarget = context.targetUnitId ~= nil and unitId == context.targetUnitId

    local static = getCachedUnitStatic(frame, unit, unitId, cfg.show_role, context.nowMs)
    local info = static ~= nil and static.info or nil
    local nameText = static ~= nil and tostring(static.name_text or "") or ""
    local showDistanceText = cfg.show_distance and unit ~= "player" and type(distance) == "number"
    if nameText == "" then
        frame.cache.data_active = true
        setFrameDisplayEnabled(frame, false)
        fadeOutFrame(frame, context.nowMs)
        return
    end
    nameText = trimText(nameText, cfg.name_max_chars)

    local guildText = static ~= nil and tostring(static.guild_text or "") or ""
    guildText = trimText(guildText, cfg.guild_max_chars)
    local displayGuildText = guildText ~= "" and ("<" .. guildText .. ">") or ""
    local layoutContent = {
        name_text = nameText,
        guild_text = displayGuildText
    }
    local fingerprint = Layout.StyleKey(cfg, layoutContent)
    if frame.cache.style ~= fingerprint then
        frame.cache.style = fingerprint
        Layout.Apply(frame, cfg, layoutContent)
    end
    local role = cfg.show_role and static ~= nil and static.role or nil

    updateCachedText(frame, "name", frame.nameLabel, nameText)
    updateCachedText(frame, "guild", frame.guildLabel, displayGuildText)
    updateCachedText(frame, "hpText", frame.hpValueLabel, Helpers.FormatValueText(cfg.value_mode, hp, hpMax))
    updateCachedText(frame, "mpText", frame.mpValueLabel, Helpers.FormatValueText(cfg.value_mode, mp, mpMax))
    updateCachedText(frame, "distText", frame.distanceLabel, showDistanceText and string.format("%.0fm", distance) or "")
    updateStatusBar(frame, "hp", frame.hpBar, hp, hpMax)
    updateStatusBar(frame, "mp", frame.mpBar, mp, mpMax)
    updateHpBarColor(frame, unit, unitId, cfg, info, hp, hpMax, context.nowMs)
    frame.cache.hp = hp
    frame.cache.hp_max = hpMax
    frame.cache.hp_pct = (hpMax ~= nil and hpMax > 0) and math.max(0, math.min(1, hp / hpMax)) or 1
    frame.__ghb_unit = unit
    frame.__ghb_unit_id = unitId
    setEventWindowInteraction(frame, canClickTargetUnit(unit, settings))
    Helpers.SafeShow(frame.nameLabel, cfg.show_name ~= false)
    Helpers.SafeShow(frame.guildLabel, cfg.show_guild and guildText ~= "")
    Helpers.SafeShow(frame.roleLabel, false)
    Helpers.SafeShow(frame.hpValueLabel, cfg.show_hp_text ~= false)
    Helpers.SafeShow(frame.mpValueLabel, cfg.show_mp_text and cfg.show_mp_bar and mpMax > 0)
    Helpers.SafeShow(frame.distanceLabel, showDistanceText)
    local showMpBar = cfg.show_mp_bar and clamp(cfg.mp_height, 0, 26, 5) > 0 and mpMax > 0
    Helpers.SafeShow(frame.mpBar, showMpBar)
    if Layout ~= nil and Layout.AnchorTargetGlow ~= nil and frame.cache.target_glow_mp ~= showMpBar then
        Layout.AnchorTargetGlow(frame, showMpBar)
        frame.cache.target_glow_mp = showMpBar
    end
    setBorderVisible(frame.targetGlow, isCurrentTarget, TARGET_GLOW_COLOR)
    setBorderVisible(frame.targetTint, isCurrentTarget, TARGET_TINT_COLOR)
    Role.Apply(frame, cfg, role)
    if shouldTrackCcUnit(unit, cfg) then
        local ccEffects = nil
        if unit == "player" and forceShowPlayerCc then
            ccEffects = playerForcedCcEffects
            frame.cache.cc_effects = ccEffects
            frame.cache.cc_last_scan_ms = context.nowMs
        else
            ccEffects = getCachedCcEffects(frame, unit)
        end
        updateCcWidgets(frame, cfg, ccEffects, unit == "player" and forceShowPlayerCc)
    else
        frame.cache.cc_effects = {}
        frame.cache.cc_last_scan_ms = 0
        hideCcWidgets(frame)
    end

    setFrameDisplayEnabled(frame, true)
    frame.cache.data_active = true
    if context.include_position ~= false then
        local positionSources = type(context.positionSources) == "table" and context.positionSources or Bars.position_sources
        local positionUnit = positionSources ~= nil and positionSources[unit] or unit
        local screenX, screenY, screenZ = resolveStableScreenPosition(frame, positionUnit, settings, context.nowMs, unit)
        if screenX == nil or screenY == nil or (screenZ ~= nil and screenZ < 0) then
            setFrameDisplayEnabled(frame, false)
            fadeOutFrame(frame, context.nowMs)
            return
        end
        placeFrame(frame, cfg, screenX, screenY)
        frame.cache.hover_alpha_mult = 1
        showFrame(frame, context.nowMs)
    elseif frame.cache.posX ~= nil and frame.cache.posY ~= nil then
        frame.cache.hover_alpha_mult = 1
        showFrame(frame, context.nowMs)
    else
        frame.cache.shown = false
    end
end

function Bars.Init()
    if Compat ~= nil then
        Compat.Probe(false)
    end
    ensureUnitKeys()
    Bars.layer_mode = currentLayerMode(Shared.EnsureSettings())
end

local function buildContext(settings, cfg, unitKeys)
    local unitIds = {}
    local nowMs = safeUiNowMs()
    local mapsDirty = false
    for _, unit in ipairs(unitKeys or {}) do
        local unitId = queryUnitId(unit)
        unitIds[unit] = unitId
        if Bars.unit_id_cache[unit] ~= unitId then
            mapsDirty = true
        end
        Bars.unit_id_cache[unit] = unitId
    end
    local lastBuildMs = tonumber(Bars.owner_source_last_build_ms) or 0
    if mapsDirty
        or not hasAnyEntries(Bars.render_owners)
        or not hasAnyEntries(Bars.position_sources)
        or (nowMs > 0 and (lastBuildMs <= 0 or (nowMs - lastBuildMs) >= OWNER_SOURCE_REBUILD_INTERVAL_MS)) then
        rebuildOwnerAndPositionMaps(nowMs)
    end
    local targetUnitId = unitIds.target or Bars.unit_id_cache.target or getCurrentTargetUnitId()
    return {
        settings = settings,
        cfg = cfg,
        targetUnitId = targetUnitId,
        nowMs = nowMs,
        include_position = true,
        unitIds = unitIds,
        renderOwners = Bars.render_owners,
        positionSources = Bars.position_sources
    }
end

local function updateUnits(unitKeys, context)
    for _, unit in ipairs(unitKeys) do
        updateOne(unit, context)
    end
end

local function appendList(dst, src)
    for _, value in ipairs(src or {}) do
        dst[#dst + 1] = value
    end
end

hasAnyEntries = function(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    for _ in pairs(tbl) do
        return true
    end
    return false
end

local function collectRoundRobinUnits(list, cursorKey, maxCount, seen)
    local out = {}
    local total = #list
    if total <= 0 or maxCount <= 0 then
        return out
    end
    local cursor = tonumber(Bars[cursorKey]) or 1
    if cursor < 1 or cursor > total then
        cursor = 1
    end
    local visited = 0
    while visited < total and #out < maxCount do
        local unit = list[cursor]
        if unit ~= nil and not seen[unit] then
            seen[unit] = true
            out[#out + 1] = unit
        end
        cursor = cursor + 1
        if cursor > total then
            cursor = 1
        end
        visited = visited + 1
    end
    Bars[cursorKey] = cursor
    return out
end

local function buildInactiveBulkUnitKeys()
    return buildLiveBulkUnitBuckets(false).inactive
end

local function buildShownActiveBulkUnitKeys()
    return buildLiveBulkUnitBuckets(true).shown
end

local function buildHiddenActiveBulkUnitKeys()
    return buildLiveBulkUnitBuckets(false).hidden
end

local function getVisibleBulkDataBatchSize(visibleCount)
    local count = tonumber(visibleCount) or 0
    if count <= 0 then
        return 0
    end
    return count
end

local function prepareUpdateState()
    if Compat ~= nil and not Compat.IsRenderable() then
        Bars.Reset()
        return nil, nil
    end
    local settings = Shared.EnsureSettings()
    syncLayerMode(settings)
    if not settings.enabled then
        Bars.Reset()
        return nil, nil
    end
    return settings, Shared.GetStyleSettings()
end

local function updatePositionsForUnits(unitKeys, settings, cfg, positionSources, renderOwners)
    local nowMs = safeUiNowMs()
    local targetUnitId = getCurrentTargetUnitId()
    local entries = {}
    for _, unit in ipairs(unitKeys or {}) do
        local frame = Bars.frames[unit]
        if frame ~= nil and frame.cache ~= nil then
            local renderOwner = type(renderOwners) == "table" and renderOwners[unit] or unit
            if renderOwner ~= nil and renderOwner ~= unit then
                setFrameDisplayEnabled(frame, false)
                setEventWindowInteraction(frame, false)
                applyTargetHighlight(frame, false)
                fadeOutFrame(frame, nowMs)
            elseif frame.cache.display_enabled ~= true then
                setEventWindowInteraction(frame, false)
                applyTargetHighlight(frame, false)
                if frame.cache.shown and tonumber(frame.cache.fade_target_alpha) == 0 then
                    fadeOutFrame(frame, nowMs)
                end
            elseif frame.cache.data_active then
                setEventWindowInteraction(frame, canClickTargetUnit(unit, settings))
                local positionUnit = type(positionSources) == "table" and positionSources[unit] or unit
                local screenX, screenY, screenZ = resolveStableScreenPosition(frame, positionUnit, settings, nowMs, unit)
                if screenX == nil or screenY == nil or (screenZ ~= nil and screenZ < 0) then
                    fadeOutFrame(frame, nowMs)
                else
                    entries[#entries + 1] = {
                        unit = unit,
                        frame = frame,
                        cfg = cfg,
                        screen_x = tonumber(screenX) or 0,
                        screen_y = tonumber(screenY) or 0,
                        raw_x = tonumber(screenX) or 0,
                        raw_y = tonumber(screenY) or 0,
                        is_current_target = tostring(frame.__ghb_unit_id or "") == tostring(targetUnitId or ""),
                        width = tonumber(frame.cache.frame_width) or clamp(cfg.width, 80, 320, 156),
                        height = tonumber(frame.cache.frame_height) or 48,
                        now_ms = nowMs
                    }
                end
            end
        end
    end

    local clusterConfig = getClusterConfig(cfg.cluster_spacing_mode)
    if tostring(cfg.cluster_spacing_mode or "split") == "off" then
        for _, entry in ipairs(entries) do
            local frame = entry.frame
            frame.cache.cluster_id = tostring(entry.unit or "")
            frame.cache.hover_alpha_mult = 1
            placeFrame(frame, entry.cfg, entry.screen_x, entry.screen_y)
            applyTargetHighlight(frame, entry.is_current_target)
            showFrame(frame, entry.now_ms)
            applyFrameCompositeAlpha(frame)
        end
        return
    end

    local clusters = buildClusters(entries, clusterConfig)
    for clusterIndex, cluster in ipairs(clusters) do
        applyClusterLayout(cluster, clusterConfig, targetUnitId, Bars.hovered_unit, tostring(clusterIndex))
    end
end

local function shouldUseUnifiedClusterPass(cfg)
    return tostring(type(cfg) == "table" and cfg.cluster_spacing_mode or "off") ~= "off"
end

local function updateVisiblePositions(settings, cfg, forceBulk)
    local units = {}
    local seen = {}
    for _, unit in ipairs(Bars.hot_unit_keys or {}) do
        if not seen[unit] then
            seen[unit] = true
            units[#units + 1] = unit
        end
    end
    local shownBulkUnits = buildShownActiveBulkUnitKeys()
    local includeBulk = (#shownBulkUnits > 0)
    if includeBulk then
        Bars.last_visible_bulk_position_ms = safeUiNowMs()
        for _, unit in ipairs(shownBulkUnits) do
            if not seen[unit] then
                seen[unit] = true
                units[#units + 1] = unit
            end
        end
    end
    updatePositionsForUnits(units, settings, cfg, Bars.position_sources, Bars.render_owners)
end

local function updateDiscoveryPositions(settings, cfg)
    -- Hidden/offscreen bulk units stay on a colder round-robin lane so they do not
    -- fight the movement cadence of bars that are already visible.
    local units = {}
    local seen = {}
    appendList(units, collectRoundRobinUnits(buildHiddenActiveBulkUnitKeys(), "discovery_position_active_cursor", DISCOVERY_POSITION_ACTIVE_BATCH_SIZE, seen))
    appendList(units, collectRoundRobinUnits(buildInactiveBulkUnitKeys(), "discovery_position_cold_cursor", DISCOVERY_POSITION_COLD_BATCH_SIZE, seen))
    updatePositionsForUnits(units, settings, cfg, Bars.position_sources, Bars.render_owners)
end

local function updateFocusData(settings, cfg)
    local units = {}
    local seen = {}
    for _, unit in ipairs(Bars.hot_unit_keys or {}) do
        if not seen[unit] then
            seen[unit] = true
            units[#units + 1] = unit
        end
    end
    local context = buildContext(settings, cfg, units)
    context.include_position = false
    updateUnits(units, context)
end

local function updateVisibleBulkData(settings, cfg)
    local shownBulkUnits = buildShownActiveBulkUnitKeys()
    local batchSize = getVisibleBulkDataBatchSize(#shownBulkUnits)
    if batchSize <= 0 then
        return
    end
    local visibleSeen = {}
    local units = collectRoundRobinUnits(shownBulkUnits, "visible_bulk_cursor", batchSize, visibleSeen)
    if #units <= 0 then
        return
    end
    local context = buildContext(settings, cfg, units)
    context.include_position = false
    updateUnits(units, context)
end

local function invalidateFrameUnitCache(frame)
    if frame == nil or frame.cache == nil then
        return
    end
    frame.cache.distance_next_refresh_ms = 0
    frame.cache.bloodlust_next_scan_ms = 0
end

function Bars.InvalidateUnitCaches()
    Bars.unit_id_cache = {}
    Bars.render_owners = {}
    Bars.position_sources = {}
    Bars.active_bulk_unit_keys = {}
    Bars.owner_source_last_build_ms = 0
    for _, frame in pairs(Bars.frames or {}) do
        invalidateFrameUnitCache(frame)
    end
end

function Bars.UpdateFocusData()
    local settings, cfg = prepareUpdateState()
    if settings == nil then
        return
    end
    updateFocusData(settings, cfg)
end

function Bars.UpdateVisibleData()
    local settings, cfg = prepareUpdateState()
    if settings == nil then
        return
    end
    updateVisibleBulkData(settings, cfg)
end

local function updateCombinedVisibleData(settings, cfg)
    updateFocusData(settings, cfg)
    updateVisibleBulkData(settings, cfg)
end

function Bars.Update()
    local settings, cfg = prepareUpdateState()
    if settings == nil then
        return
    end
    local context = buildContext(settings, cfg, Bars.unit_keys)
    context.include_position = false
    updateUnits(Bars.unit_keys, context)
    updatePositionsForUnits(Bars.unit_keys, settings, cfg, context.positionSources, context.renderOwners)
    rebuildActiveBulkUnitKeys()
end

function Bars.UpdateHotData()
    local settings, cfg = prepareUpdateState()
    if settings == nil then
        return
    end
    updateCombinedVisibleData(settings, cfg)
end

function Bars.UpdateBulkData()
    local settings, cfg = prepareUpdateState()
    if settings == nil then
        return
    end
    local units = {}
    local seen = {}
    appendList(units, collectRoundRobinUnits(buildHiddenActiveBulkUnitKeys(), "bulk_active_cursor", BULK_ACTIVE_DATA_BATCH_SIZE, seen))
    local inactiveKeys = buildInactiveBulkUnitKeys()
    local coldBatchSize = (#Bars.active_bulk_unit_keys > 0) and BULK_COLD_DATA_BATCH_SIZE or BULK_DISCOVERY_BATCH_SIZE
    appendList(units, collectRoundRobinUnits(inactiveKeys, "bulk_cold_cursor", coldBatchSize, seen))
    local context = buildContext(settings, cfg, units)
    context.include_position = false
    updateUnits(units, context)
    rebuildActiveBulkUnitKeys()
end

Bars.UpdateData = Bars.Update

function Bars.UpdateHotPositions()
    local settings, cfg = prepareUpdateState()
    if settings == nil then
        return
    end
    updateVisiblePositions(settings, cfg)
end

function Bars.UpdateVisiblePositions()
    local settings, cfg = prepareUpdateState()
    if settings == nil then
        return
    end
    updateVisiblePositions(settings, cfg)
end

function Bars.UpdateBulkPositions()
    local settings, cfg = prepareUpdateState()
    if settings == nil then
        return
    end
    if shouldUseUnifiedClusterPass(cfg) then
        return
    end
    updateDiscoveryPositions(settings, cfg)
end

function Bars.GetBulkPositionIntervalMs()
    return getBulkPositionIntervalMs()
end

function Bars.UpdatePositions()
    local settings, cfg = prepareUpdateState()
    if settings == nil then
        return
    end
    if shouldUseUnifiedClusterPass(cfg) then
        updateVisiblePositions(settings, cfg, true)
        return
    end
    updateVisiblePositions(settings, cfg, true)
    updateDiscoveryPositions(settings, cfg)
end

function Bars.Reset()
    Bars.active_bulk_unit_keys = {}
    Bars.unit_id_cache = {}
    Bars.render_owners = {}
    Bars.position_sources = {}
    Bars.bulk_active_cursor = 1
    Bars.bulk_cold_cursor = 1
    Bars.visible_bulk_cursor = 1
    Bars.discovery_position_active_cursor = 1
    Bars.discovery_position_cold_cursor = 1
    Bars.hovered_unit = nil
    Bars.owner_source_last_build_ms = 0
    Bars.last_visible_bulk_position_ms = 0
    for _, frame in pairs(Bars.frames) do
        hideFrame(frame)
    end
    if Bars.root_window ~= nil then
        Helpers.SafeShow(Bars.root_window, true)
    end
end

function Bars.Unload()
    for _, frame in pairs(Bars.frames) do
        Helpers.SafeShow(frame, false)
        if frame ~= nil and frame.__ghb_top_level == true and api.Interface ~= nil and api.Interface.Free ~= nil then
            pcall(function()
                api.Interface:Free(frame)
            end)
        end
    end
    if Bars.root_window ~= nil and api.Interface ~= nil and api.Interface.Free ~= nil then
        pcall(function()
            api.Interface:Free(Bars.root_window)
        end)
    end
    Bars.frames = {}
    Bars.root_window = nil
    Bars.unit_keys = {}
    Bars.hot_unit_keys = {}
    Bars.bulk_unit_keys = {}
    Bars.active_bulk_unit_keys = {}
    Bars.unit_id_cache = {}
    Bars.render_owners = {}
    Bars.position_sources = {}
    Bars.bulk_active_cursor = 1
    Bars.bulk_cold_cursor = 1
    Bars.visible_bulk_cursor = 1
    Bars.discovery_position_active_cursor = 1
    Bars.discovery_position_cold_cursor = 1
    Bars.hovered_unit = nil
    Bars.owner_source_last_build_ms = 0
    Bars.last_visible_bulk_position_ms = 0
    Bars.target_unitframe = nil
    Bars.watchtarget_unitframe = nil
    Bars.targetoftarget_unitframe = nil
end

return Bars
