   local encounter3 = {
      name               = "Encounter3",
      weight             = 10,
      path               = "/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
      enemies            = {
        { name = "SwordyEl", rank = 5 },
        { name = "SwordyEl", rank = 2 },
        { name = "SwordyEl", rank = 8 },
      },
      obstacles          = {
      },
      positions          = {
        { 0, 0, 0, 0, 3, 0 },
        { 0, 0, 0, 0, 1, 0 },
        { 0, 0, 0, 0, 2, 0 },
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
      music              = { path = "bn6_battle_xg.mid" },
    }
return encounter3