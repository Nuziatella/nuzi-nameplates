local api = require("api")

local StockNametag = {}

local SETTERS = {
    { fn = "SetColorFriendly", key = "friendly" },
    { fn = "SetColorFriendlyNPC", key = "friendly_npc" },
    { fn = "SetColorNeutral", key = "neutral" },
    { fn = "SetColorParty", key = "party" },
    { fn = "SetColorRaid", key = "raid" },
    { fn = "SetColorRaidPK", key = "raid_pk" },
    { fn = "SetColorPK", key = "pk" },
    { fn = "SetColorEnemy", key = "enemy" },
    { fn = "SetColorMonster", key = "monster" },
    { fn = "SetColorPirate", key = "pirate" }
}

local DEFAULT_COLORS = {
    friendly = { 255, 240, 100, 255 },
    friendly_npc = { 247, 232, 76, 255 },
    neutral = { 184, 148, 52, 255 },
    party = { 76, 204, 234, 255 },
    raid = { 39, 139, 252, 255 },
    raid_pk = { 255, 45, 0, 255 },
    pk = { 170, 80, 255, 255 },
    enemy = { 255, 0, 0, 255 },
    monster = { 255, 0, 0, 255 },
    pirate = { 255, 156, 39, 255 }
}

local function getNametagApi()
    return type(api) == "table" and type(api.Nametag) == "table" and api.Nametag or nil
end

local function hasColorApi()
    local nametag = getNametagApi()
    if nametag == nil then
        return false
    end
    for _, item in ipairs(SETTERS) do
        if type(nametag[item.fn]) ~= "function" then
            return false
        end
    end
    return true
end

local function colorChannel(value, fallback)
    local n = tonumber(value)
    if n == nil then
        n = tonumber(fallback) or 0
    end
    n = math.floor(n + 0.5)
    if n < 0 then
        return 0
    end
    if n > 255 then
        return 255
    end
    return n
end

local function decimalColorString(rgba, fallback)
    local src = type(rgba) == "table" and rgba or fallback
    local r = colorChannel(type(src) == "table" and src[1] or nil, type(fallback) == "table" and fallback[1] or 255)
    local g = colorChannel(type(src) == "table" and src[2] or nil, type(fallback) == "table" and fallback[2] or 255)
    local b = colorChannel(type(src) == "table" and src[3] or nil, type(fallback) == "table" and fallback[3] or 255)
    return tostring((r * 65536) + (g * 256) + b)
end

local function buildColors(cfg)
    cfg = type(cfg) == "table" and cfg or {}
    return {
        friendly = decimalColorString(cfg.hp_bar_color, DEFAULT_COLORS.friendly),
        friendly_npc = decimalColorString(cfg.hp_bar_color, DEFAULT_COLORS.friendly_npc),
        neutral = decimalColorString(cfg.neutral_bar_color, DEFAULT_COLORS.neutral),
        party = decimalColorString(cfg.hp_bar_color, DEFAULT_COLORS.party),
        raid = decimalColorString(cfg.hp_bar_color, DEFAULT_COLORS.raid),
        raid_pk = decimalColorString(cfg.bloodlust_team_color, DEFAULT_COLORS.raid_pk),
        pk = decimalColorString(cfg.bloodlust_target_color, DEFAULT_COLORS.pk),
        enemy = decimalColorString(cfg.hostile_bar_color, DEFAULT_COLORS.enemy),
        monster = decimalColorString(cfg.hostile_bar_color, DEFAULT_COLORS.monster),
        pirate = decimalColorString(cfg.hostile_bar_color, DEFAULT_COLORS.pirate)
    }
end

function StockNametag.Apply(cfg, state)
    local nametag = getNametagApi()
    if nametag == nil or not hasColorApi() then
        return false
    end

    local values = buildColors(cfg)
    local keyParts = {}
    for _, item in ipairs(SETTERS) do
        keyParts[#keyParts + 1] = item.fn .. "=" .. tostring(values[item.key] or "")
    end
    local colorKey = table.concat(keyParts, ";")
    if type(state) == "table" and state.stock_nametag_color_key == colorKey then
        return true
    end

    local applied = true
    for _, item in ipairs(SETTERS) do
        local color = values[item.key]
        local setter = nametag[item.fn]
        if color ~= nil and type(setter) == "function" then
            local ok = pcall(function()
                setter(nametag, color)
            end)
            if not ok then
                applied = false
            end
        end
    end
    if applied and type(state) == "table" then
        state.stock_nametag_color_key = colorKey
    end
    return applied
end

return StockNametag
