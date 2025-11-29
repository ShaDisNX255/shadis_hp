-- /server/scripts/flavor_text.lua
-- Flavor text handler + optional cosmetic giveaways via Tiled custom properties.
--
-- Per-object custom properties in Tiled:
--   Flavor          (string)  - base flavor text shown on every interaction
--   CosmeticID      (string)  - cosmetic id from cosmetic-config/config.lua
--   CosmeticExtra   (string)  - extra line when the cosmetic is newly found
--   CosmeticGotText (string)  - custom "you got" line; %NAME% -> cosmetic name
--
-- Behavior:
--   - If only Flavor is set: show Flavor on every interaction (original behavior).
--   - If CosmeticID is also set:
--       * If player does NOT have that cosmetic:
--           - show Flavor (if set)
--           - show CosmeticExtra (if set)
--           - wait until the *last* of those textboxes is closed
--           - then play ITEM_GOT_SFX and show CosmeticGotText
--       * If player already has the cosmetic:
--           - only show Flavor (no SFX)
--
-- This uses the same pattern as fishing.lua:
--   - We queue a pending action in _PENDING_COSMETIC[pid]
--   - We listen to Net:on("textbox_response", ...) and count down
--     how many textboxes we expect to be closed before firing the
--     "You got..." popup + sound.

---------------------------
-- Tileset fallback texts
---------------------------

local flavorTextMap = {
  ["/server/assets/tiles/coffee.tsx"] = "A cafe sign.\nYou feel welcomed.",
  ["/server/assets/tiles/gate.tsx"]   = "The gate needs a key to get through.",
}

-- Same memory key used by cosmetics.lua
local COSMETIC_MEM_KEY = "cosmetics_unlocked_v1"

-- Direct ezmemory access (mirrors cosmetics.lua)
local ezmemory = require("scripts/ezlibs-scripts/ezmemory")

-- helpers is optional; we only use it for get_safe_player_secret if present.
local helpers_ok, helpers = pcall(require, "scripts/ezlibs-scripts/helpers")

---------------------------
-- Logging / small helpers
---------------------------

local function ft_log(msg)
  print("[FlavorText] " .. tostring(msg))
end

local function safe_message(player_id, msg)
  if msg and msg ~= "" then
    Net.message_player(player_id, msg)
  end
end

local ITEM_GOT_SFX = "/server/assets/ezlibs-assets/sfx/item_get.ogg"

local function play_item_get_sfx(player_id)
  if Net.play_sound_for_player then
    Net.play_sound_for_player(player_id, ITEM_GOT_SFX)
  elseif Net.play_sound then
    Net.play_sound(player_id, ITEM_GOT_SFX)
  end
end

local function is_memory_loading_error(errmsg)
  if not errmsg then return false end
  return tostring(errmsg):match("still loading area_memory") ~= nil
end

local function get_secret_for_pid(pid)
  if helpers_ok and helpers and type(helpers.get_safe_player_secret) == "function" then
    return helpers.get_safe_player_secret(pid)
  end
  return pid
end

------------------------------
-- Direct ezmemory cosmetics
------------------------------

local function ft_cosmetic_pmem_get(pid)
  if not (ezmemory and ezmemory.get_player_memory) then
    return nil, nil, "no_ezmemory"
  end

  local secret = get_secret_for_pid(pid)

  local ok, pmem_or_err = pcall(ezmemory.get_player_memory, secret)
  if not ok then
    local msg = tostring(pmem_or_err)
    if is_memory_loading_error(msg) then
      ft_log("ezmemory is still loading area_memory; skipping cosmetic check for now.")
      return nil, nil, "memory_loading"
    end
    ft_log("ERROR in ezmemory.get_player_memory: " .. msg)
    return nil, nil, "error"
  end

  local pmem = pmem_or_err or {}
  if type(pmem[COSMETIC_MEM_KEY]) ~= "table" then
    pmem[COSMETIC_MEM_KEY] = {}
    if ezmemory.set_player_memory then
      pcall(ezmemory.set_player_memory, secret, pmem)
    elseif ezmemory.save_player_memory then
      pcall(ezmemory.save_player_memory, secret, pmem)
    end
  end

  return pmem, secret, nil
end

local function ft_has_cosmetic(pid, cosmetic_id)
  if not cosmetic_id or cosmetic_id == "" then
    return false, "invalid_id"
  end

  local pmem, _, err = ft_cosmetic_pmem_get(pid)
  if not pmem then
    return false, err
  end

  local bag = pmem[COSMETIC_MEM_KEY]
  return bag and bag[cosmetic_id] == true, nil
end

local function ft_unlock_cosmetic(pid, cosmetic_id)
  if not cosmetic_id or cosmetic_id == "" then
    return false, "invalid_id"
  end

  local pmem, secret, err = ft_cosmetic_pmem_get(pid)
  if not pmem then
    return false, err
  end

  local bag = pmem[COSMETIC_MEM_KEY]
  if bag[cosmetic_id] then
    return false, "already_owned"
  end

  bag[cosmetic_id] = true

  if ezmemory.set_player_memory then
    local ok, perr = pcall(ezmemory.set_player_memory, secret, pmem)
    if not ok then
      ft_log("ERROR in ezmemory.set_player_memory: " .. tostring(perr))
      return false, "error"
    end
  elseif ezmemory.save_player_memory then
    local ok, perr = pcall(ezmemory.save_player_memory, secret, pmem)
    if not ok then
      ft_log("ERROR in ezmemory.save_player_memory: " .. tostring(perr))
      return false, "error"
    end
  end

  return true, nil
end

------------------------------------------------
-- Pending cosmetic announcement (post-message)
------------------------------------------------

-- When a player picks up a cosmetic, we:
--   1) Show Flavor (if any)
--   2) Show CosmeticExtra (if any)
--   3) THEN, after the *last* of those closes, we show CosmeticGotText
--      and play the item_get SFX.
--
-- To do that, we queue this table and consume it in a textbox_response
-- handler (same trick as fishing.lua).

local _PENDING_COSMETIC = {}  -- pid -> { remaining = N, got_text = string }

local function _queue_cosmetic_after_messages(pid, num_messages, got_text)
  if num_messages <= 0 then
    -- Nothing to wait for; just show the got text immediately.
    safe_message(pid, got_text)
    play_item_get_sfx(pid)
    return
  end

  _PENDING_COSMETIC[pid] = {
    remaining = num_messages,
    got_text  = got_text,
  }
end

-- Listen for the engine event fired whenever a textbox is closed.
-- This is global and works for Net.message_player popups from objects,
-- NPC dialogues, etc.
Net:on("textbox_response", function(a, b)
  local pid
  if type(a) == "table" then
    pid = a.player_id or a[1]
  else
    pid = a
  end
  if not pid then return end

  local pending = _PENDING_COSMETIC[pid]
  if not pending then return end

  if pending.remaining > 1 then
    -- Still have more of *our* messages to drain.
    pending.remaining = pending.remaining - 1
    return
  end

  -- This was the last pre-"got" message; fire the SFX + got text.
  _PENDING_COSMETIC[pid] = nil

  safe_message(pid, pending.got_text)
  play_item_get_sfx(pid)
end)

---------------------------------------------
-- Main interaction entrypoint (engine hook)
---------------------------------------------

function handle_object_interaction(player_id, object_id, button)
  -- Only react to main interact button (A)
  if button ~= 0 then return end

  local area_id = Net.get_player_area(player_id)
  if not area_id then return end

  local object = Net.get_object_by_id(area_id, object_id)
  if not object or not object.custom_properties then
    return
  end

  local props = object.custom_properties

  ----------------------------------------------------
  -- 1) Base flavor text (with tileset fallback)
  ----------------------------------------------------
  local flavorText = props.Flavor

  if (not flavorText or flavorText == "") and object.tileset_path then
    flavorText = flavorTextMap[object.tileset_path]
  end

  ----------------------------------------------------
  -- 2) Cosmetic logic (optional)
  ----------------------------------------------------
  local cosmetic_id = props.CosmeticID

  -- Case A: no cosmetic, behave as simple flavor text.
  if not cosmetic_id or cosmetic_id == "" then
    if flavorText and flavorText ~= "" then
      safe_message(player_id, flavorText)
    end
    return
  end

  -- There is a cosmetic ID; check if player already owns it.
  local has, err = ft_has_cosmetic(player_id, cosmetic_id)
  if err == "memory_loading" or err == "no_ezmemory" or err == "error" then
    -- ezmemory not ready / failed; just show flavor and bail.
    if flavorText and flavorText ~= "" then
      safe_message(player_id, flavorText)
    end
    return
  end

  if has then
    -- Already unlocked: only show flavor, no SFX.
    if flavorText and flavorText ~= "" then
      safe_message(player_id, flavorText)
    end
    return
  end

  -- First-time pickup path.
  local extra = props.CosmeticExtra

  -- Unlock cosmetic before we announce it.
  local ok, unlock_err = ft_unlock_cosmetic(player_id, cosmetic_id)
  if not ok and unlock_err ~= "already_owned" then
    ft_log(string.format(
      "Failed to unlock cosmetic '%s' for player %s; reason=%s",
      tostring(cosmetic_id), tostring(player_id), tostring(unlock_err)
    ))
    -- Still show flavor so the object isn't silent.
    if flavorText and flavorText ~= "" then
      safe_message(player_id, flavorText)
    end
    return
  end

  -- Pretty name via Cosmetics module if present.
  local cosmetic_name = cosmetic_id
  local Cosmetics = rawget(_G, "Cosmetics")
  if Cosmetics and type(Cosmetics.get_name_for_id) == "function" then
    local ok_name, name = pcall(Cosmetics.get_name_for_id, cosmetic_id)
    if ok_name and name and name ~= "" then
      cosmetic_name = name
    end
  end

  local got_text = props.CosmeticGotText
  if got_text and got_text ~= "" then
    got_text = got_text:gsub("%%NAME%%", cosmetic_name)
  else
    got_text = ("You got the '%s' cosmetic!"):format(cosmetic_name)
  end

  ----------------------------------------------------
  -- 3) Show flavor / extra now, schedule got_text
  ----------------------------------------------------
  local num_pre_msgs = 0

  if flavorText and flavorText ~= "" then
    safe_message(player_id, flavorText)
    num_pre_msgs = num_pre_msgs + 1
  end

  if extra and extra ~= "" then
    safe_message(player_id, extra)
    num_pre_msgs = num_pre_msgs + 1
  end

  _queue_cosmetic_after_messages(player_id, num_pre_msgs, got_text)
end
