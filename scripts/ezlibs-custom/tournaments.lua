-- /server/scripts/ezlibs-custom/tournaments.lua
-- ShaDisHP tournament controller (backend-first version)
--
-- What this first version does:
--   * Uses Tiled objects with type/class "Tournament Board"
--   * Lets players join a board queue
--   * Host can start early; empty slots are backfilled with NPCs
--   * Runs an 8-slot single-elimination bracket: 8 -> 4 -> 2 -> 1
--   * Human vs Human uses WCity-style 1000 HP PvP, but does NOT affect OctoPVP ELO
--   * Human vs NPC uses Async.initiate_encounter() directly to avoid ezencounters pet injection/rewards
--   * NPC vs NPC is simulated with weighted random results
--
-- Later versions can add the fancy bracket art/UI after this backend is proven stable.

local Tournaments = {}

local ezmemory_ok, ezmemory = pcall(require, "scripts/ezlibs-scripts/ezmemory")
if not ezmemory_ok then
  ezmemory = nil
end

local teams_ok, Teams = pcall(require, "scripts/teams/teams")
if not teams_ok then
  Teams = nil
  print("[tournaments] WARNING: scripts/teams/teams could not be loaded; tournament GP rewards disabled")
end

local games_ok, games = pcall(require, "scripts/net-games/main")
if not games_ok then
  games = nil
  print("[tournaments] WARNING: scripts/net-games/main could not be loaded; visual board disabled")
end

local displayer_ok, Displayer = pcall(require, "scripts/net-games/displayer/displayer")
if not displayer_ok then
  Displayer = nil
  print("[tournaments] WARNING: displayer could not be loaded; tournament text boxes disabled")
end

local input_ok, Input = pcall(require, "scripts/net-games/input/input")
if not input_ok then
  Input = nil
  print("[tournaments] WARNING: input helper could not be loaded; spectator cancel disabled")
elseif Input.attach_virtual_input_listener then
  Input.attach_virtual_input_listener()
end

local object_registry_ok, object_registry = pcall(require, "scripts/ezlibs-scripts/object_registry")
if not object_registry_ok then
  object_registry = nil
  print("[tournaments] WARNING: object_registry could not be loaded; scheduled tournament announcements require board interaction first")
end

local package_registry_ok, package_registry = pcall(require, "scripts/ezlibs-scripts/ezencounters/package_registry")
if not package_registry_ok then
  package_registry = nil
  print("[tournaments] WARNING: encounter package registry unavailable; tournament fallback validation disabled")
end

local MenuAPI
do
  local ok, mod = pcall(require, "scripts/menuAPI/main")
  if ok and type(mod) == "table" then
    MenuAPI = mod
  else
    MenuAPI = nil
    print("[tournaments] WARNING: MenuAPI could not be loaded; tournament lobby/confirm UI disabled")
  end
end

local function require_visual_module(label, path)
  local ok, mod = pcall(require, path)
  if not ok then
    print("[tournaments][visual] WARNING: could not load " .. label .. " from " .. path .. ": " .. tostring(mod))
    return nil
  end
  return mod
end

local constants = require_visual_module("constants", "scripts/net-game-tourney/constants")
local mug_pos = require_visual_module("mug-pos", "scripts/net-game-tourney/mug-pos")
local ui_data = require_visual_module("ui-data", "scripts/net-game-tourney/ui-data")

-- Forward declare
local remember_board_visual_props
local hide_tournament_text
local message_player_safe
local tournament_visual_id
local start_queue_tournament

-- -----------------------------------------------------------------------------
-- Configuration
-- -----------------------------------------------------------------------------

local BRACKET_SIZE = 8
local DEFAULT_MUG_ANIM = (constants and constants.default_mug_anim)
  or "/server/assets/tourney/tourney-board-elements/mug.anim"
local FALLBACK_MUG_TEXTURE = "/server/assets/tourney/npc-navis-testing/mug.png"

-- Last-resort fallback in case you haven't added question/mug.png yet.
-- Change this to any guaranteed-good mug you already have.
local LAST_RESORT_MUG_TEXTURE = "/server/assets/tourney/npc-navis-testing/gutsman/mug.png"
local TOURNAMENT_PVP_HP = 1000
local EZENCOUNTERS_PACKAGE_PATH = "/server/assets/ezlibs-assets/ezencounters/optimized/tournaments.zip"

local TOURNAMENT_DEFAULT_PLAYER_POSITIONS = {
  {0,0,0,0,0,0},
  {0,1,0,0,0,0},
  {0,0,0,0,0,0},
}

local TOURNAMENT_DEFAULT_TILES = {
  {1,1,1,1,1,1},
  {1,1,1,1,1,1},
  {1,1,1,1,1,1},
}

local TOURNAMENT_DEFAULT_TEAMS = {
  {2,2,2,1,1,1},
  {2,2,2,1,1,1},
  {2,2,2,1,1,1},
}

local TOURNAMENT_SINGLE_ENEMY_POSITION = {
  {0,0,0,0,0,0},
  {0,0,0,0,1,0},
  {0,0,0,0,0,0},
}

local function copy_grid(grid)
  local out = {}
  for y, row in ipairs(grid or {}) do
    out[y] = {}
    for x, value in ipairs(row) do
      out[y][x] = value
    end
  end
  return out
end

local RANK_INDEX = {
  ["1"] = 1,
  v1 = 1,
  rank1 = 1,

  ["2"] = 2,
  v2 = 2,
  rank2 = 2,

  ["3"] = 3,
  v3 = 3,
  rank3 = 3,

  ["4"] = 4,
  sp = 4,

  ["5"] = 5,
  ex = 5,

  ["6"] = 6,
  rare1 = 6,
  r1 = 6,

  ["7"] = 7,
  rare2 = 7,
  r2 = 7,

  ["8"] = 8,
  nm = 8,
  nightmare = 8,
}

local function ez_rank_index(rank)
  local raw = tostring(rank or "1"):lower()
  return RANK_INDEX[raw] or tonumber(raw) or 1
end

local function encounter_npc(def)
  local alias = def.alias or def.enemy or def.name
  local rank = ez_rank_index(def.rank or def.rank_index or "1")

  return {
    id = def.id or (tostring(alias) .. "_r" .. tostring(rank)),
    name = def.display_name or def.name or tostring(alias),
    weight = tonumber(def.weight or 50) or 50,

    path = def.path or EZENCOUNTERS_PACKAGE_PATH,

    mug_texture = def.mug_texture or "/server/assets/tourney/npc-navis-testing/gutsman/mug.png",
    mug_animation = def.mug_animation or DEFAULT_MUG_ANIM,

    encounter_data = {
      path = def.path or EZENCOUNTERS_PACKAGE_PATH,

      enemies = def.enemies or {
        {
          name = alias,
          rank = rank,
          nickname = def.nickname,
          starting_hp = def.starting_hp,
          team = def.team,
          facing = def.facing,
        }
      },

      positions = def.positions or copy_grid(TOURNAMENT_SINGLE_ENEMY_POSITION),
      player_positions = def.player_positions or copy_grid(TOURNAMENT_DEFAULT_PLAYER_POSITIONS),
      tiles = def.tiles or copy_grid(TOURNAMENT_DEFAULT_TILES),
      teams = def.teams or copy_grid(TOURNAMENT_DEFAULT_TEAMS),

      _tournament = true,
      _no_pets = true,
      _no_area_rewards = true,
    },
  }
end

local function direct_zip_npc(def)
  return {
    id = def.id or def.name or def.path,
    name = def.name or def.id or "NPC",
    weight = tonumber(def.weight or 50) or 50,
    path = def.path,
    mug_texture = def.mug_texture,
    mug_animation = def.mug_animation or DEFAULT_MUG_ANIM,
    encounter_data = def.encounter_data,
  }
end

-- Replace/expand this with your server's actual NPC tournament pool.
-- Each NPC may be a direct encounter zip path, or a path + encounter_data table.
-- Direct Async.initiate_encounter() is intentional here so pets are excluded.
local NPC_POOL = {

}

local NPC_POOLS = {
  wcity_rank1 = {
    encounter_npc({
      id = "gutsman1",
      display_name = "GutsMan",
      alias = "GutsManPoN",
      rank = "1",
      weight = 50,
      mug_texture = "/server/assets/tourney/npc-navis-testing/gutsman/mug.png",
    }),

    encounter_npc({
      id = "roll1",
      display_name = "Roll",
      alias = "Roll",
      rank = "1",
      weight = 40,
      mug_texture = "/server/assets/tourney/npc-navis-testing/roll/mug.png",
    }),

    encounter_npc({
      id = "blastman1",
      display_name = "BlastMan",
      alias = "BlastMan",
      rank = "1",
      weight = 60,
      mug_texture = "/server/assets/tourney/npc-navis-testing/blastman/mug.png",
    }),

    encounter_npc({
      id = "cutman1",
      display_name = "CutMan",
      alias = "CutMan",
      rank = "1",
      weight = 40,
      mug_texture = "/server/assets/tourney/npc-navis-testing/cutman/mug.png",
    }),

    encounter_npc({
      id = "fireman1",
      display_name = "FireMan",
      alias = "FireManPoN",
      rank = "1",
      weight = 40,
      mug_texture = "/server/assets/tourney/npc-navis-testing/fireman/mug.png",
    }),

    encounter_npc({
      id = "hatman1",
      display_name = "HatMan",
      alias = "HatMan",
      rank = "1",
      weight = 60,
      mug_texture = "/server/assets/tourney/npc-navis-testing/hatman/mug.png",
    }),

    encounter_npc({
      id = "iceman1",
      display_name = "IceMan",
      alias = "IceManPoN",
      rank = "1",
      weight = 60,
      mug_texture = "/server/assets/tourney/npc-navis-testing/iceman/mug.png",
    }),

    encounter_npc({
      id = "jammingman1",
      display_name = "JammingMan",
      alias = "JammingMan",
      rank = "1",
      weight = 70,
      mug_texture = "/server/assets/tourney/npc-navis-testing/jammingman/mug.png",
    }),

    encounter_npc({
      id = "shademan1",
      display_name = "ShadeMan",
      alias = "ShadeMan",
      rank = "1",
      weight = 80,
      mug_texture = "/server/assets/tourney/npc-navis-testing/shademan/mug.png",
    }),

    encounter_npc({
      id = "shadowman1",
      display_name = "ShadowMan",
      alias = "ShadowManPoN",
      rank = "1",
      weight = 60,
      mug_texture = "/server/assets/tourney/npc-navis-testing/shadowman/mug.png",
    }),

    encounter_npc({
      id = "starman1",
      display_name = "StarMan",
      alias = "StarMan",
      rank = "1",
      weight = 70,
      mug_texture = "/server/assets/tourney/npc-navis-testing/starman/mug.png",
    }),

    encounter_npc({
      id = "shockdos1",
      display_name = "ShockDOS",
      alias = "ShockDOS",
      rank = "1",
      weight = 80,
      mug_texture = "/server/assets/tourney/npc-navis-testing/shockdos/mug.png",
    }),

  },

  open_strong = {
    encounter_npc({
      id = "gutsmanexe3",
      display_name = "GutsMan",
      alias = "GutsManEXE3",
      rank = "sp",
      weight = 50,
      mug_texture = "/server/assets/tourney/npc-navis-testing/gutsman/mug.png",
    }),

    encounter_npc({
      id = "airman",
      display_name = "AirMan",
      alias = "AirMan",
      rank = "sp",
      weight = 70,
      mug_texture = "/server/assets/tourney/npc-navis-testing/airman/mug.png",
    }),

--    encounter_npc({
--      id = "forte4",
--      display_name = "Forte",
--      alias = "ForteEXE4",
--      rank = "1",
--      weight = 100,
--      mug_texture = "/server/assets/tourney/npc-navis-testing/bass/mug.png",
--    }),

    encounter_npc({
      id = "blastman3",
      display_name = "BlastMan",
      alias = "BlastMan",
      rank = "sp",
      weight = 60,
      mug_texture = "/server/assets/tourney/npc-navis-testing/blastman/mug.png",
    }),

    encounter_npc({
      id = "burnerman3",
      display_name = "BurnerMan",
      alias = "BurnerMan",
      rank = "3",
      weight = 70,
      mug_texture = "/server/assets/tourney/npc-navis-testing/burnerman/mug.png",
    }),

    encounter_npc({
      id = "colonel3",
      display_name = "Colonel",
      alias = "Colonel",
      rank = "3",
      weight = 80,
      mug_texture = "/server/assets/tourney/npc-navis-testing/colonel/mug.png",
    }),

    encounter_npc({
      id = "cutman1",
      display_name = "CutMan",
      alias = "CutMan",
      rank = "1",
      weight = 40,
      mug_texture = "/server/assets/tourney/npc-navis-testing/cutman/mug.png",
    }),

    encounter_npc({
      id = "elementman3",
      display_name = "ElementMan",
      alias = "ElementMan",
      rank = "5",
      weight = 50,
      mug_texture = "/server/assets/tourney/npc-navis-testing/elementman/mug.png",
    }),

    encounter_npc({
      id = "fireman3",
      display_name = "FireMan",
      alias = "FireManPoN",
      rank = "sp",
      weight = 40,
      mug_texture = "/server/assets/tourney/npc-navis-testing/fireman/mug.png",
    }),

    encounter_npc({
      id = "hatman3",
      display_name = "HatMan",
      alias = "HatMan",
      rank = "sp",
      weight = 50,
      mug_texture = "/server/assets/tourney/npc-navis-testing/hatman/mug.png",
    }),

    encounter_npc({
      id = "iceman3",
      display_name = "IceMan",
      alias = "IceManPoN",
      rank = "sp",
      weight = 60,
      mug_texture = "/server/assets/tourney/npc-navis-testing/iceman/mug.png",
    }),

    encounter_npc({
      id = "jammingman3",
      display_name = "JammingMan",
      alias = "JammingMan",
      rank = "sp",
      weight = 70,
      mug_texture = "/server/assets/tourney/npc-navis-testing/jammingman/mug.png",
    }),

    encounter_npc({
      id = "protoman3",
      display_name = "ProtoMan",
      alias = "ProtomanPoN",
      rank = "sp",
      weight = 80,
      mug_texture = "/server/assets/tourney/npc-navis-testing/protoman/mug.png",
    }),

    encounter_npc({
      id = "quickman3",
      display_name = "QuickMan",
      alias = "QuickMan",
      rank = "sp",
      weight = 80,
      mug_texture = "/server/assets/tourney/npc-navis-testing/quickman/mug.png",
    }),

    encounter_npc({
      id = "shademan3",
      display_name = "ShadeMan",
      alias = "ShadeMan",
      rank = "sp",
      weight = 80,
      mug_texture = "/server/assets/tourney/npc-navis-testing/shademan/mug.png",
    }),

    encounter_npc({
      id = "shadowman3",
      display_name = "ShadowMan",
      alias = "ShadowManPoN",
      rank = "sp",
      weight = 60,
      mug_texture = "/server/assets/tourney/npc-navis-testing/shadowman/mug.png",
    }),

    encounter_npc({
      id = "starman1",
      display_name = "StarMan",
      alias = "StarMan",
      rank = "sp",
      weight = 60,
      mug_texture = "/server/assets/tourney/npc-navis-testing/starman/mug.png",
    }),

  },
}

local SETTINGS = {
  allow_duplicate_npcs = false,

  -- Manual start should be OFF for event-style tournaments.
  auto_start_when_full = false,
  manual_start_enabled = false,

  announce_to_eliminated_players = true,
  pvp_hp = TOURNAMENT_PVP_HP,

  -- WCity tournament PvP should not force HP.
  -- Open/auto can still force HP unless the board disables it.
  force_pvp_hp = true,
  force_pvp_hp_modes = {
    open = true,
    auto = true,
    wcity = false,
  },

  spectator_cancel_enabled = true,

  -- If a scheduled tournament reaches start time with nobody registered,
  -- fill the entire bracket from the board's normal NPC pool and run it as
  -- an exhibition tournament. NPC-only matches are deliberately slowed down
  -- so spectators can actually watch the live bracket progress.
  npc_only_tournaments_enabled = true,
  npc_only_match_min_seconds = 8,
  npc_only_match_max_seconds = 12,

  -- Wall-clock schedule.
  -- Boards can override these with Tiled properties.
  scheduled_enabled = true,

  -- Default: every hour, on the hour.
  default_schedule_every_hours = 1,
  default_schedule_start_minute = 0,
  default_schedule_start_second = 0,
  default_schedule_hour_offset = 0,

  -- Registration window.
  registration_lead_seconds = 10 * 60,
  five_min_warning_seconds = 5 * 60,

  -- Grace window so a tick slightly after the scheduled second still starts it.
  start_grace_seconds = 10,

  unregister_on_battle_start = true,
  debug = false,
  debug_visual = false,
  debug_scheduler = false,

  -- Tournament battle timeout.
  -- If a PvE battle times out, the human player is disqualified.
  -- If a PvP battle times out, the winner is chosen randomly.
  battle_timeout_seconds = 10 * 60,
}

local function tdebug(...)
  if SETTINGS.debug then
    print(...)
  end
end

local function vdebug(...)
  if SETTINGS.debug_visual or SETTINGS.debug then
    print(...)
  end
end

local function sdebug(...)
  if SETTINGS.debug_scheduler or SETTINGS.debug then
    print(...)
  end
end

local function tournament_announce(message, opts, area_id)
  opts = opts or {}
  opts.id = opts.id or "__tournament_announce"
  opts.loops = opts.loops or 2

  local announcer = rawget(_G, "RaidAnnouncer")
  if announcer and type(announcer.announce) == "function" then
    local ok, err = pcall(announcer.announce, tostring(message or ""), opts, area_id)
    if not ok then
      print("[tournaments][announce] RaidAnnouncer failed: " .. tostring(err))
    end
    return ok
  end

  print("[tournaments][announce] " .. tostring(message or ""))
  return false
end

local VISUALS = {
  enabled = true,
  show_seconds = 2.0,
  fade_seconds = 0.3,
  background_key = "red_orange_bn4",
  music = "/server/assets/tourney/music/bbn4_tournament_announcement.ogg",
  mug_scale = 1.0,

  -- Rewrite-style result reveal timing.
  transition_before_seconds = 2.0,
  path_reveal_seconds = 0.6,
  loser_reveal_seconds = 0.0,
  squash_step_seconds = 0.05,
  after_squash_seconds = 0.3,
  after_unsquash_seconds = 0.3,
  between_matches_seconds = 0.5,
  transition_after_seconds = 2.0,
}

local TOURNEY_TEXT = {
  box_id = "TOURNEY_TEXTBOX",

  -- These are mostly fallback values when backdrop exists
  x = 10,
  y = 260,
  width = 220,
  height = 56,

  font = "THICK_BLACK",
  scale = 2.0,
  z = 250,
  speed = 80,
  auto_advance_seconds = 3.0,

  -- Force the text wrapper to use more of the visual width.
  -- Tune this between 20 and 26 if needed.
  max_chars_per_line = 24,

  backdrop = {
    style = "textbox_panel",
    x = 0,
    y = 260,
    width = 240,
    height = 72,
    padding_x = 14,
    padding_y = -20,
    max_lines = 2,
    open_seconds = 0.12,
    close_seconds = 0.12,
  }
}

local VISUAL_ELEMENT_IDS = {
  -- Legacy/static IDs from older versions.
  -- Dynamic per-tournament IDs are tracked in player_visual_ids.
  "TOURNEY_BOARD_BG",
  "TOURNEY_BOARD_GRID",
  "TOURNEY_BRACKET",
  "TOURNEY_CHAMPION_TOPPER",
  "TOURNEY_TITLE_BANNER",
  "TOURNEY_CROWN_1",
  "TOURNEY_CROWN_2",

  -- Extra legacy IDs from the original tournament repo / older experiments.
  "BOARD BG",
  "BOARD GRID",
  "TOURNEY TREE",
  "BRACKET",
  "CHAMPION TOPPER",
  "TITLE BANNER",
  "CROWN_1",
  "CROWN_2",
}

for i = 1, BRACKET_SIZE do
  VISUAL_ELEMENT_IDS[#VISUAL_ELEMENT_IDS + 1] = "TOURNEY_MUG_FRAME_" .. i
  VISUAL_ELEMENT_IDS[#VISUAL_ELEMENT_IDS + 1] = "TOURNEY_MUG_" .. i

  -- Also clean up original tournament IDs, just in case.
  VISUAL_ELEMENT_IDS[#VISUAL_ELEMENT_IDS + 1] = "MUG_FRAME_" .. i
  VISUAL_ELEMENT_IDS[#VISUAL_ELEMENT_IDS + 1] = "MUG_" .. i
end

-- -----------------------------------------------------------------------------
-- Async helpers
-- -----------------------------------------------------------------------------

local function async(fn)
  local co = coroutine.create(fn)
  return Async.promisify(co)
end

local function await(v)
  return Async.await(v)
end

-- -----------------------------------------------------------------------------
-- Tournament visual asset warmup
-- -----------------------------------------------------------------------------

local function tournament_safe_has_asset(path)
  if not path or path == "" then return false end
  if not Net or not Net.has_asset then return true end

  local ok, res = pcall(Net.has_asset, path)
  return ok and res == true
end

local function tournament_first_existing_asset(...)
  for i = 1, select("#", ...) do
    local path = select(i, ...)
    if path and path ~= "" and tournament_safe_has_asset(path) then
      return path
    end
  end

  return nil
end

local function resolve_tournament_mug_texture(participant)
  local original = participant and participant.mug_texture or nil

  if original and original ~= "" and tournament_safe_has_asset(original) then
    return original
  end

  local fallback = tournament_first_existing_asset(
    FALLBACK_MUG_TEXTURE,
    LAST_RESORT_MUG_TEXTURE
  )

  if original and original ~= "" then
    print(
      "[tournaments][visual] missing mug for "
      .. tostring(participant and participant.name or participant and participant.player_id or "???")
      .. ": "
      .. tostring(original)
      .. "; using fallback "
      .. tostring(fallback)
    )
  end

  return fallback
end

local function tournament_safe_provide(player_id, path)
  if not player_id or not path or path == "" then return end
  if not Net or not Net.provide_asset_for_player then return end

  -- Never provide a missing asset; some server builds can hard-crash on bad paths.
  if not tournament_safe_has_asset(path) then return end

  pcall(Net.provide_asset_for_player, player_id, path)
end

local function tournament_add_asset(out, seen, path)
  if not path or path == "" then return end
  if seen[path] then return end

  seen[path] = true
  out[#out + 1] = path
end

local function tournament_collect_visual_assets()
  local assets = {}
  local seen = {}

  local function add(path)
    tournament_add_asset(assets, seen, path)
  end

  -- Board background variants.
  if constants and constants.bracket_background_path then
    for _, bg in pairs(constants.bracket_background_path) do
      add(bg.gradient_texture)
      add(bg.grid_texture)
    end
  end

  -- Board animations.
  if constants then
    add(constants.default_background_anim_path_bn4)
    add(constants.default_grid_anim_path_bn4)
    add(constants.default_bracket_anim_path_bn4)
    add(constants.default_mug_anim)

    -- Brackets / toppers / crowns.
    add(constants.bracket_bm_bn4)
    add(constants.bracket_rs_bn4)

    add(constants.champion_topper_bn4)
    add(constants.champion_topper_bn45)
    add(constants.champion_topper_bn4_anim)
    add(constants.champion_topper_bn45_anim)

    add(constants.crown_texture_path)
    add(constants.crown_anim_path)

    add(constants.title_banner_anim_path)

    for _, texture_path in pairs(constants.title_banner_paths or {}) do
      add(texture_path)
    end

    for _, path_def in pairs(constants.progress_bar_path or {}) do
      add(path_def.texture)
      add(path_def.anim)
    end

    for _, overlay_theme in pairs(constants.progress_bar_overlay or {}) do
      for _, path_def in pairs(overlay_theme or {}) do
        add(path_def.texture)
        add(path_def.anim)
      end
    end
  end

  -- Hardcoded board assets used by draw_tournament_board_for_player().
  add("/server/assets/tourney/tourney-board-elements/mini-mug-frame.png")
  add("/server/assets/tourney/tourney-board-elements/mini-mug-frame.anim")
  -- Fallback participant mug if a player mug asset disappears after disconnect.
  add(FALLBACK_MUG_TEXTURE)
  add(LAST_RESORT_MUG_TEXTURE)
  add(DEFAULT_MUG_ANIM)

  -- Tournament music.
  add(VISUALS.music)

  -- Textbox assets used by TOURNEY_TEXT.backdrop.style = "textbox_panel".
  add("/server/assets/net-games/displayer/textbox.png")
  add("/server/assets/net-games/displayer/textbox.animation")

  -- Known NPC mugshots.
  for _, pool in pairs(NPC_POOLS or {}) do
    for _, npc in ipairs(pool or {}) do
      add(npc.mug_texture)
      add(npc.mug_animation or DEFAULT_MUG_ANIM)
    end
  end

  return assets
end

local function tournament_prewarm_visual_assets(player_id)
  if not player_id then return end

  local assets = tournament_collect_visual_assets()

  for _, path in ipairs(assets) do
    tournament_safe_provide(player_id, path)
  end

  -- Like fishing/dialogue_types: give the client a moment to download, then touch
  -- the key board sprites offscreen so first real draw is more reliable.
  async(function()
    await(Async.sleep(1.0))

    if not Net.is_player(player_id) then return end
    if not games or not games.add_ui_element then return end

    local function prewarm(sprite_id, texture, anim, state)
      if not tournament_safe_has_asset(texture) then return end
      if anim and anim ~= "" and not tournament_safe_has_asset(anim) then return end

      pcall(
        games.add_ui_element,
        sprite_id,
        player_id,
        texture,
        anim or "",
        state or "UI",
        -1000,
        -1000,
        0,
        2.0,
        2.0
      )
    end

    -- One of each reusable board element.
    if constants and constants.bracket_background_path then
      for key, bg in pairs(constants.bracket_background_path) do
        prewarm("__tourney_pre_bg_" .. tostring(key), bg.gradient_texture, constants.default_background_anim_path_bn4, "BG")
        prewarm("__tourney_pre_grid_" .. tostring(key), bg.grid_texture, constants.default_grid_anim_path_bn4, "idle_ui")
      end
    end

    if constants then
      prewarm("__tourney_pre_bracket_bm", constants.bracket_bm_bn4, constants.default_bracket_anim_path_bn4, "UI")
      prewarm("__tourney_pre_bracket_rs", constants.bracket_rs_bn4, constants.default_bracket_anim_path_bn4, "UI")

      prewarm("__tourney_pre_topper_bn4", constants.champion_topper_bn4, constants.champion_topper_bn4_anim, "UI")
      prewarm("__tourney_pre_topper_bn45", constants.champion_topper_bn45, constants.champion_topper_bn45_anim, "UI")

      prewarm("__tourney_pre_crown", constants.crown_texture_path, constants.crown_anim_path, "INACTIVE")

      if constants.progress_bar_path then
        prewarm("__tourney_pre_path_bottom", constants.progress_bar_path.bottom_tier.texture, constants.progress_bar_path.bottom_tier.anim, "l1_move")
        prewarm("__tourney_pre_path_middle", constants.progress_bar_path.middle_tier.texture, constants.progress_bar_path.middle_tier.anim, "l2_move")
        prewarm("__tourney_pre_path_top", constants.progress_bar_path.top_tier.texture, constants.progress_bar_path.top_tier.anim, "l3_move")
      end

      local blue = constants.progress_bar_overlay and constants.progress_bar_overlay.blue_moon
      if blue then
        prewarm("__tourney_pre_overlay_bottom", blue.bottom_tier.texture, blue.bottom_tier.anim, "L1_MOVE")
        prewarm("__tourney_pre_overlay_middle", blue.middle_tier.texture, blue.middle_tier.anim, "L2_MOVE")
        prewarm("__tourney_pre_overlay_top", blue.top_tier.texture, blue.top_tier.anim, "L3_MOVE")
      end
    end

    prewarm(
      "__tourney_pre_mug_frame",
      "/server/assets/tourney/tourney-board-elements/mini-mug-frame.png",
      "/server/assets/tourney/tourney-board-elements/mini-mug-frame.anim",
      "ACTIVE"
    )

    local default_title_texture = constants
      and constants.title_banner_paths
      and constants.title_banner_paths[constants.title_banner_default or "free-tourney"]

    if default_title_texture then
      prewarm(
        "__tourney_pre_title_banner",
        default_title_texture,
        constants.title_banner_anim_path,
        constants.title_banner_state or "TITLE"
      )
    end

    prewarm(
      "__tourney_pre_textbox",
      "/server/assets/net-games/displayer/textbox.png",
      "/server/assets/net-games/displayer/textbox.animation",
      "OPEN_IDLE"
    )

    _G.__TOURNEY_VISUAL_PREWARM_DONE = _G.__TOURNEY_VISUAL_PREWARM_DONE or {}
    _G.__TOURNEY_VISUAL_PREWARM_DONE[player_id] = true
  end)
end

if not _G.__TOURNEY_VISUAL_WARMUP_HOOKED then
  _G.__TOURNEY_VISUAL_WARMUP_HOOKED = true

  Net:on("player_join", function(event)
    local pid = event.player_id
    if not pid then return end
    tournament_prewarm_visual_assets(pid)
  end)
end

local function await_with_timeout(promise, timeout_seconds)
  return async(function()
    local completed = false
    local value = nil

    if not promise or not promise.and_then then
      return {
        timed_out = false,
        value = nil,
      }
    end

    promise.and_then(function(result)
      value = result
      completed = true
    end)

    timeout_seconds = tonumber(timeout_seconds or 0) or 0

    if timeout_seconds <= 0 then
      while not completed do
        await(Async.sleep(0.25))
      end

      return {
        timed_out = false,
        value = value,
      }
    end

    local elapsed = 0

    while not completed and elapsed < timeout_seconds do
      local step = math.min(1.0, timeout_seconds - elapsed)
      await(Async.sleep(step))
      elapsed = elapsed + step
    end

    return {
      timed_out = not completed,
      value = value,
    }
  end)
end

local function get_tournament_battle_timeout(tournament)
  return tonumber(
    tournament and tournament.battle_timeout_seconds
      or SETTINGS.battle_timeout_seconds
      or 600
  ) or 600
end

-- -----------------------------------------------------------------------------
-- State
-- -----------------------------------------------------------------------------

local board_queues = {}
local active_tournaments = {}
local player_to_queue = {}
local player_to_tournament = {}
local disconnected_players = {}
local next_tournament_id = 1
local spectator_prompt_open = {}
local player_visual_ids = {}

-- Each async tournament-board presentation captures the player's current visual
-- epoch. Disconnecting (or explicitly invalidating that player's board) bumps the
-- epoch so any coroutine that wakes up later knows it must stop before touching
-- native player sprite APIs. This matters because a Rust-side panic cannot be
-- contained by Lua pcall().
local player_visual_epoch = {}

local function current_player_visual_epoch(player_id)
  return tonumber(player_visual_epoch[player_id] or 0) or 0
end

local function invalidate_player_visual_jobs(player_id)
  player_visual_epoch[player_id] = current_player_visual_epoch(player_id) + 1
end

local function tournament_visual_job_is_valid(player_id, expected_epoch)
  if not player_id or not Net.is_player(player_id) then
    return false
  end

  if expected_epoch ~= nil
    and current_player_visual_epoch(player_id) ~= expected_epoch
  then
    return false
  end

  return true
end

local scheduler_clock = 0
local next_scheduled_start_at = nil

-- Live MenuAPI lobby/list state and persistent bracket viewers.
local TourneyUX = {
  menu_views = {},
  menu_last_refresh_second = nil,
  live_board_viewers = {},
  spectator_cancel_guard_until = {},
}

-- -----------------------------------------------------------------------------
-- Small table helpers
-- -----------------------------------------------------------------------------

local function shallow_copy(t)
  local out = {}
  for k, v in pairs(t or {}) do
    out[k] = v
  end
  return out
end

local function list_copy(arr)
  local out = {}
  for i, v in ipairs(arr or {}) do
    out[i] = v
  end
  return out
end

local function shuffle_in_place(arr)
  for i = #arr, 2, -1 do
    local j = math.random(i)
    arr[i], arr[j] = arr[j], arr[i]
  end
  return arr
end

local function remove_index(arr, index)
  if index then
    table.remove(arr, index)
  end
end

local function format_duration(seconds)
  seconds = math.max(0, math.ceil(tonumber(seconds or 0) or 0))
  local minutes = math.floor(seconds / 60)
  local secs = seconds % 60

  if minutes > 0 then
    return string.format("%dm %02ds", minutes, secs)
  end

  return tostring(secs) .. "s"
end

local function format_minutes_only(seconds)
  seconds = math.max(0, tonumber(seconds or 0) or 0)
  return tostring(math.ceil(seconds / 60)) .. "m"
end

-- Lobby countdowns stay minute-only until the final minute. During the
-- last minute, expose only 5-second buckets so MenuAPI does not redraw
-- every second (important while the current client shows a loading spinner
-- for sprite/UI updates).
local function format_lobby_countdown(seconds)
  seconds = math.max(0, tonumber(seconds or 0) or 0)

  if seconds >= 60 then
    return tostring(math.ceil(seconds / 60)) .. "m"
  end

  if seconds <= 0 then
    return "0s"
  end

  -- Keep displaying 1m until the first true 5-second boundary.
  -- Then: 55..51 => 55s, 50..46 => 50s, ... 5..1 => 5s.
  if seconds > 55 then
    return "1m"
  end

  local bucket = math.ceil(seconds / 5) * 5
  bucket = math.max(5, bucket)
  return tostring(bucket) .. "s"
end

local function clamp_int(value, fallback, min_value, max_value)
  local n = math.floor(tonumber(value) or fallback or 0)

  if min_value ~= nil and n < min_value then
    n = min_value
  end

  if max_value ~= nil and n > max_value then
    n = max_value
  end

  return n
end

local function get_queue_schedule_period(queue)
  local hours = tonumber(
    queue and queue.schedule_every_hours
      or SETTINGS.default_schedule_every_hours
      or 1
  ) or 1

  if hours <= 0 then
    hours = 1
  end

  return math.max(60, math.floor(hours * 60 * 60))
end

local function get_queue_schedule_times(queue, now)
  now = math.floor(tonumber(now or os.time()) or os.time())

  local period = get_queue_schedule_period(queue)
  local period_hours = math.max(1, math.floor(period / 3600))

  local hour_offset = clamp_int(
    queue and queue.schedule_hour_offset
      or SETTINGS.default_schedule_hour_offset
      or 0,
    0,
    0,
    23
  ) % period_hours

  local minute = clamp_int(
    queue and queue.schedule_start_minute
      or SETTINGS.default_schedule_start_minute
      or 0,
    0,
    0,
    59
  )

  local second = clamp_int(
    queue and queue.schedule_start_second
      or SETTINGS.default_schedule_start_second
      or 0,
    0,
    0,
    59
  )

  local date = os.date("*t", now)
  local day_start = os.time({
    year = date.year,
    month = date.month,
    day = date.day,
    hour = 0,
    min = 0,
    sec = 0,
  })

  local first_today = day_start + (hour_offset * 3600) + (minute * 60) + second

  -- Previous scheduled start at or before now.
  local prev = first_today
  if prev > now then
    prev = prev - period
  end

  local steps = math.floor((now - prev) / period)
  prev = prev + (steps * period)

  if prev > now then
    prev = prev - period
  end

  local next_start = prev + period
  return prev, next_start, period
end

local function seconds_until_next_scheduled_tournament(queue)
  if SETTINGS.scheduled_enabled ~= true then
    return 0
  end

  if not queue then
    return 0
  end

  local _, next_start = get_queue_schedule_times(queue, os.time())
  return math.max(0, next_start - os.time())
end

local function tournament_registration_is_open(queue)
  if SETTINGS.scheduled_enabled ~= true then
    return true
  end

  local lead = tonumber(
    queue and queue.registration_lead_seconds
      or SETTINGS.registration_lead_seconds
      or 600
  ) or 600

  return seconds_until_next_scheduled_tournament(queue) <= lead
end

local function find_participant_index(participants, player_id)
  for i, participant in ipairs(participants or {}) do
    if participant.kind == "player" and participant.player_id == player_id then
      return i
    end
  end
  return nil
end

local function board_key(area_id, object_id)
  return tostring(area_id) .. ":" .. tostring(object_id)
end

local function is_tournament_object(object)
  return object and (object.type == "Tournament Board" or object.class == "Tournament Board")
end

local function to_number_or(value, fallback)
  local n = tonumber(value)
  if n == nil then return fallback end
  return n
end

local function to_bool_or(value, fallback)
  if value == nil then
    return fallback
  end

  if type(value) == "boolean" then
    return value
  end

  local s = tostring(value):lower()
  if s == "true" or s == "yes" or s == "1" or s == "on" then
    return true
  end

  if s == "false" or s == "no" or s == "0" or s == "off" then
    return false
  end

  return fallback
end
local function remember_board_tournament_props(queue, object)
  if not queue or not object then return end

  local props = object.custom_properties or {}

  queue.npc_pool_key =
    props["Tournament NPC Pool"]
    or props["NPC Pool"]
    or queue.npc_pool_key
    or "default"

  queue.pvp_mode =
    props["Tournament PVP Mode"]
    or props["PVP Mode"]
    or queue.pvp_mode
    or "auto"

  queue.force_pvp_hp = to_bool_or(
    props["Tournament Force PVP HP"]
      or props["Force PVP HP"],
    queue.force_pvp_hp
  )

  queue.schedule_every_hours = to_number_or(
    props["Tournament Every Hours"]
      or props["Every Hours"]
      or props["Schedule Every Hours"],
    queue.schedule_every_hours or SETTINGS.default_schedule_every_hours
  )

  queue.schedule_hour_offset = to_number_or(
    props["Tournament Hour Offset"]
      or props["Schedule Hour Offset"]
      or props["Hour Offset"],
    queue.schedule_hour_offset or SETTINGS.default_schedule_hour_offset
  )

  queue.schedule_start_minute = to_number_or(
    props["Tournament Start Minute"]
      or props["Start Minute"],
    queue.schedule_start_minute or SETTINGS.default_schedule_start_minute
  )

  queue.schedule_start_second = to_number_or(
    props["Tournament Start Second"]
      or props["Start Second"],
    queue.schedule_start_second or SETTINGS.default_schedule_start_second
  )

  queue.registration_lead_seconds = to_number_or(
    props["Registration Lead Seconds"]
      or props["Tournament Registration Seconds"]
      or props["Registration Seconds"],
    queue.registration_lead_seconds or SETTINGS.registration_lead_seconds
  )

  queue.battle_timeout_seconds = to_number_or(
    props["Tournament Battle Timeout Seconds"]
      or props["Battle Timeout Seconds"]
      or props["Match Timeout Seconds"],
    queue.battle_timeout_seconds or SETTINGS.battle_timeout_seconds
  )

  queue.winner_gp_reward = math.max(0, math.floor(to_number_or(
    props["Tournament GP Reward"]
      or props["GP Reward"]
      or props["Winner GP"],
    queue.winner_gp_reward or 0
  )))

  queue.winner_money_reward = math.max(0, math.floor(to_number_or(
    props["Tournament Money Reward"]
      or props["Money Reward"]
      or props["Winner Money"],
    queue.winner_money_reward or 0
  )))

  queue.deduct_opposing_team_gp = to_bool_or(
    props["Tournament GP Stakes"]
      or props["Deduct Opposing Team GP"]
      or props["GP Stakes"],
    queue.deduct_opposing_team_gp or false
  )
end

local function get_board_queue(area_id, object_id, object)
  local key = board_key(area_id, object_id)
  local queue = board_queues[key]

  if not queue then
    local props = (object and object.custom_properties) or {}
    queue = {
      key = key,
      area_id = area_id,
      object_id = object_id,
      name = props["Tournament Name"] or props["Name"] or "WCity Tournament",
      status = "waiting",
      host_player_id = nil,
      participants = {},
      active_tournament_id = nil,
    }
    board_queues[key] = queue
  end

  remember_board_tournament_props(queue, object)
  remember_board_visual_props(queue, object)

  return queue
end

local function scan_tournament_boards_for_scheduler()
  if not TableUtils or not TableUtils.GetAllTiledObjOfXType then
    return 0
  end

  local created = 0

  for _, area_id in ipairs(Net.list_areas() or {}) do
    local ok, boards = pcall(TableUtils.GetAllTiledObjOfXType, area_id, "Tournament Board")

    if ok and type(boards) == "table" then
      for _, object in ipairs(boards) do
        if object and object.id then
          local key = board_key(area_id, object.id)

          if not board_queues[key] then
            get_board_queue(area_id, object.id, object)
            created = created + 1
          else
            -- Refresh props in case the map/object data became available after initial scan.
            get_board_queue(area_id, object.id, object)
          end
        end
      end
    end
  end

  if created > 0 then
    print("[tournaments][scheduler] initialized " .. tostring(created) .. " tournament board queue(s)")
  end

  return created
end

local function get_npc_pool_for_queue(queue)
  local key = queue and queue.npc_pool_key or "default"
  return NPC_POOLS[key] or NPC_POOLS.default or NPC_POOL
end

-- -----------------------------------------------------------------------------
-- Participant helpers
-- -----------------------------------------------------------------------------

local function player_display_name(player_id)
  if Net.is_player(player_id) then
    return Net.get_player_name(player_id) or tostring(player_id)
  end
  return tostring(player_id)
end

local function make_player_participant(player_id)
  local mug = nil
  if Net.get_player_mugshot then
    mug = Net.get_player_mugshot(player_id)
  end

  return {
    kind = "player",
    id = "player:" .. tostring(player_id),
    player_id = player_id,
    name = player_display_name(player_id),
    mug_texture = mug and mug.texture_path or nil,
    -- Do NOT use the player's own mug.animation here.
    -- Player mug animations do not necessarily have the tournament "UI" state.
    mug_animation = DEFAULT_MUG_ANIM,
    eliminated = false,
    disconnected = false,
    wants_updates = true,
    spectating = false,
  }
end

local function make_npc_participant(npc_def, serial)
  local id_base = npc_def.id or npc_def.name or npc_def.path or "npc"
  return {
    kind = "npc",
    id = "npc:" .. tostring(id_base) .. ":" .. tostring(serial),
    npc_id = tostring(id_base),
    name = npc_def.name or tostring(id_base),
    weight = tonumber(npc_def.weight or 50) or 50,
    path = npc_def.path,
    encounter_data = npc_def.encounter_data,
    mug_texture = npc_def.mug_texture,
    mug_animation = npc_def.mug_animation or DEFAULT_MUG_ANIM,
    eliminated = false,
    disconnected = false,
  }
end

local function participant_name(participant)
  if not participant then
    return "???"
  end
  if participant.kind == "player" then
    return player_display_name(participant.player_id)
  end
  return participant.name or participant.npc_id or "NPC"
end

local function is_human(participant)
  return participant and participant.kind == "player"
end

local function is_connected_human(participant)
  return is_human(participant)
    and Net.is_player(participant.player_id)
    and not disconnected_players[participant.player_id]
end

local function participant_wants_tournament_updates(participant)
  return participant
    and participant.kind == "player"
    and participant.wants_updates ~= false
    and Net.is_player(participant.player_id)
end

local function get_player_participant(tournament, player_id)
  if not tournament then return nil end

  for _, participant in ipairs(tournament.all_participants or tournament.participants or {}) do
    if participant.kind == "player" and participant.player_id == player_id then
      return participant
    end
  end

  if tournament.spectators and tournament.spectators[player_id] then
    return tournament.spectators[player_id]
  end

  return nil
end

local function participant_is_in_match(participant, match)
  if not participant or not match then return false end

  return (match.player1 and match.player1.id == participant.id)
    or (match.player2 and match.player2.id == participant.id)
end

local function participant_is_in_any_active_match(tournament, participant)
  if not tournament or not participant then
    return false
  end

  for _, active_match in pairs(tournament.active_spectator_matches or {}) do
    if participant_is_in_match(participant, active_match) then
      return true
    end
  end

  return false
end

local function for_each_tournament_viewer(tournament, cb)
  if not tournament or type(cb) ~= "function" then return end

  local seen = {}

  for _, participant in ipairs(tournament.all_participants or tournament.participants or {}) do
    if participant_wants_tournament_updates(participant) then
      seen[participant.player_id] = true
      cb(participant)
    end
  end

  for player_id, spectator in pairs(tournament.spectators or {}) do
    if not seen[player_id] and participant_wants_tournament_updates(spectator) then
      cb(spectator)
    end
  end
end

-- -----------------------------------------------------------------------------
-- Tournament board visuals
-- -----------------------------------------------------------------------------

local printed_visuals_missing = false
local tournament_input_locked = {}

local function set_player_tournament_input_locked(player_id, locked)
  if not player_id or not Net.is_player(player_id) then
    tournament_input_locked[player_id] = nil
    return
  end

  if locked then
    tournament_input_locked[player_id] = true
    pcall(Net.lock_player_input, player_id)
  else
    tournament_input_locked[player_id] = nil
    pcall(Net.unlock_player_input, player_id)
  end
end

local function set_tournament_input_locked(tournament, locked)
  if not tournament then return end

  for _, participant in ipairs(tournament.all_participants or tournament.participants or {}) do
    if participant.kind == "player" then
      set_player_tournament_input_locked(participant.player_id, locked)
    end
  end
end

local function visuals_available()
  if not VISUALS.enabled then
    return false
  end

  local missing = {}

  if not games then missing[#missing + 1] = "scripts/net-games/main" end
  if not constants then missing[#missing + 1] = "scripts/net-game-tourney/constants" end
  if not mug_pos then missing[#missing + 1] = "scripts/net-game-tourney/mug-pos" end
  if not ui_data then missing[#missing + 1] = "scripts/net-game-tourney/ui-data" end
  if not games or not games.add_ui_element then missing[#missing + 1] = "games.add_ui_element" end

  if #missing > 0 then
    if not printed_visuals_missing then
      printed_visuals_missing = true
      print("[tournaments][visual] disabled, missing: " .. table.concat(missing, ", "))
    end
    return false
  end

  return true
end

local function get_board_background(queue_or_tournament)
  local key = (queue_or_tournament and queue_or_tournament.board_background)
    or VISUALS.background_key

  local backgrounds = constants and constants.bracket_background_path or nil
  if backgrounds then
    return backgrounds[key] or backgrounds.red_orange_bn4
  end

  return nil
end

local function normalize_tournament_title_banner(value)
  local key = tostring(value or ""):lower()

  key = key:gsub("^%s+", "")
  key = key:gsub("%s+$", "")
  key = key:gsub("[_%s]+", "-")

  local paths = constants and constants.title_banner_paths or nil

  if paths and paths[key] then
    return key
  end

  return (constants and constants.title_banner_default) or "free-tourney"
end

local function get_tournament_title_banner_texture(tournament)
  local paths = constants and constants.title_banner_paths or nil
  if not paths then
    return nil
  end

  local key = normalize_tournament_title_banner(
    tournament and tournament.title_banner_key
  )

  return paths[key]
    or paths[(constants and constants.title_banner_default) or "free-tourney"]
end

function remember_board_visual_props(queue, object)
  if not queue or not object then return end

  local props = object.custom_properties or {}
  queue.board_background =
    props["Board Background"]
    or props["Tournament Background"]
    or VISUALS.background_key

  queue.title_banner_key = normalize_tournament_title_banner(
    props["Tournament Title"]
    or props["Tournament Title Banner"]
    or props["Title Banner"]
    or queue.title_banner_key
  )
end
function tournament_visual_id(tournament, base_id)
  local tid = tournament and tournament.id or "no_tournament"
  return "TOURNEY_" .. tostring(tid) .. "_" .. tostring(base_id)
end

local function erase_tournament_board(player_id)
  -- Never call native sprite APIs after the player is gone. Just forget our Lua
  -- bookkeeping; the client is already disconnected and needs no visual cleanup.
  if not player_id or not Net.is_player(player_id) then
    player_visual_ids[player_id] = {}
    return
  end

  if not games or not games.remove_ui_element then
    player_visual_ids[player_id] = {}
    return
  end

  local ids = {}

  -- New dynamic IDs drawn by this tournament visual system.
  for id in pairs(player_visual_ids[player_id] or {}) do
    ids[#ids + 1] = id
  end

  -- Legacy/static IDs from earlier versions, useful for cleaning up stale cache.
  for _, id in ipairs(VISUAL_ELEMENT_IDS) do
    ids[#ids + 1] = id
  end

  for _, id in ipairs(ids) do
    pcall(games.remove_ui_element, id, player_id)

    -- Extra cleanup if your server supports sprite deallocation.
    -- This helps avoid old texture allocations sticking around.
    if Net.player_dealloc_sprite then
      pcall(Net.player_dealloc_sprite, player_id, id)
    end
  end

  player_visual_ids[player_id] = {}
end

local tournament_area_music = {}

local function safe_get_area_song(area_id)
  if not area_id or not Net.get_song then
    return nil
  end

  local ok, song = pcall(Net.get_song, area_id)
  if ok then
    return song
  end

  return nil
end

local function acquire_tournament_music(area_id)
  if not area_id or not VISUALS.music then
    return nil
  end

  local state = tournament_area_music[area_id]

  if not state then
    state = {
      original_song = safe_get_area_song(area_id),
      original_name = Net.get_area_name and Net.get_area_name(area_id) or nil,
      users = 0,
    }

    tournament_area_music[area_id] = state
    pcall(Net.set_song, area_id, VISUALS.music)
    if Net.set_area_name then
      pcall(Net.set_area_name, area_id, "Tournament")
    end
  end

  state.users = state.users + 1
  return area_id
end

local function release_tournament_music(area_id)
  if not area_id then
    return
  end

  local state = tournament_area_music[area_id]
  if not state then
    return
  end

  state.users = state.users - 1

  if state.users > 0 then
    return
  end

  tournament_area_music[area_id] = nil

  if state.original_song then
    pcall(Net.set_song, area_id, state.original_song)
  end

  if state.original_name and Net.set_area_name then
    pcall(Net.set_area_name, area_id, state.original_name)
  end
end

local function draw_ui(player_id, id, texture, anim, state, pos, sx, sy)
  if not player_id or not Net.is_player(player_id) then
    return false
  end

  if not texture or not pos then
    vdebug("[tournaments][visual] skipped draw: missing texture/pos for " .. tostring(id))
    return false
  end

  if not games or not games.add_ui_element then
    vdebug("[tournaments][visual] skipped draw: games.add_ui_element unavailable for " .. tostring(id))
    return false
  end

  local x = pos.x or 0
  local y = pos.y or 0
  local z = pos.z or 0
  anim = anim or ""
  state = state or "UI"

  local ok, err = pcall(
    games.add_ui_element,
    id,
    player_id,
    texture,
    anim,
    state,
    x,
    y,
    z,
    sx,
    sy
  )

  if ok then
    player_visual_ids[player_id] = player_visual_ids[player_id] or {}
    player_visual_ids[player_id][id] = true

    vdebug("[tournaments][visual] drew " .. tostring(id) .. " texture=" .. tostring(texture) .. " anim=" .. tostring(anim) .. " state=" .. tostring(state))
    return true
  end

  vdebug(
    "[tournaments][visual] draw failed id=" .. tostring(id)
    .. " texture=" .. tostring(texture)
    .. " anim=" .. tostring(anim)
    .. " state=" .. tostring(state)
    .. " err=" .. tostring(err)
  )

  -- Fallback: try drawing the PNG as a static sprite.
  if anim ~= "" then
    local ok_static, err_static = pcall(
      games.add_ui_element,
      id,
      player_id,
      texture,
      "",
      "",
      x,
      y,
      z,
      sx,
      sy
    )

    if ok_static then
      player_visual_ids[player_id] = player_visual_ids[player_id] or {}
      player_visual_ids[player_id][id] = true

      vdebug("[tournaments][visual] static fallback drew " .. tostring(id))
      return true
    end

    vdebug("[tournaments][visual] static fallback failed id=" .. tostring(id) .. " err=" .. tostring(err_static))
  end

  return false
end

local function add_participant_mugshot(player_id, tournament, index, participant, pos)
  if not participant or not pos then return end

  local mug_texture = resolve_tournament_mug_texture(participant)
  if not mug_texture or mug_texture == "" then
    return
  end

  local frame_pos = {
    x = pos.x,
    y = pos.y,
    z = (pos.z or 0) + 1,
  }

  draw_ui(
    player_id,
    tournament_visual_id(tournament, "MUG_FRAME_" .. index),
    constants.mug_frame_texture_path or "/server/assets/tourney/tourney-board-elements/mini-mug-frame.png",
    constants.mug_frame_anim_path or "/server/assets/tourney/tourney-board-elements/mini-mug-frame.anim",
    "ACTIVE",
    frame_pos,
    2.0,
    2.0
  )

  local mug_id = tournament_visual_id(tournament, "MUG_" .. index)
  local mug_ok = draw_ui(
    player_id,
    mug_id,
    mug_texture,
    participant.mug_animation or DEFAULT_MUG_ANIM,
    "UI",
    pos,
    VISUALS.mug_scale,
    VISUALS.mug_scale
  )

  if not mug_ok and mug_texture ~= FALLBACK_MUG_TEXTURE then
    local fallback = tournament_first_existing_asset(
      FALLBACK_MUG_TEXTURE,
      LAST_RESORT_MUG_TEXTURE
    )

    if fallback then
      draw_ui(
        player_id,
        mug_id,
        fallback,
        DEFAULT_MUG_ANIM,
        "UI",
        pos,
        VISUALS.mug_scale,
        VISUALS.mug_scale
      )
    end
  end
end

local function remove_participant_mugshot(player_id, tournament, index)
  if not player_id or not Net.is_player(player_id) then return end
  if not games or not games.remove_ui_element then return end

  local frame_id = tournament_visual_id(tournament, "MUG_FRAME_" .. index)
  local mug_id = tournament_visual_id(tournament, "MUG_" .. index)

  pcall(games.remove_ui_element, frame_id, player_id)
  pcall(games.remove_ui_element, mug_id, player_id)

  if player_visual_ids[player_id] then
    player_visual_ids[player_id][frame_id] = nil
    player_visual_ids[player_id][mug_id] = nil
  end
end

local function participant_original_index(tournament, participant)
  if not tournament or not participant then return nil end

  for i, original in ipairs(tournament.all_participants or {}) do
    if original.id == participant.id then
      return i
    end
  end

  return nil
end

local function initial_visual_positions(tournament)
  local positions = {}

  for i = 1, #(tournament.all_participants or {}) do
    if mug_pos.initial[i] then
      positions[i] = mug_pos.initial[i]
    end
  end

  return positions
end

local function positions_after_round(tournament, round_number)
  local positions = initial_visual_positions(tournament)

  local function place_result(result, target_pos)
    if result and result.winner and target_pos then
      local winner_index = participant_original_index(tournament, result.winner)
      if winner_index then
        positions[winner_index] = target_pos
      end
    end
  end

  if round_number >= 1 then
    for _, result in pairs(tournament.round_results[1] or {}) do
      local match_index = tonumber(result and result.match)
      if match_index then
        place_result(result, mug_pos.round1_winners[match_index])
      end
    end
  end

  if round_number >= 2 then
    for _, result in pairs(tournament.round_results[2] or {}) do
      local match_index = tonumber(result and result.match)
      if match_index then
        place_result(result, mug_pos.round2_winners[match_index])
      end
    end
  end

  if round_number >= 3 then
    local final_result = (tournament.round_results[3] or {})[1]
    place_result(final_result, mug_pos.champion[1])
  end

  return positions
end

local function get_visual_positions(tournament, mode)
  if mode == "initial" then
    return initial_visual_positions(tournament)
  end

  if mode == "after_round" then
    return positions_after_round(tournament, tournament.current_round or 0)
  end

  if mode == "champion" then
    return positions_after_round(tournament, 3)
  end

  return positions_after_round(tournament, math.max(0, (tournament.current_round or 1) - 1))
end

local function positions_differ(a, b)
  if not a or not b then return false end
  return a.x ~= b.x or a.y ~= b.y or a.z ~= b.z
end

local function collect_winner_movements(tournament, current_positions, new_positions)
  local moves = {}
  local round = tournament and tournament.current_round or 0
  local results = tournament and tournament.round_results and tournament.round_results[round] or {}

  -- Use match order so the reveal follows bracket order.
  for match_index = 1, #results do
    local result = results[match_index]

    if result and result.winner then
      local participant_index = participant_original_index(tournament, result.winner)
      local from_pos = participant_index and current_positions[participant_index] or nil
      local to_pos = participant_index and new_positions[participant_index] or nil

      if participant_index and positions_differ(from_pos, to_pos) then
        moves[#moves + 1] = {
          index = participant_index,
          participant = result.winner,
          result = result,
          match_index = tonumber(result.match) or match_index,
          from_pos = from_pos,
          to_pos = to_pos,
        }
      end
    end
  end

  return moves
end

local function progress_tier_info(round_number)
  if round_number == 1 then
    return "bottom_tier", "l1_move", "r1_move", "ROUND1_PATH_"
  elseif round_number == 2 then
    return "middle_tier", "l2_move", "r2_move", "ROUND2_PATH_"
  elseif round_number == 3 then
    return "top_tier", "l3_move", "r3_move", "ROUND3_PATH_"
  end

  return nil
end

local function progress_bar_index(round_number, match_index, result)
  if not result or not result.winner then return nil end

  local winner_is_player1 = result.player1
    and result.winner.id == result.player1.id

  if round_number == 1 or round_number == 2 then
    local base = (match_index - 1) * 2
    return winner_is_player1 and (base + 1) or (base + 2), winner_is_player1
  elseif round_number == 3 then
    return winner_is_player1 and 1 or 2, winner_is_player1
  end

  return nil
end

local function draw_result_path(player_id, tournament, round_number, match_index, result, with_overlay)
  if not constants or not ui_data or not result or not result.winner then
    return nil
  end
  local tier, left_state, right_state, id_prefix = progress_tier_info(round_number)
  if not tier then return nil end

  local index, winner_is_player1 = progress_bar_index(round_number, match_index, result)
  if not index then return nil end

  local base_def = constants.progress_bar_path and constants.progress_bar_path[tier]
  local overlay_def = constants.progress_bar_overlay
    and constants.progress_bar_overlay.blue_moon
    and constants.progress_bar_overlay.blue_moon[tier]

  local base_pos = ui_data.progress_bars
    and ui_data.progress_bars[tier]
    and ui_data.progress_bars[tier][index]

  local overlay_pos = ui_data.progress_bar_overlays
    and ui_data.progress_bar_overlays[tier]
    and ui_data.progress_bar_overlays[tier][index]

  if not base_def or not base_pos then
    return nil
  end

  local anim_state = winner_is_player1 and left_state or right_state
  local base_id = tournament_visual_id(tournament, id_prefix .. tostring(index))

  draw_ui(
    player_id,
    base_id,
    base_def.texture,
    base_def.anim,
    anim_state,
    base_pos,
    2.0,
    2.0
  )

  if with_overlay and overlay_def and overlay_pos then
    local overlay_id = base_id .. "_OVERLAY"
    local overlay_anim_state = string.upper(anim_state)

    draw_ui(
      player_id,
      overlay_id,
      overlay_def.texture,
      overlay_def.anim,
      overlay_anim_state,
      overlay_pos,
      2.0,
      2.0
    )
    return overlay_id
  end

  return nil
end

local function draw_completed_paths(player_id, tournament, max_round)
  if not player_id or not Net.is_player(player_id) then return end
  max_round = math.max(0, math.min(3, tonumber(max_round or 0) or 0))

  for round_number = 1, max_round do
    local results = tournament.round_results[round_number] or {}
    for match_index = 1, #results do
      local result = results[match_index]
      if result and result.winner then
        draw_result_path(
          player_id,
          tournament,
          round_number,
          tonumber(result.match) or match_index,
          result,
          false
        )
      end
    end
  end
end

local function tint_participant_eliminated(player_id, tournament, participant)
  if not player_id or not Net.is_player(player_id) then return end
  if not participant or not constants or not constants.sepia_properties then return end

  local index = participant_original_index(tournament, participant)
  if not index then return end

  local mug_id = tournament_visual_id(tournament, "MUG_" .. index)
  if games and games.update_ui_element then
    pcall(games.update_ui_element, mug_id, player_id, constants.sepia_properties)
  end
end

local function apply_existing_eliminations(player_id, tournament, mode)
  local current_round = tournament.current_round or 0
  local reveal_current_round = mode ~= "after_round_animated"

  for _, participant in ipairs(tournament.all_participants or {}) do
    if participant.eliminated then
      local eliminated_round = tonumber(participant.eliminated_round or 0) or 0

      -- During the animated result reveal, the current round's losers start in full
      -- color and fade only when their individual matchup is processed.
      if reveal_current_round or eliminated_round < current_round then
        tint_participant_eliminated(player_id, tournament, participant)
      end
    end
  end
end

local function set_participant_vertical_scale(player_id, tournament, index, mug_sy, frame_sy)
  if not player_id or not Net.is_player(player_id) then return end
  if not games or not games.update_ui_element then return end

  local mug_id = tournament_visual_id(tournament, "MUG_" .. index)
  local frame_id = tournament_visual_id(tournament, "MUG_FRAME_" .. index)

  pcall(games.update_ui_element, mug_id, player_id, { sy = mug_sy })
  pcall(games.update_ui_element, frame_id, player_id, { sy = frame_sy })
end

local function squash_participant(player_id, tournament, index, visual_epoch)
  return async(function()
    local mug_steps = { 0.8, 0.6, 0.4, 0.2, 0.0 }
    local frame_steps = { 1.7, 1.3, 0.9, 0.5, 0.0 }

    for i = 1, #mug_steps do
      if not tournament_visual_job_is_valid(player_id, visual_epoch) then
        return false
      end

      set_participant_vertical_scale(
        player_id,
        tournament,
        index,
        mug_steps[i],
        frame_steps[i]
      )

      await(Async.sleep(VISUALS.squash_step_seconds or 0.05))
    end

    return tournament_visual_job_is_valid(player_id, visual_epoch)
  end)
end

local function unsquash_participant(player_id, tournament, index, visual_epoch)
  return async(function()
    local mug_steps = { 0.2, 0.4, 0.6, 0.8, 1.0 }
    local frame_steps = { 0.5, 0.9, 1.3, 1.7, 2.0 }

    for i = 1, #mug_steps do
      if not tournament_visual_job_is_valid(player_id, visual_epoch) then
        return false
      end

      set_participant_vertical_scale(
        player_id,
        tournament,
        index,
        mug_steps[i],
        frame_steps[i]
      )

      await(Async.sleep(VISUALS.squash_step_seconds or 0.05))
    end

    return tournament_visual_job_is_valid(player_id, visual_epoch)
  end)
end

local function move_participant_ui(player_id, tournament, index, to_pos)
  if not player_id or not Net.is_player(player_id) then return end
  if not games or not games.update_ui_element or not to_pos then return end

  local mug_id = tournament_visual_id(tournament, "MUG_" .. index)
  local frame_id = tournament_visual_id(tournament, "MUG_FRAME_" .. index)

  pcall(games.update_ui_element, mug_id, player_id, {
    x = to_pos.x,
    y = to_pos.y,
    z = to_pos.z or 0,
  })

  pcall(games.update_ui_element, frame_id, player_id, {
    x = to_pos.x,
    y = to_pos.y,
    z = (to_pos.z or 0) + 1,
  })
end

local function remove_visual_element(player_id, id)
  if not player_id or not Net.is_player(player_id) then return end
  if not id or not games or not games.remove_ui_element then return end
  pcall(games.remove_ui_element, id, player_id)
  if player_visual_ids[player_id] then
    player_visual_ids[player_id][id] = nil
  end
end

local function animated_board_hold_seconds(tournament, mode)
  if mode ~= "after_round_animated" then
    if mode == "champion" then
      return 3.0
    end
    return VISUALS.show_seconds
  end

  local current_positions = get_visual_positions(tournament, "before_round")
  local new_positions = get_visual_positions(tournament, "after_round")
  local moves = collect_winner_movements(tournament, current_positions, new_positions)

  if #moves == 0 then
    return VISUALS.show_seconds
  end

  local squash_time = (VISUALS.squash_step_seconds or 0.05) * 5
  local per_match = (VISUALS.path_reveal_seconds or 0.6)
    + (VISUALS.loser_reveal_seconds or 0.15)
    + squash_time
    + (VISUALS.after_squash_seconds or 0.3)
    + squash_time
    + (VISUALS.after_unsquash_seconds or 0.3)
    + (VISUALS.between_matches_seconds or 0.5)

  return (VISUALS.transition_before_seconds or 1.0)
    + (#moves * per_match)
    + (VISUALS.transition_after_seconds or 1.5)
end

local function animate_winner_movements(player_id, tournament, moves, visual_epoch)
  return async(function()
    if not tournament_visual_job_is_valid(player_id, visual_epoch) then
      return false
    end

    if not moves or #moves == 0 then
      await(Async.sleep(VISUALS.show_seconds))
      return tournament_visual_job_is_valid(player_id, visual_epoch)
    end

    await(Async.sleep(VISUALS.transition_before_seconds or 1.0))
    if not tournament_visual_job_is_valid(player_id, visual_epoch) then
      return false
    end

    local round_number = tournament.current_round or 0

    for move_index, move in ipairs(moves) do
      if not tournament_visual_job_is_valid(player_id, visual_epoch) then
        return false
      end

      local result = move.result
      local overlay_id = draw_result_path(
        player_id,
        tournament,
        round_number,
        move.match_index or move_index,
        result,
        true
      )

      await(Async.sleep(VISUALS.path_reveal_seconds or 0.6))
      if not tournament_visual_job_is_valid(player_id, visual_epoch) then
        return false
      end

      if result and result.loser then
        tint_participant_eliminated(player_id, tournament, result.loser)
      end

      await(Async.sleep(VISUALS.loser_reveal_seconds or 0.15))
      if not tournament_visual_job_is_valid(player_id, visual_epoch) then
        return false
      end

      await(squash_participant(player_id, tournament, move.index, visual_epoch))
      if not tournament_visual_job_is_valid(player_id, visual_epoch) then
        return false
      end

      await(Async.sleep(VISUALS.after_squash_seconds or 0.3))
      if not tournament_visual_job_is_valid(player_id, visual_epoch) then
        return false
      end

      move_participant_ui(player_id, tournament, move.index, move.to_pos)
      remove_visual_element(player_id, overlay_id)

      await(unsquash_participant(player_id, tournament, move.index, visual_epoch))
      if not tournament_visual_job_is_valid(player_id, visual_epoch) then
        return false
      end

      await(Async.sleep(VISUALS.after_unsquash_seconds or 0.3))
      if not tournament_visual_job_is_valid(player_id, visual_epoch) then
        return false
      end

      if move_index < #moves then
        await(Async.sleep(VISUALS.between_matches_seconds or 0.5))
        if not tournament_visual_job_is_valid(player_id, visual_epoch) then
          return false
        end
      end
    end

    await(Async.sleep(VISUALS.transition_after_seconds or 1.5))
    return tournament_visual_job_is_valid(player_id, visual_epoch)
  end)
end

local function draw_tournament_board_for_player(player_id, tournament, mode)
  if not visuals_available() or not tournament or not Net.is_player(player_id) then
    return async(function() return false end)
  end

  local visual_epoch = current_player_visual_epoch(player_id)

  return async(function()
    if not tournament_visual_job_is_valid(player_id, visual_epoch) then
      return false
    end

    local area_id = Net.get_player_area(player_id)
    local music_area = acquire_tournament_music(area_id)

    local function abort_if_player_gone()
      if tournament_visual_job_is_valid(player_id, visual_epoch) then
        return false
      end

      -- Do not attempt sprite/HUD/camera cleanup for a disconnected player.
      -- Forget local bookkeeping and release only area-level music state.
      player_visual_ids[player_id] = {}
      release_tournament_music(music_area)
      return true
    end

    local bg_info = get_board_background(tournament)
    local pos = ui_data.unmoving_ui_pos or {}

    pcall(Net.lock_player_input, player_id)

    if Net.toggle_player_hud then
      pcall(Net.toggle_player_hud, player_id)
    end

    if VISUALS.music then
      pcall(Net.set_song, area_id, VISUALS.music)
    end

    pcall(Net.fade_player_camera, player_id, { r = 0, g = 0, b = 0, a = 255 }, VISUALS.fade_seconds)
    await(Async.sleep(VISUALS.fade_seconds))
    if abort_if_player_gone() then return false end

    hide_tournament_text(player_id)
    erase_tournament_board(player_id)

    if bg_info then
      draw_ui(player_id, tournament_visual_id(tournament, "BOARD_BG"), bg_info.gradient_texture, constants.default_background_anim_path_bn4, "BG", pos.bg)
      draw_ui(player_id, tournament_visual_id(tournament, "BOARD_GRID"), bg_info.grid_texture, constants.default_grid_anim_path_bn4, "idle_ui", pos.grid)
    end

    draw_ui(player_id, tournament_visual_id(tournament, "BRACKET"), constants.bracket_bm_bn4, constants.default_bracket_anim_path_bn4, "UI", pos.bracket)
    draw_ui(player_id, tournament_visual_id(tournament, "CHAMPION_TOPPER"), constants.champion_topper_bn4, constants.champion_topper_bn4_anim, "UI", pos.champion_topper_bn4)

    local title_banner_texture = get_tournament_title_banner_texture(tournament)

    if title_banner_texture then
      draw_ui(
        player_id,
        tournament_visual_id(tournament, "TITLE_BANNER"),
        title_banner_texture,
        constants.title_banner_anim_path,
        constants.title_banner_state or "TITLE",
        pos.title_banner
      )
    end

    -- Keep the two side crowns in their normal inactive state. The rewrite uses a
    -- dedicated center crown once the champion is known.
    draw_ui(
      player_id,
      tournament_visual_id(tournament, "CROWN_1"),
      constants.crown_texture_path,
      constants.crown_anim_path,
      "INACTIVE",
      pos.crown1
    )

    draw_ui(
      player_id,
      tournament_visual_id(tournament, "CROWN_2"),
      constants.crown_texture_path,
      constants.crown_anim_path,
      "INACTIVE",
      pos.crown2
    )

    local animate_after_round = mode == "after_round_animated"
    local positions = nil
    local moves = nil
    local completed_path_round = 0

    if animate_after_round then
      local current_positions = get_visual_positions(tournament, "before_round")
      local new_positions = get_visual_positions(tournament, "after_round")
      moves = collect_winner_movements(tournament, current_positions, new_positions)

      if #moves > 0 then
        positions = current_positions
      else
        positions = new_positions
      end

      completed_path_round = math.max(0, (tournament.current_round or 1) - 1)
    else
      positions = get_visual_positions(tournament, mode)

      if mode == "initial" then
        completed_path_round = 0
      elseif mode == "before_round" then
        completed_path_round = math.max(0, (tournament.current_round or 1) - 1)
      elseif mode == "champion" then
        completed_path_round = 3
      else
        completed_path_round = tournament.current_round or 0
      end
    end

    -- Draw permanent history paths behind the mugs before any current-round reveal.
    draw_completed_paths(player_id, tournament, completed_path_round)

    for i, participant in ipairs(tournament.all_participants or {}) do
      add_participant_mugshot(player_id, tournament, i, participant, positions[i])
    end

    apply_existing_eliminations(player_id, tournament, mode)

    if tournament.champion then
      draw_ui(
        player_id,
        tournament_visual_id(tournament, "CHAMPION_INDICATOR"),
        constants.crown_texture_path,
        constants.crown_anim_path,
        "active",
        pos.champion_crown or { x = 120, y = 36, z = 4 }
      )
    end

    pcall(Net.fade_player_camera, player_id, { r = 0, g = 0, b = 0, a = 0 }, VISUALS.fade_seconds)
    await(Async.sleep(VISUALS.fade_seconds))
    if abort_if_player_gone() then return false end

    if animate_after_round and moves and #moves > 0 then
      await(animate_winner_movements(player_id, tournament, moves, visual_epoch))
    else
      await(Async.sleep(mode == "champion" and 3.0 or VISUALS.show_seconds))
    end

    if abort_if_player_gone() then return false end

    pcall(Net.fade_player_camera, player_id, { r = 0, g = 0, b = 0, a = 255 }, VISUALS.fade_seconds)
    await(Async.sleep(VISUALS.fade_seconds))
    if abort_if_player_gone() then return false end

    erase_tournament_board(player_id)

    if Net.toggle_player_hud then
      pcall(Net.toggle_player_hud, player_id)
    end

    release_tournament_music(music_area)

    if not tournament_visual_job_is_valid(player_id, visual_epoch) then
      player_visual_ids[player_id] = {}
      return false
    end

    pcall(Net.fade_player_camera, player_id, { r = 0, g = 0, b = 0, a = 0 }, VISUALS.fade_seconds)
    if not tournament_input_locked[player_id] then
      pcall(Net.unlock_player_input, player_id)
    end

    return true
  end)
end

local function show_tournament_board_to_players(tournament, mode)
  return async(function()
    if not visuals_available() or not tournament then
      return false
    end

    local preserve_existing_live_board = mode == "initial" or mode == "before_round"

    for_each_tournament_viewer(tournament, function(participant)
      local player_id = participant.player_id

      -- A spectator can join while the opening ceremony is still running. Their
      -- persistent board must not be replaced by the transient initial/before-round
      -- presentation, because that presentation intentionally erases itself.
      if not (preserve_existing_live_board
        and TourneyUX.live_board_viewers[player_id] == tournament.id)
      then
        draw_tournament_board_for_player(player_id, tournament, mode)
      end
    end)

    await(Async.sleep(
      VISUALS.fade_seconds * 2
      + animated_board_hold_seconds(tournament, mode)
      + 0.35
    ))
    return true
  end)
end

local function tournament_text_available()
  return Displayer
    and Displayer.Text
    and Displayer.Text.createTextBox
    and Displayer.Text.resetTextBox
    and Displayer.Text.removeTextBox
end

function hide_tournament_text(player_id)
  if not player_id or not Net.is_player(player_id) then return end
  if not tournament_text_available() then return end
  pcall(Displayer.Text.removeTextBox, player_id, TOURNEY_TEXT.box_id)
end

local function show_tournament_text_for_player(player_id, message, hold_seconds)
  return async(function()
    if not Net.is_player(player_id) then
      return false
    end

    if not tournament_text_available() then
      message_player_safe(player_id, message)
      return false
    end

    local opts = {
      page_advance = "auto_advance",
      auto_advance_seconds = hold_seconds or TOURNEY_TEXT.auto_advance_seconds,
      confirm_during_typing = false,
      open_seconds = TOURNEY_TEXT.backdrop.open_seconds,

      wrap_opts = {
        max_chars_for_line = function(line_idx_in_page, default_limit)
          return math.max(default_limit, TOURNEY_TEXT.max_chars_per_line or default_limit)
        end
      }
    }

    local ok, err = pcall(
      Displayer.Text.resetTextBox,
      player_id,
      TOURNEY_TEXT.box_id,
      message,
      TOURNEY_TEXT.x,
      TOURNEY_TEXT.y,
      TOURNEY_TEXT.width,
      TOURNEY_TEXT.height,
      TOURNEY_TEXT.font,
      TOURNEY_TEXT.scale,
      TOURNEY_TEXT.z,
      TOURNEY_TEXT.backdrop,
      TOURNEY_TEXT.speed,
      opts
    )

    if not ok then
      print("[tournaments][textbox] failed: " .. tostring(err))
      message_player_safe(player_id, message)
      return false
    end

    local timeout = 0
    while timeout < 6.0 do
      if not Net.is_player(player_id) then
        return false
      end

      if Displayer.Text.isTextBoxCompleted
        and Displayer.Text.isTextBoxCompleted(player_id, TOURNEY_TEXT.box_id)
      then
        break
      end

      await(Async.sleep(0.1))
      timeout = timeout + 0.1
    end

    pcall(Displayer.Text.closeTextBox, player_id, TOURNEY_TEXT.box_id, {
      caller = "tournaments",
      reason = "done",
      close_seconds = TOURNEY_TEXT.backdrop.close_seconds,
    })

    await(Async.sleep((TOURNEY_TEXT.backdrop.close_seconds or 0.12) + 0.05))
    return true
  end)
end

local function show_queue_join_notice_for_player(player_id, message, hold_seconds)
  if not Net.is_player(player_id) then
    return false
  end

  if not tournament_text_available() then
    print("[tournaments][queue_join_notice] " .. tostring(player_id) .. ": " .. tostring(message))
    return false
  end

  local opts = {
    page_advance = "auto_advance",
    auto_advance_seconds = hold_seconds or 1.8,
    confirm_during_typing = false,
    open_seconds = TOURNEY_TEXT.backdrop.open_seconds,

    wrap_opts = {
      max_chars_for_line = function(line_idx_in_page, default_limit)
        return math.max(default_limit, TOURNEY_TEXT.max_chars_per_line or default_limit)
      end
    }
  }

  local ok, err = pcall(
    Displayer.Text.resetTextBox,
    player_id,
    TOURNEY_TEXT.box_id,
    message,
    TOURNEY_TEXT.x,
    TOURNEY_TEXT.y,
    TOURNEY_TEXT.width,
    TOURNEY_TEXT.height,
    TOURNEY_TEXT.font,
    TOURNEY_TEXT.scale,
    TOURNEY_TEXT.z,
    TOURNEY_TEXT.backdrop,
    TOURNEY_TEXT.speed,
    opts
  )

  if not ok then
    print("[tournaments][queue_join_notice] failed: " .. tostring(err))
    return false
  end

  return true
end

local function announce_queue_notice_to_other_registered_players(queue, except_player_id, message)
  if not queue then return end

  for _, participant in ipairs(queue.participants or {}) do
    if participant.kind == "player"
      and participant.player_id ~= except_player_id
      and Net.is_player(participant.player_id)
    then
      show_queue_join_notice_for_player(
        participant.player_id,
        message,
        1.8
      )
    end
  end
end

local function announce_join_to_other_registered_players(queue, joiner_id, joiner_name)
  if not queue then return end

  for _, participant in ipairs(queue.participants or {}) do
    if participant.kind == "player"
      and participant.player_id ~= joiner_id
      and Net.is_player(participant.player_id)
    then
      show_queue_join_notice_for_player(
        participant.player_id,
        tostring(joiner_name) .. " registered{end_line}for the tournament.",
        1.8
      )
    end
  end
end

-- -----------------------------------------------------------------------------
-- Persistent live tournament board / spectator UX
-- -----------------------------------------------------------------------------

function TourneyUX.participant_is_currently_battling(tournament, participant)
  if not tournament or not participant then
    return false
  end

  for _, match in pairs(tournament.active_spectator_matches or {}) do
    if match and participant_is_in_match(participant, match) then
      return true
    end
  end

  return false
end

function TourneyUX.apply_live_board_eliminations(player_id, tournament)
  if not tournament then return end

  local current_round = tonumber(tournament.current_round or 0) or 0

  for _, participant in ipairs(tournament.all_participants or {}) do
    if participant.eliminated then
      local eliminated_round = tonumber(participant.eliminated_round or 0) or 0

      -- Never reveal the current round's result early. Only losers whose result
      -- was officially presented in a previous round are tinted on the live view.
      if eliminated_round > 0 and eliminated_round < current_round then
        tint_participant_eliminated(player_id, tournament, participant)
      end
    end
  end
end

function TourneyUX.update_live_board_frame_states_for_player(player_id, tournament)
  if not tournament
    or not Net.is_player(player_id)
    or TourneyUX.live_board_viewers[player_id] ~= tournament.id
    or not games
    or not games.update_ui_element
  then
    return false
  end

  local battling = {}

  for _, match in pairs(tournament.active_spectator_matches or {}) do
    if match then
      if match.player1 then battling[match.player1.id] = true end
      if match.player2 then battling[match.player2.id] = true end
    end
  end

  for index, participant in ipairs(tournament.all_participants or {}) do
    local frame_id = tournament_visual_id(tournament, "MUG_FRAME_" .. tostring(index))
    local state = battling[participant.id] and "battling" or "ACTIVE"

    pcall(games.update_ui_element, frame_id, player_id, {
      animation_state = state,
    })
  end

  return true
end

function TourneyUX.draw_live_tournament_board_for_player(player_id, tournament)
  if not visuals_available() or not tournament or not Net.is_player(player_id) then
    return false
  end

  local first_open = TourneyUX.live_board_viewers[player_id] ~= tournament.id
  local bg_info = get_board_background(tournament)
  local pos = ui_data.unmoving_ui_pos or {}
  local positions = get_visual_positions(tournament, "before_round")
  local completed_path_round = math.max(
    0,
    (tonumber(tournament.current_round or 1) or 1) - 1
  )

  if MenuAPI and MenuAPI.is_open and MenuAPI.is_open(player_id) then
    -- A lobby/list should never remain layered over the persistent bracket.
    pcall(MenuAPI.close_all, player_id, {
      keep_frozen = true,
      reason = "tournament_live_board",
    })
    TourneyUX.menu_views[player_id] = nil
  end

  if not Net.is_player(player_id) then
    return false
  end

  hide_tournament_text(player_id)
  erase_tournament_board(player_id)
  set_player_tournament_input_locked(player_id, true)

  if first_open and Net.toggle_player_hud then
    pcall(Net.toggle_player_hud, player_id)
  end

  TourneyUX.live_board_viewers[player_id] = tournament.id

  if bg_info then
    draw_ui(
      player_id,
      tournament_visual_id(tournament, "BOARD_BG"),
      bg_info.gradient_texture,
      constants.default_background_anim_path_bn4,
      "BG",
      pos.bg
    )
    draw_ui(
      player_id,
      tournament_visual_id(tournament, "BOARD_GRID"),
      bg_info.grid_texture,
      constants.default_grid_anim_path_bn4,
      "idle_ui",
      pos.grid
    )
  end

  draw_ui(
    player_id,
    tournament_visual_id(tournament, "BRACKET"),
    constants.bracket_bm_bn4,
    constants.default_bracket_anim_path_bn4,
    "UI",
    pos.bracket
  )

  draw_ui(
    player_id,
    tournament_visual_id(tournament, "CHAMPION_TOPPER"),
    constants.champion_topper_bn4,
    constants.champion_topper_bn4_anim,
    "UI",
    pos.champion_topper_bn4
  )

  local title_banner_texture = get_tournament_title_banner_texture(tournament)
  if title_banner_texture then
    draw_ui(
      player_id,
      tournament_visual_id(tournament, "TITLE_BANNER"),
      title_banner_texture,
      constants.title_banner_anim_path,
      constants.title_banner_state or "TITLE",
      pos.title_banner
    )
  end

  draw_ui(
    player_id,
    tournament_visual_id(tournament, "CROWN_1"),
    constants.crown_texture_path,
    constants.crown_anim_path,
    "INACTIVE",
    pos.crown1
  )

  draw_ui(
    player_id,
    tournament_visual_id(tournament, "CROWN_2"),
    constants.crown_texture_path,
    constants.crown_anim_path,
    "INACTIVE",
    pos.crown2
  )

  -- The live board only shows paths already officially revealed in prior rounds.
  draw_completed_paths(player_id, tournament, completed_path_round)

  for i, participant in ipairs(tournament.all_participants or {}) do
    add_participant_mugshot(player_id, tournament, i, participant, positions[i])
  end

  TourneyUX.apply_live_board_eliminations(player_id, tournament)
  TourneyUX.update_live_board_frame_states_for_player(player_id, tournament)
  return true
end

function TourneyUX.close_live_board_for_player(player_id, tournament, keep_tournament_lock)
  local tid = tournament and tournament.id or TourneyUX.live_board_viewers[player_id]

  if not tid or TourneyUX.live_board_viewers[player_id] ~= tid then
    return false
  end

  -- Cancel any old async presentation for this player before changing ownership of
  -- the board sprites. A new presentation captures the new epoch afterward.
  invalidate_player_visual_jobs(player_id)

  TourneyUX.live_board_viewers[player_id] = nil

  if not Net.is_player(player_id) then
    player_visual_ids[player_id] = {}
    tournament_input_locked[player_id] = nil
    return true
  end

  hide_tournament_text(player_id)
  erase_tournament_board(player_id)

  if Net.toggle_player_hud then
    pcall(Net.toggle_player_hud, player_id)
  end

  if keep_tournament_lock then
    set_player_tournament_input_locked(player_id, true)
  else
    set_player_tournament_input_locked(player_id, false)
  end

  return true
end

function TourneyUX.cancel_spectator_prompt(player_id)
  if not spectator_prompt_open[player_id] then
    return
  end

  spectator_prompt_open[player_id] = nil

  if MenuAPI and MenuAPI.is_open and MenuAPI.is_open(player_id) then
    pcall(MenuAPI.close_all, player_id, {
      keep_frozen = true,
      reason = "tournament_presentation",
    })
  end
end

function TourneyUX.close_live_boards_for_tournament(tournament, keep_tournament_lock)
  if not tournament then return end

  local viewers = {}
  for player_id, tournament_id in pairs(TourneyUX.live_board_viewers) do
    if tournament_id == tournament.id then
      viewers[#viewers + 1] = player_id
    end
  end

  for _, player_id in ipairs(viewers) do
    TourneyUX.cancel_spectator_prompt(player_id)
    TourneyUX.close_live_board_for_player(
      player_id,
      tournament,
      keep_tournament_lock
    )
  end
end

function TourneyUX.refresh_live_board_viewers(tournament)
  if not tournament then return end

  for player_id, tournament_id in pairs(TourneyUX.live_board_viewers) do
    if tournament_id == tournament.id and Net.is_player(player_id) then
      TourneyUX.update_live_board_frame_states_for_player(player_id, tournament)
    end
  end
end

function TourneyUX.open_live_boards_for_waiting_viewers(tournament)
  if not tournament then return end

  for_each_tournament_viewer(tournament, function(participant)
    local player_id = participant.player_id
    local in_active_match = participant_is_in_any_active_match(tournament, participant)
    local engine_battling = false

    if Net.is_player_battling then
      local ok, value = pcall(Net.is_player_battling, player_id)
      engine_battling = ok and value == true
    end

    if in_active_match or engine_battling then
      if TourneyUX.live_board_viewers[player_id] == tournament.id then
        TourneyUX.close_live_board_for_player(player_id, tournament, true)
      end
    else
      if TourneyUX.live_board_viewers[player_id] ~= tournament.id then
        TourneyUX.draw_live_tournament_board_for_player(player_id, tournament)
      else
        TourneyUX.update_live_board_frame_states_for_player(player_id, tournament)
      end
    end
  end)
end

function TourneyUX.show_spectator_notice(player_id)
  -- Keep the short spectator instruction visually tied to the tournament board.
  show_tournament_text_for_player(
    player_id,
    "Spectating tournament.{end_line}Press B to stop spectating.",
    2.0
  )
end

function TourneyUX.enter_spectator_mode(tournament, participant, show_notice)
  if not tournament or not participant or participant.kind ~= "player" then
    return false
  end

  local player_id = participant.player_id
  if not Net.is_player(player_id) then
    return false
  end

  participant.wants_updates = true
  participant.spectating = true
  set_player_tournament_input_locked(player_id, true)
  TourneyUX.draw_live_tournament_board_for_player(player_id, tournament)

  if show_notice ~= false then
    TourneyUX.show_spectator_notice(player_id)
  end

  return true
end

function TourneyUX.stop_watching_tournament(tournament, participant)
  if not tournament or not participant or participant.kind ~= "player" then
    return false
  end

  local player_id = participant.player_id

  participant.wants_updates = false
  participant.spectating = false

  TourneyUX.cancel_spectator_prompt(player_id)
  TourneyUX.close_live_board_for_player(player_id, tournament, false)
  hide_tournament_text(player_id)
  set_player_tournament_input_locked(player_id, false)

  if participant.is_spectator_only then
    if tournament.spectators then
      tournament.spectators[player_id] = nil
    end

    if player_to_tournament[player_id] == tournament.id then
      player_to_tournament[player_id] = nil
    end
  end

  message_player_safe(player_id, "You stopped spectating the tournament.")
  return true
end

function TourneyUX.ask_player_stop_spectating(tournament, player_id)
  if not tournament or not Net.is_player(player_id) then
    return false
  end

  local participant = get_player_participant(tournament, player_id)
  if not participant
    or participant.kind ~= "player"
    or not participant.eliminated
    or participant.spectating ~= true
    or participant.wants_updates == false
  then
    return false
  end

  if spectator_prompt_open[player_id] then
    return false
  end

  if not MenuAPI or not MenuAPI.open then
    message_player_safe(
      player_id,
      "MenuAPI is unavailable; spectator mode was left unchanged."
    )
    return false
  end

  spectator_prompt_open[player_id] = true

  local function resume_spectating()
    spectator_prompt_open[player_id] = nil
    TourneyUX.spectator_cancel_guard_until[player_id] = os.clock() + 0.12

    if active_tournaments[tournament.id] == tournament
      and Net.is_player(player_id)
      and participant.wants_updates ~= false
    then
      participant.spectating = true
      set_player_tournament_input_locked(player_id, true)

      if TourneyUX.live_board_viewers[player_id] ~= tournament.id then
        TourneyUX.draw_live_tournament_board_for_player(player_id, tournament)
      else
        TourneyUX.update_live_board_frame_states_for_player(player_id, tournament)
      end
    end
  end

  local ok, err = pcall(MenuAPI.open, player_id, {
    type = 4,
    title = "Tournament",
    lines = { "Stop spectating?" },
    yes_text = "Yes",
    no_text = "No",
    default_choice = "no",
    lock_input = true,

    on_confirm = function(pid, row)
      local choice = tostring(row and (row.id or row.choice) or "no"):lower()

      if choice == "yes" then
        spectator_prompt_open[pid] = nil
        pcall(MenuAPI.close, pid, {
          keep_frozen = true,
          reason = "stop_spectating_yes",
        })
        TourneyUX.stop_watching_tournament(tournament, participant)
      else
        spectator_prompt_open[pid] = nil
        pcall(MenuAPI.close, pid, {
          keep_frozen = true,
          reason = "stop_spectating_no",
        })
        resume_spectating()
      end
    end,

    on_cancel = function(pid)
      -- B means No: close the confirmation and return to the live board.
      spectator_prompt_open[pid] = nil
      pcall(MenuAPI.close, pid, {
        keep_frozen = true,
        reason = "stop_spectating_cancel",
      })
      resume_spectating()
      return true
    end,

    on_close = function(pid)
      -- If another tournament presentation force-closes this prompt, keep the
      -- participant enrolled as a spectator; the presentation will take over.
      if spectator_prompt_open[pid] then
        resume_spectating()
      end
    end,
  })

  if not ok then
    spectator_prompt_open[player_id] = nil
    print("[tournaments][spectator] stop confirmation failed: " .. tostring(err))
    set_player_tournament_input_locked(player_id, true)
    return false
  end

  return true
end

function TourneyUX.start_eliminated_player_spectating(tournament, loser)
  if not tournament or not loser or loser.kind ~= "player" then
    return false
  end

  if tournament.status == "completed" or (tournament.current_round or 0) >= 3 then
    return false
  end

  if not Net.is_player(loser.player_id) then
    return false
  end

  return TourneyUX.enter_spectator_mode(tournament, loser, true)
end

local function show_tournament_text_to_players(tournament, message, hold_seconds)
  return async(function()
    if not tournament then return false end

    local jobs = {}

    for_each_tournament_viewer(tournament, function(participant)
      jobs[#jobs + 1] = show_tournament_text_for_player(
        participant.player_id,
        message,
        hold_seconds
      )
    end)

    for _, job in ipairs(jobs) do
      await(job)
    end

    return true
  end)
end

-- -----------------------------------------------------------------------------
-- Announcements / board messages
-- -----------------------------------------------------------------------------

local TOURNAMENT_NOTICE_BOX_ID = "menuapi_tournament_notice"
local standalone_tournament_notices = {}

local function clear_tournament_notice(player_id)
  standalone_tournament_notices[player_id] = nil

  if MenuAPI and MenuAPI.hide_message then
    pcall(MenuAPI.hide_message, player_id, TOURNAMENT_NOTICE_BOX_ID)
  end

  if Displayer and Displayer.Text and Displayer.Text.removeTextBox then
    pcall(Displayer.Text.removeTextBox, player_id, TOURNAMENT_NOTICE_BOX_ID)
  end
end

local function show_standalone_tournament_notice(player_id, message)
  if not (Displayer and Displayer.Text and Displayer.Text.resetTextBox) then
    return false
  end

  clear_tournament_notice(player_id)

  local text = tostring(message or ""):gsub("{end_line}", "\n")
  local opts = {
    page_advance = "wait_for_confirm",
    confirm_during_typing = true,
    open_seconds = TOURNEY_TEXT.backdrop.open_seconds,
    wrap_opts = {
      max_chars_for_line = function(line_idx_in_page, default_limit)
        return math.max(default_limit, TOURNEY_TEXT.max_chars_per_line or default_limit)
      end
    }
  }

  local ok, err = pcall(
    Displayer.Text.resetTextBox,
    player_id,
    TOURNAMENT_NOTICE_BOX_ID,
    text,
    TOURNEY_TEXT.x,
    TOURNEY_TEXT.y,
    TOURNEY_TEXT.width,
    TOURNEY_TEXT.height,
    TOURNEY_TEXT.font,
    TOURNEY_TEXT.scale,
    TOURNEY_TEXT.z,
    TOURNEY_TEXT.backdrop,
    TOURNEY_TEXT.speed,
    opts
  )

  if not ok then
    print("[tournaments][notice] standalone message failed: " .. tostring(err))
    return false
  end

  standalone_tournament_notices[player_id] = true
  return true
end

function message_player_safe(player_id, message)
  if not player_id or not Net.is_player(player_id) then
    return false
  end

  -- If a MenuAPI window is open, use its modal message handling so Confirm
  -- advances/finishes the textbox instead of selecting the row underneath it.
  if MenuAPI
    and MenuAPI.show_message
    and MenuAPI.is_open
    and MenuAPI.is_open(player_id)
  then
    clear_tournament_notice(player_id)

    local ok, shown = pcall(MenuAPI.show_message, player_id, tostring(message or ""), {
      box_id = TOURNAMENT_NOTICE_BOX_ID,
      modal = true,
      page_advance = "wait_for_confirm",
      confirm_during_typing = true,
      speed = 80,
    })

    if ok and shown ~= false then
      return true
    end
  end

  -- Outside MenuAPI, draw the same style box directly. A fresh Confirm press
  -- advances it; reaching the final page removes it from the player's screen.
  if show_standalone_tournament_notice(player_id, message) then
    return true
  end

  print("[tournaments][notice] tournament message unavailable for " .. tostring(player_id) .. ": " .. tostring(message))
  return false
end

local function announce_to_tournament(tournament, message)
  if not tournament then return end

  for _, participant in ipairs(tournament.all_participants or tournament.participants or {}) do
    if participant.kind == "player" and Net.is_player(participant.player_id) then
      message_player_safe(participant.player_id, message)
    end
  end
end

local function announce_to_queue(queue, message)
  if not queue then return end

  for _, participant in ipairs(queue.participants or {}) do
    if participant.kind == "player" and Net.is_player(participant.player_id) then
      message_player_safe(participant.player_id, message)
    end
  end
end

local function build_queue_summary(queue)
  local lines = {}
  lines[#lines + 1] = queue.name .. " Queue"

  if SETTINGS.scheduled_enabled == true then
    lines[#lines + 1] = "Starts in " .. format_lobby_countdown(seconds_until_next_scheduled_tournament(queue))
  end

  if #queue.participants == 0 then
    lines[#lines + 1] = "No registered players yet."
  else
    lines[#lines + 1] = "Registered players:"
    for i, participant in ipairs(queue.participants or {}) do
      lines[#lines + 1] = tostring(i) .. ". " .. participant_name(participant)
    end
  end

  return table.concat(lines, "\n")
end

local function build_round_bracket_text(tournament)
  local lines = {}
  lines[#lines + 1] = string.format("%s - Round %d", tournament.name, tournament.current_round)

  for i, match in ipairs(tournament.matches or {}) do
    lines[#lines + 1] = string.format(
      "M%d: %s vs %s",
      i,
      participant_name(match.player1),
      participant_name(match.player2)
    )
  end

  return table.concat(lines, "{end_line}")
end

local function announce_round_bracket(tournament)
  announce_to_tournament(tournament, build_round_bracket_text(tournament))
end

local function build_round_results_text(tournament)
  local lines = {}
  local round = tournament.current_round or 0
  local results = tournament.round_results[round] or {}

  lines[#lines + 1] = string.format("Round %d results:", round)

  for match_index = 1, #(tournament.matches or {}) do
    local result = results[match_index]

    if result then
      lines[#lines + 1] = string.format(
        "M%d: %s beat %s",
        match_index,
        participant_name(result.winner),
        participant_name(result.loser)
      )
    end
  end

  return table.concat(lines, "{end_line}")
end

-- -----------------------------------------------------------------------------
-- Queue management
-- -----------------------------------------------------------------------------

local function remove_from_queue(player_id, quiet)
  local key = player_to_queue[player_id]
  if not key then
    return false
  end

  local queue = board_queues[key]
  player_to_queue[player_id] = nil

  if not queue then
    return false
  end

  local index = find_participant_index(queue.participants, player_id)
  remove_index(queue.participants, index)

  if queue.host_player_id == player_id then
    queue.host_player_id = queue.participants[1] and queue.participants[1].player_id or nil
  end

  if not quiet then
    announce_queue_notice_to_other_registered_players(
      queue,
      player_id,
      player_display_name(player_id) .. " left{end_line}the tournament queue."
    )
  end

  if TourneyUX.refresh_queue_menu_viewers then
    TourneyUX.refresh_queue_menu_viewers(queue, true)
  end

  return true
end

local function unregister_player_from_queue(player_id, reason, quiet)
  local was_removed = remove_from_queue(player_id, true)

  if was_removed and not quiet then
    message_player_safe(
      player_id,
      reason or "You were unregistered from the tournament."
    )
  end

  return was_removed
end

local function prune_busy_queue_participants(queue)
  if not queue then return end

  local changed = false

  for i = #queue.participants, 1, -1 do
    local participant = queue.participants[i]

    if participant and participant.kind == "player" then
      local player_id = participant.player_id
      local should_remove = false
      local reason = nil

      if not Net.is_player(player_id) then
        should_remove = true
      elseif Net.is_player_battling and Net.is_player_battling(player_id) then
        should_remove = true
        reason = "You were removed from the tournament because you entered another battle."
      end

      if should_remove then
        player_to_queue[player_id] = nil
        table.remove(queue.participants, i)
        changed = true

        if reason then
          message_player_safe(player_id, reason)
        end
      end
    end
  end

  if queue.host_player_id and not find_participant_index(queue.participants, queue.host_player_id) then
    queue.host_player_id = queue.participants[1] and queue.participants[1].player_id or nil
    changed = true
  end

  if changed and TourneyUX.refresh_queue_menu_viewers then
    TourneyUX.refresh_queue_menu_viewers(queue, true)
  end
end

local function add_player_to_queue(queue, player_id)
  if queue.status ~= "waiting" then
    return false, "A tournament is already running from this board."
  end

  if not tournament_registration_is_open(queue) then
    return false, "Registration is closed. Next tournament starts in " ..
      format_minutes_only(seconds_until_next_scheduled_tournament(queue)) .. "."
  end

  if Net.is_player_battling and Net.is_player_battling(player_id) then
    return false, "You can't register while you're in battle."
  end

  if player_to_queue[player_id] then
    return false, "You're already queued for a tournament."
  end

  if player_to_tournament[player_id] then
    return false, "You're already in a tournament."
  end

  if #queue.participants >= BRACKET_SIZE then
    return false, "This tournament queue is already full."
  end

  local participant = make_player_participant(player_id)
  queue.participants[#queue.participants + 1] = participant
  player_to_queue[player_id] = queue.key

  if not queue.host_player_id then
    queue.host_player_id = player_id
  end

  announce_join_to_other_registered_players(
    queue,
    player_id,
    participant_name(participant)
  )

  if TourneyUX.refresh_queue_menu_viewers then
    TourneyUX.refresh_queue_menu_viewers(queue, true)
  end

  message_player_safe(
    player_id,
    "You're registered! Tournament starts in " ..
    format_minutes_only(seconds_until_next_scheduled_tournament(queue)) ..
    ". Please avoid random encounters and PVP until it starts."
  )

  return true
end

-- -----------------------------------------------------------------------------
-- Tournament state helpers
-- -----------------------------------------------------------------------------

local function generate_matches(participants)
  local matches = {}
  for i = 1, #participants, 2 do
    if participants[i] and participants[i + 1] then
      matches[#matches + 1] = {
        player1 = participants[i],
        player2 = participants[i + 1],
        completed = false,
        winner = nil,
        loser = nil,
      }
    end
  end
  return matches
end

local function fill_with_npcs(participants, queue)
  local filled = list_copy(participants)
  local source_pool = get_npc_pool_for_queue(queue)

  if #source_pool == 0 then
    return filled, "Tournament NPC pool is empty. Add tournament NPCs before starting."
  end

  local pool = list_copy(source_pool)
  shuffle_in_place(pool)
  local npc_index = 1
  local serial = 1

  while #filled < BRACKET_SIZE do
    local npc_def = pool[npc_index]
    if not npc_def then
      if not SETTINGS.allow_duplicate_npcs then
        return filled, "Not enough NPCs to backfill the tournament."
      end
      npc_index = 1
      pool = list_copy(source_pool)
      shuffle_in_place(pool)
      npc_def = pool[npc_index]
    end

    filled[#filled + 1] = make_npc_participant(npc_def, serial)
    serial = serial + 1
    npc_index = npc_index + 1
  end

  return filled, nil
end

local function create_tournament_from_queue(queue)
  local npc_only = #(queue.participants or {}) == 0
  local participants, err = fill_with_npcs(queue.participants, queue)
  if err then
    return nil, err
  end

  -- Randomize ALL bracket slots after humans + NPCs are finalized.
  -- This prevents two human registrants from always being slot 1 vs slot 2.
  shuffle_in_place(participants)

  local tournament_id = next_tournament_id
  next_tournament_id = next_tournament_id + 1

  local tournament = {
    id = tournament_id,
    name = queue.name,
    board_key = queue.key,
    area_id = queue.area_id,
    object_id = queue.object_id,
    host_player_id = queue.host_player_id,
    status = "running",
    current_round = 0,
    participants = participants,
    all_participants = list_copy(participants),
    matches = {},
    round_results = {},
    champion = nil,
    board_background = queue.board_background or VISUALS.background_key,
    title_banner_key = queue.title_banner_key
      or (constants and constants.title_banner_default)
      or "free-tourney",
    visual_positions = {},
    spectators = {},
    pvp_mode = queue.pvp_mode or "auto",
    force_pvp_hp = queue.force_pvp_hp,
    battle_timeout_seconds = queue.battle_timeout_seconds or SETTINGS.battle_timeout_seconds,
    winner_gp_reward = queue.winner_gp_reward or 0,
    winner_money_reward = queue.winner_money_reward or 0,
    deduct_opposing_team_gp = queue.deduct_opposing_team_gp == true,
    npc_only = npc_only,
  }

  active_tournaments[tournament_id] = tournament

  for _, participant in ipairs(participants) do
    if participant.kind == "player" then
      player_to_queue[participant.player_id] = nil
      player_to_tournament[participant.player_id] = tournament_id
    end
  end

  queue.status = "running"
  queue.active_tournament_id = tournament_id

  return tournament, nil
end

local function cleanup_tournament(tournament)
  if not tournament then return end

  TourneyUX.close_live_boards_for_tournament(tournament, false)
  set_tournament_input_locked(tournament, false)

  for _, participant in ipairs(tournament.all_participants or {}) do
    if participant.kind == "player" then
      local player_id = participant.player_id

      TourneyUX.cancel_spectator_prompt(player_id)
      hide_tournament_text(player_id)
      erase_tournament_board(player_id)

      spectator_prompt_open[player_id] = nil
      TourneyUX.live_board_viewers[player_id] = nil
      player_to_tournament[player_id] = nil
    end
  end

  for player_id, spectator in pairs(tournament.spectators or {}) do
    TourneyUX.cancel_spectator_prompt(player_id)
    hide_tournament_text(player_id)
    erase_tournament_board(player_id)

    spectator_prompt_open[player_id] = nil
    TourneyUX.live_board_viewers[player_id] = nil
    player_to_tournament[player_id] = nil
    set_player_tournament_input_locked(player_id, false)
  end

  active_tournaments[tournament.id] = nil

  local queue = board_queues[tournament.board_key]
  if queue then
    queue.status = "waiting"
    queue.host_player_id = nil
    queue.active_tournament_id = nil
    queue.participants = {}

    if TourneyUX.refresh_queue_menu_viewers then
      TourneyUX.refresh_queue_menu_viewers(queue, true)
    end
  end
end

-- -----------------------------------------------------------------------------
-- HP helpers for WCity-style PvP
-- -----------------------------------------------------------------------------

local function get_hp_state(player_id)
  local max_hp = 0
  local hp = 0

  pcall(function()
    max_hp = tonumber(Net.get_player_max_health(player_id) or 0) or 0
  end)

  pcall(function()
    if Net.get_player_health then
      hp = tonumber(Net.get_player_health(player_id) or 0) or 0
    else
      hp = max_hp
    end
  end)

  if hp <= 0 then hp = max_hp end

  return { hp = hp, max = max_hp }
end

local function restore_hp(player_ids, states)
  for i, player_id in ipairs(player_ids or {}) do
    local st = states and states[i]
    if st and st.max and st.max > 0 and Net.is_player(player_id) then
      local hp = math.min(tonumber(st.hp or st.max) or st.max, st.max)

      pcall(Net.set_player_max_health, player_id, st.max)
      pcall(Net.set_player_health, player_id, hp)

      local area = Net.get_player_area(player_id)
      local honor_saved = Net.get_area_custom_property(area, "Honor Saved HP") == "true"
      if honor_saved and ezmemory then
        if ezmemory.set_player_max_health then
          pcall(ezmemory.set_player_max_health, player_id, st.max, false)
        end
        if ezmemory.set_player_health then
          pcall(ezmemory.set_player_health, player_id, hp)
        end
        pcall(Net.set_player_max_health, player_id, st.max)
        pcall(Net.set_player_health, player_id, hp)
      end
    end
  end
end

local function force_tournament_pvp_hp(player_ids)
  local forced_hp = tonumber(SETTINGS.pvp_hp or TOURNAMENT_PVP_HP) or TOURNAMENT_PVP_HP
  for _, player_id in ipairs(player_ids or {}) do
    if Net.is_player(player_id) then
      pcall(Net.set_player_max_health, player_id, forced_hp)
      pcall(Net.set_player_health, player_id, forced_hp)
    end
  end
end

-- -----------------------------------------------------------------------------
-- Battle result helpers
-- -----------------------------------------------------------------------------

local function enemy_survived(stats)
  if not stats or type(stats.enemies) ~= "table" then
    return false
  end

  for _, enemy in ipairs(stats.enemies) do
    if tonumber(enemy.health or 0) > 0 then
      return true
    end
  end

  return false
end

local function stats_says_player_won_encounter(stats)
  if not stats then
    return false
  end

  if stats.ran or stats.fled or stats.escape then
    return false
  end

  local reason = tonumber(stats.reason or 0) or 0
  if reason == 1 then
    return true
  elseif reason == 2 or reason == 3 or reason == 4 then
    return false
  end

  local hp = tonumber(stats.health or stats.player_hp or stats.hp or 0) or 0
  if hp <= 0 then
    return false
  end

  if enemy_survived(stats) then
    return false
  end

  return true
end

-- -----------------------------------------------------------------------------
-- Battle starters
-- -----------------------------------------------------------------------------

local function wait_until_players_ready(player_ids)
  return async(function()
    while true do
      local busy = false
      for _, player_id in ipairs(player_ids or {}) do
        if Net.is_player(player_id) and Net.is_player_battling(player_id) then
          busy = true
          break
        end
      end
      if not busy then
        return true
      end
      await(Async.sleep(0.5))
    end
  end)
end

local function tournament_should_force_pvp_hp(tournament)
  if tournament and tournament.force_pvp_hp ~= nil then
    return tournament.force_pvp_hp == true
  end

  if SETTINGS.force_pvp_hp == false then
    return false
  end

  local mode = tostring(tournament and tournament.pvp_mode or "auto"):lower()
  local modes = SETTINGS.force_pvp_hp_modes or {}

  if modes[mode] ~= nil then
    return modes[mode] == true
  end

  return mode ~= "wcity"
end

local function run_player_vs_player(match, tournament)
  return async(function()
    local p1 = match.player1.player_id
    local p2 = match.player2.player_id

    if not Net.is_player(p1) or disconnected_players[p1] then
      return match.player2, match.player1
    end
    if not Net.is_player(p2) or disconnected_players[p2] then
      return match.player1, match.player2
    end

    await(wait_until_players_ready({ p1, p2 }))

    local player_ids = { p1, p2 }
    local hp_states = { get_hp_state(p1), get_hp_state(p2) }
    local forced_hp = tournament_should_force_pvp_hp(tournament)

    if forced_hp then
      force_tournament_pvp_hp(player_ids)
    end

    pcall(Net.lock_player_input, p1)
    pcall(Net.lock_player_input, p2)

    local cleanup_done = false
    local function cleanup_after_battle()
      if cleanup_done then return end
      cleanup_done = true

      if not tournament_input_locked[p1] then
        pcall(Net.unlock_player_input, p1)
      end

      if not tournament_input_locked[p2] then
        pcall(Net.unlock_player_input, p2)
      end

      if forced_hp then
        restore_hp(player_ids, hp_states)
      end
    end

    clear_tournament_notice(p1)
    clear_tournament_notice(p2)
    local battle_promise = Async.initiate_pvp(p1, p2)

    -- If the battle eventually finishes after a timeout, still clean up HP/input.
    if battle_promise and battle_promise.and_then then
      battle_promise.and_then(function()
        cleanup_after_battle()
      end)
    end

    local timeout_result = await(await_with_timeout(
      battle_promise,
      get_tournament_battle_timeout(tournament)
    ))

    if timeout_result and timeout_result.timed_out then
      local winner, loser
      if math.random(1, 2) == 1 then
        winner, loser = match.player1, match.player2
      else
        winner, loser = match.player2, match.player1
      end

      local msg = "Tournament match exceeded " ..
        format_duration(get_tournament_battle_timeout(tournament)) ..
        ". Winner chosen randomly: " .. participant_name(winner) .. "."

      message_player_safe(p1, msg)
      message_player_safe(p2, msg)

      print(string.format(
        "[tournaments] PvP timeout: %s vs %s; random winner=%s",
        tostring(participant_name(match.player1)),
        tostring(participant_name(match.player2)),
        tostring(participant_name(winner))
      ))

      return winner, loser
    end

    cleanup_after_battle()

    local result = timeout_result and timeout_result.value or nil

    if result and result.ran then
      if result.player_id == p1 then
        return match.player2, match.player1
      elseif result.player_id == p2 then
        return match.player1, match.player2
      end
      return match.player2, match.player1
    end

    -- This follows the same assumption as OctoPVP: the returned result is from p1's perspective.
    if result and tonumber(result.health or 0) > 0 then
      return match.player1, match.player2
    end

    return match.player2, match.player1
  end)
end

local function tournament_grid_has_nonzero(grid)
  if type(grid) ~= "table" then return false end
  for _, row in ipairs(grid) do
    if type(row) == "table" then
      for _, value in ipairs(row) do
        if tonumber(value or 0) ~= 0 then return true end
      end
    end
  end
  return false
end

local function build_npc_encounter_payload(npc)
  local data = shallow_copy(npc.encounter_data or {})
  data.path = data.path or npc.path

  -- Marker for future compatibility. We do NOT call ezencounters.begin_encounter(),
  -- so this flag is just documentation/debug data for now.
  data._tournament = true
  data._no_pets = true
  data._no_area_rewards = true

  return data
end

local function run_player_vs_npc(player_participant, npc_participant, tournament)
  return async(function()
    local player_id = player_participant.player_id

    if not Net.is_player(player_id) or disconnected_players[player_id] then
      return npc_participant, player_participant
    end

    if not npc_participant.path then
      print("[tournaments] NPC missing encounter path: " .. tostring(npc_participant.name))
      return player_participant, npc_participant
    end

    await(wait_until_players_ready({ player_id }))

    pcall(Net.lock_player_input, player_id)

    local cleanup_done = false
    local function cleanup_after_battle()
      if cleanup_done then return end
      cleanup_done = true

      if not tournament_input_locked[player_id] then
        pcall(Net.unlock_player_input, player_id)
      end
    end

    local data = build_npc_encounter_payload(npc_participant)

    -- Tournaments deliberately bypass ezencounters.begin_encounter() so pets and
    -- normal area rewards remain disabled. Validate the optimized wrapper here
    -- using only the lightweight registry, avoiding a circular module require.
    if package_registry then
      local path = tostring(data.path or "")
      local package_info = package_registry.get(path)
      local fallback_reason = nil

      if not package_info
        and path:sub(1, #package_registry.PACKAGE_PREFIX) == package_registry.PACKAGE_PREFIX
      then
        fallback_reason = "unregistered optimized package path " .. path
      elseif package_info then

          if package_info.supports_obstacles == false
              and tournament_grid_has_nonzero(data.obstacle_positions)
          then
          fallback_reason = "package " .. tostring(package_info.name)
            .. " does not contain obstacle assets"
        end

        if not fallback_reason and package_info.supports_music == false and data.music ~= nil then
          fallback_reason = "package " .. tostring(package_info.name)
            .. " does not contain packaged music"
        end
      end

      if fallback_reason then
        print("[tournaments] optimized package fallback: " .. fallback_reason)
        data.path = package_registry.FALLBACK_PATH
        data._ezencounters_fallback_reason = fallback_reason
      end
    end

    clear_tournament_notice(player_id)
    local battle_promise = Async.initiate_encounter(player_id, data.path or npc_participant.path, data)

    -- If the encounter eventually finishes after a timeout, still unlock input.
    if battle_promise and battle_promise.and_then then
      battle_promise.and_then(function()
        cleanup_after_battle()
      end)
    end

    local timeout_result = await(await_with_timeout(
      battle_promise,
      get_tournament_battle_timeout(tournament)
    ))

    if timeout_result and timeout_result.timed_out then
      message_player_safe(
        player_id,
        "Tournament match exceeded " ..
        format_duration(get_tournament_battle_timeout(tournament)) ..
        ". You were disqualified."
      )

      print(string.format(
        "[tournaments] PvE timeout: %s vs %s; NPC advances",
        tostring(participant_name(player_participant)),
        tostring(participant_name(npc_participant))
      ))

      return npc_participant, player_participant
    end

    cleanup_after_battle()

    local stats = timeout_result and timeout_result.value or nil

    if stats_says_player_won_encounter(stats) then
      return player_participant, npc_participant
    end

    return npc_participant, player_participant
  end)
end

local function run_npc_vs_npc(match, tournament)
  return async(function()
    local p1 = match.player1
    local p2 = match.player2
    local w1 = math.max(1, tonumber(p1.weight or 50) or 50)
    local w2 = math.max(1, tonumber(p2.weight or 50) or 50)
    local roll = math.random(1, w1 + w2)

    local wait_seconds = 0.25

    -- NPC-vs-NPC matches inside a normal human tournament remain nearly
    -- instant. Only a fully synthetic exhibition tournament gets a visible
    -- "battle" duration so spectators have time to watch the active frames.
    if tournament and tournament.npc_only then
      local min_wait = math.max(0, tonumber(SETTINGS.npc_only_match_min_seconds or 8) or 8)
      local max_wait = math.max(min_wait, tonumber(SETTINGS.npc_only_match_max_seconds or 12) or 12)

      -- Keep fractional configuration useful while still choosing a varied
      -- duration. Randomize in tenths of a second.
      local min_tenths = math.floor(min_wait * 10 + 0.5)
      local max_tenths = math.floor(max_wait * 10 + 0.5)
      wait_seconds = math.random(min_tenths, max_tenths) / 10
    end

    await(Async.sleep(wait_seconds))

    if roll <= w1 then
      return p1, p2
    end

    return p2, p1
  end)
end

local function match_should_show_battle_progress(match, tournament)
  if not match then return false end

  if tournament and tournament.npc_only then
    return true
  end

  return is_human(match.player1) or is_human(match.player2)
end

local function run_match(tournament, match, match_index, opts)
  opts = opts or {}

  return async(function()
    local p1 = match.player1
    local p2 = match.player2

    if not opts.suppress_match_text then
      await(show_tournament_text_to_players(tournament, string.format(
        "Round %d, Match %d:{end_line}%s vs %s",
        tournament.current_round,
        match_index,
        participant_name(p1),
        participant_name(p2)
      ), 2.5))
    end

    local winner, loser

    -- run_round_matches_parallel pre-populates all human-involved matches before
    -- any battle coroutine starts, so every waiting viewer sees the correct set
    -- of green "battling" frames immediately.
    tournament.active_spectator_matches = tournament.active_spectator_matches or {}

    if is_human(p1) and is_human(p2) then
      winner, loser = await(run_player_vs_player(match, tournament))
    elseif is_human(p1) and not is_human(p2) then
      winner, loser = await(run_player_vs_npc(p1, p2, tournament))
    elseif not is_human(p1) and is_human(p2) then
      winner, loser = await(run_player_vs_npc(p2, p1, tournament))
    else
      winner, loser = await(run_npc_vs_npc(match, tournament))
    end

    if tournament.active_spectator_matches then
      tournament.active_spectator_matches[match_index] = nil
    end

    tournament.active_spectator_match = nil
    for _, active_match in pairs(tournament.active_spectator_matches or {}) do
      if active_match then
        tournament.active_spectator_match = active_match
        break
      end
    end

    match.completed = true
    match.winner = winner
    match.loser = loser

    if loser then
      loser.eliminated = true
      loser.eliminated_round = tournament.current_round
    end

    tournament.round_results[tournament.current_round] = tournament.round_results[tournament.current_round] or {}

    -- Parallel matches finish in random order, so preserve bracket order by index.
    tournament.round_results[tournament.current_round][match_index] = {
      match = match_index,
      winner = winner,
      loser = loser,
      player1 = p1,
      player2 = p2,
    }

    if not opts.suppress_result_text then
      await(show_tournament_text_to_players(tournament, string.format(
        "%s defeated %s!",
        participant_name(winner),
        participant_name(loser)
      ), 2.5))
    end

    -- Losing humans automatically become spectators (except after the final).
    TourneyUX.start_eliminated_player_spectating(tournament, loser)

    -- The finished player can now return to the live bracket while other matches
    -- continue. Current-round results remain unrevealed until the announcer phase.
    TourneyUX.open_live_boards_for_waiting_viewers(tournament)
    TourneyUX.refresh_live_board_viewers(tournament)

    await(Async.sleep(0.25))
    return winner, loser
  end)
end

local function run_round_matches_parallel(tournament)
  return async(function()
    local jobs = {}

    tournament.active_spectator_matches = {}
    tournament.active_spectator_match = nil

    -- Mark every human-involved match active BEFORE starting any battle. This
    -- avoids a race where one player's live board could briefly open before their
    -- own match coroutine has registered itself.
    for match_index, match in ipairs(tournament.matches or {}) do
      if match_should_show_battle_progress(match, tournament) then
        tournament.active_spectator_matches[match_index] = match
        tournament.active_spectator_match = tournament.active_spectator_match or match
      end
    end

    TourneyUX.open_live_boards_for_waiting_viewers(tournament)

    for match_index, match in ipairs(tournament.matches or {}) do
      jobs[#jobs + 1] = {
        index = match_index,
        job = run_match(tournament, match, match_index, {
          suppress_match_text = true,
          suppress_result_text = true,
        })
      }
    end

    local winners_by_match = {}

    for _, entry in ipairs(jobs) do
      local winner = await(entry.job)
      winners_by_match[entry.index] = winner
    end

    tournament.active_spectator_matches = {}
    tournament.active_spectator_match = nil

    -- The live waiting board ends before the official results. From here onward
    -- the existing announcer -> advancing text -> animated result reveal is kept.
    TourneyUX.close_live_boards_for_tournament(tournament, true)

    local winners = {}
    for i = 1, #(tournament.matches or {}) do
      if winners_by_match[i] then
        winners[#winners + 1] = winners_by_match[i]
      end
    end

    tdebug("[tournaments] Round " .. tostring(tournament.current_round) .. " winners in bracket order:")
    for i, winner in ipairs(winners) do
      tdebug("  " .. tostring(i) .. ": " .. participant_name(winner))
    end

    await(show_tournament_text_to_players(
      tournament,
      build_round_results_text(tournament),
      3.2
    ))

    return winners
  end)
end

-- -----------------------------------------------------------------------------
-- Tournament runner
-- -----------------------------------------------------------------------------
local function give_tournament_money_reward(player_id, amount, tournament)
  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then
    return 0
  end

  local ok = false

  if ezmemory and ezmemory.get_player_money and ezmemory.set_player_money then
    local current = tonumber(ezmemory.get_player_money(player_id) or 0) or 0
    ok = pcall(ezmemory.set_player_money, player_id, current + amount)
  elseif ezmemory and ezmemory.spend_player_money then
    ok = pcall(ezmemory.spend_player_money, player_id, -amount)
  elseif Net.get_player_money and Net.set_player_money then
    local current = tonumber(Net.get_player_money(player_id) or 0) or 0
    ok = pcall(Net.set_player_money, player_id, current + amount)
  end

  if ok then
    message_player_safe(player_id, ("Tournament prize: +%d$!"):format(amount))
    print(("[tournaments][reward] pid=%s tournament=%s money=+%d")
      :format(tostring(player_id), tostring(tournament and tournament.name or "Tournament"), amount))
    return amount
  end

  print(("[tournaments][reward] FAILED money reward pid=%s amount=%d")
    :format(tostring(player_id), amount))
  return 0
end

local function grant_tournament_winner_rewards(tournament)
  if not tournament or not tournament.champion then
    return
  end

  local champion = tournament.champion
  if champion.kind ~= "player" or not champion.player_id or not Net.is_player(champion.player_id) then
    return
  end

  local player_id = champion.player_id
  local gp_reward = math.floor(tonumber(tournament.winner_gp_reward or 0) or 0)
  local money_reward = math.floor(tonumber(tournament.winner_money_reward or 0) or 0)

  if gp_reward > 0 then
    if Teams and Teams.award_tournament_gp then
      local awarded = Teams.award_tournament_gp(
        player_id,
        gp_reward,
        "winning " .. tostring(tournament.name or "a tournament")
      ) or 0

      print(("[tournaments][reward] pid=%s tournament=%s gp_requested=%d gp_awarded=%d")
        :format(tostring(player_id), tostring(tournament.name or "Tournament"), gp_reward, awarded))
    else
      message_player_safe(player_id, "Tournament GP reward is unavailable right now.")
      print("[tournaments][reward] Teams.award_tournament_gp unavailable")
    end
  end

  if tournament.deduct_opposing_team_gp == true then
    if Teams and Teams.deduct_opposing_team_gp_for_player then
      local deducted, opposing_team_name = Teams.deduct_opposing_team_gp_for_player(
        player_id,
        1,
        "tournament stakes"
      )

      deducted = tonumber(deducted or 0) or 0

      if deducted > 0 then
        message_player_safe(
          player_id,
          ("Tournament stakes: %s lost %d GP!"):format(
            tostring(opposing_team_name or "the opposing team"),
            deducted
          )
        )
      end

      print(("[tournaments][reward] pid=%s tournament=%s opposing_gp_deducted=%d")
        :format(tostring(player_id), tostring(tournament.name or "Tournament"), deducted))
    else
      print("[tournaments][reward] Teams.deduct_opposing_team_gp_for_player unavailable")
    end
  end

  if money_reward > 0 then
    give_tournament_money_reward(player_id, money_reward, tournament)
  end
end

local function run_tournament(tournament)
  return async(function()
    if not tournament then return end
    set_tournament_input_locked(tournament, true)

    await(show_tournament_text_to_players(tournament, tournament.name .. " is starting!", 2.5))
    await(show_tournament_board_to_players(tournament, "initial"))

    local remaining = tournament.participants
    local round_number = 1

    while #remaining > 1 do
      tournament.current_round = round_number
      tournament.matches = generate_matches(remaining)
      tournament.status = "round_" .. tostring(round_number)

      await(show_tournament_text_to_players(
        tournament,
        build_round_bracket_text(tournament),
        3.0
      ))
      await(show_tournament_board_to_players(tournament, "before_round"))
      await(Async.sleep(0.75))

      local winners = await(run_round_matches_parallel(tournament))

      remaining = winners
      tournament.participants = remaining

      local names = {}
      for _, participant in ipairs(remaining) do
        names[#names + 1] = participant_name(participant)
      end

      await(show_tournament_text_to_players(tournament, string.format(
        "Round %d complete!{end_line}Advancing: %s",
        round_number,
        table.concat(names, ", ")
      ), 3.0))

      await(show_tournament_board_to_players(tournament, "after_round_animated"))

      await(Async.sleep(1.0))
      round_number = round_number + 1
    end

    tournament.champion = remaining[1]
    tournament.status = "completed"

    TourneyUX.close_live_boards_for_tournament(tournament, true)
    await(show_tournament_board_to_players(tournament, "champion"))

    await(show_tournament_text_to_players(tournament, string.format(
      "%s winner:{end_line}%s!",
      tournament.name,
      participant_name(tournament.champion)
    ), 3.0))

    grant_tournament_winner_rewards(tournament)

    if tournament.champion and tournament.champion.kind == "player" then
      tournament_announce(
        "Tournament " .. tostring(tournament.name or "Tournament") ..
        " has finished. Congratulations to " .. participant_name(tournament.champion),
        { loops = 2 }
      )
    elseif tournament.npc_only and tournament.champion then
      tournament_announce(
        "Tournament " .. tostring(tournament.name or "Tournament") ..
        " has finished. " .. participant_name(tournament.champion) .. " is the champion!",
        { loops = 2 }
      )
    else
      tournament_announce(
        "Tournament " .. tostring(tournament.name or "Tournament") ..
        " has finished, thanks to all participants!",
        { loops = 2 }
      )
    end

    cleanup_tournament(tournament)
  end)
end

start_queue_tournament = function(queue, starter_id, automatic)
  if queue.status ~= "waiting" then
    if starter_id then
      message_player_safe(starter_id, "A tournament is already running from this board.")
    end
    return false
  end

  prune_busy_queue_participants(queue)

  local npc_only_start =
    #queue.participants == 0
    and automatic == true
    and SETTINGS.npc_only_tournaments_enabled == true

  if #queue.participants == 0 and not npc_only_start then
    if starter_id then
      message_player_safe(starter_id, "Nobody is registered for this tournament yet.")
    end
    return false
  end

  if not automatic and SETTINGS.manual_start_enabled ~= true then
    if starter_id then
      message_player_safe(starter_id, "Tournament starts automatically. Next start in " ..
        format_minutes_only(seconds_until_next_scheduled_tournament(queue)) .. ".")
    end
    return false
  end

  if not automatic and starter_id ~= queue.host_player_id then
    message_player_safe(starter_id, "Only the tournament host can start it right now.")
    return false
  end

  local tournament, err = create_tournament_from_queue(queue)
  if not tournament then
    if starter_id then
      message_player_safe(starter_id, err or "Could not start tournament.")
    end
    return false
  end

  if TourneyUX.refresh_queue_menu_viewers then
    TourneyUX.refresh_queue_menu_viewers(queue, true)
  end

  if TourneyUX.close_queue_menu_viewers then
    TourneyUX.close_queue_menu_viewers(queue, tournament)
  end

  tournament_announce(
    "Tournament " .. tostring(tournament.name or queue.name or "Tournament") .. " has started",
    { loops = 2 }
  )

  run_tournament(tournament)
  return true
end

local function rewatch_eliminated_participant(tournament, player_id)
  if not tournament or not Net.is_player(player_id) then
    return false, "Tournament not found."
  end

  local participant = get_player_participant(tournament, player_id)

  if not participant
    or participant.kind ~= "player"
    or not participant.eliminated
    or participant.is_spectator_only
  then
    return false, "You're already in this tournament."
  end

  return TourneyUX.enter_spectator_mode(tournament, participant, true), nil
end

local function add_player_as_spectator(tournament, player_id)
  if not tournament or not Net.is_player(player_id) then
    return false, "Tournament not found."
  end

  if player_to_queue[player_id] then
    unregister_player_from_queue(player_id, nil, true)
  end

  if player_to_tournament[player_id] then
    if player_to_tournament[player_id] == tournament.id then
      local participant = get_player_participant(tournament, player_id)

      if participant
        and participant.kind == "player"
        and participant.eliminated
        and not participant.is_spectator_only
      then
        return rewatch_eliminated_participant(tournament, player_id)
      end
    end

    return false, "You're already in a tournament or spectating one."
  end

  local spectator = make_player_participant(player_id)
  spectator.id = "spectator:" .. tostring(tournament.id) .. ":" .. tostring(player_id)
  spectator.eliminated = true
  spectator.spectating = true
  spectator.wants_updates = true
  spectator.is_spectator_only = true

  tournament.spectators = tournament.spectators or {}
  tournament.spectators[player_id] = spectator
  player_to_tournament[player_id] = tournament.id

  if not TourneyUX.enter_spectator_mode(tournament, spectator, true) then
    tournament.spectators[player_id] = nil
    player_to_tournament[player_id] = nil
    return false, "Could not open tournament spectator mode."
  end

  return true
end

-- -----------------------------------------------------------------------------
-- MenuAPI tournament lobby
-- -----------------------------------------------------------------------------

function TourneyUX.seconds_until_registration_open(queue)
  if SETTINGS.scheduled_enabled ~= true then
    return 0
  end

  local lead = tonumber(
    queue and queue.registration_lead_seconds
      or SETTINGS.registration_lead_seconds
      or 600
  ) or 600

  return math.max(0, seconds_until_next_scheduled_tournament(queue) - lead)
end

function TourneyUX.active_match_count(tournament)
  local count = 0
  for _, match in pairs(tournament and tournament.active_spectator_matches or {}) do
    if match then count = count + 1 end
  end
  return count
end

function TourneyUX.info_row(id, text, right)
  return {
    id = id,
    text = text,
    right = right,
    selectable = false,
  }
end

function TourneyUX.action_row(id, text)
  return {
    id = id,
    text = text,
    selectable = true,
  }
end

function TourneyUX.separator_row()
  return TourneyUX.info_row("separator", "----------------")
end

function TourneyUX.lobby_rows_for_player(player_id, queue)
  local rows = {}
  local active_tournament = queue.active_tournament_id
    and active_tournaments[queue.active_tournament_id]
    or nil

  if queue.status == "running" and active_tournament then
    rows[#rows + 1] = TourneyUX.info_row("status", "Tournament Running")
    rows[#rows + 1] = TourneyUX.info_row(
      "round",
      "Round: " .. tostring(active_tournament.current_round or 0)
    )
    rows[#rows + 1] = TourneyUX.info_row(
      "battles",
      "Battles",
      tostring(TourneyUX.active_match_count(active_tournament))
    )
    rows[#rows + 1] = TourneyUX.separator_row()

    local participant = get_player_participant(active_tournament, player_id)
    local can_spectate = not player_to_tournament[player_id]
      or (participant and participant.eliminated and participant.wants_updates == false)

    if can_spectate then
      rows[#rows + 1] = TourneyUX.action_row("spectate", "Spectate")
    elseif participant and participant.eliminated and participant.spectating == true then
      rows[#rows + 1] = TourneyUX.info_row("spectating", "Already Spectating")
    end

    rows[#rows + 1] = TourneyUX.action_row("exit", "Exit")
    return rows
  end

  local registered_here = player_to_queue[player_id] == queue.key
  local registered_elsewhere = player_to_queue[player_id]
    and player_to_queue[player_id] ~= queue.key
  local registration_open = tournament_registration_is_open(queue)
  local queue_full = #(queue.participants or {}) >= BRACKET_SIZE

  if registered_here then
    rows[#rows + 1] = TourneyUX.info_row("status", "Registered")
  elseif registered_elsewhere then
    rows[#rows + 1] = TourneyUX.info_row("status", "Registered Elsewhere")
  elseif registration_open and queue_full then
    rows[#rows + 1] = TourneyUX.info_row("status", "Signups: FULL")
  elseif registration_open then
    rows[#rows + 1] = TourneyUX.info_row("status", "Signups: OPEN")
  else
    rows[#rows + 1] = TourneyUX.info_row("status", "Signups: CLOSED")
    rows[#rows + 1] = TourneyUX.info_row(
      "opens",
      "Opens in " .. format_lobby_countdown(TourneyUX.seconds_until_registration_open(queue))
    )
  end

  if SETTINGS.scheduled_enabled == true then
    rows[#rows + 1] = TourneyUX.info_row(
      "starts",
      "Starts in " .. format_lobby_countdown(seconds_until_next_scheduled_tournament(queue))
    )
  else
    rows[#rows + 1] = TourneyUX.info_row("starts", "Starts manually")
  end

  rows[#rows + 1] = TourneyUX.info_row(
    "players",
    "Players",
    tostring(#(queue.participants or {})) .. "/" .. tostring(BRACKET_SIZE)
  )
  rows[#rows + 1] = TourneyUX.separator_row()

  if not registered_here
    and not registered_elsewhere
    and registration_open
    and not queue_full
  then
    rows[#rows + 1] = TourneyUX.action_row("register", "Register")
  end

  rows[#rows + 1] = TourneyUX.action_row("view_players", "View Players")

  if registered_here then
    if SETTINGS.manual_start_enabled == true and queue.host_player_id == player_id then
      rows[#rows + 1] = TourneyUX.action_row("start", "Start Now")
    end
    rows[#rows + 1] = TourneyUX.action_row("withdraw", "Withdraw")
  end

  rows[#rows + 1] = TourneyUX.action_row("exit", "Exit")
  return rows
end

function TourneyUX.registered_player_rows(queue)
  local rows = {}

  for i, participant in ipairs(queue and queue.participants or {}) do
    -- Keep entrant rows selectable so Type 1 can scroll naturally when the
    -- list grows. Confirming a player row intentionally does nothing.
    rows[#rows + 1] = TourneyUX.action_row(
      "player_" .. tostring(i),
      tostring(i) .. ". " .. participant_name(participant)
    )
  end

  if #rows == 0 then
    rows[#rows + 1] = TourneyUX.info_row("empty", "No players yet")
  end

  rows[#rows + 1] = TourneyUX.action_row("back", "Back")
  return rows
end

function TourneyUX.menu_rows_signature(rows)
  local parts = {}
  for _, row in ipairs(rows or {}) do
    parts[#parts + 1] = table.concat({
      tostring(row.id or ""),
      tostring(row.text or ""),
      tostring(row.right or ""),
      tostring(row.selectable ~= false),
    }, "|")
  end
  return table.concat(parts, "\n")
end

function TourneyUX.refresh_tournament_menu_view(player_id, force)
  local view = TourneyUX.menu_views[player_id]
  if not view or not MenuAPI or not MenuAPI.set_rows then
    return false
  end

  if not Net.is_player(player_id) then
    TourneyUX.menu_views[player_id] = nil
    return false
  end

  local queue = board_queues[view.queue_key]
  if not queue then
    TourneyUX.menu_views[player_id] = nil
    return false
  end

  local rows
  if view.view == "players" then
    rows = TourneyUX.registered_player_rows(queue)
  else
    rows = TourneyUX.lobby_rows_for_player(player_id, queue)
  end

  local signature = TourneyUX.menu_rows_signature(rows)
  if not force and signature == view.last_signature then
    return true
  end

  local ok, result = pcall(MenuAPI.set_rows, player_id, rows, {
    keep_cursor = true,
  })

  if ok and result ~= false then
    view.last_signature = signature
    return true
  end

  return false
end

TourneyUX.refresh_queue_menu_viewers = function(queue, force)
  if not queue then return end

  for player_id, view in pairs(TourneyUX.menu_views) do
    if view.queue_key == queue.key then
      TourneyUX.refresh_tournament_menu_view(player_id, force)
    end
  end
end

function TourneyUX.close_queue_menu_viewers(queue, tournament)
  if not queue then return end

  local viewers = {}
  for player_id, view in pairs(TourneyUX.menu_views) do
    if view.queue_key == queue.key then
      viewers[#viewers + 1] = player_id
    end
  end

  for _, player_id in ipairs(viewers) do
    TourneyUX.menu_views[player_id] = nil

    if MenuAPI and MenuAPI.is_open and MenuAPI.is_open(player_id) then
      local is_participant = tournament
        and player_to_tournament[player_id] == tournament.id

      pcall(MenuAPI.close_all, player_id, {
        keep_frozen = is_participant == true,
        reason = "tournament_started",
      })
    end
  end
end

function TourneyUX.open_registered_players_menu(player_id, queue)
  if not MenuAPI or not MenuAPI.push then
    message_player_safe(player_id, "Tournament menu is unavailable.")
    return false
  end

  local view = TourneyUX.menu_views[player_id]
  if view then
    view.view = "players"
    view.last_signature = nil
  end

  local ok, err = pcall(MenuAPI.push, player_id, {
    type = 1,
    title = "Registered Players",
    rows = TourneyUX.registered_player_rows(queue),
    lock_input = true,

    on_confirm = function(pid, row)
      if row and row.id == "back" then
        pcall(MenuAPI.close, pid, {
          reason = "tournament_players_back",
        })
      end
    end,

    on_cancel = function()
      return false
    end,

    on_close = function(pid)
      local current = TourneyUX.menu_views[pid]
      if current and current.queue_key == queue.key then
        current.view = "lobby"
        current.last_signature = nil
        async(function()
          await(Async.sleep(0))
          TourneyUX.refresh_tournament_menu_view(pid, true)
        end)
      end
    end,
  })

  if not ok then
    if view then view.view = "lobby" end
    print("[tournaments][menu] player list failed: " .. tostring(err))
    return false
  end

  TourneyUX.refresh_tournament_menu_view(player_id, true)
  return true
end

function TourneyUX.open_withdraw_confirmation(player_id, queue)
  if not MenuAPI or not MenuAPI.push then return false end

  local ok, err = pcall(MenuAPI.push, player_id, {
    type = 4,
    title = "Tournament",
    lines = { "Withdraw?" },
    yes_text = "Yes",
    no_text = "No",
    default_choice = "no",
    lock_input = true,

    on_confirm = function(pid, row)
      local choice = tostring(row and (row.id or row.choice) or "no"):lower()
      pcall(MenuAPI.close, pid, { reason = "withdraw_choice" })

      if choice == "yes" then
        remove_from_queue(pid)
        message_player_safe(pid, "You left the tournament queue.")
        TourneyUX.refresh_queue_menu_viewers(queue, true)
      end
    end,

    on_cancel = function()
      return false
    end,
  })

  if not ok then
    print("[tournaments][menu] withdraw confirmation failed: " .. tostring(err))
    return false
  end

  return true
end

function TourneyUX.open_start_confirmation(player_id, queue)
  if not MenuAPI or not MenuAPI.push then return false end

  local ok, err = pcall(MenuAPI.push, player_id, {
    type = 4,
    title = "Tournament",
    lines = { "Start tournament now?" },
    yes_text = "Yes",
    no_text = "No",
    default_choice = "no",
    lock_input = true,

    on_confirm = function(pid, row)
      local choice = tostring(row and (row.id or row.choice) or "no"):lower()
      pcall(MenuAPI.close, pid, { reason = "start_choice" })
      if choice == "yes" then
        start_queue_tournament(queue, pid)
      end
    end,

    on_cancel = function()
      return false
    end,
  })

  if not ok then
    print("[tournaments][menu] start confirmation failed: " .. tostring(err))
    return false
  end

  return true
end

function TourneyUX.open_tournament_menu(player_id, queue)
  if not MenuAPI or not MenuAPI.open then
    message_player_safe(player_id, "Tournament menu is unavailable.")
    return false
  end

  TourneyUX.menu_views[player_id] = {
    queue_key = queue.key,
    view = "lobby",
    last_signature = nil,
  }

  local ok, err = pcall(MenuAPI.open, player_id, {
    type = 1,
    title = queue.name,
    rows = TourneyUX.lobby_rows_for_player(player_id, queue),
    lock_input = true,

    on_confirm = function(pid, row)
      if not row then return end
      local id = row.id

      if id == "register" then
        local joined, join_err = add_player_to_queue(queue, pid)
        if not joined then
          message_player_safe(pid, join_err or "Could not join tournament.")
        else
          TourneyUX.refresh_queue_menu_viewers(queue, true)

          if SETTINGS.auto_start_when_full
            and #queue.participants >= BRACKET_SIZE
            and queue.host_player_id
          then
            start_queue_tournament(queue, queue.host_player_id)
          end
        end

      elseif id == "view_players" then
        TourneyUX.open_registered_players_menu(pid, queue)

      elseif id == "withdraw" then
        TourneyUX.open_withdraw_confirmation(pid, queue)

      elseif id == "start" then
        TourneyUX.open_start_confirmation(pid, queue)

      elseif id == "spectate" then
        local tournament = queue.active_tournament_id
          and active_tournaments[queue.active_tournament_id]
          or nil

        pcall(MenuAPI.close_all, pid, {
          keep_frozen = true,
          reason = "tournament_spectate",
        })
        TourneyUX.menu_views[pid] = nil

        local spectate_ok, spectate_err = add_player_as_spectator(tournament, pid)
        if not spectate_ok then
          set_player_tournament_input_locked(pid, false)
          message_player_safe(pid, spectate_err or "Could not spectate tournament.")
        end

      elseif id == "exit" then
        TourneyUX.menu_views[pid] = nil
        pcall(MenuAPI.close_all, pid, {
          reason = "tournament_exit",
        })
      end
    end,

    on_cancel = function(pid)
      TourneyUX.menu_views[pid] = nil
      return false
    end,

    on_close = function(pid)
      local view = TourneyUX.menu_views[pid]
      if view and view.queue_key == queue.key and view.view == "lobby" then
        TourneyUX.menu_views[pid] = nil
      end
    end,
  })

  if not ok then
    TourneyUX.menu_views[player_id] = nil
    print("[tournaments][menu] lobby failed: " .. tostring(err))
    message_player_safe(player_id, "Could not open tournament menu.")
    return false
  end

  TourneyUX.refresh_tournament_menu_view(player_id, true)
  return true
end

-- -----------------------------------------------------------------------------
-- Public API / integration helpers
-- -----------------------------------------------------------------------------
function Tournaments.unregister_if_queued_for_battle(player_id, reason)
  clear_tournament_notice(player_id)

  if player_to_queue[player_id] and not player_to_tournament[player_id] then
    return unregister_player_from_queue(
      player_id,
      reason or "You were unregistered from the tournament because you entered another battle.",
      false
    )
  end

  return false
end

function Tournaments.set_npc_pool(name_or_pool, pool)
  -- Backwards compatible:
  -- Tournaments.set_npc_pool(pool)
  if type(name_or_pool) == "table" and pool == nil then
    NPC_POOL = name_or_pool or {}
    NPC_POOLS.default = NPC_POOL
    return
  end

  -- Named pool:
  -- Tournaments.set_npc_pool("wcity_rank1", pool)
  local name = tostring(name_or_pool or "default")
  NPC_POOLS[name] = pool or {}
end

function Tournaments.get_npc_pool(name)
  if name then
    return NPC_POOLS[tostring(name)]
  end

  return NPC_POOLS.default or NPC_POOL
end

function Tournaments.configure(settings)
  for k, v in pairs(settings or {}) do
    SETTINGS[k] = v
  end
end

function Tournaments.is_player_busy(player_id)
  return player_to_queue[player_id] ~= nil or player_to_tournament[player_id] ~= nil
end

function Tournaments.get_player_tournament_id(player_id)
  return player_to_tournament[player_id]
end

function Tournaments.get_player_queue_key(player_id)
  return player_to_queue[player_id]
end

function Tournaments.debug_state()
  print("[tournaments] queues:")
  for key, queue in pairs(board_queues) do
    print(string.format("  %s status=%s players=%d host=%s", key, tostring(queue.status), #queue.participants, tostring(queue.host_player_id)))
  end

  print("[tournaments] active tournaments:")
  for id, tournament in pairs(active_tournaments) do
    print(string.format("  %s status=%s round=%s participants=%d", tostring(id), tostring(tournament.status), tostring(tournament.current_round), #tournament.participants))
  end
end

_G.Tournaments = Tournaments

local function run_scheduled_tournament_start(queue)
  if not queue then return false end

  if queue.status ~= "waiting" then
    sdebug("[tournaments][scheduler] skip " .. tostring(queue.key) ..
      " status=" .. tostring(queue.status))
    return false
  end

  prune_busy_queue_participants(queue)
  if TourneyUX.refresh_queue_menu_viewers then
    TourneyUX.refresh_queue_menu_viewers(queue, true)
  end

  if #queue.participants > 0 then
    return start_queue_tournament(queue, nil, true)
  end

  if SETTINGS.npc_only_tournaments_enabled == true then
    sdebug("[tournaments] Scheduled tournament time reached for " ..
      tostring(queue.key) .. "; nobody registered, starting NPC exhibition tournament.")
    return start_queue_tournament(queue, nil, true)
  end

  tournament_announce(
    "Tournament " .. tostring(queue.name or "Tournament") .. " has finished",
    { loops = 2 }
  )

  sdebug("[tournaments] Scheduled tournament time reached for " ..
    tostring(queue.key) .. ", but nobody was registered.")

  return false
end

local function update_tournament_scheduler(event)
  if SETTINGS.scheduled_enabled ~= true then
    return
  end

  local now = os.time()

  for _, queue in pairs(board_queues) do
    local prev_start, next_start = get_queue_schedule_times(queue, now)
    local seconds_to_next = math.max(0, next_start - now)
    local registration_lead = tonumber(queue.registration_lead_seconds or SETTINGS.registration_lead_seconds or 600) or 600
    local five_min = tonumber(SETTINGS.five_min_warning_seconds or 300) or 300
    local grace = tonumber(SETTINGS.start_grace_seconds or 10) or 10

    -- Registration-open announcement.
    if queue.status == "waiting"
      and seconds_to_next <= registration_lead
      and queue._last_registration_open_announce_at ~= next_start
    then
      queue._last_registration_open_announce_at = next_start

      tournament_announce(
        "Tournament " .. tostring(queue.name or "Tournament") .. " is now open for registration",
        { loops = 2 }
      )

      if TourneyUX.refresh_queue_menu_viewers then
        TourneyUX.refresh_queue_menu_viewers(queue, true)
      end
    end

    -- 5-minute warning.
    if queue.status == "waiting"
      and seconds_to_next <= five_min
      and queue._last_five_min_announce_at ~= next_start
    then
      queue._last_five_min_announce_at = next_start

      tournament_announce(
        "Tournament " .. tostring(queue.name or "Tournament") .. " starts in 5 minutes",
        { loops = 2 }
      )
    end

    -- Start trigger. We check the previous scheduled time with a small grace window
    -- so we don't miss it if the tick runs slightly after the exact second.
    if now >= prev_start
      and (now - prev_start) <= grace
      and queue._last_start_attempt_at ~= prev_start
    then
      queue._last_start_attempt_at = prev_start
      run_scheduled_tournament_start(queue)
    end
  end
end

function TourneyUX.update_open_tournament_menus()
  -- Check once per second so countdown boundaries are noticed promptly.
  -- refresh_tournament_menu_view() compares row signatures first, so the
  -- client is only redrawn when the visible bucket changes: once per minute
  -- above 1m, then once every 5s during the final minute.
  local now_second = os.time()
  if TourneyUX.menu_last_refresh_second == now_second then
    return
  end

  TourneyUX.menu_last_refresh_second = now_second

  for player_id in pairs(TourneyUX.menu_views) do
    if MenuAPI and MenuAPI.is_open and MenuAPI.is_open(player_id) then
      TourneyUX.refresh_tournament_menu_view(player_id, false)
    else
      TourneyUX.menu_views[player_id] = nil
    end
  end
end

-- -----------------------------------------------------------------------------
-- Event handlers
-- -----------------------------------------------------------------------------
Net:on("tick", function(event)
  update_tournament_scheduler(event)
  TourneyUX.update_open_tournament_menus()
end)

Net:on("virtual_input", function(event)
  local player_id = event and event.player_id
  if not player_id or not Net.is_player(player_id) then
    return
  end

  for _, button in next, event.events or {} do
    if button and button.state == 1 then
      if button.name == "Confirm" and standalone_tournament_notices[player_id] then
        if Displayer and Displayer.Text and Displayer.Text.advanceTextBox then
          pcall(Displayer.Text.advanceTextBox, player_id, TOURNAMENT_NOTICE_BOX_ID)

          local completed = false
          if Displayer.Text.getTextBoxState then
            local ok, state = pcall(Displayer.Text.getTextBoxState, player_id, TOURNAMENT_NOTICE_BOX_ID)
            completed = ok and state == "completed"
          elseif Displayer.Text.isTextBoxCompleted then
            local ok, value = pcall(Displayer.Text.isTextBoxCompleted, player_id, TOURNAMENT_NOTICE_BOX_ID)
            completed = ok and value == true
          end

          if completed then
            clear_tournament_notice(player_id)
          end
        end
        return
      end

      if button.name == "Cancel" and SETTINGS.spectator_cancel_enabled then
        local tournament_id = player_to_tournament[player_id]
        local tournament = tournament_id and active_tournaments[tournament_id] or nil
        local participant = get_player_participant(tournament, player_id)
        local guard_until = TourneyUX.spectator_cancel_guard_until[player_id] or 0

        if os.clock() >= guard_until
          and tournament
          and participant
          and participant.kind == "player"
          and participant.eliminated
          and participant.spectating == true
          and participant.wants_updates ~= false
          and TourneyUX.live_board_viewers[player_id] == tournament.id
          and not spectator_prompt_open[player_id]
          and not (MenuAPI and MenuAPI.is_open and MenuAPI.is_open(player_id))
        then
          TourneyUX.ask_player_stop_spectating(tournament, player_id)
        end
        return
      end
    end
  end
end)

if object_registry and object_registry.register_handler then
  object_registry.register_handler("Tournament Board", function(area_id, object)
    if not object or not object.id then return end

    local queue = get_board_queue(area_id, object.id, object)

    print(
      "[tournaments][object_registry] initialized board queue "
      .. tostring(queue and queue.key)
      .. " name="
      .. tostring(queue and queue.name)
    )
  end, false)
end

Net:on("object_interaction", function(event)
  if event.button ~= 0 then
    return
  end

  local player_id = event.player_id
  local area_id = Net.get_player_area(player_id)
  local object = Net.get_object_by_id(area_id, event.object_id)

  if not is_tournament_object(object) then
    return
  end

  local queue = get_board_queue(area_id, event.object_id, object)

  if player_to_tournament[player_id] then
    local tournament = queue.active_tournament_id and active_tournaments[queue.active_tournament_id] or nil
    local participant = get_player_participant(tournament, player_id)

    if queue.status == "running"
      and tournament
      and participant
      and participant.kind == "player"
      and participant.eliminated
      and participant.spectating ~= true
    then
      TourneyUX.open_tournament_menu(player_id, queue)
      return
    end

    message_player_safe(player_id, "You're already in a tournament.")
    return
  end

  TourneyUX.open_tournament_menu(player_id, queue)
end)

Net:on("player_area_transfer", function(event)
  local player_id = event.player_id

  if TourneyUX.menu_views[player_id] then
    TourneyUX.menu_views[player_id] = nil
    if MenuAPI and MenuAPI.is_open and MenuAPI.is_open(player_id) then
      pcall(MenuAPI.close_all, player_id, {
        reason = "tournament_area_transfer",
      })
    end
  end

  -- Leaving an area while merely queued should unregister the player.
  -- Active tournament players are allowed to transfer because battles do that naturally.
  if player_to_queue[player_id] and not player_to_tournament[player_id] then
    local key = player_to_queue[player_id]
    remove_from_queue(player_id)
    if board_queues[key] and TourneyUX.refresh_queue_menu_viewers then
      TourneyUX.refresh_queue_menu_viewers(board_queues[key], true)
    end
  end
end)

Net:on("player_disconnect", function(event)
  local player_id = event.player_id

  -- Invalidate FIRST. Any board coroutine that wakes after this event will stop
  -- before its next sprite/path/mug operation. Do not call visual/text removal APIs
  -- here: the native player object is already gone.
  invalidate_player_visual_jobs(player_id)
  standalone_tournament_notices[player_id] = nil
  player_visual_ids[player_id] = {}
  tournament_input_locked[player_id] = nil

  TourneyUX.spectator_cancel_guard_until[player_id] = nil
  disconnected_players[player_id] = true
  spectator_prompt_open[player_id] = nil
  TourneyUX.menu_views[player_id] = nil
  TourneyUX.live_board_viewers[player_id] = nil

  if player_to_queue[player_id] then
    local key = player_to_queue[player_id]
    remove_from_queue(player_id, true)
    if board_queues[key] and TourneyUX.refresh_queue_menu_viewers then
      TourneyUX.refresh_queue_menu_viewers(board_queues[key], true)
    end
  end

  local tournament_id = player_to_tournament[player_id]
  local tournament = tournament_id and active_tournaments[tournament_id] or nil

  if tournament and tournament.spectators then
    tournament.spectators[player_id] = nil
  end

  if tournament then
    for _, participant in ipairs(tournament.all_participants or {}) do
      if participant.kind == "player" and participant.player_id == player_id then
        participant.disconnected = true
        break
      end
    end
  end
end)

Net:on("player_connect", function(event)
  disconnected_players[event.player_id] = nil
end)

return Tournaments
