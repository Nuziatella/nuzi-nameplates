local Shared = nil
do
    local ok, mod = pcall(require, "nuzi-nameplates/shared")
    if ok then
        Shared = mod
    else
        ok, mod = pcall(require, "nuzi-nameplates.shared")
        if ok then
            Shared = mod
        end
    end
end

local Helpers = {}

local function clamp(v, lo, hi, default)
    return Shared.Clamp(v, lo, hi, default)
end

local function ensureCache(widget)
    if widget == nil then
        return nil
    end
    local cache = nil
    pcall(function()
        cache = widget.__nnp_cache
    end)
    if type(cache) ~= "table" then
        cache = {}
        pcall(function()
            widget.__nnp_cache = cache
        end)
    end
    return cache
end

function Helpers.SafeShow(widget, show)
    if widget ~= nil and widget.Show ~= nil then
        local want = show and true or false
        local cache = ensureCache(widget)
        if cache ~= nil and cache.visible == want then
            return
        end
        local ok = pcall(function()
            widget:Show(want)
        end)
        if ok and cache ~= nil then
            cache.visible = want
        end
    end
end

function Helpers.SafeClickable(widget, clickable)
    if widget ~= nil and widget.Clickable ~= nil then
        local want = clickable and true or false
        local cache = ensureCache(widget)
        if cache ~= nil and cache.clickable == want then
            return
        end
        local ok = pcall(function()
            widget:Clickable(want)
        end)
        if ok and cache ~= nil then
            cache.clickable = want
        end
    end
end

function Helpers.SafeSetText(widget, text)
    if widget ~= nil and widget.SetText ~= nil then
        local want = tostring(text or "")
        local cache = ensureCache(widget)
        if cache ~= nil and cache.text == want then
            return
        end
        local ok = pcall(function()
            widget:SetText(want)
        end)
        if ok and cache ~= nil then
            cache.text = want
        end
    end
end

function Helpers.SafeSetAlpha(widget, alpha01)
    if widget ~= nil and widget.SetAlpha ~= nil then
        local want = clamp(alpha01, 0, 1, 1)
        local cache = ensureCache(widget)
        if cache ~= nil and cache.alpha == want then
            return
        end
        local ok = pcall(function()
            widget:SetAlpha(want)
        end)
        if ok and cache ~= nil then
            cache.alpha = want
        end
    end
end

function Helpers.SafeAnchor(widget, point, rel, relPoint, x, y)
    if widget == nil or widget.AddAnchor == nil then
        return
    end
    local cache = ensureCache(widget)
    local key = table.concat({
        tostring(point or ""),
        tostring(rel or ""),
        tostring(relPoint or ""),
        tostring(x or ""),
        tostring(y or "")
    }, "|")
    if cache ~= nil and cache.anchor_key == key then
        return
    end
    local clearOk = pcall(function()
        if widget.RemoveAllAnchors ~= nil then
            widget:RemoveAllAnchors()
        end
    end)
    local ok = pcall(function()
        widget:AddAnchor(point, rel, relPoint, x, y)
    end)
    if ok then
        if cache ~= nil then
            cache.anchor_key = key
        end
        return
    end
    ok = pcall(function()
        widget:AddAnchor(point, rel, x, y)
    end)
    if ok and cache ~= nil then
        cache.anchor_key = key
    end
end

function Helpers.SafeSetExtent(widget, width, height)
    if widget == nil or widget.SetExtent == nil then
        return
    end
    local w = tonumber(width) or 0
    local h = tonumber(height) or 0
    local cache = ensureCache(widget)
    if cache ~= nil and cache.extent_w == w and cache.extent_h == h then
        return
    end
    local ok = pcall(function()
        widget:SetExtent(w, h)
    end)
    if ok and cache ~= nil then
        cache.extent_w = w
        cache.extent_h = h
    end
end

function Helpers.SafeSetBg(frame, enabled, alpha01)
    if frame == nil or frame.bg == nil then
        return
    end
    local wantVisible = enabled and true or false
    local wantAlpha = clamp(alpha01, 0, 1, 0.72)
    local cache = ensureCache(frame.bg)
    if cache == nil or cache.visible ~= wantVisible then
        local ok = pcall(function()
            frame.bg:Show(wantVisible)
        end)
        if ok and cache ~= nil then
            cache.visible = wantVisible
        end
    end
    if cache == nil or cache.bg_alpha ~= wantAlpha then
        local ok = pcall(function()
            if frame.bg.SetColor ~= nil then
                frame.bg:SetColor(1, 1, 1, wantAlpha)
            end
        end)
        if ok and cache ~= nil then
            cache.bg_alpha = wantAlpha
        end
    end
end

function Helpers.SafeSetDrawable(drawable, enabled, rgba255)
    if drawable == nil then
        return
    end
    local wantVisible = enabled and true or false
    local cache = ensureCache(drawable)
    if cache == nil or cache.visible ~= wantVisible then
        local ok = pcall(function()
            if drawable.Show ~= nil then
                drawable:Show(wantVisible)
            elseif drawable.SetVisible ~= nil then
                drawable:SetVisible(wantVisible)
            end
        end)
        if ok and cache ~= nil then
            cache.visible = wantVisible
        end
    end
    if type(rgba255) ~= "table" then
        return
    end
    local c = Helpers.Color01(rgba255, { 255, 255, 255, 255 })
    local colorKey = table.concat({
        tostring(c[1] or ""),
        tostring(c[2] or ""),
        tostring(c[3] or ""),
        tostring(c[4] or "")
    }, ",")
    if cache ~= nil and cache.color_key == colorKey then
        return
    end
    local ok = pcall(function()
        if drawable.SetColor ~= nil then
            drawable:SetColor(c[1], c[2], c[3], c[4])
        end
    end)
    if ok and cache ~= nil then
        cache.color_key = colorKey
    end
end

function Helpers.SetLabelStyle(label, fontSize, width, allowOverflow)
    if label == nil then
        return
    end
    local wantFont = tonumber(fontSize) or 0
    local wantWidth = tonumber(width) or 0
    local wantOverflow = allowOverflow and true or false
    local cache = ensureCache(label)
    local styleKey = table.concat({
        tostring(wantFont),
        tostring(wantWidth),
        tostring(wantOverflow)
    }, "|")
    if cache ~= nil and cache.label_style_key == styleKey then
        return
    end
    local ok = pcall(function()
        if label.SetLimitWidth ~= nil then
            label:SetLimitWidth(not wantOverflow)
        end
        if label.SetAutoResize ~= nil then
            label:SetAutoResize(wantOverflow)
        end
        Helpers.SafeSetExtent(label, wantWidth, wantFont + 6)
        if label.style ~= nil then
            if label.style.SetFontSize ~= nil then
                label.style:SetFontSize(wantFont)
            end
            if label.style.SetAlign ~= nil then
                label.style:SetAlign(ALIGN.LEFT)
            end
        end
    end)
    if ok and cache ~= nil then
        cache.label_style_key = styleKey
    end
end

function Helpers.MeasureTextWidth(label, text, fontSize, fallback)
    local width = nil
    if label ~= nil and label.style ~= nil and label.style.GetTextWidth ~= nil then
        pcall(function()
            width = label.style:GetTextWidth(tostring(text or ""))
        end)
    end
    width = tonumber(width)
    if width == nil then
        local len = string.len(tostring(text or ""))
        width = math.floor((tonumber(fontSize) or 12) * math.max(1, len) * 0.62)
    end
    if fallback ~= nil and width < fallback then
        width = fallback
    end
    return width
end

function Helpers.Color01(rgba255, fallback)
    local src = type(rgba255) == "table" and rgba255 or fallback or { 255, 255, 255, 255 }
    local r = clamp(src[1], 0, 255, 255) / 255
    local g = clamp(src[2], 0, 255, 255) / 255
    local b = clamp(src[3], 0, 255, 255) / 255
    local a = clamp(src[4], 0, 255, 255) / 255
    return { r, g, b, a }
end

function Helpers.SetLabelColor(label, rgba255, fallback)
    if label == nil then
        return
    end
    local c = Helpers.Color01(rgba255, fallback)
    local cache = ensureCache(label)
    local colorKey = table.concat({
        tostring(c[1] or ""),
        tostring(c[2] or ""),
        tostring(c[3] or ""),
        tostring(c[4] or "")
    }, ",")
    if cache ~= nil and cache.label_color_key == colorKey then
        return
    end
    local ok = pcall(function()
        if label.style ~= nil and label.style.SetColor ~= nil then
            label.style:SetColor(c[1], c[2], c[3], c[4])
        end
    end)
    if ok and cache ~= nil then
        cache.label_color_key = colorKey
    end
end

local function formatNumber(value)
    local n = tonumber(value)
    if n == nil then
        return "0"
    end
    local sign = ""
    if n < 0 then
        sign = "-"
        n = math.abs(n)
    end
    local raw = tostring(math.floor(n + 0.5))
    local parts = {}
    while #raw > 3 do
        table.insert(parts, 1, string.sub(raw, -3))
        raw = string.sub(raw, 1, #raw - 3)
    end
    table.insert(parts, 1, raw)
    return sign .. table.concat(parts, ",")
end

function Helpers.FormatValueText(mode, currentValue, maxValue)
    local currentNum = tonumber(currentValue) or 0
    local maxNum = tonumber(maxValue) or 0
    local pct = 0
    if maxNum > 0 then
        pct = math.floor(((currentNum / maxNum) * 100) + 0.5)
    end
    if mode == "current" then
        return formatNumber(currentNum)
    elseif mode == "percent" then
        return tostring(pct) .. "%"
    elseif mode == "both" then
        return string.format("%s / %s (%d%%)", formatNumber(currentNum), formatNumber(maxNum), pct)
    end
    return string.format("%s / %s", formatNumber(currentNum), formatNumber(maxNum))
end

function Helpers.ApplyStatusBarColor(statusBar, rgba)
    if statusBar == nil or type(rgba) ~= "table" then
        return
    end
    local cache = ensureCache(statusBar)
    local key = table.concat({
        tostring(rgba[1] or ""),
        tostring(rgba[2] or ""),
        tostring(rgba[3] or ""),
        tostring(rgba[4] or "")
    }, ",")
    if cache ~= nil and cache.statusbar_color_key == key then
        return
    end
    local ok = pcall(function()
        if statusBar.SetBarColor ~= nil then
            statusBar:SetBarColor(rgba[1], rgba[2], rgba[3], rgba[4])
        elseif statusBar.SetColor ~= nil then
            statusBar:SetColor(rgba[1], rgba[2], rgba[3], rgba[4])
        end
    end)
    if ok and cache ~= nil then
        cache.statusbar_color_key = key
    end
end

return Helpers
