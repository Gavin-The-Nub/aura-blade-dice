# Left Sidebar Simulator Buttons Design Specification

## Overview
Implement custom creator store button graphics in the left sidebar menu (`SideMenu` in `MainHUD`), matching the simulator visual style shown in the reference design. The buttons for **Shop**, **Rebirth**, and **Index** use custom illustrated button artwork from the place's Asset Manager, paired with stylized FredokaOne title text and contextual outlines.

---

## Architecture & Asset Mapping

### 1. Asset Registry (`src/ReplicatedStorage/Config/Assets.luau`)
Register the Creator Store asset IDs for the left sidebar buttons:

```luau
Plates = {
    Default = "",
    Shop = "rbxassetid://114505581952233",
    Rebirth = "rbxassetid://99418679601643",
    Index = "rbxassetid://110329880068770",
    Swords = "",
    Roll = "",
    Upgrades = "",
}
```

The plate assets contain the button graphic and central icon without baked-in text.

### 2. HUD Button Layout & Styling (`src/ReplicatedStorage/Shared/UI/HUD/MainHUD.luau`)

#### Container (`SideMenu`)
- **Position**: `UDim2.new(0, 16, 0.45, 0)` with `AnchorPoint = Vector2.new(0, 0.5)`.
- **Layout**: `UIListLayout` (Vertical, `Padding = UDim.new(0, 12)`).
- **ZIndex**: `5`.

#### Button Component (`createHudImageButton`)
- **Size**: `UDim2.new(0, 68, 0, 72)` for a prominent squircle button.
- **Image**: When `plateAsset ~= ""` (e.g., Shop, Rebirth, Index), the `ImageButton` sets:
  - `Image = plateAsset`
  - `ScaleType = Enum.ScaleType.Fit`
  - `BackgroundTransparency = 1`
  - The outer `UIStroke` is disabled/transparent so it doesn't conflict with the pre-baked artwork border.
  - The inner `IconImage` is hidden/omitted since the plate already includes the illustrated icon.
- **Text Label**:
  - `Text`: Title Case (`Shop`, `Rebirth`, `Index`).
  - `Font`: `Theme.Fonts.Number` (`Enum.Font.FredokaOne`).
  - `TextSize`: `16`.
  - `TextColor3`: `Color3.fromRGB(255, 255, 255)` (Pure white).
  - `Size`: `UDim2.new(1, 0, 0, 24)`.
  - `Position`: `UDim2.new(0.5, 0, 1, -2)` with `AnchorPoint = Vector2.new(0.5, 1)`.
  - `UIStroke`:
    - `Color`: `Color3.fromRGB(15, 15, 15)` (Deep dark outline).
    - `Thickness`: `3`.
    - `ApplyStrokeMode`: `Enum.ApplyStrokeMode.Contextual`.
- **Interactions (`UIScale`)**:
  - `MouseEnter`: Tween scale to `1.06` over 0.1s.
  - `MouseLeave`: Tween scale back to `1.0`.
  - `MouseButton1Down` / `Touch`: Tween scale to `0.92`.
  - `MouseButton1Up` / `TouchEnded`: Tween scale back to `1.0`.

#### Fallback Behavior
- If any asset ID is empty or fails, the button falls back to procedural `BackgroundColor3 = config.FallbackBgColor`, `UIStroke`, and the emoji/icon fallback text, maintaining complete backward compatibility.

---

## Verification & Testing
1. **Roblox Studio Sync**: Apply changes to `Config/Assets.luau` and `Shared/UI/HUD/MainHUD.luau`.
2. **Screen Capture & Visual Check**: Run a temporary screen capture or playtest in Studio to verify:
   - All 3 buttons render the custom Creator Store graphics cleanly.
   - Text labels (`Shop`, `Rebirth`, `Index`) align cleanly at the base of each button.
   - No clipping or overlapping issues on small or wide screens.
   - Hover and press animations work as expected.
