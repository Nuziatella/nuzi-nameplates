local api = require("api")

local CcEffects = {}

local TOOLTIP_CACHE = {}

local CATEGORY_PRIORITY = {
    hard = 400,
    silence = 320,
    root = 240,
    slow = 160,
    dot = 40,
    misc = 80
}

local EXACT_EFFECTS = {}

local function register(category, names, dispellable)
    for _, name in ipairs(names or {}) do
        EXACT_EFFECTS[string.lower(tostring(name))] = {
            category = category,
            priority = CATEGORY_PRIORITY[category] or 0,
            dispellable = dispellable == true
        }
    end
end

register("hard", {
    "Stun",
    "Poison Stun",
    "Sleep",
    "Deep Sleep",
    "Fear",
    "Petrification",
    "Petrified",
    "Deep Freeze",
    "Freeze Up",
    "Freeze of Evil Spirit",
    "Freeze",
    "Bubble Trap",
    "Wave Meteor Strike Hit",
    "Strong Telekinesis",
    "Telekinesis",
    "Meteor Impact",
    "Horrorshow",
    "Petrified Taunt",
    "Hammer Smash",
    "Ice Wall",
    "Explosive Ice",
    "Unconscious",
    "Ice Shock",
    "Alexander's Powerful Freeze",
    "Howl of Terror",
    "Shock",
    "Paralyzed",
    "Control"
}, true)

register("silence", {
    "Silence",
    "Silenced",
    "Eternal Silence",
    "Disarmed",
    "Mana Force"
}, true)

register("root", {
    "Snare",
    "Impaled",
    "Tripped",
    "Tripped (Strong)",
    "Alliance Soldier's Pull",
    "Red Dragon's Wind Gust",
    "Pulled",
    "Karim's Shackle",
    "Shockstep Effect",
    "Agrax's Snare",
    "Steel Trap",
    "Earthen Grip",
    "Phantasm's Wail",
    "Ecktom's Shackle",
    "Trap!",
    "Hell Spear",
    "Lava Trap Explosion",
    "Wraith Rooted"
}, true)

register("slow", {
    "Slow",
    "Ice Shard",
    "Bestial Leap",
    "Dizziness",
    "Poor Landing",
    "Dazed"
}, true)

register("dot", {
    "Bleed",
    "Burn",
    "Burning",
    "Conflagration",
    "Electric Shock",
    "Poison",
    "Poision",
    "Toxic Shot",
    "Enervate",
    "Enervated"
}, true)

register("misc", {
    "Splashdown Bubble",
    "Alkaran's Curse",
    "Ice",
    "Lost Tribe's Shockwave"
})

local KEYWORD_RULES = {
    { pattern = "stun", category = "hard", dispellable = true },
    { pattern = "sleep", category = "hard", dispellable = true },
    { pattern = "fear", category = "hard", dispellable = true },
    { pattern = "freeze", category = "hard", dispellable = true },
    { pattern = "petrif", category = "hard", dispellable = true },
    { pattern = "telekinesis", category = "hard", dispellable = true },
    { pattern = "paraly", category = "hard", dispellable = true },
    { pattern = "shock", category = "hard", dispellable = true },
    { pattern = "silence", category = "silence", dispellable = true },
    { pattern = "disarm", category = "silence", dispellable = true },
    { pattern = "snare", category = "root", dispellable = true },
    { pattern = "trap", category = "root", dispellable = true },
    { pattern = "shackle", category = "root", dispellable = true },
    { pattern = "root", category = "root", dispellable = true },
    { pattern = "pull", category = "root", dispellable = true },
    { pattern = "impale", category = "root", dispellable = true },
    { pattern = "trip", category = "root", dispellable = true },
    { pattern = "slow", category = "slow", dispellable = true },
    { pattern = "daze", category = "slow", dispellable = true },
    { pattern = "bleed", category = "dot", dispellable = true },
    { pattern = "burn", category = "dot", dispellable = true },
    { pattern = "conflagrat", category = "dot", dispellable = true },
    { pattern = "electric shock", category = "dot", dispellable = true },
    { pattern = "poison", category = "dot", dispellable = true },
    { pattern = "poision", category = "dot", dispellable = true },
    { pattern = "toxic", category = "dot", dispellable = true },
    { pattern = "enervat", category = "dot", dispellable = true }
}

local function safeDebuffCount(unit)
    if api.Unit == nil or api.Unit.UnitDeBuffCount == nil then
        return 0
    end
    local ok, count = pcall(function()
        return api.Unit:UnitDeBuffCount(unit)
    end)
    if not ok then
        return 0
    end
    return tonumber(count) or 0
end

local function safeDebuff(unit, index)
    if api.Unit == nil or api.Unit.UnitDeBuff == nil then
        return nil
    end
    local ok, debuff = pcall(function()
        return api.Unit:UnitDeBuff(unit, index)
    end)
    if not ok or type(debuff) ~= "table" then
        return nil
    end
    return debuff
end

local function getTooltip(buffId)
    local id = tonumber(buffId)
    if id == nil or api.Ability == nil or api.Ability.GetBuffTooltip == nil then
        return nil
    end
    if TOOLTIP_CACHE[id] ~= nil then
        return TOOLTIP_CACHE[id]
    end
    local tooltip = nil
    pcall(function()
        tooltip = api.Ability:GetBuffTooltip(id, 1)
    end)
    TOOLTIP_CACHE[id] = type(tooltip) == "table" and tooltip or false
    if TOOLTIP_CACHE[id] == false then
        return nil
    end
    return TOOLTIP_CACHE[id]
end

local function classifyName(rawName)
    local key = string.lower(tostring(rawName or ""))
    if key == "" then
        return nil
    end
    if EXACT_EFFECTS[key] ~= nil then
        return EXACT_EFFECTS[key]
    end
    for _, rule in ipairs(KEYWORD_RULES) do
        if string.find(key, rule.pattern, 1, true) ~= nil then
            return {
                category = rule.category,
                priority = CATEGORY_PRIORITY[rule.category] or 0,
                dispellable = rule.dispellable == true
            }
        end
    end
    return nil
end

local function trimText(value)
    local text = tostring(value or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function resolveDebuffName(debuff, tooltip)
    local candidates = {
        type(tooltip) == "table" and tooltip.name or nil,
        type(tooltip) == "table" and tooltip.buffName or nil,
        type(tooltip) == "table" and tooltip.title or nil,
        type(debuff) == "table" and debuff.name or nil,
        type(debuff) == "table" and debuff.buffName or nil,
        type(debuff) == "table" and debuff.debuffName or nil,
        type(debuff) == "table" and debuff.tooltipName or nil
    }
    for _, candidate in ipairs(candidates) do
        local text = trimText(candidate)
        if text ~= "" then
            return text
        end
    end
    return ""
end

local function buildEntry(debuff, tooltip, scanIndex)
    local name = resolveDebuffName(debuff, tooltip)
    local match = classifyName(name)
    if match == nil then
        return nil
    end
    local timeLeft = tonumber(debuff.timeLeft) or 0
    return {
        buff_id = tonumber(debuff.buff_id) or 0,
        name = name,
        path = tostring(debuff.path or ""),
        time_left_ms = timeLeft,
        category = match.category,
        priority = tonumber(match.priority) or 0,
        dispellable = match.dispellable == true,
        scan_index = tonumber(scanIndex) or 0
    }
end

local function compareEntries(a, b)
    local aIndex = tonumber(a ~= nil and a.scan_index or 0) or 0
    local bIndex = tonumber(b ~= nil and b.scan_index or 0) or 0
    if aIndex ~= bIndex then
        return aIndex > bIndex
    end
    local aPriority = tonumber(a ~= nil and a.priority or 0) or 0
    local bPriority = tonumber(b ~= nil and b.priority or 0) or 0
    if aPriority ~= bPriority then
        return aPriority > bPriority
    end
    local aTime = tonumber(a ~= nil and a.time_left_ms or 0) or 0
    local bTime = tonumber(b ~= nil and b.time_left_ms or 0) or 0
    if aTime ~= bTime then
        return aTime > bTime
    end
    local aId = tonumber(a ~= nil and a.buff_id or 0) or 0
    local bId = tonumber(b ~= nil and b.buff_id or 0) or 0
    if aId ~= bId then
        return aId < bId
    end
    return tostring(a ~= nil and a.name or "") < tostring(b ~= nil and b.name or "")
end

function CcEffects.ScanUnit(unit)
    local effects = {}
    local count = safeDebuffCount(unit)
    for index = 1, count do
        local debuff = safeDebuff(unit, index)
        if debuff ~= nil and debuff.buff_id ~= nil then
            local entry = buildEntry(debuff, getTooltip(debuff.buff_id), index)
            if entry ~= nil then
                table.insert(effects, entry)
            end
        end
    end
    table.sort(effects, compareEntries)
    return effects
end

return CcEffects
