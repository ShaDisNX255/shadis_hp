local encounter1 = require('scripts/fishing-config/default-encounters/encounter1')
local encounter2 = require('scripts/fishing-config/default-encounters/encounter2')
local encounter3 = require('scripts/fishing-config/default-encounters/encounter3')
local constants = require('scripts/fishing-config/constants')

local CONFIG = {
    FISHING_VIRUS = {...},
    CONSTANTS = {...},
}

local function _handle_set(set_this, value)

    if (type(set_this) ~= "string") then 
        print("`set_this` was not a string. Please provide a string value that is the name of the `key` in `CONFIG`") 
        return   
    end

    if (type(value) == "table") then
       local result = {}
        for name, set_value in next, value do
            result[name] = set_value
        end
        CONFIG[set_this] = result 
    end

    if (type(value) ~= "table") then
        if (type(CONFIG[set_this]) ~= "table") then 
        print("Not table")
        end
        CONFIG[set_this] = value
        print(CONFIG[set_this])
        return
    end
end

_handle_set("FISHING_VIRUS", {encounter1, encounter2, encounter3})
_handle_set("CONSTANTS", constants)

return CONFIG