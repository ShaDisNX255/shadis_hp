local helpers      = require('scripts/ezlibs-scripts/helpers')
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
    
    local copy = helpers.deep_copy(value)
    CONFIG[set_this] = copy
end

_handle_set("FISHING_VIRUS", {encounter1, encounter2, encounter3})
_handle_set("CONSTANTS", constants)

return CONFIG