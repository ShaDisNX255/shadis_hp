-- scripts/ezlibs-custom/dungeons.lua
-- Shared dungeon behavior: detection + heal NPC event

local dungeons = {}

local ezmemory = require("scripts/ezlibs-scripts/ezmemory")
local eznpcs   = require("scripts/ezlibs-scripts/eznpcs/eznpcs")

----------------------------------------------------------------
-- Dungeon detection
-- Uses a bool map custom property: Dungeon = true
-- (same style as "Forced Base HP", "Honor HPMem", etc.) :contentReference[oaicite:2]{index=2}
----------------------------------------------------------------
local function is_dungeon_area(area_id)
    if not area_id then return false end
    return Net.get_area_custom_property(area_id, "Dungeon") == "true"
end

dungeons.is_dungeon_area = is_dungeon_area

-- Optional debug hooks for later dungeon-wide behavior
Net:on("player_area_transfer", function(ev)
    if not ev or not ev.player_id then return end
    local area_id = Net.get_player_area(ev.player_id)
    if is_dungeon_area(area_id) then
        print("[dungeons] player", ev.player_id, "entered dungeon area", area_id)
        -- Future: dungeon-specific rules can hook in here
    end
end)

Net:on("player_join", function(ev)
    if not ev or not ev.player_id then return end
    local area_id = Net.get_player_area(ev.player_id)
    if is_dungeon_area(area_id) then
        print("[dungeons] player", ev.player_id, "joined in dungeon area", area_id)
    end
end)

----------------------------------------------------------------
-- Dialogue event: DungeonHeal
-- Heals the player up to a cap (default 500) using ezmemory.set_player_health. :contentReference[oaicite:3]{index=3}
-- Only works in areas with Dungeon = true.
--
-- Usage in Tiled dialogue:
--   Event Name: DungeonHeal
--   (optional) Heal Amount: 500   -- or any other cap for that dungeon
----------------------------------------------------------------
eznpcs.add_event{
    name = "DungeonHeal",
    action = function(npc, player_id, dialogue, relay_object)
        return async(function()
            local area_id = Net.get_player_area(player_id)
            if not is_dungeon_area(area_id) then
                -- Not in a dungeon; just continue the dialogue chain
                if dialogue and dialogue.custom_properties then
                    return dialogue.custom_properties["Next 1"]
                end
                return nil
            end

            local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
            local props = (dialogue and dialogue.custom_properties) or {}

            -- Configurable heal cap: Heal Amount / Heal / HP; default 500
            local heal_cap = tonumber(
                 props["Heal Amount"]
              or props["Heal"]
              or props["HP"]
            ) or 500

            -- Don't exceed current max HP in this area
            local cur_hp = Net.get_player_health(player_id)
            local max_hp = Net.get_player_max_health(player_id)
            local target = math.min(heal_cap, max_hp)

            if cur_hp >= target then
                -- Already at or above the cap
                if Async and Async.message_player then
                    await(Async.message_player(
                        player_id,
                        string.format("You're already at %d HP.", cur_hp),
                        mug and mug.texture_path,
                        mug and mug.animation_path
                    ))
                else
                    Net.message_player(player_id, string.format("You're already at %d HP.", cur_hp))
                end
            else
                -- Persisted heal, respecting ezmemory health rules
                ezmemory.set_player_health(player_id, target)

                local new_hp = Net.get_player_health(player_id)

                -- Same recover SFX path used elsewhere :contentReference[oaicite:4]{index=4}
                Net.play_sound_for_player(player_id, "/server/assets/ezlibs-assets/sfx/recover.ogg")

                if Async and Async.message_player then
                    await(Async.message_player(
                        player_id,
                        string.format("Recovered your HP to %d!", new_hp),
                        mug and mug.texture_path,
                        mug and mug.animation_path
                    ))
                else
                    Net.message_player(player_id, string.format("Recovered your HP to %d!", new_hp))
                end
            end

            if dialogue and dialogue.custom_properties then
                return dialogue.custom_properties["Next 1"]
            end
            return nil
        end)
    end
}

return dungeons
