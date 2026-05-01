local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local helpers = require('scripts/ezlibs-scripts/helpers')

local ezquests = {
    quests={}
}

function ezquests.add_quest(quest)
    if not quest.name then
        warn('[ezquests] quest has no name')
        return
    end
    if not quest.handle_event_async then
        warn('[ezquests] quest',quest.name,'needs a handle_event function')
        return
    end
    if not quest.determine_state then
        warn('[ezquests] quest',quest.name,'needs a determine_state function')
        return
    end
    if ezquests.quests[quest.name] then
        warn('[ezquests] quest',quest.name,'already exists and will be replaced')
    end
    ezquests.quests[quest.name] = quest
end

function ezquests.set_player_quest_flag(player_id,quest_name,flag_name,flag_state)
    print('[ezquests]',quest_name,'flag(',flag_name,')set to',flag_state,'for player',player_id)
    local safe_secret = helpers.get_safe_player_secret(player_id)
    local player_memory = ezmemory.get_player_memory(safe_secret)
    if not player_memory["quests"] then
        player_memory["quests"] = {}
    end
    if not player_memory["quests"][quest_name] then
        player_memory["quests"][quest_name] = {}
    end
    player_memory["quests"][quest_name][flag_name] = flag_state
    ezmemory.save_player_memory(safe_secret)
end

function ezquests.get_player_quest_flag(player_id,quest_name,flag_name,flag_state)
    local safe_secret = helpers.get_safe_player_secret(player_id)
    local player_memory = ezmemory.get_player_memory(safe_secret)
    if not player_memory["quests"] then
        return nil
    end
    if not player_memory["quests"][quest_name] then
        return nil
    end
    return player_memory["quests"][quest_name][flag_name]
end

function ezquests.clear_player_quest_flags(player_id,quest_name)
    print('[ezquests] clearing all flags for quest',quest_name,'for player',player_id)
    local safe_secret = helpers.get_safe_player_secret(player_id)
    local player_memory = ezmemory.get_player_memory(safe_secret)
    if not player_memory["quests"] then
        player_memory["quests"] = {}
    end
    player_memory["quests"][quest_name] = {}
    ezmemory.save_player_memory(safe_secret)
end

function ezquests.get_quest(quest_name)
    local quest = ezquests.quests[quest_name]
    if quest then
        return quest
    else
        warn('[ezquests] no quest with name ',quest_name)
    end
end

function ezquests.get_player_quest_state(player_id, quest_name)
    local quest = ezquests.get_quest(quest_name)
    if not quest then
        warn('[ezquests] quest "' .. tostring(quest_name) .. '" not found, returning nil')
        return nil
    end
    return quest:determine_state(player_id)
end

function ezquests.quest_event(player_id,quest_name,event_value)
    local quest = ezquests.get_quest(quest_name)
    if not quest then
        warn('[ezquests] cannot send event: quest "' .. tostring(quest_name) .. '" not found')
        return async(function() end)()  -- return empty promise
    end
    print('[ezquests] quest=',quest)
    return quest:handle_event_async(player_id,event_value)
end


--testing quest
--handle_event_async must return a promise
local quest_get_punched = {
    name = "Get Punched",
    handle_event_async = function (self,player_id,event_value)
        return async(function ()
            local accpeted = ezquests.get_player_quest_flag(player_id,self.name,'accepted')
            if accpeted or event_value == "accepted" then
                --set the flag if the quest is accepted, or we are accpeting it
                ezquests.set_player_quest_flag(player_id,self.name,event_value,true)
            end
            if event_value == 'reset' then
                ezquests.clear_player_quest_flags(player_id,self.name)
            end
        end)
    end,
    determine_state = function (self,player_id)
        if ezquests.get_player_quest_flag(player_id,self.name,'punched') then
            return "punched"
        end
        if ezquests.get_player_quest_flag(player_id,self.name,'accepted') then
            return "accepted"
        end
        return "unaccepted"
    end
}
ezquests.add_quest(quest_get_punched)

function ezquests.get_player_quest_stage(player_id, quest_name, default_stage)
    local v = ezquests.get_player_quest_flag(player_id, quest_name, "stage")
    v = tonumber(v)
    if v == nil then
        return default_stage or 0
    end
    return v
end

function ezquests.set_player_quest_stage(player_id, quest_name, stage)
    ezquests.set_player_quest_flag(player_id, quest_name, "stage", tonumber(stage) or 0)
end

function ezquests.unset_player_quest_flag(player_id, quest_name, flag_name)
    local safe_secret = helpers.get_safe_player_secret(player_id)
    local player_memory = ezmemory.get_player_memory(safe_secret)
    if not player_memory["quests"] or not player_memory["quests"][quest_name] then
        return
    end
    player_memory["quests"][quest_name][flag_name] = nil
    ezmemory.save_player_memory(safe_secret)
end

----------------------------------------------------------------
-- EchoProgram quest (Echo Navi storyline)
-- Note: keyitems are given/taken via TMX "Item" + "item/itemcheck" dialogue types.
----------------------------------------------------------------
local quest_echo_program = {
    name = "EchoProgram",

    handle_event_async = function(self, player_id, event_value)
        return async(function()
            if event_value == "reset" then
                ezquests.clear_player_quest_flags(player_id, self.name)
                return
            end

            if event_value == "start" then
                -- Just mark the quest started; the battle happens immediately after.
                if ezquests.get_player_quest_stage(player_id, self.name, 0) < 1 then
                    ezquests.set_player_quest_stage(player_id, self.name, 1)
                end
                ezquests.set_player_quest_flag(player_id, self.name, "accepted", true)
                return
            end

            if event_value == "echo_won" then
                -- Player receives CorruptChip via TMX. We only set progression flags here.
                ezquests.set_player_quest_stage(player_id, self.name, 2)
                ezquests.set_player_quest_flag(player_id, self.name, "need_gutsman", true)

                -- Clear downstream flags in case of weird re-entry.
                ezquests.unset_player_quest_flag(player_id, self.name, "need_roll")
                ezquests.unset_player_quest_flag(player_id, self.name, "need_darknavi")
                ezquests.unset_player_quest_flag(player_id, self.name, "need_zary_dungeon")
                ezquests.unset_player_quest_flag(player_id, self.name, "need_zary_surface")
                ezquests.unset_player_quest_flag(player_id, self.name, "need_protoman")
                return
            end

            -- Ignore other events if quest never started
            if not ezquests.get_player_quest_flag(player_id, self.name, "accepted") then
                return
            end

            if event_value == "gutsman_smash" then
                ezquests.unset_player_quest_flag(player_id, self.name, "need_gutsman")
                ezquests.set_player_quest_flag(player_id, self.name, "need_roll", true)
                return
            end

            if event_value == "roll_fix" then
                ezquests.unset_player_quest_flag(player_id, self.name, "need_roll")
                ezquests.set_player_quest_flag(player_id, self.name, "need_darknavi", true)
                return
            end

            if event_value == "darknavi_suppress" then
                ezquests.unset_player_quest_flag(player_id, self.name, "need_darknavi")

                -- Dungeon Zary is now OPTIONAL (hint only)
                ezquests.set_player_quest_flag(player_id, self.name, "need_zary_dungeon", true)

                -- Allow rink Zary immediately (no dungeon required)
                ezquests.set_player_quest_flag(player_id, self.name, "need_zary_surface", true)

                return
            end

            if event_value == "zary_meet_surface" then
                -- Optional hint. Never let this rewind/override later steps.
                ezquests.unset_player_quest_flag(player_id, self.name, "need_zary_dungeon")

                if ezquests.get_player_quest_flag(player_id, self.name, "need_protoman")
                    or ezquests.get_player_quest_flag(player_id, self.name, "completed") then
                    return
                end

                ezquests.set_player_quest_flag(player_id, self.name, "need_zary_surface", true)
                return
            end

            if event_value == "zary_reveal_official" then
                ezquests.unset_player_quest_flag(player_id, self.name, "need_zary_surface")
                ezquests.unset_player_quest_flag(player_id, self.name, "need_zary_dungeon")
                ezquests.set_player_quest_flag(player_id, self.name, "need_protoman", true)
                return
            end

            if event_value == "protoman_briefing" then
                ezquests.unset_player_quest_flag(player_id, self.name, "need_protoman")
                ezquests.set_player_quest_flag(player_id, self.name, "completed", true)
                return
            end
        end)
    end,

    determine_state = function(self, player_id)
        local stage = ezquests.get_player_quest_stage(player_id, self.name, 0)
        stage = tonumber(stage) or 0

        if stage == 0 then return "stage0" end
        if stage == 1 then return "stage1" end
        return "stage2"
    end
}

ezquests.add_quest(quest_echo_program)

return ezquests