local Direction = require("scripts/ezlibs-scripts/direction")
local helpers = require('scripts/ezlibs-scripts/helpers')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local ezcache = require('scripts/ezlibs-scripts/ezcache')
local object_registry = require('scripts/ezlibs-scripts/object_registry')
local math = require('math')
local ezbus = require('scripts/ezlibs-scripts/ezbus')
local quest_progress = require('scripts/ezlibs-scripts/quest_progress')

local eznpcs = {}
local placeholder_to_botid = {}          -- area_id -> placeholder_id -> global bot ID (for non-exclusive NPCs)
local exclusive_npcs = {}                -- player_id -> { placeholder_id = bot_id }
local exclusive_placeholders = {}        -- list of { area_id, object_id } for all exclusive NPC placeholders

-- Deferred NPC placeholders are registered at map load but do not create bots.
-- Systems such as timed raids explicitly spawn/despawn them through the public API.
local deferred_placeholders = {}         -- area_id -> placeholder_id -> true

-- NEW: Quest-exclusive NPC data
local quest_exclusive_placeholders = {}  -- list of { area_id, object_id, quest_name, required_state }
local quest_exclusive_placeholder_keys = {}
local quest_exclusive_npcs = {}           -- player_id -> { placeholder_id = bot_id }

local npcs = {}                           -- global bot ID -> npc data (for all bots, including exclusive)
local current_player_conversation = {}

local npc_asset_folder = '/server/assets/ezlibs-assets/eznpcs/'
local custom_events_script_path = 'scripts/events/eznpcs_events'
local custom_events_script_loaded = false
local generic_npc_mug_animation_path = npc_asset_folder..'mug/mug.animation'
local events = require('scripts/ezlibs-scripts/eznpcs/dialogue_types')
local npc_required_properties = {"Direction","Asset Name"}
if ezcache.add_cacheable_type then
    ezcache.add_cacheable_type("NPC")
    ezcache.add_cacheable_type("DeferredNPC")
    ezcache.add_cacheable_type("Waypoint")
    ezcache.add_cacheable_type("Dialogue")
    ezcache.add_cacheable_type("Shop Item")
    ezcache.add_cacheable_type("Mystery Option")
end


local function printd(...)
    local arg={...}
    print('[eznpcs]',table.unpack(arg))
end

-- Helper to safely evaluate boolean properties from Tiled (can be boolean or string)
local function is_property_true(val)
    if val == true then return true end
    if type(val) == "string" then return val:lower() == "true" end
    if type(val) == "number" then return val ~= 0 end
    return false
end

-- Helper: get all players currently in the server (across all areas)
local function get_all_players()
    local players = {}
    local areas = Net.list_areas()
    for _, area_id in ipairs(areas) do
        local area_players = Net.list_players(area_id) or {}
        for _, pid in ipairs(area_players) do
            table.insert(players, pid)
        end
    end
    return players
end

-- Helper: exclude a bot from everyone except the owner
local function exclude_except_for(owner_id, bot_id)
    local all_players = get_all_players()
    for _, pid in ipairs(all_players) do
        if pid ~= owner_id then
            Net.exclude_actor_for_player(pid, bot_id)
        end
    end
    printd("Excluded bot", bot_id, "from all except", owner_id)
end

-- Helper: include a bot for all players (used when creating a non-exclusive bot)
local function include_for_all(bot_id)
    local all_players = get_all_players()
    for _, pid in ipairs(all_players) do
        Net.include_actor_for_player(pid, bot_id)
    end
end


function eznpcs.get_dialogue_mugshot(npc,player_id,dialogue)
    local mugshot_asset_name = npc.asset_name
    local custom_mugshot = dialogue.custom_properties["Mugshot"]
    local mug = {}
    if custom_mugshot then
        mugshot_asset_name = custom_mugshot
    end
    mug.texture_path = npc_asset_folder.."mug/"..mugshot_asset_name..".png"
    mug.animation_path = npc.mug_animation_path
    if mugshot_asset_name == "player" then
        local player_mugshot = Net.get_player_mugshot(player_id)
        mug.texture_path = player_mugshot.texture_path
        mug.animation_path = player_mugshot.animation_path
    end
    return mug
end

function do_dialogue(npc,player_id,dialogue,relay_object)
    return async(function ()
        local dialogue_promise = nil

        local area_id = Net.get_player_area(player_id)
        local dialogue_type = dialogue.custom_properties["Dialogue Type"]
        local event_name = dialogue.custom_properties["Event Name"]
        if event_name then
            --legacy override for people still using Event Name
            dialogue_type = event_name
        end
        if dialogue_type == nil then
            printd("dialogue "..dialogue.id.." has no Dialogue Type specified.")
            return
        end
        
        if events[dialogue_type] then
            dialogue_promise = events[dialogue_type].action(npc,player_id,dialogue,relay_object)
        end

        local next_dialogue_id = await(dialogue_promise)
        if not next_dialogue_id then
            return
        end

        local dialogue = ezcache.get_object_by_id_cached(area_id,next_dialogue_id)
        if not dialogue then
            return
        end
        return await(do_dialogue(npc,player_id,dialogue,relay_object))
    end)
end

-- Creates a bot (global or per-player) and returns its npc_data
function create_bot_from_object(area_id, object, player_id, exclusive_kind)
    if not object then return end
    local x = object.x
    local y = object.y
    local z = object.z

    for i, prop_name in pairs(npc_required_properties) do
        if not object.custom_properties[prop_name] then
            printd('NPC objects require the custom property '..prop_name)
            return false
        end
    end  

    local npc_asset_name = object.custom_properties["Asset Name"]
    local npc_animation_name = object.custom_properties["Animation Name"] or false
    local npc_mug_animation_name = object.custom_properties["Mug Animation Name"] or false
    local npc_turns_to_talk = is_property_true(object.custom_properties["Dont Face Player"])
    local direction = object.custom_properties.Direction
    local speed = tonumber(
        object.custom_properties["Walk Speed"]
        or object.custom_properties["Speed"]
        or 1
    ) or 1

    -- Debug: print asset paths
    printd("Creating NPC with asset:", npc_asset_name, "texture:", npc_asset_folder.."sheet/"..npc_asset_name..".png")

    -- Create the bot (initially visible to all)
    local npc = create_npc(area_id, npc_asset_name, x, y, z, direction,
                       object.name, npc_animation_name, npc_mug_animation_name, npc_turns_to_talk, speed)

    if not npc then 
        printd("Failed to create bot for", npc_asset_name)
        return 
    end

    -- If this is an exclusive NPC for a specific player, hide it from everyone else
    if player_id then
        local target = exclusive_npcs
        local label = "Exclusive"

        if exclusive_kind == "quest" then
            target = quest_exclusive_npcs
            label = "Quest-exclusive"
        end

        if not target[player_id] then
            target[player_id] = {}
        end

        target[player_id][tostring(object.id)] = npc.bot_id

        exclude_except_for(player_id, npc.bot_id)
        printd(label .. " bot", npc.bot_id, "created for player", player_id)
    else
        -- Global NPC: store in placeholder_to_botid and ensure visible to all
        if not placeholder_to_botid[area_id] then placeholder_to_botid[area_id] = {} end
        placeholder_to_botid[area_id][tostring(object.id)] = npc.bot_id
        printd("Global bot", npc.bot_id, "created for placeholder", object.id)
    end

    if object.custom_properties["Dialogue Type"] then
        npc.first_dialogue = object
        local chat_behaviour = chat_behaviour()
        add_behaviour(npc, chat_behaviour)
    end

    if object.custom_properties["Next Waypoint 1"] then
        local waypoint_follow_behaviour = waypoint_follow_behaviour(object.custom_properties["Next Waypoint 1"])
        add_behaviour(npc, waypoint_follow_behaviour)
    end

    return npc
end

function create_npc(area_id,asset_name,x,y,z,direction,bot_name,animation_name,mug_animation_name,npc_turns_to_talk,speed)
    local texture_path = npc_asset_folder.."sheet/"..asset_name..".png"
    local animation_path = npc_asset_folder.."sheet/"..asset_name..".animation"
    local mug_animation_path = generic_npc_mug_animation_path
    local name = bot_name or nil
    --Override animations if they were provided as custom properties
    if animation_name then
        animation_path = npc_asset_folder..'sheet/'..animation_name..".animation"
    end
    if mug_animation_name then
        mug_animation_path = npc_asset_folder..'mug/'..mug_animation_name..".animation"
    end
    if npc_turns_to_talk == nil then
        npc_turns_to_talk = true
    end
    --Create bot
    local npc_data = {
        asset_name=asset_name,
        bot_id=nil, 
        name=name, 
        area_id=area_id, 
        texture_path=texture_path, 
        animation_path=animation_path, 
        mug_animation_path=mug_animation_path,
        x=x, 
        y=y, 
        z=z, 
        direction=direction, 
        solid=true,
        size=0.2,
        speed=tonumber(speed) or 1,
        dont_face_player=npc_turns_to_talk,
        warp_in = true,  -- Explicitly set warp_in to ensure visibility
    }
    printd("Creating bot with texture:", texture_path, "animation:", animation_path)
    local lastBotId = Net.create_bot(npc_data)
    if not lastBotId then 
        printd("Net.create_bot returned nil for", asset_name)
        return nil 
    end
    npc_data.bot_id = lastBotId
    npcs[lastBotId] = npc_data
    printd('created npc '..(name or "unnamed")..' id:'..lastBotId..' at ('..x..','..y..','..z..')')
    return npc_data
end

function add_behaviour(npc,behaviour)
    if behaviour.type and behaviour.action then
        npc[behaviour.type] = behaviour
        if behaviour.initialize then
            behaviour.initialize(npc)
        end
    end
end

function clear_player_conversation(player_id)
    Net.unlock_player_input(player_id)
    local bot_id = current_player_conversation[player_id]
    if bot_id then
        local npc = npcs[bot_id]
        if npc and not npc.dont_face_player then
            Net.set_bot_direction(npc.bot_id, npc.direction)
        end
        current_player_conversation[player_id] = nil
        ezbus:emit("dialogue_ended", {
            player_id = player_id,
            npc_id = bot_id
        })
    end
end

--Behaviour factories
function chat_behaviour()
    behaviour = {
        type='on_interact',
        action=function(npc,player_id,relay_object)
            return async(function ()
                if current_player_conversation[player_id] == npc.bot_id then
                    return
                end
                current_player_conversation[player_id] = npc.bot_id

                if not npc.dont_face_player then
                    local player_pos = Net.get_player_position(player_id)
                    local dir = player_pos and Direction.from_points(npc, player_pos) or nil
                    if dir then
                        Net.set_bot_direction(npc.bot_id, dir)
                    end
                end

                local dialogue = npc.first_dialogue
                Net.lock_player_input(player_id)
                await(do_dialogue(npc,player_id,dialogue,relay_object))
                clear_player_conversation(player_id)
            end)
        end
    }
    return behaviour
end

function waypoint_follow_behaviour(first_waypoint_id)
    behaviour = {
        type='on_tick',
        initialize=function(npc)
            local first_waypoint = ezcache.get_object_by_id_cached(npc.area_id, first_waypoint_id)
            if first_waypoint then
                npc.next_waypoint = first_waypoint
            else
                printd('invalid Next Waypoint '..first_waypoint_id)
            end
        end,
        action=function(npc,delta_time)
            move_npc(npc,delta_time)
        end
    }
    return behaviour
end

function do_actor_interaction(player_id,actor_id,relay_object)
    local npc = npcs[actor_id]
    if npc and npc.on_interact then
        npc.on_interact.action(npc,player_id,relay_object)
    end
end

function is_anyone_talking_to_npc(npc_id)
    for player_id, chatty_npc_id in pairs(current_player_conversation) do
        if npc_id == chatty_npc_id then return true end
    end
    return false
end

local idle_anim_by_direction = {
    ["Down Right"] = "IDLE_DR",
    ["Down Left"]  = "IDLE_DL",
    ["Up Right"]   = "IDLE_UR",
    ["Up Left"]    = "IDLE_UL",
    ["Up"]         = "IDLE_U",
    ["Down"]       = "IDLE_D",
    ["Left"]       = "IDLE_L",
    ["Right"]      = "IDLE_R",
}

local function first_nonempty_prop(props, ...)
    if not props then return nil end

    for i = 1, select("#", ...) do
        local key = select(i, ...)
        local value = props[key]

        if value ~= nil and tostring(value) ~= "" then
            return value
        end
    end

    return nil
end

local function restore_npc_idle_animation(npc)
    if not npc or not npc.bot_id then return end

    local idle_state = idle_anim_by_direction[npc.direction]
    if idle_state then
        pcall(Net.animate_bot, npc.bot_id, idle_state, true)
    end
end

local function play_waypoint_animation(npc, waypoint)
    local props = waypoint and waypoint.custom_properties
    if not props then return end

    local anim_state = first_nonempty_prop(
        props,
        "Animation State",
        "Waypoint Animation",
        "Play Animation",
        "Animation"
    )

    if not anim_state then return end

    anim_state = tostring(anim_state)

    -- Default is one-shot. Only loops if you explicitly set Animation Loop = true.
    local loop = is_property_true(first_nonempty_prop(
        props,
        "Animation Loop",
        "Loop Animation"
    ))

    local anim_wait = tonumber(first_nonempty_prop(
        props,
        "Animation Time",
        "Animation Duration",
        "Animation Wait Time"
    ))

    if anim_wait == nil then
        local wait_time = tonumber(props["Wait Time"])
        if wait_time and wait_time > 0 then
            anim_wait = wait_time
        end
    end

    if not loop then
        anim_wait = tonumber(anim_wait) or 0.45

        -- Super tiny waits can make the animation appear skipped.
        if anim_wait < 0.20 then
            anim_wait = 0.45
        end
    else
        anim_wait = tonumber(anim_wait) or 0
    end

    -- Important: force the client out of the previous state first.
    -- This helps one-shot animations restart reliably.
    local restart_delay = tonumber(first_nonempty_prop(
        props,
        "Animation Restart Delay",
        "Animation Delay"
    )) or 0.05

    if restart_delay < 0.03 then
        restart_delay = 0.05
    end

    npc.waypoint_anim_token = (tonumber(npc.waypoint_anim_token) or 0) + 1
    local token = npc.waypoint_anim_token

    if not loop then
        restore_npc_idle_animation(npc)
    end

    npc.wait_time = math.max(tonumber(npc.wait_time) or 0, anim_wait + restart_delay)
    npc.restore_anim_after_wait = not loop

    async(function()
        await(Async.sleep(restart_delay))

        if not npc or token ~= npc.waypoint_anim_token then
            return
        end

        if Net.is_bot then
            local ok_exists, exists = pcall(Net.is_bot, npc.bot_id)
            if ok_exists and not exists then
                return
            end
        end

        local ok, err = pcall(Net.animate_bot, npc.bot_id, anim_state, loop)
        if not ok then
            printd("Waypoint animation failed:", tostring(anim_state), tostring(err))
        end
    end)
end

function move_npc(npc,delta_time)
    if is_anyone_talking_to_npc(npc.bot_id) then return end
    if npc.wait_time and npc.wait_time > 0 then
        npc.wait_time = npc.wait_time - delta_time

        if npc.wait_time <= 0 and npc.restore_anim_after_wait then
            npc.restore_anim_after_wait = nil
            restore_npc_idle_animation(npc)
        end

        return
    end

    local area_id = Net.get_bot_area(npc.bot_id)
    local waypoint = npc.next_waypoint

    local distance = math.sqrt((waypoint.x - npc.x) ^ 2 + (waypoint.y - npc.y) ^ 2)
    if distance < npc.size then
        on_npc_reached_waypoint(npc,waypoint)
        return
    end
    
    local angle = math.atan(waypoint.y - npc.y, waypoint.x - npc.x)
    local vel_x = math.cos(angle) * npc.speed
    local vel_y = math.sin(angle) * npc.speed

    local new_pos = {x=0,y=0,z=npc.z,size=npc.size}

    new_pos.x = npc.x + vel_x * delta_time
    new_pos.y = npc.y + vel_y * delta_time

    if helpers.position_overlaps_something(new_pos,area_id) then return end

    Net.move_bot(npc.bot_id, new_pos.x, new_pos.y, new_pos.z)
    npc.x = new_pos.x
    npc.y = new_pos.y
end

function on_npc_reached_waypoint(npc,waypoint)
    local has_correct_type = (waypoint.type == "Waypoint")
    if not has_correct_type then
        printd("WARNING Waypoint "..waypoint.id.." at "..waypoint.x..","..waypoint.y.." in "..npc.area_id.." has incorrect type and wont be cached")
    end
    local props = waypoint.custom_properties or {}

    if props['Direction'] ~= nil then
        npc.direction = props['Direction']
        Net.set_bot_direction(npc.bot_id, props['Direction'])
    end

    if props['Wait Time'] ~= nil then
        npc.wait_time = tonumber(props['Wait Time']) or 0
    end

    play_waypoint_animation(npc, waypoint)
    local waypoint_type = "first"
    if waypoint.custom_properties["Waypoint Type"] then
        waypoint_type = waypoint.custom_properties["Waypoint Type"]
    end
    local next_waypoints = helpers.extract_numbered_properties(waypoint,"Next Waypoint ")
    local next_waypoint_id = nil
    if waypoint_type == "first" then
        next_waypoint_id = first_value_from_table(next_waypoints)
    end
    if waypoint_type == "random" then
        local next_waypoint_index = math.random(#next_waypoints)
        next_waypoint_id = next_waypoints[next_waypoint_index]
    end
    local date_b = waypoint.custom_properties['Date']
    if waypoint_type == "before" then
        if date_b then
            next_waypoint_id = next_waypoints[2]
            if helpers.is_now_before_date(date_b) then
                next_waypoint_id = next_waypoints[1]
            end
        end
    end
    if waypoint_type == "after" then
        if date_b then
            next_waypoint_id = next_waypoints[2]
            if not helpers.is_now_before_date(date_b) then
                next_waypoint_id = next_waypoints[1]
            end
        end
    end

    if next_waypoint_id then
        npc.next_waypoint = ezcache.get_object_by_id_cached(npc.area_id,next_waypoint_id)
    end
end

local function register_quest_exclusive_placeholder(area_id, object, quest_name, required_state)
    local key = tostring(area_id) .. ":" .. tostring(object.id)

    if quest_exclusive_placeholder_keys[key] then
        return
    end

    quest_exclusive_placeholder_keys[key] = true

    table.insert(quest_exclusive_placeholders, {
        area_id = area_id,
        object_id = object.id,
        quest_name = quest_name,
        required_state = required_state or "active",
    })

    printd(
        "Registered quest-exclusive placeholder id " .. tostring(object.id)
        .. " in " .. tostring(area_id)
        .. " for quest " .. tostring(quest_name)
    )
end

local function remove_quest_exclusive_bot(bot_id, warp_out)
    if not bot_id then
        return
    end

    if warp_out then
        -- Match the warp-out removal used by pets when starting expeditions.
        local ok = pcall(Net.remove_bot, bot_id, true)

        -- Fall back to ordinary removal on server builds that do not
        -- support the optional warp-out argument.
        if not ok then
            pcall(Net.remove_bot, bot_id)
        end
    else
        pcall(Net.remove_bot, bot_id)
    end

    npcs[bot_id] = nil
end

-- Helper to update quest-exclusive NPCs for a given player
local function update_quest_exclusive_for_player(
    player_id,
    changed_quest_id,
    warp_out
)
    local current = quest_exclusive_npcs[player_id]

    if not current then
        current = {}
        quest_exclusive_npcs[player_id] = current
    end

    for _, entry in ipairs(quest_exclusive_placeholders) do
        -- On login, changed_quest_id is nil and every placeholder is checked.
        -- After qset, only NPCs controlled by that Quest ID are checked.
        local relevant =
            changed_quest_id == nil
            or tostring(entry.quest_name) == tostring(changed_quest_id)

        if relevant then
            local placeholder_id = tostring(entry.object_id)
            local bot_id = current[placeholder_id]

            -- Clear stale bookkeeping if the engine already removed this bot.
            if bot_id and Net.is_bot then
                local ok_exists, exists = pcall(Net.is_bot, bot_id)

                if ok_exists and not exists then
                    current[placeholder_id] = nil
                    npcs[bot_id] = nil
                    bot_id = nil
                end
            end

            local state = quest_progress.get_state(
                player_id,
                entry.quest_name
            )

            local should_exist =
                state ~= nil
                and tostring(state) == tostring(entry.required_state)

            if should_exist then
                -- Already present and still eligible: leave it completely alone.
                if not bot_id then
                    local object = ezcache.get_object_by_id_cached(
                        entry.area_id,
                        entry.object_id
                    )

                    if object then
                        local npc = create_bot_from_object(
                            entry.area_id,
                            object,
                            player_id,
                            "quest"
                        )

                        if npc then
                            printd(
                                "Quest-exclusive bot",
                                npc.bot_id,
                                "created for player",
                                player_id,
                                "quest",
                                entry.quest_name
                            )
                        end
                    end
                end
            elseif bot_id then
                -- This NPC was present, but its required state no longer matches.
                remove_quest_exclusive_bot(bot_id, warp_out == true)
                current[placeholder_id] = nil

                printd(
                    "Quest-exclusive bot",
                    bot_id,
                    "removed for player",
                    player_id,
                    "quest",
                    entry.quest_name,
                    "state",
                    tostring(state)
                )
            end
        end
    end

    if next(current) == nil then
        quest_exclusive_npcs[player_id] = nil
    end
end

-- Register handler for NPC objects
object_registry.register_handler("NPC", function(area_id, object)
    local props = object.custom_properties or {}
    local is_quest = is_property_true(props["Quest NPC"])
    local is_exclusive = is_property_true(props["Player Exclusive"])
    local quest_exclusive = props["Quest Exclusive"]   -- string (quest name) or nil

    if quest_exclusive then
        -- This is a quest-exclusive placeholder
        local required_state = props["Quest State"] or "active"

        register_quest_exclusive_placeholder(
            area_id,
            object,
            quest_exclusive,
            required_state
        )
    elseif is_quest or is_exclusive then
        printd("Skipping quest/exclusive NPC placeholder id "..object.id.." in "..area_id)
        if is_exclusive then
            -- Store exclusive placeholder for later use
            table.insert(exclusive_placeholders, {area_id = area_id, object_id = object.id})
        end
    else
        create_bot_from_object(area_id, object)
    end
end)


-- DeferredNPC objects are intentionally not created during map preload.
-- Their Tiled object remains the source of position, asset, dialogue, and direction.
object_registry.register_handler("DeferredNPC", function(area_id, object)
    area_id = tostring(area_id)
    local placeholder_id = tostring(object.id)

    deferred_placeholders[area_id] = deferred_placeholders[area_id] or {}
    deferred_placeholders[area_id][placeholder_id] = true

    printd("Registered deferred NPC placeholder", placeholder_id, "in", area_id)
end)

-- Public API
function eznpcs.load_npcs()
    local areas = Net.list_areas()
    for i, area_id in next, areas do
        eznpcs.add_npcs_to_area(area_id)
    end
end

function eznpcs.add_npcs_to_area(area_id)
    -- Legacy: scan area for NPCs (already handled by registry, but keep for completeness)
    local objects = Net.list_objects(area_id)
    for i, object_id in next, objects do
        local object = ezcache.get_object_by_id_cached(area_id, object_id)
        if object and object.type == "NPC" then
            local props = object.custom_properties or {}
            local is_quest = is_property_true(props["Quest NPC"])
            local is_exclusive = is_property_true(props["Player Exclusive"])
            local quest_exclusive = props["Quest Exclusive"]
            if quest_exclusive then
                -- Already handled by the registry in most cases.
                -- This helper safely ignores duplicate registration.
                local required_state = props["Quest State"] or "active"

                register_quest_exclusive_placeholder(
                    area_id,
                    object,
                    quest_exclusive,
                    required_state
                )
            elseif not is_quest and not is_exclusive then
                create_bot_from_object(area_id, object)
            elseif is_exclusive then
                -- Also store in exclusive_placeholders in case area was added after startup
                table.insert(exclusive_placeholders, {area_id = area_id, object_id = object.id})
            end
        end
    end
end

function eznpcs.add_event(event_object)
    if not (event_object.name and event_object.action) then
        printd('Cant add invalid event, events need a name and action {}')
        return
    end
    if events[event_object.name] then
        printd('WARNING event '..event_object.name..' already exists and will be replaced')
    end
    events[event_object.name] = event_object
    printd('added event '..event_object.name)
end

-- Spawn a DeferredNPC placeholder as a normal global eznpcs bot.
-- Returns the bot ID, or nil when the placeholder cannot be created.
function eznpcs.spawn_deferred_npc(area_id, object_id)
    area_id = tostring(area_id)
    local placeholder_id = tostring(object_id)

    placeholder_to_botid[area_id] = placeholder_to_botid[area_id] or {}

    local existing_bot_id = placeholder_to_botid[area_id][placeholder_id]
    if existing_bot_id then
        if not Net.is_bot then
            return existing_bot_id
        end

        local ok_exists, exists = pcall(Net.is_bot, existing_bot_id)
        if not ok_exists or exists then
            return existing_bot_id
        end

        -- Clear stale bookkeeping if the engine already removed the bot.
        placeholder_to_botid[area_id][placeholder_id] = nil
        npcs[existing_bot_id] = nil
    end

    local object = ezcache.get_object_by_id_cached(area_id, object_id)
    if not object then
        printd("Unable to spawn deferred NPC: object not found", placeholder_id, "in", area_id)
        return nil
    end

    local object_kind = tostring(object.class or object.type or "")
    if object_kind ~= "DeferredNPC" then
        printd("Unable to spawn deferred NPC: placeholder", placeholder_id,
               "has type", object_kind, "instead of DeferredNPC")
        return nil
    end

    deferred_placeholders[area_id] = deferred_placeholders[area_id] or {}
    deferred_placeholders[area_id][placeholder_id] = true

    local npc = create_bot_from_object(area_id, object)
    if not npc then
        return nil
    end

    printd("Spawned deferred NPC", placeholder_id, "as bot", npc.bot_id, "in", area_id)
    return npc.bot_id
end

-- Remove a spawned DeferredNPC completely.
-- Because the bot no longer exists, it cannot render, collide, or receive interaction.
function eznpcs.despawn_deferred_npc(area_id, object_id)
    area_id = tostring(area_id)
    local placeholder_id = tostring(object_id)

    local area_mapping = placeholder_to_botid[area_id]
    local bot_id = area_mapping and area_mapping[placeholder_id] or nil
    if not bot_id then
        return false
    end

    -- Safely end any dialogue that was still attached to this bot.
    local talking_players = {}
    for player_id, conversation_bot_id in pairs(current_player_conversation) do
        if conversation_bot_id == bot_id then
            talking_players[#talking_players + 1] = player_id
        end
    end
    for _, player_id in ipairs(talking_players) do
        clear_player_conversation(player_id)
    end

    if Net.remove_bot then
        local ok_remove, remove_err = pcall(Net.remove_bot, bot_id)
        if not ok_remove then
            printd("Failed to despawn deferred NPC", placeholder_id,
                   "bot", bot_id, "error", tostring(remove_err))
            return false
        end
    end

    npcs[bot_id] = nil
    area_mapping[placeholder_id] = nil

    printd("Despawned deferred NPC", placeholder_id, "bot", bot_id, "from", area_id)
    return true
end

function eznpcs.is_deferred_npc_spawned(area_id, object_id)
    area_id = tostring(area_id)
    local placeholder_id = tostring(object_id)
    local bot_id = placeholder_to_botid[area_id]
        and placeholder_to_botid[area_id][placeholder_id]
        or nil

    if not bot_id then return false end
    if not Net.is_bot then return true end

    local ok_exists, exists = pcall(Net.is_bot, bot_id)
    return (not ok_exists) or exists == true
end

function eznpcs.create_npc_from_object(area_id,object_id)
    local object = ezcache.get_object_by_id_cached(area_id, object_id)
    return create_bot_from_object(area_id, object)
end

function eznpcs.handle_actor_interaction(player_id,actor_id)
    return do_actor_interaction(player_id,actor_id)
end

function eznpcs.on_tick(delta_time)
    if not custom_events_script_loaded then
        custom_events_script_loaded = true
        helpers.safe_require(custom_events_script_path)
    end
    for bot_id, npc in pairs(npcs) do
        if npc.on_tick then
            npc.on_tick.action(npc,delta_time)
        end
    end
end

function eznpcs.create_npc(area_id,asset_name,x,y,z,direction,bot_name,animation_name,mug_animation_name)
    return create_npc(area_id,asset_name,x,y,z,direction,bot_name,animation_name,mug_animation_name)
end

function eznpcs.handle_player_transfer(player_id)
    clear_player_conversation(player_id)
end

function eznpcs.handle_player_join(player_id)
    -- Create player‑exclusive NPCs
    for _, entry in ipairs(exclusive_placeholders) do
        local object = ezcache.get_object_by_id_cached(entry.area_id, entry.object_id)
        if object then
            local hidden = ezmemory.object_is_hidden_from_player(player_id, entry.area_id, entry.object_id)
            if not hidden then
                if not exclusive_npcs[player_id] or not exclusive_npcs[player_id][tostring(entry.object_id)] then
                    create_bot_from_object(entry.area_id, object, player_id)
                end
            end
        end
    end

    -- Create quest‑exclusive NPCs based on current quest state
    update_quest_exclusive_for_player(player_id)

    -- Exclude other players' exclusive NPCs from this new player
    for owner_id, npcs_for_owner in pairs(exclusive_npcs) do
        for placeholder_id, bot_id in pairs(npcs_for_owner) do
            if owner_id ~= player_id then
                Net.exclude_actor_for_player(player_id, bot_id)
            end
        end
    end
    -- Also exclude other players' quest‑exclusive NPCs
    for owner_id, npcs_for_owner in pairs(quest_exclusive_npcs) do
        for placeholder_id, bot_id in pairs(npcs_for_owner) do
            if owner_id ~= player_id then
                Net.exclude_actor_for_player(player_id, bot_id)
            end
        end
    end
end

function eznpcs.handle_player_disconnect(player_id)
    clear_player_conversation(player_id)

    -- Remove player‑exclusive NPCs
    if exclusive_npcs[player_id] then
        for placeholder_id, bot_id in pairs(exclusive_npcs[player_id]) do
            Net.remove_bot(bot_id)
            npcs[bot_id] = nil
        end
        exclusive_npcs[player_id] = nil
    end

    -- Remove quest‑exclusive NPCs
    if quest_exclusive_npcs[player_id] then
        for placeholder_id, bot_id in pairs(quest_exclusive_npcs[player_id]) do
            Net.remove_bot(bot_id)
            npcs[bot_id] = nil
        end
        quest_exclusive_npcs[player_id] = nil
    end
end

function eznpcs.handle_object_interaction(player_id, object_id)
    local area_id = Net.get_player_area(player_id)
    local object = ezcache.get_object_by_id_cached(area_id, object_id)
    if not object then 
        printd("handle_object_interaction: object not found in cache", object_id)
        return 
    end

    -- Check if it's an exclusive NPC placeholder
    if object.type == "NPC" and object.custom_properties then
        if is_property_true(object.custom_properties["Player Exclusive"]) then
            printd("Exclusive NPC interaction for player", player_id, "placeholder", object.id)
            if not exclusive_npcs[player_id] or not exclusive_npcs[player_id][tostring(object.id)] then
                local npc = create_bot_from_object(area_id, object, player_id)
                if npc then
                    do_actor_interaction(player_id, npc.bot_id, object)
                end
            else
                local bot_id = exclusive_npcs[player_id][tostring(object.id)]
                do_actor_interaction(player_id, bot_id, object)
            end
            return
        end

        -- Check if it's a quest-exclusive placeholder
        local quest_exclusive = object.custom_properties["Quest Exclusive"]

        if quest_exclusive then
            printd(
                "Quest-exclusive NPC interaction for player",
                player_id,
                "placeholder",
                object.id
            )

            if not quest_exclusive_npcs[player_id]
                or not quest_exclusive_npcs[player_id][tostring(object.id)]
            then
                local required_state =
                    object.custom_properties["Quest State"]
                    or "active"

                local state = quest_progress.get_state(
                    player_id,
                    quest_exclusive
                )

                if state and state == required_state then
                    local npc = create_bot_from_object(
                        area_id,
                        object,
                        player_id,
                        "quest"
                    )

                    if npc then
                        do_actor_interaction(
                            player_id,
                            npc.bot_id,
                            object
                        )
                    end
                else
                    printd(
                        "Player",
                        player_id,
                        "does not meet quest state for",
                        quest_exclusive
                    )
                end
            else
                local bot_id =
                    quest_exclusive_npcs[player_id][tostring(object.id)]

                do_actor_interaction(
                    player_id,
                    bot_id,
                    object
                )
            end

            return
        end
    end

    -- Existing relay logic for non-exclusive NPCs
    if object.custom_properties and object.custom_properties["Interact Relay"] then
        local placeholder_id = object.custom_properties["Interact Relay"]
        if placeholder_to_botid[area_id] and placeholder_to_botid[area_id][placeholder_id] then
            local bot_id = placeholder_to_botid[area_id][placeholder_id]
            do_actor_interaction(player_id, bot_id, object)
        end
    end
end

-- Helper to remove an exclusive NPC (called from dialogue_types on win)
function eznpcs.remove_exclusive_npc(player_id, placeholder_id)
    if exclusive_npcs[player_id] then
        local bot_id = exclusive_npcs[player_id][tostring(placeholder_id)]
        if bot_id then
            Net.remove_bot(bot_id)
            npcs[bot_id] = nil
            exclusive_npcs[player_id][tostring(placeholder_id)] = nil
            printd("Removed exclusive NPC bot", bot_id, "for player", player_id)
        end
    end
end

-- Helper to remove a quest‑exclusive NPC (can be called when quest state changes)
function eznpcs.remove_quest_exclusive_npc(player_id, placeholder_id)
    if quest_exclusive_npcs[player_id] then
        local key = tostring(placeholder_id)
        local bot_id = quest_exclusive_npcs[player_id][key]

        if bot_id then
            remove_quest_exclusive_bot(bot_id, true)
            quest_exclusive_npcs[player_id][key] = nil

            if next(quest_exclusive_npcs[player_id]) == nil then
                quest_exclusive_npcs[player_id] = nil
            end

            printd(
                "Removed quest-exclusive NPC bot",
                bot_id,
                "for player",
                player_id
            )
        end
    end
end

-- Helper to get bot ID for placeholder (used in ezmemory)
function eznpcs.get_bot_id_for_placeholder(area_id, placeholder_id)
    if placeholder_to_botid[area_id] then
        return placeholder_to_botid[area_id][tostring(placeholder_id)]
    end
    return nil
end

-- Refresh only the quest-exclusive NPCs controlled by the changed Quest ID.
ezbus:on("quest_progress_changed", function(event)
    if event and event.player_id then
        update_quest_exclusive_for_player(
            event.player_id,
            event.quest_id,
            true
        )
    end
end)

return eznpcs
