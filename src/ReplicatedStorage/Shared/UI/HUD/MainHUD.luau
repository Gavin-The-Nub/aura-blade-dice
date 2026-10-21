--!strict
-- Main HUD layout constructed from reusable UI components (Button, Panel, Popup).
-- Includes Gold display at top, interactive tap area, and side menu placeholders.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local Components = script.Parent.Parent:WaitForChild("Components")
local Button = require(Components:WaitForChild("Button"))
local Panel = require(Components:WaitForChild("Panel"))
local Popup = require(Components:WaitForChild("Popup"))

export type MainHUDInstance = {
	Gui: ScreenGui,
	UpdateGold: (self: MainHUDInstance, amount: number) -> (),
	SetOnTap: (self: MainHUDInstance, callback: (Vector2) -> ()) -> (),
	Destroy: (self: MainHUDInstance) -> (),
}

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

	-- 2. Top Bar: Gold Display Card
	local goldPanel = Panel.new({
		Name = "GoldDisplayPanel",
		Size = UDim2.new(0, 220, 0, 44),
		Position = UDim2.new(0.5, 0, 0, 14),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor = Theme.Colors.BackgroundCard,
		BorderColor = Theme.Colors.AuraGold,
		BorderThickness = Theme.Stroke.WidthDefault,
		CornerRadius = Theme.Corner.Round,
		Padding = UDim.new(0, 4),
		Parent = root,
	})
	goldPanel.Instance.ZIndex = 5

	local goldLayout = Instance.new("UIListLayout")
	goldLayout.FillDirection = Enum.FillDirection.Horizontal
	goldLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	goldLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	goldLayout.SortOrder = Enum.SortOrder.LayoutOrder
	goldLayout.Padding = UDim.new(0, 8)
	goldLayout.Parent = goldPanel.Content

	-- Plain shape / gold coin emblem
	local goldIconBadge = Instance.new("Frame")
	goldIconBadge.Name = "GoldIconBadge"
	goldIconBadge.Size = UDim2.new(0, 24, 0, 24)
	goldIconBadge.BackgroundColor3 = Theme.Colors.AuraGold
	goldIconBadge.BorderSizePixel = 0
	goldIconBadge.LayoutOrder = 1
	goldIconBadge.Parent = goldPanel.Content

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = Theme.Corner.Round
	badgeCorner.Parent = goldIconBadge

	local goldIcon = Instance.new("TextLabel")
	goldIcon.Name = "GoldIcon"
	goldIcon.Size = UDim2.new(1, 0, 1, 0)
	goldIcon.BackgroundTransparency = 1
	goldIcon.Text = "$"
	goldIcon.TextColor3 = Theme.Colors.BackgroundDark
	goldIcon.TextScaled = false
	goldIcon.TextSize = 16
	goldIcon.Font = Theme.Fonts.Title
	goldIcon.Parent = goldIconBadge

	local goldLabel = Instance.new("TextLabel")
	goldLabel.Name = "GoldAmount"
	goldLabel.Size = UDim2.new(0, 130, 1, 0)
	goldLabel.BackgroundTransparency = 1
	goldLabel.Text = "0"
	goldLabel.TextColor3 = Theme.Colors.TextGold
	goldLabel.TextXAlignment = Enum.TextXAlignment.Left
	goldLabel.TextScaled = false
	goldLabel.TextSize = 22
	goldLabel.Font = Theme.Fonts.Number
	goldLabel.LayoutOrder = 2
	goldLabel.Parent = goldPanel.Content

	-- 3. Side Menu (Left Stack of themed buttons)
	local sideContainer = Instance.new("Frame")
	sideContainer.Name = "SideMenu"
	sideContainer.Size = UDim2.new(0, 68, 0, 220)
	sideContainer.Position = UDim2.new(0, 12, 0.45, 0)
	sideContainer.AnchorPoint = Vector2.new(0, 0.5)
	sideContainer.BackgroundTransparency = 1
	sideContainer.ZIndex = 5
	sideContainer.Parent = root

	local sideList = Instance.new("UIListLayout")
	sideList.FillDirection = Enum.FillDirection.Vertical
	sideList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sideList.VerticalAlignment = Enum.VerticalAlignment.Center
	sideList.Padding = UDim.new(0, 10)
	sideList.Parent = sideContainer

	-- Modals for side menu buttons
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

	Button.new({
		Name = "ShopButton",
		Size = UDim2.new(0, 60, 0, 60),
		IconText = "🛍️",
		Text = "Shop",
		Direction = "Vertical",
		BackgroundColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.AuraCrimson,
		CornerRadius = Theme.Corner.Medium,
		Parent = sideContainer,
		OnClick = function()
			shopPopup:Open()
		end,
	})

	Button.new({
		Name = "RebirthButton",
		Size = UDim2.new(0, 60, 0, 60),
		IconText = "🌀",
		Text = "Rebirth",
		Direction = "Vertical",
		BackgroundColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.AuraPurple,
		CornerRadius = Theme.Corner.Medium,
		Parent = sideContainer,
		OnClick = function()
			rebirthPopup:Open()
		end,
	})

	Button.new({
		Name = "IndexButton",
		Size = UDim2.new(0, 60, 0, 60),
		IconText = "📖",
		Text = "Index",
		Direction = "Vertical",
		BackgroundColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.AuraCyan,
		CornerRadius = Theme.Corner.Medium,
		Parent = sideContainer,
		OnClick = function()
			indexPopup:Open()
		end,
	})

	-- 4. Bottom Bar: Action buttons matching reference layout (Backpack, ROLL, Upgrades)
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
	bottomList.Padding = UDim.new(0, 14)
	bottomList.Parent = bottomContainer

	local backpackPopup = createPlaceholderPopup("Backpack & Swords", "Equip your strongest blade and place backup swords on pedestals.")
	local upgradesPopup = createPlaceholderPopup("Blade Upgrades", "Master Appraiser: Roll Grades and Enchants onto your blades.")

	Button.new({
		Name = "BackpackButton",
		Size = UDim2.new(0, 78, 0, 56),
		IconText = "🗡️",
		Text = "Swords",
		Direction = "Vertical",
		BackgroundColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.AuraCyan,
		CornerRadius = Theme.Corner.Medium,
		Parent = bottomContainer,
		OnClick = function()
			backpackPopup:Open()
		end,
	})

	-- Large central ROLL button
	Button.new({
		Name = "RollButton",
		Size = UDim2.new(0, 96, 0, 68),
		IconText = "🎲",
		Text = "ROLL",
		Direction = "Vertical",
		TextColor = Theme.Colors.TextGold,
		BackgroundColor = Theme.Colors.ButtonPrimary,
		BorderColor = Theme.Colors.AuraGold,
		CornerRadius = Theme.Corner.Large,
		Parent = bottomContainer,
		OnClick = function()
			-- Placeholder until RollService is built
			goldLabel.TextColor3 = Theme.Colors.AuraCyan
			task.delay(0.2, function()
				goldLabel.TextColor3 = Theme.Colors.TextGold
			end)
		end,
	})

	Button.new({
		Name = "UpgradesButton",
		Size = UDim2.new(0, 78, 0, 56),
		IconText = "⭐",
		Text = "Upgrades",
		Direction = "Vertical",
		BackgroundColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.AuraEmerald,
		CornerRadius = Theme.Corner.Medium,
		Parent = bottomContainer,
		OnClick = function()
			upgradesPopup:Open()
		end,
	})

	local self: MainHUDInstance = {
		Gui = screenGui,
		UpdateGold = function(_, amount: number)
			goldLabel.Text = NumberFormat.format(amount)
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
