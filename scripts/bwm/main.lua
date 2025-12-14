local whitelist_areas = {
  ["WCity1"] = true,
  ["WCity2"] = true,
  ["WCity3"] = true,
  ["Dungeon1"] = true,
}

---

Net:on("player_area_transfer", function(event)
  local current_area =  Net.get_player_area(event.player_id) 
  if whitelist_areas[current_area] then
    Net.set_mod_whitelist_for_player(event.player_id, '/server/assets/whitelist.txt')
  end
end)