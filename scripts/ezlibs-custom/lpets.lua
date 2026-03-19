-- /server/scripts/ezlibs-custom/lpets.lua
-- Pet menu placeholder board

local LPets = {}

local helpers_ok, helpers = pcall(require, "scripts/ezlibs-scripts/helpers")
local ezmenus = require("scripts/ezlibs-scripts/ezmenus")

local PetsOK, Pets = pcall(require, "scripts/ezlibs-custom/pets")
if not PetsOK then
  Pets = nil
end

local function log(...)
  if helpers_ok and helpers and type(helpers.info) == "function" then
    helpers.info("[LPets]", ...)
  else
    local parts = { "[LPets]" }
    for i = 1, select("#", ...) do
      parts[#parts+1] = tostring(select(i, ...))
    end
    print(table.concat(parts, " "))
  end
end

local function warn(...)
  if helpers_ok and helpers and type(helpers.warn) == "function" then
    helpers.warn("[LPets][WARN]", ...)
  else
    local parts = { "[LPets][WARN]" }
    for i = 1, select("#", ...) do
      parts[#parts+1] = tostring(select(i, ...))
    end
    print(table.concat(parts, " "))
  end
end

local CHIP_NAMES = {
  [1]  = "Recovery30",
  [2]  = "Recovery50",
  [3]  = "PanelSteal",
  [4]  = "AreaSteal",
  [5]  = "HolyPanel",
  [6]  = "Sanctuary",
  [7]  = "Invisible",
  [8]  = "Shadow",
  [9]  = "Barrier",
  [10] = "Barrier100",
}

local MAIN_INFO_ROWS = {
  ["__lpets:header"] = true,
  ["__lpets:name"] = true,
  ["__lpets:mood"] = true,
  ["__lpets:hp"] = true,
  ["__lpets:attack"] = true,
  ["__lpets:uid_label"] = true,
  ["__lpets:uid_value"] = true,
  ["__lpets:bugfrags"] = true,
  ["__lpets:exp_header"] = true,
}

local function add_line(posts, id, text, is_read)
  posts[#posts + 1] = {
    id = id,
    read = (is_read ~= false),
    title = text,
    author = "",
  }
end

local function format_mood(mood)
  mood = tostring(mood or "neutral"):lower()

  if mood == "happy" then
    return "Happy"
  elseif mood == "sad" then
    return "Sad"
  end

  return "Neutral"
end

local function add_option(posts, id, text, is_read)
  posts[#posts + 1] = {
    id = id,
    read = (is_read ~= false),
    title = text,
    author = "",
  }
end

local function mark_ignore_next_close(pid, reason)
  if not _G then return end
  local why = reason or "lpets"

  if _G._guard_ignore_next_close then
    _G._guard_ignore_next_close(pid, why)
  end
  if _G._guard_ignore_next_post_selection then
    _G._guard_ignore_next_post_selection(pid, why)
  end
  if _G._guard_ignore_next_post then
    _G._guard_ignore_next_post(pid, why)
  end
  if _G._guard_ignore_next_selection then
    _G._guard_ignore_next_selection(pid, why)
  end
end

local function open_menu_ignoring_custom(pid, title, color, posts, reason)
  return ezmenus.open_menu(pid, title, color, posts)
end

local function close_menu(pid, board, reason)
  mark_ignore_next_close(pid, reason or "lpets:close")

  if board and board.close then
    pcall(function() board:close() end)
  else
    pcall(Net.close_bbs, pid)
  end
end

local function trim_label(text, max_len)
  text = tostring(text or "")
  max_len = math.max(1, math.floor(tonumber(max_len) or 21))
  if #text <= max_len then
    return text
  end
  return text:sub(1, max_len)
end

local function build_candidate_label(p, seen, totals)
  local base = tostring(p.display_name or p.base_name or "Pet")
  local suffix = ""

  if (totals[base] or 0) > 1 then
    seen[base] = (seen[base] or 0) + 1
    suffix = suffix .. " No." .. tostring(seen[base])
  end

  if p.placed then
    suffix = suffix .. " [HP]"
  end

  local max_base = 21 - #suffix
  if max_base < 1 then max_base = 1 end

  return trim_label(base, max_base) .. suffix
end

local function open_companion_picker(pid, allow_replace)
  local title = "      Select Companion      "
  local color = { r = 0, g = 255, b = 25 }

  local posts = {}
  local candidates = {}

  if Pets and type(Pets.list_companion_candidates) == "function" then
    local ok, result = pcall(Pets.list_companion_candidates, pid)
    if ok and type(result) == "table" then
      candidates = result
    else
      warn("Pets.list_companion_candidates failed:", tostring(result))
    end
  end

  add_line(posts, "__lpets:pick_header", "--- Your Pets ---")

if #candidates == 0 then
    add_line(posts, "__lpets:none_ready", "(No pets ready)")
  else
    local totals = {}
    local seen = {}

    for _, p in ipairs(candidates) do
      local base = tostring(p.display_name or p.base_name or "Pet")
      totals[base] = (totals[base] or 0) + 1
    end

    for _, p in ipairs(candidates) do
      local label = build_candidate_label(p, seen, totals)
      local uid = tostring(p.uid or "")
      add_option(posts, "__lpets:pet:" .. uid, label)
    end
  end

  -- Expedition section
  local exp_info = nil
  if Pets and type(Pets.get_expedition_pet_info) == "function" then
    local ok, result = pcall(Pets.get_expedition_pet_info, pid)
    if ok and type(result) == "table" then
      exp_info = result
    end
  end

  if exp_info then
    local mins_left = math.ceil((tonumber(exp_info.secs_left) or 0) / 60)
    add_line(posts, "__lpets:exp_header", "--- On Expedition ---")
    add_line(posts, "__lpets:exp_pet", tostring(exp_info.display_name) .. " (" .. tostring(mins_left) .. " min)")
  end

  local train_info = nil
  if Pets and type(Pets.get_training_pet_info) == "function" then
    local ok, result = pcall(Pets.get_training_pet_info, pid)
    if ok and type(result) == "table" then
      train_info = result
    end
  end

  if train_info then
    local mins_left = math.ceil((tonumber(train_info.secs_left) or 0) / 60)
    add_line(posts, "__lpets:train_header", "--- Training ---")
    add_line(posts, "__lpets:train_pet", tostring(train_info.display_name) .. " (" .. tostring(mins_left) .. " min)")
  end

  add_option(posts, "__lpets:back", "Back")

  local board = open_menu_ignoring_custom(pid, title, color, posts, "lpets:pick")
  local sel = tostring(await(board.selection_once()) or "")
  log("lpets picker selection = " .. sel)

  close_menu(pid, board, "lpets:pick_close")
  await(Async.sleep(0.25))

  if sel == "" or sel == "__lpets:back" or sel == "Back" then
    LPets.open_pets_board(pid)
    return
  end

  if sel == "__lpets:exp_pet" then
    Net.message_player(pid, "That pet is out on an expedition, it can't join you at the moment.")
    return
  end

  if sel == "__lpets:train_pet" then
    Net.message_player(pid, "That pet is in training, it can't join you at the moment.")
    return
  end

  local uid = sel:match("^__lpets:pet:(.+)$")
  if not uid or uid == "" then
    return
  end

  if not Pets or type(Pets.arm_owned_pet) ~= "function" then
    Net.message_player(pid, "Pet companion selection isn't available.")
    return
  end

  local ok, success, msg = pcall(Pets.arm_owned_pet, pid, uid, allow_replace == true)
  if not ok then
    warn("Pets.arm_owned_pet failed:", tostring(success))
    Net.message_player(pid, "Couldn't select that companion pet.")
    return
  end

  Net.message_player(pid, msg or (success and "Companion pet selected." or "Couldn't select that companion pet."))
end

local function build_chip_label(row)
  local name = tostring(row and row.name or "Chip")
  local qty  = math.max(1, math.floor(tonumber(row and row.qty or 1) or 1))
  return trim_label(name .. " x" .. tostring(qty), 21)
end

local function open_pet_chip_picker(pid, info)
  if not info or not info.uid or info.uid == "" then
    return
  end

  local title = "        Select Pet Chip       "
  local color = { r = 0, g = 255, b = 25 }
  local posts = {}

  add_line(posts, "__lpets:chip_header", "--- Pet Chips ---")

  local rows = {}
  if Pets and type(Pets.list_player_pet_chip_inventory) == "function" then
    local ok, result = pcall(Pets.list_player_pet_chip_inventory, pid)
    if ok and type(result) == "table" then
      rows = result
    else
      warn("Pets.list_player_pet_chip_inventory failed:", tostring(result))
    end
  end

  if info.pet_chip_id then
    add_option(posts, "__lpets:chip_unequip", "Unequip")
  end

  if #rows == 0 then
    add_line(posts, "__lpets:nochips", "(No pet chips)")
  else
    for _, row in ipairs(rows) do
      add_option(posts, "__lpets:chip:" .. tostring(row.chip_id), build_chip_label(row))
    end
  end

  add_option(posts, "__lpets:back", "Back")

  local board = open_menu_ignoring_custom(pid, title, color, posts, "lpets:chip_pick")
  local sel = tostring(await(board.selection_once()) or "")
  log("lpets chip selection = " .. sel)

  close_menu(pid, board, "lpets:chip_pick_close")
  await(Async.sleep(0.25))

  if sel == "" or sel == "__lpets:back" or sel == "Back" then
    LPets.open_pets_board(pid)
    return
  end

  if sel == "__lpets:chip_unequip" then
    if not Pets or type(Pets.unequip_chip_from_pet) ~= "function" then
      Net.message_player(pid, "Pet chip unequip isn't available.")
      return
    end

    local ok, success, msg = pcall(Pets.unequip_chip_from_pet, pid, info.uid)
    if not ok then
      warn("Pets.unequip_chip_from_pet failed:", tostring(success))
      Net.message_player(pid, "Couldn't unequip that pet chip.")
      return
    end

    Net.message_player(pid, msg or (success and "Pet chip unequipped." or "Couldn't unequip that pet chip."))
    LPets.open_pets_board(pid)
    return
  end

  local chip_id = tonumber(sel:match("^__lpets:chip:(%d+)$"))
  if not chip_id then
    return
  end

  if not Pets or type(Pets.equip_chip_on_pet) ~= "function" then
    Net.message_player(pid, "Pet chip equip isn't available.")
    return
  end

  local ok, success, msg = pcall(Pets.equip_chip_on_pet, pid, info.uid, chip_id)
  if not ok then
    warn("Pets.equip_chip_on_pet failed:", tostring(success))
    Net.message_player(pid, "Couldn't equip that pet chip.")
    return
  end

  Net.message_player(pid, msg or (success and "Pet chip equipped." or "Couldn't equip that pet chip."))
  LPets.open_pets_board(pid)
end

local function open_pet_xp_board(pid, info)
  if not info or not info.uid or info.uid == "" then
    LPets.open_pets_board(pid)
    return
  end

  local title = "            Pet XP           "
  local color = { r = 0, g = 255, b = 25 }

  local function reopen()
    local fresh = info
    if Pets and type(Pets.get_armed_pet_info) == "function" then
      local ok, result = pcall(Pets.get_armed_pet_info, pid)
      if ok and type(result) == "table" then
        fresh = result
      end
    end
    open_pet_xp_board(pid, fresh)
  end

  local xp = math.max(0, math.floor(tonumber(info.xp) or 0))
  local free = math.max(0, math.floor(tonumber(info.available_skill_points) or 0))
  local hp = math.max(1, math.floor(tonumber(info.hp) or 40))
  local attack_rank = math.max(1, math.floor(tonumber(info.rank) or 1))
  local attack_power = math.max(5, math.floor(tonumber(info.attack) or (attack_rank * 5)))
  local hp_points = math.max(0, math.floor(tonumber(info.hp_points) or 0))
  local attack_points = math.max(0, math.floor(tonumber(info.attack_points) or 0))
  local xp_to_next = math.max(0, math.floor(tonumber(info.xp_to_next_skill_point) or 0))
  local notify_on = info.xp_notifications_enabled ~= false

  local posts = {}
  add_line(posts, "__lpets:xp_header", "--- Pet XP ---")
  add_line(posts, "__lpets:xp_value", "Current XP: " .. tostring(xp))
  add_line(posts, "__lpets:xp_next", "Next Point: " .. tostring(xp_to_next) .. " XP")
  add_line(posts, "__lpets:xp_free", "Skill Points: " .. tostring(free), free <= 0)
  add_option(posts, "__lpets:xp_toggle", "Notifications: " .. (notify_on and "ON" or "OFF"))

  local hp_label = "HP: " .. tostring(hp) .. " (+" .. tostring(hp_points * 5) .. ")"
  local attack_label = "Attack: " .. tostring(attack_power) .. " (Rank " .. tostring(attack_rank) .. ", +" .. tostring(attack_points * 5) .. ")"

  if free > 0 then
    add_option(posts, "__lpets:xp_hp", hp_label, false)
    add_option(posts, "__lpets:xp_attack", attack_label, false)
  else
    add_line(posts, "__lpets:xp_hp", hp_label)
    add_line(posts, "__lpets:xp_attack", attack_label)
  end

  add_option(posts, "__lpets:back", "Back")

  local board = open_menu_ignoring_custom(pid, title, color, posts, "lpets:xp")
  local sel = tostring(await(board.selection_once()) or "")
  log("lpets xp selection = " .. sel)

  close_menu(pid, board, "lpets:xp_close")
  await(Async.sleep(0.25))

  if sel == "" or sel == "__lpets:back" or sel == "Back" then
    LPets.open_pets_board(pid)
    return
  end

  if sel == "__lpets:xp_toggle" then
    if Pets and type(Pets.set_pet_xp_notifications_enabled) == "function" then
      local ok, success = pcall(Pets.set_pet_xp_notifications_enabled, pid, not notify_on)
      if not ok or not success then
        Net.message_player(pid, "Couldn't change pet XP notifications.")
      end
    end
    reopen()
    return
  end

  if sel == "__lpets:xp_hp" then
    local res = await(Async.question_player(pid, ("Invest 1 skill point into HP? (%d -> %d)"):format(hp, hp + 5)))
    if res == 1 then
      if not Pets or type(Pets.invest_armed_pet_stat) ~= "function" then
        Net.message_player(pid, "Pet stat investing isn't available.")
      else
        local ok, success, msg = pcall(Pets.invest_armed_pet_stat, pid, "hp")
        if not ok then
          warn("Pets.invest_armed_pet_stat hp failed:", tostring(success))
          Net.message_player(pid, "Couldn't invest that skill point.")
        else
          Net.message_player(pid, msg or (success and "HP increased." or "Couldn't invest that skill point."))
        end
      end
    end
    reopen()
    return
  end

  if sel == "__lpets:xp_attack" then
    local res = await(Async.question_player(pid, ("Invest 1 skill point into Attack? (%d -> %d)"):format(attack_power, attack_power + 5)))
    if res == 1 then
      if not Pets or type(Pets.invest_armed_pet_stat) ~= "function" then
        Net.message_player(pid, "Pet stat investing isn't available.")
      else
        local ok, success, msg = pcall(Pets.invest_armed_pet_stat, pid, "attack")
        if not ok then
          warn("Pets.invest_armed_pet_stat attack failed:", tostring(success))
          Net.message_player(pid, "Couldn't invest that skill point.")
        else
          Net.message_player(pid, msg or (success and "Attack increased." or "Couldn't invest that skill point."))
        end
      end
    end
    reopen()
    return
  end

  reopen()
end

local function open_pets_board_async(pid)
  if not Net or not Net.open_board then
    warn("Net or Net.open_board missing; cannot open Pet Menu board.")
    return
  end

  local title = "       Companion Pet Menu     "
  local color = { r = 0, g = 255, b = 25 }
  local posts = {}

  add_line(posts, "__lpets:header", "--- Companion Pet ---")

  local info = nil
  if not Pets then
    warn("lpets: pets.lua failed to load")
  elseif type(Pets.get_armed_pet_info) ~= "function" then
    warn("lpets: Pets.get_armed_pet_info is missing")
  else
    local ok, result = pcall(Pets.get_armed_pet_info, pid)
    if ok then
      info = result
    else
      warn("Pets.get_armed_pet_info failed:", tostring(result))
    end
  end

  if not info then
    add_option(posts, "__lpets:choose", "(No pet selected)")
    add_option(posts, "__lpets:back", "Back")

    local board = open_menu_ignoring_custom(pid, title, color, posts, "lpets:main_empty")
    local sel = tostring(await(board.selection_once()) or "")
    log("lpets empty selection = " .. sel)

    close_menu(pid, board, "lpets:main_empty_close")
    await(Async.sleep(0.25))

    if sel == "__lpets:choose" or sel == "(No pet selected)" then
      open_companion_picker(pid, false)
    end
    return
  end

  local has_skill_points = math.max(0, math.floor(tonumber(info.available_skill_points) or 0)) > 0

  add_line(posts, "__lpets:name", "Name: " .. tostring(info.display_name or info.base_name or "Pet"))
  add_line(posts, "__lpets:mood", "Mood: " .. format_mood(info.mood))
  add_option(posts, "__lpets:xp", "XP: " .. tostring(info.xp or 0), not has_skill_points)

  if info.can_fight then
    local chip_text = "None"
    if info.pet_chip_id then
      local chip_name = CHIP_NAMES[info.pet_chip_id] or ("Chip " .. tostring(info.pet_chip_id))
      chip_text = chip_name
      if tonumber(info.pet_chip_amount or 1) > 1 then
        chip_text = chip_text .. " x" .. tostring(info.pet_chip_amount)
      end
    end

    add_line(posts, "__lpets:hp",     "HP: " .. tostring(info.hp or 40))
    add_option(posts, "__lpets:chip", "Chip: " .. chip_text)
    add_line(posts, "__lpets:attack", "Attack: " .. tostring(info.attack or 5))
  else
    add_line(posts, "__lpets:nofight1", "This pet family")
    add_line(posts, "__lpets:nofight2", "doesn't like to")
    add_line(posts, "__lpets:nofight3", "fight")
  end

  add_line(posts, "__lpets:uid_label", "Unique ID:")
  add_line(posts, "__lpets:uid_value", tostring(info.uid or ""))

  local bugfrags = 0
  if Pets and type(Pets.get_player_bugfrags) == "function" then
    local ok, n = pcall(Pets.get_player_bugfrags, pid)
    if ok then bugfrags = tonumber(n) or 0 end
  end
  add_line(posts, "__lpets:bugfrags", "Bugfrags: " .. tostring(bugfrags))

  if not info.summoned then
    add_option(posts, "__lpets:summon", "Summon")
  end

  if tostring(info.mood or "neutral"):lower() ~= "happy" then
    add_option(posts, "__lpets:feed", "Feed 1 BugFrag")
  end

  add_option(posts, "__lpets:change", "Change Companion")

  local unarm_label = (tostring(info.bucket_area_id or "") ~= "") and "Return to HP" or "Unselect Pet"
  add_option(posts, "__lpets:unarm", unarm_label)
  add_option(posts, "__lpets:back", "Back")

  local board = open_menu_ignoring_custom(pid, title, color, posts, "lpets:main_full")
  local sel = tostring(await(board.selection_once()) or "")
  log("lpets full selection = " .. sel)

  close_menu(pid, board, "lpets:main_full_close")
  await(Async.sleep(0.25))

  if sel == "" or sel == "__lpets:back" or sel == "Back" then
    return
  end

  if sel == "__lpets:chip" then
    if info and info.can_fight then
      open_pet_chip_picker(pid, info)
    end
    return
  end

  if sel == "__lpets:xp" then
    open_pet_xp_board(pid, info)
    return
  end

  if sel == "__lpets:summon" or sel == "Summon" then
    if not Pets or type(Pets.summon_companion) ~= "function" then
      Net.message_player(pid, "Companion pet summoning isn't available.")
      return
    end

    local ok, success, msg = pcall(Pets.summon_companion, pid)
    if not ok then
      warn("Pets.summon_companion failed:", tostring(success))
      Net.message_player(pid, "Couldn't summon that companion pet.")
      return
    end

    Net.message_player(pid, msg or (success and "Companion pet summoned." or "Couldn't summon that companion pet."))
    return
  end

  if sel == "__lpets:feed" or sel == "Feed 1 BugFrag" then
    if not Pets or type(Pets.feed_armed_pet) ~= "function" then
      Net.message_player(pid, "Companion pet feeding isn't available.")
      return
    end

    local ok, success, msg = pcall(Pets.feed_armed_pet, pid)
    if not ok then
      warn("Pets.feed_armed_pet failed:", tostring(success))
      Net.message_player(pid, "Couldn't feed that companion pet.")
      return
    end

    Net.message_player(pid, msg or (success and "Your pet seems happier." or "Couldn't feed that companion pet."))
    return
  end

  if sel == "__lpets:change" or sel == "Change Companion" then
    open_companion_picker(pid, true)
    return
  end

  if sel == "__lpets:unarm" or sel == unarm_label then
    if not Pets or type(Pets.unarm_pet) ~= "function" then
      Net.message_player(pid, "Companion pet removal isn't available.")
      return
    end

    local ok, success, msg = pcall(Pets.unarm_pet, pid)
    if not ok then
      warn("Pets.unarm_pet failed:", tostring(success))
      Net.message_player(pid, "Couldn't unselect that companion pet.")
      return
    end

    if success then
      if unarm_label == "Return to HP" then
        Net.message_player(pid, "Companion pet returned to HP.")
      else
        Net.message_player(pid, "Companion pet unselected.")
      end
    else
      Net.message_player(pid, msg or "Couldn't unselect that companion pet.")
    end
    return
  end

  if MAIN_INFO_ROWS[sel] or sel:match("^__lpets:nofight%d+$") then
    LPets.open_pets_board(pid)
    return
  end
end

function LPets.open_pets_board(pid)
  async(function()
    open_pets_board_async(pid)
  end)
end

return LPets