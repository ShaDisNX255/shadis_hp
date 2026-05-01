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
      score_multiplier = 60,
    },
    health = {
      enabled = true,
      threshold = 60,
      amount = 50,
    },

    cards = {
      enabled = true,
      duplicate_fallback_score_multiplier = 60,

      drops = {
        Mettaur = {
          ["1"] = {
            chip_drop("reflecmet1", STARTER_DROP),
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

    pet_exp = 5,
    allow_duplicates = true,

    enemy_count = {
      min = 1,
      max = 2,
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
      { name = "Mettaur", ranks = { "1" } }, -- Reflect
      { name = "Spikey",  ranks = { "1" } }, -- HeatShot
      { name = "Ratty",   ranks = { "1" } }, -- Ratton1
      { name = "Shrimpy", ranks = { "1" } }, -- Bubbler
    },
  },
}
