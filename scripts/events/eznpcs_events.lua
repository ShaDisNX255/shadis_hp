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

local boss2 = {
    name="boss2",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    pet_exp=9,
    enemies={
        {name="HeelNavi",rank=2},
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
          local stats = await(ezencounters.begin_encounter(player_id, bossX))
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

local boss4 = {
    name="boss4",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    pet_exp=10,
    enemies={
        {name="ProtomanPoN",rank=2},
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
        path="bn3_boss.mid"
    },
}

local event4 = {
    name="Proto Battle",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, bossX))
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

local boss5 = {
    name="boss5",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    pet_exp=8,
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
        path="bn3_boss.mid"
    },
}

local event5 = {
    name="Roll Battle",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, bossX))
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
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    pet_exp=8,
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
        path="bn3_boss.mid"
    },
}

local event6 = {
    name="Guts Battle",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, bossX))
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

local boss7 = {
    name="boss7",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    pet_exp=9,
    enemies={
        {name="GutsManPoN",rank=3},
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
        path="bn3_boss.mid"
    },
}

local event7 = {
    name="Guts3 Battle",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, bossX))
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
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    pet_exp=11,
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
        path="bn3_boss.mid"
    },
}

local event8 = {
    name="GregarB Battle",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
          local stats = await(ezencounters.begin_encounter(player_id, bossX))
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
    for _ = 1, (pack.rolls or 1) do
        local group = pick_weighted(pack.groups or {})
        if not group then return end
        local items = group.items
        if not items or #items == 0 then return end
        local idx = math.random(1, #items)
        local obj_id = items[idx]
        local info = helpers.read_item_information(area_id, obj_id)
        if info then
            await(ezmemory.give_item_with_optional_notify(player_id, area_id, obj_id, info, false))
            table.insert(names_acc, info.name)
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

local function pack_shop_action(npc, player_id, dialogue, relay_object)
    return async(function ()
        local area_id = Net.get_player_area(player_id)
        local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
        local pack = read_single_pack(dialogue)

        if not pack or not pack.groups or #pack.groups == 0 then
            await(Async.message_player(player_id, "Sorry, I'm not selling any packs right now.", mug.texture_path, mug.animation_path))
            return dialogue.custom_properties["Next 1"]
        end

        -- Intro once
        local rolls = pack.rolls or 1
        local suffix = (rolls == 1) and "card" or "cards"
        await(Async.message_player(
            player_id,
            string.format("%s - %d$ (%d %s)\n\n%s", pack.name, pack.price or 0, rolls, suffix, pack.description or ""),
            mug.texture_path, mug.animation_path
        ))

        -- First purchase (1/10/Cancel)
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
            if msg then await(Async.message_player(player_id, msg, mug.texture_path, mug.animation_path)) end
            return dialogue.custom_properties["Next 1"]
        end

        -- Loop: offer 1/10/Cancel again
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
                if msg2 then await(Async.message_player(player_id, msg2, mug.texture_path, mug.animation_path)) end
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

      -- Safety check: cosmetics module available?
      if not cosmetics or not cosmetics.unlock_for_player then
        await(Async.message_player(
          player_id,
          "Cosmetics system is not available right now.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      -- Lowercased custom props helper (already used by Pack Shop)
      local function ci_props(d)
        local ci = {}
        for k, v in pairs(d.custom_properties or {}) do
          ci[string.lower(tostring(k))] = v
        end
        return ci
      end

      local ci = ci_props(dialogue)

      -- Build the list of offers from Sell N / Price N
      local offers = {}
      local i = 1
      while true do
        local sell = ci["sell " .. i]
        if not sell then break end

        local price_raw = ci["price " .. i] or ci["cost " .. i]
        local price = tonumber(price_raw) or 0
        if price < 0 then price = 0 end

        local cosmetic_id = tostring(sell)
        local name = cosmetics.get_name_for_id
                    and cosmetics.get_name_for_id(cosmetic_id)
                    or cosmetic_id

        table.insert(offers, {
          cosmetic_id = cosmetic_id,
          price       = price,
          name        = name,
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

      -- Shop loop (BBS board)
      while true do
        -- Build BBS posts fresh each time so "Owned" tags update after purchases
        local posts, items = {}, {}
        for _, offer in ipairs(offers) do
          local owned = cosmetics.has_cosmetic
                     and cosmetics.has_cosmetic(player_id, offer.cosmetic_id)
          local label = owned
            and string.format("%s (%s, Owned)", offer.name, short_money(offer.price))
            or  string.format("%s (%s)",        offer.name, short_money(offer.price))

          local post = helpers.create_bbs_option(label)
          table.insert(posts, post)
          items[#posts] = offer
        end

        -- Open BBS-style board
        local board = ezmenus.open_menu(
          player_id,
          "Cosmetic Shop",
          COSMETIC_SHOP_COLOR,
          posts
        )

        local sel = await(board.selection_once())
        Net.close_bbs(player_id)  -- close board after selection / cancel

        if not sel then break end  -- B pressed / closed

        -- Find which offer was chosen
        local chosen
        for idx, post in ipairs(posts) do
          local pid = post.id or post.title or ""
          if sel == pid then
            chosen = items[idx]
            break
          end
        end
        if not chosen then break end

        -- Already owned? Block re-purchase.
        if cosmetics.has_cosmetic and cosmetics.has_cosmetic(player_id, chosen.cosmetic_id) then
          await(Async.message_player(
            player_id,
            "You already have the " .. chosen.name .. " cosmetic.",
            mug.texture_path, mug.animation_path
          ))
        else
          -- Yes/No confirmation (single quantity) with live preview
          local question = string.format(
            "Buy %s for %s?",
            chosen.name,
            short_money(chosen.price)
          )

          -- Apply a temporary cosmetic so the player can see it
          if cosmetics.preview_for_shop then
            cosmetics.preview_for_shop(player_id, chosen.cosmetic_id)
          end

          -- Ask the question; 1 = Yes, anything else = No/Cancel
          local res = await(Async.question_player(
            player_id,
            question,
            mug.texture_path, mug.animation_path
          ))
          local do_buy = (res == 1)

          -- Always clear the temporary preview after the question
          if cosmetics.clear_shop_previews then
            cosmetics.clear_shop_previews(player_id)
          end

          if do_buy then
            local price = chosen.price or 0

            -- Paid cosmetic
            if price > 0 then
              if not ezmemory.spend_player_money(player_id, price) then
                await(Async.message_player(
                  player_id,
                  "You don't have enough money.",
                  mug.texture_path, mug.animation_path
                ))
              else
                local ok, reason = cosmetics.unlock_for_player(player_id, chosen.cosmetic_id)
                if ok then
                  if sfx and sfx.item_get then
                    Net.play_sound_for_player(player_id, sfx.item_get)
                  end
                  await(Async.message_player(
                    player_id,
                    "You got the " .. chosen.name .. " cosmetic!",
                    mug.texture_path, mug.animation_path
                  ))
                else
                  await(Async.message_player(
                    player_id,
                    "Couldn't unlock that cosmetic (" .. tostring(reason or "error") .. ").",
                    mug.texture_path, mug.animation_path
                  ))
                end
              end

            -- Free cosmetic
            else
              local ok, reason = cosmetics.unlock_for_player(player_id, chosen.cosmetic_id)
              if ok then
                if sfx and sfx.item_get then
                  Net.play_sound_for_player(player_id, sfx.item_get)
                end
                await(Async.message_player(
                  player_id,
                  "You got the " .. chosen.name .. " cosmetic!",
                  mug.texture_path, mug.animation_path
                ))
              else
                await(Async.message_player(
                  player_id,
                  "Couldn't unlock that cosmetic (" .. tostring(reason or "error") .. ").",
                  mug.texture_path, mug.animation_path
                ))
              end
            end
          end
        end

        -- loop continues until player cancels / closes the board
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
-- BugFrag Dealer Shop (sells cosmetics + decors/pets for BugFrags)
-- Dialogue Type: "fragshop"
--
-- Configure per-NPC via custom properties (case-insensitive):
--   Sell 1   = ShadowAura
--   Type 1   = cosmetic        (or decor / pet)
--   Amount 1 = 1               (ignored for cosmetics; defaults to 1)
--   Price 1  = 5               (BugFrag cost; defaults to 0)
--   Sell 2 / Type 2 / Amount 2 / Price 2 ... etc
--
-- Optional:
--   Shop Title = BugFrag Dealer
--   Not Enough Msg = You don't have enough BugFrags.
--   Already Owned Msg = You already own that cosmetic.
----------------------------------------------------------------

local BUGFRAG_SHOP_COLOR = { r = 245, g = 210, b = 70 } -- match decor/cosmetic shop yellow
local DECOR_MEM_KEY__ONCEHUB = "oncehub_decor_inventory_v1"

local function short_frags(n)
  n = math.floor(tonumber(n) or 0)
  return string.format("%d BF", n)
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

local function oncehub_add_owned(pid, id, qty)
  qty = math.floor(tonumber(qty) or 0)
  if qty == 0 then return end
  id = tostring(id or "")
  if id == "" then return end

  local secret = (helpers and helpers.get_safe_player_secret) and helpers.get_safe_player_secret(pid) or pid
  local pmem = ezmemory.get_player_memory(secret) or {}
  if type(pmem[DECOR_MEM_KEY__ONCEHUB]) ~= "table" then
    pmem[DECOR_MEM_KEY__ONCEHUB] = {}
  end
  local inv = pmem[DECOR_MEM_KEY__ONCEHUB]
  inv[id] = (tonumber(inv[id]) or 0) + qty

  if ezmemory.save_player_memory then
    ezmemory.save_player_memory(secret)
  elseif ezmemory.set_player_memory then
    ezmemory.set_player_memory(secret, pmem)
  end
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

eznpcs.add_event{
  name = "fragshop",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
      local ci = build_ci_props(dialogue)

      -- Ensure fragments support exists
      if not ezmemory or not ezmemory.get_player_fragments or not ezmemory.spend_player_fragments then
        await(Async.message_player(
          player_id,
          "BugFrag shop isn't available on this server build.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      local title = tostring(get_ci(ci, "shop title") or "BugFrag Dealer")
      local not_enough_msg = tostring(get_ci(ci, "not enough msg") or "You don't have enough BugFrags.")
      local owned_msg = tostring(get_ci(ci, "already owned msg") or "You already own that cosmetic.")

      -- Build offers from Sell N / Type N / Amount N / Price N
      local offers = {}
      local i = 1
      while true do
        local sell = get_ci(ci, "sell " .. i)
        if not sell then break end

        local typ = tostring(get_ci(ci, "type " .. i) or "decor")
        typ = string.lower(typ)
        if typ == "pet" then typ = "decor" end
        if typ == "cosmetics" then typ = "cosmetic" end

        local amount = math.floor(tonumber(get_ci(ci, "amount " .. i) or 1) or 1)
        if amount < 1 then amount = 1 end

        local price = math.floor(tonumber(get_ci(ci, "price " .. i) or get_ci(ci, "cost " .. i) or 0) or 0)
        if price < 0 then price = 0 end

        local id = tostring(sell)
        local pretty =
          (typ == "cosmetic" and cosmetics and cosmetics.get_name_for_id and cosmetics.get_name_for_id(id))
          or (typ == "decor" and oncehub_catalog_name_for(id))
          or id

        table.insert(offers, {
          id = id,
          type = typ,
          amount = amount,
          price = price,
          name = pretty,
        })

        i = i + 1
      end

      if #offers == 0 then
        await(Async.message_player(
          player_id,
          "Sorry, I'm not selling anything right now.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      while true do
        local cur_frags = tonumber(ezmemory.get_player_fragments(player_id) or 0) or 0

        local posts, items = {}, {}
        for _, offer in ipairs(offers) do
          local label
          if offer.type == "cosmetic" then
            local owned = cosmetics and cosmetics.has_cosmetic and cosmetics.has_cosmetic(player_id, offer.id)
            label = owned
              and string.format("%s (%s, Owned)", offer.name, short_frags(offer.price))
              or  string.format("%s (%s)",        offer.name, short_frags(offer.price))
          else
            local owned = oncehub_count_owned(player_id, offer.id)
            if offer.amount ~= 1 then
              label = string.format("%s x%d (%s) [Owned:%d]", offer.name, offer.amount, short_frags(offer.price), owned)
            else
              label = string.format("%s (%s) [Owned:%d]", offer.name, short_frags(offer.price), owned)
            end
          end

          local post = helpers.create_bbs_option(label)
          table.insert(posts, post)
          items[#posts] = offer
        end

        -- Add a "balance" footer option (non-purchasable)
        local bal_post = helpers.create_bbs_option(string.format("Your BugFrags: %d", cur_frags))
        bal_post.id = "__bf_balance__"
        table.insert(posts, bal_post)

        local board = ezmenus.open_menu(
          player_id,
          title,
          BUGFRAG_SHOP_COLOR,
          posts
        )

        local sel = await(board.selection_once())
        Net.close_bbs(player_id)

        if not sel then break end -- cancel

        if sel == "__bf_balance__" then
          -- just reopen (acts like a footer)
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
          if not chosen then
            -- if they selected balance or something unknown, just loop
          else
            -- Cosmetic owned check
            if chosen.type == "cosmetic" and cosmetics and cosmetics.has_cosmetic and cosmetics.has_cosmetic(player_id, chosen.id) then
              await(Async.message_player(player_id, owned_msg, mug.texture_path, mug.animation_path))
            else
              -- Preview for cosmetics (optional)
              if chosen.type == "cosmetic" and cosmetics and cosmetics.preview_for_shop then
                cosmetics.preview_for_shop(player_id, chosen.id)
              end

              local question
              if chosen.type == "decor" and chosen.amount ~= 1 then
                question = string.format("Buy %s x%d for %s?", chosen.name, chosen.amount, short_frags(chosen.price))
              else
                question = string.format("Buy %s for %s?", chosen.name, short_frags(chosen.price))
              end

              local res = await(Async.question_player(player_id, question, mug.texture_path, mug.animation_path))
              local do_buy = (res == 1)

              if cosmetics and cosmetics.clear_shop_previews then
                cosmetics.clear_shop_previews(player_id)
              end

              if do_buy then
                if chosen.price > 0 and not ezmemory.spend_player_fragments(player_id, chosen.price) then
                  await(Async.message_player(player_id, not_enough_msg, mug.texture_path, mug.animation_path))
                else
                  local reward_msg = nil

                  if chosen.type == "cosmetic" then
                    local ok, reason = cosmetics.unlock_for_player(player_id, chosen.id)
                    if ok then
                      reward_msg = "You got the " .. chosen.name .. " cosmetic!"
                    else
                      reward_msg = "Couldn't unlock that cosmetic (" .. tostring(reason or "error") .. ")."
                    end
                  else
                    oncehub_add_owned(player_id, chosen.id, chosen.amount)
                    if chosen.amount ~= 1 then
                      reward_msg = string.format("You got %dx %s!", chosen.amount, chosen.name)
                    else
                      reward_msg = "You got " .. chosen.name .. "!"
                    end
                  end

                  if sfx and sfx.item_get then
                    pcall(Net.play_sound_for_player, player_id, sfx.item_get)
                  end

                  local new_frags = tonumber(ezmemory.get_player_fragments(player_id) or 0) or 0
                  reward_msg = (reward_msg or "Purchase complete.") .. ("\nBugFrags: %d"):format(new_frags)
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
  { id = "__tok_buy_1__",  qty = 1,  price = 20000  },
  { id = "__tok_buy_3__",  qty = 3,  price = 60000  },
  { id = "__tok_buy_5__",  qty = 5,  price = 100000 },
  { id = "__tok_buy_10__", qty = 10, price = 200000 },
  { id = "__tok_buy_30__", qty = 30, price = 600000 },
  { id = "__tok_buy_50__", qty = 50, price = 1000000 },
  { id = "__tok_buy_100__", qty = 100, price = 2000000 },
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
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
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
          local stats = await(ezencounters.begin_encounter(player_id, bossX))
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
          local area_id = Net.get_player_area(player_id)
          pcall(Net.set_song, area_id, JUKEBOX_SONG_PREFIX .. chosen.file)
        end

        local confirm = await(Async.question_player(
          player_id,
          ("Buy \"%s\" for %sz?"):format(chosen.base, tostring(price)),
          mug.texture_path, mug.animation_path
        ))

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
