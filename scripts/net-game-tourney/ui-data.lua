local UI_DATA = {
    frame_names = {
        "MUG_FRAME_" .. 1,
        "MUG_FRAME_" .. 2,
        "MUG_FRAME_" .. 3,
        "MUG_FRAME_" .. 4,
        "MUG_FRAME_" .. 5,
        "MUG_FRAME_" .. 6,
        "MUG_FRAME_" .. 7,
        "MUG_FRAME_" .. 8,
        "MUG_" .. 1,
        "MUG_" .. 2,
        "MUG_" .. 3,
        "MUG_" .. 4,
        "MUG_" .. 5,
        "MUG_" .. 6,
        "MUG_" .. 7,
        "MUG_" .. 8,
        "BOARD BG",
        "BRACKET",
        "BOARD GRID",
        "CHAMPION TOPPER",
        "TITLE BANNER",
        "CROWN_1",
        "CROWN_2",
        "CHAMPION_INDICATOR",
    },

    unmoving_ui_pos = {
        bg = {
            x = 0,
            y = 0,
            z = -2,
        },
        grid = {
            x = 0,
            y = 0,
            z = -1,
        },
        title_banner = {
            x = 0,
            y = 0,
            z = 0,
        },
        title_text = {
            center_x = 120,
            y = 6,
            z = 5,
        },
        bracket = {
            x = 0,
            y = 0,
            z = 0,
        },
        crown1 = {
            x = 64,
            y = 48,
            z = 0,
        },
        crown2 = {
            x = 176,
            y = 48,
            z = 0,
        },
        champion_crown = {
            x = 120,
            y = 36,
            z = 4,
        },
        champion_topper_bn4 = {
            x = 80,
            y = 40,
            z = 1,
        },
    },

    -- Winner path locations: 8 first-round paths, 4 semifinal paths, 2 final paths.
    progress_bars = {
        bottom_tier = {
            { x = 17,  y = 96, z = 1 },
            { x = 47,  y = 96, z = 1 },
            { x = 73,  y = 96, z = 1 },
            { x = 103, y = 96, z = 1 },
            { x = 137, y = 96, z = 1 },
            { x = 167, y = 96, z = 1 },
            { x = 193, y = 96, z = 1 },
            { x = 223, y = 96, z = 1 },
        },
        middle_tier = {
            { x = 29,  y = 72, z = 1 },
            { x = 91,  y = 72, z = 1 },
            { x = 149, y = 72, z = 1 },
            { x = 211, y = 72, z = 1 },
        },
        top_tier = {
            { x = 57,  y = 56, z = 1 },
            { x = 183, y = 56, z = 1 },
        },
    },

    -- Same locations one Z-layer above the permanent path, for the animated glow.
    progress_bar_overlays = {
        bottom_tier = {
            { x = 17,  y = 96, z = 2 },
            { x = 47,  y = 96, z = 2 },
            { x = 73,  y = 96, z = 2 },
            { x = 103, y = 96, z = 2 },
            { x = 137, y = 96, z = 2 },
            { x = 167, y = 96, z = 2 },
            { x = 193, y = 96, z = 2 },
            { x = 223, y = 96, z = 2 },
        },
        middle_tier = {
            { x = 29,  y = 72, z = 2 },
            { x = 91,  y = 72, z = 2 },
            { x = 149, y = 72, z = 2 },
            { x = 211, y = 72, z = 2 },
        },
        top_tier = {
            { x = 57,  y = 56, z = 2 },
            { x = 183, y = 56, z = 2 },
        },
    },
}

return UI_DATA
