-- scripts/events/eznpcs_onceitem.lua
-- Dialogue Type "onceitem": unique, server-wide rental with renewals
-- Dialogue Type "oncepass": renter sets/clears a visitor password for the HP checkpoint
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
--
-- ====================== Requires (note updated eznpcs path) ======================
local eznpcs   = require('scripts/ezlibs-scripts/eznpcs/eznpcs')
local helpers  = require('scripts/ezlibs-scripts/helpers')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')

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

local function dprop(dialogue, key, default)
  local v = dialogue.custom_properties[key]
  if v == nil or v == "" then return default end
  return v
end

local function cprop(obj_custom, key, default)
  local v = obj_custom[key]
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

-- ====================== Util ======================
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

-- minutes override months if > 0
local function compute_period(now_ts, months, minutes)
  if minutes and minutes > 0 then
    return now_ts, now_ts + minutes * 60
  end
  months = months or 1
  return now_ts, add_months(now_ts, months)
end

local function resolve_manual_purchased_at(dialogue, now_ts)
  local cron_like  = dialogue.custom_properties["Purchased At Date"]
  local epoch_str  = dialogue.custom_properties["Purchased At Epoch"]
  local offset_hrs = tonumber(dialogue.custom_properties["Purchased At Offset Hours"] or "0")

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

-- Remove a player's key item if they are not the current renter or lease expired
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

-- Expose a helper for doors / checks without touching inventory
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
      -- NEW: if player is holding a stale key, clean it up first
      purge_player_key_if_invalid(player_id, BUCKET_AREA_ID, once_key, item_info.name)

      -- lock to prevent double-rent; auto releases after 10s
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

      -- Active lease?
      if record and record.expires_at and record.expires_at > now_ts then
        if record.owner_secret == safe_secret then
          -- Renewal
          local prompt = dprop(dialogue, "Renew Prompt", DEFAULTS.RenewPrompt)
          prompt = prompt:gsub("{date}", fmt(record.expires_at)):gsub("{price}", tostring(renewal_price))
          local wants = (renewal_price <= 0) or ask_yes_no(player_id, prompt, mug)
          if wants then
            if not can_afford(renewal_price) then
              await(say(player_id, dprop(dialogue, "No Money Text", DEFAULTS.NoMoneyText), mug))
              return finish(next_ids[3] or next_ids[2])
            end
            -- NEW: make sure the renter actually has the key in inventory
            await(grant_key_if_missing())
            local base_ts = manual_purchased_at or now_ts
            local start_ts, end_ts = new_window_from(base_ts)
            record.owned_at = start_ts; record.expires_at = end_ts; record.owner_name = player_name
            -- keep existing password across renewals
            save_record(record)
            await(say(player_id, dprop(dialogue, "Renewed Text", DEFAULTS.RenewedText):gsub("{date}", fmt(end_ts)), mug))
            return finish(next_ids[1])
          else
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

      -- Initial rental flow (with confirm)
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
        password     = nil -- never leak old password to new renter
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

      -- NOTE: normalized key to avoid space/case mismatches
      local once_key = normalize_key(dprop(dialogue, "Once Key", ""))
	  local BUCKET_AREA_ID = resolve_mem_area_id(dialogue, player_id, nil)
      if once_key == "" then
        await(say(player_id, "No Once Key on this node.", mug))
        return nil
      end

      local mem, rec = get_record_and_prune(BUCKET_AREA_ID, once_key)
      local now = os.time()

      if not rec or not rec.expires_at or rec.expires_at <= now then
        await(say(player_id, dprop(dialogue, "Not Renter Text", DEFAULTS.NotRenterText) .. " (No active lease.)", mug))
        return nil
      end

      local player_secret = helpers.get_safe_player_secret(player_id)
      local is_owner = (player_secret == rec.owner_secret)

      -- optional debug — remove after verifying
      local dbg = string.format("[oncepass] key=%s you=%s owner=%s expires=%s owner?%s",
        once_key, tostring(player_secret), tostring(rec.owner_secret), tostring(rec.expires_at), tostring(is_owner))
      if printd then printd(dbg) else print(dbg) end

      if not is_owner then
        await(say(player_id, dprop(dialogue, "Not Renter Text", DEFAULTS.NotRenterText) .. " (Not the owner.)", mug))
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

-- ====================== Checkpoint Integration ======================
Net:on("object_interaction", function(event)
  if event.button ~= 0 then return end
  local player_id = event.player_id
  local area_id   = Net.get_player_area(player_id)
  local object_id = event.object_id
  local obj = Net.get_object_by_id(area_id, object_id)
  if not obj or obj.type ~= "Checkpoint" then return end

  local cp = obj.custom_properties or {}
  local once_key = normalize_key(cp["Once Key"])
  if once_key == "" then return end -- only handle bound checkpoints
  local BUCKET_AREA_ID = resolve_mem_area_id(nil, player_id, cp)

  -- Try to take the same lock ezcheckpoints uses.
  local lock_id = player_id.."_"..area_id.."_"..obj.id
  local lock = helpers.get_lock(player_id, lock_id)

  -- Core unlock logic (runs with or without lock)
  local function run_logic(with_lock)
    return async(function ()
      -- Clean up any stale key (optional safety)
      purge_player_key_if_invalid(player_id, BUCKET_AREA_ID, once_key, cp["Key Name"])

      -- Only show description if we own the lock (to avoid double bubbles)
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
          -- Only prompt if we own the lock (avoid duplicate prompts)
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
        local asset_name = cprop(cp, "Unlocking Asset Name", DEFAULTS.CP_UnlockingAssetName)
        local anim_ms    = tonumber(cprop(cp, "Unlocking Animation Time", DEFAULTS.CP_UnlockingAnimationTimeMS)) or 0
        local sound_path = cprop(cp, "Unlocking Sound Path", DEFAULTS.CP_UnlockingSoundPath)

        -- Safe to run even without the shared lock (it’s per-player)
        Net.lock_player_input(player_id)
        Net.play_sound_for_player(player_id, sound_path)

        if anim_ms > 0 and with_lock then
          local o = obj
          local new_bot_props = {
            x=o.x, y=o.y, z=o.z,
            texture_path='/server/assets/ezlibs-assets/ezcheckpoints/'..asset_name..'.png',
            animation_path='/server/assets/ezlibs-assets/ezcheckpoints/'..asset_name..'.animation',
            animation='UNLOCKING', warp_in=false, area_id=area_id
          }
          Net.provide_asset(area_id, new_bot_props.texture_path)
          local bot_id = Net.create_bot(new_bot_props)
          await(Async.sleep(anim_ms))
          Net.remove_bot(bot_id, false)
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
    -- We own the interaction → run normally (with description/prompt/animation)
    return run_logic(true)
  else
    -- ezcheckpoints took the lock first; wait a tick and run fallback without description/prompt
    return async(function ()
      -- small delay so the base handler finishes and releases any UI
      await(Async.sleep(50)) -- ~50ms
      await(run_logic(false))
    end)
  end
end)

return true
