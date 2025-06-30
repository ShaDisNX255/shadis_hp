local eznpcs_events = {}
local eznpcs = require('scripts/ezlibs-scripts/eznpcs/eznpcs')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local ezmystery = require('scripts/ezlibs-scripts/ezmystery')
local ezfarms = require('scripts/ezlibs-scripts/ezfarms')
local ezweather = require('scripts/ezlibs-scripts/ezweather')
local ezwarps = require('scripts/ezlibs-scripts/ezwarps/main')
local ezencounters = require('scripts/ezlibs-scripts/ezencounters/main')
local helpers = require('scripts/ezlibs-scripts/helpers')


local sfx = {
    hurt = '/server/assets/ezlibs-assets/sfx/hurt.ogg',
    item_get = '/server/assets/ezlibs-assets/sfx/item_get.ogg',
    recover = '/server/assets/ezlibs-assets/sfx/recover.ogg',
    gibberish = '/server/assets/ezlibs-assets/sfx/gibberish.ogg',
    card_error = '/server/assets/ezlibs-assets/ezfarms/card_error.ogg'
}

local event1 = {
    name = "Italian Gibberish",
    action = function(npc, player_id, dialogue, relay_object)
        return async(function()
            local player_mugshot = Net.get_player_mugshot(player_id)
            Net.play_sound_for_player(player_id, sfx.gibberish)
            return dialogue.custom_properties["Next 1"]
        end)
    end
}
eznpcs.add_event(event1)

local event2 = {
    name="Heel Navi1",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
        Net.initiate_encounter(player_id, "/server/assets/bosses/com_louise_mob_HeelNavi.zip")
        return dialogue.custom_properties["Next 1"]
    end)
end
}
eznpcs.add_event(event2)

local event3 = {
    name = "Gambler",
    action = function(npc, player_id, dialogue)
        return async(function()
            if ezmemory.spend_player_money(player_id, 5000) then
                return dialogue.custom_properties["Got moneyz"]
            else
                return dialogue.custom_properties["No moneyz"]
            end
        end)
    end
}
eznpcs.add_event(event3)

local Win_Gamble = {
    name = "Win_Gamble",
    action = function(npc, player_id, dialogue)
        return async(function()
            local zenny_amount = tonumber(dialogue.custom_properties["Amount"])
            ezmemory.spend_player_money(player_id, -zenny_amount)
            Net.play_sound_for_player(player_id, sfx.item_get)
            await(Async.message_player(player_id, "Got " .. zenny_amount .. "$!"))
            return dialogue.custom_properties["Next 1"]
        end)
    end
}
eznpcs.add_event(Win_Gamble)

