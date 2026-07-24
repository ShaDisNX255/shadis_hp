local helpers = require('scripts/ezlibs-scripts/helpers')
local ezmemory = require('scripts/ezlibs-scripts/ezmemory')
local ezbus = require('scripts/ezlibs-scripts/ezbus')

local quest_progress = {}
local QUEST_PROGRESS_MEM_KEY = "quest_progress_v1"

local function trim(value)
    if value == nil then return nil end

    local text = tostring(value)
    text = text:gsub("^%s+", ""):gsub("%s+$", "")

    if text == "" then return nil end
    return text
end

local function get_secret(player_id)
    if helpers and helpers.get_safe_player_secret then
        local ok, secret = pcall(helpers.get_safe_player_secret, player_id)
        if ok and secret and secret ~= "" then
            return tostring(secret)
        end
    end

    return tostring(player_id)
end

local function get_store(player_id)
    local secret = get_secret(player_id)
    local pmem = ezmemory.get_player_memory(secret) or {}

    if type(pmem[QUEST_PROGRESS_MEM_KEY]) ~= "table" then
        pmem[QUEST_PROGRESS_MEM_KEY] = {}
    end

    return pmem, pmem[QUEST_PROGRESS_MEM_KEY], secret
end

local function save(secret, pmem)
    if ezmemory.set_player_memory then
        pcall(ezmemory.set_player_memory, secret, pmem)
    end

    if ezmemory.save_player_memory then
        pcall(ezmemory.save_player_memory, secret)
    end
end

function quest_progress.get_state(player_id, quest_id)
    quest_id = trim(quest_id)
    if not quest_id then return nil end

    local _, store = get_store(player_id)
    local rec = store[quest_id]

    if type(rec) == "table" then
        return trim(rec.state)
    end

    if type(rec) == "string" then
        return trim(rec)
    end

    return nil
end

function quest_progress.set_state(player_id, quest_id, state)
    quest_id = trim(quest_id)
    state = trim(state)

    if not quest_id then
        return false
    end

    local pmem, store, secret = get_store(player_id)

    store[quest_id] = store[quest_id] or {}

    if type(store[quest_id]) ~= "table" then
        store[quest_id] = {
            state = tostring(store[quest_id])
        }
    end

    store[quest_id].state = state or "started"
    store[quest_id].updated_at = os.time()

    save(secret, pmem)

    ezbus:emit("quest_progress_changed", {
        player_id = player_id,
        quest_id = quest_id,
        state = store[quest_id].state,
    })

    return true
end

return quest_progress
