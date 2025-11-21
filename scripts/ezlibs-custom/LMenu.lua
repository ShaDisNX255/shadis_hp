-- /server/scripts/ezlibs-custom/LMenu.lua
-- L Menu:
--   LS   = open/close
--   U/D  = move cursor
--   A    = activate row (Cards / Summon / Unsummon / Friends / Cosmetics)

local LMenu = {}
_G.LMenu = LMenu  -- expose globally so other scripts can query state if needed

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
  row_x_cosmetics = 13,

  -- Cards row (always present)
  cards_texture   = "/server/assets/ui/lmenu/lcards.png",
  cards_anim      = "/server/assets/ui/lmenu/lcards.animation",

  -- Summon / Unsummon row (shares same sprite, different anim states)
  summon_texture  = "/server/assets/ui/lmenu/lsummon.png",
  summon_anim     = "/server/assets/ui/lmenu/lsummon.animation",

  friends_texture = "/server/assets/ui/lmenu/lfriends.png",
  friends_anim    = "/server/assets/ui/lmenu/lfriends.animation",

  -- Cosmetics row button (slightly longer tab)
  -- NOTE: adjust these to your actual asset paths.
  cosmetics_texture = "/server/assets/ui/lmenu/lcosmetics.png",
  cosmetics_anim    = "/server/assets/ui/lmenu/lcosmetics.animation",

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

  -- Cosmetic definition (actual effect that set_cosmetic will apply)
  -- IMPORTANT: point these to your snowflake assets + state.
  cosmetic_id         = "snowflake_particle",
  cosmetic_texture    = "/server/assets/cosmetics/snowflake_particle.png",
  cosmetic_animation  = "/server/assets/cosmetics/snowflake_particle.animation",
  cosmetic_anim_state = "SNOWFLAKE_PARTICLE",

  -- Cosmetic preview behavior (screen-space movement)
  cosmetics_preview_step    = 2,    -- how many logical units per D-pad tap
  cosmetics_preview_start_x = 0,    -- offset from screen center (0 = centered)
  cosmetics_preview_start_y = -24,  -- e.g., slightly above center
  cosmetics_preview_z       = 6,
  cosmetics_preview_scale   = 2.0,
}

-- Sprite IDs (unique per row)
local SPRITE_ID_CARDS         = "lmenu_cards"
local SPRITE_ID_SUMMON        = "lmenu_summon"      -- used for both Summon and Unsummon states
local SPRITE_ID_FRIENDS       = "lmenu_friends"
local SPRITE_ID_COSMETICS     = "lmenu_cosmetics"
local SPRITE_ID_LINE          = "lmenu_line"
local SPRITE_ID_ONLINE_TAB    = "lmenu_online_tab"
local ONLINE_TEXT_ID          = "lmenu_online_count"

-- Preview sprite for the cosmetic (camera/UI-aligned during preview)
local COSMETICS_PREVIEW_SPRITE_ID = "lmenu_cosmetic_preview"

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
-- Per-player menu + cosmetic state
-- ---------------------------------------------------------------------------

-- st_by_pid[pid] = {
--    cursor = int,
--    rows   = { { id="cards" }, { id="summon" } / { id="unsummon" } , { id="friends" }, { id="cosmetics" } },
-- }
local st_by_pid = {}

-- Tracks whether the cosmetic is currently equipped for this player
local cosmetics_equipped = {}  -- [pid] = true/false

-- Preview state: active while the snowflake is being positioned
-- cosmetics_preview_by_pid[pid] = { active=true, x=<offset>, y=<offset> }
local cosmetics_preview_by_pid = {}

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

  -- Always have Cards row
  rows[#rows+1] = { id = "cards" }

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

  -- Slot 2 (when available) = Summon/Unsummon
  if has_summon then
    rows[#rows+1] = { id = "unsummon" }
  elseif has_armed then
    rows[#rows+1] = { id = "summon" }
  end

  -- Friends is always available
  rows[#rows+1] = { id = "friends" }

  -- Cosmetics: always show the row (we'll handle missing assets gracefully)
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

local function clear_cosmetics_preview_ui(pid)
  if frame.remove_ui_element then
    pcall(frame.remove_ui_element, COSMETICS_PREVIEW_SPRITE_ID, pid)
  end
end

local function clear_all_ui(pid)
  if frame.remove_ui_element then
    pcall(frame.remove_ui_element, SPRITE_ID_CARDS,      pid)
    pcall(frame.remove_ui_element, SPRITE_ID_SUMMON,     pid)
    pcall(frame.remove_ui_element, SPRITE_ID_LINE,       pid)
    pcall(frame.remove_ui_element, SPRITE_ID_ONLINE_TAB, pid)
    pcall(frame.remove_ui_element, SPRITE_ID_FRIENDS,    pid)
    pcall(frame.remove_ui_element, SPRITE_ID_COSMETICS,  pid)
    pcall(frame.remove_ui_element, COSMETICS_PREVIEW_SPRITE_ID, pid)
  end

  if Displayer and Displayer.Font and Displayer.Font.eraseTextDisplay then
    pcall(Displayer.Font.eraseTextDisplay, pid, ONLINE_TEXT_ID)
  end
end

-- ---------------------------------------------------------------------------
-- Cosmetic preview helpers
-- ---------------------------------------------------------------------------

local function cosmetics_preview_active(pid)
  local st = cosmetics_preview_by_pid[pid]
  return st and st.active
end

local function draw_cosmetics_preview(pid)
  local st = cosmetics_preview_by_pid[pid]
  if not (st and st.active) then
    return
  end

  local texture = cfg.cosmetic_texture
  local anim    = cfg.cosmetic_animation
  local state   = cfg.cosmetic_anim_state or "SNOWFLAKE_PARTICLE"

  if not texture or texture == "" or not anim or anim == "" then
    warn("Cosmetic preview requested but cosmetic assets not configured.")
    return
  end

  -- Center of screen in logical coords is approximately (120, 80).
  local base_x = 120
  local base_y = 80

  local x = base_x + (st.x or 0)
  local y = base_y + (st.y or 0)
  local z = cfg.cosmetics_preview_z or cfg.z or 6
  local s = cfg.cosmetics_preview_scale or 2.0

  frame.add_ui_element(
    COSMETICS_PREVIEW_SPRITE_ID,
    pid,
    texture,
    anim,
    state,
    x,
    y,
    z,
    s,
    s
  )

  if frame.update_ui_position then
    frame.update_ui_position(COSMETICS_PREVIEW_SPRITE_ID, pid, x, y, z)
  end
end

local function start_cosmetics_preview(pid)
  local texture = cfg.cosmetic_texture
  local anim    = cfg.cosmetic_animation

  if not texture or texture == "" or not anim or anim == "" then
    warn("Cosmetics button pressed but cosmetic assets not configured; skipping preview.")
    return
  end

  cosmetics_preview_by_pid[pid] = {
    active = true,
    x = cfg.cosmetics_preview_start_x or 0,
    y = cfg.cosmetics_preview_start_y or 0,
  }

  -- IMPORTANT: no Net.message_player here (user requested no messages during preview)
  draw_cosmetics_preview(pid)
end

local function stop_cosmetics_preview(pid)
  cosmetics_preview_by_pid[pid] = nil
  clear_cosmetics_preview_ui(pid)
end

local function finalize_cosmetics_from_preview(pid)
  local st = cosmetics_preview_by_pid[pid]
  if not (st and st.active) then
    return
  end

  -- Take a copy of the offsets before clearing preview
  local x_offset = st.x or 0
  local y_offset = st.y or 0

  stop_cosmetics_preview(pid)

  local cosmetic_id = cfg.cosmetic_id or "snowflake_particle"
  local texture     = cfg.cosmetic_texture
  local anim        = cfg.cosmetic_animation
  local state       = cfg.cosmetic_anim_state or "SNOWFLAKE_PARTICLE"

  if not (texture and anim and cosmetic_id) or texture == "" or anim == "" or cosmetic_id == "" then
    warn("Cosmetic finalize requested but cosmetic not configured.")
    return
  end

  if type(frame.set_cosmetic) ~= "function" then
    warn("frame.set_cosmetic not available; cannot apply cosmetic.")
    return
  end

  -- Apply cosmetic via net-games framework; this spawns both the player sprite + public bot
  local ok, err = pcall(
    frame.set_cosmetic,
    cosmetic_id,
    pid,
    texture,
    anim,
    state,
    x_offset,
    y_offset,
    true,  -- visible
    0,     -- player_xoffset
    0,     -- player_yoffset
    1    -- anim_duration
  )

  if not ok then
    warn("set_cosmetic failed for", pid, ":", tostring(err))
    Net.message_player(pid, "(Failed to apply cosmetic; see server log.)")
    return
  end

  -- We were still in the LMenu freeze/stasis. Confirming with A now unlocks inputs.
  local ok2, err2 = pcall(frame.unfreeze_player, pid)
  if not ok2 then
    warn("unfreeze_player failed after cosmetic apply for", pid, ":", tostring(err2))
  end

  cosmetics_equipped[pid] = true

  -- This is the ONLY time we message the player for this feature (OK per your request)
  Net.message_player(pid, "Snowflake cosmetic applied.")
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

  -- Freeze player using map-defined Stasis only
  local ok, err = pcall(frame.freeze_player, pid)
  if not ok then
    warn("freeze_player failed for", pid, "err:", tostring(err))
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

  -- Allow callers to keep the player frozen (used by Cosmetics preview)
  local keep_frozen = (type(opts) == "table" and opts.keep_frozen == true)

  if not keep_frozen then
    local ok, err = pcall(frame.unfreeze_player, pid)
    if not ok then
      warn("unfreeze_player failed for", pid, "err:", tostring(err))
    end
  end

  log("Closed LMenu for", pid)
end

local NAV_DEBOUNCE_SEC = 0.02  -- tweak if needed

local function nav_allowed(st, button)
  local now = (os and os.clock and os.clock()) or 0

  local last_btn  = st.last_nav_button
  local last_time = st.last_nav_time or 0

  if last_btn == button and (now - last_time) < NAV_DEBOUNCE_SEC then
    return false
  end

  st.last_nav_button = button
  st.last_nav_time   = now
  return true
end

-- ---------------------------------------------------------------------------
-- Button handling
-- ---------------------------------------------------------------------------

if Net and Net.on then
  Net:on("button_press", function(event)
    local pid = event.player_id
    local btn = event.button

    -- First priority: cosmetic preview, if active.
    -- While preview is active, LMenu (and other logic in this file) does not react.
    if cosmetics_preview_active(pid) then
      local st = cosmetics_preview_by_pid[pid]
      local step = cfg.cosmetics_preview_step or 2

      if btn == "U" then
        st.y = (st.y or 0) - step
        draw_cosmetics_preview(pid)
      elseif btn == "D" then
        st.y = (st.y or 0) + step
        draw_cosmetics_preview(pid)
      elseif btn == "L" then
        st.x = (st.x or 0) - step
        draw_cosmetics_preview(pid)
      elseif btn == "R" then
        st.x = (st.x or 0) + step
        draw_cosmetics_preview(pid)
      elseif btn == "A" then
        -- Confirm / anchor cosmetic (this will send a single message to the player)
        finalize_cosmetics_from_preview(pid)
      elseif btn == "LS" then
        -- Cancel preview with no messages
        stop_cosmetics_preview(pid)
      end

      -- Do not let preview button presses also drive LMenu open/close
      return
    end

    -- From here down, no preview is active.

    -- We only care about LS/A/U/D in the LMenu logic
    if btn ~= "LS" and btn ~= "A" and btn ~= "U" and btn ~= "D" then
      return
    end

    local st = st_by_pid[pid]

    -- Menu closed: LS opens it, everything else ignored
    if not st then
      if btn == "LS" then
        LMenu.open(pid)
      end
      return
    end

    -- Menu is open now

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
      if not nav_allowed(st, btn) then
        return
      end
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

      if row.id == "friends" then
        LMenu.close(pid)

        if Friends and type(Friends.open_friends_board) == "function" then
          local okf, errf = pcall(Friends.open_friends_board, pid)
          if not okf then
            warn("friends.open_friends_board failed:", tostring(errf))
          end
        else
          Net.message_player(pid, "(Friends menu not available.)")
        end
        return
      end

      if row.id == "cosmetics" then
        -- Toggle behavior:
        --   - If cosmetic already equipped, unequip immediately (no preview)
        --   - If not equipped, close LMenu and enter preview mode
        local already = cosmetics_equipped[pid] == true
        local cosmetic_id = cfg.cosmetic_id or "snowflake_particle"

        if already then
          if type(frame.remove_cosmetic) == "function" then
            local ok2, err2 = pcall(frame.remove_cosmetic, cosmetic_id, pid)
            if not ok2 then
              warn("remove_cosmetic failed:", tostring(err2))
            end
          end
          cosmetics_equipped[pid] = nil
          LMenu.close(pid)
          Net.message_player(pid, "Snowflake cosmetic removed.")
        else
          -- Close menu and enter preview; no messages (per your request)
          LMenu.close(pid, { keep_frozen = true })
          start_cosmetics_preview(pid)
        end

        return
      end
    end
  end)

  Net:on("player_join", function(e)
    -- Whenever someone joins, you could refresh the online counter for all open LMenus
    -- For now we leave it no-op, since the RAIDS_ONLINE table usually drives this.
  end)

  -- Safety: auto-close on disconnect / area change
  Net:on("player_disconnect", function(e)
    if e and e.player_id then
      -- End any preview in progress
      stop_cosmetics_preview(e.player_id)
      cosmetics_equipped[e.player_id] = nil
      LMenu.close(e.player_id)
    end
  end)

  Net:on("area_transfer", function(e)
    if e and e.player_id then
      -- Area change: close menu and cancel preview so states don't leak between maps
      stop_cosmetics_preview(e.player_id)
      LMenu.close(e.player_id)
    end
  end)
end

return LMenu
