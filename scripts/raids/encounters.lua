-- /server/scripts/raids/encounters.lua
-- Raids encounters — all-in-one (E1..E6 + boss) wired directly here.

local Enc = { _packs = {} }

-- Register a list for a raid+wave (wave: 1, 2, or 3 for boss)
function Enc.register(raid_id, wave, list)
  raid_id = tostring(raid_id or "default")
  if wave ~= 1 and wave ~= 2 and wave ~= 3 then error("Enc.register: wave must be 1, 2, or 3") end
  Enc._packs[raid_id] = Enc._packs[raid_id] or { [1]={}, [2]={}, [3]={} }
  Enc._packs[raid_id][wave] = list or {}
end

function Enc.get_pack(raid_id, wave)
  raid_id = tostring(raid_id or "default")
  local p = Enc._packs[raid_id]
  return p and p[wave] or nil
end

-- ===== Actual encounter specs (copied from your old_encounters.lua) =====

local E1 = {
    name="E1",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    enemies={
        {name="Mettaur",rank=3},
        {name="Mettaur",rank=2},
        {name="Mettaur",rank=1},
    },
    obstacles={
        {name="Rock"},
        {name="Rock"},
        {name="Rock"},
        {name="Rock"},
    },
    positions={
        {0,0,0,3,2,0},
        {0,0,0,0,3,1},
        {0,0,0,3,2,0},
    },
    obstacle_positions={
        {0,0,4,0,0,0},
        {0,0,0,3,0,0},
        {0,0,2,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {1,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,1,1,1,1},
        {2,2,1,1,1,1},
        {2,2,1,1,1,1},
    },
}

local E2 = {
    name="E2",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    enemies={
        {name="Mettaur",rank=3},
        {name="Mettaur",rank=1},
    },
    obstacles={
        {name="Rock"},
        {name="Rock"},
        {name="Rock"},
        {name="Rock"},
        {name="Rock"},
        {name="Rock"},
    },
    positions={
        {0,0,0,2,2,1},
        {0,0,0,2,2,0},
        {0,0,0,2,2,0},
    },
    obstacle_positions={
        {0,0,4,0,0,0},
        {0,0,5,0,0,0},
        {0,0,6,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {1,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,1,1,1,1},
        {2,2,1,1,1,1},
        {2,2,1,1,1,1},
    },
}

local E3 = {
    name="E3",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    enemies={
        {name="Mettaur",rank=3},
        {name="Mettaur",rank=2},
        {name="Mettaur",rank=1},
    },
    obstacles={
        {name="Rock"},
        {name="Rock"},
        {name="Rock"},
    },
    positions={
        {0,0,0,2,3,3},
        {0,0,0,3,2,0},
        {0,0,0,0,3,1},
    },
    obstacle_positions={
        {0,2,0,0,0,0},
        {0,0,1,0,0,0},
        {0,0,0,3,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {1,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,1,1,1,1,1},
        {2,2,1,1,1,1},
        {2,2,1,1,1,1},
    },
}

local E4 = {
    name="E4",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    enemies={
        {name="Mettaur",rank=3},
        {name="Mettaur",rank=4},
        {name="Mettaur",rank=1},
        {name="Mettaur",rank=6},
    },
    obstacles={
    },
    positions={
        {0,0,0,4,3,1},
        {0,0,0,0,3,2},
        {0,0,0,1,3,0},
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
}

local E5 = {
    name="E5",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    enemies={
        {name="Mettaur",rank=4},
        {name="Mettaur",rank=2},
        {name="Mettaur",rank=7},
    },
    obstacles={
        {name="Rock"},
        {name="Rock"},
        {name="Rock"},
    },
    positions={
        {0,0,0,0,2,1},
        {0,0,0,0,2,3},
        {0,0,0,0,2,1},
    },
    obstacle_positions={
        {0,0,0,1,0,0},
        {0,0,0,2,0,0},
        {0,0,0,3,0,0},
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
}

local E6 = {
    name="E6",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    enemies={
        {name="Mettaur",rank=4},
        {name="Mettaur",rank=7},
        {name="Mettaur",rank=6},
    },
    obstacles={
        {name="Rock"},
        {name="Rock"},
    },
    positions={
        {0,0,0,3,0,1},
        {0,0,0,1,0,2},
        {0,0,0,0,1,0},
    },
    obstacle_positions={
        {0,0,0,0,1,0},
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
}

local boss = {
    name="boss",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=10,
    enemies={
        {name="Mettaur",rank=7},
        {name="Mettaur",rank=6},
        {name="GregarBeast",rank=4},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,1,3,0},
        {0,0,0,0,0,2},
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
}

-- Register for raid id "default": Wave1 = E1/E2/E3, Wave2 = E4/E5/E6, Boss = boss
Enc.register("Mettaur1", 1, { E1, E2, E3 })
Enc.register("Mettaur1", 2, { E4, E5, E6 })
Enc.register("Mettaur1", 3, { boss })

return Enc
