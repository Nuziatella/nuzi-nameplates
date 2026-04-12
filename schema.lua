local Schema = {}

Schema.GLOBAL_TOGGLES = {
    { key = "enabled", label = "Addon enabled" },
    { key = "anchor_to_nametag", label = "Anchor to name tag" },
    { key = "click_target", label = "Click bars to target" },
    { key = "show_player", label = "Show player" },
    { key = "show_target", label = "Show target" },
    { key = "show_watchtarget", label = "Show watchtarget" },
    { key = "show_raid_party", label = "Show raid / party" },
    { key = "show_mount", label = "Show mount / pet" }
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
    { key = "show_name", label = "Show name" },
    { key = "show_guild", label = "Show guild" },
    { key = "show_role", label = "Show role" },
    { key = "show_hp_text", label = "Show HP text" },
    { key = "show_mp_text", label = "Show MP text" },
    { key = "show_mp_bar", label = "Show MP bar" },
    { key = "show_distance", label = "Show distance" },
    { key = "show_background", label = "Show background" }
}

Schema.LAYOUT_SLIDERS = {
    { key = "width", label = "Bar width", min = 80, max = 320, factor = 1 },
    { key = "hp_height", label = "HP bar height", min = 8, max = 56, factor = 1 },
    { key = "mp_height", label = "MP bar height", min = 0, max = 26, factor = 1 },
    { key = "bar_gap", label = "Bar gap", min = 0, max = 10, factor = 1 },
    { key = "alpha_pct", label = "Frame alpha", min = 10, max = 100, factor = 1 },
    { key = "bg_alpha_pct", label = "BG alpha", min = 0, max = 100, factor = 1 },
    { key = "max_distance", label = "Max distance", min = 10, max = 300, factor = 1 },
    { key = "x_offset", label = "Frame offset X", min = -500, max = 500, factor = 1 },
    { key = "y_offset", label = "Frame offset Y", min = -200, max = 200, factor = 1 }
}

Schema.TEXT_SLIDERS = {
    { key = "name_font_size", label = "Name font", min = 8, max = 30, factor = 1 },
    { key = "name_max_chars", label = "Name max chars (0=full)", min = 0, max = 64, factor = 1 },
    { key = "guild_font_size", label = "Guild font", min = 8, max = 24, factor = 1 },
    { key = "guild_max_chars", label = "Guild max chars (0=full)", min = 0, max = 64, factor = 1 },
    { key = "role_font_size", label = "Role font", min = 8, max = 24, factor = 1 },
    { key = "value_font_size", label = "Value font", min = 8, max = 24, factor = 1 },
    { key = "value_offset_x", label = "HP/MP text offset X", min = -80, max = 80, factor = 1 },
    { key = "value_offset_y", label = "HP/MP text offset Y", min = -40, max = 40, factor = 1 },
    { key = "distance_font_size", label = "Distance font", min = 8, max = 22, factor = 1 },
    { key = "name_offset_x", label = "Name offset X", min = -80, max = 80, factor = 1 },
    { key = "name_offset_y", label = "Name offset Y", min = -80, max = 80, factor = 1 },
    { key = "guild_offset_x", label = "Guild offset X", min = -80, max = 80, factor = 1 },
    { key = "guild_offset_y", label = "Guild offset Y", min = -80, max = 80, factor = 1 },
    { key = "role_offset_x", label = "Role offset X", min = -80, max = 80, factor = 1 },
    { key = "role_offset_y", label = "Role offset Y", min = -80, max = 80, factor = 1 },
    { key = "distance_offset_x", label = "Distance offset X", min = -120, max = 120, factor = 1 },
    { key = "distance_offset_y", label = "Distance offset Y", min = -120, max = 120, factor = 1 }
}

Schema.CC_TOGGLES = {
    { key = "show_cc", label = "Show crowd control icons" },
    { key = "show_cc_timer", label = "Show CC timer" },
    { key = "show_cc_secondary", label = "Show secondary CC icons" },
    { key = "show_cc_hard", label = "Show hard CC" },
    { key = "show_cc_silence", label = "Show silence / disarm" },
    { key = "show_cc_root", label = "Show root / snare" },
    { key = "show_cc_slow", label = "Show slows" },
    { key = "show_cc_dot", label = "Show DoTs" },
    { key = "show_cc_misc", label = "Show misc CC" }
}

Schema.CC_CHOICES = {
    {
        key = "cc_anchor",
        label = "CC anchor",
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
    { key = "cc_icon_size", label = "Primary icon size", min = 16, max = 48, factor = 1 },
    { key = "cc_secondary_icon_size", label = "Secondary icon size", min = 10, max = 32, factor = 1 },
    { key = "cc_timer_font_size", label = "Timer font size", min = 8, max = 24, factor = 1 },
    { key = "cc_gap", label = "Icon gap", min = 0, max = 12, factor = 1 },
    { key = "cc_offset_x", label = "CC offset X", min = -80, max = 80, factor = 1 },
    { key = "cc_offset_y", label = "CC offset Y", min = -80, max = 80, factor = 1 }
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
        label = "HP/MP text mode",
        options = {
            { value = "current", label = "Current" },
            { value = "current_max", label = "Current / Max" },
            { value = "percent", label = "Percent" },
            { value = "both", label = "Both" }
        }
    },
    {
        key = "name_layout",
        label = "Name/Guild layout",
        options = {
            { value = "vertical", label = "Vertical" },
            { value = "horizontal", label = "Horizontal" }
        }
    }
}

return Schema
