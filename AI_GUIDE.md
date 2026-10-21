# AI_GUIDE.md: Aura Blade RNG (Roblox)

> Put this file in your project root. Rename or copy it to `CLAUDE.md` (Claude Code) or `AGENTS.md` (Codex / Cursor), or paste it at the start of a chat. Keep `docs/GDD.md` (the game design document) next to it.

## 1. What we're building

**Aura Blade RNG** is a Roblox RNG collector / clicker game. The player rolls Dice to pull Swords, equips one to tap for Gold, puts backup Swords on plot pedestals for passive income, upgrades them, and Rebirths.

**Source of truth:** `docs/GDD.md`. If this guide and the GDD disagree, ask me. Never invent numbers; take them from the GDD or from `Config` modules.

## 2. MVP scope (build only this unless I say otherwise)

In: tap to earn Gold, crits, Fever, Auto-Tap, Dice rolling (Luck), Swords, equip, Dice Merchant, plot pedestals (passive and offline Gold), personal target dummy, Grades, Enchants, Hilt Blessings, Rebirth, Dummy Trials, server events, gamepasses.

Out (do NOT build): Relic Accessories (removed), splash damage (removed, there is only ever one target), wave or knight combat (replaced by single-dummy Trials), fancy cutscenes. Use simple placeholder effects for auras until I ask for polish.

**Dummy Trials:** one dummy per floor, 30-second timer, tap or Auto-Tap, break its HP bar to clear the floor, every 5th floor is a boss dummy, pedestal swords give +5% tap damage each. Rewards are Gems, Enchant Reroll Tokens, and Luck Potions only.

## 3. Hard rules (never break these)

1. **The server is the authority.** The client only sends intent ("I tapped", "I want to roll", "buy Dice 3"). The server decides Gold earned, roll results, crits, costs, and rewards. Never trust any number sent from the client.
2. **Validate every RemoteEvent / RemoteFunction** on the server: check argument types, check the player can afford it or owns it, and rate-limit it (taps and rolls especially). Reject bad input silently.
3. **Data-driven design.** All content (Dice, Swords, Grades, Enchants, Blessings, Rebirths, Trials, events) lives in ModuleScripts under `ReplicatedStorage/Config`. Gameplay code reads from these. Never hardcode a sword's stats inside logic.
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
  Config/        -- Dice, Swords, Grades, Enchants, Blessings, Rebirths, Trials, Events
  Shared/        -- NumberFormat, WeightedRandom, small shared helpers
  Remotes/       -- RemoteEvents and RemoteFunctions
ServerScriptService/
  Services/      -- DataService, TapService, RollService, PlotService, RebirthService, TrialService, EventService
  Main (Script)  -- starts all services
StarterPlayer/
  StarterPlayerScripts/
    Controllers/ -- UI and input controllers
StarterGui/      -- ScreenGuis
```

If you want to change this structure, ask me first.

## 6. Game math (from the GDD, implement exactly)

- **Luck:** `Total Luck = Dice Base Luck × Rebirth Luck × Enchant Luck × Potion/Server boosts`
- **Roll odds:** `Effective Odds = max(1, Sword Base Odds / Total Luck)`
- **Gold per tap:** `Base Damage × Grade × Enchant × Rebirth × Crit`
- **Crit:** 10% base chance, 2.5× Gold.
- **Fever:** each tap adds 1 point to a 100-point meter. At 100 it triggers a 15-second mode with 2× swing speed, 100% crit, and +50% Luck.
- **Pedestal passive income:** each pedestal Sword gives 50% of its Gold-per-tap value every second, including offline time.

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
