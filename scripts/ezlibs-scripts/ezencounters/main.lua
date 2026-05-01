local ezwarps = require('scripts/ezlibs-scripts/ezwarps/main')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local helpers = require('scripts/ezlibs-scripts/helpers')
local eztriggers = require('scripts/ezlibs-scripts/eztriggers')
local object_registry = require('scripts/ezlibs-scripts/object_registry')
local ezbus = require('scripts/ezlibs-scripts/ezbus')
local ezconfig = require('scripts/ezlibs-scripts/ezconfig')
local PetsOK, Pets = pcall(require, "scripts/ezlibs-custom/pets")
if not PetsOK then
    Pets = nil
end
local whitelist = require('scripts/ezlibs-custom/whitelist')

local ezencounters = {}
local players_in_encounters = {}
local player_last_position = {}
local player_steps_since_encounter = {}
local named_encounters = {}
local provided_encounter_assets = {}
local encounter_finished_callbacks = {}
local area_encounter_tables = {}

-- Ensure encounters directory exists
helpers.ensure_directory(ezconfig.ENCOUNTERS_PATH)

local DEFAULT_RANDOM_PLAYER_POSITIONS = {
    {0,0,0,0,0,0},
    {0,1,0,0,0,0},
    {0,0,0,0,0,0},
}

local DEFAULT_RANDOM_TILES = {
    {1,1,1,1,1,1},
    {1,1,1,1,1,1},
    {1,1,1,1,1,1},
}

local DEFAULT_RANDOM_TEAMS = {
    {2,2,2,1,1,1},
    {2,2,2,1,1,1},
    {2,2,2,1,1,1},
}

local DEFAULT_RANDOM_ENEMY_CELLS = {
    {x=4,y=1},{x=5,y=1},{x=6,y=1},
    {x=4,y=2},{x=5,y=2},{x=6,y=2},
    {x=4,y=3},{x=5,y=3},{x=6,y=3},
}

local DEFAULT_RANDOM_ALL_CELLS = {
    {x=1,y=1},{x=2,y=1},{x=3,y=1},{x=4,y=1},{x=5,y=1},{x=6,y=1},
    {x=1,y=2},{x=2,y=2},{x=3,y=2},{x=4,y=2},{x=5,y=2},{x=6,y=2},
    {x=1,y=3},{x=2,y=3},{x=3,y=3},{x=4,y=3},{x=5,y=3},{x=6,y=3},
}

local DEFAULT_RANDOM_OBSTACLE_POOL = {
    "Rock",
    "RockCube",
    "Coffin",
    "BlastCube",
    "IceCube",
}

-- 2=cracked, 9=grass, 11=holy, 12=ice, 13=lava, 14=poison
local DEFAULT_RANDOM_PANEL_POOL = { 2, 9, 11, 12, 13, 14 }

local function _copy_grid(grid)
    local out = {}
    for y, row in ipairs(grid or {}) do
        out[y] = {}
        for x, value in ipairs(row) do
            out[y][x] = value
        end
    end
    return out
end

local function _blank_positions_grid()
    return {
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    }
end

local function _cell_key(x, y)
    return tostring(x) .. "," .. tostring(y)
end

local function _shuffle_in_place(arr)
    for i = #arr, 2, -1 do
        local j = math.random(i)
        arr[i], arr[j] = arr[j], arr[i]
    end
    return arr
end

local function _pick_distinct(pool, count)
    local temp = {}
    for i, value in ipairs(pool or {}) do
        temp[i] = value
    end
    _shuffle_in_place(temp)

    local out = {}
    for i = 1, math.min(count or 0, #temp) do
        out[#out + 1] = temp[i]
    end
    return out
end

local function _pick_weighted_key(weight_table, fallback_key)
    local total = 0
    for _, weight in pairs(weight_table or {}) do
        weight = tonumber(weight) or 0
        if weight > 0 then
            total = total + weight
        end
    end

    if total <= 0 then
        return fallback_key
    end

    local crawler = math.random() * total
    for key, weight in pairs(weight_table) do
        weight = tonumber(weight) or 0
        if weight > 0 then
            crawler = crawler - weight
            if crawler <= 0 then
                return key
            end
        end
    end

    return fallback_key
end

local pending_battle_reward_packets = {}

local function _queue_battle_rewards(player_id, rewards, ticks)
    if not rewards or #rewards == 0 then
        return
    end

    pending_battle_reward_packets[player_id] = {
        ticks = math.max(1, math.floor(tonumber(ticks or 1) or 1)),
        rewards = rewards,
    }
end

local function _send_rewards_and_fixup_wallet(player_id, rewards)
    if not rewards or #rewards == 0 then
        return
    end

    local expected_money = 0
    for _, reward in ipairs(rewards) do
        if reward and reward.type == 0 then
            expected_money = expected_money + (tonumber(reward.value) or 0)
        end
    end

    local money_before = nil
    if expected_money > 0 and Net.get_player_money then
        money_before = tonumber(Net.get_player_money(player_id) or 0) or 0
    end

    Net.send_player_battle_rewards(player_id, rewards)

    if expected_money > 0 and money_before ~= nil then
        local money_after = tonumber(Net.get_player_money(player_id) or 0) or 0
        if money_after < (money_before + expected_money) then
            pcall(ezmemory.spend_player_money, player_id, -expected_money)
        elseif ezmemory.get_player_money then
            pcall(ezmemory.get_player_money, player_id)
        end
    end
end

local function _persist_health_and_emotion(player_id, stats)
    local emotion = tonumber(stats and stats.emotion or 0) or 0
    local health = tonumber(stats and stats.health or 0) or 0

    if emotion == 1 then
        Net.set_player_emotion(player_id, emotion)
    else
        Net.set_player_emotion(player_id, 0)
    end

    if ezmemory and ezmemory.set_player_health then
        ezmemory.set_player_health(player_id, health)
    end
end

local function _result_flags(stats)
    local reason = tonumber(stats and stats.reason or 0) or 0
    local hp = tonumber(stats and (stats.health or stats.player_hp or stats.hp) or 0) or 0

    local ran, dev_escape, won, lost = false, false, false, false

    if reason == 1 then
        won = true
    elseif reason == 2 then
        lost = true
    elseif reason == 3 then
        ran = true
    elseif reason == 4 then
        ran = true
        dev_escape = true
    else
        ran = stats and (stats.ran or stats.fled or stats.escape) or false
        if not ran then
            if hp > 0 then
                won = true
            elseif hp <= 0 then
                lost = true
            end
        end
    end

    return {
        reason     = reason,
        hp         = hp,
        ran        = ran,
        dev_escape = dev_escape,
        won        = won,
        lost       = lost,
    }
end

local function _apply_area_result_awards(player_id, area_table, encounter_info, stats)
    local rewards_cfg = area_table and area_table.rewards
    if not rewards_cfg then
        return false
    end

    if rewards_cfg.enabled == false then
        _persist_health_and_emotion(player_id, stats)
        return true
    end

    local flags = _result_flags(stats)

    if not flags.won then
        _persist_health_and_emotion(player_id, stats)
        return true
    end

    local rewards = {}
    local score = tonumber(stats and stats.score or 0) or 0
    local hp = tonumber(stats and stats.health or 0) or 0
    local hp_bonus = 0

    local money_cfg = rewards_cfg.money
    if money_cfg and money_cfg.enabled ~= false then
        local multiplier = tonumber(money_cfg.score_multiplier or money_cfg.multiplier or money_cfg.per_score or 0) or 0
        local money_amount = math.floor(score * multiplier)
        if money_amount > 0 then
            rewards[#rewards + 1] = { type = 0, value = money_amount }
        end
    end

    local health_cfg = rewards_cfg.health
    if health_cfg and health_cfg.enabled ~= false then
        local threshold = tonumber(health_cfg.threshold or health_cfg.if_hp_below or 0) or 0
        local amount = tonumber(health_cfg.amount or health_cfg.give or 0) or 0
        if amount > 0 and hp <= threshold then
            hp_bonus = amount
            rewards[#rewards + 1] = { type = 2, value = amount }
        end
    end

    local cards_cfg = rewards_cfg.cards
    local card_result = nil

    if whitelist and whitelist.try_grant_area_battle_chip then
        card_result = whitelist.try_grant_area_battle_chip(
            player_id,
            cards_cfg,
            encounter_info,
            stats,
            rewards
        )

        if card_result then
            print(
                "[ezencounters][chip reward]",
                "pid=" .. tostring(player_id),
                "kind=" .. tostring(card_result.kind),
                "card=" .. tostring(card_result.package_id),
                "virus=" .. tostring(card_result.virus_name),
                "rank=" .. tostring(card_result.rank),
                "score=" .. tostring(card_result.score),
                "delay=" .. tostring(card_result.delay_ticks or 0)
            )
        end
    end

    if card_result and card_result.kind == "new" then
        local filtered = {}
        for _, reward in ipairs(rewards) do
            if reward.type ~= 0 then -- strip normal money if a new chip dropped
                filtered[#filtered + 1] = reward
            end
        end
        rewards = filtered

    elseif card_result and card_result.kind == "duplicate" then
        local filtered = {}

        -- keep non-money rewards like HP
        for _, reward in ipairs(rewards) do
            if reward.type ~= 0 then
                filtered[#filtered + 1] = reward
            end
        end

        -- add back ONLY the duplicate fallback money
        if tonumber(card_result.money or 0) > 0 then
            table.insert(filtered, 1, {
                type = 0,
                value = tonumber(card_result.money or 0),
            })
        end

        rewards = filtered
    end

    if #rewards > 0 then
        if card_result and card_result.kind == "new" and tonumber(card_result.delay_ticks or 0) > 0 then
            _queue_battle_rewards(player_id, rewards, card_result.delay_ticks)
        else
            _send_rewards_and_fixup_wallet(player_id, rewards)
        end
    end

    _persist_health_and_emotion(player_id, {
        health = hp + hp_bonus,
        emotion = stats and stats.emotion or 0
    })

    return true
end

local function _normalize_random_unit(unit_def)
    if type(unit_def) == "string" then
        return {
            name = unit_def,
            ranks = { "1" }
        }
    end

    if type(unit_def) ~= "table" then
        return nil
    end

    local name = unit_def.name or unit_def.alias
    if not name then
        return nil
    end

    local ranks = unit_def.ranks or unit_def.supported_ranks or unit_def.rank or { "1" }
    if type(ranks) ~= "table" then
        ranks = { ranks }
    end

    local normalized_ranks = {}
    for i, rank_token in ipairs(ranks) do
        normalized_ranks[i] = tostring(rank_token)
    end

    if #normalized_ranks == 0 then
        normalized_ranks[1] = "1"
    end

    return {
        name = name,
        ranks = normalized_ranks,
    }
end

local function _get_random_encounter_config(area_table)
    local cfg = area_table and area_table.random_encounters
    if not cfg or cfg.enabled ~= true then
        return nil
    end
    if not cfg.pool or #cfg.pool == 0 then
        return nil
    end
    return cfg
end

local function _get_random_package_path(area_table, cfg, is_boss)
    if is_boss and cfg and cfg.bosses and cfg.bosses.package_path then
        return cfg.bosses.package_path
    end
    if cfg and cfg.package_path then
        return cfg.package_path
    end
    if area_table and area_table.encounters and area_table.encounters[1] then
        return area_table.encounters[1].path
    end
    return nil
end

local function _pick_random_rank_token(unit_def)
    local ranks = unit_def.ranks or { "1" }
    return tostring(ranks[math.random(#ranks)] or "1")
end

local function _pick_random_units(pool, count, allow_duplicates)
    local normalized_pool = {}
    for _, unit_def in ipairs(pool or {}) do
        local normalized = _normalize_random_unit(unit_def)
        if normalized then
            normalized_pool[#normalized_pool + 1] = normalized
        end
    end

    if #normalized_pool == 0 then
        return {}
    end

    if allow_duplicates then
        local out = {}
        for i = 1, count do
            out[#out + 1] = normalized_pool[math.random(#normalized_pool)]
        end
        return out
    end

    return _pick_distinct(normalized_pool, count)
end

local function _build_enemy_positions(enemy_count, is_boss)
    local positions = _blank_positions_grid()
    local occupied = {}

    if is_boss then
        positions[2][5] = 1
        occupied[_cell_key(5, 2)] = true
        return positions, occupied
    end

    local chosen_cells = _pick_distinct(DEFAULT_RANDOM_ENEMY_CELLS, enemy_count)
    for index, cell in ipairs(chosen_cells) do
        positions[cell.y][cell.x] = index
        occupied[_cell_key(cell.x, cell.y)] = true
    end

    return positions, occupied
end

local function _get_blocked_player_cells(player_positions)
    local blocked = {}
    for y, row in ipairs(player_positions or {}) do
        for x, value in ipairs(row) do
            if tonumber(value) and tonumber(value) > 0 then
                blocked[_cell_key(x, y)] = true
            end
        end
    end
    return blocked
end

local function _build_random_obstacles(cfg, occupied, player_positions)
    local obstacle_cfg = cfg and cfg.obstacles or {}
    local obstacle_positions = _blank_positions_grid()
    local obstacles = {}

    if obstacle_cfg.enabled ~= true then
        return obstacles, obstacle_positions
    end

    local obstacle_pool = obstacle_cfg.pool or DEFAULT_RANDOM_OBSTACLE_POOL
    if #obstacle_pool == 0 then
        return obstacles, obstacle_positions
    end

    local chance = tonumber(obstacle_cfg.chance or 0.20) or 0.20
    if math.random() >= chance then
        return obstacles, obstacle_positions
    end

    local count_min = math.floor(tonumber(obstacle_cfg.count_min or obstacle_cfg.min or 1) or 1)
    local count_max = math.floor(tonumber(obstacle_cfg.count_max or obstacle_cfg.max or 2) or 2)

    if count_min < 1 then count_min = 1 end
    if count_max < count_min then count_max = count_min end

    local blocked = {}
    for key, value in pairs(occupied or {}) do
        blocked[key] = value
    end
    for key, value in pairs(_get_blocked_player_cells(player_positions)) do
        blocked[key] = value
    end

    local free_cells = {}
    for _, cell in ipairs(DEFAULT_RANDOM_ALL_CELLS) do
        if not blocked[_cell_key(cell.x, cell.y)] then
            free_cells[#free_cells + 1] = cell
        end
    end

    if #free_cells == 0 then
        return obstacles, obstacle_positions
    end

    local obstacle_count = math.random(count_min, count_max)
    obstacle_count = math.min(obstacle_count, #free_cells)

    local chosen_cells = _pick_distinct(free_cells, obstacle_count)
    for index, cell in ipairs(chosen_cells) do
        obstacles[index] = {
            name = obstacle_pool[math.random(#obstacle_pool)]
        }
        obstacle_positions[cell.y][cell.x] = index
    end

    return obstacles, obstacle_positions
end

local function _build_random_tiles(cfg, player_positions, obstacle_positions)
    local panel_cfg = cfg and cfg.panels or {}
    local tiles = _copy_grid((cfg and cfg.base_tiles) or DEFAULT_RANDOM_TILES)

    if panel_cfg.enabled ~= true then
        return tiles
    end

    local panel_pool = panel_cfg.pool or DEFAULT_RANDOM_PANEL_POOL
    if #panel_pool == 0 then
        return tiles
    end

    local chance = tonumber(panel_cfg.chance or 0.15) or 0.15
    if math.random() >= chance then
        return tiles
    end

    local count_min = math.floor(tonumber(panel_cfg.count_min or panel_cfg.min or 1) or 1)
    local count_max = math.floor(tonumber(panel_cfg.count_max or panel_cfg.max or 2) or 2)

    if count_min < 1 then count_min = 1 end
    if count_max < count_min then count_max = count_min end

    local blocked = {}

    -- Never spawn panels under player starting positions.
    for key, value in pairs(_get_blocked_player_cells(player_positions)) do
        blocked[key] = value
    end

    -- Also avoid obstacle positions so panels don't silently stack under objects.
    for y, row in ipairs(obstacle_positions or {}) do
        for x, value in ipairs(row) do
            if tonumber(value or 0) > 0 then
                blocked[_cell_key(x, y)] = true
            end
        end
    end

    local free_cells = {}
    for _, cell in ipairs(DEFAULT_RANDOM_ALL_CELLS) do
        if not blocked[_cell_key(cell.x, cell.y)] then
            free_cells[#free_cells + 1] = cell
        end
    end

    if #free_cells == 0 then
        return tiles
    end

    local count = math.random(count_min, count_max)
    count = math.min(count, #free_cells)

    local chosen_cells = _pick_distinct(free_cells, count)

    for _, cell in ipairs(chosen_cells) do
        tiles[cell.y][cell.x] = panel_pool[math.random(#panel_pool)]
    end

    return tiles
end

local function _build_random_encounter(area_id, area_table)
    local cfg = _get_random_encounter_config(area_table)
    if not cfg then
        return nil
    end

    local use_boss = false
    local boss_cfg = cfg.bosses
    if boss_cfg and boss_cfg.enabled == true and boss_cfg.pool and #boss_cfg.pool > 0 then
        local boss_chance = tonumber(boss_cfg.chance or 0) or 0
        if boss_chance > 0 and math.random() < boss_chance then
            use_boss = true
        end
    end

    local unit_pool = use_boss and boss_cfg.pool or cfg.pool
    local allow_duplicates = cfg.allow_duplicates == true

    local enemy_count = 1
    if not use_boss then
        local count_cfg = cfg.enemy_count or {}
        local min_count = math.floor(tonumber(count_cfg.min or count_cfg.min_enemies or 2) or 2)
        local max_count = math.floor(tonumber(count_cfg.max or count_cfg.max_enemies or 3) or 3)

        if min_count < 1 then min_count = 1 end
        if max_count < min_count then max_count = min_count end

        enemy_count = math.random(min_count, max_count)
        if not allow_duplicates then
            enemy_count = math.min(enemy_count, #unit_pool)
        end
    end

    local selected_units = _pick_random_units(unit_pool, enemy_count, allow_duplicates)
    if #selected_units == 0 then
        return nil
    end

    local enemies = {}
    for i, unit_def in ipairs(selected_units) do
        enemies[i] = {
            name = unit_def.name,
            rank = _pick_random_rank_token(unit_def),
        }
    end

    local player_positions = _copy_grid(cfg.player_positions or DEFAULT_RANDOM_PLAYER_POSITIONS)
    local positions, occupied = _build_enemy_positions(#enemies, use_boss)
    local obstacles, obstacle_positions = _build_random_obstacles(cfg, occupied, player_positions)
    local package_path = _get_random_package_path(area_table, cfg, use_boss)

    if not package_path then
        return nil
    end

    return {
        name = string.format("Random_%s_%d", tostring(area_id), math.random(1000000)),
        path = package_path,
        enemies = enemies,
        obstacles = obstacles,
        positions = positions,
        obstacle_positions = obstacle_positions,
        player_positions = player_positions,
        tiles = _build_random_tiles(cfg, player_positions, obstacle_positions),
        teams = _copy_grid(cfg.teams or DEFAULT_RANDOM_TEAMS),

        -- carry over area/random-level metadata used later
        pet_exp = cfg.pet_exp or area_table.pet_exp,
        results_callback = cfg.results_callback or area_table.results_callback,

        _area_id = area_id,
        _random_encounter = true,
        _random_is_boss = use_boss,
    }
end

local function _pick_encounter_for_area(area_id, area_table)
    local has_static = area_table and area_table.encounters and #area_table.encounters > 0
    local random_cfg = _get_random_encounter_config(area_table)
    local has_random = random_cfg ~= nil and _get_random_package_path(area_table, random_cfg, false) ~= nil

    if has_static and not has_random then
        return ezencounters.pick_encounter_from_table(area_table)
    end

    if has_random and not has_static then
        return _build_random_encounter(area_id, area_table)
    end

    if not has_static and not has_random then
        return nil
    end

    local source_weights = random_cfg.source_weights or {}
    local source = _pick_weighted_key({
        static = tonumber(source_weights.static or 50) or 50,
        random = tonumber(source_weights.random or 50) or 50,
    }, "static")

    if source == "random" then
        local random_encounter = _build_random_encounter(area_id, area_table)
        if random_encounter then
            return random_encounter
        end
        return ezencounters.pick_encounter_from_table(area_table)
    end

    local static_encounter = ezencounters.pick_encounter_from_table(area_table)
    if static_encounter then
        return static_encounter
    end

    return _build_random_encounter(area_id, area_table)
end

-- ====================== Battle Pet Injection ======================
local PET_ENCOUNTER_PATH = "/server/assets/ezlibs-assets/ezencounters/ezencounters.zip"
local PLAYER_ARMED_PET_KEY = "armed_pet_v1"

local function clamp_pet_attack_rank(rank)
    rank = math.floor(tonumber(rank) or 1)
    if rank < 1 then rank = 1 end
    if rank > 20 then rank = 20 end
    return rank
end

local function build_pet_bridge_name(pet_chip_id, pet_attack_rank)
    local rank = clamp_pet_attack_rank(pet_attack_rank)
    local chip_id = tonumber(pet_chip_id)

    if chip_id and chip_id > 0 then
        return "__PETC"..tostring(chip_id).."R"..tostring(rank)
    end

    return "__PETR"..tostring(rank)
end

local function _inject_armed_pet(player_id, encounter_info)
    if type(encounter_info) ~= "table" then
        print("[PET INJECT SKIP] encounter_info not table")
        return encounter_info
    end

    local enc_path = tostring(encounter_info.path or "")
    if enc_path ~= PET_ENCOUNTER_PATH then
        print("[PET INJECT SKIP] path mismatch:", enc_path)
        return encounter_info
    end

    local secret = helpers.get_safe_player_secret(player_id)
    if not secret or secret == "" then
        print("[PET INJECT SKIP] no secret")
        return encounter_info
    end

    local ok_mem, pmem = pcall(ezmemory.get_player_memory, secret)
    if not ok_mem or type(pmem) ~= "table" then
        print("[PET INJECT SKIP] no player memory")
        return encounter_info
    end

    local armed = pmem[PLAYER_ARMED_PET_KEY]
    if type(armed) ~= "table" then
        print("[PET INJECT SKIP] no armed pet")
        return encounter_info
    end

    if armed.summoned == true then
        print("[PET INJECT SKIP] companion pet is currently summoned in overworld")
        return encounter_info
    end

    local enemy_name = tostring(armed.enemy_name or "")
    if enemy_name == "" then
        print("[PET INJECT SKIP] armed pet is not battle-capable")
        return encounter_info
    end

    if type(encounter_info.enemies) ~= "table" or type(encounter_info.positions) ~= "table" then
        print("[PET INJECT SKIP] encounter missing enemies/positions")
        return encounter_info
    end

    print("[PET INJECT ARMED]",
        tostring(armed.enemy_name),
        "rank="..tostring(armed.rank),
        "hp="..tostring(armed.starting_hp),
        "chip="..tostring(armed.pet_chip_id or 0)
    )

    local ei = helpers.deep_copy(encounter_info)

    for _, en in ipairs(ei.enemies) do
        if type(en) == "table" and tostring(en.name or "") == enemy_name and tonumber(en.team or 0) == 2 then
            ei.__armed_pet_joined = true
            ei.__armed_pet_uid = tostring(armed.uid or "")
            ei.__armed_pet_kind = tostring(armed.kind or "")
            return ei
        end
    end

    local pet_attack_rank = clamp_pet_attack_rank(armed.rank or 1)
    local starting_hp = tonumber(armed.starting_hp or 40) or 40

    local pet_chip_id = tonumber(armed.pet_chip_id)
    local pet_chip_amount = tonumber(armed.pet_chip_amount or 1) or 1
    local bridge_chip_id = nil

    local pet_enemy = {
        name = enemy_name,
        rank = 1, -- always spawn pet packages on base V1 logic
        team = 2,
        starting_hp = starting_hp,
    }

    if pet_chip_id and pet_chip_id > 0 and pet_chip_amount > 0 then
        pet_enemy.pet_chip_id = pet_chip_id
        pet_enemy.pet_chip_amount = 1
        bridge_chip_id = pet_chip_id
    end

    pet_enemy.pet_bridge_name = build_pet_bridge_name(bridge_chip_id, pet_attack_rank)

print("[PET INJECT OK]",
    tostring(pet_enemy.name),
    "rank="..tostring(pet_enemy.rank),
    "hp="..tostring(pet_enemy.starting_hp),
    "chip="..tostring(pet_enemy.pet_chip_id or 0)
)
    table.insert(ei.enemies, pet_enemy)
    local pet_id = #ei.enemies

    local function can_place(r, c)
        if type(ei.positions[r]) ~= "table" then return false end
        if tonumber(ei.positions[r][c] or 0) ~= 0 then return false end
        if type(ei.obstacle_positions) == "table" and type(ei.obstacle_positions[r]) == "table" then
            if tonumber(ei.obstacle_positions[r][c] or 0) ~= 0 then return false end
        end
        if type(ei.teams) == "table" and type(ei.teams[r]) == "table" then
            if tonumber(ei.teams[r][c] or 0) ~= 2 then return false end
        end
        return true
    end

    -- Requested spawn: (1,1). Fallback inside blue side if occupied.
    local candidates = {
        {1,1},
        {2,1},{3,1},
        {1,2},{2,2},{3,2},
        {1,3},{2,3},{3,3},
    }

    for _, rc in ipairs(candidates) do
        local r, c = rc[1], rc[2]
        if can_place(r, c) then
            ei.__armed_pet_joined = true
            ei.__armed_pet_uid = tostring(armed.uid or "")
            ei.__armed_pet_kind = tostring(armed.kind or "")
            ei.positions[r][c] = pet_id
            return ei
        end
    end

    -- If we can't place it, undo the injection
    table.remove(ei.enemies, pet_id)
    return encounter_info
end

local load_encounters_for_areas = function ()
    local areas = Net.list_areas()
    local loaded_tables = {}

    for _, area_id in ipairs(areas) do
        local encounter_table_path = ezconfig.ENCOUNTERS_PATH .. area_id
        local status, area_data = pcall(function ()
            return require(encounter_table_path)
        end)

        if status == true and area_data then
            area_data.encounters = area_data.encounters or {}
            loaded_tables[area_id] = area_data

            for _, encounter_info in ipairs(area_data.encounters) do
                encounter_info._area_id = area_id

                if encounter_info.path and not provided_encounter_assets[encounter_info.path] then
                    print('[ezencounters] providing mob package ' .. encounter_info.path)
                    Net.provide_asset(area_id, encounter_info.path)
                    provided_encounter_assets[encounter_info.path] = true
                end

                if encounter_info.name then
                    print('[ezencounters] loaded named encounter ' .. encounter_info.name)
                    named_encounters[encounter_info.name] = encounter_info
                end
            end

            local random_cfg = _get_random_encounter_config(area_data)
            if random_cfg then
                local random_path = _get_random_package_path(area_data, random_cfg, false)
                if random_path and not provided_encounter_assets[random_path] then
                    print('[ezencounters] providing random encounter package ' .. random_path)
                    Net.provide_asset(area_id, random_path)
                    provided_encounter_assets[random_path] = true
                end

                local boss_path = _get_random_package_path(area_data, random_cfg, true)
                if boss_path and boss_path ~= random_path and not provided_encounter_assets[boss_path] then
                    print('[ezencounters] providing random boss encounter package ' .. boss_path)
                    Net.provide_asset(area_id, boss_path)
                    provided_encounter_assets[boss_path] = true
                end
            end

            print('[ezencounters] loaded encounter table for ' .. area_id)
        end
    end

    return loaded_tables
end

area_encounter_tables = load_encounters_for_areas()

local function should_record_step(player_id)
    local player_area = Net.get_player_area(player_id)
    if not player_last_position[player_id] then
        return false
    end
    if Net.is_player_battling(player_id) then
        return false
    end
    if ezwarps.player_is_in_animation(player_id) then
        return false
    end
    local last_pos = player_last_position[player_id]
    local last_tile = Net.get_tile(player_area, last_pos.x, last_pos.y, last_pos.z) -- { gid, flipped_horizontally, flipped_vertically, rotated }
    local tile_tileset_info =  Net.get_tileset_for_tile(player_area, last_tile.gid) -- { path, first_gid }?
    if not tile_tileset_info then
        return false
    end
    if string.find(tile_tileset_info.path,'conveyer') then
        return false
    end
    return true
end

ezencounters.increment_steps_since_encounter = function (player_id)
    if not should_record_step(player_id) then
        return
    end
    local player_area = Net.get_player_area(player_id)
    local encounter_table = area_encounter_tables[player_area]
    if not player_steps_since_encounter[player_id] then
        player_steps_since_encounter[player_id] = 1
    else
        player_steps_since_encounter[player_id] = player_steps_since_encounter[player_id] + 1
    end
    if encounter_table then
        if player_steps_since_encounter[player_id] >= encounter_table.minimum_steps_before_encounter then
            ezencounters.try_random_encounter(player_id,encounter_table)
        end
    end
end

ezencounters.handle_player_move = function(player_id, x, y, z)
    local floor = math.floor
    local rounded_pos_x = floor(x)
    local rounded_pos_y = floor(y)
    local rounded_pos_z = floor(z)
    local last_tile = player_last_position[player_id]
    if last_tile then
        if last_tile.x ~= rounded_pos_x or last_tile.y ~= rounded_pos_y or last_tile.z ~= rounded_pos_z then
            --player has moved to a different tile
            player_last_position[player_id] = {x=rounded_pos_x,y=rounded_pos_y,z=rounded_pos_z}
        end
    else
        player_last_position[player_id] = {x=rounded_pos_x,y=rounded_pos_y,z=rounded_pos_z}
    end
    ezencounters.increment_steps_since_encounter(player_id)
end

ezencounters.pick_encounter_from_table = function (encounter_table)
    if not encounter_table or not encounter_table.encounters or #encounter_table.encounters == 0 then
        return nil
    end

    local total_weight = 0
    for _, option in ipairs(encounter_table.encounters) do
        total_weight = total_weight + (tonumber(option.weight) or 0)
    end

    if total_weight <= 0 then
        return encounter_table.encounters[1]
    end

    local crawler = math.random() * total_weight
    for i, option in ipairs(encounter_table.encounters) do
        crawler = crawler - (tonumber(option.weight) or 0)
        if crawler <= 0 then
            return encounter_table.encounters[i]
        end
    end

    return encounter_table.encounters[1]
end

ezencounters.try_random_encounter = function (player_id, encounter_table)
    if math.random() > encounter_table.encounter_chance_per_step then
        return
    end

    local player_area = Net.get_player_area(player_id)
    local encounter_info = _pick_encounter_for_area(player_area, encounter_table)

    if encounter_info then
        ezencounters.begin_encounter(player_id, encounter_info)
    end
end

local function _resolve_pet_xp_award(encounter_info)
    if type(encounter_info) ~= "table" then
        return 5
    end

    local v = encounter_info.pet_exp

    if type(v) == "table" then
        v = v[1] or v.amount or v.value
    end

    if v == nil then
        return 5
    end

    return math.max(0, math.floor(tonumber(v) or 0))
end

-- FIXED: Now returns the stats
ezencounters.begin_encounter_by_name = function(player_id,encounter_name,trigger_object)
    return async(function ()
        local encounter_info = named_encounters[encounter_name]
        if encounter_info then
            local stats = await(ezencounters.begin_encounter(player_id,encounter_info,trigger_object))
            return stats
        else
            print('[ezencounters] no encounter with name ',encounter_name,' has been added to any encounter tables!')
            return nil
        end
    end)
end

ezencounters.begin_encounter = function (player_id,encounter_info,trigger_object)
    return async(function ()
        ezencounters.clear_tiles_since_encounter(player_id)
        if _G.Tournaments and _G.Tournaments.unregister_if_queued_for_battle then
            pcall(
                _G.Tournaments.unregister_if_queued_for_battle,
                player_id,
                "You were unregistered from the tournament because you started another battle."
            )
        end

        local final_encounter_info = _inject_armed_pet(player_id, encounter_info)

        players_in_encounters[player_id] = {
            encounter_info = encounter_info,
            final_encounter_info = final_encounter_info,
            trigger_object = trigger_object,
            armed_pet_joined = type(final_encounter_info) == "table" and final_encounter_info.__armed_pet_joined == true,
            armed_pet_uid = type(final_encounter_info) == "table" and tostring(final_encounter_info.__armed_pet_uid or "") or "",
            pet_xp_award = _resolve_pet_xp_award(final_encounter_info),
        }

        ezbus:emit("encounter_started", {
            player_id = player_id,
            encounter_info = encounter_info,
            final_encounter_info = final_encounter_info,
            trigger_object = trigger_object
        })

        local stats = await(Async.initiate_encounter(player_id, final_encounter_info.path, final_encounter_info))
        return stats
    end)
end

ezencounters.clear_tiles_since_encounter = function (player_id)
    player_steps_since_encounter[player_id] = nil
end

ezencounters.clear_last_position = function (player_id)
    print('[ezencounters] clearing last position')
    player_last_position[player_id] = nil
    ezencounters.clear_tiles_since_encounter(player_id)
    players_in_encounters[player_id] = nil
end

Net:on("battle_results", function(event)
    local player_id = event.player_id
    if players_in_encounters[player_id] then
        local player_encounter = players_in_encounters[player_id]

        if encounter_finished_callbacks[player_id] then
            encounter_finished_callbacks[player_id](event)
            encounter_finished_callbacks[player_id] = nil
        end

        local flags = _result_flags(event)

        if Pets
            and type(Pets.consume_armed_pet_battle_chip) == "function"
            and player_encounter.armed_pet_joined
            and player_encounter.armed_pet_uid ~= ""
            and (flags.won or flags.lost)
        then
            local ok, consumed, chip_id, remaining = pcall(
                Pets.consume_armed_pet_battle_chip,
                player_id,
                player_encounter.armed_pet_uid
            )

            if ok and consumed then
                print("[PET CHIP]",
                    "pid=" .. tostring(player_id),
                    "uid=" .. tostring(player_encounter.armed_pet_uid),
                    "chip=" .. tostring(chip_id),
                    "remaining=" .. tostring(remaining)
                )
            elseif not ok then
                print("[PET CHIP] consume failed: " .. tostring(consumed))
            end
        end

        local pet_xp_award = math.max(0, math.floor(tonumber(player_encounter.pet_xp_award) or 5))

        if Pets
            and player_encounter.armed_pet_joined
            and player_encounter.armed_pet_uid ~= ""
            and flags.won
            and pet_xp_award > 0
        then
            local ok, awarded, new_total, skill_gained, effective_amount, mood = pcall(
                Pets.award_armed_pet_battle_xp,
                player_id,
                pet_xp_award,
                player_encounter.armed_pet_uid
            )

            if ok and awarded then
                print("[PET XP]",
                    "pid=" .. tostring(player_id),
                    "uid=" .. tostring(player_encounter.armed_pet_uid),
                    "+" .. tostring(effective_amount or pet_xp_award),
                    "mood=" .. tostring(mood or "neutral"),
                    "total=" .. tostring(new_total),
                    "skill_gained=" .. tostring(skill_gained or 0)
                )
            elseif not ok then
                print("[PET XP] award failed: " .. tostring(awarded))
            end
        end

        if Pets
            and type(Pets.register_armed_pet_battle_completion) == "function"
            and player_encounter.armed_pet_joined
            and player_encounter.armed_pet_uid ~= ""
            and (flags.won or flags.lost)
        then
            local ok, recorded, progress, fatigue_added, new_fatigue, new_mood = pcall(
                Pets.register_armed_pet_battle_completion,
                player_id,
                player_encounter.armed_pet_uid
            )

            if ok and recorded and (tonumber(fatigue_added) or 0) > 0 then
                print("[PET FATIGUE]",
                    "pid=" .. tostring(player_id),
                    "uid=" .. tostring(player_encounter.armed_pet_uid),
                    "fatigue_added=" .. tostring(fatigue_added),
                    "fatigue=" .. tostring(new_fatigue),
                    "mood=" .. tostring(new_mood),
                    "progress=" .. tostring(progress)
                )
            elseif not ok then
                print("[PET FATIGUE] record failed: " .. tostring(recorded))
            end
        end

        local encounter_info = player_encounter.encounter_info
        local final_encounter_info = player_encounter.final_encounter_info

        local area_id =
            (encounter_info and encounter_info._area_id)
            or (final_encounter_info and final_encounter_info._area_id)
            or Net.get_player_area(player_id)

        local area_table = area_id and area_encounter_tables[area_id] or nil

        -- Always apply area rewards if this area defines them.
        -- This is what makes rewards = { money=..., health=... } actually work.
        _apply_area_result_awards(player_id, area_table, encounter_info or final_encounter_info, event)

        -- Run any encounter/area result callbacks once each.
        local ran_callbacks = {}

        local function run_result_callback(cb, info)
            if type(cb) == "function" and not ran_callbacks[cb] then
                ran_callbacks[cb] = true
                cb(player_id, info or encounter_info or final_encounter_info, event)
            end
        end

        run_result_callback(encounter_info and encounter_info.results_callback, encounter_info)
        run_result_callback(final_encounter_info and final_encounter_info.results_callback, final_encounter_info)
        run_result_callback(area_table and area_table.results_callback, encounter_info or final_encounter_info)
        run_result_callback(
            area_table and area_table.random_encounters and area_table.random_encounters.results_callback,
            encounter_info or final_encounter_info
        )

        players_in_encounters[player_id] = nil
    end

    ezbus:emit("encounter_finished", {
        player_id = player_id,
        stats = {
            health = event.health,
            time = event.time,
            ran = event.ran,
            emotion = event.emotion,
            turns = event.turns,
            enemies = event.enemies,
            score = event.score
        }
    })
end)

ezencounters.handle_player_transfer = ezencounters.clear_last_position

ezencounters.handle_player_disconnect = function (player_id)
    encounter_finished_callbacks[player_id] = nil
    ezencounters.clear_last_position(player_id)
end

local function on_radius_encounter_triggered(event)
    return async(function ()
        print('[ezencounters] radius encounter triggered ',event.object.custom_properties)
        local player_area = Net.get_player_area(event.player_id)
        local is_hidden_already = ezmemory.object_is_hidden_from_player(event.player_id,player_area,event.object.id)
        if is_hidden_already then
            return
        end
        local encounter_name = event.object.custom_properties["Name"]
        local stats = false
        if encounter_name then
            stats = await(ezencounters.begin_encounter_by_name(event.player_id,encounter_name,event.object))
        else
            local encounter_info = {path=event.object.custom_properties["Path"]}
            stats = await(ezencounters.begin_encounter(event.player_id,encounter_info,event.object))
        end
        if stats then
            if stats.ran or stats.health == 0 then
                return stats -- dont hide the encounter if the player ran or lost
            end
            local player_area = Net.get_player_area(event.player_id)
            if event.object.custom_properties["Once"] == "true" then
                ezmemory.hide_object_from_player(event.player_id,player_area,event.object.id)
            end
        end
        ezmemory.hide_object_from_player_till_disconnect(event.player_id,player_area,event.object.id)
    end)
end

-- Register handler for Radius Encounter objects
object_registry.register_handler("Radius Encounter", function(area_id, object)
    local radius = tonumber(object.custom_properties["Radius"] or 1)
    local emitter = eztriggers.add_radius_trigger(area_id, object, radius, radius, 0, 0)
    emitter:on('entered', function(event)
        return on_radius_encounter_triggered(event)
    end)
end)

Net:on("tick", function()
    for player_id, packet in pairs(pending_battle_reward_packets) do
        packet.ticks = packet.ticks - 1
        if packet.ticks <= 0 then
            _send_rewards_and_fixup_wallet(player_id, packet.rewards)
            pending_battle_reward_packets[player_id] = nil
        end
    end
end)

Net:on("player_disconnect", function(event)
    pending_battle_reward_packets[event.player_id] = nil
end)

return ezencounters