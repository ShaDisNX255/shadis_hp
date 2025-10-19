-- /server/scripts/fishing-config/main.lua
local helpers   = require('scripts/ezlibs-scripts/helpers')
local constants = require('scripts/fishing-config/constants')
local encounters= require('scripts/fishing-config/encounters')

local CONFIG = {
  FISHING_VIRUS = {},
  CONSTANTS     = {},
}

local function _handle_set(set_this, value)
  if (type(set_this) ~= "string") then
    print("`set_this` was not a string. Please provide a string key in CONFIG")
    return
  end
  local copy = helpers.deep_copy(value)
  CONFIG[set_this] = copy
end

-- Defaults (global)
_handle_set("FISHING_VIRUS", encounters.list)
_handle_set("CONSTANTS", constants)

-- --- Area-aware overrides -----------------------------------------------------

CONFIG.AREAS = CONFIG.AREAS or {}

-- shallow+deep merge (table fields recurse, scalars overwrite)
local function _merge(dst, src)
  if type(dst) ~= "table" or type(src) ~= "table" then return helpers.deep_copy(src) end
  for k,v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then
      _merge(dst[k], v)
    else
      dst[k] = helpers.deep_copy(v)
    end
  end
  return dst
end

function CONFIG.set_area(area_id, tbl)
  CONFIG.AREAS[area_id] = helpers.deep_copy(tbl or {})
end

function CONFIG.get_constants_for_area(area_id)
  local base = helpers.deep_copy(CONFIG.CONSTANTS)
  local area = CONFIG.AREAS and CONFIG.AREAS[area_id]
  if area and type(area.CONSTANTS) == "table" then
    _merge(base, area.CONSTANTS)
  end
  return base
end

function CONFIG.get_viruses_for_area(area_id)
  local area = CONFIG.AREAS and CONFIG.AREAS[area_id]
  if area and type(area.FISHING_VIRUS) == "table" then
    return helpers.deep_copy(area.FISHING_VIRUS)
  end
  return helpers.deep_copy(CONFIG.FISHING_VIRUS)
end

-- Optional external per-area overrides
do
  local ok, areas_mod = pcall(require, 'scripts/fishing-config/areas')
  if ok and areas_mod ~= nil then
    if type(areas_mod) == "function" then
      areas_mod(CONFIG)  -- registrar style
    elseif type(areas_mod) == "table" then
      for area_id, payload in pairs(areas_mod) do
        CONFIG.set_area(area_id, payload) -- table style
      end
    end
  end
end

return CONFIG
