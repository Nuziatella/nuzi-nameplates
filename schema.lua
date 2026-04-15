local Schema = {}

Schema.GLOBAL_TOGGLES = {
    { key = "enabled", label = "Addon on" },
    { key = "anchor_to_nametag", label = "Name tag anchor" },
    { key = "click_target", label = "Click to target" },
    { key = "show_player", label = "Self" },
    { key = "show_target", label = "Target" },
    { key = "show_watchtarget", label = "Watch target" },
    { key = "show_raid_party", label = "Raid / party" },
    { key = "show_mount", label = "Mount / pet" }
}

Schema.GLOBAL_CHOICES = {
    {
        key = "frame_layer_mode",
        label = "Draw layer",
        use_option_buttons = true,
        options = {
            { value = "default", label = "Default", description = "Uses the game's default window layer for the bars." },
            { value = "normal", label = "Normal", description = "Standard addon/UI window layer." },
            { value = "hud", label = "HUD", description = "Usually above normal windows; good for persistent overlays." },
            { value = "tooltip", label = "Tooltip", description = "Usually above dialogs and standard UI, like tooltip-style overlays." },
            { value = "dialog", label = "Dialog", description = "Popup/dialog style layer above most regular windows." },
            { value = "system", label = "System", description = "Top-most system layer. Use sparingly if the bars must stay visible." },
            { value = "questdirecting", label = "Quest Directing", description = "Quest-guidance style layer near navigation overlays." },
            { value = "game", label = "Game", description = "Closer to gameplay/world overlays and often below standard UI." },
            { value = "background", label = "Background", description = "Behind most addon and UI windows." }
        },
        help_lines = {
            "Default: Uses the client default for addon windows.",
            "Background: Behind most addon and UI windows.",
            "Game: Near gameplay/world overlays, often below regular UI.",
            "Normal: Standard addon/UI window level.",
            "HUD: Above normal UI for persistent overlay elements.",
            "Quest Directing: Near quest guidance and navigation overlays.",
            "Dialog: Popup/dialog level above regular windows.",
            "Tooltip: Very high layer, similar to tooltip overlays.",
            "System: Top-most system layer. Use only when needed."
        }
    }
}

Schema.STYLE_TOGGLES = {
    { key = "show_name", label = "Name" },
    { key = "show_guild", label = "Guild" },
    { key = "show_role", label = "Role" },
    { key = "show_hp_text", label = "HP text" },
    { key = "show_mp_text", label = "MP text" },
    { key = "show_mp_bar", label = "MP bar" },
    { key = "show_distance", label = "Distance" },
    { key = "show_background", label = "Backdrop" }
}

Schema.LAYOUT_SLIDERS = {
    { key = "width", label = "Width", min = 80, max = 320, factor = 1 },
    { key = "hp_height", label = "HP height", min = 8, max = 56, factor = 1 },
    { key = "mp_height", label = "MP height", min = 0, max = 26, factor = 1 },
    { key = "bar_gap", label = "Gap", min = 0, max = 10, factor = 1 },
    { key = "alpha_pct", label = "Alpha", min = 10, max = 100, factor = 1 },
    { key = "bg_alpha_pct", label = "BG alpha", min = 0, max = 100, factor = 1 },
    { key = "max_distance", label = "Range", min = 10, max = 300, factor = 1 },
    { key = "x_offset", label = "Offset X", min = -500, max = 500, factor = 1 },
    { key = "y_offset", label = "Offset Y", min = -200, max = 200, factor = 1 }
}

Schema.TEXT_SLIDERS = {
    { key = "name_font_size", label = "Name size", min = 8, max = 30, factor = 1 },
    { key = "name_max_chars", label = "Name chars", min = 0, max = 64, factor = 1 },
    { key = "guild_font_size", label = "Guild size", min = 8, max = 24, factor = 1 },
    { key = "guild_max_chars", label = "Guild chars", min = 0, max = 64, factor = 1 },
    { key = "role_font_size", label = "Role size", min = 8, max = 24, factor = 1 },
    { key = "value_font_size", label = "Value size", min = 8, max = 24, factor = 1 },
    { key = "value_offset_x", label = "Value X", min = -80, max = 80, factor = 1 },
    { key = "value_offset_y", label = "Value Y", min = -40, max = 40, factor = 1 },
    { key = "distance_font_size", label = "Range size", min = 8, max = 22, factor = 1 },
    { key = "name_offset_x", label = "Name X", min = -80, max = 80, factor = 1 },
    { key = "name_offset_y", label = "Name Y", min = -80, max = 80, factor = 1 },
    { key = "guild_offset_x", label = "Guild X", min = -80, max = 80, factor = 1 },
    { key = "guild_offset_y", label = "Guild Y", min = -80, max = 80, factor = 1 },
    { key = "role_offset_x", label = "Role X", min = -80, max = 80, factor = 1 },
    { key = "role_offset_y", label = "Role Y", min = -80, max = 80, factor = 1 },
    { key = "distance_offset_x", label = "Range X", min = -120, max = 120, factor = 1 },
    { key = "distance_offset_y", label = "Range Y", min = -120, max = 120, factor = 1 }
}

Schema.CC_TOGGLES = {
    { key = "show_cc", label = "CC icons" },
    { key = "show_cc_timer", label = "CC timer" },
    { key = "show_cc_secondary", label = "Secondary CC" },
    { key = "show_cc_hard", label = "Hard CC" },
    { key = "show_cc_silence", label = "Silence / disarm" },
    { key = "show_cc_root", label = "Root / snare" },
    { key = "show_cc_slow", label = "Show slows" },
    { key = "show_cc_dot", label = "DoTs" },
    { key = "show_cc_misc", label = "Misc CC" }
}

Schema.CC_CHOICES = {
    {
        key = "cc_anchor",
        label = "Anchor",
        options = {
            { value = "left", label = "Left" },
            { value = "right", label = "Right" },
            { value = "top", label = "Top" }
        }
    },
    {
        key = "cc_max_icons",
        label = "Max icons",
        options = {
            { value = 1, label = "1" },
            { value = 2, label = "2" },
            { value = 3, label = "3" },
            { value = 4, label = "4" }
        }
    }
}

Schema.CC_SLIDERS = {
    { key = "cc_icon_size", label = "Main size", min = 16, max = 48, factor = 1 },
    { key = "cc_secondary_icon_size", label = "Small size", min = 10, max = 32, factor = 1 },
    { key = "cc_timer_font_size", label = "Timer size", min = 8, max = 24, factor = 1 },
    { key = "cc_gap", label = "Gap", min = 0, max = 12, factor = 1 },
    { key = "cc_offset_x", label = "Offset X", min = -80, max = 80, factor = 1 },
    { key = "cc_offset_y", label = "Offset Y", min = -80, max = 80, factor = 1 }
}

Schema.COLOR_GROUPS = {
    { key = "hp_bar_color", label = "HP bar" },
    { key = "hostile_bar_color", label = "Hostile HP" },
    { key = "neutral_bar_color", label = "Neutral HP" },
    { key = "mp_bar_color", label = "MP bar" },
    { key = "bloodlust_team_color", label = "Bloodlust team" },
    { key = "bloodlust_target_color", label = "Bloodlust target" },
    { key = "name_color", label = "Name text" },
    { key = "guild_color", label = "Guild text" },
    { key = "value_color", label = "HP/MP text" },
    { key = "distance_color", label = "Distance text" }
}

Schema.STYLE_CHOICES = {
    {
        key = "value_mode",
        label = "Value mode",
        options = {
            { value = "current", label = "Current" },
            { value = "current_max", label = "Current / Max" },
            { value = "percent", label = "Percent" },
            { value = "both", label = "Both" }
        }
    },
    {
        key = "name_layout",
        label = "Name layout",
        options = {
            { value = "vertical", label = "Vertical" },
            { value = "horizontal", label = "Horizontal" }
        }
    },
    {
        key = "cluster_spacing_mode",
        label = "Cluster mode (exp)",
        options = {
            { value = "off", label = "Off" },
            { value = "split", label = "Split" },
            { value = "light", label = "Light" },
            { value = "medium", label = "Medium" },
            { value = "strong", label = "Strong" }
        }
    }
}

Schema.STYLE_PRESETS = {
    {
        key = "raid",
        label = "Raid",
        description = "Balanced, readable raid bars with full data and full CC coverage.",
        style = {
            width = 152,
            hp_height = 40,
            mp_height = 10,
            bar_gap = 1,
            alpha_pct = 100,
            bg_alpha_pct = 96,
            max_distance = 300,
            name_font_size = 17,
            name_max_chars = 0,
            guild_font_size = 12,
            guild_max_chars = 18,
            role_font_size = 20,
            value_font_size = 14,
            distance_font_size = 18,
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
            cc_anchor = "top",
            cc_max_icons = 4,
            cc_icon_size = 42,
            cc_secondary_icon_size = 22,
            cc_gap = 4
        }
    },
    {
        key = "compact",
        label = "Compact",
        description = "Slim bars for tighter screens while keeping the important combat info.",
        style = {
            width = 116,
            hp_height = 28,
            mp_height = 6,
            bar_gap = 0,
            alpha_pct = 96,
            bg_alpha_pct = 84,
            name_font_size = 14,
            name_max_chars = 8,
            guild_font_size = 10,
            guild_max_chars = 10,
            role_font_size = 16,
            value_font_size = 12,
            distance_font_size = 15,
            show_name = true,
            show_guild = false,
            show_role = true,
            show_hp_text = true,
            show_mp_text = false,
            show_mp_bar = true,
            show_distance = true,
            show_background = true,
            show_cc = true,
            show_cc_timer = true,
            show_cc_secondary = false,
            cc_anchor = "top",
            cc_max_icons = 2,
            cc_icon_size = 30,
            cc_secondary_icon_size = 16,
            cc_gap = 2
        }
    },
    {
        key = "large",
        label = "Large",
        description = "Bigger bars and fonts for easier reading from a distance.",
        style = {
            width = 176,
            hp_height = 46,
            mp_height = 12,
            bar_gap = 2,
            alpha_pct = 100,
            bg_alpha_pct = 100,
            name_font_size = 18,
            name_max_chars = 0,
            guild_font_size = 13,
            guild_max_chars = 20,
            role_font_size = 22,
            value_font_size = 16,
            distance_font_size = 20,
            show_name = true,
            show_guild = true,
            show_role = true,
            show_hp_text = true,
            show_mp_text = true,
            show_mp_bar = true,
            show_distance = true,
            show_background = true,
            show_cc = true,
            show_cc_timer = true,
            show_cc_secondary = true,
            cc_anchor = "top",
            cc_max_icons = 4,
            cc_icon_size = 46,
            cc_secondary_icon_size = 26,
            cc_gap = 4
        }
    },
    {
        key = "minimal",
        label = "Minimal",
        description = "Low-noise bars that keep only the essentials visible.",
        style = {
            width = 108,
            hp_height = 24,
            mp_height = 0,
            bar_gap = 0,
            alpha_pct = 92,
            bg_alpha_pct = 68,
            name_font_size = 14,
            name_max_chars = 7,
            guild_font_size = 10,
            guild_max_chars = 0,
            role_font_size = 14,
            value_font_size = 11,
            distance_font_size = 13,
            show_name = true,
            show_guild = false,
            show_role = false,
            show_hp_text = true,
            show_mp_text = false,
            show_mp_bar = false,
            show_distance = false,
            show_background = true,
            show_cc = true,
            show_cc_timer = false,
            show_cc_secondary = false,
            cc_anchor = "top",
            cc_max_icons = 2,
            cc_icon_size = 26,
            cc_secondary_icon_size = 14,
            cc_gap = 2
        }
    }
}

return Schema
