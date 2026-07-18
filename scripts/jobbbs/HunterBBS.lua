-- scripts/jobbbs/HunterBBS.lua
-- Daily Dungeon1 virus bounties with limited claims and a monthly leaderboard.
--
-- Rules:
--   * Five shared bounties are rolled for the whole server each day.
--   * Each bounty requires 5-15 defeated copies of one virus/rank.
--   * Only generated random encounters won inside Dungeon1 count.
--   * Duplicate enemies count separately.
--   * Hunter points are earned immediately, up to that bounty's daily requirement.
--   * Money is paid only after completing and claiming a bounty.
--   * A player may claim at most three bounty rewards per day.
--   * LMenu Job Progress stays hidden until the player earns their first valid kill that day.
--   * The leaderboard shows this month's top five and last month's frozen top three.

local helpers  = require("scripts/ezlibs-scripts/helpers")
local ezmemory = require("scripts/ezlibs-scripts/ezmemory")

local HunterBBS = {}
_G.HunterBBS = HunterBBS

local DEBUG = true
local function dbg(...)
  if not DEBUG then return end
  local parts = { "[hunterbbs]" }
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  print(table.concat(parts, " "))
end

-- ============================================================================
-- Configuration
-- ============================================================================

local HUNTER_AREA_ID     = "Dungeon1"
local MEMORY_AREA_ID     = "Dungeon1"
local AREA_MEMORY_KEY    = "hunterbbs_v1"
local PLAYER_MEMORY_KEY  = "hunterbbs_v1"

local DEFAULT_BOARD_TITLE = "Hunter BBS"
local BOARD_COLOR         = { r = 2, g = 6, b = 59 }

local DAILY_BOUNTY_COUNT = 5
local REQUIRED_MIN       = 5
local REQUIRED_MAX       = 15
local MAX_DAILY_CLAIMS   = 5
local HUNTER_PET_XP      = 15

-- money_per_kill is multiplied by that day's rolled requirement when claimed.
-- leaderboard_points are awarded immediately for every counted kill.
--
-- These entries mirror every virus/rank currently available in Dungeon1's
-- generated random encounter pool. Adjust the money and point values here.
local HUNTER_DEFS = {
  { name = "Yort",      rank = 1, money_per_kill = 500, leaderboard_points = 2 },
  { name = "Gunner",    rank = 1, money_per_kill = 300, leaderboard_points = 1 },
  { name = "Gunner",    rank = 2, money_per_kill = 500, leaderboard_points = 2 },
  { name = "DemonEye",  rank = 1, money_per_kill = 500, leaderboard_points = 2 },
  { name = "TuffBunny", rank = 1, money_per_kill = 500, leaderboard_points = 2 },
  { name = "Volcano",   rank = 1, money_per_kill = 500, leaderboard_points = 2 },
  { name = "Volcano",   rank = 2, money_per_kill = 700, leaderboard_points = 3 },
  { name = "Metrid",    rank = 1, money_per_kill = 700, leaderboard_points = 2 },
  { name = "Metrid",    rank = 2, money_per_kill = 900, leaderboard_points = 3 },
  { name = "MegaCorn",  rank = 1, money_per_kill = 500, leaderboard_points = 2 },
  { name = "Fishy",     rank = 1, money_per_kill = 500, leaderboard_points = 2 },
  { name = "Fishy",     rank = 2, money_per_kill = 600, leaderboard_points = 3 },
  { name = "Beetank",   rank = 1, money_per_kill = 600, leaderboard_points = 2 },
  { name = "Beetank",   rank = 2, money_per_kill = 700, leaderboard_points = 3 },
  { name = "Spikey",    rank = 2, money_per_kill = 300, leaderboard_points = 1 },
  { name = "Spikey",    rank = 3, money_per_kill = 500, leaderboard_points = 2 },
  { name = "Swordy",    rank = 2, money_per_kill = 300, leaderboard_points = 1 },
  { name = "Swordy",    rank = 3, money_per_kill = 500, leaderboard_points = 2 },
  { name = "Quaker",    rank = 1, money_per_kill = 300, leaderboard_points = 1 },
  { name = "Quaker",    rank = 2, money_per_kill = 400, leaderboard_points = 2 },
}

HunterBBS.config = {
  hunter_area_id = HUNTER_AREA_ID,
  memory_area_id = MEMORY_AREA_ID,
  daily_bounty_count = DAILY_BOUNTY_COUNT,
  required_min = REQUIRED_MIN,
  required_max = REQUIRED_MAX,
  max_daily_claims = MAX_DAILY_CLAIMS,
  definitions = HUNTER_DEFS,
}

-- ============================================================================
-- Small helpers
-- ============================================================================

local function trunc(text, max_ch)
  text = tostring(text or "")
  max_ch = math.max(1, math.floor(tonumber(max_ch) or 28))
  if #text <= max_ch then return text end
  if max_ch <= 3 then return text:sub(1, max_ch) end
  return text:sub(1, max_ch - 3) .. "..."
end

-- Bounties are now tracked by virus species only.
local function bounty_key(name)
  return tostring(name or "")
end

-- Individual rank definitions still use name + rank so each rank
-- can retain its own money and leaderboard-point values.
local function definition_key(name, rank)
  return tostring(name or "")
    .. ":"
    .. tostring(math.floor(tonumber(rank) or 1))
end

local DEF_BY_KEY = {}
local DEFS_BY_NAME = {}

for _, def in ipairs(HUNTER_DEFS) do
  def.id = definition_key(def.name, def.rank)

  DEF_BY_KEY[def.id] = def

  DEFS_BY_NAME[def.name] = DEFS_BY_NAME[def.name] or {}
  DEFS_BY_NAME[def.name][#DEFS_BY_NAME[def.name] + 1] = def
end

local function today_key()
  return os.date("%Y-%m-%d")
end

local function month_key()
  return os.date("%Y-%m")
end

local function previous_month_key(key)
  local year, month = tostring(key or ""):match("^(%d%d%d%d)%-(%d%d)$")
  year = tonumber(year)
  month = tonumber(month)
  if not year or not month then return "" end

  month = month - 1
  if month <= 0 then
    month = 12
    year = year - 1
  end

  return string.format("%04d-%02d", year, month)
end

local function shuffle(arr)
  for i = #arr, 2, -1 do
    local j = math.random(i)
    arr[i], arr[j] = arr[j], arr[i]
  end
  return arr
end

local function safe_secret(pid)
  local ok, secret = pcall(helpers.get_safe_player_secret, pid)
  if ok and secret and secret ~= "" then
    return tostring(secret)
  end
  return nil
end

local function player_name(pid)
  if Net and Net.get_player_name then
    local ok, name = pcall(Net.get_player_name, pid)
    if ok and name and name ~= "" then
      return tostring(name)
    end
  end
  return "Player"
end

local function is_yes(response)
  if type(response) == "boolean" then return response == true end
  if type(response) == "number" then return response == 1 end
  if type(response) == "string" then
    local s = response:lower():gsub("^%s+", ""):gsub("%s+$", "")
    return s == "1" or s == "yes" or s == "y" or s == "true" or s == "ok"
  end
  return false
end

local function result_flags(stats)
  local reason = tonumber(stats and stats.reason or 0) or 0
  local hp = tonumber(stats and (stats.health or stats.player_hp or stats.hp) or 0) or 0

  local won, lost, ran, dev_escape = false, false, false, false

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
    reason = reason,
    hp = hp,
    won = won,
    lost = lost,
    ran = ran,
    dev_escape = dev_escape,
  }
end

-- ============================================================================
-- Area/global persistence
-- ============================================================================

local function get_area_slot()
  if not (ezmemory and ezmemory.get_area_memory) then
    return nil
  end

  local mem = ezmemory.get_area_memory(MEMORY_AREA_ID)
  if type(mem) ~= "table" then
    return nil
  end

  mem[AREA_MEMORY_KEY] = mem[AREA_MEMORY_KEY] or {}
  return mem[AREA_MEMORY_KEY], mem
end

local function save_area_slot()
  if ezmemory and ezmemory.save_area_memory then
    pcall(ezmemory.save_area_memory, MEMORY_AREA_ID)
  end
end

local function sorted_scores(score_map, limit)
  local rows = {}

  for secret, rec in pairs(score_map or {}) do
    if type(rec) == "table" then
      rows[#rows + 1] = {
        secret = tostring(secret),
        name = tostring(rec.name or "Player"),
        points = math.max(0, math.floor(tonumber(rec.points) or 0)),
      }
    end
  end

  table.sort(rows, function(a, b)
    if a.points ~= b.points then return a.points > b.points end
    return a.name:lower() < b.name:lower()
  end)

  if limit and #rows > limit then
    for i = #rows, limit + 1, -1 do
      rows[i] = nil
    end
  end

  return rows
end

local function roll_daily_bounties()
  local names = {}

  for name in pairs(DEFS_BY_NAME) do
    names[#names + 1] = name
  end

  shuffle(names)

  local out = {}
  local count = math.min(DAILY_BOUNTY_COUNT, #names)

  for i = 1, count do
    local name = names[i]

    out[#out + 1] = {
      id = bounty_key(name),
      name = name,
      required = math.random(REQUIRED_MIN, REQUIRED_MAX),
    }
  end

  table.sort(out, function(a, b)
    return tostring(a.name) < tostring(b.name)
  end)

  return out
end

local function ensure_global_state()
  local slot = get_area_slot()
  if not slot then return nil end

  local changed = false
  local current_month = month_key()

  slot.leaderboard = slot.leaderboard or {}
  local leaderboard = slot.leaderboard
  leaderboard.current = leaderboard.current or {}

  if leaderboard.month_key ~= current_month then
    local wanted_previous = previous_month_key(current_month)
    local previous_top3 = {}

    -- Only label the outgoing scores as "last month" when they really belong
    -- to the immediately preceding calendar month.
    if leaderboard.month_key == wanted_previous then
      previous_top3 = sorted_scores(leaderboard.current, 3)
    end

    leaderboard.previous_month = {
      month_key = wanted_previous,
      top3 = previous_top3,
    }
    leaderboard.month_key = current_month
    leaderboard.current = {}
    changed = true
    dbg("monthly rollover", wanted_previous, "->", current_month)
  end

  leaderboard.previous_month = leaderboard.previous_month or {
    month_key = previous_month_key(current_month),
    top3 = {},
  }

  slot.daily = slot.daily or {}
  if slot.daily.day_key ~= today_key() or type(slot.daily.bounties) ~= "table" or #slot.daily.bounties == 0 then
    slot.daily = {
      day_key = today_key(),
      bounties = roll_daily_bounties(),
    }
    changed = true
    dbg("rolled daily bounties for", slot.daily.day_key)
  end

  -- Convert today's existing rank-specific bounties into species bounties
  -- without rerolling the list or changing their current requirements.
  --
  -- The legacy fields remain attached until tomorrow so players who have not
  -- logged in yet can migrate their personal progress when they return.
  for _, bounty in ipairs(slot.daily.bounties or {}) do
    local species_id = bounty_key(bounty.name)
    local old_id = tostring(bounty.id or "")

    if old_id ~= species_id or bounty.rank ~= nil then
      if old_id ~= "" and old_id ~= species_id then
        bounty.legacy_id = bounty.legacy_id or old_id
      end

      if bounty.legacy_money_per_kill == nil then
        local legacy_def = bounty.legacy_id
          and DEF_BY_KEY[bounty.legacy_id]
          or nil

        bounty.legacy_money_per_kill =
          tonumber(bounty.money_per_kill)
          or tonumber(legacy_def and legacy_def.money_per_kill)
          or 0
      end

      bounty.id = species_id

      -- These values now come from the actual defeated enemy rank.
      bounty.rank = nil
      bounty.money_per_kill = nil
      bounty.leaderboard_points = nil

      changed = true

      dbg(
        "migrated daily bounty",
        old_id,
        "->",
        species_id
      )
    end
  end

  if changed then
    save_area_slot()
  end

  return slot
end

local function bounty_map(global_slot)
  local out = {}
  for _, bounty in ipairs(global_slot and global_slot.daily and global_slot.daily.bounties or {}) do
    out[bounty.id] = bounty
  end
  return out
end

-- ============================================================================
-- Player persistence
-- ============================================================================

local function get_player_memory(pid)
  local secret = safe_secret(pid)
  if not secret then return nil, nil end

  local mem = ezmemory.get_player_memory(secret)
  if type(mem) ~= "table" then mem = {} end
  return mem, secret
end

local function save_player_memory(pid, mem, secret)
  mem = mem or select(1, get_player_memory(pid))
  secret = secret or safe_secret(pid)
  if not mem or not secret then return false end

  if ezmemory.set_player_memory then
    pcall(ezmemory.set_player_memory, secret, mem)
  end
  if ezmemory.save_player_memory then
    pcall(ezmemory.save_player_memory, secret)
  end
  return true
end

local function ensure_player_state(pid, global_slot)
  global_slot = global_slot or ensure_global_state()
  if not global_slot then return nil end

  local mem, secret = get_player_memory(pid)
  if not mem then return nil end

  mem[PLAYER_MEMORY_KEY] = mem[PLAYER_MEMORY_KEY] or {}
  local st = mem[PLAYER_MEMORY_KEY]
  local changed = false

  if st.day_key ~= global_slot.daily.day_key then
    st.day_key = global_slot.daily.day_key
    st.kills = {}
    st.claimed = {}
    st.reward_money = {}
    st.claims_today = 0
    st.revealed = false
    changed = true
  end

  st.kills = st.kills or {}
  st.claimed = st.claimed or {}
  st.reward_money = st.reward_money or {}
  st.claims_today = math.max(0, math.floor(tonumber(st.claims_today) or 0))
  st.revealed = st.revealed == true

  -- Migrate today's rank-specific player progress.
  --
  -- Under the old system, only the selected rank could have counted, so the
  -- migrated money can safely use that old rank's configured value.
  for _, bounty in ipairs(global_slot.daily.bounties or {}) do
    local legacy_id = bounty.legacy_id
    local new_id = bounty.id

    if legacy_id and legacy_id ~= new_id then
      local had_legacy_data =
        st.kills[legacy_id] ~= nil
        or st.claimed[legacy_id] ~= nil
        or st.reward_money[legacy_id] ~= nil

      local old_count = math.max(
        0,
        math.floor(tonumber(st.kills[legacy_id]) or 0)
      )

      local current_count = math.max(
        0,
        math.floor(tonumber(st.kills[new_id]) or 0)
      )

      local required = math.max(
        1,
        math.floor(tonumber(bounty.required) or 1)
      )

      local transferable = math.min(
        old_count,
        math.max(0, required - current_count)
      )

      if transferable > 0 then
        st.kills[new_id] = current_count + transferable

        local legacy_def = DEF_BY_KEY[legacy_id]

        local old_money_per_kill =
          tonumber(bounty.legacy_money_per_kill)
          or tonumber(legacy_def and legacy_def.money_per_kill)
          or 0

        st.reward_money[new_id] =
          math.max(
            0,
            math.floor(tonumber(st.reward_money[new_id]) or 0)
          )
          + transferable * old_money_per_kill
      end

      if st.claimed[legacy_id] == true then
        st.claimed[new_id] = true
      end

      st.kills[legacy_id] = nil
      st.claimed[legacy_id] = nil
      st.reward_money[legacy_id] = nil

      if had_legacy_data then
        changed = true

        dbg(
          "migrated player bounty",
          legacy_id,
          "->",
          new_id,
          "kills",
          transferable
        )
      end
    end
  end

  -- Keep an existing monthly leaderboard display name current.
  local current = global_slot.leaderboard and global_slot.leaderboard.current
  if current and current[secret] and current[secret].name ~= player_name(pid) then
    current[secret].name = player_name(pid)
    save_area_slot()
  end

  if changed then
    save_player_memory(pid, mem, secret)
  end

  return st, mem, secret
end

local function add_monthly_points(pid, global_slot, secret, amount)
  amount = math.max(0, math.floor(tonumber(amount) or 0))
  if amount <= 0 then return end

  local current = global_slot.leaderboard.current
  local rec = current[secret] or { name = player_name(pid), points = 0 }
  rec.name = player_name(pid)
  rec.points = math.max(0, math.floor(tonumber(rec.points) or 0)) + amount
  current[secret] = rec
end

-- ============================================================================
-- Battle tracking
-- ============================================================================

function HunterBBS.on_encounter_result(pid, encounter_info, stats)
  if not pid or type(encounter_info) ~= "table" then return false end
  if tostring(encounter_info._area_id or "") ~= HUNTER_AREA_ID then return false end
  if encounter_info._random_encounter ~= true then return false end

  local flags = result_flags(stats)
  if not flags.won or flags.ran or flags.lost then
    return false
  end

  local global_slot = ensure_global_state()
  if not global_slot then return false end

  local st, mem, secret = ensure_player_state(pid, global_slot)
  if not st then return false end

  local daily_by_key = bounty_map(global_slot)

  local total_counted = 0
  local total_points = 0
  local total_money = 0

  -- Process every enemy entry separately.
  -- Two Gunners in the encounter therefore count as two bounty kills.
  for _, enemy in ipairs(encounter_info.enemies or {}) do
    if type(enemy) == "table" then
      local species_id = bounty_key(enemy.name)
      local bounty = daily_by_key[species_id]

      local def = DEF_BY_KEY[
        definition_key(enemy.name, enemy.rank)
      ]

      if bounty and def then
        local old_count = math.max(
          0,
          math.floor(tonumber(st.kills[species_id]) or 0)
        )

        local required = math.max(
          1,
          math.floor(tonumber(bounty.required) or 1)
        )

        -- Stop counting this species once today's requirement is reached.
        if old_count < required then
          local money = math.max(
            0,
            math.floor(tonumber(def.money_per_kill) or 0)
          )

          local points = math.max(
            0,
            math.floor(tonumber(def.leaderboard_points) or 0)
          )

          st.kills[species_id] = old_count + 1

          st.reward_money[species_id] =
            math.max(
              0,
              math.floor(tonumber(st.reward_money[species_id]) or 0)
            )
            + money

          total_counted = total_counted + 1
          total_money = total_money + money
          total_points = total_points + points
        end
      end
    end
  end

  if total_counted <= 0 then
    return false
  end

  st.revealed = true
  add_monthly_points(pid, global_slot, secret, total_points)
  save_player_memory(pid, mem, secret)
  save_area_slot()

  dbg(
    "counted",
    total_counted,
    "kills,",
    total_points,
    "points and $",
    total_money,
    "for",
    player_name(pid)
  )
  return true, total_counted, total_points
end

-- ============================================================================
-- Rewards
-- ============================================================================

local function give_money(pid, amount)
  amount = math.max(0, math.floor(tonumber(amount) or 0))
  if amount <= 0 then return false end

  local granted = false
  if ezmemory.spend_player_money then
    local ok, result = pcall(ezmemory.spend_player_money, pid, -amount)
    granted = ok and result ~= false
  end

  if not granted then
    local mem, secret = get_player_memory(pid)
    if not mem then return false end
    mem.money = math.max(0, math.floor(tonumber(mem.money) or 0)) + amount
    save_player_memory(pid, mem, secret)
    granted = true
  end

  if granted then
    if Net and Net.play_sound_for_player then
      pcall(Net.play_sound_for_player, pid, "/server/assets/ezlibs-assets/sfx/item_get.ogg")
    end
    Net.message_player(pid, string.format("Got $%d!", amount))
  end

  return granted
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

local function claim_bounty(pid, bounty_id)
  local global_slot = ensure_global_state()
  if not global_slot then return false, "Hunter data is unavailable." end

  local st, mem, secret = ensure_player_state(pid, global_slot)
  if not st then return false, "Hunter data is unavailable." end

  local bounty = bounty_map(global_slot)[bounty_id]
  if not bounty then return false, "That bounty is no longer active." end
  if st.claimed[bounty_id] then return false, "Already claimed today." end
  if st.claims_today >= MAX_DAILY_CLAIMS then
    return false, string.format("You already claimed %d bounties today.", MAX_DAILY_CLAIMS)
  end

  local cur = math.max(0, math.floor(tonumber(st.kills[bounty_id]) or 0))
  local required = math.max(1, math.floor(tonumber(bounty.required) or 1))
  if cur < required then
    return false, string.format("Progress: %d/%d", cur, required)
  end

  local reward = math.max(
    0,
    math.floor(tonumber(st.reward_money[bounty_id]) or 0)
  )

  -- Persist the claim before paying so repeated input cannot redeem twice.
  st.claimed[bounty_id] = true
  st.claims_today = st.claims_today + 1
  save_player_memory(pid, mem, secret)

  if reward > 0 then
    give_money(pid, reward)
  else
    Net.message_player(pid, "Bounty claimed.")
  end

  give_pet_xp(pid, HUNTER_PET_XP)

  return true, reward
end

-- ============================================================================
-- Hunter BBS UI
-- ============================================================================

local CURRENT_BOARD_TITLE = {}
local PENDING_CLAIM = {}
local PENDING_BOARD_OPEN = {}

local function guard_next_two_closes(pid)
  if _G._guard_ignore_next_close then
    _G._guard_ignore_next_close(pid, "hunterbbs")
    _G._guard_ignore_next_close(pid, "hunterbbs")
  end
end

local function bounty_status(st, bounty)
  local cur = math.max(0, math.floor(tonumber(st.kills[bounty.id]) or 0))
  local required = math.max(1, math.floor(tonumber(bounty.required) or 1))
  if cur > required then cur = required end

  local claimed = st.claimed[bounty.id] == true
  local ready = cur >= required

  return cur, required, claimed, ready
end

local function rank_value_lines(name)
  local lines = {}

  for _, def in ipairs(DEFS_BY_NAME[name] or {}) do
    lines[#lines + 1] = string.format(
      "R%d: $%d, %dpt",
      math.floor(tonumber(def.rank) or 1),
      math.floor(tonumber(def.money_per_kill) or 0),
      math.floor(tonumber(def.leaderboard_points) or 0)
    )
  end

  return lines
end

local function bounty_detail_text(st, bounty)
  local cur, required, claimed, ready = bounty_status(st, bounty)

  local reward_earned = math.max(
    0,
    math.floor(tonumber(st.reward_money[bounty.id]) or 0)
  )

  local lines = {
    tostring(bounty.name),
    string.format("Progress: %d/%d", cur, required),
    string.format("Reward earned: $%d", reward_earned),
  }

  for _, line in ipairs(rank_value_lines(bounty.name)) do
    lines[#lines + 1] = line
  end

  if claimed then
    lines[#lines + 1] = "Status: Claimed"
  elseif ready then
    lines[#lines + 1] = "Status: Ready to claim"
  else
    lines[#lines + 1] = "Status: In progress"
  end

  return table.concat(lines, string.char(10))
end

local function open_main_board(pid, board_title)
  local global_slot = ensure_global_state()
  if not global_slot then
    Net.message_player(pid, "Hunter data is unavailable.")
    return false
  end

  local st = ensure_player_state(pid, global_slot)
  if not st then
    Net.message_player(pid, "Hunter data is unavailable.")
    return false
  end

  board_title = tostring(board_title or CURRENT_BOARD_TITLE[pid] or DEFAULT_BOARD_TITLE)
  CURRENT_BOARD_TITLE[pid] = board_title

  local posts = {
    {
      id = "__hunter:claims",
      read = true,
      title = string.format("Claims today: %d/%d", st.claims_today, MAX_DAILY_CLAIMS),
      author = "",
    },
  }

  for _, bounty in ipairs(global_slot.daily.bounties or {}) do
    local cur, required, claimed, ready = bounty_status(st, bounty)
    local token
    if claimed then
      token = "[X]"
    elseif ready then
      token = "[!]"
    elseif cur > 0 then
      token = "[>]"
    else
      token = "[ ]"
    end

  posts[#posts + 1] = {
    id = "__hunter:bounty:" .. bounty.id,
    read = true,
    title = string.format(
      "%s %s %d/%d",
      token,
      bounty.name,
      cur,
      required
    ),
    author = "",
  }
  end

  posts[#posts + 1] = {
    id = "__hunter:leaderboard",
    read = true,
    title = "Hunter Leaderboard",
    author = "",
  }
  posts[#posts + 1] = { id = "__hunter:close", read = true, title = "Close", author = "" }

  guard_next_two_closes(pid)
  Net.open_board(pid, board_title, BOARD_COLOR, posts)
  return true
end

local function open_leaderboard(pid)
  local global_slot = ensure_global_state()
  if not global_slot then
    Net.message_player(pid, "Hunter leaderboard is unavailable.")
    return false
  end

  local _, _, secret = ensure_player_state(pid, global_slot)
  local current_scores = sorted_scores(global_slot.leaderboard.current, 5)
  local previous = global_slot.leaderboard.previous_month or { month_key = "", top3 = {} }

  local posts = {
    {
      id = "__hunter:lb:current_header",
      read = true,
      title = "This Month - " .. tostring(global_slot.leaderboard.month_key or month_key()),
      author = "",
    },
  }

  if #current_scores == 0 then
    posts[#posts + 1] = { id = "__hunter:lb:none_current", read = true, title = "No scores yet.", author = "" }
  else
    for i, rec in ipairs(current_scores) do
      posts[#posts + 1] = {
        id = "__hunter:lb:current:" .. tostring(i),
        read = true,
        title = trunc(string.format("%d. %s", i, rec.name), 28),
        author = tostring(rec.points) .. " pts",
      }
    end
  end

  local own = secret and global_slot.leaderboard.current[secret] or nil
  posts[#posts + 1] = {
    id = "__hunter:lb:own",
    read = true,
    title = "Current pts",
    author = tostring(math.max(0, math.floor(tonumber(own and own.points) or 0))),
  }

  posts[#posts + 1] = {
    id = "__hunter:lb:previous_header",
    read = true,
    title = "Last Month - " .. tostring(previous.month_key or previous_month_key(month_key())),
    author = "",
  }

  if type(previous.top3) ~= "table" or #previous.top3 == 0 then
    posts[#posts + 1] = { id = "__hunter:lb:none_previous", read = true, title = "No previous scores.", author = "" }
  else
    for i, rec in ipairs(previous.top3) do
      posts[#posts + 1] = {
        id = "__hunter:lb:previous:" .. tostring(i),
        read = true,
        title = trunc(string.format("%d. %s", i, tostring(rec.name or "Player")), 28),
        author = tostring(math.max(0, math.floor(tonumber(rec.points) or 0))) .. " pts",
      }
    end
  end

  posts[#posts + 1] = { id = "__hunter:back", read = true, title = "Back", author = "" }
  posts[#posts + 1] = { id = "__hunter:close", read = true, title = "Close", author = "" }

  guard_next_two_closes(pid)
  Net.open_board(pid, "Hunter Leaderboard", BOARD_COLOR, posts)
  return true
end

function HunterBBS.open(pid, board_title)
  return open_main_board(pid, board_title)
end

function HunterBBS.open_leaderboard(pid)
  return open_leaderboard(pid)
end

function HunterBBS.handle_post_selection(event)
  local pid = event and (event.player_id or event[1])
  local post_id = event and (event.post_id or event[2])
  if not pid or post_id == nil then return false end

  local post = tostring(post_id)
  if not post:match("^__hunter:") then return false end

  if post == "__hunter:close" then
    Net.close_bbs(pid)
    return true
  end

  if post == "__hunter:back" then
    PENDING_BOARD_OPEN[pid] = {
      kind = "main",
      board_title = CURRENT_BOARD_TITLE[pid] or DEFAULT_BOARD_TITLE,
    }

    guard_next_two_closes(pid)
    pcall(Net.close_bbs, pid)
    return true
  end

  if post == "__hunter:leaderboard" then
    PENDING_BOARD_OPEN[pid] = {
      kind = "leaderboard",
    }

    guard_next_two_closes(pid)
    pcall(Net.close_bbs, pid)
    return true
  end

  local id = post:match("^__hunter:bounty:(.+)$")
  if not id then return true end

  local global_slot = ensure_global_state()
  local st = global_slot and ensure_player_state(pid, global_slot) or nil
  local bounty = global_slot and bounty_map(global_slot)[id] or nil

  if not st or not bounty then
    Net.message_player(pid, "That bounty is no longer active.")
    return true
  end

  local _, _, claimed, ready = bounty_status(st, bounty)
  local details = bounty_detail_text(st, bounty)

  if claimed then
    Net.message_player(pid, details)
    return true
  end

  if ready then
    if st.claims_today >= MAX_DAILY_CLAIMS then
      Net.message_player(pid, details .. string.char(10) .. string.format(
        "Daily claim limit reached: %d/%d",
        st.claims_today,
        MAX_DAILY_CLAIMS
      ))
      return true
    end

    Net.message_player(pid, details)
    PENDING_CLAIM[pid] = {
      bounty_id = id,
      step = "info",
      board_title = CURRENT_BOARD_TITLE[pid] or DEFAULT_BOARD_TITLE,
    }
  else
    Net.message_player(pid, details)
  end

  return true
end

function HunterBBS.handle_textbox_response(pid, response)
  local pending = PENDING_CLAIM[pid]
  if not pending then return false end

  if pending.step == "info" then
    pending.step = "question"
    Net.question_player(pid, "Claim this hunter reward?")
    return true
  end

  PENDING_CLAIM[pid] = nil

  if is_yes(response) then
    local ok, result = claim_bounty(pid, pending.bounty_id)
    if not ok then
      Net.message_player(pid, tostring(result or "Unable to claim bounty."))
    end
  end

  open_main_board(pid, pending.board_title)
  return true
end

-- ============================================================================
-- MenuAPI Job Progress integration
-- ============================================================================

local function get_menuapi()
  local MenuAPI = rawget(_G, "MenuAPI")
  if not (MenuAPI and type(MenuAPI.open) == "function") then
    local ok, mod = pcall(require, "scripts/menuAPI/main")
    if ok and type(mod) == "table" then MenuAPI = mod end
  end
  return MenuAPI
end

local function menuapi_tint(name, key)
  local MenuAPI = get_menuapi()
  if MenuAPI and type(MenuAPI.get_palette) == "function" then
    local palette = MenuAPI.get_palette(name)
    if palette and palette[key] then return palette[key] end
  end
  return nil
end

function HunterBBS.build_menuapi_progress_rows(pid)
  local global_slot = ensure_global_state()
  if not global_slot then return {} end

  local st = ensure_player_state(pid, global_slot)
  if not st or not st.revealed then
    return {}
  end

  local rows = {
    {
      id = "__hunterprog:header",
      text = "Hunter Bounties",
      selectable = false,
      enabled = false,
      disabled_prefix = false,
      show_right = false,
      tint = menuapi_tint("purple", "row_tint"),
    },
  }

  for _, bounty in ipairs(global_slot.daily.bounties or {}) do
    local cur, required, claimed, ready = bounty_status(st, bounty)
    local tint_name = (claimed or ready) and "green" or "gold"

    rows[#rows + 1] = {
      id = "__hunterprog:bounty:" .. bounty.id,
      text = trunc(tostring(bounty.name), 20),

      right = claimed
        and "Done"
        or (
          ready
          and "Ready"
          or string.format("%d/%d", cur, required)
        ),

      tint = menuapi_tint(tint_name, "row_tint"),
      right_tint = menuapi_tint(tint_name, "right_tint"),

      hunter_bounty = true,
      hunter_bounty_id = bounty.id,
      hunter_name = bounty.name,
      hunter_cur = cur,
      hunter_required = required,
      hunter_claimed = claimed,
      hunter_ready = ready,

      hunter_reward = math.max(
        0,
        math.floor(tonumber(st.reward_money[bounty.id]) or 0)
      ),

      hunter_claims_today = st.claims_today,
      hunter_claim_limit = MAX_DAILY_CLAIMS,
    }
  end

  return rows
end

function HunterBBS.handle_menuapi_progress_confirm(pid, row, menu_state, opts)
  if type(row) ~= "table" or row.hunter_bounty ~= true then
    return false
  end

  opts = opts or {}

  local cur = math.max(
    0,
    math.floor(tonumber(row.hunter_cur) or 0)
  )

  local required = math.max(
    0,
    math.floor(tonumber(row.hunter_required) or 0)
  )

  local reward = math.max(
    0,
    math.floor(tonumber(row.hunter_reward) or 0)
  )

  local status

  if row.hunter_claimed then
    status = string.format("Claimed: %d/%d", cur, required)
  elseif row.hunter_ready then
    status = string.format("Ready: %d/%d", cur, required)
  else
    status = string.format("Progress: %d/%d", cur, required)
  end

  local value_lines = rank_value_lines(row.hunter_name)

  local MenuAPI = get_menuapi()

  if not (MenuAPI and type(MenuAPI.open) == "function") then
    local lines = {
      tostring(row.hunter_name or "Bounty"),
      status,
      string.format("Reward earned: $%d", reward),
    }

    for _, line in ipairs(value_lines) do
      lines[#lines + 1] = line
    end

    Net.message_player(
      pid,
      table.concat(lines, string.char(10))
    )

    return true
  end

  local status_tint = menuapi_tint(
    (row.hunter_claimed or row.hunter_ready)
      and "green"
      or "gold",
    "row_tint"
  )

  local gray_tint = menuapi_tint("gray", "row_tint")
  local detail_rows = {}

  detail_rows[#detail_rows + 1] = {
    id = "__hunterdetail:status",
    text = status,
    selectable = false,
    disabled_prefix = false,
    tint = status_tint,
    show_right = false,
  }

  detail_rows[#detail_rows + 1] = {
    id = "__hunterdetail:reward",
    text = string.format("Reward earned: $%d", reward),
    selectable = false,
    disabled_prefix = false,
    tint = gray_tint,
    show_right = false,
  }

  for i, line in ipairs(value_lines) do
    detail_rows[#detail_rows + 1] = {
      id = "__hunterdetail:rank:" .. tostring(i),
      text = line,
      selectable = false,
      disabled_prefix = false,
      tint = gray_tint,
      show_right = false,
    }
  end

  detail_rows[#detail_rows + 1] = {
    id = "__hunterdetail:claims",
    text = string.format(
      "Claims: %d/%d",
      row.hunter_claims_today or 0,
      row.hunter_claim_limit or MAX_DAILY_CLAIMS
    ),
    selectable = false,
    disabled_prefix = false,
    tint = gray_tint,
    show_right = false,
  }

  MenuAPI.open(pid, {
    type = 2,
    title = trunc(
      tostring(row.hunter_name or "Bounty"),
      18
    ),

    color = (row.hunter_claimed or row.hunter_ready)
      and "green"
      or "gold",

    open_sfx = false,
    lock_input = false,
    cursor_enabled = false,
    scroll_enabled = false,
    show_right = false,
    rows = detail_rows,

    parent = function(player_id)
      local JobBBS =
        package.loaded["scripts/jobbbs/JobBBS"]

      if JobBBS
        and type(JobBBS.open_menuapi_progress) == "function"
      then
        JobBBS.open_menuapi_progress(player_id, {
          parent = opts.parent or "lmenu",
          color = opts.color or "blue",
          title = opts.title or "Job Progress",
          lock_input = false,
          open_sfx = false,
        })
      end
    end,
  })

  return true
end

-- ============================================================================
-- Engine listeners
-- ============================================================================

if _G.Net and Net.on and not rawget(_G, "__HUNTERBBS_LISTENERS_HOOKED__") then
  _G.__HUNTERBBS_LISTENERS_HOOKED__ = true

  Net:on("object_interaction", function(a, b, c)
    local event = type(a) == "table" and a or { player_id = a, object_id = b, button = c }
    local pid = event.player_id
    if not pid or event.button ~= 0 then return end

    local area_id = tostring(event.area or event.area_id or Net.get_player_area(pid) or "")
    local object_id = event.object_id
    if area_id == "" or object_id == nil then return end

    local object = Net.get_object_by_id(area_id, object_id)
    if not object then return end

    local class = tostring(object.class or "")
    local object_type = tostring(object.type or "")
    if class ~= "HunterBBS" and object_type ~= "HunterBBS" then return end

    local props = object.custom_properties or {}
    local title = tostring(props["Board Title"] or props["Name"] or object.name or DEFAULT_BOARD_TITLE)
    open_main_board(pid, title)
  end)

  Net:on("post_selection", function(a, b)
    local event = type(a) == "table" and a or { player_id = a, post_id = b }
    HunterBBS.handle_post_selection(event)
  end)

  Net:on("textbox_response", function(a, b)
    local pid, response
    if type(a) == "table" then
      pid = a.player_id or a[1]
      response = a.response ~= nil and a.response or a[2]
    else
      pid, response = a, b
    end

    if pid and response ~= nil then
      HunterBBS.handle_textbox_response(pid, response)
    end
  end)

  Net:on("board_close", function(event)
    local pid = type(event) == "table"
      and (event.player_id or event[1])
      or event

    if not pid then return end

    local pending = PENDING_BOARD_OPEN[pid]
    if not pending then return end

    PENDING_BOARD_OPEN[pid] = nil

    if pending.kind == "leaderboard" then
      open_leaderboard(pid)

    elseif pending.kind == "main" then
      open_main_board(
        pid,
        pending.board_title or CURRENT_BOARD_TITLE[pid] or DEFAULT_BOARD_TITLE
      )
    end
  end)

  Net:on("player_disconnect", function(event)
    local pid = type(event) == "table" and (event.player_id or event[1]) or event
    if not pid then return end
    CURRENT_BOARD_TITLE[pid] = nil
    PENDING_CLAIM[pid] = nil
    PENDING_BOARD_OPEN[pid] = nil
  end)
end

return HunterBBS
