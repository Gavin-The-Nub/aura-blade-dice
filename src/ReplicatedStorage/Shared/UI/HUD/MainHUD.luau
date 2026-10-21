--!strict
-- Main HUD layout constructed from Theme, Config/Assets, and reusable UI components.
-- Bottom-left large outlined Gold text, Left menu (Shop, Rebirth, Index),
-- and ImageButtons with plate + icon + outlined text label.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Assets = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("Assets"))
local Swords = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("Swords"))

local Components = script.Parent.Parent:WaitForChild("Components")
local Popup = require(Components:WaitForChild("Popup"))
local Button = require(Components:WaitForChild("Button"))

export type MainHUDInstance = {
	Gui: ScreenGui,
	UpdateGold: (self: MainHUDInstance, amount: number) -> (),
	UpdateFever: (self: MainHUDInstance, points: number, maxPoints: number, isActive: boolean, durationRemaining: number) -> (),
	SetAutoTapState: (self: MainHUDInstance, isEnabled: boolean) -> (),
	SetAutoRollState: (self: MainHUDInstance, isEnabled: boolean) -> (),
	SetOnTap: (self: MainHUDInstance, callback: (Vector2) -> ()) -> (),
	SetOnAutoTapToggle: (self: MainHUDInstance, callback: () -> ()) -> (),
	SetOnRoll: (self: MainHUDInstance, callback: () -> ()) -> (),
	SetOnAutoRollToggle: (self: MainHUDInstance, callback: () -> ()) -> (),
	SetOnBackpack: (self: MainHUDInstance, callback: () -> ()) -> (),
	SetOnDice: (self: MainHUDInstance, callback: () -> ()) -> (),
	ShowRollPopup: (self: MainHUDInstance, swordDef: any, isAutoSold: boolean?) -> (),
	ShowRollToast: (self: MainHUDInstance, swordOrText: any, isError: boolean?, isAutoSold: boolean?) -> (),
	SpawnFloatingNumber: (self: MainHUDInstance, pos: Vector2, amount: number, isCrit: boolean) -> (),
	Destroy: (self: MainHUDInstance) -> (),
}

type HudButtonConfig = {
	Name: string,
	Text: string,
	AssetKey: string,
	FallbackIcon: string,
	FallbackBgColor: Color3,
	BorderColor: Color3,
	TextColor: Color3?,
	Size: UDim2,
	CornerRadius: UDim?,
	LayoutOrder: number?,
	Parent: Instance,
	OnClick: () -> (),
}

local function createHudImageButton(config: HudButtonConfig): ImageButton
	local button = Instance.new("ImageButton")
	button.Name = config.Name
	button.Size = config.Size or UDim2.new(0, 60, 0, 60)
	button.LayoutOrder = config.LayoutOrder or 0
	button.AutoButtonColor = false
	button.ClipsDescendants = false

	local plates = Assets.Plates :: any
	local icons = Assets.Icons :: any

	local plateAsset: string = (plates and plates[config.AssetKey]) or (plates and plates.Default) or ""
	if plateAsset ~= "" then
		button.Image = plateAsset
		button.BackgroundTransparency = 1
		button.ScaleType = Enum.ScaleType.Slice
	else
		button.Image = ""
		button.BackgroundColor3 = config.FallbackBgColor
		button.BackgroundTransparency = 0
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = config.CornerRadius or Theme.Corner.Medium
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = config.BorderColor
	stroke.Thickness = Theme.Stroke.WidthDefault
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = button

	-- 1. Icon Image (or fallback colored shape/text)
	local iconImage = Instance.new("ImageLabel")
	iconImage.Name = "IconImage"
	iconImage.Size = UDim2.new(0.65, 0, 0.52, 0)
	iconImage.Position = UDim2.new(0.5, 0, 0.08, 0)
	iconImage.AnchorPoint = Vector2.new(0.5, 0)
	iconImage.BackgroundTransparency = 1
	iconImage.ScaleType = Enum.ScaleType.Fit
	iconImage.ZIndex = 2
	iconImage.Parent = button

	local iconAsset: string = (icons and icons[config.AssetKey]) or ""
	if iconAsset ~= "" then
		iconImage.Image = iconAsset
	else
		iconImage.Image = ""
		local fallback = Instance.new("TextLabel")
		fallback.Name = "FallbackIcon"
		fallback.Size = UDim2.new(1, 0, 1, 0)
		fallback.BackgroundTransparency = 1
		fallback.Text = config.FallbackIcon
		fallback.TextScaled = true
		fallback.Font = Theme.Fonts.Title
		fallback.ZIndex = 2
		fallback.Parent = iconImage
	end

	-- 2. Outlined text label
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Label"
	textLabel.Size = UDim2.new(1, -4, 0.36, 0)
	textLabel.Position = UDim2.new(0.5, 0, 0.96, 0)
	textLabel.AnchorPoint = Vector2.new(0.5, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = config.Text:upper()
	textLabel.TextColor3 = config.TextColor or Theme.Colors.TextPrimary
	textLabel.Font = Theme.Fonts.Button
	textLabel.TextScaled = false
	textLabel.TextSize = 12
	textLabel.ZIndex = 2
	textLabel.Parent = button

	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Theme.TextStroke.Color
	textStroke.Thickness = Theme.TextStroke.Thickness
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textStroke.Parent = textLabel

	-- Micro-interactions
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, Theme.Transitions.Fast, { Scale = 1.05 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, Theme.Transitions.Fast, { Scale = 1.0 }):Play()
	end)
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(scale, Theme.Transitions.Fast, { Scale = 0.93 }):Play()
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(scale, Theme.Transitions.Fast, { Scale = 1.0 }):Play()
		end
	end)

	button.Activated:Connect(config.OnClick)
	button.Parent = config.Parent

	return button
end

local MainHUD = {}

function MainHUD.new(parentGui: Instance): MainHUDInstance
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AuraBladeMainHUD"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 1
	screenGui.Parent = parentGui

	-- Root frame with safe mobile scaling
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.new(1, 0, 1, 0)
	root.BackgroundTransparency = 1
	root.Parent = screenGui

	-- 1. Fullscreen interactive Tap Area (layered behind HUD buttons)
	local tapArea = Instance.new("TextButton")
	tapArea.Name = "TapArea"
	tapArea.Size = UDim2.new(1, 0, 1, 0)
	tapArea.BackgroundTransparency = 1
	tapArea.Text = ""
	tapArea.AutoButtonColor = false
	tapArea.ZIndex = 1
	tapArea.Parent = root

	local onTapCallback: ((Vector2) -> ())? = nil

	-- Visual slash/tap spark effect
	local function playTapSpark(pos: Vector2)
		local spark = Instance.new("Frame")
		spark.Name = "TapSpark"
		spark.Size = UDim2.new(0, 12, 0, 12)
		spark.Position = UDim2.new(0, pos.X, 0, pos.Y)
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.BackgroundColor3 = Theme.Colors.AuraCyan
		spark.BorderSizePixel = 0
		spark.ZIndex = 2
		spark.Parent = root

		local corner = Instance.new("UICorner")
		corner.CornerRadius = Theme.Corner.Round
		corner.Parent = spark

		local tween = TweenService:Create(spark, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 48, 0, 48),
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function()
			spark:Destroy()
		end)
	end

	tapArea.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			playTapSpark(pos)
			if onTapCallback then
				onTapCallback(pos)
			end
		end
	end)

	-- 2. Gold Counter: Bottom-left, large bold text with thick UIStroke outline, NO pill
	local goldLabel = Instance.new("TextLabel")
	goldLabel.Name = "GoldAmount"
	goldLabel.Size = UDim2.new(0, 360, 0, 52)
	goldLabel.Position = UDim2.new(0, 24, 1, -22)
	goldLabel.AnchorPoint = Vector2.new(0, 1)
	goldLabel.BackgroundTransparency = 1
	goldLabel.Text = "$0"
	goldLabel.TextColor3 = Theme.Colors.TextGold
	goldLabel.TextXAlignment = Enum.TextXAlignment.Left
	goldLabel.TextYAlignment = Enum.TextYAlignment.Bottom
	goldLabel.TextScaled = false
	goldLabel.TextSize = 42
	goldLabel.Font = Theme.Fonts.Number
	goldLabel.ZIndex = 5
	goldLabel.Parent = root

	local goldStroke = Instance.new("UIStroke")
	goldStroke.Color = Theme.TextStroke.Color
	goldStroke.Thickness = Theme.TextStroke.HeavyThickness
	goldStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	goldStroke.Parent = goldLabel



	local function createPlaceholderPopup(title: string, desc: string): Popup.PopupComponent
		local popup = Popup.new({
			Title = title,
			Parent = screenGui,
		})
		local descLabel = Instance.new("TextLabel")
		descLabel.Name = "Description"
		descLabel.Size = UDim2.new(1, -16, 0, 80)
		descLabel.Position = UDim2.new(0, 8, 0, 12)
		descLabel.BackgroundTransparency = 1
		descLabel.Text = desc
		descLabel.TextColor3 = Theme.Colors.TextSecondary
		descLabel.TextSize = 16
		descLabel.TextWrapped = true
		descLabel.Font = Theme.Fonts.Body
		descLabel.Parent = popup.Content
		return popup
	end

	local shopPopup = createPlaceholderPopup("Merchant Shop", "Dice & Boosts Merchant is coming soon!\nSpend Gold to unlock higher tier Dice.")
	local rebirthPopup = createPlaceholderPopup("Rebirth Chamber", "Rebirth system unlocks permanent Gold & Luck multipliers.")
	local indexPopup = createPlaceholderPopup("Blade Codex", "View all discovered Swords, Grades, and Auras in your collection.")

	-- 3. Side Menu: Left vertical stack: Shop (1), Dice (2), Rebirth (3), Index (4)
	local sideContainer = Instance.new("Frame")
	sideContainer.Name = "SideMenu"
	sideContainer.Size = UDim2.new(0, 68, 0, 280)
	sideContainer.Position = UDim2.new(0, 16, 0.45, 0)
	sideContainer.AnchorPoint = Vector2.new(0, 0.5)
	sideContainer.BackgroundTransparency = 1
	sideContainer.ZIndex = 5
	sideContainer.Parent = root

	local sideList = Instance.new("UIListLayout")
	sideList.FillDirection = Enum.FillDirection.Vertical
	sideList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sideList.VerticalAlignment = Enum.VerticalAlignment.Center
	sideList.SortOrder = Enum.SortOrder.LayoutOrder
	sideList.Padding = UDim.new(0, 12)
	sideList.Parent = sideContainer

	createHudImageButton({
		Name = "ShopButton",
		Text = "Shop",
		AssetKey = "Shop",
		FallbackIcon = "🛍️",
		FallbackBgColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.AuraCrimson,
		Size = UDim2.new(0, 60, 0, 60),
		CornerRadius = Theme.Corner.Medium,
		LayoutOrder = 1,
		Parent = sideContainer,
		OnClick = function()
			shopPopup:Open()
		end,
	})

	local onDiceCallback: (() -> ())? = nil

	createHudImageButton({
		Name = "DiceButton",
		Text = "Dice",
		AssetKey = "Dice",
		FallbackIcon = "🎲",
		FallbackBgColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.AuraGold,
		Size = UDim2.new(0, 60, 0, 60),
		CornerRadius = Theme.Corner.Medium,
		LayoutOrder = 2,
		Parent = sideContainer,
		OnClick = function()
			if onDiceCallback then
				onDiceCallback()
			end
		end,
	})

	createHudImageButton({
		Name = "RebirthButton",
		Text = "Rebirth",
		AssetKey = "Rebirth",
		FallbackIcon = "🌀",
		FallbackBgColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.AuraPurple,
		Size = UDim2.new(0, 60, 0, 60),
		CornerRadius = Theme.Corner.Medium,
		LayoutOrder = 3,
		Parent = sideContainer,
		OnClick = function()
			rebirthPopup:Open()
		end,
	})

	createHudImageButton({
		Name = "IndexButton",
		Text = "Index",
		AssetKey = "Index",
		FallbackIcon = "📖",
		FallbackBgColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.AuraCyan,
		Size = UDim2.new(0, 60, 0, 60),
		CornerRadius = Theme.Corner.Medium,
		LayoutOrder = 4,
		Parent = sideContainer,
		OnClick = function()
			indexPopup:Open()
		end,
	})

	-- 4. Bottom Bar: Action buttons matching reference layout (Backpack/Swords, ROLL, Upgrades)
	local bottomContainer = Instance.new("Frame")
	bottomContainer.Name = "BottomBar"
	bottomContainer.Size = UDim2.new(0, 320, 0, 72)
	bottomContainer.Position = UDim2.new(0.5, 0, 1, -16)
	bottomContainer.AnchorPoint = Vector2.new(0.5, 1)
	bottomContainer.BackgroundTransparency = 1
	bottomContainer.ZIndex = 5
	bottomContainer.Parent = root

	local bottomList = Instance.new("UIListLayout")
	bottomList.FillDirection = Enum.FillDirection.Horizontal
	bottomList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	bottomList.VerticalAlignment = Enum.VerticalAlignment.Bottom
	bottomList.SortOrder = Enum.SortOrder.LayoutOrder
	bottomList.Padding = UDim.new(0, 14)
	bottomList.Parent = bottomContainer

	local backpackPopup = createPlaceholderPopup("Backpack & Swords", "Equip your strongest blade and place backup swords on pedestals.")
	local upgradesPopup = createPlaceholderPopup("Blade Upgrades", "Master Appraiser: Roll Grades and Enchants onto your blades.")

	-- Roll Result Popup (Modal for Manual Rolls)
	local rollPopup = Popup.new({
		Title = "Blade Pulled!",
		Size = UDim2.new(0.85, 0, 0.42, 0),
		MaxWidth = 400,
		MaxHeight = 280,
		Parent = screenGui,
	})

	local rollPopupRarityLabel = Instance.new("TextLabel")
	rollPopupRarityLabel.Name = "RarityLabel"
	rollPopupRarityLabel.Size = UDim2.new(1, 0, 0, 22)
	rollPopupRarityLabel.Position = UDim2.new(0, 0, 0, 8)
	rollPopupRarityLabel.BackgroundTransparency = 1
	rollPopupRarityLabel.Font = Theme.Fonts.Title
	rollPopupRarityLabel.TextSize = 15
	rollPopupRarityLabel.TextColor3 = Theme.Colors.AuraCyan
	rollPopupRarityLabel.Text = "RARE (1 in 1,200)"
	rollPopupRarityLabel.Parent = rollPopup.Content

	local rollPopupSwordLabel = Instance.new("TextLabel")
	rollPopupSwordLabel.Name = "SwordLabel"
	rollPopupSwordLabel.Size = UDim2.new(1, 0, 0, 36)
	rollPopupSwordLabel.Position = UDim2.new(0, 0, 0, 32)
	rollPopupSwordLabel.BackgroundTransparency = 1
	rollPopupSwordLabel.Font = Theme.Fonts.Title
	rollPopupSwordLabel.TextSize = 22
	rollPopupSwordLabel.TextColor3 = Theme.Colors.TextPrimary
	rollPopupSwordLabel.Text = "Static Katana"
	rollPopupSwordLabel.Parent = rollPopup.Content

	local swordStroke = Instance.new("UIStroke")
	swordStroke.Color = Theme.TextStroke.Color
	swordStroke.Thickness = 2
	swordStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	swordStroke.Parent = rollPopupSwordLabel

	local rollPopupDamageLabel = Instance.new("TextLabel")
	rollPopupDamageLabel.Name = "DamageLabel"
	rollPopupDamageLabel.Size = UDim2.new(1, 0, 0, 20)
	rollPopupDamageLabel.Position = UDim2.new(0, 0, 0, 72)
	rollPopupDamageLabel.BackgroundTransparency = 1
	rollPopupDamageLabel.Font = Theme.Fonts.Body
	rollPopupDamageLabel.TextSize = 13
	rollPopupDamageLabel.TextColor3 = Theme.Colors.TextSecondary
	rollPopupDamageLabel.Text = "Base Damage: 280 Gold/Tap"
	rollPopupDamageLabel.Parent = rollPopup.Content

	local claimButton = Button.new({
		Name = "ClaimButton",
		Text = "OK",
		Size = UDim2.new(0.6, 0, 0, 38),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor = Theme.Colors.ButtonPrimary,
		BorderColor = Theme.Colors.AuraCyan,
		TextColor = Theme.Colors.TextPrimary,
		CornerRadius = Theme.Corner.Medium,
		Parent = rollPopup.Content,
		OnClick = function()
			rollPopup:Close()
		end,
	})

	local function showRollPopup(swordDef: any, isAutoSold: boolean?)
		local rarityColor = (Swords.RarityColors and Swords.RarityColors[swordDef.rarity]) or Theme.Colors.AuraCyan
		local rarityText = ("%s (1 in %s)"):format(string.upper(swordDef.rarity), NumberFormat.format(swordDef.baseOdds))
		if isAutoSold then
			rarityText ..= " • AUTO-SOLD"
		end
		rollPopupRarityLabel.Text = rarityText
		rollPopupRarityLabel.TextColor3 = rarityColor
		rollPopupSwordLabel.Text = swordDef.name
		rollPopupSwordLabel.TextColor3 = rarityColor
		rollPopupDamageLabel.Text = ("Base Damage: %s Gold/Tap"):format(NumberFormat.format(swordDef.baseDamage))

		local claimStroke = claimButton.Instance:FindFirstChildOfClass("UIStroke")
		if claimStroke then
			claimStroke.Color = rarityColor
		end

		rollPopup:Open()
	end

	-- Auto-Roll Toast (Non-blocking notification)
	local toastFrame = Instance.new("Frame")
	toastFrame.Name = "RollToast"
	toastFrame.Size = UDim2.new(0, 310, 0, 36)
	toastFrame.Position = UDim2.new(0.5, 0, 1, -128)
	toastFrame.AnchorPoint = Vector2.new(0.5, 1)
	toastFrame.BackgroundColor3 = Theme.Colors.BackgroundDark
	toastFrame.BackgroundTransparency = 0.15
	toastFrame.Visible = false
	toastFrame.Active = false -- Never blocks clicks or taps!
	toastFrame.ZIndex = 8
	toastFrame.Parent = root

	local toastCorner = Instance.new("UICorner")
	toastCorner.CornerRadius = Theme.Corner.Medium
	toastCorner.Parent = toastFrame

	local toastStroke = Instance.new("UIStroke")
	toastStroke.Color = Theme.Colors.Border
	toastStroke.Thickness = Theme.Stroke.WidthDefault
	toastStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	toastStroke.Parent = toastFrame

	local toastLabel = Instance.new("TextLabel")
	toastLabel.Name = "ToastLabel"
	toastLabel.Size = UDim2.new(1, -16, 1, 0)
	toastLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	toastLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	toastLabel.BackgroundTransparency = 1
	toastLabel.Font = Theme.Fonts.Button
	toastLabel.TextSize = 13
	toastLabel.TextColor3 = Theme.Colors.TextPrimary
	toastLabel.Text = ""
	toastLabel.Active = false
	toastLabel.ZIndex = 9
	toastLabel.Parent = toastFrame

	local toastThread: thread? = nil
	local function showRollToast(swordOrText: any, isError: boolean?, isAutoSold: boolean?)
		if toastThread then
			task.cancel(toastThread)
			toastThread = nil
		end

		if isError then
			toastStroke.Color = Theme.Colors.ButtonClose
			toastLabel.TextColor3 = Theme.Colors.ButtonClose
			toastLabel.Text = tostring(swordOrText)
		elseif type(swordOrText) == "table" and swordOrText.name then
			local rarityColor = (Swords.RarityColors and Swords.RarityColors[swordOrText.rarity]) or Theme.Colors.AuraCyan
			toastStroke.Color = rarityColor
			toastLabel.TextColor3 = rarityColor
			if isAutoSold then
				toastLabel.Text = ("Auto-Sold: [%s] (%s)"):format(swordOrText.name, swordOrText.rarity)
			else
				toastLabel.Text = ("Rolled: [%s] (%s)"):format(swordOrText.name, swordOrText.rarity)
			end
		else
			toastStroke.Color = Theme.Colors.Border
			toastLabel.TextColor3 = Theme.Colors.TextPrimary
			toastLabel.Text = tostring(swordOrText)
		end

		toastFrame.Visible = true
		toastFrame.Position = UDim2.new(0.5, 0, 1, -122)
		TweenService:Create(toastFrame, Theme.Transitions.Pop, { Position = UDim2.new(0.5, 0, 1, -128) }):Play()

		toastThread = task.delay(2.2, function()
			local fade = TweenService:Create(toastFrame, Theme.Transitions.Fast, { BackgroundTransparency = 1 })
			fade:Play()
			fade.Completed:Connect(function()
				toastFrame.Visible = false
				toastFrame.BackgroundTransparency = 0.15
			end)
		end)
	end

	local onBackpackCallback: (() -> ())? = nil

	createHudImageButton({
		Name = "BackpackButton",
		Text = "Swords",
		AssetKey = "Swords",
		FallbackIcon = "🗡️",
		FallbackBgColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.AuraCyan,
		Size = UDim2.new(0, 78, 0, 56),
		CornerRadius = Theme.Corner.Medium,
		LayoutOrder = 1,
		Parent = bottomContainer,
		OnClick = function()
			if onBackpackCallback then
				onBackpackCallback()
			else
				backpackPopup:Open()
			end
		end,
	})

	local onRollCallback: (() -> ())? = nil

	-- Large central ROLL button
	createHudImageButton({
		Name = "RollButton",
		Text = "ROLL",
		AssetKey = "Roll",
		FallbackIcon = "🎲",
		FallbackBgColor = Theme.Colors.ButtonPrimary,
		BorderColor = Theme.Colors.AuraGold,
		TextColor = Theme.Colors.TextGold,
		Size = UDim2.new(0, 96, 0, 68),
		CornerRadius = Theme.Corner.Large,
		LayoutOrder = 2,
		Parent = bottomContainer,
		OnClick = function()
			if onRollCallback then
				onRollCallback()
			end
		end,
	})

	createHudImageButton({
		Name = "UpgradesButton",
		Text = "Upgrades",
		AssetKey = "Upgrades",
		FallbackIcon = "⭐",
		FallbackBgColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.AuraEmerald,
		Size = UDim2.new(0, 78, 0, 56),
		CornerRadius = Theme.Corner.Medium,
		LayoutOrder = 3,
		Parent = bottomContainer,
		OnClick = function()
			upgradesPopup:Open()
		end,
	})

	-- 5. Fever Bar: Positioned directly above the Bottom Bar
	local feverContainer = Instance.new("Frame")
	feverContainer.Name = "FeverBarContainer"
	feverContainer.Size = UDim2.new(0, 270, 0, 22)
	feverContainer.Position = UDim2.new(0.5, 0, 1, -98)
	feverContainer.AnchorPoint = Vector2.new(0.5, 1)
	feverContainer.BackgroundColor3 = Theme.Colors.BackgroundDark
	feverContainer.BackgroundTransparency = 0.15
	feverContainer.ClipsDescendants = true
	feverContainer.ZIndex = 5
	feverContainer.Parent = root

	local feverCorner = Instance.new("UICorner")
	feverCorner.CornerRadius = Theme.Corner.Round
	feverCorner.Parent = feverContainer

	local feverStroke = Instance.new("UIStroke")
	feverStroke.Color = Theme.Colors.Border
	feverStroke.Thickness = Theme.Stroke.WidthThin
	feverStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	feverStroke.Parent = feverContainer

	local feverFill = Instance.new("Frame")
	feverFill.Name = "Fill"
	feverFill.Size = UDim2.new(0, 0, 1, 0)
	feverFill.Position = UDim2.new(0, 0, 0, 0)
	feverFill.BackgroundColor3 = Theme.Colors.AuraCrimson
	feverFill.BorderSizePixel = 0
	feverFill.ZIndex = 6
	feverFill.Parent = feverContainer

	local feverFillCorner = Instance.new("UICorner")
	feverFillCorner.CornerRadius = Theme.Corner.Round
	feverFillCorner.Parent = feverFill

	local feverFillGradient = Instance.new("UIGradient")
	feverFillGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Colors.AuraCrimson),
		ColorSequenceKeypoint.new(1, Theme.Colors.AuraGold),
	})
	feverFillGradient.Parent = feverFill

	local feverLabel = Instance.new("TextLabel")
	feverLabel.Name = "Label"
	feverLabel.Size = UDim2.new(1, 0, 1, 0)
	feverLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	feverLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	feverLabel.BackgroundTransparency = 1
	feverLabel.Text = "FEVER 0/100"
	feverLabel.TextColor3 = Theme.Colors.TextPrimary
	feverLabel.Font = Theme.Fonts.Button
	feverLabel.TextSize = 11
	feverLabel.ZIndex = 7
	feverLabel.Parent = feverContainer

	local feverLabelStroke = Instance.new("UIStroke")
	feverLabelStroke.Color = Theme.TextStroke.Color
	feverLabelStroke.Thickness = 1.5
	feverLabelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	feverLabelStroke.Parent = feverLabel

	-- 6. Auto-Tap Toggle Button: Bottom-Right thumb zone (completely clear of ROLL)
	local autoTapButton = Instance.new("ImageButton")
	autoTapButton.Name = "AutoTapButton"
	autoTapButton.Size = UDim2.new(0, 68, 0, 58)
	autoTapButton.Position = UDim2.new(1, -20, 1, -20)
	autoTapButton.AnchorPoint = Vector2.new(1, 1)
	autoTapButton.BackgroundColor3 = Theme.Colors.ButtonSecondary
	autoTapButton.AutoButtonColor = false
	autoTapButton.ZIndex = 5
	autoTapButton.Parent = root

	local autoCorner = Instance.new("UICorner")
	autoCorner.CornerRadius = Theme.Corner.Medium
	autoCorner.Parent = autoTapButton

	local autoStroke = Instance.new("UIStroke")
	autoStroke.Color = Theme.Colors.Border
	autoStroke.Thickness = Theme.Stroke.WidthDefault
	autoStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	autoStroke.Parent = autoTapButton

	local autoScale = Instance.new("UIScale")
	autoScale.Scale = 1
	autoScale.Parent = autoTapButton

	local autoIcon = Instance.new("TextLabel")
	autoIcon.Name = "Icon"
	autoIcon.Size = UDim2.new(1, 0, 0.45, 0)
	autoIcon.Position = UDim2.new(0.5, 0, 0.08, 0)
	autoIcon.AnchorPoint = Vector2.new(0.5, 0)
	autoIcon.BackgroundTransparency = 1
	autoIcon.Text = "⚡"
	autoIcon.TextSize = 20
	autoIcon.Font = Theme.Fonts.Title
	autoIcon.ZIndex = 6
	autoIcon.Parent = autoTapButton

	local autoLabel = Instance.new("TextLabel")
	autoLabel.Name = "Label"
	autoLabel.Size = UDim2.new(1, -4, 0.4, 0)
	autoLabel.Position = UDim2.new(0.5, 0, 0.95, 0)
	autoLabel.AnchorPoint = Vector2.new(0.5, 1)
	autoLabel.BackgroundTransparency = 1
	autoLabel.Text = "AUTO: OFF"
	autoLabel.TextColor3 = Theme.Colors.TextMuted
	autoLabel.Font = Theme.Fonts.Button
	autoLabel.TextSize = 10
	autoLabel.ZIndex = 6
	autoLabel.Parent = autoTapButton

	local autoTextStroke = Instance.new("UIStroke")
	autoTextStroke.Color = Theme.TextStroke.Color
	autoTextStroke.Thickness = Theme.TextStroke.Thickness
	autoTextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	autoTextStroke.Parent = autoLabel

	-- Micro-interactions for Auto-Tap button
	autoTapButton.MouseEnter:Connect(function()
		TweenService:Create(autoScale, Theme.Transitions.Fast, { Scale = 1.05 }):Play()
	end)
	autoTapButton.MouseLeave:Connect(function()
		TweenService:Create(autoScale, Theme.Transitions.Fast, { Scale = 1.0 }):Play()
	end)
	autoTapButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(autoScale, Theme.Transitions.Fast, { Scale = 0.93 }):Play()
		end
	end)
	autoTapButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(autoScale, Theme.Transitions.Fast, { Scale = 1.0 }):Play()
		end
	end)

	local onAutoTapToggleCallback: (() -> ())? = nil
	autoTapButton.Activated:Connect(function()
		if onAutoTapToggleCallback then
			onAutoTapToggleCallback()
		end
	end)

	local function setAutoTapVisuals(isEnabled: boolean)
		if isEnabled then
			autoStroke.Color = Theme.Colors.AuraEmerald
			autoStroke.Thickness = Theme.Stroke.WidthThick
			autoTapButton.BackgroundColor3 = Color3.fromRGB(18, 48, 32)
			autoLabel.Text = "AUTO: ON"
			autoLabel.TextColor3 = Theme.Colors.AuraEmerald
		else
			autoStroke.Color = Theme.Colors.Border
			autoStroke.Thickness = Theme.Stroke.WidthDefault
			autoTapButton.BackgroundColor3 = Theme.Colors.ButtonSecondary
			autoLabel.Text = "AUTO: OFF"
			autoLabel.TextColor3 = Theme.Colors.TextMuted
		end
	end

	-- 7. Auto-Roll Toggle Button: Positioned directly above Auto-Tap
	local autoRollButton = Instance.new("ImageButton")
	autoRollButton.Name = "AutoRollButton"
	autoRollButton.Size = UDim2.new(0, 68, 0, 58)
	autoRollButton.Position = UDim2.new(1, -20, 1, -86)
	autoRollButton.AnchorPoint = Vector2.new(1, 1)
	autoRollButton.BackgroundColor3 = Theme.Colors.ButtonSecondary
	autoRollButton.AutoButtonColor = false
	autoRollButton.ZIndex = 5
	autoRollButton.Parent = root

	local autoRollCorner = Instance.new("UICorner")
	autoRollCorner.CornerRadius = Theme.Corner.Medium
	autoRollCorner.Parent = autoRollButton

	local autoRollStroke = Instance.new("UIStroke")
	autoRollStroke.Color = Theme.Colors.Border
	autoRollStroke.Thickness = Theme.Stroke.WidthDefault
	autoRollStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	autoRollStroke.Parent = autoRollButton

	local autoRollScale = Instance.new("UIScale")
	autoRollScale.Scale = 1
	autoRollScale.Parent = autoRollButton

	local autoRollIcon = Instance.new("TextLabel")
	autoRollIcon.Name = "Icon"
	autoRollIcon.Size = UDim2.new(1, 0, 0.45, 0)
	autoRollIcon.Position = UDim2.new(0.5, 0, 0.1, 0)
	autoRollIcon.AnchorPoint = Vector2.new(0.5, 0)
	autoRollIcon.BackgroundTransparency = 1
	autoRollIcon.Text = "🎲"
	autoRollIcon.TextScaled = true
	autoRollIcon.Font = Theme.Fonts.Title
	autoRollIcon.ZIndex = 6
	autoRollIcon.Parent = autoRollButton

	local autoRollLabel = Instance.new("TextLabel")
	autoRollLabel.Name = "Label"
	autoRollLabel.Size = UDim2.new(1, -4, 0.35, 0)
	autoRollLabel.Position = UDim2.new(0.5, 0, 0.94, 0)
	autoRollLabel.AnchorPoint = Vector2.new(0.5, 1)
	autoRollLabel.BackgroundTransparency = 1
	autoRollLabel.Text = "ROLL: OFF"
	autoRollLabel.TextColor3 = Theme.Colors.TextMuted
	autoRollLabel.Font = Theme.Fonts.Button
	autoRollLabel.TextSize = 10
	autoRollLabel.ZIndex = 6
	autoRollLabel.Parent = autoRollButton

	local autoRollLabelStroke = Instance.new("UIStroke")
	autoRollLabelStroke.Color = Theme.TextStroke.Color
	autoRollLabelStroke.Thickness = 1.5
	autoRollLabelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	autoRollLabelStroke.Parent = autoRollLabel

	autoRollButton.MouseEnter:Connect(function()
		TweenService:Create(autoRollScale, Theme.Transitions.Fast, { Scale = 1.05 }):Play()
	end)
	autoRollButton.MouseLeave:Connect(function()
		TweenService:Create(autoRollScale, Theme.Transitions.Fast, { Scale = 1.0 }):Play()
	end)
	autoRollButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(autoRollScale, Theme.Transitions.Fast, { Scale = 0.93 }):Play()
		end
	end)
	autoRollButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(autoRollScale, Theme.Transitions.Fast, { Scale = 1.0 }):Play()
		end
	end)

	local onAutoRollToggleCallback: (() -> ())? = nil
	autoRollButton.Activated:Connect(function()
		if onAutoRollToggleCallback then
			onAutoRollToggleCallback()
		end
	end)

	local function setAutoRollVisuals(isEnabled: boolean)
		if isEnabled then
			autoRollStroke.Color = Theme.Colors.AuraGold
			autoRollStroke.Thickness = Theme.Stroke.WidthThick
			autoRollButton.BackgroundColor3 = Color3.fromRGB(48, 40, 18)
			autoRollLabel.Text = "ROLL: ON"
			autoRollLabel.TextColor3 = Theme.Colors.AuraGold
		else
			autoRollStroke.Color = Theme.Colors.Border
			autoRollStroke.Thickness = Theme.Stroke.WidthDefault
			autoRollButton.BackgroundColor3 = Theme.Colors.ButtonSecondary
			autoRollLabel.Text = "ROLL: OFF"
			autoRollLabel.TextColor3 = Theme.Colors.TextMuted
		end
	end

	local feverCountdownThread: thread? = nil
	local isCurrentlyFever = false

	local function updateFeverDisplay(points: number, maxPoints: number, isActive: boolean, durationRemaining: number)
		if feverCountdownThread then
			task.cancel(feverCountdownThread)
			feverCountdownThread = nil
		end

		isCurrentlyFever = isActive

		if isActive then
			feverStroke.Color = Theme.Colors.AuraGold
			feverStroke.Thickness = Theme.Stroke.WidthThick
			feverFill.BackgroundColor3 = Theme.Colors.AuraGold

			local totalDuration = if durationRemaining > 0 then durationRemaining else 15
			local feverEndTime = os.clock() + durationRemaining

			feverCountdownThread = task.spawn(function()
				while isCurrentlyFever do
					local remaining = math.max(0, feverEndTime - os.clock())
					feverLabel.Text = string.format("🔥 FEVER %.1fs 🔥", remaining)
					local fillPct = math.clamp(remaining / totalDuration, 0, 1)
					feverFill.Size = UDim2.new(fillPct, 0, 1, 0)
					if remaining <= 0 then
						break
					end
					task.wait(0.05)
				end
			end)
		else
			feverStroke.Color = Theme.Colors.Border
			feverStroke.Thickness = Theme.Stroke.WidthThin
			feverFill.BackgroundColor3 = Theme.Colors.AuraCrimson

			local pct = if maxPoints > 0 then math.clamp(points / maxPoints, 0, 1) else 0
			TweenService:Create(feverFill, Theme.Transitions.Fast, {
				Size = UDim2.new(pct, 0, 1, 0),
			}):Play()
			feverLabel.Text = string.format("FEVER %d/%d", points, maxPoints)
		end
	end

	local activeDamageNumbers = 0
	local MAX_ACTIVE_DAMAGE_NUMBERS = 20

	local function spawnFloatingDamageNumber(pos: Vector2, amount: number, isCrit: boolean)
		if activeDamageNumbers >= MAX_ACTIVE_DAMAGE_NUMBERS then
			return
		end
		activeDamageNumbers += 1

		local label = Instance.new("TextLabel")
		label.Name = "DamageNumber"
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		local offsetX = math.random(-20, 20)
		local offsetY = math.random(-10, 10)
		label.Position = UDim2.new(0, pos.X + offsetX, 0, pos.Y + offsetY)
		label.BackgroundTransparency = 1
		label.Active = false
		label.ZIndex = 8

		local formattedAmount = NumberFormat.format(amount)
		if isCrit then
			label.Text = "+" .. formattedAmount .. " CRIT!"
			label.TextColor3 = Theme.Colors.TextCrit or Color3.fromRGB(255, 170, 0)
			label.TextSize = 34
			label.Font = Theme.Fonts.Title
		else
			label.Text = "+" .. formattedAmount
			label.TextColor3 = Theme.Colors.TextPrimary
			label.TextSize = 22
			label.Font = Theme.Fonts.Body
		end

		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.TextStroke.Color
		stroke.Thickness = if isCrit then 2.5 else 1.5
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = label

		label.Parent = root

		local targetY = label.Position.Y.Offset - (if isCrit then 60 else 40)
		local tweenInfo = TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(label, tweenInfo, {
			Position = UDim2.new(0, label.Position.X.Offset, 0, targetY),
			TextTransparency = 1,
		})
		local strokeTween = TweenService:Create(stroke, tweenInfo, {
			Transparency = 1,
		})

		tween:Play()
		strokeTween:Play()

		tween.Completed:Connect(function()
			label:Destroy()
			activeDamageNumbers -= 1
		end)
	end

	local self: MainHUDInstance = {
		Gui = screenGui,
		UpdateGold = function(_, amount: number)
			goldLabel.Text = "$" .. NumberFormat.format(amount)
		end,
		UpdateFever = function(_, points: number, maxPoints: number, isActive: boolean, durationRemaining: number)
			updateFeverDisplay(points, maxPoints, isActive, durationRemaining)
		end,
		SetAutoTapState = function(_, isEnabled: boolean)
			setAutoTapVisuals(isEnabled)
		end,
		SetAutoRollState = function(_, isEnabled: boolean)
			setAutoRollVisuals(isEnabled)
		end,
		SetOnTap = function(_, callback: (Vector2) -> ())
			onTapCallback = callback
		end,
		SetOnAutoTapToggle = function(_, callback: () -> ())
			onAutoTapToggleCallback = callback
		end,
		SetOnRoll = function(_, callback: () -> ())
			onRollCallback = callback
		end,
		SetOnAutoRollToggle = function(_, callback: () -> ())
			onAutoRollToggleCallback = callback
		end,
		SetOnBackpack = function(_, callback: () -> ())
			onBackpackCallback = callback
		end,
		SetOnDice = function(_, callback: () -> ())
			onDiceCallback = callback
		end,
		ShowRollPopup = function(_, swordDef: any, isAutoSold: boolean?)
			showRollPopup(swordDef, isAutoSold)
		end,
		ShowRollToast = function(_, swordOrText: any, isError: boolean?, isAutoSold: boolean?)
			showRollToast(swordOrText, isError, isAutoSold)
		end,
		SpawnFloatingNumber = function(_, pos: Vector2, amount: number, isCrit: boolean)
			spawnFloatingDamageNumber(pos, amount, isCrit)
		end,
		Destroy = function(_)
			if feverCountdownThread then
				task.cancel(feverCountdownThread)
				feverCountdownThread = nil
			end
			screenGui:Destroy()
		end,
	}

	return self
end

return MainHUD
