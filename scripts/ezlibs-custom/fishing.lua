-- /server/scripts/ezlibs-custom/fishing.lua
-- Fishing mini-game + FishBBS (Top 10 heaviest)
-- Everything in one file.

-- ====================== Requires ======================
local helpers      = require('scripts/ezlibs-scripts/helpers')
local ezmemory     = require('scripts/ezlibs-scripts/ezmemory')
local ezencounters = require('scripts/ezlibs-scripts/ezencounters/main')
local config = require('scripts/fishing-config/main')
local Constants = config.CONSTANTS
local NetGames     = require('scripts/net-games/framework')

-- Per-area resolvers (fallback to defaults if not defined)
local function _C_for(area_id)
  return (config.get_constants_for_area and config.get_constants_for_area(area_id)) or Constants
end
local function _V_for(area_id)
  return (config.get_viruses_for_area and config.get_viruses_for_area(area_id)) or config.FISHING_VIRUS
end

local okJobBBS, JobBBS = pcall(require, 'scripts/jobbbs/JobBBS')
if not okJobBBS then JobBBS = nil end

local okTeams, Teams = pcall(require, 'scripts/teams/teams')
if not okTeams then Teams = nil end


-- Resolve Async if not global
local function _resolve_async()

  if _G and _G.Async then return _G.Async end
  local ok, A = pcall(require, 'scripts/ezlibs-scripts/async')
  if ok and A then return A end
  return _G.Async
end

local function _now_s()
  return tonumber(os.time()) or 0
end

local Async        = _resolve_async()
-- Online presence cache so we can exclude for current non-owners
local AREA_PLAYERS = {} -- [area_id] = { [pid]=true, ... }
local PLAYER_AREA  = {} -- [pid] = area_id

-- ====================== Config you can edit ======================
local FISHING      = {

  -- Net-Games HUD fish meter (screen-space)
  -- Coordinates are in net-games' 240x160 virtual screen:
  --   X: 0 (left)  →  240 (right)
  --   Y: 0 (top)   →  160 (bottom)
  UI_METER = {
    X = 155,   -- horizontal center by default
    Y = 30,   -- near bottom of the screen
    SCALE = 2.0, -- sprite scale (2.0 = default net-games scale)
  },

  UI_TIMER = {
    X     = 70,  -- center-ish; tweak as you like
    Y     = 2,   -- a bit below the fish meter (which is at Y=20)
    SCALE = 2.0,  -- same scale as fish meter by default
  },
  
  -- Hidden layer where your meter prototype objects live
  TEMPLATE_LAYER         = Constants.TEMPLATE_LAYER,
  HOLD_SECONDS           = Constants.HOLD_SECONDS,
  FORCE_METER_DIMS_PX    = Constants.FORCE_METER_SIZE,
  EXPECTED_METER_DIMS_PX = Constants.EXPECTED_METER_SIZE,
  DEBUG                  = Constants.DEBUG,
  PRIVATE_METERS         = Constants.PRIVATE_METERS,
  PRIVATE_MODE           = "exclude",
  RESULTS_CALLBACK       = _default_fishing_rewards,

  -- Placement around the player
  METER_FORWARD          = 0,   -- a little in front of facing
  METER_SIDE             = 0,   -- "left" | "right" | number (tiles). If number, exact side offset (tiles).
  METER_DISTANCE         = 0.8, -- legacy fallback; kept for compatibility

  -- Extra world-space nudge after facing/side placement (tiles).
  -- Positive y moves the meter lower on the screen.
  METER_SCREEN_SHIFT     = Constants.METER_SCREEN_SHIFT,

  -- Total time window to hook the fish
  MAX_DURATION_S         = Constants.MAX_DURATION_S,

  -- Time you must hold inside the sweet band to succeed
  HOLD_RANGE_S           = Constants.SUCCESS_RANGE,

  -- Sweet spot width: number of consecutive pips that count as "sweet"
  SWEET_WIDTH            = Constants.SWEET_WIDTH, -- e.g., 2 means [4..5] or [7..8], always within 1..9

  -- Heaviness presets (higher decay = harder; mash is how much each A tap helps)
  HEAVINESS              = Constants.HEAVINESS,

  -- Odds for each heaviness tier
  HEAVINESS_CHANCES      = Constants.HEAVINESS_CHANCES,

  -- Display-only: random weight ranges (in pounds) per heaviness
  WEIGHT_RANGES_LB       = Constants.WEIGHT_RANGES_LB,

  -- Leaderboard persistence (stored under this area)
  LEADERBOARD            = {
    MEM_AREA = "fisharea", -- << your fishing zone
    KEY      = "fish_top10_v4",
    MAX      = 10,
    UNIQUE_PER = "secret",  -- or "name" if you prefer name-based uniqueness
  },

  -- Timer meter (0..5 phases), horizontal bar above the player.
  -- Fill these GIDs to match your "Fishing" layer objects for the timer bar.
  METERS_TIMER           = {
    [0] = 299, -- replace 0 with your gid for empty bar
    [1] = 300,
    [2] = 301,
    [3] = 302,
    [4] = 303,
    [5] = 304,
  },

  -- Placement just for the timer meter (independent from fish meter)
  TIMER_FORWARD          = 0.0,                             -- a touch in front of the player (0.0 is fine)
  TIMER_SIDE             = 0,                               -- 0 keeps it centered; can be "left"/"right" or a number
  TIMER_SCREEN_SHIFT     = Constants.TIMER_SCREEN_SHIFT, -- y<0 draws above the player

  -- Optional size enforcement for the timer bar (pixels -> tiles; isometric-safe)
  FORCE_TIMER_DIMS_PX    = Constants.FORCE_TIMER_SIZE,                -- e.g., { w = 91, h = 17 } if your timer is 91x17 px
  EXPECTED_TIMER_DIMS_PX =  Constants.EXPECTED_TIMER_SIZE, -- e.g., { w = 91, h = 17 } to auto-correct if it ever drifts

  -- Optional sfx paths (set to nil if not wanted)
  SFX                    = {
    start        = "/server/assets/ezlibs-assets/sfx/select.ogg",
    catch        = "/server/assets/ezlibs-assets/sfx/item_get.ogg",
    fail         = "/server/assets/ezlibs-assets/sfx/cancel.ogg",
    increment    = "/server/assets/sfx/GuageRise.ogg",
    alert        = "/server/assets/sfx/Alert.ogg",
    tick         = nil,
  },

  VIRUS_CHANCE           = Constants.VIRUS_CHANCE, -- 30 percent for eligible tiers
  VIRUS_EXCLUDED         = Constants.VIRUS_EXCLUDED,

  -- Fishing virus encounters - you can edit or add more
  -- These are self-contained encounter infos passed to ezencounters
  VIRUS_ENCOUNTERS       = config.FISHING_VIRUS,
  -- Money per pound for normal fish (not viruses)
  FISH_REWARD_PER_LB     = Constants.FISH_REWARD_PER_LB, -- edit to taste

  -- Waiting phase: bite indicator (public, visible to everyone)
  BITE                   = {
    -- Fill these with your GIDs (two frames: idle + bite flash)
    GIDS             = {
      idle = 0,   -- e.g., 310
      bite = 305, -- e.g., 311
    },
    -- Placement controls (separate from fish/timer meters)
    FORWARD          = 0.0,
    SIDE             = 0,                               -- number or "left"/"right"
    SCREEN_SHIFT     = Constants.EX_SCREEN_SHIFT, -- above player a little

    -- Optional size enforcement just for the bite icon
    FORCE_DIMS_PX    = Constants.FORCE_EX_SIZE, -- e.g., { w=32, h=32 }
    EXPECTED_DIMS_PX = Constants.EXPECTED_EX_SIZE,

    -- Random wait before a bite shows up
    WAIT_RANGE_S     = Constants.BITE_WAIT_RANGE,

    -- Window to press A when it bites (heavier = shorter)
    WINDOW_S         = Constants.WINDOW_S,

    -- Optional sfx on bite popup
    SFX_BITE         = "/server/assets/sfx/WaterDeepSplash.ogg",
  },

  BAIT = {
    ITEM_NAME = "bait",
    VIRUS_CHANCE = (Constants.BAIT and Constants.BAIT.VIRUS_CHANCE) or 0.10,
    HEAVINESS_CHANCES = (Constants.BAIT and Constants.BAIT.HEAVINESS_CHANCES) or {
      light=20, medium=20, heavy=20, very_heavy=15, brutal=15, legendary=10
    },
  },
  BUGFRAG = {
    ITEM_NAME = (Constants.BUGFRAG and Constants.BUGFRAG.ITEM_NAME) or "bugfrag",
    VIRUS_CHANCE = (Constants.BUGFRAG and Constants.BUGFRAG.VIRUS_CHANCE) or 0.60,
    HEAVINESS_CHANCES = (Constants.BUGFRAG and Constants.BUGFRAG.HEAVINESS_CHANCES) or
      { light=30, medium=30, heavy=30, very_heavy=4, brutal=4, legendary=2 },
  },
}

-- ====================== Minimal TMX helpers ======================
local FLIP_H       = 0x80000000
local FLIP_V       = 0x40000000
local FLIP_D       = 0x20000000

local function decode_gid_flags(raw)
  local g = tonumber(raw or 0) or 0
  local fh = false; if g >= FLIP_H then
    fh = true; g = g - FLIP_H
  end
  local fv = false; if g >= FLIP_V then
    fv = true; g = g - FLIP_V
  end
  local fr = false; if g >= FLIP_D then
    fr = true; g = g - FLIP_D
  end
  return g, fh, fv, fr
end

local function gid_base(raw_gid)
  return select(1, decode_gid_flags(raw_gid))
end

local function _tmx_flip_flags_from_layer(area_id, layer_name, base_gid)
  if not layer_name or layer_name == "" then return nil end
  local ok, xml = pcall(Net.map_to_string, area_id)
  if not ok or type(xml) ~= "string" then return nil end

  local body = nil
  for attrs, content in xml:gmatch('<objectgroup%s+([^>]*)>([%s%S]-)</objectgroup>') do
    local name = attrs:match('name="([^"]+)"')
    if name == layer_name then
      body = content; break
    end
  end
  if not body then return nil end

  for obj_tag in body:gmatch('<object%s+[^>]*>') do
    local ogid = tonumber(obj_tag:match('gid="(%d+)"') or "")
    if ogid then
      local g, fh, fv, fr = decode_gid_flags(ogid)
      if g == base_gid then
        return fh, fv, fr
      end
    end
  end
  return nil
end

local function find_prototype_for_gid(area_id, target_gid)
  target_gid = tonumber(target_gid or 0)
  if not target_gid or target_gid <= 0 then return nil end
  local ids = Net.list_objects(area_id) or {}
  for _, oid in ipairs(ids) do
    local o = Net.get_object_by_id(area_id, oid)
    local gid = o and o.data and tonumber(o.data.gid)
    if gid and gid == target_gid and o.width and o.height then
      return o
    end
  end
  return nil
end

local function _tmx_read_map_tilesize(xml)
  -- Only read from the <map ...> tag
  local map_tag = xml:match("<map%s+[^>]*>")
  if not map_tag then return 0, 0 end
  local tw = tonumber(map_tag:match('tilewidth="([%d%.]+)"')) or 0
  local th = tonumber(map_tag:match('tileheight="([%d%.]+)"')) or 0
  return tw, th
end

local function get_template_dims_from_layer(area_id, layer_name, gid)
  local ok_xml, xml = pcall(Net.map_to_string, area_id)
  if not ok_xml or type(xml) ~= "string" then return nil, nil end
  local tw, th = _tmx_read_map_tilesize(xml)
  if tw <= 0 or th <= 0 then return nil, nil end

  local body = nil
  for attrs, content in xml:gmatch('<objectgroup%s+([^>]*)>([%s%S]-)</objectgroup>') do
    local name = attrs:match('name="([^"]+)"')
    if name == layer_name then
      body = content; break
    end
  end
  if not body then return nil, nil end

  local want = tonumber(gid)
  local best_wt, best_ht = nil, nil
  for obj_tag in body:gmatch('<object%s+[^>]*>') do
    local ogid = tonumber(obj_tag:match('gid="(%d+)"') or "")
    local wpx  = tonumber(obj_tag:match('width="([%d%.]+)"') or "") or 0
    local hpx  = tonumber(obj_tag:match('height="([%d%.]+)"') or "") or 0
    if wpx > 0 and hpx > 0 then
      local wt, ht = (wpx / tw), (hpx / th)
      if want and ogid and ogid == want then return wt, ht end
      if not best_wt then best_wt, best_ht = wt, ht end
    end
  end
  return best_wt, best_ht
end

local function get_gid_dims_in_tiles(area_id, gid)
  local ok_ts, ts = pcall(Net.get_tileset_for_tile, area_id, gid)
  local ok_map, xml = pcall(Net.map_to_string, area_id)
  if not ok_ts or not ts or not ok_map or type(xml) ~= "string" then return nil, nil end
  local map_tw, map_th = _tmx_read_map_tilesize(xml); if map_tw == 0 or map_th == 0 then return nil, nil end
  local tile_px_w = tonumber(ts.tile_width or ts.tilewidth or ts.tileWidth)
  local tile_px_h = tonumber(ts.tile_height or ts.tileheight or ts.tileHeight)
  if not tile_px_w or not tile_px_h then return nil, nil end
  return (tile_px_w / map_tw), (tile_px_h / map_th)
end

local function resolve_object_dims(area_id, template_layer_name, gid)
  local proto = find_prototype_for_gid(area_id, gid)
  if proto then return tonumber(proto.width) or 1, tonumber(proto.height) or 1, "proto" end
  local wt, ht = get_template_dims_from_layer(area_id, template_layer_name, gid)
  if wt and ht then return wt, ht, "tmx" end
  local gw, gh = get_gid_dims_in_tiles(area_id, gid)
  if gw and gh then return gw, gh, "tileset" end
  return 1, 1, "default"
end

local function resolve_preview_flip_flags(area_id, template_layer_name, base_gid, def_fh, def_fv, def_fr)
  local proto = find_prototype_for_gid(area_id, base_gid)
  if proto and proto.data then
    local td = proto.data
    return td.flipped_horizontally or false,
        td.flipped_vertically or false,
        td.rotated or false
  end
  local try_layers = { template_layer_name, "Object Layer 1", "Object Layer 2" }
  for _, lname in ipairs(try_layers) do
    local fh, fv, fr = _tmx_flip_flags_from_layer(area_id, lname, base_gid)
    if fh ~= nil then return fh, fv, fr end
  end
  return def_fh, def_fv, def_fr
end

-- ====================== Placement helpers ======================
local function get_cursor_point(player_id, dist)
  local ok_pos, pos = pcall(Net.get_player_position, player_id)
  if not ok_pos or not pos then return nil end
  local dx, dy = 0, 1
  local ok_dir, dir = pcall(Net.get_player_direction, player_id)
  local function dir_to_offset(dirName)
    if dirName == "Left" then
      return -1, 0
    elseif dirName == "Right" then
      return 1, 0
    elseif dirName == "Up" then
      return 0, -1
    elseif dirName == "Down" then
      return 0, 1
    elseif dirName == "Up Left" then
      return -1, -1
    elseif dirName == "Up Right" then
      return 1, -1
    elseif dirName == "Down Left" then
      return -1, 1
    elseif dirName == "Down Right" then
      return 1, 1
    else
      return 0, 1
    end
  end
  if ok_dir and dir then
    dx, dy = dir_to_offset(dir)
    if dx ~= 0 and dy ~= 0 then
      local inv = 1 / math.sqrt(2); dx, dy = dx * inv, dy * inv
    end
  end
  return pos.x + dx * dist, pos.y + dy * dist, (pos.z or 0)
end

local function get_offset_point(player_id, forward_dist, side_spec, side_default)
  local ok_pos, pos = pcall(Net.get_player_position, player_id)
  if not ok_pos or not pos then return nil end

  local function dir_to_offset(dirName)
    if dirName == "Left" then
      return -1, 0
    elseif dirName == "Right" then
      return 1, 0
    elseif dirName == "Up" then
      return 0, -1
    elseif dirName == "Down" then
      return 0, 1
    elseif dirName == "Up Left" then
      return -1, -1
    elseif dirName == "Up Right" then
      return 1, -1
    elseif dirName == "Down Left" then
      return -1, 1
    elseif dirName == "Down Right" then
      return 1, 1
    else
      return 0, 1
    end
  end

  local ok_dir, dir = pcall(Net.get_player_direction, player_id)
  local fdx, fdy = dir_to_offset(ok_dir and dir or "Down")
  if fdx ~= 0 and fdy ~= 0 then
    local inv = 1 / math.sqrt(2); fdx, fdy = fdx * inv, fdy * inv
  end
  -- Perpendicular “right” vector (clockwise 90°)
  local rdx, rdy = fdy, -fdx

  local side = 0
  if type(side_spec) == "number" then
    side = side_spec
  elseif tostring(side_spec) == "left" then
    side = -(side_default or 2.0)
  else
    side = (side_default or 2.0) -- "right" or anything else
  end

  return pos.x + fdx * forward_dist + rdx * side,
      pos.y + fdy * forward_dist + rdy * side,
      (pos.z or 0)
end

-- ====================== Runtime state ======================
local SESS = {} -- [pid] = session
-- session fields:
--   area_id, started_at, last_pos {x,y,z}, active,
--   meter_color, meter_phase (0..10), meter_value (float), meter_oid,
--   sweet_lo, sweet_hi, hold_req, hold_accum,
--   heaviness, weight_lb, decay, mashGain, taps

-- ====================== Utility ======================
local function _play(pid, path)
  if not path or path == "" then return end
  pcall(Net.play_sound_for_player, pid, path)
end

local function _clamp(v, a, b) if v < a then return a elseif v > b then return b else return v end end

-- ====================== Leaderboard helpers ======================
local function _lb_bucket()
  local area = (FISHING.LEADERBOARD and FISHING.LEADERBOARD.MEM_AREA) or "fisharea"
  local key  = (FISHING.LEADERBOARD and FISHING.LEADERBOARD.KEY) or "fish_top10"
  local mem  = ezmemory.get_area_memory(area) or {}
  mem[key]   = mem[key] or {}
  return mem, mem[key], area, key
end

-- Insert a catch, sort desc by weight, trim to MAX. Returns rank (1-based) if in top MAX.
local function _record_catch(pid, weight_lb)
  if not weight_lb then return nil end
  local name = nil
  pcall(function() name = Net.get_player_name(pid) end)
  name = name or tostring(pid)

  local mem, list, area = _lb_bucket()
  local rec = { weight = tonumber(weight_lb) or 0, player_name = tostring(name), pid = tostring(pid), ts = os.time() }
  table.insert(list, rec)
  table.sort(list, function(a, b) return (a.weight or 0) > (b.weight or 0) end)
  local maxn = (FISHING.LEADERBOARD and FISHING.LEADERBOARD.MAX) or 10
  while #list > maxn do table.remove(list) end

  local rank = nil
  for i, r in ipairs(list) do
    if r == rec then
      rank = i; break
    end
  end
  ezmemory.save_area_memory(area)
  return rank
end

local function _map_info(xml)
  local map_tag = xml:match("<map%s+[^>]*>")
  if not map_tag then return "orthogonal", 32, 32 end
  local orient = map_tag:match('orientation="([^"]+)"') or "orthogonal"
  local tw = tonumber(map_tag:match('tilewidth="([%d%.]+)"')) or 32
  local th = tonumber(map_tag:match('tileheight="([%d%.]+)"')) or 32
  return orient, tw, th
end

local function _px_to_tiles(area_id, w_px, h_px)
  local ok, xml = pcall(Net.map_to_string, area_id)
  if not ok or type(xml) ~= "string" then return 1, 1 end
  local orient, tw, th = _map_info(xml)

  -- Use tileheight for BOTH axes on isometric maps (and any non-square tile sets).
  local basis = (orient == "isometric" or tw ~= th) and th or tw

  local wt = (tonumber(w_px) or 0) / basis
  local ht = (tonumber(h_px) or 0) / basis
  if wt <= 0 then wt = 1 end
  if ht <= 0 then ht = 1 end

  if FISHING.DEBUG then
    print(("[fishing] px->tiles using basis=%d (orient=%s tw=%d th=%d): %dx%d px -> %.3fx%.3f tiles")
      :format(basis, orient, tw, th, tonumber(w_px) or 0, tonumber(h_px) or 0, wt, ht))
  end
  return wt, ht
end

-- Size resolver for the timer bar; mirrors your fish resolver but uses timer-specific overrides.
local function _resolve_timer_dims(area_id, layer_name, base_gid)
  -- Force override (pixels -> tiles) if configured
  local forced = FISHING.FORCE_TIMER_DIMS_PX
  if forced and forced.w and forced.h then
    local w, h = _px_to_tiles(area_id, forced.w, forced.h)
    if FISHING.DEBUG then
      print(("[fishing] TIMER FORCE dims px %dx%d -> tiles %.3fx%.3f (gid=%s)")
        :format(forced.w, forced.h, w, h, tostring(base_gid)))
    end
    return w, h, "forced"
  end

  -- Fallback to your existing pipeline (proto -> tmx -> tileset)
  local w, h, src = resolve_object_dims(area_id, layer_name, base_gid)

  -- Expected override (auto-correct if mismatch)
  local exp = FISHING.EXPECTED_TIMER_DIMS_PX
  if exp and exp.w and exp.h then
    local ew, eh = _px_to_tiles(area_id, exp.w, exp.h)
    local dw = math.abs((tonumber(w) or 0) - ew) / (ew == 0 and 1 or ew)
    local dh = math.abs((tonumber(h) or 0) - eh) / (eh == 0 and 1 or eh)
    if dw > 0.15 or dh > 0.15 then
      if FISHING.DEBUG then
        print(("[fishing] TIMER auto-correct size %.3fx%.3f -> %.3fx%.3f (from %dx%d px)")
          :format(tonumber(w) or -1, tonumber(h) or -1, ew, eh, exp.w, exp.h))
      end
      w, h, src = ew, eh, "expected"
    end
  end

  if FISHING.DEBUG then
    print(("[fishing] TIMER dims (%s) -> tiles: %.3fx%.3f (gid=%s)")
      :format(tostring(src), tonumber(w) or -1, tonumber(h) or -1, tostring(base_gid)))
  end
  return tonumber(w) or 1, tonumber(h) or 1, src
end

-- Get current occupants of an area (server API: Net.list_players(area_id))
local function _players_in_area(area_id)
  local ok, pids = pcall(Net.list_players, area_id)
  if ok and type(pids) == "table" then return pids end
  return {}
end

-- Exclude the object for everyone in the area except the owner,
-- and remember it till they disconnect (so it stays hidden for them).
local function _exclude_for_non_owners(owner_pid, area_id, object_id)
  if not (FISHING.PRIVATE_METERS and area_id and object_id) then return end
  for _, pid in ipairs(_players_in_area(area_id)) do
    if pid ~= owner_pid then
      -- Immediate hide now…
      pcall(Net.exclude_object_for_player, pid, object_id)
      -- …and remember till they leave this session
      pcall(ezmemory.hide_object_from_player_till_disconnect, pid, area_id, object_id)
    end
  end
end

-- Include an object for the owner only
local function _include_for_owner(owner_pid, object_id)
  if not (FISHING.PRIVATE_METERS and owner_pid and object_id) then return end
  pcall(Net.include_object_for_player, owner_pid, object_id)
end

-- On join/transfer, hide any existing meters not owned by the joiner
local function _hide_existing_meters_for_joiner(ev)
  if not FISHING.PRIVATE_METERS then return end
  local pid = ev.player_id
  local aid = ev.to_area_id or ev.area_id or Net.get_player_area(pid)
  if not aid then return end

  local list = Net.list_objects(aid) or {}
  for _, oid in ipairs(list) do
    local o = Net.get_object_by_id(aid, oid)
    if o then
      local cp = o.custom_properties or {}
      local is_meter =
          (o.class == "FishingMeter") or (tostring(cp.fishing_meter or "") == "true") or
          (o.class == "FishingTimer") or (tostring(cp.fishing_timer or "") == "true")
      if is_meter and tostring(cp.fishing_pid or "") ~= tostring(pid) then
        -- Hide right now for the joiner…
        pcall(Net.exclude_object_for_player, pid, oid)
        -- …and also persist for this session
        pcall(ezmemory.hide_object_from_player_till_disconnect, pid, aid, oid)
        if FISHING.DEBUG then
          print(("[fishing] joiner hide oid=%s owner=%s for pid=%s"):format(tostring(oid), tostring(cp.fishing_pid or ""),
            tostring(pid)))
        end
      end
    end
  end
end

-- Exclude for everyone except the owner, both immediately and again one tick later.
local function _exclude_for_non_owners(owner_pid, area_id, object_id)
  if not (FISHING.PRIVATE_METERS and area_id and object_id) then return end

  local function do_exclude()
    local ok, pids = pcall(Net.list_players, area_id)
    if not ok or type(pids) ~= "table" then return end
    local n = 0
    for _, pid in ipairs(pids) do
      if pid ~= owner_pid then
        -- direct per-player hide (works even if ezmemory path fails)
        pcall(Net.exclude_object_for_player, pid, object_id)
        -- also persist till disconnect so later updates keep it hidden
        pcall(ezmemory.hide_object_from_player_till_disconnect, pid, area_id, object_id)
        n = n + 1
      end
    end
    if FISHING.DEBUG then
      print(("[fishing] excluded for %d non-owners (oid=%s area=%s)"):format(n, tostring(object_id), tostring(area_id)))
    end
  end

  -- exclude right now…
  do_exclude()
  -- …and again after a short delay so the client has definitely registered the object
  async(function()
    await(Async.sleep(0.05)) -- ~1 tick
    do_exclude()
  end)
end

-- === Hardcoded asset lookup (no layer objects required) ===
-- Directory layout you described:
--   METERS.normal:      /server/assets/fishing/blue/0.tsx .. 10.tsx (and .png)
--   METERS.sweet_spot:  /server/assets/fishing/yellow/0.tsx .. 10.tsx
--   TIMER phases:       prefer /server/assets/fishing/timer/0.tsx .. 5.tsx (fallbacks below)
--   BITE (flash):       /server/fishing/ex.tsx   (fallback: /server/assets/fishing/ex.tsx)

local fishingDir   = Constants.ASSET_FISHING_DIR
local exPath       = Constants.D_BITE_TSX_CANIDATE
local exTsx        = Constants.EX_ALERT_TSX
-- Try a timer/ subdir first; fall back to reusing blue/ if that’s how you stored them.
local ASSET_TIMER_DIRS    = { timerDir, normalDir }
-- Bite candidates (support both paths you mentioned)
local BITE_TSX_CANDIDATES = { exPath, fishingDir .. exTsx }

-- Parse TMX once per call; keyed by lowercase, slash-normalized source path
local function _tilesets_by_source(area_id)
  local ok, xml = pcall(Net.map_to_string, area_id)
  if not ok or type(xml) ~= "string" then return {} end
  local out = {}
  for firstgid, src in xml:gmatch('<tileset%s+[^>]-firstgid="(%d+)"[^>]-source="([^"]+)"[^>]*/>') do
    local tail = tostring(src):gsub("\\","/"):lower()
    out[tail] = tonumber(firstgid)
  end
  return out
end

-- Find firstgid for a TSX by matching the end of its path (robust to relative prefixes)
local function _gid_for_tsx(area_id, tsx_path)
  if not tsx_path or tsx_path == "" then return 0 end
  local tail = tostring(tsx_path):gsub("\\","/"):lower()
  local ts = _tilesets_by_source(area_id)
  for src, first in pairs(ts) do
    if src:sub(-#tail) == tail then
      return tonumber(first) or 0
    end
  end
  return 0
end

local function _meter_sheet_paths(area_id)
  local C = _C_for(area_id)

  local png  = (C and C.ASSET_FISH_PNG)  or (FISHING.ASSET_FISH_PNG)
  local anim = (C and C.ASSET_FISH_ANIM) or (FISHING.ASSET_FISH_ANIM)

  if not png or png == "" or not anim or anim == "" then
    print("[fishing] missing fish meter assets for area:", area_id, png or "nil", anim or "nil")
    return nil, nil
  end

  return png, anim
end

-- Resolve PNG path for the HUD timer using per-area constants (like the old TSX logic)
local function _timer_png_path(phase)
  phase = tonumber(phase or 0) or 0
  return "/server/assets/fishing/timer/" .. tostring(phase) .. ".png"
end

-- Timer (0..5), prefer timer/ then fallback to normal/
local function _timer_gid_from_assets(area_id, phase)
  phase = tonumber(phase or 0) or 0
  local C = _C_for(area_id)
  local fishingDir = C.ASSET_FISHING_DIR
  local dirs = {
    fishingDir .. C.ASSET_TIMER_DIR,
    fishingDir .. C.ASSET_NORMAL_DIR,
  }
  for _, d in ipairs(dirs) do
    local gid = _gid_for_tsx(area_id, d .. tostring(phase) .. ".tsx")
    if gid and gid > 0 then return gid end
  end
  return 0
end

-- Bite flash gid from ex.tsx (try file candidates)
local function _bite_gid_from_assets(area_id)
  local C = _C_for(area_id)
  local candidates = {
    C.D_BITE_TSX_CANIDATE,     -- e.g., "/server/fishing/ex.tsx"
    C.ASSET_FISHING_DIR .. C.EX_ALERT_TSX, -- e.g., "/server/assets/fishing/ex.tsx"
  }
  for _, p in ipairs(candidates) do
    local gid = _gid_for_tsx(area_id, p)
    if gid and gid > 0 then return gid end
  end
  return 0
end

-- ---- Bite indicator (public) ----
local function _bite_gid(state, area_id)
  -- Use file-based ex.tsx specifically for the “bite” flash if present
  if state == "bite" then
    local gid = _bite_gid_from_assets(area_id)
    if gid > 0 then return gid end
  end
  -- Fallback to legacy table (idle=0 is fine → nothing displayed)
  local g = FISHING.BITE and FISHING.BITE.GIDS
  return tonumber(g and g[state] or 0) or 0
end

local function _resolve_bite_dims(area_id, base_gid)
  local forced = FISHING.BITE and FISHING.BITE.FORCE_DIMS_PX
  if forced and forced.w and forced.h then
    local w, h = _px_to_tiles(area_id, forced.w, forced.h); return w, h, "forced"
  end
  local w, h, src = resolve_object_dims(area_id, FISHING.TEMPLATE_LAYER, base_gid)
  local exp = FISHING.BITE and FISHING.BITE.EXPECTED_DIMS_PX
  if exp and exp.w and exp.h then
    local ew, eh = _px_to_tiles(area_id, exp.w, exp.h)
    local dw = math.abs((tonumber(w) or 0) - ew) / (ew == 0 and 1 or ew)
    local dh = math.abs((tonumber(h) or 0) - eh) / (eh == 0 and 1 or eh)
    if dw > 0.15 or dh > 0.15 then w, h, src = ew, eh, "expected" end
  end
  return tonumber(w) or 1, tonumber(h) or 1, src
end

local function _spawn_or_update_bite(pid)
  local s = SESS[pid]; if not s or not s.active then return end
  if s.phase ~= "waiting" then return end
  local area_id = s.area_id; if not area_id then return end

  local state = s.bite_state or "idle"
  local raw_gid = _bite_gid(state, area_id)

  -- If idle has gid=0 (your choice), hard-despawn so nothing lingers
  if raw_gid == 0 then
    if s.bite_oid then
      pcall(function() Net.remove_object(area_id, s.bite_oid) end)
      s.bite_oid = nil
      if FISHING.DEBUG then print("[fishing] bite: despawn (idle=0)") end
    end
    return
  end

  local base_gid   = gid_base(raw_gid)
  local fh, fv, fr = resolve_preview_flip_flags(area_id, FISHING.TEMPLATE_LAYER, base_gid, false, false, false)
  local w, h       = _resolve_bite_dims(area_id, base_gid)

  local forward    = (FISHING.BITE and FISHING.BITE.FORWARD) or 0.0
  local side       = (FISHING.BITE and FISHING.BITE.SIDE)
  local x, y, z    = get_offset_point(pid, forward, side or 0, 0)
  if not x then return end
  do
    local sh = (FISHING.BITE and FISHING.BITE.SCREEN_SHIFT) or {}
    x = x + (sh.x or 0); y = y + (sh.y or 0); z = z + (sh.z or 0)
  end

  if FISHING.DEBUG then
    print(("[fishing] bite spawn/update: state=%s gid=%d dims=%.3fx%.3f pos=(%.2f,%.2f,%.2f)")
      :format(state, base_gid, w, h, x, y, z))
  end

  local data = { type = "tile", gid = base_gid, flipped_horizontally = fh, flipped_vertically = fv, rotated = fr }
  local spec = {
    name = "",
    class = "FishingBite",
    visible = true,
    x = x,
    y = y,
    z = z,
    width = w,
    height = h,
    rotation = 0,
    data = data,
    custom_properties = { fishing_bite = "true", fishing_pid = tostring(pid or "") }
  }

  local must_recreate = false
  if not s.bite_oid then
    must_recreate = true
  else
    local cur = Net.get_object_by_id(area_id, s.bite_oid)
    if not cur then
      must_recreate = true
    else
      local cw = tonumber(cur.width) or 0; local ch = tonumber(cur.height) or 0
      if math.abs(cw - w) > 0.001 or math.abs(ch - h) > 0.001 then must_recreate = true end
    end
  end

  if must_recreate then
    if s.bite_oid then pcall(function() Net.remove_object(area_id, s.bite_oid) end) end
    local ok, res = pcall(Net.create_object, area_id, spec)
    if not ok then
      -- retry on template layer
      spec.layer = FISHING.TEMPLATE_LAYER
      ok, res = pcall(Net.create_object, area_id, spec)
      if not ok then
        if FISHING.DEBUG then
          print("[fishing] bite create failed twice (check GID/tileset/layer).")
        end
        return
      end
    end
    s.bite_oid = res
  else
    local ok1 = pcall(Net.move_object, area_id, s.bite_oid, x, y, z)
    local ok2 = pcall(Net.set_object_data, area_id, s.bite_oid, data)
    if FISHING.DEBUG and (not ok1 or not ok2) then
      print("[fishing] bite update failed (move/data).")
    end
  end
end

local function _despawn_bite(pid)
  local s = SESS[pid]; if not s then return end
  if s.bite_oid then
    pcall(function() Net.remove_object(s.area_id, s.bite_oid) end); s.bite_oid = nil
  end
end

-- Tracks all areas where we have spawned a FishingMeter for a given player
local _PID_AREAS = {} -- pid -> { [area_id]=true, ... }

-- ====================== Meter Preview ======================
local function _timer_gid(area_id, phase)
  local gid = _timer_gid_from_assets(area_id, phase)
  if gid == 0 then
    local t = FISHING.METERS_TIMER or {}
    gid = tonumber(t[phase or 0] or 0) or 0
  end
  return gid
end

-- ====================== Net-Games Fish Meter (HUD) ======================

local METER_SPRITE_ID = "fishing_meter_hud"

-- Give each different meter sheet its own sprite_id so NetGames
-- doesn't keep reusing the very first one it allocated.
local function _meter_sprite_id_for_sheet(png_path)
  local key = tostring(png_path or "default")
  -- sanitize path into something sprite_id-safe
  key = key:gsub("[^%w]+", "_")
  return METER_SPRITE_ID .. "_" .. key
end

local function _spawn_or_update_meter(pid)
  local s = SESS[pid]; if not s or not s.active then return end

  ------------------------------------------------------------------
  -- 1) Only show meter during the reeling phase
  ------------------------------------------------------------------
  if s.phase ~= "reeling" then
    if s.meter_ui_id then
      pcall(NetGames.remove_ui_element, s.meter_ui_id, pid)
      s.meter_ui_id    = nil
      s.meter_ui_state = nil
      s.meter_ui_sheet = nil
      s.meter_ui_anim  = nil
    end
    return
  end

  ------------------------------------------------------------------
  -- 2) Resolve area + sprite sheet
  ------------------------------------------------------------------
  local area_id = s.area_id or Net.get_player_area(pid)
  if not area_id then return end

  local png_path, anim_path = _meter_sheet_paths(area_id)
  if not png_path or not anim_path then
    return -- no assets for this area
  end

  -- NEW: derive sprite_id from the sheet path so each design is separate
  local sprite_id = _meter_sprite_id_for_sheet(png_path)

  ------------------------------------------------------------------
  -- 3) Compute current state name (NORMAL_0..10 or SWEET_0..10)
  --    (same logic you already had, using s.meter_phase)
  ------------------------------------------------------------------
  local phase = tonumber(s.meter_phase or 0) or 0
  phase = _clamp(phase, 0, 10)

  local color_tag = (s.meter_color == "sweet_spot") and "SWEET" or "NORMAL"
  local state     = string.format("%s_%d", color_tag, phase)

  ------------------------------------------------------------------
  -- 4) HUD position / scale (screen-space)
  ------------------------------------------------------------------
  local hud   = FISHING.UI_METER or {}
  local X     = tonumber(hud.X) or 160
  local Y     = tonumber(hud.Y) or 20
  local scale = tonumber(hud.SCALE) or 2.0

  ------------------------------------------------------------------
  -- 5) Allocate sprite with animation when sheet/anim/sprite_id changes
  --    (first time in, or when moving between fisharea/rink/rink2)
  ------------------------------------------------------------------
  local sheet_changed =
      (s.meter_ui_sheet ~= png_path) or
      (s.meter_ui_anim  ~= anim_path) or
      (s.meter_ui_id    ~= sprite_id)

  if sheet_changed or not s.meter_ui_id then
    -- Zap old HUD object if any (cleans up old sheet)
    if s.meter_ui_id then
      pcall(NetGames.remove_ui_element, s.meter_ui_id, pid)
    end

    -- This call matches the order_points demo:
    -- games.add_ui_element("id", pid, png, anim, state, X, Y, Z, sx, sy)
    NetGames.add_ui_element(
      sprite_id,
      pid,
      png_path,
      anim_path,
      state,
      X, Y, 0,
      scale, scale
    )

    s.meter_ui_id    = sprite_id
    s.meter_ui_sheet = png_path
    s.meter_ui_anim  = anim_path
    s.meter_ui_state = state
    return
  end

  ------------------------------------------------------------------
  -- 6) Same sheet/anim: just change animation state if needed
  ------------------------------------------------------------------
  if s.meter_ui_state ~= state then
    NetGames.set_ui_animation(s.meter_ui_id, pid, state)
    s.meter_ui_state = state
  end
end

local function _despawn_meter(pid)
  local s = SESS[pid]; if not s then return end

  if s.meter_ui_id then
    pcall(NetGames.remove_ui_element, s.meter_ui_id, pid)
  end

  s.meter_ui_id    = nil
  s.meter_ui_phase = nil
  s.meter_ui_color = nil
  s.meter_ui_area  = nil
end

local function _spawn_or_update_timer(pid)
  local s = SESS[pid]; if not s or not s.active then return end

  -- Only show timer during the reeling phase
  if s.phase ~= "reeling" then
    -- Let the centralized despawner handle cleanup
    _despawn_timer(pid)
    return
  end

  -- We only need area_id for debug / bookkeeping now
  local area_id = s.area_id or Net.get_player_area(pid)
  if not area_id then return end

  -- Clamp timer phase 0..5 to be safe
  local phase = tonumber(s.timer_phase or 0) or 0
  phase = _clamp(phase, 0, 5)

  -- If we’re already showing this phase, do nothing
  if s.timer_ui_phase == phase then
    return
  end

  -- One sprite_id per timer phase across all areas
  local sprite_id    = ("fishing_timer_%d"):format(phase)
  local texture_path = _timer_png_path(phase)

  -- HUD position / scale (like the meter)
  local hud   = FISHING.UI_TIMER or {}
  local X     = tonumber(hud.X) or 160
  local Y     = tonumber(hud.Y) or 40
  local scale = tonumber(hud.SCALE) or 2.0

  local prev_id = s.timer_ui_id

  -- Draw / update this phase’s HUD sprite
  NetGames.add_ui_element(
      sprite_id,
      pid,
      texture_path,
      "",              -- animation_path
      "",              -- animation_state
      X, Y, 0,         -- screen position + Z
      scale,           -- ScaleX
      scale            -- ScaleY
  )

  if FISHING.DEBUG then
    print(("[fishing] TIMER HUD pid=%s area=%s phase=%d sprite_id=%s tex=%s")
      :format(tostring(pid), tostring(area_id), phase, sprite_id, texture_path))
  end

  -- Remove previous phase’s HUD sprite (if any)
  if prev_id and prev_id ~= sprite_id then
    pcall(NetGames.remove_ui_element, prev_id, pid)
  end

  -- Remember what we’re showing now
  s.timer_ui_id    = sprite_id
  s.timer_ui_phase = phase
  s.timer_ui_area  = area_id
end

local function _despawn_timer(pid)
  local s = SESS[pid]
  if not s then return end

  -- Remove HUD timer sprite (Net-Games)
  if s.timer_ui_id then
    pcall(NetGames.remove_ui_element, s.timer_ui_id, pid)
    s.timer_ui_id    = nil
    s.timer_ui_phase = nil
    s.timer_ui_area  = nil
  end

  -- Legacy world-object timer (in case any still exist)
  if s.timer_oid and s.area_id then
    pcall(Net.remove_object, s.area_id, s.timer_oid)
  end
  s.timer_oid = nil
end

-- ====================== Difficulty / weight helpers ======================
local function _random_weight_lb(area_id, key)
  local C = _C_for and _C_for(area_id) or nil
  local r = (C and C.WEIGHT_RANGES_LB and C.WEIGHT_RANGES_LB[key])
        or (FISHING.WEIGHT_RANGES_LB and FISHING.WEIGHT_RANGES_LB[key])
  if not r then return nil end
  local lo, hi = r[1] or 1, r[2] or 1
  return math.floor(((lo + math.random() * (hi - lo)) * 10) + 0.5) / 10
end

-- ====================== Cleanup ======================
local function _cleanup_fishing_meters(area_id, only_pid)
  if not area_id then return end
  local list = Net.list_objects(area_id) or {}
  for _, oid in ipairs(list) do
    local o = Net.get_object_by_id(area_id, oid)
    if o then
      local cp = o.custom_properties or {}
      local is_meter =
          (o.class == "FishingMeter") or (tostring(cp.fishing_meter or "") == "true") or
          (o.class == "FishingTimer") or (tostring(cp.fishing_timer or "") == "true") or
          (o.class == "FishingBite") or (tostring(cp.fishing_bite or "") == "true")
      if is_meter then
        local owner = tostring(cp.fishing_pid or "")
        local kill = false
        if only_pid then
          kill = (owner == tostring(only_pid))
        else
          if owner == "" then
            kill = true
          else
            local ok, _ = pcall(Net.get_player_area, owner)
            if (not ok) or (Net.get_player_area(owner) == nil) then kill = true end
          end
        end
        if kill then pcall(Net.remove_object, area_id, oid) end
      end
    end
  end
end

local function _cleanup_all_for_pid(pid)
  -- Clean in every area we know this player had a meter
  local areas = _PID_AREAS[pid]
  if areas then
    for aid, _ in pairs(areas) do
      pcall(_cleanup_fishing_meters, aid, pid)
    end
    _PID_AREAS[pid] = nil
  else
    -- Fallback: try current area if still available
    local ok, aid = pcall(Net.get_player_area, pid)
    if ok and aid then pcall(_cleanup_fishing_meters, aid, pid) end
  end
end

-- Weighted pick from FISHING.VIRUS_ENCOUNTERS
local function _pick_virus_encounter(area_id)
  local list = _V_for(area_id) or {}
  local total = 0
  for _, e in ipairs(list) do total = total + (e.weight or 1) end
  if total <= 0 then return list[1] end
  local roll = math.random() * total
  for _, e in ipairs(list) do
    roll = roll - (e.weight or 1)
    if roll <= 0 then return e end
  end
  return list[#list]
end

-- Provide mob package once per area
local _ASSET_PROVIDED = {} -- key "area|path" -> true
local function _ensure_asset(area_id, path)
  if not area_id or not path or path == "" then return end
  local key = tostring(area_id) .. "|" .. tostring(path)
  if not _ASSET_PROVIDED[key] then
    pcall(Net.provide_asset, area_id, path)
    _ASSET_PROVIDED[key] = true
  end
end

local function _default_fishing_rewards(player_id, encounter_info, stats)
  -- stats = { health, score, time, ran, emotion, turns, npcs = [...] }
  if not stats or stats.ran then return end -- no rewards if ran

  local aid  = Net.get_player_area(player_id)
  local C    = _C_for(aid)
  local mult = tonumber((C and C.MONEY_MULTIPLYER) or Constants.MONEY_MULTIPLYER or 0) or 0
  local monies = math.floor((stats.score or 0) * mult)
  if monies <= 0 then
    return
  end

  -- Beta 10-style overlay
  local rewards = {
    { type = 0, value = monies },  -- 0 = money
  }

  Net.send_player_battle_rewards(player_id, rewards)

  -- NOTE: no FISHING.SFX.catch here anymore.
  -- The battle reward overlay already plays a sound.
end

if FISHING.RESULTS_CALLBACK == nil then
  FISHING.RESULTS_CALLBACK = _default_fishing_rewards
end

-- When a player closes a message box, we start their queued encounter.
local _PENDING_VIRUS = {} -- pid -> { enc=table, area=string }

local function _queue_virus_battle(pid, enc, area_id)
  _PENDING_VIRUS[pid] = { enc = enc, area = area_id }
  Net.shake_player_camera(pid, 5, 1.5)
  Net.message_player(pid, "Oh no, it's a virus!")
  _play(pid, FISHING.SFX.alert)
end

local function _begin_pending_virus(pid)
  local rec = _PENDING_VIRUS[pid]
  if not rec then return end
  _PENDING_VIRUS[pid] = nil -- guard against double start

  local enc           = rec.enc
  local area          = rec.area
  _ensure_asset(area, enc and enc.path)

  -- hook rewards just like WCity1, but also notify JobBBS
  local inner_cb = FISHING.RESULTS_CALLBACK  -- may be default or custom
  enc.results_callback = function(p, enc_info, stats)
    -- original rewards
    if inner_cb then pcall(inner_cb, p, enc_info, stats) end
    -- JobBBS fishing-virus result
    if JobBBS and JobBBS.on_fish_virus_result then
      pcall(JobBBS.on_fish_virus_result, p, { area = area, stats = stats })
    end
  end

  async(function()
    await(ezencounters.begin_encounter(pid, enc))
  end)
end

-- ====================== Core game loop ======================
local function _stop(pid, msg, sfx)
  local s = SESS[pid]; if not s then return end
  s.active = false
  _despawn_meter(pid)
  _despawn_timer(pid)
  _despawn_bite(pid)
  pcall(_cleanup_fishing_meters, s.area_id, pid) -- sweep this player's meters
  SESS[pid] = nil
  if msg and msg ~= "" then
    if Async and Async.message_player then
      Async.message_player(pid, msg)
    else
      Net.message_player(pid, msg)
    end
  end
  _play(pid, sfx)
end

-- Quietly restart the waiting phase without tearing down the session.
local function _quiet_restart_wait(pid)
  local s = SESS[pid]; if not s or not s.active or s.phase ~= "waiting" then return end
  s.bite_active = false
  s.bite_state  = "idle"
  s.bite_until_rel = 0
  _spawn_or_update_bite(pid)

  -- NEW: resolve per-area wait range
  local aid = s.area_id or Net.get_player_area(pid)
  local C = (aid and _C_for(aid)) or nil
  local rng = (C and C.BITE_WAIT_RANGE) or (FISHING.BITE and FISHING.BITE.WAIT_RANGE_S) or { min = 1.2, max = 3.0 }
  local wmin = tonumber(rng.min or 1.2) or 1.2
  local wmax = tonumber(rng.max or 3.0) or 3.0
  local bite_in = wmin + math.random() * math.max(0, wmax - wmin)

  -- push next bite relative to current wait elapsed
  s.next_bite_at = (s.wait_elapsed or 0) + bite_in
  if FISHING.DEBUG then
    print(("[fishing] anti-mash: restart wait, next bite in %.2fs"):format(bite_in))
  end
end

local function _H_for(area_id)
  local C = _C_for(area_id)
  return (C and C.HEAVINESS) or FISHING.HEAVINESS
end

-- pick heaviness using a custom odds table
local function _pick_heaviness_with_odds(area_id, odds)
  local H = _H_for(area_id)
  local o = odds
  if not o then
    local C = _C_for(area_id)
    o = (C and C.HEAVINESS_CHANCES) or FISHING.HEAVINESS_CHANCES
  end
  if not o or #H == 0 then
    return H[math.random(1, #H)]
  end
  local total = 0
  for _, h in ipairs(H) do total = total + (o[h.key] or 0) end
  if total <= 0 then
    return H[math.random(1, #H)]
  end
  local roll, acc = math.random() * total, 0
  for _, h in ipairs(H) do
    acc = acc + (o[h.key] or 0)
    if roll <= acc then return h end
  end
  return H[#H]
end

-- ===== Leaderboard: one-entry-per-player helpers =====
local function _lb_cfg(area_id)
  local C = _C_for and _C_for(area_id) or nil
  local L = (C and C.LEADERBOARD) or FISHING.LEADERBOARD or {}
  local mem_area = L.MEM_AREA or L.mem_area or "fisharea"
  local key      = L.KEY or L.key or "fish_top10"
  local max      = L.MAX or (FISHING.LEADERBOARD and FISHING.LEADERBOARD.MAX) or 10
  local uniq_by  = L.UNIQUE_PER or L.unique_per
                or (FISHING.LEADERBOARD and FISHING.LEADERBOARD.UNIQUE_PER)
                or "player_id"
  return mem_area, key, max, uniq_by
end

local function _lb_load(area_id)
  local area, key = _lb_cfg(area_id)
  local mem  = ezmemory.get_area_memory(area) or {}
  local list = mem[key]
  if type(list) ~= "table" then list = {} end
  return area, key, mem, list
end

local function _lb_top10(area_id)
  local _, _, _, list = _lb_load(area_id)
  return list
end

local function _lb_save(area, key, mem, list)
  mem[key] = list
  ezmemory.save_area_memory(area)
end

-- Upsert: keep only the player’s best weight; return (rank, improved)
local function _lb_upsert(pid, weight_lb, area_id)
  -- area-aware leaderboard gate (opt-in only)
  local C = _C_for and _C_for(area_id) or nil
  local LB = C and C.LEADERBOARD or nil
  -- If no per-area leaderboard declared, do nothing
  if not LB or LB == false or (LB.enabled == false) or (LB.ENABLED == false) then
    return nil, false
  end
  -- Require a target memory area to write to
  local mem_area = LB.MEM_AREA or LB.mem_area
  if not mem_area or mem_area == "" then
    return nil, false
  end
  local name = Net.get_player_name(pid) or pid
  local area, key, mem, list = _lb_load(area_id)
  local _, _, max, uniq_by    = _lb_cfg(area_id)

  local secret = nil
  if uniq_by == "secret" and helpers.get_safe_player_secret then
    pcall(function() secret = helpers.get_safe_player_secret(pid) end)
  end
  local k_new = (uniq_by == "name") and tostring(name)
            or (uniq_by == "secret") and tostring(secret or pid)
            or tostring(pid)

  -- find existing
  local idx = nil
  for i, e in ipairs(list) do
    local row_pid    = tostring(e.player_id or e.pid or "")
    local row_name   = tostring(e.name or e.player_name or "")
    local row_secret = tostring(e.player_secret or e.secret or e.sid or "")
    local k_row = (uniq_by == "name") and row_name
              or (uniq_by == "secret") and row_secret
              or row_pid
    if k_row == k_new then idx = i; break end
  end

  local improved = false
  if idx then
    if weight_lb > (tonumber(list[idx].weight) or 0) then
      list[idx].weight       = weight_lb
      list[idx].name         = name
      list[idx].player_name  = name
      list[idx].player_id    = pid
      list[idx].player_secret= secret   -- NEW
      list[idx].when         = os.time()
      improved = true
    end
  else
    table.insert(list, {
      player_id     = pid,
      player_secret = secret,           -- NEW
      name          = name,
      player_name   = name,
      weight        = weight_lb,
      when          = os.time()
    })
    improved = true
  end

  table.sort(list, function(a,b) return (a.weight or 0) > (b.weight or 0) end)
  while #list > max do list[#list] = nil end

  mem[key] = list
  ezmemory.save_area_memory(area)

  local rank = nil
  for i, e in ipairs(list) do
    local k_row = (uniq_by == "name") and tostring(e.name or e.player_name or "")
              or (uniq_by == "secret") and tostring(e.player_secret or e.secret or e.sid or "")
              or tostring(e.player_id or e.pid or "")
    if k_row == k_new then rank = i; break end
  end

  return rank, improved
end

local function _bait_for(area_id)
  local C = _C_for(area_id)  -- you already have this resolver
  local base = FISHING.BAIT or {}
  return {
    VIRUS_CHANCE = (C.BAIT and C.BAIT.VIRUS_CHANCE) or base.VIRUS_CHANCE,
    HEAVINESS_CHANCES = (C.BAIT and C.BAIT.HEAVINESS_CHANCES) or base.HEAVINESS_CHANCES,
  }
end

local function _bugfrag_for(area_id)
  local C = _C_for(area_id)
  local base = FISHING.BUGFRAG or {}
  return {
    ITEM_NAME = (C.BUGFRAG and C.BUGFRAG.ITEM_NAME) or base.ITEM_NAME or "bugfrag",
    VIRUS_CHANCE = (C.BUGFRAG and C.BUGFRAG.VIRUS_CHANCE) or base.VIRUS_CHANCE or 0.60,
    HEAVINESS_CHANCES = (C.BUGFRAG and C.BUGFRAG.HEAVINESS_CHANCES) or base.HEAVINESS_CHANCES,
  }
end

local function _consume_item(pid, name, qty)
  pcall(ezmemory.remove_player_item, pid, name, qty or 1)
end

-- ===== end helpers =====

local function _start_session(pid, opts)
  local area = Net.get_player_area(pid); if not area then return end
  -- Resolve constants for THIS player’s area
  local C        = _C_for(area)
  local bait     = _bait_for(area)      -- per-area bait overrides (with global fallback)
  local bugfrag  = _bugfrag_for(area)   -- per-area bugfrag overrides (with global fallback)
  _cleanup_fishing_meters(area, pid)

  local used_bait     = (opts and opts.used_bait) or false
  local used_bugfrag  = (opts and opts.used_bugfrag) or false

  -- Consume 1 item when actually starting (if chosen)
  local bait_name = (bait and bait.ITEM_NAME) or (FISHING.BAIT and FISHING.BAIT.ITEM_NAME) or "bait"
  local bug_name  = (bugfrag and bugfrag.ITEM_NAME) or (FISHING.BUGFRAG and FISHING.BUGFRAG.ITEM_NAME) or "bugfrag"
  if used_bait then _consume_item(pid, bait_name, 1) end
  if used_bugfrag then _consume_item(pid, bug_name, 1) end

  -- Heaviness odds:
  --   bait      -> use bait.HEAVINESS_CHANCES
  --   bugfrag   -> use bugfrag.HEAVINESS_CHANCES
  --   otherwise -> area constants or global defaults
  local heaviness_weights =
      (used_bait    and bait.HEAVINESS_CHANCES)
   or (used_bugfrag and bugfrag.HEAVINESS_CHANCES)
   or (C.HEAVINESS_CHANCES or FISHING.HEAVINESS_CHANCES)

  -- Hold requirement (seconds): prefer C.HOLD_SECONDS, else pick from C.SUCCESS_RANGE
  local base_hold = tonumber(C.HOLD_SECONDS)
  if not base_hold then
    local r  = C.SUCCESS_RANGE or FISHING.HOLD_RANGE_S
    local lo = tonumber(r and r.min) or 3.0
    local hi = tonumber(r and r.max) or 6.0
    base_hold = lo + math.random() * math.max(0, hi - lo)
  end

  -- pick heaviness and hold (uses per-session odds)
  local H         = _pick_heaviness_with_odds(area, heaviness_weights)
  local hold_req  = (base_hold * (H.hold_mult or 1.0))
  local W         = math.max(1, math.min(3, tonumber(C.SWEET_WIDTH or FISHING.SWEET_WIDTH or 2)))
  local max_lo    = 9 - (W - 1)
  local sweet_lo  = math.random(1, max_lo)
  local sweet_hi  = sweet_lo + (W - 1)

  local px        = Net.get_player_position(pid) or { x = 0, y = 0, z = 0 }

  -- Virus chance:
  --   bait      -> bait.VIRUS_CHANCE (usually lower)
  --   bugfrag   -> bugfrag.VIRUS_CHANCE (usually higher)
  --   otherwise -> area or global default
  local virus_chance =
      (used_bait    and tonumber(bait.VIRUS_CHANCE))
   or (used_bugfrag and tonumber(bugfrag.VIRUS_CHANCE))
   or tonumber(C.VIRUS_CHANCE or FISHING.VIRUS_CHANCE)

  local s         = {
    area_id      = area,
    started_at   = _now_s(),
    last_pos     = { x = px.x, y = px.y, z = px.z },
    active       = true,

    -- waiting phase
    phase        = "waiting",
    bite_state   = "idle",
    bite_active  = false,
    bite_until   = 0,
    bite_oid     = nil,
    next_bite_at = nil, -- important: session field

    -- reeling
    meter_color  = "normal",
    meter_phase  = 0,
    meter_value  = 0.0,
    sweet_lo     = sweet_lo,
    sweet_hi     = sweet_hi,
    hold_req     = hold_req,
    hold_accum   = 0.0,
    heaviness    = H.key,
    weight_lb    = _random_weight_lb(area, H.key),
    decay        = H.decay,
    mashGain     = H.mash,

    -- item usage + odds chosen
    used_bait    = used_bait and true or false,
    used_bugfrag = used_bugfrag and true or false,
    virus_chance = virus_chance,
    odds_used    = heaviness_weights,

    taps         = 0.0,
    timer_phase  = 0,
  }
  SESS[pid]       = s
  _play(pid, FISHING.SFX.start)

  -- waiting loop
  async(function()
    local wait_rng = C.BITE_WAIT_RANGE or (FISHING.BITE and FISHING.BITE.WAIT_RANGE_S) or { min = 1.2, max = 3.0 }
    local wait_min = tonumber(wait_rng.min or 1.2) or 1.2
    local wait_max = tonumber(wait_rng.max or 3.0) or 3.0
    local step = 0.05

    -- per-session elapsed time for the waiting phase
    s.wait_elapsed = 0

    -- seed the first bite time RELATIVE to wait_elapsed
    if not s.next_bite_at then
      local bite_in = wait_min + math.random() * math.max(0, wait_max - wait_min)
      s.next_bite_at = (s.wait_elapsed or 0) + bite_in
    end

    while true do
      local cur = SESS[pid]; if not cur or not cur.active or cur.phase ~= "waiting" then return end

      -- advance our session clock
      cur.wait_elapsed = (cur.wait_elapsed or 0) + step

      -- movement cancels
      local p = Net.get_player_position(pid); if not p then return end
      local dx = (p.x - cur.last_pos.x); local dy = (p.y - cur.last_pos.y); local dz = (p.z - cur.last_pos.z)
      if math.abs(dx) > 0.01 or math.abs(dy) > 0.01 or math.abs(dz) > 0.01 then
        if JobBBS and JobBBS.on_fish_fail then pcall(JobBBS.on_fish_fail, pid) end
        _stop(pid, "Stopped fishing because you scared the fish. Stay still next time.", FISHING.SFX.fail)
        return
      end

      -- draw bite indicator
      _spawn_or_update_bite(pid)

      -- time to bite?
      if (not cur.bite_active) and (cur.wait_elapsed >= (cur.next_bite_at or math.huge)) then
        cur.bite_state     = "bite"
        cur.bite_active    = true
        local win_tbl      = (C and C.BITE and C.BITE.WINDOW_S)
                            or (FISHING.BITE and FISHING.BITE.WINDOW_S)
                            or {}
        local win          = tonumber(win_tbl[cur.heaviness] or 0.9) or 0.9
        cur.bite_until_rel = (cur.wait_elapsed or 0) + win
        Net.shake_player_camera(pid, 5, 0.1)
        _play(pid, FISHING.SFX.alert)
        if FISHING.DEBUG then
          print(("[fishing] BITE! window=%.2fs gid=%d"):format(win, _bite_gid("bite", s.area_id) or -1))
        end
        _spawn_or_update_bite(pid)
        local sfx = FISHING.BITE and FISHING.BITE.SFX_BITE; _play(pid, sfx)
      end

      -- missed the window?
      if cur.bite_active and (cur.wait_elapsed > (cur.bite_until_rel or 0)) then
        if JobBBS and JobBBS.on_fish_fail then pcall(JobBBS.on_fish_fail, pid) end
        _stop(pid, "Too slow! The fish slipped away.", FISHING.SFX.fail)
        return
      end

      await(Async.sleep(step))
    end
  end)
end


local function _begin_reeling(pid)
  local s = SESS[pid]; if not s or not s.active then return end
  local aid = s.area_id or Net.get_player_area(pid)
  local C = (aid and _C_for(aid)) or nil
  s.phase       = "reeling"
  s.ends_at     = _now_s() + math.ceil( tonumber(C.MAX_DURATION_S or FISHING.MAX_DURATION_S or 12) )
  s.meter_color = "normal"
  s.meter_phase = 0
  s.meter_value = 0.0
  s.hold_accum  = 0.0
  s.timer_phase = 0

  async(function()
    local step = 0.08
    while true do
      local cur = SESS[pid]; if not cur or not cur.active or cur.phase ~= "reeling" then return end
      -- movement cancel
      local p = Net.get_player_position(pid); if not p then return end
      local dx = (p.x - cur.last_pos.x); local dy = (p.y - cur.last_pos.y); local dz = (p.z - cur.last_pos.z)
      if math.abs(dx) > 0.01 or math.abs(dy) > 0.01 or math.abs(dz) > 0.01 then
        if JobBBS and JobBBS.on_fish_fail then pcall(JobBBS.on_fish_fail, pid) end
        _stop(pid, "Stopped fishing because you scared the fish. Stay still next time.", FISHING.SFX.fail)
        return
      end
      -- time out
      if _now_s() >= (cur.ends_at or 0) then
        if JobBBS and JobBBS.on_fish_fail then pcall(JobBBS.on_fish_fail, pid) end
        _stop(pid, "The fish got away!", FISHING.SFX.fail)
        return
      end

      -- decay + taps
      local value = tonumber(cur.meter_value or cur.meter_phase or 0)
      value = value - (cur.decay * step) + (cur.taps * cur.mashGain)
      cur.taps = 0
      value = _clamp(value, 0, 10)
      cur.meter_value = value
      local phase = math.floor(value + 0.5)
      if phase ~= cur.meter_phase then cur.meter_phase = phase end

      local in_sweet = (cur.meter_phase >= cur.sweet_lo and cur.meter_phase <= cur.sweet_hi)
      if in_sweet then
        cur.meter_color = "sweet_spot"; cur.hold_accum = cur.hold_accum + step
      else
        cur.meter_color = "normal"
      end

      -- timer bar progress (0..5)
      local ratio = 0
      if (cur.hold_req or 0) > 0 then ratio = _clamp((cur.hold_accum or 0) / cur.hold_req, 0, 1) end
      local tphase = math.floor(ratio * 5 + 0.5); if tphase ~= cur.timer_phase then cur.timer_phase = tphase end

      -- draw meters
      _spawn_or_update_meter(pid)
      _spawn_or_update_timer(pid)

      -- success
      if cur.hold_accum >= cur.hold_req then
        local tier = tostring(cur.heaviness or "")
        local excluded = (C and C.VIRUS_EXCLUDED) or FISHING.VIRUS_EXCLUDED or {}
        local eligible = not excluded[tier]
        local chance = tonumber(cur.virus_chance or FISHING.VIRUS_CHANCE or 0) or 0
        local roll = math.random()

        if eligible and roll < chance then
          local aid = cur.area_id
          local enc = _pick_virus_encounter(aid)
          -- ADD: mark that a fishing virus started (for “Clean the Pond” jobs)
          if JobBBS and JobBBS.on_fish_virus_start then
            pcall(JobBBS.on_fish_virus_start, pid, { area = aid })
          end
          _stop(pid, nil, nil)
          _queue_virus_battle(pid, enc, aid)
          return
        else
          -- fish catch: pay money and show message (+ leaderboard)
          local w = cur.weight_lb or 0
          local Cpay = _C_for(cur.area_id)
          local pay_per_lb = tonumber((Cpay and Cpay.FISH_REWARD_PER_LB) or FISHING.FISH_REWARD_PER_LB or 0) or 0
          local monies = math.floor((w * pay_per_lb) + 0.5)
          if monies > 0 then ezmemory.spend_player_money(pid, -monies) end

          local rank, improved = _lb_upsert(pid, w, cur.area_id)
          local msg = ("You caught a fish! It weighed %.1f lb. You earned $%d!"):format(w, monies)
          if improved then
            msg = msg .. " New personal best!"
            local LBmax = ((C and C.LEADERBOARD and C.LEADERBOARD.MAX)
                          or (FISHING.LEADERBOARD and FISHING.LEADERBOARD.MAX)
                          or 10)
            if rank and rank <= LBmax then
              msg = msg .. (" New leaderboard %d!"):format(rank)
            end
          end
          -- ADD THIS (notify JobBBS about a successful catch)
          if JobBBS and JobBBS.on_fish_catch then
            pcall(JobBBS.on_fish_catch, pid, {
              weight     = w,
              heaviness  = cur.heaviness,
              used_bait  = cur.used_bait or false,
              area       = cur.area_id,
              rank       = rank
            })
          end
          if Teams and Teams.on_fish_catch then
            pcall(Teams.on_fish_catch, pid)
          end
          _stop(pid, msg, FISHING.SFX.catch)
          return
        end
      end

      await(Async.sleep(step))
    end
  end)
end

local function _try_begin_reeling(pid)
  local s = SESS[pid]; if not s or not s.active or s.phase ~= "waiting" then return end
  if not s.bite_active then return end
  -- accept only if still within the relative bite window
  if (s.wait_elapsed or 0) > (s.bite_until_rel or 0) then return end
  _despawn_bite(pid)
  _begin_reeling(pid)
end

-- item helpers (ezmemory)
local function _count_item(pid, name)
  local ok, n = pcall(ezmemory.count_player_item, pid, name)
  return (ok and tonumber(n) or 0) or 0
end

-- queue: start fishing only after the player closes a message
local _PENDING_START = {} -- pid -> { used_bait = bool }
local function _queue_start_after_message(pid, msg, choice)
  _PENDING_START = _PENDING_START or {}
  local used_bait, used_bugfrag = false, false
  if type(choice) == "table" then
    used_bait    = choice.used_bait and true or false
    used_bugfrag = choice.used_bugfrag and true or false
  else
    used_bait = choice and true or false
  end
  _PENDING_START[pid] = { used_bait = used_bait, used_bugfrag = used_bugfrag }
  Net.message_player(pid, msg or "Starting to fish...")
end
local function _begin_pending_start(pid)
  local rec = _PENDING_START[pid]; if not rec then return end
  _PENDING_START[pid] = nil
  _start_session(pid, rec) -- pass { used_bait = true/false }
end

-- ====================== FishBBS (Top 10 board) ======================
local FISHBBS = {
  TITLE = "FishBBS - Top 10 Heaviest",
  COLOR = { r = 90, g = 180, b = 255 },
}

local function _trunc(s, n)
  s = tostring(s or "")
  if #s <= n then return s end
  return s:sub(1, n)
end

local function _open_fishbbs(pid)
  local aid  = Net.get_player_area(pid)
  local list = _lb_top10(aid) or {}
  local _, _, LBmax = _lb_cfg(aid)
  local posts = {}

  if #list == 0 then
    posts[#posts + 1] = { id = '__fishbbs:none', read = true, title = 'No catches yet. Be the first!', author = '' }
  else
    local MAX_NAME = 20
    for i, rec in ipairs(list) do
      local nm = _trunc(tostring(rec.name or rec.player_name or "Unknown"), MAX_NAME)
      local wt = tonumber(rec.weight or 0) or 0
      posts[#posts + 1] = {
        id     = '__fishbbs:post:' .. i,
        read   = true,
        title  = string.format('%2d  %s', i, nm),
        author = string.format('%.1f lb', wt),
      }
      if i >= LBmax then break end  -- was hardcoded 10
    end
  end

  Net.open_board(pid, FISHBBS.TITLE, FISHBBS.COLOR, posts)
end

-- Handle clicks on FishBBS
Net:on("bbs_post_selection", function(ev)
  local pid = ev.player_id; if not pid then return end
  local id = tostring(ev.post_id or '')
  if id:match('^__fishbbs:') then
    -- read-only; nothing else to do
  end
end)

Net:on("textbox_response", function(a, b)
  local pid = (type(a) == "table") and (a.player_id or a[1]) or a
  if not pid then return end
  if _PENDING_VIRUS[pid] then
    _begin_pending_virus(pid); return
  end
  if _PENDING_START[pid] then
    _begin_pending_start(pid); return
  end
end)
-- ====================== Input handling ======================
local function _register_tap(pid)
  local s = SESS[pid]; if not s or not s.active then return end
  s.taps = (s.taps or 0) + 1.0
  _play(pid, FISHING.SFX.increment)
  end

Net:on("object_interaction", function(ev)
  if ev.button ~= 0 then return end -- A only
  local pid = ev.player_id
  local area_id = Net.get_player_area(pid)

  -- Which object was clicked
  local obj = Net.get_object_by_id(area_id, ev.object_id)
  if obj then
    local cls = tostring(obj.class or '')
    local typ = tostring(obj.type or '')
    -- Open FishBBS if this is a board
    if cls == 'FishBBS' or typ == 'FishBBS' then
      _open_fishbbs(pid)
      return
    end
  end

  -- Already fishing: treat A as a tap (this lets anti-mash restart work)
  local s = SESS[pid]
  if s and s.active then
    if s.phase == "waiting" then
      if s.bite_active then
        _try_begin_reeling(pid)
      else
        _quiet_restart_wait(pid) -- was: _stop + _start_session
      end
    else
      _register_tap(pid)
    end
    return
  end
  -- Start only if this is a Water object
  if not obj then return end
  local cp = obj.custom_properties or {}
  local water = cp["Water"] or cp["water"] or cp["WATER"]
  local is_yes = (water == true) or (tostring(water or ""):lower() == "yes") or (tostring(water or ""):lower() == "true")
  if not is_yes then return end

  -- Ask to use bait (yes/no). Start after the player closes the message.
  async(function()
    local area_id       = Net.get_player_area(pid)
    local bait_conf     = _bait_for(area_id)
    local bugfrag_conf  = _bugfrag_for(area_id)
    local bait_name     = bait_conf.ITEM_NAME or "bait"
    local bug_name      = bugfrag_conf.ITEM_NAME or "bugfrag"

    local have_bait = _count_item(pid, bait_name)
    local have_bug  = _count_item(pid, bug_name)

    -- 1) Show counts as a standalone message (waits for close)
    local prompt = string.format("You have %d bait and %d bugfrags.", have_bait, have_bug)
    await(Async.message_player(pid, prompt))

    -- 2) Then ask how to proceed with a quiz
    -- NOTE: ezlibs Async.quiz_player returns 0/1/2 (NOT 1/2/3)
    local ans = await(Async.quiz_player(pid,
      "No item",  -- 0
      "Use bait",            -- 1
      "Use bugfrag"          -- 2
    ))

    if ans == 1 then
      -- Use bait
      if have_bait <= 0 then
        _queue_start_after_message(pid, "No bait left, fishing without bait...", { used_bait=false, used_bugfrag=false })
      else
        _queue_start_after_message(pid, "Using bait...", { used_bait=true, used_bugfrag=false })
      end
    elseif ans == 2 then
      -- Use bugfrag
      if have_bug <= 0 then
        _queue_start_after_message(pid, "No bugfrags left, fishing without bugfrags...", { used_bait=false, used_bugfrag=false })
      else
        _queue_start_after_message(pid, "Using bugfrag...", { used_bait=false, used_bugfrag=true })
      end
    else
      -- Fish without items
      _queue_start_after_message(pid, "Starting to fish...", { used_bait=false, used_bugfrag=false })
    end
  end)
end)

Net:on("tile_interaction", function(ev)
  if ev.button ~= 0 then return end
  local pid = ev.player_id
  local s = SESS[pid]; if not s or not s.active then return end
  if s.phase == "waiting" then
    if s.bite_active then
      _try_begin_reeling(pid)
    else
      _quiet_restart_wait(pid) -- was: _stop + _start_session
    end
    return
  end
end)

-- Cleanup on transfer/quit (also clean orphans on join/transfer)
Net:on("player_transfer", function(ev)
  local pid = ev.player_id
  if SESS[pid] and SESS[pid].active then
    if JobBBS and JobBBS.on_fish_fail then pcall(JobBBS.on_fish_fail, pid) end
    _stop(pid, "Fishing cancelled.", FISHING.SFX.fail)
  end
end)

Net:on("player_join_area", function(ev)
  local pid = ev.player_id
  local aid = ev.area_id or Net.get_player_area(pid)
  if not pid or not aid then return end
  PLAYER_AREA[pid] = aid
  AREA_PLAYERS[aid] = AREA_PLAYERS[aid] or {}
  AREA_PLAYERS[aid][pid] = true

  -- keep your existing orphan cleanup
  _cleanup_fishing_meters(aid, pid)

  -- and hide existing meters they do not own
  _hide_existing_meters_for_joiner(ev)
end)


Net:on("player_area_transfer", function(ev)
  local pid = ev.player_id
  if not pid then return end
  local from = PLAYER_AREA[pid] or ev.from_area_id or ev.area_id
  if from and AREA_PLAYERS[from] then AREA_PLAYERS[from][pid] = nil end

  local to = ev.to_area_id or Net.get_player_area(pid)
  if to then
    PLAYER_AREA[pid] = to
    AREA_PLAYERS[to] = AREA_PLAYERS[to] or {}
    AREA_PLAYERS[to][pid] = true

    _cleanup_fishing_meters(to, pid)
    _hide_existing_meters_for_joiner({ player_id = pid, area_id = to, to_area_id = to })
    _despawn_meter(pid)
    _despawn_timer(pid)
  end
end)

Net:on("player_quit", function(ev)
  local pid = ev.player_id
  if not pid then return end
  local aid = PLAYER_AREA[pid]
  if aid and AREA_PLAYERS[aid] then AREA_PLAYERS[aid][pid] = nil end
  PLAYER_AREA[pid] = nil
  if SESS[pid] and SESS[pid].active then _stop(pid, nil, nil) end
end)

Net:on("player_disconnect", function(ev)
  local pid = ev.player_id
  if not pid then return end
  local aid = PLAYER_AREA[pid]
  if aid and AREA_PLAYERS[aid] then AREA_PLAYERS[aid][pid] = nil end
  PLAYER_AREA[pid] = nil
  if SESS[pid] and SESS[pid].active then _stop(pid, nil, nil) end
  _cleanup_all_for_pid(pid)
  _despawn_meter(pid)
  _despawn_timer(pid)
end)

-- ====================== Public API (optional) ======================
local fishing = {}

function fishing.start_for_player(pid)
  _start_session(pid)
end

function fishing.open_fishbbs(pid)
  _open_fishbbs(pid)
end

return fishing
