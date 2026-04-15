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

local function normalize(text)
    return tostring(text or ""):lower()
end

local function makeLookup(list)
    local out = {}
    for _, name in ipairs(list or {}) do
        out[normalize(name)] = true
    end
    return out
end

local ROLE_CLASS_MAP = {
    tank = makeLookup({
        "Abolisher",
        "Doomlord",
        "Nightcloak",
        "Skullknight",
        "Templar"
    }),
    healer = makeLookup({
        "Cleric",
        "Confessor",
        "Doombringer",
        "Edgewalker",
        "Hierophant",
        "Soothsayer"
    }),
    melee = makeLookup({
        "Assassin",
        "Blade Dancer",
        "Blighter",
        "Bloodreaver",
        "Darkrunner",
        "Deathwish",
        "Enforcer",
        "Executioner",
        "Hexblade",
        "Infiltrator",
        "Outrider",
        "Ravager",
        "Shadowblade",
        "Shadowplay",
        "Shadowsong"
    }),
    ranged = makeLookup({
        "Ebonsong",
        "Gunslinger",
        "Hawksong",
        "Primeval",
        "Ranger",
        "Shadehunter",
        "Stone Arrow",
        "Trickster"
    }),
    magic = makeLookup({
        "Arcanist",
        "Daggerspell",
        "Demonologist",
        "Dreambreaker",
        "Enigmatist",
        "Fanatic",
        "Reaper",
        "Revenant",
        "Sorrowsong",
        "Spellsinger"
    })
}

function Role.GetRoleForClass(className)
    local key = normalize(className)
    if key == "" then
        return nil
    end
    for roleName, lookup in pairs(ROLE_CLASS_MAP) do
        if lookup[key] then
            return roleName
        end
    end
    return nil
end

function Role.GetRoleForUnit(unit)
    local className = ""
    pcall(function()
        if api.Ability ~= nil and api.Ability.GetUnitClassName ~= nil then
            className = api.Ability:GetUnitClassName(unit) or ""
        end
    end)
    if className == "" then
        pcall(function()
            if api.Unit ~= nil and api.Unit.UnitClass ~= nil then
                className = api.Unit:UnitClass(unit) or ""
            end
        end)
    end
    return Role.GetRoleForClass(className), className
end

function Role.GetRoleLetter(role)
    if role == "tank" then
        return "T"
    elseif role == "healer" then
        return "H"
    elseif role == "melee" then
        return "M"
    elseif role == "ranged" then
        return "R"
    elseif role == "magic" then
        return "X"
    end
    return "D"
end

function Role.GetRoleColor(role)
    if role == "tank" then
        return { 64, 220, 86, 255 }
    elseif role == "healer" then
        return { 255, 110, 196, 255 }
    elseif role == "melee" then
        return { 255, 88, 88, 255 }
    elseif role == "ranged" then
        return { 255, 187, 64, 255 }
    elseif role == "magic" then
        return { 120, 132, 255, 255 }
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

    if role == "tank" then
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
