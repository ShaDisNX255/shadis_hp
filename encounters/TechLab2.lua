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

local STARTER_DROP = { [11]=0.90,[10]=0.80,[9]=0.75,[8]=0.65,[7]=0.50,[6]=0.35,[5]=0.25 }
local COMMON_DROP = { [11]=0.85,[10]=0.75,[9]=0.70,[8]=0.60,[7]=0.45,[6]=0.30,[5]=0.25 }
local UNCOMMON_DROP = { [11]=0.80,[10]=0.70,[9]=0.65,[8]=0.55,[7]=0.40,[6]=0.25 }
local function chip_drop(card, chances) return { card=card, score_chances=chances } end

return {
  minimum_steps_before_encounter=45,
  encounter_chance_per_step=0.10,
  encounters={},
  rewards={
    enabled=true,
    money={ enabled=true, score_multiplier=80 },
    health={ enabled=true, threshold=80, amount=50 },
    cards={
      enabled=true,
      duplicate_fallback_score_multiplier=80,
      drops={
        Mettaur   = { ["2"]={ chip_drop("sonicwave", COMMON_DROP) } },
        Ratty     = { ["2"]={ chip_drop("Ratton2", COMMON_DROP) } },
        Fishy     = { ["1"]={ chip_drop("dashatk", UNCOMMON_DROP) } },
        Boomer    = { ["1"]={ chip_drop("boomerang1", UNCOMMON_DROP) } },
        OldStove  = { ["1"]={ chip_drop("HellsBurner1", COMMON_DROP) } },
        VacuumFan = { ["1"]={ chip_drop("windbox", COMMON_DROP) } },
        Shrimpy   = { ["1"]={ chip_drop("bubbler", STARTER_DROP) } },
        Spikey    = { ["1"]={ chip_drop("heatshot", STARTER_DROP) } },
      },
    },
  },
  results_callback=notify_jobbbs,
  random_encounters={
    enabled=true,
    package_path="/server/assets/ezlibs-assets/ezencounters/optimized/techlab.zip",
    source_weights={ static=0, random=100 },
    pet_exp=7,
    allow_duplicates=true,
    enemy_count={ min=2, max=3 },
    obstacles={ enabled=false },
    panels={ enabled=true, pool={13}, chance=0.30, min=1, max=2 },
    bosses={ enabled=false },
    results_callback=notify_jobbbs,
    pool={
      { name="Mettaur", ranks={"2"} },
      { name="Ratty", ranks={"2"} },
      { name="Fishy", ranks={"1"} },
      { name="Boomer", ranks={"1"} },
      { name="OldStove", ranks={"1"} },
      { name="VacuumFan", ranks={"1"} },
      { name="Shrimpy", ranks={"1"} },
      { name="Spikey", ranks={"1"} },
      { name="Volcano", ranks={"1"} },
    },
  },
}
