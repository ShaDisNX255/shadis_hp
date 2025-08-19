local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local helpers  = require('scripts/ezlibs-scripts/helpers')

local custom = {}
print("[cards] custom plugin loading...")

-- === YOUR SETUP ===
-- Dialog mug assets (used only for Net._message_player)
local MUG_DIR          = '/server/assets/cards/'
local GENERIC_MUG_ANIM = MUG_DIR .. 'card.animation'

-- Overworld summon assets (separate from mug)
-- Put per-card sheets here with the SAME base filename as the mug:
--   /server/assets/cards_ow/Gaia.png
--   /server/assets/cards_ow/Gaia.animation
-- Also include a fallback /server/assets/cards_ow/card.animation
local OW_DIR           = '/server/assets/cards_ow/'
local GENERIC_OW_ANIM  = OW_DIR .. 'card.animation'

-- Optional overrides: Board Title -> file base (no extension)
local CARD_ASSET_OVERRIDE = {
  -- ["[C]Kbo"] = "kuriboh",
}

-- Custom display names for summons (key by full title "[R]Gaia" or base "Gaia")
local SUMMON_NAME_OVERRIDE = {
    ["[UR]B.E.W.D."] = "Blue-Eyes White Dragon",
    ["[UR]B.L.S."] = "Black Luster Soldier",
    ["[C]B.Ox"] = "Battle Ox",
    ["[SR]BBlader"] = "Buster Blader",
    ["[UR]BChaos"] = "Magician of Black Chaos",
    ["[R]C.Dragon"] = "Curse of Dragon",
    ["C.Guard"] = "Celtic Guardian",
    ["DMGirl"] = "Dark Magician Girl",
    ["DMag"] = "Dark Magician",
    ["F.Imp"] = "Feral Imp",
    ["Gaia"] = "Gaia The Fierce Knight",
    ["H.M.Gnt"] = "Hitotsu-Me Giant",
    ["Jinzo"] = "Jinzo",
    ["JudgeM"] = "Judge Man",
    ["K.Dragon"] = "Koumori Dragon",
    ["Kbo"] = "Kuriboh",
    ["RKaise"] = "Rude Kaiser",
    ["RedEyesBD"] = "Red-Eyes Black Dragon",
    ["Saggi"] = "Saggi The Dark Clown",
    ["Swdstlk"] = "Swordstalker",
    ["V.Raider"] = "Vorse Raider",
}

-- Rarity sort order
local RARITY_ORDER = { C = 1, R = 2, SR = 3, UR = 4 }

-- === STATE ===
local player_using_card_bbs       = {}
local in_actions_menu             = {}
local pending_actions_menu        = {}
local last_viewed_card_by_player  = {}   -- [pid] = { name, png, anim, ow_png, ow_anim }
local summoned_bot_by_player      = {}   -- [pid] = bot_id
local open_list_after_close       = {}   -- [pid] = true → open Card List right after board_close

-- Actions
local ACTION_SUMMON       = "__card_action_summon__"
local ACTION_DISMISS      = "__card_action_dismiss__"
local ACTION_OPEN_LIST    = "__card_action_open_list__"
local ACTION_CLOSE        = "__card_action_close__"

local LIST_BOARD_COLOR    = { r=128, g=255, b=128 }
local ACTIONS_BOARD_COLOR = { r=255, g=230, b=120 }

-- ---------- helpers ----------
local function log(...) print('[cards]', table.unpack({...})) end
local function round16(x) return math.floor((x or 0) * 16 + 0.5) / 16 end

local function as_dir_string(d)
  if d == nil then return "" end
  d = tostring(d):lower()
  if d == "0" then return "up"
  elseif d == "1" then return "right"
  elseif d == "2" then return "down"
  elseif d == "3" then return "left" end
  return d
end

local function sort_key_from_title(title)
  title = tostring(title or "")
  -- grab tag between the first [...] if present
  local tag = title:match("^%[([A-Z]+)%]") or title:match("%[([A-Z]+)%]")
  if tag then tag = tag:upper() end
  local rank = RARITY_ORDER[tag] or 99
  -- base = everything after the first ']'
  local base = title:match("%](.*)") or title
  base = base:gsub("^%s+",""):gsub("%s+$","")
  return rank, base:lower(), base
end

local function guess_base_from_name(item_name)
  if CARD_ASSET_OVERRIDE[item_name] then
    local b = CARD_ASSET_OVERRIDE[item_name]
    log("override base for", item_name, "->", b)
    return b
  end
  local after = item_name:match("%](.*)")
  if after then
    after = after:gsub("^%s+",""):gsub("%s+$","")
    if after ~= "" then
      log("derived base (after ]) for", item_name, "->", after)
      return after
    end
  end
  local fallback = (item_name:gsub("[%[%]%s]+",""):gsub("[^%w_]","")):lower()
  log("fallback base for", item_name, "->", fallback)
  return fallback
end

-- Compute the display name for the summon:
local function get_summon_display_name(item_title)
  local base = item_title
  local after = item_title:match("%](.*)")
  if after then
    after = after:gsub("^%s+",""):gsub("%s+$","")
    if after ~= "" then base = after end
  end
  if base == item_title then base = (item_title:gsub("[%[%]]","")) end
  if SUMMON_NAME_OVERRIDE[item_title] then return SUMMON_NAME_OVERRIDE[item_title] end
  if SUMMON_NAME_OVERRIDE[base] then return SUMMON_NAME_OVERRIDE[base] end
  return base
end

-- Mug assets (dialog)
local function build_mug_paths_for_name(item_name)
  local base = guess_base_from_name(item_name)
  local png  = MUG_DIR .. base .. '.png'
  local anim = MUG_DIR .. base .. '.animation'
  if not (Net.has_asset and Net.has_asset(anim)) then anim = GENERIC_MUG_ANIM end
  log("[mug] using", "png="..tostring(png), "anim="..tostring(anim))
  return png, anim
end

-- Overworld assets (summon)
local function build_overworld_paths_for_name(item_name)
  local base = guess_base_from_name(item_name)
  local png  = OW_DIR .. base .. '.png'
  local anim = OW_DIR .. base .. '.animation'
  if not (Net.has_asset and Net.has_asset(anim)) then anim = GENERIC_OW_ANIM end
  log("[ow] using", "png="..tostring(png), "anim="..tostring(anim))
  return png, anim
end

-- engine dir → “front” offset of exactly 1 tile
local function dir_to_front_offset(dir)
  dir = as_dir_string(dir)
  if dir:find("up") or dir:find("north")   then return  0, -1 end
  if dir:find("down") or dir:find("south") then return  0,  1 end
  if dir:find("left") or dir:find("west")  then return -1,  0 end
  if dir:find("right") or dir:find("east") then return  1,  0 end
  return 0, -1
end

-- compute target “in front” of the player, snapped to 1/16, INCLUDING Z
local function compute_target_in_front(pid)
  local area_id = Net.get_player_area(pid)
  local pos     = Net.get_player_position(pid) or {x=0, y=0, z=0}
  local dir     = as_dir_string(Net.get_player_direction(pid))
  local px      = pos.x or pos[1] or 0
  local py      = pos.y or pos[2] or 0
  local pz      = pos.z or pos[3] or 0
  local dx, dy  = dir_to_front_offset(dir)
  local sx      = round16(px + dx)
  local sy      = round16(py + dy)
  local sz      = pz  -- keep same floor/z as player
  return area_id, sx, sy, sz
end

-- ---------- UI pieces ----------
local function show_card_dialog_with_mug(pid, item)
  local name = item and item.name or "(unknown)"
  local desc = item and item.description
  local text = (desc and #tostring(desc) > 0) and tostring(desc) or ("No description for: " .. name)

  local png, anim       = build_mug_paths_for_name(name)        -- mug for dialog
  local ow_png, ow_anim = build_overworld_paths_for_name(name)  -- overworld for summon

  -- keep both sets in memory
  last_viewed_card_by_player[pid] = {
    name = name, png = png, anim = anim,
    ow_png = ow_png, ow_anim = ow_anim
  }

  local ok, err = pcall(Net._message_player, pid, text, png, anim)  -- dialog uses the mug
  if ok then
    log("dialog (desc+mug) shown for", name)
  else
    log("dialog fallback (no mug):", tostring(err))
    Net.message_player(pid, text)
  end

  pending_actions_menu[pid] = true
  log("pending_actions_menu set for pid", pid)
end

local function open_actions_menu(pid, title)
  local posts = {}
  if summoned_bot_by_player[pid] then
    posts[#posts+1] = { id = ACTION_DISMISS,   read = true, title = "Dismiss" }
  else
    posts[#posts+1] = { id = ACTION_SUMMON,    read = true, title = "Summon" }
  end
  posts[#posts+1]   = { id = ACTION_OPEN_LIST, read = true, title = "Open Card List" }
  posts[#posts+1]   = { id = ACTION_CLOSE,     read = true, title = "Close" }

  in_actions_menu[pid] = true
  log("opening actions menu for pid", pid)
  Net.open_board(pid, title or "Card Options", ACTIONS_BOARD_COLOR, posts)
end

local function open_card_list(pid)
  local safe_secret   = helpers.get_safe_player_secret(pid)
  local player_memory = ezmemory.get_player_memory(safe_secret)
  local cards = {}

  for item_id, qty in pairs(player_memory.items) do
    local info = ezmemory.get_item_info(item_id)
    if info and info.name and string.find(info.name, "[", 1, true) ~= nil then
      cards[#cards+1] = { id = item_id, read = true, title = info.name }
    end
  end

  -- sort by rarity (C, R, SR, UR) then alphabetically by base name
  table.sort(cards, function(a, b)
    local ra, na_l = sort_key_from_title(a.title)
    local rb, nb_l = sort_key_from_title(b.title)
    if ra ~= rb then return ra < rb end
    if na_l ~= nb_l then return na_l < nb_l end
    -- final tie-breaker: raw title
    return tostring(a.title) < tostring(b.title)
  end)

  player_using_card_bbs[pid] = true
  in_actions_menu[pid] = false
  pending_actions_menu[pid] = false
  log("opening Card Collection for pid", pid, "count=", #cards)
  Net.open_board(pid, "Card Collection", LIST_BOARD_COLOR, cards)
end

local function spawn_card_npc_for_all(pid, info)
  local area, sx, sy, sz = compute_target_in_front(pid)
  local display_name = get_summon_display_name(info.name or "Card")
  log(("spawning card npc: %s at area=%s x=%.3f y=%.3f z=%s"):format(display_name, tostring(area), sx or -1, sy or -1, tostring(sz)))

  local ow_png  = info.ow_png or info.png    -- prefer OW assets, fall back to mug if missing
  local ow_anim = info.ow_anim or info.anim

  local ok, bot_id = pcall(Net.create_bot, {
    name               = display_name,
    area_id            = area,
    x = sx or 0, y = sy or 0, z = sz or 0,   -- <<<<< spawn on the player's Z
    texture_path       = ow_png,
    animation_path     = ow_anim,            -- overworld animation
    mug_animation_path = info.anim,          -- harmless hint for systems that read mugs on bots
    animation          = "IDLE",
  })
  if not ok or not bot_id then
    log("spawn failed:", tostring(bot_id))
    Net.message_player(pid, "Couldn't summon the card.")
    return nil
  end

  -- Force the visible name in case the engine decorates it
  pcall(Net.set_bot_name, bot_id, display_name)

  log("spawned bot_id", bot_id, "with name", display_name)
  return bot_id
end

-- ---------- events ----------
print("[cards] Loaded card collection menu (spawns IN FRONT on same Z; no follow; manual dismiss; custom summon names).")

-- Left Shoulder:
--  - If pending, open Card Options.
--  - Else if a summon exists, open Card Options.
--  - Else open Card List.
Net:on("tile_interaction", function(event)
  if event.button ~= 1 then return end -- Left Shoulder only
  local pid = event.player_id
  log("tile_interaction (Left Shoulder) pid", pid, "pending_actions_menu=", pending_actions_menu[pid], "has_summon=", summoned_bot_by_player[pid] ~= nil)

  if pending_actions_menu[pid] then
    pending_actions_menu[pid] = false
    open_actions_menu(pid, "Card Options")
    return
  end

  if summoned_bot_by_player[pid] then
    open_actions_menu(pid, "Card Options")
    return
  end

  open_card_list(pid)
end)

-- A on a board post
Net:on("post_selection", function(event)
  local pid = event.player_id
  log("post_selection pid", pid, "post_id", tostring(event.post_id), "in_actions=", in_actions_menu[pid], "in_main=", player_using_card_bbs[pid])

  if in_actions_menu[pid] then
    in_actions_menu[pid] = false
    local action = event.post_id
    log("actions menu selection:", action)

    if action == ACTION_SUMMON then
      local info = last_viewed_card_by_player[pid]
      if not info then Net.message_player(pid, "(View a card first.)"); return end
      if summoned_bot_by_player[pid] then
        log("replacing existing summon bot_id", summoned_bot_by_player[pid])
        pcall(Net.remove_bot, summoned_bot_by_player[pid])
      end
      local bot_id = spawn_card_npc_for_all(pid, info)
      if bot_id then
        summoned_bot_by_player[pid] = bot_id
        pending_actions_menu[pid] = true
        log("summoned; set pending_actions_menu for quick Dismiss/Open List")
      end
      return

    elseif action == ACTION_DISMISS then
      if summoned_bot_by_player[pid] then
        log("dismissing bot_id", summoned_bot_by_player[pid])
        pcall(Net.remove_bot, summoned_bot_by_player[pid])
        summoned_bot_by_player[pid] = nil
      end
      pending_actions_menu[pid] = true
      log("dismissed; set pending_actions_menu to reopen options")
      return

    elseif action == ACTION_OPEN_LIST then
      -- Auto-close Card Options, then open Card Collection as soon as it closes.
      open_list_after_close[pid] = true
      pcall(Net.close_bbs, pid)
      return

    elseif action == ACTION_CLOSE then
      log("closing BBS for pid", pid)
      pcall(Net.close_bbs, pid)
      player_using_card_bbs[pid] = false
      return
    end
  end

  if player_using_card_bbs[pid] == true then
    local item = ezmemory.get_item_info(event.post_id)
    log("main list selection ->", item and item.name or "(unknown)")
    show_card_dialog_with_mug(pid, item)
    return
  end

  log("post_selection fell through; no known context")
end)

Net:on("board_close", function(event)
  local pid = event.player_id
  log("board_close pid", pid)
  player_using_card_bbs[pid] = false
  in_actions_menu[pid] = false
  -- If we were asked to open the list after closing Card Options, do it now.
  if open_list_after_close[pid] then
    open_list_after_close[pid] = false
    open_card_list(pid)
  end
end)

-- Clean up on join/leave
Net:on("player_join", function(event)
  local pid = event.player_id
  log("player_join pid", pid)
  player_using_card_bbs[pid] = false
  in_actions_menu[pid] = false
  pending_actions_menu[pid] = false
  last_viewed_card_by_player[pid] = nil
  summoned_bot_by_player[pid] = nil
  open_list_after_close[pid] = false
end)

Net:on("player_disconnect", function(event)
  local pid = event.player_id
  log("player_disconnect pid", pid)
  if summoned_bot_by_player[pid] then
    log("auto-despawn bot_id", summoned_bot_by_player[pid])
    pcall(Net.remove_bot, summoned_bot_by_player[pid])
  end
  player_using_card_bbs[pid] = false
  in_actions_menu[pid] = false
  pending_actions_menu[pid] = false
  last_viewed_card_by_player[pid] = nil
  summoned_bot_by_player[pid] = nil
  open_list_after_close[pid] = false
end)

print("[cards] custom plugin ready"); return custom
