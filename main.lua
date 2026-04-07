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
local Bars = loadModule("bars")
local SettingsUi = loadModule("settings_ui")
local Compat = loadModule("compat")

local addon = {
    name = "Gharka Bars",
    author = "Nuzi",
    version = "1.5.13",
    desc = "Overhead raid bars"
}

local dataElapsedMs = 0
local positionElapsedMs = 0

local function logInfo(message)
    if api.Log ~= nil and api.Log.Info ~= nil then
        api.Log:Info("[Gharka Bars] " .. tostring(message or ""))
    end
end

local function modulesReady()
    return Shared ~= nil and Bars ~= nil and SettingsUi ~= nil and Compat ~= nil
end

local function logRuntimeSummary()
    local runtime = Compat.Get()
    local caps = runtime.caps or {}
    logInfo(string.format(
        "Runtime render=%s sliders=%s anchor=%s statusbars=%s",
        caps.render_supported and "yes" or "no",
        caps.slider_factory and "yes" or "no",
        caps.nametag_anchor and "nametag" or (caps.screen_position and "screen" or "none"),
        caps.statusbar_factory and "yes" or "no"
    ))
    for _, warning in ipairs(runtime.warnings or {}) do
        logInfo(warning)
    end
    for _, blocker in ipairs(runtime.blockers or {}) do
        if api.Log ~= nil and api.Log.Err ~= nil then
            api.Log:Err("[Gharka Bars] " .. tostring(blocker))
        end
    end
end

local function buildActions()
    return {
        apply = function()
            Bars.Update()
        end,
        save = function()
            return Shared.SaveSettings()
        end,
        backup = function()
            return Shared.SaveSettingsBackup()
        end,
        import = function()
            return Shared.ImportLatestBackup()
        end
    }
end

local function applyAll()
    Bars.Update()
    SettingsUi.Refresh()
end

local function onUpdate(dt)
    local delta = tonumber(dt) or 0
    if delta < 0 then
        delta = 0
    end
    if delta < 5 then
        delta = delta * 1000
    end
    dataElapsedMs = dataElapsedMs + delta
    positionElapsedMs = positionElapsedMs + delta
    if positionElapsedMs >= 16 then
        positionElapsedMs = 0
        Bars.UpdatePositions()
    end
    if dataElapsedMs >= 100 then
        dataElapsedMs = 0
        Bars.UpdateData()
    end
end

local function onUiReloaded()
    dataElapsedMs = 0
    positionElapsedMs = 0
    Compat.Probe(true)
    Bars.Reset()
    SettingsUi.Unload()
    Bars.Init()
    SettingsUi.Init(buildActions())
    Bars.Update()
end

local function onChatMessage(channel, unit, isHostile, name, message)
    local raw = tostring(message or "")
    if raw == "!gb" or raw == "!gharkabars" then
        SettingsUi.Toggle()
    elseif raw == "!gb on" then
        Shared.EnsureSettings().enabled = true
        Shared.SaveSettings()
        applyAll()
    elseif raw == "!gb off" then
        Shared.EnsureSettings().enabled = false
        Shared.SaveSettings()
        applyAll()
    end
end

local function onLoad()
    if not modulesReady() then
        if api.Log ~= nil and api.Log.Err ~= nil then
            api.Log:Err("[Gharka Bars] Failed to load one or more modules")
        end
        return
    end
    Shared.LoadSettings()
    Compat.Probe(true)
    logRuntimeSummary()
    Bars.Init()
    SettingsUi.Init(buildActions())
    Bars.Update()
    api.On("UPDATE", onUpdate)
    api.On("UI_RELOADED", onUiReloaded)
    api.On("CHAT_MESSAGE", onChatMessage)
    pcall(function()
        api.On("COMMUNITY_CHAT_MESSAGE", onChatMessage)
    end)
    logInfo("Loaded v" .. tostring(addon.version) .. ". Use the GB button for settings.")
end

local function onUnload()
    api.On("UPDATE", function() end)
    api.On("UI_RELOADED", function() end)
    api.On("CHAT_MESSAGE", function() end)
    pcall(function()
        api.On("COMMUNITY_CHAT_MESSAGE", function() end)
    end)
    if Bars ~= nil then
        Bars.Unload()
    end
    if SettingsUi ~= nil then
        SettingsUi.Unload()
    end
end

addon.OnLoad = onLoad
addon.OnUnload = onUnload

return addon
