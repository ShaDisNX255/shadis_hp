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
local open_battle_board

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

local function clear_card_viewer_state(pid)
  if not pid then return end
  card_list_open[pid] = nil

  -- Best-effort: many "cards" viewers leave this global/table set.
  local pam = rawget(_G, "pending_actions_menu")
  if type(pam) == "table" then
    pam[pid] = nil
  elseif pam ~= nil then
    _G.pending_actions_menu = false
  end

  -- If your cards module exposes resets, call them safely.
  local cardsmod = rawget(_G, "cards")
  if type(cardsmod) == "table" then
    if type(cardsmod.clear_pending) == "function" then pcall(cardsmod.clear_pending, pid) end
    if type(cardsmod.reset_for_pid) == "function" then pcall(cardsmod.reset_for_pid, pid) end
  end
end

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

-- Save a counts map { [item_id]=copies, ... } to ezmemory
local function persist_deck_counts(pid, counts)
  local secret = helpers.get_safe_player_secret(pid)
  local pmem   = ezmemory.get_player_memory(secret) or {}
  pmem[DECK_MEM_KEY] = counts or {}
  if ezmemory.set_player_memory then        -- common API
    ezmemory.set_player_memory(secret, pmem)
  elseif ezmemory.save_player_memory then   -- fallback name seen on some servers
    ezmemory.save_player_memory(secret, pmem)
  else
    -- No writer available; at least keep RAM cache
  end
  saved_deck_by_pid[pid] = { counts = counts or {} }
end

-- Load counts map from ezmemory (or RAM fallback)
local function load_persisted_deck_counts(pid)
  if saved_deck_by_pid[pid] and saved_deck_by_pid[pid].counts then
    return saved_deck_by_pid[pid].counts
  end
  local secret = helpers.get_safe_player_secret(pid)
  local pmem   = ezmemory.get_player_memory(secret) or {}
  local counts = pmem[DECK_MEM_KEY]
  if type(counts) == "table" then
    saved_deck_by_pid[pid] = { counts = counts } -- hydrate RAM cache
    return counts
  end
  return nil
end

-- Turn a {id=>count} map into a 10-card, fully-statted deck list
local function materialize_deck_from_counts(pid, counts)
  local deck = {}
  for id, n in pairs(counts or {}) do
    local info  = ezmemory.get_item_info(id)
    local title = (info and info.name) or tostring(id)

    -- parse stats either from info.description (fast) or from item meta
    local desc  = info and info.description or ""
    local ATK   = tonumber(tostring(desc):match("A:%s*(%d+)") or 0) or 0
    local DEF   = tonumber(tostring(desc):match("D:%s*(%d+)") or 0) or 0
    if ATK == 0 and DEF == 0 then
      local meta = read_item_meta_flexible(pid, id)
      local a, d = parse_atk_def_from_meta(meta)
      ATK, DEF = a or 0, d or 0
    end

    for i = 1, math.max(0, math.min(n or 0, 10 - #deck)) do
      deck[#deck+1] = { id=id, title=title, ATK=ATK, DEF=DEF }
      if #deck >= 10 then break end
    end
    if #deck >= 10 then break end
  end
  return deck
end

-- === ATK/DEF parsing & meta readers (drop-in) ===

local function _split_area_id(raw_id)
  -- Accept "area,id" or plain id; default area "default"
  local s = tostring(raw_id or "")
  local a, i = s:match("^([^,]+),(.+)$")
  if a and i then return a, i end
  return "default", s
end

local function parse_atk_def_from_text(text)
  if not text or text == "" then return nil, nil end
  text = tostring(text)

  -- Very tolerant patterns: catch "A: 2500", "ATK 2500", etc.
  -- Prefer numbers after A: / D:, but fall back to ATK/DEF tokens.
  local A = text:match("[Aa]%s*[:=]%s*(%d+)")
  local D = text:match("[Dd]%s*[:=]%s*(%d+)")

  if not A then A = text:match("[Aa][Tt][Kk]%s*[:=]?%s*(%d+)") end
  if not D then D = text:match("[Dd][Ee][Ff]%s*[:=]?%s*(%d+)") end

  return tonumber(A), tonumber(D)
end

-- Try to read "Description" custom property, then fall back to item info description
local function read_item_meta_flexible(pid, raw_id)
  local area, iid = _split_area_id(raw_id)
  -- custom property "Description"
  local ok1, desc_prop = pcall(ezmemory.get_item_custom_property, area, iid, "Description")
  if ok1 and desc_prop and desc_prop ~= "" then
    return { description = desc_prop }
  end
  -- fallback: info.description
  local info = ezmemory.get_item_info(iid)
  if info and info.description and info.description ~= "" then
    return { description = info.description, name = info.name }
  end
  return { description = "" }
end

local function hydrate_card_from_id(pid, card)
  -- card.id required; patch card.ATK/DEF in-place if discoverable
  if not card or not card.id then return card end
  local meta = read_item_meta_flexible(pid, card.id)
  local A, D = parse_atk_def_from_text(meta and meta.description or "")
  if A then card.ATK = A end
  if D then card.DEF = D end
  return card
end

local function rehydrate_deck_stats(pid, deck)
  if not deck then return end
  for _, c in ipairs(deck) do
    hydrate_card_from_id(pid, c)
  end
end

-- Totals across rarities for current counts
local function _rarity_totals(counts, poolmap)
  local total, urgdr_total, sr_total, r_total, c_total = 0, 0, 0, 0, 0
  for id, n in pairs(counts or {}) do
    n = tonumber(n or 0) or 0
    if n > 0 then
      total = total + n
      local row = poolmap[id]
      local rar = tostring((row and (row.rar or parse_rarity_tag(row.title))) or "C"):upper()
      if rar == "UR" or rar == "GDR" or rar == "GR" then urgdr_total = urgdr_total + n
      elseif rar == "SR" then sr_total = sr_total + n
      elseif rar == "R"  then r_total  = r_total  + n
      else c_total = c_total + n
      end
    end
  end
  return total, urgdr_total, sr_total, r_total, c_total
end

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

local function read_item_meta_flexible(pid, any_id)
  local key = tostring(any_id)
  if META_CACHE[key] ~= nil then
    return META_CACHE[key] or nil  -- false → cached miss
  end

  local area = Net.get_player_area(pid)
  local obj_id = any_id
  local a, i = key:match("^([^,]+),(%d+)$")
  if a and i then
    area   = a
    obj_id = tonumber(i)
  end

  local ok, meta = pcall(helpers.read_item_information, area, obj_id)
  if ok and meta then
    META_CACHE[key] = meta
    return meta
  end
  META_CACHE[key] = false  -- remember miss (prevents repeated noisy calls)
  return nil
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
  card_list_open[pid] = true
  local safe_secret   = helpers.get_safe_player_secret(pid)
  local player_memory = ezmemory.get_player_memory(safe_secret) or {}

  local entries = {}
  for item_id, qty in pairs(player_memory.items or {}) do
    if (qty or 0) > 0 then  -- ⬅️ only list cards you actually have
      local info = ezmemory.get_item_info(item_id)
      if info and info.name and string.find(info.name, "[", 1, true) ~= nil then
        -- Put quantity on the RIGHT; omit when qty < 2
        local right_qty = (qty and qty >= 2) and tostring(qty) or ""
        entries[#entries+1] = {
          id     = item_id,
          read   = true,
          title  = info.name,   -- left: name with rarity tag ([C]/[R]/[SR]/[UR]/...)
          author = right_qty,   -- right: "2", "3", ... (no "x")
          _raw   = info.name,   -- keep raw for sorting
        }
      end
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
  table.insert(entries, 1, { id = "__deck_edit__", read = true, title = "Deck Editor" })
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

  --- Open the Card Collection (same as old L behaviour).
  function api.open_card_list(pid)
    -- This is your existing local helper; we just wrap it.
    return open_card_list(pid)
  end
end

-- Wrapper so LMenu can open the card collection
function custom.open_card_collection_from_lmenu(pid)
  return open_card_list(pid)
end

-- If LMenu is available, wire its Cards option to our collection
if LMenu and LMenu.set_cards_callback then
  LMenu.set_cards_callback(function(pid)
    custom.open_card_collection_from_lmenu(pid)
  end)
end

-- === Duel↔Overworld helpers (spawn “behind”, reuse your summon table) ===

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

-- ==========
----------------------------------------------------------------------
-- Mini YGO — KO Mode (Monsters-Only, Single Slot) — Battle BBS
-- Public API: custom.start_card_battle(pid, { npc_name = "Duelist" })
----------------------------------------------------------------------

-- === Battle constants / IDs ===
local BATTLE_BOARD_COLOR = { r=255, g=200, b=150 }

local BTL_CANCEL     = "__b_cancel__"
local BTL_CONCEDE    = "__b_concede__"
local BTL_NEXT       = "__b_next__"
local BTL_PREV       = "__b_prev__"
local BTL_OK         = "__b_ok__"
local BTL_VIEW_ME  = "__b_view_me__"
local BTL_VIEW_OPP = "__b_view_opp__"
local BTL_DSEL_PREFIX = "__b_dsel__"   -- +index (e.g., "__b_dsel__3")
local BTL_DCONF       = "__b_dok__"
local BTL_DCANCEL     = "__b_dcancel__"

-- action rows
local BTL_SUMMON     = "__b_summon__"
local BTL_SET        = "__b_set__"
local BTL_CAST       = "__b_cast__"
local BTL_ATTACK     = "__b_attack__"
local BTL_END        = "__b_end__"
local BTL_SWITCH     = "__b_switch__"

-- cast submenus
local BTL_CAST_PICK  = "__b_cast_pick__:"      -- +spell_key
local BTL_PAY_PICK   = "__b_pay__:"            -- +item_id
local BTL_TARGET     = "__b_target__:"         -- +who / +noop

-- guard flags / reopen like Trader
battle_by_pid      = battle_by_pid or {}   -- [pid] = state
battle_reopen      = battle_reopen or {}   -- [pid] = true to reopen after close
battle_refreshing  = battle_refreshing or {}

-- simple helpers
-- === Battle BBS "lock" (prevents accidental closing with B) ===
local LOCK_BATTLE_BBS = true
local _b_warned = _b_warned or {}

local function _reopen_battle_now_or_later(pid)
  -- If a modal (announcer) is up, defer reopen until it closes
  if _ann_busy and _ann_busy[pid] then
    _reopen_pending[pid] = true
    return
  end
  if open_battle_board then
    open_battle_board(pid)
  end
end

local function def_bar(cur, max)
  cur = tonumber(cur or 0) or 0
  max = tonumber(max or 0) or 0
  if max <= 0 then return "" end
  local SLOTS = 6
  -- round to nearest slot
  local filled = math.floor((cur * SLOTS + max/2) / max)
  if filled < 0 then filled = 0 elseif filled > SLOTS then filled = SLOTS end
  return "[" .. string.rep("=", filled) .. string.rep("-", SLOTS - filled) .. "]"
end
-- Do we have a monster on the field?
local function has_monster(plr)
  return plr and plr.field ~= nil
end

-- Any spell currently castable by player idx (by simple cost check)?
local function any_castable_spell(st, idx)
  local me = st.players[idx]
  if not has_monster(me) then return false end
  local h = #me.hand
  for _, sp in ipairs(SPELLS) do
    if h >= (sp.cost or 0) then return true end
  end
  return false
end

-- Look up a spell by key (so AI/UI don’t depend on table index order)
local function SP(key)
  for _, sp in ipairs(SPELLS) do
    if sp.key == key then return sp end
  end
  return nil
end

local function has_monster(plr)
  return plr and plr.field ~= nil
end

local function can_switch_now(st, me_idx)
  local f = st.players[me_idx].field
  if not f then return false end
  if st.turn_flags.hasSwitched then return false end
  if f.lockUntilTurn and st.turn_num <= f.lockUntilTurn then return false end
  if f._enteredTurn and f._enteredTurn == st.turn_num then return false end -- cannot switch same-turn
  return true  -- allow SET → ATK and ATK ↔ DEF (when legal)
end
local function clamp(n, a, b) if n < a then return a elseif n > b then return b else return n end end
local function deepcopy(t) if type(t)~="table" then return t end local r={} for k,v in pairs(t) do r[k]=deepcopy(v) end return r end
local function shuffle(arr) for i=#arr,2,-1 do local j=math.random(i) arr[i],arr[j]=arr[j],arr[i] end return arr end

-- === Parse ATK/DEF from the card's custom property "Description" ===
-- Expected examples:
--   "URare: Dark Magician - A: 2500 / D: 2100"
--   "SRare: Gaia - A:3000 / D: 1200"
local function parse_atk_def_from_meta(meta)
  local d = ""
  if meta then
    local cp = meta.custom_properties
    d = (cp and (cp["Description"] or cp["description"])) or meta.description or ""
  end
  d = tostring(d)
  local a = tonumber(d:match("A:%s*(%d+)") or 0) or 0
  local b = tonumber(d:match("D:%s*(%d+)") or 0) or 0
  return a, b
end

-- === Turn/phase model ===
-- Single slot per side: field is either nil or { card={...}, pos="ATK"/"DEF"/"SET", curDEF, lockUntilTurn }
-- "hand" is a list of card entries; "deck" a face-down stack; "grave" list of card entries
-- Card entry: { id=item_id, title=name, rarity="C|R|SR|UR|GDR", ATK=int, DEF=int }
local function new_player_state()
  return { deck={}, hand={}, grave={}, field=nil, KOs=0 }
end

base_title = function(title)
  local after = tostring(title or ""):match("%](.*)")
  if after then after = after:gsub("^%s+",""):gsub("%s+$",""); if after ~= "" then return after end end
  return (tostring(title or ""):gsub("[%[%]]",""))
end

-- === Card snapshot of player's collection (name + counts + ids) ===
local function snapshot_player_collection(pid)
  local secret = helpers.get_safe_player_secret(pid)
  local pmem = ezmemory.get_player_memory(secret)
  local rows = {}  -- { id, title, qty, rar }
  for item_id, qty in pairs(pmem.items or {}) do
    if qty and qty > 0 then
      local info = ezmemory.get_item_info(item_id)
      if info and info.name and string.find(info.name, "[", 1, true) ~= nil then
        rows[#rows+1] = { id=item_id, title=info.name, qty=qty, rar=parse_rarity_tag(info.name) }
      end
    end
  end
  return rows
end

-- Builds a 10-card deck from the player's collection, respecting:
-- - Per-title caps: UR/GDR=1, SR<=2, R<=3, C<=owned
-- - Combined across the deck: at most ONE total among all UR/GDR
-- Parsing order for stats:
--   1) ezmemory.get_item_info(id).description
--   2) read_item_meta_flexible(pid, id) -> custom_properties["Description"/"description"] or meta.description
local function build_random_deck_from_collection(pid)
  local pool = snapshot_player_collection(pid)
  if not pool or #pool == 0 then
    return nil, "You have no cards in your collection."
  end

  -- Expand to copies with stats
  local urgdr, sr, rr, cc = {}, {}, {}, {}
  for _, row in ipairs(pool) do
    local qty = row.qty or 0
    if qty > 0 then
      local rar = tostring(row.rar or parse_rarity_tag(row.title) or "C"):upper()
      for i=1,qty do
        local meta = read_item_meta_flexible(pid, row.id)
        local A, D = parse_atk_def_from_meta(meta)
        local copy = { id=row.id, title=row.title, rarity=rar, ATK=A or 0, DEF=D or 0 }
        if rar == "UR" or rar == "GDR" or rar == "GR" then
          -- keep one “candidate” per physical copy, but we will only take 1 total later
          table.insert(urgdr, copy)
        elseif rar == "SR" then
          table.insert(sr, copy)
        elseif rar == "R" then
          table.insert(rr, copy)
        else
          table.insert(cc, copy)
        end
      end
    end
  end

  local function pick_many(src, want)
    local out = {}
    shuffle(src)
    for i=1, math.min(want, #src) do out[#out+1] = deepcopy(src[i]) end
    return out
  end

  local deck = {}
  -- UR/GDR: pick at most 1 total
  if #urgdr > 0 then
    shuffle(urgdr)
    deck[#deck+1] = deepcopy(urgdr[1])
  end
  -- SR: pick at most 2 total across SR
  local grab_sr = pick_many(sr, 2)
  for _,c in ipairs(grab_sr) do deck[#deck+1] = c end
  -- R: pick at most 3 total across R
  local grab_r = pick_many(rr, 3)
  for _,c in ipairs(grab_r) do deck[#deck+1] = c end
  -- Fill with commons
  shuffle(cc)
  local i = 1
  while #deck < 10 and i <= #cc do
    deck[#deck+1] = deepcopy(cc[i]); i = i + 1
  end

  if #deck < 10 then
    return nil, "Not enough eligible cards to build a 10-card deck under rarity totals (need more Commons or lower-rarity cards)."
  end

  shuffle(deck)
  return deck
end

-- === Core battle math ===
-- DEF chip H:
--  - if ATK < 1000 → H = ATK
--  - if ATK ≥ 1000 → H = floor(ATK/2)
local function chip_from_atk(ATK)
  ATK = tonumber(ATK or 0) or 0
  if ATK < 1000 then
    return ATK
  else
    return math.floor(ATK / 2)
  end
end

local function can_attack(state, me_idx)
  local me, opp = state.players[me_idx], state.players[3 - me_idx]
  if state.turn_flags.hasAttacked then return false end
  if state.turn_num == 1 and me_idx == 1 and state.p1AttackLocked then return false end
  return (me.field and me.field.pos == "ATK") and (opp.field ~= nil)
end

-- Per-player last duel result (so NPC scripts can read outcome later)
local _last_duel_result = _last_duel_result or {}

local function _record_duel_result_for_all_viewers(st)
  if not st or not st.winner then return end
  local w = st.winner
  local function put(pid, idx)
    if not pid then return end
    _last_duel_result[pid] = {
      player_won = (w == idx),
      winner     = w,
      npc_name   = st.npc_name
    }
  end
  if st.pids then
    put(st.pids[1], 1)
    put(st.pids[2], 2)
  else
    put(st.pid, 1)
  end
end

-- (optional) expose for debugging or other scripts
function custom.get_last_duel_result(pid)
  return _last_duel_result and _last_duel_result[pid] or nil
end

do_KO = function(state, victim_idx)
  local vic = state.players[victim_idx]
  if vic.field then
    table.insert(vic.grave, vic.field.card)
    vic.field = nil
  end

  _duel_on_monster_destroyed(state, victim_idx)


  local killer_idx = 3 - victim_idx
  local killer     = state.players[killer_idx]
  killer.KOs = (killer.KOs or 0) + 1

  -- Announce the updated KO total for the player who scored it
  if battle_announce then
    local subj = "You"
    if labels_for then subj = (labels_for(state, killer_idx)) end  -- take the subject ("You" or NPC name)
    local verb = (subj == "You") and "have" or "has"
    local ko_word = (killer.KOs == 1) and "KO" or "KOs"
    battle_announce(state, string.format("%s %s %d %s.", subj, verb, killer.KOs, ko_word))
  end

  if killer.KOs >= 3 then
    state.finished = true
    state.winner   = killer_idx

    _record_duel_result_for_all_viewers(state)
    _duel_cleanup_overworld(state)

    -- Free the duel table only for PVP matches
    if not state.table_freed then
      local ok, err = pcall(function()
        if state.mode == "pvp" and ygo_pvp and ygo_pvp.on_ygo_pvp_end then
          local winner_pid = state.pids and state.pids[killer_idx]
          local loser_pid  = state.pids and state.pids[3 - killer_idx]
          if winner_pid and loser_pid then
            ygo_pvp.on_ygo_pvp_end(winner_pid, loser_pid, { table_id = state.table_id })
          end
        end
      end)
      if not ok then print("[ygo] on_ygo_pvp_end error: "..tostring(err)) end
      state.table_freed = true
    end
  end
end

local function resolve_attack(state)
  local me_idx  = state.turn_player
  local opp_idx = 3 - me_idx
  local A = state.players[me_idx].field
  local D = state.players[opp_idx].field
  if not A or not D then return end

  local atkSubj, atkPoss = labels_for(state, me_idx)
  local defSubj, defPoss = labels_for(state, opp_idx)
  local an = short_name(A.card.title)
  local dn = short_name(D.card.title)

  -- Reveal-on-block for Sets
  if D.pos == "SET" then
    D.pos = "DEF"
    battle_announce(state, "Reveal: " .. defPoss .. " Set is " .. dn .. " [DEF " .. D.curDEF .. "/" .. D.card.DEF .. "]")
	_duel_spawn_faceup_for_seat(state, opp_idx)
  end

  if D.pos == "ATK" then
    battle_announce(state, "Attack: " .. atkPoss .. " " .. an .. " (ATK " .. A.card.ATK .. ") vs " ..
                              defPoss .. " " .. dn .. " (ATK " .. D.card.ATK .. ")")
    if A.card.ATK > D.card.ATK then
      battle_announce(state, defPoss .. " " .. dn .. " was destroyed.")
      do_KO(state, opp_idx)
    elseif A.card.ATK < D.card.ATK then
      battle_announce(state, atkPoss .. " " .. an .. " was destroyed.")
      do_KO(state, me_idx)
    else
      battle_announce(state, "Both monsters were destroyed.")
      do_KO(state, me_idx); do_KO(state, opp_idx)
    end
  else
    -- DEF battle (chip)
    local H = chip_from_atk(A.card.ATK)
    if state.turn_flags.megaNext then H = A.card.ATK end
    if state.turn_flags.rrkNext  then H = H + 1000 end

    battle_announce(state, "Attack: " .. atkPoss .. " " .. an .. " (chip " .. H .. ") vs " ..
                              defPoss .. " " .. dn .. " [DEF " .. D.curDEF .. "/" .. D.card.DEF .. "]")

    if H >= D.curDEF then
      battle_announce(state, defPoss .. " " .. dn .. " was destroyed.")
      do_KO(state, opp_idx)
    else
      D.curDEF = math.max(0, D.curDEF - H)
      battle_announce(state, defPoss .. " " .. dn .. " DEF reduced to " .. D.curDEF .. "/" .. D.card.DEF)
      A.pos = "DEF" -- Counter-Set only if defender survived
	  A._zero_def_grace = true
	  state.turn_flags.hasSwitched = true
    end

    -- Megamorph after-battle: attacker goes to DEF if still on field
    if state.turn_flags.megaNext then
      local meF = state.players[me_idx].field
      if meF then
        meF.pos = "DEF"
        state.turn_flags.hasSwitched = true
	  end
    end
  end

  state.turn_flags.hasAttacked = true
  state.turn_flags.megaNext = false
  state.turn_flags.rrkNext  = false
  cleanup_zero_def(state)
end

-- === Spells ===
-- Hand acts as mana: discard N cards to pay cost (does not touch player’s real inventory)
SPELLS = {
  -- cost 1
  { key="reinforce", name="Reinforcements (+500 ATK this turn)", cost=1, who="meATK",
    apply=function(state, me_idx)
      local f = state.players[me_idx].field
      if f and f.pos == "ATK" then
        f._tempATK = (f._tempATK or 0) + 500
        f.card.ATK = f.card.ATK + 500
        state.turn_flags._undoATK = (state.turn_flags._undoATK or 0) + 500
        return "Your monster gets +500 ATK this turn."
      end
      return "No face-up ATK monster to buff."
    end },

  { key="chip500", name="Shield Crush (Chip -500 DEF)", cost=1, who="oppDEF",
    apply=function(state, me_idx)
      local opp = state.players[3 - me_idx]
      if opp.field and opp.field.pos == "DEF" then
        opp.field._zero_def_grace = nil
        opp.field.curDEF = math.max(0, opp.field.curDEF - 500)
        opp.field._zero_def_from_effect = true
        return "Opponent DEF -500 (persistent)."
      end
      return "No valid face-up DEF target."
    end },

  { key="cease1", name="Ceasefire (Reveal Set)", cost=1, who="oppSET",
    apply=function(state, me_idx)
      local opp = state.players[3 - me_idx]
      if opp.field and opp.field.pos == "SET" then
        opp.field.pos = "DEF"
		_duel_spawn_faceup_for_seat(state, 3 - me_idx)
        return "Revealed opponent’s Set monster (now face-up DEF)."
      end
      return "No Set monster to reveal."
    end },

  -- cost 2
  { key="axe", name="Axe of Despair (+1000 ATK this turn)", cost=2, who="meATK",
    apply=function(state, me_idx)
      local f = state.players[me_idx].field
      if f and f.pos == "ATK" then
        f._tempATK = (f._tempATK or 0) + 1000
        f.card.ATK = f.card.ATK + 1000
        state.turn_flags._undoATK = (state.turn_flags._undoATK or 0) + 1000
        return "Your monster gets +1000 ATK this turn."
      end
      return "No face-up ATK monster to buff."
    end },

  { key="shield1000", name="Shield Crush (-1000 DEF)", cost=2, who="oppDEF",
    apply=function(state, me_idx)
      local opp = state.players[3 - me_idx]
      if opp.field and opp.field.pos == "DEF" then
        opp.field._zero_def_grace = nil
        opp.field.curDEF = math.max(0, opp.field.curDEF - 1000)
        opp.field._zero_def_from_effect = true
        return "Opponent DEF -1000 (persistent)."
      end
      return "No valid face-up DEF target."
    end },

  { key="econt", name="Enemy Controller (ATK→DEF, lock)", cost=2, who="oppATK",
    apply=function(state, me_idx)
      local opp = state.players[3 - me_idx]
      if opp.field and opp.field.pos == "ATK" then
        opp.field.pos = "DEF"
        opp.field.lockUntilTurn = state.turn_num + 1 -- until end of its controller’s next turn
        return "Switched opponent to DEF and position-locked."
      end
      return "No opponent ATK monster."
    end },

  -- cost 3
  { key="riryoku", name="Riryoku (+1000 to chip on next attack)", cost=3, who="none",
    apply=function(state, me_idx)
      state.turn_flags.rrkNext = true
      return "Next attack’s chip gets +1000."
    end },

  { key="shrink", name="Shrink (-1000 ATK until end of next turn)", cost=3, who="anyFACE",
    apply=function(state, me_idx)
      local me = state.players[me_idx]; local opp = state.players[3 - me_idx]
      local t = (opp.field and opp.field.pos ~= "SET") and opp.field or (me.field and me.field.pos ~= "SET" and me.field or nil)
      if not t then return "No face-up target." end
      t.card.ATK = t.card.ATK - 1000
      t._atkRevert = (t._atkRevert or 0) - 1000
      t._revertOnTurn = state.turn_num + 2
      return "Target -1000 ATK until end of its controller’s next turn."
    end },

  -- cost 4
  { key="mega", name="Megamorph (next attack uses full ATK as chip; then your attacker DEF)", cost=4, who="none",
    apply=function(state, me_idx)
      state.turn_flags.megaNext = true
      return "Next attack uses FULL ATK as chip. After battle your attacker goes to DEF."
    end },

  { key="smash", name="Smashing Ground (opp DEF to 1000)", cost=4, who="oppDEF",
    apply=function(state, me_idx)
      local opp = state.players[3 - me_idx]
      if opp.field and opp.field.pos == "DEF" then
        opp.field.curDEF = 1000
        return "Set opponent DEF to 1000."
      end
      return "No face-up DEF target."
    end },

  { key="castle", name="Castle Walls (+1000 DEF up to printed)", cost=4, who="meDEF",
    apply=function(state, me_idx)
      local me = state.players[me_idx]
      if me.field and me.field.pos == "DEF" then
        local maxDEF = me.field.card.DEF
        me.field.curDEF = clamp(me.field.curDEF + 1000, 0, maxDEF)
        return "Your DEF +1000 (capped at printed DEF)."
      end
      return "No face-up DEF monster."
    end },
}

-- === Re-balance the spell list ===
local function retune_spells()
  if not SPELLS then return end

  -- Index by key for quick edits
  local bykey = {}
  for _, sp in ipairs(SPELLS) do bykey[sp.key] = sp end

  local new = {}

  -- Keep Ceasefire (your key is "cease1") at cost 1
  if bykey["cease1"] then bykey["cease1"].cost = 1; table.insert(new, bykey["cease1"]) end

  -- Reinforcements (+500 ATK) → cost 2
  if bykey["reinforce"] then bykey["reinforce"].cost = 2; table.insert(new, bykey["reinforce"]) end

  -- Shield Crush (-500 DEF) → cost 2 (your key is "chip500")
  if bykey["chip500"] then bykey["chip500"].cost = 2; table.insert(new, bykey["chip500"]) end

  table.insert(new, {
    key  = "stopatk",
    cost = 2,
    name = "Stop Attack (Change opponent from ATK to DEF)",
    apply = function(st, me_idx)
      local opp_idx = 3 - me_idx
      local opp = st.players[opp_idx]
      if opp.field and opp.field.pos == "ATK" then
        opp.field.pos = "DEF"
        local poss = (labels_for and select(2, labels_for(st, opp_idx)))
                    or ((opp_idx == 1) and "Your" or ((st.npc_name or "NPC").."'s"))
        local nm = short_name(opp.field.card.title)
        return string.format("Stop Attack: %s %s switched to DEF.", poss, nm)
      end
      return "No opponent ATK monster."
    end
  })

  -- Axe of Despair (+1000 ATK) → cost 3
  if bykey["axe"] then bykey["axe"].cost = 3; table.insert(new, bykey["axe"]) end

  -- Shield Crush (-1000 DEF) → cost 3
  if bykey["shield1000"] then bykey["shield1000"].cost = 3; table.insert(new, bykey["shield1000"]) end

  -- Shrink stays cost 3 (enforce)
  if bykey["shrink"] then bykey["shrink"].cost = 3; table.insert(new, bykey["shrink"]) end

  -- Remove: Enemy Controller (econt), Riryoku (riryoku), and all your old cost-4 spells (mega, smash, castle)

  -- Add Raigeki (cost 4): destroy opponent's monster regardless of position (even Set)
  table.insert(new, {
    key = "raigeki",
    cost = 4,
    name = "Raigeki (Destroy opponent's monster)",
    apply = function(st, me_idx)
      local opp_idx = 3 - me_idx
      local f = st.players[opp_idx].field
      if not f then return "Raigeki: No target." end
      local poss = (labels_for and select(2, labels_for(st, opp_idx))) or ((opp_idx == 1) and "Your" or ((st.npc_name or "NPC").."'s"))
      local nm = short_name(f.card.title)
      do_KO(st, opp_idx)
      return string.format("Raigeki: %s %s was destroyed.", poss, nm)
    end
  })

  SPELLS = new
end

-- Call once after defining SPELLS
retune_spells()

-- === Utility: draw, reshuffle from grave when needed ===
local function draw_one(p)
  -- hard hand cap
  if #p.hand >= 4 then return end

  if #p.deck == 0 then
    if #p.grave > 0 then
      for i = #p.grave, 1, -1 do
        table.insert(p.deck, p.grave[i]); p.grave[i] = nil
      end
      shuffle(p.deck)
    end
  end
  if #p.deck > 0 then
    table.insert(p.hand, table.remove(p.deck))
  end
end

-- === Start-of-turn cleanup / end-of-turn cleanup ===
local function begin_turn(state)
  local me = state.players[state.turn_player]
  state.turn_flags = { hasSummoned=false, hasCast=false, hasAttacked=false, megaNext=false, rrkNext=false, _undoATK=0 }
  -- unlock positions if lock expired
  for i=1,2 do
    local f = state.players[i].field
    if f and f.lockUntilTurn and state.turn_num > f.lockUntilTurn then f.lockUntilTurn = nil end
    if f and f._revertOnTurn and state.turn_num >= f._revertOnTurn then
      if f._atkRevert and f._atkRevert ~= 0 then f.card.ATK = f.card.ATK - f._atkRevert; f._atkRevert = 0 end
      f._revertOnTurn = nil
    end
  end
  cleanup_zero_def(state)
  -- Draw (except no one draws on their FIRST turn)
  if not state.noDrawThisTurn[state.turn_player] then draw_one(me) end
  state.noDrawThisTurn[state.turn_player] = nil
end

local function end_turn(state)
  -- undo ATK buffs that say "this turn"
  if state.turn_flags._undoATK and state.turn_flags._undoATK ~= 0 then
    local f = state.players[state.turn_player].field
    if f then f.card.ATK = f.card.ATK - state.turn_flags._undoATK end
  end
  -- hand size 4
  local me = state.players[state.turn_player]
  while #me.hand > 4 do table.remove(me.hand, #me.hand) end  -- discard from end (simple)
  state.turn_player = 3 - state.turn_player
  state.turn_num = state.turn_num + 1
  begin_turn(state)
end

-- === Summon / Set ===
local function can_place(me, flags)
  if flags.hasSummoned then return false end
  return me.field == nil
end

local function do_summon(me, hand_idx)
  local c = table.remove(me.hand, hand_idx)
  me.field = { card=deepcopy(c), pos="ATK", curDEF=c.DEF }
end

local function do_set(me, hand_idx)
  local c = table.remove(me.hand, hand_idx)
  me.field = { card=deepcopy(c), pos="SET", curDEF=c.DEF }
end

-- === NPC AI (aggressive vs SET; avoids stalling in face-up DEF) ===
local function npc_take_turn(state)
  local me   = state.players[2]
  local opp  = state.players[1]

  -- find a spell by key (local helper; no global SP dependency)
  local function SPkey(key)
    if not SPELLS then return nil end
    for _, sp in ipairs(SPELLS) do
      if sp.key == key then return sp end
    end
    return nil
  end

  -- Pay & apply spell by key; announce only on success
  local function npc_cast(spkey, announce_text)
    local sp = SPkey(spkey); if not sp then return false end
    local cost = sp.cost or 0
    if #me.hand < cost then return false end
    if not npc_pay_cost(state, 2, cost) then return false end
    local msg = sp.apply(state, 2)
    if not msg or msg:match("^No ") then
      -- (Optional) refund path could go here; we keep simple.
      return false
    end
    state.turn_flags.hasCast = true
    if announce_text then battle_announce(state, fmt_npc(state) .. " cast " .. announce_text) end
    return true
  end

  local function ensure_atk()
    if me.field and me.field.pos ~= "ATK" then
      me.field.pos = "ATK"
      battle_announce(state, fmt_npc(state) .. " switched its monster to ATK.")
      -- NOTE: not marking hasSwitched here because this helper is used before buffs;
      -- we only mark when we *decide* to switch for strategy below.
    end
  end

  local opp_is_def = (opp.field and (opp.field.pos == "DEF" or opp.field.pos == "SET")) or false

  -- ---------- PRE-ACTION: improve stance ----------
  if me.field and can_switch_now and can_switch_now(state, 2) then
    if me.field.pos == "SET" then
      me.field.pos = "ATK"
      state.turn_flags.hasSwitched = true
      battle_announce(state, fmt_npc(state) .. " flipped its monster to ATK.")
    elseif me.field.pos == "DEF" then
      -- CHANGED: if opponent is DEF/SET, always go ATK (safe to swing)
      if opp_is_def then
        me.field.pos = "ATK"
        state.turn_flags.hasSwitched = true
        battle_announce(state, fmt_npc(state) .. " switched its monster to ATK.")
      else
        -- vs opponent ATK: keep your original “try to beat them” logic
        if opp.field and opp.field.pos == "ATK" then
          local plan = npc_plan_to_beat(opp.field.card.ATK or 0, me.field.card.ATK or 0, #me.hand)
          if plan then
            -- be in ATK before using ATK buffs (they only apply to face-up ATK)
            if me.field.pos ~= "ATK" then
              me.field.pos = "ATK"
              state.turn_flags.hasSwitched = true
              battle_announce(state, fmt_npc(state) .. " switched its monster to ATK.")
            end
            if not state.turn_flags.hasCast and plan.use ~= "none" then
              if plan.use == "axe"       then npc_cast("axe",        "Axe of Despair (+1000 ATK).") end
              if plan.use == "reinforce" then npc_cast("reinforce",  "Reinforcements (+500 ATK).") end
              if plan.use == "shrink" and opp.field and opp.field.pos ~= "SET" then
                npc_cast("shrink", "Shrink (-1000 ATK).")
              end
            end
          end
        end
      end
    end
  end

  -- ---------- MAIN PHASE: summon/set if empty ----------
  if not state.turn_flags.hasSummoned and not me.field then
    if #me.hand == 0 then draw_one(me) end
    if #me.hand > 0 then
      if opp.field and opp.field.pos == "ATK" then
        -- unchanged: try to find a plan to beat their ATK; else Set best DEF
        local oppATK = opp.field.card.ATK or 0
        local found_plan, best_idx = nil, 1
        table.sort(me.hand, function(a,b) return (a.ATK - a.DEF) > (b.ATK - b.DEF) end)
        for i, c in ipairs(me.hand) do
          local plan = npc_plan_to_beat(oppATK, c.ATK or 0, #me.hand - 1)
          if plan then best_idx = i; found_plan = plan; break end
        end
        local c = me.hand[best_idx]
        if found_plan then
          do_summon(me, best_idx); state.turn_flags.hasSummoned = true; me.field._enteredTurn = state.turn_num
          battle_announce(state, fmt_npc(state) .. " Summoned " .. short_name(c.title) .. " [ATK " .. (c.ATK or 0) .. "]")
          -- cast needed pump/debuff now (we are already ATK after summoning)
          if not state.turn_flags.hasCast and found_plan.use ~= "none" then
            if found_plan.use == "axe"       then npc_cast("axe",        "Axe of Despair (+1000 ATK).") end
            if found_plan.use == "reinforce" then npc_cast("reinforce",  "Reinforcements (+500 ATK).") end
            if found_plan.use == "shrink" and opp.field and opp.field.pos ~= "SET" then
              npc_cast("shrink", "Shrink (-1000 ATK).")
            end
          end
        else
          -- Can't win into ATK → Set best defender
          table.sort(me.hand, function(a,b) return (a.DEF or 0) > (b.DEF or 0) end)
          c = me.hand[1]
          do_set(me, 1); state.turn_flags.hasSummoned = true; me.field._enteredTurn = state.turn_num
          battle_announce(state, fmt_npc(state) .. " Set a monster.")
        end

      elseif opp_is_def then
        -- CHANGED: opponent in DEF/SET → ALWAYS summon best attacker and swing
        table.sort(me.hand, function(a,b) return (a.ATK or 0) > (b.ATK or 0) end)
        local c = me.hand[1]
        do_summon(me, 1); state.turn_flags.hasSummoned = true; me.field._enteredTurn = state.turn_num
        battle_announce(state, fmt_npc(state) .. " Summoned " .. short_name(c.title) .. " [ATK " .. (c.ATK or 0) .. "]")

      else
        -- Opponent empty: best attacker (unchanged)
        table.sort(me.hand, function(a,b) return (a.ATK or 0) > (b.ATK or 0) end)
        local c = me.hand[1]
        do_summon(me, 1); state.turn_flags.hasSummoned = true; me.field._enteredTurn = state.turn_num
        battle_announce(state, fmt_npc(state) .. " Summoned " .. short_name(c.title) .. " [ATK " .. (c.ATK or 0) .. "]")
      end
    end
  end

  -- Anti-DEF utility (optional). npc_cast checks cost & validity itself.
  if not state.turn_flags.hasCast and opp_is_def then
    npc_cast("shield1000", "Shield Crush (-1000 DEF).")
  end

  -- CHANGED: if we still have a monster in DEF but opponent is DEF/SET, try to flip to ATK right before attacking
  if me.field and opp_is_def and me.field.pos ~= "ATK" and can_switch_now and can_switch_now(state, 2) then
    me.field.pos = "ATK"
    state.turn_flags.hasSwitched = true
    battle_announce(state, fmt_npc(state) .. " switched its monster to ATK.")
  end

  -- Attack if possible
  if can_attack(state, 2) then
    resolve_attack(state)
  end

  -- Announce end of NPC turn (PVP shows both players; PvE shows local)
  if state.pids then
    announce_both(state, (fmt_npc(state) .. " ended their turn."))
  else
    battle_announce(state, (fmt_npc(state) .. " ended its turn."))
  end

  end_turn(state)
end

-- Show name + position; mask Set names for opponent only
local function name_pos_label(f, mask_set)
  if not f then return "(empty)" end
  local pos = (f.pos == "SET") and "SET" or f.pos
  if mask_set and f.pos == "SET" then
    return string.format("(Set Monster) [%s]", pos)
  end
  local base = base_title(f.card.title)
  return string.format("%s [%s]", base, pos)
end

local function stats_line(f, mask_set)
  if not f then return "   -" end

  local ATK = (f.card and f.card.ATK) or 0
  local DEF = (f.card and f.card.DEF) or 0

  if f.pos == "SET" then
    if mask_set then
      -- Opponent's face-down: show nothing
      return "   (face-down)"
    else
      -- Your own face-down: pick one of these styles (uncomment one)
      -- return string.format("   DEF ?/%d", DEF)   -- show printed DEF but keep current hidden
      return "   (face-down)"                       -- fully hidden
    end

  elseif f.pos == "ATK" then
    return string.format("   ATK %d", ATK)

  else -- face-up DEF
    local cur = tonumber(f.curDEF or DEF) or 0
    local max = tonumber(DEF) or cur
    local bar = (type(def_bar) == "function") and (" "..def_bar(cur, max)) or ""
    return string.format(" DEF %d/%d%s", cur, max, bar)
  end
end

local function field_label(f)
  if not f then return "(empty)" end
  local base = base_title(f.card.title)
  local pos = f.pos == "SET" and "SET" or f.pos
  if f.pos == "ATK" then
    return string.format("%s [ATK %d]", base, f.card.ATK)
  elseif f.pos == "DEF" then
    return string.format("%s [DEF %d/%d]", base, f.curDEF, f.card.DEF)
  else
    return string.format("(Set) %s [DEF ?/%d]", base, f.card.DEF)
  end
end

local function battle_title(st)
  local p1 = (st.players and st.players[1]) or {}
  local p2 = (st.players and st.players[2]) or {}

  local n1 = (p1.name and tostring(p1.name)) or "P1"
  local n2 = (p2.name and tostring(p2.name)) or (st.npc_name or "NPC")

  -- KO counters (default 0)
  local k1 = tonumber(p1.KOs or 0) or 0
  local k2 = tonumber(p2.KOs or 0) or 0
  local turn = tonumber(st.turn_num or 1) or 1

  if st.mode == "pvp" then
    return string.format("Duel: %s vs %s  |  KOs: %s %d - %d %s  |  Turn %d",
      n1, n2, n1, k1, k2, n2, turn)
  else
    -- PvE keeps the NPC name
    local npc = st.npc_name or "NPC"
    return string.format("Battle vs %s  |  KOs: You %d - %d %s  |  Turn %d",
      npc, k1, k2, npc, turn)
  end
end

local function build_main_posts(pid)
  local st = battle_by_pid[pid]
  if not st then
    return "Duel", { { id = "ygo:noop", read = true, title = "No duel state." } }
  end

  -- Who is the viewer?
  local my = seat_idx(st, pid) -- 1 or 2
  local me  = st.players[my]
  local opp = st.players[3 - my]
  local flags = st.turn_flags or {}
  local is_my_turn = (st.turn_player == my)

  -- Per-player (or fallback) hand selection
  local lastIdx = (st._lastHandIdx_by and st._lastHandIdx_by[pid]) or st._lastHandIdx

  local posts = {}

  -- ===== Actions FIRST (pinned to very top) =====
  if is_my_turn then
    -- If no monster yet & you clicked a hand card, expose Summon/Set at the top
    if (not me.field) and can_place(me, flags) and lastIdx and me.hand[lastIdx] then
      posts[#posts+1] = { id = BTL_SUMMON, read = true, title = "Summon (face-up ATK)" }
      posts[#posts+1] = { id = BTL_SET,    read = true, title = "Set (face-down DEF)" }
    end

    -- Once you have a monster (or after placing), put End Turn at the very top
    if has_monster(me) then
      posts[#posts+1] = { id = BTL_END, read = true, title = "End Turn" }
    end

    -- Only show context-legal options (use my seat index)
    if can_switch_now(st, my) then
      posts[#posts+1] = { id = BTL_SWITCH, read = true, title = "Switch Position" }
    end
    if can_attack(st, my) then
      posts[#posts+1] = { id = BTL_ATTACK, read = true, title = "Attack" }
    end
    if any_castable_spell(st, my) then
      posts[#posts+1] = { id = BTL_CAST, read = true, title = "Cast Spell" }
    end
  end

  -- ===== Field header (comes AFTER actions) =====
  local yf = me.field
  local of = opp.field
  posts[#posts+1] = { id = (yf and BTL_VIEW_ME or BTL_OK),  read = true, title = "Your:     " .. name_pos_label(yf, false) }
  posts[#posts+1] = { id = BTL_OK,                          read = true, title =                stats_line(yf, false) }
  posts[#posts+1] = { id = (of and of.pos ~= "SET" and BTL_VIEW_OPP or BTL_OK), read = true, title = "Opponent: " .. name_pos_label(of, true) }
  posts[#posts+1] = { id = BTL_OK,                          read = true, title =              stats_line(of, true) }

  -- Opponent hand count
  posts[#posts+1] = { id = BTL_OK, read = true, title = string.format("Opponent hand: %d", #(opp.hand or {})) }

  -- ===== Hand =====
  posts[#posts+1] = { id = BTL_OK, read = true, title = "Your Hand:" }
  for i, card in ipairs(me.hand) do
    local sel = (lastIdx == i) and " ←" or ""
    posts[#posts+1] = {
      id    = "hand:" .. i,
      read  = true,
      title = string.format("  %d) %s [A %d / D %d]%s", i, short_name(card.title), card.ATK, card.DEF, sel)
    }
  end

  -- ===== Always allow Concede at bottom =====
  posts[#posts+1] = { id = BTL_CONCEDE, read = true, title = "Concede" }

  return battle_title(st), posts
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

function open_battle_board(pid)
  player_using_card_bbs[pid] = false
  in_actions_menu[pid] = false
  local st = battle_by_pid[pid]; if not st then return end
  print("[custom] open_battle_board pid=", pid)
  local my = seat_idx(st, pid)
  print(string.format("[custom] open_battle_board pid=%s ui=%s my=%s", tostring(pid), tostring(st.ui or "main"), tostring(my)))

  battle_refreshing[pid] = true
  battle_ui_open[pid] = true

  local title, posts
  if st.ui == "cast" then
    title, posts = build_cast_posts(pid)
  elseif st.ui == "discard" then
    title, posts = build_discard_posts(pid)
  else
    title, posts = build_main_posts(pid)
  end
  print(string.format("[custom] open_battle_board posts=%d", #(posts or {})))
  Net.open_board(pid, title, BATTLE_BOARD_COLOR, posts)
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

-- === Battle click handler ===
local function handle_battle_post_selection(event)
  local pid     = event.player_id
  local post_id = tostring(event.post_id or "")
  local st      = battle_by_pid[pid]
  if not st then return false end

  -- Seat-aware refs
  local me_i, me, opp = me_opp(st, pid)
  local flags = st.turn_flags or {}

  -- Turn-gated actions
  local function _is_turn_action(id)
    return (id == BTL_SUMMON) or (id == BTL_SET) or (id == BTL_SWITCH)
        or (id == BTL_ATTACK) or (id == BTL_CAST) or (id == BTL_END)
  end
  if _is_turn_action(post_id) and st.turn_player ~= me_i then
    Net.message_player(pid, "[YGO] Not your turn.")
    return true
  end

  -- If finished, any click closes (keep your JobBBS hook)
  if st.finished then
    local who = (st.winner == me_i) and "You win! (3 KOs)"
             or (st.winner and "Opponent wins! (3 KOs)" or "Duel ended.")
    Net.message_player(pid, who)
    _duel_cleanup_overworld(st)
    battle_by_pid[pid] = nil
    pcall(Net.close_bbs, pid)

    -- notify AFTER closing, in the order you want
    if st.on_finish and not st._finish_notified then
      st._finish_notified = true
      local player_won = (st.winner == me_i)
      pcall(st.on_finish, { player_won = player_won, winner = st.winner, npc_name = st.npc_name })
    end

    if JobBBS and JobBBS.on_npc_duel_result then
      pcall(JobBBS.on_npc_duel_result, pid, { winner = st.winner, npc_name = st.npc_name, kos = 3 })
    end

    _record_duel_result_for_all_viewers(st)  -- fine to keep here if you like

    return true
  end

  -- View YOUR monster
  if post_id == BTL_VIEW_ME then
    local f = me.field
    if not f then return true end
    local info = item_info_from_field_card(f.card)
    if info then show_card_dialog_with_mug(pid, info) else Net.message_player(pid, "No details available for this card.") end
    return true
  end

  -- View OPP monster (only if face-up)
  if post_id == BTL_VIEW_OPP then
    local f = opp.field
    if not f or f.pos == "SET" then Net.message_player(pid, "You can’t view a face-down monster."); return true end
    local info = item_info_from_field_card(f.card)
    if info then show_card_dialog_with_mug(pid, info) else Net.message_player(pid, "No details available for this card.") end
    return true
  end

  -- Switch Position
  if post_id == BTL_SWITCH then
  if st.turn_player ~= me_i then return true end
  if not can_switch_now(st, me_i) then
    Net.message_player(pid, "You can’t switch position right now.")
    return true
  end
  local f = me.field
  if not f then return true end

  if f.pos == "SET" then
    f.pos = "ATK"
  else
    f.pos = (f.pos == "ATK") and "DEF" or "ATK"
  end

  local pname = name_for(st, me_i)
  battle_announce(st, string.format("%s switched %s to %s.", pname, short_name(f.card.title), f.pos))

  if was_set and f.pos ~= "SET" then
    _duel_spawn_faceup_for_seat(st, me_i)
  end
  st.turn_flags.hasSwitched = true
  refresh_both(st, pid)
  return true
  end

  -- Back from submenus
  if post_id == "__b_back__" then
    st.ui = "main"
    safe_request_refresh(pid)
    return true
  end

  -- Concede / Cancel
  if post_id == BTL_CONCEDE or post_id == BTL_CANCEL then
    local my = seat_idx(st, pid) or 1
    st.finished = true
    _duel_cleanup_overworld(st)
    st.winner   = 3 - my

    -- Announce
    local subj = (labels_for and select(1, labels_for(st, my, pid))) or "You"
    if st.pids then
      announce_both(st, "[Concede] " .. ((subj == "You") and ((Net.get_player_name(pid) or "Player") .. " conceded.") or (subj .. " conceded.")))
    else
      battle_announce(st, "You conceded.")
    end

    -- Let ygo_pvp free the table (if this was a PVP duel)
    pcall(function()
      if st.mode == "pvp" and ygo_pvp and ygo_pvp.on_ygo_pvp_end and st.pids then
        local winner_pid = st.pids[st.winner]
        local loser_pid  = st.pids[my]
        if winner_pid and loser_pid then
          ygo_pvp.on_ygo_pvp_end(winner_pid, loser_pid, { table_id = st.table_id })
        end
      end
    end)

    safe_request_refresh(pid)
    return true
  end

  -- Hand cursor (store per-player)
  local hand_idx = post_id:match("^hand:(%d+)")
  if hand_idx then
    st._lastHandIdx_by = st._lastHandIdx_by or {}
    st._lastHandIdx_by[pid] = tonumber(hand_idx)
    safe_request_refresh(pid)
    return true
  end

  -- Summon / Set
  if post_id == BTL_SUMMON or post_id == BTL_SET then
    if st.turn_player ~= me_i then return true end

    if not can_place(me, flags) then
      Net.message_player(pid, "You already Summoned/Set or your field is occupied.")
      return true
    end

    local idx = (st._lastHandIdx_by and st._lastHandIdx_by[pid]) or st._lastHandIdx or 1
    if not me.hand[idx] then
      Net.message_player(pid, "Select a card in hand first.")
      return true
    end

    if post_id == BTL_SUMMON then
      do_summon(me, idx)
    else
      do_set(me, idx)
    end

    if me.field then
      me.field._enteredTurn = st.turn_num
      local nm = short_name(me.field.card.title)
      local pname = name_for(st, me_i)
      if post_id == BTL_SUMMON then
        battle_announce(st, string.format("%s Summoned %s [ATK %d]", pname, nm, me.field.card.ATK))
      else
        battle_announce(st, string.format("%s Set a monster.", pname))
      end
    end
    if post_id == BTL_SUMMON then
      _duel_spawn_faceup_for_seat(st, me_i)
    end
    flags.hasSummoned = true

    -- refresh BOTH players so the other client sees the new board immediately
    refresh_both(st, pid)
    return true

  end

  -- Attack
  if post_id == BTL_ATTACK then
  if st.turn_player ~= me_i then return true end
  if can_attack(st, me_i) then
    resolve_attack(st)          -- your function does announcer lines for damage/flip/etc.
    cleanup_zero_def(st)        -- keep if you use it elsewhere
    refresh_both(st, pid)
  else
    Net.message_player(pid, "You cannot attack now.")
  end
  return true
end

  -- End Turn
if post_id == BTL_END then
  if st.turn_player ~= me_i then return true end
  if not has_monster(me) then
    Net.message_player(pid, "You must Summon/Set a monster before ending your turn.")
    return true
  end

  -- Block while opponent has a modal open (PvP only)
  if st.mode == "pvp" and gate_if_opponent_busy(st, pid) then
    return true
  end

  local ended_name = name_for(st, me_i)
  end_turn(st)  -- IMPORTANT: handles “this turn” rollbacks and begins next turn

  -- Announce turn change
  local next_name = name_for(st, st.turn_player)
  battle_announce(st, ended_name .. " ended their turn.")
  battle_announce(st, "It is now " .. next_name .. "'s turn.")

  -- In PvE, let the NPC immediately take its turn (it will call end_turn again)
  if not st.pids then
    npc_take_turn(st)
  end

  refresh_both(st, pid)
  return true
end

  -- Cast (open submenu)
  if post_id == BTL_CAST then
    if st.turn_player ~= me_i then return true end
    if not has_monster(me) then Net.message_player(pid, "You must control a monster to cast spells."); return true end
    if flags.hasCast then Net.message_player(pid, "You already cast a spell this turn."); return true end
    st.ui = "cast"
    safe_request_refresh(pid)
    return true
  end

  -- Pick a specific spell
  local picked_key = post_id:match("^"..BTL_CAST_PICK.."(.+)")
  if picked_key then
    if not has_monster(me) then
      Net.message_player(pid, "You must control a monster to cast spells.")
      st.ui = "main"; safe_request_refresh(pid); return true
    end
    local sp = SP(picked_key); if not sp then return true end
    local cost = sp.cost or 0
    if #me.hand < cost then Net.message_player(pid, "Not enough cards in hand to pay ("..cost..")."); return true end

    -- If more cards than cost, let the player choose
    if #me.hand > cost and cost > 0 then
      st._pending_spell = sp.key
      st._discard_cost  = cost
      st._discard_sel   = {}
      st.ui = "discard"
      safe_request_refresh(pid)
      return true
    end

    -- Auto-pay (use last N cards)
    if cost > 0 then
      local idxs = {}
      for i=#me.hand, #me.hand - cost + 1, -1 do table.insert(idxs, i) end
      pay_cost_from_hand(st, me_i, cost, idxs)
    end

    local msg = sp.apply(st, me_i)
    cleanup_zero_def(st)
    Net.message_player(pid, msg or (sp.name.." resolved."))
    flags.hasCast = true
    st.ui = "main"
    refresh_both(st, pid)
    return true
  end

  -- Discard picker: toggle
  local dsel = post_id:match("^"..BTL_DSEL_PREFIX.."(%d+)$")
  if dsel then
    local i = tonumber(dsel)
    if me.hand[i] then
      st._discard_sel[i] = not st._discard_sel[i]
    end
    safe_request_refresh(pid)
    return true
  end

  -- Discard picker: Confirm
  if post_id == BTL_DCONF then
    local need = st._discard_cost or 0
    local picks = {}
    for i,_ in pairs(st._discard_sel or {}) do if st._discard_sel[i] then table.insert(picks, i) end end
    table.sort(picks, function(a,b) return a>b end)
    if #picks ~= need then
      Net.message_player(pid, "Select exactly "..need.." card(s).")
      safe_request_refresh(pid); return true
    end

    for _, idx in ipairs(picks) do table.remove(me.hand, idx) end

    local sp = SP(st._pending_spell)
    st._pending_spell, st._discard_cost, st._discard_sel = nil, nil, nil
    if not sp then
      st.ui = "main"; safe_request_refresh(pid); return true
    end

    local msg = sp.apply(st, me_i)
    cleanup_zero_def(st)
    Net.message_player(pid, msg or (sp.name.." resolved."))
    flags.hasCast = true

    st.ui = "main"
    refresh_both(st, pid)
    return true
  end

  -- Discard picker: Cancel
  if post_id == BTL_DCANCEL then
    st._pending_spell, st._discard_cost, st._discard_sel = nil, nil, nil
    st.ui = "cast"
    safe_request_refresh(pid)
    return true
  end

  return true
end

-- ==========
-- Deck Editor (BBS)
-- ==========

local deck_editor = deck_editor or {}
local saved_deck_by_pid = saved_deck_by_pid or {}
-- Deck Editor state
local deck_editor     = deck_editor     or {} -- [pid] = { counts = {...}, active=true }
local deck_reopen     = deck_reopen     or {} -- [pid] = true → reopen Deck Editor after close
local deck_refreshing = deck_refreshing or {} -- [pid] = true while we are reopening programmatically

local DECK_EDIT_OPEN   = "__deck_edit__"
local DECK_ADD_PREFIX  = "deck:add:"
local DECK_REM_PREFIX  = "deck:rem:"
local DECK_SAVE        = "__deck_save__"
local DECK_CLEAR       = "__deck_clear__"
local DECK_BACK        = "__deck_back__"

local function _pool_map(rows)
  local m = {}
  for _,r in ipairs(rows or {}) do m[r.id] = r end
  return m
end

local function deck_refresh(pid)
  deck_reopen[pid] = true
  pcall(Net.close_bbs, pid)
end

local function _deck_total_and_have_urgdr(counts, poolmap)
  local total, have = 0, false
  for id, n in pairs(counts or {}) do
    if n and n > 0 then
      total = total + n
      local row = poolmap[id]
      local rar = tostring((row and (row.rar or parse_rarity_tag(row.title))) or "C"):upper()
      if rar == "UR" or rar == "GDR" or rar == "GR" then have = true end
    end
  end
  return total, have
end

-- How many more copies of this row can we add, respecting new rarity-wide caps
local function _max_add_for_row(counts, row, poolmap)
  local owned   = row.qty or 0
  local in_deck = (counts[row.id] or 0)
  local rar     = tostring(row.rar or parse_rarity_tag(row.title) or "C"):upper()
  local total, urgdr_total, sr_total, r_total = _rarity_totals(counts, poolmap)

  local remaining_owned = math.max(0, owned - in_deck)
  if remaining_owned <= 0 then return 0 end

  if rar == "UR" or rar == "GDR" or rar == "GR" then
    -- UR/GDR combined: max 1 total across deck; also cannot exceed 1 per title implicitly
    if in_deck >= 1 then return 0 end
    return (urgdr_total >= 1) and 0 or 1

  elseif rar == "SR" then
    -- SR: max 2 total across all SR
    local room = math.max(0, 2 - sr_total)
    return math.min(remaining_owned, room)

  elseif rar == "R" then
    -- R: max 3 total across all R
    local room = math.max(0, 3 - r_total)
    return math.min(remaining_owned, room)

  else
    -- Commons: limited only by ownership
    return remaining_owned
  end
end

-- Prefer persisted counts; fall back to RAM deck counts
local function _counts_from_saved(pid)
  local c = load_persisted_deck_counts and load_persisted_deck_counts(pid)
  if c and next(c) then
    local out = {}; for id,n in pairs(c) do out[id]=n end
    return out
  end
  local counts = {}
  local saved = saved_deck_by_pid and saved_deck_by_pid[pid]
  if saved and #saved > 0 then
    for _,card in ipairs(saved) do
      counts[card.id] = (counts[card.id] or 0) + 1
    end
  end
  return counts
end

function open_deck_editor(pid)
  local pool     = snapshot_player_collection(pid)
  local poolmap  = _pool_map(pool)

  -- init state first
  deck_editor[pid] = deck_editor[pid] or {}
  player_using_card_bbs[pid] = false
  deck_editor[pid].active = true

  -- IMPORTANT: only seed from saved if counts is nil (don’t overwrite {} from Clear)
  if deck_editor[pid].counts == nil then
    deck_editor[pid].counts = _counts_from_saved(pid) or {}
  end
  local counts = deck_editor[pid].counts

  -- header & rule lines (ASCII-safe + short)
  local total, urgdr_total, sr_total, r_total = _rarity_totals(counts, poolmap)
  local title = string.format("Deck Editor (%d/10)", total)
  local posts = {}
  posts[#posts+1] = { id=BTL_OK, read=true, title="Rules:" }
  posts[#posts+1] = { id=BTL_OK, read=true, title="UR/GR/GDR = 1" }
  posts[#posts+1] = { id=BTL_OK, read=true, title="SR <= 2" }
  posts[#posts+1] = { id=BTL_OK, read=true, title="R  <= 3" }
  posts[#posts+1] = { id=BTL_OK, read=true, title="Deck size = 10" }

  -- controls
  if total == 10 then
    posts[#posts+1] = { id=DECK_SAVE,  read=true, title="Save Deck (use in duels)" }
  else
    posts[#posts+1] = { id=BTL_OK,     read=true, title=string.format("Save Deck (need %d more)", 10-total) }
  end
  posts[#posts+1] = { id=DECK_CLEAR,   read=true, title="Clear Deck" }
  posts[#posts+1] = { id=DECK_BACK,    read=true, title="Back to Card List" }

  -- current deck
  posts[#posts+1] = { id=BTL_OK, read=true, title="Current Deck:" }
  local had_any = false
  local deck_lines = {}
  for id, n in pairs(counts) do
    if n and n > 0 then
      local row = poolmap[id]
      if row then deck_lines[#deck_lines+1] = { id=id, n=n, row=row } end
    end
  end
  table.sort(deck_lines, function(a,b)
    local ra, na = sort_key_from_title(a.row.title)
    local rb, nb = sort_key_from_title(b.row.title)
    if ra ~= rb then return ra < rb end
    if na ~= nb then return na < nb end
    return tostring(a.row.title) < tostring(b.row.title)
  end)
  for _,e in ipairs(deck_lines) do
    had_any = true
    posts[#posts+1] = {
      id = DECK_REM_PREFIX..e.id, read = true,
      title = string.format("  [-] %s  x%d", e.row.title, e.n)
    }
  end
  if not had_any then
    posts[#posts+1] = { id=BTL_OK, read=true, title="  (empty)" }
  end

  -- add-from-collection (hide non-addable to reduce clutter)
  posts[#posts+1] = { id=BTL_OK, read=true, title="Add from Collection:" }
  table.sort(pool, function(a,b)
    local ra, na = sort_key_from_title(a.title)
    local rb, nb = sort_key_from_title(b.title)
    if ra ~= rb then return ra < rb end
    if na ~= nb then return na < nb end
    return tostring(a.title) < tostring(b.title)
  end)
  for _, row in ipairs(pool) do
    local max_add = _max_add_for_row(counts, row, poolmap)
    if max_add > 0 and total < 10 then
      local own  = row.qty or 0
      local in_d = counts[row.id] or 0
      posts[#posts+1] = {
        id    = DECK_ADD_PREFIX..row.id, read=true,
        title = string.format("  [+] %s (owned %d, in deck %d)", row.title, own, in_d)
      }
    end
  end

  Net.open_board(pid, title, LIST_BOARD_COLOR, posts)
end

-- Handle clicks inside deck editor
function handle_deck_post_selection(event)
  local pid  = event.player_id
  local post = tostring(event.post_id or "")
  if post == "" then return false end

  -- Deck editor posts we care about
  if post ~= "__deck_edit__" and           -- opener is handled elsewhere
     post ~= "__deck_clear__" and
     post ~= "__deck_save__"  and
     post ~= "__deck_back__"  and
     not post:match("^deck:add:") and
     not post:match("^deck:rem:") then
    return false
  end

  -- Open / Back are handled in your router; we ignore here
  if post == "__deck_back__" then return false end
  if post == "__deck_edit__" then return false end

  -- Ensure editor state exists
  deck_editor[pid] = deck_editor[pid] or { counts = {} }
  local counts = deck_editor[pid].counts or {}

  -- Snapshot & helpers
  local pool    = snapshot_player_collection(pid)
  local poolmap = _pool_map(pool)

  -- CLEAR
  if post == "__deck_clear__" then
    deck_editor[pid] = deck_editor[pid] or {}
    deck_editor[pid].counts = {}      -- keep it as {}, not nil
    open_deck_editor(pid)             -- rebuild UI using the now-empty counts
    return true
  end

  -- SAVE (validates your rarity totals)
  if post == "__deck_save__" then
    local total, urgdr_total, sr_total, r_total = _rarity_totals(counts, poolmap)
    if total ~= 10 then Net.message_player(pid, "Deck must have exactly 10 cards."); return true end
    if urgdr_total > 1 then Net.message_player(pid, "UR/GDR total cannot exceed 1."); return true end
    if sr_total  > 2 then Net.message_player(pid, "SR total cannot exceed 2.");     return true end
    if r_total   > 3 then Net.message_player(pid, "R total cannot exceed 3.");      return true end

    if persist_deck_counts then persist_deck_counts(pid, counts) end
    Net.message_player(pid, "Saved deck of 10 cards. This deck will be used in duels.")
    deck_reopen[pid] = true
    pcall(Net.close_bbs, pid)
    return true
  end

  -- ADD
  local add_id = post:match("^deck:add:(.+)")
  if add_id then
    local row = poolmap[add_id]
    if not row then return true end
    local total = 0; for _,n in pairs(counts) do total = total + (n or 0) end
    if total >= 10 then Net.message_player(pid, "Deck is full."); return true end
    local max_add = _max_add_for_row(counts, row, poolmap)
    if max_add <= 0 then Net.message_player(pid, "Cannot add more of this card."); return true end
    counts[add_id] = (counts[add_id] or 0) + 1
    deck_reopen[pid] = true
    pcall(Net.close_bbs, pid)
    return true
  end

  -- REMOVE
  local rem_id = post:match("^deck:rem:(.+)")
  if rem_id then
    if (counts[rem_id] or 0) > 0 then counts[rem_id] = counts[rem_id] - 1 end
    if (counts[rem_id] or 0) <= 0 then counts[rem_id] = nil end
    deck_reopen[pid] = true
    pcall(Net.close_bbs, pid)
    return true
  end

  return false
end

-- PVP entrypoint: start a duel between two players
function custom.start_card_battle_pvp(pidA, pidB, cfg)
  print(string.format("[custom] start_card_battle_pvp: pidA=%s pidB=%s table_id=%s",
    tostring(pidA), tostring(pidB), tostring(cfg and cfg.table_id)))

  -- 1) Build decks
  local countsA = load_persisted_deck_counts and load_persisted_deck_counts(pidA) or {}
  local countsB = load_persisted_deck_counts and load_persisted_deck_counts(pidB) or {}
  print(string.format("[custom] deck counts: A=%d, B=%d",
    (countsA and (#(countsA.cards or {}) > 0 and #countsA.cards) or (next(countsA) and 10 or 0)),
    (countsB and (#(countsB.cards or {}) > 0 and #countsB.cards) or (next(countsB) and 10 or 0))))

  local deckA = materialize_deck_from_counts and materialize_deck_from_counts(pidA, countsA) or {}
  local deckB = materialize_deck_from_counts and materialize_deck_from_counts(pidB, countsB) or {}
  print(string.format("[custom] materialized decks: A=%d cards, B=%d cards", #deckA, #deckB))

  if #deckA == 0 or #deckB == 0 then
    Net.message_player(pidA, "[YGO] One of the players has no saved deck.")
    Net.message_player(pidB, "[YGO] One of the players has no saved deck.")
    print("[custom] abort: empty deck")
    return false
  end

  -- 2) Build shared battle state
  local st = {
    mode          = "pvp",
    pids          = { pidA, pidB },
    seat_of       = { [pidA]=1, [pidB]=2 },
    players       = {
      { name = Net.get_player_name(pidA) or "P1", deck = {}, hand = {}, grave = {}, KOs = 0 },
      { name = Net.get_player_name(pidB) or "P2", deck = {}, hand = {}, grave = {}, KOs = 0 },
    },
    turn_player   = 1,
    turn_num      = 1,
    noDrawThisTurn= { [1]=true, [2]=true },
    table_id      = cfg and cfg.table_id or nil,
    ui            = "main",
  }

  -- copy decks (reverse insert keeps top-of-deck order if your materializer returns top-first)
  for i=#deckA,1,-1 do table.insert(st.players[1].deck, deckA[i]) end
  for i=#deckB,1,-1 do table.insert(st.players[2].deck, deckB[i]) end
  print(string.format("[custom] state decks ready: P1=%d P2=%d", #st.players[1].deck, #st.players[2].deck))

  -- 3) Engine helpers present?
  if not shuffle or not draw_one or not begin_turn then
    print("[custom] abort: missing helpers (shuffle/draw_one/begin_turn)")
    return false
  end

  -- 4) Shuffle + draw opening hands
  shuffle(st.players[1].deck); shuffle(st.players[2].deck)
  for i=1,2 do
  draw_one(st.players[1])
  draw_one(st.players[2])
  end

  -- 5) Map both pids → shared state
  battle_by_pid[pidA] = st
  battle_by_pid[pidB] = st
  print("[custom] mapped pids to battle state")

  -- 6) Begin turn (sets flags, etc.)
  begin_turn(st)
  print("[custom] begin_turn ok; deferring UI open via board_close")

  -- 7) DO NOT open boards here; let board_close open them after the duel-table closes
  battle_reopen[pidA] = true
  battle_reopen[pidB] = true
  print("[custom] set battle_reopen for both players")

  print("[custom] PVP start complete (returning true)")
  return true
end

-- ==== Unified helpers (put before the listeners) ====
-- Small helpers to know which board is currently “active”
local function _battle_active(pid)
  return (battle_by_pid and battle_by_pid[pid] ~= nil) and (battle_ui_open and battle_ui_open[pid] == true)
end
local function _trade_active(pid)
  return trader_by_pid and trader_by_pid[pid] ~= nil
end

-- ==== Unified click router: Battle → Trader → Actions → Card List ====
Net:on("post_selection", function(event)
  local pid     = event.player_id
  local post_id = tostring(event.post_id or "")
  local battle_up = (_battle_active and _battle_active(pid)) or
                  (custom and custom.is_battle_open_for and custom.is_battle_open_for(pid)) or false
  print("[cards] post_selection pid", pid, "post_id", post_id,
        "in_actions=", in_actions_menu[pid], "in_main=", player_using_card_bbs[pid])

  -- Debug trace
  print(string.format("[custom] post_selection pid=%s post_id=%s", tostring(event.player_id), tostring(event.post_id)))
  if JobBBS and JobBBS.handle_post_selection and JobBBS.handle_post_selection(event) then
    return
  end

-- 1) JobBBS clicks
  if JobBBS and event.post_id and tostring(event.post_id):match("^__job:") then
    -- Let JobBBS handle it; if it returns true, stop other menus from processing
    local handled = JobBBS.handle_post_selection(event)
    if handled then return end
  end

  -- 2) Trader clicks
  if _trade_active(pid) and handle_trade_post_selection and handle_trade_post_selection(event) then
    return
  end

  -- 3) Deck Editor internal clicks
  if handle_deck_post_selection and handle_deck_post_selection(event) then
    return
  end

  -- 4) Open Deck Editor from Card Collection top row
  if post_id == "__deck_edit__" then
    -- mark active and schedule a reopen after the current board closes
    deck_editor[pid] = deck_editor[pid] or { counts = _counts_from_saved(pid) }
    deck_editor[pid].active = true
    deck_reopen[pid] = true
    pcall(Net.close_bbs, pid)  -- this will trigger board_close → we reopen there
    return true
  end

  -- 5) Your existing Actions menu (Summon/Dismiss/Open List/Close)
  if in_actions_menu[pid] then
    in_actions_menu[pid] = false
    local action = post_id
    print("[cards] actions menu selection:", action)

    if action == ACTION_SUMMON then
      local info = last_viewed_card_by_player[pid]
      if not info then Net.message_player(pid, "(View a card first.)"); return end
      if summoned_bot_by_player[pid] then
        pcall(Net.remove_bot, summoned_bot_by_player[pid])
      end
      local bot_id = spawn_card_npc_for_all(pid, info)
      if bot_id then
        summoned_bot_by_player[pid] = bot_id
        pending_actions_menu[pid] = true
      end
      return

    elseif action == ACTION_DISMISS then
      if summoned_bot_by_player[pid] then
        pcall(Net.remove_bot, summoned_bot_by_player[pid])
        summoned_bot_by_player[pid] = nil
      end
      pending_actions_menu[pid] = true
      return

    elseif action == ACTION_OPEN_LIST then
      -- Auto-close Card Options, then open Card Collection as soon as it closes.
      open_list_after_close[pid] = true
      pcall(Net.close_bbs, pid)
      return

    elseif action == ACTION_CLOSE then
      pcall(Net.close_bbs, pid)
      player_using_card_bbs[pid] = false
      return
    end
  end

  -- 6) Plain Card List selection → open the card’s detail/mugshot viewer
  if player_using_card_bbs[pid] == true and not battle_up then
    local item = ezmemory.get_item_info(event.post_id)
    print("[cards] main list selection ->", item and item.name or "(unknown)")
    show_card_dialog_with_mug(pid, item)
    return
  end

  -- 7) YGO PVP clicks
  if ygo_pvp and ygo_pvp.handle_post_selection and ygo_pvp.handle_post_selection(event) then
    print("[custom] post_selection handled by ygo_pvp")
    return
  end

  -- 8) Battle clicks
  if _battle_active(pid) and handle_battle_post_selection and handle_battle_post_selection(event) then
    return
  end

  print("[cards] post_selection fell through; no known context")
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
  print(string.format("[custom] board_close pid=%s", tostring(pid)))

  if JobBBS and JobBBS.is_waiting and JobBBS.is_waiting(pid) then
    return
  end

  if player_using_card_bbs[pid] then
    player_using_card_bbs[pid] = false
    in_actions_menu[pid] = false
  end

  -- If the last closed board was the Card Collection, clear its sticky flags
  if card_list_open[pid] then
    print(string.format("[custom] board_close: card list closed → clearing state for %s", tostring(pid)))
    clear_card_viewer_state(pid)
    -- don't return; let the rest of the handler run
  end

  -- Compute whether THIS close looks like a recent programmatic refresh
  local is_prog   = closing_for_refresh[pid] == true
  local age       = is_prog and ((os.clock() - (closing_for_refresh_ts[pid] or 0))) or 999
  local is_recent = is_prog and (age <= PROGRAM_REFRESH_WINDOW_S)

  -- A) Battle UI deferred open (handle FIRST so refresh can reopen instantly)
  if battle_reopen and battle_reopen[pid] then
    battle_reopen[pid] = nil
    closing_for_refresh[pid] = nil  -- consume any pending refresh marker
    if battle_by_pid and battle_by_pid[pid] then
      print(("[custom] board_close: battle_reopen → open_battle_board pid=%s"):format(pid))
      open_battle_board(pid)
      return
    end
  end

  -- B) Swallow ONLY very recent programmatic refresh closes
  if is_recent then
    closing_for_refresh[pid] = nil
    print("[custom][refresh] swallowed recent programmatic close (", string.format("%.3fs", age), ")")
    return
  end

  -- C) Manual battle-close lock: if in an active duel, reopen immediately
  local st = battle_by_pid and battle_by_pid[pid] or nil
  local lock_on = (type(BATTLE_CLOSE_LOCK) == "boolean") and BATTLE_CLOSE_LOCK or false
  if lock_on and st and not st.finished then
    print("[custom][lock] manual close during active duel → reopening Battle BBS")
    open_battle_board(pid)
    return
  end

  -- D) Duel-table lobby handler (unchanged)
  if ygo_pvp and ygo_pvp.handle_board_close and ygo_pvp.handle_board_close(event) then
    print("[custom] board_close handled by ygo_pvp")
    return
  end

  -- E) (optional legacy) ignore old battle_refreshing flag if you still use it
  if battle_refreshing and battle_refreshing[pid] then
    battle_refreshing[pid] = nil
    print("[custom] board_close: battle_refreshing cleared")
    return
  end

  -- Deck Editor: scheduled refresh
  if deck_reopen and deck_reopen[pid] then
    deck_reopen[pid] = nil
    if deck_editor and deck_editor[pid] and deck_editor[pid].active then
      deck_refreshing[pid] = true
      open_deck_editor(pid)
    end
    return
  end

  -- Deck Editor: programmatic reopen swallow
  if deck_refreshing and deck_refreshing[pid] then
    deck_refreshing[pid] = nil
    return
  end

  -- Trader reopen (programmatic)
  if trade_reopen and trade_reopen[pid] then
    trade_reopen[pid] = nil
    if trader_by_pid and trader_by_pid[pid] then
      open_trade_board(pid)
    end
    return
  end

  -- Trader: programmatic reopen swallow
  if trade_refreshing and trade_refreshing[pid] then
    trade_refreshing[pid] = nil
    return
  end

  -- Actions menu asked to open Card List
  if open_list_after_close and open_list_after_close[pid] then
    open_list_after_close[pid] = false
    open_card_list(pid)
    return
  end

  if jobbbs and jobbbs.on_board_close and jobbbs.on_board_close(event) then
    return
  end


  -- Ignore manual close if battle still active (legacy guard)
  st = battle_by_pid and battle_by_pid[pid]
  if st and not st.finished then
    print("[cards] board_close during active battle; ignoring")
    return
  end

  battle_ui_open[pid] = false
  if st and st.finished then battle_by_pid[pid] = nil end
  print("[cards] board_close pid", pid)
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

function custom.begin_card_battle_await(pid, cfg)
  return async(function()
    -- clear any stale result for this player
    if _last_duel_result then _last_duel_result[pid] = nil end

    local co      = coroutine.running()
    local resumed = false
    local result  = nil

    local function resume_now()
      if not resumed then
        resumed = true
        local A = rawget(_G, "Async")
        if A and A.defer then
          A.defer(function() coroutine.resume(co) end)
        else
          coroutine.resume(co)
        end
      end
    end

    -- piggyback JobBBS (fallback path) so we always resume on duel end
    local prev_cb = JobBBS and JobBBS.on_npc_duel_result
    if JobBBS then
      JobBBS.on_npc_duel_result = function(p, t)
        -- chain the original callback first
        if prev_cb then pcall(prev_cb, p, t) end
        -- our waiter only cares about this player
        if p == pid then
          result = result or {
            player_won = (t and t.winner == 1) or false,
            winner     = t and t.winner,
            npc_name   = t and t.npc_name,
          }
          resume_now()
          -- restore once we’ve resumed
          JobBBS.on_npc_duel_result = prev_cb
        end
      end
    end

    -- inject an on_finish that resumes this coroutine immediately on KO/concede
    local cfg2 = {}
    for k, v in pairs(cfg or {}) do cfg2[k] = v end
    cfg2.on_finish = function(res)
      result = res or (custom.get_last_duel_result and custom.get_last_duel_result(pid))
      resume_now()
      if JobBBS then JobBBS.on_npc_duel_result = prev_cb end
    end

    -- start the duel (don’t immediately bail if the state isn’t visible yet)
    custom.start_card_battle(pid, cfg2)

    -- park here until on_finish / JobBBS resumes us
    coroutine.yield()

    -- hand the resolved result back to the NPC event
    return result or (_last_duel_result and _last_duel_result[pid]) or nil
  end)
end

pcall(function()
  if LMenu and LMenu.set_cards_callback and open_card_list then
    LMenu.set_cards_callback(function(pid)
      open_card_list(pid)
    end)
  end
end)

print("[cards] custom plugin ready"); return custom
