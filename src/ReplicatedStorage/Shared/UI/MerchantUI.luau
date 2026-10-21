--!strict
-- MerchantUI: Modal dialog for the Dice Merchant.
-- Displays Dice tiers 1 to 10 with name, cost, Luck multiplier, and roll cooldown.
-- Follows strict card states: Equipped / Owned (Equip button) / Buy (cost, disabled if unaffordable).
-- No Locked state: any tier can be bought or equipped if owned.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Config = ReplicatedStorage:WaitForChild("Config")
local Dice = require(Config:WaitForChild("Dice"))

local Components = Shared:WaitForChild("UI"):WaitForChild("Components")
local Popup = require(Components:WaitForChild("Popup"))

export type MerchantUIInstance = {
	Open: (self: MerchantUIInstance) -> (),
	Close: (self: MerchantUIInstance) -> (),
	Toggle: (self: MerchantUIInstance) -> (),
	SetData: (self: MerchantUIInstance, currentTier: number, currentGold: number, ownedDice: { [string]: boolean }) -> (),
	SetOnBuy: (self: MerchantUIInstance, callback: (targetTier: number) -> ()) -> (),
	SetOnEquip: (self: MerchantUIInstance, callback: (targetTier: number) -> ()) -> (),
	Destroy: (self: MerchantUIInstance) -> (),
}

type CardElements = {
	Frame: Frame,
	Stroke: UIStroke,
	TitleLabel: TextLabel,
	StatsLabel: TextLabel,
	ActionContainer: Frame,
}

local MerchantUI = {}

function MerchantUI.new(parentGui: Instance): MerchantUIInstance
	local screenGui: Instance
	if parentGui:IsA("ScreenGui") then
		screenGui = parentGui
	else
		local existing = parentGui:FindFirstChild("AuraBladeMerchantGui")
		if existing and existing:IsA("ScreenGui") then
			existing:Destroy()
		end
		local sg = Instance.new("ScreenGui")
		sg.Name = "AuraBladeMerchantGui"
		sg.ResetOnSpawn = false
		sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		sg.DisplayOrder = 10
		sg.Parent = parentGui
		screenGui = sg
	end

	local isOpened = false

	-- Modal popup window
	local popup = Popup.new({
		Title = "Dice Merchant",
		Size = UDim2.new(0.92, 0, 0.82, 0),
		MaxWidth = 580,
		MaxHeight = 520,
		Parent = screenGui,
		OnClose = function()
			isOpened = false
		end,
	})

	local rootContent = popup.Content

	-- Header banner
	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.Size = UDim2.new(1, 0, 0, 34)
	banner.Position = UDim2.new(0, 0, 0, 0)
	banner.BackgroundColor3 = Theme.Colors.BackgroundDark
	banner.BackgroundTransparency = 0.3
	banner.BorderSizePixel = 0
	banner.Parent = rootContent

	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = Theme.Corner.Small
	bannerCorner.Parent = banner

	local bannerText = Instance.new("TextLabel")
	bannerText.Name = "BannerText"
	bannerText.Size = UDim2.new(1, -16, 1, 0)
	bannerText.Position = UDim2.new(0, 8, 0, 0)
	bannerText.BackgroundTransparency = 1
	bannerText.Font = Theme.Fonts.Button
	bannerText.TextSize = 13
	bannerText.TextColor3 = Theme.Colors.TextSecondary
	bannerText.TextXAlignment = Enum.TextXAlignment.Left
	bannerText.Text = "Purchase Dice with Gold and equip any owned tier to scale your stats!"
	bannerText.Parent = banner

	-- Scrollable container for Dice cards
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "DiceList"
	scrollFrame.Size = UDim2.new(1, 0, 1, -42)
	scrollFrame.Position = UDim2.new(0, 0, 0, 40)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 5
	scrollFrame.ScrollBarImageColor3 = Theme.Colors.AuraCyan
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = rootContent

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = scrollFrame

	local onBuyCallback: ((targetTier: number) -> ())? = nil
	local onEquipCallback: ((targetTier: number) -> ())? = nil
	local currentDiceTier = 1
	local currentGold = 0
	local currentOwnedDice: { [string]: boolean } = { ["1"] = true }
	local cardElementsList: { [number]: CardElements } = {}

	-- Helper to format cost string
	local function formatCost(cost: number): string
		if cost == 0 then
			return "Free"
		end
		return NumberFormat.format(cost) .. " Gold"
	end

	-- Build static card frames for all configured Dice tiers
	for _, def in Dice do
		local card = Instance.new("Frame")
		card.Name = "Card_Tier_" .. def.tier
		card.Size = UDim2.new(1, -10, 0, 66)
		card.LayoutOrder = def.tier
		card.BackgroundColor3 = Theme.Colors.ButtonSecondary
		card.Parent = scrollFrame

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = Theme.Corner.Medium
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = Theme.Colors.Border
		cardStroke.Thickness = Theme.Stroke.WidthDefault
		cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		cardStroke.Parent = card

		-- Left info section
		local infoContainer = Instance.new("Frame")
		infoContainer.Name = "Info"
		infoContainer.Size = UDim2.new(1, -130, 1, 0)
		infoContainer.Position = UDim2.new(0, 12, 0, 0)
		infoContainer.BackgroundTransparency = 1
		infoContainer.Parent = card

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "Title"
		titleLabel.Size = UDim2.new(1, 0, 0, 24)
		titleLabel.Position = UDim2.new(0, 0, 0, 10)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Font = Theme.Fonts.Title
		titleLabel.TextSize = 15
		titleLabel.TextColor3 = Theme.Colors.TextPrimary
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.Text = ("Tier %d: %s"):format(def.tier, def.name)
		titleLabel.Parent = infoContainer

		local statsLabel = Instance.new("TextLabel")
		statsLabel.Name = "Stats"
		statsLabel.Size = UDim2.new(1, 0, 0, 20)
		statsLabel.Position = UDim2.new(0, 0, 0, 34)
		statsLabel.BackgroundTransparency = 1
		statsLabel.Font = Theme.Fonts.Body
		statsLabel.TextSize = 12
		statsLabel.TextColor3 = Theme.Colors.TextSecondary
		statsLabel.TextXAlignment = Enum.TextXAlignment.Left
		statsLabel.Text = ("%sx Luck  •  %.1fs CD  •  %s"):format(NumberFormat.format(def.baseLuck), def.rollCooldown, formatCost(def.cost))
		statsLabel.Parent = infoContainer

		-- Right action container
		local actionContainer = Instance.new("Frame")
		actionContainer.Name = "ActionContainer"
		actionContainer.Size = UDim2.new(0, 116, 0, 42)
		actionContainer.Position = UDim2.new(1, -12, 0.5, 0)
		actionContainer.AnchorPoint = Vector2.new(1, 0.5)
		actionContainer.BackgroundTransparency = 1
		actionContainer.Parent = card

		cardElementsList[def.tier] = {
			Frame = card,
			Stroke = cardStroke,
			TitleLabel = titleLabel,
			StatsLabel = statsLabel,
			ActionContainer = actionContainer,
		}
	end

	-- Updates visuals according to the 3 states: Equipped, Owned (Equip button), Buy (cost)
	local function renderCards()
		for _, def in Dice do
			local elems = cardElementsList[def.tier]
			if not elems then
				continue
			end

			elems.ActionContainer:ClearAllChildren()

			local tier = def.tier
			local isOwned = currentOwnedDice[tostring(tier)] == true
			local isEquipped = (tier == currentDiceTier)

			if isEquipped then
				-- State 1: EQUIPPED
				elems.Frame.BackgroundColor3 = Color3.fromRGB(24, 38, 48)
				elems.Stroke.Color = Theme.Colors.AuraCyan
				elems.Stroke.Thickness = Theme.Stroke.WidthThick
				elems.TitleLabel.TextColor3 = Theme.Colors.AuraCyan

				local badge = Instance.new("Frame")
				badge.Name = "EquippedBadge"
				badge.Size = UDim2.new(1, 0, 1, 0)
				badge.BackgroundColor3 = Color3.fromRGB(16, 44, 56)
				badge.BorderSizePixel = 0
				badge.Parent = elems.ActionContainer

				local badgeCorner = Instance.new("UICorner")
				badgeCorner.CornerRadius = Theme.Corner.Medium
				badgeCorner.Parent = badge

				local badgeStroke = Instance.new("UIStroke")
				badgeStroke.Color = Theme.Colors.AuraCyan
				badgeStroke.Thickness = 1
				badgeStroke.Parent = badge

				local badgeLabel = Instance.new("TextLabel")
				badgeLabel.Name = "Label"
				badgeLabel.Size = UDim2.new(1, 0, 1, 0)
				badgeLabel.BackgroundTransparency = 1
				badgeLabel.Font = Theme.Fonts.Button
				badgeLabel.TextSize = 13
				badgeLabel.TextColor3 = Theme.Colors.AuraCyan
				badgeLabel.Text = "EQUIPPED"
				badgeLabel.Parent = badge

			elseif isOwned then
				-- State 2: OWNED (Equip button)
				elems.Frame.BackgroundColor3 = Color3.fromRGB(28, 30, 38)
				elems.Stroke.Color = Theme.Colors.Border
				elems.Stroke.Thickness = Theme.Stroke.WidthDefault
				elems.TitleLabel.TextColor3 = Theme.Colors.TextPrimary

				local equipBtn = Instance.new("TextButton")
				equipBtn.Name = "EquipButton"
				equipBtn.Size = UDim2.new(1, 0, 1, 0)
				equipBtn.BackgroundColor3 = Theme.Colors.ButtonSecondary
				equipBtn.AutoButtonColor = false
				equipBtn.Text = ""
				equipBtn.Parent = elems.ActionContainer

				local btnCorner = Instance.new("UICorner")
				btnCorner.CornerRadius = Theme.Corner.Medium
				btnCorner.Parent = equipBtn

				local btnStroke = Instance.new("UIStroke")
				btnStroke.Color = Theme.Colors.AuraEmerald
				btnStroke.Thickness = Theme.Stroke.WidthDefault
				btnStroke.Parent = equipBtn

				local btnScale = Instance.new("UIScale")
				btnScale.Scale = 1
				btnScale.Parent = equipBtn

				local btnLabel = Instance.new("TextLabel")
				btnLabel.Name = "Label"
				btnLabel.Size = UDim2.new(1, -4, 1, 0)
				btnLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
				btnLabel.AnchorPoint = Vector2.new(0.5, 0.5)
				btnLabel.BackgroundTransparency = 1
				btnLabel.Font = Theme.Fonts.Button
				btnLabel.TextSize = 12
				btnLabel.TextColor3 = Theme.Colors.AuraEmerald
				btnLabel.Text = "EQUIP"
				btnLabel.Parent = equipBtn

				local textStroke = Instance.new("UIStroke")
				textStroke.Color = Theme.TextStroke.Color
				textStroke.Thickness = 1.2
				textStroke.Parent = btnLabel

				equipBtn.MouseEnter:Connect(function()
					TweenService:Create(btnScale, Theme.Transitions.Fast, { Scale = 1.05 }):Play()
				end)
				equipBtn.MouseLeave:Connect(function()
					TweenService:Create(btnScale, Theme.Transitions.Fast, { Scale = 1.0 }):Play()
				end)
				equipBtn.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						TweenService:Create(btnScale, Theme.Transitions.Fast, { Scale = 0.94 }):Play()
					end
				end)
				equipBtn.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						TweenService:Create(btnScale, Theme.Transitions.Fast, { Scale = 1.0 }):Play()
					end
				end)

				equipBtn.Activated:Connect(function()
					if onEquipCallback then
						onEquipCallback(tier)
					end
				end)

			else
				-- State 3: BUY (Cost, disabled if unaffordable)
				local canAfford = currentGold >= def.cost
				elems.Frame.BackgroundColor3 = if canAfford then Color3.fromRGB(32, 34, 44) else Color3.fromRGB(20, 22, 28)
				elems.Stroke.Color = if canAfford then Theme.Colors.AuraGold else Theme.Colors.Border
				elems.Stroke.Thickness = if canAfford then Theme.Stroke.WidthThick else Theme.Stroke.WidthDefault
				elems.TitleLabel.TextColor3 = if canAfford then Theme.Colors.TextPrimary else Theme.Colors.TextMuted

				local buyBtn = Instance.new("TextButton")
				buyBtn.Name = "BuyButton"
				buyBtn.Size = UDim2.new(1, 0, 1, 0)
				buyBtn.BackgroundColor3 = if canAfford then Theme.Colors.ButtonPrimary else Color3.fromRGB(42, 28, 28)
				buyBtn.AutoButtonColor = false
				buyBtn.Text = ""
				buyBtn.Parent = elems.ActionContainer

				local btnCorner = Instance.new("UICorner")
				btnCorner.CornerRadius = Theme.Corner.Medium
				btnCorner.Parent = buyBtn

				local btnStroke = Instance.new("UIStroke")
				btnStroke.Color = if canAfford then Theme.Colors.AuraGold else Color3.fromRGB(80, 40, 40)
				btnStroke.Thickness = Theme.Stroke.WidthDefault
				btnStroke.Parent = buyBtn

				local btnScale = Instance.new("UIScale")
				btnScale.Scale = 1
				btnScale.Parent = buyBtn

				local btnLabel = Instance.new("TextLabel")
				btnLabel.Name = "Label"
				btnLabel.Size = UDim2.new(1, -4, 1, 0)
				btnLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
				btnLabel.AnchorPoint = Vector2.new(0.5, 0.5)
				btnLabel.BackgroundTransparency = 1
				btnLabel.Font = Theme.Fonts.Button
				btnLabel.TextSize = 12
				btnLabel.TextColor3 = if canAfford then Theme.Colors.TextGold else Theme.Colors.TextMuted
				btnLabel.Text = ("BUY %s"):format(NumberFormat.format(def.cost))
				btnLabel.Parent = buyBtn

				local textStroke = Instance.new("UIStroke")
				textStroke.Color = Theme.TextStroke.Color
				textStroke.Thickness = 1.2
				textStroke.Parent = btnLabel

				if canAfford then
					buyBtn.MouseEnter:Connect(function()
						TweenService:Create(btnScale, Theme.Transitions.Fast, { Scale = 1.05 }):Play()
					end)
					buyBtn.MouseLeave:Connect(function()
						TweenService:Create(btnScale, Theme.Transitions.Fast, { Scale = 1.0 }):Play()
					end)
					buyBtn.InputBegan:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							TweenService:Create(btnScale, Theme.Transitions.Fast, { Scale = 0.94 }):Play()
						end
					end)
					buyBtn.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							TweenService:Create(btnScale, Theme.Transitions.Fast, { Scale = 1.0 }):Play()
						end
					end)
				end

				buyBtn.Activated:Connect(function()
					if onBuyCallback then
						onBuyCallback(tier)
					end
				end)
			end
		end
	end

	renderCards()

	isOpened = false

	local self: MerchantUIInstance = {
		Open = function(_)
			isOpened = true
			popup:Open()
		end,
		Close = function(_)
			isOpened = false
			popup:Close()
		end,
		Toggle = function(_)
			if isOpened then
				isOpened = false
				popup:Close()
			else
				isOpened = true
				popup:Open()
			end
		end,
		SetData = function(_, tier: number, gold: number, ownedDice: { [string]: boolean })
			currentDiceTier = tier
			currentGold = gold
			currentOwnedDice = ownedDice or { ["1"] = true }
			bannerText.Text = ("Equipped: Tier %d | Available Gold: %s"):format(tier, NumberFormat.format(gold))
			renderCards()
		end,
		SetOnBuy = function(_, callback: (targetTier: number) -> ())
			onBuyCallback = callback
		end,
		SetOnEquip = function(_, callback: (targetTier: number) -> ())
			onEquipCallback = callback
		end,
		Destroy = function(_)
			popup:Destroy()
			if screenGui and screenGui ~= parentGui then
				screenGui:Destroy()
			end
		end,
	}

	return self
end

return MerchantUI
