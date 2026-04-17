local api = require("api")
local Core = api._NuziCore or require("nuzi-core/core")

local Commands = Core.Commands
local Events = Core.Events
local Log = Core.Log
local Require = Core.Require
local Scheduler = Core.Scheduler

local bootstrapLogger = Log.Create("Gharka Bars")
local moduleErrors = {}

local function appendModuleErrors(name, errors)
    if type(errors) ~= "table" or #errors == 0 then
        moduleErrors[#moduleErrors + 1] = string.format("%s: unknown load failure", tostring(name))
        return
    end
    moduleErrors[#moduleErrors + 1] = string.format(
        "%s: %s",
        tostring(name),
        Require.DescribeErrors(errors)
    )
end

local modules, failures = Require.AddonSet("gharka-bars", {
    "shared",
    "bars",
    "settings_ui",
    "compat"
})

for name, failure in pairs(failures or {}) do
    appendModuleErrors(name, failure.errors)
end

local Shared = modules.shared
local Bars = modules.bars
local SettingsUi = modules.settings_ui
local Compat = modules.compat

local addon = {
    name = "Gharka Bars",
    author = "Nuzi",
    version = "1.5.44",
    desc = "Overhead raid bars"
}

local logger = Log.Create(addon.name)
local events = Events.Create({
    logger = logger
})

local updateLoops = Scheduler.CreateMultiLoop({
    loops = {
        visible_positions = {
            interval_ms = 16,
            max_elapsed_ms = 96
        },
        bulk_positions = {
            interval_ms = 16,
            max_elapsed_ms = 192
        },
        hot_data = {
            interval_ms = 33,
            max_elapsed_ms = 198
        },
        bulk_data = {
            interval_ms = 220,
            max_elapsed_ms = 1320
        }
    }
})

local commandRouter = nil

local function modulesReady()
    return Shared ~= nil and Bars ~= nil and SettingsUi ~= nil and Compat ~= nil
end

local function logModuleErrors()
    if #moduleErrors == 0 then
        return
    end
    for _, detail in ipairs(moduleErrors) do
        logger:Err("Module load error: " .. tostring(detail))
    end
end

local function safeBarsCall(label, fn)
    local ok = logger:Try(label, fn)
    return ok and true or false
end

local function logRuntimeSummary()
    local runtime = Compat.Get()
    local caps = runtime.caps or {}
    logger:Info(string.format(
        "Runtime render=%s sliders=%s anchor=%s statusbars=%s",
        caps.render_supported and "yes" or "no",
        caps.slider_factory and "yes" or "no",
        caps.nametag_anchor and "nametag" or (caps.screen_position and "screen" or "none"),
        caps.statusbar_factory and "yes" or "no"
    ))
    for _, warning in ipairs(runtime.warnings or {}) do
        logger:Info(warning)
    end
    for _, blocker in ipairs(runtime.blockers or {}) do
        logger:Err(tostring(blocker))
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

local function updateVisiblePositions()
    if Bars.UpdateVisiblePositions ~= nil then
        safeBarsCall("Bars.UpdateVisiblePositions", function()
            Bars.UpdateVisiblePositions()
        end)
        return
    end
    safeBarsCall("Bars.UpdateHotPositions", function()
        Bars.UpdateHotPositions()
    end)
end

local function updateBulkPositions()
    safeBarsCall("Bars.UpdateBulkPositions", function()
        Bars.UpdateBulkPositions()
    end)
end

local function updateHotData()
    safeBarsCall("Bars.UpdateHotData", function()
        Bars.UpdateHotData()
    end)
end

local function updateBulkData()
    safeBarsCall("Bars.UpdateBulkData", function()
        Bars.UpdateBulkData()
    end)
end

updateLoops:Get("visible_positions").callback = updateVisiblePositions
updateLoops:Get("bulk_positions").callback = updateBulkPositions
updateLoops:Get("hot_data").callback = updateHotData
updateLoops:Get("bulk_data").callback = updateBulkData

local function getPlayerName()
    if api.Unit == nil or api.Unit.GetUnitName == nil then
        return ""
    end
    local ok, name = pcall(function()
        return api.Unit:GetUnitName("player")
    end)
    if not ok then
        return ""
    end
    return tostring(name or "")
end

local function onCommand(ctx)
    local subcommand = string.lower(tostring(ctx.subcommand or ""))
    if subcommand == "" then
        SettingsUi.Toggle()
        return true
    end
    if subcommand == "on" then
        Shared.EnsureSettings().enabled = true
        Shared.SaveSettings()
        applyAll()
        return true
    end
    if subcommand == "off" then
        Shared.EnsureSettings().enabled = false
        Shared.SaveSettings()
        applyAll()
        return true
    end
    return false, "unhandled"
end

local function buildCommandRouter()
    local router = Commands.CreateRouter({
        logger = logger,
        get_player_name = getPlayerName,
        local_only = true
    })
    router:Add("!gb", onCommand)
    router:AddAlias("!gharkabars", "!gb")
    return router
end

local function onUpdate(dt)
    if not modulesReady() then
        return
    end

    local bulkPositionIntervalMs = 16
    if Bars.GetBulkPositionIntervalMs ~= nil then
        bulkPositionIntervalMs = tonumber(Bars.GetBulkPositionIntervalMs()) or 16
    end
    updateLoops:SetInterval("bulk_positions", bulkPositionIntervalMs)
    updateLoops:Tick(dt)
end

local function onUiReloaded()
    if not modulesReady() then
        return
    end

    updateLoops:Reset()
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
    if commandRouter == nil then
        return false
    end
    return commandRouter:DispatchMessage(message, name, unit)
end

local function onLoad()
    if not modulesReady() then
        logModuleErrors()
        bootstrapLogger:Err("Failed to load one or more modules.")
        return
    end

    logModuleErrors()
    Shared.LoadSettings()
    Compat.Probe(true)
    logRuntimeSummary()
    updateLoops:Reset()
    commandRouter = buildCommandRouter()

    safeBarsCall("Bars.Init(load)", function()
        Bars.Init()
    end)
    SettingsUi.Init(buildActions())
    safeBarsCall("Bars.Update(load)", function()
        Bars.Update()
    end)

    events:OnSafe("UPDATE", "UPDATE", onUpdate)
    events:OnSafe("UI_RELOADED", "UI_RELOADED", onUiReloaded)
    events:OnSafe("CHAT_MESSAGE", "CHAT_MESSAGE", onChatMessage)
    events:OptionalOnSafe("COMMUNITY_CHAT_MESSAGE", "COMMUNITY_CHAT_MESSAGE", onChatMessage)
    logger:Info("Loaded v" .. tostring(addon.version) .. ". Use the GB button for settings.")
end

local function onUnload()
    events:ClearAll()
    updateLoops:Reset()
    commandRouter = nil
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
