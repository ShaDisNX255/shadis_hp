local JobBBS = (function()
  local ok, M = pcall(require, 'scripts/jobbbs/JobBBS')
  if ok and M then return M end
  ok, M = pcall(require, 'scripts/jobbbs/jobbbs')
  return ok and M or nil
end)()

local function notify_jobbbs(player_id, encounter_info, stats)
  if JobBBS and JobBBS.on_encounter_result then
    pcall(JobBBS.on_encounter_result, player_id, stats)
  end
end

local STARTER_DROP = {
  [11] = 0.90, -- S
  [10] = 0.80,
  [9]  = 0.75,
  [8]  = 0.65,
  [7]  = 0.50,
  [6]  = 0.35,
  [5]  = 0.25,
}

local COMMON_DROP = {
  [11] = 0.85, -- S
  [10] = 0.75,
  [9]  = 0.70,
  [8]  = 0.60,
  [7]  = 0.45,
  [6]  = 0.30,
  [5]  = 0.25,
}

local VERY_RARE_DROP = {
  [11] = 0.70, -- S
  [10] = 0.60,
  [9]  = 0.55,
  [8]  = 0.45,
}

local function chip_drop(card, chances)
  return {
    card = card,
    score_chances = chances,
  }
end

return {
  minimum_steps_before_encounter = 40,
  encounter_chance_per_step = 0.10,

  encounters = {},

  rewards = {
    enabled = true,
    money = {
      enabled = true,
      score_multiplier = 70,
    },
    health = {
      enabled = true,
      threshold = 70,
      amount = 50,
    },

    cards = {
      enabled = true,
      duplicate_fallback_score_multiplier = 70,

      drops = {
        Mettaur = {
          ["1"] = {
            chip_drop("shockwave", COMMON_DROP),
          },
        },

        Swordy = {
          ["1"] = {
            chip_drop("longsword", COMMON_DROP),
          },
        },

        VacuumFan = {
          ["1"] = {
            chip_drop("windbox", COMMON_DROP),
          },
        },

        OldStove = {
          ["1"] = {
            chip_drop("HellsBurner1", COMMON_DROP),
          },
        },

        Bunny = {
          ["1"] = {
            chip_drop("RabiRing1", VERY_RARE_DROP),
          },
        },

        Spikey = {
          ["1"] = {
            chip_drop("heatshot", STARTER_DROP),
          },
        },

        Ratty = {
          ["1"] = {
            chip_drop("ratton1", STARTER_DROP),
          },
        },

        Shrimpy = {
          ["1"] = {
            chip_drop("bubbler", STARTER_DROP),
          },
        },
      },
    },
  },

  results_callback = notify_jobbbs,

  random_encounters = {
    enabled = true,
    package_path = "/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",

    source_weights = {
      static = 0,
      random = 100,
    },

    pet_exp = 6,
    allow_duplicates = true,

    enemy_count = {
      min = 2,
      max = 3,
    },

    obstacles = {
      enabled = false,
    },

    panels = {
      enabled = false,
    },

    bosses = {
      enabled = false,
    },

    results_callback = notify_jobbbs,

    pool = {
      { name = "Mettaur",   ranks = { "1" } }, -- ShockWave
      { name = "Spikey",    ranks = { "1" } }, -- old filler: HeatShot
      { name = "Ratty",     ranks = { "1" } }, -- old filler: Ratton1
      { name = "Shrimpy",   ranks = { "1" } }, -- old filler: Bubbler
      { name = "Swordy",    ranks = { "1" } }, -- LongSword
      { name = "VacuumFan", ranks = { "1" } }, -- WindBox
      { name = "OldStove",  ranks = { "1" } }, -- HellsBurner1
      { name = "Bunny",     ranks = { "1" } }, -- rare RabiRing1
    },
  },
}
