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

local Layout = {}

local function clamp(v, lo, hi, default)
    return Shared.Clamp(v, lo, hi, default)
end

local function colorKey(color)
    if type(color) ~= "table" then
        return ""
    end
    return table.concat({
        tostring(color[1] or ""),
        tostring(color[2] or ""),
        tostring(color[3] or ""),
        tostring(color[4] or "")
    }, ",")
end

function Layout.StyleKey(cfg, content)
    content = type(content) == "table" and content or {}
    return table.concat({
        tostring(cfg.width), tostring(cfg.hp_height), tostring(cfg.mp_height), tostring(cfg.bar_gap),
        tostring(cfg.alpha_pct), tostring(cfg.bg_alpha_pct), tostring(cfg.max_distance),
        tostring(cfg.name_font_size), tostring(cfg.guild_font_size), tostring(cfg.role_font_size),
        tostring(cfg.value_font_size), tostring(cfg.distance_font_size), tostring(cfg.value_mode),
        tostring(cfg.name_layout), tostring(cfg.cluster_spacing_mode), tostring(cfg.x_offset), tostring(cfg.y_offset),
        tostring(cfg.name_offset_x), tostring(cfg.name_offset_y), tostring(cfg.guild_offset_x),
        tostring(cfg.guild_offset_y), tostring(cfg.role_offset_x), tostring(cfg.role_offset_y),
        tostring(cfg.value_offset_x), tostring(cfg.value_offset_y),
        tostring(cfg.distance_offset_x), tostring(cfg.distance_offset_y), tostring(cfg.show_name),
        tostring(cfg.show_guild), tostring(cfg.show_role), tostring(cfg.show_hp_text),
        tostring(cfg.show_mp_text), tostring(cfg.show_mp_bar), tostring(cfg.show_distance),
        tostring(cfg.show_background), colorKey(cfg.hp_bar_color), colorKey(cfg.mp_bar_color),
        colorKey(cfg.name_color), colorKey(cfg.guild_color), colorKey(cfg.value_color),
        colorKey(cfg.distance_color),
        tostring(content.name_text or ""),
        tostring(content.guild_text or "")
    }, "|")
end

local function anchorTargetDrawable(drawable, frame, includeMpBar, inset)
    if frame == nil or drawable == nil then
        return
    end
    inset = tonumber(inset) or 0
    if type(drawable) == "table" and type(drawable.parts) == "table" then
        local topRef = frame.hpBar or frame
        local bottomRef = (includeMpBar and frame.mpBar ~= nil) and frame.mpBar or (frame.hpBar or frame)
        local thickness = inset <= 0 and 2 or 3
        pcall(function()
            local top = drawable.parts.top
            local bottom = drawable.parts.bottom
            local left = drawable.parts.left
            local right = drawable.parts.right
            if top ~= nil then
                top:RemoveAllAnchors()
                top:AddAnchor("TOPLEFT", topRef, -3 - inset, -3 - inset)
                top:AddAnchor("TOPRIGHT", topRef, 3 + inset, -3 - inset)
                if top.SetHeight ~= nil then
                    top:SetHeight(thickness)
                end
            end
            if bottom ~= nil then
                bottom:RemoveAllAnchors()
                bottom:AddAnchor("BOTTOMLEFT", bottomRef, -3 - inset, 3 + inset)
                bottom:AddAnchor("BOTTOMRIGHT", bottomRef, 3 + inset, 3 + inset)
                if bottom.SetHeight ~= nil then
                    bottom:SetHeight(thickness)
                end
            end
            if left ~= nil then
                left:RemoveAllAnchors()
                left:AddAnchor("TOPLEFT", topRef, -3 - inset, -3 - inset)
                left:AddAnchor("BOTTOMLEFT", bottomRef, -3 - inset, 3 + inset)
                if left.SetWidth ~= nil then
                    left:SetWidth(thickness)
                end
            end
            if right ~= nil then
                right:RemoveAllAnchors()
                right:AddAnchor("TOPRIGHT", topRef, 3 + inset, -3 - inset)
                right:AddAnchor("BOTTOMRIGHT", bottomRef, 3 + inset, 3 + inset)
                if right.SetWidth ~= nil then
                    right:SetWidth(thickness)
                end
            end
        end)
        return
    end
    pcall(function()
        drawable:RemoveAllAnchors()
        if frame.hpBar == nil then
            drawable:AddAnchor("TOPLEFT", frame, -2 - inset, -2 - inset)
            drawable:AddAnchor("BOTTOMRIGHT", frame, 2 + inset, 2 + inset)
            return
        end
        if includeMpBar and frame.mpBar ~= nil then
            drawable:AddAnchor("TOPLEFT", frame.hpBar, -3 - inset, -3 - inset)
            drawable:AddAnchor("BOTTOMRIGHT", frame.mpBar, 3 + inset, 3 + inset)
            return
        end
        drawable:AddAnchor("TOPLEFT", frame.hpBar, -3 - inset, -3 - inset)
        drawable:AddAnchor("BOTTOMRIGHT", frame.hpBar, 3 + inset, 3 + inset)
    end)
end

function Layout.AnchorTargetGlow(frame, includeMpBar)
    anchorTargetDrawable(frame.targetGlow, frame, includeMpBar and true or false, 1)
    anchorTargetDrawable(frame.targetTint, frame, includeMpBar and true or false, -1)
end

function Layout.Apply(frame, cfg, content)
    content = type(content) == "table" and content or {}
    local width = clamp(cfg.width, 80, 320, 156)
    local hpHeight = clamp(cfg.hp_height, 8, 56, 16)
    local mpHeight = clamp(cfg.mp_height, 0, 26, 5)
    local barGap = clamp(cfg.bar_gap, 0, 10, 2)
    local nameFs = clamp(cfg.name_font_size, 8, 30, 14)
    local guildFs = clamp(cfg.guild_font_size, 8, 24, 11)
    local roleFs = clamp(cfg.role_font_size, 8, 24, 11)
    local valueFs = clamp(cfg.value_font_size, 8, 24, 12)
    local valueOffsetX = clamp(cfg.value_offset_x, -80, 80, 0)
    local valueOffsetY = clamp(cfg.value_offset_y, -40, 40, 0)
    local distFs = clamp(cfg.distance_font_size, 8, 22, 11)
    local showName = cfg.show_name and true or false
    local showGuild = cfg.show_guild and true or false
    local showRole = cfg.show_role and true or false
    local showMpBar = cfg.show_mp_bar and mpHeight > 0
    local layout = tostring(cfg.name_layout or "vertical")
    local nameText = tostring(content.name_text or "")
    local guildText = tostring(content.guild_text or "")

    local roleReserved = showRole and (roleFs + 8) or 0
    local guildReserved = showGuild and (guildFs + 8) or 0
    local topLineHeight = 0
    if showName or showRole then
        topLineHeight = math.max(showName and nameFs or 0, showRole and roleFs or 0) + 4
    end
    if showGuild and layout == "horizontal" and showName then
        topLineHeight = math.max(topLineHeight, guildFs + 4)
    end

    local textHeight = topLineHeight
    if showGuild and not (layout == "horizontal" and showName) then
        textHeight = textHeight + guildFs + 2
    end
    local totalHeight = textHeight + hpHeight + (showMpBar and (barGap + mpHeight) or 0) + 6

    local topTextWidth = width - 12 - roleReserved
    local nameWidth = showName and (Helpers.MeasureTextWidth(frame.nameLabel, nameText, nameFs, math.max(40, topTextWidth)) + 10) or topTextWidth
    local guildWidth = showGuild and (Helpers.MeasureTextWidth(frame.guildLabel, guildText, guildFs, math.max(34, topTextWidth)) + 10) or topTextWidth
    if layout == "horizontal" and showName and showGuild then
        nameWidth = math.max(40, nameWidth)
        guildWidth = math.max(34, guildWidth)
    else
        nameWidth = math.max(40, nameWidth)
        guildWidth = math.max(34, guildWidth)
    end
    local textBlockWidth = topTextWidth
    if layout == "horizontal" and showName and showGuild then
        textBlockWidth = nameWidth + guildWidth + 8
    else
        textBlockWidth = math.max(showName and nameWidth or 0, showGuild and guildWidth or 0)
    end
    local frameWidth = math.max(width, textBlockWidth + roleReserved + 12)
    local barInsetLeft = math.floor((frameWidth - width) / 2)
    local barInsetRight = frameWidth - width - barInsetLeft

    if frame.cache ~= nil then
        frame.cache.frame_width = frameWidth
        frame.cache.frame_height = totalHeight
        frame.cache.target_glow_mp = showMpBar and true or false
    end
    pcall(function()
        frame:SetExtent(frameWidth, totalHeight)
    end)

    Helpers.SetLabelStyle(frame.nameLabel, nameFs, nameWidth, true)
    Helpers.SetLabelStyle(frame.guildLabel, guildFs, guildWidth, true)
    Helpers.SetLabelStyle(frame.roleLabel, roleFs, 1)
    Helpers.SetLabelStyle(frame.hpValueLabel, valueFs, width - 10)
    Helpers.SetLabelStyle(frame.mpValueLabel, valueFs, width - 10)
    Helpers.SetLabelStyle(frame.distanceLabel, distFs, 70)

    Helpers.SetLabelColor(frame.nameLabel, cfg.name_color, { 255, 255, 255, 255 })
    Helpers.SetLabelColor(frame.guildLabel, cfg.guild_color, { 150, 210, 255, 255 })
    Helpers.SetLabelColor(frame.hpValueLabel, cfg.value_color, { 255, 255, 255, 255 })
    Helpers.SetLabelColor(frame.mpValueLabel, cfg.value_color, { 255, 255, 255, 255 })
    Helpers.SetLabelColor(frame.distanceLabel, cfg.distance_color, { 255, 226, 140, 255 })

    local baseNameX = 3 + roleReserved
    local baseNameY = 0
    local baseGuildX = (layout == "horizontal" and showName and showGuild) and (baseNameX + nameWidth + 8) or 3
    local baseGuildY = (layout == "horizontal" and showName and showGuild) and 0 or (topLineHeight - 2)

    if showName then
        Helpers.SafeAnchor(
            frame.nameLabel, "TOPLEFT", frame, "TOPLEFT",
            baseNameX + clamp(cfg.name_offset_x, -80, 80, 0),
            baseNameY + clamp(cfg.name_offset_y, -80, 80, 0)
        )
    end
    if showGuild then
        Helpers.SafeAnchor(
            frame.guildLabel, "TOPLEFT", frame, "TOPLEFT",
            baseGuildX + clamp(cfg.guild_offset_x, -80, 80, 0),
            baseGuildY + clamp(cfg.guild_offset_y, -80, 80, 0)
        )
    end
    Helpers.SafeShow(frame.roleLabel, false)

    if frame.hpBar ~= nil then
        pcall(function()
            frame.hpBar:RemoveAllAnchors()
            frame.hpBar:AddAnchor("TOPLEFT", frame, barInsetLeft, textHeight)
            frame.hpBar:AddAnchor("TOPRIGHT", frame, -barInsetRight, textHeight)
            frame.hpBar:SetHeight(hpHeight)
        end)
    end
    if frame.eventWindow ~= nil and frame.hpBar ~= nil then
        pcall(function()
            frame.eventWindow:RemoveAllAnchors()
            frame.eventWindow:AddAnchor("TOPLEFT", frame.hpBar, "TOPLEFT", -3, -3)
            frame.eventWindow:AddAnchor("BOTTOMRIGHT", frame.hpBar, "BOTTOMRIGHT", 3, 3)
            if frame.eventWindow.Raise ~= nil then
                frame.eventWindow:Raise()
            end
        end)
    end
    if frame.mpBar ~= nil then
        pcall(function()
            frame.mpBar:RemoveAllAnchors()
            frame.mpBar:AddAnchor("TOPLEFT", frame.hpBar, "BOTTOMLEFT", 0, -barGap)
            frame.mpBar:AddAnchor("TOPRIGHT", frame.hpBar, "BOTTOMRIGHT", 0, -barGap)
            frame.mpBar:SetHeight(mpHeight)
        end)
        Helpers.SafeShow(frame.mpBar, showMpBar)
    end

    Helpers.SafeAnchor(frame.hpValueLabel, "CENTER", frame.hpBar, "CENTER", valueOffsetX, valueOffsetY)
    if frame.mpBar ~= nil then
        Helpers.SafeAnchor(frame.mpValueLabel, "CENTER", frame.mpBar, "CENTER", valueOffsetX, valueOffsetY)
    end
    Helpers.SafeAnchor(
        frame.distanceLabel, "TOPRIGHT", frame, "TOPRIGHT",
        clamp(cfg.distance_offset_x, -120, 120, -2),
        clamp(cfg.distance_offset_y, -120, 120, 0)
    )

    Helpers.SafeSetBg(frame, cfg.show_background ~= false, clamp(cfg.bg_alpha_pct, 0, 100, 72) / 100)
    if frame.cache ~= nil then
        frame.cache.base_alpha = clamp(cfg.alpha_pct, 10, 100, 100) / 100
    end

    if frame.bg ~= nil then
        pcall(function()
            frame.bg:RemoveAllAnchors()
            if showMpBar and frame.mpBar ~= nil then
                frame.bg:AddAnchor("TOPLEFT", frame.hpBar, -3, -3)
                frame.bg:AddAnchor("BOTTOMRIGHT", frame.mpBar, 2, 3)
            else
                frame.bg:AddAnchor("TOPLEFT", frame.hpBar, -3, -3)
                frame.bg:AddAnchor("BOTTOMRIGHT", frame.hpBar, 2, 3)
            end
        end)
    end

    Layout.AnchorTargetGlow(frame, showMpBar)

    if frame.mpBar ~= nil and frame.mpBar.statusBar ~= nil then
        Helpers.ApplyStatusBarColor(frame.mpBar.statusBar, Helpers.Color01(cfg.mp_bar_color, { 46, 122, 240, 255 }))
    end
end

return Layout
