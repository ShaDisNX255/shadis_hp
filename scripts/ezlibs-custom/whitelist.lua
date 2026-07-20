local whitelist = {}

local helpers = require('scripts/ezlibs-scripts/helpers')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local enums = require('scripts/libs/enums')
local AssetType = enums.AssetType
local PackageType = enums.PackageType

local ENFORCED_AREAS = {
  WCity1 = true,
  WCity2 = true,
  WCity3 = true,
  TechLab1 = true,
  TechLab2 = true,
  Dungeon1 = true,
}

local BASE_WHITELIST_DISK_PATH = "./assets/whitelist.txt"
local GENERATED_WHITELIST_DIR = "/server/assets/generated_whitelists"
local BLANK_WHITELIST_ASSET_PATH = "/server/assets/blank_whitelist.txt"

-- v1 stored ownership by package ID.
-- v2 stores cards/programs by permanent whitelist keys instead.
local LEGACY_PLAYER_UNLOCKS_MEM_KEY = "__player_mod_unlocks_v1"
local PLAYER_UNLOCKS_MEM_KEY = "__player_mod_unlocks_v2"

local DEBUG_WHITELIST = false

local function printd(...)
  if not DEBUG_WHITELIST then return end
  print("[whitelist]", ...)
end

-- Stable non-card package definitions.
-- Keep the table key permanent even if package_id changes again later.
whitelist.PACKAGE_DEFS = {
  undershirt = {
    package_id = "com.OFC.block.EXE6-013-UnderShirt",
  },
}

-- Backwards-compatible public table used by existing scripts.
whitelist.PACKAGES = {
  undershirt = whitelist.PACKAGE_DEFS.undershirt.package_id,
}

whitelist.CARDS = {
  reflecmet1 = {
    package_id = "com.wcity.OFC.card.EXE6-091-ReflecMet1",
    legacy_package_ids = { "com.OFC.card.EXE6-091-ReflecMet1" },
    asset_path = "/server/assets/chips/EXE6-Reflect.zip",
    code = "A",
  },

  shockwave = {
    package_id = "com.OFC.card.EXEPoN-051-ShockWave",
    asset_path = "/server/assets/chips/EXEPoN-Shockwave.zip",
    code = "*",
  },

  longsword = {
    package_id = "com.OFC.card.EXEPoN-040-LongSword",
    asset_path = "/server/assets/chips/EXEPoN-LongSword.zip",
    code = "*",
  },

  windbox = {
    package_id = "com.OFC.card.EXE6-134-Toppuu",
    asset_path = "/server/assets/chips/EXE6-Windbox.zip",
    code = "*",
  },

  ratton1 = {
    package_id = "com.OFC.card.EXEPoN-031-Ratton1",
    asset_path = "/server/assets/chips/EXEPoN-Ratton.zip",
    code = "*",
  },

  bubbler = {
    package_id = "rune.wcity.legacy.bubbler",
    legacy_package_ids = { "rune.legacy.bubbler" },
    asset_path = "/server/assets/chips/EXE3-Bubbler.zip",
    code = "P",
  },
  yoyo1 = {
    package_id = "com.wcity.OFC.card.EXE6-018-YoYo",
    legacy_package_ids = { "com.OFC.card.EXE6-018-YoYo" },
    asset_path = "/server/assets/chips/EXE6-YoYo.zip",
    code = "L",
  },
  HellsBurner1 = {
    package_id = "com.wcity.OFC.card.EXE6-019-HellsBurner1",
    legacy_package_ids = { "com.OFC.card.EXE6-019-HellsBurner1" },
    asset_path = "/server/assets/chips/EXE6-HellsBurner1.zip",
    code = "H",
  },
  MachineGun1 = {
    package_id = "com.wcity.OFC.card.EXE6-055-MachineGun1",
    legacy_package_ids = { "com.OFC.card.EXE6-055-MachineGun1" },
    asset_path = "/server/assets/chips/EXE6-MachineGun1.zip",
    code = "T",
  },
  MachineGun2 = {
    package_id = "com.wcity.OFC.card.EXE6-056-MachineGun2",
    legacy_package_ids = { "com.OFC.card.EXE6-056-MachineGun2" },
    asset_path = "/server/assets/chips/EXE6-MachineGun2.zip",
    code = "T",
  },
  KillerSensor1 = {
    package_id = "com.wcity.OFC.card.EXE6-116-KillerSensor1",
    legacy_package_ids = { "com.OFC.card.EXE6-116-KillerSensor1" },
    asset_path = "/server/assets/chips/EXE6-KillerSensor1.zip",
    code = "J",
  },
  KillerSensor2 = {
    package_id = "com.wcity.OFC.card.EXE6-117-KillerSensor2",
    legacy_package_ids = { "com.OFC.card.EXE6-117-KillerSensor2" },
    asset_path = "/server/assets/chips/EXE6-KillerSensor2.zip",
    code = "N",
  },
  RabiRing1 = {
    package_id = "com.wcity.OFC.card.EXEPoN-017-RabiRing1",
    legacy_package_ids = { "com.OFC.card.EXEPoN-017-RabiRing1" },
    asset_path = "/server/assets/chips/EXEPoN-RabiRing1.zip",
    code = "A",
  },
  RabiRing2 = {
    package_id = "com.wcity.OFC.card.EXEPoN-018-RabiRing2",
    legacy_package_ids = { "com.OFC.card.EXEPoN-018-RabiRing2" },
    asset_path = "/server/assets/chips/EXEPoN-RabiRing2.zip",
    code = "B",
  },
  Ratton2 = {
    package_id = "com.wcity.OFC.card.EXEPoN-032-Ratton2",
    legacy_package_ids = { "com.OFC.card.EXEPoN-032-Ratton2" },
    asset_path = "/server/assets/chips/EXEPoN-Ratton2.zip",
    code = "A",
  },
  sonicwave = {
    package_id = "com.wcity.OFC.card.EXEPoN-052-SonicWave",
    legacy_package_ids = { "com.OFC.card.EXEPoN-052-SonicWave" },
    asset_path = "/server/assets/chips/EXEPoN-SonicWave.zip",
    code = "G",
  },
  spreadgun1 = {
    package_id = "com.OFC.card.EXE6-009-SpreadGun1",
    asset_path = "/server/assets/chips/EXE6-SpreadGun1.zip",
    code = "*",
  },
  spreadgun2 = {
    package_id = "com.wcity.OFC.card.EXE6-010-SpreadGun2",
    legacy_package_ids = { "com.OFC.card.EXE6-010-SpreadGun2" },
    asset_path = "/server/assets/chips/EXE6-SpreadGun2.zip",
    code = "A",
  },
  thunderball = {
    package_id = "com.wcity.OFC.card.EXE6-029-ThunderBall",
    legacy_package_ids = { "com.OFC.card.EXE6-029-ThunderBall" },
    asset_path = "/server/assets/chips/EXE6-ThunderBall.zip",
    code = "*",
  },
  roll1 = {
    package_id = "com.wcity.k1rbyat1na.card.EXE6-222-Roll",
    legacy_package_ids = { "com.k1rbyat1na.card.EXE6-222-Roll" },
    asset_path = "/server/assets/chips/EXE6-Roll1.zip",
    code = "R",
  },
  gutsman1 = {
    package_id = "com.wcity.louise.card.gutsmanv1",
    legacy_package_ids = { "com.louise.card.gutsmanv1" },
    asset_path = "/server/assets/chips/EXE3-Gutsman1.zip",
    code = "G",
  },
  rec30 = {
    package_id = "com.wcity.OFC.card.EXE6-157-Recovery30",
    legacy_package_ids = { "com.OFC.card.EXE6-157-Recovery30" },
    asset_path = "/server/assets/chips/EXE6-Rec30.zip",
    code = "Q",
  },
  heatshot = {
    package_id = "com.wcity.OFC.card.EXEPoN-014-HeatShot",
    legacy_package_ids = { "com.OFC.card.EXEPoN-014-HeatShot" },
    asset_path = "/server/assets/chips/EXEPoN-HeatShot.zip",
    code = "*",
  },
  dashatk = {
    package_id = "com.wcity.louise.card.dashattck",
    legacy_package_ids = { "com.louise.card.dashattck" },
    asset_path = "/server/assets/chips/BN3-DashAtk.zip",
    code = "C",
  },

  wavearm = {
    package_id = "hoov.wcity1.cards.wavearm1",
    legacy_package_ids = { "hoov.cards.wavearm1" },
    asset_path = "/server/assets/chips/BN6-Wavearm1.zip",
    code = "G",
  },

  boomerang1 = {
    package_id = "com.wcity.OFC.card.EXEPoN-066-Boomerang1",
    legacy_package_ids = { "com.OFC.card.EXEPoN-066-Boomerang1" },
    asset_path = "/server/assets/chips/EXEPoN-Boomerang1.zip",
    code = "L",
  },

  boomerang2 = {
    package_id = "com.wcity.OFC.card.EXEPoN-067-Boomerang2",
    legacy_package_ids = { "com.OFC.card.EXEPoN-067-Boomerang2" },
    asset_path = "/server/assets/chips/EXEPoN-Boomerang2.zip",
    code = "O",
  },

  highcannon = {
    package_id = "com.wcity.OFC.card.EXEPoN-002-HighCannon",
    legacy_package_ids = { "com.OFC.card.EXEPoN-002-HighCannon" },
    asset_path = "/server/assets/chips/EXEPoN-HighCannon.zip",
    code = "C",
  },

  gundelsol1 = {
    package_id = "com.wcity.OFC.card.EXE6-015-GunDelSol1",
    legacy_package_ids = { "com.OFC.card.EXE6-015-GunDelSol1" },
    asset_path = "/server/assets/chips/EXE6-GunDelSol1.zip",
    code = "*",
  },

  energybomb = {
    package_id = "com.wcity.rune.k1rbyat1na.card.EXE6-060-EnergyBomb",
    legacy_package_ids = { "com.rune.k1rbyat1na.card.EXE6-060-EnergyBomb" },
    asset_path = "/server/assets/chips/EXE6-EnergyBomb.zip",
    code = "*",
  },

  megaenergybomb = {
    package_id = "com.wcity.rune.k1rbyat1na.card.EXE6-061-MegaEnergyBomb",
    legacy_package_ids = { "com.rune.k1rbyat1na.card.EXE6-061-MegaEnergyBomb" },
    asset_path = "/server/assets/chips/EXE6-MegaEnergyBomb.zip",
    code = "O",
  },

  stonecube = {
    package_id = "com.OFC.card.EXE6-138-StoneCube",
    asset_path = "/server/assets/chips/EXE6-StoneCube.zip",
    code = "*",
  },

  attack20 = {
    package_id = "com.wcity.OFC.card.EXEPoN-121-Attack+20",
    legacy_package_ids = { "com.OFC.card.EXEPoN-121-Attack+20" },
    asset_path = "/server/assets/chips/EXEPoN-Attack20.zip",
    code = "*",
  },
  barrier = {
    package_id = "Barr10.wcity.Library.92",
    legacy_package_ids = { "Barr10.Unified.Library.92" },
    asset_path = "/server/assets/chips/EXE6-Barrier.zip",
    code = "*",
  },
  darkhole = {
    package_id = "com.OFC.card.EXE4-132-DarkHole",
    asset_path = "/server/assets/chips/EXE4-Darkhole.zip",
    code = "*",
  },
  pulsebeam1 = {
    package_id = "com.OFC.card.EXE5-012-PulseBeam1",
    asset_path = "/server/assets/chips/EXE5-Pulsebeam1.zip",
    code = "P",

    display_name = "PulseBeam1",
    preview_key = "pulsebeam1",
    folder_card = "regular",
  },
  shademan1 = {
    package_id = "com.OFC.card.EXE5-262-ShadeMan",
    asset_path = "/server/assets/chips/EXE5-Shademan.zip",
    code = "S",
  },
  poltergeist = {
    package_id = "com.darkware.card.EXE5-Poltergeist",
    asset_path = "/server/assets/chips/EXE5-Poltergeist.zip",
    code = "*",
  },
  meteorearth1 = {
    package_id = "com.wcity.OFC.card.EXE5-093-MeteorEarth1",
    asset_path = "/server/assets/chips/EXE5-MeteorEarth1.zip",
    code = "A",

    display_name = "MeteorEarth1",
    preview_key = "meteorearth1",
    folder_card = "regular",
  },
  strawdoll = {
    package_id = "com.wcity.OFC.card.EXE6-153-WaraNingyou",
    asset_path = "/server/assets/chips/EXE6-StrawDoll.zip",
    code = "*",

    display_name = "StrawDoll",
    preview_key = "strawdoll",
    folder_card = "regular",
  },
  count1 = {
    package_id = "com.wcity.k1rbyat1na.card.EXE6-276-Hakushaku",
    asset_path = "/server/assets/chips/EXE6-Count.zip",
    code = "H",

    display_name = "Count",
    preview_key = "count1",
    folder_card = "mega",
  },
}

-- Current and legacy package-ID indexes.
-- Legacy IDs resolve ownership/migrations, but are never authorized in a
-- generated whitelist. Only current package IDs are authorized.
local card_by_package_id = {}
local card_key_by_package_id = {}
local current_card_key_by_package_id = {}

local package_key_by_package_id = {}
local current_package_key_by_package_id = {}

local function register_unique(index, package_id, stable_key, label)
  package_id = tostring(package_id or "")
  if package_id == "" then return end

  local existing = index[package_id]
  if existing and existing ~= stable_key then
    print(string.format(
      "[whitelist] ERROR: duplicate %s package ID '%s' for '%s' and '%s'",
      tostring(label),
      package_id,
      tostring(existing),
      tostring(stable_key)
    ))
    return
  end

  index[package_id] = stable_key
end

for card_key, card_def in pairs(whitelist.CARDS) do
  card_def.card_key = card_key

  if card_def.package_id and card_def.package_id ~= "" then
    register_unique(card_key_by_package_id, card_def.package_id, card_key, "card")
    register_unique(current_card_key_by_package_id, card_def.package_id, card_key, "current card")
    card_by_package_id[card_def.package_id] = card_def
  end

  for _, legacy_package_id in ipairs(card_def.legacy_package_ids or {}) do
    register_unique(card_key_by_package_id, legacy_package_id, card_key, "legacy card")
    card_by_package_id[legacy_package_id] = card_def
  end
end

for package_key, package_def in pairs(whitelist.PACKAGE_DEFS) do
  package_def.package_key = package_key

  if package_def.package_id and package_def.package_id ~= "" then
    register_unique(package_key_by_package_id, package_def.package_id, package_key, "package")
    register_unique(current_package_key_by_package_id, package_def.package_id, package_key, "current package")
  end

  for _, legacy_package_id in ipairs(package_def.legacy_package_ids or {}) do
    register_unique(package_key_by_package_id, legacy_package_id, package_key, "legacy package")
  end
end

-- Anything listed here is omitted unless the current package ID is unlocked.
-- Legacy IDs are deliberately locked too, preventing old hashes from becoming
-- public if they temporarily remain in assets/whitelist.txt during rollout.
local LOCKED_BY_DEFAULT = {}

local function lock_package_definition(def)
  if def.package_id and def.package_id ~= "" then
    LOCKED_BY_DEFAULT[def.package_id] = true
  end

  for _, legacy_package_id in ipairs(def.legacy_package_ids or {}) do
    LOCKED_BY_DEFAULT[legacy_package_id] = true
  end
end

for _, package_def in pairs(whitelist.PACKAGE_DEFS) do
  lock_package_definition(package_def)
end

for _, card_def in pairs(whitelist.CARDS) do
  lock_package_definition(card_def)
end

local cached_whitelist = {}
local POSTWIN_REWARD_DELAY_TICKS = 20
local JOIN_RESEND_DELAY_TICKS = 20
local pending_join_reward_packets = {}

local function build_card_reward_entry(card_def, code)
  if not card_def.package_id or card_def.package_id == "" then
    printd("missing package_id for", tostring(card_def and card_def.asset_path or "unknown_card"))
    return nil
  end

  return {
    type = 1,
    card_id = card_def.package_id,
    code = code or card_def.code or "*",
  }
end

local function queue_join_reward_packet(player_id, rewards, ticks)
  if not rewards or #rewards == 0 then
    return
  end

  pending_join_reward_packets[player_id] = {
    ticks = math.max(1, math.floor(tonumber(ticks or JOIN_RESEND_DELAY_TICKS) or JOIN_RESEND_DELAY_TICKS)),
    rewards = rewards,
  }
end

local function whitelist_text_hash(text)
  local h = 0
  for i = 1, #text do
    h = (h * 131 + text:byte(i)) % 2147483647
  end
  return tostring(h)
end

local function read_text_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

local function get_safe_secret(player_id)
  return helpers.get_safe_player_secret(player_id)
end

local function resolve_unlock_target(key_or_package_id)
  local value = tostring(key_or_package_id or "")
  if value == "" then
    return nil, nil
  end

  if whitelist.CARDS[value] then
    return "card", value
  end

  if whitelist.PACKAGE_DEFS[value] then
    return "package", value
  end

  local card_key = card_key_by_package_id[value]
  if card_key then
    return "card", card_key
  end

  local package_key = package_key_by_package_id[value]
  if package_key then
    return "package", package_key
  end

  return "raw_package", value
end

local function unlocks_contain(unlocks, kind, key)
  if kind == "card" then
    return unlocks.cards[key] == true
  end

  if kind == "package" then
    return unlocks.packages[key] == true
  end

  if kind == "raw_package" then
    return unlocks.raw_packages[key] == true
  end

  return false
end

local function set_unlock(unlocks, kind, key)
  if kind == "card" then
    unlocks.cards[key] = true
    return true
  end

  if kind == "package" then
    unlocks.packages[key] = true
    return true
  end

  if kind == "raw_package" then
    unlocks.raw_packages[key] = true
    return true
  end

  return false
end

local function normalize_unlock_memory(player_memory)
  local unlocks = player_memory[PLAYER_UNLOCKS_MEM_KEY]

  if type(unlocks) ~= "table" then
    unlocks = {}
    player_memory[PLAYER_UNLOCKS_MEM_KEY] = unlocks
  end

  if type(unlocks.cards) ~= "table" then
    unlocks.cards = {}
  end

  if type(unlocks.packages) ~= "table" then
    unlocks.packages = {}
  end

  if type(unlocks.raw_packages) ~= "table" then
    unlocks.raw_packages = {}
  end

  return unlocks
end

-- Handles an accidental/intermediate flat v2 table safely, if one ever existed.
local function migrate_flat_v2_unlocks(unlocks)
  local changed = false
  local reserved = {
    cards = true,
    packages = true,
    raw_packages = true,
  }

  local flat_keys = {}
  for key, value in pairs(unlocks) do
    if not reserved[key] and value == true then
      flat_keys[#flat_keys + 1] = key
    end
  end

  for _, old_key in ipairs(flat_keys) do
    local kind, stable_key = resolve_unlock_target(old_key)
    if kind and stable_key then
      if not unlocks_contain(unlocks, kind, stable_key) then
        set_unlock(unlocks, kind, stable_key)
      end
      unlocks[old_key] = nil
      changed = true
    end
  end

  return changed
end

-- Imports old v1 package-ID ownership into stable v2 keys.
-- It is intentionally idempotent and leaves v1 untouched as a rollback copy.
local function import_legacy_unlocks(player_memory, unlocks)
  local legacy = player_memory[LEGACY_PLAYER_UNLOCKS_MEM_KEY]
  if type(legacy) ~= "table" then
    return false
  end

  local changed = false

  for legacy_package_id, is_unlocked in pairs(legacy) do
    if is_unlocked == true then
      local kind, stable_key = resolve_unlock_target(legacy_package_id)

      if kind and stable_key and not unlocks_contain(unlocks, kind, stable_key) then
        set_unlock(unlocks, kind, stable_key)
        changed = true
        printd("migrated v1 unlock", legacy_package_id, "->", kind, stable_key)
      end
    end
  end

  return changed
end

-- If an unknown raw package later becomes registered, move it into its stable key.
local function migrate_registered_raw_unlocks(unlocks)
  local changed = false
  local raw_ids = {}

  for package_id, is_unlocked in pairs(unlocks.raw_packages) do
    if is_unlocked == true then
      raw_ids[#raw_ids + 1] = package_id
    end
  end

  for _, package_id in ipairs(raw_ids) do
    local kind, stable_key = resolve_unlock_target(package_id)

    if kind and kind ~= "raw_package" and stable_key then
      if not unlocks_contain(unlocks, kind, stable_key) then
        set_unlock(unlocks, kind, stable_key)
      end

      unlocks.raw_packages[package_id] = nil
      changed = true
    end
  end

  return changed
end

local function get_player_unlocks(player_id)
  if ezmemory.is_loaded and not ezmemory.is_loaded() then
    return nil, nil
  end

  local safe_secret = get_safe_secret(player_id)
  if not safe_secret or safe_secret == "" then
    return nil, nil
  end

  local player_memory = ezmemory.get_player_memory(safe_secret)
  if type(player_memory) ~= "table" then
    return nil, safe_secret
  end

  local unlocks = normalize_unlock_memory(player_memory)
  local changed = false

  if migrate_flat_v2_unlocks(unlocks) then
    changed = true
  end

  if import_legacy_unlocks(player_memory, unlocks) then
    changed = true
  end

  if migrate_registered_raw_unlocks(unlocks) then
    changed = true
  end

  if changed then
    ezmemory.save_player_memory(safe_secret)
  end

  return unlocks, safe_secret
end

local function normalize_busting_level(score)
  if type(score) == "string" and string.upper(score) == "S" then
    return 11
  end

  return math.floor(tonumber(score) or 0)
end

local function provide_card_asset_for_player(player_id, card_def)
  if not card_def or not card_def.asset_path or card_def.asset_path == "" then
    return false, "missing_asset_path"
  end

  local hint = {
    asset_type = AssetType.DATA,
    package_type = PackageType.CARD,
  }

  local ok, err = pcall(Net.provide_asset_for_player, player_id, card_def.asset_path, hint)

  if ok then
    printd("provided card asset", player_id, card_def.package_id, card_def.asset_path)
    return true
  else
    printd("FAILED to provide card asset", player_id, card_def.package_id, card_def.asset_path, err)
    return false, err
  end
end

function whitelist.provide_unlocked_assets_for_player(player_id)
  local unlocks = select(1, get_player_unlocks(player_id))
  if not unlocks then
    return false
  end

  for card_key, is_unlocked in pairs(unlocks.cards) do
    if is_unlocked then
      local card_def = whitelist.CARDS[card_key]
      if card_def then
        provide_card_asset_for_player(player_id, card_def)
      end
    end
  end

  return true
end

function whitelist.queue_unlocked_card_rewards_for_player(player_id)
  local unlocks = select(1, get_player_unlocks(player_id))
  if not unlocks then
    return false
  end

  local rewards = {}

  for card_key, is_unlocked in pairs(unlocks.cards) do
    if is_unlocked then
      local card_def = whitelist.CARDS[card_key]
      if card_def then
        provide_card_asset_for_player(player_id, card_def)
        rewards[#rewards + 1] = build_card_reward_entry(card_def)
      end
    end
  end

  if #rewards > 0 then
    queue_join_reward_packet(player_id, rewards, JOIN_RESEND_DELAY_TICKS)
    return true
  end

  return false
end

local function resolve_score_chance(rule, score)
  local score_chances = rule.score_chances or rule.busting_levels
  if type(score_chances) == "table" then
    local chance = score_chances[score]
    if chance == nil then
      chance = score_chances[tostring(score)]
    end
    return tonumber(chance) or 0
  end

  return tonumber(rule.chance or 0) or 0
end

function whitelist.try_grant_area_battle_chip(player_id, cards_cfg, encounter_info, stats, rewards)
  if not cards_cfg or cards_cfg.enabled == false then
    return nil
  end

  local enemies = encounter_info and encounter_info.enemies
  if type(enemies) ~= "table" then
    return nil
  end

  local score = normalize_busting_level(stats and stats.score)
  if score <= 0 then
    return nil
  end

  local drops = cards_cfg.drops or {}
  local candidates = {}

  for _, enemy in ipairs(enemies) do
    if type(enemy) == "table" and tonumber(enemy.team or 1) ~= 2 then
      local virus_name = tostring(enemy.name or "")
      local rank = tostring(enemy.rank or "1")

      local virus_drops = drops[virus_name]
      local rules = virus_drops and (virus_drops[rank] or virus_drops[tonumber(rank)])

      if type(rules) == "table" then
        for _, rule in ipairs(rules) do
          local chance = resolve_score_chance(rule, score)
          if chance > 0 and math.random() <= chance then
            candidates[#candidates + 1] = {
              card_key = rule.card or rule.chip,
              code = rule.code,
              duplicate_money = tonumber(rule.duplicate_money or 0) or 0,
              duplicate_score_multiplier = tonumber(
                rule.duplicate_score_multiplier
                or cards_cfg.duplicate_fallback_score_multiplier
                or 0
              ) or 0,
              virus_name = virus_name,
              rank = rank,
            }
          end
        end
      end
    end
  end

  if #candidates == 0 then
    return nil
  end

  -- Only award ONE chip total, even if multiple enemies qualified.
  local chosen = candidates[math.random(#candidates)]
  local card_def = whitelist.CARDS[chosen.card_key]

  if not card_def or not card_def.package_id then
    printd("missing card definition for battle reward key", tostring(chosen.card_key))
    return nil
  end

  if whitelist.player_has_card_unlocked(player_id, chosen.card_key) then
    local duplicate_money = tonumber(chosen.duplicate_money or 0) or 0

    if duplicate_money <= 0 then
      local mult = tonumber(chosen.duplicate_score_multiplier or 0) or 0
      if mult > 0 then
        duplicate_money = math.floor(score * mult)
      end
    end

    if duplicate_money > 0 then
      rewards[#rewards + 1] = {
        type = 0,
        value = duplicate_money,
      }
    end

    return {
      kind = "duplicate",
      package_id = card_def.package_id,
      card_key = chosen.card_key,
      money = duplicate_money,
      virus_name = chosen.virus_name,
      rank = chosen.rank,
      score = score,
    }
  end

  provide_card_asset_for_player(player_id, card_def)
  whitelist.unlock_package(player_id, chosen.card_key)

  table.insert(rewards, 1, build_card_reward_entry(card_def, chosen.code))

  return {
    kind = "new",
    package_id = card_def.package_id,
    card_key = chosen.card_key,
    code = chosen.code or card_def.code or "*",
    virus_name = chosen.virus_name,
    rank = chosen.rank,
    score = score,
    delay_ticks = POSTWIN_REWARD_DELAY_TICKS,
  }
end

-- Only current package IDs can be authorized in generated whitelist files.
-- Legacy IDs remain usable for migration/API lookup, but old whitelist lines
-- are intentionally excluded even for players who owned the chip.
local function is_current_package_id_unlocked(unlocks, package_id)
  local card_key = current_card_key_by_package_id[package_id]
  if card_key then
    return unlocks.cards[card_key] == true
  end

  local package_key = current_package_key_by_package_id[package_id]
  if package_key then
    return unlocks.packages[package_key] == true
  end

  return unlocks.raw_packages[package_id] == true
end

local function build_player_whitelist_text(player_id)
  local unlocks = select(1, get_player_unlocks(player_id))
  if not unlocks then
    return nil
  end

  local base_text = read_text_file(BASE_WHITELIST_DISK_PATH)
  if not base_text then
    printd("could not read base whitelist:", BASE_WHITELIST_DISK_PATH)
    return nil
  end

  local out_lines = {}

  for line in (base_text .. "\n"):gmatch("(.-)\n") do
    local _, package_id = line:match("^%s*(%S+)%s+(%S+)%s*$")

    -- Keep section headers / blank lines / anything non-package-looking.
    if not package_id then
      table.insert(out_lines, line)
    elseif not LOCKED_BY_DEFAULT[package_id]
        or is_current_package_id_unlocked(unlocks, package_id)
    then
      table.insert(out_lines, line)
    end
  end

  return table.concat(out_lines, "\n")
end

local function rebuild_player_whitelist_asset(player_id)
  local unlocks, safe_secret = get_player_unlocks(player_id)
  if not unlocks then
    return nil
  end

  local text = build_player_whitelist_text(player_id)
  if not text then
    return nil
  end

  local hash = whitelist_text_hash(text)
  local asset_path = string.format("%s/%s_%s.txt", GENERATED_WHITELIST_DIR, safe_secret, hash)

  local cached = cached_whitelist[safe_secret]
  if not cached or cached.text ~= text or cached.path ~= asset_path then
    Net.update_asset(asset_path, text)
    cached_whitelist[safe_secret] = {
      text = text,
      path = asset_path,
    }
  end

  Net.provide_asset_for_player(player_id, asset_path)
  return asset_path
end

function whitelist.is_enforced_area(area_id)
  return ENFORCED_AREAS[area_id] == true
end

function whitelist.player_has_package_unlocked(player_id, key_or_package_id)
  local unlocks = select(1, get_player_unlocks(player_id))
  if not unlocks then
    return false
  end

  local kind, stable_key = resolve_unlock_target(key_or_package_id)
  return unlocks_contain(unlocks, kind, stable_key)
end

function whitelist.unlock_package(player_id, key_or_package_id)
  if not key_or_package_id or key_or_package_id == "" then
    return false, "missing_package_id"
  end

  local unlocks, safe_secret = get_player_unlocks(player_id)
  if not unlocks then
    return false, "memory_not_ready"
  end

  local kind, stable_key = resolve_unlock_target(key_or_package_id)
  if not kind or not stable_key then
    return false, "missing_package_id"
  end

  if unlocks_contain(unlocks, kind, stable_key) then
    whitelist.apply_for_player(player_id)
    return false, "already_unlocked"
  end

  set_unlock(unlocks, kind, stable_key)
  ezmemory.save_player_memory(safe_secret)

  -- Re-apply immediately in case the player is already in an enforced area.
  whitelist.apply_for_player(player_id)
  return true
end

function whitelist.unlock_undershirt(player_id)
  return whitelist.unlock_package(player_id, "undershirt")
end

local function apply_blank_whitelist_for_player(player_id)
  Net.provide_asset_for_player(
    player_id,
    BLANK_WHITELIST_ASSET_PATH
  )

  Net.set_mod_whitelist_for_player(
    player_id,
    BLANK_WHITELIST_ASSET_PATH
  )

  printd(
    "cleared whitelist for unrestricted area",
    player_id,
    BLANK_WHITELIST_ASSET_PATH
  )

  return true
end

function whitelist.apply_for_player(player_id)
  local area_id = Net.get_player_area(player_id)
  if not area_id then
    return false
  end

  -- Anything outside the protected area list is "anything goes."
  if not whitelist.is_enforced_area(area_id) then
    return apply_blank_whitelist_for_player(player_id)
  end

  local asset_path = rebuild_player_whitelist_asset(player_id)
  if not asset_path then
    return false
  end

  Net.provide_asset_for_player(player_id, asset_path)
  Net.set_mod_whitelist_for_player(player_id, asset_path)

  printd(
    "applied restricted whitelist",
    player_id,
    area_id,
    asset_path
  )

  return true
end

function whitelist.get_card_def(card_key_or_package_id)
  if not card_key_or_package_id then
    return nil
  end

  local key = tostring(card_key_or_package_id)
  return whitelist.CARDS[key] or card_by_package_id[key]
end

function whitelist.player_has_card_unlocked(player_id, card_key_or_package_id)
  local card_def = whitelist.get_card_def(card_key_or_package_id)
  if not card_def or not card_def.card_key then
    return false, card_def
  end

  local unlocks = select(1, get_player_unlocks(player_id))
  if not unlocks then
    return false, card_def
  end

  return unlocks.cards[card_def.card_key] == true, card_def
end

function whitelist.unlock_card(player_id, card_key_or_package_id, code, delay_ticks)
  local card_def = whitelist.get_card_def(card_key_or_package_id)
  if not card_def or not card_def.card_key then
    return false, "missing_card_def", nil
  end

  if whitelist.player_has_card_unlocked(player_id, card_def.card_key) then
    return false, "already_unlocked", card_def
  end

  local ok_asset, asset_err = provide_card_asset_for_player(player_id, card_def)
  if not ok_asset then
    return false, asset_err or "provide_failed", card_def
  end

  local ok_unlock, reason = whitelist.unlock_package(player_id, card_def.card_key)
  if not ok_unlock and reason ~= "already_unlocked" then
    return false, reason, card_def
  end

  local reward = build_card_reward_entry(card_def, code)
  if reward then
    queue_join_reward_packet(player_id, { reward }, delay_ticks or POSTWIN_REWARD_DELAY_TICKS)
  end

  return true, "unlocked", card_def
end

Net:on("tick", function()
  for player_id, packet in pairs(pending_join_reward_packets) do
    packet.ticks = packet.ticks - 1
    if packet.ticks <= 0 then
      pcall(Net.send_player_battle_rewards, player_id, packet.rewards)
      pending_join_reward_packets[player_id] = nil
    end
  end
end)

Net:on("player_disconnect", function(event)
  pending_join_reward_packets[event.player_id] = nil
end)

Net:on("player_connect", function(event)
  whitelist.provide_unlocked_assets_for_player(event.player_id)
end)

Net:on("player_join", function(event)
  whitelist.queue_unlocked_card_rewards_for_player(event.player_id)
  whitelist.apply_for_player(event.player_id)
end)

Net:on("player_area_transfer", function(event)
  whitelist.apply_for_player(event.player_id)
end)

return whitelist
