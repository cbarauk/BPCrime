--[[
    BPCrime - parking meters - server.lua
    All payouts, cooldowns, lockpick usage and validation happen here. Client is never trusted.
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- Lower bound on how long a real Tumbler run takes (about 0.25s per round).
-- Anything faster is treated as a client-side bypass.
local MIN_ATTEMPT_SECONDS = math.floor(#Config.LockpickRounds * 0.25)

-- ============================================================================
--  INLINE HELPERS (no shared/utils dependency)
-- ============================================================================
local function joaat(str)
    local hash = 0
    str = str:lower()
    for i = 1, #str do
        hash = (hash + str:byte(i)) & 0xffffffff
        hash = (hash + (hash << 10)) & 0xffffffff
        hash = hash ~ (hash >> 6)
    end
    hash = (hash + (hash << 3)) & 0xffffffff
    hash = hash ~ (hash >> 11)
    hash = (hash + (hash << 15)) & 0xffffffff
    return hash
end

local KEY_PATTERN = '^(%a[%w_]*)@(%-?%d+%.?%d*)_(%-?%d+%.?%d*)_(%-?%d+%.?%d*)$'

local function parseKey(key, allowedNames)
    if type(key) ~= 'string' or #key > 128 then return nil end
    local model, sx, sy, sz = key:match(KEY_PATTERN)
    if not model or not allowedNames[model] then return nil end
    local x, y, z = tonumber(sx), tonumber(sy), tonumber(sz)
    if not x or not y or not z then return nil end
    if x ~= x or y ~= y or z ~= z then return nil end
    if math.abs(x) > 10000.0 or math.abs(y) > 10000.0 or math.abs(z) > 10000.0 then return nil end
    return vector3(x, y, z)
end

local function loadCooldowns(file, allowedNames)
    local raw = LoadResourceFile(GetCurrentResourceName(), file)
    if not raw then return {} end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then return {} end
    local now, out = os.time(), {}
    for key, expiry in pairs(data) do
        if type(expiry) == 'number' and expiry > now and parseKey(key, allowedNames) then
            out[key] = expiry
        end
    end
    return out
end

local function saveCooldowns(file, cooldowns)
    SaveResourceFile(GetCurrentResourceName(), file, json.encode(cooldowns), -1)
end

-- ============================================================================
--  ALLOWED MODELS
-- ============================================================================
local allowedNames, allowedModels = {}, {}
for _, name in ipairs(Config.MeterModels) do
    allowedNames[name]          = true
    allowedModels[joaat(name)]  = name
end

-- ============================================================================
--  STATE
-- ============================================================================
local cooldowns, busyPlayers, busyMeters, lastAttempt = {}, {}, {}, {}
local COOLDOWN_FILE = 'cooldowns.json'

local function SaveCooldowns()
    if not Config.PersistCooldowns then return end
    saveCooldowns(COOLDOWN_FILE, cooldowns)
end

local function LoadCooldowns()
    if not Config.PersistCooldowns then return end
    cooldowns = loadCooldowns(COOLDOWN_FILE, allowedNames)
    local n = 0
    for _ in pairs(cooldowns) do n = n + 1 end
    print(('[BPCrime] restored %d active cooldown(s)'):format(n))
end

-- ============================================================================
--  HELPERS
-- ============================================================================
local function Notify(src, msg, ntype)
    TriggerClientEvent('QBCore:Notify', src, msg, ntype or 'primary')
end

local function IsOnCooldown(key)
    local e = cooldowns[key]
    return e ~= nil and e > os.time()
end

local function ReleaseAttempt(src)
    local st = busyPlayers[src]
    if st then
        if busyMeters[st.meterKey] == src then busyMeters[st.meterKey] = nil end
        busyPlayers[src] = nil
    end
end

local function SetCooldown(key)
    cooldowns[key] = os.time() + (Config.CooldownMinutes * 60)
    TriggerClientEvent('meters:client:setCooldown', -1, key, Config.CooldownMinutes * 60)
    SaveCooldowns()
end

local function ClearCooldown(key)
    cooldowns[key] = nil
    TriggerClientEvent('meters:client:clearCooldown', -1, key)
    SaveCooldowns()
end

local function HasLockpick(src)
    local P = QBCore.Functions.GetPlayer(src)
    return P ~= nil and P.Functions.GetItemByName(Config.LockpickItem) ~= nil
end

local function LogAttempt(src, key, success, amount)
    local name = GetPlayerName(src) or 'unknown'
    if success then
        print(('[BPCrime] %s [#%d] broke open %s and looted $%d'):format(name, src, key, amount))
    else
        print(('[BPCrime] FAILED attempt: %s [#%d] on %s'):format(name, src, key))
    end
end

-- ============================================================================
--  VALIDATION
-- ============================================================================
local function ValidateAttempt(src, netId, key)
    local meterCoords = parseKey(key, allowedNames)
    if not meterCoords then
        return nil, 'Invalid interaction.'
    end

    netId = tonumber(netId) or 0
    if netId ~= 0 then
        local entity = NetworkGetEntityFromNetworkId(netId)
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            if not allowedModels[GetEntityModel(entity)] then
                return nil, 'Invalid target.'
            end
            if #(GetEntityCoords(entity) - meterCoords) > 2.0 then
                return nil, 'Invalid interaction.'
            end
        end
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        return nil, 'Invalid ped.'
    end

    if #(GetEntityCoords(ped) - meterCoords) > (Config.InteractDistance + Config.ServerDistanceGrace) then
        return nil, 'You are too far away from the meter.'
    end

    if IsOnCooldown(key) then
        return nil, 'This meter has already been looted.'
    end

    return meterCoords
end

-- ============================================================================
--  EVENTS
-- ============================================================================
RegisterNetEvent('meters:server:startAttempt', function(netId, key)
    local src = source

    if busyPlayers[src] then
        return Notify(src, "You're already busy with a meter.", 'error')
    end

    local last = lastAttempt[src]
    if last and (os.time() - last) < Config.AttemptDelay then
        return Notify(src, 'Slow down a little.', 'error')
    end

    local meterCoords, err = ValidateAttempt(src, netId, key)
    if not meterCoords then
        return TriggerClientEvent('meters:client:attemptRejected', src, err)
    end

    if not HasLockpick(src) then
        return TriggerClientEvent('meters:client:attemptRejected', src,
            ('You need a %s to break this open.'):format(Config.LockpickItem))
    end

    if busyMeters[key] then
        return Notify(src, 'Someone is already working on this meter.', 'error')
    end

    busyPlayers[src] = { meterKey = key, expires = os.time() + Config.AttemptTimeout, startedAt = os.time() }
    busyMeters[key]  = src

    TriggerClientEvent('meters:client:attemptAccepted', src, key)

    SetTimeout(Config.AttemptTimeout * 1000, function()
        if busyPlayers[src] and busyPlayers[src].meterKey == key then
            ReleaseAttempt(src)
        end
    end)
end)

RegisterNetEvent('meters:server:finishAttempt', function(key, success, cancelled)
    local src   = source
    local state = busyPlayers[src]

    if not state or state.meterKey ~= key then return end

    if state.expires < os.time() then
        ReleaseAttempt(src)
        return Notify(src, 'You took too long.', 'error')
    end

    success = success == true
    cancelled = cancelled == true

    -- Reject a "success" that finished faster than a human could play it.
    if success and (os.time() - state.startedAt) < MIN_ATTEMPT_SECONDS then
        ReleaseAttempt(src)
        LogAttempt(src, key, false)
        return Notify(src, 'You failed to break the meter open.', 'error')
    end

    local meterCoords, err = ValidateAttempt(src, 0, key)
    ReleaseAttempt(src)

    if not meterCoords then
        return Notify(src, err, 'error')
    end

    lastAttempt[src] = os.time()

    if not success then
        if Config.BreakOnFail and not cancelled then
            local Player = QBCore.Functions.GetPlayer(src)
            if Player and Player.Functions.RemoveItem(Config.LockpickItem, 1) then
                TriggerClientEvent(Config.ItemBoxEvent, src, QBCore.Shared.Items[Config.LockpickItem], 'remove', 1)
            end
        end
        LogAttempt(src, key, false)
        return Notify(src, cancelled and 'You back off the meter' or 'You failed to break the meter open.', 'error')
    end

    local amount = math.random(Config.PayoutMin, Config.PayoutMax)
    local Player = QBCore.Functions.GetPlayer(src)
    if Player and Player.Functions.AddMoney(Config.PayoutAccount, amount, 'parking-meter-loot') then
        SetCooldown(key)
        LogAttempt(src, key, true, amount)
        Notify(src, ('You pry the meter open and pocket $%d in loose change!'):format(amount), 'success')
    else
        Notify(src, 'Failed to process the payout.', 'error')
    end
end)

RegisterNetEvent('meters:server:requestSync', function()
    local src = source
    local now, remaining = os.time(), {}
    for key, expiry in pairs(cooldowns) do
        local secs = expiry - now
        if secs > 0 then remaining[key] = secs end
    end
    TriggerClientEvent('meters:client:fullSync', src, remaining)
end)

AddEventHandler('playerDropped', function()
    local src = source
    ReleaseAttempt(src)
    lastAttempt[src] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        SaveCooldowns()
    end
end)

LoadCooldowns()

-- ============================================================================
--  EXPORTS
-- ============================================================================
exports('GetMeterCooldowns', function()
    return cooldowns
end)

exports('ClearMeterCooldown', function(key)
    if cooldowns[key] then
        ClearCooldown(key)
        return true
    end
    return false
end)
