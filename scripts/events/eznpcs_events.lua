local eznpcs_events = {}
local eznpcs = require('scripts/ezlibs-scripts/eznpcs/eznpcs')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local ezmystery = require('scripts/ezlibs-scripts/ezmystery')
local ezfarms = require('scripts/ezlibs-scripts/ezfarms')
local ezweather = require('scripts/ezlibs-scripts/ezweather')
local ezwarps = require('scripts/ezlibs-scripts/ezwarps/main')
local ezencounters = require('scripts/ezlibs-scripts/ezencounters/main')
local helpers = require('scripts/ezlibs-scripts/helpers')
local custom = require('scripts/ezlibs-custom/custom')
local onceitem = require('scripts/events/eznpcs_onceitem')   -- loads the onceitem rental type
local teams = require('scripts/teams/teams')
local raids    = require('scripts/raids/raids')
local cosmetics = require('scripts/ezlibs-custom/cosmetics')
local ezmenus   = require('scripts/ezlibs-scripts/ezmenus')

local COSMETIC_SHOP_COLOR = { r = 245, g = 210, b = 70 } -- same yellow as decorshop

local sfx = {
    hurt = '/server/assets/ezlibs-assets/sfx/hurt.ogg',
    item_get = '/server/assets/ezlibs-assets/sfx/item_get.ogg',
    recover = '/server/assets/ezlibs-assets/sfx/recover.ogg',
    gibberish = '/server/assets/ezlibs-assets/sfx/gibberish.ogg',
    card_error = '/server/assets/ezlibs-assets/ezfarms/card_error.ogg'
}

local JobBBS = (function()
  local ok, M = pcall(require, 'scripts/jobbbs/JobBBS')
  if ok and M then return M end
  ok, M = pcall(require, 'scripts/jobbbs/jobbbs') -- fallback if name changes
  return ok and M or nil
end)()

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

local boss2 = {
    name="boss2",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    enemies={
        {name="HeelNavi",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,0,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local event2 = {
    name="Heel Navi1",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
        local stats = await(ezencounters.begin_encounter(player_id, boss2))
            if stats.ran or stats.health == 0 then
                return dialogue.custom_properties["Battle Lost"]
            else
                return dialogue.custom_properties["Battle Won"]
            end
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

local boss4 = {
    name="boss4",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    enemies={
        {name="ProtomanPoN",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,0,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    music={
        path="bn3_boss.mid"
    },
}

local event4 = {
    name="Proto Battle",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
        local stats = await(ezencounters.begin_encounter(player_id, boss4))
            if stats.ran or stats.health == 0 then
                return dialogue.custom_properties["Battle Lost"]
            else
                return dialogue.custom_properties["Battle Won"]
            end
        end)
    end
}
eznpcs.add_event(event4)

local boss5 = {
    name="boss5",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    enemies={
        {name="Roll",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,0,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    music={
        path="bn3_boss.mid"
    },
}

local event5 = {
    name="Roll Battle",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
        local stats = await(ezencounters.begin_encounter(player_id, boss5))
            if stats.ran or stats.health == 0 then
                return dialogue.custom_properties["Battle Lost"]
            else
                return dialogue.custom_properties["Battle Won"]
            end
        end)
    end
}
eznpcs.add_event(event5)

local boss6 = {
    name="boss6",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    enemies={
        {name="GutsManPoN",rank=2},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,0,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    music={
        path="bn3_boss.mid"
    },
}

local event6 = {
    name="Guts Battle",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
        local stats = await(ezencounters.begin_encounter(player_id, boss6))
            if stats.ran or stats.health == 0 then
                return dialogue.custom_properties["Battle Lost"]
            else
                return dialogue.custom_properties["Battle Won"]
            end
        end)
    end
}
eznpcs.add_event(event6)

local boss7 = {
    name="boss7",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    enemies={
        {name="GutsManPoN",rank=3},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,0,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    music={
        path="bn3_boss.mid"
    },
}

local event7 = {
    name="Guts3 Battle",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
        local stats = await(ezencounters.begin_encounter(player_id, boss7))
            if stats.ran or stats.health == 0 then
                return dialogue.custom_properties["Battle Lost"]
            else
                return dialogue.custom_properties["Battle Won"]
            end
        end)
    end
}
eznpcs.add_event(event7)

local boss8 = {
    name="boss8",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    enemies={
        {name="GregarBeast",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,0,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
        {1,1,1,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
    music={
        path="bn3_boss.mid"
    },
}

local event8 = {
    name="GregarB Battle",
    action=function (npc,player_id,dialogue,relay_object)
        return async(function()
        local stats = await(ezencounters.begin_encounter(player_id, boss8))
            if stats.ran or stats.health == 0 then
                return dialogue.custom_properties["Battle Lost"]
            else
                return dialogue.custom_properties["Battle Won"]
            end
        end)
    end
}
eznpcs.add_event(event8)

-- Weighted pick helper (number weights)
local function pick_weighted(entries)
    local total = 0
    for _, e in ipairs(entries or {}) do total = total + (tonumber(e.weight) or 0) end
    if total <= 0 then return nil end
    local roll, acc = math.random() * total, 0
    for _, e in ipairs(entries) do
        acc = acc + (tonumber(e.weight) or 0)
        if roll <= acc then return e end
    end
    return entries[#entries]
end

-- Case-insensitive props helpers
local function build_ci_props(dialogue)
    local ci = {}
    for k, v in pairs(dialogue.custom_properties or {}) do
        ci[string.lower(tostring(k))] = v
    end
    return ci
end
local function get_ci(ci, key) return ci[string.lower(key)] end
local function extract_seq_ci(ci, prefix_lc)
    local out, i = {}, 1
    while true do
        local v = ci[prefix_lc .. i]
        if v == nil then break end
        table.insert(out, v)
        i = i + 1
    end
    return out
end

-- Parse single pack + rarity groups
local function read_single_pack(dialogue)
    local ci = build_ci_props(dialogue)

    local name  = get_ci(ci, "pack name")
    if not name then return nil end
    local price = tonumber(get_ci(ci, "pack price")) or 0
    local rolls = tonumber(get_ci(ci, "pack rolls")) or 1
    local desc  = get_ci(ci, "pack description") or ("Contains "..rolls.." random card(s).")

    local pools = {
      { label = "Common",     items = extract_seq_ci(ci, "common "),     rate = tonumber(get_ci(ci, "common rate"))     },
      { label = "Rare",       items = extract_seq_ci(ci, "rare "),       rate = tonumber(get_ci(ci, "rare rate"))       },
      { label = "Super Rare", items = extract_seq_ci(ci, "super rare "), rate = tonumber(get_ci(ci, "super rare rate")) },
      { label = "Ultra Rare", items = extract_seq_ci(ci, "ultra rare "), rate = tonumber(get_ci(ci, "ultra rare rate")) },
      { label = "Gold Rare",  items = extract_seq_ci(ci, "gold rare "),  rate = tonumber(get_ci(ci, "gold rare rate"))  },
      { label = "Ghost Rare", items = extract_seq_ci(ci, "ghost rare "), rate = tonumber(get_ci(ci, "ghost rare rate")) },
    }

    -- Default rates if none set
    local any_rate = false
    for _, p in ipairs(pools) do if (p.rate or 0) > 0 then any_rate = true break end end
    if not any_rate then
      local has_gdr = pools[5].items and #pools[5].items > 0
      local has_gr  = pools[6].items and #pools[6].items > 0
      if has_gdr or has_gr then
        pools[1].rate, pools[2].rate, pools[3].rate, pools[4].rate = 753, 207, 30, 9
        pools[5].rate = has_gdr and 1 or 0
        pools[6].rate = has_gr  and 1 or 0
      else
        pools[1].rate, pools[2].rate, pools[3].rate, pools[4].rate = 70, 25, 4, 1
      end
    end

    -- Keep only pools that have items and a positive rate
    local groups = {}
    for _, p in ipairs(pools) do
        if p.items and #p.items > 0 and (p.rate or 0) > 0 then
            table.insert(groups, { label = p.label, items = p.items, weight = p.rate })
        end
    end

    return { name = name, price = price, rolls = rolls, description = desc, groups = groups }
end

-- Grant items for one pack (spending handled elsewhere)
local function grant_one_pack(player_id, area_id, pack, names_acc)
    for _ = 1, (pack.rolls or 1) do
        local group = pick_weighted(pack.groups or {})
        if not group then return end
        local items = group.items
        if not items or #items == 0 then return end
        local idx = math.random(1, #items)
        local obj_id = items[idx]
        local info = helpers.read_item_information(area_id, obj_id)
        if info then
            await(ezmemory.give_item_with_optional_notify(player_id, area_id, obj_id, info, false))
            table.insert(names_acc, info.name)
        end
    end
end

-- Open exactly one pack: spend, grant, popup
local function open_one_pack(player_id, area_id, pack, mug)
    if not ezmemory.spend_player_money(player_id, pack.price or 0) then
        return false, "You don't have enough money."
    end
    local gained = {}
    grant_one_pack(player_id, area_id, pack, gained)
    if sfx and sfx.item_get then Net.play_sound_for_player(player_id, sfx.item_get) end
    await(Async.message_player(
        player_id,
        (#gained > 0)
            and string.format("Opened %s and got:\n- %s", pack.name, table.concat(gained, "\n- "))
            or string.format("Opened %s... but it was empty?", pack.name),
        mug.texture_path, mug.animation_path
    ))
    if JobBBS and JobBBS.on_pack_open then
      pcall(JobBBS.on_pack_open, player_id, { count = 1, pack = pack.name })
    end
    return true
end

-- Open N packs at once: charge upfront; aggregate by name; one popup
local function open_n_packs(player_id, area_id, pack, mug, n)
    n = n or 10
    local total_cost = (pack.price or 0) * n
    if total_cost < 0 then total_cost = 0 end
    if not ezmemory.spend_player_money(player_id, total_cost) then
        return false, "You don't have enough money."
    end

    local counts, order = {}, {}
    for _ = 1, n do
        local names = {}
        grant_one_pack(player_id, area_id, pack, names)
        for _, name in ipairs(names) do
            if not counts[name] then
                counts[name] = 1
                table.insert(order, name)
            else
                counts[name] = counts[name] + 1
            end
        end
    end

    if sfx and sfx.item_get then Net.play_sound_for_player(player_id, sfx.item_get) end

    local lines = {}
    for _, name in ipairs(order) do
        table.insert(lines, string.format("x%d %s", counts[name], name))
    end
    local header = string.format("Opened %d x %s and got:", n, pack.name)
    local body = (#lines > 0) and (header.."\n- "..table.concat(lines, "\n- ")) or (header.."\n(nothing?)")
    await(Async.message_player(player_id, body, mug.texture_path, mug.animation_path))
    if JobBBS and JobBBS.on_pack_open then
      pcall(JobBBS.on_pack_open, player_id, { count = n, pack = pack.name })
    end
    return true
end

local function short_money(n)
    n = tonumber(n) or 0
    local abs = math.abs(n)
    if abs >= 1e9 then
        return string.format("$%dB", math.floor(n/1e9 + 0.5))
    elseif abs >= 1e6 then
        local v = n/1e6
        if v >= 10 or v == math.floor(v) then
            return string.format("$%dM", math.floor(v + 0.5))
        else
            return string.format("$%.1fM", v)
        end
    elseif abs >= 1e3 then
        local v = n/1e3
        if v >= 10 or v == math.floor(v) then
            return string.format("$%dk", math.floor(v + 0.5))
        else
            return string.format("$%.1fk", v)
        end
    else
        return string.format("$%d", n)
    end
end

-- 3-option chooser: Buy 1 / Buy 10 / Cancel (B acts as Cancel in quiz); fallback to Yes/No if needed
local function choose_buy_quantity(player_id, mug, pack)
    local p = tonumber(pack.price or 0)
    local opt1 = string.format("Buy 1 (%s)",  short_money(p))
    local opt2 = string.format("Buy 10 (%s)", short_money(p * 10))
    local opt3 = "Cancel"

    -- Primary path: 3-option cursor selection
    local res = await(Async.quiz_player(player_id, opt1, opt2, opt3, mug.texture_path, mug.animation_path))
    -- quiz_player returns 0/1/2
    if res == 0 then return 1 end
    if res == 1 then return 10 end
    if res == 2 then return nil end

    -- Fallback: two Yes/No prompts (B behaves as No)
    local buy1 = await(Async.question_player(player_id, opt1.."?",
                    mug.texture_path, mug.animation_path))
    if buy1 then return 1 end

    local buy10 = await(Async.question_player(player_id, opt2.."?",
                    mug.texture_path, mug.animation_path))
    if buy10 then return 10 end

    return nil
end

local function pack_shop_action(npc, player_id, dialogue, relay_object)
    return async(function ()
        local area_id = Net.get_player_area(player_id)
        local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
        local pack = read_single_pack(dialogue)

        if not pack or not pack.groups or #pack.groups == 0 then
            await(Async.message_player(player_id, "Sorry, I'm not selling any packs right now.", mug.texture_path, mug.animation_path))
            return dialogue.custom_properties["Next 1"]
        end

        -- Intro once
        local rolls = pack.rolls or 1
        local suffix = (rolls == 1) and "card" or "cards"
        await(Async.message_player(
            player_id,
            string.format("%s - %d$ (%d %s)\n\n%s", pack.name, pack.price or 0, rolls, suffix, pack.description or ""),
            mug.texture_path, mug.animation_path
        ))

        -- First purchase (1/10/Cancel)
        local qty = choose_buy_quantity(player_id, mug, pack)
        if not qty then
            return dialogue.custom_properties["Next 1"]
        end

        local ok, msg
        if qty == 1 then
            ok, msg = open_one_pack(player_id, area_id, pack, mug)
        else
            ok, msg = open_n_packs(player_id, area_id, pack, mug, 10)
        end
        if not ok then
            if msg then await(Async.message_player(player_id, msg, mug.texture_path, mug.animation_path)) end
            return dialogue.custom_properties["Next 1"]
        end

        -- Loop: offer 1/10/Cancel again
        while true do
            local qty2 = choose_buy_quantity(player_id, mug, pack)
            if not qty2 then break end

            local ok2, msg2
            if qty2 == 1 then
                ok2, msg2 = open_one_pack(player_id, area_id, pack, mug)
            else
                ok2, msg2 = open_n_packs(player_id, area_id, pack, mug, 10)
            end

            if not ok2 then
                if msg2 then await(Async.message_player(player_id, msg2, mug.texture_path, mug.animation_path)) end
                break
            end
        end

        return dialogue.custom_properties["Next 1"]
    end)
end

-- Register (exact name)
eznpcs.add_event{ name = "Pack Shop", action = pack_shop_action }

local function ci_props(dialogue)
  local ci = {}; for k,v in pairs(dialogue.custom_properties or {}) do ci[string.lower(tostring(k))] = v end; return ci
end
local function get(ci,k) return ci[string.lower(k)] end
local function seq(ci,prefix) local out,i={},1; while true do local v=ci[prefix..i]; if v==nil then break end; out[#out+1]=v; i=i+1 end; return out end

local function read_groups(dialogue)
  local ci = ci_props(dialogue)
  local pools = {
    { label="Common",     items=seq(ci,"common "),     weight=tonumber(get(ci,"common rate"))     },
    { label="Rare",       items=seq(ci,"rare "),       weight=tonumber(get(ci,"rare rate"))       },
    { label="Super Rare", items=seq(ci,"super rare "), weight=tonumber(get(ci,"super rare rate")) },
    { label="Ultra Rare", items=seq(ci,"ultra rare "), weight=tonumber(get(ci,"ultra rare rate")) },
    { label="Gold Rare",  items=seq(ci,"gold rare "),  weight=tonumber(get(ci,"gold rare rate"))  },
    { label="Ghost Rare", items=seq(ci,"ghost rare "), weight=tonumber(get(ci,"ghost rare rate")) },
  }
  local any=false; for _,p in ipairs(pools) do if (p.weight or 0) > 0 then any=true break end end
  if not any then
    local has_gdr = pools[5].items and #pools[5].items > 0
    local has_gr  = pools[6].items and #pools[6].items > 0
    if has_gdr or has_gr then
      pools[1].weight,pools[2].weight,pools[3].weight,pools[4].weight = 753,207,30,9
      pools[5].weight = has_gdr and 1 or 0
      pools[6].weight = has_gr  and 1 or 0
    else
      pools[1].weight,pools[2].weight,pools[3].weight,pools[4].weight = 70,25,4,1
    end
  end
  local groups = {}
  for _,p in ipairs(pools) do
    if p.items and #p.items>0 and (p.weight or 0)>0 then groups[#groups+1]=p end
  end
  return groups
end

eznpcs.add_event{
  name = "Card Trader",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
      local groups = read_groups(dialogue)
      if not groups or #groups == 0 then
        await(Async.message_player(player_id, "Trader is misconfigured: no return pools.", mug.texture_path, mug.animation_path))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end
      local desc = (dialogue.custom_properties and (dialogue.custom_properties["pack description"] or dialogue.custom_properties["Pack Description"])) or
                   "Trade any 10 cards and I'll give you 1 random card."
      -- Kick off the board-driven picker; the BBS plugin handles the rest
      custom.start_card_trade(player_id, { desc = desc, groups = groups })
      -- Optionally show their mug once before opening the board:
      await(Async.message_player(player_id, "Let's trade - pick exactly 10 cards.", mug.texture_path, mug.animation_path))
      return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
    end)
  end
}

eznpcs.add_event{
  name = "Card Battle (NPC)",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
      await(Async.message_player(
        player_id,
        "Let's duel! I'll build decks from your collection.\n(10 cards; UR/GDR=1, SR≤2, R≤3, C=any)",
        mug.texture_path, mug.animation_path
      ))

      local npc_name =
        (dialogue and dialogue.custom_properties and
         (dialogue.custom_properties["NPC Name"] or dialogue.custom_properties["Npc Name"])) or "NPC Duelist"

      -- We’ll wait for this to flip true
      local done, result = false, nil

      local ci = build_ci_props(dialogue)
      -- Accept either “Deck 1..10” or (fallback) “Card 1..10”
      local deck_ids = extract_seq_ci(ci, "deck ")
      if #deck_ids == 0 then
        deck_ids = extract_seq_ci(ci, "card ")
      end
      -- Optional: enforce exactly 10; otherwise leave nil to fall back to random
      if #deck_ids ~= 10 then deck_ids = nil end

      -- Start the duel and inject an on_finish that completes our wait
      custom.start_card_battle(player_id, {
        npc_name = npc_name,
        npc_deck_ids = deck_ids,
        on_finish = function(res)
          result = res
          done   = true
        end
      })

      -- tick helper that always returns a real awaitable
      local function _tick()
        if Async.sleep_frames then return Async.sleep_frames(1) end
        if Async.sleep        then return Async.sleep(0.016) end
        -- fall back to deferring one turn; ezlibs usually supports this
        return Async.defer()
      end

      -- Wait here until on_finish runs
      while not done do
        await(_tick())
      end

      if result and result.player_won then
        return dialogue.custom_properties["Battle Won"]
      else
        return dialogue.custom_properties["Battle Lost"]
      end
    end)
  end
}

local event_hp_warp = {
  name = "HP Warp",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function ()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)

      local prompt = dialogue.custom_properties["Prompt"] or "Which HP would you like to visit?"
      await(Async.message_player(player_id, prompt, mug.texture_path, mug.animation_path))

      -- Free-text input (player can type a number)
      local raw = await(Async.prompt_player(player_id))
      if raw == nil or raw == "" then
        return dialogue.custom_properties["On Cancel"] or dialogue.custom_properties["Next 2"]
      end

      -- Extract first number from the input
      local n = tonumber(tostring(raw):match("%d+"))
      local min = tonumber(dialogue.custom_properties["Min"]) or 1
      local max = tonumber(dialogue.custom_properties["Max"]) or 999
      if not n or n < min or n > max then
        local msg = dialogue.custom_properties["Invalid Msg"] or "That's not a valid HP."
        await(Async.message_player(player_id, msg, mug.texture_path, mug.animation_path))
        return dialogue.custom_properties["On Invalid"] or dialogue.custom_properties["Next 2"]
      end

      -- Build the landing key string
      local pad = tonumber(dialogue.custom_properties["Pad"]) or 0
      local nn  = (pad > 0) and string.format("%0"..pad.."d", n) or tostring(n)
      local tpl = dialogue.custom_properties["Data Template"] or "HP {n}"
      local data = tpl:gsub("{n}", nn)

      print(string.format("[HPWarp] pid=%s input=%s -> landing='%s'", tostring(player_id), tostring(raw), data))

      -- Hand off to ezwarps (will transfer immediately if it finds the landing) 
      ezwarps.handle_player_request(player_id, data)

      -- We end the dialogue here (warp happens or ezwarps logs “no landing” if missing)
      return nil
    end)
  end
}
eznpcs.add_event(event_hp_warp)

eznpcs.add_event{
  name = "cosmeticshop",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)

      -- Safety check: cosmetics module available?
      if not cosmetics or not cosmetics.unlock_for_player then
        await(Async.message_player(
          player_id,
          "Cosmetics system is not available right now.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      -- Lowercased custom props helper (already used by Pack Shop)
      local function ci_props(d)
        local ci = {}
        for k, v in pairs(d.custom_properties or {}) do
          ci[string.lower(tostring(k))] = v
        end
        return ci
      end

      local ci = ci_props(dialogue)

      -- Build the list of offers from Sell N / Price N
      local offers = {}
      local i = 1
      while true do
        local sell = ci["sell " .. i]
        if not sell then break end

        local price_raw = ci["price " .. i] or ci["cost " .. i]
        local price = tonumber(price_raw) or 0
        if price < 0 then price = 0 end

        local cosmetic_id = tostring(sell)
        local name = cosmetics.get_name_for_id
                    and cosmetics.get_name_for_id(cosmetic_id)
                    or cosmetic_id

        table.insert(offers, {
          cosmetic_id = cosmetic_id,
          price       = price,
          name        = name,
        })

        i = i + 1
      end

      if #offers == 0 then
        await(Async.message_player(
          player_id,
          "Sorry, I'm not selling any cosmetics right now.",
          mug.texture_path, mug.animation_path
        ))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      -- Shop loop (BBS board)
      while true do
        -- Build BBS posts fresh each time so "Owned" tags update after purchases
        local posts, items = {}, {}
        for _, offer in ipairs(offers) do
          local owned = cosmetics.has_cosmetic
                     and cosmetics.has_cosmetic(player_id, offer.cosmetic_id)
          local label = owned
            and string.format("%s (%s, Owned)", offer.name, short_money(offer.price))
            or  string.format("%s (%s)",        offer.name, short_money(offer.price))

          local post = helpers.create_bbs_option(label)
          table.insert(posts, post)
          items[#posts] = offer
        end

        -- Open BBS-style board
        local board = ezmenus.open_menu(
          player_id,
          "Cosmetic Shop",
          COSMETIC_SHOP_COLOR,
          posts
        )

        local sel = await(board.selection_once())
        Net.close_bbs(player_id)  -- close board after selection / cancel

        if not sel then break end  -- B pressed / closed

        -- Find which offer was chosen
        local chosen
        for idx, post in ipairs(posts) do
          local pid = post.id or post.title or ""
          if sel == pid then
            chosen = items[idx]
            break
          end
        end
        if not chosen then break end

        -- Already owned? Block re-purchase.
        if cosmetics.has_cosmetic and cosmetics.has_cosmetic(player_id, chosen.cosmetic_id) then
          await(Async.message_player(
            player_id,
            "You already have the " .. chosen.name .. " cosmetic.",
            mug.texture_path, mug.animation_path
          ))
        else
          -- Yes/No confirmation (single quantity)
          local question = string.format(
            "Buy %s for %s?",
            chosen.name,
            short_money(chosen.price)
          )

          local do_buy = await(Async.question_player(
            player_id,
            question,
            mug.texture_path, mug.animation_path
          ))

          if do_buy then
            local price = chosen.price or 0

            -- Paid cosmetic
            if price > 0 then
              if not ezmemory.spend_player_money(player_id, price) then
                await(Async.message_player(
                  player_id,
                  "You don't have enough money.",
                  mug.texture_path, mug.animation_path
                ))
              else
                local ok, reason = cosmetics.unlock_for_player(player_id, chosen.cosmetic_id)
                if ok then
                  if sfx and sfx.item_get then
                    Net.play_sound_for_player(player_id, sfx.item_get)
                  end
                  await(Async.message_player(
                    player_id,
                    "You got the " .. chosen.name .. " cosmetic!",
                    mug.texture_path, mug.animation_path
                  ))
                else
                  await(Async.message_player(
                    player_id,
                    "Couldn't unlock that cosmetic (" .. tostring(reason or "error") .. ").",
                    mug.texture_path, mug.animation_path
                  ))
                end
              end

            -- Free cosmetic
            else
              local ok, reason = cosmetics.unlock_for_player(player_id, chosen.cosmetic_id)
              if ok then
                if sfx and sfx.item_get then
                  Net.play_sound_for_player(player_id, sfx.item_get)
                end
                await(Async.message_player(
                  player_id,
                  "You got the " .. chosen.name .. " cosmetic!",
                  mug.texture_path, mug.animation_path
                ))
              else
                await(Async.message_player(
                  player_id,
                  "Couldn't unlock that cosmetic (" .. tostring(reason or "error") .. ").",
                  mug.texture_path, mug.animation_path
                ))
              end
            end
          end
        end

        -- loop continues until player cancels / closes the board
      end

      return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
    end)
  end
}

eznpcs.add_event{
  name = "decorclear",
  action = function(npc, player_id, dialogue, relay_object)
    return async(function()
      local mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)

      if not cosmetics or not cosmetics.clear_all_for_player then
        await(Async.message_player(player_id,
          "Cosmetics system is not available.",
          mug.texture_path, mug.animation_path))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      local prompt = (dialogue.custom_properties and dialogue.custom_properties["Prompt"])
                  or "Clear ALL your cosmetics and unequip them?"

      local confirm = true
      if Async.question_player then
        confirm = await(Async.question_player(player_id,
          prompt, mug.texture_path, mug.animation_path))
      end

      if not confirm then
        await(Async.message_player(player_id,
          "Okay, leaving your cosmetics as-is.",
          mug.texture_path, mug.animation_path))
        return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
      end

      cosmetics.clear_all_for_player(player_id)

      await(Async.message_player(player_id,
        "All cosmetics cleared for this account.\nYou can re-purchase them in the shop.",
        mug.texture_path, mug.animation_path))

      return dialogue.custom_properties and dialogue.custom_properties["Next 1"]
    end)
  end
}
