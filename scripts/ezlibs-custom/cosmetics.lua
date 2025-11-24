-- /server/scripts/ezlibs-custom/cosmetics.lua
-- Cosmetics submenu + preview (called from LMenu)

local Cosmetics = {}
_G.Cosmetics = Cosmetics -- optional global convenience

-- ---------------------------------------------------------------------------
-- net-games framework
-- ---------------------------------------------------------------------------

local frame_ok, frame = pcall(require, "scripts/net-games/framework")
if not frame_ok or not frame then
  print("[Cosmetics] ERROR: failed to require scripts/net-games/framework; cosmetics submenu disabled.")
  return Cosmetics
end

-- Displayer init (copy of LMenu’s logic)
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
    print("[Cosmetics] WARNING: Displayer failed to init:", tostring(err))
    Displayer = nil
  end
end

if not Displayer then
  print("[Cosmetics] WARNING: Displayer not available; cosmetics text will be disabled.")
end

-- ---------------------------------------------------------------------------
-- Logging
-- ---------------------------------------------------------------------------

local helpers_ok, helpers = pcall(require, "scripts/ezlibs-scripts/helpers")

local function log(...)
  if helpers_ok and helpers and type(helpers.info) == "function" then
    helpers.info("[Cosmetics]", ...)
  else
    local parts = { "[Cosmetics]" }
    for i = 1, select("#", ...) do
      parts[#parts+1] = tostring(select(i, ...))
    end
    print(table.concat(parts, " "))
  end
end

local function warn(...)
  if helpers_ok and helpers and type(helpers.warn) == "function" then
    helpers.warn("[Cosmetics][WARN]", ...)
  else
    local parts = { "[Cosmetics][WARN]" }
    for i = 1, select("#", ...) do
      parts[#parts+1] = tostring(select(i, ...))
    end
    print(table.concat(parts, " "))
  end
end

-- ---------------------------------------------------------------------------
-- Persistent unlocks (per-player, via ezmemory)
-- ---------------------------------------------------------------------------

local ezmemory_ok, ezmemory = pcall(require, "scripts/ezlibs-scripts/ezmemory")
if not ezmemory_ok or not ezmemory then
  warn("Failed to require scripts/ezlibs-scripts/ezmemory; cosmetics unlocks will not persist.")
end

local COSMETIC_MEM_KEY = "cosmetics_unlocked_v1"

local function cosmetic_pmem_get(pid)
  if not (ezmemory_ok and ezmemory and ezmemory.get_player_memory) then
    return nil, nil
  end

  local secret
  if helpers_ok and helpers and type(helpers.get_safe_player_secret) == "function" then
    secret = helpers.get_safe_player_secret(pid)
  else
    secret = pid
  end

  local pmem = ezmemory.get_player_memory(secret) or {}
  if type(pmem[COSMETIC_MEM_KEY]) ~= "table" then
    pmem[COSMETIC_MEM_KEY] = {}
    if ezmemory.set_player_memory then
      ezmemory.set_player_memory(secret, pmem)
    elseif ezmemory.save_player_memory then
      ezmemory.save_player_memory(secret, pmem)
    end
  end
  return pmem, secret
end

local function cosmetic_is_unlocked(pid, cosmetic_id)
  if not cosmetic_id or cosmetic_id == "" then return false end
  local pmem = cosmetic_pmem_get(pid)
  local bag  = pmem and pmem[COSMETIC_MEM_KEY] or nil
  return bag and bag[cosmetic_id] == true
end

local function cosmetic_set_unlocked(pid, cosmetic_id, value)
  if not cosmetic_id or cosmetic_id == "" then
    return false
  end
  local pmem, secret = cosmetic_pmem_get(pid)
  if not pmem then
    return false
  end
  if value then
    pmem[COSMETIC_MEM_KEY][cosmetic_id] = true
  else
    pmem[COSMETIC_MEM_KEY][cosmetic_id] = nil
  end

  if ezmemory.set_player_memory then
    ezmemory.set_player_memory(secret, pmem)
  elseif ezmemory.save_player_memory then
    ezmemory.save_player_memory(secret, pmem)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Config: menu asset, positions, text knobs, preview knobs, cosmetics blocks
-- ---------------------------------------------------------------------------

local config_ok, config = pcall(require, "scripts/cosmetic-config/config")
if not config_ok or not config then
  warn("Failed to require scripts/cosmetic-config/config; cosmetics submenu disabled.")
  return Cosmetics
end

local cfg            = config.cfg or {}
local cosmetics_defs = config.cosmetics or {}

-- Build OPTIONS from cosmetic blocks + placeholder tests
local OPTIONS = {}

for _, def in ipairs(cosmetics_defs) do
  table.insert(OPTIONS, {
    key            = def.key,
    name           = def.name,
    cosmetic_id    = def.id,
    texture        = def.texture,
    animation      = def.animation,
    anim_state     = def.anim_state,
    xforced        = def.xforced,
    yforced        = def.yforced,
    preview_start_x = def.preview_start_x,
    preview_start_y = def.preview_start_y,
    preview_sprite_id = def.preview_sprite_id,
    loop_duration   = def.loop_duration,
  })
end

-- Quick lookup by cosmetic_id (for shops, etc.)
local OPTIONS_BY_ID = {}
for _, opt in ipairs(OPTIONS) do
  if opt.cosmetic_id and opt.cosmetic_id ~= "" then
    OPTIONS_BY_ID[opt.cosmetic_id] = opt
  end
end

local VISIBLE_ROWS = 5

-- ---------------------------------------------------------------------------
-- IDs, per-player state
-- ---------------------------------------------------------------------------

local MENU_SPRITE_ID    = "cosmetics_menu_bg"
local WINDOW_SPRITE_ID  = "cosmetics_menu_window"  -- new: preview window
local TEXT_BASE_ID      = "cosmetics_menu_option_" -- text_id = TEXT_BASE_ID..index
local DEFAULT_PREVIEW_SPRITE_ID = "cosmetics_menu_preview_default"

local function preview_sprite_id_for_opt(opt)
  if opt and opt.preview_sprite_id and opt.preview_sprite_id ~= "" then
    return opt.preview_sprite_id
  end

  -- Fallback: build one from the key if you forget to set it
  if opt and opt.key then
    return "cosmetics_menu_preview_" .. tostring(opt.key)
  end

  return DEFAULT_PREVIEW_SPRITE_ID
end

-- state_by_pid[pid] = {
--   mode       = "menu" | "preview",
--   cursor     = 1..NUM_OPTIONS,
--   preview_x  = number,
--   preview_y  = number,
--   active_opt = OPTIONS[cursor] (during preview)
-- }
local state_by_pid = {}

-- Tracks what the player has equipped (future-proof)
-- equipped_by_pid[pid] = { [cosmetic_id] = true }
local equipped_by_pid = {}

local function current_equipped_id(pid)
  local t = equipped_by_pid[pid]
  if not t then return nil end

  -- We expect only one, but just in case, return the first true entry.
  for cosmetic_id, is_on in pairs(t) do
    if is_on then
      return cosmetic_id
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Owned / unlocked cosmetics per player (persistent via ezmemory)
-- ---------------------------------------------------------------------------

local function unlocked_options_for_player(pid)
  local opts = {}

  -- If ezmemory isn't available, treat all cosmetics as unlocked
  if not (ezmemory_ok and ezmemory and ezmemory.get_player_memory) then
    for _, opt in ipairs(OPTIONS) do
      if opt.cosmetic_id and opt.texture and opt.animation then
        opts[#opts+1] = opt
      end
    end
    return opts
  end

  local pmem = cosmetic_pmem_get(pid)
  local bag  = pmem and pmem[COSMETIC_MEM_KEY] or {}

  for _, opt in ipairs(OPTIONS) do
    local cid = opt.cosmetic_id
    if cid and cid ~= "" and bag[cid] then
      opts[#opts+1] = opt
    end
  end

  return opts
end

local function num_options_for_player(pid)
  local unlocked = unlocked_options_for_player(pid)
  local count    = #unlocked
  if count == 0 then
    return 1 -- single "Empty" placeholder row
  end
  return count
end

local function option_for_player_at(pid, index)
  local unlocked = unlocked_options_for_player(pid)
  return unlocked[index]
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function selection_state_for_cursor(row_index)
  if cfg.use_debug_selection then
    return "SELECTION_DEBUG"
  end
  if row_index < 1 then row_index = 1 end
  if row_index > VISIBLE_ROWS then row_index = VISIBLE_ROWS end
  return string.format("SELECTION_%d", row_index)
end

-- Map the absolute cursor (1..NUM_OPTIONS) to a row index (1..VISIBLE_ROWS)
local function current_row_index(st)
  if not st or not st.cursor then
    return 1
  end

  local top = st.top_index or 1
  local row = (st.cursor - top) + 1

  if row < 1 then row = 1 end
  if row > VISIBLE_ROWS then row = VISIBLE_ROWS end

  return row
end

local function clear_text_for_player(pid)
  -- Clear Text subsystem (for cosmetics list)
  if frame.remove_text then
    for i = 1, VISIBLE_ROWS do
      local text_id = TEXT_BASE_ID .. i
      pcall(frame.remove_text, text_id, pid)
    end
  end

  -- Clear Font subsystem (in case we ever switch over)
  if Displayer and Displayer.Font and Displayer.Font.eraseTextDisplay then
    for i = 1, VISIBLE_ROWS do
      local text_id = TEXT_BASE_ID .. i
      pcall(Displayer.Font.eraseTextDisplay, pid, text_id)
    end
  end
end

local function clear_menu_ui(pid)
  if frame.remove_ui_element then
    pcall(frame.remove_ui_element, MENU_SPRITE_ID, pid)
  end
  clear_text_for_player(pid)
end

local function clear_window_ui(pid)
  if frame.remove_ui_element then
    pcall(frame.remove_ui_element, WINDOW_SPRITE_ID, pid)
  end
end

local function clear_preview_ui(pid)
  if not frame.remove_ui_element then
    return
  end

  -- Remove all cosmetics' preview sprites for this player
  for _, opt in ipairs(OPTIONS) do
    local sid = preview_sprite_id_for_opt(opt)
    pcall(frame.remove_ui_element, sid, pid)
  end
end

local function draw_list_for_player(pid)
  if not frame.draw_text then
    warn("frame.draw_text not available; cosmetics list text will not be shown.")
    return
  end

  clear_text_for_player(pid)

  local st = state_by_pid[pid] or {}

  local list_x     = cfg.list_x       or cfg.menu_x or 0
  local list_y     = cfg.list_y       or cfg.menu_y or 0
  local spacing    = cfg.list_spacing or 22
  local list_z     = cfg.list_z       or 230
  local list_font  = cfg.list_font    or "THICK"
  local list_scale = cfg.list_scale   or 1.0

  local unlocked       = unlocked_options_for_player(pid)
  local unlocked_count = #unlocked
  local total          = (unlocked_count == 0) and 1 or unlocked_count

  -- Clamp cursor to 1..total
  if not st.cursor or st.cursor < 1 then
    st.cursor = 1
  elseif st.cursor > total then
    st.cursor = total
  end

  -- Clamp and persist top_index for this player
  local top     = st.top_index or 1
  local max_top = math.max(1, total - VISIBLE_ROWS + 1)

  if top < 1 then top = 1 end
  if top > max_top then top = max_top end
  st.top_index = top

  local bottom = math.min(total, top + VISIBLE_ROWS - 1)
  local row    = 1

  -- No cosmetics unlocked -> show single "Empty" line
  if unlocked_count == 0 then
    local text_id = TEXT_BASE_ID .. row
    local ok, err = pcall(
      frame.draw_text,
      text_id,
      pid,
      cfg.empty_label or "Empty",
      list_x,
      list_y,
      list_z,
      list_font,
      list_scale
    )

    if not ok then
      warn("draw_text failed for player", pid, "empty cosmetics:", tostring(err))
    end
    return
  end

  for idx = top, bottom do
    local opt   = unlocked[idx]
    local label = opt.name or ("Option" .. tostring(idx))
    local text_id = TEXT_BASE_ID .. row
    local ty      = list_y + (row - 1) * spacing
    local ok, err = pcall(
      frame.draw_text,
      text_id,
      pid,
      label,
      list_x,
      ty,
      list_z,
      list_font,
      list_scale
    )

    if not ok then
      warn("draw_text failed for player", pid, "option", idx, ":", tostring(err))
    end

    row = row + 1
  end
end

local function draw_menu(pid)
  local st = state_by_pid[pid]
  if not st or st.mode ~= "menu" then
    return
  end

  local texture = cfg.menu_texture
  local anim    = cfg.menu_animation

  if not texture or texture == "" or not anim or anim == "" then
    warn("Cosmetics menu assets not configured; cannot draw menu.")
    return
  end

  local row_index  = current_row_index(st)
  local anim_state = selection_state_for_cursor(row_index)
  local x          = cfg.menu_x     or 120
  local y          = cfg.menu_y     or 80
  local z          = cfg.menu_z     or 6
  local s          = cfg.menu_scale or 2.0

  frame.add_ui_element(
    MENU_SPRITE_ID,
    pid,
    texture,
    anim,
    anim_state,
    x, y, z,
    s, s
  )

  if frame.update_ui_position then
    frame.update_ui_position(MENU_SPRITE_ID, pid, x, y, z)
  end

  if frame.update_ui_element then
    pcall(frame.update_ui_element, MENU_SPRITE_ID, pid, { opacity = 255 })
  end

  draw_list_for_player(pid)
end

local function refresh_menu_cursor(pid)
  local st = state_by_pid[pid]
  if not st or st.mode ~= "menu" then
    return
  end

  local row_index  = current_row_index(st)
  local anim_state = selection_state_for_cursor(row_index)

  if frame.set_ui_animation then
    local ok, err = pcall(frame.set_ui_animation, MENU_SPRITE_ID, pid, anim_state)
    if not ok then
      warn("set_ui_animation failed for", pid, ":", tostring(err))
    end
  else
    draw_menu(pid)
  end

  draw_list_for_player(pid)
end

local function draw_window(pid)
  -- Cosmetic window uses the same texture/anim but a dedicated anim state
  local texture = cfg.window_texture
  local anim    = cfg.window_animation

  if not texture or texture == "" or not anim or anim == "" then
    return
  end

  local x = cfg.window_x     or 120
  local y = cfg.window_y     or 80
  local z = cfg.window_z     or (cfg.menu_z or 6)
  local s = cfg.window_scale or (cfg.menu_scale or 2.0)

  -- Always remove any previous window sprite for this player
  if frame.remove_ui_element then
    pcall(frame.remove_ui_element, WINDOW_SPRITE_ID, pid)
  end

  frame.add_ui_element(
    WINDOW_SPRITE_ID,
    pid,
    texture,
    anim,
    "COSMETIC_WINDOW",
    x, y, z,
    s, s
  )

  if frame.update_ui_position then
    frame.update_ui_position(WINDOW_SPRITE_ID, pid, x, y, z)
  end

  if frame.update_ui_element then
    pcall(frame.update_ui_element, WINDOW_SPRITE_ID, pid, { opacity = 255 })
  end
end

local function draw_preview(pid)
  local st = state_by_pid[pid]
  if not st or st.mode ~= "preview" then
    return
  end

  local opt = st.active_opt
  if not opt then
    warn("draw_preview called with no active_opt; aborting.")
    return
  end

  local texture = opt.texture
  local anim    = opt.animation
  local state   = opt.anim_state or "SNOWFLAKE_PARTICLE"

  if not texture or texture == "" or not anim or anim == "" then
    warn("Cosmetic preview requested but cosmetic assets not configured.")
    return
  end

  local base_x = cfg.preview_base_x or 120
  local base_y = cfg.preview_base_y or 80

  local x = base_x + (st.preview_x or 0)
  local y = base_y + (st.preview_y or 0)
  local z = cfg.preview_z     or cfg.menu_z or 6
  local s = cfg.preview_scale or 2.0

  local sprite_id = preview_sprite_id_for_opt(opt)

  -- Clear this cosmetic's previous preview sprite for safety
  if frame.remove_ui_element then
    pcall(frame.remove_ui_element, sprite_id, pid)
  end

  frame.add_ui_element(
    sprite_id,
    pid,
    texture,
    anim,
    state,
    x, y, z,
    s, s
  )

  if frame.update_ui_position then
    frame.update_ui_position(sprite_id, pid, x, y, z)
  end
end

local function finalize_cosmetic_from_preview(pid)
  local st = state_by_pid[pid]
  if not st or st.mode ~= "preview" then
    return
  end

  local opt = st.active_opt
  if not opt then
    warn("finalize_cosmetic_from_preview called with no active_opt; aborting.")
    return
  end

  local cosmetic_id = opt.cosmetic_id
  local texture     = opt.texture
  local anim        = opt.animation
  local state       = opt.anim_state or "SNOWFLAKE_PARTICLE"

  if not (texture and anim and cosmetic_id)
    or texture == "" or anim == "" or cosmetic_id == "" then
    warn("Cosmetic finalize requested but cosmetic not configured.")
    return
  end

  if type(frame.set_cosmetic) ~= "function" then
    warn("frame.set_cosmetic not available; cannot apply cosmetic.")
    return
  end

  -- NEW: per-cosmetic base offsets (fall back to something sane)
  local base_xforced = opt.xforced or 27
  local base_yforced = opt.yforced or 0

  local x_offset = st.preview_x or 0
  local y_offset = st.preview_y or 0

  -- Pick per-cosmetic loop, fall back to config default, then 1.0
  local duration = opt.loop_duration

  local ok, err = pcall(
    frame.set_cosmetic,
    cosmetic_id,
    pid,
    texture,
    anim,
    state,
    x_offset + base_xforced,
    y_offset + base_yforced,
    true,          -- visible
    -base_xforced, -- player_xoffset (keeps sprite aligned with bot)
    -base_yforced, -- player_yoffset
    duration              -- anim_duration
  )

  if not ok then
    warn("set_cosmetic failed for", pid, ":", tostring(err))
    Net.message_player(pid, "(Failed to apply cosmetic; see server log.)")
    return
  end

  -- Single-slot: clear any previous cosmetic flags, then set the current one
  equipped_by_pid[pid] = equipped_by_pid[pid] or {}
  for id, _ in pairs(equipped_by_pid[pid]) do
    equipped_by_pid[pid][id] = nil
  end
  equipped_by_pid[pid][cosmetic_id] = true

  local label = opt.name or "Cosmetic"
  Net.message_player(pid, label .. " cosmetic applied.")

  -- Fully close cosmetics submenu (clears UI + unfreezes player)
  Cosmetics.close(pid)
end

local function cancel_preview_and_return_to_menu(pid)
  local st = state_by_pid[pid]
  if not st or st.mode ~= "preview" then
    return
  end

  clear_preview_ui(pid)
  clear_window_ui(pid)

  st.mode       = "menu"
  st.active_opt = nil

  draw_menu(pid)
end

-- ---------------------------------------------------------------------------
-- Public helpers for shops / debug
-- ---------------------------------------------------------------------------

function Cosmetics.has_cosmetic(pid, cosmetic_id)
  return cosmetic_is_unlocked(pid, cosmetic_id)
end

function Cosmetics.unlock_for_player(pid, cosmetic_id)
  if not cosmetic_id or cosmetic_id == "" then
    return false, "invalid_id"
  end
  if not OPTIONS_BY_ID[cosmetic_id] then
    return false, "unknown_id"
  end
  if cosmetic_is_unlocked(pid, cosmetic_id) then
    return false, "already_owned"
  end
  if not cosmetic_set_unlocked(pid, cosmetic_id, true) then
    return false, "no_memory"
  end
  return true
end

function Cosmetics.clear_all_for_player(pid)
  -- Wipe unlocks
  if ezmemory_ok and ezmemory and ezmemory.get_player_memory then
    local pmem, secret = cosmetic_pmem_get(pid)
    if pmem and pmem[COSMETIC_MEM_KEY] then
      pmem[COSMETIC_MEM_KEY] = {}
      if ezmemory.set_player_memory then
        ezmemory.set_player_memory(secret, pmem)
      elseif ezmemory.save_player_memory then
        ezmemory.save_player_memory(secret, pmem)
      end
    end
  end

  -- Also remove any equipped cosmetics for this player
  local t = equipped_by_pid[pid]
  if t then
    for cosmetic_id, _ in pairs(t) do
      if type(frame.remove_cosmetic) == "function" then
        pcall(frame.remove_cosmetic, cosmetic_id, pid)
      end
    end
    equipped_by_pid[pid] = nil
  end
end

function Cosmetics.get_name_for_id(cosmetic_id)
  local opt = OPTIONS_BY_ID[cosmetic_id]
  return opt and opt.name or nil
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function Cosmetics.is_open(pid)
  return state_by_pid[pid] ~= nil
end

function Cosmetics.is_in_preview(pid)
  local st = state_by_pid[pid]
  return st and st.mode == "preview"
end

function Cosmetics.open_menu(pid)
  -- Clean any stale UI/state but keep player frozen (LMenu already did that)
  if state_by_pid[pid] then
    clear_menu_ui(pid)
    clear_preview_ui(pid)
    clear_window_ui(pid)
  end

  state_by_pid[pid] = {
    mode      = "menu",
    cursor    = 1,
    preview_x = cfg.preview_start_x or 0,
    preview_y = cfg.preview_start_y or -24,
    top_index = 1, -- first visible option in the window
  }

  draw_menu(pid)
  log("Opened Cosmetics menu for", pid)
end

-- If you ever want to close this from elsewhere:
--   Cosmetics.close(pid)           -> closes & unfreezes player
--   Cosmetics.close(pid, { keep_frozen = true }) -> closes but keeps freeze
function Cosmetics.close(pid, opts)
  local st = state_by_pid[pid]
  if not st then
    return
  end

  clear_menu_ui(pid)
  clear_preview_ui(pid)
  clear_window_ui(pid)

  state_by_pid[pid] = nil

  local keep_frozen = (type(opts) == "table" and opts.keep_frozen == true)
  if not keep_frozen and frame.unfreeze_player then
    local ok, err = pcall(frame.unfreeze_player, pid)
    if not ok then
      warn("unfreeze_player failed in Cosmetics.close for", pid, ":", tostring(err))
    end
  end

  log("Closed Cosmetics menu for", pid)
end

-- ---------------------------------------------------------------------------
-- Button handling
-- ---------------------------------------------------------------------------

local NAV_DEBOUNCE_SEC = 0.02

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

local function close_from_button(pid)
  -- Tell LMenu to ignore the *next* LS-open attempt for this player
  local LMenu = rawget(_G, "LMenu")
  if LMenu and LMenu._suppress_next_open then
    LMenu._suppress_next_open[pid] = true
  end

  Cosmetics.close(pid)
end

local function handle_menu_button(pid, btn)
  local st = state_by_pid[pid]
  if not st or st.mode ~= "menu" then
    return false
  end

  -- Up / Down navigation
  if btn == "U" or btn == "D" then
    local total = num_options_for_player(pid)

    -- If there is only 0 or 1 visible option ("Empty" or a single cosmetic),
    -- don't move the cursor at all.
    if total <= 1 then
      return true
    end

    if not nav_allowed(st, btn) then
      return true
    end

    -- Move cursor within 1..total (no wrap-around)
    if btn == "U" then
      if st.cursor and st.cursor > 1 then
        st.cursor = st.cursor - 1
      end
    else
      if not st.cursor then st.cursor = 1 end
      if st.cursor < total then
        st.cursor = st.cursor + 1
      end
    end

    -- Adjust top_index so the cursor stays within the visible window
    local top     = st.top_index or 1
    local max_top = math.max(1, total - VISIBLE_ROWS + 1)

    if st.cursor < top then
      top = st.cursor
    elseif st.cursor > (top + VISIBLE_ROWS - 1) then
      top = st.cursor - VISIBLE_ROWS + 1
    end

    if top < 1 then top = 1 end
    if top > max_top then top = max_top end
    st.top_index = top

    refresh_menu_cursor(pid)
    return true
  end

  -- Confirm selection
  if btn == "A" then
    local opt = option_for_player_at(pid, st.cursor or 1)
    if not opt then
      Cosmetics.close(pid)  -- this clears the UI and unfreezes the player
      Net.message_player(pid, "You don't have any cosmetics yet.")
      return true
    end

    -- Only handle real cosmetics (Snowflake, Confetti, etc.)
    if opt.cosmetic_id and opt.texture and opt.animation then
      local cosmetic_id = opt.cosmetic_id
      local current_id  = current_equipped_id(pid)

      -- CASE 1: selecting the SAME cosmetic you already have -> UNEQUIP + message + close
      if current_id == cosmetic_id then
        if type(frame.remove_cosmetic) == "function" then
          local ok2, err2 = pcall(frame.remove_cosmetic, cosmetic_id, pid)
          if not ok2 then
            warn("remove_cosmetic failed for", pid, ":", tostring(err2))
          end
        end

        if equipped_by_pid[pid] then
          equipped_by_pid[pid][cosmetic_id] = nil
          if next(equipped_by_pid[pid]) == nil then
            equipped_by_pid[pid] = nil
          end
        end

        -- Close submenu & unfreeze via Cosmetics.close, then show message
        Cosmetics.close(pid)
        local label = opt.name or "Cosmetic"
        Net.message_player(pid, label .. " cosmetic removed.")
        return true
      end

      -- CASE 2: selecting a DIFFERENT cosmetic while one is equipped -> swap silently
      if current_id then
        if type(frame.remove_cosmetic) == "function" then
          local ok2, err2 = pcall(frame.remove_cosmetic, current_id, pid)
          if not ok2 then
            warn("remove_cosmetic (swap) failed for", pid, ":", tostring(err2))
          end
        end

        if equipped_by_pid[pid] then
          equipped_by_pid[pid][current_id] = nil
          if next(equipped_by_pid[pid]) == nil then
            equipped_by_pid[pid] = nil
          end
        end
        -- No player message here (silent swap)
      end

      -- CASE 3: enter preview for the newly selected cosmetic

      -- Keep the cosmetics menu visible and spawn the small window + preview sprite.
      st.mode       = "preview"
      st.active_opt = opt
      st.preview_x  = opt.preview_start_x or cfg.preview_start_x
      st.preview_y  = opt.preview_start_y or cfg.preview_start_y

      draw_window(pid)
      draw_preview(pid)
    end

    return true
  end

  -- LS = close cosmetics menu entirely and unfreeze
  if btn == "LS" then
    close_from_button(pid)
    return true
  end

  return false
end

local function handle_preview_button(pid, btn)
  local st = state_by_pid[pid]
  if not st or st.mode ~= "preview" then
    return false
  end

  local step = cfg.preview_step or 2

  if btn == "U" then
    st.preview_y = (st.preview_y or 0) - step
    draw_preview(pid)
    return true
  elseif btn == "D" then
    st.preview_y = (st.preview_y or 0) + step
    draw_preview(pid)
    return true
  elseif btn == "L" then
    st.preview_x = (st.preview_x or 0) - step
    draw_preview(pid)
    return true
  elseif btn == "R" then
    st.preview_x = (st.preview_x or 0) + step
    draw_preview(pid)
    return true
  elseif btn == "A" then
    -- Confirm, apply cosmetic, and close + unfreeze.
    finalize_cosmetic_from_preview(pid)
    return true
  elseif btn == "LS" then
    -- Cancel preview, go back to submenu (still frozen).
    cancel_preview_and_return_to_menu(pid)
    return true
  end

  return false
end

if Net and Net.on then
  Net:on("button_press", function(event)
    local pid = event.player_id
    local btn = event.button

    local st = state_by_pid[pid]
    if not st then
      return -- Cosmetics submenu not active for this player
    end

    -- While Cosmetics is active, we fully consume inputs we care about.
    if st.mode == "preview" then
      if handle_preview_button(pid, btn) then
        return
      end
    elseif st.mode == "menu" then
      if handle_menu_button(pid, btn) then
        return
      end
    end
  end)

  -- Safety: auto-close on disconnect / area change
  Net:on("player_disconnect", function(e)
    if e and e.player_id then
      Cosmetics.close(e.player_id)
    end
  end)

  Net:on("area_transfer", function(e)
    if e and e.player_id then
      Cosmetics.close(e.player_id)
    end
  end)
end

return Cosmetics
