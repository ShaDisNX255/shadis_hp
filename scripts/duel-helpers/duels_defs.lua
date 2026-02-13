-- Auto-generated helper module: duel constants moved out of duels.lua
-- Put this file at: scripts/duel-helpers/duels_defs.lua

local defs = {
  ATKDEF_ANIM = "/server/assets/duels/atkdef.animation",
  ATKDEF_SPRITE_ID = "duel_atkdef",
  ATKDEF_TEX = "/server/assets/duels/atkdef.png",
  ATKPOS_ANIM = "/server/assets/duels/atkpos.animation",
  ATKPOS_SPRITE_ID = "duel_atkpos",
  ATKPOS_STATE_ATK = "atk",
  ATKPOS_STATE_POS = "pos",
  ATKPOS_TEX = "/server/assets/duels/atkpos.png",
  ATTACK_MZ1_OBJ_ID = "duel_attack_mz1_obj",
  ATTACK_MZ2_OBJ_ID = "duel_attack_mz2_obj",
  CARD_ANIM = "/server/assets/duels/card.animation",
  CARD_STATE = "idle",
  CURSOR_ANIM = "/server/assets/duels/cursor.animation",
  CURSOR_SPRITE_ID = "duel_cursor",
  CURSOR_STATE = "cursor",
  CURSOR_TEX = "/server/assets/duels/cursor.png",
  DECK_MEM_KEY = "miniygo_deck_v2",
  DUELS_RNG_NONCE_KEY = "__duels_rng_nonce_v1",
  FACEDOWN_SPR = "duel_facedown",
  FACE_DOWN_TEX = "/server/assets/cards_ow/FaceDown.png",
  FIELD_ANIM = "/server/assets/duels/fieldui.animation",
  FIELD_MENU_ATK_OBJ_ID = "duel_field_menu_atk",
  FIELD_MENU_POS_OBJ_ID = "duel_field_menu_pos",
  FIELD_SPRITE_ID = "duel_field_ui",
  FIELD_STATE = "fieldui",
  FIELD_TEX = "/server/assets/duels/fieldui.png",
  INFO_ATK_ICON_ID = "duel_info_atk_icon",
  INFO_ATK_VAL_ID = "duel_info_atk_val",
  INFO_DEF_ICON_ID = "duel_info_def_icon",
  INFO_DEF_VAL_ID = "duel_info_def_val",
  INFO_NAME_ID = "duel_info_name",
  MINICURSOR_ANIM = "/server/assets/duels/minicursor.animation",
  MINICURSOR_SPRITE_ID = "duel_minicursor",
  MINICURSOR_STATE = "minicursor",
  MINICURSOR_TEX = "/server/assets/duels/minicursor.png",
  MZ1_OBJ_ID = "duel_mz1_obj",
  MZ2_OBJ_ID = "duel_mz2_obj",
  OPP_HAND_OBJ_PREFIX = "duel_opp_hand_",
  OPP_HAND_SPRITE_ID = "duel_opp_hand_facedown",
  OPP_INFO_ATK_ICON_ID = "duel_opp_info_atk_icon",
  OPP_INFO_ATK_VAL_ID = "duel_opp_info_atk_val",
  OPP_INFO_DEF_ICON_ID = "duel_opp_info_def_icon",
  OPP_INFO_DEF_VAL_ID = "duel_opp_info_def_val",
  OPP_INFO_NAME_ID = "duel_opp_info_name",
  OPP_POINTS_OBJ_PREFIX = "duel_opp_point_",
  PARTICLE_DEFAULT_OX = 32,
  PARTICLE_DEFAULT_OY = 32,
  PARTICLE_OBJ_PREFIX = "duel_dust_",
  PARTICLE_SPRITE_ID = "duel_particle",
  PARTICLE_TEX = "/server/assets/particle.png",
  PAUSE_MENU_CON_OBJ_ID = "duel_pause_con",
  PAUSE_MENU_CURSOR_OBJ_ID = "duel_pause_cursor",
  PAUSE_MENU_TURN_OBJ_ID = "duel_pause_turn",
  PLY_HAND_OBJ_PREFIX = "duel_ply_hand_",
  PLY_POINTS_OBJ_PREFIX = "duel_ply_point_",
  POINTCOUNTER_ANIM = "/server/assets/duels/pointcounter.animation",
  POINTCOUNTER_SPRITE_ID = "duel_pointcounter",
  POINTCOUNTER_TEX = "/server/assets/duels/pointcounter.png",
  POS_ANIM_OBJ_ID = "duel_pos_anim_obj",
  RNG_MOD = 2147483647,
  RNG_MUL = 16807,
  SUMMONS_ANIM = "/server/assets/duels/summons.animation",
  SUMMONS_SPRITE_ID = "duel_summons",
  SUMMONS_STATE_SET = "set",
  SUMMONS_STATE_SUMMON = "summon",
  SUMMONS_TEX = "/server/assets/duels/summons.png",
  SUMMON_ANIM_OBJ_ID = "duel_summon_anim_obj",
  TURNCON_ANIM = "/server/assets/duels/turncon.animation",
  TURNCON_SPRITE_ID = "duel_turncon",
  TURNCON_STATE_CON = "con",
  TURNCON_STATE_TURN = "turn",
  TURNCON_TEX = "/server/assets/duels/turncon.png",
  RARITY_DIR = {
  C   = "/server/assets/cards_ow/common",
  R   = "/server/assets/cards_ow/rare",
  SR  = "/server/assets/cards_ow/srare",
  UR  = "/server/assets/cards_ow/urare",
  GR  = "/server/assets/cards_ow/grare",
  GDR = "/server/assets/cards_ow/gdrare",
},
  SPELLCOUNTER_TEX = "/server/assets/duels/counter.png",
  SPELLCOUNTER_ANIM = "/server/assets/duels/counter.animation",
  SPELLCOUNTER_SPRITE_ID = "duel_spellcounter",
  SPELLCOUNTER_STATE = "counter",
  SPELLSUI_TEX = "/server/assets/duels/spellsui.png",
  SPELLSUI_ANIM = "/server/assets/duels/spellsui.animation",
  SPELLSUI_SPRITE_ID = "duel_spellsui",
  SPELLSUI_STATE = "spellsui",

  SPELLICONS_TEX = "/server/assets/duels/spellicons.png",
  SPELLICONS_ANIM = "/server/assets/duels/spellicons.animation",
  SPELLICONS_SPRITE_ID = "duel_spellicons",

  SPELLS_MENU_BG_OBJ_ID = "duel_spells_menu_bg",
  SPELLS_MENU_CURSOR_OBJ_ID = "duel_spells_menu_cursor",
  SPELLS_MENU_ICON_PREFIX = "duel_spells_menu_icon_",
  SPELLS_MENU_COST_PREFIX = "duel_spells_menu_cost_",
  SPELLS_MENU_TEXT_NAME_PREFIX = "duel_spells_menu_name_",
  SPELLS_MENU_TEXT_DESC_PREFIX = "duel_spells_menu_desc_",
  PLY_SPELL_OBJ_PREFIX = "duel_ply_spell_",
  OPP_SPELL_OBJ_PREFIX = "duel_opp_spell_",
  TURNCON_STATE_SPELL = "spell",
  PAUSE_MENU_SPELL_OBJ_ID = "duel_pause_spell",
  KNOBS = {
    -- Win condition point counters (3 pips each)
    POINT_COUNTER = {
      enabled = true,

      -- overall scale + depth
      sx = 2.0,
      sy = 2.0,
      z  = 210,

      -- Counter #1 (player points): base position (pip #1)
      ply_x = 95,
      ply_y = 147,

      -- Counter #2 (opponent points): base position (pip #1)
      opp_x = 95,
      opp_y = 10,

      -- spacing between pips (use two knobs because the art is “weird”)
      dy12 = 16,
      dy23 = 18,

      -- state names (if your .animation uses different spellings, tweak here)
      empty_states  = { "empty1",  "empty2",  "empty3"  },
      filled_states = { "filled1", "filled2", "filled3" },

      -- how long to leave the duel UI up after someone reaches 3, before auto-close
      end_hold = 1.0,
    },

    -- Spell counters (spells). Debug-draws two sets of 6 so you can position/scale.
    SPELL_COUNTER = {
      enabled = true,
      debug_draw_all = false,
      max = 6,

      -- overall scale + depth
      sx = 1.0,
      sy = 1.0,
      z  = 210,

      -- spacing between counters (layout px)
      dx = 8,
      dy = 0,

      -- Player counters: appear left -> right
      ply_x = 150,
      ply_y = 90,
      ply_dir = 1,

      -- Opponent counters: appear right -> left (mirrored field)
      opp_x = 90,
      opp_y = 70,
      opp_dir = -1,
    },

    -- Defender reveal hold (when a face-down DEF monster is attacked)
    REVEAL = {
      enabled = true,
      hold = 1.0, -- seconds revealed before finishing battle resolution
    },
    -- Monster Zone cards (from duels (3).lua)
    MZ1 = { x = 90, y = 4,  sx = 3.0, sy = 3.0, z = -90, ro = 180 }, -- opponent
    MZ2 = { x = 89, y = 67, sx = 3.0, sy = 3.0, z = -90, ro = 0   }, -- player
  -- Particle burst when a monster is destroyed
  DESTROY_DUST = {
    enabled = true,

    -- how many particles per burst and how many can exist at once
    count = 28,
    limit = 96,

    -- particle lifetime in "frames" (ticks), and spawn jitter around center
    life_frames = 30,
    jitter = 2.0,

    -- motion tuning (units are in your pre-UI_POS_MULT coordinate space)
    vel = 3.6,
    gravity = 0.08,
    friction = 0.96,

    -- scale starts large then shrinks (min is the "end" size)
    scale_min = 0.20,
    scale_max = 1.05,

    -- draw depth (added to MZ z)
    z_offset = 20,

    -- particle texture origin (particle.png is usually 64x64)
    ox = 32,
    oy = 32,

    -- additive blending if supported by this fork (scripts/libs/enums)
    add_blend = true,

    -- optional color tint range (defaults to a bright bluish-white)
    r = { 220, 255 },
    g = { 220, 255 },
    b = { 255, 255 },
    -- rainbow tinting: recolor *some* particles after spawn
    -- set rainbow=true to enable (keeps most particles in the default bluish-white)
    rainbow = true,
    rainbow_chance = 0.40,   -- 0..1 chance each spawned particle becomes rainbow
    rainbow_by_angle = true, -- true = hue based on particle direction, false = random hue
    rainbow_sat = 1.0,       -- 0..1 saturation
    rainbow_val = 1.0,       -- 0..1 value/brightness

    -- if true, rainbow particles will *shift hue every tick* (animated rainbow)
    rainbow_animate = true,
    -- degrees of hue shift per tick (higher = faster color cycling)
    rainbow_tick_deg = 80,
    -- additional degrees of hue shift over particle lifetime (1 full cycle = 360)
    rainbow_life_deg = 360,
  },
    SUMMON_MENU = {
      -- scale for the 16x16 summon/set icons
      sx = 2, sy = 2,
      z = -58,

      -- position relative to selected card (layout space)
      -- These offsets are applied from the selected card's TOP-LEFT before origin conversion.
      -- Tweak these to land "towards the bottom" like you want.
      offset_x = 32.5,   -- roughly card center in card pixels
      offset_y = 15,     -- near bottom (assuming ~30px tall card)
      gap_x = 18,        -- distance between summon and set icon centers (layout px)
    },

    FIELD_MENU = {
      -- scale for the 16x16 atk/pos icons
      sx = 2, sy = 2,
      z = -58,

      -- position relative to the player's field card (layout space)
      -- These offsets are applied from the field card's TOP-LEFT before origin conversion.
      offset_x = 32.5,
      offset_y = 15,
      gap_x = 18,
    },

    MINICURSOR = {
      sx = 2, sy = 2,
      z = -57,

      -- extra offsets from whichever icon center we’re selecting
      offset_x = 0,
      offset_y = 0,
    },

    -- Summon (not set) animation: card flies from hand to MZ2 with a smooth arc + scale pulse.
    -- Implemented purely via sprites-api by updating ONE sprite-object each tick.
    SUMMON_ANIM = {
      enabled = true,

      -- seconds from hand -> zone
      duration = 0.25,

      -- arc height in layout-space units (positive number moves arc UP)
      arc_height = 24,

      -- peak scale multiplier at the midpoint (1.0 = no pulse)
      peak_scale_mul = 1.35,

      -- draw layer for the flying card (should be above hand)
      z = -70,

      -- optional tiny rotation wobble (degrees), 0 disables
      wobble_ro_deg = 0,
    },

    -- Position change animation (for "Change Position" on-field)
    -- Also sprites-api only: updates ONE sprite-object each tick.
    POS_ANIM = {
      enabled = true,

      -- seconds for the rotate / reveal
      duration = 0.18,

      -- small scale pulse at midpoint (1.0 = no pulse)
      peak_scale_mul = 1.15,

      -- used only for facedown -> faceup reveal flip
      flip_min = 0.06,
      swap_t   = 0.5,

      -- draw layer for the animating card (should be above the zone card)
      z = -70,
    },

  -- Attack animation (card "recoil then lunge")
  ATTACK_ANIM = {
    enabled = true,

    duration = 0.22,   -- seconds

    -- player zone (MZ2): 0 -> +recoil (down) -> -lunge (up) -> 0
    ply_recoil = 5,
    ply_lunge  = 15,

    -- opponent zone (MZ1): 0 -> -recoil (up) -> +lunge (down) -> 0
    opp_recoil = 5,
    opp_lunge  = 15,

    -- phase timings in normalized t (0..1)
    t1 = 0.25,  -- end recoil
    t2 = 0.60,  -- end lunge (then return to 0)

    -- draw above the normal monster z
    z_offset = 12,
  },

  -- Pause menu (End Turn / Concede)
  PAUSE_MENU = {
    -- final/top-left position of the menu group (layout space)
    x = 7,
    y = 7,

    -- scale for the 16x16 buttons
    sx = 3,
    sy = 3,

    -- draw order
    z = 210,

    -- vertical spacing between the two buttons (layout px)
    gap_y = 30,

    -- Cursor placement (uses regular cursor sprite, rotated 90°, placed to the RIGHT)
    cursor_ro = 90,
    cursor_sx = 2,
    cursor_sy = 2,

    -- distance to the right of the button (layout px)
    cursor_gap_x = 20,

    -- extra fine offsets (layout px)
    cursor_off_x = -17,
    cursor_off_y = -10,

    -- Slide-in animation (from left -> final position)
    slide_enabled = true,
    slide_from_x = -35,     -- starting offset in layout px (negative means offscreen-left)
    slide_duration = 0.5,
    },

  -- Spells menu
  SPELLS_MENU = {
    enabled = true,

    -- background texture is 160x100 with 0,0 anchor
    x = 15,      -- centered on 240x160
    y = 15,
    w = 160,
    h = 100,
    z = 235,

    sx = 2.8,
    sy = 2.7,

    pad_x = 10,
    pad_y = 10,

    -- Each spell takes up 2 lines; this is the total row height.
    row_h = 20,
    visible_rows = 6,

    -- Icon + text layout
    icon_sx = 1.7,
    icon_sy = 1.5,
    icon_gap_x = 0,

    name_font = "THICK",
    name_scale = 1.6,
    desc_font = "THICK",
    desc_scale = 1.1,
    name_off_y = 0,
    desc_off_y = 10,

    -- Cost counters (small)
    cost_sx = 1.0,
    cost_sy = 1.0,
    cost_dx = 7,
    cost_off_y = 5,
    max_cost = 6,

    -- Cursor (regular cursor sprite, rotated 270°, placed to the LEFT)
    cursor_ro = 270,
    cursor_sx = 2,
    cursor_sy = 2,
    cursor_gap_x = 2,
    cursor_off_x = -4,
    cursor_off_y = -2,
  },

  -- Opponent AI knobs
  -- Decision logic lives in duels_AI.lua; this file schedules animations + executes the plan.
  AI = {
    enabled = true,

    -- AI type:
    --   "default" (implemented)
    --   "aggressive" (TODO)
    --   "smart" (TODO)
    -- If st.cfg.ai_type isn't set, this "type" is used as the fallback.
    type = "default",

    -- Delay before the AI starts acting on its turn (seconds)
    think_delay = 0.20,

    -- Delay between finishing a summon/position-change and starting an attack (seconds)
    attack_delay = 0.45,

    -- If the AI has no legal action, how long to wait before ending its turn (seconds)
    end_turn_delay = 0.4,

    -- Print the AI plan + reason to logs
    debug = false,
  },
    UI_POS_MULT = 2,

    FIELD = { x = 0, y = 0, sx = 2, sy = 2, z = -100 },

    -- You changed card.animation originx/originy; set these to match.
    -- (We compensate positions by converting TOP-LEFT -> ORIGIN coords.)
    CARD_ORIGIN = { ox = 10.5, oy = 15 },

    -- "top_left": x/y knobs represent TOP-LEFT of the unrotated card
    -- "origin"  : x/y knobs represent the ORIGIN (pivot) directly
    CARD_POS_MODE = "top_left",

    -- Hand layout
    HAND = {
      scale     = 3.0,
      spacing_x = 18,
      z         = -80,

      -- Centering behavior: your PLY_HAND_POS / OPP_HAND_POS are tuned for 2 cards (card1 at base).
      -- When count != tuned_for_count, we shift start_x so the group's center stays fixed.
      center_enabled  = true,
      tuned_for_count = 2,

      -- erase safety: how many hand objects to wipe on close/open
      max_cards_to_clear = 10,
      highlight_lift_y = 5, -- pixels in your layout space (before UI_POS_MULT)
    },

    -- Base positions (these are your "card #1 TOP-LEFT" positions when tuned_for_count cards)
    OPP_HAND_POS = { x = 150, y = -18, ro = 0 },
    PLY_HAND_POS = { x = 10, y = 90, ro = 0 },

    -- Starting hands
    STARTING_HAND = { player = 2, opponent = 2 },

    -- Max hand sizes (you said you'll set max=4 later; this already supports it)
    HAND_MAX = { player = 4, opponent = 4 },

    CURSOR = {
      -- cursor sprite scale (independent of card scale)
      sx = 2,
      sy = 2,

      -- cursor draw order (should be above cards)
      z = 250,

      -- extra offset from the computed card-center (let you align the graphic)
      offset_x = 0,
      offset_y = -25,

      -- what point on the card we treat as "center" in *card local pixels*
      -- defaulting to your card origin works well since yours is centered (10.5, 15)
      card_center_x = 10.5,
      card_center_y = 15,
    },

    -- Card info panel (right side)
    -- All positions are in "logical" coordinates (will be multiplied by UI_POS_MULT by sprites/displayer).
    INFO_PANEL = {
      -- Base position of the whole group
      x = 175,
      y = 110,
      z = 206,

      -- Monster name (centered within name_center_w)
      name_y = -10,
      name_center_w = 80,
      name_char_w = 6,   -- rough char width in THICK font at scale=1
      name_scale = 2,
      name_font = "THICK",

      -- Name alignment:
      -- "center": centered inside [x .. x+name_center_w]
      -- "left": left-aligned at x + name_x_offset
      name_align = "left",
      name_x_offset = -5,

      -- ATK / DEF rows (left aligned)
      icon_x = -20,
      icon_scale = 2.0,

      atk_y = 12,
      def_y = 25,

      value_x = -5,      -- offset from base x (not from icon width)
      value_y_offset = -2,

      atk_value_font = "GRADIENT",
      def_value_font = "GRADIENT_GREEN",
      value_scale = 2,
    },
    -- Opponent info panel (always shows opponent field card).
    -- Inherits all other settings from INFO_PANEL; override x/y/z here.
    OPP_INFO_PANEL = {
      x = 30,
      y = 20,
      z = 206,
    },
    DRAW_ANIM = {
      slide_dy       = 20,
      slide_duration = 0.22, -- scaled by TIME_SCALE automatically
      move_duration  = 0.28, -- scaled by TIME_SCALE automatically
      max_visible    = 10,
      stack_dx       = 1,
      stack_dy       = -1,
    },
    TIME_SCALE = 0.60, -- 0.25 for 75% faster (more aggressive)
  },
}

return defs
