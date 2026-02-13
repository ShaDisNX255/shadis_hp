-- /server/scripts/ezlibs-custom/duels.lua
-- Duel UI + hands + deck draw logic (reads deck from cards.lua memory key: miniygo_deck_v2)

local duels = {}

-- ---------------------------------------------------------------------------
-- Constants (moved out of duels.lua to avoid Lua's 200-local limit)
-- ---------------------------------------------------------------------------
do
  local ok, defs = pcall(require, "scripts/duel-helpers/duels_defs")
  if ok and type(defs) == "table" then
    for k, v in pairs(defs) do
      duels[k] = v
    end
  end
end



-- ---------------------------------------------------------------------------
-- Knob time scaling
-- ---------------------------------------------------------------------------
if type(duels.KNOBS) == "table" then
  do
    local TS = tonumber(duels.KNOBS.TIME_SCALE) or 1.0
    if TS ~= 1.0 then
      local function scale_frames(v)
        return math.max(1, math.floor(v * TS + 0.5))
      end

      local function walk(t)
        for k, v in pairs(t) do
          if type(v) == "table" then
            walk(v)
          elseif type(v) == "number" then
            local ks = tostring(k)
            -- seconds-ish knobs
            if ks == "duration"
              or ks == "hold"
              or ks == "end_hold"
              or ks == "slide_duration"
              or ks:match("_delay$")
              or ks:match("_duration$")
              or ks:match("_hold$")
            then
              t[k] = v * TS
            -- tick/frame-ish knobs
            elseif ks == "life_frames" then
              t[k] = scale_frames(v)
            end
          end
        end
      end

      walk(duels.KNOBS)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Time helper (server-safe): accumulate real time from Net:on("tick") delta_time
-- ---------------------------------------------------------------------------
duels._time = duels._time or 0.0
duels._now  = duels._now  or function()
  return duels._time
end
-- ---------------------------------------------------------------------------
-- helpers + ezmemory (same pattern as cards.lua)
-- ---------------------------------------------------------------------------
local helpers_ok, helpers = pcall(require, "scripts/ezlibs-scripts/helpers")
if not helpers_ok then helpers = nil end

local ezmemory_ok, ezmemory = pcall(require, "scripts/ezlibs-scripts/ezmemory")
if not ezmemory_ok then ezmemory = nil end

-- ---------------------------------------------------------------------------
-- Opponent AI module (decision logic only)
-- ---------------------------------------------------------------------------
local duels_AI_ok, duels_AI = pcall(require, "scripts/ezlibs-custom/duels_AI")
if not duels_AI_ok then duels_AI = nil end


local sleeves_ok, card_sleeves = pcall(require, "scripts/ezlibs-custom/card_sleeves")
if not sleeves_ok then card_sleeves = nil end

-- ----------------------------------------------------------------------
-- Spells module (spell counters + spell activation)
-- ---------------------------------------------------------------------------
-- ----------------------------------------------------------------------
-- Spells module (spell counters + spell activation)
-- NOTE: Avoid top-level locals (duels.lua is at Lua local-var limit).
-- ----------------------------------------------------------------------
duels._spells = (function()
  local ok, mod = pcall(require, "scripts/duel-helpers/duels_spells")
  if ok then return mod end
  return nil
end)()
-- ---------------------------------------------------------------------------
-- Net-Games Displayer (for fonts) - same pattern as cards.lua
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
-- Assets
-- ---------------------------------------------------------------------------

-- NOTE: You originally said card.animation returns "IDLE_CARD", but you found "idle" loops.
-- Set this to whatever actually loops on your fork/assets:


-- ---------------------------------------------------------------------------
-- Deck memory key (cards.lua uses this)
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Rarity -> folder mapping (as you specified)
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Sprite resource IDs
-- ---------------------------------------------------------------------------

-- One sprite resource for opponent facedown cards (many objects share it)

-- Object-id prefixes (instances)




-- ATK/DEF icons (info panel)

-- Stardust particle effect (monster destroyed)

-- stardust core (optional; safely disabled if not present)
local stardust_ok, stardust = pcall(require, "scripts/libs/stardust/core")
if not stardust_ok then stardust = nil end

-- enums for ColorMode.ADD (optional; falls back to default blending)
local enums_ok, enums = pcall(require, "scripts/libs/enums")
local ColorMode = (enums_ok and enums and enums.ColorMode) or nil


-- ATK/POS icons (field action menu)


-- TURN / CONCEDE icons (pause menu)

-- Point counters (win condition UI)


-- Spell counters (spells UI)
duels.SPELLCOUNTER_TEX   = "/server/assets/duels/counter.png"
duels.SPELLCOUNTER_ANIM  = "/server/assets/duels/counter.animation"
duels.SPELLCOUNTER_SPRITE_ID = "duel_spellcounter"
duels.SPELLCOUNTER_STATE = "counter"
-- Spells menu UI
duels.SPELLSUI_TEX = "/server/assets/duels/spellsui.png"
duels.SPELLSUI_ANIM = "/server/assets/duels/spellsui.animation"
duels.SPELLSUI_SPRITE_ID = "duel_spellsui"
duels.SPELLSUI_STATE = "spellsui"

duels.SPELLICONS_TEX = "/server/assets/duels/spellicons.png"
duels.SPELLICONS_ANIM = "/server/assets/duels/spellicons.animation"
duels.SPELLICONS_SPRITE_ID = "duel_spellicons"

duels.SPELLS_MENU_BG_OBJ_ID = "duel_spells_menu_bg"
duels.SPELLS_MENU_CURSOR_OBJ_ID = "duel_spells_menu_cursor"
duels.SPELLS_MENU_ICON_PREFIX = "duel_spells_menu_icon_"
duels.SPELLS_MENU_COST_PREFIX = "duel_spells_menu_cost_"
duels.SPELLS_MENU_TEXT_NAME_PREFIX = "duel_spells_menu_name_"
duels.SPELLS_MENU_TEXT_DESC_PREFIX = "duel_spells_menu_desc_"

duels.PLY_SPELL_OBJ_PREFIX = "duel_ply_spell_"
duels.OPP_SPELL_OBJ_PREFIX = "duel_opp_spell_"

duels.PLY_DECK_OBJ_PREFIX = "duel_ply_deck_"
duels.OPP_DECK_OBJ_PREFIX = "duel_opp_deck_"
duels.DRAW_CARD_OBJ_ID    = "duel_draw_pickup_card"

--forward declaring some annoying functions
local _get_opponent_hand_card_tl
local _erase_monsters
local _draw_hands
local _erase_summon_menu
local _erase_field_menu
local _draw_monsters
local _toggle_opponent_monster_position
local _draw_point_counters
local _end_duel_by_points
local _ai_opp_try_cast_spell

-- ---------------------------------------------------------------------------
-- Knobs
-- ---------------------------------------------------------------------------
-- (Moved to scripts/duel-helpers/duels_defs.lua as defs.KNOBS)

-- ---------------------------------------------------------------------------
-- State per player
-- ---------------------------------------------------------------------------
local st_by_pid = {}

-- Last duel result (persists after _close so other systems can query it)
local last_duel_result_by_pid = {}

function duels.get_last_duel_result(pid)
  return pid and last_duel_result_by_pid[pid] or nil
end

-- ---------------------------------------------------------------------------
-- Utility helpers (trimmed from cards.lua)
-- ---------------------------------------------------------------------------
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
  return nil
end

local function split_area_id(raw_id)
  local s = tostring(raw_id or "")
  local a, i = s:match("^([^,]+),(.+)$")
  if a and i then return a, i end
  return "default", s
end

local function get_safe_secret(pid)
  if helpers and type(helpers.get_safe_player_secret) == "function" then
    local ok, res = pcall(helpers.get_safe_player_secret, pid)
    if ok and res ~= nil then return res end
  end
  return pid
end

local function clone_counts(t)
  local out = {}
  if type(t) == "table" then
    for k, v in pairs(t) do
      local n = math.floor(tonumber(v) or 0)
      if n > 0 then out[tostring(k)] = n end
    end
  end
  return out
end

local function get_player_mem(pid)
  if not (ezmemory and ezmemory.get_player_memory) then return {} end
  local secret = get_safe_secret(pid)
  local ok, pmem = pcall(ezmemory.get_player_memory, secret)
  if ok and type(pmem) == "table" then return pmem end
  return {}
end

local function load_deck_counts(pid)
  local pmem = get_player_mem(pid)
  return clone_counts(pmem[duels.DECK_MEM_KEY])
end

local function extract_rarity_tag(name)
  if not name then return nil end
  local tag = tostring(name):match("^%[([^%]]+)%]")
  if tag then tag = tag:gsub("%s+", "") end
  return tag
end

local function strip_rarity_tag(name)
  if not name then return "" end
  local stripped = tostring(name):gsub("^%[[^%]]+%]", "")
  stripped = stripped:gsub("^%s+", ""):gsub("%s+$", "")
  return stripped
end

-- Duel-local RNG (Park–Miller) so other scripts reseeding math.random can't affect duels.

local function _next_duel_nonce(pid)
  -- fallback that always changes even if memory saving fails
  _G.__duels_seed_nonce = (_G.__duels_seed_nonce or 0) + 1
  local fallback = _G.__duels_seed_nonce

  local secret = get_safe_secret(pid)

  -- try to persist per-player nonce in ezmemory
  if ezmemory and ezmemory.get_player_memory then
    local ok, pmem = pcall(ezmemory.get_player_memory, secret)
    if ok and type(pmem) == "table" then
      local n = tonumber(pmem[duels.DUELS_RNG_NONCE_KEY]) or 0
      n = n + 1
      pmem[duels.DUELS_RNG_NONCE_KEY] = n

      -- IMPORTANT: save the whole pmem table
      if ezmemory.set_player_memory then
        pcall(ezmemory.set_player_memory, secret, pmem)
      elseif ezmemory.save_player_memory then
        pcall(ezmemory.save_player_memory, secret, pmem)
      end

      return n + fallback * 100000
    end
  end

  return fallback * 100000
end

local function _rng_seed_from(pid)
  local t = os.time() or 0
  local addr = tonumber(tostring({}):sub(8), 16) or 0   -- address entropy (like cards.lua)
  local clk = 0
  if os.clock then
    clk = math.floor((os.clock() % 1) * 1e9)           -- sub-second entropy
  end

  local nonce = _next_duel_nonce(pid)
  local p = tonumber(pid) or 0

  local seed = (t + addr + clk + (p * 31) + (nonce * 101)) % duels.RNG_MOD
  if seed <= 0 then seed = 1 end

  return seed
end

local function _rng_next(rng)
  rng.seed = (rng.seed * duels.RNG_MUL) % duels.RNG_MOD
  return rng.seed
end

local function _rng_int(rng, a, b)
  local r = _rng_next(rng)
  return a + (r % (b - a + 1))
end

-- ---------------------------------------------------------------------------
-- Math / positioning helpers
-- ---------------------------------------------------------------------------
local function _abs(v) return (v and v < 0) and -v or (v or 0) end
local function _round_to_int(v) return math.floor((v or 0) + 0.5) end

local function _clamp_int(v, lo, hi)
  v = tonumber(v) or 0
  v = math.floor(v)
  if v < lo then return lo end
  if hi and v > hi then return hi end
  return v
end

local function _apply_card_origin_if_needed(x, y, sx, sy)
  if duels.KNOBS.CARD_POS_MODE == "origin" then
    return x, y
  end

  local o = duels.KNOBS.CARD_ORIGIN or { ox = 0, oy = 0 }
  local ox = o.ox or 0
  local oy = o.oy or 0

  -- Convert TOP-LEFT coords to ORIGIN coords.
  local dx = ox * _abs(sx or 1)
  local dy = oy * _abs(sy or 1)

  return (x or 0) + dx, (y or 0) + dy
end

local function _hand_start_x(base_x, count, spacing, hand_knobs)
  base_x = base_x or 0
  spacing = spacing or 0
  count = count or 0

  if not hand_knobs.center_enabled then
    return base_x
  end

  local tuned = _clamp_int(hand_knobs.tuned_for_count or count, 1, 30)
  local anchor_x = base_x + ((tuned - 1) * spacing) / 2
  local start_x  = anchor_x - ((count - 1) * spacing) / 2
  return start_x
end


-- ---------------------------------------------------------------------------
-- Displayer helpers + ATK/DEF parsing (borrowed from cards.lua)
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
  if not id then return end

  if Displayer and Displayer.Font then
    -- cards.lua uses eraseTextDisplay (most common on net-games forks)
    if Displayer.Font.eraseTextDisplay then
      if not pcall(Displayer.Font.eraseTextDisplay, pid, id) then
        pcall(Displayer.Font.eraseTextDisplay, Displayer.Font, pid, id)
      end
      return
    end

    -- fallback for other forks
    if Displayer.Font.eraseTextWithId then
      if not pcall(Displayer.Font.eraseTextWithId, pid, id) then
        pcall(Displayer.Font.eraseTextWithId, Displayer.Font, pid, id)
      end
      return
    end

    if Displayer.Font.eraseText then
      if not pcall(Displayer.Font.eraseText, pid, id) then
        pcall(Displayer.Font.eraseText, Displayer.Font, pid, id)
      end
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
  local ok = pcall(Displayer.Font.drawTextWithId, pid, text, sx, sy, font or "", tonumber(scale) or 1.0, tonumber(z) or 0, id)
  if not ok then
    pcall(Displayer.Font.drawTextWithId, Displayer.Font, pid, text, sx, sy, font or "", tonumber(scale) or 1.0, tonumber(z) or 0, id)
  end
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


local function _clear_info_panel(pid)
  erase_text(pid, duels.INFO_NAME_ID)
  erase_text(pid, duels.INFO_ATK_VAL_ID)
  erase_text(pid, duels.INFO_DEF_VAL_ID)
  if Net.player_erase_sprite then
    pcall(Net.player_erase_sprite, pid, duels.INFO_ATK_ICON_ID)
    pcall(Net.player_erase_sprite, pid, duels.INFO_DEF_ICON_ID)
  end
end

local function _clear_opp_info_panel(pid)
  erase_text(pid, duels.OPP_INFO_NAME_ID)
  erase_text(pid, duels.OPP_INFO_ATK_VAL_ID)
  erase_text(pid, duels.OPP_INFO_DEF_VAL_ID)
  if Net.player_erase_sprite then
    pcall(Net.player_erase_sprite, pid, duels.OPP_INFO_ATK_ICON_ID)
    pcall(Net.player_erase_sprite, pid, duels.OPP_INFO_DEF_ICON_ID)
  end
end

local function _merged_opp_info_panel_knobs()
  -- Shallow merge: INFO_PANEL baseline + OPP_INFO_PANEL overrides
  local base = duels.KNOBS.INFO_PANEL or {}
  local over = duels.KNOBS.OPP_INFO_PANEL or {}
  local ip = {}
  for k, v in pairs(base) do ip[k] = v end
  for k, v in pairs(over) do ip[k] = v end
  return ip
end

local function _get_opp_field_card_for_panel(st)
  if not (st and st.field and st.field.opp_monster and st.field.opp_monster.card) then
    return nil, nil
  end
  local mon = st.field.opp_monster
  if mon.facedown then
    return { raw_name = "????", iid = nil, area = nil, _hidden = true }, mon
  end
  return mon.card, mon
end

local function _get_cursor_card(st)
  if not st then return nil, nil end
  local mode = st.cursor_mode or "hand"

  -- While summon menu is up, always show the selected hand card.
  if st.in_summon_menu then
    mode = "hand"
  end

  -- While field menu is up, always show the player's field card.
  if st.in_field_menu then
    mode = "ply_field"
  end

  if mode == "hand" then
    local idx = st.in_summon_menu and (st.selected_hand_index or st.cursor_index or 1) or (st.cursor_index or 1)
    local card = st.ply and st.ply.hand and st.ply.hand[idx] or nil
    return card, "hand"
  elseif mode == "ply_field" then
    if st.field and st.field.ply_monster then
      return st.field.ply_monster.card, "ply_field"
    end
    return nil, "ply_field"
  elseif mode == "opp_field" then
    if st.field and st.field.opp_monster then
      -- Hide opponent facedown info
      if st.field.opp_monster.facedown then
        return { raw_name = "????", iid = nil, area = nil, _hidden = true }, "opp_field"
      end
      return st.field.opp_monster.card, "opp_field"
    end
    return nil, "opp_field"
  end

  return nil, mode
end

local function _info_panel_center_x_for(text, base_x, w, char_w, scale)
  local s = tostring(text or "")
  local n = #s
  local cw = tonumber(char_w) or 6
  local sc = tonumber(scale) or 1.0
  local tw = n * cw * sc
  return (base_x or 0) + (w or 0) / 2 - tw / 2
end

local function _update_opp_info_panel(pid, st)
  local ip = _merged_opp_info_panel_knobs()
  if ip.enabled == false then
    _clear_opp_info_panel(pid)
    return
  end

  local base_x = tonumber(ip.x) or 0
  local base_y = tonumber(ip.y) or 0
  local z = tonumber(ip.z) or 0

  _clear_opp_info_panel(pid)

  if not ensure_player_fonts(pid) then
    return
  end

  -- Ensure atk/def sprite resource exists (shared with the normal INFO_PANEL)
  if Net.provide_asset_for_player then
    pcall(Net.provide_asset_for_player, pid, duels.ATKDEF_TEX)
    pcall(Net.provide_asset_for_player, pid, duels.ATKDEF_ANIM)
  end
  if Net.player_alloc_sprite then
    pcall(Net.player_alloc_sprite, pid, duels.ATKDEF_SPRITE_ID, {
      texture_path = duels.ATKDEF_TEX,
      anim_path = duels.ATKDEF_ANIM,
      anim_state = "atk",
    })
  end

  -- IMPORTANT: Do NOT consult cursor/hand selection here.
  -- This panel should reflect ONLY the opponent monster zone.
  local mon = st and st.field and st.field.opp_monster or nil
  local card = (mon and mon.card) or nil

  local name = "EMPTY"
  local atk  = nil
  local def  = nil
  local name_font = ip.name_font or "THICK"

  if card then
    if mon.facedown then
      -- Face-down opponent monster: name hidden, stats hidden (you can change these if desired)
      name = "????"
      atk = nil
      def = nil
    else
      local info = (ezmemory and card.iid) and ezmemory.get_item_info(card.iid) or nil

      -- Name: strip rarity tags if present
      local raw = tostring((info and info.name) or (card.raw_name or "") or "")
      if raw ~= "" then
        name = strip_rarity_tag(raw)
      end

      -- Stats from description
      local desc = tostring((info and info.description) or "")
      atk, def = parse_atk_def_from_text(desc)

      -- Prefer persistent DEF (chip damage tracked)
      if mon and mon.def_current ~= nil then
        def = tonumber(mon.def_current) or def
      end
      -- Spells may apply temporary ATK modifiers (reinforcements / axe / shrink)
      if mon and mon.atk_bonus ~= nil and atk ~= nil then
        local a = tonumber(atk)
        if a ~= nil then
          atk = a + (tonumber(mon.atk_bonus) or 0)
        end
      end
    end
  end

  -- Name draw
  local name_x
  local name_off = tonumber(ip.name_x_offset) or 0
  if (ip.name_align or "center") == "left" then
    name_x = base_x + name_off
  else
    name_x = _info_panel_center_x_for(name, base_x, tonumber(ip.name_center_w) or 0, ip.name_char_w, ip.name_scale) + name_off
  end
  local name_y = base_y + (tonumber(ip.name_y) or 0)
  draw_text(pid, name, name_x, name_y, name_font, ip.name_scale, z, duels.OPP_INFO_NAME_ID)

  -- Icons + values
  local icon_x = base_x + (tonumber(ip.icon_x) or 0)
  local atk_y  = base_y + (tonumber(ip.atk_y) or 0)
  local def_y  = base_y + (tonumber(ip.def_y) or 0)

  local icon_s = tonumber(ip.icon_scale) or 1.0

  if Net.player_draw_sprite then
    local mult = duels.KNOBS.UI_POS_MULT or 1
    pcall(Net.player_draw_sprite, pid, duels.ATKDEF_SPRITE_ID, {
      id = duels.OPP_INFO_ATK_ICON_ID,
      x = math.floor(icon_x * mult),
      y = math.floor(atk_y * mult),
      sx = icon_s,
      sy = icon_s,
      z = z,
      anim_state = "atk",
    })
    pcall(Net.player_draw_sprite, pid, duels.ATKDEF_SPRITE_ID, {
      id = duels.OPP_INFO_DEF_ICON_ID,
      x = math.floor(icon_x * mult),
      y = math.floor(def_y * mult),
      sx = icon_s,
      sy = icon_s,
      z = z,
      anim_state = "def",
    })
  end

  local vx = base_x + (tonumber(ip.value_x) or 0)
  local vy_off = tonumber(ip.value_y_offset) or 0

  -- Display conventions:
  -- - Empty field: "00"
  -- - Face-down: "--" (or "??" if you prefer)
  local atk_txt, def_txt
  if not card then
    atk_txt, def_txt = "00", "00"
  elseif mon and mon.facedown then
    atk_txt, def_txt = "--", "--"
  else
    atk_txt = (atk ~= nil) and tostring(atk) or "00"
    def_txt = (def ~= nil) and tostring(def) or "00"
  end

  draw_text(pid, atk_txt, vx, atk_y + vy_off, ip.atk_value_font or "GRADIENT", ip.value_scale, z, duels.OPP_INFO_ATK_VAL_ID)
  draw_text(pid, def_txt, vx, def_y + vy_off, ip.def_value_font or "GRADIENT_GREEN", ip.value_scale, z, duels.OPP_INFO_DEF_VAL_ID)
end

local function _update_info_panel(pid, st)
  local ip = duels.KNOBS.INFO_PANEL or {}
  local base_x = tonumber(ip.x) or 0
  local base_y = tonumber(ip.y) or 0
  local z = tonumber(ip.z) or 0

  _clear_info_panel(pid)

  if not ensure_player_fonts(pid) then
    return
  end

  -- Ensure atk/def sprite resource exists
  if Net.provide_asset_for_player then
    pcall(Net.provide_asset_for_player, pid, duels.ATKDEF_TEX)
    pcall(Net.provide_asset_for_player, pid, duels.ATKDEF_ANIM)
  end
  if Net.player_alloc_sprite then
    pcall(Net.player_alloc_sprite, pid, duels.ATKDEF_SPRITE_ID, {
      texture_path = duels.ATKDEF_TEX,
      anim_path = duels.ATKDEF_ANIM,
      anim_state = "atk",
    })
  end

  -- Cursor-selected card (hand/field) + mode
  local card, cursor_mode = _get_cursor_card(st)

  -- IMPORTANT: fresh locals every call (prevents any “carry over” between updates)
  local name = "EMPTY"
  local atk  = nil
  local def  = nil
  local name_font = ip.name_font or "THICK"

  if card then
    if card._hidden then
      -- e.g. facedown opponent field when cursor hovers it
      name = "????"
      atk  = nil
      def  = nil
    else
      local info = (ezmemory and card.iid) and ezmemory.get_item_info(card.iid) or nil

      -- Name: prefer item info name, fallback to raw_name; strip rarity tags
      local raw = tostring((info and info.name) or (card.raw_name or "") or "")
      if raw ~= "" then
        name = strip_rarity_tag(raw)
      end

      -- Parse ATK/DEF from description (items_inline format)
      local desc = tostring((info and info.description) or "")
      atk, def = parse_atk_def_from_text(desc)

      -- Prefer persistent DEF values when highlighting field monsters
      if cursor_mode == "ply_field" then
        local m = st and st.field and st.field.ply_monster or nil
        if m and m.card and m.def_current ~= nil then
          def = tostring(m.def_current)
        end
        if m and m.card and m.atk_bonus ~= nil and atk ~= nil then
          local a = tonumber(atk)
          if a ~= nil then
            atk = tostring(a + (tonumber(m.atk_bonus) or 0))
          end
        end
      elseif cursor_mode == "opp_field" then
        local m = st and st.field and st.field.opp_monster or nil
        -- Only trust def_current when the card is face-up
        if m and m.card and (not m.facedown) and m.def_current ~= nil then
          def = tostring(m.def_current)
        end
        if m and m.card and (not m.facedown) and m.atk_bonus ~= nil and atk ~= nil then
          local a = tonumber(atk)
          if a ~= nil then
            atk = tostring(a + (tonumber(m.atk_bonus) or 0))
          end
        end
      end
    end
  end

  -- Name draw
  local name_x
  local name_off = tonumber(ip.name_x_offset) or 0
  if (ip.name_align or "center") == "left" then
    name_x = base_x + name_off
  else
    name_x = _info_panel_center_x_for(name, base_x, tonumber(ip.name_center_w) or 0, ip.name_char_w, ip.name_scale) + name_off
  end
  local name_y = base_y + (tonumber(ip.name_y) or 0)
  draw_text(pid, name, name_x, name_y, name_font, ip.name_scale, z, duels.INFO_NAME_ID)

  -- Icons + values
  local icon_x = base_x + (tonumber(ip.icon_x) or 0)
  local atk_y  = base_y + (tonumber(ip.atk_y) or 0)
  local def_y  = base_y + (tonumber(ip.def_y) or 0)

  local icon_s = tonumber(ip.icon_scale) or 1.0

  if Net.player_draw_sprite then
    local mult = duels.KNOBS.UI_POS_MULT or 1
    pcall(Net.player_draw_sprite, pid, duels.ATKDEF_SPRITE_ID, {
      id = duels.INFO_ATK_ICON_ID,
      x = math.floor(icon_x * mult),
      y = math.floor(atk_y * mult),
      sx = icon_s,
      sy = icon_s,
      z = z,
      anim_state = "atk",
    })
    pcall(Net.player_draw_sprite, pid, duels.ATKDEF_SPRITE_ID, {
      id = duels.INFO_DEF_ICON_ID,
      x = math.floor(icon_x * mult),
      y = math.floor(def_y * mult),
      sx = icon_s,
      sy = icon_s,
      z = z,
      anim_state = "def",
    })
  end

  local vx = base_x + (tonumber(ip.value_x) or 0)
  local vy_off = tonumber(ip.value_y_offset) or 0

  -- Keep your original behavior: unknown stats show as "--"
  local atk_txt = (atk ~= nil) and tostring(atk) or "--"
  local def_txt = (def ~= nil) and tostring(def) or "--"

  draw_text(pid, atk_txt, vx, atk_y + vy_off, ip.atk_value_font or "GRADIENT", ip.value_scale, z, duels.INFO_ATK_VAL_ID)
  draw_text(pid, def_txt, vx, def_y + vy_off, ip.def_value_font or "GRADIENT_GREEN", ip.value_scale, z, duels.INFO_DEF_VAL_ID)
end

-- ---------------------------------------------------------------------------
-- Sprite helpers
-- ---------------------------------------------------------------------------
local function _provide(pid, path)
  if Net.provide_asset_for_player and path and path ~= "" then
    pcall(Net.provide_asset_for_player, pid, path)
  end
end

local function _alloc_sprite(pid, sprite_id, texture_path, anim_path, anim_state)
  _provide(pid, texture_path)
  _provide(pid, anim_path)

  if not Net.player_alloc_sprite then return end

  local opts = { texture_path = texture_path }
  if anim_path and anim_path ~= "" then
    opts.anim_path = anim_path
    opts.anim_state = anim_state or ""
  end

  pcall(Net.player_alloc_sprite, pid, sprite_id, opts)
end

local function _dealloc_sprite(pid, sprite_id)
  if Net.player_dealloc_sprite then
    pcall(Net.player_dealloc_sprite, pid, sprite_id)
  end
end

local function _sanitize_sprite_id(s)
  s = tostring(s or "")
  return (s:gsub("[^%w]", "_"))
end

local function _hash_string(s)
  s = tostring(s or "")
  local h = 0
  for i = 1, #s do
    h = (h * 131 + s:byte(i)) % 2147483647
  end
  return h
end

local function _resolve_facedown_tex(pid)
  if card_sleeves and card_sleeves.get_equipped and card_sleeves.get_tex_for_id then
    local ok_id, id = pcall(card_sleeves.get_equipped, pid)
    if ok_id and id then
      local ok_tex, tex = pcall(card_sleeves.get_tex_for_id, id)
      if ok_tex and tex and tex ~= "" then
        return tex
      end
    end
  end
  return duels.FACE_DOWN_TEX
end

local function _ensure_facedown_sprite(pid, st)
  if not st then return duels.OPP_HAND_SPRITE_ID end

  local tex = st.facedown_tex or duels.FACE_DOWN_TEX
  if not tex or tex == "" then tex = duels.FACE_DOWN_TEX end

  -- Cache a unique sprite_id per facedown texture to avoid “sprite id doesn’t update” issues.
  local sid = st.facedown_sprite_id
  if sid then return sid end

  sid = "duel_facedown_" .. tostring(_hash_string(tex))
  st.facedown_sprite_id = sid

  st.allocated_card_sprites = st.allocated_card_sprites or {}
  st.allocated_card_sprites[#st.allocated_card_sprites + 1] = sid

  _alloc_sprite(pid, sid, tex, duels.CARD_ANIM, duels.CARD_STATE)
  return sid
end

-- Top-level: allocate a unique sprite_id per texture (prevents sprite-id caching issues)
local function _ensure_card_sprite(pid, st, card)
  if not (st and card and card.tex) then return nil end

  st.card_sprites_by_tex = st.card_sprites_by_tex or {}
  st.allocated_card_sprites = st.allocated_card_sprites or {}

  local sid = st.card_sprites_by_tex[card.tex]
  if sid then return sid end

  -- IMPORTANT: make sprite_id unique per texture (future-proof vs foil variants)
  local base = (card.rarity or "C") .. "_" .. (card.base_name or "card")
  local h = _hash_string(card.tex)
  sid = "duel_card_" .. _sanitize_sprite_id(base) .. "_" .. tostring(h)

  _alloc_sprite(pid, sid, card.tex, duels.CARD_ANIM, duels.CARD_STATE)

  st.card_sprites_by_tex[card.tex] = sid
  st.allocated_card_sprites[#st.allocated_card_sprites + 1] = sid
  return sid
end

local function _draw_sprite_obj(pid, sprite_id, obj_id, x, y, sx, sy, z, anim_state, ro)
  if not Net.player_draw_sprite then return end
  local mult = duels.KNOBS.UI_POS_MULT or 1

  local obj = {
    id = obj_id,
    x = _round_to_int((x or 0) * mult),
    y = _round_to_int((y or 0) * mult),
    sx = sx,
    sy = sy,
    z = z,
    anim_state = anim_state,
  }
  if ro ~= nil then obj.ro = ro end

  pcall(Net.player_draw_sprite, pid, sprite_id, obj)
end

local function _erase_obj(pid, obj_id)
  if Net.player_erase_sprite then
    pcall(Net.player_erase_sprite, pid, obj_id)
  end
end

local function _erase_and_dealloc(pid, sprite_id, obj_id)
  if obj_id then _erase_obj(pid, obj_id) else _erase_obj(pid, sprite_id .. "_obj") end
  _dealloc_sprite(pid, sprite_id)
end

-- ---------------------------------------------------------------------------
-- Destroy burst particles (Stardust)

-- HSV (0..360, 0..1, 0..1) -> RGB (0..255 ints)
local function _hsv_to_rgb(h, s, v)
  h = (tonumber(h) or 0) % 360
  s = math.max(0, math.min(1, tonumber(s) or 1))
  v = math.max(0, math.min(1, tonumber(v) or 1))

  local c = v * s
  local hp = h / 60
  local x = c * (1 - math.abs((hp % 2) - 1))

  local r1, g1, b1 = 0, 0, 0
  if hp < 1 then
    r1, g1, b1 = c, x, 0
  elseif hp < 2 then
    r1, g1, b1 = x, c, 0
  elseif hp < 3 then
    r1, g1, b1 = 0, c, x
  elseif hp < 4 then
    r1, g1, b1 = 0, x, c
  elseif hp < 5 then
    r1, g1, b1 = x, 0, c
  else
    r1, g1, b1 = c, 0, x
  end

  local m = v - c
  return
    math.floor((r1 + m) * 255 + 0.5),
    math.floor((g1 + m) * 255 + 0.5),
    math.floor((b1 + m) * 255 + 0.5)
end

-- ---------------------------------------------------------------------------
local function _ensure_destroy_dust(pid, st)
  if not (pid and st) then return nil end
  local pk = duels.KNOBS.DESTROY_DUST or {}
  if pk.enabled == false then return nil end
  if not (stardust and Net and Net.player_alloc_sprite and Net.player_draw_sprite) then return nil end

  st.destroy_dust = st.destroy_dust or {}

  if st.destroy_dust.sprite_ready ~= true then
    if Net.provide_asset_for_player then
      pcall(Net.provide_asset_for_player, pid, duels.PARTICLE_TEX)
    end
    pcall(Net.player_alloc_sprite, pid, duels.PARTICLE_SPRITE_ID, {
      texture_path = duels.PARTICLE_TEX,
    })
    st.destroy_dust.sprite_ready = true
  end

  if not st.destroy_dust.sys then
    local life = tonumber(pk.life_frames) or 18
    local lim  = tonumber(pk.limit) or 96
    local vel  = tonumber(pk.vel) or 3.6
    local grav = tonumber(pk.gravity) or 0.08
    local fric = tonumber(pk.friction) or 0.96

    local scale_min = tonumber(pk.scale_min) or 0.20
    local scale_max = tonumber(pk.scale_max) or 1.05

    local rr = (pk.r and pk.r[1]) or 220
    local rr2 = (pk.r and pk.r[2]) or rr
    local gg = (pk.g and pk.g[1]) or 220
    local gg2 = (pk.g and pk.g[2]) or gg
    local bb = (pk.b and pk.b[1]) or 255
    local bb2 = (pk.b and pk.b[2]) or bb

    -- easing helper: 1 -> 0 as particle ages (lets us "fade out" and "shrink")
    local function rev(x) return 1 - (x or 0) end

    st.destroy_dust.sys = stardust()
      :frames(life)
      :delay(999999) -- effectively "manual spawn only"
      :spawn(0)
      :limit(lim)

      :start_x(0, 0)
      :start_y(0, 0)

      :vel_x(-vel, vel)
      :vel_y(-vel, vel)
      :acc_x(0, 0)
      :acc_y(grav, grav)

      :fco_x(fric, fric)
      :fco_y(fric, fric)


      :scl_x(scale_min, scale_max, rev)  -- starts at scale_max, ends at scale_min
      :scl_y(scale_min, scale_max, rev)

      :ach(0, 255, rev)     -- starts opaque, fades to 0 alpha
      :rch(rr, rr2)
      :gch(gg, gg2)
      :bch(bb, bb2)

      :build()

    st.destroy_dust.last_drawn = 0
    -- core.lua doesn't expose a :rot() builder method, but it *does* support rot ranges.
    -- Set the spawn-time random rotation range directly.
    st.destroy_dust.sys.low.rot = 0
    st.destroy_dust.sys.upp.rot = 360

  end

  return st.destroy_dust.sys
end

local function _spawn_destroy_dust(pid, st, side)
  if not (pid and st) then return end
  local pk = duels.KNOBS.DESTROY_DUST or {}
  if pk.enabled == false then return end

  local sys = _ensure_destroy_dust(pid, st)
  if not sys then return end

  -- Use the zone's *origin* (your card origin is already centered, so this is perfect).
  local k = (side == "opp") and (duels.KNOBS.MZ1 or {}) or (duels.KNOBS.MZ2 or {})
  local sx = tonumber(k.sx) or 1
  local sy = tonumber(k.sy) or sx

  local cx, cy = _apply_card_origin_if_needed(tonumber(k.x) or 0, tonumber(k.y) or 0, sx, sy)

  local jit = tonumber(pk.jitter) or 2.0
  sys:start_x(cx - jit, cx + jit)
  sys:start_y(cy - jit, cy + jit)

  local count = tonumber(pk.count) or 28
  local prev_len = tonumber(sys.len) or 0

  sys:gen(count)

  -- Optional: recolor some of the freshly spawned particles into a rainbow spectrum.
  -- This keeps the overall "stardust" look, but adds colorful sparkles.
  if pk.rainbow then
    local chance = tonumber(pk.rainbow_chance) or 0.35
    local sat    = tonumber(pk.rainbow_sat) or 1.0
    local val    = tonumber(pk.rainbow_val) or 1.0
    local by_ang = (pk.rainbow_by_angle ~= false)
    local anim   = (pk.rainbow_animate == true)

    for i = prev_len + 1, (tonumber(sys.len) or 0) do
      local p = sys.liv and sys.liv[i] or nil
      if p and p.cnt and p.cnt > 0 and math.random() <= chance then
        local hue = math.random() * 360
        if by_ang and p.vel then
          local vx = tonumber(p.vel.x) or 0
          local vy = tonumber(p.vel.y) or 0
          -- math.atan(y, x) is atan2 in Lua
          local ang = math.atan(vy, vx)
          local norm = ang / (2 * math.pi)
          norm = norm - math.floor(norm) -- wrap into [0,1)
          hue = norm * 360
        end

        local r, g, b = _hsv_to_rgb(hue, sat, val)
        p.rch, p.gch, p.bch = r, g, b

        -- mark for animated hue shifting (colors will be overridden during draw)
        if anim then
          p._rb = true
          p._hue0 = hue
        end
      end
    end

  end
end

local function _draw_destroy_dust(pid, st)
  if not (pid and st and st.destroy_dust and st.destroy_dust.sys) then return end
  if not (Net and Net.player_draw_sprite) then return end

  local pk = duels.KNOBS.DESTROY_DUST or {}
  if pk.enabled == false then return end

  local sys = st.destroy_dust.sys

  -- Animated rainbow support:
  -- If rainbow_animate is enabled, we cycle hues every tick, plus optionally across particle lifetime.
  local rb_anim = (pk.rainbow and pk.rainbow_animate == true)
  local rb_sat  = tonumber(pk.rainbow_sat) or 1.0
  local rb_val  = tonumber(pk.rainbow_val) or 1.0
  local rb_tick = tonumber(pk.rainbow_tick_deg) or 80
  local rb_life = tonumber(pk.rainbow_life_deg) or 360

  if rb_anim then
    st.destroy_dust.hue_phase = ((tonumber(st.destroy_dust.hue_phase) or 0) + rb_tick) % 360
  else
    st.destroy_dust.hue_phase = tonumber(st.destroy_dust.hue_phase) or 0
  end

  local mult = duels.KNOBS.UI_POS_MULT or 1
  local ox = tonumber(pk.ox) or duels.PARTICLE_DEFAULT_OX
  local oy = tonumber(pk.oy) or duels.PARTICLE_DEFAULT_OY

  local base_z = tonumber(((duels.KNOBS.MZ2 or {}).z)) or tonumber(((duels.KNOBS.MZ1 or {}).z)) or -90
  local z = base_z + (tonumber(pk.z_offset) or 20)

  local color_mode = nil
  if pk.add_blend and ColorMode and ColorMode.ADD then
    color_mode = ColorMode.ADD
  end

  local drawn = 0
  sys:for_each(function(i, p, alive)
    if not alive then return end
    drawn = i

    local r, g, b = p.rch, p.gch, p.bch
    if rb_anim and p._rb then
      local max = tonumber(p.max) or 1
      if max <= 0 then max = 1 end
      local cnt = tonumber(p.cnt) or 0
      local w = 1 - (cnt / max)
      if w < 0 then w = 0 elseif w > 1 then w = 1 end
      local hue = ((tonumber(p._hue0) or 0) + (tonumber(st.destroy_dust.hue_phase) or 0) + (w * rb_life)) % 360
      r, g, b = _hsv_to_rgb(hue, rb_sat, rb_val)
    end

    local obj = {
      id = duels.PARTICLE_OBJ_PREFIX .. i,
      x = _round_to_int((p.pos.x or 0) * mult),
      y = _round_to_int((p.pos.y or 0) * mult),
      ox = ox,
      oy = oy,
      sx = p.scl.x,
      sy = p.scl.y,
      z = z,
      a = p.ach,
      r = r,
      g = g,
      b = b,
    }
    if color_mode ~= nil then obj.color_mode = color_mode end
    if p.rot ~= nil then obj.ro = p.rot end

    pcall(Net.player_draw_sprite, pid, duels.PARTICLE_SPRITE_ID, obj)
  end)

  -- hide any stale ids when count shrinks (stardust compacts its live list)
  local prev = tonumber(st.destroy_dust.last_drawn) or 0
  if prev > drawn then
    for i = drawn + 1, prev do
      -- Fast hide: keep object, but collapse it.
      pcall(Net.player_draw_sprite, pid, duels.PARTICLE_SPRITE_ID, {
        id = duels.PARTICLE_OBJ_PREFIX .. i,
        sx = 0,
        sy = 0,
        a = 0,
        z = z,
      })
    end
  end
  st.destroy_dust.last_drawn = drawn
end

local function _clear_destroy_dust(pid, st)
  if not (pid and st) then return end
  if st.destroy_dust then
    local prev = tonumber(st.destroy_dust.last_drawn) or 0
    if prev > 0 then
      for i = 1, prev do
        _erase_obj(pid, duels.PARTICLE_OBJ_PREFIX .. i)
      end
    end
    st.destroy_dust.last_drawn = 0

    if st.destroy_dust.sys and st.destroy_dust.sys.destroy then
      pcall(st.destroy_dust.sys.destroy, st.destroy_dust.sys)
    end
    st.destroy_dust.sys = nil
  end

  _dealloc_sprite(pid, duels.PARTICLE_SPRITE_ID)
end



-- ---------------------------------------------------------------------------
-- Summon animation (sprites-api only)
-- ---------------------------------------------------------------------------


local function _clamp01(t)
  t = tonumber(t) or 0
  if t < 0 then return 0 end
  if t > 1 then return 1 end
  return t
end

local function _lerp(a, b, t)
  return (a or 0) + ((b or 0) - (a or 0)) * (t or 0)
end

local function _smoothstep(t)
  -- classic smoothstep: 3t^2 - 2t^3
  return t * t * (3 - 2 * t)
end

local function _quad_bezier(p0, p1, p2, t)
  -- (1-t)^2 p0 + 2(1-t)t p1 + t^2 p2
  local u = 1 - t
  local tt = t * t
  local uu = u * u
  local x = uu * p0.x + 2 * u * t * p1.x + tt * p2.x
  local y = uu * p0.y + 2 * u * t * p1.y + tt * p2.y
  return x, y
end

local function _start_summon_anim(pid, st, card, start_x, start_y, start_s, end_x, end_y, end_s, kind, opts)
  local ak = duels.KNOBS.SUMMON_ANIM or {}
  if not ak.enabled then return false end

  kind = kind or "summon" -- "summon" | "set"
  opts = (type(opts) == "table") and opts or nil

  local hidden_set = (kind == "set" and opts and opts.hidden)

  local sprite_id
  if hidden_set then
    -- Opponent SET: keep FaceDown.png for the entire flight (never show the real card).
    sprite_id = _ensure_facedown_sprite(pid, st)
  else
    -- ensure the sprite resource exists for this card
    sprite_id = _ensure_card_sprite(pid, st, card)
    if not sprite_id then return false end
  end

  -- SET animation: can optionally swap to facedown mid-flight (player SET).
  local alt_sprite_id = nil
  local ro0, ro2 = nil, nil
  local swap_t = nil
  local flip_min = nil

  if kind == "set" then
    -- ensure facedown sprite resource exists (swap target)
    local fd_sid = _ensure_facedown_sprite(pid, st)

    -- rotate into DEF-style by the end
    ro0 = 0
    ro2 = 90
    if opts and opts.ro0 ~= nil then ro0 = tonumber(opts.ro0) or ro0 end
    if opts and opts.ro2 ~= nil then ro2 = tonumber(opts.ro2) or ro2 end

    if not hidden_set then
      alt_sprite_id = fd_sid
      swap_t = 0.50
    end

    -- how thin it gets at midpoint (0.0 would be fully invisible; keep slightly >0)
    flip_min = 0.06
  end

  local now = duels._now()
  st.summon_anim = {
    active = true,
    started_at = now,
    duration = tonumber(ak.duration) or 0.35,

    kind = kind,

    target_side = (opts and opts.target_side) or "ply",
    target_pos  = (opts and opts.target_pos) or nil,

    sprite_id = sprite_id,
    alt_sprite_id = alt_sprite_id,

    ro0 = ro0,
    ro2 = ro2,
    swap_t = swap_t,
    flip_min = flip_min,

    card = card,

    x0 = start_x, y0 = start_y,
    x2 = end_x,   y2 = end_y,

    s0 = start_s, s2 = end_s,

    arc_h = tonumber(ak.arc_height) or 24,
    peak_mul = tonumber(ak.peak_scale_mul) or 1.35,

    z = tonumber(ak.z) or -70,
    wobble = tonumber(ak.wobble_ro_deg) or 0,
  }

  -- Place control point halfway, lifted up by arc height
  st.summon_anim.x1 = (start_x + end_x) * 0.5
  st.summon_anim.y1 = (start_y + end_y) * 0.5 - st.summon_anim.arc_h

  -- First frame
  _draw_sprite_obj(pid, sprite_id, duels.SUMMON_ANIM_OBJ_ID, start_x, start_y, start_s, start_s, st.summon_anim.z, duels.CARD_STATE, ro0)
  return true
end

local function _update_summon_anim(pid, st)
  local a = st and st.summon_anim
  if not (a and a.active) then return false end

  local now = duels._now()
  local t = (now - (a.started_at or now)) / (a.duration or 0.35)
  t = _clamp01(t)

  local te = _smoothstep(t)

  -- position along a smooth arc
  local x, y = _quad_bezier(
    {x = a.x0, y = a.y0},
    {x = a.x1, y = a.y1},
    {x = a.x2, y = a.y2},
    te
  )

  -- scale lerp + midpoint pulse (sin(pi*t))
  local base_s = _lerp(a.s0, a.s2, te)
  local pulse = 1.0
  if (a.peak_mul or 1.0) > 1.0 then
    pulse = 1.0 + ((a.peak_mul - 1.0) * math.sin(math.pi * t))
  end
  local s = base_s * pulse

  -- Decide sprite + transform for summon vs set
  local sprite_id = a.sprite_id
  local ro = nil
  local sx, sy = s, s

  if a.kind == "set" then
    -- swap to facedown at midpoint while "edge-on"
    local swap_t = a.swap_t or 0.5
    if a.alt_sprite_id and t >= swap_t then
      sprite_id = a.alt_sprite_id
    end

    -- rotate 0 -> 90 over the flight
    ro = _lerp(a.ro0 or 0, a.ro2 or 90, te)

    -- flip squeeze: width is 1 at ends, min at midpoint
    local minw = a.flip_min or 0.06
    local edge = math.abs(2 * t - 1) -- 1 at ends, 0 at mid
    local wmul = minw + (1 - minw) * edge
    sx = s * wmul
    sy = s
  else
    -- optional base rotation (e.g. opponent summons use 0->180)
    local base_ro = nil
    if a.ro0 ~= nil or a.ro2 ~= nil then
      base_ro = _lerp(a.ro0 or 0, a.ro2 or 0, te)
    end

    -- optional wobble for normal summon (adds on top of base_ro if present)
    if (a.wobble or 0) ~= 0 then
      local wob = math.sin(math.pi * 2 * t) * a.wobble
      base_ro = (base_ro or 0) + wob
    end

    ro = base_ro
  end

  _draw_sprite_obj(pid, sprite_id, duels.SUMMON_ANIM_OBJ_ID, x, y, sx, sy, a.z, duels.CARD_STATE, ro)

  if t >= 1 then
    a.active = false
    return true -- finished
  end

  return false
end

local function _end_summon_anim(pid, st)
  if st and st.summon_anim then
    _erase_obj(pid, duels.SUMMON_ANIM_OBJ_ID)
    st.summon_anim = nil
  end
end


-- ---------------------------------------------------------------------------
-- Position change animation (sprites-api only)
-- ---------------------------------------------------------------------------


local function _update_pos_anim(pid, st)
  local a = st and st.pos_anim
  if not (a and a.active) then return false end

  local now = duels._now()
  local t = (now - (a.started_at or now)) / (a.duration or 0.18)
  t = _clamp01(t)

  local te = _smoothstep(t)

  -- midpoint pulse (sin(pi*t))
  local pulse = 1.0
  if (a.peak_mul or 1.0) > 1.0 then
    pulse = 1.0 + ((a.peak_mul - 1.0) * math.sin(math.pi * t))
  end

  local sprite_id = a.sprite_id
  local ro = _lerp(a.ro0 or 0, a.ro2 or 0, te)
  local sx = (a.base_sx or 1) * pulse
  local sy = (a.base_sy or 1) * pulse

  if a.kind == "fd_to_atk" or a.kind == "fd_to_def" then
    -- swap to face-up texture at midpoint while "edge-on"
    local swap_t = a.swap_t or 0.5
    if a.alt_sprite_id and t >= swap_t then
      sprite_id = a.alt_sprite_id
    end

    -- flip squeeze: width is 1 at ends, min at midpoint
    local minw = a.flip_min or 0.06
    local edge = math.abs(2 * t - 1) -- 1 at ends, 0 at mid
    local wmul = minw + (1 - minw) * edge
    sx = sx * wmul
  end

  _draw_sprite_obj(pid, sprite_id, duels.POS_ANIM_OBJ_ID, a.x, a.y, sx, sy, a.z, duels.CARD_STATE, ro)

  if t >= 1 then
    a.active = false
    return true
  end

  return false
end


-- ---------------------------------------------------------------------------
-- Attack animation (no damage yet)
-- ---------------------------------------------------------------------------

local function _erase_attack_anim(pid)
  _erase_obj(pid, duels.ATTACK_MZ1_OBJ_ID)
  _erase_obj(pid, duels.ATTACK_MZ2_OBJ_ID)
end

local function _can_attack(mon)
  return mon and mon.card and (not mon.facedown) and ((mon.pos or "atk") == "atk")
end


local function _get_card_atk_def(card)
  if not card then return nil, nil end
  local info = (ezmemory and card.iid) and ezmemory.get_item_info(card.iid) or nil
  local desc = tostring((info and info.description) or "")
  return parse_atk_def_from_text(desc)
end

-- returns (value, mode) where mode is "atk" or "def"
local function _get_mon_battle_value(mon)
  if not mon or not mon.card then return 0, "none" end
  local atk, def = _get_card_atk_def(mon.card)
  atk = tonumber(atk) or 0
  def = tonumber(def) or 0

  if (mon.pos or "atk") == "def" then
    local cur = tonumber(mon.def_current)
    if cur == nil then
      cur = def
      mon.def_current = cur
    end
    return cur, "def"
  end

  -- Cache baseline DEF for later (only used when the monster is face-up / player-owned; UI already hides facedown opponent).
  if mon.def_current == nil then
    mon.def_current = def
  end

  -- Spells may apply temporary ATK modifiers (reinforcements / axe / shrink)
  local bonus = tonumber(mon.atk_bonus) or 0
  if bonus ~= 0 then
    atk = atk + bonus
  end

  return atk, "atk"
end


local function _destroy_monster(pid, st, side)
  if not (st and st.field) then return end

  -- Spawn a small stardust burst at the zone center before removing the monster.
  _spawn_destroy_dust(pid, st, side)

  if side == "opp" then
    st.field.opp_monster = nil
  else
    st.field.ply_monster = nil
  end
end

local function _resolve_attack_battle(pid, st, attacker_side)
  if not (st and st.field) then return end
  attacker_side = attacker_side or "ply"

  local atk_slot = (attacker_side == "opp") and st.field.opp_monster or st.field.ply_monster
  local def_side = (attacker_side == "opp") and "ply" or "opp"
  local def_slot = (def_side == "opp") and st.field.opp_monster or st.field.ply_monster

  local destroyed_ply = false
  local destroyed_opp = false
  local function mark_destroy(side)
    if side == "ply" then destroyed_ply = true else destroyed_opp = true end
  end

  if not _can_attack(atk_slot) then return end
  if not (def_slot and def_slot.card) then
    -- No direct attacks in this mini-YGO
    return
  end

  -- Reveal-on-block: if you attack a set monster, flip it face-up DEF before calculation.
  if def_slot.facedown then
    def_slot.facedown = false
    def_slot.pos = "def"
    -- initialize persistent DEF if needed
    local _, base_def = _get_card_atk_def(def_slot.card)
    def_slot.def_current = tonumber(def_slot.def_current) or (tonumber(base_def) or 0)
  end

  -- Attacker ATK (includes spell modifiers via mon.atk_bonus)
  local attacker_atk, _ = _get_mon_battle_value(atk_slot)
  attacker_atk = tonumber(attacker_atk) or 0

  -- Defender mode/value (DEF uses def_current)
  local defender_value, def_mode = _get_mon_battle_value(def_slot)

  -- A) ATK vs ATK
  if def_mode == "atk" then
    if attacker_atk > defender_value then
      mark_destroy(def_side)
    elseif attacker_atk < defender_value then
      mark_destroy(attacker_side)
    else
      mark_destroy("ply")
      mark_destroy("opp")
    end

    if destroyed_ply then _destroy_monster(pid, st, "ply") end
    if destroyed_opp then _destroy_monster(pid, st, "opp") end

    if destroyed_opp then st.ply_points = _clamp_int((st.ply_points or 0) + 1, 0, 3) end
    if destroyed_ply then st.opp_points = _clamp_int((st.opp_points or 0) + 1, 0, 3) end


    -- Spell counters: +1 to destroyer, +2 to side that lost the monster
    local maxsc = _clamp_int(((duels.KNOBS.SPELL_COUNTER or {}).max) or 6, 1, 24)
    if duels._spells and duels._spells.on_monster_destroyed then
      if destroyed_opp then pcall(duels._spells.on_monster_destroyed, st, "ply", "opp", maxsc) end
      if destroyed_ply then pcall(duels._spells.on_monster_destroyed, st, "opp", "ply", maxsc) end
    else
      if destroyed_opp then
        st.ply_spell_counters = _clamp_int((st.ply_spell_counters or 0) + 1, 0, maxsc)
        st.opp_spell_counters = _clamp_int((st.opp_spell_counters or 0) + 2, 0, maxsc)
      end
      if destroyed_ply then
        st.opp_spell_counters = _clamp_int((st.opp_spell_counters or 0) + 1, 0, maxsc)
        st.ply_spell_counters = _clamp_int((st.ply_spell_counters or 0) + 2, 0, maxsc)
      end
    end
    duels._draw_spell_counters(pid, st)

    _draw_point_counters(pid, st)
    _end_duel_by_points(pid, st)
    return
  end

  -- B) ATK vs DEF (chip damage)
  local chip = attacker_atk
  if chip > 1000 then chip = math.floor(chip / 2) end

  local cur_def = tonumber(def_slot.def_current)
  if cur_def == nil then
    local _, base_def = _get_card_atk_def(def_slot.card)
    cur_def = tonumber(base_def) or 0
  end

  cur_def = cur_def - chip
  def_slot.def_current = cur_def

  if cur_def <= 0 then
    mark_destroy(def_side)

    if destroyed_ply then _destroy_monster(pid, st, "ply") end
    if destroyed_opp then _destroy_monster(pid, st, "opp") end

    if destroyed_opp then st.ply_points = _clamp_int((st.ply_points or 0) + 1, 0, 3) end
    if destroyed_ply then st.opp_points = _clamp_int((st.opp_points or 0) + 1, 0, 3) end


    -- Spell counters: +1 to destroyer, +2 to side that lost the monster
    local maxsc = _clamp_int(((duels.KNOBS.SPELL_COUNTER or {}).max) or 6, 1, 24)
    if duels._spells and duels._spells.on_monster_destroyed then
      if destroyed_opp then pcall(duels._spells.on_monster_destroyed, st, "ply", "opp", maxsc) end
      if destroyed_ply then pcall(duels._spells.on_monster_destroyed, st, "opp", "ply", maxsc) end
    else
      if destroyed_opp then
        st.ply_spell_counters = _clamp_int((st.ply_spell_counters or 0) + 1, 0, maxsc)
        st.opp_spell_counters = _clamp_int((st.opp_spell_counters or 0) + 2, 0, maxsc)
      end
      if destroyed_ply then
        st.opp_spell_counters = _clamp_int((st.opp_spell_counters or 0) + 1, 0, maxsc)
        st.ply_spell_counters = _clamp_int((st.ply_spell_counters or 0) + 2, 0, maxsc)
      end
    end
    duels._draw_spell_counters(pid, st)

    _draw_point_counters(pid, st)
    _end_duel_by_points(pid, st)
  else
    -- Defender survives => attacker switches to DEF
    atk_slot.pos = "def"
    -- Rule: this forced switch counts as this turn's position change (so you can't switch back)
    local ti = st.turn_index or 0
    if attacker_side == "opp" then
      st.opp_pos_changed_turn_index = ti
    else
      st.ply_pos_changed_turn_index = ti
    end
    -- seed attacker DEF cache for info panel (optional)
    local _, base_def = _get_card_atk_def(atk_slot.card)
    atk_slot.def_current = tonumber(atk_slot.def_current) or (tonumber(base_def) or 0)
  end
end


local function _attack_offset(t, t1, t2, recoil_target, lunge_target)
  t = _clamp01(t or 0)
  t1 = tonumber(t1) or 0.25
  t2 = tonumber(t2) or 0.60
  if t1 <= 0 then t1 = 0.001 end
  if t2 <= t1 then t2 = t1 + 0.001 end
  if t >= 1 then return 0 end

  if t < t1 then
    local u = _smoothstep(_clamp01(t / t1))
    return _lerp(0, recoil_target, u)
  elseif t < t2 then
    local u = _smoothstep(_clamp01((t - t1) / (t2 - t1)))
    return _lerp(recoil_target, lunge_target, u)
  else
    local u = _smoothstep(_clamp01((t - t2) / (1 - t2)))
    return _lerp(lunge_target, 0, u)
  end
end

local function _start_attack_anim(pid, st, attacker_side)
  if not (st and st.field) then return end
  if st.attack_anim and st.attack_anim.active then return end
  if (st.summon_anim and st.summon_anim.active) or (st.pos_anim and st.pos_anim.active) or (st.attack_anim and st.attack_anim.active) then return end

  local ak = duels.KNOBS.ATTACK_ANIM or {}
  if ak.enabled == false then return end

  attacker_side = attacker_side or "ply"
  local atk_mon = (attacker_side == "opp") and st.field.opp_monster or st.field.ply_monster
  if not _can_attack(atk_mon) then return end

  -- No direct attacks: must have a target monster.
  local def_mon = (attacker_side == "opp") and st.field.ply_monster or st.field.opp_monster
  if not (def_mon and def_mon.card) then return end

  -- capture defender state for reveal flow
  local defender_side = (attacker_side == "opp") and "ply" or "opp"
  local def_was_facedown = (def_mon.facedown == true)

  -- Rule: only 1 attack per turn
  local ti = st.turn_index or 0
  if attacker_side == "opp" then
    if st.opp_attacked_turn_index == ti then return end
    st.opp_attacked_turn_index = ti
  else
    if st.ply_attacked_turn_index == ti then return end
    st.ply_attacked_turn_index = ti
  end

  -- Hide ONLY the attacker's normal zone sprite during the lunge (defender stays visible).
  if attacker_side == "opp" then
    if st.field.opp_monster and st.field.opp_monster.card then _erase_obj(pid, duels.MZ1_OBJ_ID) end
  else
    if st.field.ply_monster and st.field.ply_monster.card then _erase_obj(pid, duels.MZ2_OBJ_ID) end
  end

  _erase_attack_anim(pid)
  _erase_obj(pid, duels.CURSOR_SPRITE_ID .. "_obj")

  local a = {
    active = true,
    started_at = duels._now(),
    duration = tonumber(ak.duration) or 0.22,
    attacker_side = attacker_side,
    defender_side = defender_side,
    def_was_facedown = def_was_facedown,

    t1 = tonumber(ak.t1) or 0.25,
    t2 = tonumber(ak.t2) or 0.60,

    z_offset = tonumber(ak.z_offset) or 12,

    ply = nil,
    opp = nil,
  }

  if attacker_side == "opp" then
    -- Attacker is opponent (MZ1)
    local mz = duels.KNOBS.MZ1 or {}
    local sx = tonumber(mz.sx) or 1
    local sy = tonumber(mz.sy) or sx
    local x, y = _apply_card_origin_if_needed(tonumber(mz.x) or 0, tonumber(mz.y) or 0, sx, sy)

    local atk_ro = tonumber(mz.ro) or 0
    local def_ro = (atk_ro + 90) % 360

    local mon = st.field.opp_monster
    local sprite_id, ro

    if mon.facedown then
      sprite_id = _ensure_facedown_sprite(pid, st)
      ro = def_ro
    else
      sprite_id = _ensure_card_sprite(pid, st, mon.card)
      ro = ((mon.pos or "atk") == "def") and def_ro or atk_ro
    end

    a.opp = {
      obj_id = duels.ATTACK_MZ1_OBJ_ID,
      sprite_id = sprite_id,
      x = x, y = y,
      sx = sx, sy = sy,
      z = (tonumber(mz.z) or -90) + a.z_offset,
      ro = ro,

      recoil_target = - (tonumber(ak.opp_recoil) or 5),  -- up
      lunge_target  = (tonumber(ak.opp_lunge) or 15),   -- down
    }
  else
    -- Attacker is player (MZ2)
    local mz = duels.KNOBS.MZ2 or {}
    local sx = tonumber(mz.sx) or 1
    local sy = tonumber(mz.sy) or sx
    local x, y = _apply_card_origin_if_needed(tonumber(mz.x) or 0, tonumber(mz.y) or 0, sx, sy)

    local atk_ro = tonumber(mz.ro) or 0
    local def_ro = 90

    local mon = st.field.ply_monster
    local sprite_id, ro

    if mon.facedown then
      sprite_id = _ensure_facedown_sprite(pid, st)
      ro = def_ro
    else
      sprite_id = _ensure_card_sprite(pid, st, mon.card)
      ro = ((mon.pos or "atk") == "def") and def_ro or atk_ro
    end

    a.ply = {
      obj_id = duels.ATTACK_MZ2_OBJ_ID,
      sprite_id = sprite_id,
      x = x, y = y,
      sx = sx, sy = sy,
      z = (tonumber(mz.z) or -90) + a.z_offset,
      ro = ro,

      recoil_target = (tonumber(ak.ply_recoil) or 5),    -- down
      lunge_target  = - (tonumber(ak.ply_lunge) or 15),  -- up
    }
  end

  st.attack_anim = a

  -- initial draw
  _erase_attack_anim(pid)
  if a.opp then
    _draw_sprite_obj(pid, a.opp.sprite_id, a.opp.obj_id, a.opp.x, a.opp.y, a.opp.sx, a.opp.sy, a.opp.z, duels.CARD_STATE, a.opp.ro)
  end
  if a.ply then
    _draw_sprite_obj(pid, a.ply.sprite_id, a.ply.obj_id, a.ply.x, a.ply.y, a.ply.sx, a.ply.sy, a.ply.z, duels.CARD_STATE, a.ply.ro)
  end
end


local function _update_attack_anim(pid, st)
  local a = st and st.attack_anim
  if not (a and a.active) then return false end

  local now = duels._now()
  local dur = tonumber(a.duration) or 0.22
  if dur <= 0 then dur = 0.001 end
  local t = (now - (a.started_at or now)) / dur
  local done = (t >= 1.0)

  _erase_attack_anim(pid)

  if a.opp then
    local oy = _attack_offset(t, a.t1, a.t2, a.opp.recoil_target, a.opp.lunge_target)
    _draw_sprite_obj(pid, a.opp.sprite_id, a.opp.obj_id,
      a.opp.x, a.opp.y + oy, a.opp.sx, a.opp.sy, a.opp.z, duels.CARD_STATE, a.opp.ro)
  end

  if a.ply then
    local py = _attack_offset(t, a.t1, a.t2, a.ply.recoil_target, a.ply.lunge_target)
    _draw_sprite_obj(pid, a.ply.sprite_id, a.ply.obj_id,
      a.ply.x, a.ply.y + py, a.ply.sx, a.ply.sy, a.ply.z, duels.CARD_STATE, a.ply.ro)
  end

  return done
end

local function _end_attack_anim(pid, st)
  if st then
    st.attack_anim = nil
  end
  _erase_attack_anim(pid)
end

local function _end_pos_anim(pid, st)
  if st and st.pos_anim then
    _erase_obj(pid, duels.POS_ANIM_OBJ_ID)
    st.pos_anim = nil
  end
end



local function _update_hand_cursor(pid, st)
  if not st then return end

  local hand = st.ply and st.ply.hand or {}
  local count = #hand

  -- Hide cursor if no hand cards
  if count <= 0 then
    _erase_obj(pid, duels.CURSOR_SPRITE_ID .. "_obj")
    return
  end

  -- Clamp selection
  st.cursor_index = math.max(1, math.min(st.cursor_index or 1, count))

  local hk = duels.KNOBS.HAND
  local ph = duels.KNOBS.PLY_HAND_POS
  local ck = duels.KNOBS.CURSOR

  local step_x = hk.spacing_x or 0
  local start_x = _hand_start_x(ph.x, count, step_x, hk)
  local y_tl = ph.y or 0

  -- Top-left of selected card in your hand layout space
  local sel_tl_x = start_x + (st.cursor_index - 1) * step_x
  local sel_tl_y = y_tl - (tonumber(hk.highlight_lift_y) or 0)

  -- Convert to "card center" in layout space.
  -- card_center_x/y are in card-local pixels, scaled by the card scale.
  local card_scale = hk.scale or 1
  local cx = sel_tl_x + (ck.card_center_x or 0) * _abs(card_scale)
  local cy = sel_tl_y + (ck.card_center_y or 0) * _abs(card_scale)

  -- Apply user offsets (still in layout-space pixels)
  cx = cx + (ck.offset_x or 0)
  cy = cy + (ck.offset_y or 0)

  -- Ensure cursor sprite exists and draw it
  _alloc_sprite(pid, duels.CURSOR_SPRITE_ID, duels.CURSOR_TEX, duels.CURSOR_ANIM, duels.CURSOR_STATE)
  _draw_sprite_obj(
    pid,
    duels.CURSOR_SPRITE_ID,
    duels.CURSOR_SPRITE_ID .. "_obj",
    cx, cy,
    ck.sx, ck.sy,
    ck.z or (hk.z - 1),
    duels.CURSOR_STATE,
    nil
  )
end


local function _update_cursor(pid, st)
  if not st then return end
  if st.in_summon_menu or st.in_field_menu or st.in_pause_menu or st.in_spells_menu or (st.pos_anim and st.pos_anim.active) or (st.attack_anim and st.attack_anim.active) then
    _erase_obj(pid, duels.CURSOR_SPRITE_ID .. "_obj")
    return
  end

  local mode = st.cursor_mode or "hand"
  if mode == "hand" then
    _update_hand_cursor(pid, st)
    return
  end

  -- Field positions are based on the monster zones; cursor uses the card "origin" point.
  local ck = duels.KNOBS.CURSOR or {}
  local mz = (mode == "opp_field") and duels.KNOBS.MZ1 or duels.KNOBS.MZ2
  mz = mz or {}

  local x, y = _apply_card_origin_if_needed(tonumber(mz.x) or 0, tonumber(mz.y) or 0, tonumber(mz.sx) or 1, tonumber(mz.sy) or 1)
  x = x + (tonumber(ck.offset_x) or 0)
  y = y + (tonumber(ck.offset_y) or 0)

  _draw_sprite_obj(pid, duels.CURSOR_SPRITE_ID, duels.CURSOR_SPRITE_ID .. "_obj", x, y, tonumber(ck.sx) or 2, tonumber(ck.sy) or 2, tonumber(ck.z) or -60, duels.CURSOR_STATE)
end

-- ---------------------------------------------------------------------------
-- Deck -> expanded list
-- ---------------------------------------------------------------------------
local function _card_texture_from_raw_name(raw_name)
  raw_name = tostring(raw_name or "")
  local tag = extract_rarity_tag(raw_name)
  tag = tostring(tag or "C"):upper()
  local base = strip_rarity_tag(raw_name)
  local dir = duels.RARITY_DIR[tag] or duels.RARITY_DIR.C
  return dir .. "/" .. base .. ".png", tag, base
end

local function _build_deck_list_from_counts(pid, deck_counts)
  local list = {}
  if not (ezmemory and ezmemory.get_item_info) then
    return list
  end

  for item_id, n in pairs(deck_counts or {}) do
    n = math.floor(tonumber(n) or 0)
    if n > 0 then
      local area, iid = split_area_id(item_id)
      local info = ezmemory.get_item_info(iid)
      local raw_name = info and info.name and tostring(info.name) or ""
      if raw_name ~= "" then
        local tex, tag, base = _card_texture_from_raw_name(raw_name)
        -- Optional: if missing asset, keep it but you’ll see it as blank; log once.
        if has_asset(tex) == false then
          print(("[Duels] Missing card texture: %s (from %s)"):format(tex, raw_name))
        end

        for _ = 1, n do
          list[#list + 1] = {
            item_id   = tostring(item_id),
            raw_name  = raw_name,
            rarity    = tag,
            base_name = base,
            tex       = tex,
            area      = area,
            iid       = iid,
          }
        end
      end
    end
  end

  return list
end

local function _make_pile(n)
  local pile = {}
  for i = 1, n do pile[i] = i end
  return pile
end

local function _draw_random_from_deck(st_side)
  if not st_side then return nil end
  local pile = st_side.pile
  local deck = st_side.deck
  if type(pile) ~= "table" or #pile == 0 then return nil end

  local pick = (st_side.rng and _rng_int(st_side.rng, 1, #pile)) or math.random(1, #pile)
  local deck_index = table.remove(pile, pick)
  return deck and deck[deck_index] or nil
end
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Turn flow + Opponent AI
-- ---------------------------------------------------------------------------

local function _ai_knobs()
  return duels.KNOBS.AI or {}
end

local function _ai_enabled()
  local ak = _ai_knobs()
  return (ak.enabled ~= false) and (duels_AI ~= nil)
end

local function _ai_ctx(st)
  local ak = _ai_knobs()
  local ai_type = (st and st.cfg and st.cfg.ai_type) or ak.type or "default"
  local rng = st and st.opp and st.opp.rng

  return {
    ai_type = ai_type,
    get_card_atk_def = _get_card_atk_def,
    rng_int = function(lo, hi)
      lo = math.floor(tonumber(lo) or 1)
      hi = math.floor(tonumber(hi) or lo)
      if hi < lo then lo, hi = hi, lo end
      if rng then
        return _rng_int(rng, lo, hi)
      end
      return math.random(lo, hi)
    end,
  }
end

local function _ai_log(st, plan)
  local ak = _ai_knobs()
  if ak.debug ~= true then return end

  local t = (st and st.turn_index) or 0
  local r = (plan and plan.reason) or ""
  local kind = (plan and plan.play and plan.play.kind) or "none"
  local pos  = (plan and plan.play and plan.play.pos) or ""
  local atk  = (plan and plan.attack) and "attack" or ""
  local tog  = (plan and plan.toggle_to_atk) and "toggle_to_atk" or ""

  print(("[Duels][AI][t=%d] plan=%s %s %s %s reason=%s"):format(t, kind, pos, tog, atk, r))
end

local function _ai_clear_pending(st)
  if not st then return end
  st.ai_after_summon = nil
  st.ai_after_pos = nil
end

local function _ai_opp_queue_attack(pid, st, now)
  if not _ai_enabled() then return false end
  if not (st and st.field) then return false end

  -- Rule: only 1 attack per turn (AI)
  if (st.opp_attacked_turn_index or -1) == (st.turn_index or 0) then
    return false
  end
  -- Attack if we have a face-up ATK monster AND the player has a target monster (no direct attacks).
  local mon = st.field.opp_monster
  if not _can_attack(mon) then return false end
  if not (st.field.ply_monster and st.field.ply_monster.card) then return false end

  local ak = _ai_knobs()
  local t = now or duels._now()
  st.pending_opp_attack = true
  st.pending_opp_attack_at = t + (tonumber(ak.attack_delay) or 0.75)
  return true
end

local function _ai_opp_queue_end_turn(pid, st, now)
  if not _ai_enabled() then return false end
  if not st then return false end
  local ak = _ai_knobs()
  st.pending_opp_end_turn_at = (now or duels._now()) + (tonumber(ak.end_turn_delay) or 0.6)
  return true
end

local function _ai_opp_execute_plan(pid, st, plan, now)
  if not (plan and st and st.opp and st.field) then
    _ai_opp_queue_end_turn(pid, st, now)
    return
  end

  -- Prevent re-entrance while animations are running
  if (st.summon_anim and st.summon_anim.active) or (st.pos_anim and st.pos_anim.active) or (st.attack_anim and st.attack_anim.active) then
    return
  end
  if st.pending_opp_attack or st.pending_opp_end_turn_at then
    return
  end

  _ai_clear_pending(st)

  -- 0) Cast spell immediately (if not tied to a summon)
  if plan.spell_id and not plan.play then
    _ai_opp_try_cast_spell(pid, st, plan.spell_id)
  end

  -- ------------------------------------------------------------
  -- 1) Play from hand (summon/set) if requested
  -- ------------------------------------------------------------
  if plan.play then
    local hand = st.opp.hand or {}
    if #hand <= 0 then
      _ai_opp_queue_end_turn(pid, st, now)
      return
    end

    local idx = tonumber(plan.play.hand_index or plan.play.idx or plan.play.i) or 1
    if idx < 1 then idx = 1 end
    if idx > #hand then idx = #hand end

    local card = hand[idx]
    if not card then
      _ai_opp_queue_end_turn(pid, st, now)
      return
    end

    -- Capture start position BEFORE removing from hand
    local hk = duels.KNOBS.HAND
    local start_tl_x, start_tl_y = _get_opponent_hand_card_tl(st, idx)
    local start_x, start_y = _apply_card_origin_if_needed(start_tl_x or 0, start_tl_y or 0, hk.scale or 1, hk.scale or 1)

    -- Remove from opponent hand
    table.remove(hand, idx)

    -- Clear UI bits that would look weird during AI action
    _erase_obj(pid, duels.CURSOR_SPRITE_ID .. "_obj")
    -- only clear opponent zone (prevents player-zone flicker)
    _erase_obj(pid, duels.MZ1_OBJ_ID)
    _erase_obj(pid, duels.ATTACK_MZ1_OBJ_ID)

    -- Redraw hands immediately (card leaves hand now)
    _draw_hands(pid, st)

    st.opp_summoned_this_turn = true

    local mz = duels.KNOBS.MZ1 or {}
    local end_x, end_y = _apply_card_origin_if_needed(mz.x, mz.y, mz.sx, mz.sy)
    local start_s = hk.scale or 1
    local end_s   = mz.sx or 1

    local atk_ro = tonumber(mz.ro) or 0
    local def_ro = (atk_ro + 90) % 360

    local kind = tostring(plan.play.kind or "summon")
    local pos  = tostring(plan.play.pos or "atk")

    -- What to do after this summon anim finishes
    st.ai_after_summon = {
      spell_id = plan.spell_id,
      attack = (plan.attack == true),
      end_turn = (plan.end_turn ~= false),
    }

    if kind == "set" then
      _start_summon_anim(pid, st, card, start_x, start_y, start_s, end_x, end_y, end_s, "set", {
        target_side = "opp",
        hidden = true,
        ro0 = 0,
        ro2 = def_ro,
        target_pos = "def",
      })
      return
    end

    -- kind == "summon"
    local ro2 = (pos == "def") and def_ro or atk_ro
    local target_pos = (pos == "def") and "def" or "atk"
    _start_summon_anim(pid, st, card, start_x, start_y, start_s, end_x, end_y, end_s, "summon", {
      target_side = "opp",
      ro0 = 0,
      ro2 = ro2,
      target_pos = target_pos,
    })
    return
  end

  -- ------------------------------------------------------------
  -- 2) Position toggle (only if already has a monster)
  -- ------------------------------------------------------------
  if plan.toggle_to_atk then
    st.ai_after_pos = {
      attack = (plan.attack == true),
      end_turn = (plan.end_turn ~= false),
    }

    _toggle_opponent_monster_position(pid, st)

    -- If an anim started, we'll wait for it to finish and then continue.
    if st.pos_anim and st.pos_anim.active then
      return
    end

    -- If toggle was not allowed / didn't animate, just fall through.
  end

  -- ------------------------------------------------------------
  -- 3) Attack (no summon this turn)
  -- ------------------------------------------------------------
  if plan.attack == true then
    local attacked = _ai_opp_queue_attack(pid, st, now)
    if attacked then return end
  end

  -- ------------------------------------------------------------
  -- 4) End turn
  -- ------------------------------------------------------------
  if plan.end_turn ~= false then
    _ai_opp_queue_end_turn(pid, st, now)
  end
end

local function _ai_opp_take_turn(pid, st, now)
  if not _ai_enabled() then return end
  if not st then return end
  if st.in_pause_menu or st.in_spells_menu then return end
  if st.turn ~= "opp" then return end
  if not duels_AI then return end

  local ak = _ai_knobs()
  local delay = tonumber(ak.think_delay) or 0.25
  local t = now or duels._now()

  -- Plan once per opponent turn
  if st.ai_planned_for_turn ~= (st.turn_index or 0) then
    st.ai_planned_for_turn = (st.turn_index or 0)
    st.ai_plan_at = t + delay
    st.ai_cached_plan = nil
  end

  if st.ai_cached_plan == nil and t >= (st.ai_plan_at or 0) then
    st.ai_cached_plan = duels_AI.plan(st, _ai_ctx(st))
    _ai_log(st, st.ai_cached_plan)
  end

  if st.ai_cached_plan then
    _ai_opp_execute_plan(pid, st, st.ai_cached_plan, now)

    -- Clear cache once we start an animation or schedule something
    if (st.summon_anim and st.summon_anim.active)
      or (st.pos_anim and st.pos_anim.active)
      or (st.pending_opp_attack)
      or (st.pending_opp_end_turn_at) then
      st.ai_cached_plan = nil
    end
  end
end



local function _hand_max_for_side(st, side)
  local hm = duels.KNOBS.HAND_MAX or {}
  if side == "opp" then
    return _clamp_int(hm.opponent or 4, 1, 10)
  end
  return _clamp_int(hm.player or 4, 1, 10)
end

local function _draw_one_at_start_of_turn(pid, st, side)
  if not st then return false end
  side = side or "ply"
  local p = (side == "opp") and st.opp or st.ply
  if not p then return false end

  local hand = p.hand or {}
  local max = _hand_max_for_side(st, side)
  if #hand >= max then return false end

  local c = _draw_random_from_deck(p)
  if not c then return false end
  hand[#hand + 1] = c
  return true
end

local function _draw_anim_knobs()
  local d = (duels.KNOBS and duels.KNOBS.DRAW_ANIM) or {}
  return {
    slide_dy       = tonumber(d.slide_dy) or 16,
    slide_duration = tonumber(d.slide_duration) or 0.22,
    move_duration  = tonumber(d.move_duration) or 0.28,
    max_visible    = tonumber(d.max_visible) or 10,
    stack_dx       = tonumber(d.stack_dx) or 1,
    stack_dy       = tonumber(d.stack_dy) or -1,
    z              = (duels.KNOBS.HAND.z or 0) - 25,
  }
end

local function _erase_deck_stack(pid)
  local dk = _draw_anim_knobs()
  for i = 1, dk.max_visible do
    _erase_obj(pid, duels.PLY_DECK_OBJ_PREFIX .. i)
    _erase_obj(pid, duels.OPP_DECK_OBJ_PREFIX .. i)
  end
  _erase_obj(pid, duels.DRAW_CARD_OBJ_ID)
end

local function _draw_deck_stack(pid, st, side)
  if not st then return end
  local dk = _draw_anim_knobs()
  local hk = duels.KNOBS.HAND
  local hsx, hsy = hk.scale, hk.scale

  local p = (side == "opp") and st.opp or st.ply
  local pile = (p and p.pile) or {}
  local n = #pile
  local vis = math.min(n, dk.max_visible)

  local prefix = (side == "opp") and duels.OPP_DECK_OBJ_PREFIX or duels.PLY_DECK_OBJ_PREFIX
  local base = (side == "opp") and duels.KNOBS.OPP_HAND_POS or duels.KNOBS.PLY_HAND_POS

  -- Deck anchor: exactly under the hand’s tuned base (revealed by sliding the hand away)
  local x0_tl = (base.x or 0)
  local y0_tl = (base.y or 0)

  local fd_sid = _ensure_facedown_sprite(pid, st)

  -- Draw stack bottom->top
  for i = 1, vis do
    local x_tl = x0_tl + (i - 1) * dk.stack_dx
    local y_tl = y0_tl + (i - 1) * dk.stack_dy
    local x, y = _apply_card_origin_if_needed(x_tl, y_tl, hsx, hsy)
    _draw_sprite_obj(pid, fd_sid, prefix .. i, x, y, hsx, hsy, dk.z + i, duels.CARD_STATE, base.ro)
  end

  -- erase stale
  for i = vis + 1, dk.max_visible do
    _erase_obj(pid, prefix .. i)
  end
end

local function _hand_slot_tl_for_count(st, side, count_new, index_new)
  local hk = duels.KNOBS.HAND
  local step_x = hk.spacing_x or 0
  local base = (side == "opp") and duels.KNOBS.OPP_HAND_POS or duels.KNOBS.PLY_HAND_POS

  local start_x = _hand_start_x(base.x, count_new, step_x, hk)
  local y_tl = base.y or 0
  local x_tl = start_x + (index_new - 1) * step_x
  return x_tl, y_tl
end

local function _start_draw_anim(pid, st, side)
  if not st then return false end
  if st.draw_anim and st.draw_anim.active then return false end

  local p = (side == "opp") and st.opp or st.ply
  if not p then return false end

  local hand = p.hand or {}
  local max = _hand_max_for_side(st, side)
  if #hand >= max then return false end

  if not (p.pile and #p.pile > 0) then
    return false
  end

  local dk = _draw_anim_knobs()
  local vis_before = math.min(#p.pile, dk.max_visible)

  st.draw_anim = {
    active = true,
    side = side,
    stage = 1,          -- 1=slide_out, 2=move, 3=slide_in
    t0 = duels._now(),
    pending_draw = true,
    vis_before = vis_before,
    drawn_card = nil,
  }

  return true
end

local function _update_draw_anim(pid, st, now)
  local anim = st.draw_anim
  if not (anim and anim.active) then return true end

  local dk = _draw_anim_knobs()
  local side = anim.side
  local dir = (side == "opp") and -1 or 1

  local function set_hand_offset(v)
    if side == "opp" then st.opp_hand_slide_dy = v else st.ply_hand_slide_dy = v end
  end

  local function finish()
    -- restore
    st.ply_hand_slide_dy = 0
    st.opp_hand_slide_dy = 0
    anim.active = false
    st.draw_anim = nil
    _erase_deck_stack(pid)
    _draw_hands(pid, st)
    return true
  end

  if anim.stage == 1 then
    local u = (now - anim.t0) / math.max(0.001, dk.slide_duration)
    if u >= 1 then
      u = 1
      anim.stage = 2
      anim.t0 = now
    end
    local eased = _smoothstep(_clamp01(u))
    set_hand_offset(dir * dk.slide_dy * eased)

    _draw_hands(pid, st)
    _draw_deck_stack(pid, st, side)
    _erase_obj(pid, duels.DRAW_CARD_OBJ_ID)
    return false
  end

  if anim.stage == 2 then
    -- draw exactly once at the start of the “pickup/move” stage
    local p = (side == "opp") and st.opp or st.ply
    if anim.pending_draw then
      local c = _draw_random_from_deck(p)
      if not c then
        return finish()
      end
      anim.drawn_card = c
      anim.pending_draw = false
      anim.hand_count_before = #(p.hand or {})
    end

    set_hand_offset(dir * dk.slide_dy)

    local u = (now - anim.t0) / math.max(0.001, dk.move_duration)
    if u >= 1 then u = 1 end
    local eased = _smoothstep(_clamp01(u))

    -- moving card start = “top of stack” position before draw
    local base = (side == "opp") and duels.KNOBS.OPP_HAND_POS or duels.KNOBS.PLY_HAND_POS
    local x0_tl = (base.x or 0) + (math.max(1, anim.vis_before) - 1) * dk.stack_dx
    local y0_tl = (base.y or 0) + (math.max(1, anim.vis_before) - 1) * dk.stack_dy

    -- moving card end = new hand slot (count+1), at the fully-slid hand position
    local new_count = (anim.hand_count_before or 0) + 1
    local x1_tl, y1_tl = _hand_slot_tl_for_count(st, side, new_count, new_count)
    y1_tl = (y1_tl or 0) + (dir * dk.slide_dy)

    local x_tl = _lerp(x0_tl, x1_tl, eased)
    local y_tl = _lerp(y0_tl, y1_tl, eased)

    local hk = duels.KNOBS.HAND
    local hsx, hsy = hk.scale, hk.scale
    local x, y = _apply_card_origin_if_needed(x_tl, y_tl, hsx, hsy)

    _draw_hands(pid, st)
    _draw_deck_stack(pid, st, side)
    local fd_sid = _ensure_facedown_sprite(pid, st)
    _draw_sprite_obj(pid, fd_sid, duels.DRAW_CARD_OBJ_ID, x, y, hsx, hsy, (dk.z + 999), duels.CARD_STATE, base.ro)

    if u >= 1 then
      -- Commit card into hand AFTER the card reaches the hand area
      p.hand[#p.hand + 1] = anim.drawn_card
      anim.drawn_card = nil
      _erase_obj(pid, duels.DRAW_CARD_OBJ_ID)

      anim.stage = 3
      anim.t0 = now
    end

    return false
  end

  if anim.stage == 3 then
    local u = (now - anim.t0) / math.max(0.001, dk.slide_duration)
    if u >= 1 then u = 1 end
    local eased = _smoothstep(_clamp01(u))

    set_hand_offset(dir * dk.slide_dy * (1 - eased))

    _draw_hands(pid, st)
    _draw_deck_stack(pid, st, side)

    if u >= 1 then
      return finish()
    end
    return false
  end

  return finish()
end

-- Starts a new turn for `side` ("ply" or "opp"), applying draw rules + per-turn resets.
-- Draw rule: no draw on each player's first turn; draw 1 card starting from their 2nd turn.
local function _begin_turn(pid, st, side)
  if not st then return end
  side = side or "ply"

  st.turn = side
  st.turn_index = (st.turn_index or 0) + 1
  -- clear any opponent end-turn scheduling on a new turn
  st.pending_opp_end_turn_at = nil
  st.pending_opp_attack = false
  st.pending_opp_attack_at = nil


  if duels._spells and duels._spells.on_begin_turn then
    pcall(duels._spells.on_begin_turn, st, side)
  end

  if side == "opp" then
    st.opp_turn = (st.opp_turn or 0) + 1
    st.opp_summoned_this_turn = false
  else
    st.ply_turn = (st.ply_turn or 0) + 1
    st.ply_summoned_this_turn = false
  end

  -- Auto-apply "atk_then_def" position change on the NEXT opponent turn (can't change position same turn as summon).
  if side == "opp" and st.pending_opp_pos_on_next_opp_turn then
    st.pending_opp_pos_on_next_opp_turn = nil
    local mon = st.field and st.field.opp_monster
    if mon and mon.card and (not mon.facedown) and ((mon.pos or "atk") == "atk") then
      _toggle_opponent_monster_position(pid, st)
    end
  end

  local n = (side == "opp") and (st.opp_turn or 1) or (st.ply_turn or 1)
  if n > 1 then
    local started = _start_draw_anim(pid, st, side)
    if not started then
      _draw_one_at_start_of_turn(pid, st, side)
    end
  end

  -- close any modal menus on turn switch
  st.in_summon_menu = false
  st.in_field_menu = false
  st.selected_hand_index = nil
  _erase_summon_menu(pid)
  _erase_field_menu(pid)

  -- redraw everything
  _draw_hands(pid, st)
  _draw_monsters(pid, st)

  -- Kick AI on opponent turns (summon or attack)
  if side == "opp" and not st.pending_reveal_battle then
    _ai_opp_take_turn(pid, st)
  end
end


local function _end_turn(pid, st)
  if not st then return end
  _begin_turn(pid, st, "opp")
end




-- ---------------------------------------------------------------------------
-- Pause menu (End Turn / Concede)
-- ---------------------------------------------------------------------------


local function _erase_pause_menu(pid)
  _erase_obj(pid, duels.PAUSE_MENU_TURN_OBJ_ID)
  _erase_obj(pid, "duel_pause_spell")
  _erase_obj(pid, duels.PAUSE_MENU_CON_OBJ_ID)
  _erase_obj(pid, duels.PAUSE_MENU_CURSOR_OBJ_ID)
end

local function _draw_pause_menu(pid, st)
  if not st or not st.in_pause_menu then
    _erase_pause_menu(pid)
    return
  end

  local mk = duels.KNOBS.PAUSE_MENU or {}
  local now = duels._now()

  -- If slide_enabled gets toggled ON while open, restart the slide.
  local slide_enabled = (mk.slide_enabled ~= false)
  if st.pause_menu_last_slide_enabled == nil then
    st.pause_menu_last_slide_enabled = slide_enabled
  elseif slide_enabled and (st.pause_menu_last_slide_enabled == false) then
    st.pause_menu_opened_at = now
  end
  st.pause_menu_last_slide_enabled = slide_enabled

  local base_x = tonumber(mk.x) or 0
  local base_y = tonumber(mk.y) or 0
  local z = tonumber(mk.z) or -58
  local sx = tonumber(mk.sx) or 2
  local sy = tonumber(mk.sy) or 2
  local gap_y = tonumber(mk.gap_y) or 18

  -- Slide-in animation (from left -> final)
  local slide_dx = 0
  if slide_enabled then
    local dur = tonumber(mk.slide_duration) or 0.18
    local t0 = st.pause_menu_opened_at or now
    local t = (now - t0) / ((dur > 0) and dur or 0.001)
    if t < 0 then t = 0 end
    if t > 1 then t = 1 end
    local te = _smoothstep(_clamp01(t))
    local from_x = tonumber(mk.slide_from_x) or -40
    slide_dx = from_x * (1 - te)
  end

  local x = base_x + slide_dx
  local y_turn  = base_y
  local y_spell = base_y + gap_y
  local y_con   = base_y + gap_y * 2

  -- allocate resources
  _alloc_sprite(pid, duels.TURNCON_SPRITE_ID, duels.TURNCON_TEX, duels.TURNCON_ANIM, duels.TURNCON_STATE_TURN)
  _alloc_sprite(pid, duels.CURSOR_SPRITE_ID, duels.CURSOR_TEX, duels.CURSOR_ANIM, duels.CURSOR_STATE)

  -- draw buttons
  _draw_sprite_obj(pid, duels.TURNCON_SPRITE_ID, duels.PAUSE_MENU_TURN_OBJ_ID,  x, y_turn,  sx, sy, z, duels.TURNCON_STATE_TURN,  nil)
  _draw_sprite_obj(pid, duels.TURNCON_SPRITE_ID, "duel_pause_spell", x, y_spell, sx, sy, z, "spell", nil)
  _draw_sprite_obj(pid, duels.TURNCON_SPRITE_ID, duels.PAUSE_MENU_CON_OBJ_ID,   x, y_con,   sx, sy, z, duels.TURNCON_STATE_CON,   nil)

  -- rotated cursor to the right of the selected button
  local choice = st.pause_choice or 1 -- 1=turn, 2=spells, 3=concede
  local icon_y = (choice == 3) and y_con or ((choice == 2) and y_spell or y_turn)

local icon_w = 16 * sx
  local icon_h = 16 * sy

  local cx = x + icon_w + (tonumber(mk.cursor_gap_x) or 10)
  local cy = icon_y + icon_h * 0.5

  cx = cx + (tonumber(mk.cursor_off_x) or 0)
  cy = cy + (tonumber(mk.cursor_off_y) or 0)

  _draw_sprite_obj(
    pid,
    duels.CURSOR_SPRITE_ID,
    duels.PAUSE_MENU_CURSOR_OBJ_ID,
    cx, cy,
    tonumber(mk.cursor_sx) or 2,
    tonumber(mk.cursor_sy) or 2,
    tonumber(duels.KNOBS.CURSOR and duels.KNOBS.CURSOR.z) or -60,
    duels.CURSOR_STATE,
    tonumber(mk.cursor_ro) or 90
  )
end


-- ---------------------------------------------------------------------------
-- Spells menu (UI only)
-- ---------------------------------------------------------------------------
local function _erase_spells_menu(pid)
  _erase_obj(pid, duels.SPELLS_MENU_BG_OBJ_ID)
  _erase_obj(pid, duels.SPELLS_MENU_CURSOR_OBJ_ID)

  local defs = (duels._spells and duels._spells.get_spell_defs and duels._spells.get_spell_defs()) or {}
  local n = #defs

  local mk = duels.KNOBS.SPELLS_MENU or {}
  local max_cost = _clamp_int(mk.max_cost or 6, 1, 24)

  for i = 1, n do
    _erase_obj(pid, duels.SPELLS_MENU_ICON_PREFIX .. i)
    for j = 1, max_cost do
      _erase_obj(pid, duels.SPELLS_MENU_COST_PREFIX .. i .. "_" .. j)
    end
    erase_text(pid, duels.SPELLS_MENU_TEXT_NAME_PREFIX .. i)
    erase_text(pid, duels.SPELLS_MENU_TEXT_DESC_PREFIX .. i)
  end
end

local function _draw_spells_menu(pid, st)
  if not st or not st.in_spells_menu then
    _erase_spells_menu(pid)
    return
  end

  local mk = duels.KNOBS.SPELLS_MENU or {}
  if mk.enabled == false then
    _erase_spells_menu(pid)
    return
  end

  -- Ensure displayer fonts are ready; otherwise text may not render.
  ensure_player_fonts(pid)


  local defs = (duels._spells and duels._spells.get_spell_defs and duels._spells.get_spell_defs()) or {}
  local n = #defs
  if n <= 0 then
    _erase_spells_menu(pid)
    return
  end

  local base_x = tonumber(mk.x) or 40
  local base_y = tonumber(mk.y) or 30
  local z = tonumber(mk.z) or 235
  local sx = tonumber(mk.sx) or 1
  local sy = tonumber(mk.sy) or 1

  local pad_x = tonumber(mk.pad_x) or 10
  local pad_y = tonumber(mk.pad_y) or 10
  local row_h = tonumber(mk.row_h) or 20
  local rows = _clamp_int(mk.visible_rows or 4, 1, 12)

  local icon_sx = tonumber(mk.icon_sx) or 1.5
  local icon_sy = tonumber(mk.icon_sy) or icon_sx
  local icon_gap_x = tonumber(mk.icon_gap_x) or 6

  local name_font = mk.name_font or "THICK"
  local name_scale = tonumber(mk.name_scale) or 1.6
  local desc_font = mk.desc_font or "THICK"
  local desc_scale = tonumber(mk.desc_scale) or 1.1

  local name_off_y = tonumber(mk.name_off_y) or 0
  local desc_off_y = tonumber(mk.desc_off_y) or 10

  local cost_sx = tonumber(mk.cost_sx) or 1.0
  local cost_sy = tonumber(mk.cost_sy) or cost_sx
  local cost_dx = tonumber(mk.cost_dx) or 7
  local cost_off_y = tonumber(mk.cost_off_y) or 2
  local max_cost = _clamp_int(mk.max_cost or 6, 1, 24)

  -- Allocate sprites
  _alloc_sprite(pid, duels.SPELLSUI_SPRITE_ID, duels.SPELLSUI_TEX, duels.SPELLSUI_ANIM, duels.SPELLSUI_STATE)
  _alloc_sprite(pid, duels.SPELLICONS_SPRITE_ID, duels.SPELLICONS_TEX, duels.SPELLICONS_ANIM, (defs[1] and defs[1].id) or "")
  _alloc_sprite(pid, duels.SPELLCOUNTER_SPRITE_ID, duels.SPELLCOUNTER_TEX, duels.SPELLCOUNTER_ANIM, duels.SPELLCOUNTER_STATE)

  -- Background
  _draw_sprite_obj(pid, duels.SPELLSUI_SPRITE_ID, duels.SPELLS_MENU_BG_OBJ_ID, base_x, base_y, sx, sy, z, duels.SPELLSUI_STATE, nil)

  -- Selection + scrolling
  local choice = _clamp_int(st.spells_choice or 1, 1, n)
  st.spells_choice = choice

  local top = tonumber(st.spells_scroll) or 1
  local max_top = math.max(1, n - rows + 1)
  if top < 1 then top = 1 end
  if top > max_top then top = max_top end

  if choice < top then top = choice end
  if choice > (top + rows - 1) then top = choice - rows + 1 end
  if top < 1 then top = 1 end
  if top > max_top then top = max_top end

  st.spells_scroll = top

  local list_x = base_x + pad_x
  local list_y = base_y + pad_y

  -- We don't know icon dimensions; we place name to the right of the icon with a knob gap.
  local name_x = list_x + (16 * icon_sx) + icon_gap_x
  local cost_right_x = base_x + (tonumber(mk.w) or 160) - pad_x

  local function draw_cost(spell_i, cost, row_y)
    cost = _clamp_int(cost or 0, 0, max_cost)
    for j = 1, max_cost do
      local obj_id = duels.SPELLS_MENU_COST_PREFIX .. spell_i .. "_" .. j
      if j <= cost then
        local x = cost_right_x - (cost - j) * cost_dx
        local y = row_y + cost_off_y
        _draw_sprite_obj(pid, duels.SPELLCOUNTER_SPRITE_ID, obj_id, x, y, cost_sx, cost_sy, z + 2, duels.SPELLCOUNTER_STATE, nil)
      else
        _erase_obj(pid, obj_id)
      end
    end
  end

  -- Draw visible range; erase others
  local vis_lo = top
  local vis_hi = math.min(n, top + rows - 1)

  for i = 1, n do
    local def = defs[i]
    local icon_obj = duels.SPELLS_MENU_ICON_PREFIX .. i
    local name_id = duels.SPELLS_MENU_TEXT_NAME_PREFIX .. i
    local desc_id = duels.SPELLS_MENU_TEXT_DESC_PREFIX .. i

    if i >= vis_lo and i <= vis_hi then
      local r = i - vis_lo
      local row_y = list_y + r * row_h
      local row_x = list_x

      -- icon
      _draw_sprite_obj(pid, duels.SPELLICONS_SPRITE_ID, icon_obj, row_x, row_y, icon_sx, icon_sy, z + 1, def.id or "", nil)

      -- name + desc (displayer)
      draw_text(pid, tostring(def.name or def.id or ""), name_x, row_y + name_off_y, name_font, name_scale, z + 3, name_id)
      draw_text(pid, tostring(def.desc or ""), name_x, row_y + desc_off_y, desc_font, desc_scale, z + 3, desc_id)

      -- cost
      draw_cost(i, tonumber(def.cost) or 0, row_y)

    else
      _erase_obj(pid, icon_obj)
      for j = 1, max_cost do
        _erase_obj(pid, duels.SPELLS_MENU_COST_PREFIX .. i .. "_" .. j)
      end
      erase_text(pid, name_id)
      erase_text(pid, desc_id)
    end
  end

  -- Cursor to the left of the selected row
  _alloc_sprite(pid, duels.CURSOR_SPRITE_ID, duels.CURSOR_TEX, duels.CURSOR_ANIM, duels.CURSOR_STATE)
  local sel_r = choice - vis_lo
  if sel_r < 0 then sel_r = 0 end
  if sel_r > (rows - 1) then sel_r = rows - 1 end

  local icon_y = list_y + sel_r * row_h
  local cx = list_x - (tonumber(mk.cursor_gap_x) or 10)
  local cy = icon_y + row_h * 0.5
  cx = cx + (tonumber(mk.cursor_off_x) or 0)
  cy = cy + (tonumber(mk.cursor_off_y) or 0)

  _draw_sprite_obj(
    pid,
    duels.CURSOR_SPRITE_ID,
    duels.SPELLS_MENU_CURSOR_OBJ_ID,
    cx, cy,
    tonumber(mk.cursor_sx) or 2,
    tonumber(mk.cursor_sy) or 2,
    tonumber(duels.KNOBS.CURSOR and duels.KNOBS.CURSOR.z) or (z + 4),
    duels.CURSOR_STATE,
    tonumber(mk.cursor_ro) or 270
  )
end

-- ---------------------------------------------------------------------------
-- Rendering: field + hands
-- ---------------------------------------------------------------------------
local function _draw_field(pid, st)
  _alloc_sprite(pid, duels.FIELD_SPRITE_ID, duels.FIELD_TEX, duels.FIELD_ANIM, duels.FIELD_STATE)

  local fk = duels.KNOBS.FIELD
  _draw_sprite_obj(pid, duels.FIELD_SPRITE_ID, duels.FIELD_SPRITE_ID .. "_obj",
    fk.x, fk.y, fk.sx, fk.sy, fk.z, duels.FIELD_STATE, nil
  )
end

local function _erase_point_counters(pid)
  for i = 1, 3 do
    _erase_obj(pid, duels.PLY_POINTS_OBJ_PREFIX .. i)
    _erase_obj(pid, duels.OPP_POINTS_OBJ_PREFIX .. i)
  end
end

function _draw_point_counters(pid, st)
  if not st then return end
  local pk = duels.KNOBS.POINT_COUNTER or {}
  if pk.enabled == false then
    _erase_point_counters(pid)
    return
  end

  _alloc_sprite(pid, duels.POINTCOUNTER_SPRITE_ID, duels.POINTCOUNTER_TEX, duels.POINTCOUNTER_ANIM, "empty1")

  local sx = tonumber(pk.sx) or 2.0
  local sy = tonumber(pk.sy) or sx
  local z  = tonumber(pk.z) or 200

  -- Horizontal spacing between pips (supports your older dy12/dy23 knobs as fallback)
  local dx12 = tonumber(pk.dx12)
  if dx12 == nil then dx12 = tonumber(pk.dy12) end
  if dx12 == nil then dx12 = 10 end

  local dx23 = tonumber(pk.dx23)
  if dx23 == nil then dx23 = tonumber(pk.dy23) end
  if dx23 == nil then dx23 = dx12 end

  local empty_states  = pk.empty_states  or { "empty1",  "empty2",  "empty3" }
  local filled_states = pk.filled_states or { "filled1", "filled2", "filled3" }

  local ply_pts = _clamp_int(st.ply_points or 0, 0, 3)
  local opp_pts = _clamp_int(st.opp_points or 0, 0, 3)

  local function draw_set(base_x, base_y, filled_count, prefix)
    base_x = tonumber(base_x) or 0
    base_y = tonumber(base_y) or 0

    local xs = {
      base_x,
      base_x + dx12,
      base_x + dx12 + dx23,
    }

    for i = 1, 3 do
      local state = (filled_count >= i)
        and (filled_states[i] or ("filled" .. i))
        or  (empty_states[i]  or ("empty"  .. i))

      _draw_sprite_obj(pid, duels.POINTCOUNTER_SPRITE_ID, prefix .. i, xs[i], base_y, sx, sy, z, state, nil)
    end
  end

  draw_set(pk.ply_x, pk.ply_y, ply_pts, duels.PLY_POINTS_OBJ_PREFIX)
  draw_set(pk.opp_x, pk.opp_y, opp_pts, duels.OPP_POINTS_OBJ_PREFIX)
end

-- ---------------------------------------------------------------------------
-- Spell counters (debug UI)
-- ---------------------------------------------------------------------------
function duels._erase_spell_counters(pid)
  local sk = duels.KNOBS.SPELL_COUNTER or {}
  local maxn = _clamp_int(sk.max or 6, 1, 24)
  for i = 1, maxn do
    _erase_obj(pid, duels.PLY_SPELL_OBJ_PREFIX .. i)
    _erase_obj(pid, duels.OPP_SPELL_OBJ_PREFIX .. i)
  end
end
function duels._draw_spell_counters(pid, st)
  if not st then return end
  local sk = duels.KNOBS.SPELL_COUNTER or {}
  if sk.enabled == false then
    duels._erase_spell_counters(pid)
    return
  end

  _alloc_sprite(pid, duels.SPELLCOUNTER_SPRITE_ID, duels.SPELLCOUNTER_TEX, duels.SPELLCOUNTER_ANIM, duels.SPELLCOUNTER_STATE)

  local sx = tonumber(sk.sx) or 2.0
  local sy = tonumber(sk.sy) or sx
  local z  = tonumber(sk.z)  or 210
  local dx = tonumber(sk.dx) or 16
  local dy = tonumber(sk.dy) or 0
  local maxn = _clamp_int(sk.max or 6, 1, 24)

  local n_ply = tonumber(st.ply_spell_counters) or 0
  local n_opp = tonumber(st.opp_spell_counters) or 0
  if sk.debug_draw_all then
    n_ply = maxn
    n_opp = maxn
  end
  n_ply = _clamp_int(n_ply, 0, maxn)
  n_opp = _clamp_int(n_opp, 0, maxn)

  local function draw_set(base_x, base_y, dir, count, prefix)
    base_x = tonumber(base_x) or 0
    base_y = tonumber(base_y) or 0
    dir = tonumber(dir) or 1
    for i = 1, maxn do
      local obj_id = prefix .. i
      if i <= count then
        local x = base_x + (i - 1) * dx * dir
        local y = base_y + (i - 1) * dy
        _draw_sprite_obj(pid, duels.SPELLCOUNTER_SPRITE_ID, obj_id, x, y, sx, sy, z, duels.SPELLCOUNTER_STATE, nil)
      else
        _erase_obj(pid, obj_id)
      end
    end
  end

  draw_set(sk.ply_x, sk.ply_y, sk.ply_dir or  1, n_ply, duels.PLY_SPELL_OBJ_PREFIX)
  draw_set(sk.opp_x, sk.opp_y, sk.opp_dir or -1, n_opp, duels.OPP_SPELL_OBJ_PREFIX)
end

function _end_duel_by_points(pid, st)
  if not (pid and st) then return end
  if st.duel_over then return end

  local p = tonumber(st.ply_points) or 0
  local o = tonumber(st.opp_points) or 0
  if p < 3 and o < 3 then return end

  local outcome
  if p >= 3 and o >= 3 then outcome = "tie"
  elseif p >= 3 then outcome = "ply"
  else outcome = "opp"
  end

  st.duel_over = true
  st.duel_outcome = outcome

  last_duel_result_by_pid[pid] = {
    outcome = outcome,              -- "ply" | "opp" | "tie"
    ply_points = p,
    opp_points = o,
    ended_turn_index = st.turn_index or 0,
  }

  -- ------------------------------------------------------------
  -- Notify once: on_finish + JobBBS
  -- ------------------------------------------------------------
  if not st._finish_notified then
    st._finish_notified = true

    local cfg = st.cfg or {}
    local npc_name = cfg.npc_name or "NPC Duelist"

    local res = {
      player_won = (outcome == "ply"),
      outcome = outcome,
      ply_points = p,
      opp_points = o,
      npc_name = npc_name,
      ended_turn_index = st.turn_index or 0,
    }

    -- 1) NPC / caller callback
    local cb = cfg.on_finish or cfg._on_finish
    if cb then
      pcall(cb, res)
    end

    -- 2) JobBBS duel win tracking (expects winner == 1 or "player")
    local JB = nil
    if duels then
      duels._jobbbs_cached = duels._jobbbs_cached or (function()
        local ok, M = pcall(require, "scripts/jobbbs/JobBBS")
        if ok and type(M) == "table" then return M end
        ok, M = pcall(require, "scripts/jobbbs/jobbbs")
        if ok and type(M) == "table" then return M end
        return nil
      end)()
      JB = duels._jobbbs_cached
    end

    if JB and JB.on_npc_duel_result then
      local winner = (outcome == "ply") and "player" or ((outcome == "opp") and "opponent" or "tie")
      pcall(JB.on_npc_duel_result, pid, {
        winner = winner,
        npc_name = npc_name,
        ply_points = p,
        opp_points = o,
      })
    end
  end

  local hold = tonumber((duels.KNOBS.POINT_COUNTER or {}).end_hold) or 1.0
  st.pending_close_at = duels._now() + hold
end

function _draw_hands(pid, st)
  if not st then return end

  local hk = duels.KNOBS.HAND
  local hsx, hsy = hk.scale, hk.scale
  local hz = hk.z
  local step_x = hk.spacing_x or 0

  local fd_sid = _ensure_facedown_sprite(pid, st)

  -- -------------------------------------------------------------------------
  -- Opponent hand (FaceDown)
  -- -------------------------------------------------------------------------
  local opp_count = #(st.opp.hand or {})
  do
    local oh = duels.KNOBS.OPP_HAND_POS
    local start_x = _hand_start_x(oh.x, opp_count, step_x, hk)
    local y_tl = (oh.y or 0) + (st.opp_hand_slide_dy or 0)

    for i = 1, opp_count do
      local x_tl = start_x + (i - 1) * step_x
      local x, y = _apply_card_origin_if_needed(x_tl, y_tl, hsx, hsy)
      local zi = (hz or 0) + i
      _draw_sprite_obj(pid, fd_sid, duels.OPP_HAND_OBJ_PREFIX .. i, x, y, hsx, hsy, zi, duels.CARD_STATE, oh.ro)
    end

    -- erase stale objects beyond current count
    local max_wipe = _clamp_int(hk.max_cards_to_clear or 10, 1, 50)
    for i = opp_count + 1, max_wipe do
      _erase_obj(pid, duels.OPP_HAND_OBJ_PREFIX .. i)
    end
  end

  -- -------------------------------------------------------------------------
  -- Player hand
  -- -------------------------------------------------------------------------
  st.card_sprites_by_tex = st.card_sprites_by_tex or {}
  st.allocated_card_sprites = st.allocated_card_sprites or {}

  -- Cache what texture each hand slot object last showed.
  -- Needed because ONB sprite objects may not "rebind" to a new sprite_id cleanly.
  st.ply_hand_obj_tex = st.ply_hand_obj_tex or {}

  local ply_count = #(st.ply.hand or {})
  do
    local ph = duels.KNOBS.PLY_HAND_POS
    local start_x = _hand_start_x(ph.x, ply_count, step_x, hk)
    local y_tl = (ph.y or 0) + (st.ply_hand_slide_dy or 0)
    local lift = tonumber(hk.highlight_lift_y) or 0

    local highlight_i = nil
    if st.draw_anim and st.draw_anim.active then
      highlight_i = nil
    end
    if st.in_summon_menu then
      highlight_i = (st.selected_hand_index or st.cursor_index or 1)
    elseif (st.cursor_mode or "hand") == "hand" then
      highlight_i = (st.cursor_index or 1)
    end

    for i = 1, ply_count do
      local card = st.ply.hand[i]
      if card and card.tex then
        local sprite_id = _ensure_card_sprite(pid, st, card)

        local x_tl = start_x + (i - 1) * step_x
        local y_tl_i = y_tl
        if i == highlight_i then
          y_tl_i = y_tl_i - lift
        end

        local x, y = _apply_card_origin_if_needed(x_tl, y_tl_i, hsx, hsy)

        local obj_id = duels.PLY_HAND_OBJ_PREFIX .. i

        -- If this slot is about to show a different texture than last time, erase first.
        -- This prevents "summon left -> right disappears / left duplicates" visuals.
        if st.ply_hand_obj_tex[i] ~= card.tex then
          _erase_obj(pid, obj_id)
          st.ply_hand_obj_tex[i] = card.tex
        end

        local zi = (hz or 0) + i
        _draw_sprite_obj(pid, sprite_id, obj_id, x, y, hsx, hsy, zi, duels.CARD_STATE, ph.ro)
      end
    end

    -- erase stale objects beyond current count + clear cache for those slots
    local max_wipe = _clamp_int(hk.max_cards_to_clear or 10, 1, 50)
    for i = ply_count + 1, max_wipe do
      _erase_obj(pid, duels.PLY_HAND_OBJ_PREFIX .. i)
      st.ply_hand_obj_tex[i] = nil
    end
  end

  -- Cursor/UI last, so it sits on top and uses final positions
  if not (st.in_summon_menu or st.in_field_menu or st.in_pause_menu or st.in_spells_menu
    or (st.pos_anim and st.pos_anim.active)
    or (st.attack_anim and st.attack_anim.active)
    or (st.draw_anim and st.draw_anim.active)) then
    _update_cursor(pid, st)
  else
    _erase_obj(pid, duels.CURSOR_SPRITE_ID .. "_obj")
  end

  _update_info_panel(pid, st)
  _update_opp_info_panel(pid, st)
  duels._draw_spell_counters(pid, st)
  _draw_pause_menu(pid, st)
  _draw_spells_menu(pid, st)
end

function _erase_summon_menu(pid)
  _erase_obj(pid, duels.SUMMONS_SPRITE_ID .. "_summon")
  _erase_obj(pid, duels.SUMMONS_SPRITE_ID .. "_set")
  _erase_obj(pid, duels.MINICURSOR_SPRITE_ID .. "_obj")
end


-- Field action menu object ids

function _erase_field_menu(pid)
  _erase_obj(pid, duels.FIELD_MENU_ATK_OBJ_ID)
  _erase_obj(pid, duels.FIELD_MENU_POS_OBJ_ID)
  _erase_obj(pid, duels.MINICURSOR_SPRITE_ID .. "_obj")
end

local function _get_mz2_top_left()
  local k = duels.KNOBS.MZ2 or {}
  local x = tonumber(k.x) or 0
  local y = tonumber(k.y) or 0

  if duels.KNOBS.CARD_POS_MODE == "origin" then
    -- Convert origin coords -> top-left coords
    local o = duels.KNOBS.CARD_ORIGIN or { ox = 0, oy = 0 }
    local ox = tonumber(o.ox) or 0
    local oy = tonumber(o.oy) or 0
    local sx = tonumber(k.sx) or 1
    local sy = tonumber(k.sy) or 1
    x = x - ox * _abs(sx)
    y = y - oy * _abs(sy)
  end

  return x, y
end

local function _draw_field_menu(pid, st)
  if not st then return end
  if not (st.field and st.field.ply_monster and st.field.ply_monster.card) then
    _erase_field_menu(pid)
    return
  end

  local mk = duels.KNOBS.FIELD_MENU or {}
  local mini = duels.KNOBS.MINICURSOR or {}

  local x_tl, y_tl = _get_mz2_top_left()

  -- Base point (layout space) near bottom of field card
  local base_x = x_tl + (mk.offset_x or 0)
  local base_y = y_tl + (mk.offset_y or 0)

  local gap = mk.gap_x or 18
  local atk_x = base_x - gap * 0.5
  local pos_x = base_x + gap * 0.5
  local icon_y = base_y

  -- allocate sprites
  _alloc_sprite(pid, duels.ATKPOS_SPRITE_ID, duels.ATKPOS_TEX, duels.ATKPOS_ANIM, duels.ATKPOS_STATE_ATK)
  _alloc_sprite(pid, duels.MINICURSOR_SPRITE_ID, duels.MINICURSOR_TEX, duels.MINICURSOR_ANIM, duels.MINICURSOR_STATE)

  -- draw icons
  _draw_sprite_obj(pid, duels.ATKPOS_SPRITE_ID, duels.FIELD_MENU_ATK_OBJ_ID, atk_x, icon_y, mk.sx, mk.sy, mk.z, duels.ATKPOS_STATE_ATK, nil)
  _draw_sprite_obj(pid, duels.ATKPOS_SPRITE_ID, duels.FIELD_MENU_POS_OBJ_ID, pos_x, icon_y, mk.sx, mk.sy, mk.z, duels.ATKPOS_STATE_POS, nil)

  -- minicursor on selection
  local choice = st.field_choice or 1 -- 1=atk, 2=pos
  local cx = (choice == 2) and pos_x or atk_x
  local cy = icon_y
  cx = cx + (mini.offset_x or 0)
  cy = cy + (mini.offset_y or 0)

  _draw_sprite_obj(pid, duels.MINICURSOR_SPRITE_ID, duels.MINICURSOR_SPRITE_ID .. "_obj", cx, cy, mini.sx, mini.sy, mini.z, duels.MINICURSOR_STATE, nil)
end


local function _get_player_hand_card_tl(st, index)
  local hk = duels.KNOBS.HAND
  local ph = duels.KNOBS.PLY_HAND_POS
  local step_x = hk.spacing_x or 0

  local hand = st.ply and st.ply.hand or {}
  local count = #hand
  if count <= 0 then return nil end

  index = math.max(1, math.min(index or 1, count))

  local start_x = _hand_start_x(ph.x, count, step_x, hk)
  local y_tl = (ph.y or 0) + (st.ply_hand_slide_dy or 0)

  local lift = tonumber(hk.highlight_lift_y) or 0
  local y_tl_i = y_tl
  local highlight_i = nil
  if st.in_summon_menu then
    highlight_i = (st.selected_hand_index or st.cursor_index or 1)
  elseif (st.cursor_mode or "hand") == "hand" then
    highlight_i = (st.cursor_index or 1)
  end

  if highlight_i and index == highlight_i then
    y_tl_i = y_tl_i - lift
  end

  local x_tl = start_x + (index - 1) * step_x
  return x_tl, y_tl_i
end

function _get_opponent_hand_card_tl(st, index)
  local hk = duels.KNOBS.HAND
  local oh = duels.KNOBS.OPP_HAND_POS
  local step_x = hk.spacing_x or 0

  local hand = st.opp and st.opp.hand or {}
  local count = #hand
  if count <= 0 then return nil end

  index = math.max(1, math.min(index or 1, count))

  local start_x = _hand_start_x(oh.x, count, step_x, hk)
  local y_tl = (oh.y or 0) + (st.opp_hand_slide_dy or 0)

  local x_tl = start_x + (index - 1) * step_x
  return x_tl, y_tl
end


local function _draw_summon_menu(pid, st)
  if not st then return end
  local hand = st.ply and st.ply.hand or {}
  if #hand <= 0 then return end

  local idx = st.selected_hand_index or st.cursor_index or 1
  local x_tl, y_tl = _get_player_hand_card_tl(st, idx)
  if not x_tl then return end

  local mk = duels.KNOBS.SUMMON_MENU
  local mini = duels.KNOBS.MINICURSOR

  -- Base point (layout space) near bottom of selected card
  local base_x = x_tl + (mk.offset_x or 0)
  local base_y = y_tl + (mk.offset_y or 0)

  local gap = mk.gap_x or 18
  local summon_x = base_x - gap * 0.5
  local set_x    = base_x + gap * 0.5
  local icon_y   = base_y

  -- allocate once
  _alloc_sprite(pid, duels.SUMMONS_SPRITE_ID, duels.SUMMONS_TEX, duels.SUMMONS_ANIM, duels.SUMMONS_STATE_SUMMON)
  _alloc_sprite(pid, duels.MINICURSOR_SPRITE_ID, duels.MINICURSOR_TEX, duels.MINICURSOR_ANIM, duels.MINICURSOR_STATE)

  -- draw icons as two separate objects (same sprite resource, different anim_state)
  _draw_sprite_obj(pid, duels.SUMMONS_SPRITE_ID, duels.SUMMONS_SPRITE_ID .. "_summon",
    summon_x, icon_y, mk.sx, mk.sy, mk.z, duels.SUMMONS_STATE_SUMMON, nil)

  _draw_sprite_obj(pid, duels.SUMMONS_SPRITE_ID, duels.SUMMONS_SPRITE_ID .. "_set",
    set_x, icon_y, mk.sx, mk.sy, mk.z, duels.SUMMONS_STATE_SET, nil)

  -- minicursor over selected choice
  local choice = st.summon_choice or 1 -- 1=summon, 2=set
  local cx = (choice == 2) and set_x or summon_x
  local cy = icon_y

  cx = cx + (mini.offset_x or 0)
  cy = cy + (mini.offset_y or 0)

  _draw_sprite_obj(pid, duels.MINICURSOR_SPRITE_ID, duels.MINICURSOR_SPRITE_ID .. "_obj",
    cx, cy, mini.sx, mini.sy, mini.z, duels.MINICURSOR_STATE, nil)
end

function _erase_monsters(pid)
  -- Hard wipe: use for clear/reset only.
  _erase_obj(pid, duels.MZ1_OBJ_ID)
  _erase_obj(pid, duels.MZ2_OBJ_ID)

  -- also clear any transient attack objects
  _erase_obj(pid, duels.ATTACK_MZ1_OBJ_ID)
  _erase_obj(pid, duels.ATTACK_MZ2_OBJ_ID)
end


local function _clear_all(pid, st)
  -- Field background (safety: erase both legacy + current object ids)
  _erase_obj(pid, duels.FIELD_SPRITE_ID)
  _erase_and_dealloc(pid, duels.FIELD_SPRITE_ID, duels.FIELD_SPRITE_ID .. "_obj")

  -- wipe opponent + player hand objects
  local hk = duels.KNOBS.HAND
  local max_wipe = _clamp_int(hk.max_cards_to_clear or 10, 1, 50)
  for i = 1, max_wipe do
    _erase_obj(pid, duels.OPP_HAND_OBJ_PREFIX .. i)
    _erase_obj(pid, duels.PLY_HAND_OBJ_PREFIX .. i)
  end

  _erase_deck_stack(pid)
  if st then
    st.ply_hand_slide_dy = 0
    st.opp_hand_slide_dy = 0
    st.draw_anim = nil
  end

  -- erase big cursor
  _erase_and_dealloc(pid, duels.CURSOR_SPRITE_ID)

  -- erase summon menu UI
  _erase_summon_menu(pid)
  _dealloc_sprite(pid, duels.SUMMONS_SPRITE_ID)

  -- erase field action menu UI
  _erase_field_menu(pid)
  _dealloc_sprite(pid, duels.ATKPOS_SPRITE_ID)

  -- erase pause menu UI
  _erase_pause_menu(pid)
  _dealloc_sprite(pid, duels.TURNCON_SPRITE_ID)

  -- erase spells menu UI
  _erase_spells_menu(pid)
  _dealloc_sprite(pid, duels.SPELLSUI_SPRITE_ID)
  _dealloc_sprite(pid, duels.SPELLICONS_SPRITE_ID)

  _dealloc_sprite(pid, duels.MINICURSOR_SPRITE_ID)

  -- erase monsters
  _erase_monsters(pid)

  -- erase any active summon animation
  _erase_obj(pid, duels.SUMMON_ANIM_OBJ_ID)
  if st then st.summon_anim = nil end

  -- erase any active position animation
  _erase_obj(pid, duels.POS_ANIM_OBJ_ID)
  if st then st.pos_anim = nil end

  -- erase info panel (displayer text + icons)
  _clear_info_panel(pid)
  _clear_opp_info_panel(pid)
  _dealloc_sprite(pid, duels.ATKDEF_SPRITE_ID)

  -- dealloc opponent facedown sprite resource
  _dealloc_sprite(pid, duels.OPP_HAND_SPRITE_ID)

  -- erase + destroy any destroy-burst particles
  _clear_destroy_dust(pid, st)

  -- erase + dealloc win condition UI
  _erase_point_counters(pid)
  _dealloc_sprite(pid, duels.POINTCOUNTER_SPRITE_ID)

  -- erase + dealloc spell counter UI
  duels._erase_spell_counters(pid)
  _dealloc_sprite(pid, duels.SPELLCOUNTER_SPRITE_ID)

  -- dealloc any per-card sprites allocated this duel
  if st and st.allocated_card_sprites then
    for _, sid in ipairs(st.allocated_card_sprites) do
      _dealloc_sprite(pid, sid)
    end
  end

  if st then
    st.card_sprites_by_tex = nil
    st.allocated_card_sprites = nil
    st.ply_hand_obj_tex = nil
    st.field_obj_tex = nil -- (optional) clear any cached field bindings
  end
end

function _draw_monsters(pid, st)
  if not st or not st.field then return end

  st.field_obj_tex = st.field_obj_tex or {}

  -- IMPORTANT:
  -- Do NOT call _erase_monsters(pid) here.
  -- That wipes BOTH zones and causes a visible flicker when only one side changes.
  --
  -- We only erase a zone when it becomes empty, OR when its displayed texture changes
  -- (e.g. face-down -> face-up, or a different monster is summoned).

  local pos_side = (st.pos_anim and st.pos_anim.active) and st.pos_anim.target_side or nil

  -- ------------------------------------------------------------
  -- Opponent monster zone (MZ1)
  -- ------------------------------------------------------------
  if pos_side == "opp" then
    _erase_obj(pid, duels.MZ1_OBJ_ID)
  else
    local mz1 = st.field.opp_monster
    if mz1 and mz1.card then
      local marker = mz1.facedown and (st.facedown_tex or duels.FACE_DOWN_TEX) or ((mz1.card and mz1.card.tex) or "__missing_tex__")
      if st.field_obj_tex.mz1 ~= marker then
        _erase_obj(pid, duels.MZ1_OBJ_ID)
        st.field_obj_tex.mz1 = marker
      end

      local k = duels.KNOBS.MZ1 or {}
      local sx, sy = k.sx, k.sy
      local x, y = _apply_card_origin_if_needed(k.x, k.y, sx, sy)

      local atk_ro = tonumber(k.ro) or 0
      local def_ro = (atk_ro + 90) % 360

      if mz1.facedown then
      local fd_sid = _ensure_facedown_sprite(pid, st)
      _draw_sprite_obj(pid, fd_sid, duels.MZ1_OBJ_ID,
          x, y, sx, sy, k.z, duels.CARD_STATE, def_ro)
      else
        local sprite_id = _ensure_card_sprite(pid, st, mz1.card)
        local ro = ((mz1.pos or "atk") == "def") and def_ro or atk_ro
        _draw_sprite_obj(pid, sprite_id, duels.MZ1_OBJ_ID,
          x, y, sx, sy, k.z, duels.CARD_STATE, ro)
      end
    else
      st.field_obj_tex.mz1 = nil
      _erase_obj(pid, duels.MZ1_OBJ_ID)
    end
  end

  -- ------------------------------------------------------------
  -- Player monster zone (MZ2)
  -- ------------------------------------------------------------
  if pos_side == "ply" then
    _erase_obj(pid, duels.MZ2_OBJ_ID)
  else
    local mz2 = st.field.ply_monster
    if mz2 and mz2.card then
      local marker = mz2.facedown and (st.facedown_tex or duels.FACE_DOWN_TEX) or ((mz2.card and mz2.card.tex) or "__missing_tex__")
      if st.field_obj_tex.mz2 ~= marker then
        _erase_obj(pid, duels.MZ2_OBJ_ID)
        st.field_obj_tex.mz2 = marker
      end

      local k = duels.KNOBS.MZ2 or {}
      local sx, sy = k.sx, k.sy
      local x, y = _apply_card_origin_if_needed(k.x, k.y, sx, sy)

      if mz2.facedown then
        local fd_sid = _ensure_facedown_sprite(pid, st)
        _draw_sprite_obj(pid, fd_sid, duels.MZ2_OBJ_ID,
          x, y, sx, sy, k.z, duels.CARD_STATE, 90)
      else
        local sprite_id = _ensure_card_sprite(pid, st, mz2.card)
        _draw_sprite_obj(pid, sprite_id, duels.MZ2_OBJ_ID,
          x, y, sx, sy, k.z, duels.CARD_STATE, ((mz2.pos or "atk") == "def") and 90 or (k.ro or 0))
      end
    else
      st.field_obj_tex.mz2 = nil
      _erase_obj(pid, duels.MZ2_OBJ_ID)
    end
  end
end

local function _toggle_player_monster_position(pid, st)
  if not (st and st.field and st.field.ply_monster and st.field.ply_monster.card) then return end
  if st.pos_anim and st.pos_anim.active then return end

  -- Rule: only 1 position change per turn
  local ti = st.turn_index or 0
  if st.ply_pos_changed_turn_index == ti then
    _draw_monsters(pid, st)
    _draw_hands(pid, st)
    return
  end

  local mz = st.field.ply_monster
  -- Rule: cannot change battle position the same turn the monster was summoned/set.
  if (mz.summoned_turn_index or -1) == (st.turn_index or 0) then
    _draw_monsters(pid, st)
    _draw_hands(pid, st)
    return
  end

  st.ply_pos_changed_turn_index = (st.turn_index or 0)

  local pk = duels.KNOBS.POS_ANIM or {}
  if pk.enabled == false then
    -- fallback: immediate toggle (no animation)
    if mz.facedown then
      mz.facedown = false
      mz.pos = "atk"
    else
      mz.pos = ((mz.pos or "atk") == "atk") and "def" or "atk"
    end
    _draw_monsters(pid, st)
    _draw_hands(pid, st)
    return
  end

  local k = duels.KNOBS.MZ2 or {}
  local base_sx = tonumber(k.sx) or 1
  local base_sy = tonumber(k.sy) or 1
  local x, y = _apply_card_origin_if_needed(tonumber(k.x) or 0, tonumber(k.y) or 0, base_sx, base_sy)

  local kind, ro0, ro2, sprite_id, alt_sprite_id
  local target_facedown, target_pos

  if mz.facedown then
    -- facedown defense -> faceup attack (flip + rotate back)
    kind = "fd_to_atk"
    target_facedown = false
    target_pos = "atk"

    sprite_id = _ensure_facedown_sprite(pid, st)
    alt_sprite_id = _ensure_card_sprite(pid, st, mz.card)

    ro0 = 90
    ro2 = (tonumber(k.ro) or 0)
  else
    sprite_id = _ensure_card_sprite(pid, st, mz.card)
    alt_sprite_id = nil
    target_facedown = false

    if (mz.pos or "atk") == "atk" then
      kind = "atk_to_def"
      target_pos = "def"
      ro0 = (tonumber(k.ro) or 0)
      ro2 = 90
    else
      kind = "def_to_atk"
      target_pos = "atk"
      ro0 = 90
      ro2 = (tonumber(k.ro) or 0)
    end
  end

  -- Hide the static monster while animating
  _erase_obj(pid, duels.MZ2_OBJ_ID)
  _erase_obj(pid, duels.CURSOR_SPRITE_ID .. "_obj")

  local z = tonumber(pk.z) or ((tonumber(k.z) or -90) + 10)

  st.pos_anim = {
    active = true,
    target_side = "ply",
    started_at = duels._now(),
    duration = tonumber(pk.duration) or 0.18,

    kind = kind,
    card = mz.card,

    x = x, y = y,
    base_sx = base_sx,
    base_sy = base_sy,
    z = z,

    sprite_id = sprite_id,
    alt_sprite_id = alt_sprite_id,

    ro0 = ro0,
    ro2 = ro2,

    peak_mul = tonumber(pk.peak_scale_mul) or 1.0,
    flip_min = tonumber(pk.flip_min) or 0.06,
    swap_t = tonumber(pk.swap_t) or 0.5,

    target = { facedown = target_facedown, pos = target_pos },
  }

  -- Draw first frame immediately
  _draw_sprite_obj(pid, sprite_id, duels.POS_ANIM_OBJ_ID, x, y, base_sx, base_sy, z, duels.CARD_STATE, ro0)
end

-- Reveal a face-down defense monster by flipping it to face-up DEF (used when attacked)
local function _start_reveal_def_anim(pid, st, target_side)
  if not (st and st.field) then return end
  if st.pos_anim and st.pos_anim.active then return end

  target_side = target_side or "opp"
  local is_opp = (target_side == "opp")
  local mz = is_opp and st.field.opp_monster or st.field.ply_monster
  if not (mz and mz.card and mz.facedown) then return end

  local k  = duels.KNOBS[is_opp and "MZ1" or "MZ2"] or {}
  local pk = duels.KNOBS.POS_ANIM or {}

  local base_sx = tonumber(k.sx) or 1
  local base_sy = tonumber(k.sy) or base_sx
  local x, y = _apply_card_origin_if_needed(tonumber(k.x) or 0, tonumber(k.y) or 0, base_sx, base_sy)

  local ro_def
  if is_opp then
    local atk_ro = tonumber(k.ro) or 0
    ro_def = (atk_ro + 90) % 360
  else
    -- player facedown uses a constant 90° in _draw_monsters
    ro_def = 90
  end

  local fd_sid = _ensure_facedown_sprite(pid, st)
  local alt = _ensure_card_sprite(pid, st, mz.card)

  -- Hide the static monster while animating
  local obj_id = is_opp and duels.MZ1_OBJ_ID or duels.MZ2_OBJ_ID
  _erase_obj(pid, obj_id)
  _erase_obj(pid, duels.CURSOR_SPRITE_ID .. "_obj")

  -- Clear cached binding for this zone (so the post-anim redraw can safely rebind)
  if st.field_obj_cache then
    st.field_obj_cache[is_opp and "mz1" or "mz2"] = nil
  end

  local z = tonumber(pk.z) or ((tonumber(k.z) or -90) + 10)

  st.pos_anim = {
    active = true,
    target_side = target_side,
    started_at = duels._now(),
    duration = tonumber(pk.duration) or 0.18,

    kind = "fd_to_def",
    card = mz.card,

    x = x, y = y,
    base_sx = base_sx,
    base_sy = base_sy,
    z = z,

    ro0 = ro_def,
    ro2 = ro_def,

    sprite_id = fd_sid,
    alt_sprite_id = alt,

    peak_mul = tonumber(pk.peak_mul) or 1.08,
    swap_t   = tonumber(pk.swap_t) or 0.5,
    flip_min = tonumber(pk.flip_min) or 0.06,

    target = { facedown = false, pos = "def" },
  }

  _erase_obj(pid, duels.POS_ANIM_OBJ_ID)
  _draw_sprite_obj(pid, st.pos_anim.sprite_id, duels.POS_ANIM_OBJ_ID,
    x, y, base_sx, base_sy, z, duels.CARD_STATE, ro_def)
end


function _toggle_opponent_monster_position(pid, st)
  if not (st and st.field and st.field.opp_monster and st.field.opp_monster.card) then return end
  if st.pos_anim and st.pos_anim.active then return end

  -- Rule: only 1 position change per turn
  local ti = st.turn_index or 0
  if st.opp_pos_changed_turn_index == ti then
    _draw_monsters(pid, st)
    _draw_hands(pid, st)
    return
  end

  local mz = st.field.opp_monster
  -- Rule: cannot change battle position the same turn the monster was summoned/set.
  if (mz.summoned_turn_index or -1) == (st.turn_index or 0) then
    _draw_monsters(pid, st)
    _draw_hands(pid, st)
    return
  end

  st.opp_pos_changed_turn_index = (st.turn_index or 0)

  local pk = duels.KNOBS.POS_ANIM or {}
  if pk.enabled == false then
    if mz.facedown then
      mz.facedown = false
      mz.pos = "atk"
    else
      mz.pos = ((mz.pos or "atk") == "atk") and "def" or "atk"
    end
    _draw_monsters(pid, st)
    _draw_hands(pid, st)
    return
  end

  local k = duels.KNOBS.MZ1 or {}
  local base_sx = tonumber(k.sx) or 1
  local base_sy = tonumber(k.sy) or 1
  local x, y = _apply_card_origin_if_needed(tonumber(k.x) or 0, tonumber(k.y) or 0, base_sx, base_sy)

  local atk_ro = tonumber(k.ro) or 0
  local def_ro = (atk_ro + 90) % 360

  local kind, ro0, ro2, sprite_id, alt_sprite_id
  local target_facedown, target_pos

  if mz.facedown then
    -- facedown defense -> faceup attack (flip + rotate)
    kind = "fd_to_atk"
    target_facedown = false
    target_pos = "atk"

    sprite_id = _ensure_facedown_sprite(pid, st)
    alt_sprite_id = _ensure_card_sprite(pid, st, mz.card)

    ro0 = def_ro
    ro2 = atk_ro
  else
    sprite_id = _ensure_card_sprite(pid, st, mz.card)
    alt_sprite_id = nil
    target_facedown = false

    if (mz.pos or "atk") == "atk" then
      kind = "atk_to_def"
      target_pos = "def"
      ro0 = atk_ro
      ro2 = def_ro
    else
      kind = "def_to_atk"
      target_pos = "atk"
      ro0 = def_ro
      ro2 = atk_ro
    end
  end

  _erase_obj(pid, duels.MZ1_OBJ_ID)
  _erase_obj(pid, duels.CURSOR_SPRITE_ID .. "_obj")

  local z = tonumber(pk.z) or ((tonumber(k.z) or -90) + 10)

  st.pos_anim = {
    active = true,
    target_side = "opp",
    started_at = duels._now(),
    duration = tonumber(pk.duration) or 0.18,

    kind = kind,
    card = mz.card,

    x = x, y = y,
    base_sx = base_sx,
    base_sy = base_sy,
    z = z,

    sprite_id = sprite_id,
    alt_sprite_id = alt_sprite_id,

    ro0 = ro0,
    ro2 = ro2,

    peak_mul = tonumber(pk.peak_scale_mul) or 1.0,
    flip_min = tonumber(pk.flip_min) or 0.06,
    swap_t = tonumber(pk.swap_t) or 0.5,

    target = { facedown = target_facedown, pos = target_pos },
  }

  _draw_sprite_obj(pid, sprite_id, duels.POS_ANIM_OBJ_ID, x, y, base_sx, base_sy, z, duels.CARD_STATE, ro0)
end

local function _shuffle_in_place(t, rng)
  for i = #t, 2, -1 do
    local j = _rng_int(rng, 1, i)
    t[i], t[j] = t[j], t[i]
  end
end

local function _random_deck_counts_from_collection(pid, rng)
  local pmem = get_player_mem(pid)
  local urgdr, sr, rr, cc = {}, {}, {}, {}

  for item_id, qty in pairs(pmem.items or {}) do
    qty = math.floor(tonumber(qty) or 0)
    if qty > 0 then
      local info = ezmemory.get_item_info(item_id)
      local name = info and info.name or ""
      local tag  = extract_rarity_tag(name)
      if tag then
        tag = tostring(tag):upper()
        for _ = 1, qty do
          if tag == "duels.UR" or tag == "duels.GDR" or tag == "duels.GR" then
            urgdr[#urgdr+1] = tostring(item_id)
          elseif tag == "duels.SR" then
            sr[#sr+1] = tostring(item_id)
          elseif tag == "R" then
            rr[#rr+1] = tostring(item_id)
          else
            cc[#cc+1] = tostring(item_id)
          end
        end
      end
    end
  end

  local function take(src, want)
    if #src == 0 or want <= 0 then return {} end
    _shuffle_in_place(src, rng)
    local out = {}
    for i = 1, math.min(want, #src) do out[#out+1] = src[i] end
    return out
  end

  local picked = {}

  -- duels.UR/duels.GDR/duels.GR: at most 1
  if #urgdr > 0 then
    _shuffle_in_place(urgdr, rng)
    picked[#picked+1] = urgdr[1]
  end

  for _, id in ipairs(take(sr, 2)) do picked[#picked+1] = id end
  for _, id in ipairs(take(rr, 3)) do picked[#picked+1] = id end

  _shuffle_in_place(cc, rng)
  local i = 1
  while #picked < 10 and i <= #cc do
    picked[#picked+1] = cc[i]
    i = i + 1
  end

  if #picked < 10 then
    return nil, "Not enough eligible cards to build a 10-card deck."
  end

  -- convert picked ids -> counts
  local counts = {}
  for _, id in ipairs(picked) do
    counts[id] = (counts[id] or 0) + 1
  end
  return counts
end

local function _npc_deck_counts_from_dialogue(pid, deck_ids)
  if type(deck_ids) ~= "table" or #deck_ids ~= 10 then return nil end

  local area_id = Net.get_player_area(pid)
  local counts = {}
  local total = 0

  for _, v in ipairs(deck_ids) do
    if total >= 10 then break end
    local raw = tostring(v)

    -- 1) If it's already a valid item_id, keep it
    if ezmemory.get_item_info(raw) then
      counts[raw] = (counts[raw] or 0) + 1
      total = total + 1
    else
      -- 2) Otherwise treat as object id (optionally "area,obj")
      local a, obj_id = split_area_id(raw)
      a = a or area_id
      local info = helpers.read_item_information(a, obj_id)

      -- try common fields for the actual inventory item id
      local iid =
        (info and (info.item_id or info.id)) or
        (info and info.custom and (info.custom.item_id or info.custom.id)) or
        nil

      if iid and ezmemory.get_item_info(iid) then
        iid = tostring(iid)
        counts[iid] = (counts[iid] or 0) + 1
        total = total + 1
      else
        return nil -- fail -> let caller fallback to random
      end
    end
  end

  return (total == 10) and counts or nil
end

-- ---------------------------------------------------------------------------
-- Game init + draw actions
-- ---------------------------------------------------------------------------
local function _init_game_state(pid, cfg)
  cfg = cfg or {}

  local DECK_N = math.floor(tonumber(cfg.deck_size) or 10)
  if DECK_N <= 0 then DECK_N = 10 end

  -- Shared RNG for deckbuilding + draws (piles are separate so draws are still independent)
  local rng = { seed = _rng_seed_from(pid) }

  local function _try_get_item_info(iid)
    if not (ezmemory and ezmemory.get_item_info) then return nil end
    local ok, info = pcall(ezmemory.get_item_info, tostring(iid))
    if ok then return info end
    return nil
  end

  local function _clone_entry(t)
    local o = {}
    for k, v in pairs(t) do o[k] = v end
    return o
  end

  local function _build_deck_from_id_list_for_area(area_id, ids)
    if type(ids) ~= "table" or #ids ~= DECK_N then return nil end
    local list = {}
    area_id = tostring(area_id or "default")

    for i = 1, #ids do
      local iid = tostring(ids[i])
      local info = _try_get_item_info(iid)
      local raw_name = info and info.name and tostring(info.name) or ""
      if raw_name == "" then return nil end

      local tex, tag, base = _card_texture_from_raw_name(raw_name)
      if has_asset(tex) == false then
        print(("[Duels] Missing card texture: %s (from %s)"):format(tex, raw_name))
      end

      list[#list + 1] = {
        item_id   = area_id .. "," .. iid,
        raw_name  = raw_name,
        rarity    = tostring(tag or "C"):upper(),
        base_name = base,
        tex       = tex,
        area      = area_id,
        iid       = iid,
      }
    end

    return list
  end

  -- Random deck from player's collection with caps:
  -- UR/GDR/GR ≤ 1 total, SR ≤ 2, R ≤ 3, C any
  local function _build_random_deck_from_collection()
    local pmem = get_player_mem(pid)
    local items = (type(pmem.items) == "table" and pmem.items) or {}

    local urgdr, sr, rr, cc = {}, {}, {}, {}

    for raw_item_id, qty in pairs(items) do
      qty = math.floor(tonumber(qty) or 0)
      if qty > 0 then
        local area, iid = split_area_id(raw_item_id)
        local info = _try_get_item_info(iid)
        local name = info and info.name and tostring(info.name) or ""

        -- Only treat tagged things as cards (prevents random non-card items from entering deck)
        local tag0 = extract_rarity_tag(name)
        if tag0 then
          local tex, tag, base = _card_texture_from_raw_name(name)
          local rar = tostring(tag or "C"):upper()

          local base_entry = {
            raw_name  = name,
            rarity    = rar,
            base_name = base,
            tex       = tex,
            area      = area,
            iid       = iid,
          }

          local bucket = cc
          if (rar == "UR") or (rar == "GDR") or (rar == "GR") then
            bucket = urgdr
          elseif rar == "SR" then
            bucket = sr
          elseif rar == "R" then
            bucket = rr
          else
            bucket = cc
          end

          for _ = 1, qty do
            local e = _clone_entry(base_entry)
            e.item_id = tostring(raw_item_id)
            bucket[#bucket + 1] = e
          end
        end
      end
    end

    local urgdr_limit, sr_limit, rr_limit = 1, 2, 3
    local eligible_total =
      math.min(#urgdr, urgdr_limit) +
      math.min(#sr,   sr_limit) +
      math.min(#rr,   rr_limit) +
      #cc

    if eligible_total < DECK_N then
      return nil, ("Not enough eligible cards to build a %d-card deck under rarity totals.\n(Need: UR/GDR/GR ≤ 1, SR ≤ 2, R ≤ 3, C = any)")
        :format(DECK_N)
    end

    local deck = {}

    local function take(bucket, n)
      for _ = 1, n do
        if #bucket == 0 then break end
        local idx = _rng_int(rng, 1, #bucket)
        deck[#deck + 1] = table.remove(bucket, idx)
      end
    end

    take(urgdr, math.min(#urgdr, urgdr_limit))
    take(sr,    math.min(#sr,   sr_limit))
    take(rr,    math.min(#rr,   rr_limit))
    while #deck < DECK_N do
      take(cc, 1)
    end

    return deck
  end

  -- 1) Player deck: saved deck if exactly DECK_N, otherwise random (unless forced)
  local deck_list do
    if cfg.force_random_player_deck then
      deck_list = nil
    else
      local deck_counts = load_deck_counts(pid)
      deck_list = _build_deck_list_from_counts(pid, deck_counts)
      if #deck_list ~= DECK_N then deck_list = nil end
    end

    if not deck_list then
      local err
      deck_list, err = _build_random_deck_from_collection()
      if not deck_list then
        return nil, err or "Could not build your deck."
      end
    end
  end

  -- 2) Opponent deck: cfg list (10 ids) else random
  local opp_deck_list do
    local area_id = (Net and Net.get_player_area and Net.get_player_area(pid)) or "default"
    opp_deck_list = _build_deck_from_id_list_for_area(area_id, cfg.npc_deck_ids)

    if not opp_deck_list then
      local err2
      opp_deck_list, err2 = _build_random_deck_from_collection()
      if not opp_deck_list then
        return nil, err2 or "Could not build NPC deck."
      end
    end
  end

  local st = {
    cfg = cfg,

    ply = {
      deck = deck_list,
      pile = _make_pile(#deck_list),
      hand = {},
      rng  = rng,
    },

    opp = {
      deck = opp_deck_list,
      pile = _make_pile(#opp_deck_list),
      hand = {},
      rng  = rng,
    },
  }

  st.field = {
    ply_monster = nil,
    opp_monster = nil,
  }

  st.selected_hand_index = nil
  st.in_summon_menu = false
  st.summon_choice = 1

  st.in_field_menu = false
  st.field_choice = 1

  st.cursor_index = 1
  st.cursor_mode = st.cursor_mode or "hand"
  st._btn = st._btn or {}

  -- Spells / spell counters (module optional)
  st.ply_spell_counters = 0
  st.opp_spell_counters = 0
  st.ply_spell_used_turn_index = -1
  st.opp_spell_used_turn_index = -1
  if duels._spells and duels._spells.init_state then
    pcall(duels._spells.init_state, st)
  end

  -- Turn flow
  st.turn = "ply"
  st.turn_index = 1
  st.ply_turn = 1
  st.ply_attacked_turn_index = -1
  st.opp_attacked_turn_index = -1
  st.ply_pos_changed_turn_index = -1
  st.opp_pos_changed_turn_index = -1
  st.opp_turn = 0
  st.ply_summoned_this_turn = false
  st.opp_summoned_this_turn = false
  st.pending_opp_end_turn_at = nil
  st.pending_opp_pos_on_next_opp_turn = nil

  -- Initial draws
  local start_p = _clamp_int(duels.KNOBS.STARTING_HAND.player or 2, 0, 10)
  local start_o = _clamp_int(duels.KNOBS.STARTING_HAND.opponent or 2, 0, 10)
  local max_p   = _clamp_int(duels.KNOBS.HAND_MAX.player or 4, 1, 10)
  local max_o   = _clamp_int(duels.KNOBS.HAND_MAX.opponent or 4, 1, 10)

  for _ = 1, start_p do
    if #st.ply.hand >= max_p then break end
    local c = _draw_random_from_deck(st.ply)
    if not c then break end
    st.ply.hand[#st.ply.hand + 1] = c
  end

  for _ = 1, start_o do
    if #st.opp.hand >= max_o then break end
    local c = _draw_random_from_deck(st.opp)
    if not c then break end
    st.opp.hand[#st.opp.hand + 1] = c
  end

  -- Win condition state
  st.ply_points = 0
  st.opp_points = 0
  st.duel_over = false
  st.duel_outcome = nil
  st.pending_close_at = nil

  return st
end

-- ---------------------------------------------------------------------------
-- Open / Close
-- ---------------------------------------------------------------------------
local function _close(pid)
  local st = st_by_pid[pid]
  if not st then return end

  -- Notify once on close (covers normal finish + disconnect during finish window)
  if not st._finish_notified then
    st._finish_notified = true

    local outcome = st.duel_outcome -- "ply" | "opp" | "tie" | nil
    local winner
    if outcome == "ply" then winner = 1
    elseif outcome == "opp" then winner = 2
    else winner = nil end

    local npc_name = (st.cfg and st.cfg.npc_name) or nil

    -- custom.lua compatible callback payload:
    local cb = st.cfg and st.cfg.on_finish
    if cb then
      local player_won = (winner == 1)
      pcall(cb, { player_won = player_won, winner = winner, npc_name = npc_name })
    end

    -- JobBBS win tracking (only increments if a duel job is active and winner==1)
    local JobBBS = rawget(_G, "JobBBS")
    if st.duel_over and JobBBS and JobBBS.on_npc_duel_result then
      pcall(JobBBS.on_npc_duel_result, pid, { winner = winner, npc_name = npc_name, kos = 3 })
    end
  end

  _clear_all(pid, st)
  st_by_pid[pid] = nil

  if Net.unlock_player_input then
    pcall(Net.unlock_player_input, pid)
  end
end


local function _open(pid, cfg)
  if st_by_pid[pid] then return end

  if Net.lock_player_input then
    pcall(Net.lock_player_input, pid)
  end

  local st, init_err = _init_game_state(pid, cfg)
  if not st then
    -- optional: notify + release the waiting NPC coroutine
    if cfg.on_finish then
      pcall(cfg.on_finish, { player_won = false, reason = "init_failed", error = init_err })
    end
    if Net.unlock_player_input then pcall(Net.unlock_player_input, pid) end
    return
  end
  st.cfg = cfg

  st.facedown_tex = _resolve_facedown_tex(pid)
  st.facedown_sprite_id = nil

  -- Clear any stale objects (hot reload / crash)
  _clear_all(pid, st)

  -- Draw UI
  _draw_field(pid, st)
  _draw_point_counters(pid, st)
  duels._draw_spell_counters(pid, st)

  -- Preload particle sprite + stardust system (optional)
  _ensure_destroy_dust(pid, st)

  -- Monster zones cleared for now (no MZ sprites drawn)
  -- (Later you can add them back when you implement placing cards.)

  -- Draw initial hands from deck
  _draw_hands(pid, st)
  _draw_monsters(pid, st)

  st_by_pid[pid] = st
end

function duels.start_card_battle(pid, cfg)
  if not pid then return end
  _open(pid, cfg)
end

-- ---------------------------------------------------------------------------
-- Button logic
-- ---------------------------------------------------------------------------
Net:on("virtual_input", function(event)
  if not event then return end
  local pid = event.player_id
  local st = pid and st_by_pid[pid]
  if not st then return end

  -- If duel is over, ignore all gameplay inputs (auto-close handled elsewhere)
  if st.duel_over then return end

  st._btn = st._btn or {}

  local evs = event.events
  if not evs then return end

  if st.draw_anim and st.draw_anim.active then
    return
  end

  for _, button in next, evs do
    local name = button.name
    local state = button.state
    local pressed = (state == 0 or state == 1)

    -- ------------------------------------------------------------
    -- Pause menu toggle (End Turn / Concede)
    -- ------------------------------------------------------------
    if name == "Pause" then
      if pressed then
        if not st._btn.pause_down then
          st._btn.pause_down = true

          -- If spells menu is open, treat Pause as "Cancel" for it.
          if st.in_spells_menu then
            st.in_spells_menu = false
            _erase_spells_menu(pid)
            _draw_hands(pid, st)
            goto continue_buttons
          end

          if st.in_pause_menu then
            -- close pause menu
            st.in_pause_menu = false
            _erase_pause_menu(pid)
            _draw_hands(pid, st)
          else
            -- opening pause menu closes other mini menus
            if st.in_spells_menu then
              st.in_spells_menu = false
              _erase_spells_menu(pid)
              st.spells_choice = 1
              st.spells_scroll = 1
            end
            if st.in_summon_menu then
              st.in_summon_menu = false
              _erase_summon_menu(pid)
              st.selected_hand_index = nil
              st.summon_choice = 1
            end
            if st.in_field_menu then
              st.in_field_menu = false
              _erase_field_menu(pid)
              st.field_choice = 1
            end

            st.in_pause_menu = true
            st.pause_choice = 1
            st.pause_menu_opened_at = duels._now()
            st.pause_menu_last_slide_enabled = nil

            _erase_obj(pid, duels.CURSOR_SPRITE_ID .. "_obj")
            _draw_hands(pid, st)
          end
        end
      else
        st._btn.pause_down = false
      end
      goto continue_buttons
    end

    -- ------------------------------------------------------------
-- When spells menu is open, ONLY allow Up/Down, Confirm, Cancel
-- ------------------------------------------------------------
if st.in_spells_menu then
  if name == "Move Up" then
    if pressed then
      if not st._btn.spells_up_down then
        st._btn.spells_up_down = true
        local defs = (duels._spells and duels._spells.get_spell_defs and duels._spells.get_spell_defs()) or {}
        local n = #defs
        if n > 0 then
          local c = tonumber(st.spells_choice) or 1
          c = c - 1
          if c < 1 then c = n end
          st.spells_choice = c
          local rows = _clamp_int((duels.KNOBS.SPELLS_MENU or {}).visible_rows or 4, 1, 12)
          local top = tonumber(st.spells_scroll) or 1
          if c < top then top = c end
          if c > (top + rows - 1) then top = c - rows + 1 end
          local max_top = math.max(1, n - rows + 1)
          if top < 1 then top = 1 end
          if top > max_top then top = max_top end
          st.spells_scroll = top
          _draw_hands(pid, st)
        end
      end
    else
      st._btn.spells_up_down = false
    end
    goto continue_buttons
  end

  if name == "Move Down" then
    if pressed then
      if not st._btn.spells_down_down then
        st._btn.spells_down_down = true
        local defs = (duels._spells and duels._spells.get_spell_defs and duels._spells.get_spell_defs()) or {}
        local n = #defs
        if n > 0 then
          local c = tonumber(st.spells_choice) or 1
          c = c + 1
          if c > n then c = 1 end
          st.spells_choice = c
          local rows = _clamp_int((duels.KNOBS.SPELLS_MENU or {}).visible_rows or 4, 1, 12)
          local top = tonumber(st.spells_scroll) or 1
          if c < top then top = c end
          if c > (top + rows - 1) then top = c - rows + 1 end
          local max_top = math.max(1, n - rows + 1)
          if top < 1 then top = 1 end
          if top > max_top then top = max_top end
          st.spells_scroll = top
          _draw_hands(pid, st)
        end
      end
    else
      st._btn.spells_down_down = false
    end
    goto continue_buttons
  end

  if name == "Confirm" and pressed then
    local defs = duels._spells.get_spell_defs()
    local n = duels._spells.get_spell_count()
    if n <= 0 then
      goto continue_buttons
    end

    local c = tonumber(st.spells_choice) or 1
    if c < 1 then c = 1 end
    if c > n then c = n end
    local def = defs[c]
    st.last_spell_selected = def and (def.id or def.name) or nil

    -- Try to activate first; only close the spells menu if activation succeeds.
    local ok_spell, reason = true, "ok"
    if duels._spells and duels._spells.activate and def and def.id then
      local sc_knob = duels.KNOBS.SPELL_COUNTERS or duels.KNOBS.SPELL_COUNTER or {}
      local api = {
        pid = pid,
        start_reveal_def_anim = _start_reveal_def_anim,
        toggle_opponent_monster_position = _toggle_opponent_monster_position,
        toggle_player_monster_position = _toggle_player_monster_position,
        destroy_monster = _destroy_monster,
        draw_monsters = _draw_monsters,
        draw_spell_counters = duels._draw_spell_counters,
        draw_point_counters = _draw_point_counters,
        end_duel_by_points = _end_duel_by_points,
        max_spell_counters = _clamp_int(sc_knob.max or 6, 1, 24),
        max_points = 3,
      }

      local ok_call
      ok_call, ok_spell, reason = pcall(duels._spells.activate, st, "ply", def.id, api)
      if not ok_call then
        ok_spell = false
        reason = "spell_runtime_error"
      end
    end

    if ok_spell then
      st.in_spells_menu = false
      _erase_spells_menu(pid)
      _draw_hands(pid, st)
    else
      -- Keep spells menu open so you can adjust / try another target.
      st.last_spell_error = reason
      _draw_hands(pid, st)
    end

    goto continue_buttons
  end

  if name == "Cancel" and pressed then
    st.in_spells_menu = false
    _erase_spells_menu(pid)
    _draw_hands(pid, st)
    goto continue_buttons
  end

  goto continue_buttons
end

-- ------------------------------------------------------------
    -- When pause menu is open, ONLY allow Up/Down, Confirm, Cancel
    -- ------------------------------------------------------------
    if st.in_pause_menu then
      if name == "Move Up" then
        if pressed then
          if not st._btn.up_down then
            st._btn.up_down = true
            local c = tonumber(st.pause_choice) or 1
            c = c - 1
            if c < 1 then c = 3 end
            st.pause_choice = c
            _draw_hands(pid, st)
          end
        else
          st._btn.up_down = false
        end
        goto continue_buttons
      end

      if name == "Move Down" then
        if pressed then
          if not st._btn.down_down then
            st._btn.down_down = true
            local c = tonumber(st.pause_choice) or 1
            c = c + 1
            if c > 3 then c = 1 end
            st.pause_choice = c
            _draw_hands(pid, st)
          end
        else
          st._btn.down_down = false
        end
        goto continue_buttons
      end

      if name == "Confirm" and pressed then
        local choice = st.pause_choice or 1
        if choice == 3 then
          -- Concede: close the duel
          _close(pid)
          return
elseif choice == 2 then
  -- Spells menu (UI only for now)
  st.in_pause_menu = false
  _erase_pause_menu(pid)

  st.in_spells_menu = true
  st.spells_choice = 1
  st.spells_scroll = 1

  _erase_obj(pid, duels.CURSOR_SPRITE_ID .. "_obj")
  _draw_hands(pid, st)
  goto continue_buttons
        else
          -- End Turn
          if (not (st.field and st.field.ply_monster)) and (not st.ply_summoned_this_turn) then
            goto continue_buttons
          end

          st.in_pause_menu = false
          _erase_pause_menu(pid)

          _end_turn(pid, st)

          _draw_hands(pid, st)
          _draw_monsters(pid, st)
          goto continue_buttons
        end
      end

      if name == "Cancel" and pressed then
        st.in_pause_menu = false
        _erase_pause_menu(pid)
        _draw_hands(pid, st)
        goto continue_buttons
      end

      goto continue_buttons
    end

    -- ------------------------------------------------------------
    -- If an animation is playing, ignore inputs (duel is modal)
    -- ------------------------------------------------------------
    if (st.summon_anim and st.summon_anim.active)
      or (st.pos_anim and st.pos_anim.active)
      or (st.attack_anim and st.attack_anim.active)
      or st.pending_reveal_battle
    then
      return
    end

    -- If it's opponent's turn, ignore gameplay inputs (Pause still works above)
    if (st.turn == "opp") and (not st.in_pause_menu) then
      return
    end

    -- ------------------------------------------------------------
    -- Confirm
    -- ------------------------------------------------------------
    if name == "Confirm" and pressed then
      local mode = st.cursor_mode or "hand"

      -- If field action menu is open, confirm selection
      if st.in_field_menu then
        local choice = st.field_choice or 1 -- 1=atk, 2=pos

        st.in_field_menu = false
        _erase_field_menu(pid)

        if choice == 1 then
          -- Attack
          local mon = st.field and st.field.ply_monster
          local def = st.field and st.field.opp_monster
          if _can_attack(mon) and def and def.card then
            _start_attack_anim(pid, st, "ply")
            return
          end

          _draw_hands(pid, st)
          _draw_monsters(pid, st)
          return
        else
          _toggle_player_monster_position(pid, st)
          return
        end
      end

      -- Open field action menu when cursor is on player's field monster
      if (not st.in_summon_menu) and mode == "ply_field" then
        if st.field and st.field.ply_monster and st.field.ply_monster.card then
          st.in_field_menu = true
          st.field_choice = 1

          _erase_obj(pid, duels.CURSOR_SPRITE_ID .. "_obj")
          _draw_hands(pid, st)
          _draw_field_menu(pid, st)
        end
        return
      end

      -- Hand logic (summon/set menu)
      local hand = st.ply and st.ply.hand or {}
      if #hand <= 0 then return end
      if mode ~= "hand" and not st.in_summon_menu then return end

      if not st.in_summon_menu then
        if st.field and st.field.ply_monster then
          return
        end

        st.selected_hand_index = st.cursor_index or 1
        st.in_summon_menu = true
        st.summon_choice = 1

        _erase_obj(pid, duels.CURSOR_SPRITE_ID .. "_obj")
        _draw_hands(pid, st)
        _draw_summon_menu(pid, st)
        return
      else
        if st.field and st.field.ply_monster then
          return
        end

        local idx = st.selected_hand_index or st.cursor_index or 1
        idx = math.max(1, math.min(idx, #(st.ply.hand or {})))
        local card = st.ply.hand[idx]
        if not card then return end

        local hk = duels.KNOBS.HAND
        local start_x_tl, start_y_tl = _get_player_hand_card_tl(st, idx)
        local start_x, start_y = _apply_card_origin_if_needed(start_x_tl or 0, start_y_tl or 0, hk.scale or 1, hk.scale or 1)

        table.remove(st.ply.hand, idx)
        local new_count = #(st.ply.hand or {})
        if new_count <= 0 then
          st.cursor_index = 1
        else
          st.cursor_index = math.min(idx, new_count)
        end

        st.in_summon_menu = false
        _erase_summon_menu(pid)
        st.selected_hand_index = nil

        st.field = st.field or {}

        local k = duels.KNOBS.MZ2
        local end_x, end_y = _apply_card_origin_if_needed(k.x, k.y, k.sx, k.sy)
        local start_s = hk.scale or 1
        local end_s   = k.sx or 1

        _draw_hands(pid, st)
        _erase_obj(pid, duels.MZ2_OBJ_ID)
        _erase_obj(pid, duels.ATTACK_MZ2_OBJ_ID)

        st.ply_summoned_this_turn = true

        if st.summon_choice == 2 then
          _start_summon_anim(pid, st, card, start_x, start_y, start_s, end_x, end_y, end_s, "set")
        else
          _start_summon_anim(pid, st, card, start_x, start_y, start_s, end_x, end_y, end_s)
        end

        return
      end
    end

    -- ------------------------------------------------------------
    -- Move Right
    -- ------------------------------------------------------------
    if name == "Move Right" then
      if pressed then
        if not st._btn.right_down then
          st._btn.right_down = true

          if st.in_summon_menu then
            st.summon_choice = 2
            _draw_summon_menu(pid, st)
          elseif st.in_field_menu then
            st.field_choice = 2
            _draw_field_menu(pid, st)
          else
            if (st.cursor_mode or "hand") == "hand" then
              local count = #(st.ply.hand or {})
              if count > 0 then
                st.cursor_index = math.min((st.cursor_index or 1) + 1, count)
                _draw_hands(pid, st)
              end
            end
          end
        end
      else
        st._btn.right_down = false
      end
    end

    -- ------------------------------------------------------------
    -- Move Left
    -- ------------------------------------------------------------
    if name == "Move Left" then
      if pressed then
        if not st._btn.left_down then
          st._btn.left_down = true

          if st.in_summon_menu then
            st.summon_choice = 1
            _draw_summon_menu(pid, st)
          elseif st.in_field_menu then
            st.field_choice = 1
            _draw_field_menu(pid, st)
          else
            if (st.cursor_mode or "hand") == "hand" then
              local count = #(st.ply.hand or {})
              if count > 0 then
                st.cursor_index = math.max((st.cursor_index or 1) - 1, 1)
                _draw_hands(pid, st)
              end
            end
          end
        end
      else
        st._btn.left_down = false
      end
    end

    -- ------------------------------------------------------------
    -- Move Up (hand -> player field -> opponent field)
    -- ------------------------------------------------------------
    if name == "Move Up" then
      if pressed then
        if not st._btn.up_down then
          st._btn.up_down = true
          if not (st.in_summon_menu or st.in_field_menu) then
            local mode = st.cursor_mode or "hand"
            if mode == "hand" then
              st.cursor_mode = "ply_field"
            elseif mode == "ply_field" then
              st.cursor_mode = "opp_field"
            end
            _draw_hands(pid, st)
          end
        end
      else
        st._btn.up_down = false
      end
    end

    -- ------------------------------------------------------------
    -- Move Down (opponent field -> player field -> hand)
    -- ------------------------------------------------------------
    if name == "Move Down" then
      if pressed then
        if not st._btn.down_down then
          st._btn.down_down = true
          if not (st.in_summon_menu or st.in_field_menu) then
            local mode = st.cursor_mode or "hand"
            if mode == "opp_field" then
              st.cursor_mode = "ply_field"
            elseif mode == "ply_field" then
              st.cursor_mode = "hand"
            end
            _draw_hands(pid, st)
          end
        end
      else
        st._btn.down_down = false
      end
    end

    -- ------------------------------------------------------------
    -- Cancel (close mini menus)
    -- ------------------------------------------------------------
    if name == "Cancel" and pressed then
      if st.in_summon_menu then
        st.in_summon_menu = false
        _erase_summon_menu(pid)
        _draw_hands(pid, st)
        st.selected_hand_index = nil
        st.summon_choice = 1
        return
      end

      if st.in_field_menu then
        st.in_field_menu = false
        _erase_field_menu(pid)
        _draw_hands(pid, st)
        st.field_choice = 1
        return
      end

      return
    end

    ::continue_buttons::
  end
end)

-- ---------------------------------------------------------------------------
-- Safety cleanup
-- ---------------------------------------------------------------------------
Net:on("player_disconnect", function(e) if e and e.player_id then _close(e.player_id) end end)
Net:on("player_transfer",   function(e) if e and e.player_id then _close(e.player_id) end end)
Net:on("area_transfer",     function(e) if e and e.player_id then _close(e.player_id) end end)

-- ---------------------------------------------------------------------------
-- Expose Duel open-state so other UI systems (e.g. LMenu) can respect this modal UI.
-- ---------------------------------------------------------------------------
do
  local Duels = rawget(_G, "Duels")
  if type(Duels) ~= "table" then Duels = {} end

  function Duels.is_open_for(pid)
    return st_by_pid[pid] ~= nil
  end

  duels.is_open_for = Duels.is_open_for

  rawset(_G, "Duels", Duels)
  rawset(_G, "duel_ui_is_open", Duels.is_open_for)
end


-- ---------------------------------------------------------------------------
-- Tick: drive summon animation updates
-- ---------------------------------------------------------------------------
if not rawget(_G, "__duels_tick_v1_registered") then
  rawset(_G, "__duels_tick_v1_registered", true)

Net:on("tick", function()
  -- advance wall-time (clamp to avoid huge jumps if the server hitches)
  local dt = (ev and ev.delta_time) or (1/60)
  if dt < 0 then dt = 0 end
  if dt > 0.25 then dt = 0.25 end
  duels._time = duels._time + dt

  local now = duels._now()

  for pid, st in pairs(st_by_pid) do
    if st then
      _draw_destroy_dust(pid, st)

      -- ------------------------------------------------------------
      -- 0) If duel has ended, close after the configured hold
      -- ------------------------------------------------------------
      if st.duel_over then
        local when = st.pending_close_at
        if when and now >= when then
          _close(pid)
        end
        -- While waiting to close, do not drive AI/animations.
        goto continue_pid
      end

      -- ------------------------------------------------------------
      -- 1) Drive draw/pickup animation (blocks AI/actions while active)
      -- ------------------------------------------------------------
      if st.draw_anim and st.draw_anim.active then
        local done = _update_draw_anim(pid, st, now)
        if not done then
          goto continue_pid
        end
      end

      -- ------------------------------------------------------------
      -- 1.5) Let the opponent AI think/act during opponent turns
      -- ------------------------------------------------------------
      if (st.turn == "opp") and (not st.in_pause_menu) and (not st.pending_reveal_battle) then
        _ai_opp_take_turn(pid, st, now)
      end

      -- ------------------------------------------------------------
      -- 2) Drive summon / set fly-in animation
      -- ------------------------------------------------------------
      if st.summon_anim and st.summon_anim.active then
        local finished = _update_summon_anim(pid, st)
        if finished then
          -- Capture anim data BEFORE ending it (because _end_summon_anim() nils st.summon_anim)
          local anim = st.summon_anim
          local card = anim and anim.card or nil
          local kind = anim and anim.kind or "summon"

          _end_summon_anim(pid, st)
          -- finalize: place monster in the correct zone
          st.field = st.field or {}

          local side = (anim and anim.target_side) or "ply"
          local facedown = (kind == "set")
          local pos = (kind == "set") and "def" or ((anim and anim.target_pos) or "atk")

          if side == "opp" then
            do
              local _, base_def = _get_card_atk_def(card)
              st.field.opp_monster = {
                card = card,
                facedown = facedown,
                pos = pos,
                def_current = (tonumber(base_def) or 0),
                summoned_turn_index = (st.turn_index or 0)
              }
            end
          else
            do
              local _, base_def = _get_card_atk_def(card)
              st.field.ply_monster = {
                card = card,
                facedown = facedown,
                pos = pos,
                def_current = (tonumber(base_def) or 0),
                summoned_turn_index = (st.turn_index or 0)
              }
            end
          end

          _draw_monsters(pid, st)

          -- If opponent just finished a summon/set during opponent turn, follow the AI plan.
          if (side == "opp") and (st.turn == "opp") then
            local after = st.ai_after_summon
            st.ai_after_summon = nil

            -- NEW: cast the planned spell tied to this summon (before deciding to attack)
            if after and after.spell_id then
              _ai_opp_try_cast_spell(pid, st, after.spell_id)
              if st.duel_over then goto continue_pid end
            end

            if after and after.attack then
              local ok = _ai_opp_queue_attack(pid, st, now)
              if (not ok) and (after.end_turn ~= false) then
                _ai_opp_queue_end_turn(pid, st, now)
              end
            elseif after and (after.end_turn ~= false) then
              _ai_opp_queue_end_turn(pid, st, now)
            else
              -- Fallback: if AI is enabled and we didn't schedule anything, end the turn.
              if _ai_enabled() then
                if not (st.pending_opp_attack and st.pending_opp_attack_at) then
                  _ai_opp_queue_end_turn(pid, st, now)
                end
              end
            end
          end

          _draw_hands(pid, st) -- refreshes info panel + cursor too
          _draw_point_counters(pid, st)

          if st.duel_over then goto continue_pid end
        end
      end

      -- ------------------------------------------------------------
      -- 3) Drive position-change animation (ATK<->DEF / reveal)
      -- ------------------------------------------------------------
      if st.pos_anim and st.pos_anim.active then
        local finished = _update_pos_anim(pid, st)
        if finished then
          local anim = st.pos_anim
          local target = anim and anim.target or nil

          _end_pos_anim(pid, st)

          if target and st.field then
            local side = (anim and anim.target_side) or "ply"
            local slot = (side == "opp") and st.field.opp_monster or st.field.ply_monster
            if slot then
              slot.facedown = target.facedown
              slot.pos = target.pos

              -- If this was a reveal flip (face-down -> face-up DEF) and we have a deferred battle pending,
              -- start the "reveal hold" timer NOW (after the flip is complete).
              if st.pending_reveal_battle and st.pending_reveal_battle.is_reveal and (not st.reveal_hold_until) then
                local pb = st.pending_reveal_battle
                if (anim and anim.kind == "fd_to_def") and (not pb.defender_side or pb.defender_side == (anim and anim.target_side)) then
                  st.reveal_hold_until = now + (st.reveal_hold_seconds or 1.0)
                  st.reveal_hold_seconds = nil
                end
              end
            end
          end

          _draw_monsters(pid, st)
          _draw_hands(pid, st)
          _draw_point_counters(pid, st)

          -- If this position change was AI-driven (opponent), continue with queued action.
          if (anim and anim.target_side == "opp") and (st.turn == "opp") then
            local after = st.ai_after_pos
            st.ai_after_pos = nil
            if after and after.attack then
              local ok = _ai_opp_queue_attack(pid, st, now)
              if (not ok) and (after.end_turn ~= false) then
                _ai_opp_queue_end_turn(pid, st, now)
              end
            elseif after and (after.end_turn ~= false) then
              _ai_opp_queue_end_turn(pid, st, now)
            end
          end

          if st.duel_over then goto continue_pid end
        end
      end

      -- ------------------------------------------------------------
      -- 4) Drive attack animation (card lunge)
      -- ------------------------------------------------------------
      if st.attack_anim and st.attack_anim.active then
        local finished = _update_attack_anim(pid, st)
        if finished then
          -- Capture BEFORE ending (ending clears st.attack_anim).
          local a = st.attack_anim
          local attacker_side = (a and a.attacker_side) or "ply"
          local defender_side = (a and a.defender_side) or ((attacker_side == "opp") and "ply" or "opp")
          local def_was_fd = (a and a.def_was_facedown) or false

          _end_attack_anim(pid, st)

          local deferred = false
          local rk = duels.KNOBS.REVEAL or {}
          if def_was_fd and rk.enabled ~= false and defender_side and st.field then
            local slot = (defender_side == "opp") and st.field.opp_monster or st.field.ply_monster
            if slot and slot.card and slot.facedown then
              st.pending_reveal_battle = {
                attacker_side = attacker_side,
                defender_side = defender_side,
                end_turn_after = (attacker_side == "opp") and true or false,
                is_reveal = true,
              }

              -- Hold starts AFTER the flip completes (see pos_anim completion edit).
              st.reveal_hold_seconds = tonumber(rk.hold) or 1.0
              st.reveal_hold_until = nil

              _start_reveal_def_anim(pid, st, defender_side)

              -- If reveal anim couldn't start, force immediate reveal but still delay battle.
              if not (st.pos_anim and st.pos_anim.active) then
                slot.facedown = false
                slot.pos = "def"
                st.reveal_hold_until = now + (st.reveal_hold_seconds or 1.0)
                st.reveal_hold_seconds = nil
              end

              -- Restore attacker zone right away (defender stays animated/hidden).
              _draw_monsters(pid, st)
              _draw_hands(pid, st)
              _draw_point_counters(pid, st)

              deferred = true
            end
          end

          if not deferred then
            _resolve_attack_battle(pid, st, attacker_side)
            _draw_monsters(pid, st)
            _draw_hands(pid, st)
            _draw_point_counters(pid, st)

            if st.duel_over then goto continue_pid end

            if attacker_side == "opp" and _ai_enabled() then
              _begin_turn(pid, st, "ply")
            end
          end
        end
      end

      -- ------------------------------------------------------------
      -- 4.5) Deferred battle resolution after revealing a face-down defender
      -- ------------------------------------------------------------
      if st.pending_reveal_battle and (st.reveal_hold_until ~= nil) then
        local hold_until = st.reveal_hold_until or 0
        if now >= hold_until then
          if not ((st.summon_anim and st.summon_anim.active) or (st.pos_anim and st.pos_anim.active) or (st.attack_anim and st.attack_anim.active)) then
            local pb = st.pending_reveal_battle
            st.pending_reveal_battle = nil
            st.reveal_hold_until = nil
            st.reveal_hold_seconds = nil

            _resolve_attack_battle(pid, st, (pb and pb.attacker_side) or "ply")
            _draw_monsters(pid, st)
            _draw_hands(pid, st)
            _draw_point_counters(pid, st)

            if st.duel_over then goto continue_pid end

            if (pb and pb.end_turn_after) and _ai_enabled() then
              _begin_turn(pid, st, "ply")
            end
          end
        end
      end

      -- ------------------------------------------------------------
      -- 5) Drive opponent scheduled attack (after summon delay)
      -- ------------------------------------------------------------
      if st.pending_opp_attack and (st.turn == "opp") then
        local when = st.pending_opp_attack_at or 0
        if now >= when then
          if not st.pending_reveal_battle
            and not ((st.summon_anim and st.summon_anim.active)
                  or (st.pos_anim and st.pos_anim.active)
                  or (st.attack_anim and st.attack_anim.active))
          then
            st.pending_opp_attack = false
            st.pending_opp_attack_at = nil
            _start_attack_anim(pid, st, "opp")

            -- safety: if attack cannot start (e.g., target disappeared), end the opponent turn shortly
            if not (st.attack_anim and st.attack_anim.active) then
              if _ai_enabled() then
                _ai_opp_queue_end_turn(pid, st, now)
              end
            end
          end
        end
      end

      -- ------------------------------------------------------------
      -- 6) Drive opponent scheduled end-turn (when no legal attack happens)
      -- ------------------------------------------------------------
      if st.pending_opp_end_turn_at and (st.turn == "opp") then
        local when = st.pending_opp_end_turn_at or 0
        if now >= when then
          if not st.pending_reveal_battle
            and not ((st.summon_anim and st.summon_anim.active)
                  or (st.pos_anim and st.pos_anim.active)
                  or (st.attack_anim and st.attack_anim.active))
          then
            st.pending_opp_end_turn_at = nil
            if _ai_enabled() and (not st.duel_over) then
              _begin_turn(pid, st, "ply")
            end
          end
        end
      end

      -- ------------------------------------------------------------
      -- 7) Drive pause-menu slide animation (must redraw per tick)
      -- ------------------------------------------------------------
      if st.in_pause_menu then
        local mk = duels.KNOBS.PAUSE_MENU or {}
        if mk.slide_enabled ~= false then
          local dur = tonumber(mk.slide_duration) or 0.18

          -- Ensure open time is initialized
          if not st.pause_menu_opened_at then
            st.pause_menu_opened_at = now
          end

          -- Redraw while sliding (so you see motion)
          if (now - st.pause_menu_opened_at) <= dur then
            _draw_pause_menu(pid, st)
          end
        end
      end
    end

    ::continue_pid::
  end
end)

function _ai_opp_try_cast_spell(pid, st, spell_id)
  if not (st and st.field and spell_id and duels and duels._spells) then return false end

  local api = {
    destroy_monster = function(target_side, reason)
      _destroy_monster(pid, st, target_side, reason or "spell")
    end,
    end_duel_by_points = function(winner_side)
      _end_duel_by_points(pid, st, winner_side)
    end,
    toggle_opponent_monster_position = function(new_pos)
      _toggle_opponent_monster_position(pid, st, new_pos)
    end,
    toggle_player_monster_position = function(new_pos)
      _toggle_player_monster_position(pid, st, new_pos)
    end,
    modify_opponent_def_permanently = function(delta)
      local mon = st.field.opp_monster
      if mon then
        _apply_perm_def(mon, delta)
        _draw_monsters(pid, st)
      end
    end,
    modify_player_def_permanently = function(delta)
      local mon = st.field.ply_monster
      if mon then
        _apply_perm_def(mon, delta)
        _draw_monsters(pid, st)
      end
    end,
    start_reveal_def_anim = function(target_side)
      _start_reveal_def_anim(pid, st, target_side)
    end,
  }

  local ok_spell, reason = duels._spells.activate(st, "opp", spell_id, api)
  if not ok_spell and _ai_knobs().debug then
    print(("[duels.ai] spell '%s' failed: %s"):format(tostring(spell_id), tostring(reason)))
  end
  return ok_spell
end

end


return duels
