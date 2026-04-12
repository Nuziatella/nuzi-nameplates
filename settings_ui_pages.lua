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

local function bindColorSlider(ctx, colorKey, channelIndex, slider, value)
    if slider == nil or slider.SetHandler == nil then
        return
    end
    slider:SetHandler("OnSliderChanged", function(_, raw)
        local style = ctx.Shared.GetStyleSettings()
        if type(style[colorKey]) ~= "table" then
            style[colorKey] = { 255, 255, 255, 255 }
        end
        local n = math.floor((tonumber(raw) or 0) + 0.5)
        style[colorKey][channelIndex] = n
        if value ~= nil and value.SetText ~= nil then
            value:SetText(tostring(n))
        end
        ctx.applyChanges()
    end)
end

function Pages.BuildGeneralPage(ctx, wnd)
    ctx.addPageWidget("general", ctx.createLabel("ghbGeneralTitle", wnd, "Global Behavior", 24, 98, 16, 220))
    ctx.addPageWidget("general", ctx.createLabel("ghbGeneralHint", wnd, "Tracking toggles and draw priority for overhead bars. Draw layer cycles through the client UI strata.", 24, 122, 12, 700))
    ctx.addPageWidget("general", ctx.createLabel("ghbRuntimeTitle", wnd, "Runtime", 24, 148, 15, 220))
    for index = 1, 3 do
        local line = ctx.createLabel("ghbRuntimeLine" .. tostring(index), wnd, "", 24, 172 + ((index - 1) * 20), 12, 760)
        ctx.addPageWidget("general", line)
        ctx.SettingsUi.controls["runtime_line_" .. tostring(index)] = line
    end
    local runtimeWarn = ctx.createLabel("ghbRuntimeWarn", wnd, "", 24, 236, 12, 700)
    ctx.addPageWidget("general", runtimeWarn)
    ctx.SettingsUi.controls.runtime_warning = runtimeWarn
    local leftX, rightX, startY, rowGap = 24, 380, 286, 42
    for index, item in ipairs(ctx.Schema.GLOBAL_TOGGLES) do
        local colX = index <= 5 and leftX or rightX
        local rowY = startY + (((index - 1) % 5) * rowGap)
        local cb = ctx.createCheckbox("ghbGlobal" .. item.key, wnd, item.label, colX, rowY, 260)
        ctx.addPageWidget("general", cb.button)
        ctx.addPageWidget("general", cb.label)
        ctx.SettingsUi.controls["global_" .. item.key] = cb
        bindGlobalToggle(ctx, item, cb)
    end
    local choiceY = 508
    for _, item in ipairs(ctx.Schema.GLOBAL_CHOICES or {}) do
        local label, btn = ctx.createChoiceRow("ghbGlobalChoice" .. item.key, wnd, item.label, 24, choiceY, 180)
        ctx.addPageWidget("general", label)
        if item.use_option_buttons then
            if btn.Show ~= nil then
                btn:Show(false)
            end
        else
            ctx.addPageWidget("general", btn)
            ctx.SettingsUi.controls["global_choice_" .. item.key] = btn
            bindGlobalChoice(ctx, item, btn)
        end

        local descY = choiceY + 82
        if item.use_option_buttons then
            local columns = 3
            local buttonWidth = 140
            local buttonHeight = 28
            local buttonGapX = 12
            local buttonGapY = 10
            local startX = 214
            local startY = choiceY - 2
            for index, option in ipairs(item.options or {}) do
                local col = (index - 1) % columns
                local row = math.floor((index - 1) / columns)
                local buttonX = startX + (col * (buttonWidth + buttonGapX))
                local buttonY = startY + (row * (buttonHeight + buttonGapY))
                local optionBtn = ctx.createButton(
                    "ghbGlobalChoiceOption" .. item.key .. tostring(index),
                    wnd,
                    tostring(option.label or option.value or ""),
                    buttonX,
                    buttonY,
                    buttonWidth,
                    buttonHeight
                )
                ctx.addPageWidget("general", optionBtn)
                ctx.SettingsUi.controls["global_choice_option_" .. item.key .. "_" .. tostring(option.value)] = optionBtn
                bindGlobalChoiceOption(ctx, item, option, optionBtn)
                descY = math.max(descY, buttonY + buttonHeight + 12)
            end
        end

        local desc = ctx.createLabel("ghbGlobalChoiceDesc" .. item.key, wnd, "", 24, descY, 12, 700)
        ctx.addPageWidget("general", desc)
        ctx.SettingsUi.controls["global_choice_desc_" .. item.key] = desc
        choiceY = descY + 30
        if type(item.help_lines) == "table" and #item.help_lines > 0 then
            local helpTitle = ctx.createLabel("ghbGlobalChoiceHelpTitle" .. item.key, wnd, "Layer Guide", 24, choiceY, 13, 180)
            ctx.addPageWidget("general", helpTitle)
            choiceY = choiceY + 24
            for index, line in ipairs(item.help_lines) do
                local help = ctx.createLabel("ghbGlobalChoiceHelp" .. item.key .. tostring(index), wnd, line, 24, choiceY, 12, 700)
                ctx.addPageWidget("general", help)
                choiceY = choiceY + 18
            end
            choiceY = choiceY + 10
        end
    end
end

function Pages.BuildLayoutPage(ctx, wnd)
    ctx.addPageWidget("layout", ctx.createLabel("ghbLayoutTitle", wnd, "Layout", 24, 98, 16, 220))
    ctx.addPageWidget("layout", ctx.createLabel("ghbLayoutHint", wnd, "Bar size, visibility, spacing, and overall placement.", 24, 122, 12, 520))

    local toggleLeftX, toggleRightX, toggleY, toggleGap = 24, 380, 164, 40
    for index, item in ipairs(ctx.Schema.STYLE_TOGGLES) do
        local colX = index <= 4 and toggleLeftX or toggleRightX
        local rowY = toggleY + (((index - 1) % 4) * toggleGap)
        local cb = ctx.createCheckbox("ghbStyleToggle" .. item.key, wnd, item.label, colX, rowY, 240)
        ctx.addPageWidget("layout", cb.button)
        ctx.addPageWidget("layout", cb.label)
        ctx.SettingsUi.controls["style_toggle_" .. item.key] = cb
        bindStyleToggle(ctx, item, cb)
    end

    local choiceY = 340
    for _, item in ipairs(ctx.Schema.STYLE_CHOICES) do
        local label, btn = ctx.createChoiceRow("ghbChoice" .. item.key, wnd, item.label, 24, choiceY, 190)
        ctx.addPageWidget("layout", label)
        ctx.addPageWidget("layout", btn)
        ctx.SettingsUi.controls["style_choice_" .. item.key] = btn
        bindStyleChoice(ctx, item, btn)
        choiceY = choiceY + 38
    end

    ctx.addPageWidget("layout", ctx.createLabel("ghbLayoutSliders", wnd, "Dimensions and Anchoring", 24, 424, 15, 260))
    eachSlider(ctx.Schema.LAYOUT_SLIDERS, function(index, item)
        local colX = index <= 5 and 24 or 500
        local localIndex = index <= 5 and index or (index - 5)
        local rowY = 458 + ((localIndex - 1) * 34)
        local label, slider, value = ctx.createSlider("ghbLayoutSlider" .. item.key, wnd, item.label, colX, rowY, item.min, item.max)
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
    ctx.addPageWidget("text", ctx.createLabel("ghbTextHint", wnd, "Font families are client-limited. Set max chars to 0 for full names, and use the shared HP/MP text offsets to move both values together.", 24, 122, 12, 760))

    eachSlider(ctx.Schema.TEXT_SLIDERS, function(index, item)
        local colX = index <= 9 and 24 or 500
        local localIndex = index <= 9 and index or (index - 9)
        local rowY = 168 + ((localIndex - 1) * 38)
        local label, slider, value = ctx.createSlider("ghbTextSlider" .. item.key, wnd, item.label, colX, rowY, item.min, item.max)
        ctx.addPageWidget("text", label)
        ctx.addPageWidget("text", slider)
        ctx.addPageWidget("text", value)
        ctx.SettingsUi.controls["style_slider_" .. item.key] = slider
        ctx.SettingsUi.controls["style_slider_val_" .. item.key] = value
        bindStyleSlider(ctx, item, slider, value)
    end)
end

function Pages.BuildCcPage(ctx, wnd)
    ctx.addPageWidget("cc", ctx.createLabel("ghbCcTitle", wnd, "Crowd Control", 24, 98, 16, 220))
    ctx.addPageWidget("cc", ctx.createLabel("ghbCcHint", wnd, "Attach CC icons and timers directly to the custom bar frames instead of using a separate floating widget.", 24, 122, 12, 700))

    local toggleLeftX = 24
    local toggleRightX = 380
    local toggleY = 170
    local toggleGap = 38
    local ccToggles = ctx.Schema.CC_TOGGLES or {}
    local splitIndex = math.max(1, math.ceil(#ccToggles / 2))
    for index, item in ipairs(ccToggles) do
        local isRightColumn = index > splitIndex
        local colX = isRightColumn and toggleRightX or toggleLeftX
        local rowIndex = isRightColumn and (index - splitIndex) or index
        local cb = ctx.createCheckbox("ghbCcToggle" .. item.key, wnd, item.label, colX, toggleY + ((rowIndex - 1) * toggleGap), 280)
        ctx.addPageWidget("cc", cb.button)
        ctx.addPageWidget("cc", cb.label)
        ctx.SettingsUi.controls["cc_toggle_" .. item.key] = cb
        bindStyleToggle(ctx, item, cb)
    end

    local toggleRows = math.max(splitIndex, #ccToggles - splitIndex)
    local choiceY = toggleY + (toggleRows * toggleGap) + 18
    for _, item in ipairs(ctx.Schema.CC_CHOICES or {}) do
        local label, btn = ctx.createChoiceRow("ghbCcChoice" .. item.key, wnd, item.label, 24, choiceY, 190)
        ctx.addPageWidget("cc", label)
        ctx.addPageWidget("cc", btn)
        ctx.SettingsUi.controls["cc_choice_" .. item.key] = btn
        bindStyleChoice(ctx, item, btn)
        choiceY = choiceY + 38
    end

    local sliderTitleY = choiceY + 24
    ctx.addPageWidget("cc", ctx.createLabel("ghbCcSliders", wnd, "Placement and Size", 24, sliderTitleY, 15, 260))
    eachSlider(ctx.Schema.CC_SLIDERS or {}, function(index, item)
        local colX = index <= 3 and 24 or 500
        local localIndex = index <= 3 and index or (index - 3)
        local rowY = sliderTitleY + 34 + ((localIndex - 1) * 38)
        local label, slider, value = ctx.createSlider("ghbCcSlider" .. item.key, wnd, item.label, colX, rowY, item.min, item.max)
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
    ctx.addPageWidget("colors", ctx.createLabel("ghbColorHint", wnd, "Tune HP/MP bars and text colors. Role colors use built-in tank/healer/melee/ranged/magic colors.", 24, 122, 12, 640))

    local prevBtn = ctx.createButton("ghbColorsPrev", wnd, "Prev", 500, 96, 70, 26)
    local nextBtn = ctx.createButton("ghbColorsNext", wnd, "Next", 652, 96, 70, 26)
    local pageLabel = ctx.createLabel("ghbColorsPage", wnd, "Page 1 / 1", 578, 100, 12, 70)
    ctx.addPageWidget("colors", prevBtn)
    ctx.addPageWidget("colors", nextBtn)
    ctx.addPageWidget("colors", pageLabel)
    ctx.SettingsUi.controls.color_prev = prevBtn
    ctx.SettingsUi.controls.color_next = nextBtn
    ctx.SettingsUi.controls.color_page_label = pageLabel

    local groupsPerPage = 4
    ctx.SettingsUi.color_page_count = math.max(1, math.ceil(#ctx.Schema.COLOR_GROUPS / groupsPerPage))
    ctx.SettingsUi.color_group_widgets = {}

    if prevBtn ~= nil and prevBtn.SetHandler ~= nil then
        prevBtn:SetHandler("OnClick", function()
            ctx.SettingsUi.color_page = math.max(1, (ctx.SettingsUi.color_page or 1) - 1)
            if ctx.SettingsUi.Refresh ~= nil then
                ctx.SettingsUi.Refresh()
            end
        end)
    end
    if nextBtn ~= nil and nextBtn.SetHandler ~= nil then
        nextBtn:SetHandler("OnClick", function()
            ctx.SettingsUi.color_page = math.min(ctx.SettingsUi.color_page_count or 1, (ctx.SettingsUi.color_page or 1) + 1)
            if ctx.SettingsUi.Refresh ~= nil then
                ctx.SettingsUi.Refresh()
            end
        end)
    end

    for index, group in ipairs(ctx.Schema.COLOR_GROUPS) do
        local page = math.floor((index - 1) / groupsPerPage) + 1
        local pageIndex = ((index - 1) % groupsPerPage) + 1
        local colX = pageIndex <= 2 and 24 or 500
        local localIndex = pageIndex <= 2 and pageIndex or (pageIndex - 2)
        local baseY = 170 + ((localIndex - 1) * 240)
        local groupWidgets = {}

        local title = ctx.createLabel("ghbColorGroup" .. group.key, wnd, group.label, colX, baseY, 15, 220)
        table.insert(groupWidgets, title)
        ctx.addPageWidget("colors", title)
        local channels = {
            { suffix = "R", index = 1, label = "Red" },
            { suffix = "G", index = 2, label = "Green" },
            { suffix = "B", index = 3, label = "Blue" }
        }
        for channelOffset, channel in ipairs(channels) do
            local y = baseY + 32 + ((channelOffset - 1) * 38)
            local item = { key = group.key .. "_" .. channel.suffix, label = channel.label, min = 0, max = 255 }
            local label, slider, value = ctx.createSlider("ghbColorSlider" .. group.key .. channel.suffix, wnd, item.label, colX, y, 0, 255)
            table.insert(groupWidgets, label)
            table.insert(groupWidgets, slider)
            table.insert(groupWidgets, value)
            ctx.addPageWidget("colors", label)
            ctx.addPageWidget("colors", slider)
            ctx.addPageWidget("colors", value)
            ctx.SettingsUi.controls["color_slider_" .. group.key .. "_" .. channel.index] = slider
            ctx.SettingsUi.controls["color_slider_val_" .. group.key .. "_" .. channel.index] = value
            bindColorSlider(ctx, group.key, channel.index, slider, value)
        end
        ctx.SettingsUi.color_group_widgets[group.key] = {
            page = page,
            widgets = groupWidgets
        }
    end
end

return Pages
