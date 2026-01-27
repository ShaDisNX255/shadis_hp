-- Auto-generated helper module: sprite helpers moved out of duels.lua
-- Put this file at: scripts/duel-helpers/duels_sprite.lua

return function(duels)
  local M = {}

  local function round_to_int(x)
    return math.floor((x or 0) + 0.5)
  end

  function M.provide(pid, path)
    if Net.provide_asset_for_player and path and path ~= "" then
      pcall(Net.provide_asset_for_player, pid, path)
    end
  end

  function M.alloc_sprite(pid, sprite_id, texture_path, anim_path, anim_state)
    M.provide(pid, texture_path)
    M.provide(pid, anim_path)
    if not Net.player_alloc_sprite then return end
    local opts = { texture_path = texture_path }
    if anim_path and anim_path ~= "" then
      opts.anim_path = anim_path
      opts.anim_state = anim_state or ""
    end
    pcall(Net.player_alloc_sprite, pid, sprite_id, opts)
  end

  function M.dealloc_sprite(pid, sprite_id)
    if Net.player_dealloc_sprite then
      pcall(Net.player_dealloc_sprite, pid, sprite_id)
    end
  end

  function M.sanitize_sprite_id(s)
    s = tostring(s or "")
    return (s:gsub("[^%w]", "_"))
  end

  function M.hash_string(s)
    s = tostring(s or "")
    local h = 0
    for i = 1, #s do
      h = (h * 131 + s:byte(i)) % 2147483647
    end
    return h
  end

  function M.ensure_card_sprite(pid, st, card)
    if not (st and card and card.tex) then return nil end
    st.card_sprites_by_tex = st.card_sprites_by_tex or {}
    st.allocated_card_sprites = st.allocated_card_sprites or {}
    local sid = st.card_sprites_by_tex[card.tex]
    if sid then return sid end
    local base = (card.rarity or "C") .. "_" .. (card.base_name or "card")
    local h = M.hash_string(card.tex)
    sid = "duel_card_" .. M.sanitize_sprite_id(base) .. "_" .. tostring(h)
    M.alloc_sprite(pid, sid, card.tex, duels.CARD_ANIM, duels.CARD_STATE)
    st.card_sprites_by_tex[card.tex] = sid
    st.allocated_card_sprites[#st.allocated_card_sprites + 1] = sid
    return sid
  end

  function M.draw_sprite_obj(pid, sprite_id, obj_id, x, y, sx, sy, z, anim_state, ro)
    if not Net.player_draw_sprite then return end
    local mult = 1
    if duels and duels.KNOBS and duels.KNOBS.UI_POS_MULT then mult = duels.KNOBS.UI_POS_MULT end
    local obj = {
      id = obj_id,
      x = round_to_int((x or 0) * mult),
      y = round_to_int((y or 0) * mult),
      sx = sx,
      sy = sy,
      z = z,
      anim_state = anim_state,
    }
    if ro ~= nil then obj.ro = ro end
    pcall(Net.player_draw_sprite, pid, sprite_id, obj)
  end

  function M.erase_obj(pid, obj_id)
    if Net.player_erase_sprite then
      pcall(Net.player_erase_sprite, pid, obj_id)
    end
  end

  function M.erase_and_dealloc(pid, sprite_id, obj_id)
    M.erase_obj(pid, obj_id)
    M.dealloc_sprite(pid, sprite_id)
  end

  return M
end