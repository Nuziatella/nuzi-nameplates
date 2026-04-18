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
local CreateNuziSlider = nil

pcall(function()
    CreateNuziSlider = require("nuzi-core/ui/slider")
end)

local SettingsUi = {
    button = nil,
    button_icon = nil,
    window = nil,
    controls = {},
    actions = nil,
    dragging = false,
    active_page = "general",
    page_widgets = { general = {}, layout = {}, text = {}, cc = {}, colors = {} },
    color_page = 1,
    color_page_count = 1,
    color_group_widgets = {},
    profile_items = {}
}

local BASE_WINDOW_WIDTH = 748
local BASE_WINDOW_HEIGHT = 884
local detectedAddonDir = nil

local function safeCall(fn)
    local ok, value = pcall(fn)
    if ok then
        return value
    end
    return nil
end

local function safeFree(widget)
    if widget == nil or api.Interface == nil or api.Interface.Free == nil then
        return
    end
    pcall(function()
        api.Interface:Free(widget)
    end)
end

local function safeDestroy(widget)
    if widget == nil then
        return
    end
    if widget.Show ~= nil then
        pcall(function()
            widget:Show(false)
        end)
    end
    if widget.Destroy ~= nil then
        pcall(function()
            widget:Destroy()
        end)
        return
    end
    safeFree(widget)
end

local function safeShow(widget, show)
    if widget ~= nil and widget.Show ~= nil then
        pcall(function()
            widget:Show(show and true or false)
        end)
    end
end

local function applyCommonWindowBehavior(window)
    if window == nil then
        return
    end
    safeCall(function()
        window:SetCloseOnEscape(false)
    end)
    safeCall(function()
        window:EnableHidingIsRemove(false)
    end)
    safeCall(function()
        window:SetUILayer("game")
    end)
end

local function isShiftDown()
    if api ~= nil and api.Input ~= nil and api.Input.IsShiftKeyDown ~= nil then
        local ok, down = pcall(function()
            return api.Input:IsShiftKeyDown()
        end)
        if ok then
            return down and true or false
        end
    end
    return false
end

local function normalizePath(path)
    return string.gsub(tostring(path or ""), "\\", "/")
end

local function trimText(value)
    local text = tostring(value or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function fileExists(path)
    if type(io) ~= "table" or type(io.open) ~= "function" then
        return false
    end
    local file = nil
    local ok = pcall(function()
        file = io.open(path, "rb")
    end)
    if ok and file ~= nil then
        pcall(function()
            file:close()
        end)
        return true
    end
    return false
end

local function addonDir()
    if detectedAddonDir ~= nil then
        return detectedAddonDir or nil
    end
    detectedAddonDir = false
    if type(debug) == "table" and type(debug.getinfo) == "function" then
        local info = debug.getinfo(1, "S")
        local source = type(info) == "table" and tostring(info.source or "") or ""
        if string.sub(source, 1, 1) == "@" then
            source = normalizePath(string.sub(source, 2))
            local folder = string.match(source, "^(.*)/[^/]+$")
            if type(folder) == "string" and folder ~= "" then
                detectedAddonDir = folder
                return folder
            end
        end
    end
    return nil
end

local function assetPath(relativePath)
    local rawRelative = normalizePath(relativePath)
    local strippedRelative = string.match(rawRelative, "^[^/]+/(.+)$") or rawRelative
    local candidates = {}
    local seen = {}
    local function addCandidate(path)
        path = normalizePath(path)
        if path == "" or seen[path] then
            return
        end
        seen[path] = true
        candidates[#candidates + 1] = path
    end
    local folder = addonDir()
    if folder ~= nil then
        addCandidate(folder .. "/" .. strippedRelative)
        addCandidate(folder .. "/" .. rawRelative)
    end
    local baseDir = normalizePath(type(api) == "table" and type(api.baseDir) == "string" and api.baseDir or "")
    if baseDir ~= "" then
        addCandidate(baseDir .. "/" .. rawRelative)
        addCandidate(baseDir .. "/" .. strippedRelative)
    end
    addCandidate(rawRelative)
    addCandidate(strippedRelative)
    for _, candidate in ipairs(candidates) do
        if fileExists(candidate) then
            return candidate
        end
    end
    return candidates[1] or rawRelative
end

local function createImageDrawable(widget, id, path, layer, width, height)
    if widget == nil then
        return nil
    end
    local drawable = safeCall(function()
        if widget.CreateImageDrawable ~= nil then
            return widget:CreateImageDrawable(id, layer or "artwork")
        end
        if widget.CreateDrawable ~= nil then
            return widget:CreateDrawable(id, layer or "artwork")
        end
        return nil
    end)
    if drawable == nil then
        return nil
    end
    safeCall(function()
        drawable:SetTexture(path)
    end)
    safeCall(function()
        drawable:AddAnchor("TOPLEFT", widget, 0, 0)
    end)
    safeCall(function()
        drawable:SetExtent(width, height)
    end)
    safeShow(drawable, true)
    return drawable
end

local function readOffset(widget)
    if widget == nil then
        return nil, nil
    end
    local ok = false
    local x, y = nil, nil
    if widget.GetEffectiveOffset ~= nil then
        ok, x, y = pcall(function()
            return widget:GetEffectiveOffset()
        end)
    end
    if (not ok or x == nil or y == nil) and widget.GetOffset ~= nil then
        ok, x, y = pcall(function()
            return widget:GetOffset()
        end)
    end
    if not ok then
        return nil, nil
    end
    return tonumber(x), tonumber(y)
end

local anchorToUiParent

local function applySavedPositions(settings)
    settings = settings or Shared.EnsureSettings()
    if SettingsUi.button ~= nil then
        local iconSettings = Shared.GetIconSettings ~= nil and Shared.GetIconSettings() or settings
        anchorToUiParent(
            SettingsUi.button,
            Shared.Clamp(iconSettings.button_x, 0, 4000, 40),
            Shared.Clamp(iconSettings.button_y, 0, 4000, 220)
        )
    end
    if SettingsUi.window ~= nil then
        anchorToUiParent(
            SettingsUi.window,
            Shared.Clamp(settings.window_x, 0, 4000, 520),
            Shared.Clamp(settings.window_y, 0, 4000, 90)
        )
    end
end

anchorToUiParent = function(widget, x, y)
    if widget == nil or widget.RemoveAllAnchors == nil or widget.AddAnchor == nil then
        return
    end
    safeCall(function()
        widget:RemoveAllAnchors()
        widget:AddAnchor("TOPLEFT", "UIParent", tonumber(x) or 0, tonumber(y) or 0)
    end)
end

local function persistPosition(kind, widget)
    local x, y = readOffset(widget)
    if x == nil or y == nil then
        return
    end
    anchorToUiParent(widget, x, y)
    local settings = Shared.EnsureSettings()
    if kind == "button" then
        if Shared.SaveIconPosition ~= nil then
            Shared.SaveIconPosition(x, y)
        else
            Shared.SetUiPosition(kind, x, y)
        end
        settings.button_x = x
        settings.button_y = y
        Shared.SaveSettings()
        return
    elseif kind == "window" then
        Shared.SetUiPosition(kind, x, y)
        settings.window_x = x
        settings.window_y = y
    end
    Shared.SaveSettings()
end

local function persistAllPositions()
    if SettingsUi.button ~= nil then
        persistPosition("button", SettingsUi.button)
    end
    if SettingsUi.window ~= nil then
        persistPosition("window", SettingsUi.window)
    end
end

local function snapshotPositions()
    local positions = {}
    positions.button_x, positions.button_y = readOffset(SettingsUi.button)
    positions.window_x, positions.window_y = readOffset(SettingsUi.window)
    return positions
end

local function attachShiftDrag(widget, kind, dragFlagKey)
    if widget == nil or widget.SetHandler == nil then
        return
    end
    if widget.RegisterForDrag ~= nil then
        widget:RegisterForDrag("LeftButton")
    end
    if widget.EnableDrag ~= nil then
        widget:EnableDrag(true)
    end
    widget:SetHandler("OnDragStart", function(self)
        if not isShiftDown() then
            return
        end
        if dragFlagKey ~= nil then
            SettingsUi[dragFlagKey] = true
        end
        if self.StartMoving ~= nil then
            self:StartMoving()
        end
        if api.Cursor ~= nil and api.Cursor.ClearCursor ~= nil then
            api.Cursor:ClearCursor()
        end
        if api.Cursor ~= nil and api.Cursor.SetCursorImage ~= nil then
            api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
        end
    end)
    widget:SetHandler("OnDragStop", function(self)
        if self.StopMovingOrSizing ~= nil then
            self:StopMovingOrSizing()
        end
        if dragFlagKey ~= nil then
            SettingsUi[dragFlagKey] = false
        end
        if api.Cursor ~= nil and api.Cursor.ClearCursor ~= nil then
            api.Cursor:ClearCursor()
        end
        persistPosition(kind, self)
    end)
end

local function getLauncherSize()
    local settings = Shared.EnsureSettings()
    local size = Shared.Clamp(settings.button_size, 32, 96, 48)
    settings.button_size = size
    return math.floor(size + 0.5)
end

local function applyLauncherLayout()
    local size = getLauncherSize()
    if SettingsUi.button ~= nil and SettingsUi.button.SetExtent ~= nil then
        SettingsUi.button:SetExtent(size, size)
    end
    if SettingsUi.button_icon ~= nil and SettingsUi.button_icon.SetExtent ~= nil then
        SettingsUi.button_icon:SetExtent(size, size)
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
    pcall(function()
        if label.SetAutoResize ~= nil then
            label:SetAutoResize(false)
        end
        if label.SetLimitWidth ~= nil then
            label:SetLimitWidth(true)
        end
    end)
    if label.style ~= nil then
        if label.style.SetFontSize ~= nil then
            label.style:SetFontSize(fontSize or 13)
        end
        if label.style.SetAlign ~= nil then
            label.style:SetAlign(ALIGN.LEFT)
        end
        if label.style.SetShadow ~= nil then
            label.style:SetShadow(true)
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

local function safeSetText(widget, text)
    if widget ~= nil and widget.SetText ~= nil then
        pcall(function()
            widget:SetText(tostring(text or ""))
        end)
    end
end

local function safeGetText(widget)
    if widget == nil or widget.GetText == nil then
        return ""
    end
    local text = ""
    pcall(function()
        text = widget:GetText() or ""
    end)
    return tostring(text or "")
end

local function createEdit(id, parent, text, x, y, width, height, maxLength, guideText)
    local field = nil
    pcall(function()
        if W_CTRL ~= nil and W_CTRL.CreateEdit ~= nil then
            field = W_CTRL.CreateEdit(id, parent)
        elseif api.Interface ~= nil and api.Interface.CreateWidget ~= nil then
            field = api.Interface:CreateWidget("edit", id, parent)
        end
    end)
    if field == nil then
        return nil
    end
    pcall(function()
        field:SetExtent(width or 160, height or 24)
        if field.AddAnchor ~= nil then
            local anchored = pcall(function()
                field:AddAnchor("TOPLEFT", parent, x, y)
            end)
            if not anchored then
                field:AddAnchor("TOPLEFT", x, y)
            end
        end
        if maxLength ~= nil and field.SetMaxTextLength ~= nil then
            field:SetMaxTextLength(maxLength)
        end
        if guideText ~= nil and field.CreateGuideText ~= nil then
            field:CreateGuideText(tostring(guideText))
        end
        safeSetText(field, text)
        if field.style ~= nil then
            if field.style.SetAlign ~= nil then
                field.style:SetAlign(ALIGN.LEFT)
            end
            if field.style.SetColor ~= nil then
                field.style:SetColor(0, 0, 0, 1)
            end
        end
        if field.Show ~= nil then
            field:Show(true)
        end
    end)
    return field
end

local function createComboBox(id, parent, items, x, y, width, height)
    local combo = nil
    pcall(function()
        if W_CTRL ~= nil and W_CTRL.CreateComboBox ~= nil then
            combo = W_CTRL.CreateComboBox(parent)
        elseif api.Interface ~= nil and api.Interface.CreateComboBox ~= nil then
            combo = api.Interface:CreateComboBox(parent)
        end
    end)
    if combo == nil then
        return nil
    end
    combo.__ghb_items = items or {}
    pcall(function()
        if combo.AddAnchor ~= nil then
            local anchored = pcall(function()
                combo:AddAnchor("TOPLEFT", parent, x, y)
            end)
            if not anchored then
                combo:AddAnchor("TOPLEFT", x, y)
            end
        end
        if combo.SetExtent ~= nil then
            combo:SetExtent(width or 180, height or 24)
        end
        if combo.AddItem ~= nil then
            for _, item in ipairs(combo.__ghb_items) do
                combo:AddItem(tostring(item))
            end
        else
            combo.dropdownItem = combo.__ghb_items
        end
        if combo.Show ~= nil then
            combo:Show(true)
        end
    end)
    return combo
end

local function setComboItems(ctrl, items)
    if ctrl == nil then
        return
    end
    ctrl.__ghb_items = items or {}
    if ctrl.AddItem ~= nil then
        pcall(function()
            if ctrl.Clear ~= nil then
                ctrl:Clear()
            elseif ctrl.RemoveAllItems ~= nil then
                ctrl:RemoveAllItems()
            end
            for _, item in ipairs(ctrl.__ghb_items) do
                ctrl:AddItem(tostring(item))
            end
        end)
        return
    end
    ctrl.dropdownItem = ctrl.__ghb_items
end

local function getComboIndexRaw(ctrl)
    if ctrl == nil then
        return nil
    end
    local raw = nil
    pcall(function()
        if ctrl.GetSelectedIndex ~= nil then
            raw = ctrl:GetSelectedIndex()
        elseif ctrl.GetSelIndex ~= nil then
            raw = ctrl:GetSelIndex()
        end
    end)
    return tonumber(raw)
end

local function setComboIndex1Based(ctrl, idx)
    if ctrl == nil or idx == nil then
        return
    end
    idx = tonumber(idx)
    if idx == nil then
        return
    end

    local function updateBase(raw)
        raw = tonumber(raw)
        if raw == nil then
            return
        end
        if raw == idx then
            ctrl.__ghb_index_base = 1
        elseif raw == (idx - 1) then
            ctrl.__ghb_index_base = 0
        end
    end

    if ctrl.Select ~= nil then
        local selValue = idx
        if ctrl.GetSelIndex ~= nil and ctrl.GetSelectedIndex == nil then
            ctrl.__ghb_index_base = 0
            selValue = idx - 1
        else
            ctrl.__ghb_index_base = 1
        end
        pcall(function()
            ctrl:Select(selValue)
        end)
        updateBase(getComboIndexRaw(ctrl))
        return
    end

    local function trySetter(setter, value)
        local ok = pcall(function()
            setter(ctrl, value)
        end)
        if not ok then
            return nil
        end
        return getComboIndexRaw(ctrl)
    end

    if ctrl.SetSelectedIndex ~= nil then
        ctrl.__ghb_index_base = nil
        local raw = trySetter(ctrl.SetSelectedIndex, idx)
        updateBase(raw)
        if ctrl.__ghb_index_base == nil then
            raw = trySetter(ctrl.SetSelectedIndex, idx - 1)
            updateBase(raw)
        end
        return
    end

    if ctrl.SetSelIndex ~= nil then
        ctrl.__ghb_index_base = 0
        updateBase(trySetter(ctrl.SetSelIndex, idx - 1))
    end
end

local function getComboIndex1Based(ctrl, maxCount)
    local raw = getComboIndexRaw(ctrl)
    if raw == nil then
        return nil
    end
    local base = ctrl.__ghb_index_base
    if base == nil then
        if raw == 0 then
            base = 0
        elseif maxCount ~= nil and raw == maxCount then
            base = 1
        elseif maxCount ~= nil and raw == (maxCount - 1) then
            base = 0
        else
            base = 1
        end
        ctrl.__ghb_index_base = base
    end
    if base == 0 then
        return raw + 1
    end
    return raw
end

local function createPlainButton(id, parent, x, y, width, height)
    local button = safeCall(function()
        if api.Interface ~= nil and api.Interface.CreateEmptyWindow ~= nil then
            return api.Interface:CreateEmptyWindow(id, "UIParent")
        end
        return nil
    end)
    if button == nil then
        if parent ~= nil and parent.CreateChildWidget ~= nil then
            button = safeCall(function()
                return parent:CreateChildWidget("button", id, 0, true)
            end)
        else
            button = safeCall(function()
                return api.Interface:CreateWidget("button", id, parent)
            end)
        end
    end
    if button == nil then
        return nil
    end
    if button.RemoveAllAnchors ~= nil and button.AddAnchor ~= nil then
        safeCall(function()
            button:RemoveAllAnchors()
            button:AddAnchor("TOPLEFT", "UIParent", x, y)
        end)
    else
        button:AddAnchor("TOPLEFT", x, y)
    end
    button:SetExtent(width or 48, height or 48)
    if button.SetText ~= nil then
        button:SetText("")
    end
    applyCommonWindowBehavior(button)
    safeShow(button, true)
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

local function createSlider(id, parent, text, x, y, minValue, maxValue, options)
    options = type(options) == "table" and options or {}
    local labelWidth = tonumber(options.label_width) or 120
    local sliderWidth = tonumber(options.slider_width) or 200
    local valueWidth = tonumber(options.value_width) or 60
    local sliderOffset = tonumber(options.slider_offset) or (labelWidth + 12)
    local valueOffset = tonumber(options.value_offset) or (sliderOffset + sliderWidth + 12)
    local label = createLabel(id .. "Label", parent, text, x, y, 13, labelWidth)
    local slider = nil
    if CreateNuziSlider ~= nil then
        local ok, res = pcall(function()
            return CreateNuziSlider(id, parent)
        end)
        if ok then
            slider = res
        end
    end
    if slider == nil and api._Library ~= nil and api._Library.UI ~= nil and api._Library.UI.CreateSlider ~= nil then
        local ok, res = pcall(function()
            return api._Library.UI.CreateSlider(id, parent)
        end)
        if ok then
            slider = res
        end
    end
    if slider ~= nil then
        slider:AddAnchor("TOPLEFT", x + sliderOffset, y - 4)
        slider:SetExtent(sliderWidth, 26)
        slider:SetMinMaxValues(minValue, maxValue)
        if slider.SetStep ~= nil then
            slider:SetStep(1)
        end
    end
    local value = createLabel(id .. "Value", parent, "0", x + valueOffset, y, 13, valueWidth)
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

local function syncProfileNameInput(text)
    local input = SettingsUi.controls.profile_name_input
    if input == nil then
        return
    end
    local current = safeGetText(input)
    local lastSynced = tostring(input.__ghb_last_synced_text or "")
    local target = tostring(text or "")
    if current == "" or current == lastSynced then
        safeSetText(input, target)
        input.__ghb_last_synced_text = target
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
    local launcherSlider = SettingsUi.controls.global_slider_button_size
    local launcherValue = SettingsUi.controls.global_slider_val_button_size
    if launcherSlider ~= nil and launcherSlider.SetValue ~= nil then
        launcherSlider:SetValue(getLauncherSize(), false)
    end
    if launcherValue ~= nil and launcherValue.SetText ~= nil then
        launcherValue:SetText(tostring(getLauncherSize()))
    end
    SettingsUi.profile_items = Shared.ListProfiles()
    local profileNames = {}
    local activeIndex = 1
    for index, profile in ipairs(SettingsUi.profile_items) do
        profileNames[index] = tostring(profile.file_name or "")
        if profile.is_active then
            activeIndex = index
        end
    end
    local profileDropdown = SettingsUi.controls.profile_dropdown
    if profileDropdown ~= nil then
        setComboItems(profileDropdown, profileNames)
        if #profileNames > 0 then
            setComboIndex1Based(profileDropdown, activeIndex)
        end
    end
    syncProfileNameInput(Shared.GetActiveProfileFileName())
    applyLauncherLayout()
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

local function getSelectedProfilePath()
    local dropdown = SettingsUi.controls.profile_dropdown
    local items = SettingsUi.profile_items or {}
    local index = getComboIndex1Based(dropdown, #items)
    if index == nil or items[index] == nil then
        return nil
    end
    return items[index].path
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
        applyLauncherLayout = applyLauncherLayout,
        setStatus = setStatus,
        refreshControls = refreshControls,
        nextOptionValue = nextOptionValue
    }
end

local function collectWidgetRefs(value, seen, out)
    if value == nil then
        return
    end
    if type(value) ~= "table" then
        return
    end
    if value.Show ~= nil or value.SetHandler ~= nil or value.AddAnchor ~= nil or value.RemoveAllAnchors ~= nil then
        if not seen[value] then
            seen[value] = true
            table.insert(out, value)
        end
        return
    end
    for _, nested in pairs(value) do
        collectWidgetRefs(nested, seen, out)
    end
end

local function freeTrackedWidgets()
    local seen = {}
    local widgets = {}
    collectWidgetRefs(SettingsUi.controls, seen, widgets)
    collectWidgetRefs(SettingsUi.page_widgets, seen, widgets)
    collectWidgetRefs(SettingsUi.color_group_widgets, seen, widgets)

    for _, widget in ipairs(widgets) do
        if widget ~= SettingsUi.window and widget ~= SettingsUi.button then
            safeFree(widget)
        end
    end
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
    applyCommonWindowBehavior(wnd)
    local settings = Shared.EnsureSettings()
    anchorToUiParent(
        wnd,
        Shared.Clamp(settings.window_x, 0, 4000, 520),
        Shared.Clamp(settings.window_y, 0, 4000, 90)
    )
    attachShiftDrag(wnd, "window", nil)

    createLabel("ghbTitle", wnd, "Gharka Bars", 24, 18, 20, 240)
    createLabel("ghbSubtitle", wnd, "Shift+drag to move | presets and launcher controls live on General.", 24, 44, 12, 620)
    local tabs = {
        { key = "general", text = "General", x = 24 },
        { key = "layout", text = "Layout", x = 132 },
        { key = "text", text = "Text", x = 240 },
        { key = "cc", text = "CC", x = 348 },
        { key = "colors", text = "Colors", x = 456 }
    }
    for _, tab in ipairs(tabs) do
        local btn = createButton("ghbTab" .. tab.key, wnd, tab.text, tab.x, 68, 100, 28)
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

    SettingsUi.controls.status_label = createLabel("ghbStatus", wnd, "", 24, 776, 12, 700)
    local saveBtn = createButton("ghbSave", wnd, "Save", 24, 808, 72, 28)
    local profileInput = createEdit("ghbProfileName", wnd, "", 104, 810, 150, 24, 48, "Profile name")
    local profileDropdown = createComboBox("ghbProfileDropdown", wnd, { Shared.GetActiveProfileFileName() }, 264, 810, 166, 24)
    local loadBtn = createButton("ghbLoadProfile", wnd, "Load", 438, 808, 72, 28)
    local resetStyleBtn = createButton("ghbResetStyle", wnd, "Reset Style", 520, 808, 96, 28)
    local resetAllBtn = createButton("ghbResetAll", wnd, "Reset All", 624, 808, 96, 28)

    SettingsUi.controls.profile_name_input = profileInput
    SettingsUi.controls.profile_dropdown = profileDropdown

    saveBtn:SetHandler("OnClick", function()
        local profileName = trimText(safeGetText(profileInput))
        local ok, result = nil, nil
        if profileName ~= "" then
            ok, result = Shared.SaveSettingsAsProfile(profileName)
        else
            ok, result = Shared.SaveSettings()
            if ok then
                result = Shared.GetActiveProfileFileName()
            end
        end
        if ok then
            applyChanges()
            refreshControls()
            safeSetText(profileInput, Shared.GetActiveProfileFileName())
            if profileInput ~= nil then
                profileInput.__ghb_last_synced_text = Shared.GetActiveProfileFileName()
            end
            setStatus("Saved profile: " .. tostring(result or Shared.GetActiveProfileFileName()))
        else
            setStatus("Save failed: " .. tostring(result))
        end
    end)
    loadBtn:SetHandler("OnClick", function()
        local profilePath = getSelectedProfilePath()
        if profilePath == nil then
            setStatus("Load failed: select a profile")
            return
        end
        local ok, result = Shared.LoadProfile(profilePath)
        if ok then
            applyChanges()
            refreshControls()
            safeSetText(profileInput, Shared.GetActiveProfileFileName())
            if profileInput ~= nil then
                profileInput.__ghb_last_synced_text = Shared.GetActiveProfileFileName()
            end
            setStatus("Loaded profile: " .. tostring(result or Shared.GetActiveProfileFileName()))
        else
            setStatus("Load failed: " .. tostring(result))
        end
    end)
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
    local btn = createPlainButton(
        Shared.CONSTANTS.BUTTON_ID, parent,
        Shared.Clamp(settings.button_x, 0, 4000, 40),
        Shared.Clamp(settings.button_y, 0, 4000, 220), getLauncherSize(), getLauncherSize()
    )
    SettingsUi.button = btn
    SettingsUi.button_icon = createImageDrawable(
        btn,
        "gharkaBarsSettingsButtonIcon",
        assetPath("gharka-bars/icon_launcher.png"),
        "artwork",
        getLauncherSize(),
        getLauncherSize()
    )
    if SettingsUi.button_icon == nil and btn.SetText ~= nil then
        btn:SetText("GB")
    end
    applyLauncherLayout()
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
    attachShiftDrag(btn, "button", "dragging")
end

function SettingsUi.Init(actions)
    SettingsUi.actions = actions or {}
    ensureButton()
    applySavedPositions()
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
    applySavedPositions()
    applyWindowScale()
    local show = true
    if SettingsUi.window.IsVisible ~= nil then
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
end

function SettingsUi.GetPositions()
    return snapshotPositions()
end

function SettingsUi.SavePositions()
    local positions = snapshotPositions()
    local settings = Shared.EnsureSettings()
    if positions.button_x ~= nil then
        if Shared.SaveIconPosition ~= nil then
            Shared.SaveIconPosition(positions.button_x, positions.button_y)
        else
            Shared.SetUiPosition("button", positions.button_x, positions.button_y)
        end
        settings.button_x = positions.button_x
    end
    if positions.button_y ~= nil then
        settings.button_y = positions.button_y
    end
    if positions.window_x ~= nil then
        Shared.SetUiPosition("window", positions.window_x, positions.window_y)
        settings.window_x = positions.window_x
    end
    if positions.window_y ~= nil then
        settings.window_y = positions.window_y
    end
    Shared.SaveSettings()
    applySavedPositions(settings)
    return positions
end

function SettingsUi.Unload()
    freeTrackedWidgets()
    safeDestroy(SettingsUi.window)
    safeDestroy(SettingsUi.button)
    SettingsUi.button = nil
    SettingsUi.button_icon = nil
    SettingsUi.window = nil
    SettingsUi.controls = {}
    SettingsUi.dragging = false
    SettingsUi.active_page = "general"
    SettingsUi.page_widgets = { general = {}, layout = {}, text = {}, cc = {}, colors = {} }
    SettingsUi.color_page = 1
    SettingsUi.color_page_count = 1
    SettingsUi.color_group_widgets = {}
    SettingsUi.profile_items = {}
end

return SettingsUi
