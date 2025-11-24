-- /server/scripts/cosmetic-config/config.lua
-- Central cosmetics config: menu/window knobs + per-cosmetic blocks

local cfg = {
  -- Cosmetics menu background (cmenu.png + cmenu.animation)
  menu_texture   = "/server/assets/ui/cosmetics/cmenu.png",
  menu_animation = "/server/assets/ui/cosmetics/cmenu.animation",

  -- Preview window background (separate file to avoid texture reuse issues)
  window_texture   = "/server/assets/ui/cosmetics/cpreview.png",
  window_animation = "/server/assets/ui/cosmetics/cpreview.animation",

  -- "Knobs" for menu background position + scale
  menu_x      = 5,     -- logical X (0..240) for cmenu background
  menu_y      = 20,    -- logical Y (0..160)
  menu_z      = 6,     -- Z-depth
  menu_scale  = 2.0,   -- scale for cmenu sprite

  -- "Knobs" for text list (independent of menu_x/menu_y)
  list_x         = 20,   -- logical X for text
  list_y         = 40,   -- logical Y for first line
  list_spacing   = 22,   -- vertical distance between list items
  list_z         = 230,  -- text Z-depth (above cmenu)
  list_font      = "THICK",
  list_scale     = 1.0,

  -- Cosmetic preview window (new sprite, separate knobs)
  window_x      = 86,   -- center-ish; tweak as needed
  window_y      = 35,
  window_z      = 7,     -- slightly above menu background
  window_scale  = 2.0,

  -- If true, cmenu always uses SELECTION_DEBUG (all cursors visible)
  use_debug_selection = false,

  -- Preview behavior (screen-space movement)
  preview_step    = 2,
  preview_start_x = 0,
  preview_start_y = -24,
  preview_base_x  = 120,
  preview_base_y  = 80,
  preview_z       = 6,
  preview_scale   = 2.0,
}

-- Per-cosmetic blocks:
-- copy-paste one of these and edit to add a new cosmetic.
local cosmetics = {
  {
    id              = "snowflake_particle",               -- internal cosmetic id
    key             = "snowflake",                        -- menu key
    name            = "Snowflake",                        -- text shown in list
    texture         = "/server/assets/cosmetics/snowflakes.png",
    animation       = "/server/assets/cosmetics/snowflakes.animation",
    anim_state      = "SNOWFLAKE_PARTICLE",
    preview_sprite_id = "preview_snowflake",
    loop_duration = 1.0,

    -- Alignment knobs (bot <-> sprite)
    xforced         = 50,
    yforced         = 0,

    -- Preview starting offsets (inside the preview window)
    preview_start_x = -25,
    preview_start_y = -40,
  },
  {
    id              = "confetti",
    key             = "confetti",
    name            = "Confetti",
    texture         = "/server/assets/cosmetics/confetti.png",
    animation       = "/server/assets/cosmetics/confetti.animation",
    anim_state      = "CONFETTI",
    preview_sprite_id = "preview_confetti",
    loop_duration = 0.5,

    xforced         = 0,
    yforced         = 0,

    preview_start_x = 0,
    preview_start_y = 30,
  },
  {
    id              = "shock",
    key             = "shock",
    name            = "Shock",
    texture         = "/server/assets/cosmetics/shock.png",
    animation       = "/server/assets/cosmetics/shock.animation",
    anim_state      = "SHOCK",
    preview_sprite_id = "preview_shock",
    loop_duration = 0.4,

    xforced         = 0,
    yforced         = 0,

    preview_start_x = 0,
    preview_start_y = -40,
  },
  {
    id              = "DarkAura",
    key             = "DarkAura",
    name            = "DarkAura",
    texture         = "/server/assets/cosmetics/DarkAura.png",
    animation       = "/server/assets/cosmetics/DarkAura.animation",
    anim_state      = "DARK_AURA",
    preview_sprite_id = "preview_darkaura",
    loop_duration = 0.3,

    xforced         = 0,
    yforced         = 0,

    preview_start_x = 0,
    preview_start_y = -40,
  },
}

return {
  cfg       = cfg,
  cosmetics = cosmetics,
}
