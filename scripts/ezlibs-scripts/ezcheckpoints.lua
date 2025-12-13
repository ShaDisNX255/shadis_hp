local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local helpers = require('scripts/ezlibs-scripts/helpers')

local ezcheckpoints = {}

--[[Features

Key Name (string) = money
    if name is money, spend money
Required Keys (number) = 1
Consume Key (bool) = false

Once (bool) = true 
    if the gate is hidden forever

Unlocking Frame Index (number)
Unlocking Animation Time (number)
Unlocking Sound Path (string)

Skip Prompt (bool) = false 
    dont ask the player if they want to unlock
Description (string) = 
    description before lock prompt
Unlocked Message (string) 
    override the message on unlock
Unlock Failed Message (string) 
    override the message on failed unlock
]]

local function password_check(player_id,prompt_message,correct_password)
    return async(function ()
        local passed = false
        if #prompt_message > 0 then
            await(Async.message_player(player_id,prompt_message))
        end
        local input = await(Async.prompt_player(player_id))
        if input == correct_password then
            passed = true
        end
        return passed
    end)
end

local function money_check(player_id,prompt_message,amount,consume_money)
    return async(function ()
        local passed = false
        local choice = 1
        if #prompt_message > 0 then
            choice = await(Async.question_player(player_id,prompt_message))
            if choice == 0 then
                return nil
            end
        end
        if choice == 1 then
            if consume_money then
                passed = ezmemory.spend_player_money(player_id, amount)
            else
                passed = Net.get_player_money(player_id) >= amount
            end
        end
        return passed
    end)
end

local function item_check(player_id,prompt_message,required_item,amount,consume_item)
    return async(function ()
        local passed = false
        local choice = 1
        if #prompt_message > 0 then
            choice = await(Async.question_player(player_id,prompt_message))
            if choice == 0 then
                return nil
            end
        end
        if choice == 1 then
            passed = ezmemory.count_player_item(player_id,required_item) >= amount
            if passed and consume_item then
                ezmemory.remove_player_item(player_id, required_item, amount)
            end
        end
        return passed
    end)
end

local function unlock_checkpoint_for_player(player_id, area_id, object_id, unlocking_asset_name, unlocking_sound_path, unlocking_animation_time, once)
  return async(function ()
    Net.lock_player_input(player_id)

    local object = Net.get_object_by_id(area_id, object_id)
    if not object then
      Net.unlock_player_input(player_id)
      return false
    end

    Net.play_sound_for_player(player_id, unlocking_sound_path)

    if once then
      ezmemory.hide_object_from_player(player_id, area_id, object_id)
    else
      ezmemory.hide_object_from_player_till_disconnect(player_id, area_id, object_id)
    end

    if unlocking_animation_time > 0 then
      local new_bot_props = {
        x = object.x,
        y = object.y,
        z = object.z,
        texture_path = "/server/assets/ezlibs-assets/ezcheckpoints/" .. unlocking_asset_name .. ".png",
        animation_path = "/server/assets/ezlibs-assets/ezcheckpoints/" .. unlocking_asset_name .. ".animation",
        animation = "UNLOCKING",
        warp_in = false,
        area_id = area_id
      }
      Net.provide_asset(area_id, new_bot_props.texture_path)

      local bot_id = Net.create_bot(new_bot_props)
      await(Async.sleep(unlocking_animation_time))
      Net.remove_bot(bot_id, false)
    end

    Net.unlock_player_input(player_id)
    return true
  end)
end

Net:on("object_interaction", function(event)
    local button = event.button
    if button ~= 0 then return end

    local player_id = event.player_id
    local object_id = event.object_id
    local area_id = Net.get_player_area(player_id)

    local checkpoint_object = Net.get_object_by_id(area_id, object_id)
    if not checkpoint_object then return end
    if checkpoint_object.type ~= "Checkpoint" then return end

    -- anti spam lock
    local lock_id = player_id.."_"..area_id.."_"..checkpoint_object.id
    local lock = helpers.get_lock(player_id, lock_id)
    if not lock then
        return
    end

    local cp = checkpoint_object.custom_properties or {}

    -- Gather information from checkpoint object
    -- by default it will just ask for 1 money and vanish
    local password = cp["Password"] or false
    local key_name = cp["Key Name"] or "money"
    local required_keys = tonumber(cp["Required Keys"] or 1)
    local consume = cp["Consume"] == "true"
    local once = cp["Once"] == "true"
    local unlocking_asset_name = cp["Unlocking Asset Name"] or "bn5cubegreen_bot"
    local unlocking_animation_time = tonumber(cp["Unlocking Animation Time"] or 0)
    local unlocking_sound_path = cp["Unlocking Sound Path"] or "/server/assets/ezlibs-assets/sfx/panel_change.ogg"
    local skip_prompt =  cp["Skip Prompt"] == "true"
    local description = cp["Description"] or "It's a Security Cube"
    local unlocked_message = cp["Unlocked Message"] or "The Security Cube was unlocked!"
    local unlock_failed_message = cp["Unlock Failed Message"] or "You were unable to unlock the Security Cube"

    -- Boss Gate config (only used if Boss Gate)
    local boss_gate_flag = (cp["Boss Gate"] == "true")
    local key_name_l = tostring(key_name or ""):lower()
    local is_boss_gate = boss_gate_flag or (key_name_l == "boss gate") or (key_name_l == "bossgate")

    local function _trim(s)
        return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function _split_csv(s)
        s = tostring(s or "")
        local out = {}
        for part in s:gmatch("[^,]+") do
            local v = _trim(part)
            if v ~= "" then out[#out+1] = v end
        end
        return out
    end

    return async(function ()
        -- Always show description first (keeps legacy behavior)
        if #tostring(description or "") > 0 then
            await(Async.message_player(player_id, description))
        end

        --------------------------------------------------------------------
        -- Boss Gate special-case:
        --  - No Yes/No prompt
        --  - Check dungeon boss pools
        --  - If not defeated -> message & return
        --  - If defeated -> unlock immediately
        --------------------------------------------------------------------
        if is_boss_gate then
            local okD, dungeon = pcall(require, "scripts/ezlibs-custom/dungeon")
            if not okD or type(dungeon) ~= "table" or type(dungeon.are_bosses_defeated) ~= "function" then
                await(Async.message_player(player_id, "[Boss Gate] dungeon.lua not loaded; can't check boss pools."))
                lock.release()
                return
            end

            local boss_ids = _split_csv(cp["Boss IDs"] or cp["Boss ID"] or "")
            local mem_area = _trim(cp["Boss Memory Area"] or area_id)
            if mem_area == "" then mem_area = area_id end

            if #boss_ids == 0 then
                await(Async.message_player(player_id, "[Boss Gate] Missing 'Boss IDs' property."))
                lock.release()
                return
            end

            local all, remaining = dungeon.are_bosses_defeated(mem_area, boss_ids)

            if not all then
                local msg = tostring(cp["Boss Not Defeated Message"] or "Boss still not defeated.")
                local show_remaining = (tostring(cp["Show Remaining"] or "true") == "true")
                if show_remaining and remaining and #remaining > 0 then
                    msg = msg .. " (" .. table.concat(remaining, ", ") .. ")"
                end
                await(Async.message_player(player_id, msg))
                lock.release()
                return
            end

            -- All required bosses defeated -> unlock and message
            local unlocked = await(unlock_checkpoint_for_player(
                player_id,
                area_id,
                object_id,
                unlocking_asset_name,
                unlocking_sound_path,
                unlocking_animation_time,
                once
            ))

            if unlocked then
                if #tostring(unlocked_message or "") > 0 then
                    await(Async.message_player(player_id, unlocked_message))
                end
            else
                await(Async.message_player(player_id, unlock_failed_message))
            end

            lock.release()
            return
        end

        --------------------------------------------------------------------
        -- Legacy behavior (money / item / password) unchanged
        --------------------------------------------------------------------
        local prompt_message = ""
        local prompt_type = "item"

        if not skip_prompt then
            prompt_message = "Use "..key_name.." to Unlock?"

            if key_name == "money" then
                prompt_type = "money"
                if consume then
                    prompt_message = "Spend "..required_keys.."$ to Unlock?"
                else
                    prompt_message = "Show "..required_keys.."$ to Unlock?"
                end
            elseif prompt_type == "item" and required_keys > 1 then
                if consume then
                    prompt_message = "Use "..required_keys.." "..key_name.." to Unlock?"
                else
                    prompt_message = "Show "..required_keys.." "..key_name.." to Unlock?"
                end
            end

            -- password overrides if it exists
            if password then
                prompt_message = "Please input the password"
                prompt_type = "password"
            end
        end

        local unlocked = false
        if prompt_type == "password" then
            unlocked = await(password_check(player_id, prompt_message, password))
        elseif prompt_type == "money" then
            unlocked = await(money_check(player_id, prompt_message, required_keys, consume))
        else
            unlocked = await(item_check(player_id, prompt_message, key_name, required_keys, consume))
        end

        if unlocked == true then
            await(unlock_checkpoint_for_player(
                player_id,
                area_id,
                object_id,
                unlocking_asset_name,
                unlocking_sound_path,
                unlocking_animation_time,
                once
            ))
            if #tostring(unlocked_message or "") > 0 then
                await(Async.message_player(player_id, unlocked_message))
            end
        elseif unlocked == false then
            await(Async.message_player(player_id, unlock_failed_message))
        end

        lock.release()
    end)
end)

return ezcheckpoints