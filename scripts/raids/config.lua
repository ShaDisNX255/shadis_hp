-- /server/scripts/raids/config.lua
-- Unified raid configuration.
--
-- Everything that defines a raid lives in one entry:
--   - map object IDs
--   - battle progression
--   - boss settings
--   - rewards
--   - production schedule
--   - test schedule
--
-- Tiled only needs the physical objects:
--   DeferredNPC -> Next 1 points to its Dialogue object
--   Dialogue    -> Event Name = raid
--   RaidBBS     -> Visible unchecked

local Config = {}

local RAIDS = {
  Mettaur1 = {
    enabled = true,

    -- ================================================================
    -- Map placement
    -- ================================================================
    area_id            = "WCity1",
    memory_area        = "WCity1",
    display_name       = "Mettaur1 Raid",
    dialogue_object_id = 208,
    npc_object_id      = 206,
    bbs_object_id      = 209,
    done_message       = "The raid has already been cleared.",

    -- ================================================================
    -- Battle progression
    -- ================================================================
    style                 = "Repeat",
    wave2_points_required = 500,
    wave3_points_required = 350,

    boss_pool_max         = 10000,
    boss_win_damage       = 500,
    boss_encounter_hp     = 1800,
    boss_id_match         = "GrgBeast",
    repeat_cooldown_secs  = 7200,

    money_wave1 = 15000,
    money_wave2 = 25000,
    money_boss  = 35000,

    -- ================================================================
    -- Scheduler branch
    --
    -- "test"       = fixed interval below
    -- "production" = randomized daily schedule below
    -- ================================================================
    schedule_mode = "production",

    production = {
      spawns_per_day  = 4,
      defeats_per_day = 2,

      -- How long the NPC waits before somebody selects Fight.
      spawn_minutes = 15,

      -- Starts when the first player selects Fight.
      active_minutes = 45,

      -- How long the NPC/BBS remain after the boss is defeated.
      results_minutes = 30,

      -- Set true to force one immediate spawn after server startup.
      spawn_on_boot = false,
    },

    test = {
      -- A new spawn opportunity every 10 minutes.
      -- If the previous raid is still available, active, or showing results,
      -- that opportunity is skipped instead of creating an overlapping raid.
      spawn_interval_minutes = 10,

      spawn_minutes   = 1,
      active_minutes  = 2,
      results_minutes = 1,

      -- true = immediate spawn after restart, then every 10 minutes
      -- false = first spawn occurs after 10 minutes
      spawn_on_boot = true,
    },
  },
}

function Config.get_raid(raid_id)
  return RAIDS[tostring(raid_id or "")]
end

function Config.get_raids()
  return RAIDS
end

function Config.get_primary_raid_id()
  if RAIDS.Mettaur1 and RAIDS.Mettaur1.enabled ~= false then
    return "Mettaur1"
  end

  for raid_id, raid in pairs(RAIDS) do
    if type(raid) == "table" and raid.enabled ~= false then
      return raid_id
    end
  end

  return nil
end

-- ===== Reward hooks =====
-- These run for the player whose result caused the transition/defeat.

function Config.on_wave1_cleared(pid, raid_id, state)
end

function Config.on_wave2_cleared(pid, raid_id, state)
end

function Config.on_boss_defeated(pid, raid_id, state)
end

return Config
