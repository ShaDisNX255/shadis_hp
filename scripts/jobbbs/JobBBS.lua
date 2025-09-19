-- scripts/jobbbs/JobBBS.lua
-- Multi-board JobBBS with daily per-board random jobs (1 per category),
-- baseline-aware tracking, and rewards (money/items) on claim.
--
-- Notes:
-- • Each JobBBS object can have its own "board name" (we read the object's name).
-- • Per-player state persists via ezmemory under mem.jobbbs.
-- • Per-board state lives in st.boards[board_id] (accepted/claimed/jobs for today).
-- • Progress (visited areas, NPCs, viruses, duels, packs) is shared, but each job
--   uses its own baseline snapshot taken on acceptance, so multiple boards won't
--   interfere with each other.
-- • We choose 1 random job per category per board/day deterministically based on
--   (player_name, board_id, date, category).

local helpers  = require('scripts/ezlibs-scripts/helpers')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')

local JobBBS = {}

-- Debug toggle
local DEBUG = true
local function dbg(...)
  if DEBUG then print('[jobbbs]', ...) end
end

-- ===== UI Tunables =====
local DEFAULT_BOARD_TITLE = 'Job BBS'
local COLOR_BOARD         = { r=120, g=200, b=255 }
local MAX_TITLE_CH        = 28   -- keep one-line titles short
local MAX_AUTHOR_CH       = 18

-- ===== Persistence (ezmemory) =====
local function _mem(pid)
  local secret = helpers.get_safe_player_secret(pid)
  return ezmemory.get_player_memory(secret) or {}
end

local function _snapshot(st)
  return {
    day_key  = st.day_key,
    prog     = st.prog     or {},
    boards   = st.boards   or {},
  }
end

local function save_mem(pid, st)
  local mem = _mem(pid)
  mem.jobbbs = _snapshot(st)
  -- If your ezmemory build needs an explicit save, call it here.
end

local function load_mem_into_state(pid, st)
  local mem = _mem(pid)
  local slot = mem.jobbbs
  if type(slot) == 'table' then
    st.day_key = slot.day_key or st.day_key
    st.prog    = slot.prog    or {}
    st.boards  = slot.boards  or {}
  end
end

-- ===== Helpers =====
local function trunc(s, n)
  s = tostring(s or '')
  if #s <= n then return s end
  if n < 4 then return s:sub(1, n) end
  return s:sub(1, n-3)..'...'
end

local function wrap(txt, width)
  txt = tostring(txt or '')
  local NL = string.char(10)
  local CR = string.char(13)
  txt = txt:gsub(CR..NL, NL):gsub(CR, NL)
  local out = {}
  for line in (txt..NL):gmatch('(.-)'..NL) do
    local s = line
    while #s > width do
      local cut = s:sub(1, width)
      local p = cut:match('^(.*)%s+') or cut
      out[#out+1] = p
      s = s:sub(#p + 2)
    end
    out[#out+1] = s
  end
  return out
end

local function safe_id(s)
  s = tostring(s or '')
  s = s:gsub('%s+', ' '):gsub('^%s*(.-)%s*$', '%1')
  s = s:gsub('[^%w%-%._ ]', '_')
  return s
end

-- Deterministic pick: FNV-1a32 hash
local function fnv1a32(str)
  local hash = 2166136261
  for i = 1, #str do
    hash = hash ~ str:byte(i)
    -- 32-bit multiply by FNV prime 16777619
    hash = (hash * 16777619) % 4294967296
  end
  return hash
end

local function pick_deterministic(keys, seed)
  local n = #keys
  if n <= 1 then return keys[1] end
  local h = fnv1a32(seed)
  local idx = (h % n) + 1
  return keys[idx]
end

-- Map job id -> tracking category (for gating progress until accept)
local function job_category(job_id)
  if not job_id then return nil end
  if job_id:match('^visit')   then return 'visit'   end
  if job_id:match('^npc')     then return 'npc'     end
  if job_id:match('^inspect') then return 'inspect' end
  if job_id:match('^virus')   then return 'virus'   end
  if job_id:match('^duel')    then return 'duel'    end
  if job_id:match('^pack')    then return 'pack'    end
  return nil
end

-- Activate a category on first acceptance; clears pre-accept progress so it starts fresh
local function activate_category(st, cat)
  st.prog = st.prog or {}
  st.prog.active = st.prog.active or {}
  if st.prog.active[cat] then return end
  st.prog.active[cat] = true
end

-- Helpers for baselines
local function copy_set(src)
  local dst = {}
  if src then for k,v in pairs(src) do if v then dst[k]=true end end end
  return dst
end

local function count_diff(current, baseline)
  local c=0
  if current then
    for k in pairs(current) do if not (baseline and baseline[k]) then c=c+1 end end
  end
  return c
end

-- ===== Per-player state =====
-- st fields: day_key, prog={visited/spoke_npcs/objects/obj_areas, virus, duel, pack, active, baseline},
--            boards[board_id] = { accepted, claimed, job_ids, awaiting_kind, awaiting_idx }
local S = rawget(_G, '__JOBBBS_STATE__')
if not S or type(S) ~= 'table' then
  S = { by_pid = {}, by_key = {} }
  _G.__JOBBBS_STATE__ = S
end
local function player_key(pid)
  return 'pid:'..tostring(pid)
end

-- Unify any old name-keyed state into the PID key
local function attach_state(pid)
  local st = S.by_pid[pid]
  if st then return st end

  local pid_key = 'pid:'..tostring(pid)

  -- If you previously stored by name, pull that table and alias it
  local name, name_key
  if _G.Net and Net.get_player_name then
    pcall(function() name = Net.get_player_name(pid) end)
  end
  if name and name ~= '' then name_key = 'name:'..tostring(name) end

  st = S.by_key[pid_key] or (name_key and S.by_key[name_key]) or nil
  if not st then
    st = { day_key = os.date('%Y-%m-%d'), prog={}, boards={} }
    load_mem_into_state(pid, st)
  end

  S.by_key[pid_key] = st
  if name_key then S.by_key[name_key] = st end -- optional alias for backwards compat
  S.by_pid[pid] = st
  return st
end

-- Daily reset helpers
local function today_key()
  return os.date('%Y-%m-%d')
end

local function ensure_daily_reset(pid)
  local st = attach_state(pid)
  local today = os.date('%Y-%m-%d')
  st.day_key = st.day_key or today
  if st.day_key ~= today then
    st.day_key = today
    st.prog = st.prog or {}

    -- keep these: they reset job snapshots and gates
    st.prog.baseline = {}
    st.prog.active   = {}

    -- NEW: reset per-day unique sets so “visit/talk/inspect today” starts fresh
    st.prog.visited    = {}
    st.prog.spoke_npcs = {}
    st.prog.objects    = {}
    st.prog.obj_areas  = {}

    save_mem(pid, st)
    if dbg then dbg('daily reset -> cleared per-day sets', pid, today) end
  end
end

-- ===== Rewards =====
local REWARDS = {
  visit3         = { money=30000 },
  visit4         = { money=40000 },
  visit5         = { money=50000 },
  visit6         = { money=60000 },
  visit7         = { money=70000 },
  visit8         = { money=80000 },
  visit9         = { money=90000 },
  visit10        = { money=100000 },
  visit11        = { money=110000 },
  visit12        = { money=120000 },
  visit13        = { money=200000 },
  npc3           = { money=40000 },
  npc6           = { money=60000 },
  npc9           = { money=90000 },
  npc12          = { money=120000 },
  inspect3       = { money=40000 },
  inspect6       = { money=60000 },
  inspect9       = { money=90000 },
  inspect12      = { money=120000 },
  inspect_area3  = { money=60000 },
  inspect_area6  = { money=100000 },
  inspect_area9  = { money=140000 },
  inspect_area12 = { money=200000  },
  virus_clear3   = { money=40000 },
  virus_clear6   = { money=60000 },
  virus_clear9   = { money=90000 },
  virus_clear12   = { money=120000 },
  virus_run3     = { money=7000 },
  virus_run6     = { money=15000 },
  virus_run9     = { money=23000 },
  virus_run12     = { money=30000 },
  virus_bust8_3  = { money=60000 },
  virus_bust8_6  = { money=100000 },
  virus_bust8_9  = { money=140000 },
  virus_bust8_12  = { money=200000 },
  virus_turn1_3  = { money=40000 },
  virus_turn1_6  = { money=60000 },
  virus_turn1_9  = { money=90000 },
  virus_turn1_12  = { money=120000 },
  virus_fast3    = { money=60000 },
  virus_fast6    = { money=100000 },
  virus_fast9    = { money=140000 },
  virus_fast12    = { money=200000 },
  duel_win1      = { money=40000 },
  duel_win2      = { money=60000 },
  duel_win3      = { money=90000 },
  pack_open1     = { money=60000 },
  pack_open10    = { money=140000 },
}

local function give_money(pid, amount)
  amount = math.floor(tonumber(amount) or 0)
  if amount == 0 then return end
  local ok = false
  -- match WCity1.lua behavior
  if ezmemory.spend_player_money then
    ok = pcall(ezmemory.spend_player_money, pid, -amount)
  end
  if not ok then
    local mem = _mem(pid)
    mem.money = math.max(0, (tonumber(mem.money) or 0) + amount)
  end
  Net.message_player(pid, string.format('Got $%d!', amount))
  if Net.play_sound_for_player then
    pcall(Net.play_sound_for_player, pid, '/server/assets/ezlibs-assets/sfx/item_get.ogg')
  end
end

local function give_item(pid, item_id, qty)
  qty = math.floor(tonumber(qty) or 1)
  if qty <= 0 then return end
  if ezmemory.give_item_with_optional_notify then
    local area_id = Net.get_player_area(pid)
    -- We don't have the info table here; give_item_with_optional_notify can accept nil info in your build, or we silently update mem.items as fallback
    local ok = pcall(ezmemory.give_item_with_optional_notify, pid, area_id, item_id, nil, true)
    if ok then return end
  end
  -- fallback: directly bump mem.items
  local mem = _mem(pid)
  mem.items = mem.items or {}
  local k = tostring(item_id)
  mem.items[k] = (tonumber(mem.items[k]) or 0) + qty
  Net.message_player(pid, string.format('Received item %s x%d', tostring(item_id), qty))
end

JobBBS.on_claim_reward = function(pid, job)
  local spec = REWARDS[job.id] or { money = 200 }
  if spec.money then give_money(pid, spec.money) end
  if spec.item then
    if type(spec.item) == 'table' then
      for _, t in ipairs(spec.item) do give_item(pid, t.id, t.qty or 1) end
    else
      give_item(pid, spec.item, spec.qty or 1)
    end
  end
end

-- ===== Job pool (definitions) =====
-- Each check accepts (pid, st, baseline_key)
local function jobs_pool()
  local P = {}
  local function J(id, title, poster, desc, check)
    P[id] = { id=id, title=title, poster=poster, desc=desc, check=check }
  end

  -- Visit
  J('visit3', 'Explorer', 'ShaDisNX', 'LVL1: Here is an easy one, visit 3 different areas today.',
    function(pid, st, base_key)
      st.prog.visited = st.prog.visited or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].visited or nil
      local n = count_diff(st.prog.visited, base)
      return n>=3, n, 3
    end)
  J('visit4', 'Explorer', 'ShaDisNX', 'LVL2: Here is an easy one, visit 4 different areas today.',
    function(pid, st, base_key)
      st.prog.visited = st.prog.visited or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].visited or nil
      local n = count_diff(st.prog.visited, base)
      return n>=4, n, 4
    end)
  J('visit5', 'Explorer', 'ShaDisNX', 'LVL3: Here is an easy one, visit 5 different areas today.',
    function(pid, st, base_key)
      st.prog.visited = st.prog.visited or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].visited or nil
      local n = count_diff(st.prog.visited, base)
      return n>=5, n, 5
    end)
  J('visit6', 'Adventurer', 'ShaDisNX', 'LVL1: I see, lookig for a challenge are we? Visit 6 different areas today.',
    function(pid, st, base_key)
      st.prog.visited = st.prog.visited or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].visited or nil
      local n = count_diff(st.prog.visited, base)
      return n>=6, n, 6
    end)
  J('visit7', 'Adventurer', 'ShaDisNX', 'LVL2: I see, lookig for a challenge are we? Visit 7 different areas today.',
    function(pid, st, base_key)
      st.prog.visited = st.prog.visited or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].visited or nil
      local n = count_diff(st.prog.visited, base)
      return n>=7, n, 7
    end)
  J('visit8', 'Adventurer', 'ShaDisNX', 'LVL3: I see, lookig for a challenge are we? Visit 8 different areas today.',
    function(pid, st, base_key)
      st.prog.visited = st.prog.visited or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].visited or nil
      local n = count_diff(st.prog.visited, base)
      return n>=8, n, 8
    end)
  J('visit9', 'Adventurer', 'ShaDisNX', 'LVL MAX: I see, lookig for a challenge are we? Visit 9 different areas today.',
    function(pid, st, base_key)
      st.prog.visited = st.prog.visited or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].visited or nil
      local n = count_diff(st.prog.visited, base)
      return n>=9, n, 9
    end)
  J('visit10', 'Pioneer', 'ShaDisNX', 'LVL1: Only for the most determined, visit 10 different areas today.',
    function(pid, st, base_key)
      st.prog.visited = st.prog.visited or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].visited or nil
      local n = count_diff(st.prog.visited, base)
      return n>=10, n, 10
    end)
  J('visit11', 'Pioneer', 'ShaDisNX', 'LVL2: Only for the most determined, visit 11 different areas today.',
    function(pid, st, base_key)
      st.prog.visited = st.prog.visited or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].visited or nil
      local n = count_diff(st.prog.visited, base)
      return n>=11, n, 11
    end)
  J('visit12', 'Pioneer', 'ShaDisNX', 'LVL3: Only for the most determined, visit 12 different areas today.',
    function(pid, st, base_key)
      st.prog.visited = st.prog.visited or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].visited or nil
      local n = count_diff(st.prog.visited, base)
      return n>=12, n, 12
    end)
  J('visit13', 'Pioneer', 'ShaDisNX', 'LVL MAX: The hardest task of all, visit every area available in ShaDisHP. 13 Areas in total.',
    function(pid, st, base_key)
      st.prog.visited = st.prog.visited or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].visited or nil
      local n = count_diff(st.prog.visited, base)
      return n>=13, n, 13
    end)

  -- NPC
  J('npc3', 'Socializer', 'Mr. Prog', 'LVL1: Talk to 3 NPCs today',
    function(pid, st, base_key)
      st.prog.spoke_npcs = st.prog.spoke_npcs or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].spoke_npcs or nil
      local c = count_diff(st.prog.spoke_npcs, base); return c>=3, c, 3
    end)
  J('npc6', 'Socializer', 'Mr. Prog', 'LVL2: Talk to 6 NPCs today',
    function(pid, st, base_key)
      st.prog.spoke_npcs = st.prog.spoke_npcs or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].spoke_npcs or nil
      local c = count_diff(st.prog.spoke_npcs, base); return c>=6, c, 6
    end)
  J('npc9', 'Socializer', 'Mr. Prog', 'LVL3: Talk to 9 NPCs today',
    function(pid, st, base_key)
      st.prog.spoke_npcs = st.prog.spoke_npcs or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].spoke_npcs or nil
      local c = count_diff(st.prog.spoke_npcs, base); return c>=9, c, 9
    end)
  J('npc12', 'Socializer', 'Mr. Prog', 'LVL MAX: Talk to 12 NPCs today',
    function(pid, st, base_key)
      st.prog.spoke_npcs = st.prog.spoke_npcs or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].spoke_npcs or nil
      local c = count_diff(st.prog.spoke_npcs, base); return c>=12, c, 12
    end)

  -- Inspect
  J('inspect3', 'Inspector', 'LuigiEXE', 'LVL1: Inspect 3 different objects.',
    function(pid, st, base_key)
      st.prog.objects = st.prog.objects or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].objects or nil
      local c = count_diff(st.prog.objects, base); return c>=3, c, 3
    end)
  J('inspect6', 'Inspector', 'LuigiEXE', 'LVL2: Inspect 6 different objects.',
    function(pid, st, base_key)
      st.prog.objects = st.prog.objects or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].objects or nil
      local c = count_diff(st.prog.objects, base); return c>=6, c, 6
    end)
  J('inspect9', 'Inspector', 'LuigiEXE', 'LVL3: Inspect 9 different objects.',
    function(pid, st, base_key)
      st.prog.objects = st.prog.objects or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].objects or nil
      local c = count_diff(st.prog.objects, base); return c>=9, c, 9
    end)
  J('inspect12', 'Inspector', 'LuigiEXE', 'LVL MAX: Inspect 12 different objects.',
    function(pid, st, base_key)
      st.prog.objects = st.prog.objects or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].objects or nil
      local c = count_diff(st.prog.objects, base); return c>=12, c, 12
    end)
  J('inspect_area3', 'Curious', 'LuigiEXE', 'LVL1: Inspect objects in 3 different areas.',
    function(pid, st, base_key)
      st.prog.obj_areas = st.prog.obj_areas or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].obj_areas or nil
      local c = count_diff(st.prog.obj_areas, base); return c>=3, c, 3
    end)
  J('inspect_area6', 'Curious', 'LuigiEXE', 'LVL2: Inspect objects in 6 different areas.',
    function(pid, st, base_key)
      st.prog.obj_areas = st.prog.obj_areas or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].obj_areas or nil
      local c = count_diff(st.prog.obj_areas, base); return c>=6, c, 6
    end)
  J('inspect_area9', 'Curious', 'LuigiEXE', 'LVL3: Inspect objects in 9 different areas.',
    function(pid, st, base_key)
      st.prog.obj_areas = st.prog.obj_areas or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].obj_areas or nil
      local c = count_diff(st.prog.obj_areas, base); return c>=9, c, 9
    end)
  J('inspect_area12', 'Curious', 'LuigiEXE', 'LVL MAX: Inspect objects in all the different areas available in ShaDisHP. 13 in total.',
    function(pid, st, base_key)
      st.prog.obj_areas = st.prog.obj_areas or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].obj_areas or nil
      local c = count_diff(st.prog.obj_areas, base); return c>=13, c, 13
    end)

  -- Virus
  J('virus_clear3', 'NetBattler', 'ProtoMan', 'LV1: Defeat 3 virus encounters.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.clears or 0; local n = math.max(0, cur - ((base and base.clears) or 0)); return n>=3, n, 3
    end)
  J('virus_clear6', 'NetBattler', 'ProtoMan', 'LV2: Defeat 6 virus encounters.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.clears or 0; local n = math.max(0, cur - ((base and base.clears) or 0)); return n>=6, n, 6
    end)
  J('virus_clear9', 'NetBattler', 'ProtoMan', 'LV3: Defeat 9 virus encounters.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.clears or 0; local n = math.max(0, cur - ((base and base.clears) or 0)); return n>=9, n, 9
    end)
  J('virus_clear12', 'NetBattler', 'ProtoMan', 'LVL MAX: Defeat 12 virus encounters.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.clears or 0; local n = math.max(0, cur - ((base and base.clears) or 0)); return n>=12, n, 12
    end)
  J('virus_run3', 'RUN', 'LuigiEXE', 'LV1: Run from 3 virus encounters.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.runs or 0; local n = math.max(0, cur - ((base and base.runs) or 0)); return n>=3, n, 3
    end)
  J('virus_run6', 'RUN', 'LuigiEXE', 'LV2: Run from 6 virus encounters.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.runs or 0; local n = math.max(0, cur - ((base and base.runs) or 0)); return n>=6, n, 6
    end)
  J('virus_run9', 'RUN', 'LuigiEXE', 'LV3: Run from 9 virus encounters.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.runs or 0; local n = math.max(0, cur - ((base and base.runs) or 0)); return n>=9, n, 9
    end)
  J('virus_run12', 'RUN', 'LuigiEXE', 'LVL MAX: Run from 12 virus encounters.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.runs or 0; local n = math.max(0, cur - ((base and base.runs) or 0)); return n>=12, n, 12
    end)
  J('virus_bust8_3', 'Ace NetOp', 'ProtoMan', 'LV1: Delete 3 virus encounters with a busting LV of 8 or more.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.bust8 or 0; local n = math.max(0, cur - ((base and base.bust8) or 0)); return n>=3, n, 3
    end)
  J('virus_bust8_6', 'Ace NetOp', 'ProtoMan', 'LV2: Delete 6 virus encounters with a busting LV of 8 or more.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.bust8 or 0; local n = math.max(0, cur - ((base and base.bust8) or 0)); return n>=6, n, 6
    end)
  J('virus_bust8_9', 'Ace NetOp', 'ProtoMan', 'LV3: Delete 9 virus encounters with a busting LV of 8 or more.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.bust8 or 0; local n = math.max(0, cur - ((base and base.bust8) or 0)); return n>=9, n, 9
    end)
  J('virus_bust8_12', 'Ace NetOp', 'ProtoMan', 'LVL MAX: Delete 12 virus encounters with a busting LV of 8 or more.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.bust8 or 0; local n = math.max(0, cur - ((base and base.bust8) or 0)); return n>=12, n, 12
    end)
  J('virus_turn1_3', 'Ace Navi', 'ProtoMan', 'LV1: Delete 3 virus encounters in 1 turn.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.turn1 or 0; local n = math.max(0, cur - ((base and base.turn1) or 0)); return n>=3, n, 3
    end)
  J('virus_turn1_6', 'Ace Navi', 'ProtoMan', 'LV2: Delete 6 virus encounters in 1 turn.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.turn1 or 0; local n = math.max(0, cur - ((base and base.turn1) or 0)); return n>=6, n, 6
    end)
  J('virus_turn1_9', 'Ace Navi', 'ProtoMan', 'LV3: Delete 9 virus encounters in 1 turn.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.turn1 or 0; local n = math.max(0, cur - ((base and base.turn1) or 0)); return n>=9, n, 9
    end)
  J('virus_turn1_12', 'Ace Navi', 'ProtoMan', 'LVL MAX: Delete 12 virus encounters in 1 turn.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.turn1 or 0; local n = math.max(0, cur - ((base and base.turn1) or 0)); return n>=12, n, 12
    end)
  J('virus_fast3', 'Speedster', 'ProtoMan', 'LV1: Delete 3 virus encounters in 10s or less.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.fast or 0; local n = math.max(0, cur - ((base and base.fast) or 0)); return n>=3, n, 3
    end)
  J('virus_fast6', 'Speedster', 'ProtoMan', 'LV2: Delete 6 virus encounters in 10s or less.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.fast or 0; local n = math.max(0, cur - ((base and base.fast) or 0)); return n>=6, n, 6
    end)
  J('virus_fast9', 'Speedster', 'ProtoMan', 'LV3: Delete 9 virus encounters in 10s or less.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.fast or 0; local n = math.max(0, cur - ((base and base.fast) or 0)); return n>=9, n, 9
    end)
  J('virus_fast12', 'Speedster', 'ProtoMan', 'LVL MAX: Delete 12 virus encounters in 10s or less.',
    function(pid, st, base_key)
      st.prog.virus = st.prog.virus or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].virus or nil
      local cur = st.prog.virus.fast or 0; local n = math.max(0, cur - ((base and base.fast) or 0)); return n>=12, n, 12
    end)

  -- Duel
  J('duel_win1', 'Duelist', 'DuelProg', 'LV1: Win 1 YGO Duel.',
    function(pid, st, base_key)
      st.prog.duel = st.prog.duel or { wins = 0 }
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].duel or nil
      local cur = st.prog.duel.wins or 0; local n = math.max(0, cur - ((base and base.wins) or 0)); return n>=1, n, 1
    end)
  J('duel_win2', 'Duelist', 'DuelProg', 'LV2: Win 2 YGO Duels.',
    function(pid, st, base_key)
      st.prog.duel = st.prog.duel or { wins = 0 }
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].duel or nil
      local cur = st.prog.duel.wins or 0; local n = math.max(0, cur - ((base and base.wins) or 0)); return n>=2, n, 2
    end)
  J('duel_win3', 'Duelist', 'DuelProg', 'LVL MAX: Win 3 YGO Duels.',
    function(pid, st, base_key)
      st.prog.duel = st.prog.duel or { wins = 0 }
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].duel or nil
      local cur = st.prog.duel.wins or 0; local n = math.max(0, cur - ((base and base.wins) or 0)); return n>=3, n, 3
    end)

  -- Pack
  J('pack_open1', 'First Pack', 'Card Shop', 'Open 1 booster pack.',
    function(pid, st, base_key)
      st.prog.pack = st.prog.pack or { opened = 0 }
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].pack or nil
      local cur = st.prog.pack.opened or 0; local n = math.max(0, cur - ((base and base.opened) or 0)); return n>=1, n, 1
    end)
  J('pack_open10', 'Booster Binge', 'Card Shop', 'Open 10 booster packs.',
    function(pid, st, base_key)
      st.prog.pack = st.prog.pack or { opened = 0 }
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].pack or nil
      local cur = st.prog.pack.opened or 0; local n = math.max(0, cur - ((base and base.opened) or 0)); return n>=10, n, 10
    end)

  -- Categorize ids
  local CATS = {
    visit   = { 'visit3', 'visit4', 'visit5', 'visit6', 'visit7', 'visit8', 'visit9', 'visit10', 'visit11', 'visit12', 'visit13' },
    npc     = { 'npc3', 'npc6', 'npc9', 'npc12' },
    inspect = { 'inspect3', 'inspect6', 'inspect9', 'inspect12', 'inspect_area3', 'inspect_area6', 'inspect_area9', 'inspect_area12' },
    virus   = { 'virus_clear3', 'virus_clear6', 'virus_clear9', 'virus_clear12', 'virus_run3', 'virus_run6', 'virus_run9', 'virus_run12', 'virus_bust8_3', 'virus_bust8_6', 'virus_bust8_9', 'virus_bust8_12',
	'virus_turn1_3', 'virus_turn1_6', 'virus_turn1_9', 'virus_turn1_12', 'virus_fast3', 'virus_fast6', 'virus_fast9', 'virus_fast12' },
    duel    = { 'duel_win1', 'duel_win2', 'duel_win3' },
    pack    = { 'pack_open1', 'pack_open10' },
  }
  return P, CATS
end

-- ===== Board helpers =====
local function get_board(st, board_id)
  st.boards = st.boards or {}
  local B = st.boards[board_id]
  if not B then
    B = { accepted={}, claimed={}, job_ids=nil, awaiting_kind=nil, awaiting_idx=nil }
    st.boards[board_id] = B
  end
  return B
end

-- Find whichever board is currently awaiting a Yes/No for this player
local function find_waiting_board(st)
  if not st or not st.boards then return nil, nil end
  for bid, B in pairs(st.boards) do
    if B and B.awaiting_kind ~= nil and B.awaiting_idx ~= nil then
      return bid, B
    end
  end
  return nil, nil
end

local function ensure_jobs_for_today(pid, st, board_id)
  local B = get_board(st, board_id)
  if B.job_ids and B.day_key == st.day_key then return B end
  local pool, cats = jobs_pool()
  local order = { 'visit','npc','inspect','virus','duel','pack' }
  local ids = {}
  for _, cat in ipairs(order) do
    local list = cats[cat]
    local seed = table.concat({ player_key(pid), st.day_key, board_id, cat }, '|')
    ids[#ids+1] = pick_deterministic(list, seed)
  end
  B.job_ids = ids
  B.day_key = st.day_key
  return B
end

-- ===== Passive progress listeners =====
if _G.Net and Net.on and not _G.__jobbbs_hooks_move_talk_v2 then
  _G.__jobbbs_hooks_move_talk_v2 = true

  -- Handles both table-style and positional events
  local function on_area_change(a, b, c, ...)
    print('[jobbbs] on_area_change types:', type(a), type(b), type(c))
    if type(a) == 'table' then for k,v in pairs(a) do print('[jobbbs] ev', k, v) end end
    local pid, to_area
    if type(a) == 'table' then
      local ev = a
      pid     = ev.player_id or ev.pid or ev.id or ev.source or ev.actor_id
      to_area = ev.to_area or ev.dest_area or ev.to or ev.area or ev.destination or ev.to_area_id
    else
      -- positional: (pid, from_area, to_area) or (pid, to_area)
      pid, to_area = a, (c or b)
    end
    if not pid then return end

    local st = attach_state(pid)
    ensure_daily_reset(pid)
    if not st then return end

    st.prog.active = st.prog.active or {}
    if not st.prog.active.visit then return end  -- gate until a visit* job is accepted

    st.prog.visited = st.prog.visited or {}
    local area = tostring(to_area or (Net.get_player_area and Net.get_player_area(pid)) or '')
    if area == '' then return end
    if not st.prog.visited[area] then
      st.prog.visited[area] = true
      save_mem(pid, st)
    end
    if dbg then dbg('visit++', pid, area) end
  end

  Net:on('player_area_transfered', on_area_change)
  Net:on('player_transfered',      on_area_change)
  Net:on('player_area_transfer',   on_area_change)

  -- Keep your NPC tracking as-is
  Net:on('actor_interaction', function(ev)
    if ev.button ~= 0 then return end
    local pid = ev.player_id
    local st = attach_state(pid)
    ensure_daily_reset(pid)
    if not st then return end
    if Net.is_player and Net.is_player(ev.actor_id) then return end
    st.prog.active = st.prog.active or {}
    if not st.prog.active.npc then return end
    local area = tostring(Net.get_player_area(pid) or '')
    local key  = area..':'..tostring(ev.actor_id or '')
    st.prog.spoke_npcs = st.prog.spoke_npcs or {}
    if not st.prog.spoke_npcs[key] then
      st.prog.spoke_npcs[key] = true
      save_mem(pid, st)
    end
    st.prog.spoke = (st.prog.spoke or 0) + 1
    save_mem(pid, st)
  end)
end

-- ===== UI builders =====
local function open_list(pid, board_id, board_title)
  local st = attach_state(pid)
  st.day_key = st.day_key or today_key()
  ensure_daily_reset(pid)
  st.current_board = board_id
  local B = ensure_jobs_for_today(pid, st, board_id)

  local posts = {}
  -- Legend lines (replace the old "Choose a job:" line)
  posts[#posts+1] = { id='__job:hintA', read=true, title='[ ] = Available',  author='' }
  posts[#posts+1] = { id='__job:hintP', read=true, title='[>] = In Process', author='' }
  posts[#posts+1] = { id='__job:hintC', read=true, title='[X] = Complete',   author='' }
  posts[#posts+1] = { id='__job:blank', read=true, title='',   author='' }
  posts[#posts+1] = { id='__job:blank2', read=true, title='-----Available Jobs-----',   author='' }

  local by_id = (function() local p,_=jobs_pool(); return p end)()
  local TOK = { A='[ ]', P='[>]', C='[X]' }

  -- Sort by status: Available(0) < In-Process(1) < Complete(2), then by title
  local function _rank(jid)
    local j = by_id[jid]
    local done     = B.claimed[j.id] == true
    local accepted = (B.accepted[j.id] == true) and not done
    return done and 2 or (accepted and 1 or 0)
  end

  table.sort(B.job_ids, function(a, b)
    local ra, rb = _rank(a), _rank(b)
    if ra ~= rb then return ra < rb end
    local ja, jb = by_id[a], by_id[b]
    return (ja.title or '') < (jb.title or '')
  end)

  for i, jid in ipairs(B.job_ids or {}) do
    local j = by_id[jid]
    local done     = B.claimed[j.id] == true
    local accepted = (B.accepted[j.id] == true) and not done

    local status       = done and TOK.C or (accepted and TOK.P or TOK.A)
    local is_available = (not done and not accepted) -- [ ] should be bold

    posts[#posts+1] = {
      id     = '__job:view:'..i,
      read   = not is_available,  -- false => bold/unread for Available
      title  = string.format('%s %s', status, trunc(j.title, MAX_TITLE_CH)),
      author = trunc(j.poster, MAX_AUTHOR_CH),
    }
end

  posts[#posts+1] = { id='__job:close', read=true, title='Close', author='' }

  Net.open_board(pid, board_title or DEFAULT_BOARD_TITLE, COLOR_BOARD, posts)
end

-- ===== Public API =====
function JobBBS.open(pid, board_name)
  local st = attach_state(pid)
  st.day_key = st.day_key or today_key()
  ensure_daily_reset(pid)
  local bname = safe_id(board_name or DEFAULT_BOARD_TITLE)
  open_list(pid, bname, board_name or DEFAULT_BOARD_TITLE)
end

function JobBBS.handle_post_selection(event)
  local pid = event.player_id
    local st = attach_state(pid)
    ensure_daily_reset(pid)
    if not st then return end

  local post = tostring(event.post_id or '')
  if not post:match('^__job:') then return false end

  if post == '__job:close' then
    Net.close_bbs(pid)
    return true
  end

  local idx = post:match('^__job:view:(%d+)$')
  if idx then
    idx = tonumber(idx)
    local board_id = st.current_board or safe_id(DEFAULT_BOARD_TITLE)
    local B = ensure_jobs_for_today(pid, st, board_id)
    local by_id = (function() local p,_=jobs_pool(); return p end)()
    local jid = B.job_ids[idx]
    local job = jid and by_id[jid]
    if not job then return true end

    local lines = wrap(job.desc, MAX_TITLE_CH)
    local NL = string.char(10)
    Net.message_player(pid, table.concat(lines, NL))

    if B.claimed[job.id] then
      Net.message_player(pid, 'Already claimed.')
      return true
    end

    if B.accepted[job.id] then
      local base_key = board_id..'/'..job.id
      local done = job.check(pid, st, base_key)
      if done then
        B.awaiting_kind = 'claim'
        B.awaiting_idx  = idx
        B.awaiting_base = base_key
        B.awaiting_step = 'info'
      else
        local _, cur, need = job.check(pid, st, base_key)
        Net.message_player(pid, string.format('Progress: %d/%d', cur or 0, need or 0))
      end
    else
      B.awaiting_kind = 'accept'
      B.awaiting_idx  = idx
      B.awaiting_base = board_id..'/'..job.id
      B.awaiting_step = 'info'
    end
    return true
  end

  return false
end

function JobBBS.handle_textbox_response_event(event)
  local pid = event.player_id or event[1]
  local response = (event.response ~= nil) and event.response or event[2]
  if response == nil then return false end
  return JobBBS.handle_textbox_response(pid, response)
end

local function is_yes(r)
  local t = type(r)
  -- Your build: Yes == 1, No == 0 (string "1"/"0" can appear too)
  if t == 'number' then return r == 1 end
  if t == 'boolean' then return r == true end
  if t == 'string' then
    local s = r:lower():gsub('^%s*(.-)%s*$', '%1')
    return (s == '1' or s == 'y' or s == 'yes' or s == 'true' or s == 'ok' or s == 'accept')
  end
  return false
end

function JobBBS.handle_textbox_response(pid, response)
  local st = attach_state(pid)
  if not st then return false end
  -- Prefer the last-opened board, but fall back to any board that's awaiting
  local board_id = st.current_board
  local B = (board_id and st.boards and st.boards[board_id]) or nil
  if not (B and B.awaiting_kind) then
    board_id, B = find_waiting_board(st)
  end
  if not (board_id and B and B.awaiting_kind) then return false end

  -- Two-step flow: first OK on the info box, then Yes/No on the question.
  local step = B.awaiting_step or 'question'
  if step == 'info' then
    B.awaiting_step = 'question'
    if B.awaiting_kind == 'accept' then
      Net.question_player(pid, 'Accept this job?')
    elseif B.awaiting_kind == 'claim' then
      Net.question_player(pid, 'Claim reward for this job?')
    end
    return true
  end

  local yes = is_yes(response)
  local idx = B.awaiting_idx
  local kind = B.awaiting_kind
  local base_key = B.awaiting_base
  B.awaiting_kind, B.awaiting_idx, B.awaiting_base = nil, nil, nil

  local by_id = (function() local p,_=jobs_pool(); return p end)()
  local jid = (ensure_jobs_for_today(pid, st, board_id).job_ids or {})[idx]
  local job = jid and by_id[jid]
  if not job then return true end

  if kind == 'accept' then
    if yes then
      if B.claimed[job.id] then
        Net.message_player(pid, 'Already claimed today.')
      elseif B.accepted[job.id] then
        Net.message_player(pid, 'Already accepted.')
      else
        B.accepted[job.id] = true
        st.prog = st.prog or {}
        st.prog.baseline = st.prog.baseline or {}
        st.prog.baseline[base_key] = {
          visited    = copy_set(st.prog.visited),
          spoke_npcs = copy_set(st.prog.spoke_npcs),
          objects    = copy_set(st.prog.objects),
          obj_areas  = copy_set(st.prog.obj_areas),
          virus = {
            clears = (st.prog.virus and st.prog.virus.clears) or 0,
            runs   = (st.prog.virus and st.prog.virus.runs)   or 0,
            bust8  = (st.prog.virus and st.prog.virus.bust8)  or 0,
            fast   = (st.prog.virus and st.prog.virus.fast)   or 0,
            turn1  = (st.prog.virus and st.prog.virus.turn1)  or 0,
          },
          duel = { wins = (st.prog.duel and st.prog.duel.wins) or 0 },
          pack = { opened = (st.prog.pack and st.prog.pack.opened) or 0 },
        }
        local cat = job_category(job.id)
        if cat then activate_category(st, cat) end
        Net.message_player(pid, 'Accepted: '..job.title)
        save_mem(pid, st)
      end
    end
    open_list(pid, board_id)
    return true
  elseif kind == 'claim' then
    if yes then
      if B.claimed[job.id] then
        Net.message_player(pid, 'Already claimed today.')
      else
        local done = job.check(pid, st, base_key)
        if done then
          B.claimed[job.id] = true
          save_mem(pid, st)
          if JobBBS.on_claim_reward then
            pcall(JobBBS.on_claim_reward, pid, job)
          end
        else
          Net.message_player(pid, 'Not complete yet.')
        end
      end
    end
    open_list(pid, board_id)
    return true
  end
  return true
end

function JobBBS.is_waiting(pid)
  local st = S.by_pid[pid]
  if not st then return false end
  local b = st.current_board and st.boards and st.boards[st.current_board]
  return b and b.awaiting_kind ~= nil
end

function JobBBS.on_board_close(event)
  return false
end

-- ===== Engine listeners (object + yes/no) =====
if _G.Net and Net.on then
  Net:on('object_interaction', function(ev)
    if ev.button ~= 0 then return end
    local pid  = ev.player_id
    ensure_daily_reset(pid)
    local area = Net.get_player_area(pid)
    local obj  = Net.get_object_by_id(area, ev.object_id)
    if not obj then return end

    local cls  = tostring(obj.class or '')
    local typ  = tostring(obj.type  or '')
    if cls == 'JobBBS' or typ == 'JobBBS' then
      local board_name = tostring(obj.name or DEFAULT_BOARD_TITLE)
      JobBBS.open(pid, board_name)
      return
    end

    -- Track unique object interactions only after an inspect-type job is accepted
    local st = attach_state(pid)
    if st and st.prog then
      st.prog.active = st.prog.active or {}
      if st.prog.active.inspect then
        local key = tostring(area)..':'..tostring(ev.object_id or '')
        st.prog.objects   = st.prog.objects   or {}
        st.prog.obj_areas = st.prog.obj_areas or {}
        st.prog.objects[key] = true
        st.prog.obj_areas[tostring(area)] = true
        save_mem(pid, st)
      end
    end
  end)

  Net:on('textbox_response', function(a, b)
    local pid, response
    if type(a) == 'table' then
      pid      = a.player_id or a[1]
      response = (a.response ~= nil) and a.response or a[2]
    else
      pid, response = a, b
    end
    if not pid or response == nil then return end
    dbg('textbox_response', tostring(pid), tostring(response))
	  if (_ack_count[pid] or 0) > 0 then
      _ack_count[pid] = _ack_count[pid] - 1
      print(("[custom][announce] textbox_response --ack %s -> %d"):format(tostring(pid), _ack_count[pid]))
    else
      -- keep it clamped
      _ack_count[pid] = 0
    end
    _after_modal_closed(pid)

    -- (optional) daily reset; no-op if same day
    ensure_daily_reset(pid)

    -- Deliver to JobBBS; it will no-op if not waiting
    JobBBS.handle_textbox_response(pid, response)
  end)
end

-- ===== External hooks from other systems =====
function JobBBS.on_encounter_result(pid, stats)
  ensure_daily_reset(pid)
  local st = attach_state(pid); if not st then return end
  st.prog = st.prog or {}
  st.prog.active = st.prog.active or {}
  if not st.prog.active.virus then return end

  st.prog.virus = st.prog.virus or { clears=0, runs=0, bust8=0, fast=0, turn1=0 }

  if stats and stats.ran then
    st.prog.virus.runs = (st.prog.virus.runs or 0) + 1
    save_mem(pid, st)
    return
  end

  st.prog.virus.clears = (st.prog.virus.clears or 0) + 1
  local score = tonumber(stats and stats.score) or 0
  if score >= 8 then st.prog.virus.bust8 = (st.prog.virus.bust8 or 0) + 1 end
  local elapsed = tonumber(stats and stats.time)
  if elapsed and elapsed <= 10 then st.prog.virus.fast = (st.prog.virus.fast or 0) + 1 end
  local turns = tonumber(stats and stats.turns)
  if turns and turns <= 1 then st.prog.virus.turn1 = (st.prog.virus.turn1 or 0) + 1 end
  save_mem(pid, st)
end

function JobBBS.on_npc_duel_result(pid, info)
  ensure_daily_reset(pid)
  local st = attach_state(pid); if not st then return end
  st.prog = st.prog or {}
  st.prog.active = st.prog.active or {}
  if not st.prog.active.duel then return end
  st.prog.duel = st.prog.duel or { wins = 0 }
  local w = info and info.winner
  if w == 1 or w == 'player' then st.prog.duel.wins = (st.prog.duel.wins or 0) + 1; save_mem(pid, st) end
end

function JobBBS.on_pack_open(pid, info)
  ensure_daily_reset(pid)
  local st = attach_state(pid); if not st then return end
  st.prog = st.prog or {}
  st.prog.active = st.prog.active or {}
  if not st.prog.active.pack then return end
  st.prog.pack = st.prog.pack or { opened = 0 }
  local n = 1
  if info then local c = tonumber(info.count or info.packs or info.n); if c and c>0 then n=c end end
  st.prog.pack.opened = (st.prog.pack.opened or 0) + n
  save_mem(pid, st)
end

return JobBBS