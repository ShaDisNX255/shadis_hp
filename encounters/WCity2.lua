local JobBBS = (function()
  local ok, M = pcall(require, 'scripts/jobbbs/JobBBS')
  if ok and M then return M end
  ok, M = pcall(require, 'scripts/jobbbs/jobbbs') -- fallback name if needed
  return ok and M or nil
end)()

-- Keep the JobBBS encounter-result hook.
-- Rewards themselves are handled by the area-level "rewards" config below,
-- so this callback intentionally does NOT grant money/HP again.
local function notify_jobbbs(player_id, encounter_info, stats)
  if JobBBS and JobBBS.on_encounter_result then
    pcall(JobBBS.on_encounter_result, player_id, stats)
  end
end

return {
  minimum_steps_before_encounter = 40,
  encounter_chance_per_step = 0.10,

  -- No more static/repetitive formations
  encounters = {},

  -- Keep current reward behavior:
  -- money = busting level * 100
  -- +50 HP if post-battle HP <= 20
  rewards = {
    enabled = true,
    money = {
      enabled = true,
      score_multiplier = 80,
    },
    health = {
      enabled = true,
      threshold = 30,
      amount = 50,
    },

    cards = {
      enabled = true,

      -- If the selected chip was already unlocked, give money instead.
      duplicate_fallback_score_multiplier = 60,

      drops = {
        Yort = {
          ["1"] = {
            {
              card = "yoyo1",
              score_chances = {
                [11] = 0.90,
                [10] = 0.80,
                [9] = 0.75,
                [8] = 0.70,
              },
            },
          },
        },

        OldStove = {
          ["1"] = {
            {
              card = "HellsBurner1",
              score_chances = {
                [11] = 0.90,
                [10] = 0.80,
                [9] = 0.75,
                [8] = 0.70,
              },
            },
          },
        },

        Gunner = {
          ["1"] = {
            {
              card = "MachineGun1",
              score_chances = {
                [11] = 0.90,
                [10] = 0.80,
                [9] = 0.75,
                [8] = 0.70,
              },
            },
          },
        },

        Shooter = {
          ["1"] = {
            {
              card = "MachineGun2",
              score_chances = {
                [11] = 0.80,
                [10] = 0.70,
                [9] = 0.65,
                [8] = 0.60,
              },
            },
          },
        },

        Swordy = {
          ["1"] = {
            {
              card = "longsword",
              score_chances = {
                [11] = 0.90,
                [10] = 0.80,
                [9] = 0.75,
                [8] = 0.70,
              },
            },
          },
        },

        KillerEye = {
          ["1"] = {
            {
              card = "KillerSensor1",
              score_chances = {
                [11] = 0.90,
                [10] = 0.80,
                [9] = 0.75,
                [8] = 0.70,
              },
            },
          },
        },

        DemonEye = {
          ["1"] = {
            {
              card = "KillerSensor2",
              score_chances = {
                [11] = 0.90,
                [10] = 0.80,
                [9] = 0.75,
                [8] = 0.70,
              },
            },
          },
        },

        Shrimpy = {
          ["1"] = {
            {
              card = "bubbler",
              score_chances = {
                [11] = 0.90,
                [10] = 0.80,
                [9] = 0.75,
                [8] = 0.70,
              },
            },
          },
        },

        Bunny = {
          ["1"] = {
            {
              card = "RabiRing1",
              score_chances = {
                [11] = 0.90,
                [10] = 0.80,
                [9] = 0.75,
                [8] = 0.70,
              },
            },
          },
        },

        TuffBunny = {
          ["1"] = {
            {
              card = "RabiRing2",
              score_chances = {
                [11] = 0.90,
                [10] = 0.80,
                [9] = 0.75,
                [8] = 0.70,
              },
            },
          },
        },

        Ratty = {
          ["1"] = {
            {
              card = "ratton1",
              score_chances = {
                [11] = 0.90,
                [10] = 0.80,
                [9] = 0.75,
                [8] = 0.70,
              },
            },
          },
          ["2"] = {
            {
              card = "Ratton2",
              score_chances = {
                [11] = 0.90,
                [10] = 0.80,
                [9] = 0.75,
                [8] = 0.70,
              },
            },
          },
        },

        Mettaur = {
          ["2"] = {
            {
              card = "sonicwave",
              score_chances = {
                [11] = 0.90, -- S
                [10] = 0.80,
              },
            },
          },
        },

      },
    },
  },

  -- Best-effort JobBBS hook in case your random builder carries callbacks through
  results_callback = notify_jobbbs,

  random_encounters = {
    enabled = true,
    package_path = "/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",

    -- Make this area fully random
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

    -- Keep it simple for now
    obstacles = {
      enabled = false,
    },

    panels = {
      enabled = false,
    },

    bosses = {
      enabled = false,
    },

    -- Best-effort JobBBS hook for builders that copy callback from here
    results_callback = notify_jobbbs,

    -- All rank 1 only
    pool = {
      { name = "Yort",       ranks = { "1" } },
      { name = "OldStove",   ranks = { "1" } },
      { name = "Gunner",     ranks = { "1" } },
      { name = "Shooter",    ranks = { "1" } },
      { name = "Swordy",     ranks = { "1" } },
      { name = "KillerEye",  ranks = { "1" } },
      { name = "DemonEye",   ranks = { "1" } },
      { name = "Shrimpy",    ranks = { "1" } },
      { name = "Bunny",      ranks = { "1" } },
      { name = "TuffBunny",  ranks = { "1" } },
      { name = "Ratty",      ranks = { "1", "2" } },
      { name = "Mettaur",    ranks = { "2" } },
    },
  },
}