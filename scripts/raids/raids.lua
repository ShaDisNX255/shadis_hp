local eznpcs       = require('scripts/ezlibs-scripts/eznpcs/eznpcs')
local ezencounters = require('scripts/ezlibs-scripts/ezencounters/main')
local ezmemory     = require('scripts/ezlibs-scripts/ezmemory')
local helpers      = require('scripts/ezlibs-scripts/helpers')

local Config       = require('scripts/raids/config')
local Enc          = require('scripts/raids/encounters')

local TeamsOK, Teams = pcall(require, 'scripts/teams/teams')
local JobBBSOK, JobBBS = pcall(require, 'scripts/jobbbs/JobBBS')
-- ===== Displayer bootstrap via Net-Games =====
local Displayer = _G.Displayer  -- reuse if some other script already set it

if not Displayer then
  local ok, D = pcall(require, 'scripts/net-games/displayer/displayer')
  if ok and type(D) == 'table' then
    -- Initialize the Net-Games Displayer once
    if D.init then
      local ok_init, err = pcall(D.init, D)
      if not ok_init then
        print("[RAIDS] Net-Games Displayer.init failed:", tostring(err))
      end
    end
    Displayer       = D
    _G.Displayer    = D   -- keep the global name for compatibility
  else
    print("[RAIDS] Failed to require scripts/net-games/displayer; raid marquee disabled")
  end
end

_G.__DISPLAYER_READY =
  (Displayer and Displayer.Text and Displayer.Text.drawMarqueeText) or false
print("[RAIDS] Displayer (Net-Games) init:",
      _G.__DISPLAYER_READY and "OK" or "FAILED")
-- ===== /Displayer bootstrap =====

-- ===== Login test marquee (local toggle) =====
local TEST_LOGIN_MARQUEE = false   -- set true to show a test marquee on login
local TEST_LOGIN_TEXT    = "Login test marquee - tweak in raids.lua"
local TEST_LOGIN_OPTS = {
  loops = 2,
  id    = "__raid_login_test",  -- unique id so it doesn't overwrite others
}
-- ===== /Login test marquee =====

-- Force the login marquee to read a specific Raid ID / Area
-- Set to nil to auto-detect like before.
local LOGIN_ANNOUNCE_RAID_ID   = nil          -- nil = let code auto-pick a raid
local LOGIN_ANNOUNCE_MEM_AREA  = nil          -- e.g. "WCity1"; nil = default / player's area

-- Limit which raids are allowed to show on the login announcer.
-- Any raid_id not in this table is ignored by the auto-detect logic.
local LOGIN_ANNOUNCE_ALLOWED_RAIDS = nil

-- Peek current raid store for an area without creating anything
local function _peek_store(area_id)
  local mem = ezmemory.get_area_memory(area_id)
  return (mem and mem.raids) or {}
end

-- true if a raid is “active” (has actually started)
local function _is_active(s)
  if not s then return false end

  -- Timed raids are considered active as soon as they spawn, even before
  -- anyone has earned the first point.
  if type(s.timed) == "table" and s.timed.enabled == true then
    return s.timed.phase == "available" or s.timed.phase == "active"
  end

  -- If the raid has been flagged as defeated, it's no longer active
  if s.defeated then
    return false
  end

  -- If there is a boss pool and it's at 0, also treat as not active
  local boss_max = tonumber(s.boss_pool_max or 0) or 0
  local boss_hp  = tonumber(s.boss_pool_hp or boss_max) or 0
  if boss_max > 0 and boss_hp <= 0 then
    return false
  end

  -- Active as soon as wave1 has any points, wave advanced, or boss HP moved.
  return (tonumber(s.wave1_points or 0) > 0)
      or (tonumber(s.wave or 1) > 1)
      or (boss_hp < boss_max)
end

-- true if this raid_id is allowed to be shown on the login announcer
local function _is_allowed_for_login(rid)
  if not LOGIN_ANNOUNCE_ALLOWED_RAIDS then return true end
  if not next(LOGIN_ANNOUNCE_ALLOWED_RAIDS) then return true end
  return LOGIN_ANNOUNCE_ALLOWED_RAIDS[rid] == true
end

-- Find any active raid in area (prefer truly active; else most progressed)
local function _find_active_or_progress(area_id)
  local store = _peek_store(area_id)
  local best_id, best_s, best_score = nil, nil, -1

  for rid, s in pairs(store) do
    -- skip raids that are not allowed for login announcements
    if _is_allowed_for_login(rid) then
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
  end

  return best_id, best_s  -- may be nil/nil if no allowed raids exist yet
end

-- ==== Online tracking (global, area-agnostic) ====
local ONLINE = {}  -- [pid] = true
_G.RAIDS_ONLINE = ONLINE  -- expose for other scripts (e.g., LMenu)

-- Keep ONLINE in sync (cover both common event names)
if not _G.__RAIDS_ONLINE_WIRED then
  _G.__RAIDS_ONLINE_WIRED = true

  local function refresh_lmenu_online()
    local LM = rawget(_G, "LMenu")
    if LM and LM.refresh_online_for_all then
      pcall(LM.refresh_online_for_all)
    end
  end

  Net:on("player_join", function(ev)
    ONLINE[ev.player_id] = true
    refresh_lmenu_online()
  end)

  Net:on("player_disconnect", function(ev)
    ONLINE[ev.player_id] = nil
    refresh_lmenu_online()
  end)

  Net:on("player_left", function(ev)   -- some builds use a different name
    ONLINE[ev.player_id] = nil
    refresh_lmenu_online()
  end)
end
-- ==== /Online tracking ====

local PRIMARY_RAID_ID = (Config and Config.get_primary_raid_id and Config.get_primary_raid_id()) or nil
local PRIMARY_RAID_CFG = (PRIMARY_RAID_ID and Config and Config.get_raid and Config.get_raid(PRIMARY_RAID_ID)) or nil
local RAID_MEM_AREA = PRIMARY_RAID_CFG and (PRIMARY_RAID_CFG.memory_area or PRIMARY_RAID_CFG.area_id) or nil

local Raids = {}

-- =========================
-- ===== Timed raids ========
-- =========================

local TIMED_RAIDS = {} -- [physical_area .. "|" .. raid_id] = runtime config
local TIMED_VISIBILITY_CACHE = {} -- [pid][timed_key] = visibility signature

local TIMED_STATE_VERSION = 3
local TIMED_SPAWN_CATCHUP_SECONDS = 120

print("[RAIDS TIMED] unified config build 2026-07-11-v5 loaded")

-- Timed raid NPCs use eznpcs DeferredNPC placeholders. Hidden raids have
-- no bot at all; visible raids explicitly create one.
local function _timed_key(area_id, raid_id)
  return tostring(area_id or "") .. "|" .. tostring(raid_id or PRIMARY_RAID_ID)
end

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

-- Keep track of areas that have raid state so we can scan them on login
local RAID_MEM_AREAS = {}

local function _safe_area_mem(area_id)
  local mem = ezmemory.get_area_memory(area_id)
  if not mem then mem = {} end
  mem.raids = mem.raids or {}

  -- remember this area so offline payouts can find it later
  RAID_MEM_AREAS[area_id] = true

  return mem, mem.raids
end

local function _safe_secret(pid)
  return helpers.get_safe_player_secret and helpers.get_safe_player_secret(pid) or tostring(pid)
end

local function _trim(value)
  local s = tostring(value or "")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function _is_true(value)
  if value == true then return true end
  if type(value) == "number" then return value ~= 0 end
  if type(value) == "string" then
    value = value:lower()
    return value == "true" or value == "1" or value == "yes" or value == "on"
  end
  return false
end


local function _positive_int(value, fallback, minimum, maximum)
  local n = math.floor(tonumber(value) or tonumber(fallback) or 0)
  if minimum and n < minimum then n = minimum end
  if maximum and n > maximum then n = maximum end
  return n
end

local function _object_id(value)
  if value == nil or value == "" then return nil end
  local n = tonumber(value)
  return n and tostring(math.floor(n)) or tostring(value)
end

local function _day_key(now)
  return os.date("%Y-%m-%d", now or _now())
end

local function _day_bounds(now)
  local dt = os.date("*t", now or _now())
  local start_time = os.time({
    year = dt.year, month = dt.month, day = dt.day,
    hour = 0, min = 0, sec = 0,
  })
  local next_time = os.time({
    year = dt.year, month = dt.month, day = dt.day + 1,
    hour = 0, min = 0, sec = 0,
  })
  return start_time, next_time
end

local function _stable_hash(text_value)
  local h = 5381
  local s = tostring(text_value or "")
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 2147483647
  end
  return h
end

local function _format_minutes(seconds)
  return math.max(0, math.ceil((tonumber(seconds) or 0) / 60))
end

local function _result_flags(stats)
  local reason = tonumber(stats and stats.reason or 0) or 0
  local hp = tonumber(stats and (stats.health or stats.player_hp or stats.hp) or 0) or 0

  local ran, dev_escape, won, lost = false, false, false, false

  if reason == 1 then        -- 1 = battle won
    won = true
  elseif reason == 2 then    -- 2 = battle lost
    lost = true
  elseif reason == 3 then    -- 3 = ran (L button)
    ran = true
  elseif reason == 4 then    -- 4 = ran (ESC / dev escape)
    ran = true
    dev_escape = true
  else
    -- Backwards compatibility for older ONB builds
    ran = stats and (stats.ran or stats.fled or stats.escape) or false
    if not ran then
      if hp > 0 then
        won = true
      elseif hp <= 0 then
        lost = true
      end
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
  local f = _result_flags(stats)
  if (not f.ran) and f.hp > 0 and fallback_on_win then
    return math.floor(fallback_on_win)
  end
  return 0
end

local function _persist_health_and_emotion(pid, encounter_info, stats)
  if not stats then return end

    Net.set_player_emotion(pid, 0)

  if stats.health then
    ezmemory.set_player_health(pid, stats.health)
  end
end

-- Right-side marquee look (tweak as you like)
local UI = {
  scale        = 1.2,
  z            = 220,
  speed        = "slow",   -- slow | medium | quick
  width        = 220,
  height       = 38,
  padding_x    = 6,
  padding_y    = 4,
  margin_right = -100,          -- distance from the right edge
  y            = 6,          -- top Y of the box
  loops        = 2,          -- exactly two passes, as requested
  font         = "THICK",
  backdrop_scale = 1.0,
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
  local scale        = opts.scale or UI.scale
  local width        = opts.width or UI.width
  local height       = opts.height or UI.height
  local padding_x    = opts.padding_x or UI.padding_x
  local padding_y    = opts.padding_y or UI.padding_y
  local margin_right = opts.margin_right or UI.margin_right
  local y            = opts.y or UI.y
  local z            = opts.z or UI.z
  local speed        = opts.speed or UI.speed
  local loops        = (opts.loops ~= nil) and opts.loops or UI.loops
  local font         = opts.font or UI.font
  local backdrop_scale = opts.backdrop_scale or UI.backdrop_scale or 1.0

  -- NEW: allow each marquee to have its own text id so they don't clobber each other
  local id = opts.id or "__raid_announce"

  local line_h   = math.ceil(9 * scale)  -- THICK baseline ~9px
  local x        = _screen_w() - margin_right - width
  local baseline = y + padding_y + line_h - 2

  D.Text.drawMarqueeText(
    pid,
    id,
    tostring(text or ""),
    baseline,
    font, scale,
    z,
    speed,
    {
      x = x, y = y, width = width, height = height,
      padding_x = padding_x, padding_y = padding_y,
      loops = loops, scale = backdrop_scale,
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

local function _ensure_claims(s)
  s.claims = s.claims or {}
  s.claims.wave1 = s.claims.wave1 or {}
  s.claims.wave2 = s.claims.wave2 or {}
  s.claims.boss  = s.claims.boss  or {}
end

-- =========================
-- ===== Money rewards =====
-- =========================

-- Record money to pay for each eligible contributor on a given wave.
local function _queue_money_claims_for_wave(area_id, raid_id, s, wave_key)
  _ensure_claims(s)

  local field
  if wave_key == "wave1" or wave_key == "w1" then
    field   = "money_wave1"
    wave_key = "wave1"
  elseif wave_key == "wave2" or wave_key == "w2" then
    field   = "money_wave2"
    wave_key = "wave2"
  elseif wave_key == "boss" then
    field   = "money_boss"
    wave_key = "boss"
  else
    return
  end

  local per = tonumber(s[field] or 0) or 0
  if per <= 0 then return end

  for secret, c in pairs(s.contributions or {}) do
    local eligible = false
    if wave_key == "wave1" then
      eligible = (tonumber(c.w1 or 0) or 0) > 0
    elseif wave_key == "wave2" then
      eligible = (tonumber(c.w2 or 0) or 0) > 0
    elseif wave_key == "boss" then
      eligible = (tonumber(c.boss_dmg or 0) or 0) > 0
    end

    if eligible then
      local prev = tonumber(s.claims[wave_key][secret] or 0) or 0
      s.claims[wave_key][secret] = prev + per
      print(("[RAIDS MONEY] Queued +%d z (total=%d) for secret=%s (raid=%s, wave=%s)")
        :format(per, prev + per, tostring(secret), tostring(raid_id), tostring(wave_key)))
    end
  end

  if ezmemory and ezmemory.save_area_memory then
    ezmemory.save_area_memory(area_id)
  end
end

-- Pay and clear all pending money claims for this secret in this raid.
local function _pay_pending_claims_for_pid(pid, area_id, raid_id, s)
  if not Net or not Net.is_player or not Net.is_player(pid) then return end
  -- IMPORTANT: ezmemory is the source of truth for money (it pushes pm.money into Net on login).
  -- So we must update ezmemory, not just Net, or payouts will be lost on relog.
  if ezmemory and ezmemory.set_player_money and ezmemory.get_player_memory then
    -- ok
  elseif not (Net.get_player_money and Net.set_player_money) then
    return
  end

  local secret = _safe_secret(pid)
  local claims = s.claims or {}
  claims.wave1 = claims.wave1 or {}
  claims.wave2 = claims.wave2 or {}
  claims.boss  = claims.boss  or {}

  local a1 = tonumber(claims.wave1[secret] or 0) or 0
  local a2 = tonumber(claims.wave2[secret] or 0) or 0
  local a3 = tonumber(claims.boss[secret]  or 0) or 0
  local total = a1 + a2 + a3

  if total <= 0 then return end

  -- clear claims now that we're about to pay them
  claims.wave1[secret] = nil
  claims.wave2[secret] = nil
  claims.boss[secret]  = nil

  local current
  if ezmemory and ezmemory.get_player_memory then
    local safe_secret = helpers.get_safe_player_secret(pid)
    local pm = ezmemory.get_player_memory(safe_secret)
    current = tonumber(pm and pm.money or 0) or 0
  else
    current = tonumber(Net.get_player_money(pid) or 0) or 0
  end

  local new_balance = current + total
  if ezmemory and ezmemory.set_player_money then
    ezmemory.set_player_money(pid, new_balance)
  else
    Net.set_player_money(pid, new_balance)
  end

  local name = Net.get_player_name and Net.get_player_name(pid) or tostring(pid)
  print(("[RAIDS MONEY] Paid %d z to %s (raid=%s, area=%s, secret=%s)")
    :format(total, tostring(name), tostring(raid_id), tostring(area_id), tostring(secret)))

  -- Build a nice player-facing message with per-wave breakdown
  local parts = {}
  if a1 > 0 then parts[#parts+1] = ("Wave 1: %d z"):format(a1) end
  if a2 > 0 then parts[#parts+1] = ("Wave 2: %d z"):format(a2) end
  if a3 > 0 then parts[#parts+1] = ("Boss: %d z"):format(a3) end

  local msg
  if #parts > 0 then
    msg = ("Raid rewards received: +%d z (%s)"):format(total, table.concat(parts, ", "))
  else
    msg = ("Raid rewards received: +%d z"):format(total)
  end

  if Net.message_player then
    Net.message_player(pid, msg)
  end

  if ezmemory and ezmemory.save_area_memory then
    ezmemory.save_area_memory(area_id)
  end
end

local function _pay_pending_claims_for_connected(area_id, raid_id, s)
  local pids = _all_pids(nil) -- global connected list (uses ONLINE + fallbacks)
  for _, pid in ipairs(pids) do
    _pay_pending_claims_for_pid(pid, area_id, raid_id, s)
  end
end

-- Pay any pending claims for this player across all raid states (login-time).
local function _pay_all_claims_for_pid(pid)
  if not Net or not Net.is_player or not Net.is_player(pid) then return end
  local secret = _safe_secret(pid)

  for area_id, _ in pairs(RAID_MEM_AREAS) do
    local mem, store = _safe_area_mem(area_id)
    for raid_id, s in pairs(store or {}) do
      local claims = s.claims
      if claims and (
        (claims.wave1 and claims.wave1[secret]) or
        (claims.wave2 and claims.wave2[secret]) or
        (claims.boss  and claims.boss[secret])
      ) then
        -- This will print a debug message when it actually pays
        _pay_pending_claims_for_pid(pid, area_id, raid_id, s)
      end
    end
  end
end

-- =========================
-- ===== State =========
-- =========================

local function _copy_raid_config(raid_id)
  if not (Config and Config.get_raid) then
    error("scripts/raids/config.lua does not expose Config.get_raid")
  end

  local src_cfg = Config.get_raid(raid_id)
  if type(src_cfg) ~= "table" then
    error("Unknown raid id in scripts/raids/config.lua: " .. tostring(raid_id))
  end

  local cfg = {}
  for k, v in pairs(src_cfg) do cfg[k] = v end
  return cfg
end

local function _apply_state_config(s, raid_id)
  local cfg = _copy_raid_config(raid_id)

  local old_boss_max = tonumber(s.boss_pool_max or 0) or 0
  local new_boss_max = tonumber(cfg.boss_pool_max or 10000) or 10000

  s.raid_id               = raid_id
  s.style                 = cfg.style or "Repeat"
  s.wave2_points_required = tonumber(cfg.wave2_points_required or 50) or 50
  s.wave3_points_required = tonumber(cfg.wave3_points_required or 35) or 35
  s.boss_pool_max         = new_boss_max
  s.boss_win_damage       = tonumber(cfg.boss_win_damage or 500) or 500
  s.boss_encounter_hp     = tonumber(cfg.boss_encounter_hp or 0) or 0
  s.boss_id_match         = tostring(cfg.boss_id_match or "")
  s.repeat_cooldown_secs  = tonumber(cfg.repeat_cooldown_secs or 1800) or 1800
  s.money_wave1           = tonumber(cfg.money_wave1 or 0) or 0
  s.money_wave2           = tonumber(cfg.money_wave2 or 0) or 0
  s.money_boss            = tonumber(cfg.money_boss or 0) or 0

  -- Config edits apply after restart without healing an already damaged boss.
  if s.boss_pool_hp == nil or old_boss_max <= 0 then
    s.boss_pool_hp = new_boss_max
  elseif tonumber(s.boss_pool_hp) == old_boss_max and old_boss_max ~= new_boss_max then
    s.boss_pool_hp = new_boss_max
  end
end

local function _ensure_state(area_id, raid_id)
  local mem, store = _safe_area_mem(area_id)
  local s = store[raid_id]
  local created = false

  if not s then
    created = true
    s = {
      raid_id       = raid_id,
      wave          = 1,
      wave1_points  = 0,
      wave2_points  = 0,
      defeated      = false,
      defeated_at   = nil,
      contributions = {},
      claims         = { wave1 = {}, wave2 = {}, boss = {} },
      cooldown_until = nil,
    }
    store[raid_id] = s
  end

  s.wave = tonumber(s.wave or 1) or 1
  s.wave1_points = tonumber(s.wave1_points or 0) or 0
  s.wave2_points = tonumber(s.wave2_points or 0) or 0
  s.contributions = s.contributions or {}
  _ensure_claims(s)
  _apply_state_config(s, raid_id)

  if created then
    ezmemory.save_area_memory(area_id)
  end

  return s, mem, store
end

local function _reset_progress(s)
  -- Keep pending claims. They may belong to offline players and must survive
  -- repeat/timed resets until those players log in and receive payment.
  _ensure_claims(s)
  s.wave = 1
  s.wave1_points = 0
  s.wave2_points = 0
  s.boss_pool_hp = tonumber(s.boss_pool_max or 0) or 0
  s.defeated = false
  s.defeated_at = nil
  s.cooldown_until = nil
  s.contributions = {}
end

local function _maybe_advance_wave(s)
  -- Lock wave 1 once it's cleared; lock wave 2 once it's cleared.
  if s.wave < 2 and s.wave1_points >= s.wave2_points_required then s.wave = 2 end
  if s.wave < 3 and s.wave2_points >= s.wave3_points_required then s.wave = 3 end
end

local function _try_reset_if_repeat(s)
  if s.style == "Repeat" and s.defeated then
    _reset_progress(s)
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
  local s = _ensure_state(area_id, raid_id or PRIMARY_RAID_ID)
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
  local s = _ensure_state(area_id, raid_id or PRIMARY_RAID_ID)
  damage = math.max(0, math.floor(tonumber(damage) or 0))
  if damage <= 0 then return end
  local secret = _safe_secret(pid)
  local c = s.contributions[secret] or { points=0, wins=0, boss_dmg=0 }
  c.boss_dmg = (c.boss_dmg or 0) + damage
  s.contributions[secret] = c
  s.boss_pool_hp = math.max(0, (s.boss_pool_hp or 0) - damage)
end

-- =========================
-- ===== Timed lifecycle ====
-- =========================

local function _timed_visible(s)
  local t = s and s.timed
  if type(t) ~= "table" or t.enabled ~= true then return true end
  return t.phase == "available" or t.phase == "active" or t.phase == "results"
end

local function _make_daily_schedule(cfg, now)
  local count = _positive_int(cfg.spawns_per_day, 4, 1, 24)
  local day_start, next_day = _day_bounds(now)
  local day_length = math.max(1, next_day - day_start)
  local times = {}
  local key = _day_key(now)

  for i = 1, count do
    local window_start = day_start + math.floor(day_length * (i - 1) / count)
    local window_end = day_start + math.floor(day_length * i / count)
    local span = math.max(1, window_end - window_start)
    local margin = (span > 1200) and 300 or math.floor(span * 0.10)
    local usable = math.max(1, span - (margin * 2))
    local hash = _stable_hash(tostring(i) .. "|" .. tostring(cfg.key) .. "|" .. key)
    times[i] = window_start + margin + (hash % usable)
  end

  return times
end

local function _print_schedule(cfg, times)
  local out = {}
  for i, ts in ipairs(times or {}) do
    out[#out + 1] = os.date("%H:%M", ts)
  end
  print(("[RAIDS TIMED] %s daily schedule: %s")
    :format(tostring(cfg.key), table.concat(out, ", ")))
end

local function _start_timed_day(cfg, s, now)
  local t = s.timed or {}
  s.timed = t

  t.version = TIMED_STATE_VERSION
  t.enabled = true
  t.day_key = _day_key(now)
  t.phase = "hidden"
  t.used_spawns = {}

  if cfg.test_mode then
    t.spawn_times = {}
    t.schedule_count = 0
    cfg._test_next_spawn_at = now + cfg.test_spawn_interval_seconds
    print(("[RAIDS TIMED] TEST schedule %s every %d min; next=%s")
      :format(cfg.key, math.floor(cfg.test_spawn_interval_seconds / 60),
        os.date("%H:%M:%S", cfg._test_next_spawn_at)))
  else
    t.spawn_times = _make_daily_schedule(cfg, now)
    t.schedule_count = cfg.spawns_per_day
    _print_schedule(cfg, t.spawn_times)
  end

  t.defeats_today = 0
  t.losses_today = 0
  t.spawned_at = nil
  t.engaged_at = nil
  t.deadline = nil
  t.results_until = nil
  t.current_spawn_index = nil
  t.run_id = math.floor(tonumber(t.run_id or 0) or 0) + 1

  _reset_progress(s)
end

local function _ensure_timed_state(cfg, s, now)
  now = now or _now()
  local changed = false

  if type(s.timed) ~= "table" or s.timed.version ~= TIMED_STATE_VERSION then
    s.timed = {
      version = TIMED_STATE_VERSION,
      enabled = true,
      phase = "hidden",
      run_id = 0,
    }
    _start_timed_day(cfg, s, now)
    changed = true
  end

  local t = s.timed
  t.enabled = true
  t.phase = t.phase or "hidden"
  t.run_id = math.floor(tonumber(t.run_id or 0) or 0)
  t.defeats_today = math.floor(tonumber(t.defeats_today or 0) or 0)
  t.losses_today = math.floor(tonumber(t.losses_today or 0) or 0)
  t.used_spawns = t.used_spawns or {}

  -- Store current tunables in memory for inspection/debugging. Runtime logic still
  -- reads cfg, so config edits take effect without deleting the raid state.
  t.spawns_per_day = cfg.spawns_per_day
  t.defeats_per_day = cfg.defeats_per_day
  t.spawn_seconds = cfg.spawn_seconds
  t.active_seconds = cfg.active_seconds
  t.results_seconds = cfg.results_seconds
  t.test_mode = cfg.test_mode == true
  t.test_spawn_interval_seconds = cfg.test_spawn_interval_seconds

  local today = _day_key(now)
  if (not t.day_key) or (t.day_key ~= today and t.phase == "hidden") then
    _start_timed_day(cfg, s, now)
    changed = true
  elseif (not cfg.test_mode) and t.day_key == today and (
      type(t.spawn_times) ~= "table" or
      t.schedule_count ~= cfg.spawns_per_day
    ) and t.phase == "hidden" then
    t.spawn_times = _make_daily_schedule(cfg, now)
    t.schedule_count = cfg.spawns_per_day
    t.used_spawns = {}
    _print_schedule(cfg, t.spawn_times)
    changed = true
  end

  return t, changed
end


local function _resolve_timed_bot_id(cfg)
  if not (cfg and cfg.npc_object_id and eznpcs and eznpcs.get_bot_id_for_placeholder) then
    return nil
  end

  local ok, bot_id = pcall(
    eznpcs.get_bot_id_for_placeholder,
    cfg.area_id,
    cfg.npc_object_id
  )

  if ok then return bot_id end
  return nil
end


local function _set_timed_board_global_visibility(cfg, visible, force)
  if not (cfg and cfg.bbs_object_id and Net.set_object_visibility) then
    return
  end

  local signature = visible and "visible" or "hidden"
  if not force and cfg._board_visibility_signature == signature then
    return
  end

  local object_id = tonumber(cfg.bbs_object_id) or cfg.bbs_object_id
  local ok, err = pcall(
    Net.set_object_visibility,
    cfg.area_id,
    object_id,
    visible == true
  )

  if ok then
    cfg._board_visibility_signature = signature
  else
    print(("[RAIDS TIMED] Failed to set BBS visibility key=%s visible=%s err=%s")
      :format(tostring(cfg.key), tostring(visible), tostring(err)))
  end
end

local function _set_timed_bot_global_presence(cfg, visible, force)
  if not cfg then return nil end

  local object_id = tonumber(cfg.npc_object_id) or cfg.npc_object_id

  if visible then
    local existing_bot_id = _resolve_timed_bot_id(cfg)
    local signature = existing_bot_id and ("visible:" .. tostring(existing_bot_id)) or nil

    if not force and signature and cfg._bot_presence_signature == signature then
      return existing_bot_id
    end

    if not (eznpcs and eznpcs.spawn_deferred_npc) then
      print(("[RAIDS TIMED] eznpcs.spawn_deferred_npc unavailable for %s")
        :format(tostring(cfg.key)))
      return nil
    end

    local ok_spawn, bot_id = pcall(
      eznpcs.spawn_deferred_npc,
      cfg.area_id,
      object_id
    )

    if not ok_spawn or not bot_id then
      print(("[RAIDS TIMED] Failed to spawn deferred NPC key=%s object=%s err=%s")
        :format(tostring(cfg.key), tostring(cfg.npc_object_id),
          tostring(ok_spawn and "no bot returned" or bot_id)))
      cfg._bot_presence_signature = nil
      return nil
    end

    cfg._last_bot_id = bot_id
    cfg._bot_presence_signature = "visible:" .. tostring(bot_id)
    print(("[RAIDS TIMED] NPC spawned key=%s bot=%s")
      :format(tostring(cfg.key), tostring(bot_id)))
    return bot_id
  end

  local existing_bot_id = _resolve_timed_bot_id(cfg)
  if not force and not existing_bot_id and cfg._bot_presence_signature == "hidden" then
    return nil
  end

  if not (eznpcs and eznpcs.despawn_deferred_npc) then
    print(("[RAIDS TIMED] eznpcs.despawn_deferred_npc unavailable for %s")
      :format(tostring(cfg.key)))
    return existing_bot_id
  end

  local ok_remove, removed = pcall(
    eznpcs.despawn_deferred_npc,
    cfg.area_id,
    object_id
  )

  if not ok_remove then
    print(("[RAIDS TIMED] Failed to despawn deferred NPC key=%s object=%s err=%s")
      :format(tostring(cfg.key), tostring(cfg.npc_object_id), tostring(removed)))
    return existing_bot_id
  end

  cfg._last_bot_id = nil
  cfg._bot_presence_signature = "hidden"

  if removed or existing_bot_id then
    print(("[RAIDS TIMED] NPC despawned key=%s bot=%s")
      :format(tostring(cfg.key), tostring(existing_bot_id)))
  end

  return nil
end

local function _set_timed_visibility_for_player(pid, cfg, s, force)
  if not (pid and cfg and s) then return end

  local ok_area, player_area = pcall(Net.get_player_area, pid)
  if not ok_area or tostring(player_area or "") ~= tostring(cfg.area_id or "") then
    return
  end

  local visible = _timed_visible(s)
  local bot_id = _resolve_timed_bot_id(cfg)

  TIMED_VISIBILITY_CACHE[pid] = TIMED_VISIBILITY_CACHE[pid] or {}
  local signature = table.concat({
    visible and "1" or "0",
    tostring(bot_id or ""),
    tostring(cfg.bbs_object_id or ""),
  }, ":")

  if not force and TIMED_VISIBILITY_CACHE[pid][cfg.key] == signature then
    return
  end

  -- Keep per-player visibility in addition to the global BBS visibility. This
  -- prevents stale client state when somebody enters the area after a phase change.
  if cfg.bbs_object_id then
    local object_id = tonumber(cfg.bbs_object_id) or cfg.bbs_object_id
    if visible and Net.include_object_for_player then
      pcall(Net.include_object_for_player, pid, object_id)
    elseif (not visible) and Net.exclude_object_for_player then
      pcall(Net.exclude_object_for_player, pid, object_id)
    end
  end

  if bot_id then
    if visible and Net.include_actor_for_player then
      pcall(Net.include_actor_for_player, pid, bot_id)
    elseif (not visible) and Net.exclude_actor_for_player then
      pcall(Net.exclude_actor_for_player, pid, bot_id)
    end
  end

  TIMED_VISIBILITY_CACHE[pid][cfg.key] = signature
end

local function _sync_timed_visibility(cfg, s, force)
  local visible = _timed_visible(s)

  -- These two operations are global and must happen even when nobody is
  -- currently standing in the raid area.
  _set_timed_board_global_visibility(cfg, visible, force)
  _set_timed_bot_global_presence(cfg, visible, force)

  for _, pid in ipairs(_all_pids(cfg.area_id)) do
    _set_timed_visibility_for_player(pid, cfg, s, force)
  end
end

local function _sync_player_timed_visibility(pid, force)
  TIMED_VISIBILITY_CACHE[pid] = TIMED_VISIBILITY_CACHE[pid] or {}
  for _, cfg in pairs(TIMED_RAIDS) do
    local s = _ensure_state(cfg.mem_area, cfg.raid_id)

    -- Retry global presence here in case the DeferredNPC registry completed
    -- after raids.lua first registered the config entry.
    _set_timed_board_global_visibility(cfg, _timed_visible(s), force)
    _set_timed_bot_global_presence(cfg, _timed_visible(s), force)
    _set_timed_visibility_for_player(pid, cfg, s, force)
  end
end

local function _timed_cfg_for_dialogue(area_id, dialogue_id)
  area_id = tostring(area_id or "")
  dialogue_id = _object_id(dialogue_id)

  for _, cfg in pairs(TIMED_RAIDS) do
    if tostring(cfg.area_id) == area_id
      and _object_id(cfg.dialogue_id) == dialogue_id
    then
      return cfg
    end
  end

  return nil
end

local function _timed_cfg_for_bbs(area_id, bbs_object_id)
  area_id = tostring(area_id or "")
  bbs_object_id = _object_id(bbs_object_id)

  for _, cfg in pairs(TIMED_RAIDS) do
    if tostring(cfg.area_id) == area_id
      and _object_id(cfg.bbs_object_id) == bbs_object_id
    then
      return cfg
    end
  end

  return nil
end

-- Register one complete raid definition from scripts/raids/config.lua.
-- There is no Tiled discovery fallback: config.lua is the only source of
-- scheduling, progression, placement IDs, and rewards.
local function _register_configured_raid(raid_id, source)
  if type(source) ~= "table" or source.enabled == false then
    return nil
  end

  raid_id = tostring(raid_id or "")
  local area_id = _trim(source.area_id)

  if raid_id == "" then
    print("[RAIDS TIMED] Ignored config entry with an empty raid id")
    return nil
  end

  if area_id == "" then
    print(("[RAIDS TIMED] Config raid %s is missing area_id")
      :format(raid_id))
    return nil
  end

  local dialogue_id = _object_id(source.dialogue_object_id)
  local npc_object_id = _object_id(source.npc_object_id)
  local bbs_object_id = _object_id(source.bbs_object_id)

  if not dialogue_id then
    print(("[RAIDS TIMED] Config raid %s is missing dialogue_object_id")
      :format(raid_id))
    return nil
  end

  if not npc_object_id then
    print(("[RAIDS TIMED] Config raid %s is missing npc_object_id")
      :format(raid_id))
    return nil
  end

  if not bbs_object_id then
    print(("[RAIDS TIMED] Config raid %s is missing bbs_object_id")
      :format(raid_id))
    return nil
  end

  local schedule_mode = tostring(source.schedule_mode or "production"):lower()
  local test_mode = schedule_mode == "test"
  local production = type(source.production) == "table" and source.production or {}
  local test = type(source.test) == "table" and source.test or {}
  local active_schedule = test_mode and test or production

  local key = _timed_key(area_id, raid_id)
  local cfg = TIMED_RAIDS[key] or { key = key }
  local first_registration = TIMED_RAIDS[key] == nil

  cfg.key = key
  cfg.area_id = area_id
  cfg.raid_id = raid_id
  cfg.dialogue_id = dialogue_id
  cfg.npc_object_id = npc_object_id
  cfg.bbs_object_id = bbs_object_id
  cfg.mem_area = tostring(source.memory_area or area_id)
  cfg.display_name = _trim(source.display_name or raid_id)
  cfg.done_message = tostring(source.done_message or "The raid has already been cleared.")

  cfg.test_mode = test_mode
  cfg.spawns_per_day = _positive_int(production.spawns_per_day, 4, 1, 144)
  cfg.defeats_per_day = _positive_int(production.defeats_per_day, 1, 1, 144)
  cfg.test_spawn_interval_seconds =
    _positive_int(test.spawn_interval_minutes, 10, 1, 1440) * 60

  cfg.spawn_seconds =
    _positive_int(active_schedule.spawn_minutes, test_mode and 1 or 15, 1, 1440) * 60
  cfg.active_seconds =
    _positive_int(active_schedule.active_minutes, test_mode and 2 or 45, 1, 1440) * 60
  cfg.results_seconds =
    _positive_int(active_schedule.results_minutes, test_mode and 1 or 30, 1, 1440) * 60
  cfg.spawn_on_boot = _is_true(active_schedule.spawn_on_boot)

  if first_registration and cfg.spawn_on_boot then
    cfg._boot_spawn_pending = true
  end

  if first_registration or cfg._registered_test_interval ~= cfg.test_spawn_interval_seconds then
    cfg._registered_test_interval = cfg.test_spawn_interval_seconds
    cfg._test_next_spawn_at = _now() + cfg.test_spawn_interval_seconds
  end

  TIMED_RAIDS[key] = cfg
  RAID_MEM_AREAS[cfg.mem_area] = true

  local s = _ensure_state(cfg.mem_area, cfg.raid_id)
  local _, changed = _ensure_timed_state(cfg, s, _now())
  if changed then ezmemory.save_area_memory(cfg.mem_area) end
  _sync_timed_visibility(cfg, s, first_registration)

  print(("[RAIDS TIMED] Registered raid=%s area=%s dialogue=%s npc=%s bbs=%s mode=%s")
    :format(
      cfg.raid_id,
      cfg.area_id,
      tostring(cfg.dialogue_id),
      tostring(cfg.npc_object_id),
      tostring(cfg.bbs_object_id),
      cfg.test_mode and "test" or "production"
    ))

  return cfg
end

local function _register_configured_raids()
  if not (Config and Config.get_raids) then
    error("scripts/raids/config.lua does not expose Config.get_raids")
  end

  local configured = Config.get_raids() or {}
  local found = 0

  for raid_id, source in pairs(configured) do
    if _register_configured_raid(raid_id, source) then
      found = found + 1
    end
  end

  return found
end

local function _hide_and_reset_timed_raid(cfg, s, now)
  local t = s.timed
  t.phase = "hidden"
  t.spawned_at = nil
  t.engaged_at = nil
  t.deadline = nil
  t.results_until = nil
  t.current_spawn_index = nil
  t.run_id = math.floor(tonumber(t.run_id or 0) or 0) + 1
  _reset_progress(s)
  ezmemory.save_area_memory(cfg.mem_area)
  _sync_timed_visibility(cfg, s, true)
end

local function _spawn_timed_raid(cfg, s, spawn_index, now)
  local t = s.timed
  _reset_progress(s)
  t.phase = "available"
  t.spawned_at = now
  t.engaged_at = nil
  t.deadline = now + cfg.spawn_seconds
  t.results_until = nil
  t.current_spawn_index = spawn_index
  t.run_id = math.floor(tonumber(t.run_id or 0) or 0) + 1

  ezmemory.save_area_memory(cfg.mem_area)
  _sync_timed_visibility(cfg, s, true)

  _announce_all(("RAID SPAWNED - %s appeared in %s!")
    :format(cfg.display_name, cfg.area_id),
    { loops = 2 })
  print(("[RAIDS TIMED] Spawned %s slot=%s run=%s")
    :format(cfg.key, tostring(spawn_index), tostring(t.run_id)))
end

local function _engage_timed_raid(cfg, s, now)
  local t = s.timed
  now = now or _now()

  if t.phase == "active" then
    return true
  end
  if t.phase ~= "available" then
    return false, "This raid is no longer available."
  end
  if t.deadline and now >= t.deadline then
    return false, "The raid disappeared before it could be engaged."
  end

  t.phase = "active"
  t.engaged_at = now
  t.deadline = now + cfg.active_seconds
  ezmemory.save_area_memory(cfg.mem_area)
  _sync_timed_visibility(cfg, s, true)

  _announce_all(("RAID STARTED - %s - %d minutes left!")
    :format(cfg.display_name, _format_minutes(cfg.active_seconds)),
    { loops = 2 })
  print(("[RAIDS TIMED] Engaged %s run=%s")
    :format(cfg.key, tostring(t.run_id)))
  return true
end

local function _enter_timed_results(cfg, s, now)
  local t = s.timed
  t.phase = "results"
  t.defeats_today = math.floor(tonumber(t.defeats_today or 0) or 0) + 1
  t.deadline = nil
  t.results_until = now + cfg.results_seconds
  -- Invalidate all other battles that were started during this run.
  t.run_id = math.floor(tonumber(t.run_id or 0) or 0) + 1
  s.cooldown_until = nil
  _sync_timed_visibility(cfg, s, true)
end

local function _timed_battle_is_current(cfg, s, battle_run_id)
  if not (cfg and s and type(s.timed) == "table") then return true end
  local t = s.timed
  return t.enabled == true
     and t.phase == "active"
     and tonumber(t.run_id) == tonumber(battle_run_id)
     and (not t.deadline or _now() < t.deadline)
end

local function _process_timed_raid(cfg, now)
  local s = _ensure_state(cfg.mem_area, cfg.raid_id)
  local t, changed = _ensure_timed_state(cfg, s, now)

  if t.phase == "available" and t.deadline and now >= t.deadline then
    t.losses_today = math.floor(tonumber(t.losses_today or 0) or 0) + 1
    _announce_all(("RAID LOST - %s disapeared")
      :format(cfg.display_name), { loops = 2 })
    print("[RAIDS TIMED] Available timeout " .. cfg.key)
    _hide_and_reset_timed_raid(cfg, s, now)
    return
  elseif t.phase == "active" and t.deadline and now >= t.deadline then
    t.losses_today = math.floor(tonumber(t.losses_today or 0) or 0) + 1
    _announce_all(("RAID FAILED - %s was not defeated in time.")
      :format(cfg.display_name), { loops = 2 })
    print("[RAIDS TIMED] Active timeout " .. cfg.key)
    _hide_and_reset_timed_raid(cfg, s, now)
    return
  elseif t.phase == "results" and t.results_until and now >= t.results_until then
    print("[RAIDS TIMED] Results expired " .. cfg.key)
    _hide_and_reset_timed_raid(cfg, s, now)
    return
  end

  -- A raid that crosses midnight is allowed to finish its current lifecycle.
  -- Once hidden, the next tick creates the new day's schedule.
  if t.phase == "hidden" and t.day_key ~= _day_key(now) then
    _start_timed_day(cfg, s, now)
    changed = true
  end

  if cfg._boot_spawn_pending then
    cfg._boot_spawn_pending = false
    if t.phase == "hidden"
      and (cfg.test_mode or t.defeats_today < cfg.defeats_per_day)
    then
      _spawn_timed_raid(cfg, s, cfg.test_mode and "test-boot" or nil, now)
      return
    end
  end

  -- Test mode uses a fixed interval from server startup instead of the
  -- randomized daily schedule. It never creates overlapping raids: if the
  -- previous raid is still available, active, or showing results, that test
  -- slot is skipped and the next one remains ten minutes later.
  if cfg.test_mode then
    local interval = math.max(60, tonumber(cfg.test_spawn_interval_seconds) or 600)
    local next_spawn_at = tonumber(cfg._test_next_spawn_at)

    if not next_spawn_at then
      next_spawn_at = now + interval
      cfg._test_next_spawn_at = next_spawn_at
    end

    if now >= next_spawn_at then
      repeat
        next_spawn_at = next_spawn_at + interval
      until next_spawn_at > now
      cfg._test_next_spawn_at = next_spawn_at

      if t.phase == "hidden" then
        _spawn_timed_raid(cfg, s, "test", now)
        print(("[RAIDS TIMED] TEST next %s at %s")
          :format(cfg.key, os.date("%H:%M:%S", cfg._test_next_spawn_at)))
        return
      end

      print(("[RAIDS TIMED] TEST slot skipped %s phase=%s next=%s")
        :format(cfg.key, tostring(t.phase),
          os.date("%H:%M:%S", cfg._test_next_spawn_at)))
    end

    if changed then ezmemory.save_area_memory(cfg.mem_area) end
    _sync_timed_visibility(cfg, s, false)
    return
  end

  local candidate = nil
  for i, ts in ipairs(t.spawn_times or {}) do
    if not t.used_spawns[i] and now >= tonumber(ts or 0) then
      t.used_spawns[i] = true
      changed = true
      if (now - tonumber(ts or 0)) <= TIMED_SPAWN_CATCHUP_SECONDS then
        candidate = i
      end
    end
  end

  if candidate
    and t.phase == "hidden"
    and t.defeats_today < cfg.defeats_per_day
  then
    _spawn_timed_raid(cfg, s, candidate, now)
    return
  end

  if changed then ezmemory.save_area_memory(cfg.mem_area) end
  _sync_timed_visibility(cfg, s, false)
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

  if type(s.timed) == "table" and s.timed.enabled == true then
    local t = s.timed
    local status = tostring(t.phase or "hidden")
    local remaining = nil
    if t.phase == "available" or t.phase == "active" then
      remaining = t.deadline and _format_minutes(t.deadline - _now()) or nil
    elseif t.phase == "results" then
      remaining = t.results_until and _format_minutes(t.results_until - _now()) or nil
    end
    if remaining then status = status .. " - " .. tostring(remaining) .. "m" end
    posts[#posts+1] = {
      id="__raidbbs:status", read=true,
      title="Status: " .. status,
      author=""
    }
  end

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
    local object_kind = tostring(obj.class or obj.type or "")
    if object_kind == "RaidBBS" then
      local cfg = _timed_cfg_for_bbs(area_id, ev.object_id)
      if not cfg then
        Net.message_player(pid, "This RaidBBS is not configured in scripts/raids/config.lua.")
        return
      end

      local s = _ensure_state(cfg.mem_area, cfg.raid_id)
      if not _timed_visible(s) then
        Net.message_player(pid, "The raid is not currently available.")
        return
      end

      _open_raid_board(pid, cfg.mem_area, cfg.raid_id)
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
    local physical_area = Net.get_player_area(pid)
    local timed_cfg = _timed_cfg_for_dialogue(physical_area, dialogue and dialogue.id)

    if not timed_cfg then
      await(Async.message_player(
        pid,
        "This raid dialogue is not configured in scripts/raids/config.lua."
      ))
      return nil
    end

    local raid_id = timed_cfg.raid_id
    local mem_area = timed_cfg.mem_area
    local done_msg = timed_cfg.done_message
    local s, mem, store = _ensure_state(mem_area, raid_id)

    if timed_cfg then
      local t = _ensure_timed_state(timed_cfg, s, _now())
      if t.phase == "hidden" then
        await(Async.message_player(pid, "The raid is not currently available."))
        return nil
      elseif t.phase == "results" then
        local mins = t.results_until and _format_minutes(t.results_until - _now()) or 0
        await(Async.message_player(pid,
          done_msg .. ((mins > 0) and (" Results remain for " .. mins .. " min.") or "")))
        return nil
      elseif t.phase ~= "available" and t.phase ~= "active" then
        await(Async.message_player(pid, "The raid is not currently available."))
        return nil
      end
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
      if timed_cfg and s.timed then
        local deadline = (s.timed.phase == "results") and s.timed.results_until or s.timed.deadline
        if deadline then
          status = status .. (" - %dm left"):format(_format_minutes(deadline - _now()))
        end
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

    if spec and not spec.results_callback then
      spec.results_callback = _persist_health_and_emotion
    end

    local battle_run_id = nil
    if timed_cfg then
      local ok_engage, engage_message = _engage_timed_raid(timed_cfg, s, _now())
      if not ok_engage then
        await(Async.message_player(pid, engage_message or "The raid is no longer available."))
        return nil
      end
      battle_run_id = s.timed and s.timed.run_id or nil
    end

    -- Begin encounter and await result
    local stats = await(ezencounters.begin_encounter(pid, spec))

    -- The raid may have expired, been defeated by someone else, or reset while
    -- this player was still battling. Never apply a stale result to a new run.
    if timed_cfg and not _timed_battle_is_current(timed_cfg, s, battle_run_id) then
      await(Async.message_player(pid, "The raid ended before your battle was completed."))
      return nil
    end

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
  local flags   = _result_flags(stats)
  local ran     = flags.ran
  local php     = flags.hp
  local won     = flags.won
  local derived = _calc_points_from_stats and _calc_points_from_stats(stats) or "n/a"

  print(string.format(
    "[RAID DBG] summary reason=%s won=%s ran=%s dev_escape=%s player_hp=%s derived_points=%s",
    tostring(flags.reason),
    tostring(won),
    tostring(ran),
    tostring(flags.dev_escape),
    tostring(php),
    tostring(derived)
  ))
end
-- ==== /RAID DEBUG ====

    -- Handle result per wave (use snapshot)
    if wave_at_start < 3 then
      local flags = _result_flags(stats)
      local ran      = flags.ran
      local defeated = flags.lost
                        or ((flags.hp or 0) <= 0 and not flags.ran)

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

      if award > 0 and JobBBSOK and JobBBS and JobBBS.on_raid_progress then
        pcall(JobBBS.on_raid_progress, pid, {
          raid_id = raid_id,
          wave    = wave_at_start,
          points  = award,
          boss    = false,
        })
      end

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
        if first_points and not timed_cfg then
          local msg = string.format(
            "RAID STARTED - Wave 1 %d/%d",
            tonumber(s.wave1_points or 0) or 0,
            tonumber(s.wave2_points_required or 0) or 0
          )
          _announce_all(msg, { loops = 2 })
        end

        if was == 1 and s.wave == 2 then
          -- Wave 1 cleared → pay pendings
          for _, cc in pairs(s.contributions or {}) do
            cc.chain2 = 0
          end
          ezmemory.save_area_memory(mem_area)
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
          -- Queue and pay Wave 1 money rewards
          _queue_money_claims_for_wave(mem_area, raid_id, s, "wave1")
          _pay_pending_claims_for_connected(mem_area, raid_id, s)

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
		  print("[RAID DBG] Wave1 cleared")

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
          -- Queue and pay Wave 2 money rewards
          _queue_money_claims_for_wave(mem_area, raid_id, s, "wave2")
          _pay_pending_claims_for_connected(mem_area, raid_id, s)

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
		  print("[RAID DBG] Wave2 cleared")

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
      local flags   = _result_flags(stats)
      local ran     = flags.ran
      local dev_escape = flags.dev_escape
      local enemies = stats and stats.enemies
      local has_snapshot = (type(enemies) == "table" and next(enemies) ~= nil)

      local dmg = 0

      if has_snapshot then
        -- Try to compute from enemy list (partial damage if boss present)
        dmg = _boss_damage_from_enemies_list(stats, s.boss_encounter_hp, s.boss_id_match) or 0

        -- If the player ran and we don't see the boss in the snapshot,
        -- assume boss was killed and player escaped due to soft-lock adds → full encounter damage.
        if ran and not dev_escape then
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
        if dev_escape then
          -- ESC / dev-run: treat as no damage, so you can safely abort tests.
          dmg = 0
        else
          -- Non-run and L-button runs fall back to the generic damage logic.
          local php = flags.hp or tonumber(stats and (stats.health or stats.player_hp or stats.hp) or 0) or 0
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

        if JobBBSOK and JobBBS and JobBBS.on_raid_progress then
          pcall(JobBBS.on_raid_progress, pid, {
            raid_id     = raid_id,
            wave        = 3,
            boss        = true,
            boss_damage = dmg,
          })
        end
      end

      local msg = ("Boss HP: %d/%d"):format(s.boss_pool_hp or 0, s.boss_pool_max or 0)
      if s.boss_pool_hp <= 0 and not s.defeated then
        if JobBBSOK and JobBBS and JobBBS.on_raid_progress then
          pcall(JobBBS.on_raid_progress, pid, {
            raid_id = raid_id,
            wave    = 3,
            boss    = true,
            killed  = true,   -- no extra damage; we already sent dmg above
          })
        end
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

        s.defeated    = true
        s.defeated_at = _now()
        if timed_cfg then
          _enter_timed_results(timed_cfg, s, _now())
        elseif s.style == "Repeat" then
          local cd = tonumber(s.repeat_cooldown_secs or 1800); if not cd or cd <= 0 then cd = 1800 end
          s.cooldown_until = _now() + cd
        end
        ezmemory.save_area_memory(mem_area)
        if Config.on_boss_defeated then pcall(Config.on_boss_defeated, pid, raid_id, s) end
        -- Queue and pay boss money rewards
        _queue_money_claims_for_wave(mem_area, raid_id, s, "boss")
        _pay_pending_claims_for_connected(mem_area, raid_id, s)
        -- ANNOUNCE top boss damage dealers
        local contribs = _contrib_list(s, "boss_dmg", 6)
        local end_msg = "RAID CLEARED - Top Damage: " .. (contribs ~= "" and contribs or "(no data)")
        if timed_cfg then
          end_msg = end_msg .. (" - Results remain for %d min.")
            :format(_format_minutes(timed_cfg.results_seconds))
        end
        _announce_all(end_msg, { loops = 2 })
		print("[RAID DBG] Boss defeated")
        if timed_cfg then
          await(Async.message_player(pid,
            ("Boss defeated! Results remain for %d min.")
              :format(_format_minutes(timed_cfg.results_seconds))))
        else
          await(Async.message_player(pid, "Boss defeated!"))
        end
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

-- Register every raid from the unified config table before wiring the scheduler.
local configured_raid_count = _register_configured_raids()
print("[RAIDS TIMED] configured raids=" .. tostring(configured_raid_count))

if not _G.__RAIDS_TIMED_WIRED then
  _G.__RAIDS_TIMED_WIRED = true

  local timed_tick_accum = 0

  Net:on("tick", function(ev)
    local dt = 0

    if type(ev) == "number" then
      dt = tonumber(ev) or 0
    elseif type(ev) == "table" then
      dt = tonumber(ev.delta_time or ev.delta or ev.dt or 0) or 0
    end

    -- Beta builds normally provide delta_time. This fallback keeps the raid
    -- scheduler alive if a build emits a tick table without that field.
    if dt <= 0 then dt = 1 / 60 end

    timed_tick_accum = timed_tick_accum + dt
    if timed_tick_accum < 1.0 then return end
    timed_tick_accum = timed_tick_accum - 1.0

    local now = _now()
    for _, cfg in pairs(TIMED_RAIDS) do
      local ok, err = pcall(_process_timed_raid, cfg, now)
      if not ok then
        print(("[RAIDS TIMED] tick error %s: %s")
          :format(tostring(cfg.key), tostring(err)))
      end
    end
  end)

  Net:on("player_join", function(ev)
    local pid = ev.player_id
    TIMED_VISIBILITY_CACHE[pid] = nil
    pcall(_sync_player_timed_visibility, pid, true)

    if Async and Async.sleep then
      Async.sleep(0.25).and_then(function()
        pcall(_sync_player_timed_visibility, pid, true)
      end)
    end
  end)

  Net:on("player_area_transfer", function(ev)
    local pid = ev.player_id
    TIMED_VISIBILITY_CACHE[pid] = nil
    pcall(_sync_player_timed_visibility, pid, true)

    if Async and Async.sleep then
      Async.sleep(0.10).and_then(function()
        pcall(_sync_player_timed_visibility, pid, true)
      end)
    end
  end)

  Net:on("player_disconnect", function(ev)
    TIMED_VISIBILITY_CACHE[ev.player_id] = nil
  end)
end

if not _G.__RAIDS_LOGIN_ANNOUNCE then
  _G.__RAIDS_LOGIN_ANNOUNCE = true
  Net:on("player_join", function(ev)
    local pid = ev.player_id

    -- Pay any pending raid money for this player (offline rewards).
    _pay_all_claims_for_pid(pid)
    ------------------------------------------------------------------
    -- 1) Global login marquee: "<name> logged in!"
    ------------------------------------------------------------------
    do
      local login_name = ("Player %s"):format(pid)
      if Net.get_player_name then
        local ok_name, pname = pcall(Net.get_player_name, pid)
        if ok_name and pname and pname ~= "" then
          login_name = pname
        end
      end

      local login_text = string.format("%s logged in!", login_name)

      -- Small-ish ticker near the bottom-left; tweak numbers to taste.
      local login_opts = {
        id           = "__raid_login_announce", -- unique id for login ticker
        scale        = 0.9,
        width        = 120,
        height       = 16,
        padding_x    = 3,
        padding_y    = 2,
        margin_right = 115,   -- with width=150 on 240px screen, this puts x ~ 4px from left
        y            = 300,  -- near bottom (0 = top, 160 = bottom)
        z            = 210,  -- slightly under the big raid marquee (z=220)
        speed        = "slow",
        loops        = 1,    -- <- exactly one loop
        font         = "THICK", -- or UI.font / "THICK", whatever you prefer
      }

      local ok_broadcast, err_broadcast = pcall(_announce_all, login_text, login_opts)
      if not ok_broadcast then
        print(("[RAIDS] login broadcast marquee error pid=%s: %s")
          :format(pid, tostring(err_broadcast)))
      end
    end

    ------------------------------------------------------------------
    -- 2) Existing logic: test marquee + raid status on login
    ------------------------------------------------------------------

    -- Decide which area to read state from
    local area_for_state = LOGIN_ANNOUNCE_MEM_AREA or RAID_MEM_AREA or Net.get_player_area(pid)
    print(("[RAIDS] login check pid=%s area_for_state=%s"):format(pid, tostring(area_for_state)))

    -- Optional test marquee just for this player
    if TEST_LOGIN_MARQUEE then
      local ok, err = pcall(_marquee, pid, TEST_LOGIN_TEXT, TEST_LOGIN_OPTS)
      if not ok then
        print(("[RAIDS] login test marquee error pid=%s: %s"):format(pid, tostring(err)))
      end
    end

    -- Choose which raid to show
    local rid, s
    if LOGIN_ANNOUNCE_RAID_ID and LOGIN_ANNOUNCE_RAID_ID ~= "" then
      rid = tostring(LOGIN_ANNOUNCE_RAID_ID)
      s   = _peek_store(area_for_state)[rid]  -- <-- DO NOT create new state
      if not s then
        print(("[RAIDS] login check: pinned rid=%s not found in area=%s")
          :format(rid, tostring(area_for_state)))
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
        print("[RAIDS] login check: no active raid in state (rid=" .. tostring(rid) .. ")")
        return
      end
    end

    -- Build the status string from the selected state
    local msg
    if type(s.timed) == "table" and s.timed.enabled == true and s.timed.phase == "available" then
      local raid_cfg = Config.get_raid(rid) or {}

      msg = string.format(
        "RAID SPAWNED - %s appeared in %s!",
        raid_cfg.display_name or rid,
        raid_cfg.area_id or area_for_state
      )
    elseif s.wave == 1 then
      msg = string.format("RAID IN PROGRESS - %s - W1 %d/%d",
        rid, s.wave1_points or 0, s.wave2_points_required or 0)
    elseif s.wave == 2 then
      msg = string.format("RAID IN PROGRESS - %s - W2 %d/%d",
        rid, s.wave2_points or 0, s.wave3_points_required or 0)
    else
      msg = string.format("RAID IN PROGRESS - %s - Boss %d/%d",
        rid, s.boss_pool_hp or 0, s.boss_pool_max or 0)
    end

    if type(s.timed) == "table" and s.timed.enabled == true
      and s.timed.phase == "active" and s.timed.deadline then
      msg = msg .. string.format(" - %d min left",
        _format_minutes(s.timed.deadline - _now()))
    end

    local ok, err = pcall(_marquee, pid, msg, { loops = 2 })
    if not ok then
      print(("[RAIDS] login marquee error pid=%s: %s"):format(pid, tostring(err)))
    end
  end)
end

-- Public marquee announcer API.
-- Other scripts can call:
--   _G.RaidAnnouncer.announce("Some message", { loops = 2 })
function Raids.announce(text, opts, area_id)
  opts = opts or {}

  if opts.loops == nil then
    opts.loops = 2
  end

  if opts.id == nil then
    opts.id = "__global_announce"
  end

  return _announce_all(tostring(text or ""), opts, area_id)
end

_G.RaidAnnouncer = _G.RaidAnnouncer or {}
_G.RaidAnnouncer.announce = function(text, opts, area_id)
  return Raids.announce(text, opts, area_id)
end

return Raids
