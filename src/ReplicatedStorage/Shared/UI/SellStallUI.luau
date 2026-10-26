--!strict
-- SellStallUI: Modal panel for the Plaza Sell Stall.
-- Features Sell All with server preview & confirmation dialog, and a link to Auto-Sell settings.
-- Built mobile-first inside its own ScreenGui using the shared Popup component and Theme tokens.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local Components = Shared:WaitForChild("UI"):WaitForChild("Components")
local Popup = require(Components:WaitForChild("Popup"))
local Button = require(Components:WaitForChild("Button"))

export type SellPreviewData = {
	count: number,
	totalGold: number,
	gradedOrEnchantedCount: number,
	token: string?,
}

export type SellStallUIInstance = {
	Open: (self: SellStallUIInstance) -> (),
	Close: (self: SellStallUIInstance) -> (),
	Toggle: (self: SellStallUIInstance) -> (),
	IsOpen: (self: SellStallUIInstance) -> boolean,
	IsConfirmOpen: (self: SellStallUIInstance) -> boolean,
	SetPreviewData: (self: SellStallUIInstance, data: SellPreviewData?) -> (),
	SetBusy: (self: SellStallUIInstance, isBusy: boolean) -> (),
	ShowResult: (self: SellStallUIInstance, message: string, isSuccess: boolean) -> (),
	SetOnRequestPreview: (self: SellStallUIInstance, callback: () -> ()) -> (),
	SetOnConfirmSellAll: (self: SellStallUIInstance, callback: () -> ()) -> (),
	SetOnOpenAutoSell: (self: SellStallUIInstance, callback: () -> ()) -> (),
	Destroy: (self: SellStallUIInstance) -> (),
}

local SellStallUI = {}

function SellStallUI.new(parentGui: Instance): SellStallUIInstance
	local screenGui: ScreenGui
	if parentGui:IsA("ScreenGui") then
		screenGui = parentGui
	else
		local existing = parentGui:FindFirstChild("AuraBladeSellStallGui")
		if existing and existing:IsA("ScreenGui") then
			existing:Destroy()
		end
		local sg = Instance.new("ScreenGui")
		sg.Name = "AuraBladeSellStallGui"
		sg.ResetOnSpawn = false
		sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		sg.DisplayOrder = 12
		sg.Parent = parentGui
		screenGui = sg
	end

	local isOpened = false
	local isConfirmOpened = false
	local currentPreview: SellPreviewData? = nil
	local onRequestPreviewCallback: (() -> ())? = nil
	local onConfirmSellAllCallback: (() -> ())? = nil
	local onOpenAutoSellCallback: (() -> ())? = nil

	-- Main Sell Stall Popup
	local popup = Popup.new({
		Title = "Sell Stall",
		Size = UDim2.new(0.88, 0, 0.65, 0),
		MaxWidth = 480,
		MaxHeight = 380,
		Parent = screenGui,
		OnClose = function()
			isOpened = false
			isConfirmOpened = false
		end,
	})

	local rootContent = popup.Content

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, 10)
	layout.Parent = rootContent

	-- Info banner card
	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.Size = UDim2.new(1, 0, 0, 54)
	banner.BackgroundColor3 = Theme.Colors.BackgroundCard
	banner.BackgroundTransparency = 0.2
	banner.Parent = rootContent

	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = Theme.Corner.Medium
	bannerCorner.Parent = banner

	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Color = Theme.Colors.BorderSubtle
	bannerStroke.Thickness = Theme.Stroke.WidthDefault
	bannerStroke.Parent = banner

	local bannerText = Instance.new("TextLabel")
	bannerText.Name = "BannerText"
	bannerText.Size = UDim2.new(1, -20, 1, 0)
	bannerText.Position = UDim2.new(0, 10, 0, 0)
	bannerText.BackgroundTransparency = 1
	bannerText.Text = "Liquidate unequipped backpack swords for Gold.\nEquipped, placed, and locked swords are never sold."
	bannerText.TextColor3 = Theme.Colors.TextSecondary
	bannerText.Font = Theme.Fonts.Body
	bannerText.TextSize = 13
	bannerText.TextWrapped = true
	bannerText.TextYAlignment = Enum.TextYAlignment.Center
	bannerText.Parent = banner

	-- Sell All card
	local sellAllCard = Instance.new("Frame")
	sellAllCard.Name = "SellAllCard"
	sellAllCard.Size = UDim2.new(1, 0, 0, 140)
	sellAllCard.BackgroundColor3 = Theme.Colors.BackgroundCard
	sellAllCard.BackgroundTransparency = 0.1
	sellAllCard.Parent = rootContent

	local sellAllCorner = Instance.new("UICorner")
	sellAllCorner.CornerRadius = Theme.Corner.Medium
	sellAllCorner.Parent = sellAllCard

	local sellAllStroke = Instance.new("UIStroke")
	sellAllStroke.Color = Theme.Colors.Border
	sellAllStroke.Thickness = Theme.Stroke.WidthDefault
	sellAllStroke.Parent = sellAllCard

	local previewStatsLabel = Instance.new("TextLabel")
	previewStatsLabel.Name = "PreviewStats"
	previewStatsLabel.Size = UDim2.new(1, -24, 0, 36)
	previewStatsLabel.Position = UDim2.new(0, 12, 0, 12)
	previewStatsLabel.BackgroundTransparency = 1
	previewStatsLabel.Font = Theme.Fonts.Title
	previewStatsLabel.TextSize = 15
	previewStatsLabel.TextColor3 = Theme.Colors.TextPrimary
	previewStatsLabel.Text = "Checking backpack..."
	previewStatsLabel.TextXAlignment = Enum.TextXAlignment.Center
	previewStatsLabel.Parent = sellAllCard

	local previewWarningLabel = Instance.new("TextLabel")
	previewWarningLabel.Name = "PreviewWarning"
	previewWarningLabel.Size = UDim2.new(1, -24, 0, 20)
	previewWarningLabel.Position = UDim2.new(0, 12, 0, 48)
	previewWarningLabel.BackgroundTransparency = 1
	previewWarningLabel.Font = Theme.Fonts.Body
	previewWarningLabel.TextSize = 12
	previewWarningLabel.TextColor3 = Theme.Colors.TextMuted
	previewWarningLabel.Text = ""
	previewWarningLabel.TextXAlignment = Enum.TextXAlignment.Center
	previewWarningLabel.Parent = sellAllCard

	-- Big Sell All Button
	local sellAllButton = Button.new({
		Name = "SellAllButton",
		Text = "SELL ALL UNLOCKED",
		Size = UDim2.new(1, -32, 0, 44),
		Position = UDim2.new(0.5, 0, 1, -12),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor = Theme.Colors.ButtonClose,
		BorderColor = Theme.Colors.AuraCrimson,
		TextColor = Theme.Colors.TextPrimary,
		CornerRadius = Theme.Corner.Medium,
		Parent = sellAllCard,
	})

	-- Link to Auto-Sell Rules Button
	local autoSellLinkBtn = Button.new({
		Name = "AutoSellLinkButton",
		Text = "CONFIGURE AUTO-SELL RULES",
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.AuraEmerald,
		TextColor = Theme.Colors.AuraEmerald,
		CornerRadius = Theme.Corner.Medium,
		Parent = rootContent,
		OnClick = function()
			if onOpenAutoSellCallback then
				onOpenAutoSellCallback()
			end
		end,
	})

	-- Result/status feedback label
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, 0, 0, 24)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Theme.Fonts.Body
	statusLabel.TextSize = 13
	statusLabel.TextColor3 = Theme.Colors.AuraEmerald
	statusLabel.Text = ""
	statusLabel.Parent = rootContent

	-- Sell All Confirmation Sub-Popup
	local confirmPopup = Popup.new({
		Title = "Confirm Sell All",
		Size = UDim2.new(0.75, 0, 0.46, 0),
		MaxWidth = 400,
		MaxHeight = 260,
		Parent = screenGui,
		OnClose = function()
			isConfirmOpened = false
		end,
	})

	local confirmContent = confirmPopup.Content

	local confirmText = Instance.new("TextLabel")
	confirmText.Name = "ConfirmDesc"
	confirmText.Size = UDim2.new(1, -20, 0, 70)
	confirmText.Position = UDim2.new(0.5, 0, 0, 8)
	confirmText.AnchorPoint = Vector2.new(0.5, 0)
	confirmText.BackgroundTransparency = 1
	confirmText.Font = Theme.Fonts.Body
	confirmText.TextSize = 13
	confirmText.TextColor3 = Theme.Colors.TextPrimary
	confirmText.TextWrapped = true
	confirmText.TextYAlignment = Enum.TextYAlignment.Center
	confirmText.Text = ""
	confirmText.Parent = confirmContent

	local confirmWarningText = Instance.new("TextLabel")
	confirmWarningText.Name = "ConfirmWarning"
	confirmWarningText.Size = UDim2.new(1, -20, 0, 24)
	confirmWarningText.Position = UDim2.new(0.5, 0, 0, 82)
	confirmWarningText.AnchorPoint = Vector2.new(0.5, 0)
	confirmWarningText.BackgroundTransparency = 1
	confirmWarningText.Font = Theme.Fonts.Title
	confirmWarningText.TextSize = 12
	confirmWarningText.TextColor3 = Theme.Colors.AuraCrimson
	confirmWarningText.Text = ""
	confirmWarningText.Parent = confirmContent

	local confirmActions = Instance.new("Frame")
	confirmActions.Name = "ConfirmActions"
	confirmActions.Size = UDim2.new(1, -20, 0, 40)
	confirmActions.Position = UDim2.new(0.5, 0, 1, -8)
	confirmActions.AnchorPoint = Vector2.new(0.5, 1)
	confirmActions.BackgroundTransparency = 1
	confirmActions.Parent = confirmContent

	local confirmActionsLayout = Instance.new("UIListLayout")
	confirmActionsLayout.FillDirection = Enum.FillDirection.Horizontal
	confirmActionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	confirmActionsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	confirmActionsLayout.Padding = UDim.new(0, 12)
	confirmActionsLayout.Parent = confirmActions

	local cancelConfirmBtn = Button.new({
		Name = "CancelConfirmButton",
		Text = "CANCEL",
		Size = UDim2.new(0.46, 0, 1, 0),
		BackgroundColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.Border,
		TextColor = Theme.Colors.TextPrimary,
		Parent = confirmActions,
		OnClick = function()
			isConfirmOpened = false
			confirmPopup:Close()
		end,
	})

	local proceedSellBtn = Button.new({
		Name = "ProceedSellButton",
		Text = "YES, SELL ALL",
		Size = UDim2.new(0.46, 0, 1, 0),
		BackgroundColor = Theme.Colors.ButtonClose,
		BorderColor = Theme.Colors.AuraCrimson,
		TextColor = Theme.Colors.TextPrimary,
		Parent = confirmActions,
		OnClick = function()
			isConfirmOpened = false
			confirmPopup:Close()
			if onConfirmSellAllCallback then
				onConfirmSellAllCallback()
			end
		end,
	})

	local function refreshPreviewUI()
		if not currentPreview then
			previewStatsLabel.Text = "Checking backpack..."
			previewStatsLabel.TextColor3 = Theme.Colors.TextMuted
			previewWarningLabel.Text = ""
			sellAllButton:SetEnabled(false)
			sellAllButton:SetText("SELL ALL UNLOCKED")
			return
		end

		if currentPreview.count <= 0 then
			previewStatsLabel.Text = "No sellable swords in backpack."
			previewStatsLabel.TextColor3 = Theme.Colors.TextMuted
			previewWarningLabel.Text = "Equipped, placed, and locked swords cannot be sold."
			previewWarningLabel.TextColor3 = Theme.Colors.TextMuted
			sellAllButton:SetEnabled(false)
			sellAllButton:SetText("NO SWORDS TO SELL")
			sellAllButton:SetBorderColor(Theme.Colors.BorderSubtle)
		else
			previewStatsLabel.Text = ("Sell %d Swords for +%s Gold"):format(
				currentPreview.count,
				NumberFormat.format(currentPreview.totalGold)
			)
			previewStatsLabel.TextColor3 = Theme.Colors.TextGold

			if currentPreview.gradedOrEnchantedCount > 0 then
				previewWarningLabel.Text = ("⚠️ %d sword(s) have Grades or Enchants!"):format(currentPreview.gradedOrEnchantedCount)
				previewWarningLabel.TextColor3 = Theme.Colors.AuraCrimson
			else
				previewWarningLabel.Text = "✓ No graded or enchanted swords in batch."
				previewWarningLabel.TextColor3 = Theme.Colors.AuraEmerald
			end

			sellAllButton:SetEnabled(true)
			sellAllButton:SetText(("SELL ALL (%d SWORDS)"):format(currentPreview.count))
			sellAllButton:SetBorderColor(Theme.Colors.AuraCrimson)
		end
	end

	sellAllButton.Instance.Activated:Connect(function()
		if not currentPreview or currentPreview.count <= 0 then
			return
		end

		confirmText.Text = ("Are you sure you want to sell %d unlocked swords for +%s Gold?\n\nEquipped, placed, and locked swords are safe."):format(
			currentPreview.count,
			NumberFormat.format(currentPreview.totalGold)
		)

		if currentPreview.gradedOrEnchantedCount > 0 then
			confirmWarningText.Text = ("⚠️ Warning: %d of these swords have a Grade or Enchant!"):format(currentPreview.gradedOrEnchantedCount)
		else
			confirmWarningText.Text = ""
		end

		isConfirmOpened = true
		confirmPopup:Open()
	end)

	local self: SellStallUIInstance = {
		Open = function(_)
			isOpened = true
			isConfirmOpened = false
			statusLabel.Text = ""
			popup:Open()
			if onRequestPreviewCallback then
				onRequestPreviewCallback()
			end
		end,
		Close = function(_)
			isOpened = false
			isConfirmOpened = false
			confirmPopup:Close()
			popup:Close()
		end,
		Toggle = function(this)
			if isOpened then
				this:Close()
			else
				this:Open()
			end
		end,
		IsOpen = function(_)
			return isOpened
		end,
		IsConfirmOpen = function(_)
			return isConfirmOpened
		end,
		SetPreviewData = function(_, data: SellPreviewData?)
			currentPreview = data
			refreshPreviewUI()
		end,
		SetBusy = function(_, isBusy: boolean)
			if isBusy then
				sellAllButton:SetEnabled(false)
				sellAllButton:SetText("SELLING...")
			else
				refreshPreviewUI()
			end
		end,
		ShowResult = function(_, message: string, isSuccess: boolean)
			statusLabel.Text = message
			statusLabel.TextColor3 = if isSuccess then Theme.Colors.AuraEmerald else Theme.Colors.AuraCrimson
			task.delay(4, function()
				if statusLabel.Text == message then
					statusLabel.Text = ""
				end
			end)
		end,
		SetOnRequestPreview = function(_, callback)
			onRequestPreviewCallback = callback
		end,
		SetOnConfirmSellAll = function(_, callback)
			onConfirmSellAllCallback = callback
		end,
		SetOnOpenAutoSell = function(_, callback)
			onOpenAutoSellCallback = callback
		end,
		Destroy = function(_)
			isOpened = false
			sellAllButton:Destroy()
			autoSellLinkBtn:Destroy()
			cancelConfirmBtn:Destroy()
			proceedSellBtn:Destroy()
			confirmPopup:Destroy()
			popup:Destroy()
			if screenGui and screenGui.Parent then
				screenGui:Destroy()
			end
		end,
	}

	return self
end

return SellStallUI
