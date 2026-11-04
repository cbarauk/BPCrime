Config = Config or {}

-- ============================================================================
--  METER MODELS
--  Every prop of these models on the map is interactable.
-- ============================================================================
Config.MeterModels = {
    'prop_parknmeter_01',
    'prop_parknmeter_02',
}

-- ============================================================================
--  LOCKPICK (Tumbler minigame)
--  Needs a lockpick in the inventory. A lost minigame can consume it.
-- ============================================================================
Config.LockpickItem   = 'lockpick'
Config.BreakOnFail    = true        -- remove 1 lockpick when the minigame is lost (not when cancelled)
Config.Picks          = 3           -- in-minigame retries before the lock wins
Config.ItemBoxEvent   = 'qb-inventory:client:ItemBox'  -- older qb-inventory: 'inventory:client:ItemBox'
Config.TumblerOffsetZ = 1.4         -- metres above the meter's origin where the dial floats

-- One entry per pin, in order. `time` is the seconds you get to hit the key.
Config.LockpickRounds = {
    { time = 3.0 },
    { time = 2.8 },
    { time = 2.6 },
    { time = 2.4 },
    { time = 2.2 },
    { time = 2.0 },
    { time = 1.8 },
    { time = 1.6 },
    { time = 1.4 },
    { time = 1.2 },
}

-- Lockpick animation. Must be stationary, loopable, full-body.
-- Keep flag = 1 (loop, full body); 49 lets the lower body drift.
Config.LockpickAnim = {
    dict = 'amb@prop_human_parking_meter@male@idle_a',
    anim = 'idle_a',
    flag = 1,
}

-- Lockpick audio. Plays from the meter's coords. Set any block to nil (or name = nil) to disable it.
Config.LockpickSound = {
    loop = {
        name  = 'Beep_02',
        set   = 'DLC_HEIST_HACKING_SNAKE_SOUNDS',
        range = 5.0,
    },
    success = {
        name  = 'Hack_Success',
        set   = 'DLC_HEIST_HACKING_SNAKE_SOUNDS',
        range = 6.0,
    },
    fail = {
        name  = 'Hack_Fail',
        set   = 'DLC_HEIST_HACKING_SNAKE_SOUNDS',
        range = 6.0,
    },
}

-- ============================================================================
--  PAYOUT
-- ============================================================================
Config.PayoutAccount = 'cash'
Config.PayoutMin     = 25
Config.PayoutMax     = 200

-- ============================================================================
--  COOLDOWN
-- ============================================================================
Config.CooldownMinutes  = 10
Config.PersistCooldowns = true

-- ============================================================================
--  INTERACTION
-- ============================================================================
Config.InteractDistance = 2.0

-- ============================================================================
--  COIN BURST (on success)
-- ============================================================================
Config.CoinEffect = {
    Enabled    = true,
    Model      = 'vw_prop_vw_coin_01a',
    Count      = 50,
    Networked  = false,
    BurstDelay = 45,
    Lifetime   = 4000,
}

-- ============================================================================
--  ANTI-ABUSE
-- ============================================================================
local function totalRoundTime()
    local t = 0
    for _, r in ipairs(Config.LockpickRounds) do t = t + r.time end
    return t
end

-- Max time an attempt may stay open: all rounds plus a grace period.
Config.AttemptTimeout      = math.ceil(totalRoundTime()) + 30
Config.AttemptDelay        = 5
Config.ServerDistanceGrace = 0.5
