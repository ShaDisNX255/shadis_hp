-- scripts/ezlibs-custom/pets.lua
-- Anchorless "Virus Pet" system + Expedition v1 (OnceHub HPs).
--
-- Pets are bots (Net.create_bot) with waypoint movement (eznpcs-style).
-- Placement/removal is handled by eznpcs_onceitem.lua (Home Hub -> Pets).
--
-- Persistence (area memory, bucket area set by OnceHub):
--   mem.oncehub_pets_v1[oncehub_key] = { pet_entry, ... }
--
-- Expedition v1:
--   • Pet has fatigue counter -> mood (happy/neutral/sad)
--   • Feed 1 BugFrag to raise 1 mood tier
--   • 1 expedition per player at a time
--   • Expedition lasts 1 hour, pet roams a random configured area
--   • Pet returns to original HP + stores reward until the OWNER interacts
--   • Cooldown after returning (longer if sad)
--   • If HP rental expires, expedition is cancelled and pet is removed

local pets = {}

-- ====================== Requires ======================
local helpers  = require('scripts/ezlibs-scripts/helpers')
local ezmenus  = require('scripts/ezlibs-scripts/ezmenus')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')

-- Teams is optional; we only call it if available.
local Teams = (function()
  local ok, M = pcall(require, 'scripts/teams/teams')
  if ok and M then return M end
  return rawget(_G, "Teams")
end)()

-- ====================== Config ======================
local CONFIG = {
  -- How often a pet considers choosing a new wander target (seconds)
  move_interval_sec = 5.0,
  move_jitter_sec   = 1.5,

  -- If blocked while moving, how long to wait before giving up and picking a new target
  blocked_timeout_sec = 1.25,

  -- Pet collision + movement
  size  = 0.20,
  speed = 2.00,

  -- If you want pets to be solid (can't walk through)
  solid = true,

  -- Choose movement directions (virus/isometric)
  directions = { "Up Left", "Up Right", "Down Left", "Down Right" },

  -- How close to a waypoint counts as "arrived"
  arrive_epsilon = 0.05,
}

-- ====================== Expedition v1 Config ======================
local EXPEDITION = {
  debug = true, -- set false when stable
  -- Expedition duration (minutes). Set to 1 for testing.
  duration_minutes = 60,

  -- Derived seconds value (do not edit directly)
  duration_sec = 60 * 60,
  -- Mood thresholds based on FATIGUE (increments by 1 per expedition)
  -- happy: 0..14 (15 expeditions to drop to neutral)
  -- neutral: 15..34 (20 more to drop to sad)
  -- sad: 35+
  happy_to_neutral = 15,
  neutral_to_sad   = 35,

  -- Feed cost
  feed_frag_cost = 1,

  -- Cooldowns after returning (seconds)
  cooldown_by_mood = {
    happy   = 30 * 60,
    neutral = 40 * 60,
    sad     = 50 * 60,
  },

  -- Where pets can roam during expeditions (your provided starter list)
  roam_areas = {
    { area_id="decorshop", x=14, y=10, z=0, label="Decor Shop" },
    { area_id="default",   x=26, y=26, z=0, label="ShaDis_Home" },
    { area_id="rink",   x=24, y=38, z=0, label="Ice_Rink1" },
    { area_id="rink2",   x=24, y=40, z=0, label="Ice_Rink2" },
    { area_id="rink3",   x=24, y=38, z=0, label="Ice_Rink3" },
    { area_id="WCity1",   x=42, y=34, z=3, label="WCity1" },
    { area_id="WCity2",   x=7, y=19, z=0, label="WCity2" },
    { area_id="WCity3",   x=28, y=17, z=0, label="WCity3" },
  },

  -- Reward tables: weights should sum to 100 (you can tweak freely).
  -- NOTE: "nothing" is represented as a small consolation (money) reward.
  reward_tables = {
    neutral = {
      { id="consolation", weight=50 },
      { id="money",       weight=25 },
      { id="card",        weight=15 },
      { id="gp",          weight=7  },
      { id="frag",        weight=3  },
    },
    happy = {
      { id="consolation", weight=45 }, -- 5% better odds than neutral
      { id="money",       weight=27 },
      { id="card",        weight=17 },
      { id="gp",          weight=7  },
      { id="frag",        weight=4  },
    },
    sad = {
      { id="consolation", weight=55 }, -- 5% worse odds than neutral
      { id="money",       weight=24 },
      { id="card",        weight=13 },
      { id="gp",          weight=6  },
      { id="frag",        weight=2  },
    },
  },

  -- Reward parameters
  consolation_money = 10000,
  money_min = 50000,
  money_max = 100000,

  gp_amount   = 1,
  frag_amount = 1,

  -- If the card pool is empty, "card" rolls will fall back to money.
  card_pool = {
    -- EXAMPLES (safe placeholders). Replace with your real pool anytime.
    { name="[UR]S.Skull", description="URare: Summoned Skull - A: 2500 / D: 1200"},
    { name="[UR]B.L.S.", description="URare: Black Luster Soldier - A: 3000 / D: 2500"},
    { name="[UR]Seiyaryu", description="URare: Seiyaryu - A: 2500 / D: 2300"},
    { name="[GR]DMGirl", description="GRare: Dark Magician Girl - A: 2000 / D: 1700"},
    { name="[GR]DMag", description="GRare: Dark Magician - A: 2500 / D: 2100"},
    { name="[GR]B.Sk.D.", description="GRare: Black Skull Dragon - A: 3200 / D: 2500"},
    { name="[GDR]Kbo", description="GDRare: Kuriboh - A: 300 / D: 200" },
    { name="[SR]F.A.V.Lord", description="FullArt: Vampire Lord - A: 2000 / D: 1500"},
    { name="[SR]F.A.DMGirl", description="FullArt: Dark Magician Girl - A: 2000 / D: 1700"},
    { name="[GDR]F.A.DMGirl", description="FullArt: Dark Magician Girl - A: 2000 / D: 1700"},
  },
}

-- Derive duration_sec from duration_minutes (allows easy testing).
EXPEDITION.duration_sec = math.max(1, math.floor((tonumber(EXPEDITION.duration_minutes) or 60) * 60))

-- ====================== Pet Definitions ======================
local PET_DEFS = {
  mettaur = { name = "Mettaur", texture = "mettaur.png", animation = "mettaur.animation" },
  meddy  = { name = "Meddy",  texture = "meddy.png",  animation = "meddy.animation"  },
  ratty  = { name = "Ratty",  texture = "ratty.png",  animation = "ratty.animation"  },
  spooky  = { name = "Spooky",  texture = "spooky.png",  animation = "spooky.animation"  },
  swordy  = { name = "Swordy",  texture = "Swordy.png",  animation = "Swordy.animation"  },
  moloko  = { name = "Moloko",  texture = "Moloko.png",  animation = "Moloko.animation"  },
  powie  = { name = "Powie",  texture = "Powie.png",  animation = "Powie.animation"  },
  kabutank  = { name = "Kabutank",  texture = "kabutank.png",  animation = "kabutank.animation"  },
}

local function build_paths(kind)
  local def = PET_DEFS[kind]
  if not def then return nil end
  return def,
    ("/server/assets/pets/" .. def.texture),
    ("/server/assets/pets/" .. def.animation)
end

-- Direction suffix used for animation state names like WALK_UR, IDLE_DL.
local DIR_SUFFIX = {
  ["Up Right"] = "UR",
  ["Up Left"]  = "UL",
  ["Down Right"] = "DR",
  ["Down Left"]  = "DL",
}

-- Isometric tile delta mapping.
local DIR_VECTORS = {
  ["Up Left"]    = { -1,  0 },
  ["Up Right"]   = {  0, -1 },
  ["Down Left"]  = {  0,  1 },
  ["Down Right"] = {  1,  0 },
}

local function dir_to_vec(dir)
  local v = DIR_VECTORS[dir]
  if not v then return 0, 0 end
  return v[1], v[2]
end

local function nearest_tile(n)
  if n >= 0 then return math.floor(n + 0.5) end
  return math.ceil(n - 0.5)
end

local function now_seed_rng()
  pcall(function() math.randomseed(os.time() % 2147483647) end)
end

local function dbg(...)
  if not EXPEDITION.debug then return end
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts+1] = tostring(select(i, ...))
  end
  print("[pets][exp] "..table.concat(parts, " "))
end

-- Ask custom.lua to ignore the very next board_close for this player (one-shot)
-- Needed because custom.lua listens for board_close and may "consume" the click that closed our board.
local function _mark_ignore_next_close(pid, reason)
  -- Some servers have a custom.lua "click guardian" that will consume board events.
  -- OnceHub uses _guard_ignore_next_close(); some servers also expose guards for selection events.
  if not _G then return end
  local why = reason or "pets"
  if _G._guard_ignore_next_close then
    _G._guard_ignore_next_close(pid, why)
  end
  if _G._guard_ignore_next_post_selection then
    _G._guard_ignore_next_post_selection(pid, why)
  end
  if _G._guard_ignore_next_post then
    _G._guard_ignore_next_post(pid, why)
  end
  if _G._guard_ignore_next_selection then
    _G._guard_ignore_next_selection(pid, why)
  end
end

-- Wrapper: mark ignore + open board (returns the board handle like Net.open_board)
local function _open_menu_ignoring_custom(pid, title, color, posts, reason)
  _mark_ignore_next_close(pid, reason or ("pets:"..tostring(title)))
  dbg("open_menu:", title, "reason=", reason or "")
  return ezmenus.open_menu(pid, title, color, posts)
end

local function _now() return os.time() end

local function _fmt_time_left(sec)
  sec = math.max(0, math.floor(tonumber(sec) or 0))
  local m = math.floor(sec / 60)
  local s = sec % 60
  if m >= 60 then
    local h = math.floor(m / 60)
    m = m % 60
    return string.format("%dh %dm", h, m)
  end
  return string.format("%dm %ds", m, s)
end

-- ====================== Memory helpers ======================
local function ensure_bucket_mem(bucket_area_id)
  local mem = ezmemory.get_area_memory(bucket_area_id) or ezmemory.get_area_memory(bucket_area_id)
  if not mem then error("pets.lua: Failed to initialize area memory for "..tostring(bucket_area_id)) end
  if mem.oncehub_pets_v1 == nil then mem.oncehub_pets_v1 = {} end
  if mem.oncehub_pet_expeditions_v1 == nil then mem.oncehub_pet_expeditions_v1 = {} end
  -- Pet stats that should survive remove/re-summon (ex: fatigue / mood)
  if mem.oncehub_pet_stats_v1 == nil then mem.oncehub_pet_stats_v1 = {} end
  return mem
end

local function load_pet_list(bucket_area_id, oncehub_key)
  local mem = ensure_bucket_mem(bucket_area_id)
  local t = mem.oncehub_pets_v1[oncehub_key]
  if t == nil then
    t = {}
    mem.oncehub_pets_v1[oncehub_key] = t
    pcall(function() ezmemory.save_area_memory(bucket_area_id) end)
  end
  return t, mem
end

local function save_bucket(bucket_area_id)
  pcall(function() ezmemory.save_area_memory(bucket_area_id) end)
end

-- ====================== Pet stats persistence ======================
-- Keep fatigue/mood even if the renter removes & re-summons the pet.
-- Stored in bucket area memory:
--   mem.oncehub_pet_stats_v1[owner_secret][kind].fatigue = <int>
local function _ensure_pet_stats(bucket_area_id)
  local mem = ensure_bucket_mem(bucket_area_id)
  if type(mem.oncehub_pet_stats_v1) ~= "table" then
    mem.oncehub_pet_stats_v1 = {}
  end
  return mem.oncehub_pet_stats_v1
end

local function _get_saved_fatigue(bucket_area_id, owner_secret, kind)
  if not owner_secret or owner_secret == "" then return nil end
  kind = tostring(kind or ""):lower()
  local stats = _ensure_pet_stats(bucket_area_id)
  local by_owner = stats[owner_secret]
  if type(by_owner) ~= "table" then return nil end
  local rec = by_owner[kind]
  if type(rec) ~= "table" then return nil end
  return tonumber(rec.fatigue)
end

local function _set_saved_fatigue(bucket_area_id, owner_secret, kind, fatigue)
  if not owner_secret or owner_secret == "" then return end
  kind = tostring(kind or ""):lower()
  local stats = _ensure_pet_stats(bucket_area_id)
  local by_owner = stats[owner_secret]
  if type(by_owner) ~= "table" then
    by_owner = {}
    stats[owner_secret] = by_owner
  end
  local rec = by_owner[kind]
  if type(rec) ~= "table" then
    rec = {}
    by_owner[kind] = rec
  end
  rec.fatigue = math.max(0, math.floor(tonumber(fatigue) or 0))
  pcall(function() ezmemory.save_area_memory(bucket_area_id) end)
end

local function _get_hp_lease(bucket_area_id, oncehub_key)
  local mem = ensure_bucket_mem(bucket_area_id)
  return mem.onceitems and mem.onceitems[oncehub_key] or nil
end

local function _get_hp_owner_secret(bucket_area_id, oncehub_key)
  local lease = _get_hp_lease(bucket_area_id, oncehub_key)
  return lease and lease.owner_secret or nil
end

local function _get_hp_expires_at(bucket_area_id, oncehub_key)
  local lease = _get_hp_lease(bucket_area_id, oncehub_key)
  return lease and tonumber(lease.expires_at) or nil
end

-- Normalize / migrate an entry in-place (keeps old pets working).
local function normalize_entry(e, bucket_area_id, oncehub_key)
  if type(e) ~= "table" then return nil end

  e.uid  = tostring(e.uid or "")
  e.kind = tostring(e.kind or ""):lower()
  if e.kind == "" then e.kind = "mettaur" end

  e.bucket_area_id = e.bucket_area_id or bucket_area_id
  e.oncehub_key    = e.oncehub_key or oncehub_key

  -- Owner info: older saves stored "secret" as boolean. Recover from current lease if possible.
  if type(e.owner_secret) ~= "string" or e.owner_secret == "" then
    local s = _get_hp_owner_secret(bucket_area_id, oncehub_key)
    if type(s) == "string" and s ~= "" then
      e.owner_secret = s
    else
      e.owner_secret = e.owner_secret or ""
    end
  end
  if type(e.owner_name) ~= "string" or e.owner_name == "" then
    e.owner_name = e.owner_name or ""
  end

  -- Fatigue: migrate from old "emotion" if present.
  if e.fatigue == nil then
    local emo = tostring(e.emotion or "happy")
    if emo == "neutral" then
      e.fatigue = EXPEDITION.happy_to_neutral
    elseif emo == "angry" or emo == "sad" then
      e.fatigue = EXPEDITION.neutral_to_sad
    else
      e.fatigue = 0
    end
  end
  e.fatigue = math.max(0, math.floor(tonumber(e.fatigue) or 0))

  e.cooldown_ends_at = math.floor(tonumber(e.cooldown_ends_at) or 0)

  -- Home position (where it must return)
  e.home_area_id = e.home_area_id or e.area_id
  e.home_x = e.home_x or e.x
  e.home_y = e.home_y or e.y
  e.home_z = e.home_z or e.z or 0

  -- Current position
  e.area_id = tostring(e.area_id or e.home_area_id or "")
  e.x = tonumber(e.x or e.home_x or 0) or 0
  e.y = tonumber(e.y or e.home_y or 0) or 0
  e.z = tonumber(e.z or e.home_z or 0) or 0

  -- Expedition
  if type(e.exp) ~= "table" then e.exp = {} end
  e.exp.active = e.exp.active and true or false
  e.exp.started_at = math.floor(tonumber(e.exp.started_at) or 0)
  e.exp.ends_at    = math.floor(tonumber(e.exp.ends_at) or 0)
  e.exp.mood       = tostring(e.exp.mood or "")
  e.exp.lease_expires_at = math.floor(tonumber(e.exp.lease_expires_at) or 0)

  if type(e.exp.dest) ~= "table" then e.exp.dest = nil end
  if type(e.exp.reward) ~= "table" then e.exp.reward = nil end
  e.exp.reward_pending = e.exp.reward_pending and true or false

  return e
end

local function mood_from_fatigue(fatigue)
  fatigue = tonumber(fatigue) or 0
  if fatigue >= EXPEDITION.neutral_to_sad then
    return "sad"
  elseif fatigue >= EXPEDITION.happy_to_neutral then
    return "neutral"
  end
  return "happy"
end

-- ====================== Nickname + "Pet it" lines ======================
local function _get_player_bugfrags(pid)
  local n = 0
  pcall(function()
    if ezmemory.get_player_fragments then
      n = ezmemory.get_player_fragments(pid)
    elseif Net.get_player_fragments then
      n = Net.get_player_fragments(pid)
    end
  end)
  return tonumber(n) or 0
end

local function _sanitize_nickname(s)
  s = tostring(s or "")
  -- strip control chars + collapse whitespace
  s = s:gsub("[%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then return "" end
  local max_len = 16
  if #s > max_len then s = s:sub(1, max_len) end
  return s
end

local PET_IT_LINES = {
  happy = {
    "It hops in place and gives a proud little chirp.",
    "It leans into your hand like it was waiting for that.",
    "It wiggles happily, sparks of energy popping around it.",
    "It does a tiny victory pose, then looks back at you to see your reaction.",
    "It circles you once and settles down, content.",
    "It bounces twice, like it's trying to show off how energetic it feels.",
    "It happily nudges your hand again, clearly asking for one more pat.",
    "It gives a bright little beep and does a quick spin in place.",
    "It puffs itself up proudly, then relaxes with a satisfied wiggle.",
    "It chirps and taps the floor like it's drumming a tiny celebration.",
  },
  neutral = {
    "It tilts its head, watching your hand carefully.",
    "It accepts the pat, then goes back to scanning the room.",
    "It makes a small sound-neither excited nor upset.",
    "It shifts its feet and looks around, mildly curious.",
    "It relaxes a little, but still seems focused.",
    "It blinks slowly, then gives a small nod like it understands.",
    "It pauses for a second, then resumes its steady little pacing.",
    "It lets you pet it, but keeps one eye on its surroundings.",
    "It gives a quiet hum, then settles into a calm stance.",
    "It seems to appreciate it... though it won't admit it out loud.",
  },
  sad = {
    "It flinches at first, then slowly relaxes under your hand.",
    "It looks down, but stays close as if comforted.",
    "It lets out a tiny sigh and blinks a few times.",
    "It scoots closer, like it doesn't want to be left alone.",
    "It gives a quiet little sound… it seems to want reassurance.",
    "It hesitates, then leans into your hand like it needed that.",
    "It looks up at you for a moment, then quietly stays by your side.",
    "It shuffles its feet and gives a small, shaky little chirp.",
    "It relaxes just a bit, but still seems worried about something.",
    "It stays still under your hand, soaking up the comfort.",
  },
}

local function _pick_one(list)
  local n = (type(list) == "table") and #list or 0
  if n <= 0 then return nil end
  now_seed_rng()
  return list[math.random(1, n)]
end

local function _pet_it_text(mood)
  return _pick_one(PET_IT_LINES[mood] or PET_IT_LINES.happy) or "It seems content."
end

local function _validate_reward_tables()
  for mood, entries in pairs(EXPEDITION.reward_tables or {}) do
    local total = 0
    for _, e in ipairs(entries or {}) do total = total + (tonumber(e.weight) or 0) end
    if total ~= 100 then
      print(("[pets][exp] WARNING: reward_tables.%s weights sum to %d (expected 100)"):format(tostring(mood), total))
    end
  end
end

local function pick_weighted(entries)
  local total = 0
  for _, e in ipairs(entries or {}) do total = total + (tonumber(e.weight) or 0) end
  if total <= 0 then return nil end
  local r = math.random() * total
  local acc = 0
  for _, e in ipairs(entries or {}) do
    acc = acc + (tonumber(e.weight) or 0)
    if r <= acc then return e end
  end
  return entries[#entries]
end

-- ====================== Runtime state ======================
-- uid -> rec
local records = {}
-- area_id -> { uid=true, ... }
local by_area = {}
-- bot_id(string) -> uid
local bot_to_uid = {}

local world_time = 0
local next_area_scan_time = 0
local area_has_players = {}

-- ====================== Helpers ======================
local function is_pet_id(item_id)
  return type(item_id) == "string" and item_id:sub(1, 4) == "pet_"
end
pets.is_pet_id = is_pet_id

local function blocked(area_id, x, y, z, size)
  local zz = z or 0

  -- Hard-guard: never wander outside map bounds
  if Net.get_width and Net.get_height then
    local w = Net.get_width(area_id)
    local h = Net.get_height(area_id)
    if w and h then
      if x < 0 or y < 0 or x >= w or y >= h then
        return true
      end
    end
  end

  -- Extra guard: don't step onto "void" tiles (gid == 0) on the current z-layer
  if Net.get_tile then
    local gx = nearest_tile(x)
    local gy = nearest_tile(y)
    local t = Net.get_tile(area_id, gx, gy, zz)
    if not t or not t.gid or t.gid == 0 then
      return true
    end
  end

  local probe = { x = x, y = y, z = zz, size = size or CONFIG.size }
  -- helpers.position_overlaps_something expects a position table + area_id (like eznpcs)
  return helpers.position_overlaps_something(probe, area_id)
end

local function safe_animate(bot_id, state)
  if not bot_id or not state then return end
  pcall(function() Net.animate_bot(bot_id, state, true) end)
end

local function safe_set_dir(bot_id, dir)
  if not bot_id or not dir then return end
  pcall(function() Net.set_bot_direction(bot_id, dir) end)
end

local function alloc_uid()
  return tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
end

local function index_record(rec)
  records[rec.uid] = rec
  by_area[rec.area_id] = by_area[rec.area_id] or {}
  by_area[rec.area_id][rec.uid] = true
  if rec.bot_id then
    bot_to_uid[tostring(rec.bot_id)] = rec.uid
  end
end

local function move_record_area(rec, new_area_id)
  if not rec or not new_area_id then return end
  if by_area[rec.area_id] then
    by_area[rec.area_id][rec.uid] = nil
  end
  rec.area_id = new_area_id
  by_area[rec.area_id] = by_area[rec.area_id] or {}
  by_area[rec.area_id][rec.uid] = true
end

local function unindex_record(rec)
  if not rec then return end
  if rec.bot_id then
    bot_to_uid[tostring(rec.bot_id)] = nil
  end
  records[rec.uid] = nil
  if by_area[rec.area_id] then
    by_area[rec.area_id][rec.uid] = nil
  end
end

-- ====================== Bot spawn / despawn ======================
local function spawn_pet_bot(rec)
  local def, tex, anim = build_paths(rec.kind)
  if not def then
    print("[pets] Unknown pet kind:", tostring(rec.kind))
    return nil
  end

  Net.provide_asset(rec.area_id, tex)
  Net.provide_asset(rec.area_id, anim)

  local dir = rec.direction or "Down Left"
  local suffix = DIR_SUFFIX[dir] or "DL"

  local bid = Net.create_bot({
    name = def.name,
    area_id = rec.area_id,
    x = rec.x, y = rec.y, z = rec.z or 0,
    direction = dir,
    solid = CONFIG.solid,
    size = CONFIG.size,
    speed = CONFIG.speed,
    texture_path = tex,
    animation_path = anim,
    animation = "IDLE_" .. suffix,
  })

  rec.bot_id = bid
  bot_to_uid[tostring(bid)] = rec.uid
  safe_animate(bid, "IDLE_" .. suffix)
  return bid
end

local function despawn_pet_bot(rec, warp_out)
  if rec and rec.bot_id and Net.is_bot(rec.bot_id) then
    -- Try optional warp-out effect if supported (falls back to normal removal).
    if warp_out then
      local ok = pcall(Net.remove_bot, rec.bot_id, true)
      if not ok then pcall(Net.remove_bot, rec.bot_id) end
    else
      pcall(Net.remove_bot, rec.bot_id)
    end
  end
  if rec and rec.bot_id then
    bot_to_uid[tostring(rec.bot_id)] = nil
  end
  if rec then
    rec.bot_id = nil
  end
end

-- ====================== Waypoint movement (eznpcs style) ======================
local function choose_wander_waypoint(rec)
  local tx = nearest_tile(rec.x)
  local ty = nearest_tile(rec.y)
  local z  = rec.z or 0

  for _ = 1, 10 do
    local dir = CONFIG.directions[math.random(1, #CONFIG.directions)]
    local dx, dy = dir_to_vec(dir)
    local gx, gy = tx + dx, ty + dy

    if not blocked(rec.area_id, gx, gy, z, CONFIG.size) then
      rec.waypoint = { x = gx, y = gy, z = z }
      rec.direction = dir

      local suffix = DIR_SUFFIX[dir] or "DL"
      safe_set_dir(rec.bot_id, dir)
      safe_animate(rec.bot_id, "WALK_" .. suffix)
      return true
    end
  end

  return false
end

local function finish_waypoint(rec)
  if not rec.waypoint then return end
  rec.x, rec.y, rec.z = rec.waypoint.x, rec.waypoint.y, rec.waypoint.z
  if rec.bot_id and Net.is_bot(rec.bot_id) then
    Net.move_bot(rec.bot_id, rec.x, rec.y, rec.z)
    local suffix = DIR_SUFFIX[rec.direction or "Down Left"] or "DL"
    safe_animate(rec.bot_id, "IDLE_" .. suffix)
  end
  rec.waypoint = nil
  rec.blocked_for = 0
  rec.next_move_time = world_time + CONFIG.move_interval_sec + (math.random() * CONFIG.move_jitter_sec)
end

local function move_toward_waypoint(rec, delta_time)
  if not rec.waypoint then return end
  if not rec.bot_id or not Net.is_bot(rec.bot_id) then
    rec.waypoint = nil
    rec.next_move_time = world_time + 1.0
    return
  end

  local wx, wy, wz = rec.waypoint.x, rec.waypoint.y, rec.waypoint.z
  local dx = wx - rec.x
  local dy = wy - rec.y
  local dist = math.sqrt(dx*dx + dy*dy)

  local eps = CONFIG.arrive_epsilon or 0.05
  if dist <= eps then
    finish_waypoint(rec)
    return
  end

  local angle = math.atan(dy, dx)
  local vel_x = math.cos(angle) * CONFIG.speed
  local vel_y = math.sin(angle) * CONFIG.speed

  local nx = rec.x + vel_x * delta_time
  local ny = rec.y + vel_y * delta_time
  local nz = wz or rec.z or 0

  if blocked(rec.area_id, nx, ny, nz, CONFIG.size) then
    rec.blocked_for = (rec.blocked_for or 0) + delta_time
    if rec.blocked_for >= (CONFIG.blocked_timeout_sec or 1.25) then
      rec.waypoint = nil
      rec.blocked_for = 0
      local suffix = DIR_SUFFIX[rec.direction or "Down Left"] or "DL"
      safe_animate(rec.bot_id, "IDLE_" .. suffix)
      rec.next_move_time = world_time + 0.8
    end
    return
  end

  rec.blocked_for = 0
  rec.x, rec.y, rec.z = nx, ny, nz
  Net.move_bot(rec.bot_id, nx, ny, nz)
end

-- ====================== Entry lookup/update helpers ======================
local function find_entry(bucket_area_id, uid)
  local mem = ensure_bucket_mem(bucket_area_id)
  for oncehub_key, list in pairs(mem.oncehub_pets_v1 or {}) do
    if type(list) == "table" then
      for idx, e in ipairs(list) do
        if tostring(e.uid or "") == tostring(uid) then
          normalize_entry(e, bucket_area_id, oncehub_key)
          return e, oncehub_key, list, idx, mem
        end
      end
    end
  end
  return nil
end

local function update_entry_runtime_fields(e, rec)
  if not e or not rec then return end
  e.area_id = rec.area_id
  e.x, e.y, e.z = rec.x, rec.y, rec.z
  e.bot_id = rec.bot_id
  e.owner_secret = rec.owner_secret or e.owner_secret
  e.owner_name   = rec.owner_name   or e.owner_name
end

local function _owner_name_from_secret(secret)
  if not secret or secret == "" then return "" end
  local pm = ezmemory.get_player_memory(secret)
  local n = (pm and (pm.last_name or (pm.teams and pm.teams.last_name))) or nil
  if n and n ~= "" then return n end
  return ""
end

-- ====================== Expedition state helpers ======================
local function get_active_expedition_uid(bucket_area_id, owner_secret)
  local mem = ensure_bucket_mem(bucket_area_id)
  local rec = mem.oncehub_pet_expeditions_v1[tostring(owner_secret or "")]
  if type(rec) == "table" then
    return rec.uid, tonumber(rec.ends_at or 0)
  elseif type(rec) == "string" then
    return rec, 0
  end
  return nil
end

local function set_active_expedition(bucket_area_id, owner_secret, uid, ends_at)
  local mem = ensure_bucket_mem(bucket_area_id)
  mem.oncehub_pet_expeditions_v1[tostring(owner_secret or "")] = { uid=tostring(uid or ""), ends_at=math.floor(tonumber(ends_at) or 0) }
  save_bucket(bucket_area_id)
end

local function clear_active_expedition(bucket_area_id, owner_secret)
  local mem = ensure_bucket_mem(bucket_area_id)
  mem.oncehub_pet_expeditions_v1[tostring(owner_secret or "")] = nil
  save_bucket(bucket_area_id)
end

local function choose_roam_area()
  local t = EXPEDITION.roam_areas or {}
  if #t == 0 then return nil end
  local pick = t[math.random(1, #t)]
  return pick
end

local function is_on_cooldown(e)
  local now = _now()
  return (tonumber(e.cooldown_ends_at) or 0) > now
end

local function cooldown_left(e)
  return math.max(0, (tonumber(e.cooldown_ends_at) or 0) - _now())
end

local function expedition_active(e)
  return e and e.exp and e.exp.active == true
end

local function expedition_left(e)
  if not expedition_active(e) then return 0 end
  return math.max(0, (tonumber(e.exp.ends_at) or 0) - _now())
end

local function _dbg_frags(pid, tag)
  if not EXPEDITION.debug then return end

  if not Net.get_player_fragments then
    print(("[pets][frag] %s pid=%s (Net.get_player_fragments missing)"):format(tag, tostring(pid)))
    return
  end

  local ok, n = pcall(Net.get_player_fragments, pid)
  print(("[pets][frag] %s pid=%s frags=%s ok=%s"):format(tag, tostring(pid), tostring(n), tostring(ok)))
end

local function generate_reward(mood_snapshot)
  local mood = mood_snapshot or "neutral"
  local entries = (EXPEDITION.reward_tables and EXPEDITION.reward_tables[mood]) or (EXPEDITION.reward_tables and EXPEDITION.reward_tables.neutral) or {}
  local pick = pick_weighted(entries)
  local id = pick and pick.id or "consolation"


  if id == "consolation" then
    return { kind="money", amount=tonumber(EXPEDITION.consolation_money) or 1000, label="scraps" }
  elseif id == "money" then
    local mn = tonumber(EXPEDITION.money_min) or 10000
    local mx = tonumber(EXPEDITION.money_max) or 50000
    if mx < mn then mn, mx = mx, mn end
    local amt = math.random(mn, mx)
    return { kind="money", amount=amt }
  elseif id == "frag" then
    return { kind="frag", amount=tonumber(EXPEDITION.frag_amount) or 1 }
  elseif id == "card" then
    local pool = EXPEDITION.card_pool or {}
    if #pool == 0 then
      -- fallback
      local mn = tonumber(EXPEDITION.money_min) or 10000
      local mx = tonumber(EXPEDITION.money_max) or 50000
      local amt = math.random(mn, mx)
      return { kind="money", amount=amt, label="fallback" }
    end
    local c = pool[math.random(1, #pool)]
    return { kind="card", name=tostring(c.name or "Card"), description=tostring(c.description or ""), amount=1 }
  elseif id == "gp" then
    return { kind="gp", amount=tonumber(EXPEDITION.gp_amount) or 1 }
  end

  -- unknown -> consolation
  return { kind="money", amount=tonumber(EXPEDITION.consolation_money) or 1000, label="scraps" }
end

local function apply_reward_to_player(pid, reward)
  if not pid or not reward then return end
  local area_id = Net.get_player_area(pid)

  if reward.kind == "money" then
    pcall(ezmemory.spend_player_money, pid, -tonumber(reward.amount or 0))
    Net.message_player(pid, "Got "..tostring(reward.amount or 0).."z!")
    return
  end

  if reward.kind == "frag" then
  local amt = tonumber(reward.amount or 0) or 0
  if ezmemory.spend_player_fragments then
    _dbg_frags(pid, "reward:before")
    pcall(ezmemory.spend_player_fragments, pid, -amt)
    _dbg_frags(pid, "reward:after")
  else
    local ok, cur = pcall(Net.get_player_fragments, pid)
    cur = ok and (tonumber(cur) or 0) or 0
    pcall(Net.set_player_fragments, pid, cur + amt)
  end
  Net.message_player(pid, "Got "..tostring(amt).." BugFrag!")
  return
end

if reward.kind == "card" then
    local item_info = { type="item", name=tostring(reward.name), description=tostring(reward.description or ""), amount=tonumber(reward.amount or 1) }
    pcall(ezmemory.create_or_update_item, item_info.name, item_info.description, false)
    pcall(ezmemory.give_player_item, pid, item_info.name, item_info.amount)
    Net.message_player(pid, "Got "..item_info.name.."!")
    return
  end

  if reward.kind == "gp" then
    if Teams and Teams.award_activity_gp then
      pcall(Teams.award_activity_gp, pid, tonumber(reward.amount or 1), "pet expedition")
    elseif Teams and Teams.debug_add_gp then
      pcall(Teams.debug_add_gp, pid, tonumber(reward.amount or 1))
    else
      -- fallback to money if teams isn't loaded
      local amt = tonumber(EXPEDITION.money_min) or 10000
      pcall(ezmemory.spend_player_money, pid, -amt)
      Net.message_player(pid, "Got "..tostring(amt).."z!")
    end
    return
  end
end

local function result_flavor(mood, reward)
  mood = tostring(mood or "neutral")

  local kind  = reward and tostring(reward.kind or "") or ""
  local label = reward and tostring(reward.label or "") or ""

  -- In your generate_reward(), consolation is { kind="money", label="scraps", amount=... }
  local is_consolation_money = (kind == "money" and label == "scraps")
  local is_gp = (kind == "gp")

  -- "Did well" bucket (per your example): bug frag, regular money, or a card.
  local did_well = (kind == "frag") or (kind == "card") or (kind == "money" and not is_consolation_money)

  if mood == "happy" then
    if is_consolation_money or is_gp then
      return "Your virus looks a bit embarrassed it couldn't do better."
    elseif did_well then
      return "Your virus looks happy about the expedition."
    end
    return "Your virus looks pleased with the trip."

  elseif mood == "neutral" then
    if is_consolation_money or is_gp then
      return "Your virus gives a small shrug and hands you what it managed to find."
    elseif did_well then
      return "Your virus seems quietly satisfied with what it brought back."
    end
    return "Your virus reports back from its trip."

  else -- sad (or anything else)
    if is_consolation_money or is_gp then
      return "Your virus trudges back, apologetic… it didn't find much this time."
    elseif did_well then
      return "Your virus looks exhausted, but a little proud of what it managed to bring back."
    end
    return "Your virus seems exhausted after its trip."
  end
end

local function owner_on_team(pid)
  local secret = helpers.get_safe_player_secret(pid)
  local pm = ezmemory.get_player_memory(secret) or {}
  local cur = pm.teams and pm.teams.current
  return (cur and cur.team) ~= nil
end

-- Complete an expedition (called by tick). Updates memory, moves/respawns bots as needed.
local function complete_expedition_for_entry(e, bucket_area_id)
  if not e or not expedition_active(e) then return end
  local now = _now()

  -- Rental expired? Cancel expedition and remove pet entirely.
  local lease_expires_at = tonumber(e.exp.lease_expires_at or 0) or 0
  if lease_expires_at > 0 and lease_expires_at <= now then
    dbg("Expedition cancelled (lease expired). uid=", e.uid, "owner=", e.owner_secret)
    -- Try to despawn roaming bot if present
    if e.bot_id and Net.is_bot(e.bot_id) then pcall(Net.remove_bot, e.bot_id) end
local rec = records[tostring(e.uid)]
if rec then
  despawn_pet_bot(rec, false)
  unindex_record(rec)
end
    -- Remove from storage list
    local list = load_pet_list(bucket_area_id, e.oncehub_key)
    for i = #list, 1, -1 do
      if tostring(list[i].uid or "") == tostring(e.uid) then
        table.remove(list, i)
        break
      end
    end
    -- Clear expedition map
    clear_active_expedition(bucket_area_id, e.owner_secret)
    save_bucket(bucket_area_id)
    return
  end

  -- Generate reward now (stored until claim)
  local mood_snapshot = (e.exp and e.exp.mood) or "neutral"
  local reward = generate_reward(mood_snapshot) -- owner_on_team unknown offline; resolved on claim for gp fallback
  -- If reward is gp but owner is offline, we still store gp and fallback on claim if needed.
  e.exp.reward = reward
  e.exp.reward_pending = true

  -- End expedition, return to home position
  e.exp.active = false

  local cd = EXPEDITION.cooldown_by_mood[mood_from_fatigue(e.fatigue)] or (30*60)
  e.cooldown_ends_at = now + cd

-- Despawn roaming bot if it exists
if e.bot_id and Net.is_bot(e.bot_id) then
  dbg("Despawning roaming bot uid=", e.uid, "bot_id=", e.bot_id)
  pcall(Net.remove_bot, e.bot_id)
end
e.bot_id = nil

-- Clear any roaming runtime record
local rec = records[tostring(e.uid)]
if rec then
  despawn_pet_bot(rec, false)
  unindex_record(rec)
end

e.area_id = e.home_area_id
e.x, e.y, e.z = e.home_x, e.home_y, e.home_z or 0

-- Spawn the pet back home immediately
local home_rec = {
  uid = tostring(e.uid),
  kind = tostring(e.kind or ""):lower(),
  area_id = e.area_id,
  x = e.x, y = e.y, z = e.z or 0,
  direction = "Down Left",
  next_move_time = world_time + 1.0,
  blocked_for = 0,
  owner_secret = e.owner_secret,
  owner_name = e.owner_name,
}
spawn_pet_bot(home_rec)
index_record(home_rec)
e.bot_id = home_rec.bot_id

  dbg("Expedition complete; returning uid=", e.uid, "to", e.area_id, "cooldown=", cd)
  clear_active_expedition(bucket_area_id, e.owner_secret)
  save_bucket(bucket_area_id)
end

local function start_expedition_for_player(pid, e, bucket_area_id)
  local now = _now()
  local secret = helpers.get_safe_player_secret(pid)
  if secret ~= (e.owner_secret or "") then
    return false, "Only the owner can send this pet on an expedition."
  end

  if not e.owner_name or e.owner_name == "" then
    e.owner_name = Net.get_player_name(pid)
  end

  -- Only start expeditions from the pet's HOME HP area.
  local cur_area = Net.get_player_area(pid)
  if tostring(cur_area or "") ~= tostring(e.home_area_id or "") then
    return false, "This pet can only be sent from its home HP."
  end

  -- Only one active expedition per player
  local active_uid = get_active_expedition_uid(bucket_area_id, secret)
  if active_uid and tostring(active_uid) ~= "" and tostring(active_uid) ~= tostring(e.uid) then
    return false, "You already have a pet out on an expedition."
  end

  -- Cooldown guard
  if is_on_cooldown(e) then
    return false, "Your pet is resting. Come back in ".._fmt_time_left(cooldown_left(e)).."."
  end

  -- Duration derived from minutes
  local duration_sec = math.max(60, math.floor((tonumber(EXPEDITION.duration_minutes) or 60) * 60))

  -- Lease must last long enough (or cancel)
  local expires_at = _get_hp_expires_at(bucket_area_id, e.oncehub_key)
  if expires_at and tonumber(expires_at) and tonumber(expires_at) > 0 then
    if tonumber(expires_at) < (now + duration_sec) then
      return false, "Your HP rental will expire before the expedition ends."
    end
  end

  -- Pick destination (your config table)
  local dest = choose_roam_area()
  if not dest then
    return false, "No expedition destinations are configured."
  end

  local mood_snapshot = mood_from_fatigue(e.fatigue)

  -- Fatigue increases when you send it out
  e.fatigue = math.max(0, math.floor(tonumber(e.fatigue) or 0) + 1)
  _set_saved_fatigue(bucket_area_id, e.owner_secret, e.kind, e.fatigue)

  -- Mark expedition
  e.exp.active = true
  e.exp.started_at = now
  e.exp.ends_at = now + duration_sec
  e.exp.mood = mood_snapshot
  e.exp.dest = { area_id=dest.area_id, x=dest.x, y=dest.y, z=dest.z or 0, label=dest.label or dest.area_id }
  e.exp.lease_expires_at = tonumber(expires_at or 0) or 0
  e.exp.reward = nil
  e.exp.reward_pending = false

  dbg("Starting expedition uid=", e.uid, "owner=", e.owner_name, "dest=", dest.area_id, dest.x, dest.y, dest.z or 0)

  -- Tell player where it went (fun)
  local label = tostring(dest.label or dest.area_id or "somewhere")
  Net.message_player(pid, ("Your virus headed out to %s."):format(label))

  -- Despawn + unindex current runtime record (if any)
  local rec = records[tostring(e.uid)]
  if rec then
    despawn_pet_bot(rec, true)
    unindex_record(rec)
  else
    -- fallback: if e has a bot_id but isn't indexed for some reason
    if e.bot_id and Net.is_bot(e.bot_id) then
      pcall(Net.remove_bot, e.bot_id, true)
      bot_to_uid[tostring(e.bot_id)] = nil
    end
    e.bot_id = nil
  end

  -- Move pet data to roaming location BEFORE spawning
  e.area_id = dest.area_id
  e.x, e.y, e.z = dest.x, dest.y, dest.z or 0

  -- Spawn roam bot (spawn_pet_bot returns bot_id or nil)
  local bot_id = spawn_pet_bot(e)
  if not bot_id then
    dbg("Expedition spawn failed uid=", e.uid)
    e.exp.active = false
    e.exp.reward = nil
    e.exp.reward_pending = false
    save_bucket(bucket_area_id)
    clear_active_expedition(bucket_area_id, secret)
    return false, "Couldn't send your pet out right now."
  end

  e.bot_id = bot_id
  index_record(e)

  -- Set active expedition map
  set_active_expedition(bucket_area_id, secret, e.uid, e.exp.ends_at)

  save_bucket(bucket_area_id)
  dbg("Expedition started uid=", e.uid, "ends_at=", e.exp.ends_at)

  local mins = math.floor(duration_sec / 60)
  return true, ("Sent out for %d minute%s."):format(mins, mins == 1 and "" or "s", mood_snapshot)
end

local function feed_pet(pid, e, bucket_area_id)
  local secret = helpers.get_safe_player_secret(pid)
  if secret ~= (e.owner_secret or "") then
    return false, "Only the owner can feed this pet."
  end

  if not e.owner_name or e.owner_name == "" then
    e.owner_name = Net.get_player_name(pid)
  end

  local mood = mood_from_fatigue(e.fatigue)
  if mood == "happy" then
    return false, "Your pet is already happy."
  end

  if not ezmemory.spend_player_fragments then
    return false, "Fragments support isn't installed in ezmemory yet."
  end

  local cost = tonumber(EXPEDITION.feed_frag_cost) or 1
  _dbg_frags(pid, "feed:before_spend")
  if not ezmemory.spend_player_fragments(pid, cost) then
    return false, "Not enough BugFrags."
  end
  _dbg_frags(pid, "feed:after_spend")

  -- Replace the "set to threshold-1" logic with:
  if mood == "sad" then
    e.fatigue = math.max(0, e.fatigue - (EXPEDITION.neutral_to_sad - EXPEDITION.happy_to_neutral)) -- 20
  elseif mood == "neutral" then
    e.fatigue = math.max(0, e.fatigue - EXPEDITION.happy_to_neutral) -- 15
  end

  _set_saved_fatigue(bucket_area_id, e.owner_secret, e.kind, e.fatigue)
  save_bucket(bucket_area_id)
  return true, "You fed your virus. It seems happier."
end

-- ====================== Public API ======================
function pets.list_pets(bucket_area_id, oncehub_key)
  local list = load_pet_list(bucket_area_id, oncehub_key)
  local out = {}
  for i, e in ipairs(list) do
    normalize_entry(e, bucket_area_id, oncehub_key)
    out[i] = {
      uid = e.uid,
      kind = e.kind,
      area_id = e.area_id,
      x = e.x, y = e.y, z = e.z,
      mood = mood_from_fatigue(e.fatigue),
      fatigue = e.fatigue,
      bot_id = e.bot_id,
      expedition_active = expedition_active(e),
      cooldown_ends_at = e.cooldown_ends_at,
    }
  end
  return out
end

function pets.summon_pet(area_id, bucket_area_id, oncehub_key, kind, x, y, z, owner_secret)
  kind = tostring(kind or "mettaur"):lower()
  if kind == "" then kind = "mettaur" end

  local list = load_pet_list(bucket_area_id, oncehub_key)
  local uid = alloc_uid()

  local owner_name = ""
  if owner_secret and owner_secret ~= "" then
    owner_name = _owner_name_from_secret(owner_secret)
  end

  local saved_fatigue = _get_saved_fatigue(bucket_area_id, owner_secret, kind)
  if saved_fatigue == nil then
    fatigue = math.max(0, math.floor(tonumber(EXPEDITION.happy_to_neutral) or 15))
  else
    fatigue = math.max(0, math.floor(tonumber(saved_fatigue) or 0))
  end

  -- Ensure there's a stats record so mood persists across remove/re-summon.
  _set_saved_fatigue(bucket_area_id, owner_secret, kind, fatigue)

  local e = {
    uid = uid,
    kind = kind,
    home_area_id = area_id,
    bucket_area_id = bucket_area_id,
    oncehub_key = oncehub_key,
    area_id = area_id,
    x = x, y = y, z = z or 0,
    owner_secret = owner_secret or "",
    owner_name = owner_name or "",
    fatigue = fatigue,
    cooldown_ends_at = 0,
    bot_id = "",
    exp = {
      active = false,
      started_at = 0,
      ends_at = 0,
      mood = "neutral",
      dest = nil,
      lease_expires_at = 0,
      reward = nil,
      reward_pending = false,
    }
  }

  table.insert(list, e)
  save_bucket(bucket_area_id)

  -- spawn_pet_bot returns bot_id (or nil). It also sets e.bot_id internally.
  local bot_id = spawn_pet_bot(e)
  if not bot_id then
    dbg("summon_pet spawn failed uid=", uid, "kind=", kind, "area_id=", area_id)
    return nil, "spawn_failed"
  end

  e.bot_id = bot_id
  index_record(e)
  save_bucket(bucket_area_id)

  return uid
end

local function _remove_pet_internal(bucket_area_id, uid, force)
  local e = find_entry(bucket_area_id, uid)
  if not e then return false, "Pet not found." end

  -- Block removal if expedition active or cooldown (unless forced)
  if not force then
    if expedition_active(e) then
      local left = expedition_left(e)
      local where = (e.exp.dest and e.exp.dest.label) or (e.exp.dest and e.exp.dest.area_id) or "somewhere"
      return false, ("That pet is on an expedition (%s). Returns in %s."):format(tostring(where), _fmt_time_left(left))
    end
    if is_on_cooldown(e) then
      return false, "That pet is resting. Cooldown: ".._fmt_time_left(cooldown_left(e)).."."
    end
  end

  -- despawn runtime bot if present
  if e.bot_id and Net.is_bot(e.bot_id) then
    dbg("Removing bot uid=", e.uid, "bot_id=", e.bot_id, "force=", force and "true" or "false")
    pcall(Net.remove_bot, e.bot_id)
  end

  -- remove runtime record if exists
  local rec = records[tostring(uid)]
  if rec then
    despawn_pet_bot(rec, false)
    unindex_record(rec)
  end

  -- remove from storage list
  local list = load_pet_list(bucket_area_id, e.oncehub_key)
  for i = #list, 1, -1 do
    if tostring(list[i].uid or "") == tostring(uid) then
      table.remove(list, i)
      break
    end
  end

  -- clear expedition map if needed
  if e.owner_secret and e.owner_secret ~= "" then
    local active_uid = get_active_expedition_uid(bucket_area_id, e.owner_secret)
    if active_uid and tostring(active_uid) == tostring(uid) then
      clear_active_expedition(bucket_area_id, e.owner_secret)
    end
  end

  save_bucket(bucket_area_id)
  return true, "Pet removed."
end

function pets.remove_pet(area_id, bucket_area_id, oncehub_key, uid_or_bot)
  if not uid_or_bot then return false, "Missing pet id." end
  local uid = tostring(uid_or_bot)

  if bot_to_uid[uid] then
    uid = bot_to_uid[uid]
  end

  return _remove_pet_internal(bucket_area_id, uid, false)
end

function pets.remove_all(area_id, bucket_area_id, oncehub_key)
  local list = load_pet_list(bucket_area_id, oncehub_key)

  -- Respect the same guards as single-remove:
  -- do NOT remove pets on expedition or cooldown.
  local removed, skipped = 0, 0

  for i = #list, 1, -1 do
    local e = normalize_entry(list[i], bucket_area_id, oncehub_key)
    if e and (expedition_active(e) or is_on_cooldown(e)) then
      skipped = skipped + 1
    else
      local uid = tostring(list[i].uid or "")

      -- despawn runtime record
      local rec = records[uid]
      if rec then
        despawn_pet_bot(rec, false)
        unindex_record(rec)
      end

      -- despawn bot if stored
      if list[i].bot_id and Net.is_bot(list[i].bot_id) then
        pcall(Net.remove_bot, list[i].bot_id)
      end

      table.remove(list, i)
      removed = removed + 1
    end
  end

  save_bucket(bucket_area_id)
  return removed, skipped
end

function pets.rehydrate_for_hp(area_id, bucket_area_id, oncehub_key)
  local list = load_pet_list(bucket_area_id, oncehub_key)

  for _, e in ipairs(list) do
    normalize_entry(e, bucket_area_id, oncehub_key)

    -- refresh owner_secret from lease (useful for older saves)
    if (not e.owner_secret) or e.owner_secret == "" then
      local s = _get_hp_owner_secret(bucket_area_id, oncehub_key)
      if type(s) == "string" and s ~= "" then e.owner_secret = s end
    end

    -- spawn bot only if this entry lives in this area
    if e.area_id == area_id then
      local uid = tostring(e.uid)
      local rec = records[uid]
      if not rec then
        rec = {
          uid = uid,
          kind = tostring(e.kind or ""):lower(),
          area_id = area_id,
          x = e.x or 0, y = e.y or 0, z = e.z or 0,
          direction = "Down Left",
          next_move_time = world_time + 1.0,
          blocked_for = 0,
          owner_secret = e.owner_secret,
          owner_name = e.owner_name,
        }
        spawn_pet_bot(rec)
        index_record(rec)
      else
        if not rec.bot_id or not Net.is_bot(rec.bot_id) then
          spawn_pet_bot(rec)
          index_record(rec)
        end
      end
      e.bot_id = rec.bot_id
    end
  end

  save_bucket(bucket_area_id)
end

-- Optional: rehydrate any pets in a given area (scans all keys in the bucket)
function pets.rehydrate_all_for_area(area_id, bucket_area_id)
  local mem = ensure_bucket_mem(bucket_area_id)
  for oncehub_key, list in pairs(mem.oncehub_pets_v1 or {}) do
    if type(list) == "table" then
      for _, e in ipairs(list) do
        normalize_entry(e, bucket_area_id, oncehub_key)
        if e.area_id == area_id then
          pets.rehydrate_for_hp(area_id, bucket_area_id, oncehub_key)
          break
        end
      end
    end
  end
end

-- ====================== Interaction ======================
local interaction_lock = {}

local function with_interaction_lock(pid, fn)
  if interaction_lock[pid] then return end
  interaction_lock[pid] = true
  async(function()
    local ok, err = pcall(fn)
    if not ok then
      dbg("PET interaction error pid=", tostring(pid), "err=", tostring(err))
    end
    await(Async.sleep(0.25))
    interaction_lock[pid] = nil
  end)
end

local function open_pet_action_menu(pid, e, bucket_area_id)
  local mood = mood_from_fatigue(e.fatigue)

  -- If pet is currently roaming, just show a flavor line.
  if expedition_active(e) then
    local owner = e.owner_name
    if owner == "" then owner = "someone" end

    local is_owner = helpers.get_safe_player_secret(pid) == (e.owner_secret or "")

    -- Nickname-aware message (falls back to old messages if no nickname)
    local nick = _sanitize_nickname(e.nickname)
    if nick ~= tostring(e.nickname or "") then
      e.nickname = nick
      save_bucket(bucket_area_id)
    end

    if nick ~= "" then
      if is_owner then
        Net.message_player(pid, ("You see %s (your pet). It seems to be busy looking through the area."):format(nick))
      else
        Net.message_player(pid, ("You see %s (%s's pet). It seems to be busy."):format(nick, owner))
      end
    else
      if is_owner then
        Net.message_player(pid, "You see your pet. It seems to be busy looking through the area.")
      else
        Net.message_player(pid, ("You see %s's pet. It seems to be busy."):format(owner))
      end
    end

    return
  end

  -- If reward is pending, claim it now (owner only).
  if e.exp and e.exp.reward_pending and e.exp.reward then
    local secret = helpers.get_safe_player_secret(pid)
    if secret ~= (e.owner_secret or "") then
      Net.message_player(pid, "This pet doesn't seem interested in showing you anything.")
      return
    end

    if not e.owner_name or e.owner_name == "" then
      e.owner_name = Net.get_player_name(pid)
    end

    Net.message_player(pid, result_flavor(e.exp.mood or mood, e.exp.reward))

    -- apply reward, with gp fallback if not on team
    local r = e.exp.reward
    if r and r.kind == "gp" and not owner_on_team(pid) then
      -- preserve your existing fallback behavior
      r = { kind="moneyz", amount=r.money_fallback_amount or 1000 }
    end

    local ok, err = pcall(apply_reward_to_player, pid, r)
    if not ok then
      dbg("claim_reward FAILED uid=", tostring(e.uid), "err=", tostring(err))
      Net.message_player(pid, "Couldn't claim reward (server error).")
      return
    end

    e.exp.reward_pending = false
    e.exp.reward = nil
    save_bucket(bucket_area_id)

    return
  end

  local secret = helpers.get_safe_player_secret(pid)
  local is_owner = (secret == (e.owner_secret or ""))

  -- Sanitize nickname on read (so title never gets weird)
  local nick = _sanitize_nickname(e.nickname)
  if nick ~= tostring(e.nickname or "") then
    e.nickname = nick
    save_bucket(bucket_area_id)
  end
  local display = (nick ~= "" and nick) or "Virus Pet"

  -- Board title shows current BugFrags
  local frags = _get_player_bugfrags(pid)
  local title = ("%s - %d BugFrags"):format(display, frags)

  -- Build menu options
  local opts = {}
  local can_send, send_disabled_msg = true, nil

  if is_on_cooldown(e) then
    can_send = false
    send_disabled_msg = "Cooldown: ".._fmt_time_left(cooldown_left(e))
  end

  if not is_owner then
    can_send = false
    send_disabled_msg = "Only the owner can send expeditions."
  end

  if can_send then
    table.insert(opts, helpers.create_bbs_option("Send on expedition"))
  else
    table.insert(opts, helpers.create_bbs_option("Send on expedition ("..tostring(send_disabled_msg or "unavailable")..")"))
  end

  -- Feed only for owner (avoid confusing non-owners)
  if is_owner and mood ~= "happy" then
    table.insert(opts, helpers.create_bbs_option("Feed 1 BugFrag"))
  end

  table.insert(opts, helpers.create_bbs_option("Pet it"))

  if is_owner then
    table.insert(opts, helpers.create_bbs_option("Set/Clear Nickname"))
  end

  table.insert(opts, helpers.create_bbs_option("Nevermind"))

  -- IMPORTANT: use the correct helper name
  local board = _open_menu_ignoring_custom(pid, title, {r=255,g=230,b=160}, opts, "pets:act")
  local sel = await(board.selection_once())

  -- Always close board after selection (and guard custom.lua close hook)
  _mark_ignore_next_close(pid, "pets:act_close")
  pcall(function() board:close() end)
  pcall(Net.close_bbs, pid)

  if not sel or sel == "Nevermind" then
    return
  end

  if sel:find("^Send on expedition") == 1 then
    if not can_send then
      Net.message_player(pid, send_disabled_msg or "Not available.")
      return
    end
    local ok, msg = start_expedition_for_player(pid, e, bucket_area_id)
    if msg and msg ~= "" then
      Net.message_player(pid, msg)
    elseif ok then
      Net.message_player(pid, "Sent on expedition.")
    else
      Net.message_player(pid, "Couldn't start expedition.")
    end
    return
  end

  if sel == "Feed 1 BugFrag" then
    local ok, msg = feed_pet(pid, e, bucket_area_id)
    Net.message_player(pid, msg or (ok and "Fed." or "Couldn't feed."))
    return
  end

  if sel == "Pet it" then
    Net.message_player(pid, _pet_it_text(mood))
    return
  end

  if sel == "Set/Clear Nickname" then
    if not is_owner then
      Net.message_player(pid, "Only the owner can set a nickname.")
      return
    end

    if not Async or not Async.prompt_player then
      Net.message_player(pid, "Nickname input isn't available on this server build.")
      return
    end

    -- IMPORTANT:
    -- Do NOT call Net.prompt_player here. On your server it opens a prompt but doesn't give us an await-able promise.
    -- That causes us to miss the real input ("Metty") and later accidentally consume a "0" from some other textbox close.
    dbg("nickname prompt: opening pid=", tostring(pid))
    local input = await(Async.prompt_player(pid))
    dbg("nickname prompt: response pid=", tostring(pid), "value=", tostring(input))

    -- If player cancelled/closed, many systems send "0". Treat that as cancel (NOT clear).
    if input == nil then
      Net.message_player(pid, "Nickname cancelled.")
      return
    end
    input = tostring(input)
    if input == "0" then
      Net.message_player(pid, "Nickname cancelled.")
      return
    end

    local new_nick = _sanitize_nickname(input)
    e.nickname = new_nick
    save_bucket(bucket_area_id)

    if new_nick == "" then
      Net.message_player(pid, "Nickname cleared.")
    else
      Net.message_player(pid, ("Nickname set to: %s"):format(new_nick))
    end
    return
  end
end

Net:on("actor_interaction", function(event)
  local player_id = event.player_id
  local actor_id = event.actor_id or event.actor
  if not player_id or not actor_id then return end

  local uid = bot_to_uid[tostring(actor_id)]
  if not uid then return end

  -- Find the entry for this uid by searching all areas for oncehub_pets_v1.
  with_interaction_lock(player_id, function()
    -- We'll scan all net areas as potential buckets (safe for small scale).
    for _, bucket_area_id in ipairs(Net.list_areas() or {}) do
      local e = find_entry(bucket_area_id, uid)
      if e then
        open_pet_action_menu(player_id, e, bucket_area_id)
        return
      end
    end
    Net.message_player(player_id, "This pet seems confused (missing memory entry).")
  end)
end)

-- ====================== Tick loop ======================
local function refresh_area_has_players()
  area_has_players = {}
  for _, area_id in ipairs(Net.list_areas() or {}) do
    local players = Net.list_players(area_id) or {}
    if #players > 0 then
      area_has_players[area_id] = true
    end
  end
end

local next_expedition_scan = 0

local function scan_and_complete_expeditions()
  local now = _now()
  if world_time < next_expedition_scan then return end
  next_expedition_scan = world_time + 2.0

  for _, bucket_area_id in ipairs(Net.list_areas() or {}) do
    local mem = ezmemory.get_area_memory(bucket_area_id)
    if mem and type(mem.oncehub_pets_v1) == "table" then
      for oncehub_key, list in pairs(mem.oncehub_pets_v1) do
        if type(list) == "table" then
          for _, e in ipairs(list) do
            normalize_entry(e, bucket_area_id, oncehub_key)
            if expedition_active(e) and (tonumber(e.exp.ends_at) or 0) > 0 and (tonumber(e.exp.ends_at) or 0) <= now then
              dbg("Tick completing uid=", e.uid, "bucket=", bucket_area_id, "once_key=", oncehub_key)
              complete_expedition_for_entry(e, bucket_area_id)
            end
          end
        end
      end
    end
  end
end

Net:on("tick", function(event)
  local dt = event.delta_time or 0
  world_time = world_time + dt

  if world_time >= next_area_scan_time then
    next_area_scan_time = world_time + 1.0
    refresh_area_has_players()
  end

  -- Finish expeditions even if players are offline
  scan_and_complete_expeditions()

  -- Move pets only in areas with players
  for area_id, uids in pairs(by_area) do
    if area_has_players[area_id] then
      for uid, _ in pairs(uids) do
        local rec = records[uid]
        if rec and rec.bot_id and Net.is_bot(rec.bot_id) then
          if rec.waypoint then
            move_toward_waypoint(rec, dt)
          elseif world_time >= (rec.next_move_time or 0) then
            if choose_wander_waypoint(rec) then
              -- continue
            else
              rec.next_move_time = world_time + 1.0
            end
          end
        end
      end
    end
  end
end)

now_seed_rng()
_validate_reward_tables()

return pets
