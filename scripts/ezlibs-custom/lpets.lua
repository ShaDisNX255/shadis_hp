-- /server/scripts/ezlibs-custom/lpets.lua
-- LMenu Pet Menu v0.1 (MenuAPI)
--
-- This file is the LMenu-facing UI adapter for pets.lua.
-- pets.lua remains the backend owner of pet memory, companion state,
-- battle stats, chips, training, expedition, summon/call-back, and HP return.

local LPets = {}
_G.LPets = LPets

local helpers_ok, helpers = pcall(require, "scripts/ezlibs-scripts/helpers")

local MenuAPIOK, MenuAPI = pcall(require, "scripts/menuAPI/main")
if not MenuAPIOK then
  MenuAPI = rawget(_G, "MenuAPI")
end

local PetsOK, Pets = pcall(require, "scripts/ezlibs-custom/pets")
if not PetsOK then
  Pets = nil
end

-- ---------------------------------------------------------------------------
-- Logging
-- ---------------------------------------------------------------------------

local function log(...)
  if helpers_ok and helpers and type(helpers.info) == "function" then
    helpers.info("[LPets]", ...)
  else
    local parts = { "[LPets]" }
    for i = 1, select("#", ...) do
      parts[#parts + 1] = tostring(select(i, ...))
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
      parts[#parts + 1] = tostring(select(i, ...))
    end
    print(table.concat(parts, " "))
  end
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local OPEN_PET_MENUS = {}
local LAST_MAIN_ROW_ID_BY_PID = {}
local LAST_PICKER_ROW_ID_BY_PID = {}
local LAST_CHIP_ROW_ID_BY_PID = {}
local LAST_XP_ROW_ID_BY_PID = {}

local function get_menuapi()
  local M = rawget(_G, "MenuAPI") or MenuAPI

  if not (M and type(M.open) == "function") then
    local ok, mod = pcall(require, "scripts/menuAPI/main")
    if ok and type(mod) == "table" then
      M = mod
      MenuAPI = mod
    end
  end

  return M
end

local function short(text, max_ch)
  text = tostring(text or "")
  max_ch = math.max(1, math.floor(tonumber(max_ch) or 20))

  if #text <= max_ch then return text end
  if max_ch <= 3 then return text:sub(1, max_ch) end
  return text:sub(1, max_ch - 3) .. "..."
end

local function proper(text)
  text = tostring(text or "")
  if text == "" then return text end
  return text:sub(1, 1):upper() .. text:sub(2):lower()
end

local function format_mood(mood)
  mood = tostring(mood or "neutral"):lower()

  if mood == "happy" then return "Happy" end
  if mood == "sad" then return "Sad" end
  return "Neutral"
end

local function mood_tint(mood)
  mood = tostring(mood or "neutral"):lower()

  if mood == "happy" then
    return { r = 60, g = 180, b = 80, color_mode = 2 }
  end

  if mood == "sad" then
    return { r = 200, g = 55, b = 55, color_mode = 2 }
  end

  return { r = 230, g = 190, b = 60, color_mode = 2 }
end

local function safe_number(value, fallback)
  return math.floor(tonumber(value) or tonumber(fallback) or 0)
end

local function minutes_label(secs)
  local mins = math.ceil((tonumber(secs) or 0) / 60)
  if mins < 0 then mins = 0 end
  return tostring(mins) .. "m"
end

local function play_error(pid)
  local UI = rawget(_G, "UI_SFX")
  if UI and type(UI.play) == "function" then
    pcall(UI.play, pid, "error")
  end
end

local function message(pid, text, opts)
  text = tostring(text or "")
  if text == "" then return false end

  opts = opts or {}

  local M = get_menuapi()
  if M and type(M.show_message) == "function" then
    local ok, shown = pcall(M.show_message, pid, text, {
      box_id = opts.box_id or "lpets_message",
      speed = opts.speed or 80,
      z = opts.z or 300,
      on_close = opts.on_close,
      modal = opts.modal,
      page_advance = opts.page_advance,
      confirm_during_typing = opts.confirm_during_typing,
    })

    if ok and shown then
      return true
    end
  end

  -- LPets intentionally does not fall back to Net.message_player.
  -- These messages should live inside MenuAPI so they do not fight engine textboxes.
  return false
end

local function row(id, text, right, opts)
  opts = opts or {}

  return {
    id = id,
    text = text,
    right = right,
    show_right = right ~= nil and right ~= "",
    selectable = opts.selectable ~= false,
    enabled = opts.enabled ~= false,
    disabled_prefix = opts.disabled_prefix,
    data = opts.data,
  }
end

local function info_row(id, text, right)
  return row(id, text, right, {
    selectable = false,
    enabled = false,
    disabled_prefix = false,
  })
end

local function row_index_for_id(rows, row_id)
  if not row_id then return nil end

  for i, r in ipairs(rows or {}) do
    if r and r.id == row_id then
      return i
    end
  end

  return nil
end

local function first_selectable_row_id(rows)
  for _, r in ipairs(rows or {}) do
    if r and r.selectable ~= false and r.enabled ~= false then
      return r.id
    end
  end

  return nil
end

local function remember_row(pid, st, bucket)
  if not (pid and st and st.rows and st.cursor and bucket) then return end

  local r = st.rows[st.cursor]
  if r and r.id then
    bucket[pid] = r.id
  end
end

local function menu_opts(opts)
  opts = opts or {}

  return {
    parent = opts.parent or "lmenu",
    open_sfx = opts.open_sfx ~= nil and opts.open_sfx or false,
    cancel_sfx = opts.cancel_sfx ~= nil and opts.cancel_sfx or "cancel",
    lock_input = opts.lock_input == true,
  }
end

local function main_parent(opts)
  opts = menu_opts(opts)

  return function(player_id)
    return LPets.open_pets_board(player_id, opts)
  end
end

local function close_current_keep_frozen(pid, reason)
  local M = get_menuapi()
  if M and type(M.close) == "function" then
    pcall(M.close, pid, { keep_frozen = true, reason = reason or "lpets_replace" })
  end
end

local function refresh_main_later(pid, opts)
  opts = menu_opts(opts)

  if Async and Async.sleep then
    Async.sleep(0.05).and_then(function()
      LPets.open_pets_board(pid, opts)
    end)
  else
    LPets.open_pets_board(pid, opts)
  end
end

-- ---------------------------------------------------------------------------
-- Pet visuals for the type 5 profile mug slot
-- ---------------------------------------------------------------------------

local PET_VISUALS = {
  mettaur  = { name = "Mettaur",  texture = "mettaur.png",  animation = "mettaur.animation",  texture_r2 = "mettaur-r2.png",  texture_r3 = "mettaur-r3.png" },
  meddy    = { name = "Meddy",    texture = "meddy.png",    animation = "meddy.animation",    texture_r2 = "meddy-r2.png",    texture_r3 = "meddy-r3.png" },
  ratty    = { name = "Ratty",    texture = "ratty.png",    animation = "ratty.animation",    texture_r2 = "ratty-r2.png",    texture_r3 = "ratty-r3.png" },
  spooky   = { name = "Spooky",   texture = "spooky.png",   animation = "spooky.animation",   texture_r2 = "spooky-r2.png",   texture_r3 = "spooky-r3.png" },
  swordy   = { name = "Swordy",   texture = "swordy.png",   animation = "swordy.animation",   texture_r2 = "swordy-r2.png",   texture_r3 = "swordy-r3.png" },
  moloko   = { name = "Moloko",   texture = "moloko.png",   animation = "moloko.animation",   texture_r2 = "moloko-r2.png",   texture_r3 = "moloko-r3.png" },
  powie    = { name = "Powie",    texture = "powie.png",    animation = "powie.animation",    texture_r2 = "mowie-r2.png",    texture_r3 = "powie-r3.png" },
  kabutank = { name = "Kabutank", texture = "kabutank.png", animation = "kabutank.animation", texture_r2 = "kabutank-r2.png", texture_r3 = "kabutank-r3.png" },
  jelly    = { name = "Jelly",    texture = "jelly.png",    animation = "jelly.animation",    texture_r2 = "jelly.png",    texture_r3 = "jelly.png" },
  volgear  = { name = "Volgear",  texture = "volgear.png",  animation = "volgear.animation",  texture_r2 = "volgear.png", texture_r3 = "volgear.png" },
  magtect  = { name = "Magtect",  texture = "magtect.png",  animation = "magtect.animation",  texture_r2 = "magtect.png", texture_r3 = "magtect.png" },
  fishy    = { name = "Fishy",    texture = "fishy.png",    animation = "fishy.animation",    texture_r2 = "fishy-r2.png", texture_r3 = "jelly-r3.png" },
  piranha  = { name = "Piranha",  texture = "piranha.png",  animation = "piranha.animation",  texture_r2 = "piranha-r2.png", texture_r3 = "piranha-r3.png" },
  brushman = { name = "Brushman", texture = "brushman.png", animation = "brushman.animation", texture_r2 = "brushman-r2.png", texture_r3 = "brushman-r3.png" },
  bunny    = { name = "Bunny",    texture = "bunny.png",    animation = "bunny.animation",    texture_r2 = "bunny-r2.png", texture_r3 = "bunny-r3.png" },
}

local function pet_visual_paths(kind, attack_rank)
  kind = tostring(kind or ""):lower()
  local def = PET_VISUALS[kind]
  if not def then return nil, nil end

  local rank = safe_number(attack_rank, 1)
  local tex = def.texture

  if rank >= 20 and def.texture_r3 then
    tex = def.texture_r3
  elseif rank >= 11 and def.texture_r2 then
    tex = def.texture_r2
  end

  return "/server/assets/pets/" .. tostring(tex), "/server/assets/pets/" .. tostring(def.animation)
end

local function provide_pet_visual(pid, texture, anim)
  if not (Net and Net.get_player_area and Net.provide_asset) then return end
  local ok, area_id = pcall(Net.get_player_area, pid)
  if not ok or not area_id then return end

  if texture and texture ~= "" then pcall(Net.provide_asset, area_id, texture) end
  if anim and anim ~= "" then pcall(Net.provide_asset, area_id, anim) end
end

-- ---------------------------------------------------------------------------
-- Backend snapshots
-- ---------------------------------------------------------------------------

local function get_armed_info(pid)
  if not (Pets and type(Pets.get_armed_pet_info) == "function") then
    return nil
  end

  local ok, info = pcall(Pets.get_armed_pet_info, pid)
  if ok and type(info) == "table" then
    return info
  end

  if not ok then
    warn("Pets.get_armed_pet_info failed:", tostring(info))
  end

  return nil
end

local function apply_sp_gauge_spec(spec, info)
  spec = spec or {}

  if not info then
    spec.spbar_state = "sp_01"
    spec.spbar_xp = nil
    spec.spbar_xp_per_point = 175
    spec.spbar_available_points = 0
    return spec
  end

  spec.spbar_state = nil
  spec.spbar_xp = safe_number(info.spbar_xp or info.xp, 0)
  spec.spbar_xp_per_point = math.max(1, safe_number(info.spbar_xp_per_point or info.xp_per_skill_point, 175))
  spec.spbar_available_points = safe_number(info.available_skill_points, 0)

  return spec
end

local function get_bugfrags(pid)
  if Pets and type(Pets.get_player_bugfrags) == "function" then
    local ok, count = pcall(Pets.get_player_bugfrags, pid)
    if ok then return safe_number(count, 0) end
  end

  return 0
end

local function chip_name(chip_id)
  if not chip_id then return nil end

  if Pets and type(Pets.get_pet_chip_name) == "function" then
    local ok, name = pcall(Pets.get_pet_chip_name, chip_id)
    if ok and name and name ~= "" then return tostring(name) end
  end

  return "Chip " .. tostring(chip_id)
end

-- ---------------------------------------------------------------------------
-- Pet chip type 5 preview card
-- ---------------------------------------------------------------------------

local PET_CHIP_PREVIEW_DIR = "/server/assets/pets/chips/"

-- Type 5 only descriptions.
-- These do NOT affect shop item descriptions in pets.lua.
local PET_CHIP_PROFILE_DESCRIPTIONS = {
  Recovery30 = "Restores 30 HP to your pet during battle.",
  Recovery50 = "Restores 50 HP to your pet during battle.",
  PanelSteal = "Steals one panel as your pets first move.",
  AreaSteal = "Steals one row as your pets first move.",
  HolyPanel = "Creates a holy panel as the first move.",
  Sanctuary = "Changes your field into holy panels.",
  Invisible = "Makes your pet invisible for a few seconds.",
  Shadow = "Only sword attacks can hit your pet.",
  Barrier = "Gives your pet a small protective barrier.",
  Barrier100 = "Gives your pet a 100 HP barrier.",
}

local function wrap_preview_lines(text, width, max_lines)
  text = tostring(text or "")
  width = math.max(1, math.floor(tonumber(width) or 13))
  max_lines = math.max(1, math.floor(tonumber(max_lines) or 4))

  local lines = {}

  local function push_line(line)
    if #lines >= max_lines then return end
    line = tostring(line or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      lines[#lines + 1] = short(line, width)
    end
  end

  for raw_line in (text .. "\n"):gmatch("(.-)\n") do
    local s = tostring(raw_line or ""):gsub("^%s+", ""):gsub("%s+$", "")

    while s ~= "" and #lines < max_lines do
      if #s <= width then
        push_line(s)
        s = ""
      else
        local cut = s:sub(1, width)
        local p = cut:match("^(.*)%s+") or cut

        if p == "" then
          p = s:sub(1, width)
        end

        push_line(p)
        s = s:sub(#p + 1):gsub("^%s+", "")
      end
    end
  end

  return lines
end

local function empty_chip_profile()
  return {
    title = "",
    title_max_ch = 20,
    title_font = "THICK",
    title_scale = 1.05,

    font = "THICK",
    text_scale = 1.1,
    text_x = 8,
    text_y = 38,
    text_advance = 11,
    text_max_ch = 14,

    lines = {},
  }
end

local function chip_profile_description(chip_id, chip)
  chip_id = tonumber(chip_id)
  chip = chip or {}

  local name = tostring(chip.name or chip_name(chip_id) or "")
  local desc = PET_CHIP_PROFILE_DESCRIPTIONS[name]

  if not desc and chip_id then
    desc = PET_CHIP_PROFILE_DESCRIPTIONS[chip_id]
  end

  if not desc or desc == "" then
    desc = tostring(chip.description or "")
  end

  if desc == "" then
    desc = "No chip info available."
  end

  return desc
end

local function build_chip_profile(pid, selected_row)
  if not (selected_row and type(selected_row.data) == "table") then
    return empty_chip_profile()
  end

  local chip = selected_row.data
  local chip_id = tonumber(chip.chip_id)
  if not chip_id then
    return empty_chip_profile()
  end

  local name = tostring(chip.name or chip_name(chip_id) or "Chip")
  local texture = PET_CHIP_PREVIEW_DIR .. name .. ".png"

  -- Only the PNG is required. Static UI sprites can use no animation.
  provide_pet_visual(pid, texture, nil)

  return {
    title = short(name, 20),
    title_max_ch = 20,

    mug_texture = texture,
    mug_anim = nil,
    mug_state = "",

    -- Tweak these after you see the chip PNGs in-game.
    mug_scale = 1.0,
    mug_x = 7,
    mug_y = 20,

    title_font = "THICK",
    title_scale = 1.05,

    font = "THICK",
    text_scale = 1.05,

    -- Description sits to the right of the chip preview.
    text_x = 40,
    text_y = 15,
    text_advance = 10,
    text_max_ch = 14,

    lines = wrap_preview_lines(chip_profile_description(chip_id, chip), 14, 4),
  }
end

-- ---------------------------------------------------------------------------
-- Main menu builders
-- ---------------------------------------------------------------------------

local function build_profile(pid, info)
  if not info then
    return {
      title = "No Pet",
      title_max_ch = 20,
      title_font = "THICK",
      title_scale = 1.05,
      font = "THICK",
      text_scale = 1.4,
      text_y = 15,
      text_max_ch = 12,
      lines = {
        "Select",
        "Companion",
      },
    }
  end

  local PET_PREVIEW_OFFSETS = {
    -- Positive x moves right. Negative x moves left.
    -- Positive y moves down. Negative y moves up.
    kabutank = { x = 4 },
    fishy    = { x = -4 },
  }

  local texture, anim = pet_visual_paths(info.kind, info.rank)
  provide_pet_visual(pid, texture, anim)

  local hp = safe_number(info.hp, 0)
  local atk = safe_number(info.attack, safe_number(info.rank, 1) * 5)
  local xp = safe_number(info.xp, 0)
  local mood = format_mood(info.mood)
  local preview_offset = PET_PREVIEW_OFFSETS[tostring(info.kind or ""):lower()] or {}
  local mug_x = 21 + safe_number(preview_offset.x, 0)
  local mug_y = 47 + safe_number(preview_offset.y, 0)
  local mug_scale = tonumber(preview_offset.scale) or 2.0

  return {
    title = short(info.display_name or info.base_name or "Pet", 20),
    title_max_ch = 20,

    mug_texture = texture,
    mug_anim = anim,

    -- WALK_DL works, but it will only loop if the pet .animation state loops.
    -- Keep IDLE_DL for now unless you edit the animation file to loop WALK_DL.
    mug_state = "walk_dl",

    -- These will work after the small MenuAPI patch below.
    mug_scale = mug_scale,
    mug_x = mug_x,
    mug_y = mug_y,

    title_font = "THICK",
    title_scale = 1.05,

    font = "THICK",
    text_scale = 1.2,

    -- Lower number moves Mood/HP/ATK/XP upward.
    text_y = 14,
    text_advance = 10,
    text_max_ch = 14,

    line_tints = {
      mood_tint(info.mood),
    },

    lines = {
      short(mood, 12),
      short("HP " .. tostring(hp), 12),
      short("ATK " .. tostring(atk), 12),
      short("XP " .. tostring(xp), 12),
    },
  }
end

local function build_main_rows(pid, info)
  local rows = {}

  if not info then
    rows[#rows + 1] = row("__lpets:select", "Select Pet")
    return rows
  end

  local free = safe_number(info.available_skill_points, 0)
  local bugfrags = get_bugfrags(pid)

  if info.summoned == true then
    rows[#rows + 1] = row("__lpets:callback", "Unsummon")
  else
    rows[#rows + 1] = row("__lpets:summon", "Summon")
  end

  rows[#rows + 1] = row("__lpets:xp", "Pet Stats", free > 0 and "NEW" or nil)

  if info.can_fight == false then
    rows[#rows + 1] = info_row("__lpets:nofight", "Cannot Battle")
  else
    local chip = info.pet_chip_id and chip_name(info.pet_chip_id) or "None"
    rows[#rows + 1] = row("__lpets:chip", "Pet Chip", short(chip, 6))
  end

  if tostring(info.mood or ""):lower() ~= "happy" then
    rows[#rows + 1] = row("__lpets:feed", "Feed BugFrag", tostring(bugfrags))
  end

  rows[#rows + 1] = row("__lpets:change", "Change Pet")

  if tostring(info.bucket_area_id or "") ~= "" then
    rows[#rows + 1] = row("__lpets:unarm", "Return to HP")
  else
    rows[#rows + 1] = row("__lpets:unarm", "Unselect Pet")
  end

  rows[#rows + 1] = row("__lpets:back", "Back")

  return rows
end

local function show_action_message(pid, text)
  message(pid, text)
end

-- Forward declarations for menu functions.
local open_companion_picker
local open_pet_chip_picker
local open_pet_xp_board
local open_confirm

-- ---------------------------------------------------------------------------
-- Public main menu
-- ---------------------------------------------------------------------------

function LPets.open_pets_board(pid, opts)
  opts = menu_opts(opts)

  local M = get_menuapi()
  if not (M and type(M.open) == "function") then
    message(pid, "Pet menu isn't available.")
    return false
  end

  if not Pets then
    message(pid, "Pet system isn't available.")
    return false
  end

  local info = get_armed_info(pid)
  local rows = build_main_rows(pid, info)

  local remembered = LAST_MAIN_ROW_ID_BY_PID[pid]
  local cursor = row_index_for_id(rows, remembered)
  if not cursor then
    cursor = row_index_for_id(rows, first_selectable_row_id(rows))
  end

  local spec = apply_sp_gauge_spec({
    type = 6,
    z = 220,
    title = "Pets",
    color = "green",

    open_sfx = opts.open_sfx,
    cancel_sfx = opts.cancel_sfx,

    bg_tint = { r = 135, g = 205, b = 150, color_mode = 2 },
    title_tint = { r = 25, g = 95, b = 55, color_mode = 2 },
    row_tint = { r = 50, g = 100, b = 65, color_mode = 2 },
    right_tint = { r = 35, g = 135, b = 80, color_mode = 2 },

    parent = opts.parent,
    lock_input = opts.lock_input,

    profile = build_profile(pid, info),
    rows = rows,
    cursor = cursor,

    on_confirm = function(player_id, selected_row, st)
      if not selected_row or not selected_row.id then return true end
      LAST_MAIN_ROW_ID_BY_PID[player_id] = selected_row.id

      local id = selected_row.id
      local fresh = get_armed_info(player_id)

      if id == "__lpets:back" then
        close_current_keep_frozen(player_id, "lpets_back")
        local parent = opts.parent
        if parent == "lmenu" then
          local LMenu = rawget(_G, "LMenu")
          if LMenu and type(LMenu.open) == "function" then
            pcall(LMenu.open, player_id)
          end
        elseif type(parent) == "function" then
          pcall(parent, player_id)
        end
        return true
      end

      if id == "__lpets:select" then
        return open_companion_picker(player_id, false, opts)
      end

      if id == "__lpets:change" then
        return open_companion_picker(player_id, true, opts)
      end

      if not fresh then
        play_error(player_id)
        show_action_message(player_id, "No companion pet selected.")
        refresh_main_later(player_id, opts)
        return true
      end

      if id == "__lpets:summon" then
        if not (Pets and type(Pets.summon_companion) == "function") then
          show_action_message(player_id, "Pet summon isn't available.")
          return true
        end

        local ok_call, success, msg = pcall(Pets.summon_companion, player_id)
        if not ok_call then
          warn("Pets.summon_companion failed:", tostring(success))
          success, msg = false, "Couldn't summon that companion pet."
        end

        if not success then play_error(player_id) end
        show_action_message(player_id, msg or (success and "Companion pet summoned." or "Couldn't summon that companion pet."))
        refresh_main_later(player_id, opts)
        return true
      end

      if id == "__lpets:callback" then
        if not (Pets and type(Pets.call_back_companion) == "function") then
          show_action_message(player_id, "Pet call back isn't available.")
          return true
        end

        local ok_call, success, msg = pcall(Pets.call_back_companion, player_id)
        if not ok_call then
          warn("Pets.call_back_companion failed:", tostring(success))
          success, msg = false, "Couldn't call back that companion pet."
        end

        if not success then play_error(player_id) end
        show_action_message(player_id, msg or (success and "Companion pet called back." or "Couldn't call back that companion pet."))
        refresh_main_later(player_id, opts)
        return true
      end

      if id == "__lpets:xp" then
        return open_pet_xp_board(player_id, fresh, opts)
      end

      if id == "__lpets:chip" then
        return open_pet_chip_picker(player_id, fresh, opts)
      end

      if id == "__lpets:feed" then
        return open_confirm(player_id, opts, {
          title = "Feed Pet",
          lines = {
            "Use 1 BugFrag?",
            short(fresh.display_name or "Pet", 20),
          },
          yes = function(confirm_pid)
            if not (Pets and type(Pets.feed_armed_pet) == "function") then
              return false, "Pet feeding isn't available."
            end
            return Pets.feed_armed_pet(confirm_pid)
          end,
        })
      end

      if id == "__lpets:unarm" then
        local label = (tostring(fresh.bucket_area_id or "") ~= "") and "Return to HP?" or "Unselect pet?"
        return open_confirm(player_id, opts, {
          title = "Pet",
          lines = {
            label,
            short(fresh.display_name or "Pet", 20),
          },
          yes = function(confirm_pid)
            if not (Pets and type(Pets.unarm_pet) == "function") then
              return false, "Pet unselect isn't available."
            end
            return Pets.unarm_pet(confirm_pid)
          end,
        })
      end

      return true
    end,

    on_close = function(player_id, st)
      remember_row(player_id, st, LAST_MAIN_ROW_ID_BY_PID)
      OPEN_PET_MENUS[player_id] = nil
    end,
  }, info)

  local ok = M.open(pid, spec)

  if ok then
    OPEN_PET_MENUS[pid] = true
  end

  return ok
end

-- ---------------------------------------------------------------------------
-- Companion picker
-- ---------------------------------------------------------------------------

local function build_candidate_label(p, seen, totals)
  local base = tostring(p.display_name or p.base_name or "Pet")
  local suffix = ""

  if (totals[base] or 0) > 1 then
    seen[base] = (seen[base] or 0) + 1
    suffix = suffix .. " No." .. tostring(seen[base])
  end

  local max_base = 20 - #suffix
  if max_base < 1 then max_base = 1 end

  return short(base, max_base) .. suffix
end

local function build_companion_rows(pid)
  local rows = {}
  local candidates = {}

  if Pets and type(Pets.list_companion_candidates) == "function" then
    local ok, result = pcall(Pets.list_companion_candidates, pid)
    if ok and type(result) == "table" then
      candidates = result
    else
      warn("Pets.list_companion_candidates failed:", tostring(result))
    end
  end

  rows[#rows + 1] = info_row("__lpets:pick_header", "Your Pets")

  if #candidates == 0 then
    rows[#rows + 1] = info_row("__lpets:none_ready", "No pets ready")
  else
    local totals = {}
    local seen = {}

    for _, p in ipairs(candidates) do
      local base = tostring(p.display_name or p.base_name or "Pet")
      totals[base] = (totals[base] or 0) + 1
    end

    for _, p in ipairs(candidates) do
      local uid = tostring(p.uid or "")
      if uid ~= "" then
        rows[#rows + 1] = row("__lpets:pet:" .. uid, build_candidate_label(p, seen, totals), p.placed and "HP" or nil, {
          data = p,
        })
      end
    end
  end

  if Pets and type(Pets.get_expedition_pet_info) == "function" then
    local ok, exp_info = pcall(Pets.get_expedition_pet_info, pid)
    if ok and type(exp_info) == "table" then
      rows[#rows + 1] = info_row("__lpets:exp_header", "On Expedition")
      rows[#rows + 1] = info_row("__lpets:exp_pet", short(exp_info.display_name or "Pet", 14), minutes_label(exp_info.secs_left))
    end
  end

  if Pets and type(Pets.get_training_pet_info) == "function" then
    local ok, train_info = pcall(Pets.get_training_pet_info, pid)
    if ok and type(train_info) == "table" then
      rows[#rows + 1] = info_row("__lpets:train_header", "Training")
      rows[#rows + 1] = info_row("__lpets:train_pet", short(train_info.display_name or "Pet", 14), minutes_label(train_info.secs_left))
    end
  end

  rows[#rows + 1] = row("__lpets:back", "Back")

  return rows
end

local function build_picker_profile(pid, selected_row)
  if selected_row and type(selected_row.data) == "table" then
    return build_profile(pid, selected_row.data)
  end

  return {
    title = "Select Pet",
    title_max_ch = 20,
    title_font = "THICK",
    title_scale = 1.05,
    font = "THICK",
    text_scale = 1.4,
    text_y = 15,
    text_max_ch = 12,
    lines = {
      "Choose",
      "A Pet",
    },
  }
end

open_companion_picker = function(pid, allow_replace, opts)
  opts = menu_opts(opts)

  local M = get_menuapi()
  if not (M and type(M.open) == "function") then
    message(pid, "Pet menu isn't available.")
    return false
  end

  local rows = build_companion_rows(pid)
  local cursor = row_index_for_id(rows, LAST_PICKER_ROW_ID_BY_PID[pid]) or row_index_for_id(rows, first_selectable_row_id(rows))

  return M.open(pid, apply_sp_gauge_spec({
    type = 6,
    z = 220,
    title = "Select Pet",
    color = "green",
    open_sfx = false,
    cancel_sfx = opts.cancel_sfx,
    parent = main_parent(opts),
    lock_input = opts.lock_input,

    profile = build_picker_profile(pid, rows[cursor]),
    rows = rows,
    cursor = cursor,

    bg_tint = { r = 135, g = 205, b = 150, color_mode = 2 },
    title_tint = { r = 25, g = 95, b = 55, color_mode = 2 },
    row_tint = { r = 50, g = 100, b = 65, color_mode = 2 },
    right_tint = { r = 230, g = 190, b = 60, color_mode = 2 },

    on_cursor_change = function(player_id, selected_row, st)
      if selected_row and selected_row.id then
        LAST_PICKER_ROW_ID_BY_PID[player_id] = selected_row.id
      end

      local profile = build_picker_profile(player_id, selected_row)

      if M and type(M.set_profile) == "function" then
        M.set_profile(player_id, profile)

        if M and type(M.set_sp_gauge) == "function" then
          local data = selected_row and selected_row.data or nil
          if type(data) == "table" then
            M.set_sp_gauge(player_id, {
              xp = safe_number(data.xp, 0),
              xp_per_point = math.max(1, safe_number(data.xp_per_skill_point, 175)),
              available_points = safe_number(data.available_skill_points, 0),
            })
          else
            M.set_sp_gauge(player_id, {
              state = "sp_01",
              available_points = 0,
            })
          end
        end

      else
        st.profile = profile
        if M and type(M.refresh) == "function" then
          M.refresh(player_id)
        end
      end

      return true
    end,

    on_confirm = function(player_id, selected_row, st)
      if not selected_row or not selected_row.id then return true end
      LAST_PICKER_ROW_ID_BY_PID[player_id] = selected_row.id

      if selected_row.id == "__lpets:back" then
        return LPets.open_pets_board(player_id, opts)
      end

      local uid = tostring(selected_row.id):match("^__lpets:pet:(.+)$")
      if not uid or uid == "" then return true end

      if not (Pets and type(Pets.arm_owned_pet) == "function") then
        play_error(player_id)
        message(player_id, "Pet companion selection isn't available.")
        return true
      end

      local ok_call, success, msg = pcall(Pets.arm_owned_pet, player_id, uid, allow_replace == true)
      if not ok_call then
        warn("Pets.arm_owned_pet failed:", tostring(success))
        success, msg = false, "Couldn't select that companion pet."
      end

      if not success then play_error(player_id) end
      message(player_id, msg or (success and "Companion pet selected." or "Couldn't select that companion pet."))
      return LPets.open_pets_board(player_id, opts)
    end,

    on_close = function(player_id, st)
      remember_row(player_id, st, LAST_PICKER_ROW_ID_BY_PID)
    end,
  }, rows[cursor] and rows[cursor].data))
end

-- ---------------------------------------------------------------------------
-- Chip picker
-- ---------------------------------------------------------------------------

local function build_chip_rows(pid, info)
  local rows = {}
  local chips = {}

  -- Removed the old "Pet Chips" info row.
  -- The menu title already says "Pet Chip".

  if info and info.pet_chip_id then
    rows[#rows + 1] = row("__lpets:chip_unequip", "Unequip")
  end

  if Pets and type(Pets.list_player_pet_chip_inventory) == "function" then
    local ok, result = pcall(Pets.list_player_pet_chip_inventory, pid)
    if ok and type(result) == "table" then
      chips = result
    else
      warn("Pets.list_player_pet_chip_inventory failed:", tostring(result))
    end
  end

  if #chips == 0 then
    rows[#rows + 1] = info_row("__lpets:nochips", "No pet chips")
  else
    for _, chip in ipairs(chips) do
      local chip_id = tonumber(chip.chip_id)
      if chip_id then
        local name = tostring(chip.name or chip_name(chip_id) or "Chip")
        local qty = math.max(1, safe_number(chip.qty, 1))

        rows[#rows + 1] = row("__lpets:chip:" .. tostring(chip_id), short(name, 16), "x" .. tostring(qty), {
          data = chip,
        })
      end
    end
  end

  rows[#rows + 1] = row("__lpets:back", "Back")
  return rows
end

open_pet_chip_picker = function(pid, info, opts)
  opts = menu_opts(opts)

  if not info or tostring(info.uid or "") == "" then
    message(pid, "No companion pet selected.")
    return LPets.open_pets_board(pid, opts)
  end

  local M = get_menuapi()
  if not (M and type(M.open) == "function") then
    message(pid, "Pet menu isn't available.")
    return false
  end

  local rows = build_chip_rows(pid, info)
  local cursor = row_index_for_id(rows, LAST_CHIP_ROW_ID_BY_PID[pid]) or row_index_for_id(rows, first_selectable_row_id(rows))

  return M.open(pid, {
    type = 5,
    z = 220,
    title = "Pet Chip",
    color = "green",
    open_sfx = false,
    cancel_sfx = opts.cancel_sfx,
    parent = main_parent(opts),
    lock_input = opts.lock_input,

    profile = build_chip_profile(pid, rows[cursor]),
    rows = rows,
    cursor = cursor,

    bg_tint = { r = 135, g = 205, b = 150, color_mode = 2 },
    title_tint = { r = 25, g = 95, b = 55, color_mode = 2 },
    row_tint = { r = 50, g = 100, b = 65, color_mode = 2 },
    right_tint = { r = 35, g = 135, b = 80, color_mode = 2 },

    on_cursor_change = function(player_id, selected_row, st)
      if selected_row and selected_row.id then
        LAST_CHIP_ROW_ID_BY_PID[player_id] = selected_row.id
      end

      local profile = build_chip_profile(player_id, selected_row)

      if M and type(M.set_profile) == "function" then
        M.set_profile(player_id, profile)
      else
        st.profile = profile
        if M and type(M.refresh) == "function" then
          M.refresh(player_id)
        end
      end

      return true
    end,

    on_confirm = function(player_id, selected_row, st)
      if not selected_row or not selected_row.id then return true end
      LAST_CHIP_ROW_ID_BY_PID[player_id] = selected_row.id

      if selected_row.id == "__lpets:back" then
        return LPets.open_pets_board(player_id, opts)
      end

      local ok_call, success, msg

      if selected_row.id == "__lpets:chip_unequip" then
        if not (Pets and type(Pets.unequip_chip_from_pet) == "function") then
          play_error(player_id)
          message(player_id, "Pet chip unequip isn't available.")
          return true
        end

        ok_call, success, msg = pcall(Pets.unequip_chip_from_pet, player_id, info.uid)
        if not ok_call then
          warn("Pets.unequip_chip_from_pet failed:", tostring(success))
          success, msg = false, "Couldn't unequip that pet chip."
        end
      else
        local chip_id = tonumber(tostring(selected_row.id):match("^__lpets:chip:(%d+)$"))
        if not chip_id then return true end

        if not (Pets and type(Pets.equip_chip_on_pet) == "function") then
          play_error(player_id)
          message(player_id, "Pet chip equip isn't available.")
          return true
        end

        ok_call, success, msg = pcall(Pets.equip_chip_on_pet, player_id, info.uid, chip_id)
        if not ok_call then
          warn("Pets.equip_chip_on_pet failed:", tostring(success))
          success, msg = false, "Couldn't equip that pet chip."
        end
      end

      if not success then play_error(player_id) end
      message(player_id, msg or (success and "Pet chip updated." or "Couldn't update that pet chip."))
      return LPets.open_pets_board(player_id, opts)
    end,

    on_close = function(player_id, st)
      remember_row(player_id, st, LAST_CHIP_ROW_ID_BY_PID)
    end,
  })
end

-- ---------------------------------------------------------------------------
-- XP menu
-- ---------------------------------------------------------------------------

local function build_xp_rows(info)
  local rows = {}

  if not info then
    rows[#rows + 1] = info_row("__lpets:no_pet", "No pet selected")
    rows[#rows + 1] = row("__lpets:back", "Back")
    return rows
  end

  local free = safe_number(info.available_skill_points, 0)
  local total = safe_number(info.total_skill_points, 0)
  local next_xp = safe_number(info.xp_to_next_skill_point, 0)
  local notify_on = info.xp_notifications_enabled ~= false

  rows[#rows + 1] = info_row("__lpets:xp_next", "Next Point", tostring(next_xp))
  rows[#rows + 1] = info_row("__lpets:xp_points", "Skill Points", tostring(free) .. "/" .. tostring(total))
  rows[#rows + 1] = row("__lpets:xp_toggle", "Notify", notify_on and "ON" or "OFF")
  rows[#rows + 1] = row("__lpets:show_id", "Show PET ID")

  if info.can_fight == false then
    rows[#rows + 1] = info_row("__lpets:nofight", "No battle stats")
  else
    rows[#rows + 1] = row("__lpets:xp_hp", "Increase HP", "+5", {
      selectable = free > 0,
      enabled = free > 0,
    })

    rows[#rows + 1] = row("__lpets:xp_attack", "Increase ATK", "+5", {
      selectable = free > 0,
      enabled = free > 0,
    })
  end

  rows[#rows + 1] = row("__lpets:back", "Back")

  return rows
end

open_pet_xp_board = function(pid, info, opts)
  opts = menu_opts(opts)

  local fresh = get_armed_info(pid) or info
  local M = get_menuapi()
  if not (M and type(M.open) == "function") then
    message(pid, "Pet menu isn't available.")
    return false
  end

  local rows = build_xp_rows(fresh)
  local cursor = row_index_for_id(rows, LAST_XP_ROW_ID_BY_PID[pid]) or row_index_for_id(rows, first_selectable_row_id(rows))

  return M.open(pid, apply_sp_gauge_spec({
    type = 6,
    z = 220,
    title = "Pet Stats",
    color = "green",
    open_sfx = false,
    cancel_sfx = opts.cancel_sfx,
    parent = main_parent(opts),
    lock_input = opts.lock_input,
  
    profile = build_profile(pid, fresh),
    rows = rows,
    cursor = cursor,

    bg_tint = { r = 135, g = 205, b = 150, color_mode = 2 },
    title_tint = { r = 25, g = 95, b = 55, color_mode = 2 },
    row_tint = { r = 50, g = 100, b = 65, color_mode = 2 },
    right_tint = { r = 35, g = 135, b = 80, color_mode = 2 },

    on_confirm = function(player_id, selected_row, st)
      if not selected_row or not selected_row.id then return true end
      LAST_XP_ROW_ID_BY_PID[player_id] = selected_row.id

      local id = selected_row.id
      local current = get_armed_info(player_id)

      if id == "__lpets:back" then
        return LPets.open_pets_board(player_id, opts)
      end

      if not current then
        play_error(player_id)
        message(player_id, "No companion pet selected.")
        return LPets.open_pets_board(player_id, opts)
      end

      if id == "__lpets:xp_toggle" then
        if Pets and type(Pets.set_pet_xp_notifications_enabled) == "function" then
          local now_on = current.xp_notifications_enabled ~= false
          local ok_call, success, enabled = pcall(Pets.set_pet_xp_notifications_enabled, player_id, not now_on)

          if not ok_call or success == false then
            play_error(player_id)
            message(player_id, "Couldn't update XP notifications.")
            return true
          end

          local updated = get_armed_info(player_id) or current

          if M and type(M.set_rows) == "function" then
            M.set_rows(player_id, build_xp_rows(updated), {
              keep_cursor = true,
            })
          end

          if enabled == true then
            message(player_id, "XP notifications ON. You will receive info when your pet gains XP.")
          else
            message(player_id, "XP notifications OFF. You will stop receiving info when your pet gains XP.")
          end

          return true
        end

        play_error(player_id)
        message(player_id, "XP notification settings aren't available.")
        return true
      end

      if id == "__lpets:show_id" then
        local pet_id = tostring(current.uid or "")

        if pet_id == "" then
          play_error(player_id)
          message(player_id, "This pet has no PET ID.")
        else
          message(player_id, "PET ID: " .. pet_id)
        end

        return true
      end

      if id == "__lpets:xp_hp" then
        return open_confirm(player_id, opts, {
          title = "Pet Stats",
          parent = function(cancel_pid)
            open_pet_xp_board(cancel_pid, get_armed_info(cancel_pid), opts)
          end,
          lines = {
            "Spend 1 point?",
            "HP " .. tostring(safe_number(current.hp, 40)) .. " to " .. tostring(safe_number(current.hp, 40) + 5),
          },
          yes = function(confirm_pid)
            if not (Pets and type(Pets.invest_armed_pet_stat) == "function") then
              return false, "Pet stat upgrade isn't available."
            end
            return Pets.invest_armed_pet_stat(confirm_pid, "hp")
          end,
          after = function(after_pid)
            open_pet_xp_board(after_pid, get_armed_info(after_pid), opts)
          end,
          after_no = function(after_pid)
            open_pet_xp_board(after_pid, get_armed_info(after_pid), opts)
          end,
        })
      end

      if id == "__lpets:xp_attack" then
        return open_confirm(player_id, opts, {
          title = "Pet Stats",
          parent = function(cancel_pid)
            open_pet_xp_board(cancel_pid, get_armed_info(cancel_pid), opts)
          end,
          lines = {
            "Spend 1 point?",
            "ATK " .. tostring(safe_number(current.attack, 5)) .. " to " .. tostring(safe_number(current.attack, 5) + 5),
          },
          yes = function(confirm_pid)
            if not (Pets and type(Pets.invest_armed_pet_stat) == "function") then
              return false, "Pet stat upgrade isn't available."
            end
            return Pets.invest_armed_pet_stat(confirm_pid, "attack")
          end,
          after = function(after_pid)
            open_pet_xp_board(after_pid, get_armed_info(after_pid), opts)
          end,
          after_no = function(after_pid)
            open_pet_xp_board(after_pid, get_armed_info(after_pid), opts)
          end,
        })
      end

      return true
    end,

    on_close = function(player_id, st)
      remember_row(player_id, st, LAST_XP_ROW_ID_BY_PID)
    end,
  }, fresh))
end

-- ---------------------------------------------------------------------------
-- Confirm helper
-- ---------------------------------------------------------------------------

open_confirm = function(pid, opts, spec)
  opts = menu_opts(opts)
  spec = spec or {}

  local M = get_menuapi()
  if not (M and type(M.open) == "function") then
    return false
  end

  return M.open(pid, {
    type = 4,
    z = 220,
    title = spec.title or "Confirm",
    color = "green",
    open_sfx = false,
    cancel_sfx = opts.cancel_sfx,
    parent = spec.parent or main_parent(opts),
    lock_input = opts.lock_input,
    lines = spec.lines or {},
    default_choice = spec.default_choice or "no",

    bg_tint = { r = 135, g = 205, b = 150, color_mode = 2 },
    title_tint = { r = 25, g = 95, b = 55, color_mode = 2 },
    row_tint = { r = 50, g = 100, b = 65, color_mode = 2 },
    right_tint = { r = 35, g = 135, b = 80, color_mode = 2 },

    on_confirm = function(player_id, selected_row)
      local choice = selected_row and selected_row.choice or "no"

      if choice ~= "yes" then
        if type(spec.after_no) == "function" then
          spec.after_no(player_id)
        else
          LPets.open_pets_board(player_id, opts)
        end
        return true
      end

      local success, msg = false, nil
      if type(spec.yes) == "function" then
        local ok_call, a, b = pcall(spec.yes, player_id)
        if ok_call then
          success, msg = a, b
        else
          warn("confirm yes failed:", tostring(a))
          success, msg = false, "Couldn't complete that pet action."
        end
      end

      if not success then
        play_error(player_id)

        if msg and msg ~= "" then
          message(player_id, msg, {
            on_close = function(close_pid)
              if type(spec.after) == "function" then
                spec.after(close_pid, success, msg)
              else
                LPets.open_pets_board(close_pid, opts)
              end
            end,
          })

          return true
        end
      end

      if msg and msg ~= "" then
        message(player_id, msg)
      end

      if type(spec.after) == "function" then
        spec.after(player_id, success, msg)
      else
        LPets.open_pets_board(player_id, opts)
      end

      return true
    end,
  })
end

function LPets.show_sp_gauge_gain(pid, data)
  data = data or {}

  local M = get_menuapi()
  if not (M and type(M.open) == "function") then
    return false
  end

  local old_xp = safe_number(data.old_xp, 0)
  local new_xp = safe_number(data.new_xp, old_xp)

  -- Lifetime XP is used for the text message.
  -- SP bar XP is current-segment progress under the curve.
  local old_bar_xp = safe_number(data.old_spbar_xp or data.spbar_old_xp or data.old_xp, old_xp)
  local new_bar_xp = safe_number(data.new_spbar_xp or data.spbar_new_xp or data.new_xp, new_xp)

  local new_per = math.max(1, safe_number(
    data.new_spbar_xp_per_point
    or data.spbar_xp_per_point
    or data.xp_per_skill_point,
    175
  ))

  local old_per = math.max(1, safe_number(
    data.old_spbar_xp_per_point
    or data.spbar_old_xp_per_point
    or data.old_xp_per_skill_point,
    new_per
  ))

  local per = new_per
  local available = safe_number(data.available_skill_points, 0)
  local gained = safe_number(data.skill_points_gained, 0)
  local xp_gained = math.max(0, new_xp - old_xp)

  local start_points = math.max(0, available - gained)
  local already_started = false

  local function close_popup_now()
    local MenuAPI = get_menuapi()
    if MenuAPI and type(MenuAPI.close) == "function" then
      MenuAPI.close(pid, {
        keep_frozen = false,
        reason = "sp_gauge_done",
      })
    end
  end

  local function start_animation()
    if already_started then
      return
    end

    already_started = true

    local MenuAPI = get_menuapi()
    if not MenuAPI then
      return
    end

    local delay = 0.025
    local start_points_for_bar = start_points

    local function set_bar(xp, xp_per_point, points)
      if type(MenuAPI.set_sp_gauge) == "function" then
        MenuAPI.set_sp_gauge(pid, {
          xp = xp,
          xp_per_point = xp_per_point,
          available_points = points,
        })
      end
    end

    if not (type(async) == "function" and Async and Async.sleep) then
      set_bar(new_bar_xp, new_per, available)
      close_popup_now()
      return
    end

    async(function()
      local function wait(seconds)
        await(Async.sleep(math.max(0, tonumber(seconds) or 0)))
      end

      local function phase_wait(from_xp, to_xp, xp_per_point)
        from_xp = math.max(0, tonumber(from_xp) or 0)
        to_xp = math.max(from_xp, tonumber(to_xp) or from_xp)
        xp_per_point = math.max(1, tonumber(xp_per_point) or 1)

        local pct = math.max(0, math.min(1, (to_xp - from_xp) / xp_per_point))
        local frames = math.max(2, math.ceil(55 * pct))

        return frames * delay + 0.08
      end

      local function animate_phase(from_xp, to_xp, xp_per_point, points)
        from_xp = math.max(0, math.floor(tonumber(from_xp) or 0))
        to_xp = math.max(from_xp, math.floor(tonumber(to_xp) or from_xp))
        xp_per_point = math.max(1, math.floor(tonumber(xp_per_point) or 1))

        if type(MenuAPI.animate_sp_gauge) == "function" and to_xp > from_xp then
          MenuAPI.animate_sp_gauge(pid, {
            from_xp = from_xp,
            to_xp = to_xp,
            xp_per_point = xp_per_point,
            available_points = points,
            skill_points_gained = 0,
            delay = delay,
          })

          wait(phase_wait(from_xp, to_xp, xp_per_point))
        else
          set_bar(to_xp, xp_per_point, points)
          wait(delay * 2)
        end
      end

      if gained > 0 then
        local points_now = start_points_for_bar

        -- Phase 1: fill the old curved segment to full.
        animate_phase(old_bar_xp, old_per, old_per, points_now)

        -- Phase 2: reset once per gained SP.
        for i = 1, gained do
          points_now = math.min(available, points_now + 1)

          set_bar(0, new_per, points_now)
          wait(delay * 4)

          -- If multiple SP were gained, show full intermediate fills.
          if i < gained then
            animate_phase(0, new_per, new_per, points_now)
            set_bar(0, new_per, points_now)
            wait(delay * 4)
          end
        end

        -- Phase 3: fill the new segment progress after the reset.
        if new_bar_xp > 0 then
          animate_phase(0, new_bar_xp, new_per, available)
        else
          set_bar(0, new_per, available)
        end
      else
        -- Normal same-segment gain.
        animate_phase(old_bar_xp, new_bar_xp, new_per, available)
      end

      wait(0.75)
      close_popup_now()
    end)
  end

  local ok = M.open(pid, {
    type = 7,
    z = 230,
    title = "",
    color = "green",
    open_sfx = false,
    cancel_sfx = false,
    lock_input = true,

    profile = build_profile(pid, get_armed_info(pid)),

    spbar_xp = old_bar_xp,
    spbar_xp_per_point = old_per,
    spbar_available_points = start_points,

    bg_tint = { r = 135, g = 205, b = 150, color_mode = 2 },
  })

  if not ok then
    return false
  end

  local msg = "Your pet gained " .. tostring(xp_gained) .. " XP."

  if gained > 0 then
    msg = msg .. " Skill Gauge full. " .. tostring(available) .. " SP available."
  end

  if type(M.show_message) == "function" then
    local shown = M.show_message(pid, msg, {
      box_id = "lpets_sp_gain",
      speed = 80,
      z = 300,

      -- Important:
      -- Confirm advances/closes the message first.
      -- The animation starts only after the message is closed.
      on_close = start_animation,
    })

    if shown then
      return true
    end
  end

  -- Fallback if MenuAPI textbox is unavailable.
  if Net and Net.message_player then
    pcall(Net.message_player, pid, msg)
  end

  start_animation()
  return true
end

return LPets
