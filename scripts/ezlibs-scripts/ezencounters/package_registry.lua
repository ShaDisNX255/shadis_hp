-- Generated encounter package registry for the Android-friendly split packages.
-- The original ezencounters.zip remains the full legacy fallback.
local registry = {}

registry.FALLBACK_PATH = "/server/assets/ezlibs-assets/ezencounters/ezencounters.zip"
registry.DOWNLOAD_AREA = "WCity1"
registry.PACKAGE_PREFIX = "/server/assets/ezlibs-assets/ezencounters/optimized/"

registry.WCITY1_PATH = registry.PACKAGE_PREFIX .. "wcity1.zip"
registry.WCITY2_PATH = registry.PACKAGE_PREFIX .. "wcity2.zip"
registry.TECHLAB_PATH = registry.PACKAGE_PREFIX .. "techlab.zip"
registry.DUNGEON1_PATH = registry.PACKAGE_PREFIX .. "dungeon1.zip"
registry.EVENTS_PATH = registry.PACKAGE_PREFIX .. "events.zip"
registry.FISHING_PATH = registry.PACKAGE_PREFIX .. "fishing.zip"
registry.RAIDS_PATH = registry.PACKAGE_PREFIX .. "raids.zip"
registry.TOURNAMENTS_PATH = registry.PACKAGE_PREFIX .. "tournaments.zip"
registry.ELMQUEST_PATH = registry.PACKAGE_PREFIX .. "elmquest.zip"
registry.PETDUELS_PATH = registry.PACKAGE_PREFIX .. "petduels.zip"


registry.packages = {
    [registry.WCITY1_PATH] = {
        name = "WCity1" ,
        package_id = "com.shadishp.mob.ezencounters.wcity1" ,
        allow_battle_pets = true,
        supports_obstacles = false,
        supports_music = false,
    },
    [registry.WCITY2_PATH] = {
        name = "WCity2" ,
        package_id = "com.shadishp.mob.ezencounters.wcity2" ,
        allow_battle_pets = true,
        supports_obstacles = false,
        supports_music = false,
    },
    [registry.TECHLAB_PATH] = {
        name = "TechLab" ,
        package_id = "com.shadishp.mob.ezencounters.techlab" ,
        allow_battle_pets = true,
        supports_obstacles = false,
        supports_music = false,
    },
    [registry.DUNGEON1_PATH] = {
        name = "Dungeon1" ,
        package_id = "com.shadishp.mob.ezencounters.dungeon1" ,
        allow_battle_pets = true,
        supports_obstacles = true,
        supports_music = false,
    },
    [registry.EVENTS_PATH] = {
        name = "Events" ,
        package_id = "com.shadishp.mob.ezencounters.events" ,
        allow_battle_pets = true,
        supports_obstacles = false,
        supports_music = true,
    },
    [registry.FISHING_PATH] = {
        name = "Fishing" ,
        package_id = "com.shadishp.mob.ezencounters.fishing" ,
        allow_battle_pets = true,
        supports_obstacles = true,
        supports_music = false,
    },
    [registry.RAIDS_PATH] = {
        name = "Raids" ,
        package_id = "com.shadishp.mob.ezencounters.raids" ,
        allow_battle_pets = true,
        supports_obstacles = true,
        supports_music = false,
    },
    [registry.TOURNAMENTS_PATH] = {
        name = "Tournaments" ,
        package_id = "com.shadishp.mob.ezencounters.tournaments" ,
        allow_battle_pets = false,
        supports_obstacles = false,
        supports_music = false,
    },
    [registry.ELMQUEST_PATH] = {
        name = "Elmquest" ,
        package_id = "com.shadishp.mob.ezencounters.elmquest" ,
        allow_battle_pets = true,
        supports_obstacles = false,
        supports_music = false,
    },
    [registry.PETDUELS_PATH] = {
        name = "PetDuels",
        package_id = "com.shadishp.mob.ezencounters.petduels",
        allow_battle_pets = false,
        supports_obstacles = false,
        supports_music = false,
    },
}

function registry.get(path)
    return registry.packages[tostring(path or "")]
end

function registry.list_paths()
    local out = {}
    for path in pairs(registry.packages) do out[#out + 1] = path end
    table.sort(out)
    return out
end

return registry
