local Pets = require("scripts/ezlibs-custom/pets")
local package_registry = require("scripts/ezlibs-scripts/ezencounters/package_registry")

local LPetsOK, LPets =
  pcall(
    require,
    "scripts/ezlibs-custom/lpets"
  )

if not LPetsOK then
  print(
    "[petduels] LPets load failed:",
    tostring(LPets)
  )

  LPets = rawget(_G, "LPets")
end

local petduels = {}

local PET_DUEL_PATH =
  package_registry.PETDUELS_PATH
  or (package_registry.PACKAGE_PREFIX .. "petduels.zip")

local active_duels = {}

local function is_player(pid)
  return pid
    and Net
    and Net.is_player
    and Net.is_player(pid)
end

local function message(pid, text)
  if is_player(pid) and Net.message_player then
    pcall(Net.message_player, pid, tostring(text or ""))
  end
end

local function player_name(pid)
  if is_player(pid) and Net.get_player_name then
    local ok, name = pcall(Net.get_player_name, pid)
    if ok and name and name ~= "" then
      return tostring(name)
    end
  end

  return "Player"
end

local function get_battle_pet(pid)
  if not (Pets and type(Pets.get_armed_pet_info) == "function") then
    return nil
  end

  local ok, pet = pcall(Pets.get_armed_pet_info, pid)
  if not ok then
    print("[petduels] get_armed_pet_info failed:", tostring(pet))
    return nil
  end

  if type(pet) ~= "table" then
    return nil
  end

  if pet.can_fight ~= true or tostring(pet.enemy_name or "") == "" then
    return nil
  end

  return pet
end

local function pair_status(p1, p2)
  if not (is_player(p1) and is_player(p2)) then
    return false, "invalid_player"
  end

  if p1 == p2 then
    return false, "same_player"
  end

  if active_duels[p1] or active_duels[p2] then
    return false, "busy"
  end

  if Net.is_player_battling
    and (Net.is_player_battling(p1) or Net.is_player_battling(p2))
  then
    return false, "busy"
  end

  local pet1 = get_battle_pet(p1)
  if not pet1 then
    return false, "p1_no_pet"
  end

  local pet2 = get_battle_pet(p2)
  if not pet2 then
    return false, "p2_no_pet"
  end

  return true, nil, pet1, pet2
end

function petduels.can_request(sender, target)
  local ok, reason = pair_status(sender, target)
  if ok then
    return true
  end

  if reason == "p1_no_pet" then
    return false, "You don't have a battle-ready pet equipped."
  end

  if reason == "p2_no_pet" then
    return false, player_name(target) .. " doesn't have a battle-ready pet equipped."
  end

  if reason == "busy" then
    return false, "Pet Duel is not available right now."
  end

  return false, "Pet Duel is not available."
end

local function clamp_pet_rank(rank)
  rank = math.floor(tonumber(rank) or 1)

  if rank < 1 then
    rank = 1
  elseif rank > 20 then
    rank = 20
  end

  return rank
end

-- ---------------------------------------------------------------------------
-- Pet Duel pre-battle resolution
--
-- Base setup:
--   Resolve match-wide HP scaling.
--
-- Step 1:
--   Arm traps.
--
-- Step 2:
--   Resolve passive programs.
--
-- Step 3:
--   Resolve field-changing programs.
--
-- Step 4:
--   Launch combat.
--
-- Only HP scaling + HP+ passives have gameplay behavior for now.
-- ---------------------------------------------------------------------------

local function copy_pet_snapshot(pet)
  local copy = {}

  for key, value in pairs(pet or {}) do
    copy[key] = value
  end

  return copy
end

local function pet_attack_value(pet)
  local attack = tonumber(pet and pet.attack)

  if attack == nil then
    attack =
      clamp_pet_rank(pet and pet.rank) * 5
  end

  return math.max(
    1,
    math.floor(attack)
  )
end

local function pet_base_hp(pet)
  return math.max(
    1,
    math.floor(
      tonumber(pet and pet.hp) or 1
    )
  )
end

local function round_hp(value)
  return math.max(
    1,
    math.floor(
      (tonumber(value) or 1) + 0.5
    )
  )
end

local function get_customizer_battle_state(
  player_id,
  pet
)
  local empty = {
    installed = {},
    programs = {},
    hp_bonus = 0,
    dominant_element = nil,
  }

  local uid =
    tostring(
      pet
      and pet.uid
      or ""
    )

  if uid == "" then
    return empty
  end

  local L =
    LPets
    or rawget(_G, "LPets")

  if not (
    L
    and type(
      L.get_pet_customizer_battle_state
    ) == "function"
  ) then
    print(
      "[petduels] PetCustomizer battle state unavailable"
    )

    return empty
  end

  local ok, state =
    pcall(
      L.get_pet_customizer_battle_state,
      uid,
      player_id
    )

  if not ok then
    print(
      "[petduels] PetCustomizer state failed:",
      tostring(state)
    )

    return empty
  end

  if type(state) ~= "table" then
    return empty
  end

  return state
end

local function calculate_hp_multiplier(
  pet1,
  pet2
)
  local attack1 =
    pet_attack_value(pet1)

  local attack2 =
    pet_attack_value(pet2)

  local average_attack =
    (attack1 + attack2) / 2

  local multiplier =
    average_attack / 10

  if multiplier < 1 then
    multiplier = 1
  elseif multiplier > 10 then
    multiplier = 10
  end

  return multiplier
end

local function create_prebattle_pet(
  player_id,
  pet,
  hp_multiplier
)
  local battle_pet =
    copy_pet_snapshot(pet)

  local base_hp =
    pet_base_hp(pet)

  local attack =
    pet_attack_value(pet)

  local scaled_hp =
    round_hp(
      base_hp * hp_multiplier
    )

  local customizer =
    get_customizer_battle_state(
      player_id,
      pet
    )

  battle_pet.hp = scaled_hp

  battle_pet.pet_duel_state = {
    player_id = player_id,

    base_hp = base_hp,
    attack = attack,

    hp_multiplier = hp_multiplier,

    scaled_hp = scaled_hp,

    hp_bonus = 0,
    final_hp = scaled_hp,

    customizer = customizer,
  }

  return battle_pet
end

local function resolve_trap_step(context)
  -- STEP 1
  --
  -- Reserved for things such as:
  -- AntiRecov
  -- AntiField
  -- AntiBarrier
  --
  -- These will eventually ARM here and react
  -- to later steps/combat events.
end

local function resolve_passive_step(context)
  -- STEP 2
  --
  -- HP+ is the first implemented passive.
  --
  -- Important:
  -- HP+ is added AFTER match HP scaling.
  -- HP+100 therefore always means +100,
  -- not +100 multiplied by battle scaling.

  for _, pet in ipairs(context.pets) do
    local state = pet.pet_duel_state

    local customizer =
      state
      and state.customizer
      or {}

    local has_under_shirt = false

    for _, program in ipairs(
      customizer.programs or {}
    ) do
      if
        tostring(
          program.passive_effect or ""
        ) == "under_shirt"
      then
        has_under_shirt = true
        break
      end
    end

    local hp_bonus =
      math.max(
        0,
        math.floor(
          tonumber(
            customizer.hp_bonus
          ) or 0
        )
      )

    state.hp_bonus = hp_bonus

    state.final_hp =
      state.scaled_hp + hp_bonus

    pet.hp = state.final_hp

    state.under_shirt =
      has_under_shirt

    pet.under_shirt =
      has_under_shirt

    local element =
      tostring(
        customizer.dominant_element or ""
      ):lower()

    if
      element == "fire"
      or element == "aqua"
      or element == "elec"
      or element == "wood"
    then
      state.element = element
      pet.battle_element = element
    else
      state.element = nil
      pet.battle_element = nil
    end
  end
end

local FIELD_SHORTNAMES = {
  lava = "LavaField",
  grass = "GrassField",
  ice = "IceField",
  sea = "SeaField",
}

local function get_pet_field_effect(pet)
  local state =
    pet
    and pet.pet_duel_state

  local customizer =
    state
    and state.customizer
    or {}

  for _, program in ipairs(
    customizer.programs or {}
  ) do
    local effect =
      string.lower(
        tostring(
          program.field_effect or ""
        )
      )

    if FIELD_SHORTNAMES[effect] then
      return effect
    end
  end

  return nil
end

local function copy_field_presentations(
  presentations
)
  local copy = {}

  for _, presentation in ipairs(
    presentations or {}
  ) do
    copy[#copy + 1] = {
      effect = presentation.effect,
      shortname = presentation.shortname,

      owner_player_id =
        presentation.owner_player_id,

      target = presentation.target,
    }
  end

  return copy
end

local function resolve_field_step(context)
  local pet1 = context.pets[1]
  local pet2 = context.pets[2]

  local state1 =
    pet1
    and pet1.pet_duel_state

  local state2 =
    pet2
    and pet2.pet_duel_state

  local effect1 =
    get_pet_field_effect(pet1)

  local effect2 =
    get_pet_field_effect(pet2)

  context.field_presentations = {}

  local both_wood =
    state1
    and state2
    and state1.element == "wood"
    and state2.element == "wood"

  local single_grass_field =
    (
      effect1 == "grass"
      and effect2 == nil
    )
    or
    (
      effect2 == "grass"
      and effect1 == nil
    )

  if
    both_wood
    and single_grass_field
  then
    -- Anti-stalemate exception:
    --
    -- If both pets are Wood element and only one
    -- player brought GrassField, neutralize it.
    --
    -- Otherwise very low-ATK Wood pets can heal
    -- indefinitely from the Grass panels.
    context.field_presentations[1] = {
      effect = "cancel",
      shortname = "CancelField",

      -- Keep P1 as the canonical presenter so both
      -- independent simulations resolve identically.
      owner_player_id =
        state1.player_id,

      target = "none",
    }

    print(
      "[petduels] FIELD",
      "cancelled",
      "reason=wood_grass_stalemate"
    )

  elseif effect1 and effect2 then
    if effect1 == effect2 then
      -- Same Field programs neutralize each other.
      --
      -- We still send a presentation so the players
      -- can SEE that their programs cancelled rather
      -- than thinking nothing happened.
      context.field_presentations[1] = {
        effect = "cancel",
        shortname = "CancelField",

        -- P1 is always used as the canonical presenter.
        -- Both clients therefore receive the same
        -- deterministic presentation order.
        owner_player_id =
          state1.player_id,

        target = "none",
      }

      print(
        "[petduels] FIELD",
        "cancelled",
        "same_effect="
          .. tostring(effect1)
      )
    else
      -- Canonical order is ALWAYS original P1,
      -- followed by original P2.
      --
      -- Each Field only affects the opponent's side.
      context.field_presentations[1] = {
        effect = effect1,
        shortname =
          FIELD_SHORTNAMES[effect1],

        owner_player_id =
          state1.player_id,

        target = "opponent",
      }

      context.field_presentations[2] = {
        effect = effect2,
        shortname =
          FIELD_SHORTNAMES[effect2],

        owner_player_id =
          state2.player_id,

        target = "opponent",
      }

      print(
        "[petduels] FIELD",
        "p1=" .. tostring(effect1),
        "p2=" .. tostring(effect2),
        "rule=cross"
      )
    end

  elseif effect1 then
    context.field_presentations[1] = {
      effect = effect1,
      shortname =
        FIELD_SHORTNAMES[effect1],

      owner_player_id =
        state1.player_id,

      target = "all",
    }

    print(
      "[petduels] FIELD",
      "effect=" .. tostring(effect1),
      "owner="
        .. tostring(state1.player_id),
      "target=all"
    )

  elseif effect2 then
    context.field_presentations[1] = {
      effect = effect2,
      shortname =
        FIELD_SHORTNAMES[effect2],

      owner_player_id =
        state2.player_id,

      target = "all",
    }

    print(
      "[petduels] FIELD",
      "effect=" .. tostring(effect2),
      "owner="
        .. tostring(state2.player_id),
      "target=all"
    )
  end

  if state1 then
    state1.field_effect = effect1

    state1.field_presentations =
      copy_field_presentations(
        context.field_presentations
      )
  end

  if state2 then
    state2.field_effect = effect2

    state2.field_presentations =
      copy_field_presentations(
        context.field_presentations
      )
  end
end

local PRE_BATTLE_STEPS = {
  {
    id = "traps",
    name = "Traps",
    resolve = resolve_trap_step,
  },

  {
    id = "passives",
    name = "Passives",
    resolve = resolve_passive_step,
  },

  {
    id = "field",
    name = "Field",
    resolve = resolve_field_step,
  },
}

local function print_prebattle_pet(pet)
  local state =
    pet
    and pet.pet_duel_state

  if not state then
    return
  end

  print(
    "[petduels] PREP PET",
    "pet="
      .. tostring(
        pet.display_name
        or pet.enemy_name
      ),
    "base_hp="
      .. tostring(state.base_hp),
    "attack="
      .. tostring(state.attack),
    "scale="
      .. string.format(
        "%.2f",
        state.hp_multiplier
      ),
    "scaled_hp="
      .. tostring(state.scaled_hp),
    "hp_bonus="
      .. tostring(state.hp_bonus),
    "final_hp="
      .. tostring(state.final_hp),
    "element="
      .. tostring(state.element or "none")
  )
end

local function resolve_prebattle(
  p1,
  p2,
  pet1,
  pet2
)
  local hp_multiplier =
    calculate_hp_multiplier(
      pet1,
      pet2
    )

  local context = {
    hp_multiplier = hp_multiplier,

    pets = {
      create_prebattle_pet(
        p1,
        pet1,
        hp_multiplier
      ),

      create_prebattle_pet(
        p2,
        pet2,
        hp_multiplier
      ),
    },
  }

  print(
    "[petduels] PREP",
    "base_hp_multiplier="
      .. string.format(
        "%.2f",
        hp_multiplier
      )
  )

  for index, step in ipairs(PRE_BATTLE_STEPS) do
    print(
      "[petduels] PREP STEP",
      tostring(index),
      tostring(step.name)
    )

    local ok, err =
      pcall(
        step.resolve,
        context
      )

    if not ok then
      print(
        "[petduels] PREP STEP FAILED",
        tostring(step.id),
        tostring(err)
      )

      return nil
    end
  end

  for _, pet in ipairs(context.pets) do
    print_prebattle_pet(pet)
  end

  return context
end

local function build_pet_bridge_name(pet)
  local rank = clamp_pet_rank(pet.rank)
  local chip_id = tonumber(pet.pet_chip_id)
  local chip_amount = math.floor(tonumber(pet.pet_chip_amount) or 0)

  if chip_id and chip_id > 0 and chip_amount > 0 then
    return "__PETC" .. tostring(chip_id) .. "R" .. tostring(rank)
  end

  return "__PETR" .. tostring(rank)
end

local function build_pet_enemy(pet, team)
  local chip_id = tonumber(pet.pet_chip_id)
  local chip_amount = math.floor(tonumber(pet.pet_chip_amount) or 0)

  if not chip_id or chip_id <= 0 or chip_amount <= 0 then
    chip_id = nil
  end

  return {
    name = tostring(pet.enemy_name),
    rank = 1, -- pet package stays on base V1 logic; attack rank travels in the bridge name
    team = team,
    starting_hp = math.max(1, math.floor(tonumber(pet.hp) or 1)),
    hp_cap = math.max(
      1,
      math.floor(
        tonumber(pet.hp) or 1
      )
    ),
    under_shirt =
      pet.under_shirt == true,
    element = pet.battle_element,
    pet_bridge_name = build_pet_bridge_name(pet),
    pet_chip_id = chip_id,
    pet_chip_amount = chip_id and 1 or nil,
  }
end

local function build_encounter(own_pet, opponent_pet)
  local own_state =
    own_pet
    and own_pet.pet_duel_state
    or nil

  local opponent_state =
    opponent_pet
    and opponent_pet.pet_duel_state
    or nil

  local field_presentations = {}

  for _, presentation in ipairs(
    own_state
    and own_state.field_presentations
    or {}
  ) do
    local owner_team = nil

    if
      own_state
      and presentation.owner_player_id
        == own_state.player_id
    then
      owner_team = 2

    elseif
      opponent_state
      and presentation.owner_player_id
        == opponent_state.player_id
    then
      owner_team = 1
    end

    if owner_team ~= nil then
      local target_team = nil

      if presentation.target == "opponent" then
        if owner_team == 2 then
          target_team = 1
        else
          target_team = 2
        end
      end

      field_presentations[
        #field_presentations + 1
      ] = {
        effect = presentation.effect,

        shortname =
          presentation.shortname,

        owner_team = owner_team,

        target = presentation.target,
        target_team = target_team,
      }
    end
  end

  local field_tiles =
    own_state
    and own_state.field_tiles
    or nil
  return {
    path = PET_DUEL_PATH,

    -- Safety markers in case Pet Duels are ever routed through ezencounters later.
    allow_battle_pets = false,
    _no_pets = true,
    no_results = true,
    pet_duel = true,

    -- Enemy #1 is ALWAYS the viewer's pet.
    -- Enemy #2 is ALWAYS the opponent's pet.
    enemies = {
      build_pet_enemy(own_pet, 2),
      build_pet_enemy(opponent_pet, 1),
    },

    positions = {
      {0,0,0,0,0,0},
      {0,1,0,0,2,0},
      {0,0,0,0,0,0},
    },

    tiles = {
      {1,1,1,1,1,1},
      {1,1,1,1,1,1},
      {1,1,1,1,1,1},
    },

    teams = {
      {2,2,2,1,1,1},
      {2,2,2,1,1,1},
      {2,2,2,1,1,1},
    },
    field_presentations =
      field_presentations,
    -- Intentionally NO player_positions.
  }
end

local function provide_package(pid)
  if not is_player(pid) then
    return false
  end

  if not (Net and Net.provide_asset_for_player) then
    return false
  end

  local ok, err = pcall(Net.provide_asset_for_player, pid, PET_DUEL_PATH)
  if not ok then
    print("[petduels] failed to provide package:", tostring(err))
    return false
  end

  return true
end

local function snapshot_player_state(pid)
  local state = {}

  if Net.get_player_health then
    local ok, value = pcall(Net.get_player_health, pid)
    if ok then state.health = value end
  end

  if Net.get_player_max_health then
    local ok, value = pcall(Net.get_player_max_health, pid)
    if ok then state.max_health = value end
  end

  if Net.get_player_emotion then
    local ok, value = pcall(Net.get_player_emotion, pid)
    if ok then state.emotion = value end
  end

  return state
end

local function restore_player_state(pid, state)
  if not is_player(pid) or type(state) ~= "table" then
    return
  end

  if state.max_health ~= nil and Net.set_player_max_health then
    pcall(Net.set_player_max_health, pid, state.max_health)
  end

  if state.health ~= nil and Net.set_player_health then
    pcall(Net.set_player_health, pid, state.health)
  end

  if state.emotion ~= nil and Net.set_player_emotion then
    pcall(Net.set_player_emotion, pid, state.emotion)
  end
end

local function log_result(viewer_pid, own_pet, opponent_pet, stats)
  print(
    "[petduels] RESULT",
    "viewer=" .. tostring(viewer_pid),
    "own=" .. tostring(own_pet.display_name or own_pet.enemy_name),
    "opponent=" .. tostring(opponent_pet.display_name or opponent_pet.enemy_name),
    "ran=" .. tostring(type(stats) == "table" and stats.ran or nil)
  )

  local enemies = type(stats) == "table" and stats.enemies or nil
  if type(enemies) ~= "table" then
    print("[petduels] RESULT enemies=<missing>")
    return
  end

  print(
    "[petduels] RESULT enemy_count=" .. tostring(#enemies)
  )

  for i, enemy in ipairs(enemies) do
    print(
      "[petduels] RESULT enemy",
      "index=" .. tostring(i),
      "id=" .. tostring(enemy and enemy.id),
      "health=" .. tostring(enemy and enemy.health)
    )
  end
end

local function classify_result(stats)
  if type(stats) ~= "table" then
    return "unknown"
  end

  if stats.ran == true then
    return "aborted"
  end

  local enemies = stats.enemies
  if type(enemies) ~= "table" then
    return "unknown"
  end

  -- Pet Duel result behavior:
  --
  -- Our pet is placed on the encounter player's side.
  -- The opponent pet is placed on the enemy side.
  --
  -- Battle results only contain enemy-side survivors.
  --
  -- No surviving enemies = our pet won.
  -- A surviving enemy     = our pet lost.

  if #enemies == 0 then
    return "win"
  end

  local saw_valid_enemy = false

  for _, enemy in ipairs(enemies) do
    local hp = tonumber(enemy and enemy.health)

    if hp ~= nil then
      saw_valid_enemy = true

      if hp > 0 then
        return "loss"
      end
    end
  end

  if saw_valid_enemy then
    return "win"
  end

  return "unknown"
end

local function show_result(pid, outcome)
  if outcome == "win" then
    message(pid, "Your pet won!")
  elseif outcome == "loss" then
    message(pid, "Your pet lost.")
  elseif outcome == "draw" then
    message(pid, "The pet duel ended in a draw.")
  elseif outcome == "aborted" then
    message(pid, "The pet duel ended early.")
  else
    message(pid, "Pet duel ended, but the winner couldn't be identified.")
  end
end

local function launch_for_viewer(viewer_pid, opponent_pid, own_pet, opponent_pet)
  local saved_state = snapshot_player_state(viewer_pid)
  provide_package(viewer_pid)

  print(
    "[petduels] START",
    "viewer=" .. tostring(viewer_pid),
    "own=" .. tostring(own_pet.display_name or own_pet.enemy_name),
    "own_hp=" .. tostring(own_pet.hp),
    "own_rank=" .. tostring(own_pet.rank),
    "own_chip=" .. tostring(own_pet.pet_chip_id or 0),
    "opponent=" .. tostring(opponent_pet.display_name or opponent_pet.enemy_name),
    "opponent_hp=" .. tostring(opponent_pet.hp),
    "opponent_rank=" .. tostring(opponent_pet.rank),
    "opponent_chip=" .. tostring(opponent_pet.pet_chip_id or 0)
  )

  local encounter = build_encounter(own_pet, opponent_pet)

  local ok, promise = pcall(
    Async.initiate_encounter,
    viewer_pid,
    PET_DUEL_PATH,
    encounter
  )

  if not ok or not promise or type(promise.and_then) ~= "function" then
    active_duels[viewer_pid] = nil
    restore_player_state(viewer_pid, saved_state)
    print("[petduels] initiate_encounter failed:", tostring(promise))
    message(viewer_pid, "Couldn't start the pet duel.")
    return false
  end

  promise.and_then(function(stats)
    active_duels[viewer_pid] = nil

    if not is_player(viewer_pid) then
      return
    end

    -- Pet Duels must not alter the overworld player's HP/emotion.
    restore_player_state(viewer_pid, saved_state)

    log_result(viewer_pid, own_pet, opponent_pet, stats)
    show_result(viewer_pid, classify_result(stats))
  end)

  return true
end

local function saved_pet_status(
  viewer_pid,
  opponent_owner_ref,
  opponent_pet
)
  if not is_player(viewer_pid) then
    return false,
      "Pet Duel is not available."
  end

  if active_duels[viewer_pid] then
    return false,
      "Pet Duel is not available right now."
  end

  if
    Net.is_player_battling
    and Net.is_player_battling(viewer_pid)
  then
    return false,
      "Pet Duel is not available right now."
  end

  local own_pet =
    get_battle_pet(viewer_pid)

  if not own_pet then
    return false,
      "You don't have a battle-ready pet equipped."
  end

  opponent_owner_ref =
    tostring(opponent_owner_ref or "")

  if opponent_owner_ref == "" then
    return false,
      "Couldn't identify that pet's owner."
  end

  if
    type(opponent_pet) ~= "table"
    or opponent_pet.can_fight ~= true
    or tostring(opponent_pet.enemy_name or "") == ""
    or tostring(opponent_pet.uid or "") == ""
  then
    return false,
      "That pet isn't battle-ready."
  end

  if
    not Pets
    or type(
      Pets.is_hp_battle_enabled
    ) ~= "function"
  then
    return false,
      "This pet is not accepting Pet Duels."
  end

  local ok_enabled, enabled =
    pcall(
      Pets.is_hp_battle_enabled,
      opponent_owner_ref,
      opponent_pet.uid
    )

  if
    not ok_enabled
    or enabled ~= true
  then
    return false,
      "This pet is not accepting Pet Duels."
  end

  return true, nil, own_pet
end

function petduels.can_start_against_saved_pet(
  viewer_pid,
  opponent_owner_ref,
  opponent_pet
)
  local ok, reason =
    saved_pet_status(
      viewer_pid,
      opponent_owner_ref,
      opponent_pet
    )

  return ok, reason
end

function petduels.start_against_saved_pet(
  viewer_pid,
  opponent_owner_ref,
  opponent_pet
)
  local ok,
        reason,
        own_pet =
    saved_pet_status(
      viewer_pid,
      opponent_owner_ref,
      opponent_pet
    )

  if not ok then
    message(
      viewer_pid,
      reason
      or "Pet Duel is not available."
    )

    return false
  end

  opponent_owner_ref =
    tostring(opponent_owner_ref or "")

  -- For a normal Pet Duel, resolve_prebattle receives
  -- two player IDs.
  --
  -- Here the second value is the offline owner's safe
  -- memory secret. LPets can use that value directly to
  -- retrieve pet_customizers_v1 for this pet UID.
  local prebattle =
    resolve_prebattle(
      viewer_pid,
      opponent_owner_ref,
      own_pet,
      opponent_pet
    )

  if not prebattle then
    message(
      viewer_pid,
      "Pet Duel setup failed."
    )

    return false
  end

  own_pet =
    prebattle.pets[1]

  opponent_pet =
    prebattle.pets[2]

  print(
    "[petduels] PREP STEP",
    "4",
    "Combat"
  )

  -- Only the visitor needs an encounter.
  --
  -- Unlike normal player-vs-player Pet Duels, there is
  -- no second online viewer whose simulation must start.
  active_duels[viewer_pid] =
    "hp:"
    .. opponent_owner_ref
    .. ":"
    .. tostring(opponent_pet.uid or "")

  local started =
    launch_for_viewer(
      viewer_pid,
      nil,
      own_pet,
      opponent_pet
    )

  if not started then
    active_duels[viewer_pid] = nil
  end

  return started
end

function petduels.start(p1, p2)
  local ok, reason, pet1, pet2 = pair_status(p1, p2)

  if not ok then
    if reason == "p1_no_pet" then
      message(p1, "You don't have a battle-ready pet equipped.")
      message(p2, player_name(p1) .. " doesn't have a battle-ready pet equipped.")
    elseif reason == "p2_no_pet" then
      message(p2, "You don't have a battle-ready pet equipped.")
      message(p1, player_name(p2) .. " doesn't have a battle-ready pet equipped.")
    else
      message(p1, "Pet Duel is no longer available.")
      message(p2, "Pet Duel is no longer available.")
    end

    return false
  end

  local prebattle =
    resolve_prebattle(
      p1,
      p2,
      pet1,
      pet2
    )

  if not prebattle then
    message(
      p1,
      "Pet Duel setup failed."
    )

    message(
      p2,
      "Pet Duel setup failed."
    )

    return false
  end

  pet1 = prebattle.pets[1]
  pet2 = prebattle.pets[2]

  print(
    "[petduels] PREP STEP",
    "4",
    "Combat"
  )

  -- Each player gets an independent simulation.
  -- In each simulation, that viewer's own pet is enemy #1/team 2.
  active_duels[p1] = p2
  active_duels[p2] = p1

  local started1 = launch_for_viewer(p1, p2, pet1, pet2)
  local started2 = launch_for_viewer(p2, p1, pet2, pet1)

  if not started1 then
    active_duels[p1] = nil
  end

  if not started2 then
    active_duels[p2] = nil
  end

  return started1 and started2
end

function petduels.is_active(pid)
  return active_duels[pid] ~= nil
end

Net:on("player_join", function(event)
  if event and event.player_id then
    provide_package(event.player_id)
  end
end)

Net:on("player_disconnect", function(event)
  if event and event.player_id then
    active_duels[event.player_id] = nil
  end
end)

return petduels
