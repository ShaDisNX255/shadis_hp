
local helpers = require('scripts/ezlibs-scripts/helpers')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local ezquests = require('scripts/ezlibs-scripts/ezquests')
local ezemail = require('scripts/ezlibs-scripts/ezemail')
local whitelist = require('scripts/ezlibs-custom/whitelist')
local NG_SHOP_ITEM_GET_SFX = "/server/assets/ezlibs-assets/sfx/item_get.ogg"
local SUCCESS_SFX = "/server/assets/sfx/compile_complete.ogg"
local FAIL_SFX = "/server/assets/sfx/card_error.ogg"

local function trim_string(value)
    if value == nil then return nil end
    local text = tostring(value)
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    return text
end

local function get_case_insensitive_property(props, wanted_key)
    if not props then return nil end

    wanted_key = tostring(wanted_key):lower()

    for key, value in pairs(props) do
        if tostring(key):lower() == wanted_key then
            return value
        end
    end

    return nil
end

local function get_dialogue_chip_keys(dialogue)
    local props = dialogue.custom_properties or {}
    local keys = {}

    local single = trim_string(get_case_insensitive_property(props, "Chip"))
    if single then
        keys[#keys + 1] = single
    end

    local numbered_chips = helpers.extract_numbered_properties(dialogue, "Chip ")
    for _, chip_key in ipairs(numbered_chips) do
        chip_key = trim_string(chip_key)
        if chip_key then
            keys[#keys + 1] = chip_key
        end
    end

    return keys
end

local function get_chip_display_name(card_def, fallback_key)
    if card_def then
        if card_def.name then
            return tostring(card_def.name)
        end

        if card_def.display_name then
            return tostring(card_def.display_name)
        end

        -- Prefer asset filename because package IDs sometimes use internal names.
        -- Example: /server/assets/chips/EXEPoN-Shockwave.zip -> Shockwave
        local asset_path = tostring(card_def.asset_path or "")
        local file = asset_path:match("([^/\\]+)$")
        if file and file ~= "" then
            file = file:gsub("%.zip$", "")
            file = file:gsub("^EXE%d+%-", "")
            file = file:gsub("^EXEPoN%-", "")
            file = file:gsub("^BN%d+%-", "")
            if file ~= "" then
                return file
            end
        end

        local package_id = tostring(card_def.package_id or "")
        local package_name = package_id:match("([^%.%-]+)$")
        if package_name and package_name ~= "" then
            return package_name
        end
    end

    return tostring(fallback_key or "BattleChip")
end

local function stop_chip_item_get_anim(player_id)
    local direction = nil

    -- Prefer the server's current player direction if available.
    if Net.get_player_direction then
        local ok, result = pcall(Net.get_player_direction, player_id)
        if ok then
            direction = result
        end
    end

    -- Fallback in case this server build doesn't expose get_player_direction.
    if not direction or direction == "" then
        direction = "Down"
    end

    if ezmemory.set_direction_anim then
        pcall(ezmemory.set_direction_anim, player_id, direction)
    else
        pcall(Net.animate_player, player_id, "IDLE_D", true)
    end
end

local function notify_chip_get(player_id, chip_name, notify_player)
    return async(function()
        if notify_player ~= true then
            return
        end

        if NG_SHOP_ITEM_GET_SFX then
            pcall(Net.provide_asset_for_player, player_id, NG_SHOP_ITEM_GET_SFX)
            pcall(Net.play_sound_for_player, player_id, NG_SHOP_ITEM_GET_SFX)
        end

        local started_anim = false

        if ezmemory.play_anim_get then
            local ok = pcall(ezmemory.play_anim_get, player_id)
            started_anim = ok
        end

        await(Async.message_player(player_id, "Got " .. tostring(chip_name) .. "!"))

        if started_anim then
            stop_chip_item_get_anim(player_id)
        end
    end)
end

local function play_dialogue_sfx_for_player(player_id, sfx_path)
    if not sfx_path or sfx_path == "" then
        return
    end

    if Net.provide_asset_for_player then
        pcall(Net.provide_asset_for_player, player_id, sfx_path)
    end

    if Net.play_sound_for_player then
        pcall(Net.play_sound_for_player, player_id, sfx_path)
    end
end

--=====================================================
-- net-games UI warm-up (pre-provide talk/menu assets on login)
--=====================================================
if not _G.__EZNG_UI_WARMUP_HOOKED then
  _G.__EZNG_UI_WARMUP_HOOKED = true

  local function safe_has_asset(path)
    if not path or path == "" then return false end
    if not (Net and Net.has_asset) then return true end
    local ok, res = pcall(Net.has_asset, path)
    return ok and res == true
  end

  local function safe_provide(pid, path)
    if not (Net and Net.provide_asset_for_player) then return end
    -- IMPORTANT: never provide a missing asset; it can hard-crash the server.
    if not safe_has_asset(path) then return end
    pcall(Net.provide_asset_for_player, pid, path)
  end

  local function list_dir_files(fs_dir)
    local out = {}
    local is_win = package.config:sub(1,1) == "\\"
    local cmd
    if is_win then
      local d = fs_dir:gsub("/", "\\")
      cmd = 'dir /b "' .. d .. '\\*"'
    else
      cmd = 'ls -1 "' .. fs_dir .. '" 2>/dev/null'
    end

    local pp = io.popen(cmd)
    if not pp then return out end

    for line in pp:lines() do
      local name = (line or ""):gsub("\r", "")
      if name ~= "" then
        table.insert(out, name)
      end
    end
    pp:close()
    return out
  end

  local function safe_provide_dir(pid, fs_dir, asset_prefix, allow_ext)
    allow_ext = allow_ext or { png=true, animation=true, ogg=true, wav=true }
    for _, name in ipairs(list_dir_files(fs_dir)) do
      local ext = name:match("%.([%w]+)$")
      ext = ext and ext:lower() or nil
      if ext and allow_ext[ext] then
        safe_provide(pid, asset_prefix .. name)
      end
    end
  end

  Net:on("player_join", function(event)
    local pid = event.player_id
    if not pid then return end

    -- net-games UI (menus + textbox backdrops usually live here)
    safe_provide_dir(pid, "assets/net-games/ui",      "/server/assets/net-games/ui/")
    safe_provide_dir(pid, "assets/net-games/cursors", "/server/assets/net-games/cursors/")
    safe_provide_dir(pid, "assets/net-games/displayer", "/server/assets/net-games/displayer/")
    safe_provide_dir(pid, "assets/net-games/sfx",     "/server/assets/net-games/sfx/")

    -- PROG prompt mug/nameplate used by TalkPresets
    safe_provide_dir(pid, "assets/ow/prog", "/server/assets/ow/prog/", { png=true, animation=true })

    -- Give the client time to download the UI assets, then "touch" them by alloc+draw offscreen
    _G.__EZNG_UI_PREWARM_DONE = _G.__EZNG_UI_PREWARM_DONE or {}
    if not _G.__EZNG_UI_PREWARM_DONE[pid] then
      async(function()
        await(Async.sleep(1.0))

        local function safe_alloc_draw(sprite_id, tex, anim, state)
          if not safe_has_asset(tex) then return end
          if anim and not safe_has_asset(anim) then return end

          if anim then
            pcall(Net.player_alloc_sprite, pid, sprite_id, {
              texture_path = tex,
              anim_path = anim,
              anim_state = state or "OPEN_IDLE",
            })
          else
            pcall(Net.player_alloc_sprite, pid, sprite_id, { texture_path = tex })
          end

          -- Draw offscreen so the client actually resolves it this session
          pcall(Net.player_draw_sprite, pid, sprite_id, {
            id = "__ezng_prewarm_draw_" .. sprite_id,
            x = -1000, y = -1000, z = 0,
            sx = 2.0, sy = 2.0,
            anim_state = state,
          })
        end

        local ANIM = "/server/assets/net-games/ui/prompt_vert_menu_an.animation"

        safe_alloc_draw("__ezng_pre_menu_bg",      "/server/assets/net-games/ui/prompt_vert_menu_an.png",        ANIM, "OPEN_IDLE")
        safe_alloc_draw("__ezng_pre_menu_bg_shop", "/server/assets/net-games/ui/prompt_vert_menu_shop_an.png",   ANIM, "OPEN_IDLE")
        safe_alloc_draw("__ezng_pre_menu_frame",   "/server/assets/net-games/ui/prompt_vert_menu_an_frame.png",  ANIM, "OPEN_IDLE")
        safe_alloc_draw("__ezng_pre_menu_frame_shop","/server/assets/net-games/ui/prompt_vert_menu_shop_an_frame.png", ANIM, "OPEN_IDLE")

        safe_alloc_draw("__ezng_pre_highlight",     "/server/assets/net-games/ui/highlight_default.png")
        safe_alloc_draw("__ezng_pre_highlight_shop","/server/assets/net-games/ui/highlight_shop.png")
        safe_alloc_draw("__ezng_pre_cursor",        "/server/assets/net-games/cursors/green_cursor.png")
        safe_alloc_draw("__ezng_pre_scroll",        "/server/assets/net-games/ui/scrollbar.png")

        safe_alloc_draw("__ezng_pre_shop_item",     "/server/assets/net-games/ui/card_shop_item.png")
        safe_alloc_draw("__ezng_pre_shop_exit",     "/server/assets/net-games/ui/card_shop_exit.png")

        _G.__EZNG_UI_PREWARM_DONE[pid] = true
      end)
    end
  end)
end


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
    chipcheck={
        name = 'chipcheck',
        action = function(npc, player_id, dialogue, relay_object)
            return async(function ()
                local next_dialogues = helpers.extract_numbered_properties(dialogue,"Next ")
                local chip_keys = get_dialogue_chip_keys(dialogue)

                if #chip_keys == 0 then
                    warn("[eznpcs] chipcheck missing Chip/Card/Package Id on dialogue node", dialogue.id)
                    return next_dialogues[2] or next_dialogues[1]
                end

                local check_passed = true

                for _, chip_key in ipairs(chip_keys) do
                    local has_chip, card_def = whitelist.player_has_card_unlocked(player_id, chip_key)

                    if not card_def then
                        warn("[eznpcs] chipcheck unknown battle chip", tostring(chip_key), "on dialogue node", dialogue.id)
                        check_passed = false
                    elseif not has_chip then
                        check_passed = false
                    end
                end

                return next_dialogues[check_passed and 1 or 2]
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
    ng_shop = {
      name = "ng_shop",
      action = function(npc, player_id, dialogue, relay_object)
        return async(function()
          local area_id = Net.get_player_area(player_id)

          -- If net-games isn’t installed, fall back to the stock ezmemory shop.
          local ok_menu, TalkVertMenu_or_err = pcall(require, "scripts/net-games/npcs/talk_vert_menu")
          if not ok_menu then
            print("[ng_shop] failed to load talk_vert_menu:", TalkVertMenu_or_err)

            -- fallback to old shop...
            local mugshot = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
            local shop_items = {}
            local ids = helpers.extract_numbered_properties(dialogue, "Item ")
            for _, oid in ipairs(ids) do
              local info = helpers.read_item_information(area_id, oid)
              if info then
                table.insert(shop_items, {
                  name = info.name,
                  price = info.price,
                  description = info.description or "???",
                  is_key = info.type == "keyitem"
                })
              end
            end
            await(ezmemory.open_shop_async(player_id, shop_items, mugshot.texture_path, mugshot.animation_path))
            return first_value_from_table(helpers.extract_numbered_properties(dialogue, "Next "))
          end

          local TalkVertMenu = TalkVertMenu_or_err
          local ok_presets, TalkPresets_or_err = pcall(require, "scripts/net-games/npcs/talk_presets")
          if not ok_presets then
            print("[ng_shop] failed to load talk_presets:", TalkPresets_or_err)
            -- If you want, you can fallback to old shop UI here like you do above.
            return first_value_from_table(helpers.extract_numbered_properties(dialogue, "Next "))
          end
          local TalkPresets = TalkPresets_or_err

          -- Build a PROG-style mugshot, but swap texture/anim to match eznpcs Asset Name/Mugshot.
          local ez_mug = eznpcs.get_dialogue_mugshot(npc, player_id, dialogue)
          local mug = helpers.deep_copy(TalkPresets.mugs.prog or { enabled = true })
          mug.texture_path = ez_mug.texture_path
          mug.anim_path = ez_mug.animation_path
          mug.sprite_id = nil

          -- Build item options from Item # properties (same as eznpcs shop)
          local ids = helpers.extract_numbered_properties(dialogue, "Item ")
          local options = {}
          local by_id = {}

          for _, oid in ipairs(ids) do
            local info = helpers.read_item_information(area_id, oid)
            if info and info.name and info.price then
              local price = tonumber(info.price) or 0
              local id = tostring(oid)

              options[#options+1] = {
                id = id,
                text = string.format("%s  %d$", tostring(info.name), price), -- fallback if columns disabled
                shop_name = tostring(info.name),
                shop_price = tonumber(price) or 0,
              }

              by_id[id] = {
                object_id = oid,
                info = info,
                price = price,
                is_key = (info.type == "keyitem"),
              }
            end
          end

          options[#options+1] = { id = "exit", text = "Exit" }
          local exit_index = #options

          -- Card filename index (case-insensitive) using your cards_list.txt if present
          local function build_cards_index()
            local map = {}

            local function add_file(file)
              file = (file or ""):gsub("\r", "")
              if file:match("%.png$") then
                local base = file:gsub("%.png$", "")
                map[base:lower()] = file
              end
            end

            local tried = {
              "assets/cards/cards_list.txt",
              "assets/cards_list.txt",
            }

            for _, p in ipairs(tried) do
              local f = io.open(p, "r")
              if f then
                for line in f:lines() do add_file(line) end
                f:close()
                return map
              end
            end

            -- Fallback: directory listing
            local is_win = package.config:sub(1,1) == "\\"
            local cmd = is_win and 'dir /b "assets\\cards\\*.png"' or 'ls -1 "assets/cards"/*.png 2>/dev/null'
            local pp = io.popen(cmd)
            if pp then
              for line in pp:lines() do
                local file = (line or ""):match("([^/\\\\]+)$") or line
                add_file(file)
              end
              pp:close()
            end

            return map
          end

          local cards_index = build_cards_index()

          local function strip_tag(name)
            name = tostring(name or "")
            name = name:gsub("^%[[^%]]+%]%s*", "") -- remove leading [C]/[UR]/etc
            name = name:gsub("%s+", "")            -- remove spaces
            return name
          end

          local DEFAULT_ICON = "/server/assets/net-games/ui/card_shop_item.png"

          local icon_by_choice = {}
          for id, rec in pairs(by_id) do
            local raw = tostring(rec.info.name or "")
            if raw:match("^%[[^%]]+%]") then
              local base = strip_tag(raw)
              local file = cards_index[base:lower()] or (base .. ".png")
              icon_by_choice[id] = "/server/assets/cards/" .. file
            else
              icon_by_choice[id] = DEFAULT_ICON
            end
          end

          -- Pre-provide icons to avoid stutter while scrolling
          local function safe_has_asset(path)
            if not path or path == "" then return false end
            if not (Net and Net.has_asset) then return true end
            local ok, res = pcall(Net.has_asset, path)
            return ok and res == true
          end

          if Net and Net.provide_asset_for_player then
            for _, path in pairs(icon_by_choice) do
              if safe_has_asset(path) then
                pcall(Net.provide_asset_for_player, player_id, path)
              end
            end
          end

          local talk_cfg = {
            preset = "prog_prompt",
            area_id = area_id,
            object = "ng_shop_" .. tostring(dialogue.id or "shop"),
            ui = {
              mugshot = mug,
              typing_speed = 9999,
            }
          }

          local layout = TalkPresets.get_vert_menu_layout("prog_prompt_shop") or {}

          local assets = {
            menu_bg       = "/server/assets/net-games/ui/prompt_vert_menu_shop_an.png",
            menu_bg_anim  = "/server/assets/net-games/ui/prompt_vert_menu_an.animation",
            menu_bg_frame = "/server/assets/net-games/ui/prompt_vert_menu_shop_an_frame.png",
            highlight     = "/server/assets/net-games/ui/highlight_shop.png",
          }

          TalkVertMenu.open(player_id, npc.name or "SHOP", talk_cfg, {
            intro_text = "What would you like?",
            options = options,
            exit_index = exit_index,
            layout = layout,
            assets = assets,

            monies_amount_fn = function(pid)
              return tostring(Net.get_player_money(pid) or 0) .. "$"
            end,

            shop_item_texture_fn = function(choice)
              if not choice or not choice.id then return DEFAULT_ICON end
              return icon_by_choice[tostring(choice.id)] or DEFAULT_ICON
            end,

            flow = {
              keep_menu_open = true,
              after_text = "Anything else?",
              exit_goodbye_text = "Come again!",

              confirm = {
                enabled = true,
                skip_ids = { exit = true },
                text_fn = function(pid, choice_id)
                  local rec = by_id[tostring(choice_id)]
                  if not rec then return "Buy this?" end
                  local have = tonumber(Net.get_player_money(pid) or 0) or 0
                  return string.format("Buy %s for %d$?\nYou have %d$", tostring(rec.info.name), rec.price, have)
                end,
              },

              post_select = { enabled = true, skip_ids = { exit = true } },
            },

            on_confirm_yes = function(pid, choice_id, _choice_text, menu)
              local rec = by_id[tostring(choice_id)]
              if not rec then
                return "Huh? That item is gone.", "Anything else?"
              end

              if rec.is_key then
                local owned = tonumber(ezmemory.count_player_item(pid, rec.info.name) or 0) or 0
                if owned > 0 then
                  return "You already have that key item.", "Anything else?"
                end
              end

              local cost = rec.price or 0
              if cost < 0 then cost = 0 end

              local ok = ezmemory.spend_player_money(pid, cost)
              if not ok then
                local have = tonumber(Net.get_player_money(pid) or 0) or 0
                return string.format("Not enough money.\nCost: %d$  You have: %d$", cost, have), "Anything else?"
              end

              -- Grant synchronously (same logic as give_item_with_optional_notify, minus the popup)
              local is_key = rec.is_key
              if is_key or rec.info.type == "item" then
                ezmemory.create_or_update_item(rec.info.name, rec.info.description or "???", is_key)
                ezmemory.give_player_item(pid, rec.info.name, rec.info.amount or 1)
              end

              -- Force refresh so the money text updates immediately
              if menu and menu.render_menu_contents then
                pcall(function() menu:render_menu_contents(true) end)
              end

              -- Play purchase SFX like the other migrated shops
              if NG_SHOP_ITEM_GET_SFX then
                pcall(Net.provide_asset_for_player, pid, NG_SHOP_ITEM_GET_SFX)
                pcall(Net.play_sound_for_player, pid, NG_SHOP_ITEM_GET_SFX)
              end

              return string.format("Purchased %s!\n(-%d$)", tostring(rec.info.name), cost), "Anything else?"
            end,
          })

          while TalkVertMenu.is_busy and TalkVertMenu.is_busy(player_id) do
            await(Async.sleep(0.05))
          end

          return first_value_from_table(helpers.extract_numbered_properties(dialogue, "Next "))
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
    chip={
        name = "chip",
        action = function(npc, player_id, dialogue, relay_object)
            return async(function ()
                local chip_keys = get_dialogue_chip_keys(dialogue)
                local props = dialogue.custom_properties or {}

                local notify_player = props["Dont Notify"] ~= "true"

                -- 1 tick makes NPC chip gifts feel immediate instead of using the default post-battle delay.
                local delay_ticks = tonumber(props["Delay Ticks"] or props["Reward Delay Ticks"] or "1") or 1

                for index, chip_key in ipairs(chip_keys) do
                    local code = props["Code " .. tostring(index)] or props["Code"]

                    local ok, reason, card_def = whitelist.unlock_card(player_id, chip_key, code, delay_ticks)

                    if ok then
                        local chip_name = get_chip_display_name(card_def, chip_key)
                        await(notify_chip_get(player_id, chip_name, notify_player))
                    elseif reason ~= "already_unlocked" then
                        warn(
                            "[eznpcs] chip dialogue failed to unlock battle chip",
                            tostring(chip_key),
                            "reason:",
                            tostring(reason),
                            "dialogue:",
                            tostring(dialogue.id)
                        )
                    end
                end

                return props["Next 1"]
            end)
        end
    },
    successsfx={
        name = "successsfx",
        action = function(npc, player_id, dialogue, relay_object)
            return async(function ()
                play_dialogue_sfx_for_player(player_id, SUCCESS_SFX)
                return dialogue.custom_properties["Next 1"]
            end)
        end
    },
    failsfx={
        name = "failsfx",
        action = function(npc, player_id, dialogue, relay_object)
            return async(function ()
                play_dialogue_sfx_for_player(player_id, FAIL_SFX)
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