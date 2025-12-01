-- /server/scripts/raids/config.lua
-- Pure configuration + reward hooks (no external dependencies beyond ezlibs).
-- Server owners: tweak defaults here. You can also override per-NPC via Dialogue custom properties.

local Config = {}

-- Defaults by raid id (you can duplicate the "default" block to create presets)
local DEFAULTS = {
  -- Mettaur raid
  Mettaur1 = {
    style                 = "Repeat",
    wave2_points_required = 500,
    wave3_points_required = 350,
    boss_pool_max         = 10000,
    boss_win_damage       = 500,
    boss_encounter_hp     = 1800,
    boss_id_match         = "GrgBeast",  -- matches GregarBeast boss
    repeat_cooldown_secs  = 7200,
    raid_memory_area      = "WCity1",
    money_wave1           = 50000,
    money_wave2           = 75000,
    money_boss            = 90000,
  },

  Swordy1 = {
    style                 = "Repeat",  -- or "Once"
    wave2_points_required = 300,       -- W1 -> W2 threshold
    wave3_points_required = 150,       -- W2 -> Boss threshold
    boss_pool_max         = 15000,     -- shared HP pool for this boss
    boss_win_damage       = 700,       -- fallback per win
    boss_encounter_hp     = 800,      -- HP in a single encounter
    boss_id_match         = "Quickman",
    repeat_cooldown_secs  = 14400,
    raid_memory_area      = "WCity2",
    money_wave1           = 70000,
    money_wave2           = 80000,
    money_boss            = 100000,
  },

  -- Fallback if some raid_id has no preset
  default = {
    style                 = "Repeat",
    wave2_points_required = 500,
    wave3_points_required = 350,
    boss_pool_max         = 10000,
    boss_win_damage       = 500,
    boss_encounter_hp     = 1800,
    boss_id_match         = "GrgBeast",
    repeat_cooldown_secs  = 7200,
    raid_memory_area      = "WCity1",
  },
}

function Config.get_defaults(raid_id)
  return (DEFAULTS[raid_id] and DEFAULTS[raid_id]) or DEFAULTS.default
end

-- ===== Reward hooks (intentionally no-ops by default) =====
-- Called on the player who triggered the transition/kill.
function Config.on_wave1_cleared(pid, raid_id, state)
  -- Example:
  -- Net.message_player(pid, "[DEBUG] wave1 cleared reward hook")
end

function Config.on_wave2_cleared(pid, raid_id, state)
  -- Example:
  -- Net.message_player(pid, "[DEBUG] wave2 cleared reward hook")
end

function Config.on_boss_defeated(pid, raid_id, state)
  -- Example:
  -- Net.message_player(pid, "[DEBUG] boss defeated reward hook")
end

return Config
