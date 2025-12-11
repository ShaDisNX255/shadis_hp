-- scripts/ezlibs-custom/secret_path_switch.lua
-- One-time secret path reveal via an interactable object (debug version)

local secret_paths = {}

local function dbg(msg)
    print("[secret_path_switch] " .. msg)
end

local function err(msg)
    printerr("[secret_path_switch] " .. msg)
end

dbg("module loaded")

local function get_area_paths(area_id)
    local area_paths = secret_paths[area_id]
    if not area_paths then
        area_paths = {}
        secret_paths[area_id] = area_paths
        dbg("created area_paths table for area_id=" .. tostring(area_id))
    end
    return area_paths
end

local function reveal_path_for_switch(area_id, obj, player_id)
    local props = obj.custom_properties or {}
    dbg(string.format(
        "reveal_path_for_switch called for obj_id=%s area_id=%s player_id=%s",
        tostring(obj.id), tostring(area_id), tostring(player_id)
    ))

    -- Identify this path (so multiple switches on the same area don't fight)
    local path_id = props["Path ID"] or tostring(obj.id)
    dbg("path_id=" .. tostring(path_id))

    -- Use explicit Path Layer if present, otherwise default to the object's z
    local layer = tonumber(props["Path Layer"] or obj.z or 0)
    dbg("Path Layer prop=" .. tostring(props["Path Layer"]) .. " -> layer=" .. tostring(layer))

    local x1 = tonumber(props["Path X1"] or 0)
    local y1 = tonumber(props["Path Y1"] or 0)
    local x2 = tonumber(props["Path X2"] or x1)
    local y2 = tonumber(props["Path Y2"] or y1)

    -- Normalize so order in Tiled doesn’t matter
    local x_start = math.min(x1, x2)
    local x_end   = math.max(x1, x2)
    local y_start = math.min(y1, y2)
    local y_end   = math.max(y1, y2)

    dbg(string.format(
        "path rectangle raw: (%d,%d) to (%d,%d), normalized: (%d,%d) to (%d,%d)",
        x1, y1, x2, y2, x_start, y_start, x_end, y_end
    ))

    local sample_x = tonumber(props["Floor Sample X"] or 0)
    local sample_y = tonumber(props["Floor Sample Y"] or 0)

    dbg(string.format("floor sample at: (%d,%d)", sample_x, sample_y))

    if sample_x == 0 and sample_y == 0 then
        err("Missing Floor Sample X/Y on switch object '" .. (obj.name or "?") .. "' (obj_id=" .. tostring(obj.id) .. ")")
        Net.message_player(player_id, "Debug: Floor Sample X/Y missing.")
        return
    end

    local area_paths = get_area_paths(area_id)
    local state = area_paths[path_id] or { revealed = false }

    if state.revealed then
        dbg("path already revealed for path_id=" .. tostring(path_id))
        Net.message_player(player_id, "Nothing seems to happen...")
        return
    end

    -- Grab the floor tile we want to copy
    dbg(string.format("calling Net.get_tile(%s, %d, %d, %d)", tostring(area_id), sample_x, sample_y, layer))
    local floor_tile = Net.get_tile(area_id, sample_x, sample_y, layer)
    if not floor_tile then
        err(string.format(
            "Net.get_tile returned nil at (%d,%d,%d)",
            sample_x, sample_y, layer
        ))
        Net.message_player(player_id, "Debug: Sample tile is nil.")
        return
    end
    if floor_tile.gid == 0 then
        err(string.format(
            "Floor sample at (%d,%d,%d) has gid=0 (empty)",
            sample_x, sample_y, layer
        ))
        Net.message_player(player_id, "Debug: Sample tile is empty.")
        return
    end

    dbg(string.format("floor sample gid=%d (flipH=%s, flipV=%s, rot=%s)",
        floor_tile.gid,
        tostring(floor_tile.flipped_horizontally),
        tostring(floor_tile.flipped_vertically),
        tostring(floor_tile.rotated)
    ))

    -- Apply floor tile to the whole rectangle
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
    area_paths[path_id] = state
    dbg("path reveal completed for path_id=" .. tostring(path_id))

    -- Optional sound for everyone in the area
    if props["Sound Path"] and props["Sound Path"] ~= "" then
        dbg("playing sound: " .. tostring(props["Sound Path"]))
        Net.play_sound(area_id, props["Sound Path"])
    else
        dbg("no Sound Path property, skipping sound")
    end

    -- Optional *post* message for the activator
    local post_msg = props["Post Message"]
    if post_msg and post_msg ~= "" then
        dbg("sending post message to player: " .. post_msg)
        Net.message_player(player_id, post_msg)
    else
        dbg("no Post Message property, skipping post message")
    end
end

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

    -- Dump properties for debugging
    for k, v in pairs(props) do
        dbg(string.format("  prop[%s] = %s", tostring(k), tostring(v)))
    end

    local switch_flag = props["Secret Path Switch"]
    dbg("Secret Path Switch flag value=" .. tostring(switch_flag))

    if not switch_flag then
        dbg("Secret Path Switch flag not set or false, ignoring object")
        return
    end

    dbg("Secret Path Switch flag is set; continuing")

    ----------------------------------------------------------------
    -- (Optional) owner/oncehub logic you already had goes here.
    -- We leave whatever you had above this comment as-is.
    ----------------------------------------------------------------

    ----------------------------------------------------------------
    -- NEW: Optional "Ask Question" flavor
    ----------------------------------------------------------------
    local ask_prop = props["Ask Question"]
    local ask_question =
        (ask_prop == true) or
        (ask_prop == "true") or
        (ask_prop == "True") or
        (ask_prop == 1) or
        (ask_prop == "1")

    -- If Ask Question is not enabled, behave exactly like before
    if not ask_question then
        dbg("Ask Question not enabled; revealing path immediately")
        reveal_path_for_switch(area_id, obj, player_id)
        return
    end

    dbg("Ask Question enabled; starting async question flow")

    -- Read flavor strings
    local pre_msg     = props["Message"] or "You find a secret switch..."
    local question    = props["Question"] or "Do you want to press it?"
    local yes_text    = props["Yes Text"] or "Who wouldn't?"
    local no_text     = props["No Text"]
    local post_msg    = props["Post Message"]

    -- Run the widget flow asynchronously so we don't block the server
    return Async.promisify(coroutine.create(function()
        -- 1) Show the initial flavor line
        if pre_msg and pre_msg ~= "" then
            dbg("pre_msg: " .. pre_msg)
            Async.await(Async.message_player(player_id, pre_msg))
        end

        -- 2) Ask the Yes/No question
        dbg("question: " .. question)
        local answer = Async.await(Async.question_player(player_id, question))
        dbg("answer from question_player: " .. tostring(answer))

        -- Assumption: question_player returns 1 for Yes, 0 or nil for No/B
        if answer ~= 1 then
            dbg("player chose No or cancelled")
            if no_text and no_text ~= "" then
                dbg("no_text: " .. no_text)
                Async.await(Async.message_player(player_id, no_text))
            end
            return
        end

        -- 3) YES branch: "Who wouldn't?" then reveal path
        if yes_text and yes_text ~= "" then
            dbg("yes_text: " .. yes_text)
            Async.await(Async.message_player(player_id, yes_text))
        end

        -- We don't want the reveal helper to reuse the Message string
        -- as a post-reveal message, so temporarily blank it out.
        local orig_message = props["Message"]
        props["Message"] = nil

        dbg("calling reveal_path_for_switch after YES")
        reveal_path_for_switch(area_id, obj, player_id)

        -- Restore local copy of Message (in case anything else reads props)
        props["Message"] = orig_message

    end))
end)
