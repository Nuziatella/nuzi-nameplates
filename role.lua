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

local Role = {}

local function mapTeamRoleId(roleId)
    local value = tonumber(roleId)
    if value == nil then
        return nil
    end
    if value == 1 then
        return "defender"
    elseif value == 2 then
        return "healer"
    elseif value == 3 then
        return "attacker"
    end
    return "undecided"
end

local function getUnitName(unit)
    if api.Unit == nil then
        return ""
    end
    if api.Unit.UnitName ~= nil then
        local name = tostring(api.Unit:UnitName(unit) or "")
        if name ~= "" then
            return name
        end
    end
    if api.Unit.GetUnitId == nil or api.Unit.GetUnitNameById == nil then
        return ""
    end
    local unitId = api.Unit:GetUnitId(unit)
    if unitId == nil then
        return ""
    end
    return tostring(api.Unit:GetUnitNameById(unitId) or "")
end

local function getTeamMemberIndexForUnit(unit)
    if api.Team == nil or api.Team.GetRole == nil then
        return nil, false
    end

    local token = tostring(unit or "")
    local memberIndex = tonumber(token:match("^team(%d+)$"))
    if memberIndex ~= nil and memberIndex > 0 then
        return memberIndex, false
    end

    if token == "player" and api.Team.GetTeamPlayerIndex ~= nil then
        local playerIndex = tonumber(api.Team:GetTeamPlayerIndex())
        if playerIndex ~= nil and playerIndex > 0 then
            return playerIndex, false
        end
        return nil, false
    end

    if api.Team.GetMemberIndexByName == nil or api.Unit == nil or api.Unit.UnitIsTeamMember == nil then
        return nil, false
    end
    if api.Unit:UnitIsTeamMember(unit) ~= true then
        return nil, false
    end

    local unitName = getUnitName(unit)
    if unitName == "" then
        return nil, true
    end

    local namedIndex = tonumber(api.Team:GetMemberIndexByName(unitName))
    if namedIndex ~= nil and namedIndex > 0 then
        return namedIndex, false
    end
    return nil, true
end

local function getTeamRoleForUnit(unit)
    local memberIndex, shouldRetry = getTeamMemberIndexForUnit(unit)
    if memberIndex == nil or api.Team == nil or api.Team.GetRole == nil then
        return nil, nil, shouldRetry
    end
    local role = mapTeamRoleId(api.Team:GetRole(memberIndex))
    if role == nil then
        return nil, nil, true
    end
    return role, "team:" .. tostring(memberIndex), false
end

function Role.GetRoleForUnit(unit)
    return getTeamRoleForUnit(unit)
end

function Role.GetRoleLetter(role)
    if role == "tank" then
        return "T"
    elseif role == "defender" then
        return "D"
    elseif role == "healer" then
        return "H"
    elseif role == "attacker" then
        return "A"
    elseif role == "melee" then
        return "M"
    elseif role == "ranged" then
        return "R"
    elseif role == "magic" then
        return "X"
    elseif role == "undecided" then
        return "U"
    end
    return "D"
end

function Role.GetRoleColor(role)
    if role == "tank" then
        return { 64, 220, 86, 255 }
    elseif role == "defender" then
        return { 255, 210, 70, 255 }
    elseif role == "healer" then
        return { 255, 110, 196, 255 }
    elseif role == "attacker" then
        return { 255, 88, 88, 255 }
    elseif role == "melee" then
        return { 255, 88, 88, 255 }
    elseif role == "ranged" then
        return { 255, 187, 64, 255 }
    elseif role == "magic" then
        return { 120, 132, 255, 255 }
    elseif role == "undecided" then
        return { 110, 170, 255, 255 }
    end
    return { 255, 88, 88, 255 }
end

local function ensurePart(frame, key)
    if frame == nil or frame.CreateImageDrawable == nil then
        return nil
    end
    if frame[key] ~= nil then
        return frame[key]
    end
    local drawable = nil
    pcall(function()
        drawable = frame:CreateImageDrawable("Textures/Defaults/White.dds", "overlay")
        drawable:SetVisible(false)
    end)
    frame[key] = drawable
    return drawable
end

local function setPart(drawable, frame, x, y, width, height, color)
    if drawable == nil then
        return
    end
    local rgba = Helpers.Color01(color, { 255, 255, 255, 255 })
    local key = table.concat({
        tostring(x or ""),
        tostring(y or ""),
        tostring(width or ""),
        tostring(height or ""),
        tostring(rgba[1] or ""),
        tostring(rgba[2] or ""),
        tostring(rgba[3] or ""),
        tostring(rgba[4] or "")
    }, "|")
    if drawable.__ghb_role_key == key and drawable.__ghb_role_visible == true then
        return
    end
    pcall(function()
        if drawable.RemoveAllAnchors ~= nil then
            drawable:RemoveAllAnchors()
        end
        if drawable.AddAnchor ~= nil then
            drawable:AddAnchor("TOPLEFT", frame, x, y)
        end
        if drawable.SetExtent ~= nil then
            drawable:SetExtent(width, height)
        end
        if drawable.SetColor ~= nil then
            drawable:SetColor(rgba[1], rgba[2], rgba[3], rgba[4])
        end
        if drawable.SetVisible ~= nil then
            drawable:SetVisible(true)
        end
    end)
    drawable.__ghb_role_key = key
    drawable.__ghb_role_visible = true
end

function Role.Hide(frame)
    if frame == nil then
        return
    end
    if frame.__ghb_role_hidden == true then
        return
    end
    for _, key in ipairs({ "roleIconA", "roleIconB", "roleIconC", "roleIconD" }) do
        local drawable = frame[key]
        if drawable ~= nil and drawable.SetVisible ~= nil then
            pcall(function()
                drawable:SetVisible(false)
            end)
            drawable.__ghb_role_visible = false
        end
    end
    frame.__ghb_role_hidden = true
    frame.__ghb_role_sig = nil
end

function Role.Apply(frame, cfg, role)
    if frame == nil or type(cfg) ~= "table" or not cfg.show_role or role == nil or role == "" then
        Role.Hide(frame)
        return
    end

    local size = Shared.Clamp(cfg.role_font_size, 8, 24, 11)
    local x = 3 + Shared.Clamp(cfg.role_offset_x, -80, 80, 0)
    local y = Shared.Clamp(cfg.role_offset_y, -80, 80, 0)
    local color = Role.GetRoleColor(role)
    local sig = table.concat({
        tostring(role or ""),
        tostring(size),
        tostring(x),
        tostring(y),
        tostring(color[1] or ""),
        tostring(color[2] or ""),
        tostring(color[3] or ""),
        tostring(color[4] or "")
    }, "|")
    if frame.__ghb_role_sig == sig and frame.__ghb_role_hidden ~= true then
        return
    end
    local a = ensurePart(frame, "roleIconA")
    local b = ensurePart(frame, "roleIconB")
    local c = ensurePart(frame, "roleIconC")
    local d = ensurePart(frame, "roleIconD")
    Role.Hide(frame)

    if role == "tank" or role == "defender" then
        setPart(a, frame, x, y + 1, size, size, color)
        setPart(b, frame, x + 2, y + 3, math.max(2, size - 4), math.max(2, size - 4), { 24, 24, 24, 110 })
    elseif role == "healer" then
        local thick = math.max(2, math.floor(size / 3))
        local arm = math.max(4, size)
        setPart(a, frame, x + math.floor((arm - thick) / 2), y, thick, arm, color)
        setPart(b, frame, x, y + math.floor((arm - thick) / 2), arm, thick, color)
    elseif role == "ranged" then
        local shaft = math.max(2, math.floor(size / 4))
        local half = math.max(4, math.floor(size / 2))
        setPart(a, frame, x, y + math.floor(size / 2), size, shaft, color)
        setPart(b, frame, x + size - half, y, half, half, color)
        setPart(c, frame, x + size - half, y + size - half, half, half, color)
    elseif role == "magic" then
        local thick = math.max(2, math.floor(size / 3))
        local mid = math.floor(size / 2)
        setPart(a, frame, x + mid, y, thick, size, color)
        setPart(b, frame, x, y + mid, size, thick, color)
        setPart(c, frame, x + math.floor(size / 4), y + math.floor(size / 4), thick, thick, { 255, 255, 255, 190 })
        setPart(d, frame, x + size - math.floor(size / 4) - thick, y + size - math.floor(size / 4) - thick, thick, thick, { 255, 255, 255, 190 })
    else
        local blade = math.max(2, math.floor(size / 3))
        setPart(a, frame, x, y + 1, blade, size, color)
        setPart(b, frame, x + blade + 2, y - 1, blade, size + 2, color)
        setPart(c, frame, x + ((blade + 2) * 2), y + 2, blade, math.max(4, size - 2), color)
    end
    frame.__ghb_role_hidden = false
    frame.__ghb_role_sig = sig
end

return Role
