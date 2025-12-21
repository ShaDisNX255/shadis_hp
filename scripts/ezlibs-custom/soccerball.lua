-- scripts/soccerball.lua
-- Soccer ball gimmick: placeholder TMX object (type/class SoccerBall) spawns a solid bot you can "kick".

local CONFIG = {
  -- area_id is the filename without extension (default.tmx -> "default") :contentReference[oaicite:1]{index=1}
  area_id = "default",

  placeholder_type = "SoccerBall",

  -- Where the ball sprite+animation live (you said you'll use this new directory)
  -- Put files in: ./assets/soccerball/sheet/<Asset Name>.png + .animation
  asset_sheet_dir = "/server/assets/soccerball/sheet/",

  -- Goofy kick tuning
  scan_interval_sec = 0.02,       -- how often we check for nearby players (lower = more CPU)
  touch_radius_tiles = 1.0,      -- how close a player must be to "kick"
  per_player_cooldown_sec = 0.10, -- prevents spam while someone stands on it

  kick_duration_sec = 0.30,       -- you asked for ~half-second nudges
  kick_speed_tiles_per_sec = 5.0, -- how fast it moves during that half second

  -- Boundaries
  void_is_wall = true,            -- treat gid==0 as a wall
  max_bounces_per_kick = 1,       -- keep it simple + non-jittery

  -- Safety reset
  reset_after_inactive_sec = 8.0,

  debug = false,
}

local function dprint(...)
  if CONFIG.debug then
    print("[soccerball]", ...)
  end
end

-- Optional: if ezlibs helpers exists, we can also treat collision overlaps as walls (nice for blocking geometry).
local helpers = nil
pcall(function()
  helpers = require("scripts/ezlibs-scripts/helpers")
end)

local DIR_VECTORS = {
  ["Up"] = { 0, -1 },
  ["Down"] = { 0,  1 },
  ["Left"] = { -1, 0 },
  ["Right"] = {  1, 0 },

  ["Up Left"] = { -1, -1 },
  ["Up Right"] = {  1, -1 },
  ["Down Left"] = { -1,  1 },
  ["Down Right"] = {  1,  1 },
}

local OPP_DIR = {
  ["Up"] = "Down",
  ["Down"] = "Up",
  ["Left"] = "Right",
  ["Right"] = "Left",
  ["Up Left"] = "Down Right",
  ["Up Right"] = "Down Left",
  ["Down Left"] = "Up Right",
  ["Down Right"] = "Up Left",
}

local function dir_to_unit_vec(direction)
  local v = DIR_VECTORS[direction] or DIR_VECTORS["Down"]
  local dx, dy = v[1], v[2]
  local len = math.sqrt(dx*dx + dy*dy)
  if len == 0 then return 0, 0 end
  return dx / len, dy / len
end

local function nearest_tile(n)
  -- positions can be fractional; tiles are indexed as ints
  return math.floor(n + 0.5)
end

local function is_void_tile(area_id, x, y, z)
  if not CONFIG.void_is_wall then return false end
  local w = Net.get_width(area_id)
  local h = Net.get_height(area_id)

  local tx = nearest_tile(x)
  local ty = nearest_tile(y)
  local tz = math.floor((z or 0) + 0.5)

  if tx < 0 or ty < 0 or tx >= w or ty >= h then
    return true
  end

  local tile = Net.get_tile(area_id, tx, ty, tz)
  if not tile then return true end
  return tile.gid == 0
end

local function overlaps_something(area_id, x, y, z)
  if helpers and helpers.position_overlaps_something then
    return helpers.position_overlaps_something({
      x = x,
      y = y,
      z = z or 0,
      size = CONFIG.ball_size or 0.2,
    }, area_id) == true
  end
  return false
end

local function blocked(area_id, x, y, z)
  if is_void_tile(area_id, x, y, z) then return true end
  if overlaps_something(area_id, x, y, z) then return true end
  return false
end

-- Balls keyed by placeholder object id
local balls = {}
local world_time = 0.0
local next_scan_time = 0.0
local placeholders_loaded = false

local function placeholder_matches(o)
  if not o then return false end
  -- Server returns both "class" and deprecated "type" in the object struct :contentReference[oaicite:2]{index=2}
  return (o.class == CONFIG.placeholder_type) or (o.type == CONFIG.placeholder_type)
end

local function build_paths(asset_name)
  local base = CONFIG.asset_sheet_dir .. asset_name
  return base .. ".png", base .. ".animation"
end

local function ensure_bot(ball)
  if ball.bot_id and Net.is_bot(ball.bot_id) then return true end

  if not ball.asset_name or ball.asset_name == "" then
    if not ball.missing_asset_warned then
      print("[soccerball] SoccerBall '" .. tostring(ball.name) .. "' missing 'Asset Name' property; not spawning.")
      ball.missing_asset_warned = true
    end
    return false
  end

  local texture_path, anim_path = build_paths(ball.asset_name)

  -- make sure clients can download the files
  Net.provide_asset(ball.area_id, texture_path)
  Net.provide_asset(ball.area_id, anim_path)

  local bot_id = Net.create_bot({
    name = ball.name,
    area_id = ball.area_id,
    x = ball.spawn.x,
    y = ball.spawn.y,
    z = ball.spawn.z,
    direction = ball.initial_direction,
    solid = true,
    texture_path = texture_path,
    animation_path = anim_path,
  })

  ball.bot_id = bot_id
  dprint("spawned bot", bot_id, "for", ball.name)

  return true
end

local function reset_ball(ball, reason)
  if not ensure_bot(ball) then return end
  Net.move_bot(ball.bot_id, ball.spawn.x, ball.spawn.y, ball.spawn.z)
  Net.set_bot_direction(ball.bot_id, ball.initial_direction)
  ball.moving = false
  ball.remaining = 0
  ball.bounces = 0
  ball.last_activity = world_time
  dprint("reset", ball.name, reason or "")
end

local function kick_ball(ball, direction)
  if not ensure_bot(ball) then return end

  local dx, dy = dir_to_unit_vec(direction)
  ball.kick_dir = direction
  ball.vx = dx * CONFIG.kick_speed_tiles_per_sec
  ball.vy = dy * CONFIG.kick_speed_tiles_per_sec
  ball.remaining = CONFIG.kick_duration_sec
  ball.moving = true
  ball.bounces = 0

  Net.set_bot_direction(ball.bot_id, direction)
  ball.last_activity = world_time
end

local function load_placeholders()
  placeholders_loaded = true
  local area_id = CONFIG.area_id

  local object_ids = Net.list_objects(area_id)
  for _, oid in ipairs(object_ids) do
    local o = Net.get_object_by_id(area_id, oid)
    if placeholder_matches(o) then
      -- hide the placeholder point
      Net.set_object_visibility(area_id, oid, false)

      local props = o.custom_properties or {}
      local name = o.name or ("SoccerBall_" .. tostring(oid))
      local initial_dir = props["Direction"] or "Down"
      local asset_name = props["Asset Name"] -- you’ll add this

      balls[oid] = {
        area_id = area_id,
        placeholder_id = oid,
        name = name,

        spawn = { x = o.x, y = o.y, z = o.z or 0 },
        initial_direction = initial_dir,

        asset_name = asset_name,

        bot_id = nil,

        moving = false,
        remaining = 0,
        bounces = 0,
        vx = 0,
        vy = 0,
        kick_dir = initial_dir,

        last_activity = world_time,

        per_player_last_touch = {},
        missing_asset_warned = false,
      }

      dprint("found placeholder", oid, name, "at", o.x, o.y, o.z or 0)
      ensure_bot(balls[oid])
    end
  end
end

Net:on("tick", function(event)
  world_time = world_time + (event.delta_time or 0)

  -- Wait until the area exists (server loads areas by filename without extension) :contentReference[oaicite:3]{index=3}
  if not placeholders_loaded then
    local ok = false
    for _, a in ipairs(Net.list_areas()) do
      if a == CONFIG.area_id then ok = true break end
    end
    if ok then
      load_placeholders()
    end
  end

  -- Movement update (every tick)
  for _, ball in pairs(balls) do
    if ensure_bot(ball) then
      local pos = Net.get_bot_position(ball.bot_id)
      local z = pos.z

      -- If we ever end up on void, snap back immediately
      if blocked(ball.area_id, pos.x, pos.y, z) then
        reset_ball(ball, "glitched onto void/blocked")
      else
        if ball.moving and ball.remaining > 0 then
          local dt = event.delta_time or 0
          local step_x = ball.vx * dt
          local step_y = ball.vy * dt

          local nx = pos.x + step_x
          local ny = pos.y + step_y

          if blocked(ball.area_id, nx, ny, z) then
            if ball.bounces < CONFIG.max_bounces_per_kick then
              ball.bounces = ball.bounces + 1
              ball.vx = -ball.vx
              ball.vy = -ball.vy
              ball.kick_dir = OPP_DIR[ball.kick_dir] or ball.kick_dir
              Net.set_bot_direction(ball.bot_id, ball.kick_dir)
            else
              ball.moving = false
              ball.remaining = 0
            end
          else
            Net.move_bot(ball.bot_id, nx, ny, z)
            ball.remaining = ball.remaining - dt
            ball.last_activity = world_time

            if ball.remaining <= 0 then
              ball.moving = false
              ball.remaining = 0
              ball.bounces = 0
            end
          end
        end

        -- Inactivity reset (only when not currently moving)
        if (not ball.moving) and (world_time - (ball.last_activity or 0) >= CONFIG.reset_after_inactive_sec) then
          reset_ball(ball, "inactive timeout")
        end
      end
    end
  end

  -- Cheap proximity scan (rate-limited)
  if world_time < next_scan_time then return end
  next_scan_time = world_time + CONFIG.scan_interval_sec

  local players = Net.list_players(CONFIG.area_id)
  if not players or #players == 0 then return end

  for _, ball in pairs(balls) do
    if ensure_bot(ball) then
      local bpos = Net.get_bot_position(ball.bot_id)

      for _, pid in ipairs(players) do
        local ppos = Net.get_player_position(pid)
        if ppos and ppos.z == bpos.z then
          local dx = ppos.x - bpos.x
          local dy = ppos.y - bpos.y
          local dist2 = dx*dx + dy*dy

          if dist2 <= (CONFIG.touch_radius_tiles * CONFIG.touch_radius_tiles) then
            local last = ball.per_player_last_touch[pid] or -1e9
            if (world_time - last) >= CONFIG.per_player_cooldown_sec then
              local pdir = Net.get_player_direction(pid) or "Down"
              kick_ball(ball, pdir)
              ball.per_player_last_touch[pid] = world_time
            end
          end
        end
      end
    end
  end
end)
