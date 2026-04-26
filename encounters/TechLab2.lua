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
  [11] = 0.80, -- S
  [10] = 0.65,
  [9]  = 0.45,
  [8]  = 0.30,
  [7]  = 0.18,
  [6]  = 0.10,
  [5]  = 0.05,
}

local COMMON_DROP = {
  [11] = 0.75, -- S
  [10] = 0.55,
  [9]  = 0.40,
  [8]  = 0.25,
  [7]  = 0.15,
  [6]  = 0.08,
  [5]  = 0.04,
}

local UNCOMMON_DROP = {
  [11] = 0.55, -- S
  [10] = 0.40,
  [9]  = 0.25,
  [8]  = 0.15,
  [7]  = 0.08,
  [6]  = 0.04,
}

local function chip_drop(card, chances)
  return {
    card = card,
    score_chances = chances,
  }
end

return {
  minimum_steps_before_encounter = 45,
  encounter_chance_per_step = 0.10,

  encounters = {},

  rewards = {
    enabled = true,
    money = {
      enabled = true,
      score_multiplier = 105,
    },
    health = {
      enabled = true,
      threshold = 80,
      amount = 50,
    },

    cards = {
      enabled = true,
      duplicate_fallback_score_multiplier = 60,

      drops = {
        Mettaur = {
          ["2"] = {
            chip_drop("sonicwave", COMMON_DROP),
          },
        },

        Ratty = {
          ["2"] = {
            chip_drop("Ratton2", COMMON_DROP),
          },
        },

        Fishy = {
          ["1"] = {
            chip_drop("dashatk", UNCOMMON_DROP),
          },
        },

        Boomer = {
          ["1"] = {
            chip_drop("boomerang1", UNCOMMON_DROP),
          },
        },

        OldStove = {
          ["1"] = {
            chip_drop("HellsBurner1", COMMON_DROP),
          },
        },

        VacuumFan = {
          ["1"] = {
            chip_drop("windbox", COMMON_DROP),
          },
        },

        Shrimpy = {
          ["1"] = {
            chip_drop("bubbler", STARTER_DROP),
          },
        },

        Spikey = {
          ["1"] = {
            chip_drop("heatshot", STARTER_DROP),
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

    pet_exp = 7,
    allow_duplicates = true,

    enemy_count = {
      min = 2,
      max = 3,
    },

    obstacles = {
      enabled = false,
    },

    panels = {
      enabled = true,
      pool = { 13 }, -- lava only
      chance = 0.30,
      min = 1,
      max = 2,
    },

    bosses = {
      enabled = false,
    },

    results_callback = notify_jobbbs,

    pool = {
      { name = "Mettaur",   ranks = { "2" } }, -- SonicWave
      { name = "Ratty",     ranks = { "2" } }, -- Ratton2
      { name = "Fishy",     ranks = { "1" } }, -- DashAtk
      { name = "Boomer",    ranks = { "1" } }, -- Boomerang1
      { name = "OldStove",  ranks = { "1" } }, -- old filler: HellsBurner1
      { name = "VacuumFan", ranks = { "1" } }, -- old filler: WindBox
      { name = "Shrimpy",   ranks = { "1" } }, -- old filler: Bubbler
      { name = "Spikey",    ranks = { "1" } }, -- old filler: HeatShot
      { name = "Volcano",   ranks = { "1" } }, -- no chip; lava synergy
    },
  },
}
