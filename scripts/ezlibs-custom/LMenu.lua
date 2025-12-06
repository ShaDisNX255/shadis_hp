-- /server/scripts/ezlibs-custom/LMenu.lua
-- L Menu:
--   LS   = open/close
--   U/D  = move cursor
--   A    = activate row (Cards / Summon / Unsummon / Friends / Cosmetics)

local LMenu = {}
_G.LMenu = LMenu  -- expose globally so other scripts can query state if needed

local suppress_next_open = {}
LMenu._suppress_next_open = suppress_next_open

-- ---------------------------------------------------------------------------
-- net-games framework
-- ---------------------------------------------------------------------------

local frame_ok, frame = pcall(require, "scripts/net-games/framework")
if not frame_ok or not frame then
  print("[LMenu] ERROR: failed to require scripts/net-games/framework; LMenu disabled.")
  return LMenu
end

-- ---------------------------------------------------------------------------
-- Friends API helper (opens Friends placeholder BBS)
-- ---------------------------------------------------------------------------

local FriendsOK, Friends = pcall(require, "scripts/ezlibs-custom/friends")
if not FriendsOK then
  Friends = nil
end

-- ---------------------------------------------------------------------------
-- Cosmetics submenu (new module handles all cosmetic logic)
-- ---------------------------------------------------------------------------

local CosmeticsOK, Cosmetics = pcall(require, "scripts/ezlibs-custom/cosmetics")
if not CosmeticsOK then
  Cosmetics = nil
end

-- ---------------------------------------------------------------------------
-- Jobs progress viewer (JobBBS integration)
-- ---------------------------------------------------------------------------

local JobBBSOK, JobBBS = pcall(require, "scripts/jobbbs/JobBBS")
if not JobBBSOK then
  JobBBS = nil
end

-- ---------------------------------------------------------------------------
-- Displayer (for gradient font text)
-- ---------------------------------------------------------------------------

local Displayer = _G.Displayer

if not Displayer then
  local ok, mod = pcall(require, "scripts/net-games/displayer/displayer")
  if ok and type(mod) == "table" then
    Displayer = mod
    _G.Displayer = mod
  else
    Displayer = nil
  end
end

if Displayer and Displayer.isValid and not Displayer:isValid() and Displayer.init then
  local ok_init, err = pcall(Displayer.init, Displayer)
  if not ok_init or not Displayer:isValid() then
    print("[LMenu] WARNING: Displayer failed to init:", tostring(err))
    Displayer = nil
  end
end

if not Displayer then
  print("[LMenu] WARNING: Displayer not available; online counter text will be disabled.")
end

-- ---------------------------------------------------------------------------
-- Config: asset paths, positions, scaling
-- ---------------------------------------------------------------------------

local cfg = {
  -- Logical UI coordinates (0..240 x, 0..160 y); framework doubles them internally.
  base_x      = 15,   -- default X for rows (used if row_x_* is nil)
  base_y      = 30,   -- move menu up/down
  row_spacing = 18,   -- vertical distance between rows
  z           = 6,    -- UI Z-depth
  scale       = 2,    -- change if tabs feel too big/small

  -- Optional per-row X overrides (use this to visually right-align the longer Cosmetics tab)
  -- If nil, that row falls back to base_x.
  row_x_cards     = nil,
  row_x_summon    = nil,
  row_x_friends   = nil,
  row_x_cosmetics = 12,
  row_x_jobs      = nil,

  -- Cards row (always present)
  cards_texture   = "/server/assets/ui/lmenu/lcards.png",
  cards_anim      = "/server/assets/ui/lmenu/lcards.animation",

  -- Summon / Unsummon row (shares same sprite, different anim states)
  summon_texture  = "/server/assets/ui/lmenu/lsummon.png",
  summon_anim     = "/server/assets/ui/lmenu/lsummon.animation",

  friends_texture = "/server/assets/ui/lmenu/lfriends.png",
  friends_anim    = "/server/assets/ui/lmenu/lfriends.animation",

  -- Cosmetics row button (slightly longer tab)
  cosmetics_texture = "/server/assets/ui/lmenu/lcosmetics.png",
  cosmetics_anim    = "/server/assets/ui/lmenu/lcosmetics.animation",

  -- Jobs row button
  jobs_texture    = "/server/assets/ui/lmenu/ljobs.png",
  jobs_anim       = "/server/assets/ui/lmenu/ljobs.animation",

  -- Decorative line at the bottom
  line_texture    = "/server/assets/ui/lmenu/lline.png",
  line_x          = 8,     -- around center for 225px wide line at scale 1
  line_y          = 140,   -- near bottom (0..160)
  line_z          = 5,     -- slightly behind/under tabs if you want
  line_sx         = 2.0,   -- X scale
  line_sy         = 1.0,   -- Y scale

  -- "Players Online" tab (drawn on the right side)
  online_tab_texture = "/server/assets/ui/lmenu/lonline.png",
  online_tab_x       = 140,   -- logical X (0..240); move tab left/right
  online_tab_y       = 30,    -- logical Y (0..160); move tab up/down
  online_tab_z       = 6,     -- Z-depth; usually same as other UI
  online_tab_sx      = 2.0,   -- X scale
  online_tab_sy      = 2.0,   -- Y scale

  -- Text (online player count) drawn on top of the tab
  online_text_x      = 214,   -- logical X for number
  online_text_y      = 48,    -- logical Y for number
  online_text_z      = 230,   -- text Z-order (should be above tab)
  online_text_scale  = 1.5,   -- GRADIENT_GREEN font scale
}

-- Sprite IDs (unique per row)
local SPRITE_ID_CARDS      = "lmenu_cards"
local SPRITE_ID_SUMMON     = "lmenu_summon"      -- used for both Summon and Unsummon states
local SPRITE_ID_FRIENDS    = "lmenu_friends"
local SPRITE_ID_COSMETICS  = "lmenu_cosmetics"
local SPRITE_ID_JOBS       = "lmenu_jobs"
local SPRITE_ID_LINE       = "lmenu_line"
local SPRITE_ID_ONLINE_TAB = "lmenu_online_tab"
local ONLINE_TEXT_ID       = "lmenu_online_count"

-- ---------------------------------------------------------------------------
-- Logging (safe even if helpers module isn't present)
-- ---------------------------------------------------------------------------

local helpers_ok, helpers = pcall(require, "scripts/ezlibs-scripts/helpers")

local function log(...)
  if helpers_ok and helpers and type(helpers.info) == "function" then
    helpers.info("[LMenu]", ...)
  else
    local parts = { "[LMenu]" }
    for i = 1, select("#", ...) do
      parts[#parts+1] = tostring(select(i, ...))
    end
    print(table.concat(parts, " "))
  end
end

local function warn(...)
  if helpers_ok and helpers and type(helpers.warn) == "function" then
    helpers.warn("[LMenu][WARN]", ...)
  else
    local parts = { "[LMenu][WARN]" }
    for i = 1, select("#", ...) do
      parts[#parts+1] = tostring(select(i, ...))
    end
    print(table.concat(parts, " "))
  end
end

-- ---------------------------------------------------------------------------
-- Sound effects
-- ---------------------------------------------------------------------------

local sfx = {
  choose = "/server/assets/sfx/card_choose.ogg",
  select = "/server/assets/sfx/card_select.ogg",
  cancel = "/server/assets/sfx/card_cancel.ogg",
}

local function play_sfx(pid, key)
  if not (Net and Net.play_sound_for_player) then
    return
  end

  local path = sfx[key]
  if not path then
    return
  end

  local ok, err = pcall(Net.play_sound_for_player, pid, path)
  if not ok then
    warn("play_sound_for_player failed for", pid, ":", tostring(err))
  end
end

-- ---------------------------------------------------------------------------
-- Stasis helper (kept in case you want it again later)
-- ---------------------------------------------------------------------------

local function compute_stasis_for_player(pid)
  if not Net or not Net.get_player_position then
    return nil
  end

  local pos = Net.get_player_position(pid)
  if not pos then
    return "0,0,0"
  end

  local x = math.floor(tonumber(pos.x) or 0)
  local y = math.floor(tonumber(pos.y) or 0)
  local z = math.floor(tonumber(pos.z) or 0)

  return string.format("%d,%d,%d", x, y, z)
end

-- ---------------------------------------------------------------------------
-- Per-player menu state
-- ---------------------------------------------------------------------------

-- st_by_pid[pid] = {
--    cursor = int,
--    rows   = { { id="cards" }, { id="summon" } / { id="unsummon" } , { id="friends" }, { id="cosmetics" } },
-- }
local st_by_pid = {}

-- ---------------------------------------------------------------------------
-- Online player counter (number only, drawn with GRADIENT_GREEN font)
-- ---------------------------------------------------------------------------

local function count_online_players()
  -- Primary: raids.lua ONLINE table (kept in sync with joins/leaves)
  local online = rawget(_G, "RAIDS_ONLINE")
  if type(online) == "table" then
    local n = 0
    for _ in pairs(online) do
      n = n + 1
    end
    return n
  end

  -- Fallback: Net APIs, in case raids.lua isn't loaded for some reason
  if Net and Net.get_player_ids then
    local ok, ids = pcall(Net.get_player_ids)
    if ok and type(ids) == "table" then
      local n = 0
      for _ in pairs(ids) do
        n = n + 1
      end
      return n
    end
  end

  return 0
end

local function update_online_text(pid)
  local D = Displayer
  if not (D and D.Font and D.Font.drawTextWithId) then
    return
  end

  -- Ensure this player has font sprites allocated
  local fs = D._subsystems and D._subsystems.FontSystem
  if fs and fs.player_fonts and not fs.player_fonts[pid] and fs.setupPlayerFonts then
    pcall(fs.setupPlayerFonts, fs, pid)
  end

  local count = count_online_players()
  local x     = (cfg.online_text_x or 0) * 2
  local y     = (cfg.online_text_y or 0) * 2
  local z     = cfg.online_text_z or 230
  local scale = cfg.online_text_scale or 1.5

  -- Clear previous display (safe even if it does not exist yet)
  pcall(D.Font.eraseTextDisplay, pid, ONLINE_TEXT_ID)

  local ok, err = pcall(
    D.Font.drawTextWithId,
    pid,
    tostring(count),
    x,
    y,
    "GRADIENT_GREEN",
    scale,
    z,
    ONLINE_TEXT_ID
  )

  if not ok then
    warn("Failed to draw online counter for", pid, ":", tostring(err))
  end
end

local function refresh_online_for_all()
  for pid, _ in pairs(st_by_pid) do
    update_online_text(pid)
  end
end

function LMenu.refresh_online_for_all()
  refresh_online_for_all()
end

-- ---------------------------------------------------------------------------
-- Card API helper (bridge to custom.lua)
-- ---------------------------------------------------------------------------

local function card_api()
  return rawget(_G, "card_overworld_api")
end

-- ---------------------------------------------------------------------------
-- Build rows based on card state (armed? summon active?)
-- ---------------------------------------------------------------------------

local function build_rows_for_player(pid)
  local rows = {}

  local api = card_api()
  local has_armed  = false
  local has_summon = false

  if api then
    if type(api.is_card_armed) == "function" then
      local ok, val = pcall(api.is_card_armed, pid)
      has_armed = ok and (val == true)
    end
    if type(api.has_summon) == "function" then
      local ok, val = pcall(api.has_summon, pid)
      has_summon = ok and (val == true)
    end
  end

  -- FIRST: Summon/Unsummon row (when available)
  if has_summon then
    rows[#rows+1] = { id = "unsummon" }
  elseif has_armed then
    rows[#rows+1] = { id = "summon" }
  end

  -- Then the Cards row (always present)
  rows[#rows+1] = { id = "cards" }

  -- Jobs: always show the row
  rows[#rows+1] = { id = "jobs" }

  -- Friends is always available
  rows[#rows+1] = { id = "friends" }

  -- Cosmetics: always show the row
  rows[#rows+1] = { id = "cosmetics" }

  return rows
end

-- ---------------------------------------------------------------------------
-- UI allocation helpers
-- ---------------------------------------------------------------------------

local function ensure_cards_ui(pid, y, selected)
  local x = cfg.row_x_cards or cfg.base_x

  frame.add_ui_element(
    SPRITE_ID_CARDS,
    pid,
    cfg.cards_texture,
    cfg.cards_anim,
    selected and "CARDS_SELECTED" or "CARDS_UNSELECTED",
    x,
    y,
    cfg.z,
    cfg.scale,
    cfg.scale
  )

  if frame.update_ui_position then
    frame.update_ui_position(SPRITE_ID_CARDS, pid, x, y, cfg.z)
  end
  if frame.set_ui_animation then
    frame.set_ui_animation(
      SPRITE_ID_CARDS,
      pid,
      selected and "CARDS_SELECTED" or "CARDS_UNSELECTED"
    )
  end
  if frame.update_ui_element then
    frame.update_ui_element(SPRITE_ID_CARDS, pid, { opacity = 255 })
  end
end

local function ensure_summon_ui(pid, y, row_id, selected)
  -- row_id is "summon" or "unsummon"
  local anim
  if row_id == "summon" then
    anim = selected and "SUMMON_SELECTED" or "SUMMON_UNSELECTED"
  else
    anim = selected and "UNSUMMON_SELECTED" or "UNSUMMON_UNSELECTED"
  end

  local x = cfg.row_x_summon or cfg.base_x

  frame.add_ui_element(
    SPRITE_ID_SUMMON,
    pid,
    cfg.summon_texture,
    cfg.summon_anim,
    anim,
    x,
    y,
    cfg.z,
    cfg.scale,
    cfg.scale
  )

  if frame.update_ui_position then
    frame.update_ui_position(SPRITE_ID_SUMMON, pid, x, y, cfg.z)
  end
  if frame.set_ui_animation then
    frame.set_ui_animation(SPRITE_ID_SUMMON, pid, anim)
  end
  if frame.update_ui_element then
    frame.update_ui_element(SPRITE_ID_SUMMON, pid, { opacity = 255 })
  end
end

local function ensure_friends_ui(pid, y, selected)
  if not cfg.friends_texture or cfg.friends_texture == "" then
    return
  end

  local anim = selected and "FRIENDS_SELECTED" or "FRIENDS_UNSELECTED"
  local x    = cfg.row_x_friends or cfg.base_x

  frame.add_ui_element(
    SPRITE_ID_FRIENDS,
    pid,
    cfg.friends_texture,
    cfg.friends_anim,
    anim,
    x,
    y,
    cfg.z,
    cfg.scale,
    cfg.scale
  )

  if frame.update_ui_position then
    frame.update_ui_position(SPRITE_ID_FRIENDS, pid, x, y, cfg.z)
  end
  if frame.set_ui_animation then
    frame.set_ui_animation(SPRITE_ID_FRIENDS, pid, anim)
  end
  if frame.update_ui_element then
    frame.update_ui_element(SPRITE_ID_FRIENDS, pid, { opacity = 255 })
  end
end

local function ensure_jobs_ui(pid, y, selected)
  if not cfg.jobs_texture or cfg.jobs_texture == "" then
    return
  end

  local anim = selected and "JOBS_SELECTED" or "JOBS_UNSELECTED"
  local x    = cfg.row_x_jobs or cfg.base_x

  frame.add_ui_element(
    SPRITE_ID_JOBS,
    pid,
    cfg.jobs_texture,
    cfg.jobs_anim,
    anim,
    x,
    y,
    cfg.z,
    cfg.scale,
    cfg.scale
  )

  if frame.update_ui_position then
    frame.update_ui_position(SPRITE_ID_JOBS, pid, x, y, cfg.z)
  end
  if frame.set_ui_animation then
    frame.set_ui_animation(SPRITE_ID_JOBS, pid, anim)
  end
  if frame.update_ui_element then
    frame.update_ui_element(SPRITE_ID_JOBS, pid, { opacity = 255 })
  end
end

local function ensure_cosmetics_ui(pid, y, selected)
  if not cfg.cosmetics_texture or cfg.cosmetics_texture == "" then
    -- Asset not configured; keep row logic but no sprite
    return
  end

  local anim = selected and "COSMETICS_SELECTED" or "COSMETICS_UNSELECTED"
  local x    = cfg.row_x_cosmetics or cfg.base_x

  frame.add_ui_element(
    SPRITE_ID_COSMETICS,
    pid,
    cfg.cosmetics_texture,
    cfg.cosmetics_anim,
    anim,
    x,
    y,
    cfg.z,
    cfg.scale,
    cfg.scale
  )

  if frame.update_ui_position then
    frame.update_ui_position(SPRITE_ID_COSMETICS, pid, x, y, cfg.z)
  end
  if frame.set_ui_animation then
    frame.set_ui_animation(SPRITE_ID_COSMETICS, pid, anim)
  end
  if frame.update_ui_element then
    frame.update_ui_element(SPRITE_ID_COSMETICS, pid, { opacity = 255 })
  end
end

local function ensure_line_ui(pid)
  if not cfg.line_texture or cfg.line_texture == "" then
    return
  end

  local x  = cfg.line_x  or 0
  local y  = cfg.line_y  or 0
  local z  = cfg.line_z  or cfg.z
  local sx = cfg.line_sx or cfg.scale
  local sy = cfg.line_sy or cfg.scale

  -- Static image: no animation_path, empty animation_state
  frame.add_ui_element(
    SPRITE_ID_LINE,
    pid,
    cfg.line_texture,
    nil,   -- no animation file
    "",    -- no animation state
    x,
    y,
    z,
    sx,
    sy
  )

  if frame.update_ui_position then
    frame.update_ui_position(SPRITE_ID_LINE, pid, x, y, z)
  end

  if frame.update_ui_element then
    pcall(frame.update_ui_element, SPRITE_ID_LINE, pid, { opacity = 255 })
  end
end

local function ensure_online_tab_ui(pid)
  if not cfg.online_tab_texture or cfg.online_tab_texture == "" then
    return
  end

  local x  = cfg.online_tab_x  or 0
  local y  = cfg.online_tab_y  or 0
  local z  = cfg.online_tab_z  or cfg.z
  local sx = cfg.online_tab_sx or cfg.scale
  local sy = cfg.online_tab_sy or cfg.scale

  frame.add_ui_element(
    SPRITE_ID_ONLINE_TAB,
    pid,
    cfg.online_tab_texture,
    nil,
    "",
    x,
    y,
    z,
    sx,
    sy
  )

  if frame.update_ui_position then
    frame.update_ui_position(SPRITE_ID_ONLINE_TAB, pid, x, y, z)
  end

  if frame.update_ui_element then
    pcall(frame.update_ui_element, SPRITE_ID_ONLINE_TAB, pid, { opacity = 255 })
  end
end

local function hide_summon_ui(pid)
  if not frame.update_ui_element then
    return
  end
  pcall(frame.update_ui_element, SPRITE_ID_SUMMON, pid, { opacity = 0 })
end

local function clear_all_ui(pid)
  if frame.remove_ui_element then
    pcall(frame.remove_ui_element, SPRITE_ID_CARDS,      pid)
    pcall(frame.remove_ui_element, SPRITE_ID_SUMMON,     pid)
    pcall(frame.remove_ui_element, SPRITE_ID_LINE,       pid)
    pcall(frame.remove_ui_element, SPRITE_ID_ONLINE_TAB, pid)
    pcall(frame.remove_ui_element, SPRITE_ID_FRIENDS,    pid)
    pcall(frame.remove_ui_element, SPRITE_ID_COSMETICS,  pid)
    pcall(frame.remove_ui_element, SPRITE_ID_JOBS,       pid)
  end

  if Displayer and Displayer.Font and Displayer.Font.eraseTextDisplay then
    pcall(Displayer.Font.eraseTextDisplay, pid, ONLINE_TEXT_ID)
  end
end

-- ---------------------------------------------------------------------------
-- Redraw menu for a player
-- ---------------------------------------------------------------------------

local function rebuild_and_redraw(pid)
  local st = st_by_pid[pid]
  if not st then return end

  st.rows = build_rows_for_player(pid)
  local rows  = st.rows
  local count = #rows

  if count == 0 then
    clear_all_ui(pid)
    st.cursor = nil
    return
  end

  -- Clamp cursor
  if not st.cursor or st.cursor < 1 or st.cursor > count then
    st.cursor = 1
  end

  -- Draw rows
  for i, row in ipairs(rows) do
    local y = cfg.base_y + (i - 1) * cfg.row_spacing
    local selected = (i == st.cursor)

    if row.id == "cards" then
      ensure_cards_ui(pid, y, selected)
    elseif row.id == "summon" or row.id == "unsummon" then
      ensure_summon_ui(pid, y, row.id, selected)
    elseif row.id == "friends" then
      ensure_friends_ui(pid, y, selected)
    elseif row.id == "cosmetics" then
      ensure_cosmetics_ui(pid, y, selected)
    elseif row.id == "jobs" then
      ensure_jobs_ui(pid, y, selected)
    end
  end

  -- If we only have a Cards row, hide the summon sprite so it doesn't linger
  if count < 2 then
    hide_summon_ui(pid)
  end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function LMenu.is_open_for(pid)
  return st_by_pid[pid] ~= nil
end

function LMenu.open(pid)
  if st_by_pid[pid] then
    return
  end

  st_by_pid[pid] = {
    cursor          = 1,
    rows            = {},
    last_nav_button = nil,
    last_nav_time   = 0,
    has_selected    = false,
  }

  -- Lock player input so we start receiving Net:on("virtual_input") events (net-games v2.1)
  if Net and Net.lock_player_input then
    local ok, err = pcall(Net.lock_player_input, pid)
    if not ok then
      warn("lock_player_input failed for", pid, "err:", tostring(err))
    end
  else
    warn("Net.lock_player_input not available; LMenu cannot lock player input.")
  end

  rebuild_and_redraw(pid)
  ensure_line_ui(pid)
  ensure_online_tab_ui(pid)
  update_online_text(pid)

  log("Opened LMenu for", pid)
end

function LMenu.close(pid, opts)
  local st = st_by_pid[pid]
  if not st then return end

  clear_all_ui(pid)
  st_by_pid[pid] = nil

  -- Allow callers to keep the player locked (used by Cosmetics submenu)
  local keep_frozen = (type(opts) == "table" and opts.keep_frozen == true)

  if not keep_frozen then
    if Net and Net.unlock_player_input then
      local ok, err = pcall(Net.unlock_player_input, pid)
      if not ok then
        warn("unlock_player_input failed for", pid, "err:", tostring(err))
      end
    else
      warn("Net.unlock_player_input not available; player may remain locked.")
    end
  end

  log("Closed LMenu for", pid)
end

local DEBUG_INPUT = false  -- set to true if you want to log virtual_input events

-- Hold-repeat settings for LMenu Up/Down navigation.
-- These ONLY apply to held buttons, not single presses.
local HOLD_FIRST_DELAY_SEC  = 0.15   -- wait this long before first repeat
local HOLD_REPEAT_DELAY_SEC = 0.02  -- then repeat at this interval

local function hold_nav_allowed(st, dir)
  local now = (os and os.clock and os.clock()) or 0

  -- New hold direction or fresh hold: initialize & don't move yet
  if st.hold_nav_dir ~= dir then
    st.hold_nav_dir          = dir
    st.hold_nav_start_time   = now
    st.hold_nav_last_time    = now
    st.hold_nav_first_fired  = false
    return false
  end

  local start = st.hold_nav_start_time or now
  local last  = st.hold_nav_last_time or start

  -- First repeat: wait HOLD_FIRST_DELAY_SEC
  if not st.hold_nav_first_fired then
    if (now - start) < HOLD_FIRST_DELAY_SEC then
      return false
    end
    st.hold_nav_first_fired = true
    st.hold_nav_last_time   = now
    return true
  end

  -- Subsequent repeats: wait HOLD_REPEAT_DELAY_SEC between moves
  if (now - last) < HOLD_REPEAT_DELAY_SEC then
    return false
  end

  st.hold_nav_last_time = now
  return true
end

local function reset_hold_nav(st, dir)
  if not st then return end
  if dir == nil or st.hold_nav_dir == dir then
    st.hold_nav_dir         = nil
    st.hold_nav_start_time  = nil
    st.hold_nav_last_time   = nil
    st.hold_nav_first_fired = nil
  end
end


local function handle_lmenu_button(pid, btn)
  -- No extra guards here; caller is responsible for passing LS/A/U/D

  local st = st_by_pid[pid]

  -- Menu closed: LS opens it
  if not st then
    if btn == "LS" then
      -- If Cosmetics just closed from this same button press, skip opening.
      if suppress_next_open[pid] then
        suppress_next_open[pid] = nil
        return
      end
      LMenu.open(pid)
    end
    return
  end

  -- Menu is open

  -- LS = close menu
  if btn == "LS" then
    if not st.has_selected then
      play_sfx(pid, "cancel")
    end
    LMenu.close(pid)
    return
  end

  -- U/D = move cursor
  if btn == "U" or btn == "D" then
    local rows  = st.rows or {}
    local count = #rows
    if count <= 1 then
      return
    end

    if btn == "U" then
      st.cursor = st.cursor - 1
      if st.cursor < 1 then st.cursor = count end
    else
      st.cursor = st.cursor + 1
      if st.cursor > count then st.cursor = 1 end
    end

    rebuild_and_redraw(pid)
    play_sfx(pid, "select")
    return
  end

  -- A = activate current row
  if btn == "A" then
    local rows  = st.rows or {}
    local row   = rows[st.cursor or 1]
    if not row then return end

    st.has_selected = true
    play_sfx(pid, "choose")

    local api = card_api()

    -- Cards: open card collection
    if row.id == "cards" then
      LMenu.close(pid)
      if api and type(api.open_card_list) == "function" then
        local ok2, err2 = pcall(api.open_card_list, pid)
        if not ok2 then
          warn("open_card_list failed:", tostring(err2))
        end
      else
        Net.message_player(pid, "(Card Collection not available.)")
      end
      return
    end

    -- Summon armed card
    if row.id == "summon" then
      if not api or type(api.summon_armed) ~= "function" then
        Net.message_player(pid, "(Summon not available.)")
        return
      end
      local ok2, res = pcall(api.summon_armed, pid)
      if not ok2 then
        warn("summon_armed error:", tostring(res))
        return
      end
      rebuild_and_redraw(pid)
      return
    end

    -- Unsummon
    if row.id == "unsummon" then
      if not api or type(api.unsummon) ~= "function" then
        Net.message_player(pid, "(Unsummon not available.)")
        return
      end
      local ok2, res = pcall(api.unsummon, pid)
      if not ok2 then
        warn("unsummon error:", tostring(res))
        return
      end
      rebuild_and_redraw(pid)
      return
    end

    -- Friends board
    if row.id == "friends" then
      LMenu.close(pid)

      if Friends and type(Friends.open_friends_board) == "function" then
        local okf, errf = pcall(Friends.open_friends_board, pid)
        if not okf then
          warn("Friends.open_friends_board failed:", tostring(errf))
        end
      else
        Net.message_player(pid, "(Friends menu not available.)")
      end
      return
    end

    -- Jobs progress viewer
    if row.id == "jobs" then
      LMenu.close(pid)

      if JobBBS and type(JobBBS.open_progress_board) == "function" then
        local okj, errj = pcall(JobBBS.open_progress_board, pid)
        if not okj then
          warn("JobBBS.open_progress_board failed for", pid, ":", tostring(errj))
        end
      else
        Net.message_player(pid, "(Job progress viewer not available.)")
      end
      return
    end

    -- Cosmetics submenu
    if row.id == "cosmetics" then
      -- Close the LMenu but keep the player locked, then open the Cosmetics submenu.
      LMenu.close(pid, { keep_frozen = true })

      if Cosmetics and type(Cosmetics.open_menu) == "function" then
        local okc, errc = pcall(Cosmetics.open_menu, pid)
        if not okc then
          warn("Cosmetics.open_menu failed for", pid, ":", tostring(errc))
          -- Fail-safe: unlock so the player isn't stuck
          if Net and Net.unlock_player_input then
            local ok2, err2 = pcall(Net.unlock_player_input, pid)
            if not ok2 then
              warn("unlock_player_input after Cosmetics.open_menu failure:", tostring(err2))
            end
          end
        end
      else
        Net.message_player(pid, "(Cosmetics menu not available.)")
        -- Also unlock in this case
        if Net and Net.unlock_player_input then
          local ok2, err2 = pcall(Net.unlock_player_input, pid)
          if not ok2 then
            warn("unlock_player_input after missing Cosmetics module:", tostring(err2))
          end
        end
      end

      return
    end
  end
end

-- ---------------------------------------------------------------------------
-- Button handling: opener via Net:on("button_press"),
-- navigation via Net:on("virtual_input")
-- ---------------------------------------------------------------------------

if Net and Net.on then
  -- Use the legacy button_press event ONLY as a way to open the menu
  -- while the player is not yet locked. As soon as the menu opens,
  -- LMenu.open() calls Net.lock_player_input and we switch to virtual_input.
  Net:on("button_press", function(event)
    local pid = event.player_id
    local btn = event.button
    if not pid or not btn then
      return
    end

    -- If either LMenu or Cosmetics are already open for this player,
    -- ignore button_press. Input while "frozen" is handled by virtual_input.
    local lmenu_open = (st_by_pid[pid] ~= nil)

    local cosmetics_open = false
    if Cosmetics and type(Cosmetics.is_open) == "function" then
      local ok, open = pcall(Cosmetics.is_open, pid)
      cosmetics_open = ok and open
    end

    if lmenu_open or cosmetics_open then
      return
    end

    -- Old engine names here ("LS", "A", "U", "D", etc.).
    -- We only care about LS to open the menu.
    if btn == "LS" then
      handle_lmenu_button(pid, "LS")
    end
  end)

  Net:on("virtual_input", function(event)
    local pid  = event.player_id
    local evs  = event.events

    if DEBUG_INPUT then
      -- Log that we at least received the event, even if events is nil/empty
      log("virtual_input event for pid=", pid, "has_events=", evs and "yes" or "no")
    end

    if not evs then return end

    -- Cache whether menus are open for this player
    local function is_cosmetics_open()
      if not (Cosmetics and type(Cosmetics.is_open) == "function") then
        return false
      end
      local ok, open = pcall(Cosmetics.is_open, pid)
      return ok and open
    end

    local cosmetics_open = is_cosmetics_open()
    local lmenu_open     = (st_by_pid[pid] ~= nil)

    for _, button in next, evs do
      local name  = button.name
      local state = button.state

      if DEBUG_INPUT then
        log("virtual_input pid=", pid, "name=", name, "state=", state)
      end

      ----------------------------------------------------------------
      -- 1) Global hard-close: Pause / Shoulder R
      ----------------------------------------------------------------
      if state == 1 and (name == "Pause" or name == "Shoulder R") then
        local did_any = false

        -- Close Cosmetics if open
        if cosmetics_open and Cosmetics and type(Cosmetics.close) == "function" then
          local okc, errc = pcall(Cosmetics.close, pid)
          if not okc then
            warn("Cosmetics.close via Pause/Shoulder R failed for", pid, ":", tostring(errc))
          end
          cosmetics_open = false
          did_any = true
        end

        -- Close LMenu if open
        if st_by_pid[pid] then
          LMenu.close(pid)
          lmenu_open = false
          did_any = true
        end

        if did_any then
          return
        end
      end

      ----------------------------------------------------------------
      -- 2) Global back: Shoot
      --    - If Cosmetics open -> back to LMenu (keep locked)
      --    - Else if LMenu open -> close LMenu
      ----------------------------------------------------------------
      if state == 1 and name == "Shoot" then
        if cosmetics_open then
          if Cosmetics and type(Cosmetics.close) == "function" then
            -- close submenu but keep player input locked
            local okc, errc = pcall(Cosmetics.close, pid, { keep_frozen = true })
            if not okc then
              warn("Cosmetics.close (keep_frozen) via Shoot failed for", pid, ":", tostring(errc))
            end
          end

          cosmetics_open = false

          -- Immediately go back to LMenu (still locked)
          if not st_by_pid[pid] then
            LMenu.open(pid)
            lmenu_open = true
          end
          return
        elseif lmenu_open then
          -- LMenu is open: Shoot acts as back/close
          LMenu.close(pid)
          lmenu_open = false
          return
        end
        -- If nothing is open, ignore Shoot
      end

      ----------------------------------------------------------------
      -- 3) Regular LMenu navigation (only when Cosmetics is NOT open)
      --    - Taps on U/D move immediately
      --    - Holds on U/D wait 1s, then repeat every 0.15s
      ----------------------------------------------------------------
      if not cosmetics_open then
        -- Map engine button names to old LMenu logical buttons:
        --   LS = "Shoulder L"
        --   U  = "Move Up"
        --   D  = "Move Down"
        --   A  = "Confirm"

        local st_for_nav = st_by_pid[pid]
        local is_press       = (state == 1)
        local is_hold_or_scr = (state == 2 or state == 4)

        ----------------------------------------------------------------
        -- Single presses: always instantaneous, no delay at all
        ----------------------------------------------------------------
        if is_press then
          local btn = nil

          if name == "Shoulder L" or name == "LS" then           -- open/close LMenu
            btn = "LS"
          elseif name == "Confirm" then
            btn = "A"
          elseif name == "Move Up" then
            -- New tap: clear any hold state so a fresh hold
            -- will get its own 1s delay.
            if st_for_nav then reset_hold_nav(st_for_nav, "U") end
            btn = "U"
          elseif name == "Move Down" then
            if st_for_nav then reset_hold_nav(st_for_nav, "D") end
            btn = "D"
          end

          if btn then
            handle_lmenu_button(pid, btn)
            lmenu_open = (st_by_pid[pid] ~= nil)
          end
        end

        ----------------------------------------------------------------
        -- Held / scroll: only used for Up/Down repeats with delay
        ----------------------------------------------------------------
        if is_hold_or_scr and st_for_nav then
          local dir = nil
          if name == "Move Up" then
            dir = "U"
          elseif name == "Move Down" then
            dir = "D"
          end

          if dir and hold_nav_allowed(st_for_nav, dir) then
            handle_lmenu_button(pid, dir)
            lmenu_open = (st_by_pid[pid] ~= nil)
          end
        end
      end
    end
  end)

  Net:on("player_join", function(e)
    -- Optional: could refresh online count here
  end)

  -- Safety: auto-close on disconnect / area change
  Net:on("player_disconnect", function(e)
    if e and e.player_id then
      LMenu.close(e.player_id)
    end
  end)

  Net:on("area_transfer", function(e)
    if e and e.player_id then
      -- Area change: close menu so states don't leak between maps
      LMenu.close(e.player_id)
    end
  end)
end

return LMenu
