local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
-- Optional dungeon helper (for unified result flags / run penalties)
local dungeon
do
  local ok, mod = pcall(require, 'scripts/ezlibs-custom/dungeon')
  if ok and mod then dungeon = mod end
end

local sfx = {
    item_get='/server/assets/ezlibs-assets/sfx/item_get.ogg'
}

local JobBBS = (function()
  local ok, M = pcall(require, 'scripts/jobbbs/JobBBS')
  if ok and M then return M end
  ok, M = pcall(require, 'scripts/jobbbs/jobbbs') -- fallback name if needed
  return ok and M or nil
end)()

local function _result_flags(stats)
  -- If dungeon.lua exposes a classifier, use that
  if dungeon then
    local f = dungeon.result_flags or dungeon._result_flags
    if type(f) == "function" then
      return f(stats)
    end
  end

  -- Fallback: local copy (same idea as JobBBS/raids)
  local reason = tonumber(stats and stats.reason or 0) or 0
  local hp     = tonumber(stats and (stats.health or stats.player_hp or stats.hp) or 0) or 0

  local ran, dev_escape, won, lost = false, false, false, false

  if reason == 1 then
    -- Normal win
    won = true
  elseif reason == 2 then
    -- Normal loss
    lost = true
  elseif reason == 3 then
    -- L-button / legit run
    ran = true
  elseif reason == 4 then
    -- Dev ESC/run: still a run, but with special meaning
    ran = true
    dev_escape = true
  else
    -- Older engines or weird stats: fall back to the legacy flags
    ran = stats and (stats.ran or stats.fled or stats.escape) or false

    if not ran then
      if hp > 0 then
        won = true
      elseif hp <= 0 then
        lost = true
      end
    end
  end

  return {
    reason     = reason,
    hp         = hp,
    ran        = ran,
    dev_escape = dev_escape,
    won        = won,
    lost       = lost,
  }
end

-- === Battle Debug Helpers (paste once near the top) ===
local BATTLE_DEBUG = true          -- flip to false to disable
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
  print(string.format("[Dungeon1 DBG] Player=%s Encounter=%s", tostring(pname), tostring(ename)))
  print("[Dungeon1 DBG] -------- Encounter stats (flattened) --------")
  local lines = _dbg_flatten(stats or {}, "stats")
  for _,line in ipairs(lines) do
    print("[Dungeon1 DBG] "..line)
  end
  local ran = (stats and (stats.ran or stats.fled or stats.escape)) and true or false
  local hp  = tonumber(stats and (stats.health or stats.player_hp or stats.hp) or 0) or 0
  local turns = tonumber(stats and stats.turns or 0) or 0
  local time  = tonumber(stats and stats.time  or 0) or 0
  local score = tonumber(stats and stats.score or 0) or 0
  print(string.format("[Dungeon1 DBG] summary ran=%s hp=%s turns=%s time=%s score=%s",
    tostring(ran), tostring(hp), tostring(turns), tostring(time), tostring(score)))
  print(string.rep("-", 64))

  if BATTLE_DEBUG_TO_PLAYER then
    Net.message_player(player_id, string.format(
      "[DBG] ran=%s hp=%d turns=%d time=%.2f score=%d",
      tostring(ran), hp, turns, time, score
    ))
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

-- Dungeon "lives" revives can adjust the player's HP outside the battle stats.
-- When persisting HP after rewards, never LOWER the player's current HP.
local function _final_persist_hp(player_id, intended_hp)
  intended_hp = tonumber(intended_hp or 0) or 0
  local cur = tonumber(Net.get_player_health(player_id) or intended_hp) or intended_hp
  if cur > intended_hp then
    return cur
  end
  return intended_hp
end

local function _in_dungeon(player_id)
  if not (dungeon and dungeon.is_dungeon_area) then return false end
  local area_id = Net.get_player_area(player_id)
  return dungeon.is_dungeon_area(area_id)
end

local give_result_awards = function (player_id, encounter_info, stats)
  -- Normalize result so we respect stats.reason (3 = legit run, 4 = dev ESC)
  local flags = _result_flags(stats)

  -- DEBUG (put this right at the top)
  if BATTLE_DEBUG then
    _debug_encounter_result(player_id, encounter_info, stats)
  end

  -- If the player ran (either type), persist health/emotion only (no rewards)
  if flags.dev_escape then
    persist_health_and_emotion(player_id, encounter_info, stats)
    dungeon.apply_run_penalty(player_id, encounter_info, stats)
    return
  end

  -- If this was a straight-up loss (HP hit 0), kick the player out of the dungeon.
  if dungeon and dungeon.kick_player_if_dead and flags.lost then
    dungeon.kick_player_if_dead(player_id, stats)
  end

  -- 1) Money = busting level * 100
  local monies = (stats.score or 0) * 400

  -- 2) HP bonus:
  --    If HP < 101: always +150
  --    Else if HP < 401: 1/3 chance of +150
  local hp = (stats.health or 0)
  local hp_bonus = 0

  -- Build the beta-10 reward list
  local rewards = {}
  if monies > 0 then
    table.insert(rewards, { type = 0, value = monies })  -- 0=Money
  end
  if hp < 101 then
    hp_bonus = 150
  elseif hp < 401 then
    -- 1/3 chance
    if math.random(3) == 1 then
      hp_bonus = 150
    end
  end

  -- If we lost in a dungeon, don't also grant HP+ here (the "life" revive handles healing).
  if _in_dungeon(player_id) and flags.lost then
    hp_bonus = 0
  end

  if hp_bonus > 0 then
    table.insert(rewards, { type = 2, value = hp_bonus })
  end

  if #rewards > 0 then
    Net.send_player_battle_rewards(player_id, rewards)
  end

  -- Keep ezmemory in sync with the final HP the player ends up with after the HP+ reward
  -- (so the next encounter/persisted state matches what the client shows)
  local final_hp = (stats.health or 0) + hp_bonus

  -- Only protect against "life revive" overwriting HP on a LOSS in a dungeon.
  if _in_dungeon(player_id) and flags.lost then
    final_hp = _final_persist_hp(player_id, final_hp)
  end

  local final_stats = { health = final_hp, emotion = stats.emotion }
  persist_health_and_emotion(player_id, encounter_info, final_stats)
end

local mini_boss_rewards = function (player_id, encounter_info, stats)
  -- Normalize result so we respect stats.reason (3 = legit run, 4 = dev ESC)
  local flags = _result_flags(stats)

  -- DEBUG (put this right at the top)
  if BATTLE_DEBUG then
    _debug_encounter_result(player_id, encounter_info, stats)
  end

  -- If the player ran (either type), persist health/emotion only (no rewards)
  if flags.dev_escape then
    persist_health_and_emotion(player_id, encounter_info, stats)
    dungeon.apply_run_penalty(player_id, encounter_info, stats)
    return
  end

  -- 1) Money = busting level * 1500
  local monies = (stats.score or 0) * 1500

  -- 2) If post-battle HP < 101, give +300 HP
  local hp_bonus = ((stats.health or 0) < 101) and 300 or 0

  -- If we lost in a dungeon, don't also grant HP+ here (the "life" revive handles healing).
  if _in_dungeon(player_id) and flags.lost then
    hp_bonus = 0
  end

  -- 3) 5% chance to drop 1 BugFrag
  local bugfrag_amount = (math.random(100) <= 5) and 1 or 0

  local rewards = {}
  if monies > 0 then
    table.insert(rewards, { type = 0, value = monies })  -- 0=Money
  end
  if hp_bonus > 0 then
    table.insert(rewards, { type = 2, value = hp_bonus }) -- 2=Health+
  end
  if bugfrag_amount > 0 then
    table.insert(rewards, { type = 3, value = bugfrag_amount }) -- 3=BugFrags
  end

  if #rewards > 0 then
    Net.send_player_battle_rewards(player_id, rewards)
  end

  local final_hp = (stats.health or 0) + hp_bonus

  if _in_dungeon(player_id) and flags.lost then
    final_hp = _final_persist_hp(player_id, final_hp)
  end

  local final_stats = { health = final_hp, emotion = stats.emotion }
  persist_health_and_emotion(player_id, encounter_info, final_stats)
end


local Dungeon1 = {
    name="Dungeon1",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    enemies={
        {name="Volcano",rank=2},
        {name="Yort",rank=3},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,1},
        {0,0,0,2,0,0},
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
        {13,1,1,1,13,1},
        {13,1,1,1,1,1},
        {13,1,1,1,1,13},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = give_result_awards
}

local Dungeon2 = {
    name="Dungeon2",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    enemies={
        {name="Yort",rank=3},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
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
        {1,1,13,1,1,1},
        {1,1,1,1,1,1},
        {13,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = give_result_awards
}

local Dungeon3 = {
    name="Dungeon3",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    enemies={
        {name="Spikey",rank=3},
        {name="Spikey",rank=2},
        {name="Spikey",rank=4},
    },
    obstacles={
        {name="RockCube"},
        {name="RockCube"},
        {name="Rock"},
    },
    positions={
        {0,0,0,0,1,0},
        {0,0,0,0,0,3},
        {0,0,0,0,2,0},
    },
    obstacle_positions={
        {0,0,0,2,0,0},
        {0,0,1,0,0,0},
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

local Dungeon4 = {
    name="Dungeon4",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    enemies={
        {name="Metrid",rank=2},
        {name="Yort",rank=3},
    },
    obstacles={
        {name="RockCube"},
    },
    positions={
        {0,0,0,0,0,1},
        {0,0,0,2,0,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,1,0},
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
        {1,13,13,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = give_result_awards
}

local Dungeon5 = {
    name="Dungeon5",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    enemies={
        {name="Swordy",rank=3},
        {name="Powie3",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,1,2,0},
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
        {1,1,13,13,1,1},
        {1,1,1,1,1,1},
        {1,13,13,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = give_result_awards
}

local Dungeon6 = {
    name="Dungeon6",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    enemies={
        {name="Volcano",rank=1},
        {name="Volcano",rank=3},
        {name="Volcano",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,2},
        {0,0,0,0,3,0},
        {0,0,0,1,0,0},
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
        {1,1,13,13,1,1},
        {1,1,1,1,13,1},
        {13,1,1,1,1,13},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = give_result_awards
}

local Dungeon7 = {
    name="Dungeon7",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    enemies={
        {name="Beetank",rank=3},
        {name="Fishy",rank=3},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,1},
        {0,0,0,0,2,0},
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
        {13,1,13,1,1,1},
        {1,1,1,1,1,1},
        {13,1,13,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = give_result_awards
}

local Dungeon8 = {
    name="Dungeon8",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    enemies={
        {name="Sniper",rank=1},
        {name="Gloomer",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,2},
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
        {1,1,13,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = give_result_awards
}

local Dungeon9 = {
    name="Dungeon9",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    enemies={
        {name="Mettaur",rank=4},
        {name="Yort",rank=3},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,2,0},
        {0,0,0,0,0,1},
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

local Dungeon10 = {
    name="Dungeon10",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    enemies={
        {name="Beetank",rank=2},
        {name="Chumpy",rank=1},
        {name="MegaCorn",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,1,0,0},
        {0,0,0,0,2,0},
        {0,0,0,0,0,3},
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

local MiniBoss1 = {
    name="MiniBoss1",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=0,
    enemies={
        {name="HeelNavi",rank=4},
        {name="Swordy",rank=3},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,2,1,0},
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
    results_callback = mini_boss_rewards
}

local MiniBoss2 = {
    name="MiniBoss2",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=0,
    enemies={
        {name="Noir",rank=1},
        {name="Metrid",rank=2},
        {name="MegaBunny",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,2},
        {0,0,0,0,1,0},
        {0,0,0,0,0,3},
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
        {1,13,1,1,1,1},
        {1,1,1,1,1,1},
        {1,13,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = mini_boss_rewards
}

local MiniBoss3 = {
    name="MiniBoss3",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=0,
    enemies={
        {name="ElementMan",rank=4},
        {name="JokerEye",rank=1},
        {name="Sniper",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,0,1,3},
        {0,0,0,2,0,0},
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
        {13,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,13,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    results_callback = mini_boss_rewards
}

local MainBoss = {
    name="MainBoss",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=0,
    enemies={
        {name="MegaBunny",rank=1},
        {name="ShadeMan",rank=1},
        {name="Metrid",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,3,0,0},
        {0,0,0,0,2,0},
        {0,0,0,1,0,0},
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
    results_callback = mini_boss_rewards
}

return {
    minimum_steps_before_encounter=40,
    encounter_chance_per_step=0.10,
    encounters={Dungeon1,Dungeon2,Dungeon3,Dungeon4,Dungeon5,Dungeon6,Dungeon7,Dungeon8,Dungeon9,Dungeon10,MiniBoss1,MiniBoss2,MiniBoss3,MainBoss}
}