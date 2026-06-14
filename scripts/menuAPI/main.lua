-- /server/scripts/menuAPI/main.lua
-- Rebuilt MenuAPI with reusable components and menu type definitions.
--
-- Type 1: scrolling vertical list.
-- Type 2: compact info window.
-- Type 3: compact selectable menu.
-- Type 4: compact confirm prompt with horizontal Yes/No choice.
-- Type 5: profile card + compact friends list.

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

-- ---------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------

local cfg = {
  title_tint = { r = 18, g = 42, b = 100, color_mode = 2 },
  row_tint   = { r = 95, g = 100, b = 108, color_mode = 2 },
  right_tint = { r = 95, g = 100, b = 108, color_mode = 2 },

  open_sfx   = "screen_open",
  move_sfx   = "select",
  choose_sfx = "choose",
  cancel_sfx = "cancel",
  error_sfx  = "error",

  nav_first_repeat_delay_sec = 1.0,
  nav_repeat_delay_sec       = 0.20,
  lock_input_by_default      = true,

  -- Backwards-compatible config aliases used by older callers/tests.
  menu1_texture = "/server/assets/ui/menuAPI/menu1.png",
  menu1_anim = nil,
  menu1_state = "",
  menu1_x = 49,
  menu1_y = 17,
  menu1_z = 220,
  menu1_scale = 2.0,

  menu2_texture = "/server/assets/ui/menuAPI/menu2.png",
  menu2_anim = nil,
  menu2_state = "",
  menu2_x = 49,
  menu2_y = 17,
  menu2_z = 220,
  menu2_scale = 2.0,

  menu3_texture = "/server/assets/ui/menuAPI/menu3.png",
  menu3_anim = nil,
  menu3_state = "",

  title_x = 17,
  title_y = 1,
  title_font = "THICK",
  title_scale = 1.5,
  title_max_ch = 18,
  row_x = 13,
  row_y = 16,
  row_font = "THICK",
  row_scale = 1.5,
  row_advance = 13,
  visible_rows = 8,
  row_max_ch = 20,
  right_x = 103,
  right_font = "THICK",
  right_scale = 1.5,
  right_max_ch = 5,
  cursor_texture = "/server/assets/ui/menuAPI/cursor.png",
  cursor_x = 1,
  cursor_y_offset = -2,
  cursor_scale = 2.0,
  scroll_texture = "/server/assets/ui/menuAPI/scroll.png",
  scroll_x = 131,
  scroll_top_y = 11,
  scroll_bottom_y = 106,
  scroll_h = 13,
  scroll_scale = 2.0,

  -- Dialogue/textbox used by MenuAPI.show_message.
  message_box_id = "menuapi_message",
  message_x = 10,
  message_y = 260,
  message_w = 220,
  message_h = 56,
  message_font = "THIN_BLACK",
  message_scale = 2.02,
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
}

MenuAPI.config = cfg

-- ---------------------------------------------------------------------------
-- Named tint palettes
-- ---------------------------------------------------------------------------

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
local next_instance_id = 0
local message_token_by_key = {}

local function next_ui_prefix(pid, menu_type)
  next_instance_id = next_instance_id + 1
  return "menuapi_" .. tostring(pid) .. "_t" .. tostring(menu_type or 1) .. "_" .. tostring(next_instance_id)
end

local function message_key(pid, box_id)
  return tostring(pid) .. ":" .. tostring(box_id or cfg.message_box_id)
end

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

local function table_copy(src)
  local out = {}
  if type(src) == "table" then
    for k, v in pairs(src) do
      if type(v) == "table" then
        local nested = {}
        for nk, nv in pairs(v) do nested[nk] = nv end
        out[k] = nested
      else
        out[k] = v
      end
    end
  end
  return out
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

local function opt_bool(value, default)
  if value == nil then return default end
  return value ~= false
end

local function row_text(row)
  if type(row) ~= "table" then return tostring(row or "") end
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
      for k, v in pairs(row) do copy[k] = v end
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
    if row_selectable(row) then return i end
  end
  return (#(rows or {}) > 0) and 1 or 0
end

local function nearest_selectable_index(rows, start_idx, dir)
  local count = #(rows or {})
  if count <= 0 then return 0 end

  start_idx = clamp(start_idx or 1, 1, count)
  dir = (dir and dir < 0) and -1 or 1

  if row_selectable(rows[start_idx]) then return start_idx end

  local i = start_idx
  for _ = 1, count do
    i = i + dir
    if i < 1 then i = count end
    if i > count then i = 1 end
    if row_selectable(rows[i]) then return i end
  end

  return start_idx
end

local function ensure_cursor_visible(st)
  local rows = st.rows or {}
  local total = #rows
  local visible = tonumber(st.visible_rows) or 1

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
  local layout = st.layout or {}
  return (st.x or layout.x or 0) + (x or 0), (st.y or layout.y or 0) + (y or 0)
end

-- ---------------------------------------------------------------------------
-- Safe UI wrappers and tracked cleanup
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

local function ensure_ui_tracker(st)
  st.ui_ids = st.ui_ids or {}
  st.ui_ids.sprites = st.ui_ids.sprites or {}
  st.ui_ids.texts = st.ui_ids.texts or {}
  return st.ui_ids
end

local function track_sprite(st, id)
  local ui = ensure_ui_tracker(st)
  ui.sprites[id] = true
end

local function track_text(st, id)
  local ui = ensure_ui_tracker(st)
  ui.texts[id] = true
end

local function clear_registered_ui(pid, st)
  if not st or type(st.ui_ids) ~= "table" then return end

  if type(st.ui_ids.sprites) == "table" then
    for id in pairs(st.ui_ids.sprites) do
      safe_remove(id, pid)
    end
  end

  if type(st.ui_ids.texts) == "table" and Displayer and Displayer.Font and Displayer.Font.eraseTextDisplay then
    for id in pairs(st.ui_ids.texts) do
      if not pcall(Displayer.Font.eraseTextDisplay, pid, id) then
        pcall(Displayer.Font.eraseTextDisplay, Displayer.Font, pid, id)
      end
    end
  end

  st.ui_ids = { sprites = {}, texts = {} }
end

local function add_sprite(pid, st, key, texture, anim, anim_state, x, y, z, sx, sy, tint)
  local id = (st.ui_prefix or "menuapi") .. "_" .. tostring(key)
  safe_remove(id, pid)

  if safe_add(id, pid, texture, anim, anim_state, x, y, z, sx, sy) then
    track_sprite(st, id)

    local final_tint = normalize_tint(tint)
    if final_tint and frame and type(frame.update_ui_element) == "function" then
      pcall(frame.update_ui_element, id, pid, final_tint)
    end

    return id
  end

  return nil
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
    if fs.player_fonts and fs.player_fonts[pid] then return true end
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

local function draw_text_raw(pid, text, x, y, font, scale, z, id, tint)
  if not Displayer then return false end

  ensure_player_fonts(pid)

  local sx = math.floor((x or 0) * 2)
  local sy = math.floor((y or 0) * 2)
  local final_tint = normalize_tint(tint)

  local fs = Displayer._subsystems and Displayer._subsystems.FontSystem
  if fs and fs.drawTextWithId then
    local ok, result = pcall(
      fs.drawTextWithId,
      fs,
      pid,
      tostring(text or ""),
      sx,
      sy,
      font,
      scale,
      z,
      id,
      final_tint
    )

    if ok and result then return true end
  end

  if Displayer.Font and Displayer.Font.drawTextWithId then
    local ok = pcall(Displayer.Font.drawTextWithId, pid, tostring(text or ""), sx, sy, font, scale, z, id)
    if not ok then
      ok = pcall(Displayer.Font.drawTextWithId, Displayer.Font, pid, tostring(text or ""), sx, sy, font, scale, z, id)
    end
    return ok
  end

  return false
end

local function draw_text(pid, st, key, text, x, y, font, scale, z, tint)
  local id = (st.ui_prefix or "menuapi") .. "_" .. tostring(key)
  erase_text(pid, id)
  track_text(st, id)
  return draw_text_raw(pid, text, x, y, font, scale, z, id, tint)
end

-- ---------------------------------------------------------------------------
-- Components
-- ---------------------------------------------------------------------------

local function draw_background(pid, st)
  local layout = st.layout or {}

  add_sprite(
    pid,
    st,
    "bg",
    st.texture or layout.texture,
    st.anim or layout.anim,
    st.anim_state or layout.anim_state or "",
    st.x or layout.x or 0,
    st.y or layout.y or 0,
    st.z or layout.z or 0,
    st.scale or layout.scale or 2.0,
    st.scale or layout.scale or 2.0,
    st.bg_tint
  )
end

local function draw_title(pid, st)
  local layout = st.layout or {}
  local x, y = rel(st, st.title_x or layout.title_x or 0, st.title_y or layout.title_y or 0)

  draw_text(
    pid,
    st,
    "title",
    truncate(st.title or "Menu", st.title_max_ch or layout.title_max_ch or 18),
    x,
    y,
    st.title_font or layout.title_font or "THICK",
    st.title_scale or layout.title_scale or 1.5,
    (st.z or layout.z or 0) + 5,
    st.title_tint or cfg.title_tint
  )
end

local function draw_vertical_rows(pid, st, skip_title)
  local layout = st.layout or {}

  if not skip_title then
    draw_title(pid, st)
  end

  local rows = st.rows or {}
  local top = st.top_index or 1
  local visible = tonumber(st.visible_rows) or layout.visible_rows or 4
  local row_y = st.row_y or layout.row_y or 0
  local row_x = st.row_x or layout.row_x or 0
  local row_advance = st.row_advance or layout.row_advance or 13

  for i = 1, visible do
    local idx = top + i - 1
    local row = rows[idx]
    local y_rel = row_y + ((i - 1) * row_advance)

    if row then
      local text_x, text_y = rel(st, row_x, y_rel)
      local display = truncate(row_text(row), st.row_max_ch or layout.row_max_ch or 20)

      if row_selectable(row) == false and row.disabled_prefix ~= false then
        display = truncate("- " .. str_trim(display), st.row_max_ch or layout.row_max_ch or 20)
      end

      draw_text(
        pid,
        st,
        "row_" .. tostring(i),
        display,
        text_x,
        text_y,
        row.font or st.row_font or layout.row_font or "THICK",
        row.scale or st.row_scale or layout.row_scale or 1.5,
        row.z or (st.z or layout.z or 0) + 5,
        row.tint or st.row_tint or cfg.row_tint
      )

      local right = ""
      if st.show_right ~= false then right = row_right(row) end

      if right ~= "" then
        local right_x, right_y = rel(st, st.right_x or layout.right_x or 0, y_rel)
        draw_text(
          pid,
          st,
          "right_" .. tostring(i),
          truncate(right, st.right_max_ch or layout.right_max_ch or 5),
          right_x,
          right_y,
          row.right_font or st.right_font or layout.right_font or "THICK",
          row.right_scale or st.right_scale or layout.right_scale or 1.5,
          row.right_z or (st.z or layout.z or 0) + 5,
          row.right_tint or st.right_tint or cfg.right_tint
        )
      end
    end
  end
end

local function draw_cursor(pid, st)
  local layout = st.layout or {}
  if st.cursor_enabled == false then return end

  local rows = st.rows or {}
  local total = #rows
  if total <= 0 or not st.cursor or st.cursor <= 0 then return end

  local top = st.top_index or 1
  local visible = tonumber(st.visible_rows) or layout.visible_rows or 4
  local row_index = st.cursor - top + 1
  if row_index < 1 or row_index > visible then return end

  local row_y = st.row_y or layout.row_y or 0
  local row_advance = st.row_advance or layout.row_advance or 13
  local cursor_y_offset = st.cursor_y_offset or layout.cursor_y_offset or 0
  local y_rel = row_y + ((row_index - 1) * row_advance) + cursor_y_offset
  local x, y = rel(st, st.cursor_x or layout.cursor_x or 0, y_rel)

  add_sprite(
    pid,
    st,
    "cursor",
    st.cursor_texture or layout.cursor_texture,
    st.cursor_anim or layout.cursor_anim,
    st.cursor_state or layout.cursor_state or "",
    x,
    y,
    (st.z or layout.z or 0) + 6,
    st.cursor_scale or layout.cursor_scale or 2.0,
    st.cursor_scale or layout.cursor_scale or 2.0
  )
end

local function scroll_y_for_state(st)
  if st.scroll_enabled == false then return nil end

  local layout = st.layout or {}
  local rows = st.rows or {}
  local total = #rows
  local visible = tonumber(st.visible_rows) or layout.visible_rows or 4

  if total <= visible then return nil end

  local top = st.top_index or 1
  local max_top = math.max(1, total - visible + 1)
  local t = (top - 1) / math.max(1, max_top - 1)

  local track_top = st.scroll_top_y or layout.scroll_top_y or 11
  local track_bottom = st.scroll_bottom_y or layout.scroll_bottom_y or 106
  local bar_h = st.scroll_h or layout.scroll_h or 13
  local max_y = math.max(track_top, track_bottom - bar_h)

  return track_top + ((max_y - track_top) * t)
end

local function draw_scroll(pid, st)
  local layout = st.layout or {}
  local y_rel = scroll_y_for_state(st)
  if not y_rel then return end

  local x, y = rel(st, st.scroll_x or layout.scroll_x or 0, y_rel)

  add_sprite(
    pid,
    st,
    "scroll",
    st.scroll_texture or layout.scroll_texture,
    st.scroll_anim or layout.scroll_anim,
    st.scroll_state or layout.scroll_state or "",
    x,
    y,
    (st.z or layout.z or 0) + 6,
    st.scroll_scale or layout.scroll_scale or 2.0,
    st.scroll_scale or layout.scroll_scale or 2.0
  )
end

local function draw_vertical_menu(pid, st)
  draw_background(pid, st)
  ensure_cursor_visible(st)
  draw_vertical_rows(pid, st)
  draw_cursor(pid, st)
  draw_scroll(pid, st)
end

local function draw_confirm_prompt(pid, st)
  local layout = st.layout or {}

  draw_background(pid, st)
  draw_title(pid, st)

  local lines = st.lines or st.type4_lines or {}
  local line_x = st.line_x or layout.line_x or 13
  local line_y = st.line_y or layout.line_y or 16
  local line_advance = st.line_advance or layout.line_advance or 13

  for i = 1, 3 do
    local text = tostring(lines[i] or "")
    local x, y = rel(st, line_x, line_y + ((i - 1) * line_advance))

    draw_text(
      pid,
      st,
      "line_" .. tostring(i),
      truncate(text, st.line_max_ch or layout.line_max_ch or 20),
      x,
      y,
      st.row_font or layout.row_font or "THICK",
      st.row_scale or layout.row_scale or 1.5,
      (st.z or layout.z or 0) + 5,
      st.row_tint or cfg.row_tint
    )
  end

  local choice = st.choice or "no"
  local yes_label = tostring(st.yes_text or "Yes")
  local no_label = tostring(st.no_text or "No")
  local yes_text = (choice == "yes") and ("> " .. yes_label) or ("  " .. yes_label)
  local no_text = (choice == "no") and ("> " .. no_label) or ("  " .. no_label)
  local selected_tint = st.choice_selected_tint or st.title_tint or cfg.title_tint
  local normal_tint = st.choice_normal_tint or st.row_tint or cfg.row_tint
  local choice_y = st.choice_y or layout.choice_y or 55

  local yes_x, yes_y = rel(st, st.yes_x or layout.yes_x or 25, choice_y)
  local no_x, no_y = rel(st, st.no_x or layout.no_x or 82, choice_y)

  draw_text(
    pid,
    st,
    "choice_yes",
    truncate(yes_text, st.choice_max_ch or layout.choice_max_ch or 8),
    yes_x,
    yes_y,
    st.row_font or layout.row_font or "THICK",
    st.row_scale or layout.row_scale or 1.5,
    (st.z or layout.z or 0) + 5,
    (choice == "yes") and selected_tint or normal_tint
  )

  draw_text(
    pid,
    st,
    "choice_no",
    truncate(no_text, st.choice_max_ch or layout.choice_max_ch or 8),
    no_x,
    no_y,
    st.row_font or layout.row_font or "THICK",
    st.row_scale or layout.row_scale or 1.5,
    (st.z or layout.z or 0) + 5,
    (choice == "no") and selected_tint or normal_tint
  )
end

local function draw_profile_card(pid, st)
  local layout = st.layout or {}
  local profile = st.profile or {}

  local px = st.profile_x or layout.profile_x or 49
  local py = st.profile_y or layout.profile_y or 4
  local pz = st.profile_z or layout.profile_z or (st.z or layout.z or 220)
  local scale = st.profile_scale or layout.profile_scale or 2.0

  add_sprite(
    pid,
    st,
    "profile_bg",
    st.profile_texture or layout.profile_texture or cfg.menu3_texture,
    st.profile_anim or layout.profile_anim,
    st.profile_state or layout.profile_state or "",
    px,
    py,
    pz,
    scale,
    scale,
    st.bg_tint
  )

  local mug_texture = profile.mug_texture
  local mug_anim = profile.mug_anim
  local mug_state = profile.mug_state or "UI"

  if mug_texture and mug_texture ~= "" then
    add_sprite(
      pid,
      st,
      "profile_mug",
      mug_texture,
      mug_anim,
      mug_state,
      px + (layout.mug_x or 8),
      py + (layout.mug_y or 14),
      pz + 7,
      profile.mug_scale or layout.mug_scale or 1.25,
      profile.mug_scale or layout.mug_scale or 1.25
    )
  end

  local profile_title = tostring(profile.title or "")
  if profile_title ~= "" then
    draw_text(
      pid,
      st,
      "profile_title",
      truncate(profile_title, profile.title_max_ch or layout.profile_title_max_ch or 12),
      px + (layout.profile_title_x or 66),
      py + (layout.profile_title_y or 3),
      profile.title_font or layout.profile_title_font or "THICK_BLACK",
      profile.title_scale or layout.profile_title_scale or 1.25,
      pz + 9,
      profile.title_tint or profile.tint or st.title_tint or cfg.title_tint
    )
  end
  local lines = profile.lines or {}
  local text_x = layout.profile_text_x or 66
  local text_y = profile.text_y or layout.profile_text_y or 14
  local text_advance = layout.profile_text_advance or 13
  local max_ch = layout.profile_text_max_ch or 12

  for i = 1, 4 do
    local text = tostring(lines[i] or "")
    if text ~= "" then
      draw_text(
        pid,
        st,
        "profile_line_" .. tostring(i),
        truncate(text, max_ch),
        px + text_x,
        py + text_y + ((i - 1) * text_advance),
        profile.font or layout.profile_font or "THICK",
        profile.text_scale or layout.profile_text_scale or 1.35,
        pz + 8,
        profile.tint or st.row_tint or cfg.row_tint
      )
    end
  end
end

local function draw_profile_friends_menu(pid, st)
  local layout = st.layout or {}

  draw_profile_card(pid, st)

  add_sprite(
    pid,
    st,
    "list_bg",
    st.list_texture or layout.list_texture or cfg.menu2_texture,
    st.list_anim or layout.list_anim,
    st.list_state or layout.list_state or "",
    st.list_x or layout.list_x or 49,
    st.list_y or layout.list_y or 84,
    st.list_z or layout.list_z or (st.z or layout.z or 220),
    st.list_scale or layout.list_scale or 2.0,
    st.list_scale or layout.list_scale or 2.0,
    st.bg_tint
  )

  local old_x, old_y, old_z = st.x, st.y, st.z
  st.x = st.list_x or layout.list_x or 49
  st.y = st.list_y or layout.list_y or 84
  st.z = st.list_z or layout.list_z or st.z or layout.z or 220

  ensure_cursor_visible(st)
  draw_vertical_rows(pid, st)
  draw_cursor(pid, st)
  draw_scroll(pid, st)

  st.x, st.y, st.z = old_x, old_y, old_z
end

local function sprite_id_for_key(st, key)
  return (st.ui_prefix or "menuapi") .. "_" .. tostring(key)
end

local function text_id_for_key(st, key)
  return (st.ui_prefix or "menuapi") .. "_" .. tostring(key)
end

local function clear_profile_details(pid, st)
  safe_remove(sprite_id_for_key(st, "profile_mug"), pid)
  erase_text(pid, text_id_for_key(st, "profile_title"))

  for i = 1, 4 do
    erase_text(pid, text_id_for_key(st, "profile_line_" .. tostring(i)))
  end
end

local function redraw_profile_details_only(pid, st)
  if not st or st.type ~= 5 then
    return false
  end

  local layout = st.layout or {}
  local profile = st.profile or {}

  local px = st.profile_x or layout.profile_x or 49
  local py = st.profile_y or layout.profile_y or 4
  local pz = st.profile_z or layout.profile_z or (st.z or layout.z or 220)

  clear_profile_details(pid, st)

  local mug_texture = profile.mug_texture
  local mug_anim = profile.mug_anim
  local mug_state = profile.mug_state or "UI"

  if mug_texture and mug_texture ~= "" then
    add_sprite(
      pid,
      st,
      "profile_mug",
      mug_texture,
      mug_anim,
      mug_state,
      px + (layout.mug_x or 8),
      py + (layout.mug_y or 14),
      pz + 7,
      profile.mug_scale or layout.mug_scale or 1.25,
      profile.mug_scale or layout.mug_scale or 1.25
    )
  end

  local profile_title = tostring(profile.title or "")
  if profile_title ~= "" then
    draw_text(
      pid,
      st,
      "profile_title",
      truncate(profile_title, profile.title_max_ch or layout.profile_title_max_ch or 12),
      px + (layout.profile_title_x or 66),
      py + (layout.profile_title_y or 3),
      profile.title_font or layout.profile_title_font or "THICK_BLACK",
      profile.title_scale or layout.profile_title_scale or 1.25,
      pz + 9,
      profile.title_tint or profile.tint or st.title_tint or cfg.title_tint
    )
  end

  local lines = profile.lines or {}
  local text_x = layout.profile_text_x or 66
  local text_y = profile.text_y or layout.profile_text_y or 14
  local text_advance = layout.profile_text_advance or 13
  local max_ch = layout.profile_text_max_ch or 12

  for i = 1, 4 do
    local text = tostring(lines[i] or "")

    if text ~= "" then
      draw_text(
        pid,
        st,
        "profile_line_" .. tostring(i),
        truncate(text, max_ch),
        px + text_x,
        py + text_y + ((i - 1) * text_advance),
        profile.font or layout.profile_font or "THICK",
        profile.text_scale or layout.profile_text_scale or 1.35,
        pz + 8,
        profile.tint or st.row_tint or cfg.row_tint
      )
    end
  end

  return true
end

local function clear_visible_row_text(pid, st)
  local layout = st.layout or {}
  local visible = tonumber(st.visible_rows) or layout.visible_rows or 4

  for i = 1, visible do
    erase_text(pid, text_id_for_key(st, "row_" .. tostring(i)))
    erase_text(pid, text_id_for_key(st, "right_" .. tostring(i)))
  end
end

local function with_vertical_list_origin(st, fn)
  if not st then return end

  -- Type 5 draws its selectable list inside the list panel, not at the
  -- profile card origin. Match draw_profile_friends_menu's temporary origin.
  if st.type ~= 5 then
    fn()
    return
  end

  local layout = st.layout or {}
  local old_x, old_y, old_z = st.x, st.y, st.z

  st.x = st.list_x or layout.list_x or 49
  st.y = st.list_y or layout.list_y or 84
  st.z = st.list_z or layout.list_z or st.z or layout.z or 220

  local ok, err = pcall(fn)

  st.x, st.y, st.z = old_x, old_y, old_z

  if not ok then
    error(err)
  end
end

local function redraw_cursor_only(pid, st)
  with_vertical_list_origin(st, function()
    draw_cursor(pid, st)
  end)
end

local function redraw_visible_list_only(pid, st)
  with_vertical_list_origin(st, function()
    clear_visible_row_text(pid, st)

    -- Remove these first so stale cursor/scroll sprites cannot linger.
    safe_remove(sprite_id_for_key(st, "cursor"), pid)
    safe_remove(sprite_id_for_key(st, "scroll"), pid)

    -- Redraw rows without title/background/window.
    draw_vertical_rows(pid, st, true)
    draw_cursor(pid, st)
    draw_scroll(pid, st)
  end)
end

-- ---------------------------------------------------------------------------
-- Menu type definitions
-- ---------------------------------------------------------------------------

local MENU_TYPES = {
  [1] = {
    name = "scroll_list",
    kind = "vertical",
    vertical_input = true,
    cursor_enabled = true,
    scroll_enabled = true,
    show_right = true,
    layout = {
      texture = "/server/assets/ui/menuAPI/menu1.png",
      anim = nil,
      anim_state = "",
      x = 49,
      y = 17,
      z = 220,
      scale = 2.0,

      title_x = 17,
      title_y = 1,
      title_font = "THICK",
      title_scale = 1.5,
      title_max_ch = 18,

      row_x = 13,
      row_y = 16,
      row_font = "THICK",
      row_scale = 1.5,
      row_advance = 13,
      visible_rows = 8,
      row_max_ch = 20,

      right_x = 103,
      right_font = "THICK",
      right_scale = 1.5,
      right_max_ch = 5,

      cursor_texture = "/server/assets/ui/menuAPI/cursor.png",
      cursor_anim = nil,
      cursor_state = "",
      cursor_x = 1,
      cursor_y_offset = -2,
      cursor_scale = 2.0,

      scroll_texture = "/server/assets/ui/menuAPI/scroll.png",
      scroll_anim = nil,
      scroll_state = "",
      scroll_x = 131,
      scroll_top_y = 11,
      scroll_bottom_y = 106,
      scroll_h = 13,
      scroll_scale = 2.0,
    },
    draw = draw_vertical_menu,
  },

  [2] = {
    name = "info_window",
    kind = "vertical",
    vertical_input = false,
    cursor_enabled = false,
    scroll_enabled = false,
    show_right = false,
    layout = {
      texture = "/server/assets/ui/menuAPI/menu2.png",
      anim = nil,
      anim_state = "",
      x = 49,
      y = 17,
      z = 220,
      scale = 2.0,

      title_x = 17,
      title_y = 1,
      title_font = "THICK",
      title_scale = 1.5,
      title_max_ch = 18,

      row_x = 13,
      row_y = 16,
      row_font = "THICK",
      row_scale = 1.5,
      row_advance = 13,
      visible_rows = 4,
      row_max_ch = 20,

      right_x = 103,
      right_font = "THICK",
      right_scale = 1.5,
      right_max_ch = 5,
    },
    draw = draw_vertical_menu,
  },

  [3] = {
    name = "compact_menu",
    kind = "vertical",
    vertical_input = true,
    cursor_enabled = true,
    scroll_enabled = false,
    show_right = false,
    max_rows = 4,
    layout = {
      texture = "/server/assets/ui/menuAPI/menu2.png",
      anim = nil,
      anim_state = "",
      x = 49,
      y = 17,
      z = 220,
      scale = 2.0,

      title_x = 17,
      title_y = 1,
      title_font = "THICK",
      title_scale = 1.5,
      title_max_ch = 18,

      row_x = 13,
      row_y = 16,
      row_font = "THICK",
      row_scale = 1.5,
      row_advance = 13,
      visible_rows = 4,
      row_max_ch = 20,

      right_x = 103,
      right_font = "THICK",
      right_scale = 1.5,
      right_max_ch = 5,

      cursor_texture = "/server/assets/ui/menuAPI/cursor.png",
      cursor_anim = nil,
      cursor_state = "",
      cursor_x = 1,
      cursor_y_offset = -2,
      cursor_scale = 2.0,
    },
    draw = draw_vertical_menu,
  },

  [4] = {
    name = "confirm_prompt",
    kind = "confirm",
    horizontal_input = true,
    cursor_enabled = false,
    scroll_enabled = false,
    show_right = false,
    layout = {
      texture = "/server/assets/ui/menuAPI/menu2.png",
      anim = nil,
      anim_state = "",
      x = 49,
      y = 17,
      z = 220,
      scale = 2.0,

      title_x = 17,
      title_y = 1,
      title_font = "THICK",
      title_scale = 1.5,
      title_max_ch = 18,

      row_font = "THICK",
      row_scale = 1.5,
      line_x = 13,
      line_y = 16,
      line_advance = 13,
      line_max_ch = 20,

      choice_y = 55,
      yes_x = 25,
      no_x = 82,
      choice_max_ch = 8,
    },
    draw = draw_confirm_prompt,
  },

  [5] = {
    name = "profile_card",
    kind = "vertical",
    vertical_input = true,
    cursor_enabled = true,
    scroll_enabled = true,
    show_right = true,
    layout = {
      profile_texture = "/server/assets/ui/menuAPI/menu3.png",
      profile_anim = nil,
      profile_state = "",
      profile_x = 144,
      profile_y = 20,
      profile_z = 220,
      profile_scale = 2.0,

      mug_x = 4,
      mug_y = 13,
      mug_scale = 1.0,

      profile_title_x = 17,
      profile_title_y = 2,
      profile_title_max_ch = 10,
      profile_title_font = "THICK",
      profile_title_scale = 1.8,

      profile_text_x = 40,
      profile_text_y = 24,
      profile_text_advance = 10,
      profile_text_max_ch = 10,
      profile_font = "THICK",
      profile_text_scale = 1.5,

      list_texture = "/server/assets/ui/menuAPI/menu1.png",
      list_anim = nil,
      list_state = "",
      list_x = 2,
      list_y = 20,
      list_z = 10,
      list_scale = 2.0,

      title_x = 17,
      title_y = 1,
      title_font = "THICK",
      title_scale = 1.5,
      title_max_ch = 18,

      row_x = 13,
      row_y = 16,
      row_font = "THICK",
      row_scale = 1.5,
      row_advance = 13,
      visible_rows = 8,
      row_max_ch = 14,

      right_x = 96,
      right_font = "THICK",
      right_scale = 1.5,
      right_max_ch = 6,

      cursor_texture = "/server/assets/ui/menuAPI/cursor.png",
      cursor_anim = nil,
      cursor_state = "",
      cursor_x = 1,
      cursor_y_offset = -2,
      cursor_scale = 2.0,

      scroll_texture = "/server/assets/ui/menuAPI/scroll.png",
      scroll_anim = nil,
      scroll_state = "",
      scroll_x = 131,
      scroll_top_y = 11,
      scroll_bottom_y = 106,
      scroll_h = 13,
      scroll_scale = 2.0,
    },
    draw = draw_profile_friends_menu,
  },
}

MenuAPI.menu_types = MENU_TYPES

local function resolve_menu_type(menu_type)
  if type(menu_type) == "string" then
    local lowered = menu_type:lower()
    for id, def in pairs(MENU_TYPES) do
      if def.name == lowered then return id end
    end
  end

  return tonumber(menu_type or 1) or 1
end

local function apply_layout_overrides(layout, spec)
  local map = {
    texture = "texture",
    anim = "anim",
    anim_state = "anim_state",
    x = "x",
    y = "y",
    z = "z",
    scale = "scale",

    title_x = "title_x",
    title_y = "title_y",
    title_font = "title_font",
    title_scale = "title_scale",
    title_max_ch = "title_max_ch",

    row_x = "row_x",
    row_y = "row_y",
    row_font = "row_font",
    row_scale = "row_scale",
    row_advance = "row_advance",
    visible_rows = "visible_rows",
    row_max_ch = "row_max_ch",

    right_x = "right_x",
    right_font = "right_font",
    right_scale = "right_scale",
    right_max_ch = "right_max_ch",

    cursor_texture = "cursor_texture",
    cursor_anim = "cursor_anim",
    cursor_state = "cursor_state",
    cursor_x = "cursor_x",
    cursor_y_offset = "cursor_y_offset",
    cursor_scale = "cursor_scale",

    scroll_texture = "scroll_texture",
    scroll_anim = "scroll_anim",
    scroll_state = "scroll_state",
    scroll_x = "scroll_x",
    scroll_top_y = "scroll_top_y",
    scroll_bottom_y = "scroll_bottom_y",
    scroll_h = "scroll_h",
    scroll_scale = "scroll_scale",

    line_x = "type4_line_x",
    line_y = "type4_line_y",
    line_advance = "type4_line_advance",
    line_max_ch = "type4_line_max_ch",
    choice_y = "type4_choice_y",
    yes_x = "type4_yes_x",
    no_x = "type4_no_x",
    choice_max_ch = "type4_choice_max_ch",
  }

  for dst, src in pairs(map) do
    if spec[src] ~= nil then
      layout[dst] = spec[src]
    end
  end
end

local function build_state(pid, spec, menu_type, def)
  local palette = MenuAPI.get_palette(spec.palette or spec.color or spec.theme or "default")
  local layout = table_copy(def.layout)
  apply_layout_overrides(layout, spec)

  local rows = normalize_rows(spec.rows or {})
  if def.max_rows and #rows > def.max_rows then
    log("Menu type", tostring(menu_type), "received more than", tostring(def.max_rows), "rows; trimming extra rows for", tostring(pid))
    local trimmed = {}
    for i = 1, def.max_rows do trimmed[i] = rows[i] end
    rows = trimmed
  end

  local cursor = tonumber(spec.cursor or spec.cursor_index) or first_selectable_index(rows)
  cursor = nearest_selectable_index(rows, cursor, 1)

  local lock_input = spec.lock_input
  if lock_input == nil then lock_input = cfg.lock_input_by_default end

  local st = {
    type = menu_type,
    type_name = def.name,
    kind = def.kind,
    layout = layout,
    ui_prefix = next_ui_prefix(pid, menu_type),
    ui_ids = { sprites = {}, texts = {} },

    title = spec.title or "Menu",
    profile = spec.profile or {},
    rows = rows,
    cursor = cursor,
    top_index = tonumber(spec.top_index) or 1,
    visible_rows = tonumber(spec.visible_rows) or layout.visible_rows,

    x = tonumber(spec.x) or layout.x,
    y = tonumber(spec.y) or layout.y,
    z = tonumber(spec.z) or layout.z,
    scale = tonumber(spec.scale) or layout.scale,

    parent = spec.parent,
    on_confirm = spec.on_confirm,
    on_cancel = spec.on_cancel,
    on_close = spec.on_close,
    lock_input = lock_input == true,
    cancel_sfx = spec.cancel_sfx,

    texture = spec.texture or layout.texture,
    anim = spec.anim or layout.anim,
    anim_state = spec.anim_state or layout.anim_state,

    cursor_enabled = opt_bool(spec.cursor_enabled, def.cursor_enabled),
    scroll_enabled = opt_bool(spec.scroll_enabled, def.scroll_enabled),
    show_right = opt_bool(spec.show_right, def.show_right),

    title_tint = spec.title_tint or palette.title_tint,
    row_tint = spec.row_tint or palette.row_tint,
    right_tint = spec.right_tint or palette.right_tint,
    bg_tint = spec.bg_tint or palette.bg_tint,

    lines = spec.lines or spec.type4_lines,
    choice = tostring(spec.default_choice or spec.choice or "no"):lower() == "yes" and "yes" or "no",
    yes_text = spec.yes_text or "Yes",
    no_text = spec.no_text or "No",
    choice_selected_tint = spec.choice_selected_tint or spec.type4_selected_tint,
    choice_normal_tint = spec.choice_normal_tint or spec.type4_normal_tint,
  }

  if def.kind == "vertical" then
    ensure_cursor_visible(st)
  end

  return st
end

local function redraw(pid)
  local st = state_by_pid[pid]
  if not st then return false end

  local def = MENU_TYPES[st.type]
  if not def or type(def.draw) ~= "function" then return false end

  clear_registered_ui(pid, st)
  def.draw(pid, st)
  return true
end

-- ---------------------------------------------------------------------------
-- Parent/back behavior
-- ---------------------------------------------------------------------------

local pending_parent_reopen = rawget(_G, "__MENUAPI_PENDING_PARENT_REOPEN__")
if type(pending_parent_reopen) ~= "table" then
  pending_parent_reopen = {}
  _G.__MENUAPI_PENDING_PARENT_REOPEN__ = pending_parent_reopen
end

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

local function reopen_parent_later(pid, parent)
  if not parent then return end

  pending_parent_reopen[pid] = {
    parent = parent,
    ticks = 1,
  }
end

if Net and Net.on and not rawget(_G, "__MENUAPI_PARENT_REOPEN_TICK__") then
  _G.__MENUAPI_PARENT_REOPEN_TICK__ = true

  Net:on("tick", function()
    local pending = rawget(_G, "__MENUAPI_PENDING_PARENT_REOPEN__")
    if type(pending) ~= "table" then return end

    for pid, job in pairs(pending) do
      job.ticks = (tonumber(job.ticks) or 1) - 1

      if job.ticks <= 0 then
        pending[pid] = nil
        open_parent(pid, job.parent)
      end
    end
  end)
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

  MenuAPI.hide_message(pid)
  clear_registered_ui(pid, st)
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

  local def = MENU_TYPES[st.type]
  if not def or def.kind ~= "vertical" then return false end

  opts = opts or {}
  local old_id = nil
  if st.cursor and st.rows and st.rows[st.cursor] then
    old_id = st.rows[st.cursor].id
  end

  st.rows = normalize_rows(rows)

  if def.max_rows and #st.rows > def.max_rows then
    local trimmed = {}
    for i = 1, def.max_rows do trimmed[i] = st.rows[i] end
    st.rows = trimmed
  end

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
  return redraw(pid)
end

function MenuAPI.set_profile(pid, profile)
  local st = state_by_pid[pid]
  if not st or st.type ~= 5 then
    return false
  end

  st.profile = profile or {}
  return redraw_profile_details_only(pid, st)
end

function MenuAPI.open(pid, spec)
  spec = spec or {}

  local menu_type = resolve_menu_type(spec.type or 1)
  local def = MENU_TYPES[menu_type]

  if not def then
    log("Unsupported menu type", tostring(spec.type), "for", tostring(pid))
    return false, "unsupported_type"
  end

  if state_by_pid[pid] then
    MenuAPI.close(pid, { keep_frozen = true, reason = "replace" })
  end

  local st = build_state(pid, spec, menu_type, def)
  state_by_pid[pid] = st

  if st.lock_input and Net and Net.lock_player_input then
    pcall(Net.lock_player_input, pid)
  end

  local open_sfx = spec.open_sfx
  if open_sfx == nil then open_sfx = cfg.open_sfx end
  if open_sfx ~= false and open_sfx ~= "" then
    play_sfx(pid, open_sfx)
  end

  redraw(pid)
  return true
end

function MenuAPI.hide_message(pid, box_id_override)
  local st = state_by_pid[pid]
  local box_id = box_id_override or (st and st.message_box_id) or cfg.message_box_id
  local on_close = st and st.message_on_close

  if Displayer and Displayer.Text then
    if Displayer.Text.closeTextBox then
      pcall(Displayer.Text.closeTextBox, pid, box_id, {
        caller = "MenuAPI",
        reason = "hide_message",
        close_seconds = cfg.message_backdrop and cfg.message_backdrop.close_seconds or 0.12,
      })
    end

    if Displayer.Text.removeTextBox then
      pcall(Displayer.Text.removeTextBox, pid, box_id)
    end
  end

  if st and (not box_id_override or st.message_box_id == box_id_override) then
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
  if not st or not st.message_open then return false end

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
    st.message_open = opts.modal ~= false
    st.message_on_close = opts.on_close
  end

  local duration = tonumber(opts.duration or opts.auto_close_seconds or 0)
  if duration > 0 and Async and Async.sleep then
    local key = message_key(pid, box_id)
    message_token_by_key[key] = (message_token_by_key[key] or 0) + 1
    local token = message_token_by_key[key]

    Async.sleep(duration).and_then(function()
      if message_token_by_key[key] == token then
        MenuAPI.hide_message(pid, box_id)
      end
    end)
  end

  return true
end

-- ---------------------------------------------------------------------------
-- Input handlers
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
    if row_selectable(rows[cur]) then break end
  end

  if cur ~= old then
    local old_top = st.top_index or 1

    st.cursor = cur
    ensure_cursor_visible(st)

    if (st.top_index or 1) ~= old_top then
      redraw_visible_list_only(pid, st)
    else
      redraw_cursor_only(pid, st)
    end

    play_sfx(pid, cfg.move_sfx)
  end

  return true
end

local function move_horizontal_choice(pid, choice)
  local st = state_by_pid[pid]
  if not st or st.kind ~= "confirm" then return false end

  choice = (choice == "yes") and "yes" or "no"
  if st.choice ~= choice then
    st.choice = choice
    redraw(pid)
    play_sfx(pid, cfg.move_sfx)
  end

  return true
end

local function confirm_selection(pid)
  local st = state_by_pid[pid]
  if not st then return false end

  if st.kind == "confirm" then
    local choice = st.choice or "no"
    local row = {
      id = choice,
      choice = choice,
      text = (choice == "yes") and (st.yes_text or "Yes") or (st.no_text or "No"),
    }

    play_sfx(pid, cfg.choose_sfx)

    if type(st.on_confirm) == "function" then
      pcall(st.on_confirm, pid, row, st)
    end

    return true
  end

  local row = st.rows and st.rows[st.cursor]
  if not row or not row_selectable(row) then
    play_sfx(pid, cfg.error_sfx)
    return true
  end

  play_sfx(pid, cfg.choose_sfx)

  if type(row.on_confirm) == "function" then
    local ok, handled = pcall(row.on_confirm, pid, row, st)
    if ok and handled ~= false then return true end
  end

  if type(st.on_confirm) == "function" then
    pcall(st.on_confirm, pid, row, st)
  end

  return true
end

function MenuAPI.handle_cancel(pid)
  local st = state_by_pid[pid]
  if not st then return false, "not_open" end

  local cancel_sfx = st.cancel_sfx
  if cancel_sfx == nil then
    cancel_sfx = cfg.cancel_sfx
  end

  if cancel_sfx ~= false and cancel_sfx ~= "" then
    play_sfx(pid, cancel_sfx)
  end

  if type(st.on_cancel) == "function" then
    local ok, handled = pcall(st.on_cancel, pid, st)
    if ok and handled == true then return true, "handled" end
  end

  local has_parent = st.parent ~= nil

  MenuAPI.close(pid, {
    keep_frozen = has_parent,
    reopen_parent = has_parent,
    reason = "cancel",
  })

  return true, "closed"
end

local function handle_button(pid, btn, kind)
  local st = state_by_pid[pid]
  if not st then return false end

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

    return true
  end

  if st.kind == "confirm" and (btn == "L" or btn == "R") then
    if kind == "press" or kind == "hold" then
      return move_horizontal_choice(pid, btn == "L" and "yes" or "no")
    end
    return true
  end

  if st.kind == "vertical" and (btn == "U" or btn == "D") then
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
    if not state_by_pid[pid] then return end

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
      elseif name == "Move Left" then
        btn = "L"
      elseif name == "Move Right" then
        btn = "R"
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
        if handle_button(pid, btn, kind) then return end
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
