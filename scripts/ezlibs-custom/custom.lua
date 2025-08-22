local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local helpers  = require('scripts/ezlibs-scripts/helpers')

local custom = {}
print("[cards] custom plugin loading...")

-- === YOUR SETUP ===
-- Dialog mug assets (used only for Net._message_player)
local MUG_DIR          = '/server/assets/cards/'
local GENERIC_MUG_ANIM = MUG_DIR .. 'card.animation'

-- Overworld summon assets (separate from mug)
-- Put per-card sheets here with the SAME base filename as the mug:
--   /server/assets/cards_ow/Gaia.png
--   /server/assets/cards_ow/Gaia.animation
-- Also include a fallback /server/assets/cards_ow/card.animation
local OW_DIR           = '/server/assets/cards_ow/'
-- NEW: map rarity tag → subfolder
local OW_SUBDIR_BY_RARITY = {
  C  = 'common',   -- /server/assets/cards_ow/common/
  R  = 'rare',     -- /server/assets/cards_ow/rare/
  SR = 'srare',    -- /server/assets/cards_ow/srare/
  UR = 'urare',    -- /server/assets/cards_ow/urare/
  GDR = 'gdrare',  -- /server/assets/cards_ow/gdrare/
}
local GENERIC_OW_ANIM  = OW_DIR .. 'card.animation'

-- optional quick blocklist by exact item title (e.g., "[SR]Jinzo")
local UNTRADABLE_BY_NAME = {
    ["[SR]Jinzo"] = true,
    ["[R]RKaiser"] = true,
    ["[UR]RedEyesBD"] = true,
}

-- treat "true", "1", true as truthy
local function truthy(v)
  return v == true or v == 1 or v == "1" or (type(v) == "string" and v:lower() == "true")
end

-- is this item a card AND allowed to trade?
local function is_tradable_card(pid, item_id, info)
  if not info or not info.name then return false end
  -- only treat names starting with '[' as cards
  if tostring(info.name):sub(1,1) ~= "[" then return false end
  -- blocklist by exact name
  if UNTRADABLE_BY_NAME[info.name] then return false end

  -- optional: respect an item custom property in the editor: Untradable=true (or untradable/no_trade)
  local meta = nil
  pcall(function() meta = helpers.read_item_information(Net.get_player_area(pid), item_id) end)
  local cp = meta and meta.custom_properties
  if cp and (truthy(cp["Untradable"]) or truthy(cp["untradable"]) or truthy(cp["no_trade"])) then
    return false
  end

  -- (optional override if you ever want to force allow)
  if cp and truthy(cp["tradable"]) then return true end

  return true
end

-- Optional overrides: Board Title -> file base (no extension)
local CARD_ASSET_OVERRIDE = {
  -- ["[C]Kbo"] = "kuriboh",
}

-- Custom display names for summons (key by full title "[R]Gaia" or base "Gaia")
local SUMMON_NAME_OVERRIDE = {
    ["B.E.W.D."] = "Blue-Eyes White Dragon",
    ["B.L.S."] = "Black Luster Soldier",
    ["B.Ox"] = "Battle Ox",
    ["BBlader"] = "Buster Blader",
    ["BChaos"] = "Magician of Black Chaos",
    ["C.Dragon"] = "Curse of Dragon",
    ["C.Guard"] = "Celtic Guardian",
    ["DMGirl"] = "Dark Magician Girl",
    ["DMag"] = "Dark Magician",
    ["F.Imp"] = "Feral Imp",
    ["Gaia"] = "Gaia The Fierce Knight",
    ["H.M.Gnt"] = "Hitotsu-Me Giant",
    ["Jinzo"] = "Jinzo",
    ["JudgeM"] = "Judge Man",
    ["K.Dragon"] = "Koumori Dragon",
    ["Kbo"] = "Kuriboh",
    ["RKaise"] = "Rude Kaiser",
    ["RedEyesBD"] = "Red-Eyes Black Dragon",
    ["Saggi"] = "Saggi The Dark Clown",
    ["Swdstlk"] = "Swordstalker",
    ["V.Raider"] = "Vorse Raider",
    ["MElf"] = "Mystical Elf",
    ["SkullRBrd"] = "Skull Red Bird",
    ["ArmrdLiz"] = "Armored Lizard",
    ["Griffore"] = "Griffore",
    ["XHCan"] = "X-Head Cannon",
    ["MChsr"] = "Mechanicalchaser",
    ["FlameSwm"] = "Flame Swordsman",
    ["REBMD"] = "Red-Eyes Black Metal Dragon",
    ["S.Skull"] = "Summoned Skull",
    ["B.Sk.D."] = "Black Skull Dragon",
}

-- Rarity sort order
local RARITY_ORDER = { C = 1, R = 2, SR = 3, UR = 4, GDR = 5 }

-- === STATE ===
local player_using_card_bbs       = {}
local in_actions_menu             = {}
local pending_actions_menu        = {}
local last_viewed_card_by_player  = {}   -- [pid] = { name, png, anim, ow_png, ow_anim }
local summoned_bot_by_player      = {}   -- [pid] = bot_id
local open_list_after_close       = {}   -- [pid] = true → open Card List right after board_close

-- Actions
local ACTION_SUMMON       = "__card_action_summon__"
local ACTION_DISMISS      = "__card_action_dismiss__"
local ACTION_OPEN_LIST    = "__card_action_open_list__"
local ACTION_CLOSE        = "__card_action_close__"

local LIST_BOARD_COLOR    = { r=128, g=255, b=128 }
local ACTIONS_BOARD_COLOR = { r=255, g=230, b=120 }

-- ---------- helpers ----------
local function extract_rarity_from_title(title)
  title = tostring(title or "")
  local tag = title:match("^%[([A-Za-z]+)%]") or title:match("%[([A-Za-z]+)%]")
  if not tag then return nil end
  tag = tag:upper()
  if OW_SUBDIR_BY_RARITY[tag] then
    return tag
  end
  return nil
end
local function log(...) print('[cards]', table.unpack({...})) end
local function round16(x) return math.floor((x or 0) * 16 + 0.5) / 16 end

-- Build a left-aligned title: "[C] x2 Name" (or just "[C] Name" when qty < 2)
local function title_with_qty_left(full_title, qty)
  full_title = tostring(full_title or "")
  local rar, base = full_title:match("^%[([A-Za-z]+)%]%s*(.*)")
  -- base fallback if no bracketed rarity
  if not rar then
    if qty and qty >= 2 then
      return string.format("x%d %s", qty, full_title)
    else
      return full_title
    end
  end
  base = (base and base ~= "") and base or full_title
  if qty and qty >= 2 then
    return string.format("[%s] x%d %s", rar, qty, base)
  else
    return string.format("[%s] %s", rar, base)
  end
end

local function as_dir_string(d)
  if d == nil then return "" end
  d = tostring(d):lower()
  if d == "0" then return "up"
  elseif d == "1" then return "right"
  elseif d == "2" then return "down"
  elseif d == "3" then return "left" end
  return d
end

local function sort_key_from_title(title)
  title = tostring(title or "")
  -- grab tag between the first [...] if present
  local tag = title:match("^%[([A-Z]+)%]") or title:match("%[([A-Z]+)%]")
  if tag then tag = tag:upper() end
  local rank = RARITY_ORDER[tag] or 99
  -- base = everything after the first ']'
  local base = title:match("%](.*)") or title
  base = base:gsub("^%s+",""):gsub("%s+$","")
  return rank, base:lower(), base
end

local function guess_base_from_name(item_name)
  if CARD_ASSET_OVERRIDE[item_name] then
    local b = CARD_ASSET_OVERRIDE[item_name]
    log("override base for", item_name, "->", b)
    return b
  end
  local after = item_name:match("%](.*)")
  if after then
    after = after:gsub("^%s+",""):gsub("%s+$","")
    if after ~= "" then
      log("derived base (after ]) for", item_name, "->", after)
      return after
    end
  end
  local fallback = (item_name:gsub("[%[%]%s]+",""):gsub("[^%w_]","")):lower()
  log("fallback base for", item_name, "->", fallback)
  return fallback
end

-- Compute the display name for the summon:
local function get_summon_display_name(item_title)
  local base = item_title
  local after = item_title:match("%](.*)")
  if after then
    after = after:gsub("^%s+",""):gsub("%s+$","")
    if after ~= "" then base = after end
  end
  if base == item_title then base = (item_title:gsub("[%[%]]","")) end
  if SUMMON_NAME_OVERRIDE[item_title] then return SUMMON_NAME_OVERRIDE[item_title] end
  if SUMMON_NAME_OVERRIDE[base] then return SUMMON_NAME_OVERRIDE[base] end
  return base
end

-- Mug assets (dialog)
local function build_mug_paths_for_name(item_name)
  local base = guess_base_from_name(item_name)
  local png  = MUG_DIR .. base .. '.png'
  local anim = MUG_DIR .. base .. '.animation'
  if not (Net.has_asset and Net.has_asset(anim)) then anim = GENERIC_MUG_ANIM end
  log("[mug] using", "png="..tostring(png), "anim="..tostring(anim))
  return png, anim
end

-- Overworld assets (summon)
local function build_overworld_paths_for_name(item_name)
  local base   = guess_base_from_name(item_name)       -- e.g., "B.E.W.D."
  local rar    = extract_rarity_from_title(item_name)  -- "C","R","SR","UR", "GDR" or nil
  local sub    = rar and OW_SUBDIR_BY_RARITY[rar]
  local dir    = sub and (OW_DIR .. sub .. "/") or OW_DIR

  -- First choice: rarity subfolder
  local png    = dir .. base .. '.png'
  local anim   = dir .. base .. '.animation'
  local anim_fallback_same = dir .. 'card.animation'

  -- If per-card animation is missing in rarity folder, use that folder's card.animation,
  -- and if that doesn't exist, fall back to the global generic animation.
  if not (Net.has_asset and Net.has_asset(anim)) then
    if Net.has_asset and Net.has_asset(anim_fallback_same) then
      anim = anim_fallback_same
    else
      anim = GENERIC_OW_ANIM
    end
  end
  log("[ow] rarity="..tostring(rar).." dir="..dir.." using", "png="..tostring(png), "anim="..tostring(anim))
  return png, anim
end

-- engine dir → “front” offset of exactly 1 tile
local function dir_to_front_offset(dir)
  dir = as_dir_string(dir)
  if dir:find("up") or dir:find("north")   then return  0, -1 end
  if dir:find("down") or dir:find("south") then return  0,  1 end
  if dir:find("left") or dir:find("west")  then return -1,  0 end
  if dir:find("right") or dir:find("east") then return  1,  0 end
  return 0, -1
end

-- compute target “in front” of the player, snapped to 1/16, INCLUDING Z
local function compute_target_in_front(pid)
  local area_id = Net.get_player_area(pid)
  local pos     = Net.get_player_position(pid) or {x=0, y=0, z=0}
  local dir     = as_dir_string(Net.get_player_direction(pid))
  local px      = pos.x or pos[1] or 0
  local py      = pos.y or pos[2] or 0
  local pz      = pos.z or pos[3] or 0
  local dx, dy  = dir_to_front_offset(dir)
  local sx      = round16(px + dx)
  local sy      = round16(py + dy)
  local sz      = pz  -- keep same floor/z as player
  return area_id, sx, sy, sz
end

-- ---------- UI pieces ----------
local function show_card_dialog_with_mug(pid, item)
  local name = item and item.name or "(unknown)"
  local desc = item and item.description
  local text = (desc and #tostring(desc) > 0) and tostring(desc) or ("No description for: " .. name)

  local png, anim       = build_mug_paths_for_name(name)        -- mug for dialog
  local ow_png, ow_anim = build_overworld_paths_for_name(name)  -- overworld for summon

  -- keep both sets in memory
  last_viewed_card_by_player[pid] = {
    name = name, png = png, anim = anim,
    ow_png = ow_png, ow_anim = ow_anim
  }

  local ok, err = pcall(Net._message_player, pid, text, png, anim)  -- dialog uses the mug
  if ok then
    log("dialog (desc+mug) shown for", name)
  else
    log("dialog fallback (no mug):", tostring(err))
    Net.message_player(pid, text)
  end

  pending_actions_menu[pid] = true
  log("pending_actions_menu set for pid", pid)
end

local function open_actions_menu(pid, title)
  local posts = {}
  if summoned_bot_by_player[pid] then
    posts[#posts+1] = { id = ACTION_DISMISS,   read = true, title = "Dismiss" }
  else
    posts[#posts+1] = { id = ACTION_SUMMON,    read = true, title = "Summon" }
  end
  posts[#posts+1]   = { id = ACTION_OPEN_LIST, read = true, title = "Open Card List" }
  posts[#posts+1]   = { id = ACTION_CLOSE,     read = true, title = "Close" }

  in_actions_menu[pid] = true
  log("opening actions menu for pid", pid)
  Net.open_board(pid, title or "Card Options", ACTIONS_BOARD_COLOR, posts)
end

local function open_card_list(pid)
  local safe_secret   = helpers.get_safe_player_secret(pid)
  local player_memory = ezmemory.get_player_memory(safe_secret)

  local entries = {}
  for item_id, qty in pairs(player_memory.items or {}) do
    local info = ezmemory.get_item_info(item_id)
    if info and info.name and string.find(info.name, "[", 1, true) ~= nil then
      -- Put quantity on the RIGHT; omit when qty < 2
      local right_qty = (qty and qty >= 2) and tostring(qty) or ""
      entries[#entries+1] = {
        id     = item_id,
        read   = true,
        title  = info.name,   -- left: just the name (with [C]/[R]/… tag)
        author = right_qty,   -- right: "2", "3", ... (no "x")
        _raw   = info.name,   -- keep raw for sorting
      }
    end
  end

  -- Sort by rarity (C,R,SR,UR) then alphabetically by base name
  table.sort(entries, function(a, b)
    local ra, na_l = sort_key_from_title(a._raw)
    local rb, nb_l = sort_key_from_title(b._raw)
    if ra ~= rb then return ra < rb end
    if na_l ~= nb_l then return na_l < nb_l end
    return tostring(a._raw) < tostring(b._raw)
  end)

  player_using_card_bbs[pid] = true
  in_actions_menu[pid] = false
  pending_actions_menu[pid] = false
  log("opening Card Collection for pid", pid, "count=", #entries)
  Net.open_board(pid, "Card Collection", LIST_BOARD_COLOR, entries)
end

local function spawn_card_npc_for_all(pid, info)
  local area, sx, sy, sz = compute_target_in_front(pid)
  local display_name = get_summon_display_name(info.name or "Card")
  log(("spawning card npc: %s at area=%s x=%.3f y=%.3f z=%s"):format(display_name, tostring(area), sx or -1, sy or -1, tostring(sz)))

  local ow_png  = info.ow_png or info.png    -- prefer OW assets, fall back to mug if missing
  local ow_anim = info.ow_anim or info.anim

  local ok, bot_id = pcall(Net.create_bot, {
    name               = display_name,
    area_id            = area,
    x = sx or 0, y = sy or 0, z = sz or 0,   -- <<<<< spawn on the player's Z
    texture_path       = ow_png,
    animation_path     = ow_anim,            -- overworld animation
    mug_animation_path = info.anim,          -- harmless hint for systems that read mugs on bots
    animation          = "IDLE",
  })
  if not ok or not bot_id then
    log("spawn failed:", tostring(bot_id))
    Net.message_player(pid, "Couldn't summon the card.")
    return nil
  end

  -- Force the visible name in case the engine decorates it
  pcall(Net.set_bot_name, bot_id, display_name)

  log("spawned bot_id", bot_id, "with name", display_name)
  return bot_id
end

-- ---------- events ----------
print("[cards] Loaded card collection menu (spawns IN FRONT on same Z; no follow; manual dismiss; custom summon names).")

-- Left Shoulder:
--  - If pending, open Card Options.
--  - Else if a summon exists, open Card Options.
--  - Else open Card List.
Net:on("tile_interaction", function(event)
  if event.button ~= 1 then return end -- Left Shoulder only
  local pid = event.player_id
  log("tile_interaction (Left Shoulder) pid", pid, "pending_actions_menu=", pending_actions_menu[pid], "has_summon=", summoned_bot_by_player[pid] ~= nil)

  if pending_actions_menu[pid] then
    pending_actions_menu[pid] = false
    open_actions_menu(pid, "Card Options")
    return
  end

  if summoned_bot_by_player[pid] then
    open_actions_menu(pid, "Card Options")
    return
  end

  open_card_list(pid)
end)

-- ==========
-- Card Trader (BBS) minimal picker (integrated)
-- Public API: custom.start_card_trade(pid, { desc=string, groups={ {label="Common", items={...}, weight=70}, ... } })
-- ==========

-- per-player trade state
local trader_by_pid     = trader_by_pid     or {} -- [pid] = { desc, groups, page, picks{[id]=n}, inv{ {id,name,qty}... }, order{ id... } }
local trade_refreshing  = trade_refreshing  or {} -- [pid]=true while we are programmatically reopening the board
local trade_reopen      = trade_reopen      or {} -- [pid]=true to reopen after close

local TRADE_BOARD_COLOR = { r=180, g=220, b=255 }
local TRADE_PER_PAGE  = 12
local TRADE_TARGET    = 10
local TRADE_CONFIRM   = "__trade_confirm__"
local TRADE_CLEAR     = "__trade_clear__"
local TRADE_NEXT      = "__trade_next__"
local TRADE_PREV      = "__trade_prev__"
local TRADE_CANCEL    = "__trade_cancel__"
local TRADE_REPEAT    = "__trade_repeat__"

local function trade_count_picks(picks)
  local n = 0; for _,c in pairs(picks or {}) do n = n + (c or 0) end; return n
end

local function trade_snapshot_cards(pid)
  local secret = helpers.get_safe_player_secret(pid)
  local pmem = ezmemory.get_player_memory(secret)
  local rows = {}
  for item_id, qty in pairs(pmem.items or {}) do
    if qty and qty > 0 then
      local info = ezmemory.get_item_info(item_id)
      if is_tradable_card(pid, item_id, info) then
        rows[#rows+1] = { id=item_id, name=info.name, qty=qty }
      end
    end
  end
  table.sort(rows, function(a,b)
    local ra, na_l = sort_key_from_title(a.name)
    local rb, nb_l = sort_key_from_title(b.name)
    if ra ~= rb then return ra < rb end
    if na_l ~= nb_l then return na_l < nb_l end
    return tostring(a.name) < tostring(b.name)
  end)
  local order = {}; for i,r in ipairs(rows) do order[i] = r.id end
  return rows, order
end

local function trade_build_posts(pid)
  local st = trader_by_pid[pid]; if not st then return "Card Trader", {} end
  local posts = {}
  local picked = trade_count_picks(st.picks)
  local title = string.format("Card Trader - Select %d cards", TRADE_TARGET, picked, TRADE_TARGET)
  local can_repeat = false
  local repeat_label = nil
  if st.last_item_id and picked < TRADE_TARGET then
    for _, r in ipairs(st.inv) do
      if tostring(r.id) == tostring(st.last_item_id) then
        local left = (r.qty or 0) - (st.picks[st.last_item_id] or 0)
        if left > 0 then
          can_repeat = true
          repeat_label = "Pick Again"
          -- Optional: include the name, but keep it short to avoid overlap:
          -- repeat_label = ("Pick Again: %s"):format(r.name)
        end
        break
      end
    end
  end
  if can_repeat then
    posts[#posts+1] = { id=TRADE_REPEAT, read=true, title=repeat_label }
  end
  -- actions row
  posts[#posts+1] = { id=TRADE_CONFIRM, read=true, title=string.format("Confirm (%d/%d)", picked, TRADE_TARGET) }
  posts[#posts+1] = { id=TRADE_CLEAR,   read=true, title="Clear" }
  posts[#posts+1] = { id=TRADE_PREV,    read=true, title="Prev Page" }
  posts[#posts+1] = { id=TRADE_NEXT,    read=true, title="Next Page" }
  posts[#posts+1] = { id=TRADE_CANCEL,  read=true, title="Cancel" }

  -- page
  local start = ((st.page or 1) - 1) * TRADE_PER_PAGE + 1
  local finish = math.min(start + TRADE_PER_PAGE - 1, #st.order)
  for i = start, finish do
    local item_id = st.order[i]
    local row
    for _,r in ipairs(st.inv) do if r.id == item_id then row = r; break end end
    if row then
      local picked_n = st.picks[tostring(item_id)] or 0
      local left     = math.max(0, (row.qty or 0) - picked_n)

      -- Left text shows everything: quantity + selection
      local label = title_with_qty_left(row.name, left)  -- e.g., "[C] x3 Name"
      if picked_n > 0 then
        label = (picked_n == 1) and ("[*] " .. label) or (string.format("[*%d] %s", picked_n, label))
      end

      posts[#posts+1] = {
        id     = "trade:"..tostring(item_id),
        read   = true,
        title  = label,
        author = ""   -- keep empty so nothing shows on the right
      }
    end
  end

  return title, posts
end

local function open_trade_board(pid)
  trade_refreshing[pid] = true
  local title, posts = trade_build_posts(pid)
  Net.open_board(pid, title, TRADE_BOARD_COLOR, posts)
end

local function trade_pick_weighted(groups)
  local total = 0; for _,g in ipairs(groups or {}) do total = total + (tonumber(g.weight) or 0) end
  if total <= 0 then return nil end
  local roll, acc = math.random() * total, 0
  for _,g in ipairs(groups) do acc = acc + (tonumber(g.weight) or 0); if roll <= acc then return g end end
  return groups[#groups]
end

local function grant_trade_return(pid)
  local st = trader_by_pid[pid]; if not st then return nil end
  local g = trade_pick_weighted(st.groups); if not g or not g.items or #g.items==0 then return nil end
  local obj_id = g.items[math.random(1, #g.items)]
  local info = helpers.read_item_information(Net.get_player_area(pid), obj_id)
  if not info then return nil end
  ezmemory.give_item_with_optional_notify(pid, Net.get_player_area(pid), obj_id, info, false)
  return info.name
end

local function trade_try_consume(pid)
  local st = trader_by_pid[pid]; if not st then return false, "Not in a trade." end
  if trade_count_picks(st.picks) ~= TRADE_TARGET then return false, "You must select exactly "..TRADE_TARGET.." cards." end

  local removed = {}
  for item_id_str, n in pairs(st.picks) do
    n = tonumber(n) or 0
    if n > 0 then
      -- item_id_str is a string key; get info by id
      local info = ezmemory.get_item_info(item_id_str) or ezmemory.get_item_info(tonumber(item_id_str))
      if info and info.name then
        local have = ezmemory.count_player_item(pid, info.name)
        local take = math.min(n, have)
        if take > 0 then
          ezmemory.remove_player_item(pid, info.name, take)
          removed[#removed+1] = { name = info.name, qty = take }
        end
      end
    end
  end
  table.sort(removed, function(a,b) return a.name < b.name end)
  return (#removed > 0), removed
end

-- Expose entry point
function custom.start_card_trade(pid, cfg)
  local inv, order = trade_snapshot_cards(pid)
  trader_by_pid[pid] = {
    desc   = (cfg and cfg.desc) or "Trade any 10 cards for 1 random card.",
    groups = (cfg and cfg.groups) or {},
    page   = 1,
    picks  = {},
    inv    = inv,
    order  = order
  }
  trade_refreshing[pid] = nil  -- clear any stale flag before first open
  local total = 0; for _,r in ipairs(inv) do total = total + (r.qty or 0) end
  Net.message_player(pid, trader_by_pid[pid].desc .. string.format("\n\nYou currently have %d card(s).", total))
  open_trade_board(pid)
end

-- We forward-declare the click handler so the post_selection can call it
local handle_trade_post_selection

handle_trade_post_selection = function(event)
  local pid     = event.player_id
  local post_id = tostring(event.post_id or "")
  local st      = trader_by_pid[pid]
  if not st then return false end

  if post_id == TRADE_CANCEL then
    trader_by_pid[pid] = nil
    pcall(Net.close_bbs, pid)
    return true

  elseif post_id == TRADE_CLEAR then
    st.picks = {}
    trade_reopen[pid] = true
    pcall(Net.close_bbs, pid)
    return true

  elseif post_id == TRADE_NEXT then
    local pages = math.max(1, math.ceil(#st.order / TRADE_PER_PAGE))
    st.page = st.page + 1
    if st.page > pages then st.page = 1 end
    trade_reopen[pid] = true
    pcall(Net.close_bbs, pid)
    return true

  elseif post_id == TRADE_PREV then
    local pages = math.max(1, math.ceil(#st.order / TRADE_PER_PAGE))
    st.page = st.page - 1
    if st.page < 1 then st.page = pages end
    trade_reopen[pid] = true
    pcall(Net.close_bbs, pid)
    return true

  elseif post_id == TRADE_REPEAT then
    local last_id = st.last_item_id
    if not last_id then return true end
  
    -- find the row for the last id
    local row
    for _, r in ipairs(st.inv) do
      if tostring(r.id) == tostring(last_id) then row = r; break end
    end
    if not row then return true end
  
    local picked = st.picks[last_id] or 0
    local left   = (row.qty or 0) - picked
    if left > 0 and trade_count_picks(st.picks) < TRADE_TARGET then
      st.picks[last_id] = picked + 1
      st.last_item_id   = last_id
    else
      -- optional: tell player why it didn't add
      -- Net.message_player(pid, "No copies left or already picked 10.")
    end
    trade_reopen[pid] = true
    pcall(Net.close_bbs, pid)
    return true

  elseif post_id == TRADE_CONFIRM then
    local ok, removed_or_msg = trade_try_consume(pid)
    if not ok then
      Net.message_player(pid, removed_or_msg)
      return true
    end
    local got = grant_trade_return(pid)
    local lines = {}; for _,r in ipairs(removed_or_msg) do lines[#lines+1] = string.format("x%d %s", r.qty, r.name) end
    Net.message_player(pid, string.format("You traded:\n- %s\n\nYou received: %s", table.concat(lines, "\n- "), got or "(nothing?)"))

    -- refresh inventory; continue if still have >= 10
    local inv2, order2 = trade_snapshot_cards(pid)
    local total_after = 0; for _,r in ipairs(inv2) do total_after = total_after + (r.qty or 0) end
    if total_after >= TRADE_TARGET then
      st.inv, st.order, st.picks, st.page = inv2, order2, {}, 1
      trade_reopen[pid] = true
      pcall(Net.close_bbs, pid)
    else
      trader_by_pid[pid] = nil
      pcall(Net.close_bbs, pid)
    end
    return true

  else
    -- card row toggle (only handle rows tagged with "trade:<id>")
    if not post_id:match("^trade:") then
      return false  -- not ours; let other handlers process
    end

    local item_id_str = post_id:sub(7)  -- strip "trade:"
    local row
    for _, r in ipairs(st.inv) do
      if tostring(r.id) == item_id_str then row = r; break end
    end
    if not row then
      return false
    end

    local picked = st.picks[item_id_str] or 0
    local left   = (row.qty or 0) - picked
    if left > 0 and trade_count_picks(st.picks) < TRADE_TARGET then
      st.picks[item_id_str] = picked + 1
    else
      st.picks[item_id_str] = nil
    end
    st.last_item_id = item_id_str
    trade_reopen[pid] = true
    pcall(Net.close_bbs, pid)  -- reopen happens in board_close
    return true
  end
end

-- ==========
Net:on("post_selection", function(event)
  local pid = event.player_id
  log("post_selection pid", pid, "post_id", tostring(event.post_id), "in_actions=", in_actions_menu[pid], "in_main=", player_using_card_bbs[pid])
  if handle_trade_post_selection and handle_trade_post_selection(event) then return end

  if in_actions_menu[pid] then
    in_actions_menu[pid] = false
    local action = event.post_id
    log("actions menu selection:", action)

    if action == ACTION_SUMMON then
      local info = last_viewed_card_by_player[pid]
      if not info then Net.message_player(pid, "(View a card first.)"); return end
      if summoned_bot_by_player[pid] then
        log("replacing existing summon bot_id", summoned_bot_by_player[pid])
        pcall(Net.remove_bot, summoned_bot_by_player[pid])
      end
      local bot_id = spawn_card_npc_for_all(pid, info)
      if bot_id then
        summoned_bot_by_player[pid] = bot_id
        pending_actions_menu[pid] = true
        log("summoned; set pending_actions_menu for quick Dismiss/Open List")
      end
      return

    elseif action == ACTION_DISMISS then
      if summoned_bot_by_player[pid] then
        log("dismissing bot_id", summoned_bot_by_player[pid])
        pcall(Net.remove_bot, summoned_bot_by_player[pid])
        summoned_bot_by_player[pid] = nil
      end
      pending_actions_menu[pid] = true
      log("dismissed; set pending_actions_menu to reopen options")
      return

    elseif action == ACTION_OPEN_LIST then
      -- Auto-close Card Options, then open Card Collection as soon as it closes.
      open_list_after_close[pid] = true
      pcall(Net.close_bbs, pid)
      return

    elseif action == ACTION_CLOSE then
      log("closing BBS for pid", pid)
      pcall(Net.close_bbs, pid)
      player_using_card_bbs[pid] = false
      return
    end
  end

  if player_using_card_bbs[pid] == true then
    local item = ezmemory.get_item_info(event.post_id)
    log("main list selection ->", item and item.name or "(unknown)")
    show_card_dialog_with_mug(pid, item)
    return
  end

  log("post_selection fell through; no known context")
end)

Net:on("board_close", function(event)
  local pid = event.player_id
  log("board_close pid", pid)

  -- If we scheduled a reopen from a click, do it first.
  if trade_reopen and trade_reopen[pid] then
    trade_reopen[pid] = nil
    if trader_by_pid and trader_by_pid[pid] then
      open_trade_board(pid)  -- sets trade_refreshing[pid] = true internally
    end
    return
  end

  -- If the close was triggered by our own Net.open_board refresh, ignore it.
  if trade_refreshing and trade_refreshing[pid] then
    trade_refreshing[pid] = nil
    return
  end

  -- Normal close behavior: exit trade mode.
  trader_by_pid[pid] = nil
  player_using_card_bbs[pid] = false
  in_actions_menu[pid] = false
  if open_list_after_close[pid] then
    open_list_after_close[pid] = false
    open_card_list(pid)
  end
end)

-- Clean up on join/leave
Net:on("player_join", function(event)
  local pid = event.player_id
  log("player_join pid", pid)
  player_using_card_bbs[pid] = false
  in_actions_menu[pid] = false
  pending_actions_menu[pid] = false
  last_viewed_card_by_player[pid] = nil
  summoned_bot_by_player[pid] = nil
  open_list_after_close[pid] = false
end)

Net:on("player_disconnect", function(event)
  local pid = event.player_id
  log("player_disconnect pid", pid)
  if summoned_bot_by_player[pid] then
    log("auto-despawn bot_id", summoned_bot_by_player[pid])
    pcall(Net.remove_bot, summoned_bot_by_player[pid])
  end
  player_using_card_bbs[pid] = false
  in_actions_menu[pid] = false
  pending_actions_menu[pid] = false
  last_viewed_card_by_player[pid] = nil
  summoned_bot_by_player[pid] = nil
  open_list_after_close[pid] = false
  trader_by_pid[pid] = nil
end)

print("[cards] custom plugin ready"); return custom
