--!strict
-- RebirthPopup: Mobile-first confirmation dialog for Rebirth progression.
-- Text-only interface (no emojis, no arrow glyphs) styled via Theme tokens.
-- Uses own ScreenGui with DisplayOrder 21, ensuring full camera and tap mobility when closed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Components = Shared:WaitForChild("UI"):WaitForChild("Components")
local Popup = require(Components:WaitForChild("Popup"))
local Button = require(Components:WaitForChild("Button"))

export type RebirthPreviewData = {
	token: string?,
	canAfford: boolean,
	isMaxRebirth: boolean?,
	currentRebirths: number,
	nextRebirths: number,
	cost: number,
	currentGold: number,
	currentGoldMult: number,
	newGoldMult: number,
	currentLuckMult: number?,
	newLuckMult: number?,
	gemsGrant: number,
	currentSlots: number,
	newSlots: number,
	slotChange: number,
}

export type RebirthPopupInstance = {
	Show: (self: RebirthPopupInstance, data: RebirthPreviewData, onConfirm: (token: string) -> ()) -> (),
	ShowError: (self: RebirthPopupInstance, errorMessage: string) -> (),
	Close: (self: RebirthPopupInstance) -> (),
	SetStatus: (self: RebirthPopupInstance, text: string, isError: boolean?) -> (),
	SetBusy: (self: RebirthPopupInstance, isBusy: boolean) -> (),
	Destroy: (self: RebirthPopupInstance) -> (),
}

local RebirthPopup = {}

function RebirthPopup.new(parentGui: Instance): RebirthPopupInstance
	local screenGui: ScreenGui? = nil
	local host: Instance
	if parentGui:IsA("ScreenGui") then
		screenGui = parentGui
		host = parentGui
	elseif parentGui:IsA("GuiObject") then
		host = parentGui
	else
		local sg = parentGui:FindFirstChild("RebirthPopupGui") :: ScreenGui?
		if not sg then
			sg = Instance.new("ScreenGui")
			sg.Name = "RebirthPopupGui"
			sg.ResetOnSpawn = false
			sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			sg.DisplayOrder = 21 -- Rule 7: RebirthPopupGui DisplayOrder = 21
			sg.Enabled = false
			sg.Parent = parentGui
		end
		screenGui = sg
		host = sg
	end

	local onConfirmCallback: ((token: string) -> ())? = nil
	local currentToken: string? = nil
	local isBusy = false

	local popup = Popup.new({
		Title = "Rebirth Chamber",
		Size = UDim2.new(0.88, 0, 0.74, 0),
		MaxWidth = 460,
		MaxHeight = 440,
		Parent = host,
		OnClose = function()
			if screenGui then
				screenGui.Enabled = false
			end
			onConfirmCallback = nil
			currentToken = nil
			isBusy = false
		end,
	})

	local rootContent = popup.Content

	-- Scrollable area for cards (tier, benefits, warning)
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ScrollContent"
	scrollFrame.Size = UDim2.new(1, 0, 1, -74)
	scrollFrame.Position = UDim2.new(0, 0, 0, 0)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 3
	scrollFrame.ScrollBarImageColor3 = Theme.Colors.Border
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = rootContent

	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.FillDirection = Enum.FillDirection.Vertical
	scrollLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollLayout.Padding = UDim.new(0, 8)
	scrollLayout.Parent = scrollFrame

	local scrollPadding = Instance.new("UIPadding")
	scrollPadding.PaddingRight = UDim.new(0, 4)
	scrollPadding.Parent = scrollFrame

	-- 1. Tier Progression Header Card
	local tierCard = Instance.new("Frame")
	tierCard.Name = "TierCard"
	tierCard.Size = UDim2.new(1, 0, 0, 40)
	tierCard.BackgroundColor3 = Theme.Colors.BackgroundCard
	tierCard.BorderSizePixel = 0
	tierCard.LayoutOrder = 1
	tierCard.Parent = scrollFrame

	local tierCardCorner = Instance.new("UICorner")
	tierCardCorner.CornerRadius = Theme.Corner.Medium
	tierCardCorner.Parent = tierCard

	local tierCardStroke = Instance.new("UIStroke")
	tierCardStroke.Color = Theme.Colors.Border
	tierCardStroke.Thickness = Theme.Stroke.WidthDefault
	tierCardStroke.Parent = tierCard

	local tierLabel = Instance.new("TextLabel")
	tierLabel.Name = "TierLabel"
	tierLabel.Size = UDim2.new(1, -16, 1, 0)
	tierLabel.Position = UDim2.new(0, 8, 0, 0)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Font = Theme.Fonts.Title
	tierLabel.TextSize = 15
	tierLabel.TextColor3 = Theme.Colors.AuraCyan
	tierLabel.TextXAlignment = Enum.TextXAlignment.Center
	tierLabel.Text = "Rebirth 0 to Rebirth 1"
	tierLabel.Parent = tierCard

	-- 2. Benefits Overview Card
	local benefitsCard = Instance.new("Frame")
	benefitsCard.Name = "BenefitsCard"
	benefitsCard.Size = UDim2.new(1, 0, 0, 126)
	benefitsCard.BackgroundColor3 = Theme.Colors.BackgroundCard
	benefitsCard.BorderSizePixel = 0
	benefitsCard.LayoutOrder = 2
	benefitsCard.Parent = scrollFrame

	local benefitsCorner = Instance.new("UICorner")
	benefitsCorner.CornerRadius = Theme.Corner.Medium
	benefitsCorner.Parent = benefitsCard

	local benefitsStroke = Instance.new("UIStroke")
	benefitsStroke.Color = Theme.Colors.Border
	benefitsStroke.Thickness = Theme.Stroke.WidthDefault
	benefitsStroke.Parent = benefitsCard

	local benefitsList = Instance.new("UIListLayout")
	benefitsList.FillDirection = Enum.FillDirection.Vertical
	benefitsList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	benefitsList.VerticalAlignment = Enum.VerticalAlignment.Center
	benefitsList.SortOrder = Enum.SortOrder.LayoutOrder
	benefitsList.Padding = UDim.new(0, 4)
	benefitsList.Parent = benefitsCard

	local benefitsPadding = Instance.new("UIPadding")
	benefitsPadding.PaddingLeft = UDim.new(0, 12)
	benefitsPadding.PaddingRight = UDim.new(0, 12)
	benefitsPadding.PaddingTop = UDim.new(0, 6)
	benefitsPadding.PaddingBottom = UDim.new(0, 6)
	benefitsPadding.Parent = benefitsCard

	local multLabel = Instance.new("TextLabel")
	multLabel.Name = "MultLabel"
	multLabel.Size = UDim2.new(1, 0, 0, 24)
	multLabel.BackgroundTransparency = 1
	multLabel.Font = Theme.Fonts.Body
	multLabel.TextSize = 13
	multLabel.TextColor3 = Theme.Colors.TextPrimary
	multLabel.TextXAlignment = Enum.TextXAlignment.Left
	multLabel.Text = "Gold Multiplier: 1.0x to 1.5x (+0.5x)"
	multLabel.LayoutOrder = 1
	multLabel.Parent = benefitsCard

	local luckLabel = Instance.new("TextLabel")
	luckLabel.Name = "LuckLabel"
	luckLabel.Size = UDim2.new(1, 0, 0, 24)
	luckLabel.BackgroundTransparency = 1
	luckLabel.Font = Theme.Fonts.Body
	luckLabel.TextSize = 13
	luckLabel.TextColor3 = Theme.Colors.AuraCyan
	luckLabel.TextXAlignment = Enum.TextXAlignment.Left
	luckLabel.Text = "Luck Multiplier: 1.0x to 1.5x (+0.5x)"
	luckLabel.LayoutOrder = 2
	luckLabel.Parent = benefitsCard

	local gemsLabel = Instance.new("TextLabel")
	gemsLabel.Name = "GemsLabel"
	gemsLabel.Size = UDim2.new(1, 0, 0, 24)
	gemsLabel.BackgroundTransparency = 1
	gemsLabel.Font = Theme.Fonts.Body
	gemsLabel.TextSize = 13
	gemsLabel.TextColor3 = Theme.Colors.AuraGold
	gemsLabel.TextXAlignment = Enum.TextXAlignment.Left
	gemsLabel.Text = "Gem Reward: +100 Gems"
	gemsLabel.LayoutOrder = 3
	gemsLabel.Parent = benefitsCard

	local slotsLabel = Instance.new("TextLabel")
	slotsLabel.Name = "SlotsLabel"
	slotsLabel.Size = UDim2.new(1, 0, 0, 24)
	slotsLabel.BackgroundTransparency = 1
	slotsLabel.Font = Theme.Fonts.Body
	slotsLabel.TextSize = 13
	slotsLabel.TextColor3 = Theme.Colors.AuraEmerald
	slotsLabel.TextXAlignment = Enum.TextXAlignment.Left
	slotsLabel.Text = "Pedestal Slots: 4 (No change)"
	slotsLabel.LayoutOrder = 4
	slotsLabel.Parent = benefitsCard

	-- 3. Reset Warning Banner
	local warningFrame = Instance.new("Frame")
	warningFrame.Name = "WarningFrame"
	warningFrame.Size = UDim2.new(1, 0, 0, 52)
	warningFrame.BackgroundColor3 = Theme.Colors.PanelBackground
	warningFrame.BorderSizePixel = 0
	warningFrame.LayoutOrder = 3
	warningFrame.Parent = scrollFrame

	local warningCorner = Instance.new("UICorner")
	warningCorner.CornerRadius = Theme.Corner.Small
	warningCorner.Parent = warningFrame

	local warningStroke = Instance.new("UIStroke")
	warningStroke.Color = Theme.Colors.AuraCrimson
	warningStroke.Thickness = Theme.Stroke.WidthThin
	warningStroke.Parent = warningFrame

	local warningLabel = Instance.new("TextLabel")
	warningLabel.Name = "WarningLabel"
	warningLabel.Size = UDim2.new(1, -16, 1, -8)
	warningLabel.Position = UDim2.new(0, 8, 0, 4)
	warningLabel.BackgroundTransparency = 1
	warningLabel.Font = Theme.Fonts.Body
	warningLabel.TextSize = 11
	warningLabel.TextColor3 = Theme.Colors.TextPrimary
	warningLabel.TextWrapped = true
	warningLabel.TextXAlignment = Enum.TextXAlignment.Left
	warningLabel.TextYAlignment = Enum.TextYAlignment.Center
	warningLabel.Text = "WARNING: Rebirth will reset your GOLD to 0. All Dice, Swords, Gems, Tokens, and Pedestals are kept."
	warningLabel.Parent = warningFrame

	-- Pinned bottom container (outside scroll area)
	local bottomContainer = Instance.new("Frame")
	bottomContainer.Name = "BottomContainer"
	bottomContainer.Size = UDim2.new(1, 0, 0, 72)
	bottomContainer.Position = UDim2.new(0, 0, 1, 0)
	bottomContainer.AnchorPoint = Vector2.new(0, 1)
	bottomContainer.BackgroundTransparency = 1
	bottomContainer.Parent = rootContent

	local bottomLayout = Instance.new("UIListLayout")
	bottomLayout.FillDirection = Enum.FillDirection.Vertical
	bottomLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	bottomLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	bottomLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bottomLayout.Padding = UDim.new(0, 2)
	bottomLayout.Parent = bottomContainer

	-- 4. Cost Label (Pinned)
	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "CostLabel"
	costLabel.Size = UDim2.new(1, 0, 0, 18)
	costLabel.BackgroundTransparency = 1
	costLabel.Font = Theme.Fonts.Title
	costLabel.TextSize = 13
	costLabel.TextColor3 = Theme.Colors.TextGold
	costLabel.TextXAlignment = Enum.TextXAlignment.Center
	costLabel.Text = "Cost: 250K Gold"
	costLabel.LayoutOrder = 1
	costLabel.Parent = bottomContainer

	-- 5. Status / Error Message (Pinned)
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, 0, 0, 14)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Theme.Fonts.Body
	statusLabel.TextSize = 11
	statusLabel.TextColor3 = Theme.Colors.AuraCrimson
	statusLabel.TextXAlignment = Enum.TextXAlignment.Center
	statusLabel.Text = ""
	statusLabel.LayoutOrder = 2
	statusLabel.Parent = bottomContainer

	-- 6. Confirm and Cancel Buttons (Pinned)
	local actionButtonContainer = Instance.new("Frame")
	actionButtonContainer.Name = "ActionButtonContainer"
	actionButtonContainer.Size = UDim2.new(1, 0, 0, 36)
	actionButtonContainer.BackgroundTransparency = 1
	actionButtonContainer.LayoutOrder = 3
	actionButtonContainer.Parent = bottomContainer

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.Padding = UDim.new(0, 8)
	buttonLayout.Parent = actionButtonContainer

	local cancelBtn = Button.new({
		Name = "CancelButton",
		Text = "CANCEL",
		Size = UDim2.new(0.35, -4, 1, 0),
		BackgroundColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.Border,
		TextColor = Theme.Colors.TextSecondary,
		CornerRadius = Theme.Corner.Medium,
		LayoutOrder = 1,
		Parent = actionButtonContainer,
		OnClick = function()
			popup:Close()
		end,
	})

	local confirmBtn = Button.new({
		Name = "ConfirmRebirthButton",
		Text = "REBIRTH",
		Size = UDim2.new(0.65, -4, 1, 0),
		BackgroundColor = Theme.Colors.ButtonPrimary,
		BorderColor = Theme.Colors.AuraPurple,
		TextColor = Theme.Colors.TextPrimary,
		CornerRadius = Theme.Corner.Medium,
		LayoutOrder = 2,
		Parent = actionButtonContainer,
		OnClick = function()
			if isBusy then
				return
			end
			if not currentToken then
				statusLabel.TextColor3 = Theme.Colors.AuraCrimson
				statusLabel.Text = "Cannot rebirth: Not enough Gold or preview expired."
				return
			end
			if onConfirmCallback then
				isBusy = true
				statusLabel.TextColor3 = Theme.Colors.AuraCyan
				statusLabel.Text = "Executing rebirth..."
				onConfirmCallback(currentToken)
			end
		end,
	})

	local confirmTitle = confirmBtn.Instance:FindFirstChild("Title", true) :: TextLabel?
	if confirmTitle then
		confirmTitle.TextScaled = true
	end

	local cancelTitle = cancelBtn.Instance:FindFirstChild("Title", true) :: TextLabel?
	if cancelTitle then
		cancelTitle.TextScaled = true
	end

	local self: RebirthPopupInstance = {
		Show = function(_, data: RebirthPreviewData, onConfirm: (token: string) -> ())
			currentToken = data.token
			onConfirmCallback = onConfirm
			isBusy = false
			statusLabel.Text = ""

			tierLabel.TextColor3 = Theme.Colors.AuraCyan

			if data.isMaxRebirth then
				tierLabel.Text = string.format("Current: Rebirth %d (MAX TIER)", data.currentRebirths)
				multLabel.Text = string.format("Gold Multiplier: %.1fx (Maximum)", data.currentGoldMult)
				luckLabel.Text = string.format("Luck Multiplier: %.1fx (Maximum)", data.currentLuckMult or data.currentGoldMult)
				gemsLabel.Text = "Gem Reward: None (Maxed)"
				slotsLabel.Text = string.format("Pedestal Slots: %d", data.currentSlots)
				slotsLabel.TextColor3 = Theme.Colors.TextSecondary
				costLabel.Text = "Maximum Rebirth Tier Reached"
				warningLabel.Text = "You have unlocked the maximum rebirth tier! No further rebirths available."

				confirmBtn:SetEnabled(false)
				confirmBtn:SetText("MAX REBIRTH REACHED")
			else
				tierLabel.Text = string.format("Current: Rebirth %d to Rebirth %d", data.currentRebirths, data.nextRebirths)
				multLabel.Text = string.format("Gold Multiplier: %.1fx to %.1fx (+%.1fx)", data.currentGoldMult, data.newGoldMult, data.newGoldMult - data.currentGoldMult)
				local curLuck = data.currentLuckMult or 1.0
				local nxtLuck = data.newLuckMult or 1.0
				luckLabel.Text = string.format("Luck Multiplier: %.1fx to %.1fx (+%.1fx)", curLuck, nxtLuck, nxtLuck - curLuck)
				gemsLabel.Text = string.format("Gem Reward: +%s Gems", NumberFormat.format(data.gemsGrant))

				if data.slotChange > 0 then
					slotsLabel.Text = string.format("Pedestal Slots: %d to %d (+%d Slot)", data.currentSlots, data.newSlots, data.slotChange)
					slotsLabel.TextColor3 = Theme.Colors.AuraEmerald
				else
					slotsLabel.Text = string.format("Pedestal Slots: %d (No change)", data.currentSlots)
					slotsLabel.TextColor3 = Theme.Colors.TextSecondary
				end

				costLabel.Text = string.format("Cost: %s Gold (You have: %s Gold)", NumberFormat.format(data.cost), NumberFormat.format(data.currentGold))
				warningLabel.Text = "WARNING: Rebirth will reset your GOLD to 0. All Dice, Swords, Gems, Tokens, and Pedestals are kept."

				-- Rule 1: If player cannot afford, button is disabled and shows disabled text
				if not data.canAfford or not data.token then
					confirmBtn:SetEnabled(false)
					confirmBtn:SetText("LOCKED - NEED MORE GOLD")
				else
					confirmBtn:SetEnabled(true)
					confirmBtn:SetText("REBIRTH")
				end
			end

			if screenGui then
				screenGui.Enabled = true
			end
			popup:Open()
		end,

		ShowError = function(_, errorMessage: string)
			currentToken = nil
			onConfirmCallback = nil
			isBusy = false

			tierLabel.Text = "Rebirth Preview Error"
			tierLabel.TextColor3 = Theme.Colors.AuraCrimson

			multLabel.Text = "Unable to fetch rebirth preview."
			gemsLabel.Text = "Please try again later."
			slotsLabel.Text = ""

			warningLabel.Text = errorMessage
			costLabel.Text = "Error Loading Preview"
			statusLabel.TextColor3 = Theme.Colors.AuraCrimson
			statusLabel.Text = errorMessage

			confirmBtn:SetEnabled(false)
			confirmBtn:SetText("ERROR")

			if screenGui then
				screenGui.Enabled = true
			end
			popup:Open()
		end,

		Close = function(_)
			popup:Close()
		end,

		SetStatus = function(_, text: string, isError: boolean?)
			statusLabel.TextColor3 = if isError then Theme.Colors.AuraCrimson else Theme.Colors.AuraCyan
			statusLabel.Text = text
		end,

		SetBusy = function(_, busy: boolean)
			isBusy = busy
		end,

		Destroy = function(_)
			cancelBtn:Destroy()
			confirmBtn:Destroy()
			popup:Destroy()
			if screenGui then
				screenGui:Destroy()
			end
		end,
	}

	return self
end

return RebirthPopup
