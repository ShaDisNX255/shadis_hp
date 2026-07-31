local eznpcs = require("scripts/ezlibs-scripts/eznpcs/eznpcs")
local ezencounters = require("scripts/ezlibs-scripts/ezencounters/main")
local ezmemory = require("scripts/ezlibs-scripts/ezmemory")

local function _encounter_result_flags(stats)
    local reason = tonumber(stats and stats.reason or 0) or 0
    local hp = tonumber(stats and (stats.health or stats.player_hp or stats.hp) or 0) or 0

    local ran, won, lost = false, false, false

    if reason == 1 then        -- battle won
        won = true
    elseif reason == 2 then    -- battle lost
        lost = true
    elseif reason == 3 then    -- ran with L
        ran = true
    elseif reason == 4 then    -- ESC / dev escape
        ran = true
    else
        -- backwards compatibility with older builds
        ran = stats and (stats.ran or stats.fled or stats.escape) or false
        if not ran then
            if hp > 0 then
                won = true
            else
                lost = true
            end
        end
    end

    return {
        reason = reason,
        hp = hp,
        ran = ran,
        won = won,
        lost = lost,
    }
end

local grass1 = {
    name="grass1",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/elmquest.zip",
    pet_exp=0,
    no_results=true,
    enemies={
        {name="Mettaur",rank=1},
        {name="Weathers",rank=2},
        {name="AppleSam",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,1,0,0},
        {0,0,0,0,3,0},
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
        {1,9,1,1,9,1},
        {9,1,9,9,1,9},
        {1,9,1,1,9,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local grass2 = {
    name="grass2",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/elmquest.zip",
    pet_exp=0,
    no_results=true,
    enemies={
        {name="Mettaur",rank=2},
        {name="Weathers",rank=2},
        {name="AppleSam",rank=1},
        {name="MegaCorn",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,4,0,0},
        {0,0,0,1,3,0},
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
        {9,9,9,9,9,9},
        {9,1,1,1,1,9},
        {9,9,9,9,9,9},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local grass3 = {
    name="grass3",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/elmquest.zip",
    pet_exp=0,
    no_results=true,
    enemies={
        {name="Mettaur",rank=3},
        {name="AppleSam",rank=1},
        {name="DreamMoss",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,1,3,0},
        {0,0,0,0,0,0},
        {0,0,0,2,0,3},
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
        {9,9,9,9,9,9},
        {9,9,9,9,9,9},
        {9,9,9,9,9,9},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local grass4 = {
    name="grass4",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/elmquest.zip",
    pet_exp=0,
    no_results=true,

    -- Applied only to this encounter after the battle Player has spawned.
    -- The engine calls the grass element Wood, but the wrapper accepts either name.
    player_modifier={
        element="wood",

        chip_visual={
            shortname="SwapWood",
            time_freeze=true,

            color={
                r=153,
                g=255,
                b=51,
                a=200,
            },
        },
    },
    enemies={
        {name="Mettaur",rank=3},
        {name="Weathers",rank=2},
        {name="DreamMeraru",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,1,3,0},
        {0,0,0,0,0,0},
        {0,0,0,2,0,3},
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
        {9,9,9,1,1,1},
        {9,9,9,1,1,1},
        {9,9,9,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local grass_1 = {
    name="grass_1",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, grass1))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(grass_1)

local grass_2 = {
    name="grass_2",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, grass2))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(grass_2)

local grass_3 = {
    name="grass_3",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, grass3))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(grass_3)

local grass_4 = {
    name="grass_4",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, grass4))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(grass_4)




local aqua1 = {
    name="aqua1",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/elmquest.zip",
    pet_exp=0,
    no_results=true,
    enemies={
        {name="Mettaur",rank=1},
        {name="Weathers",rank=2},
        {name="Shrimpy",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,1,0,0},
        {0,0,0,0,3,0},
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
        {1,16,1,1,16,1},
        {16,1,16,16,1,16},
        {1,16,1,1,16,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local aqua2 = {
    name="aqua2",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/elmquest.zip",
    pet_exp=0,
    no_results=true,
    enemies={
        {name="Mettaur",rank=2},
        {name="Weathers",rank=2},
        {name="Lark",rank=1},
        {name="Piranha",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,4,0,0},
        {0,0,0,1,3,0},
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
        {1,12,1,1,12,1},
        {12,12,12,12,12,12},
        {1,12,1,1,12,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local aqua3 = {
    name="aqua3",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/elmquest.zip",
    pet_exp=0,
    no_results=true,
    enemies={
        {name="Mettaur",rank=3},
        {name="Weathers",rank=2},
        {name="DreamLapia",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,1,3,0},
        {0,0,0,0,0,0},
        {0,0,0,2,0,3},
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
        {16,12,16,16,12,16},
        {12,12,12,12,12,12},
        {16,12,16,16,12,16},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local aqua4 = {
    name="aqua4",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/elmquest.zip",
    pet_exp=0,
    no_results=true,

    player_modifier={
        element="aqua",

        chip_visual={
            shortname="SwapAqua",
            time_freeze=true,

            color={
                r=51,
                g=153,
                b=255,
                a=200,
            },
        },
    },
    enemies={
        {name="Mettaur",rank=3},
        {name="Weathers",rank=2},
        {name="DreamBolt",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,1,3,0},
        {0,0,0,0,0,0},
        {0,0,0,2,0,3},
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
        {16,12,16,1,1,1},
        {12,12,12,1,1,1},
        {16,12,16,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local aqua_1 = {
    name="aqua_1",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, aqua1))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(aqua_1)

local aqua_2 = {
    name="aqua_2",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, aqua2))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(aqua_2)

local aqua_3 = {
    name="aqua_3",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, aqua3))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(aqua_3)

local aqua_4 = {
    name="aqua_4",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, aqua4))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(aqua_4)




local fire1 = {
    name="fire1",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/elmquest.zip",
    pet_exp=0,
    no_results=true,
    enemies={
        {name="Mettaur",rank=1},
        {name="Metrid",rank=1},
        {name="Spikey",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,1,0,0},
        {0,0,0,0,3,0},
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
        {1,13,1,1,13,1},
        {1,1,1,1,1,1},
        {1,13,1,1,13,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local fire2 = {
    name="fire2",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/elmquest.zip",
    pet_exp=0,
    no_results=true,
    enemies={
        {name="Mettaur",rank=2},
        {name="Spikey",rank=2},
        {name="Metrid",rank=2},
        {name="Weathers",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,4,0,0},
        {0,0,0,1,3,0},
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
        {1,13,1,1,13,1},
        {13,1,13,13,1,13},
        {1,13,1,1,13,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local fire3 = {
    name="fire3",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/elmquest.zip",
    pet_exp=0,
    no_results=true,
    enemies={
        {name="Mettaur",rank=3},
        {name="Weathers",rank=2},
        {name="DreamMeraru",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,1,3,0},
        {0,0,0,0,0,0},
        {0,0,0,2,0,3},
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
        {13,13,13,13,13,13},
        {13,1,1,1,1,13},
        {13,13,13,13,13,13},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local fire4 = {
    name="fire4",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/elmquest.zip",
    pet_exp=0,
    no_results=true,

    player_modifier={
        element="fire",

        chip_visual={
            shortname="SwapFire",
            time_freeze=true,

            color={
                r=255,
                g=0,
                b=0,
                a=200,
            },
        },
    },
    enemies={
        {name="Mettaur",rank=3},
        {name="Weathers",rank=2},
        {name="DreamLapia",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,1,3,0},
        {0,0,0,0,0,0},
        {0,0,0,2,0,3},
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
        {13,13,13,1,1,1},
        {13,13,13,1,1,1},
        {13,13,13,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local fire_1 = {
    name="fire_1",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, fire1))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(fire_1)

local fire_2 = {
    name="fire_2",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, fire2))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(fire_2)

local fire_3 = {
    name="fire_3",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, fire3))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(fire_3)

local fire_4 = {
    name="fire_4",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, fire4))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(fire_4)




local elec1 = {
    name="elec1",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/elmquest.zip",
    pet_exp=0,
    no_results=true,
    enemies={
        {name="Mettaur",rank=1},
        {name="Bunny",rank=1},
        {name="KillerEye",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,1,0,0},
        {0,0,0,0,3,0},
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
        {1,18,1,1,18,1},
        {1,1,1,1,1,1},
        {1,18,1,1,18,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local elec2 = {
    name="elec2",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/elmquest.zip",
    pet_exp=0,
    no_results=true,
    enemies={
        {name="Mettaur",rank=2},
        {name="DemonEye",rank=1},
        {name="TuffBunny",rank=1},
        {name="Weathers",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,4,0,0},
        {0,0,0,1,3,0},
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
        {1,18,1,1,18,1},
        {18,1,18,18,1,18},
        {1,18,1,1,18,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local elec3 = {
    name="elec3",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/elmquest.zip",
    pet_exp=0,
    no_results=true,
    enemies={
        {name="Mettaur",rank=3},
        {name="Weathers",rank=2},
        {name="DreamBolt",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,1,3,0},
        {0,0,0,0,0,0},
        {0,0,0,2,0,3},
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
        {18,18,18,18,18,18},
        {18,18,18,18,18,18},
        {18,18,18,18,18,18},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local elec4 = {
    name="elec4",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/elmquest.zip",
    pet_exp=0,
    no_results=true,

    player_modifier={
        element="elec",

        chip_visual={
            shortname="SwapElec",
            time_freeze=true,

            color={
                r=255,
                g=255,
                b=0,
                a=200,
            },
        },
    },
    enemies={
        {name="Mettaur",rank=3},
        {name="AppleSam",rank=1},
        {name="DreamMoss",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,1,3,0},
        {0,0,0,0,0,0},
        {0,0,0,2,0,3},
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
        {18,18,18,1,1,1},
        {18,18,18,1,1,1},
        {18,18,18,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local elec_1 = {
    name="elec_1",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, elec1))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(elec_1)

local elec_2 = {
    name="elec_2",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, elec2))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(elec_2)

local elec_3 = {
    name="elec_3",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, elec3))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(elec_3)

local elec_4 = {
    name="elec_4",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, elec4))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(elec_4)