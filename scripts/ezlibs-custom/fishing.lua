-- /server/scripts/ezlibs-custom/fishing.lua
-- Fishing mini-game + FishBBS (Top 10 heaviest)
-- Everything in one file.

-- ====================== Requires ======================
local helpers  = require('scripts/ezlibs-scripts/helpers')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')

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

local Async = _resolve_async()

-- ====================== Config you can edit ======================
local FISHING = {
  -- Hidden layer where your meter prototype objects live
  TEMPLATE_LAYER = "Fishing",
  HOLD_SECONDS = 5.0,

  -- Placement around the player
  METER_FORWARD = 0.2,         -- a little in front of facing
  METER_SIDE    = "right",     -- "left" | "right" | number (tiles). If number, exact side offset (tiles).
  METER_DISTANCE = 0.8,        -- legacy fallback; kept for compatibility

  -- Extra world-space nudge after facing/side placement (tiles).
  -- Positive y moves the meter lower on the screen.
  METER_SCREEN_SHIFT = { x = 2.5, y = 0.0, z = 0.0 },

  -- Total time window to hook the fish
  MAX_DURATION_S = 10.0,

  -- Time you must hold inside the sweet band to succeed
  HOLD_RANGE_S = { min = 3.0, max = 6.0 },

  -- Sweet spot width: number of consecutive pips that count as "sweet"
  SWEET_WIDTH = 2,             -- e.g., 2 means [4..5] or [7..8], always within 1..9

  -- Heaviness presets (higher decay = harder; mash is how much each A tap helps)
  HEAVINESS = {
    --  key            decay/s   mashGain  hold_mult
    { key="light",       decay=1.2,  mash=1.20,  hold_mult=0.95 },
    { key="medium",      decay=1.8,  mash=1.00,  hold_mult=1.00 },
    { key="heavy",       decay=2.5,  mash=0.90,  hold_mult=1.10 },
    -- Harder tiers
    { key="very_heavy",  decay=3.6,  mash=0.85,  hold_mult=1.20 },
    { key="brutal",      decay=4.8,  mash=0.80,  hold_mult=1.35 },
    { key="legendary",   decay=6.0,  mash=0.75,  hold_mult=1.50 },
  },

  -- Odds for each heaviness tier
  HEAVINESS_CHANCES = {
    light       = 25,
    medium      = 25,
    heavy       = 25,
    very_heavy  = 10,
    brutal      = 10,
    legendary   = 5,
  },

  -- Display-only: random weight ranges (in pounds) per heaviness
  WEIGHT_RANGES_LB = {
    light       = {  1.0,  3.0 },
    medium      = {  3.0,  7.0 },
    heavy       = {  7.0, 12.0 },
    very_heavy  = { 12.0, 18.0 },
    brutal      = { 18.0, 25.0 },
    legendary   = { 25.0, 40.0 },
  },

  -- Leaderboard persistence (stored under this area)
  LEADERBOARD = {
    MEM_AREA = "fisharea",  -- << your fishing zone
    KEY      = "fish_top10",
    MAX      = 10,
  },

  -- Your meter catalog (blue 0..10, yellow 0..10) – GIDs kept exactly
  METERS = {
    blue = {
      [0]  = 275,  -- 0
      [1]  = 286,  -- blue-1
      [2]  = 288,  -- blue-2
      [3]  = 289,  -- blue-3
      [4]  = 290,  -- blue-4
      [5]  = 291,  -- blue-5
      [6]  = 292,  -- blue-6
      [7]  = 293,  -- blue-7
      [8]  = 294,  -- blue-8
      [9]  = 295,  -- blue-9
      [10] = 287,  -- blue-10
    },
    yellow = {
      [0]  = 0,    -- no yellow-0 asset (intentional)
      [1]  = 276,  -- yellow-1
      [2]  = 277,  -- yellow-2
      [3]  = 278,  -- yellow-3
      [4]  = 279,  -- yellow-4
      [5]  = 280,  -- yellow-5
      [6]  = 281,  -- yellow-6
      [7]  = 282,  -- yellow-7
      [8]  = 283,  -- yellow-8
      [9]  = 284,  -- yellow-9
      [10] = 285,  -- yellow-10
    },
  },

  -- Optional sfx paths (set to nil if not wanted)
  SFX = {
    start  = "/server/assets/ezlibs-assets/sfx/select.ogg",
    catch  = "/server/assets/ezlibs-assets/sfx/item_get.ogg",
    fail   =  "/server/assets/ezlibs-assets/sfx/cancel.ogg",
    tick   = nil,
  },
}

-- ====================== Minimal TMX helpers ======================
local FLIP_H = 0x80000000
local FLIP_V = 0x40000000
local FLIP_D = 0x20000000

local function decode_gid_flags(raw)
  local g = tonumber(raw or 0) or 0
  local fh = false; if g >= FLIP_H then fh = true; g = g - FLIP_H end
  local fv = false; if g >= FLIP_V then fv = true; g = g - FLIP_V end
  local fr = false; if g >= FLIP_D then fr = true; g = g - FLIP_D end
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
    if name == layer_name then body = content; break end
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
  local tw = tonumber(xml:match('tilewidth="(%d+)"') or xml:match('tilewidth="(%d+%.%d+)"')) or 0
  local th = tonumber(xml:match('tileheight="(%d+)"') or xml:match('tileheight="(%d+%.%d+)"')) or 0
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
    if name == layer_name then body = content; break end
  end
  if not body then return nil, nil end

  local want = tonumber(gid)
  local best_wt, best_ht = nil, nil
  for obj_tag in body:gmatch('<object%s+[^>]*>') do
    local ogid = tonumber(obj_tag:match('gid="(%d+)"') or "")
    local wpx  = tonumber(obj_tag:match('width="([%d%.]+)"')  or "") or 0
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
  local tile_px_w = tonumber(ts.tile_width  or ts.tilewidth  or ts.tileWidth)
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
           td.flipped_vertically   or false,
           td.rotated              or false
  end
  local try_layers = { template_layer_name, "Object Layer 1", "Object Layer 2" }
  for _, lname in ipairs(try_layers) do
    local fh, fv, fr = _tmx_flip_flags_from_layer(area_id, lname, base_gid)
    if fh ~= nil then return fh, fv, fr end
  end
  return def_fh, def_fv, def_fr
end

-- Cache per-area per-gid meter dimensions so they never bounce between players
local _DIM_CACHE = {}
local function _meter_dims_from_template(area_id, base_gid)
  local key = tostring(area_id) .. ":" .. tostring(base_gid)
  local hit = _DIM_CACHE[key]
  if hit then return hit.w, hit.h end

  -- First: exact object from the "Fishing" template layer
  local w, h = get_template_dims_from_layer(area_id, FISHING.TEMPLATE_LAYER, base_gid)
  if not w or not h then
    -- Fallback: tileset tile->map tile ratio
    w, h = get_gid_dims_in_tiles(area_id, base_gid)
  end
  w = tonumber(w) or 1
  h = tonumber(h) or 1

  _DIM_CACHE[key] = { w = w, h = h }
  return w, h
end

-- ====================== Placement helpers ======================
local function get_cursor_point(player_id, dist)
  local ok_pos, pos = pcall(Net.get_player_position, player_id)
  if not ok_pos or not pos then return nil end
  local dx, dy = 0, 1
  local ok_dir, dir = pcall(Net.get_player_direction, player_id)
  local function dir_to_offset(dirName)
    if     dirName == "Left"       then return -1, 0
    elseif dirName == "Right"      then return  1, 0
    elseif dirName == "Up"         then return  0,-1
    elseif dirName == "Down"       then return  0, 1
    elseif dirName == "Up Left"    then return -1,-1
    elseif dirName == "Up Right"   then return  1,-1
    elseif dirName == "Down Left"  then return -1, 1
    elseif dirName == "Down Right" then return  1, 1
    else return 0,1 end
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
    if     dirName == "Left"       then return -1, 0
    elseif dirName == "Right"      then return  1, 0
    elseif dirName == "Up"         then return  0,-1
    elseif dirName == "Down"       then return  0, 1
    elseif dirName == "Up Left"    then return -1,-1
    elseif dirName == "Up Right"   then return  1,-1
    elseif dirName == "Down Left"  then return -1, 1
    elseif dirName == "Down Right" then return  1, 1
    else return 0,1 end
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
    side =  (side_default or 2.0) -- "right" or anything else
  end

  return pos.x + fdx * forward_dist + rdx * side,
         pos.y + fdy * forward_dist + rdy * side,
         (pos.z or 0)
end

-- ====================== Runtime state ======================
local SESS = {}    -- [pid] = session
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
  mem[key] = mem[key] or {}
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
  table.sort(list, function(a,b) return (a.weight or 0) > (b.weight or 0) end)
  local maxn = (FISHING.LEADERBOARD and FISHING.LEADERBOARD.MAX) or 10
  while #list > maxn do table.remove(list) end

  local rank = nil
  for i, r in ipairs(list) do
    if r == rec then rank = i; break end
  end
  ezmemory.save_area_memory(area)
  return rank
end

local function _lb_top10()
  local _, list = _lb_bucket()
  return list
end

-- ====================== Meter Preview ======================
local function _meter_gid(area_id, color, phase)
  local catalog = FISHING.METERS[color] or {}
  return tonumber(catalog[phase or 0] or 0) or 0
end

local function _spawn_or_update_meter(pid)
  local s = SESS[pid]; if not s or not s.active then return end

  local area_id = s.area_id
  if not area_id then return end

  local raw_gid = _meter_gid(area_id, s.meter_color, s.meter_phase or 0)
  if not raw_gid or raw_gid == 0 then return end

  local base_gid = gid_base(raw_gid)
  local want_fh, want_fv, want_fr = resolve_preview_flip_flags(area_id, FISHING.TEMPLATE_LAYER, base_gid, false, false, false)
  local w, h = _meter_dims_from_template(area_id, base_gid)
  w = tonumber(w) or 1
  h = tonumber(h) or 1

  local forward = FISHING.METER_FORWARD or FISHING.METER_DISTANCE or 0.2
  local side_default = math.max(1.4, (w or 1) * 0.65)
  local side_spec = (FISHING.METER_SIDE ~= nil) and FISHING.METER_SIDE or "right"
  local x, y, z = get_offset_point(pid, forward, side_spec, side_default)
  if not x or not y then return end
  z = tonumber(z) or 0
  x = tonumber(x) or 0
  y = tonumber(y) or 0

  -- Apply world-space nudge
  do
    local shift = FISHING.METER_SCREEN_SHIFT or {}
    x = x + (shift.x or 0)
    y = y + (shift.y or 0)   -- increase y to move lower
    z = z + (shift.z or 0)
  end

  local data = {
    type = "tile",
    gid = tonumber(base_gid) or 0,
    flipped_horizontally = not not want_fh,
    flipped_vertically   = not not want_fv,
    rotated              = not not want_fr,
  }

  local spec = {
    name     = "",
    class    = "FishingMeter",
    visible  = true,
    x        = x, y = y, z = z,
    width    = w, height = h,
    rotation = 0,
    data     = data,
    custom_properties = {
      fishing_meter = "true",
      fishing_pid   = tostring(pid or ""),
    }
  }

  local must_recreate = false
  if not s.meter_oid then
    must_recreate = true
  else
    local cur = Net.get_object_by_id(area_id, s.meter_oid)
    if not cur or (cur.data and tonumber(cur.data.gid) ~= data.gid) then
      must_recreate = true
    end
  end

  if must_recreate then
    if s.meter_oid then pcall(function() Net.remove_object(area_id, s.meter_oid) end) end
    local ok, res = pcall(Net.create_object, area_id, spec)
    if not ok then
      spec.layer = FISHING.TEMPLATE_LAYER
      ok, res = pcall(Net.create_object, area_id, spec)
      if not ok then return end
    end
    s.meter_oid = res
  else
    Net.move_object(area_id, s.meter_oid, x, y, z)
    Net.set_object_data(area_id, s.meter_oid, data)
  end
end

local function _despawn_meter(pid)
  local s = SESS[pid]; if not s then return end
  if s.meter_oid then
    pcall(function() Net.remove_object(s.area_id, s.meter_oid) end)
    s.meter_oid = nil
  end
end

-- ====================== Difficulty / weight helpers ======================
local function _pick_heaviness()
  local H = FISHING.HEAVINESS
  local odds = FISHING.HEAVINESS_CHANCES
  if not odds then
    return H[math.random(1, #H)]
  end
  local total = 0
  for _, h in ipairs(H) do
    total = total + (odds[h.key] or 0)
  end
  if total <= 0 then
    return H[math.random(1, #H)]
  end
  local roll = math.random() * total
  local acc = 0
  for _, h in ipairs(H) do
    acc = acc + (odds[h.key] or 0)
    if roll <= acc then return h end
  end
  return H[#H]
end

local function _random_weight_lb(key)
  local r = FISHING.WEIGHT_RANGES_LB and FISHING.WEIGHT_RANGES_LB[key]
  if not r then return nil end
  local lo, hi = r[1] or 1, r[2] or 1
  -- 1 decimal place
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
      local is_meter = (o.class == "FishingMeter") or (tostring(cp.fishing_meter or "") == "true")
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

-- ====================== Core game loop ======================
local function _stop(pid, msg, sfx)
  local s = SESS[pid]; if not s then return end
  s.active = false
  _despawn_meter(pid)
  pcall(_cleanup_fishing_meters, s.area_id, pid) -- sweep this player's meters
  SESS[pid] = nil
  if msg and msg ~= "" then
    if Async and Async.message_player then Async.message_player(pid, msg)
    else Net.message_player(pid, msg) end
  end
  _play(pid, sfx)
end

local function _start_session(pid)
  local area = Net.get_player_area(pid)
  if not area then return end

  -- Nuke any lingering meters in this area for this player
  _cleanup_fishing_meters(area, pid)

  -- Pick fish heaviness w/ odds; scale hold time by heaviness
  local H = _pick_heaviness()
  local base_hold = (FISHING.HOLD_SECONDS or (FISHING.HOLD_RANGE_S.min + math.random() * (FISHING.HOLD_RANGE_S.max - FISHING.HOLD_RANGE_S.min)))
  local hold_req  = base_hold * (H.hold_mult or 1.0)
  -- Sweet band (width W) constrained to 1..9 inclusive
  local W = math.max(1, math.min(3, tonumber(FISHING.SWEET_WIDTH or 2)))
  local max_lo = 9 - (W - 1)
  local sweet_lo = math.random(1, max_lo)
  local sweet_hi = sweet_lo + (W - 1)

  local px = Net.get_player_position(pid) or {x=0,y=0,z=0}

  local s = {
    area_id     = area,
    started_at  = _now_s(),
    ends_at     = _now_s() + math.ceil(FISHING.MAX_DURATION_S),
    last_pos    = { x = px.x, y = px.y, z = px.z },
    active      = true,

    meter_color = "blue",
    meter_phase = 0,           -- 0..10 (display int)
    meter_value = 0.0,         -- 0..10 (float accumulator)

    sweet_lo    = sweet_lo,    -- inclusive
    sweet_hi    = sweet_hi,    -- inclusive
    hold_req    = hold_req,    -- seconds needed inside band
    hold_accum  = 0.0,

    heaviness  = H.key,
    weight_lb  = _random_weight_lb(H.key),
    decay      = H.decay,
    mashGain   = H.mash,
    taps       = 0.0,
  }
  SESS[pid] = s
  _play(pid, FISHING.SFX.start)

  async(function()
    local step = 0.08
    while true do
      local cur = SESS[pid]; if not cur or not cur.active then return end
      -- Cancel if the player moved
      local p = Net.get_player_position(pid); if not p then return end
      local dx = (p.x - cur.last_pos.x); local dy = (p.y - cur.last_pos.y); local dz = (p.z - cur.last_pos.z)
      if math.abs(dx) > 0.01 or math.abs(dy) > 0.01 or math.abs(dz) > 0.01 then
        _stop(pid, "Stopped fishing because you scared the fish. Stay still next time.", FISHING.SFX.fail)
        return
      end

      -- Time out (use wall time to avoid CPU-time stalls)
      if _now_s() >= (cur.ends_at or 0) then
        _stop(pid, "The fish got away!", FISHING.SFX.fail)
        return
      end
      -- Apply decay & taps with float accumulator
      local value = tonumber(cur.meter_value or cur.meter_phase or 0)
      value = value - (cur.decay * step) + (cur.taps * cur.mashGain)
      cur.taps = 0
      value = _clamp(value, 0, 10)
      cur.meter_value = value

      -- Snap to displayed phase (integer 0..10)
      local phase = math.floor(value + 0.5)
      if phase ~= cur.meter_phase then
        cur.meter_phase = phase
      end

      -- Yellow while inside the sweet band; blue otherwise
      local in_sweet = (cur.meter_phase >= cur.sweet_lo and cur.meter_phase <= cur.sweet_hi)
      if in_sweet then
        cur.meter_color = "yellow"
        cur.hold_accum = cur.hold_accum + step
      else
        cur.meter_color = "blue"
      end

      -- Update meter preview
      _spawn_or_update_meter(pid)

      -- Success
      if cur.hold_accum >= cur.hold_req then
        local w = cur.weight_lb
        local rank = _record_catch(pid, w)
        local msg = ("You caught a fish! (%.1f lb)"):format(w or 0)
        if rank and rank <= ((FISHING.LEADERBOARD and FISHING.LEADERBOARD.MAX) or 10) then
          msg = msg .. ("  New leaderboard #%d!"):format(rank)
        end
        _stop(pid, msg, FISHING.SFX.catch)
        return
      end

      await(Async.sleep(step))
    end
  end)
end

-- ====================== FishBBS (Top 10 board) ======================
local FISHBBS = {
  TITLE = "FishBBS - Top 10 Heaviest",
  COLOR = { r=90, g=180, b=255 },
}

local function _trunc(s, n)
  s = tostring(s or "")
  if #s <= n then return s end
  return s:sub(1, n)
end

local function _open_fishbbs(pid)
  local list = _lb_top10() or {}
  local posts = {}

  if #list == 0 then
    posts[#posts+1] = { id='__fishbbs:none', read=true, title='No catches yet. Be the first!', author='' }
  else
    local MAX_NAME = 20
    for i, rec in ipairs(list) do
      local nm = _trunc(tostring(rec.player_name or "Unknown"), MAX_NAME)
      local wt = tonumber(rec.weight or 0) or 0
      posts[#posts+1] = {
        id     = '__fishbbs:post:'..i,
        read   = true,
        title  = string.format('%2d  %s', i, nm),   -- no '#'
        author = string.format('%.1f lb', wt),
      }
      if i >= 10 then break end
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

-- ====================== Input handling ======================
local function _register_tap(pid)
  local s = SESS[pid]; if not s or not s.active then return end
  s.taps = (s.taps or 0) + 1.0
  _play(pid, FISHING.SFX.tick)
end

Net:on("object_interaction", function(ev)
  if ev.button ~= 0 then return end -- A only
  local pid = ev.player_id
  local area_id = Net.get_player_area(pid)

  -- Resolve the clicked object (for class/type)
  local obj = Net.get_object_by_id(area_id, ev.object_id)
  if obj then
    local cls = tostring(obj.class or '')
    local typ = tostring(obj.type  or '')
    -- If this is a FishBBS object, open the board and return.
    if cls == 'FishBBS' or typ == 'FishBBS' then
      _open_fishbbs(pid)
      return
    end
  end

  -- If already fishing, treat A as mash
  local s = SESS[pid]
  if s and s.active then
    _register_tap(pid)
    return
  end

  -- Start immediately on Water object (testing phase)
  if not obj then return end
  local cp = obj.custom_properties or {}
  local water = cp["Water"] or cp["water"] or cp["WATER"]
  local is_yes = (water == true) or (tostring(water or ""):lower() == "yes") or (tostring(water or ""):lower() == "true")
  if not is_yes then return end

  _start_session(pid)
end)

Net:on("tile_interaction", function(ev)
  if ev.button ~= 0 then return end -- A only
  local pid = ev.player_id
  local s = SESS[pid]
  if not s or not s.active then return end
  _register_tap(pid)
end)

-- Cleanup on transfer/quit (also clean orphans on join/transfer)
Net:on("player_transfer", function(ev)
  local pid = ev.player_id
  if SESS[pid] and SESS[pid].active then
    _stop(pid, "Fishing cancelled.", FISHING.SFX.fail)
  end
end)

Net:on("player_quit", function(ev)
  local pid = ev.player_id
  if SESS[pid] and SESS[pid].active then
    _stop(pid, nil, nil)
  end
end)

Net:on("player_join_area", function(ev)
  local aid = ev.area_id or Net.get_player_area(ev.player_id)
  if aid then _cleanup_fishing_meters(aid, ev.player_id) end
end)

Net:on("player_area_transfer", function(ev)
  local aid = ev.to_area_id or ev.area_id or Net.get_player_area(ev.player_id)
  if aid then _cleanup_fishing_meters(aid, ev.player_id) end
end)

-- ====================== Public API (optional) ======================
local fishing = {}

function fishing.set_meters(tbl)
  if type(tbl) == "table" then
    if tbl.blue   then FISHING.METERS.blue   = tbl.blue   end
    if tbl.yellow then FISHING.METERS.yellow = tbl.yellow end
  end
end

function fishing.start_for_player(pid)
  _start_session(pid)
end

function fishing.open_fishbbs(pid)
  _open_fishbbs(pid)
end

return fishing
