local CONSTANTS = {
  -- Set to true for Debugging mode. 
  DEBUG                  = false,
  -- Default values/Setup values
  D_BITE_TSX_CANIDATE    = "/server/fishing/ex.tsx",
  TEMPLATE_LAYER         = "Fishing",
  -- Game Feel
  PRIVATE_METERS         = true,
  VIRUS_CHANCE           = 0.30,
  HOLD_SECONDS           = 5.0,
  MAX_DURATION_S         = 12.0,
  SWEET_WIDTH            = 2,
  BITE_WAIT_RANGE        = { min = 1.2, max = 3.0 },
  SUCCESS_RANGE          = { min = 3.0, max = 6.0 },
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
  ASSET_NORMAL_DIR       = "normal/",
  ASSET_SWEET_DIR        = "sweet-spot/",
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
  FISH_REWARD_PER_LB     = 1800,
  MONEY_MULTIPLYER       = 5000,  
}

return CONSTANTS