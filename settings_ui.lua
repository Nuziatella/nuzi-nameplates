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
local Schema = loadModule("schema")
local Pages = loadModule("settings_ui_pages")
local Compat = loadModule("compat")

local SettingsUi = {
    button = nil,
    window = nil,
    controls = {},
    actions = nil,
    dragging = false,
    active_page = "general",
    page_widgets = { general = {}, layout = {}, text = {}, cc = {}, colors = {} },
    color_page = 1,
    color_page_count = 1,
    color_group_widgets = {}
}

local BASE_WINDOW_WIDTH = 760
local BASE_WINDOW_HEIGHT = 900

local function safeShow(widget, show)
    if widget ~= nil and widget.Show ~= nil then
        pcall(function()
            widget:Show(show and true or false)
        end)
    end
end

local function addPageWidget(page, widget)
    if widget ~= nil and SettingsUi.page_widgets[page] ~= nil then
        table.insert(SettingsUi.page_widgets[page], widget)
    end
    return widget
end

local function createLabel(id, parent, text, x, y, fontSize, width)
    local label = api.Interface:CreateWidget("label", id, parent)
    label:AddAnchor("TOPLEFT", x, y)
    label:SetExtent(width or 220, 18)
    label:SetText(text)
    if label.style ~= nil then
        if label.style.SetFontSize ~= nil then
            label.style:SetFontSize(fontSize or 13)
        end
        if label.style.SetAlign ~= nil then
            label.style:SetAlign(ALIGN.LEFT)
        end
    end
    return label
end

local function createButton(id, parent, text, x, y, width, height)
    local button = api.Interface:CreateWidget("button", id, parent)
    button:AddAnchor("TOPLEFT", x, y)
    button:SetExtent(width or 100, height or 26)
    button:SetText(text)
    if api.Interface ~= nil and api.Interface.ApplyButtonSkin ~= nil then
        pcall(function()
            api.Interface:ApplyButtonSkin(button, BUTTON_BASIC.DEFAULT)
        end)
    end
    return button
end

local function createCheckbox(id, parent, text, x, y, labelWidth)
    local box = api.Interface:CreateWidget("button", id, parent)
    box:AddAnchor("TOPLEFT", x, y)
    box:SetExtent(26, 26)
    box:SetText("[ ]")
    local label = createLabel(id .. "Label", parent, text, x + 36, y + 4, 13, labelWidth or 250)
    local proxy = { button = box, label = label, checked = false }
    function proxy:SetChecked(v)
        self.checked = v and true or false
        if self.button ~= nil and self.button.SetText ~= nil then
            self.button:SetText(self.checked and "[X]" or "[ ]")
        end
    end
    function proxy:SetHandler(eventName, fn)
        if eventName == "OnClick" and self.button ~= nil and self.button.SetHandler ~= nil then
            self.button:SetHandler("OnClick", fn)
        end
    end
    proxy:SetChecked(false)
    return proxy
end

local function createSlider(id, parent, text, x, y, minValue, maxValue)
    local label = createLabel(id .. "Label", parent, text, x, y, 13, 180)
    local slider = nil
    if api._Library ~= nil and api._Library.UI ~= nil and api._Library.UI.CreateSlider ~= nil then
        local ok, res = pcall(function()
            return api._Library.UI.CreateSlider(id, parent)
        end)
        if ok then
            slider = res
        end
    end
    if slider ~= nil then
        slider:AddAnchor("TOPLEFT", x + 190, y - 4)
        slider:SetExtent(200, 26)
        slider:SetMinMaxValues(minValue, maxValue)
        if slider.SetStep ~= nil then
            slider:SetStep(1)
        end
    end
    local value = createLabel(id .. "Value", parent, "0", x + 400, y, 13, 60)
    return label, slider, value
end

local function createChoiceRow(id, parent, text, x, y, width)
    local label = createLabel(id .. "Label", parent, text, x, y, 13, 180)
    local button = createButton(id .. "Button", parent, "", x + 190, y - 2, width or 180, 28)
    return label, button
end

local function optionLabel(choiceDef, value)
    for _, option in ipairs(choiceDef.options or {}) do
        if tostring(option.value) == tostring(value) then
            return tostring(option.label)
        end
    end
    return tostring(value or "")
end

local function optionDescription(choiceDef, value)
    for _, option in ipairs(choiceDef.options or {}) do
        if tostring(option.value) == tostring(value) then
            return tostring(option.description or option.label or value or "")
        end
    end
    return ""
end

local function optionButtonControlKey(choiceKey, optionValue)
    return "global_choice_option_" .. tostring(choiceKey or "") .. "_" .. tostring(optionValue or "")
end

local function nextOptionValue(choiceDef, currentValue)
    local options = choiceDef.options or {}
    if #options == 0 then
        return currentValue
    end
    for index, option in ipairs(options) do
        if tostring(option.value) == tostring(currentValue) then
            local nextIndex = index + 1
            if nextIndex > #options then
                nextIndex = 1
            end
            return options[nextIndex].value
        end
    end
    return options[1].value
end

local function applyChanges()
    if SettingsUi.actions ~= nil and SettingsUi.actions.apply ~= nil then
        SettingsUi.actions.apply()
    end
end

local function setStatus(text)
    local label = SettingsUi.controls.status_label
    if label ~= nil and label.SetText ~= nil then
        label:SetText(tostring(text or ""))
    end
end

local function applyWindowScale()
    if SettingsUi.window == nil or SettingsUi.window.SetScale == nil then
        return
    end
    local screenWidth = 1920
    local screenHeight = 1080
    pcall(function()
        if api.Interface ~= nil and api.Interface.GetScreenWidth ~= nil then
            screenWidth = tonumber(api.Interface:GetScreenWidth()) or screenWidth
        end
        if api.Interface ~= nil and api.Interface.GetScreenHeight ~= nil then
            screenHeight = tonumber(api.Interface:GetScreenHeight()) or screenHeight
        end
    end)
    local widthScale = (screenWidth - 40) / BASE_WINDOW_WIDTH
    local heightScale = (screenHeight - 60) / BASE_WINDOW_HEIGHT
    local scale = math.min(1, widthScale, heightScale)
    if scale < 0.7 then
        scale = 0.7
    end
    pcall(function()
        SettingsUi.window:SetScale(scale)
    end)
end

local function refreshColorPage()
    if type(SettingsUi.color_group_widgets) ~= "table" then
        return
    end
    local currentPage = Shared.Clamp(SettingsUi.color_page, 1, SettingsUi.color_page_count or 1, 1)
    SettingsUi.color_page = currentPage
    for _, entry in pairs(SettingsUi.color_group_widgets) do
        local show = entry.page == currentPage
        for _, widget in ipairs(entry.widgets or {}) do
            safeShow(widget, show and SettingsUi.active_page == "colors")
        end
    end
    if SettingsUi.controls.color_page_label ~= nil and SettingsUi.controls.color_page_label.SetText ~= nil then
        SettingsUi.controls.color_page_label:SetText(string.format("Page %d / %d", currentPage, math.max(1, SettingsUi.color_page_count or 1)))
    end
    if SettingsUi.controls.color_prev ~= nil and SettingsUi.controls.color_prev.Enable ~= nil then
        pcall(function()
            SettingsUi.controls.color_prev:Enable(currentPage > 1)
        end)
    end
    if SettingsUi.controls.color_next ~= nil and SettingsUi.controls.color_next.Enable ~= nil then
        pcall(function()
            SettingsUi.controls.color_next:Enable(currentPage < math.max(1, SettingsUi.color_page_count or 1))
        end)
    end
end

local function setColorPage(page)
    SettingsUi.color_page = Shared.Clamp(page, 1, SettingsUi.color_page_count or 1, 1)
    refreshColorPage()
end

local function setActivePage(page)
    SettingsUi.active_page = page
    for name, widgets in pairs(SettingsUi.page_widgets) do
        local show = name == page
        for _, widget in ipairs(widgets) do
            safeShow(widget, show)
        end
    end
    local tabs = {
        { key = "general", text = "General" },
        { key = "layout", text = "Layout" },
        { key = "text", text = "Text" },
        { key = "cc", text = "CC" },
        { key = "colors", text = "Colors" }
    }
    for _, tab in ipairs(tabs) do
        local ctrl = SettingsUi.controls["tab_" .. tab.key]
        if ctrl ~= nil and ctrl.SetText ~= nil then
            ctrl:SetText(page == tab.key and ("[" .. tab.text .. "]") or tab.text)
        end
    end
    if page == "colors" then
        refreshColorPage()
    end
end

local function refreshSliderValues(prefix, list, style)
    for _, item in ipairs(list or {}) do
        local ctrl = SettingsUi.controls[prefix .. item.key]
        local val = SettingsUi.controls[prefix .. "val_" .. item.key]
        local display = tonumber(style[item.key]) or 0
        if ctrl ~= nil and ctrl.SetValue ~= nil then
            ctrl:SetValue(display, false)
        end
        if val ~= nil and val.SetText ~= nil then
            val:SetText(tostring(math.floor(display + 0.5)))
        end
    end
end

local function refreshColorValues(style)
    for _, group in ipairs(Schema.COLOR_GROUPS or {}) do
        local color = type(style[group.key]) == "table" and style[group.key] or { 255, 255, 255, 255 }
        for channelIndex = 1, 3 do
            local slider = SettingsUi.controls["color_slider_" .. group.key .. "_" .. channelIndex]
            local value = SettingsUi.controls["color_slider_val_" .. group.key .. "_" .. channelIndex]
            local display = tonumber(color[channelIndex]) or 0
            if slider ~= nil and slider.SetValue ~= nil then
                slider:SetValue(display, false)
            end
            if value ~= nil and value.SetText ~= nil then
                value:SetText(tostring(math.floor(display + 0.5)))
            end
        end
    end
end

local function refreshControls()
    local settings = Shared.EnsureSettings()
    local style = Shared.GetStyleSettings()
    local runtime = Compat ~= nil and Compat.Get() or nil
    for _, item in ipairs(Schema.GLOBAL_TOGGLES) do
        local ctrl = SettingsUi.controls["global_" .. item.key]
        if ctrl ~= nil and ctrl.SetChecked ~= nil then
            ctrl:SetChecked(settings[item.key] and true or false)
        end
    end
    for _, item in ipairs(Schema.GLOBAL_CHOICES or {}) do
        local ctrl = SettingsUi.controls["global_choice_" .. item.key]
        if ctrl ~= nil and ctrl.SetText ~= nil then
            ctrl:SetText(optionLabel(item, settings[item.key]))
        end
        for _, option in ipairs(item.options or {}) do
            local optionCtrl = SettingsUi.controls[optionButtonControlKey(item.key, option.value)]
            if optionCtrl ~= nil and optionCtrl.SetText ~= nil then
                local label = tostring(option.label or option.value or "")
                if tostring(settings[item.key]) == tostring(option.value) then
                    optionCtrl:SetText("[" .. label .. "]")
                else
                    optionCtrl:SetText(label)
                end
            end
        end
        local desc = SettingsUi.controls["global_choice_desc_" .. item.key]
        if desc ~= nil and desc.SetText ~= nil then
            desc:SetText(optionDescription(item, settings[item.key]))
        end
    end
    for _, item in ipairs(Schema.STYLE_TOGGLES) do
        local ctrl = SettingsUi.controls["style_toggle_" .. item.key]
        if ctrl ~= nil and ctrl.SetChecked ~= nil then
            ctrl:SetChecked(style[item.key] and true or false)
        end
    end
    refreshSliderValues("style_slider_", Schema.LAYOUT_SLIDERS, style)
    refreshSliderValues("style_slider_", Schema.TEXT_SLIDERS, style)
    for _, item in ipairs(Schema.CC_TOGGLES or {}) do
        local ctrl = SettingsUi.controls["cc_toggle_" .. item.key]
        if ctrl ~= nil and ctrl.SetChecked ~= nil then
            ctrl:SetChecked(style[item.key] and true or false)
        end
    end
    for _, item in ipairs(Schema.CC_CHOICES or {}) do
        local ctrl = SettingsUi.controls["cc_choice_" .. item.key]
        if ctrl ~= nil and ctrl.SetText ~= nil then
            ctrl:SetText(optionLabel(item, style[item.key]))
        end
    end
    refreshSliderValues("cc_slider_", Schema.CC_SLIDERS, style)
    for _, item in ipairs(Schema.STYLE_CHOICES) do
        local ctrl = SettingsUi.controls["style_choice_" .. item.key]
        if ctrl ~= nil and ctrl.SetText ~= nil then
            ctrl:SetText(optionLabel(item, style[item.key]))
        end
    end
    refreshColorValues(style)
    local runtimeLines = runtime ~= nil and runtime.runtime_lines or {}
    for index = 1, 3 do
        local label = SettingsUi.controls["runtime_line_" .. tostring(index)]
        if label ~= nil and label.SetText ~= nil then
            label:SetText(tostring(runtimeLines[index] or ""))
        end
    end
    local runtimeWarn = SettingsUi.controls.runtime_warning
    if runtimeWarn ~= nil and runtimeWarn.SetText ~= nil then
        runtimeWarn:SetText(Compat ~= nil and Compat.GetRuntimeStatusText() or "")
    end
    setActivePage(SettingsUi.active_page or "general")
    refreshColorPage()
end

local function runAction(key, okText, failText, refreshAfter)
    if type(SettingsUi.actions) ~= "table" or type(SettingsUi.actions[key]) ~= "function" then
        setStatus(failText .. ": unavailable")
        return
    end
    local ok, a, b = pcall(function()
        return SettingsUi.actions[key]()
    end)
    if ok and (a == true or a == nil) then
        setStatus(okText .. (type(b) == "string" and b ~= "" and (": " .. b) or ""))
        if refreshAfter then
            refreshControls()
        end
        applyChanges()
    else
        setStatus(failText .. ": " .. tostring(ok and b or a))
    end
end

local function buildContext()
    return {
        Schema = Schema,
        Shared = Shared,
        SettingsUi = SettingsUi,
        addPageWidget = addPageWidget,
        createLabel = createLabel,
        createButton = createButton,
        createCheckbox = createCheckbox,
        createSlider = createSlider,
        createChoiceRow = createChoiceRow,
        applyChanges = applyChanges,
        refreshControls = refreshControls,
        nextOptionValue = nextOptionValue
    }
end

local function ensureWindow()
    if SettingsUi.window ~= nil then
        return
    end
    local ok, wnd = pcall(function()
        return api.Interface:CreateWindow(Shared.CONSTANTS.WINDOW_ID, "Gharka Bars", BASE_WINDOW_WIDTH, BASE_WINDOW_HEIGHT)
    end)
    if not ok or wnd == nil then
        SettingsUi.window = nil
        return
    end
    SettingsUi.window = wnd
    wnd:AddAnchor("CENTER", "UIParent", 0, 0)
    if wnd.SetHandler ~= nil then
        wnd:SetHandler("OnCloseByEsc", function()
            safeShow(wnd, false)
        end)
    end

    createLabel("ghbTitle", wnd, "Gharka Bars", 24, 18, 20, 240)
    local tabs = {
        { key = "general", text = "General", x = 24 },
        { key = "layout", text = "Layout", x = 152 },
        { key = "text", text = "Text", x = 280 },
        { key = "cc", text = "CC", x = 408 },
        { key = "colors", text = "Colors", x = 536 }
    }
    for _, tab in ipairs(tabs) do
        local btn = createButton("ghbTab" .. tab.key, wnd, tab.text, tab.x, 72, 120, 28)
        SettingsUi.controls["tab_" .. tab.key] = btn
        btn:SetHandler("OnClick", function()
            setActivePage(tab.key)
        end)
    end

    local ctx = buildContext()
    Pages.BuildGeneralPage(ctx, wnd)
    Pages.BuildLayoutPage(ctx, wnd)
    Pages.BuildTextPage(ctx, wnd)
    Pages.BuildCcPage(ctx, wnd)
    Pages.BuildColorsPage(ctx, wnd)

    SettingsUi.controls.status_label = createLabel("ghbStatus", wnd, "", 24, 822, 12, 900)
    local saveBtn = createButton("ghbSave", wnd, "Save", 24, 852, 100, 28)
    local backupBtn = createButton("ghbBackup", wnd, "Backup", 134, 852, 100, 28)
    local importBtn = createButton("ghbImport", wnd, "Import", 244, 852, 100, 28)
    local resetStyleBtn = createButton("ghbResetStyle", wnd, "Reset Style", 384, 852, 110, 28)
    local resetAllBtn = createButton("ghbResetAll", wnd, "Reset All", 504, 852, 110, 28)
    local closeBtn = createButton("ghbClose", wnd, "Close", 646, 852, 90, 28)

    saveBtn:SetHandler("OnClick", function() runAction("save", "Saved", "Save failed", false) end)
    backupBtn:SetHandler("OnClick", function() runAction("backup", "Backup saved", "Backup failed", false) end)
    importBtn:SetHandler("OnClick", function() runAction("import", "Imported backup", "Import failed", true) end)
    resetStyleBtn:SetHandler("OnClick", function()
        Shared.ResetStyleSettings()
        applyChanges()
        refreshControls()
        setStatus("Reset style")
    end)
    resetAllBtn:SetHandler("OnClick", function()
        Shared.ResetAllSettings()
        applyChanges()
        refreshControls()
        setStatus("Reset all settings")
    end)
    closeBtn:SetHandler("OnClick", function()
        safeShow(wnd, false)
    end)

    refreshControls()
    applyWindowScale()
    safeShow(wnd, false)
end

local function ensureButton()
    if SettingsUi.button ~= nil then
        return
    end
    local settings = Shared.EnsureSettings()
    local parent = api.rootWindow
    if parent == nil then
        return
    end
    local btn = createButton(
        Shared.CONSTANTS.BUTTON_ID, parent, "GB",
        Shared.Clamp(settings.button_x, 0, 4000, 70),
        Shared.Clamp(settings.button_y, 0, 4000, 390), 42, 26
    )
    SettingsUi.button = btn
    if btn.RegisterForDrag ~= nil then
        btn:RegisterForDrag("LeftButton")
    end
    if btn.EnableDrag ~= nil then
        btn:EnableDrag(true)
    end
    btn:SetHandler("OnClick", function()
        if SettingsUi.dragging then
            SettingsUi.dragging = false
            return
        end
        ensureWindow()
        local show = true
        if SettingsUi.window ~= nil and SettingsUi.window.IsVisible ~= nil then
            local ok, visible = pcall(function()
                return SettingsUi.window:IsVisible()
            end)
            if ok then
                show = not visible
            end
        end
        safeShow(SettingsUi.window, show)
        if show then
            refreshControls()
        end
    end)
    btn:SetHandler("OnDragStart", function(self)
        if api.Input ~= nil and api.Input.IsShiftKeyDown ~= nil then
            local ok, isDown = pcall(function()
                return api.Input:IsShiftKeyDown()
            end)
            if ok and not isDown then
                return
            end
        end
        SettingsUi.dragging = true
        if self.StartMoving ~= nil then
            self:StartMoving()
        end
    end)
    btn:SetHandler("OnDragStop", function(self)
        if self.StopMovingOrSizing ~= nil then
            self:StopMovingOrSizing()
        end
        if self.GetOffset ~= nil then
            local ok, x, y = pcall(function()
                return self:GetOffset()
            end)
            if ok then
                local settingsNow = Shared.EnsureSettings()
                settingsNow.button_x = tonumber(x) or settingsNow.button_x
                settingsNow.button_y = tonumber(y) or settingsNow.button_y
                Shared.SaveSettings()
            end
        end
    end)
end

function SettingsUi.Init(actions)
    SettingsUi.actions = actions or {}
    ensureButton()
    if SettingsUi.window ~= nil then
        refreshControls()
    end
end

function SettingsUi.Refresh()
    if SettingsUi.window ~= nil then
        refreshControls()
    end
end

function SettingsUi.Toggle()
    ensureWindow()
    if SettingsUi.window == nil then
        return
    end
    applyWindowScale()
    safeShow(SettingsUi.window, true)
    refreshControls()
end

function SettingsUi.Unload()
    if SettingsUi.window ~= nil and api.Interface ~= nil and api.Interface.Free ~= nil then
        pcall(function()
            api.Interface:Free(SettingsUi.window)
        end)
    end
    if SettingsUi.button ~= nil and api.Interface ~= nil and api.Interface.Free ~= nil then
        pcall(function()
            api.Interface:Free(SettingsUi.button)
        end)
    end
    SettingsUi.button = nil
    SettingsUi.window = nil
    SettingsUi.controls = {}
    SettingsUi.dragging = false
    SettingsUi.active_page = "general"
    SettingsUi.page_widgets = { general = {}, layout = {}, text = {}, cc = {}, colors = {} }
    SettingsUi.color_page = 1
    SettingsUi.color_page_count = 1
    SettingsUi.color_group_widgets = {}
end

return SettingsUi
