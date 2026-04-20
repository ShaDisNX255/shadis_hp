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
  Dungeon1 = true,
}

local BASE_WHITELIST_DISK_PATH = "./assets/whitelist.txt"
local GENERATED_WHITELIST_DIR = "/server/assets/generated_whitelists"
local PLAYER_UNLOCKS_MEM_KEY = "__player_mod_unlocks_v1"

whitelist.PACKAGES = {
  undershirt = "com.OFC.block.EXE6-013-UnderShirt",
}

whitelist.CARDS = {
  reflecmet1 = {
    package_id = "com.OFC.card.EXE6-091-ReflecMet1",
    asset_path = "/server/assets/chips/EXE6-Reflect.zip",
    code = "*",
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
    package_id = "rune.legacy.bubbler",
    asset_path = "/server/assets/chips/EXE3-Bubbler.zip",
    code = "*",
  },
  yoyo1 = {
    package_id = "com.OFC.card.EXE6-018-YoYo",
    asset_path = "/server/assets/chips/EXE6-YoYo.zip",
    code = "*",
  },
  HellsBurner1 = {
    package_id = "com.OFC.card.EXE6-019-HellsBurner1",
    asset_path = "/server/assets/chips/EXE6-HellsBurner1.zip",
    code = "*",
  },
  MachineGun1 = {
    package_id = "com.OFC.card.EXE6-055-MachineGun1",
    asset_path = "/server/assets/chips/EXE6-MachineGun1.zip",
    code = "*",
  },
  MachineGun2 = {
    package_id = "com.OFC.card.EXE6-056-MachineGun2",
    asset_path = "/server/assets/chips/EXE6-MachineGun2.zip",
    code = "*",
  },
  KillerSensor1 = {
    package_id = "com.OFC.card.EXE6-116-KillerSensor1",
    asset_path = "/server/assets/chips/EXE6-KillerSensor1.zip",
    code = "*",
  },
  KillerSensor2 = {
    package_id = "com.OFC.card.EXE6-117-KillerSensor2",
    asset_path = "/server/assets/chips/EXE6-KillerSensor2.zip",
    code = "*",
  },
  RabiRing1 = {
    package_id = "com.OFC.card.EXEPoN-017-RabiRing1",
    asset_path = "/server/assets/chips/EXEPoN-RabiRing1.zip",
    code = "*",
  },
  RabiRing2 = {
    package_id = "com.OFC.card.EXEPoN-018-RabiRing2",
    asset_path = "/server/assets/chips/EXEPoN-RabiRing2.zip",
    code = "*",
  },
  Ratton2 = {
    package_id = "com.OFC.card.EXEPoN-032-Ratton2",
    asset_path = "/server/assets/chips/EXEPoN-Ratton2.zip",
    code = "*",
  },
  sonicwave = {
    package_id = "com.OFC.card.EXEPoN-052-SonicWave",
    asset_path = "/server/assets/chips/EXEPoN-SonicWave.zip",
    code = "*",
  },
  spreadgun1 = {
    package_id = "com.OFC.card.EXE6-009-SpreadGun1",
    asset_path = "/server/assets/chips/EXE6-SpreadGun1.zip",
    code = "*",
  },
  spreadgun2 = {
    package_id = "com.OFC.card.EXE6-010-SpreadGun2",
    asset_path = "/server/assets/chips/EXE6-SpreadGun2.zip",
    code = "*",
  },
  thunderball = {
    package_id = "com.OFC.card.EXE6-029-ThunderBall",
    asset_path = "/server/assets/chips/EXE6-ThunderBall.zip",
    code = "*",
  },
  roll1 = {
    package_id = "com.k1rbyat1na.card.EXE6-222-Roll",
    asset_path = "/server/assets/chips/EXE6-Roll1.zip",
    code = "*",
  },
  gutsman1 = {
    package_id = "com.louise.card.gutsmanv1",
    asset_path = "/server/assets/chips/EXE3-Gutsman1.zip",
    code = "*",
  },
  rec30 = {
    package_id = "com.OFC.card.EXE6-157-Recovery30",
    asset_path = "/server/assets/chips/EXE6-Rec30.zip",
    code = "*",
  },
  rec50 = {
    package_id = "com.OFC.card.EXE6-158-Recovery50",
    asset_path = "/server/assets/chips/EXE6-Rec50.zip",
    code = "*",
  },
  vulcan2 = {
    package_id = "com.keristero.card.Vulcan2",
    asset_path = "/server/assets/chips/EXE6-Vulcan2.zip",
    code = "*",
  },
  vulcan3 = {
    package_id = "com.keristero.card.Vulcan3",
    asset_path = "/server/assets/chips/EXE6-Vulcan3.zip",
    code = "*",
  },
  heatshot = {
    package_id = "com.OFC.card.EXEPoN-014-HeatShot",
    asset_path = "/server/assets/chips/EXEPoN-HeatShot.zip",
    code = "*",
  },
  grassstage = {
    package_id = "com.Thor.card.GrassStg",
    asset_path = "/server/assets/chips/EXE3-GrassStage.zip",
    code = "*",
  },
}

local card_by_package_id = {}
for _, card_def in pairs(whitelist.CARDS) do
  if card_def.package_id then
    card_by_package_id[card_def.package_id] = card_def
  end
end

-- Anything listed here is locked until the player unlocks it.
-- Future chips/programs just get added here by package_id.
local LOCKED_BY_DEFAULT = {
  [whitelist.PACKAGES.undershirt] = true,
}

for _, card_def in pairs(whitelist.CARDS) do
  if card_def.package_id then
    LOCKED_BY_DEFAULT[card_def.package_id] = true
  end
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

local DEBUG_WHITELIST = false

local function printd(...)
  if not DEBUG_WHITELIST then return end
  print("[whitelist]", ...)
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

local function get_player_unlocks(player_id)
  if ezmemory.is_loaded and not ezmemory.is_loaded() then
    return nil, nil
  end

  local safe_secret = get_safe_secret(player_id)
  local player_memory = ezmemory.get_player_memory(safe_secret)

  player_memory[PLAYER_UNLOCKS_MEM_KEY] = player_memory[PLAYER_UNLOCKS_MEM_KEY] or {}
  return player_memory[PLAYER_UNLOCKS_MEM_KEY], safe_secret
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

  for package_id, is_unlocked in pairs(unlocks) do
    if is_unlocked then
      local card_def = card_by_package_id[package_id]
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

  for package_id, is_unlocked in pairs(unlocks) do
    if is_unlocked then
      local card_def = card_by_package_id[package_id]
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

  if whitelist.player_has_package_unlocked(player_id, card_def.package_id) then
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
  whitelist.unlock_package(player_id, card_def.package_id)

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

    -- Keep section headers / blank lines / anything non-package-looking
    if not package_id then
      table.insert(out_lines, line)
    elseif not LOCKED_BY_DEFAULT[package_id] or unlocks[package_id] then
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

function whitelist.player_has_package_unlocked(player_id, package_id)
  local unlocks = select(1, get_player_unlocks(player_id))
  return unlocks ~= nil and unlocks[package_id] == true
end

function whitelist.unlock_package(player_id, package_id)
  if not package_id or package_id == "" then
    return false, "missing_package_id"
  end

  local unlocks, safe_secret = get_player_unlocks(player_id)
  if not unlocks then
    return false, "memory_not_ready"
  end

  if unlocks[package_id] then
    whitelist.apply_for_player(player_id)
    return false, "already_unlocked"
  end

  unlocks[package_id] = true
  ezmemory.save_player_memory(safe_secret)

  -- Re-apply immediately in case the player is already in an enforced area
  whitelist.apply_for_player(player_id)
  return true
end

function whitelist.unlock_undershirt(player_id)
  return whitelist.unlock_package(player_id, whitelist.PACKAGES.undershirt)
end

function whitelist.apply_for_player(player_id)
  local area_id = Net.get_player_area(player_id)
  if not area_id or not whitelist.is_enforced_area(area_id) then
    return false
  end

  local asset_path = rebuild_player_whitelist_asset(player_id)
  if not asset_path then
    return false
  end

  Net.provide_asset_for_player(player_id, asset_path)
  Net.set_mod_whitelist_for_player(player_id, asset_path)
  printd("applied whitelist", player_id, asset_path)
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
  if not card_def then
    return false, nil
  end

  return whitelist.player_has_package_unlocked(player_id, card_def.package_id), card_def
end

function whitelist.unlock_card(player_id, card_key_or_package_id, code, delay_ticks)
  local card_def = whitelist.get_card_def(card_key_or_package_id)
  if not card_def then
    return false, "missing_card_def", nil
  end

  if whitelist.player_has_package_unlocked(player_id, card_def.package_id) then
    return false, "already_unlocked", card_def
  end

  local ok_asset, asset_err = provide_card_asset_for_player(player_id, card_def)
  if not ok_asset then
    return false, asset_err or "provide_failed", card_def
  end

  local ok_unlock, reason = whitelist.unlock_package(player_id, card_def.package_id)
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