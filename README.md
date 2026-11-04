# BPCrime

A FiveM resource for QBCore servers where players can pry open parking meters with a lockpick using a Tumbler-style minigame and collect loose change.


https://github.com/user-attachments/assets/42a8aa9d-23c8-4abe-a03b-3e92a849560a

## Features

- Lockpick any parking meter prop (`prop_parknmeter_01` / `prop_parknmeter_02`) using the qb-target menu.
- Tumbler minigame with a rotating dial, timed rounds and configurable difficulty.
- Failed attempts can consume a lockpick (toggleable).
- Random cash payout on success, with a coin burst effect.
- Per-meter cooldown, optionally saved to disk so it survives restarts.
- Server-side validation: payouts, item removal, distance and cooldowns are all handled on the server.

## Requirements

- [qb-core](https://github.com/qbcore-framework/qb-core)
- [qb-target](https://github.com/qbcore-framework/qb-target)
- A qb-inventory compatible inventory with a `lockpick` item

## Configuration

All settings live in `config.lua`. Some useful ones:

| Option | Default | Description |
| --- | --- | --- |
| `Config.MeterModels` | `prop_parknmeter_01`, `prop_parknmeter_02` | Prop models that can be lockpicked |
| `Config.LockpickItem` | `'lockpick'` | Item required to start an attempt |
| `Config.BreakOnFail` | `true` | Remove a lockpick when the minigame is lost |
| `Config.Picks` | `3` | Retries before the lock wins |
| `Config.LockpickRounds` | 10 rounds | Time allowed per round (fewer or shorter rounds = harder) |
| `Config.PayoutMin` / `Config.PayoutMax` | `25` / `200` | Cash payout range |
| `Config.PayoutAccount` | `'cash'` | Account the payout is added to |
| `Config.CooldownMinutes` | `10` | How long a meter stays empty after being looted |
| `Config.PersistCooldowns` | `true` | Save cooldowns to `cooldowns.json` |
| `Config.InteractDistance` | `2.0` | Distance at which the qb-target option appears |
| `Config.ItemBoxEvent` | `'qb-inventory:client:ItemBox'` | Change to `'inventory:client:ItemBox'` for older qb-inventory |

## Exports

For other resources to interact with cooldowns:

```lua
-- Returns the table of active cooldowns (meter key -> expiry timestamp)
local cooldowns = exports['BPCrime']:GetMeterCooldowns()

-- Clears the cooldown on a specific meter, returns true if one existed
local cleared = exports['BPCrime']:ClearMeterCooldown(key)
```

## Credits

Created by CBaraUK.

## License

Add your license here (e.g. MIT).
