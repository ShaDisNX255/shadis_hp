local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local helpers  = require('scripts/ezlibs-scripts/helpers')

-- Cards live here now
local MUG_DIR            = '/server/assets/cards/'
local GENERIC_MUG_ANIM   = MUG_DIR .. 'card.animation'

-- Optional overrides: CARD NAME (as shown in the board) -> base filename (no extension)
-- Example: ["[C]Kbo"]="kuriboh" looks for kuriboh.png / kuriboh.animation
local CARD_ASSET_OVERRIDE = {
--    ["[C]Kbo"] = "kuriboh",
}

local player_using_card_bbs = {}
local custom = {}

-- --- helpers -------------------------------------------------------------

local function guess_base_from_name(item_name)
  -- 1) explicit override
  if CARD_ASSET_OVERRIDE[item_name] then return CARD_ASSET_OVERRIDE[item_name] end
  -- 2) text after ']' (e.g. "[C]Kbo" -> "Kbo");
  local after = item_name:match("%](.*)")
  if after then
    after = after:gsub("^%s+",""):gsub("%s+$","")
    if after ~= "" then return after end
  end
  -- 3) stripped fallback
  return (item_name:gsub("[%[%]%s]+",""):gsub("[^%w_]","")):lower()
end

local function build_mug_paths_for_name(item_name)
  local base = guess_base_from_name(item_name)
  local png  = MUG_DIR .. base .. '.png'
  -- Prefer per-card animation if present, otherwise generic card.animation
  local anim = MUG_DIR .. base .. '.animation'
  if not (Net.has_asset and Net.has_asset(anim)) then
    anim = GENERIC_MUG_ANIM
  end
  return png, anim
end

-- Show dialog with the card's DESCRIPTION as text, plus mug
local function show_card_dialog_with_mug(pid, item)
  local name = item and item.name or "(unknown)"
  local desc = item and item.description
  -- Fallback text if description is missing/empty
  local text = (desc and #tostring(desc) > 0) and tostring(desc) or ("No description for: " .. name)

  local png, anim = build_mug_paths_for_name(name)

  -- Use the working signature: strings only (text, mug_texture_path, mug_animation_path)
  local ok = pcall(Net._message_player, pid, text, png, anim)
  if not ok then
    Net.message_player(pid, text .. "\n(mug could not be shown)")
  end
end

-- --- UI flow -------------------------------------------------------------

print("[cards] Loaded card collection menu script.")

-- Shoulder button opens the card list
Net:on("tile_interaction", function(event)
  if event.button == 1 then
    local safe_secret   = helpers.get_safe_player_secret(event.player_id)
    local player_memory = ezmemory.get_player_memory(safe_secret)
    local cards = {}
    local board_color = { r=128, g=255, b=128 }

    for item_id, qty in pairs(player_memory.items) do
      local info = ezmemory.get_item_info(item_id)
      -- treat anything with "[" as a "card"
      if info and info.name and string.find(info.name, "[", 1, true) ~= nil then
        cards[#cards+1] = { id=item_id, read=true, title=info.name, author=tostring(qty) }
      end
    end

    player_using_card_bbs[event.player_id] = true
    Net.open_board(event.player_id, "Card Collection", board_color, cards)
  end
end)

-- Press A on a card: show its mug + DESCRIPTION
Net:on("post_selection", function(event)
  if not player_using_card_bbs[event.player_id] then return end
  local item = ezmemory.get_item_info(event.post_id)
  show_card_dialog_with_mug(event.player_id, item)
end)

Net:on("board_close", function(event)
  if player_using_card_bbs[event.player_id] then
    player_using_card_bbs[event.player_id] = false
  end
end)

Net:on("player_join", function(event)
  player_using_card_bbs[event.player_id] = false
end)

Net:on("player_disconnect", function(event)
  player_using_card_bbs[event.player_id] = false
end)

return custom
