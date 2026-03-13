local ezmemory = require('scripts/ezlibs-scripts/ezmemory')

local sfx = {
    item_get='/server/assets/ezlibs-assets/sfx/item_get.ogg'
}

-- === Battle Debug Helpers (paste once near the top) ===
local BATTLE_DEBUG = false          -- flip to false to disable
local BATTLE_DEBUG_TO_PLAYER = false -- also show a short line to the player

local function _dbg_flatten(value, base, out, seen)
  out  = out  or {}
  seen = seen or {}
  local tv = type(value)
  if tv ~= "table" then
    out[#out+1] = string.format("%s = %s (%s)", base, tostring(value), tv)
    return out
  end
  if seen[value] then
    out[#out+1] = string.format("%s = <cycle> (table)", base)
    return out
  end
  seen[value] = true

  -- array part first
  local n = #value
  for i = 1, n do
    _dbg_flatten(value[i], string.format("%s[%d]", base, i), out, seen)
  end
  -- then map part, sorted
  local keys = {}
  for k,_ in pairs(value) do
    if not (type(k)=="number" and k>=1 and k<=n and k==math.floor(k)) then
      keys[#keys+1] = k
    end
  end
  table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
  for _,k in ipairs(keys) do
    local child = (type(k)=="string" and k:match("^[%a_][%w_]*$")) and (base.."."..k) or (base.."["..tostring(k).."]")
    _dbg_flatten(value[k], child, out, seen)
  end
  return out
end

local function _debug_encounter_result(player_id, encounter_info, stats)
  local pname = Net.get_player_name(player_id) or player_id
  local ename = encounter_info and (encounter_info.name or encounter_info.id) or "<unknown encounter>"
  print(string.rep("-", 64))
  print(string.format("[WCity DBG] Player=%s Encounter=%s", tostring(pname), tostring(ename)))
  print("[WCity DBG] -------- Encounter stats (flattened) --------")
  local lines = _dbg_flatten(stats or {}, "stats")
  for _,line in ipairs(lines) do
    print("[WCity DBG] "..line)
  end
  local ran = (stats and (stats.ran or stats.fled or stats.escape)) and true or false
  local hp  = tonumber(stats and (stats.health or stats.player_hp or stats.hp) or 0) or 0
  local turns = tonumber(stats and stats.turns or 0) or 0
  local time  = tonumber(stats and stats.time  or 0) or 0
  local score = tonumber(stats and stats.score or 0) or 0
  print(string.format("[WCity DBG] summary ran=%s hp=%s turns=%s time=%s score=%s",
    tostring(ran), tostring(hp), tostring(turns), tostring(time), tostring(score)))
  print(string.rep("-", 64))

  if BATTLE_DEBUG_TO_PLAYER then
    Net.message_player(player_id, string.format(
      "[DBG] ran=%s hp=%d turns=%d time=%.2f score=%d",
      tostring(ran), hp, turns, time, score
    ))
  end
end
-- === /Battle Debug Helpers ===

local JobBBS = (function()
  local ok, M = pcall(require, 'scripts/jobbbs/JobBBS')
  if ok and M then return M end
  ok, M = pcall(require, 'scripts/jobbbs/jobbbs') -- fallback name if needed
  return ok and M or nil
end)()

-- Unified reward sender that:
--  1) Always uses Net.send_player_battle_rewards (UI popup)
--  2) Fixes up BugFrags (type=3) if the engine doesn't actually apply them server-side
--  3) Fixes up Money (type=0) if the engine doesn't actually apply it server-side
--  4) Syncs money/frags into ezmemory so relog can't revert
--
-- Usage:
--   _send_rewards_and_fixup_wallet(player_id, rewards)
--
local function _send_rewards_and_fixup_wallet(player_id, rewards)
  if not rewards or #rewards == 0 then return end

  -- Sum expected deltas from the packet
  local expected_money = 0
  local expected_frags = 0
  for _, r in ipairs(rewards) do
    if r then
      local v = tonumber(r.value) or 0
      if r.type == 0 then
        expected_money = expected_money + v
      elseif r.type == 3 then
        expected_frags = expected_frags + v
      end
    end
  end

  -- Snapshot server-side counters BEFORE sending (only if relevant APIs exist)
  local money_before = nil
  if expected_money > 0 and Net.get_player_money then
    money_before = tonumber(Net.get_player_money(player_id) or 0) or 0
  end

  local frags_before = nil
  if expected_frags > 0 and Net.get_player_fragments then
    frags_before = tonumber(Net.get_player_fragments(player_id) or 0) or 0
  end

  -- 1) Send the UI reward packet (this is required for the reward popup)
  Net.send_player_battle_rewards(player_id, rewards)

  -- 2) Fixups (only if the server-side counters didn't move as expected)

  -- Money fixup: if Net.get_player_money didn't increase, force-add via ezmemory
  if expected_money > 0 and money_before ~= nil then
    local money_after = tonumber(Net.get_player_money(player_id) or 0) or 0
    if money_after < (money_before + expected_money) then
      -- Force persist + server sync through ezmemory
      -- spend_player_money with a negative amount ADDS money.
      pcall(ezmemory.spend_player_money, player_id, -expected_money)

      if BATTLE_DEBUG then
        local now = tonumber(Net.get_player_money(player_id) or 0) or 0
        print(('[DBG] send_player_battle_rewards DID NOT apply money; fixed up +%d. Net %d -> %d')
          :format(expected_money, money_before, now))
      end
    elseif BATTLE_DEBUG then
      print(('[DBG] send_player_battle_rewards applied money +%d. Net %d -> %d')
        :format(expected_money, money_before, money_after))
    end
  end

  -- BugFrag fixup: if Net.get_player_fragments didn't increase, force-add via ezmemory
  if expected_frags > 0 and frags_before ~= nil then
    local frags_after = tonumber(Net.get_player_fragments(player_id) or 0) or 0
    if frags_after < (frags_before + expected_frags) then
      pcall(ezmemory.add_player_fragments, player_id, expected_frags)

      if BATTLE_DEBUG then
        local now = tonumber(Net.get_player_fragments(player_id) or 0) or 0
        print(('[DBG] send_player_battle_rewards DID NOT apply frags; fixed up +%d. Net %d -> %d')
          :format(expected_frags, frags_before, now))
      end
    elseif BATTLE_DEBUG then
      print(('[DBG] send_player_battle_rewards applied frags +%d. Net %d -> %d')
        :format(expected_frags, frags_before, frags_after))
    end
  end

  -- 3) Sync/merge into ezmemory so relog can't revert.
  -- Note: money merge only helps if Net.get_player_money reflects reality, but we already fixed-up above.
  local function _sync_wallet(tag)
    if ezmemory then
      if ezmemory.get_player_money then pcall(ezmemory.get_player_money, player_id) end
      if ezmemory.get_player_fragments then pcall(ezmemory.get_player_fragments, player_id) end
    end

    if BATTLE_DEBUG then
      local m = Net.get_player_money and (tonumber(Net.get_player_money(player_id) or 0) or 0) or -1
      local f = Net.get_player_fragments and (tonumber(Net.get_player_fragments(player_id) or 0) or 0) or -1
      print(string.format("[DBG] wallet sync (%s): money=%d frags=%d", tostring(tag or "now"), m, f))
    end
  end

  _sync_wallet("immediate")

  -- tiny delayed sync, if Async is available (harmless if missing)
  if _G and _G.Async and _G.async and _G.await and _G.Async.sleep then
    async(function()
      await(Async.sleep(0.05))
      _sync_wallet("delayed")
    end)
  end
end


local persist_health_and_emotion = function (player_id,encounter_info,stats)
    if stats.emotion == 1 then
        Net.set_player_emotion(player_id, stats.emotion)
    else
        Net.set_player_emotion(player_id, 0)
    end
    ezmemory.set_player_health(player_id,stats.health)
end

local give_result_awards = function (player_id, encounter_info, stats)
  -- Let JobBBS react to the result like before
  if JobBBS and JobBBS.on_encounter_result then
    pcall(JobBBS.on_encounter_result, player_id, stats)
  end

  -- If the player ran, persist health/emotion only (no rewards), same policy as before
  if stats.ran then
    persist_health_and_emotion(player_id, encounter_info, stats)
    return
  end

  -- 1) Money = busting level * 100
  local monies = (stats.score or 0) * 100

  -- 2) If post-battle HP < 20, give +50 HP
  local hp_bonus = ((stats.health or 0) < 20) and 50 or 0

  -- Build the beta-10 reward list
  local rewards = {}
  if monies > 0 then
    table.insert(rewards, { type = 0, value = monies })  -- 0=Money
  end
  if hp_bonus > 0 then
    table.insert(rewards, { type = 2, value = hp_bonus }) -- 2=Health+
  end

  if #rewards > 0 then
    _send_rewards_and_fixup_wallet(player_id, rewards)
  end

  -- Keep ezmemory in sync with the final HP the player ends up with after the HP+ reward
  -- (so the next encounter/persisted state matches what the client shows)
  local final_stats = { health = (stats.health or 0) + hp_bonus, emotion = stats.emotion }
  persist_health_and_emotion(player_id, encounter_info, final_stats)
end

local give_result_awards_rare = function (player_id, encounter_info, stats)
  -- Let JobBBS react to the result like before
  if JobBBS and JobBBS.on_encounter_result then
    pcall(JobBBS.on_encounter_result, player_id, stats)
  end

  -- If the player ran, persist health/emotion only (no rewards), same policy as before
  if stats.ran then
    persist_health_and_emotion(player_id, encounter_info, stats)
    return
  end

  -- 1) Money = busting level * 300
  local monies = (stats.score or 0) * 300

  -- 2) If post-battle HP < 20, give +50 HP
  local hp_bonus = ((stats.health or 0) < 20) and 50 or 0

  -- Build the beta-10 reward list
  local rewards = {}
  if monies > 0 then
    table.insert(rewards, { type = 0, value = monies })  -- 0=Money
  end
  if hp_bonus > 0 then
    table.insert(rewards, { type = 2, value = hp_bonus }) -- 2=Health+
  end

  if #rewards > 0 then
    _send_rewards_and_fixup_wallet(player_id, rewards)
  end

  -- Keep ezmemory in sync with the final HP the player ends up with after the HP+ reward
  -- (so the next encounter/persisted state matches what the client shows)
  local final_stats = { health = (stats.health or 0) + hp_bonus, emotion = stats.emotion }
  persist_health_and_emotion(player_id, encounter_info, final_stats)
end

local Encounter1 = {
    name="Encounter1",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    pet_exp=6,
    enemies={
        {name="Ratty",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,1},
        {0,0,0,0,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,2,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = give_result_awards
}

local Encounter2 = {
    name="Encounter2",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    pet_exp=6,
    enemies={
        {name="Swordy",rank=2},
        {name="Fishy",rank=3},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,2,0},
        {0,0,0,1,0,0},
        {0,0,0,0,2,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {8,1,1,1,1,1},
        {8,1,1,1,1,1},
        {8,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = give_result_awards
}

local Encounter3 = {
    name="Encounter3",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    pet_exp=6,
    enemies={
        {name="Quaker",rank=2},
        {name="Quaker",rank=3},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,1},
        {0,0,0,0,0,2},
        {0,0,0,0,0,1},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {12,12,1,1,1,1},
        {1,12,12,1,1,1},
        {1,12,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = give_result_awards
}

local Encounter4 = {
    name="Encounter4",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    pet_exp=6,
    enemies={
        {name="Chumpy",rank=1},
        {name="MegaCorn",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,1,0},
        {0,0,0,0,0,2},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = give_result_awards
}

local Encounter5 = {
    name="Encounter5",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    pet_exp=6,
    enemies={
        {name="Powie3",rank=1},
        {name="ColdHead",rank=1},
        {name="Doomer",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,2},
        {0,0,0,3,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = give_result_awards
}

local Encounter6 = {
    name="Encounter6",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    pet_exp=6,
    enemies={
        {name="Yort",rank=2},
        {name="Doomer",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,2},
        {0,0,0,1,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = give_result_awards
}

local Encounter7 = {
    name="Encounter7",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    pet_exp=6,
    enemies={
        {name="ColdHead",rank=1},
        {name="Piranha",rank=3},
        {name="MegaBunny",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,2,0},
        {0,0,0,0,0,1},
        {0,0,0,3,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,12,1,1,1,1},
        {1,12,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = give_result_awards
}

local Encounter8 = {
    name="Encounter8",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    pet_exp=6,
    enemies={
        {name="Cactroll",rank=1},
        {name="Cacter",rank=1},
        {name="DemonEye",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,1},
        {0,0,0,0,0,2},
        {0,0,0,3,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = give_result_awards
}

local Encounter9 = {
    name="Encounter9",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    pet_exp=7,
    enemies={
        {name="Metrid",rank=2},
        {name="Metrid",rank=3},
        {name="JokerEye",rank=1},
    },
    obstacles={
        {name="Rock"},
        {name="Rock"},
    },
    positions={
        {0,0,0,0,0,1},
        {0,0,0,0,0,3},
        {0,0,0,0,0,2},
    },
    obstacle_positions={
        {0,0,0,1,0,0},
        {0,0,0,0,0,0},
        {0,0,0,2,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = give_result_awards
}

local Encounter10 = {
    name="Encounter10",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    pet_exp=7,
    enemies={
        {name="Metrid",rank=4},
        {name="HotHead",rank=1},
    },
    obstacles={
        {name="RockCube"},
    },
    positions={
        {0,0,0,0,2,1},
        {0,0,0,0,0,0},
        {0,0,0,0,2,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,1,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = give_result_awards
}

local boss1 = {
    name="boss1",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=5,
    pet_exp=10,
    enemies={
        {name="GutsManPoN",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,0,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    music={
        path="bn3_boss.mid"
    },
    results_callback = give_result_awards_rare
}

return {
    minimum_steps_before_encounter=40,
    encounter_chance_per_step=0.10,
    encounters={Encounter1,Encounter2,Encounter3,Encounter4,Encounter5,Encounter6,Encounter7,Encounter8,Encounter9,Encounter10,boss1}
}