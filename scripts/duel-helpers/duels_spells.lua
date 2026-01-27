-- /server/scripts/duel-helpers/duels_spells.lua
-- Spells + spell counters + spell logic for duels.lua
--
-- Design goals:
--  - Keep spell rules/validation in this module (duels.lua stays mostly UI/animation)
--  - Only require duels.lua to pass a small 'api' table for visuals (destroy/reveal/toggle)
--  - Enforce: 1 spell per turn + spend counters only on successful activation

local M = {}

local function _side_key(side)
  return (side == "opp") and "opp" or "ply"
end

local function _other_side(side)
  return (_side_key(side) == "opp") and "ply" or "opp"
end

local function _clamp_int(v, lo, hi)
  v = tonumber(v) or 0
  lo = tonumber(lo) or 0
  hi = tonumber(hi) or 0
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function _get_mon(st, side)
  if not (st and st.field) then return nil end
  side = _side_key(side)
  if side == "opp" then return st.field.opp_monster end
  return st.field.ply_monster
end

local function _expire_temp_atk(mon, cur_turn_index)
  if not mon then return end
  local exp = tonumber(mon.atk_bonus_expires_turn)
  if exp ~= nil and exp < (tonumber(cur_turn_index) or 0) then
    mon.atk_bonus = nil
    mon.atk_bonus_expires_turn = nil
  end

end

local function _apply_pending_end_turn_switches(st, cur_turn_index)
  -- Used by Earthquake (and any future 'end turn' position switch effects).
  if not st then return end
  cur_turn_index = tonumber(cur_turn_index) or 0

  for _, side in ipairs({ "ply", "opp" }) do
    if st[side .. "_pending_end_turn_switch_to_def"] then
      local set_ti = tonumber(st[side .. "_pending_end_turn_switch_to_def_set_turn"]) or -1
      if set_ti < cur_turn_index then
        local mon = _get_mon(st, side)
        if mon and mon.card then
          mon.facedown = false
          mon.pos = "def"
        end
        st[side .. "_pending_end_turn_switch_to_def"] = nil
        st[side .. "_pending_end_turn_switch_to_def_set_turn"] = nil
      end
    end
  end
end

function M.init_state(st)
  if not st then return end
  st.ply_spell_counters = tonumber(st.ply_spell_counters) or 0
  st.opp_spell_counters = tonumber(st.opp_spell_counters) or 0
  st.ply_spell_used_turn_index = tonumber(st.ply_spell_used_turn_index) or -1
  st.opp_spell_used_turn_index = tonumber(st.opp_spell_used_turn_index) or -1
end

function M.on_begin_turn(st, side)
  -- Apply any pending end-of-turn effects, then expire any temp ATK mods (reinforcements / axe / shrink).
  M.init_state(st)
  if not st then return end
  local ti = tonumber(st.turn_index) or 0
  _apply_pending_end_turn_switches(st, ti)
  if st.field then
    _expire_temp_atk(st.field.ply_monster, ti)
    _expire_temp_atk(st.field.opp_monster, ti)
  end
end

function M.get_counters(st, side)
  if not st then return 0 end
  side = _side_key(side)
  return tonumber(st[side .. "_spell_counters"]) or 0
end

function M.add_counters(st, side, amount, maxn)
  if not st then return 0 end
  side = _side_key(side)
  amount = tonumber(amount) or 0
  maxn = tonumber(maxn) or 99

  local k = side .. "_spell_counters"
  local cur = tonumber(st[k]) or 0
  cur = cur + amount
  if cur < 0 then cur = 0 end
  if cur > maxn then cur = maxn end
  st[k] = cur
  return cur
end

function M.on_monster_destroyed(st, destroyer_side, destroyed_side, maxn)
  -- Per spec:
  --  - +1 when you destroy an opponent's monster
  --  - +2 when the opponent destroys your monster (catch-up for the side that lost the monster)
  if not st then return end
  M.init_state(st)

  maxn = tonumber(maxn) or 6
  if destroyer_side then M.add_counters(st, destroyer_side, 1, maxn) end
  if destroyed_side then M.add_counters(st, destroyed_side, 2, maxn) end
end

function M.can_cast(st, side, cost)
  if not st then return false, "no_state" end
  side = _side_key(side)
  cost = tonumber(cost) or 0

  local turn_index = tonumber(st.turn_index) or 0
  local used_k = side .. "_spell_used_turn_index"
  local used_turn = tonumber(st[used_k]) or -1

  if used_turn == turn_index then
    return false, "already_used_this_turn"
  end

  local cur = tonumber(st[side .. "_spell_counters"]) or 0
  if cur < cost then
    return false, "not_enough_counters"
  end

  return true, "ok"
end

function M.spend_and_mark_used(st, side, cost)
  local ok, reason = M.can_cast(st, side, cost)
  if not ok then return false, reason end

  side = _side_key(side)
  cost = tonumber(cost) or 0
  st[side .. "_spell_counters"] = (tonumber(st[side .. "_spell_counters"]) or 0) - cost
  if st[side .. "_spell_counters"] < 0 then st[side .. "_spell_counters"] = 0 end

  st[side .. "_spell_used_turn_index"] = tonumber(st.turn_index) or 0
  return true, "ok"
end

-- ---------------------------------------------------------------------------
-- Spell definitions (UI + logic)
-- ---------------------------------------------------------------------------
local SPELL_DEFS = {
  { id = "ceasefire",       name = "Ceasefire",        cost = 1, desc = "Reveal opp's face-down monster" },
  { id = "reinforcements",  name = "Reinforcements",   cost = 2, desc = "+500 ATK to your monster this turn" },
  { id = "shield-crush",    name = "Shield Crush",     cost = 2, desc = "-500 DEF to opp's monster permanently" },
  { id = "stop-attack",     name = "Stop Attack",      cost = 2, desc = "Switch opp's monster to DEF" },
  { id = "axe-despair",     name = "Axe of Desplair",  cost = 3, desc = "+1000 ATK to your monster this turn" },
  { id = "curse-anubis",    name = "Curse of Anubis",  cost = 3, desc = "-1000 DEF to opp's monster permanently" },
  { id = "blue-medicine",   name = "Blue Medicine",    cost = 3, desc = "+500 DEF to your monster permanently" },
  { id = "earthquake",      name = "Earthquake",       cost = 3, desc = "Switch to DEF mode at turn end" },
  { id = "shrink",          name = "Shrink",           cost = 3, desc = "-1000 ATK to opp's monster for this turn" },
  { id = "raigeki",         name = "Raigeki",          cost = 4, desc = "Destroy opp monster. Can't be used to 3rd pt" },
}

function M.get_spell_defs()
  return SPELL_DEFS
end

function M.get_spell_count()
  return #SPELL_DEFS
end

function M.get_spell_def(i)
  return SPELL_DEFS[tonumber(i) or 1]
end

function M.get_spell_def_by_id(spell_id)
  spell_id = tostring(spell_id or "")
  for _, d in ipairs(SPELL_DEFS) do
    if d and d.id == spell_id then return d end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Activation + rules
-- ---------------------------------------------------------------------------

local function _apply_temp_atk(mon, amount, turn_index)
  if not mon then return end
  amount = tonumber(amount) or 0
  turn_index = tonumber(turn_index) or 0
  mon.atk_bonus = (tonumber(mon.atk_bonus) or 0) + amount
  mon.atk_bonus_expires_turn = turn_index
end

local function _apply_perm_def(mon, amount)
  if not mon then return end
  amount = tonumber(amount) or 0
  mon.def_current = (tonumber(mon.def_current) or 0) + amount
end

local function _spell_destroy_monster(st, api, destroyer_side, destroyed_side)
  if not (st and api and api.destroy_monster) then return false, "no_api_destroy" end
  destroyer_side = _side_key(destroyer_side)
  destroyed_side = _side_key(destroyed_side)

  -- Must have an actual monster to destroy.
  local target = _get_mon(st, destroyed_side)
  if not (target and target.card) then
    return false, "no_target_monster"
  end

  -- Visual + remove slot
  local ok_destroy = pcall(api.destroy_monster, api.pid, st, destroyed_side)
  if api.draw_monsters then pcall(api.draw_monsters, api.pid, st) end

  -- If destruction failed for any reason, do NOT award points/counters.
  local still = _get_mon(st, destroyed_side)
  if (not ok_destroy) or (still and still.card) then
    return false, "destroy_failed"
  end

  -- Award point
  local max_points = tonumber(api.max_points) or 3
  local pts_k = destroyer_side .. "_points"
  st[pts_k] = _clamp_int((tonumber(st[pts_k]) or 0) + 1, 0, max_points)

  -- Spell counters from destruction
  local maxsc = tonumber(api.max_spell_counters) or 6
  if M.on_monster_destroyed then
    pcall(M.on_monster_destroyed, st, destroyer_side, destroyed_side, maxsc)
  end
  if api.draw_spell_counters then pcall(api.draw_spell_counters, api.pid, st) end
  if api.draw_point_counters then pcall(api.draw_point_counters, api.pid, st) end
  if api.end_duel_by_points then pcall(api.end_duel_by_points, api.pid, st) end

  return true, "ok"
end

-- Returns: ok:boolean, reason:string
-- api table (from duels.lua) may include:
--   pid, start_reveal_def_anim(pid, st, side), toggle_opponent_monster_position(pid, st),
--   destroy_monster(pid, st, side), draw_spell_counters(pid, st), draw_point_counters(pid, st), end_duel_by_points(pid, st),
--   max_spell_counters, max_points
function M.activate(st, side, spell_id, api)
  if not st then return false, "no_state" end
  M.init_state(st)

  side = _side_key(side)
  spell_id = tostring(spell_id or "")
  api = api or {}

  -- Debug breadcrumbs
  st.last_spell_selected = spell_id

  local def = M.get_spell_def_by_id(spell_id)
  if not def then
    st.last_spell_error = "unknown_spell"
    return false, "unknown_spell"
  end

  -- Basic "can cast" checks: 1/turn + enough counters
  local ok_can, reason_can = M.can_cast(st, side, def.cost)
  if not ok_can then
    st.last_spell_error = reason_can
    return false, reason_can
  end

  -- Target validation depends on spell.
  local my_mon = _get_mon(st, side)
  local opp_side = _other_side(side)
  local opp_mon = _get_mon(st, opp_side)

  if spell_id == "ceasefire" then
    if not (opp_mon and opp_mon.card and opp_mon.facedown) then
      st.last_spell_error = "no_facedown_target"
      return false, "no_facedown_target"
    end
  elseif spell_id == "reinforcements" or spell_id == "axe-despair" then
    if not (my_mon and my_mon.card and (not my_mon.facedown)) then
      st.last_spell_error = "no_faceup_own_monster"
      return false, "no_faceup_own_monster"
    end
  elseif spell_id == "shield-crush" or spell_id == "curse-anubis" then
    if not (opp_mon and opp_mon.card and (not opp_mon.facedown)) then
      st.last_spell_error = "no_faceup_opp_monster"
      return false, "no_faceup_opp_monster"
    end
  elseif spell_id == "stop-attack" then
    if not (opp_mon and opp_mon.card and (not opp_mon.facedown) and ((opp_mon.pos or "atk") == "atk")) then
      st.last_spell_error = "no_faceup_atk_target"
      return false, "no_faceup_atk_target"
    end
  elseif spell_id == "blue-medicine" then
    if not (my_mon and my_mon.card and (not my_mon.facedown)) then
      st.last_spell_error = "no_faceup_own_monster"
      return false, "no_faceup_own_monster"
    end
  elseif spell_id == "earthquake" then
    if not (my_mon and my_mon.card and (not my_mon.facedown)) then
      st.last_spell_error = "no_faceup_own_monster"
      return false, "no_faceup_own_monster"
    end
  elseif spell_id == "shrink" then
    if not (opp_mon and opp_mon.card and (not opp_mon.facedown)) then
      st.last_spell_error = "no_faceup_opp_monster"
      return false, "no_faceup_opp_monster"
    end
  elseif spell_id == "raigeki" then
    -- Cannot be used to win the duel: disallow if you already have 2 points.
    local pts = tonumber(st[side .. "_points"]) or 0
    if pts >= 2 then
      st.last_spell_error = "raigeki_blocked_at_2_points"
      return false, "raigeki_blocked_at_2_points"
    end
    if not (opp_mon and opp_mon.card) then
      st.last_spell_error = "no_target_monster"
      return false, "no_target_monster"
    end
  end

  -- At this point, we are committed: spend counters + mark spell used this turn.
  local ok_spend, reason_spend = M.spend_and_mark_used(st, side, def.cost)
  if not ok_spend then
    st.last_spell_error = reason_spend
    return false, reason_spend
  end

  -- Record activation
  st.last_spell_activated = spell_id
  st.last_spell_activated_side = side
  st.last_spell_activated_at = os.clock()
  st.last_spell_error = nil

  -- Apply effect
  local ti = tonumber(st.turn_index) or 0

  if spell_id == "ceasefire" then
    if api.start_reveal_def_anim then
      pcall(api.start_reveal_def_anim, api.pid, st, opp_side)
    else
      -- Fallback: hard flip (no anim)
      if opp_mon then
        opp_mon.facedown = false
        opp_mon.pos = "def"
      end
    end

  elseif spell_id == "reinforcements" then
    _apply_temp_atk(my_mon, 500, ti)

  elseif spell_id == "axe-despair" then
    _apply_temp_atk(my_mon, 1000, ti)

  elseif spell_id == "shrink" then
    _apply_temp_atk(opp_mon, -1000, ti)

  elseif spell_id == "shield-crush" then
    _apply_perm_def(opp_mon, -500)
    if (tonumber(opp_mon.def_current) or 0) <= 0 then
      -- Destroy by effect; award point + counters.
      local okd = _spell_destroy_monster(st, api, side, opp_side)
      if not okd then
        -- If destroy failed unexpectedly, at least clamp DEF to 0.
        opp_mon.def_current = 0
      end
    end

  elseif spell_id == "curse-anubis" then
    _apply_perm_def(opp_mon, -1000)
    if (tonumber(opp_mon.def_current) or 0) <= 0 then
      local okd = _spell_destroy_monster(st, api, side, opp_side)
      if not okd then
        opp_mon.def_current = 0
      end
    end

  elseif spell_id == "blue-medicine" then
    _apply_perm_def(my_mon, 500)

  elseif spell_id == "earthquake" then
    -- Schedule: at the end of this turn, switch our monster to face-up DEF.
    st[side .. "_pending_end_turn_switch_to_def"] = true
    st[side .. "_pending_end_turn_switch_to_def_set_turn"] = ti

  elseif spell_id == "stop-attack" then
    -- Switch the opponent monster to DEF (face-up only; validation already done).
    -- Note: duels.lua exposes separate helpers for toggling each side; choose based on target.
    if opp_side == "opp" and api.toggle_opponent_monster_position then
      pcall(api.toggle_opponent_monster_position, api.pid, st)
    elseif opp_side == "ply" and api.toggle_player_monster_position then
      pcall(api.toggle_player_monster_position, api.pid, st)
    else
      -- Fallback: hard switch (no anim)
      if opp_mon then opp_mon.pos = "def" end
    end

  elseif spell_id == "raigeki" then
    _spell_destroy_monster(st, api, side, opp_side)

  end

  -- Refresh counters immediately (tick will also redraw).
  if api.draw_spell_counters then pcall(api.draw_spell_counters, api.pid, st) end

  return true, "ok"
end

-- Backwards compatible name (older duels.lua called this).
function M.activate_placeholder(st, side, spell_id, api)
  return M.activate(st, side, spell_id, api)
end

return M
