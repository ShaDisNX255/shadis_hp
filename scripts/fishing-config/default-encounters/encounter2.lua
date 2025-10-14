  local encounter2 = {
      name               = "Encounter2",
      weight             = 10,
      path               = "/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
      enemies            = {
        { name = "Piranha",  rank = 4 },
        { name = "ColdHead", rank = 1 },
        { name = "Tark",     rank = 1 },
      },
      obstacles          = {
        { name = "Rock" },
      },
      positions          = {
        { 0, 0, 0, 0, 0, 2 },
        { 0, 0, 0, 0, 1, 3 },
        { 0, 0, 0, 0, 0, 0 },
      },
      obstacle_positions = {
        { 0, 0, 0, 0, 0, 0 },
        { 0, 0, 0, 0, 0, 0 },
        { 0, 0, 0, 0, 0, 0 },
      },
      player_positions   = {
        { 0, 0, 0, 0, 0, 0 },
        { 0, 1, 0, 0, 0, 0 },
        { 0, 0, 0, 0, 0, 0 },
      },
      tiles              = {
        { 1, 1, 1, 1, 1, 1 },
        { 1, 1, 1, 1, 1, 1 },
        { 1, 1, 1, 1, 1, 1 },
      },
      teams              = {
        { 2, 2, 2, 1, 1, 1 },
        { 2, 2, 2, 1, 1, 1 },
        { 2, 2, 2, 1, 1, 1 },
      },
    }
return encounter2