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
    unit_keys = {},
    target_unitframe = nil,
    watchtarget_unitframe = nil,
    targetoftarget_unitframe = nil,
    layer_mode = nil
}

local applyLayerToFrame
local setBorderVisible
local changeTarget
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
local CC_SCAN_INTERVAL_MS = 250
local CC_EXTRA_ICON_COUNT = 3
local UNIT_STATIC_REFRESH_MS = 2000
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
    local ok, value = pcall(function()
        return api.Time:GetUiMsec()
    end)
    if not ok then
        return 0
    end
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
    pcall(function()
        if label.SetExtent ~= nil then
            label:SetExtent(56, (tonumber(fontSize) or 11) + 6)
        end
        if label.style ~= nil and label.style.SetFontSize ~= nil then
            label.style:SetFontSize(fontSize)
        end
    end)
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

local function shouldTrackCcUnit(unit)
    return unit == "player" or unit == "target" or unit == "watchtarget"
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

local function getCurrentTargetUnitId()
    if api == nil or api.Unit == nil or api.Unit.GetUnitId == nil then
        return nil
    end
    local unitId = nil
    pcall(function()
        unitId = api.Unit:GetUnitId("target")
    end)
    return normalizeUnitId(unitId)
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
    local key = tostring(unit or "")
    if key == "" then
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

local function getUnitInfo(unit, unitId)
    local normalizedId = normalizeUnitId(unitId)
    local info = nil
    if normalizedId ~= nil then
        pcall(function()
            info = api.Unit:GetUnitInfoById(normalizedId)
        end)
    end
    if type(info) ~= "table" and api.Unit.UnitInfo ~= nil then
        pcall(function()
            info = api.Unit:UnitInfo(unit)
        end)
    end
    if type(info) ~= "table" then
        return nil
    end
    return info
end

local function getUnitName(unitId, info)
    local normalizedId = normalizeUnitId(unitId)
    local nameText = ""
    if normalizedId ~= nil then
        pcall(function()
            nameText = api.Unit:GetUnitNameById(normalizedId) or ""
        end)
    end
    if nameText == "" and type(info) == "table" then
        nameText = tostring(info.name or info.unitName or "")
    end
    return nameText
end

local function getCachedUnitStatic(frame, unit, unitId, includeRole, nowMs)
    if frame == nil or frame.cache == nil or unitId == nil then
        return nil
    end
    local cached = frame.cache.unit_static
    local refreshNeeded = true
    if type(cached) == "table" and cached.unit_id == unitId then
        refreshNeeded = false
        local last = tonumber(cached.last_refresh_ms) or 0
        if nowMs > 0 and last > 0 and (nowMs - last) >= UNIT_STATIC_REFRESH_MS then
            refreshNeeded = true
        end
        if includeRole and cached.role == nil then
            refreshNeeded = true
        end
    end
    if not refreshNeeded then
        return cached
    end

    local info = getUnitInfo(unit, unitId)
    local role = nil
    local className = nil
    if includeRole then
        role, className = Role.GetRoleForUnit(unit)
    end

    cached = {
        unit_id = unitId,
        last_refresh_ms = nowMs,
        info = info,
        name_text = getUnitName(unitId, info),
        guild_text = type(info) == "table" and tostring(info.expeditionName or "") or "",
        role = role,
        class_name = className
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
    pcall(function()
        if frame.ccPrimary.SetExtent ~= nil then
            frame.ccPrimary:SetExtent(iconSize, iconSize)
        end
    end)
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
        if entry.icon ~= nil and entry.icon.SetExtent ~= nil then
            pcall(function()
                entry.icon:SetExtent(secondarySize, secondarySize)
            end)
        end
        setCcTimerStyle(entry.timer, secondaryTimerFont)
        Helpers.SafeAnchor(entry.timer, "CENTER", entry.icon, "CENTER", 0, 0)
        if anchor == "right" or anchor == "top" then
            Helpers.SafeAnchor(entry.icon, "LEFT", previous, "RIGHT", gap, 0)
        else
            Helpers.SafeAnchor(entry.icon, "RIGHT", previous, "LEFT", -gap, 0)
        end
        previous = entry.icon
    end
end

local function updateCcWidgets(frame, cfg, effects, forceShow)
    if frame == nil or frame.ccPrimary == nil then
        return
    end
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
    table.insert(Bars.unit_keys, "target")
    table.insert(Bars.unit_keys, "player")
    for i = 1, 50 do
        table.insert(Bars.unit_keys, string.format("team%d", i))
    end
    table.insert(Bars.unit_keys, "watchtarget")
    table.insert(Bars.unit_keys, "playerpet1")
end

local function ensureFrame(unit)
    if Bars.frames[unit] ~= nil then
        return Bars.frames[unit]
    end
    local frameId = "gharkaBars_" .. tostring(unit)
    local frame = api.Interface:CreateEmptyWindow(frameId)
    pcall(function()
        if frame.SetUILayer ~= nil and Bars.layer_mode ~= nil and Bars.layer_mode ~= "default" then
            frame:SetUILayer(Bars.layer_mode)
        end
    end)
    Helpers.SafeClickable(frame, false)
    Helpers.SafeShow(frame, false)

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
        eventWindow:Show(true)
        if eventWindow.EnablePick ~= nil then
            eventWindow:EnablePick(true)
        end
    end)
    Helpers.SafeClickable(eventWindow, true)
    if eventWindow ~= nil and eventWindow.SetHandler ~= nil then
        eventWindow:SetHandler("OnClick", function(_, button)
            if button == "RightButton" or button == "MiddleButton" then
                return
            end
            if frame.__ghb_click_target ~= true then
                return
            end
            changeTarget(frame.__ghb_unit or unit, frame.__ghb_unit_id)
        end)
    end
    frame.eventWindow = eventWindow
    frame.__ghb_unit = unit
    frame.__ghb_unit_id = nil
    frame.__ghb_click_target = true
    frame.cache = {}
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
    if Bars.layer_mode == nil or Bars.layer_mode == "default" then
        return
    end
    pcall(function()
        widget:SetUILayer(Bars.layer_mode)
    end)
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
    local unitCandidates = getTargetUnitCandidates(unit)
    local targetInfo = getUnitInfo(unit, desiredUnitId)
    local targetName = getUnitName(desiredUnitId, targetInfo)
    logTargetDebug(string.format("Click target request unit=%s unitId=%s current=%s", tostring(unit), tostring(desiredUnitId), tostring(beforeTargetId)))

    if type(TargetUnit) == "function" then
        for _, candidate in ipairs(unitCandidates) do
            if tryTargetCall("TargetUnit(" .. tostring(candidate) .. ")", function()
                TargetUnit(candidate)
            end, beforeTargetId, desiredUnitId) then
                return
            end
        end
        if unitId ~= nil then
            if tryTargetCall("TargetUnit(unitId)", function()
                TargetUnit(unitId)
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
        if unitId ~= nil then
            if tryTargetCall("api.Unit.TargetUnit(unitId)", function()
                api.Unit.TargetUnit(unitId)
            end, beforeTargetId, desiredUnitId) then
                return
            end
            if tryTargetCall("api.Unit:TargetUnit(unitId)", function()
                api.Unit:TargetUnit(unitId)
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

    local tu, stockUnit = getStockFrameForUnit(unit)
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
    local buffCount = 0
    pcall(function()
        buffCount = api.Unit:UnitBuffCount(unit) or 0
    end)
    for index = 1, tonumber(buffCount) or 0 do
        local buff = nil
        pcall(function()
            buff = api.Unit:UnitBuff(unit, index)
        end)
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
    local result = false
    pcall(function()
        result = api.Unit:UnitIsTeamMember(unit) and true or false
    end)
    return result
end

local function isBloodlustFriendlyUnit(unit, info)
    local faction = type(info) == "table" and tostring(info.faction or "") or ""
    if faction == "hostile" or faction == "neutral" then
        return false
    end
    return unitHasBuff(unit, BLOODLUST_BUFF_ID)
end

local function getBarRelation(unit, info)
    local faction = type(info) == "table" and tostring(info.faction or "") or ""
    if isBloodlustFriendlyUnit(unit, info) then
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

local function getHpBarAppearance(unit, cfg, info)
    local relation = getBarRelation(unit, info)
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
    return relation, Helpers.Color01(cfg.hp_bar_color, { 220, 46, 46, 255 }), nil
end

local function updateHpBarColor(frame, unit, cfg, info)
    if frame == nil or frame.hpBar == nil or frame.hpBar.statusBar == nil then
        return
    end
    local relation, rgba, textColor = getHpBarAppearance(unit, cfg, info)
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
    if frame.cache ~= nil then
        frame.cache.active = false
        frame.cache.shown = false
    end
    Role.Hide(frame)
    setBorderVisible(frame.targetGlow, false, TARGET_GLOW_COLOR)
    setBorderVisible(frame.targetTint, false, TARGET_TINT_COLOR)
    hideCcWidgets(frame)
    Helpers.SafeShow(frame, false)
end

local function getScreenPosition(unit, settings)
    unit = normalizeUnitToken(unit)
    if unit == nil then
        return nil, nil, nil
    end
    local screenX, screenY, screenZ = nil, nil, nil
    if settings.anchor_to_nametag and api.Unit.GetUnitScreenNameTagOffset ~= nil then
        pcall(function()
            screenX, screenY, screenZ = api.Unit:GetUnitScreenNameTagOffset(unit)
        end)
    end
    if screenX == nil or screenY == nil then
        pcall(function()
            screenX, screenY, screenZ = api.Unit:GetUnitScreenPosition(unit)
        end)
    end
    return screenX, screenY, screenZ
end

local function placeFrame(frame, cfg, screenX, screenY)
    local width = tonumber(frame.cache.frame_width) or clamp(cfg.width, 80, 320, 156)
    local posX = math.ceil(screenX) + clamp(cfg.x_offset, -500, 500, 0) - math.floor(width / 2)
    local posY = math.ceil(screenY) - clamp(cfg.y_offset, -200, 200, 24)
    if frame.cache.shown and frame.cache.posX ~= nil and frame.cache.posY ~= nil then
        if math.abs(frame.cache.posX - posX) <= 1 and math.abs(frame.cache.posY - posY) <= 1 then
            return
        end
    end
    if frame.cache.posX == posX and frame.cache.posY == posY and frame.cache.shown then
        return
    end
    frame.cache.posX = posX
    frame.cache.posY = posY
    Helpers.SafeAnchor(frame, "TOPLEFT", "UIParent", "TOPLEFT", posX, posY)
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
        playerForcedCcEffects = getPlayerVisibilityCcEffects(context.nowMs)
        forceShowPlayerCc = type(playerForcedCcEffects) == "table" and #playerForcedCcEffects > 0
    end
    if not (settings.enabled and (shouldShowUnit(unit, settings) or forceShowPlayerCc)) then
        hideFrame(Bars.frames[unit])
        return
    end

    local frame = ensureFrame(unit)
    applyLayerToFrame(frame)
    local unitId = nil
    pcall(function()
        unitId = api.Unit:GetUnitId(unit)
    end)
    unitId = normalizeUnitId(unitId)
    if unitId == nil then
        hideFrame(frame)
        return
    end

    local screenX, screenY, screenZ = getScreenPosition(unit, settings)
    if screenX == nil or screenY == nil or (screenZ ~= nil and screenZ < 0) then
        hideFrame(frame)
        return
    end

    local distance = nil
    if api.Unit.UnitDistance ~= nil then
        pcall(function()
            distance = api.Unit:UnitDistance(unit)
        end)
    end
    if type(distance) == "number" and distance > clamp(cfg.max_distance, 10, 300, 130) then
        hideFrame(frame)
        return
    end

    local hp = 0
    local hpMax = 0
    local mp = 0
    local mpMax = 0
    pcall(function()
        hp = api.Unit:UnitHealth(unit) or 0
        hpMax = api.Unit:UnitMaxHealth(unit) or 0
        mp = api.Unit:UnitMana(unit) or 0
        mpMax = api.Unit:UnitMaxMana(unit) or 0
    end)

    local isCurrentTarget = context.targetUnitId ~= nil and unitId == context.targetUnitId

    local static = getCachedUnitStatic(frame, unit, unitId, cfg.show_role, context.nowMs)
    local info = static ~= nil and static.info or nil
    local nameText = static ~= nil and tostring(static.name_text or "") or ""
    if nameText == "" then
        hideFrame(frame)
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
    local role = (cfg.show_role and static ~= nil and static.role) or "dps"

    updateCachedText(frame, "name", frame.nameLabel, nameText)
    updateCachedText(frame, "guild", frame.guildLabel, displayGuildText)
    updateCachedText(frame, "hpText", frame.hpValueLabel, Helpers.FormatValueText(cfg.value_mode, hp, hpMax))
    updateCachedText(frame, "mpText", frame.mpValueLabel, Helpers.FormatValueText(cfg.value_mode, mp, mpMax))
    updateCachedText(frame, "distText", frame.distanceLabel, cfg.show_distance and type(distance) == "number" and string.format("%.0fm", distance) or "")
    updateStatusBar(frame, "hp", frame.hpBar, hp, hpMax)
    updateStatusBar(frame, "mp", frame.mpBar, mp, mpMax)
    updateHpBarColor(frame, unit, cfg, info)
    frame.__ghb_unit = unit
    frame.__ghb_unit_id = unitId
    frame.__ghb_click_target = settings.click_target and true or false
    Helpers.SafeClickable(frame.eventWindow, frame.__ghb_click_target)
    Helpers.SafeShow(frame.eventWindow, frame.__ghb_click_target)
    Helpers.SafeShow(frame.nameLabel, cfg.show_name ~= false)
    Helpers.SafeShow(frame.guildLabel, cfg.show_guild and guildText ~= "")
    Helpers.SafeShow(frame.roleLabel, false)
    Helpers.SafeShow(frame.hpValueLabel, cfg.show_hp_text ~= false)
    Helpers.SafeShow(frame.mpValueLabel, cfg.show_mp_text and cfg.show_mp_bar and mpMax > 0)
    Helpers.SafeShow(frame.distanceLabel, cfg.show_distance and type(distance) == "number")
    Helpers.SafeShow(frame.mpBar, cfg.show_mp_bar and clamp(cfg.mp_height, 0, 26, 5) > 0 and mpMax > 0)
    if Layout ~= nil and Layout.AnchorTargetGlow ~= nil then
        Layout.AnchorTargetGlow(frame, cfg.show_mp_bar and clamp(cfg.mp_height, 0, 26, 5) > 0 and mpMax > 0)
    end
    setBorderVisible(frame.targetGlow, isCurrentTarget, TARGET_GLOW_COLOR)
    setBorderVisible(frame.targetTint, isCurrentTarget, TARGET_TINT_COLOR)
    Role.Apply(frame, cfg, role)
    if shouldTrackCcUnit(unit) then
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

    placeFrame(frame, cfg, screenX, screenY)
    frame.cache.active = true
    frame.cache.shown = true
    Helpers.SafeShow(frame, true)
end

function Bars.Init()
    if Compat ~= nil then
        Compat.Probe(false)
    end
    ensureUnitKeys()
    Bars.layer_mode = currentLayerMode(Shared.EnsureSettings())
    Bars.target_unitframe = getStockTargetFrame()
    Bars.watchtarget_unitframe = getStockWatchtargetFrame()
    Bars.targetoftarget_unitframe = getStockTargetOfTargetFrame()
end

function Bars.Update()
    if Compat ~= nil and not Compat.IsRenderable() then
        Bars.Reset()
        return
    end
    local settings = Shared.EnsureSettings()
    syncLayerMode(settings)
    if Bars.target_unitframe == nil then
        Bars.target_unitframe = getStockTargetFrame()
    end
    if Bars.watchtarget_unitframe == nil then
        Bars.watchtarget_unitframe = getStockWatchtargetFrame()
    end
    if Bars.targetoftarget_unitframe == nil then
        Bars.targetoftarget_unitframe = getStockTargetOfTargetFrame()
    end
    local cfg = Shared.GetStyleSettings()
    local targetUnitId = nil
    pcall(function()
        targetUnitId = api.Unit:GetUnitId("target")
    end)
    local context = {
        settings = settings,
        cfg = cfg,
        targetUnitId = targetUnitId,
        nowMs = safeUiNowMs()
    }
    for _, unit in ipairs(Bars.unit_keys) do
        updateOne(unit, context)
    end
end
Bars.UpdateData = Bars.Update
function Bars.UpdatePositions()
    local settings = Shared.EnsureSettings()
    if Compat ~= nil and not Compat.IsRenderable() then
        Bars.Reset()
        return
    end
    syncLayerMode(settings)
    if not settings.enabled then
        Bars.Reset()
        return
    end
    local cfg = Shared.GetStyleSettings()
    for _, unit in ipairs(Bars.unit_keys) do
        local frame = Bars.frames[unit]
        if frame ~= nil and frame.cache ~= nil and frame.cache.active then
            local screenX, screenY, screenZ = getScreenPosition(unit, settings)
            if screenX == nil or screenY == nil or (screenZ ~= nil and screenZ < 0) then
                hideFrame(frame)
            else
                placeFrame(frame, cfg, screenX, screenY)
                frame.cache.shown = true
                Helpers.SafeShow(frame, true)
            end
        end
    end
end

function Bars.Reset()
    for _, frame in pairs(Bars.frames) do
        hideFrame(frame)
    end
end

function Bars.Unload()
    for _, frame in pairs(Bars.frames) do
        Helpers.SafeShow(frame, false)
        if api.Interface ~= nil and api.Interface.Free ~= nil then
            pcall(function()
                api.Interface:Free(frame)
            end)
        end
    end
    Bars.frames = {}
    Bars.unit_keys = {}
    Bars.target_unitframe = nil
end

return Bars
