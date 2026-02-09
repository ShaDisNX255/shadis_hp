-- /server/scripts/ezlibs-custom/card_sleeves.lua
-- Own-many / equip-one card sleeves + shop preview sprite

local M = {}

local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local helpers  = require('scripts/ezlibs-scripts/helpers')

local OWNED_KEY    = "ygo_sleeves_owned_v1"
local EQUIPPED_KEY = "ygo_sleeve_equipped_v1"

local PREVIEW_SPRITE_ID = "ygo_sleeve_shop_preview"
local PREVIEW_OBJ_ID    = "ygo_sleeve_shop_preview_obj"

local BASE = "/server/assets/cards_ow/FaceDown/"

local SLEEVES = {
  { id = "black-bronze", name = "Black Bronze", tex = BASE .. "black-bronze.png" },
  { id = "black-gray",   name = "Black Gray",   tex = BASE .. "black-gray.png"   },
  { id = "black-yellow", name = "Black Yellow", tex = BASE .. "black-yellow.png" },
  { id = "normal",       name = "Normal",       tex = BASE .. "normal.png"       },
  { id = "pattern1",     name = "Pattern 1",    tex = BASE .. "pattern1.png"     },
  { id = "poketcg",      name = "Poke TCG",     tex = BASE .. "poketcg.png"      },
  { id = "puzzle",       name = "Puzzle",       tex = BASE .. "puzzle.png"       },
}

local BY_ID = {}
for _, s in ipairs(SLEEVES) do BY_ID[s.id] = s end

local preview_tex_by_pid = {}

local preview_sprite_by_pid = {}

local function _sanitize_id(s)
  s = tostring(s or "")
  return (s:gsub("[^%w]", "_"))
end

local function get_secret(pid)
  if helpers and helpers.get_safe_player_secret then
    return helpers.get_safe_player_secret(pid)
  end
  return pid
end

local function pmem_get(pid)
  local secret = get_secret(pid)
  local pmem = ezmemory.get_player_memory(secret) or {}
  if type(pmem[OWNED_KEY]) ~= "table" then
    pmem[OWNED_KEY] = {}
    if ezmemory.set_player_memory then
      ezmemory.set_player_memory(secret, pmem)
    elseif ezmemory.save_player_memory then
      ezmemory.save_player_memory(secret, pmem)
    end
  end
  -- Always own "normal" and default equip it once
  local changed = false
  if pmem[OWNED_KEY]["normal"] ~= true then
    pmem[OWNED_KEY]["normal"] = true
    changed = true
  end
  if pmem[EQUIPPED_KEY] == nil or pmem[EQUIPPED_KEY] == "" then
    pmem[EQUIPPED_KEY] = "normal"
    changed = true
  end

  if changed then
    if ezmemory.set_player_memory then
      ezmemory.set_player_memory(secret, pmem)
    elseif ezmemory.save_player_memory then
      ezmemory.save_player_memory(secret, pmem)
    end
  end
  return pmem, secret
end

function M.list_defs()
  return SLEEVES
end

function M.get_def(id)
  return BY_ID[tostring(id or "")]
end

function M.get_name_for_id(id)
  local d = M.get_def(id)
  return d and d.name or tostring(id or "")
end

function M.get_tex_for_id(id)
  local d = M.get_def(id)
  return d and d.tex or nil
end

function M.has_sleeve(pid, id)
  id = tostring(id or "")
  if id == "normal" then return true end
  if id == "" then return false end
  local pmem = pmem_get(pid)
  local bag = pmem and pmem[OWNED_KEY] or nil
  return bag and bag[id] == true
end

function M.unlock_for_player(pid, id)
  id = tostring(id or "")
  if id == "" then return false, "invalid_id" end
  if not BY_ID[id] then return false, "unknown_id" end

  local pmem, secret = pmem_get(pid)
  if not pmem then return false, "no_memory" end

  pmem[OWNED_KEY][id] = true

  if ezmemory.set_player_memory then
    ezmemory.set_player_memory(secret, pmem)
  elseif ezmemory.save_player_memory then
    ezmemory.save_player_memory(secret, pmem)
  end

  return true
end

function M.get_equipped(pid)
  local pmem = pmem_get(pid)
  local id = tostring((pmem and pmem[EQUIPPED_KEY]) or "normal")
  if BY_ID[id] then return id end
  return "normal"
end

function M.set_equipped(pid, id)
  id = tostring(id or "")
  if not BY_ID[id] then return false, "unknown_id" end
  -- allow equipping only if owned OR it's normal (free/default)
  if id ~= "normal" and not M.has_sleeve(pid, id) then
    return false, "not_owned"
  end

  local pmem, secret = pmem_get(pid)
  if not pmem then return false, "no_memory" end
  pmem[EQUIPPED_KEY] = id

  if ezmemory.set_player_memory then
    ezmemory.set_player_memory(secret, pmem)
  elseif ezmemory.save_player_memory then
    ezmemory.save_player_memory(secret, pmem)
  end

  return true
end

local function provide(pid, path)
  if Net.provide_asset_for_player and path and path ~= "" then
    pcall(Net.provide_asset_for_player, pid, path)
  end
end

local function dealloc_preview(pid)
  if Net.player_erase_sprite then
    pcall(Net.player_erase_sprite, pid, PREVIEW_OBJ_ID)
  end

  local sid = preview_sprite_by_pid[pid] or PREVIEW_SPRITE_ID
  if Net.player_dealloc_sprite then
    pcall(Net.player_dealloc_sprite, pid, sid)
  end

  preview_tex_by_pid[pid] = nil
  preview_sprite_by_pid[pid] = nil
end

function M.preview_for_shop(pid, sleeve_id, opts)
  opts = opts or {}
  if not (Net.player_alloc_sprite and Net.player_draw_sprite) then return end

  local tex = M.get_tex_for_id(sleeve_id)
  if not tex then return end

  local sprite_id = PREVIEW_SPRITE_ID .. "_" .. _sanitize_id(sleeve_id)

  -- Pull the same anim/state duels uses (fallbacks included)
  local card_anim  = "/server/assets/duels/card.animation"
  local card_state = "idle"
  local mult = 1

  do
    local ok_defs, defs = pcall(require, "scripts/ezlibs-custom/duels_defs")
    if not ok_defs then
      ok_defs, defs = pcall(require, "scripts/duel-helpers/duels_defs")
    end
    if ok_defs and type(defs) == "table" then
      if defs.CARD_ANIM then card_anim = defs.CARD_ANIM end
      if defs.CARD_STATE then card_state = defs.CARD_STATE end
      if defs.KNOBS and defs.KNOBS.UI_POS_MULT then mult = defs.KNOBS.UI_POS_MULT end
    else
      local ok_duels, duels = pcall(require, "scripts/ezlibs-custom/duels")
      if ok_duels and type(duels) == "table" then
        if duels.CARD_ANIM then card_anim = duels.CARD_ANIM end
        if duels.CARD_STATE then card_state = duels.CARD_STATE end
        if duels.KNOBS and duels.KNOBS.UI_POS_MULT then mult = duels.KNOBS.UI_POS_MULT end
      end
    end
  end

  -- Realloc if we’re switching sleeves (sprite_id changes) OR texture changed.
  if preview_sprite_by_pid[pid] ~= sprite_id or preview_tex_by_pid[pid] ~= tex then
    -- Erase old preview object + dealloc old sprite (best-effort)
    dealloc_preview(pid)

    provide(pid, tex)
    provide(pid, card_anim)

    pcall(Net.player_alloc_sprite, pid, sprite_id, {
      texture_path = tex,
      anim_path    = card_anim,
      anim_state   = card_state,
    })

    preview_sprite_by_pid[pid] = sprite_id
    preview_tex_by_pid[pid] = tex
  end

  -- Slightly above center (20px up in base coordinate space)
  local base_x = opts.x or 120
  local base_y = opts.y or 60
  local sx = opts.sx or 3.0
  local sy = opts.sy or sx
  local z  = opts.z  or 999

  local obj = {
    id = PREVIEW_OBJ_ID,
    x  = math.floor(base_x * mult + 0.5),
    y  = math.floor(base_y * mult + 0.5),
    sx = sx,
    sy = sy,
    z  = z,
    anim_state = card_state,
  }

  pcall(Net.player_draw_sprite, pid, sprite_id, obj)
end

function M.clear_shop_previews(pid)
  dealloc_preview(pid)
end

-- Safety: clear if the player disconnects/transfers during a dialogue
if Net and Net.on then
  Net:on("player_disconnect", function(e)
    if e and e.player_id then
      M.clear_shop_previews(e.player_id)
    end
  end)
  Net:on("area_transfer", function(e)
    if e and e.player_id then
      M.clear_shop_previews(e.player_id)
    end
  end)
end

return M
