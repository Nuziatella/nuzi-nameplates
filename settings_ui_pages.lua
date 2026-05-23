local function eachSlider(list, fn)
    for index, item in ipairs(list or {}) do
        fn(index, item)
    end
end

local Pages = {}

local function bindGlobalToggle(ctx, item, cb)
    cb:SetHandler("OnClick", function()
        local settings = ctx.Shared.EnsureSettings()
        settings[item.key] = not (settings[item.key] and true or false)
        ctx.applyChanges()
        ctx.refreshControls()
    end)
end

local function bindGlobalChoice(ctx, item, button)
    button:SetHandler("OnClick", function()
        local settings = ctx.Shared.EnsureSettings()
        settings[item.key] = ctx.nextOptionValue(item, settings[item.key])
        ctx.applyChanges()
        ctx.refreshControls()
    end)
end

local function bindGlobalChoiceOption(ctx, item, option, button)
    button:SetHandler("OnClick", function()
        local settings = ctx.Shared.EnsureSettings()
        settings[item.key] = option.value
        ctx.applyChanges()
        ctx.refreshControls()
    end)
end

local function bindGlobalSlider(ctx, key, slider, value)
    if slider == nil or slider.SetHandler == nil then
        return
    end
    slider:SetHandler("OnSliderChanged", function(_, raw)
        local settings = ctx.Shared.EnsureSettings()
        local n = math.floor((tonumber(raw) or 48) + 0.5)
        settings[key] = n
        if value ~= nil and value.SetText ~= nil then
            value:SetText(tostring(n))
        end
        ctx.Shared.SaveSettings()
        if ctx.applyLauncherLayout ~= nil then
            ctx.applyLauncherLayout()
        end
    end)
end

local function bindStyleToggle(ctx, item, cb)
    cb:SetHandler("OnClick", function()
        local style = ctx.Shared.GetStyleSettings()
        style[item.key] = not (style[item.key] and true or false)
        ctx.applyChanges()
        ctx.refreshControls()
    end)
end

local function bindStyleChoice(ctx, item, button)
    button:SetHandler("OnClick", function()
        local style = ctx.Shared.GetStyleSettings()
        style[item.key] = ctx.nextOptionValue(item, style[item.key])
        ctx.applyChanges()
        ctx.refreshControls()
    end)
end

local function bindStyleSlider(ctx, item, slider, value)
    if slider == nil or slider.SetHandler == nil then
        return
    end
    slider:SetHandler("OnSliderChanged", function(_, raw)
        local n = tonumber(raw) or 0
        ctx.Shared.GetStyleSettings()[item.key] = n
        if value ~= nil and value.SetText ~= nil then
            value:SetText(tostring(math.floor(n + 0.5)))
        end
        ctx.applyChanges()
    end)
end

local function addSection(ctx, page, wnd, id, title, hint, x, y, width)
    local titleLabel = ctx.createLabel(id .. "Title", wnd, title, x, y, 15, width or 260)
    ctx.addPageWidget(page, titleLabel)
    local hintLabel = nil
    if type(hint) == "string" and hint ~= "" then
        hintLabel = ctx.createLabel(id .. "Hint", wnd, hint, x, y + 22, 12, width or 320)
        ctx.addPageWidget(page, hintLabel)
    end
    return titleLabel, hintLabel
end

local function createTightSlider(ctx, id, wnd, label, x, y, minValue, maxValue)
    return ctx.createSlider(id, wnd, label, x, y, minValue, maxValue, {
        label_width = 108,
        slider_width = 140,
        value_width = 44,
        slider_offset = 112,
        value_offset = 258
    })
end

local function findItemByKey(list, key)
    for _, item in ipairs(list or {}) do
        if item.key == key then
            return item
        end
    end
    return nil
end

local function addGlobalToggleControl(ctx, page, wnd, key, x, y, width)
    local item = findItemByKey(ctx.Schema.GLOBAL_TOGGLES, key)
    if item == nil then
        return nil
    end
    local cb = ctx.createCheckbox("nnpGlobal" .. item.key, wnd, item.label, x, y, width or 220)
    ctx.addPageWidget(page, cb.button)
    ctx.addPageWidget(page, cb.label)
    ctx.SettingsUi.controls["global_" .. item.key] = cb
    bindGlobalToggle(ctx, item, cb)
    return cb
end

local function addStyleToggleControl(ctx, page, wnd, item, x, y, width)
    if item == nil then
        return nil
    end
    local cb = ctx.createCheckbox("nnpStyleToggle" .. item.key, wnd, item.label, x, y, width or 220)
    ctx.addPageWidget(page, cb.button)
    ctx.addPageWidget(page, cb.label)
    ctx.SettingsUi.controls["style_toggle_" .. item.key] = cb
    bindStyleToggle(ctx, item, cb)
    return cb
end

local function addStyleChoiceControl(ctx, page, wnd, item, x, y)
    if item == nil then
        return nil
    end
    local label, btn = ctx.createChoiceRow("nnpChoice" .. item.key, wnd, item.label, x, y, 170)
    ctx.addPageWidget(page, label)
    ctx.addPageWidget(page, btn)
    ctx.SettingsUi.controls["style_choice_" .. item.key] = btn
    bindStyleChoice(ctx, item, btn)
    return btn
end

local function addStyleSliderControl(ctx, page, wnd, prefix, item, x, y)
    if item == nil then
        return nil
    end
    local label, slider, value = createTightSlider(ctx, prefix .. item.key, wnd, item.label, x, y, item.min, item.max)
    ctx.addPageWidget(page, label)
    ctx.addPageWidget(page, slider)
    ctx.addPageWidget(page, value)
    ctx.SettingsUi.controls["style_slider_" .. item.key] = slider
    ctx.SettingsUi.controls["style_slider_val_" .. item.key] = value
    bindStyleSlider(ctx, item, slider, value)
    return slider
end

local function copyColor(style, key)
    local value = style[key]
    if type(value) ~= "table" then
        return nil
    end
    return {
        tonumber(value[1]) or 255,
        tonumber(value[2]) or 255,
        tonumber(value[3]) or 255,
        tonumber(value[4]) or 255
    }
end

local function applyPreset(ctx, preset)
    if type(preset) ~= "table" then
        return
    end
    local current = ctx.Shared.GetStyleSettings()
    local savedColors = {}
    for _, group in ipairs(ctx.Schema.COLOR_GROUPS or {}) do
        savedColors[group.key] = copyColor(current, group.key)
    end

    ctx.Shared.ResetStyleSettings()
    local style = ctx.Shared.GetStyleSettings()
    for key, color in pairs(savedColors) do
        if color ~= nil then
            style[key] = color
        end
    end
    for key, value in pairs(preset.style or {}) do
        style[key] = value
    end

    ctx.applyChanges()
    ctx.refreshControls()
    if ctx.setStatus ~= nil then
        ctx.setStatus("Applied preset: " .. tostring(preset.label or preset.key or "Preset"))
    end
end

function Pages.BuildGeneralPage(ctx, wnd)
    addSection(ctx, "general", wnd, "nnpPreset", "Presets", "Apply a starting layout without changing saved colors.", 24, 112, 700)
    local presetButtons = ctx.Schema.STYLE_PRESETS or {}
    for index, preset in ipairs(presetButtons) do
        local buttonX = 24 + ((index - 1) * 172)
        local button = ctx.createButton("nnpPresetBtn" .. tostring(preset.key), wnd, tostring(preset.label or preset.key or "Preset"), buttonX, 158, 146, 30)
        ctx.addPageWidget("general", button)
        button:SetHandler("OnClick", function()
            applyPreset(ctx, preset)
        end)
    end

    addSection(ctx, "general", wnd, "nnpCore", "Core", nil, 24, 234, 320)
    addGlobalToggleControl(ctx, "general", wnd, "enabled", 24, 270, 260)

    addSection(ctx, "general", wnd, "nnpGeneralProfiles", "Profiles", nil, 388, 234, 320)
    ctx.addPageWidget("general", ctx.createLabel("nnpGeneralProfilesHint", wnd, "Save, load, and reset profiles from the footer.", 388, 270, 12, 320))
end

function Pages.BuildUnitsPage(ctx, wnd)
    addSection(ctx, "units", wnd, "nnpUnitVisibility", "Unit Visibility", "Choose which unit bars are allowed to appear.", 24, 112, 700)

    local unitKeys = {
        "show_player",
        "show_target",
        "show_watchtarget",
        "show_targettarget",
        "show_raid_party",
        "show_mount"
    }
    for index, key in ipairs(unitKeys) do
        local colX = index <= 3 and 24 or 388
        local row = index <= 3 and index or (index - 3)
        addGlobalToggleControl(ctx, "units", wnd, key, colX, 162 + ((row - 1) * 34), 240)
    end

    addSection(ctx, "units", wnd, "nnpUnitInteraction", "Interaction", nil, 24, 320, 700)
    addGlobalToggleControl(ctx, "units", wnd, "click_target", 24, 356, 260)
end

function Pages.BuildLayoutPage(ctx, wnd)
    addSection(ctx, "layout", wnd, "nnpLayoutVisibility", "Pieces", "Pick which parts of each nameplate stay visible.", 24, 112, 700)
    for index, item in ipairs(ctx.Schema.STYLE_TOGGLES or {}) do
        local colX = index <= 4 and 24 or 388
        local row = index <= 4 and index or (index - 4)
        addStyleToggleControl(ctx, "layout", wnd, item, colX, 160 + ((row - 1) * 34), 220)
    end

    addSection(ctx, "layout", wnd, "nnpLayoutMode", "Modes", "Switch how names, values, and health fills are arranged.", 24, 330, 700)
    for index, item in ipairs(ctx.Schema.STYLE_CHOICES or {}) do
        local col = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        addStyleChoiceControl(ctx, "layout", wnd, item, col == 0 and 24 or 388, 378 + (row * 42))
    end

    addSection(ctx, "layout", wnd, "nnpLayoutFrame", "Size", "Tune the bar block before adjusting offsets.", 24, 500, 700)
    local shown = 0
    eachSlider(ctx.Schema.LAYOUT_SLIDERS, function(_, item)
        if item.key ~= "x_offset" and item.key ~= "y_offset" then
            shown = shown + 1
            local colX = shown <= 4 and 24 or 388
            local row = shown <= 4 and shown or (shown - 4)
            addStyleSliderControl(ctx, "layout", wnd, "nnpLayoutSlider", item, colX, 548 + ((row - 1) * 34))
        end
    end)
end

function Pages.BuildTextPage(ctx, wnd)
    addSection(ctx, "text", wnd, "nnpTextFonts", "Fonts and Limits", "Use 0 chars for full names.", 24, 112, 700)
    eachSlider(ctx.Schema.TEXT_SLIDERS, function(index, item)
        if index <= 9 then
            local colX = index <= 5 and 24 or 388
            local localIndex = index <= 5 and index or (index - 5)
            addStyleSliderControl(ctx, "text", wnd, "nnpTextSlider", item, colX, 160 + ((localIndex - 1) * 34))
        end
    end)
end

function Pages.BuildPositionsPage(ctx, wnd)
    addSection(ctx, "positions", wnd, "nnpPositionFrame", "Frame Anchor", "Move the whole nameplate block relative to the game name tag.", 24, 112, 700)

    local offsetSliders = {}
    for _, item in ipairs(ctx.Schema.LAYOUT_SLIDERS or {}) do
        if item.key == "x_offset" or item.key == "y_offset" then
            offsetSliders[#offsetSliders + 1] = item
        end
    end
    for index, item in ipairs(offsetSliders) do
        addStyleSliderControl(ctx, "positions", wnd, "nnpPositionFrameSlider", item, 24 + ((index - 1) * 364), 160)
    end

    addSection(ctx, "positions", wnd, "nnpPositionText", "Text Offsets", "Fine-tune text only after size and layout feel right.", 24, 250, 700)
    local shown = 0
    eachSlider(ctx.Schema.TEXT_SLIDERS, function(index, item)
        if index >= 10 then
            shown = shown + 1
            local colX = shown <= 4 and 24 or 388
            local row = shown <= 4 and shown or (shown - 4)
            addStyleSliderControl(ctx, "positions", wnd, "nnpPositionTextSlider", item, colX, 298 + ((row - 1) * 34))
        end
    end)
end

function Pages.BuildCcPage(ctx, wnd)
    addSection(ctx, "cc", wnd, "nnpCcVisibility", "Filters", "Choose which CC families deserve icons and which can stay hidden.", 24, 112, 700)
    local ccToggles = ctx.Schema.CC_TOGGLES or {}
    local splitIndex = math.max(1, math.ceil(#ccToggles / 2))
    for index, item in ipairs(ccToggles) do
        local isRightColumn = index > splitIndex
        local colX = isRightColumn and 396 or 24
        local rowIndex = isRightColumn and (index - splitIndex) or index
        local rowY = 160 + ((rowIndex - 1) * 32)
        local cb = ctx.createCheckbox("nnpCcToggle" .. item.key, wnd, item.label, colX, rowY, 220)
        ctx.addPageWidget("cc", cb.button)
        ctx.addPageWidget("cc", cb.label)
        ctx.SettingsUi.controls["cc_toggle_" .. item.key] = cb
        bindStyleToggle(ctx, item, cb)
    end

    addSection(ctx, "cc", wnd, "nnpCcRules", "Rules", "Anchor and icon count change the overall footprint more than size alone.", 24, 350, 700)
    local ccChoices = ctx.Schema.CC_CHOICES or {}
    local ccChoiceRows = math.max(1, math.ceil(#ccChoices / 2))
    for index, item in ipairs(ccChoices) do
        local localIndex = index - 1
        local colX = (localIndex % 2 == 0) and 24 or 396
        local rowY = 398 + (math.floor(localIndex / 2) * 34)
        local label, btn = ctx.createChoiceRow("nnpCcChoice" .. item.key, wnd, item.label, colX, rowY, 170)
        ctx.addPageWidget("cc", label)
        ctx.addPageWidget("cc", btn)
        ctx.SettingsUi.controls["cc_choice_" .. item.key] = btn
        bindStyleChoice(ctx, item, btn)
    end

    local placementSectionY = 462 + ((ccChoiceRows - 1) * 42)
    local placementSliderStartY = 510 + ((ccChoiceRows - 1) * 42)
    addSection(ctx, "cc", wnd, "nnpCcPlacement", "Placement", "Size and offsets decide how close CC sits to the bar and text.", 24, placementSectionY, 700)
    eachSlider(ctx.Schema.CC_SLIDERS or {}, function(index, item)
        local colX = index <= 3 and 24 or 388
        local localIndex = index <= 3 and index or (index - 3)
        local rowY = placementSliderStartY + ((localIndex - 1) * 34)
        local label, slider, value = createTightSlider(ctx, "nnpCcSlider" .. item.key, wnd, item.label, colX, rowY, item.min, item.max)
        ctx.addPageWidget("cc", label)
        ctx.addPageWidget("cc", slider)
        ctx.addPageWidget("cc", value)
        ctx.SettingsUi.controls["cc_slider_" .. item.key] = slider
        ctx.SettingsUi.controls["cc_slider_val_" .. item.key] = value
        bindStyleSlider(ctx, item, slider, value)
    end)

    local alertsSectionY = placementSliderStartY + 98
    addSection(ctx, "cc", wnd, "nnpAlerts", "Alerts", "Flash urgent HP-bar borders without changing icon placement.", 24, alertsSectionY, 700)
    for index, item in ipairs(ctx.Schema.ALERT_TOGGLES or {}) do
        local colX = index == 1 and 24 or 388
        local cb = ctx.createCheckbox("nnpAlertToggle" .. item.key, wnd, item.label, colX, alertsSectionY + 48, 260)
        ctx.addPageWidget("cc", cb.button)
        ctx.addPageWidget("cc", cb.label)
        ctx.SettingsUi.controls["alert_toggle_" .. item.key] = cb
        bindStyleToggle(ctx, item, cb)
    end
    eachSlider(ctx.Schema.ALERT_SLIDERS or {}, function(index, item)
        local rowY = alertsSectionY + 84 + ((index - 1) * 34)
        local label, slider, value = createTightSlider(ctx, "nnpAlertSlider" .. item.key, wnd, item.label, 24, rowY, item.min, item.max)
        ctx.addPageWidget("cc", label)
        ctx.addPageWidget("cc", slider)
        ctx.addPageWidget("cc", value)
        ctx.SettingsUi.controls["alert_slider_" .. item.key] = slider
        ctx.SettingsUi.controls["alert_slider_val_" .. item.key] = value
        bindStyleSlider(ctx, item, slider, value)
    end)
end

function Pages.BuildAdvancedPage(ctx, wnd)
    addSection(ctx, "advanced", wnd, "nnpAdvancedAnchor", "Anchoring", nil, 24, 112, 320)
    addGlobalToggleControl(ctx, "advanced", wnd, "anchor_to_nametag", 24, 148, 260)

    addSection(ctx, "advanced", wnd, "nnpLauncher", "Launcher", nil, 388, 112, 320)
    local label, slider, value = ctx.createSlider("nnpGlobalSliderButtonSize", wnd, "Icon size", 388, 148, 32, 96, {
        label_width = 104,
        slider_width = 150,
        value_width = 44,
        slider_offset = 102,
        value_offset = 260
    })
    ctx.addPageWidget("advanced", label)
    ctx.addPageWidget("advanced", slider)
    ctx.addPageWidget("advanced", value)
    ctx.SettingsUi.controls.global_slider_button_size = slider
    ctx.SettingsUi.controls.global_slider_val_button_size = value
    bindGlobalSlider(ctx, "button_size", slider, value)

    addSection(ctx, "advanced", wnd, "nnpLayer", "Draw Layer", nil, 24, 248, 700)
    local choice = (ctx.Schema.GLOBAL_CHOICES or {})[1]
    local choiceY = 286
    if choice ~= nil then
        local label, button = ctx.createChoiceRow("nnpGlobalChoice" .. choice.key, wnd, choice.label, 24, choiceY, 156)
        ctx.addPageWidget("advanced", label)
        if choice.use_option_buttons then
            if button.Show ~= nil then
                button:Show(false)
            end
        else
            ctx.addPageWidget("advanced", button)
            ctx.SettingsUi.controls["global_choice_" .. choice.key] = button
            bindGlobalChoice(ctx, choice, button)
        end

        local columns = 3
        local buttonWidth = 150
        local buttonGapX = 10
        local buttonGapY = 8
        local startX = 196
        local startY = choiceY - 2
        local descY = choiceY + 34
        for index, option in ipairs(choice.options or {}) do
            local col = (index - 1) % columns
            local row = math.floor((index - 1) / columns)
            local buttonX = startX + (col * (buttonWidth + buttonGapX))
            local buttonY = startY + (row * (28 + buttonGapY))
            local optionBtn = ctx.createButton(
                "nnpGlobalChoiceOption" .. choice.key .. tostring(index),
                wnd,
                tostring(option.label or option.value or ""),
                buttonX,
                buttonY,
                buttonWidth,
                28
            )
            ctx.addPageWidget("advanced", optionBtn)
            ctx.SettingsUi.controls["global_choice_option_" .. choice.key .. "_" .. tostring(option.value)] = optionBtn
            bindGlobalChoiceOption(ctx, choice, option, optionBtn)
            descY = math.max(descY, buttonY + 40)
        end

        local desc = ctx.createLabel("nnpGlobalChoiceDesc" .. choice.key, wnd, "", 24, descY, 12, 700)
        ctx.addPageWidget("advanced", desc)
        ctx.SettingsUi.controls["global_choice_desc_" .. choice.key] = desc
        ctx.addPageWidget("advanced", ctx.createLabel("nnpLayerHint1", wnd, "Game or Background usually keeps bars under map, bags, and bigger AAClassic windows.", 24, descY + 22, 12, 700))
    end

    addSection(ctx, "advanced", wnd, "nnpRuntime", "Runtime", nil, 24, 542, 700)
    for index = 1, 3 do
        local line = ctx.createLabel("nnpRuntimeLine" .. tostring(index), wnd, "", 24, 574 + ((index - 1) * 22), 12, 700)
        ctx.addPageWidget("advanced", line)
        ctx.SettingsUi.controls["runtime_line_" .. tostring(index)] = line
    end
    local runtimeWarn = ctx.createLabel("nnpRuntimeWarn", wnd, "", 24, 648, 12, 700)
    ctx.addPageWidget("advanced", runtimeWarn)
    ctx.SettingsUi.controls.runtime_warning = runtimeWarn
end

function Pages.BuildColorsPage(ctx, wnd)
    ctx.addPageWidget("colors", ctx.createLabel("nnpColorTitle", wnd, "Colors", 24, 98, 16, 220))
    ctx.addPageWidget("colors", ctx.createLabel("nnpColorHint", wnd, "Tune bars and text without losing existing saved palettes. Click any swatch to edit a single color.", 24, 122, 12, 680))
    ctx.addPageWidget("colors", ctx.createLabel("nnpColorHint2", wnd, "Presets leave colors alone. Reset only changes the one color you press it on.", 24, 144, 12, 680))

    local prevBtn = ctx.createButton("nnpColorsPrev", wnd, "<", 548, 96, 34, 26)
    local nextBtn = ctx.createButton("nnpColorsNext", wnd, ">", 688, 96, 34, 26)
    local pageLabel = ctx.createLabel("nnpColorsPage", wnd, "Page 1 / 1", 590, 100, 12, 92)
    ctx.addPageWidget("colors", prevBtn)
    ctx.addPageWidget("colors", nextBtn)
    ctx.addPageWidget("colors", pageLabel)
    ctx.SettingsUi.controls.color_prev = prevBtn
    ctx.SettingsUi.controls.color_next = nextBtn
    ctx.SettingsUi.controls.color_page_label = pageLabel

    local groupsPerPage = 6
    ctx.SettingsUi.color_page = 1
    ctx.SettingsUi.color_page_count = math.max(1, math.ceil(#ctx.Schema.COLOR_GROUPS / groupsPerPage))
    ctx.SettingsUi.color_group_widgets = {}
    ctx.SettingsUi.color_cards = {}

    if prevBtn ~= nil and prevBtn.SetHandler ~= nil then
        prevBtn:SetHandler("OnClick", function()
            if ctx.closeColorPicker ~= nil then
                ctx.closeColorPicker(true)
            end
            ctx.SettingsUi.color_page = math.max(1, (ctx.SettingsUi.color_page or 1) - 1)
            if ctx.SettingsUi.Refresh ~= nil then
                ctx.SettingsUi.Refresh()
            end
        end)
    end
    if nextBtn ~= nil and nextBtn.SetHandler ~= nil then
        nextBtn:SetHandler("OnClick", function()
            if ctx.closeColorPicker ~= nil then
                ctx.closeColorPicker(true)
            end
            ctx.SettingsUi.color_page = math.min(ctx.SettingsUi.color_page_count or 1, (ctx.SettingsUi.color_page or 1) + 1)
            if ctx.SettingsUi.Refresh ~= nil then
                ctx.SettingsUi.Refresh()
            end
        end)
    end

    for index, group in ipairs(ctx.Schema.COLOR_GROUPS or {}) do
        local page = math.floor((index - 1) / groupsPerPage) + 1
        local pageIndex = ((index - 1) % groupsPerPage) + 1
        local col = (pageIndex - 1) % 2
        local row = math.floor((pageIndex - 1) / 2)
        local colX = col == 0 and 24 or 388
        local baseY = 184 + (row * 172)
        local card = ctx.createColorCard(group, wnd, colX, baseY, 334, 154)
        local groupWidgets = {}
        if card ~= nil and card.root ~= nil then
            groupWidgets[1] = card.root
            ctx.addPageWidget("colors", card.root)
        end
        ctx.SettingsUi.color_group_widgets[group.key] = {
            page = page,
            widgets = groupWidgets
        }
    end

    if ctx.ensureColorPicker ~= nil then
        ctx.ensureColorPicker(wnd)
    end
end

return Pages
