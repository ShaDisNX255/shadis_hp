-- duels_AI.lua
-- All duel AI decision-making lives here.
--
-- The AI returns a "plan" table consumed by duels.lua.
--
-- Plan fields (all optional):
--   play = { hand_index = <hand index>, kind = "summon"|"set", pos = "atk"|"def" }
--   toggle_to_atk = true
--   attack = true
--   spell_id = <spell id string>
--   end_turn = true
--
-- Notes:
-- - duels.lua handles the legality checks (summon limits, position-change rules, spell costs, etc.).
-- - This AI adds spell decisions when they can *guarantee* the player's monster is destroyed,
--   and only once the AI has at least 2 spell counters.
-- - Exception: 'Earthquake' is considered *before* attack spells, but ONLY when the player is
--   1 point away from winning, the AI's monster is very strong (ATK>2000 and current DEF>2000),
--   and the AI can KO the player's *face-up* monster with no boosts.

local M = {}

local function _get_card_atk_def(ctx, card)
  if not (ctx and ctx.get_card_atk_def) then return 0, 0 end
  local a, d = ctx.get_card_atk_def(card)
  return tonumber(a) or 0, tonumber(d) or 0
end

local function _mon_atk(ctx, mon)
  if not (mon and mon.card) then return 0 end
  local atk = _get_card_atk_def(ctx, mon.card)
  return (tonumber(atk) or 0) + (tonumber(mon.atk_bonus) or 0)
end

local function _mon_def(ctx, mon)
  if not (mon and mon.card) then return 0 end
  if mon.def_current ~= nil then
    return tonumber(mon.def_current) or 0
  end
  local _, def = _get_card_atk_def(ctx, mon.card)
  return tonumber(def) or 0
end

local function _chip_damage_from_atk(atk)
  atk = tonumber(atk) or 0
  if atk > 1000 then
    return math.floor(atk / 2)
  end
  return atk
end

local function _atk_vs_mon_outcome(attacker_atk, defender_mon, ctx)
  -- Returns: defender_destroyed, attacker_destroyed
  if not defender_mon then return false, false end

  local dpos = defender_mon.pos or "atk"
  if dpos == "atk" then
    local def_atk = _mon_atk(ctx, defender_mon)
    if attacker_atk > def_atk then
      return true, false
    elseif attacker_atk < def_atk then
      return false, true
    else
      -- tie
      return true, true
    end
  else
    local def_val = _mon_def(ctx, defender_mon)
    local chip = _chip_damage_from_atk(attacker_atk)
    if chip >= def_val then
      return true, false
    end
    return false, false
  end
end

local function _strict_kill(attacker_atk, defender_mon, ctx)
  local def_dead, atk_dead = _atk_vs_mon_outcome(attacker_atk, defender_mon, ctx)
  return def_dead and (not atk_dead)
end

local function _any_destroy(attacker_atk, defender_mon, ctx)
  local def_dead, _ = _atk_vs_mon_outcome(attacker_atk, defender_mon, ctx)
  return def_dead
end

local function _pick_highest_atk(hand, ctx)
  local best_idx, best_atk = nil, -1
  for i, card in ipairs(hand or {}) do
    local a = _get_card_atk_def(ctx, card)
    if a > best_atk then
      best_idx, best_atk = i, a
    end
  end
  return best_idx, best_atk
end

local function _pick_highest_def(hand, ctx)
  local best_idx, best_def = nil, -1
  for i, card in ipairs(hand or {}) do
    local _, d = _get_card_atk_def(ctx, card)
    if d > best_def then
      best_idx, best_def = i, d
    end
  end
  return best_idx, best_def
end

local function _best_summon_for_chip_kill(hand, ctx, target_def)
  -- Finds the *strongest* monster that will destroy a DEF-position target via chip.
  target_def = tonumber(target_def) or 0
  local best_idx, best_atk = nil, -1

  for i, card in ipairs(hand or {}) do
    local a = _get_card_atk_def(ctx, card)
    local chip = _chip_damage_from_atk(a)
    if chip >= target_def and a > best_atk then
      best_idx, best_atk = i, a
    end
  end

  return best_idx, best_atk
end

local function _spell_used_this_turn(st)
  local ti = tonumber(st and st.turn_index) or 0
  return (st and st.opp_spell_used_turn_index == ti) or false
end

local function _opp_spell_counters(st)
  return tonumber(st and st.opp_spell_counters) or 0
end

local function _points_down_by_two(st)
  local ply = tonumber(st and st.ply_points) or 0
  local opp = tonumber(st and st.opp_points) or 0
  return (ply - opp) >= 2
end

local function _opponent_one_from_win(st)
  -- "Opponent is 1 point away from winning" means the player has 2 or more points (win at 3).
  local ply = tonumber(st and st.ply_points) or 0
  return ply >= 2
end



local function _pick_best_earthquake_summon(hand, ctx)
  -- Highest ATK monster in hand that also has base DEF>2000 (for Earthquake safety rule).
  local best_idx, best_atk = nil, -1
  for i, card in ipairs(hand or {}) do
    local a, d = _get_card_atk_def(ctx, card)
    if (tonumber(a) or 0) > 2000 and (tonumber(d) or 0) > 2000 then
      if a > best_atk then
        best_idx, best_atk = i, a
      end
    end
  end
  return best_idx, best_atk
end

local function _should_cast_earthquake(st, ctx)
  -- Earthquake (defensive):
  -- Only consider this FIRST when:
  --  - the opponent (player) is 1 point away from winning (player has 2+ points; win at 3)
  --  - we have a face-up monster with ATK>2000 and current DEF>2000
  --  - AND (we can KO the player's face-up monster with no boosts OR the player has a face-down set monster)
  --
  -- For face-down set monsters, we do NOT know stats; Earthquake is used as a defensive "play safe" option.
  if not st then return false end
  if _spell_used_this_turn(st) then return false end
  if _opp_spell_counters(st) < 3 then return false end
  if not _opponent_one_from_win(st) then return false end

  local omon = st.field and st.field.opp_monster
  if not (omon and omon.card and (not omon.facedown)) then return false end

  local a = _mon_atk(ctx, omon)
  local d = _mon_def(ctx, omon) -- uses current DEF when available
  if not ((tonumber(a) or 0) > 2000 and (tonumber(d) or 0) > 2000) then
    return false
  end

  local pmon = st.field and st.field.ply_monster
  if not (pmon and pmon.card) then return false end

  if pmon.facedown then
    -- Always consider Earthquake when the player has a set monster and we're in danger.
    return true
  end

  -- Otherwise, must be able to KO without any boost.
  return _strict_kill(a, pmon, ctx)
end


local function _plan_spell_kill(st, ctx, opts)
  -- Returns a plan or nil.

  opts = opts or {}
  local allow_cost3 = (opts.allow_cost3 == true)

  local pmon = st and st.field and st.field.ply_monster
  if not (pmon and pmon.card) then return nil end
  if pmon.facedown then return nil end

  local counters = _opp_spell_counters(st)
  if counters < 2 then return nil end
  if _spell_used_this_turn(st) then return nil end

  local behind = _points_down_by_two(st)

  local omon = st.field.opp_monster
  local has_own = (omon and omon.card and (not omon.facedown))

  -- If we already have a monster that can naturally destroy the player's monster, do NOT cast spells.
  if has_own then
    local o_atk = _mon_atk(ctx, omon)
    if _any_destroy(o_atk, pmon, ctx) then
      return nil
    end
  end

  local ppos = pmon.pos or "atk"
  local p_atk = _mon_atk(ctx, pmon)
  local p_def = _mon_def(ctx, pmon)

  local function plan_with_existing(spell_id, needs_attack)
    local plan = { end_turn = true, spell_id = spell_id }
    if needs_attack then
      plan.attack = true
      if omon.pos == "def" then plan.toggle_to_atk = true end
    end
    return plan
  end

  local function plan_with_summon(idx, spell_id, needs_attack)
    local plan = { end_turn = true, spell_id = spell_id }
    if idx ~= nil then
      plan.play = { hand_index = idx, idx = idx, kind = "summon", pos = "atk" }
    end
    if needs_attack then plan.attack = true end
    return plan
  end

  -- -------------------------
  -- Cost 2 spells (priority):
  -- -------------------------
  local function try_cost2()
    if counters < 2 then return nil end

    -- shield-crush: -500 DEF (and destroys if DEF <= 0)
    do
      local new_def = p_def - 500
      if new_def <= 0 then
        -- guaranteed destruction by spell alone
        if has_own then
        return plan_with_existing("shield-crush", false)
      else
        -- Still must summon if we have a monster in hand, even if the spell alone destroys.
        local idx = _pick_highest_atk(st.opp and st.opp.hand, ctx)
        return plan_with_summon(idx, "shield-crush", false)
      end
      end
      if ppos == "def" then
        if has_own then
          local o_atk = _mon_atk(ctx, omon)
          if (not _any_destroy(o_atk, pmon, ctx)) and _chip_damage_from_atk(o_atk) >= new_def then
            return plan_with_existing("shield-crush", true)
          end
        else
          local idx = _best_summon_for_chip_kill(st.opp and st.opp.hand, ctx, new_def)
          if idx then
            return plan_with_summon(idx, "shield-crush", true)
          end
        end
      end
    end

    -- stop-attack: force ATK -> DEF, then try to chip-kill
    do
      if ppos == "atk" then
        if has_own then
          local o_atk = _mon_atk(ctx, omon)
          if (not _any_destroy(o_atk, pmon, ctx)) and _chip_damage_from_atk(o_atk) >= p_def then
            return plan_with_existing("stop-attack", true)
          end
        else
          local idx = _best_summon_for_chip_kill(st.opp and st.opp.hand, ctx, p_def)
          if idx then
            return plan_with_summon(idx, "stop-attack", true)
          end
        end
      end
    end

    -- reinforcements: +500 ATK, then attack
    do
      if has_own then
        local o_atk = _mon_atk(ctx, omon)
        if not _any_destroy(o_atk, pmon, ctx) then
          local boosted = o_atk + 500
          if ppos == "atk" then
            if boosted > p_atk then
              return plan_with_existing("reinforcements", true)
            end
          else
            if _chip_damage_from_atk(boosted) >= p_def then
              return plan_with_existing("reinforcements", true)
            end
          end
        end
      else
        local hand = st.opp and st.opp.hand or {}
        if ppos == "atk" then
          -- Need: (atk + 500) > p_atk AND atk < p_atk (otherwise we'd naturally destroy)
          local best_idx, best_a = nil, -1
          for i, card in ipairs(hand) do
            local a = _get_card_atk_def(ctx, card)
            if a < p_atk and (a + 500) > p_atk and a > best_a then
              best_idx, best_a = i, a
            end
          end
          if best_idx then
            return plan_with_summon(best_idx, "reinforcements", true)
          end
        else
          -- Need: chip(atk) < p_def AND chip(atk+500) >= p_def
          local best_idx, best_a = nil, -1
          for i, card in ipairs(hand) do
            local a = _get_card_atk_def(ctx, card)
            local chip0 = _chip_damage_from_atk(a)
            local chip1 = _chip_damage_from_atk(a + 500)
            if chip0 < p_def and chip1 >= p_def and a > best_a then
              best_idx, best_a = i, a
            end
          end
          if best_idx then
            return plan_with_summon(best_idx, "reinforcements", true)
          end
        end
      end
    end

    return nil
  end

  -- -------------------------
  -- Cost 3 spells (behind by 2):
  -- -------------------------
  local function try_cost3()
    if counters < 3 then return nil end

    -- curse-anubis: -1000 DEF perm (and destroys if DEF <= 0)
    do
      local new_def = p_def - 1000
      if new_def <= 0 then
        if has_own then
        return plan_with_existing("curse-anubis", false)
      else
        -- Still must summon if we have a monster in hand, even if the spell alone destroys.
        local idx = _pick_highest_atk(st.opp and st.opp.hand, ctx)
        return plan_with_summon(idx, "curse-anubis", false)
      end
      end
      if ppos == "def" then
        if has_own then
          local o_atk = _mon_atk(ctx, omon)
          if (not _any_destroy(o_atk, pmon, ctx)) and _chip_damage_from_atk(o_atk) >= new_def then
            return plan_with_existing("curse-anubis", true)
          end
        else
          local idx = _best_summon_for_chip_kill(st.opp and st.opp.hand, ctx, new_def)
          if idx then
            return plan_with_summon(idx, "curse-anubis", true)
          end
        end
      end
    end

    -- shrink: opponent ATK -1000 (ATK target only), then attack
    do
      if ppos == "atk" then
        if has_own then
          local o_atk = _mon_atk(ctx, omon)
          if not _any_destroy(o_atk, pmon, ctx) then
            if o_atk > (p_atk - 1000) then
              return plan_with_existing("shrink", true)
            end
          end
        else
          local hand = st.opp and st.opp.hand or {}
          -- Need: atk > p_atk - 1000 AND atk < p_atk (otherwise we'd naturally destroy)
          local best_idx, best_a = nil, -1
          for i, card in ipairs(hand) do
            local a = _get_card_atk_def(ctx, card)
            if a < p_atk and a > (p_atk - 1000) and a > best_a then
              best_idx, best_a = i, a
            end
          end
          if best_idx then
            return plan_with_summon(best_idx, "shrink", true)
          end
        end
      end
    end

    -- axe-despair: +1000 ATK, then attack
    do
      if has_own then
        local o_atk = _mon_atk(ctx, omon)
        if not _any_destroy(o_atk, pmon, ctx) then
          local boosted = o_atk + 1000
          if ppos == "atk" then
            if boosted > p_atk then
              return plan_with_existing("axe-despair", true)
            end
          else
            if _chip_damage_from_atk(boosted) >= p_def then
              return plan_with_existing("axe-despair", true)
            end
          end
        end
      else
        local hand = st.opp and st.opp.hand or {}
        if ppos == "atk" then
          local best_idx, best_a = nil, -1
          for i, card in ipairs(hand) do
            local a = _get_card_atk_def(ctx, card)
            if a < p_atk and (a + 1000) > p_atk and a > best_a then
              best_idx, best_a = i, a
            end
          end
          if best_idx then
            return plan_with_summon(best_idx, "axe-despair", true)
          end
        else
          local best_idx, best_a = nil, -1
          for i, card in ipairs(hand) do
            local a = _get_card_atk_def(ctx, card)
            local chip0 = _chip_damage_from_atk(a)
            local chip1 = _chip_damage_from_atk(a + 1000)
            if chip0 < p_def and chip1 >= p_def and a > best_a then
              best_idx, best_a = i, a
            end
          end
          if best_idx then
            return plan_with_summon(best_idx, "axe-despair", true)
          end
        end
      end
    end

    return nil
  end

  -- -------------------------
  -- Decide by score state
  -- -------------------------
  local plan = try_cost2()
  if plan then return plan end

  if behind or allow_cost3 then
    plan = try_cost3()
    if plan then return plan end

    -- Fallback: summon highest ATK (if empty field), then raigeki.
    if counters >= 4 then
      local opp_points = tonumber(st.opp_points) or 0
      if opp_points >= 2 then
        -- raigeki would be illegal; try stop-attack instead if it guarantees a kill
        local stop_plan = nil
        if ppos == "atk" then
          if has_own then
            local o_atk = _mon_atk(ctx, omon)
            if _chip_damage_from_atk(o_atk) >= p_def then
              stop_plan = plan_with_existing("stop-attack", true)
            end
          else
            local idx = _best_summon_for_chip_kill(st.opp and st.opp.hand, ctx, p_def)
            if idx then stop_plan = plan_with_summon(idx, "stop-attack", true) end
          end
        end
        return stop_plan
      end

      if not has_own then
        local idx = _pick_highest_atk(st.opp and st.opp.hand, ctx)
        -- If no monster in hand, still try raigeki (it doesn't require our monster).
        return plan_with_summon(idx, "raigeki", false)
      end

      -- If we already have a monster, just raigeki.
      return plan_with_existing("raigeki", false)
    end
  end

  return nil
end

local function _default_plan(st, ctx)
  local plan = { end_turn = true }

  local pmon = st.field and st.field.ply_monster
  local omon = st.field and st.field.opp_monster

  local pstate = {
    has = (pmon ~= nil),
    facedown = (pmon and pmon.facedown) or false,
    is_atk = (pmon and pmon.pos == "atk") or false,
    is_def = (pmon and pmon.pos == "def") or false,
    atk = (pmon and _mon_atk(ctx, pmon)) or 0,
  }

  local ostate = {
    has = (omon ~= nil),
    facedown = (omon and omon.facedown) or false,
    is_atk = (omon and omon.pos == "atk") or false,
    is_def = (omon and omon.pos == "def") or false,
    atk = (omon and _mon_atk(ctx, omon)) or 0,
  }

  local hand = (st.opp and st.opp.hand) or {}

  if ostate.has then
    if ostate.facedown then
      -- Reveal and attack.
      plan.toggle_to_atk = true
      plan.attack = true
      return plan
    end

    if ostate.is_def then
      plan.toggle_to_atk = true
    end

    if pstate.has then
      if pstate.facedown then
        -- Unknown defense: just attack.
        plan.attack = true
        return plan
      end

      if pstate.is_def then
        plan.attack = true
        return plan
      end

      -- ATK vs ATK: only attack if we can at least tie.
      if ostate.atk >= pstate.atk then
        plan.attack = true
      end
      return plan
    end

    -- No player monster: nothing to attack.
    return plan
  end

  -- No opponent monster: play from hand.
  if #hand == 0 then
    return plan
  end

  -- Player SET a facedown DEF monster and we have no monster yet:
  -- If our *highest ATK* is > 1500, summon it in ATK and attack.
  -- Otherwise, set our *highest DEF* monster.
  if pstate.has and pstate.is_def and pstate.facedown then
    local idx, a = _pick_highest_atk(hand, ctx)
    if idx and (tonumber(a) or 0) > 1500 then
      plan.play = { hand_index = idx, idx = idx, kind = "summon", pos = "atk" }
      plan.attack = true
    else
      local def_idx = _pick_highest_def(hand, ctx) or idx
      if def_idx then
        plan.play = { hand_index = def_idx, idx = def_idx, kind = "set", pos = "def" }
      end
    end
    return plan
  end

  -- Player has a face-up DEF monster and we have no monster yet:
  -- Summon highest ATK only if it can destroy; otherwise set highest DEF.
  if pstate.has and pstate.is_def and (not pstate.facedown) then
    local idx, a = _pick_highest_atk(hand, ctx)
    if idx and _any_destroy(a, pmon, ctx) then
      plan.play = { hand_index = idx, idx = idx, kind = "summon", pos = "atk" }
      plan.attack = true
    else
      local def_idx = _pick_highest_def(hand, ctx) or idx
      if def_idx then
        plan.play = { hand_index = def_idx, idx = def_idx, kind = "set", pos = "def" }
      end
    end
    return plan
  end

  -- Player has a face-up ATK monster and we have no monster yet:
  -- Summon highest ATK only if it can destroy; otherwise set highest DEF.
  if pstate.has and pstate.is_atk and (not pstate.facedown) then
    local idx, a = _pick_highest_atk(hand, ctx)
    if idx and _any_destroy(a, pmon, ctx) then
      plan.play = { hand_index = idx, idx = idx, kind = "summon", pos = "atk" }
      plan.attack = true
    else
      local def_idx = _pick_highest_def(hand, ctx) or idx
      if def_idx then
        plan.play = { hand_index = def_idx, idx = def_idx, kind = "set", pos = "def" }
      end
    end
    return plan
  end

  -- Default: set the highest DEF card in defense.
  local idx = _pick_highest_def(hand, ctx)
  if idx then
    plan.play = { hand_index = idx, idx = idx, kind = "set", pos = "def" }
  end
  return plan
end

function M.plan(st, ctx)
  local pmon = st and st.field and st.field.ply_monster
  local omon = st and st.field and st.field.opp_monster
  local hand = (st and st.opp and st.opp.hand) or {}
  local counters = _opp_spell_counters(st)

  local function have_own_faceup()
    return (omon and omon.card and (not omon.facedown))
  end

  local function have_player_mon()
    return (pmon and pmon.card)
  end

  local function player_is_facedown_set()
    return have_player_mon() and (pmon.facedown == true)
  end

  local function player_pos()
    return (pmon and (pmon.pos or "atk")) or "atk"
  end

  local function can_ko_with_atk_value(attacker_atk)
    if not have_player_mon() then return false end
    if player_is_facedown_set() then return false end -- unknown stats; cannot "know" KO
    return _strict_kill(attacker_atk, pmon, ctx)
  end

  local function best_attack_value_no_spells()
    if have_own_faceup() then
      return _mon_atk(ctx, omon), nil
    end
    local idx, a = _pick_highest_atk(hand, ctx)
    return a, idx
  end

  local danger = _opponent_one_from_win(st)

  -- -----------------------------------------------------------------------
  -- DANGER LOGIC (player is 1 point away from winning)
  -- -----------------------------------------------------------------------
  if danger and have_player_mon() then
    -- (1) Consider Earthquake FIRST:
    --     - if we can KO player's face-up monster with no boosts
    --       OR if the player has a set, face-down monster
    --     - requires: spell unused + 3+ counters + strong monster rule.
    do
      if (not _spell_used_this_turn(st)) and counters >= 3 then
        if have_own_faceup() then
          if _should_cast_earthquake(st, ctx) then
            local plan = _default_plan(st, ctx)
            plan.spell_id = "earthquake"
            plan.attack = true
            return plan
          end
        else
          local eq_idx, eq_atk = _pick_best_earthquake_summon(hand, ctx)
          if eq_idx then
            local ok_faceup_ko = (not player_is_facedown_set()) and can_ko_with_atk_value(eq_atk)
            local ok_facedown = player_is_facedown_set()
            if ok_faceup_ko or ok_facedown then
              local plan = { end_turn = true, spell_id = "earthquake", attack = true }
              plan.play = { hand_index = eq_idx, idx = eq_idx, kind = "summon", pos = "atk" }
              return plan
            end
          end
        end
      end
    end

    -- (2) If it can't KO with no boost, try _plan_spell_kill (allow cost-3 lines even if not "behind by 2").
    do
      local best_atk, _ = best_attack_value_no_spells()
      if best_atk and can_ko_with_atk_value(best_atk) then
        return _default_plan(st, ctx)
      end

      local spell_plan = _plan_spell_kill(st, ctx, { allow_cost3 = true })
      if spell_plan then
        return spell_plan
      end
    end

    -- (3) Can't KO with spell and player is in face-up DEF:
    --     summon highest ATK, cast blue-medicine (if possible), and attack.
    do
      if (not player_is_facedown_set()) and player_pos() == "def" then
        local plan = { end_turn = true }

        if have_own_faceup() then
          if omon.pos == "def" then plan.toggle_to_atk = true end
        else
          local idx = _pick_highest_atk(hand, ctx)
          if idx then
            plan.play = { hand_index = idx, idx = idx, kind = "summon", pos = "atk" }
          end
        end

        if (not _spell_used_this_turn(st)) and counters >= 3 then
          plan.spell_id = "blue-medicine"
        end

        plan.attack = true
        return plan
      end
    end

    -- If player is DEF but face-down (set), treat it as "safe to swing" (no extra spells).
    do
      if player_pos() == "def" then
        local plan = { end_turn = true }
        if have_own_faceup() then
          if omon.facedown or omon.pos == "def" then plan.toggle_to_atk = true end
          plan.attack = true
          return plan
        end
        local idx = _pick_highest_atk(hand, ctx)
        if idx then
          plan.play = { hand_index = idx, idx = idx, kind = "summon", pos = "atk" }
          plan.attack = true
        end
        return plan
      end
    end

    -- (4) Can't KO with spell and player is face-up ATK:
    --     cast Stop Attack + summon highest ATK + attack; if can't cast it -> set highest DEF.
    do
      if (not player_is_facedown_set()) and player_pos() == "atk" then
        if (not _spell_used_this_turn(st)) and counters >= 2 then
          local plan = { end_turn = true, spell_id = "stop-attack", attack = true }
          if have_own_faceup() then
            if omon.facedown or omon.pos == "def" then plan.toggle_to_atk = true end
          else
            local idx = _pick_highest_atk(hand, ctx)
            if idx then
              plan.play = { hand_index = idx, idx = idx, kind = "summon", pos = "atk" }
            end
          end
          return plan
        end

        if not (omon and omon.card) then
          local plan = { end_turn = true }
          local didx = _pick_highest_def(hand, ctx)
          if didx then
            plan.play = { hand_index = didx, idx = didx, kind = "set", pos = "def" }
          end
          return plan
        end

        return _default_plan(st, ctx)
      end
    end

    return _default_plan(st, ctx)
  end

  -- -----------------------------------------------------------------------
  -- NORMAL LOGIC (player has 0 or 1 point)
  -- -----------------------------------------------------------------------

  -- (1) If we can KO with no boosts, do it (do not waste spell counters).
  do
    if have_player_mon() and (not player_is_facedown_set()) then
      -- If we already have a monster (face-up or face-down), use it.
      if omon and omon.card then
        local o_atk = _mon_atk(ctx, omon)
        if _any_destroy(o_atk, pmon, ctx) then
          return _default_plan(st, ctx)
        end
      else
        -- Otherwise, see if our highest-ATK summon can KO without spells.
        local idx, a = _pick_highest_atk(hand, ctx)
        if idx and _any_destroy(a, pmon, ctx) then
          local plan = { end_turn = true, attack = true }
          plan.play = { hand_index = idx, idx = idx, kind = "summon", pos = "atk" }
          return plan
        end
      end
    end
  end

  -- (2) Try guaranteed-kill spell lines (conservative: cost-3 only when "behind by 2").
  do
    local spell_plan = _plan_spell_kill(st, ctx, { allow_cost3 = false })
    if spell_plan then
      return spell_plan
    end
  end

  if not have_player_mon() then
    return _default_plan(st, ctx)
  end

  -- (3) If player is in DEF (set or face-up): summon highest ATK and attack.
  if player_pos() == "def" then
    local plan = { end_turn = true }
    if have_own_faceup() then
      if omon.facedown or omon.pos == "def" then plan.toggle_to_atk = true end
      plan.attack = true
      return plan
    end
    local idx = _pick_highest_atk(hand, ctx)
    if idx then
      plan.play = { hand_index = idx, idx = idx, kind = "summon", pos = "atk" }
      plan.attack = true
    end
    return plan
  end

  -- (4) Player is face-up ATK:
  --     if we can't beat it (no spells available/guaranteed), set highest DEF (only if we have no monster).
  if (not player_is_facedown_set()) and player_pos() == "atk" then
    local best_atk, _ = best_attack_value_no_spells()
    if best_atk and _any_destroy(best_atk, pmon, ctx) then
      return _default_plan(st, ctx)
    end

    if not (omon and omon.card) then
      local plan = { end_turn = true }
      local didx = _pick_highest_def(hand, ctx)
      if didx then
        plan.play = { hand_index = didx, idx = didx, kind = "set", pos = "def" }
      end
      return plan
    end

    return _default_plan(st, ctx)
  end

  return _default_plan(st, ctx)
end



return M
