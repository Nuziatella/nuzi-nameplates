local api = require("api")

local Compat = {
    state = nil
}

local nuziCoreSliderFactory = nil

local function hasNuziCoreSliderFactory()
    if nuziCoreSliderFactory ~= nil then
        return nuziCoreSliderFactory and true or false
    end

    local ok, factory = pcall(require, "nuzi-core/ui/slider")
    nuziCoreSliderFactory = ok and type(factory) == "function"
    return nuziCoreSliderFactory
end

local function hasFunction(tbl, key)
    return type(tbl) == "table" and type(tbl[key]) == "function"
end

local function append(list, value)
    list[#list + 1] = value
end

local function buildRuntimeText(caps)
    local anchorText = caps.nametag_anchor and "Name tag" or (caps.screen_position and "Screen position" or "Unavailable")
    local sliderText = caps.slider_factory and (caps.nuzi_core_slider and "Nuzi Core" or "Available") or "Unavailable"
    local barsText = caps.statusbar_factory and "Available" or "Unavailable"
    return {
        string.format("Render: %s", caps.render_supported and "Supported" or "Blocked"),
        string.format("Anchoring: %s", anchorText),
        string.format("Sliders: %s | Status bars: %s", sliderText, barsText)
    }
end

function Compat.Probe(force)
    if Compat.state ~= nil and not force then
        return Compat.state
    end

    local caps = {
        create_window = hasFunction(api.Interface, "CreateWindow"),
        create_empty_window = hasFunction(api.Interface, "CreateEmptyWindow"),
        create_widget = hasFunction(api.Interface, "CreateWidget"),
        apply_button_skin = hasFunction(api.Interface, "ApplyButtonSkin"),
        nuzi_core_slider = hasNuziCoreSliderFactory(),
        addon_library_slider = type(api._Library) == "table"
            and type(api._Library.UI) == "table"
            and type(api._Library.UI.CreateSlider) == "function",
        file_read = hasFunction(api.File, "Read"),
        file_write = hasFunction(api.File, "Write"),
        save_settings = type(api.SaveSettings) == "function",
        root_window = api.rootWindow ~= nil,
        statusbar_factory = type(W_BAR) == "table" and type(W_BAR.CreateStatusBarOfRaidFrame) == "function",
        nametag_anchor = hasFunction(api.Unit, "GetUnitScreenNameTagOffset"),
        screen_position = hasFunction(api.Unit, "GetUnitScreenPosition"),
        unit_id = hasFunction(api.Unit, "GetUnitId"),
        unit_info = hasFunction(api.Unit, "GetUnitInfoById") or hasFunction(api.Unit, "UnitInfo"),
        chat_event = type(api.On) == "function",
        stock_target_frame = ADDON ~= nil and type(ADDON.GetContent) == "function" and UIC ~= nil and UIC.TARGET_UNITFRAME ~= nil
    }
    caps.slider_factory = caps.nuzi_core_slider or caps.addon_library_slider

    local blockers = {}
    local warnings = {}

    if not caps.create_empty_window then
        append(blockers, "CreateEmptyWindow unavailable")
    end
    if not caps.create_widget then
        append(blockers, "CreateWidget unavailable")
    end
    if not caps.statusbar_factory then
        append(blockers, "W_BAR.CreateStatusBarOfRaidFrame unavailable")
    end
    if not caps.screen_position and not caps.nametag_anchor then
        append(blockers, "No unit screen-position API available")
    end

    if not caps.slider_factory then
        append(warnings, "Slider widget unavailable; slider controls cannot be adjusted on this client.")
    end
    if not caps.nametag_anchor and caps.screen_position then
        append(warnings, "Name-tag anchoring unavailable; using unit screen position fallback.")
    end
    if not caps.apply_button_skin then
        append(warnings, "Button skin helper unavailable; buttons will use raw widget styling.")
    end
    if not caps.stock_target_frame then
        append(warnings, "Stock target frame content unavailable.")
    end

    caps.render_supported = #blockers == 0

    Compat.state = {
        caps = caps,
        blockers = blockers,
        warnings = warnings,
        runtime_lines = buildRuntimeText(caps)
    }
    return Compat.state
end

function Compat.Get()
    return Compat.Probe(false)
end

function Compat.GetCaps()
    return Compat.Get().caps
end

function Compat.IsRenderable()
    return Compat.Get().caps.render_supported and true or false
end

function Compat.GetWarnings()
    return Compat.Get().warnings
end

function Compat.GetBlockers()
    return Compat.Get().blockers
end

function Compat.GetRuntimeLines()
    return Compat.Get().runtime_lines
end

function Compat.GetRuntimeStatusText()
    local state = Compat.Get()
    if #state.blockers > 0 then
        return "Runtime blocked: " .. table.concat(state.blockers, "; ")
    end
    if #state.warnings > 0 then
        return "Runtime warnings: " .. table.concat(state.warnings, " ")
    end
    return "Runtime OK"
end

return Compat
