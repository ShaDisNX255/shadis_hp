-- /server/scripts/ezlibs-custom/cards.lua
-- Cards Gallery (sprites-api)
--
-- This module is meant to be opened from LMenu.

local Cards = {}
_G.Cards = Cards

-- ---------------------------------------------------------------------------
-- net-games framework (sprites-api wrapper)
-- ---------------------------------------------------------------------------

local frame_ok, frame = pcall(require, "scripts/net-games/framework")
if not frame_ok or not frame then
  print("[Cards] ERROR: failed to require scripts/net-games/framework; Cards disabled.")
  return Cards
end


-- ---------------------------------------------------------------------------
-- Displayer for fonts
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
-- helpers + ezmemory
-- ---------------------------------------------------------------------------

local helpers_ok, helpers = pcall(require, "scripts/ezlibs-scripts/helpers")
if not helpers_ok then helpers = nil end

local ezmemory_ok, ezmemory = pcall(require, "scripts/ezlibs-scripts/ezmemory")
if not ezmemory_ok then ezmemory = nil end

-- ---------------------------------------------------------------------------
-- Config knobs
-- ---------------------------------------------------------------------------

local cfg = {
  -- mainui
  mainui_sprite_id = "cards_mainui",
  mainui_texture   = "/server/assets/ui/cards/mainui.png",
  mainui_anim      = "/server/assets/ui/cards/mainui.animation",
  mainui_state     = "mainui",
  mainui_x         = 0,
  mainui_y         = 0,
  mainui_z         = 200,
  mainui_scale     = 2,

  -- list (text)
  visible_lines    = 7,
  list_x           = 108,
  list_y           = 37,
  list_pad_x       = 0,
  list_pad_y       = 0,
  list_row_advance = 16,
  list_z           = 205,
  list_font        = "THICK",
  list_font_scale  = 2.0,
  list_text_id_base = "cards_list_line_",

  -- quantities (text)
  count_x           = 200,
  count_pad_x       = 0,
  count_z           = 205,
  count_font        = "GRADIENT",
  count_font_scale  = 2.0,
  count_text_id_base = "cards_count_line_",

-- List rarity icons (drawn left of the quantity, one per visible line)
list_rarity_texture        = "/server/assets/ui/cards/icons.png",
list_rarity_anim           = "/server/assets/ui/cards/icons.animation",
list_rarity_sprite_id_base = "cards_list_rarity_",
list_rarity_x              = 186,  -- tweak; should be left of your count_x
list_rarity_y_offset       = 0,   -- tweak vertical alignment per row
list_rarity_z              = 205,
list_rarity_scale          = 1.1,

  -- cursor sprite
  cursor_sprite_id = "cards_cursor",
  cursor_texture   = "/server/assets/ui/cards/cursor.png",
  cursor_anim      = "/server/assets/ui/cards/cursor.animation",
  cursor_state     = "cursor",
  cursor_x         = 83,
  cursor_y_offset  = -11,
  cursor_z         = 206,
  cursor_scale     = 2,

  -- chip preview frame
  chip_sprite_id = "cards_chip",
  chip_texture   = "/server/assets/ui/cards/chip.png",
  chip_anim      = "/server/assets/ui/cards/chip.animation",
  chip_state     = "chip",
  chip_x         = 21,
  chip_y         = 22,
  chip_z         = 202,
  chip_scale     = 2,

  -- card art preview (40x40)
  card_art_sprite_id = "cards_art",
  card_art_dir       = "/server/assets/cards/",
  card_art_ext       = ".png",
  card_art_anim      = "/server/assets/cards/card.animation",
  card_art_state     = "TALK",
  card_art_x         = 31,
  card_art_y         = 33,
  card_art_z         = 203,
  card_art_scale     = 2,


  -- rarity icon overlay (drawn on top of preview art)
  -- icons.png/.animation provide states: "C", "R", "SR", "UR", "GR", "GDR"
  rarity_icon_sprite_id    = "cards_rarity",
  rarity_icon_texture      = "/server/assets/ui/cards/icons.png",
  rarity_icon_anim         = "/server/assets/ui/cards/icons.animation",
  -- Position is relative to card_art_x/card_art_y so it follows your preview knobs.
  rarity_icon_offset_x     = -20,
  rarity_icon_offset_y     = -19,
  rarity_icon_z            = 205,
  rarity_icon_scale        = 2,

  -- GDR sparkle flair (drawn on top of the rarity icon; only for GDR cards)
  -- sparkle.png/.animation provides state: "sparkle"
  -- Position is relative to the rarity icon position (so it "sticks" to the icon).
  rarity_sparkle_sprite_id = "cards_rarity_sparkle",
  rarity_sparkle_texture   = "/server/assets/ui/cards/sparkle.png",
  rarity_sparkle_anim      = "/server/assets/ui/cards/sparkle.animation",
  rarity_sparkle_state     = "sparkle",
  rarity_sparkle_offset_x  = -7,
  rarity_sparkle_offset_y  = -7,
  rarity_sparkle_z         = 206,
  rarity_sparkle_scale     = 2,


  -- monster stats (text near preview)
  -- Labels use THICK font, numbers use GRADIENT font.
  -- These are absolute UI coordinates (like list_x/list_y).
  stats_label_x           = 31,
  stats_label_y           = 81,
  stats_label_row_advance = 12,
  stats_label_z           = 206,
  stats_label_font        = "THICK",
  stats_label_scale       = 1.1,
  stats_label_text_atk    = "ATK",
  stats_label_text_def    = "DEF",
  stats_label_def_offset_x = 0,
  stats_label_def_offset_y = 0,


  stats_value_x           = 55,
  stats_value_y           = 81,
  stats_value_row_advance = 12,
  stats_value_z           = 206,
  stats_value_font        = "GRADIENT",
  stats_value_scale       = 1.1,
  stats_missing_text      = "----",

  -- deck builder (gallery/deck toggle)
  deck_size               = 10,
  deck_mem_key            = "miniygo_deck_v2",

  -- text line 1: mode + deck size (top-left)
  mode_text_x             = 4,
  mode_text_y             = 4,
  mode_text_z             = 206,
  mode_text_font          = "THICK",
  mode_text_scale         = 1.1,
  mode_text_id            = "cards_mode_text",

  -- text line 2: in-deck and limits (top-right, 2 lines)
  deckinfo_x              = 143,
  deckinfo_y              = 10,
  deckinfo_row_advance    = 8,
  deckinfo_z              = 206,
  deckinfo_font           = "THICK",
  deckinfo_scale          = 1.0,
  deckinfo_text_id_1      = "cards_deckinfo_1",
  deckinfo_text_id_2      = "cards_deckinfo_2",

  -- description box (bottom-left)
  desc_x                  = 17,
  desc_y                  = 122,
  desc_row_advance        = 8,
  desc_z                  = 206,
  desc_font               = "THICK",
  desc_scale              = 1.0,
  desc_max_lines          = 5,
  desc_wrap_chars         = 20,
  desc_text_id_base       = "cards_desc_",
  stats_value_def_offset_x = 0,
  stats_value_def_offset_y = 0,

  -- scroll wheel indicator
  scroll_sprite_id = "cards_scroll",
  scroll_texture   = "/server/assets/ui/cards/scroll.png",
  scroll_anim      = "/server/assets/ui/cards/scroll.animation",
  scroll_state     = "scroll",
  scroll_x         = 224,
  scroll_top_y     = 27,
  scroll_bottom_y  = 135,
  scroll_z         = 206,
  scroll_scale     = 1.9,

  -- Full-art (F.A.*) combined chip overlay
  -- Drawn on TOP of chip + 40x40 art, but BELOW the rarity icon.
  fa_chip_dir        = "/server/assets/cards/chips/",
  fa_chip_ext        = ".png",
  fa_chip_x          = 21,   -- usually same as chip_x
  fa_chip_y          = 22,   -- usually same as chip_y
  fa_chip_z          = 204,  -- between art_z (203) and rarity_icon_z (205)
  fa_chip_scale      = 2,    -- usually same as chip_scale
  fa_chip_sprite_id_base = "cards_fa_chip_",

  -- behavior
  hide_rarity_tags             = true,
  name_max_chars               = 24,
  scroll_first_repeat_delay_sec = 0.40,
  scroll_repeat_delay_sec       = 0.11,

  card_select_sfx = "/server/assets/sfx/card_select.ogg",
  card_choose_sfx = "/server/assets/sfx/card_choose.ogg",
  card_cancel_sfx = "/server/assets/sfx/card_cancel.ogg",

  -- mainui tint when in deck mode (sprites-api per-object color)
  -- color_mode: 0 = Multiply (recommended for "slight green"), 2 = Colorize (strong recolor)
  mainui_deck_color_mode = 0,
  mainui_deck_r = 210,
  mainui_deck_g = 255,
  mainui_deck_b = 210,

  -- default (gallery) draw color
  mainui_gallery_color_mode = 0,
  mainui_gallery_r = 255,
  mainui_gallery_g = 255,
  mainui_gallery_b = 255,
}

-- ---------------------------------------------------------------------------
-- Utilities
-- ---------------------------------------------------------------------------
local pending_lmenu_open = {}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function sanitize_sprite_id(s)
  s = tostring(s or "")
  s = s:gsub("%W", "_")
  if #s == 0 then s = "x" end
  if #s > 64 then s = s:sub(1, 64) end
  return s
end

local function split_area_id(raw_id)
  local s = tostring(raw_id or "")
  local a, i = s:match("^([^,]+),(.+)$")
  if a and i then return a, i end
  return "default", s
end

local function parse_atk_def_from_text(text)
  if not text or text == "" then return nil, nil end
  text = tostring(text)

  -- Very tolerant patterns: catch "A: 2500", "ATK 2500", etc.
  -- Prefer numbers after A: / D:, but fall back to ATK/DEF tokens.
  local A = text:match("[Aa]%s*[:=]%s*(%d+)")
  local D = text:match("[Dd]%s*[:=]%s*(%d+)")

  if not A then A = text:match("[Aa][Tt][Kk]%s*[:=]?%s*(%d+)") end
  if not D then D = text:match("[Dd][Ee][Ff]%s*[:=]?%s*(%d+)") end

  return tonumber(A), tonumber(D)
end

local function strip_rarity_tag(name)
  if not name then return "" end
  -- remove leading "[X]" including multi-char tags like [GDR]
  local stripped = tostring(name):gsub("^%[[^%]]+%]", "")
  -- also trim whitespace
  stripped = stripped:gsub("^%s+", ""):gsub("%s+$", "")
  return stripped
end

local RARITY_ORDER = {
  C   = 1,
  R   = 2,
  SR  = 3,
  UR  = 4,
  GR  = 5,
  GDR = 6,
}


local VALID_RARITY_STATES = {
  C = true, R = true, SR = true, UR = true, GR = true, GDR = true,
}

local function normalize_rarity_state(tag)
  if tag == nil then return nil end
  tag = tostring(tag):gsub("%s+", "")
  if VALID_RARITY_STATES[tag] then
    return tag
  end
  return nil
end

local function extract_rarity_tag(name)
  if not name then return nil end
  local tag = tostring(name):match("^%[([^%]]+)%]")
  if tag then
    tag = tag:gsub("%s+", "")
  end
  return tag
end

local function rarity_rank_from_name(name)
  local tag = extract_rarity_tag(name)
  if not tag then return 999 end
  return RARITY_ORDER[tag] or 999
end

local function truncate_for_ui(s, max_chars)
  s = tostring(s or "")
  max_chars = max_chars or 24
  if #s <= max_chars then return s end
  return s:sub(1, max_chars - 1) .. "..."
end

-- Net.has_asset can be noisy if spammed; keep a small cache.
local asset_cache = {}
local function has_asset(path)
  if path == nil then return false end
  local cached = asset_cache[path]
  if cached ~= nil then return cached end

  if not (Net and Net.has_asset) then
    asset_cache[path] = true
    return true
  end

  local ok, res = pcall(Net.has_asset, path)
  if ok and res == true then
    asset_cache[path] = true
    return true
  end

  if ok and res == false then
    asset_cache[path] = false
    return false
  end

  -- Unknown/transient; do NOT cache.
  return nil
end

-- ---------------------------------------------------------------------------
-- Inventory snapshot
-- ---------------------------------------------------------------------------

local function get_safe_secret(pid)
  if helpers and type(helpers.get_safe_player_secret) == "function" then
    local ok, res = pcall(helpers.get_safe_player_secret, pid)
    if ok and res ~= nil then
      return res
    end
  end
  return pid
end

local function snapshot_player_cards(pid)
  if not (ezmemory and ezmemory.get_player_memory and ezmemory.get_item_info) then
    return {}
  end

  local secret = get_safe_secret(pid)
  local pmem   = ezmemory.get_player_memory(secret) or {}
  local items  = pmem.items
  if type(items) ~= "table" then
    return {}
  end

  local entries = {}
  for item_id, qty in pairs(items) do
    qty = tonumber(qty) or 0
    if qty > 0 then
      local area, iid = split_area_id(item_id)
      local info = ezmemory.get_item_info(iid)
      if info and info.name then
        -- For stats, prefer the *item info description* (same source custom.lua uses for ATK/DEF),
        -- but fall back to the custom property "Description" if that's the only one populated.
        local desc_prop = ""
        if ezmemory.get_item_custom_property then
          local okd, dp = pcall(ezmemory.get_item_custom_property, area, iid, "Description")
          if okd and dp and dp ~= "" then
            desc_prop = dp
          end
        end

        local desc_info = tostring(info.description or "")
        local desc = desc_info

        -- If the info description doesn't contain stats, but the custom property does, use that.
        local ai, di = parse_atk_def_from_text(desc_info)
        if (ai == nil and di == nil) and desc_prop ~= "" then
          desc = desc_prop
        end

        local raw = tostring(info.name)
        -- Same heuristic as the old card gallery: card item names contain '['
        if raw:find("[", 1, true) ~= nil then
          local base = strip_rarity_tag(raw)
          local rank = rarity_rank_from_name(raw)
          local display = cfg.hide_rarity_tags and base or raw
          display = truncate_for_ui(display, cfg.name_max_chars)
          entries[#entries+1] = {
            item_id      = item_id,
            item_area    = area,
            item_iid     = iid,
            description  = desc,
            description_info = desc_info,
            description_prop = desc_prop,
            raw_name     = raw,
            base_name    = base,
            rarity_rank  = rank,
            qty          = qty,
            display_name = display,
          }
        end
      end
    end
  end

  table.sort(entries, function(a, b)
    if a.rarity_rank ~= b.rarity_rank then
      return a.rarity_rank < b.rarity_rank
    end
    local al = tostring(a.base_name):lower()
    local bl = tostring(b.base_name):lower()
    if al ~= bl then
      return al < bl
    end
    return tostring(a.raw_name) < tostring(b.raw_name)
  end)

  return entries
end

-- build_card_entries was referenced by open_menu; alias it to the snapshot builder.
local function build_card_entries(pid)
  return snapshot_player_cards(pid)
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local state_by_pid = {}

-- ---------------------------------------------------------------------------
-- Deck builder state + persistence (shares the same memory key as custom.lua)
-- ---------------------------------------------------------------------------

local MODE_GALLERY = "gallery"
local MODE_DECK    = "deck"

local function clone_counts(t)
  local out = {}
  if type(t) == "table" then
    for k, v in pairs(t) do
      local n = math.floor(tonumber(v) or 0)
      if n > 0 then
        out[tostring(k)] = n
      end
    end
  end
  return out
end

local function get_player_mem(pid)
  if not (ezmemory and ezmemory.get_player_memory) then
    return {}
  end
  local secret = get_safe_secret(pid)
  local ok, pmem = pcall(ezmemory.get_player_memory, secret)
  if ok and type(pmem) == "table" then
    return pmem
  end
  return {}
end

local function save_player_mem(pid, pmem)
  if not (ezmemory and pmem) then
    return false
  end
  local secret = get_safe_secret(pid)

  if type(ezmemory.set_player_memory) == "function" then
    return pcall(ezmemory.set_player_memory, secret, pmem)
  end
  if type(ezmemory.save_player_memory) == "function" then
    return pcall(ezmemory.save_player_memory, secret, pmem)
  end

  -- some forks only expose get_player_memory; in that case we just can't persist
  return false
end

local function load_deck_counts(pid)
  local pmem = get_player_mem(pid)
  return clone_counts(pmem[cfg.deck_mem_key])
end

local function persist_deck_counts(pid, counts)
  local pmem = get_player_mem(pid)
  pmem[cfg.deck_mem_key] = counts or {}
  save_player_mem(pid, pmem)
end

local function deck_group_for_rarity(tag)
  tag = tostring(tag or "C"):upper()
  if tag == "UR" or tag == "GR" or tag == "GDR" then
    return "URGDR", 1, "Limit GDR/UR/GR 1 MAX"
  elseif tag == "SR" then
    return "SR", 2, "Limit SR 2 MAX"
  elseif tag == "R" then
    return "R", 3, "Limit R 3 MAX"
  end
  return "C", (cfg.deck_size or 10), "Limit C Owned MAX"
end

local function recalc_deck_totals(st)
  local total, urgdr_total, sr_total, r_total = 0, 0, 0, 0
  for item_id, n in pairs(st.deck_counts or {}) do
    n = tonumber(n) or 0
    if n > 0 then
      total = total + n
      local e = st.entry_by_id and st.entry_by_id[item_id]
      local tag = e and extract_rarity_tag(e.raw_name) or "C"
      tag = tostring(tag or "C"):upper()
      if tag == "UR" or tag == "GR" or tag == "GDR" then
        urgdr_total = urgdr_total + n
      elseif tag == "SR" then
        sr_total = sr_total + n
      elseif tag == "R" then
        r_total = r_total + n
      end
    end
  end
  st.deck_total = total
  st.deck_urgdr_total = urgdr_total
  st.deck_sr_total = sr_total
  st.deck_r_total = r_total
end

local function build_deck_entries(st)
  local out = {}
  for item_id, n in pairs(st.deck_counts or {}) do
    n = tonumber(n) or 0
    if n > 0 then
      local base = st.entry_by_id and st.entry_by_id[item_id]
      if base then
        local copy = {}
        for k, v in pairs(base) do
          copy[k] = v
        end
        copy.qty = n
        out[#out+1] = copy
      end
    end
  end

  table.sort(out, function(a, b)
    if a.rarity_rank ~= b.rarity_rank then
      return a.rarity_rank < b.rarity_rank
    end
    local al = tostring(a.base_name):lower()
    local bl = tostring(b.base_name):lower()
    if al ~= bl then
      return al < bl
    end
    return tostring(a.raw_name) < tostring(b.raw_name)
  end)

  return out
end

local function sanitize_deck_counts(pid, st)
  -- 1) drop missing, clamp to owned
  local cleaned = {}
  for item_id, n in pairs(st.deck_counts or {}) do
    n = math.floor(tonumber(n) or 0)
    if n > 0 then
      local e = st.entry_by_id and st.entry_by_id[item_id]
      local owned = e and (tonumber(e.qty) or 0) or 0
      if owned > 0 then
        if n > owned then n = owned end
        if n > 0 then cleaned[item_id] = n end
      end
    end
  end
  st.deck_counts = cleaned

  -- 2) enforce rarity caps (same as custom.lua deck editor)
  local function apply_cap(group, cap)
    local ids = {}
    for item_id, n in pairs(st.deck_counts) do
      if n > 0 then
        local e = st.entry_by_id and st.entry_by_id[item_id]
        local tag = e and extract_rarity_tag(e.raw_name) or "C"
        local g = deck_group_for_rarity(tag)
        if g == group then
          ids[#ids+1] = item_id
        end
      end
    end

    table.sort(ids, function(a, b)
      local ea = st.entry_by_id[a]
      local eb = st.entry_by_id[b]
      local ra = ea and ea.rarity_rank or 999
      local rb = eb and eb.rarity_rank or 999
      if ra ~= rb then return ra < rb end
      local al = tostring(ea and ea.base_name or ""):lower()
      local bl = tostring(eb and eb.base_name or ""):lower()
      if al ~= bl then return al < bl end
      return tostring(ea and ea.raw_name or "") < tostring(eb and eb.raw_name or "")
    end)

    local remaining = cap
    for _, item_id in ipairs(ids) do
      local n = st.deck_counts[item_id] or 0
      if remaining <= 0 then
        st.deck_counts[item_id] = nil
      else
        if n > remaining then
          st.deck_counts[item_id] = remaining
          remaining = 0
        else
          remaining = remaining - n
        end
      end
    end
  end

  apply_cap("URGDR", 1)
  apply_cap("SR", 2)
  apply_cap("R", 3)

  -- 3) enforce overall deck size
  recalc_deck_totals(st)
  local deck_size = cfg.deck_size or 10
  if st.deck_total > deck_size then
    -- keep rarer cards first if we have to trim
    local ids = {}
    for item_id, n in pairs(st.deck_counts) do
      if (tonumber(n) or 0) > 0 then
        ids[#ids+1] = item_id
      end
    end

    table.sort(ids, function(a, b)
      local ea = st.entry_by_id[a]
      local eb = st.entry_by_id[b]
      local ra = ea and ea.rarity_rank or 999
      local rb = eb and eb.rarity_rank or 999
      if ra ~= rb then return ra > rb end -- descending = rarer first
      local al = tostring(ea and ea.base_name or ""):lower()
      local bl = tostring(eb and eb.base_name or ""):lower()
      if al ~= bl then return al < bl end
      return tostring(ea and ea.raw_name or "") < tostring(eb and eb.raw_name or "")
    end)

    local remaining = deck_size
    local new_counts = {}
    for _, item_id in ipairs(ids) do
      if remaining <= 0 then break end
      local n = math.floor(tonumber(st.deck_counts[item_id]) or 0)
      if n > 0 then
        if n > remaining then n = remaining end
        new_counts[item_id] = n
        remaining = remaining - n
      end
    end
    st.deck_counts = new_counts
  end

  recalc_deck_totals(st)
  persist_deck_counts(pid, st.deck_counts)
end

local function get_selected_entry(st)
  local idx = tonumber(st.cursor_index) or 0
  if idx <= 0 then return nil end
  return st.entries and st.entries[idx] or nil
end

local function set_mode_only(st, mode)
  if mode ~= MODE_GALLERY and mode ~= MODE_DECK then
    mode = MODE_GALLERY
  end
  st.mode = mode
  st.armed_item_id = nil
  if mode == MODE_GALLERY then
    st.entries = st.gallery_entries or {}
  else
    st.entries = build_deck_entries(st)
  end
  st.cursor_index = (#st.entries > 0 and 1) or 0
  st.top_index = 1
end

function Cards.is_open(pid)
  return state_by_pid[pid] ~= nil
end

local function get_state(pid)
  return state_by_pid[pid]
end

local function total_entries_for(pid)
  local st = state_by_pid[pid]
  if not st or type(st.entries) ~= "table" then return 0 end
  return #st.entries
end

local function safe_remove(sprite_id, pid)
  if frame and frame.remove_ui_element and sprite_id then
    pcall(frame.remove_ui_element, sprite_id, pid)
  end
end

local function safe_add(sprite_id, pid, texture, anim, state, x, y, z, sx, sy)
  if not (frame and frame.add_ui_element) then return end
  frame.add_ui_element(sprite_id, pid, texture, anim, state, x, y, z, sx, sy)
end

local function safe_set_state(sprite_id, pid, state)
  if not (frame and sprite_id and state) then return false end

  -- Different net-games forks name this slightly differently.
  local fns = {
    "update_ui_state",
    "update_ui_animation_state",
    "update_ui_anim_state",
    "set_ui_state",
    "set_ui_animation_state",
  }

  for _, fn in ipairs(fns) do
    local f = frame[fn]
    if type(f) == "function" then
      if pcall(f, sprite_id, pid, state) then
        return true
      end
    end
  end

  return false
end

local function is_full_art_base(base)
  base = tostring(base or "")
  return base:sub(1, 4) == "F.A."
end

local function fa_chip_path_for_base(base)
  return (cfg.fa_chip_dir or "/server/assets/cards/chips/") .. tostring(base or "") .. (cfg.fa_chip_ext or ".png")
end

local function fa_chip_sprite_id_for_base(base)
  -- sanitize AFTER prefix+base so length stays within sanitize_sprite_id limits
  return sanitize_sprite_id((cfg.fa_chip_sprite_id_base or "cards_fa_chip_") .. tostring(base or ""))
end

local function clear_fa_chip_overlay(pid)
  local st = state_by_pid[pid]
  if st and st.fa_chip_sprite_id then
    safe_remove(st.fa_chip_sprite_id, pid)
    st.fa_chip_sprite_id = nil
    st.fa_chip_path = nil
  end
end

local function update_fa_chip_overlay(pid, base)
  local st = state_by_pid[pid]
  if not st then return end

  if not is_full_art_base(base) then
    clear_fa_chip_overlay(pid)
    return
  end

  local path = fa_chip_path_for_base(base)
  local exists = has_asset(path)
  if exists == false then
    -- Missing asset -> no overlay (keeps gallery stable)
    clear_fa_chip_overlay(pid)
    return
  end

  local new_id = fa_chip_sprite_id_for_base(base)

  -- If switching between FA cards, remove the previous overlay sprite id
  if st.fa_chip_sprite_id and st.fa_chip_sprite_id ~= new_id then
    safe_remove(st.fa_chip_sprite_id, pid)
  end

  -- If already showing the correct overlay, do nothing
  if st.fa_chip_sprite_id == new_id and st.fa_chip_path == path then
    return
  end

  -- Draw overlay (do NOT remove+add same id; we removed old if different)
  safe_add(
    new_id,
    pid,
    path,
    cfg.chip_anim,
    cfg.chip_state,
    cfg.fa_chip_x or cfg.chip_x,
    cfg.fa_chip_y or cfg.chip_y,
    cfg.fa_chip_z or 204,
    cfg.fa_chip_scale or cfg.chip_scale,
    cfg.fa_chip_scale or cfg.chip_scale
  )

  st.fa_chip_sprite_id = new_id
  st.fa_chip_path = path
end

-- ---------------------------------------------------------------------------
-- Sprite UI drawing
-- ---------------------------------------------------------------------------

local function draw_mainui(pid)
  safe_remove(cfg.mainui_sprite_id, pid)
  safe_add(
    cfg.mainui_sprite_id,
    pid,
    cfg.mainui_texture,
    cfg.mainui_anim,
    cfg.mainui_state,
    cfg.mainui_x,
    cfg.mainui_y,
    cfg.mainui_z,
    cfg.mainui_scale,
    cfg.mainui_scale
  )
end

local function draw_cursor(pid)
  safe_remove(cfg.cursor_sprite_id, pid)
  safe_add(
    cfg.cursor_sprite_id,
    pid,
    cfg.cursor_texture,
    cfg.cursor_anim,
    cfg.cursor_state,
    cfg.cursor_x,
    cfg.list_y + cfg.cursor_y_offset,
    cfg.cursor_z,
    cfg.cursor_scale,
    cfg.cursor_scale
  )
end

local function draw_chip(pid)
  safe_remove(cfg.chip_sprite_id, pid)
  safe_add(
    cfg.chip_sprite_id,
    pid,
    cfg.chip_texture,
    cfg.chip_anim,
    cfg.chip_state,
    cfg.chip_x,
    cfg.chip_y,
    cfg.chip_z,
    cfg.chip_scale,
    cfg.chip_scale
  )
end

local function draw_scrollwheel(pid, y)
  safe_remove(cfg.scroll_sprite_id, pid)
  safe_remove(cfg.rarity_icon_sprite_id, pid)
  safe_remove(cfg.rarity_sparkle_sprite_id, pid)
  safe_add(
    cfg.scroll_sprite_id,
    pid,
    cfg.scroll_texture,
    cfg.scroll_anim,
    cfg.scroll_state,
    cfg.scroll_x,
    y,
    cfg.scroll_z,
    cfg.scroll_scale,
    cfg.scroll_scale
  )
end


-- ---------------------------------------------------------------------------
-- Text drawing helpers
-- ---------------------------------------------------------------------------

local function ensure_player_fonts(pid)
  -- Prefer the same FontSystem path cosmetics/LMenu use (stable across forks)
  if Displayer and Displayer._subsystems and Displayer._subsystems.FontSystem then
    local fs = Displayer._subsystems.FontSystem
    if fs.player_fonts and not fs.player_fonts[pid] and fs.setupPlayerFonts then
      pcall(fs.setupPlayerFonts, fs, pid)
    end
    if fs.player_fonts and fs.player_fonts[pid] then
      return true
    end
  end

  -- Fallback for older displayer versions
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

local function draw_text(pid, text, x, y, font, scale, z, id)
  if not (Displayer and Displayer.Font and Displayer.Font.drawTextWithId) then
    return
  end

  -- Displayer uses "screen pixels", where 1 logical unit = 2 pixels.
  local sx = math.floor((x or 0) * 2)
  local sy = math.floor((y or 0) * 2)

  -- Different net-games forks expose Font.* as either plain functions or methods.
  local ok = pcall(Displayer.Font.drawTextWithId, pid, text, sx, sy, font, scale, z, id)
  if not ok then
    ok = pcall(Displayer.Font.drawTextWithId, Displayer.Font, pid, text, sx, sy, font, scale, z, id)
  end

  if not ok and font ~= "WHITE" then
    pcall(Displayer.Font.drawTextWithId, pid, text, sx, sy, "WHITE", scale, z, id)
    pcall(Displayer.Font.drawTextWithId, Displayer.Font, pid, text, sx, sy, "WHITE", scale, z, id)
  end
end

local function clear_list_text(pid)
  for i = 1, cfg.visible_lines do
    erase_text(pid, cfg.list_text_id_base .. tostring(i))
    erase_text(pid, cfg.count_text_id_base .. tostring(i))
  end
end

local STAT_ID_LBL_ATK = "cards_stat_label_atk"
local STAT_ID_LBL_DEF = "cards_stat_label_def"
local STAT_ID_VAL_ATK = "cards_stat_value_atk"
local STAT_ID_VAL_DEF = "cards_stat_value_def"


-- ---------------------------------------------------------------------------
-- Mode/deck/description UI
-- ---------------------------------------------------------------------------

local function clear_deck_ui_text(pid)
  erase_text(pid, cfg.mode_text_id)
  erase_text(pid, cfg.deckinfo_text_id_1)
  erase_text(pid, cfg.deckinfo_text_id_2)

  local max_lines = cfg.desc_max_lines or 5
  for i = 1, max_lines do
    erase_text(pid, (cfg.desc_text_id_base or "cards_desc_") .. tostring(i))
  end
end

local function wrap_text_lines(text, max_chars, max_lines)
  text = tostring(text or "")
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")

  max_chars = tonumber(max_chars) or 36
  max_lines = tonumber(max_lines) or 5

  local out = {}

  for para in text:gmatch("[^\n]+") do
    local line = ""
    for word in para:gmatch("%S+") do
      if line == "" then
        line = word
      elseif #line + 1 + #word <= max_chars then
        line = line .. " " .. word
      else
        out[#out+1] = line
        line = word
        if #out >= max_lines then
          return out
        end
      end
    end

    if line ~= "" then
      out[#out+1] = line
      if #out >= max_lines then
        return out
      end
    end
  end

  return out
end

local function trim_desc_for_box(text)
  text = tostring(text or "")

  -- Cut anything starting at " - A:" (tolerate minor spacing/case)
  local i = text:find("%s%-%s*[Aa]%s*:", 1)
  if i then
    text = text:sub(1, i - 1)
  end

  -- Trim trailing whitespace
  text = text:gsub("%s+$", "")
  return text
end

local function draw_description_box(pid, text)
  -- NEW: show only the portion before " - A:"
  text = trim_desc_for_box(text)

  local max_lines = cfg.desc_max_lines or 5
  local lines = wrap_text_lines(text, cfg.desc_wrap_chars or 36, max_lines)

  for i = 1, max_lines do
    local id = (cfg.desc_text_id_base or "cards_desc_") .. tostring(i)
    erase_text(pid, id)
  end

  local x = cfg.desc_x or 0
  local y = cfg.desc_y or 0
  local dy = cfg.desc_row_advance or 12

  for i, line in ipairs(lines) do
    if i > max_lines then break end
    draw_text(
      pid,
      line,
      x,
      y + (i - 1) * dy,
      cfg.desc_font or "THICK",
      cfg.desc_scale or 1.0,
      cfg.desc_z or 206,
      (cfg.desc_text_id_base or "cards_desc_") .. tostring(i)
    )
  end
end

local function update_mode_deck_texts(pid)
  local st = state_by_pid[pid]
  if not st then return end

  ensure_player_fonts(pid)

  -- IMPORTANT: erase before redraw, otherwise Displayer can leave old characters behind
  erase_text(pid, cfg.mode_text_id)
  erase_text(pid, cfg.deckinfo_text_id_1)
  erase_text(pid, cfg.deckinfo_text_id_2)

  local deck_total = tonumber(st.deck_total) or 0
  local deck_size  = cfg.deck_size or 10
  local mode_name  = (st.mode == MODE_DECK) and "DECK" or "GALLERY"

  draw_text(
    pid,
    string.format("%s - Deck %d/%d", mode_name, deck_total, deck_size),
    cfg.mode_text_x or 0,
    cfg.mode_text_y or 0,
    cfg.mode_text_font or "THICK",
    cfg.mode_text_scale or 1.1,
    cfg.mode_text_z or 206,
    cfg.mode_text_id
  )

  local entry = get_selected_entry(st)
  local in_deck = 0
  local cap = deck_size
  local limit_label = ""

  if entry and entry.item_id then
    in_deck = tonumber(st.deck_counts and st.deck_counts[entry.item_id]) or 0
    local base = (st.entry_by_id and st.entry_by_id[entry.item_id]) or entry
    local tag = base and extract_rarity_tag(base.raw_name) or "C"
    local _, group_cap, label = deck_group_for_rarity(tag)
    cap = group_cap or cap
    limit_label = label or ""
  end

  draw_text(
    pid,
    string.format("In Deck: %d/%d", in_deck, cap),
    cfg.deckinfo_x or 0,
    cfg.deckinfo_y or 0,
    cfg.deckinfo_font or "THICK",
    cfg.deckinfo_scale or 1.2,
    cfg.deckinfo_z or 206,
    cfg.deckinfo_text_id_1
  )

  -- line 2: only draw if we have something; it's already erased above so no leftovers
  if limit_label ~= "" then
    draw_text(
      pid,
      limit_label,
      cfg.deckinfo_x or 0,
      (cfg.deckinfo_y or 0) + (cfg.deckinfo_row_advance or 12),
      cfg.deckinfo_font or "THICK",
      cfg.deckinfo_scale or 1.2,
      cfg.deckinfo_z or 206,
      cfg.deckinfo_text_id_2
    )
  end

  -- description box already erases its own lines each call
  draw_description_box(pid, entry and entry.description or "")
end

local function arm_card_for_pid(pid, raw_name)
  local api = rawget(_G, "card_overworld_api")
  if not api then return false end
  if type(api.arm_card) == "function" then
    local ok, res = pcall(api.arm_card, pid, raw_name)
    return ok and res ~= false
  end
  return false
end

local function deck_can_add(st, item_id)
  local deck_size = cfg.deck_size or 10
  if (tonumber(st.deck_total) or 0) >= deck_size then
    return false, "Deck is full."
  end

  local base = st.entry_by_id and st.entry_by_id[item_id]
  if not base then
    return false, "You don't own this card."
  end

  local owned = tonumber(base.qty) or 0
  local in_deck = tonumber(st.deck_counts and st.deck_counts[item_id]) or 0

  if owned <= 0 then
    return false, "You don't own this card."
  end
  if in_deck >= owned then
    return false, "No extra copies owned."
  end

  local tag = extract_rarity_tag(base.raw_name) or "C"
  local group, cap = deck_group_for_rarity(tag)

  if group == "URGDR" then
    if in_deck >= 1 then
      return false, "Deck limit: GDR/UR/GR 1 MAX."
    end
    if (tonumber(st.deck_urgdr_total) or 0) >= cap then
      return false, "Deck limit: GDR/UR/GR 1 MAX."
    end
  elseif group == "SR" then
    if (tonumber(st.deck_sr_total) or 0) >= cap then
      return false, "Deck limit: SR 2 MAX."
    end
  elseif group == "R" then
    if (tonumber(st.deck_r_total) or 0) >= cap then
      return false, "Deck limit: R 3 MAX."
    end
  end

  return true
end

local function play_deck_error_sfx(pid)
  local path = cfg.deck_error_sfx or "/server/assets/sfx/card_error.ogg"

  if Net and Net.provide_asset_for_player then
    pcall(Net.provide_asset_for_player, pid, path)
  end

  if Net and Net.play_sound_for_player then
    pcall(Net.play_sound_for_player, pid, path)
  end
end

local function provide_sfx_once(pid, path)
  local st = state_by_pid[pid]
  if not st then return end
  st._provided_sfx = st._provided_sfx or {}

  if st._provided_sfx[path] then return end
  st._provided_sfx[path] = true

  if Net and Net.provide_asset_for_player then
    pcall(Net.provide_asset_for_player, pid, path)
  end
end

local function play_sfx(pid, path)
  if not path or path == "" then return end
  provide_sfx_once(pid, path)

  if Net and Net.play_sound_for_player then
    pcall(Net.play_sound_for_player, pid, path)
  end
end

local function play_card_select_sfx(pid)
  play_sfx(pid, cfg.card_select_sfx or "/server/assets/sfx/card_select.ogg")
end

local function play_card_choose_sfx(pid)
  play_sfx(pid, cfg.card_choose_sfx or "/server/assets/sfx/card_choose.ogg")
end

local function play_card_cancel_sfx(pid)
  play_sfx(pid, cfg.card_cancel_sfx or "/server/assets/sfx/card_cancel.ogg")
end

local function deck_add_one(pid, st, item_id)
  local ok = deck_can_add(st, item_id)
  if not ok then
    -- No message spam; just a generic error sfx.
    play_deck_error_sfx(pid)
    return false
  end

  st.deck_counts[item_id] = (st.deck_counts[item_id] or 0) + 1

  -- Keep totals correct and persist to player memory
  recalc_deck_totals(st)
  persist_deck_counts(pid, st.deck_counts)

  play_card_choose_sfx(pid)
  return true
end

local function deck_remove_one(pid, st, item_id)
  local cur = tonumber(st.deck_counts and st.deck_counts[item_id]) or 0
  if cur <= 0 then
    return false
  end

  cur = cur - 1
  if cur <= 0 then
    st.deck_counts[item_id] = nil
  else
    st.deck_counts[item_id] = cur
  end

  recalc_deck_totals(st)
  persist_deck_counts(pid, st.deck_counts)

  -- NEW: play cancel sfx on successful removal
  play_card_cancel_sfx(pid)

  return true
end

local function clear_stats_text(pid)
  erase_text(pid, STAT_ID_LBL_ATK)
  erase_text(pid, STAT_ID_LBL_DEF)
  erase_text(pid, STAT_ID_VAL_ATK)
  erase_text(pid, STAT_ID_VAL_DEF)

  local st = state_by_pid[pid]
  if st then
    st.stats_item_id = nil
    st.stats_atk = nil
    st.stats_def = nil
  end
end

local function draw_stats_text(pid, atk, def)
  ensure_player_fonts(pid)

  -- IMPORTANT: erase before redraw so old trailing digits don't remain (e.g. 3000 -> 300)
  erase_text(pid, STAT_ID_LBL_ATK)
  erase_text(pid, STAT_ID_LBL_DEF)
  erase_text(pid, STAT_ID_VAL_ATK)
  erase_text(pid, STAT_ID_VAL_DEF)

  local ly = cfg.stats_label_y or 0
  local lrow = cfg.stats_label_row_advance or 12
  local vx = cfg.stats_value_x or 0
  local vy = cfg.stats_value_y or 0
  local vrow = cfg.stats_value_row_advance or lrow

  draw_text(
    pid,
    cfg.stats_label_text_atk or "ATK",
    cfg.stats_label_x or 0,
    ly,
    cfg.stats_label_font or "THICK",
    cfg.stats_label_scale or 2.0,
    cfg.stats_label_z or 206,
    STAT_ID_LBL_ATK
  )

  draw_text(
    pid,
    cfg.stats_label_text_def or "DEF",
    (cfg.stats_label_x or 0) + (cfg.stats_label_def_offset_x or 0),
    ly + lrow + (cfg.stats_label_def_offset_y or 0),
    cfg.stats_label_font or "THICK",
    cfg.stats_label_scale or 2.0,
    cfg.stats_label_z or 206,
    STAT_ID_LBL_DEF
  )

  local miss = cfg.stats_missing_text or "----"
  local atk_text = (atk ~= nil) and tostring(atk) or miss
  local def_text = (def ~= nil) and tostring(def) or miss

  draw_text(
    pid,
    atk_text,
    vx,
    vy,
    cfg.stats_value_font or "GRADIENT",
    cfg.stats_value_scale or 2.0,
    cfg.stats_value_z or 206,
    STAT_ID_VAL_ATK
  )

  draw_text(
    pid,
    def_text,
    vx + (cfg.stats_value_def_offset_x or 0),
    vy + vrow + (cfg.stats_value_def_offset_y or 0),
    cfg.stats_value_font or "GRADIENT",
    cfg.stats_value_scale or 2.0,
    cfg.stats_value_z or 206,
    STAT_ID_VAL_DEF
  )
end

local function update_stats_text(pid, entry)
  local st = state_by_pid[pid]
  if not st then return end

  if not entry then
    clear_stats_text(pid)
    return
  end
  local desc_info = tostring(entry.description_info or "")
  local desc_prop = tostring(entry.description_prop or "")

  -- Prefer stats parsed from the item-info description (prevents the "300 -> 3000" issue when
  -- some custom-property descriptions are scaled differently), then fall back.
  local atk, def = parse_atk_def_from_text(desc_info)
  if atk == nil and def == nil then
    atk, def = parse_atk_def_from_text(desc_prop)
  end
  if atk == nil and def == nil then
    local desc = tostring(entry.description or "")
    atk, def = parse_atk_def_from_text(desc)
  end

  local key = tostring(entry.item_id or "")
  st.stats_item_id = key
  st.stats_atk = atk
  st.stats_def = def

  draw_stats_text(pid, atk, def)
end

-- ----------------------------
-- Sprites-API helpers
-- ----------------------------
local function spr_provide(pid, path)
  if Net and Net.provide_asset_for_player and path and path ~= "" then
    pcall(Net.provide_asset_for_player, pid, path)
  end
end

local function spr_alloc_once(st, pid, sprite_id, texture, anim, default_state)
  if not (Net and Net.player_alloc_sprite) then return false end
  st._spr_alloc = st._spr_alloc or {}
  if st._spr_alloc[sprite_id] then return true end

  spr_provide(pid, texture)
  spr_provide(pid, anim)

  local ok = pcall(Net.player_alloc_sprite, pid, sprite_id, {
    texture_path = texture,
    anim_path = anim,
    anim_state = default_state or "C",
  })

  if ok then st._spr_alloc[sprite_id] = true end
  return ok
end

local function spr_draw(pid, sprite_id, obj_id, x, y, z, scale, state)
  if not (Net and Net.player_draw_sprite) then return false end
  -- UI coords in your script are “logical”, like Displayer text; multiply by 2 to match UI pixels.
  -- (Your draw_text does this, and framework.move_ui_element does X*2/Y*2 too.)【turn69file13†cards.lua†L62-L66】【turn69file4†framework.lua†L58-L65】
  local ok = pcall(Net.player_draw_sprite, pid, sprite_id, {
    id = obj_id,
    x = math.floor((x or 0) * 2),
    y = math.floor((y or 0) * 2),
    z = z or 0,
    sx = scale or 2,
    sy = scale or 2,
    anim_state = state,
  })
  return ok
end

local function spr_erase(pid, obj_id)
  if Net and Net.player_erase_sprite and obj_id then
    pcall(Net.player_erase_sprite, pid, obj_id)
  end
end

local function spr_dealloc(st, pid, sprite_id)
  if Net and Net.player_dealloc_sprite and sprite_id then
    pcall(Net.player_dealloc_sprite, pid, sprite_id)
  end
  if st and st._spr_alloc then st._spr_alloc[sprite_id] = nil end
end

-- ---------------------------------------------------------------------------
-- List rendering
-- ---------------------------------------------------------------------------

local function update_cursor_position(pid)
  local st = state_by_pid[pid]
  if not st then return end

  local line = (st.cursor_index or 1) - (st.top_index or 1) + 1
  line = clamp(line, 1, cfg.visible_lines)

  local x = cfg.cursor_x
  local y = cfg.list_y + (line - 1) * cfg.list_row_advance + cfg.cursor_y_offset

  if frame.update_ui_position then
    pcall(frame.update_ui_position, cfg.cursor_sprite_id, pid, x, y, cfg.cursor_z)
  else
    -- Fallback: rebuild cursor
    draw_cursor(pid)
    pcall(frame.update_ui_position, cfg.cursor_sprite_id, pid, x, y, cfg.cursor_z)
  end
end

local function compute_scrollwheel_y(pid)
  local st = state_by_pid[pid]
  local total = total_entries_for(pid)
  if not st or total <= 0 then
    return cfg.scroll_top_y
  end

  local visible = cfg.visible_lines
  local max_top = math.max(1, total - visible + 1)
  local top = clamp(st.top_index or 1, 1, max_top)

  if max_top <= 1 then
    return cfg.scroll_top_y
  end

  local progress = (top - 1) / (max_top - 1)
  local y = cfg.scroll_top_y + progress * (cfg.scroll_bottom_y - cfg.scroll_top_y)
  return math.floor(y + 0.5)
end

local function update_scrollwheel(pid)
  local y = compute_scrollwheel_y(pid)
  if frame.update_ui_position then
    local ok = pcall(frame.update_ui_position, cfg.scroll_sprite_id, pid, cfg.scroll_x, y, cfg.scroll_z)
    if ok then return end
  end
  -- fallback: rebuild
  draw_scrollwheel(pid, y)
end

local function list_rarity_ids(line_index)
  local sid = (cfg.list_rarity_sprite_id_base or "cards_list_rarity_") .. tostring(line_index)
  return sid, (sid .. "_obj")
end

local function draw_list_rarity_icon(pid, line_index, raw_name, row_y)
  local st = state_by_pid[pid]
  if not st then return end

  local sprite_id, obj_id = list_rarity_ids(line_index)

  local tag = extract_rarity_tag(raw_name)
  local state = normalize_rarity_state(tag)

  -- If no valid rarity, just erase the object (leave allocation alone for reuse)
  if not state then
    spr_erase(pid, obj_id)
    return
  end

  local x = cfg.list_rarity_x or 0
  local y = (row_y or 0) + (cfg.list_rarity_y_offset or 0)
  local z = cfg.list_rarity_z or 205
  local sc = cfg.list_rarity_scale or 2

  -- allocate once per player per line sprite_id
  spr_alloc_once(st, pid, sprite_id, cfg.list_rarity_texture, cfg.list_rarity_anim, state)

  -- always draw (safe + simple; you can optimize later by caching per-line state)
  spr_draw(pid, sprite_id, obj_id, x, y, z, sc, state)
end

local function redraw_visible_rows(pid)
  local st = state_by_pid[pid]
  if not st then return end

  ensure_player_fonts(pid)

  clear_list_text(pid)

  local entries = st.entries or {}
  local total = #entries
  local top = st.top_index or 1

  for i = 1, cfg.visible_lines do
    local idx = top + i - 1
    local y = cfg.list_y + (i - 1) * cfg.list_row_advance

    if idx <= total then
      local e = entries[idx]
      local name = e and e.display_name or ""
      local qty  = e and (tonumber(e.qty) or 0) or 0

      draw_list_rarity_icon(pid, i, e and e.raw_name or "", y)

      draw_text(
        pid,
        name,
        cfg.list_x + cfg.list_pad_x,
        y + cfg.list_pad_y,
        cfg.list_font,
        cfg.list_font_scale,
        cfg.list_z,
        cfg.list_text_id_base .. tostring(i)
      )

      draw_text(
        pid,
        string.format("%03d", qty),
        cfg.count_x + cfg.count_pad_x,
        y + cfg.list_pad_y,
        cfg.count_font,
        cfg.count_font_scale,
        cfg.count_z,
        cfg.count_text_id_base .. tostring(i)
      )
    else
      -- NEW: no entry in this line, erase the old rarity icon so it doesn't linger
      draw_list_rarity_icon(pid, i, nil, y)
    end
  end

  update_cursor_position(pid)
  update_scrollwheel(pid)
end


-- ---------------------------------------------------------------------------
-- Rarity icon overlay (on top of preview art)
-- ---------------------------------------------------------------------------

local function rarity_icon_xy()
  return cfg.card_art_x + (cfg.rarity_icon_offset_x or 0),
         cfg.card_art_y + (cfg.rarity_icon_offset_y or 0)
end

local function rarity_sparkle_xy()
  local ix, iy = rarity_icon_xy()
  return ix + (cfg.rarity_sparkle_offset_x or 0),
         iy + (cfg.rarity_sparkle_offset_y or 0)
end

local function clear_rarity_sparkle(pid)
  safe_remove(cfg.rarity_sparkle_sprite_id, pid)
  local st = state_by_pid[pid]
  if st then
    st.gdr_sparkle_on = false
  end
end

local function draw_rarity_sparkle(pid)
  local x, y = rarity_sparkle_xy()
  safe_remove(cfg.rarity_sparkle_sprite_id, pid)
  safe_add(
    cfg.rarity_sparkle_sprite_id,
    pid,
    cfg.rarity_sparkle_texture,
    cfg.rarity_sparkle_anim,
    cfg.rarity_sparkle_state,
    x,
    y,
    cfg.rarity_sparkle_z,
    cfg.rarity_sparkle_scale,
    cfg.rarity_sparkle_scale
  )
end

local function update_rarity_sparkle(pid, rarity_state)
  local st = state_by_pid[pid]
  if not st then return end

  local want = (rarity_state == "GDR")

  if not want then
    if st.gdr_sparkle_on then
      clear_rarity_sparkle(pid)
    end
    return
  end

  -- Want sparkle: draw once, then just keep it positioned (in case knobs changed)
  if not st.gdr_sparkle_on then
    draw_rarity_sparkle(pid)
    st.gdr_sparkle_on = true
  end

  local x, y = rarity_sparkle_xy()
  if frame.update_ui_position then
    pcall(frame.update_ui_position, cfg.rarity_sparkle_sprite_id, pid, x, y, cfg.rarity_sparkle_z)
  end
end

local function clear_rarity_icon(pid)
  safe_remove(cfg.rarity_icon_sprite_id, pid)
  clear_rarity_sparkle(pid)
  local st = state_by_pid[pid]
  if st then
    st.current_rarity_state = nil
  end
end

local function draw_rarity_icon(pid, state)
  local x, y = rarity_icon_xy()
  safe_remove(cfg.rarity_icon_sprite_id, pid)
  safe_add(
    cfg.rarity_icon_sprite_id,
    pid,
    cfg.rarity_icon_texture,
    cfg.rarity_icon_anim,
    state,
    x,
    y,
    cfg.rarity_icon_z,
    cfg.rarity_icon_scale,
    cfg.rarity_icon_scale
  )
end

local function update_rarity_icon(pid, raw_tag)
  local st = state_by_pid[pid]
  if not st then return end

  local state = normalize_rarity_state(raw_tag)

  -- Hide if unrecognized/no tag
  if not state then
    if st.current_rarity_state ~= nil or st.gdr_sparkle_on then
      clear_rarity_icon(pid)
    end
    return
  end

  local x, y = rarity_icon_xy()

  -- First time draw
  if st.current_rarity_state == nil then
    draw_rarity_icon(pid, state)
    st.current_rarity_state = state
    update_rarity_sparkle(pid, state)
    return
  end

  -- Same state: just keep it positioned (in case knobs changed)
  if st.current_rarity_state == state then
    if frame.update_ui_position then
      pcall(frame.update_ui_position, cfg.rarity_icon_sprite_id, pid, x, y, cfg.rarity_icon_z)
    end
    update_rarity_sparkle(pid, state)
    return
  end

  -- Try to swap animation state without rebuilding, else rebuild.
  if safe_set_state(cfg.rarity_icon_sprite_id, pid, state) then
    st.current_rarity_state = state
    if frame.update_ui_position then
      pcall(frame.update_ui_position, cfg.rarity_icon_sprite_id, pid, x, y, cfg.rarity_icon_z)
    end
    update_rarity_sparkle(pid, state)
    return
  end

  draw_rarity_icon(pid, state)
  st.current_rarity_state = state
  update_rarity_sparkle(pid, state)
end

-- ---------------------------------------------------------------------------
-- Preview art
-- ---------------------------------------------------------------------------

local function clear_preview_art(pid)
  local st = state_by_pid[pid]
  if not st then
    safe_remove(cfg.card_art_sprite_id, pid)
    return
  end

  if st.preview_art_sprite_id then
    safe_remove(st.preview_art_sprite_id, pid)
  end

  -- legacy/compat: ensure base id is not left behind
  safe_remove(cfg.card_art_sprite_id, pid)

  st.preview_art_sprite_id = nil
  st.current_art_path = nil
end

local function draw_preview_art(pid, sprite_id, art_path)
  -- Allow old call style: draw_preview_art(pid, art_path)
  if art_path == nil then
    art_path = sprite_id
    sprite_id = nil
  end

  sprite_id = sprite_id or cfg.card_art_sprite_id or "cards_art"
  art_path = art_path and tostring(art_path) or ""

  -- If we still don't have a valid path, don't try to draw.
  if art_path == "" then
    return
  end

  safe_remove(sprite_id, pid)
  safe_add(
    sprite_id,
    pid,
    art_path,
    cfg.card_art_anim or "",
    cfg.card_art_state or "",
    cfg.card_art_x or 0,
    cfg.card_art_y or 0,
    cfg.card_art_z or 0,
    cfg.card_art_scale or 1,
    cfg.card_art_scale or 1
  )
end

local function update_preview(pid)
  local st = state_by_pid[pid]
  if not st then return end

  local entry = get_selected_entry(st)
  if not entry then
    clear_preview_art(pid)
    clear_fa_chip_overlay(pid)
    clear_rarity_sparkle(pid)
    clear_rarity_icon(pid)
    clear_stats_text(pid)
    update_mode_deck_texts(pid)
    return
  end

  local raw_name = tostring(entry.raw_name or "")
  local base = tostring(entry.base_name or raw_name)
  if base == "" then
    clear_preview_art(pid)
    clear_fa_chip_overlay(pid)
    clear_rarity_sparkle(pid)
    clear_rarity_icon(pid)
    clear_stats_text(pid)
    update_mode_deck_texts(pid)
    return
  end

  -- Always keep FA overlay updated (this is what makes F.A.* work again)
  update_fa_chip_overlay(pid, base)

  -- Always keep rarity + sparkle updated (don’t do manual `== "gdr"` checks)
  update_rarity_icon(pid, extract_rarity_tag(raw_name))

  -- Always keep stats + description box updated
  update_stats_text(pid, entry)
  update_mode_deck_texts(pid)

  -- Build art path
  local art_dir = cfg.card_art_dir or "/server/assets/cards/"
  local art_ext = cfg.card_art_ext or ".png"
  local art_path = art_dir .. base .. art_ext

  -- If the art isn’t a valid asset, just clear it (no fallback to "cards_art", etc.)
  if has_asset(art_path) == false then
    clear_preview_art(pid)
    st.current_art_path = art_path
    return
  end

  -- Stable per-card sprite id (prevents stale art + allows safe switching)
  local stable_id = (cfg.card_art_sprite_id or "cards_art") .. "_" .. sanitize_sprite_id(base)

  if st.preview_art_sprite_id and st.preview_art_sprite_id ~= stable_id then
    safe_remove(st.preview_art_sprite_id, pid)
  end

  if st.current_art_path == art_path and st.preview_art_sprite_id == stable_id then
    return
  end

  st.preview_art_sprite_id = stable_id
  st.current_art_path = art_path

  -- IMPORTANT: always call with (pid, sprite_id, art_path)
  draw_preview_art(pid, stable_id, art_path)
end

-- ---------------------------------------------------------------------------
-- Navigation
-- ---------------------------------------------------------------------------

local function adjust_view_for_cursor(st, total)
  local visible = cfg.visible_lines
  local cursor = clamp(st.cursor_index or 1, 1, total)
  local top = st.top_index or 1

  local bottom = top + visible - 1
  if cursor < top then
    top = cursor
  elseif cursor > bottom then
    top = cursor - visible + 1
  end

  local max_top = math.max(1, total - visible + 1)
  top = clamp(top, 1, max_top)

  st.cursor_index = cursor
  st.top_index = top
end

local function move_selection_by(pid, delta)
  local st = state_by_pid[pid]
  if not st then return end

  local total = total_entries_for(pid)
  if total <= 0 then return end

  local old_cursor = st.cursor_index or 1
  local old_top = st.top_index or 1

  st.cursor_index = clamp(old_cursor + delta, 1, total)
  adjust_view_for_cursor(st, total)

  -- Only play/select + redraw if something actually changed
  if (st.cursor_index or 1) == old_cursor and (st.top_index or 1) == old_top then
    return
  end

  play_card_select_sfx(pid)
  redraw_visible_rows(pid)
  update_preview(pid)
end

local function page_scroll(pid, direction)
  local st = state_by_pid[pid]
  if not st then return end

  local total = total_entries_for(pid)
  if total <= 0 then return end

  local old_cursor = st.cursor_index or 1
  local old_top = st.top_index or 1

  local visible = cfg.visible_lines
  local max_top = math.max(1, total - visible + 1)

  local row = (st.cursor_index or 1) - (st.top_index or 1)
  row = clamp(row, 0, visible - 1)

  local new_top = (st.top_index or 1) + direction * visible
  new_top = clamp(new_top, 1, max_top)

  local new_cursor = new_top + row
  new_cursor = clamp(new_cursor, 1, total)

  st.top_index = new_top
  st.cursor_index = new_cursor
  adjust_view_for_cursor(st, total)

  if (st.cursor_index or 1) == old_cursor and (st.top_index or 1) == old_top then
    return
  end

  play_card_select_sfx(pid)
  redraw_visible_rows(pid)
  update_preview(pid)
end

local function apply_mainui_tint(pid, is_deck_mode)
  if not (Net and Net.player_draw_sprite) then return end

  local mode = is_deck_mode and (cfg.mainui_deck_color_mode or 0) or (cfg.mainui_gallery_color_mode or 0)
  local r = is_deck_mode and (cfg.mainui_deck_r or 255) or (cfg.mainui_gallery_r or 255)
  local g = is_deck_mode and (cfg.mainui_deck_g or 255) or (cfg.mainui_gallery_g or 255)
  local b = is_deck_mode and (cfg.mainui_deck_b or 255) or (cfg.mainui_gallery_b or 255)

  -- IMPORTANT: object id is sprite_id .. "_obj" (framework convention)
  pcall(Net.player_draw_sprite, pid, cfg.mainui_sprite_id, {
    id = cfg.mainui_sprite_id .. "_obj",
    r = r, g = g, b = b,
    color_mode = mode,
  })
end


local function should_fire_repeat(st, now_sec)
  if st.hold_dir == 0 then return false end
  if now_sec < (st.next_scroll_ts or 0) then return false end

  local delay = cfg.scroll_repeat_delay_sec
  if not st.has_scrolled_once then
    delay = cfg.scroll_first_repeat_delay_sec
    st.has_scrolled_once = true
  end

  st.next_scroll_ts = now_sec + delay
  return true
end

local function start_hold(st, dir, now_sec)
  st.hold_dir = dir
  st.has_scrolled_once = false
  st.next_scroll_ts = now_sec
end

local function stop_hold(st, dir)
  if st.hold_dir == dir then
    st.hold_dir = 0
    st.has_scrolled_once = false
    st.next_scroll_ts = 0
  end
end

local function on_tick(pid)
  local st = state_by_pid[pid]
  if not st then return end

  if st.hold_dir == 0 then return end
  local now_sec = os.clock()
  if should_fire_repeat(st, now_sec) then
    move_selection_by(pid, st.hold_dir)
  end
end

local function handle_cards_button(pid, name, state)
  local st = state_by_pid[pid]
  if not st then return false end

  local is_press       = (state == 1)
  local is_hold_or_scr = (state == 2 or state == 4)
  local is_release     = (state == 0)

  -- Toggle modes
  if is_press and (name == "Move Left" or name == "Left") then
    if st.mode ~= MODE_DECK then
      set_mode_only(st, MODE_DECK)
      apply_mainui_tint(pid, true)
      redraw_visible_rows(pid)
      update_preview(pid)
    end
    return true
  end

  if is_press and (name == "Move Right" or name == "Right") then
    if st.mode ~= MODE_GALLERY then
      set_mode_only(st, MODE_GALLERY)
      apply_mainui_tint(pid, false)
      redraw_visible_rows(pid)
      update_preview(pid)
    end
    return true
  end

  -- Confirm: 1st press arms, 2nd press acts (add/remove)
  if is_press and (name == "Confirm" or name == "A") then
    local entry = get_selected_entry(st)
    if not entry or not entry.item_id then
      return true
    end

    local item_id = entry.item_id

    -- re-arm if selection changed
    if st.armed_item_id ~= item_id then
      st.armed_item_id = item_id
      local base = (st.entry_by_id and st.entry_by_id[item_id]) or entry
      arm_card_for_pid(pid, base.raw_name)
      update_mode_deck_texts(pid)
      return true
    end

    -- already armed on this card -> act
    local changed = false
    if st.mode == MODE_GALLERY then
      changed = deck_add_one(pid, st, item_id)
    else
      changed = deck_remove_one(pid, st, item_id)
    end

    if changed then
      -- rebuild deck list if we're in deck mode
      if st.mode == MODE_DECK then
        local keep = item_id
        st.entries = build_deck_entries(st)
        -- keep cursor on same card if still present
        local new_idx = 1
        for i, e in ipairs(st.entries) do
          if e and e.item_id == keep then
            new_idx = i
            break
          end
        end
        st.cursor_index = (#st.entries > 0 and new_idx) or 0
        st.top_index = 1
        redraw_visible_rows(pid)
      end
      update_preview(pid)
    else
      update_mode_deck_texts(pid)
    end

    return true
  end

  -- Up/Down: single press moves once.
  -- Held events (state 2/4) repeat with a delay, like LMenu/Cosmetics.
  if name == "Up" or name == "Down" then
    local dir = (name == "Up") and -1 or 1

    if is_press then
      move_selection_by(pid, dir)
      st.hold_btn = name
      st.next_scroll_ts = os.clock() + (cfg.scroll_first_repeat_delay_sec or 0.40)
      st.armed_item_id = nil
      return true
    end

    if is_hold_or_scr then
      local now = os.clock()
      if st.hold_btn ~= name then
        -- Switched direction while holding
        st.hold_btn = name
        st.next_scroll_ts = now + (cfg.scroll_first_repeat_delay_sec or 0.40)
        return true
      end

      if now >= (st.next_scroll_ts or 0) then
        move_selection_by(pid, dir)
        st.next_scroll_ts = now + (cfg.scroll_repeat_delay_sec or 0.11)
        st.armed_item_id = nil
      end
      return true
    end

    if is_release then
      if st.hold_btn == name then
        st.hold_btn = nil
        st.next_scroll_ts = 0
      end
      return true
    end
  end

  -- Shoulder L/R: Page up/down with hold-to-repeat (same feel as Up/Down).
  if name == "Shoulder L" or name == "Shoulder R" then
    local dir = (name == "Shoulder L") and -1 or 1

    if is_press then
      -- Do one page move immediately, then start repeating if held.
      page_scroll(pid, dir)
      st.hold_btn = name
      st.next_scroll_ts = os.clock() + (cfg.scroll_first_repeat_delay_sec or 0.40)
      st.armed_item_id = nil
      return true
    end

    if is_hold_or_scr then
      local now = os.clock()
      if st.hold_btn ~= name then
        -- Switched shoulder while holding
        st.hold_btn = name
        st.next_scroll_ts = now + (cfg.scroll_first_repeat_delay_sec or 0.40)
        return true
      end

      if now >= (st.next_scroll_ts or 0) then
        page_scroll(pid, dir)
        st.next_scroll_ts = now + (cfg.scroll_repeat_delay_sec or 0.11)
        st.armed_item_id = nil
      end
      return true
    end

    if is_release then
      if st.hold_btn == name then
        st.hold_btn = nil
        st.next_scroll_ts = 0
      end
      return true
    end
  end

  -- Back to LMenu
  if is_press and name == "Cancel" then
    Cards.handle_cancel(pid)
    return true
  end

  -- Hard close
  if is_press and name == "Pause" then
    Cards.close(pid, { keep_frozen = false })
    return true
  end

  return false
end



-- ---------------------------------------------------------------------------
-- Open/close
-- ---------------------------------------------------------------------------

local function erase_all_text(pid)
  clear_list_text(pid)
  clear_stats_text(pid)
  clear_deck_ui_text(pid)
end

function Cards.open_menu(pid)
  if state_by_pid[pid] then return end

  -- lock input so overworld controls can't fire
  if Net and Net.lock_player_input then
    pcall(Net.lock_player_input, pid)
  end

  local gallery = build_card_entries(pid)

  local entry_by_id = {}
  for _, e in ipairs(gallery) do
    if e and e.item_id then
      entry_by_id[e.item_id] = e
    end
  end

  local st = {
    -- mode/list
    mode = MODE_GALLERY,
    gallery_entries = gallery,
    entry_by_id = entry_by_id,
    entries = gallery,

    -- deck
    deck_counts = load_deck_counts(pid),
    deck_total = 0,
    deck_urgdr_total = 0,
    deck_sr_total = 0,
    deck_r_total = 0,

    -- cursor/scroll
    cursor_index = (#gallery > 0 and 1) or 0,
    top_index = 1,
    hold_btn = nil,
    hold_dir = 0,
    has_scrolled_once = false,
    next_scroll_ts = 0,

    -- preview
    preview_art_sprite_id = nil,
    current_art_path = nil,
    current_rarity_state = nil,
    gdr_sparkle_on = false,

    -- FA overlay tracking
    fa_chip_sprite_id = nil,
    fa_chip_path = nil,

    -- arming
    armed_item_id = nil,
  }

  state_by_pid[pid] = st
  apply_mainui_tint(pid, false) -- gallery mode default

  -- sanitize persisted deck against current inventory / caps
  sanitize_deck_counts(pid, st)

  draw_mainui(pid)
  draw_chip(pid)
  draw_cursor(pid)

  -- scroll wheel initial position
  draw_scrollwheel(pid, cfg.scroll_top_y)

  redraw_visible_rows(pid)
  update_preview(pid)
end

function Cards.close(pid, opts)
  opts = opts or {}
  local st = state_by_pid[pid]
  if not st then return end

  -- sprites (net-games ui elements)
  safe_remove(cfg.mainui_sprite_id, pid)
  safe_remove(cfg.cursor_sprite_id, pid)
  safe_remove(cfg.chip_sprite_id, pid)
  safe_remove(cfg.scroll_sprite_id, pid)
  safe_remove(cfg.rarity_icon_sprite_id, pid)
  safe_remove(cfg.rarity_sparkle_sprite_id, pid)
  clear_preview_art(pid)
  clear_fa_chip_overlay(pid)

  -- sprites-api: list rarity icons (one per visible line)
  if cfg.list_rarity_sprite_id_base then
    for i = 1, (cfg.visible_lines or 0) do
      local sid, oid = list_rarity_ids(i)
      spr_erase(pid, oid)
      spr_dealloc(st, pid, sid)
    end
  end

  -- text
  erase_all_text(pid)

  state_by_pid[pid] = nil

  if not opts.keep_frozen then
    if Net and Net.unlock_player_input then
      pcall(Net.unlock_player_input, pid)
    end
  end
end


function Cards.handle_cancel(pid)
  -- Close Cards UI, keep overworld frozen.
  Cards.close(pid, { keep_frozen = true })

  -- Defer reopening LMenu by one tick so the same Cancel press
  -- doesn't immediately close LMenu.
  pending_lmenu_open[pid] = true
  return true
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

if Net and Net.on then
  Net:on("virtual_input", function(event)
    local pid = event.player_id
    if not state_by_pid[pid] then return end

    local function dispatch(raw_name, state)
      if not raw_name then return false end

      -- Normalize common naming differences between forks
      local name = raw_name
      if name == "Move Up" then name = "Up" end
      if name == "Move Down" then name = "Down" end

      return handle_cards_button(pid, name, state)
    end

    if type(event.buttons) == "table" then
      for _, btn in ipairs(event.buttons) do
        if dispatch(btn.button, btn.state) then
          break
        end
      end
    elseif type(event.events) == "table" then
      for _, btn in next, event.events do
        if dispatch(btn.name, btn.state) then
          break
        end
      end
    end
  end)

  Net:on("tick", function()
    for pid, _ in pairs(state_by_pid) do
      on_tick(pid)
    end
  for pid, _ in pairs(pending_lmenu_open) do
    pending_lmenu_open[pid] = nil

    local LMenu = rawget(_G, "LMenu")
    if not LMenu then
      local ok, mod = pcall(require, "scripts/ezlibs-custom/LMenu")
      if ok and type(mod) == "table" then
        LMenu = mod
        _G.LMenu = _G.LMenu or mod
      end
    end

    if LMenu and type(LMenu.open) == "function" then
      pcall(LMenu.open, pid)
    else
      -- fallback: if LMenu isn't present, at least unfreeze
      if Net and Net.unlock_player_input then
        pcall(Net.unlock_player_input, pid)
      end
    end
  end
  end)

  Net:on("player_disconnect", function(event)
    Cards.close(event.player_id, { keep_frozen = false })
  end)

  Net:on("player_area_transfer", function(event)
    Cards.close(event.player_id, { keep_frozen = false })
  end)
end

return Cards
