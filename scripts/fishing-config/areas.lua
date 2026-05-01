-- /server/scripts/fishing-config/areas.lua

local E = require('scripts/fishing-config/encounters')
local helpers = require('scripts/ezlibs-scripts/helpers')

local function with_weight(enc, w)
  local x = helpers.deep_copy(enc)
  x.weight = w
  return x
end

return {
  fisharea = {
    CONSTANTS = {
      LEADERBOARD           = {
        ENABLED  = true,
        MEM_AREA = "fisharea",
        KEY      = "fish_top10_v5",
        MAX      = 10,
        UNIQUE_PER = "secret",
      },
    },
    FISHING_VIRUS = {
      E.encounter1,
      E.encounter2,
      E.encounter3,
    },
  },
  rink = {
    CONSTANTS = {
      PET_REWARDS = {
        jelly   = 0.03,
        piranha = 0.03,
      },
      LEADERBOARD           = {
        ENABLED  = true,
        MEM_AREA = "rink",
        KEY      = "rink_top5_v2",
        MAX      = 5,
        UNIQUE_PER = "secret",
      },
      VIRUS_CHANCE           = 0.28,
      ASSET_FISH_PNG         = "/server/assets/fishing/icy-fish.png",
      ASSET_FISH_ANIM        = "/server/assets/fishing/icy-fish.animation",
      EXPECTED_METER_SIZE    = {w = 24, h = 93},
      METER_SCREEN_SHIFT     = { x = 1.75, y = 0.0, z = 0.0 },
      WINDOW_S              = {
        light = 0.95,
        medium = 0.85,
        heavy = 0.75,
        very_heavy = 0.55,
        brutal = 0.45,
        legendary = 0.35,
      },
      HEAVINESS              = {
          --  key            decay/s   mashGain  hold_mult
        { key = "light",      decay = 1.2, mash = 1.20, hold_mult = 0.85 },
        { key = "medium",     decay = 1.8, mash = 1.00, hold_mult = 0.90 },
        { key = "heavy",      decay = 2.5, mash = 0.90, hold_mult = 1.00 },
        -- Harder tiers
        { key = "very_heavy", decay = 3.6, mash = 0.85, hold_mult = 1.05 },
        { key = "brutal",     decay = 4.8, mash = 0.80, hold_mult = 1.10 },
        { key = "legendary",  decay = 5.4, mash = 0.75, hold_mult = 1.20 },
      },
      WEIGHT_RANGES_LB = {
        light      = { 2.0, 4.0 },
        medium     = { 4.0, 8.0 },
        heavy      = { 8.0, 13.0 },
        very_heavy = { 13.0, 19.0 },
        brutal     = { 19.0, 26.0 },
        legendary  = { 26.0, 41.0 },
      },
      VIRUS_EXCLUDED          = {
        heavy      = true,
        very_heavy = true,
        brutal     = true,
        legendary  = true,
      },
      HEAVINESS_CHANCES = {
        light      = 20,
        medium     = 20,
        heavy      = 20,
        very_heavy = 15,
        brutal     = 15,
        legendary  = 10,
      },
      BITE_WAIT_RANGE        = { min = 7, max = 12.0 },
      BAIT = {
        VIRUS_CHANCE = 0.08,
        HEAVINESS_CHANCES = {
          light      = 15,
          medium     = 15,
          heavy      = 15,
          very_heavy = 20,
          brutal     = 20,
          legendary  = 15,
        },
      },
    },
    FISHING_VIRUS = {
      with_weight(E.encounter4, 1),
      with_weight(E.encounter5, 20),
      with_weight(E.encounter6, 1),
      with_weight(E.encounter7, 20),
    },
  },
  rink2 = {
    CONSTANTS = {
      PET_REWARDS = {
        jelly   = 0.03,
        piranha = 0.03,
      },
      VIRUS_CHANCE           = 0.26,
      ASSET_FISH_PNG         = "/server/assets/fishing/icy-fish.png",
      ASSET_FISH_ANIM        = "/server/assets/fishing/icy-fish.animation",
      EXPECTED_METER_SIZE    = {w = 24, h = 93},
      METER_SCREEN_SHIFT     = { x = 1.75, y = 0.0, z = 0.0 },
      WINDOW_S              = {
        light = 0.95,
        medium = 0.85,
        heavy = 0.75,
        very_heavy = 0.55,
        brutal = 0.45,
        legendary = 0.35,
      },
      HEAVINESS              = {
          --  key            decay/s   mashGain  hold_mult
        { key = "light",      decay = 1.1, mash = 1.20, hold_mult = 0.85 },
        { key = "medium",     decay = 1.7, mash = 1.00, hold_mult = 0.90 },
        { key = "heavy",      decay = 2.4, mash = 0.90, hold_mult = 1.00 },
        -- Harder tiers
        { key = "very_heavy", decay = 3.5, mash = 0.85, hold_mult = 1.05 },
        { key = "brutal",     decay = 4.7, mash = 0.80, hold_mult = 1.10 },
        { key = "legendary",  decay = 5.3, mash = 0.75, hold_mult = 1.20 },
      },
      WEIGHT_RANGES_LB = {
        light      = { 3.0, 5.0 },
        medium     = { 5.0, 9.0 },
        heavy      = { 9.0, 14.0 },
        very_heavy = { 14.0, 20.0 },
        brutal     = { 20.0, 27.0 },
        legendary  = { 27.0, 42.0 },
      },
      VIRUS_EXCLUDED          = {
        heavy      = true,
        very_heavy = true,
        brutal     = true,
        legendary  = true,
      },
      HEAVINESS_CHANCES = {
        light      = 18,
        medium     = 18,
        heavy      = 18,
        very_heavy = 17,
        brutal     = 17,
        legendary  = 12,
      },
      BITE_WAIT_RANGE        = { min = 7, max = 12.0 },
      BAIT = {
        VIRUS_CHANCE = 0.07,
        HEAVINESS_CHANCES = {
          light      = 13,
          medium     = 13,
          heavy      = 13,
          very_heavy = 22,
          brutal     = 22,
          legendary  = 17,
        },
      },
    },
    FISHING_VIRUS = {
      with_weight(E.encounter4, 2),
      with_weight(E.encounter5, 18),
      with_weight(E.encounter6, 2),
      with_weight(E.encounter7, 18),
    },
  },
  rink3 = {
    CONSTANTS = {
      PET_REWARDS = {
        jelly   = 0.04,
        piranha = 0.04,
      },
      LEADERBOARD           = {
        ENABLED  = true,
        MEM_AREA = "rink3",
        KEY      = "rink3_top5_v2",
        MAX      = 5,
        UNIQUE_PER = "secret",
      },
      VIRUS_CHANCE           = 0.24,
      ASSET_FISH_PNG         = "/server/assets/fishing/icy-fish.png",
      ASSET_FISH_ANIM        = "/server/assets/fishing/icy-fish.animation",
      EXPECTED_METER_SIZE    = {w = 24, h = 93},
      METER_SCREEN_SHIFT     = { x = 1.75, y = 0.0, z = 0.0 },
      WINDOW_S              = {
        light = 0.95,
        medium = 0.85,
        heavy = 0.75,
        very_heavy = 0.55,
        brutal = 0.45,
        legendary = 0.35,
      },
      HEAVINESS              = {
          --  key            decay/s   mashGain  hold_mult
        { key = "light",      decay = 1.0, mash = 1.20, hold_mult = 0.80 },
        { key = "medium",     decay = 1.6, mash = 1.00, hold_mult = 0.85 },
        { key = "heavy",      decay = 2.3, mash = 0.90, hold_mult = 0.95 },
        -- Harder tiers
        { key = "very_heavy", decay = 3.4, mash = 0.85, hold_mult = 1.00 },
        { key = "brutal",     decay = 4.6, mash = 0.80, hold_mult = 1.05 },
        { key = "legendary",  decay = 5.2, mash = 0.75, hold_mult = 1.15 },
      },
      WEIGHT_RANGES_LB = {
        light      = { 4.0, 6.0 },
        medium     = { 6.0, 10.0 },
        heavy      = { 10.0, 15.0 },
        very_heavy = { 15.0, 21.0 },
        brutal     = { 21.0, 28.0 },
        legendary  = { 28.0, 43.0 },
      },
      VIRUS_EXCLUDED          = {
        heavy      = true,
        very_heavy = true,
        brutal     = true,
        legendary  = true,
      },
      HEAVINESS_CHANCES = {
        light      = 17,
        medium     = 17,
        heavy      = 17,
        very_heavy = 18,
        brutal     = 18,
        legendary  = 13,
      },
      BITE_WAIT_RANGE        = { min = 7, max = 12.0 },
      BAIT = {
        VIRUS_CHANCE = 0.06,
        HEAVINESS_CHANCES = {
          light      = 12,
          medium     = 12,
          heavy      = 12,
          very_heavy = 23,
          brutal     = 23,
          legendary  = 18,
        },
      },
    },
    FISHING_VIRUS = {
      with_weight(E.encounter4, 3),
      with_weight(E.encounter5, 17),
      with_weight(E.encounter6, 3),
      with_weight(E.encounter7, 17),
    },
  },
}