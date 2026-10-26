# AI_GUIDE.md: Aura Blade RNG (Roblox)

> Put this file in your project root. Rename or copy it to `CLAUDE.md` (Claude Code) or `AGENTS.md` (Codex / Cursor), or paste it at the start of a chat. Keep `docs/GDD.md` (the game design document) next to it.

## 1. What we're building

**Aura Blade RNG** is a Roblox RNG collector / clicker game. The player rolls Dice to pull Swords, equips one to tap for Gold, puts backup Swords on plot pedestals for passive income, upgrades them, and Rebirths.

**Source of truth:** `docs/GDD.md`. If this guide and the GDD disagree, ask me. Never invent numbers; take them from the GDD or from `Config` modules.

## 2. MVP scope (build only this unless I say otherwise)

In: tap to earn Gold, crits, Fever, Auto-Tap, Dice rolling (global cooldown, Luck ladder), Swords, equip & Equip Best, sword Lock, stations (Plaza: Dice Merchant, Sell stall, Shop [Robux, later]; near Trials: Master Appraiser, Enchanter, Runesmith), Auto Grade Roll, plot pedestals (cap 11: 4 start, Rebirths 3/5/7/9/10 +1, VIP Forge +2; passive and offline Gold), personal target dummy, Grades (1 Gem per roll), Enchants, Hilt Blessings, Rebirth (resets Gold only; Dice, swords, Gems, Tokens, Potions, pedestal slots kept; costs/multipliers to be verified against Anime Dice), Dummy Trials, server events, gamepasses, economy simulation.

Out (do NOT build): Relic Accessories (removed), splash damage (removed, there is only ever one target), wave or knight combat (replaced by single-dummy Trials), fancy cutscenes. Use simple placeholder effects for auras until I ask for polish.

**Dummy Trials:** one dummy per floor, 30-second timer, tap or Auto-Tap, break its HP bar to clear the floor, every 5th floor is a boss dummy, pedestal swords give +5% tap damage each. Rewards are Gems, Enchant Reroll Tokens, and Luck Potions only.

## 3. Hard rules (never break these)

1. **The server is the authority.** The client only sends intent ("I tapped", "I want to roll", "buy Dice 3"). The server decides Gold earned, roll results, crits, costs, and rewards. Never trust any number sent from the client.
2. **Validate every RemoteEvent / RemoteFunction** on the server: check argument types, check the player can afford it or owns it, and rate-limit it (taps and rolls especially). Reject bad input silently.
3. **Data-driven design.** All content (Dice, Swords, Grades, Enchants, Blessings, Rebirths, Trials, events) lives in ModuleScripts under `ReplicatedStorage/Config`. Gameplay code reads from these. Never hardcode a sword's stats inside logic.
   - *Note:* The temporary `test_sword` fallback in `TapService` and entry in `Config/Swords` must be removed when the real sword inventory/equip feature is built.
4. **Save data safely.** Use DataStore (or ProfileStore) with `pcall`, retries, and session locking. Save on leave, on a timer, and on `BindToClose`. Never wipe a profile if loading fails; kick the player with a message instead.
5. **One feature per task.** Don't refactor or change unrelated systems. If you think something else needs changing, tell me first.
6. **Plan before code.** For any new feature, give a short plan (files you'll touch, remotes you'll add, data fields you'll add) and wait for my OK.

## 4. Code standards

- Language: **Luau**, start every script with `--!strict` where practical. Add type annotations on module APIs.
- Use modern APIs: `task.wait`, `task.spawn`, `task.delay`. Do **not** use `wait()`, `spawn()`, or `delay()`.
- Use ModuleScripts for logic. Keep Scripts and LocalScripts thin (just wiring).
- No global variables. Use `local` and return a table from modules.
- Use `CollectionService` tags or named folders to find pedestals, dummies, and other world objects. Don't use brittle paths like `workspace.Model.Part.Part2`.
- Handle `Players.PlayerAdded` **and** players already in the game, and clean up on `PlayerRemoving`.
- Small functions, clear names, and a short comment explaining *why* for any non-obvious logic.
- UI must work on **mobile first** (tap input, `UIScale` or scale-based sizing, no tiny buttons). Most Roblox players are on phones.

## 5. Project structure (Script Sync folder layout)

```
ReplicatedStorage/
  Config/        -- Assets, DataTemplate, Dice, Game, Grades, Swords; Enchants/Blessings/Rebirths/Trials/Events (planned)
  Shared/        -- NumberFormat, Remotes, Theme; WeightedRandom (planned)
    UI/          -- InventoryUI, MerchantUI, OfflineIncomePopup, SwordSelectorPopup
      Components/-- Button, Panel, Popup
      HUD/       -- MainHUD
ServerScriptService/
  Main (Script)  -- starts all services
  PlayerActionLock (ModuleScript) -- lives at ServerScriptService/PlayerActionLock (not in Services/)
  EconSim (ModuleScript) -- lives at ServerScriptService/EconSim (not in Services/)
  Services/      -- DataService, DevCommands, InventoryService (Equip, Equip Best, Sell; Sell All [planned], Lock [planned]), MerchantService, PlotService, RollService, TapService; RebirthService (planned), TrialService (planned), EventService (planned)
StarterPlayer/
  StarterPlayerScripts/
    Controllers/ -- DevFeedback, HUDController, InventoryController, MerchantController, PlotController, RollController, TapController, TargetDummyController
Workspace/       -- World map & interaction zones: Personal Plots (Dummies, Pedestals), Stations (Plaza: Dice Merchant; Sell Stall [planned], Shop [planned]; Near Trials: Master Appraiser [planned], Enchanter [planned], Runesmith [planned])
Tools/Scripts/   -- Economy simulation & testing scripts (planned)
```

**Script Sync Rule:** Only create folders inside folders that are already synced (`Config`, `Shared`, `Services`, `Controllers`). If you ever need a new top-level folder, ask the user first so they can link it with Script Sync.
If you want to change this structure, ask me first.

## 6. Game math (from the GDD, implement exactly)

- **Luck:** `Total Luck = Dice Base Luck × Rebirth Luck × Enchant Luck × Potion/Server boosts`
- **Roll odds & Cooldown:** `Effective Odds = max(1, Sword Base Odds / Total Luck)`. Roll cooldown is **global** (`Config/Game.Roll.Cooldown`, baseline 3.0s placeholder), not per Dice.
- **Dice Ladder:** 29-tier progression table (Basic Dice up to Zenith Dice). Players can purchase any tier with Gold in any order and switch/equip any owned Dice tier at will.
- **Gold per tap:** `Base Damage × Grade × Enchant × Rebirth × Crit`
- **Crit:** 10% base chance, 2.5× Gold.
- **Fever:** each tap adds 1 point to a 100-point meter. At 100 it triggers a 15-second mode with 2× swing speed, 100% crit, and +50% Luck.
- **Pedestal passive income:** each pedestal Sword gives 50% of its Gold-per-tap value every second, including offline time (capped at 8 hours). Hard cap of **11 pedestals** per plot (4 starting, +1 each at Rebirths 3, 5, 7, 9, and 10, and +2 from VIP Forge). Each plot physically has 11 pedestal models, locked until earned.
- **Grades & Auto Grade Roll:** Rolled with Gems at Master Appraiser (near Trials), costing **1 Gem per roll**. A roll replaces the sword's Grade (one Grade per sword). Free **Auto Grade Roll**: player picks a target Grade; server rolls until result is target or better, Gems run out, or player stops; never starts if sword already has target or better.
- **Selling & Lock:** Single sell and Sell All **never touch equipped or placed swords**. Every other sword sells unless the player locked it. Sword **Lock** is a boolean flag on each sword toggled in the inventory, preventing single sell and causing Sell All to skip it. Sell All confirmation dialog shows sword count and total Gold payout, and warns how many of those swords have a Grade or Enchant.
- **Rebirth:** Rebirth resets **Gold only**. Dice (`DiceTier` and `OwnedDice`), swords, Gems, Tokens, Potions, and pedestal slots are **permanently kept**. Rebirth multipliers and costs are marked *to be verified against Anime Dice* until confirmed. Old text saying Rebirth resets Dice is obsolete and removed.

When the GDD has a table, copy it into the matching Config module faithfully.

## 7. Big numbers

Costs reach Septillion scale. Use normal Luau numbers (doubles). Always display values through `Shared/NumberFormat` (for example `5e24` becomes `5Sp`). Never display raw floats in the UI. Round Gold to whole numbers when saving.

## 8. How to work with me

- I'm a student building this with AI help, so explain **why** you chose an approach in a few sentences, not just what you did. Keep explanations short and direct.
- After each feature, give me a **test checklist** I can follow in Studio (what to click, what should happen, what should *not* happen).
- If something is ambiguous in the GDD, ask one clear question instead of guessing.
- If you use Studio MCP, only touch what the task needs. Don't delete or rewrite existing objects without telling me.
- Remind me to `git commit` when a feature works.

## 9. Definition of done (every feature)

- [ ] Works in a Studio playtest with 1 player and with 2+ players (Start Server mode)
- [ ] Server validates everything, with no client-trusted values
- [ ] Data saves and loads correctly (leave and rejoin to test)
- [ ] Works with touch input and a small screen
- [ ] No errors or warnings in Output
- [ ] Numbers come from Config, not hardcoded
- [ ] I have a test checklist and a commit message

## 10. Known open issues

- **Dual Wielding:** Needs two equipped swords, but the codebase and player data model currently assume a single `EquippedSword`.
- **Rebirth Multipliers & Costs:** Multipliers and Gold costs in Config and GDD are unverified placeholders until confirmed against Anime Dice.
- **Sword List Content:** The sword list in `Config/Swords` is too short for the high-Luck dice (players with top-tier dice will roll beyond the highest-rarity swords currently defined).
