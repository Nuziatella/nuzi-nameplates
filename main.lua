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
    version = "1.5.43",
    desc = "Overhead raid bars"
}

local hotDataElapsedMs = 0
local bulkDataElapsedMs = 0
local hotPositionElapsedMs = 0
local bulkPositionElapsedMs = 0
local HOT_POSITION_INTERVAL_MS = 16
local HOT_DATA_INTERVAL_MS = 33
local BULK_DATA_INTERVAL_MS = 220

local function logInfo(message)
    if api.Log ~= nil and api.Log.Info ~= nil then
        api.Log:Info("[Gharka Bars] " .. tostring(message or ""))
    end
end

local function logError(message)
    if api.Log ~= nil and api.Log.Err ~= nil then
        api.Log:Err("[Gharka Bars] " .. tostring(message or ""))
    end
end

local function safeBarsCall(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        logError(tostring(label or "Bars call failed") .. ": " .. tostring(err or "unknown error"))
    end
    return ok
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
            safeBarsCall("Bars.Update(apply)", function()
                Bars.Update()
            end)
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
    safeBarsCall("Bars.Update(applyAll)", function()
        Bars.Update()
    end)
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
    hotDataElapsedMs = hotDataElapsedMs + delta
    bulkDataElapsedMs = bulkDataElapsedMs + delta
    hotPositionElapsedMs = hotPositionElapsedMs + delta
    bulkPositionElapsedMs = bulkPositionElapsedMs + delta
    if hotPositionElapsedMs >= HOT_POSITION_INTERVAL_MS then
        hotPositionElapsedMs = 0
        if Bars.UpdateVisiblePositions ~= nil then
            safeBarsCall("Bars.UpdateVisiblePositions", function()
                Bars.UpdateVisiblePositions()
            end)
        else
            safeBarsCall("Bars.UpdateHotPositions", function()
                Bars.UpdateHotPositions()
            end)
        end
    end
    local bulkPositionIntervalMs = 16
    if Bars ~= nil and Bars.GetBulkPositionIntervalMs ~= nil then
        bulkPositionIntervalMs = tonumber(Bars.GetBulkPositionIntervalMs()) or 16
    end
    if bulkPositionElapsedMs >= bulkPositionIntervalMs then
        bulkPositionElapsedMs = 0
        safeBarsCall("Bars.UpdateBulkPositions", function()
            Bars.UpdateBulkPositions()
        end)
    end
    if hotDataElapsedMs >= HOT_DATA_INTERVAL_MS then
        hotDataElapsedMs = 0
        safeBarsCall("Bars.UpdateHotData", function()
            Bars.UpdateHotData()
        end)
    end
    if bulkDataElapsedMs >= BULK_DATA_INTERVAL_MS then
        bulkDataElapsedMs = 0
        safeBarsCall("Bars.UpdateBulkData", function()
            Bars.UpdateBulkData()
        end)
    end
end

local function onUiReloaded()
    hotDataElapsedMs = 0
    bulkDataElapsedMs = 0
    hotPositionElapsedMs = 0
    bulkPositionElapsedMs = 0
    Compat.Probe(true)
    safeBarsCall("Bars.Reset(UI_RELOADED)", function()
        Bars.Reset()
    end)
    SettingsUi.Unload()
    safeBarsCall("Bars.Init(UI_RELOADED)", function()
        Bars.Init()
    end)
    SettingsUi.Init(buildActions())
    safeBarsCall("Bars.Update(UI_RELOADED)", function()
        Bars.Update()
    end)
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
    safeBarsCall("Bars.Init(load)", function()
        Bars.Init()
    end)
    SettingsUi.Init(buildActions())
    safeBarsCall("Bars.Update(load)", function()
        Bars.Update()
    end)
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
