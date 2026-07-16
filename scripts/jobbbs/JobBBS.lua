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
local function _secret(pid)
  return helpers.get_safe_player_secret(pid)
end

local function _mem(pid)
  local secret = _secret(pid)
  return ezmemory.get_player_memory(secret) or {}, secret
end

local function _snapshot(st)
  return {
    day_key   = st.day_key,
    prog      = st.prog      or {},
    boards    = st.boards    or {},
    __migrate = st.__migrate or {},
  }
end

local function save_mem(pid, st)
  local mem, secret = _mem(pid)
  mem.jobbbs = _snapshot(st)

  if ezmemory.set_player_memory then
    pcall(ezmemory.set_player_memory, secret, mem)
  end

  if ezmemory.save_player_memory then
    pcall(ezmemory.save_player_memory, secret)
  end
end

local function load_mem_into_state(pid, st)
  local mem = _mem(pid)
  local slot = mem.jobbbs

  if type(slot) == "table" then
    st.day_key   = slot.day_key or st.day_key
    st.prog      = slot.prog or {}
    st.boards    = slot.boards or {}
    st.__migrate = slot.__migrate or st.__migrate or {}
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
  if job_id:match('^raid')    then return 'raid'    end
  if job_id:match('^fish')    then return 'fish'    end
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

local function _run_one_time_migrations(st, pid)
  st.__migrate = st.__migrate or {}

  ------------------------------------------------------------------
  -- (A) One-time wipe for inspect_area* jobs (areas-based progress)
  ------------------------------------------------------------------
  if not st.__migrate.inspect_area_reset_v1 then
    st.prog = st.prog or {}

    -- Clear the unique-area set so the next accept snapshots a clean slate
    st.prog.obj_areas = {}

    -- Drop baselines ONLY for inspect_area* jobs
    if st.prog.baseline then
      for base_key in pairs(st.prog.baseline) do
        -- base_key looks like "<boardId>/<jobId>"
        local jid = tostring(base_key):match('/([^/]+)$') or tostring(base_key)
        if jid:match('^inspect_area') then
          st.prog.baseline[base_key] = nil
        end
      end
    end

    -- Ungate and un-accept inspect_area* so you can re-accept cleanly
    st.prog.active = st.prog.active or {}
    st.prog.active.inspect = nil
    for _, B in pairs(st.boards or {}) do
      B.accepted = B.accepted or {}
      for jid in pairs(B.accepted) do
        if tostring(jid):match('^inspect_area') then
          B.accepted[jid] = nil
        end
      end
      B.awaiting_kind, B.awaiting_idx, B.awaiting_base, B.awaiting_step = nil, nil, nil, nil
    end

    st.__migrate.inspect_area_reset_v1 = true
    save_mem(pid, st)
    if dbg then dbg('[migrate] inspect_area_reset_v1 applied', tostring(pid)) end
  end

  ------------------------------------------------------------------
  -- (B) One-time wipe for inspect* (object-based progress)
  ------------------------------------------------------------------
  if not st.__migrate.inspect_reset_v1 then
    st.prog = st.prog or {}

    -- Clear unique object keys
    st.prog.objects = {}

    -- Drop baselines for inspect* (but NOT inspect_area*)
    if st.prog.baseline then
      for base_key in pairs(st.prog.baseline) do
        local jid = tostring(base_key):match('/([^/]+)$') or tostring(base_key)
        -- match inspect, inspect9, inspect12, etc., but exclude inspect_area*
        if jid:match('^inspect$') or jid:match('^inspect%d+$') then
          st.prog.baseline[base_key] = nil
        end
      end
    end

    -- Ungate and un-accept inspect* jobs (not the area ones)
    st.prog.active = st.prog.active or {}
    st.prog.active.inspect = nil
    for _, B in pairs(st.boards or {}) do
      B.accepted = B.accepted or {}
      for jid in pairs(B.accepted) do
        local s = tostring(jid)
        if (s:match('^inspect$') or s:match('^inspect%d+$')) then
          B.accepted[jid] = nil
        end
      end
    end

    st.__migrate.inspect_reset_v1 = true
    save_mem(pid, st)
    if dbg then dbg('[migrate] inspect_reset_v1 applied', tostring(pid)) end
  end
end

-- Unify any old name-keyed state into the PID key
local function attach_state(pid)
  local st = S.by_pid[pid]
  if st then
    _run_one_time_migrations(st, pid)  -- <-- run even for already-attached players
    return st
  end

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
  _run_one_time_migrations(st, pid)
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

    -- reset job snapshots and gates
    st.prog.baseline = {}
    st.prog.active   = {}

    -- reset per-day unique sets
    st.prog.visited    = {}
    st.prog.spoke_npcs = {}
    st.prog.objects    = {}
    st.prog.obj_areas  = {}

    -- wipe all boards so nothing carries over
    if st.boards then
      for _, B in pairs(st.boards) do
        if B then
          B.accepted, B.claimed = {}, {}
          B.awaiting_kind, B.awaiting_idx, B.awaiting_base, B.awaiting_step = nil, nil, nil, nil
          B.job_ids = nil
          B.day_key = nil
        end
      end
    end

    save_mem(pid, st)
  end
end

local JOB_PET_XP = 15
-- ===== Rewards =====
local REWARDS = {
  visit3         = { money=1500 },
  visit4         = { money=2000 },
  visit5         = { money=2500 },
  visit6         = { money=3000 },
  visit7         = { money=3500 },
  visit8         = { money=4000 },
  visit9         = { money=4500 },
  visit10        = { money=5000 },
  visit11        = { money=5500 },
  visit12        = { money=6000 },
  visit13        = { money=8000 },
  npc3           = { money=2000 },
  npc6           = { money=3000 },
  npc9           = { money=4500 },
  npc12          = { money=6000 },
  inspect3       = { money=2000 },
  inspect6       = { money=3000 },
  inspect9       = { money=4500 },
  inspect12      = { money=6000 },
  inspect_area3  = { money=3000 },
  inspect_area6  = { money=5000 },
  inspect_area9  = { money=7000 },
  inspect_area12 = { money=8000  },
  virus_clear3   = { money=2000 },
  virus_clear6   = { money=3000 },
  virus_clear9   = { money=4500 },
  virus_clear12   = { money=6000 },
  virus_run3     = { money=3000 },
  virus_run6     = { money=4000 },
  virus_run9     = { money=6000 },
  virus_run12     = { money=8000 },
  virus_bust8_3  = { money=3000 },
  virus_bust8_6  = { money=5000 },
  virus_bust8_9  = { money=7000 },
  virus_bust8_12  = { money=8000 },
  virus_turn1_3  = { money=2000 },
  virus_turn1_6  = { money=3000 },
  virus_turn1_9  = { money=4500 },
  virus_turn1_12  = { money=6000 },
  virus_fast3    = { money=3000 },
  virus_fast6    = { money=5000 },
  virus_fast9    = { money=7000 },
  virus_fast12    = { money=8000 },
  duel_win1      = { money=2000 },
  duel_win2      = { money=3000 },
  duel_win3      = { money=4500 },
  pack_open1     = { money=3000 },
  pack_open10    = { money=25000 },
  fish_catch3       = { money = 2000 },
  fish_catch6       = { money = 3500 },
  fish_catch9       = { money = 5000 },
  fish_catch12      = { money = 6500 },
  fish_single_10lb  = { money = 3000 },
  fish_single_15lb  = { money = 4500 },
  fish_single_20lb  = { money = 6500 },
  fish_total_40lb   = { money = 4500 },
  fish_total_60lb   = { money = 6500 },
  fish_total_90lb   = { money = 9000 },
  fish_streak3      = { money = 3500 },
  fish_streak4      = { money = 4500 },
  fish_streak5      = { money = 6000 },
  fish_streak6      = { money = 8000 },
  fish_virus_lake3  = { money = 4500 },
  fish_virus_lake6  = { money = 7000 },
  fish_virus_lake9  = { money = 8000 },
  -- Raids
  raid_wave2     = { money = 3000 },
  raid_wave4     = { money = 5000 },
  raid_pts30     = { money = 4500 },
  raid_pts60     = { money = 6500 },
  raid_bdmg500   = { money = 5000 },
  raid_bdmg1500  = { money = 8000 },
  raid_kill      = { money = 10000 },
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

local function give_pet_xp(pid, amount)
  amount = math.max(0, math.floor(tonumber(amount) or 0))
  if amount <= 0 then return false end

  local loaded = package and package.loaded
  local Pets = loaded and loaded["scripts/ezlibs-custom/pets"] or nil

  if type(Pets) ~= "table"
    or type(Pets.award_armed_pet_battle_xp) ~= "function"
  then
    return false
  end

  local ok, awarded = pcall(
    Pets.award_armed_pet_battle_xp,
    pid,
    amount
  )

  return ok and awarded == true
end

JobBBS.on_claim_reward = function(pid, job)
  local spec = REWARDS[job.id] or { money = 200 }
  if spec.money then
    give_money(pid, spec.money)
    give_pet_xp(pid, spec.pet_xp or JOB_PET_XP)
  end
  if spec.item then
    if type(spec.item) == 'table' then
      for _, t in ipairs(spec.item) do give_item(pid, t.id, t.qty or 1) end
    else
      give_item(pid, spec.item, spec.qty or 1)
    end
  end
end

local JOB_PROGRESS_DESCS = {
  -- Visit
  visit3  = "Visit 3 different areas.",
  visit4  = "Visit 4 different areas.",
  visit5  = "Visit 5 different areas.",
  visit6  = "Visit 6 different areas.",
  visit7  = "Visit 7 different areas.",
  visit8  = "Visit 8 different areas.",
  visit9  = "Visit 9 different areas.",
  visit10 = "Visit 10 different areas.",
  visit11 = "Visit 11 different areas.",
  visit12 = "Visit 12 different areas.",
  visit13 = "Visit 13 different areas.",

  -- NPC
  npc3  = "Talk to 3 NPCs.",
  npc6  = "Talk to 6 NPCs.",
  npc9  = "Talk to 9 NPCs.",
  npc12 = "Talk to 12 NPCs.",

  -- Inspect
  inspect3  = "Inspect 3 objects.",
  inspect6  = "Inspect 6 objects.",
  inspect9  = "Inspect 9 objects.",
  inspect12 = "Inspect 12 objects.",

  inspect_area3  = "Inspect objects in 3 areas.",
  inspect_area6  = "Inspect objects in 6 areas.",
  inspect_area9  = "Inspect objects in 9 areas.",
  inspect_area12 = "Inspect objects in 13 areas.",

  -- Virus
  virus_clear3  = "Defeat 3 virus encounters.",
  virus_clear6  = "Defeat 6 virus encounters.",
  virus_clear9  = "Defeat 9 virus encounters.",
  virus_clear12 = "Defeat 12 virus encounters.",

  virus_run3  = "Run from 3 virus encounters.",
  virus_run6  = "Run from 6 virus encounters.",
  virus_run9  = "Run from 9 virus encounters.",
  virus_run12 = "Run from 12 virus encounters.",

  virus_bust8_3  = "Delete 3 viruses with Busting LV 8 or more.",
  virus_bust8_6  = "Delete 6 viruses with Busting LV 8 or more.",
  virus_bust8_9  = "Delete 9 viruses with Busting LV 8 or more.",
  virus_bust8_12 = "Delete 12 viruses with Busting LV 8 or more.",

  virus_turn1_3  = "Delete 3 viruses in 1 turn.",
  virus_turn1_6  = "Delete 6 viruses in 1 turn.",
  virus_turn1_9  = "Delete 9 viruses in 1 turn.",
  virus_turn1_12 = "Delete 12 viruses in 1 turn.",

  virus_fast3  = "Delete 3 viruses in 10s or less.",
  virus_fast6  = "Delete 6 viruses in 10s or less.",
  virus_fast9  = "Delete 9 viruses in 10s or less.",
  virus_fast12 = "Delete 12 viruses in 10s or less.",

  -- Duel
  duel_win1 = "Win 1 YGO Duel.",
  duel_win2 = "Win 2 YGO Duels.",
  duel_win3 = "Win 3 YGO Duels.",

  -- Pack
  pack_open1  = "Open 1 booster pack.",
  pack_open10 = "Open 10 booster packs.",

  -- Fishing
  fish_catch3  = "Catch 3 fish.",
  fish_catch6  = "Catch 6 fish.",
  fish_catch9  = "Catch 9 fish.",
  fish_catch12 = "Catch 12 fish.",

  fish_single_10lb = "Catch a fish 10 lbs or heavier.",
  fish_single_15lb = "Catch a fish 15 lbs or heavier.",
  fish_single_20lb = "Catch a fish 20 lbs or heavier.",

  fish_total_40lb = "Catch 40 lbs of fish.",
  fish_total_60lb = "Catch 60 lbs of fish.",
  fish_total_90lb = "Catch 90 lbs of fish.",

  fish_streak3 = "Catch 3 fish in a row.",
  fish_streak4 = "Catch 4 fish in a row.",
  fish_streak5 = "Catch 5 fish in a row.",
  fish_streak6 = "Catch 6 fish in a row.",

  fish_virus_lake3 = "Defeat 3 lake virus encounters.",
  fish_virus_lake6 = "Defeat 6 lake virus encounters.",
  fish_virus_lake9 = "Defeat 9 lake virus encounters.",

  -- Raid
  raid_wave2 = "Participate in 2 raid battles.",
  raid_wave4 = "Participate in 4 raid battles.",

  raid_pts30 = "Earn 30 raid points.",
  raid_pts60 = "Earn 60 raid points.",

  raid_bdmg500  = "Deal 500 raid boss damage.",
  raid_bdmg1500 = "Deal 1500 raid boss damage.",

  raid_kill = "Land the finishing blow on a raid boss.",
}

-- ===== Job pool (definitions) =====
-- Each check accepts (pid, st, baseline_key)
local function jobs_pool()
  local P = {}
  local function J(id, title, poster, desc, progress_desc, check)
    -- Backwards compatible:
    -- Old format: J(id, title, poster, desc, check)
    -- New format: J(id, title, poster, desc, progress_desc, check)
    if type(progress_desc) == "function" and check == nil then
      check = progress_desc
      progress_desc = nil
    end

    P[id] = {
      id = id,
      title = title,
      poster = poster,
      desc = desc,
      progress_desc = progress_desc or JOB_PROGRESS_DESCS[id],
      check = check,
    }
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
  J('pack_open10', 'Card Maniac', 'Card Shop', 'Open 10 booster packs.',
    function(pid, st, base_key)
      st.prog.pack = st.prog.pack or { opened = 0 }
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].pack or nil
      local cur = st.prog.pack.opened or 0; local n = math.max(0, cur - ((base and base.opened) or 0)); return n>=10, n, 10
    end)
  -- ========= Fishing (your 5 lines) =========
  -- Daily Angler (HowlerMan) - N: 3,6,9,12
  J('fish_catch3',  'Daily Angler', 'HowlerMan', 'Me need at least 3 fish today, ook! Can you do that?',
    function(pid, st, base_key)
      st.prog.fish = st.prog.fish or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].fish or {}
      local cur  = (st.prog.fish.catches or 0) - (base.catches or 0); return cur>=3, cur, 3
    end)
  J('fish_catch6',  'Daily Angler', 'HowlerMan', 'Me need at least 6 fish today, ook! Can you do that?',
    function(pid, st, base_key)
      st.prog.fish = st.prog.fish or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].fish or {}
      local cur  = (st.prog.fish.catches or 0) - (base.catches or 0); return cur>=6, cur, 6
    end)
  J('fish_catch9',  'Daily Angler', 'HowlerMan', 'Me need at least 9 fish today, ook! Can you do that?',
    function(pid, st, base_key)
      st.prog.fish = st.prog.fish or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].fish or {}
      local cur  = (st.prog.fish.catches or 0) - (base.catches or 0); return cur>=9, cur, 9
    end)
  J('fish_catch12', 'Daily Angler', 'HowlerMan', 'Me need at least 12 fish today, ook! Can you do that?',
    function(pid, st, base_key)
      st.prog.fish = st.prog.fish or {}
      local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].fish or {}
      local cur  = (st.prog.fish.catches or 0) - (base.catches or 0); return cur>=12, cur, 12
    end)

  -- Raid (uses st.prog.raid from raids.lua callbacks)
  J('raid_wave2', 'Raid Help', 'Mr. Prog', 'LVL1: Participate in 2 raid battles.',
    function(pid, st, base_key)
      st.prog.raid = st.prog.raid or {}
      local base = st.prog.baseline
                  and st.prog.baseline[base_key]
                  and st.prog.baseline[base_key].raid or nil
      local cur = st.prog.raid.battles or 0
      local n = math.max(0, cur - ((base and base.battles) or 0))
      return n>=2, n, 2
    end)

  J('raid_wave4', 'Raid Help', 'Mr. Prog', 'LVL2: Participate in 4 raid battles.',
    function(pid, st, base_key)
      st.prog.raid = st.prog.raid or {}
      local base = st.prog.baseline
                  and st.prog.baseline[base_key]
                  and st.prog.baseline[base_key].raid or nil
      local cur = st.prog.raid.battles or 0
      local n = math.max(0, cur - ((base and base.battles) or 0))
      return n>=4, n, 4
    end)

  J('raid_pts30', 'Raid Pts', 'ShaDisNX', 'LVL1: Earn 30 raid points from any raid.',
    function(pid, st, base_key)
      st.prog.raid = st.prog.raid or {}
      local base = st.prog.baseline
                  and st.prog.baseline[base_key]
                  and st.prog.baseline[base_key].raid or nil
      local cur = st.prog.raid.points or 0
      local n = math.max(0, cur - ((base and base.points) or 0))
      return n>=30, n, 30
    end)

  J('raid_pts60', 'Raid Pts', 'ShaDisNX', 'LVL2: Earn 60 raid points from any raid.',
    function(pid, st, base_key)
      st.prog.raid = st.prog.raid or {}
      local base = st.prog.baseline
                  and st.prog.baseline[base_key]
                  and st.prog.baseline[base_key].raid or nil
      local cur = st.prog.raid.points or 0
      local n = math.max(0, cur - ((base and base.points) or 0))
      return n>=60, n, 60
    end)

  J('raid_bdmg500', 'Boss Dmg', 'ShaDisNX', 'LVL1: Deal 500 damage to a raid boss.',
    function(pid, st, base_key)
      st.prog.raid = st.prog.raid or {}
      local base = st.prog.baseline
                  and st.prog.baseline[base_key]
                  and st.prog.baseline[base_key].raid or nil
      local cur = st.prog.raid.boss_dmg or 0
      local n = math.max(0, cur - ((base and base.boss_dmg) or 0))
      return n>=500, n, 500
    end)

  J('raid_bdmg1500', 'Boss Dmg', 'ShaDisNX', 'LVL2: Deal 1500 damage to raid bosses.',
    function(pid, st, base_key)
      st.prog.raid = st.prog.raid or {}
      local base = st.prog.baseline
                  and st.prog.baseline[base_key]
                  and st.prog.baseline[base_key].raid or nil
      local cur = st.prog.raid.boss_dmg or 0
      local n = math.max(0, cur - ((base and base.boss_dmg) or 0))
      return n>=1500, n, 1500
    end)

  J('raid_kill', 'Boss Kill', 'ShaDisNX', 'LVL MAX: Land the finishing blow on a raid boss.',
    function(pid, st, base_key)
      st.prog.raid = st.prog.raid or {}
      local base = st.prog.baseline
                  and st.prog.baseline[base_key]
                  and st.prog.baseline[base_key].raid or nil
      local cur = st.prog.raid.boss_kills or 0
      local n = math.max(0, cur - ((base and base.boss_kills) or 0))
      return n>=1, n, 1
    end)

  -- Big Fish (HowlerMan) - N: 10,15,20 (single catch)
  local function _big_single_check(pid, st, base_key, need_lb)
    st.prog.fish = st.prog.fish or {}

    local base = (st.prog.baseline
                 and st.prog.baseline[base_key]
                 and st.prog.baseline[base_key].fish) or {}

    local F = st.prog.fish

    local cur_c  = tonumber(F.catches or 0) or 0
    local base_c = tonumber(base.catches or 0) or 0
    local last_w = tonumber(F.last_w or 0) or 0

    local marker_key = "single_" .. tostring(need_lb) .. "_at"
    local qualified_at = tonumber(F[marker_key] or 0) or 0

    -- Marker handles new catches permanently.
    -- The last_w fallback lets currently accepted jobs made before this
    -- update still complete when the latest catch qualifies.
    local done =
      qualified_at > base_c
      or ((cur_c > base_c) and (last_w >= need_lb))

    -- Do not display an old pre-acceptance lifetime record as progress.
    local caught_since_accept = cur_c > base_c
    local prog = done
      and need_lb
      or (caught_since_accept and math.min(last_w, need_lb) or 0)

    return done, prog, need_lb
  end
  J('fish_single_10lb', 'Big Fish', 'HowlerMan', 'Me hungry! Catch fish that weighs more than 10 lbs, ook!',
    function(pid, st, base_key) return _big_single_check(pid, st, base_key, 10) end)
  J('fish_single_15lb', 'Big Fish', 'HowlerMan', 'Me hungry! Catch fish that weighs more than 15 lbs, ook!',
    function(pid, st, base_key) return _big_single_check(pid, st, base_key, 15) end)
  J('fish_single_20lb', 'Big Fish', 'HowlerMan', 'Me hungry! Catch fish that weighs more than 20 lbs, ook!',
    function(pid, st, base_key) return _big_single_check(pid, st, base_key, 20) end)

  -- Total Weight (HowlerMan) - N: 40,60,90 (sum since accept)
  local function _total_weight_check(pid, st, base_key, need_lb)
    st.prog.fish = st.prog.fish or {}
    local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].fish or {}
    local cur = (tonumber(st.prog.fish.total_lb or 0) or 0) - (tonumber(base.total_lb or 0) or 0)
    local prog = math.floor(cur + 0.0001)
    return cur >= need_lb, prog, need_lb
  end
  J('fish_total_40lb', 'Total Weight', 'HowlerMan', 'Me catch many big fish today, ook! Can you catch 40 lbs of fish too, ook?',
    function(pid, st, base_key) return _total_weight_check(pid, st, base_key, 40) end)
  J('fish_total_60lb', 'Total Weight', 'HowlerMan', 'Me catch many big fish today, ook! Can you catch 60 lbs of fish too, ook?',
    function(pid, st, base_key) return _total_weight_check(pid, st, base_key, 60) end)
  J('fish_total_90lb', 'Total Weight', 'HowlerMan', 'Me catch many big fish today, ook! Can you catch 90 lbs of fish too, ook?',
    function(pid, st, base_key) return _total_weight_check(pid, st, base_key, 90) end)

  -- On a Roll (HowlerMan) - N: 3,4,5,6 (best streak since accept; failures reset live streak)
local function _streak_check(pid, st, base_key, need)
  st.prog.fish = st.prog.fish or {}
  local base = (st.prog.baseline and st.prog.baseline[base_key]
               and st.prog.baseline[base_key].fish) or {}

  local best_now   = tonumber(st.prog.fish.streak or 0) or 0
  local base_best  = tonumber(base.streak or 0) or 0
  local live       = tonumber(st.prog.fish.streak_live or 0) or 0
  local cur_c      = tonumber(st.prog.fish.catches or 0) or 0
  local base_c     = tonumber(base.catches or 0) or 0
  local since_c    = math.max(0, cur_c - base_c)

  -- Live streak that is guaranteed to be fully after acceptance
  local live_since_accept = math.min(live, since_c)

  -- Completion should be “sticky” if you achieved the needed streak at any point since accept
  local beat_baseline = (best_now >= need) and (best_now > base_best)
  local done = beat_baseline or (live_since_accept >= need)

  -- Progress UI should reflect the CURRENT live streak (so it drops when you fail)
  local prog = math.min(live_since_accept, need)

  return done, prog, need
end
  J('fish_streak3', 'On a Roll', 'HowlerMan', "Me a better fisher than you, ook! Bet you can't catch 3 fish in a row!",
    function(pid, st, base_key) return _streak_check(pid, st, base_key, 3) end)
  J('fish_streak4', 'On a Roll', 'HowlerMan', "Me a better fisher than you, ook! Bet you can't catch 4 fish in a row!",
    function(pid, st, base_key) return _streak_check(pid, st, base_key, 4) end)
  J('fish_streak5', 'On a Roll', 'HowlerMan', "Me a better fisher than you, ook! Bet you can't catch 5 fish in a row!",
    function(pid, st, base_key) return _streak_check(pid, st, base_key, 5) end)
  J('fish_streak6', 'On a Roll', 'HowlerMan', "Me a better fisher than you, ook! Bet you can't catch 6 fish in a row!",
    function(pid, st, base_key) return _streak_check(pid, st, base_key, 6) end)

  -- Clean the Pond (ProtoMan) - N: 3,6,9 (wins vs viruses spawned by fishing)
  local function _virus_fish_wins(pid, st, base_key, need)
    st.prog.fish = st.prog.fish or {}
    local base = st.prog.baseline and st.prog.baseline[base_key] and st.prog.baseline[base_key].fish or {}
    local cur = (st.prog.fish.virus_wins or 0) - (base.virus_wins or 0)
    return cur >= need, cur, need
  end
  J('fish_virus_lake3', 'Clean Pond', 'ProtoMan', 'Official NetBattler business, defeat 3 virus encounters that spawn in the lake.',
    function(pid, st, base_key) return _virus_fish_wins(pid, st, base_key, 3) end)
  J('fish_virus_lake6', 'Clean Pond', 'ProtoMan', 'Official NetBattler business, defeat 6 virus encounters that spawn in the lake.',
    function(pid, st, base_key) return _virus_fish_wins(pid, st, base_key, 6) end)
  J('fish_virus_lake9', 'Clean Pond', 'ProtoMan', 'Official NetBattler business, defeat 9 virus encounters that spawn in the lake.',
    function(pid, st, base_key) return _virus_fish_wins(pid, st, base_key, 9) end)

  -- Categorize ids
  local CATS = {
    visit   = { 'visit3', 'visit4', 'visit5', 'visit6', 'visit7', 'visit8', 'visit9', 'visit10', 'visit11', 'visit12', 'visit13' },
    npc     = { 'npc3', 'npc6', 'npc9', 'npc12' },
    inspect = { 'inspect3', 'inspect6', 'inspect9', 'inspect12', 'inspect_area3', 'inspect_area6', 'inspect_area9', 'inspect_area12' },
    virus   = { 'virus_clear3', 'virus_clear6', 'virus_clear9', 'virus_clear12', 'virus_run3', 'virus_run6', 'virus_run9', 'virus_run12', 'virus_bust8_3', 'virus_bust8_6', 'virus_bust8_9', 'virus_bust8_12',
	'virus_turn1_3', 'virus_turn1_6', 'virus_turn1_9', 'virus_turn1_12', 'virus_fast3', 'virus_fast6', 'virus_fast9', 'virus_fast12' },
    duel    = { 'duel_win1', 'duel_win2', 'duel_win3' },
    pack    = { 'pack_open1', 'pack_open10' },
    fish    = {
      'fish_catch3','fish_catch6','fish_catch9','fish_catch12',
      'fish_single_10lb','fish_single_15lb','fish_single_20lb',
      'fish_total_40lb','fish_total_60lb','fish_total_90lb',
      'fish_streak3','fish_streak4','fish_streak5','fish_streak6',
      'fish_virus_lake3','fish_virus_lake6','fish_virus_lake9'
    },
    raid    = {
      'raid_wave2','raid_wave4',
      'raid_pts30','raid_pts60',
      'raid_bdmg500','raid_bdmg1500',
      'raid_kill'
    },
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

  -- Day-flip guard (normal case): board day differs from player day → wipe flags
  if B.day_key and B.day_key ~= st.day_key then
    B.accepted, B.claimed = {}, {}
    B.awaiting_kind, B.awaiting_idx, B.awaiting_base, B.awaiting_step = nil, nil, nil, nil
    if st.prog and st.prog.baseline then
      for k,_ in pairs(st.prog.baseline) do
        if k:match('^'..board_id..'/') then st.prog.baseline[k] = nil end
      end
    end
    -- per-day "read" state: wipe on day flip
    B.opened_desc = {}
    -- mark that flags are clean for this day
    B.flags_stamp = st.day_key
  end

  -- If jobs already exist for "today", do a one-time repair if they were picked by an old build
  -- Old builds set B.day_key but never stamped; that left yesterday's claimed flags intact.
  if B.job_ids and B.day_key == st.day_key then
    if B.flags_stamp ~= st.day_key then
      -- repair: nuke stale flags once
      B.accepted, B.claimed = {}, {}
      B.awaiting_kind, B.awaiting_idx, B.awaiting_base, B.awaiting_step = nil, nil, nil, nil
      if st.prog and st.prog.baseline then
        for k,_ in pairs(st.prog.baseline) do
          if k:match('^'..board_id..'/') then st.prog.baseline[k] = nil end
        end
      end
      B.flags_stamp = st.day_key
      save_mem(pid, st)
    end
    save_mem(pid, st)
    return B
  end

  -- (Re)pick today's jobs deterministically
  local pool, cats = jobs_pool()
  local order = { 'visit','npc','inspect','virus','duel','pack','fish', 'raid' }
  local ids = {}
  for _, cat in ipairs(order) do
    local list = cats[cat]
    local seed = table.concat({ player_key(pid), st.day_key, board_id, cat }, '|')
    ids[#ids+1] = pick_deterministic(list, seed)
  end
  B.job_ids = ids
  B.day_key = st.day_key
  -- when we generate a fresh list for the day, flags should be considered clean
  B.opened_desc = {}
  B.flags_stamp = st.day_key
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
    local is_available = (not done and not accepted)

    -- "Unread" means: available AND description not yet opened today
    B.opened_desc = B.opened_desc or {}
    local has_opened          = B.opened_desc[j.id] == true
    local is_unread_available = is_available and not has_opened

    posts[#posts+1] = {
      id     = '__job:view:'..i,
      -- false => bold/unread → show NEW only for available + never-read
      read   = not is_unread_available,
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

-- View-only board that shows progress for currently accepted jobs (all boards)
local function open_progress_board(pid)
  -- Ensure state is attached + day reset is applied
  ensure_daily_reset(pid)
  local st = attach_state(pid)
  if not st then return end

  local posts = {}
  posts[#posts+1] = { id='__job:hintP', read=true, title='[>] = In Process', author='' }
  posts[#posts+1] = { id='__job:hintC', read=true, title='[X] = Complete',   author='' }
  posts[#posts+1] = {
    id     = '__jobprog:blank',
    read   = true,
    title  = '',
    author = ''
  }

  local by_id = (function() local p,_ = jobs_pool(); return p end)()
  local any   = false

  -- Same symbols as the main JobBBS list
  local TOK = { P = '[>]', C = '[X]' }

  -- Iterate all boards and show accepted jobs (that haven’t been claimed yet)
  for board_id, B in pairs(st.boards or {}) do
    if B and B.accepted then
      -- Make sure today’s jobs exist for this board
      ensure_jobs_for_today(pid, st, board_id)

      local claimed = B.claimed or {}

      for jid, accepted in pairs(B.accepted) do
        if accepted and not claimed[jid] then
          local job = by_id[jid]
          if job and job.check then
            any = true

            local base_key       = board_id..'/'..jid
            local done, cur, need = job.check(pid, st, base_key)
            cur  = cur  or 0
            need = need or 0

            -- Use [>] for in-process, [X] for complete
            local status_tok = done and TOK.C or TOK.P

            -- Line 1: Job name with token prefix, like the normal JobBBS
            posts[#posts+1] = {
              id     = '__jobprog:title:'..board_id..':'..jid,
              read   = true, -- view-only board, no bold/unread states
              title  = string.format('%s %s', status_tok, trunc(job.title, MAX_TITLE_CH)),
              author = '' -- or job.poster if you want
            }

            -- Line 2: Progress line
            -- If done, show "Complete" (prevents e.g. 4/3, 5/3 from continuing to climb).
            local cur_i  = math.floor(tonumber(cur)  or 0)
            local need_i = math.floor(tonumber(need) or 0)
            if cur_i < 0 then cur_i = 0 end
            if need_i < 0 then need_i = 0 end
            if (not done) and need_i > 0 and cur_i > need_i then cur_i = need_i end

            posts[#posts+1] = {
              id     = '__jobprog:prog:'..board_id..':'..jid,
              read   = true,
              title  = done and 'Progress: Complete' or string.format('Progress: %d/%d', cur_i, need_i),
              author = ''
            }
          end
        end
      end
    end
  end

  if not any then
    posts[#posts+1] = {
      id     = '__jobprog:none',
      read   = true,
      title  = 'No accepted jobs today.',
      author = ''
    }
  end

  -- This board is view-only; we use a different id prefix (__jobprog:)
  -- so JobBBS.handle_post_selection ignores all clicks (unless you add a special handler).
  Net.open_board(pid, 'Job Progress', COLOR_BOARD, posts)
end

function JobBBS.open_progress_board(pid)
  open_progress_board(pid)
end

local function get_menuapi()
  local MenuAPI = rawget(_G, "MenuAPI")

  if not (MenuAPI and type(MenuAPI.open) == "function") then
    local ok, mod = pcall(require, "scripts/menuAPI/main")
    if ok and type(mod) == "table" then
      MenuAPI = mod
    end
  end

  return MenuAPI
end

local function menuapi_tint(name, key)
  local MenuAPI = get_menuapi()

  if MenuAPI and type(MenuAPI.get_palette) == "function" then
    local p = MenuAPI.get_palette(name)
    if p and p[key] then
      return p[key]
    end
  end

  return nil
end

local function fit_menu_lines(text, width, max_lines)
  local lines = wrap(text or "", width or 20)
  local out = {}

  for i = 1, max_lines do
    out[i] = lines[i] or ""
  end

  if #lines > max_lines and max_lines > 0 then
    local last = tostring(out[max_lines] or "")
    if #last > 3 then
      out[max_lines] = last:sub(1, math.max(1, width - 3)) .. "..."
    else
      out[max_lines] = "..."
    end
  end

  return out
end

-- MenuAPI version of the LMenu Job Progress viewer.
-- Shows accepted, unclaimed jobs from all boards.
function JobBBS.build_menuapi_progress_rows(pid)
  ensure_daily_reset(pid)

  local st = attach_state(pid)
  if not st then
    return {
      { id = "__jobprog:none", text = "No job data.", selectable = false, show_right = false },
    }
  end

  local by_id = (function()
    local p, _ = jobs_pool()
    return p
  end)()

  local rows = {}

  for board_id, B in pairs(st.boards or {}) do
    if B and B.accepted then
      ensure_jobs_for_today(pid, st, board_id)

      local claimed = B.claimed or {}

      for jid, accepted in pairs(B.accepted) do
        if accepted and not claimed[jid] then
          local job = by_id[jid]

          if job and job.check then
            local base_key = board_id .. "/" .. jid
            local done, cur, need = job.check(pid, st, base_key)

            cur = math.floor(tonumber(cur) or 0)
            need = math.floor(tonumber(need) or 0)

            if cur < 0 then cur = 0 end
            if need < 0 then need = 0 end
            if (not done) and need > 0 and cur > need then cur = need end

            local status_tint = menuapi_tint(done and "green" or "gold", "row_tint")
            local right = done and "Done" or string.format("%d/%d", cur, need)

            rows[#rows + 1] = {
              id = "__jobprog:title:" .. tostring(board_id) .. ":" .. tostring(jid),
              text = trunc(job.title, MAX_TITLE_CH),
              right = right,
              tint = status_tint,
              right_tint = status_tint,

              -- Extra data used by MenuAPI confirm.
              board_id = board_id,
              job_id = jid,
              job_title = job.title,
              job_desc = job.desc,
              job_progress_desc = job.progress_desc or job.desc,
              job_poster = job.poster,
              job_done = done,
              job_cur = cur,
              job_need = need,
            }
          end
        end
      end
    end
  end

  table.sort(rows, function(a, b)
    local ad = a.job_done and 1 or 0
    local bd = b.job_done and 1 or 0
    if ad ~= bd then return ad < bd end

    local at = tostring(a.job_title or a.text or "")
    local bt = tostring(b.job_title or b.text or "")
    return at < bt
  end)

  if #rows == 0 then
    rows[#rows + 1] = {
      id = "__jobprog:none",
      text = "No accepted jobs.",
      selectable = false,
      enabled = false,
      show_right = false,
    }
  end

  return rows
end

function JobBBS.handle_menuapi_progress_confirm(pid, row, menu_state, opts)
  if type(row) ~= "table" or not row.job_id then
    return true
  end

  opts = opts or {}

  local cur = math.floor(tonumber(row.job_cur) or 0)
  local need = math.floor(tonumber(row.job_need) or 0)

  local progress_text
  if row.job_done then
    progress_text = "Progress: Complete"
  else
    progress_text = string.format("Progress: %d/%d", cur, need)
  end

  local desc = tostring(row.job_progress_desc or row.job_desc or "")
  if desc == "" then
    desc = tostring(row.job_title or "Job")
  end

  local MenuAPI = get_menuapi()

  if MenuAPI and type(MenuAPI.open) == "function" then
    local status_tint = menuapi_tint(row.job_done and "green" or "gold", "row_tint")
    local desc_tint = menuapi_tint("gray", "row_tint")

    local lines = fit_menu_lines(desc, 20, 3)

    local detail_rows = {
      { id = "__jobdetail:desc1", text = lines[1], selectable = false, disabled_prefix = false, tint = desc_tint, show_right = false },
      { id = "__jobdetail:desc2", text = lines[2], selectable = false, disabled_prefix = false, tint = desc_tint, show_right = false },
      { id = "__jobdetail:desc3", text = lines[3], selectable = false, disabled_prefix = false, tint = desc_tint, show_right = false },
      { id = "__jobdetail:prog",  text = progress_text, selectable = false, disabled_prefix = false, tint = status_tint, show_right = false },
    }

    MenuAPI.open(pid, {
      type = 2,
      title = trunc(row.job_title or "Job", 18),
      color = row.job_done and "green" or "gold",
      rows = detail_rows,
      open_sfx = false,

      lock_input = false,
      cursor_enabled = false,
      scroll_enabled = false,
      show_right = false,

      parent = function(pid)
        JobBBS.open_menuapi_progress(pid, {
          parent = opts.parent or "lmenu",
          color = opts.color or "blue",
          title = opts.title or "Job Progress",
          lock_input = false,
          open_sfx = false,
        })
      end,
    })

    return true
  end

  local NL = string.char(10)
  Net.message_player(pid, desc .. NL .. progress_text)
  return true
end

function JobBBS.open_menuapi_progress(pid, opts)
  opts = opts or {}

  local MenuAPI = rawget(_G, "MenuAPI")
  if not (MenuAPI and type(MenuAPI.open) == "function") then
    local ok, mod = pcall(require, "scripts/menuAPI/main")
    if ok and type(mod) == "table" then
      MenuAPI = mod
    end
  end

  if not (MenuAPI and type(MenuAPI.open) == "function") then
    Net.message_player(pid, "(MenuAPI not available.)")
    return false
  end

  return MenuAPI.open(pid, {
    type = 1,
    title = opts.title or "Job Progress",
    parent = opts.parent or "lmenu",
    color = opts.color or "blue",
    open_sfx = opts.open_sfx,

    -- LMenu already closed with keep_frozen = true,
    -- so avoid double-locking input here.
    lock_input = opts.lock_input == true,

    rows = JobBBS.build_menuapi_progress_rows(pid),

    on_confirm = function(pid, selected_row, menu_state)
      return JobBBS.handle_menuapi_progress_confirm(pid, selected_row, menu_state, opts)
    end,
  })
end

function JobBBS.handle_post_selection(event)
  local pid = event.player_id
    local st = attach_state(pid)
    ensure_daily_reset(pid)
    if not st then return end

  local post = tostring(event.post_id or '')
  -- View-only Job Progress board:
  -- If you click the job title line, show its description in chat.
  -- (No accept/claim, no extra progress line here.)
  local prog_board_id, prog_job_id = post:match('^__jobprog:title:([^:]+):(.+)$')
  if prog_board_id and prog_job_id then
    local by_id = (function() local p,_ = jobs_pool(); return p end)()
    local job = by_id[prog_job_id]

    if job and job.desc then
      local lines = wrap(job.desc, MAX_TITLE_CH)
      local NL = string.char(10)
      Net.message_player(pid, table.concat(lines, NL))
    end

    -- It's a view-only board: don’t start accept/claim flows.
    return true
  end

  -- Normal JobBBS boards use "__job:" IDs as before.
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
    -- Mark this job as "description opened" for today (clears NEW next time)
    B.opened_desc = B.opened_desc or {}
    B.opened_desc[job.id] = true
    save_mem(pid, st)
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

        -- Extra visibility for streak fishing jobs: show why the streak last broke.
        if tostring(job.id):match('^fish_streak') then
          local F = st.prog and st.prog.fish
          local r = F and F.last_break
          if r then
            local pretty = ({
              moved       = 'Moved (scared the fish)',
              timeout     = 'Timer ran out',
              missed_bite = 'Missed the bite window',
              transfer    = 'Area transfer / cancelled',
              virus_spawn = 'Virus encounter',
            })[r] or tostring(r)
            Net.message_player(pid, 'Last streak break: ' .. pretty)
          end
        end
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
          fish = {
            catches     = (st.prog.fish and st.prog.fish.catches)     or 0,
            total_lb    = (st.prog.fish and st.prog.fish.total_lb)    or 0,
            max_single  = (st.prog.fish and st.prog.fish.max_single)  or 0,
            streak      = (st.prog.fish and st.prog.fish.streak)      or 0,
            virus_wins  = (st.prog.fish and st.prog.fish.virus_wins)  or 0,
            last_w      = (st.prog.fish and st.prog.fish.last_w)      or 0,
          },
          raid = {
            battles    = (st.prog.raid and st.prog.raid.battles)    or 0,
            points     = (st.prog.raid and st.prog.raid.points)     or 0,
            boss_dmg   = (st.prog.raid and st.prog.raid.boss_dmg)   or 0,
            boss_kills = (st.prog.raid and st.prog.raid.boss_kills) or 0,
          },
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
  Net:on('object_interaction', function(a, b, c)
    -- Normalize payload (table or positional)
    local ev = (type(a) == 'table') and a or { player_id = a, object_id = b, button = c }
    local pid = ev.player_id
    if not pid then return end

    -- Match your original behavior: only act on confirm button (0)
    if ev.button ~= 0 then return end

    -- Resolve area + object
    local area = ev.area or ev.area_id or (Net.get_player_area and Net.get_player_area(pid))
    area = tostring(area or ''); if area == '' then return end

    local obj_id = ev.object_id
    local obj = nil
    if obj_id ~= nil and Net.get_object_by_id then
      obj = Net.get_object_by_id(area, obj_id)
      if not obj then return end
    else
      -- if your build ever omits object_id, we can't open boards reliably
      return
    end

    -- 1) If it's a JobBBS object, open the board (exactly like your old code)
    local cls  = tostring(obj.class or '')
    local typ  = tostring(obj.type  or '')
    if cls == 'JobBBS' or typ == 'JobBBS' then
      local board_name = tostring(obj.name or DEFAULT_BOARD_TITLE)
      JobBBS.open(pid, board_name)
      return
    end

    -- 2) Otherwise, track unique object inspections (post-accept only)
    local st = attach_state(pid); if not st then return end
    ensure_daily_reset(pid)

    st.prog = st.prog or {}
    st.prog.active = st.prog.active or {}
    if not st.prog.active.inspect then return end

    -- Stable key: area + object_id (fallbacks just in case)
    local key = area..':'..tostring(obj_id or obj.id or obj.name or '')

    st.prog.objects   = st.prog.objects   or {}
    st.prog.obj_areas = st.prog.obj_areas or {}

    if not st.prog.objects[key] then
      st.prog.objects[key] = true
      st.prog.obj_areas[area] = true
      save_mem(pid, st)
      if dbg then dbg('inspect++', pid, key) end
    else
      if dbg then dbg('inspect (repeat)', pid, key) end
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

-- Normalize encounter results (mirrors raids.lua)
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

-- ===== External hooks from other systems =====
function JobBBS.on_encounter_result(pid, stats)
  ensure_daily_reset(pid)
  local st = attach_state(pid); if not st then return end
  st.prog = st.prog or {}
  st.prog.active = st.prog.active or {}
  if not st.prog.active.virus then return end

  st.prog.virus = st.prog.virus or { clears=0, runs=0, bust8=0, fast=0, turn1=0 }

  -- Use unified flags (reason-based; same semantics as raids.lua)
  local flags = _result_flags(stats)

  -- Any kind of run?
  if flags.ran then
    -- Only count L-button runs (reason == 3) toward virus_run jobs.
    -- ESC/dev runs (reason == 4) do NOT advance the JobBBS run quests.
    if flags.reason == 3 then
      st.prog.virus.runs = (st.prog.virus.runs or 0) + 1
      save_mem(pid, st)
    end
    return
  end

  -- Anything that isn't a run is treated as a "clear" like before
  st.prog.virus.clears = (st.prog.virus.clears or 0) + 1

  -- Old bust/time/turn logic kept intact
  local score = tonumber(stats and stats.score) or 0
  if score >= 8 then
    st.prog.virus.bust8 = (st.prog.virus.bust8 or 0) + 1
  end

  local elapsed = tonumber(stats and stats.time)
  if elapsed and elapsed <= 10 then
    st.prog.virus.fast = (st.prog.virus.fast or 0) + 1
  end

  local turns = tonumber(stats and stats.turns)
  if turns and turns <= 1 then
    st.prog.virus.turn1 = (st.prog.virus.turn1 or 0) + 1
  end

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

function JobBBS.on_fish_catch(pid, info)
  ensure_daily_reset(pid)
  local st = attach_state(pid); if not st then return end
  st.prog = st.prog or {}; st.prog.active = st.prog.active or {}
  if not st.prog.active.fish then return end
  st.prog.fish = st.prog.fish or { catches=0, total_lb=0, max_single=0, streak=0, streak_live=0, virus_wins=0 }

  local F = st.prog.fish
  local w = tonumber(info and (info.weight or info.weight_lb or info.w)) or 0
  F.catches    = (F.catches or 0) + 1
  -- Remember the catch number of the latest qualifying Big Fish catch.
  -- This lets jobs prove the fish was caught after acceptance and keeps
  -- the job completed even if a smaller fish is caught afterward.
  if w >= 10 then F.single_10_at = F.catches end
  if w >= 15 then F.single_15_at = F.catches end
  if w >= 20 then F.single_20_at = F.catches end
  F.total_lb   = (F.total_lb or 0) + w
  if w > (F.max_single or 0) then F.max_single = w end
  F.last_w     = w
  F.streak_live = (F.streak_live or 0) + 1
  if (F.streak_live or 0) > (F.streak or 0) then F.streak = F.streak_live end
  st.prog.fish = F
  save_mem(pid, st)
end

function JobBBS.on_fish_fail(pid, info)
  ensure_daily_reset(pid)
  local st = attach_state(pid); if not st then return end
  st.prog = st.prog or {}; st.prog.active = st.prog.active or {}
  if not st.prog.active.fish then return end
  st.prog.fish = st.prog.fish or { streak_live=0 }
  st.prog.fish.streak_live = 0

  -- Optional debug/help for players: remember what broke the streak last.
  -- (fishing.lua can pass { reason = 'moved'|'timeout'|'missed_bite'|'transfer'|... })
  if type(info) == 'table' then
    st.prog.fish.last_break = info.reason or st.prog.fish.last_break
    st.prog.fish.last_break_phase = info.phase or st.prog.fish.last_break_phase
    st.prog.fish.last_break_at = os.time()
  end
  save_mem(pid, st)
end

function JobBBS.on_fish_virus_start(pid, info)
  -- Treat a virus spawn as a "non-catch" that breaks a fish-catch streak.
  -- Otherwise streak jobs can feel inconsistent (you didn't catch a fish, but the streak kept going).
  ensure_daily_reset(pid)
  local st = attach_state(pid); if not st then return end
  st.prog = st.prog or {}; st.prog.active = st.prog.active or {}
  if not st.prog.active.fish then return end
  st.prog.fish = st.prog.fish or { streak_live = 0 }
  st.prog.fish.streak_live = 0
  if type(info) == 'table' then
    st.prog.fish.last_break = info.reason or 'virus_spawn'
    st.prog.fish.last_break_phase = 'reeling'
    st.prog.fish.last_break_at = os.time()
  else
    st.prog.fish.last_break = 'virus_spawn'
    st.prog.fish.last_break_phase = 'reeling'
    st.prog.fish.last_break_at = os.time()
  end
  save_mem(pid, st)
end

function JobBBS.on_fish_virus_result(pid, info)
  ensure_daily_reset(pid)
  local st = attach_state(pid); if not st then return end
  st.prog = st.prog or {}; st.prog.active = st.prog.active or {}
  if not st.prog.active.fish then return end
  local stats = info and info.stats
  if stats and not stats.ran then
    st.prog.fish = st.prog.fish or { virus_wins=0 }
    st.prog.fish.virus_wins = (st.prog.fish.virus_wins or 0) + 1
    save_mem(pid, st)
  end
end

function JobBBS.on_raid_progress(pid, info)
  ensure_daily_reset(pid)
  local st = attach_state(pid); if not st then return end
  st.prog = st.prog or {}
  st.prog.active = st.prog.active or {}
  if not st.prog.active.raid then return end

  st.prog.raid = st.prog.raid or { battles=0, points=0, boss_dmg=0, boss_kills=0 }

  local pts      = tonumber(info and info.points) or 0
  local boss_dmg = tonumber(info and (info.boss_damage or info.boss_dmg)) or 0
  local killed   = info and info.killed

  local participated = false

  -- Wave 1/2 participation (points)
  if pts > 0 then
    st.prog.raid.points  = (st.prog.raid.points  or 0) + pts
    participated = true
  end

  -- Wave 3 (boss) participation (damage)
  if boss_dmg > 0 then
    st.prog.raid.boss_dmg = (st.prog.raid.boss_dmg or 0) + boss_dmg
    participated = true
  end

  -- Count “participated in 1 raid battle” if they earned points OR dealt boss damage.
  -- (Avoid counting the kill-only callback as a second battle.)
  if participated then
    st.prog.raid.battles = (st.prog.raid.battles or 0) + 1
  end

  if killed then
    st.prog.raid.boss_kills = (st.prog.raid.boss_kills or 0) + 1
  end

  save_mem(pid, st)
end

return JobBBS
