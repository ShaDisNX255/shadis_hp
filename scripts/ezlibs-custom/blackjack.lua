-- /server/scripts/ezlibs-custom/blackjack.lua
-- Blackjack mini-game (sprite-api + Displayer)
--
-- Controls:
--   - Left/Right: adjust bet (only while betting)
--   - Confirm: Hit (or collect payout/reset if round over)
--   - Move Down: Stand
--   - Cancel: Close
--
-- Token behavior:
--   - Bet starts at 0
--   - While betting, Tokens display shows (bank - bet) in real time
--   - Bet is NOT spent until the round starts (first Hit or Stand)
--   - Payout is added to bank when you press Confirm after the round ends

-- net-games Displayer (for font-based numbers only)
local Displayer = require("scripts/net-games/displayer/displayer")
Displayer:init() -- safe even if other systems use it too

-- ezmemory (token currency) - same detection strategy as slots.lua
local ezmemory = rawget(_G, "ezmemory")
if not ezmemory then
  local ok, mod = pcall(require, "scripts/ezlibs-scripts/ezmemory")
  if ok then ezmemory = mod end
end
if not ezmemory then
  local ok, mod = pcall(require, "scripts/ezlibs-custom/ezmemory")
  if ok then ezmemory = mod end
end

-- Async helpers (internal Async API)
local Async = rawget(_G, "Async")

local function async(p)
  if not Async or not Async.promisify then
    local ok, err = pcall(p)
    if not ok then print("[blackjack] async error:", err) end
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
-- Assets
-- ======================
local TABLE_TEX   = "/server/assets/blackjack/ui/table.png"
local TABLE_ANIM  = "/server/assets/blackjack/ui/table.animation"
local TABLE_STATE = "table"

local CARDS_TEX   = "/server/assets/blackjack/ui/cards.png"
local CARDS_ANIM  = "/server/assets/blackjack/ui/cards.animation"
local CARD_BACK_STATE = "face-down"

local CONTROLS_TEX   = "/server/assets/blackjack/ui/controls.png"
local CONTROLS_ANIM  = "/server/assets/blackjack/ui/controls.animation"
local CONTROLS_STATE = "controls"

local CURRENCY_TEX   = "/server/assets/blackjack/ui/currency.png"
local CURRENCY_ANIM  = "/server/assets/blackjack/ui/currency.animation" -- states: tokens, payout, bet

-- ======================
-- Knobs (screen + positioning)
-- ======================
local SCREEN_W = 240
local SCREEN_H = 160

-- Engine coordinate multiplier (slots uses 2; keep consistent)
local UI_POS_MULT = 2

-- ----------------------
-- Main table UI knobs
-- ----------------------
local TABLE_W = 160
local TABLE_H = 120

-- Keep your tuned values
local UI_SX = 1.5
local UI_SY = 1.5
local UI_OFFSET_X = 0
local UI_OFFSET_Y = 0
local UI_Z = 6

local TABLE_SPRITE_ID = "blackjack_table_ui"

-- ----------------------
-- Controls UI knobs
-- ----------------------
local CONTROLS_UI = {
  sx = 2.0,
  sy = 2.0,
  rel_x = 55,
  rel_y = 155,
  z = UI_Z + 5,
}
local CONTROLS_SPRITE_ID = "blackjack_controls_ui"

-- ----------------------
-- Currency UI knobs
-- ----------------------
local CURRENCY_UI = {
  z = UI_Z + 8,

  tokens = { rel_x = 195, rel_y = 65, sx = 2.5, sy = 2.5, state = "tokens" },
  payout = { rel_x = 195, rel_y = 40, sx = 2.5, sy = 2.5, state = "payout" },
  bet    = { rel_x = 195, rel_y = 15, sx = 2.5, sy = 2.5, state = "bet" },
}

local CURRENCY_TEXT = {
  font = "GRADIENT",
  z = UI_Z + 9,

  tokens = { id = "blackjack_tokens_text", rel_x = 204, rel_y = 77, scale = 1.5 },
  payout = { id = "blackjack_payout_text", rel_x = 204, rel_y = 52, scale = 1.5 },
  bet    = { id = "blackjack_bet_text",    rel_x = 204, rel_y = 27, scale = 1.5 },
}

local CURRENCY_ID = {
  tokens = "blackjack_currency_tokens_ui",
  payout = "blackjack_currency_payout_ui",
  bet    = "blackjack_currency_bet_ui",
}

-- ----------------------
-- Scoreboard UI (Displayer only)
-- ----------------------
local SCOREBOARD_UI = {
  z = UI_Z + 9,

  label_font = "THICK",
  value_font = "GRADIENT",

  rel_x = 190,
  rel_y = 120,

  label_scale = 1.5,
  value_scale = 1.6,

  line_gap = 10,

  label_dx = 0,
  value_dx = 0,
}

local SCOREBOARD_TEXT = {
  dealer_label = { id = "bj_score_dealer_label", text = "Dealer:" },
  dealer_value = { id = "bj_score_dealer_value", text = "00" },
  player_label = { id = "bj_score_player_label", text = "You:" },
  player_value = { id = "bj_score_player_value", text = "00" },
}

-- ----------------------
-- Card UI knobs
-- ----------------------
local CARD_UI = {
  sx = 2.8,
  sy = 2.8,

  z = UI_Z + 10,

  overlap_dx = 15,
  overlap_dy = 0,

  dealer = { rel_x = 20, rel_y = 15 },
  player = { rel_x = 20, rel_y = 90 },
}

-- ======================
-- Gameplay knobs
-- ======================
local MAX_HAND_CARDS = 12
local DEALER_DRAW_DELAY_SEC = 0.6

-- Max bet cap (tokens)
local MAX_BET = 10

local MAX_DISPLAY = 9999
local FALLBACK_STARTING_TOKENS = 10

-- ======================
-- State
-- st_by_pid[pid] = {
--   ui_x, ui_y,
--   deck,
--   dealer_cards, dealer_hole_real, player_cards,
--   stage = "betting"|"player_turn"|"dealer_turn"|"round_over",
--   busy = bool,
--   round_token = int,
--   use_ez_tokens = bool,
--   tokens_bank = int,
--   bet = int,
--   payout = int,
-- }
-- ======================
local st_by_pid = {}

local function _is_open(pid)
  return st_by_pid[pid] ~= nil
end

-- Expose Blackjack open-state so other UI systems (e.g. LMenu) can respect this modal UI.
do
  local Blackjack = rawget(_G, "Blackjack")
  if type(Blackjack) ~= "table" then Blackjack = {} end

  function Blackjack.is_open_for(pid)
    return st_by_pid[pid] ~= nil
  end

  rawset(_G, "Blackjack", Blackjack)
  rawset(_G, "blackjack_ui_is_open", Blackjack.is_open_for)
end

-- ======================
-- Sprite + Displayer helpers
-- ======================
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

local function _draw_sprite(pid, sprite_id, x, y, sx, sy, z, anim_state)
  pcall(Net.player_draw_sprite, pid, sprite_id, {
    id = sprite_id .. "_obj",
    x = x * UI_POS_MULT,
    y = y * UI_POS_MULT,
    sx = sx,
    sy = sy,
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

local function _ensure_displayer_fonts(pid)
  local fs = Displayer and Displayer._subsystems and Displayer._subsystems.FontSystem
  if not fs then return end
  if not fs.player_fonts or not fs.player_fonts[pid] then
    pcall(function() fs:setupPlayerFonts(pid) end)
  end
end

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

-- ======================
-- Formatting
-- ======================
local function _clamp4(n)
  n = math.floor(tonumber(n) or 0)
  if n < 0 then n = 0 end
  if n > MAX_DISPLAY then n = MAX_DISPLAY end
  return n
end

local function _fmt4(n)
  return string.format("%04d", _clamp4(n))
end

local function _fmt2(n)
  n = math.floor(tonumber(n) or 0)
  if n < 0 then n = 0 end
  if n > 99 then n = 99 end
  return string.format("%02d", n)
end

-- ======================
-- Position helpers
-- ======================
local function _center_pos()
  local w = (TABLE_W or 0) * UI_SX
  local h = (TABLE_H or 0) * UI_SY
  local x = math.floor((SCREEN_W - w) / 2) + UI_OFFSET_X
  local y = math.floor((SCREEN_H - h) / 2) + UI_OFFSET_Y
  return x, y
end

-- ======================
-- Controls UI
-- ======================
local function _clear_controls(pid)
  _erase_and_dealloc(pid, CONTROLS_SPRITE_ID)
end

local function _draw_controls(pid)
  local st = st_by_pid[pid]
  if not st then return end

  local x = st.ui_x + (CONTROLS_UI.rel_x or 0)
  local y = st.ui_y + (CONTROLS_UI.rel_y or 0)

  _alloc_sprite_safely(pid, CONTROLS_SPRITE_ID, CONTROLS_TEX, CONTROLS_ANIM, CONTROLS_STATE)
  _draw_sprite(pid, CONTROLS_SPRITE_ID, x, y, CONTROLS_UI.sx, CONTROLS_UI.sy, CONTROLS_UI.z, CONTROLS_STATE)
end

-- ======================
-- Currency UI
-- ======================
local function _clear_currency(pid)
  _erase_and_dealloc(pid, CURRENCY_ID.tokens)
  _erase_and_dealloc(pid, CURRENCY_ID.payout)
  _erase_and_dealloc(pid, CURRENCY_ID.bet)

  _erase_text(pid, CURRENCY_TEXT.tokens.id)
  _erase_text(pid, CURRENCY_TEXT.payout.id)
  _erase_text(pid, CURRENCY_TEXT.bet.id)
end

local function _draw_currency_icon(pid, key)
  local st = st_by_pid[pid]
  if not st then return end
  local cfg = CURRENCY_UI[key]
  if not cfg then return end

  local sprite_id = CURRENCY_ID[key]
  local x = st.ui_x + (cfg.rel_x or 0)
  local y = st.ui_y + (cfg.rel_y or 0)

  _alloc_sprite_safely(pid, sprite_id, CURRENCY_TEX, CURRENCY_ANIM, cfg.state)
  _draw_sprite(pid, sprite_id, x, y, cfg.sx, cfg.sy, CURRENCY_UI.z, cfg.state)
end

local function _draw_currency_icons(pid)
  _provide(pid, CURRENCY_TEX)
  _provide(pid, CURRENCY_ANIM)

  _draw_currency_icon(pid, "tokens")
  _draw_currency_icon(pid, "payout")
  _draw_currency_icon(pid, "bet")
end

local function _draw_currency_text(pid)
  local st = st_by_pid[pid]
  if not st then return end

  local base_x = st.ui_x * UI_POS_MULT
  local base_y = st.ui_y * UI_POS_MULT

  draw_text(
    CURRENCY_TEXT.tokens.id,
    pid,
    "0000",
    base_x + (CURRENCY_TEXT.tokens.rel_x * UI_POS_MULT),
    base_y + (CURRENCY_TEXT.tokens.rel_y * UI_POS_MULT),
    CURRENCY_TEXT.z,
    CURRENCY_TEXT.font,
    CURRENCY_TEXT.tokens.scale
  )

  draw_text(
    CURRENCY_TEXT.payout.id,
    pid,
    "0000",
    base_x + (CURRENCY_TEXT.payout.rel_x * UI_POS_MULT),
    base_y + (CURRENCY_TEXT.payout.rel_y * UI_POS_MULT),
    CURRENCY_TEXT.z,
    CURRENCY_TEXT.font,
    CURRENCY_TEXT.payout.scale
  )

  draw_text(
    CURRENCY_TEXT.bet.id,
    pid,
    "0000",
    base_x + (CURRENCY_TEXT.bet.rel_x * UI_POS_MULT),
    base_y + (CURRENCY_TEXT.bet.rel_y * UI_POS_MULT),
    CURRENCY_TEXT.z,
    CURRENCY_TEXT.font,
    CURRENCY_TEXT.bet.scale
  )
end

local function _set_tokens_text(pid, n)
  update_text(CURRENCY_TEXT.tokens.id, pid, _fmt4(n))
end

local function _set_payout_text(pid, n)
  update_text(CURRENCY_TEXT.payout.id, pid, _fmt4(n))
end

local function _set_bet_text(pid, n)
  update_text(CURRENCY_TEXT.bet.id, pid, _fmt4(n))
end

-- ======================
-- Scoreboard (Displayer only)
-- ======================
local function _clear_scoreboard(pid)
  _erase_text(pid, SCOREBOARD_TEXT.dealer_label.id)
  _erase_text(pid, SCOREBOARD_TEXT.dealer_value.id)
  _erase_text(pid, SCOREBOARD_TEXT.player_label.id)
  _erase_text(pid, SCOREBOARD_TEXT.player_value.id)
end

local function _draw_scoreboard(pid)
  local st = st_by_pid[pid]
  if not st then return end

  local z = SCOREBOARD_UI.z or (UI_Z + 9)
  local label_font = SCOREBOARD_UI.label_font or "THICK"
  local value_font = SCOREBOARD_UI.value_font or "GRADIENT"
  local label_scale = SCOREBOARD_UI.label_scale or 1.0
  local value_scale = SCOREBOARD_UI.value_scale or 1.0
  local gap = SCOREBOARD_UI.line_gap or 10

  local bx = (st.ui_x + (SCOREBOARD_UI.rel_x or 0)) * UI_POS_MULT
  local by = (st.ui_y + (SCOREBOARD_UI.rel_y or 0)) * UI_POS_MULT

  local label_dx = (SCOREBOARD_UI.label_dx or 0) * UI_POS_MULT
  local value_dx = (SCOREBOARD_UI.value_dx or 0) * UI_POS_MULT

  -- Line 1
  draw_text(
    SCOREBOARD_TEXT.dealer_label.id,
    pid,
    SCOREBOARD_TEXT.dealer_label.text,
    bx + label_dx,
    by + (0 * gap * UI_POS_MULT),
    z,
    label_font,
    label_scale
  )

  -- Line 2
  draw_text(
    SCOREBOARD_TEXT.dealer_value.id,
    pid,
    SCOREBOARD_TEXT.dealer_value.text,
    bx + value_dx,
    by + (1 * gap * UI_POS_MULT),
    z,
    value_font,
    value_scale
  )

  -- Line 3
  draw_text(
    SCOREBOARD_TEXT.player_label.id,
    pid,
    SCOREBOARD_TEXT.player_label.text,
    bx + label_dx,
    by + (2 * gap * UI_POS_MULT),
    z,
    label_font,
    label_scale
  )

  -- Line 4
  draw_text(
    SCOREBOARD_TEXT.player_value.id,
    pid,
    SCOREBOARD_TEXT.player_value.text,
    bx + value_dx,
    by + (3 * gap * UI_POS_MULT),
    z,
    value_font,
    value_scale
  )
end

local function _set_scoreboard(pid, dealer_score, player_score)
  update_text(SCOREBOARD_TEXT.dealer_value.id, pid, _fmt2(dealer_score))
  update_text(SCOREBOARD_TEXT.player_value.id, pid, _fmt2(player_score))
end

-- ======================
-- Cards + deck
-- ======================
local function _card_state(suit, rank)
  return string.format("%s-%s", suit, rank)
end

local function _build_deck_states()
  local suits = { "heart", "club", "spade", "diamond" }
  local ranks = { "ace", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "jack", "queen", "king" }

  local deck = {}
  for _, s in ipairs(suits) do
    for _, r in ipairs(ranks) do
      deck[#deck+1] = _card_state(s, r)
    end
  end
  return deck
end

local function _draw_from_deck(deck)
  if not deck or #deck == 0 then return nil end
  local i = math.random(#deck)
  local state = deck[i]
  deck[i] = deck[#deck]
  deck[#deck] = nil
  return state
end

local function _dealer_sprite_id(i) return "bj_dealer_card_" .. tostring(i) end
local function _player_sprite_id(i) return "bj_player_card_" .. tostring(i) end

local function _clear_cards(pid)
  for i = 1, MAX_HAND_CARDS do
    _erase_and_dealloc(pid, _dealer_sprite_id(i))
    _erase_and_dealloc(pid, _player_sprite_id(i))
  end
end

local function _card_xy(st, who, idx)
  local base = (who == "dealer") and CARD_UI.dealer or CARD_UI.player
  local base_x = st.ui_x + (base.rel_x or 0)
  local base_y = st.ui_y + (base.rel_y or 0)

  local x = base_x + (idx - 1) * (CARD_UI.overlap_dx or 0)
  local y = base_y + (idx - 1) * (CARD_UI.overlap_dy or 0)
  local z = (CARD_UI.z or (UI_Z + 10)) + (idx - 1)
  return x, y, z
end

local function _draw_hand(pid, who)
  local st = st_by_pid[pid]
  if not st then return end

  local cards = (who == "dealer") and st.dealer_cards or st.player_cards
  if not cards then return end

  for i = 1, #cards do
    local state = cards[i]
    if state then
      local sprite_id = (who == "dealer") and _dealer_sprite_id(i) or _player_sprite_id(i)
      local x, y, z = _card_xy(st, who, i)

      _alloc_sprite_safely(pid, sprite_id, CARDS_TEX, CARDS_ANIM, state)
      _draw_sprite(pid, sprite_id, x, y, CARD_UI.sx, CARD_UI.sy, z, state)
    end
  end
end

local function _update_card(pid, who, idx, state)
  local st = st_by_pid[pid]
  if not st then return end

  local sprite_id = (who == "dealer") and _dealer_sprite_id(idx) or _player_sprite_id(idx)
  local x, y, z = _card_xy(st, who, idx)

  -- ensure allocated (safe)
  _alloc_sprite_safely(pid, sprite_id, CARDS_TEX, CARDS_ANIM, state)
  _erase_only(pid, sprite_id)
  _draw_sprite(pid, sprite_id, x, y, CARD_UI.sx, CARD_UI.sy, z, state)
end

local function _append_card(pid, who, state)
  local st = st_by_pid[pid]
  if not st then return end

  local cards = (who == "dealer") and st.dealer_cards or st.player_cards
  if not cards then return end

  if #cards >= MAX_HAND_CARDS then return end

  cards[#cards+1] = state
  local idx = #cards
  _update_card(pid, who, idx, state)
end

-- ======================
-- Scoring
-- ======================
local RANK_VALUE = {
  two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, nine = 9,
  ten = 10, jack = 10, queen = 10, king = 10,
}

local function _rank_from_state(state)
  if not state or state == CARD_BACK_STATE then return nil end
  local _, rank = state:match("^(%a+)%-(%a+)$")
  return rank
end

local function _score_hand(cards, ignore_face_down)
  if not cards then return 0 end

  local total = 0
  local aces = 0

  for _, stt in ipairs(cards) do
    if stt ~= nil then
      if ignore_face_down and stt == CARD_BACK_STATE then
        -- skip
      else
        local rank = _rank_from_state(stt)
        if rank == "ace" then
          total = total + 11
          aces = aces + 1
        else
          total = total + (RANK_VALUE[rank] or 0)
        end
      end
    end
  end

  while total > 21 and aces > 0 do
    total = total - 10
    aces = aces - 1
  end

  return total
end

local function _refresh_scores(pid)
  local st = st_by_pid[pid]
  if not st then return end

  local dealer_visible = _score_hand(st.dealer_cards, true)
  local player_score = _score_hand(st.player_cards, false)

  _set_scoreboard(pid, dealer_visible, player_score)
end

-- ======================
-- Token backend
-- ======================
local function _has_ez_tokens_api()
  local em = ezmemory or rawget(_G, "ezmemory")
  if type(em) ~= "table" then return false end
  return type(em.get_player_tokens) == "function"
     and type(em.add_player_tokens) == "function"
     and type(em.spend_player_tokens) == "function"
end

local function _sync_bank(pid)
  local st = st_by_pid[pid]
  if not st then return 0 end

  if st.use_ez_tokens then
    local em = ezmemory or rawget(_G, "ezmemory")
    if em and em.get_player_tokens then
      local ok, cur = pcall(em.get_player_tokens, pid)
      cur = tonumber(ok and cur or 0) or 0
      st.tokens_bank = math.max(0, math.floor(cur))
    end
  end

  return st.tokens_bank or 0
end

local function _refresh_tokens_display(pid)
  local st = st_by_pid[pid]
  if not st then return end

  local bank = math.max(0, math.floor(st.tokens_bank or 0))
  local bet = math.max(0, math.floor(st.bet or 0))

  local show = bank
  if st.stage == "betting" then
    show = bank - bet
    if show < 0 then show = 0 end
  end

  _set_tokens_text(pid, show)
end

local function _set_bet(pid, n)
  local st = st_by_pid[pid]
  if not st then return end
  n = math.floor(tonumber(n) or 0)
  if n < 0 then n = 0 end

  if n > MAX_BET then n = MAX_BET end
  if n > MAX_DISPLAY then n = MAX_DISPLAY end

  st.bet = n
  _set_bet_text(pid, st.bet)
  _refresh_tokens_display(pid)
end

local function _set_payout(pid, n)
  local st = st_by_pid[pid]
  if not st then return end
  n = math.floor(tonumber(n) or 0)
  if n < 0 then n = 0 end
  if n > MAX_DISPLAY then n = MAX_DISPLAY end

  st.payout = n
  _set_payout_text(pid, st.payout)
end

local function _change_bet(pid, delta)
  local st = st_by_pid[pid]
  if not st then return end
  if st.busy then return end
  if st.stage ~= "betting" then return end

  local bank = math.max(0, math.floor(st.tokens_bank or 0))
  local bet = math.max(0, math.floor(st.bet or 0))

  local new_bet = bet + delta
  if new_bet < 0 then new_bet = 0 end
  if new_bet > bank then new_bet = bank end
  if new_bet > MAX_BET then new_bet = MAX_BET end
  if new_bet > MAX_DISPLAY then new_bet = MAX_DISPLAY end

  if new_bet == bet then return end
  _set_bet(pid, new_bet)
end

-- ======================
-- Round lifecycle
-- ======================
local function _reset_hand(pid)
  local st = st_by_pid[pid]
  if not st then return end

  -- cancel any in-flight dealer coroutine
  st.round_token = (st.round_token or 0) + 1
  st.busy = false

  -- Clear any existing card sprites
  _clear_cards(pid)

  -- Betting preview: show 4 face-down cards so the table doesn't feel empty,
  -- but DO NOT reveal any information (prevents open/close hand-fishing).
  st.deck = nil
  st.dealer_hole_real = nil
  st.dealer_cards = { CARD_BACK_STATE, CARD_BACK_STATE }
  st.player_cards = { CARD_BACK_STATE, CARD_BACK_STATE }
  st.stage = "betting"

  _set_payout(pid, 0)
  _set_bet(pid, 0)

  -- Scores stay 00/00 until the bet is committed and real cards are dealt
  _set_scoreboard(pid, 0, 0)

  -- Draw placeholders
  _draw_hand(pid, "dealer")
  _draw_hand(pid, "player")
end

local function _deal_new_hand(pid)
  local st = st_by_pid[pid]
  if not st then return end

  local deck = _build_deck_states()

  local dealer_hole = _draw_from_deck(deck)
  local dealer_up   = _draw_from_deck(deck)
  local player_1    = _draw_from_deck(deck)
  local player_2    = _draw_from_deck(deck)

  st.deck = deck
  st.dealer_hole_real = dealer_hole
  st.dealer_cards = { CARD_BACK_STATE, dealer_up }
  st.player_cards = { player_1, player_2 }

  -- Update the 4 placeholder cards in-place
  for i = 1, #st.dealer_cards do
    _update_card(pid, "dealer", i, st.dealer_cards[i])
  end
  for i = 1, #st.player_cards do
    _update_card(pid, "player", i, st.player_cards[i])
  end

  _refresh_scores(pid)
end

local function _commit_bet(pid)
  local st = st_by_pid[pid]
  if not st then return false end

  local bet = math.max(0, math.floor(st.bet or 0))
  if bet > MAX_BET then
    bet = MAX_BET
    st.bet = bet
    _set_bet_text(pid, bet)
    _refresh_tokens_display(pid)
  end
  if bet <= 0 then return false end

  local em = ezmemory or rawget(_G, "ezmemory")

  if st.use_ez_tokens and em and em.spend_player_tokens then
    local ok = false
    local ok_call, res = pcall(em.spend_player_tokens, pid, bet)
    if ok_call then ok = (res ~= false) end

    if not ok then
      _sync_bank(pid)
      _set_bet(pid, 0)
      return false
    end

    _sync_bank(pid)
  else
    -- local-only fallback
    st.tokens_bank = math.max(0, math.floor((st.tokens_bank or 0) - bet))
  end

  st.stage = "player_turn"

  -- while betting we already showed (bank - bet); after spending bank decreases by bet,
  -- so the tokens display should stay consistent.
  _refresh_tokens_display(pid)

  return true
end

local function _start_round_if_needed(pid)
  local st = st_by_pid[pid]
  if not st then return false end

  if st.stage == "betting" then
    if not _commit_bet(pid) then
      return false
    end

    -- Bet is now committed; deal the initial cards.
    _deal_new_hand(pid)
    return true
  end

  return true
end

local function _finish_round(pid)
  local st = st_by_pid[pid]
  if not st then return end

  local bet = math.max(0, math.floor(st.bet or 0))
  local pscore = _score_hand(st.player_cards, false)
  local dscore = _score_hand(st.dealer_cards, false)

  local payout = 0

  if pscore > 21 then
    payout = 0
  elseif dscore > 21 then
    payout = bet * 2
  elseif pscore > dscore then
    payout = bet * 2
  elseif pscore < dscore then
    payout = 0
  else
    -- push: return bet
    payout = bet
  end

  _set_payout(pid, payout)

  st.stage = "round_over"
  st.busy = false

  -- tokens display should show bank (bet already spent)
  _refresh_tokens_display(pid)
end

local function _start_dealer_turn(pid)
  local st = st_by_pid[pid]
  if not st then return end
  if st.busy then return end

  st.busy = true
  st.stage = "dealer_turn"
  st.round_token = (st.round_token or 0) + 1
  local token = st.round_token

  -- reveal hole card
  if st.dealer_cards and st.dealer_cards[1] == CARD_BACK_STATE then
    st.dealer_cards[1] = st.dealer_hole_real
    _update_card(pid, "dealer", 1, st.dealer_hole_real)
    _refresh_scores(pid)
  end

  async(function()
    local st0 = st_by_pid[pid]
    if not st0 or st0.round_token ~= token then return end

    local pscore = _score_hand(st0.player_cards, false)

    -- If player already bust, don't bother hitting; just end after reveal.
    if pscore > 21 then
      sleep(0.15)
      local st1 = st_by_pid[pid]
      if not st1 or st1.round_token ~= token then return end
      _finish_round(pid)
      return
    end

    while true do
      local st1 = st_by_pid[pid]
      if not st1 or st1.round_token ~= token then return end

      local dscore = _score_hand(st1.dealer_cards, false)
      if dscore >= 17 and dscore >= pscore then
        break
      end

      sleep(DEALER_DRAW_DELAY_SEC)

      local st2 = st_by_pid[pid]
      if not st2 or st2.round_token ~= token then return end

      local next = _draw_from_deck(st2.deck)
      if not next then
        st2.deck = _build_deck_states()
        next = _draw_from_deck(st2.deck)
      end

      if next then
        _append_card(pid, "dealer", next)
        _refresh_scores(pid)
      end

      local st3 = st_by_pid[pid]
      if not st3 or st3.round_token ~= token then return end
      local dscore2 = _score_hand(st3.dealer_cards, false)
      if dscore2 > 21 then
        break
      end
    end

    local st4 = st_by_pid[pid]
    if not st4 or st4.round_token ~= token then return end

    _finish_round(pid)
  end)
end

local function _player_hit(pid)
  local st = st_by_pid[pid]
  if not st then return end
  if st.busy then return end

  if st.stage == "round_over" then
    -- Confirm in round_over is handled by the input loop
    return
  end
  local was_betting = (st.stage == "betting")

  if not _start_round_if_needed(pid) then
    -- bet was 0 or spend failed
    return
  end

  -- If this press *started* the round, treat it as the initial deal (no extra hit card yet).
  if was_betting then
    return
  end

  local next = _draw_from_deck(st.deck)
  if not next then
    st.deck = _build_deck_states()
    next = _draw_from_deck(st.deck)
  end

  if next then
    _append_card(pid, "player", next)
    _refresh_scores(pid)
  end

  local pscore = _score_hand(st.player_cards, false)
  if pscore >= 21 then
    -- Auto-stand on 21, or go to dealer/reveal on bust.
    _start_dealer_turn(pid)
  end
end

local function _player_stand(pid)
  local st = st_by_pid[pid]
  if not st then return end
  if st.busy then return end

  if st.stage == "round_over" then return end

  if not _start_round_if_needed(pid) then
    return
  end

  _start_dealer_turn(pid)
end

local function _collect_payout_and_reset(pid)
  local st = st_by_pid[pid]
  if not st then return end

  local payout = math.max(0, math.floor(st.payout or 0))

  if payout > 0 then
    local em = ezmemory or rawget(_G, "ezmemory")
    if st.use_ez_tokens and em and em.add_player_tokens then
      pcall(function() em.add_player_tokens(pid, payout) end)
      _sync_bank(pid)
    else
      st.tokens_bank = math.max(0, math.floor((st.tokens_bank or 0) + payout))
    end
  end

  _set_payout(pid, 0)
  _reset_hand(pid)
  _refresh_tokens_display(pid)
end

-- ======================
-- Open / Close
-- ======================
local function _close(pid)
  local st = st_by_pid[pid]
  if not st then return end

  -- cancel any in-flight dealer coroutine
  st.round_token = (st.round_token or 0) + 1

  _erase_and_dealloc(pid, TABLE_SPRITE_ID)
  _clear_controls(pid)
  _clear_currency(pid)
  _clear_scoreboard(pid)
  _clear_cards(pid)

  st_by_pid[pid] = nil

  if Net.unlock_player_input then
    pcall(Net.unlock_player_input, pid)
  end
end

local function _open(pid)
  if st_by_pid[pid] then return end

  if Net.lock_player_input then
    pcall(Net.lock_player_input, pid)
  end

  -- Clear any stale objects from a prior crash/hot reload
  _erase_and_dealloc(pid, TABLE_SPRITE_ID)
  _clear_controls(pid)
  _clear_currency(pid)
  _clear_scoreboard(pid)
  _clear_cards(pid)

  local x, y = _center_pos()
  st_by_pid[pid] = {
    ui_x = x,
    ui_y = y,

    deck = nil,
    dealer_hole_real = nil,
    dealer_cards = nil,
    player_cards = nil,

    stage = "betting",
    busy = false,
    round_token = 0,

    use_ez_tokens = false,
    tokens_bank = 0,
    bet = 0,
    payout = 0,
  }

  -- Draw table
  _alloc_sprite_safely(pid, TABLE_SPRITE_ID, TABLE_TEX, TABLE_ANIM, TABLE_STATE)
  _draw_sprite(pid, TABLE_SPRITE_ID, x, y, UI_SX, UI_SY, UI_Z, TABLE_STATE)

  -- Overlays
  _draw_controls(pid)
  _draw_currency_icons(pid)
  _draw_currency_text(pid)
  _draw_scoreboard(pid)

  -- Decide token backend once per open.
  st_by_pid[pid].use_ez_tokens = _has_ez_tokens_api()
  if st_by_pid[pid].use_ez_tokens then
    _sync_bank(pid)
  else
    st_by_pid[pid].tokens_bank = FALLBACK_STARTING_TOKENS
  end

  _set_payout(pid, 0)
  _set_bet(pid, 0)
  _refresh_tokens_display(pid)

  -- Enter betting state (no cards dealt until bet is committed)
  _reset_hand(pid)
end

-- ======================
-- Interaction hook (press A on a blackjack table object)
-- ======================
Net:on("object_interaction", function(ev)
  if not ev or ev.button ~= 0 then return end -- A only

  local pid = ev.player_id
  if not pid or _is_open(pid) then return end

  local area_id = Net.get_player_area(pid)
  if not area_id then return end

  local obj = Net.get_object_by_id(area_id, ev.object_id)
  if not obj then return end

  local cp = obj.custom_properties or {}
  local v = cp["Blackjack"]
  if not v then return end

  _open(pid)
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
  if not event then return end

  local pid = event.player_id
  local st = pid and st_by_pid[pid] or nil
  if not st then return end

  local evs = event.events
  if not evs then return end

  for _, button in next, evs do
    local name = button.name
    local state = button.state    -- Cancel is only allowed when NO round is active.
    -- Allowed in: betting (before the round starts) and round_over (hand finished).
    -- Blocked in: player_turn, dealer_turn.
    if state == 1 and name == "Cancel" then
      if st.stage == "betting" or st.stage == "round_over" then
        _close(pid)
      end
      return
    end

    -- ignore inputs during dealer autoplay
    if st.busy then
      goto continue
    end

    if state == 1 and _is_move_right(name) then
      _change_bet(pid, 1)
      return
    end

    if state == 1 and _is_move_left(name) then
      _change_bet(pid, -1)
      return
    end

    if state == 1 and name == "Move Down" then
      -- Stand
      _player_stand(pid)
      return
    end

    if state == 1 and name == "Confirm" then
      if st.stage == "round_over" then
        _collect_payout_and_reset(pid)
      else
        _player_hit(pid)
      end
      return
    end

    ::continue::
  end
end)

-- ======================
-- Safety cleanup
-- ======================
Net:on("player_disconnect", function(e) if e and e.player_id then _close(e.player_id) end end)
Net:on("player_transfer",   function(e) if e and e.player_id then _close(e.player_id) end end)
Net:on("area_transfer",     function(e) if e and e.player_id then _close(e.player_id) end end)

return {}
