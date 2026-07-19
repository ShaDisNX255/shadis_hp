--[[
* ----------------------------------------------------------------------- *
              Player Ranking and Matchmaking Script by OctoChris
     https://discord.com/channels/455429604455219211/1273290963099586671
	 	         https://github.com/indianajson/octo-ranking/
* ----------------------------------------------------------------------- *
]]--

--dependencies
local sha = require('scripts/octo-ranking/sha256')
local json = require('scripts/libs/json')
local FriendsOK, Friends = pcall(require, "scripts/ezlibs-custom/friends")
if not FriendsOK then
  Friends = nil
end

--defaults
local ranks_open  = {}
local ranks_wcity = {}
-- OctoPVP map property:
--   "true"  => WCityPVP (ranked-only, whitelisted)
--   anything else (false/blank/etc) => OpenPVP (ranked + unranked)
local area_is_wcity = {["default"] = false}

local player_challenges = {}
local battle_requests = {}
local battle_request_cooldowns = {}
local friend_requests = {}
local friend_request_cooldowns = {}
local actor_menu_target_by_pid = {}
local bbs_type = {}
local bbs_mode = {} -- "open" | "wcity"
local players_in_battle = {}
local timer = 0
local function find_in_table(t, v1)
    for i, v2 in pairs(t) do
        if v1 == v2 then
            return i
        end
    end
    return nil
end

local function unregister_tourney_queue_for_pvp(pid)
  if _G.Tournaments and _G.Tournaments.unregister_if_queued_for_battle then
    pcall(
      _G.Tournaments.unregister_if_queued_for_battle,
      pid,
      "You were unregistered from the tournament because you started PVP."
    )
  end
end

local function load_file(file_path, ranks)
  Async.read_file(file_path..".json").and_then(function(value)
    if value ~= "" then
      local decoded = json.decode(value)
      if type(decoded) == "table" then
        for k in pairs(ranks) do ranks[k] = nil end
        for k,v in pairs(decoded) do ranks[k] = v end
        print("[octo] Loaded ranks:", file_path)
      else
        print("[octo] Failed to decode ranks:", file_path)
      end
    else
      print("[octo] No ranks file:", file_path)
    end
  end)
end



local function save_file(file_path, ranks)
    local encoded = json.encode(ranks, true)
--	local json = json.encode(player_id_ranks)
--	table.sort(player_id_ranks,function(a,b)
--		return a.Points > b.Points
--	end)
	local csvdata = "Name,Rank,ELO,Total Games,Wins,Losses"
    for _, rank_data in pairs(ranks) do
      csvdata = csvdata.."\n"..rank_data.Name..","..rank_data.Rank..","..rank_data.Points..","..rank_data.Games..","..rank_data.Win..","..rank_data.Loss
    end

    Async.write_file(file_path..".json", encoded).and_then(function(value)
      if value then
        Async.write_file(file_path..".txt", csvdata)
      end
    end)
end

local function search_rankdata_based_on_name(Name, ranks)
    for player_id, rank_data in pairs(ranks) do
		if rank_data.Secret == Name then
			return player_id,rank_data
		end
	end
end

local function check_areas()
	local areas = Net.list_areas()
	for _, area_id in next, areas do
		area_id = tostring(area_id)
		local v = Net.get_area_custom_property(area_id, "OctoPVP")
		-- ONLY exact "true" enables WCityPVP. Everything else counts as OpenPVP.
		area_is_wcity[area_id] = (v == "true")
	end
end

local function get_area_mode(area_id)
	if area_is_wcity[tostring(area_id)] == true then
		return "wcity"
	end
	return "open"
end

--start Octo-Ranking
print("[octo] Starting Octo-Ranking")
load_file("scripts/octo-ranking/player_id_ranks_open",  ranks_open)
load_file("scripts/octo-ranking/player_id_ranks_wcity", ranks_wcity)
local players_in_open_unranked_matchmaking = {}
local players_in_open_ranked_matchmaking = {}
local players_in_wcity_ranked_matchmaking = {}

local function remove_from_pool(pool, pid)
	local idx = find_in_table(pool, pid)
	if idx ~= nil then
		table.remove(pool, idx)
	end
end

local function clear_player_matchmaking(pid)
	remove_from_pool(players_in_open_unranked_matchmaking, pid)
	remove_from_pool(players_in_open_ranked_matchmaking, pid)
	remove_from_pool(players_in_wcity_ranked_matchmaking, pid)
end

local function is_in_any_matchmaking(pid)
	return find_in_table(players_in_open_unranked_matchmaking, pid) ~= nil
		or find_in_table(players_in_open_ranked_matchmaking, pid) ~= nil
		or find_in_table(players_in_wcity_ranked_matchmaking, pid) ~= nil
end

check_areas()
local function find_nearest_rating_to(player_1_id, pool, ranks)
    local rank_data_1 = ranks[player_1_id]
	if not rank_data_1 or type(pool) ~= "table" then
		return 1
	end

	local target_index = 1
	local target_delta = nil

	for idx, player_2_id in ipairs(pool) do
		local rank_data_2 = ranks[player_2_id]
		if rank_data_2 then
			local delta = math.abs(rank_data_1.Points - rank_data_2.Points)
			if target_delta == nil or delta < target_delta then
				target_delta = delta
				target_index = idx
			end
		end
	end

	return target_index
end



-- ---------------------------------------------------------------------------
-- Ranked battle helpers (HP forced to 1000 + ELO update)
-- ---------------------------------------------------------------------------

local function apply_rank_thresholds(rank_data)
  local p = rank_data.Points or 0

  if p < 2500 then
    rank_data.Rank = "D-"
  end
  if p >= 2500 then
    rank_data.Rank = "D"
  end
  if p >= 5000 then
    rank_data.Rank = "D+"
  end
  if p >= 7500 then
    rank_data.Rank = "C-"
  end
  if p >= 10000 then
    rank_data.Rank = "C"
  end
  if p >= 12500 then
    rank_data.Rank = "C+"
  end
  if p >= 15000 then
    rank_data.Rank = "B-"
  end
  if p >= 17500 then
    rank_data.Rank = "B"
  end
  if p >= 20000 then
    rank_data.Rank = "B+"
  end
  if p >= 22500 then
    rank_data.Rank = "A-"
  end
  if p >= 25000 then
    rank_data.Rank = "A"
  end
  if p >= 27500 then
    rank_data.Rank = "A+"
  end
  if p >= 30000 then
    rank_data.Rank = "S-"
  end
  if p >= 32500 then
    rank_data.Rank = "S"
  end
  if p >= 35000 then
    rank_data.Rank = "S+"
  end
  if p >= 37500 then
    rank_data.Rank = "SS"
  end
  if p >= 40000 then
    rank_data.Rank = "U"
  end
  if p >= 42500 then
    rank_data.Rank = "W"
  end
  if p >= 45000 then
    rank_data.Rank = "X"
  end
  if p >= 47500 then
    rank_data.Rank = "Z"
  end
end

local function restore_hp(player_ids, states)
  for i, pid in ipairs(player_ids) do
    local st = states[i]
    if st and st.max then
      local hp = tonumber(st.hp) or tonumber(st.max) or 0
      local mx = tonumber(st.max) or 0
      if mx > 0 then
        hp = math.min(hp, mx)

        -- restore Net state
        pcall(Net.set_player_max_health, pid, mx)
        pcall(Net.set_player_health, pid, hp)

        -- if this area honors saved HP, also restore ezmemory so it can't snap back
        local area = Net.get_player_area(pid)
        local honor_saved = (Net.get_area_custom_property(area, "Honor Saved HP") == "true")
        if honor_saved and ezmemory and ezmemory.set_player_max_health and ezmemory.set_player_health then
          pcall(ezmemory.set_player_max_health, pid, mx, false)
          pcall(ezmemory.set_player_health, pid, hp)

          -- one more pass to ensure Net matches after ezmemory area logic runs
          pcall(Net.set_player_max_health, pid, mx)
          pcall(Net.set_player_health, pid, hp)
        end
      end
    end
  end
end

local function apply_ranked_result(player_ids, winner_index, hps, ranks)
  for i, pid in ipairs(player_ids) do
    local hp = hps[i]
    local rd = ranks[pid]
    if rd then
      rd.Name  = Net.get_player_name(pid)
      rd.Games = (rd.Games or 0) + 1
      if i == winner_index then
        rd.Win = (rd.Win or 0) + 1
      else
        rd.Loss = (rd.Loss or 0) + 1
      end

      rd.Points = math.ceil(((((rd.Win - rd.Loss) / rd.Games) * 0.5) + 0.5) * 50000)
      if rd.Points < 0 then
        rd.Points = 0
      elseif rd.Points > 50000 then
        rd.Points = 50000
      end

      apply_rank_thresholds(rd)
    end

    if hp then
      pcall(Net.set_player_max_health, pid, hp)
      pcall(Net.set_player_health, pid, hp)
    end
  end
end

local function start_ranked_battle(p1, p2, mode)
  local ranks = (mode == "wcity") and ranks_wcity or ranks_open
  local player_ids = { p1, p2 }

  for _, pid in ipairs(player_ids) do
    if Net.is_player_battling(pid) then
      return
    end
  end

  unregister_tourney_queue_for_pvp(p1)
  unregister_tourney_queue_for_pvp(p2)

  local hps = { Net.get_player_max_health(p1), Net.get_player_max_health(p2) }

  -- Force HP to 1000 for ranked
  for _, pid in ipairs(player_ids) do
    local mhp = 1000
    Net.set_player_max_health(pid, mhp)
    Net.set_player_health(pid, mhp)
  end

  players_in_battle[p1] = p2
  players_in_battle[p2] = p1

  Async.initiate_pvp(p1, p2).and_then(function(value)
    -- If either player quit, don't affect ELO; just restore HP.
    if value and value.ran then
      restore_hp(player_ids, hps)
      -- No ELO change
      return
    end

    local winner_index = 2
    if value and value.health and value.health > 0 then
      winner_index = 1
    end

    apply_ranked_result(player_ids, winner_index, hps, ranks)
    save_file((mode == "wcity") and "scripts/octo-ranking/player_id_ranks_wcity"
                       or  "scripts/octo-ranking/player_id_ranks_open", ranks)
  end)
end

-- ---------------------------------------------------------------------------
-- Lobby integration (OpenPVP only)
-- ---------------------------------------------------------------------------
local Lobby
do
  local ok, mod = pcall(require, "scripts/ezlibs-custom/lobby")
  if ok then Lobby = mod end
end

if Lobby and Lobby.register_activity then
  -- OpenPVP Unranked
  Lobby.register_activity("bn_openpvp_unranked", {
    max_players = 2,
    minimizable = true,
    start = function(players)
      local p1, p2 = players[1], players[2]
      if Net.is_player_battling(p1) or Net.is_player_battling(p2) then return false end
      unregister_tourney_queue_for_pvp(p1)
      unregister_tourney_queue_for_pvp(p2)
      Net.initiate_pvp(p1, p2)
      players_in_battle[p1] = p2
      players_in_battle[p2] = p1
      return true
    end
  })

  -- OpenPVP Ranked
  Lobby.register_activity("bn_openpvp_ranked", {
    max_players = 2,
    minimizable = true,

    -- pick closest ELO among candidates (optional but nice)
    pick_random_partner = function(pid, candidates)
      local r1 = (ranks_open[pid] and ranks_open[pid].Points) or 25000
      local best, best_diff = candidates[1], math.huge
      for _, other in ipairs(candidates) do
        local r2 = (ranks_open[other] and ranks_open[other].Points) or 25000
        local d = math.abs(r2 - r1)
        if d < best_diff then
          best, best_diff = other, d
        end
      end
      return best
    end,

    start = function(players)
      local p1, p2 = players[1], players[2]
      if Net.is_player_battling(p1) or Net.is_player_battling(p2) then return false end
      start_ranked_battle(p1, p2, "open")
      return true
    end
  })
end

-- ---------------------------------------------------------------------------
-- Menu open helpers (used by PVP Board and by LMenu OpenPVP button)
-- ---------------------------------------------------------------------------

local function open_matchmaking_menu(pid, mode)
  if mode ~= "wcity" then
    mode = "open"
  end

  bbs_type[pid] = "ServerMenu"
  bbs_mode[pid] = mode

  local ranks = (mode == "wcity") and ranks_wcity or ranks_open
  local rank_data = ranks[pid]
  if not rank_data then
    return
  end

  local ranked_title = "Rank Battle: " .. (rank_data.Rank) .. "/" .. (rank_data.Points)
  if (rank_data.Games or 0) < 5 then
    ranked_title = "Rank Battle: " .. (rank_data.Games) .. "/5 Games"
  end

  local server_menu = {}

  if mode == "open" then
    server_menu[#server_menu + 1] = { id = "Unranked", read = true, title = "Free Battle", author = "" }
  end

  server_menu[#server_menu + 1] = { id = "Ranked", read = true, title = ranked_title, author = "" }
  server_menu[#server_menu + 1] = { id = "Leaderboard", read = true, title = "View Leaderboard", author = "" }
  server_menu[#server_menu + 1] = { id = "About Ranking", read = true, title = "About Ranking", author = "" }

  player_challenges[pid] = nil
  clear_player_matchmaking(pid)

  local title = (mode == "wcity") and "WCity PVP" or "Open PVP"
  Net.open_board(pid, title, { r = 127, g = 127, b = 127 }, server_menu)
end

local function get_menuapi()
  local MenuAPI = rawget(_G, "MenuAPI")

  if not (MenuAPI and type(MenuAPI.open) == "function") then
    local ok, mod = pcall(require, "scripts/menuAPI/main")
    if ok and type(mod) == "table" then
      MenuAPI = mod
    end
  end

  return MenuAPI
end

local function unlock_player_after_lmenu(pid)
  if Net and Net.unlock_player_input then
    pcall(Net.unlock_player_input, pid)
  end
end

local function openpvp_rank_right(rank_data)
  if not rank_data then
    return "?"
  end

  if (tonumber(rank_data.Games) or 0) < 5 then
    return tostring(tonumber(rank_data.Games) or 0) .. "/5"
  end

  return tostring(rank_data.Rank or "?") .. "/" .. tostring(rank_data.Points or 0)
end

local function build_openpvp_menuapi_rows(pid)
  local rank_data = ranks_open[pid]
  local rank_right = openpvp_rank_right(rank_data)

  return {
    { id = "Unranked", text = "Free Battle", show_right = false },
    { id = "Ranked", text = "Rank Battle", right = rank_right },
    { id = "Leaderboard", text = "View Leaderboard", show_right = false },
    { id = "About Ranking", text = "About Ranking", show_right = false },
  }
end

local function open_openpvp_about_menuapi(pid, opts)
  opts = opts or {}

  local text =
    "OpenPVP lets you use Ranked or Free Battle matchmaking. " ..
    "Ranked forces both players to 1000 HP and affects your ELO rank. " ..
    "If either player quits, ELO is unchanged. " ..
    "Free Battle uses normal HP and does not affect ELO. Have fun!"

  local MenuAPI = get_menuapi()

  if MenuAPI and type(MenuAPI.show_message) == "function" then
    local ok = MenuAPI.show_message(pid, text, {
      box_id = "openpvp_about",
      speed = 80,
    })

    if ok then
      return true
    end
  end

  Net.message_player(pid, text)
  return true
end

local function open_openpvp_leaderboard_board(pid)
  local MenuAPI = get_menuapi()
  if MenuAPI and type(MenuAPI.close) == "function" then
    MenuAPI.close(pid, { keep_frozen = true, reason = "pvp_leaderboard" })
  end

  unlock_player_after_lmenu(pid)

  local leaderboard = {}

  for _, rank_data in pairs(ranks_open) do
    if (tonumber(rank_data.Games) or 0) >= 5 then
      leaderboard[#leaderboard + 1] = rank_data
    end
  end

  table.sort(leaderboard, function(a, b)
    return (tonumber(a.Points) or 0) > (tonumber(b.Points) or 0)
  end)

  local posts = {}

  if #leaderboard == 0 then
    posts[#posts + 1] = {
      id = "none",
      read = true,
      title = "No ranked players yet.",
      author = "",
    }
  else
    for i, rank_data in ipairs(leaderboard) do
      posts[#posts + 1] = {
        id = tostring(i),
        read = true,
        title = tostring(i) .. ". " .. tostring(rank_data.Name or "Player") .. " " .. tostring(rank_data.Rank or "?") .. "/" .. tostring(rank_data.Points or 0),
        author = "",
      }
    end
  end

  bbs_type[pid] = "Leaderboard"
  bbs_mode[pid] = "open"

  Net.open_board(pid, "PVP Leaderboard", { r = 127, g = 127, b = 127 }, posts)
  return true
end

local function handle_openpvp_menuapi_confirm(pid, row, menu_state, opts)
  if type(row) ~= "table" then
    return true
  end

  opts = opts or {}

  local post_id = tostring(row.id or "")

  if post_id == "About Ranking" then
    open_openpvp_about_menuapi(pid, opts)
    return true
  end

  if post_id == "Leaderboard" then
    open_openpvp_leaderboard_board(pid)
    return true
  end

  if post_id == "Ranked" then
    if is_in_any_matchmaking(pid) then
      Net.message_player(pid, "Already in matchmaking.")
      return true
    end

    local MenuAPI = get_menuapi()
    if MenuAPI and type(MenuAPI.close) == "function" then
      MenuAPI.close(pid, { keep_frozen = true, reason = "pvp_ranked" })
    end

    unlock_player_after_lmenu(pid)

    if Lobby and Lobby.open_activity then
      Lobby.open_activity(pid, "bn_openpvp_ranked")
    else
      Net.message_player(pid, "OpenPVP lobby is not available.")
    end

    return true
  end

  if post_id == "Unranked" then
    local MenuAPI = get_menuapi()
    if MenuAPI and type(MenuAPI.close) == "function" then
      MenuAPI.close(pid, { keep_frozen = true, reason = "pvp_unranked" })
    end

    unlock_player_after_lmenu(pid)

    if Lobby and Lobby.open_activity then
      Lobby.open_activity(pid, "bn_openpvp_unranked")
    else
      Net.message_player(pid, "OpenPVP lobby is not available.")
    end

    return true
  end

  return true
end

-- ---------------------------------------------------------------------------
-- Actor interaction MenuAPI
-- ---------------------------------------------------------------------------

local open_actor_interaction_menuapi

local function short_name(name, max_ch)
  name = tostring(name or "Player")
  max_ch = tonumber(max_ch) or 16

  if #name <= max_ch then
    return name
  end

  if max_ch <= 3 then
    return name:sub(1, max_ch)
  end

  return name:sub(1, max_ch - 3) .. "..."
end

local function request_key(sender, target)
  return tostring(sender) .. ">" .. tostring(target)
end

local function request_key_involves_player(key, pid)
  local sender, target = tostring(key or ""):match("^([^>]+)>(.+)$")
  pid = tostring(pid)
  return sender == pid or target == pid
end

local function is_real_player(pid)
  return pid and Net and Net.is_player and Net.is_player(pid)
end

local function safe_player_secret(pid)
  if Friends and type(Friends.secret_for_player) == "function" then
    local ok, secret = pcall(Friends.secret_for_player, pid)
    if ok and secret and secret ~= "" then
      return tostring(secret)
    end
  end

  if pid and Net and Net.get_player_secret then
    local ok, secret = pcall(Net.get_player_secret, pid)
    if ok and secret and secret ~= "" then
      return tostring(secret)
    end
  end

  return nil
end

local function is_tour_active(pid)
  local sessions = rawget(_G, "__TOUR_SESSIONS__")
  local s = type(sessions) == "table" and sessions[pid] or nil
  return type(s) == "table" and s.active == true
end

local function close_menuapi(pid, reason)
  local MenuAPI = get_menuapi()
  if MenuAPI and type(MenuAPI.close) == "function" then
    MenuAPI.close(pid, { keep_frozen = false, reason = reason or "closed" })
  end
end

local function close_lmenu_before_request_popup(pid)
  local LMenu = rawget(_G, "LMenu")
  if not LMenu or type(LMenu.close) ~= "function" then
    return false
  end

  if type(LMenu.is_open_for) == "function" then
    local ok, is_open = pcall(LMenu.is_open_for, pid)
    if ok and not is_open then
      return false
    end
  end

  -- Important: keep_frozen=true prevents a brief unlock before the
  -- request popup takes over input.
  pcall(LMenu.close, pid, { keep_frozen = true })
  return true
end

local function refresh_actor_menu_if_open(pid, target_pid)
  if actor_menu_target_by_pid[pid] ~= target_pid then
    return
  end

  if not (is_real_player(pid) and is_real_player(target_pid)) then
    actor_menu_target_by_pid[pid] = nil
    return
  end

  if open_actor_interaction_menuapi then
    open_actor_interaction_menuapi(pid, target_pid, { open_sfx = false })
  end
end

local function start_actor_pvp(player_id, actor_id, mode)
  if not (is_real_player(player_id) and is_real_player(actor_id)) then
    return false
  end

  if Net.is_player_battling and (Net.is_player_battling(player_id) or Net.is_player_battling(actor_id)) then
    Net.message_player(player_id, "Battle is no longer available.")
    Net.message_player(actor_id, "Battle is no longer available.")
    return false
  end

  clear_player_matchmaking(player_id)
  clear_player_matchmaking(actor_id)

  if mode == "wcity" then
    start_ranked_battle(player_id, actor_id, mode)
  else
    unregister_tourney_queue_for_pvp(player_id)
    unregister_tourney_queue_for_pvp(actor_id)

    Net.initiate_pvp(player_id, actor_id)
    players_in_battle[player_id] = actor_id
    players_in_battle[actor_id] = player_id
  end

  return true
end

local function cleanup_requests_for_player(player_id)
  battle_requests[player_id] = nil
  battle_request_cooldowns[player_id] = nil
  friend_requests[player_id] = nil
  friend_request_cooldowns[player_id] = nil
  actor_menu_target_by_pid[player_id] = nil

  for sender, target in pairs(battle_requests) do
    if target == player_id then
      battle_requests[sender] = nil
    end
  end

  for sender, target in pairs(friend_requests) do
    if target == player_id then
      if Friends then
        local sender_secret = safe_player_secret(sender)

        if Friends.reject_request_by_secret and sender_secret then
          pcall(Friends.reject_request_by_secret, target, sender_secret)
        else
          pcall(Friends.reject_request, target, sender)
        end
      end

      friend_requests[sender] = nil
    end
  end

  for key in pairs(battle_request_cooldowns) do
    if request_key_involves_player(key, player_id) then
      battle_request_cooldowns[key] = nil
    end
  end

  for key in pairs(friend_request_cooldowns) do
    if request_key_involves_player(key, player_id) then
      friend_request_cooldowns[key] = nil
    end
  end
end

local function cooldown_battle_request(sender, target)
  local key = request_key(sender, target)
  battle_request_cooldowns[key] = true

  if Async and Async.sleep then
    Async.sleep(5).and_then(function()
      battle_request_cooldowns[key] = nil
      refresh_actor_menu_if_open(sender, target)
    end)
  else
    battle_request_cooldowns[key] = nil
  end
end

local function reject_battle_request(sender, target, reason)
  if battle_requests[sender] == target then
    battle_requests[sender] = nil
  end

  player_challenges[sender] = nil
  close_menuapi(target, reason or "battle_request_rejected")
  cooldown_battle_request(sender, target)
end

local function accept_battle_request(sender, target, mode)
  if battle_requests[sender] ~= target then
    close_menuapi(target, "battle_request_missing")
    return true
  end

  battle_requests[sender] = nil
  battle_request_cooldowns[request_key(sender, target)] = nil
  player_challenges[sender] = nil

  close_menuapi(target, "battle_request_accept")
  close_menuapi(sender, "battle_request_accept")

  actor_menu_target_by_pid[sender] = nil
  actor_menu_target_by_pid[target] = nil

  start_actor_pvp(target, sender, mode)
  return true
end

local function send_battle_request(sender, target, mode)
  if not (is_real_player(sender) and is_real_player(target)) then
    return true
  end

  local key = request_key(sender, target)
  if battle_requests[sender] == target or battle_request_cooldowns[key] then
    return true
  end

  if Net.is_player_battling and (Net.is_player_battling(sender) or Net.is_player_battling(target)) then
    Net.message_player(sender, "Battle is not available right now.")
    return true
  end

  battle_requests[sender] = target
  player_challenges[sender] = target

  clear_player_matchmaking(sender)

  local sender_name = short_name(Net.get_player_name(sender), 16)

  if Net.exclusive_player_emote then
    pcall(Net.exclusive_player_emote, target, sender, 7)
    pcall(Net.exclusive_player_emote, sender, sender, 7)
  end

  refresh_actor_menu_if_open(sender, target)

  local MenuAPI = get_menuapi()
  if not (MenuAPI and type(MenuAPI.open) == "function") then
    Net.message_player(target, sender_name .. " sent you a battle request.")
    return true
  end

  close_lmenu_before_request_popup(target)
  MenuAPI.open(target, {
    type = 4,
    title = "Battle Request",
    color = (mode == "wcity") and "red" or "purple",
    open_sfx = "screen_open",
    lock_input = true,

    lines = {
      sender_name .. " sent you",
      "a battle request.",
      "Accept?",
    },

    default_choice = "no",
    yes_text = "Yes",
    no_text = "No",

    on_confirm = function(target_pid, row)
      local choice = tostring(row and row.id or "no")

      if choice == "yes" then
        return accept_battle_request(sender, target_pid, mode)
      end

      reject_battle_request(sender, target_pid, "battle_request_no")
      return true
    end,

    on_cancel = function(target_pid)
      reject_battle_request(sender, target_pid, "battle_request_cancel")
      return true
    end,
  })

  return true
end

local function cooldown_friend_request(sender, target)
  local key = request_key(sender, target)
  friend_request_cooldowns[key] = true

  if Async and Async.sleep then
    Async.sleep(5).and_then(function()
      friend_request_cooldowns[key] = nil
      refresh_actor_menu_if_open(sender, target)
    end)
  else
    friend_request_cooldowns[key] = nil
  end
end

local function close_friend_request(sender, target, reason)
  if friend_requests[sender] == target then
    friend_requests[sender] = nil
  end

  close_menuapi(target, reason or "friend_request_closed")
  cooldown_friend_request(sender, target)
end

local function send_friend_request(sender, target)
  if not (is_real_player(sender) and is_real_player(target)) then
    return true
  end

  if not Friends then
    Net.message_player(sender, "Friend system is not available.")
    return true
  end

  local status = Friends.relationship_status(sender, target)

  if status == "self" then
    Net.message_player(sender, "You can't add yourself.")
    return true
  end

  if status == "friends" then
    Net.message_player(sender, "You're already friends.")
    return true
  end

  if status == "incoming" then
    local ok = Friends.accept_request(sender, target)

    if ok then
      Net.message_player(sender, "Friend added!")
      Net.message_player(target, Net.get_player_name(sender) .. " accepted your friend request.")
    else
      Net.message_player(sender, "Couldn't accept friend request.")
    end

    refresh_actor_menu_if_open(sender, target)
    refresh_actor_menu_if_open(target, sender)
    return true
  end

  local key = request_key(sender, target)

  if friend_requests[sender] == target or friend_request_cooldowns[key] then
    Net.message_player(sender, "Friend request already sent.")
    return true
  end

  local sender_secret = safe_player_secret(sender)
  local target_secret = safe_player_secret(target)
  local sender_name_full = Net.get_player_name(sender) or "Player"
  local sender_name = short_name(sender_name_full, 16)

  -- If a saved outgoing request exists but no live popup/cooldown exists,
  -- clear the stale saved request and create a fresh popup.
  if status == "outgoing" then
    if Friends.reject_request_by_secret and target_secret then
      pcall(Friends.reject_request_by_secret, sender, target_secret, {
        skip_refresh = true,
      })
    else
      pcall(Friends.reject_request, sender, target)
    end
  end

  local sent_ok = Friends.send_request(sender, target)
  if not sent_ok then
    Net.message_player(sender, "Couldn't send friend request.")
    return true
  end

  friend_requests[sender] = target

  if Net.exclusive_player_emote then
    pcall(Net.exclusive_player_emote, target, sender, 12)
    pcall(Net.exclusive_player_emote, sender, sender, 12)
  end

  refresh_actor_menu_if_open(sender, target)
  refresh_actor_menu_if_open(target, sender)

  local MenuAPI = get_menuapi()
  if not (MenuAPI and type(MenuAPI.open) == "function") then
    Net.message_player(target, sender_name .. " sent you a friend request.")
    return true
  end

  close_lmenu_before_request_popup(target)
  MenuAPI.open(target, {
    type = 4,
    title = "Friend Request",
    color = "green",
    open_sfx = "screen_open",
    lock_input = true,

    lines = {
      sender_name .. " sent you",
      "a friend request.",
      "Accept?",
    },

    default_choice = "no",
    yes_text = "Yes",
    no_text = "No",

    on_confirm = function(target_pid, row)
      local choice = tostring(row and row.id or "no")
      close_friend_request(sender, target_pid, "friend_request_answer")

      if choice == "yes" then
        local ok, err

        if Friends.accept_request_by_secret and sender_secret then
          ok, err = Friends.accept_request_by_secret(target_pid, sender_secret, sender_name_full)
        else
          ok, err = Friends.accept_request(target_pid, sender)
        end

        if ok then
          Net.message_player(target_pid, "Friend added!")

          if is_real_player(sender) then
            Net.message_player(sender, Net.get_player_name(target_pid) .. " accepted your friend request.")
          end
        else
          Net.message_player(target_pid, "Couldn't add friend.")
          print("[octo] friend accept failed:", tostring(err))
        end
      else
        if Friends.reject_request_by_secret and sender_secret then
          Friends.reject_request_by_secret(target_pid, sender_secret)
        else
          Friends.reject_request(target_pid, sender)
        end
      end

      refresh_actor_menu_if_open(sender, target_pid)
      refresh_actor_menu_if_open(target_pid, sender)

      return true
    end,

    on_cancel = function(target_pid)
      if Friends.reject_request_by_secret and sender_secret then
        Friends.reject_request_by_secret(target_pid, sender_secret)
      else
        Friends.reject_request(target_pid, sender)
      end

      close_friend_request(sender, target_pid, "friend_request_cancel")

      refresh_actor_menu_if_open(sender, target_pid)
      refresh_actor_menu_if_open(target_pid, sender)

      return true
    end,
  })

  return true
end

local function send_pat(sender, target)
  if not (is_real_player(sender) and is_real_player(target)) then
    return true
  end

  local sender_name = short_name(Net.get_player_name(sender), 16)
  local MenuAPI = get_menuapi()

  if MenuAPI and type(MenuAPI.show_message) == "function" then
    MenuAPI.show_message(target, sender_name .. " patted you.", {
      box_id = "pat_notice",
      modal = false,
      duration = 1.0,
      speed = 1000,
    })
  else
    Net.message_player(target, sender_name .. " patted you.")
  end

  close_menuapi(sender, "pat")
  actor_menu_target_by_pid[sender] = nil
  return true
end

local function build_actor_rows(player_id, actor_id)
  local battle_text = "Request Battle"
  local battle_selectable = true

  if battle_requests[actor_id] == player_id then
    battle_text = "Accept Battle"
  elseif battle_requests[player_id] == actor_id or battle_request_cooldowns[request_key(player_id, actor_id)] then
    battle_text = "Request Sent"
    battle_selectable = false
  end

  local friend_text = "Add Friend"
  local friend_selectable = true

  local friend_status = Friends and Friends.relationship_status(player_id, actor_id) or "none"

  if friend_status == "friends" then
    friend_text = "Friends"
    friend_selectable = false
  elseif friend_status == "incoming" then
    friend_text = "Accept Friend"
    friend_selectable = true
  elseif friend_requests[player_id] == actor_id
    or friend_request_cooldowns[request_key(player_id, actor_id)]
  then
    friend_text = "Friend Sent"
    friend_selectable = false
  elseif friend_status == "outgoing" then
    friend_text = "Send Again"
    friend_selectable = true
  end

  return {
    {
      id = "battle",
      text = battle_text,
      selectable = battle_selectable,
      enabled = battle_selectable,
      disabled_prefix = false,
    },
    {
      id = "friend",
      text = friend_text,
      selectable = friend_selectable,
      enabled = friend_selectable,
      disabled_prefix = false,
    },
    { id = "pat", text = "Pat", show_right = false },
    { id = "duel", text = "Request Duel", show_right = false },
  }
end

open_actor_interaction_menuapi = function(player_id, actor_id, opts)
  opts = opts or {}

  if not (is_real_player(player_id) and is_real_player(actor_id)) then
    return false
  end

  local MenuAPI = get_menuapi()
  if not (MenuAPI and type(MenuAPI.open) == "function") then
    Net.message_player(player_id, "(Player menu not available.)")
    return false
  end

  local player_area = Net.get_player_area(player_id)
  local mode = get_area_mode(player_area)

  if is_tour_active(player_id) then
    return false
  end

  if is_tour_active(actor_id) then
    local MenuAPI = get_menuapi()

    if MenuAPI and type(MenuAPI.show_message) == "function" then
      MenuAPI.show_message(player_id, "They're taking a tour right now.", {
        box_id = "tour_busy",
        modal = false,
        duration = 1.2,
        speed = 1000,
      })
    else
      Net.message_player(player_id, "They're taking a tour right now.")
    end

    return false
  end

  bbs_type[player_id] = nil
  bbs_mode[player_id] = mode
  actor_menu_target_by_pid[player_id] = actor_id

  return MenuAPI.open(player_id, {
    type = 3,
    title = short_name(Net.get_player_name(actor_id), 18),
    color = "purple",
    open_sfx = opts.open_sfx,

    rows = build_actor_rows(player_id, actor_id),

    on_confirm = function(pid, row)
      local id = tostring(row and row.id or "")

      if not is_real_player(actor_id) then
        close_menuapi(pid, "target_left")
        return true
      end

      if id == "battle" then
        if battle_requests[actor_id] == pid then
          return accept_battle_request(actor_id, pid, mode)
        end

        return send_battle_request(pid, actor_id, mode)
      end

      if id == "friend" then
        return send_friend_request(pid, actor_id)
      end

      if id == "pat" then
        return send_pat(pid, actor_id)
      end

      if id == "duel" then
        local MenuAPI2 = get_menuapi()
        if MenuAPI2 and type(MenuAPI2.show_message) == "function" then
          MenuAPI2.show_message(pid, "Duel requests are WIP.", {
            box_id = "duel_wip",
            speed = 80,
          })
        else
          Net.message_player(pid, "Duel requests are WIP.")
        end
        return true
      end

      return true
    end,

    on_close = function(pid)
      if actor_menu_target_by_pid[pid] == actor_id then
        actor_menu_target_by_pid[pid] = nil
      end
    end,
  })
end

-- Expose a tiny API so LMenu can open OpenPVP.
_G.OctoPVP = rawget(_G, "OctoPVP") or {}
_G.OctoPVP.open_openpvp_menuapi = function(pid, opts)
  opts = opts or {}

  local area = Net.get_player_area(pid)
  if get_area_mode(area) == "wcity" then
    Net.message_player(pid, "OpenPVP isn't available in this area.")
    unlock_player_after_lmenu(pid)
    return false
  end

  -- If player already has a minimized OpenPVP lobby session, restore it.
  if Lobby and Lobby.has_session and Lobby.open_activity then
    if Lobby.has_session(pid, "bn_openpvp_unranked") then
      unlock_player_after_lmenu(pid)
      Lobby.open_activity(pid, "bn_openpvp_unranked")
      return true
    end

    if Lobby.has_session(pid, "bn_openpvp_ranked") then
      unlock_player_after_lmenu(pid)
      Lobby.open_activity(pid, "bn_openpvp_ranked")
      return true
    end
  end

  local MenuAPI = get_menuapi()

  if not (MenuAPI and type(MenuAPI.open) == "function") then
    unlock_player_after_lmenu(pid)
    open_matchmaking_menu(pid, "open")
    return false
  end

  bbs_type[pid] = "ServerMenu"
  bbs_mode[pid] = "open"

  player_challenges[pid] = nil
  clear_player_matchmaking(pid)

  return MenuAPI.open(pid, {
    type = 3,
    title = opts.title or "Open PVP",
    color = opts.color or "purple",
    parent = opts.parent or "lmenu",
    bg_tint = { r = 172, g = 176, b = 184, color_mode = 2 },
    open_sfx = opts.open_sfx,

    -- LMenu already closed with keep_frozen = true.
    lock_input = opts.lock_input == true,

    show_right = true,
    right_max_ch = 8,

    rows = build_openpvp_menuapi_rows(pid),

    on_confirm = function(pid, selected_row, menu_state)
      return handle_openpvp_menuapi_confirm(pid, selected_row, menu_state, opts)
    end,
  })
end
_G.OctoPVP.open_openpvp_menu = function(pid)
  local area = Net.get_player_area(pid)
  if get_area_mode(area) == "wcity" then
    Net.message_player(pid, "OpenPVP isn't available in this area.")
    return
  end

  -- If player already has a minimizable OpenPVP lobby session (usually minimized), restore it
  if Lobby and Lobby.has_session and Lobby.open_activity then
    if Lobby.has_session(pid, "bn_openpvp_unranked") then
      Lobby.open_activity(pid, "bn_openpvp_unranked")
      return
    end
    if Lobby.has_session(pid, "bn_openpvp_ranked") then
      Lobby.open_activity(pid, "bn_openpvp_ranked")
      return
    end
  end

  -- otherwise show the old board menu (Free/Rank/Leaderboard/About)
  open_matchmaking_menu(pid, "open")
end

local function ensure_rank_entry(pid, ranks)
  local secret = sha.sha256(Net.get_player_secret(pid))

  if ranks[pid] == nil then
    local old_id, rank_data = search_rankdata_based_on_name(secret, ranks)
    if rank_data ~= nil then
      ranks[old_id] = nil
      ranks[pid] = rank_data
    else
      ranks[pid] = {Secret = secret, Name = Net.get_player_name(pid), Rank = "?", Points = 25000, Games = 0, Win = 0, Loss = 0}
    end
  else
    ranks[pid].Secret = secret
    ranks[pid].Name = Net.get_player_name(pid)
  end
end

Net:on("player_connect", function(event)
  local pid = event.player_id
  if not pid then return end

  -- Ensure entries exist/are updated in BOTH ladders
  ensure_rank_entry(pid, ranks_open)
  ensure_rank_entry(pid, ranks_wcity)

  -- Persist both ladders
  save_file("scripts/octo-ranking/player_id_ranks_open",  ranks_open)
  save_file("scripts/octo-ranking/player_id_ranks_wcity", ranks_wcity)
end)

Net:on("board_close", function(event)
	bbs_type[event.player_id] = nil
	bbs_mode[event.player_id] = nil
end)

Net:on("object_interaction", function(event)
	-- PVP Boards are for WCityPVP only (ranked-only, whitelisted areas).
	local pid = event.player_id
	local player_area = Net.get_player_area(pid)
	local object = Net.get_object_by_id(player_area, event.object_id)
	if not object or (object.class ~= "PVP Board" and object.type ~= "PVP Board") then
		return
	end

	if event.button ~= 0 then
		return
	end

	if get_area_mode(player_area) ~= "wcity" then
		return
	end

	open_matchmaking_menu(pid, "wcity")
end)

Net:on("actor_interaction", function(event)
  local player_id = event.player_id
  local actor_id = event.actor_id

  if event.button ~= 0 then
    return
  end

  if not Net.is_player(actor_id) then
    return
  end

  open_actor_interaction_menuapi(player_id, actor_id)
end)

Net:on("battle_results", function(event)
  --Taken from Keristero's pvp_with_stats.lua
  if players_in_battle[event.player_id] then
      players_in_battle[event.player_id] = nil
  end
  if player_challenges[event.player_id] then
	player_challenges[event.player_id] = nil
  end
end)

Net:on("player_disconnect", function(event)
  local player_id = event.player_id
  players_in_battle[player_id] = nil
  player_challenges[player_id] = nil
  clear_player_matchmaking(player_id)
  cleanup_requests_for_player(player_id)
end)

Net:on("player_area_transfer", function(event)
	local player_id = event.player_id
	local area = Net.get_player_area(player_id)
	local mode = get_area_mode(area)

  -- Area changes invalidate local challenges and request prompts.
  player_challenges[player_id] = nil
  cleanup_requests_for_player(player_id)

	-- Don't allow players to stay queued across WCity/Open boundaries
	if mode == "wcity" then
		remove_from_pool(players_in_open_unranked_matchmaking, player_id)
		remove_from_pool(players_in_open_ranked_matchmaking, player_id)
	else
		remove_from_pool(players_in_wcity_ranked_matchmaking, player_id)
	end
end)

Net:on("tick", function(event)
	--Taken from Keristero's pvp_with_stats.lua
    timer = timer + event.delta_time
    if timer > 5 then
        for player_id, value in pairs(players_in_battle) do
			if players_in_battle[player_id] ~= nil then 
            	Net.set_player_emote(player_id, 7) --swords emote
			end
        end  
        timer = 0
    end
end)

Net:on("post_selection", function(event)
	local player_id = event.player_id
	local post_id = event.post_id
	local mode = bbs_mode[player_id] or get_area_mode(Net.get_player_area(player_id))
	local ranks = (mode == "wcity") and ranks_wcity or ranks_open
	if bbs_type[player_id] ~= "ServerMenu" then return end
	if post_id == "About Ranking" then
		if mode == "wcity" then
			Net.message_player(player_id, "WCityPVP is ranked-only and uses the WCity whitelist. Ranked battles force both players to 1000 HP. Your ELO determines your rank and goes up on wins / down on losses. If either player quits a ranked battle, neither player's ELO is affected. Don't leave your matches if you can help it!")
		else
			Net.message_player(player_id, "OpenPVP is where you can matchmake with other players and battle without WCity restrictions. There are two rooms for matchmaking: Ranked and Free Battle. Ranked battles force both players to 1000 HP and affect your ELO rank. If either player quits a ranked battle, neither player's ELO is affected. Free Battle has no HP restriction. Have fun!")
		end
	elseif post_id == "RankedLocked" then
		Net.message_player(player_id, "Please set your nickname for Rank Battle. To do this, bring up the pause menu and choose Config.")
	elseif post_id == "Leaderboard" then
		pcall(function() Net.close_bbs(player_id) end)
		local post_index = 0
		local leaderboard = {}
		for player_id, rank_data in pairs(ranks) do
  		  if rank_data.Games >= 5 then
    		table.insert(leaderboard, rank_data)
  		  end
		end
		bbs_type[player_id] = "Leaderboard"
		local post_data_array = {}
		for n,rank_data in pairs(leaderboard) do
			post_index = post_index + 1
			local post_data = {}
			post_data.id = tostring(post_index)
			post_data.read = true
			post_data.title = post_index..". "..rank_data.Name.." "..rank_data.Rank.."/"..rank_data.Points
			post_data.author = ""
			table.insert(post_data_array,post_data)
		end
		Async.sleep(0.1).and_then(function(value)
			local emitter = Net.open_board(player_id,"PVP Leaderboard",{r = 127,g = 127,b = 127},post_data_array)
			emitter:on("post_request", function()
				if post_index < #leaderboard then
					post_index = post_index + 1
					local rank_data = leaderboard[post_index]
					local post_data = {{}}
					post_data[1].id = tostring(post_index)
					post_data[1].read = true
					post_data[1].title = post_index..". "..rank_data.Name.." "..rank_data.Rank.."/"..rank_data.Points
					post_data[1].author = ""
					Net.append_posts(player_id, post_data)
				end
			end)
		end)
    elseif post_id == "Ranked" and (not is_in_any_matchmaking(player_id)) then
		pcall(function() Net.close_bbs(player_id) end)

		-- OpenPVP uses Lobby system
		if mode == "open" and Lobby and Lobby.open_activity then
		  Lobby.open_activity(player_id, "bn_openpvp_ranked")
		  return
		end
		local pool = (mode == "wcity") and players_in_wcity_ranked_matchmaking or players_in_open_ranked_matchmaking
		local msg = (mode == "wcity") and "Started WCity ranked matchmaking... open WCity PVP to cancel." or "Started ranked matchmaking... open Open PVP to cancel."

		Async.message_player(player_id, msg).and_then(function()
			table.insert(pool, player_id)

			if #pool >= 2 then
				Async.sleep(4.9).and_then(function()
					if #pool < 2 then
						while #pool > 0 do
							local pid = table.remove(pool, 1)
							Net.message_player(pid, "No other players in matchmaking!")
						end
						return
					end

					local ranks = (mode == "wcity") and ranks_wcity or ranks_open

					local p1 = table.remove(pool, 1)
					local idx = find_nearest_rating_to(p1, pool, ranks)
					local p2 = table.remove(pool, idx)

					start_ranked_battle(p1, p2, mode)
				end)
			end
		end)
    elseif post_id == "Unranked" and mode == "open" then
      pcall(function() Net.close_bbs(player_id) end)

      if Lobby and Lobby.open_activity then
        Lobby.open_activity(player_id, "bn_openpvp_unranked")
      end
    end
end)
