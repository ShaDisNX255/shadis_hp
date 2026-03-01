-- /server/scripts/teams/month.lua
-- DEFAULT money every month; MONTHS adds month-specific extras that MERGE with DEFAULT.
-- EVENTS are 2–3 day special claims, independent of monthly.

local Month = {}

-- ===== Default rewards that apply every month =====
Month.DEFAULT = {
  min_gp_for_payout      = 5,      -- winner eligibility
  min_gp_for_consolation = 5,      -- loser eligibility

  team_win = {
    money = 500000,                -- winners always get this money
    -- (you can add default packs/items here later if you want)
  },

  top_player = {
    money = 300000,                -- top player per team always gets this money
  },

  losing_team = {
    money = 150000,                 -- losers (meeting min GP) always get this money
  },
}

-- ===== Month-specific extras that MERGE onto DEFAULT =====
Month.MONTHS = {
  -- October 2025
  ["2025-10"] = {
    top_player = {

    },
    team_win = {
      items_inline = {
        { type="item", name="[GDR]Kbo", description="GDRare: Kuriboh - A: 300 / D: 200", amount=1 }
      }
    },
    losing_team = {
      items_inline = {
        { type="item", name="[GDR]Kbo", description="GDRare: Kuriboh - A: 300 / D: 200", amount=1 }
      }
    },
  },

  -- November 2025
  ["2025-11"] = {
    top_player = {
      items_inline = {
        { type="item", name="[SR]F.A.DMGirl", description="FullArt: Dark Magician Girl - A: 2000 / D: 1700", amount=1 }
      }
    },
    team_win = {
      decor = {{ id="nov_fountain", qty=1, label="Blue Fountain" }}
    },
    losing_team = {
      pack_name = "Team Pack Vol. 1",
      pack_rolls = 1,   -- how many random cards to give from pack_pool
      pack_pool = {
        -- weight is relative odds; amount is how many copies of that card to give
        { type = "item", name = "[SR]Gaia", description = "SRare: Gaia the Fierce Knight - A: 2300 / D: 2100", amount = 1, weight = 20 },
        { type = "item", name = "[SR]REBMD", description = "SRare: Red-Eyes Black Metal Dragon - A: 2800 / D: 2400", amount = 1, weight = 20 },
        { type = "item", name = "[SR]REBD", description = "SRare: Red Eyes Black Dragon - A: 2400 / D: 2000", amount = 1, weight = 20 },
        { type = "item", name = "[UR]S.Skull", description = "URare: Summoned Skull - A: 2500 / D: 1200", amount = 1, weight = 20 },
        { type = "item", name = "[GR]DMGirl", description = "GRare: Dark Magician Girl - A: 2000 / D: 1700", amount = 1, weight = 4 },
        { type = "item", name = "[GR]DMag", description = "GRare: Dark Magician - A: 2500 / D: 2100", amount = 1, weight = 4 },
        { type = "item", name = "[GDR]S.Skull", description = "GDRare: Summoned Skull - A: 2500 / D: 1200", amount = 1, weight = 2 },
      },
    },
  },

  -- December 2025
  ["2025-12"] = {
    top_player = {
      items_inline = {
        { type="item", name="[UR]F.A.DMag", description="FullArt: Dark Magician - A: 2500 / D: 2100", amount=1 }
      }
    },
    team_win = {
       cosmetics = {
         { id = "Wave1", label = "Wave1" },
       },
    },
    losing_team = {
      pack_name = "Team Pack Vol. 1",
      pack_rolls = 1,   -- how many random cards to give from pack_pool
      pack_pool = {
        -- weight is relative odds; amount is how many copies of that card to give
        { type = "item", name = "[SR]Gaia",       description = "SRare: Gaia the Fierce Knight - A: 2300 / D: 2100", amount = 1, weight = 20 },
        { type = "item", name = "[SR]REBMD",      description = "SRare: Red-Eyes Black Metal Dragon - A: 2800 / D: 2400", amount = 1, weight = 20 },
        { type = "item", name = "[SR]REBD",       description = "SRare: Red Eyes Black Dragon - A: 2400 / D: 2000", amount = 1, weight = 20 },
        { type = "item", name = "[UR]S.Skull",    description = "URare: Summoned Skull - A: 2500 / D: 1200", amount = 1, weight = 20 },
        { type = "item", name = "[GR]DMGirl",     description = "GRare: Dark Magician Girl - A: 2000 / D: 1700", amount = 1, weight = 4 },
        { type = "item", name = "[GR]DMag",       description = "GRare: Dark Magician - A: 2500 / D: 2100", amount = 1, weight = 4 },
        { type = "item", name = "[GDR]S.Skull",   description = "GDRare: Summoned Skull - A: 2500 / D: 1200", amount = 1, weight = 2 },
        { type = "item", name = "[SR]F.A.DMGirl", description = "FullArt: Dark Magician Girl - A: 2000 / D: 1700", amount=1, weight = 2}
      },
    },
  },

  -- January 2026
  ["2026-01"] = {
    top_player = {
      items_inline = {
        { type="item", name="[UR]F.A.REBD", description="FullArt: Red Eyes Black Dragon - A: 2400 / D: 2000", amount=1 }
      }
    },
    team_win = {
       cosmetics = {
         { id = "Lightning1", label = "Lightning1" },
       },
    },
    losing_team = {
      pack_name = "Team Pack Vol. 1",
      pack_rolls = 1,   -- how many random cards to give from pack_pool
      pack_pool = {
        -- weight is relative odds; amount is how many copies of that card to give
        { type = "item", name = "[SR]Gaia",       description = "SRare: Gaia the Fierce Knight - A: 2300 / D: 2100", amount = 1, weight = 20 },
        { type = "item", name = "[SR]REBMD",      description = "SRare: Red-Eyes Black Metal Dragon - A: 2800 / D: 2400", amount = 1, weight = 20 },
        { type = "item", name = "[SR]REBD",       description = "SRare: Red Eyes Black Dragon - A: 2400 / D: 2000", amount = 1, weight = 20 },
        { type = "item", name = "[UR]S.Skull",    description = "URare: Summoned Skull - A: 2500 / D: 1200", amount = 1, weight = 20 },
        { type = "item", name = "[GR]DMGirl",     description = "GRare: Dark Magician Girl - A: 2000 / D: 1700", amount = 1, weight = 4 },
        { type = "item", name = "[GR]DMag",       description = "GRare: Dark Magician - A: 2500 / D: 2100", amount = 1, weight = 4 },
        { type = "item", name = "[GDR]S.Skull",   description = "GDRare: Summoned Skull - A: 2500 / D: 1200", amount = 1, weight = 2 },
        { type = "item", name = "[SR]F.A.DMGirl", description = "FullArt: Dark Magician Girl - A: 2000 / D: 1700", amount=1, weight = 2},
        { type = "item", name = "[UR]F.A.DMag",   description = "FullArt: Dark Magician - A: 2500 / D: 2100", amount=1, weight = 2}
      },
    },
  },
  -- February 2026
  ["2026-02"] = {
    top_player = {
      items_inline = {
        { type="item", name="[UR]F.A.S.Skull", description="FullArt: Summoned Skull - A: 2500 / D: 1200", amount=1 }
      }
    },
    team_win = {
       cosmetics = {
         { id = "Lightning1", label = "Lightning1" },
       },
    },
    losing_team = {
      pack_name = "Team Pack Vol. 1",
      pack_rolls = 1,   -- how many random cards to give from pack_pool
      pack_pool = {
        -- weight is relative odds; amount is how many copies of that card to give
        { type = "item", name = "[SR]Gaia",       description = "SRare: Gaia the Fierce Knight - A: 2300 / D: 2100", amount = 1, weight = 20 },
        { type = "item", name = "[SR]REBMD",      description = "SRare: Red-Eyes Black Metal Dragon - A: 2800 / D: 2400", amount = 1, weight = 20 },
        { type = "item", name = "[SR]REBD",       description = "SRare: Red Eyes Black Dragon - A: 2400 / D: 2000", amount = 1, weight = 20 },
        { type = "item", name = "[UR]S.Skull",    description = "URare: Summoned Skull - A: 2500 / D: 1200", amount = 1, weight = 20 },
        { type = "item", name = "[GR]DMGirl",     description = "GRare: Dark Magician Girl - A: 2000 / D: 1700", amount = 1, weight = 4 },
        { type = "item", name = "[GR]DMag",       description = "GRare: Dark Magician - A: 2500 / D: 2100", amount = 1, weight = 4 },
        { type = "item", name = "[GDR]S.Skull",   description = "GDRare: Summoned Skull - A: 2500 / D: 1200", amount = 1, weight = 2 },
        { type = "item", name = "[SR]F.A.DMGirl", description = "FullArt: Dark Magician Girl - A: 2000 / D: 1700", amount=1, weight = 2},
        { type = "item", name = "[UR]F.A.DMag",   description = "FullArt: Dark Magician - A: 2500 / D: 2100", amount=1, weight = 2},
        { type = "item", name = "[UR]F.A.REBD",   description = "FullArt: Red Eyes Black Dragon - A: 2400 / D: 2000", amount=1, weight = 2 },
      },
    },
  },
}

-- ===== Dated special events (independent of monthly rewards) =====
-- Dates inclusive, format "YYYY-MM-DD"
Month.EVENTS = {
  -- Example:
  {
   id   = "Halloween-DOTD-2025",
   name = "Halloween & Day of the Dead 2025",
   start = "2025-10-27",
   ["end"] = "2025-11-01",
   rewards = {
      items_inline = {
        { type="item", name="[SR]F.A.V.Lord", description="FullArt: Vampire Lord - A: 2000 / D: 1500", amount=1 }
      },
      decor_pack_name = "Day of the Dead Skull Gift",
      decor_rolls = 1,
      decor_pool = {
        { id="skull_1", weight=1, label="DOTD Skull Blk" },
        { id="skull_2", weight=1, label="DOTD Skull Wht" },
      },
   }
 },
  {
   id   = "Christmas-2025",
   name = "Christmas 2025 Gift",
   start = "2025-12-25",
   ["end"] = "2025-12-31",
   rewards = {
            items_inline = {
        { type="item", name="[SR]F.A.Kboble", description="FullArt: Kuribohble - A: 300 / D: 200", amount=1 }
      },
   }
  },
  {
   id   = "PrizeTest-260301",
   name = "Prize Test",
   start = "2026-02-01",
   ["end"] = "2026-02-02",
   rewards = {
     cosmetics = {
       { id = "Shiny1", label = "Shiny1" },
     },
     items_inline = {
         { type="item", name="[UR]F.A.S.Skull", description="FullArt: Summoned Skull - A: 2500 / D: 1200", amount=1 }
     },
   }
  },
}

-- ===== Utilities =====
local function _deepcopy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k,x in pairs(v) do t[k] = _deepcopy(x) end
  return t
end

-- Merge a bucket (team_win/top_player/losing_team) from base+over:
-- money sums; items_inline concatenates; pack_pool concatenates; pack_rolls adds; pack_name prefers override
local function _merge_bucket(base, over)
  base = _deepcopy(base or {})
  over = over or {}

  base.money = (tonumber(base.money or 0) or 0) + (tonumber(over.money or 0) or 0)

  if over.items_inline then
    base.items_inline = base.items_inline or {}
    for _,it in ipairs(over.items_inline) do table.insert(base.items_inline, _deepcopy(it)) end
  end

  if over.pack_pool then
    base.pack_pool = base.pack_pool or {}
    for _,it in ipairs(over.pack_pool) do table.insert(base.pack_pool, _deepcopy(it)) end
  end
  if over.pack_rolls then
    base.pack_rolls = (tonumber(base.pack_rolls or 0) or 0) + (tonumber(over.pack_rolls or 0) or 0)
  end
  if over.pack_name then
    base.pack_name = over.pack_name
  end
  -- Merge decor (fixed decor rewards)
  if over.decor then
    base.decor = base.decor or {}
    for _, d in ipairs(over.decor) do
      table.insert(base.decor, _deepcopy(d))
    end
  end

  -- Merge cosmetics (cosmetic rewards)
  if over.cosmetics then
    base.cosmetics = base.cosmetics or {}
    for _, c in ipairs(over.cosmetics) do
      table.insert(base.cosmetics, _deepcopy(c))
    end
  end

  return base
end

-- Public: DEFAULT merged with MONTHS[month_key]
function Month.get_rewards_for(month_key)
  local base = Month.DEFAULT or {}
  local over = (Month.MONTHS and Month.MONTHS[month_key]) or {}

  local out = _deepcopy(base)
  if over.min_gp_for_payout ~= nil then out.min_gp_for_payout = over.min_gp_for_payout end
  if over.min_gp_for_consolation ~= nil then out.min_gp_for_consolation = over.min_gp_for_consolation end

  out.team_win    = _merge_bucket(base.team_win,    over.team_win)
  out.top_player  = _merge_bucket(base.top_player,  over.top_player)
  out.losing_team = _merge_bucket(base.losing_team, over.losing_team)
  return out
end

-- Events API
local function _ymd_to_time(s)
  local y,m,d = s:match("^(%d+)%-(%d+)%-(%d+)$")
  if not y then return nil end
  return os.time{ year=tonumber(y), month=tonumber(m), day=tonumber(d), hour=12 }
end

function Month.get_active_events(now_ts)
  local ts = now_ts or os.time()
  local y  = tonumber(os.date("%Y", ts))
  local m  = tonumber(os.date("%m", ts))
  local d  = tonumber(os.date("%d", ts))
  local day_ts = os.time{ year=y, month=m, day=d, hour=12 }

  local list = {}
  for _,evt in ipairs(Month.EVENTS or {}) do
    local st = _ymd_to_time(evt.start or "")
    local ed = _ymd_to_time(evt["end"] or evt.until_date or "")
    if st and ed and day_ts >= st and day_ts <= ed then list[#list+1] = evt end
  end
  return list
end

return Month
