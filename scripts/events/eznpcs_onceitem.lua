-- scripts/events/eznpcs_onceitem.lua
-- Dialogue Type "onceitem": unique, server-wide rental with renewals
-- Dialogue Type "oncepass": renter sets/clears a visitor password for the HP checkpoint
-- Dialogue Type "oncehub": renter hub (password + decorate HP with live preview)
--
-- Checkpoint integration:
--   Any object of type "Checkpoint" with custom property:
--     Once Key = <same unique key as the NPC>   (e.g., "House.A.Key")
--   Behavior:
--     • Owner (current renter) opens immediately
--     • Visitors open with renter-defined password (via oncepass)
--     • Gate hides-for-session only (reappears on relog or lease change)
--     • Password auto-clears when lease expires or changes owner
--
-- Loader (in eznpcs_events.lua): helpers.safe_require('scripts/events/eznpcs_onceitem')

-- ====================== Requires ======================
local eznpcs   = require('scripts/ezlibs-scripts/eznpcs/eznpcs')
local helpers  = require('scripts/ezlibs-scripts/helpers')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local ezmenus  = require('scripts/ezlibs-scripts/ezmenus')
local ezweather = require('scripts/ezlibs-scripts/ezweather')

-- ====================== Text Defaults ======================
local DEFAULTS = {
  -- onceitem (dialogue)
  RentPrompt          = "Rent the {item} for {price}$? It will expire on {date}.",
  DeclinedText        = "All good! Come back anytime.",
  DeclinedNext        = nil, -- end conversation by default
  RenewPrompt         = "You rent this until {date}. Renew for {price}$?",
  RenewedText         = "Renewed! New expiry: {date}.",
  OwnedText           = "{owner} already has the {item} until {date}.",
  SoldText            = "It's yours, {owner}! ({item}) Expires {date}.",
  NoMoneyText         = "You don't have enough.",
  BusyText            = "Someone else is being served—try again in a moment.",
  BusyNext            = nil, -- end conversation by default
  SkipRentConfirm     = "false",

  -- oncepass (butler)
  NotRenterText       = "Only the current renter can do that.",
  PassAction          = "set",
  PassPrompt          = "Enter a password (1-24 chars):",
  PassSavedText       = "Password saved.",
  PassClearedText     = "Password cleared.",

  -- checkpoint (object)
  CP_Description              = "It's a Security Cube.",
  CP_VisitorPasswordPrompt    = "Please input the password.",
  CP_WrongPasswordMessage     = "Incorrect password.",
  CP_OwnerUnlockedMessage     = "Access granted.",
  CP_LeaseInactiveMessage     = "This HP is not currently rented.",
  CP_UnlockingAssetName       = "bn5cubegreen_bot",
  CP_UnlockingAnimationTimeMS = "0",
  CP_UnlockingSoundPath       = "/server/assets/ezlibs-assets/sfx/panel_change.ogg",
}

-- ====================== Session state for oncehub ======================
local ONCEHUB = {
  -- [player_id] = {
  --   area_id, once_key, bucket_area_id,
  --   mode = 'place'|'remove',
  --   object_gid, preview_id,
  --   template_layer_name, prototype,
  --   template_dims_w, template_dims_h,
  --   cursor_distance,
  --   _blink,
  --   active = true
  -- }
  sessions = {},
}

local ONCEHUB_CATALOG = {
  { id = "bus_stop",       name = "Bus Stop",       gid = 259, layer = "Object Layer 2" },
  { id = "robot_toy",  name = "Robot Toy",  ts_source = "../assets/objects/toy.tsx", gid = 260, layer = "Object Layer 2" },
  { id = "green_tree",  name = "Green Cyber Tree",  ts_source = "../assets/objects/tree.tsx", gid = 261, layer = "Object Layer 2" },
  { id = "blue_tree",  name = "Blue Cyber Tree",  ts_source = "../assets/objects/tree.tsx", gid = 265, layer = "Object Layer 2" },
  { id = "stuffed_bear",  name = "Stuffed Bear",  ts_source = "../assets/objects/Teddy.tsx", gid = 269, layer = "Object Layer 2" },
  { id = "lan_tile",  name = "Animated HP Tile",  ts_source = "../assets/objects/LanHpAnimatedTiles.tsx", gid = 270, layer = "Object Layer 2" },
  { id = "junk_1",  name = "Junk Pile",  ts_source = "../assets/objects/Junkpiles.tsx", gid = 274, layer = "Object Layer 2" },
  { id = "cyber_duck",  name = "Cyber Duck",  ts_source = "../assets/objects/Ducky.tsx", gid = 2147483932, layer = "Object Layer 2" },
  { id = "welcome_coffee",  name = "Welcome Coffee Sign",  ts_source = "../assets/objects/coffee.tsx", gid = 285, layer = "Object Layer 2" },
  { id = "spinning_top",  name = "Spinning Top",  ts_source = "../assets/objects/beyblade.tsx", gid = 289, layer = "Object Layer 2" },
  { id = "red_boss",  name = "Red Boss Marker",  ts_source = "../assets/objects/EXE6_boss_markers.tsx", gid = 2147483924, layer = "Object Layer 2" },
  { id = "blue_boss",  name = "Blue Boss Marker",  ts_source = "../assets/objects/EXE6_boss_markers.tsx", gid = 2147483926, layer = "Object Layer 2" },
  { id = "yellow_boss",  name = "Yellow Boss Marker",  ts_source = "../assets/objects/EXE6_boss_markers.tsx", gid = 2147483928, layer = "Object Layer 2" },
  { id = "purple_boss",  name = "Purple Boss Marker",  ts_source = "../assets/objects/EXE6_boss_markers.tsx", gid = 2147483930, layer = "Object Layer 2" },
  { id = "protoman_doll",  name = "Protoman Doll",  ts_source = "../assets/objects/BoktaiDolls28x33.tsx", gid = 2147483947, layer = "Object Layer 2" },
  { id = "megaman_doll",  name = "Megaman Doll",  ts_source = "../assets/objects/BoktaiDolls28x33.tsx", gid = 2147483946, layer = "Object Layer 2" },
  { id = "otenko_doll",  name = "Otenko Doll",  ts_source = "../assets/objects/BoktaiDolls28x33.tsx", gid = 2147483943, layer = "Object Layer 2" },
  { id = "doronbo_doll",  name = "Doronbo Doll",  ts_source = "../assets/objects/BoktaiDolls28x33.tsx", gid = 2147483945, layer = "Object Layer 2" },
  { id = "okenko_doll",  name = "Okenko Doll",  ts_source = "../assets/objects/BoktaiDolls28x33.tsx", gid = 2147483944, layer = "Object Layer 2" },
}

local MENU_COLOR = {
  YELLOW = {r=245,g=210,b=70},
  GREEN  = {r=60, g=170,b=90},
  BLUE   = {r=80, g=140,b=220},
}

-- ====================== Small helpers ======================
local function _path_tail(p)
  p = tostring(p or "")
  -- compare by tail so relative vs absolute doesn’t matter
  return (p:gsub("\\","/"):gsub(".*/",""))
end

-- Resolve a catalog entry to a gid for the current map
local function catalog_resolve_gid(area_id, entry)
  if entry.gid then return tonumber(entry.gid) end
  if not (entry.ts_source and entry.local_id) then return nil end
  local ok, xml = pcall(Net.map_to_string, area_id)
  if not ok or type(xml) ~= "string" then return nil end
  local tail = _path_tail(entry.ts_source)
  for fg, src in xml:gmatch('<tileset%s+[^>]*firstgid="(%d+)"[^>]*source="([^"]+)"') do
    if _path_tail(src) == tail then
      local first = tonumber(fg)
      if first then return first + tonumber(entry.local_id or 0) end
    end
  end
  -- also handle reversed attr order
  for src, fg in xml:gmatch('<tileset%s+[^>]*source="([^"]+)"[^>]*firstgid="(%d+)"') do
    if _path_tail(src) == tail then
      local first = tonumber(fg)
      if first then return first + tonumber(entry.local_id or 0) end
    end
  end
  return nil
end

-- Lookup friendly name/id by gid (for older placed objects that lack oncehub_name)
local function catalog_entry_by_gid(area_id, gid)
  gid = tonumber(gid or 0)
  if gid <= 0 then return nil end
  for _, e in ipairs(ONCEHUB_CATALOG) do
    local egid = catalog_resolve_gid(area_id, e) or e.gid
    if egid and egid == gid then return e end
  end
  return nil
end

local function dprop(dialogue, key, default)
  local v = dialogue and dialogue.custom_properties and dialogue.custom_properties[key] or nil
  if v == nil or v == "" then return default end
  return v
end

local function cprop(obj_custom, key, default)
  local v = obj_custom and obj_custom[key] or nil
  if v == nil or v == "" then return default end
  return v
end

local function normalize_key(s)
  return (tostring(s or ""):gsub("^%s+",""):gsub("%s+$",""))
end

local DEFAULT_MEM_AREA = "WCity1"

local function resolve_mem_area_id(dialogue, player_id, obj_custom)
  local v = nil
  if obj_custom then v = normalize_key(obj_custom["Memory Area"]) end
  if (not v or v == "") and dialogue and dialogue.custom_properties then
    v = normalize_key(dialogue.custom_properties["Memory Area"])
  end
  if (not v or v == "") and player_id then
    v = Net.get_player_area(player_id)
  end
  if not v or v == "" then v = DEFAULT_MEM_AREA end
  return v
end

local function say(player_id, text, mug)
  if text and text ~= "" then
    return Async.message_player(player_id, text, mug and mug.texture_path, mug and mug.animation_path)
  end
  return Async.sleep(0)
end

local function ask_yes_no(player_id, prompt, mug)
  local res = await(Async.question_player(player_id, prompt, mug and mug.texture_path, mug and mug.animation_path))
  return res == 1 -- 1=Yes
end

local function ask_text(player_id, prompt, mug)
  await(say(player_id, prompt or "Enter text:", mug))
  return await(Async.prompt_player(player_id))
end

local function fmt(ts)
  if not ts then return "unknown" end
  return os.date("%Y-%m-%d %H:%M", ts)
end

local function add_months(ts, months)
  local t = os.date("*t", ts)
  local y, m = t.year, t.month + (months or 0)
  y = y + math.floor((m - 1) / 12)
  m = ((m - 1) % 12) + 1
  local d = math.min(t.day, 28)
  return os.time{year=y, month=m, day=d, hour=t.hour, min=t.min, sec=t.sec}
end

local function compute_period(now_ts, months, minutes)
  if minutes and minutes > 0 then
    return now_ts, now_ts + minutes * 60
  end
  months = months or 1
  return now_ts, add_months(now_ts, months)
end

local function resolve_manual_purchased_at(dialogue, now_ts)
  local cron_like  = dialogue and dialogue.custom_properties and dialogue.custom_properties["Purchased At Date"]
  local epoch_str  = dialogue and dialogue.custom_properties and dialogue.custom_properties["Purchased At Epoch"]
  local offset_hrs = tonumber(dialogue and dialogue.custom_properties and dialogue.custom_properties["Purchased At Offset Hours"] or "0")
  if cron_like and cron_like ~= "" then
    local ts = helpers.date_string_to_timestamp(cron_like)
    if ts then return ts end
  end
  if epoch_str and epoch_str ~= "" then
    local n = tonumber(epoch_str); if n and n > 0 then return n end
  end
  if offset_hrs ~= 0 then
    return now_ts + math.floor(offset_hrs * 3600)
  end
  return nil
end

-- === Menu-close debounce (prevents stray A from hitting checkpoints) ===
local MENU_DEBOUNCE = {}  -- [pid] -> boolean
local function menu_closed_now(pid, secs)
  secs = secs or 0.30
  MENU_DEBOUNCE[pid] = true
  async(function()
    await(Async.sleep(secs))
    MENU_DEBOUNCE[pid] = false
  end)
end
local function recently_closed_menu(pid)
  return MENU_DEBOUNCE[pid] == true
end

local function fast_close_board(pid)
  pcall(Net.close_bbs, pid)          -- close immediately (non-blocking)

  -- Give the UI one tick to tear down. Some engines require >0, so use 0.01s.
  -- (If your Async allows 0, you can change to 0 to be even snappier.)
  await(Async.sleep(0))

  -- Brief input shield so no other plugin sees the close press
  menu_closed_now(pid, 0.01)         -- locks/unlocks input for ~400ms
end

-- ====================== Memory helpers ======================
local function ensure_bucket_mem(BUCKET_AREA_ID)
  local mem = ezmemory.get_area_memory(BUCKET_AREA_ID) or ezmemory.get_area_memory(BUCKET_AREA_ID)
  if not mem then error("Failed to initialize area memory for "..tostring(BUCKET_AREA_ID)) end
  local mutated = false
  if mem.hidden_objects == nil then mem.hidden_objects = {}; mutated = true end
  if mem.onceitems      == nil then mem.onceitems      = {}; mutated = true end
  if mutated then ezmemory.save_area_memory(BUCKET_AREA_ID) end
  return mem
end

local function purge_player_key_if_invalid(player_id, BUCKET_AREA_ID, once_key, item_name)
  if not (ezmemory.count_player_item and ezmemory.remove_player_item) then return end
  if not item_name or item_name == "" then return end
  local have = (ezmemory.count_player_item(player_id, item_name) or 0) > 0
  if not have then return end
  local mem = ensure_bucket_mem(BUCKET_AREA_ID)
  local rec = mem.onceitems[once_key]
  local now = os.time()
  local secret = helpers.get_safe_player_secret(player_id)
  local valid = rec and rec.expires_at and rec.expires_at > now and rec.owner_secret == secret
  if not valid then
    ezmemory.remove_player_item(player_id, item_name, 999999)
    print(("[onceitem] removed expired key %s from %s"):format(item_name, Net.get_player_name(player_id)))
  end
end

local function get_record_and_prune(BUCKET_AREA_ID, once_key)
  local mem = ensure_bucket_mem(BUCKET_AREA_ID)
  local rec = mem.onceitems[once_key]
  if not rec then return mem, nil end
  if not rec.expires_at or rec.expires_at <= os.time() then
    if rec.password then rec.password = nil; ezmemory.save_area_memory(BUCKET_AREA_ID) end
    return mem, rec
  end
  return mem, rec
end

function eznpcs.player_has_active_lease(player_id, once_key, bucket_area_id)
  local now = os.time()
  local secret = helpers.get_safe_player_secret(player_id)
  local function check_area(area_id)
    local mem = ezmemory.get_area_memory(area_id) or ezmemory.get_area_memory(area_id)
    if not mem or not mem.onceitems then return false end
    local rec = mem.onceitems[once_key]
    return rec and rec.expires_at and rec.expires_at > now and rec.owner_secret == secret
  end
  if bucket_area_id and bucket_area_id ~= "" then
    return check_area(bucket_area_id)
  end
  local cur = Net.get_player_area(player_id)
  if check_area(cur) then return true end
  local areas = Net.list_areas() or {}
  for _,aid in ipairs(areas) do
    if aid ~= cur and check_area(aid) then return true end
  end
  return false
end

-- ====================== oncehub core (preview + placement + remove) ======================
local function stop_session(player_id, reason)
  local s = ONCEHUB.sessions[player_id]
  if not s then return end
  s.active = false

  -- remove the tracked preview
  if s.preview_id then pcall(function() Net.remove_object(s.area_id, s.preview_id) end) end

  -- remove the tracked removal cursor (if any)
  if s.rem_cursor_id then pcall(function() Net.remove_object(s.area_id, s.rem_cursor_id) end) end

  -- also purge any stray previews for this once_key in the area
  for _, oid in ipairs(Net.list_objects(s.area_id) or {}) do
    local o  = Net.get_object_by_id(s.area_id, oid)
    local cp = o and o.custom_properties
    if cp and cp.oncehub_preview == "true"
       and (cp.oncehub_key or "") == (s.once_key or "") then
      pcall(Net.remove_object, s.area_id, oid)
    end
  end
  if s.rem_cursor_id then
    pcall(function() Net.remove_object(s.area_id, s.rem_cursor_id) end)
  end
  ONCEHUB.sessions[player_id] = nil
  if reason and reason ~= "" then Async.message_player(player_id, reason) end
end

-- Resolve a test GID (dialogue "Test GID" overrides; else tileset named like Bus Stop; else TMX scan)
local function try_resolve_test_gid(dialogue, area_id)
  local gid = tonumber(dialogue and dialogue.custom_properties and dialogue.custom_properties["Test GID"] or "")
  if gid and gid > 0 then return gid end
  local function norm(s) return (tostring(s or "")):lower() end
  local function looks_like_bus_stop(s)
    s = norm(s); return s:find("bus stop",1,true) or s:find("bus_stop",1,true) or s:find("busstop",1,true)
  end
  local ok, tilesets = pcall(Net.list_tilesets, area_id)
  if ok and type(tilesets) == "table" then
    for _, ts in ipairs(tilesets) do
      if looks_like_bus_stop(ts.name) or looks_like_bus_stop(ts.display_name) then
        local fg = tonumber(ts.first_gid or ts.firstgid or ts.firstGid); if fg and fg > 0 then return fg end
      end
    end
    for _, ts in ipairs(tilesets) do
      if looks_like_bus_stop(ts.source) or looks_like_bus_stop(ts.path) or looks_like_bus_stop(ts.filename) then
        local fg = tonumber(ts.first_gid or ts.firstgid or ts.firstGid); if fg and fg > 0 then return fg end
      end
    end
  end
  local ok2, xml = pcall(Net.map_to_string, area_id)
  if ok2 and type(xml) == "string" then
    for source, fg in xml:gmatch('<tileset%s+[^>]*source="([^"]+)"[^>]*firstgid="(%d+)"') do
      if looks_like_bus_stop(source) then local n=tonumber(fg); if n and n>0 then return n end end
    end
    for fg, source in xml:gmatch('<tileset%s+[^>]*firstgid="(%d+)"[^>]*source="([^"]+)"') do
      if looks_like_bus_stop(source) then local n=tonumber(fg); if n and n>0 then return n end end
    end
  end
  return nil
end

local REM_CURSOR_TSX_TAIL  = "edit_mode_tile_removal_cursor.tsx" -- filename only
local REM_CURSOR_LOCAL_ID  = 0   -- tile index inside that .tsx (usually 0)
local REM_CURSOR_TILE_SIZE = 1   -- width/height to use for the cursor (in tile units)

local function resolve_removal_cursor_gid(area_id)
  local ok, xml = pcall(Net.map_to_string, area_id)
  if not ok or type(xml) ~= "string" then return nil end
  local want = REM_CURSOR_TSX_TAIL:lower()

  -- exact tail match (both attribute orders)
  for fg, src in xml:gmatch('<tileset%s+[^>]*firstgid="(%d+)"[^>]*source="([^"]+)"') do
    if _path_tail(src):lower() == want then return (tonumber(fg) or 0) + REM_CURSOR_LOCAL_ID end
  end
  for src, fg in xml:gmatch('<tileset%s+[^>]*source="([^"]+)"[^>]*firstgid="(%d+)"') do
    if _path_tail(src):lower() == want then return (tonumber(fg) or 0) + REM_CURSOR_LOCAL_ID end
  end

  -- looser fallback: any tileset with that stem in its filename
  for fg, src in xml:gmatch('<tileset%s+[^>]*firstgid="(%d+)"[^>]*source="([^"]+)"') do
    if _path_tail(src):lower():find("edit_mode_tile_removal_cursor", 1, true) then
      return tonumber(fg)
    end
  end
  for src, fg in xml:gmatch('<tileset%s+[^>]*source="([^"]+)"[^>]*firstgid="(%d+)"') do
    if _path_tail(src):lower():find("edit_mode_tile_removal_cursor", 1, true) then
      return tonumber(fg)
    end
  end

  return nil
end

-- ---------- DIMENSIONS: prototype → TMX layer → tileset image ----------
local function _tmx_read_map_tilesize(xml)
  local tw = tonumber(xml:match('tilewidth="(%d+)"') or xml:match('tilewidth="(%d+%.%d+)"')) or 0
  local th = tonumber(xml:match('tileheight="(%d+)"') or xml:match('tileheight="(%d+%.%d+)"')) or 0
  return tw, th
end

local function find_prototype_for_gid(area_id, target_gid)
  target_gid = tonumber(target_gid or 0)
  if not target_gid or target_gid <= 0 then return nil end
  local ids = Net.list_objects(area_id) or {}
  for _, oid in ipairs(ids) do
    local o = Net.get_object_by_id(area_id, oid)
    local gid = o and o.data and tonumber(o.data.gid)
    if gid and gid == target_gid and o.width and o.height then
      return o -- first exact match wins
    end
  end
  return nil
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
      local wt, ht = (wpx / tw), (hpx / th) -- keep fractional tiles
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
  local map_tw, map_th = _tmx_read_map_tilesize(xml)
  if map_tw == 0 or map_th == 0 then return nil, nil end
  local tile_px_w = tonumber(ts.tile_width  or ts.tilewidth  or ts.tileWidth)
  local tile_px_h = tonumber(ts.tile_height or ts.tileheight or ts.tileHeight)
  if not tile_px_w or not tile_px_h then return nil, nil end
  return (tile_px_w / map_tw), (tile_px_h / map_th)
end

local function resolve_object_dims(area_id, template_layer_name, gid)
  -- 1) Prototype instance on the current map
  local proto = find_prototype_for_gid(area_id, gid)
  if proto then
    return tonumber(proto.width) or 1, tonumber(proto.height) or 1, "proto"
  end
  -- 2) TMX layer scan
  local wt, ht = get_template_dims_from_layer(area_id, template_layer_name, gid)
  if wt and ht then return wt, ht, "tmx" end
  -- 3) Tileset image size → tiles
  local gw, gh = get_gid_dims_in_tiles(area_id, gid)
  if gw and gh then return gw, gh, "tileset" end
  -- 4) Give up
  return 1, 1, "default"
end

-- ---------- Cursor helpers ----------
local function dir_to_offset(dir)
  if     dir == "Left"       then return -1, 0
  elseif dir == "Right"      then return  1, 0
  elseif dir == "Up"         then return  0,-1
  elseif dir == "Down"       then return  0, 1
  elseif dir == "Up Left"    then return -1,-1
  elseif dir == "Up Right"   then return  1,-1
  elseif dir == "Down Left"  then return -1, 1
  elseif dir == "Down Right" then return  1, 1
  else return 0,1 end
end

-- NEW: normalized fractional cursor distance
local function get_cursor_point(player_id, dist)
  local ok_pos, pos = pcall(Net.get_player_position, player_id)
  if not ok_pos or not pos then return nil end  -- player not available yet

  local dx, dy = 0, 1
  local ok_dir, dir = pcall(Net.get_player_direction, player_id)
  if ok_dir and dir then
    dx, dy = dir_to_offset(dir)
    if dx ~= 0 and dy ~= 0 then
      local inv = 1 / math.sqrt(2)
      dx, dy = dx * inv, dy * inv
    end
  end

  return pos.x + dx * dist, pos.y + dy * dist, pos.z
end

local function object_covers_point(o, x, y, z)
  if not o or o.z ~= z then return false end
  local ox, oy = o.x, o.y
  local ow, oh = o.width or 1, o.height or 1
  return (x >= ox and x < ox + ow and y >= oy and y < oy + oh)
end

local function find_oncehub_object_at(area_id, x, y, z)
  local ids = Net.list_objects(area_id) or {}
  for _, oid in ipairs(ids) do
    local o = Net.get_object_by_id(area_id, oid)
    if o and o.custom_properties
       and o.custom_properties.placed_by_oncehub == "true"
       and not (o.custom_properties.oncehub_preview == "true")
       and object_covers_point(o, x, y, z) then
      return o, oid
    end
  end
  return nil, nil
end

-- TMX flip flags (see Tiled docs)
local FLIP_H = 0x80000000
local FLIP_V = 0x40000000
local FLIP_D = 0x20000000

local function decode_gid_flags(raw)
  local g = tonumber(raw or 0) or 0
  local fh = false; if g >= FLIP_H then fh = true; g = g - FLIP_H end
  local fv = false; if g >= FLIP_V then fv = true; g = g - FLIP_V end
  local fr = false; if g >= FLIP_D then fr = true; g = g - FLIP_D end
  return g, fh, fv, fr  -- base_gid, horiz, vert, diagonal(“rotated”)
end

-- Return the base (unflipped) gid, ignoring TMX flip bits
local function gid_base(raw_gid)
  local base = select(1, decode_gid_flags(raw_gid))
  return base
end

-- Read flip flags for a gid from a specific TMX object layer (by name)
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

-- Prefer live prototype object (if present), else TMX layer (Object Layer 1/2), else defaults
local function resolve_preview_flip_flags(area_id, template_layer_name, base_gid, def_fh, def_fv, def_fr)
  -- 1) Live prototype object on the map
  local proto = find_prototype_for_gid(area_id, base_gid)
  if proto and proto.data then
    local td = proto.data
    return td.flipped_horizontally or false,
           td.flipped_vertically   or false,
           td.rotated              or false
  end

  -- 2) TMX layers (try provided template layer, then common ones)
  local try_layers = { template_layer_name, "Object Layer 1", "Object Layer 2" }
  for _, lname in ipairs(try_layers) do
    local fh, fv, fr = _tmx_flip_flags_from_layer(area_id, lname, base_gid)
    if fh ~= nil then return fh, fv, fr end
  end

  -- 3) Fallback: whatever we already had
  return def_fh, def_fv, def_fr
end

-- ---------- Preview follow ----------
local function ensure_preview(player_id)
  local s = ONCEHUB.sessions[player_id]; if not s or not s.active then return end

if s.mode == 'remove' then
  local dist = s.cursor_distance or 0.75
  local cx, cy, cz = get_cursor_point(player_id, dist)
  if not cx then return end  -- player not ready this tick

  -- Which object would we remove right now?
  local target, _ = find_oncehub_object_at(s.area_id, cx, cy, cz)

  -- ===== 1) Cursor: always visible =====
if s.rem_cursor_gid then
  -- If there's a target, cursor hugs its bounds; otherwise follow the aim point at 1x1
  local tx, ty, tz, tw, th
  local want_fh, want_fv, want_fr

  if target then
    tx, ty, tz = target.x, target.y, target.z
    tw, th     = target.width or 1, target.height or 1
    -- When we have a target, keep the cursor un-flipped (overlay shape is driven by size)
    want_fh, want_fv, want_fr = false, false, false
  else
    tx, ty, tz = cx, cy, cz
    tw, th     = REM_CURSOR_TILE_SIZE, REM_CURSOR_TILE_SIZE

    -- 64×32 isometric-friendly “square”: diagonal + vertical flip
    -- (This makes a square-looking overlay instead of a diamond.)
    want_fh, want_fv, want_fr = false, true, true
  end

  local base_gid = gid_base(s.rem_cursor_gid)
  local must_recreate = (not s.rem_cursor_id)
                     or (s._rem_w ~= tw) or (s._rem_h ~= th)
                     or (s._rem_fh ~= want_fh) or (s._rem_fv ~= want_fv) or (s._rem_fr ~= want_fr)

  if must_recreate then
    if s.rem_cursor_id then pcall(function() Net.remove_object(s.area_id, s.rem_cursor_id) end) end
    s.rem_cursor_id = Net.create_object(s.area_id, {
      name   = "",
      class  = "DecorRemoveCursor",
      visible= true,
      x = tx, y = ty, z = tz,
      width = tw, height = th,
      rotation = 0,
      data = {
        type = "tile",
        gid  = base_gid,
        flipped_horizontally = want_fh,
        flipped_vertically   = want_fv,
        rotated              = want_fr,
      },
      custom_properties = {
        placed_by_oncehub = "preview",
        oncehub_preview   = "true",
        oncehub_key       = s.once_key,
        passable          = "true",
      }
    })
    s._rem_w, s._rem_h = tw, th
    s._rem_fh, s._rem_fv, s._rem_fr = want_fh, want_fv, want_fr
  else
    pcall(Net.move_object, s.area_id, s.rem_cursor_id, tx, ty, tz)
  end
end

  -- ===== 2) Blink overlay only if a removable target is under the selector =====
  if not target then
    if s.preview_id then pcall(function() Net.remove_object(s.area_id, s.preview_id) end); s.preview_id = nil end
    return
  end

  s._blink = not s._blink
  local td = target.data or {}
  local base_fh = td.flipped_horizontally or false
  local base_fv = td.flipped_vertically   or false
  local base_fr = td.rotated              or false
  local info = {
    name = "",
    class = "DecorRemovePreview",
    visible = true,
    x = target.x, y = target.y, z = target.z,
    width = target.width or 1, height = target.height or 1,
    rotation = 0,
    data = {
      type = "tile",
      gid  = td.gid or 0,
      flipped_horizontally = (s._blink and (not base_fh)) or base_fh, -- blink
      flipped_vertically   = base_fv,
      rotated              = base_fr,
    },
    custom_properties = {
      placed_by_oncehub = "preview",
      oncehub_preview   = "true",
      oncehub_key       = s.once_key,
      passable          = "true",
    }
  }

  if s.preview_id then pcall(function() Net.remove_object(s.area_id, s.preview_id) end); s.preview_id = nil end
  s.preview_id = Net.create_object(s.area_id, info)
  return
end

  -- PLACE mode preview: keep ONE preview and MOVE it each tick (no re-creates)
  local dist = s.cursor_distance or 0.75
  local cx, cy, cz = get_cursor_point(player_id, dist)
  if not cx then return end
  local w, h = resolve_object_dims(s.area_id, s.template_layer_name or "Object Layer 2", s.object_gid)

  -- If we already have a preview, just move it to the new cursor position
  if s.preview_id then
    pcall(Net.move_object, s.area_id, s.preview_id, cx, cy, cz)
    return
  end

  -- First tick of session: purge any stale previews for this once_key in this area
  for _, oid in ipairs(Net.list_objects(s.area_id) or {}) do
    local o  = Net.get_object_by_id(s.area_id, oid)
    local cp = o and o.custom_properties
    if cp and cp.oncehub_preview == "true"
       and (cp.oncehub_key or "") == (s.once_key or "") then
      pcall(Net.remove_object, s.area_id, oid)
    end
  end

  -- Create the single preview object and remember its id
  local base_gid, fh, fv, fr = decode_gid_flags(s.object_gid)
  fh, fv, fr = resolve_preview_flip_flags(
    s.area_id,
    s.template_layer_name or "Object Layer 2",  -- your existing template-layer setting
    base_gid,
    fh, fv, fr
  )
  s.preview_id = Net.create_object(s.area_id, {
    name = "",
    class = "DecorPreview",
    visible = true,
    x = cx, y = cy, z = cz,
    width = w, height = h,
    rotation = 0,
    data = {
      type = "tile",
      gid  = base_gid,
      flipped_horizontally = fh,
      flipped_vertically   = fv,
      rotated              = fr,
    },
    custom_properties = {
      placed_by_oncehub = "preview",
      oncehub_preview   = "true",
      oncehub_key       = s.once_key,   -- tag with this HP key
      passable          = "true"
    }
  })
end

-- ====================== Decor inventory (per-player; ONCEHUB_CATALOG-only) ======================
-- Stored separately from ezlibs item inventory to avoid mixing with other items.

local function _decor_ci(dialogue)
  local ci = {}
  for k,v in pairs(dialogue.custom_properties or {}) do
    ci[string.lower(tostring(k))] = v
  end
  return ci
end
local function _decor_get_prop_ci(ci, key) return ci[string.lower(key)] end

local function _catalog_by_id(id)
  for _, e in ipairs(ONCEHUB_CATALOG) do
    if e.id == id then return e end
  end
  return nil
end

local function _player_decor_mem(pid)
  local pm = ezmemory.get_player_memory(pid)
  pm.decor_inventory = pm.decor_inventory or {}   -- { [id]=count }
  return pm.decor_inventory, pm
end

local function decor_count_owned(pid, id)
  local inv = _player_decor_mem(pid)
  return tonumber(inv[id] or 0)
end

local function decor_add_owned(pid, id, qty)
  qty = tonumber(qty or 0) or 0
  if qty == 0 then return end
  local inv, pm = _player_decor_mem(pid)
  inv[id] = (tonumber(inv[id] or 0) or 0) + qty
  if ezmemory.save_player_memory then ezmemory.save_player_memory(pid) end
end

local function count_placed_in_area_by_key(area_id, once_key, object_id)
  local c = 0
  local ids = Net.list_objects(area_id)
  for _, oid in ipairs(ids) do
    local o = Net.get_object_by_id(area_id, oid)
    local cp = o and o.custom_properties
    if cp and cp.placed_by_oncehub == "true" and cp.oncehub_id == object_id then
      -- Count only objects placed for THIS HP/renter
      if cp.oncehub_key == once_key then c = c + 1 end
    end
  end
  return c
end

local function decor_left_to_place(pid, area_id, once_key, object_id)
  local owned  = decor_count_owned(pid, object_id)
  local placed = count_placed_in_area_by_key(area_id, once_key, object_id)
  local left   = owned - placed
  if left < 0 then left = 0 end
  return left, owned, placed
end

local function short_money(n)  -- tiny UI helper like your pack shop
  n = tonumber(n) or 0
  local abs = math.abs(n)
  if abs >= 1e9 then return string.format("$%dB", math.floor(n/1e9 + 0.5))
  elseif abs >= 1e6 then
    local v = n/1e6
    if v >= 10 or v == math.floor(v) then return string.format("$%dM", math.floor(v + 0.5))
    else return string.format("$%.1fM", v) end
  elseif abs >= 1e3 then
    local v = n/1e3
    if v >= 10 or v == math.floor(v) then return string.format("$%dk", math.floor(v + 0.5))
    else return string.format("$%.1fk", v) end
  else
    return string.format("$%d", n)
  end
end

-- Price resolution: first NPC property "Price <id>" (case-insensitive), else entry.price, else default
local DECOR_DEFAULT_PRICE = 1000
local function price_for(dialogue, id)
  local ci = _decor_ci(dialogue)
  local p = _decor_get_prop_ci(ci, "Price "..id)
  p = tonumber(p or nil)
  if not p then
    local e = _catalog_by_id(id); if e and e.price then p = tonumber(e.price) end
  end
  return p or DECOR_DEFAULT_PRICE
end

-- Price resolution with index:
--  1) "Price N" (matches the corresponding "Sell N")
--  2) legacy: "Price <id>"
--  3) entry.price in ONCEHUB_CATALOG
--  4) DECOR_DEFAULT_PRICE
local DECOR_DEFAULT_PRICE = DECOR_DEFAULT_PRICE or 1000

local function _catalog_by_id(id)
  for _, e in ipairs(ONCEHUB_CATALOG) do
    if e.id == id then return e end
  end
end

local function _decor_ci(dialogue)
  local ci = {}
  for k,v in pairs(dialogue.custom_properties or {}) do
    ci[string.lower(tostring(k))] = v
  end
  return ci
end

local function _decor_get_prop_ci(ci, key)
  return ci[string.lower(key)]
end

local function price_for_index_or_id(dialogue, idx, id)
  local ci = _decor_ci(dialogue)
  local p = _decor_get_prop_ci(ci, "Price "..tostring(idx))
  p = tonumber(p or nil)
  if not p then
    -- backward-compat for "Price bus_stop"
    p = tonumber(_decor_get_prop_ci(ci, "Price "..tostring(id)) or nil)
  end
  if not p then
    local e = _catalog_by_id(id)
    if e and e.price then p = tonumber(e.price) end
  end
  return p or DECOR_DEFAULT_PRICE
end

-- ====================== Persistent Decor Inventory ======================
local DECOR_MEM_KEY = "oncehub_decor_inventory_v1"

local function _pmem_secret(pid)
  if helpers.get_safe_player_secret then
    return helpers.get_safe_player_secret(pid)
  end
  -- Fallback if helper is missing: use player_id (less ideal)
  return pid
end

local function _pmem_get(pid)
  local secret = _pmem_secret(pid)
  local pmem = ezmemory.get_player_memory(secret) or {}
  if type(pmem[DECOR_MEM_KEY]) ~= "table" then
    pmem[DECOR_MEM_KEY] = {}
    if ezmemory.set_player_memory then
      ezmemory.set_player_memory(secret, pmem)
    elseif ezmemory.save_player_memory then
      ezmemory.save_player_memory(secret, pmem)
    end
  end
  return pmem, secret
end

local function _decor_inv(pid)
  local pmem = _pmem_get(pid)
  return pmem[DECOR_MEM_KEY]  -- pmem[1] = actual table returned above
end

local function decor_count_owned(pid, id)
  -- Only track catalog ids
  if not _catalog_by_id(id) then return 0 end
  local inv = _decor_inv(pid)
  return tonumber(inv[id] or 0)
end

local function decor_set_owned(pid, id, count)
  if not _catalog_by_id(id) then return end
  count = math.max(0, tonumber(count or 0) or 0)
  local pmem, secret = _pmem_get(pid)
  pmem[DECOR_MEM_KEY][id] = count
  if ezmemory.set_player_memory then
    ezmemory.set_player_memory(secret, pmem)
  elseif ezmemory.save_player_memory then
    ezmemory.save_player_memory(secret, pmem)
  end
end

local function decor_add_owned(pid, id, qty)
  if qty == 0 then return end
  local cur = decor_count_owned(pid, id)
  decor_set_owned(pid, id, cur + qty)
end

-- Count how many of this object the *current renter* has already placed in this HP
local function count_placed_in_area_by_key(area_id, once_key, object_id)
  local c = 0
  for _, oid in ipairs(Net.list_objects(area_id)) do
    local o = Net.get_object_by_id(area_id, oid)
    local cp = o and o.custom_properties
    if cp and cp.placed_by_oncehub == "true" and cp.oncehub_id == object_id then
      if cp.oncehub_key == once_key then c = c + 1 end
    end
  end
  return c
end

local function decor_left_to_place(pid, area_id, once_key, object_id)
  local owned  = decor_count_owned(pid, object_id)
  local placed = count_placed_in_area_by_key(area_id, once_key, object_id)
  local left   = math.max(0, owned - placed)
  return left, owned, placed
end

-- ====================== Placement persistence (area memory) ======================
-- Stores a lightweight list of placed oncehub objects, keyed by HP's Once Key.
local PLACEMENTS_MEM_KEY = "oncehub_placements_v1"

-- Collect all placed objects for this renter in this area
local function snapshot_oncehub_placements(area_id, once_key)
  local out = {}
  for _, oid in ipairs(Net.list_objects(area_id)) do
    local o = Net.get_object_by_id(area_id, oid)
    local cp = o and o.custom_properties
    if cp and cp.placed_by_oncehub == "true" and (cp.oncehub_key or "") == (once_key or "") then
      table.insert(out, {
        visible  = true,
        x = o.x, y = o.y, z = o.z,
        width = o.width, height = o.height,
        rotation = o.rotation or 0,
        -- minimal data required to recreate the tile object:
        data = o.data and {
          type = o.data.type or "tile",
          gid  = tonumber(o.data.gid or 0),
          flipped_horizontally = o.data.flipped_horizontally or false,
          flipped_vertically   = o.data.flipped_vertically   or false,
          rotated              = o.data.rotated              or false,
        } or nil,
        -- keep metadata so removal/limits still work after reboot:
        custom_properties = {
          placed_by_oncehub = "true",
          oncehub_gid  = (cp.oncehub_gid  or ""),
          oncehub_name = (cp.oncehub_name or "Object"),
          oncehub_id   = (cp.oncehub_id   or "object"),
          oncehub_key  = (cp.oncehub_key  or (once_key or "")),
        }
      })
    end
  end
  return out
end

-- Map once_key (or "area:<id>") -> owning area_id
local function _remember_key_area(mem_area, key, area_id)
  local mem = ezmemory.get_area_memory(mem_area)
  mem.oncehub_key_areas = mem.oncehub_key_areas or {}
  mem.oncehub_key_areas[key] = area_id
  ezmemory.save_area_memory(mem_area)
end

-- Save the current placement list into area memory (bucket or live area)
local function save_placements(area_id, bucket_area_id, once_key)
  local key = once_key or ("area:"..area_id)
  local mem_area = bucket_area_id or area_id

  local mem = ezmemory.get_area_memory(mem_area)
  mem[PLACEMENTS_MEM_KEY] = mem[PLACEMENTS_MEM_KEY] or {}
  mem[PLACEMENTS_MEM_KEY][key] = snapshot_oncehub_placements(area_id, once_key)

  -- remember which area this key belongs to
  mem.oncehub_key_areas = mem.oncehub_key_areas or {}
  mem.oncehub_key_areas[key] = area_id

  ezmemory.save_area_memory(mem_area)
end

-- Recreate objects from saved list if none currently exist (prevents duplicates)
local function rehydrate_placements(area_id, bucket_area_id, once_key)
  local mem = ezmemory.get_area_memory(bucket_area_id or area_id) or {}
  local saved = mem[PLACEMENTS_MEM_KEY] and mem[PLACEMENTS_MEM_KEY][once_key or ("area:"..area_id)]
  if not (saved and #saved > 0) then return false end

  -- If there are already objects for this once_key, do nothing.
  for _, oid in ipairs(Net.list_objects(area_id)) do
    local o = Net.get_object_by_id(area_id, oid)
    local cp = o and o.custom_properties
    if cp and cp.placed_by_oncehub == "true" and (cp.oncehub_key or "") == (once_key or "") then
      return false
    end
  end

  for _, obj in ipairs(saved) do
    -- defensive shallow copy
    Net.create_object(area_id, {
      visible  = obj.visible ~= false,
      x = obj.x, y = obj.y, z = obj.z,
      width = obj.width, height = obj.height,
      rotation = obj.rotation or 0,
      data = obj.data and {
        type = obj.data.type or "tile",
        gid  = tonumber(obj.data.gid or 0),
        flipped_horizontally = obj.data.flipped_horizontally or false,
        flipped_vertically   = obj.data.flipped_vertically   or false,
        rotated              = obj.data.rotated              or false,
      } or nil,
      custom_properties = {
        placed_by_oncehub = "true",
        oncehub_gid  = (obj.custom_properties and obj.custom_properties.oncehub_gid)  or "",
        oncehub_name = (obj.custom_properties and obj.custom_properties.oncehub_name) or "Object",
        oncehub_id   = (obj.custom_properties and obj.custom_properties.oncehub_id)   or "object",
        oncehub_key  = (obj.custom_properties and obj.custom_properties.oncehub_key)  or (once_key or ""),
      }
    })
  end
  return true
end

-- Convenience: call this whenever the hub/menu opens
local function ensure_rehydrated(player_id, dialogue)
  local area_id  = Net.get_player_area(player_id)
  local once_key = normalize_key(dprop(dialogue, "Once Key", ""))
  if once_key == "" then return end
  local BUCKET   = resolve_mem_area_id(dialogue, player_id, nil)
  rehydrate_placements(area_id, BUCKET, once_key)
end

-- ====================== Auto-rehydrate on area enter/transfer ======================
local function rehydrate_all_for_area(area_id)
  local tried = {}
  local function try_from(bucket_area_id)
    local mem = ezmemory.get_area_memory(bucket_area_id or area_id)
    local map = mem and mem[PLACEMENTS_MEM_KEY]
    if type(map) ~= "table" then return end
    for key, _ in pairs(map) do
      if not tried[key] then
        local allow = false

        if type(key) == "string" and key:sub(1,5) == "area:" then
          -- area-scoped snapshot: only rehydrate in the same area
          allow = (key == ("area:"..area_id))
        else
          -- once_key snapshot: only if mapping says this area owns it
          local areas = mem.oncehub_key_areas
          if areas and areas[key] == area_id then
            allow = true
          end
        end

        if allow then
          rehydrate_placements(area_id, bucket_area_id, key)
        end
        tried[key] = true
      end
    end
  end

  -- 1) try live area first
  try_from(nil)

  -- 2) also try the default bucket (covers older saves & your current bucket config)
  if DEFAULT_MEM_AREA and DEFAULT_MEM_AREA ~= area_id then
    try_from(DEFAULT_MEM_AREA)
  end
end

local function _rehydrate_from_event(ev)
  local pid = _safe_get_player(ev)
  if not pid then return end
  local area_id = _safe_get_to_area(ev, pid)
  if not area_id then return end
  -- Rehydrate anything saved for this area (for all once_keys in its mem)
  rehydrate_all_for_area(area_id)
end

local function _oncehub_rehydrate_for_player(pid)
  async(function()
    await(Async.sleep(0.10))  -- give the map a tick to finish loading
    local aid = Net.get_player_area(pid)
    if aid then
      -- idempotent: no duplicates if objects already exist
      rehydrate_all_for_area(aid)
      -- print("[oncehub] rehydrated area: "..tostring(aid))
    end
  end)
end

local function _safe_get_player(ev)
  return (ev and (ev.player_id or ev.id or ev.pid)) or nil
end

local function _safe_get_to_area(ev, pid)
  return (ev and (ev.to_area_id or ev.area_id or ev.new_area_id)) or (pid and Net.get_player_area(pid)) or nil
end

-- Wrap ezweather.handle_player_join
do
  local _old = ezweather.handle_player_join
  ezweather.handle_player_join = function(pid)
    if _old then _old(pid) end
    _oncehub_rehydrate_for_player(pid)
  end
end

-- Wrap ezweather.handle_player_transfer
do
  local _old = ezweather.handle_player_transfer
  ezweather.handle_player_transfer = function(pid)
    if _old then _old(pid) end
    _oncehub_rehydrate_for_player(pid)
  end
end

-- ---------- Actions ----------
-- Save both the legacy XML and the structured placements into *both*
-- the live area AND (if present) the bucket area memory.
local function persist_area(area_id, bucket_area_id, once_key)
  local key = once_key or ("area:"..area_id)
  local snapshot = Net.map_to_string(area_id)
  local placements = snapshot_oncehub_placements(area_id, once_key)

  -- Write to LIVE AREA memory
  do
    local mem = ezmemory.get_area_memory(area_id)
    mem["oncehub_snapshots"] = mem["oncehub_snapshots"] or {}
    mem["oncehub_snapshots"][key] = snapshot
    mem[PLACEMENTS_MEM_KEY] = mem[PLACEMENTS_MEM_KEY] or {}
    mem[PLACEMENTS_MEM_KEY][key] = placements
    mem.oncehub_key_areas = mem.oncehub_key_areas or {}
    mem.oncehub_key_areas[key] = area_id
    ezmemory.save_area_memory(area_id)
  end

  -- Also write to BUCKET (if configured)
  if bucket_area_id and bucket_area_id ~= area_id then
    local mem = ezmemory.get_area_memory(bucket_area_id)
    mem["oncehub_snapshots"] = mem["oncehub_snapshots"] or {}
    mem["oncehub_snapshots"][key] = snapshot
    mem[PLACEMENTS_MEM_KEY] = mem[PLACEMENTS_MEM_KEY] or {}
    mem[PLACEMENTS_MEM_KEY][key] = placements
    mem.oncehub_key_areas = mem.oncehub_key_areas or {}
    mem.oncehub_key_areas[key] = area_id
    ezmemory.save_area_memory(bucket_area_id)
  end
end

local function place_current(player_id)
  local s = ONCEHUB.sessions[player_id]; if not s or not s.active then return end
  if not s.preview_id then return end
  local preview = Net.get_object_by_id(s.area_id, s.preview_id)
  if not preview then return end

  local permanent = {
    name = "",
    class = "Decor",
    visible = true,
    x = preview.x, y = preview.y, z = preview.z,
    width = preview.width, height = preview.height,
    rotation = 0,
    data = preview.data,
    custom_properties = {
      placed_by_oncehub = "true",
      oncehub_gid       = tostring(s.object_gid or ""),
      oncehub_name      = tostring(s.object_name or "Object"),
      oncehub_id        = tostring(s.object_id   or "object"),
	  oncehub_key       = tostring(s.once_key    or ""),
    }
  }
  Net.create_object(s.area_id, permanent)
  persist_area(s.area_id, s.bucket_area_id, s.once_key)
  stop_session(player_id, "Placed "..(s.object_name or "object")..".")
end

local function remove_current(player_id)
  local s = ONCEHUB.sessions[player_id]; if not s or not s.active then return end
  local dist = s.cursor_distance or 0.75
  local cx, cy, cz = get_cursor_point(player_id, dist)
  local obj, oid = find_oncehub_object_at(s.area_id, cx, cy, cz)
  if not obj then
    Async.message_player(player_id, "No editable object in front.")
    return
  end

  local name = (obj.custom_properties and obj.custom_properties.oncehub_name)
  if not name then
    local e = catalog_entry_by_gid(s.area_id, obj.data and obj.data.gid)
    name = (e and e.name) or "object"
  end

  Net.remove_object(s.area_id, oid)
  persist_area(s.area_id, s.bucket_area_id, s.once_key)
  stop_session(player_id, "Removed "..name..".")
end

-- ---------- Start sessions ----------
local function get_template_layer_name(dialogue)
  local v = (dialogue and dialogue.custom_properties and dialogue.custom_properties["Template Layer"]) or ""
  v = tostring(v or ""):gsub("^%s+",""):gsub("%s+$","")
  return (v ~= "" and v) or "Object Layer 2"
end

local function start_place_session(player_id, dialogue, chosen_gid, chosen_name, chosen_id, template_layer)
  local area_id = Net.get_player_area(player_id)
  local object_gid = tonumber(chosen_gid)
  if not object_gid then
    object_gid = try_resolve_test_gid(dialogue, area_id)
  end
  if object_gid then object_gid = gid_base(object_gid) end
  if not object_gid then
    Async.message_player(player_id, "Couldn't resolve a placeable object (gid).")
    return
  end

  -- Authorize renter
  local once_key = normalize_key(dprop(dialogue, "Once Key", ""))
  local BUCKET_AREA_ID = resolve_mem_area_id(dialogue, player_id, nil)
  local mem = ezmemory.get_area_memory(BUCKET_AREA_ID); mem.onceitems = mem.onceitems or {}
  local rec = mem.onceitems[once_key]; local now = os.time()
  if (not rec) or (not rec.expires_at) or (rec.expires_at <= now) or (helpers.get_safe_player_secret(player_id) ~= rec.owner_secret) then
    Async.message_player(player_id, "Only the current renter can decorate this HP.")
    return
  end
  local left, owned = decor_left_to_place(player_id, area_id, once_key, (chosen_id or ""))
  if owned > 0 and left <= 0 then
    Async.message_player(player_id, ("You’ve used all of your %s (owned %d)."):format(chosen_name or "object", owned))
    return
  end

  ONCEHUB.sessions[player_id] = {
    area_id = area_id,
    bucket_area_id = BUCKET_AREA_ID,
    once_key = once_key,
    object_gid = object_gid,
    object_name = chosen_name or "Object",
    object_id   = chosen_id   or "object",
    template_layer_name = template_layer or get_template_layer_name(dialogue),
    cursor_distance = tonumber(dprop(dialogue, "Cursor Distance Tiles", "0.75")) or 0.75,
    mode = 'place',
    active = true,
  }
  async(function()
    await(Async.message_player(player_id, "Place Mode: Press A to place. Leave the area to cancel."))
  end)
  return true
end

local function open_place_catalog_menu(player_id, dialogue)
  return async(function ()
    local area_id = Net.get_player_area(player_id)

    -- Need the once_key to calculate "left" correctly per HP
    local once_key = normalize_key(dprop(dialogue, "Once Key", ""))
    if once_key == "" then
      await(Async.message_player(player_id, "This butler needs an 'Once Key' property.")); return
    end
	ensure_rehydrated(player_id, dialogue)

    -- Build menu from catalog, but only show items the player owns; label with (left/owned)
    local posts, index = {}, {}
    for _, e in ipairs(ONCEHUB_CATALOG) do
      local gid = catalog_resolve_gid(area_id, e) or e.gid
      if gid then
        local left, owned = decor_left_to_place(player_id, area_id, once_key, e.id)
        if owned > 0 then -- hide completely if never purchased
          if left > 0 then
            local label = string.format("%s (%d/%d)", e.name, left, owned)
            table.insert(posts, helpers.create_bbs_option(label))
            index[#posts] = { gid = gid, name = e.name, id = e.id, layer = e.layer or "Object Layer 2" }
          end
        end
      end
    end

    if #posts == 0 then
      await(Async.message_player(player_id, "No available decorations to place. Buy some at a decor shop!"))
      return
    end

    local board = ezmenus.open_menu(player_id, "Choose decoration", {r=60,g=170,b=90}, posts)
    local sel = await(board.selection_once())
	menu_closed_now(player_id, 0.5)
	fast_close_board(player_id)
    if not sel then return end

    -- selection is the post.id/title; find the chosen entry
    for i, post in ipairs(posts) do
      local pid = post.id or post.title or ""
      if sel == pid then
        local chosen = index[i]
        if chosen and chosen.gid then
          start_place_session(player_id, dialogue, chosen.gid, chosen.name, chosen.id, chosen.layer)
          -- Kick the preview loop
          async(function ()
            while true do
              local s = ONCEHUB.sessions[player_id]
              if not s or not s.active then break end
              ensure_preview(player_id)
              await(Async.sleep(0.08))
            end
          end)
        else
          await(Async.message_player(player_id, "Couldn’t resolve that object’s gid."))
        end
        return
      end
    end

    print(("[oncehub] WARN: selection '%s' did not match any post.id"):format(tostring(sel)))
  end)
end

local function start_remove_session(player_id, dialogue)
  -- Authorize renter
  local once_key = normalize_key(dprop(dialogue, "Once Key", ""))
  local BUCKET_AREA_ID = resolve_mem_area_id(dialogue, player_id, nil)
  local mem = ezmemory.get_area_memory(BUCKET_AREA_ID); mem.onceitems = mem.onceitems or {}
  local rec = mem.onceitems[once_key]; local now = os.time()
  if (not rec) or (not rec.expires_at) or (rec.expires_at <= now) or (helpers.get_safe_player_secret(player_id) ~= rec.owner_secret) then
    Async.message_player(player_id, "Only the current renter can decorate this HP.")
    return
  end

  local area_id = Net.get_player_area(player_id)
  local rem_gid = resolve_removal_cursor_gid(area_id)

  ONCEHUB.sessions[player_id] = {
    area_id = area_id,
    bucket_area_id = BUCKET_AREA_ID,
    once_key = once_key,
    cursor_distance = tonumber(dprop(dialogue, "Cursor Distance Tiles", "0.75")) or 0.75,
    mode = 'remove',
    active = true,
    rem_cursor_gid = rem_gid,
    rem_cursor_id  = nil,
  }

  async(function()
    await(Async.message_player(player_id, "Remove Mode: Target turns mirrored. Press A to remove. Leave the area to cancel."))
  end)
  return true
end

-- ====================== oncehub menus ======================
local function open_decorate_menu(player_id, dialogue)
  return async(function ()
    local posts = {
      helpers.create_bbs_option("Place object"),
      helpers.create_bbs_option("Remove object"),
      helpers.create_bbs_option("Clear all")
    }
    local board = ezmenus.open_menu(player_id, "Decorate HP", MENU_COLOR.GREEN, posts)
    local sel = await(board.selection_once())
	menu_closed_now(player_id, 0.5)
	fast_close_board(player_id)
    if sel == "Place object" then
      await(open_place_catalog_menu(player_id, dialogue))
    elseif sel == "Remove object" then
      if start_remove_session(player_id, dialogue) then
        async(function ()
          while true do
            local s = ONCEHUB.sessions[player_id]
            if not s or not s.active then break end
            ensure_preview(player_id)
            await(Async.sleep(0.08))
          end
        end)
      end
    elseif sel == "Clear all" then
      local area_id   = Net.get_player_area(player_id)
      local once_key  = normalize_key(dprop(dialogue, "Once Key", ""))
      if once_key == "" then return end

      -- ✅ Renter-only gate (same logic as start_place_session/start_remove_session)
      local BUCKET_AREA_ID = resolve_mem_area_id(dialogue, player_id, nil)
      local mem = ezmemory.get_area_memory(BUCKET_AREA_ID); mem.onceitems = mem.onceitems or {}
      local rec = mem.onceitems[once_key]; local now = os.time()
      if (not rec) or (not rec.expires_at) or (rec.expires_at <= now)
         or (helpers.get_safe_player_secret(player_id) ~= rec.owner_secret) then
        await(Async.message_player(player_id, "Only the current renter can clear this HP."))
        return
      end

      -- Remove only this renter's placed objects (and any stray previews)
      for _, oid in ipairs(Net.list_objects(area_id) or {}) do
        local o  = Net.get_object_by_id(area_id, oid)
        local cp = o and o.custom_properties
        if cp and (cp.oncehub_key or "") == once_key then
          if cp.placed_by_oncehub == "true" or cp.oncehub_preview == "true" then
            Net.remove_object(area_id, oid)
          end
        end
      end
    
      -- Persist the now-empty placement list (prevents rehydrate)
      persist_area(area_id, BUCKET_AREA_ID, once_key)

      await(Async.message_player(player_id, "Cleared all objects."))
    end
  end)
end

local function open_pass_menu(player_id, npc, dialogue)
  return async(function ()
    local opts = {
      helpers.create_bbs_option("Set visitor password"),
      helpers.create_bbs_option("Clear visitor password"),
    }
    local board = ezmenus.open_menu(player_id, "Visitor Password", MENU_COLOR.BLUE, opts)
    local sel = await(board.selection_once())
	menu_closed_now(player_id, 0.5)
	fast_close_board(player_id)

    local once_key = normalize_key(dprop(dialogue, "Once Key", ""))
    if once_key == "" then await(Async.message_player(player_id, "This butler needs an 'Once Key' property.")); return end
    local BUCKET = resolve_mem_area_id(dialogue, player_id, nil)
    local mem = ezmemory.get_area_memory(BUCKET); mem.onceitems = mem.onceitems or {}
    local rec = mem.onceitems[once_key]
    local now = os.time()
    if (not rec) or (not rec.expires_at) or (rec.expires_at <= now) or (helpers.get_safe_player_secret(player_id) ~= rec.owner_secret) then
      await(Async.message_player(player_id, "Only the current renter can change the password.")); return
    end

    if sel == "Clear visitor password" then
      rec.password = nil; ezmemory.save_area_memory(BUCKET); await(Async.message_player(player_id, "Password cleared."))
    elseif sel == "Set visitor password" then
      await(Async.message_player(player_id, "Enter a password (1-24 chars):"))
      local pw = await(Async.prompt_player(player_id)) or ""
      pw = pw:gsub("^%s+",""):gsub("%s+$","")
      if #pw < 1 or #pw > 24 then
        await(Async.message_player(player_id, "Password must be 1–24 characters."))
      else
        rec.password = pw; ezmemory.save_area_memory(BUCKET); await(Async.message_player(player_id, "Password saved."))
      end
    end
  end)
end

-- Register oncehub dialogue
eznpcs.add_event({
  name = "oncehub",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function ()
	  ensure_rehydrated(player_id, dialogue)
      local posts = {
        helpers.create_bbs_option("Set/Clear visitor password"),
        helpers.create_bbs_option("Decorate HP"),
      }
      local board = ezmenus.open_menu(player_id, "Home Hub", MENU_COLOR.YELLOW, posts)
      local sel = await(board.selection_once())
	  menu_closed_now(player_id, 0.5)
	  fast_close_board(player_id)
      if sel == "Set/Clear visitor password" then
        await(open_pass_menu(player_id, npc, dialogue))
      elseif sel == "Decorate HP" then
        await(open_decorate_menu(player_id, dialogue))
      end
    end)
  end
})

-- ====================== oncehub listeners ======================
Net:on("tile_interaction", function (event)
  if event.button ~= 0 then return end -- A/Confirm
  local pid = event.player_id
  if recently_closed_menu(pid) then return end
  local s = ONCEHUB.sessions[pid]
  if not (s and s.active) then return end
  if s.mode == 'place' then
    place_current(pid)
  elseif s.mode == 'remove' then
    remove_current(pid)
  end
end)

Net:on("player_area_transfer", function(ev)
  -- end any active decorate session from the *old* area
  if ONCEHUB.sessions[ev.player_id] then
    stop_session(ev.player_id, "Decorate Mode ended.")
  end
  -- after arriving, give the area a tick to finish loading, then rehydrate
  async(function()
    await(Async.sleep(0.10)) -- ~100ms; adjust if your server ticks differ
    local aid = ev.to_area_id or ev.area_id or ev.new_area_id or Net.get_player_area(ev.player_id)
    if aid then rehydrate_all_for_area(aid) end
  end)
end)

Net:on("player_join_area", function(ev)
  async(function()
    await(Async.sleep(0.10)) -- give the area a tick to finish loading
    local pid = ev.player_id or ev.id
    local aid = ev.to_area_id or ev.area_id or ev.new_area_id or (pid and Net.get_player_area(pid))
    if aid then rehydrate_all_for_area(aid) end
  end)
end)

-- Also handle first login/spawn into the default area
Net:on("player_join", function(ev)
  async(function()
    await(Async.sleep(0.10))
    local pid = ev.player_id or ev.id
    local aid = pid and Net.get_player_area(pid)
    if aid then rehydrate_all_for_area(aid) end
  end)
end)

-- ====================== Dialogue: onceitem (rental) ======================
eznpcs.add_event({
  name = "onceitem",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function ()
      local area_id   = Net.get_player_area(player_id)
      local mug       = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
      local next_ids  = helpers.extract_numbered_properties(dialogue, "Next ")
      local item_ids  = helpers.extract_numbered_properties(dialogue, "Item ")
      local notify    = dprop(dialogue, "Dont Notify", "false") ~= "true"
      local BUCKET_AREA_ID = resolve_mem_area_id(dialogue, player_id, nil)
      print("[onceitem] bucket:", tostring(BUCKET_AREA_ID))

      local price          = tonumber(dprop(dialogue, "Price", "0")) or 0
      local renewal_price  = tonumber(dprop(dialogue, "Renewal Price", "0")) or 0
      local lease_months   = tonumber(dprop(dialogue, "Lease Months", "1")) or 1
      local lease_minutes  = tonumber(dprop(dialogue, "Lease Minutes", "0")) or 0

      local item_object_id = item_ids[1]
      if not item_object_id then
        await(say(player_id, "No item configured for this NPC.", mug))
        return next_ids[2]
      end

      local item_info = helpers.read_item_information(area_id, item_object_id)
      if not item_info then
        await(say(player_id, "Configured item couldn't be found.", mug))
        return next_ids[2]
      end

      local once_key = normalize_key(dprop(dialogue, "Once Key", item_info.name or tostring(dialogue.id)))
      purge_player_key_if_invalid(player_id, BUCKET_AREA_ID, once_key, item_info.name)

      local lock = helpers.get_lock(player_id, "onceitem:"..once_key, 10)
      if not lock then
        await(say(player_id, dprop(dialogue, "Busy Text", DEFAULTS.BusyText), mug))
        local busy_next = dprop(dialogue, "Busy Next", DEFAULTS.BusyNext)
        if busy_next then return busy_next else return nil end
      end
      local function finish(next_id) lock.release(); return next_id end

      local mem = ensure_bucket_mem(BUCKET_AREA_ID)
      local record = mem.onceitems[once_key]
      local now_ts = os.time()
      local manual_purchased_at = resolve_manual_purchased_at(dialogue, now_ts)
      local safe_secret = helpers.get_safe_player_secret(player_id)
      local player_name = Net.get_player_name(player_id)

      local function save_record(r) mem.onceitems[once_key] = r; ezmemory.save_area_memory(BUCKET_AREA_ID) end
      local function can_afford(amount) return amount <= 0 or (Net.get_player_money(player_id) >= amount and ezmemory.spend_player_money(player_id, amount)) end

      local function grant_key_if_missing()
        return async(function ()
          if item_info.type ~= "money" and item_info.name and ezmemory.count_player_item then
            if ezmemory.count_player_item(player_id, item_info.name) > 0 then
              print('[onceitem] '..Net.get_player_name(player_id)..' already has '..item_info.name)
              return
            end
          end
          print('[onceitem] granting '..tostring(item_info.name)..' to '..Net.get_player_name(player_id))
          await(ezmemory.give_item_with_optional_notify(player_id, area_id, item_object_id, item_info, notify))
        end)
      end

      local function new_window_from(ts) local s,e = compute_period(ts, lease_months, lease_minutes); return s,e end

      if record and record.expires_at and record.expires_at > now_ts then
        if record.owner_secret == safe_secret then
          local prompt = dprop(dialogue, "Renew Prompt", DEFAULTS.RenewPrompt)
          prompt = prompt:gsub("{date}", fmt(record.expires_at)):gsub("{price}", tostring(renewal_price))
          local wants = (renewal_price <= 0) or ask_yes_no(player_id, prompt, mug)
          if wants then
            if not can_afford(renewal_price) then
              await(say(player_id, dprop(dialogue, "No Money Text", DEFAULTS.NoMoneyText), mug))
              return finish(next_ids[3] or next_ids[2])
            end
            await(grant_key_if_missing())
            local base_ts = manual_purchased_at or now_ts
            local start_ts, end_ts = new_window_from(base_ts)
            record.owned_at = start_ts; record.expires_at = end_ts; record.owner_name = player_name
            save_record(record)
            await(say(player_id, dprop(dialogue, "Renewed Text", DEFAULTS.RenewedText):gsub("{date}", fmt(end_ts)), mug))
            return finish(next_ids[1])
          else
            -- Renter declined renewal: offer to clear HP as a safeguard
            local clear_prompt = dprop(dialogue, "Clear HP Prompt", "Would you like to clear your HP?")
            local do_clear = await(Async.question_player(player_id, clear_prompt, mug.texture_path, mug.animation_path))

            if do_clear == 1 then
              -- Prefer explicit HP Area; fall back to player's current area if not set
              local hp_area_id = tostring(dprop(dialogue, "HP Area", ""))
              if hp_area_id == "" then hp_area_id = Net.get_player_area(player_id) end

              local removed = 0
              for _, oid in ipairs(Net.list_objects(hp_area_id) or {}) do
                local o  = Net.get_object_by_id(hp_area_id, oid)
                local cp = o and o.custom_properties
                if cp and cp.placed_by_oncehub == "true"
                   and normalize_key(cp.oncehub_key) == normalize_key(once_key) then
                  pcall(Net.remove_object, hp_area_id, oid)
                  removed = removed + 1
                end
              end

              -- Persist the cleared state so nothing rehydrates later
              persist_area(hp_area_id, BUCKET_AREA_ID, once_key)

              await(Async.message_player(
                player_id,
                (removed > 0) and ("HP cleared ("..removed.." objects removed).") or "HP was already clear.",
                mug.texture_path, mug.animation_path
              ))
            end

            return finish(next_ids[2])
          end
        else
          local msg = dprop(dialogue, "Owned Text", DEFAULTS.OwnedText)
          msg = msg:gsub("{owner}", record.owner_name or "someone")
                   :gsub("{item}",  item_info.name or "item")
                   :gsub("{date}",  fmt(record.expires_at))
          await(say(player_id, msg, mug))
          return finish(next_ids[2])
        end
      end

      local base_ts = manual_purchased_at or now_ts
      local _, preview_end = new_window_from(base_ts)

      local skip_confirm = dprop(dialogue, "Skip Rent Confirm", DEFAULTS.SkipRentConfirm) == "true"
      if not skip_confirm then
        local prompt = dprop(dialogue, "Rent Prompt", DEFAULTS.RentPrompt)
        prompt = prompt:gsub("{item}",  item_info.name or "item")
                       :gsub("{price}", tostring(price))
                       :gsub("{date}",  fmt(preview_end))
        local wants = ask_yes_no(player_id, prompt, mug)
        if not wants then
          await(say(player_id, dprop(dialogue, "Declined Text", DEFAULTS.DeclinedText), mug))
          local declined_next = dprop(dialogue, "Declined Next", DEFAULTS.DeclinedNext)
          if declined_next then return finish(declined_next) else return finish(nil) end
        end
      end

      if not can_afford(price) then
        await(say(player_id, dprop(dialogue, "No Money Text", DEFAULTS.NoMoneyText), mug))
        return finish(next_ids[3] or next_ids[2])
      end

      local start_ts, end_ts = new_window_from(base_ts)
      await(grant_key_if_missing())

      local new_rec = {
        owner_secret = safe_secret,
        owner_name   = player_name,
        item_id      = item_object_id,
        item_name    = item_info.name,
        price_paid   = price,
        owned_at     = start_ts,
        expires_at   = end_ts,
        password     = nil
      }
      save_record(new_rec)

      local sold_text = dprop(dialogue, "Sold Text", DEFAULTS.SoldText)
      sold_text = sold_text:gsub("{owner}", player_name)
                           :gsub("{item}",  item_info.name or "item")
                           :gsub("{date}",  fmt(end_ts))
      await(say(player_id, sold_text, mug))

      return finish(next_ids[1])
    end)
  end
})

-- ====================== Dialogue: oncepass (butler password) ======================
eznpcs.add_event({
  name = "oncepass",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function ()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
      local once_key = normalize_key(dprop(dialogue, "Once Key", ""))
      local BUCKET_AREA_ID = resolve_mem_area_id(dialogue, player_id, nil)
      if once_key == "" then await(say(player_id, "No Once Key on this node.", mug)); return nil end

      local mem, rec = get_record_and_prune(BUCKET_AREA_ID, once_key)
      local now = os.time()
      if not rec or not rec.expires_at or rec.expires_at <= now then
        await(say(player_id, dprop(dialogue, "Not Renter Text", DEFAULTS.NotRenterText).." (No active lease.)", mug))
        return nil
      end

      local player_secret = helpers.get_safe_player_secret(player_id)
      local is_owner = (player_secret == rec.owner_secret)

      local dbg = string.format("[oncepass] key=%s you=%s owner=%s expires=%s owner?%s",
        once_key, tostring(player_secret), tostring(rec.owner_secret), tostring(rec.expires_at), tostring(is_owner))
      if printd then printd(dbg) else print(dbg) end

      if not is_owner then
        await(say(player_id, dprop(dialogue, "Not Renter Text", DEFAULTS.NotRenterText).." (Not the owner.)", mug))
        return nil
      end

      local action = string.lower(dprop(dialogue, "Pass Action", DEFAULTS.PassAction))
      if action == "clear" then
        rec.password = nil
        ezmemory.save_area_memory(BUCKET_AREA_ID)
        await(say(player_id, dprop(dialogue, "Pass Cleared Text", DEFAULTS.PassClearedText), mug))
        return nil
      else
        local prompt = dprop(dialogue, "Pass Prompt", DEFAULTS.PassPrompt)
        local pw = ask_text(player_id, prompt, mug)
        pw = tostring(pw or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if #pw < 1 or #pw > 24 then
          await(say(player_id, "Password must be 1–24 characters.", mug))
          return nil
        end
        rec.password = pw
        ezmemory.save_area_memory(BUCKET_AREA_ID)
        await(say(player_id, dprop(dialogue, "Pass Saved Text", DEFAULTS.PassSavedText), mug))
        return nil
      end
    end)
  end
})

-- ====================== Dialogue: decorshop (sells ONLY ONCEHUB_CATALOG items) ======================
-- Configuration per NPC (custom properties, case-insensitive):
--   Optional subset to sell:  Sell 1 = bus_stop, Sell 2 = megaman_doll, ...
--   Unit prices:             Price bus_stop = 500, Price megaman_doll = 1500, ...
-- Fallback: if no Price is set, uses entry.price or DECOR_DEFAULT_PRICE.

eznpcs.add_event{
  name = "decorshop",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function ()
      local area_id = Net.get_player_area(player_id)
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
      local ci  = _decor_ci(dialogue)

      -- Build the for-sale rows by index so "Price N" matches "Sell N"
      -- Each row is { idx = N, id = "catalog_id" }
      local sell_rows = {}
      do
        local n = 1
        while true do
          local spec = _decor_get_prop_ci(ci, "Sell "..n)
          if not spec then break end
          -- allow one-per-line OR comma/space separated ids
          for id in tostring(spec):gmatch("[^,%s]+") do
            -- only allow IDs that exist in ONCEHUB_CATALOG
            if _catalog_by_id(id) then
              table.insert(sell_rows, { idx = n, id = id })
            end
          end
          n = n + 1
        end

        -- If no explicit Sell N, default to full catalog with stable indexing
        if #sell_rows == 0 then
          for i, e in ipairs(ONCEHUB_CATALOG) do
            table.insert(sell_rows, { idx = i, id = e.id })
          end
        end
      end

      -- Build menu posts with index-matched prices
      local posts, items = {}, {}
      for _, row in ipairs(sell_rows) do
        local entry = _catalog_by_id(row.id)
        if entry then
          local unit  = price_for_index_or_id(dialogue, row.idx, row.id) -- matches Price N, falls back to Price <id> / entry.price / default
          local label = string.format("%s (%s)", entry.name, short_money(unit))
          table.insert(posts, helpers.create_bbs_option(label))
          items[#posts] = { id = row.id, name = entry.name, unit = unit }
        end
      end

      if #posts == 0 then
        await(Async.message_player(
          player_id,
          "Sorry, I’m not selling any decorations right now.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      -- Loop shop until Cancel/close
      while true do
        local board = ezmenus.open_menu(player_id, "Decor Shop", MENU_COLOR.YELLOW, posts)
        local sel = await(board.selection_once())
		menu_closed_now(player_id, 0.5)
		fast_close_board(player_id)
        if not sel then break end

        -- Find chosen item
        local chosen
        for i, post in ipairs(posts) do
          local pid = post.id or post.title or ""
          if sel == pid then chosen = items[i]; break end
        end
        if not chosen then break end

        -- Quantity chooser (1 / 3 / Cancel)
        local opt1 = string.format("Buy 1  (%s)", short_money(chosen.unit * 1))
        local opt2 = string.format("Buy 3  (%s)", short_money(chosen.unit * 3))
        local opt3 = "Cancel"

        local res = await(Async.quiz_player(
          player_id, opt1, opt2, opt3, mug.texture_path, mug.animation_path
        ))

        -- res: 0 = Buy 1, 1 = Buy 3, 2 = Cancel, nil = closed with B
        local qty = (res == 0 and 1) or (res == 1 and 3) or nil
        if not qty then
          -- user chose Cancel or closed the quiz; do nothing and return to the shop list
          goto continue
        end

        local cost = chosen.unit * qty
        if not ezmemory.spend_player_money(player_id, cost) then
          await(Async.message_player(player_id, "You don't have enough money.", mug.texture_path, mug.animation_path))
		  menu_closed_now(player_id, 0.5)
          goto continue
        end

        decor_add_owned(player_id, chosen.id, qty)  -- persistent add (ONCEHUB_CATALOG-only)
        if sfx and sfx.item_get then Net.play_sound_for_player(player_id, sfx.item_get) end
        await(Async.message_player(
          player_id,
          ("Purchased x%d %s."):format(qty, chosen.name),
          mug.texture_path, mug.animation_path
        ))
		menu_closed_now(player_id, 0.5)

        ::continue::
        -- loop again
      end

      return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
    end)
  end
}

-- ====================== Checkpoint Integration ======================
Net:on("object_interaction", function(event)
  if event.button ~= 0 then return end -- only A/Confirm
  local player_id = event.player_id
  if recently_closed_menu(player_id) then return end
  local area_id   = Net.get_player_area(player_id)
  local object_id = event.object_id
  local obj = Net.get_object_by_id(area_id, object_id)
  if not obj or obj.type ~= "Checkpoint" then return end

  local cp = obj.custom_properties or {}
  local once_key = normalize_key(cp["Once Key"])
  if once_key == "" then return end
  local BUCKET_AREA_ID = resolve_mem_area_id(nil, player_id, cp)

  local lock_id = player_id.."_"..area_id.."_"..obj.id
  local lock = helpers.get_lock(player_id, lock_id)

  local function run_logic(with_lock)
    return async(function ()
      purge_player_key_if_invalid(player_id, BUCKET_AREA_ID, once_key, cp["Key Name"])

      if with_lock then
        local description = cprop(cp, "Description", DEFAULTS.CP_Description)
        if #description > 0 then await(Async.message_player(player_id, description)) end
      end

      local mem, rec = get_record_and_prune(BUCKET_AREA_ID, once_key)
      local now = os.time()
      if not rec or not rec.expires_at or rec.expires_at <= now then
        if with_lock then
          await(Async.message_player(player_id, cprop(cp, "Lease Inactive Message", DEFAULTS.CP_LeaseInactiveMessage)))
        end
        if with_lock and lock then lock.release() end
        return
      end

      local is_owner = helpers.get_safe_player_secret(player_id) == rec.owner_secret
      local unlocked = false

      if is_owner then
        unlocked = true
      else
        local pw = rec.password
        if pw and #pw > 0 then
          if with_lock then
            await(Async.message_player(player_id, cprop(cp, "Visitor Password Prompt", DEFAULTS.CP_VisitorPasswordPrompt)))
            local input = await(Async.prompt_player(player_id))
            if tostring(input or "") == pw then
              unlocked = true
            else
              await(Async.message_player(player_id, cprop(cp, "Wrong Password Message", DEFAULTS.CP_WrongPasswordMessage)))
            end
          end
        else
          if with_lock then
            await(Async.message_player(player_id, cprop(cp, "Wrong Password Message", DEFAULTS.CP_WrongPasswordMessage)))
          end
        end
      end

      if unlocked then
        local sound_path = cprop(cp, "Unlocking Sound Path", DEFAULTS.CP_UnlockingSoundPath)

        if sound_path and #sound_path > 0 then
          Net.play_sound_for_player(player_id, sound_path)
        end

        ezmemory.hide_object_from_player_till_disconnect(player_id, area_id, object_id)
        Net.unlock_player_input(player_id)

        local ok_msg = is_owner
          and cprop(cp, "Owner Unlocked Message", DEFAULTS.CP_OwnerUnlockedMessage)
          or  cprop(cp, "Unlocked Message",      "The Security Cube was unlocked!")
        if with_lock and #ok_msg > 0 then await(Async.message_player(player_id, ok_msg)) end
      end

      if with_lock and lock then lock.release() end
    end)
  end

  if lock then
    return run_logic(true)
  else
    return async(function ()
      await(Async.sleep(0.05))
      await(run_logic(false))
    end)
  end
end)

return true
