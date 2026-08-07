-- /server/scripts/ezlibs-custom/lobby.lua
-- Visual-only Lobby UI test (no matchmaking logic yet).
-- Interact with a map object of class/type "Lobby Maker" to open.
-- Uses /server/assets/ui/lobby/main.png + main.animation states.

local Lobby = {}
_G.Lobby = Lobby

-- ---------------------------------------------------------------------------
-- net-games framework (UI sprite wrapper)
-- ---------------------------------------------------------------------------
local frame_ok, frame = pcall(require, "scripts/net-games/main")
if not frame_ok or not frame then
  print("[lobby] ERROR: failed to require scripts/net-games/main; lobby UI disabled.")
  return Lobby
end

-- ---------------------------------------------------------------------------
-- Displayer for draw text
-- ---------------------------------------------------------------------------
local Displayer = _G.Displayer
if not Displayer then
  local ok, mod = pcall(require, "scripts/net-games/displayer/displayer")
  if ok and type(mod) == "table" then
    Displayer = mod
    _G.Displayer = mod
  end
end

if Displayer and Displayer.isValid and not Displayer:isValid() and Displayer.init then
  pcall(Displayer.init, Displayer)
end

-- ---------------------------------------------------------------------------
-- Sound effects (same global UI_SFX as LMenu)
-- ---------------------------------------------------------------------------

local UI_SFX = rawget(_G, "UI_SFX")
if type(UI_SFX) ~= "table" then
  UI_SFX = {}
  _G.UI_SFX = UI_SFX
end

UI_SFX.paths = UI_SFX.paths or {}
UI_SFX.paths.choose      = UI_SFX.paths.choose      or "/server/assets/sfx/card_choose.ogg"
UI_SFX.paths.select      = UI_SFX.paths.select      or "/server/assets/sfx/card_select.ogg"
UI_SFX.paths.cancel      = UI_SFX.paths.cancel      or "/server/assets/sfx/card_cancel.ogg"
UI_SFX.paths.error       = UI_SFX.paths.error       or "/server/assets/sfx/card_error.ogg"
UI_SFX.paths.screen_open = UI_SFX.paths.screen_open or "/server/assets/sfx/card_screen_open.ogg"

if type(UI_SFX.play) ~= "function" then
  function UI_SFX.play(pid, key)
    if not (Net and Net.play_sound_for_player) then return end
    local path = UI_SFX.paths and UI_SFX.paths[key]
    if not path then return end
    pcall(Net.play_sound_for_player, pid, path)
  end
end

local function play_sfx(pid, key)
  local UI = rawget(_G, "UI_SFX")
  if UI and type(UI.play) == "function" then
    pcall(UI.play, pid, key)
  end
end

-- ---------------------------------------------------------------------------
-- Async helpers (for 1s join animation delay)
-- ---------------------------------------------------------------------------
local Async = rawget(_G, "Async")

local function async(p)
  if not Async or not Async.promisify then
    local ok, err = pcall(p)
    if not ok then print("[lobby] async error:", err) end
    return nil
  end
  local co = coroutine.create(p)
  return Async.promisify(co)
end

local function await(v)
  if not Async or not Async.await then return nil end
  return Async.await(v)
end

local function sleep(sec)
  if not Async or not Async.sleep then return nil end
  return await(Async.sleep(sec))
end

-- ---------------------------------------------------------------------------
-- Config (tweak these positions freely)
-- ---------------------------------------------------------------------------
local SCREEN_W, SCREEN_H = 240, 160

local cfg = {
  texture = "/server/assets/ui/lobby/main.png",
  anim    = "/server/assets/ui/lobby/main.animation",
  scale   = 2,

  z_bg    = 5,
  z_ui    = 6,
  z_text  = 230,

  -- random button (w=38, h=12 per main.animation)
  random_y = 22,
  random_x = math.floor((SCREEN_W - 38) / 2),

  -- lobby rows (w=207, h=21 per main.animation)
  lobby_x = math.floor((SCREEN_W - 207) / 2),
  lobby_y0 = 45,         -- first row y
  lobby_row_step = 28,   -- 21px row height + ~3px gap

  -- wait box (w=118, h=14 per main.animation)
  wait_y = 135,
  wait_x = math.floor((SCREEN_W - 118) / 2),

  -- text inside lobby row
  lobby_text_x_pad = 60,
  lobby_text_y_pad = 6,
  lobby_font       = "THICK",
  lobby_font_scale = 2.0,
  -- minimize hint (only shown for minimizable activities)
  hint_text  = "Press Start = Minimize",
  hint_font  = "THICK",
  hint_scale = 1.0,
  hint_x     = 152,  -- tweak to move right/left
  hint_y     = 149,  -- tweak to move up/down
}

local function provide_lobby_assets(pid)
  if not (Net and Net.provide_asset_for_player) then
    return
  end

  pcall(Net.provide_asset_for_player, pid, cfg.texture)
  pcall(Net.provide_asset_for_player, pid, cfg.anim)
end

-- ---------------------------------------------------------------------------
-- Host / Join (lobby-main) layout
-- ---------------------------------------------------------------------------
cfg.room_btn_y = 17

-- Host buttons (Start / Kick / Cancel)
cfg.host_btn_start_x  = 47
cfg.host_btn_kick_x   = 112
cfg.host_btn_cancel_x = 167

-- Join buttons (Ready / Leave)
cfg.join_btn_ready_x = 78
cfg.join_btn_leave_x = 138

-- Owner box
cfg.owner_box_x = math.floor((SCREEN_W - 207) / 2)
cfg.owner_box_y = 30

-- Text inside owner box + member list
cfg.owner_text_x = cfg.owner_box_x + 60
cfg.owner_text_y = cfg.owner_box_y + 6

cfg.member_x    = 99
cfg.member_y0   = 65
cfg.member_step = 20

-- Name cursor wrapper
cfg.name_cursor_x = math.floor((SCREEN_W - 223) / 2)
cfg.name_cursor_y_pad = -6

-- ---------------------------------------------------------------------------
-- Per-player state
-- ---------------------------------------------------------------------------
local st_by_pid = {}

-- ---------------------------------------------------------------------------
-- Lobby core registries
-- ---------------------------------------------------------------------------
local activities = {}              -- activity_id -> cfg
local lobbies_by_activity = {}     -- activity_id -> { lobby_id, lobby_id, ... } (max 3)
local lobbies = {}                 -- lobby_id -> lobby object
local pid_active_activity = {}     -- pid -> activity_id (enforce 1 queue state)
local pid_lobby = {}               -- pid -> lobby_id (if in a lobby)
local lobby_seq = 0

local function is_open(pid)
  return st_by_pid[pid] ~= nil
end
Lobby.is_open = is_open

function Lobby.is_open_for(pid)
  local st = st_by_pid[pid]
  return st ~= nil and st.ui_visible == true
end
rawset(_G, "lobby_ui_is_open", Lobby.is_open_for)


-- ---------------------------------------------------------------------------
-- Forward declaring a few functions
-- ---------------------------------------------------------------------------
local draw_join_ui
local draw_ui
local draw_host_ui
local draw_minimize_hint
local ensure_activity

-- ---------------------------------------------------------------------------
-- Safe UI wrappers (net-games forks differ slightly)
-- ---------------------------------------------------------------------------
local function safe_add(sprite_id, pid, state, x, y, z)
  if not (frame and frame.add_ui_element) then return end

  pcall(frame.add_ui_element,
    sprite_id,
    pid,
    cfg.texture,
    cfg.anim,
    state,
    x, y, z,
    cfg.scale, cfg.scale
  )

  if frame.update_ui_position then
    pcall(frame.update_ui_position, sprite_id, pid, x, y, z)
  end

  if frame.set_ui_animation then
    pcall(frame.set_ui_animation, sprite_id, pid, state)
  end

  if frame.update_ui_element then
    pcall(frame.update_ui_element, sprite_id, pid, { opacity = 255 })
  end
end

local function safe_remove(sprite_id, pid)
  if frame and frame.remove_ui_element then
    pcall(frame.remove_ui_element, sprite_id, pid)
  end
end

local function safe_set_state(sprite_id, pid, state)
  if frame and frame.set_ui_animation then
    return pcall(frame.set_ui_animation, sprite_id, pid, state)
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Text helpers (copied in spirit from cards.lua)
-- ---------------------------------------------------------------------------
local function ensure_fonts(pid)
  if Displayer and Displayer._subsystems and Displayer._subsystems.FontSystem then
    local fs = Displayer._subsystems.FontSystem
    if fs.player_fonts and not fs.player_fonts[pid] and fs.setupPlayerFonts then
      pcall(fs.setupPlayerFonts, fs, pid)
    end
    if fs.player_fonts and fs.player_fonts[pid] then
      return true
    end
  end

  if Displayer and Displayer.Font and Displayer.Font.loadTextureForPlayer then
    if pcall(Displayer.Font.loadTextureForPlayer, pid) then return true end
    if pcall(Displayer.Font.loadTextureForPlayer, Displayer.Font, pid) then return true end
  end

  return false
end

local function erase_text(pid, id)
  if Displayer and Displayer.Font and Displayer.Font.eraseTextDisplay then
    if not pcall(Displayer.Font.eraseTextDisplay, pid, id) then
      pcall(Displayer.Font.eraseTextDisplay, Displayer.Font, pid, id)
    end
  end
end

local function draw_text(pid, text, x, y, font, scale, z, id)
  if not (Displayer and Displayer.Font and Displayer.Font.drawTextWithId) then return end

  -- Displayer uses "screen pixels" where 1 logical unit = 2 pixels.
  local sx = math.floor((x or 0) * 2)
  local sy = math.floor((y or 0) * 2)

  local ok = pcall(Displayer.Font.drawTextWithId, pid, text, sx, sy, font, scale, z, id)
  if not ok then
    pcall(Displayer.Font.drawTextWithId, Displayer.Font, pid, text, sx, sy, font, scale, z, id)
  end
end

-- ---------------------------------------------------------------------------
-- Sprite IDs
-- ---------------------------------------------------------------------------
local SID_MAIN   = "lobby_main"
local SID_RANDOM = "lobby_random"
local SID_WAIT   = "lobby_wait"
local function sid_row(i) return "lobby_row_" .. tostring(i) end
local function tid_row(i) return "lobby_row_text_" .. tostring(i) end
local SID_OWNER       = "lobby_owner"
local SID_NAME_CURSOR = "lobby_name_cursor"

local SID_BTN_START  = "lobby_btn_start"
local SID_BTN_KICK   = "lobby_btn_kick"
local SID_BTN_CANCEL = "lobby_btn_cancel"

local SID_BTN_READY  = "lobby_btn_ready"
local SID_BTN_LEAVE  = "lobby_btn_leave"

local TID_OWNER = "lobby_owner_text"
local function tid_member(i) return "lobby_member_text_" .. tostring(i) end
local TID_HINT = "lobby_minimize_hint"

-- ---------------------------------------------------------------------------
-- Draw / Clear
-- ---------------------------------------------------------------------------
local function clear_ui(pid)
  -- main screen sprites
  safe_remove(SID_MAIN, pid)
  safe_remove(SID_RANDOM, pid)
  safe_remove(SID_WAIT, pid)
  for i = 1, 3 do
    safe_remove(sid_row(i), pid)
  end

  -- room sprites
  safe_remove(SID_OWNER, pid)
  safe_remove(SID_NAME_CURSOR, pid)

  safe_remove(SID_BTN_START, pid)
  safe_remove(SID_BTN_KICK, pid)
  safe_remove(SID_BTN_CANCEL, pid)

  safe_remove(SID_BTN_READY, pid)
  safe_remove(SID_BTN_LEAVE, pid)

  -- main screen text
  for i = 1, 3 do
    erase_text(pid, tid_row(i))
  end

  -- room text
  erase_text(pid, TID_OWNER)
  for i = 1, 4 do
    erase_text(pid, tid_member(i))
  end
  erase_text(pid, TID_HINT)
end

local function apply_cursor(pid)
  local st = st_by_pid[pid]
  if not st then return end

  -- ----------------------------
  -- MAIN LIST MODE
  -- ----------------------------
  if st.mode == "main" then
    local cur = st.cursor or 1

    -- Random waiting (only for random matchmaking)
    if st.waiting then
      safe_set_state(SID_WAIT, pid, "wait-loading")
      safe_set_state(SID_RANDOM, pid, "random-selected")
      for i = 1, 3 do safe_set_state(sid_row(i), pid, "lobby-unselected") end
      return
    end

    -- Joining animation (no wait-loading per your request)
    if st.busy and st.busy_kind == "joining" then
      safe_set_state(SID_WAIT, pid, "wait-idle")
      safe_set_state(SID_RANDOM, pid, "random-unselected")
      for i = 1, 3 do
        safe_set_state(sid_row(i), pid, (i == st.join_target) and "lobby-loading" or "lobby-unselected")
      end
      return
    end

    -- Browsing
    safe_set_state(SID_WAIT, pid, "wait-idle")
    safe_set_state(SID_RANDOM, pid, (cur == 1) and "random-selected" or "random-unselected")
    for i = 1, 3 do
      local idx = 1 + i
      safe_set_state(sid_row(i), pid, (cur == idx) and "lobby-selected" or "lobby-unselected")
    end
    return
  end

  -- ----------------------------
  -- HOST LOBBY MODE
  -- ----------------------------
  if st.mode == "host" then
    local b = st.btn_cursor or 1
    safe_set_state(SID_BTN_START,  pid, (b == 1) and "start-selected"  or "start-unselected")
    safe_set_state(SID_BTN_KICK,   pid, (b == 2) and "kick-selected"   or "kick-unselected")
    safe_set_state(SID_BTN_CANCEL, pid, (b == 3) and "cancel-selected" or "cancel-unselected")

    local n = st.name_cursor or 1
    local y = cfg.member_y0 + (n - 1) * cfg.member_step + cfg.name_cursor_y_pad
    safe_add(SID_NAME_CURSOR, pid, "name-cursor", cfg.name_cursor_x, y, cfg.z_ui)
    return
  end

  -- ----------------------------
  -- JOINED LOBBY MODE
  -- ----------------------------
  if st.mode == "join" then
    local b = st.btn_cursor or 1
    safe_set_state(SID_BTN_READY, pid, (b == 1) and "ready-selected" or "ready-unselected")
    safe_set_state(SID_BTN_LEAVE, pid, (b == 2) and "leave-selected" or "leave-unselected")
    safe_set_state(SID_WAIT, pid, st.ready and "wait-loading" or "wait-idle")
    return
  end
end

local function enter_main(pid)
  local st = st_by_pid[pid]; if not st then return end
  st.mode = "main"
  st.waiting = false
  st.busy = false
  st.busy_kind = nil
  st.join_target = nil

  clear_ui(pid)
  st.redraw_ticks = 8
  draw_ui(pid)
end

local function enter_host(pid)
  local st = st_by_pid[pid]; if not st then return end
  st.mode = "host"
  st.busy = false
  st.busy_kind = nil
  st.join_target = nil
  st.waiting = false
  st.redraw_ticks = 0

  st.btn_cursor = 1
  st.name_cursor = 1
  st.owner_name = Net.get_player_name(pid)
  st.members = { st.owner_name, "Test1", "Test2", "" }

  clear_ui(pid)
  draw_host_ui(pid)
  apply_cursor(pid)
end

local function enter_join(pid, owner_label)
  local st = st_by_pid[pid]; if not st then return end
  st.mode = "join"
  st.busy = false
  st.busy_kind = nil
  st.join_target = nil
  st.waiting = false
  st.redraw_ticks = 0

  st.btn_cursor = 1
  st.ready = false
  st.owner_name = owner_label
  local you = Net.get_player_name(pid)
  st.members = { owner_label, you, "", "" }

  clear_ui(pid)
  draw_join_ui(pid)
  apply_cursor(pid)
end

local function start_join_with_delay(pid, row) -- row 1..3
  local st = st_by_pid[pid]
  if not st or st.mode ~= "main" then return end
  if st.waiting or st.busy then return end

  -- NEW: resolve the lobby id from the current list rendering
  local lobby_id = (st.row_lobby_ids and st.row_lobby_ids[row]) or nil
  if not lobby_id then
    play_sfx(pid, "cancel")
    return
  end

  st.busy = true
  st.busy_kind = "joining"
  st.join_target = row
  st.redraw_ticks = 0
  st.join_token = (st.join_token or 0) + 1
  local token = st.join_token

  play_sfx(pid, "choose")
  apply_cursor(pid) -- shows lobby-loading

  async(function()
    sleep(0.6)

    local st2 = st_by_pid[pid]
    if not st2 or st2.mode ~= "main" then return end
    if not st2.busy or st2.busy_kind ~= "joining" then return end
    if st2.join_token ~= token then return end

    -- NEW: join the specific lobby_id we captured
    local join_fn = Lobby._join_lobby or Lobby.join_lobby
    if type(join_fn) ~= "function" then
      -- Fallback (shouldn't happen once core logic is in):
      play_sfx(pid, "cancel")
      st2.busy = false
      st2.busy_kind = nil
      st2.join_target = nil
      apply_cursor(pid)
      return
    end

    local lobby, err = join_fn(pid, lobby_id, { auto_ready = false })
    if not lobby then
      -- join failed (lobby closed/full/etc). Return to browsing.
      play_sfx(pid, "cancel")
      st2.busy = false
      st2.busy_kind = nil
      st2.join_target = nil
      apply_cursor(pid)
      return
    end

    -- Switch into join UI WITHOUT overwriting the synced lobby state
    local st3 = st_by_pid[pid]
    if not st3 then return end

    st3.mode = "join"
    st3.btn_cursor = 1
    st3.busy = false
    st3.busy_kind = nil
    st3.join_target = nil

    clear_ui(pid)
    draw_join_ui(pid)
    apply_cursor(pid)
  end)
end

local function abort_join(pid)
  local st = st_by_pid[pid]; if not st then return end
  if st.busy and st.busy_kind == "joining" then
    st.join_token = (st.join_token or 0) + 1
    st.busy = false
    st.busy_kind = nil
    st.join_target = nil
    apply_cursor(pid)
  end
end

function draw_ui(pid)
  ensure_fonts(pid)
  local st = st_by_pid[pid]
  local activity_id = st and st.activity_id or "debug"
  local lobby_ids = lobbies_by_activity[activity_id] or {}
  st.row_lobby_ids = {}

  -- main bg
  safe_add(SID_MAIN, pid, "main", 0, 0, cfg.z_bg)

  -- random button
  safe_add(SID_RANDOM, pid, "random-unselected", cfg.random_x, cfg.random_y, cfg.z_ui)

  -- lobby rows
  for i = 1, 3 do
    local y = cfg.lobby_y0 + (i - 1) * cfg.lobby_row_step
    safe_add(sid_row(i), pid, "lobby-unselected", cfg.lobby_x, y, cfg.z_ui)

    -- text label (visual test)
    local tx = cfg.lobby_x + cfg.lobby_text_x_pad
    local ty = y + cfg.lobby_text_y_pad
    local lobby_id = lobby_ids[i]
    st.row_lobby_ids[i] = lobby_id

    local label = ""
    if lobby_id and lobbies[lobby_id] then
      label = lobbies[lobby_id].owner_name or ""
    end

    if label ~= "" then
      draw_text(pid, label, tx, ty, cfg.lobby_font, cfg.lobby_font_scale, cfg.z_text, tid_row(i))
    else
      erase_text(pid, tid_row(i))
    end
  end

  -- wait indicator (use loading for now)
  safe_add(SID_WAIT, pid, "wait-idle", cfg.wait_x, cfg.wait_y, cfg.z_ui)
  draw_minimize_hint(pid, st)
  apply_cursor(pid)
end

local function draw_members(pid, st)
  for i = 1, 4 do
    local name = (st.members and st.members[i]) or ""
    if name ~= "" then
      local y = cfg.member_y0 + (i - 1) * cfg.member_step
      erase_text(pid, tid_member(i)) -- IMPORTANT: clears leftover pixels from longer previous text
      draw_text(pid, name, cfg.member_x, y, cfg.lobby_font, cfg.lobby_font_scale, cfg.z_text, tid_member(i))
    else
      erase_text(pid, tid_member(i))
    end
  end
end

local function draw_owner_box(pid, st)
  safe_add(SID_OWNER, pid, "lobby-owner", cfg.owner_box_x, cfg.owner_box_y, cfg.z_ui)
  draw_text(pid, st.owner_name or "", cfg.owner_text_x, cfg.owner_text_y,
            cfg.lobby_font, cfg.lobby_font_scale, cfg.z_text, TID_OWNER)
end

function draw_minimize_hint(pid, st)
  local activity_id = st and st.activity_id or nil
  local cfgA = activity_id and ensure_activity(activity_id) or nil

  if cfgA and cfgA.minimizable and st and st.ui_visible then
    ensure_fonts(pid)
    erase_text(pid, TID_HINT)
    draw_text(pid, cfg.hint_text, cfg.hint_x, cfg.hint_y, cfg.hint_font, cfg.hint_scale, cfg.z_text, TID_HINT)
  else
    erase_text(pid, TID_HINT)
  end
end

function draw_host_ui(pid)
  local st = st_by_pid[pid]; if not st then return end
  ensure_fonts(pid)

  safe_add(SID_MAIN, pid, "lobby-main", 0, 0, cfg.z_bg)

  safe_add(SID_BTN_START,  pid, "start-unselected",  cfg.host_btn_start_x,  cfg.room_btn_y, cfg.z_ui)
  safe_add(SID_BTN_KICK,   pid, "kick-unselected",   cfg.host_btn_kick_x,   cfg.room_btn_y, cfg.z_ui)
  safe_add(SID_BTN_CANCEL, pid, "cancel-unselected", cfg.host_btn_cancel_x, cfg.room_btn_y, cfg.z_ui)

  draw_owner_box(pid, st)
  draw_members(pid, st)

  -- name cursor (position is updated by apply_cursor)
  safe_add(SID_NAME_CURSOR, pid, "name-cursor", cfg.name_cursor_x, cfg.member_y0 + cfg.name_cursor_y_pad, cfg.z_ui)
  draw_minimize_hint(pid, st)
end

function draw_join_ui(pid)
  local st = st_by_pid[pid]; if not st then return end
  ensure_fonts(pid)

  safe_add(SID_MAIN, pid, "lobby-main", 0, 0, cfg.z_bg)

  safe_add(SID_BTN_READY, pid, "ready-unselected", cfg.join_btn_ready_x, cfg.room_btn_y, cfg.z_ui)
  safe_add(SID_BTN_LEAVE, pid, "leave-unselected", cfg.join_btn_leave_x, cfg.room_btn_y, cfg.z_ui)
  safe_add(SID_WAIT, pid, "wait-idle", cfg.wait_x, cfg.wait_y, cfg.z_ui)

  draw_owner_box(pid, st)
  draw_members(pid, st)
  draw_minimize_hint(pid, st)
end

-- ---------------------------------------------------------------------------
-- Lobby core: activities / lobbies / quickmatch / minimize
-- ---------------------------------------------------------------------------

local function now_s() return os.time() end

local function in_battle(pid)
  local ok, v
  if type(_G._battle_active) == "function" then
    ok, v = pcall(_G._battle_active, pid)
    if ok and v then return true end
  end
  local custom = rawget(_G, "custom")
  if type(custom) == "table" and type(custom.is_battle_open_for) == "function" then
    ok, v = pcall(custom.is_battle_open_for, pid)
    if ok and v then return true end
  end
  if Net and Net.is_player_in_battle then
    ok, v = pcall(Net.is_player_in_battle, pid)
    if ok and v then return true end
  end
  return false
end

function ensure_activity(activity_id)
  if not activities[activity_id] then
    activities[activity_id] = {
      id = activity_id,
      max_players = 2,
      minimizable = false,
      start = nil, -- function(players, lobby)
    }
  end
  lobbies_by_activity[activity_id] = lobbies_by_activity[activity_id] or {}
  return activities[activity_id]
end

function Lobby.register_activity(activity_id, cfg)
  if not activity_id or activity_id == "" then return false end
  cfg = cfg or {}
  local maxp = math.floor(tonumber(cfg.max_players) or 2)
  if maxp < 2 then maxp = 2 end
  if maxp > 4 then maxp = 4 end

  activities[activity_id] = {
    id = activity_id,
    max_players = maxp,
    minimizable = cfg.minimizable == true,
    start = cfg.start, -- function(players, lobby) -> true/false
  }
  lobbies_by_activity[activity_id] = lobbies_by_activity[activity_id] or {}
  return true
end

local function rebuild_member_strings(lobby)
  local out = {}
  for i, pid in ipairs(lobby.members) do
    local name = Net.get_player_name(pid) or "(?)"
    if lobby.ready[pid] then name = name .. " (Ready)" end
    out[i] = name
  end
  while #out < 4 do out[#out+1] = "" end
  return out
end

local function sync_room_ui(lobby)
  for _, pid in ipairs(lobby.members) do
    local st = st_by_pid[pid]
    if st and st.activity_id == lobby.activity_id then
      st.lobby_id   = lobby.id
      st.owner_name = lobby.owner_name
      st.members    = rebuild_member_strings(lobby)
      st.ready      = lobby.ready[pid] == true

      if st.ui_visible then
        -- Only draw room UI elements if the player is actually in a room screen.
        if st.mode == "host" or st.mode == "join" then
          draw_owner_box(pid, st)
          draw_members(pid, st)
        end
        -- Cursor/wait visuals are safe in any mode.
        apply_cursor(pid)
      end
    end
  end

  -- nudge main list viewers to refresh
  for pid, st in pairs(st_by_pid) do
    if st.activity_id == lobby.activity_id and st.ui_visible and st.mode == "main" then
      st.redraw_ticks = 2
    end
  end
end

local function go_main(pid, opts)
  local st = st_by_pid[pid]; if not st then return end
  opts = opts or {}

  st.mode = "main"
  st.busy = false
  st.busy_kind = nil
  st.join_target = nil
  st.btn_cursor = nil
  st.name_cursor = nil
  st.ready = false
  st.lobby_id = nil

  if not opts.keep_search then
    st.waiting = false
    st.search_state = nil
    st.search_token = (st.search_token or 0) + 1
  end

  if st.ui_visible then
    clear_ui(pid)
    st.redraw_ticks = 8
    draw_ui(pid)
  end
end

local function suspend_ui(pid)
  local st = st_by_pid[pid]; if not st then return false end
  if not st.ui_visible then return false end
  clear_ui(pid)
  st.ui_visible = false
  st.suspended_for_start = true
  if Net and Net.unlock_player_input then pcall(Net.unlock_player_input, pid) end
  return true
end

local function restore_ui(pid)
  local st = st_by_pid[pid]; if not st then return false end
  if st.ui_visible then return true end

  st.ui_visible = true
  st.suspended_for_start = false

  if Net and Net.lock_player_input then pcall(Net.lock_player_input, pid) end

  if st.mode == "main" then
    draw_ui(pid)
  elseif st.mode == "host" then
    draw_host_ui(pid)
    apply_cursor(pid)
  elseif st.mode == "join" then
    draw_join_ui(pid)
    apply_cursor(pid)
  end
  return true
end

function Lobby.minimize(pid)
  local st = st_by_pid[pid]
  if not st then return false end
  local cfgA = ensure_activity(st.activity_id)

  if not cfgA.minimizable then return false end
  if not st.ui_visible then return true end

  clear_ui(pid)
  st.ui_visible = false
  st.minimized = true
  if Net and Net.unlock_player_input then pcall(Net.unlock_player_input, pid) end
  return true
end

function Lobby.restore(pid)
  local st = st_by_pid[pid]
  if not st then return false end
  if st.ui_visible then return true end
  st.minimized = false
  return restore_ui(pid)
end

function Lobby.open_activity(pid, activity_id)
  if not pid then return false end
  provide_lobby_assets(pid)
  activity_id = tostring(activity_id or "debug")
  local cfgA = ensure_activity(activity_id)

  -- enforce 1 queue state
  local prev = pid_active_activity[pid]
  if prev and prev ~= activity_id and st_by_pid[pid] then
    Lobby.close(pid) -- closes old session
  end

  local st = st_by_pid[pid]
  if st and st.activity_id == activity_id then
    -- already have session: just restore if minimized
    if not st.ui_visible then
      return Lobby.restore(pid)
    end
    return true
  end

  st_by_pid[pid] = {
    activity_id = activity_id,
    ui_visible = true,
    minimized = false,

    mode = "main",
    cursor = 1,
    waiting = false,
    search_state = nil,
    search_token = 0,

    busy = false,
    busy_kind = nil,
    join_target = nil,
    redraw_ticks = 8,
    next_list_refresh = now_s() + 10,
  }
  pid_active_activity[pid] = activity_id

  if Net and Net.lock_player_input then pcall(Net.lock_player_input, pid) end
  draw_ui(pid)
  return true
end

function Lobby.has_session(pid, activity_id)
  local st = st_by_pid[pid]
  return st ~= nil and st.activity_id == tostring(activity_id)
end

-- keep old name for your Lobby Maker test object
function Lobby.open(pid)
  return Lobby.open_activity(pid, "debug")
end

local function close_lobby(lobby_id, reason)
  local lobby = lobbies[lobby_id]
  if not lobby then return end

  -- remove from activity list
  local list = lobbies_by_activity[lobby.activity_id] or {}
  for i = #list, 1, -1 do
    if list[i] == lobby_id then table.remove(list, i) end
  end

  -- kick everyone out (your rule C)
  local members = lobby.members or {}
  lobbies[lobby_id] = nil

  for _, pid in ipairs(members) do
    pid_lobby[pid] = nil
    local st = st_by_pid[pid]
    if st and st.activity_id == lobby.activity_id then
      st.lobby_id = nil
      st.ready = false

      -- If they were quickmatching, keep them searching; otherwise back to main
      if st.search_state == "random" and st.waiting then
        if st.ui_visible then apply_cursor(pid) end
      else
        go_main(pid, { keep_search = false })
      end
    end
  end
end

local function leave_lobby(pid, reason, opts)
  opts = opts or {}
  local lobby_id = pid_lobby[pid]
  if not lobby_id then return end

  local lobby = lobbies[lobby_id]
  if not lobby then
    pid_lobby[pid] = nil
    return
  end

  -- owner leaving closes lobby
  if pid == lobby.owner_pid then
    return close_lobby(lobby_id, reason or "owner_left")
  end

  -- remove member
  for i = #lobby.members, 1, -1 do
    if lobby.members[i] == pid then table.remove(lobby.members, i) end
  end
  lobby.ready[pid] = nil
  pid_lobby[pid] = nil

  sync_room_ui(lobby)

  -- return player to main; keep_search used for random fallback timeouts
  local st = st_by_pid[pid]
  if st and st.activity_id == lobby.activity_id then
    go_main(pid, { keep_search = opts.keep_search == true })
  end
end

local function kick_selected_from_host(owner_pid)
  local st = st_by_pid[owner_pid]
  if not st or st.mode ~= "host" then return end
  if not st.lobby_id then return end

  local lobby = lobbies[st.lobby_id]
  if not lobby or lobby.owner_pid ~= owner_pid then return end

  local idx = st.name_cursor or 1
  local target_pid = lobby.members[idx]

  -- Can't kick empty slots or yourself
  if (not target_pid) or target_pid == owner_pid then
    play_sfx(owner_pid, "cancel")
    return
  end

  -- If the target is a random-searcher hidden-joined player, keep them searching after kick
  local tgt = st_by_pid[target_pid]
  local keep_search = tgt and tgt.search_state == "random" and tgt.waiting == true

  play_sfx(target_pid, "cancel")
  leave_lobby(target_pid, "kicked", { keep_search = keep_search })

  -- Clamp cursor if it pointed past the new member count
  if (st.name_cursor or 1) > #lobby.members then
    st.name_cursor = math.max(1, #lobby.members)
  end

  play_sfx(owner_pid, "choose")
  apply_cursor(owner_pid)
end

local function create_lobby_for(pid)
  local st = st_by_pid[pid]; if not st then return nil, "no_session" end
  local act = ensure_activity(st.activity_id)
  local list = lobbies_by_activity[st.activity_id] or {}

  if #list >= 3 then return nil, "max_lobbies" end
  if pid_lobby[pid] then return nil, "already_in_lobby" end

  lobby_seq = lobby_seq + 1
  local lobby_id = st.activity_id .. ":" .. tostring(lobby_seq)

  local lobby = {
    id = lobby_id,
    activity_id = st.activity_id,
    owner_pid = pid,
    owner_name = Net.get_player_name(pid) or "(?)",
    members = { pid },
    ready = { [pid] = true },
    created_at = now_s(),
  }

  lobbies[lobby_id] = lobby
  table.insert(list, lobby_id)
  lobbies_by_activity[st.activity_id] = list
  pid_lobby[pid] = lobby_id

  return lobby
end

local function join_lobby(pid, lobby_id, opts)
  opts = opts or {}
  local st = st_by_pid[pid]; if not st then return nil, "no_session" end

  local lobby = lobbies[lobby_id]
  if not lobby then return nil, "missing" end
  if lobby.activity_id ~= st.activity_id then return nil, "wrong_activity" end

  local act = ensure_activity(lobby.activity_id)
  if #lobby.members >= act.max_players then return nil, "full" end

  -- if somehow in another lobby, leave it
  if pid_lobby[pid] then
    leave_lobby(pid, "switch_lobby", { keep_search = st.search_state == "random" })
  end

  table.insert(lobby.members, pid)
  lobby.ready[pid] = opts.auto_ready == true
  pid_lobby[pid] = lobby_id

  sync_room_ui(lobby)
  return lobby
end

Lobby._join_lobby = join_lobby
Lobby.join_lobby  = join_lobby

local function attempt_start(activity_id, players, lobby_obj)
  local cfgA = ensure_activity(activity_id)
  if type(cfgA.start) ~= "function" then
    for _, pid in ipairs(players) do
      play_sfx(pid, "cancel")
    end
    print("[lobby] no start function for activity:", tostring(activity_id))
    return false
  end

  -- basic eligibility check
  for _, pid in ipairs(players) do
    if in_battle(pid) then
      play_sfx(pid, "cancel")
      print("[lobby] can't start, player in battle:", tostring(pid))
      return false
    end
  end

  -- temporarily hide UI + unlock so the activity can control input/UI
  local suspended = {}
  for _, pid in ipairs(players) do
    if suspend_ui(pid) then suspended[#suspended+1] = pid end
  end

  local ok, ret = pcall(cfgA.start, players, lobby_obj)
  if ok and ret then
    -- success: end sessions + destroy lobby (if any)
    for _, pid in ipairs(players) do
      st_by_pid[pid] = nil
      pid_active_activity[pid] = nil
      pid_lobby[pid] = nil
    end
    if lobby_obj and lobby_obj.id and lobbies[lobby_obj.id] then
      close_lobby(lobby_obj.id, "started")
    end
    return true
  end

  -- failed: restore UI
  for _, pid in ipairs(players) do
    restore_ui(pid)
  end
  return false
end

local function try_autostart_lobby(lobby)
  local cfgA = ensure_activity(lobby.activity_id)

  -- Owner Start should work when:
  -- - at least 2 players
  -- - everyone currently in the lobby is ready
  if #lobby.members < 2 then return false end
  if #lobby.members > cfgA.max_players then return false end

  for _, pid in ipairs(lobby.members) do
    if not lobby.ready[pid] then return false end
  end

  -- stop any random loops for these players
  for _, pid in ipairs(lobby.members) do
    local st = st_by_pid[pid]
    if st and st.search_state == "random" then
      st.search_token = (st.search_token or 0) + 1
      st.search_state = nil
      st.waiting = false
    end
  end

  local players = { table.unpack(lobby.members) }
  return attempt_start(lobby.activity_id, players, lobby)
end

local function set_ready(pid, ready)
  local lobby_id = pid_lobby[pid]
  local lobby = lobby_id and lobbies[lobby_id] or nil
  if not lobby then return end

  lobby.ready[pid] = (ready == true)
  sync_room_ui(lobby)
  -- IMPORTANT: do NOT start here. Owner Start button controls starting.
end

local function find_random_partner(pid, activity_id)
  local cfgA = ensure_activity(activity_id)

  local candidates = {}
  for other, st in pairs(st_by_pid) do
    if other ~= pid
      and st.activity_id == activity_id
      and st.search_state == "random"
      and st.waiting
      and not in_battle(other)
    then
      candidates[#candidates + 1] = other
    end
  end

  if #candidates == 0 then return nil end

  if type(cfgA.pick_random_partner) == "function" then
    local ok, pick = pcall(cfgA.pick_random_partner, pid, candidates)
    if ok and pick then
      for _, c in ipairs(candidates) do
        if c == pick then return pick end
      end
    end
  end

  return candidates[1]
end

local function pick_open_lobby(activity_id)
  local list = lobbies_by_activity[activity_id] or {}
  local cfgA = ensure_activity(activity_id)

  local best_id, best_size = nil, -1
  for _, lid in ipairs(list) do
    local lobby = lobbies[lid]
    if lobby and #lobby.members < cfgA.max_players then
      if #lobby.members > best_size then
        best_id, best_size = lid, #lobby.members
      end
    end
  end
  return best_id
end

local function cancel_random(pid)
  local st = st_by_pid[pid]; if not st then return end
  if st.search_state == "random" then
    st.search_token = (st.search_token or 0) + 1
    st.search_state = nil
    st.waiting = false
    if pid_lobby[pid] then
      leave_lobby(pid, "random_cancel", { keep_search = false })
    end
    if st.ui_visible then apply_cursor(pid) end
  end
end

local function start_random(pid)
  local st = st_by_pid[pid]
  if not st or st.mode ~= "main" then return end
  if st.search_state == "random" then return end

  st.waiting = true
  st.search_state = "random"
  st.search_token = (st.search_token or 0) + 1
  local token = st.search_token
  local activity_id = st.activity_id

  if st.ui_visible then apply_cursor(pid) end

  async(function()
    while true do
      local st2 = st_by_pid[pid]
      if not st2 or st2.search_state ~= "random" or st2.search_token ~= token then return end

      -- seek for up to 10 seconds (check every second)
      for _ = 1, 10 do
        local st3 = st_by_pid[pid]
        if not st3 or st3.search_state ~= "random" or st3.search_token ~= token then return end

        local other = find_random_partner(pid, activity_id)
        if other then
          -- stop both searches
          local os = st_by_pid[other]
          if os and os.search_state == "random" then
            os.search_token = (os.search_token or 0) + 1
            os.search_state = nil
            os.waiting = false
            if os.ui_visible then apply_cursor(other) end
          end
          st3.search_state = nil
          st3.waiting = false

          local players = { pid, other }
          attempt_start(activity_id, players, { id = "random", activity_id = activity_id })
          return
        end

        sleep(1.0)
      end

      -- fallback: join an open lobby (hidden), auto-ready
      local lid = pick_open_lobby(activity_id)
      if lid then
        join_lobby(pid, lid, { auto_ready = true })
        -- wait 10 seconds for autostart; if not started, leave and loop again
        for _ = 1, 10 do
          local st4 = st_by_pid[pid]
          if not st4 or st4.search_state ~= "random" or st4.search_token ~= token then return end
          if pid_lobby[pid] ~= lid then break end -- started or kicked
          sleep(1.0)
        end
        if pid_lobby[pid] == lid then
          leave_lobby(pid, "random_timeout", { keep_search = true })
          -- keep searching
          local st5 = st_by_pid[pid]
          if st5 then
            st5.waiting = true
            st5.search_state = "random"
            if st5.ui_visible then apply_cursor(pid) end
          end
        end
      end
    end
  end)
end

Lobby.start_random  = start_random
Lobby.cancel_random = cancel_random

-- ---------------------------------------------------------------------------
-- Public surface
-- ---------------------------------------------------------------------------

function Lobby.close(pid)
  local st = st_by_pid[pid]
  if not st then return end

  cancel_random(pid)

  if pid_lobby[pid] then
    leave_lobby(pid, "ui_close", { keep_search = false })
  end

  clear_ui(pid)
  st_by_pid[pid] = nil
  pid_active_activity[pid] = nil
  pid_lobby[pid] = nil

  if Net and Net.unlock_player_input then pcall(Net.unlock_player_input, pid) end
end

-- ---------------------------------------------------------------------------
-- Object interaction (Lobby Maker opens debug activity)
-- ---------------------------------------------------------------------------
local function get_obj(area_id, object_id)
  local ok, obj = pcall(Net.get_object_by_id, area_id, object_id)
  if not ok then return nil end
  return obj
end

Net:on("object_interaction", function(event)
  if event.button ~= 0 then return end -- A only
  local pid = event.player_id
  local area_id = Net.get_player_area(pid)
  local obj = get_obj(area_id, event.object_id)
  if not obj then return end

  if (obj.class ~= "Lobby Maker" and obj.type ~= "Lobby Maker") then
    return
  end

  Lobby.open_activity(pid, "debug")
  play_sfx(pid, "screen_open")
end)

-- ---------------------------------------------------------------------------
-- Input handling while open (virtual_input)
-- ---------------------------------------------------------------------------
local function is_left(name)  return name == "Move Left"  or name == "Left"  end
local function is_right(name) return name == "Move Right" or name == "Right" end

Net:on("virtual_input", function(event)
  local pid = event.player_id
  local st = st_by_pid[pid]
  if not st or not st.ui_visible then return end
  if not event.events then return end

  local cfgA = ensure_activity(st.activity_id)

  for _, b in next, event.events do
    local name  = b.name
    local state = b.state
    if state ~= 1 then goto continue end

    -- Shoulder L = manual refresh
    if name == "Shoulder L" or name == "LS" then
      if st.mode == "main" then
        play_sfx(pid, "choose")
        st.redraw_ticks = 4
        draw_ui(pid)
      end
      return
    end

    -- Shoulder R = create lobby
    if name == "Shoulder R" then
      if st.mode == "main" and not st.waiting and not st.busy then
        local lobby, err = create_lobby_for(pid)
        if not lobby then
          play_sfx(pid, "cancel")
          if Net and Net.message_player and err == "max_lobbies" then
            pcall(Net.message_player, pid, "[Lobby] Max 3 lobbies already open.")
          end
          return
        end

        st.mode = "host"
        st.btn_cursor = 1
        st.name_cursor = 1
        st.lobby_id = lobby.id
        st.owner_name = lobby.owner_name
        st.members = rebuild_member_strings(lobby)

        play_sfx(pid, "choose")
        clear_ui(pid)
        draw_host_ui(pid)
        apply_cursor(pid)
      end
      return
    end

    -- Pause (Start) = minimize (if activity allows it) from ANY screen
    if name == "Pause" and cfgA.minimizable then
      play_sfx(pid, "cancel")
      Lobby.minimize(pid)
      return
    end

    -- Cancel/back/pause
    if name == "Cancel" or name == "Back" or (name == "Pause" and not cfgA.minimizable) then
      -- joining animation abort
      if st.busy and st.busy_kind == "joining" then
        play_sfx(pid, "cancel")
        abort_join(pid)
        return
      end

      -- random quickmatch cancel
      if st.search_state == "random" and st.waiting then
        play_sfx(pid, "cancel")
        cancel_random(pid)
        apply_cursor(pid)
        return
      end

      -- join mode: first cancel unready, second cancel leaves
      if st.mode == "join" and (name == "Cancel" or name == "Back") and st.ready then
        play_sfx(pid, "cancel")
        st.ready = false
        set_ready(pid, false)
        return
      end

      -- host/join -> return to main (and close lobby if you were owner)
      if st.mode == "host" and st.lobby_id then
        play_sfx(pid, "cancel")
        close_lobby(st.lobby_id, "owner_cancel")
        go_main(pid, { keep_search = false })
        return
      end

      if st.mode == "join" and st.lobby_id then
        play_sfx(pid, "cancel")
        leave_lobby(pid, "leave", { keep_search = false })
        return
      end

      -- main -> close UI
      play_sfx(pid, "cancel")
      Lobby.close(pid)
      return
    end

    -- ----------------------------
    -- MAIN MODE
    -- ----------------------------
    if st.mode == "main" then
      if st.waiting or st.busy then goto continue end

      if name == "Move Up" then
        st.cursor = (st.cursor or 1) - 1
        if st.cursor < 1 then st.cursor = 4 end
        play_sfx(pid, "select")
        apply_cursor(pid)
        goto continue
      end

      if name == "Move Down" then
        st.cursor = (st.cursor or 1) + 1
        if st.cursor > 4 then st.cursor = 1 end
        play_sfx(pid, "select")
        apply_cursor(pid)
        goto continue
      end

      if name == "Confirm" or name == "OK" then
        if st.cursor == 1 then
          play_sfx(pid, "choose")
          start_random(pid)
        else
          local row = st.cursor - 1 -- 1..3
          local lobby_id = st.row_lobby_ids and st.row_lobby_ids[row] or nil
          if not lobby_id then
            play_sfx(pid, "cancel")
            return
          end
          start_join_with_delay(pid, row) -- keep your existing 0.6–1s anim; it will use row->lobby_id now via draw_ui()
        end
        return
      end
    end

    -- ----------------------------
    -- HOST MODE
    -- ----------------------------
    if st.mode == "host" then
      if is_left(name) then
        st.btn_cursor = (st.btn_cursor or 1) - 1
        if st.btn_cursor < 1 then st.btn_cursor = 3 end
        play_sfx(pid, "select")
        apply_cursor(pid)
        return
      end

      if is_right(name) then
        st.btn_cursor = (st.btn_cursor or 1) + 1
        if st.btn_cursor > 3 then st.btn_cursor = 1 end
        play_sfx(pid, "select")
        apply_cursor(pid)
        return
      end

      if name == "Move Up" then
        st.name_cursor = (st.name_cursor or 1) - 1
        if st.name_cursor < 1 then st.name_cursor = 4 end
        play_sfx(pid, "select")
        apply_cursor(pid)
        return
      end

      if name == "Move Down" then
        st.name_cursor = (st.name_cursor or 1) + 1
        if st.name_cursor > 4 then st.name_cursor = 1 end
        play_sfx(pid, "select")
        apply_cursor(pid)
        return
      end

      if name == "Confirm" or name == "OK" then
        play_sfx(pid, "choose")

        -- Start
        if (st.btn_cursor or 1) == 1 and st.lobby_id and lobbies[st.lobby_id] then
          local ok = try_autostart_lobby(lobbies[st.lobby_id])
          if not ok then
            play_sfx(pid, "error")
          else
            play_sfx(pid, "choose")
          end
          return
        end

        -- Kick
        if (st.btn_cursor or 1) == 2 then
          kick_selected_from_host(pid)
          return
        end

        -- Cancel
        if (st.btn_cursor or 1) == 3 and st.lobby_id then
          close_lobby(st.lobby_id, "owner_cancel")
          go_main(pid, { keep_search = false })
          return
        end
      end
    end

    -- ----------------------------
    -- JOIN MODE
    -- ----------------------------
    if st.mode == "join" then
      if is_left(name) or is_right(name) then
        st.btn_cursor = (st.btn_cursor or 1) == 1 and 2 or 1
        play_sfx(pid, "select")
        apply_cursor(pid)
        return
      end

      if name == "Confirm" or name == "OK" then
        if (st.btn_cursor or 1) == 1 then
          st.ready = not st.ready
          play_sfx(pid, "choose")
          set_ready(pid, st.ready)
        else
          play_sfx(pid, "cancel")
          leave_lobby(pid, "leave", { keep_search = false })
        end
        return
      end
    end

    ::continue::
  end
end)

-- ---------------------------------------------------------------------------
-- Preload shared lobby UI assets
-- ---------------------------------------------------------------------------
Net:on("player_join", function(event)
  if not event or not event.player_id then
    return
  end

  provide_lobby_assets(event.player_id)
end)

-- ---------------------------------------------------------------------------
-- Cleanup on disconnect / transfer
-- ---------------------------------------------------------------------------
Net:on("player_disconnect", function(e)
  local pid = e.player_id
  if pid_lobby[pid] then
    close_lobby(pid_lobby[pid], "disconnect")
  end
  if st_by_pid[pid] then
    clear_ui(pid)
    st_by_pid[pid] = nil
    pid_active_activity[pid] = nil
    pid_lobby[pid] = nil
  end
end)

Net:on("player_area_transfer", function(e)
  local pid = e.player_id
  if st_by_pid[pid] then
    Lobby.close(pid)
  end
end)

-- ---------------------------------------------------------------------------
-- Tick: redraw reliability + list refresh every 10 seconds
-- ---------------------------------------------------------------------------
Net:on("tick", function()
  local t = now_s()
  for pid, st in pairs(st_by_pid) do
    if st.ui_visible and st.mode == "main" then
      if st.next_list_refresh and t >= st.next_list_refresh then
        st.next_list_refresh = t + 10
        st.redraw_ticks = 2
      end
    end

    if st.ui_visible and st.mode == "main" and st.redraw_ticks and st.redraw_ticks > 0 then
      if not st.busy then draw_ui(pid) end
      st.redraw_ticks = st.redraw_ticks - 1
    end
  end
end)

return Lobby
