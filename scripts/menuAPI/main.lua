-- /server/scripts/menuAPI/main.lua
-- MenuAPI Type 1
--
-- Type 1: title + cursor + selectable rows + vertical scrolling.
-- Designed to be opened from LMenu or directly by another script.

local MenuAPI = {}
_G.MenuAPI = MenuAPI

-- ---------------------------------------------------------------------------
-- net-games framework
-- ---------------------------------------------------------------------------

local frame_ok, frame = pcall(require, "scripts/net-games/main")
if not frame_ok or not frame then
  print("[MenuAPI] ERROR: failed to require scripts/net-games/main; MenuAPI disabled.")
  return MenuAPI
end

-- ---------------------------------------------------------------------------
-- Displayer / font helper
-- ---------------------------------------------------------------------------

local Displayer = rawget(_G, "Displayer")
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

local async = function(fn)
  local co = coroutine.create(fn)
  return Async.promisify(co)
end

local await = Async.await

-- ---------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------

local cfg = {
  -- Screen/logical coordinates are 0..240 x 0..160.
  -- net-games doubles x/y internally, so sprite scale 2 usually means
  -- the sprite texture pixel size maps nicely to logical UI units.

  title_tint = { r = 18, g = 42, b = 100, color_mode = 2 },
  row_tint   = { r = 95, g = 100, b = 108, color_mode = 2 },
  right_tint = { r = 95, g = 100, b = 108, color_mode = 2 },

  -- Menu Type 1 background: 142 x 126 px, anchor 0,0.
  menu1_texture = "/server/assets/ui/menuAPI/menu1.png",
  menu1_anim    = nil,
  menu1_state   = "",
  menu1_w       = 142,
  menu1_h       = 126,
  menu1_x       = 49, -- centered: (240 - 142) / 2
  menu1_y       = 17, -- centered: (160 - 126) / 2
  menu1_z       = 220,
  menu1_scale   = 2.0,

  -- Title position relative to menu background.
  title_x       = 17,
  title_y       = 1,
  title_z       = 225,
  title_font    = "THICK",
  title_scale   = 1.5,
  title_max_ch  = 18,
  title_id      = "menuapi_t1_title",

  -- Row text position relative to menu background.
  row_x         = 13,
  row_y         = 16,
  row_z         = 225,
  row_font      = "THICK",
  row_scale     = 1.5,
  row_advance   = 13,
  visible_rows  = 8,
  row_max_ch    = 20,
  row_text_id_base = "menuapi_t1_row_",

  -- Optional right-side small text, useful for progress like "2/3".
  -- Set row.right or row.value to draw it.
  right_x       = 103,
  right_z       = 225,
  right_font    = "THICK",
  right_scale   = 1.5,
  right_max_ch  = 5,
  right_text_id_base = "menuapi_t1_right_",
  show_right    = true,

  -- Cursor: 10 x 11 px, anchor 0,0, drawn left of row text.
  cursor_texture = "/server/assets/ui/menuAPI/cursor.png",
  cursor_anim    = nil,
  cursor_state   = "",
  cursor_x       = 1,
  cursor_y_offset = -2,
  cursor_z       = 226,
  cursor_scale   = 2.0,

  -- Scroll bar: 8 x 13 px, anchor 0,0.
  -- scroll_bottom_y is treated as the bottom of the track, so the bar's
  -- top y will stop at bottom - scroll_h.
  scroll_texture = "/server/assets/ui/menuAPI/scroll.png",
  scroll_anim    = nil,
  scroll_state   = "",
  scroll_x       = 131,
  scroll_top_y   = 11,
  scroll_bottom_y = 106,
  scroll_w       = 8,
  scroll_h       = 13,
  scroll_z       = 226,
  scroll_scale   = 2.0,

  -- Input behavior.
  nav_first_repeat_delay_sec = 1.0,
  nav_repeat_delay_sec       = 0.20,

  -- SFX keys use _G.UI_SFX when LMenu has already set it up.
  open_sfx   = "screen_open",
  move_sfx   = "select",
  choose_sfx = "choose",
  cancel_sfx = "cancel",
  error_sfx  = "error",

  -- Direct opens lock input by default. If opening from LMenu after
  -- LMenu.close(pid, { keep_frozen = true }), pass lock_input = false.
  lock_input_by_default = true,

  message_box_id = "menuapi_t1_message",

  message_x = 10,
  message_y = 260,
  message_w = 220,
  message_h = 56,
  message_font = "THIN_BLACK",
  -- Panel/backdrop scale. Keep this at 2.0 so the textbox panel stays normal size.
  message_scale = 2.02,

  -- Text-only scale. This requires the small text-display.lua patch below.
  message_text_scale = 1.8,
  message_z = 260,
  message_speed = 80,

  message_backdrop = {
    style = "textbox_panel",
    x = 0,
    y = 260,
    width = 360,
    height = 72,
    padding_x = 14,
    padding_y = -45,
    max_lines = 3,
    open_seconds = 0.12,
    close_seconds = 0.12,
  },

  -- Menu Type 2 background: 135 x 75 px, anchor 0,0.
  -- Put the asset here, or temporarily point this to menu1_texture while testing.
  menu2_texture = "/server/assets/ui/menuAPI/menu2.png",
  menu2_anim    = nil,
  menu2_state   = "",
  menu2_w       = 135,
  menu2_h       = 75,
  menu2_x       = 49,
  menu2_y       = 17,
  menu2_z       = 220,
  menu2_scale   = 2.0,

  menu2_title_x      = 17,
  menu2_title_y      = 1,
  menu2_title_max_ch = 18,

  menu2_row_x        = 13,
  menu2_row_y        = 16,
  menu2_row_advance  = 13,
  menu2_visible_rows = 4,
  menu2_row_max_ch   = 20,

}

MenuAPI.config = cfg

-- ---------------------------------------------------------------------------
-- Named tint palettes
-- ---------------------------------------------------------------------------
-- color_mode = 2 means Colorize.
-- Pass one of these with spec.color/spec.palette/spec.theme.
MenuAPI.tint_palettes = {
  default = {
    title_tint = { r = 18,  g = 42,  b = 100, color_mode = 2 },
    row_tint   = { r = 95,  g = 100, b = 108, color_mode = 2 },
    right_tint = { r = 95,  g = 100, b = 108, color_mode = 2 },
  },

  red = {
    title_tint = { r = 120, g = 20,  b = 24,  color_mode = 2 },
    row_tint   = { r = 128, g = 27,  b = 27,  color_mode = 2 },
    right_tint = { r = 120, g = 50,  b = 50,  color_mode = 2 },
  },

  blue = {
    title_tint = { r = 18,  g = 42,  b = 100, color_mode = 2 },
    row_tint   = { r = 70,  g = 90,  b = 125, color_mode = 2 },
    right_tint = { r = 65,  g = 85,  b = 120, color_mode = 2 },
  },

  green = {
    title_tint = { r = 20,  g = 95,  b = 55,  color_mode = 2 },
    row_tint   = { r = 65,  g = 105, b = 75,  color_mode = 2 },
    right_tint = { r = 55,  g = 115, b = 70,  color_mode = 2 },
  },

  gold = {
    title_tint = { r = 145, g = 95,  b = 20,  color_mode = 2 },
    row_tint   = { r = 115, g = 95,  b = 55,  color_mode = 2 },
    right_tint = { r = 135, g = 100, b = 35,  color_mode = 2 },
  },

  purple = {
    title_tint = { r = 95,  g = 40,  b = 125, color_mode = 2 },
    row_tint   = { r = 95,  g = 80,  b = 115, color_mode = 2 },
    right_tint = { r = 105, g = 75,  b = 125, color_mode = 2 },
  },

  gray = {
    title_tint = { r = 55,  g = 60,  b = 70,  color_mode = 2 },
    row_tint   = { r = 95,  g = 100, b = 108, color_mode = 2 },
    right_tint = { r = 95,  g = 100, b = 108, color_mode = 2 },
  },
}

function MenuAPI.get_palette(name)
  name = tostring(name or "default"):lower()
  return MenuAPI.tint_palettes[name] or MenuAPI.tint_palettes.default
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local state_by_pid = {}

-- state_by_pid[pid] = {
--   type = 1,
--   title = string,
--   rows = { { id=..., text=..., right=..., enabled=true, selectable=true } },
--   cursor = 1,
--   top_index = 1,
--   x = number,
--   y = number,
--   z = number,
--   lock_input = bool,
--   parent = string/table/function,
--   on_confirm = function(pid, row, st),
--   on_cancel = function(pid, st),
--   on_close = function(pid, st, reason),
-- }

-- ---------------------------------------------------------------------------
-- Logging / SFX
-- ---------------------------------------------------------------------------

local function log(...)
  local parts = { "[MenuAPI]" }
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  print(table.concat(parts, " "))
end

local function play_sfx(pid, key)
  local UI = rawget(_G, "UI_SFX")
  if UI and type(UI.play) == "function" then
    pcall(UI.play, pid, key)
    return
  end

  -- Fallback paths, in case LMenu has not initialized _G.UI_SFX yet.
  local fallback = {
    choose = "/server/assets/sfx/card_choose.ogg",
    select = "/server/assets/sfx/card_select.ogg",
    cancel = "/server/assets/sfx/card_cancel.ogg",
    error = "/server/assets/sfx/card_error.ogg",
    screen_open = "/server/assets/sfx/card_screen_open.ogg",
  }

  local path = fallback[key]
  if path and Net and Net.play_sound_for_player then
    pcall(Net.play_sound_for_player, pid, path)
  end
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function clamp(v, lo, hi)
  v = tonumber(v) or lo
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function str_trim(text)
  return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function truncate(text, max_ch)
  text = tostring(text or "")
  max_ch = tonumber(max_ch) or 20
  if #text <= max_ch then return text end
  if max_ch <= 3 then return text:sub(1, max_ch) end
  return text:sub(1, max_ch - 3) .. "..."
end

local function normalize_tint(tint)
  if type(tint) ~= "table" then return nil end

  local out = {
    r = tonumber(tint.r) or 255,
    g = tonumber(tint.g) or 255,
    b = tonumber(tint.b) or 255,
  }

  if tint.opacity ~= nil then
    out.opacity = tonumber(tint.opacity) or 255
  elseif tint.a ~= nil then
    out.opacity = tonumber(tint.a) or 255
  end

  if tint.color_mode ~= nil then
    out.color_mode = tonumber(tint.color_mode) or 0
  end

  return out
end

local function row_text(row)
  if type(row) ~= "table" then
    return tostring(row or "")
  end
  return tostring(row.text or row.label or row.title or row.name or row.id or "")
end

local function row_right(row)
  if type(row) ~= "table" then return "" end
  if row.show_right == false then return "" end

  local value = row.right
  if value == nil then value = row.value end
  if value == nil then value = row.count end

  if value == nil then return "" end
  return tostring(value)
end

local function row_selectable(row)
  if type(row) ~= "table" then return true end
  if row.selectable == false then return false end
  if row.enabled == false then return false end
  return true
end

local function normalize_rows(rows)
  local out = {}
  for i, row in ipairs(rows or {}) do
    if type(row) == "table" then
      local copy = {}
      for k, v in pairs(row) do
        copy[k] = v
      end
      copy.id = copy.id or tostring(i)
      out[#out + 1] = copy
    else
      out[#out + 1] = { id = tostring(i), text = tostring(row) }
    end
  end
  return out
end

local function first_selectable_index(rows)
  for i, row in ipairs(rows or {}) do
    if row_selectable(row) then
      return i
    end
  end
  return (#(rows or {}) > 0) and 1 or 0
end

local function nearest_selectable_index(rows, start_idx, dir)
  local count = #(rows or {})
  if count <= 0 then return 0 end

  start_idx = clamp(start_idx or 1, 1, count)
  dir = (dir and dir < 0) and -1 or 1

  if row_selectable(rows[start_idx]) then
    return start_idx
  end

  local i = start_idx
  for _ = 1, count do
    i = i + dir
    if i < 1 then i = count end
    if i > count then i = 1 end
    if row_selectable(rows[i]) then
      return i
    end
  end

  return start_idx
end

local function ensure_cursor_visible(st)
  local total = #(st.rows or {})
  local visible = tonumber(st.visible_rows) or cfg.visible_rows
  if total <= 0 then
    st.cursor = 0
    st.top_index = 1
    return
  end

  st.cursor = clamp(st.cursor or 1, 1, total)

  local max_top = math.max(1, total - visible + 1)
  local top = clamp(st.top_index or 1, 1, max_top)

  if st.cursor < top then
    top = st.cursor
  elseif st.cursor > top + visible - 1 then
    top = st.cursor - visible + 1
  end

  st.top_index = clamp(top, 1, max_top)
end

local function rel(st, x, y)
  return (st.x or cfg.menu1_x) + (x or 0), (st.y or cfg.menu1_y) + (y or 0)
end

local function sprite_id(pid, suffix, menu_type)
  local t = tonumber(menu_type or 1) or 1
  return "menuapi_t" .. tostring(t) .. "_" .. tostring(pid) .. "_" .. tostring(suffix)
end

local function opt_bool(value, default)
  if value == nil then
    return default
  end

  return value ~= false
end

-- ---------------------------------------------------------------------------
-- Safe UI wrappers
-- ---------------------------------------------------------------------------

local function safe_remove(sprite_id_value, pid)
  if frame and frame.remove_ui_element and sprite_id_value then
    pcall(frame.remove_ui_element, sprite_id_value, pid)
  end
end

local function safe_add(sprite_id_value, pid, texture, anim, state, x, y, z, sx, sy)
  if not (frame and frame.add_ui_element and sprite_id_value and texture and texture ~= "") then
    return false
  end

  local ok = pcall(
    frame.add_ui_element,
    sprite_id_value,
    pid,
    texture,
    anim,
    state or "",
    x or 0,
    y or 0,
    z or 0,
    sx or 2.0,
    sy or sx or 2.0
  )

  return ok
end

local function safe_move(sprite_id_value, pid, x, y, z)
  if not (frame and sprite_id_value) then return false end

  if type(frame.update_ui_position) == "function" then
    if pcall(frame.update_ui_position, sprite_id_value, pid, x, y, z) then
      return true
    end
  end

  if type(frame.update_ui_element) == "function" then
    local props = { x = x, y = y }
    if z ~= nil then props.z = z end
    return pcall(frame.update_ui_element, sprite_id_value, pid, props)
  end

  return false
end

-- ---------------------------------------------------------------------------
-- Text helpers
-- ---------------------------------------------------------------------------

local function ensure_player_fonts(pid)
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
    if pcall(Displayer.Font.loadTextureForPlayer, pid) then
      return true
    end
    if pcall(Displayer.Font.loadTextureForPlayer, Displayer.Font, pid) then
      return true
    end
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

local function draw_text(pid, text, x, y, font, scale, z, id, tint)
  if not Displayer then
    return false
  end

  ensure_player_fonts(pid)

  -- Displayer uses screen pixels, where logical UI coords are doubled.
  local sx = math.floor((x or 0) * 2)
  local sy = math.floor((y or 0) * 2)
  local final_tint = normalize_tint(tint)

  -- Preferred path: raw FontSystem supports tint.
  local fs = Displayer._subsystems and Displayer._subsystems.FontSystem
  if fs and fs.drawTextWithId then
    local ok, result = pcall(
      fs.drawTextWithId,
      fs,
      pid,
      text,
      sx,
      sy,
      font,
      scale,
      z,
      id,
      final_tint
    )

    if ok and result then
      return true
    end
  end

  -- Fallback: old wrapper, no tint.
  if Displayer.Font and Displayer.Font.drawTextWithId then
    local ok = pcall(Displayer.Font.drawTextWithId, pid, text, sx, sy, font, scale, z, id)
    if not ok then
      ok = pcall(Displayer.Font.drawTextWithId, Displayer.Font, pid, text, sx, sy, font, scale, z, id)
    end
    return ok
  end

  return false
end

local function clear_text(pid)
  erase_text(pid, cfg.title_id)
  for i = 1, cfg.visible_rows do
    erase_text(pid, cfg.row_text_id_base .. tostring(i))
    erase_text(pid, cfg.right_text_id_base .. tostring(i))
  end
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

local function clear_ui(pid)
  MenuAPI.hide_message(pid)

  -- Clear both type pools so old menu1/menu2 allocations do not visually linger.
  for _, t in ipairs({ 1, 2 }) do
    safe_remove(sprite_id(pid, "bg", t), pid)
    safe_remove(sprite_id(pid, "cursor", t), pid)
    safe_remove(sprite_id(pid, "scroll", t), pid)
  end

  clear_text(pid)
end

local function scroll_y_for_state(st)
  if st.scroll_enabled == false then
    return nil
  end
  local rows = st.rows or {}
  local total = #rows
  local visible = tonumber(st.visible_rows) or cfg.visible_rows

  if total <= visible then
    return nil
  end

  local top = st.top_index or 1
  local max_top = math.max(1, total - visible + 1)
  local t = (top - 1) / math.max(1, max_top - 1)

  local track_top = st.scroll_top_y or cfg.scroll_top_y or 11
  local track_bottom = st.scroll_bottom_y or cfg.scroll_bottom_y or 106
  local bar_h = st.scroll_h or cfg.scroll_h or 13
  local max_y = math.max(track_top, track_bottom - bar_h)

  return track_top + ((max_y - track_top) * t)
end

local function draw_background(pid, st)
  local x = st.x or cfg.menu1_x
  local y = st.y or cfg.menu1_y
  local z = st.z or cfg.menu1_z

  safe_remove(sprite_id(pid, "bg", st.type), pid)
  safe_add(
    sprite_id(pid, "bg", st.type),
    pid,
    st.texture or cfg.menu1_texture,
    st.anim or cfg.menu1_anim,
    st.anim_state or cfg.menu1_state,
    x,
    y,
    z,
    st.scale or cfg.menu1_scale,
    st.scale or cfg.menu1_scale
  )
end

local function draw_title(pid, st)
  erase_text(pid, cfg.title_id)

  local x, y = rel(st, st.title_x or cfg.title_x, st.title_y or cfg.title_y)
  draw_text(
    pid,
    truncate(st.title or "Menu", st.title_max_ch or cfg.title_max_ch),
    x,
    y,
    st.title_font or cfg.title_font,
    st.title_scale or cfg.title_scale,
    (st.z or cfg.menu1_z) + 5,
    cfg.title_id,
    st.title_tint or cfg.title_tint
  )
end

local function draw_rows(pid, st)
  clear_text(pid)
  draw_title(pid, st)

  local rows = st.rows or {}
  local top = st.top_index or 1
  local visible = tonumber(st.visible_rows) or cfg.visible_rows

  local row_y = st.row_y or cfg.row_y
  local row_x = st.row_x or cfg.row_x
  local row_advance = st.row_advance or cfg.row_advance

  for i = 1, visible do
    local idx = top + i - 1
    local row = rows[idx]
    local y_rel = row_y + ((i - 1) * row_advance)

    if row then
      local text_x, text_y = rel(st, row_x, y_rel)
      local display = truncate(row_text(row), st.row_max_ch or cfg.row_max_ch)

      -- Optional disabled marker. Keeping it subtle: callers can also bake
      -- their own prefix into row.text if they want something different.
      if row_selectable(row) == false and row.disabled_prefix ~= false then
        display = truncate("- " .. str_trim(display), st.row_max_ch or cfg.row_max_ch)
      end

      draw_text(
        pid,
        display,
        text_x,
        text_y,
        row.font or st.row_font or cfg.row_font,
        row.scale or st.row_scale or cfg.row_scale,
        row.z or (st.z or cfg.menu1_z) + 5,
        (st.row_text_id_base or cfg.row_text_id_base) .. tostring(i),
        row.tint or st.row_tint or cfg.row_tint
      )

      local right = ""
      if st.show_right ~= false then
        right = row_right(row)
      end

      if right ~= "" then
        local right_x, right_y = rel(st, st.right_x or cfg.right_x, y_rel)
        draw_text(
          pid,
          truncate(right, st.right_max_ch or cfg.right_max_ch),
          right_x,
          right_y,
          row.right_font or st.right_font or cfg.right_font,
          row.right_scale or st.right_scale or cfg.right_scale,
          row.right_z or (st.z or cfg.menu1_z) + 5,
          cfg.right_text_id_base .. tostring(i),
          row.right_tint or st.right_tint or cfg.right_tint
        )
      end
    end
  end
end

local function draw_cursor(pid, st)
  safe_remove(sprite_id(pid, "cursor", st.type), pid)

  if st.cursor_enabled == false then
    return
  end

  local rows = st.rows or {}
  local total = #rows
  if total <= 0 or not st.cursor or st.cursor <= 0 then
    return
  end

  local top = st.top_index or 1
  local visible = tonumber(st.visible_rows) or cfg.visible_rows
  local row_index = st.cursor - top + 1

  if row_index < 1 or row_index > visible then
    return
  end

  local row_y = st.row_y or cfg.row_y
  local row_advance = st.row_advance or cfg.row_advance
  local cursor_y_offset = st.cursor_y_offset or cfg.cursor_y_offset or 0

  local y_rel = row_y + ((row_index - 1) * row_advance) + cursor_y_offset
  local x, y = rel(st, st.cursor_x or cfg.cursor_x, y_rel)

  safe_add(
    sprite_id(pid, "cursor", st.type),
    pid,
    st.cursor_texture or cfg.cursor_texture,
    st.cursor_anim or cfg.cursor_anim,
    st.cursor_state or cfg.cursor_state,
    x,
    y,
    (st.z or cfg.menu1_z) + 6,
    st.cursor_scale or cfg.cursor_scale,
    st.cursor_scale or cfg.cursor_scale
  )
end

local function draw_scroll(pid, st)
  safe_remove(sprite_id(pid, "scroll", st.type), pid)

  local y_rel = scroll_y_for_state(st)
  if not y_rel then
    return
  end

  local x, y = rel(st, st.scroll_x or cfg.scroll_x, y_rel)

  safe_add(
    sprite_id(pid, "scroll", st.type),
    pid,
    st.scroll_texture or cfg.scroll_texture,
    st.scroll_anim or cfg.scroll_anim,
    st.scroll_state or cfg.scroll_state,
    x,
    y,
    (st.z or cfg.menu1_z) + 6,
    st.scroll_scale or cfg.scroll_scale,
    st.scroll_scale or cfg.scroll_scale
  )
end

local function redraw(pid)
  local st = state_by_pid[pid]
  if not st then return end

  ensure_cursor_visible(st)
  draw_background(pid, st)
  draw_rows(pid, st)
  draw_cursor(pid, st)
  draw_scroll(pid, st)
end

-- ---------------------------------------------------------------------------
-- Parent/back behavior
-- ---------------------------------------------------------------------------

local function open_parent(pid, parent)
  if not parent then return false end

  if type(parent) == "function" then
    local ok = pcall(parent, pid)
    return ok
  end

  if type(parent) == "table" and type(parent.open) == "function" then
    local ok = pcall(parent.open, pid)
    return ok
  end

  if parent == "lmenu" then
    local LMenu = rawget(_G, "LMenu")
    if LMenu and type(LMenu.open) == "function" then
      local ok = pcall(LMenu.open, pid)
      return ok
    end
  end

  return false
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function MenuAPI.is_open(pid)
  return state_by_pid[pid] ~= nil
end

_G.menuapi_ui_is_open = function(pid)
  return state_by_pid[pid] ~= nil
end

function MenuAPI.get_state(pid)
  return state_by_pid[pid]
end

local pending_parent_reopen = rawget(_G, "__MENUAPI_PENDING_PARENT_REOPEN__")
if type(pending_parent_reopen) ~= "table" then
  pending_parent_reopen = {}
  _G.__MENUAPI_PENDING_PARENT_REOPEN__ = pending_parent_reopen
end

local function reopen_parent_later(pid, parent)
  if not parent then
    return
  end

  pending_parent_reopen[pid] = {
    parent = parent,
    at = ((os and os.clock and os.clock()) or 0) + 0.05,
  }
end

if Net and Net.on and not rawget(_G, "__MENUAPI_PARENT_REOPEN_TICK__") then
  _G.__MENUAPI_PARENT_REOPEN_TICK__ = true

  Net:on("tick", function()
    local pending = rawget(_G, "__MENUAPI_PENDING_PARENT_REOPEN__")
    if type(pending) ~= "table" then
      return
    end

    local now = (os and os.clock and os.clock()) or 0

    for pid, job in pairs(pending) do
      if now >= (tonumber(job.at) or 0) then
        pending[pid] = nil
        open_parent(pid, job.parent)
      end
    end
  end)
end

function MenuAPI.close(pid, opts)
  local st = state_by_pid[pid]
  if not st then return false end

  opts = opts or {}
  local reason = opts.reason or "closed"
  local keep_frozen = opts.keep_frozen == true
  local reopen_parent = opts.reopen_parent == true
  local parent = st.parent
  local on_close = st.on_close
  local lock_input = st.lock_input == true

  clear_ui(pid)
  state_by_pid[pid] = nil

  if type(on_close) == "function" then
    pcall(on_close, pid, st, reason)
  end

  if reopen_parent then
    reopen_parent_later(pid, parent)
  elseif lock_input and not keep_frozen and Net and Net.unlock_player_input then
    pcall(Net.unlock_player_input, pid)
  end

  return true
end

function MenuAPI.set_rows(pid, rows, opts)
  local st = state_by_pid[pid]
  if not st then return false end

  opts = opts or {}
  local old_id = nil
  if st.cursor and st.rows and st.rows[st.cursor] then
    old_id = st.rows[st.cursor].id
  end

  st.rows = normalize_rows(rows)

  if opts.keep_cursor ~= false and old_id then
    for i, row in ipairs(st.rows) do
      if row.id == old_id then
        st.cursor = i
        break
      end
    end
  end

  if not st.cursor or st.cursor < 1 or st.cursor > #st.rows then
    st.cursor = first_selectable_index(st.rows)
  end

  st.cursor = nearest_selectable_index(st.rows, st.cursor, 1)
  ensure_cursor_visible(st)
  redraw(pid)
  return true
end

function MenuAPI.refresh(pid)
  if not state_by_pid[pid] then return false end
  redraw(pid)
  return true
end

function MenuAPI.open(pid, spec)
  spec = spec or {}

  local menu_type = tonumber(spec.type or 1) or 1

  if menu_type ~= 1 and menu_type ~= 2 then
    log("Unsupported menu type", tostring(spec.type), "for", tostring(pid))
    return false, "unsupported_type"
  end

  local is_type2 = menu_type == 2

  -- Clean stale copy first. Keep lock state while replacing UI.
  if state_by_pid[pid] then
    MenuAPI.close(pid, { keep_frozen = true, reason = "replace" })
  end

  local rows = normalize_rows(spec.rows or {})
  local cursor = tonumber(spec.cursor or spec.cursor_index) or first_selectable_index(rows)
  cursor = nearest_selectable_index(rows, cursor, 1)

  local lock_input = spec.lock_input
  if lock_input == nil then
    lock_input = cfg.lock_input_by_default
  end

  local palette = MenuAPI.get_palette(spec.palette or spec.color or spec.theme or "default")

  local def_texture = is_type2 and cfg.menu2_texture or cfg.menu1_texture
  local def_anim = is_type2 and cfg.menu2_anim or cfg.menu1_anim
  local def_state = is_type2 and cfg.menu2_state or cfg.menu1_state
  local def_x = is_type2 and cfg.menu2_x or cfg.menu1_x
  local def_y = is_type2 and cfg.menu2_y or cfg.menu1_y
  local def_z = is_type2 and cfg.menu2_z or cfg.menu1_z
  local def_scale = is_type2 and cfg.menu2_scale or cfg.menu1_scale

  local def_title_x = is_type2 and cfg.menu2_title_x or cfg.title_x
  local def_title_y = is_type2 and cfg.menu2_title_y or cfg.title_y
  local def_title_max_ch = is_type2 and cfg.menu2_title_max_ch or cfg.title_max_ch

  local def_row_x = is_type2 and cfg.menu2_row_x or cfg.row_x
  local def_row_y = is_type2 and cfg.menu2_row_y or cfg.row_y
  local def_row_advance = is_type2 and cfg.menu2_row_advance or cfg.row_advance
  local def_visible_rows = is_type2 and cfg.menu2_visible_rows or cfg.visible_rows
  local def_row_max_ch = is_type2 and cfg.menu2_row_max_ch or cfg.row_max_ch

  local def_show_right = is_type2 and false or true
  local def_cursor_enabled = is_type2 and false or true
  local def_scroll_enabled = is_type2 and false or true

  local st = {
    type = menu_type,
    title = spec.title or "Menu",
    rows = rows,
    cursor = cursor,
    top_index = tonumber(spec.top_index) or 1,
    visible_rows = tonumber(spec.visible_rows) or def_visible_rows,
    x = tonumber(spec.x) or def_x,
    y = tonumber(spec.y) or def_y,
    z = tonumber(spec.z) or def_z,
    scale = tonumber(spec.scale) or def_scale,
    parent = spec.parent,
    on_confirm = spec.on_confirm,
    on_cancel = spec.on_cancel,
    on_close = spec.on_close,
    lock_input = lock_input == true,

    -- optional per-instance visual overrides
    texture = spec.texture or def_texture,
    anim = spec.anim or def_anim,
    anim_state = spec.anim_state or def_state,

    title_x = tonumber(spec.title_x) or def_title_x,
    title_y = tonumber(spec.title_y) or def_title_y,
    title_font = spec.title_font,
    title_scale = spec.title_scale,
    title_max_ch = spec.title_max_ch or def_title_max_ch,

    row_x = tonumber(spec.row_x) or def_row_x,
    row_y = tonumber(spec.row_y) or def_row_y,
    row_font = spec.row_font,
    row_scale = spec.row_scale,
    row_advance = spec.row_advance or def_row_advance,
    row_max_ch = spec.row_max_ch or def_row_max_ch,

    right_x = tonumber(spec.right_x) or cfg.right_x,
    right_font = spec.right_font,
    right_scale = spec.right_scale,
    right_max_ch = spec.right_max_ch,

    cursor_enabled = opt_bool(spec.cursor_enabled, def_cursor_enabled),
    cursor_texture = spec.cursor_texture,
    cursor_anim = spec.cursor_anim,
    cursor_state = spec.cursor_state,
    cursor_scale = spec.cursor_scale,
    cursor_x = spec.cursor_x,
    cursor_y_offset = spec.cursor_y_offset,

    scroll_enabled = opt_bool(spec.scroll_enabled, def_scroll_enabled),
    scroll_texture = spec.scroll_texture,
    scroll_anim = spec.scroll_anim,
    scroll_state = spec.scroll_state,
    scroll_scale = spec.scroll_scale,

    show_right = opt_bool(spec.show_right, def_show_right),
    title_tint = spec.title_tint or palette.title_tint,
    row_tint = spec.row_tint or palette.row_tint,
    right_tint = spec.right_tint or palette.right_tint,
  }

  state_by_pid[pid] = st
  ensure_cursor_visible(st)

  if st.lock_input and Net and Net.lock_player_input then
    pcall(Net.lock_player_input, pid)
  end

  play_sfx(pid, cfg.open_sfx)
  redraw(pid)
  return true
end

function MenuAPI.hide_message(pid)
  local st = state_by_pid[pid]
  local box_id = (st and st.message_box_id) or cfg.message_box_id
  local on_close = st and st.message_on_close

  if Displayer and Displayer.Text then
    if Displayer.Text.closeTextBox then
      pcall(Displayer.Text.closeTextBox, pid, box_id, {
        caller = "MenuAPI",
        reason = "hide_message",
        close_seconds = cfg.message_backdrop and cfg.message_backdrop.close_seconds or 0.12,
      })
    end

    -- Remove too, so stale dialogue never survives menu close/reopen.
    if Displayer.Text.removeTextBox then
      pcall(Displayer.Text.removeTextBox, pid, box_id)
    end
  end

  if st then
    st.message_open = false
    st.message_box_id = nil
    st.message_on_close = nil
  end

  if type(on_close) == "function" then
    pcall(on_close, pid)
  end

  return true
end

function MenuAPI.advance_message(pid)
  local st = state_by_pid[pid]
  if not st or not st.message_open then
    return false
  end

  local box_id = st.message_box_id or cfg.message_box_id

  if Displayer and Displayer.Text and Displayer.Text.advanceTextBox then
    pcall(Displayer.Text.advanceTextBox, pid, box_id)
  end

  local completed = false
  if Displayer and Displayer.Text and Displayer.Text.isTextBoxCompleted then
    local ok, result = pcall(Displayer.Text.isTextBoxCompleted, pid, box_id)
    completed = ok and result == true
  elseif Displayer and Displayer.Text and Displayer.Text.getTextBoxState then
    local ok, result = pcall(Displayer.Text.getTextBoxState, pid, box_id)
    completed = ok and result == "completed"
  end

  if completed then
    MenuAPI.hide_message(pid)
  end

  return true
end

function MenuAPI.show_message(pid, text, opts)
  opts = opts or {}

  if not (Displayer and Displayer.Text and Displayer.Text.resetTextBox) then
    return false
  end

  local st = state_by_pid[pid]
  local box_id = opts.box_id or cfg.message_box_id

  -- Default MenuAPI messages should behave like regular dialogue:
  -- stay open, wait for Confirm, advance pages, then close on final Confirm.
  local tb_opts = opts.textbox_opts or {
    page_advance = opts.page_advance or "wait_for_confirm",
    confirm_during_typing = opts.confirm_during_typing ~= false,
    open_seconds = opts.open_seconds or (cfg.message_backdrop and cfg.message_backdrop.open_seconds) or 0.12,
    wrap_opts = opts.wrap_opts,
    text_scale = opts.text_scale or cfg.message_text_scale,
  }

  local ok, err = pcall(
    Displayer.Text.resetTextBox,
    pid,
    box_id,
    tostring(text or ""),
    opts.x or cfg.message_x,
    opts.y or cfg.message_y,
    opts.width or cfg.message_w,
    opts.height or cfg.message_h,
    opts.font or cfg.message_font,
    opts.scale or cfg.message_scale,
    opts.z or cfg.message_z,
    opts.backdrop or cfg.message_backdrop,
    opts.speed or cfg.message_speed,
    tb_opts
  )

  if not ok then
    log("show_message failed:", tostring(err))
    return false
  end

  if st then
    st.message_box_id = box_id
    st.message_open = opts.modal ~= false -- default true
    st.message_on_close = opts.on_close
  end

  return true
end

-- ---------------------------------------------------------------------------
-- Navigation / input
-- ---------------------------------------------------------------------------

local function move_selection(pid, dir)
  local st = state_by_pid[pid]
  if not st then return false end

  local rows = st.rows or {}
  local total = #rows
  if total <= 1 then return true end

  local old = st.cursor or first_selectable_index(rows)
  local cur = old

  for _ = 1, total do
    cur = cur + dir
    if cur < 1 then cur = total end
    if cur > total then cur = 1 end
    if row_selectable(rows[cur]) then
      break
    end
  end

  if cur ~= old then
    st.cursor = cur
    ensure_cursor_visible(st)
    draw_rows(pid, st)
    draw_cursor(pid, st)
    draw_scroll(pid, st)
    play_sfx(pid, cfg.move_sfx)
  end

  return true
end

local function confirm_selection(pid)
  local st = state_by_pid[pid]
  if not st then return false end

  local row = st.rows and st.rows[st.cursor]
  if not row or not row_selectable(row) then
    play_sfx(pid, cfg.error_sfx)
    return true
  end

  play_sfx(pid, cfg.choose_sfx)

  if type(row.on_confirm) == "function" then
    local ok, handled = pcall(row.on_confirm, pid, row, st)
    if ok and handled ~= false then
      return true
    end
  end

  if type(st.on_confirm) == "function" then
    pcall(st.on_confirm, pid, row, st)
  end

  return true
end

function MenuAPI.handle_cancel(pid)
  local st = state_by_pid[pid]
  if not st then return false, "not_open" end

  play_sfx(pid, cfg.cancel_sfx)

  if type(st.on_cancel) == "function" then
    local ok, handled = pcall(st.on_cancel, pid, st)
    if ok and handled == true then
      return true, "handled"
    end
  end

  MenuAPI.close(pid, {
    keep_frozen = true,
    reopen_parent = st.parent ~= nil,
    reason = "cancel",
  })

  return true, "closed"
end

local function handle_button(pid, btn, kind)
  local st = state_by_pid[pid]
  if not st then return false end

  -- Dialogue/message box has priority over menu navigation.
  -- Confirm advances/closes it. Cancel/LS closes just the message.
  if st.message_open then
    if kind == "press" and btn == "A" then
      play_sfx(pid, cfg.choose_sfx)
      MenuAPI.advance_message(pid)
      return true
    end

    if kind == "press" and (btn == "Cancel" or btn == "LS") then
      play_sfx(pid, cfg.cancel_sfx)
      MenuAPI.hide_message(pid)
      return true
    end

    -- Block Up/Down/etc. while dialogue is open.
    return true
  end

  if btn == "U" or btn == "D" then
    local dir = (btn == "U") and -1 or 1

    if kind == "press" then
      st.hold_btn = btn
      st.next_scroll_ts = os.clock() + (cfg.nav_first_repeat_delay_sec or 0.15)
      return move_selection(pid, dir)
    elseif kind == "hold" then
      local now = os.clock()
      if st.hold_btn ~= btn then
        st.hold_btn = btn
        st.next_scroll_ts = now + (cfg.nav_first_repeat_delay_sec or 0.15)
        return true
      end
      if now >= (st.next_scroll_ts or 0) then
        st.next_scroll_ts = now + (cfg.nav_repeat_delay_sec or 0.02)
        return move_selection(pid, dir)
      end
      return true
    elseif kind == "release" then
      if st.hold_btn == btn then
        st.hold_btn = nil
        st.next_scroll_ts = 0
      end
      return true
    end
  end

  if kind == "press" and btn == "A" then
    return confirm_selection(pid)
  end

  if kind == "press" and (btn == "Cancel" or btn == "LS") then
    MenuAPI.handle_cancel(pid)
    return true
  end

  if kind == "press" and btn == "Pause" then
    play_sfx(pid, cfg.cancel_sfx)
    MenuAPI.close(pid, { keep_frozen = false, reason = "pause" })
    return true
  end

  return false
end

if Net and Net.on then
  Net:on("virtual_input", function(event)
    local pid = event.player_id
    local st = state_by_pid[pid]
    if not st then return end

    local evs = event.events
    if not evs then return end

    for _, button in next, evs do
      local name = button.name
      local state = button.state

      local is_press = (state == 1)
      local is_hold_or_scr = (state == 2 or state == 4)
      local is_release = (state == 3)

      local btn = nil
      if name == "Move Up" then
        btn = "U"
      elseif name == "Move Down" then
        btn = "D"
      elseif name == "Confirm" then
        btn = "A"
      elseif name == "Cancel" then
        btn = "Cancel"
      elseif name == "Shoulder L" then
        btn = "LS"
      elseif name == "Pause" then
        btn = "Pause"
      end

      if btn then
        local kind = is_press and "press" or (is_hold_or_scr and "hold" or (is_release and "release" or "other"))
        if handle_button(pid, btn, kind) then
          return
        end
      end
    end
  end)

  Net:on("player_disconnect", function(event)
    if event and event.player_id then
      MenuAPI.close(event.player_id, { keep_frozen = true, reason = "disconnect" })
    end
  end)
end

return MenuAPI
