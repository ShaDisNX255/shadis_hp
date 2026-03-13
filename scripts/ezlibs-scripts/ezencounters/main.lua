local ezwarps = require('scripts/ezlibs-scripts/ezwarps/main')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local helpers = require('scripts/ezlibs-scripts/helpers')
local eztriggers = require('scripts/ezlibs-scripts/eztriggers')
local PetsOK, Pets = pcall(require, "scripts/ezlibs-custom/pets")
if not PetsOK then
    Pets = nil
end

local ezencounters = {}
local players_in_encounters = {}
local player_last_position = {}
local player_steps_since_encounter = {}
local named_encounters = {}
local provided_encounter_assets = {}
local encounter_finished_callbacks = {}

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
    local area_encounter_tables = {}
    for i, area_id in ipairs(areas) do
        local encounter_table_path = 'encounters/'..area_id
        local status, err = pcall(function () require(encounter_table_path) end)
        if status == true then
            area_encounter_tables[area_id] = require(encounter_table_path)
            for index, encounter_info in ipairs(area_encounter_tables[area_id].encounters) do
                if not provided_encounter_assets[encounter_info.path] then
                    print('[ezencounters] providing mob package '..encounter_info.path)
                    Net.provide_asset(area_id, encounter_info.path)
                    provided_encounter_assets[encounter_info.path] = true
                end
                if encounter_info.name then
                    print('[ezencounters] loaded named encounter '..encounter_info.name)
                    named_encounters[encounter_info.name] = encounter_info
                end
            end
            print('[ezencounters] loaded encounter table for '..area_id)
        end
    end
    return area_encounter_tables
end

local area_encounter_tables = load_encounters_for_areas()

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
    local total_weight = 0
    for _, option in ipairs(encounter_table.encounters) do
        total_weight = total_weight + option.weight
    end
    local crawler = math.random() * total_weight
    for i, option in ipairs(encounter_table.encounters) do
        crawler = crawler - option.weight
        if crawler <= 0 then
            return encounter_table.encounters[i]
        end
    end
    return encounter_table.encounters[1]
end

ezencounters.try_random_encounter = function (player_id,encounter_table)
    if math.random() <= encounter_table.encounter_chance_per_step then
        local encounter_info = ezencounters.pick_encounter_from_table(encounter_table)
        ezencounters.begin_encounter(player_id, encounter_info)
    end
end

ezencounters.begin_encounter_by_name = function(player_id,encounter_name,trigger_object)
    return async(function ()
        local encounter_info = named_encounters[encounter_name]
        if encounter_info then
            await(ezencounters.begin_encounter(player_id,encounter_info,trigger_object))
        else
            print('[ezencounters] no encounter with name ',encounter_name,' has been added to any encounter tables!')
        end
    end)
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

ezencounters.begin_encounter = function (player_id,encounter_info,trigger_object)
    return async(function ()
        --print('[ezencounters] beginning encounter for',player_id)
        ezencounters.clear_tiles_since_encounter(player_id)

        local final_encounter_info = _inject_armed_pet(player_id, encounter_info)

        players_in_encounters[player_id] = {
            encounter_info = encounter_info,
            final_encounter_info = final_encounter_info,
            armed_pet_joined = type(final_encounter_info) == "table" and final_encounter_info.__armed_pet_joined == true,
            armed_pet_uid = type(final_encounter_info) == "table" and tostring(final_encounter_info.__armed_pet_uid or "") or "",
            pet_xp_award = _resolve_pet_xp_award(final_encounter_info),
        }

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

        if player_encounter.encounter_info.results_callback then
            player_encounter.encounter_info.results_callback(player_id, player_encounter.encounter_info, event)
        end

        players_in_encounters[player_id] = nil
    end
    -- stats = { health: number, score: number, time: number, ran: bool, emotion: number, turns: number, npcs: { id: String, health: number }[] }
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

local areas = Net.list_areas()
for i, area_id in next, areas do
    --filter and store an array of all radius encounters
    local objects = Net.list_objects(area_id)
    for j, object_id in next, objects do
        local object = Net.get_object_by_id(area_id, object_id)
        if object.type == "Radius Encounter" then
            local radius = tonumber(object.custom_properties["Radius"] or 1)
            local emitter = eztriggers.add_radius_trigger(area_id,object,radius,radius,0,0)
            emitter:on('entered_radius',function(event)
                return on_radius_encounter_triggered(event)
            end)
        end
    end
end

return ezencounters