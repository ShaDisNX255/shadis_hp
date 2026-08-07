-- /server/scripts/ezlibs-custom/uno_pvp.lua
-- Multiplayer UNO for 2-4 players.
--
-- First-release rules:
--   * Classic 108-card deck, seven cards per player.
--   * Match color, number, or action symbol.
--   * Draw one; only the newly drawn card may be played afterward.
--   * No stacking, jump-in, draw-until-playable, scoring, or manual UNO call.
--   * Wild Draw Four is rejected when the player owns an active-color card.
--   * Disconnecting or leaving the area forfeits.
--
-- Required assets:
--   /server/assets/uno/pixel-uno.png
--   /server/assets/uno/pixel-uno.animation
--   /server/assets/uno/official-navi-exe4_orange_2.png
--   /server/assets/uno/official-navi-exe4_orange_2.animation
--
-- Reused assets:
--   /server/assets/blackjack/ui/table.png
--   /server/assets/blackjack/ui/table.animation

local UNO = {}
_G.UNO = UNO

local LobbyOK, Lobby = pcall(require, "scripts/ezlibs-custom/lobby")
local MenuAPIOK, MenuAPI = pcall(require, "scripts/menuAPI/main")
local DisplayerOK, Displayer = pcall(require, "scripts/net-games/displayer/displayer")

if DisplayerOK and Displayer then
  if type(Displayer.init) == "function" then
    pcall(Displayer.init, Displayer)
  end
else
  Displayer = nil
end

local Async = rawget(_G, "Async")

local CFG = {
  DEBUG = true,

  ACTIVITY_ID = "uno",
  TABLE_TYPE = "UNO Table",
  MAX_PLAYERS = 4,
  STARTING_HAND = 7,

  SCREEN_W = 240,
  SCREEN_H = 160,
  UI_POS_MULT = 2,

  TABLE_TEX = "/server/assets/blackjack/ui/table.png",
  TABLE_ANIM = "/server/assets/blackjack/ui/table.animation",
  TABLE_STATE = "table",
  TABLE_X = 0,
  TABLE_Y = -10,
  TABLE_SX = 1.5,
  TABLE_SY = 1.5,

  CARD_TEX = "/server/assets/uno/pixel-uno.png",
  CARD_ANIM = "/server/assets/uno/pixel-uno.animation",
  CARD_BACK_STATE = "CARD_BACK",

  CURSOR_TEX = "/server/assets/duels/cursor.png",
  CURSOR_ANIM = "/server/assets/duels/cursor.animation",
  CURSOR_STATE = "cursor",
  CURSOR_SX = 2.0,
  CURSOR_SY = 2.0,

  Z = {
    table = 5,
    opponent = 20,
    center = 45,
    hand = 80,
    cursor = 150,
    text = 230,
  },

  -- All positions are logical 240x160 screen coordinates.
  DRAW_X = 92,
  DRAW_Y = 58,
  DISCARD_X = 126,
  DISCARD_Y = 58,
  COLOR_MARKER_X = 156,
  COLOR_MARKER_Y = 65,

  HAND_Y = 116,
  HAND_SLIDE_DOWN = 24,
  HAND_SELECTED_RAISE = 7,
  HAND_SCALE = 1.5,
  HAND_NORMAL_STEP = 18,
  HAND_AVAILABLE_W = 216,

  OPP_SCALE = 1.0,
  OPP_TOP_Y = 7,
  OPP_TOP_AVAILABLE_W = 145,
  OPP_SIDE_Y = 39,
  OPP_SIDE_AVAILABLE_H = 65,
  OPP_LEFT_X = 7,
  OPP_RIGHT_X = 222,

  COLOR_PICK_Y = 61,
  COLOR_PICK_STEP = 30,

  DIM_R = 135,
  DIM_G = 135,
  DIM_B = 135,
  DIM_COLOR_MODE = 0,

  RESULT_SECONDS = 4.0,
}

local COLOR_ORDER = { "RED", "YELLOW", "GREEN", "BLUE" }
local COLOR_INDEX = { RED = 1, YELLOW = 2, GREEN = 3, BLUE = 4 }
local KIND_ORDER = {
  number = 1,
  skip = 2,
  reverse = 3,
  draw2 = 4,
  wild = 5,
  wild4 = 6,
}
local COLOR_PICK_STATES = {
  "BLANK_RED_OUTLINE",
  "BLANK_YELLOW_OUTLINE",
  "BLANK_GREEN_OUTLINE",
  "BLANK_BLUE_OUTLINE",
}
local COLOR_MARKER_STATES = {
  RED = "BLANK_RED_FILLED",
  YELLOW = "BLANK_YELLOW_FILLED",
  GREEN = "BLANK_GREEN_FILLED",
  BLUE = "BLANK_BLUE_FILLED",
}

local MATCHES = {}
local MATCH_BY_PID = {}
local VIEWS = {}
local match_sequence = 0
local card_sequence = 0
local close_match

local function dlog(...)
  if not CFG.DEBUG then return end
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  print("[uno] " .. table.concat(parts, " "))
end

local function async(fn)
  if Async and type(Async.promisify) == "function" then
    return Async.promisify(coroutine.create(fn))
  end
  local ok, err = pcall(fn)
  if not ok then dlog("async error:", err) end
  return nil
end

local function sleep(seconds)
  if Async and type(Async.sleep) == "function" and type(Async.await) == "function" then
    return Async.await(Async.sleep(seconds))
  end
  return nil
end

local function play_sfx(pid, key)
  local ui = rawget(_G, "UI_SFX")
  if type(ui) == "table" and type(ui.play) == "function" then
    pcall(ui.play, pid, key)
    return
  end

  local fallback = {
    choose = "/server/assets/sfx/card_choose.ogg",
    select = "/server/assets/sfx/card_select.ogg",
    cancel = "/server/assets/sfx/card_cancel.ogg",
    error = "/server/assets/sfx/card_error.ogg",
    screen_open = "/server/assets/sfx/card_screen_open.ogg",
  }
  if Net and Net.play_sound_for_player and fallback[key] then
    pcall(Net.play_sound_for_player, pid, fallback[key])
  end
end

local function player_name(pid)
  if not pid then return "Player" end
  local ok, name = pcall(Net.get_player_name, pid)
  if ok and name and name ~= "" then return tostring(name) end
  return "Player"
end

local function short_name(pid, max_len)
  local name = player_name(pid)
  max_len = max_len or 13
  if #name <= max_len then return name end
  return name:sub(1, math.max(1, max_len - 1)) .. "."
end

local function provide(pid, path)
  if Net and Net.provide_asset_for_player and path and path ~= "" then
    pcall(Net.provide_asset_for_player, pid, path)
  end
end

local function provide_uno_assets(pid)
  provide(pid, CFG.TABLE_TEX)
  provide(pid, CFG.TABLE_ANIM)

  provide(pid, CFG.CARD_TEX)
  provide(pid, CFG.CARD_ANIM)

  provide(pid, CFG.CURSOR_TEX)
  provide(pid, CFG.CURSOR_ANIM)
end

local function alloc_sprite(pid, sprite_id, texture_path, anim_path, anim_state)
  provide(pid, texture_path)
  provide(pid, anim_path)
  if not (Net and Net.player_alloc_sprite) then return false end

  local opts = { texture_path = texture_path }
  if anim_path and anim_path ~= "" then
    opts.anim_path = anim_path
    opts.anim_state = anim_state or ""
  end

  local ok = pcall(Net.player_alloc_sprite, pid, sprite_id, opts)
  if not ok and Net.player_dealloc_sprite then
    pcall(Net.player_dealloc_sprite, pid, sprite_id)
    ok = pcall(Net.player_alloc_sprite, pid, sprite_id, opts)
  end
  return ok
end

local function draw_sprite(pid, sprite_id, obj_id, x, y, sx, sy, z, anim_state, extra)
  if not (Net and Net.player_draw_sprite) then return end
  local obj = {
    id = obj_id,
    x = math.floor((tonumber(x) or 0) * CFG.UI_POS_MULT + 0.5),
    y = math.floor((tonumber(y) or 0) * CFG.UI_POS_MULT + 0.5),
    sx = sx or 1,
    sy = sy or sx or 1,
    z = z or 0,
    anim_state = anim_state,
  }

  if type(extra) == "table" then
    for key, value in pairs(extra) do obj[key] = value end
  end

  pcall(Net.player_draw_sprite, pid, sprite_id, obj)
end

local function erase_obj(pid, obj_id)
  if Net and Net.player_erase_sprite then
    pcall(Net.player_erase_sprite, pid, obj_id)
  end
end

local function dealloc_sprite(pid, sprite_id)
  if Net and Net.player_dealloc_sprite then
    pcall(Net.player_dealloc_sprite, pid, sprite_id)
  end
end

local function ensure_fonts(pid)
  if not Displayer then return false end
  local fs = Displayer._subsystems and Displayer._subsystems.FontSystem
  if fs and (not fs.player_fonts or not fs.player_fonts[pid]) and fs.setupPlayerFonts then
    pcall(fs.setupPlayerFonts, fs, pid)
  end
  return true
end

local function draw_text(pid, id, text, x, y, z, font, scale)
  if not Displayer then return end
  ensure_fonts(pid)

  if Displayer.Text and type(Displayer.Text.drawText) == "function" then
    pcall(Displayer.Text.drawText, pid, id, tostring(text or ""),
      math.floor((x or 0) * CFG.UI_POS_MULT),
      math.floor((y or 0) * CFG.UI_POS_MULT),
      z or CFG.Z.text,
      font or "THICK",
      scale or 1.0)
    return
  end

  if Displayer.Font and type(Displayer.Font.drawTextWithId) == "function" then
    local ok = pcall(Displayer.Font.drawTextWithId, pid, tostring(text or ""),
      math.floor((x or 0) * CFG.UI_POS_MULT),
      math.floor((y or 0) * CFG.UI_POS_MULT),
      font or "THICK",
      scale or 1.0,
      z or CFG.Z.text,
      id)
    if not ok then
      pcall(Displayer.Font.drawTextWithId, Displayer.Font, pid, tostring(text or ""),
        math.floor((x or 0) * CFG.UI_POS_MULT),
        math.floor((y or 0) * CFG.UI_POS_MULT),
        font or "THICK",
        scale or 1.0,
        z or CFG.Z.text,
        id)
    end
  end
end

local function erase_text(pid, id)
  if not Displayer then return end
  if Displayer.Text and type(Displayer.Text.removeText) == "function" then
    pcall(Displayer.Text.removeText, pid, id)
  elseif Displayer.Font and type(Displayer.Font.eraseTextDisplay) == "function" then
    if not pcall(Displayer.Font.eraseTextDisplay, pid, id) then
      pcall(Displayer.Font.eraseTextDisplay, Displayer.Font, pid, id)
    end
  end
end

local function shuffle(list)
  for i = #list, 2, -1 do
    local j = math.random(i)
    list[i], list[j] = list[j], list[i]
  end
  return list
end

local function new_card(color, kind, value, anim_state)
  card_sequence = card_sequence + 1
  return {
    id = "uno_card_" .. tostring(card_sequence),
    color = color,
    kind = kind,
    value = value,
    state = anim_state,
  }
end

local function build_deck()
  local deck = {}

  for _, color in ipairs(COLOR_ORDER) do
    deck[#deck + 1] = new_card(color, "number", 0, color .. "_0_FILLED")

    for value = 1, 9 do
      deck[#deck + 1] = new_card(color, "number", value, color .. "_" .. value .. "_FILLED")
      deck[#deck + 1] = new_card(color, "number", value, color .. "_" .. value .. "_OUTLINE")
    end

    deck[#deck + 1] = new_card(color, "skip", nil, color .. "_SKIP_FILLED")
    deck[#deck + 1] = new_card(color, "skip", nil, color .. "_SKIP_OUTLINE")
    deck[#deck + 1] = new_card(color, "reverse", nil, color .. "_REVERSE_FILLED")
    deck[#deck + 1] = new_card(color, "reverse", nil, color .. "_REVERSE_OUTLINE")
    deck[#deck + 1] = new_card(color, "draw2", nil, color .. "_DRAW_2_FILLED")
    deck[#deck + 1] = new_card(color, "draw2", nil, color .. "_DRAW_2_OUTLINE")
  end

  for _ = 1, 4 do
    deck[#deck + 1] = new_card(nil, "wild", nil, "WILD")
    deck[#deck + 1] = new_card(nil, "wild4", nil, "WILD_DRAW_4")
  end

  return shuffle(deck)
end

local function card_sort_key(card)
  local color_key = card.color and (COLOR_INDEX[card.color] or 9) or 9
  local kind_key = KIND_ORDER[card.kind] or 9
  local value_key = card.kind == "number" and (tonumber(card.value) or 0) or 20
  local art_key = tostring(card.state or "")
  return color_key, kind_key, value_key, art_key
end

local function sort_hand(hand)
  table.sort(hand, function(a, b)
    local ac, ak, av, aa = card_sort_key(a)
    local bc, bk, bv, ba = card_sort_key(b)
    if ac ~= bc then return ac < bc end
    if ak ~= bk then return ak < bk end
    if av ~= bv then return av < bv end
    return aa < ba
  end)
end

local function find_card_index(hand, card_id)
  for i, card in ipairs(hand or {}) do
    if card.id == card_id then return i end
  end
  return nil
end

local function remove_card(hand, card_id)
  local index = find_card_index(hand, card_id)
  if not index then return nil end
  return table.remove(hand, index), index
end

local function player_index(match, pid)
  for i, player_id in ipairs(match.players) do
    if player_id == pid then return i end
  end
  return nil
end

local function next_index(match, start_index, steps)
  local count = #match.players
  if count <= 0 then return nil end
  local index = start_index
  steps = math.max(0, tonumber(steps) or 1)
  for _ = 1, steps do
    index = ((index - 1 + match.direction) % count) + 1
  end
  return index
end

local function current_pid(match)
  return match and match.players[match.turn_index] or nil
end

local function top_discard(match)
  return match and match.discard[#match.discard] or nil
end

local function has_color_card(hand, color, ignore_id)
  if not color then return false end
  for _, card in ipairs(hand or {}) do
    if card.id ~= ignore_id and card.color == color then return true end
  end
  return false
end

local function same_symbol(a, b)
  if not a or not b then return false end
  if a.kind ~= b.kind then return false end
  if a.kind == "number" then return a.value == b.value end
  return a.kind == "skip" or a.kind == "reverse" or a.kind == "draw2"
end

local function is_playable(match, pid, card)
  if not (match and pid and card) then
    return false
  end

  -- Both Wild cards may always be placed. Wild Draw Four legality is
  -- checked privately if the affected player chooses to challenge.
  if card.kind == "wild" or card.kind == "wild4" then
    return true
  end

  if card.color == match.current_color then
    return true
  end

  return same_symbol(card, top_discard(match))
end

local function recycle_discard(match)
  if #match.draw_pile > 0 then return true end
  if #match.discard <= 1 then return false end

  local top = table.remove(match.discard)
  local recycled = match.discard
  match.discard = { top }
  match.draw_pile = recycled
  shuffle(match.draw_pile)
  dlog("reshuffled discard into draw pile; cards=", #match.draw_pile)
  return #match.draw_pile > 0
end

local function draw_one(match)
  if #match.draw_pile == 0 and not recycle_discard(match) then return nil end
  return table.remove(match.draw_pile)
end

local function draw_cards(match, pid, count)
  local hand = match.hands[pid]
  if not hand then return 0 end

  local drawn = 0
  for _ = 1, count do
    local card = draw_one(match)
    if not card then break end
    hand[#hand + 1] = card
    drawn = drawn + 1
  end
  sort_hand(hand)
  return drawn
end

local function match_for_pid(pid)
  local match_id = MATCH_BY_PID[pid]
  return match_id and MATCHES[match_id] or nil
end

function UNO.is_open_for(pid)
  return VIEWS[pid] ~= nil
end
rawset(_G, "uno_ui_is_open", UNO.is_open_for)

local function view_ids(pid)
  local suffix = tostring(pid):gsub("[^%w]", "_")
  return {
    table_sprite = "uno_table_" .. suffix,
    card_sprite = "uno_cards_" .. suffix,
    cursor_sprite = "uno_cursor_" .. suffix,
    table_obj = "uno_table_obj",
    cursor_obj = "uno_cursor_obj",
  }
end

local function clear_dynamic_objects(pid, view)
  if not view then return end

  for i = 1, view.max_hand_drawn or 0 do erase_obj(pid, "uno_hand_" .. i) end
  for slot = 1, 3 do
    for i = 1, (view.max_opp_drawn and view.max_opp_drawn[slot] or 0) do
      erase_obj(pid, "uno_opp_" .. slot .. "_" .. i)
    end
  end
  for i = 1, 4 do erase_obj(pid, "uno_color_pick_" .. i) end

  erase_obj(pid, "uno_draw_pile")
  erase_obj(pid, "uno_discard")
  erase_obj(pid, "uno_color_marker")
  erase_obj(pid, "uno_direction")
  erase_obj(pid, view.ids.cursor_obj)

  erase_text(pid, "uno_status")
  erase_text(pid, "uno_hint")
  erase_text(pid, "uno_selected")
  erase_text(pid, "uno_direction_text")
  for slot = 1, 3 do
    erase_text(pid, "uno_opp_name_" .. slot)
    erase_text(pid, "uno_opp_count_" .. slot)
  end
end

local function cleanup_view(pid, unlock)
  local view = VIEWS[pid]
  if not view then return end

  if MenuAPIOK and MenuAPI and type(MenuAPI.is_open) == "function" and MenuAPI.is_open(pid) then
    pcall(MenuAPI.close_all, pid, { keep_frozen = true, reason = "uno_cleanup" })
  end

  clear_dynamic_objects(pid, view)
  erase_obj(pid, view.ids.table_obj)
  dealloc_sprite(pid, view.ids.table_sprite)
  dealloc_sprite(pid, view.ids.card_sprite)
  dealloc_sprite(pid, view.ids.cursor_sprite)

  VIEWS[pid] = nil
  if unlock and Net and Net.unlock_player_input then
    pcall(Net.unlock_player_input, pid)
  end
end

local function hand_layout(hand_count, slide_y)
  local scale = CFG.HAND_SCALE
  local card_w = 22 * scale / CFG.UI_POS_MULT
  local normal_step = CFG.HAND_NORMAL_STEP
  local step = normal_step

  if hand_count > 1 then
    step = math.min(normal_step, (CFG.HAND_AVAILABLE_W - card_w) / (hand_count - 1))
  end
  if step < 2 then step = 2 end

  local total_w = card_w + math.max(0, hand_count - 1) * step
  local start_x = math.floor((CFG.SCREEN_W - total_w) / 2)
  return start_x, CFG.HAND_Y + (slide_y or 0), step
end

local function relative_opponents(match, viewer_pid)
  local result = {}
  local me = player_index(match, viewer_pid)
  local count = #match.players
  if not me or count < 2 then return result end

  if count == 2 then
    result[1] = { pid = match.players[next_index(match, me, 1)], place = "top" }
  elseif count == 3 then
    local previous = ((me - 2) % count) + 1
    local following = (me % count) + 1
    result[1] = { pid = match.players[previous], place = "left" }
    result[2] = { pid = match.players[following], place = "right" }
  else
    local previous = ((me - 2) % count) + 1
    local following = (me % count) + 1
    local opposite = ((me + 1) % count) + 1
    result[1] = { pid = match.players[previous], place = "left" }
    result[2] = { pid = match.players[following], place = "right" }
    result[3] = { pid = match.players[opposite], place = "top" }
  end
  return result
end

local function opponent_card_position(place, card_count, index)
  local scale = CFG.OPP_SCALE
  local card_w = 22 * scale / CFG.UI_POS_MULT
  local card_h = 34 * scale / CFG.UI_POS_MULT

  if place == "top" then
    local step = 10
    if card_count > 1 then
      step = math.min(step, (CFG.OPP_TOP_AVAILABLE_W - card_w) / (card_count - 1))
    end
    if step < 1 then step = 1 end
    local total = card_w + math.max(0, card_count - 1) * step
    local x = math.floor((CFG.SCREEN_W - total) / 2) + (index - 1) * step
    return x, CFG.OPP_TOP_Y, CFG.Z.opponent + index
  end

  local step = 8
  if card_count > 1 then
    step = math.min(step, (CFG.OPP_SIDE_AVAILABLE_H - card_h) / (card_count - 1))
  end
  if step < 1 then step = 1 end
  local x = place == "left" and CFG.OPP_LEFT_X or CFG.OPP_RIGHT_X
  local y = CFG.OPP_SIDE_Y + (index - 1) * step
  return x, y, CFG.Z.opponent + index
end

local function draw_opponents(pid, match, view)
  local opponents = relative_opponents(match, pid)
  view.max_opp_drawn = view.max_opp_drawn or {}

  for slot = 1, 3 do
    local opp = opponents[slot]
    local old_max = view.max_opp_drawn[slot] or 0
    local count = opp and #(match.hands[opp.pid] or {}) or 0

    for i = count + 1, old_max do erase_obj(pid, "uno_opp_" .. slot .. "_" .. i) end
    erase_text(pid, "uno_opp_name_" .. slot)
    erase_text(pid, "uno_opp_count_" .. slot)

    if opp then
      for i = 1, count do
        local x, y, z = opponent_card_position(opp.place, count, i)
        draw_sprite(pid, view.ids.card_sprite, "uno_opp_" .. slot .. "_" .. i,
          x, y, CFG.OPP_SCALE, CFG.OPP_SCALE, z, CFG.CARD_BACK_STATE)
      end

      local active = current_pid(match) == opp.pid
      local prefix = active and "> " or ""
      if opp.place == "top" then
        draw_text(pid, "uno_opp_name_" .. slot, prefix .. short_name(opp.pid, 15), 87, 28,
          CFG.Z.text, "THICK", 1.0)
        draw_text(pid, "uno_opp_count_" .. slot, tostring(count) .. " cards", 100, 38,
          CFG.Z.text, "THICK", 0.85)
      elseif opp.place == "left" then
        draw_text(pid, "uno_opp_name_" .. slot, prefix .. short_name(opp.pid, 10), 4, 106,
          CFG.Z.text, "THICK", 0.8)
        draw_text(pid, "uno_opp_count_" .. slot, tostring(count), 4, 115,
          CFG.Z.text, "THICK", 0.8)
      else
        draw_text(pid, "uno_opp_name_" .. slot, prefix .. short_name(opp.pid, 10), 178, 106,
          CFG.Z.text, "THICK", 0.8)
        draw_text(pid, "uno_opp_count_" .. slot, tostring(count), 226, 115,
          CFG.Z.text, "THICK", 0.8)
      end
    end

    view.max_opp_drawn[slot] = math.max(old_max, count)
  end
end

local function selected_card_for_view(match, pid, view)
  local hand = match.hands[pid] or {}
  if #hand == 0 then return nil, nil end

  if match.phase == "drawn_choice" and match.pending_draw_pid == pid and match.pending_draw_card_id then
    local index = find_card_index(hand, match.pending_draw_card_id)
    if index then
      view.hand_index = index
      return hand[index], index
    end
  end

  if view.hand_index < 1 then view.hand_index = 1 end
  if view.hand_index > #hand then view.hand_index = #hand end
  return hand[view.hand_index], view.hand_index
end

local function draw_hand(pid, match, view)
  local hand = match.hands[pid] or {}
  local old_max = view.max_hand_drawn or 0
  local start_x, base_y, step = hand_layout(#hand, view.hand_slide_y or 0)
  local selected, selected_index = selected_card_for_view(match, pid, view)

  for i = #hand + 1, old_max do erase_obj(pid, "uno_hand_" .. i) end
  erase_text(pid, "uno_selected")

  for i, card in ipairs(hand) do
    local can_select = current_pid(match) == pid
      and match.phase ~= "round_over"
      and match.phase ~= "color_select"

    local is_selected =
      can_select
      and view.cursor_mode == "hand"
      and i == selected_index

    local y = base_y - (is_selected and CFG.HAND_SELECTED_RAISE or 0)
    local playable = is_playable(match, pid, card)

    if match.phase == "drawn_choice" and match.pending_draw_pid == pid then
      playable = card.id == match.pending_draw_card_id
    end

    -- Always provide a color. Reused sprite objects retain the previous tint
    -- when these values are omitted.
    local extra = {
      r = 255,
      g = 255,
      b = 255,
      color_mode = CFG.DIM_COLOR_MODE,
    }

    if not playable then
      extra.r = CFG.DIM_R
      extra.g = CFG.DIM_G
      extra.b = CFG.DIM_B
    end

    draw_sprite(pid, view.ids.card_sprite, "uno_hand_" .. i,
      start_x + (i - 1) * step,
      y,
      CFG.HAND_SCALE,
      CFG.HAND_SCALE,
      CFG.Z.hand + i,
      card.state,
      extra)
  end

  view.hand_positions = {
    start_x = start_x,
    base_y = base_y,
    step = step,
    selected_index = selected_index,
  }

  view.max_hand_drawn = math.max(old_max, #hand)
end

local function draw_center(pid, match, view)
  draw_sprite(pid, view.ids.card_sprite, "uno_draw_pile",
    CFG.DRAW_X, CFG.DRAW_Y, CFG.HAND_SCALE, CFG.HAND_SCALE,
    CFG.Z.center, CFG.CARD_BACK_STATE)

  local top = top_discard(match)
  if top then
    draw_sprite(pid, view.ids.card_sprite, "uno_discard",
      CFG.DISCARD_X, CFG.DISCARD_Y, CFG.HAND_SCALE, CFG.HAND_SCALE,
      CFG.Z.center + 1, top.state)
  end

  local marker = COLOR_MARKER_STATES[match.current_color]
  if marker then
    draw_sprite(pid, view.ids.card_sprite, "uno_color_marker",
      CFG.COLOR_MARKER_X, CFG.COLOR_MARKER_Y, 0.9, 0.9,
      CFG.Z.center + 2, marker)
  end

  erase_text(pid, "uno_direction_text")
  draw_text(pid, "uno_direction_text", match.direction == 1 and ">>" or "<<",
    111, 50, CFG.Z.text, "THICK", 1.0)
end

local function draw_color_picker(pid, match, view)
  for i = 1, 4 do erase_obj(pid, "uno_color_pick_" .. i) end
  if match.phase ~= "color_select" or match.pending_wild_pid ~= pid then return end

  local total_w = (4 - 1) * CFG.COLOR_PICK_STEP + (22 * CFG.HAND_SCALE / CFG.UI_POS_MULT)
  local start_x = math.floor((CFG.SCREEN_W - total_w) / 2)
  view.color_start_x = start_x

  for i, state in ipairs(COLOR_PICK_STATES) do
    local y = CFG.COLOR_PICK_Y - (i == view.color_index and 5 or 0)
    draw_sprite(pid, view.ids.card_sprite, "uno_color_pick_" .. i,
      start_x + (i - 1) * CFG.COLOR_PICK_STEP,
      y,
      CFG.HAND_SCALE,
      CFG.HAND_SCALE,
      CFG.Z.hand + i,
      state)
  end
end

local function status_and_hint(match, pid, view)
  local status
  local hint
  local active_pid = current_pid(match)

  if match.phase == "round_over" then
    status = "Winner: " .. short_name(match.winner_pid, 18)

    local counts = {}

    for _, other_pid in ipairs(match.players) do
      if other_pid ~= match.winner_pid then
        counts[#counts + 1] =
          short_name(other_pid, 8)
          .. ":"
          .. tostring(#(match.hands[other_pid] or {}))
      end
    end

    hint = #counts > 0
      and table.concat(counts, "  ")
      or "Match complete"

  elseif match.phase == "color_select" then
    status =
      short_name(match.pending_wild_pid, 15)
      .. " is choosing a color"

    if match.pending_wild_pid == pid then
      hint = "Left/Right: Color   A: Choose   B: Back"
    else
      hint = "Please wait"
    end

  elseif match.phase == "wild4_challenge" then
    local challenger_pid = match.pending_wild4_challenger_pid

    status =
      short_name(challenger_pid, 15)
      .. " is deciding on the +4"

    if challenger_pid == pid then
      hint = "Choose Draw 4 or Challenge"
    else
      hint = "Please wait"
    end

  elseif match.phase == "drawn_choice" then
    status =
      short_name(active_pid, 15)
      .. " drew a playable card"

    if match.pending_draw_pid == pid then
      hint = "A: Play drawn card   B: Keep"
    else
      hint = "Please wait"
    end

  else
    status = "Turn: " .. short_name(active_pid, 16)

    if active_pid == pid then
      if view.cursor_mode == "draw_pile" then
        hint = "A: Draw   Down/B: Hand"
      else
        hint =
          "Left/Right: Cards   Up: Draw pile   A: Play   B: Menu"
      end
    else
      if view.cursor_mode == "draw_pile" then
        hint = "Down/B: View hand"
      else
        hint = "Up: View table   B: Menu"
      end
    end
  end

  if match.notice and match.notice ~= "" then
    status = match.notice .. "  " .. status
  end

  if view.local_notice and view.local_notice ~= "" then
    status = view.local_notice
  end

  erase_text(pid, "uno_status")
  erase_text(pid, "uno_hint")

  draw_text(
    pid,
    "uno_status",
    status,
    64,
    44,
    CFG.Z.text,
    "THICK",
    1.1
  )

  draw_text(
    pid,
    "uno_hint",
    hint,
    16,
    150,
    CFG.Z.text,
    "THICK",
    0.78
  )
end

local function cursor_position(match, pid, view)
  if match.phase == "color_select" and match.pending_wild_pid == pid then
    local x = (view.color_start_x or 60)
      + (view.color_index - 1) * CFG.COLOR_PICK_STEP
      + 8

    local selected_y = CFG.COLOR_PICK_Y - 5
    return x, selected_y - 1
  end

  if view.cursor_mode == "draw_pile" then
    return CFG.DRAW_X + 8, CFG.DRAW_Y - 1
  end

  local hp = view.hand_positions or {}
  local index = hp.selected_index or view.hand_index or 1

  local x = (hp.start_x or 20)
    + (index - 1) * (hp.step or CFG.HAND_NORMAL_STEP)
    + 8

  local selected_y =
    (hp.base_y or CFG.HAND_Y) - CFG.HAND_SELECTED_RAISE

  return x, selected_y - 1
end

local function draw_cursor(pid, match, view)
  erase_obj(pid, view.ids.cursor_obj)

  if view.menu_open or match.phase == "round_over" then
    return
  end

  local owns_input = current_pid(match) == pid

  if match.phase == "color_select" then
    owns_input = match.pending_wild_pid == pid
  elseif match.phase == "wild4_challenge" then
    owns_input = false
  elseif match.phase == "drawn_choice" then
    owns_input = match.pending_draw_pid == pid
  end

  if not owns_input then
    return
  end

  local x, y = cursor_position(match, pid, view)

  draw_sprite(
    pid,
    view.ids.cursor_sprite,
    view.ids.cursor_obj,
    x,
    y,
    CFG.CURSOR_SX,
    CFG.CURSOR_SY,
    CFG.Z.cursor,
    CFG.CURSOR_STATE
  )
end

local function redraw_view(pid)
  local view = VIEWS[pid]
  local match = match_for_pid(pid)
  if not (view and match) then return end

  draw_center(pid, match, view)
  draw_opponents(pid, match, view)
  draw_hand(pid, match, view)
  draw_color_picker(pid, match, view)
  status_and_hint(match, pid, view)
  draw_cursor(pid, match, view)
end

local function redraw_all(match)
  if not match then return end
  for _, pid in ipairs(match.players) do
    if VIEWS[pid] then redraw_view(pid) end
  end
end

local function set_local_notice(pid, text)
  local view = VIEWS[pid]
  if not view then return end

  view.local_notice = tostring(text or "")
  redraw_view(pid)
end

local function set_cursor_mode(pid, mode)
  local view = VIEWS[pid]
  local match = match_for_pid(pid)
  if not (view and match) then return end

  view.cursor_mode = mode
  view.hand_slide_target = mode == "hand" and 0 or CFG.HAND_SLIDE_DOWN
  redraw_view(pid)
end

local function reset_views_for_turn(match)
  for _, pid in ipairs(match.players) do
    local view = VIEWS[pid]
    if view then
      view.cursor_mode = "hand"
      view.hand_slide_target = 0
      view.local_notice = nil
      if #(match.hands[pid] or {}) > 0 then
        view.hand_index = math.min(math.max(view.hand_index or 1, 1), #match.hands[pid])
      else
        view.hand_index = 1
      end
    end
  end
end

local function finish_match(match, winner_pid, reason)
  if not match or match.phase == "round_over" then return end
  match.phase = "round_over"
  match.winner_pid = winner_pid
  match.notice = reason or ""
  match.close_token = (match.close_token or 0) + 1
  local token = match.close_token

  reset_views_for_turn(match)
  redraw_all(match)
  for _, pid in ipairs(match.players) do play_sfx(pid, "select") end

  async(function()
    sleep(CFG.RESULT_SECONDS)
    local current = MATCHES[match.id]
    if current and current.close_token == token then close_match(current) end
  end)
end

local function complete_turn(match, actor_index, steps)
  match.turn_index = next_index(match, actor_index, steps or 1)
  match.phase = "turn"
  match.pending_draw_pid = nil
  match.pending_draw_card_id = nil
  match.pending_wild_pid = nil
  match.pending_wild_card_id = nil
  match.pending_wild_return_phase = nil

  match.pending_wild4_offender_pid = nil
  match.pending_wild4_challenger_pid = nil
  match.pending_wild4_actor_index = nil
  match.pending_wild4_illegal = nil

  reset_views_for_turn(match)
  redraw_all(match)
end

local function begin_color_select(match, pid, card_id, return_phase)
  match.phase = "color_select"
  match.pending_wild_pid = pid
  match.pending_wild_card_id = card_id
  match.pending_wild_return_phase = return_phase or "turn"

  local view = VIEWS[pid]
  if view then
    view.color_index = view.color_index or 1
    view.cursor_mode = "color"
    view.hand_slide_target = CFG.HAND_SLIDE_DOWN
  end
  redraw_all(match)
end

local function clear_wild4_challenge(match)
  match.pending_wild4_offender_pid = nil
  match.pending_wild4_challenger_pid = nil
  match.pending_wild4_actor_index = nil
  match.pending_wild4_illegal = nil

  match.pending_draw_pid = nil
  match.pending_draw_card_id = nil

  match.pending_wild_pid = nil
  match.pending_wild_card_id = nil
  match.pending_wild_return_phase = nil
end

local function resolve_wild4_challenge(match, challenged)
  if not match or match.phase ~= "wild4_challenge" then
    return false
  end

  local offender_pid = match.pending_wild4_offender_pid
  local challenger_pid = match.pending_wild4_challenger_pid
  local actor_index =
    player_index(match, offender_pid)
    or match.pending_wild4_actor_index

  local was_illegal = match.pending_wild4_illegal == true

  if not offender_pid or not challenger_pid or not actor_index then
    clear_wild4_challenge(match)
    match.phase = "turn"
    reset_views_for_turn(match)
    redraw_all(match)
    return false
  end

  local challenger_view = VIEWS[challenger_pid]
  if challenger_view then
    challenger_view.menu_open = false
  end

  clear_wild4_challenge(match)

  if challenged and was_illegal then
    -- Successful challenge: the player who used the +4 draws four.
    -- The challenger does not lose their turn.
    draw_cards(match, offender_pid, 4)

    match.phase = "turn"
    match.turn_index =
      player_index(match, challenger_pid)
      or next_index(match, actor_index, 1)

    match.notice =
      short_name(challenger_pid, 10)
      .. " caught the bluff! "
      .. short_name(offender_pid, 10)
      .. " drew 4."

    reset_views_for_turn(match)
    redraw_all(match)
    return true
  end

  if challenged then
    -- Failed challenge: four from the card plus two for challenging.
    draw_cards(match, challenger_pid, 6)

    match.notice =
      short_name(challenger_pid, 10)
      .. " challenged and drew 6."
  else
    draw_cards(match, challenger_pid, 4)

    match.notice =
      short_name(challenger_pid, 10)
      .. " drew 4."
  end

  -- If Wild Draw Four was the offender's final card, the match only
  -- ends now that the challenge opportunity and penalty are resolved.
  if #(match.hands[offender_pid] or {}) == 0 then
    finish_match(match, offender_pid, match.notice)
    return true
  end

  -- The affected player loses their turn.
  complete_turn(match, actor_index, 2)
  return true
end

local function open_wild4_challenge_menu(match)
  if not match or match.phase ~= "wild4_challenge" then
    return false
  end

  local challenger_pid = match.pending_wild4_challenger_pid
  local offender_pid = match.pending_wild4_offender_pid
  local view = challenger_pid and VIEWS[challenger_pid] or nil

  if not challenger_pid or not offender_pid or not view then
    return resolve_wild4_challenge(match, false)
  end

  if not (
    MenuAPIOK
    and MenuAPI
    and type(MenuAPI.push) == "function"
  ) then
    -- If the menu is unavailable, safely accept the four cards.
    return resolve_wild4_challenge(match, false)
  end

  view.menu_open = true
  erase_obj(challenger_pid, view.ids.cursor_obj)

  local offender_name = short_name(offender_pid, 12)

  local opened = MenuAPI.push(challenger_pid, {
    type = 3,

    title = offender_name .. " +4",
    color = "red",

    x = 49,
    y = 46,
    z = 290,

    open_sfx = "screen_open",
    cancel_sfx = "cancel",
    lock_input = false,

    -- Start on Draw 4. It is the safer/default choice.
    cursor = 4,

    rows = {
      {
        id = "prompt",
        text = "Challenge the play?",
        selectable = false,
        enabled = false,
        disabled_prefix = false,
      },
      {
        id = "spacing",
        text = "",
        selectable = false,
        enabled = false,
        disabled_prefix = false,
      },
      {
        id = "challenge",
        text = "Challenge",
      },
      {
        id = "draw4",
        text = "Draw 4",
      },
    },

    on_confirm = function(player_id, row)
      local current_match = match_for_pid(player_id)

      if not current_match
        or current_match.phase ~= "wild4_challenge"
      then
        return true
      end

      local choice = tostring(row and row.id or "")

      if choice ~= "challenge" and choice ~= "draw4" then
        return true
      end

      -- Resolve first so the menu's on_close callback cannot resolve
      -- the same +4 challenge a second time.
      resolve_wild4_challenge(
        current_match,
        choice == "challenge"
      )

      if MenuAPI and type(MenuAPI.close_all) == "function" then
        MenuAPI.close_all(player_id, {
          keep_frozen = true,
          reason = "uno_wild4_resolved",
        })
      end

      return true
    end,

    on_close = function(player_id)
      local current_view = VIEWS[player_id]

      if current_view then
        current_view.menu_open = false
      end

      local current_match = match_for_pid(player_id)

      -- Pressing B instead of choosing an option means accepting Draw 4.
      if current_match
        and current_match.phase == "wild4_challenge"
        and current_match.pending_wild4_challenger_pid == player_id
      then
        resolve_wild4_challenge(current_match, false)
      elseif current_view then
        redraw_view(player_id)
      end
    end,
  })

  if not opened then
    view.menu_open = false
    return resolve_wild4_challenge(match, false)
  end

  return true
end

local function commit_play(match, pid, card_id, chosen_color)
  if not match or current_pid(match) ~= pid then
    return false, "not_your_turn"
  end

  match.notice = ""

  local hand = match.hands[pid]
  local card = hand and hand[find_card_index(hand, card_id) or -1] or nil

  if not card then
    return false, "card_missing"
  end

  if match.phase == "drawn_choice"
    and match.pending_draw_card_id ~= card_id
  then
    return false, "only_drawn_card"
  end

  if not is_playable(match, pid, card) then
    return false, "not_playable"
  end

  if (card.kind == "wild" or card.kind == "wild4")
    and not chosen_color
  then
    begin_color_select(match, pid, card_id, match.phase)
    return true, "choosing_color"
  end

  local actor_index = player_index(match, pid)

  -- This must be checked before changing the active color or removing
  -- the card. The result remains secret unless a challenge occurs.
  local wild4_was_illegal =
    card.kind == "wild4"
    and has_color_card(hand, match.current_color, card.id)

  remove_card(hand, card_id)

  match.discard[#match.discard + 1] = card
  match.current_color = chosen_color or card.color

  sort_hand(hand)

  local steps = 1

  if card.kind == "skip" then
    steps = 2

  elseif card.kind == "reverse" then
    if #match.players == 2 then
      steps = 2
    else
      match.direction = -match.direction
      steps = 1
    end

  elseif card.kind == "draw2" then
    local target_index = next_index(match, actor_index, 1)
    local target_pid = match.players[target_index]

    draw_cards(match, target_pid, 2)

    match.notice =
      short_name(target_pid, 10)
      .. " drew 2."

    steps = 2

  elseif card.kind == "wild4" then
    local target_index = next_index(match, actor_index, 1)
    local target_pid = match.players[target_index]

    match.phase = "wild4_challenge"
    match.pending_wild4_offender_pid = pid
    match.pending_wild4_challenger_pid = target_pid
    match.pending_wild4_actor_index = actor_index
    match.pending_wild4_illegal = wild4_was_illegal

    match.notice =
      short_name(target_pid, 10)
      .. " may challenge the +4."
  end

  play_sfx(pid, "select")

  if #hand == 1 then
    local uno_notice =
      short_name(pid, 10)
      .. " has UNO!"

    if match.notice and match.notice ~= "" then
      match.notice =
        match.notice
        .. " "
        .. uno_notice
    else
      match.notice = uno_notice
    end
  end

  if card.kind == "wild4" then
    match.pending_wild_pid = nil
    match.pending_wild_card_id = nil
    match.pending_wild_return_phase = nil

    reset_views_for_turn(match)
    redraw_all(match)
    open_wild4_challenge_menu(match)
    return true
  end

  if #hand == 0 then
    finish_match(match, pid, "")
    return true
  end

  match.pending_wild_pid = nil
  match.pending_wild_card_id = nil
  match.pending_wild_return_phase = nil

  complete_turn(match, actor_index, steps)
  return true
end

local function draw_for_turn(match, pid)
  if not match or match.phase ~= "turn" or current_pid(match) ~= pid then
    return false, "not_your_turn"
  end

  match.notice = ""
  local card = draw_one(match)
  if not card then return false, "draw_pile_empty" end

  local hand = match.hands[pid]
  hand[#hand + 1] = card
  sort_hand(hand)
  play_sfx(pid, "choose")

  if is_playable(match, pid, card) then
    match.phase = "drawn_choice"
    match.pending_draw_pid = pid
    match.pending_draw_card_id = card.id
    local view = VIEWS[pid]
    if view then
      view.cursor_mode = "hand"
      view.hand_slide_target = 0
      view.hand_index = find_card_index(hand, card.id) or 1
    end
    redraw_all(match)
    return true
  end

  local actor_index = player_index(match, pid)
  complete_turn(match, actor_index, 1)
  return true
end

local function keep_drawn_card(match, pid)
  if not match or match.phase ~= "drawn_choice" or match.pending_draw_pid ~= pid then return false end
  match.notice = ""
  local actor_index = player_index(match, pid)
  play_sfx(pid, "cancel")
  complete_turn(match, actor_index, 1)
  return true
end

local function cancel_color_select(match, pid)
  if not match or match.phase ~= "color_select" or match.pending_wild_pid ~= pid then return false end
  local return_phase = match.pending_wild_return_phase or "turn"
  match.phase = return_phase
  match.pending_wild_pid = nil
  match.pending_wild_card_id = nil
  match.pending_wild_return_phase = nil

  local view = VIEWS[pid]
  if view then
    view.cursor_mode = "hand"
    view.hand_slide_target = 0
    if return_phase == "drawn_choice" and match.pending_draw_card_id then
      view.hand_index = find_card_index(match.hands[pid], match.pending_draw_card_id) or view.hand_index
    end
  end
  play_sfx(pid, "cancel")
  redraw_all(match)
  return true
end

local function open_view(pid, match)
  if VIEWS[pid] then cleanup_view(pid, false) end

  local ids = view_ids(pid)
  local view = {
    match_id = match.id,
    ids = ids,

    -- The lobby host's Confirm press is what launched the match.
    -- Ignore UNO input until that button is released.
    start_input_blocked = match.start_input_pid == pid,

    hand_index = 1,
    cursor_mode = "hand",
    color_index = 1,
    hand_slide_y = 0,
    hand_slide_target = 0,
    max_hand_drawn = 0,
    max_opp_drawn = { 0, 0, 0 },
    menu_open = false,
  }
  VIEWS[pid] = view

  if Net and Net.lock_player_input then pcall(Net.lock_player_input, pid) end
  alloc_sprite(pid, ids.table_sprite, CFG.TABLE_TEX, CFG.TABLE_ANIM, CFG.TABLE_STATE)
  alloc_sprite(pid, ids.card_sprite, CFG.CARD_TEX, CFG.CARD_ANIM, CFG.CARD_BACK_STATE)
  alloc_sprite(pid, ids.cursor_sprite, CFG.CURSOR_TEX, CFG.CURSOR_ANIM, CFG.CURSOR_STATE)

  draw_sprite(pid, ids.table_sprite, ids.table_obj,
    CFG.TABLE_X, CFG.TABLE_Y, CFG.TABLE_SX, CFG.TABLE_SY, CFG.Z.table, CFG.TABLE_STATE)
  play_sfx(pid, "screen_open")
  redraw_view(pid)
end

close_match = function(match)
  if not match or not MATCHES[match.id] then return end
  match.close_token = (match.close_token or 0) + 1

  local players = {}
  for _, pid in ipairs(match.players) do players[#players + 1] = pid end
  for _, pid in ipairs(players) do
    MATCH_BY_PID[pid] = nil
    cleanup_view(pid, true)
  end
  MATCHES[match.id] = nil
  dlog("closed match", match.id)
end

function UNO.forfeit(pid, reason)
  local match = match_for_pid(pid)
  if not match then return false end
  if match.phase == "round_over" then return false end

  local leaving_index = player_index(match, pid)
  if not leaving_index then return false end
  local was_current = current_pid(match) == pid
  local name = short_name(pid, 12)

  for _, card in ipairs(match.hands[pid] or {}) do
    match.draw_pile[#match.draw_pile + 1] = card
  end
  shuffle(match.draw_pile)
  match.hands[pid] = nil

  table.remove(match.players, leaving_index)
  MATCH_BY_PID[pid] = nil
  cleanup_view(pid, reason ~= "disconnect")

  if #match.players <= 1 then
    local winner = match.players[1]
    if winner then
      finish_match(match, winner, name .. " forfeited.")
    else
      MATCHES[match.id] = nil
    end
    return true
  end

  if match.pending_draw_pid == pid or match.pending_wild_pid == pid then
    match.phase = "turn"
    match.pending_draw_pid = nil
    match.pending_draw_card_id = nil
    match.pending_wild_pid = nil
    match.pending_wild_card_id = nil
    match.pending_wild_return_phase = nil
  end

  if leaving_index < match.turn_index then
    match.turn_index = match.turn_index - 1
  elseif was_current then
    -- The next player shifted into the removed player's old index.
    if leaving_index > #match.players then leaving_index = 1 end
    match.turn_index = leaving_index
  elseif match.turn_index > #match.players then
    match.turn_index = 1
  end

  match.notice = name .. " forfeited."
  reset_views_for_turn(match)
  redraw_all(match)
  return true
end

local function close_pause_menu(pid)
  local view = VIEWS[pid]
  if view then view.menu_open = false end
  if MenuAPIOK and MenuAPI and type(MenuAPI.close_all) == "function" then
    pcall(MenuAPI.close_all, pid, { keep_frozen = true, reason = "uno_resume" })
  end
  if VIEWS[pid] then redraw_view(pid) end
end

local function open_forfeit_confirm(pid)
  if not (MenuAPIOK and MenuAPI and type(MenuAPI.push) == "function") then return false end

  return MenuAPI.push(pid, {
    type = 4,
    title = "Forfeit?",
    color = "red",
    x = 49,
    y = 54,
    z = 290,
    open_sfx = false,
    cancel_sfx = "cancel",
    lock_input = false,
    lines = {
      "Leave this UNO match?",
      "You will forfeit.",
    },
    default_choice = "no",
    yes_text = "Yes",
    no_text = "No",
    on_confirm = function(player_id, row)
      local choice = row and row.choice or "no"
      if choice ~= "yes" then
        MenuAPI.close(player_id, { keep_frozen = true, reason = "uno_forfeit_no" })
        return true
      end

      MenuAPI.close_all(player_id, { keep_frozen = true, reason = "uno_forfeit_yes" })
      local view = VIEWS[player_id]
      if view then view.menu_open = false end
      UNO.forfeit(player_id, "forfeit")
      return true
    end,
  })
end

local function open_pause_menu(pid)
  local view = VIEWS[pid]
  if not view or view.menu_open then return false end
  if not (MenuAPIOK and MenuAPI and type(MenuAPI.push) == "function") then
    play_sfx(pid, "error")
    set_local_notice(pid, "Pause menu unavailable.")
    return false
  end

  view.menu_open = true
  erase_obj(pid, view.ids.cursor_obj)

  local ok = MenuAPI.push(pid, {
    type = 3,
    title = "UNO",
    color = "red",
    x = 49,
    y = 54,
    z = 280,
    open_sfx = "screen_open",
    cancel_sfx = "cancel",
    lock_input = false,
    rows = {
      { id = "resume", text = "Resume" },
      { id = "forfeit", text = "Forfeit" },
    },
    on_confirm = function(player_id, row)
      if row and row.id == "forfeit" then
        open_forfeit_confirm(player_id)
        return true
      end
      close_pause_menu(player_id)
      return true
    end,
    on_close = function(player_id)
      local current_view = VIEWS[player_id]
      if current_view and (not MenuAPI.is_open or not MenuAPI.is_open(player_id)) then
        current_view.menu_open = false
        redraw_view(player_id)
      end
    end,
  })

  if not ok then
    view.menu_open = false
    redraw_view(pid)
    return false
  end
  return true
end

local function validate_players(players)
  if type(players) ~= "table" then return false, "missing_players" end
  if #players < 2 or #players > CFG.MAX_PLAYERS then return false, "player_count" end

  local seen = {}
  for _, pid in ipairs(players) do
    if not pid or seen[pid] or MATCH_BY_PID[pid] then return false, "invalid_player" end
    seen[pid] = true
  end
  return true
end

local function draw_initial_discard(match)
  local attempts = #match.draw_pile
  while attempts > 0 do
    local card = draw_one(match)
    if not card then return nil end
    if card.kind ~= "wild4" then
      match.discard[#match.discard + 1] = card
      return card
    end
    match.draw_pile[#match.draw_pile + 1] = card
    shuffle(match.draw_pile)
    attempts = attempts - 1
  end
  return nil
end

local function apply_initial_card(match, card)
  match.current_color = card.color
  if card.kind == "wild" then
    match.current_color = COLOR_ORDER[math.random(#COLOR_ORDER)]
  elseif card.kind == "skip" then
    match.turn_index = next_index(match, match.turn_index, 1)
  elseif card.kind == "reverse" then
    if #match.players == 2 then
      match.turn_index = next_index(match, match.turn_index, 1)
    else
      match.direction = -1
    end
  elseif card.kind == "draw2" then
    local target_pid = current_pid(match)
    draw_cards(match, target_pid, 2)
    match.notice = short_name(target_pid, 10) .. " drew 2."
    match.turn_index = next_index(match, match.turn_index, 1)
  end
end

function UNO.start_match(players, opts)
  local valid, err = validate_players(players)
  if not valid then
    dlog("start rejected:", err)
    return false
  end

  -- Normally these were already provided when each player touched the
  -- table, but keep this fallback for matches started another way.
  for _, pid in ipairs(players) do
    provide_uno_assets(pid)
  end

  match_sequence = match_sequence + 1
  local match_id = (opts and opts.match_id) or ("uno:" .. tostring(match_sequence))
  local match = {
    id = match_id,
    start_input_pid = opts and opts.start_input_pid or nil,

    players = {},
    hands = {},
    draw_pile = build_deck(),
    discard = {},
    direction = 1,
    turn_index = math.random(#players),
    current_color = nil,
    phase = "turn",
    notice = "",
    close_token = 0,
  }

  for _, pid in ipairs(players) do
    match.players[#match.players + 1] = pid
    match.hands[pid] = {}
  end

  -- Deal one card to each player per pass.
  for _ = 1, CFG.STARTING_HAND do
    for _, pid in ipairs(match.players) do
      local card = draw_one(match)
      if not card then return false end
      match.hands[pid][#match.hands[pid] + 1] = card
    end
  end
  for _, pid in ipairs(match.players) do sort_hand(match.hands[pid]) end

  local first_card = draw_initial_discard(match)
  if not first_card then return false end
  apply_initial_card(match, first_card)

  MATCHES[match.id] = match
  for _, pid in ipairs(match.players) do MATCH_BY_PID[pid] = match.id end
  for _, pid in ipairs(match.players) do open_view(pid, match) end
  redraw_all(match)

  dlog("started", match.id, "players=", #match.players, "first=", first_card.state)
  return true
end

local function play_selected(pid)
  local match = match_for_pid(pid)
  local view = VIEWS[pid]
  if not (match and view) then return end
  if current_pid(match) ~= pid then play_sfx(pid, "error"); return end

  local card = selected_card_for_view(match, pid, view)
  if not card then play_sfx(pid, "error"); return end
  local ok, reason = commit_play(match, pid, card.id, nil)
  if not ok then
    play_sfx(pid, "error")

    if reason == "not_playable" then
      set_local_notice(pid, "That card cannot be played.")
    end
  end
end

local function choose_color(pid)
  local match = match_for_pid(pid)
  local view = VIEWS[pid]
  if not (match and view) then return end
  if match.phase ~= "color_select" or match.pending_wild_pid ~= pid then return end
  local color = COLOR_ORDER[view.color_index]
  commit_play(match, pid, match.pending_wild_card_id, color)
end

local function move_hand_cursor(pid, delta)
  local match = match_for_pid(pid)
  local view = VIEWS[pid]
  if not (match and view) then return end
  local hand = match.hands[pid] or {}
  if #hand == 0 then return end

  if match.phase == "drawn_choice" and match.pending_draw_pid == pid then
    play_sfx(pid, "error")
    return
  end

  view.hand_index = ((view.hand_index - 1 + delta) % #hand) + 1
  play_sfx(pid, "choose")
  redraw_view(pid)
end

local function move_color_cursor(pid, delta)
  local match = match_for_pid(pid)
  local view = VIEWS[pid]
  if not (match and view) then return end
  view.color_index = ((view.color_index - 1 + delta) % 4) + 1
  play_sfx(pid, "choose")
  redraw_view(pid)
end

local function is_left(name)
  return name == "Move Left" or name == "Left"
end
local function is_right(name)
  return name == "Move Right" or name == "Right"
end
local function is_up(name)
  return name == "Move Up" or name == "Up"
end
local function is_down(name)
  return name == "Move Down" or name == "Down"
end
local function is_confirm(name)
  return name == "Confirm" or name == "OK"
end
local function is_cancel(name)
  return name == "Cancel" or name == "Back"
end

local function handle_input(pid, name)
  local match = match_for_pid(pid)
  local view = VIEWS[pid]
  if not (match and view) then return end

  if view.menu_open
    or (
      MenuAPIOK
      and MenuAPI
      and MenuAPI.is_open
      and MenuAPI.is_open(pid)
    )
  then
    return
  end

  if match.phase == "round_over" then
    return
  end

  -- The affected player's decision is handled entirely by menuAPI.
  if match.phase == "wild4_challenge" then
    return
  end

  -- Any new input dismisses the previous private error.
  view.local_notice = nil

  if match.phase == "color_select"
    and match.pending_wild_pid == pid
  then
    if is_left(name) then
      move_color_cursor(pid, -1)
    elseif is_right(name) then
      move_color_cursor(pid, 1)
    elseif is_confirm(name) then
      choose_color(pid)
    elseif is_cancel(name) then
      cancel_color_select(match, pid)
    end

    return
  end

  if match.phase == "drawn_choice"
    and match.pending_draw_pid == pid
  then
    if is_confirm(name) then
      play_selected(pid)
    elseif is_cancel(name) then
      keep_drawn_card(match, pid)
    end

    return
  end

  -- Waiting players may only raise or lower their hand.
  -- Cancel remains available from the hand so they can forfeit.
  if current_pid(match) ~= pid then
    if is_up(name) and view.cursor_mode == "hand" then
      set_cursor_mode(pid, "draw_pile")
      play_sfx(pid, "choose")

    elseif (is_down(name) or is_cancel(name))
      and view.cursor_mode == "draw_pile"
    then
      set_cursor_mode(pid, "hand")
      play_sfx(pid, "cancel")

    elseif is_cancel(name) then
      open_pause_menu(pid)
    end

    return
  end

  if is_left(name) and view.cursor_mode == "hand" then
    move_hand_cursor(pid, -1)

  elseif is_right(name) and view.cursor_mode == "hand" then
    move_hand_cursor(pid, 1)

  elseif is_up(name) and view.cursor_mode == "hand" then
    set_cursor_mode(pid, "draw_pile")
    play_sfx(pid, "choose")

  elseif is_down(name) and view.cursor_mode == "draw_pile" then
    set_cursor_mode(pid, "hand")
    play_sfx(pid, "choose")

  elseif is_confirm(name) then
    if view.cursor_mode == "draw_pile" then
      local ok = draw_for_turn(match, pid)

      if not ok then
        play_sfx(pid, "error")
        set_local_notice(pid, "You cannot draw right now.")
      end
    else
      play_selected(pid)
    end

  elseif is_cancel(name) then
    if view.cursor_mode == "draw_pile" then
      set_cursor_mode(pid, "hand")
      play_sfx(pid, "cancel")
    else
      open_pause_menu(pid)
    end
  end
end

-- Smoothly lower/raise the local hand when moving between the hand and table.
Net:on("tick", function()
  for pid, view in pairs(VIEWS) do
    local target = tonumber(view.hand_slide_target) or 0
    local current = tonumber(view.hand_slide_y) or 0
    if current ~= target then
      local step = 4
      if current < target then
        current = math.min(target, current + step)
      else
        current = math.max(target, current - step)
      end
      view.hand_slide_y = current
      redraw_view(pid)
    end
  end
end)

Net:on("virtual_input", function(event)
  if not event or not event.player_id or not event.events then
    return
  end

  local pid = event.player_id
  local view = VIEWS[pid]
  if not view then return end

  view.button_down = view.button_down or {}

  -- The host may still be holding the same Confirm button that started
  -- the match from the lobby. Do not let that input leak into UNO.
  if view.start_input_blocked then
    for _, button in next, event.events do
      if is_confirm(button.name) then
        local pressed = button.state == 0 or button.state == 1

        if not pressed then
          view.start_input_blocked = false
          view.button_down = {}
        end
      end
    end

    return
  end

  for _, button in next, event.events do
    local name = button.name
    local pressed = button.state == 0 or button.state == 1

    if pressed then
      if not view.button_down[name] then
        view.button_down[name] = true
        handle_input(pid, name)
      end
    else
      view.button_down[name] = false
    end
  end
end)

Net:on("object_interaction", function(event)
  if not event or event.button ~= 0 then return end
  local pid = event.player_id
  if not pid or VIEWS[pid] then return end

  local area_id = Net.get_player_area(pid)
  if not area_id then return end
  local ok, obj = pcall(Net.get_object_by_id, area_id, event.object_id)
  if not ok or not obj then return end

  local cp = obj.custom_properties or {}
  local is_uno_table = obj.class == CFG.TABLE_TYPE
    or obj.type == CFG.TABLE_TYPE
    or cp["UNO"] == true
    or tostring(cp["UNO"] or ""):lower() == "true"
  if not is_uno_table then return end

  -- Begin transferring the board, cards, and cursor while the player
  -- is still using the lobby.
  provide_uno_assets(pid)

  if LobbyOK and Lobby and type(Lobby.open_activity) == "function" then
    Lobby.open_activity(pid, CFG.ACTIVITY_ID)
  elseif Net and Net.message_player then
    Net.message_player(pid, "UNO lobby is unavailable.")
  end
end)

local function forfeit_event(event, reason)
  if event and event.player_id and MATCH_BY_PID[event.player_id] then
    UNO.forfeit(event.player_id, reason)
  end
end

Net:on("player_disconnect", function(event) forfeit_event(event, "disconnect") end)
Net:on("player_transfer", function(event) forfeit_event(event, "transfer") end)
Net:on("area_transfer", function(event) forfeit_event(event, "transfer") end)
Net:on("player_area_transfer", function(event) forfeit_event(event, "transfer") end)

if LobbyOK and Lobby and type(Lobby.register_activity) == "function" then
  Lobby.register_activity(CFG.ACTIVITY_ID, {
    max_players = CFG.MAX_PLAYERS,
    minimizable = false,
    start = function(players, lobby)
      local match_id = lobby and lobby.id and ("uno:" .. tostring(lobby.id)) or nil

      return UNO.start_match(players, {
        match_id = match_id,
        start_input_pid = lobby and lobby.owner_pid or nil,
      })
    end,
  })
else
  dlog("WARNING: lobby module unavailable; UNO tables cannot open matchmaking.")
end

UNO._config = CFG
UNO._matches = MATCHES
UNO._views = VIEWS
UNO.close_match = function(pid)
  local match = match_for_pid(pid)
  if match then close_match(match); return true end
  return false
end

print("[uno] UNO multiplayer loaded")
return UNO
