local api = require("api")
local Core = api._NuziCore or require("nuzi-core/core")

local Runtime = Core.Runtime
local Settings = Core.Settings

local Shared = {}

Shared.CONSTANTS = {
    ADDON_ID = "gharka-bars",
    TITLE = "Gharka Bars",
    VERSION = "1.5.44",
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
        cc_tracking_scope = "focus",
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

local ICON_DEFAULTS = {
    version = 1,
    button_x = Shared.DEFAULT_SETTINGS.button_x,
    button_y = Shared.DEFAULT_SETTINGS.button_y
}

Shared.Clamp = Runtime.Clamp

local function assignChanged(target, key, value)
    if target[key] == value then
        return false
    end
    target[key] = value
    return true
end

local function normalizeMainSettings(settings)
    if type(settings) ~= "table" then
        return false
    end

    local changed = false
    if type(settings.style) ~= "table" then
        settings.style = Runtime.DeepCopy(Shared.DEFAULT_SETTINGS.style)
        changed = true
    end

    if settings.full_name_migration_v1 ~= true then
        if type(settings.style) ~= "table" then
            settings.style = Runtime.DeepCopy(Shared.DEFAULT_SETTINGS.style)
        end
        settings.style.name_max_chars = 0
        settings.style.guild_max_chars = 0
        settings.full_name_migration_v1 = true
        changed = true
    end

    local buttonX = Shared.Clamp(settings.button_x, 0, 4000, Shared.DEFAULT_SETTINGS.button_x)
    local buttonY = Shared.Clamp(settings.button_y, 0, 4000, Shared.DEFAULT_SETTINGS.button_y)
    local windowX = Shared.Clamp(settings.window_x, 0, 4000, Shared.DEFAULT_SETTINGS.window_x)
    local windowY = Shared.Clamp(settings.window_y, 0, 4000, Shared.DEFAULT_SETTINGS.window_y)

    if assignChanged(settings, "button_x", buttonX) then
        changed = true
    end
    if assignChanged(settings, "button_y", buttonY) then
        changed = true
    end
    if assignChanged(settings, "window_x", windowX) then
        changed = true
    end
    if assignChanged(settings, "window_y", windowY) then
        changed = true
    end

    return changed
end

local store = Settings.CreateAddonStore(Shared.CONSTANTS, {
    read_mode = "serialized_then_flat",
    write_mode = "serialized_then_flat",
    read_raw_text_fallback = true,
    write_mirror_paths = {
        Shared.CONSTANTS.LEGACY_SETTINGS_FILE_PATH
    },
    backups = {
        read_mode = "serialized_then_flat",
        write_mode = "serialized_then_flat",
        read_raw_text_fallback = true,
        backup_dir = Shared.CONSTANTS.SETTINGS_BACKUP_DIR,
        backup_prefix = "settings",
        index_file_path = Shared.CONSTANTS.SETTINGS_BACKUP_INDEX_FILE_PATH,
        index_fallback_file_path = Shared.CONSTANTS.SETTINGS_BACKUP_INDEX_FALLBACK_FILE_PATH,
        legacy_index_paths = {
            Shared.CONSTANTS.LEGACY_SETTINGS_BACKUP_INDEX_FILE_PATH,
            Shared.CONSTANTS.LEGACY_SETTINGS_BACKUP_INDEX_FALLBACK_FILE_PATH
        },
        latest_backup_file_path = Shared.CONSTANTS.SETTINGS_BACKUP_FILE_PATH,
        legacy_latest_paths = {
            Shared.CONSTANTS.LEGACY_SETTINGS_BACKUP_FILE_PATH
        },
        max_backups = 30
    },
    profiles = {
        read_mode = "serialized_then_flat",
        write_mode = "serialized_then_flat",
        read_raw_text_fallback = true,
        profile_dir = "gharka-bars/.data",
        state_file_path = Shared.CONSTANTS.PROFILE_STATE_FILE_PATH,
        state_mode = "serialized_then_flat",
        state_write_mode = "serialized_then_flat",
        state_raw_text_fallback = true
    },
    log_name = Shared.CONSTANTS.TITLE,
    normalize = function(settings)
        return normalizeMainSettings(settings)
    end
})

local iconStore = Settings.CreateSidecarStore({
    settings_file_path = Shared.CONSTANTS.ICON_SETTINGS_FILE_PATH,
    defaults = Runtime.DeepCopy(ICON_DEFAULTS),
    read_mode = "serialized_then_flat",
    write_mode = "serialized_then_flat",
    read_raw_text_fallback = true,
    save_global_settings = false,
    use_api_settings = false,
    log_name = Shared.CONSTANTS.TITLE .. " Icon",
    normalize = function(value)
        if type(value) ~= "table" then
            return false
        end

        local changed = false
        local version = tonumber(value.version) or ICON_DEFAULTS.version
        local buttonX = Shared.Clamp(value.button_x, 0, 4000, ICON_DEFAULTS.button_x)
        local buttonY = Shared.Clamp(value.button_y, 0, 4000, ICON_DEFAULTS.button_y)

        if assignChanged(value, "version", version) then
            changed = true
        end
        if assignChanged(value, "button_x", buttonX) then
            changed = true
        end
        if assignChanged(value, "button_y", buttonY) then
            changed = true
        end

        return changed
    end
})

Shared.store = store
Shared.icon_store = iconStore

local function profileManager()
    return store.profile_manager
end

local function ensureProfileState()
    local manager = profileManager()
    local state = manager ~= nil and manager:EnsureState() or {}
    state.version = tonumber(state.version) or 1
    state.window_x = Shared.Clamp(state.window_x, 0, 4000, Shared.DEFAULT_SETTINGS.window_x)
    state.window_y = Shared.Clamp(state.window_y, 0, 4000, Shared.DEFAULT_SETTINGS.window_y)
    Shared.state.profile_state = state
    return state
end

local function saveProfileState()
    local manager = profileManager()
    if manager == nil then
        return false
    end
    local state = ensureProfileState()
    manager.state = state
    local ok = manager:SaveState()
    Shared.state.profile_state = state
    return ok and true or false
end

local function ensureIconSettings()
    local settings = iconStore:Ensure()
    settings.version = tonumber(settings.version) or ICON_DEFAULTS.version
    settings.button_x = Shared.Clamp(settings.button_x, 0, 4000, ICON_DEFAULTS.button_x)
    settings.button_y = Shared.Clamp(settings.button_y, 0, 4000, ICON_DEFAULTS.button_y)
    Shared.state.icon_settings = settings
    return settings
end

local function saveIconSettings()
    local settings = ensureIconSettings()
    local ok = iconStore:Save()
    Shared.state.icon_settings = settings
    return ok and true or false
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

function Shared.GetStore()
    return store
end

function Shared.LoadSettings()
    local settings = store:Load()
    Shared.state.settings = settings

    local iconSettings, iconMeta = iconStore:Load()
    Shared.state.icon_settings = iconSettings

    local state = ensureProfileState()
    local bootstrapIcon = false
    if type(iconMeta) == "table" and not iconMeta.has_primary then
        local buttonX = Shared.Clamp(state.button_x ~= nil and state.button_x or settings.button_x, 0, 4000, Shared.DEFAULT_SETTINGS.button_x)
        local buttonY = Shared.Clamp(state.button_y ~= nil and state.button_y or settings.button_y, 0, 4000, Shared.DEFAULT_SETTINGS.button_y)
        if assignChanged(iconSettings, "button_x", buttonX) then
            bootstrapIcon = true
        end
        if assignChanged(iconSettings, "button_y", buttonY) then
            bootstrapIcon = true
        end
    end
    if bootstrapIcon then
        saveIconSettings()
    end

    applyPersistentUiState(settings)
    saveProfileState()

    Shared.state.settings = settings
    Shared.state.profile_state = state
    Shared.state.icon_settings = iconSettings
    return settings
end

function Shared.EnsureSettings()
    local settings = store:Ensure()
    Runtime.ApplyDefaults(settings, Shared.DEFAULT_SETTINGS)
    normalizeMainSettings(settings)
    applyPersistentUiState(settings)
    Shared.state.settings = settings
    return settings
end

function Shared.GetStyleSettings()
    local settings = Shared.EnsureSettings()
    if type(settings.style) ~= "table" then
        settings.style = Runtime.DeepCopy(Shared.DEFAULT_SETTINGS.style)
    end
    return settings.style
end

function Shared.ResetStyleSettings()
    Shared.EnsureSettings().style = Runtime.DeepCopy(Shared.DEFAULT_SETTINGS.style)
end

function Shared.ResetAllSettings()
    Shared.state.settings = store:Reset()
    applyPersistentUiState(Shared.state.settings)
end

function Shared.SaveSettings()
    local settings = Shared.EnsureSettings()
    applyPersistentUiState(settings)
    Shared.state.settings = settings
    local ok, meta = store:Save()
    saveProfileState()
    return ok, meta
end

function Shared.GetActiveProfilePath()
    return store:GetActiveProfilePath()
end

function Shared.GetActiveProfileFileName()
    return store:GetActiveProfileFileName()
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
    end

    if kind ~= "window" then
        return false
    end

    local state = ensureProfileState()
    state.window_x = Shared.Clamp(x, 0, 4000, Shared.DEFAULT_SETTINGS.window_x)
    state.window_y = Shared.Clamp(y, 0, 4000, Shared.DEFAULT_SETTINGS.window_y)
    Shared.state.profile_state = state
    applyPersistentUiState(Shared.state.settings)
    saveProfileState()
    return true
end

function Shared.ListProfiles()
    return store:ListProfiles()
end

function Shared.SaveSettingsAsProfile(name)
    local ok, result = store:SaveAsProfile(name)
    if ok then
        Shared.state.settings = store:Ensure()
        applyPersistentUiState(Shared.state.settings)
        saveProfileState()
    end
    return ok, result
end

function Shared.LoadProfile(path)
    local ok, result = store:LoadProfile(path)
    if ok then
        Shared.state.settings = store:Ensure()
        applyPersistentUiState(Shared.state.settings)
        saveProfileState()
    end
    return ok, result
end

function Shared.SaveSettingsBackup()
    return store:SaveBackup()
end

function Shared.ImportLatestBackup()
    local ok, result = store:ImportLatestBackup()
    if ok then
        Shared.state.settings = store:Ensure()
        applyPersistentUiState(Shared.state.settings)
        saveProfileState()
    end
    return ok, result
end

return Shared
