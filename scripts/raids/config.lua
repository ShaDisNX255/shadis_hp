-- /server/scripts/raids/config.lua
-- Pure configuration + reward hooks (no external dependencies beyond ezlibs).
-- Server owners: tweak defaults here. You can also override per-NPC via Dialogue custom properties.

local Config = {}

-- Defaults by raid id (you can duplicate the "default" block to create presets)
local DEFAULTS = {
  default = {
    style                 = "Repeat",  -- "Repeat" or "Once"
    wave2_points_required = 500,        -- points to clear wave 1
    wave3_points_required = 350,        -- points to clear wave 2
    boss_pool_max         = 10000,     -- shared boss HP pool
    boss_win_damage       = 500,       -- applied when the player wins and stats don't expose damage
    -- how much HP the boss has **in a single encounter**
    boss_encounter_hp = 1800,

    -- substring to identify the boss in stats.enemies[k].id
    -- tip: use a short, plain substring to dodge weird characters, e.g. "GrgBeast" or "GregarBeast"
    boss_id_match = "GrgBeast",
    repeat_cooldown_secs = 1800,  -- 30 minutes default for Repeat raids
    raid_memory_area = "WCity1",
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
