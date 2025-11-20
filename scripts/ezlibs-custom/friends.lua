-- /server/scripts/ezlibs-custom/friends.lua
-- Friends menu placeholder:
--  - Opens a BBS titled "Friends Online - Placeholder"
--  - Section 1: "Players Online" + one row per online player
--  - Section 2: "Friends Online" + "Not yet Implemented"

local Friends = {}

-- Optional: simple logging, if helpers is available
local helpers_ok, helpers = pcall(require, "scripts/ezlibs-scripts/helpers")

local function log(...)
  if helpers_ok and helpers and type(helpers.info) == "function" then
    helpers.info("[Friends]", ...)
  else
    local parts = { "[Friends]" }
    for i = 1, select("#", ...) do
      parts[#parts+1] = tostring(select(i, ...))
    end
    print(table.concat(parts, " "))
  end
end

local function warn(...)
  if helpers_ok and helpers and type(helpers.warn) == "function" then
    helpers.warn("[Friends][WARN]", ...)
  else
    local parts = { "[Friends][WARN]" }
    for i = 1, select("#", ...) do
      parts[#parts+1] = tostring(select(i, ...))
    end
    print(table.concat(parts, " "))
  end
end

-- Collect online player IDs (global), preferring RAIDS_ONLINE if present
local function _get_online_player_ids()
  local ids = {}

  local ONLINE = rawget(_G, "RAIDS_ONLINE")
  if type(ONLINE) == "table" then
    for pid, is_on in pairs(ONLINE) do
      if is_on then
        ids[#ids+1] = pid
      end
    end
  end

  -- Fallback: Net APIs, in case RAIDS_ONLINE is not available
  if #ids == 0 and Net and Net.get_player_ids then
    local ok, v = pcall(Net.get_player_ids)
    if ok and type(v) == "table" then
      for _, pid in ipairs(v) do
        ids[#ids+1] = pid
      end
    end
  end

  -- Dedup, just in case
  if #ids > 1 then
    local seen, out = {}, {}
    for _, pid in ipairs(ids) do
      if not seen[pid] then
        seen[pid] = true
        out[#out+1] = pid
      end
    end
    ids = out
  end

  return ids
end

-- Resolve player names for display
local function _get_online_names()
  local ids = _get_online_player_ids()
  local names = {}

  for _, pid in ipairs(ids) do
    local name = ("Player %s"):format(pid)
    if Net and Net.get_player_name then
      local ok, pname = pcall(Net.get_player_name, pid)
      if ok and pname and pname ~= "" then
        name = pname
      end
    end
    names[#names+1] = name
  end

  table.sort(names)
  return names
end

-- Public API: open the Friends placeholder board
function Friends.open_friends_board(pid)
  if not Net or not Net.open_board then
    warn("Net or Net.open_board missing; cannot open Friends board.")
    return
  end

  local title = "Friends Online - Placeholder"
  local color = { r = 160, g = 240, b = 255 }

  local posts = {}

  -- Section 1: Players Online
  posts[#posts+1] = {
    id    = "__friends:players_header",
    read  = true,
    title = "Players Online",
    author = "",
  }

  local names = _get_online_names()
  if #names == 0 then
    posts[#posts+1] = {
      id    = "__friends:none",
      read  = true,
      title = "(None)",
      author = "",
    }
  else
    for i, name in ipairs(names) do
      posts[#posts+1] = {
        id    = "__friends:player:" .. tostring(i),
        read  = true,
        title = "- " .. name,
        author = "",
      }
    end
  end

  -- Section 2: Friends Online (stubbed)
  posts[#posts+1] = {
    id    = "__friends:friends_header",
    read  = true,
    title = "Friends Online",
    author = "",
  }

  posts[#posts+1] = {
    id    = "__friends:not_impl",
    read  = true,
    title = "Not yet Implemented",
    author = "",
  }

  Net.open_board(pid, title, color, posts)
  log("Opened Friends board for", pid)
end

return Friends
