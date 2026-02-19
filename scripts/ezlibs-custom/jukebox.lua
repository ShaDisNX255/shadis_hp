--[[
* ---------------------------------------------------------- *
                 Jukebox v2.1 by D3str0y3d
	 https://github.com/ninjaman255/Server_12_22_2021_Jukebox
* ---------------------------------------------------------- *
]] --

print("[jukebox] Loading the groove!")

local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local helpers  = require('scripts/ezlibs-scripts/helpers')

local JUKEBOX_TRACKS_MEM_KEY = "jukebox_tracks_v1"
local JUKEBOX_DIR_DISK       = "./assets/jukebox"
local JUKEBOX_SONG_PREFIX    = "/server/assets/jukebox/"

-- defaults
local Songs = {}
local color =
{
  r = 0,
  g = 0,
  b = 0
}
local ACTIVE_JUKEBOX = {} -- [player_id] = { area_id, bucket_area_id, once_key, songs, close_id, full_access }

--Shorthand for async
function async(p)
  local co = coroutine.create(p)
  return Async.promisify(co)
end

--Shorthand for await
function await(v) return Async.await(v) end

--purpose: splits a string based on a delimiter
local function splitter(inputstr, sep)
  if sep == nil then
    sep = '%s'
  else
    sep = sep:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
  end

  local t = {}
  for str in (inputstr .. sep):gmatch("(.-)" .. sep) do
    table.insert(t, str)
  end
  return t
end

local function parse_rgb(str)
  local parts = splitter(tostring(str or "0,0,0"), ",")
  return {
    r = tonumber(parts[1]) or 0,
    g = tonumber(parts[2]) or 0,
    b = tonumber(parts[3]) or 0,
  }
end

--purpose: checks if server is running on windows or unix and adjusts populating the song list accordingly
local function get_os()
  if package.config:sub(1, 1) == "\\" then
    return "windows"
  else
    return "unix"
  end
end

local function listFiles(dir)
  local files = {}
  local is_windows = package.config:sub(1,1) == "\\"
  local cmd = is_windows
    and ('dir /b /a-d "'..dir..'"')
    or  ('ls -1 "'..dir..'"')

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

-- grabbing initial song names from dir "server/assets/jukebox"
local songList = listFiles(JUKEBOX_DIR_DISK)

local function CreatePost(i, name, author)
  return {
    id = i,
    title = string.gsub(name, "%.ogg$", ""),
    author = author or "",
    read = true,
  }
end

-- Creates posts with file name
local function CompilePosts(inputTable, author, finalizedTable)
  for key, value in pairs(inputTable) do
    local postToAdd = CreatePost(key, value, author or "")
    table.insert(finalizedTable, postToAdd)
  end
  table.insert(finalizedTable, CreatePost(#finalizedTable + 1, "Close Jukebox", ""))
end

-- run the function
CompilePosts(songList, "", Songs)

Net:on("post_selection", function(event)
local ctx = ACTIVE_JUKEBOX[event.player_id]
if not ctx then return end

local idx = tonumber(event.post_id)
if not idx then return end

if idx == ctx.close_id then
  Net.close_bbs(event.player_id)
  ACTIVE_JUKEBOX[event.player_id] = nil
  return
end

local file = ctx.songs[idx]
if not file then return end

Net.set_song(ctx.area_id, JUKEBOX_SONG_PREFIX .. file)

-- If this is an HP jukebox, persist the selection into the lease record
if not ctx.full_access and ctx.bucket_area_id and ctx.once_key then
  local mem = ezmemory.get_area_memory(ctx.bucket_area_id) or {}
  if mem.onceitems and mem.onceitems[ctx.once_key] then
    mem.onceitems[ctx.once_key].jukebox_song = file
    ezmemory.save_area_memory(ctx.bucket_area_id)
  end
end

Net.close_bbs(event.player_id)
ACTIVE_JUKEBOX[event.player_id] = nil
end)

Net:on("object_interaction", function(event)
  -- safety: never let this script break all interactions again
  local ok, err = pcall(function()
    -- only A/Interact (some builds always pass button, some don't)
    if event.button ~= nil and event.button ~= 0 then return end

    local area_id = Net.get_player_area(event.player_id)
    local object = Net.get_object_by_id(area_id, event.object_id)
    if not object then return end

    local is_jukebox = (object.type == "Jukebox" or object.class == "Jukebox")
    local is_fullbox = (object.type == "FullBox" or object.class == "FullBox")
    if not (is_jukebox or is_fullbox) then
      return -- IMPORTANT: ignore all other objects
    end

    local songs = listFiles(JUKEBOX_DIR_DISK)
    if #songs == 0 then
      if Net.message_player then
        Net.message_player(event.player_id, "No songs found in /server/assets/jukebox.")
      end
      return
    end

    if is_fullbox then
      -- FullBox: all songs, no ownership rules, no saving
      ACTIVE_JUKEBOX[event.player_id] = {
        area_id = area_id,
        songs = songs,
        close_id = #songs + 1,
        full_access = true
      }
    else
      -- Jukebox: if placed in HP (oncehub context), enforce renter + filter by owned
      local cp = object.custom_properties or {}
      local once_key = tostring(cp.oncehub_key or "")
      local bucket   = tostring(cp.oncehub_bucket or "")

      if once_key ~= "" and bucket ~= "" then
        local mem = ezmemory.get_area_memory(bucket) or {}
        local rec = mem.onceitems and mem.onceitems[once_key]

        if not (rec and rec.owner_secret) then
          if Net.message_player then
            Net.message_player(event.player_id, "This HP doesn't have an active lease record.")
          end
          return
        end

        local my_secret = helpers.get_safe_player_secret(event.player_id)
        if my_secret ~= rec.owner_secret then
          if Net.message_player then
            Net.message_player(event.player_id, "Only the current renter can change the music.")
          end
          return
        end

        local pmem = ezmemory.get_player_memory(rec.owner_secret) or {}
        local owned = pmem[JUKEBOX_TRACKS_MEM_KEY] or {}

        local filtered = {}
        for _, f in ipairs(songs) do
          local v = owned[f]
          if v == true or (tonumber(v or 0) or 0) > 0 then
            table.insert(filtered, f)
          end
        end
        songs = filtered

        if #songs == 0 then
          if Net.message_player then
            Net.message_player(event.player_id, "No tracks owned. Buy songs at the Music Shop!")
          end
          return
        end

        ACTIVE_JUKEBOX[event.player_id] = {
          area_id = area_id,
          bucket_area_id = bucket,
          once_key = once_key,
          songs = songs,
          close_id = #songs + 1,
          full_access = false
        }
      else
        -- standalone jukebox (not tied to an HP lease)
        ACTIVE_JUKEBOX[event.player_id] = {
          area_id = area_id,
          songs = songs,
          close_id = #songs + 1,
          full_access = true
        }
      end
    end

    local posts = {}
    for i, file in ipairs(ACTIVE_JUKEBOX[event.player_id].songs) do
      table.insert(posts, CreatePost(i, file))
    end
    table.insert(posts, CreatePost(ACTIVE_JUKEBOX[event.player_id].close_id, "Close Jukebox"))

    local cp = object.custom_properties or {}
    local rgb = parse_rgb(cp.Color or "0,0,0")
    Net.open_board(event.player_id, "Songs", rgb, posts)
  end)

  if not ok then
    print("[jukebox] object_interaction error: " .. tostring(err))
  end
end)
