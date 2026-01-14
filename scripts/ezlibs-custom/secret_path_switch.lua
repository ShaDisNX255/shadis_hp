-- scripts/ezlibs-custom/secret_path_switch.lua
-- Secret path switch (TOGGLE + optional auto-hide) [Option A: hide = clear to empty gid=0]

local secret_paths = {} -- [area_id][path_id] = state

local function dbg(msg)
    print("[secret_path_switch] " .. msg)
end

local function err(msg)
    if printerr then
        printerr("[secret_path_switch] " .. msg)
    else
        print("[secret_path_switch][ERR] " .. msg)
    end
end

dbg("module loaded")

local function to_bool(v)
    return (v == true) or (v == 1) or (v == "1") or (v == "true") or (v == "True") or (v == "TRUE")
end

local function to_num(v, default)
    local n = tonumber(v)
    if n == nil then return default end
    return n
end

local function get_area_paths(area_id)
    local area_paths = secret_paths[area_id]
    if not area_paths then
        area_paths = {}
        secret_paths[area_id] = area_paths
        dbg("created area_paths table for area_id=" .. tostring(area_id))
    end
    return area_paths
end

local function get_or_create_state(area_id, path_id)
    local area_paths = get_area_paths(area_id)
    local state = area_paths[path_id]
    if not state then
        state = {
            revealed = false,
            layer = 0,
            x_start = 0, x_end = 0,
            y_start = 0, y_end = 0,
            auto_hide_remaining = nil, -- seconds remaining; counted down in tick
        }
        area_paths[path_id] = state
    end
    return state
end

local function compute_path_rect(obj, props)
    local path_id = props["Path ID"] or tostring(obj.id)

    -- Use explicit Path Layer if present, otherwise default to the object's z
    local layer = to_num(props["Path Layer"] or obj.z or 0, 0)

    local x1 = to_num(props["Path X1"], 0)
    local y1 = to_num(props["Path Y1"], 0)
    local x2 = to_num(props["Path X2"], x1)
    local y2 = to_num(props["Path Y2"], y1)

    -- Normalize so order in Tiled doesn’t matter
    local x_start = math.min(x1, x2)
    local x_end   = math.max(x1, x2)
    local y_start = math.min(y1, y2)
    local y_end   = math.max(y1, y2)

    return path_id, layer, x_start, x_end, y_start, y_end
end

local function read_auto_hide_seconds(props)
    -- Add ONE of these properties to your switch object if you want auto-hide:
    --   Auto Hide Seconds = 3600
    --   Auto Hide Minutes = 60
    --   Auto Hide Hours   = 1
    local secs = to_num(props["Auto Hide Seconds"], 0)
    if secs and secs > 0 then return secs end

    local mins = to_num(props["Auto Hide Minutes"], 0)
    if mins and mins > 0 then return mins * 60 end

    local hours = to_num(props["Auto Hide Hours"], 0)
    if hours and hours > 0 then return hours * 3600 end

    return 0
end

local function reveal_path(area_id, obj, player_id)
    local props = obj.custom_properties or {}

    dbg(string.format(
        "reveal_path called for obj_id=%s area_id=%s player_id=%s",
        tostring(obj.id), tostring(area_id), tostring(player_id)
    ))

    local path_id, layer, x_start, x_end, y_start, y_end = compute_path_rect(obj, props)
    dbg("path_id=" .. tostring(path_id) .. " layer=" .. tostring(layer))

    local state = get_or_create_state(area_id, path_id)
    if state.revealed then
        dbg("path already revealed for path_id=" .. tostring(path_id))
        Net.message_player(player_id, "Nothing seems to happen...")
        return false
    end

    state.layer, state.x_start, state.x_end, state.y_start, state.y_end = layer, x_start, x_end, y_start, y_end

    local sample_x = to_num(props["Floor Sample X"], 0)
    local sample_y = to_num(props["Floor Sample Y"], 0)
    dbg(string.format("floor sample at: (%d,%d)", sample_x, sample_y))

    if sample_x == 0 and sample_y == 0 then
        err("Missing Floor Sample X/Y on switch object '" .. (obj.name or "?") .. "' (obj_id=" .. tostring(obj.id) .. ")")
        Net.message_player(player_id, "Debug: Floor Sample X/Y missing.")
        return false
    end

    local floor_tile = Net.get_tile(area_id, sample_x, sample_y, layer)
    if not floor_tile then
        err(string.format("Net.get_tile returned nil at (%d,%d,%d)", sample_x, sample_y, layer))
        Net.message_player(player_id, "Debug: Sample tile is nil.")
        return false
    end
    if floor_tile.gid == 0 then
        err(string.format("Floor sample at (%d,%d,%d) has gid=0 (empty)", sample_x, sample_y, layer))
        Net.message_player(player_id, "Debug: Sample tile is empty.")
        return false
    end

    dbg(string.format("floor sample gid=%d (flipH=%s, flipV=%s, rot=%s)",
        floor_tile.gid,
        tostring(floor_tile.flipped_horizontally),
        tostring(floor_tile.flipped_vertically),
        tostring(floor_tile.rotated)
    ))

    for tx = x_start, x_end do
        for ty = y_start, y_end do
            dbg(string.format("setting tile (%d,%d,%d) to gid=%d", tx, ty, layer, floor_tile.gid))
            Net.set_tile(
                area_id,
                tx,
                ty,
                layer,
                floor_tile.gid,
                floor_tile.flipped_horizontally,
                floor_tile.flipped_vertically,
                floor_tile.rotated
            )
        end
    end

    state.revealed = true

    -- Optional sound for everyone in the area
    if props["Sound Path"] and props["Sound Path"] ~= "" then
        dbg("playing sound: " .. tostring(props["Sound Path"]))
        Net.play_sound(area_id, props["Sound Path"])
    end

    -- Optional post message for activator
    local post_msg = props["Post Message"]
    if post_msg and post_msg ~= "" then
        dbg("sending post message to player: " .. post_msg)
        Net.message_player(player_id, post_msg)
    end

    -- Optional auto-hide
    local auto_hide_secs = read_auto_hide_seconds(props)
    if auto_hide_secs > 0 then
        state.auto_hide_remaining = auto_hide_secs
        dbg("auto-hide armed: " .. tostring(auto_hide_secs) .. "s")
    else
        state.auto_hide_remaining = nil
        dbg("auto-hide not armed (no Auto Hide property set)")
    end

    dbg("path reveal completed for path_id=" .. tostring(path_id))
    return true
end

local function hide_path(area_id, obj, player_id, silent)
    local props = obj.custom_properties or {}

    dbg(string.format(
        "hide_path called for obj_id=%s area_id=%s player_id=%s",
        tostring(obj.id), tostring(area_id), tostring(player_id)
    ))

    local path_id, layer, x_start, x_end, y_start, y_end = compute_path_rect(obj, props)
    dbg("path_id=" .. tostring(path_id) .. " layer=" .. tostring(layer))

    local state = get_or_create_state(area_id, path_id)
    if not state.revealed then
        dbg("path already hidden for path_id=" .. tostring(path_id))
        if player_id and not silent then
            Net.message_player(player_id, "Nothing seems to happen...")
        end
        return false
    end

    -- Option A: "no tiles before revealed" => hide by clearing to empty gid=0
    for tx = x_start, x_end do
        for ty = y_start, y_end do
            dbg(string.format("clearing tile (%d,%d,%d) to gid=0", tx, ty, layer))
            Net.set_tile(area_id, tx, ty, layer, 0, false, false, false)
        end
    end

    state.revealed = false
    state.auto_hide_remaining = nil
    state.layer, state.x_start, state.x_end, state.y_start, state.y_end = layer, x_start, x_end, y_start, y_end

    if not silent and player_id then
        local hide_msg = props["Hide Message"] or "You hear a click... the way closes."
        if hide_msg ~= "" then
            Net.message_player(player_id, hide_msg)
        end
    end

    local hide_sound = props["Hide Sound Path"]
    if hide_sound and hide_sound ~= "" then
        Net.play_sound(area_id, hide_sound)
    end

    dbg("path hide completed for path_id=" .. tostring(path_id))
    return true
end

-- Auto-hide countdown (delta_time in seconds)
Net:on("tick", function(event)
    local dt = to_num(event.delta_time, 0)
    if dt <= 0 then return end

    for area_id, area_paths in pairs(secret_paths) do
        for _, state in pairs(area_paths) do
            if state.revealed and state.auto_hide_remaining then
                state.auto_hide_remaining = state.auto_hide_remaining - dt
                if state.auto_hide_remaining <= 0 then
                    dbg("auto-hide firing for area_id=" .. tostring(area_id))

                    for tx = state.x_start, state.x_end do
                        for ty = state.y_start, state.y_end do
                            Net.set_tile(area_id, tx, ty, state.layer, 0, false, false, false)
                        end
                    end

                    state.revealed = false
                    state.auto_hide_remaining = nil
                end
            end
        end
    end
end)

Net:on("object_interaction", function(event)
    dbg(string.format(
        "object_interaction event: player_id=%s object_id=%d button=%d",
        tostring(event.player_id),
        tonumber(event.object_id or -1),
        tonumber(event.button or -1)
    ))

    -- Accept both 0 and 1 as confirm/talk buttons
    if event.button ~= 0 and event.button ~= 1 then
        dbg("button is not 0 or 1 (confirm), ignoring")
        return
    end

    local player_id = event.player_id
    if not Net.is_player(player_id) then
        dbg("player is no longer valid, ignoring")
        return
    end

    local area_id = Net.get_player_area(player_id)
    dbg("player is in area_id=" .. tostring(area_id))
    if not area_id then
        dbg("no area_id for player, aborting")
        return
    end

    local obj = Net.get_object_by_id(area_id, event.object_id)
    if not obj then
        dbg("object not found by id=" .. tostring(event.object_id))
        return
    end

    dbg("object name=" .. tostring(obj.name) .. " id=" .. tostring(obj.id))

    local props = obj.custom_properties or {}

    local switch_flag = props["Secret Path Switch"]
    dbg("Secret Path Switch flag value=" .. tostring(switch_flag))
    if not switch_flag then
        dbg("Secret Path Switch flag not set or false, ignoring object")
        return
    end

    local path_id = props["Path ID"] or tostring(obj.id)
    local state = get_or_create_state(area_id, path_id)

    -- TOGGLE: if revealed, hide immediately (no question flow)
    if state.revealed then
        dbg("toggle: currently revealed -> hiding")
        hide_path(area_id, obj, player_id, false)
        return
    end

    ----------------------------------------------------------------
    -- (Optional) owner/oncehub logic you already had goes here.
    -- We leave whatever you had above this comment as-is.
    ----------------------------------------------------------------

    -- Optional "Ask Question" flavor (for revealing only)
    local ask_question = to_bool(props["Ask Question"])
    if not ask_question then
        dbg("Ask Question not enabled; revealing path immediately")
        reveal_path(area_id, obj, player_id)
        return
    end

    dbg("Ask Question enabled; starting async question flow")

    local pre_msg  = props["Message"] or "You find a secret switch..."
    local question = props["Question"] or "Do you want to press it?"
    local yes_text = props["Yes Text"] or "Who wouldn't?"
    local no_text  = props["No Text"]

    return Async.promisify(coroutine.create(function()
        if pre_msg and pre_msg ~= "" then
            dbg("pre_msg: " .. pre_msg)
            Async.await(Async.message_player(player_id, pre_msg))
        end

        dbg("question: " .. question)
        local answer = Async.await(Async.question_player(player_id, question))
        dbg("answer from question_player: " .. tostring(answer))

        if answer ~= 1 then
            dbg("player chose No or cancelled")
            if no_text and no_text ~= "" then
                dbg("no_text: " .. no_text)
                Async.await(Async.message_player(player_id, no_text))
            end
            return
        end

        if yes_text and yes_text ~= "" then
            dbg("yes_text: " .. yes_text)
            Async.await(Async.message_player(player_id, yes_text))
        end

        dbg("calling reveal_path after YES")
        reveal_path(area_id, obj, player_id)
    end))
end)
