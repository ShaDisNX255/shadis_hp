local eznpcs_events = {}
local eznpcs = require('scripts/ezlibs-scripts/eznpcs/eznpcs')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local ezmystery = require('scripts/ezlibs-scripts/ezmystery')
local ezfarms = require('scripts/ezlibs-scripts/ezfarms')
local ezweather = require('scripts/ezlibs-scripts/ezweather')
local ezwarps = require('scripts/ezlibs-scripts/ezwarps/main')
local ezencounters = require('scripts/ezlibs-scripts/ezencounters/main')
local helpers = require('scripts/ezlibs-scripts/helpers')
local custom = require('scripts/ezlibs-custom/custom')
local onceitem = require('scripts/events/eznpcs_onceitem')   -- loads the onceitem rental type
local teams = require('scripts/teams/teams')
local raids    = require('scripts/raids/raids')
local cosmetics = require('scripts/ezlibs-custom/cosmetics')
local ezmenus   = require('scripts/ezlibs-scripts/ezmenus')
local duels  = require('scripts/ezlibs-custom/duels')
local card_sleeves = require('scripts/ezlibs-custom/card_sleeves')
local ezquests = require('scripts/ezlibs-scripts/ezquests')
local whitelist = require('scripts/ezlibs-custom/whitelist')
local ezrushroads = require('scripts/ezlibs-scripts/ezrushroads')

local Pets = (function()
  local ok, M = pcall(require, 'scripts/ezlibs-custom/pets')
  if ok and M then return M end
  return nil
end)()

local COSMETIC_SHOP_COLOR = { r = 245, g = 210, b = 70 } -- same yellow as decorshop

local JUKEBOX_TRACKS_MEM_KEY = "jukebox_tracks_v1"
local JUKEBOX_DIR_DISK       = "./assets/jukebox"
local JUKEBOX_SONG_PREFIX    = "/server/assets/jukebox/"

local function _list_jukebox_songs()
  local files = {}
  local is_windows = package.config:sub(1,1) == "\\"
  local cmd = is_windows
    and ('dir /b /a-d "'..JUKEBOX_DIR_DISK..'"')
    or  ('ls -1 "'..JUKEBOX_DIR_DISK..'"')

  local p = io.popen(cmd)
  if not p then return files end
  for f in p:lines() do
    if type(f) == "string" and f:lower():sub(-4) == ".ogg" then
      table.insert(files, f)
    end
  end
  p:close()

  table.sort(files, function(a,b) return a:lower() < b:lower() end)
  return files
end

local function _songshop_is_owned(secret, file)
  local pmem = ezmemory.get_player_memory(secret) or {}
  pmem[JUKEBOX_TRACKS_MEM_KEY] = pmem[JUKEBOX_TRACKS_MEM_KEY] or {}
  local v = pmem[JUKEBOX_TRACKS_MEM_KEY][file]
  return v == true or (tonumber(v or 0) or 0) > 0
end

local function _songshop_set_owned(secret, file)
  local pmem = ezmemory.get_player_memory(secret) or {}
  pmem[JUKEBOX_TRACKS_MEM_KEY] = pmem[JUKEBOX_TRACKS_MEM_KEY] or {}
  pmem[JUKEBOX_TRACKS_MEM_KEY][file] = 1
  if ezmemory.save_player_memory then
    ezmemory.save_player_memory(secret)
  elseif ezmemory.set_player_memory then
    ezmemory.set_player_memory(secret, pmem)
  end
end

local sfx = {
    hurt = '/server/assets/ezlibs-assets/sfx/hurt.ogg',
    item_get = '/server/assets/ezlibs-assets/sfx/item_get.ogg',
    recover = '/server/assets/ezlibs-assets/sfx/recover.ogg',
    gibberish = '/server/assets/ezlibs-assets/sfx/gibberish.ogg',
    card_error = '/server/assets/ezlibs-assets/ezfarms/card_error.ogg'
}

local JobBBS = (function()
  local ok, M = pcall(require, 'scripts/jobbbs/JobBBS')
  if ok and M then return M end
  ok, M = pcall(require, 'scripts/jobbbs/jobbbs') -- fallback if name changes
  return ok and M or nil
end)()

----------------------------------------------------------------
-- Dialogue-driven secret paths (persistent)
-- Used by the "SecretPath" dialogue event
----------------------------------------------------------------

local SECRET_PATHS_MEM_KEY = "__secret_paths_dialogue"
local rehydrated_secret_areas = {}

local function get_secret_paths_bucket(area_id)
    if not ezmemory or not ezmemory.get_area_memory then
        return nil, nil
    end
    local mem = ezmemory.get_area_memory(area_id) or ezmemory.get_area_memory(area_id)
    if not mem then return nil, nil end

    mem[SECRET_PATHS_MEM_KEY] = mem[SECRET_PATHS_MEM_KEY] or {}
    return mem[SECRET_PATHS_MEM_KEY], mem
end

local function rehydrate_secret_paths_for_area(area_id)
    if not area_id or rehydrated_secret_areas[area_id] then
        return
    end

    local bucket = get_secret_paths_bucket(area_id)
    if not bucket then
      print("[SecretPath] no bucket for area:", area_id)
	  return
    end

    local total = 0

    for path_id, rec in pairs(bucket) do
        print("[SecretPath] found record:", path_id, "revealed=", rec and rec.revealed)
        if rec and rec.revealed and rec.segments then
            local layer = rec.layer or 0
            for _, seg in ipairs(rec.segments) do
                local gid = seg.gid
                if gid and gid ~= 0 then
                    for tx = seg.x_start, seg.x_end do
                        for ty = seg.y_start, seg.y_end do
                            Net.set_tile(
                                area_id,
                                tx,
                                ty,
                                layer,
                                gid,
                                seg.fh,
                                seg.fv,
                                seg.rot
                            )
                            total = total + 1
                        end
                    end
                end
            end
        end
    end

    if total > 0 then
        print(string.format(
            "[SecretPath] Rehydrated %d tiles in area '%s'",
            total, tostring(area_id)
        ))
    end

    rehydrated_secret_areas[area_id] = true
end

local function reveal_dialogue_path(area_id, player_id, dialogue)
    local props = dialogue.custom_properties or {}

    -- Identify this path (so multiple NPCs/quests don't fight)
    local raw_id = props["Path ID"] or props["Path Id"] or props["path id"]
    local path_id = tostring(raw_id or (dialogue.name or dialogue.id or "default_path"))

    local bucket = get_secret_paths_bucket(area_id)
    if not bucket then
        Net.message_player(player_id, "Debug: Area memory not available for secret path.")
        return
    end

    -- Already revealed in a previous run? Just show repeat message.
    local rec = bucket[path_id]
    if rec and rec.revealed then
        local repeat_msg = props["Repeat Message"]
        if repeat_msg and repeat_msg ~= "" then
            Net.message_player(player_id, repeat_msg)
        end
        return
    end

    local layer = tonumber(props["Path Layer"] or 0)

    local segments = {}
    local segments_mem = {}
    local had_error = false

    local function add_segment(label, path_prefix, sample_prefix)
        if had_error then return end

        -- Example: path_prefix="Path"  -> "Path X1", "Path Y1", ...
        --          path_prefix="Path 2" -> "Path 2 X1", etc.
        local x1_key = path_prefix .. " X1"
        local y1_key = path_prefix .. " Y1"
        local x2_key = path_prefix .. " X2"
        local y2_key = path_prefix .. " Y2"

        local sx_key = sample_prefix .. " X"
        local sy_key = sample_prefix .. " Y"

        local x1_prop = props[x1_key]
        local y1_prop = props[y1_key]

        -- If X1/Y1 not defined, this segment doesn't exist; that's fine.
        if x1_prop == nil or y1_prop == nil then
            return
        end

        local x1 = tonumber(x1_prop) or 0
        local y1 = tonumber(y1_prop) or 0
        local x2 = tonumber(props[x2_key] or x1)
        local y2 = tonumber(props[y2_key] or y1)

        local sx_prop = props[sx_key]
        local sy_prop = props[sy_key]

        if sx_prop == nil or sy_prop == nil then
            Net.message_player(player_id, "Debug: Missing floor sample for " .. label .. ".")
            had_error = true
            return
        end

        local sx = tonumber(sx_prop) or 0
        local sy = tonumber(sy_prop) or 0

        local floor_tile = Net.get_tile(area_id, sx, sy, layer)
        if not floor_tile then
            Net.message_player(player_id, "Debug: Sample tile is nil for " .. label .. ".")
            had_error = true
            return
        end
        if floor_tile.gid == 0 then
            Net.message_player(player_id, "Debug: Sample tile is empty for " .. label .. ".")
            had_error = true
            return
        end

        local x_start = math.min(x1, x2)
        local x_end   = math.max(x1, x2)
        local y_start = math.min(y1, y2)
        local y_end   = math.max(y1, y2)

        -- Runtime segment (uses full tile table)
        table.insert(segments, {
            x_start = x_start,
            x_end   = x_end,
            y_start = y_start,
            y_end   = y_end,
            tile    = floor_tile,
        })

        -- Persistent segment (only primitives so ezmemory can serialize)
        table.insert(segments_mem, {
            x_start = x_start,
            x_end   = x_end,
            y_start = y_start,
            y_end   = y_end,
            gid     = floor_tile.gid,
            fh      = floor_tile.flipped_horizontally,
            fv      = floor_tile.flipped_vertically,
            rot     = floor_tile.rotated,
        })
    end

    -- Segment 1 uses the same property names as secret_path_switch:
    -- Path X1/Y1/X2/Y2 + Floor Sample X/Y
    add_segment("segment 1", "Path", "Floor Sample")

    -- Extra segments: Path 2 X1/Y1/X2/Y2 + Floor Sample 2 X/Y, Path 3..., etc.
    for i = 2, 8 do
        add_segment("segment " .. i, "Path " .. i, "Floor Sample " .. i)
    end

    if had_error then
        return
    end

    if #segments == 0 then
        Net.message_player(player_id, "Debug: No path segments defined on this dialogue.")
        return
    end

    -- Paint all segments now
    for _, seg in ipairs(segments) do
        local t = seg.tile
        for tx = seg.x_start, seg.x_end do
            for ty = seg.y_start, seg.y_end do
                Net.set_tile(
                    area_id,
                    tx,
                    ty,
                    layer,
                    t.gid,
                    t.flipped_horizontally,
                    t.flipped_vertically,
                    t.rotated
                )
            end
        end
    end

    -- Persist config to area memory so we can repaint after reboot
    bucket[path_id] = {
        revealed = true,
        layer    = layer,
        segments = segments_mem,
    }
    ezmemory.save_area_memory(area_id)

    -- Optional sound (everyone in area)
    local sound_path = props["Sound Path"]
    if sound_path and sound_path ~= "" then
        Net.play_sound(area_id, sound_path)
    end

    -- Optional post message (only to triggering player)
    local post_msg = props["Post Message"]
    if post_msg and post_msg ~= "" then
        Net.message_player(player_id, post_msg)
    end
end

local event1 = {
    name = "Italian Gibberish",
    action = function(npc, player_id, dialogue, relay_object)
        return async(function()
            local player_mugshot = Net.get_player_mugshot(player_id)
            Net.play_sound_for_player(player_id, sfx.gibberish)
            return dialogue.custom_properties["Next 1"]
        end)
    end
}
eznpcs.add_event(event1)

local function _encounter_result_flags(stats)
    local reason = tonumber(stats and stats.reason or 0) or 0
    local hp = tonumber(stats and (stats.health or stats.player_hp or stats.hp) or 0) or 0

    local ran, won, lost = false, false, false

    if reason == 1 then        -- battle won
        won = true
    elseif reason == 2 then    -- battle lost
        lost = true
    elseif reason == 3 then    -- ran with L
        ran = true
    elseif reason == 4 then    -- ESC / dev escape
        ran = true
    else
        -- backwards compatibility with older builds
        ran = stats and (stats.ran or stats.fled or stats.escape) or false
        if not ran then
            if hp > 0 then
                won = true
            else
                lost = true
            end
        end
    end

    return {
        reason = reason,
        hp = hp,
        ran = ran,
        won = won,
        lost = lost,
    }
end

local function _normalize_busting_score(score)
    if type(score) == "string" and string.upper(score) == "S" then
        return 11
    end
    return math.floor(tonumber(score) or 0)
end

local boss2 = {
    name="boss2",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/events.zip",
    pet_exp=0,
    enemies={
        {name="HeelNavi",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,0,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local event2 = {
    name="Heel Navi1",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, boss2))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(event2)

local event3 = {
    name = "Gambler",
    action = function(npc, player_id, dialogue)
        return async(function()
            if ezmemory.spend_player_money(player_id, 5000) then
                return dialogue.custom_properties["Got moneyz"]
            else
                return dialogue.custom_properties["No moneyz"]
            end
        end)
    end
}
eznpcs.add_event(event3)

local Win_Gamble = {
    name = "Win_Gamble",
    action = function(npc, player_id, dialogue)
        return async(function()
            local zenny_amount = tonumber(dialogue.custom_properties["Amount"])
            ezmemory.spend_player_money(player_id, -zenny_amount)
            Net.play_sound_for_player(player_id, sfx.item_get)
            await(Async.message_player(player_id, "Got " .. zenny_amount .. "$!"))
            return dialogue.custom_properties["Next 1"]
        end)
    end
}
eznpcs.add_event(Win_Gamble)

local Win_Reward = {
    name = "Win_Reward",
    action = function(npc, player_id, dialogue)
        return async(function()
            local props = dialogue.custom_properties or {}

            local amount = math.floor(tonumber(props["Amount"] or 0) or 0)
            if amount <= 0 then
                await(Async.message_player(player_id, "No reward amount configured."))
                return props["Next 2"] or props["Next 1"]
            end

            local reward_type = tostring(
                props["Reward Type"]
                or props["Type"]
                or props["Currency"]
                or "money"
            ):lower()

            local ok = true
            local message = nil

            if reward_type == "bugfrag"
                or reward_type == "bugfrags"
                or reward_type == "frag"
                or reward_type == "frags"
                or reward_type == "bf"
            then
                if ezmemory.add_player_fragments then
                    local ok_call, result = pcall(ezmemory.add_player_fragments, player_id, amount)
                    ok = ok_call and result ~= false
                elseif ezmemory.spend_player_fragments then
                    local ok_call, result = pcall(ezmemory.spend_player_fragments, player_id, -amount)
                    ok = ok_call and result ~= false
                else
                    ok = false
                end

                message = "Got " .. tostring(amount) .. " BugFrag" .. (amount == 1 and "!" or "s!")

            elseif reward_type == "rushfood"
                or reward_type == "rush_food"
                or reward_type == "rush food"
                or reward_type == "rush"
                or reward_type == "food"
            then
                if ezrushroads and ezrushroads.add_food then
                    local ok_call, new_total = pcall(ezrushroads.add_food, player_id, amount)
                    ok = ok_call and new_total ~= nil
                else
                    ok = false
                end

                message = "Got " .. tostring(amount) .. " Rush Food!"

            else
                local ok_call, result = pcall(ezmemory.spend_player_money, player_id, -amount)
                ok = ok_call and result ~= false
                message = "Got " .. tostring(amount) .. "$!"
            end

            if not ok then
                await(Async.message_player(player_id, "Reward could not be given."))
                return props["Next 2"] or props["Next 1"]
            end

            local direction = nil
            if Net.get_player_direction then
                local ok_dir, dir = pcall(Net.get_player_direction, player_id)
                if ok_dir then
                    direction = dir
                end
            end

            if ezmemory.play_anim_get then
                pcall(ezmemory.play_anim_get, player_id)
            end

            Net.play_sound_for_player(player_id, sfx.item_get)
            await(Async.message_player(player_id, message))

            if direction and ezmemory.set_direction_anim then
                pcall(ezmemory.set_direction_anim, player_id, direction)
            end

            return props["Next 1"]
        end)
    end
}
eznpcs.add_event(Win_Reward)

local boss4 = {
    name="boss4",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/events.zip",
    pet_exp=0,
    enemies={
        {name="ProtomanPoN",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,0,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    music={
        path="exe3-boss.ogg",
        loop_start = 7535,
        loop_end = 39259,
    },
}

local event4 = {
    name="Proto Battle",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, boss4))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(event4)

local function reward_roll1_on_win(player_id, encounter_info, stats)
    local flags = _encounter_result_flags(stats)
    if not flags.won then
        return
    end

    local ok, reason = whitelist.unlock_card(player_id, "roll1", "*")
    if ok then
        print("[Roll Battle] awarded Roll1 to", tostring(player_id))
    elseif reason == "already_unlocked" then
        print("[Roll Battle] player already owns Roll1:", tostring(player_id))
    else
        print("[Roll Battle] failed to award Roll1:", tostring(player_id), tostring(reason))
    end
end

local boss5 = {
    name="boss5",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/events.zip",
    pet_exp=0,
    results_callback = reward_roll1_on_win,
    enemies={
        {name="Roll",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,0,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    music={
        path="exe3-boss.ogg",
        loop_start = 7535,
        loop_end = 39259,
    },
}

local event5 = {
    name="Roll Battle",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, boss5))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(event5)

local boss6 = {
    name="boss6",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/events.zip",
    pet_exp=0,
    enemies={
        {name="GutsManPoN",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,0,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    music={
        path="exe3-boss.ogg",
        loop_start = 7535,
        loop_end = 39259,
    },
}

local event6 = {
    name="Guts Battle",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, boss6))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(event6)

local function reward_gutsman_chip_on_win(player_id, encounter_info, stats)
    local flags = _encounter_result_flags(stats)
    if not flags.won then
        return
    end

    local score = _normalize_busting_score(stats and stats.score)
    if score < 6 then
        print("[Guts3 Battle] no chip reward; score too low:", tostring(player_id), tostring(score))
        return
    end

    local ok, reason = whitelist.unlock_card(player_id, "gutsman1", "*")
    if ok then
        print("[Guts3 Battle] awarded GutsMan chip to", tostring(player_id), "score=" .. tostring(score))
    elseif reason == "already_unlocked" then
        print("[Guts3 Battle] player already owns GutsMan chip:", tostring(player_id), "score=" .. tostring(score))
    else
        print("[Guts3 Battle] failed to award GutsMan chip:", tostring(player_id), tostring(reason), "score=" .. tostring(score))
    end
end

local boss7 = {
    name="boss7",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/events.zip",
    pet_exp=0,
    results_callback = reward_gutsman_chip_on_win,
    enemies={
        {name="GutsManEXE3",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,0,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    music={
        path="exe3-boss.ogg",
        loop_start = 7535,
        loop_end = 39259,
    },
}

local event7 = {
    name="Guts3 Battle",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, boss7))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(event7)

local boss8 = {
    name="boss8",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/events.zip",
    pet_exp=0,
    enemies={
        {name="GregarBeast",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,0,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    music={
        path="exe3-boss.ogg",
        loop_start = 7535,
        loop_end = 39259,
    },
}

local event8 = {
    name="GregarB Battle",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, boss8))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(event8)

local event_tech1_1 = {
    name="Tech1_1 Battle",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(
              ezencounters.begin_encounter_by_name(
                  player_id,
                  "tech1_1",
                  relay_object
              )
          )
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(event_tech1_1)

-- Weighted pick helper (number weights)
local function pick_weighted(entries)
    local total = 0
    for _, e in ipairs(entries or {}) do total = total + (tonumber(e.weight) or 0) end
    if total <= 0 then return nil end
    local roll, acc = math.random() * total, 0
    for _, e in ipairs(entries) do
        acc = acc + (tonumber(e.weight) or 0)
        if roll <= acc then return e end
    end
    return entries[#entries]
end

-- Case-insensitive props helpers
local function build_ci_props(dialogue)
    local ci = {}
    for k, v in pairs(dialogue.custom_properties or {}) do
        ci[string.lower(tostring(k))] = v
    end
    return ci
end
local function get_ci(ci, key) return ci[string.lower(key)] end
local function extract_seq_ci(ci, prefix_lc)
    local out, i = {}, 1
    while true do
        local v = ci[prefix_lc .. i]
        if v == nil then break end
        table.insert(out, v)
        i = i + 1
    end
    return out
end

-- Parse single pack + rarity groups
local function read_single_pack(dialogue)
    local ci = build_ci_props(dialogue)

    local name  = get_ci(ci, "pack name")
    if not name then return nil end
    local price = tonumber(get_ci(ci, "pack price")) or 0
    local rolls = tonumber(get_ci(ci, "pack rolls")) or 1
    local desc  = get_ci(ci, "pack description") or ("Contains "..rolls.." random card(s).")

    local pools = {
      { label = "Common",     items = extract_seq_ci(ci, "common "),     rate = tonumber(get_ci(ci, "common rate"))     },
      { label = "Rare",       items = extract_seq_ci(ci, "rare "),       rate = tonumber(get_ci(ci, "rare rate"))       },
      { label = "Super Rare", items = extract_seq_ci(ci, "super rare "), rate = tonumber(get_ci(ci, "super rare rate")) },
      { label = "Ultra Rare", items = extract_seq_ci(ci, "ultra rare "), rate = tonumber(get_ci(ci, "ultra rare rate")) },
      { label = "Gold Rare",  items = extract_seq_ci(ci, "gold rare "),  rate = tonumber(get_ci(ci, "gold rare rate"))  },
      { label = "Ghost Rare", items = extract_seq_ci(ci, "ghost rare "), rate = tonumber(get_ci(ci, "ghost rare rate")) },
    }

    -- Default rates if none set
    local any_rate = false
    for _, p in ipairs(pools) do if (p.rate or 0) > 0 then any_rate = true break end end
    if not any_rate then
      local has_gdr = pools[5].items and #pools[5].items > 0
      local has_gr  = pools[6].items and #pools[6].items > 0
      if has_gdr or has_gr then
        pools[1].rate, pools[2].rate, pools[3].rate, pools[4].rate = 753, 207, 30, 9
        pools[5].rate = has_gdr and 1 or 0
        pools[6].rate = has_gr  and 1 or 0
      else
        pools[1].rate, pools[2].rate, pools[3].rate, pools[4].rate = 70, 25, 4, 1
      end
    end

    -- Keep only pools that have items and a positive rate
    local groups = {}
    for _, p in ipairs(pools) do
        if p.items and #p.items > 0 and (p.rate or 0) > 0 then
            table.insert(groups, { label = p.label, items = p.items, weight = p.rate })
        end
    end

    return { name = name, price = price, rolls = rolls, description = desc, groups = groups }
end

-- Grant items for one pack (spending handled elsewhere)
local function grant_one_pack(player_id, area_id, pack, names_acc)
    local rolls = math.max(1, math.floor(tonumber(pack and pack.rolls) or 1))

    for _ = 1, rolls do
        local group = pick_weighted(pack.groups or {})
        if not group then
            break
        end

        local items = group.items
        if not items or #items == 0 then
            break
        end

        local idx = math.random(1, #items)
        local obj_id = items[idx]
        local info = helpers.read_item_information(area_id, obj_id)

        if info then
            if info.type == "keyitem" or info.type == "item" then
                local is_key = (info.type == "keyitem")
                ezmemory.create_or_update_item(info.name, info.description or "???", is_key)
                ezmemory.give_player_item(player_id, info.name, info.amount or 1)
                table.insert(names_acc, info.name)

            elseif info.type == "money" then
                ezmemory.spend_player_money(player_id, -(info.amount or 0))
                table.insert(names_acc, tostring(info.amount or 0) .. "$")

            elseif info.type == "fragments" then
                ezmemory.add_player_fragments(player_id, info.amount or 0)
                table.insert(names_acc, tostring(info.amount or 0) .. " Bug Fragments")

            elseif info.type == "tokens" then
                ezmemory.add_player_tokens(player_id, info.amount or 0)
                table.insert(names_acc, tostring(info.amount or 0) .. " Tokens")
            end
        end
    end
end

-- Open exactly one pack: spend, grant, popup
local function open_one_pack(player_id, area_id, pack, mug)
    if not ezmemory.spend_player_money(player_id, pack.price or 0) then
        return false, "You don't have enough money."
    end
    local gained = {}
    grant_one_pack(player_id, area_id, pack, gained)
    if sfx and sfx.item_get then Net.play_sound_for_player(player_id, sfx.item_get) end
    await(Async.message_player(
        player_id,
        (#gained > 0)
            and string.format("Opened %s and got:\n- %s", pack.name, table.concat(gained, "\n- "))
            or string.format("Opened %s... but it was empty?", pack.name),
        mug.texture_path, mug.animation_path
    ))
    if JobBBS and JobBBS.on_pack_open then
      pcall(JobBBS.on_pack_open, player_id, { count = 1, pack = pack.name })
    end
    return true
end

-- Open N packs at once: charge upfront; aggregate by name; one popup
local function open_n_packs(player_id, area_id, pack, mug, n)
    n = n or 10
    local total_cost = (pack.price or 0) * n
    if total_cost < 0 then total_cost = 0 end
    if not ezmemory.spend_player_money(player_id, total_cost) then
        return false, "You don't have enough money."
    end

    local counts, order = {}, {}
    for _ = 1, n do
        local names = {}
        grant_one_pack(player_id, area_id, pack, names)
        for _, name in ipairs(names) do
            if not counts[name] then
                counts[name] = 1
                table.insert(order, name)
            else
                counts[name] = counts[name] + 1
            end
        end
    end

    if sfx and sfx.item_get then Net.play_sound_for_player(player_id, sfx.item_get) end

    local lines = {}
    for _, name in ipairs(order) do
        table.insert(lines, string.format("x%d %s", counts[name], name))
    end
    local header = string.format("Opened %d x %s and got:", n, pack.name)
    local body = (#lines > 0) and (header.."\n- "..table.concat(lines, "\n- ")) or (header.."\n(nothing?)")
    await(Async.message_player(player_id, body, mug.texture_path, mug.animation_path))
    if JobBBS and JobBBS.on_pack_open then
      pcall(JobBBS.on_pack_open, player_id, { count = n, pack = pack.name })
    end
    return true
end

local function open_packs_for_ng_shop(player_id, area_id, pack, n)
    n = math.max(1, math.floor(tonumber(n) or 1))

    local unit_price = math.max(0, tonumber(pack.price) or 0)
    local total_cost = unit_price * n

    if total_cost > 0 and not ezmemory.spend_player_money(player_id, total_cost) then
        return false, "You don't have enough money."
    end

    local counts, order = {}, {}

    for _ = 1, n do
        local names = {}
        grant_one_pack(player_id, area_id, pack, names)

        for _, name in ipairs(names) do
            if not counts[name] then
                counts[name] = 1
                table.insert(order, name)
            else
                counts[name] = counts[name] + 1
            end
        end
    end

    if sfx and sfx.item_get then
        Net.play_sound_for_player(player_id, sfx.item_get)
    end

    if JobBBS and JobBBS.on_pack_open then
        pcall(JobBBS.on_pack_open, player_id, { count = n, pack = pack.name })
    end

    local lines = {}
    for _, name in ipairs(order) do
        lines[#lines + 1] = string.format("x%d %s", counts[name], name)
    end

    local header
    if n == 1 then
        header = string.format("Opened 1 x %s and got:", tostring(pack.name))
    else
        header = string.format("Opened %d x %s and got:", n, tostring(pack.name))
    end

    local body = (#lines > 0)
        and (header .. "\n- " .. table.concat(lines, "\n- "))
        or (header .. "\n(nothing?)")

    if total_cost > 0 then
        body = body .. string.format("\n\n(-%d$)", total_cost)
    end

    return true, body
end

local function short_money(n)
    n = tonumber(n) or 0
    local abs = math.abs(n)
    if abs >= 1e9 then
        return string.format("$%dB", math.floor(n/1e9 + 0.5))
    elseif abs >= 1e6 then
        local v = n/1e6
        if v >= 10 or v == math.floor(v) then
            return string.format("$%dM", math.floor(v + 0.5))
        else
            return string.format("$%.1fM", v)
        end
    elseif abs >= 1e3 then
        local v = n/1e3
        if v >= 10 or v == math.floor(v) then
            return string.format("$%dk", math.floor(v + 0.5))
        else
            return string.format("$%.1fk", v)
        end
    else
        return string.format("$%d", n)
    end
end

-- 3-option chooser: Buy 1 / Buy 10 / Cancel (B acts as Cancel in quiz); fallback to Yes/No if needed
local function choose_buy_quantity(player_id, mug, pack)
    local p = tonumber(pack.price or 0)
    local opt1 = string.format("Buy 1 (%s)",  short_money(p))
    local opt2 = string.format("Buy 10 (%s)", short_money(p * 10))
    local opt3 = "Cancel"

    -- Primary path: 3-option cursor selection
    local res = await(Async.quiz_player(player_id, opt1, opt2, opt3, mug.texture_path, mug.animation_path))
    -- quiz_player returns 0/1/2
    if res == 0 then return 1 end
    if res == 1 then return 10 end
    if res == 2 then return nil end

    -- Fallback: two Yes/No prompts (B behaves as No)
    local buy1 = await(Async.question_player(player_id, opt1.."?",
                    mug.texture_path, mug.animation_path))
    if buy1 then return 1 end

    local buy10 = await(Async.question_player(player_id, opt2.."?",
                    mug.texture_path, mug.animation_path))
    if buy10 then return 10 end

    return nil
end

local function normalize_shop_preview_path(p)
    p = tostring(p or "")
    if p == "" then return nil end

    if not p:match("%.[%w]+$") then
        p = p .. ".png"
    end

    if p:sub(1, 7) == "/server/" then
        return p
    end

    if p:sub(1, 1) == "/" then
        return p
    end

    return "/server/assets/" .. p
end

local function pack_shop_action(npc, player_id, dialogue, relay_object)
    return async(function ()
        local area_id = Net.get_player_area(player_id)
        local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
        local pack = read_single_pack(dialogue)
        local ci = build_ci_props(dialogue)

        if not pack or not pack.groups or #pack.groups == 0 then
            await(Async.message_player(
                player_id,
                "Sorry, I'm not selling any packs right now.",
                mug.texture_path, mug.animation_path
            ))
            return dialogue.custom_properties["Next 1"]
        end

        --=====================================================
        -- NEW: net-games powered pack shop
        --=====================================================
        local ok_menu, TalkVertMenu_or_err = pcall(require, "scripts/net-games/npcs/talk_vert_menu")
        if ok_menu then
            local TalkVertMenu = TalkVertMenu_or_err
            local TalkPresets = require("scripts/net-games/npcs/talk_presets")

            local title = tostring(get_ci(ci, "shop title") or "Pack Shop")

            -- PROG prompt mug, but using this NPC's real mug assets
            local prog_mug = helpers.deep_copy(TalkPresets.mugs.prog or { enabled = true })
            prog_mug.texture_path = mug.texture_path
            prog_mug.anim_path = mug.animation_path
            prog_mug.sprite_id = nil

            local DEFAULT_ICON = "/server/assets/net-games/ui/card_shop_item.png"

            local preview_path = normalize_shop_preview_path(
                get_ci(ci, "pack preview")
                or get_ci(ci, "preview")
                or get_ci(ci, "icon")
                or get_ci(ci, "shop preview")
                or get_ci(ci, "preview path")
            )

            if preview_path and Net and Net.has_asset then
                local ok, exists = pcall(Net.has_asset, preview_path)
                if ok and exists == false then
                    preview_path = nil
                end
            end

            local pack_icon = preview_path or DEFAULT_ICON

            if Net and Net.provide_asset_for_player then
                pcall(Net.provide_asset_for_player, player_id, pack_icon)
            end

            local price = math.max(0, tonumber(pack.price) or 0)
            local rolls = math.max(1, tonumber(pack.rolls) or 1)
            local suffix = (rolls == 1) and "card" or "cards"

            local options = {
                {
                    id = "buy1",
                    text = "Buy 1",
                    shop_name = "Buy 1",
                    shop_price = price,
                },
                {
                    id = "buy10",
                    text = "Buy 10",
                    shop_name = "Buy 10",
                    shop_price = price * 10,
                },
                {
                    id = "exit",
                    text = "Exit",
                }
            }

            local intro_lines = {
                tostring(pack.name),
                string.format("%d$ each • %d %s", price, rolls, suffix),
            }

            local desc = tostring(pack.description or "")
            if desc ~= "" then
                intro_lines[#intro_lines + 1] = desc
            end

            local talk_cfg = {
                preset = "prog_prompt",
                area_id = area_id,
                object = "packshop_" .. tostring(dialogue.id or "shop"),
                ui = {
                    mugshot = prog_mug,
                    typing_speed = 9999,
                }
            }

            local layout = TalkPresets.get_vert_menu_layout("prog_prompt_shop") or {}

            local assets = {
                menu_bg       = "/server/assets/net-games/ui/prompt_vert_menu_shop_an.png",
                menu_bg_anim  = "/server/assets/net-games/ui/prompt_vert_menu_an.animation",
                menu_bg_frame = "/server/assets/net-games/ui/prompt_vert_menu_shop_an_frame.png",
                highlight     = "/server/assets/net-games/ui/highlight_shop.png",
            }

            if Net.lock_player_input then
                pcall(Net.lock_player_input, player_id)
            end

            TalkVertMenu.open(player_id, title, talk_cfg, {
                intro_text = table.concat(intro_lines, "\n"),
                options = options,
                exit_index = #options,
                layout = layout,
                assets = assets,

                monies_amount_fn = function(pid)
                    return tostring(tonumber(Net.get_player_money(pid) or 0) or 0)
                end,

                shop_item_texture_fn = function(choice)
                    if not choice or not choice.id then
                        return DEFAULT_ICON
                    end
                    if tostring(choice.id) == "exit" then
                        return DEFAULT_ICON
                    end
                    return pack_icon
                end,

                flow = {
                    keep_menu_open = true,
                    after_text = "Anything else?",
                    exit_goodbye_text = "Come again!",

                    confirm = {
                        enabled = true,
                        skip_ids = { exit = true },
                        text_fn = function(pid, choice_id)
                            local qty = (tostring(choice_id) == "buy10") and 10 or 1
                            local total_cost = price * qty
                            local have = tonumber(Net.get_player_money(pid) or 0) or 0

                            return string.format(
                                "Buy %d x %s for %d$?\nYou have %d$",
                                qty,
                                tostring(pack.name),
                                total_cost,
                                have
                            )
                        end,
                    },

                    post_select = { enabled = true, skip_ids = { exit = true } },
                },

                on_confirm_yes = function(pid, choice_id, _choice_text, menu)
                    local qty = (tostring(choice_id) == "buy10") and 10 or 1

                    local ok, result_text = open_packs_for_ng_shop(pid, area_id, pack, qty)
                    if not ok then
                        return result_text or "You don't have enough money.", "Anything else?"
                    end

                    -- refresh live balance immediately
                    if menu and menu.render_menu_contents then
                        pcall(function() menu:render_menu_contents(true) end)
                    end

                    return result_text, "Anything else?"
                end,
            })

            while TalkVertMenu.is_busy and TalkVertMenu.is_busy(player_id) do
                await(Async.sleep(0.05))
            end

            return dialogue.custom_properties["Next 1"]
        end

        --=====================================================
        -- Fallback: keep old Pack Shop behavior if net-games is unavailable
        --=====================================================
        local rolls = pack.rolls or 1
        local suffix = (rolls == 1) and "card" or "cards"

        await(Async.message_player(
            player_id,
            string.format("%s - %d$ (%d %s)\n\n%s", pack.name, pack.price or 0, rolls, suffix, pack.description or ""),
            mug.texture_path, mug.animation_path
        ))

        local qty = choose_buy_quantity(player_id, mug, pack)
        if not qty then
            return dialogue.custom_properties["Next 1"]
        end

        local ok, msg
        if qty == 1 then
            ok, msg = open_one_pack(player_id, area_id, pack, mug)
        else
            ok, msg = open_n_packs(player_id, area_id, pack, mug, 10)
        end

        if not ok then
            if msg then
                await(Async.message_player(player_id, msg, mug.texture_path, mug.animation_path))
            end
            return dialogue.custom_properties["Next 1"]
        end

        while true do
            local qty2 = choose_buy_quantity(player_id, mug, pack)
            if not qty2 then break end

            local ok2, msg2
            if qty2 == 1 then
                ok2, msg2 = open_one_pack(player_id, area_id, pack, mug)
            else
                ok2, msg2 = open_n_packs(player_id, area_id, pack, mug, 10)
            end

            if not ok2 then
                if msg2 then
                    await(Async.message_player(player_id, msg2, mug.texture_path, mug.animation_path))
                end
                break
            end
        end

        return dialogue.custom_properties["Next 1"]
    end)
end

-- Register (exact name)
eznpcs.add_event{ name = "Pack Shop", action = pack_shop_action }

local function ci_props(dialogue)
  local ci = {}; for k,v in pairs(dialogue.custom_properties or {}) do ci[string.lower(tostring(k))] = v end; return ci
end
local function get(ci,k) return ci[string.lower(k)] end
local function seq(ci,prefix) local out,i={},1; while true do local v=ci[prefix..i]; if v==nil then break end; out[#out+1]=v; i=i+1 end; return out end

local function read_groups(dialogue)
  local ci = ci_props(dialogue)
  local pools = {
    { label="Common",     items=seq(ci,"common "),     weight=tonumber(get(ci,"common rate"))     },
    { label="Rare",       items=seq(ci,"rare "),       weight=tonumber(get(ci,"rare rate"))       },
    { label="Super Rare", items=seq(ci,"super rare "), weight=tonumber(get(ci,"super rare rate")) },
    { label="Ultra Rare", items=seq(ci,"ultra rare "), weight=tonumber(get(ci,"ultra rare rate")) },
    { label="Gold Rare",  items=seq(ci,"gold rare "),  weight=tonumber(get(ci,"gold rare rate"))  },
    { label="Ghost Rare", items=seq(ci,"ghost rare "), weight=tonumber(get(ci,"ghost rare rate")) },
  }
  local any=false; for _,p in ipairs(pools) do if (p.weight or 0) > 0 then any=true break end end
  if not any then
    local has_gdr = pools[5].items and #pools[5].items > 0
    local has_gr  = pools[6].items and #pools[6].items > 0
    if has_gdr or has_gr then
      pools[1].weight,pools[2].weight,pools[3].weight,pools[4].weight = 753,207,30,9
      pools[5].weight = has_gdr and 1 or 0
      pools[6].weight = has_gr  and 1 or 0
    else
      pools[1].weight,pools[2].weight,pools[3].weight,pools[4].weight = 70,25,4,1
    end
  end
  local groups = {}
  for _,p in ipairs(pools) do
    if p.items and #p.items>0 and (p.weight or 0)>0 then groups[#groups+1]=p end
  end
  return groups
end

eznpcs.add_event{
  name = "Card Trader",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
      local groups = read_groups(dialogue)
      if not groups or #groups == 0 then
        await(Async.message_player(player_id, "Trader is misconfigured: no return pools.", mug.texture_path, mug.animation_path))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end
      local desc = (dialogue.custom_properties and (dialogue.custom_properties["pack description"] or dialogue.custom_properties["Pack Description"])) or
                   "Trade any 10 cards and I'll give you 1 random card."
      -- Kick off the board-driven picker; the BBS plugin handles the rest
      custom.start_card_trade(player_id, { desc = desc, groups = groups })
      -- Optionally show their mug once before opening the board:
      await(Async.message_player(player_id, "Let's trade - pick exactly 10 cards.", mug.texture_path, mug.animation_path))
      return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
    end)
  end
}

eznpcs.add_event{
  name = "Card Battle (NPC)",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
      await(Async.message_player(
        player_id,
        "Let's duel! I'll build decks from your collection.\n(10 cards; UR/GDR=1, SR≤2, R≤3, C=any)",
        mug.texture_path, mug.animation_path
      ))

      local npc_name =
        (dialogue and dialogue.custom_properties and
         (dialogue.custom_properties["NPC Name"] or dialogue.custom_properties["Npc Name"])) or "NPC Duelist"

      -- We’ll wait for this to flip true
      local done, result = false, nil

      local ci = build_ci_props(dialogue)
      -- Accept either “Deck 1..10” or (fallback) “Card 1..10”
      local deck_ids = extract_seq_ci(ci, "deck ")
      if #deck_ids == 0 then
        deck_ids = extract_seq_ci(ci, "card ")
      end
      -- Optional: enforce exactly 10; otherwise leave nil to fall back to random
      if #deck_ids ~= 10 then deck_ids = nil end

      -- Start the duel and inject an on_finish that completes our wait
      duels.start_card_battle(player_id, {
        npc_name = npc_name,
        npc_deck_ids = deck_ids,
        on_finish = function(res)
          result = res
          done   = true
          -- JobBBS hook (matches what custom.lua used to do)
          local JobBBS = rawget(_G, "JobBBS")
          if JobBBS and JobBBS.on_npc_duel_result and res then
            local winner = res.player_won and 1 or 2 -- JobBBS only counts when winner==1
            pcall(JobBBS.on_npc_duel_result, player_id, {
              winner = winner,
              npc_name = npc_name,
              kos = 3,
            })
          end
        end
      })

      -- tick helper that always returns a real awaitable
      local function _tick()
        if Async.sleep_frames then return Async.sleep_frames(1) end
        if Async.sleep        then return Async.sleep(0.016) end
        -- fall back to deferring one turn; ezlibs usually supports this
        return Async.defer()
      end

      -- Wait here until on_finish runs
      while not done do
        await(_tick())
      end

      -- IMPORTANT: duels calls on_finish BEFORE it clears/deallocates the duel sprites.
      -- So wait until the duel UI is actually closed before continuing.
      while duels.is_open_for and duels.is_open_for(player_id) do
        await(_tick())
      end

      -- Deck construction failed before the duel could begin.
      if result and result.reason == "init_failed" then
        await(Async.message_player(
          player_id,
          "You don't have enough cards to build a valid 10-card deck.",
          mug.texture_path,
          mug.animation_path
        ))
        return nil
      end

      if result and result.player_won then
        return dialogue.custom_properties["Battle Won"]
      else
        return dialogue.custom_properties["Battle Lost"]
      end
    end)
  end
}

local event_hp_warp = {
  name = "HP Warp",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function ()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)

      local prompt = dialogue.custom_properties["Prompt"] or "Which HP would you like to visit?"
      await(Async.message_player(player_id, prompt, mug.texture_path, mug.animation_path))

      -- Free-text input (player can type a number)
      local raw = await(Async.prompt_player(player_id))
      if raw == nil or raw == "" then
        return dialogue.custom_properties["On Cancel"] or dialogue.custom_properties["Next 2"]
      end

      -- Extract first number from the input
      local n = tonumber(tostring(raw):match("%d+"))
      local min = tonumber(dialogue.custom_properties["Min"]) or 1
      local max = tonumber(dialogue.custom_properties["Max"]) or 999
      if not n or n < min or n > max then
        local msg = dialogue.custom_properties["Invalid Msg"] or "That's not a valid HP."
        await(Async.message_player(player_id, msg, mug.texture_path, mug.animation_path))
        return dialogue.custom_properties["On Invalid"] or dialogue.custom_properties["Next 2"]
      end

      -- Build the landing key string
      local pad = tonumber(dialogue.custom_properties["Pad"]) or 0
      local nn  = (pad > 0) and string.format("%0"..pad.."d", n) or tostring(n)
      local tpl = dialogue.custom_properties["Data Template"] or "HP {n}"
      local data = tpl:gsub("{n}", nn)

      print(string.format("[HPWarp] pid=%s input=%s -> landing='%s'", tostring(player_id), tostring(raw), data))

      -- Hand off to ezwarps (will transfer immediately if it finds the landing) 
      ezwarps.handle_player_request(player_id, data)

      -- We end the dialogue here (warp happens or ezwarps logs “no landing” if missing)
      return nil
    end)
  end
}
eznpcs.add_event(event_hp_warp)

eznpcs.add_event{
  name = "cosmeticshop",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
      local ci = build_ci_props(dialogue)

      if not cosmetics or not cosmetics.unlock_for_player then
        await(Async.message_player(
          player_id,
          "Cosmetics system is not available right now.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      local title = tostring(get_ci(ci, "shop title") or "Cosmetic Shop")
      local not_enough_msg = tostring(get_ci(ci, "not enough msg") or "You don't have enough money.")
      local owned_msg = tostring(get_ci(ci, "already owned msg") or "You already have that cosmetic.")

      local offers = {}
      local i = 1
      while true do
        local sell = get_ci(ci, "sell " .. i)
        if not sell then break end

        local price = math.max(0, math.floor(tonumber(
          get_ci(ci, "price " .. i)
          or get_ci(ci, "cost " .. i)
          or 0
        ) or 0))

        local cosmetic_id = tostring(sell)
        local pretty = (cosmetics.get_name_for_id and cosmetics.get_name_for_id(cosmetic_id)) or cosmetic_id

        table.insert(offers, {
          cosmetic_id = cosmetic_id,
          price = price,
          name = pretty,
        })

        i = i + 1
      end

      if #offers == 0 then
        await(Async.message_player(
          player_id,
          "Sorry, I'm not selling any cosmetics right now.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      local ok_menu, TalkVertMenu_or_err = pcall(require, "scripts/net-games/npcs/talk_vert_menu")
      if not ok_menu then
        await(Async.message_player(
          player_id,
          "The new shop UI isn't available right now.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      local function safe_has_asset(path)
        if not path or path == "" then return false end
        if not (Net and Net.has_asset) then return true end
        local ok, res = pcall(Net.has_asset, path)
        return ok and res == true
      end

      if Net and Net.provide_asset_for_player then
        local seen = {}

        local function push(path)
          if not path or path == "" or seen[path] then return end
          if not safe_has_asset(path) then return end
          seen[path] = true
          pcall(Net.provide_asset_for_player, player_id, path)
        end

        for _, offer in ipairs(offers) do
          local opt = cosmetics.get_shop_option and cosmetics.get_shop_option(offer.cosmetic_id)
          if opt then
            push(opt.menu_preview_texture or opt.texture)
            push(opt.menu_preview_animation or opt.animation)
          end
        end
      end

      await(Async.sleep(0.05))

      local TalkVertMenu = TalkVertMenu_or_err
      local TalkPresets = require("scripts/net-games/npcs/talk_presets")

      local prog_mug = helpers.deep_copy(TalkPresets.mugs.prog or { enabled = true })
      prog_mug.texture_path = mug.texture_path
      prog_mug.anim_path = mug.animation_path
      prog_mug.sprite_id = nil

      local talk_cfg = {
        preset = "prog_prompt",
        area_id = Net.get_player_area(player_id),
        object = "cosmeticshop_" .. tostring(dialogue.id or "shop"),
        ui = {
          mugshot = prog_mug,
          typing_speed = 9999,
        }
      }

      local layout = TalkPresets.get_vert_menu_layout("prog_prompt_shop") or {}

      -- Reduce redraw/animation churn while the cosmetic preview is active.
      layout.text_intro_enabled = false
      layout.shop_item_intro_enabled = false

      -- Cosmetic shop uses its own preview sprites, not the built-in shop item icon.
      layout.shop_item_enabled = false
      layout.shop_item_swap_exit = false

      local assets = {
        menu_bg       = "/server/assets/net-games/ui/prompt_vert_menu_shop_an.png",
        menu_bg_anim  = "/server/assets/net-games/ui/prompt_vert_menu_an.animation",
        menu_bg_frame = "/server/assets/net-games/ui/prompt_vert_menu_shop_an_frame.png",
        highlight     = "/server/assets/net-games/ui/highlight_shop.png",
      }

      local options = {}
      local by_choice_id = {}

      for _, offer in ipairs(offers) do
        local owned = cosmetics.has_cosmetic and cosmetics.has_cosmetic(player_id, offer.cosmetic_id)
        local display_name = owned and (offer.name .. " [Owned]") or offer.name

        options[#options + 1] = {
          id = offer.cosmetic_id,
          text = display_name,
          shop_name = display_name,
          shop_price = offer.price,
        }

        by_choice_id[offer.cosmetic_id] = offer
      end

      options[#options + 1] = { id = "exit", text = "Exit" }
      local exit_index = #options

      local last_preview_id = "__none__"

      local function update_cosmetic_shop_preview(choice)
        local id = choice and choice.id and tostring(choice.id) or nil

        if id == "exit" then
          id = nil
        end

        -- PromptVertical can call this during normal redraws/animations.
        -- Only touch preview sprites when the selected cosmetic actually changes.
        if id == last_preview_id then
          return nil
        end

        last_preview_id = id

        if id then
          if cosmetics.show_shop_preview then
            cosmetics.show_shop_preview(player_id, id)
          end
        else
          if cosmetics.clear_shop_previews then
            cosmetics.clear_shop_previews(player_id)
          end
        end

        return nil
      end

      if Net.lock_player_input then
        pcall(Net.lock_player_input, player_id)
      end

      TalkVertMenu.open(player_id, title, talk_cfg, {
        intro_text = "What would you like?",
        options = options,
        exit_index = exit_index,
        layout = layout,
        assets = assets,

        monies_amount_fn = function(pid)
          return tostring(tonumber(Net.get_player_money(pid) or 0) or 0)
        end,

        shop_item_texture_fn = update_cosmetic_shop_preview,

        flow = {
          keep_menu_open = true,
          after_text = "Anything else?",
          exit_goodbye_text = "Come again!",

          confirm = {
            enabled = true,
            skip_ids = { exit = true },
            text_fn = function(pid, choice_id)
              local offer = by_choice_id[tostring(choice_id)]
              if not offer then
                return "Buy this cosmetic?"
              end

              local have = tonumber(Net.get_player_money(pid) or 0) or 0
              return string.format(
                "Buy %s for %d$?\nYou have %d$",
                tostring(offer.name),
                tonumber(offer.price) or 0,
                have
              )
            end,
          },

          post_select = { enabled = true, skip_ids = { exit = true } },
        },

        on_confirm_yes = function(pid, choice_id, _choice_text, menu)
          local offer = by_choice_id[tostring(choice_id)]
          if not offer then
            return "Huh? That cosmetic is gone.", "Anything else?"
          end

          if cosmetics.has_cosmetic and cosmetics.has_cosmetic(pid, offer.cosmetic_id) then
            return owned_msg, "Anything else?"
          end

          local cost = math.max(0, tonumber(offer.price) or 0)
          if cost > 0 and not ezmemory.spend_player_money(pid, cost) then
            local have = tonumber(Net.get_player_money(pid) or 0) or 0
            return string.format(
              "%s\nCost: %d$  You have: %d$",
              not_enough_msg,
              cost,
              have
            ), "Anything else?"
          end

          local ok, reason = cosmetics.unlock_for_player(pid, offer.cosmetic_id)
          if not ok then
            if cost > 0 then
              ezmemory.spend_player_money(pid, -cost)
            end

            local msg = (reason == "already_owned" or reason == "already_unlocked")
              and owned_msg
              or ("Couldn't unlock that cosmetic (" .. tostring(reason or "error") .. ").")

            return msg, "Anything else?"
          end

          if menu and menu.options then
            for _, opt in ipairs(menu.options) do
              if tostring(opt.id) == tostring(choice_id) then
                opt.text = offer.name .. " [Owned]"
                opt.shop_name = offer.name .. " [Owned]"
                break
              end
            end
          end

          if menu and menu.render_menu_contents then
            pcall(function() menu:render_menu_contents(true) end)
          end

          if sfx and sfx.item_get then
            pcall(Net.play_sound_for_player, pid, sfx.item_get)
          end

          if cost > 0 then
            return string.format("You got the %s cosmetic!\n(-%d$)", offer.name, cost), "Anything else?"
          end

          return string.format("You got the %s cosmetic!", offer.name), "Anything else?"
        end,
      })

      while TalkVertMenu.is_busy and TalkVertMenu.is_busy(player_id) do
        await(Async.sleep(0.05))
      end

      if cosmetics and cosmetics.clear_shop_previews then
        cosmetics.clear_shop_previews(player_id)
      end

      return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
    end)
  end
}

eznpcs.add_event{
  name = "sleeveshop",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)

      if not card_sleeves or not card_sleeves.unlock_for_player then
        await(Async.message_player(
          player_id,
          "Card sleeves system is not available right now.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      local ci = build_ci_props(dialogue)
      local title = tostring(get_ci(ci, "shop title") or "Card Sleeve Shop")

      -- Build offers from Sell N / Price N; if none configured, sell ALL known sleeves at Price=0.
      local offers = {}
      local i = 1
      while true do
        local sell = get_ci(ci, "sell " .. i)
        if not sell then break end

        local price = tonumber(get_ci(ci, "price " .. i) or get_ci(ci, "cost " .. i) or 0) or 0
        if price < 0 then price = 0 end

        local sleeve_id = tostring(sell)
        table.insert(offers, {
          sleeve_id = sleeve_id,
          price = price,
          name = (card_sleeves.get_name_for_id and card_sleeves.get_name_for_id(sleeve_id)) or sleeve_id,
        })

        i = i + 1
      end

      if #offers == 0 then
        for _, def in ipairs(card_sleeves.list_defs()) do
          table.insert(offers, {
            sleeve_id = def.id,
            price = 0,
            name = def.name or def.id,
          })
        end
      end

      if #offers == 0 then
        await(Async.message_player(
          player_id,
          "Sorry, I'm not selling any card sleeves right now.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      while true do
        local posts, items = {}, {}

        for _, offer in ipairs(offers) do
          local owned = card_sleeves.has_sleeve(player_id, offer.sleeve_id)
          local label = owned
            and string.format("%s (%s, Owned)", offer.name, short_money(offer.price))
            or  string.format("%s (%s)",        offer.name, short_money(offer.price))

          table.insert(posts, helpers.create_bbs_option(label))
          items[#posts] = offer
        end

        local board = ezmenus.open_menu(player_id, title, COSMETIC_SHOP_COLOR, posts)
        local sel = await(board.selection_once())
        Net.close_bbs(player_id)

        if not sel then break end

        local chosen
        for idx, post in ipairs(posts) do
          local pid = post.id or post.title or ""
          if sel == pid then
            chosen = items[idx]
            break
          end
        end
        if not chosen then break end

        if card_sleeves.has_sleeve(player_id, chosen.sleeve_id) then
          await(Async.message_player(
            player_id,
            "You already own the " .. chosen.name .. " sleeve.",
            mug.texture_path, mug.animation_path
          ))
        else
          -- Preview in the center while confirming purchase
          card_sleeves.preview_for_shop(player_id, chosen.sleeve_id)

          local q = string.format("Buy %s sleeve for %s?", chosen.name, short_money(chosen.price))
          local res = await(Async.question_player(player_id, q, mug.texture_path, mug.animation_path))
          local do_buy = (res == 1)

          card_sleeves.clear_shop_previews(player_id)

          if do_buy then
            local price = chosen.price or 0
            if price > 0 and not ezmemory.spend_player_money(player_id, price) then
              await(Async.message_player(
                player_id,
                "You don't have enough money.",
                mug.texture_path, mug.animation_path
              ))
            else
              local ok, reason = card_sleeves.unlock_for_player(player_id, chosen.sleeve_id)
              if ok then
                -- Since selector isn’t built yet, auto-equip what they bought
                pcall(card_sleeves.set_equipped, player_id, chosen.sleeve_id)

                if sfx and sfx.item_get then
                  Net.play_sound_for_player(player_id, sfx.item_get)
                end
                await(Async.message_player(
                  player_id,
                  "You got the " .. chosen.name .. " sleeve! (Equipped)",
                  mug.texture_path, mug.animation_path
                ))
              else
                await(Async.message_player(
                  player_id,
                  "Couldn't unlock that sleeve (" .. tostring(reason or "error") .. ").",
                  mug.texture_path, mug.animation_path
                ))
              end
            end
          end
        end
      end

      return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
    end)
  end
}

----------------------------------------------------------------
-- Multi-type BugFrag Shop
-- Dialogue Type: "fragshop"
--
-- Supported Type N values:
--   chip       = whitelist BattleChip, unique, becomes SOLD OUT
--   cosmetic   = cosmetic unlock, unique, becomes SOLD OUT
--   pet        = modern owned pet, repeatable
--
-- Required per listing:
--   Sell N, Type N, Price N
--
-- Optional per listing:
--   Amount N, Name N, Code N, Preview N, Icon N
--
-- Optional shared:
--   Shop Title, Not Enough Msg, Already Owned Msg, Sold Out Msg
--   Preview Dir, Preview Ext
--   Pet Preview X/Y/Z/Scale/State
----------------------------------------------------------------

local FRAGSHOP_DEFAULT_ICON = "/server/assets/net-games/ui/card_shop_item.png"

local function fragshop_type(raw_type, item_id)
  local typ = tostring(raw_type or "chip"):lower()

  if typ == "card" or typ == "battlechip" or typ == "battle chip" then
    typ = "chip"
  elseif typ == "cosmetics" then
    typ = "cosmetic"
  elseif typ == "pets" then
    typ = "pet"
  elseif typ == "decor" and tostring(item_id or ""):sub(1, 4) == "pet_" then
    -- Backwards compatibility for the old Dungeon1 setup.
    typ = "pet"
  end

  return typ
end

local function oncehub_catalog_name_for(id)
  id = tostring(id or "")
  local cat = rawget(_G, "ONCEHUB_CATALOG") or ONCEHUB_CATALOG
  if type(cat) == "table" then
    for _, e in ipairs(cat) do
      if tostring(e.id) == id then
        return e.name or e.label or e.title or id
      end
    end
  end
  return id
end

local function fragshop_pet_kind(item_id)
  return tostring(item_id or ""):gsub("^pet_", ""):lower()
end

local function fragshop_pet_name(item_id)
  local name = fragshop_pet_kind(item_id):gsub("_", " ")

  name = name:gsub("(%a)([%w']*)", function(first, rest)
    return first:upper() .. rest:lower()
  end)

  return name ~= "" and name or "Pet"
end

local function fragshop_chip_name(card_def, fallback)
  if card_def then
    if card_def.display_name then
      return tostring(card_def.display_name)
    end

    if card_def.name then
      return tostring(card_def.name)
    end
  end

  return tostring(fallback or "BattleChip")
end

local function fragshop_is_sold_out(pid, offer)
  if not offer then
    return true
  end

  if offer.type == "chip" then
    return whitelist.player_has_card_unlocked(
      pid,
      offer.item_id
    ) == true
  end

  if offer.type == "cosmetic" then
    return cosmetics
      and cosmetics.has_cosmetic
      and cosmetics.has_cosmetic(pid, offer.item_id)
      or false
  end

  -- Pets remain repeatable. Each purchase creates a new pet UID.
  return false
end

local function oncehub_count_owned(pid, id)
  id = tostring(id or "")
  if id == "" then return 0 end
  local secret = (helpers and helpers.get_safe_player_secret) and helpers.get_safe_player_secret(pid) or pid
  local pmem = ezmemory.get_player_memory(secret) or {}
  local inv = pmem[DECOR_MEM_KEY__ONCEHUB]
  if type(inv) ~= "table" then return 0 end
  return tonumber(inv[id] or 0) or 0
end

local function fragshop_clear_previews(pid)
  if cosmetics and cosmetics.clear_shop_previews then
    pcall(cosmetics.clear_shop_previews, pid)
  end

  if Pets and Pets.clear_shop_preview then
    pcall(Pets.clear_shop_preview, pid)
  end
end

local function fragshop_refund(pid, amount)
  amount = math.max(
    0,
    math.floor(tonumber(amount) or 0)
  )

  if amount > 0 then
    pcall(
      ezmemory.spend_player_fragments,
      pid,
      -amount
    )
  end
end

local function fragshop_update_row(
  menu,
  choice_id,
  offer,
  sold_out
)
  if not (menu and menu.options) then
    return
  end

  for _, opt in ipairs(menu.options) do
    if tostring(opt.id) == tostring(choice_id) then
      local label = sold_out
        and "SOLD OUT"
        or tostring(offer.name)

      opt.text = label
      opt.shop_name = label
      opt.shop_price = tonumber(offer.price) or 0
      break
    end
  end

  -- TalkVertMenu redraws after the result text closes.
end

eznpcs.add_event{
  name = "fragshop",

  action = function(
    npc,
    player_id,
    dialogue,
    relay_object
  )
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(
        npc,
        player_id,
        dialogue
      )

      local ci = build_ci_props(dialogue)

      if not (
        ezmemory
        and ezmemory.get_player_fragments
        and ezmemory.spend_player_fragments
      ) then
        await(Async.message_player(
          player_id,
          "BugFrag shop isn't available on this server build.",
          mug.texture_path,
          mug.animation_path
        ))

        return dialogue.custom_properties
          and dialogue.custom_properties["Next 1"]
      end

      local ok_menu, TalkVertMenu = pcall(
        require,
        "scripts/net-games/npcs/talk_vert_menu"
      )

      local ok_presets, TalkPresets = pcall(
        require,
        "scripts/net-games/npcs/talk_presets"
      )

      if not ok_menu
        or not TalkVertMenu
        or not ok_presets
        or not TalkPresets
      then
        await(Async.message_player(
          player_id,
          "The new BugFrag shop UI isn't available right now.",
          mug.texture_path,
          mug.animation_path
        ))

        return dialogue.custom_properties
          and dialogue.custom_properties["Next 1"]
      end

      local title = tostring(
        get_ci(ci, "shop title")
        or "BugFrag Dealer"
      )

      local not_enough_msg = tostring(
        get_ci(ci, "not enough msg")
        or "You don't have enough BugFrags."
      )

      local owned_msg = tostring(
        get_ci(ci, "already owned msg")
        or "You already own that item."
      )

      local sold_out_msg = tostring(
        get_ci(ci, "sold out msg")
        or "That item is SOLD OUT."
      )

      local preview_dir = tostring(
        get_ci(ci, "preview dir")
        or "chips/previews/"
      )

      local preview_ext = tostring(
        get_ci(ci, "preview ext")
        or ".png"
      )

      local offers = {}
      local i = 1

      while true do
        local raw_sell = get_ci(ci, "sell " .. i)

        if raw_sell == nil then
          break
        end

        local item_id = tostring(raw_sell)

        local typ = fragshop_type(
          get_ci(ci, "type " .. i),
          item_id
        )

        local amount = math.max(
          1,
          math.floor(tonumber(
            get_ci(ci, "amount " .. i)
            or 1
          ) or 1)
        )

        local price = math.max(
          0,
          math.floor(tonumber(
            get_ci(ci, "price " .. i)
            or get_ci(ci, "cost " .. i)
            or 0
          ) or 0)
        )

        local custom_name = get_ci(
          ci,
          "name " .. i
        )

        local offer = {
          choice_id = tostring(i),
          item_id = item_id,
          type = typ,
          amount = amount,
          price = price,
        }

        local valid = false

        if typ == "chip" then
          local card_def = whitelist
            and whitelist.get_card_def
            and whitelist.get_card_def(item_id)
            or nil

          if card_def and card_def.package_id then
            offer.name = tostring(
              custom_name
              or fragshop_chip_name(
                card_def,
                item_id
              )
            )

            offer.code = tostring(
              get_ci(ci, "code " .. i)
              or card_def.code
              or "*"
            )

            local preview =
              get_ci(ci, "preview " .. i)
              or get_ci(ci, "icon " .. i)

            if preview == nil
              or tostring(preview) == ""
            then
              local dir = preview_dir

              if dir ~= ""
                and dir:sub(-1) ~= "/"
              then
                dir = dir .. "/"
              end

              preview = dir
                .. tostring(
                  card_def.preview_key
                  or card_def.card_key
                  or item_id
                )
                .. preview_ext
            end

            offer.preview_path =
              normalize_shop_preview_path(preview)

            if offer.preview_path
              and Net
              and Net.has_asset
            then
              local ok_exists, exists = pcall(
                Net.has_asset,
                offer.preview_path
              )

              if ok_exists and exists == false then
                offer.preview_path =
                  FRAGSHOP_DEFAULT_ICON
              end
            end

            valid = true
          else
            print(
              "[fragshop] invalid chip:",
              item_id
            )
          end

        elseif typ == "cosmetic" then
          local cosmetic_opt = cosmetics
            and cosmetics.get_shop_option
            and cosmetics.get_shop_option(item_id)
            or nil

          if cosmetic_opt then
            offer.name = tostring(
              custom_name
              or (
                cosmetics.get_name_for_id
                and cosmetics.get_name_for_id(item_id)
              )
              or cosmetic_opt.name
              or item_id
            )

            offer.amount = 1
            valid = true
          else
            print(
              "[fragshop] invalid cosmetic:",
              item_id
            )
          end

        elseif typ == "pet" then
          if Pets
            and Pets.grant_owned_pet
            and item_id:sub(1, 4) == "pet_"
          then
            offer.pet_kind =
              fragshop_pet_kind(item_id)

            offer.name = tostring(
              custom_name
              or fragshop_pet_name(item_id)
            )

            valid = true
          else
            print(
              "[fragshop] invalid pet:",
              item_id
            )
          end

        else
          print(
            "[fragshop] unsupported item type:",
            typ,
            item_id
          )
        end

        if valid then
          offers[#offers + 1] = offer
        end

        i = i + 1
      end

      if #offers == 0 then
        await(Async.message_player(
          player_id,
          "Sorry, I'm not selling anything right now.",
          mug.texture_path,
          mug.animation_path
        ))

        return dialogue.custom_properties
          and dialogue.custom_properties["Next 1"]
      end

      local prog_mug = helpers.deep_copy(
        TalkPresets.mugs.prog
        or { enabled = true }
      )

      prog_mug.texture_path = mug.texture_path
      prog_mug.anim_path = mug.animation_path
      prog_mug.sprite_id = nil

      local talk_cfg = {
        preset = "prog_prompt",
        area_id = Net.get_player_area(player_id),

        object = "fragshop_"
          .. tostring(dialogue.id or "shop"),

        ui = {
          mugshot = prog_mug,
          typing_speed = 9999,
        }
      }

      local layout =
        TalkPresets.get_vert_menu_layout(
          "prog_prompt_shop"
        ) or {}

      layout.monies_label_text = "FRAGS"

      local assets = {
        menu_bg =
          "/server/assets/net-games/ui/prompt_vert_menu_shop_an.png",

        menu_bg_anim =
          "/server/assets/net-games/ui/prompt_vert_menu_an.animation",

        menu_bg_frame =
          "/server/assets/net-games/ui/prompt_vert_menu_shop_an_frame.png",

        highlight =
          "/server/assets/net-games/ui/highlight_shop.png",
      }

      local options = {}
      local by_choice_id = {}

      for _, offer in ipairs(offers) do
        local label =
          fragshop_is_sold_out(
            player_id,
            offer
          )
          and "SOLD OUT"
          or offer.name

        options[#options + 1] = {
          id = offer.choice_id,
          text = label,
          shop_name = label,
          shop_price = offer.price,
        }

        by_choice_id[offer.choice_id] =
          offer
      end

      options[#options + 1] = {
        id = "exit",
        text = "Exit"
      }

      local exit_index = #options
      local last_preview_id = "__none__"

      local function update_preview(choice)
        local choice_id =
          choice
          and choice.id
          and tostring(choice.id)
          or nil

        if choice_id == "exit" then
          choice_id = nil
        end

        if choice_id == last_preview_id then
          local current = choice_id
            and by_choice_id[choice_id]
            or nil

          if current
            and current.type == "chip"
          then
            return current.preview_path
              or FRAGSHOP_DEFAULT_ICON
          end

          -- Pet and cosmetic previews draw their own sprites.
          return nil
        end

        last_preview_id = choice_id

        fragshop_clear_previews(
          player_id
        )

        local offer = choice_id
          and by_choice_id[choice_id]
          or nil

        if not offer then
          return FRAGSHOP_DEFAULT_ICON
        end

        if offer.type == "chip" then
          return offer.preview_path
            or FRAGSHOP_DEFAULT_ICON
        end

        if offer.type == "cosmetic" then
          if cosmetics
            and cosmetics.show_shop_preview
          then
            pcall(
              cosmetics.show_shop_preview,
              player_id,
              offer.item_id
            )
          end

          -- Cosmetic preview supplies its own sprites.
          return nil
        end

        if offer.type == "pet" then
          if Pets
            and Pets.show_shop_preview
          then
            pcall(
              Pets.show_shop_preview,
              player_id,
              ci,
              offer.pet_kind
            )
          end

          -- Pet preview supplies its own sprites.
          return nil
        end

        return FRAGSHOP_DEFAULT_ICON
      end

      if Net
        and Net.provide_asset_for_player
      then
        pcall(
          Net.provide_asset_for_player,
          player_id,
          FRAGSHOP_DEFAULT_ICON
        )

        for _, offer in ipairs(offers) do
          if offer.type == "chip"
            and offer.preview_path
          then
            pcall(
              Net.provide_asset_for_player,
              player_id,
              offer.preview_path
            )
          end
        end
      end

      await(Async.sleep(0.05))

      if Net.lock_player_input then
        pcall(
          Net.lock_player_input,
          player_id
        )
      end

      TalkVertMenu.open(
        player_id,
        title,
        talk_cfg,
        {
          intro_text = "What would you like?",
          options = options,
          exit_index = exit_index,
          layout = layout,
          assets = assets,

          monies_amount_fn = function(pid)
            return tostring(
              tonumber(
                ezmemory.get_player_fragments(pid)
                or 0
              ) or 0
            )
          end,

          shop_item_texture_fn =
            update_preview,

          flow = {
            keep_menu_open = true,
            after_text = "Anything else?",
            exit_goodbye_text = "Come again!",

            confirm = {
              enabled = true,
              skip_ids = {
                exit = true
              },

              text_fn = function(
                pid,
                choice_id
              )
                local offer =
                  by_choice_id[
                    tostring(choice_id)
                  ]

                if not offer then
                  return "Buy this?"
                end

                if fragshop_is_sold_out(
                  pid,
                  offer
                ) then
                  return sold_out_msg
                end

                local have = tonumber(
                  ezmemory.get_player_fragments(
                    pid
                  ) or 0
                ) or 0

                local amount_text =
                  (
                    offer.type == "pet"
                    and offer.amount > 1
                  )
                  and (
                    " x"
                    .. offer.amount
                  )
                  or ""

                return string.format(
                  "Buy %s%s for %d BF?\nYou have %d BF",
                  offer.name,
                  amount_text,
                  offer.price,
                  have
                )
              end,
            },

            post_select = {
              enabled = true,
              skip_ids = {
                exit = true
              }
            },
          },

          on_confirm_yes = function(
            pid,
            choice_id,
            _choice_text,
            menu
          )
            local offer =
              by_choice_id[
                tostring(choice_id)
              ]

            if not offer then
              return
                "Huh? That item is gone.",
                "Anything else?"
            end

            if fragshop_is_sold_out(
              pid,
              offer
            ) then
              return
                owned_msg,
                "Anything else?"
            end

            local cost = math.max(
              0,
              math.floor(
                tonumber(offer.price)
                or 0
              )
            )

            if cost > 0
              and not ezmemory.spend_player_fragments(
                pid,
                cost
              )
            then
              local have = tonumber(
                ezmemory.get_player_fragments(
                  pid
                ) or 0
              ) or 0

              return string.format(
                "%s\nCost: %d BF  You have: %d BF",
                not_enough_msg,
                cost,
                have
              ), "Anything else?"
            end

            local granted = false
            local reason = nil
            local created = nil

            if offer.type == "chip" then
              granted, reason =
                whitelist.unlock_card(
                  pid,
                  offer.item_id,
                  offer.code
                )

            elseif offer.type == "cosmetic" then
              granted, reason =
                cosmetics.unlock_for_player(
                  pid,
                  offer.item_id
                )

            elseif offer.type == "pet" then
              local ok_grant, result = pcall(
                Pets.grant_owned_pet,
                pid,
                offer.item_id,
                offer.amount
              )

              created =
                ok_grant and result or nil

              granted =
                type(created) == "table"
                and #created == offer.amount

              reason =
                granted and nil or result
            end

            if not granted then
              fragshop_refund(
                pid,
                cost
              )

              if reason == "already_unlocked"
                or reason == "already_owned"
              then
                return
                  owned_msg,
                  "Anything else?"
              end

              return
                "Couldn't complete that purchase ("
                .. tostring(reason or "error")
                .. ").",
                "Anything else?"
            end

            fragshop_update_row(
              menu,
              choice_id,
              offer,
              fragshop_is_sold_out(
                pid,
                offer
              )
            )

            if sfx
              and sfx.item_get
            then
              pcall(
                Net.play_sound_for_player,
                pid,
                sfx.item_get
              )
            end

            if offer.type == "chip" then
              return string.format(
                "You bought %s!\n(-%d BF)",
                offer.name,
                cost
              ), "Anything else?"
            end

            if offer.type == "cosmetic" then
              return string.format(
                "You got the %s cosmetic!\n(-%d BF)",
                offer.name,
                cost
              ), "Anything else?"
            end

            local first_pet =
              created and created[1]

            if offer.amount == 1
              and first_pet
              and first_pet.uid
            then
              return string.format(
                "You bought %s!\nPet ID: %s\n(-%d BF)",
                offer.name,
                tostring(first_pet.uid),
                cost
              ), "Anything else?"
            end

            return string.format(
              "You bought %dx %s!\n(-%d BF)",
              offer.amount,
              offer.name,
              cost
            ), "Anything else?"
          end,
        }
      )

      while TalkVertMenu.is_busy
        and TalkVertMenu.is_busy(player_id)
      do
        await(Async.sleep(0.05))
      end

      fragshop_clear_previews(
        player_id
      )

      return dialogue.custom_properties
        and dialogue.custom_properties["Next 1"]
    end)
  end
}


----------------------------------------------------------------
-- Token Vendor Shop (sells Tokens for Moneyz)
-- Dialogue Type: "tokenshop"
--
-- Fixed offers:
--   1 Token  for 20000
--   3 Tokens for 60000
--   5 Tokens for 100000
--   10 Tokens for 200000
--
-- Optional (case-insensitive) custom properties:
--   Shop Title = Token Vendor
--   Not Enough Msg = You don't have enough money.
----------------------------------------------------------------

local TOKEN_SHOP_COLOR = { r = 110, g = 220, b = 255 } -- bright cyan
local TOKEN_OFFERS = {
  { id = "__tok_buy_1__",  qty = 1,  price = 2000  },
  { id = "__tok_buy_3__",  qty = 3,  price = 6000  },
  { id = "__tok_buy_5__",  qty = 5,  price = 10000 },
  { id = "__tok_buy_10__", qty = 10, price = 20000 },
  { id = "__tok_buy_30__", qty = 30, price = 60000 },
  { id = "__tok_buy_50__", qty = 50, price = 100000 },
  { id = "__tok_buy_100__", qty = 100, price = 200000 },
}

eznpcs.add_event{
  name = "tokenshop",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
      local ci = build_ci_props(dialogue)

      -- Ensure token + money helpers exist
      if not ezmemory
        or not ezmemory.get_player_tokens
        or not ezmemory.add_player_tokens
        or not ezmemory.spend_player_money
      then
        await(Async.message_player(
          player_id,
          "Token shop isn't available on this server build.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      local title = tostring(get_ci(ci, "shop title") or "Token Vendor")
      local not_enough_msg = tostring(get_ci(ci, "not enough msg") or "You don't have enough money.")

      while true do
        local cur_tokens = tonumber(ezmemory.get_player_tokens(player_id) or 0) or 0

        local posts = {}

        for _, offer in ipairs(TOKEN_OFFERS) do
          local label = string.format(
            "Buy %d Token%s (%s)",
            offer.qty,
            (offer.qty == 1 and "" or "s"),
            short_money(offer.price)
          )
          local post = helpers.create_bbs_option(label)
          post.id = offer.id
          table.insert(posts, post)
        end

        -- Balance footer option (non-purchasable)
        local bal_post = helpers.create_bbs_option(string.format("Your Tokens: %d", cur_tokens))
        bal_post.id = "__tok_balance__"
        table.insert(posts, bal_post)

        local board = ezmenus.open_menu(
          player_id,
          title,
          TOKEN_SHOP_COLOR,
          posts
        )

        local sel = await(board.selection_once())
        Net.close_bbs(player_id)

        if not sel then break end -- cancel

        if sel ~= "__tok_balance__" then
          local chosen
          for _, offer in ipairs(TOKEN_OFFERS) do
            if sel == offer.id then
              chosen = offer
              break
            end
          end

          if chosen then
            local question = string.format(
              "Buy %d Token%s for %s?",
              chosen.qty,
              (chosen.qty == 1 and "" or "s"),
              short_money(chosen.price)
            )

            local res = await(Async.question_player(player_id, question, mug.texture_path, mug.animation_path))
            local do_buy = (res == 1)

            if do_buy then
              if chosen.price > 0 and not ezmemory.spend_player_money(player_id, chosen.price) then
                await(Async.message_player(player_id, not_enough_msg, mug.texture_path, mug.animation_path))
              else
                ezmemory.add_player_tokens(player_id, chosen.qty)

                if sfx and sfx.item_get then
                  pcall(Net.play_sound_for_player, player_id, sfx.item_get)
                end

                local new_tokens = tonumber(ezmemory.get_player_tokens(player_id) or 0) or 0
                await(Async.message_player(
                  player_id,
                  string.format("You bought %d Token%s!\nTokens: %d", chosen.qty, (chosen.qty == 1 and "" or "s"), new_tokens),
                  mug.texture_path, mug.animation_path
                ))
              end
            end
          end
        end
      end

      return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
    end)
  end
}

----------------------------------------------------------------
-- Token Redeem Shop (spends Tokens to grant rewards)
-- Dialogue Type: "tokenredeem"
--
-- Build offers from (case-insensitive) custom properties:
--   Sell 1   = <id or name>
--   Type 1   = cosmetic | decor | pet | item | card
--   Amount 1 = <int> (default 1)
--   Price 1  = <int tokens>
--
-- For Type=item/card you can optionally provide:
--   Desc 1 / Description 1 = <item description>
--   Key 1 / Key Item 1     = true/false  (creates as key item when true)
--
-- Optional (case-insensitive) custom properties:
--   Shop Title        = Token Redeemer
--   Not Enough Msg    = You don't have enough Tokens.
--   Already Owned Msg = You already own that cosmetic.
--   Currency Label    = Tokens
--   Default Desc      = Redeemed from the Token Shop.
----------------------------------------------------------------

local TOKEN_REDEEM_COLOR = { r = 245, g = 210, b = 70 } -- gold/yellow

local function _short_tokens(n)
  n = math.floor(tonumber(n or 0) or 0)
  return tostring(n)
end

local function _parse_bool(v)
  if v == nil then return false end
  if type(v) == "boolean" then return v end
  local s = string.lower(tostring(v))
  return (s == "true" or s == "1" or s == "yes" or s == "y" or s == "on")
end

eznpcs.add_event{
  name = "tokenredeem",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
      local ci = build_ci_props(dialogue)

      -- Ensure token support exists
      if not ezmemory
        or not ezmemory.get_player_tokens
        or not ezmemory.spend_player_tokens
      then
        await(Async.message_player(
          player_id,
          "Token redeem shop isn't available on this server build.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      local title = tostring(get_ci(ci, "shop title") or "Token Redeemer")
      local not_enough_msg = tostring(get_ci(ci, "not enough msg") or "You don't have enough Tokens.")
      local owned_msg = tostring(get_ci(ci, "already owned msg") or "You already own that cosmetic.")
      local currency_label = tostring(get_ci(ci, "currency label") or "Tokens")
      local default_desc = tostring(get_ci(ci, "default desc") or "Redeemed from the Token Shop.")

      -- Build offers from Sell N / Type N / Amount N / Price N (+ optional Desc/Key)
      local offers = {}
      local i = 1
      while true do
        local sell = get_ci(ci, "sell " .. i)
        if not sell then break end

        local typ = tostring(get_ci(ci, "type " .. i) or "decor")
        typ = string.lower(typ)
        if typ == "pet" then typ = "decor" end
        if typ == "cosmetics" then typ = "cosmetic" end
        if typ == "cards" or typ == "card" then typ = "item" end
        if typ == "items" then typ = "item" end

        local amount = math.floor(tonumber(get_ci(ci, "amount " .. i) or 1) or 1)
        if amount < 1 then amount = 1 end

        local price = math.floor(tonumber(get_ci(ci, "price " .. i) or get_ci(ci, "cost " .. i) or 0) or 0)
        if price < 0 then price = 0 end

        local id = tostring(sell)
        local pretty =
          (typ == "cosmetic" and cosmetics and cosmetics.get_name_for_id and cosmetics.get_name_for_id(id))
          or (typ == "decor" and oncehub_catalog_name_for(id))
          or id

        local desc = get_ci(ci, "desc " .. i) or get_ci(ci, "description " .. i)
        local key_item = _parse_bool(get_ci(ci, "key " .. i) or get_ci(ci, "key item " .. i))

        table.insert(offers, {
          id = id,
          type = typ,
          amount = amount,
          price = price,
          name = pretty,
          desc = desc,
          key_item = key_item,
        })

        i = i + 1
      end

      if #offers == 0 then
        await(Async.message_player(
          player_id,
          "Sorry, I'm not redeeming anything right now.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      while true do
        local cur_tokens = tonumber(ezmemory.get_player_tokens(player_id) or 0) or 0

        local posts = {}
        local items = {}

        for _, offer in ipairs(offers) do
          local label
          if offer.type == "cosmetic" then
            local owned = cosmetics and cosmetics.has_cosmetic and cosmetics.has_cosmetic(player_id, offer.id)
            label = owned
              and string.format("%s (%s %s, Owned)", offer.name, _short_tokens(offer.price), currency_label)
              or  string.format("%s (%s %s)",        offer.name, _short_tokens(offer.price), currency_label)
          elseif offer.type == "decor" then
            local owned = oncehub_count_owned(player_id, offer.id)
            if offer.amount ~= 1 then
              label = string.format("%s x%d (%s %s) [Owned:%d]", offer.name, offer.amount, _short_tokens(offer.price), currency_label, owned)
            else
              label = string.format("%s (%s %s) [Owned:%d]", offer.name, _short_tokens(offer.price), currency_label, owned)
            end
          else -- item
            if offer.amount ~= 1 then
              label = string.format("%s x%d (%s %s)", offer.name, offer.amount, _short_tokens(offer.price), currency_label)
            else
              label = string.format("%s (%s %s)", offer.name, _short_tokens(offer.price), currency_label)
            end
          end

          local post = helpers.create_bbs_option(label)
          table.insert(posts, post)
          items[#posts] = offer
        end

        -- Add a "balance" footer option (non-purchasable)
        local bal_post = helpers.create_bbs_option(string.format("Your %s: %d", currency_label, cur_tokens))
        bal_post.id = "__tok_balance__"
        table.insert(posts, bal_post)

        local board = ezmenus.open_menu(
          player_id,
          title,
          TOKEN_REDEEM_COLOR,
          posts
        )

        local sel = await(board.selection_once())
        Net.close_bbs(player_id)

        if not sel then break end -- cancel

        if sel == "__tok_balance__" then
          -- footer; just reopen
        else
          -- Resolve choice
          local chosen
          for idx, post in ipairs(posts) do
            local pid = post.id or post.title or ""
            if sel == pid then
              chosen = items[idx]
              break
            end
          end

          if chosen then
            -- Cosmetic owned check
            if chosen.type == "cosmetic"
              and cosmetics
              and cosmetics.has_cosmetic
              and cosmetics.has_cosmetic(player_id, chosen.id)
            then
              await(Async.message_player(player_id, owned_msg, mug.texture_path, mug.animation_path))
            else
              -- Preview for cosmetics (optional)
              if chosen.type == "cosmetic" and cosmetics and cosmetics.preview_for_shop then
                cosmetics.preview_for_shop(player_id, chosen.id)
              end

              -- Confirmation
              local question
              if (chosen.type ~= "cosmetic") and chosen.amount ~= 1 then
                question = string.format("Redeem %s x%d for %s %s?", chosen.name, chosen.amount, _short_tokens(chosen.price), currency_label)
              else
                question = string.format("Redeem %s for %s %s?", chosen.name, _short_tokens(chosen.price), currency_label)
              end

              local res = await(Async.question_player(player_id, question, mug.texture_path, mug.animation_path))
              local do_buy = (res == 1)

              if cosmetics and cosmetics.clear_shop_previews then
                cosmetics.clear_shop_previews(player_id)
              end

              if do_buy then
                if chosen.price > 0 and not ezmemory.spend_player_tokens(player_id, chosen.price) then
                  await(Async.message_player(player_id, not_enough_msg, mug.texture_path, mug.animation_path))
                else
                  local reward_msg

                  if chosen.type == "cosmetic" then
                    if cosmetics and cosmetics.unlock_for_player then
                      local ok, reason = cosmetics.unlock_for_player(player_id, chosen.id)
                      if ok then
                        reward_msg = "You got the " .. chosen.name .. " cosmetic!"
                      else
                        reward_msg = "Couldn't unlock that cosmetic (" .. tostring(reason or "error") .. ")."
                      end
                    else
                      reward_msg = "Cosmetics system isn't installed on this server."
                    end
                  elseif chosen.type == "decor" then
                    oncehub_add_owned(player_id, chosen.id, chosen.amount)
                    if chosen.amount ~= 1 then
                      reward_msg = string.format("You got %dx %s!", chosen.amount, chosen.name)
                    else
                      reward_msg = "You got " .. chosen.name .. "!"
                    end
                  else -- item
                    if ezmemory.get_or_create_item and ezmemory.give_player_item then
                      local desc = tostring(chosen.desc or default_desc)
                      ezmemory.get_or_create_item(chosen.id, desc, chosen.key_item) -- ensure it exists
                      ezmemory.give_player_item(player_id, chosen.id, chosen.amount) -- pass NAME (not id)
                      if chosen.amount ~= 1 then
                        reward_msg = string.format("You got %dx %s!", chosen.amount, chosen.name)
                      else
                        reward_msg = "You got " .. chosen.name .. "!"
                      end
                    else
                      reward_msg = "Item system isn't installed on this server build."
                    end
                  end

                  if sfx and sfx.item_get then
                    pcall(Net.play_sound_for_player, player_id, sfx.item_get)
                  end

                  local new_tokens = tonumber(ezmemory.get_player_tokens(player_id) or 0) or 0
                  reward_msg = (reward_msg or "Redeem complete.") .. ("\n%s: %d"):format(currency_label, new_tokens)
                  await(Async.message_player(player_id, reward_msg, mug.texture_path, mug.animation_path))
                end
              end
            end
          end
        end
      end

      return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
    end)
  end
}

eznpcs.add_event{
  name = "decorclear",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)

      if not cosmetics or not cosmetics.clear_all_for_player then
        await(Async.message_player(player_id,
          "Cosmetics system is not available.",
          mug.texture_path, mug.animation_path))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      local prompt = (dialogue.custom_properties and dialogue.custom_properties["Prompt"])
                  or "Clear ALL your cosmetics and unequip them?"

      local confirm = true
      if Async.question_player then
        local res = await(Async.question_player(
          player_id,
          prompt,
          mug.texture_path,
          mug.animation_path
        ))
        confirm = (res == 1) -- 1 = Yes, anything else = No/Cancel
      end

      if not confirm then
        await(Async.message_player(player_id,
          "Okay, leaving your cosmetics as-is.",
          mug.texture_path, mug.animation_path))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      cosmetics.clear_all_for_player(player_id)

      await(Async.message_player(player_id,
        "All cosmetics cleared for this account.\nYou can re-purchase them in the shop.",
        mug.texture_path, mug.animation_path))

      return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
    end)
  end
}

eznpcs.add_event{
  name = "cosmeticgift",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)

      -- Make sure the cosmetics system is available
      if not cosmetics or not cosmetics.unlock_for_player then
        await(Async.message_player(
          player_id,
          "Cosmetics system is not available right now.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      -- Case-insensitive props
      local ci = build_ci_props(dialogue)

      -- Read cosmetic id from custom properties:
      -- Accepts "CosmeticID", "Cosmetic Id", or "Cosmetic"
      local cosmetic_id = get_ci(ci, "cosmetic id")
                        or get_ci(ci, "cosmeticid")
                        or get_ci(ci, "cosmetic")

      if not cosmetic_id or cosmetic_id == "" then
        await(Async.message_player(
          player_id,
          "This NPC isn't configured with a cosmetic reward.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      cosmetic_id = tostring(cosmetic_id)

      -- Nice display name (falls back to id if unknown)
      local name = cosmetics.get_name_for_id
                and cosmetics.get_name_for_id(cosmetic_id)
                or cosmetic_id

      -- Optional flavor text before the gift (from a "Prompt" custom property)
      local prompt = dialogue.custom_properties["Prompt"]
      if prompt and prompt ~= "" then
        await(Async.message_player(
          player_id,
          prompt,
          mug.texture_path, mug.animation_path
        ))
      end

      -- Already have it? Just say so and bail.
      if cosmetics.has_cosmetic and cosmetics.has_cosmetic(player_id, cosmetic_id) then
        await(Async.message_player(
          player_id,
          "You already have the " .. name .. " cosmetic.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      -- Try to unlock it
      local ok, reason = cosmetics.unlock_for_player(player_id, cosmetic_id)
      if ok then
        if sfx and sfx.item_get then
          Net.play_sound_for_player(player_id, sfx.item_get)
        end
        await(Async.message_player(
          player_id,
          "You got the " .. name .. " cosmetic!",
          mug.texture_path, mug.animation_path
        ))
      else
        await(Async.message_player(
          player_id,
          "Couldn't give you that cosmetic (" .. tostring(reason or "error") .. ").",
          mug.texture_path, mug.animation_path
        ))
      end

      return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
    end)
  end
}

eznpcs.add_event{
  name = "SecretPath",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local area_id = Net.get_player_area(player_id)
      if not area_id then
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      reveal_dialogue_path(area_id, player_id, dialogue)

      -- Continue to whatever the dialogue's "Next 1" is, like other events.
      if dialogue.custom_properties then
        return dialogue.custom_properties["Next 1"]
      end
      return nil
    end)
  end
}

-- Duel rules menu (BBS selector -> jump to another dialogue)
local DUEL_RULES_COLOR = { r = 110, g = 220, b = 255 } -- pick any color you want

eznpcs.add_event{
  name = "Duel Rules Menu",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      -- (optional) Mug, if you want to show message_player prompts before/after
      -- local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)

      -- Case-insensitive props (you already have these helpers in this file)
      local ci = build_ci_props(dialogue)

      -- Accept both "Monster Exp" and "Monsters Exp", etc.
      local monsters_next = get_ci(ci, "monsters exp") or get_ci(ci, "monster exp")
      local spells_next   = get_ci(ci, "spells exp")  or get_ci(ci, "spell exp")
      local battles_next  = get_ci(ci, "battles exp") or get_ci(ci, "battle exp")

      -- Where to go if player cancels / exits
      local on_cancel = get_ci(ci, "on cancel") or (dialogue.custom_properties and dialogue.custom_properties["Next 1"])

      -- Build menu posts with stable IDs
      local posts = {}

      local p1 = helpers.create_bbs_option("Monsters")
      p1.id = "__duel_rules_monsters__"
      table.insert(posts, p1)

      local p2 = helpers.create_bbs_option("Spells")
      p2.id = "__duel_rules_spells__"
      table.insert(posts, p2)

      local p3 = helpers.create_bbs_option("Battles")
      p3.id = "__duel_rules_battles__"
      table.insert(posts, p3)

      local p4 = helpers.create_bbs_option("Exit")
      p4.id = "__duel_rules_exit__"
      table.insert(posts, p4)

      local title = get_ci(ci, "board title") or "Duel Rules"

      local board = ezmenus.open_menu(player_id, title, DUEL_RULES_COLOR, posts)
      local sel = await(board.selection_once())
      Net.close_bbs(player_id)

      if not sel or sel == "__duel_rules_exit__" then
        return on_cancel
      end

      if sel == "__duel_rules_monsters__" then
        return monsters_next or on_cancel
      elseif sel == "__duel_rules_spells__" then
        return spells_next or on_cancel
      elseif sel == "__duel_rules_battles__" then
        return battles_next or on_cancel
      end

      return on_cancel
    end)
  end
}

local echo_boss = {
    name="echo_boss",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/events.zip",
    enemies={
        {name="FireManPoN",rank=3},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,0,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local EchoProgram_Battle = {
    name="EchoProgram Battle",
    action=function(npc, player_id, dialogue, relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, echo_boss))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(EchoProgram_Battle)

local EchoProgram_GameOver = {
    name="EchoProgram GameOver",
    action=function(npc, player_id, dialogue, relay_object)
        return async(function()
            -- Reset quest progress then kick (game over)
            await(ezquests.quest_event(player_id, "EchoProgram", "reset"))
            await(Async.message_player(player_id, "GAME OVER"))
            Net.kick_player(player_id, "Game Over", false)
            return nil
        end)
    end
}
eznpcs.add_event(EchoProgram_GameOver)

----------------------------------------------------------------
-- BBS Item Shop (sells normal items for Moneyz)
-- Dialogue Type: "itemshopbbs"
--
-- Configure per-NPC via custom properties:
--   Item 1   = <object id>
--   Price 1  = <money price override, optional>
--   Item 2   = <object id>
--   Price 2  = <money price override, optional>
--   ...
--
-- Optional:
--   Shop Title      = Item Shop
--   Not Enough Msg  = You don't have enough money.
--
-- Notes:
-- - Item N should point to a normal item object in the same area.
-- - The object's own Name/Amount/Description/Type are used for granting.
-- - Price N overrides the object's own Price property if provided.
----------------------------------------------------------------

local ITEM_SHOP_BBS_COLOR = { r = 245, g = 210, b = 70 }

eznpcs.add_event{
  name = "itemshopbbs",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local area_id = Net.get_player_area(player_id)
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
      local ci  = build_ci_props(dialogue)

      local title = tostring(get_ci(ci, "shop title") or "Item Shop")
      local not_enough_msg = tostring(get_ci(ci, "not enough msg") or "You don't have enough money.")

      -- Build offers from Item N (+ optional Price N override)
      local offers = {}
      local i = 1
      while true do
        local raw_item_id = get_ci(ci, "item " .. i)
        if not raw_item_id then break end

        local object_id = tonumber(raw_item_id)
        if object_id then
          local info = helpers.read_item_information(area_id, object_id)

          -- Only allow normal items / keyitems here
          if info and (info.type == "item" or info.type == "keyitem") then
            local price = tonumber(get_ci(ci, "price " .. i) or get_ci(ci, "cost " .. i) or info.price or 0) or 0
            if price < 0 then price = 0 end

            table.insert(offers, {
              object_id = object_id,
              unit_price = price,
              info = info,
            })
          end
        end

        i = i + 1
      end

      if #offers == 0 then
        await(Async.message_player(
          player_id,
          "Sorry, I'm not selling any items right now.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      while true do
        local posts = {}
        local chosen_by_post_id = {}

        for idx, offer in ipairs(offers) do
          local base_amount = math.max(1, math.floor(tonumber(offer.info.amount or 1) or 1))
          local name = tostring(offer.info.name or ("Item " .. idx))

          local label
          if base_amount > 1 then
            label = string.format("%s x%d (%s)", name, base_amount, short_money(offer.unit_price))
          else
            label = string.format("%s (%s)", name, short_money(offer.unit_price))
          end

          local post = helpers.create_bbs_option(label)
          post.id = "__itemshopbbs:" .. tostring(idx)
          table.insert(posts, post)
          chosen_by_post_id[post.id] = offer
        end

        local board = ezmenus.open_menu(player_id, title, ITEM_SHOP_BBS_COLOR, posts)
        local sel = await(board.selection_once())
        Net.close_bbs(player_id)

        if not sel then break end

        local chosen = chosen_by_post_id[tostring(sel)]
        if not chosen then break end

        local opt1 = string.format("Buy 1  (%s)", short_money(chosen.unit_price * 1))
        local opt2 = string.format("Buy 3  (%s)", short_money(chosen.unit_price * 3))
        local opt3 = "Cancel"

        local res = await(Async.quiz_player(
          player_id,
          opt1,
          opt2,
          opt3,
          mug.texture_path,
          mug.animation_path
        ))

        -- 0 = Buy 1, 1 = Buy 3, 2/nil = Cancel
        local qty = (res == 0 and 1) or (res == 1 and 3) or nil
        if not qty then
          goto continue
        end

        local total_cost = chosen.unit_price * qty
        if total_cost > 0 and not ezmemory.spend_player_money(player_id, total_cost) then
          await(Async.message_player(
            player_id,
            not_enough_msg,
            mug.texture_path,
            mug.animation_path
          ))
          goto continue
        end

        local base_amount = math.max(1, math.floor(tonumber(chosen.info.amount or 1) or 1))
        local grant_info = {
          name = chosen.info.name,
          description = chosen.info.description,
          type = chosen.info.type,
          amount = base_amount * qty,
          price = chosen.info.price,
        }

        await(ezmemory.give_item_with_optional_notify(
          player_id,
          area_id,
          chosen.object_id,
          grant_info,
          false
        ))

        if sfx and sfx.item_get then
          pcall(Net.play_sound_for_player, player_id, sfx.item_get)
        end

        await(Async.message_player(
          player_id,
          string.format("Purchased x%d %s.", qty, tostring(chosen.info.name or "item")),
          mug.texture_path,
          mug.animation_path
        ))

        ::continue::
      end

      return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
    end)
  end
}

eznpcs.add_event({
  name = "songshop",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)

      local price = tonumber((dialogue.custom_properties and dialogue.custom_properties["Song Price"]) or "") or 200000
      local do_preview = tostring((dialogue.custom_properties and dialogue.custom_properties["Preview"]) or "true") ~= "false"
      local title = tostring((dialogue.custom_properties and dialogue.custom_properties["Shop Title"]) or "Song Shop")

      local songs = _list_jukebox_songs()
      if #songs == 0 then
        await(Async.message_player(player_id, "No songs found in /server/assets/jukebox.", mug.texture_path, mug.animation_path))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      local secret = helpers.get_safe_player_secret(player_id)

      while true do
        local posts, index = {}, {}

        for _, file in ipairs(songs) do
          local base = file:gsub("%.ogg$", "")
          local owned = _songshop_is_owned(secret, file)
          local label = owned and ("(Owned)" .. base) or base
          table.insert(posts, helpers.create_bbs_option(label))
          index[#posts] = { file = file, base = base, owned = owned }
        end

        local board = ezmenus.open_menu(player_id, title, COSMETIC_SHOP_COLOR, posts)
        local sel = await(board.selection_once())
        Net.close_bbs(player_id)

        if not sel then break end

        local chosen
        for i, post in ipairs(posts) do
          local pid = post.id or post.title or ""
          if sel == pid then chosen = index[i]; break end
        end
        if not chosen then break end

        if chosen.owned then
          await(Async.message_player(player_id, "Are you dense? You already bought that.", mug.texture_path, mug.animation_path))
          goto continue
        end

        if do_preview then
          pcall(Net.set_song_for_player, player_id, JUKEBOX_SONG_PREFIX .. chosen.file)
        end

        local confirm = await(Async.question_player(
          player_id,
          ("Buy \"%s\" for %sz?"):format(chosen.base, tostring(price)),
          mug.texture_path, mug.animation_path
        ))

        if do_preview then
          pcall(Net.stop_song_for_player, player_id)
        end

        if confirm == 1 then
          if not ezmemory.spend_player_money(player_id, price) then
            await(Async.message_player(player_id, "You can't afford that go get a job or something", mug.texture_path, mug.animation_path))
            goto continue
          end

          _songshop_set_owned(secret, chosen.file)
          if sfx and sfx.item_get then pcall(Net.play_sound_for_player, player_id, sfx.item_get) end
          await(Async.message_player(player_id, "Well at least you're smart enough to purchase that.", mug.texture_path, mug.animation_path))
        end

        ::continue::
      end

      return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
    end)
  end
})

eznpcs.add_event{
  name = "PetTrainer",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)

      if not Pets then
        await(Async.message_player(player_id, "The training system isn't available right now.", mug.texture_path, mug.animation_path))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      local training = Pets.get_training_info(player_id)

      if training then
        local ends_at = tonumber(training.ends_at or 0) or 0
        local now     = os.time()
        local name    = tostring(training.display_name or "Your pet")

        if now >= ends_at then
          local res = await(Async.question_player(
            player_id,
            name .. " has finished training! Ready to take them back?",
            mug.texture_path, mug.animation_path
          ))
          if res == 1 then
            local ok, msg = Pets.claim_trained_pet(player_id)
            await(Async.message_player(player_id, msg, mug.texture_path, mug.animation_path))
          else
            await(Async.message_player(player_id, "Alright, I'll hold onto them a little longer.", mug.texture_path, mug.animation_path))
          end
        else
          local mins = math.ceil((ends_at - now) / 60)
          await(Async.message_player(
            player_id,
            name .. " is still in training! " .. mins .. " minute(s) remaining.",
            mug.texture_path, mug.animation_path
          ))
        end

        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      local info = Pets.get_armed_pet_info(player_id)

      if not info then
        await(Async.message_player(
          player_id,
          "Bring a companion pet with you and I'll put them through a training session!",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      if info.summoned then
        await(Async.message_player(
          player_id,
          "Call your companion back before dropping them off for training.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      local cp           = dialogue.custom_properties or {}
      local cost         = math.max(0,  math.floor(tonumber(cp["Cost"])     or 90000))
      local duration_min = math.max(1,  math.floor(tonumber(cp["Duration"]) or 60))
      local cooldown_min = math.max(0,  math.floor(tonumber(cp["Cooldown"]) or 60))
      local duration_sec = duration_min * 60
      local cooldown_sec = cooldown_min * 60
      local xp           = Pets.TRAINING_XP or 75

      local pet_name = tostring(info.display_name or "your pet")

      local res = await(Async.question_player(
        player_id,
        ("Send " .. pet_name .. " for a " .. duration_min .. "-min training session for " .. cost .. "z? (+" .. xp .. " XP on return)"),
        mug.texture_path, mug.animation_path
      ))

      if res == 1 then
        local ok, msg = Pets.start_training(player_id, cost, duration_sec, cooldown_sec)
        await(Async.message_player(player_id, msg, mug.texture_path, mug.animation_path))
      else
        await(Async.message_player(player_id, "Please come again!", mug.texture_path, mug.animation_path))
      end

      return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
    end)
  end
}

eznpcs.add_event{
  name = "UnlockWhitelistPackage",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
      local ci = build_ci_props(dialogue)

      local package_id = get_ci(ci, "package id") or get_ci(ci, "packageid")
      local reward_name = tostring(get_ci(ci, "reward name") or get_ci(ci, "reward") or package_id or "that unlock")
      local already_msg = tostring(get_ci(ci, "already msg") or ("You already unlocked " .. reward_name .. "."))
      local unlock_msg = tostring(get_ci(ci, "unlock msg") or ("You can now use " .. reward_name .. "!"))

      if not package_id or package_id == "" then
        await(Async.message_player(
          player_id,
          "This NPC is missing a Package ID.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      if whitelist.player_has_package_unlocked(player_id, package_id) then
        await(Async.message_player(
          player_id,
          already_msg,
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      local ok, reason = whitelist.unlock_package(player_id, package_id)

      if ok then
        if sfx and sfx.item_get then
          Net.play_sound_for_player(player_id, sfx.item_get)
        end

        await(Async.message_player(
          player_id,
          unlock_msg,
          mug.texture_path, mug.animation_path
        ))
      else
        local fail_msg = (reason == "already_unlocked") and already_msg
          or "I couldn't unlock that right now."

        await(Async.message_player(
          player_id,
          fail_msg,
          mug.texture_path, mug.animation_path
        ))
      end

      return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
    end)
  end
}

eznpcs.add_event({
  name = "chipshop",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
      local ci = build_ci_props(dialogue)

      local title = tostring(get_ci(ci, "shop title") or "Chip Shop")
      local currency = string.lower(tostring(
        get_ci(ci, "currency")
        or get_ci(ci, "currency type")
        or get_ci(ci, "seller type")
        or "money"
      ))

      if currency == "bugfrag" or currency == "bugfrags" or currency == "frags" then
        currency = "bugfrags"
      else
        currency = "money"
      end

      local not_enough_msg = tostring(
        get_ci(ci, "not enough msg")
        or ((currency == "bugfrags") and "You don't have enough BugFrags." or "You don't have enough money.")
      )
      local owned_msg = tostring(
        get_ci(ci, "already owned msg")
        or "You already bought that chip."
      )

      local sold_out_msg = tostring(
        get_ci(ci, "sold out msg")
        or "That item is SOLD OUT."
      )

      -- Optional HPMem stock.
      -- Each numbered HPMem is purchased once per player, per shop.
      local hpmem_limit = math.max(0, math.floor(tonumber(
        get_ci(ci, "hpmem limit")
        or 0
      ) or 0))

      -- A stable Shop ID prevents stock from resetting if the Tiled
      -- dialogue object's numeric ID changes later.
      local hpmem_shop_key = tostring(
        get_ci(ci, "hpmem shop id")
        or get_ci(ci, "shop id")
        or (
          tostring(Net.get_player_area(player_id) or "unknown")
          .. ":"
          .. tostring(dialogue.id or dialogue.name or "chipshop")
        )
      )

      local hpmem_slots = {}
      local hpmem_player_secret = nil

      if hpmem_limit > 0 then
        hpmem_player_secret = helpers.get_safe_player_secret(player_id)

        local pmem = ezmemory.get_player_memory(hpmem_player_secret) or {}

        pmem.chipshop_hpmem_v1 =
          pmem.chipshop_hpmem_v1 or {}

        pmem.chipshop_hpmem_v1[hpmem_shop_key] =
          pmem.chipshop_hpmem_v1[hpmem_shop_key] or {}

        hpmem_slots =
          pmem.chipshop_hpmem_v1[hpmem_shop_key]
      end

      local function hpmem_slot_is_sold(slot)
        return hpmem_slots[tostring(slot)] == true
      end

      local function hpmem_price_for_slot(slot)
        local raw_price =
          get_ci(ci, "hpmem price " .. tostring(slot))
          or get_ci(ci, "hpmem cost " .. tostring(slot))

        if raw_price == nil or tostring(raw_price) == "" then
          return nil
        end

        return math.max(
          0,
          math.floor(tonumber(raw_price) or 0)
        )
      end

      local function find_next_hpmem_slot()
        for slot = 1, hpmem_limit do
          if not hpmem_slot_is_sold(slot) then
            local price = hpmem_price_for_slot(slot)

            if price == nil then
              print(string.format(
                "[chipshop] %s is missing HPMem Price %d.",
                hpmem_shop_key,
                slot
              ))

              return nil, nil
            end

            return slot, price
          end
        end

        return nil, nil
      end

      local function mark_hpmem_slot_sold(slot)
        if not slot then
          return
        end

        hpmem_slots[tostring(slot)] = true

        if hpmem_player_secret and ezmemory.save_player_memory then
          ezmemory.save_player_memory(hpmem_player_secret)
        end
      end

      local function refresh_hpmem_offer(offer)
        local next_slot, next_price = find_next_hpmem_slot()

        if next_slot and next_price ~= nil then
          offer.slot = next_slot
          offer.price = next_price
          offer.sold_out = false
        else
          offer.slot = nil
          offer.sold_out = true

          -- Keep the final HPMem price visible beside SOLD OUT.
          if hpmem_limit > 0 then
            offer.price =
              hpmem_price_for_slot(hpmem_limit)
              or offer.price
              or 0
          end
        end
      end

      local offers = {}

      -- HPMem is one evolving offer and always appears first.
      if hpmem_limit > 0 then
        local hpmem_offer = {
          kind = "hpmem",
          name = tostring(
            get_ci(ci, "hpmem name")
            or "HPMem"
          ),
          price = 0,
          slot = nil,
          sold_out = false,
        }

        refresh_hpmem_offer(hpmem_offer)
        table.insert(offers, hpmem_offer)
      end
      local i = 1
      while true do
        local sell = get_ci(ci, "sell " .. i)
        if not sell then break end

        local price = math.max(0, math.floor(tonumber(
          get_ci(ci, "price " .. i)
          or get_ci(ci, "cost " .. i)
          or 0
        ) or 0))

        local code = tostring(get_ci(ci, "code " .. i) or "*")
        local card_def = whitelist.get_card_def(sell)

        if card_def then
          local display_name = tostring(
            get_ci(ci, "name " .. i)
            or get_ci(ci, "reward name " .. i)
            or sell
          )

          table.insert(offers, {
            kind = "chip",
            lookup = tostring(sell),
            package_id = card_def.package_id,
            price = price,
            code = code,
            name = display_name,
            prop_index = i,
          })
        end

        i = i + 1
      end

      local function offer_is_sold_out(pid, offer)
        if not offer then
          return true
        end

        if offer.kind == "hpmem" then
          return offer.sold_out == true
            or offer.slot == nil
        end

        return whitelist.player_has_card_unlocked(
          pid,
          offer.package_id
        )
      end

      if #offers == 0 then
        await(Async.message_player(
          player_id,
          "Sorry, I'm not selling anything right now.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

--=====================================================
-- NEW: net-games powered shop UI (PromptVertical)
-- (falls back to existing BBS shop if net-games missing)
--=====================================================
local ok_menu, TalkVertMenu_or_err = pcall(require, "scripts/net-games/npcs/talk_vert_menu")
if ok_menu then
  local TalkVertMenu = TalkVertMenu_or_err
  local TalkPresets = require("scripts/net-games/npcs/talk_presets")

  -- If selling for bugfrags, ensure API exists (mirrors fragshop’s safety style)
  if currency == "bugfrags" and (not ezmemory.get_player_fragments or not ezmemory.spend_player_fragments) then
    await(Async.message_player(
      player_id,
      "BugFrag chip shop isn't available on this server build.",
      mug.texture_path, mug.animation_path
    ))
    return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
  end

  -- Build a PROG-style mugshot, but swap texture/anim to match eznpcs Asset Name/Mugshot.
  local ez_mug = mug
  local prog_mug = helpers.deep_copy(TalkPresets.mugs.prog or { enabled = true })
  prog_mug.texture_path = ez_mug.texture_path
  prog_mug.anim_path = ez_mug.animation_path
  prog_mug.sprite_id = nil

  local function normalize_preview_path(p)
    p = tostring(p or "")
    if p == "" then return nil end

    -- Add extension if missing
    if not p:match("%.[%w]+$") then
      p = p .. ".png"
    end

    -- Allow full /server/... paths, otherwise treat as relative to /server/assets/
    if p:sub(1, 7) == "/server/" then
      return p
    end
    if p:sub(1, 1) == "/" then
      return p -- absolute (leave it)
    end
    return "/server/assets/" .. p
  end

  local preview_dir = tostring(get_ci(ci, "preview dir") or "")
  local preview_ext = tostring(get_ci(ci, "preview ext") or ".png")
  if preview_ext ~= "" and preview_ext:sub(1,1) ~= "." then
    preview_ext = "." .. preview_ext
  end
  local preview_template = tostring(get_ci(ci, "preview template") or "")

  local DEFAULT_ICON = "/server/assets/net-games/ui/card_shop_item.png"

  local options = {}
  local by_choice_id = {}     -- id -> offer
  local opt_ref_by_id = {}    -- id -> option table (so we can update label to “Owned” after purchase)
  local icon_by_id = {}       -- id -> texture path

  for idx, offer in ipairs(offers) do
    local id = tostring(idx)
    by_choice_id[id] = offer

    local sold_out = offer_is_sold_out(player_id, offer)
    local display_name = sold_out and "SOLD OUT" or offer.name

    options[#options+1] = {
      id = id,
      text = display_name,
      shop_name = display_name,

      -- Keep the original price visible even after the item sells out.
      shop_price = tonumber(offer.price) or 0,
    }

    opt_ref_by_id[id] = options[#options]

    local p = nil

    if offer.kind == "hpmem" then
      -- HPMems use the generic shop icon unless one of these
      -- optional properties is provided.
      p = get_ci(
            ci,
            "hpmem preview " .. tostring(offer.slot)
          )
        or get_ci(
            ci,
            "hpmem icon " .. tostring(offer.slot)
          )
        or get_ci(ci, "hpmem preview")
        or get_ci(ci, "hpmem icon")
    else
      p = get_ci(
            ci,
            "preview " .. tostring(offer.prop_index or idx)
          )
        or get_ci(
            ci,
            "icon " .. tostring(offer.prop_index or idx)
          )

      if (not p or p == "") and preview_template ~= "" then
        p = preview_template
          :gsub("{id}", tostring(offer.lookup))
          :gsub("{sell}", tostring(offer.lookup))
          :gsub("{code}", tostring(offer.code or "*"))
      end

      if (not p or p == "") and preview_dir ~= "" then
        local dir = preview_dir

        if dir:sub(-1) ~= "/" then
          dir = dir .. "/"
        end

        p = dir .. tostring(offer.lookup) .. preview_ext
      end
    end

    p = normalize_preview_path(p)

    -- Do not attempt to send a nonexistent preview asset.
    if p and Net and Net.has_asset then
      local ok, exists = pcall(Net.has_asset, p)

      if ok and exists == false then
        p = nil
      end
    end

    icon_by_id[id] = p or DEFAULT_ICON
  end

  options[#options+1] = { id = "exit", text = "Exit" }
  local exit_index = #options

  -- Pre-provide icons so first-open isn’t blank
  if Net and Net.provide_asset_for_player then
    local seen = {}
    for _, path in pairs(icon_by_id) do
      if path and not seen[path] then
        seen[path] = true
        pcall(Net.provide_asset_for_player, player_id, path)
      end
    end
  end

  -- Slight delay helps first-time icon render on fresh login (same idea as your fishing preload)
  await(Async.sleep(0.05))

  local layout = TalkPresets.get_vert_menu_layout("prog_prompt_shop") or {}
  layout.monies_label_text = (currency == "bugfrags") and "FRAGS" or "MONIES"

  local talk_cfg = {
    preset = "prog_prompt",
    area_id = Net.get_player_area(player_id),
    object = "chipshop_" .. tostring(dialogue.id or "shop"),
    ui = {
      mugshot = prog_mug,
      typing_speed = 9999,
    }
  }

  local function get_balance(pid)
    if currency == "bugfrags" then
      return tonumber(ezmemory.get_player_fragments(pid) or 0) or 0
    end
    return tonumber(Net.get_player_money(pid) or 0) or 0
  end

  -- Make sure input is locked so net-games virtual_input works
  if Net.lock_player_input then
    pcall(Net.lock_player_input, player_id)
  end

  local assets = {
    menu_bg       = "/server/assets/net-games/ui/prompt_vert_menu_shop_an.png",
    menu_bg_anim  = "/server/assets/net-games/ui/prompt_vert_menu_an.animation",
    menu_bg_frame = "/server/assets/net-games/ui/prompt_vert_menu_shop_an_frame.png",
    highlight     = "/server/assets/net-games/ui/highlight_shop.png",
  }

  TalkVertMenu.open(player_id, title, talk_cfg, {
    intro_text = "What would you like?",
    options = options,
    exit_index = exit_index,
    layout = layout,
    assets = assets,

    monies_amount_fn = function(pid)
      -- NOTE: no "$" / "M" suffix; your prompt_vertical row formatter does k/m already
      return tostring(get_balance(pid))
    end,

    shop_item_texture_fn = function(choice)
      if not choice or not choice.id then return DEFAULT_ICON end
      return icon_by_id[tostring(choice.id)] or DEFAULT_ICON
    end,

    flow = {
      keep_menu_open = true,
      after_text = "Anything else?",
      exit_goodbye_text = "Come again!",

      confirm = {
        enabled = true,
        skip_ids = { exit = true },
        text_fn = function(pid, choice_id)
          local offer = by_choice_id[tostring(choice_id)]

          if not offer then
            return "Buy this?"
          end

          if offer_is_sold_out(pid, offer) then
            return sold_out_msg
          end

          local have = get_balance(pid)
          local unit = (currency == "bugfrags") and " BF" or "$"
          return string.format(
            "Buy %s for %d%s?\nYou have %d%s",
            tostring(offer.name),
            tonumber(offer.price) or 0,
            unit,
            have,
            unit
          )
        end,
      },

      post_select = { enabled = true, skip_ids = { exit = true } },
    },

    on_confirm_yes = function(pid, choice_id, _choice_text, menu)
      local offer = by_choice_id[tostring(choice_id)]

      if not offer then
        return "Huh? That item is gone.", "Anything else?"
      end

      if offer_is_sold_out(pid, offer) then
        local message = sold_out_msg

        if offer.kind == "chip" then
          message = owned_msg
        end

        return message, "Anything else?"
      end

      local cost = tonumber(offer.price) or 0

      if cost < 0 then
        cost = 0
      end

      local paid = true

      if cost > 0 then
        if currency == "bugfrags" then
          paid = ezmemory.spend_player_fragments(pid, cost)
        else
          paid = ezmemory.spend_player_money(pid, cost)
        end
      end

      if not paid then
        return not_enough_msg, "Anything else?"
      end

      if offer.kind == "hpmem" then
        local old_total = tonumber(
          ezmemory.count_player_item(pid, "HPMem") or 0
        ) or 0

        local ok_give, new_total = pcall(
          ezmemory.give_player_item,
          pid,
          "HPMem",
          1
        )

        new_total = tonumber(new_total or 0) or 0

        if not ok_give or new_total <= old_total then
          -- Refund the purchase if the HPMem could not be given.
          if cost > 0 then
            if currency == "bugfrags" then
              ezmemory.spend_player_fragments(pid, -cost)
            else
              ezmemory.spend_player_money(pid, -cost)
            end
          end

          return "Couldn't give you the HPMem.", "Anything else?"
        end

        mark_hpmem_slot_sold(offer.slot)
        refresh_hpmem_offer(offer)
      else
        local ok, reason = whitelist.unlock_card(
          pid,
          offer.lookup,
          offer.code
        )

        if not ok then
          -- Refund the purchase if the chip could not be unlocked.
          if cost > 0 then
            if currency == "bugfrags" then
              ezmemory.spend_player_fragments(pid, -cost)
            else
              ezmemory.spend_player_money(pid, -cost)
            end
          end

          local message

          if reason == "already_unlocked" then
            message = owned_msg
          else
            message =
              "Couldn't unlock that chip ("
              .. tostring(reason or "error")
              .. ")."
          end

          return message, "Anything else?"
        end
      end

      -- Update the selected row immediately.
      local opt = opt_ref_by_id[tostring(choice_id)]

      if opt then
        if offer.kind == "hpmem"
          and not offer_is_sold_out(pid, offer)
        then
          -- Another HPMem remains. Keep the same row and advance
          -- it to the next configured price.
          opt.shop_name = tostring(offer.name)
          opt.text = tostring(offer.name)
          opt.shop_price = tonumber(offer.price) or 0
        else
          -- Chips sell out immediately. HPMem only reaches this
          -- after the final configured HPMem is purchased.
          opt.shop_name = "SOLD OUT"
          opt.text = "SOLD OUT"
          opt.shop_price = tonumber(offer.price) or 0
        end
      end

      -- Do not force a redraw here. TalkVertMenu will redraw after
      -- displaying the purchase result.
      if sfx and sfx.item_get then
        Net.play_sound_for_player(pid, sfx.item_get)
      end

      if offer.kind == "hpmem" then
        return "You bought an HPMem!\nMax HP increased by 20!",
          "Anything else?"
      end

      return "You bought " .. tostring(offer.name) .. "!",
        "Anything else?"
    end,
  })

  -- IMPORTANT: do not let eznpcs finish the dialogue until the menu is closed,
  -- otherwise overworld input unlocks and the menu stops receiving inputs.
  while TalkVertMenu.is_busy and TalkVertMenu.is_busy(player_id) do
    await(Async.sleep(0.05))
  end

  return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
else
  print("[chipshop] failed to load talk_vert_menu:", TalkVertMenu_or_err)
end

      while true do
        local posts = {}
        local items = {}

        for idx, offer in ipairs(offers) do
          local sold_out = offer_is_sold_out(
            player_id,
            offer
          )

          local price_label = (currency == "bugfrags")
            and (tostring(offer.price) .. " BF")
            or short_money(offer.price)

          local label = sold_out
            and string.format("SOLD OUT (%s)", price_label)
            or string.format("%s (%s)", offer.name, price_label)

          local post = helpers.create_bbs_option(label)
          post.id = "__chipshop:" .. tostring(idx)
          table.insert(posts, post)
          items[post.id] = offer
        end

        local balance
        if currency == "bugfrags" then
          balance = tonumber(ezmemory.get_player_fragments(player_id) or 0) or 0
        else
          balance = tonumber(Net.get_player_money(player_id) or 0) or 0
        end

        local bal_post = helpers.create_bbs_option(
          (currency == "bugfrags")
            and ("Your BugFrags: " .. tostring(balance))
            or ("Your Money: " .. short_money(balance))
        )
        bal_post.id = "__chipshop_balance__"
        table.insert(posts, bal_post)

        local board = ezmenus.open_menu(player_id, title, COSMETIC_SHOP_COLOR, posts)
        local sel = await(board.selection_once())
        Net.close_bbs(player_id)

        if not sel then
          break
        end

        if sel ~= "__chipshop_balance__" then
          local chosen = items[tostring(sel)]

          if chosen then
            if offer_is_sold_out(player_id, chosen) then
              local message = sold_out_msg

              if chosen.kind == "chip" then
                message = owned_msg
              end

              await(Async.message_player(
                player_id,
                message,
                mug.texture_path,
                mug.animation_path
              ))
            else
              local price_label = (currency == "bugfrags")
                and (tostring(chosen.price) .. " BugFrags")
                or short_money(chosen.price)

              local confirm = await(Async.question_player(
                player_id,
                string.format(
                  "Buy %s for %s?",
                  chosen.name,
                  price_label
                ),
                mug.texture_path,
                mug.animation_path
              ))

              if confirm == 1 then
                local paid = true

                if chosen.price > 0 then
                  if currency == "bugfrags" then
                    paid = ezmemory.spend_player_fragments(
                      player_id,
                      chosen.price
                    )
                  else
                    paid = ezmemory.spend_player_money(
                      player_id,
                      chosen.price
                    )
                  end
                end

                if not paid then
                  await(Async.message_player(
                    player_id,
                    not_enough_msg,
                    mug.texture_path,
                    mug.animation_path
                  ))
                else
                  local granted = false
                  local fail_msg = nil

                  if chosen.kind == "hpmem" then
                    local old_total = tonumber(
                      ezmemory.count_player_item(
                        player_id,
                        "HPMem"
                      ) or 0
                    ) or 0

                    local ok_give, new_total = pcall(
                      ezmemory.give_player_item,
                      player_id,
                      "HPMem",
                      1
                    )

                    new_total = tonumber(new_total or 0) or 0
                    granted = ok_give and new_total > old_total

                    if granted then
                      mark_hpmem_slot_sold(chosen.slot)
                      refresh_hpmem_offer(chosen)
                    else
                      fail_msg = "Couldn't give you the HPMem."
                    end
                  else
                    local ok, reason = whitelist.unlock_card(
                      player_id,
                      chosen.lookup,
                      chosen.code
                    )

                    granted = ok == true

                    if not granted then
                      if reason == "already_unlocked" then
                        fail_msg = owned_msg
                      else
                        fail_msg =
                          "Couldn't unlock that chip ("
                          .. tostring(reason or "error")
                          .. ")."
                      end
                    end
                  end

                  if granted then
                    if sfx and sfx.item_get then
                      Net.play_sound_for_player(
                        player_id,
                        sfx.item_get
                      )
                    end

                    local success_msg

                    if chosen.kind == "hpmem" then
                      success_msg =
                        "You bought an HPMem! Max HP increased by 20!"
                    else
                      success_msg =
                        "You bought " .. chosen.name .. "!"
                    end

                    await(Async.message_player(
                      player_id,
                      success_msg,
                      mug.texture_path,
                      mug.animation_path
                    ))
                  else
                    -- Refund a failed purchase.
                    if chosen.price > 0 then
                      if currency == "bugfrags" then
                        ezmemory.spend_player_fragments(
                          player_id,
                          -chosen.price
                        )
                      else
                        ezmemory.spend_player_money(
                          player_id,
                          -chosen.price
                        )
                      end
                    end

                    await(Async.message_player(
                      player_id,
                      fail_msg or "Couldn't complete that purchase.",
                      mug.texture_path,
                      mug.animation_path
                    ))
                  end
                end
              end
            end
          end
        end
      end

      return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
    end)
  end
})

----------------------------------------------------------------
-- Pet stat checker
-- Dialogue Type: petcheck
--
-- Routes:
--   Next 1 = pet passes all configured checks
--   Next 2 = no pet / neutral / sad / wrong type / stat too low / stat too high
--
-- Optional custom properties:
--   Mood = happy
--   Pet Type = mettaur
--   Min HP = 40
--   Max HP = 100
--   Min Attack = 5
--   Max Attack = 100
--   Min Attack Rank = 1
--   Max Attack Rank = 20
--
-- Notes:
--   - Leave a property blank to ignore that check.
--   - Mood compares happy / neutral / sad.
--   - Pet Type compares internal kind: mettaur, ratty, swordy, powie, etc.
--   - Attack is the final displayed battle attack, rank * 5.
--   - Attack Rank is the pet's internal rank, 1-20.
----------------------------------------------------------------

local function _petcheck_trim(value)
  if value == nil then return nil end
  local text = tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return nil end
  return text
end

local function _petcheck_ci(props, key)
  if type(props) ~= "table" then return nil end

  local wanted = tostring(key or ""):lower()
  for k, v in pairs(props) do
    if tostring(k):lower() == wanted then
      return _petcheck_trim(v)
    end
  end

  return nil
end

local function _petcheck_num(props, key)
  local v = _petcheck_ci(props, key)
  if v == nil then return nil end
  return tonumber(v)
end

local function _petcheck_bool(props, key, default)
  local v = _petcheck_ci(props, key)
  if v == nil then return default end

  v = tostring(v):lower()

  if v == "true" or v == "yes" or v == "1" or v == "on" then
    return true
  end

  if v == "false" or v == "no" or v == "0" or v == "off" then
    return false
  end

  return default
end

eznpcs.add_event{
  name = "petcheck",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local props = dialogue.custom_properties or {}
      local next_pass = props["Next 1"]
      local next_fail = props["Next 2"]

      if not (Pets and type(Pets.get_armed_pet_info) == "function") then
        return next_fail
      end

      local ok, info = pcall(Pets.get_armed_pet_info, player_id)
      if not ok or type(info) ~= "table" then
        return next_fail
      end

      local battle_ready = _petcheck_bool(props, "Battle Ready", false)
      if battle_ready then
        if info.can_fight ~= true then
          return next_fail
        end

        if info.summoned == true then
          return next_fail
        end
      end

      local expected_can_fight = _petcheck_bool(props, "Can Fight", nil)
      if expected_can_fight ~= nil then
        if (info.can_fight == true) ~= expected_can_fight then
          return next_fail
        end
      end

      local expected_summoned = _petcheck_bool(props, "Summoned", nil)
      if expected_summoned ~= nil then
        if (info.summoned == true) ~= expected_summoned then
          return next_fail
        end
      end

      local expected_mood = _petcheck_ci(props, "Mood")
      if expected_mood then
        local actual_mood = tostring(info.mood or "neutral"):lower()
        if actual_mood ~= expected_mood:lower() then
          return next_fail
        end
      end

      local expected_kind = _petcheck_ci(props, "Pet Type") or _petcheck_ci(props, "Kind")
      if expected_kind then
        local actual_kind = tostring(info.kind or ""):lower()
        expected_kind = expected_kind:gsub("^pet_", ""):lower()
        if actual_kind ~= expected_kind then
          return next_fail
        end
      end

      local hp = tonumber(info.hp or 0) or 0
      local min_hp = _petcheck_num(props, "Min HP")
      local max_hp = _petcheck_num(props, "Max HP")

      if min_hp and hp < min_hp then return next_fail end
      if max_hp and hp > max_hp then return next_fail end

      local attack = tonumber(info.attack or 0) or 0
      local min_attack = _petcheck_num(props, "Min Attack")
      local max_attack = _petcheck_num(props, "Max Attack")

      if min_attack and attack < min_attack then return next_fail end
      if max_attack and attack > max_attack then return next_fail end

      local rank = tonumber(info.rank or 0) or 0
      local min_rank = _petcheck_num(props, "Min Attack Rank") or _petcheck_num(props, "Min Rank")
      local max_rank = _petcheck_num(props, "Max Attack Rank") or _petcheck_num(props, "Max Rank")

      if min_rank and rank < min_rank then return next_fail end
      if max_rank and rank > max_rank then return next_fail end

      return next_pass
    end)
  end
}

local pet_quest2 = {
    name="pet_quest2",
    path="/server/assets/ezlibs-assets/ezencounters/optimized/events.zip",
    pet_exp=0,
    enemies={
        {name="Fishy",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,1,0,0},
        {0,0,0,0,1,0},
        {0,0,0,0,0,1},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local pet_quest2_fight = {
    name="Pet Quest2 Fight",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, pet_quest2))
          local flags = _encounter_result_flags(stats)

          if flags.ran or flags.lost then
              return dialogue.custom_properties["Battle Lost"]
          else
              return dialogue.custom_properties["Battle Won"]
          end
        end)
    end
}
eznpcs.add_event(pet_quest2_fight)

----------------------------------------------------------------
-- Pet XP Reward
-- Dialogue Type: petxp
--
-- Custom properties:
--   Amount = 9
--   Pet XP = 9
--   XP = 9
--
-- Optional:
--   Next 1 = success next dialogue
--   Next 2 = fail next dialogue
--   Dont Notify = true
--   Expected PET ID = pet-...
--
-- Notes:
--   - Put this at the end of a Tiled dialogue chain.
--   - Remove pet_exp from scripted battle encounter tables to avoid double XP.
----------------------------------------------------------------

local function _petxp_prop(props, ...)
  if type(props) ~= "table" then return nil end

  for i = 1, select("#", ...) do
    local wanted = tostring(select(i, ...)):lower()

    for k, v in pairs(props) do
      if tostring(k):lower() == wanted then
        if v ~= nil and tostring(v) ~= "" then
          return v
        end
      end
    end
  end

  return nil
end

local function _get_menuapi_for_petxp()
  local M = rawget(_G, "MenuAPI")

  if not (M and type(M.is_open) == "function") then
    local ok, mod = pcall(require, "scripts/menuAPI/main")
    if ok and type(mod) == "table" then
      M = mod
    end
  end

  return M
end

local function _get_lpets_for_petxp()
  local L = rawget(_G, "LPets")

  if not (L and type(L.show_sp_gauge_gain) == "function") then
    local ok, mod = pcall(require, "scripts/ezlibs-custom/lpets")
    if ok and type(mod) == "table" then
      L = mod
    end
  end

  return L
end

eznpcs.add_event({
  name = "petxp",

  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local props = dialogue.custom_properties or {}

      if not (Pets and type(Pets.award_armed_pet_battle_xp) == "function") then
        return props["Next 2"] or props["Next 1"]
      end

      local amount = tonumber(
        _petxp_prop(props, "Amount", "Pet XP", "XP") or 0
      ) or 0

      amount = math.max(0, math.floor(amount))

      if amount <= 0 then
        return props["Next 2"] or props["Next 1"]
      end

      local before = nil

      if type(Pets.get_armed_pet_info) == "function" then
        local ok_before, info = pcall(
          Pets.get_armed_pet_info,
          player_id
        )

        if ok_before and type(info) == "table" then
          before = info
        end
      end

      local old_xp =
        before
        and math.max(0, math.floor(tonumber(before.xp) or 0))
        or 0

      local expected_uid = _petxp_prop(
        props,
        "Expected PET ID",
        "Expected Pet ID",
        "Expected UID",
        "Pet ID"
      )

      local ok, new_xp, skill_gained, effective_amount, mood =
        Pets.award_armed_pet_battle_xp(
          player_id,
          amount,
          {
            expected_uid = expected_uid,
            notify = false,
          }
        )

      effective_amount = math.max(
        0,
        math.floor(tonumber(effective_amount) or 0)
      )

      if not ok or effective_amount <= 0 then
        return props["Next 2"] or props["Next 1"]
      end

      local after = nil

      if type(Pets.get_armed_pet_info) == "function" then
        local ok_after, info = pcall(
          Pets.get_armed_pet_info,
          player_id
        )

        if ok_after and type(info) == "table" then
          after = info
        end
      end

      local notify =
        tostring(props["Dont Notify"] or ""):lower() ~= "true"

      if notify then
        local LPets = _get_lpets_for_petxp()

        if LPets and type(LPets.show_sp_gauge_gain) == "function" then
          pcall(LPets.show_sp_gauge_gain, player_id, {
            old_xp = old_xp,
            new_xp = math.max(
              0,
              math.floor(tonumber(new_xp) or old_xp)
            ),

            old_spbar_xp =
              before and before.spbar_xp,

            old_spbar_xp_per_point =
              before and before.spbar_xp_per_point,

            new_spbar_xp =
              after and after.spbar_xp,

            new_spbar_xp_per_point =
              after and after.spbar_xp_per_point,

            spbar_xp_per_point =
              after and after.spbar_xp_per_point,

            xp_per_skill_point =
              after and after.xp_per_skill_point or 175,

            available_skill_points =
              after and after.available_skill_points or 0,

            skill_points_gained =
              skill_gained or 0,
          })

          local MenuAPI = _get_menuapi_for_petxp()

          if MenuAPI and type(MenuAPI.is_open) == "function" then
            local guard = 0

            while MenuAPI.is_open(player_id) and guard < 400 do
              await(Async.sleep(0.05))
              guard = guard + 1
            end
          else
            await(Async.sleep(2.0))
          end

        elseif Net and Net.message_player then
          await(Async.message_player(
            player_id,
            "Your pet gained "
              .. tostring(effective_amount)
              .. " XP."
          ))
        end
      end

      return props["Next 1"]
    end)
  end
})

-- ============================================================
-- Tour private bot session state
-- ============================================================

local TOUR_SONG_PATH = "/server/assets/Wcity Tour.ogg"
local TOUR_RESTORE_SONG_PATH = "/server/assets/ChillCafe.ogg"

local TOUR_SESSIONS = rawget(_G, "__TOUR_SESSIONS__")
if type(TOUR_SESSIONS) ~= "table" then
  TOUR_SESSIONS = {}
  _G.__TOUR_SESSIONS__ = TOUR_SESSIONS
end

local function tour_all_players()
  local out = {}

  if not (Net and Net.list_areas and Net.list_players) then
    return out
  end

  for _, area_id in ipairs(Net.list_areas() or {}) do
    for _, pid in ipairs(Net.list_players(area_id) or {}) do
      out[#out + 1] = pid
    end
  end

  return out
end

local function start_tour_song_for_player(player_id)
  if not TOUR_SONG_PATH or TOUR_SONG_PATH == "" then
    return false
  end

  if Net.provide_asset_for_player then
    pcall(Net.provide_asset_for_player, player_id, TOUR_SONG_PATH)
  end

  if Net.set_song_for_player then
    local ok = pcall(Net.set_song_for_player, player_id, TOUR_SONG_PATH)
    return ok == true
  end

  return false
end

local function cleanup_tour_session(player_id)
  local s = TOUR_SESSIONS[player_id]
  if not s then return end

  s.active = false

  if s.tour_song_started then
    -- Do not use Net.stop_song_for_player here.
    -- It stops the tour song, but can also leave the area BGM stopped.
    if Net.set_song_for_player and TOUR_RESTORE_SONG_PATH and TOUR_RESTORE_SONG_PATH ~= "" then
      pcall(Net.provide_asset_for_player, player_id, TOUR_RESTORE_SONG_PATH)
      pcall(Net.set_song_for_player, player_id, TOUR_RESTORE_SONG_PATH)
    end
  end

  if s.private_bot_id then
    pcall(Net.remove_bot, s.private_bot_id)
  end

  if s.original_bot_id then
    pcall(Net.include_actor_for_player, player_id, s.original_bot_id)
  end

  pcall(Net.unlock_player_input, player_id)

  TOUR_SESSIONS[player_id] = nil
end

if not rawget(_G, "__TOUR_SESSION_HOOKED__") then
  _G.__TOUR_SESSION_HOOKED__ = true

  Net:on("player_disconnect", function(event)
    if event and event.player_id then
      cleanup_tour_session(event.player_id)
    end
  end)

  -- If someone joins while a tour is active, hide all private tour bots from them.
  Net:on("player_join", function(event)
    local joined_id = event and event.player_id
    if not joined_id then return end

    for owner_id, s in pairs(TOUR_SESSIONS) do
      if s and s.active and s.private_bot_id and joined_id ~= owner_id then
        pcall(Net.exclude_actor_for_player, joined_id, s.private_bot_id)
      end
    end
  end)
end

eznpcs.add_event{
  name = "tour",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local area_id = Net.get_player_area(player_id)
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
      local props = dialogue.custom_properties or {}

      local original_bot_id = npc and npc.bot_id
      if not original_bot_id then
        await(Async.message_player(player_id, "Tour guide is missing a bot id."))
        return props["Next 1"]
      end

      -- Tweak this if the guide lags slightly behind the player.
      local GUIDE_SPEED_MULT = tonumber(props["Guide Speed Mult"] or props["GuideSpeedMult"] or 2.1) or 2.1

      -- Safety: if this player somehow already had a tour bot, remove it first.
      cleanup_tour_session(player_id)

      local session = {
        active = true,
        original_bot_id = original_bot_id,
        private_bot_id = nil,
        tour_song_started = false,
      }

      TOUR_SESSIONS[player_id] = session
      session.tour_song_started = start_tour_song_for_player(player_id)

      local DIR_SUFFIX = {
        ["Down Right"] = "DR",
        ["Down Left"]  = "DL",
        ["Up Right"]   = "UR",
        ["Up Left"]    = "UL",
      }

      local VALID_DIR = {
        ["Down Right"] = true,
        ["Down Left"]  = true,
        ["Up Right"]   = true,
        ["Up Left"]    = true,
      }

      local function normalize_direction(dir, fallback)
        dir = tostring(dir or "")

        if VALID_DIR[dir] then
          return dir
        end

        return fallback or "Down Right"
      end

      local function anim_state(prefix, dir)
        return prefix .. "_" .. (DIR_SUFFIX[dir] or "DR")
      end

      local function direction_from_delta(dx, dy)
        dx = tonumber(dx) or 0
        dy = tonumber(dy) or 0

        if math.abs(dx) >= math.abs(dy) then
          if dx >= 0 then
            return "Down Right"
          else
            return "Up Left"
          end
        else
          if dy >= 0 then
            return "Down Left"
          else
            return "Up Right"
          end
        end
      end

      local function get_prop(obj, ...)
        local obj_props = obj and obj.custom_properties or nil
        if not obj_props then return nil end

        for i = 1, select("#", ...) do
          local key = select(i, ...)
          local value = obj_props[key]

          if value ~= nil and tostring(value) ~= "" then
            return value
          end
        end

        return nil
      end

      local function get_marker(name)
        local marker = Net.get_object_by_name(area_id, name)
        if not marker then
          error("[tour] Missing marker object: " .. tostring(name))
        end
        return marker
      end

      local function player_still_here()
        if not session.active then return false end

        local ok, cur_area = pcall(Net.get_player_area, player_id)
        return ok and cur_area == area_id
      end

      local function guide_says(text)
        if not player_still_here() then
          return Async.sleep(0)
        end

        return Async.message_player(
          player_id,
          text,
          mug.texture_path,
          mug.animation_path
        )
      end

      local function get_player_pos()
        local pos = Net.get_player_position(player_id) or {}
        return {
          x = tonumber(pos.x) or 0,
          y = tonumber(pos.y) or 0,
          z = tonumber(pos.z) or 0,
        }
      end

      local function create_private_guide()
        local start_dir = normalize_direction(npc.direction, "Down Right")
        local start_anim = anim_state("IDLE", start_dir)

        local texture_path = npc.texture_path
        local animation_path = npc.animation_path

        if texture_path and texture_path ~= "" then
          pcall(Net.provide_asset, area_id, texture_path)
        end

        if animation_path and animation_path ~= "" then
          pcall(Net.provide_asset, area_id, animation_path)
        end

        local bot_data = {
          name = tostring(npc.name or "Tour Guide"),
          area_id = area_id,

          x = tonumber(npc.x) or 0,
          y = tonumber(npc.y) or 0,
          z = tonumber(npc.z) or 0,

          direction = start_dir,
          solid = false,
          size = tonumber(npc.size) or 0.2,
          speed = tonumber(npc.speed) or 1,

          texture_path = texture_path,
          animation_path = animation_path,
          animation = start_anim,

          -- Avoid a visible warp-in for the private copy.
          warp_in = false,
        }

        local private_bot_id = nil

        local ok_create, created = pcall(Net.create_bot, bot_data)
        if ok_create then
          private_bot_id = created
        end

        if not private_bot_id then
          error("[tour] Failed to create private tour guide bot.")
        end

        -- Hide the private guide from everyone except this player.
        for _, pid in ipairs(tour_all_players()) do
          if pid ~= player_id then
            pcall(Net.exclude_actor_for_player, pid, private_bot_id)
          end
        end

        pcall(Net.include_actor_for_player, player_id, private_bot_id)
        pcall(Net.set_bot_direction, private_bot_id, start_dir)
        pcall(Net.animate_bot, private_bot_id, start_anim, true)

        session.private_bot_id = private_bot_id

        return {
          bot_id = private_bot_id,
          x = bot_data.x,
          y = bot_data.y,
          z = bot_data.z,
          direction = start_dir,
        }
      end

      -- Hide the real NPC only for this player.
      -- Other players can still talk to the original NPC and get their own private guide.
      pcall(Net.exclude_actor_for_player, player_id, original_bot_id)

      local guide = create_private_guide()

      local function marker_dirs(guide_marker, player_marker, guide_walk_dir, player_walk_dir)
        -- For guide:
        -- Preferred: TourGuide marker has Direction.
        -- Optional: TourGuide marker has Guide Direction.
        local guide_dir = normalize_direction(
          get_prop(guide_marker, "Guide Direction", "Direction", "Face Direction", "Final Direction")
          or get_prop(player_marker, "Guide Direction"),
          guide_walk_dir
        )

        -- For player:
        -- Preferred: TourPlayer marker has Direction.
        -- Optional: TourGuide marker has Player Direction.
        local player_dir = normalize_direction(
          get_prop(player_marker, "Player Direction", "Direction", "Face Direction", "Final Direction")
          or get_prop(guide_marker, "Player Direction"),
          player_walk_dir
        )

        return guide_dir, player_dir
      end

      local function move_pair(guide_marker_name, player_marker_name, duration)
        if not player_still_here() then return end

        duration = tonumber(duration or 1.5) or 1.5

        local guide_marker = get_marker(guide_marker_name)
        local player_marker = get_marker(player_marker_name)

        -- Allow per-point duration from either marker if desired.
        local marker_duration =
          tonumber(get_prop(guide_marker, "Duration", "Move Duration", "Walk Duration") or "")
          or tonumber(get_prop(player_marker, "Duration", "Move Duration", "Walk Duration") or "")

        if marker_duration and marker_duration > 0 then
          duration = marker_duration
        end

        local player_pos = get_player_pos()

        local px1 = tonumber(player_pos.x) or 0
        local py1 = tonumber(player_pos.y) or 0
        local px2 = tonumber(player_marker.x) or px1
        local py2 = tonumber(player_marker.y) or py1

        local gx1 = tonumber(guide.x) or 0
        local gy1 = tonumber(guide.y) or 0
        local gz1 = tonumber(guide.z) or 0

        local gx2 = tonumber(guide_marker.x) or gx1
        local gy2 = tonumber(guide_marker.y) or gy1
        local gz2 = tonumber(guide_marker.z) or gz1

        local player_walk_dir = direction_from_delta(px2 - px1, py2 - py1)
        local guide_walk_dir  = direction_from_delta(gx2 - gx1, gy2 - gy1)

        local guide_final_dir, player_final_dir =
          marker_dirs(guide_marker, player_marker, guide_walk_dir, player_walk_dir)

        local player_walk = anim_state("WALK", player_walk_dir)
        local player_idle = anim_state("IDLE", player_final_dir)

        local guide_walk = anim_state("WALK", guide_walk_dir)
        local guide_idle = anim_state("IDLE", guide_final_dir)

        print("[tour] moving guide to", guide_marker_name, gx2, gy2, gz2, "dir", guide_final_dir)
        print("[tour] moving player to", player_marker_name, px2, py2, player_marker.z, "dir", player_final_dir)

        -- Player uses the cutscene-style movement.
        Net.animate_player_properties(player_id, {
          {
            properties = {
              {
                property = "X",
                value = px1
              },
              {
                property = "Y",
                value = py1
              },
              {
                property = "Animation",
                value = player_walk
              }
            },
          },
          {
            properties = {
              {
                property = "X",
                ease = "Linear",
                value = px2
              },
              {
                property = "Y",
                ease = "Linear",
                value = py2
              }
            },
            duration = duration
          },
          {
            properties = {
              {
                property = "Animation",
                value = player_idle
              }
            },
            duration = 0.0
          }
        })

        -- Guide uses real movement with Net.move_bot, waypoint-style.
        guide.direction = guide_walk_dir
        pcall(Net.set_bot_direction, guide.bot_id, guide_walk_dir)
        pcall(Net.animate_bot, guide.bot_id, guide_walk, true)

        local guide_duration = duration / GUIDE_SPEED_MULT
        if guide_duration < 0.05 then
          guide_duration = 0.05
        end

        local elapsed = 0
        local step_time = 1 / 30

        while elapsed < guide_duration do
          if not player_still_here() then return end

          local t = elapsed / guide_duration
          if t < 0 then t = 0 end
          if t > 1 then t = 1 end

          local x = gx1 + ((gx2 - gx1) * t)
          local y = gy1 + ((gy2 - gy1) * t)
          local z = gz1 + ((gz2 - gz1) * t)

          Net.move_bot(guide.bot_id, x, y, z)

          guide.x = x
          guide.y = y
          guide.z = z

          await(Async.sleep(step_time))
          elapsed = elapsed + step_time
        end

        if not player_still_here() then return end

        -- Final exact position.
        Net.move_bot(guide.bot_id, gx2, gy2, gz2)

        guide.x = gx2
        guide.y = gy2
        guide.z = gz2
        guide.direction = guide_final_dir

        pcall(Net.set_bot_direction, guide.bot_id, guide_final_dir)
        pcall(Net.animate_bot, guide.bot_id, guide_idle, true)

        -- Wait out the rest of the player's movement.
        local remaining = duration - guide_duration
        if remaining > 0 then
          await(Async.sleep(remaining))
        end

        if not player_still_here() then return end

        -- Final facing after both actors have finished.
        pcall(Net.animate_player, player_id, player_idle, true)
        pcall(Net.set_bot_direction, guide.bot_id, guide_final_dir)
        pcall(Net.animate_bot, guide.bot_id, guide_idle, true)
      end

      local function walk_path(points)
        for _, p in ipairs(points or {}) do
          if not player_still_here() then return end

          move_pair(
            p[1] or p.guide,
            p[2] or p.player,
            p[3] or p.duration or 1.5
          )
        end
      end

      local blocks = {}

      local function add_block(fn)
        blocks[#blocks + 1] = fn
      end

      ------------------------------------------------------------
      -- TOUR SCRIPT STARTS HERE
      ------------------------------------------------------------

      add_block(function()
        walk_path({
          { "TourGuide1", "TourPlayer1", 1.5 },
        })

        await(guide_says("This is our first stop, TeamsHQ."))
        await(guide_says("Every month, you can join a team and earn RP through different server events."))
        await(guide_says("At the end of the month, the team with the most RP wins. If you earn enough RP, you can also win good money and sometimes unique prizes."))
      end)

      add_block(function()
        walk_path({
          { "TourGuide2", "TourPlayer2", 1.8 },
        })

        await(guide_says("This is the JobBBS board."))
        await(guide_says("You can accept daily jobs here and complete them for money."))
        await(guide_says("You can also open your Left Trigger menu anytime to check your current job progress."))
      end)

      add_block(function()
        walk_path({
          { "TourGuide3", "TourPlayer3", 1.8 },
        })

        await(guide_says("Our third stop is the ice rink and fishing area."))
        await(guide_says("Ice puzzles are great for new players. Clearing each one for the first time gives an extra money bonus."))
        await(guide_says("Fishing is another easy way to earn money. It does not need any investment, just start catching fish and get money based on its weight."))
        await(guide_says("The ice rinks also have their own ice fishing variant with different difficulty."))
      end)

      add_block(function()
        walk_path({
          { "TourGuide4", "TourPlayer4", 1.8 },
        })

        await(guide_says("This is the General BBS and the UNO table."))
        await(guide_says("The General BBS is where players can leave messages and chat freely."))
        await(guide_says("The UNO table is here in case you just want to relax and play a few friendly games of UNO "))
      end)

      add_block(function()
        walk_path({
          { "TourGuide5", "TourPlayer5", 1.8 },
        })

        await(guide_says("This is the train station."))
        await(guide_says("From here, you can visit servers made by other creators."))
        await(guide_says("I recommend checking out the Web Browser server, where your Navi can explore the real internet."))
        await(guide_says("Just remember, progress does not transfer between servers. Some servers may also have their own Navi or chip rules, but that is rare."))
      end)

      add_block(function()
        walk_path({
          { "TourGuide6A", "TourPlayer6A", 0.5 },
          { "TourGuide6B", "TourPlayer6B", 0.5 },
          { "TourGuide6C", "TourPlayer6C", 0.5 },
          { "TourGuide6",  "TourPlayer6",  1.0 },
        })

        await(guide_says("This is the YGO hangout."))
        await(guide_says("This server has a YGO card collection and duel mini-game."))
        await(guide_says("You can open packs, collect cards, build a deck, and duel with the cards you find."))
        await(guide_says("Card collecting isn't everyone's cup of tea so don't feel like you have to buy cards"))
      end)

      add_block(function()
        walk_path({
          { "TourGuide7A", "TourPlayer7A", 1.4 },
          { "TourGuide7",  "TourPlayer7",  1.3 },
        })

        await(guide_says("This path leads to the WCity adventure areas."))
        await(guide_says("Beyond this point, only approved NetNavis, BattleChips, and NCPs are allowed."))
        await(guide_says("Once you enter, you build your folder using chips earned through battles."))
        await(guide_says("Check the pinned BBS posts to see where to download the allowed Navis, chips, and Navi Customizer programs."))
        await(guide_says("WCity has story quests and gets new quests regularly. You can adventure alone or bring a friend."))
        await(guide_says("The password for this block is Welcome"))
      end)

      ------------------------------------------------------------
      -- TOUR SCRIPT ENDS HERE
      ------------------------------------------------------------

      Net.lock_player_input(player_id)

      local ok, err = pcall(function()
        for _, block in ipairs(blocks) do
          if not player_still_here() then return end
          block()
        end
      end)

      if not ok then
        print("[tour] error:", err)
        if player_still_here() then
          await(Async.message_player(player_id, "The tour broke. Tell an admin."))
        end
      end

      cleanup_tour_session(player_id)

      return props["Next 1"]
    end)
  end
}

----------------------------------------------------------------
-- Dialogue Type: provideassets
--
-- Tiled properties:
--   Dialogue Type = provideassets
--   Asset = /server/assets/example.png
--
-- Or:
--   Asset 1 = /server/assets/example.png
--   Asset 2 = /server/assets/example.animation
--   Asset 3 = /server/assets/example.ogg
--
--   Next 1 = <next dialogue object id>
----------------------------------------------------------------

eznpcs.add_event{
  name = "provideassets",

  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local props = dialogue.custom_properties or {}
      local asset_paths = {}
      local seen = {}

      local function add_asset_path(path)
        path = tostring(path or "")
        path = path:gsub("\\", "/")
        path = path:gsub("^%s+", ""):gsub("%s+$", "")

        if path == "" then
          return
        end

        -- Convenience path normalization.
        if path:sub(1, 7) == "server/" then
          path = "/" .. path
        elseif path:sub(1, 8) == "assets/" then
          path = "/server/" .. path
        elseif path:sub(1, 8) == "/assets/" then
          path = "/server" .. path
        end

        if not seen[path] then
          seen[path] = true
          asset_paths[#asset_paths + 1] = path
        end
      end

      -- Optional unnumbered property for a single asset.
      add_asset_path(props["Asset"])

      -- Asset 1, Asset 2, Asset 3, etc.
      for _, path in ipairs(
        helpers.extract_numbered_properties(dialogue, "Asset ")
      ) do
        add_asset_path(path)
      end

      for _, path in ipairs(asset_paths) do
        local exists = true

        if Net.has_asset then
          local ok, result = pcall(Net.has_asset, path)
          exists = ok and result == true
        end

        if exists then
          local ok, err = pcall(
            Net.provide_asset_for_player,
            player_id,
            path
          )

          if not ok then
            print(
              "[provideassets] Failed to provide "
              .. tostring(path)
              .. ": "
              .. tostring(err)
            )
          end
        else
          print(
            "[provideassets] Asset does not exist: "
            .. tostring(path)
          )
        end
      end

      -- Give the transfers a small head start if the next dialogue
      -- immediately tries to draw or play one of these assets.
      if #asset_paths > 0 then
        await(Async.sleep(0.05))
      end

      return props["Next 1"]
    end)
  end
}

-- Repaint any already-revealed paths when players appear in an area
Net:on("player_join", function(ev)
    if not ev or not ev.player_id then return end
    local area_id = Net.get_player_area(ev.player_id)
    if area_id then
        rehydrate_secret_paths_for_area(area_id)
    end
end)

Net:on("player_area_transfer", function(ev)
    if not ev or not ev.player_id then return end
    local area_id = Net.get_player_area(ev.player_id)
    if area_id then
        rehydrate_secret_paths_for_area(area_id)
    end
end)

helpers.safe_require("scripts/events/eznpcs_battle_events")
