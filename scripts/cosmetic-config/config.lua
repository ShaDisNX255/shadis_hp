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

  -- Small "menu preview" sprite (always visible while cosmetics menu is open)
  -- Starts centered on the screen; you can tweak these later.
  menu_preview_base_x = 180,  -- center X on 240x160
  menu_preview_base_y = 35,   -- center Y
  menu_preview_z      = 8,    -- slightly above menu bg/window
  menu_preview_scale  = 1.25, -- smaller than full cosmetics (menu_scale=2.0)
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

    menu_preview_texture    = "/server/assets/cosmetics/snowflakes_preview.png",
    menu_preview_animation  = "/server/assets/cosmetics/snowflakes_preview.animation",
    menu_preview_anim_state = "SNOWFLAKE_PREVIEW",
    menu_preview_sprite_id  = "menu_preview_snowflake",
    menu_preview_offset_x   = 0,
    menu_preview_offset_y   = 0,
    menu_preview_scale          = 1.25,
    menu_preview_loop_duration  = 1.0,
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

    menu_preview_texture    = "/server/assets/cosmetics/confetti_preview.png",
    menu_preview_animation  = "/server/assets/cosmetics/confetti_preview.animation",
    menu_preview_anim_state = "CONFETTI_PREVIEW",
    menu_preview_sprite_id  = "menu_preview_confetti",
    menu_preview_offset_x   = 13,
    menu_preview_offset_y   = 60,
    menu_preview_scale          = 2,
    menu_preview_loop_duration  = 0.5,
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

    menu_preview_texture    = "/server/assets/cosmetics/shock_preview.png",
    menu_preview_animation  = "/server/assets/cosmetics/shock_preview.animation",
    menu_preview_anim_state = "SHOCK_PREVIEW",
    menu_preview_sprite_id  = "menu_preview_shock",
    menu_preview_offset_x   = 13,
    menu_preview_offset_y   = 25,
    menu_preview_scale          = 1.25,
    menu_preview_loop_duration  = 0.4,
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
    preview_start_y = 10,

    menu_preview_texture    = "/server/assets/cosmetics/DarkAura_preview.png",
    menu_preview_animation  = "/server/assets/cosmetics/DarkAura_preview.animation",
    menu_preview_anim_state = "DARKAURA_PREVIEW",
    menu_preview_sprite_id  = "menu_preview_darkaura",
    menu_preview_offset_x   = 13,
    menu_preview_offset_y   = 30,
    menu_preview_scale          = 0.5,
    menu_preview_loop_duration  = 0.3,
  },
  {
    id              = "Matrix",
    key             = "Matrix",
    name            = "Matrix",
    texture         = "/server/assets/cosmetics/matrix.png",
    animation       = "/server/assets/cosmetics/matrix.animation",
    anim_state      = "MATRIX_CODE",
    preview_sprite_id = "preview_matrix",
    loop_duration = 1.0,

    xforced         = 50,
    yforced         = 0,

    preview_start_x = -25,
    preview_start_y = -60,

    menu_preview_texture    = "/server/assets/cosmetics/matrix_preview.png",
    menu_preview_animation  = "/server/assets/cosmetics/matrix_preview.animation",
    menu_preview_anim_state = "MATRIX_PREVIEW",
    menu_preview_sprite_id  = "menu_preview_matrix",
    menu_preview_offset_x   = 3,
    menu_preview_offset_y   = 0,
    menu_preview_scale          = 0.8,
  },
  {
    id              = "BeanStar",
    key             = "BeanStar",
    name            = "BeanStar",
    texture         = "/server/assets/cosmetics/beanstar.png",
    animation       = "/server/assets/cosmetics/beanstar.animation",
    anim_state      = "BEANSTAR",
    preview_sprite_id = "preview_beanstar",
    loop_duration = 3.0,

    xforced         = 18,
    yforced         = 0,

    preview_start_x = -10,
    preview_start_y = -20,

    menu_preview_texture    = "/server/assets/cosmetics/beanstar_preview.png",  
    menu_preview_animation  = "/server/assets/cosmetics/beanstar_preview.animation",
    menu_preview_anim_state = "BEANSTAR_PREVIEW",
    menu_preview_sprite_id  = "menu_preview_beanstar",
    menu_preview_offset_x   = -5,
    menu_preview_offset_y   = 0,
    menu_preview_scale          = 2.0,
  },
  {
    id              = "PinkCyberElf",
    key             = "PinkCyberElf",
    name            = "Pink CyberElf",
    texture         = "/server/assets/cosmetics/pinkcyberelf.png",
    animation       = "/server/assets/cosmetics/pinkcyberelf.animation",
    anim_state      = "CYBERELF_PINK",
    preview_sprite_id = "preview_pinkcyberelf",
    loop_duration = 2.2,

    xforced         = 60,
    yforced         = 0,

    preview_start_x = -30,
    preview_start_y = -40,

    menu_preview_texture    = "/server/assets/cosmetics/pinkcyberelf_preview.png",  
    menu_preview_animation  = "/server/assets/cosmetics/pinkcyberelf_preview.animation",
    menu_preview_anim_state = "PINKCYBER_PREVIEW",
    menu_preview_sprite_id  = "menu_preview_pinkcyberelf",
    menu_preview_offset_x   = 0,
    menu_preview_offset_y   = 10,
    menu_preview_scale          = 1.0,
  },
  {
    id              = "GreenCyberElf",
    key             = "GreenCyberElf",
    name            = "Green CyberElf",
    texture         = "/server/assets/cosmetics/greencyberelf.png",
    animation       = "/server/assets/cosmetics/greencyberelf.animation",
    anim_state      = "CYBERELF_GREEN",
    preview_sprite_id = "preview_greencyberelf",
    loop_duration = 2.2,

    xforced         = 60,
    yforced         = 0,

    preview_start_x = -30,
    preview_start_y = -40,

    menu_preview_texture    = "/server/assets/cosmetics/greencyberelf_preview.png",  
    menu_preview_animation  = "/server/assets/cosmetics/greencyberelf_preview.animation",
    menu_preview_anim_state = "GREENCYBER_PREVIEW",
    menu_preview_sprite_id  = "menu_preview_greencyberelf",
    menu_preview_offset_x   = 0,
    menu_preview_offset_y   = 10,
    menu_preview_scale          = 1.0,
  },
  {
    id              = "BlueCyberElf",
    key             = "BlueCyberElf",
    name            = "Blue CyberElf",
    texture         = "/server/assets/cosmetics/bluecyberelf.png",
    animation       = "/server/assets/cosmetics/bluecyberelf.animation",
    anim_state      = "CYBERELF_BLUE",
    preview_sprite_id = "preview_bluecyberelf",
    loop_duration = 2.2,

    xforced         = 60,
    yforced         = 0,

    preview_start_x = -30,
    preview_start_y = -40,

    menu_preview_texture    = "/server/assets/cosmetics/bluecyberelf_preview.png",  
    menu_preview_animation  = "/server/assets/cosmetics/bluecyberelf_preview.animation",
    menu_preview_anim_state = "BLUECYBER_PREVIEW",
    menu_preview_sprite_id  = "menu_preview_bluecyberelf",
    menu_preview_offset_x   = 0,
    menu_preview_offset_y   = 10,
    menu_preview_scale          = 1.0,
  },
}

return {
  cfg       = cfg,
  cosmetics = cosmetics,
}
