--[[
    BPCrime - client.lua

    Minigame: the Tumbler lockpick (NUI, html/index.html). The player stays
    frozen and plays the lockpick anim while the dial runs. The client only
    renders and reports the result; the server decides payouts, item loss
    and cooldowns.

    modelNames is built SYNCHRONOUSLY at file load (not in a thread), and
    qb-target is registered with a single AddTargetModel call taking the
    whole Config.MeterModels table.
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- Local state -----------------------------------------------------------------
local modelNames      = {}
local cooldowns       = {}

local isBusy          = false  -- an attempt is pending on the server or running
local activeMeter     = nil    -- { key, coords } for the current attempt
local nuiOpen         = false
local lockpickSoundId = nil
local spawnedProps    = {}

for _, name in ipairs(Config.MeterModels) do
    modelNames[joaat(name)] = name
end

-- Generic helpers ---------------------------------------------------------------

local function Notify(msg, ntype)
    QBCore.Functions.Notify(msg, ntype)
end

local function GetMeterInfo(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    local name = modelNames[GetEntityModel(entity)]
    if not name then return nil end

    local c = GetEntityCoords(entity)
    local key = ('%s@%.1f_%.1f_%.1f'):format(name, c.x, c.y, c.z)
    return key, c
end

local function IsLooted(key)
    return cooldowns[key] and cooldowns[key] > GetGameTimer()
end

local function MinutesLeft(key)
    local ms = cooldowns[key] - GetGameTimer()
    return math.max(1, math.ceil(ms / 60000))
end

local function loadDict(dict)
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do
        Wait(10)
    end
end

-- ============================================================================
--  COIN BURST (cosmetic, on success)
-- ============================================================================
local function DeleteSpawnedProps()
    for i = #spawnedProps, 1, -1 do
        local prop = spawnedProps[i]
        if DoesEntityExist(prop) then
            SetEntityAsMissionEntity(prop, true, true)
            DeleteEntity(prop)
        end
        spawnedProps[i] = nil
    end
end

local function CoinBurst(coords)
    if not Config.CoinEffect.Enabled then return end

    CreateThread(function()
        local model = joaat(Config.CoinEffect.Model)
        RequestModel(model)
        local deadline = GetGameTimer() + 2000
        while not HasModelLoaded(model) and GetGameTimer() < deadline do
            Wait(10)
        end
        if not HasModelLoaded(model) then return end

        PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)

        for _ = 1, Config.CoinEffect.Count do
            local ang = math.random() * math.pi * 2.0
            local spd = 0.25 + math.random() * 0.75

            local prop = CreateObjectNoOffset(
                model,
                coords.x + (math.random() - 0.5) * 0.08,
                coords.y + (math.random() - 0.5) * 0.08,
                coords.z + 0.7,
                Config.CoinEffect.Networked, false, false)

            if prop and prop ~= 0 then
                SetEntityRotation(prop, math.random() * 360.0, math.random() * 90.0, math.random() * 360.0, 2, false)
                ActivatePhysics(prop)
                SetEntityVelocity(prop, math.cos(ang) * spd, math.sin(ang) * spd, 1.2 + math.random() * 1.2)
                spawnedProps[#spawnedProps + 1] = prop
            end

            Wait(Config.CoinEffect.BurstDelay)
        end

        SetModelAsNoLongerNeeded(model)
        Wait(Config.CoinEffect.Lifetime)
        DeleteSpawnedProps()
    end)
end

-- ============================================================================
--  LOCKPICK AUDIO (plays from the meter)
-- ============================================================================
local function playLockpickLoop(coords)
    local cfg = Config.LockpickSound and Config.LockpickSound.loop
    if not cfg or not cfg.name then return end

    if lockpickSoundId then
        StopSound(lockpickSoundId)
        ReleaseSoundId(lockpickSoundId)
    end

    lockpickSoundId = GetSoundId()
    PlaySoundFromCoord(lockpickSoundId, cfg.name, coords.x, coords.y, coords.z,
        cfg.set or nil, true, cfg.range or 5.0, false)
end

local function stopLockpickLoop()
    if not lockpickSoundId then return end
    StopSound(lockpickSoundId)
    ReleaseSoundId(lockpickSoundId)
    lockpickSoundId = nil
end

local function playLockpickSting(which, coords)
    local cfg = Config.LockpickSound and Config.LockpickSound[which]
    if not cfg or not cfg.name then return end

    PlaySoundFromCoord(GetSoundId(), cfg.name, coords.x, coords.y, coords.z,
        cfg.set or nil, false, cfg.range or 5.0, false)
end

-- ============================================================================
--  TUMBLER (NUI)
-- ============================================================================
local endAttempt   -- forward declaration, defined after stopTumbler

local function startTumbler(coords)
    nuiOpen = true

    local ped     = PlayerPedId()
    local heading = GetEntityHeading(ped)
    local a       = Config.LockpickAnim

    SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true)
    FreezeEntityPosition(ped, true)

    loadDict(a.dict)
    TaskPlayAnim(ped, a.dict, a.anim, 8.0, -8.0, -1, a.flag or 1, 0, false, false, false)

    -- Hold the player in place and keep the anim looping for the whole minigame.
    CreateThread(function()
        while nuiOpen do
            if IsEntityDead(ped) then
                endAttempt(false, true)
                break
            end
            SetEntityHeading(ped, heading)
            if not IsEntityPlayingAnim(ped, a.dict, a.anim, 3) then
                TaskPlayAnim(ped, a.dict, a.anim, 8.0, -8.0, -1, a.flag or 1, 0, false, false, false)
            end
            Wait(0)
        end
    end)

    -- Float the dial over the meter: push its screen position to the NUI
    -- whenever it moves, and hide it while the meter is off-screen.
    CreateThread(function()
        local above = coords + vector3(0.0, 0.0, Config.TumblerOffsetZ)
        local lastOn, lastX, lastY
        while nuiOpen do
            local onScreen, sx, sy = GetScreenCoordFromWorldCoord(above.x, above.y, above.z)
            if onScreen ~= lastOn or (onScreen and (sx ~= lastX or sy ~= lastY)) then
                lastOn, lastX, lastY = onScreen, sx, sy
                SendNUIMessage({ action = 'pos', visible = onScreen, x = sx, y = sy })
            end
            Wait(0)
        end
    end)

    playLockpickLoop(coords)

    SetNuiFocus(true, false)
    SendNUIMessage({
        action = 'open',
        picks  = Config.Picks,
        rounds = Config.LockpickRounds,
    })
end

local function stopTumbler()
    if not nuiOpen then return end
    nuiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    stopLockpickLoop()
    ClearPedTasks(PlayerPedId())
    FreezeEntityPosition(PlayerPedId(), false)
end

-- Ends the current attempt and reports it to the server exactly once.
endAttempt = function(success, cancelled)
    local attempt = activeMeter
    activeMeter = nil
    stopTumbler()

    if attempt then
        playLockpickSting(success and 'success' or 'fail', attempt.coords)
        if success then CoinBurst(attempt.coords) end
        TriggerServerEvent('meters:server:finishAttempt', attempt.key, success, cancelled)
    end
    isBusy = false
end

RegisterNUICallback('result', function(data, cb)
    cb('ok')
    endAttempt(data.success == true, data.cancelled == true)
end)

-- ============================================================================
--  INTERACTION
-- ============================================================================
local function AttemptBreak(entity)
    if isBusy then return end

    local key, coords = GetMeterInfo(entity)
    if not key or not coords then return end

    if IsLooted(key) then
        Notify(('This meter has already been looted. Try again in ~%d minute(s).'):format(MinutesLeft(key)), 'error')
        return
    end

    isBusy      = true
    activeMeter = { key = key, coords = coords }

    TriggerServerEvent('meters:server:startAttempt', NetworkGetNetworkIdFromEntity(entity), key)

    -- Safety net: if the server never answers, free the client.
    SetTimeout((Config.AttemptTimeout + 5) * 1000, function()
        if isBusy and not nuiOpen then
            activeMeter = nil
            isBusy = false
        end
    end)
end

RegisterNetEvent('meters:client:attemptRejected', function(reason)
    activeMeter = nil
    isBusy = false
    Notify(reason or 'You cannot do that right now.', 'error')
end)

RegisterNetEvent('meters:client:attemptAccepted', function(key)
    if not activeMeter or activeMeter.key ~= key then return end
    startTumbler(activeMeter.coords)
end)

-- ============================================================================
--  COOLDOWN SYNC
-- ============================================================================
RegisterNetEvent('meters:client:fullSync', function(remaining)
    cooldowns = {}
    for key, secs in pairs(remaining) do
        if secs > 0 then
            cooldowns[key] = GetGameTimer() + (secs * 1000)
        end
    end
end)

RegisterNetEvent('meters:client:setCooldown', function(key, secs)
    cooldowns[key] = GetGameTimer() + (secs * 1000)
end)

RegisterNetEvent('meters:client:clearCooldown', function(key)
    cooldowns[key] = nil
end)

-- ============================================================================
--  qb-target — single AddTargetModel call
-- ============================================================================
CreateThread(function()
    exports['qb-target']:AddTargetModel(Config.MeterModels, {
        options = {
            {
                icon = 'fas fa-screwdriver-wrench',
                label = 'Lockpick Parking Meter',
                item = Config.LockpickItem,
                canInteract = function(entity)
                    local key = GetMeterInfo(entity)
                    return key ~= nil and not IsLooted(key)
                end,
                action = function(entity)
                    AttemptBreak(entity)
                end,
            },
            {
                icon = 'fas fa-clock',
                label = 'Already Looted',
                canInteract = function(entity)
                    local key = GetMeterInfo(entity)
                    return key ~= nil and IsLooted(key)
                end,
                action = function(entity)
                    local key = GetMeterInfo(entity)
                    if key then
                        Notify(('This meter was emptied recently. Come back in ~%d minute(s).'):format(MinutesLeft(key)), 'error')
                    end
                end,
            },
        },
        distance = Config.InteractDistance,
    })
end)

-- Cleanup on resource stop -------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    stopTumbler()
    DeleteSpawnedProps()
    exports['qb-target']:RemoveTargetModel(Config.MeterModels)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('meters:server:requestSync')
end)

CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do Wait(1000) end
    TriggerServerEvent('meters:server:requestSync')
end)
