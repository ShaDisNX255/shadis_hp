local CONSTANTS = {
  -- Set to true for Debugging mode. 
  DEBUG                  = false,
  -- Default values/Setup values
  D_BITE_TSX_CANIDATE    = "/server/fishing/ex.tsx",
  TEMPLATE_LAYER         = "Fishing",
  -- Game Feel
  PRIVATE_METERS         = true,
  VIRUS_CHANCE           = 0.30,
  VIRUS_EXCLUDED          = {
    brutal = true,
    legendary = true,
  },
  HOLD_SECONDS           = 5.0,
  MAX_DURATION_S         = 12.0,
  SWEET_WIDTH            = 2,
  BITE_WAIT_RANGE        = { min = 1.2, max = 3.0 },
  SUCCESS_RANGE          = { min = 3.0, max = 6.0 },
  WINDOW_S              = {
    light = 0.85,
    medium = 0.75,
    heavy = 0.65,
    very_heavy = 0.45,
    brutal = 0.35,
    legendary = 0.25,
  },
  HEAVINESS              = {
    --  key            decay/s   mashGain  hold_mult
    { key = "light",      decay = 1.2, mash = 1.20, hold_mult = 0.95 },
    { key = "medium",     decay = 1.8, mash = 1.00, hold_mult = 1.00 },
    { key = "heavy",      decay = 2.5, mash = 0.90, hold_mult = 1.10 },
    -- Harder tiers
    { key = "very_heavy", decay = 3.6, mash = 0.85, hold_mult = 1.15 },
    { key = "brutal",     decay = 4.8, mash = 0.80, hold_mult = 1.20 },
    { key = "legendary",  decay = 5.4, mash = 0.75, hold_mult = 1.30 },
  },
  -- Asset Paths
  ASSET_FISHING_DIR      = "/server/assets/fishing/",
  ASSET_FISH_PNG         = "/server/assets/fishing/normal-fish.png",
  ASSET_FISH_ANIM        = "/server/assets/fishing/normal-fish.animation",
  ASSET_TIMER_DIR        = "timer/",
  EX_ALERT_TSX           = "ex.tsx",
  -- Asset (METER) Properties
  FORCE_METER_SIZE       = false,
  EXPECTED_METER_SIZE    = {w = 17, h = 91},
  METER_SCREEN_SHIFT     = { x = 1.5, y = 0.0, z = 0.0 },
  -- Asset (TIMER) Properties
  FORCE_TIMER_SIZE       = false,
  EXPECTED_TIMER_SIZE    = { w = 94, h = 16 },
  TIMER_SCREEN_SHIFT     = { x = -2.0, y = -2.0, z = 0.0 },
  -- Asset (EX ALERT) Properties
  FORCE_EX_SIZE          = false,
  EXPECTED_EX_SIZE       = { w = 22, h = 22 },
  EX_SCREEN_SHIFT        = { x = -1.0, y = -1.0, z = 0.0 },
  -- Catch/Reward Values
  FISH_REWARD_PER_LB     = 700,

  PET_REWARDS = {
    jelly   = 0.03,
    piranha = 0.03,
  },

  MONEY_MULTIPLYER       = 500,
  -- Odds for each heaviness tier (percent-like weights; they don't need to sum to 100)
  HEAVINESS_CHANCES = {
    light      = 25,
    medium     = 25,
    heavy      = 25,
    very_heavy = 10,
    brutal     = 10,
    legendary  = 5,
  },

  -- Display-only: random weight ranges (in pounds) per heaviness bucket
  WEIGHT_RANGES_LB = {
    light      = { 1.0, 3.0 },
    medium     = { 3.0, 7.0 },
    heavy      = { 7.0, 12.0 },
    very_heavy = { 12.0, 18.0 },
    brutal     = { 18.0, 25.0 },
    legendary  = { 25.0, 40.0 },
  },
  BAIT = {
    VIRUS_CHANCE = 0.10,
    HEAVINESS_CHANCES = {
      light      = 20,
      medium     = 20,
      heavy      = 20,
      very_heavy = 15,
      brutal     = 15,
      legendary  = 10,
    },
  },
  BUGFRAG = {
    ITEM_NAME = "BugBait",
    VIRUS_CHANCE = 0.70,
    HEAVINESS_CHANCES = {
      light      = 30,
      medium     = 30,
      heavy      = 30,
      very_heavy = 4,
      brutal     = 4,
      legendary  = 2,
    },
  },
}

return CONSTANTS
