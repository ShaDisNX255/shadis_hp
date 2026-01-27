-- /server/scripts/ezlibs-custom/slots.lua
-- Slots mini-game (sprite-api only)
-- Adds: wager marks + wager changing (1..3)
-- Adds: win detection + win flashing (NO payouts wired)
-- Adds: Mettaur UI sprite (idle/win/lose)
-- Fix: prevent closing before claiming payout; allow Confirm to claim immediately (even during flashing)

-- net-games Displayer (for font-based numbers only)
local Displayer = require("scripts/net-games/displayer/displayer")
Displayer:init() -- safe even if other systems use it too

-- ezmemory (token currency)
-- Prefer the same module path used by eznpcs_events.lua, but keep fallbacks for older layouts.
local ezmemory = rawget(_G, "ezmemory")
if not ezmemory then
  local ok, mod = pcall(require, "scripts/ezlibs-scripts/ezmemory")
  if ok then ezmemory = mod end
end
if not ezmemory then
  local ok, mod = pcall(require, "scripts/ezlibs-custom/ezmemory")
  if ok then ezmemory = mod end
end


-- Shared currency UI assets (NOT per-skin)
local CURRENCY_TEX  = "/server/assets/slots/currency.png"
local CURRENCY_ANIM = "/server/assets/slots/currency.animation"

-- Knobs: currency icons (offsets are relative to your mainui origin)
local CURRENCY_UI = {
  sprite_id = "slots_currency_ui", -- allocated sprite name for this shared sheet
  z = 400,                         -- should be above mainui

  tokens = { ox = 15,  oy = -18,  sx = 2.0, sy = 2.0, state = "tokens" },
  payout = { ox = 100,  oy = -18,  sx = 2.0, sy = 2.0, state = "payout" },
}

-- Knobs: the two "0000" numbers (also relative to mainui origin)
local CURRENCY_TEXT = {
  font = "GRADIENT",
  z = 410, -- should be above currency icons

  tokens = { id = "slots_tokens_text", ox = 22, oy = -8, scale = 1.1 },
  payout = { id = "slots_payout_text", ox = 108, oy = -8, scale = 1.1 },
}

-- ======================
-- Token / payout knobs (TESTING ONLY)
-- ======================
local MAX_DISPLAY = 9999 -- 4-digit display clamp
local FALLBACK_STARTING_TOKENS = 10 -- used only when ezmemory token API isn't available

-- ======================
-- Payout tables (tokens)  ✅ FINALIZED
-- ======================
local PAY_MYSTERY_1 = 1
local PAY_MYSTERY_2_ADJ = 2
local PAY_MYSTERY_3 = 3

local PAY_3K = {
  seven = 200,
  mega  = 150,
  badge = 120,
  bar   = 100,
  rush  = 10,
  tango = 8,
  beat  = 9,
  prog  = 6,
}

-- ======================
-- Config knobs (virtual screen + coordinate mapping)
-- ======================
local SCREEN_W = 240
local SCREEN_H = 160
local UI_POS_MULT = 2 -- keep as-is if your positioning is already perfect

-- ======================
-- Timing knobs
-- ======================
local SPIN_DURATION_SEC = 2.0
local STOP_GAP_SEC = 1.0

local WIN_FLASH_TIMES = 5
local WIN_FLASH_INTERVAL_SEC = 0.5

-- ======================
-- Main UI knobs
-- ======================
local MAINUI_W = 147
local MAINUI_H = 123

-- Keep your tuned values
local UI_SX = 2.0
local UI_SY = 2.0
local UI_OFFSET_X = 75
local UI_OFFSET_Y = 65
local UI_Z = 6

local USE_MAINUI_ANIMATION = false
local MAINUI_ANIM_STATE = "mainui"

-- ======================
-- METT (Mettaur) knobs  ✅ NEW
-- ======================
-- Position is relative to mainui top-left (ui_x/ui_y)
local METT_REL_X = 64
local METT_REL_Y = 15
local METT_SX = UI_SX
local METT_SY = UI_SY
local METT_Z  = UI_Z + 4 -- above mainui/icons/marks; tweak if needed

-- ======================
-- Initial/icons grid knobs (your tuned values)
-- ======================
local ICON_REL_X = 17
local ICON_REL_Y = 24

local ICON_W = 32
local ICON_H = 24
local ICON_GAP_X = 8
local ICON_GAP_Y = 0

local ICON_SX = UI_SX
local ICON_SY = UI_SY
local ICON_Z  = UI_Z + 2

-- ======================
-- Spin reels knobs (your tuned values)
-- ======================
local SPIN_REL_X = 17
local SPIN_REL_Y = 40
local SPIN_GAP_X = 40

local SPIN_SX = UI_SX
local SPIN_SY = UI_SY
local SPIN_Z  = UI_Z + 1

-- ======================
-- Wager marks knobs (KEEPING YOUR WORKING VALUES)
-- ======================
local MARK_REL_X = 5
local MARK_REL_Y = 58
local MARK_SX = UI_SX
local MARK_SY = UI_SY
local MARK_Z  = UI_Z + 3  -- above everything; adjust if you want behind icons

-- ======================
-- INFO board (hold Move Down) ✅ NEW
-- ======================
local INFO_REL_X = 0     -- relative to mainui top-left (ui_x/ui_y)
local INFO_REL_Y = 0
local INFO_SX = UI_SX
local INFO_SY = UI_SY
local INFO_Z  = UI_Z + 20 -- above EVERYTHING
local INFO_SCALE = 1.25        -- uniform
local INFO_SCALE_X = 1.0      -- optional fine-tune
local INFO_SCALE_Y = 1.0

local INFO_ID = {
  ["slot-green"]     = "slots_info_slot_green",
  ["digital-green"]  = "slots_info_digital_green",
  ["slot-purple"]    = "slots_info_slot_purple",
  ["digital-purple"] = "slots_info_digital_purple",
}


-- ======================
-- Allowed SlotMachine folder values
-- ======================
local ALLOWED = {
  ["slot-green"]     = true,
  ["digital-green"]  = true,
  ["slot-purple"]    = true,
  ["digital-purple"] = true,
}

-- ======================
-- Wheel order (17-stop), wrapping mystery2 -> seven
-- ======================
local WHEEL = {
  "seven",
  "prog",
  "beat",
  "rush",
  "bar",
  "prog2",
  "tango",
  "beat2",
  "badge",
  "prog3",
  "mystery",
  "beat3",
  "mega",
  "prog4",
  "rush2",
  "tango2",
  "mystery2",
}

-- Stop-id -> displayed symbol (and payout symbol)
local STOP_ALIAS = {
  prog2 = "prog", prog3 = "prog", prog4 = "prog",
  beat2 = "beat", beat3 = "beat",
  rush2 = "rush",
  tango2 = "tango",
  mystery2 = "mystery",
}

local function _canon_symbol(stop_id)
  return STOP_ALIAS[stop_id] or stop_id
end

local WHEEL_INDEX = {}
for i, v in ipairs(WHEEL) do WHEEL_INDEX[v] = i end

local function _wheel_prev(i) i = i - 1; if i < 1 then i = #WHEEL end; return i end
local function _wheel_next(i) i = i + 1; if i > #WHEEL then i = 1 end; return i end

-- ---------------------------
-- SFX
-- ---------------------------
local SFX = {
  win     = "/server/assets/slots/sfx/item_get.ogg",
  lose    = "/server/assets/slots/sfx/card_error.ogg",
  stop    = "/server/assets/slots/sfx/pause.ogg",
  jackpot = "/server/assets/slots/sfx/jackpot.ogg", -- placeholder for now
}

local function _play_sfx(pid, key)
  local path = SFX[key]
  if not path then return end
  pcall(Net.play_sound_for_player, pid, path)
end

-- ======================
-- Sprite ids
-- ======================
local UI_ID = {
  ["slot-green"]     = "slots_mainui_slot_green",
  ["digital-green"]  = "slots_mainui_digital_green",
  ["slot-purple"]    = "slots_mainui_slot_purple",
  ["digital-purple"] = "slots_mainui_digital_purple",
}

-- ✅ NEW: mettaur sprite id per folder
local METT_ID = {
  ["slot-green"]     = "slots_mett_slot_green",
  ["digital-green"]  = "slots_mett_digital_green",
  ["slot-purple"]    = "slots_mett_slot_purple",
  ["digital-purple"] = "slots_mett_digital_purple",
}

local SPIN_ID = {
  ["slot-green"]     = { "slots_spin_slot_green_1", "slots_spin_slot_green_2", "slots_spin_slot_green_3" },
  ["slot-purple"]    = { "slots_spin_slot_purple_1", "slots_spin_slot_purple_2", "slots_spin_slot_purple_3" },
  ["digital-green"]  = { "slots_spin_digital_green_1", "slots_spin_digital_green_2", "slots_spin_digital_green_3" },
  ["digital-purple"] = { "slots_spin_digital_purple_1", "slots_spin_digital_purple_2", "slots_spin_digital_purple_3" },
}

-- 9 icons, row-major
local ICON_ID = {
  ["slot-green"] = {
    "slots_icon_slot_green_1","slots_icon_slot_green_2","slots_icon_slot_green_3",
    "slots_icon_slot_green_4","slots_icon_slot_green_5","slots_icon_slot_green_6",
    "slots_icon_slot_green_7","slots_icon_slot_green_8","slots_icon_slot_green_9",
  },
  ["slot-purple"] = {
    "slots_icon_slot_purple_1","slots_icon_slot_purple_2","slots_icon_slot_purple_3",
    "slots_icon_slot_purple_4","slots_icon_slot_purple_5","slots_icon_slot_purple_6",
    "slots_icon_slot_purple_7","slots_icon_slot_purple_8","slots_icon_slot_purple_9",
  },
  ["digital-green"] = {
    "slots_icon_digital_green_1","slots_icon_digital_green_2","slots_icon_digital_green_3",
    "slots_icon_digital_green_4","slots_icon_digital_green_5","slots_icon_digital_green_6",
    "slots_icon_digital_green_7","slots_icon_digital_green_8","slots_icon_digital_green_9",
  },
  ["digital-purple"] = {
    "slots_icon_digital_purple_1","slots_icon_digital_purple_2","slots_icon_digital_purple_3",
    "slots_icon_digital_purple_4","slots_icon_digital_purple_5","slots_icon_digital_purple_6",
    "slots_icon_digital_purple_7","slots_icon_digital_purple_8","slots_icon_digital_purple_9",
  },
}

-- 10 wager marks (states one..ten)
local MARK_ID = {
  ["slot-green"] = {
    "slots_mark_slot_green_1","slots_mark_slot_green_2","slots_mark_slot_green_3","slots_mark_slot_green_4","slots_mark_slot_green_5",
    "slots_mark_slot_green_6","slots_mark_slot_green_7","slots_mark_slot_green_8","slots_mark_slot_green_9","slots_mark_slot_green_10",
  },
  ["slot-purple"] = {
    "slots_mark_slot_purple_1","slots_mark_slot_purple_2","slots_mark_slot_purple_3","slots_mark_slot_purple_4","slots_mark_slot_purple_5",
    "slots_mark_slot_purple_6","slots_mark_slot_purple_7","slots_mark_slot_purple_8","slots_mark_slot_purple_9","slots_mark_slot_purple_10",
  },
  ["digital-green"] = {
    "slots_mark_digital_green_1","slots_mark_digital_green_2","slots_mark_digital_green_3","slots_mark_digital_green_4","slots_mark_digital_green_5",
    "slots_mark_digital_green_6","slots_mark_digital_green_7","slots_mark_digital_green_8","slots_mark_digital_green_9","slots_mark_digital_green_10",
  },
  ["digital-purple"] = {
    "slots_mark_digital_purple_1","slots_mark_digital_purple_2","slots_mark_digital_purple_3","slots_mark_digital_purple_4","slots_mark_digital_purple_5",
    "slots_mark_digital_purple_6","slots_mark_digital_purple_7","slots_mark_digital_purple_8","slots_mark_digital_purple_9","slots_mark_digital_purple_10",
  },
}

local MARK_STATE = { "one","two","three","four","five","six","seven","eight","nine","ten" }

-- KEEPING YOUR WORKING FRAME MAP
local MARK_FRAME = {
  one   = { x = 0,   y = 17  },
  two   = { x = 0,   y = 22 },
  three = { x = 0,   y = 34 },
  four  = { x = 0,   y = 46 },
  five  = { x = 0,   y = 50 },

  six   = { x = 64.5, y = 17  },
  seven = { x = 64.5, y = 22 },
  eight = { x = 64.5, y = 34 },
  nine  = { x = 64.5, y = 46 },
  ten   = { x = 64.5, y = 50 },
}

local WAGER_LINES = {
  [1] = { 3, 8 },
  [2] = { 2, 3, 4, 7, 8, 9 },
  [3] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 },
}

-- Paylines (cell indexes are row-major: 1..3 top, 4..6 mid, 7..9 bottom)
local PAYLINES = {
  top   = { cells = { 1, 2, 3 }, marks = { 2, 7 } },
  mid   = { cells = { 4, 5, 6 }, marks = { 3, 8 } },
  bot   = { cells = { 7, 8, 9 }, marks = { 4, 9 } },
  diag1 = { cells = { 1, 5, 9 }, marks = { 1, 10 } }, -- diagonal 1
  diag2 = { cells = { 7, 5, 3 }, marks = { 5, 6 } },  -- diagonal 2
}

local ACTIVE_PAYLINES = {
  [1] = { "mid" },
  [2] = { "top", "mid", "bot" },
  [3] = { "top", "mid", "bot", "diag1", "diag2" },
}

-- Two sprite IDs so your existing _draw_sprite/_erase_and_dealloc helpers work cleanly
local CURRENCY_ID = {
  tokens = "slots_currency_tokens_ui",
  payout = "slots_currency_payout_ui",
}

-- ======================
-- Async helpers (internal Async API)
-- ======================
local Async = rawget(_G, "Async")

local function async(p)
  if not Async or not Async.promisify then
    local ok, err = pcall(p)
    if not ok then print("[slots] async error:", err) end
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

-- ======================
-- State
-- st_by_pid[pid] = {
--   folder, ui_x, ui_y,
--   phase="initial"|"spinning"|"results",
--   busy=true/false,
--   round_token=int,
--   wager=1..3,
--   grid = { [1]=symbol,...,[9]=symbol },
--   await_claim=bool,   -- payout pending + must be claimed before closing
-- }
-- ======================
local st_by_pid = {}

local function _is_open(pid) return st_by_pid[pid] ~= nil end


-- Expose Slots open-state so other UI systems (e.g. LMenu) can respect this modal UI.
-- (We keep both a table API and a simple function alias for convenience.)
do
  local Slots = rawget(_G, "Slots")
  if type(Slots) ~= "table" then Slots = {} end

  function Slots.is_open_for(pid)
    return st_by_pid[pid] ~= nil
  end

  rawset(_G, "Slots", Slots)
  rawset(_G, "slots_ui_is_open", Slots.is_open_for)
end
local function _center_mainui_pos()
  local w = MAINUI_W * UI_SX
  local h = MAINUI_H * UI_SY
  local x = math.floor((SCREEN_W - w) / 2) + UI_OFFSET_X
  local y = math.floor((SCREEN_H - h) / 2) + UI_OFFSET_Y
  return x, y
end

local function _provide(pid, path)
  if Net.provide_asset_for_player and path and path ~= "" then
    pcall(Net.provide_asset_for_player, pid, path)
  end
end

local function _alloc_sprite_safely(pid, sprite_id, texture_path, anim_path, anim_state)
  _provide(pid, texture_path)
  _provide(pid, anim_path)

  if not Net.player_alloc_sprite then return end

  local opts = { texture_path = texture_path }
  if anim_path and anim_path ~= "" then
    opts.anim_path = anim_path
    opts.anim_state = anim_state or ""
  end

  local ok = pcall(Net.player_alloc_sprite, pid, sprite_id, opts)
  if not ok and Net.player_dealloc_sprite then
    pcall(Net.player_dealloc_sprite, pid, sprite_id)
    pcall(Net.player_alloc_sprite, pid, sprite_id, opts)
  end
end

local function _ensure_displayer_fonts(pid)
  -- Displayer's FontSystem allocates font sprites on player_join.
  -- If this script hot-reloaded while you're already logged in, that join event already passed.
  local fs = Displayer and Displayer._subsystems and Displayer._subsystems.FontSystem
  if not fs then return end

  if not fs.player_fonts or not fs.player_fonts[pid] then
    pcall(function() fs:setupPlayerFonts(pid) end)
  end
end

-- Matches the signature you quoted
local function draw_text(text_id, player_id, text, x, y, z, font, scale)
  _ensure_displayer_fonts(player_id)
  pcall(function()
    Displayer.Text.drawText(player_id, text_id, text, x, y, z, font, scale)
  end)
end

local function update_text(text_id, player_id, text)
  pcall(function()
    Displayer.Text.updateText(player_id, text_id, text)
  end)
end

local function _erase_text(player_id, text_id)
  pcall(function()
    Displayer.Text.removeText(player_id, text_id)
  end)
end

local function _clamp4(n)
  n = math.floor(tonumber(n) or 0)
  if n < 0 then n = 0 end
  if n > MAX_DISPLAY then n = MAX_DISPLAY end
  return n
end

local function _fmt4(n)
  return string.format("%04d", _clamp4(n))
end

local function _norm_tokens(n)
  n = math.floor(tonumber(n) or 0)
  if n < 0 then n = 0 end
  return n
end

local function _has_ez_tokens_api()
  local em = ezmemory or rawget(_G, "ezmemory")
  if type(em) ~= "table" then return false end
  -- Require full token API so we don't accidentally mix modes.
  return type(em.get_player_tokens) == "function"
     and type(em.add_player_tokens) == "function"
     and type(em.spend_player_tokens) == "function"
end

local function _set_tokens(pid, n)
  local st = st_by_pid[pid]
  if not st then return end
  st.tokens_real = _norm_tokens(n)
  update_text(CURRENCY_TEXT.tokens.id, pid, _fmt4(st.tokens_real))
end

local function _get_tokens(pid)
  local st = st_by_pid[pid]
  if not st then return 0 end
  return _norm_tokens(st.tokens_real)
end

local function _sync_tokens(pid)
  local st = st_by_pid[pid]
  if not st then return 0 end

  -- Only sync from ezmemory when we explicitly chose that backend on open.
  if st.use_ez_tokens then
    local em = ezmemory or rawget(_G, "ezmemory")
    if em and em.get_player_tokens then
      local ok, cur = pcall(em.get_player_tokens, pid)
      cur = tonumber(ok and cur or 0) or 0
      _set_tokens(pid, cur)
    end
  end

  return _get_tokens(pid)
end

local function _set_payout(pid, n)
  local st = st_by_pid[pid]
  if not st then return end
  st.payout = _clamp4(n)
  update_text(CURRENCY_TEXT.payout.id, pid, _fmt4(st.payout))
end

-- redraw all 9 icon cells from st.grid (used to restore after canceling flashing)
local function _restore_result_grid(pid)
  local st = st_by_pid[pid]
  if not st then return end
  local folder = st.folder
  if not folder then return end

  for idx = 1, 9 do
    local sym = st.grid and st.grid[idx]
    if sym then
      local sprite_id = ICON_ID[folder][idx]
      local x, y = (function()
        local r = math.floor((idx - 1) / 3) + 1
        local c = ((idx - 1) % 3) + 1
        local x0 = st.ui_x + ICON_REL_X + (c - 1) * (ICON_W + ICON_GAP_X)
        local y0 = st.ui_y + ICON_REL_Y + (r - 1) * (ICON_H + ICON_GAP_Y)
        return x0, y0
      end)()
      pcall(Net.player_draw_sprite, pid, sprite_id, {
        id = sprite_id .. "_obj",
        x = x * UI_POS_MULT,
        y = y * UI_POS_MULT,
        sx = ICON_SX, sy = ICON_SY,
        z = ICON_Z,
        anim_state = sym,
      })
    end
  end
end

local function _draw_sprite(pid, sprite_id, x, y, sx, sy, z, anim_state)
  pcall(Net.player_draw_sprite, pid, sprite_id, {
    id = sprite_id .. "_obj",
    x = x * UI_POS_MULT,
    y = y * UI_POS_MULT,
    sx = sx, sy = sy,
    z = z,
    anim_state = anim_state,
  })
end

local function _erase_only(pid, sprite_id)
  pcall(Net.player_erase_sprite, pid, sprite_id .. "_obj")
end

local function _erase_and_dealloc(pid, sprite_id)
  _erase_only(pid, sprite_id)
  if Net.player_dealloc_sprite then
    pcall(Net.player_dealloc_sprite, pid, sprite_id)
  end
end

local function _clear_all_spins(pid)
  for _, ids in pairs(SPIN_ID) do
    for _, sprite_id in ipairs(ids) do
      _erase_and_dealloc(pid, sprite_id)
    end
  end
end

local function _clear_all_icons(pid)
  for _, ids in pairs(ICON_ID) do
    for _, sprite_id in ipairs(ids) do
      _erase_and_dealloc(pid, sprite_id)
    end
  end
end

local function _clear_all_marks(pid)
  for _, ids in pairs(MARK_ID) do
    for _, sprite_id in ipairs(ids) do
      _erase_and_dealloc(pid, sprite_id)
    end
  end
end

local function _clear_all_mainui(pid)
  for _, sprite_id in pairs(UI_ID) do
    _erase_and_dealloc(pid, sprite_id)
  end
end

-- ✅ NEW: clear mettaur
local function _clear_all_mett(pid)
  for _, sprite_id in pairs(METT_ID) do
    _erase_and_dealloc(pid, sprite_id)
  end
end

local function _clear_currency(pid)
  _erase_and_dealloc(pid, CURRENCY_ID.tokens)
  _erase_and_dealloc(pid, CURRENCY_ID.payout)
  _erase_text(pid, CURRENCY_TEXT.tokens.id)
  _erase_text(pid, CURRENCY_TEXT.payout.id)
end

local function _erase_info(pid)
  local st = st_by_pid[pid]
  if not st then return end

  local folder = st.folder
  local sprite_id = INFO_ID[folder]
  if sprite_id then
    _erase_and_dealloc(pid, sprite_id)
  end

  st.info_down = false
end

local function _close(pid)
  local st = st_by_pid[pid]
  if not st then return end

  -- cancel any in-flight async round (also cancels flashing)
  st.round_token = (st.round_token or 0) + 1

  _clear_all_spins(pid)
  _clear_all_icons(pid)
  _clear_all_marks(pid)
  _clear_all_mett(pid)
  _clear_all_mainui(pid)
  _clear_currency(pid)
  _erase_info(pid)
  st_by_pid[pid] = nil

  if Net.unlock_player_input then
    pcall(Net.unlock_player_input, pid)
  end
end

-- ======================
-- Asset base helpers
-- ======================
local function _icon_sheet_base(folder)
  return tostring(folder):find("^digital%-") and "digital-icons" or "slot-icons"
end

local function _spin_sheet_base(folder)
  return tostring(folder):find("^digital%-") and "digital-spin" or "slot-spin"
end

-- ======================
-- Geometry helpers (cells)
-- ======================
local function _cell_rc(cell_idx)
  local r = math.floor((cell_idx - 1) / 3) + 1
  local c = ((cell_idx - 1) % 3) + 1
  return r, c
end

local function _cell_xy(st, cell_idx)
  local r, c = _cell_rc(cell_idx)
  local x = st.ui_x + ICON_REL_X + (c - 1) * (ICON_W + ICON_GAP_X)
  local y = st.ui_y + ICON_REL_Y + (r - 1) * (ICON_H + ICON_GAP_Y)
  return x, y
end

-- ======================
-- Wager mark draw helpers (uses your MARK_FRAME + MARK_REL)
-- ======================
local function _mark_xy(st, line_i)
  local state = MARK_STATE[line_i]
  local fr = MARK_FRAME[state]
  if not fr then return nil end

  local ref = MARK_FRAME.three
  local anchor_x = st.ui_x + MARK_REL_X
  local anchor_y = st.ui_y + MARK_REL_Y

  local dx = (fr.x - ref.x) * MARK_SX
  local dy = (fr.y - ref.y) * MARK_SY
  return anchor_x + dx, anchor_y + dy
end

local function _draw_mark_line(pid, line_i)
  local st = st_by_pid[pid]
  if not st then return end
  local folder = st.folder

  local ids = MARK_ID[folder]
  if not ids then return end

  local x, y = _mark_xy(st, line_i)
  if not x then return end

  local state = MARK_STATE[line_i]
  local sprite_id = ids[line_i]
  local texture_path = "/server/assets/slots/" .. folder .. "/wager-mark.png"
  local anim_path    = "/server/assets/slots/" .. folder .. "/wager-mark.animation"

  _alloc_sprite_safely(pid, sprite_id, texture_path, anim_path, state)
  _draw_sprite(pid, sprite_id, x, y, MARK_SX, MARK_SY, MARK_Z, state)
end

-- ======================
-- ✅ NEW: Mettaur drawer/state setter
-- ======================
local function _set_mett_state(pid, state)
  local st = st_by_pid[pid]
  if not st then return end

  local folder = st.folder
  local sprite_id = METT_ID[folder]
  if not sprite_id then return end

  local texture_path = "/server/assets/slots/" .. folder .. "/mett.png"
  local anim_path    = "/server/assets/slots/" .. folder .. "/mett.animation"

  local x = st.ui_x + METT_REL_X
  local y = st.ui_y + METT_REL_Y

  -- ensure allocated once; re-draw updates anim_state
  _alloc_sprite_safely(pid, sprite_id, texture_path, anim_path, state)

  -- erase first so we never “miss” an anim_state update
  _erase_only(pid, sprite_id)
  _draw_sprite(pid, sprite_id, x, y, METT_SX, METT_SY, METT_Z, state)
end

local function _draw_info(pid)
  local st = st_by_pid[pid]
  if not st then return end

  local folder = st.folder
  local sprite_id = INFO_ID[folder]
  if not sprite_id then return end

  local texture_path = "/server/assets/slots/" .. folder .. "/info.png"
  local anim_path    = "/server/assets/slots/" .. folder .. "/info.animation"
  local anim_state   = "info"

  local x = st.ui_x + INFO_REL_X
  local y = st.ui_y + INFO_REL_Y

  -- allocate + draw (erase first to avoid state weirdness)
  _alloc_sprite_safely(pid, sprite_id, texture_path, anim_path, anim_state)
  _erase_only(pid, sprite_id)
  local sx = INFO_SX * INFO_SCALE * INFO_SCALE_X
  local sy = INFO_SY * INFO_SCALE * INFO_SCALE_Y
  _draw_sprite(pid, sprite_id, x, y, sx, sy, INFO_Z, anim_state)

  st.info_down = true
end

-- ======================
-- Drawers
-- ======================
local function _draw_mainui(pid, folder, x, y)
  local sprite_id = UI_ID[folder]
  local texture_path = "/server/assets/slots/" .. folder .. "/mainui.png"

  local anim_path, anim_state = "", ""
  if USE_MAINUI_ANIMATION then
    anim_path = "/server/assets/slots/" .. folder .. "/mainui.animation"
    anim_state = MAINUI_ANIM_STATE
  end

  _alloc_sprite_safely(pid, sprite_id, texture_path, anim_path, anim_state)
  _draw_sprite(pid, sprite_id, x, y, UI_SX, UI_SY, UI_Z, anim_state)
end

local function _draw_icon_cell(pid, cell_idx, state)
  local st = st_by_pid[pid]
  if not st then return end

  local folder = st.folder
  local base = _icon_sheet_base(folder)
  local texture_path = "/server/assets/slots/" .. folder .. "/" .. base .. ".png"
  local anim_path    = "/server/assets/slots/" .. folder .. "/" .. base .. ".animation"

  local sprite_id = ICON_ID[folder][cell_idx]
  local x, y = _cell_xy(st, cell_idx)

  _alloc_sprite_safely(pid, sprite_id, texture_path, anim_path, state)
  _draw_sprite(pid, sprite_id, x, y, ICON_SX, ICON_SY, ICON_Z, state)
end

local function _draw_initial_icons(pid)
  local st = st_by_pid[pid]
  if not st then return end

  for r = 1, 3 do
    local state = (r == 1 and "seven") or (r == 2 and "bar") or "badge"
    for c = 1, 3 do
      local idx = (r - 1) * 3 + c
      _draw_icon_cell(pid, idx, state)
    end
  end
end

local function _draw_currency_ui(pid)
  local st = st_by_pid[pid]
  if not st then return end

  -- Ensure assets are provided (re-using your helper)
  _provide(pid, CURRENCY_TEX)
  _provide(pid, CURRENCY_ANIM)

  -- TOKENS icon
  do
    local sprite_id = CURRENCY_ID.tokens
    _alloc_sprite_safely(pid, sprite_id, CURRENCY_TEX, CURRENCY_ANIM, CURRENCY_UI.tokens.state)
    _draw_sprite(
      pid,
      sprite_id,
      st.ui_x + CURRENCY_UI.tokens.ox,
      st.ui_y + CURRENCY_UI.tokens.oy,
      CURRENCY_UI.tokens.sx,
      CURRENCY_UI.tokens.sy,
      CURRENCY_UI.z,
      CURRENCY_UI.tokens.state
    )
  end

  -- PAYOUT icon
  do
    local sprite_id = CURRENCY_ID.payout
    _alloc_sprite_safely(pid, sprite_id, CURRENCY_TEX, CURRENCY_ANIM, CURRENCY_UI.payout.state)
    _draw_sprite(
      pid,
      sprite_id,
      st.ui_x + CURRENCY_UI.payout.ox,
      st.ui_y + CURRENCY_UI.payout.oy,
      CURRENCY_UI.payout.sx,
      CURRENCY_UI.payout.sy,
      CURRENCY_UI.z,
      CURRENCY_UI.payout.state
    )
  end
end

local function _draw_currency_text(pid)
  local st = st_by_pid[pid]
  if not st then return end

  -- IMPORTANT: your sprites multiply x/y by UI_POS_MULT, so text should too
  local base_x = st.ui_x * UI_POS_MULT
  local base_y = st.ui_y * UI_POS_MULT

  draw_text(
    CURRENCY_TEXT.tokens.id,
    pid,
    "0000",
    base_x + (CURRENCY_TEXT.tokens.ox * UI_POS_MULT),
    base_y + (CURRENCY_TEXT.tokens.oy * UI_POS_MULT),
    CURRENCY_TEXT.z,
    CURRENCY_TEXT.font,
    CURRENCY_TEXT.tokens.scale
  )

  draw_text(
    CURRENCY_TEXT.payout.id,
    pid,
    "0000",
    base_x + (CURRENCY_TEXT.payout.ox * UI_POS_MULT),
    base_y + (CURRENCY_TEXT.payout.oy * UI_POS_MULT),
    CURRENCY_TEXT.z,
    CURRENCY_TEXT.font,
    CURRENCY_TEXT.payout.scale
  )
end

local function _draw_spins(pid)
  local st = st_by_pid[pid]
  if not st then return end

  local folder = st.folder
  local base = _spin_sheet_base(folder)

  local texture_path = "/server/assets/slots/" .. folder .. "/" .. base .. ".png"
  local anim_path    = "/server/assets/slots/" .. folder .. "/" .. base .. ".animation"
  local anim_state   = base

  local base_x = st.ui_x + SPIN_REL_X
  local base_y = st.ui_y + SPIN_REL_Y

  local ids = SPIN_ID[folder]
  for i = 1, 3 do
    local sprite_id = ids[i]
    local x = base_x + (i - 1) * SPIN_GAP_X
    local y = base_y

    _alloc_sprite_safely(pid, sprite_id, texture_path, anim_path, anim_state)
    _draw_sprite(pid, sprite_id, x, y, SPIN_SX, SPIN_SY, SPIN_Z, anim_state)
  end
end

local function _draw_reel_result(pid, reel_index, mid_stop)
  local st = st_by_pid[pid]
  if not st then return end

  local mid_i = WHEEL_INDEX[mid_stop] or 1
  local top_i = _wheel_prev(mid_i)
  local bot_i = _wheel_next(mid_i)

  local top_stop = WHEEL[top_i]
  local bot_stop = WHEEL[bot_i]

  -- Canonical symbols are what we DRAW and what we STORE for win logic/payouts
  local top_symbol = _canon_symbol(top_stop)
  local mid_symbol = _canon_symbol(mid_stop)
  local bot_symbol = _canon_symbol(bot_stop)

  -- store result grid (row-major)
  st.grid = st.grid or {}
  st.grid[reel_index]     = top_symbol
  st.grid[reel_index + 3] = mid_symbol
  st.grid[reel_index + 6] = bot_symbol

  -- draw the 3 cells in this reel (use canonical anim states)
  _draw_icon_cell(pid, reel_index,     top_symbol)
  _play_sfx(pid, "stop")
  _draw_icon_cell(pid, reel_index + 3, mid_symbol)
  _play_sfx(pid, "stop")
  _draw_icon_cell(pid, reel_index + 6, bot_symbol)
  _play_sfx(pid, "stop")
end


-- Wager marks: draw only the active line states
local function _refresh_wager_marks(pid)
  local st = st_by_pid[pid]
  if not st then return end

  local folder = st.folder
  local wager = st.wager or 1
  if wager < 1 then wager = 1 elseif wager > 3 then wager = 3 end

  local ids = MARK_ID[folder]
  if not ids then return end

  local show = {}
  for _, line_i in ipairs(WAGER_LINES[wager]) do show[line_i] = true end

  for i = 1, 10 do
    if show[i] then
      _draw_mark_line(pid, i)
    else
      _erase_and_dealloc(pid, ids[i])
    end
  end
end

local function _set_wager(pid, new_wager)
  local st = st_by_pid[pid]
  if not st then return end
  if st.busy then return end -- only when not spinning / not flashing / not awaiting claim

  if new_wager < 1 then new_wager = 1 end
  if new_wager > 3 then new_wager = 3 end
  if st.wager == new_wager then return end

  st.wager = new_wager
  _refresh_wager_marks(pid)
end

-- ======================
-- Win evaluation + flashing
-- ======================
local function _is_mystery(sym) return sym == "mystery" end

-- returns: { any=bool, icon_cells=set, mark_lines=set }
local function _count_mystery(sa, sb, sc)
  local n = 0
  if _is_mystery(sa) then n = n + 1 end
  if _is_mystery(sb) then n = n + 1 end
  if _is_mystery(sc) then n = n + 1 end
  return n
end

-- "Big four" jackpot symbols (3-of-a-kind)
local JACKPOT_BIG4 = {
  seven = true,
  mega  = true,
  bar   = true,
  badge = true,
}

-- returns: wins_table, payout_total
local function _evaluate_wins(st)
  local wins = { any = false, icon_cells = {}, mark_lines = {}, jackpot = false }
  local payout_total = 0

  local wager = st.wager or 1
  if wager < 1 then wager = 1 elseif wager > 3 then wager = 3 end

  local grid = st.grid or {}
  local active = ACTIVE_PAYLINES[wager] or ACTIVE_PAYLINES[1]

  for _, key in ipairs(active) do
    local pl = PAYLINES[key]
    local a, b, c = pl.cells[1], pl.cells[2], pl.cells[3]
    local sa, sb, sc = grid[a], grid[b], grid[c]
    if not (sa and sb and sc) then goto continue end

    -- 1) 3-of-a-kind
    if sa == sb and sb == sc then
      -- Jackpot if it's one of the big four
      if (not _is_mystery(sa)) and JACKPOT_BIG4[sa] then
        wins.jackpot = true
      end

      wins.any = true
      wins.icon_cells[a] = true
      wins.icon_cells[b] = true
      wins.icon_cells[c] = true
      wins.mark_lines[pl.marks[1]] = true
      wins.mark_lines[pl.marks[2]] = true

      if _is_mystery(sa) then
        payout_total = payout_total + PAY_MYSTERY_3
      else
        payout_total = payout_total + (PAY_3K[sa] or 0)
      end

      goto continue
    end

    -- 2) 2 adjacent mystery (a+b OR b+c)
    local ab = _is_mystery(sa) and _is_mystery(sb)
    local bc = _is_mystery(sb) and _is_mystery(sc)
    if ab or bc then
      wins.any = true
      if ab then
        wins.icon_cells[a] = true
        wins.icon_cells[b] = true
      else
        wins.icon_cells[b] = true
        wins.icon_cells[c] = true
      end
      wins.mark_lines[pl.marks[1]] = true
      wins.mark_lines[pl.marks[2]] = true

      payout_total = payout_total + PAY_MYSTERY_2_ADJ
      goto continue
    end

    -- 3) 1 mystery anywhere (NOTE: if it's 2 mysteries separated, pay it twice)
    local mcount = _count_mystery(sa, sb, sc)
    if mcount > 0 then
      wins.any = true
      if _is_mystery(sa) then wins.icon_cells[a] = true end
      if _is_mystery(sb) then wins.icon_cells[b] = true end
      if _is_mystery(sc) then wins.icon_cells[c] = true end
      wins.mark_lines[pl.marks[1]] = true
      wins.mark_lines[pl.marks[2]] = true

      payout_total = payout_total + (PAY_MYSTERY_1 * mcount)
      goto continue
    end

    ::continue::
  end

  return wins, payout_total
end

local function _flash_wins(pid, token, icon_cells_set, mark_lines_set)
  local st = st_by_pid[pid]
  if not st then return end
  local folder = st.folder

  for i = 1, WIN_FLASH_TIMES do
    local st2 = st_by_pid[pid]
    if not st2 or st2.round_token ~= token then return end

    -- HIDE
    for cell_idx, _ in pairs(icon_cells_set) do
      local sprite_id = ICON_ID[folder][cell_idx]
      _erase_only(pid, sprite_id)
    end
    for line_i, _ in pairs(mark_lines_set) do
      local sprite_id = MARK_ID[folder][line_i]
      _erase_only(pid, sprite_id)
    end

    sleep(WIN_FLASH_INTERVAL_SEC)

    local st3 = st_by_pid[pid]
    if not st3 or st3.round_token ~= token then return end

    -- SHOW (re-draw using the stored grid + mark positions)
    for cell_idx, _ in pairs(icon_cells_set) do
      local sym = st3.grid and st3.grid[cell_idx]
      if sym then
        local sprite_id = ICON_ID[folder][cell_idx]
        local x, y = _cell_xy(st3, cell_idx)
        _draw_sprite(pid, sprite_id, x, y, ICON_SX, ICON_SY, ICON_Z, sym)
      end
    end
    for line_i, _ in pairs(mark_lines_set) do
      local sprite_id = MARK_ID[folder][line_i]
      local x, y = _mark_xy(st3, line_i)
      if x then
        local state = MARK_STATE[line_i]
        _draw_sprite(pid, sprite_id, x, y, MARK_SX, MARK_SY, MARK_Z, state)
      end
    end

    sleep(WIN_FLASH_INTERVAL_SEC)
  end
end

-- ======================
-- Round control
-- ======================
local function _collect_payout(pid)
  local st = st_by_pid[pid]
  if not st then return end

  local payout = _norm_tokens(st.payout or 0)
  if payout <= 0 then return end

  local em = ezmemory or rawget(_G, "ezmemory")
  if st.use_ez_tokens and em and em.add_player_tokens then
    pcall(function() em.add_player_tokens(pid, payout) end)
    _sync_tokens(pid)
  else
    _set_tokens(pid, _get_tokens(pid) + payout)
  end

  _set_payout(pid, 0)

  -- Stop flashing immediately (snappy): bump token so _flash_wins exits
  st.round_token = (st.round_token or 0) + 1

  -- Restore grid + wager marks so we don't get stuck “hidden” mid-flash
  _restore_result_grid(pid)
  _refresh_wager_marks(pid)

  -- Now unlock UI controls
  st.await_claim = false
  st.busy = false
end

local function _start_round(pid)
  local st = st_by_pid[pid]
  if not st then return end
  if st.busy then return end

  -- Reset claim flag at spin start
  st.await_claim = false

  local wager = st.wager or 1
  if wager < 1 then wager = 1 elseif wager > 3 then wager = 3 end

  local have = _sync_tokens(pid)

  if have < wager then
    _play_sfx(pid, "lose")
    return
  end

  local em = ezmemory or rawget(_G, "ezmemory")
  if st.use_ez_tokens and em and em.spend_player_tokens then
    local ok = em.spend_player_tokens(pid, wager)
    if not ok then
      _sync_tokens(pid)
      _play_sfx(pid, "lose")
      return
    end
  else
    _set_tokens(pid, have - wager)
  end

  _sync_tokens(pid)
  _set_payout(pid, 0)

  st.busy = true
  st.phase = "spinning"
  st.round_token = (st.round_token or 0) + 1
  local token = st.round_token

  _refresh_wager_marks(pid)
  _set_mett_state(pid, "idle")

  _clear_all_icons(pid)
  st.grid = {}
  _draw_spins(pid)

  async(function()
    sleep(SPIN_DURATION_SEC)

    local st2 = st_by_pid[pid]
    if not st2 or st2.round_token ~= token then return end

    local folder = st2.folder
    for reel = 1, 3 do
      local spin_sprite_id = SPIN_ID[folder][reel]
      _erase_and_dealloc(pid, spin_sprite_id)

      local mid = WHEEL[math.random(#WHEEL)]
      _draw_reel_result(pid, reel, mid)

      if reel < 3 then
        sleep(STOP_GAP_SEC)
        local st3 = st_by_pid[pid]
        if not st3 or st3.round_token ~= token then return end
      end
    end

    local st4 = st_by_pid[pid]
    if not st4 or st4.round_token ~= token then return end

    st4.phase = "results"

    local wins, payout_total = _evaluate_wins(st4)

    if payout_total > 0 then
      st4.await_claim = true
      _set_payout(pid, payout_total)
    end

    if payout_total > 0 then
      _set_mett_state(pid, "win")
      _play_sfx(pid, wins.jackpot and "jackpot" or "win")
      _flash_wins(pid, token, wins.icon_cells, wins.mark_lines)
    else
      _set_mett_state(pid, "lose")
      _play_sfx(pid, "lose")
    end

    local st5 = st_by_pid[pid]
    if not st5 or st5.round_token ~= token then return end

    -- Lock until payout is claimed (but Confirm can claim immediately via virtual_input busy-override)
    if (st5.payout or 0) > 0 then
      st5.busy = true
    else
      st5.busy = false
    end
  end)
end

-- ======================
-- Open
-- ======================
local function _open(pid, folder)
  if st_by_pid[pid] ~= nil then return end

  if Net.lock_player_input then
    pcall(Net.lock_player_input, pid)
  end

  _clear_all_spins(pid)
  _clear_all_icons(pid)
  _clear_all_marks(pid)
  _clear_all_mett(pid)
  _clear_all_mainui(pid)
  _clear_currency(pid)

  local x, y = _center_mainui_pos()

  st_by_pid[pid] = {
    folder = folder,
    ui_x = x,
    ui_y = y,
    phase = "initial",
    busy = false,
    round_token = 0,
    wager = 1,
    grid = {},
    tokens_real = 0,
    payout = 0,
    use_ez_tokens = false,

    -- payout-claim gating
    await_claim = false,
  }

  _draw_mainui(pid, folder, x, y)
  _set_mett_state(pid, "idle")

  _draw_currency_ui(pid)
  _draw_currency_text(pid)

  st_by_pid[pid].use_ez_tokens = _has_ez_tokens_api()
  if st_by_pid[pid].use_ez_tokens then
    _sync_tokens(pid)
  else
    _set_tokens(pid, FALLBACK_STARTING_TOKENS)
  end
  _set_payout(pid, 0)

  _draw_initial_icons(pid)
  _refresh_wager_marks(pid)
end

Net:on("object_interaction", function(ev)
  if ev.button ~= 0 then return end -- A only
  local pid = ev.player_id
  local area_id = Net.get_player_area(pid)
  if not area_id then return end

  local obj = Net.get_object_by_id(area_id, ev.object_id)
  if not obj then return end

  local cp = obj.custom_properties or {}
  local v = cp["SlotMachine"]
  if not v then return end

  local folder = tostring(v):lower():gsub("%s+", ""):gsub("_", "-")
  if not ALLOWED[folder] then return end

  _open(pid, folder)
end)

-- ======================
-- Inputs while UI is open
-- ======================
local function _is_move_left(name)
  return name == "Move Left" or name == "Left"
end

local function _is_move_right(name)
  return name == "Move Right" or name == "Right"
end

Net:on("virtual_input", function(event)
  local pid = event.player_id
  local st = st_by_pid[pid]
  if not st then return end

  local evs = event.events
  if not evs then return end

  -- Busy = ignore ALL inputs
  -- EXCEPT: allow Confirm to claim payout immediately (even during flashing)
  if st.busy then
    for _, button in next, evs do
      if button.state == 1 and button.name == "Confirm" then
        if (st.payout or 0) > 0 and st.await_claim then
          _collect_payout(pid)
        end
        return
      end
    end
    return
  end

  for _, button in next, evs do
    local name  = button.name
    local state = button.state

    if state == 1 and name == "Cancel" then
      _close(pid)
      return
    end

    if state == 1 and name == "Confirm" then
      if (st.payout or 0) > 0 then
        _collect_payout(pid)
      else
        _start_round(pid)
      end
      return
    end

    -- INFO BOARD (engine states: 1=press, 2/4=held-repeat)
    if name == "Move Down" then
      local is_press = (state == 1 or state == 0)
      local is_hold  = (state == 2 or state == 4)

      if is_press or is_hold then
        if not st.info_down then
          _draw_info(pid)
        end
      else
        if st.info_down then
          _erase_info(pid)
        end
      end
      return
    end

    if state == 1 and _is_move_right(name) then
      _set_wager(pid, (st.wager or 1) + 1)
      return
    end

    if state == 1 and _is_move_left(name) then
      _set_wager(pid, (st.wager or 1) - 1)
      return
    end
  end
end)

-- Safety cleanup
Net:on("player_disconnect", function(e) if e and e.player_id then _close(e.player_id) end end)
Net:on("player_transfer",   function(e) if e and e.player_id then _close(e.player_id) end end)
Net:on("area_transfer",     function(e) if e and e.player_id then _close(e.player_id) end end)

return {}
