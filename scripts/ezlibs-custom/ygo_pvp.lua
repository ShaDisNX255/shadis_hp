-- scripts/ezlibs-custom/ygo_duel_tables.lua
-- Mini YGO — Duel Table lobby (2 seats, board-driven)
-- Players interact with an object of class/type "Duel Table".
-- When both seated players are Ready, we call:
--   custom.start_card_battle_pvp(pidA, pidB, { table_id = <string> })
--
-- This file is self-contained. It keeps runtime seat state in RAM and
-- gracefully cleans up on disconnect/area-transfer/board-close.

local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local helpers  = require('scripts/ezlibs-scripts/helpers')

local M = {}

local duels_pvp_ok, duels_pvp = false, nil

-- ===== DEBUG =====
local YGO_PVP_DEBUG = true
local function dlog(msg) if YGO_PVP_DEBUG then print("[ygo_pvp] " .. tostring(msg)) end end
local function dlogf(fmt, ...) if YGO_PVP_DEBUG then print("[ygo_pvp] " .. string.format(fmt, ...)) end end

-- injection API (top of ygo_pvp.lua)
local start_pvp_fn = nil
local starter_locked = false

local LobbyOK, Lobby = pcall(require, "scripts/ezlibs-custom/lobby")
if LobbyOK and Lobby and Lobby.register_activity then
  Lobby.register_activity("ygo_pvp", {
    max_players = 2,
    minimizable = false,
    start = function(players, lobby)
      if not start_pvp_fn then return false end

      -- duels_pvp expects table_id for match_id; lobby_id isn't used there
      local ok = start_pvp_fn(players[1], players[2], { table_id = lobby and lobby.id or "pvp" })
      if ok and duels_pvp and duels_pvp.handle_board_close then
        -- duels_pvp queues pending open and normally waits for board_close;
        -- lobby flow has no board, so trigger it directly.
        pcall(duels_pvp.handle_board_close, { player_id = players[1] })
        pcall(duels_pvp.handle_board_close, { player_id = players[2] })
      end

      return ok
    end
  })
end

function M.set_start_fn(fn, lock)
  if starter_locked then
    dlog("set_start_fn ignored: starter locked")
    return false
  end
  start_pvp_fn = fn
  if lock == true then starter_locked = true end
  dlog("set_start_fn injected" .. (starter_locked and " (locked)" or ""))
  return true
end

duels_pvp_ok, duels_pvp = pcall(require, "scripts/ezlibs-custom/duels_pvp")
if duels_pvp_ok and duels_pvp and duels_pvp.start_card_battle_pvp then
  M.set_start_fn(duels_pvp.start_card_battle_pvp, true)
end

dlog("Starting Yu-Gi-Oh PVP tables")

-- ----------------------
-- Runtime state
-- ----------------------
-- tables_by_area[area_id][table_id] = {
--   seatA = { pid = <player_id>, ready = bool } or nil,
--   seatB = { pid = <player_id>, ready = bool } or nil,
--   status = "idle" | "dueling",
-- }
local tables_by_area = {}

-- quick reverse map to find a player’s table
-- seated_by_pid[pid] = { area_id=..., table_id=..., seat="A"|"B" }
local seated_by_pid = {}

-- Used to re-open the board after actions
local reopen_after_close = {}
local refreshing_flag    = {}

-- ----------------------
-- Helpers
-- ----------------------
local function _get_obj(area_id, object_id)
  local ok, obj = pcall(Net.get_object_by_id, area_id, object_id)
  if not ok then return nil end
  return obj
end

local function _area_tables(area_id)
  tables_by_area[area_id] = tables_by_area[area_id] or {}
  return tables_by_area[area_id]
end

local function _get_table_id(obj)
  -- Support either custom property key or fallback to object numeric id
  local cp = obj.custom_properties or {}
  return tostring(cp["Duel Table ID"] or cp["table_id"] or obj.id)
end

local function _seat_of(pid)
  return seated_by_pid[pid] -- or nil
end

local function _get_table(area_id, table_id)
  local slot = _area_tables(area_id)[table_id]
  if not slot then
    slot = { seatA = nil, seatB = nil, status = "idle" }
    _area_tables(area_id)[table_id] = slot
  end
  return slot
end

local function _seat_taken_label(seat)
  if not seat or not seat.pid then return "(empty)" end
  local name = Net.get_player_name(seat.pid) or "(?)"
  if seat.ready then
    return name .. " [Ready]"
  else
    return name
  end
end

local function _someone_else(pid, seat)
  return seat and seat.pid and seat.pid ~= pid
end

local function _player_is_seated_here(pid, area_id, table_id)
  local tag = _seat_of(pid)
  return tag and tag.area_id == area_id and tag.table_id == table_id
end

local function _mask_table_to_status(tbl)
  local A = tbl.seatA and tbl.seatA.pid
  local B = tbl.seatB and tbl.seatB.pid
  local Aready = tbl.seatA and tbl.seatA.ready
  local Bready = tbl.seatB and tbl.seatB.ready
  if tbl.status == "dueling" then return "Dueling" end
  if A and B then
    if Aready and Bready then return "Ready" else return "Seated" end
  end
  if A or B then return "Open Seat" end
  return "Idle"
end

-- ----------------------
-- UI: open the Duel Table board for a player
-- ----------------------
local BOARD_COLOR = { r=50, g=160, b=220, a=255 }

local function _open_table_board(pid, area_id, object_id)
  local obj = _get_obj(area_id, object_id)
  if not obj then return end
  local table_id = _get_table_id(obj)
  local slot = _get_table(area_id, table_id)

  local seat_info = _seat_of(pid)
  local i_am_seated = seat_info and seat_info.area_id == area_id and seat_info.table_id == table_id
  local my_seat = i_am_seated and seat_info.seat or nil

  local title = ("Duel Table #%s  —  %s"):format(table_id, _mask_table_to_status(slot))
  local posts = {}

  -- Seats summary
  posts[#posts+1] = { id="ygo:noop", read=true, title="Seat A: ".._seat_taken_label(slot.seatA) }
  posts[#posts+1] = { id="ygo:noop", read=true, title="Seat B: ".._seat_taken_label(slot.seatB) }

  -- Actions for the viewer
  if slot.status ~= "dueling" then
    if not i_am_seated then
      if not slot.seatA then posts[#posts+1] = { id="ygo:sit:A:"..area_id..":"..table_id..":"..object_id, read=true, title="Sit in Seat A" } end
      if not slot.seatB then posts[#posts+1] = { id="ygo:sit:B:"..area_id..":"..table_id..":"..object_id, read=true, title="Sit in Seat B" } end
    else
      -- viewer seated
      if my_seat == "A" then
        if slot.seatA.ready then
          posts[#posts+1] = { id="ygo:unready:"..area_id..":"..table_id..":"..object_id, read=true, title="Unready" }
        else
          posts[#posts+1] = { id="ygo:ready:"..area_id..":"..table_id..":"..object_id,   read=true, title="Ready Up" }
        end
      else
        if slot.seatB.ready then
          posts[#posts+1] = { id="ygo:unready:"..area_id..":"..table_id..":"..object_id, read=true, title="Unready" }
        else
          posts[#posts+1] = { id="ygo:ready:"..area_id..":"..table_id..":"..object_id,   read=true, title="Ready Up" }
        end
      end
      posts[#posts+1] = { id="ygo:leave:"..area_id..":"..table_id..":"..object_id, read=true, title="Leave Seat" }
    end
  else
    posts[#posts+1] = { id="ygo:noop", read=true, title="A duel is currently in progress." }
  end

  -- Quality-of-life: Refresh
  posts[#posts+1] = { id="ygo:refresh:"..area_id..":"..table_id..":"..object_id, read=true, title="Refresh" }

  Net.open_board(pid, title, BOARD_COLOR, posts)
end

-- Schedule a reopen after an action
local function _reopen(pid)
  dlogf("_reopen: pid=%s", tostring(pid))
  reopen_after_close[pid] = true
  pcall(Net.close_bbs, pid)
end

-- ----------------------
-- Seat mutations
-- ----------------------
local function _sit(pid, area_id, table_id, which, object_id)
  local slot = _get_table(area_id, table_id)
  if slot.status == "dueling" then
    Net.message_player(pid, "This table is currently in a duel.")
    return _reopen(pid)
  end
  if which == "A" then
    if slot.seatA and slot.seatA.pid ~= pid then
      Net.message_player(pid, "Seat A is occupied.")
      return _reopen(pid)
    end
    slot.seatA = { pid = pid, ready = false }
    seated_by_pid[pid] = { area_id=area_id, table_id=table_id, seat="A", object_id=object_id }
  else
    if slot.seatB and slot.seatB.pid ~= pid then
      Net.message_player(pid, "Seat B is occupied.")
      return _reopen(pid)
    end
    slot.seatB = { pid = pid, ready = false }
    seated_by_pid[pid] = { area_id=area_id, table_id=table_id, seat="B", object_id=object_id }
  end
  return _reopen(pid)
end

local function _leave(pid, area_id, table_id)
  local slot = _get_table(area_id, table_id)
  if slot.seatA and slot.seatA.pid == pid then
    slot.seatA = nil
  elseif slot.seatB and slot.seatB.pid == pid then
    slot.seatB = nil
  end
  seated_by_pid[pid] = nil
  return _reopen(pid)
end

local function _set_ready(pid, area_id, table_id, ready)
  local slot = _get_table(area_id, table_id)
  if not slot then
    Net.message_player(pid, "[YGO] Duel table not found.")
    return
  end

  if slot.status == "dueling" then
    dlog("_set_ready: already dueling → reopen seat's board")
    return _reopen(pid)
  end

  -- Mark the caller as ready/unready
  if slot.seatA and slot.seatA.pid == pid then
    slot.seatA.ready = ready
  elseif slot.seatB and slot.seatB.pid == pid then
    slot.seatB.ready = ready
  else
    Net.message_player(pid, "You are not seated at this table.")
    return _reopen(pid)
  end

  -- If both ready → start duel
  if slot.seatA and slot.seatB and slot.seatA.ready and slot.seatB.ready then
    local p1, p2 = slot.seatA.pid, slot.seatB.pid
    dlogf("_set_ready: BOTH READY at table=%s (A=%s, B=%s)", tostring(table_id), tostring(p1), tostring(p2))

    -- prefer injected starter; fallback to global
    local starter = start_pvp_fn
    if not starter then
      dlog("_set_ready: starter MISSING")
      Net.message_player(p1, "[YGO] PVP entrypoint missing (duels_pvp.start_card_battle_pvp).")
      Net.message_player(p2, "[YGO] PVP entrypoint missing (duels_pvp.start_card_battle_pvp).")
      slot.seatA.ready, slot.seatB.ready = false, false
      slot.status = "idle"
      _reopen(p1); _reopen(p2)
      return
    end

    -- Transition to dueling and invoke the starter
    slot.status = "dueling"
    dlog("_set_ready: status=dueling; invoking starter")

    local ok, ret = pcall(starter, p1, p2, { table_id = table_id })
    dlogf("_set_ready: starter returned ok=%s ret=%s", tostring(ok), tostring(ret))

    if not ok or ret == false or ret == nil then
      dlog("_set_ready: START FAILED → reverting lobby to idle")
      slot.status = "idle"
      slot.seatA.ready, slot.seatB.ready = false, false
      _reopen(p1); _reopen(p2)
      return
    end

    -- Success: hand off UI to battle
    dlog("_set_ready: STARTED OK; clearing table flags & requesting BBS close")

    -- Clear any leftover lobby reopen/refresh flags so we don't swallow the next close
    if reopen_after_close then
      reopen_after_close[p1] = nil
      reopen_after_close[p2] = nil
    end
    if refreshing_flag then
      refreshing_flag[p1] = nil
      refreshing_flag[p2] = nil
    end

    -- Close the duel-table BBS; custom.lua will open battle UI on board_close
    pcall(Net.close_bbs, p1)
    pcall(Net.close_bbs, p2)
    -- Do NOT call _reopen here; battle UI will open via custom.lua's board_close using battle_reopen[*]
  else
    dlogf("_set_ready: ONE READY (A=%s, B=%s)", tostring(slot.seatA and slot.seatA.ready), tostring(slot.seatB and slot.seatB.ready))
    _reopen(pid)
  end
end

-- ----------------------
-- Events
-- ----------------------

-- Interact with object → open table board
Net:on("object_interaction", function(event)
  if event.button ~= 0 then return end -- A only
  local pid     = event.player_id
  local area_id = Net.get_player_area(pid)
  local obj     = _get_obj(area_id, event.object_id)
  if not obj then return end

  -- Accept both .class and .type for safety (like octo-ranking)
  if (obj.class ~= "Duel Table" and obj.type ~= "Duel Table") then return end

  -- Open the board for this table
  if Lobby and Lobby.open_activity then
    Lobby.open_activity(pid, "ygo_pvp")
  else
    _open_table_board(pid, area_id, event.object_id)
  end
end)

-- Expose a handler your main router can call
function M.handle_post_selection(event)
  dlogf("post_selection: pid=%s post_id=%s", tostring(event.player_id), tostring(event.post_id))
  local pid  = event.player_id
  local post = tostring(event.post_id or "")
  if not post:find("^ygo:") then return false end

  -- Split by colon: ygo:sit:A:<area_id>:<table_id>:<object_id>
  local parts = {}
  for tok in post:gmatch("([^:]+)") do parts[#parts+1] = tok end
  -- parts[1]="ygo", [2]=verb, [3]=maybe seat, [4]=area_id, [5]=table_id, [6]=object_id
  local verb     = parts[2]
  local seat     = (parts[3] == "A" or parts[3] == "B") and parts[3] or nil
  local idx_base = seat and 4 or 3
  local area_id  = parts[idx_base]
  local table_id = parts[idx_base + 1]
  local object_id= parts[idx_base + 2]

  if verb == "sit" and seat then
    _sit(pid, area_id, table_id, seat, object_id); return true
  elseif verb == "ready" then
    _set_ready(pid, area_id, table_id, true);      return true
  elseif verb == "unready" then
    _set_ready(pid, area_id, table_id, false);     return true
  elseif verb == "leave" then
    _leave(pid, area_id, table_id);                return true
  elseif verb == "refresh" or verb == "noop" then
    _open_table_board(pid, area_id, object_id);    return true
  end
  return false
end

-- Wrapper: reopen the lobby board for whoever just closed it
local function _open_board(pid)
  local seat = seated_by_pid[pid]
  if not seat then return end
  refreshing_flag[pid] = true
  _open_table_board(pid, seat.area_id, seat.object_id)
end

-- Expose a board_close hook the main router can call
function M.handle_board_close(event)
  local pid = event.player_id

  -- Debug helpers
  local _dlog  = (type(dlog)  == "function") and dlog  or function(msg) print("[ygo_pvp] " .. tostring(msg)) end
  local _dlogf = (type(dlogf) == "function") and dlogf or function(fmt, ...) print("[ygo_pvp] " .. string.format(fmt, ...)) end

  _dlogf("board_close: pid=%s", tostring(pid))
  _dlogf("flags before: reopen_after_close=%s refreshing_flag=%s",
         tostring(reopen_after_close and reopen_after_close[pid]),
         tostring(refreshing_flag and refreshing_flag[pid]))

  -- 1) Planned LOBBY reopen (Sit/Ready/Unready paths)
  if reopen_after_close and reopen_after_close[pid] then
    reopen_after_close[pid] = nil
    local seat = seated_by_pid and seated_by_pid[pid]
    if not seat then
      _dlog("reopen path: seat not found; delegate")
      return false
    end
    if refreshing_flag then refreshing_flag[pid] = true end
    if type(_open_table_board) == "function" then
      _dlogf("reopen path: opening lobby BBS (area=%s, object=%s, table=%s)",
             tostring(seat.area_id), tostring(seat.object_id), tostring(seat.table_id))
      _open_table_board(pid, seat.area_id, seat.object_id)
      _dlog("reopen path: done (consumed)")
      return true
    else
      _dlog("ERROR: _open_table_board is nil; delegate")
      return false
    end
  end

  -- 2) One-shot swallow after our own lobby refresh
  if refreshing_flag and refreshing_flag[pid] then
    -- BUT: if the table is already dueling, do NOT swallow — delegate so custom.lua can open battle UI
    local seat = seated_by_pid and seated_by_pid[pid]
    local status = nil
    if seat and type(_get_table) == "function" then
      local slot = _get_table(seat.area_id, seat.table_id)
      status = slot and slot.status or nil
    end

    refreshing_flag[pid] = nil

    if status == "dueling" then
      if duels_pvp and duels_pvp.handle_board_close then
      local ok, res = pcall(duels_pvp.handle_board_close, event)
      if not ok then
        _dlog("duels_pvp.handle_board_close ERROR: " .. tostring(res))
        return false
      end
      _dlog("duels_pvp.handle_board_close returned " .. tostring(res))
      return res == true
      end
      return false
    else
      _dlog("refresh path: swallowing one-shot close (consumed)")
      return true
    end
  end

  -- 3) Default: delegate to custom.lua (so it can handle battle_reopen, etc.)
  local seat = seated_by_pid and seated_by_pid[pid]
  if seat and type(_get_table) == "function" then
    local slot = _get_table(seat.area_id, seat.table_id)
    _dlogf("delegate path: table_id=%s status=%s",
           tostring(seat.table_id), tostring(slot and slot.status))
  else
    _dlog("delegate path: no seat or _get_table missing")
  end

  -- If the table is dueling, let duels_pvp open the duel UI
  local seat = seated_by_pid and seated_by_pid[pid]
  if seat and type(_get_table) == "function" then
    local slot = _get_table(seat.area_id, seat.table_id)
    local status = slot and slot.status
    if status == "dueling" then
      if duels_pvp and duels_pvp.handle_board_close then
      local ok, res = pcall(duels_pvp.handle_board_close, event)
      if not ok then
        _dlog("duels_pvp.handle_board_close ERROR: " .. tostring(res))
        return false
      end
      _dlog("duels_pvp.handle_board_close returned " .. tostring(res))
      return res == true
      end
    end
  end

  return false
  end

-- Clean up seats when a player leaves/disconnects
Net:on("player_disconnect", function(event)
  local seat = _seat_of(event.player_id)
  if not seat then return end
  local slot = _get_table(seat.area_id, seat.table_id)
  if slot.seatA and slot.seatA.pid == event.player_id then slot.seatA = nil end
  if slot.seatB and slot.seatB.pid == event.player_id then slot.seatB = nil end
  slot.status = "idle"
  seated_by_pid[event.player_id] = nil
end)

Net:on("player_area_transfer", function(event)
  local seat = _seat_of(event.player_id)
  if not seat then return end
  if seat.area_id ~= Net.get_player_area(event.player_id) then
    local slot = _get_table(seat.area_id, seat.table_id)
    if slot.seatA and slot.seatA.pid == event.player_id then slot.seatA = nil end
    if slot.seatB and slot.seatB.pid == event.player_id then slot.seatB = nil end
    slot.status = "idle"
    seated_by_pid[event.player_id] = nil
  end
end)

-- ----------------------
-- API from the battle system to free a table after duel
-- Call this from your PVP battle end code.
-- ----------------------
function M.on_ygo_pvp_end(pidWinner, pidLoser, opts)
  dlogf("on_ygo_pvp_end: winner=%s loser=%s table_id=%s",
        tostring(pidWinner), tostring(pidLoser), tostring(opts and opts.table_id))

  local a = _seat_of(pidWinner)
  local b = _seat_of(pidLoser)

  if a and b and a.area_id == b.area_id and a.table_id == b.table_id then
    local slot = _get_table(a.area_id, a.table_id)
    slot.seatA, slot.seatB = nil, nil
    slot.status = "idle"
    if seated_by_pid[pidWinner] then seated_by_pid[pidWinner] = nil end
    if seated_by_pid[pidLoser]  then seated_by_pid[pidLoser]  = nil end
  else
    if a then
      local slot = _get_table(a.area_id, a.table_id)
      if slot.seatA and slot.seatA.pid == pidWinner then slot.seatA = nil end
      if slot.seatB and slot.seatB.pid == pidWinner then slot.seatB = nil end
      slot.status = "idle"
      seated_by_pid[pidWinner] = nil
    end
    if b then
      local slot = _get_table(b.area_id, b.table_id)
      if slot.seatA and slot.seatA.pid == pidLoser then slot.seatA = nil end
      if slot.seatB and slot.seatB.pid == pidLoser then slot.seatB = nil end
      slot.status = "idle"
      seated_by_pid[pidLoser] = nil
    end
  end
end
print("[ygo] Starting Yu-Gi-Oh PVP tables")
return M