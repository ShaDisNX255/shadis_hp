-- scripts/ezlibs-custom/pets.lua
-- Anchorless "Virus Pet" system + Expedition v1 (OnceHub HPs).
--
-- Pets are bots (Net.create_bot) with waypoint movement (eznpcs-style).
-- Placement/removal is handled by eznpcs_onceitem.lua (Home Hub -> Pets).
--
-- Persistence (area memory, bucket area set by OnceHub):
--   mem.oncehub_pets_v1[oncehub_key] = { pet_entry, ... }
--
-- Expedition v1:
--   • Pet has fatigue counter -> mood (happy/neutral/sad)
--   • Feed 1 BugFrag to raise 1 mood tier
--   • 1 expedition per player at a time
--   • Expedition lasts 1 hour, pet roams a random configured area
--   • Pet returns to original HP + stores reward until the OWNER interacts
--   • Cooldown after returning (longer if sad)
--   • If HP rental expires, expedition is cancelled and pet is removed

local pets = {}

-- ====================== Requires ======================
local helpers  = require('scripts/ezlibs-scripts/helpers')
local ezmenus  = require('scripts/ezlibs-scripts/ezmenus')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')

-- ==== Forward Declare ==== ---
local clamp_pet_battle_rank
local _clear_companion_runtime
local companion_live_entries
local _get_owned_pet
local _get_player_pets_store
local save_bucket
local _sync_live_companion_from_owned

-- Teams is optional; we only call it if available.
local Teams = (function()
  local ok, M = pcall(require, 'scripts/teams/teams')
  if ok and M then return M end
  return rawget(_G, "Teams")
end)()

-- ====================== Config ======================
local CONFIG = {
  -- How often a pet considers choosing a new wander target (seconds)
  move_interval_sec = 5.0,
  move_jitter_sec   = 1.5,

  -- If blocked while moving, how long to wait before giving up and picking a new target
  blocked_timeout_sec = 1.25,

  -- Pet collision + movement
  size  = 0.20,
  speed = 2.00,

  -- If you want pets to be solid (can't walk through)
  solid = true,

  -- Choose movement directions (virus/isometric)
  directions = { "Up Left", "Up Right", "Down Left", "Down Right" },

  -- How close to a waypoint counts as "arrived"
  arrive_epsilon = 0.05,
}

-- ====================== Expedition v1 Config ======================
local EXPEDITION = {
  debug = true, -- set false when stable
  -- Expedition duration (minutes). Set to 1 for testing.
  duration_minutes = 60,

  -- Derived seconds value (do not edit directly)
  duration_sec = 60 * 60,
  -- Mood thresholds based on FATIGUE (increments by 1 per expedition)
  -- happy: 0..14 (15 expeditions to drop to neutral)
  -- neutral: 15..34 (20 more to drop to sad)
  -- sad: 35+
  happy_to_neutral = 15,
  neutral_to_sad   = 35,

  -- Feed cost
  feed_frag_cost = 1,

  -- Cooldowns after returning (seconds)
  cooldown_by_mood = {
    happy   = 30 * 60,
    neutral = 40 * 60,
    sad     = 50 * 60,
  },

  -- Where pets can roam during expeditions (your provided starter list)
  roam_areas = {
    { area_id="decorshop", x=14, y=10, z=0, label="Decor Shop" },
    { area_id="default",   x=26, y=26, z=0, label="ShaDis_Home" },
    { area_id="rink",   x=24, y=38, z=0, label="Ice_Rink1" },
    { area_id="rink2",   x=24, y=40, z=0, label="Ice_Rink2" },
    { area_id="rink3",   x=24, y=38, z=0, label="Ice_Rink3" },
    { area_id="WCity1",   x=42, y=34, z=3, label="WCity1" },
    { area_id="WCity2",   x=7, y=19, z=0, label="WCity2" },
    { area_id="WCity3",   x=28, y=17, z=0, label="WCity3" },
  },

  -- Reward tables: weights should sum to 100 (you can tweak freely).
  -- NOTE: "nothing" is represented as a small consolation (money) reward.
  reward_tables = {
    neutral = {
      { id="consolation", weight=50 },
      { id="money",       weight=25 },
      { id="card",        weight=15 },
      { id="gp",          weight=7  },
      { id="frag",        weight=3  },
    },
    happy = {
      { id="consolation", weight=45 }, -- 5% better odds than neutral
      { id="money",       weight=27 },
      { id="card",        weight=17 },
      { id="gp",          weight=7  },
      { id="frag",        weight=4  },
    },
    sad = {
      { id="consolation", weight=55 }, -- 5% worse odds than neutral
      { id="money",       weight=24 },
      { id="card",        weight=13 },
      { id="gp",          weight=6  },
      { id="frag",        weight=2  },
    },
  },

  -- Reward parameters
  consolation_money = 10000,
  money_min = 50000,
  money_max = 100000,

  gp_amount   = 1,
  frag_amount = 1,

  -- If the card pool is empty, "card" rolls will fall back to money.
  card_pool = {
    -- EXAMPLES (safe placeholders). Replace with your real pool anytime.
    { name="[UR]S.Skull", description="URare: Summoned Skull - A: 2500 / D: 1200"},
    { name="[UR]B.L.S.", description="URare: Black Luster Soldier - A: 3000 / D: 2500"},
    { name="[UR]Seiyaryu", description="URare: Seiyaryu - A: 2500 / D: 2300"},
    { name="[UR]F.A.REBD", description="FullArt: Red Eyes Black Dragon - A: 2400 / D: 2000"},
    { name="[GR]DMGirl", description="GRare: Dark Magician Girl - A: 2000 / D: 1700"},
    { name="[GR]DMag", description="GRare: Dark Magician - A: 2500 / D: 2100"},
    { name="[GR]B.Sk.D.", description="GRare: Black Skull Dragon - A: 3200 / D: 2500"},
    { name="[GDR]Kbo", description="GDRare: Kuriboh - A: 300 / D: 200" },
    { name="[SR]F.A.V.Lord", description="FullArt: Vampire Lord - A: 2000 / D: 1500"},
    { name="[SR]F.A.DMGirl", description="FullArt: Dark Magician Girl - A: 2000 / D: 1700"},
    { name="[GDR]F.A.DMGirl", description="FullArt: Dark Magician Girl - A: 2000 / D: 1700"},
  },
}

-- Derive duration_sec from duration_minutes (allows easy testing).
EXPEDITION.duration_sec = math.max(1, math.floor((tonumber(EXPEDITION.duration_minutes) or 60) * 60))

-- ====================== Pet Definitions ======================
local PET_DEFS = {
  mettaur  = { name = "Mettaur",  texture = "mettaur.png",  animation = "mettaur.animation",  texture_r2 = "mettaur-r2.png",  texture_r3 = "mettaur-r3.png"  },
  meddy    = { name = "Meddy",    texture = "meddy.png",    animation = "meddy.animation",    texture_r2 = "meddy-r2.png",    texture_r3 = "meddy-r3.png"    },
  ratty    = { name = "Ratty",    texture = "ratty.png",    animation = "ratty.animation",    texture_r2 = "ratty-r2.png",    texture_r3 = "ratty-r3.png"    },
  spooky   = { name = "Spooky",   texture = "spooky.png",   animation = "spooky.animation",   texture_r2 = "spooky-r2.png",   texture_r3 = "spooky-r3.png"   },
  swordy   = { name = "Swordy",   texture = "swordy.png",   animation = "swordy.animation",   texture_r2 = "swordy-r2.png",   texture_r3 = "swordy-r3.png"   },
  moloko   = { name = "Moloko",   texture = "moloko.png",   animation = "moloko.animation",   texture_r2 = "moloko-r2.png",   texture_r3 = "moloko-r3.png"   },
  powie    = { name = "Powie",    texture = "powie.png",    animation = "powie.animation",    texture_r2 = "mowie-r2.png",    texture_r3 = "powie-r3.png"    },
  kabutank = { name = "Kabutank", texture = "kabutank.png", animation = "kabutank.animation", texture_r2 = "kabutank-r2.png", texture_r3 = "kabutank-r3.png" },
  jelly    = { name = "Jelly",    texture = "jelly.png",    animation = "jelly.animation",    texture_r2 = "jelly.png",       texture_r3 = "jelly.png"       },
  volgear  = { name = "Volgear",  texture = "volgear.png",  animation = "volgear.animation",  texture_r2 = "volgear.png",     texture_r3 = "volgear.png"     },
  magtect  = { name = "Magtect",  texture = "magtect.png",  animation = "magtect.animation",  texture_r2 = "magtect.png",     texture_r3 = "magtect.png"     },
  fishy    = { name = "Fishy",    texture = "fishy.png",    animation = "fishy.animation",    texture_r2 = "fishy-r2.png",    texture_r3 = "jelly-r3.png"    },
  piranha  = { name = "Piranha",  texture = "piranha.png",  animation = "piranha.animation",  texture_r2 = "piranha-r2.png",  texture_r3 = "piranha-r3.png"  },
  brushman = { name = "Brushman", texture = "brushman.png", animation = "brushman.animation", texture_r2 = "brushman-r2.png", texture_r3 = "brushman-r3.png" },
  bunny    = { name = "Bunny",    texture = "bunny.png",    animation = "bunny.animation",    texture_r2 = "bunny-r2.png",    texture_r3 = "bunny-r3.png"    },
}

-- ====================== Battle Pet (Take With You) ======================
-- overworld kind -> battle enemy name (resolved by ezencounters.zip enemy_packages)
-- You already have this mapping in (ezencounterszip)entry.lua:
--   MettaurPet = "com.OFC.char.EXE6-001-MetallPet"
-- Chip List --
-- 1  = Recovery30
-- 2  = Recovery50
-- 3  = PanelSteal
-- 4  = AreaSteal
-- 5  = HolyPanel
-- 6  = Sanctuary
-- 7  = Invisible
-- 8  = Shadow
-- 9  = Barrier
-- 10 = Barrier100
local BATTLE_PETS = {
  mettaur = {
    enemy_name = "MettaurPet",
    rank = 1,
    default_starting_hp = 40,
    test_pet_chip_id = nil,
    test_pet_chip_amount = 1,
  },
  ratty = {
    enemy_name = "RattyPet",
    rank = 1,
    default_starting_hp = 40,
    test_pet_chip_id = nil,
    test_pet_chip_amount = 1,
  },
  swordy = {
    enemy_name = "SwordyPet",
    rank = 1,
    default_starting_hp = 40,
    test_pet_chip_id = nil,
    test_pet_chip_amount = 1,
  },
  powie = {
    enemy_name = "PowiePet",
    rank = 1,
    default_starting_hp = 40,
    test_pet_chip_id = nil,
    test_pet_chip_amount = 1,
  },
}

local PET_CHIPS = {
  [1]  = { display_name = "Recovery30", item_name = "PetChip: Recovery30", description = "Pet battle chip: Recovery30" },
  [2]  = { display_name = "Recovery50", item_name = "PetChip: Recovery50", description = "Pet battle chip: Recovery50" },
  [3]  = { display_name = "PanelSteal", item_name = "PetChip: PanelSteal", description = "Pet battle chip: PanelSteal" },
  [4]  = { display_name = "AreaSteal", item_name = "PetChip: AreaSteal", description = "Pet battle chip: AreaSteal" },
  [5]  = { display_name = "HolyPanel", description = "PetChip: HolyPanel", item_name = "Pet battle chip: HolyPanel" },
  [6]  = { display_name = "Sanctuary", item_name = "PetChip: Sanctuary", description = "Pet battle chip: Sanctuary" },
  [7]  = { display_name = "Invisible", item_name = "PetChip: Invisible", description = "Pet battle chip: Invisible" },
  [8]  = { display_name = "Shadow", item_name = "PetChip: Shadow", description = "Pet battle chip: Shadow" },
  [9]  = { display_name = "Barrier", item_name = "PetChip: Barrier", description = "Pet battle chip: Barrier" },
  [10] = { display_name = "Barrier100", item_name = "PetChip: Barrier100", description = "Pet battle chip: Barrier100" },
}

local function _pet_chip_def(chip_id)
  return PET_CHIPS[tonumber(chip_id)]
end

local function _pet_chip_name(chip_id)
  local def = _pet_chip_def(chip_id)
  return def and def.display_name or nil
end

local function _pet_chip_item_name(chip_id)
  local def = _pet_chip_def(chip_id)
  return def and def.item_name or nil
end

local function _pet_chip_id_from_item_name(item_name)
  item_name = tostring(item_name or "")
  for chip_id, def in pairs(PET_CHIPS) do
    if tostring(def.item_name) == item_name then
      return tonumber(chip_id)
    end
  end
  return nil
end

-- Stored in PLAYER memory (we clear it on disconnect/join)
local PLAYER_ARMED_PET_KEY = "armed_pet_v1"
local OWNED_PETS_MEM_KEY   = "owned_pet_instances_v1"
local LEGACY_PET_COUNT_KEYS = { "oncehub_decor_inventory_v1", "decor_inventory" }

local function dbg(...)
  if not EXPEDITION.debug then return end
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts+1] = tostring(select(i, ...))
  end
  print("[pets][exp] "..table.concat(parts, " "))
end

local function _safe_get_player_memory(secret)
  secret = tostring(secret or "")
  if secret == "" then return nil end

  local ok, pmem = pcall(ezmemory.get_player_memory, secret)
  if ok then
    if type(pmem) ~= "table" then
      pmem = {}
    end
    return pmem
  end

  local err = tostring(pmem or "")
  if not err:find("still loading area_memory", 1, true) then
    dbg("pets: get_player_memory failed secret=", secret, " err=", err)
  end
  return nil
end

local function _safe_save_player_memory(secret, pmem)
  secret = tostring(secret or "")
  if secret == "" then return false end

  if ezmemory.set_player_memory then
    local ok = pcall(ezmemory.set_player_memory, secret, pmem)
    if ok then return true end
  end

  if ezmemory.save_player_memory then
    local ok = pcall(ezmemory.save_player_memory, secret, pmem)
    if ok then return true end
  end

  return false
end

local function _resolve_pet_owner_secret(owner_or_pid)
  if owner_or_pid == nil then
    return ""
  end

  if helpers and type(helpers.get_safe_player_secret) == "function" then
    local ok, secret = pcall(helpers.get_safe_player_secret, owner_or_pid)
    if ok and secret and secret ~= "" then
      return tostring(secret)
    end
  end

  return tostring(owner_or_pid or "")
end

local function pet_item_id_from_kind(kind)
  kind = tostring(kind or ""):lower()
  if kind == "" then kind = "mettaur" end
  return "pet_" .. kind
end

local function _default_pet_level()
  return 1
end

local function _default_pet_hp(kind)
  local battle = BATTLE_PETS[tostring(kind or ""):lower()]
  return math.max(1, math.floor(tonumber(battle and battle.default_starting_hp or 40) or 40))
end

local function _default_pet_attack(kind)
  return 1
end

local function _default_pet_xp()
  return 0
end

local PET_BATTLE_XP_DEFAULT    = 5
local PET_EXPEDITION_XP        = PET_BATTLE_XP_DEFAULT * 15
local PET_XP_PER_SKILL_POINT   = PET_BATTLE_XP_DEFAULT * 35 -- 175 XP = 35 normal wins
local PLAYER_PET_XP_NOTIFY_KEY = "pet_xp_notify_v1"
local PET_BATTLES_PER_FATIGUE  = 15
local PET_HAPPY_XP_BONUS       = 1
local PET_SAD_XP_PENALTY       = -1
local PET_MAX_SKILL_POINTS = 31  -- 12 for HP (40->100) + 19 for Attack (5->100)
local PET_MAX_XP = PET_MAX_SKILL_POINTS * PET_XP_PER_SKILL_POINT  -- 7750
local PET_TRAINING_XP      = 75
local PET_TRAINING_MEM_KEY = "pet_training_v1"

local function _coerce_skill_counter(n)
  return math.max(0, math.floor(tonumber(n) or 0))
end

local function _pet_attack_points_from_stat(kind, stat_attack)
  local base = _default_pet_attack(kind)
  return math.max(0, math.floor((tonumber(stat_attack) or base) - base))
end

local function _pet_hp_points_from_stat(kind, stat_hp)
  local base = _default_pet_hp(kind)
  return math.max(0, math.floor(((tonumber(stat_hp) or base) - base) / 5))
end

local function _pet_total_skill_points_from_xp(xp)
  return math.max(0, math.floor((tonumber(xp) or 0) / PET_XP_PER_SKILL_POINT))
end

local function _pet_free_skill_points_for_pet(p)
  if type(p) ~= "table" then return 0 end

  local atk = _coerce_skill_counter(p.attack_points or _pet_attack_points_from_stat(p.kind, p.stat_attack))
  local hp  = _coerce_skill_counter(p.hp_points or _pet_hp_points_from_stat(p.kind, p.stat_hp))

  return math.max(0, _pet_total_skill_points_from_xp(p.xp) - atk - hp)
end

local function _pet_xp_to_next_skill_point(xp)
  local cur = math.max(0, math.floor(tonumber(xp) or 0))
  local rem = cur % PET_XP_PER_SKILL_POINT

  if rem == 0 then
    return PET_XP_PER_SKILL_POINT
  end

  return PET_XP_PER_SKILL_POINT - rem
end

local function _pet_xp_notifications_enabled_from_pmem(pmem)
  if type(pmem) ~= "table" then
    return true
  end

  local v = pmem[PLAYER_PET_XP_NOTIFY_KEY]
  if v == nil then
    return true
  end

  return v == true
end

local function _default_pet_fatigue()
  return 0
end

local function _pet_mood_from_fatigue(fatigue)
  fatigue = tonumber(fatigue) or 0
  if fatigue >= EXPEDITION.neutral_to_sad then
    return "sad"
  elseif fatigue >= EXPEDITION.happy_to_neutral then
    return "neutral"
  end
  return "happy"
end

local function _pet_mood_xp_delta(mood)
  mood = tostring(mood or ""):lower()

  if mood == "happy" then
    return PET_HAPPY_XP_BONUS
  elseif mood == "sad" then
    return PET_SAD_XP_PENALTY
  end

  return 0
end

local function _feed_like_fatigue_relief(fatigue)
  local mood = _pet_mood_from_fatigue(fatigue)
  fatigue = math.max(0, math.floor(tonumber(fatigue) or 0))

  if mood == "sad" then
    return math.max(0, fatigue - (EXPEDITION.neutral_to_sad - EXPEDITION.happy_to_neutral)), true
  elseif mood == "neutral" then
    return math.max(0, fatigue - EXPEDITION.happy_to_neutral), true
  end

  return fatigue, false
end

local function _reduce_battle_fatigue_from_companion_petting(e, bucket_area_id)
  if type(e) ~= "table" then
    return false
  end

  if e.companion_summoned ~= true then
    return false
  end

  local owner_secret = tostring(e.owner_secret or "")
  local uid = tostring(e.uid or "")
  if owner_secret == "" or uid == "" then
    return false
  end

  local owned = _get_owned_pet(owner_secret, uid)
  if not owned then
    return false
  end

  owned.fatigue = math.max(0, math.floor(tonumber(owned.fatigue) or 0))
  owned.battle_fatigue_progress = math.max(0, math.floor(tonumber(owned.battle_fatigue_progress) or 0))

  -- Reduce by exactly 1 "battle fatigue step".
  -- If progress is already 0, borrow from regular fatigue and wrap progress to 14.
  if owned.battle_fatigue_progress > 0 then
    owned.battle_fatigue_progress = owned.battle_fatigue_progress - 1
  elseif owned.fatigue > 0 then
    owned.fatigue = owned.fatigue - 1
    owned.battle_fatigue_progress = PET_BATTLES_PER_FATIGUE - 1
  else
    return false
  end

  e.fatigue = owned.fatigue
  e.battle_fatigue_progress = owned.battle_fatigue_progress

  local store = select(1, _get_player_pets_store(owner_secret))
  if not store or type(store.pets) ~= "table" then
    return false
  end

  store.pets[uid] = owned
  ezmemory.save_player_memory(owner_secret)

  if bucket_area_id and bucket_area_id ~= "" then
    save_bucket(bucket_area_id)
  end

  _sync_live_companion_from_owned(owned)
  return true
end

function _get_player_pets_store(owner_secret)
  owner_secret = tostring(owner_secret or "")
  if owner_secret == "" then return nil, nil end

  local pmem = _safe_get_player_memory(owner_secret)
  if type(pmem) ~= "table" then
    return nil, nil
  end

  local store = pmem[OWNED_PETS_MEM_KEY]

  if type(store) ~= "table" then
    store = { next_num = 1, pets = {} }
    pmem[OWNED_PETS_MEM_KEY] = store
    _safe_save_player_memory(owner_secret, pmem)
  end

  if type(store.pets) ~= "table" then
    store.pets = {}
  end

  store.next_num = math.max(1, math.floor(tonumber(store.next_num) or 1))
  return store, pmem
end

local function _alloc_owned_pet_uid(owner_secret)
  local store = select(1, _get_player_pets_store(owner_secret))
  if not store then
    return tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
  end

  local n = store.next_num or 1
  store.next_num = n + 1
  ezmemory.save_player_memory(owner_secret)

  return string.format("pet-%d-%06d-%d", os.time(), math.random(100000, 999999), n)
end

local function _normalize_owned_pet(p)
  if type(p) ~= "table" then return nil end

  p.uid = tostring(p.uid or "")
  p.kind = tostring(p.kind or "mettaur"):lower()
  if p.kind == "" then p.kind = "mettaur" end

  p.item_id = tostring(p.item_id or pet_item_id_from_kind(p.kind))
  p.level = math.max(1, math.floor(tonumber(p.level) or _default_pet_level()))
  p.stat_hp = math.max(1, math.floor(tonumber(p.stat_hp) or _default_pet_hp(p.kind)))
  p.stat_attack = math.max(1, math.floor(tonumber(p.stat_attack) or _default_pet_attack(p.kind)))
  p.attack_points = _coerce_skill_counter(p.attack_points or _pet_attack_points_from_stat(p.kind, p.stat_attack))
  p.hp_points = _coerce_skill_counter(p.hp_points or _pet_hp_points_from_stat(p.kind, p.stat_hp))
  p.xp = math.max(0, math.floor(tonumber(p.xp) or _default_pet_xp()))
  p.fatigue = math.max(0, math.floor(tonumber(p.fatigue) or _default_pet_fatigue()))
  p.battle_fatigue_progress = math.max(0, math.floor(tonumber(p.battle_fatigue_progress) or 0))
  p.nickname = tostring(p.nickname or "")
  p.pet_chip_id = tonumber(p.pet_chip_id)
  if p.pet_chip_id and not PET_CHIPS[p.pet_chip_id] then
    p.pet_chip_id = nil
  end

  p.pet_chip_amount = math.max(1, math.floor(tonumber(p.pet_chip_amount or 1) or 1))
  if not p.pet_chip_id then
    p.pet_chip_amount = 1
  end

  if type(p.placement) ~= "table" then
    p.placement = nil
  else
    p.placement.bucket_area_id = tostring(p.placement.bucket_area_id or "")
    p.placement.oncehub_key    = tostring(p.placement.oncehub_key or "")
    p.placement.area_id        = tostring(p.placement.area_id or "")
    p.placement.x              = tonumber(p.placement.x or 0) or 0
    p.placement.y              = tonumber(p.placement.y or 0) or 0
    p.placement.z              = tonumber(p.placement.z or 0) or 0
  end

  return p
end

local function _award_owned_pet_xp_for_secret(secret, uid, amount)
  secret = tostring(secret or "")
  uid = tostring(uid or "")
  amount = math.max(0, math.floor(tonumber(amount) or 0))

  if secret == "" or uid == "" or amount <= 0 then
    return false, 0, 0
  end

  local pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then
    return false, 0, 0
  end

  local store = pmem[OWNED_PETS_MEM_KEY]
  if type(store) ~= "table" or type(store.pets) ~= "table" then
    return false, 0, 0
  end

  local p = _normalize_owned_pet(store.pets[uid])
  if type(p) ~= "table" then
    return false, 0, 0
  end

  local old_total = _pet_total_skill_points_from_xp(p.xp)

  p.xp = math.min(PET_MAX_XP, math.max(0, math.floor(tonumber(p.xp or 0) or 0) + amount))

  local new_total = _pet_total_skill_points_from_xp(p.xp)

  store.pets[uid] = p
  pmem[OWNED_PETS_MEM_KEY] = store
  _safe_save_player_memory(secret, pmem)

  return true, p.xp, math.max(0, new_total - old_total)
end

function _get_owned_pet(owner_secret, uid)
  local store = select(1, _get_player_pets_store(owner_secret))
  if not store then return nil end

  uid = tostring(uid or "")
  local p = store.pets and store.pets[uid] or nil
  if type(p) ~= "table" then return nil end

  p = _normalize_owned_pet(p)
  store.pets[uid] = p
  return p
end

function _sync_live_companion_from_owned(p)
  if type(p) ~= "table" then return end

  local uid = tostring(p.uid or "")
  if uid == "" then return end

  local live = companion_live_entries and companion_live_entries[uid]
  if type(live) ~= "table" then
    return
  end

  live.stat_hp = p.stat_hp
  live.stat_attack = p.stat_attack
  live.attack_points = p.attack_points
  live.hp_points = p.hp_points
  live.xp = p.xp
  live.fatigue = p.fatigue
  live.battle_fatigue_progress = p.battle_fatigue_progress
  live.nickname = tostring(p.nickname or live.nickname or "")
end

local function _count_owned_pet_instances(owner_secret, kind)
  local store = select(1, _get_player_pets_store(owner_secret))
  if not store then return 0 end

  kind = tostring(kind or ""):lower()
  local n = 0

  for uid, raw in pairs(store.pets or {}) do
    local p = _normalize_owned_pet(raw)
    store.pets[uid] = p
    if kind == "" or p.kind == kind then
      n = n + 1
    end
  end

  return n
end

local function _legacy_owned_pet_count(owner_secret, item_id)
  local pmem = _safe_get_player_memory(owner_secret)
  if type(pmem) ~= "table" then
    return 0
  end

  local best = 0

  for _, key in ipairs(LEGACY_PET_COUNT_KEYS) do
    local inv = pmem[key]
    if type(inv) == "table" then
      best = math.max(best, tonumber(inv[item_id] or 0) or 0)
    end
  end

  return math.max(0, best)
end

local function _find_first_unplaced_owned_pet(owner_secret, kind, preferred_uid)
  owner_secret = tostring(owner_secret or "")
  kind = tostring(kind or ""):lower()
  preferred_uid = tostring(preferred_uid or "")

  if preferred_uid ~= "" then
    local p = _get_owned_pet(owner_secret, preferred_uid)
    if p and p.kind == kind and p.placement == nil then
      return p
    end
    return nil
  end

  local store = select(1, _get_player_pets_store(owner_secret))
  if not store then return nil end

  local best = nil
  for uid, raw in pairs(store.pets or {}) do
    local p = _normalize_owned_pet(raw)
    store.pets[uid] = p

    if p.kind == kind and p.placement == nil then
      if not best or tostring(p.uid) < tostring(best.uid) then
        best = p
      end
    end
  end

  return best
end

local function _attach_owned_pet_to_entry(e, bucket_area_id, oncehub_key)
  local owner_secret = tostring(e.owner_secret or "")
  if owner_secret == "" then return end

  local store = select(1, _get_player_pets_store(owner_secret))
  if not store then return end

  local uid = tostring(e.uid or "")
  local dirty = false

  if uid == "" then
    uid = _alloc_owned_pet_uid(owner_secret)
    e.uid = uid
    dirty = true
  end

  local p = store.pets[uid]
  if type(p) ~= "table" then
    p = {
      uid = uid,
      kind = e.kind,
      item_id = pet_item_id_from_kind(e.kind),
      level = e.level,
      stat_hp = e.stat_hp,
      xp = e.xp,
      stat_attack = e.stat_attack,
      fatigue = e.fatigue,
      battle_fatigue_progress = e.battle_fatigue_progress,
      nickname = e.nickname,
      attack_points = e.attack_points,
      hp_points = e.hp_points,
      placement = {
        bucket_area_id = tostring(bucket_area_id or e.bucket_area_id or ""),
        oncehub_key    = tostring(oncehub_key or e.oncehub_key or ""),
        area_id        = tostring(e.home_area_id or e.area_id or ""),
        x = tonumber(e.home_x or e.x or 0) or 0,
        y = tonumber(e.home_y or e.y or 0) or 0,
        z = tonumber(e.home_z or e.z or 0) or 0,
      }
    }
    p = _normalize_owned_pet(p)
    store.pets[uid] = p
    dirty = true
  else
    p = _normalize_owned_pet(p)
    store.pets[uid] = p

    if type(p.placement) ~= "table"
      or tostring(p.placement.bucket_area_id or "") ~= tostring(bucket_area_id or e.bucket_area_id or "")
      or tostring(p.placement.oncehub_key or "") ~= tostring(oncehub_key or e.oncehub_key or "")
    then
      p.placement = {
        bucket_area_id = tostring(bucket_area_id or e.bucket_area_id or ""),
        oncehub_key    = tostring(oncehub_key or e.oncehub_key or ""),
        area_id        = tostring(e.home_area_id or e.area_id or ""),
        x = tonumber(e.home_x or e.x or 0) or 0,
        y = tonumber(e.home_y or e.y or 0) or 0,
        z = tonumber(e.home_z or e.z or 0) or 0,
      }
      store.pets[uid] = p
      dirty = true
    end
  end

  -- owned record is authoritative for persistent stats
  e.kind        = p.kind
  e.level       = p.level
  e.stat_hp     = p.stat_hp
  e.stat_attack = p.stat_attack
  e.attack_points = p.attack_points
  e.hp_points     = p.hp_points
  e.xp          = p.xp
  e.fatigue     = p.fatigue
  e.battle_fatigue_progress = p.battle_fatigue_progress
  e.nickname    = tostring(p.nickname or "")
  e.pet_chip_id     = p.pet_chip_id
  e.pet_chip_amount = p.pet_chip_amount

  if dirty then
    ezmemory.save_player_memory(owner_secret)
  end
end

local function _save_owned_pet_from_entry(e, clear_placement)
  local owner_secret = tostring(e.owner_secret or "")
  if owner_secret == "" then return end

  local store = select(1, _get_player_pets_store(owner_secret))
  if not store then return end

  local uid = tostring(e.uid or "")
  if uid == "" then
    uid = _alloc_owned_pet_uid(owner_secret)
    e.uid = uid
  end

  local p = store.pets[uid] or {}
  p.uid         = uid
  p.kind        = tostring(e.kind or p.kind or "mettaur"):lower()
  p.item_id     = tostring(p.item_id or pet_item_id_from_kind(p.kind))
  p.level       = math.max(1, math.floor(tonumber(e.level or p.level or _default_pet_level())))
  p.stat_hp     = math.max(1, math.floor(tonumber(e.stat_hp or p.stat_hp or _default_pet_hp(p.kind))))
  p.stat_attack = math.max(1, math.floor(tonumber(e.stat_attack or p.stat_attack or _default_pet_attack(p.kind))))
  p.attack_points = _coerce_skill_counter(e.attack_points or p.attack_points or _pet_attack_points_from_stat(p.kind, e.stat_attack))
  p.hp_points     = _coerce_skill_counter(e.hp_points or p.hp_points or _pet_hp_points_from_stat(p.kind, e.stat_hp))
  p.xp          = math.max(0, math.floor(tonumber(e.xp or p.xp or _default_pet_xp())))
  p.fatigue     = math.max(0, math.floor(tonumber(e.fatigue or p.fatigue or _default_pet_fatigue())))
  p.battle_fatigue_progress = math.max(0, math.floor(tonumber(e.battle_fatigue_progress or p.battle_fatigue_progress or 0)))
  p.nickname    = tostring(e.nickname or p.nickname or "")
  p.pet_chip_id = tonumber(e.pet_chip_id)
  if p.pet_chip_id and not PET_CHIPS[p.pet_chip_id] then
    p.pet_chip_id = nil
  end

  p.pet_chip_amount = math.max(1, math.floor(tonumber(e.pet_chip_amount or p.pet_chip_amount or 1) or 1))
  if not p.pet_chip_id then
    p.pet_chip_amount = 1
  end

  if clear_placement then
    p.placement = nil
  else
    p.placement = {
      bucket_area_id = tostring(e.bucket_area_id or ""),
      oncehub_key    = tostring(e.oncehub_key or ""),
      area_id        = tostring(e.home_area_id or e.area_id or ""),
      x = tonumber(e.home_x or e.x or 0) or 0,
      y = tonumber(e.home_y or e.y or 0) or 0,
      z = tonumber(e.home_z or e.z or 0) or 0,
    }
  end

  store.pets[uid] = _normalize_owned_pet(p)
  ezmemory.save_player_memory(owner_secret)
end

function pets.ensure_player_pet_ids(owner_or_pid)
  local owner_secret = _resolve_pet_owner_secret(owner_or_pid)
  if owner_secret == "" then return false end

  local store = select(1, _get_player_pets_store(owner_secret))
  if not store then return false end

  local dirty = false

  for kind, _ in pairs(PET_DEFS) do
    local want = _legacy_owned_pet_count(owner_secret, pet_item_id_from_kind(kind))
    local have = _count_owned_pet_instances(owner_secret, kind)

    while have < want do
      local uid = _alloc_owned_pet_uid(owner_secret)
      store.pets[uid] = _normalize_owned_pet({
        uid = uid,
        kind = kind,
        item_id = pet_item_id_from_kind(kind),
      })
      have = have + 1
      dirty = true
    end
  end

  if dirty then
    ezmemory.save_player_memory(owner_secret)
  end

  return true
end

function pets.list_owned_pets(owner_or_pid, opts)
  local owner_secret = _resolve_pet_owner_secret(owner_or_pid)
  local store = select(1, _get_player_pets_store(owner_secret))
  local out = {}
  if not store then return out end

  local want_kind = opts and tostring(opts.kind or ""):lower() or ""
  local only_unplaced = opts and opts.only_unplaced == true

  for uid, raw in pairs(store.pets or {}) do
    local p = _normalize_owned_pet(raw)
    store.pets[uid] = p

    local include = true
    if want_kind ~= "" and p.kind ~= want_kind then include = false end
    if only_unplaced and p.placement ~= nil then include = false end

    if include then
      out[#out+1] = {
        uid = p.uid,
        kind = p.kind,
        item_id = p.item_id,
        level = p.level,
        stat_hp = p.stat_hp,
        stat_attack = p.stat_attack,
        fatigue = p.fatigue,
        mood = _pet_mood_from_fatigue(p.fatigue),
        nickname = tostring(p.nickname or ""),
        placed = p.placement ~= nil,
        placement = p.placement,
        pet_chip_id = p.pet_chip_id,
        pet_chip_amount = p.pet_chip_amount,
        xp = p.xp,
        attack_points = p.attack_points,
        hp_points = p.hp_points,
      }
    end
  end

  table.sort(out, function(a, b)
    if a.kind == b.kind then
      return tostring(a.uid) < tostring(b.uid)
    end
    return tostring(a.kind) < tostring(b.kind)
  end)

  return out
end

function pets.get_armed_pet_info(owner_or_pid)
  local owner_secret = _resolve_pet_owner_secret(owner_or_pid)
  if owner_secret == "" then
    return nil
  end

  local pmem = _safe_get_player_memory(owner_secret)
  if type(pmem) ~= "table" then
    return nil
  end

  local armed = pmem[PLAYER_ARMED_PET_KEY]
  if type(armed) ~= "table" then
    return nil
  end

  local uid  = tostring(armed.uid or "")
  local kind = tostring(armed.kind or "mettaur"):lower()
  if kind == "" then kind = "mettaur" end

  local battle_def = BATTLE_PETS[kind]
  local pet_def    = PET_DEFS[kind] or {}
  local owned      = nil

  if uid ~= "" then
    owned = _get_owned_pet(owner_secret, uid)
  end

  local base_name = tostring(pet_def.name or kind:gsub("^%l", string.upper))
  local nickname  = ""

  if owned and tostring(owned.nickname or "") ~= "" then
    nickname = tostring(owned.nickname or "")
  end

  local display_name = (nickname ~= "" and nickname) or base_name

  local fatigue = _default_pet_fatigue()
  local xp = 0
  local battle_fatigue_progress = 0

  if owned then
    fatigue = tonumber(owned.fatigue) or fatigue
    xp = math.max(0, math.floor(tonumber(owned.xp) or 0))
    battle_fatigue_progress = math.max(0, math.floor(tonumber(owned.battle_fatigue_progress) or 0))
  end

  local mood = _pet_mood_from_fatigue(fatigue)
  local can_fight = battle_def ~= nil

  local hp = math.max(1, math.floor(tonumber(
    (owned and owned.stat_hp)
    or armed.starting_hp
    or (battle_def and battle_def.default_starting_hp)
    or _default_pet_hp(kind)
  ) or _default_pet_hp(kind)))

  local rank = clamp_pet_battle_rank(
    (owned and owned.stat_attack)
    or armed.rank
    or (battle_def and battle_def.rank)
    or _default_pet_attack(kind)
  )

  local attack = rank * 5

  local chip_id = tonumber(
    (owned and owned.pet_chip_id)
    or armed.pet_chip_id
    or nil
  )

  local chip_amount = math.max(1, math.floor(tonumber(
    (owned and owned.pet_chip_amount)
    or armed.pet_chip_amount
    or 1
  ) or 1))

  if not chip_id then
    chip_amount = 1
  end

  local attack_points = owned
    and _coerce_skill_counter(owned.attack_points or _pet_attack_points_from_stat(kind, owned.stat_attack))
    or _coerce_skill_counter(_pet_attack_points_from_stat(kind, rank))

  local hp_points = owned
    and _coerce_skill_counter(owned.hp_points or _pet_hp_points_from_stat(kind, owned.stat_hp))
    or _coerce_skill_counter(_pet_hp_points_from_stat(kind, hp))

  local total_skill_points = _pet_total_skill_points_from_xp(xp)
  local spent_skill_points = attack_points + hp_points
  local available_skill_points = math.max(0, total_skill_points - spent_skill_points)

  return {
    uid = uid,
    kind = kind,
    base_name = base_name,
    nickname = nickname,
    display_name = display_name,
    mood = mood,
    can_fight = can_fight,
    hp = hp,
    xp = xp,
    fatigue = math.max(0, math.floor(tonumber(fatigue) or 0)),
    battle_fatigue_progress = battle_fatigue_progress,
    rank = rank,
    attack = attack,
    attack_points = attack_points,
    hp_points = hp_points,
    total_skill_points = total_skill_points,
    spent_skill_points = spent_skill_points,
    available_skill_points = available_skill_points,
    xp_to_next_skill_point = _pet_xp_to_next_skill_point(xp),
    xp_per_skill_point = PET_XP_PER_SKILL_POINT,
    xp_notifications_enabled = _pet_xp_notifications_enabled_from_pmem(pmem),
    pet_chip_id = chip_id,
    pet_chip_amount = chip_amount,
    enemy_name = tostring(armed.enemy_name or (battle_def and battle_def.enemy_name) or ""),
    bucket_area_id = tostring(armed.bucket_area_id or ""),
    summoned = armed.summoned == true,
  }
end

function pets.set_pet_xp_notifications_enabled(owner_or_pid, enabled)
  local secret = _resolve_pet_owner_secret(owner_or_pid)
  if secret == "" then
    return false, false
  end

  local pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then
    return false, false
  end

  pmem[PLAYER_PET_XP_NOTIFY_KEY] = enabled == true
  _safe_save_player_memory(secret, pmem)

  return true, pmem[PLAYER_PET_XP_NOTIFY_KEY]
end

function pets.award_owned_pet_xp(owner_or_pid, uid, amount)
  local secret = _resolve_pet_owner_secret(owner_or_pid)
  return _award_owned_pet_xp_for_secret(secret, uid, amount)
end

function pets.award_armed_pet_battle_xp(pid, amount, expected_uid)
  local secret = helpers.get_safe_player_secret(pid)
  if not secret or secret == "" then
    return false, 0, 0, 0, "neutral"
  end

  amount = math.max(0, math.floor(tonumber(amount) or 0))
  if amount <= 0 then
    return false, 0, 0, 0, "neutral"
  end

  local pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then
    return false, 0, 0, 0, "neutral"
  end

  local armed = pmem[PLAYER_ARMED_PET_KEY]
  if type(armed) ~= "table" then
    return false, 0, 0, 0, "neutral"
  end

  local kind = tostring(armed.kind or ""):lower()
  if kind == "" or not BATTLE_PETS[kind] or tostring(armed.enemy_name or "") == "" then
    return false, 0, 0, 0, "neutral"
  end

  local uid = tostring(armed.uid or "")
  if uid == "" then
    return false, 0, 0, 0, "neutral"
  end

  expected_uid = tostring(expected_uid or "")
  if expected_uid ~= "" and expected_uid ~= uid then
    return false, 0, 0, 0, "neutral"
  end

  local store = pmem[OWNED_PETS_MEM_KEY]
  if type(store) ~= "table" or type(store.pets) ~= "table" then
    return false, 0, 0, 0, "neutral"
  end

  local p = _normalize_owned_pet(store.pets[uid])
  if type(p) ~= "table" then
    return false, 0, 0, 0, "neutral"
  end

  local mood = _pet_mood_from_fatigue(p.fatigue)
  local effective_amount = amount

  if amount > 0 then
    effective_amount = math.max(0, amount + _pet_mood_xp_delta(mood))
  end

  local current_xp = math.max(0, math.floor(tonumber(p.xp) or 0))
  if current_xp >= PET_MAX_XP then
    return true, current_xp, 0, 0, mood
  end

  if effective_amount <= 0 then
    return true, math.max(0, math.floor(tonumber(p.xp) or 0)), 0, 0, mood
  end

  local notify = _pet_xp_notifications_enabled_from_pmem(pmem)
  local old_total = _pet_total_skill_points_from_xp(p.xp)

  p.xp = math.min(PET_MAX_XP, math.max(0, math.floor(tonumber(p.xp or 0) or 0) + effective_amount))

  local new_total = _pet_total_skill_points_from_xp(p.xp)
  local skill_gained = math.max(0, new_total - old_total)

  store.pets[uid] = p
  pmem[OWNED_PETS_MEM_KEY] = store
  _safe_save_player_memory(secret, pmem)
  _sync_live_companion_from_owned(p)

  if notify and Net and Net.message_player then
    local msg = ("Your pet gained %d XP."):format(effective_amount)
    if skill_gained > 0 then
      msg = msg .. (" %d skill point%s available."):format(skill_gained, skill_gained == 1 and "" or "s")
    end
    pcall(Net.message_player, pid, msg)
  end

  return true, p.xp, skill_gained, effective_amount, mood
end

function pets.register_armed_pet_battle_completion(pid, expected_uid)
  local secret = helpers.get_safe_player_secret(pid)
  if not secret or secret == "" then
    return false, 0, 0, 0, "neutral"
  end

  local pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then
    return false, 0, 0, 0, "neutral"
  end

  local armed = pmem[PLAYER_ARMED_PET_KEY]
  if type(armed) ~= "table" then
    return false, 0, 0, 0, "neutral"
  end

  local kind = tostring(armed.kind or ""):lower()
  if kind == "" or not BATTLE_PETS[kind] or tostring(armed.enemy_name or "") == "" then
    return false, 0, 0, 0, "neutral"
  end

  local uid = tostring(armed.uid or "")
  if uid == "" then
    return false, 0, 0, 0, "neutral"
  end

  expected_uid = tostring(expected_uid or "")
  if expected_uid ~= "" and expected_uid ~= uid then
    return false, 0, 0, 0, "neutral"
  end

  local store = pmem[OWNED_PETS_MEM_KEY]
  if type(store) ~= "table" or type(store.pets) ~= "table" then
    return false, 0, 0, 0, "neutral"
  end

  local p = _normalize_owned_pet(store.pets[uid])
  if type(p) ~= "table" then
    return false, 0, 0, 0, "neutral"
  end

  p.battle_fatigue_progress = math.max(0, math.floor(tonumber(p.battle_fatigue_progress) or 0)) + 1

  local fatigue_added = 0
  while p.battle_fatigue_progress >= PET_BATTLES_PER_FATIGUE do
    p.battle_fatigue_progress = p.battle_fatigue_progress - PET_BATTLES_PER_FATIGUE
    p.fatigue = math.max(0, math.floor(tonumber(p.fatigue or 0) or 0) + 1)
    fatigue_added = fatigue_added + 1
  end

  store.pets[uid] = p
  pmem[OWNED_PETS_MEM_KEY] = store
  _safe_save_player_memory(secret, pmem)
  _sync_live_companion_from_owned(p)

  return true, p.battle_fatigue_progress, fatigue_added, p.fatigue, _pet_mood_from_fatigue(p.fatigue)
end

function pets.feed_armed_pet(pid)
  local secret = helpers.get_safe_player_secret(pid)
  if not secret or secret == "" then
    return false, "Pet owner not found."
  end

  local pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then
    return false, "Pet memory isn't ready yet."
  end

  local armed = pmem[PLAYER_ARMED_PET_KEY]
  if type(armed) ~= "table" then
    return false, "No companion pet selected."
  end

  local uid = tostring(armed.uid or "")
  if uid == "" then
    return false, "Missing pet id."
  end

  local store = pmem[OWNED_PETS_MEM_KEY]
  if type(store) ~= "table" or type(store.pets) ~= "table" then
    return false, "Pet data wasn't found."
  end

  local p = _normalize_owned_pet(store.pets[uid])
  if type(p) ~= "table" then
    return false, "Pet not found."
  end

  local mood = _pet_mood_from_fatigue(p.fatigue)
  if mood == "happy" then
    return false, "Your pet is already happy."
  end

  if not ezmemory.spend_player_fragments then
    return false, "Fragments support isn't installed in ezmemory yet."
  end

  local cost = tonumber(EXPEDITION.feed_frag_cost) or 1
  if not ezmemory.spend_player_fragments(pid, cost) then
    return false, "Not enough BugFrags."
  end

  p.fatigue = select(1, _feed_like_fatigue_relief(p.fatigue))
  store.pets[uid] = p
  pmem[OWNED_PETS_MEM_KEY] = store
  _safe_save_player_memory(secret, pmem)
  _sync_live_companion_from_owned(p)

  return true, "You fed your virus. It seems happier."
end

function pets.relieve_pet_fatigue_from_petting(pid, uid, owner_secret)
  local actor_secret = helpers.get_safe_player_secret(pid)
  owner_secret = tostring(owner_secret or "")
  uid = tostring(uid or "")

  if actor_secret == "" or owner_secret == "" or uid == "" then
    return false, false, 0, "neutral"
  end

  if actor_secret == owner_secret then
    return true, false, 0, "neutral"
  end

  local store, pmem = _get_player_pets_store(owner_secret)
  if not store or type(pmem) ~= "table" then
    return false, false, 0, "neutral"
  end

  local p = _normalize_owned_pet(store.pets[uid])
  if type(p) ~= "table" then
    return false, false, 0, "neutral"
  end

  local old_fatigue = math.max(0, math.floor(tonumber(p.fatigue) or 0))
  p.fatigue = math.max(0, old_fatigue - 1)

  store.pets[uid] = p
  pmem[OWNED_PETS_MEM_KEY] = store
  _safe_save_player_memory(owner_secret, pmem)
  _sync_live_companion_from_owned(p)

  return true, p.fatigue < old_fatigue, p.fatigue, _pet_mood_from_fatigue(p.fatigue)
end

function pets.consume_armed_pet_battle_chip(pid, expected_uid)
  local secret = helpers.get_safe_player_secret(pid)
  if not secret or secret == "" then
    return false, "no_owner"
  end

  local pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then
    return false, "no_memory"
  end

  local armed = pmem[PLAYER_ARMED_PET_KEY]
  if type(armed) ~= "table" then
    return false, "no_armed_pet"
  end

  local uid = tostring(armed.uid or "")
  if uid == "" then
    return false, "no_uid"
  end

  expected_uid = tostring(expected_uid or "")
  if expected_uid ~= "" and expected_uid ~= uid then
    return false, "uid_mismatch"
  end

  local kind = tostring(armed.kind or ""):lower()
  if kind == "" or not BATTLE_PETS[kind] or tostring(armed.enemy_name or "") == "" then
    return false, "not_battle_pet"
  end

  local chip_id = tonumber(armed.pet_chip_id)
  if not chip_id or chip_id < 1 then
    return false, "no_chip"
  end

  local item_name = _pet_chip_item_name(chip_id)
  if not item_name or item_name == "" then
    return false, "bad_chip_item"
  end

  local have_qty = tonumber(ezmemory.count_player_item(pid, item_name) or 0) or 0
  if have_qty < 1 then
    pcall(pets.unequip_chip_from_pet, pid, uid)
    return false, "out_of_stock"
  end

  local ok_remove, remaining = pcall(ezmemory.remove_player_item, pid, item_name, 1)
  if not ok_remove then
    return false, "remove_failed"
  end

  remaining = tonumber(remaining or 0) or 0
  if remaining < 1 then
    pcall(pets.unequip_chip_from_pet, pid, uid)
  end

  return true, chip_id, remaining
end

function pets.grant_owned_pet(owner_or_pid, item_id, qty)
  local owner_secret = _resolve_pet_owner_secret(owner_or_pid)
  if owner_secret == "" then return {} end

  item_id = tostring(item_id or "")
  if item_id:sub(1, 4) ~= "pet_" then return {} end

  local kind = item_id:gsub("^pet_", ""):lower()
  local store = select(1, _get_player_pets_store(owner_secret))
  local created = {}

  qty = math.max(1, math.floor(tonumber(qty) or 1))
  for _ = 1, qty do
    local uid = _alloc_owned_pet_uid(owner_secret)
    local p = _normalize_owned_pet({
      uid = uid,
      kind = kind,
      item_id = item_id,
    })
    store.pets[uid] = p
    created[#created + 1] = p
  end

  ezmemory.save_player_memory(owner_secret)
  return created
end

local function build_paths(kind, stat_attack)
  local def = PET_DEFS[kind]
  if not def then return nil end
  local rank = math.floor(tonumber(stat_attack) or 1)
  local tex = def.texture
  if rank >= 20 and def.texture_r3 then
    tex = def.texture_r3
  elseif rank >= 11 and def.texture_r2 then
    tex = def.texture_r2
  end
  return def,
    ("/server/assets/pets/" .. tex),
    ("/server/assets/pets/" .. def.animation)
end

-- Direction suffix used for animation state names like WALK_UR, IDLE_DL.
local DIR_SUFFIX = {
  ["Up Right"] = "UR",
  ["Up Left"]  = "UL",
  ["Down Right"] = "DR",
  ["Down Left"]  = "DL",
}

-- Isometric tile delta mapping.
local DIR_VECTORS = {
  ["Up Left"]    = { -1,  0 },
  ["Up Right"]   = {  0, -1 },
  ["Down Left"]  = {  0,  1 },
  ["Down Right"] = {  1,  0 },
}

local function dir_to_vec(dir)
  local v = DIR_VECTORS[dir]
  if not v then return 0, 0 end
  return v[1], v[2]
end

local function nearest_tile(n)
  if n >= 0 then return math.floor(n + 0.5) end
  return math.ceil(n - 0.5)
end

local function now_seed_rng()
  pcall(function() math.randomseed(os.time() % 2147483647) end)
end

-- Ask custom.lua to ignore the very next board_close for this player (one-shot)
-- Needed because custom.lua listens for board_close and may "consume" the click that closed our board.
local function _mark_ignore_next_close(pid, reason)
  -- Some servers have a custom.lua "click guardian" that will consume board events.
  -- OnceHub uses _guard_ignore_next_close(); some servers also expose guards for selection events.
  if not _G then return end
  local why = reason or "pets"
  if _G._guard_ignore_next_close then
    _G._guard_ignore_next_close(pid, why)
  end
  if _G._guard_ignore_next_post_selection then
    _G._guard_ignore_next_post_selection(pid, why)
  end
  if _G._guard_ignore_next_post then
    _G._guard_ignore_next_post(pid, why)
  end
  if _G._guard_ignore_next_selection then
    _G._guard_ignore_next_selection(pid, why)
  end
end

-- Wrapper: mark ignore + open board (returns the board handle like Net.open_board)
local function _open_menu_ignoring_custom(pid, title, color, posts, reason)
  _mark_ignore_next_close(pid, reason or ("pets:"..tostring(title)))
  dbg("open_menu:", title, "reason=", reason or "")
  return ezmenus.open_menu(pid, title, color, posts)
end

local function _now() return os.time() end

local function _fmt_time_left(sec)
  sec = math.max(0, math.floor(tonumber(sec) or 0))
  local m = math.floor(sec / 60)
  local s = sec % 60
  if m >= 60 then
    local h = math.floor(m / 60)
    m = m % 60
    return string.format("%dh %dm", h, m)
  end
  return string.format("%dm %ds", m, s)
end

-- ====================== Memory helpers ======================
local function ensure_bucket_mem(bucket_area_id)
  local mem = ezmemory.get_area_memory(bucket_area_id) or ezmemory.get_area_memory(bucket_area_id)
  if not mem then error("pets.lua: Failed to initialize area memory for "..tostring(bucket_area_id)) end
  if mem.oncehub_pets_v1 == nil then mem.oncehub_pets_v1 = {} end
  if mem.oncehub_pet_expeditions_v1 == nil then mem.oncehub_pet_expeditions_v1 = {} end
  -- Pet stats that should survive remove/re-summon (ex: fatigue / mood)
  if mem.oncehub_pet_stats_v1 == nil then mem.oncehub_pet_stats_v1 = {} end
  return mem
end

local function load_pet_list(bucket_area_id, oncehub_key)
  local mem = ensure_bucket_mem(bucket_area_id)
  local t = mem.oncehub_pets_v1[oncehub_key]
  if t == nil then
    t = {}
    mem.oncehub_pets_v1[oncehub_key] = t
    pcall(function() ezmemory.save_area_memory(bucket_area_id) end)
  end
  return t, mem
end

function save_bucket(bucket_area_id)
  pcall(function() ezmemory.save_area_memory(bucket_area_id) end)
end

-- ====================== Pet stats persistence ======================
-- Keep fatigue/mood even if the renter removes & re-summons the pet.
-- Stored in bucket area memory:
--   mem.oncehub_pet_stats_v1[owner_secret][kind].fatigue = <int>
local function _ensure_pet_stats(bucket_area_id)
  local mem = ensure_bucket_mem(bucket_area_id)
  if type(mem.oncehub_pet_stats_v1) ~= "table" then
    mem.oncehub_pet_stats_v1 = {}
  end
  return mem.oncehub_pet_stats_v1
end

local function _get_saved_fatigue(bucket_area_id, owner_secret, kind)
  if not owner_secret or owner_secret == "" then return nil end
  kind = tostring(kind or ""):lower()
  local stats = _ensure_pet_stats(bucket_area_id)
  local by_owner = stats[owner_secret]
  if type(by_owner) ~= "table" then return nil end
  local rec = by_owner[kind]
  if type(rec) ~= "table" then return nil end
  return tonumber(rec.fatigue)
end

local function _set_saved_fatigue(bucket_area_id, owner_secret, kind, fatigue)
  if not owner_secret or owner_secret == "" then return end
  kind = tostring(kind or ""):lower()
  local stats = _ensure_pet_stats(bucket_area_id)
  local by_owner = stats[owner_secret]
  if type(by_owner) ~= "table" then
    by_owner = {}
    stats[owner_secret] = by_owner
  end
  local rec = by_owner[kind]
  if type(rec) ~= "table" then
    rec = {}
    by_owner[kind] = rec
  end
  rec.fatigue = math.max(0, math.floor(tonumber(fatigue) or 0))
  pcall(function() ezmemory.save_area_memory(bucket_area_id) end)
end

local function _get_hp_lease(bucket_area_id, oncehub_key)
  local mem = ensure_bucket_mem(bucket_area_id)
  return mem.onceitems and mem.onceitems[oncehub_key] or nil
end

local function _get_hp_owner_secret(bucket_area_id, oncehub_key)
  local lease = _get_hp_lease(bucket_area_id, oncehub_key)
  return lease and lease.owner_secret or nil
end

local function _get_hp_expires_at(bucket_area_id, oncehub_key)
  local lease = _get_hp_lease(bucket_area_id, oncehub_key)
  return lease and tonumber(lease.expires_at) or nil
end

-- Normalize / migrate an entry in-place (keeps old pets working).
local function normalize_entry(e, bucket_area_id, oncehub_key)
  if type(e) ~= "table" then return nil end

  e.uid  = tostring(e.uid or "")
  e.kind = tostring(e.kind or ""):lower()
  if e.kind == "" then e.kind = "mettaur" end

  e.bucket_area_id = e.bucket_area_id or bucket_area_id
  e.oncehub_key    = e.oncehub_key or oncehub_key

  -- Owner info: older saves stored "secret" as boolean. Recover from current lease if possible.
  if type(e.owner_secret) ~= "string" or e.owner_secret == "" then
    local s = _get_hp_owner_secret(bucket_area_id, oncehub_key)
    if type(s) == "string" and s ~= "" then
      e.owner_secret = s
    else
      e.owner_secret = e.owner_secret or ""
    end
  end
  if type(e.owner_name) ~= "string" or e.owner_name == "" then
    e.owner_name = e.owner_name or ""
  end

  -- Fatigue: migrate from old "emotion" if present.
  if e.fatigue == nil then
    local emo = tostring(e.emotion or "happy")
    if emo == "neutral" then
      e.fatigue = EXPEDITION.happy_to_neutral
    elseif emo == "angry" or emo == "sad" then
      e.fatigue = EXPEDITION.neutral_to_sad
    else
      e.fatigue = 0
    end
  end
  e.fatigue = math.max(0, math.floor(tonumber(e.fatigue) or 0))

  e.cooldown_ends_at = math.floor(tonumber(e.cooldown_ends_at) or 0)

  e.level = math.max(1, math.floor(tonumber(e.level) or _default_pet_level()))
  e.stat_hp = math.max(1, math.floor(tonumber(e.stat_hp) or _default_pet_hp(e.kind)))
  e.stat_attack = math.max(1, math.floor(tonumber(e.stat_attack) or _default_pet_attack(e.kind)))
  e.xp = math.max(0, math.floor(tonumber(e.xp) or _default_pet_xp()))
  e.battle_fatigue_progress = math.max(0, math.floor(tonumber(e.battle_fatigue_progress) or 0))
  e.attack_points = _coerce_skill_counter(e.attack_points or _pet_attack_points_from_stat(e.kind, e.stat_attack))
  e.hp_points     = _coerce_skill_counter(e.hp_points or _pet_hp_points_from_stat(e.kind, e.stat_hp))
  e.nickname = tostring(e.nickname or "")

  -- Home position (where it must return)
  e.home_area_id = e.home_area_id or e.area_id
  e.home_x = e.home_x or e.x
  e.home_y = e.home_y or e.y
  e.home_z = e.home_z or e.z or 0

  -- Current position
  e.area_id = tostring(e.area_id or e.home_area_id or "")
  e.x = tonumber(e.x or e.home_x or 0) or 0
  e.y = tonumber(e.y or e.home_y or 0) or 0
  e.z = tonumber(e.z or e.home_z or 0) or 0

  -- Expedition
  if type(e.exp) ~= "table" then e.exp = {} end
  e.exp.active = e.exp.active and true or false
  e.exp.started_at = math.floor(tonumber(e.exp.started_at) or 0)
  e.exp.ends_at    = math.floor(tonumber(e.exp.ends_at) or 0)
  e.exp.mood       = tostring(e.exp.mood or "")
  e.exp.lease_expires_at = math.floor(tonumber(e.exp.lease_expires_at) or 0)

  if type(e.exp.dest) ~= "table" then e.exp.dest = nil end
  if type(e.exp.reward) ~= "table" then e.exp.reward = nil end
  e.exp.reward_pending = e.exp.reward_pending and true or false
  e.exp.xp_reward = math.max(0, math.floor(tonumber(e.exp.xp_reward) or 0))
  e.exp.skill_points_gained = math.max(0, math.floor(tonumber(e.exp.skill_points_gained) or 0))

  -- If true, pet is currently "with" a player and should not spawn in overworld
  e.with_owner = e.with_owner and true or false
  _attach_owned_pet_to_entry(e, bucket_area_id, oncehub_key)
  return e
end

local function mood_from_fatigue(fatigue)
  return _pet_mood_from_fatigue(fatigue)
end

-- ====================== Nickname + "Pet it" lines ======================
local function _get_player_bugfrags(pid)
  local n = 0
  pcall(function()
    if ezmemory.get_player_fragments then
      n = ezmemory.get_player_fragments(pid)
    elseif Net.get_player_fragments then
      n = Net.get_player_fragments(pid)
    end
  end)
  return tonumber(n) or 0
end

local function _sanitize_nickname(s)
  s = tostring(s or "")
  -- strip control chars + collapse whitespace
  s = s:gsub("[%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then return "" end
  local max_len = 16
  if #s > max_len then s = s:sub(1, max_len) end
  return s
end

local PET_IT_LINES = {
  happy = {
    "It hops in place and gives a proud little chirp.",
    "It leans into your hand like it was waiting for that.",
    "It wiggles happily, sparks of energy popping around it.",
    "It does a tiny victory pose, then looks back at you to see your reaction.",
    "It circles you once and settles down, content.",
    "It bounces twice, like it's trying to show off how energetic it feels.",
    "It happily nudges your hand again, clearly asking for one more pat.",
    "It gives a bright little beep and does a quick spin in place.",
    "It puffs itself up proudly, then relaxes with a satisfied wiggle.",
    "It chirps and taps the floor like it's drumming a tiny celebration.",
  },
  neutral = {
    "It tilts its head, watching your hand carefully.",
    "It accepts the pat, then goes back to scanning the room.",
    "It makes a small sound-neither excited nor upset.",
    "It shifts its feet and looks around, mildly curious.",
    "It relaxes a little, but still seems focused.",
    "It blinks slowly, then gives a small nod like it understands.",
    "It pauses for a second, then resumes its steady little pacing.",
    "It lets you pet it, but keeps one eye on its surroundings.",
    "It gives a quiet hum, then settles into a calm stance.",
    "It seems to appreciate it... though it won't admit it out loud.",
  },
  sad = {
    "It flinches at first, then slowly relaxes under your hand.",
    "It looks down, but stays close as if comforted.",
    "It lets out a tiny sigh and blinks a few times.",
    "It scoots closer, like it doesn't want to be left alone.",
    "It gives a quiet little sound… it seems to want reassurance.",
    "It hesitates, then leans into your hand like it needed that.",
    "It looks up at you for a moment, then quietly stays by your side.",
    "It shuffles its feet and gives a small, shaky little chirp.",
    "It relaxes just a bit, but still seems worried about something.",
    "It stays still under your hand, soaking up the comfort.",
  },
}

local function _pick_one(list)
  local n = (type(list) == "table") and #list or 0
  if n <= 0 then return nil end
  now_seed_rng()
  return list[math.random(1, n)]
end

local function _pet_it_text(mood)
  return _pick_one(PET_IT_LINES[mood] or PET_IT_LINES.happy) or "It seems content."
end

local function _validate_reward_tables()
  for mood, entries in pairs(EXPEDITION.reward_tables or {}) do
    local total = 0
    for _, e in ipairs(entries or {}) do total = total + (tonumber(e.weight) or 0) end
    if total ~= 100 then
      print(("[pets][exp] WARNING: reward_tables.%s weights sum to %d (expected 100)"):format(tostring(mood), total))
    end
  end
end

local function pick_weighted(entries)
  local total = 0
  for _, e in ipairs(entries or {}) do total = total + (tonumber(e.weight) or 0) end
  if total <= 0 then return nil end
  local r = math.random() * total
  local acc = 0
  for _, e in ipairs(entries or {}) do
    acc = acc + (tonumber(e.weight) or 0)
    if r <= acc then return e end
  end
  return entries[#entries]
end

-- ====================== Runtime state ======================
-- uid -> rec
local records = {}
-- area_id -> { uid=true, ... }
local by_area = {}
-- bot_id(string) -> uid
local bot_to_uid = {}
companion_live_entries = {} -- uid -> live entry for summoned companion pets

local world_time = 0
local next_area_scan_time = 0
local area_has_players = {}

-- ====================== Helpers ======================
local function is_pet_id(item_id)
  return type(item_id) == "string" and item_id:sub(1, 4) == "pet_"
end
pets.is_pet_id = is_pet_id

local function blocked(area_id, x, y, z, size)
  local zz = z or 0

  -- Hard-guard: never wander outside map bounds
  if Net.get_width and Net.get_height then
    local w = Net.get_width(area_id)
    local h = Net.get_height(area_id)
    if w and h then
      if x < 0 or y < 0 or x >= w or y >= h then
        return true
      end
    end
  end

  -- Extra guard: don't step onto "void" tiles (gid == 0) on the current z-layer
  if Net.get_tile then
    local gx = nearest_tile(x)
    local gy = nearest_tile(y)
    local t = Net.get_tile(area_id, gx, gy, zz)
    if not t or not t.gid or t.gid == 0 then
      return true
    end
  end

  local probe = { x = x, y = y, z = zz, size = size or CONFIG.size }
  -- helpers.position_overlaps_something expects a position table + area_id (like eznpcs)
  return helpers.position_overlaps_something(probe, area_id)
end

local function safe_animate(bot_id, state)
  if not bot_id or not state then return end
  pcall(function() Net.animate_bot(bot_id, state, true) end)
end

local function safe_set_dir(bot_id, dir)
  if not bot_id or not dir then return end
  pcall(function() Net.set_bot_direction(bot_id, dir) end)
end

local function alloc_uid()
  return tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
end

local function index_record(rec)
  records[rec.uid] = rec
  by_area[rec.area_id] = by_area[rec.area_id] or {}
  by_area[rec.area_id][rec.uid] = true
  if rec.bot_id then
    bot_to_uid[tostring(rec.bot_id)] = rec.uid
  end
end

local function move_record_area(rec, new_area_id)
  if not rec or not new_area_id then return end
  if by_area[rec.area_id] then
    by_area[rec.area_id][rec.uid] = nil
  end
  rec.area_id = new_area_id
  by_area[rec.area_id] = by_area[rec.area_id] or {}
  by_area[rec.area_id][rec.uid] = true
end

local function unindex_record(rec)
  if not rec then return end
  if rec.bot_id then
    bot_to_uid[tostring(rec.bot_id)] = nil
  end
  records[rec.uid] = nil
  if by_area[rec.area_id] then
    by_area[rec.area_id][rec.uid] = nil
  end
end

-- ====================== Bot spawn / despawn ======================
local function spawn_pet_bot(rec)
  local def, tex, anim = build_paths(rec.kind, rec.stat_attack)
  if not def then
    print("[pets] Unknown pet kind:", tostring(rec.kind))
    return nil
  end

  Net.provide_asset(rec.area_id, tex)
  Net.provide_asset(rec.area_id, anim)

  local dir = rec.direction or "Down Left"
  local suffix = DIR_SUFFIX[dir] or "DL"

  local bid = Net.create_bot({
    name = def.name,
    area_id = rec.area_id,
    x = rec.x, y = rec.y, z = rec.z or 0,
    direction = dir,
    solid = CONFIG.solid,
    size = CONFIG.size,
    speed = CONFIG.speed,
    texture_path = tex,
    animation_path = anim,
    animation = "IDLE_" .. suffix,
  })

  rec.bot_id = bid
  bot_to_uid[tostring(bid)] = rec.uid
  safe_animate(bid, "IDLE_" .. suffix)
  return bid
end

local function despawn_pet_bot(rec, warp_out)
  if rec and rec.bot_id and Net.is_bot(rec.bot_id) then
    -- Try optional warp-out effect if supported (falls back to normal removal).
    if warp_out then
      local ok = pcall(Net.remove_bot, rec.bot_id, true)
      if not ok then pcall(Net.remove_bot, rec.bot_id) end
    else
      pcall(Net.remove_bot, rec.bot_id)
    end
  end
  if rec and rec.bot_id then
    bot_to_uid[tostring(rec.bot_id)] = nil
  end
  if rec then
    rec.bot_id = nil
  end
end

-- ====================== Waypoint movement (eznpcs style) ======================
local function choose_wander_waypoint(rec)
  local tx = nearest_tile(rec.x)
  local ty = nearest_tile(rec.y)
  local z  = rec.z or 0

  for _ = 1, 10 do
    local dir = CONFIG.directions[math.random(1, #CONFIG.directions)]
    local dx, dy = dir_to_vec(dir)
    local gx, gy = tx + dx, ty + dy

    if not blocked(rec.area_id, gx, gy, z, CONFIG.size) then
      rec.waypoint = { x = gx, y = gy, z = z }
      rec.direction = dir

      local suffix = DIR_SUFFIX[dir] or "DL"
      safe_set_dir(rec.bot_id, dir)
      safe_animate(rec.bot_id, "WALK_" .. suffix)
      return true
    end
  end

  return false
end

local function finish_waypoint(rec)
  if not rec.waypoint then return end
  rec.x, rec.y, rec.z = rec.waypoint.x, rec.waypoint.y, rec.waypoint.z
  if rec.bot_id and Net.is_bot(rec.bot_id) then
    Net.move_bot(rec.bot_id, rec.x, rec.y, rec.z)
    local suffix = DIR_SUFFIX[rec.direction or "Down Left"] or "DL"
    safe_animate(rec.bot_id, "IDLE_" .. suffix)
  end
  rec.waypoint = nil
  rec.blocked_for = 0
  rec.next_move_time = world_time + CONFIG.move_interval_sec + (math.random() * CONFIG.move_jitter_sec)
end

local function move_toward_waypoint(rec, delta_time)
  if not rec.waypoint then return end
  if not rec.bot_id or not Net.is_bot(rec.bot_id) then
    rec.waypoint = nil
    rec.next_move_time = world_time + 1.0
    return
  end

  local wx, wy, wz = rec.waypoint.x, rec.waypoint.y, rec.waypoint.z
  local dx = wx - rec.x
  local dy = wy - rec.y
  local dist = math.sqrt(dx*dx + dy*dy)

  local eps = CONFIG.arrive_epsilon or 0.05
  if dist <= eps then
    finish_waypoint(rec)
    return
  end

  local angle = math.atan(dy, dx)
  local vel_x = math.cos(angle) * CONFIG.speed
  local vel_y = math.sin(angle) * CONFIG.speed

  local nx = rec.x + vel_x * delta_time
  local ny = rec.y + vel_y * delta_time
  local nz = wz or rec.z or 0

  if blocked(rec.area_id, nx, ny, nz, CONFIG.size) then
    rec.blocked_for = (rec.blocked_for or 0) + delta_time
    if rec.blocked_for >= (CONFIG.blocked_timeout_sec or 1.25) then
      rec.waypoint = nil
      rec.blocked_for = 0
      local suffix = DIR_SUFFIX[rec.direction or "Down Left"] or "DL"
      safe_animate(rec.bot_id, "IDLE_" .. suffix)
      rec.next_move_time = world_time + 0.8
    end
    return
  end

  rec.blocked_for = 0
  rec.x, rec.y, rec.z = nx, ny, nz
  Net.move_bot(rec.bot_id, nx, ny, nz)
end

-- ====================== Entry lookup/update helpers ======================
local function find_entry(bucket_area_id, uid)
  local mem = ensure_bucket_mem(bucket_area_id)
  for oncehub_key, list in pairs(mem.oncehub_pets_v1 or {}) do
    if type(list) == "table" then
      for idx, e in ipairs(list) do
        if tostring(e.uid or "") == tostring(uid) then
          normalize_entry(e, bucket_area_id, oncehub_key)
          return e, oncehub_key, list, idx, mem
        end
      end
    end
  end
  return nil
end

local function return_armed_pet_for_replacement(secret)
  if not secret or secret == "" then return false end

  local pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then
    return false
  end

  local armed = pmem and pmem[PLAYER_ARMED_PET_KEY]
  if type(armed) ~= "table" then
    return true
  end

  local uid = tostring(armed.uid or "")
  local bucket_area_id = tostring(armed.bucket_area_id or "")

  -- Always clear any live summoned runtime first.
  if uid ~= "" then
    _clear_companion_runtime(uid, false)
  end

  -- Inventory-only pet: just clear the armed state.
  if uid == "" or bucket_area_id == "" then
    pmem[PLAYER_ARMED_PET_KEY] = nil
    _safe_save_player_memory(secret, pmem)
    return true
  end

  -- HP-based pet: return it home and respawn it at the HP.
  local e = find_entry(bucket_area_id, uid)
  if e then
    e.companion_summoned = nil
    e.with_owner = false
    e.area_id = e.home_area_id
    e.x, e.y, e.z = e.home_x, e.home_y, e.home_z or 0
    e.bot_id = nil

    local spawn_rec = {
      uid = uid,
      kind = tostring(e.kind or ""):lower(),
      area_id = e.area_id,
      x = e.x, y = e.y, z = e.z or 0,
      direction = "Down Left",
      next_move_time = world_time + 1.0,
      blocked_for = 0,
      owner_secret = e.owner_secret,
      owner_name = e.owner_name,
      stat_attack = e.stat_attack,
    }

    local bot_id = spawn_pet_bot(spawn_rec)
    if bot_id then
      spawn_rec.bot_id = bot_id
      index_record(spawn_rec)
      e.bot_id = bot_id
    end

    save_bucket(bucket_area_id)
  end

  pmem[PLAYER_ARMED_PET_KEY] = nil
  _safe_save_player_memory(secret, pmem)
  return true
end

local function _detach_armed_pet_for_training(secret)
  if not secret or secret == "" then return false, "" end

  local pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then return false, "" end

  local armed = pmem[PLAYER_ARMED_PET_KEY]
  if type(armed) ~= "table" then return true, "" end

  local uid            = tostring(armed.uid or "")
  local bucket_area_id = tostring(armed.bucket_area_id or "")

  -- Clear any live summoned companion runtime (no warp-out effect)
  if uid ~= "" then
    _clear_companion_runtime(uid, false)
  end

  -- For HP-based pets: mark as in_training and reset position, but do NOT re-spawn the bot
  if uid ~= "" and bucket_area_id ~= "" then
    local e = find_entry(bucket_area_id, uid)
    if e then
      e.companion_summoned = nil
      e.with_owner         = false
      e.in_training        = true
      e.area_id            = e.home_area_id
      e.x, e.y, e.z       = e.home_x, e.home_y, e.home_z or 0
      e.bot_id             = nil
      save_bucket(bucket_area_id)
    end
  end

  pmem[PLAYER_ARMED_PET_KEY] = nil
  _safe_save_player_memory(secret, pmem)

  return true, bucket_area_id
end

local function _entry_display_name(e)
  local kind = tostring(e and e.kind or "mettaur"):lower()
  local def = PET_DEFS[kind] or {}
  local base = tostring(def.name or kind:gsub("^%l", string.upper))

  local nick = _sanitize_nickname(e and e.nickname or "")
  if e and nick ~= tostring(e.nickname or "") then
    e.nickname = nick
  end

  return (nick ~= "" and nick) or base
end

function _clear_companion_runtime(uid, warp_out)
  uid = tostring(uid or "")
  if uid == "" then return end

  local rec = records[uid]
  if rec then
    rec.companion_summoned = nil
    despawn_pet_bot(rec, warp_out == true)
    unindex_record(rec)
  end

  local live = companion_live_entries[uid]
  if live then
    live.bot_id = nil
    live.companion_summoned = nil
  end

  companion_live_entries[uid] = nil
end

local function _entry_display_name(e)
  local kind = tostring(e and e.kind or "mettaur"):lower()
  local def = PET_DEFS[kind] or {}
  local base = tostring(def.name or kind:gsub("^%l", string.upper))

  local nick = _sanitize_nickname(e and e.nickname or "")
  if e and nick ~= tostring(e.nickname or "") then
    e.nickname = nick
  end

  return (nick ~= "" and nick) or base
end

local function _companion_owner_name(pid, secret)
  local name = ""

  if pid and Net.get_player_name then
    local ok, result = pcall(Net.get_player_name, pid)
    if ok and result and result ~= "" then
      name = tostring(result)
    end
  end

  if name == "" then
    name = tostring(_owner_name_from_secret(secret) or "")
  end

  return name
end

local function _get_companion_spawn_target(pid)
  local area_id = Net.get_player_area(pid)
  local pos = Net.get_player_position(pid) or { x = 0, y = 0, z = 0 }
  local dir = tostring(Net.get_player_direction(pid) or "Down Left")

  local px = nearest_tile(pos.x or pos[1] or 0)
  local py = nearest_tile(pos.y or pos[2] or 0)
  local pz = tonumber(pos.z or pos[3] or 0) or 0

  local dx, dy = dir_to_vec(dir)

  local tries = {
    { x = px + dx, y = py + dy, dir = dir },
    { x = px - dx, y = py - dy, dir = dir },
  }

  for _, alt in ipairs(CONFIG.directions or {}) do
    local ax, ay = dir_to_vec(alt)
    tries[#tries + 1] = { x = px + ax, y = py + ay, dir = alt }
  end

  for _, t in ipairs(tries) do
    if not blocked(area_id, t.x, t.y, pz, CONFIG.size) then
      return area_id, t.x, t.y, pz, t.dir
    end
  end

  return area_id, px, py, pz, dir
end

local function clear_armed_pet_for_player(pid)
  local secret = helpers.get_safe_player_secret(pid)
  if not secret or secret == "" then return end
  return_armed_pet_for_replacement(secret)
end

local function _on_disconnect_or_join(event)
  local pid = (type(event) == "table") and event.player_id or event
  if pid then clear_armed_pet_for_player(pid) end
end

Net:on("player_disconnect", _on_disconnect_or_join)
Net:on("handle_player_disconnect", _on_disconnect_or_join)
Net:on("handle_player_join", _on_disconnect_or_join) -- cleanup if server crashed while armed

local function update_entry_runtime_fields(e, rec)
  if not e or not rec then return end
  e.area_id = rec.area_id
  e.x, e.y, e.z = rec.x, rec.y, rec.z
  e.bot_id = rec.bot_id
  e.owner_secret = rec.owner_secret or e.owner_secret
  e.owner_name   = rec.owner_name   or e.owner_name
end

local function _owner_name_from_secret(secret)
  if not secret or secret == "" then return "" end
  local pm = _safe_get_player_memory(secret)
  local n = (pm and (pm.last_name or (pm.teams and pm.teams.last_name))) or nil
  if n and n ~= "" then return n end
  return ""
end

-- ====================== Expedition state helpers ======================
local function get_active_expedition_uid(bucket_area_id, owner_secret)
  local mem = ensure_bucket_mem(bucket_area_id)
  local rec = mem.oncehub_pet_expeditions_v1[tostring(owner_secret or "")]
  if type(rec) == "table" then
    return rec.uid, tonumber(rec.ends_at or 0)
  elseif type(rec) == "string" then
    return rec, 0
  end
  return nil
end

local function set_active_expedition(bucket_area_id, owner_secret, uid, ends_at)
  local mem = ensure_bucket_mem(bucket_area_id)
  mem.oncehub_pet_expeditions_v1[tostring(owner_secret or "")] = { uid=tostring(uid or ""), ends_at=math.floor(tonumber(ends_at) or 0) }
  save_bucket(bucket_area_id)
end

local function clear_active_expedition(bucket_area_id, owner_secret)
  local mem = ensure_bucket_mem(bucket_area_id)
  mem.oncehub_pet_expeditions_v1[tostring(owner_secret or "")] = nil
  save_bucket(bucket_area_id)
end

local function choose_roam_area()
  local t = EXPEDITION.roam_areas or {}
  if #t == 0 then return nil end
  local pick = t[math.random(1, #t)]
  return pick
end

local function is_on_cooldown(e)
  local now = _now()
  return (tonumber(e.cooldown_ends_at) or 0) > now
end

local function cooldown_left(e)
  return math.max(0, (tonumber(e.cooldown_ends_at) or 0) - _now())
end

local function expedition_active(e)
  return e and e.exp and e.exp.active == true
end

local function expedition_left(e)
  if not expedition_active(e) then return 0 end
  return math.max(0, (tonumber(e.exp.ends_at) or 0) - _now())
end

local function _dbg_frags(pid, tag)
  if not EXPEDITION.debug then return end

  if not Net.get_player_fragments then
    print(("[pets][frag] %s pid=%s (Net.get_player_fragments missing)"):format(tag, tostring(pid)))
    return
  end

  local ok, n = pcall(Net.get_player_fragments, pid)
  print(("[pets][frag] %s pid=%s frags=%s ok=%s"):format(tag, tostring(pid), tostring(n), tostring(ok)))
end

local function generate_reward(mood_snapshot)
  local mood = mood_snapshot or "neutral"
  local entries = (EXPEDITION.reward_tables and EXPEDITION.reward_tables[mood]) or (EXPEDITION.reward_tables and EXPEDITION.reward_tables.neutral) or {}
  local pick = pick_weighted(entries)
  local id = pick and pick.id or "consolation"


  if id == "consolation" then
    return { kind="money", amount=tonumber(EXPEDITION.consolation_money) or 1000, label="scraps" }
  elseif id == "money" then
    local mn = tonumber(EXPEDITION.money_min) or 10000
    local mx = tonumber(EXPEDITION.money_max) or 50000
    if mx < mn then mn, mx = mx, mn end
    local amt = math.random(mn, mx)
    return { kind="money", amount=amt }
  elseif id == "frag" then
    return { kind="frag", amount=tonumber(EXPEDITION.frag_amount) or 1 }
  elseif id == "card" then
    local pool = EXPEDITION.card_pool or {}
    if #pool == 0 then
      -- fallback
      local mn = tonumber(EXPEDITION.money_min) or 10000
      local mx = tonumber(EXPEDITION.money_max) or 50000
      local amt = math.random(mn, mx)
      return { kind="money", amount=amt, label="fallback" }
    end
    local c = pool[math.random(1, #pool)]
    return { kind="card", name=tostring(c.name or "Card"), description=tostring(c.description or ""), amount=1 }
  elseif id == "gp" then
    return { kind="gp", amount=tonumber(EXPEDITION.gp_amount) or 1 }
  end

  -- unknown -> consolation
  return { kind="money", amount=tonumber(EXPEDITION.consolation_money) or 1000, label="scraps" }
end

local function apply_reward_to_player(pid, reward)
  if not pid or not reward then return end
  local area_id = Net.get_player_area(pid)

  if reward.kind == "money" then
    pcall(ezmemory.spend_player_money, pid, -tonumber(reward.amount or 0))
    Net.message_player(pid, "Got "..tostring(reward.amount or 0).."z!")
    return
  end

  if reward.kind == "frag" then
  local amt = tonumber(reward.amount or 0) or 0
  if ezmemory.spend_player_fragments then
    _dbg_frags(pid, "reward:before")
    pcall(ezmemory.spend_player_fragments, pid, -amt)
    _dbg_frags(pid, "reward:after")
  else
    local ok, cur = pcall(Net.get_player_fragments, pid)
    cur = ok and (tonumber(cur) or 0) or 0
    pcall(Net.set_player_fragments, pid, cur + amt)
  end
  Net.message_player(pid, "Got "..tostring(amt).." BugFrag!")
  return
end

if reward.kind == "card" then
    local item_info = { type="item", name=tostring(reward.name), description=tostring(reward.description or ""), amount=tonumber(reward.amount or 1) }
    pcall(ezmemory.create_or_update_item, item_info.name, item_info.description, false)
    pcall(ezmemory.give_player_item, pid, item_info.name, item_info.amount)
    Net.message_player(pid, "Got "..item_info.name.."!")
    return
  end

  if reward.kind == "gp" then
    if Teams and Teams.award_activity_gp then
      pcall(Teams.award_activity_gp, pid, tonumber(reward.amount or 1), "pet expedition")
    elseif Teams and Teams.debug_add_gp then
      pcall(Teams.debug_add_gp, pid, tonumber(reward.amount or 1))
    else
      -- fallback to money if teams isn't loaded
      local amt = tonumber(EXPEDITION.money_min) or 10000
      pcall(ezmemory.spend_player_money, pid, -amt)
      Net.message_player(pid, "Got "..tostring(amt).."z!")
    end
    return
  end
end

local function result_flavor(mood, reward)
  mood = tostring(mood or "neutral")

  local kind  = reward and tostring(reward.kind or "") or ""
  local label = reward and tostring(reward.label or "") or ""

  -- In your generate_reward(), consolation is { kind="money", label="scraps", amount=... }
  local is_consolation_money = (kind == "money" and label == "scraps")
  local is_gp = (kind == "gp")

  -- "Did well" bucket (per your example): bug frag, regular money, or a card.
  local did_well = (kind == "frag") or (kind == "card") or (kind == "money" and not is_consolation_money)

  if mood == "happy" then
    if is_consolation_money or is_gp then
      return "Your virus looks a bit embarrassed it couldn't do better."
    elseif did_well then
      return "Your virus looks happy about the expedition."
    end
    return "Your virus looks pleased with the trip."

  elseif mood == "neutral" then
    if is_consolation_money or is_gp then
      return "Your virus gives a small shrug and hands you what it managed to find."
    elseif did_well then
      return "Your virus seems quietly satisfied with what it brought back."
    end
    return "Your virus reports back from its trip."

  else -- sad (or anything else)
    if is_consolation_money or is_gp then
      return "Your virus trudges back, apologetic… it didn't find much this time."
    elseif did_well then
      return "Your virus looks exhausted, but a little proud of what it managed to bring back."
    end
    return "Your virus seems exhausted after its trip."
  end
end

local function owner_on_team(pid)
  local secret = helpers.get_safe_player_secret(pid)
  local pm = _safe_get_player_memory(secret) or {}
  local cur = pm.teams and pm.teams.current
  return (cur and cur.team) ~= nil
end

-- Complete an expedition (called by tick). Updates memory, moves/respawns bots as needed.
local function complete_expedition_for_entry(e, bucket_area_id)
  if not e or not expedition_active(e) then return end
  local now = _now()

  -- Rental expired? Cancel expedition and remove pet entirely.
  local lease_expires_at = tonumber(e.exp.lease_expires_at or 0) or 0
  if lease_expires_at > 0 and lease_expires_at <= now then
    dbg("Expedition cancelled (lease expired). uid=", e.uid, "owner=", e.owner_secret)
    -- Try to despawn roaming bot if present
    if e.bot_id and Net.is_bot(e.bot_id) then pcall(Net.remove_bot, e.bot_id) end
local rec = records[tostring(e.uid)]
if rec then
  despawn_pet_bot(rec, false)
  unindex_record(rec)
end
    -- Remove from storage list
    local list = load_pet_list(bucket_area_id, e.oncehub_key)
    for i = #list, 1, -1 do
      if tostring(list[i].uid or "") == tostring(e.uid) then
        table.remove(list, i)
        break
      end
    end
    -- Clear expedition map
    clear_active_expedition(bucket_area_id, e.owner_secret)
    save_bucket(bucket_area_id)
    return
  end

  -- Generate reward now (stored until claim)
  local mood_snapshot = (e.exp and e.exp.mood) or "neutral"
  local reward = generate_reward(mood_snapshot) -- owner_on_team unknown offline; resolved on claim for gp fallback
  -- If reward is gp but owner is offline, we still store gp and fallback on claim if needed.
  e.exp.reward = reward
  e.exp.reward_pending = true
  e.exp.xp_reward = 0
  e.exp.skill_points_gained = 0

  local xp_ok, new_xp, skill_gained = _award_owned_pet_xp_for_secret(
    tostring(e.owner_secret or ""),
    tostring(e.uid or ""),
    PET_EXPEDITION_XP
  )

  if xp_ok then
    e.xp = new_xp
    e.exp.xp_reward = PET_EXPEDITION_XP
    e.exp.skill_points_gained = math.max(0, tonumber(skill_gained) or 0)
  end

  -- End expedition, return to home position
  e.exp.active = false

  local cd = EXPEDITION.cooldown_by_mood[mood_from_fatigue(e.fatigue)] or (30*60)
  e.cooldown_ends_at = now + cd

-- Despawn roaming bot if it exists
if e.bot_id and Net.is_bot(e.bot_id) then
  dbg("Despawning roaming bot uid=", e.uid, "bot_id=", e.bot_id)
  pcall(Net.remove_bot, e.bot_id)
end
e.bot_id = nil

-- Clear any roaming runtime record
local rec = records[tostring(e.uid)]
if rec then
  despawn_pet_bot(rec, false)
  unindex_record(rec)
end

e.area_id = e.home_area_id
e.x, e.y, e.z = e.home_x, e.home_y, e.home_z or 0

-- Spawn the pet back home immediately
local home_rec = {
  uid = tostring(e.uid),
  kind = tostring(e.kind or ""):lower(),
  area_id = e.area_id,
  x = e.x, y = e.y, z = e.z or 0,
  direction = "Down Left",
  next_move_time = world_time + 1.0,
  blocked_for = 0,
  owner_secret = e.owner_secret,
  owner_name = e.owner_name,
  stat_attack = e.stat_attack,
}
spawn_pet_bot(home_rec)
index_record(home_rec)
e.bot_id = home_rec.bot_id

  dbg("Expedition complete; returning uid=", e.uid, "to", e.area_id, "cooldown=", cd)
  clear_active_expedition(bucket_area_id, e.owner_secret)
  save_bucket(bucket_area_id)
end

local function start_expedition_for_player(pid, e, bucket_area_id)
  local now = _now()
  local secret = helpers.get_safe_player_secret(pid)
  if secret ~= (e.owner_secret or "") then
    return false, "Only the owner can send this pet on an expedition."
  end

  if not e.owner_name or e.owner_name == "" then
    e.owner_name = Net.get_player_name(pid)
  end

  -- Only start expeditions from the pet's HOME HP area.
  local cur_area = Net.get_player_area(pid)
  if tostring(cur_area or "") ~= tostring(e.home_area_id or "") then
    return false, "This pet can only be sent from its home HP."
  end

  -- Only one active expedition per player
  local active_uid = get_active_expedition_uid(bucket_area_id, secret)
  if active_uid and tostring(active_uid) ~= "" and tostring(active_uid) ~= tostring(e.uid) then
    return false, "You already have a pet out on an expedition."
  end

  -- Cooldown guard
  if is_on_cooldown(e) then
    return false, "Your pet is resting. Come back in ".._fmt_time_left(cooldown_left(e)).."."
  end

  -- Duration derived from minutes
  local duration_sec = math.max(60, math.floor((tonumber(EXPEDITION.duration_minutes) or 60) * 60))

  -- Lease must last long enough (or cancel)
  local expires_at = _get_hp_expires_at(bucket_area_id, e.oncehub_key)
  if expires_at and tonumber(expires_at) and tonumber(expires_at) > 0 then
    if tonumber(expires_at) < (now + duration_sec) then
      return false, "Your HP rental will expire before the expedition ends."
    end
  end

  -- Pick destination (your config table)
  local dest = choose_roam_area()
  if not dest then
    return false, "No expedition destinations are configured."
  end

  local mood_snapshot = mood_from_fatigue(e.fatigue)

  -- Fatigue increases when you send it out
  e.fatigue = math.max(0, math.floor(tonumber(e.fatigue) or 0) + 1)
  _save_owned_pet_from_entry(e, false)

  -- Mark expedition
  e.exp.active = true
  e.exp.started_at = now
  e.exp.ends_at = now + duration_sec
  e.exp.mood = mood_snapshot
  e.exp.dest = { area_id=dest.area_id, x=dest.x, y=dest.y, z=dest.z or 0, label=dest.label or dest.area_id }
  e.exp.lease_expires_at = tonumber(expires_at or 0) or 0
  e.exp.reward = nil
  e.exp.reward_pending = false
  e.exp.xp_reward = 0
  e.exp.skill_points_gained = 0

  dbg("Starting expedition uid=", e.uid, "owner=", e.owner_name, "dest=", dest.area_id, dest.x, dest.y, dest.z or 0)

  -- Tell player where it went (fun)
  local label = tostring(dest.label or dest.area_id or "somewhere")
  Net.message_player(pid, ("Your virus headed out to %s."):format(label))

  -- Despawn + unindex current runtime record (if any)
  local rec = records[tostring(e.uid)]
  if rec then
    despawn_pet_bot(rec, true)
    unindex_record(rec)
  else
    -- fallback: if e has a bot_id but isn't indexed for some reason
    if e.bot_id and Net.is_bot(e.bot_id) then
      pcall(Net.remove_bot, e.bot_id, true)
      bot_to_uid[tostring(e.bot_id)] = nil
    end
    e.bot_id = nil
  end

  -- Move pet data to roaming location BEFORE spawning
  e.area_id = dest.area_id
  e.x, e.y, e.z = dest.x, dest.y, dest.z or 0

  -- Spawn roam bot (spawn_pet_bot returns bot_id or nil)
  local bot_id = spawn_pet_bot(e)
  if not bot_id then
    dbg("Expedition spawn failed uid=", e.uid)
    e.exp.active = false
    e.exp.reward = nil
    e.exp.reward_pending = false
    save_bucket(bucket_area_id)
    clear_active_expedition(bucket_area_id, secret)
    return false, "Couldn't send your pet out right now."
  end

  e.bot_id = bot_id
  index_record(e)

  -- Set active expedition map
  set_active_expedition(bucket_area_id, secret, e.uid, e.exp.ends_at)

  save_bucket(bucket_area_id)
  dbg("Expedition started uid=", e.uid, "ends_at=", e.exp.ends_at)

  local mins = math.floor(duration_sec / 60)
  return true, ("Sent out for %d minute%s."):format(mins, mins == 1 and "" or "s", mood_snapshot)
end

function clamp_pet_battle_rank(rank)
  rank = math.floor(tonumber(rank) or 1)
  if rank < 1 then rank = 1 end
  if rank > 20 then rank = 20 end
  return rank
end

-- Arm a pet so it joins the owner's battles (despawns from overworld; cleared on disconnect)
local function take_pet_with_you(pid, e, bucket_area_id, allow_replace, skip_home_area_check)
  local secret = helpers.get_safe_player_secret(pid)
  if secret ~= (e.owner_secret or "") then
    return false, "Only the owner can take this pet with them."
  end

  local kind = tostring(e.kind or ""):lower()
  local battle_def = BATTLE_PETS[kind]

  -- Keep the HP-side restriction unless explicitly bypassed
  if not skip_home_area_check then
    local cur_area = Net.get_player_area(pid)
    if tostring(cur_area or "") ~= tostring(e.home_area_id or "") then
      return false, "This pet can only be taken from its home HP."
    end
  end

  -- Only 1 pet armed at a time, unless we're explicitly replacing it
  local pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then
    return false, "Pet memory isn't ready yet."
  end

  if pmem[PLAYER_ARMED_PET_KEY] then
    if not allow_replace then
      return false, "You already have a pet with you."
    end

    local ok = return_armed_pet_for_replacement(secret)
    if not ok then
      return false, "Couldn't return your current pet."
    end

    pmem = _safe_get_player_memory(secret)
    if type(pmem) ~= "table" then
      return false, "Pet memory isn't ready yet."
    end
  end

  -- Despawn + unindex current runtime record
  local uid = tostring(e.uid)
  local rec = records[uid]
  if rec then
    despawn_pet_bot(rec, true)
    unindex_record(rec)
  else
    if e.bot_id and Net.is_bot(e.bot_id) then
      pcall(Net.remove_bot, e.bot_id, true)
      bot_to_uid[tostring(e.bot_id)] = nil
    end
  end

  e.bot_id = nil
  e.with_owner = true

  local owned = _get_owned_pet(secret, uid)

  local equipped_chip_id = nil
  local equipped_chip_amount = 1

  if battle_def then
    equipped_chip_id = tonumber(
      (owned and owned.pet_chip_id)
      or e.pet_chip_id
      or battle_def.test_pet_chip_id
      or nil
    )

    equipped_chip_amount = math.max(1, math.floor(tonumber(
      (owned and owned.pet_chip_amount)
      or e.pet_chip_amount
      or battle_def.test_pet_chip_amount
      or 1
    ) or 1))
  end

  pmem[PLAYER_ARMED_PET_KEY] = {
    uid = uid,
    kind = kind,
    enemy_name = tostring((battle_def and battle_def.enemy_name) or ""),
    rank = clamp_pet_battle_rank((owned and owned.stat_attack) or e.stat_attack or (battle_def and battle_def.rank) or 1),
    starting_hp = math.max(1, math.floor(tonumber(e.stat_hp or (battle_def and battle_def.default_starting_hp) or 40) or 40)),
    pet_chip_id = equipped_chip_id,
    pet_chip_amount = equipped_chip_amount,
    bucket_area_id = tostring(bucket_area_id or ""),
    source = "hp",
    summoned = false,
    summoned_area_id = "",
  }

  print("[PET ARM SAVE]",
    tostring(pmem[PLAYER_ARMED_PET_KEY].enemy_name or ""),
    "hp=" .. tostring(pmem[PLAYER_ARMED_PET_KEY].starting_hp),
    "chip=" .. tostring(pmem[PLAYER_ARMED_PET_KEY].pet_chip_id or 0)
  )

  _safe_save_player_memory(secret, pmem)
  save_bucket(bucket_area_id)

  return true, "Companion pet selected."
end

local function _companion_base_name(kind)
  kind = tostring(kind or "mettaur"):lower()
  local def = PET_DEFS[kind] or {}
  return tostring(def.name or kind:gsub("^%l", string.upper))
end

function pets.list_companion_candidates(owner_or_pid)
  local owner_secret = _resolve_pet_owner_secret(owner_or_pid)
  if owner_secret == "" then
    return {}
  end

  pets.ensure_player_pet_ids(owner_secret)

  local owned = pets.list_owned_pets(owner_secret)
  local out = {}

  for _, p in ipairs(owned) do
    local base_name = _companion_base_name(p.kind)
    local nickname = tostring(p.nickname or "")
    local display_name = (nickname ~= "" and nickname) or base_name

    local on_expedition = false

    if type(p.placement) == "table" then
      local bucket_area_id = tostring(p.placement.bucket_area_id or "")
      if bucket_area_id ~= "" then
        local e = find_entry(bucket_area_id, p.uid)
        if e and expedition_active(e) then
          on_expedition = true
        end
      end
    end

    local in_training = false
    local pmem = _safe_get_player_memory(owner_secret)
    if type(pmem) == "table" then
      local t = pmem[PET_TRAINING_MEM_KEY]
      if type(t) == "table" and tostring(t.uid or "") == tostring(p.uid or "") then
        in_training = true
      end
    end

    if not on_expedition and not in_training then
      out[#out + 1] = {
        uid = tostring(p.uid or ""),
        kind = tostring(p.kind or "mettaur"),
        base_name = base_name,
        nickname = nickname,
        display_name = display_name,
        mood = tostring(p.mood or "neutral"),
        placed = p.placed == true,
        placement = p.placement,
        can_fight = BATTLE_PETS[tostring(p.kind or ""):lower()] ~= nil,
      }
    end
  end

  table.sort(out, function(a, b)
    local an = tostring(a.display_name or a.base_name or a.kind or ""):lower()
    local bn = tostring(b.display_name or b.base_name or b.kind or ""):lower()
    if an == bn then
      return tostring(a.uid or "") < tostring(b.uid or "")
    end
    return an < bn
  end)

  return out
end

function pets.arm_owned_pet(pid, uid, allow_replace)
  local secret = helpers.get_safe_player_secret(pid)
  if not secret or secret == "" then
    return false, "Pet owner not found."
  end

  uid = tostring(uid or "")
  if uid == "" then
    return false, "Missing pet id."
  end

  pets.ensure_player_pet_ids(secret)

  local owned = _get_owned_pet(secret, uid)
  if not owned then
    return false, "Pet not found."
  end

  -- If the pet is currently placed in an HP, use the real live entry so it gets
  -- despawned from the HP correctly and can later return there.
  if type(owned.placement) == "table" then
    local bucket_area_id = tostring(owned.placement.bucket_area_id or "")
    if bucket_area_id ~= "" then
      local e = find_entry(bucket_area_id, uid)
      if e then
        if expedition_active(e) then
          local left = expedition_left(e)
          local where = (e.exp and e.exp.dest and e.exp.dest.label)
                     or (e.exp and e.exp.dest and e.exp.dest.area_id)
                     or "somewhere"
          return false, ("That pet is on an expedition (%s). Returns in %s."):format(tostring(where), _fmt_time_left(left))
        end

        return take_pet_with_you(pid, e, bucket_area_id, allow_replace, true)
      end
    end
  end

  -- Inventory-only pet
  local pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then
    return false, "Pet memory isn't ready yet."
  end

  local kind = tostring(owned.kind or "mettaur"):lower()
  local battle_def = BATTLE_PETS[kind]

  local equipped_chip_id = nil
  local equipped_chip_amount = 1

  if battle_def then
    equipped_chip_id = tonumber(owned.pet_chip_id or battle_def.test_pet_chip_id or nil)
    equipped_chip_amount = math.max(1, math.floor(tonumber(
      owned.pet_chip_amount or battle_def.test_pet_chip_amount or 1
    ) or 1))
  end

  if pmem[PLAYER_ARMED_PET_KEY] then
    if not allow_replace then
      return false, "You already have a pet with you."
    end

    local ok = return_armed_pet_for_replacement(secret)
    if not ok then
      return false, "Couldn't return your current pet."
    end

    pmem = _safe_get_player_memory(secret)
    if type(pmem) ~= "table" then
      return false, "Pet memory isn't ready yet."
    end
  end

  pmem[PLAYER_ARMED_PET_KEY] = {
    uid = uid,
    kind = kind,
    enemy_name = tostring((battle_def and battle_def.enemy_name) or ""),
    rank = clamp_pet_battle_rank(owned.stat_attack or (battle_def and battle_def.rank) or 1),
    starting_hp = math.max(1, math.floor(tonumber(owned.stat_hp or (battle_def and battle_def.default_starting_hp) or 40) or 40)),
    pet_chip_id = equipped_chip_id,
    pet_chip_amount = equipped_chip_amount,
    bucket_area_id = "",
    source = "inventory",
    summoned = false,
    summoned_area_id = "",
  }

  _safe_save_player_memory(secret, pmem)
  return true, "Companion pet selected."
end

function pets.invest_armed_pet_stat(pid, stat_name)
  local secret = helpers.get_safe_player_secret(pid)
  if not secret or secret == "" then
    return false, "Pet owner not found."
  end

  local pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then
    return false, "Pet memory isn't ready yet."
  end

  local armed = pmem[PLAYER_ARMED_PET_KEY]
  if type(armed) ~= "table" then
    return false, "No companion pet selected."
  end

  local uid = tostring(armed.uid or "")
  if uid == "" then
    return false, "Missing pet id."
  end

  local store = pmem[OWNED_PETS_MEM_KEY]
  if type(store) ~= "table" or type(store.pets) ~= "table" then
    return false, "Pet data wasn't found."
  end

  local p = _normalize_owned_pet(store.pets[uid])
  if type(p) ~= "table" then
    return false, "Pet not found."
  end

  p.attack_points = _coerce_skill_counter(p.attack_points or _pet_attack_points_from_stat(p.kind, p.stat_attack))
  p.hp_points     = _coerce_skill_counter(p.hp_points or _pet_hp_points_from_stat(p.kind, p.stat_hp))

  local free = _pet_free_skill_points_for_pet(p)
  if free < 1 then
    return false, "No skill points available."
  end

  stat_name = tostring(stat_name or ""):lower()

if stat_name == "hp" then
    if p.stat_hp >= 100 then
      return false, "HP is already at the maximum of 100."
    end
    p.hp_points = p.hp_points + 1
    p.stat_hp = math.max(1, math.floor(tonumber(p.stat_hp or _default_pet_hp(p.kind)) or _default_pet_hp(p.kind)) + 5)

  elseif stat_name == "attack" then
    local current_rank = clamp_pet_battle_rank(p.stat_attack or _default_pet_attack(p.kind))

    if current_rank >= 20 then
      return false, "Attack is already maxed."
    end

    if current_rank >= 19 and p.stat_hp < 100 then
      return false, "Raise HP to 100 before pushing Attack to Rank 20."
    end

    if current_rank >= 10 and p.stat_hp < 70 then
      return false, "Raise HP to 70 before pushing Attack past Rank 10."
    end

    p.attack_points = p.attack_points + 1
    p.stat_attack = clamp_pet_battle_rank(current_rank + 1)

  else
    return false, "Unknown stat."
  end

  store.pets[uid] = p
  pmem[OWNED_PETS_MEM_KEY] = store

  local battle_def = BATTLE_PETS[tostring(p.kind or ""):lower()]
  armed.rank = clamp_pet_battle_rank(p.stat_attack)
  armed.starting_hp = math.max(1, math.floor(tonumber(
    p.stat_hp
    or (battle_def and battle_def.default_starting_hp)
    or _default_pet_hp(p.kind)
  ) or _default_pet_hp(p.kind)))
  pmem[PLAYER_ARMED_PET_KEY] = armed

  _safe_save_player_memory(secret, pmem)

  if type(p.placement) == "table" then
    local bucket_area_id = tostring(p.placement.bucket_area_id or "")
    if bucket_area_id ~= "" then
      local e = find_entry(bucket_area_id, uid)
      if e then
        e.stat_hp = p.stat_hp
        e.stat_attack = p.stat_attack
        e.attack_points = p.attack_points
        e.hp_points = p.hp_points
        e.xp = p.xp
        save_bucket(bucket_area_id)
      end
    end
  end

  local live = companion_live_entries[tostring(uid)]
  if type(live) == "table" then
    live.stat_hp = p.stat_hp
    live.stat_attack = p.stat_attack
    live.xp = p.xp
  end

  if stat_name == "hp" then
    return true, ("HP increased to %d."):format(p.stat_hp)
  end

  return true, ("Attack increased to %d (Rank %d)."):format(clamp_pet_battle_rank(p.stat_attack) * 5, clamp_pet_battle_rank(p.stat_attack))
end

function pets.unarm_pet(pid)
  local secret = helpers.get_safe_player_secret(pid)
  if not secret or secret == "" then
    return false, "Pet owner not found."
  end

  local ok = return_armed_pet_for_replacement(secret)
  if not ok then
    return false, "Couldn't unselect your companion pet."
  end

  return true, "Companion pet unselected."
end

function pets.ensure_pet_chip_items()
  for _, def in pairs(PET_CHIPS) do
    pcall(ezmemory.create_or_update_item, def.item_name, def.description, false)
  end
end

function pets.get_pet_chip_name(chip_id)
  return _pet_chip_name(chip_id)
end

function pets.list_player_pet_chip_inventory(pid)
  pets.ensure_pet_chip_items()

  local secret = helpers.get_safe_player_secret(pid)
  if not secret or secret == "" then
    return {}
  end

  local pmem = _safe_get_player_memory(secret)
  local items = (type(pmem) == "table" and pmem.items) or {}
  local rows = {}

  for chip_id, def in pairs(PET_CHIPS) do
    local item_id = ezmemory.get_item_id_by_name(def.item_name)
    local qty = 0

    if item_id then
      qty = tonumber(items[item_id] or 0) or 0
    end

    if qty > 0 then
      rows[#rows + 1] = {
        chip_id = tonumber(chip_id),
        name = def.display_name,
        item_name = def.item_name,
        qty = qty,
      }
    end
  end

  table.sort(rows, function(a, b)
    return tonumber(a.chip_id or 0) < tonumber(b.chip_id or 0)
  end)

  return rows
end

function pets.give_player_pet_chip(pid, chip_id, amount)
  pets.ensure_pet_chip_items()

  local def = _pet_chip_def(chip_id)
  if not def then
    return false, "Unknown pet chip."
  end

  amount = math.max(1, math.floor(tonumber(amount) or 1))

  local ok = pcall(ezmemory.give_player_item, pid, def.item_name, amount)
  if not ok then
    return false, "Couldn't give that pet chip."
  end

  return true, ("Gave %s x%d."):format(def.display_name, amount)
end

function pets.equip_chip_on_pet(pid, uid, chip_id)
  local secret = helpers.get_safe_player_secret(pid)
  if not secret or secret == "" then
    return false, "Pet owner not found."
  end

  uid = tostring(uid or "")
  if uid == "" then
    return false, "Missing pet id."
  end

  local chip_def = _pet_chip_def(chip_id)
  if not chip_def then
    return false, "Unknown pet chip."
  end

  local owned = _get_owned_pet(secret, uid)
  if not owned then
    return false, "Pet not found."
  end

  if not BATTLE_PETS[tostring(owned.kind or ""):lower()] then
    return false, "That pet family doesn't use battle chips."
  end

  local inventory = pets.list_player_pet_chip_inventory(pid)
  local have_qty = 0
  for _, row in ipairs(inventory) do
    if tonumber(row.chip_id) == tonumber(chip_id) then
      have_qty = tonumber(row.qty or 0) or 0
      break
    end
  end

  if have_qty < 1 then
    return false, "You don't own that pet chip."
  end

  owned.pet_chip_id = tonumber(chip_id)
  owned.pet_chip_amount = 1

  -- Sync any placed HP entry
  if type(owned.placement) == "table" then
    local bucket_area_id = tostring(owned.placement.bucket_area_id or "")
    if bucket_area_id ~= "" then
      local e = find_entry(bucket_area_id, uid)
      if e then
        e.pet_chip_id = owned.pet_chip_id
        e.pet_chip_amount = owned.pet_chip_amount
        save_bucket(bucket_area_id)
      end
    end
  end

  -- Sync active armed state if this pet is currently selected
  local pmem = _safe_get_player_memory(secret)
  if type(pmem) == "table" then
    local armed = pmem[PLAYER_ARMED_PET_KEY]
    if type(armed) == "table" and tostring(armed.uid or "") == uid then
      armed.pet_chip_id = owned.pet_chip_id
      armed.pet_chip_amount = owned.pet_chip_amount
      pmem[PLAYER_ARMED_PET_KEY] = armed
    end
    _safe_save_player_memory(secret, pmem)
  end

  ezmemory.save_player_memory(secret)
  return true, ("%s equipped."):format(chip_def.display_name)
end

function pets.unequip_chip_from_pet(pid, uid)
  local secret = helpers.get_safe_player_secret(pid)
  if not secret or secret == "" then
    return false, "Pet owner not found."
  end

  uid = tostring(uid or "")
  if uid == "" then
    return false, "Missing pet id."
  end

  local owned = _get_owned_pet(secret, uid)
  if not owned then
    return false, "Pet not found."
  end

  owned.pet_chip_id = nil
  owned.pet_chip_amount = 1

  -- Sync any placed HP entry
  if type(owned.placement) == "table" then
    local bucket_area_id = tostring(owned.placement.bucket_area_id or "")
    if bucket_area_id ~= "" then
      local e = find_entry(bucket_area_id, uid)
      if e then
        e.pet_chip_id = nil
        e.pet_chip_amount = 1
        save_bucket(bucket_area_id)
      end
    end
  end

  -- Sync active armed state if this pet is currently selected
  local pmem = _safe_get_player_memory(secret)
  if type(pmem) == "table" then
    local armed = pmem[PLAYER_ARMED_PET_KEY]
    if type(armed) == "table" and tostring(armed.uid or "") == uid then
      armed.pet_chip_id = nil
      armed.pet_chip_amount = 1
      pmem[PLAYER_ARMED_PET_KEY] = armed
    end
    _safe_save_player_memory(secret, pmem)
  end

  ezmemory.save_player_memory(secret)
  return true, "Pet chip unequipped."
end

function pets.is_companion_summoned(pid)
  local secret = helpers.get_safe_player_secret(pid)
  if not secret or secret == "" then
    return false
  end

  local pmem = _safe_get_player_memory(secret)
  local armed = pmem and pmem[PLAYER_ARMED_PET_KEY]
  return type(armed) == "table" and armed.summoned == true
end

function pets.call_back_companion(pid)
  local secret = helpers.get_safe_player_secret(pid)
  if not secret or secret == "" then
    return false, "Pet owner not found."
  end

  local pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then
    return false, "Pet memory isn't ready yet."
  end

  local armed = pmem[PLAYER_ARMED_PET_KEY]
  if type(armed) ~= "table" then
    return false, "No companion pet selected."
  end

  if armed.summoned ~= true then
    return false, "Your companion pet isn't summoned."
  end

  local uid = tostring(armed.uid or "")
  local bucket_area_id = tostring(armed.bucket_area_id or "")

  _clear_companion_runtime(uid, false)

  if bucket_area_id ~= "" then
    local e = find_entry(bucket_area_id, uid)
    if e then
      e.companion_summoned = nil
      e.with_owner = true
      e.area_id = e.home_area_id
      e.x, e.y, e.z = e.home_x, e.home_y, e.home_z or 0
      e.bot_id = nil
      save_bucket(bucket_area_id)
    end
  end

  armed.summoned = false
  armed.summoned_area_id = ""
  pmem[PLAYER_ARMED_PET_KEY] = armed
  _safe_save_player_memory(secret, pmem)

  return true, "Companion pet called back."
end

function pets.summon_companion(pid)
  local secret = helpers.get_safe_player_secret(pid)
  if not secret or secret == "" then
    return false, "Pet owner not found."
  end

  local pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then
    return false, "Pet memory isn't ready yet."
  end

  local armed = pmem[PLAYER_ARMED_PET_KEY]
  if type(armed) ~= "table" then
    return false, "No companion pet selected."
  end

  if armed.summoned == true then
    return false, "Your companion pet is already summoned."
  end

  local uid = tostring(armed.uid or "")
  local kind = tostring(armed.kind or "mettaur"):lower()
  local bucket_area_id = tostring(armed.bucket_area_id or "")

  if uid == "" then
    return false, "Missing pet id."
  end

  local area_id, sx, sy, sz, dir = _get_companion_spawn_target(pid)
  local owner_name = _companion_owner_name(pid, secret)

  _clear_companion_runtime(uid, true)

  local e = nil

  if bucket_area_id ~= "" then
    e = find_entry(bucket_area_id, uid)
    if not e then
      return false, "Couldn't find that companion pet."
    end

    e.owner_name = owner_name ~= "" and owner_name or e.owner_name
    e.area_id = area_id
    e.x, e.y, e.z = sx, sy, sz
    e.direction = dir
    e.next_move_time = world_time + 1.0
    e.blocked_for = 0
    e.bot_id = nil
    e.with_owner = false
    e.companion_summoned = true

    local bot_id = spawn_pet_bot(e)
    if not bot_id then
      e.companion_summoned = nil
      e.with_owner = true
      return false, "Couldn't summon that companion pet."
    end

    e.bot_id = bot_id
    index_record(e)
    companion_live_entries[uid] = e
    save_bucket(bucket_area_id)
  else
    local owned = _get_owned_pet(secret, uid)
    if not owned then
      return false, "Couldn't find that companion pet."
    end

    e = {
      uid = uid,
      kind = kind,
      level = tonumber(owned.level or 1) or 1,
      stat_hp = tonumber(owned.stat_hp or 40) or 40,
      stat_attack = tonumber(owned.stat_attack or 1) or 1,
      nickname = tostring(owned.nickname or ""),
      fatigue = tonumber(owned.fatigue or _default_pet_fatigue()) or _default_pet_fatigue(),
      cooldown_ends_at = 0,
      owner_secret = secret,
      owner_name = owner_name,
      bucket_area_id = "",
      oncehub_key = "",
      home_area_id = area_id,
      home_x = sx,
      home_y = sy,
      home_z = sz,
      area_id = area_id,
      x = sx, y = sy, z = sz,
      direction = dir,
      next_move_time = world_time + 1.0,
      blocked_for = 0,
      bot_id = nil,
      with_owner = false,
      companion_summoned = true,
      companion_transient = true,
      exp = {
        active = false,
        started_at = 0,
        ends_at = 0,
        mood = "",
        dest = nil,
        lease_expires_at = 0,
        reward = nil,
        reward_pending = false,
        xp_reward = 0,
        skill_points_gained = 0,
      }
    }

    local bot_id = spawn_pet_bot(e)
    if not bot_id then
      return false, "Couldn't summon that companion pet."
    end

    e.bot_id = bot_id
    index_record(e)
    companion_live_entries[uid] = e
  end

  armed.summoned = true
  armed.summoned_area_id = tostring(area_id or "")
  pmem[PLAYER_ARMED_PET_KEY] = armed
  _safe_save_player_memory(secret, pmem)

  return true, "Companion pet summoned."
end

local function feed_pet(pid, e, bucket_area_id)
  local secret = helpers.get_safe_player_secret(pid)
  if secret ~= (e.owner_secret or "") then
    return false, "Only the owner can feed this pet."
  end

  if not e.owner_name or e.owner_name == "" then
    e.owner_name = Net.get_player_name(pid)
  end

  local mood = _pet_mood_from_fatigue(e.fatigue)
  if mood == "happy" then
    return false, "Your pet is already happy."
  end

  if not ezmemory.spend_player_fragments then
    return false, "Fragments support isn't installed in ezmemory yet."
  end

  local cost = tonumber(EXPEDITION.feed_frag_cost) or 1
  _dbg_frags(pid, "feed:before_spend")
  if not ezmemory.spend_player_fragments(pid, cost) then
    return false, "Not enough BugFrags."
  end
  _dbg_frags(pid, "feed:after_spend")

  e.fatigue = select(1, _feed_like_fatigue_relief(e.fatigue))

  _save_owned_pet_from_entry(e, false)
  save_bucket(bucket_area_id)
  _sync_live_companion_from_owned(_get_owned_pet(secret, tostring(e.uid or "")) or {})
  return true, "You fed your virus. It seems happier."
end

-- ====================== Public API ======================
function pets.list_pets(bucket_area_id, oncehub_key)
  local list = load_pet_list(bucket_area_id, oncehub_key)
  local out = {}

  for i, e in ipairs(list) do
    normalize_entry(e, bucket_area_id, oncehub_key)

    out[i] = {
      uid = e.uid,
      kind = e.kind,
      area_id = e.area_id,
      x = e.x, y = e.y, z = e.z,
      mood = mood_from_fatigue(e.fatigue),
      fatigue = e.fatigue,
      level = e.level,
      stat_hp = e.stat_hp,
      stat_attack = e.stat_attack,
      nickname = tostring(e.nickname or ""),
      bot_id = e.bot_id,
      expedition_active = expedition_active(e),
      cooldown_ends_at = e.cooldown_ends_at,
    }
  end

  return out
end

function pets.summon_pet(area_id, bucket_area_id, oncehub_key, kind, x, y, z, owner_secret, preferred_uid)
  kind = tostring(kind or "mettaur"):lower()
  if kind == "" then kind = "mettaur" end

  owner_secret = tostring(owner_secret or "")
  if owner_secret == "" then
    return nil, "missing_owner"
  end

  pets.ensure_player_pet_ids(owner_secret)

  local owned = _find_first_unplaced_owned_pet(owner_secret, kind, preferred_uid)
  if not owned then
    return nil, "no_available_pet"
  end

  local list = load_pet_list(bucket_area_id, oncehub_key)
  local owner_name = _owner_name_from_secret(owner_secret)

  local e = {
    uid = tostring(owned.uid),
    kind = kind,
    level = owned.level,
    stat_hp = owned.stat_hp,
    stat_attack = owned.stat_attack,
    nickname = tostring(owned.nickname or ""),
    home_area_id = area_id,
    bucket_area_id = bucket_area_id,
    oncehub_key = oncehub_key,
    area_id = area_id,
    x = x, y = y, z = z or 0,
    owner_secret = owner_secret,
    owner_name = owner_name or "",
    fatigue = owned.fatigue,
    cooldown_ends_at = 0,
    bot_id = "",
    exp = {
      active = false,
      started_at = 0,
      ends_at = 0,
      mood = "neutral",
      dest = nil,
      lease_expires_at = 0,
      reward = nil,
      reward_pending = false,
      xp_reward = 0,
      skill_points_gained = 0,
    }
  }

  table.insert(list, e)
  _save_owned_pet_from_entry(e, false)
  save_bucket(bucket_area_id)

  local bot_id = spawn_pet_bot(e)
  if not bot_id then
    dbg("summon_pet spawn failed uid=", e.uid, "kind=", kind, "area_id=", area_id)
    return nil, "spawn_failed"
  end

  e.bot_id = bot_id
  index_record(e)
  _save_owned_pet_from_entry(e, false)
  save_bucket(bucket_area_id)

  return e.uid
end

local function _remove_pet_internal(bucket_area_id, uid, force)
  local e = find_entry(bucket_area_id, uid)
  if not e then return false, "Pet not found." end

  -- Block removal if expedition active or cooldown (unless forced)
  if not force then
    if expedition_active(e) then
      local left = expedition_left(e)
      local where = (e.exp.dest and e.exp.dest.label) or (e.exp.dest and e.exp.dest.area_id) or "somewhere"
      return false, ("That pet is on an expedition (%s). Returns in %s."):format(tostring(where), _fmt_time_left(left))
    end
    if is_on_cooldown(e) then
      return false, "That pet is resting. Cooldown: ".._fmt_time_left(cooldown_left(e)).."."
    end
    if e.in_training then
      return false, "That pet is currently in a training session."
    end
  end

  -- despawn runtime bot if present
  if e.bot_id and Net.is_bot(e.bot_id) then
    dbg("Removing bot uid=", e.uid, "bot_id=", e.bot_id, "force=", force and "true" or "false")
    pcall(Net.remove_bot, e.bot_id)
  end

  -- remove runtime record if exists
  local rec = records[tostring(uid)]
  if rec then
    despawn_pet_bot(rec, false)
    unindex_record(rec)
  end

  _save_owned_pet_from_entry(e, true)
  -- remove from storage list
  local list = load_pet_list(bucket_area_id, e.oncehub_key)
  for i = #list, 1, -1 do
    if tostring(list[i].uid or "") == tostring(uid) then
      table.remove(list, i)
      break
    end
  end

  -- clear expedition map if needed
  if e.owner_secret and e.owner_secret ~= "" then
    local active_uid = get_active_expedition_uid(bucket_area_id, e.owner_secret)
    if active_uid and tostring(active_uid) == tostring(uid) then
      clear_active_expedition(bucket_area_id, e.owner_secret)
    end
  end

  save_bucket(bucket_area_id)
  return true, "Pet removed."
end

function pets.remove_pet(area_id, bucket_area_id, oncehub_key, uid_or_bot)
  if not uid_or_bot then return false, "Missing pet id." end
  local uid = tostring(uid_or_bot)

  if bot_to_uid[uid] then
    uid = bot_to_uid[uid]
  end

  return _remove_pet_internal(bucket_area_id, uid, false)
end

function pets.remove_all(area_id, bucket_area_id, oncehub_key)
  local list = load_pet_list(bucket_area_id, oncehub_key)

  -- Respect the same guards as single-remove:
  -- do NOT remove pets on expedition or cooldown.
  local removed, skipped = 0, 0

  for i = #list, 1, -1 do
    local e = normalize_entry(list[i], bucket_area_id, oncehub_key)
    if e and (expedition_active(e) or is_on_cooldown(e) or e.in_training) then
      skipped = skipped + 1
    else
      _save_owned_pet_from_entry(e, true)
      local uid = tostring(list[i].uid or "")

      -- despawn runtime record
      local rec = records[uid]
      if rec then
        despawn_pet_bot(rec, false)
        unindex_record(rec)
      end

      -- despawn bot if stored
      if list[i].bot_id and Net.is_bot(list[i].bot_id) then
        pcall(Net.remove_bot, list[i].bot_id)
      end

      table.remove(list, i)
      removed = removed + 1
    end
  end

  save_bucket(bucket_area_id)
  return removed, skipped
end

function pets.rehydrate_for_hp(area_id, bucket_area_id, oncehub_key)
  local list = load_pet_list(bucket_area_id, oncehub_key)

  for _, e in ipairs(list) do
    normalize_entry(e, bucket_area_id, oncehub_key)

    -- refresh owner_secret from lease (useful for older saves)
    if (not e.owner_secret) or e.owner_secret == "" then
      local s = _get_hp_owner_secret(bucket_area_id, oncehub_key)
      if type(s) == "string" and s ~= "" then e.owner_secret = s end
    end

    -- spawn bot only if this entry lives in this area
    if e.area_id == area_id and not e.with_owner and not e.in_training then
      local uid = tostring(e.uid)
      local rec = records[uid]
      if not rec then
        rec = {
          uid = uid,
          kind = tostring(e.kind or ""):lower(),
          area_id = area_id,
          x = e.x or 0, y = e.y or 0, z = e.z or 0,
          direction = "Down Left",
          next_move_time = world_time + 1.0,
          blocked_for = 0,
          owner_secret = e.owner_secret,
          owner_name = e.owner_name,
          stat_attack = e.stat_attack,
        }
        spawn_pet_bot(rec)
        index_record(rec)
      else
        if not rec.bot_id or not Net.is_bot(rec.bot_id) then
          spawn_pet_bot(rec)
          index_record(rec)
        end
      end
      e.bot_id = rec.bot_id
    end
  end

  save_bucket(bucket_area_id)
end

-- Optional: rehydrate any pets in a given area (scans all keys in the bucket)
function pets.rehydrate_all_for_area(area_id, bucket_area_id)
  local mem = ensure_bucket_mem(bucket_area_id)
  for oncehub_key, list in pairs(mem.oncehub_pets_v1 or {}) do
    if type(list) == "table" then
      for _, e in ipairs(list) do
        normalize_entry(e, bucket_area_id, oncehub_key)
        if e.area_id == area_id and not e.with_owner and not e.in_training then
          pets.rehydrate_for_hp(area_id, bucket_area_id, oncehub_key)
          break
        end
      end
    end
  end
end

-- ====================== Interaction ======================
local interaction_lock = {}

local function with_interaction_lock(pid, fn)
  if interaction_lock[pid] then return end
  interaction_lock[pid] = true
  async(function()
    local ok, err = pcall(fn)
    if not ok then
      dbg("PET interaction error pid=", tostring(pid), "err=", tostring(err))
    end
    await(Async.sleep(0.25))
    interaction_lock[pid] = nil
  end)
end

local function open_pet_action_menu(pid, e, bucket_area_id)
  local mood = mood_from_fatigue(e.fatigue)
  local secret = helpers.get_safe_player_secret(pid)
  local is_owner = (secret == (e.owner_secret or ""))

  if e.companion_summoned then
    local display = _entry_display_name(e)
    local owner = tostring(e.owner_name or "")
    if owner == "" then owner = "someone" end

    if is_owner then
      local res = await(Async.question_player(pid, ("Do you want to call back %s?"):format(display)))
      if res == 1 then
        local ok, msg = pets.call_back_companion(pid)
        if msg and msg ~= "" then
          Net.message_player(pid, msg)
        elseif not ok then
          Net.message_player(pid, "Couldn't call back that companion pet.")
        end
      end
    else
      local res = await(Async.question_player(pid, ("You see %s (%s's pet). Do you want to pet it?"):format(display, owner)))
      if res == 1 then
        _reduce_battle_fatigue_from_companion_petting(e, bucket_area_id)
        Net.message_player(pid, _pet_it_text(mood))
      end
    end

    return
  end

  -- If pet is currently roaming, just show a flavor line.
  if expedition_active(e) then
    local owner = e.owner_name
    if owner == "" then owner = "someone" end

    local is_owner = helpers.get_safe_player_secret(pid) == (e.owner_secret or "")

    -- Nickname-aware message (falls back to old messages if no nickname)
    local nick = _sanitize_nickname(e.nickname)
    if nick ~= tostring(e.nickname or "") then
      e.nickname = nick
      save_bucket(bucket_area_id)
    end

    if nick ~= "" then
      if is_owner then
        Net.message_player(pid, ("You see %s (your pet). It seems to be busy looking through the area."):format(nick))
      else
        Net.message_player(pid, ("You see %s (%s's pet). It seems to be busy."):format(nick, owner))
      end
    else
      if is_owner then
        Net.message_player(pid, "You see your pet. It seems to be busy looking through the area.")
      else
        Net.message_player(pid, ("You see %s's pet. It seems to be busy."):format(owner))
      end
    end

    return
  end

  -- If reward is pending, claim it now (owner only).
  if e.exp and e.exp.reward_pending and e.exp.reward then
    if secret ~= (e.owner_secret or "") then
      Net.message_player(pid, "This pet doesn't seem interested in showing you anything.")
      return
    end

    if not e.owner_name or e.owner_name == "" then
      e.owner_name = Net.get_player_name(pid)
    end

    Net.message_player(pid, result_flavor(e.exp.mood or mood, e.exp.reward))

    -- apply reward, with gp fallback if not on team
    local r = e.exp.reward
    if r and r.kind == "gp" and not owner_on_team(pid) then
      -- preserve your existing fallback behavior
      r = { kind="moneyz", amount=r.money_fallback_amount or 1000 }
    end

    local ok, err = pcall(apply_reward_to_player, pid, r)
    if not ok then
      dbg("claim_reward FAILED uid=", tostring(e.uid), "err=", tostring(err))
      Net.message_player(pid, "Couldn't claim reward (server error).")
      return
    end

    local xp_reward = math.max(0, math.floor(tonumber(e.exp.xp_reward) or 0))
    local skill_points_gained = math.max(0, math.floor(tonumber(e.exp.skill_points_gained) or 0))

    if xp_reward > 0 and _pet_xp_notifications_enabled_from_pmem(_safe_get_player_memory(secret)) then
      local xp_msg = ("%s gained %d XP."):format(_entry_display_name(e), xp_reward)
      if skill_points_gained > 0 then
        xp_msg = xp_msg .. (" %d skill point%s available."):format(skill_points_gained, skill_points_gained == 1 and "" or "s")
      end
      Net.message_player(pid, xp_msg)
    end

    e.exp.xp_reward = 0
    e.exp.skill_points_gained = 0
    e.exp.reward_pending = false
    e.exp.reward = nil
    save_bucket(bucket_area_id)

    return
  end

  local kind_key = tostring(e.kind or ""):lower()
  local battle_def = BATTLE_PETS[kind_key]

  -- Sanitize nickname on read (so title never gets weird)
  local nick = _sanitize_nickname(e.nickname)
  if nick ~= tostring(e.nickname or "") then
    e.nickname = nick
    save_bucket(bucket_area_id)
  end
  local display = (nick ~= "" and nick) or "Virus Pet"

  -- Board title shows current BugFrags
  local frags = _get_player_bugfrags(pid)
  local title = ("%s - %d BugFrags"):format(display, frags)

  local can_take, take_disabled_msg = true, nil
  local has_armed_pet = false

  -- Build menu options
  local opts = {}

  if not is_owner then
    can_take = false
    take_disabled_msg = "Only the owner can take this pet with them."
  end

  if can_take then
    local cur_area = Net.get_player_area(pid)
    if tostring(cur_area or "") ~= tostring(e.home_area_id or "") then
      can_take = false
      take_disabled_msg = "Only available from this pet's home HP."
    end
  end

  if can_take then
    local pmem = _safe_get_player_memory(secret)
    has_armed_pet = pmem and pmem[PLAYER_ARMED_PET_KEY] ~= nil
  end

  if can_take then
    table.insert(opts, helpers.create_bbs_option("Take With You"))
  else
    table.insert(opts, helpers.create_bbs_option("Take With You ("..tostring(take_disabled_msg or "unavailable")..")"))
  end
  local can_send, send_disabled_msg = true, nil

  if is_on_cooldown(e) then
    can_send = false
    send_disabled_msg = "Cooldown: ".._fmt_time_left(cooldown_left(e))
  end

  if not is_owner then
    can_send = false
    send_disabled_msg = "Only the owner can send expeditions."
  end

  -- Block all owner actions if the pet is currently in a training session
  if e.in_training then
    can_take = false
    take_disabled_msg = "This pet is in training."
    can_send = false
    send_disabled_msg = "This pet is in training."
  end

  if can_send then
    table.insert(opts, helpers.create_bbs_option("Send on expedition"))
  else
    table.insert(opts, helpers.create_bbs_option("Send on expedition ("..tostring(send_disabled_msg or "unavailable")..")"))
  end

  -- Feed only for owner (avoid confusing non-owners)
  if is_owner and mood ~= "happy" then
    table.insert(opts, helpers.create_bbs_option("Feed 1 BugFrag"))
  end

  table.insert(opts, helpers.create_bbs_option("Pet it"))

  if is_owner then
    table.insert(opts, helpers.create_bbs_option("Set/Clear Nickname"))
  end

  table.insert(opts, helpers.create_bbs_option("Nevermind"))

  -- IMPORTANT: use the correct helper name
  local board = _open_menu_ignoring_custom(pid, title, {r=255,g=230,b=160}, opts, "pets:act")
  local sel = await(board.selection_once())

  -- Always close board after selection (and guard custom.lua close hook)
  _mark_ignore_next_close(pid, "pets:act_close")
  pcall(function() board:close() end)
  pcall(Net.close_bbs, pid)

  if not sel or sel == "Nevermind" then
    return
  end

  if sel:find("^Take With You") == 1 then
    if not can_take then
      Net.message_player(pid, take_disabled_msg or "Couldn't take pet.")
      return
    end

    local replace_existing = false

    if has_armed_pet then
      local res = await(Async.question_player(pid, "Do you want to replace your current pet?"))

      -- Assumes 1 = Yes. If your build returns the opposite, flip this check.
      if res ~= 1 then
        Net.message_player(pid, "Keeping your current pet.")
        return
      end

      replace_existing = true
    end

    local ok, msg = take_pet_with_you(pid, e, bucket_area_id, replace_existing)
    Net.message_player(pid, msg or (ok and "Done." or "Couldn't take pet."))
    return
  end

  if sel:find("^Send on expedition") == 1 then
    if not can_send then
      Net.message_player(pid, send_disabled_msg or "Not available.")
      return
    end
    local ok, msg = start_expedition_for_player(pid, e, bucket_area_id)
    if msg and msg ~= "" then
      Net.message_player(pid, msg)
    elseif ok then
      Net.message_player(pid, "Sent on expedition.")
    else
      Net.message_player(pid, "Couldn't start expedition.")
    end
    return
  end

  if sel == "Feed 1 BugFrag" then
    local ok, msg = feed_pet(pid, e, bucket_area_id)
    Net.message_player(pid, msg or (ok and "Fed." or "Couldn't feed."))
    return
  end

  if sel == "Pet it" then
    Net.message_player(pid, _pet_it_text(mood))
    return
  end

  if sel == "Set/Clear Nickname" then
    if not is_owner then
      Net.message_player(pid, "Only the owner can set a nickname.")
      return
    end

    if not Async or not Async.prompt_player then
      Net.message_player(pid, "Nickname input isn't available on this server build.")
      return
    end

    -- IMPORTANT:
    -- Do NOT call Net.prompt_player here. On your server it opens a prompt but doesn't give us an await-able promise.
    -- That causes us to miss the real input ("Metty") and later accidentally consume a "0" from some other textbox close.
    dbg("nickname prompt: opening pid=", tostring(pid))
    local input = await(Async.prompt_player(pid))
    dbg("nickname prompt: response pid=", tostring(pid), "value=", tostring(input))

    -- If player cancelled/closed, many systems send "0". Treat that as cancel (NOT clear).
    if input == nil then
      Net.message_player(pid, "Nickname cancelled.")
      return
    end
    input = tostring(input)
    if input == "0" then
      Net.message_player(pid, "Nickname cancelled.")
      return
    end

    local new_nick = _sanitize_nickname(input)
    e.nickname = new_nick
    _save_owned_pet_from_entry(e, false)
    save_bucket(bucket_area_id)

    if new_nick == "" then
      Net.message_player(pid, "Nickname cleared.")
    else
      Net.message_player(pid, ("Nickname set to: %s"):format(new_nick))
    end
    return
  end
end

Net:on("actor_interaction", function(event)
  local player_id = event.player_id
  local actor_id = event.actor_id or event.actor
  if not player_id or not actor_id then return end

  local uid = bot_to_uid[tostring(actor_id)]
  if not uid then return end

  -- Find the live entry for this uid.
  with_interaction_lock(player_id, function()
    local live = companion_live_entries[tostring(uid)]
    if live then
      open_pet_action_menu(player_id, live, tostring(live.bucket_area_id or ""))
      return
    end

    -- Fallback: scan persisted HP pet entries.
    for _, bucket_area_id in ipairs(Net.list_areas() or {}) do
      local e = find_entry(bucket_area_id, uid)
      if e then
        open_pet_action_menu(player_id, e, bucket_area_id)
        return
      end
    end

    Net.message_player(player_id, "This pet seems confused (missing memory entry).")
  end)
end)

-- ====================== Tick loop ======================
local function refresh_area_has_players()
  area_has_players = {}
  for _, area_id in ipairs(Net.list_areas() or {}) do
    local players = Net.list_players(area_id) or {}
    if #players > 0 then
      area_has_players[area_id] = true
    end
  end
end

local next_expedition_scan = 0

local function scan_and_complete_expeditions()
  local now = _now()
  if world_time < next_expedition_scan then return end
  next_expedition_scan = world_time + 2.0

  for _, bucket_area_id in ipairs(Net.list_areas() or {}) do
    local mem = ezmemory.get_area_memory(bucket_area_id)
    if mem and type(mem.oncehub_pets_v1) == "table" then
      for oncehub_key, list in pairs(mem.oncehub_pets_v1) do
        if type(list) == "table" then
          for _, e in ipairs(list) do
            normalize_entry(e, bucket_area_id, oncehub_key)
            if expedition_active(e) and (tonumber(e.exp.ends_at) or 0) > 0 and (tonumber(e.exp.ends_at) or 0) <= now then
              dbg("Tick completing uid=", e.uid, "bucket=", bucket_area_id, "once_key=", oncehub_key)
              complete_expedition_for_entry(e, bucket_area_id)
            end
          end
        end
      end
    end
  end
end

Net:on("tick", function(event)
  local dt = event.delta_time or 0
  world_time = world_time + dt

  if world_time >= next_area_scan_time then
    next_area_scan_time = world_time + 1.0
    refresh_area_has_players()
  end

  -- Finish expeditions even if players are offline
  scan_and_complete_expeditions()

  -- Move pets only in areas with players
  for area_id, uids in pairs(by_area) do
    if area_has_players[area_id] then
      for uid, _ in pairs(uids) do
        local rec = records[uid]
        if rec and rec.bot_id and Net.is_bot(rec.bot_id) then
          if rec.waypoint then
            move_toward_waypoint(rec, dt)
          elseif world_time >= (rec.next_move_time or 0) then
            if choose_wander_waypoint(rec) then
              -- continue
            else
              rec.next_move_time = world_time + 1.0
            end
          end
        end
      end
    end
  end
end)

-- Public: returns the player's current bugfrag count
function pets.get_player_bugfrags(pid)
  return _get_player_bugfrags(pid)
end

-- Public: returns info about the pet currently on expedition for this player, or nil if none.
-- Returns: { display_name, secs_left } or nil
function pets.get_expedition_pet_info(owner_or_pid)
  local owner_secret = _resolve_pet_owner_secret(owner_or_pid)
  if owner_secret == "" then return nil end

  pets.ensure_player_pet_ids(owner_secret)
  local owned = pets.list_owned_pets(owner_secret)

  for _, p in ipairs(owned) do
    if type(p.placement) == "table" then
      local bucket_area_id = tostring(p.placement.bucket_area_id or "")
      if bucket_area_id ~= "" then
        local e = find_entry(bucket_area_id, p.uid)
        if e and expedition_active(e) then
          local base_name = _companion_base_name(p.kind)
          local nickname = tostring(p.nickname or "")
          local display_name = (nickname ~= "" and nickname) or base_name
          return {
            display_name = display_name,
            secs_left = expedition_left(e),
          }
        end
      end
    end
  end

  return nil
end

pets.TRAINING_XP = PET_TRAINING_XP

function pets.get_training_info(owner_or_pid)
  local secret = _resolve_pet_owner_secret(owner_or_pid)
  if secret == "" then return nil end
  local pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then return nil end
  local t = pmem[PET_TRAINING_MEM_KEY]
  if type(t) ~= "table" then return nil end
  return t
end

function pets.start_training(pid, cost, duration_sec, cooldown_sec)
  cost         = math.max(0,  math.floor(tonumber(cost)         or 90000))
  duration_sec = math.max(60, math.floor(tonumber(duration_sec) or 3600))
  cooldown_sec = math.max(0,  math.floor(tonumber(cooldown_sec) or 3600))

  local secret = helpers.get_safe_player_secret(pid)
  if not secret or secret == "" then
    return false, "Couldn't find your data."
  end

  local pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then return false, "Data not ready." end

  if type(pmem[PET_TRAINING_MEM_KEY]) == "table" then
    return false, "A pet is already in training!"
  end

  local armed = pmem[PLAYER_ARMED_PET_KEY]
  if type(armed) ~= "table" then
    return false, "You don't have a companion pet with you."
  end

  if armed.summoned == true then
    return false, "Call your pet back before sending them to training."
  end

  local uid            = tostring(armed.uid  or "")
  local kind           = tostring(armed.kind or "mettaur"):lower()
  local bucket_area_id = tostring(armed.bucket_area_id or "")
  if uid == "" then return false, "Your pet has no ID." end

  local owned = _get_owned_pet(secret, uid)
  if owned then
    local cd = tonumber(owned.training_cooldown_ends_at or 0) or 0
    if cd > _now() then
      local left = math.ceil((cd - _now()) / 60)
      return false, ("That pet needs %d more minute(s) of rest before training again."):format(left)
    end
  end

  if not ezmemory.spend_player_money(pid, cost) then
    return false, ("You need %dz for a training session."):format(cost)
  end

  local def          = PET_DEFS[kind] or {}
  local base_name    = tostring(def.name or kind:gsub("^%l", string.upper))
  local nickname     = owned and tostring(owned.nickname or "") or ""
  local display_name = (nickname ~= "" and nickname) or base_name

  local ok = _detach_armed_pet_for_training(secret)
  if not ok then
    ezmemory.spend_player_money(pid, -cost)
    return false, "Couldn't take your pet for training."
  end

  pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then
    ezmemory.spend_player_money(pid, -cost)
    return false, "Data error, please try again."
  end

  pmem[PET_TRAINING_MEM_KEY] = {
    uid            = uid,
    kind           = kind,
    display_name   = display_name,
    ends_at        = _now() + duration_sec,
    cooldown_sec   = cooldown_sec,
    bucket_area_id = bucket_area_id,
  }
  _safe_save_player_memory(secret, pmem)

  return true, display_name .. " has been taken in for training!"
end

function pets.claim_trained_pet(pid)
  local secret = helpers.get_safe_player_secret(pid)
  if not secret or secret == "" then
    return false, "Couldn't find your data."
  end

  local pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then return false, "Data not ready." end

  local t = pmem[PET_TRAINING_MEM_KEY]
  if type(t) ~= "table" then
    return false, "No pet currently in training."
  end

  local ends_at = tonumber(t.ends_at or 0) or 0
  local now     = _now()

  if now < ends_at then
    local left = math.ceil((ends_at - now) / 60)
    return false, ("%s isn't done yet! %d minute(s) remaining."):format(tostring(t.display_name or "Your pet"), left)
  end

  local uid          = tostring(t.uid or "")
  local display_name = tostring(t.display_name or "Your pet")

  if uid == "" then
    pmem[PET_TRAINING_MEM_KEY] = nil
    _safe_save_player_memory(secret, pmem)
    return false, "Training record was corrupted, sorry about that."
  end

  _award_owned_pet_xp_for_secret(secret, uid, PET_TRAINING_XP)

  local pmem2 = _safe_get_player_memory(secret)
  if type(pmem2) == "table" then
    local store = pmem2[OWNED_PETS_MEM_KEY]
    if type(store) == "table" and type(store.pets) == "table" then
      local p = _normalize_owned_pet(store.pets[uid])
      if type(p) == "table" then
        local saved_cooldown = math.max(0, math.floor(tonumber(t.cooldown_sec or 3600) or 3600))
        p.training_cooldown_ends_at = _now() + saved_cooldown
        store.pets[uid] = p
        pmem2[OWNED_PETS_MEM_KEY] = store
        _safe_save_player_memory(secret, pmem2)
      end
    end
  end

  -- Clear the in_training flag on the HP entry so the pet can be interacted with again
  local t_bucket = tostring(t.bucket_area_id or "")
  if uid ~= "" and t_bucket ~= "" then
    local entry = find_entry(t_bucket, uid)
    if entry then
      entry.in_training = nil
      save_bucket(t_bucket)
    end
  end

  local pmem3 = _safe_get_player_memory(secret)
  if type(pmem3) == "table" then
    pmem3[PET_TRAINING_MEM_KEY] = nil
    _safe_save_player_memory(secret, pmem3)
  end

  local arm_ok, arm_success = pcall(pets.arm_owned_pet, pid, uid, true)
  if not arm_ok or not arm_success then
    return true, (display_name .. " completed training and gained " .. PET_TRAINING_XP .. " XP! (Returned to your inventory)")
  end

  return true, (display_name .. " completed training and gained " .. PET_TRAINING_XP .. " XP!")
end

function pets.get_training_pet_info(owner_or_pid)
  local secret = _resolve_pet_owner_secret(owner_or_pid)
  if secret == "" then return nil end
  local pmem = _safe_get_player_memory(secret)
  if type(pmem) ~= "table" then return nil end
  local t = pmem[PET_TRAINING_MEM_KEY]
  if type(t) ~= "table" then return nil end
  return {
    display_name = tostring(t.display_name or "Pet"),
    secs_left    = math.max(0, (tonumber(t.ends_at) or 0) - _now()),
  }
end

now_seed_rng()
_validate_reward_tables()

return pets