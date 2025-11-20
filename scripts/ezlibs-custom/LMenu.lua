-- /server/scripts/ezlibs-custom/LMenu.lua
-- L Menu:
--   LS   = open/close
--   U/D  = move cursor
--   A    = activate row (Cards / Summon / Unsummon)

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
  base_x      = 15,   -- move menu left/right
  base_y      = 30,   -- move menu up/down
  row_spacing = 18,   -- vertical distance between rows
  z           = 6,    -- UI Z-depth
  scale       = 2,  -- change if tabs feel too big/small

  -- Cards row (always present)
  cards_texture   = "/server/assets/ui/lmenu/lcards.png",
  cards_anim      = "/server/assets/ui/lmenu/lcards.animation",

  -- Summon / Unsummon row (shares same sprite, different anim states)
  summon_texture  = "/server/assets/ui/lmenu/lsummon.png",
  summon_anim     = "/server/assets/ui/lmenu/lsummon.animation",

  friends_texture = "/server/assets/ui/lmenu/lfriends.png",
  friends_anim    = "/server/assets/ui/lmenu/lfriends.animation",

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
local SPRITE_ID_CARDS         = "lmenu_cards"
local SPRITE_ID_SUMMON        = "lmenu_summon"  -- used for both Summon and Unsummon states
local SPRITE_ID_FRIENDS       = "lmenu_friends"
local SPRITE_ID_LINE          = "lmenu_line"
local SPRITE_ID_ONLINE_TAB    = "lmenu_online_tab"
local ONLINE_TEXT_ID          = "lmenu_online_count"

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
-- Stasis: compute a per-player stasis override for freeze_player
-- ---------------------------------------------------------------------------

local function compute_stasis_for_player(pid)
  if not Net or not Net.get_player_position then
    return nil
  end

  local pos = Net.get_player_position(pid)
  if not pos then
    -- Fallback: some safe-ish default; you can tweak this if needed
    return "0,0,0"
  end

  -- Use the *exact* tile the player is currently on.
  -- freeze_player treats these as tile coords and adds +0.5 internally.
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
--    rows   = { { id="cards" }, { id="summon" } / { id="unsummon" } },
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
  -- (covers cases where they joined before FontSystem init, or weird race conditions)
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

  -- Friends is always available, and:
  --   - If Summon/Unsummon exists, Friends becomes slot 3
  --   - If not, Friends becomes slot 2
  rows[#rows+1] = { id = "friends" }

  return rows
end

-- ---------------------------------------------------------------------------
-- UI allocation helpers
-- ---------------------------------------------------------------------------

local function ensure_cards_ui(pid, y, selected)
  -- Allocate if not present; add_ui_element is idempotent thanks to ui_cache
  frame.add_ui_element(
    SPRITE_ID_CARDS,
    pid,
    cfg.cards_texture,
    cfg.cards_anim,
    selected and "CARDS_SELECTED" or "CARDS_UNSELECTED",
    cfg.base_x,
    y,
    cfg.z,
    cfg.scale,
    cfg.scale
  )

  -- Move to correct position and update anim
  if frame.update_ui_position then
    frame.update_ui_position(SPRITE_ID_CARDS, pid, cfg.base_x, y, cfg.z)
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

  frame.add_ui_element(
    SPRITE_ID_SUMMON,
    pid,
    cfg.summon_texture,
    cfg.summon_anim,
    anim,
    cfg.base_x,
    y,
    cfg.z,
    cfg.scale,
    cfg.scale
  )

  if frame.update_ui_position then
    frame.update_ui_position(SPRITE_ID_SUMMON, pid, cfg.base_x, y, cfg.z)
  end
  if frame.set_ui_animation then
    frame.set_ui_animation(SPRITE_ID_SUMMON, pid, anim)
  end
  if frame.update_ui_element then
    frame.update_ui_element(SPRITE_ID_SUMMON, pid, { opacity = 255 })
  end
end

local function ensure_friends_ui(pid, y, selected)
  -- If you temporarily don’t want a sprite, leave friends_texture empty and this will no-op.
  if not cfg.friends_texture or cfg.friends_texture == "" then
    return
  end

  local anim = selected and "FRIENDS_SELECTED" or "FRIENDS_UNSELECTED"

  frame.add_ui_element(
    SPRITE_ID_FRIENDS,
    pid,
    cfg.friends_texture,
    cfg.friends_anim,
    anim,
    cfg.base_x,
    y,
    cfg.z,
    cfg.scale,
    cfg.scale
  )

  if frame.update_ui_position then
    frame.update_ui_position(SPRITE_ID_FRIENDS, pid, cfg.base_x, y, cfg.z)
  end
  if frame.set_ui_animation then
    frame.set_ui_animation(SPRITE_ID_FRIENDS, pid, anim)
  end
  if frame.update_ui_element then
    frame.update_ui_element(SPRITE_ID_FRIENDS, pid, { opacity = 255 })
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
    -- Make sure it's visible
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

  -- On first open, the summon sprite may not exist yet.
  -- Wrapping this in pcall avoids a hard crash when ui_cache[player_id][sprite_id] is nil.
  local ok, _ = pcall(frame.update_ui_element, SPRITE_ID_SUMMON, pid, { opacity = 0 })
  -- If it fails, we just silently ignore it; once the sprite exists, this will work.
end



local function clear_all_ui(pid)
  if frame.remove_ui_element then
    pcall(frame.remove_ui_element, SPRITE_ID_CARDS,      pid)
    pcall(frame.remove_ui_element, SPRITE_ID_SUMMON,     pid)
    pcall(frame.remove_ui_element, SPRITE_ID_LINE,       pid)
    pcall(frame.remove_ui_element, SPRITE_ID_ONLINE_TAB, pid)
    pcall(frame.remove_ui_element, SPRITE_ID_FRIENDS,    pid)
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
  local rows = st.rows
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

function LMenu.close(pid)
  local st = st_by_pid[pid]
  if not st then return end

  clear_all_ui(pid)
  st_by_pid[pid] = nil

  local ok, err = pcall(frame.unfreeze_player, pid)
  if not ok then
    warn("unfreeze_player failed for", pid, "err:", tostring(err))
  end

  log("Closed LMenu for", pid)
end

local NAV_DEBOUNCE_SEC = 0.02  -- tweak if needed

local function nav_allowed(st, button)
  -- Use os.clock() if available; otherwise no debouncing.
  local now = (os and os.clock and os.clock()) or 0

  local last_btn  = st.last_nav_button
  local last_time = st.last_nav_time or 0

  if last_btn == button and (now - last_time) < NAV_DEBOUNCE_SEC then
    -- Too soon, treat as "still holding the same button"
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

    -- We only care about LS/A/U/D
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

    -- From here down, menu is open

    -- LS = close menu
    if btn == "LS" then
      -- Only play cancel if they never selected anything this session
      if not st.has_selected then
        play_sfx(pid, "cancel")
      end
      LMenu.close(pid)
      return
    end

    -- U/D = move cursor
    if btn == "U" or btn == "D" then
      -- Debounce: ignore very rapid repeats of the same button
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
      -- Mark that something was selected this session (affects cancel SFX logic)
      st.has_selected = true

      -- Play selection sound for any of the main options
      play_sfx(pid, "choose")

      local api = card_api()

      if row.id == "cards" then
        -- Close menu and open Card Collection
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
        -- After summoning, rows change (we now have Unsummon), so rebuild UI
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
        -- After unsummoning, rows may change; rebuild UI
        rebuild_and_redraw(pid)
        return
      end
      if row.id == "friends" then
        -- Close menu and open Friends placeholder BBS
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
    end
  end)

  Net:on("player_join", function(e)
    -- Whenever someone joins, refresh the online counter for all players that have LMenu open
  end)

  -- Safety: auto-close on disconnect / area change
  Net:on("player_disconnect", function(e)
    if e and e.player_id then
      LMenu.close(e.player_id)
    end
  end)

  Net:on("area_transfer", function(e)
    if e and e.player_id then
      LMenu.close(e.player_id)
    end
  end)
end

return LMenu
