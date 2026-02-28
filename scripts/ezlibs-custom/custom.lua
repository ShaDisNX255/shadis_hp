local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local helpers  = require('scripts/ezlibs-scripts/helpers')
local ygo_pvp  = require('scripts/ezlibs-custom/ygo_pvp')
local jobbbs  = require('scripts/jobbbs/JobBBS')
local fishing  = require('scripts/ezlibs-custom/fishing')
local secret  = require('scripts/ezlibs-custom/secret_path_switch')
local dungeon  = require('scripts/ezlibs-custom/dungeon')
local soccerball  = require('scripts/ezlibs-custom/soccerball')
local slots  = require('scripts/ezlibs-custom/slots')
local blackjack = require('scripts/ezlibs-custom/blackjack')
local duels  = require('scripts/ezlibs-custom/duels')
local lobby  = require('scripts/ezlibs-custom/lobby')
local octopvp  = require('scripts/octo-ranking/octopvp')
-- Optional L-Menu (net-games) support
local LMenu
do
  local ok, M = pcall(require, "scripts/ezlibs-custom/LMenu")
  if ok and M then
    LMenu = M
    print("[cards] LMenu module loaded; L button will open LMenu.")
  else
    print("[cards] LMenu module not found; L button will use legacy behaviour (if enabled).")
  end
end


local custom = {}
-- Read an item’s info/meta when you might have either "area,id" or just a raw id.
local META_CACHE = {}  -- memoize misses/hits to avoid log spam
-- Forward decls so earlier helpers can reference them
local do_KO            -- assigned later
local build_cast_posts -- assigned later
local base_title  -- forward decl so short_name can call it
local battle_ui_open = battle_ui_open or {}

-- Forward declare so earlier closures capture it as an upvalue, not a global
local name_for

_G.__bbs_guard = _G.__bbs_guard or { ignore_once = {} }

local function _guard_ignore_next_close(pid, why)
  if not pid then return end
  _G.__bbs_guard.ignore_once[pid] = tostring(why or "foreign")
end
_G._guard_ignore_next_close = _guard_ignore_next_close  -- expose for other modules

function name_for(st, seat_i)
  local p = st.players and st.players[seat_i]
  -- Prefer stored name; fallback to player name from pid; else P1/P2
  local n = (p and p.name)
        or (st.pids and Net.get_player_name(st.pids[seat_i]))
        or ("P"..tostring(seat_i))
  return n
end
-- Return ezmemory item info from a field card (id may be "area,id" or plain id)
local function item_info_from_field_card(card)
  if not card or not card.id then return nil end
  local info = ezmemory.get_item_info(card.id)
  if info then return info end
  local a,i = tostring(card.id):match("^([^,]+),(%d+)$")
  if i then
    info = ezmemory.get_item_info(tonumber(i))
    if info then return info end
  end
  return nil
end

-- === Parse rarity from title like "[SR]Dark Magician" (respects your existing tags) ===
local function parse_rarity_tag(title)
  local rar = title and title:match("^%[([A-Za-z]+)%]") or title and title:match("%[([A-Za-z]+)%]")
  rar = rar and rar:upper() or nil
  if rar == "URARE" then rar = "UR" end  -- tolerate "URare" in Description vs title tag
  return rar
end

-- --- Card Viewer cross-talk guard -----------------------------------------
local card_list_open = card_list_open or {}

-- Optional: allows the cards module to skip itself during battles if you add a check there.
function custom.is_battle_open_for(pid)
  local map = rawget(_G, "battle_by_pid")
  local st  = map and map[pid]
  return (st ~= nil) and (st.finished ~= true)
end
-- === Battle UI globals (declare once, at top of helpers) ===
battle_reopen   = battle_reopen   or {}  -- existing in your code; keep table shared
_ann_q          = _ann_q          or {}  -- per-player announcement queue
_ann_busy       = _ann_busy       or {}  -- true while a modal is open for that pid
_reopen_pending = _reopen_pending or {}  -- deferred board refresh while modal is up
_ack_count       = _ack_count       or {}

-- === Safe announcer (queues popups so they never overlap) ===
-- ========= Modal-aware announcer + gate =========
-- Try to resolve Async from require or from _G.Async (some servers preload it)
local function _resolve_async()
  local ok, A = pcall(require, "scripts/ezlibs-scripts/async")
  if ok and A and A.message_player then return A end
  if _G.Async and _G.Async.message_player then return _G.Async end
  return nil
end

local Async = _resolve_async()

-- per-player count of currently-open modal boxes
_ack_count      = _ack_count      or {}
_reopen_pending = _reopen_pending or {}

-- When a modal closes, if we had deferred a refresh, do it now.
local function _after_modal_closed_impl(pid)
  if _reopen_pending[pid] then
    _reopen_pending[pid] = nil
    if not battle_reopen[pid] then battle_reopen[pid] = true end
    pcall(Net.close_bbs, pid)
  end
end

-- EXPOSE for JobBBS.lua (which calls this on textbox_response)
_G._after_modal_closed = function(pid)
  -- decrement ack if needed
  local n = (_ack_count[pid] or 0)
  if n > 0 then
    _ack_count[pid] = n - 1
    print(("[custom][announce] JobBBS --ack %s -> %d"):format(tostring(pid), _ack_count[pid]))
  else
    _ack_count[pid] = 0
  end
  _after_modal_closed_impl(pid)
end

-- === SAFE REFRESH: don't close BBS if a modal is up ===
closing_for_refresh      = closing_for_refresh      or {}
closing_for_refresh_ts   = closing_for_refresh_ts   or {}
PROGRAM_REFRESH_WINDOW_S = PROGRAM_REFRESH_WINDOW_S or 0.35  -- ~350ms

local function safe_request_refresh(pid)
  if not pid then return end
  -- if an async announcer modal is up, defer until it’s closed
  if _ann_busy and _ann_busy[pid] then
    _reopen_pending[pid] = true
    return
  end
  -- mark this as a programmatic (refresh) close and timestamp it
  closing_for_refresh[pid]    = true
  closing_for_refresh_ts[pid] = os.clock()
  -- tell board_close to reopen the battle board afterward
  battle_reopen[pid] = true
  print("[custom][refresh] programmatic close scheduled for", pid)
  pcall(Net.close_bbs, pid)
end

-- Announcer: prefer true modal via Async; fall back to non-modal toast
local function safe_announce(pid, msg)
  if not pid or not msg or msg == "" then return end

  if not Async then
    -- Try to resolve again in case modules loaded later
    Async = _resolve_async()
  end

  if Async and Async.message_player then
    -- Treat as modal: ++ack now; JobBBS will call _after_modal_closed() on close
    _ack_count[pid] = (_ack_count[pid] or 0) + 1
    print(("[custom][announce] MODAL ++ack %s -> %d"):format(tostring(pid), _ack_count[pid]))
    local ok, err = pcall(Async.message_player, pid, msg)
    if not ok then
      print("[custom][announce] Async.message_player error: "..tostring(err))
      -- Fallback to non-modal and undo the ack to avoid “stuck busy”
      _ack_count[pid] = math.max(0, (_ack_count[pid] or 1) - 1)
      print(("[custom][announce] Fallback --ack %s -> %d"):format(tostring(pid), _ack_count[pid]))
      pcall(Net.message_player, pid, msg)
      _after_modal_closed_impl(pid)
    end
    return
  end

  -- Last resort: non-modal toast (cannot gate on this)
  print(("[custom][announce] non-modal to=%s"):format(tostring(pid)))
  pcall(Net.message_player, pid, msg)
end

-- Announce to both viewers (PvP) or the single player (PvE)
local function battle_announce(st, msg)
  if not st or not msg then return end
  if st.pids and type(st.pids) == "table" then
    for _, p in ipairs(st.pids) do safe_announce(p, msg) end
  elseif st.pid then
    safe_announce(st.pid, msg)
  end
end

-- Refresh both viewers, or just the actor in PvE
local function refresh_both(st, actor_pid)
  if not st then return end
  if st.pids and type(st.pids)=="table" then
    for _, p in ipairs(st.pids) do safe_request_refresh(p) end
  else
    safe_request_refresh(actor_pid or st.pid)
  end
end

-- Block End Turn while the opponent has any modal open
function gate_if_opponent_busy(st, actor_pid)
  if not st or not st.pids or not actor_pid then return false end
  local my  = seat_idx(st, actor_pid) or 1
  local opp = st.pids[3 - my]
  if not opp then return false end
  local busy = (_ack_count[opp] or 0) > 0
  print(("[custom][gate] actor=%s opp=%s opp_ack=%d busy=%s")
        :format(tostring(actor_pid), tostring(opp), _ack_count[opp] or 0, tostring(busy)))
  if busy then
    local nm = Net.get_player_name(opp) or "opponent"
    -- IMPORTANT: non-modal toast so we don’t create a new modal here
    pcall(Net.message_player, actor_pid, "Waiting on "..nm.." to close their message...")
    return true
  end
  return false
end

-- Ensure `custom` is visible to modules that expect a global (fallback)
_G.custom = _G.custom or custom

local JobBBS = (function()
  local ok, M = pcall(require, 'scripts/jobbbs/JobBBS')
  if ok and M then return M end
  ok, M = pcall(require, 'scripts/jobbbs/jobbbs')
  return ok and M or nil
end)()

-- If the module loaded, prefer injection; otherwise we’ll fall back to global `custom`.
if ygo_pvp then
  if ygo_pvp.set_start_fn then
    ygo_pvp.set_start_fn(function(a, b, cfg)
      return custom.start_card_battle_pvp(a, b, cfg)
    end)
    print("[ygo] PVP start function injected.")
  else
    print("[ygo] Warning: ygo_pvp.set_start_fn missing; module may expect global `custom`.")
  end
else
  print("[ygo] ERROR: PVP module not found; duel tables won’t work.")
end

local ok_ygo, ygo_pvp = pcall(require, "scripts/ezlibs-custom/ygo_pvp")
if ok_ygo and ygo_pvp and ygo_pvp.set_start_fn then
  ygo_pvp.set_start_fn(function(a, b, cfg)
    return custom.start_card_battle_pvp(a, b, cfg)
  end)
end

do
  if not _G.__cards_rng_seeded then
    local t  = os.time()
    local s  = tonumber(tostring({}):sub(8), 16) or 0  -- address entropy
    local c  = math.floor((os.clock() % 1) * 1e9)      -- sub-second entropy
    local seed = (t + s + c) % 2147483647
    math.randomseed(seed)
    -- warm up a few calls
    for i = 1, 5 do math.random() end
    _G.__cards_rng_seeded = true
  end
end

-- ===== Deck persistence (RAM + ezmemory) =====
local saved_deck_by_pid = saved_deck_by_pid or {}   -- session cache
local DECK_MEM_KEY      = "miniygo_deck_v2"         -- per-player key in ezmemory

local function short_name(title)
  local base = base_title(title or "")
  -- keep it short (BBS rows are narrow)
  return base
end

-- Returns two strings for a given side: subject and possessive.
-- idx=1 is the human player; idx=2 is the NPC.
local function labels_for(st, seat_i)
  seat_i = (seat_i == 1) and 1 or 2
  if st.mode == "pvp" then
    local p = st.players and st.players[seat_i]
    local n = (p and p.name) or ("P"..seat_i)
    return n, (n .. "'s")
  else
    if seat_i == 1 then
      return "You", "Your"
    else
      local npc = st.npc_name or "NPC"
      return npc, (npc .. "'s")
    end
  end
end

-- Format one-liners
local function fmt_npc(st) return st.npc_name or "NPC" end

-- Decide if our candidate ATK can beat oppATK using at most one affordable spell (by key).
local function npc_plan_to_beat(oppATK, candATK, hand_after_summon)
  -- already wins without a spell
  if candATK > oppATK then return { use = "none" } end

  -- find needed spells by key (no reliance on global SP)
  local axe, reinforce, shrink
  if SPELLS and type(SPELLS) == "table" then
    for _, sp in ipairs(SPELLS) do
      if sp.key == "axe" then axe = sp
      elseif sp.key == "reinforce" then reinforce = sp
      elseif sp.key == "shrink" then shrink = sp
      end
    end
  end

  local function afford(sp) return sp and hand_after_summon >= (sp.cost or 0) end

  if afford(axe) and (candATK + 1000) > oppATK then
    return { use = "axe" }
  end
  if afford(reinforce) and (candATK + 500) > oppATK then
    return { use = "reinforce" }
  end
  if afford(shrink) and candATK > (oppATK - 1000) then
    return { use = "shrink" }
  end
  return nil
end

-- NPC pays spell cost by discarding from end of hand
local function npc_pay_cost(st, me_idx, cost)
  local me = st.players[me_idx]
  if #me.hand < cost then return false end
  for i = 1, cost do table.remove(me.hand, #me.hand) end
  return true
end

local function cleanup_zero_def(state)
  for idx = 1, 2 do
    local f = state.players[idx].field
    -- Only destroy if: face-up DEF, DEF <= 0, came from an effect (spell), and no grace flag.
    if f and f.pos == "DEF" and (f.curDEF or 0) <= 0 and f._zero_def_from_effect and not f._zero_def_grace then
      local _, poss = labels_for(state, idx)
      local nm = short_name(f.card.title)
      battle_announce(state, poss .. " " .. nm .. " was destroyed (0 DEF).")
      do_KO(state, idx)
    end
  end
end
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
  GR  = 'grare',   -- /server/assets/cards_ow/grare/
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
  local meta = read_item_meta_flexible(pid, item_id)
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
    ["F.A.DMGirl"] = "Dark Magician Girl",
    ["DMag"] = "Dark Magician",
    ["F.A.DMag"] = "Dark Magician",
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
    ["GearFK"] = "Gearfried The Iron Knight",
    ["GobAtkFrc"] = "Goblin Attack Force",
    ["REBD"] = "Red-Eyes Black Dragon",
    ["PanthrWar"] = "Panther Warrior",
    ["ZMetalTnk"] = "Z-Metal Tank",
    ["JiraiGumo"] = "JiraiGumo",
    ["BabyDrgn"] = "Baby Dragon",
    ["SilverFng"] = "Silver Fang",
    ["GSoStone"] = "Giant Soldier of Stone",
	["F.A.V.Lord"] = "Vampire Lord",
    ["F.A.Kboble"] = "Kuribohble",
    ["F.A.REBD"] = "Red-Eyes Black Dragon",
    ["F.A.BEWD"] = "Blue-Eyes White Dragon",
    ["TyrntDrgn"] = "Tyrant Dragon",
    ["TriHrDrgn"] = "Tri-Horned Dragon",
    ["Seiyaryu"] = "Seiyaryu",
    ["KsrGldr"] = "Kaiser Glider",
    ["LstrDrg2"] = "Luster Dragon 2",
    ["CybrDrgn"] = "Cyber Dragon",
    ["Hyoznryu"] = "Hyozanryu",
    ["RyuRan"] = "Ryu-Ran",
    ["KsrSeaHs"] = "Kaiser Sea Horse",
    ["LaJinn"] = "La Jinn the Mystical Genie of the Lamp",
    ["LstrDrgn"] = "Luster Dragon",
    ["SprDrgn"] = "Spear Dragon",
    ["LordOfD"] = "Lord of D.",
    ["AquaMdr"] = "Aqua Madoor",
    ["MystHrs"] = "Mystic Horseman",
    ["WWingCat"] = "W-Wing Catapult",
    ["RyuKish"] = "Ryu-Kishin",
    ["PetiDrgn"] = "Petit Dragon",
}

-- Rarity sort order
local RARITY_ORDER = { C = 1, R = 2, SR = 3, UR = 4, GR = 5, GDR = 6 }

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

  local pos, dir
  local double_id = pid .. "-double"

  -- If the net-games freeze double exists, use its position/direction
  if Net.is_bot and Net.get_bot_position and Net.get_bot_direction
     and Net.is_bot(double_id) then
    pos = Net.get_bot_position(double_id) or { x = 0, y = 0, z = 0 }
    dir = as_dir_string(Net.get_bot_direction(double_id))
  else
    -- Fallback: normal player position/direction
    pos = Net.get_player_position(pid) or { x = 0, y = 0, z = 0 }
    dir = as_dir_string(Net.get_player_direction(pid))
  end

  local px = pos.x or pos[1] or 0
  local py = pos.y or pos[2] or 0
  local pz = pos.z or pos[3] or 0
  local dx, dy = dir_to_front_offset(dir)
  local sx = round16(px + dx)
  local sy = round16(py + dy)
  local sz = pz -- keep same floor/z

  return area_id, sx, sy, sz
end

local function compute_target_behind(pid)
  local area_id = Net.get_player_area(pid)
  local pos     = Net.get_player_position(pid) or {x=0, y=0, z=0}
  local dir     = as_dir_string(Net.get_player_direction(pid))
  local px, py, pz = pos.x or pos[1] or 0, pos.y or pos[2] or 0, pos.z or pos[3] or 0
  local dx, dy  = dir_to_front_offset(dir)
  local sx      = round16(px - dx)
  local sy      = round16(py - dy)
  local sz      = pz
  return area_id, sx, sy, sz
end

-- ---------- UI pieces ----------
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

-- === External API for LMenu / other modules ===
_G.card_overworld_api = _G.card_overworld_api or {}

do
  local api = _G.card_overworld_api

  --- Has the player “armed” a card (viewed a card’s description)?
  function api.is_card_armed(pid)
    return last_viewed_card_by_player[pid] ~= nil
  end

  --- Does the player currently have an overworld card summon?
  function api.has_summon(pid)
    return summoned_bot_by_player[pid] ~= nil
  end

  --- Try to summon the currently armed card.
  --- Returns true on success, false on failure.
  function api.summon_armed(pid)
    local info = last_viewed_card_by_player[pid]
    if not info then
      Net.message_player(pid, "(View a card first.)")
      return false
    end

    -- If something is already summoned, remove it first.
    if summoned_bot_by_player[pid] then
      pcall(Net.remove_bot, summoned_bot_by_player[pid])
      summoned_bot_by_player[pid] = nil
    end

    -- This is your existing helper that spawns the OW NPC for the card.
    local bot_id = spawn_card_npc_for_all(pid, info)
    if bot_id then
      summoned_bot_by_player[pid] = bot_id
      return true
    end

    return false
  end

  --- Try to dismiss the current summon.
  function api.unsummon(pid)
    if summoned_bot_by_player[pid] then
      pcall(Net.remove_bot, summoned_bot_by_player[pid])
      summoned_bot_by_player[pid] = nil
      return true
    end
    return false
  end

function api.arm_card(pid, item_name)
  item_name = tostring(item_name or "")
  if item_name == "" then return false end

  local png, anim = build_mug_paths_for_name(item_name)
  local ow_png, ow_anim = build_overworld_paths_for_name(item_name)

  last_viewed_card_by_player[pid] = {
    name = item_name,
    png = png,
    anim = anim,
    ow_png = ow_png,
    ow_anim = ow_anim,
  }

  return true
end

end


-- Track table exists earlier; just reuse it here
summoned_bot_by_player = summoned_bot_by_player or {}

-- Seat -> player_id (PVP has both; PvE uses st.pid for seat 1)
local function _pid_for_seat(st, seat_i)
  if st and st.pids and type(st.pids) == "table" then return st.pids[seat_i] end
  if st and seat_i == 1 then return st.pid end
  return nil
end

-- Remove the player’s current OW card (same behavior as your Actions “Dismiss”)
local function _duel_dismiss_overworld_for_pid(pid)
  if summoned_bot_by_player and summoned_bot_by_player[pid] then
    pcall(Net.remove_bot, summoned_bot_by_player[pid])
    summoned_bot_by_player[pid] = nil
  end
end

-- Spawn a card OW bot BEHIND the summoner (mirrors spawn_card_npc_for_all fields)
local function spawn_card_npc_behind(pid, info)
  local area, sx, sy, sz = compute_target_behind(pid)
  local display_name = get_summon_display_name(info.name or "Card")
  local ow_png  = info.ow_png or info.png
  local ow_anim = info.ow_anim or info.anim

  local ok, bot_id = pcall(Net.create_bot, {
    name               = display_name,
    area_id            = area,
    x = sx or 0, y = sy or 0, z = sz or 0,
    texture_path       = ow_png,
    animation_path     = ow_anim,
    mug_animation_path = info.anim,
    animation          = "IDLE",
  })
  if not ok or not bot_id then
    Net.message_player(pid, "Couldn't summon the card.")
    return nil
  end
  pcall(Net.set_bot_name, bot_id, display_name)
  return bot_id
end

-- Item info from a field slot -> OW paths; spawn behind; replace any prior
local function _duel_spawn_faceup_for_seat(st, seat_i)
  if not st then return end
  local pid = _pid_for_seat(st, seat_i); if not pid then return end
  local pl  = st.players and st.players[seat_i]
  local f   = pl and pl.field
  if not f or f.pos == "SET" then return end -- never leak face-down info

  local info  = item_info_from_field_card(f.card) or {}
  local name  = (info and info.name) or f.card.title
  local ow_png, ow_anim = build_overworld_paths_for_name(name)
  local _, mug_anim     = build_mug_paths_for_name(name)

  _duel_dismiss_overworld_for_pid(pid)
  local bot_id = spawn_card_npc_behind(pid, { name=name, ow_png=ow_png, ow_anim=ow_anim, anim=mug_anim })
  if bot_id then
    summoned_bot_by_player[pid] = bot_id
  end
end

-- Call this whenever a seat’s monster is destroyed/removed from field
local function _duel_on_monster_destroyed(st, seat_i)
  local pid = _pid_for_seat(st, seat_i)
  if pid then _duel_dismiss_overworld_for_pid(pid) end
end

-- Clear both players’ OW spawns (use on duel end)
local function _duel_cleanup_overworld(st)
  if not st then return end
  if st.pids and type(st.pids)=="table" then
    for _, p in ipairs(st.pids) do _duel_dismiss_overworld_for_pid(p) end
  elseif st.pid then
    _duel_dismiss_overworld_for_pid(st.pid)
  end
end

-- ---------- events ----------
print("[cards] Loaded card collection menu (spawns IN FRONT on same Z; no follow; manual dismiss; custom summon names).")

-- Left Shoulder:
--  - If pending, open Card Options.
--  - Else if a summon exists, open Card Options.
--  - Else open Card List.
--Net:on("tile_interaction", function(event)
--  if event.button ~= 1 then return end -- Left Shoulder only
--  local pid = event.player_id
--  log("tile_interaction (Left Shoulder) pid", pid, "pending_actions_menu=", pending_actions_menu[pid], "has_summon=", summoned_bot_by_player[pid] ~= nil)
--  -- Detect an active battle UI for this player
--  local battle_up = (_battle_active and _battle_active(pid))
                 --or (custom and custom.is_battle_open_for and custom.is_battle_open_for(pid))
                 --or false

  -- ✅ If we’re in battle AND the viewer set the "open actions next" latch,
  -- open the battle actions instead of the Card Viewer.
--  if battle_up and pending_actions_menu[pid] then
--    in_actions_menu[pid] = true              -- we’re explicitly going into actions
    -- leave pending_actions_menu[pid] as-is or clear it here; either is fine.
    -- Clearing here is a bit tidier:
--    pending_actions_menu[pid] = false

    -- trigger a reopen so build_main_posts can render Summon/Set at top
--    battle_reopen[pid] = true
--    pcall(Net.close_bbs, pid)
--    return
--  end

--  if pending_actions_menu[pid] then
--    pending_actions_menu[pid] = false
--    open_actions_menu(pid, "Card Options")
--    return
--  end

--  if summoned_bot_by_player[pid] then
--    open_actions_menu(pid, "Card Options")
--    return
--  end

--  open_card_list(pid)
--end)

-- ==========
-- Card Trader (BBS) minimal picker (integrated)
-- Public API: custom.start_card_trade(pid, { desc=string, groups={ {label="Common", items={...}, weight=70}, ... } })
-- ==========

-- per-player trade state
local trader_by_pid     = trader_by_pid     or {} -- [pid] = { desc, groups, page, picks{[id]=n}, inv{ {id,name,qty}... }, order{ id... } }
local trade_refreshing  = trade_refreshing  or {} -- [pid]=true while we are programmatically reopening the board
local trade_reopen      = trade_reopen      or {} -- [pid]=true to reopen after close

local TRADE_BOARD_COLOR = { r=180, g=220, b=255 }
local TRADE_PER_PAGE  = 9999
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

-- Adjust group weights based on what the player fed (SR/UR/GR/GDR)
-- Scheme: UR feed → UR up to +90% (9% per UR); SR feed → SR up to +90% (9% per SR) and UR up to +30% (3% per SR).
-- UR feed also grants a combined +10% to GDR/GR (1% per UR, split across the present pools).
local function _apply_trade_boosts_for_picks(pid, groups, picks)
  -- count fed rarities
  local fed = { C=0, R=0, SR=0, UR=0, GDR=0, GR=0 }
  for item_id_str, n in pairs(picks or {}) do
    n = tonumber(n or 0) or 0
    if n > 0 then
      local info = ezmemory.get_item_info(item_id_str) or ezmemory.get_item_info(tonumber(item_id_str))
      local rar  = (info and info.name and (parse_rarity_tag(info.name) or "C") or "C"):upper()
      if fed[rar] ~= nil then fed[rar] = fed[rar] + n end
    end
  end

  -- copy current weights
  local labels, baseW, totalW, idx = {}, {}, 0, {}
  for i,g in ipairs(groups or {}) do
    labels[i] = g.label
    baseW[i]  = tonumber(g.weight) or 0
    totalW    = totalW + baseW[i]
    idx[g.label] = i
  end
  if totalW <= 0 then return groups end

  local function add_share(label, share)  -- share is fraction of 1.0 of total mass
    local i = idx[label]; if not i or share <= 0 then return end
    baseW[i] = baseW[i] + share * totalW
  end

  -- compute boosts (fractions of 1.0), clamped
  local ur_major = math.min(0.90, 0.09 * (fed.UR or 0))
  local sr_major = math.min(0.90, 0.09 * (fed.SR or 0))
  local ur_cross = math.min(0.30, 0.03 * (fed.SR or 0))
  local sp_total = math.min(0.10, 0.01 * (fed.UR or 0)) -- for Gold/Ghost combined

  -- apply boosts
  add_share("Ultra Rare", ur_major)
  add_share("Ultra Rare", ur_cross)  -- SRs nudge UR too
  add_share("Super Rare", sr_major)

  -- split special bump across whichever of GDR/GR pools are present
  local present = {}
  if idx["Gold Rare"]  then present[#present+1] = "Gold Rare" end
  if idx["Ghost Rare"] then present[#present+1] = "Ghost Rare" end
  if #present > 0 and sp_total > 0 then
    local each = sp_total / #present
    for _,lab in ipairs(present) do add_share(lab, each) end
  end

  -- remove the added mass proportionally from Common/Rare reservoir
  local added = 0
  for i,g in ipairs(groups or {}) do added = added + (baseW[i] - (tonumber(g.weight) or 0)) end
  if added > 0 then
    local res = 0
    local CR = {}
    for _,lab in ipairs({"Common","Rare"}) do
      local i = idx[lab]; if i then res = res + baseW[i]; CR[#CR+1] = i end
    end
    if res > 0 then
      for _,i in ipairs(CR) do
        local cut = added * (baseW[i] / res)
        baseW[i] = math.max(0, baseW[i] - cut)
      end
    end
  end

  -- return adjusted groups (same shape)
  local out = {}
  for i,g in ipairs(groups or {}) do
    out[i] = { label = g.label, items = g.items, weight = baseW[i] }
  end
  return out
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
  -- NEW: adjust weights using what the player fed before we roll the group
  local adjusted = _apply_trade_boosts_for_picks(pid, st.groups, st.picks)
  local g = trade_pick_weighted(adjusted); if not g or not g.items or #g.items == 0 then return nil end
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

-- Seating helper used by the battle UI; global so any builder can use it.
_G.seat_idx = _G.seat_idx or function(st, pid)
  if not st then return 1 end
  -- Fast path: explicit mapping (we set this in PVP state)
  if st.seat_of and st.seat_of[pid] then
    return st.seat_of[pid]
  end
  -- Fallback: infer from st.pids[1/2]
  if st.pids then
    if st.pids[1] == pid then return 1 end
    if st.pids[2] == pid then return 2 end
  end
  -- Last resort: default to P1
  return 1
end

-- Returns my_index(1/2), me, opp
local function me_opp(st, pid)
  local me_i = seat_idx(st, pid)
  local opp_i = 3 - me_i
  return me_i, st.players[me_i], st.players[opp_i]
end

-- Broadcast small “announcer” messages to both players
local function announce_both(st, text)
  if not st or not st.pids then return end
  for _, p in ipairs(st.pids) do
    Net.message_player(p, "[YGO] " .. text)
  end
end

-- === Discard picker (choose exactly N cards to pay a spell cost) ===
build_discard_posts = function(pid)
  local st = battle_by_pid[pid]
  if not st then
    return "Duel", { { id=BTL_OK, read=true, title="(no state)" } }
  end

  local my = seat_idx(st, pid)
  local me = st.players[my]
  local need = st._discard_cost or 0

  st._discard_sel = st._discard_sel or {}
  local chosen = 0
  for _, v in pairs(st._discard_sel) do if v then chosen = chosen + 1 end end

  local posts = {}
  posts[#posts+1] = {
    id    = BTL_OK, read = true,
    title = string.format("Discard %d card(s) to cast %s:", need, st._pending_spell or "?")
  }

  for i, c in ipairs(me.hand) do
    local picked = st._discard_sel[i]
    local mark   = picked and " [x]" or " [ ]"
    posts[#posts+1] = {
      id    = BTL_DSEL_PREFIX..i, read = true,
      title = string.format("  %d) %s [A %d / D %d]%s", i, short_name(c.title), c.ATK, c.DEF, mark)
    }
  end

  posts[#posts+1] = {
    id    = (chosen == need) and BTL_DCONF or BTL_OK, read = true,
    title = (chosen == need) and "Confirm Discard" or string.format("Confirm Discard (%d/%d)", chosen, need)
  }
  posts[#posts+1] = { id = BTL_DCANCEL, read = true, title = "Cancel" }

  return battle_title(st).." - Discard", posts
end

-- === Cast submenu (shows spells + costs; paying via hand picks) ===
build_cast_posts = function(pid)
  local st = battle_by_pid[pid]
  if not st then
    return "Duel", { { id=BTL_OK, read=true, title="(no state)" } }
  end

  local my = seat_idx(st, pid)
  local posts = {}
  posts[#posts+1] = { id=BTL_OK, read=true, title="Select a Spell (discard = cost):" }

  local function split_name_desc(s)
    s = tostring(s or "")
    local n, d = s:match("^%s*([^%(]+)%s*%(%s*(.+)%)%s*$")
    if n then return (n:gsub("%s+$","")), d end
    n, d = s:match("^%s*([^%—%-:]+)%s*[—%-%:]+%s*(.+)%s*$")
    if n then return (n:gsub("%s+$","")), d end
    return s, nil
  end

  for _, sp in ipairs(SPELLS) do
    local cost = sp.cost or 0
    local enabled = (#st.players[my].hand >= cost)
    local base, desc = split_name_desc(sp.name)
    local label = string.format("[%d] %s", cost, base)
    if not enabled then label = label .. "  (need " .. cost .. ")" end

    posts[#posts+1] = { id = BTL_CAST_PICK .. sp.key, read = true, title = label }
    if desc and #desc > 0 then
      posts[#posts+1] = { id = BTL_OK, read = true, title = "    " .. desc }
    end
  end

  posts[#posts+1] = { id="__b_back__", read=true, title="Back" }
  return battle_title(st).." - Spells", posts
end

local function open_cast_board(pid)
  battle_refreshing[pid] = true
  local title, posts = build_cast_posts(pid)
  Net.open_board(pid, title, BATTLE_BOARD_COLOR, posts)
end

-- === Pay cost by discarding chosen cards from hand ===
local function pay_cost_from_hand(st, me_idx, cost, chosen_idxs_descending)
  local me = st.players[me_idx]
  if #me.hand < cost then return false end
  -- delete using provided hand indices (descending order so removal doesn’t shift earlier)
  table.sort(chosen_idxs_descending, function(a,b) return a>b end)
  for _,i in ipairs(chosen_idxs_descending) do
    table.remove(me.hand, i)
  end
  return true
end

-- Build a 10-card deck from a list of object IDs in the current area.
local function _build_deck_from_id_list_for_area(area_id, id_list)
  if type(id_list) ~= "table" or #id_list ~= 10 then return nil end
  local deck = {}

  for _, obj_id in ipairs(id_list) do
    local info = helpers.read_item_information(area_id, obj_id)
    if not info then return nil end

    local card_tbl = info.custom and info.custom.card
    if type(card_tbl) == "table" then
      -- Use embedded card data, but make sure id/ATK/DEF exist
      local c = deepcopy(card_tbl)
      c.id    = c.id or (area_id .. "," .. tostring(obj_id))
      if c.ATK == nil or c.DEF == nil then
        local A, D = parse_atk_def_from_text(info.description or "")
        c.ATK = c.ATK or (A or 0)
        c.DEF = c.DEF or (D or 0)
      end
      deck[#deck+1] = c
    else
      -- Build from the item’s name/description like the pack/trader flow
      local A, D = parse_atk_def_from_text(info.description or "")
      deck[#deck+1] = {
        id    = area_id .. "," .. tostring(obj_id),
        title = info.name or ("Card "..tostring(obj_id)),
        ATK   = A or 0,
        DEF   = D or 0
      }
    end
  end

  return (#deck == 10) and deck or nil
end

local function _finish_early(reason, msg)
  local cb = cfg and (cfg.on_finish or cfg._on_finish)
  if cb then pcall(cb, { player_won=false, reason=reason or "deck_build_failed", error=msg }) end
end

function custom.start_card_battle(pid, cfg)
  cfg = cfg or {}

  -- Ensure the NPC coroutine is always released even on early failure
  local function _finish_early(reason, msg)
    local cb = (cfg.on_finish or cfg._on_finish)
    if cb then
      local ok, err = pcall(cb, {
        player_won = false,
        reason     = reason or "deck_build_failed",
        error      = msg
      })
      if not ok then print("[card_battle] on_finish callback error: " .. tostring(err)) end
    end
  end

  -- 1) Build Player deck: prefer persisted deck, else random
  local deck1
  do
    local counts = load_persisted_deck_counts(pid)
    if counts then
      local d = materialize_deck_from_counts(pid, counts)
      if d and #d == 10 then deck1 = d end
    end
    if not deck1 then
      local err
      deck1, err = build_random_deck_from_collection(pid)
      if not deck1 then
        Net.message_player(pid, err or "Could not build your deck.")
        _finish_early("deck1_failed", err)
        return  -- IMPORTANT: we now notify and exit
      end
    end
  end

  -- 2) NPC deck: random from your collection (or cfg list)
  local deck2
  do
    local ids = cfg and cfg.npc_deck_ids
    if ids then
      local area_id = Net.get_player_area(pid)
      deck2 = _build_deck_from_id_list_for_area(area_id, ids)
    end
    if not deck2 then
      local err2
      deck2, err2 = build_random_deck_from_collection(pid)
      if not deck2 then
        Net.message_player(pid, err2 or "NPC could not build a deck.")
        _finish_early("deck2_failed", err2)
        return  -- IMPORTANT: we now notify and exit
      end
    end
  end

  -- Ensure both decks have ATK/DEF (safety)
  rehydrate_deck_stats(pid, deck1)
  rehydrate_deck_stats(pid, deck2)

  -- Shuffle both before opening draw
  if shuffle then
    shuffle(deck1)
    shuffle(deck2)
  end

  -- Build player states and draw opening 2
  local P1 = new_player_state(); P1.deck = deck1
  local P2 = new_player_state(); P2.deck = deck2
  draw_one(P1); draw_one(P1)
  draw_one(P2); draw_one(P2)

  local state = {
    npc_name      = (cfg and cfg.npc_name) or "NPC Duelist",
    players       = { [1]=P1, [2]=P2 },
    turn_player   = 1,
    turn_num      = 1,
    p1AttackLocked= true,
    finished      = false,
    noDrawThisTurn= { [1]=true, [2]=true }, -- no one draws on their very first turn
    turn_flags    = { hasSummoned=false, hasCast=false, hasAttacked=false, megaNext=false, rrkNext=false },
    pid           = pid,
    on_finish = cfg and (cfg.on_finish or cfg._on_finish),
  }

  battle_by_pid[pid] = state
  begin_turn(state)
  open_battle_board(pid)
end

-- ==== Unified helpers (put before the listeners) ====
-- Small helpers to know which board is currently “active”
local function _battle_active(pid)
  return (battle_by_pid and battle_by_pid[pid] ~= nil) and (battle_ui_open and battle_ui_open[pid] == true)
end
local function _trade_active(pid)
  return trader_by_pid and trader_by_pid[pid] ~= nil
end

-- ==== Click router (trimmed): JobBBS → Trader → ygo_pvp ====
Net:on("post_selection", function(event)
  local pid     = event.player_id
  local post_id = tostring(event.post_id or "")

  print(string.format("[custom] post_selection pid=%s post_id=%s", tostring(pid), post_id))

  -- 1) JobBBS clicks (let JobBBS decide if it wants to consume)
  if JobBBS and JobBBS.handle_post_selection then
    local ok, handled = pcall(JobBBS.handle_post_selection, event)
    if ok and handled then
      return
    end
  end

  -- 2) Trader clicks
  if _trade_active and _trade_active(pid) and handle_trade_post_selection then
    local ok, handled = pcall(handle_trade_post_selection, event)
    if ok and handled then
      return
    end
  end

  -- 3) YGO PVP clicks (lobby / duel table flow)
  if ygo_pvp and ygo_pvp.handle_post_selection then
    local ok, handled = pcall(ygo_pvp.handle_post_selection, event)
    if ok and handled then
      print("[custom] post_selection handled by ygo_pvp")
      return
    end
  end

  print("[custom] post_selection fell through; no handler consumed it")
end)


BATTLE_CLOSE_LOCK = (BATTLE_CLOSE_LOCK == nil) and true or BATTLE_CLOSE_LOCK
closing_for_refresh    = closing_for_refresh    or {}
closing_for_refresh_ts = closing_for_refresh_ts or {}
PROGRAM_REFRESH_WINDOW_S = PROGRAM_REFRESH_WINDOW_S or 0.35

Net:on("board_close", function(event)
  local pid = event.player_id
  local why = _G.__bbs_guard and _G.__bbs_guard.ignore_once and _G.__bbs_guard.ignore_once[pid]

  print(string.format("[custom][bbs] board_close pid=%s ignore_once=%s", tostring(pid), tostring(why)))

  -- If a foreign module asked us to ignore this close, do so and clear the flag
  if why then
    _G.__bbs_guard.ignore_once[pid] = nil
    print(string.format("[custom][bbs] skipping board_close logic for %s (reason: %s)", tostring(pid), why))
    return
  end

  -- If JobBBS is in a "waiting" flow, let it own the close semantics
  if JobBBS and JobBBS.is_waiting and JobBBS.is_waiting(pid) then
    return
  end

  -- YGO PVP close handling (duel-table / lobby cleanup)
  if ygo_pvp and ygo_pvp.handle_board_close then
    local ok, handled = pcall(ygo_pvp.handle_board_close, event)
    if ok and handled then
      print("[custom] board_close handled by ygo_pvp")
      return
    end
  end

  -- Trader reopen (programmatic)
  if trade_reopen and trade_reopen[pid] then
    trade_reopen[pid] = nil
    if trader_by_pid and trader_by_pid[pid] and open_trade_board then
      open_trade_board(pid)
    end
    return
  end

  -- Trader: swallow programmatic reopen-close
  if trade_refreshing and trade_refreshing[pid] then
    trade_refreshing[pid] = nil
    return
  end

  -- Legacy/alternate JobBBS hook (if you still have this module name in your project)
  if jobbbs and jobbbs.on_board_close then
    local ok, handled = pcall(jobbbs.on_board_close, event)
    if ok and handled then
      return
    end
  end

  print(string.format("[custom] board_close pid=%s (no action)", tostring(pid)))
end)

-- Clean up on join/leave
Net:on("player_join", function(event)
  local pid = event.player_id
  player_using_card_bbs[pid] = false
  in_actions_menu[pid] = false
  pending_actions_menu[pid] = false
  last_viewed_card_by_player[pid] = nil
  summoned_bot_by_player[pid] = nil
  open_list_after_close[pid] = false
  -- Emit a simple, uncolored, grep-friendly join line for the watcher
  local function safe(s) return (s and tostring(s):gsub("%s+"," ")) or "?" end
  local name = safe(Net.get_player_name(pid))
  local area = safe(Net.get_player_area(pid))
  io.write(("PLAYER_JOIN: %s | pid=%s | area=%s\n"):format(name, pid, area))
  io.stdout:flush()  -- ensure it hits logs.txt immediately even if stdout is block-buffered
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

function custom.clear_last_loaded_card(pid, title_opt)
  local cur = last_viewed_card_by_player[pid]
  if not cur then return end
  if (not title_opt) or tostring(cur.name) == tostring(title_opt) then
    last_viewed_card_by_player[pid] = nil
  end
end

-- === exports used by oncehub "Card Frame" ================================

-- 1) expose the last "loaded" card that was viewed (desc shown)
function custom.get_last_loaded_card(pid)
  -- last_viewed_card_by_player is defined earlier in this file
  return last_viewed_card_by_player and last_viewed_card_by_player[pid] or nil
end

-- 2) expose the display-name rule so other scripts can match bot names
function custom.display_name_for_title(title)
  return get_summon_display_name(title)
end

-- 3) let others reuse your in-front spawner if they want
custom.spawn_card_npc_for_all = spawn_card_npc_for_all

-- 4) coord-based spawner (same assets/name pipeline you already use)
function custom.spawn_card_npc_at(area_id, x, y, z, info)
  info = info or {}
  local raw_name  = info.name or info.title or "Card"
  local disp_name = get_summon_display_name(raw_name)

  -- prefer provided OW assets; otherwise derive from name just like your summoner
  local ow_png  = info.ow_png
  local ow_anim = info.ow_anim
  if not ow_png or not ow_anim then
    ow_png, ow_anim = build_overworld_paths_for_name(disp_name)
  end

  local ok, bot_id = pcall(Net.create_bot, {
    name               = disp_name,
    area_id            = area_id,
    x = x or 0, y = y or 0, z = z,
    texture_path       = ow_png,
    animation_path     = ow_anim,
    mug_animation_path = info.anim,
    animation          = "IDLE",
  })
  if not ok or not bot_id then return nil end
  pcall(Net.set_bot_name, bot_id, disp_name)
  return bot_id
end

print("[cards] custom plugin ready"); return custom
