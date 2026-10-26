# 🚀 Aura Blade RNG — Launch Checklist

This checklist tracks critical pre-launch actions and verification items required before deploying to public production.

---

## 1. Studio-Only Dev Commands Removal / Disabling

The following commands are implemented in `src/ServerScriptService/Services/DevCommands.luau` for Studio playtesting and debugging. **They must be deleted or disabled before public launch:**

- [ ] **/dice `<tier>`**: Sets owned Dice tiers 1..tier and equips `tier` for instant high-tier progression testing.
- [ ] **/resetdice**: Resets `OwnedDice` to only Tier 1 (`Basic Dice`) and equips Tier 1.
- [ ] **/gold `<amount>` / /gold +`<amount>`**: Sets or adds arbitrary Gold amounts.
- [ ] **/fever [amount]**: Instantly triggers Fever Mode or sets Fever meter points.
- [ ] **/rolltest [count]**: Runs high-speed roll probability simulations and prints statistics to Output.
- [ ] **/clearswords**: Clears all owned swords, unequips active weapon, and empties pedestals.
- [ ] **/place `<slot>` `<inventoryIndex>`**: Places sword from inventory index onto target pedestal slot.
- [ ] **/unplace `<slot>`**: Removes sword from target pedestal slot.
- [ ] **/fakeoffline [now] `<hours>`**: Stages or immediately simulates `<hours>` of offline income.
- [ ] **/equipbest**: Automatically equips best damage sword and places top remaining swords onto pedestals.
- [ ] **/econ [extended] [expected] [scope N] [goldMult] [luckMult] [critFeverFactor]**: Runs comprehensive economy and progression simulation across all 29 Dice tiers, or calculates expected Grade/Enchant multipliers.

> **Production Safeguard:** Verify that `DevCommands.luau` and `ServerScriptService/EconSim.luau` include Studio-only gating or are removed before production builds.

---

## 2. Server Authority & Anti-Exploit

- [ ] All Remotes validate argument types and ranges on the server (`BuyDiceTier`, `EquipSword`, `SellSword`, `Tap`, `Roll`).
- [ ] Client cannot spoof Gold, Luck, or Dice tiers.
- [ ] Per-player purchase lock and rate-limiting prevents race conditions and replay spam.

---

## 3. Data Persistence & Economy

- [ ] Enable Studio API Access & DataStore service in Game Settings.
- [ ] Verify ProfileStore session locking and shutdown save (`BindToClose`).
- [ ] Test player rejoin to confirm `DiceTier`, `Gold`, and `OwnedSwords` persist across sessions.
- [ ] Verify offline Gold formula and timestamps.

---

## 4. UI & Mobile Responsiveness

- [ ] Test HUD on phone emulator (iPhone / Android aspect ratios) via Studio Device View.
- [ ] Ensure buttons meet minimum touch target sizes (at least 44x44px).
- [ ] Confirm modal close buttons and scrims release touch focus so fullscreen `TapArea` remains responsive.
