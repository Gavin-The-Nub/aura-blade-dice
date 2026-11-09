# Design Spec: Backpack System & Items Tab (Swords & Items)

**Date:** 2026-11-09  
**Status:** Implemented  
**Scope:** HUD Button Redesign, Bottom-Left HUD Cleanup, and Tabbed Backpack (Swords vs. Items)

---

## 1. Overview & Motivation
Previously, the bottom bar featured a button labeled `"Swords"`, and the lower-left HUD showed both the player's Gold and a row with Gems and Tickets.
To align with the target UI (reference screenshot):
1. The bottom-left HUD now displays only the primary money balance (`$0`).
2. The bottom bar button is changed from `"Swords"` to `"Backpack"` (🎒).
3. The popup window is renamed to `"Backpack"` and features a docked vertical tab strip on the left with two choices:
   - **Swords:** Weapon inventory, capacity, equip best, auto-sell filter chips, and sword inspector.
   - **Items:** Collectible/stackable items inventory featuring **Gems** (💎) and **Enchant Tickets** (🎟️), with quantities displayed in bottom-right badges (`x1.6k`, `x5`) and an item detail inspector.

---

## 2. Architecture & Components

```
ScreenGui
 ├── MainHUD
 │    ├── Bottom-Left: GoldAmount ("$0") [CurrencyRow removed]
 │    └── BottomBar: BackpackButton ("Backpack", 🎒) -> toggles InventoryController.Toggle()
 └── AuraBladeInventoryGui (Backpack)
      └── Popup: "Backpack"
           ├── TabStrip (Left Column ~68px)
           │    ├── SwordsTabButton (🗡️ Swords)
           │    └── ItemsTabButton (🎒 Items)
           └── MainContainer
                ├── SwordsView (Visible when Swords tab active)
                │    ├── TopBar (Capacity 0/50, EQUIP BEST, Auto-sell chips)
                │    └── Body (Swords Grid 63% + Sword Inspector 35%)
                ├── ItemsView (Visible when Items tab active)
                │    ├── TopBar ("ITEMS & CURRENCIES")
                │    └── Body
                │         ├── ItemsGridPanel (63% Scrolling Grid with 💎 Gems & 🎟️ Tickets)
                │         └── ItemsInspectorPanel (35% Item preview, count, desc & station tips)
                └── ToastFrame (Cross-tab feedback notification)
```

---

## 3. Data Flow & Syncing
- `InventoryController`:
  - Listens to `DataChanged` for `"Gems"` and `"EnchantTokens"`, syncing in real-time.
  - Queries initial `Gems` and `EnchantTokens` from `GetInitialData`.
  - Forwards values to `InventoryUI:SetItemData(gems, tokens)`.
- `MainHUD`:
  - Retains internal state for `UpdateGems` and `UpdateTokens` without rendering them on the lower-left screen.

---

## 4. Test Checklist
- [x] **HUD Bottom-Left:** Only the Gold amount (`$0`) is visible; no Gems or Tickets clutter the bottom-left corner.
- [x] **Bottom Bar:** The first action button is labeled `"Backpack"` with a backpack icon (🎒).
- [x] **Backpack Window Tabs:**
  - Clicking `"Backpack"` opens the window titled `"Backpack"`.
  - The left sidebar has two vertical tabs: `Swords` (🗡️) and `Items` (🎒).
- [x] **Swords Tab:** Shows all swords, capacity (`0/50`), `EQUIP BEST`, auto-sell filters, and sword inspector.
- [x] **Items Tab:**
  - Clicking `Items` switches views cleanly.
  - Displays **Gems** card (💎) with count `x...` and cyan border.
  - Displays **Tickets** card (🎟️) with count `x...` and purple border.
  - Clicking an item selects it, highlights its border with gold, and updates the right-side Item Inspector with its name, icon, owned amount, description, and station tip.
  - Shows placeholder empty slots for authentic backpack grid feel.
- [x] **Responsive & Clean:** Works with close button (`X`), toggle button, and maintains all equip/sell/lock functionality.

