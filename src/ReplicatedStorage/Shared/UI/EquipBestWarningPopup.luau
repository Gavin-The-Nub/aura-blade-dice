--!strict
-- EquipBestWarningPopup: Mobile-first confirmation dialog shown when Equip Best
-- would unequip or unplace any blessed sword. Displays leaving blessed swords,
-- newly active blessed swords, and net changes across blessing families.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Components = Shared:WaitForChild("UI"):WaitForChild("Components")
local Popup = require(Components:WaitForChild("Popup"))
local Button = require(Components:WaitForChild("Button"))
local BlessingBadge = require(Components:WaitForChild("BlessingBadge"))

export type LeavingSwordInfo = {
	uid: string,
	swordName: string,
	slot: string,
	blessing: string,
	family: string,
	badgeColor: string?,
	effectText: string?,
}

export type PreviewData = {
	token: string,
	leavingSwords: { LeavingSwordInfo }?,
	becomingActiveSwords: { LeavingSwordInfo }?,
	netChanges: {
		Fortune: number?,
		Greed: number?,
		Grade: number?,
		Enchant: number?,
		SwiftfootWalk: number?,
		SwiftfootTap: number?,
	}?,
}

export type EquipBestWarningPopupInstance = {
	Show: (self: EquipBestWarningPopupInstance, data: PreviewData, onConfirm: (token: string) -> ()) -> (),
	Close: (self: EquipBestWarningPopupInstance) -> (),
	SetBusy: (self: EquipBestWarningPopupInstance, isBusy: boolean) -> (),
	Destroy: (self: EquipBestWarningPopupInstance) -> (),
}

local EquipBestWarningPopup = {}

function EquipBestWarningPopup.new(parentGui: Instance): EquipBestWarningPopupInstance
	local screenGui: ScreenGui
	if parentGui:IsA("ScreenGui") then
		screenGui = parentGui
	else
		local sg = Instance.new("ScreenGui")
		sg.Name = "EquipBestWarningGui"
		sg.ResetOnSpawn = false
		sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		sg.DisplayOrder = 20
		sg.Enabled = false
		sg.Parent = parentGui
		screenGui = sg
	end

	local onConfirmCallback: ((token: string) -> ())? = nil
	local currentToken: string? = nil
	local isBusy = false

	local popup = Popup.new({
		Title = "Equip Best Warning",
		Size = UDim2.new(0.88, 0, 0.74, 0),
		MaxWidth = 460,
		MaxHeight = 440,
		Parent = screenGui,
		OnClose = function()
			screenGui.Enabled = false
			onConfirmCallback = nil
			currentToken = nil
		end,
	})

	local rootContent = popup.Content

	-- Header warning note
	local warningDesc = Instance.new("TextLabel")
	warningDesc.Name = "WarningDesc"
	warningDesc.Size = UDim2.new(1, 0, 0, 28)
	warningDesc.Position = UDim2.new(0, 0, 0, 0)
	warningDesc.BackgroundTransparency = 1
	warningDesc.Font = Theme.Fonts.Body
	warningDesc.TextSize = 11
	warningDesc.TextColor3 = Theme.Colors.TextPrimary
	warningDesc.TextWrapped = true
	warningDesc.TextXAlignment = Enum.TextXAlignment.Left
	warningDesc.TextYAlignment = Enum.TextYAlignment.Top
	warningDesc.Text = "Equipping best swords will unequip or unplace the following blessed sword(s):"
	warningDesc.Parent = rootContent

	-- Scrollable area for leaving swords and net changes
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ScrollContent"
	scrollFrame.Size = UDim2.new(1, 0, 1, -80)
	scrollFrame.Position = UDim2.new(0, 0, 0, 32)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 3
	scrollFrame.ScrollBarImageColor3 = Theme.Colors.Border
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = rootContent

	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollLayout.Padding = UDim.new(0, 6)
	scrollLayout.Parent = scrollFrame

	-- Container for dynamic cards
	local cardsContainer = Instance.new("Frame")
	cardsContainer.Name = "CardsContainer"
	cardsContainer.Size = UDim2.new(1, 0, 0, 0)
	cardsContainer.AutomaticSize = Enum.AutomaticSize.Y
	cardsContainer.BackgroundTransparency = 1
	cardsContainer.LayoutOrder = 1
	cardsContainer.Parent = scrollFrame

	local cardsLayout = Instance.new("UIListLayout")
	cardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cardsLayout.Padding = UDim.new(0, 4)
	cardsLayout.Parent = cardsContainer

	-- Container for net changes
	local netChangesFrame = Instance.new("Frame")
	netChangesFrame.Name = "NetChangesFrame"
	netChangesFrame.Size = UDim2.new(1, 0, 0, 0)
	netChangesFrame.AutomaticSize = Enum.AutomaticSize.Y
	netChangesFrame.BackgroundColor3 = Theme.Colors.PanelOverlay
	netChangesFrame.BackgroundTransparency = 0.3
	netChangesFrame.LayoutOrder = 2
	netChangesFrame.Parent = scrollFrame

	local netCorner = Instance.new("UICorner")
	netCorner.CornerRadius = Theme.Corner.Small
	netCorner.Parent = netChangesFrame

	local netStroke = Instance.new("UIStroke")
	netStroke.Color = Theme.Colors.Border
	netStroke.Thickness = Theme.Stroke.WidthThin
	netStroke.Parent = netChangesFrame

	local netPadding = Instance.new("UIPadding")
	netPadding.PaddingTop = UDim.new(0, 6)
	netPadding.PaddingBottom = UDim.new(0, 6)
	netPadding.PaddingLeft = UDim.new(0, 8)
	netPadding.PaddingRight = UDim.new(0, 8)
	netPadding.Parent = netChangesFrame

	local netLayout = Instance.new("UIListLayout")
	netLayout.SortOrder = Enum.SortOrder.LayoutOrder
	netLayout.Padding = UDim.new(0, 3)
	netLayout.Parent = netChangesFrame

	local netTitle = Instance.new("TextLabel")
	netTitle.Name = "NetTitle"
	netTitle.Size = UDim2.new(1, 0, 0, 16)
	netTitle.BackgroundTransparency = 1
	netTitle.Font = Theme.Fonts.Button
	netTitle.TextSize = 11
	netTitle.TextColor3 = Theme.Colors.TextGold
	netTitle.TextXAlignment = Enum.TextXAlignment.Left
	netTitle.Text = "NET BLESSING CHANGES:"
	netTitle.LayoutOrder = 1
	netTitle.Parent = netChangesFrame

	local netRowsContainer = Instance.new("Frame")
	netRowsContainer.Name = "NetRowsContainer"
	netRowsContainer.Size = UDim2.new(1, 0, 0, 0)
	netRowsContainer.AutomaticSize = Enum.AutomaticSize.Y
	netRowsContainer.BackgroundTransparency = 1
	netRowsContainer.LayoutOrder = 2
	netRowsContainer.Parent = netChangesFrame

	local netRowsLayout = Instance.new("UIListLayout")
	netRowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	netRowsLayout.Padding = UDim.new(0, 2)
	netRowsLayout.Parent = netRowsContainer

	-- Bottom Actions Frame
	local actionsFrame = Instance.new("Frame")
	actionsFrame.Name = "ActionsFrame"
	actionsFrame.Size = UDim2.new(1, 0, 0, 38)
	actionsFrame.Position = UDim2.new(0, 0, 1, -38)
	actionsFrame.BackgroundTransparency = 1
	actionsFrame.Parent = rootContent

	local actionsLayout = Instance.new("UIListLayout")
	actionsLayout.FillDirection = Enum.FillDirection.Horizontal
	actionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	actionsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	actionsLayout.Padding = UDim.new(0, 12)
	actionsLayout.Parent = actionsFrame

	local cancelBtn = Button.new({
		Name = "CancelButton",
		Text = "CANCEL",
		Size = UDim2.new(0.46, 0, 1, 0),
		BackgroundColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.Border,
		TextColor = Theme.Colors.TextPrimary,
		Parent = actionsFrame,
		OnClick = function()
			if isBusy then return end
			popup:Close()
		end,
	})

	local confirmBtn = Button.new({
		Name = "ConfirmButton",
		Text = "CONFIRM EQUIP",
		Size = UDim2.new(0.46, 0, 1, 0),
		BackgroundColor = Theme.Colors.ButtonClose,
		BorderColor = Theme.Colors.AuraCrimson,
		TextColor = Theme.Colors.TextPrimary,
		Parent = actionsFrame,
		OnClick = function()
			if isBusy then return end
			if currentToken and onConfirmCallback then
				onConfirmCallback(currentToken)
			end
		end,
	})

	local function clearDynamicContent()
		for _, child in cardsContainer:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for _, child in netRowsContainer:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function formatPercent(fraction: number): string
		local pct = math.floor(fraction * 100 + 0.5)
		if pct > 0 then
			return ("+%d%%"):format(pct)
		else
			return ("%d%%"):format(pct)
		end
	end

	local function addNetRow(label: string, changeFraction: number, order: number)
		local row = Instance.new("Frame")
		row.Name = "NetRow_" .. label
		row.Size = UDim2.new(1, 0, 0, 16)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order
		row.Parent = netRowsContainer

		local labelTxt = Instance.new("TextLabel")
		labelTxt.Name = "Label"
		labelTxt.Size = UDim2.new(0.7, 0, 1, 0)
		labelTxt.BackgroundTransparency = 1
		labelTxt.Font = Theme.Fonts.Body
		labelTxt.TextSize = 11
		labelTxt.TextColor3 = Theme.Colors.TextMuted
		labelTxt.TextXAlignment = Enum.TextXAlignment.Left
		labelTxt.Text = label
		labelTxt.Parent = row

		local valTxt = Instance.new("TextLabel")
		valTxt.Name = "Value"
		valTxt.Size = UDim2.new(0.3, 0, 1, 0)
		valTxt.Position = UDim2.new(0.7, 0, 0, 0)
		valTxt.BackgroundTransparency = 1
		valTxt.Font = Theme.Fonts.Button
		valTxt.TextSize = 11
		valTxt.TextXAlignment = Enum.TextXAlignment.Right
		valTxt.Text = formatPercent(changeFraction)
		valTxt.TextColor3 = if changeFraction < 0 then Theme.Colors.AuraCrimson else Theme.Colors.AuraEmerald
		valTxt.Parent = row
	end

	local function populateData(data: PreviewData)
		clearDynamicContent()

		local order = 1

		-- Leaving swords
		local leaving = data.leavingSwords or {}
		for _, info in ipairs(leaving) do
			local card = Instance.new("Frame")
			card.Name = "LeavingCard_" .. (info.uid or tostring(order))
			card.Size = UDim2.new(1, 0, 0, 44)
			card.BackgroundColor3 = Theme.Colors.PanelOverlay
			card.BackgroundTransparency = 0.4
			card.LayoutOrder = order
			order += 1
			card.Parent = cardsContainer

			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = Theme.Corner.Small
			cardCorner.Parent = card

			local cardStroke = Instance.new("UIStroke")
			cardStroke.Color = Theme.Colors.AuraCrimson
			cardStroke.Thickness = Theme.Stroke.WidthThin
			cardStroke.Transparency = 0.5
			cardStroke.Parent = card

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "SwordName"
			nameLabel.Size = UDim2.new(0.6, -8, 0, 18)
			nameLabel.Position = UDim2.new(0, 8, 0, 4)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Theme.Fonts.Title
			nameLabel.TextSize = 12
			nameLabel.TextColor3 = Theme.Colors.TextPrimary
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Text = info.swordName
			nameLabel.Parent = card

			local slotLabel = Instance.new("TextLabel")
			slotLabel.Name = "SlotOrigin"
			slotLabel.Size = UDim2.new(0.6, -8, 0, 14)
			slotLabel.Position = UDim2.new(0, 8, 0, 22)
			slotLabel.BackgroundTransparency = 1
			slotLabel.Font = Theme.Fonts.Body
			slotLabel.TextSize = 10
			slotLabel.TextColor3 = Theme.Colors.TextGold
			slotLabel.TextXAlignment = Enum.TextXAlignment.Left
			slotLabel.Text = "Leaving " .. (info.slot or "slot")
			slotLabel.Parent = card

			BlessingBadge.new({
				Blessing = info.blessing,
				Position = UDim2.new(1, -8, 0, 6),
				AnchorPoint = Vector2.new(1, 0),
				Parent = card,
			})

			if info.effectText and info.effectText ~= "" then
				local effectLabel = Instance.new("TextLabel")
				effectLabel.Name = "EffectText"
				effectLabel.Size = UDim2.new(0.38, 0, 0, 14)
				effectLabel.Position = UDim2.new(1, -8, 0, 26)
				effectLabel.AnchorPoint = Vector2.new(1, 0)
				effectLabel.BackgroundTransparency = 1
				effectLabel.Font = Theme.Fonts.Body
				effectLabel.TextSize = 9
				effectLabel.TextColor3 = Theme.Colors.TextMuted
				effectLabel.TextXAlignment = Enum.TextXAlignment.Right
				effectLabel.Text = info.effectText
				effectLabel.Parent = card
			end
		end

		-- Becoming active swords
		local becomingActive = data.becomingActiveSwords or {}
		if #becomingActive > 0 then
			local activeHeader = Instance.new("TextLabel")
			activeHeader.Name = "BecomingActiveHeader"
			activeHeader.Size = UDim2.new(1, 0, 0, 16)
			activeHeader.BackgroundTransparency = 1
			activeHeader.Font = Theme.Fonts.Button
			activeHeader.TextSize = 11
			activeHeader.TextColor3 = Theme.Colors.AuraEmerald
			activeHeader.TextXAlignment = Enum.TextXAlignment.Left
			activeHeader.Text = "BECOMING ACTIVE:"
			activeHeader.LayoutOrder = order
			order += 1
			activeHeader.Parent = cardsContainer

			for _, info in ipairs(becomingActive) do
				local card = Instance.new("Frame")
				card.Name = "ActiveCard_" .. (info.uid or tostring(order))
				card.Size = UDim2.new(1, 0, 0, 44)
				card.BackgroundColor3 = Theme.Colors.PanelOverlay
				card.BackgroundTransparency = 0.4
				card.LayoutOrder = order
				order += 1
				card.Parent = cardsContainer

				local cardCorner = Instance.new("UICorner")
				cardCorner.CornerRadius = Theme.Corner.Small
				cardCorner.Parent = card

				local cardStroke = Instance.new("UIStroke")
				cardStroke.Color = Theme.Colors.AuraEmerald
				cardStroke.Thickness = Theme.Stroke.WidthThin
				cardStroke.Transparency = 0.5
				cardStroke.Parent = card

				local nameLabel = Instance.new("TextLabel")
				nameLabel.Name = "SwordName"
				nameLabel.Size = UDim2.new(0.6, -8, 0, 18)
				nameLabel.Position = UDim2.new(0, 8, 0, 4)
				nameLabel.BackgroundTransparency = 1
				nameLabel.Font = Theme.Fonts.Title
				nameLabel.TextSize = 12
				nameLabel.TextColor3 = Theme.Colors.TextPrimary
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
				nameLabel.Text = info.swordName
				nameLabel.Parent = card

				local slotLabel = Instance.new("TextLabel")
				slotLabel.Name = "SlotTarget"
				slotLabel.Size = UDim2.new(0.6, -8, 0, 14)
				slotLabel.Position = UDim2.new(0, 8, 0, 22)
				slotLabel.BackgroundTransparency = 1
				slotLabel.Font = Theme.Fonts.Body
				slotLabel.TextSize = 10
				slotLabel.TextColor3 = Theme.Colors.AuraEmerald
				slotLabel.TextXAlignment = Enum.TextXAlignment.Left
				slotLabel.Text = "Entering " .. (info.slot or "slot")
				slotLabel.Parent = card

				BlessingBadge.new({
					Blessing = info.blessing,
					Position = UDim2.new(1, -8, 0, 6),
					AnchorPoint = Vector2.new(1, 0),
					Parent = card,
				})

				if info.effectText and info.effectText ~= "" then
					local effectLabel = Instance.new("TextLabel")
					effectLabel.Name = "EffectText"
					effectLabel.Size = UDim2.new(0.38, 0, 0, 14)
					effectLabel.Position = UDim2.new(1, -8, 0, 26)
					effectLabel.AnchorPoint = Vector2.new(1, 0)
					effectLabel.BackgroundTransparency = 1
					effectLabel.Font = Theme.Fonts.Body
					effectLabel.TextSize = 9
					effectLabel.TextColor3 = Theme.Colors.TextMuted
					effectLabel.TextXAlignment = Enum.TextXAlignment.Right
					effectLabel.Text = info.effectText
					effectLabel.Parent = card
				end
			end
		end

		-- Net changes
		local net = data.netChanges or {}
		local anyChanges = false

		if net.Fortune and math.abs(net.Fortune) > 0.0001 then
			addNetRow("Fortune (Roll Luck)", net.Fortune, 1)
			anyChanges = true
		end
		if net.Greed and math.abs(net.Greed) > 0.0001 then
			addNetRow("Greed (Gold Multiplier)", net.Greed, 2)
			anyChanges = true
		end
		if net.Grade and math.abs(net.Grade) > 0.0001 then
			addNetRow("Appraiser (Grade Luck)", net.Grade, 3)
			anyChanges = true
		end
		if net.Enchant and math.abs(net.Enchant) > 0.0001 then
			addNetRow("Enchanter (Enchant Luck)", net.Enchant, 4)
			anyChanges = true
		end
		if net.SwiftfootWalk and math.abs(net.SwiftfootWalk) > 0.0001 then
			addNetRow("Swiftfoot (WalkSpeed)", net.SwiftfootWalk, 5)
			anyChanges = true
		end
		if net.SwiftfootTap and math.abs(net.SwiftfootTap) > 0.0001 then
			addNetRow("Swiftfoot (Auto-Tap Speed)", net.SwiftfootTap, 6)
			anyChanges = true
		end

		if not anyChanges then
			local noneLabel = Instance.new("TextLabel")
			noneLabel.Name = "NoNetChanges"
			noneLabel.Size = UDim2.new(1, 0, 0, 16)
			noneLabel.BackgroundTransparency = 1
			noneLabel.Font = Theme.Fonts.Body
			noneLabel.TextSize = 11
			noneLabel.TextColor3 = Theme.Colors.TextMuted
			noneLabel.TextXAlignment = Enum.TextXAlignment.Left
			noneLabel.Text = "No net change in capped family totals."
			noneLabel.Parent = netRowsContainer
		end
	end

	local self: EquipBestWarningPopupInstance = {
		Show = function(_, data: PreviewData, onConfirm: (token: string) -> ())
			currentToken = data.token
			onConfirmCallback = onConfirm
			isBusy = false
			confirmBtn:SetEnabled(true)
			confirmBtn:SetText("CONFIRM EQUIP")
			populateData(data)
			screenGui.Enabled = true
			popup:Open()
		end,
		Close = function(_)
			popup:Close()
			screenGui.Enabled = false
			onConfirmCallback = nil
			currentToken = nil
		end,
		SetBusy = function(_, busy: boolean)
			isBusy = busy
			confirmBtn:SetEnabled(not busy)
			cancelBtn:SetEnabled(not busy)
			confirmBtn:SetText(if busy then "EQUIPPING..." else "CONFIRM EQUIP")
		end,
		Destroy = function(_)
			popup:Destroy()
			screenGui:Destroy()
		end,
	}

	return self
end

return EquipBestWarningPopup
