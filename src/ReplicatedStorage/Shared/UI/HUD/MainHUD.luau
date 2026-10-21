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

local Components = script.Parent.Parent:WaitForChild("Components")
local Popup = require(Components:WaitForChild("Popup"))

export type MainHUDInstance = {
	Gui: ScreenGui,
	UpdateGold: (self: MainHUDInstance, amount: number) -> (),
	SetOnTap: (self: MainHUDInstance, callback: (Vector2) -> ()) -> (),
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

	-- Modals container for dialog popups
	local modalContainer = Instance.new("Frame")
	modalContainer.Name = "Modals"
	modalContainer.Size = UDim2.new(1, 0, 1, 0)
	modalContainer.BackgroundTransparency = 1
	modalContainer.ZIndex = 10
	modalContainer.Parent = screenGui

	local function createPlaceholderPopup(title: string, desc: string): Popup.PopupComponent
		local popup = Popup.new({
			Title = title,
			Parent = modalContainer,
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

	-- 3. Side Menu: Left vertical stack in exact order: Shop (1), Rebirth (2), Index (3)
	local sideContainer = Instance.new("Frame")
	sideContainer.Name = "SideMenu"
	sideContainer.Size = UDim2.new(0, 68, 0, 220)
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

	createHudImageButton({
		Name = "RebirthButton",
		Text = "Rebirth",
		AssetKey = "Rebirth",
		FallbackIcon = "🌀",
		FallbackBgColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.AuraPurple,
		Size = UDim2.new(0, 60, 0, 60),
		CornerRadius = Theme.Corner.Medium,
		LayoutOrder = 2,
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
		LayoutOrder = 3,
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
			backpackPopup:Open()
		end,
	})

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
			-- Placeholder until RollService is built
			goldLabel.TextColor3 = Theme.Colors.AuraCyan
			task.delay(0.2, function()
				goldLabel.TextColor3 = Theme.Colors.TextGold
			end)
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

	local self: MainHUDInstance = {
		Gui = screenGui,
		UpdateGold = function(_, amount: number)
			goldLabel.Text = "$" .. NumberFormat.format(amount)
		end,
		SetOnTap = function(_, callback: (Vector2) -> ())
			onTapCallback = callback
		end,
		Destroy = function(_)
			screenGui:Destroy()
		end,
	}

	return self
end

return MainHUD
