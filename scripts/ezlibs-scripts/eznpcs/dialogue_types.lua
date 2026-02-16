
local helpers = require('scripts/ezlibs-scripts/helpers')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local ezquests = require('scripts/ezlibs-scripts/ezquests')
local ezemail = require('scripts/ezlibs-scripts/ezemail')

--Dialogue Types
local dialogue_types = {
    first={
        name = "first",
        action = function(npc, player_id, dialogue, relay_object)
            return async(function()
                local dialogue_texts = helpers.extract_numbered_properties(dialogue,"Text ")
                local next_dialogues = helpers.extract_numbered_properties(dialogue,"Next ")
                local mugshot = eznpcs.get_dialogue_mugshot(npc,player_id,dialogue)
                local res = await(Async.message_player(player_id, dialogue_texts[1], mugshot.texture_path, mugshot.animation_path))
                local next_id = first_value_from_table(next_dialogues)
                return next_id
            end)
        end
    },
    question={
        name = "question",
        action = function(npc, player_id, dialogue, relay_object)
            return async(function ()
                local dialogue_texts = helpers.extract_numbered_properties(dialogue,"Text ")
                local next_dialogues = helpers.extract_numbered_properties(dialogue,"Next ")
                local mugshot = eznpcs.get_dialogue_mugshot(npc,player_id,dialogue)
                local res = await(Async.question_player(player_id, dialogue_texts[1], mugshot.texture_path, mugshot.animation_path))
                local next_id = next_dialogues[2-res]
                return next_id
            end)
        end
    },
    quiz={
        name = "quiz",
        action = function(npc, player_id, dialogue, relay_object)
            return async(function ()
                local dialogue_texts = helpers.extract_numbered_properties(dialogue,"Text ")
                local next_dialogues = helpers.extract_numbered_properties(dialogue,"Next ")
                local mugshot = eznpcs.get_dialogue_mugshot(npc,player_id,dialogue)
                local res = await(Async.quiz_player(player_id, dialogue_texts[1],dialogue_texts[2],dialogue_texts[3], mugshot.texture_path, mugshot.animation_path))
                local next_id = next_dialogues[res+1]
                return next_id
            end)
        end
    },
    random={
        name = "random",
        action = function(npc, player_id, dialogue, relay_object)
            return async(function ()
                local dialogue_texts = helpers.extract_numbered_properties(dialogue,"Text ")
                local next_dialogues = helpers.extract_numbered_properties(dialogue,"Next ")
                local mugshot = eznpcs.get_dialogue_mugshot(npc,player_id,dialogue)
                local rnd_text_index = math.random( #dialogue_texts)
                local res = await(Async.message_player(player_id, dialogue_texts[rnd_text_index], mugshot.texture_path, mugshot.animation_path))
                local next_id = next_dialogues[rnd_text_index] or next_dialogues[1]
                return next_id
            end)
        end
    },
    itemcheck={
        name = 'itemcheck',
        action = function(npc, player_id, dialogue, relay_object)
            return async(function ()
                local area_id = Net.get_player_area(player_id)
                local required_items = helpers.extract_numbered_properties(dialogue,"Item ")
                local next_dialogues = helpers.extract_numbered_properties(dialogue,"Next ")

                local take_item = dialogue.custom_properties["Take Item"] == "true"
                local next_dialogue_id = nil

                local check_passed = true
                for index, item_object_id in ipairs(required_items) do
                    local item_info = helpers.read_item_information(area_id,item_object_id)
                    local has_count = 0
                    if item_info then
                        if item_info.type == "money" then
                            has_count = Net.get_player_money(player_id)
                        else
                            has_count = ezmemory.count_player_item(player_id, item_info.name)
                        end
                        if has_count < item_info.amount then
                            check_passed = false
                        end
                    end
                end
                if check_passed then
                    next_dialogue_id = next_dialogues[1]
                    for index, item_object_id in ipairs(required_items) do
                        local item_info = helpers.read_item_information(area_id,item_object_id)
                        if item_info and take_item then
                            if item_info.type == "money" then
                                ezmemory.spend_player_money(player_id,item_info.amount)
                            else
                                ezmemory.remove_player_item(player_id,item_info.name, item_info.amount)
                            end
                        end
                    end
                else
                    next_dialogue_id = next_dialogues[2]
                end
                return next_dialogue_id
            end)
        end
    },
    questcheck={
        name = "questcheck",
        action = function(npc, player_id, dialogue, relay_object)
            return async(function ()
                local next_dialogues = helpers.extract_numbered_properties(dialogue,"Next ")

                local quest_name = dialogue.custom_properties["Quest Name"]
                local flag_name  = dialogue.custom_properties["Flag Name"]

                -- Optional:
                -- - If Flag Value is empty/nil => truthy check
                -- - If Flag Value exists => compare (string compare by default)
                local expected   = dialogue.custom_properties["Flag Value"]
                local op         = dialogue.custom_properties["Operator"] or dialogue.custom_properties["Op"] -- ==, !=, >=, <=, >, <
                local invert     = dialogue.custom_properties["Invert"] == "true"

                if not quest_name or not flag_name then
                    warn("[eznpcs] questcheck missing Quest Name / Flag Name on dialogue node", dialogue.id)
                    return next_dialogues[2] or next_dialogues[1]
                end

                local value = ezquests.get_player_quest_flag(player_id, quest_name, flag_name)

                local passed = false

                if expected == nil or expected == "" then
                    -- truthy check (treat nil/false/"false" as false)
                    passed = not (value == nil or value == false or value == "false")
                else
                    local cmp = op or "=="
                    if cmp == "==" or cmp == "=" then
                        passed = tostring(value) == tostring(expected)
                    elseif cmp == "!=" then
                        passed = tostring(value) ~= tostring(expected)
                    else
                        -- numeric operators if possible
                        local a = tonumber(value)
                        local b = tonumber(expected)
                        if a ~= nil and b ~= nil then
                            if     cmp == ">=" then passed = a >= b
                            elseif cmp == "<=" then passed = a <= b
                            elseif cmp == ">"  then passed = a >  b
                            elseif cmp == "<"  then passed = a <  b
                            else
                                passed = tostring(value) == tostring(expected)
                            end
                        else
                            passed = tostring(value) == tostring(expected)
                        end
                    end
                end

                if invert then
                    passed = not passed
                end

                return next_dialogues[passed and 1 or 2]
            end)
        end
    },
    before={
        name = "before",
        action = function(npc, player_id, dialogue, relay_object)
            return async(function ()
                local dialogue_texts = helpers.extract_numbered_properties(dialogue,"Text ")
                local next_dialogues = helpers.extract_numbered_properties(dialogue,"Next ")
                local mugshot = eznpcs.get_dialogue_mugshot(npc,player_id,dialogue)
                local date_b = dialogue.custom_properties['Date']
                local message = dialogue_texts[2]
                local next_dialogue_id = next_dialogues[2]
                if helpers.is_now_before_date(date_b) then
                    message = dialogue_texts[1]
                    next_dialogue_id = next_dialogues[1]
                end
                if message then
                    await(Async.message_player(player_id, message, mugshot.texture_path, mugshot.animation_path))
                end
                return next_dialogue_id
            end)
        end
    },
    after={
        name = "after",
        action = function(npc, player_id, dialogue, relay_object)
            return async(function ()
                local dialogue_texts = helpers.extract_numbered_properties(dialogue,"Text ")
                local next_dialogues = helpers.extract_numbered_properties(dialogue,"Next ")
                local mugshot = eznpcs.get_dialogue_mugshot(npc,player_id,dialogue)
                local date_b = dialogue.custom_properties['Date']
                local message = dialogue_texts[2]
                local next_dialogue_id = next_dialogues[2]
                if not helpers.is_now_before_date(date_b) then
                    message = dialogue_texts[1]
                    next_dialogue_id = next_dialogues[1]
                end
                if message then
                    await(Async.message_player(player_id, message, mugshot.texture_path, mugshot.animation_path))
                end
                return next_dialogue_id
            end)
        end
    },
    shop={
        name = "shop",
        action = function(npc, player_id, dialogue, relay_object)
            return async(function ()
                local area_id = Net.get_player_area(player_id)
                local shop_item_object_ids = helpers.extract_numbered_properties(dialogue,"Item ")
                local next_dialogues = helpers.extract_numbered_properties(dialogue,"Next ")
                local mugshot = eznpcs.get_dialogue_mugshot(npc,player_id,dialogue)
                local shop_items = {}

                --create list of items for sale
                for i, item_object_id in ipairs(shop_item_object_ids) do
                    local item_info = helpers.read_item_information(area_id,item_object_id)
                    if item_info then
                        local shop_item = {
                            name=item_info.name,
                            price=item_info.price,
                            description=item_info.description or "???",
                            is_key=item_info.type == 'keyitem'
                        }
                        table.insert(shop_items,shop_item)
                    end
                end

                await(ezmemory.open_shop_async(player_id,shop_items,mugshot.texture_path,mugshot.animation_path))
                local next_id = first_value_from_table(next_dialogues)
                return next_id
            end)
        end
    },
    password={
        name = "password",
        action = function(npc, player_id, dialogue, relay_object)
            return async(function ()
                local correct_password = dialogue.custom_properties["Text 1"]
                local user_input = await(Async.prompt_player(player_id))
                if user_input == correct_password then
                    return dialogue.custom_properties["Next 1"]
                else
                    return dialogue.custom_properties["Next 2"]
                end
            end)
        end
    },
    quest_switch={
        name = "quest_switch",
        action = function(npc, player_id, dialogue, relay_object)
            return async(function ()
                --returns a different next dialogue based on current quest state
                --specify a quest name as a property
                local quest_name = dialogue.custom_properties["Quest Name"]
                local quest_state = ezquests.get_player_quest_state(player_id,quest_name)
                if dialogue.custom_properties[quest_state] then
                    return dialogue.custom_properties[quest_state]
                else
                    warn('[eznpcs] dialogue node',dialogue.id,'has no custom property for quest state',quest_state)
                end
            end)
        end
    },
    quest_event={
        name = "quest_event",
        action = function(npc, player_id, dialogue, relay_object)
            return async(function ()
                local quest_name = dialogue.custom_properties["Quest Name"]
                local event_value = dialogue.custom_properties["Event Value"]
                local next_dialogues = helpers.extract_numbered_properties(dialogue,"Next ")
                await(ezquests.quest_event(player_id,quest_name,event_value))
                return first_value_from_table(next_dialogues)
            end)
        end
    },
    item={
        name = "item",
        action = function(npc, player_id, dialogue, relay_object)
            return async(function ()
                local area_id = Net.get_player_area(player_id)
                local gift_item_ids = helpers.extract_numbered_properties(dialogue,"Item ")
                local notify_player = dialogue.custom_properties["Dont Notify"] ~= "true"
                for index, item_id in ipairs(gift_item_ids) do
                    ezmemory.give_item_with_optional_notify(player_id,area_id,item_id,nil,notify_player)
                end
                return dialogue.custom_properties["Next 1"]
            end)
        end
    },
    email={
        name = "email",
        action = function(npc, player_id, dialogue, relay_object)
            return async(function()
                local next_dialogues = helpers.extract_numbered_properties(dialogue,"Next ")
                local next_id = first_value_from_table(next_dialogues)

                local MUG_DIR = "/server/assets/ezlibs-assets/eznpcs/mug/"

                local function has_asset(path)
                    if not path or path == "" then return false end
                    if not (Net and Net.has_asset) then return true end
                    local ok, res = pcall(Net.has_asset, path)
                    if ok and res == true then return true end
                    if ok and res == false then return false end
                    return true
                end

                local function ensure_ext(p, ext)
                    if not p or p == "" then return nil end
                    -- if it already has an extension, leave it
                    if p:match("%.[%w]+$") then return p end
                    return p .. ext
                end

                local function resolve_texture(raw)
                    if not raw or raw == "" then return nil end
                    -- full path provided
                    if raw:find("/") then
                        return ensure_ext(raw, ".png")
                    end
                    -- shorthand name
                    local name = raw
                    if not name:match("%.png$") then name = name .. ".png" end
                    return MUG_DIR .. name
                end

                local function resolve_anim(raw)
                    if raw == nil or raw == "" then
                        return MUG_DIR .. "mug.animation"
                    end
                    if raw:find("/") then
                        return ensure_ext(raw, ".animation")
                    end
                    local name = raw
                    if not name:match("%.animation$") then name = name .. ".animation" end
                    return MUG_DIR .. name
                end

                local id = dialogue.custom_properties["Email Id"]
                if not id or id == "" then
                    warn("[eznpcs] email dialogue missing Email Id on node", dialogue.id)
                    return next_id
                end

                local icon  = tonumber(dialogue.custom_properties["Email Icon"] or "1") or 1
                local title = dialogue.custom_properties["Email Title"] or "Mail"
                local from  = dialogue.custom_properties["Email From"] or "???"

                local body_lines = helpers.extract_numbered_properties(dialogue,"Body ")
                local body = ""
                if body_lines and #body_lines > 0 then
                    body = table.concat(body_lines, "\n\n")
                else
                    body = dialogue.custom_properties["Email Body"] or ""
                end

                local notify = (dialogue.custom_properties["Dont Notify"] ~= "true")
                local delay  = tonumber(dialogue.custom_properties["Notify Delay"])
                local msg    = dialogue.custom_properties["Notify Message"] or "Looks like you got an e-mail."
                local persist = (dialogue.custom_properties["Persist"] ~= "false")

                -- Mug rules
                local tex_raw  = dialogue.custom_properties["Mug Texture Path"]
                local anim_raw = dialogue.custom_properties["Mug Animation Path"]

                local tex_path = resolve_texture(tex_raw)
                local anim_path = nil

                if tex_path then
                    anim_path = resolve_anim(anim_raw)

                    -- If either is missing, send with no mug + warn
                    if not has_asset(tex_path) or not has_asset(anim_path) then
                        warn("[eznpcs] email mug asset missing. tex=", tex_path, "anim=", anim_path, " -> sending without mug")
                        tex_path = nil
                        anim_path = nil
                    end
                end

                local mail = {
                    id = tostring(id),
                    icon = icon,
                    title = title,
                    from = from,
                    body = body,
                }

                if tex_path and anim_path then
                    mail.mug_texture_path = tex_path
                    mail.mug_animation_path = anim_path
                end

                if persist then
                    -- guarded by ezemail memory (won't create duplicates)
                    ezemail.send_once(player_id, mail, {
                        notify = notify,
                        notify_message = msg,
                        notify_delay = delay
                    })
                else
                    ezemail.send_temp(player_id, mail, {
                        notify = notify,
                        notify_message = msg,
                        notify_delay = delay
                    })
                end

                return next_id
            end)
        end
    }
}

return dialogue_types