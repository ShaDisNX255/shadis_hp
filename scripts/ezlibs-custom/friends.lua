-- /server/scripts/ezlibs-custom/friends.lua
-- Friends menu placeholder:
--  - Opens a BBS titled "Friends Online - Placeholder"
--  - Section 1: "Players Online" + one row per online player
--  - Section 2: "Friends Online" + "Not yet Implemented"

local Friends = {}

-- Optional: simple logging, if helpers is available
local helpers_ok, helpers = pcall(require, "scripts/ezlibs-scripts/helpers")
local ezmemory_ok, ezmemory = pcall(require, "scripts/ezlibs-scripts/ezmemory")
if not ezmemory_ok then
  ezmemory = nil
end

local MenuAPIOK, MenuAPI = pcall(require, "scripts/menuAPI/main")
if not MenuAPIOK then
  MenuAPI = nil
end

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

local DEBUG_PROFILE_CARD_USE_ONLINE_PLAYERS = false
-- Set this to false once real mutual-friend storage is wired.

local DEFAULT_MUG_ANIM = "/server/assets/tourney/tourney-board-elements/mug.anim"
local FALLBACK_MUG_TEXTURE = "/server/assets/tourney/npc-navis-testing/mug.png"
local LAST_RESORT_MUG_TEXTURE = "/server/assets/tourney/npc-navis-testing/gutsman/mug.png"

local function _safe_secret(pid)
  if helpers_ok and helpers and type(helpers.get_safe_player_secret) == "function" then
    local ok, secret = pcall(helpers.get_safe_player_secret, pid)
    if ok and secret and secret ~= "" then
      return tostring(secret)
    end
  end

  if Net and Net.get_player_secret then
    local ok, secret = pcall(Net.get_player_secret, pid)
    if ok and secret and secret ~= "" then
      return tostring(secret)
    end
  end

  return nil
end

local function _player_name(pid)
  if Net and Net.get_player_name then
    local ok, name = pcall(Net.get_player_name, pid)
    if ok and name and name ~= "" then
      return tostring(name)
    end
  end

  return "Player"
end

local function _short(text, max_ch)
  text = tostring(text or "")
  max_ch = tonumber(max_ch) or 12

  if #text <= max_ch then return text end
  if max_ch <= 3 then return text:sub(1, max_ch) end

  return text:sub(1, max_ch - 3) .. "..."
end

local function _has_asset(path)
  if not path or path == "" then return false end
  if not Net or not Net.has_asset then return true end

  local ok, exists = pcall(Net.has_asset, path)
  return ok and exists == true
end

local function _first_existing_asset(...)
  for i = 1, select("#", ...) do
    local path = select(i, ...)
    if _has_asset(path) then
      return path
    end
  end

  return nil
end

local function _mug_for_pid(pid)
  if pid and Net and Net.is_player and Net.is_player(pid) and Net.get_player_mugshot then
    local ok, mug = pcall(Net.get_player_mugshot, pid)
    if ok and mug and _has_asset(mug.texture_path) then
      return mug.texture_path, DEFAULT_MUG_ANIM, "UI"
    end
  end

  return _first_existing_asset(FALLBACK_MUG_TEXTURE, LAST_RESORT_MUG_TEXTURE), DEFAULT_MUG_ANIM, "UI"
end

local _get_online_player_ids

local function _online_pid_for_secret(secret)
  if not secret then return nil end

  for _, pid in ipairs(_get_online_player_ids()) do
    if _safe_secret(pid) == secret then
      return pid
    end
  end

  return nil
end

local function _area_label_for_pid(pid)
  if pid and Net and Net.is_player and Net.is_player(pid) and Net.get_player_area then
    local ok, area_id = pcall(Net.get_player_area, pid)

    if ok and area_id and area_id ~= "" then
      if Net.get_area_name then
        local ok_name, area_name = pcall(Net.get_area_name, area_id)
        if ok_name and area_name and area_name ~= "" then
          return tostring(area_name)
        end
      end

      return tostring(area_id)
    end
  end

  return "Offline"
end

local function _rented_hp_label_for_secret(secret)
  if not (secret and ezmemory and ezmemory.get_area_memory and Net and Net.list_areas) then
    return "HP: None"
  end

  local now = os.time()

  local function check_area(area_id)
    local mem = ezmemory.get_area_memory(area_id)
    local onceitems = mem and mem.onceitems

    if type(onceitems) ~= "table" then
      return nil
    end

    for once_key, rec in pairs(onceitems) do
      if type(rec) == "table"
        and rec.owner_secret == secret
        and tonumber(rec.expires_at or 0) > now
      then
        local raw = tostring(rec.item_name or rec.item_id or once_key or "")
        local n = raw:match("[Hh][Pp]0*(%d+)")

        if n then
          return "HP: " .. tostring(tonumber(n) or n)
        end

        if raw ~= "" then
          return "HP: " .. raw
        end

        return "HP: ?"
      end
    end

    return nil
  end

  local found = check_area("WCity1")
  if found then return found end

  for _, area_id in ipairs(Net.list_areas() or {}) do
    found = check_area(area_id)
    if found then return found end
  end

  return "HP: None"
end

-- Collect online player IDs (global), preferring RAIDS_ONLINE if present
_get_online_player_ids = function()
  local ids = {}

  local ONLINE = rawget(_G, "RAIDS_ONLINE")
  if type(ONLINE) == "table" then
    for pid, is_on in pairs(ONLINE) do
      if is_on ~= false then
        ids[#ids+1] = pid
      end
    end
  end

  -- Fallback: Net APIs, in case RAIDS_ONLINE is not available
  if #ids == 0 and Net and Net.get_player_ids then
    local ok, v = pcall(Net.get_player_ids)
    if ok and type(v) == "table" then
      for key, value in pairs(v) do
        local found_pid = value

        if type(value) == "boolean" then
          found_pid = key
        end

        if found_pid ~= nil then
          ids[#ids + 1] = found_pid
        end
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

local FRIENDS_MEM_KEY = "friends_v1"
local OPEN_FRIEND_MENUS = {}
local LAST_FRIEND_ROW_ID_BY_PID = {}

local function _friend_mem_by_secret(secret)
  if not (secret and ezmemory and ezmemory.get_player_memory) then
    return nil, nil
  end

  local mem = ezmemory.get_player_memory(secret) or {}
  mem[FRIENDS_MEM_KEY] = mem[FRIENDS_MEM_KEY] or {}

  local slot = mem[FRIENDS_MEM_KEY]
  slot.friends = slot.friends or {}
  slot.incoming = slot.incoming or {}
  slot.outgoing = slot.outgoing or {}

  return mem, slot
end

local function _friend_mem(pid)
  return _friend_mem_by_secret(_safe_secret(pid))
end

local function _save_friend_mem(secret, mem)
  if not (secret and mem and ezmemory) then
    return
  end

  if ezmemory.set_player_memory then
    pcall(ezmemory.set_player_memory, secret, mem)
  end

  if ezmemory.save_player_memory then
    pcall(ezmemory.save_player_memory, secret)
  end
end

local function _player_info(pid)
  local secret = _safe_secret(pid)
  if not secret then return nil end

  return {
    pid = pid,
    secret = secret,
    name = _player_name(pid),
  }
end

function Friends.secret_for_player(pid)
  return _safe_secret(pid)
end

local function _friend_record_name(rec, fallback)
  if type(rec) == "table" and rec.name and rec.name ~= "" then
    return tostring(rec.name)
  end

  return tostring(fallback or "Friend")
end

function Friends.relationship_status(pid, target_pid)
  if not (pid and target_pid) then
    return "none"
  end

  local mine = _player_info(pid)
  local other = _player_info(target_pid)

  if not (mine and other) then
    return "none"
  end

  if mine.secret == other.secret then
    return "self"
  end

  local _, slot = _friend_mem_by_secret(mine.secret)
  if not slot then
    return "none"
  end

  if slot.friends[other.secret] then
    return "friends"
  end

  if slot.incoming[other.secret] then
    return "incoming"
  end

  if slot.outgoing[other.secret] then
    return "outgoing"
  end

  return "none"
end

function Friends.send_request(sender_pid, target_pid)
  local sender = _player_info(sender_pid)
  local target = _player_info(target_pid)

  if not (sender and target) then
    return false, "missing_player"
  end

  if sender.secret == target.secret then
    return false, "self"
  end

  local status = Friends.relationship_status(sender_pid, target_pid)

  if status == "friends" then
    return false, "already_friends"
  end

  if status == "outgoing" then
    return false, "already_sent"
  end

  if status == "incoming" then
    return Friends.accept_request(sender_pid, target_pid)
  end

  local sender_mem, sender_slot = _friend_mem_by_secret(sender.secret)
  local target_mem, target_slot = _friend_mem_by_secret(target.secret)

  if not (sender_mem and sender_slot and target_mem and target_slot) then
    return false, "memory_unavailable"
  end

  local now = os.time()

  sender_slot.outgoing[target.secret] = {
    name = target.name,
    sent_at = now,
  }

  target_slot.incoming[sender.secret] = {
    name = sender.name,
    sent_at = now,
  }

  _save_friend_mem(sender.secret, sender_mem)
  _save_friend_mem(target.secret, target_mem)

  Friends.refresh_all_open_friend_menus()

  return true
end

function Friends.accept_request(receiver_pid, sender_pid)
  local receiver = _player_info(receiver_pid)
  local sender = _player_info(sender_pid)

  if not (receiver and sender) then
    return false, "missing_player"
  end

  if receiver.secret == sender.secret then
    return false, "self"
  end

  local receiver_mem, receiver_slot = _friend_mem_by_secret(receiver.secret)
  local sender_mem, sender_slot = _friend_mem_by_secret(sender.secret)

  if not (receiver_mem and receiver_slot and sender_mem and sender_slot) then
    return false, "memory_unavailable"
  end

  local now = os.time()

  receiver_slot.friends[sender.secret] = {
    name = sender.name,
    added_at = now,
  }

  sender_slot.friends[receiver.secret] = {
    name = receiver.name,
    added_at = now,
  }

  receiver_slot.incoming[sender.secret] = nil
  receiver_slot.outgoing[sender.secret] = nil

  sender_slot.incoming[receiver.secret] = nil
  sender_slot.outgoing[receiver.secret] = nil

  _save_friend_mem(receiver.secret, receiver_mem)
  _save_friend_mem(sender.secret, sender_mem)

  Friends.refresh_all_open_friend_menus()

  return true
end

function Friends.reject_request(receiver_pid, sender_pid)
  local receiver = _player_info(receiver_pid)
  local sender = _player_info(sender_pid)

  if not (receiver and sender) then
    return false, "missing_player"
  end

  local receiver_mem, receiver_slot = _friend_mem_by_secret(receiver.secret)
  local sender_mem, sender_slot = _friend_mem_by_secret(sender.secret)

  if receiver_mem and receiver_slot then
    receiver_slot.incoming[sender.secret] = nil
    receiver_slot.outgoing[sender.secret] = nil
    _save_friend_mem(receiver.secret, receiver_mem)
  end

  if sender_mem and sender_slot then
    sender_slot.incoming[receiver.secret] = nil
    sender_slot.outgoing[receiver.secret] = nil
    _save_friend_mem(sender.secret, sender_mem)
  end

  Friends.refresh_all_open_friend_menus()

  return true
end

function Friends.accept_request_by_secret(receiver_pid, sender_secret, sender_name_hint, opts)
  opts = opts or {}

  local receiver = _player_info(receiver_pid)
  sender_secret = sender_secret and tostring(sender_secret) or nil

  if not (receiver and sender_secret and sender_secret ~= "") then
    return false, "missing_player"
  end

  if receiver.secret == sender_secret then
    return false, "self"
  end

  local receiver_mem, receiver_slot = _friend_mem_by_secret(receiver.secret)
  local sender_mem, sender_slot = _friend_mem_by_secret(sender_secret)

  if not (receiver_mem and receiver_slot and sender_mem and sender_slot) then
    return false, "memory_unavailable"
  end

  local incoming_rec = receiver_slot.incoming[sender_secret]
  local outgoing_rec = sender_slot.outgoing[receiver.secret]

  -- Be forgiving: if one side exists, let the accept repair the relationship.
  if not incoming_rec and not outgoing_rec then
    return false, "request_missing"
  end

  local sender_pid = _online_pid_for_secret(sender_secret)
  local sender_name = sender_pid and _player_name(sender_pid)
    or _friend_record_name(incoming_rec, sender_name_hint or "Friend")

  local now = os.time()

  receiver_slot.friends[sender_secret] = {
    name = sender_name,
    added_at = now,
  }

  sender_slot.friends[receiver.secret] = {
    name = receiver.name,
    added_at = now,
  }

  receiver_slot.incoming[sender_secret] = nil
  receiver_slot.outgoing[sender_secret] = nil

  sender_slot.incoming[receiver.secret] = nil
  sender_slot.outgoing[receiver.secret] = nil

  _save_friend_mem(receiver.secret, receiver_mem)
  _save_friend_mem(sender_secret, sender_mem)

  if opts.skip_refresh ~= true then
    Friends.refresh_all_open_friend_menus()
  end

  return true
end

function Friends.reject_request_by_secret(receiver_pid, sender_secret, opts)
  opts = opts or {}

  local receiver = _player_info(receiver_pid)
  sender_secret = sender_secret and tostring(sender_secret) or nil

  if not (receiver and sender_secret and sender_secret ~= "") then
    return false, "missing_player"
  end

  if receiver.secret == sender_secret then
    return false, "self"
  end

  local receiver_mem, receiver_slot = _friend_mem_by_secret(receiver.secret)
  local sender_mem, sender_slot = _friend_mem_by_secret(sender_secret)

  local changed = false

  if receiver_mem and receiver_slot then
    if receiver_slot.incoming[sender_secret] ~= nil then changed = true end
    if receiver_slot.outgoing[sender_secret] ~= nil then changed = true end

    receiver_slot.incoming[sender_secret] = nil
    receiver_slot.outgoing[sender_secret] = nil

    _save_friend_mem(receiver.secret, receiver_mem)
  end

  if sender_mem and sender_slot then
    if sender_slot.incoming[receiver.secret] ~= nil then changed = true end
    if sender_slot.outgoing[receiver.secret] ~= nil then changed = true end

    sender_slot.incoming[receiver.secret] = nil
    sender_slot.outgoing[receiver.secret] = nil

    _save_friend_mem(sender_secret, sender_mem)
  end

  if opts.skip_refresh ~= true then
    Friends.refresh_all_open_friend_menus()
  end

  return true, changed
end

function Friends.remove_friend(pid, target_secret, opts)
  opts = opts or {}

  local mine = _player_info(pid)
  target_secret = target_secret and tostring(target_secret) or nil

  if not (mine and target_secret and target_secret ~= "") then
    return false, "missing_player"
  end

  if mine.secret == target_secret then
    return false, "self"
  end

  local my_mem, my_slot = _friend_mem_by_secret(mine.secret)

  if not (my_mem and my_slot) then
    return false, "memory_unavailable"
  end

  local old_rec = my_slot.friends[target_secret]
  if not old_rec then
    return false, "not_friends"
  end

  -- Remove from my side.
  my_slot.friends[target_secret] = nil
  my_slot.incoming[target_secret] = nil
  my_slot.outgoing[target_secret] = nil
  _save_friend_mem(mine.secret, my_mem)

  -- Remove from their side too, so the friendship is truly mutual-deleted.
  local other_mem, other_slot = _friend_mem_by_secret(target_secret)
  if other_mem and other_slot then
    other_slot.friends[mine.secret] = nil
    other_slot.incoming[mine.secret] = nil
    other_slot.outgoing[mine.secret] = nil
    _save_friend_mem(target_secret, other_mem)
  end

  if opts.skip_refresh ~= true then
    Friends.refresh_all_open_friend_menus()
  end

  return true, old_rec
end

function Friends.build_profile(viewer_pid, target)
  target = target or {}

  local target_pid = target.pid
  local target_secret = target.secret
  local target_name = target.name

  if target_pid and Net and Net.is_player and Net.is_player(target_pid) then
    target_secret = target_secret or _safe_secret(target_pid)
    target_name = target_name or _player_name(target_pid)
  elseif target_secret then
    target_pid = _online_pid_for_secret(target_secret)
  end

  target_name = target_name or (target_pid and _player_name(target_pid)) or "Player"
  target_secret = target_secret or (target_pid and _safe_secret(target_pid))

  local mug_texture, mug_anim, mug_state = _mug_for_pid(target_pid)
  local hp_label = _rented_hp_label_for_secret(target_secret)
  local area_label = target_pid and _area_label_for_pid(target_pid) or "Offline"

  return {
    title = _short(target_name, 10),

    mug_texture = mug_texture,
    mug_anim = mug_anim,
    mug_state = mug_state,
    mug_scale = 1.59,

    title_font = "THICK",
    title_scale = 1.05,

    font = "THICK",
    text_scale = 1.4,
    text_y = nil,

    lines = {
      hp_label,
      area_label,
    },
  }
end

function Friends.build_friend_rows(pid)
  local rows = {}
  local _, slot = _friend_mem(pid)

  if slot and type(slot.friends) == "table" then
    for other_secret, rec in pairs(slot.friends) do
      local other_pid = _online_pid_for_secret(other_secret)
      local online = other_pid ~= nil
      local name = online and _player_name(other_pid) or _friend_record_name(rec, "Friend")

      rows[#rows + 1] = {
        id = "__friend:" .. tostring(other_secret),
        text = _short(name, 16),
        right = online and "Online" or "Off",
        friend_secret = other_secret,
        friend_pid = other_pid,
        friend_name = name,
      }
    end
  end

  table.sort(rows, function(a, b)
    local ao = tostring(a.right or "") == "Online"
    local bo = tostring(b.right or "") == "Online"

    if ao ~= bo then
      return ao
    end

    return tostring(a.text or ""):lower() < tostring(b.text or ""):lower()
  end)

  if #rows == 0 then
    rows[#rows + 1] = {
      id = "__friends:none",
      text = "No friends yet.",
      selectable = false,
      enabled = false,
      show_right = false,
      disabled_prefix = false,
    }
  end

  return rows
end

local function _row_index_for_id(rows, row_id)
  if not row_id then return nil end

  for i, row in ipairs(rows or {}) do
    if row and row.id == row_id then
      return i, row
    end
  end

  return nil
end

local function _row_index_for_secret(rows, secret)
  if not secret then return nil end
  return _row_index_for_id(rows, "__friend:" .. tostring(secret))
end

local function _selected_from_friend_row(row)
  if type(row) ~= "table" or not row.friend_secret then
    return nil
  end

  return {
    pid = row.friend_pid,
    secret = row.friend_secret,
    name = row.friend_name or row.text,
  }
end

local function _self_selection(pid)
  return {
    pid = pid,
    secret = _safe_secret(pid),
    name = _player_name(pid),
  }
end

local function _first_friend_selection(rows)
  for _, row in ipairs(rows or {}) do
    local selected = _selected_from_friend_row(row)
    if selected then
      return selected
    end
  end

  return nil
end

local function _refresh_after_friend_removed(pid)
  local rows = Friends.build_friend_rows(pid)
  local selected = _first_friend_selection(rows) or _self_selection(pid)

  OPEN_FRIEND_MENUS[pid] = OPEN_FRIEND_MENUS[pid] or {}
  OPEN_FRIEND_MENUS[pid].selected = selected

  if selected and selected.secret and selected.secret ~= _safe_secret(pid) then
    LAST_FRIEND_ROW_ID_BY_PID[pid] = "__friend:" .. tostring(selected.secret)
  else
    LAST_FRIEND_ROW_ID_BY_PID[pid] = nil
  end

  Friends.refresh_open_friend_menu(pid)
end

function Friends.open_remove_friend_confirm(pid, friend)
  if not (MenuAPI and type(MenuAPI.push) == "function") then
    return false
  end

  friend = friend or {}
  local friend_name = _short(friend.name or "Friend", 12)

  return MenuAPI.push(pid, {
    type = 4,
    title = "Remove?",
    color = "red",

    x = 49,
    y = 54,
    z = 280,

    open_sfx = false,
    cancel_sfx = "cancel",
    lock_input = false,

    lines = {
      "Remove " .. friend_name .. "?",
      "This affects both sides.",
    },

    default_choice = "no",
    yes_text = "Yes",
    no_text = "No",

    on_confirm = function(player_id, row)
      local choice = row and row.choice or "no"

      if choice ~= "yes" then
        MenuAPI.close(player_id, {
          keep_frozen = true,
          reason = "remove_friend_cancelled",
        })
        return true
      end

      local ok, err = Friends.remove_friend(player_id, friend.secret, {
        skip_refresh = true,
      })

      -- Close confirm, then close the action menu below it.
      MenuAPI.close(player_id, {
        keep_frozen = true,
        reason = "remove_friend_confirm_closed",
      })

      MenuAPI.close(player_id, {
        keep_frozen = true,
        reason = "friend_actions_closed",
      })

      if ok then
        _refresh_after_friend_removed(player_id)
        Friends.refresh_all_open_friend_menus()

        if MenuAPI.show_message then
          MenuAPI.show_message(player_id, "Removed " .. friend_name .. ".", {
            box_id = "friends_message",
            duration = 1.20,
            modal = false,
            z = 300,
          })
        end
      else
        Friends.refresh_open_friend_menu(player_id)

        if MenuAPI.show_message then
          MenuAPI.show_message(player_id, "Could not remove friend.", {
            box_id = "friends_message",
            duration = 1.20,
            modal = false,
            z = 300,
          })
        end

        warn("remove_friend failed", tostring(err))
      end

      return true
    end,
  })
end

function Friends.open_friend_actions(pid, friend)
  if not (MenuAPI and type(MenuAPI.push) == "function") then
    return false
  end

  friend = friend or {}
  local friend_name = _short(friend.name or "Friend", 10)

  return MenuAPI.push(pid, {
    type = 3,
    title = friend_name,
    color = "red",

    x = 49,
    y = 54,
    z = 260,

    open_sfx = "screen_open",
    cancel_sfx = "cancel",
    lock_input = false,

    rows = {
      {
        id = "remove",
        text = "Remove Friend",
      },
      {
        id = "cancel",
        text = "Cancel",
      },
    },

    on_confirm = function(player_id, row)
      if row and row.id == "remove" then
        Friends.open_remove_friend_confirm(player_id, friend)
        return true
      end

      MenuAPI.close(player_id, {
        keep_frozen = true,
        reason = "friend_actions_cancel",
      })

      return true
    end,
  })
end

function Friends.refresh_open_friend_menu(pid)
  local open = OPEN_FRIEND_MENUS[pid]
  if not open then return false end

  if not (MenuAPI and type(MenuAPI.get_state) == "function" and type(MenuAPI.set_rows) == "function") then
    return false
  end

  local st = MenuAPI.get_state(pid)
  if not st then
    OPEN_FRIEND_MENUS[pid] = nil
    return false
  end

  -- If a child window is stacked on top of the Friends menu, do not clear
  -- the Friends session record. The parent list is still alive underneath.
  if st.type ~= 5 then
    if MenuAPI.stack_size and MenuAPI.stack_size(pid) > 1 then
      return false
    end

    OPEN_FRIEND_MENUS[pid] = nil
    return false
  end

  local selected = open.selected or {
    pid = pid,
    secret = _safe_secret(pid),
    name = _player_name(pid),
  }

  if selected.secret then
    selected.pid = _online_pid_for_secret(selected.secret)
  end

  st.profile = Friends.build_profile(pid, selected)

  MenuAPI.set_rows(pid, Friends.build_friend_rows(pid), {
    keep_cursor = true,
  })

  return true
end

function Friends.refresh_all_open_friend_menus()
  for pid in pairs(OPEN_FRIEND_MENUS) do
    Friends.refresh_open_friend_menu(pid)
  end
end

local function _refresh_all_later()
  if Async and Async.sleep then
    Async.sleep(0.05).and_then(function()
      Friends.refresh_all_open_friend_menus()
    end)
  else
    Friends.refresh_all_open_friend_menus()
  end
end

-- Public API: open the Friends placeholder board
function Friends.open_friends_board(pid, opts)
  opts = opts or {}

  if not (MenuAPI and type(MenuAPI.open) == "function") then
    Net.message_player(pid, "(Friends menu not available.)")
    return false
  end

  local rows = Friends.build_friend_rows(pid)

  local selected = opts.selected
  local remembered_idx, remembered_row = _row_index_for_id(rows, LAST_FRIEND_ROW_ID_BY_PID[pid])

  if not selected then
    selected = _selected_from_friend_row(remembered_row)
  end

  selected = selected or {
    pid = pid,
    secret = _safe_secret(pid),
    name = _player_name(pid),
  }

  local cursor = tonumber(opts.cursor or opts.cursor_index)

  if not cursor and selected.secret then
    cursor = _row_index_for_secret(rows, selected.secret)
  end

  if not cursor then
    cursor = remembered_idx
  end

  local ok = MenuAPI.open(pid, {
    type = 5,
    z = 220,
    title = "Friends",
    color = "green",

    open_sfx = opts.open_sfx ~= nil and opts.open_sfx or false,
    cancel_sfx = opts.cancel_sfx ~= nil and opts.cancel_sfx or "cancel",

    bg_tint = { r = 145, g = 205, b = 210, color_mode = 2 },
    title_tint = { r = 20, g = 85, b = 100, color_mode = 2 },
    row_tint = { r = 45, g = 90, b = 100, color_mode = 2 },
    right_tint = { r = 20, g = 125, b = 120, color_mode = 2 },

    -- Keep parent behavior so B/LS returns to LMenu.
    parent = opts.parent or "lmenu",

    -- Keep your tint lines here.
    -- bg_tint = ...
    -- title_tint = ...
    -- row_tint = ...
    -- right_tint = ...

    -- Lock by default. Only skip locking if explicitly told false.
    lock_input = opts.lock_input == true,

    profile = Friends.build_profile(pid, selected),
    rows = rows,
    cursor = cursor,

    on_confirm = function(player_id, row)
      local selected_friend = _selected_from_friend_row(row)
      if not selected_friend then
        return true
      end

      LAST_FRIEND_ROW_ID_BY_PID[player_id] = row.id

      local open = OPEN_FRIEND_MENUS[player_id]
      if open then
        open.selected = selected_friend
      end

      local profile = Friends.build_profile(player_id, selected_friend)

      if MenuAPI and type(MenuAPI.set_profile) == "function" then
        MenuAPI.set_profile(player_id, profile)
      else
        local st = MenuAPI and type(MenuAPI.get_state) == "function" and MenuAPI.get_state(player_id) or nil
        if st then
          st.profile = profile
        end

        if MenuAPI and type(MenuAPI.refresh) == "function" then
          MenuAPI.refresh(player_id)
        end
      end

      Friends.open_friend_actions(player_id, selected_friend)
      return true
    end,

    on_close = function(player_id, st)
      local row = st and st.rows and st.cursor and st.rows[st.cursor] or nil

      if row and row.friend_secret and row.id then
        LAST_FRIEND_ROW_ID_BY_PID[player_id] = row.id
      end

      OPEN_FRIEND_MENUS[player_id] = nil
    end,
  })

  if ok then
    OPEN_FRIEND_MENUS[pid] = {
      selected = selected,
    }
  end

  return ok
end

if Net and Net.on and not rawget(_G, "__FRIENDS_MENU_LIVE_REFRESH_HOOKED__") then
  _G.__FRIENDS_MENU_LIVE_REFRESH_HOOKED__ = true

  Net:on("player_join", function()
    _refresh_all_later()
  end)

  Net:on("player_disconnect", function()
    _refresh_all_later()
  end)

  Net:on("player_area_transfer", function()
    _refresh_all_later()
  end)
end

return Friends
