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

local Bars = {
    frames = {},
    unit_keys = {},
    target_unitframe = nil,
    layer_mode = nil
}

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
local BLOODLUST_BUFF_ID = 1482
local HOSTILE_TEXT_COLOR = { 255, 244, 244, 255 }
local NEUTRAL_TEXT_COLOR = { 40, 28, 0, 255 }

local function clamp(v, lo, hi, default)
    return Shared.Clamp(v, lo, hi, default)
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

local function setBorderVisible(border, enabled, rgba255)
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
    local eventWindow = api.Interface:CreateWidget("emptywidget", frameId .. ".event", frame)
    pcall(function()
        eventWindow:AddAnchor("TOPLEFT", frame, 0, 0)
        eventWindow:AddAnchor("BOTTOMRIGHT", frame, 0, 0)
        eventWindow:Show(false)
        eventWindow:EnableDrag(false)
    end)
    Helpers.SafeClickable(eventWindow, false)
    frame.eventWindow = eventWindow
    frame.cache = {}
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

local function syncLayerMode(settings)
    local mode = currentLayerMode(settings)
    if Bars.layer_mode == mode then
        return
    end
    if next(Bars.frames) ~= nil then
        Bars.Unload()
    end
    Bars.layer_mode = mode
    ensureUnitKeys()
    if ADDON ~= nil and ADDON.GetContent ~= nil and UIC ~= nil then
        pcall(function()
            Bars.target_unitframe = ADDON:GetContent(UIC.TARGET_UNITFRAME)
        end)
    end
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
    local forced = false
    if api.Unit ~= nil and api.Unit.UnitIsForceAttack ~= nil then
        pcall(function()
            forced = api.Unit:UnitIsForceAttack(unit) and true or false
        end)
    end
    return forced or unitHasBuff(unit, BLOODLUST_BUFF_ID)
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
    Helpers.SafeShow(frame, false)
end

local function getScreenPosition(unit, settings)
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

local function updateOne(unit)
    local settings = Shared.EnsureSettings()
    syncLayerMode(settings)
    if not (settings.enabled and shouldShowUnit(unit, settings)) then
        hideFrame(Bars.frames[unit])
        return
    end

    local frame = ensureFrame(unit)
    local unitId = nil
    pcall(function()
        unitId = api.Unit:GetUnitId(unit)
    end)
    if unitId == nil then
        hideFrame(frame)
        return
    end

    local screenX, screenY, screenZ = getScreenPosition(unit, settings)
    if screenX == nil or screenY == nil or (screenZ ~= nil and screenZ < 0) then
        hideFrame(frame)
        return
    end

    local cfg = Shared.GetStyleSettings()
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

    local info = nil
    pcall(function()
        info = api.Unit:GetUnitInfoById(unitId)
    end)
    if type(info) ~= "table" and api.Unit.UnitInfo ~= nil then
        pcall(function()
            info = api.Unit:UnitInfo(unit)
        end)
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

    local targetUnitId = nil
    pcall(function()
        targetUnitId = api.Unit:GetUnitId("target")
    end)
    local isCurrentTarget = targetUnitId ~= nil and unitId == targetUnitId

    local nameText = ""
    pcall(function()
        nameText = api.Unit:GetUnitNameById(unitId) or ""
    end)
    if nameText == "" and type(info) == "table" then
        nameText = tostring(info.name or info.unitName or "")
    end
    if nameText == "" then
        hideFrame(frame)
        return
    end
    nameText = trimText(nameText, cfg.name_max_chars)

    local guildText = ""
    if cfg.show_guild and type(info) == "table" then
        guildText = tostring(info.expeditionName or "")
    end
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
    local role = "dps"
    if cfg.show_role then
        role = Role.GetRoleForUnit(unit)
    end

    updateCachedText(frame, "name", frame.nameLabel, nameText)
    updateCachedText(frame, "guild", frame.guildLabel, displayGuildText)
    updateCachedText(frame, "hpText", frame.hpValueLabel, Helpers.FormatValueText(cfg.value_mode, hp, hpMax))
    updateCachedText(frame, "mpText", frame.mpValueLabel, Helpers.FormatValueText(cfg.value_mode, mp, mpMax))
    updateCachedText(frame, "distText", frame.distanceLabel, cfg.show_distance and type(distance) == "number" and string.format("%.0fm", distance) or "")
    updateStatusBar(frame, "hp", frame.hpBar, hp, hpMax)
    updateStatusBar(frame, "mp", frame.mpBar, mp, mpMax)
    updateHpBarColor(frame, unit, cfg, info)
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
    if ADDON ~= nil and ADDON.GetContent ~= nil and UIC ~= nil then
        pcall(function()
            Bars.target_unitframe = ADDON:GetContent(UIC.TARGET_UNITFRAME)
        end)
    end
end

function Bars.Update()
    if Compat ~= nil and not Compat.IsRenderable() then
        Bars.Reset()
        return
    end
    syncLayerMode(Shared.EnsureSettings())
    for _, unit in ipairs(Bars.unit_keys) do
        updateOne(unit)
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
