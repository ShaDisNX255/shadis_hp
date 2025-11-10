-- /server/scripts/teams/teams.lua
-- Monthly two-team system with BBS boards + JobBBS hook + month.lua reward catalog

local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local helpers  = require('scripts/ezlibs-scripts/helpers')
local Month    = require('scripts/teams/month')  -- << define rewards in this file

-- Try JobBBS from either path; if present we will hook job-claim to +1 GP.
local JobBBS = (function()
  local ok, M = pcall(require, 'scripts/jobbbs/JobBBS')
  if ok and M then return M end
  ok, M = pcall(require, 'scripts/jobbbs/jobbbs')
  return ok and M or nil
end)()

local Teams = {}

-- =========================
-- ====== CONFIG AREA ======
-- =========================
-- IMPORTANT: must be a real area id that always exists (e.g., the map where these boards live)
local TEAM_DATA_AREA_ID = "teamshq"

-- Team names (reusable for other servers; nothing hard-coded)
local TEAM_NAMES = {
  [1] = "Team Protoman",
  [2] = "Team Colonel",
}

-- Object types for map objects (press A to open)
local OBJ_TEAM_1   = "Team1BBS"
local OBJ_TEAM_2   = "Team2BBS"
local OBJ_SCORES   = "TeamScoresBBS"

-- Last day (inclusive) of the month players may join a team (set to 31 for testing)
local JOIN_WINDOW_LAST_DAY = 31

-- Test toggles
local TEST_ALLOW_INFINITE_SWITCH = false  -- if true, switch teams unlimited times in a month
local TEST_ALWAYS_ALLOW_CLAIM     = false -- if true, claim monthly rewards every press (uses current month)

-- BBS header colors
local TEAM_COLORS = {
  [1] = { r=220, g=70,  b=70  }, -- Team 1: red
  [2] = { r=70,  g=90,  b=170 }, -- Team 2: darker blue
}
local COLOR_TEAM  = { r=160, g=220, b=255 } -- fallback
local COLOR_SCORE = { r=255, g=230, b=160 }

-- == GP from Raids ==
local RAID_GP = {
  -- conversion: how much progress equals 1 GP
  w1_points_per_gp    = 50,     -- Wave 1 points → GP
  w2_points_per_gp    = 30,     -- Wave 2 points → GP
  boss_damage_per_gp  = 1000,   -- Boss damage → GP

  -- daily caps
  player_daily_cap    = 10,     -- max GP/player/day from raids
  team_cap_per_active = 10,     -- team cap/day = active_contributors_today * this
  team_daily_cap_min  = 10,     -- floor
  team_daily_cap_max  = 80,     -- ceiling

  -- underdog multiplier (updates daily; disabled in the last 48h)
  underdog_enabled        = true,
  underdog_mul            = 1.20,  -- applied to losing team
  leading_mul             = 1.00,  -- applied to leading team
  bonus_off_last_hours    = 48,    -- disable multipliers in last 48h of month
}

-- =========================
-- ====== UTILITIES  =======
-- =========================
local function _now() return os.time() end
local function _month_key(ts) return os.date("%Y-%m", ts or _now()) end
local function _day_of_month(ts) return tonumber(os.date("%d", ts or _now())) end

local function _sum_values(t)
  local s = 0
  for _, v in pairs(t or {}) do s = s + (tonumber(v) or 0) end
  return s
end

local function _count_keys(tbl)
  local n = 0
  for _ in pairs(tbl or {}) do n = n + 1 end
  return n
end

local function _coin_flip(month_key, salt)
  local s = tostring(month_key or "") .. "|" .. tostring(salt or "")
  local h = 0
  for i = 1, #s do h = (h * 131 + s:byte(i)) % 1000000007 end
  return (h % 2 == 0) and 1 or 2  -- returns 1 or 2
end

-- Weighted picker for { weight = N, ... } entries
local function _pick_weighted(entries)
  local total = 0
  for _, e in ipairs(entries or {}) do total = total + (tonumber(e.weight) or 0) end
  if total <= 0 then return nil end
  local roll, acc = math.random() * total, 0
  for _, e in ipairs(entries) do
    acc = acc + (tonumber(e.weight) or 0)
    if roll <= acc then return e end
  end
  return entries[#entries]
end

-- =========================
-- ====== PERSISTENCE ======
-- =========================
-- Area memory layout:
-- mem.teams = {
--   month_key = "YYYY-MM",
--   month     = {
--     [1] = { total=0, roster = { [secret]=true }, gp_by_secret = { [secret]=n } },
--     [2] = { total=0, roster = { ... },          gp_by_secret = { ... } },
--   },
--   names     = { [secret] = "Last Known Name" },
--   prev      = {
--     month_key = "YYYY-MM",
--     totals    = { [1]=n1, [2]=n2 },
--     roster    = { [1]=size1, [2]=size2 },
--     top       = { [1]={secret=..., gp=...}, [2]={secret=..., gp=...} },
--     winner    = 1 or 2 or 0
--   }
-- }
--
-- Player memory (by safe secret):
-- pmem.teams.current = { team=1|2|nil, month="YYYY-MM", gp=0, last_switch_month="YYYY-MM" }
-- pmem.teams.hist    = { ["YYYY-MM"] = { team=1|2, gp=N } }
-- pmem.teams.claimed = { ["YYYY-MM"] = { team=true, top=true, losing=true } }
-- pmem.teams.events_claimed = { [event_id]=true }

local function _amem()
  local mem = ezmemory.get_area_memory(TEAM_DATA_AREA_ID)
  if not mem then
    print("[teams] WARNING: get_area_memory returned nil for area", TEAM_DATA_AREA_ID)
    mem = {}
  end
  mem.teams = mem.teams or {}
  return mem, mem.teams
end

local function _save_area()
  if ezmemory.save_area_memory then
    ezmemory.save_area_memory(TEAM_DATA_AREA_ID)
  end
end

local function _roll_month_if_needed()
  local mem, t = _amem()
  local now_key = _month_key()

  -- Month rollover: finalize last month into t.prev
  if t.month_key and t.month_key ~= now_key and t.month then
    -- Ensure check-in fields exist on old month buckets
    local p1 = t.month[1] or { total=0, roster={}, gp_by_secret={}, checkins_total=0, checkins_by_secret={} }
    local p2 = t.month[2] or { total=0, roster={}, gp_by_secret={}, checkins_total=0, checkins_by_secret={} }

    -- Deterministic coin flip based on month key + salt; returns 1 or 2
    local function coin_flip(month_key, salt)
      local s = tostring(month_key or "") .. "|" .. tostring(salt or "")
      local h = 0
      for i = 1, #s do h = (h * 131 + s:byte(i)) % 1000000007 end
      return (h % 2 == 0) and 1 or 2
    end

    -- Per-team MVP selection with tie-break on MOST check-ins, then coin flip
    local function top_of(tb, mkey, team_tag)
      local best_s, best_gp, best_chk, best_coin = nil, -1, nil, nil
      for s, gp in pairs(tb.gp_by_secret or {}) do
        gp = tonumber(gp or 0)
        local chk = tonumber((tb.checkins_by_secret and tb.checkins_by_secret[s]) or 0)
        local cf  = coin_flip(mkey, "mvp|"..tostring(team_tag).."|"..tostring(s))  -- 1 or 2
        if gp > best_gp
           or (gp == best_gp and (best_chk == nil or chk > best_chk))   -- most check-ins wins
           or (gp == best_gp and chk == best_chk and (best_coin == nil or cf < best_coin)) then
          best_gp, best_s, best_chk, best_coin = gp, s, chk, cf
        end
      end
      if not best_s then return nil, 0 end
      return best_s, best_gp
    end

    local mkey = t.month_key
    local s1, g1 = top_of(p1, mkey, 1)
    local s2, g2 = top_of(p2, mkey, 2)

    local tot1 = tonumber(p1.total or 0)
    local tot2 = tonumber(p2.total or 0)

    local win
    if tot1 ~= tot2 then
      win = (tot1 > tot2) and 1 or 2
    else
      -- Team tie: MOST total check-ins wins; else deterministic coin flip
      local c1 = tonumber(p1.checkins_total or 0)
      local c2 = tonumber(p2.checkins_total or 0)
      if c1 ~= c2 then
        win = (c1 > c2) and 1 or 2
      else
        win = coin_flip(mkey, "team") -- 1 or 2
      end
    end

    t.prev = {
      month_key = t.month_key,
      totals    = { [1]=tot1, [2]=tot2 },
      roster    = { [1]=_count_keys(p1.roster), [2]=_count_keys(p2.roster) },
      top       = { [1]={secret=s1, gp=g1 or 0}, [2]={secret=s2, gp=g2 or 0} },
      winner    = win
    }
  end

  -- Start a fresh current month if needed
  if t.month_key ~= now_key or not t.month then
    t.month_key = now_key
    t.month     = {
      [1] = { total=0, roster={}, gp_by_secret={}, checkins_total=0, checkins_by_secret={} },
      [2] = { total=0, roster={}, gp_by_secret={}, checkins_total=0, checkins_by_secret={} },
    }
  end

  t.names = t.names or {}
  _save_area()
  return mem, t
end

local function _pmem(pid)
  local secret = helpers.get_safe_player_secret(pid)
  local pmem   = ezmemory.get_player_memory(secret) or {}
  pmem.teams   = pmem.teams or {}
  pmem.teams.current = pmem.teams.current or { team=nil, month=_month_key(), gp=0, last_switch_month=nil }
  local cur = pmem.teams.current
  if cur.month ~= _month_key() then
    pmem.teams.hist = pmem.teams.hist or {}
    pmem.teams.hist[cur.month] = { team = cur.team, gp = cur.gp or 0 }
    pmem.teams.current = { team = cur.team, month = _month_key(), gp = 0, checkins = 0, last_switch_month = cur.last_switch_month }
  end
  pmem.teams.claimed = pmem.teams.claimed or {}
  pmem.teams.events_claimed = pmem.teams.events_claimed or {}
  if ezmemory.set_player_memory then ezmemory.set_player_memory(secret, pmem) else ezmemory.save_player_memory(secret, pmem) end
  return secret, pmem
end

-- =========================
-- ====== NAMES/ROSTER =====
-- =========================
local function _team_name(i) return TEAM_NAMES[i] or ("Team "..tostring(i)) end

local function _get_display_name(pid)
  local ok, name = pcall(Net.get_player_name, pid)
  if ok and type(name)=="string" and #name>0 then return name end
  ok, name = pcall(Net.get_player_display_name, pid)
  if ok and type(name)=="string" and #name>0 then return name end
  return nil
end

local function _remember_name(pid, secret)
  local name = _get_display_name(pid)
  if not name then return end
  local mem, t = _roll_month_if_needed()
  t.names[secret] = name
  local pm = ezmemory.get_player_memory(secret) or {}
  pm.teams = pm.teams or {}
  pm.teams.last_name = name
  if ezmemory.set_player_memory then ezmemory.set_player_memory(secret, pm) else ezmemory.save_player_memory(secret, pm) end
  _save_area()
end

local function _add_to_roster(t_mem, team, secret)
  local slot = t_mem.month[team]
  slot.roster[secret] = true
end

local function _remove_from_roster(t_mem, team, secret)
  local slot = t_mem.month[team]
  if slot then slot.roster[secret] = nil end
end

-- Optional, safe "self-sync" to backfill from pmem once (will not duplicate GP on switches)
local function _sync_self_into_area(pid)
  local mem, t_mem = _roll_month_if_needed()
  local secret, pmem = _pmem(pid)
  local cur = pmem.teams.current
  if not cur or not cur.team then return end

  local slot1 = t_mem.month[1] or { gp_by_secret = {}, roster = {} }
  local slot2 = t_mem.month[2] or { gp_by_secret = {}, roster = {} }
  local g1 = tonumber(slot1.gp_by_secret[secret] or 0)
  local g2 = tonumber(slot2.gp_by_secret[secret] or 0)

  -- If any GP exists for this player in either team this month, do not mirror totals again.
  if (g1 > 0) or (g2 > 0) then
    (t_mem.month[cur.team].roster)[secret] = true
    _remember_name(pid, secret)
    _save_area()
    return
  end

  local want = tonumber(cur.gp or 0)
  local slot = t_mem.month[cur.team]
  slot.roster[secret] = true
  if want > 0 then
    slot.gp_by_secret[secret] = want
    slot.total = math.max(tonumber(slot.total or 0), 0) + want
  end
  _remember_name(pid, secret)
  _save_area()
end

-- =========================
-- ====== REWARDS ==========
-- =========================
local function _give_inline_item(pid, info, notify)
  local area_id = Net.get_player_area(pid) or TEAM_DATA_AREA_ID
  local item_info = {
    type        = info.type or "item",   -- "item" or "keyitem"
    name        = tostring(info.name or "Item"),
    description = tostring(info.description or ""),
    amount      = tonumber(info.amount or info.qty or 1),
  }
  pcall(ezmemory.give_item_with_optional_notify, pid, area_id, nil, item_info, notify ~= false)
end

local DECOR_MEM_KEY = "oncehub_decor_inventory_v1"

local _DECOR_FRIENDLY = {

}

local function _decor_name_for(id)
  -- 1) Prefer the local mapping declared in this file
  if _DECOR_FRIENDLY and _DECOR_FRIENDLY[id] then
    return _DECOR_FRIENDLY[id]
  end

  -- 2) Optional: also honor a global mapping if you ever set one elsewhere
  local t = rawget(_G, "_DECOR_FRIENDLY")
  if t and t[id] then return t[id] end

  -- 3) Fallback: try to read a label from ONCEHUB_CATALOG
  local cat = rawget(_G, "ONCEHUB_CATALOG")
  if cat and cat[id] then
    local e = cat[id]
    if e.name and e.name ~= "" then return e.name end
    if e.Name and e.Name ~= "" then return e.Name end
    if e.title and e.title ~= "" then return e.title end
    if e.Title and e.Title ~= "" then return e.Title end
    if e.props then
      local p = e.props
      if p.Name and p.Name ~= "" then return p.Name end
      if p.name and p.name ~= "" then return p.name end
      if p.Title and p.Title ~= "" then return p.Title end
      if p.title and p.title ~= "" then return p.title end
    end
  end

  -- 4) Last resort: raw id
  return tostring(id)
end

-- ===== and replace the message line inside _grant_decor_owned =====
-- Net.message_player(pid, ("Got decor: %s x%d."):format(_decor_name_for(id), qty))
local function _grant_decor_owned(pid, id, qty, label)
  qty = math.max(1, tonumber(qty or 1))
  local secret = helpers.get_safe_player_secret(pid)
  local pm = ezmemory.get_player_memory(secret) or {}
  pm[DECOR_MEM_KEY] = pm[DECOR_MEM_KEY] or {}
  pm[DECOR_MEM_KEY][id] = math.max(0, tonumber(pm[DECOR_MEM_KEY][id] or 0)) + qty
  if ezmemory.set_player_memory then
    ezmemory.set_player_memory(secret, pm)
  else
    ezmemory.save_player_memory(secret, pm)
  end

  local pretty = (label and label ~= "" and label) or _decor_name_for(id)
  Net.message_player(pid, ("Got decor: %s x%d."):format(pretty, qty))
  if Net.play_sound_for_player then
    pcall(Net.play_sound_for_player, pid, "/server/assets/ezlibs-assets/sfx/item_get.ogg")
  end
end

-- Grants money, inline items, card pack(s), fixed decor, and decor pack(s)
local function _grant_reward(pid, spec)
  if not spec then return end

  -- Money with explicit message
  if spec.money and spec.money ~= 0 then
    local amt = math.floor(tonumber(spec.money) or 0)
    local ok = pcall(ezmemory.spend_player_money, pid, -amt)
    if not ok then
      local secret = helpers.get_safe_player_secret(pid)
      local pm     = ezmemory.get_player_memory(secret) or {}
      pm.money = math.max(0, (tonumber(pm.money) or 0) + amt)
      if ezmemory.set_player_memory then ezmemory.set_player_memory(secret, pm) else ezmemory.save_player_memory(secret, pm) end
    end
    Net.message_player(pid, "Got "..tostring(amt).."$!")
  end

  -- Fixed inline items (cards/keys via ezmemory)
  if spec.items_inline then
    for _, info in ipairs(spec.items_inline) do
      local area_id = Net.get_player_area(pid) or TEAM_DATA_AREA_ID
      local item_info = {
        type        = info.type or "item",
        name        = tostring(info.name or "Item"),
        description = tostring(info.description or ""),
        amount      = tonumber(info.amount or info.qty or 1),
      }
      pcall(ezmemory.give_item_with_optional_notify, pid, area_id, nil, item_info, true)
    end
  end

  -- FIXED DECOR (no pack banner; just grants)
  -- spec.decor = { { id="skull_1", qty=1, label="DOTD Skull (Black)" }, ... }
  if spec.decor then
    for _, d in ipairs(spec.decor) do
      if d and d.id then
        _grant_decor_owned(pid, tostring(d.id), tonumber(d.qty or d.amount or 1), d.label)
      end
    end
  end

  -- DECOR PACK (weighted), prints pack name once
  -- spec.decor_pack_name, spec.decor_rolls, spec.decor_pool = { {id=..., weight=..., qty=..., label=...}, ... }
  if spec.decor_pool and #spec.decor_pool > 0 then
    local pack_name = spec.decor_pack_name or "Decor Pack"
    Net.message_player(pid, "Got "..pack_name..".")
    local rolls = tonumber(spec.decor_rolls or 1) or 1
    for i=1,rolls do
      local pick = _pick_weighted(spec.decor_pool)
      if pick and pick.id then
        _grant_decor_owned(pid, tostring(pick.id), tonumber(pick.qty or pick.amount or 1), pick.label)
      end
    end
  end

  -- CARD PACK (weighted), prints pack name and an “Opened pack and got …” line per roll
  if spec.pack_pool and #spec.pack_pool > 0 then
    local pack_name = spec.pack_name or "Card Pack"
    Net.message_player(pid, "Got "..pack_name..".")
    local rolls = tonumber(spec.pack_rolls or 1)
    for i = 1, rolls do
      local pick = _pick_weighted(spec.pack_pool)
      if pick then
        Net.message_player(pid, "Opened pack and got: "..tostring(pick.name)..".")
        local area_id = Net.get_player_area(pid) or TEAM_DATA_AREA_ID
        local item_info = {
          type="item",
          name=tostring(pick.name),
          description=tostring(pick.description or ""),
          amount=tonumber(pick.amount or 1),
        }
        pcall(ezmemory.give_item_with_optional_notify, pid, area_id, nil, item_info, false)
        if Net.play_sound_for_player then
          pcall(Net.play_sound_for_player, pid, "/server/assets/ezlibs-assets/sfx/item_get.ogg")
        end
      end
    end
  end
end

local function _now() return os.time() end
local function _today_key() return os.date("%Y-%m-%d", _now()) end
local function _hours_until_month_end()
  local now  = os.date("*t", _now())
  local last = os.date("*t", os.time{year=now.year, month=now.month+1, day=0, hour=23, min=59, sec=59})
  local sec  = os.difftime(os.time(last), _now())
  return math.max(0, math.floor(sec/3600))
end
local function _is_last_48h_of_month()
  return _hours_until_month_end() <= (RAID_GP.bonus_off_last_hours or 48)
end


-- =========================
-- ====== GP EARNING  ======
-- =========================
local function _add_gp(pid, amount, why)
  local mem, t_mem = _roll_month_if_needed()
  local secret, pmem = _pmem(pid)
  local cur = pmem.teams.current
  if not cur.team then
    Net.message_player(pid, "Join a team first to earn GP.")
    return
  end
  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then return end

  cur.gp = (cur.gp or 0) + amount
  pmem.teams.hist = pmem.teams.hist or {}
  pmem.teams.hist[cur.month] = { team = cur.team, gp = cur.gp }

  local slot = t_mem.month[cur.team]
  slot.total = (slot.total or 0) + amount
  slot.gp_by_secret[secret] = (slot.gp_by_secret[secret] or 0) + amount
  _add_to_roster(t_mem, cur.team, secret)

  _remember_name(pid, secret)

  if ezmemory.set_player_memory then ezmemory.set_player_memory(secret, pmem) else ezmemory.save_player_memory(secret, pmem) end
  _save_area()

  if why then Net.message_player(pid, ("+%d GP for %s."):format(amount, why)) end
end

-- Tracks daily GP cap usage & actives (by secret) + today's team multipliers
local function _ensure_daily_bucket()
  local mem, t_mem = _roll_month_if_needed()
  t_mem.daily = t_mem.daily or {}
  local key = _today_key()
  local d = t_mem.daily[key]
  if d then return d, t_mem end

  d = {
    active_by_team = { [1] = {}, [2] = {} },  -- set of secrets that contributed today
    team_used      = { [1] = 0,   [2] = 0   },-- GP used by team today
    player_used    = {},                      -- [secret] = GP used today
    mul_today      = { [1] = 1.0, [2] = 1.0 }
  }

  -- compute underdog multipliers (once per day)
  if RAID_GP.underdog_enabled and not _is_last_48h_of_month() then
    t_mem.month[1] = t_mem.month[1] or { total=0, roster={}, gp_by_secret={} }
    t_mem.month[2] = t_mem.month[2] or { total=0, roster={}, gp_by_secret={} }
    local t1 = tonumber(t_mem.month[1].total or 0) or 0
    local t2 = tonumber(t_mem.month[2].total or 0) or 0
    if t1 > t2 then
      d.mul_today[1] = RAID_GP.leading_mul or 1.0
      d.mul_today[2] = RAID_GP.underdog_mul or 1.0
    elseif t2 > t1 then
      d.mul_today[2] = RAID_GP.leading_mul or 1.0
      d.mul_today[1] = RAID_GP.underdog_mul or 1.0
    else
      d.mul_today[1], d.mul_today[2] = 1.0, 1.0 -- tie → no boost
    end
  end

  t_mem.daily[key] = d
  _save_area()
  return d, t_mem
end

-- Award GP by secret (works if player is offline). pid_opt only used for an optional toast.
local function _add_gp_by_secret(secret, amount, why, pid_opt)
  amount = math.floor(tonumber(amount) or 0); if amount <= 0 then return end

  local pm = ezmemory.get_player_memory(secret) or {}
  pm.teams = pm.teams or {}
  pm.teams.current = pm.teams.current or { team=nil, month=_month_key(), gp=0, last_switch_month=nil }
  local cur = pm.teams.current
  if not cur.team then return end

  -- monthly rollover for player
  if cur.month ~= _month_key() then
    pm.teams.hist = pm.teams.hist or {}
    pm.teams.hist[cur.month] = { team = cur.team, gp = cur.gp or 0 }
    pm.teams.current = { team = cur.team, month = _month_key(), gp = 0, checkins = cur.checkins, last_switch_month = cur.last_switch_month }
    cur = pm.teams.current
  end

  local mem, t_mem = _roll_month_if_needed()
  local slot = t_mem.month[cur.team]
  cur.gp = (cur.gp or 0) + amount
  slot.total = (slot.total or 0) + amount
  slot.gp_by_secret[secret] = (slot.gp_by_secret[secret] or 0) + amount
  _add_to_roster(t_mem, cur.team, secret)

  if pm.teams and pm.teams.last_name and pm.teams.last_name ~= "" then
    t_mem.names[secret] = pm.teams.last_name
  end

  if ezmemory.set_player_memory then ezmemory.set_player_memory(secret, pm) else ezmemory.save_player_memory(secret, pm) end
  _save_area()

  if pid_opt and why then pcall(Net.message_player, pid_opt, ("+%d GP for %s."):format(amount, why)) end
end

-- Offline-safe payout used by Raids (called on wave clear / boss death)
-- kind = "w1" | "w2" | "boss"; amount = points (w1/w2) or damage (boss)
function Teams.on_raid_contribution_secret(secret, raid_id, kind, amount, pid_opt)
  amount = tonumber(amount) or 0
  if amount <= 0 then return end

  local per = (kind == "w1" and RAID_GP.w1_points_per_gp)
           or (kind == "w2" and RAID_GP.w2_points_per_gp)
           or (kind == "boss" and RAID_GP.boss_damage_per_gp)
           or 0
  if per <= 0 then return end
  local base = math.floor(amount / per)
  if base <= 0 then return end

  -- resolve team
  local pm = ezmemory.get_player_memory(secret) or {}
  pm.teams = pm.teams or {}; pm.teams.current = pm.teams.current or { team=nil, month=_month_key(), gp=0, last_switch_month=nil }
  local cur = pm.teams.current
  if not cur.team then return end
  local team = cur.team

  -- caps + today's multiplier
  local d = _ensure_daily_bucket()
  local mul  = (d.mul_today and d.mul_today[team]) or 1.0
  local gp   = math.floor(base * mul)
  if gp <= 0 then return end

  local actives = d.active_by_team[team] or {}; actives[secret] = true; d.active_by_team[team] = actives
  local active_n = 0; for _ in pairs(actives) do active_n = active_n + 1 end

  local team_cap = math.max(RAID_GP.team_daily_cap_min or 0,
                    math.min(RAID_GP.team_daily_cap_max or 9999,
                      math.max(active_n,1) * (RAID_GP.team_cap_per_active or 0)))
  local team_used = tonumber(d.team_used[team] or 0)
  local team_room = math.max(0, team_cap - team_used)

  local p_used = tonumber(d.player_used[secret] or 0)
  local p_cap  = RAID_GP.player_daily_cap or 10
  local p_room = math.max(0, p_cap - p_used)

  local give = math.max(0, math.min(gp, p_room, team_room))
  if give <= 0 then return end

  d.player_used[secret] = p_used + give
  d.team_used[team]     = team_used + give
  _save_area()

  _add_gp_by_secret(secret, give, "raids", pid_opt)
end

-- Convenience wrapper (online toast if present)
function Teams.on_raid_contribution(pid, raid_id, kind, amount)
  local secret = helpers.get_safe_player_secret(pid)
  Teams.on_raid_contribution_secret(secret, raid_id, kind, amount, pid)
end

-- =========================
-- ====== BBS HELPERS  =====
-- =========================
local function _sanitize_posts(posts)
  for _, p in ipairs(posts or {}) do
    p.id     = tostring(p.id or "")
    p.title  = tostring(p.title or "")
    p.author = tostring(p.author or "")
    if p.read == nil then p.read = true end
  end
end

local function _guard_next_two_closes(pid)
  if _G._guard_ignore_next_close then
    _G._guard_ignore_next_close(pid, "teams")
    _G._guard_ignore_next_close(pid, "teams")
  end
end

local _pending_open = {}  -- [pid] = { kind="members"|"team"|"scores", team=number|nil }

-- =========================
-- ====== OPEN BOARDS  =====
-- =========================
local function _team_posts(pid, team)
  _roll_month_if_needed()
  local _, pmem = _pmem(pid)
  local cur = pmem.teams.current

  local is_member   = (cur.team == team)
  local day         = _day_of_month()
  local last_day    = (JOIN_WINDOW_LAST_DAY or 14)
  local can_join    = (not cur.team) and (day >= 1 and day <= last_day)

  local can_switch = (cur.team ~= nil) and (cur.team ~= team) and
                     (TEST_ALLOW_INFINITE_SWITCH or (cur.last_switch_month ~= _month_key()))

  local label
  if is_member then
    label = "You are in this team"
  elseif cur.team then
    label = "Switch to this team"
  else
    label = "Join this team"
  end

  local author = ""
  if (not is_member) and (not can_join) and (not can_switch) then
    author = "(Locked)"
  end

  -- Count active unclaimed events
  local unclaimed_events = 0
  do
    local claimed = pmem.teams.events_claimed or {}
    for _, evt in ipairs(Month.get_active_events()) do
      if not claimed[evt.id] then unclaimed_events = unclaimed_events + 1 end
    end
  end

  local posts = {
    { id="__team:join:"..team,    read=true, title=label,                    author=author },
    { id="__team:checkin:"..team, read=true, title="Daily Check-In (+1 GP)", author=""     },
    { id="__team:status:"..team,  read=true, title="My Status",              author=""     },
    { id="__team:members:"..team, read=true, title="Members List",           author=""     },
  }

  if unclaimed_events > 0 then
    posts[#posts+1] = { id="__team:event_claim", read=true,
                        title=("Claim Event Reward ("..tostring(unclaimed_events).." active)"),
                        author="" }
  end

  posts[#posts+1] = { id="__team:claim",          read=true, title="Claim Monthly Rewards",  author="" }
  posts[#posts+1] = { id="__team:close",          read=true, title="Close",                  author="" }
  return posts
end

local function _open_team_board(pid, team)
  _roll_month_if_needed()
  -- optional, safe; keeps roster and name fresh without duplicating GP
  _sync_self_into_area(pid)

  local title = string.format("%s - %s", "Team Board", _team_name(team))
  local posts = _team_posts(pid, team)
  _sanitize_posts(posts)
  _guard_next_two_closes(pid)
  local color = (TEAM_COLORS and TEAM_COLORS[team]) or COLOR_TEAM
  Net.open_board(pid, title, color, posts)
end

local function _open_members_board(pid, team)
  -- optional, safe; keeps roster and name fresh without duplicating GP
  _sync_self_into_area(pid)

  local mem, t_mem = _roll_month_if_needed()
  local slot = t_mem.month[team] or { roster={}, gp_by_secret={} }
  local color = (TEAM_COLORS and TEAM_COLORS[team]) or COLOR_TEAM

  -- CURRENT ROSTER ONLY (do not union with gp_by_secret)
  local rows = {}
  for s,_ in pairs(slot.roster or {}) do
    local gp = slot.gp_by_secret[s] or 0
    local name = t_mem.names[s]
    if not name or name == "" then
      local pm = ezmemory.get_player_memory(s) or {}
      name = (pm.teams and pm.teams.last_name) or "Unknown"
    end
    rows[#rows+1] = { secret=s, name=name, gp=gp }
  end

  table.sort(rows, function(a,b)
    if a.gp ~= b.gp then return (a.gp > b.gp) end
    return tostring(a.name) < tostring(b.name)
  end)

  local posts = {}
  posts[#posts+1] = { id="__team:list_hdr:"..team, read=true, title=("Members - ".._team_name(team)), author="" }
  if #rows == 0 then
    posts[#posts+1] = { id="__team:list_nil", read=true, title="No members yet.", author="" }
  else
    for i, row in ipairs(rows) do
      posts[#posts+1] = { id="__team:list_row:"..i, read=true, title=(("%d. %s %dGP"):format(i, row.name, row.gp)), author="" }
    end
  end
  posts[#posts+1] = { id="__team:back:"..team, read=true, title="Back", author="" }
  posts[#posts+1] = { id="__team:close", read=true, title="Close", author="" }

  _sanitize_posts(posts)
  _guard_next_two_closes(pid)
  Net.open_board(pid, "Team Members", color, posts)
end

local function _open_scores_board(pid)
  -- optional, safe; keeps roster and name fresh without duplicating GP
  _sync_self_into_area(pid)

  local _, t_mem = _roll_month_if_needed()
  local title = "Teams - Scores"
  local posts = {}

  local month = t_mem.month_key or _month_key()
  local t1 = t_mem.month[1] or { roster={}, gp_by_secret={}, total=0 }
  local t2 = t_mem.month[2] or { roster={}, gp_by_secret={}, total=0 }

  local t1_total   = math.max(tonumber(t1.total or 0), _sum_values(t1.gp_by_secret))
  local t2_total   = math.max(tonumber(t2.total or 0), _sum_values(t2.gp_by_secret))
  local t1_members = _count_keys(t1.roster)
  local t2_members = _count_keys(t2.roster)

  posts[#posts+1] = { id="__teamscores:hdr_cur", read=true, title=("This month ("..month..")"), author="" }

  posts[#posts+1] = { id="__teamscores:t1_name",   read=true, title=_team_name(1), author="" }
  posts[#posts+1] = { id="__teamscores:t1_total",  read=true, title=("- Total GP: "..tostring(t1_total)), author="" }
  posts[#posts+1] = { id="__teamscores:t1_roster", read=true, title=("- Members: "..tostring(t1_members)), author="" }

  posts[#posts+1] = { id="__teamscores:t2_name",   read=true, title=_team_name(2), author="" }
  posts[#posts+1] = { id="__teamscores:t2_total",  read=true, title=("- Total GP: "..tostring(t2_total)), author="" }
  posts[#posts+1] = { id="__teamscores:t2_roster", read=true, title=("- Members: "..tostring(t2_members)), author="" }

  if t_mem.prev and t_mem.prev.month_key then
    posts[#posts+1] = { id="__teamscores:sep", read=true, title=("- Last Month ("..t_mem.prev.month_key..") -"), author="" }
    local pt = t_mem.prev.totals or {}
    local pr = t_mem.prev.roster or {}
    local pt1 = tonumber(pt[1] or 0)
    local pt2 = tonumber(pt[2] or 0)
    local pr1 = tonumber(pr[1] or 0)
    local pr2 = tonumber(pr[2] or 0)
    posts[#posts+1] = { id="__teamscores:pt1_name",   read=true, title=_team_name(1), author="" }
    posts[#posts+1] = { id="__teamscores:pt1_total",  read=true, title=("- Total GP: "..tostring(pt1)), author="" }
    posts[#posts+1] = { id="__teamscores:pt1_roster", read=true, title=("- Members: "..tostring(pr1)), author="" }
    posts[#posts+1] = { id="__teamscores:pt2_name",   read=true, title=_team_name(2), author="" }
    posts[#posts+1] = { id="__teamscores:pt2_total",  read=true, title=("- Total GP: "..tostring(pt2)), author="" }
    posts[#posts+1] = { id="__teamscores:pt2_roster", read=true, title=("- Members: "..tostring(pr2)), author="" }
  end

  posts[#posts+1] = { id="__teamscores:close", read=true, title="Close", author="" }
  _sanitize_posts(posts)
  _guard_next_two_closes(pid)
  Net.open_board(pid, title, COLOR_SCORE, posts)
end

-- =========================
-- ====== BBS ACTIONS  =====
-- =========================
local function _handle_team_action(pid, post_id)
  local mem, t_mem = _roll_month_if_needed()
  local secret, pmem = _pmem(pid)
  local cur = pmem.teams.current

  -- Join / Switch
  local team = tonumber(post_id:match("^__team:join:(%d+)$") or "")
  if team and (team == 1 or team == 2) then
    local day = _day_of_month()
    if not cur.team then
      -- Join (days 1..JOIN_WINDOW_LAST_DAY)
      if not (day >= 1 and day <= (JOIN_WINDOW_LAST_DAY or 14)) then
        Net.message_player(pid, "Joining is only allowed on days 1-"..tostring(JOIN_WINDOW_LAST_DAY or 14)..".")
        return true
      end
      cur.team = team
      cur.month = _month_key(); cur.gp = cur.gp or 0
      _add_to_roster(t_mem, team, secret)
      _remember_name(pid, secret)
      Net.message_player(pid, "Joined ".._team_name(team).."!")
    else
      -- Switch (once per month unless testing)
      if cur.team == team then Net.message_player(pid, "You are already in this team."); return true end
      if (not TEST_ALLOW_INFINITE_SWITCH) and cur.last_switch_month == _month_key() then
        Net.message_player(pid, "You can only switch teams once this month.")
        return true
      end
      _remove_from_roster(t_mem, cur.team, secret)
      cur.team = team
      if not TEST_ALLOW_INFINITE_SWITCH then
        cur.last_switch_month = _month_key()
      end
      _add_to_roster(t_mem, team, secret)
      _remember_name(pid, secret)
      Net.message_player(pid, "Switched to ".._team_name(team)..".")
    end
    if ezmemory.set_player_memory then ezmemory.set_player_memory(secret, pmem) else ezmemory.save_player_memory(secret, pmem) end
    _save_area()
    _pending_open[pid] = { kind="team", team=team }
    _guard_next_two_closes(pid)
    pcall(Net.close_bbs, pid)
    return true
  end

  -- Daily check-in
  local chk_team = tonumber(post_id:match("^__team:checkin:(%d+)$") or "")
  if chk_team then
    if cur.team ~= chk_team then
      Net.message_player(pid, "Join this team first.")
      return true
    end

    pmem.teams._last_checkin = pmem.teams._last_checkin or ""
    local today = os.date("%Y-%m-%d", _now())

    if pmem.teams._last_checkin == today then
      Net.message_player(pid, "Already checked in today.")
    else
      -- mark today's check-in
      pmem.teams._last_checkin = today

      -- count player check-ins this month (used for MVP tie-breaker)
      pmem.teams.current.checkins = (pmem.teams.current.checkins or 0) + 1
      if ezmemory.set_player_memory then
        ezmemory.set_player_memory(secret, pmem)
      else
        ezmemory.save_player_memory(secret, pmem)
      end

      -- count team check-ins this month (used for team tie-breaker)
      local _, t_mem_i = _roll_month_if_needed()
      local slot = t_mem_i.month[cur.team]
      slot.checkins_total = (slot.checkins_total or 0) + 1
      slot.checkins_by_secret = slot.checkins_by_secret or {}
      slot.checkins_by_secret[secret] = (slot.checkins_by_secret[secret] or 0) + 1
      _save_area()

      -- award GP
      _add_gp(pid, 1, "daily check-in")
    end
    return true
  end

  -- My Status
  local st_team = tonumber(post_id:match("^__team:status:(%d+)$") or "")
  if st_team then
    local my = pmem.teams.current
    local status = my.team and ("Team: ".._team_name(my.team).." - GP this month: "..tostring(my.gp or 0))
                             or  "You are not in a team."
    Net.message_player(pid, status)
    return true
  end

  -- Members list
  local list_team = tonumber(post_id:match("^__team:members:(%d+)$") or "")
  if list_team then
    _pending_open[pid] = { kind="members", team=list_team }
    _guard_next_two_closes(pid)
    pcall(Net.close_bbs, pid)
    return true
  end

  -- Back from members to team
  local back_team = tonumber(post_id:match("^__team:back:(%d+)$") or "")
  if back_team then
    _pending_open[pid] = { kind="team", team=back_team }
    _guard_next_two_closes(pid)
    pcall(Net.close_bbs, pid)
    return true
  end

  -- Claim Special Event Reward(s)
  if post_id == "__team:event_claim" then
    local secret2, pm = _pmem(pid)
    pm.teams.events_claimed = pm.teams.events_claimed or {}
    local claimed = pm.teams.events_claimed
    local active = Month.get_active_events()
    local gave_any = false

    for _, evt in ipairs(active) do
      if not claimed[evt.id] then
        Net.message_player(pid, "Event: "..(evt.name or "Special event"))
        local spec = evt.rewards or {}
        if spec.pack_pool and not spec.pack_name then
          spec = { pack_name = (evt.name or "Event").." Pack",
                   pack_rolls = spec.pack_rolls or 1,
                   pack_pool  = spec.pack_pool }
        end
        _grant_reward(pid, spec)
        claimed[evt.id] = true
        gave_any = true
      end
    end

    if ezmemory.set_player_memory then ezmemory.set_player_memory(secret2, pm) else ezmemory.save_player_memory(secret2, pm) end
    Net.message_player(pid, gave_any and "Special event reward claimed." or "No special event rewards available now.")
    return true
  end

  -- Claim Monthly Rewards
  if post_id == "__team:claim" then
    local secret2, pm2 = _pmem(pid)
    local _, tmem = _roll_month_if_needed()

    -- TEST MODE: pay out using CURRENT month rewards (DEFAULT + MONTHS[current])
    if TEST_ALWAYS_ALLOW_CLAIM then
      local rset_now = Month.get_rewards_for(tmem.month_key)
      Net.message_player(pid, "Test mode - Your team won!")
      _grant_reward(pid, rset_now.team_win)
      Net.message_player(pid, "Test mode - You were the highest scorer from your team!")
      _grant_reward(pid, rset_now.top_player)
      Net.message_player(pid, "Test mode - Losing team consolation.")
      _grant_reward(pid, rset_now.losing_team)
      return true
    end

    -- NORMAL: claim LAST month (DEFAULT + MONTHS[last])
    local prev = tmem.prev
    if not (prev and prev.month_key) then
      Net.message_player(pid, "No monthly rewards available yet.")
      return true
    end

    local month_key = prev.month_key
    local rset = Month.get_rewards_for(month_key)
    local min_win = tonumber(rset.min_gp_for_payout or 0)
    local min_con = tonumber(rset.min_gp_for_consolation or 0)

    pm2.teams.claimed[month_key] = pm2.teams.claimed[month_key] or { team=false, top=false, losing=false }
    local flags = pm2.teams.claimed[month_key]

    local hist = pm2.teams.hist and pm2.teams.hist[month_key]
    if not hist or not hist.team then
      Net.message_player(pid, "You were not on a team last month.")
      return true
    end

    local my_team = hist.team
    local my_gp   = tonumber(hist.gp or 0)
    local gave_any = false

    -- Team win reward
    if not flags.team then
      if prev.winner ~= 0 and my_team == prev.winner then
        if my_gp >= min_win then
          Net.message_player(pid, "Your team won last month!")
          _grant_reward(pid, rset.team_win)
          flags.team = true
          gave_any = true
        else
          Net.message_player(pid, "Your team won, but you only had "..my_gp.." GP (need "..min_win..").")
        end
      end
    end

    -- Losing team consolation (not on tie)
    if not flags.losing then
      if prev.winner ~= 0 and my_team ~= prev.winner and my_gp >= min_con then
        Net.message_player(pid, "Your team lost last month. Consolation reward:")
        _grant_reward(pid, rset.losing_team)
        flags.losing = true
        gave_any = true
      end
    end

    -- Top player reward (independent; can stack with either of the above)
    if not flags.top then
      local top = prev.top and prev.top[my_team]
      local me  = helpers.get_safe_player_secret(pid)
      if top and top.secret == me then
        Net.message_player(pid, "You were the highest scorer from your team last month!")
        _grant_reward(pid, rset.top_player)
        flags.top = true
        gave_any = true
      end
    end

    if ezmemory.set_player_memory then ezmemory.set_player_memory(secret2, pm2) else ezmemory.save_player_memory(secret2, pm2) end
    Net.message_player(pid, gave_any and "Rewards claimed!" or "No rewards available for you.")
    return true
  end

  if post_id == "__team:close" then pcall(Net.close_bbs, pid); return true end

  return false
end

local function _handle_scores_action(pid, post_id)
  if post_id == "__teamscores:close" then pcall(Net.close_bbs, pid); return true end
  return post_id:match("^__teamscores:") and true or false
end

-- =========================
-- ====== HOOK EVENTS  =====
-- =========================
if not _G.__TEAMS_WIRED then
  _G.__TEAMS_WIRED = true

  Net:on("object_interaction", function(ev)
    if ev.button ~= 0 then return end
    local pid = ev.player_id
    local area_id = Net.get_player_area(pid)
    local obj = area_id and Net.get_object_by_id(area_id, ev.object_id)
    if not obj then return end
    if obj.type == OBJ_TEAM_1 then _open_team_board(pid, 1)
    elseif obj.type == OBJ_TEAM_2 then _open_team_board(pid, 2)
    elseif obj.type == OBJ_SCORES then _open_scores_board(pid)
    end
  end)

  Net:on("post_selection", function(ev)
    local pid = ev.player_id
    local id  = tostring(ev.post_id or "")
    if id:match("^__team:") then
      _handle_team_action(pid, id)
    elseif id:match("^__teamscores:") then
      _handle_scores_action(pid, id)
    end
  end)

  Net:on("board_close", function(ev)
    local pid = ev.player_id
    local pending = _pending_open[pid]
    if not pending then return end
    _pending_open[pid] = nil
    if pending.kind == "members" then
      _open_members_board(pid, pending.team)
    elseif pending.kind == "team" then
      _open_team_board(pid, pending.team)
    elseif pending.kind == "scores" then
      _open_scores_board(pid)
    end
  end)
end

-- Hook into JobBBS: +1 GP on every successful job CLAIM (after JobBBS grants its reward).
do
  if JobBBS then
    local old = JobBBS.on_claim_reward
    JobBBS.on_claim_reward = function(pid, job)
      if old then pcall(old, pid, job) end
      _add_gp(pid, 1, "completing a Job")
    end
  end
end

-- Optional debug helper
function Teams.debug_add_gp(pid, n) _add_gp(pid, n or 1, "debug") end

return Teams
