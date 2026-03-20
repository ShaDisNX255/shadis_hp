local helpers = require('scripts/ezlibs-scripts/helpers')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')

local ezemail = {}
-- tweak these
local NEW_MAIL_MESSAGE_DELAY = 1.5        -- seconds: wait after ring before message_player
local ENABLE_TEST_EMAIL_ON_JOIN = false    -- set false after you finish tuning
local TEST_EMAIL_DELAY = 2.0              -- seconds (start same as NEW_MAIL_MESSAGE_DELAY)
local EZEMAIL_DEBUG = true -- set false after verified
local ANNOUNCEMENTS_FEED_MODULE = 'scripts/ezlibs-scripts/announcements_feed'


local function _preload_email_assets(player_id, mail)
  if not (Net and Net.provide_asset_for_player) then return end
  if not mail then return end

  if mail.mug_texture_path and mail.mug_texture_path ~= "" then
    pcall(Net.provide_asset_for_player, player_id, mail.mug_texture_path)
  end

  if mail.mug_animation_path and mail.mug_animation_path ~= "" then
    pcall(Net.provide_asset_for_player, player_id, mail.mug_animation_path)
  end
end

local function _get_bucket(player_id)
    local safe_secret = helpers.get_safe_player_secret(player_id)
    local mem = ezmemory.get_player_memory(safe_secret)
    mem.emails = mem.emails or {}
    mem.emails.by_id = mem.emails.by_id or {}
    return safe_secret, mem.emails.by_id
end

local function _dbg(...)
    if EZEMAIL_DEBUG then
        print("[ezemail]", ...)
    end
end

local function _percent_decode(s)
    s = tostring(s or "")
    return (s:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

local function _get_tombstone_set()
  local ok, feed = pcall(require, ANNOUNCEMENTS_FEED_MODULE)
  if not ok or type(feed) ~= "table" then
    return {}
  end

  local t = feed.tombstones
  if type(t) ~= "table" then
    return {}
  end

  local set = {}

  for _, id in ipairs(t) do
    id = tostring(id)
    set[id] = true
    set[_percent_decode(id)] = true
  end

  for k, v in pairs(t) do
    if v == true then
      k = tostring(k)
      set[k] = true
      set[_percent_decode(k)] = true
    end
  end

  return set
end

local function _find_mail_in_bucket(bucket, email_id)
    if not bucket or not email_id then return nil, nil end
    email_id = tostring(email_id)

    if bucket[email_id] then return bucket[email_id], email_id end

    local want = _percent_decode(email_id)

    for k, v in pairs(bucket) do
        if k == email_id then
            return v, k
        end
        if _percent_decode(k) == want then
            return v, k
        end
        if _percent_decode(email_id) == _percent_decode(k) then
            return v, k
        end
    end

    return nil, nil
end

local function _mark_email_read(player_id, email_id)
    if not player_id or not email_id then return end

    local safe_secret, bucket = _get_bucket(player_id)
    local stored, key = _find_mail_in_bucket(bucket, email_id)

    if not stored then
        _dbg("email_read fired but mail id not found in memory:", tostring(email_id))
        return
    end

    if stored.read ~= true then
        stored.read = true
        ezmemory.save_player_memory(safe_secret)
        _dbg("marked read:", tostring(key))
    else
        _dbg("already read:", tostring(key))
    end
end

-- ring_only = true means just ring the HUD, skip the popup message
-- This is used when re-notifying about unread mail on re-login
local function _notify_new_mail(player_id, msg, delay_seconds, ring_only)
    delay_seconds = delay_seconds or NEW_MAIL_MESSAGE_DELAY

    pcall(function()
        if Net.ring_player_hud then
            Net.ring_player_hud(player_id)
        end
    end)

    -- If ring_only, stop here — don't send the popup message
    if ring_only then return end

    msg = msg or "Looks like you got an e-mail."

    if not Net.message_player then
        return
    end

    local function send_msg()
        pcall(function()
            local mug = Net.get_player_mugshot(player_id)
            Net.message_player(player_id, msg, mug.texture_path, mug.animation_path)
        end)
    end

    if Async and Async.sleep and delay_seconds and delay_seconds > 0 then
        Async.sleep(delay_seconds).and_then(send_msg)
    else
        send_msg()
    end
end

function ezemail.resend_all(player_id)
    if not Net.send_player_email then
        return
    end

    local ok, safe_secret, bucket = pcall(function()
        local ss, b = _get_bucket(player_id)
        return ss, b
    end)

    if not ok or not bucket then
        return
    end

    local dirty = false
    local tombstones = _get_tombstone_set()

    -- Remove tombstoned emails from memory so they won't be restored
    if tombstones and next(tombstones) ~= nil then
      local to_delete = {}

      for key, stored in pairs(bucket) do
        local id = tostring((stored and stored.id) or key)
        if tombstones[id] or tombstones[key] or tombstones[_percent_decode(id)] or tombstones[_percent_decode(key)] then
          to_delete[#to_delete + 1] = key
        end
      end

      if #to_delete > 0 then
        for _, key in ipairs(to_delete) do
          bucket[key] = nil
        end
        dirty = true
        _dbg("pruned tombstoned mails:", #to_delete)
      end
    end

    local has_unread = false

    for _, stored in pairs(bucket) do
      local mail = helpers.deep_copy(stored)

      -- Send the email with its actual read status (don't force it to read)
      -- mail.read is already set correctly from stored

      pcall(function()
        _preload_email_assets(player_id, mail)
        Net.send_player_email(player_id, mail)
      end)

      -- Track if there are any unread emails so we can ring once at the end
      if stored.read ~= true then
        has_unread = true
      end
    end

    -- If any emails are still unread, ring the HUD (but no popup message this time)
    if has_unread then
      _notify_new_mail(player_id, nil, nil, true) -- ring only
    end

    if dirty then
      ezmemory.save_player_memory(safe_secret)
    end
end

-- Sends + saves (only notifies the FIRST time this mail id is ever sent to this player)
-- opts = { notify=true/false, notify_message="...", notify_use_player_mug=true/false }
function ezemail.send_once(player_id, mail, opts)
    opts = opts or {}
    if not mail or not mail.id then
        return
    end
    local tombstones = _get_tombstone_set()
    if tombstones[mail.id] or tombstones[_percent_decode(mail.id)] then
      _dbg("send_once blocked (tombstoned):", tostring(mail.id))
      return
    end
    if not Net.send_player_email then
        return
    end

    local safe_secret, bucket = _get_bucket(player_id)
    local first_time = (bucket[mail.id] == nil)

    if first_time then
        -- Save the email as unread
        bucket[mail.id] = mail
        bucket[mail.id].read = false
        ezmemory.save_player_memory(safe_secret)
    end

    -- Always send to current session (mailbox is session-only)
    -- Send with the current read status from memory
    local mail_to_send = helpers.deep_copy(bucket[mail.id])
    pcall(function()
        _preload_email_assets(player_id, mail_to_send)
        Net.send_player_email(player_id, mail_to_send)
    end)

    -- Notify only the first time: ring + popup message
    if first_time and opts.notify ~= false then
        local msg = opts.notify_message or "Looks like you got an e-mail."
        local delay = opts.notify_delay or NEW_MAIL_MESSAGE_DELAY
        _notify_new_mail(player_id, msg, delay, false) -- full notification
    end
end

-- Sends an email WITHOUT saving it (session-only).
function ezemail.send_temp(player_id, mail, opts)
    opts = opts or {}
    if not mail or not mail.id then return end
    if not Net.send_player_email then return end

    pcall(function()
        _preload_email_assets(player_id, mail)
        Net.send_player_email(player_id, mail)
    end)

    if opts.notify ~= false then
        local msg = opts.notify_message or "Looks like you got an e-mail."
        local delay = opts.notify_delay or NEW_MAIL_MESSAGE_DELAY
        _notify_new_mail(player_id, msg, delay, false)
    end
end

function ezemail.send_test_email(player_id, delay_seconds)
    if not Net.send_player_email then
        return
    end

    local safe_secret = helpers.get_safe_player_secret(player_id)
    local mail = {
        id = "EZTEST_" .. tostring(safe_secret) .. "_" .. tostring(os.time()),
        icon = 1,
        title = "Test",
        from = "MailSys",
        body = "Testing email notification delay.\n\nDelay: " .. tostring(delay_seconds or TEST_EMAIL_DELAY) .. " seconds.",
        mug_texture_path = "/server/assets/ezlibs-assets/eznpcs/mug/denpa-warp-sf2.png",
        mug_animation_path = "/server/assets/ezlibs-assets/eznpcs/mug/mug.animation",
        read = false,
    }

    pcall(function()
        ezemail.send_temp(player_id, mail, { notify = true })
    end)

end

-- Silent restore on login (no ring/message for read mail; ring only for unread)
Net:on("player_join", function(event)
    if not event or not event.player_id then return end

    if ezmemory and ezmemory.is_loaded and not ezmemory.is_loaded() then
        return
    end

    ezemail.resend_all(event.player_id)
    pcall(function()
      local ezannounce = require('scripts/ezlibs-scripts/ezannounce')
      ezannounce.send_missing(event.player_id)
    end)
    if ENABLE_TEST_EMAIL_ON_JOIN then
        ezemail.send_test_email(event.player_id, TEST_EMAIL_DELAY)
    end
end)

-- Now that email_read is fixed, we use it to actually mark emails as read in memory
Net:on("email_read", function(event)
  local player_id = event.player_id
  local email_id = event.email_id

  _dbg("email_read fired:", tostring(player_id), tostring(email_id))
  _mark_email_read(player_id, email_id)
end)

return ezemail
