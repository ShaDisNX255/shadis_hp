local ezmemory = require('scripts/ezlibs-scripts/ezmemory')

local sfx = {
    item_get='/server/assets/ezlibs-assets/sfx/item_get.ogg'
}

local JobBBS = (function()
  local ok, M = pcall(require, 'scripts/jobbbs/JobBBS')
  if ok and M then return M end
  ok, M = pcall(require, 'scripts/jobbbs/jobbbs') -- fallback name if needed
  return ok and M or nil
end)()

local persist_health_and_emotion = function (player_id,encounter_info,stats)
    if stats.emotion == 1 then
        Net.set_player_emotion(player_id, stats.emotion)
    else
        Net.set_player_emotion(player_id, 0)
    end
    ezmemory.set_player_health(player_id,stats.health)
end

local give_result_awards = function (player_id,encounter_info,stats)
    if JobBBS and JobBBS.on_encounter_result then
      pcall(JobBBS.on_encounter_result, player_id, stats)
    end
    -- stats = { health: number, score: number, time: number, ran: bool, emotion: number, turns: number, npcs: { id: String, health: number }[] }
    persist_health_and_emotion(player_id,encounter_info,stats)
    if stats.ran then
        return -- no rewards for wimps
    end
    local reward_monies = (stats.score*100)
    ezmemory.spend_player_money(player_id,-reward_monies) -- spending money backwards gives money
    if reward_monies > 0 then
        Net.message_player(player_id,"Got $"..reward_monies.."!")
        Net.play_sound_for_player(player_id,sfx.item_get)
    end
end

local give_result_awards_rare = function (player_id,encounter_info,stats)
    if JobBBS and JobBBS.on_encounter_result then
      pcall(JobBBS.on_encounter_result, player_id, stats)
    end
    -- stats = { health: number, score: number, time: number, ran: bool, emotion: number, turns: number, npcs: { id: String, health: number }[] }
    if stats.ran then
        return -- no rewards for wimps
    end
    local reward_monies = (stats.score*2000)
    ezmemory.spend_player_money(player_id,-reward_monies) -- spending money backwards gives money
    if reward_monies > 0 then
        Net.message_player(player_id,"Got $"..reward_monies.."!")
        Net.play_sound_for_player(player_id,sfx.item_get)
    end
end

local Encounter1 = {
    name="Encounter1",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
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