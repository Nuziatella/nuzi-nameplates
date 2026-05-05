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
local Helpers = loadModule("bar_helpers")
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
    color_cards = {},
    color_picker = {
        overlay = nil,
        panel = nil,
        palette_cells = {},
        active_group = nil,
        original_color = nil
    },
    profile_items = {}
}

local BASE_WINDOW_WIDTH = 980
local BASE_WINDOW_HEIGHT = 884
local detectedAddonDir = nil
local THEME = {
    title = { 0.98, 0.90, 0.72, 1 },
    heading = { 0.96, 0.88, 0.70, 1 },
    text = { 0.95, 0.93, 0.90, 1 },
    hint = { 0.78, 0.74, 0.68, 1 }
}
local PAGE_DEFS = {
    {
        key = "general",
        label = "General",
        title = "General",
        summary = "Profiles, presets, launcher settings, and live runtime status."
    },
    {
        key = "layout",
        label = "Layout",
        title = "Layout",
        summary = "Visibility, layout modes, and overall frame sizing."
    },
    {
        key = "text",
        label = "Text",
        title = "Text",
        summary = "Font sizing, clipping, and value offset tuning."
    },
    {
        key = "cc",
        label = "Crowd Control",
        title = "Crowd Control",
        summary = "Filters, tracking scope, icon rules, and placement."
    },
    {
        key = "colors",
        label = "Colors",
        title = "Colors",
        summary = "Per-element palette tuning for bars, text, and state colors."
    }
}

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
        return api.Input:IsShiftKeyDown() and true or false
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

local function createEmptyChild(id, parent, x, y, width, height)
    if parent == nil then
        return nil
    end
    local widget = nil
    if parent.CreateChildWidget ~= nil then
        widget = safeCall(function()
            return parent:CreateChildWidget("emptywidget", id, 0, true)
        end)
    end
    if widget == nil and api.Interface ~= nil and api.Interface.CreateWidget ~= nil then
        widget = safeCall(function()
            return api.Interface:CreateWidget("emptywidget", id, parent)
        end)
    end
    if widget == nil then
        return nil
    end
    if widget.AddAnchor ~= nil then
        widget:AddAnchor("TOPLEFT", x or 0, y or 0)
    end
    if widget.SetExtent ~= nil then
        widget:SetExtent(width or 100, height or 100)
    end
    safeShow(widget, true)
    return widget
end

local function addPanelBackground(widget, alpha)
    if widget == nil then
        return nil
    end

    local background = nil
    if widget.CreateNinePartDrawable ~= nil and TEXTURE_PATH ~= nil and TEXTURE_PATH.HUD ~= nil then
        background = widget:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
        if background ~= nil and background.SetTextureInfo ~= nil then
            background:SetTextureInfo("bg_quest")
        end
    elseif widget.CreateColorDrawable ~= nil then
        background = widget:CreateColorDrawable(0.08, 0.07, 0.05, alpha or 0.86, "background")
    end

    if background ~= nil then
        if background.SetColor ~= nil then
            background:SetColor(0.08, 0.07, 0.05, tonumber(alpha) or 0.86)
        end
        background:AddAnchor("TOPLEFT", widget, 0, 0)
        background:AddAnchor("BOTTOMRIGHT", widget, 0, 0)
    end
    return background
end

local function addPanelAccent(widget, height, alpha)
    if widget == nil or widget.CreateColorDrawable == nil then
        return nil
    end
    local accent = widget:CreateColorDrawable(0.94, 0.80, 0.48, alpha or 0.12, "overlay")
    accent:AddAnchor("TOPLEFT", widget, 0, 0)
    accent:AddAnchor("TOPRIGHT", widget, 0, 0)
    if accent.SetHeight ~= nil then
        accent:SetHeight(height or 44)
    else
        accent:SetExtent(1, height or 44)
    end
    return accent
end

local function addPanelDivider(widget, topInset, leftInset, rightInset, alpha)
    if widget == nil or widget.CreateColorDrawable == nil then
        return nil
    end
    local divider = widget:CreateColorDrawable(0.88, 0.76, 0.46, alpha or 0.16, "overlay")
    divider:AddAnchor("TOPLEFT", widget, leftInset or 18, topInset or 58)
    divider:AddAnchor("TOPRIGHT", widget, rightInset or -18, topInset or 58)
    if divider.SetHeight ~= nil then
        divider:SetHeight(1)
    else
        divider:SetExtent(1, 1)
    end
    return divider
end

local function readOffset(widget)
    if widget == nil then
        return nil, nil
    end
    local ok = false
    local x, y = nil, nil
    if widget.GetOffset ~= nil then
        ok, x, y = pcall(function()
            return widget:GetOffset()
        end)
    end
    if (not ok or x == nil or y == nil) and widget.GetEffectiveOffset ~= nil then
        ok, x, y = pcall(function()
            return widget:GetEffectiveOffset()
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

local function attachShiftDrag(widget, kind, dragFlagKey, moveTarget)
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
        local target = moveTarget or self
        if dragFlagKey ~= nil then
            SettingsUi[dragFlagKey] = true
        end
        if target.StartMoving ~= nil then
            target:StartMoving()
        end
        if api.Cursor ~= nil and api.Cursor.ClearCursor ~= nil then
            api.Cursor:ClearCursor()
        end
        if api.Cursor ~= nil and api.Cursor.SetCursorImage ~= nil then
            api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
        end
    end)
    widget:SetHandler("OnDragStop", function(self)
        local target = moveTarget or self
        if target.StopMovingOrSizing ~= nil then
            target:StopMovingOrSizing()
        end
        if dragFlagKey ~= nil then
            SettingsUi[dragFlagKey] = false
        end
        if api.Cursor ~= nil and api.Cursor.ClearCursor ~= nil then
            api.Cursor:ClearCursor()
        end
        persistPosition(kind, target)
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
        local color = THEME.text
        local size = tonumber(fontSize) or 13
        if size >= 18 then
            color = THEME.title
        elseif size >= 15 then
            color = THEME.heading
        elseif size <= 12 then
            color = THEME.hint
        end
        if label.style.SetFontSize ~= nil then
            label.style:SetFontSize(size)
        end
        if label.style.SetAlign ~= nil then
            label.style:SetAlign(ALIGN.LEFT)
        end
        if label.style.SetColor ~= nil then
            label.style:SetColor(color[1], color[2], color[3], color[4])
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
    local picker = SettingsUi.color_picker or {}
    if picker.overlay ~= nil then
        local groupEntry = picker.active_group ~= nil and SettingsUi.color_group_widgets[picker.active_group] or nil
        local showPicker = SettingsUi.active_page == "colors" and picker.active_group ~= nil
        if showPicker and groupEntry ~= nil then
            showPicker = groupEntry.page == currentPage
        end
        safeShow(picker.overlay, showPicker)
    end
end

local function setColorPage(page)
    SettingsUi.color_page = Shared.Clamp(page, 1, SettingsUi.color_page_count or 1, 1)
    refreshColorPage()
end

local refreshColorValues

local function clampColorChannel(value, fallback)
    return math.floor(Shared.Clamp(tonumber(value), 0, 255, fallback or 0) + 0.5)
end

local function copyColorValue(value, fallback)
    local src = type(value) == "table" and value or fallback or { 255, 255, 255, 255 }
    return {
        clampColorChannel(src[1], 255),
        clampColorChannel(src[2], 255),
        clampColorChannel(src[3], 255),
        clampColorChannel(src[4], 255)
    }
end

local function defaultColorForKey(key)
    local defaults = Shared.DEFAULT_SETTINGS ~= nil and Shared.DEFAULT_SETTINGS.style or nil
    return copyColorValue(defaults ~= nil and defaults[key] or nil, { 255, 255, 255, 255 })
end

local function getStyleColor(style, key)
    return copyColorValue(type(style) == "table" and style[key] or nil, defaultColorForKey(key))
end

local function ensureStyleColor(style, key)
    if type(style) ~= "table" then
        return defaultColorForKey(key)
    end
    if type(style[key]) ~= "table" then
        style[key] = defaultColorForKey(key)
        return style[key]
    end
    style[key][1] = clampColorChannel(style[key][1], 255)
    style[key][2] = clampColorChannel(style[key][2], 255)
    style[key][3] = clampColorChannel(style[key][3], 255)
    style[key][4] = clampColorChannel(style[key][4], 255)
    return style[key]
end

local function getColorGroupByKey(key)
    for _, group in ipairs(Schema.COLOR_GROUPS or {}) do
        if group.key == key then
            return group
        end
    end
    return nil
end

local function setDrawableColor(drawable, color, alphaScale)
    if drawable == nil or drawable.SetColor == nil then
        return
    end
    local resolved = copyColorValue(color, { 255, 255, 255, 255 })
    local alpha = (resolved[4] / 255) * (tonumber(alphaScale) or 1)
    if alpha < 0 then
        alpha = 0
    elseif alpha > 1 then
        alpha = 1
    end
    drawable:SetColor(resolved[1] / 255, resolved[2] / 255, resolved[3] / 255, alpha)
end

local function setLabelColor255(label, color)
    if label == nil or label.style == nil or label.style.SetColor == nil then
        return
    end
    local resolved = copyColorValue(color, { 255, 255, 255, 255 })
    label.style:SetColor(
        resolved[1] / 255,
        resolved[2] / 255,
        resolved[3] / 255,
        resolved[4] / 255
    )
end

local function formatColorHex(color)
    local resolved = copyColorValue(color, { 255, 255, 255, 255 })
    return string.format("#%02X%02X%02X", resolved[1], resolved[2], resolved[3])
end

local function formatColorRgb(color)
    local resolved = copyColorValue(color, { 255, 255, 255, 255 })
    return string.format("RGB %d, %d, %d", resolved[1], resolved[2], resolved[3])
end

local function hsvToRgb(h, s, v)
    local hue = tonumber(h) or 0
    local sat = tonumber(s) or 0
    local val = tonumber(v) or 0
    hue = hue - math.floor(hue)
    sat = Shared.Clamp(sat, 0, 1, 0)
    val = Shared.Clamp(val, 0, 1, 0)
    local i = math.floor(hue * 6)
    local f = (hue * 6) - i
    local p = val * (1 - sat)
    local q = val * (1 - (f * sat))
    local t = val * (1 - ((1 - f) * sat))
    local mod = i % 6
    local r, g, b = val, t, p
    if mod == 1 then
        r, g, b = q, val, p
    elseif mod == 2 then
        r, g, b = p, val, t
    elseif mod == 3 then
        r, g, b = p, q, val
    elseif mod == 4 then
        r, g, b = t, p, val
    elseif mod == 5 then
        r, g, b = val, p, q
    end
    return {
        math.floor((r * 255) + 0.5),
        math.floor((g * 255) + 0.5),
        math.floor((b * 255) + 0.5),
        255
    }
end

local function paletteCellColor(column, row, columns, rows)
    local rowPct = (row - 1) / math.max(1, (rows or 1) - 1)
    if column == 1 then
        local value = math.floor((((1 - rowPct) * 0.82) + 0.12) * 255 + 0.5)
        return { value, value, value, 255 }
    end
    local hue = (column - 2) / math.max(1, (columns or 2) - 2)
    local saturation = 0.25 + (rowPct * 0.70)
    local value = 1 - (rowPct * 0.58)
    return hsvToRgb(hue, saturation, value)
end

local function createBareButton(id, parent, x, y, width, height)
    local button = api.Interface:CreateWidget("button", id, parent)
    button:AddAnchor("TOPLEFT", x, y)
    button:SetExtent(width or 80, height or 24)
    button:SetText("")
    safeShow(button, true)
    return button
end

local function getPreviewBarTexture(group)
    local key = type(group) == "table" and tostring(group.key or "") or ""
    if key == "mp_bar_color" then
        return STATUSBAR_STYLE ~= nil and STATUSBAR_STYLE.MP_RAID or nil
    end
    return STATUSBAR_STYLE ~= nil and STATUSBAR_STYLE.HP_RAID or nil
end

local function createPreviewStatusBar(id, parent, group, height)
    if parent == nil or W_BAR == nil or W_BAR.CreateStatusBarOfRaidFrame == nil then
        return nil
    end
    local bar = safeCall(function()
        return W_BAR.CreateStatusBarOfRaidFrame(id, parent)
    end)
    if bar == nil then
        return nil
    end
    safeShow(bar, true)
    if bar.Clickable ~= nil then
        bar:Clickable(false)
    end
    if bar.statusBar ~= nil and bar.statusBar.Clickable ~= nil then
        bar.statusBar:Clickable(false)
    end
    local texture = getPreviewBarTexture(group)
    if bar.ApplyBarTexture ~= nil then
        safeCall(function()
            if texture ~= nil then
                bar:ApplyBarTexture(texture)
            else
                bar:ApplyBarTexture()
            end
        end)
    end
    if bar.RemoveAllAnchors ~= nil and bar.AddAnchor ~= nil then
        safeCall(function()
            bar:RemoveAllAnchors()
            bar:AddAnchor("TOPLEFT", parent, 0, 0)
            bar:AddAnchor("TOPRIGHT", parent, 0, 0)
            if bar.SetHeight ~= nil then
                bar:SetHeight(height or 18)
            end
        end)
    end
    if bar.statusBar ~= nil and bar.statusBar.SetMinMaxValues ~= nil then
        safeCall(function()
            bar.statusBar:SetMinMaxValues(0, 100)
        end)
    end
    if bar.statusBar ~= nil and bar.statusBar.SetValue ~= nil then
        safeCall(function()
            bar.statusBar:SetValue(100)
        end)
    end
    return bar
end

local function createInsetFill(widget, inset, layer)
    if widget == nil or widget.CreateColorDrawable == nil then
        return nil
    end
    local margin = tonumber(inset) or 0
    local fill = widget:CreateColorDrawable(1, 1, 1, 1, layer or "artwork")
    fill:AddAnchor("TOPLEFT", widget, margin, margin)
    fill:AddAnchor("BOTTOMRIGHT", widget, -margin, -margin)
    return fill
end

local function createColorSwatchButton(id, parent, x, y, width, height)
    local button = createBareButton(id, parent, x, y, width, height)
    if button == nil then
        return nil
    end
    if button.CreateColorDrawable ~= nil then
        local background = button:CreateColorDrawable(0.05, 0.04, 0.03, 0.96, "background")
        background:AddAnchor("TOPLEFT", button, 0, 0)
        background:AddAnchor("BOTTOMRIGHT", button, 0, 0)
        button.__ghb_fill = createInsetFill(button, 3, "artwork")
        local gloss = button:CreateColorDrawable(1, 1, 1, 0.08, "overlay")
        gloss:AddAnchor("TOPLEFT", button, 3, 3)
        gloss:AddAnchor("TOPRIGHT", button, -3, 3)
        if gloss.SetHeight ~= nil then
            gloss:SetHeight(math.max(4, math.floor((height or 18) * 0.3)))
        else
            gloss:SetExtent(1, math.max(4, math.floor((height or 18) * 0.3)))
        end
    end
    return button
end

local function createColorPreviewFrame(id, parent, group, x, y, width, height)
    local frame = createEmptyChild(id, parent, x, y, width, height)
    if frame == nil then
        return nil
    end
    addPanelBackground(frame, 0.84)
    addPanelAccent(frame, math.max(12, math.floor((height or 24) * 0.42)), 0.06)
    frame.__ghb_preview_mode = type(group) == "table" and group.preview or "bar"
    if frame.__ghb_preview_mode == "text" then
        frame.__ghb_preview_label = createLabel(id .. "Text", frame, "Preview Text", 14, 15, 14, (width or 140) - 28)
    else
        frame.__ghb_preview_label = createLabel(id .. "Text", frame, "Bar Preview", 14, 8, 12, (width or 140) - 28)
        local bar = createEmptyChild(id .. "Bar", frame, 14, 28, (width or 140) - 28, 18)
        if bar ~= nil then
            if bar.CreateColorDrawable ~= nil then
                local barBg = bar:CreateColorDrawable(0.12, 0.11, 0.10, 0.92, "background")
                barBg:AddAnchor("TOPLEFT", bar, 0, 0)
                barBg:AddAnchor("BOTTOMRIGHT", bar, 0, 0)
            end
            frame.__ghb_preview_bar = createPreviewStatusBar(id .. "StatusBar", bar, group, 18)
            if frame.__ghb_preview_bar ~= nil then
                frame.__ghb_preview_statusbar = frame.__ghb_preview_bar.statusBar or frame.__ghb_preview_bar
            else
                frame.__ghb_preview_fill = createInsetFill(bar, 2, "artwork")
            end
        end
    end
    return frame
end

local function updateColorPreview(preview, group, color)
    if preview == nil then
        return
    end
    local mode = preview.__ghb_preview_mode or (type(group) == "table" and group.preview) or "bar"
    if mode == "text" then
        setLabelColor255(preview.__ghb_preview_label, color)
    elseif preview.__ghb_preview_statusbar ~= nil then
        local previewMode = (type(group) == "table" and group.key == "mp_bar_color") and "mp" or "hp"
        if preview.__ghb_preview_bar ~= nil and preview.__ghb_preview_texture_mode ~= previewMode then
            preview.__ghb_preview_texture_mode = previewMode
            local texture = getPreviewBarTexture(group)
            if preview.__ghb_preview_bar.ApplyBarTexture ~= nil then
                safeCall(function()
                    if texture ~= nil then
                        preview.__ghb_preview_bar:ApplyBarTexture(texture)
                    else
                        preview.__ghb_preview_bar:ApplyBarTexture()
                    end
                end)
            end
        end
        local resolved = copyColorValue(color, { 255, 255, 255, 255 })
        local rgba = {
            resolved[1] / 255,
            resolved[2] / 255,
            resolved[3] / 255,
            resolved[4] / 255
        }
        if Helpers ~= nil and Helpers.ApplyStatusBarColor ~= nil then
            Helpers.ApplyStatusBarColor(preview.__ghb_preview_statusbar, rgba)
        end
    elseif preview.__ghb_preview_fill ~= nil then
        setDrawableColor(preview.__ghb_preview_fill, color)
    end
end

local function updateColorCardDisplay(card, group, color)
    if type(card) ~= "table" then
        return
    end
    if card.swatch ~= nil and card.swatch.__ghb_fill ~= nil then
        setDrawableColor(card.swatch.__ghb_fill, color)
    end
    safeSetText(card.hex_label, formatColorHex(color))
    safeSetText(card.rgb_label, formatColorRgb(color))
    updateColorPreview(card.preview, group, color)
end

local function refreshColorCardDisplays(style)
    for _, group in ipairs(Schema.COLOR_GROUPS or {}) do
        local card = SettingsUi.color_cards[group.key]
        if card ~= nil then
            updateColorCardDisplay(card, group, getStyleColor(style, group.key))
        end
    end
end

local function refreshColorPickerDisplay(style)
    local picker = SettingsUi.color_picker or {}
    local group = getColorGroupByKey(picker.active_group)
    local color = getStyleColor(style, picker.active_group)
    if picker.title_label ~= nil then
        picker.title_label:SetText(group ~= nil and ("Edit " .. tostring(group.label or "")) or "Edit color")
    end
    if picker.hint_label ~= nil then
        picker.hint_label:SetText(group ~= nil and tostring(group.description or "") or "")
    end
    if picker.swatch ~= nil and picker.swatch.__ghb_fill ~= nil then
        setDrawableColor(picker.swatch.__ghb_fill, color)
    end
    safeSetText(picker.hex_label, formatColorHex(color))
    safeSetText(picker.rgb_label, formatColorRgb(color))
    updateColorPreview(picker.preview, group, color)
    for channelIndex = 1, 3 do
        local slider = picker.sliders ~= nil and picker.sliders[channelIndex] or nil
        local value = picker.values ~= nil and picker.values[channelIndex] or nil
        local display = color[channelIndex] or 0
        if slider ~= nil and slider.SetValue ~= nil then
            slider:SetValue(display, false)
        end
        safeSetText(value, tostring(display))
    end
end

local function applyPickerColor(color)
    local picker = SettingsUi.color_picker or {}
    if picker.active_group == nil then
        return
    end
    local style = Shared.GetStyleSettings()
    local current = ensureStyleColor(style, picker.active_group)
    local changed = false
    for channelIndex = 1, 3 do
        local value = clampColorChannel(color[channelIndex], current[channelIndex] or 255)
        if current[channelIndex] ~= value then
            current[channelIndex] = value
            changed = true
        end
    end
    if changed then
        applyChanges()
    end
    refreshColorValues(style)
end

local function setPickerChannel(channelIndex, raw)
    local picker = SettingsUi.color_picker or {}
    if picker.active_group == nil then
        return
    end
    local style = Shared.GetStyleSettings()
    local current = ensureStyleColor(style, picker.active_group)
    local value = clampColorChannel(raw, current[channelIndex] or 0)
    if current[channelIndex] ~= value then
        current[channelIndex] = value
        applyChanges()
    end
    refreshColorValues(style)
end

local function closeColorPicker(commit)
    local picker = SettingsUi.color_picker or {}
    if picker.overlay == nil then
        return
    end
    if not commit and picker.active_group ~= nil and type(picker.original_color) == "table" then
        local style = Shared.GetStyleSettings()
        style[picker.active_group] = copyColorValue(picker.original_color, defaultColorForKey(picker.active_group))
        applyChanges()
        refreshColorValues(style)
    end
    picker.active_group = nil
    picker.original_color = nil
    safeShow(picker.overlay, false)
end

local function openColorPicker(group)
    local groupKey = type(group) == "table" and group.key or group
    if type(groupKey) ~= "string" or groupKey == "" then
        return
    end
    local picker = SettingsUi.color_picker or {}
    if picker.overlay == nil then
        return
    end
    picker.active_group = groupKey
    picker.original_color = getStyleColor(Shared.GetStyleSettings(), groupKey)
    safeShow(picker.overlay, SettingsUi.active_page == "colors")
    refreshColorValues(Shared.GetStyleSettings())
end

local function ensureColorPicker(parent)
    local picker = SettingsUi.color_picker
    if picker.overlay ~= nil or parent == nil then
        return picker.overlay
    end

    picker.overlay = createEmptyChild("ghbColorPickerOverlay", parent, 0, 0, 748, 770)
    if picker.overlay ~= nil and picker.overlay.CreateColorDrawable ~= nil then
        local veil = picker.overlay:CreateColorDrawable(0.01, 0.01, 0.01, 0.54, "background")
        veil:AddAnchor("TOPLEFT", picker.overlay, 0, 0)
        veil:AddAnchor("BOTTOMRIGHT", picker.overlay, 0, 0)
    end

    picker.panel = createEmptyChild("ghbColorPickerPanel", picker.overlay, 78, 84, 592, 562)
    if picker.panel ~= nil then
        addPanelBackground(picker.panel, 0.96)
        addPanelAccent(picker.panel, 50, 0.14)
        addPanelDivider(picker.panel, 58, 18, -18, 0.18)
    end

    local panel = picker.panel or picker.overlay
    picker.title_label = createLabel("ghbColorPickerTitle", panel, "Edit color", 18, 16, 18, 320)
    picker.hint_label = createLabel("ghbColorPickerHint", panel, "", 18, 40, 12, 320)
    picker.swatch = createColorSwatchButton("ghbColorPickerSwatch", panel, 376, 22, 188, 72)
    picker.hex_label = createLabel("ghbColorPickerHex", panel, "", 376, 102, 13, 188)
    picker.rgb_label = createLabel("ghbColorPickerRgb", panel, "", 376, 124, 12, 188)
    picker.preview = createColorPreviewFrame("ghbColorPickerPreview", panel, { preview = "bar" }, 376, 154, 188, 94)

    createLabel("ghbColorPickerPaletteTitle", panel, "Palette", 22, 80, 15, 120)
    createLabel("ghbColorPickerPaletteHint", panel, "Click a swatch for quick picks, then fine-tune below.", 22, 104, 12, 320)

    picker.palette_cells = {}
    local paletteColumns = 13
    local paletteRows = 9
    local cellWidth = 22
    local cellHeight = 18
    local gapX = 4
    local gapY = 4
    local startX = 22
    local startY = 134
    for row = 1, paletteRows do
        for column = 1, paletteColumns do
            local index = ((row - 1) * paletteColumns) + column
            local cell = createColorSwatchButton(
                "ghbColorPickerCell" .. tostring(index),
                panel,
                startX + ((column - 1) * (cellWidth + gapX)),
                startY + ((row - 1) * (cellHeight + gapY)),
                cellWidth,
                cellHeight
            )
            local cellColor = paletteCellColor(column, row, paletteColumns, paletteRows)
            cell.__ghb_palette_color = cellColor
            if cell.__ghb_fill ~= nil then
                setDrawableColor(cell.__ghb_fill, cellColor)
            end
            cell:SetHandler("OnClick", function()
                applyPickerColor(cell.__ghb_palette_color)
            end)
            picker.palette_cells[index] = cell
        end
    end

    picker.sliders = {}
    picker.values = {}
    local channels = {
        { label = "Red", index = 1 },
        { label = "Green", index = 2 },
        { label = "Blue", index = 3 }
    }
    for channelOffset, channel in ipairs(channels) do
        local _, slider, value = createSlider(
            "ghbColorPickerSlider" .. channel.label,
            panel,
            channel.label,
            22,
            354 + ((channelOffset - 1) * 44),
            0,
            255,
            {
                label_width = 66,
                slider_width = 248,
                value_width = 44,
                slider_offset = 70,
                value_offset = 326
            }
        )
        picker.sliders[channel.index] = slider
        picker.values[channel.index] = value
        if slider ~= nil and slider.SetHandler ~= nil then
            slider:SetHandler("OnSliderChanged", function(_, raw)
                setPickerChannel(channel.index, raw)
            end)
        end
    end

    picker.reset_button = createButton("ghbColorPickerReset", panel, "Default", 22, 500, 96, 28)
    picker.cancel_button = createButton("ghbColorPickerCancel", panel, "Cancel", 408, 500, 72, 28)
    picker.apply_button = createButton("ghbColorPickerApply", panel, "Apply", 488, 500, 76, 28)
    picker.reset_button:SetHandler("OnClick", function()
        local activeGroup = picker.active_group
        if activeGroup == nil then
            return
        end
        local style = Shared.GetStyleSettings()
        style[activeGroup] = defaultColorForKey(activeGroup)
        applyChanges()
        refreshColorValues(style)
    end)
    picker.cancel_button:SetHandler("OnClick", function()
        closeColorPicker(false)
    end)
    picker.apply_button:SetHandler("OnClick", function()
        closeColorPicker(true)
    end)

    addPageWidget("colors", picker.overlay)
    safeShow(picker.overlay, false)
    return picker.overlay
end

local function createColorCard(group, parent, x, y, width, height)
    local card = createEmptyChild("ghbColorCard" .. tostring(group.key), parent, x, y, width, height)
    if card == nil then
        return nil
    end
    addPanelBackground(card, 0.84)
    addPanelAccent(card, 34, 0.10)
    addPanelDivider(card, 42, 14, -14, 0.10)

    local cardWidth = width or 320
    local title = createLabel("ghbColorCardTitle" .. tostring(group.key), card, tostring(group.label or group.key or ""), 16, 12, 15, 184)
    local description = createLabel(
        "ghbColorCardDesc" .. tostring(group.key),
        card,
        tostring(group.description or "Color setting"),
        16,
        38,
        12,
        math.max(96, cardWidth - 148)
    )
    local swatch = createColorSwatchButton("ghbColorCardSwatch" .. tostring(group.key), card, cardWidth - 86, 14, 70, 48)
    local hexLabel = createLabel("ghbColorCardHex" .. tostring(group.key), card, "", cardWidth - 114, 70, 13, 112)
    local rgbLabel = createLabel("ghbColorCardRgb" .. tostring(group.key), card, "", 16, 70, 12, 188)
    local preview = createColorPreviewFrame("ghbColorCardPreview" .. tostring(group.key), card, group, 16, 96, 180, 54)
    local editBtn = createButton("ghbColorCardEdit" .. tostring(group.key), card, "Edit", cardWidth - 146, 112, 58, 28)
    local resetBtn = createButton("ghbColorCardReset" .. tostring(group.key), card, "Reset", cardWidth - 80, 112, 58, 28)

    local function openGroupPicker()
        openColorPicker(group)
    end

    swatch:SetHandler("OnClick", openGroupPicker)
    editBtn:SetHandler("OnClick", openGroupPicker)
    resetBtn:SetHandler("OnClick", function()
        local style = Shared.GetStyleSettings()
        style[group.key] = defaultColorForKey(group.key)
        applyChanges()
        refreshColorValues(style)
    end)

    local refs = {
        root = card,
        title = title,
        description = description,
        swatch = swatch,
        hex_label = hexLabel,
        rgb_label = rgbLabel,
        preview = preview,
        edit_button = editBtn,
        reset_button = resetBtn
    }
    SettingsUi.color_cards[group.key] = refs
    updateColorCardDisplay(refs, group, getStyleColor(Shared.GetStyleSettings(), group.key))
    return refs
end

local function setActivePage(page)
    if page ~= "colors" and SettingsUi.color_picker ~= nil and SettingsUi.color_picker.active_group ~= nil then
        closeColorPicker(true)
    end
    SettingsUi.active_page = page
    for name, widgets in pairs(SettingsUi.page_widgets) do
        local show = name == page
        for _, widget in ipairs(widgets) do
            safeShow(widget, show)
        end
    end
    for _, pageDef in ipairs(PAGE_DEFS) do
        local ctrl = SettingsUi.controls["nav_" .. pageDef.key]
        if ctrl ~= nil and ctrl.SetText ~= nil then
            local label = tostring(pageDef.label or pageDef.key)
            if pageDef.key == page then
                label = "> " .. label
            end
            ctrl:SetText(label)
        end
        if ctrl ~= nil and ctrl.SetAlpha ~= nil then
            ctrl:SetAlpha(pageDef.key == page and 1 or 0.82)
        end
        local pageTitle = SettingsUi.controls.page_header_title
        local pageSummary = SettingsUi.controls.page_header_summary
        if pageDef.key == page then
            if pageTitle ~= nil and pageTitle.SetText ~= nil then
                pageTitle:SetText(tostring(pageDef.title or pageDef.label or pageDef.key))
            end
            if pageSummary ~= nil and pageSummary.SetText ~= nil then
                pageSummary:SetText(tostring(pageDef.summary or ""))
            end
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

refreshColorValues = function(style)
    refreshColorCardDisplays(style)
    if SettingsUi.color_picker ~= nil and SettingsUi.color_picker.active_group ~= nil then
        refreshColorPickerDisplay(style)
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
        createEmptyChild = createEmptyChild,
        createLabel = createLabel,
        createButton = createButton,
        createCheckbox = createCheckbox,
        createSlider = createSlider,
        createChoiceRow = createChoiceRow,
        createColorCard = createColorCard,
        ensureColorPicker = ensureColorPicker,
        openColorPicker = openColorPicker,
        closeColorPicker = closeColorPicker,
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
    collectWidgetRefs(SettingsUi.color_cards, seen, widgets)
    collectWidgetRefs(SettingsUi.color_picker, seen, widgets)

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
    local wnd = safeCall(function()
        -- The stock skinned window shell rejects custom widths in this client.
        if api.Interface ~= nil and api.Interface.CreateEmptyWindow ~= nil then
            return api.Interface:CreateEmptyWindow(Shared.CONSTANTS.WINDOW_ID, "UIParent")
        end
        if api.Interface ~= nil and api.Interface.CreateWindow ~= nil then
            return api.Interface:CreateWindow(Shared.CONSTANTS.WINDOW_ID, "Gharka Bars Settings", 0, 0)
        end
        return nil
    end)
    if wnd == nil then
        SettingsUi.window = nil
        return
    end
    SettingsUi.window = wnd
    applyCommonWindowBehavior(wnd)
    if wnd.SetExtent ~= nil then
        wnd:SetExtent(BASE_WINDOW_WIDTH, BASE_WINDOW_HEIGHT)
    end
    local settings = Shared.EnsureSettings()
    anchorToUiParent(
        wnd,
        Shared.Clamp(settings.window_x, 0, 4000, 520),
        Shared.Clamp(settings.window_y, 0, 4000, 90)
    )
    attachShiftDrag(wnd, "window", nil)

    local shell = createEmptyChild("ghbWindowShell", wnd, 0, 0, BASE_WINDOW_WIDTH, BASE_WINDOW_HEIGHT)
    if shell ~= nil then
        addPanelBackground(shell, 0.94)
        addPanelAccent(shell, 44, 0.08)
        addPanelDivider(shell, 44, 12, -12, 0.12)
    end

    local header = createEmptyChild("ghbHeader", wnd, 0, 0, BASE_WINDOW_WIDTH, 24)
    if header ~= nil then
        addPanelBackground(header, 0.98)
        addPanelAccent(header, 24, 0.10)
        addPanelDivider(header, 24, 10, -10, 0.14)
        attachShiftDrag(header, "window", nil, wnd)
        createLabel("ghbHeaderTitle", header, "Gharka Bars Settings", 14, 3, 15, 260)
        local closeBtn = createButton("ghbHeaderClose", header, "X", BASE_WINDOW_WIDTH - 38, 1, 26, 22)
        if closeBtn ~= nil and closeBtn.SetHandler ~= nil then
            closeBtn:SetHandler("OnClick", function()
                safeShow(SettingsUi.window, false)
            end)
        end
        SettingsUi.controls.header = header
        SettingsUi.controls.header_close = closeBtn
    end

    local navPanel = createEmptyChild("ghbNavPanel", wnd, 12, 38, 168, 834)
    if navPanel ~= nil then
        addPanelBackground(navPanel, 0.88)
        addPanelAccent(navPanel, 42, 0.12)
    end

    local contentPanel = createEmptyChild("ghbContentPanel", wnd, 192, 26, 776, 846)
    if contentPanel ~= nil then
        addPanelBackground(contentPanel, 0.86)
        addPanelAccent(contentPanel, 54, 0.12)
        addPanelDivider(contentPanel, 58, 18, -18, 0.18)
    end

    SettingsUi.controls.window_shell = shell
    SettingsUi.controls.nav_panel = navPanel
    SettingsUi.controls.content_panel = contentPanel

    local navParent = navPanel or wnd
    local contentParent = contentPanel or wnd
    createLabel("ghbNavTitle", navParent, "Gharka Bars", 14, 12, 18, 132)
    createLabel("ghbNavSubtitle", navParent, "Overlay settings", 14, 36, 12, 132)
    createLabel("ghbNavSectionTitle", navParent, "Sections", 14, 74, 15, 132)
    createLabel(
        "ghbNavHint",
        navParent,
        "Shift+drag the launcher or settings window to move them.",
        14,
        770,
        12,
        140
    )

    SettingsUi.controls.page_header_title = createLabel("ghbPageHeaderTitle", contentParent, "", 18, 14, 18, 520)
    SettingsUi.controls.page_header_summary = createLabel("ghbPageHeaderSummary", contentParent, "", 18, 40, 12, 720)

    local navY = 106
    for _, pageDef in ipairs(PAGE_DEFS) do
        local btn = createButton("ghbNav" .. pageDef.key, navParent, tostring(pageDef.label or pageDef.key), 10, navY, 146, 30)
        SettingsUi.controls["nav_" .. pageDef.key] = btn
        btn:SetHandler("OnClick", function()
            setActivePage(pageDef.key)
        end)
        navY = navY + 36
    end

    local pageParents = {}
    for _, pageDef in ipairs(PAGE_DEFS) do
        local pageRoot = createEmptyChild("ghbPageRoot" .. pageDef.key, contentParent, 0, 0, 748, 770)
        if pageRoot ~= nil then
            addPageWidget(pageDef.key, pageRoot)
            pageParents[pageDef.key] = pageRoot
        end
    end

    local ctx = buildContext()
    Pages.BuildGeneralPage(ctx, pageParents.general or contentParent)
    Pages.BuildLayoutPage(ctx, pageParents.layout or contentParent)
    Pages.BuildTextPage(ctx, pageParents.text or contentParent)
    Pages.BuildCcPage(ctx, pageParents.cc or contentParent)
    Pages.BuildColorsPage(ctx, pageParents.colors or contentParent)

    local footerPanel = createEmptyChild("ghbFooterPanel", contentParent, 18, 776, 738, 70)
    if footerPanel ~= nil then
        addPanelBackground(footerPanel, 0.80)
        addPanelAccent(footerPanel, 28, 0.08)
    end
    local footerParent = footerPanel or contentParent
    SettingsUi.controls.footer_panel = footerPanel
    SettingsUi.controls.status_label = createLabel("ghbStatus", footerParent, "", 16, 10, 12, 690)
    local saveBtn = createButton("ghbSave", footerParent, "Save", 16, 34, 72, 28)
    local profileInput = createEdit("ghbProfileName", footerParent, "", 96, 36, 158, 24, 48, "Profile name")
    local profileDropdown = createComboBox("ghbProfileDropdown", footerParent, { Shared.GetActiveProfileFileName() }, 264, 36, 180, 24)
    local loadBtn = createButton("ghbLoadProfile", footerParent, "Load", 452, 34, 72, 28)
    local resetStyleBtn = createButton("ghbResetStyle", footerParent, "Reset Style", 532, 34, 96, 28)
    local resetAllBtn = createButton("ghbResetAll", footerParent, "Reset All", 636, 34, 96, 28)

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
    SettingsUi.color_cards = {}
    SettingsUi.color_picker = {
        overlay = nil,
        panel = nil,
        palette_cells = {},
        active_group = nil,
        original_color = nil
    }
    SettingsUi.profile_items = {}
end

return SettingsUi
