-- /server/scripts/raids/main.lua
-- Modular, ezlibs-only Raid Framework
-- Usage:
--   1) Put this file + config.lua + encounters.lua in /server/scripts/raids/
--   2) Ensure this file is required at boot by *some* loaded script, e.g. add:
--        helpers.safe_require('scripts/raids/main')
--      to your scripts/eznpcs_events.lua (or require it from anywhere that always loads).
--   3) In Tiled, set an NPC Dialogue with:  Dialogue Type = "raid"
--      Optional custom properties on the Dialogue:
--        - Raid ID         : string key (defaults to "default")
--        - Raid Style      : "Repeat" | "Once"   (defaults from config.lua)
--        - Wave2 Points    : number (override threshold to unlock wave 2)
--        - Wave3 Points    : number (override threshold to unlock wave 3)
--        - Boss Pool HP    : number (override boss shared HP pool max)
--        - Boss Win Damage : number (damage applied to pool when player wins; default 500)
--        - Memory Area     : area_id string to store shared progress (defaults to current area)
--        - Raid Done Msg   : message to show if Raid Style is Once and already cleared
--   4) To show the leaderboard, place an object with type = "RaidBBS"
--      (optional property "Raid ID" to select a specific raid id; else "default").
--
-- Flow (no menus > 3 options):
--   • Player talks to a "raid" NPC -> we show a short info line and ask "Fight? Yes/No".
--   • We immediately toss the player into the correct wave based on shared progress:
--       Wave 1 until Wave2 Points reached, then Wave 2 until Wave3 Points reached,
--       then Wave 3 (boss) until the Boss Pool HP hits 0.
--   • Wave 1/2 points are awarded from busting level (S=10, 9..1 -> 9..1). No points on run/defeat.
--   • Boss reduces the shared HP pool. On win: Boss Win Damage (or from stats if exposed).
--     On loss: we try to subtract partial damage if stats expose enemy remaining HP (best effort).
--   • After each battle we message progress to the player.
--   • When boss pool reaches 0:
--       - If style == "Repeat": the raid auto-resets to Wave 1.
--       - If style == "Once"  : further attempts show Raid Done Msg (or a default) and do nothing.
--   • Reward hooks are defined in config.lua (no hard ties to other systems).
--
-- Public API (returned as module table):
--   raids.get_state(area_id, raid_id)
--   raids.reset(area_id, raid_id)
--   raids.report_points(pid, amount, raid_id?)          -- optional manual hook
--   raids.report_boss_damage(pid, damage, raid_id?)     -- optional manual hook

local eznpcs       = require('scripts/ezlibs-scripts/eznpcs/eznpcs')
local ezencounters = require('scripts/ezlibs-scripts/ezencounters/main')
local ezmemory     = require('scripts/ezlibs-scripts/ezmemory')
local helpers      = require('scripts/ezlibs-scripts/helpers')

local Config       = require('scripts/raids/config')
local Enc          = require('scripts/raids/encounters')

local Raids = {}

-- =========================
-- ===== Utilities =========
-- =========================

local function _now() return os.time() end

local function _pick_weighted(list)
  local total = 0
  for _, e in ipairs(list or {}) do total = total + (tonumber(e.weight) or 0) end
  if total <= 0 then return nil end
  local roll, acc = math.random() * total, 0
  for _, e in ipairs(list) do
    acc = acc + (tonumber(e.weight) or 0)
    if roll <= acc then return e end
  end
  return list[#list]
end

local function _safe_area_mem(area_id)
  local mem = ezmemory.get_area_memory(area_id)
  if not mem then mem = {} end
  mem.raids = mem.raids or {}
  return mem, mem.raids
end

local function _safe_secret(pid)
  return helpers.get_safe_player_secret and helpers.get_safe_player_secret(pid) or tostring(pid)
end

local function _calc_points_from_stats(stats)
  -- Best-effort extraction of a Busting Level. Supports several possible shapes.
  -- Priority: numeric 10..1 or letter 'S' -> 10.
  local v = nil
  if stats then
    v = stats.busting or stats.busting_level or stats.busting_lv or stats.rank or stats.score
  end
  if type(v) == 'string' then
    v = v:upper()
    if v == 'S' then return 10 end
    local n = tonumber(v) ; if n then v = n else v = nil end
  end
  if type(v) == 'number' then
    local n = math.floor(v)
    if n >= 10 then return 10 end
    if n <= 0  then return 0  end
    return n
  end
  return 0
end

local function _boss_damage_from_stats(stats, fallback_on_win)
  -- We try a few common shapes:
  --  stats.enemy_total_hp, stats.enemy_remaining_hp
  --  stats.damage_to_enemy, stats.total_damage, stats.damage_dealt
  if not stats then return 0 end
  local tot = tonumber(stats.enemy_total_hp or stats.enemy_total or stats.total_enemy_hp)
  local rem = tonumber(stats.enemy_remaining_hp or stats.enemy_remaining or stats.enemy_hp)
  local dmg = tonumber(stats.damage_to_enemy or stats.total_damage or stats.damage_dealt)
  if dmg and dmg > 0 then return math.floor(dmg) end
  if tot and rem and (tot >= rem) then return math.floor(tot - rem) end
  -- Fallback: if the player won, apply a fixed chunk (configured)
  if (not stats.ran) and (tonumber(stats.health or 1) > 0) and fallback_on_win then
    return math.floor(fallback_on_win)
  end
  return 0
end

-- =========================
-- ===== State =========
-- =========================

local function _ensure_state(area_id, raid_id, overrides)
  local mem, store = _safe_area_mem(area_id)
  local s = store[raid_id]
  if not s then
    local cfg = Config.get_defaults(raid_id)
    -- Apply overrides (from Dialogue custom properties)
    if overrides then
      if overrides.style then cfg.style = overrides.style end
      if overrides.wave2 then cfg.wave2_points_required = tonumber(overrides.wave2) or cfg.wave2_points_required end
      if overrides.wave3 then cfg.wave3_points_required = tonumber(overrides.wave3) or cfg.wave3_points_required end
      if overrides.boss_hp then cfg.boss_pool_max = tonumber(overrides.boss_hp) or cfg.boss_pool_max end
      if overrides.boss_win_damage then cfg.boss_win_damage = tonumber(overrides.boss_win_damage) or cfg.boss_win_damage end
    end
    s = {
      raid_id              = raid_id,
      style                = cfg.style or "Repeat",
      wave                 = 1,
      wave1_points         = 0,
      wave2_points         = 0,
      wave2_points_required= tonumber(cfg.wave2_points_required or 50),
      wave3_points_required= tonumber(cfg.wave3_points_required or 35),
      boss_pool_max        = tonumber(cfg.boss_pool_max or 10000),
      boss_pool_hp         = tonumber(cfg.boss_pool_max or 10000),
      boss_win_damage      = tonumber(cfg.boss_win_damage or 500),
      boss_encounter_hp    = tonumber(cfg.boss_encounter_hp or 0),
      boss_id_match        = tostring(cfg.boss_id_match or ""),
      defeated             = false,
      defeated_at          = nil,
      contributions        = {},   -- [secret] = { points = n, wins = n, boss_dmg = n }
      claims               = { wave1 = {}, wave2 = {}, boss = {} }, -- for reward hooks (opt-in)
    }
    -- Apply overrides from Dialogue custom properties (if present)
    if overrides then
      if overrides.boss_encounter_hp then
        s.boss_encounter_hp = tonumber(overrides.boss_encounter_hp) or s.boss_encounter_hp
      end
      if overrides.boss_id_match and overrides.boss_id_match ~= "" then
        s.boss_id_match = tostring(overrides.boss_id_match)
      end
    end
    store[raid_id] = s
    ezmemory.save_area_memory(area_id)
  end
  return s, mem, store
end

local function _maybe_advance_wave(s)
  -- Lock wave 1 once it's cleared; lock wave 2 once it's cleared.
  if s.wave < 2 and s.wave1_points >= s.wave2_points_required then s.wave = 2 end
  if s.wave < 3 and s.wave2_points >= s.wave3_points_required then s.wave = 3 end
end

local function _try_reset_if_repeat(s)
  if s.style == "Repeat" and s.defeated then
    -- Reset to fresh raid
    s.wave           = 1
    s.wave1_points   = 0
    s.wave2_points   = 0
    s.boss_pool_hp   = s.boss_pool_max
    s.defeated       = false
    s.defeated_at    = nil
    s.contributions  = {}
    s.claims         = { wave1 = {}, wave2 = {}, boss = {} }
  end
end

function Raids.get_state(area_id, raid_id)
  local s = _ensure_state(area_id, raid_id)
  return s
end

function Raids.reset(area_id, raid_id)
  local mem, store = _safe_area_mem(area_id)
  store[raid_id] = nil
  ezmemory.save_area_memory(area_id)
end

-- Optional manual hooks:
function Raids.report_points(pid, amount, raid_id)
  local area_id = Net.get_player_area(pid)
  local s = _ensure_state(area_id, raid_id or "default")
  amount = math.max(0, math.floor(tonumber(amount) or 0))
  if amount <= 0 then return end
  local secret = _safe_secret(pid)
  local c = s.contributions[secret] or { points=0, wins=0, boss_dmg=0 }
  c.points = (c.points or 0) + amount
  c.wins   = (c.wins   or 0) + 1
  s.contributions[secret] = c
  if s.wave < 2 then s.wave1_points = (s.wave1_points or 0) + amount
  elseif s.wave < 3 then s.wave2_points = (s.wave2_points or 0) + amount end
  _maybe_advance_wave(s)
end

function Raids.report_boss_damage(pid, damage, raid_id)
  local area_id = Net.get_player_area(pid)
  local s = _ensure_state(area_id, raid_id or "default")
  damage = math.max(0, math.floor(tonumber(damage) or 0))
  if damage <= 0 then return end
  local secret = _safe_secret(pid)
  local c = s.contributions[secret] or { points=0, wins=0, boss_dmg=0 }
  c.boss_dmg = (c.boss_dmg or 0) + damage
  s.contributions[secret] = c
  s.boss_pool_hp = math.max(0, (s.boss_pool_hp or 0) - damage)
end

-- =========================
-- ===== Leaderboard =======
-- =========================

local function _open_raid_board(pid, area_id, raid_id)
  local s = _ensure_state(area_id, raid_id)
  local title = string.format("Raid - %s", raid_id)
  local color = { r=255, g=230, b=140 }

  local rows = {}
  for secret, c in pairs(s.contributions or {}) do
    local name = "Unknown"
    local pm = ezmemory.get_player_memory(secret) or {}
    if pm.teams and pm.teams.last_name and pm.teams.last_name ~= "" then
      name = pm.teams.last_name
    elseif pm.last_name and pm.last_name ~= "" then
      name = pm.last_name
    end
    rows[#rows+1] = { name=name, points=tonumber(c.points or 0), boss=tonumber(c.boss_dmg or 0) }
  end

  table.sort(rows, function(a,b)
    if a.points ~= b.points then return (a.points > b.points) end
    return a.name < b.name
  end)

  local posts = {}
  posts[#posts+1] = { id="__raidbbs:hdr", read=true,
                      title=(("Wave1: %d/%d  -  Wave2: %d/%d  -  Boss HP: %d/%d")
                              :format(s.wave1_points or 0, s.wave2_points_required or 0,
                                      s.wave2_points or 0, s.wave3_points_required or 0,
                                      s.boss_pool_hp or 0, s.boss_pool_max or 0)),
                      author="" }

  if #rows == 0 then
    posts[#posts+1] = { id="__raidbbs:none", read=true, title="No contributors yet.", author="" }
  else
    local limit = 20
    for i=1, math.min(limit, #rows) do
      local r = rows[i]
      posts[#posts+1] = { id=("__raidbbs:row:"..i), read=true,
                           title=(("%d. %s  %dpt  %dDMG"):format(i, r.name, r.points, r.boss)),
                           author="" }
    end
  end
  posts[#posts+1] = { id="__raidbbs:close", read=true, title="Close", author="" }

  -- Use Net.open_board directly (short single-page board).
  Net.open_board(pid, title, color, posts)
end

-- Hook object type = "RaidBBS"
if not _G.__RAIDS_BBS_WIRED then
  _G.__RAIDS_BBS_WIRED = true
  Net:on("object_interaction", function(ev)
    if ev.button ~= 0 then return end
    local pid     = ev.player_id
    local area_id = Net.get_player_area(pid)
    local obj = area_id and Net.get_object_by_id(area_id, ev.object_id)
    if not obj then return end
    if obj.type == "RaidBBS" then
      local raid_id = (obj.custom_properties and (obj.custom_properties["Raid ID"] or obj.custom_properties["Raid"]))
                      or "default"
      _open_raid_board(pid, area_id, tostring(raid_id))
    end
  end)
  Net:on("post_selection", function(ev)
    if tostring(ev.post_id or "") == "__raidbbs:close" then pcall(Net.close_bbs, ev.player_id) end
  end)
end

-- Extract boss damage from the 'enemies' list: damage = boss_encounter_hp - boss_remaining_hp
local function _boss_damage_from_enemies_list(stats, encounter_hp, id_match)
  if not stats or type(stats.enemies) ~= "table" then return nil end
  if not encounter_hp or encounter_hp <= 0 then return nil end
  if not id_match or id_match == "" then return nil end

  local needle = tostring(id_match):lower()
  local target = nil
  for _, e in pairs(stats.enemies) do
    local id = tostring(e.id or "")
    if id:lower():find(needle, 1, true) then  -- plain substring match
      target = e
      break
    end
  end
  if not target then return nil end

  local rem = tonumber(target.health)
  if not rem then return nil end

  local dmg = encounter_hp - rem
  if dmg < 0 then dmg = 0 end
  return dmg
end

-- =========================
-- ===== Core Event ========
-- =========================

local function _raid_action(npc, pid, dialogue, relay_object)
  return async(function()
    -- Resolve raid settings
    local raid_id   = (dialogue.custom_properties and (dialogue.custom_properties["Raid ID"] or dialogue.custom_properties["Raid"])) or "default"
    local style     = (dialogue.custom_properties and dialogue.custom_properties["Raid Style"]) or nil
    local wave2_pt  = dialogue.custom_properties and tonumber(dialogue.custom_properties["Wave2 Points"])
    local wave3_pt  = dialogue.custom_properties and tonumber(dialogue.custom_properties["Wave3 Points"])
    local boss_hp   = dialogue.custom_properties and tonumber(dialogue.custom_properties["Boss Pool HP"])
    local boss_win  = dialogue.custom_properties and tonumber(dialogue.custom_properties["Boss Win Damage"])
    local mem_area  = (dialogue.custom_properties and (dialogue.custom_properties["Memory Area"] or dialogue.custom_properties["Raid Area"])) or Net.get_player_area(pid)
    local done_msg  = (dialogue.custom_properties and dialogue.custom_properties["Raid Done Msg"]) or "The raid has already been cleared."
    local boss_enc_hp = dialogue.custom_properties and tonumber(dialogue.custom_properties["Boss Encounter HP"])
    local boss_match  = dialogue.custom_properties and dialogue.custom_properties["Boss ID Match"]

    raid_id = tostring(raid_id or "default")
    mem_area = tostring(mem_area or Net.get_player_area(pid))
    local overrides = {
      style = style,
      wave2 = wave2_pt,
      wave3 = wave3_pt,
      boss_hp = boss_hp,
      boss_win_damage = boss_win,
      boss_encounter_hp = boss_enc_hp,
      boss_id_match = boss_match,
    }
    local s, mem, store = _ensure_state(mem_area, raid_id, overrides)

    -- If style is "Repeat" and previously defeated, reset immediately on interaction.
    _try_reset_if_repeat(s)

    if s.style == "Once" and s.defeated then
      await(Async.message_player(pid, done_msg))
      return nil
    end

    -- Wave advance (in case thresholds were externally tweaked)
    _maybe_advance_wave(s)

    -- Short info -> YES/NO
    await(Async.message_player(pid, 
      ("Raid '%s' • Wave %d/3 • W2:%d/%d • W3:%d/%d • Boss:%d/%d")
      :format(raid_id, s.wave, s.wave1_points, s.wave2_points_required,
              s.wave2_points, s.wave3_points_required,
              s.boss_pool_hp, s.boss_pool_max)))

    local ans = await(Async.quiz_player(pid, "Fight", "Info", "Leave"))
    if ans == 1 then  -- "Info"
      await(Async.message_player(pid,
        "Three waves:\n- Wave1/2: earn points by Busting LV (S=10..1=1).\n- Wave3: chip away a shared Boss HP pool.\nNo farming of wave 1 once cleared."))
      return nil
    elseif ans ~= 0 then
      return nil
    end

    -- Select encounter for current wave
    local pack_list
    if s.wave == 1 then pack_list = Enc.get_pack(raid_id, 1)
    elseif s.wave == 2 then pack_list = Enc.get_pack(raid_id, 2)
    else pack_list = Enc.get_pack(raid_id, 3) end

    if not pack_list or #pack_list == 0 then
      await(Async.message_player(pid, "This raid has no encounters configured for wave "..tostring(s.wave).."."))
      return nil
    end

    local spec = _pick_weighted(pack_list) or pack_list[1]

    -- Begin encounter and await result
    local stats = await(ezencounters.begin_encounter(pid, spec))

-- ==== RAID DEBUG: dump all boss stats to server log ====
do
  local function _dump(prefix, v, seen, depth)
    seen  = seen  or {}
    depth = depth or 0
    local ind = string.rep("  ", depth)
    local tv  = type(v)
    if tv ~= "table" then
      print(string.format("[RAID DBG] %s%s", prefix or "", tostring(v)))
      return
    end
    if seen[v] then
      print(string.format("[RAID DBG] %s{<cycle>}", prefix or ""))
      return
    end
    seen[v] = true
    for k,val in pairs(v) do
      local line = string.format("%s[%s] = ", ind, tostring(k))
      if type(val) == "table" then
        print(string.format("[RAID DBG] %s{", line))
        _dump(ind, val, seen, depth + 1)
        print(string.format("[RAID DBG] %s}", ind))
      else
        print(string.format("[RAID DBG] %s%s", line, tostring(val)))
      end
    end
  end

  print("[RAID DBG] -------- Boss encounter stats (raw) --------")
  _dump("", stats)

  -- Heuristic summary (common field names across ezencounters builds)
  local rem = stats and (stats.boss_hp_left or stats.enemy_remaining_hp or stats.enemy_hp or
                         stats.hp_left or stats.remaining_hp or stats.enemy_remaining)
  local tot = stats and (stats.enemy_total_hp or stats.total_enemy_hp or stats.enemy_total or stats.total_hp)
  local ran = stats and (stats.ran or stats.fled or stats.escape)
  local php = stats and (stats.health or stats.player_hp or stats.hp)
  local won = (not ran) and (tonumber(php or 0) > 0)

  print(string.format(
    "[RAID DBG] -------- Boss summary -------- won=%s ran=%s player_hp=%s enemy_remaining=%s enemy_total=%s",
    tostring(won), tostring(ran), tostring(php), tostring(rem), tostring(tot)
  ))
  print("[RAID DBG] -------------------------------------------")
end
-- ==== /RAID DEBUG ====

    -- Handle result per wave
    if s.wave < 3 then
      if stats.ran or tonumber(stats.health or 0) <= 0 then
        await(Async.message_player(pid, "No points earned."))
        return nil
      end
      local pts = _calc_points_from_stats(stats)
      pts = math.max(0, math.floor(pts or 0))
      local secret = _safe_secret(pid)
      local c = s.contributions[secret] or { points=0, wins=0, boss_dmg=0 }
      c.points = (c.points or 0) + pts
      c.wins   = (c.wins   or 0) + 1
      s.contributions[secret] = c

      if s.wave == 1 then
        s.wave1_points = (s.wave1_points or 0) + pts
        local was = s.wave
        _maybe_advance_wave(s)
        ezmemory.save_area_memory(mem_area)
        if was == 1 and s.wave == 2 then
          -- Wave 1 just cleared -> reward hook
          if Config.on_wave1_cleared then pcall(Config.on_wave1_cleared, pid, raid_id, s) end
          await(Async.message_player(pid, ("Wave 1 cleared! Progress: %d/%d"):format(s.wave1_points, s.wave2_points_required)))
        else
          await(Async.message_player(pid, ("+%d pt  •  Wave 1: %d/%d"):format(pts, s.wave1_points, s.wave2_points_required)))
        end
      else -- wave 2
        s.wave2_points = (s.wave2_points or 0) + pts
        local was = s.wave
        _maybe_advance_wave(s)
        ezmemory.save_area_memory(mem_area)
        if was == 2 and s.wave == 3 then
          if Config.on_wave2_cleared then pcall(Config.on_wave2_cleared, pid, raid_id, s) end
          await(Async.message_player(pid, ("Wave 2 cleared! Progress: %d/%d"):format(s.wave2_points, s.wave3_points_required)))
        else
          await(Async.message_player(pid, ("+%d pt  •  Wave 2: %d/%d"):format(pts, s.wave2_points, s.wave3_points_required)))
        end
      end
      return nil
    else
      -- Boss wave
      local dmg = _boss_damage_from_enemies_list(stats, s.boss_encounter_hp, s.boss_id_match)
      -- If we didn't find the boss entry:
      if not dmg then
        -- If the player WON (player HP > 0), assume full encounter damage
        if tonumber(stats and stats.health or 0) > 0 and s.boss_encounter_hp and s.boss_encounter_hp > 0 then
          dmg = s.boss_encounter_hp
        else
          -- Otherwise fall back to your old heuristic (kept as a safety net)
          dmg = _boss_damage_from_stats(stats, s.boss_win_damage)
        end
      end
      if dmg > 0 then
        local secret = _safe_secret(pid)
        local c = s.contributions[secret] or { points=0, wins=0, boss_dmg=0 }
        c.boss_dmg = (c.boss_dmg or 0) + dmg
        s.contributions[secret] = c
        s.boss_pool_hp = math.max(0, (s.boss_pool_hp or 0) - dmg)
      end
      local msg = ("Boss HP: %d/%d"):format(s.boss_pool_hp or 0, s.boss_pool_max or 0)
      if s.boss_pool_hp <= 0 then
        s.defeated = true
        s.defeated_at = _now()
        ezmemory.save_area_memory(mem_area)
        if Config.on_boss_defeated then pcall(Config.on_boss_defeated, pid, raid_id, s) end
        await(Async.message_player(pid, "Boss defeated!"))
        -- Auto-reset if repeat
        _try_reset_if_repeat(s)
        ezmemory.save_area_memory(mem_area)
      else
        ezmemory.save_area_memory(mem_area)
        await(Async.message_player(pid, (dmg > 0) and (("-"..dmg.." • "..msg)) or msg))
      end
      return nil
    end
  end)
end

-- Register dialogue type "raid"
eznpcs.add_event({
  name   = "raid",
  action = _raid_action,
})

return Raids
