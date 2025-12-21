-- scripts/ezlibs-custom/quest_bbs.lua
-- Single-quest Quest BBS using JobBBS-style yes/no flow.

local ezquests = require("scripts/ezlibs-scripts/ezquests")
local eznpcs   = require("scripts/ezlibs-scripts/eznpcs/eznpcs")
local ezcache  = require("scripts/ezlibs-scripts/ezcache")

local quest_bbs = {}

-- Track NPC spawn (global) and per-player pending modal step
local spawned_npcs   = {}     -- key = area_id:object_id
local quest_modal    = {}     -- [pid] = { quest_id=..., step="info"/"question" }

local function qlog(...)
  print("[QuestBBS]", ...)
end

----------------------------------------------------------------
-- Board-close guard helpers (reuse custom.lua guard)
----------------------------------------------------------------
local function _mark_ignore_next_close(pid, reason)
  if _G and _G._guard_ignore_next_close then
    _G._guard_ignore_next_close(pid, reason or "quest_bbs")
  end
end

local function open_board_guarded(pid, title, color, posts, reason)
  _mark_ignore_next_close(pid, reason or ("quest_bbs:" .. tostring(title)))
  qlog("opening board", title, "for", pid, "reason=", reason)
  Net.open_board(pid, title, color, posts)
end

----------------------------------------------------------------
-- Quest definition: "Need help"
----------------------------------------------------------------
local QUEST_BOARD_COLOR = { r = 85, g = 85, b = 85 }

local QUEST_ID = "wcity2_need_help"

local QUEST = {
  quest_name    = QUEST_ID,
  title         = "Need help",
  requestor     = "ExplrNavi",
  body          = "Hello, I found this strange area hidden in the net and I'd like some help exploring it. Meet me in WCity2.",

  -- For testing, you said npc is currently on area "default" with object id 179.
  -- Later you can change this to npc_area_id = "WCity2" and npc_object_id = 29.
  npc_area_id   = "WCity2",
  npc_object_id = 195,
}

----------------------------------------------------------------
-- Quest state helpers (simple: just use ezquests flags)
----------------------------------------------------------------
local function quest_is_accepted(pid)
  local ok, flag = pcall(ezquests.get_player_quest_flag, pid, QUEST.quest_name, "accepted")
  if not ok then
    qlog("get_player_quest_flag error:", flag)
    return false
  end
  return flag and true or false
end

local function quest_state_for(pid)
  if quest_is_accepted(pid) then
    return "accepted"
  end
  return "unaccepted"
end

local function state_token(state)
  if state == "accepted" then
    return "[>]"
  else
    return "[ ]"
  end
end

local function mark_quest_accepted(pid)
  local ok, err = pcall(ezquests.set_player_quest_flag, pid, QUEST.quest_name, "accepted", true)
  if not ok then
    qlog("set_player_quest_flag error:", err)
  end
end

----------------------------------------------------------------
-- NPC spawn helpers
----------------------------------------------------------------
local function spawn_quest_npc()
  local key = QUEST.npc_area_id .. ":" .. tostring(QUEST.npc_object_id)
  if spawned_npcs[key] then
    return
  end

  qlog("Spawning quest NPC from object", QUEST.npc_object_id, "in", QUEST.npc_area_id)
  local ok, err = pcall(eznpcs.create_npc_from_object, QUEST.npc_area_id, QUEST.npc_object_id)
  if not ok then
    qlog("ERROR spawning quest NPC:", err)
    return
  end
  spawned_npcs[key] = true
end

local function maybe_spawn_for_player(player_id)
  local area_id = Net.get_player_area(player_id)
  qlog("maybe_spawn_for_player pid=", player_id, "area=", area_id, "accepted=", accepted)
  if not area_id or area_id ~= QUEST.npc_area_id then
    return
  end
  if quest_is_accepted(player_id) then
    spawn_quest_npc()
  end
end

Net:on("player_join", function(ev)
  if ev and ev.player_id then
    maybe_spawn_for_player(ev.player_id)
  end
end)

Net:on("player_area_transfer", function(ev)
  if ev and ev.player_id then
    maybe_spawn_for_player(ev.player_id)
  end
end)

----------------------------------------------------------------
-- Main Quest BBS board
----------------------------------------------------------------
local function open_main_board(pid)
  local posts = {}

  -- Short legend like JobBBS uses
  posts[#posts+1] = { id = "__quest:legendA", read = true, title = "[ ] = Available", author = "" }
  posts[#posts+1] = { id = "__quest:legendB", read = true, title = "[>] = Accepted",  author = "" }
  posts[#posts+1] = { id = "__quest:blank",   read = true, title = "",                author = "" }

  local state = quest_state_for(pid)
  local tok   = state_token(state)

  posts[#posts+1] = {
    id     = "__quest:view:" .. QUEST_ID,
    read   = (state ~= "unaccepted"), -- bold if new
    title  = string.format("%s %s", tok, QUEST.title),
    author = QUEST.requestor,
  }

  posts[#posts+1] = { id = "__quest:close", read = true, title = "Close", author = "" }

  open_board_guarded(pid, "Quest BBS", QUEST_BOARD_COLOR, posts, "quest_bbs:main")
end

----------------------------------------------------------------
-- Accept flow (called after Yes on the question)
----------------------------------------------------------------
local function accept_quest(pid, quest_id)
  if quest_id ~= QUEST_ID then
    return
  end

  if quest_is_accepted(pid) then
    Net.message_player(pid, "You already accepted this quest.")
    open_main_board(pid)
    return
  end

  mark_quest_accepted(pid)
  spawn_quest_npc()

  Net.message_player(
    pid,
    'You accepted the quest "' .. QUEST.title .. '"!\n' ..
    "Meet " .. QUEST.requestor .. " in WCity2."
  )

  open_main_board(pid)
end

----------------------------------------------------------------
-- Object interaction: touching QuestBBS opens the board
----------------------------------------------------------------
Net:on("object_interaction", function(a, b, c)
  -- Normalize payload (table or positional)
  local ev = (type(a) == "table") and a or { player_id = a, object_id = b, button = c }
  local pid = ev.player_id
  if not pid then return end

  -- Only react to confirm / A button (0)
  if ev.button ~= nil and ev.button ~= 0 then return end

  -- Resolve area
  local area_id = ev.area or ev.area_id or (Net.get_player_area and Net.get_player_area(pid))
  area_id = tostring(area_id or "")
  if area_id == "" then return end

  local object_id = ev.object_id
  if not object_id then return end

  local object
  if Net.get_object_by_id then
    object = Net.get_object_by_id(area_id, object_id)
  end
  if not object then
    object = ezcache.get_object_by_id_cached(area_id, object_id)
  end
  if not object then return end

  local typ = tostring(object.type  or "")
  local cls = tostring(object.class or "")

  if typ == "QuestBBS" or cls == "QuestBBS" then
    qlog("object_interaction on QuestBBS:", "area=", area_id,
      "obj_id=", object_id, "type=", typ, "class=", cls)
    open_main_board(pid)
  end
end)

----------------------------------------------------------------
-- Yes/No helper (same semantics as JobBBS)
----------------------------------------------------------------
local function is_yes(r)
  local t = type(r)
  if t == "number" then return r == 1 end
  if t == "boolean" then return r == true end
  if t == "string" then
    local s = r:lower():gsub("^%s*(.-)%s*$", "%1")
    return (s == "1" or s == "y" or s == "yes" or s == "true" or s == "ok" or s == "accept")
  end
  return false
end

----------------------------------------------------------------
-- Board post handler: click quest → info, then question_player
----------------------------------------------------------------
Net:on("post_selection", function(event)
  local pid     = event.player_id
  local post_id = tostring(event.post_id or "")
  if not pid or post_id == "" then
    return
  end

  -- Only handle our own posts
  if not post_id:match("^__quest:") then
    return
  end

  qlog("post_selection pid=", pid, " post_id=", post_id)

  if post_id == "__quest:close" then
    -- Let central BBS/code actually close; we just ignore here
    return
  end

  if post_id == "__quest:legendA" or post_id == "__quest:legendB" or post_id == "__quest:blank" then
    return
  end

  local view_id = post_id:match("^__quest:view:(.+)$")
  if view_id then
    if view_id ~= QUEST_ID then
      return
    end

    local state = quest_state_for(pid)

    -- Step 1: show quest details in a textbox, JobBBS-style
    local header = ("Title: %s\nFrom: %s\n\n"):format(QUEST.title, QUEST.requestor)
    Net.message_player(pid, header .. QUEST.body)

    if state == "unaccepted" then
      -- Mark that we're waiting for the info-box OK first
      quest_modal[pid] = { quest_id = QUEST_ID, step = "info" }
    elseif state == "accepted" then
      Net.message_player(
        pid,
        "You already accepted this quest.\n" ..
        "Meet " .. QUEST.requestor .. " in WCity2."
      )
    else
      Net.message_player(pid, "This quest is already finished.")
    end

    return
  end
end)

----------------------------------------------------------------
-- textbox_response: two-step flow like JobBBS
--  step 'info'     -> we trigger question_player('Accept this quest?')
--  step 'question' -> interpret Yes/No and accept or not
----------------------------------------------------------------
Net:on("textbox_response", function(a, b)
  local pid, response
  if type(a) == "table" then
    pid      = a.player_id or a[1]
    response = (a.response ~= nil) and a.response or a[2]
  else
    pid, response = a, b
  end

  if not pid or response == nil then
    return
  end

  local state = quest_modal[pid]
  if not state then
    -- Not our modal; let JobBBS/custom/etc handle it.
    return
  end

  qlog("textbox_response pid=", pid, " resp=", tostring(response), " type=", type(response), " step=", state.step)

  if state.step == "info" then
    -- First response: OK on the info box.
    -- Move to question step and ask "Accept this quest?"
    state.step = "question"
    Net.question_player(pid, "Accept this quest?")
    return
  end

  -- Second response: Yes/No to the question.
  quest_modal[pid] = nil

  if is_yes(response) then
    accept_quest(pid, state.quest_id)
  else
    Net.message_player(pid, "Quest not accepted.")
    open_main_board(pid)
  end
end)

----------------------------------------------------------------
-- Public API (optional)
----------------------------------------------------------------
function quest_bbs.open_main_board(pid)
  open_main_board(pid)
end

return quest_bbs
