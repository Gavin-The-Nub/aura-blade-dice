# ⚔️ Aura Blade RNG — Game Design Document (GDD)

**Genre:** RNG Collector / Clicker & Plot Simulator Hybrid  
**Core Concept:** Roll through a 29-tier Dice progression ladder to pull rare Swords that radiate full-body Auras around both the blade and the player. Tap to swing your equipped Sword to earn Gold, place backup Swords on your plot for passive income, and scale your stats through Grades, Blade Enchants, and Rebirths.

---

## 1. The Core Gameplay Loop

1. **Roll the Sword Dice:** Players roll their equipped Dice (manually or via Auto-Roll) to pull Swords based on weighted probability odds.
2. **Equip & Radiate:** Equip your strongest Sword into your main hand. Every Sword contains a built-in Aura that immediately wraps both the weapon and the player's avatar in custom VFX, idle animations, and lighting while setting base **Damage**.
3. **Tap to Slash & Earn Gold:** Every click/tap swings your Sword. Each swing unleashes custom slash trails and awards **Gold** based on your Sword's Damage and active multipliers.
4. **Display & Upgrade:** Place secondary Swords onto your Plot Pedestals for passive Gold per second, buy higher-tier Dice to boost your Luck, roll Grades and Enchants onto your best blades, and Rebirth to permanently multiply your Gold and Luck.

---

## 2. Core Math, Luck & Economy Formulas

### A. Probability & Luck Formula
Every Sword has a base probability denominator ($1 \text{ in } X$). A player’s **Total Luck** directly divides that denominator on every roll:

$$\text{Total Luck} = (\text{Dice Base Luck} \times \text{Rebirth Luck Multiplier} \times \text{Enchant Luck Buffs} \times \text{Potion/Server Boosts})$$

$$\text{Effective Roll Odds} = \max\left(1, \frac{\text{Sword Base Odds}}{\text{Total Luck}}\right)$$

### B. Gold Per Tap Formula (Soft-Scaled Curve)
To ensure balanced progression across 29 tiers without allowing a single lucky early roll to skip the entire game, Sword Base Damage scales smoothly alongside multiplicative stations:

$$\text{Gold Per Tap} = \text{Sword Base Damage} \times \text{Grade Multiplier} \times \text{Enchant Multiplier} \times \text{Rebirth Multiplier} \times \text{Crit Bonus}$$

* **Critical Swings:** Base **10% Crit Chance** to deal **2.5x Gold** on a swing with a screen-shake effect.
* **Fever Bar (Overcharge):** Every tap fills 1 point of a 100-point Fever Meter. At 100/100, **Fever Mode** triggers for 15 seconds, granting **2x Swing Speed**, **100% Crit Chance**, and **+50% Total Luck**.

---

## 3. The 29-Tier Sword Dice Progression Ladder

Players spend Gold at the Dice Merchant to purchase any Dice tier and equip any owned Dice. Tiers can be bought in any order without skipping constraints. Purchasing a Dice tier automatically equips it if it is higher than the currently equipped tier. Players can freely switch between any owned Dice at any time. Each tier provides a substantial boost to base Luck (roughly $2\times$ to $2.5\times$), while Gold costs scale exponentially up through the late-game Octillions ($100\text{Oc}$).

> [!NOTE]
> **Roll Cooldown:** Dice no longer alter roll cooldown. A uniform roll cooldown is governed globally in `Config/Game.Roll.Cooldown` (baseline 3.0s placeholder). A dedicated Roll Speed upgrade will shorten it in a future progression feature.

| Tier | Dice Name | Gold Cost | Base Luck | Visual Theme |
| :--- | :--- | :--- | :--- | :--- |
| **1** | **Basic Dice** | Free | $1\times$ | Simple carved wood with iron pips |
| **2** | **Ember Dice** | $2,500$ | $5\times$ | Charred obsidian with glowing orange cracks |
| **3** | **Tide Dice** | $10,000$ | $10\times$ | Translucent ocean blue with bubble particles |
| **4** | **Verdant Dice** | $75,000$ | $20\times$ | Mossy ancient stone wrapped in vines |
| **5** | **Volt Dice** | $500,000$ | $42\times$ | Crackling yellow-blue storm core |
| **6** | **Glacier Dice** | $4\text{M}$ | $100\times$ | Frosted diamond cube emitting cold mist |
| **7** | **Magma Dice** | $30\text{M}$ | $200\times$ | Molten lava rock dripping fire |
| **8** | **Gale Dice** | $200\text{M}$ | $400\times$ | Swirling emerald wind vortex |
| **9** | **Sandstorm Dice** | $1.5\text{B}$ | $750\times$ | Golden sandstone with orbiting dust runes |
| **10** | **Phantom Dice** | $12\text{B}$ | $1,500\times$ | Ghostly purple spectral cube |
| **11** | **Bloodforged Dice** | $100\text{B}$ | $3,000\times$ | Crimson steel with floating red crystals |
| **12** | **Solaris Dice** | $750\text{B}$ | $6,000\times$ | Blazing miniature sun with solar flares |
| **13** | **Lunaris Dice** | $5\text{T}$ | $12,500\times$ | Silver crescent filigree and starlight |
| **14** | **Gravity Dice** | $37\text{T}$ | $25,000\times$ | Floating purple rings crushing inward |
| **15** | **Venomspire Dice** | $150\text{T}$ | $50,000\times$ | Neon acid green with toxic vapor |
| **16** | **Cybernetic Dice** | $1\text{Qa}$ | $100,000\times$ | Holographic wireframe with digital glitches |
| **17** | **Dragonheart Dice** | $8.5\text{Qa}$ | $200,000\times$ | Scaled ruby core pulsing like a heartbeat |
| **18** | **Runic Dice** | $100\text{Qa}$ | $400,000\times$ | Floating celestial tablets with ancient glyphs |
| **19** | **Nebula Dice** | $1\text{Qi}$ | $1\text{M}\times$ | Deep space cloud with birthing stars |
| **20** | **Chronos Dice** | $12\text{Qi}$ | $2\text{M}\times$ | Interlocking golden clockwork gears |
| **21** | **Abyssal Dice** | $150\text{Qi}$ | $5\text{M}\times$ | Dark matter cube devouring nearby light |
| **22** | **Seraphic Dice** | $1\text{Sx}$ | $10\text{M}\times$ | Six golden wings wrapped around a halo core |
| **23** | **Dimension Dice** | $15\text{Sx}$ | $25\text{M}\times$ | Shattered glass portal showing parallel worlds |
| **24** | **Singularity Dice** | $100\text{Sx}$ | $62.5\text{M}\times$ | Event horizon orb with relativistic jets |
| **25** | **Omniversal Dice** | $750\text{Sx}$ | $150\text{M}\times$ | Chromatic shifting reality cube |
| **26** | **Astral Dice** | $10\text{Sp}$ | $375\text{M}\times$ | Primordial cosmic dust and shifting stellar nebulae |
| **27** | **Eternal Dice** | $250\text{Sp}$ | $950\text{M}\times$ | Infinite starlight loops and timeless crystalline prisms |
| **28** | **Infinity Dice** | $5\text{Oc}$ | $2\text{B}\times$ | Event horizon singularities and reality distortion rings |
| **29** | **Zenith Dice** | $100\text{Oc}$ | $5\text{B}\times$ | Prismatic aura halos, crowned reality blades, and transcendent godlight |

---

## 4. Sword Rarity Tiers & Soft-Scaled Damage Curve

Instead of Base Damage scaling 1:1 with rarity odds, Swords follow a controlled power curve so upgrades, Grades, and Rebirths remain essential throughout the entire game. Each Sword coats both the blade and the player in its signature Aura.

| Rarity Tier | Odds Range | Base Damage (Gold/Tap) | Blade & Avatar Aura Visuals |
| :--- | :--- | :--- | :--- |
| **Common** | $1 \text{ in } 2$ – $1 \text{ in } 50$ | $1$ – $15$ | Subtle metallic sheen on the blade, light hilt sparks, clean white slash trail. |
| **Uncommon** | $1 \text{ in } 75$ – $1 \text{ in } 750$ | $25$ – $150$ | Elemental glow along the blade edge; faint particle wisps around the player's hands. |
| **Rare** | $1 \text{ in } 1,000$ – $1 \text{ in } 15,000$ | $250$ – $1,200$ | Elemental fire, frost, or lightning wraps the blade and swirls around the player's torso and feet. |
| **Epic** | $1 \text{ in } 20,000$ – $1 \text{ in } 250,000$ | $1,800$ – $9,500$ | Full-body energy shroud, custom levitating idle pose, glowing eyes, and rising energy pillars. |
| **Legendary** | $1 \text{ in } 500,000$ – $1 \text{ in } 10\text{M}$ | $16,000$ – $125,000$ | Expanding ground domain beneath the player's feet (magma cracks, ice glyph, shadow pool) + back wings/halos. |
| **Mythic** | $1 \text{ in } 25\text{M}$ – $1 \text{ in } 750\text{M}$ | $250,000$ – $3.5\text{M}$ | Cinematic pull cutscene. Summons a giant phantom guardian, dragon, or cosmic ring behind the player that strikes on every tap. |
| **Secret / Apex** | $1 \text{ in } 1\text{B}+$ | $10\text{M}$ – $250\text{M}+$ | Global chat announcement + server weather/skybox override for 60s. Screen-shaking reality-slash effects on every tap. |

### Sample Sword Progression Table
* **Rusty Shortsword ($1 \text{ in } 2$ | Common):** $1\text{ Base Damage}$ — Chipped iron blade with dust specks.
* **Wooden Training Blade ($1 \text{ in } 8$ | Common):** $3\text{ Base Damage}$ — Falling oak leaves on swing.
* **Iron Broadsword ($1 \text{ in } 35$ | Common):** $12\text{ Base Damage}$ — Silver metallic glint and sharp air trail.
* **Ember Wakizashi ($1 \text{ in } 150$ | Uncommon):** $45\text{ Base Damage}$ — Flickering flame edge and warm embers around the player's wrists.
* **Static Katana ($1 \text{ in } 1,200$ | Rare):** $280\text{ Base Damage}$ — Yellow lightning arcs snapping across the blade and the player's shoulders.
* **Frostbite Claymore ($1 \text{ in } 8,500$ | Rare):** $850\text{ Base Damage}$ — Swirling snowstorm aura around the avatar; shatters ice crystals on tap.
* **Cursed Blood Scythe-Blade ($1 \text{ in } 38,000$ | Epic):** $2,200\text{ Base Damage}$ — Crimson fog shroud, floating red runes, and wide blood-crescent slashes.
* **Thunderlord Greatsword ($1 \text{ in } 290,000$ | Epic):** $9,100\text{ Base Damage}$ — Levitating storm-god idle pose with thunderclouds orbiting the player's head.
* **Solar Flare Saber ($1 \text{ in } 1.5\text{M}$ | Legendary):** $32,000\text{ Base Damage}$ — Scorched magma ground domain and a blazing sun halo behind the player's back.
* **Chronos Clockwork Blade ($1 \text{ in } 8.5\text{M}$ | Legendary):** $115,000\text{ Base Damage}$ — Giant rotating Roman numeral clock beneath the player's feet; distorts time on every swing.
* **Abyssal Voidreaper ($1 \text{ in } 50\text{M}$ | Mythic):** $420,000\text{ Base Damage}$ — Summons a towering phantom grim reaper behind the player that mirrors every tap attack.
* **Celestial Dragonfang ($1 \text{ in } 450\text{M}$ | Mythic):** $2.4\text{M Base Damage}$ — Coiling astral dragon wraps around the player and breathes starfire every 5th tap.
* **Eternity: Sovereign of Blades ($1 \text{ in } 5\text{B}$ | Secret):** $28\text{M Base Damage}$ — Shattered dimension wings, custom boss music aura, and screen-wide dimensional slashes.

---

## 5. Multiplier Stations (Grades, Enchants & Blessings)

Once a player pulls a high-rarity Sword, they can bring it to three specialist stations in the plaza to roll multiplicative buffs onto that specific blade.

### A. Blade Forging / Grades (Rolled with Gems)
Players spend **Gems** at the Master Appraiser to roll a Quality Grade onto their Sword, providing a flat multiplier to its Base Damage:

| Grade | Roll Chance | Damage / Gold Multiplier | Visual Badge Color |
| :--- | :--- | :--- | :--- |
| **D** | $35.0\%$ | $1.0\times$ | Gray |
| **C** | $25.0\%$ | $1.25\times$ | White |
| **B** | $18.0\%$ | $1.5\times$ | Green |
| **A** | $12.0\%$ | $2.0\times$ | Blue |
| **S** | $6.5\%$ | $3.0\times$ | Purple |
| **SS** | $2.5\%$ | $5.0\times$ | Gold |
| **SSS** | $0.85\%$ | $8.5\times$ | Crimson |
| **Z** | $0.14\%$ | $15.0\times$ | Cyan Neon |
| **Z+** | $0.01\%$ | $30.0\times$ | Prismatic Rainbow |

### B. Sword Enchants (Rolled with Enchant Reroll Tokens)
Each Sword can hold one **Enchant**. Enchants scale the Sword's **Gold Multiplier**, **Trial/Boss Damage**, and **Swing Speed**:

| Enchant Name | Roll Chance | Gold & Damage Multiplier | Bonus Passive Effect |
| :--- | :--- | :--- | :--- |
| **Sharpness** | $40.0\%$ | $1.2\times$ | $+5\%$ Swing Speed |
| **Berserker** | $25.0\%$ | $1.6\times$ | $+10\%$ Crit Chance |
| **Vampiric** | $15.0\%$ | $2.2\times$ | $+15\%$ Fever Bar Charge Rate |
| **Executioner** | $10.0\%$ | $3.5\times$ | $+25\%$ Boss & Trial Damage |
| **Ronin** | $6.0\%$ | $6.0\times$ | $+20\%$ Swing Speed & Double Slash chance |
| **Sovereign** | $2.8\%$ | $12.0\times$ | $+35\%$ Crit Chance & $+15\%$ Base Luck |
| **Transcendent** | $1.0\%$ | $28.0\times$ | Every 3rd tap deals $3\times$ Damage |
| **Genesis** | $0.18\%$ | $75.0\times$ | $+50\%$ Swing Speed & $+50\%$ Total Luck |
| **Singularity** | $0.02\%$ | $150.0\times$ | $2\times$ All Sword Stats & Instant Fever Recovery |

### C. Hilt Blessings (Rolled with Gold)
Players can spend **Gold** at the Runesmith to roll a utility **Hilt Blessing** onto any Sword. Blessings remain active whether the Sword is held in your hand OR placed on a Plot Pedestal:
* **Fortune I / II / III:** $+5\% / +12\% / +25\%$ Global Roll Luck.
* **Greed I / II / III:** $+10\% / +25\% / +50\%$ Global Gold Earned.
* **Appraiser's Eye:** $+20\%$ Luck when rolling for **Grades**.
* **Enchanter's Soul:** $+20\%$ Luck when rolling for **Enchants**.
* **Swiftfoot:** $+15\%$ Player WalkSpeed and $+10\%$ Auto-Tap Speed.

---

## 6. Player Forge Plots (Active + Passive Hybrid)

Each server houses 6 to 8 personal **Player Forge Plots** ringing the main plaza.
* **Active Main Hand (Tap Income):** The player equips their #1 strongest Sword in their hand to actively tap and slash for full Gold value.
* **Sword Pedestals (Passive & Offline Income):** Each plot starts with **4 Sword Pedestals** (expandable up to 10 via Rebirths and Gamepasses). Players place their backup Swords onto these pedestals.
* **Passive Payout Rate:** Every Sword placed on a Plot Pedestal radiates its Aura upward and automatically generates **50% of its Gold-Per-Tap value every second** (including Offline Gold accumulation while the player is logged out).
* **Personal Plot Target Dummy:** Positioned at the front of each plot so players can slash an interactive target with damage numbers and hit-sparks right at home.

---

## 7. Rebirth System

Once a player accumulates enough Gold, they can trigger a **Rebirth** to permanently accelerate their account progression.

* **What Resets:** Current Gold balance, equipped Dice tier (`DiceTier` resets to 1 / *Basic Dice*), and all owned Dice tiers (`OwnedDice` resets back to only Tier 1 Basic Dice).
* **What Stays:** All rolled **Swords** (including Grades, Enchants, and Blessings), **Gems**, **Enchant Rerolls**, **Potions**, and **Unlocked Pedestal Slots** are permanently kept.
* **Rebirth Scaling Table (First 10 Rebirths):**

| Rebirth Level | Gold Cost | Permanent Gold Multiplier | Permanent Luck Multiplier | Bonus Reward |
| :--- | :--- | :--- | :--- | :--- |
| **Rebirth 1** | $250,000$ | $1.5\times$ | $1.25\times$ | $100\text{ Gems}$ |
| **Rebirth 2** | $5\text{M}$ | $2.25\times$ | $1.5\times$ | $150\text{ Gems}$ |
| **Rebirth 3** | $150\text{M}$ | $3.5\times$ | $2.0\times$ | $+1\text{ Plot Pedestal Slot}$ |
| **Rebirth 4** | $5\text{B}$ | $5.0\times$ | $2.5\times$ | $300\text{ Gems}$ |
| **Rebirth 5** | $250\text{B}$ | $7.5\times$ | $3.25\times$ | $+1\text{ Plot Pedestal Slot}$ |
| **Rebirth 6** | $15\text{T}$ | $11.0\times$ | $4.0\times$ | $500\text{ Gems}$ |
| **Rebirth 7** | $1\text{Qa}$ | $16.0\times$ | $5.0\times$ | $+1\text{ Plot Pedestal Slot}$ |
| **Rebirth 8** | $85\text{Qa}$ | $24.0\times$ | $6.5\times$ | $1,000\text{ Gems}$ |
| **Rebirth 9** | $7.5\text{Qi}$ | $35.0\times$ | $8.0\times$ | $+1\text{ Plot Pedestal Slot}$ |
| **Rebirth 10** | $750\text{Qi}$ | $50.0\times$ | $10.0\times$ | **Ascended Aura Title** + $+1\text{ Slot}$ |

---

## 8. Dummy Trials & Server Events (Endgame Content)

### A. Dummy Trials
Players enter tiered **Trial rooms** (*Iron Citadel*, *Crimson Pagoda*, *Void Spire*) and hit a single training dummy before a 30-second floor timer expires.
* **Gameplay:** Tap to hit, or enable **Auto-Tap**. Break the dummy's HP bar before the timer ends to clear the floor. Each floor increases the dummy's HP, and every 5th floor is a **Boss Dummy** with more HP, a unique model, and a bigger reward. Crits and Fever Mode apply as normal.
* **Pedestal Bonus:** Swords placed on Plot Pedestals add a small bonus to tap damage inside Trials (+5% per pedestal Sword).
* **Rewards:** Clearing floors drops **Gems**, **Enchant Reroll Tokens**, and **Luck Potions**, with amounts scaling by tier and floor.

### B. Global Server Weather & Mutation Events
Every 20 minutes, the server shifts into a 5-minute **Dimensional Surge Event**:
* **Blood Eclipse:** $2\times\text{ Gold}$ per tap; $10\%$ chance for any rolled Sword to gain the **Bloodforged Mutation** ($2.5\times\text{ Base Damage}$).
* **Starfall Night:** $2\times\text{ Server Roll Luck}$; $10\%$ chance for rolled Swords to gain the **Celestial Mutation** ($3.5\times\text{ Base Damage}$).
* **Golden Rush:** Giant Gold Meteor spawns in the center arena; tapping it rewards Enchant Rerolls and grants a $5\times\text{ Gold}$ buff.

---

## 9. Monetization & Gamepasses

* **Free-to-Play Baseline:** Standard **Auto-Roll**, **Auto-Tap**, and **Auto-Sell** filters are 100% free so all players can grind and AFK comfortably.
* **Premium Gamepasses:**
  * **Fast Slash ($199\text{ Robux}$):** $2\times$ Tapping/Swing speed and $2\times$ Fever Bar charge rate.
  * **Multi-Roll ($299\text{ Robux}$):** Roll 3 Dice simultaneously on every cooldown.
  * **Dual Wielding ($499\text{ Robux}$):** Hold and swing **2 Swords** in your hands at once, combining both of their Damage values and layering both Auras.
  * **Super Luck ($399\text{ Robux}$):** Permanent $2\times$ Total Luck multiplier.
  * **Ultra Luck ($799\text{ Robux}$):** Permanent $4\times$ Total Luck multiplier (stacks with Super Luck).
  * **VIP Forge ($499\text{ Robux}$):** $+50\%$ Gold earned, $+2\text{ Plot Pedestal Slots}$, and Golden Chat Tag.