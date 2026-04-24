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

  -- Cosmetic SHOP preview (separate from the normal cosmetics menu preview)
  shop_preview_base_x = 172,  -- lower = further left
  shop_preview_base_y = 35,
  shop_preview_z      = 140,

  -- Rarity stars (crarity.png + crarity.animation)
  -- These are global knobs; one rarity sprite, updated when you move the cursor.
  rarity_texture        = "/server/assets/ui/cosmetics/crarity.png",
  rarity_animation      = "/server/assets/ui/cosmetics/crarity.animation",
  rarity_x              = 164,
  rarity_y              = 84,
  rarity_z              = 9,
  rarity_scale          = 2.5,
  rarity_default_state  = "GOLD_5",
  -- === Background behind stars (raritybg) ===
  -- Used for the cosmeticshop preview (and anywhere else you want).
  rarity_bg_texture     = "/server/assets/ui/cosmetics/raritybg.png",
  rarity_bg_animation   = "/server/assets/ui/cosmetics/raritybg.animation",
  rarity_bg_state       = "RARITYBG",

  -- These are your "knobs" for the background.
  -- If left nil, it will follow the star position.
  rarity_bg_x           = 151,  -- nil = same as rarity_x
  rarity_bg_y           = 73,  -- nil = same as rarity_y
  rarity_bg_z           = nil,  -- nil = just under rarity_z
  rarity_bg_scale       = 2.0,
  ---------------------------------------------------------------------------
  -- Sort hint icon (csort) - shows when you're on the cosmetics list
  ---------------------------------------------------------------------------
  sort_hint_texture        = "/server/assets/ui/cosmetics/csort.png",
  sort_hint_animation      = "/server/assets/ui/cosmetics/csort.animation",

  -- Where to draw the hint (tweak these to taste)
  sort_hint_x              = 46,
  sort_hint_y              = 140,
  sort_hint_z              = 10,
  sort_hint_scale          = 2.5,

  -- Which animation state to use in each mode
  -- "abc"  = "press to sort by name"
  -- "star" = "press to sort by rarity"
  sort_hint_state_alpha    = "abc",
  sort_hint_state_rarity   = "star",
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
    rarity          = "GOLD_5",
    loop_duration = 1.12,

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
    id                = "confetti",
    key               = "confetti",
    name              = "Confetti",
    texture           = "/server/assets/cosmetics/confetti.png",
    animation         = "/server/assets/cosmetics/confetti.animation",
    anim_state        = "CONFETTI",
    preview_sprite_id = "preview_confetti",
    rarity          = "GOLD_4",
    loop_duration     = 0.468,

    xforced           = 0,
    yforced           = 0,

    preview_start_x   = 0,
    preview_start_y   = 30,

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
    rarity          = "GREEN_2",
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
    menu_preview_loop_duration  = 0.468,
  },
  {
    id              = "DarkAura",
    key             = "DarkAura",
    name            = "DarkAura",
    texture         = "/server/assets/cosmetics/DarkAura.png",
    animation       = "/server/assets/cosmetics/DarkAura.animation",
    anim_state      = "DARK_AURA",
    preview_sprite_id = "preview_darkaura",
    rarity          = "GREEN_3",
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
    rarity          = "GOLD_5",
    loop_duration = 0.88,

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
    menu_preview_scale      = 0.8,
  },
  {
    id              = "BeanStar",
    key             = "BeanStar",
    name            = "BeanStar",
    texture         = "/server/assets/cosmetics/beanstar.png",
    animation       = "/server/assets/cosmetics/beanstar.animation",
    anim_state      = "BEANSTAR",
    preview_sprite_id = "preview_beanstar",
    rarity          = "GREEN_4",
    loop_duration = 3.2,

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
    menu_preview_scale      = 2.0,
  },
  {
    id              = "PinkCyberElf",
    key             = "PinkCyberElf",
    name            = "Pink_CyberElf",
    texture         = "/server/assets/cosmetics/pinkcyberelf.png",
    animation       = "/server/assets/cosmetics/pinkcyberelf.animation",
    anim_state      = "CYBERELF_PINK",
    preview_sprite_id = "preview_pinkcyberelf",
    rarity          = "GOLD_5",
    loop_duration = 2.24,

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
    menu_preview_scale      = 1.0,
  },
  {
    id              = "GreenCyberElf",
    key             = "GreenCyberElf",
    name            = "Green_CyberElf",
    texture         = "/server/assets/cosmetics/greencyberelf.png",
    animation       = "/server/assets/cosmetics/greencyberelf.animation",
    anim_state      = "CYBERELF_GREEN",
    preview_sprite_id = "preview_greencyberelf",
    rarity          = "GOLD_5",
    loop_duration = 2.24,

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
    menu_preview_scale      = 1.0,
  },
  {
    id              = "BlueCyberElf",
    key             = "BlueCyberElf",
    name            = "Blue_CyberElf",
    texture         = "/server/assets/cosmetics/bluecyberelf.png",
    animation       = "/server/assets/cosmetics/bluecyberelf.animation",
    anim_state      = "CYBERELF_BLUE",
    preview_sprite_id = "preview_bluecyberelf",
    rarity          = "GOLD_5",
    loop_duration = 2.24,

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
    menu_preview_scale      = 1.0,
  },
  {
    id              = "GigFreez",
    key             = "GigFreez",
    name            = "GigFreez",
    texture         = "/server/assets/cosmetics/GigFreez.png",
    animation       = "/server/assets/cosmetics/GigFreez.animation",
    anim_state      = "GIG_FREEZ",
    preview_sprite_id = "preview_GigFreez",
    rarity          = "GREEN_5",
    loop_duration = 1.2,

    xforced         = 32,
    yforced         = 0,

    preview_start_x = -16,
    preview_start_y = -20,

    menu_preview_texture    = "/server/assets/cosmetics/GigFreez_preview.png",  
    menu_preview_animation  = "/server/assets/cosmetics/GigFreez_preview.animation",
    menu_preview_anim_state = "GIGFREEZ_PREVIEW",
    menu_preview_sprite_id  = "menu_preview_GigFreez",
    menu_preview_offset_x   =5,
    menu_preview_offset_y   = 10,
    menu_preview_scale      = 1.0,
  },
  {
    id              = "MMBadge",
    key             = "MMBadge",
    name            = "MMBadge",
    texture         = "/server/assets/cosmetics/MMBadge.png",
    animation       = "/server/assets/cosmetics/MMBadge.animation",
    anim_state      = "MM_BADGE",
    preview_sprite_id = "preview_MMBadge",
    rarity          = "GOLD_2",
    loop_duration = 0.6,

    xforced         = 10,
    yforced         = -1,

    preview_start_x = -5,
    preview_start_y = 3,

    menu_preview_texture    = "/server/assets/cosmetics/MMBadge_preview.png",  
    menu_preview_animation  = "/server/assets/cosmetics/MMBadge_preview.animation",
    menu_preview_anim_state = "MMBADGE_PREVIEW",
    menu_preview_sprite_id  = "menu_preview_MMBadge",
    menu_preview_offset_x   =7,
    menu_preview_offset_y   = 12,
    menu_preview_scale      = 3.0,
  },
  {
    id              = "Sparkle1",
    key             = "Sparkle1",
    name            = "Sparkle1",
    texture         = "/server/assets/cosmetics/Sparkle1.png",
    animation       = "/server/assets/cosmetics/Sparkle1.animation",
    anim_state      = "Sparkle1",
    preview_sprite_id = "preview_Sparkle1",
    rarity          = "GOLD_4",
    loop_duration = 1.7,

    xforced         = 50,
    yforced         = 0,

    preview_start_x = -25,
    preview_start_y = -40,

    menu_preview_texture    = "/server/assets/cosmetics/Sparkle1_preview.png",  
    menu_preview_animation  = "/server/assets/cosmetics/Sparkle1_preview.animation",
    menu_preview_anim_state = "SPARKLE1_PREVIEW",
    menu_preview_sprite_id  = "menu_preview_Sparkle1",
    menu_preview_offset_x   = 0,
    menu_preview_offset_y   = 5,
    menu_preview_scale      = 1.0,
  },
  {
    id              = "Ready",
    key             = "Ready",
    name            = "Ready",
    texture         = "/server/assets/cosmetics/Ready.png",
    animation       = "/server/assets/cosmetics/Ready.animation",
    anim_state      = "READY",
    preview_sprite_id = "preview_Ready",
    rarity          = "GREEN_5",
    loop_duration = 7.45,
    world_scale       = 1.0,
    bot_scale       = 0.5,

    xforced         = 64,
    yforced         = 0,

    preview_start_x = -32,
    preview_start_y = 18,
    preview_scale   = 1.0,

    menu_preview_texture    = "/server/assets/cosmetics/Ready_preview.png",  
    menu_preview_animation  = "/server/assets/cosmetics/Ready_preview.animation",
    menu_preview_anim_state = "READY_PREVIEW",
    menu_preview_sprite_id  = "menu_preview_Ready",
    menu_preview_offset_x   = -20,
    menu_preview_offset_y   = 23,
    menu_preview_scale      = 1.0,
  },
  {
    id              = "ChipGreen",
    key             = "ChipGreen",
    name            = "ChipGreen",
    texture         = "/server/assets/cosmetics/ChipGreen.png",
    animation       = "/server/assets/cosmetics/ChipGreen.animation",
    anim_state      = "ChipGreen",
    preview_sprite_id = "preview_ChipGreen",
    rarity          = "GOLD_3",
    loop_duration = 1.2,

    xforced         = 16,
    yforced         = 0,

    preview_start_x = -8,
    preview_start_y = -70,

    menu_preview_texture    = "/server/assets/cosmetics/ChipGreen_preview.png",  
    menu_preview_animation  = "/server/assets/cosmetics/ChipGreen_preview.animation",
    menu_preview_anim_state = "ChipGreen_PREVIEW",
    menu_preview_sprite_id  = "menu_preview_ChipGreen",
    menu_preview_offset_x   = 7,
    menu_preview_offset_y   = 0,
    menu_preview_scale      = 1.5,
  },
  {
    id              = "ChipRed",
    key             = "ChipRed",
    name            = "ChipRed",
    texture         = "/server/assets/cosmetics/ChipRed.png",
    animation       = "/server/assets/cosmetics/ChipRed.animation",
    anim_state      = "ChipRed",
    preview_sprite_id = "preview_ChipRed",
    rarity          = "GOLD_3",
    loop_duration = 1.2,

    xforced         = 16,
    yforced         = 0,

    preview_start_x = -8,
    preview_start_y = -70,

    menu_preview_texture    = "/server/assets/cosmetics/ChipRed_preview.png",  
    menu_preview_animation  = "/server/assets/cosmetics/ChipRed_preview.animation",
    menu_preview_anim_state = "ChipRed_PREVIEW",
    menu_preview_sprite_id  = "menu_preview_ChipRed",
    menu_preview_offset_x   = 7,
    menu_preview_offset_y   = 0,
    menu_preview_scale      = 1.5,
  },
  {
    id              = "ChipMulti",
    key             = "ChipMulti",
    name            = "ChipMulti",
    texture         = "/server/assets/cosmetics/ChipMulti.png",
    animation       = "/server/assets/cosmetics/ChipMulti.animation",
    anim_state      = "ChipMulti",
    preview_sprite_id = "preview_ChipMulti",
    rarity          = "GOLD_3",
    loop_duration = 1.2,

    xforced         = 16,
    yforced         = 0,

    preview_start_x = -8,
    preview_start_y = -70,

    menu_preview_texture    = "/server/assets/cosmetics/ChipMulti_preview.png",  
    menu_preview_animation  = "/server/assets/cosmetics/ChipMulti_preview.animation",
    menu_preview_anim_state = "ChipMulti_PREVIEW",
    menu_preview_sprite_id  = "menu_preview_ChipMulti",
    menu_preview_offset_x   = 7,
    menu_preview_offset_y   = 0,
    menu_preview_scale      = 1.5,
  },
  {
    id              = "Sims",
    key             = "Sims",
    name            = "Sims",
    texture         = "/server/assets/cosmetics/Sims.png",
    animation       = "/server/assets/cosmetics/Sims.animation",
    anim_state      = "SIMS",
    preview_sprite_id = "preview_Sims",
    rarity          = "GOLD_1",
    loop_duration = 5,
    world_scale       = 0.3,
    bot_scale       = 0.15,

    xforced         = 9,
    yforced         = 0,

    preview_start_x = -5,
    preview_start_y = -50,
    preview_scale   = 0.3,

    menu_preview_texture    = "/server/assets/cosmetics/Sims_preview.png",  
    menu_preview_animation  = "/server/assets/cosmetics/Sims_preview.animation",
    menu_preview_anim_state = "SIMS_preview",
    menu_preview_sprite_id  = "menu_preview_Sims",
    menu_preview_offset_x   = 10,
    menu_preview_offset_y   = 5,
    menu_preview_scale      = 0.5,
  },
  {
    id                = "BugFrag",
    key               = "BugFrag",
    name              = "BugFrag",
    texture           = "/server/assets/cosmetics/bugfrag.png",
    animation         = "/server/assets/cosmetics/bugfrag.animation",
    anim_state        = "BugFrag",
    preview_sprite_id = "preview_BugFrag",
    rarity          = "GREEN_1",
    loop_duration     = 1.2,
    world_scale       = 1.0,
    bot_scale         = 0.5,

    xforced         = 12,
    yforced         = 0,

    preview_start_x = -6,
    preview_start_y = 4,
    preview_scale   = 1.0,

    menu_preview_texture    = "/server/assets/cosmetics/bugfrag_preview.png",  
    menu_preview_animation  = "/server/assets/cosmetics/bugfrag_preview.animation",
    menu_preview_anim_state = "BugFrag_PREVIEW",
    menu_preview_sprite_id  = "menu_preview_BugFrag",
    menu_preview_offset_x   = 5,
    menu_preview_offset_y   = 10,
    menu_preview_scale      = 1.5,
  },
  {
    id                = "ColonelB",
    key               = "ColonelB",
    name              = "ColonelB",
    texture           = "/server/assets/cosmetics/ColonelB.png",
    animation         = "/server/assets/cosmetics/ColonelB.animation",
    anim_state        = "ColonelB",
    preview_sprite_id = "preview_ColonelB",
    rarity          = "GOLD_1",
    loop_duration     = 1.2,
    world_scale       = 1.0,
    bot_scale         = 0.5,

    xforced         = 12,
    yforced         = 0,

    preview_start_x = -6,
    preview_start_y = 4,
    preview_scale   = 1.0,

    menu_preview_texture    = "/server/assets/cosmetics/ColonelB_preview.png",  
    menu_preview_animation  = "/server/assets/cosmetics/ColonelB_preview.animation",
    menu_preview_anim_state = "ColonelB_preview",
    menu_preview_sprite_id  = "menu_preview_ColonelB",
    menu_preview_offset_x   = 5,
    menu_preview_offset_y   = 10,
    menu_preview_scale      = 1.5,
  },
  {
    id                = "ProtomanB",
    key               = "ProtomanB",
    name              = "ProtomanB",
    texture           = "/server/assets/cosmetics/ProtomanB.png",
    animation         = "/server/assets/cosmetics/ProtomanB.animation",
    anim_state        = "ProtomanB",
    preview_sprite_id = "preview_ProtomanB",
    rarity          = "GOLD_1",
    loop_duration     = 1.2,
    world_scale       = 1.0,
    bot_scale         = 0.5,

    xforced         = 12,
    yforced         = 0,

    preview_start_x = -6,
    preview_start_y = 4,
    preview_scale   = 1.0,

    menu_preview_texture    = "/server/assets/cosmetics/ProtomanB_preview.png",  
    menu_preview_animation  = "/server/assets/cosmetics/ProtomanB_preview.animation",
    menu_preview_anim_state = "ProtomanB_preview",
    menu_preview_sprite_id  = "menu_preview_ProtomanB",
    menu_preview_offset_x   = 5,
    menu_preview_offset_y   = 10,
    menu_preview_scale      = 1.5,
  },
  {
    id              = "bugfragpile",
    key             = "bugfragpile",
    name            = "BugFrag_Pile",
    texture         = "/server/assets/cosmetics/bugfragpile.png",
    animation       = "/server/assets/cosmetics/bugfragpile.animation",
    anim_state      = "BUGFRAGPILE",
    preview_sprite_id = "preview_bugfragpile",
    rarity          = "GOLD_4",
    loop_duration = 0.9,

    xforced         = 40,
    yforced         = 0,

    preview_start_x = -19,
    preview_start_y = -10,

    menu_preview_texture    = "/server/assets/cosmetics/bugfragpile_preview.png",  
    menu_preview_animation  = "/server/assets/cosmetics/bugfragpile_preview.animation",
    menu_preview_anim_state = "BUGFRAGPILE_preview",
    menu_preview_sprite_id  = "menu_preview_bugfragpile",
    menu_preview_offset_x   = 0,
    menu_preview_offset_y   = 5,
    menu_preview_scale      = 1.5,
  },
  {
    id              = "bugfragdealer",
    key             = "bugfragdealer",
    name            = "BugFrag_Dealer",
    texture         = "/server/assets/cosmetics/bugfragdealer.png",
    animation       = "/server/assets/cosmetics/bugfragdealer.animation",
    anim_state      = "BUGFRAGDEALER",
    preview_sprite_id = "preview_bugfragdealer",
    rarity          = "GOLD_5",
    loop_duration = 0.9,

    xforced         = 82,
    yforced         = 0,

    preview_start_x = -40,
    preview_start_y = -10,

    menu_preview_texture    = "/server/assets/cosmetics/bugfragdealer_preview.png",  
    menu_preview_animation  = "/server/assets/cosmetics/bugfragdealer_preview.animation",
    menu_preview_anim_state = "BUGFRAGDEALER_preview",
    menu_preview_sprite_id  = "menu_preview_bugfragdealer",
    menu_preview_offset_x   = -15,
    menu_preview_offset_y   = 5,
    menu_preview_scale      = 1.5,
  },
  {
    id              = "dmgaura",
    key             = "dmgaura",
    name            = "Damage_Aura",
    texture         = "/server/assets/cosmetics/dmgaura.png",
    animation       = "/server/assets/cosmetics/dmgaura.animation",
    anim_state      = "dmgaura",
    preview_sprite_id = "preview_dmgaura",
    rarity          = "GREEN_4",
    loop_duration = 1.0,

    xforced         = 50,
    yforced         = 0,

    preview_start_x = -25,
    preview_start_y = -40,

    menu_preview_texture    = "/server/assets/cosmetics/dmgaura_preview.png",
    menu_preview_animation  = "/server/assets/cosmetics/dmgaura_preview.animation",
    menu_preview_anim_state = "dmgaura_preview",
    menu_preview_sprite_id  = "menu_preview_dmgaura",
    menu_preview_offset_x   = 0,
    menu_preview_offset_y   = 5,
    menu_preview_scale          = 1.25,
    menu_preview_loop_duration  = 1.0,
  },
  {
    id              = "Wave1",
    key             = "Wave1",
    name            = "Wave1",
    texture         = "/server/assets/cosmetics/Wave1.png",
    animation       = "/server/assets/cosmetics/Wave1.animation",
    anim_state      = "WAVE1",
    preview_sprite_id = "preview_Wave1",
    rarity          = "RED_5",
    loop_duration = 0.7,

    xforced         = 0,
    yforced         = 0,

    preview_start_x = 0,
    preview_start_y = 0,

    menu_preview_texture    = "/server/assets/cosmetics/Wave1_preview.png",
    menu_preview_animation  = "/server/assets/cosmetics/Wave1_preview.animation",
    menu_preview_anim_state = "Wave1_preview",
    menu_preview_sprite_id  = "menu_preview_Wave1",
    menu_preview_offset_x   = 13,
    menu_preview_offset_y   = 25,
    menu_preview_scale          = 1.25,
    menu_preview_loop_duration  = 1.0,
  },
  {
    id              = "Beastout",
    key             = "Beastout",
    name            = "Beastout",
    texture         = "/server/assets/cosmetics/Beastout.png",
    animation       = "/server/assets/cosmetics/Beastout.animation",
    anim_state      = "BEASTOUT",
    preview_sprite_id = "preview_Beastout",
    rarity          = "GREEN_4",
    loop_duration = 0.36,

    xforced         = 70,
    yforced         = 0,

    preview_start_x = -36,
    preview_start_y = -50,

    menu_preview_texture    = "/server/assets/cosmetics/Beastout_preview.png",
    menu_preview_animation  = "/server/assets/cosmetics/Beastout_preview.animation",
    menu_preview_anim_state = "BEASTOUT_preview",
    menu_preview_sprite_id  = "menu_preview_Beastout",
    menu_preview_offset_x   = -3,
    menu_preview_offset_y   = -3,
    menu_preview_scale          = 1.0,
  },
  {
    id              = "ShadowAura",
    key             = "ShadowAura",
    name            = "ShadowAura",
    texture         = "/server/assets/cosmetics/ShadowAura.png",
    animation       = "/server/assets/cosmetics/ShadowAura.animation",
    anim_state      = "SHADOWAURA",
    preview_sprite_id = "preview_ShadowAura",
    rarity          = "GOLD_5",
    loop_duration = 1.3,

    xforced         = 64,
    yforced         = 0,

    preview_start_x = -32,
    preview_start_y = -46,

    menu_preview_texture    = "/server/assets/cosmetics/ShadowAura_preview.png",
    menu_preview_animation  = "/server/assets/cosmetics/ShadowAura_preview.animation",
    menu_preview_anim_state = "SHADOWAURA_preview",
    menu_preview_sprite_id  = "menu_preview_ShadowAura",
    menu_preview_offset_x   = -3,
    menu_preview_offset_y   = 7,
    menu_preview_scale          = 1.0,
  },
  {
    id              = "Lightning1",
    key             = "Lightning1",
    name            = "Lightning1",
    texture         = "/server/assets/cosmetics/Lightning1.png",
    animation       = "/server/assets/cosmetics/Lightning1.animation",
    anim_state      = "LIGHTNING",
    preview_sprite_id = "preview_Lightning1",
    rarity          = "RED_5",
    loop_duration = 1.6,

    xforced         = 50,
    yforced         = 0,

    preview_start_x = -25,
    preview_start_y = -60,

    menu_preview_texture    = "/server/assets/cosmetics/Lightning1_preview.png",
    menu_preview_animation  = "/server/assets/cosmetics/Lightning1_preview.animation",
    menu_preview_anim_state = "LIGHTNING_preview",
    menu_preview_sprite_id  = "menu_preview_Lightning1",
    menu_preview_offset_x   = 5,
    menu_preview_offset_y   = 0,
    menu_preview_scale          = 1.0,
  },
  {
    id              = "Tokens",
    key             = "Tokens",
    name            = "Tokens",
    texture         = "/server/assets/cosmetics/Tokens.png",
    animation       = "/server/assets/cosmetics/Tokens.animation",
    anim_state      = "Tokens",
    preview_sprite_id = "preview_Tokens",
    rarity          = "CYAN_5",
    loop_duration = 1.6,

    xforced         = 37,
    yforced         = 0,

    preview_start_x = -18,
    preview_start_y = -48,

    menu_preview_texture    = "/server/assets/cosmetics/Tokens_preview.png",
    menu_preview_animation  = "/server/assets/cosmetics/Tokens_preview.animation",
    menu_preview_anim_state = "Tokens_preview",
    menu_preview_sprite_id  = "menu_preview_Tokens",
    menu_preview_offset_x   = 5,
    menu_preview_offset_y   = 5,
    menu_preview_scale          = 1.0,
  },
  {
    id              = "ProtoBadge",
    key             = "ProtoBadge",
    name            = "ProtoBadge",
    texture         = "/server/assets/cosmetics/ProtoBadge.png",
    animation       = "/server/assets/cosmetics/ProtoBadge.animation",
    anim_state      = "idle_protobadge",
    preview_sprite_id = "preview_ProtoBadge",
    rarity          = "GREEN_5",
    loop_duration = 2.9,

    xforced         = 23,
    yforced         = -2,

    preview_start_x = -12,
    preview_start_y = -2,

    menu_preview_texture    = "/server/assets/cosmetics/ProtoBadge_preview.png",
    menu_preview_animation  = "/server/assets/cosmetics/ProtoBadge_preview.animation",
    menu_preview_anim_state = "idle_protobadge",
    menu_preview_sprite_id  = "menu_preview_ProtoBadge",
    menu_preview_offset_x   = 8,
    menu_preview_offset_y   = 12,
    menu_preview_scale          = 1.0,
  },
  {
    id              = "Shiny1",
    key             = "Shiny1",
    name            = "Shiny1",
    texture         = "/server/assets/cosmetics/Shiny1.png",
    animation       = "/server/assets/cosmetics/Shiny1.animation",
    anim_state      = "idle_shiny1",
    preview_sprite_id = "preview_Shiny1",
    rarity          = "RED_5",
    loop_duration = 2.18,

    xforced         = 37,
    yforced         = 0,

    preview_start_x = -18,
    preview_start_y = -45,

    menu_preview_texture    = "/server/assets/cosmetics/Shiny1_preview.png",
    menu_preview_animation  = "/server/assets/cosmetics/Shiny1_preview.animation",
    menu_preview_anim_state = "idle_shiny1",
    menu_preview_sprite_id  = "menu_preview_Shiny1",
    menu_preview_offset_x   = 5,
    menu_preview_offset_y   = 8,
    menu_preview_scale      = 1.0,
  },
  {
    id              = "FullShiny",
    key             = "FullShiny",
    name            = "FullShiny",
    texture         = "/server/assets/cosmetics/FullShiny.png",
    animation       = "/server/assets/cosmetics/FullShiny.animation",
    anim_state      = "idle_fullshiny",
    preview_sprite_id = "preview_FullShiny",
    rarity          = "GOLD_5",
    loop_duration = 2.18,

    xforced         = 48,
    yforced         = 0,

    preview_start_x = -24,
    preview_start_y = -47,

    menu_preview_texture    = "/server/assets/cosmetics/FullShiny.png",
    menu_preview_animation  = "/server/assets/cosmetics/FullShiny.animation",
    menu_preview_anim_state = "idle_fullshiny",
    menu_preview_sprite_id  = "menu_preview_FullShiny",
    menu_preview_offset_x   = 2,
    menu_preview_offset_y   = 8,
    menu_preview_scale      = 1.0,
  },
}

return {
  cfg       = cfg,
  cosmetics = cosmetics,
}
