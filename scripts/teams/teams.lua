-- /server/scripts/teams/teams.lua
-- Monthly two-team system with BBS boards + JobBBS hook
-- Area-memory backed (set TEAM_DATA_AREA_ID below).

local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local helpers  = require('scripts/ezlibs-scripts/helpers')

-- Optional JobBBS hook
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
-- IMPORTANT: this must be the area (map) where your team boards live.
-- "HomePage" is a good default for your setup. Change if needed.
local TEAM_DATA_AREA_ID = "teamshq"

-- Change team names here:
local TEAM_NAMES = {
  [1] = "Team Protoman",
  [2] = "Team Colonel",
}

-- Object types for map objects (A-button):
local OBJ_TEAM_1   = "Team1BBS"
local OBJ_TEAM_2   = "Team2BBS"
local OBJ_SCORES   = "TeamScoresBBS"

-- Last day (inclusive) of the month players may join a team (set to 31 for testing past the 14th)
local JOIN_WINDOW_LAST_DAY = 30

-- Testing toggle: allow unlimited team switching in the current month
local TEST_ALLOW_INFINITE_SWITCH = true

-- Payout requires at least this many GP on the winning team that month
local MIN_GP_FOR_PAYOUT = 5

-- Reward payloads (edit to taste)
local REWARDS = {
  team_win = {
    money = 10000,
    items = {
      -- { id = 123, qty = 1 },
    }
  },
  top_player = {
    money = 20000,
    items = {
      -- { id = 456, qty = 1 },
    }
  }
}

-- BBS colors
local TEAM_COLORS = {
  [1] = { r=220, g=70,  b=70  },
  [2] = { r=0,  g=88,  b=216 },
}
local COLOR_SCORE = { r=255, g=230, b=160 }

-- =========================
-- ====== UTILITIES  =======
-- =========================
local function _now() return os.time() end
local function _month_key(ts) return os.date("%Y-%m", ts or _now()) end
local function _day_of_month(ts) return tonumber(os.date("%d", ts or _now())) end

-- Robust totals and unique member counts
local function _sum_values(t)
  local s = 0
  for _, v in pairs(t or {}) do s = s + (tonumber(v) or 0) end
  return s
end

local function _union_len(a, b)
  local seen, n = {}, 0
  for k in pairs(a or {}) do if not seen[k] then seen[k] = true; n = n + 1 end end
  for k in pairs(b or {}) do if not seen[k] then seen[k] = true; n = n + 1 end end
  return n
end

-- =========================
-- ====== PERSISTENCE ======
-- =========================
-- mem (area): mem.teams = {
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
-- pmem.teams per player (by safe secret):
--   current = { team=1|2|nil, month="YYYY-MM", gp=0, last_switch_month="YYYY-MM" }
--   hist    = { ["YYYY-MM"] = { team=1|2, gp=N } }
--   claimed = { ["YYYY-MM"] = { team=true, top=true } }
--   last_name = "cached display name"

local function _amem()
  -- get area memory for the configured area
  local mem = ezmemory.get_area_memory(TEAM_DATA_AREA_ID)
  if not mem then
    -- If this prints, TEAM_DATA_AREA_ID is wrong. Set it to your hub area id.
    print("[teams] WARNING: get_area_memory returned nil for area", TEAM_DATA_AREA_ID)
    mem = {}
  end
  mem.teams = mem.teams or {}
  return mem, mem.teams
end

local function _save_area()
  -- save back to area storage
  if ezmemory.save_area_memory then
    ezmemory.save_area_memory(TEAM_DATA_AREA_ID)
  else
    -- some stacks auto-save; leave silent fallback
  end
end

local function _roll_month_if_needed()
  local mem, t = _amem()
  local now_key = _month_key()
  if t.month_key and t.month_key ~= now_key and t.month then
    local p1 = t.month[1] or { total=0, roster={}, gp_by_secret={} }
    local p2 = t.month[2] or { total=0, roster={}, gp_by_secret={} }
    local function top_of(tb)
      local best_s, best_gp = nil, -1
      for s,gp in pairs(tb.gp_by_secret or {}) do
        if gp > best_gp then best_gp, best_s = gp, s end
      end
      return best_s, best_gp
    end
    local s1,g1 = top_of(p1); local s2,g2 = top_of(p2)
    t.prev = {
      month_key = t.month_key,
      totals    = { [1]=p1.total or 0, [2]=p2.total or 0 },
      roster    = {
        [1]=_union_len(p1.roster, p1.gp_by_secret),
        [2]=_union_len(p2.roster, p2.gp_by_secret),
      },
      top       = { [1]={secret=s1, gp=g1 or 0}, [2]={secret=s2, gp=g2 or 0} },
      winner    = ((p1.total or 0) == (p2.total or 0)) and 0 or (((p1.total or 0) > (p2.total or 0)) and 1 or 2),
    }
  end
  if t.month_key ~= now_key or not t.month then
    t.month_key = now_key
    t.month     = {
      [1] = { total=0, roster={}, gp_by_secret={} },
      [2] = { total=0, roster={}, gp_by_secret={} },
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
    pmem.teams.current = { team = cur.team, month = _month_key(), gp = 0, last_switch_month = cur.last_switch_month }
  end
  pmem.teams.claimed = pmem.teams.claimed or {}
  if ezmemory.set_player_memory then ezmemory.set_player_memory(secret, pmem) else ezmemory.save_player_memory(secret, pmem) end
  return secret, pmem
end

-- =========================
-- ====== NAME CACHE  ======
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
  -- also stash in pmem so we can fallback if needed
  local pm = ezmemory.get_player_memory(secret) or {}
  pm.teams = pm.teams or {}
  pm.teams.last_name = name
  if ezmemory.set_player_memory then ezmemory.set_player_memory(secret, pm) else ezmemory.save_player_memory(secret, pm) end
  _save_area()
end

-- Sync this player's per-player data into the team area memory (current month).
local function _sync_self_into_area(pid)
  local mem, t_mem = _roll_month_if_needed()
  local secret, pmem = _pmem(pid)
  local cur = pmem.teams.current
  if not cur or not cur.team then return end

  local slot1 = t_mem.month[1] or { gp_by_secret = {}, roster = {} }
  local slot2 = t_mem.month[2] or { gp_by_secret = {}, roster = {} }
  local g1 = tonumber(slot1.gp_by_secret[secret] or 0)
  local g2 = tonumber(slot2.gp_by_secret[secret] or 0)

  -- If this player already has any GP logged in either team, DO NOT mirror totals.
  if (g1 > 0) or (g2 > 0) then
    -- still keep roster + name fresh for the team they are currently on
    (t_mem.month[cur.team].roster)[secret] = true
    _remember_name(pid, secret)
    _save_area()
    return
  end

  -- One-time migration path (for old data before area storage existed)
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
-- ====== CORE  ============
-- =========================
local function _add_to_roster(t_mem, team, secret)
  local slot = t_mem.month[team]
  slot.roster[secret] = true
end

local function _remove_from_roster(t_mem, team, secret)
  local slot = t_mem.month[team]
  if slot then slot.roster[secret] = nil end
end

local function _grant_reward(pid, spec)
  if not spec then return end
  if spec.money and spec.money ~= 0 then
    local ok = pcall(ezmemory.spend_player_money, pid, -math.floor(tonumber(spec.money) or 0))
    if not ok then
      local secret = helpers.get_safe_player_secret(pid)
      local pm     = ezmemory.get_player_memory(secret) or {}
      pm.money = math.max(0, (tonumber(pm.money) or 0) + math.floor(tonumber(spec.money) or 0))
      if ezmemory.set_player_memory then ezmemory.set_player_memory(secret, pm) else ezmemory.save_player_memory(secret, pm) end
    end
  end
  if spec.items then
    local area_id = Net.get_player_area(pid)
    for _, it in ipairs(spec.items) do
      local id  = it.id; local qty = it.qty or 1
      for i=1,qty do pcall(ezmemory.give_item_with_optional_notify, pid, area_id, id, nil, true) end
    end
  end
  if Net.play_sound_for_player then pcall(Net.play_sound_for_player, pid, '/server/assets/ezlibs-assets/sfx/item_get.ogg') end
end

-- Add GP to player and team (writes to TEAM_DATA_AREA_ID)
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

-- Consume two closes from custom.lua
local function _guard_next_two_closes(pid)
  if _G._guard_ignore_next_close then
    _G._guard_ignore_next_close(pid, "teams")
    _G._guard_ignore_next_close(pid, "teams")
  end
end

-- Deferred open after close
local _pending_open = {}  -- [pid] = { kind="members"|"team"|"scores", team=number|nil }

-- Build main Team board posts
local function _team_posts(pid, team)
  _roll_month_if_needed()
  local _, pmem = _pmem(pid)
  local cur = pmem.teams.current

  local is_member   = (cur.team == team)
  local day         = _day_of_month()
  local last_day    = (JOIN_WINDOW_LAST_DAY or 14)
  local can_join    = (not cur.team) and (day >= 1 and day <= last_day)
  local can_switch  = (cur.team ~= nil)
                      and (cur.team ~= team)
                      and (TEST_ALLOW_INFINITE_SWITCH or (cur.last_switch_month ~= _month_key()))

  local label
  if is_member then
    label = "Current Team"
  elseif cur.team then
    label = "Switch Team"
  else
    label = "Join Team"
  end

  local author = ""
  if (not is_member) and (not can_join) and (not can_switch) then
    author = "(Locked)"
  end

  local posts = {
    { id="__team:join:"..team,    read=true, title=label,                    author=author },
    { id="__team:checkin:"..team, read=true, title="Daily Check-In (+1 GP)", author=""     },
    { id="__team:status:"..team,  read=true, title="My Status",              author=""     },
    { id="__team:members:"..team, read=true, title="Members List",           author=""     },
    { id="__team:claim",          read=true, title="Claim Monthly Rewards",  author=""     },
    { id="__team:close",          read=true, title="Close",                  author=""     },
  }
  return posts
end

local function _open_team_board(pid, team)
  _roll_month_if_needed()
  local title = string.format("%s - %s", "Team Board", _team_name(team))
  local posts = _team_posts(pid, team)
  local color = (TEAM_COLORS and TEAM_COLORS[team]) or COLOR_TEAM
  _sync_self_into_area(pid)
  _sanitize_posts(posts)
  _guard_next_two_closes(pid)
  Net.open_board(pid, title, color, posts)
end

-- Build and open the Members scoreboard board
local function _open_members_board(pid, team)
  _sync_self_into_area(pid)
  local mem, t_mem = _roll_month_if_needed()
  local slot = t_mem.month[team] or { roster={}, gp_by_secret={} }
  local color = (TEAM_COLORS and TEAM_COLORS[team]) or COLOR_TEAM

  -- Build rows from CURRENT ROSTER ONLY (no union with gp_by_secret)
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

local function _count_keys(tbl)
  local n = 0
  for _ in pairs(tbl or {}) do n = n + 1 end
  return n
end

local function _open_scores_board(pid)
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
    if cur.team ~= chk_team then Net.message_player(pid, "Join this team first."); return true end
    pmem.teams._last_checkin = pmem.teams._last_checkin or ""
    local today = os.date("%Y-%m-%d", _now())
    if pmem.teams._last_checkin == today then
      Net.message_player(pid, "Already checked in today.")
    else
      pmem.teams._last_checkin = today
      if ezmemory.set_player_memory then ezmemory.set_player_memory(secret, pmem) else ezmemory.save_player_memory(secret, pmem) end
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

  -- Members: open scoreboard board (defer)
  local list_team = tonumber(post_id:match("^__team:members:(%d+)$") or "")
  if list_team then
    _pending_open[pid] = { kind="members", team=list_team }
    _guard_next_two_closes(pid)
    pcall(Net.close_bbs, pid)
    return true
  end

  -- Back from members list to team board (defer)
  local back_team = tonumber(post_id:match("^__team:back:(%d+)$") or "")
  if back_team then
    _pending_open[pid] = { kind="team", team=back_team }
    _guard_next_two_closes(pid)
    pcall(Net.close_bbs, pid)
    return true
  end

  -- Claim Monthly Rewards
  if post_id == "__team:claim" then
    local _, tmem = _roll_month_if_needed()
    local prev = tmem.prev
    if not (prev and prev.month_key) then Net.message_player(pid, "No monthly rewards available yet."); return true end

    local month_key = prev.month_key
    pmem.teams.claimed[month_key] = pmem.teams.claimed[month_key] or { team=false, top=false }
    local flags = pmem.teams.claimed[month_key]

    local hist = pmem.teams.hist and pmem.teams.hist[month_key]
    if not hist or not hist.team then
      Net.message_player(pid, "You were not on a team last month.")
      return true
    end

    local gave_any = false

    -- Team win reward (requires MIN_GP_FOR_PAYOUT)
    if not flags.team then
      if prev.winner ~= 0 and hist.team == prev.winner and (hist.gp or 0) >= MIN_GP_FOR_PAYOUT then
        _grant_reward(pid, REWARDS.team_win); flags.team = true; gave_any = true
      end
    end

    -- Top-player reward (per-team)
    if not flags.top then
      local top = prev.top and prev.top[hist.team]
      if top and top.secret == secret then
        _grant_reward(pid, REWARDS.top_player); flags.top = true; gave_any = true
      end
    end

    if ezmemory.set_player_memory then ezmemory.set_player_memory(secret, pmem) else ezmemory.save_player_memory(secret, pmem) end
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

function Teams.debug_add_gp(pid, n) _add_gp(pid, n or 1, "debug") end

return Teams
