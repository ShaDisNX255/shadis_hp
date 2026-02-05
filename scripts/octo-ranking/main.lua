--[[
Octo Ranking + Matchmaking (Open + WCity split)

- Open PVP: accessed via LMenu hook only (ranked + casual + leaderboard)
- WCity PVP: accessed via world "PVP Board" objects ONLY (ranked + casual + leaderboard)
- Direct challenges (actor_interaction): available everywhere; format is decided by
  where BOTH players are currently located (WCity only if both in same WCity area).
]]--

local sha  = require('scripts/octo-ranking/sha256')
local json = require('scripts/octo-ranking/json')

-- -------------------------
-- State
-- -------------------------

local ranks_open  = {}
local ranks_wcity = {}

-- Areas with OctoPVP = "true" are considered WCity format areas
local wcity_areas = { ["default"] = false }

-- active battles (player_id -> opponent_id)
local players_in_battle = {}

-- direct challenges (player_id -> { target=pid, format="open"|"wcity" })
local player_challenges = {}

-- which BBS menu is open (player_id -> "OpenMenu"|"WCityMenu")
local bbs_type = {}

-- matchmaking queues
local q_open_ranked    = {}
local q_open_unranked  = {}
local q_wcity_ranked   = {}
local q_wcity_unranked = {}

local timer = 0

-- -------------------------
-- Helpers
-- -------------------------

local function find_in_table(t, v)
  for i, x in pairs(t) do
    if x == v then return i end
  end
  return nil
end

local function is_wcity_area(area_id)
  return wcity_areas[tostring(area_id)] == true
end

local function format_for_pair(p1, p2)
  local a1 = Net.get_player_area(p1)
  local a2 = Net.get_player_area(p2)
  if a1 and a2 and a1 == a2 and is_wcity_area(a1) then
    return "wcity"
  end
  return "open"
end

local function rank_tbl(format)
  return (format == "wcity") and ranks_wcity or ranks_open
end

local function ranks_path(format)
  return (format == "wcity")
    and "scripts/octo-ranking/player_id_ranks_wcity"
    or  "scripts/octo-ranking/player_id_ranks_open"
end

local function load_ranks(file_path, out_tbl)
  Async.read_file(file_path .. ".json").and_then(function(value)
    if value == "" then
      print("[octo] No ranks file yet: " .. file_path)
      return
    end
    local decoded = json.decode(value)
    if not decoded then
      print("[octo] Failed to decode ranks file: " .. file_path)
      return
    end
    for k in pairs(out_tbl) do out_tbl[k] = nil end
    for k, v in pairs(decoded) do out_tbl[k] = v end
    print("[octo] Loaded ranks: " .. file_path)
  end)
end

local function save_ranks(file_path, tbl)
  local encoded = json.encode(tbl)

  local csvdata = "Name,Rank,ELO,Total Games,Wins,Losses"
  for _, rd in pairs(tbl) do
    csvdata = csvdata .. "\n"
      .. (rd.Name or "?") .. ","
      .. (rd.Rank or "?") .. ","
      .. tostring(rd.Points or 0) .. ","
      .. tostring(rd.Games or 0) .. ","
      .. tostring(rd.Win or 0) .. ","
      .. tostring(rd.Loss or 0)
  end

  Async.write_file(file_path .. ".json", encoded).and_then(function(ok)
    if ok then
      Async.write_file(file_path .. ".txt", csvdata)
    end
  end)
end

local function search_rankdata_based_on_secret(tbl, secret_hash)
  for player_id, rank_data in pairs(tbl) do
    if rank_data.Secret == secret_hash then
      return player_id, rank_data
    end
  end
end

local function ensure_rank_entry(tbl, player_id)
  local secret_hash = sha.sha256(Net.get_player_secret(player_id))
  local name = Net.get_player_name(player_id)

  if tbl[player_id] then
    tbl[player_id].Secret = secret_hash
    tbl[player_id].Name = name
    return
  end

  local old_id, old_rank = search_rankdata_based_on_secret(tbl, secret_hash)
  if old_rank then
    tbl[old_id] = nil
    tbl[player_id] = old_rank
    tbl[player_id].Secret = secret_hash
    tbl[player_id].Name = name
    return
  end

  tbl[player_id] = {
    Secret = secret_hash,
    Name   = name,
    Rank   = "?",
    Points = 25000,
    Games  = 0,
    Win    = 0,
    Loss   = 0
  }
end

local function check_areas()
  for _, area_id in next, Net.list_areas() do
    area_id = tostring(area_id)
    local prop = Net.get_area_custom_property(area_id, "OctoPVP")
    if prop == "true" then
      wcity_areas[area_id] = true
    elseif prop == "false" then
      wcity_areas[area_id] = false
    elseif prop ~= nil and prop ~= "" then
      print("[octo] Invalid OctoPVP value in " .. area_id .. ": " .. tostring(prop))
    end
  end
end

local function build_sorted_leaderboard(tbl, min_games)
  local arr = {}
  for _, rd in pairs(tbl) do
    if (rd.Games or 0) >= (min_games or 0) then
      arr[#arr + 1] = rd
    end
  end
  table.sort(arr, function(a, b)
    return (a.Points or 0) > (b.Points or 0)
  end)
  return arr
end

local function find_nearest_rating_to(queue, tbl, p1)
  local best_i = 1
  local best_d = nil
  local r1 = tbl[p1]
  for i, p2 in pairs(queue) do
    local r2 = tbl[p2]
    local d = math.abs((r1.Points or 0) - (r2.Points or 0))
    if best_d == nil or d < best_d then
      best_d = d
      best_i = i
    end
  end
  return best_i
end

local function snapshot_hp(pid)
  return { max = Net.get_player_max_health(pid), hp = Net.get_player_health(pid) }
end

local function restore_hp(pid, snap)
  if not snap then return end
  Net.set_player_max_health(pid, snap.max)
  Net.set_player_health(pid, math.min(snap.hp, snap.max))
end

local function remove_from_all_queues(pid)
  local i = find_in_table(q_open_ranked, pid);   if i then table.remove(q_open_ranked, i) end
  i = find_in_table(q_open_unranked, pid);       if i then table.remove(q_open_unranked, i) end
  i = find_in_table(q_wcity_ranked, pid);        if i then table.remove(q_wcity_ranked, i) end
  i = find_in_table(q_wcity_unranked, pid);      if i then table.remove(q_wcity_unranked, i) end
end

local function open_menu(pid, format)
  remove_from_all_queues(pid)
  player_challenges[pid] = nil

  local tbl = rank_tbl(format)
  ensure_rank_entry(tbl, pid)

  bbs_type[pid] = (format == "wcity") and "WCityMenu" or "OpenMenu"

  local ranked_title = "Rank Battle: " .. (tbl[pid].Rank) .. "/" .. (tbl[pid].Points)
  if (tbl[pid].Games or 0) < 5 then
    ranked_title = "Rank Battle: " .. tostring(tbl[pid].Games or 0) .. "/5 Games"
  end

  local posts = {
    { id = "Unranked", read = true, title = "Free Battle", author = "" },
    { id = "Ranked", read = true, title = ranked_title, author = "" },
    { id = "Leaderboard", read = true, title = "View Leaderboard", author = "" },
    { id = "About", read = true, title = "About PVP", author = "" },
  }

  local title = (format == "wcity") and "WCity PVP" or "Open PVP"
  Net.open_board(pid, title, { r = 127, g = 127, b = 127 }, posts)
end

-- -------------------------
-- LMenu Hook (Open only)
-- -------------------------

_G.OctoPVP = _G.OctoPVP or {}
_G.OctoPVP.open_open_pvp_menu = function(player_id)
  if not player_id or not Net.is_player(player_id) then return end
  open_menu(player_id, "open")
end

-- (extra alias in case your LMenu calls a different name)
_G.OctoPVP.open_menu_open = _G.OctoPVP.open_open_pvp_menu

-- Make Open PVP callable even if _G isn't shared across scripts
pcall(function()
  Net.__octo_pvp_loaded = true
  Net.__octo_open_open_pvp_menu = function(pid)
    open_menu(pid, "open")
  end
end)

-- -------------------------
-- Startup
-- -------------------------

print("[octo] Octo PVP split starting...")
load_ranks(ranks_path("open"),  ranks_open)
load_ranks(ranks_path("wcity"), ranks_wcity)
check_areas()

-- -------------------------
-- Events
-- -------------------------

Net:on("player_connect", function(ev)
  ensure_rank_entry(ranks_open, ev.player_id)
  ensure_rank_entry(ranks_wcity, ev.player_id)
  save_ranks(ranks_path("open"),  ranks_open)
  save_ranks(ranks_path("wcity"), ranks_wcity)
end)

Net:on("board_close", function(ev)
  bbs_type[ev.player_id] = nil
end)

-- WCity boards ONLY: show WCity format ONLY
Net:on("object_interaction", function(ev)
  if ev.button ~= 0 then return end

  local area = Net.get_player_area(ev.player_id)
  local obj = Net.get_object_by_id(area, ev.object_id)
  if obj.class ~= "PVP Board" and obj.type ~= "PVP Board" then
    return
  end

  if not is_wcity_area(area) then
    Net.message_player(ev.player_id, "This board only works in WCity PVP areas.")
    return
  end

  open_menu(ev.player_id, "wcity")
end)

-- Direct challenges everywhere; format is chosen by BOTH players' location
Net:on("actor_interaction", function(ev)
  if ev.button ~= 0 then return end
  if not Net.is_player(ev.actor_id) then return end

  local p1 = ev.player_id
  local p2 = ev.actor_id

  remove_from_all_queues(p1)

  local fmt = format_for_pair(p1, p2)
  local tag = (fmt == "wcity") and "[WCity]" or "[Open]"

  local posts = {
    { id = "ChallengeRequest", read = true, title = tag .. " Request Battle: " .. Net.get_player_name(p2), author = "" },
  }

  if player_challenges[p2]
    and player_challenges[p2].target == p1
    and player_challenges[p2].format == fmt
  then
    posts[1] = { id = "ChallengeAccept", read = true, title = tag .. " Accept Battle: " .. Net.get_player_name(p2), author = "" }
  end

  local emitter = Net.open_board(p1, "PVP Request " .. tag, { r = 127, g = 127, b = 127 }, posts)

  emitter:on("post_selection", function(sel)
    if sel.post_id == "ChallengeRequest" then
      player_challenges[p1] = { target = p2, format = fmt }
      Net.exclusive_player_emote(p2, p1, 7)
      Net.exclusive_player_emote(p1, p1, 7)
      return
    end

    if sel.post_id == "ChallengeAccept" then
      -- Re-check at accept time (prevents format swapping by moving)
      local fmt_now = format_for_pair(p1, p2)
      if fmt_now ~= fmt then
        Net.message_player(p1, "Both players must be in the same format area to start this battle.")
        return
      end

      player_challenges[p1] = nil
      player_challenges[p2] = nil

      Net.initiate_pvp(p1, p2)
      players_in_battle[p1] = p2
      players_in_battle[p2] = p1
      return
    end
  end)
end)

Net:on("battle_results", function(ev)
  players_in_battle[ev.player_id] = nil
  player_challenges[ev.player_id] = nil
end)

Net:on("player_disconnect", function(ev)
  local pid = ev.player_id
  players_in_battle[pid] = nil
  player_challenges[pid] = nil
  remove_from_all_queues(pid)
end)

Net:on("player_area_transfer", function(ev)
  local pid = ev.player_id
  local area = Net.get_player_area(pid)

  -- If they leave WCity, cancel WCity queue/challenges
  if not is_wcity_area(area) then
    local i = find_in_table(q_wcity_ranked, pid);   if i then table.remove(q_wcity_ranked, i) end
    i = find_in_table(q_wcity_unranked, pid);       if i then table.remove(q_wcity_unranked, i) end

    local ch = player_challenges[pid]
    if ch and ch.format == "wcity" then
      player_challenges[pid] = nil
    end
  end
end)

Net:on("tick", function(ev)
  timer = timer + ev.delta_time
  if timer > 5 then
    for pid, _ in pairs(players_in_battle) do
      if players_in_battle[pid] ~= nil then
        Net.set_player_emote(pid, 7)
      end
    end
    timer = 0
  end
end)

-- -------------------------
-- Matchmaking (post_selection)
-- -------------------------

Net:on("post_selection", function(ev)
  local pid = ev.player_id
  local post_id = ev.post_id

  local mt = bbs_type[pid]
  if mt ~= "OpenMenu" and mt ~= "WCityMenu" then return end

  local fmt = (mt == "WCityMenu") and "wcity" or "open"
  local tbl = rank_tbl(fmt)

  local q_ranked   = (fmt == "wcity") and q_wcity_ranked   or q_open_ranked
  local q_unranked = (fmt == "wcity") and q_wcity_unranked or q_open_unranked

  if post_id == "About" then
    Net.message_player(pid,
      "Ranked: forces both players to 1000 HP. If either player quits, points are unchanged.\n" ..
      "Free Battle: no HP restriction.\n" ..
      "WCity format only exists in OctoPVP=true areas.")
    return
  end

  if post_id == "Leaderboard" then
    pcall(function() Net.close_bbs(pid) end)

    local lb = build_sorted_leaderboard(tbl, 5)
    local posts = {}
    for i, rd in ipairs(lb) do
      posts[#posts+1] = {
        id = tostring(i),
        read = true,
        title = i .. ". " .. rd.Name .. " " .. rd.Rank .. "/" .. rd.Points,
        author = "",
      }
      if i >= 50 then break end
    end

    Async.sleep(0.1).and_then(function()
      local emitter = Net.open_board(pid,
        (fmt == "wcity") and "WCity PVP Leaderboard" or "Open PVP Leaderboard",
        { r=127,g=127,b=127 },
        posts
      )

      local post_index = #posts
      emitter:on("post_request", function()
        if post_index < #lb then
          post_index = post_index + 1
          local rd = lb[post_index]
          Net.append_posts(pid, {{
            id = tostring(post_index),
            read = true,
            title = post_index .. ". " .. rd.Name .. " " .. rd.Rank .. "/" .. rd.Points,
            author = "",
          }})
        end
      end)
    end)
    return
  end

  if post_id == "Ranked" and not find_in_table(q_ranked, pid) and not find_in_table(q_unranked, pid) then
    pcall(function() Net.close_bbs(pid) end)
    Async.message_player(pid, "Started ranked matchmaking...").and_then(function()
      table.insert(q_ranked, pid)

      if #q_ranked >= 2 then
        Async.sleep(4.9).and_then(function()
          if #q_ranked < 2 then
            while #q_ranked > 0 do
              local p = table.remove(q_ranked, 1)
              Net.message_player(p, "No other players in matchmaking!")
            end
            return
          end

          local p1 = table.remove(q_ranked, 1)
          local p2 = table.remove(q_ranked, find_nearest_rating_to(q_ranked, tbl, p1))
          if not p2 then return end

          if Net.is_player_battling(p1) or Net.is_player_battling(p2) then return end

          local snaps = { [p1] = snapshot_hp(p1), [p2] = snapshot_hp(p2) }
          Net.set_player_max_health(p1, 1000); Net.set_player_health(p1, 1000)
          Net.set_player_max_health(p2, 1000); Net.set_player_health(p2, 1000)

          local function cleanup()
            restore_hp(p1, snaps[p1])
            restore_hp(p2, snaps[p2])
            players_in_battle[p1] = nil
            players_in_battle[p2] = nil
            player_challenges[p1] = nil
            player_challenges[p2] = nil
          end

          Async.sleep(0.1).and_then(function()
            players_in_battle[p1] = p2
            players_in_battle[p2] = p1

            Async.initiate_pvp(p1, p2).and_then(function(res)
              if res.ran then
                cleanup()
                save_ranks(ranks_path(fmt), tbl)
                return
              end

              local winner = (res.health > 0) and p1 or p2

              for _, p in ipairs({p1, p2}) do
                ensure_rank_entry(tbl, p)
                tbl[p].Name  = Net.get_player_name(p)
                tbl[p].Games = (tbl[p].Games or 0) + 1
                if p == winner then
                  tbl[p].Win = (tbl[p].Win or 0) + 1
                else
                  tbl[p].Loss = (tbl[p].Loss or 0) + 1
                end

                tbl[p].Points = math.ceil(((((tbl[p].Win - tbl[p].Loss) / tbl[p].Games) * 0.5) + 0.5) * 50000)
                if tbl[p].Points < 0 then tbl[p].Points = 0 end
                if tbl[p].Points > 50000 then tbl[p].Points = 50000 end

                local pts = tbl[p].Points
                if pts < 2500 then tbl[p].Rank = "D-" end
                if pts >= 2500  then tbl[p].Rank = "D"  end
                if pts >= 5000  then tbl[p].Rank = "D+" end
                if pts >= 7500  then tbl[p].Rank = "C-" end
                if pts >= 10000 then tbl[p].Rank = "C"  end
                if pts >= 12500 then tbl[p].Rank = "C+" end
                if pts >= 15000 then tbl[p].Rank = "B-" end
                if pts >= 17500 then tbl[p].Rank = "B"  end
                if pts >= 20000 then tbl[p].Rank = "B+" end
                if pts >= 22500 then tbl[p].Rank = "A-" end
                if pts >= 25000 then tbl[p].Rank = "A"  end
                if pts >= 27500 then tbl[p].Rank = "A+" end
                if pts >= 30000 then tbl[p].Rank = "S-" end
                if pts >= 32500 then tbl[p].Rank = "S"  end
                if pts >= 35000 then tbl[p].Rank = "S+" end
                if pts >= 37500 then tbl[p].Rank = "SS" end
                if pts >= 40000 then tbl[p].Rank = "U"  end
                if pts >= 42500 then tbl[p].Rank = "W"  end
                if pts >= 45000 then tbl[p].Rank = "X"  end
                if pts >= 47500 then tbl[p].Rank = "Z"  end
              end

              cleanup()
              save_ranks(ranks_path(fmt), tbl)
            end)
          end)
        end)
      end
    end)
    return
  end

  if post_id == "Unranked" and not find_in_table(q_ranked, pid) and not find_in_table(q_unranked, pid) then
    pcall(function() Net.close_bbs(pid) end)
    Async.message_player(pid, "Started unranked matchmaking...").and_then(function()
      table.insert(q_unranked, pid)

      if #q_unranked >= 2 then
        Async.sleep(4.9).and_then(function()
          if #q_unranked < 2 then
            while #q_unranked > 0 do
              local p = table.remove(q_unranked, 1)
              Net.message_player(p, "No other players in matchmaking!")
            end
            return
          end

          local p1 = table.remove(q_unranked, 1)
          local p2 = table.remove(q_unranked, 1)
          if Net.is_player_battling(p1) or Net.is_player_battling(p2) then return end

          Async.sleep(0.1).and_then(function()
            Net.initiate_pvp(p1, p2)
            players_in_battle[p1] = p2
            players_in_battle[p2] = p1
          end)
        end)
      end
    end)
    return
  end
end)
