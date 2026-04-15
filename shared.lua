local api = require("api")

local Shared = {}

Shared.CONSTANTS = {
    ADDON_ID = "gharka-bars",
    TITLE = "Gharka Bars",
    VERSION = "1.5.41",
    BUTTON_ID = "gharkaBarsSettingsButton",
    WINDOW_ID = "gharkaBarsSettingsWindow",
    SETTINGS_FILE_PATH = "gharka-bars/.data/settings.txt",
    ICON_SETTINGS_FILE_PATH = "gharka-bars/.data/icon_settings.txt",
    PROFILE_STATE_FILE_PATH = "gharka-bars/.data/profile_state.txt",
    LEGACY_SETTINGS_FILE_PATH = "gharka-bars/settings.txt",
    SETTINGS_BACKUP_FILE_PATH = "gharka-bars/.data/settings_backup.txt",
    LEGACY_SETTINGS_BACKUP_FILE_PATH = "gharka-bars/settings_backup.txt",
    SETTINGS_BACKUP_INDEX_FILE_PATH = "gharka-bars/.data/backups/index.txt",
    LEGACY_SETTINGS_BACKUP_INDEX_FILE_PATH = "gharka-bars/backups/index.txt",
    SETTINGS_BACKUP_INDEX_FALLBACK_FILE_PATH = "gharka-bars/.data/settings_backup_index.txt",
    LEGACY_SETTINGS_BACKUP_INDEX_FALLBACK_FILE_PATH = "gharka-bars/settings_backup_index.txt",
    SETTINGS_BACKUP_DIR = "gharka-bars/.data/backups"
}

local function styleDefaults()
    return {
        width = 138,
        hp_height = 36,
        mp_height = 9,
        bar_gap = 0,
        alpha_pct = 100,
        bg_alpha_pct = 100,
        max_distance = 300,
        name_font_size = 16,
        name_max_chars = 8,
        guild_font_size = 12,
        guild_max_chars = 0,
        role_font_size = 20,
        value_font_size = 14,
        value_offset_x = 80,
        value_offset_y = -9,
        distance_font_size = 19,
        x_offset = 6,
        y_offset = 82,
        name_offset_x = 33,
        name_offset_y = 21,
        guild_offset_x = -80,
        guild_offset_y = 41,
        role_offset_x = 52,
        role_offset_y = 1,
        distance_offset_x = -16,
        distance_offset_y = 0,
        value_mode = "percent",
        name_layout = "horizontal",
        cluster_spacing_mode = "off",
        target_relation_mode = "legacy",
        show_name = true,
        show_guild = true,
        show_role = true,
        show_hp_text = true,
        show_mp_text = false,
        show_mp_bar = true,
        show_distance = true,
        show_background = true,
        show_cc = true,
        show_cc_timer = true,
        show_cc_secondary = true,
        show_cc_hard = true,
        show_cc_silence = true,
        show_cc_root = true,
        show_cc_slow = true,
        show_cc_dot = true,
        show_cc_misc = true,
        cc_anchor = "top",
        cc_max_icons = 4,
        cc_icon_size = 45,
        cc_secondary_icon_size = 25,
        cc_gap = 4,
        cc_offset_x = 0,
        cc_offset_y = -31,
        cc_timer_font_size = 11,
        hp_bar_color = { 255, 200, 251, 255 },
        hostile_bar_color = { 255, 0, 0, 255 },
        neutral_bar_color = { 184, 148, 52, 255 },
        mp_bar_color = { 46, 122, 240, 255 },
        bloodlust_team_color = { 255, 45, 0, 255 },
        bloodlust_target_color = { 170, 80, 255, 255 },
        name_color = { 255, 255, 255, 255 },
        guild_color = { 0, 255, 118, 255 },
        value_color = { 255, 178, 56, 255 },
        distance_color = { 255, 226, 140, 255 }
    }
end

Shared.DEFAULT_SETTINGS = {
    enabled = true,
    anchor_to_nametag = true,
    click_target = true,
    click_through_ctrl = true,
    click_through_shift = true,
    show_player = false,
    show_target = true,
    show_watchtarget = true,
    show_raid_party = true,
    show_mount = false,
    frame_layer_mode = "game",
    button_x = 40,
    button_y = 220,
    button_size = 48,
    window_x = 520,
    window_y = 90,
    full_name_migration_v1 = true,
    style = styleDefaults()
}

Shared.state = {
    settings = nil,
    profile_state = nil,
    icon_settings = nil
}

local function deepCopy(value, visited)
    if type(value) ~= "table" then
        return value
    end
    visited = visited or {}
    if visited[value] ~= nil then
        return visited[value]
    end
    local out = {}
    visited[value] = out
    for k, v in pairs(value) do
        out[deepCopy(k, visited)] = deepCopy(v, visited)
    end
    return out
end

local function mergeInto(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return
    end
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then
                dst[key] = {}
            end
            mergeInto(dst[key], value)
        else
            dst[key] = value
        end
    end
end

local function ensureDefaults(dst, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then
                dst[key] = deepCopy(value)
            else
                ensureDefaults(dst[key], value)
            end
        elseif dst[key] == nil then
            dst[key] = value
        end
    end
end

local function readTableFile(path)
    if api.File == nil or api.File.Read == nil then
        return nil
    end
    local ok, res = pcall(function()
        return api.File:Read(path)
    end)
    if ok and type(res) == "table" then
        return res
    end
    return nil
end

local function writeTableFile(path, tbl)
    if api.File == nil or api.File.Write == nil or type(tbl) ~= "table" then
        return false, "api.File:Write unavailable"
    end
    local ok, err = pcall(function()
        api.File:Write(path, tbl)
    end)
    if not ok then
        return false, tostring(err)
    end
    return true, ""
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

local function getFileName(path)
    local normalized = normalizePath(path)
    return string.match(normalized, "([^/]+)$") or normalized
end

local function ensureTxtExtension(name)
    local text = tostring(name or "")
    if string.match(string.lower(text), "%.txt$") ~= nil then
        return text
    end
    return text .. ".txt"
end

local function normalizeProfilePath(path)
    local text = trimText(path)
    if text == "" then
        return Shared.CONSTANTS.SETTINGS_FILE_PATH
    end
    text = normalizePath(text)
    if string.find(text, "/", 1, true) == nil then
        text = "gharka-bars/.data/" .. ensureTxtExtension(text)
    end
    return text
end

local function sanitizeProfileName(name)
    local text = trimText(name)
    text = string.gsub(text, "%.txt$", "")
    text = string.gsub(text, "[^%w%-%_ ]", "_")
    text = string.gsub(text, "%s+", "_")
    text = trimText(text)
    if text == "" then
        return nil
    end
    local lower = string.lower(text)
    if lower == "profile_state" or lower == "settings_backup" or lower == "settings_backup_index" then
        text = text .. "_profile"
    end
    return ensureTxtExtension(text)
end

local function listProfilePaths(state)
    local out = {}
    local seen = {}
    local function add(path)
        local normalized = normalizeProfilePath(path)
        if normalized == nil or seen[normalized] then
            return
        end
        seen[normalized] = true
        out[#out + 1] = normalized
    end
    add(Shared.CONSTANTS.SETTINGS_FILE_PATH)
    if type(state) == "table" then
        local count = tonumber(state.profile_count) or 0
        for index = 1, count do
            add(state[string.format("profile_%03d", index)])
        end
        add(state.active_profile)
    end
    table.sort(out, function(a, b)
        if a == Shared.CONSTANTS.SETTINGS_FILE_PATH then
            return true
        end
        if b == Shared.CONSTANTS.SETTINGS_FILE_PATH then
            return false
        end
        return string.lower(getFileName(a)) < string.lower(getFileName(b))
    end)
    return out
end

local function writeProfilePaths(state, paths)
    for key in pairs(state) do
        if string.match(tostring(key), "^profile_%d%d%d$") ~= nil then
            state[key] = nil
        end
    end
    state.profile_count = 0
    for index, path in ipairs(paths or {}) do
        state.profile_count = index
        state[string.format("profile_%03d", index)] = normalizeProfilePath(path)
    end
end

local function ensureIconSettings()
    if type(Shared.state.icon_settings) ~= "table" then
        Shared.state.icon_settings = {}
    end
    local state = Shared.state.icon_settings
    state.version = tonumber(state.version) or 1
    state.button_x = Shared.Clamp(state.button_x, 0, 4000, Shared.DEFAULT_SETTINGS.button_x)
    state.button_y = Shared.Clamp(state.button_y, 0, 4000, Shared.DEFAULT_SETTINGS.button_y)
    return state
end

local function saveIconSettings()
    return writeTableFile(Shared.CONSTANTS.ICON_SETTINGS_FILE_PATH, ensureIconSettings())
end

local function ensureProfileState()
    if type(Shared.state.profile_state) ~= "table" then
        Shared.state.profile_state = {}
    end
    local state = Shared.state.profile_state
    state.version = tonumber(state.version) or 1
    local paths = listProfilePaths(state)
    if #paths == 0 then
        paths = { Shared.CONSTANTS.SETTINGS_FILE_PATH }
    end
    writeProfilePaths(state, paths)
    state.active_profile = normalizeProfilePath(state.active_profile or Shared.CONSTANTS.SETTINGS_FILE_PATH)
    local activePresent = false
    for _, path in ipairs(paths) do
        if path == state.active_profile then
            activePresent = true
            break
        end
    end
    if not activePresent then
        paths[#paths + 1] = state.active_profile
        writeProfilePaths(state, paths)
    end
    state.window_x = Shared.Clamp(state.window_x, 0, 4000, Shared.DEFAULT_SETTINGS.window_x)
    state.window_y = Shared.Clamp(state.window_y, 0, 4000, Shared.DEFAULT_SETTINGS.window_y)
    return state
end

local function applyPersistentUiState(settings)
    if type(settings) ~= "table" then
        return settings
    end
    local iconState = ensureIconSettings()
    local state = ensureProfileState()
    settings.button_x = Shared.Clamp(iconState.button_x, 0, 4000, Shared.DEFAULT_SETTINGS.button_x)
    settings.button_y = Shared.Clamp(iconState.button_y, 0, 4000, Shared.DEFAULT_SETTINGS.button_y)
    settings.window_x = Shared.Clamp(state.window_x, 0, 4000, Shared.DEFAULT_SETTINGS.window_x)
    settings.window_y = Shared.Clamp(state.window_y, 0, 4000, Shared.DEFAULT_SETTINGS.window_y)
    return settings
end

local function saveProfileState()
    return writeTableFile(Shared.CONSTANTS.PROFILE_STATE_FILE_PATH, ensureProfileState())
end

function Shared.Clamp(value, minValue, maxValue, fallback)
    local n = tonumber(value)
    if n == nil then
        return fallback
    end
    if minValue ~= nil and n < minValue then
        return minValue
    end
    if maxValue ~= nil and n > maxValue then
        return maxValue
    end
    return n
end

function Shared.LoadSettings()
    local migrated = false
    local needsLocalBootstrap = false
    local needsIconBootstrap = false
    local profileState = readTableFile(Shared.CONSTANTS.PROFILE_STATE_FILE_PATH)
    if type(profileState) == "table" then
        Shared.state.profile_state = profileState
    else
        Shared.state.profile_state = {}
    end
    local iconState = readTableFile(Shared.CONSTANTS.ICON_SETTINGS_FILE_PATH)
    if type(iconState) == "table" then
        Shared.state.icon_settings = iconState
    else
        Shared.state.icon_settings = {}
        needsIconBootstrap = true
    end
    profileState = ensureProfileState()
    local activeProfilePath = normalizeProfilePath(profileState.active_profile)
    local loaded = readTableFile(activeProfilePath)
    if type(loaded) == "table" then
        Shared.state.settings = loaded
    elseif activeProfilePath ~= Shared.CONSTANTS.SETTINGS_FILE_PATH then
        needsLocalBootstrap = true
        profileState.active_profile = Shared.CONSTANTS.SETTINGS_FILE_PATH
        loaded = readTableFile(Shared.CONSTANTS.SETTINGS_FILE_PATH)
        if type(loaded) == "table" then
            Shared.state.settings = loaded
        end
    end
    if type(Shared.state.settings) ~= "table" then
        loaded = readTableFile(Shared.CONSTANTS.SETTINGS_FILE_PATH)
    end
    if type(loaded) == "table" and type(Shared.state.settings) ~= "table" then
        Shared.state.settings = loaded
    else
        if type(Shared.state.settings) ~= "table" then
            needsLocalBootstrap = true
            local legacyLoaded = readTableFile(Shared.CONSTANTS.LEGACY_SETTINGS_FILE_PATH)
            if type(legacyLoaded) == "table" then
                Shared.state.settings = legacyLoaded
                migrated = true
            elseif api.GetSettings ~= nil then
                Shared.state.settings = api.GetSettings(Shared.CONSTANTS.ADDON_ID) or {}
            else
                Shared.state.settings = {}
            end
        end
    end
    if needsIconBootstrap then
        local iconSettings = ensureIconSettings()
        iconSettings.button_x = Shared.Clamp(
            ensureProfileState().button_x ~= nil and ensureProfileState().button_x or (type(Shared.state.settings) == "table" and Shared.state.settings.button_x or nil),
            0,
            4000,
            Shared.DEFAULT_SETTINGS.button_x
        )
        iconSettings.button_y = Shared.Clamp(
            ensureProfileState().button_y ~= nil and ensureProfileState().button_y or (type(Shared.state.settings) == "table" and Shared.state.settings.button_y or nil),
            0,
            4000,
            Shared.DEFAULT_SETTINGS.button_y
        )
    end
    Shared.EnsureSettings()
    if migrated or needsLocalBootstrap then
        Shared.SaveSettings()
    end
    if needsIconBootstrap then
        saveIconSettings()
    end
    saveProfileState()
    return Shared.state.settings
end

function Shared.EnsureSettings()
    if type(Shared.state.settings) ~= "table" then
        Shared.state.settings = {}
    end
    ensureDefaults(Shared.state.settings, Shared.DEFAULT_SETTINGS)
    if type(Shared.state.settings.style) ~= "table" then
        Shared.state.settings.style = deepCopy(Shared.DEFAULT_SETTINGS.style)
    end
    local style = Shared.state.settings.style
    if Shared.state.settings.full_name_migration_v1 ~= true then
        style.name_max_chars = 0
        style.guild_max_chars = 0
        Shared.state.settings.full_name_migration_v1 = true
    end
    applyPersistentUiState(Shared.state.settings)
    return Shared.state.settings
end

function Shared.GetStyleSettings()
    local settings = Shared.EnsureSettings()
    if type(settings.style) ~= "table" then
        settings.style = deepCopy(Shared.DEFAULT_SETTINGS.style)
    end
    return settings.style
end

function Shared.ResetStyleSettings()
    Shared.EnsureSettings().style = deepCopy(Shared.DEFAULT_SETTINGS.style)
end

function Shared.ResetAllSettings()
    Shared.state.settings = deepCopy(Shared.DEFAULT_SETTINGS)
end

function Shared.SaveSettings()
    local settings = Shared.EnsureSettings()
    applyPersistentUiState(settings)
    if api.SaveSettings ~= nil then
        pcall(function()
            api.SaveSettings()
        end)
    end
    local ok, err = writeTableFile(normalizeProfilePath(ensureProfileState().active_profile), settings)
    if ok then
        saveProfileState()
    end
    return ok, err
end

function Shared.GetActiveProfilePath()
    return normalizeProfilePath(ensureProfileState().active_profile)
end

function Shared.GetActiveProfileFileName()
    return getFileName(Shared.GetActiveProfilePath())
end

function Shared.GetIconSettings()
    return ensureIconSettings()
end

function Shared.SaveIconPosition(x, y)
    local iconState = ensureIconSettings()
    iconState.button_x = Shared.Clamp(x, 0, 4000, Shared.DEFAULT_SETTINGS.button_x)
    iconState.button_y = Shared.Clamp(y, 0, 4000, Shared.DEFAULT_SETTINGS.button_y)
    if type(Shared.state.settings) == "table" then
        Shared.state.settings.button_x = iconState.button_x
        Shared.state.settings.button_y = iconState.button_y
    end
    return saveIconSettings()
end

function Shared.SetUiPosition(kind, x, y)
    if kind == "button" then
        Shared.SaveIconPosition(x, y)
        applyPersistentUiState(Shared.state.settings)
        return true
    elseif kind == "window" then
        local state = ensureProfileState()
        state.window_x = Shared.Clamp(x, 0, 4000, Shared.DEFAULT_SETTINGS.window_x)
        state.window_y = Shared.Clamp(y, 0, 4000, Shared.DEFAULT_SETTINGS.window_y)
    else
        return false
    end
    applyPersistentUiState(Shared.state.settings)
    saveProfileState()
    return true
end

function Shared.ListProfiles()
    local state = ensureProfileState()
    local activePath = normalizeProfilePath(state.active_profile)
    local out = {}
    for _, path in ipairs(listProfilePaths(state)) do
        out[#out + 1] = {
            path = path,
            file_name = getFileName(path),
            is_active = path == activePath
        }
    end
    return out
end

function Shared.SaveSettingsAsProfile(name)
    local fileName = sanitizeProfileName(name)
    if fileName == nil then
        return false, "enter a profile name"
    end
    local state = ensureProfileState()
    local previousActive = normalizeProfilePath(state.active_profile)
    state.active_profile = normalizeProfilePath(fileName)
    writeProfilePaths(state, listProfilePaths(state))
    local ok, err = Shared.SaveSettings()
    if not ok then
        state.active_profile = previousActive
        saveProfileState()
        return false, err
    end
    return true, getFileName(state.active_profile)
end

function Shared.LoadProfile(path)
    local normalizedPath = normalizeProfilePath(path)
    local parsed = readTableFile(normalizedPath)
    if type(parsed) ~= "table" then
        return false, "profile not found"
    end
    Shared.state.settings = {}
    mergeInto(Shared.state.settings, parsed)
    Shared.EnsureSettings()
    local state = ensureProfileState()
    state.active_profile = normalizedPath
    writeProfilePaths(state, listProfilePaths(state))
    local ok, err = Shared.SaveSettings()
    if not ok then
        return false, err
    end
    return true, getFileName(normalizedPath)
end

function Shared.SaveSettingsBackup()
    local settings = Shared.EnsureSettings()
    local ts = nil
    pcall(function()
        if api.Time ~= nil and api.Time.GetLocalTime ~= nil then
            ts = api.Time:GetLocalTime()
        end
    end)
    if ts == nil then
        ts = tostring(math.random(1000000000, 9999999999))
    end
    ts = tostring(ts)

    local backupPath = string.format("%s/settings_%s.txt", Shared.CONSTANTS.SETTINGS_BACKUP_DIR, ts)
    local ok, err = writeTableFile(backupPath, settings)
    if not ok then
        backupPath = string.format("gharka-bars/.data/settings_backup_%s.txt", ts)
        ok, err = writeTableFile(backupPath, settings)
        if not ok then
            return false, err
        end
    end

    local idx = readTableFile(Shared.CONSTANTS.SETTINGS_BACKUP_INDEX_FILE_PATH)
    if type(idx) ~= "table" then
        idx = readTableFile(Shared.CONSTANTS.SETTINGS_BACKUP_INDEX_FALLBACK_FILE_PATH)
    end
    if type(idx) ~= "table" then
        idx = readTableFile(Shared.CONSTANTS.LEGACY_SETTINGS_BACKUP_INDEX_FILE_PATH)
    end
    if type(idx) ~= "table" then
        idx = readTableFile(Shared.CONSTANTS.LEGACY_SETTINGS_BACKUP_INDEX_FALLBACK_FILE_PATH)
    end
    if type(idx) ~= "table" then
        idx = { version = 1, backups = {} }
    end
    if type(idx.backups) ~= "table" then
        idx.backups = {}
    end
    table.insert(idx.backups, 1, { path = backupPath, timestamp = ts })
    while #idx.backups > 30 do
        table.remove(idx.backups)
    end
    writeTableFile(Shared.CONSTANTS.SETTINGS_BACKUP_INDEX_FILE_PATH, idx)
    pcall(function()
        if readTableFile(Shared.CONSTANTS.SETTINGS_BACKUP_INDEX_FILE_PATH) == nil then
            writeTableFile(Shared.CONSTANTS.SETTINGS_BACKUP_INDEX_FALLBACK_FILE_PATH, idx)
        end
    end)
    pcall(function()
        if readTableFile(Shared.CONSTANTS.SETTINGS_BACKUP_FILE_PATH) == nil then
            writeTableFile(Shared.CONSTANTS.SETTINGS_BACKUP_FILE_PATH, settings)
        end
    end)
    return true, backupPath
end

function Shared.ImportLatestBackup()
    local idx = readTableFile(Shared.CONSTANTS.SETTINGS_BACKUP_INDEX_FILE_PATH)
    if type(idx) ~= "table" then
        idx = readTableFile(Shared.CONSTANTS.SETTINGS_BACKUP_INDEX_FALLBACK_FILE_PATH)
    end
    if type(idx) ~= "table" then
        idx = readTableFile(Shared.CONSTANTS.LEGACY_SETTINGS_BACKUP_INDEX_FILE_PATH)
    end
    if type(idx) ~= "table" then
        idx = readTableFile(Shared.CONSTANTS.LEGACY_SETTINGS_BACKUP_INDEX_FALLBACK_FILE_PATH)
    end
    local backupPath = nil
    if type(idx) == "table" and type(idx.backups) == "table" and type(idx.backups[1]) == "table" then
        backupPath = idx.backups[1].path
    end
    if type(backupPath) ~= "string" or backupPath == "" then
        backupPath = Shared.CONSTANTS.SETTINGS_BACKUP_FILE_PATH
    end
    local parsed = readTableFile(backupPath)
    if type(parsed) ~= "table" then
        parsed = readTableFile(Shared.CONSTANTS.LEGACY_SETTINGS_BACKUP_FILE_PATH)
    end
    if type(parsed) ~= "table" then
        return false, "no backup found"
    end
    Shared.state.settings = {}
    mergeInto(Shared.state.settings, parsed)
    Shared.EnsureSettings()
    return Shared.SaveSettings()
end

return Shared
