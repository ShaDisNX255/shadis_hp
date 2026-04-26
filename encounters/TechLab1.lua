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

local RARE_DROP = {
  [11] = 0.35, -- S
  [10] = 0.25,
  [9]  = 0.15,
  [8]  = 0.08,
  [7]  = 0.04,
}

local function chip_drop(card, chances)
  return {
    card = card,
    score_chances = chances,
  }
end

return {
  minimum_steps_before_encounter = 50,
  encounter_chance_per_step = 0.10,

  encounters = {},

  rewards = {
    enabled = true,
    money = {
      enabled = true,
      score_multiplier = 120,
    },
    health = {
      enabled = true,
      threshold = 90,
      amount = 50,
    },

    cards = {
      enabled = true,
      duplicate_fallback_score_multiplier = 80,

      drops = {
        Boomer = {
          ["2"] = {
            chip_drop("boomerang2", UNCOMMON_DROP),
          },
        },

        Quaker = {
          ["1"] = {
            chip_drop("wavearm", RARE_DROP),
          },
        },

        Gunner = {
          ["1"] = {
            chip_drop("MachineGun1", RARE_DROP),
          },
        },

        KillerEye = {
          ["1"] = {
            chip_drop("KillerSensor1", RARE_DROP),
          },
        },

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

    pet_exp = 8,
    allow_duplicates = true,

    enemy_count = {
      min = 3,
      max = 4,
    },

    obstacles = {
      enabled = false,
    },

    panels = {
      enabled = true,
      pool = { 13 }, -- lava only
      chance = 0.45,
      min = 1,
      max = 3,
    },

    bosses = {
      enabled = false,
    },

    results_callback = notify_jobbbs,

    pool = {
      { name = "Boomer",    ranks = { "2" } },      -- Boomerang2
      { name = "Quaker",    ranks = { "1" } },      -- rare WaveArm
      { name = "Gunner",    ranks = { "1" } },      -- rare MachineGun1
      { name = "KillerEye", ranks = { "1" } },      -- rare KillerSensor1
      { name = "Mettaur",   ranks = { "2" } },      -- old filler: SonicWave
      { name = "Ratty",     ranks = { "2" } },      -- old filler: Ratton2
      { name = "Fishy",     ranks = { "1" } },      -- old filler: DashAtk
      { name = "Volcano",   ranks = { "1", "2" } }, -- no chip; lava synergy
      { name = "Metrid",    ranks = { "1" } },      -- no chip filler
      { name = "MegaCorn",  ranks = { "1" } },      -- no chip filler for now
    },
  },
}
