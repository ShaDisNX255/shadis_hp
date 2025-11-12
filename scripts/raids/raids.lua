local eznpcs       = require('scripts/ezlibs-scripts/eznpcs/eznpcs')
local ezencounters = require('scripts/ezlibs-scripts/ezencounters/main')
local ezmemory     = require('scripts/ezlibs-scripts/ezmemory')
local helpers      = require('scripts/ezlibs-scripts/helpers')

local Config       = require('scripts/raids/config')
local Enc          = require('scripts/raids/encounters')

local TeamsOK, Teams = pcall(require, 'scripts/teams/teams')
-- ===== Force-init Displayer once (boot-safe) =====
if not _G.__DISPLAYER_READY then
  -- Try the primary module
  local ok, D = pcall(require, 'scripts/displayer/displayer')
  if ok and type(D) == 'table' then
    -- Many builds return an instance that must be initialized
    if D.init then pcall(D.init, D) end
    -- Publish to global so every script can find the same instance
    _G.Displayer = D
  end

  -- Some builds register subsystems on require; make sure text subsystem is loaded
  if not (_G.Displayer and _G.Displayer.Text and _G.Displayer.Text.drawMarqueeText) then
    pcall(require, 'scripts/displayer/text-display')
  end

  -- Final sanity: if we still only have the table but not the methods, init now
  if _G.Displayer and _G.Displayer.init
     and not (_G.Displayer.Text and _G.Displayer.Text.drawMarqueeText) then
    pcall(_G.Displayer.init, _G.Displayer)
  end

  _G.__DISPLAYER_READY = (_G.Displayer and _G.Displayer.Text and _G.Displayer.Text.drawMarqueeText) or false
  print("[RAIDS] Displayer init:", _G.__DISPLAYER_READY and "OK" or "FAILED")
end
-- ===== /Force-init Displayer =====

-- ===== Login test marquee (local toggle) =====
local TEST_LOGIN_MARQUEE = false   -- set true to show a test marquee on login
local TEST_LOGIN_TEXT    = "Login test marquee - tweak in raids.lua"
local TEST_LOGIN_OPTS    = { loops = 2 }  -- you can add width/height/scale/speed/etc here
-- ===== /Login test marquee =====

-- Force the login marquee to read a specific Raid ID / Area
-- Set to nil to auto-detect like before.
local LOGIN_ANNOUNCE_RAID_ID   = "RaidTest2"   -- <== put your exact Raid ID here (or nil)
local LOGIN_ANNOUNCE_MEM_AREA  = nil           -- optional: e.g. "WCity1"; nil = use RAID_MEM_AREA or player's area

-- Peek current raid store for an area without creating anything
local function _peek_store(area_id)
  local mem = ezmemory.get_area_memory(area_id)
  return (mem and mem.raids) or {}
end

-- true if a raid is “active” (has actually started)
local function _is_active(s)
  if not s then return false end
  -- Active as soon as wave1 has any points, wave advanced, or boss HP moved.
  return (tonumber(s.wave1_points or 0) > 0)
      or (tonumber(s.wave or 1) > 1)
      or (tonumber(s.boss_pool_hp or s.boss_pool_max or 0) < tonumber(s.boss_pool_max or 0))
end

-- Find any active raid in area (prefer truly active; else most progressed)
local function _find_active_or_progress(area_id)
  local store = _peek_store(area_id)
  local best_id, best_s, best_score = nil, nil, -1

  for rid, s in pairs(store) do
    if _is_active(s) then
      return rid, s
    end
    -- Not active: choose the most progressed as a fallback
    local wave  = tonumber(s.wave or 1) or 1
    local wsum  = (tonumber(s.wave1_points or 0) or 0) + (tonumber(s.wave2_points or 0) or 0)
    local score = (wave * 100000) + wsum
    if score > best_score then
      best_id, best_s, best_score = rid, s, score
    end
  end

  return best_id, best_s  -- may be nil/nil if no raids exist yet
end

-- ==== Online tracking (global, area-agnostic) ====
local ONLINE = {}  -- [pid] = true

-- Keep ONLINE in sync (cover both common event names)
if not _G.__RAIDS_ONLINE_WIRED then
  _G.__RAIDS_ONLINE_WIRED = true

  Net:on("player_join", function(ev)
    ONLINE[ev.player_id] = true
  end)

  Net:on("player_disconnect", function(ev)
    ONLINE[ev.player_id] = nil
  end)
  Net:on("player_left", function(ev)   -- some builds use a different name
    ONLINE[ev.player_id] = nil
  end)
end
-- ==== /Online tracking ====

local CFG_DEFAULTS  = (Config and Config.get_defaults and Config.get_defaults("default")) or {}
local RAID_MEM_AREA = CFG_DEFAULTS.raid_memory_area

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

-- Right-side marquee look (tweak as you like)
local UI = {
  scale        = 1.2,
  z            = 220,
  speed        = "slow",   -- slow | medium | quick
  width        = 200,
  height       = 38,
  padding_x    = 6,
  padding_y    = 4,
  margin_right = -90,          -- distance from the right edge
  y            = 6,          -- top Y of the box
  loops        = 2,          -- exactly two passes, as requested
  font         = "THICK",
}

local function _screen_w() return 240 end
local function _screen_h() return 160 end

-- get all connected player ids (global or area-scoped)
local function _all_pids(area_id)
  local ids = {}

  -- Primary source: our ONLINE set
  if area_id then
    for pid,_ in pairs(ONLINE) do
      local ok, a = pcall(Net.get_player_area, pid)
      if ok and a == area_id then
        ids[#ids+1] = pid
      end
    end
  else
    for pid,_ in pairs(ONLINE) do
      ids[#ids+1] = pid
    end
  end

  -- Fallback if ONLINE is empty (e.g., server boot race)
  if #ids == 0 then
    if Net.get_player_ids then
      local ok, v = pcall(Net.get_player_ids)
      if ok and type(v) == "table" then ids = v end
    elseif Net.get_players then
      local ok, m = pcall(Net.get_players)
      if ok and type(m) == "table" then
        for pid,_ in pairs(m) do ids[#ids+1] = pid end
      end
    elseif Net.list_players then
      -- try all areas we can infer from connected players
      -- (no-op here if we truly don't know any areas yet)
      for pid,_ in pairs(ONLINE) do
        local ok, a = pcall(Net.get_player_area, pid)
        if ok and a then
          local ok2, v = pcall(Net.list_players, a)
          if ok2 and type(v) == "table" then
            for _,p in ipairs(v) do ids[#ids+1] = p end
          end
        end
      end
    end
  end

  -- Deduplicate in case multiple sources added the same pid
  if #ids > 1 then
    local seen, out = {}, {}
    for _,p in ipairs(ids) do
      if not seen[p] then seen[p] = true; out[#out+1] = p end
    end
    ids = out
  end

  return ids
end

-- draw a right-side marquee for one player
local function _marquee(pid, text, opts)
  local D = _G.Displayer
  if not (D and D.Text and D.Text.drawMarqueeText) then
    print("[RAIDS] ERROR: Displayer.Text.drawMarqueeText unavailable after init; aborting draw")
    return
  end

  opts = opts or {}
  local scale       = opts.scale or UI.scale
  local width       = opts.width or UI.width
  local height      = opts.height or UI.height
  local padding_x   = opts.padding_x or UI.padding_x
  local padding_y   = opts.padding_y or UI.padding_y
  local margin_right= opts.margin_right or UI.margin_right
  local y           = opts.y or UI.y
  local z           = opts.z or UI.z
  local speed       = opts.speed or UI.speed
  local loops       = (opts.loops ~= nil) and opts.loops or UI.loops
  local font        = opts.font or UI.font

  local line_h   = math.ceil(9 * scale)  -- THICK baseline ~9px
  local x        = _screen_w() - margin_right - width
  local baseline = y + padding_y + line_h - 2

  D.Text.drawMarqueeText(
    pid,
    "__raid_announce",
    tostring(text or ""),
    baseline,
    font, scale,
    z,
    speed,
    {
      x=x, y=y, width=width, height=height,
      padding_x=padding_x, padding_y=padding_y,
      loops=loops,
    }
  )
end

-- broadcast marquee to ALL currently connected players
local function _announce_all(text, opts, area_id)
  local pids = _all_pids(area_id)  -- pass nil for global; pass area_id to target one area
  print(("[RAIDS] announce area=%s text=%s -> recipients=%d")
        :format(tostring(area_id or "<global>"), tostring(text), #pids))
  for _, pid in ipairs(pids) do
    local ok, err = pcall(_marquee, pid, text, opts)
    if not ok then
      print(("[RAIDS] marquee error pid=%s: %s"):format(tostring(pid), tostring(err)))
    end
  end
end

-- make a short contributions list for a wave: "Name - 15, Name2 - 8, ..."
local function _contrib_list(s, field, max_names)
  max_names = max_names or 6
  local rows = {}
  for _, c in pairs(s.contributions or {}) do
    local v = tonumber(c[field] or 0)
    if v and v > 0 then
      local name = c.name
      if (not name) or name == "" then
        local pm = ezmemory.get_player_memory(_safe_secret(c._last_pid)) or {}
        name = pm.last_name or (pm.teams and pm.teams.last_name) or "Unknown"
      end
      rows[#rows+1] = { name = name, v = v }
    end
  end
  table.sort(rows, function(a,b) if a.v ~= b.v then return a.v > b.v end return a.name < b.name end)
  local parts = {}
  for i=1, math.min(#rows, max_names) do
    parts[#parts+1] = string.format("%s - %d", rows[i].name, rows[i].v)
  end
  if #rows > max_names then parts[#parts+1] = "..." end
  return table.concat(parts, ", ")
end

-- optional team GP summary hook (shows only if your Teams module exposes it)
local function _try_team_gp_summary(raid_id, wave_label)
  if TeamsOK and Teams and Teams.get_raid_wave_gp_summary then
    local ok, r = pcall(Teams.get_raid_wave_gp_summary, raid_id, wave_label)
    if ok and r and (r.t1 or r.t2) then
      local t1n = r.team1_name or "Team 1"
      local t2n = r.team2_name or "Team 2"
      local t1d = tonumber(r.t1 or 0) or 0
      local t2d = tonumber(r.t2 or 0) or 0
      if t1d ~= 0 or t2d ~= 0 then
        local s1 = string.format("%s %s%d GP", t1n, (t1d>=0 and "+" or ""), t1d)
        local s2 = string.format("%s %s%d GP", t2n, (t2d>=0 and "+" or ""), t2d)
        return s1 .. ", " .. s2
      end
    end
  end
  return nil -- no data / no Teams support
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
      repeat_cooldown_secs  = tonumber(cfg.repeat_cooldown_secs or 1800),
      cooldown_until        = nil,
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
  local title = "Raid - " .. raid_id
  local color = { r=255, g=230, b=140 }

  local function short(sv, n)
    sv = tostring(sv or "Unknown")
    return (#sv > n) and sv:sub(1, n) or sv
  end
  local function rows_from_contribs(field)
    local rows = {}
    for secret, c in pairs(s.contributions or {}) do
      local v = tonumber(c[field] or 0)
      if v and v > 0 then                    -- only show contributors for this section
        local name = c.name
        if not name or name == "" then
          local pm = ezmemory.get_player_memory(secret) or {}
          name = pm.last_name or (pm.teams and pm.teams.last_name) or "Unknown"
        end
        rows[#rows+1] = { name = name, v = v }
      end
    end
    table.sort(rows, function(a,b)
      if a.v ~= b.v then return a.v > b.v end
      return a.name < b.name
    end)
    return rows
  end

  local w1 = rows_from_contribs("w1")
  local w2 = rows_from_contribs("w2")
  local bd = rows_from_contribs("boss_dmg")
  local N  = 10

  local posts = {}

  posts[#posts+1] = {
    id="__raidbbs:h1", read=true,
    title=string.format("-- Wave 1 %d/%d --", s.wave1_points or 0, s.wave2_points_required or 0),
    author=""
  }
  if #w1 == 0 then
    posts[#posts+1] = { id="__raidbbs:w1none", read=true, title="(No Data)", author="" }
  else
    for i=1, math.min(N, #w1) do
      local r = w1[i]
      posts[#posts+1] = { id="__raidbbs:w1:"..i, read=true, title=string.format("%d. %s %d", i, short(r.name, 14), r.v), author="" }
    end
  end

  posts[#posts+1] = {
    id="__raidbbs:h2", read=true,
    title=string.format("-- Wave 2 %d/%d --", s.wave2_points or 0, s.wave3_points_required or 0),
    author=""
  }
  if #w2 == 0 then
    posts[#posts+1] = { id="__raidbbs:w2none", read=true, title="(No Data)", author="" }
  else
    for i=1, math.min(N, #w2) do
      local r = w2[i]
      posts[#posts+1] = { id="__raidbbs:w2:"..i, read=true, title=string.format("%d. %s %d", i, short(r.name, 14), r.v), author="" }
    end
  end

  posts[#posts+1] = {
    id="__raidbbs:h3", read=true,
    title=string.format("-- Boss %d/%d --", s.boss_pool_hp or 0, s.boss_pool_max or 0),
    author=""
  }
  if #bd == 0 then
    posts[#posts+1] = { id="__raidbbs:bdnone", read=true, title="(No Data)", author="" }
  else
    for i=1, math.min(N, #bd) do
      local r = bd[i]
      posts[#posts+1] = { id="__raidbbs:bd:"..i, read=true, title=string.format("%d. %s %d", i, short(r.name, 14), r.v), author="" }
    end
  end

  posts[#posts+1] = { id="__raidbbs:close", read=true, title="Close", author="" }
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
    local repeat_cd   = dialogue.custom_properties and tonumber(dialogue.custom_properties["Repeat Cooldown Secs"])

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
      repeat_cooldown_secs = repeat_cd,
    }
    local s, mem, store = _ensure_state(mem_area, raid_id, overrides)

    -- Repeat cooldown gate
    if s.style == "Repeat" and s.defeated then
      local now = _now()
      if s.cooldown_until and now < s.cooldown_until then
        local mins = math.ceil((s.cooldown_until - now)/60)
        await(Async.message_player(pid, ("Raid inactive. Try again in %d min."):format(mins)))
        return nil
      else
        -- cooldown elapsed -> reset now
        s.cooldown_until = nil
        s.defeated = false
        s.defeated_at = nil
        s.wave = 1
        s.wave1_points, s.wave2_points = 0, 0
        s.boss_pool_hp = s.boss_pool_max
        s.contributions = {}
        s.claims = { wave1 = {}, wave2 = {}, boss = {} }
        ezmemory.save_area_memory(mem_area)
      end
    end

    if s.style == "Once" and s.defeated then
      await(Async.message_player(pid, done_msg))
      return nil
    end

    _maybe_advance_wave(s)

    -- Quiz with ONLY options (no preface)
    local ans = await(Async.quiz_player(pid, "Fight", "Info", "Leave"))

    if ans == 1 then  -- "Info"
      local status
      if s.wave == 1 then
        status = ("W1: %d/%d"):format(s.wave1_points or 0, s.wave2_points_required or 0)
      elseif s.wave == 2 then
        status = ("W2: %d/%d"):format(s.wave2_points or 0, s.wave3_points_required or 0)
      else
        status = ("Boss: %d/%d"):format(s.boss_pool_hp or 0, s.boss_pool_max or 0)
      end
      await(Async.message_player(pid, status))
      return nil
    elseif ans ~= 0 then
      return nil -- "Leave" or closed
    end

    -- Select encounter snapshot
    local wave_at_start = s.wave
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

-- ==== RAID DEBUG (enhanced: full, flattened, typed) ====
do
  -- Flattens any Lua value into dotted paths with deterministic key order.
  local function _flatten(value, base, out, seen)
    out  = out  or {}
    seen = seen or {}
    local tv = type(value)

    if tv ~= "table" then
      out[#out+1] = string.format("%s = %s (%s)", base, tostring(value), tv)
      return out
    end

    if seen[value] then
      out[#out+1] = string.format("%s = <cycle> (table)", base)
      return out
    end
    seen[value] = true

    -- Array part first (1..n)
    local n = #value
    for i = 1, n do
      _flatten(value[i], string.format("%s[%d]", base, i), out, seen)
    end

    -- Then non-array keys, sorted by tostring(key)
    local keys = {}
    for k,_ in pairs(value) do
      if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
        keys[#keys+1] = k
      end
    end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)

    for _,k in ipairs(keys) do
      local child_base
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        child_base = base .. "." .. k
      else
        child_base = base .. "[" .. tostring(k) .. "]"
      end
      _flatten(value[k], child_base, out, seen)
    end
    return out
  end

  print("[RAID DBG] -------- Encounter stats (flattened) --------")
  local lines = _flatten(stats or {}, "stats")
  for _,line in ipairs(lines) do
    print("[RAID DBG] " .. line)
  end

  -- Helpful summary + what our points parser thinks
  local ran = stats and (stats.ran or stats.fled or stats.escape)
  local php = stats and (stats.health or stats.player_hp or stats.hp)
  local won = (not ran) and (tonumber(php or 0) > 0)
  local derived = _calc_points_from_stats and _calc_points_from_stats(stats) or "n/a"

  print(string.format("[RAID DBG] summary won=%s ran=%s player_hp=%s derived_points=%s",
                      tostring(won), tostring(ran), tostring(php), tostring(derived)))
  print("[RAID DBG] --------------------------------------------")
end
-- ==== /RAID DEBUG ====

    -- Handle result per wave (use snapshot)
    if wave_at_start < 3 then
      local ran      = (stats and stats.ran) or false
      local defeated = tonumber(stats.health or 0) <= 0

      if ran then
        local secret = _safe_secret(pid)
        local c = s.contributions[secret] or { points=0, wins=0, boss_dmg=0 }
        c.chain2 = 0
        s.contributions[secret] = c
        ezmemory.save_area_memory(mem_area)
        await(Async.message_player(pid, "No points - chain reset"))
        return nil
      end

      if defeated then
        await(Async.message_player(pid, "No points earned."))
        return nil
      end

      -- Base points from busting level
      local base = _calc_points_from_stats(stats)
      base = math.max(0, math.floor(base or 0))

      -- Per-player x2 chain
      local secret = _safe_secret(pid)
      local c = s.contributions[secret] or { points=0, wins=0, boss_dmg=0 }

      local chain = tonumber(c.chain2 or 0) or 0
      if chain < 0 then chain = 0 end
      local factor = (chain > 0) and math.floor(math.pow(2, chain)) or 1
      local award  = base * factor

      local applied_tag = (factor > 1) and (" - x"..factor) or ""
      local next_chain  = (base >= 10) and (chain + 1) or 0
      local next_tag    = ""
      if base >= 10 then
        next_tag = " x"..math.floor(math.pow(2, next_chain)).."pts next"
      end

      -- Update contributor (+ pending tallies)
      local pname = Net.get_player_name(pid)
      c.points = (c.points or 0) + award
      c.wins   = (c.wins   or 0) + 1
      c.name   = pname or c.name
      c.chain2 = next_chain
      c._last_pid = pid

      if wave_at_start == 1 then
        -- Detect first-ever points on Wave 1 (brand new raid start)
        local first_points = ((tonumber(s.wave1_points or 0) or 0) <= 0) and (award > 0)

        c.w1 = (c.w1 or 0) + award
        c._pend_w1_pts = (c._pend_w1_pts or 0) + award
        s.contributions[secret] = c

        s.wave1_points = (s.wave1_points or 0) + award
        local was = s.wave
        _maybe_advance_wave(s)
        ezmemory.save_area_memory(mem_area)

        -- Announce brand-new raid started
        if first_points then
          local msg = string.format(
            "RAID STARTED - Wave 1 %d/%d",
            tonumber(s.wave1_points or 0) or 0,
            tonumber(s.wave2_points_required or 0) or 0
          )
          _announce_all(msg, { loops = 2 })
        end

        if was == 1 and s.wave == 2 then
          -- Wave 1 cleared → pay pendings
          if TeamsOK and Teams then
            for secret2, cc in pairs(s.contributions or {}) do
              local pend = tonumber(cc._pend_w1_pts or 0) or 0
              if pend > 0 then
                if Teams.on_raid_contribution_secret then
                  pcall(Teams.on_raid_contribution_secret, secret2, raid_id, "w1", pend, cc._last_pid)
                elseif cc._last_pid and Teams.on_raid_contribution then
                  pcall(Teams.on_raid_contribution, cc._last_pid, raid_id, "w1", pend)
                end
              end
              cc._pend_w1_pts = 0
            end
          end
          if Config.on_wave1_cleared then pcall(Config.on_wave1_cleared, pid, raid_id, s) end

          -- ANNOUNCE Wave 1 cleared (Team GP summary + contributions)
          local gp = _try_team_gp_summary(raid_id, "w1")
          local contribs = _contrib_list(s, "w1")
          local msg
          if gp and gp ~= "" then
            msg = string.format("WAVE 1 CLEARED - %s - Players: %s", gp, (contribs ~= "" and contribs or "(no data)"))
          else
            msg = string.format("WAVE 1 CLEARED - Players: %s", (contribs ~= "" and contribs or "(no data)"))
          end
          _announce_all(msg, { loops = 2 })

          await(Async.message_player(pid,
            ("+%d pt%s - Wave 1 cleared! %d/%d%s")
            :format(award, applied_tag, s.wave1_points, s.wave2_points_required, next_tag)))
        else
          await(Async.message_player(pid,
            ("+%d pt%s - Wave 1: %d/%d%s")
            :format(award, applied_tag, s.wave1_points, s.wave2_points_required, next_tag)))
        end

      else -- wave 2
        c.w2 = (c.w2 or 0) + award
        c._pend_w2_pts = (c._pend_w2_pts or 0) + award
        s.contributions[secret] = c

        s.wave2_points = (s.wave2_points or 0) + award
        local was = s.wave
        _maybe_advance_wave(s)
        ezmemory.save_area_memory(mem_area)

        if was == 2 and s.wave == 3 then
          -- Wave 2 cleared → pay pendings
          if TeamsOK and Teams then
            for secret2, cc in pairs(s.contributions or {}) do
              local pend = tonumber(cc._pend_w2_pts or 0) or 0
              if pend > 0 then
                if Teams.on_raid_contribution_secret then
                  pcall(Teams.on_raid_contribution_secret, secret2, raid_id, "w2", pend, cc._last_pid)
                elseif cc._last_pid and Teams.on_raid_contribution then
                  pcall(Teams.on_raid_contribution, cc._last_pid, raid_id, "w2", pend)
                end
              end
              cc._pend_w2_pts = 0
            end
          end
          if Config.on_wave2_cleared then pcall(Config.on_wave2_cleared, pid, raid_id, s) end

          -- ANNOUNCE Wave 2 cleared (Team GP summary + contributions)
          local gp = _try_team_gp_summary(raid_id, "w2")
          local contribs = _contrib_list(s, "w2")
          local msg
          if gp and gp ~= "" then
            msg = string.format("WAVE 2 CLEARED - %s - Players: %s", gp, (contribs ~= "" and contribs or "(no data)"))
          else
            msg = string.format("WAVE 2 CLEARED - Players: %s", (contribs ~= "" and contribs or "(no data)"))
          end
          _announce_all(msg, { loops = 2 })

          await(Async.message_player(pid,
            ("+%d pt%s - Wave 2 cleared! %d/%d%s")
            :format(award, applied_tag, s.wave2_points, s.wave3_points_required, next_tag)))
        else
          await(Async.message_player(pid,
            ("+%d pt%s - Wave 2: %d/%d%s")
            :format(award, applied_tag, s.wave2_points, s.wave3_points_required, next_tag)))
        end
      end
      return nil

    else
      -- Boss wave
      local ran = (stats and (stats.ran or stats.fled or stats.escape)) or false
      local enemies = stats and stats.enemies
      local has_snapshot = (type(enemies) == "table" and next(enemies) ~= nil)

      local dmg = 0

      if has_snapshot then
        -- Try to compute from enemy list (partial damage if boss present)
        dmg = _boss_damage_from_enemies_list(stats, s.boss_encounter_hp, s.boss_id_match) or 0

        -- If player ran legitimately and we don't see the boss in the snapshot,
        -- assume boss was killed and player escaped due to soft-lock adds → full encounter damage.
        if ran then
          local boss_present = false
          local match = tostring(s.boss_id_match or "")
          for _, e in pairs(enemies) do
            local id = tostring(e and e.id or "")
            if match ~= "" and id:find(match, 1, true) then
              boss_present = true
              break
            end
          end
          if not boss_present then
            dmg = tonumber(s.boss_encounter_hp or 0) or 0
          end
        end

      else
        -- No enemy snapshot at all.
        if ran then
          -- Dev ESC run: treat as no damage.
          dmg = 0
        else
          -- Non-run fallbacks (as before).
          local php = tonumber(stats and (stats.health or stats.player_hp or stats.hp) or 0) or 0
          if php > 0 and (s.boss_encounter_hp or 0) > 0 then
            dmg = s.boss_encounter_hp
          else
            dmg = _boss_damage_from_stats(stats, s.boss_win_damage)
          end
        end
      end

      if dmg > 0 then
        local secret = _safe_secret(pid)
        local pname  = Net.get_player_name(pid)
        local c = s.contributions[secret] or { points=0, wins=0, boss_dmg=0 }
        c.boss_dmg    = (c.boss_dmg or 0) + dmg
        c._pend_bdmg  = (c._pend_bdmg or 0) + dmg
        c.name        = pname or c.name
        c._last_pid   = pid
        s.contributions[secret] = c
        s.boss_pool_hp = math.max(0, (s.boss_pool_hp or 0) - dmg)
      end

      local msg = ("Boss HP: %d/%d"):format(s.boss_pool_hp or 0, s.boss_pool_max or 0)
      if s.boss_pool_hp <= 0 then
        -- Boss defeated → pay all contributors (offline-safe), then start cooldown if Repeat
        if TeamsOK and Teams then
          for secret2, cc in pairs(s.contributions or {}) do
            local pend = tonumber(cc._pend_bdmg or 0) or 0
            if pend > 0 then
              if Teams.on_raid_contribution_secret then
                pcall(Teams.on_raid_contribution_secret, secret2, raid_id, "boss", pend, cc._last_pid)
              elseif cc._last_pid and Teams.on_raid_contribution then
                pcall(Teams.on_raid_contribution, cc._last_pid, raid_id, "boss", pend)
              end
            end
            cc._pend_bdmg = 0
          end
        end

        s.defeated   = true
        s.defeated_at= _now()
        if s.style == "Repeat" then
          local cd = tonumber(s.repeat_cooldown_secs or 1800); if not cd or cd <= 0 then cd = 1800 end
          s.cooldown_until = _now() + cd
        end
        ezmemory.save_area_memory(mem_area)
        if Config.on_boss_defeated then pcall(Config.on_boss_defeated, pid, raid_id, s) end
        await(Async.message_player(pid, "Boss defeated!"))
        ezmemory.save_area_memory(mem_area)
      else
        ezmemory.save_area_memory(mem_area)
        await(Async.message_player(pid, (dmg > 0) and (("-"..dmg.." - "..msg)) or msg))
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

if not _G.__RAIDS_LOGIN_ANNOUNCE then
  _G.__RAIDS_LOGIN_ANNOUNCE = true
  Net:on("player_join", function(ev)
    local pid = ev.player_id

    -- Decide which area to read state from
    local area_for_state = LOGIN_ANNOUNCE_MEM_AREA or RAID_MEM_AREA or Net.get_player_area(pid)
    print(("[RAIDS] login check pid=%s area_for_state=%s"):format(pid, tostring(area_for_state)))

    -- If you enabled the local test marquee, show it here (optional)
    if TEST_LOGIN_MARQUEE then
      local ok, err = pcall(_marquee, pid, TEST_LOGIN_TEXT, TEST_LOGIN_OPTS)
      if not ok then print(("[RAIDS] login test marquee error pid=%s: %s"):format(pid, tostring(err))) end
    end

    -- Choose which raid to show
    local rid, s
    if LOGIN_ANNOUNCE_RAID_ID and LOGIN_ANNOUNCE_RAID_ID ~= "" then
      rid = tostring(LOGIN_ANNOUNCE_RAID_ID)
      s   = _peek_store(area_for_state)[rid]  -- <-- DO NOT create new state
      if not s then
        print(("[RAIDS] login check: pinned rid=%s not found in area=%s"):format(rid, tostring(area_for_state)))
        return
      end
      if not _is_active(s) then
        print(("[RAIDS] login check: pinned rid=%s exists but not active (w1=%s w2=%s wave=%s)")
              :format(rid, tostring(s.wave1_points), tostring(s.wave2_points), tostring(s.wave)))
        return
      end
    else
      -- Fallback to auto-detect (find active raid or most-progressed)
      rid, s = _find_active_or_progress(area_for_state)
      if not s or not _is_active(s) then
        print("[RAIDS] login check: no active raid in state (rid="..tostring(rid)..")")
        return
      end
    end

    -- Build the status string from the selected state
    local msg
    if s.wave == 1 then
      msg = string.format("RAID IN PROGRESS - %s - W1 %d/%d", rid, s.wave1_points or 0, s.wave2_points_required or 0)
    elseif s.wave == 2 then
      msg = string.format("RAID IN PROGRESS - %s - W2 %d/%d", rid, s.wave2_points or 0, s.wave3_points_required or 0)
    else
      msg = string.format("RAID IN PROGRESS - %s - Boss %d/%d", rid, s.boss_pool_hp or 0, s.boss_pool_max or 0)
    end

    local ok, err = pcall(_marquee, pid, msg, { loops = 2 })
    if not ok then print(("[RAIDS] login marquee error pid=%s: %s"):format(pid, tostring(err))) end
  end)
end

return Raids
