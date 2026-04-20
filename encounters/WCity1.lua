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
      score_multiplier = 60,
    },
    health = {
      enabled = true,
      threshold = 60,
      amount = 50,
    },

    cards = {
      enabled = true,

      -- If the selected chip was already unlocked, give money instead.
      duplicate_fallback_score_multiplier = 60,

      drops = {
        Mettaur = {
          ["1"] = {
            {
              card = "reflecmet1",
              score_chances = {
                [11] = 0.90, -- S
                [10] = 0.75,
              },
            },
            {
              card = "shockwave",
              score_chances = {
                [9] = 0.60,
                [8] = 0.45,
                [7] = 0.30,
                [6] = 0.20,
                [5] = 0.10,
                [4] = 0.05,
              },
            },
          },
        },

        Swordy = {
          ["1"] = {
            {
              card = "longsword",
              score_chances = {
                [11] = 0.90, -- S
                [10] = 0.75,
                [9] = 0.60,
                [8] = 0.45,
                [7] = 0.30,
                [6] = 0.20,
                [5] = 0.10,
                [4] = 0.05,
              },
            },
          },
        },

        Shrimpy = {
          ["1"] = {
            {
              card = "bubbler",
              score_chances = {
                [11] = 0.90, -- S
                [10] = 0.75,
                [9] = 0.60,
                [8] = 0.45,
                [7] = 0.30,
                [6] = 0.20,
                [5] = 0.10,
                [4] = 0.05,
              },
            },
          },
        },

        Ratty = {
          ["1"] = {
            {
              card = "ratton1",
              score_chances = {
                [11] = 0.90, -- S
                [10] = 0.75,
                [9] = 0.60,
                [8] = 0.45,
                [7] = 0.30,
                [6] = 0.20,
                [5] = 0.10,
                [4] = 0.05,
              },
            },
          },
        },

        VacuumFan = {
          ["1"] = {
            {
              card = "windbox",
              score_chances = {
                [11] = 0.90, -- S
                [10] = 0.75,
                [9] = 0.60,
                [8] = 0.45,
                [7] = 0.30,
                [6] = 0.20,
                [5] = 0.10,
                [4] = 0.05,
              },
            },
          },
        },

        Bunny = {
          ["1"] = {
            {
              card = "RabiRing1",
              score_chances = {
                [11] = 0.90, -- S
                [10] = 0.75,
                [9] = 0.60,
                [8] = 0.45,
                [7] = 0.30,
                [6] = 0.20,
                [5] = 0.10,
                [4] = 0.05,
              },
            },
          },
        },

        Spikey = {
          ["1"] = {
            {
              card = "heatshot",
              score_chances = {
                [11] = 0.90, -- S
                [10] = 0.75,
                [9] = 0.60,
                [8] = 0.45,
                [7] = 0.30,
                [6] = 0.20,
                [5] = 0.10,
                [4] = 0.05,
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
      { name = "Mettaur",    ranks = { "1" } },
      { name = "Swordy",     ranks = { "1" } },
      { name = "Shrimpy",    ranks = { "1" } },
      { name = "Spikey",     ranks = { "1" } },
      { name = "Ratty",      ranks = { "1" } },
      { name = "Bunny",      ranks = { "1" } },
    },
  },
}