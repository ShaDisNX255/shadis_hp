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

--defaults
local ranks_open  = {}
local ranks_wcity = {}
-- OctoPVP map property:
--   "true"  => WCityPVP (ranked-only, whitelisted)
--   anything else (false/blank/etc) => OpenPVP (ranked + unranked)
local area_is_wcity = {["default"] = false}

local player_challenges = {}
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

-- Expose a tiny API so LMenu can open OpenPVP.
_G.OctoPVP = rawget(_G, "OctoPVP") or {}
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

	local player_area = Net.get_player_area(player_id)
	local mode = get_area_mode(player_area) -- "wcity" or "open"

	bbs_type[player_id] = "ServerMenu"
	bbs_mode[player_id] = mode

	local name = Net.get_player_name(actor_id)
	local request_title = (mode == "wcity") and ("Request Ranked Battle: " .. name) or ("Request Battle: " .. name)
	local accept_title  = (mode == "wcity") and ("Accept Ranked Battle: " .. name) or ("Accept Battle: " .. name)

	local server_menu = {
		{ id = "Challenge1", read = true, title = request_title, author = "" },
		{ id = "Leaderboard", read = true, title = "View Leaderboard", author = "" },
		{ id = "About Ranking", read = true, title = "About Ranking", author = "" },
	}

	if player_challenges[actor_id] == player_id and player_challenges[player_id] ~= actor_id then
		server_menu[1] = { id = "Challenge2", read = true, title = accept_title, author = "" }
	end

	-- Reset your own state when opening the menu
	player_challenges[player_id] = nil
	clear_player_matchmaking(player_id)

	local emitter = Net.open_board(player_id, "Matchmaking Request", { r = 127, g = 127, b = 127 }, server_menu)
	emitter:on("post_selection", function(ev)
		if ev.post_id == "Challenge1" then
			player_challenges[player_id] = actor_id
			Net.exclusive_player_emote(actor_id, player_id, 7)
			Net.exclusive_player_emote(player_id, player_id, 7)
		elseif ev.post_id == "Challenge2" then
			player_challenges[actor_id] = nil
			if mode == "wcity" then
				start_ranked_battle(player_id, actor_id, mode)
			else
				Net.initiate_pvp(player_id, actor_id)
				players_in_battle[player_id] = actor_id
				players_in_battle[actor_id] = player_id
			end
		end
	end)
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
end)

Net:on("player_area_transfer", function(event)
	local player_id = event.player_id
	local area = Net.get_player_area(player_id)
	local mode = get_area_mode(area)

	-- Area changes invalidate local challenges
	player_challenges[player_id] = nil

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
