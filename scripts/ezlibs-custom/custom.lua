local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local helpers = require('scripts/ezlibs-scripts/helpers')
local player_using_card_bbs = {}

local custom = {}

print("[cards] Loaded card collection menu script.")
-- This script will show a BBS containing a player's card collection if they press Left Shoulder

Net:on("tile_interaction", function(event)
  if event.button == 1 then -- press Left Shoulder

    local safe_secret = helpers.get_safe_player_secret(event.player_id)
    local player_memory = ezmemory.get_player_memory(safe_secret)
    local cards = {}
    local board_color = { r= 128, g= 255, b= 128 }
    for item_id, quantity in pairs(player_memory.items) do
        local item_info = ezmemory.get_item_info(item_id)
        if string.find(item_info.name, "[", 1, true) ~= nil then --this ensures the item is a card
          cards[#cards+1] = { id=item_id, read=true, title=item_info.name, author=tostring(quantity) }
        end 
    end
    local bbs_name = "Card Collection"
    player_using_card_bbs[event.player_id] = true
    Net.open_board(event.player_id, bbs_name, board_color, cards)
  end 
 
end)

local function read_card_description(player_id,post_id)
    local item = ezmemory.get_item_info(post_id)
    Net.message_player(player_id, item.description) 
end 

Net:on("post_selection", function(event)
  -- checks if player is in a train menu
    if player_using_card_bbs[event.player_id] == true then
        --summons train based on train_name and chosen destination
        read_card_description(event.player_id,event.post_id)
    end
end)

Net:on("board_close", function(event)
    if player_using_card_bbs[event.player_id] == true then
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