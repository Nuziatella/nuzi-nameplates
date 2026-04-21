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
    ctx.addPageWidget("general", ctx.createLabel("ghbGeneralTitle", wnd, "General", 24, 98, 16, 220))
    ctx.addPageWidget("general", ctx.createLabel("ghbGeneralHint", wnd, "Quick setup for presets, tracking, layer, and launcher size.", 24, 122, 12, 700))

    addSection(ctx, "general", wnd, "ghbPreset", "Presets", nil, 24, 154, 700)
    local presetButtons = ctx.Schema.STYLE_PRESETS or {}
    for index, preset in ipairs(presetButtons) do
        local col = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local buttonX = 24 + (col * 188)
        local buttonY = 186 + (row * 54)
        local button = ctx.createButton("ghbPresetBtn" .. tostring(preset.key), wnd, tostring(preset.label or preset.key or "Preset"), buttonX, buttonY, 156, 30)
        ctx.addPageWidget("general", button)
        button:SetHandler("OnClick", function()
            applyPreset(ctx, preset)
        end)
    end
    ctx.addPageWidget("general", ctx.createLabel("ghbPresetLegend", wnd, "Raid balanced | Compact tight | Large bigger | Minimal low-noise", 24, 298, 12, 700))

    addSection(ctx, "general", wnd, "ghbRuntime", "Runtime", nil, 24, 338, 320)
    for index = 1, 3 do
        local line = ctx.createLabel("ghbRuntimeLine" .. tostring(index), wnd, "", 24, 370 + ((index - 1) * 22), 12, 320)
        ctx.addPageWidget("general", line)
        ctx.SettingsUi.controls["runtime_line_" .. tostring(index)] = line
    end
    local runtimeWarn = ctx.createLabel("ghbRuntimeWarn", wnd, "", 24, 438, 12, 320)
    ctx.addPageWidget("general", runtimeWarn)
    ctx.SettingsUi.controls.runtime_warning = runtimeWarn

    addSection(ctx, "general", wnd, "ghbTracking", "Tracking", nil, 392, 338, 320)
    for index, item in ipairs(ctx.Schema.GLOBAL_TOGGLES or {}) do
        local rowY = 370 + ((index - 1) * 28)
        local cb = ctx.createCheckbox("ghbGlobal" .. item.key, wnd, item.label, 392, rowY, 220)
        ctx.addPageWidget("general", cb.button)
        ctx.addPageWidget("general", cb.label)
        ctx.SettingsUi.controls["global_" .. item.key] = cb
        bindGlobalToggle(ctx, item, cb)
    end

    addSection(ctx, "general", wnd, "ghbLayer", "Layer", nil, 24, 546, 700)
    local choice = (ctx.Schema.GLOBAL_CHOICES or {})[1]
    local choiceY = 578
    if choice ~= nil then
        local label, button = ctx.createChoiceRow("ghbGlobalChoice" .. choice.key, wnd, choice.label, 24, choiceY, 156)
        ctx.addPageWidget("general", label)
        if choice.use_option_buttons then
            if button.Show ~= nil then
                button:Show(false)
            end
        else
            ctx.addPageWidget("general", button)
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
                "ghbGlobalChoiceOption" .. choice.key .. tostring(index),
                wnd,
                tostring(option.label or option.value or ""),
                buttonX,
                buttonY,
                buttonWidth,
                28
            )
            ctx.addPageWidget("general", optionBtn)
            ctx.SettingsUi.controls["global_choice_option_" .. choice.key .. "_" .. tostring(option.value)] = optionBtn
            bindGlobalChoiceOption(ctx, choice, option, optionBtn)
            descY = math.max(descY, buttonY + 40)
        end

        local desc = ctx.createLabel("ghbGlobalChoiceDesc" .. choice.key, wnd, "", 24, descY, 12, 700)
        ctx.addPageWidget("general", desc)
        ctx.SettingsUi.controls["global_choice_desc_" .. choice.key] = desc
        ctx.addPageWidget("general", ctx.createLabel("ghbLayerHint1", wnd, "Tip: Game or Background usually keeps bars under map, bags, and bigger AAClassic windows.", 24, descY + 22, 12, 700))
    end

    addSection(ctx, "general", wnd, "ghbLauncher", "Launcher", nil, 24, 728, 700)
    local label, slider, value = ctx.createSlider("ghbGlobalSliderButtonSize", wnd, "Icon size", 24, 760, 32, 96, {
        label_width = 120,
        slider_width = 190,
        value_width = 44,
        slider_offset = 116,
        value_offset = 314
    })
    ctx.addPageWidget("general", label)
    ctx.addPageWidget("general", slider)
    ctx.addPageWidget("general", value)
    ctx.SettingsUi.controls.global_slider_button_size = slider
    ctx.SettingsUi.controls.global_slider_val_button_size = value
    bindGlobalSlider(ctx, "button_size", slider, value)
end

function Pages.BuildLayoutPage(ctx, wnd)
    ctx.addPageWidget("layout", ctx.createLabel("ghbLayoutTitle", wnd, "Layout", 24, 98, 16, 220))
    ctx.addPageWidget("layout", ctx.createLabel("ghbLayoutHint", wnd, "Tune what shows, how the frame is built, and where the bar sits.", 24, 122, 12, 660))

    addSection(ctx, "layout", wnd, "ghbLayoutVisibility", "Visibility", "Pick which pieces of each bar stay visible.", 24, 154, 700)
    for index, item in ipairs(ctx.Schema.STYLE_TOGGLES or {}) do
        local colX = index <= 4 and 24 or 364
        local rowY = 202 + (((index - 1) % 4) * 34)
        local cb = ctx.createCheckbox("ghbStyleToggle" .. item.key, wnd, item.label, colX, rowY, 210)
        ctx.addPageWidget("layout", cb.button)
        ctx.addPageWidget("layout", cb.label)
        ctx.SettingsUi.controls["style_toggle_" .. item.key] = cb
        bindStyleToggle(ctx, item, cb)
    end

    addSection(ctx, "layout", wnd, "ghbLayoutMode", "Style", "Switch how names and values are arranged before you fine-tune sliders.", 24, 360, 700)
    for index, item in ipairs(ctx.Schema.STYLE_CHOICES or {}) do
        local col = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local rowY = 408 + (row * 42)
        local colX = col == 0 and 24 or 388
        local label, btn = ctx.createChoiceRow("ghbChoice" .. item.key, wnd, item.label, colX, rowY, 170)
        ctx.addPageWidget("layout", label)
        ctx.addPageWidget("layout", btn)
        ctx.SettingsUi.controls["style_choice_" .. item.key] = btn
        bindStyleChoice(ctx, item, btn)
    end

    addSection(ctx, "layout", wnd, "ghbLayoutFrame", "Frame", "Size, alpha, range, and anchor offsets for the full bar block.", 24, 532, 700)
    eachSlider(ctx.Schema.LAYOUT_SLIDERS, function(index, item)
        local colX = index <= 5 and 24 or 388
        local localIndex = index <= 5 and index or (index - 5)
        local rowY = 580 + ((localIndex - 1) * 34)
        local label, slider, value = createTightSlider(ctx, "ghbLayoutSlider" .. item.key, wnd, item.label, colX, rowY, item.min, item.max)
        ctx.addPageWidget("layout", label)
        ctx.addPageWidget("layout", slider)
        ctx.addPageWidget("layout", value)
        ctx.SettingsUi.controls["style_slider_" .. item.key] = slider
        ctx.SettingsUi.controls["style_slider_val_" .. item.key] = value
        bindStyleSlider(ctx, item, slider, value)
    end)
end

function Pages.BuildTextPage(ctx, wnd)
    ctx.addPageWidget("text", ctx.createLabel("ghbTextTitle", wnd, "Text", 24, 98, 16, 220))
    ctx.addPageWidget("text", ctx.createLabel("ghbTextHint", wnd, "Use 0 chars for full names. Value X/Y moves both HP and MP text together.", 24, 122, 12, 700))

    addSection(ctx, "text", wnd, "ghbTextFonts", "Fonts and Limits", "Tune sizes first, then trim names only if the bars still feel crowded.", 24, 154, 700)
    eachSlider(ctx.Schema.TEXT_SLIDERS, function(index, item)
        if index <= 9 then
            local colX = index <= 5 and 24 or 388
            local localIndex = index <= 5 and index or (index - 5)
            local rowY = 202 + ((localIndex - 1) * 34)
            local label, slider, value = createTightSlider(ctx, "ghbTextSlider" .. item.key, wnd, item.label, colX, rowY, item.min, item.max)
            ctx.addPageWidget("text", label)
            ctx.addPageWidget("text", slider)
            ctx.addPageWidget("text", value)
            ctx.SettingsUi.controls["style_slider_" .. item.key] = slider
            ctx.SettingsUi.controls["style_slider_val_" .. item.key] = value
            bindStyleSlider(ctx, item, slider, value)
        end
    end)

    addSection(ctx, "text", wnd, "ghbTextOffsets", "Offsets", "Use offsets only after the font sizes feel right.", 24, 402, 700)
    eachSlider(ctx.Schema.TEXT_SLIDERS, function(index, item)
        if index >= 10 then
            local offsetIndex = index - 9
            local colX = offsetIndex <= 4 and 24 or 388
            local localIndex = offsetIndex <= 4 and offsetIndex or (offsetIndex - 4)
            local rowY = 450 + ((localIndex - 1) * 34)
            local label, slider, value = createTightSlider(ctx, "ghbTextSlider" .. item.key, wnd, item.label, colX, rowY, item.min, item.max)
            ctx.addPageWidget("text", label)
            ctx.addPageWidget("text", slider)
            ctx.addPageWidget("text", value)
            ctx.SettingsUi.controls["style_slider_" .. item.key] = slider
            ctx.SettingsUi.controls["style_slider_val_" .. item.key] = value
            bindStyleSlider(ctx, item, slider, value)
        end
    end)
end

function Pages.BuildCcPage(ctx, wnd)
    ctx.addPageWidget("cc", ctx.createLabel("ghbCcTitle", wnd, "Crowd Control", 24, 98, 16, 220))
    ctx.addPageWidget("cc", ctx.createLabel("ghbCcHint", wnd, "Attach CC icons and timers directly to the bar frame, then tune size and placement.", 24, 122, 12, 700))

    addSection(ctx, "cc", wnd, "ghbCcVisibility", "Filters", "Choose which CC families deserve icons and which can stay hidden.", 24, 154, 700)
    local ccToggles = ctx.Schema.CC_TOGGLES or {}
    local splitIndex = math.max(1, math.ceil(#ccToggles / 2))
    for index, item in ipairs(ccToggles) do
        local isRightColumn = index > splitIndex
        local colX = isRightColumn and 396 or 24
        local rowIndex = isRightColumn and (index - splitIndex) or index
        local rowY = 202 + ((rowIndex - 1) * 32)
        local cb = ctx.createCheckbox("ghbCcToggle" .. item.key, wnd, item.label, colX, rowY, 220)
        ctx.addPageWidget("cc", cb.button)
        ctx.addPageWidget("cc", cb.label)
        ctx.SettingsUi.controls["cc_toggle_" .. item.key] = cb
        bindStyleToggle(ctx, item, cb)
    end

    addSection(ctx, "cc", wnd, "ghbCcRules", "Rules", "Anchor and icon count change the overall footprint more than size alone.", 24, 392, 700)
    local ccChoices = ctx.Schema.CC_CHOICES or {}
    local ccChoiceRows = math.max(1, math.ceil(#ccChoices / 2))
    for index, item in ipairs(ccChoices) do
        local localIndex = index - 1
        local colX = (localIndex % 2 == 0) and 24 or 396
        local rowY = 440 + (math.floor(localIndex / 2) * 34)
        local label, btn = ctx.createChoiceRow("ghbCcChoice" .. item.key, wnd, item.label, colX, rowY, 170)
        ctx.addPageWidget("cc", label)
        ctx.addPageWidget("cc", btn)
        ctx.SettingsUi.controls["cc_choice_" .. item.key] = btn
        bindStyleChoice(ctx, item, btn)
    end

    local placementSectionY = 504 + ((ccChoiceRows - 1) * 42)
    local placementSliderStartY = 552 + ((ccChoiceRows - 1) * 42)
    addSection(ctx, "cc", wnd, "ghbCcPlacement", "Placement", "Size and offsets decide how close CC sits to the bar and text.", 24, placementSectionY, 700)
    eachSlider(ctx.Schema.CC_SLIDERS or {}, function(index, item)
        local colX = index <= 3 and 24 or 388
        local localIndex = index <= 3 and index or (index - 3)
        local rowY = placementSliderStartY + ((localIndex - 1) * 34)
        local label, slider, value = createTightSlider(ctx, "ghbCcSlider" .. item.key, wnd, item.label, colX, rowY, item.min, item.max)
        ctx.addPageWidget("cc", label)
        ctx.addPageWidget("cc", slider)
        ctx.addPageWidget("cc", value)
        ctx.SettingsUi.controls["cc_slider_" .. item.key] = slider
        ctx.SettingsUi.controls["cc_slider_val_" .. item.key] = value
        bindStyleSlider(ctx, item, slider, value)
    end)
end

function Pages.BuildColorsPage(ctx, wnd)
    ctx.addPageWidget("colors", ctx.createLabel("ghbColorTitle", wnd, "Colors", 24, 98, 16, 220))
    ctx.addPageWidget("colors", ctx.createLabel("ghbColorHint", wnd, "Tune bars and text without losing existing saved palettes. Click any swatch to edit a single color.", 24, 122, 12, 680))
    ctx.addPageWidget("colors", ctx.createLabel("ghbColorHint2", wnd, "Presets leave colors alone. Reset only changes the one color you press it on.", 24, 144, 12, 680))

    local prevBtn = ctx.createButton("ghbColorsPrev", wnd, "<", 548, 96, 34, 26)
    local nextBtn = ctx.createButton("ghbColorsNext", wnd, ">", 688, 96, 34, 26)
    local pageLabel = ctx.createLabel("ghbColorsPage", wnd, "Page 1 / 1", 590, 100, 12, 92)
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
