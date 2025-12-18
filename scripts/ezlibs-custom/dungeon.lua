-- scripts/ezlibs-custom/dungeon.lua
-- Shared dungeon behavior: detection, heal NPC event, run penalties,
-- and (NEW) raid-style dungeon mini-boss pools + boss-gates for ezcheckpoints.

local dungeon = {}

local ezmemory = require("scripts/ezlibs-scripts/ezmemory")
local eznpcs   = require("scripts/ezlibs-scripts/eznpcs/eznpcs")

----------------------------------------------------------------
-- Dungeon detection
-- Uses a bool map custom property: Dungeon = true
----------------------------------------------------------------
local function is_dungeon_area(area_id)
  if not area_id then return false end
  -- Net.get_area_custom_property returns strings: "true"/"false"/nil
  return Net.get_area_custom_property(area_id, "Dungeon") == "true"
end

dungeon.is_dungeon_area = is_dungeon_area

----------------------------------------------------------------
local DAMAGE_MSG = "Damage critical, logging out before deletion"

-- pid -> { stage="show"|"kick", from_area=string, exit={...} }
local _PENDING_KICK = {}

----------------------------------------------------------------
-- Dungeon "Life" system (optional gameplay mechanic)
--
-- On entering a dungeon area (Dungeon=true), player gets extra "lives"
-- equal to the number of OTHER players currently in the same area.
-- Each life prevents ONE dungeon kick-out (HP<=0), heals you back up to
-- the map's "Forced Base HP" (or max HP fallback), and shows a message.
--
-- Optional map custom properties:
--   DungeonLivesCap (int)         -> cap extra lives (0/blank = uncapped)
--   DungeonLivesShowOnEnter (bool)-> "true" to show a message on entry
----------------------------------------------------------------
local _DUNGEON_LIVES = {}        -- [pid] = { lives=int, dungeon_root=string }
local _WAS_IN_DUNGEON = {}       -- [pid] = bool

local function _get_forced_base_hp(area_id)
  local v = Net.get_area_custom_property(area_id, "Forced Base HP")
  if v == nil then
    v = Net.get_area_custom_property(area_id, "ForcedBaseHP")
  end
  local n = tonumber(v or "")
  if n and n > 0 then
    return math.floor(n)
  end
  return nil
end

local function _grant_lives_on_enter(player_id, area_id)
  if not player_id or not area_id then return end
  if not is_dungeon_area(area_id) then return end

  local ids = Net.list_players(area_id) or {}
  local others = 0
  for _, pid in ipairs(ids) do
    if pid ~= player_id then
      others = others + 1
    end
  end

  local cap = tonumber(Net.get_area_custom_property(area_id, "DungeonLivesCap") or 0) or 0
  if cap > 0 then
    others = math.min(others, cap)
  end

  _DUNGEON_LIVES[player_id] = {
    lives = others,
    max_lives = others,
    dungeon_root = area_id,
  }

  if others > 0 and Net.get_area_custom_property(area_id, "DungeonLivesShowOnEnter") == "true" then
    Net.message_player(player_id, ("You feel the power of allies nearby. Extra lives: %d"):format(others))
  end
end

local function _clear_lives(player_id)
  _DUNGEON_LIVES[player_id] = nil
  _WAS_IN_DUNGEON[player_id] = nil
end

-- Returns true if it consumed a life and healed the player (preventing kick)
local function _try_consume_life(player_id, area_id)
  local st = _DUNGEON_LIVES[player_id]
  if not st then return false end

  local lives = tonumber(st.lives or 0) or 0
  if lives <= 0 then return false end

  -- consume
  st.lives = lives - 1

  local heal_to = _get_forced_base_hp(area_id) or tonumber(Net.get_player_max_health(player_id) or 1) or 1
  heal_to = math.max(1, math.floor(heal_to))
  -- If Forced Base HP is higher than the player's current max HP,
  -- raise max HP so the revive can actually reach the forced base.
  local max_hp = tonumber(Net.get_player_max_health(player_id) or heal_to) or heal_to
  if heal_to > max_hp then
    if Net.set_player_max_health then
      Net.set_player_max_health(player_id, heal_to)
      max_hp = heal_to
    else
      -- fallback: clamp if this server build doesn't expose set_player_max_health
      heal_to = max_hp
    end
  end

  -- Persist via ezmemory when available (consistent with DungeonHeal)
  if ezmemory and ezmemory.set_player_health then
    ezmemory.set_player_health(player_id, heal_to)
  else
    Net.set_player_health(player_id, heal_to)
  end

  Net.message_player(
    player_id,
    ("The power of other players in the area have healed you. Lives left: %d"):format(st.lives)
  )
  return true
end

-- Track dungeon entry/exit to grant lives once per dungeon "run"
local function _refresh_player_dungeon_state(player_id)
  if not player_id then return end
  local area_id = Net.get_player_area(player_id)
  if not area_id then return end

  local now = is_dungeon_area(area_id)
  local was = _WAS_IN_DUNGEON[player_id] or false

  if now and not was then
    _WAS_IN_DUNGEON[player_id] = true
    _grant_lives_on_enter(player_id, area_id)
  elseif (not now) and was then
    _clear_lives(player_id)
  else
    _WAS_IN_DUNGEON[player_id] = now
  end
end

Net:on("player_join", function(event)
  local pid = event and event.player_id
  if not pid then return end
  _WAS_IN_DUNGEON[pid] = false
  _refresh_player_dungeon_state(pid)
end)

Net:on("player_area_transfer", function(event)
  local pid = event and event.player_id
  if not pid then return end
  _refresh_player_dungeon_state(pid)
end)

Net:on("player_disconnect", function(event)
  local pid = event and event.player_id
  if not pid then return end
  _PENDING_KICK[pid] = nil
  _clear_lives(pid)
end)

local function _parse_textbox_response_args(a, b)
  if type(a) == "table" then
    local pid = a.player_id or a[1]
    local resp = (a.response ~= nil) and a.response or a[2]
    return pid, resp
  end
  return a, b
end

local function _resolve_exit_from_area(dungeon_area_id)
  local target_area      = Net.get_area_custom_property(dungeon_area_id, "DungeonKickArea")
  local target_object_id = Net.get_area_custom_property(dungeon_area_id, "DungeonKickObject")

  if not (target_area and target_object_id) or target_area == "" or target_object_id == "" then
    return nil
  end

  local target_id = tonumber(target_object_id) or target_object_id
  local target_obj = Net.get_object_by_id(target_area, target_id)
  if not target_obj then
    print(string.format(
      "[dungeon] DungeonKickObject id=%s not found in area %s",
      tostring(target_object_id), tostring(target_area)
    ))
    return nil
  end

  local x = (target_obj.x or 0)
  local y = (target_obj.y or 0)
  local z = (target_obj.z or 0)

  local dir = "Down Right"
  if target_obj.custom_properties and target_obj.custom_properties["Direction"] then
    dir = target_obj.custom_properties["Direction"]
  end

  return {
    area_id = target_area,
    x = x + 0.5,
    y = y + 0.5,
    z = z,
    dir = dir,
  }
end

-- defer_damage_msg=true means:
--   wait for ONE textbox close (boss-progress OR run-penalty),
--   then show DAMAGE_MSG, then kick after DAMAGE_MSG closes.
local function kick_player_out_of_dungeon(player_id, defer_damage_msg)
  if not player_id then return end

  local area_id = Net.get_player_area(player_id)
  if not is_dungeon_area(area_id) then
    return
  end

  -- Life system: prevent the dungeon kick if the player has an extra life
  if _try_consume_life(player_id, area_id) then
    _PENDING_KICK[player_id] = nil
    return true
  end

  local exit = _resolve_exit_from_area(area_id)
  if not exit then
    return
  end

  -- Don't double-queue.
  if _PENDING_KICK[player_id] then
    return
  end

  _PENDING_KICK[player_id] = {
    stage = defer_damage_msg and "show" or "kick",
    from_area = area_id,
    exit = exit,
  }

  if not defer_damage_msg then
    Net.message_player(player_id, DAMAGE_MSG)
  end

  return false
end

-- expose for other scripts (if you call it externally)
dungeon.kick_player_out_of_dungeon = kick_player_out_of_dungeon

Net:on("textbox_response", function(a, b)
  local pid = _parse_textbox_response_args(a, b)
  if not pid then return end

  local state = _PENDING_KICK[pid]
  if not state then
    return
  end

  -- If they left the dungeon already, disarm.
  local cur_area = Net.get_player_area(pid)
  if not is_dungeon_area(cur_area) or (state.from_area and cur_area ~= state.from_area) then
    _PENDING_KICK[pid] = nil
    return
  end

  if state.stage == "show" then
    -- We just closed the “pre” textbox (boss HP line OR run penalty line)
    state.stage = "kick"
    Net.message_player(pid, DAMAGE_MSG)
    return
  end

  if state.stage == "kick" then
    local exit = state.exit
    _PENDING_KICK[pid] = nil

    if not exit then return end

    Net.transfer_player(
      pid,
      exit.area_id,
      true, -- custom warp animation
      exit.x,
      exit.y,
      exit.z,
      exit.dir
    )
  end
end)

-- Helper: for normal encounters (no extra “pre” textbox)
function dungeon.kick_player_if_dead(player_id, stats_or_flags)
  if not player_id then return end
  local area_id = Net.get_player_area(player_id)
  if not is_dungeon_area(area_id) then return end

  local hp = 0
  if type(stats_or_flags) == "table" then
    hp = tonumber(stats_or_flags.hp or stats_or_flags.health or stats_or_flags.player_hp or 0) or 0
  else
    hp = tonumber(Net.get_player_health(player_id) or 0) or 0
  end

  if hp <= 0 then
    kick_player_out_of_dungeon(player_id, false) -- show DAMAGE_MSG immediately
  end
end


----------------------------------------------------------------
-- Dialogue event: DungeonHeal
-- Heals the player up to a cap (default 500) using ezmemory.set_player_health.
-- Only works in areas with Dungeon = true.
--
-- Usage in Tiled dialogue:
--   Event Name: DungeonHeal
--   (optional) Heal Amount / Heal / HP (number) -> heal cap for this NPC
----------------------------------------------------------------
eznpcs.add_event{
  name = "DungeonHeal",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local area_id = Net.get_player_area(player_id)

      local next_1 = nil
      if dialogue and dialogue.custom_properties then
        next_1 = dialogue.custom_properties["Next 1"]
      end

      if not is_dungeon_area(area_id) then
        return next_1
      end

      local mug   = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
      local props = (dialogue and dialogue.custom_properties) or {}

      local function _msg(text)
        if Async and Async.message_player then
          await(Async.message_player(
            player_id,
            text,
            mug and mug.texture_path,
            mug and mug.animation_path
          ))
        else
          Net.message_player(player_id, text)
        end
      end

      -- --------------------------
      -- HP HEAL (same behavior)
      -- --------------------------
      local heal_cap = tonumber(
        props["Heal Amount"]
        or props["Heal"]
        or props["HP"]
      ) or 500

      local cur_hp = tonumber(Net.get_player_health(player_id) or 0) or 0
      local max_hp = tonumber(Net.get_player_max_health(player_id) or 0) or 0
      local target_hp = math.min(heal_cap, max_hp)

      local hp_changed = false
      local new_hp = cur_hp

      if cur_hp < target_hp then
        ezmemory.set_player_health(player_id, target_hp)
        new_hp = tonumber(Net.get_player_health(player_id) or target_hp) or target_hp
        hp_changed = true
      end

      -- --------------------------
      -- LIVES REFILL (even if HP is max)
      -- Refill to "current party size" lives:
      --   lives = #other players in this dungeon area (capped by DungeonLivesCap)
      -- --------------------------
      local lives_changed = false
      local new_lives = nil

      do
        local ids = Net.list_players(area_id) or {}
        local others = 0
        for _, pid in ipairs(ids) do
          if pid ~= player_id then
            others = others + 1
          end
        end

        local cap = tonumber(Net.get_area_custom_property(area_id, "DungeonLivesCap") or 0) or 0
        if cap > 0 then
          others = math.min(others, cap)
        end

        local st = _DUNGEON_LIVES[player_id]
        if st and type(st) == "table" then
          local cur_lives = tonumber(st.lives or 0) or 0
          new_lives = math.max(cur_lives, others) -- never reduce lives via healer
          if new_lives ~= cur_lives then
            st.lives = new_lives
            lives_changed = true
          end
        else
          -- If life state is missing but they're in a dungeon, recreate it
          -- (only if they'd actually have >0 lives right now)
          if others > 0 then
            _DUNGEON_LIVES[player_id] = { lives = others, dungeon_root = area_id }
            new_lives = others
            lives_changed = true
          end
        end
      end

      -- Play SFX if anything was actually restored
      if hp_changed or lives_changed then
        Net.play_sound_for_player(
          player_id,
          "/server/assets/ezlibs-assets/sfx/recover.ogg"
        )
      end

      -- One textbox message (covers all cases)
      local lines = {}

      if hp_changed then
        table.insert(lines, string.format("See? Didn't even explode this time. Proud of us~<3! Recovered your HP to %d!", new_hp))
      else
        table.insert(lines, string.format("Oi, you're already perfect! What am I, a glorified cheerleader? You're already at %d HP.", cur_hp))
      end

      if lives_changed and new_lives ~= nil then
        table.insert(lines, string.format("Your extra lives were restored. Lives left: %d", new_lives))
      end

      _msg(table.concat(lines, "\n"))
      return next_1
    end)
  end
}

----------------------------------------------------------------
-- Result decoding (JobBBS semantics)
--  reason 1 = win
--  reason 2 = loss
--  reason 3 = run via L-button (legit)
--  reason 4 = dev/ESC run (what we punish)
-- Fallbacks to stats.ran for older builds.
----------------------------------------------------------------
local function _result_flags(stats)
  local reason = tonumber(stats and stats.reason or 0) or 0
  local hp     = tonumber(stats and (stats.health or stats.player_hp or stats.hp) or 0) or 0

  local ran, dev_escape, won, lost = false, false, false, false

  if reason == 1 then
    won = true
  elseif reason == 2 then
    lost = true
  elseif reason == 3 then
    ran = true
  elseif reason == 4 then
    ran = true
    dev_escape = true
  else
    ran = stats and (stats.ran or stats.fled or stats.escape) or false
    if not ran then
      if hp > 0 then won = true else lost = true end
    end
  end

  return {
    reason     = reason,
    hp         = hp,
    ran        = ran,
    dev_escape = dev_escape,
    won        = won,
    lost       = lost,
  }
end

dungeon.result_flags = _result_flags

----------------------------------------------------------------
-- Run-away penalty for dungeon
-- Called from encounter results callbacks (Dungeon1.lua etc.).
--
-- Rules:
--  • Only applies if the player is in an area with Dungeon = true.
--  • Only applies for dev/ESC runs (reason == 4).
--  • PunishHP map custom property controls how much HP to subtract.
----------------------------------------------------------------
function dungeon.apply_run_penalty(player_id, encounter_info, stats)
  if not player_id or not stats then return end

  local area_id = Net.get_player_area(player_id)
  if not is_dungeon_area(area_id) then
    return
  end

  local flags = _result_flags(stats)

  -- Only punish dev/ESC runs, NOT legit L-button runs.
  if not (flags.ran and flags.dev_escape and flags.reason == 4) then
    return
  end

  local punish_str = Net.get_area_custom_property(area_id, "PunishHP")
  local punish_hp  = tonumber(punish_str or 0) or 0
  if punish_hp <= 0 then
    return
  end

  local base_hp = flags.hp or 0
  local new_hp  = base_hp - punish_hp
  if new_hp < 0 then new_hp = 0 end

  ezmemory.set_player_health(player_id, new_hp)

  Net.message_player(
    player_id,
    string.format("Run penalty! Lost %d HP. (Now %d HP)", punish_hp, new_hp)
  )
  if new_hp <= 0 and dungeon.kick_player_out_of_dungeon then
    dungeon.kick_player_out_of_dungeon(player_id, true) -- defer until run-penalty textbox closes
  end
end

----------------------------------------------------------------
-- ===============================
-- ===== Dungeon Boss Pools ======
-- ===============================
--
-- Global mini-boss HP pools stored in AREA memory:
--   mem.__dungeon_bosses[boss_id] = { pool_max, pool_hp, defeated, defeated_at }
--
-- ezcheckpoints "Boss Gate" calls:
--   dungeon.are_bosses_defeated(mem_area, boss_ids)
--
-- Optional Tiled boss trigger object:
--   type="DungeonBoss"
--   props:
--     Encounter Name (string)  -> named encounter in Dungeon1.lua
--     Boss ID (string)         -> Boss1 / Boss2 / Boss3
--     Boss Pool Max HP (int)   -> global pool max
--     Boss Win Damage (int)    -> fallback damage if stats has no damage fields
--     Boss Memory Area (string)-> optional store area (defaults current area)
--     Already Defeated Message (string)
--     Start Prompt (string)    -> if set, asks Yes/No
--     Progress Message (string)-> optional template {id} {hp} {max} {dmg}
----------------------------------------------------------------

local BOSS_MEM_KEY = "__dungeon_bosses"

local function _trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function _split_csv(s)
  if not s then return {} end
  s = tostring(s)
  local out = {}
  for part in s:gmatch("[^,]+") do
    local v = _trim(part)
    if v ~= "" then out[#out+1] = v end
  end
  return out
end

local function _get_boss_bucket(mem_area)
  local mem = ezmemory.get_area_memory(mem_area)
  mem[BOSS_MEM_KEY] = mem[BOSS_MEM_KEY] or {}
  return mem, mem[BOSS_MEM_KEY]
end

local function _ensure_boss(mem_area, boss_id, pool_max)
  boss_id = _trim(boss_id)
  if boss_id == "" then return nil end

  local _, bucket = _get_boss_bucket(mem_area)
  local s = bucket[boss_id]
  if not s then
    local m = tonumber(pool_max or 0) or 0
    if m <= 0 then m = 1 end
    s = { pool_max = m, pool_hp = m, defeated = false }
    bucket[boss_id] = s
    ezmemory.save_area_memory(mem_area)
  else
    local m = tonumber(pool_max or 0) or 0
    if m > 0 and ((tonumber(s.pool_max or 0) or 0) <= 0) then
      s.pool_max = m
      if (tonumber(s.pool_hp or 0) or 0) <= 0 and not s.defeated then
        s.pool_hp = m
      end
      ezmemory.save_area_memory(mem_area)
    end
  end
  return s
end

function dungeon.get_boss_state(mem_area, boss_id, pool_max)
  if not mem_area or not boss_id then return nil end
  return _ensure_boss(mem_area, boss_id, pool_max)
end

local function _boss_damage_from_stats(stats, fallback_on_win)
  if not stats then return 0 end

  local dmg = tonumber(stats.damage_to_enemy or stats.total_damage or stats.damage_dealt)
  if dmg and dmg > 0 then return math.floor(dmg) end

  local tot = tonumber(stats.enemy_total_hp or stats.enemy_total or stats.total_enemy_hp)
  local rem = tonumber(stats.enemy_remaining_hp or stats.enemy_remaining or stats.enemy_hp)
  if tot and rem and (tot >= rem) then
    return math.floor(tot - rem)
  end

  local f = _result_flags(stats)
  if (not f.ran) and f.hp > 0 and fallback_on_win and tonumber(fallback_on_win) and tonumber(fallback_on_win) > 0 then
    return math.floor(tonumber(fallback_on_win))
  end

  return 0
end

local function _trim(s)
  if s == nil then return "" end
  s = tostring(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Returns boss damage (number) if boss found in stats.enemies, otherwise nil
local function _boss_damage_from_enemies_list(stats, boss_encounter_hp, boss_id_match)
  if not stats or type(stats.enemies) ~= "table" then return nil end

  boss_encounter_hp = tonumber(boss_encounter_hp) or 0
  if boss_encounter_hp <= 0 then return nil end

  local match = string.lower(tostring(boss_id_match or ""))
  if match == "" then return nil end

  for _, e in ipairs(stats.enemies) do
    local enemy_id = e.id or e.name or ""
    enemy_id = string.lower(tostring(enemy_id))
    if enemy_id ~= "" and string.find(enemy_id, match, 1, true) then
      local rem = tonumber(e.remaining_hp or e.hp or 0) or 0
      if rem < 0 then rem = 0 end
      if rem > boss_encounter_hp then rem = boss_encounter_hp end
      return boss_encounter_hp - rem
    end
  end

  return nil
end

-- Unified “raid-style” boss damage calc:
-- - Prefer enemies list (works on LOSS)
-- - If boss not found and player still had HP, assume boss died (same idea raids uses) :contentReference[oaicite:4]{index=4}
-- - Otherwise fall back to _boss_damage_from_stats
local function _boss_damage_for_pool(stats, flags, win_dmg, boss_encounter_hp, boss_id_match)
  local dmg = _boss_damage_from_enemies_list(stats, boss_encounter_hp, boss_id_match)
  if dmg ~= nil then return dmg end

  local php = tonumber(flags and flags.hp) or 0
  if php > 0 and (tonumber(boss_encounter_hp) or 0) > 0 and not (flags and flags.dev_escape) then
    return tonumber(boss_encounter_hp) or 0
  end

  return _boss_damage_from_stats(stats, win_dmg)
end

function dungeon.apply_boss_pool_damage(mem_area, boss_id, damage, pool_max)
  if not mem_area or not boss_id then return nil, false, 0 end

  local s = _ensure_boss(mem_area, boss_id, pool_max)
  if not s then return nil, false, 0 end
  if s.defeated then
    return s, false, 0
  end

  local d = math.floor(tonumber(damage or 0) or 0)
  if d <= 0 then
    return s, false, 0
  end

  local hp = tonumber(s.pool_hp or s.pool_max or 0) or 0
  local maxhp = tonumber(s.pool_max or 0) or 0
  if maxhp <= 0 then maxhp = hp end

  hp = math.max(0, hp - d)
  s.pool_hp = hp
  s.pool_max = maxhp

  local defeated_now = false
  if hp <= 0 then
    s.defeated = true
    s.defeated_at = os.time()
    defeated_now = true
  end

  ezmemory.save_area_memory(mem_area)
  return s, defeated_now, d
end

function dungeon.are_bosses_defeated(mem_area, boss_ids)
  mem_area = tostring(mem_area or "")
  if mem_area == "" then return false, {} end

  local _, bucket = _get_boss_bucket(mem_area)
  local remaining = {}
  local all = true

  for _, id in ipairs(boss_ids or {}) do
    local boss_id = _trim(id)
    if boss_id ~= "" then
      local s = bucket[boss_id]
      if not s or not s.defeated then
        all = false
        if s and s.pool_hp and s.pool_max then
          remaining[#remaining+1] = ("%s (%d/%d)"):format(boss_id, tonumber(s.pool_hp or 0) or 0, tonumber(s.pool_max or 0) or 0)
        else
          remaining[#remaining+1] = boss_id
        end
      end
    end
  end

  return all, remaining
end

-- Debug helpers
function dungeon.reset_boss(mem_area, boss_id)
  mem_area = tostring(mem_area or "")
  boss_id  = _trim(boss_id)
  if mem_area == "" or boss_id == "" then return end
  local _, bucket = _get_boss_bucket(mem_area)
  bucket[boss_id] = nil
  ezmemory.save_area_memory(mem_area)
end

function dungeon.reset_all_bosses(mem_area)
  mem_area = tostring(mem_area or "")
  if mem_area == "" then return end
  local mem = ezmemory.get_area_memory(mem_area)
  mem[BOSS_MEM_KEY] = {}
  ezmemory.save_area_memory(mem_area)
end

----------------------------------------------------------------
-- Optional: Tiled "DungeonBoss" trigger object support
----------------------------------------------------------------

local _BOSS_FIGHT_CTX = {} -- [pid] = { boss_id, mem_area, pool_max, win_damage, progress_msg }

local function _get_ezencounters()
  local ok, m = pcall(require, "scripts/ezlibs-scripts/ezencounters/main")
  if ok and type(m) == "table" then return m end
  ok, m = pcall(require, "scripts/ezlibs-scripts/ezencounters/ezencounters")
  if ok and type(m) == "table" then return m end
  ok, m = pcall(require, "scripts/ezlibs-scripts/ezencounters")
  if ok and type(m) == "table" then return m end
  return _G.ezencounters
end

local function _fmt_progress(tpl, boss_id, s, dmg)
  tpl = tostring(tpl or "")
  if tpl == "" then
    return nil
  end
  local hp  = tonumber(s and s.pool_hp or 0) or 0
  local max = tonumber(s and s.pool_max or 0) or 0
  tpl = tpl:gsub("{id}", tostring(boss_id))
  tpl = tpl:gsub("{hp}", tostring(hp))
  tpl = tpl:gsub("{max}", tostring(max))
  tpl = tpl:gsub("{dmg}", tostring(tonumber(dmg or 0) or 0))
  return tpl
end

-- =========================================================
-- DungeonBoss (Dialogue Event) - stashes ctx, battle_results applies pool damage
-- =========================================================
dungeon._boss_fight_ctx      = dungeon._boss_fight_ctx      or {}
dungeon._boss_fight_outcome  = dungeon._boss_fight_outcome  or {}

local DUNGEON_BOSS_DIALOGUE_EVENT = {
  name = "DungeonBoss",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local props = (dialogue and dialogue.custom_properties) or {}

      local function _msg(text)
        text = tostring(text or "")
        if text == "" then return end
        if Async and Async.message_player then
          await(Async.message_player(player_id, text))
        else
          Net.message_player(player_id, text)
        end
      end

      -- Only do boss-pool logic in dungeon maps (if you have this helper)
      local area_id = Net.get_player_area(player_id)
      if is_dungeon_area and not is_dungeon_area(area_id) then
        return props["Next 1"]
      end

      local encounter_name = _trim(props["Encounter Name"] or props["Encounter"] or "")
      if encounter_name == "" then
        print(("[DUNGEON] DungeonBoss missing 'Encounter Name' (pid=%s)"):format(tostring(player_id)))
        return props["Next 1"]
      end

      local boss_id  = _trim(props["Boss ID"] or props["Boss"] or encounter_name)
      local mem_area = _trim(props["Boss Memory Area"] or area_id)
      if mem_area == "" then mem_area = area_id end

      local pool_max = tonumber(props["Boss Pool Max HP"] or props["Boss Pool Max"] or 0) or 0
      local win_dmg  = tonumber(props["Boss Encounter HP"] or props["Win Damage"] or 0) or 0

      -- raids-style loss tracking inputs
      local boss_encounter_hp = tonumber(props["Boss Encounter HP"] or props["Encounter HP"] or props["Enemy HP"] or 0) or 0
      local boss_id_match     = _trim(props["Boss ID Match"] or props["Boss Match"] or props["Boss Name Match"] or "")

      -- Optional ask first
      local start_prompt = _trim(props["Start Prompt"])
      if start_prompt ~= "" and Async and Async.question_player then
        local choice = await(Async.question_player(player_id, start_prompt))
        if tonumber(choice) ~= 1 then
          _msg(props["Decline Message"] or "Maybe later.")
          return props["Decline"] or props["Next 1"]
        end
      end

      -- No pool => normal encounter
      if pool_max <= 0 then
        local ezenc = _get_ezencounters()
        if ezenc and ezenc.begin_encounter_by_name then
          await(ezenc.begin_encounter_by_name(player_id, encounter_name, relay_object or npc))
        end
        return props["Next 1"]
      end

      -- Ensure boss state, block if already defeated
      local s = _ensure_boss(mem_area, boss_id, pool_max)
      if s and (s.defeated or (tonumber(s.pool_hp or 0) <= 0)) then
        _msg(props["Already Defeated Message"] or "This boss has already been defeated.")
        return props["Already Defeated"] or props["Next 1"]
      end

      -- Stash context for battle_results to consume
      dungeon._boss_fight_outcome[player_id] = nil
      dungeon._boss_fight_ctx[player_id] = {
        boss_id            = boss_id,
        mem_area           = mem_area,
        pool_max           = pool_max,
        win_damage         = win_dmg,
        boss_encounter_hp  = boss_encounter_hp,
        boss_id_match_csv  = boss_id_match,
      }

      local ezenc = _get_ezencounters()
      if not ezenc or not ezenc.begin_encounter_by_name then
        print("[DUNGEON] ezencounters.begin_encounter_by_name missing; can't start boss encounter")
        dungeon._boss_fight_ctx[player_id] = nil
        return props["Next 1"]
      end

      -- Start and wait for battle to finish (battle_results will populate outcome)
      await(ezenc.begin_encounter_by_name(player_id, encounter_name, relay_object or npc))

      local out = dungeon._boss_fight_outcome[player_id]
      dungeon._boss_fight_outcome[player_id] = nil

      if not out then
        -- Safety fallback
        return props["Next 1"]
      end

      -- Ran: do not touch pool
      if out.ran then
        _msg(props["Ran Message"] or "")
        return props["Battle Ran"] or props["Next 1"]
      end

      -- Progress message (always based on the applied pool update)
      local hide_progress = tostring(props["Hide Progress"] or "") == "true"
      if not hide_progress and out.state then
        local prog = tostring(props["Progress Message"] or "")
        if prog == "" then prog = "{id} HP: {hp}/{max} (-{dmg})" end
        _msg(_fmt_progress(prog, boss_id, out.state, tonumber(out.applied or 0) or 0))
      end

      if out.defeated_now then
        _msg(props["Boss Defeated Message"] or "Boss defeated!")
        return props["Boss Defeated"] or props["Battle Won"] or props["Next 1"]
      end

      -- Lost => kick using your existing dungeon kick flow
      if (tonumber(out.hp or 0) or 0) <= 0 then
        local kick = dungeon.kick_player_out_of_dungeon or kick_player_out_of_dungeon
        if kick then
          -- If we just showed progress, defer so the next close shows Damage critical,
          -- and the following close performs the warp (same pattern as your run-penalty fix)
          local revived = kick(player_id, false) -- always show DAMAGE_MSG immediately when we’re actually kicking

          if not revived then
            return nil -- IMPORTANT: end the dialogue chain so you can't start another fight
          end
        end
        return props["Battle Lost"] or props["Next 1"]
      end

      return props["Battle Won"] or props["Next 1"]
    end)
  end
}

eznpcs.add_event(DUNGEON_BOSS_DIALOGUE_EVENT)


-- =========================================================
-- Boss pool damage computed from battle_results (raids-style)
-- =========================================================
dungeon._boss_fight_ctx     = dungeon._boss_fight_ctx     or {}
dungeon._boss_fight_outcome = dungeon._boss_fight_outcome or {}

local function _norm_id(s)
  s = tostring(s or "")
  -- drop control + non-ascii junk (fixes HeelNavi� etc)
  s = s:gsub("[%z\1-\31\127]", "")
  s = s:gsub("[\128-\255]", "")
  s = s:lower()
  -- keep only word-ish, remove underscores for looser matching
  s = s:gsub("[^%w_%-]", "")
  s = s:gsub("_", "")
  return s
end

local function _split_match_tokens(s)
  local out = {}
  s = tostring(s or "")
  for tok in s:gmatch("[^,|;]+") do
    tok = _norm_id(tok)
    if tok ~= "" then out[#out+1] = tok end
  end
  return out
end

local function _result_flags_local(stats)
  local reason = tonumber(stats and stats.reason or 0) or 0
  local hp = tonumber(stats and (stats.health or stats.player_hp or stats.hp) or 0) or 0
  local ran = false
  if reason == 3 or reason == 4 then ran = true end
  if stats and (stats.ran or stats.fled or stats.escape) then ran = true end
  local won = (reason == 1) or (stats and stats.won == true) or false
  return { reason = reason, hp = hp, ran = ran, won = won }
end

local function _boss_damage_from_stats_local(stats, boss_encounter_hp, boss_match_csv, flags, win_damage)
  if flags and flags.won and (tonumber(win_damage or 0) or 0) > 0 then
    return tonumber(win_damage) or 0
  end

  local max_hp = tonumber(boss_encounter_hp or 0) or 0
  if max_hp <= 0 then return 0 end

  local enemies = stats and stats.enemies
  if type(enemies) ~= "table" then return 0 end

  local tokens = _split_match_tokens(boss_match_csv)
  local best = 0

  for _, e in pairs(enemies) do
    local raw_id = tostring((e and (e.id or e.name or e.species or e.type)) or "")
    local idn = _norm_id(raw_id)
    if idn ~= "" then
      local match = (#tokens == 0)
      if not match then
        for _, t in ipairs(tokens) do
          if idn:find(t, 1, true) then match = true break end
        end
      end

      if match then
        local cur = tonumber((e and (e.health or e.remaining_hp or e.hp or e.current_health or e.cur_hp)) or 0) or 0
        local dmg = max_hp - cur
        if dmg > best then best = dmg end
      end
    end
  end

  if best < 0 then best = 0 end
  return best
end

Net:on("battle_results", function(ev)
  if type(ev) ~= "table" then return end

  local stats = (type(ev.stats) == "table") and ev.stats or ev
  local pid = ev.player_id or (stats and stats.player_id)
  if not pid then return end

  local ctx = dungeon._boss_fight_ctx[pid]
  if not ctx then return end

  local flags = _result_flags_local(stats)
  local out = { ran = flags.ran, hp = flags.hp, reason = flags.reason, won = flags.won }

  if not flags.ran then
    local dmg = _boss_damage_from_stats_local(
      stats,
      ctx.boss_encounter_hp,
      ctx.boss_id_match_csv,
      flags,
      ctx.win_damage
    )

    local state, defeated_now, applied = dungeon.apply_boss_pool_damage(
      ctx.mem_area,
      ctx.boss_id,
      dmg,
      ctx.pool_max
    )

    out.state = state
    out.defeated_now = defeated_now
    out.applied = applied
    out.dmg = dmg
  end

  dungeon._boss_fight_outcome[pid] = out
  dungeon._boss_fight_ctx[pid] = nil
end)


return dungeon
