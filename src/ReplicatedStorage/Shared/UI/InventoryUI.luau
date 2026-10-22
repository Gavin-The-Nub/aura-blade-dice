--!strict
-- InventoryUI: Grid-based sword backpack with rarity colors, stats preview,
-- Equip/Unequip flow, Sell confirmation modal, and Auto-Sell filter chips.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Config = ReplicatedStorage:WaitForChild("Config")
local Swords = require(Config:WaitForChild("Swords"))
local GameConfig = require(Config:WaitForChild("Game"))
local Assets = require(Config:WaitForChild("Assets"))

local Components = Shared:WaitForChild("UI"):WaitForChild("Components")
local Popup = require(Components:WaitForChild("Popup"))
local Button = require(Components:WaitForChild("Button"))
local Panel = require(Components:WaitForChild("Panel"))

export type OwnedSwordEntry = {
	uid: string,
	id: string,
	[string]: any,
}

export type InventoryUIInstance = {
	Open: (self: InventoryUIInstance) -> (),
	Close: (self: InventoryUIInstance) -> (),
	SetData: (
		self: InventoryUIInstance,
		ownedSwords: { OwnedSwordEntry },
		equippedUid: string,
		autoSellRules: { [string]: boolean },
		placedSwords: { [string]: string }?
	) -> (),
	SetOnEquip: (self: InventoryUIInstance, callback: (uid: string) -> ()) -> (),
	SetOnUnequip: (self: InventoryUIInstance, callback: () -> ()) -> (),
	SetOnSell: (self: InventoryUIInstance, callback: (uid: string) -> ()) -> (),
	SetOnToggleAutoSell: (self: InventoryUIInstance, callback: (rarity: string, enabled: boolean) -> ()) -> (),
	SetOnEquipBest: (self: InventoryUIInstance, callback: () -> ()) -> (),
	SetEquipBestBusy: (self: InventoryUIInstance, isBusy: boolean) -> (),
	ShowEquipBestMessage: (self: InventoryUIInstance, message: string, isSuccess: boolean?) -> (),
	Destroy: (self: InventoryUIInstance) -> (),
}

local InventoryUI = {}

-- Cached sword definitions indexed by id
local swordDefMap: { [string]: Swords.SwordDef } = {}
for _, def in Swords do
	swordDefMap[def.id] = def
end

function InventoryUI.new(parentGui: Instance): InventoryUIInstance
	local screenGui: Instance
	local ownsScreenGui = false
	if parentGui:IsA("ScreenGui") then
		screenGui = parentGui
	else
		local sg = Instance.new("ScreenGui")
		sg.Name = "AuraBladeInventoryGui"
		sg.ResetOnSpawn = false
		sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		sg.DisplayOrder = 10
		sg.Parent = parentGui
		screenGui = sg
		ownsScreenGui = true
	end

	-- Main Inventory Modal
	local popup = Popup.new({
		Title = "Swords & Inventory",
		Size = UDim2.new(0.92, 0, 0.85, 0),
		MaxWidth = 680,
		MaxHeight = 520,
		Parent = screenGui,
	})

	local rootContent = popup.Content

	-- Top Bar: Capacity + Equip Best on Row 1; Auto-Sell Header on Row 2; Rarity Chips on Row 3
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 80)
	topBar.Position = UDim2.new(0, 0, 0, 0)
	topBar.BackgroundTransparency = 1
	topBar.Parent = rootContent

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "CountLabel"
	countLabel.Size = UDim2.new(0.5, -60, 0, 24)
	countLabel.Position = UDim2.new(0, 4, 0, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.Font = Theme.Fonts.Button
	countLabel.TextSize = 12
	countLabel.TextColor3 = Theme.Colors.TextSecondary
	countLabel.TextXAlignment = Enum.TextXAlignment.Left
	countLabel.Text = "CAPACITY: 0/50"
	countLabel.Parent = topBar

	-- Forward reference for callback
	local onEquipBestCallback: (() -> ())? = nil

	-- Green "Equip Best" button right-aligned on Row 1 (never overlaps countLabel or Auto-Sell title)
	local equipBestBtn = Button.new({
		Name = "EquipBestButton",
		Text = "EQUIP BEST",
		Size = UDim2.new(0, 110, 0, 24),
		Position = UDim2.new(1, -4, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor = Color3.fromRGB(39, 174, 96),
		BorderColor = Color3.fromRGB(46, 204, 113),
		TextColor = Color3.fromRGB(255, 255, 255),
		CornerRadius = Theme.Corner.Small,
		Parent = topBar,
		OnClick = function()
			if onEquipBestCallback then
				onEquipBestCallback()
			end
		end,
	})

	local autoSellTitle = Instance.new("TextLabel")
	autoSellTitle.Name = "AutoSellTitle"
	autoSellTitle.Size = UDim2.new(1, -8, 0, 16)
	autoSellTitle.Position = UDim2.new(0, 4, 0, 26)
	autoSellTitle.BackgroundTransparency = 1
	autoSellTitle.Font = Theme.Fonts.Button
	autoSellTitle.TextSize = 10
	autoSellTitle.TextColor3 = Theme.Colors.TextGold
	autoSellTitle.TextXAlignment = Enum.TextXAlignment.Left
	autoSellTitle.Text = "AUTO-SELL LOW RARITIES:"
	autoSellTitle.Parent = topBar

	-- Horizontal scrolling container for Auto-Sell rarity chips
	local filterScroll = Instance.new("ScrollingFrame")
	filterScroll.Name = "FilterScroll"
	filterScroll.Size = UDim2.new(1, 0, 0, 34)
	filterScroll.Position = UDim2.new(0, 0, 0, 44)
	filterScroll.BackgroundTransparency = 1
	filterScroll.ScrollBarThickness = 2
	filterScroll.ScrollBarImageColor3 = Theme.Colors.Border
	filterScroll.CanvasSize = UDim2.new(0, 680, 0, 0)
	filterScroll.Parent = topBar

	local filterList = Instance.new("UIListLayout")
	filterList.FillDirection = Enum.FillDirection.Horizontal
	filterList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	filterList.VerticalAlignment = Enum.VerticalAlignment.Center
	filterList.Padding = UDim.new(0, 6)
	filterList.SortOrder = Enum.SortOrder.LayoutOrder
	filterList.Parent = filterScroll

	-- Split Body: Left Grid (64%), Right Inspector (36%)
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 1, -84)
	body.Position = UDim2.new(0, 0, 0, 84)
	body.BackgroundTransparency = 1
	body.Parent = rootContent

	-- Left: Grid container
	local gridPanel = Panel.new({
		Name = "GridPanel",
		Size = UDim2.new(0.63, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor = Theme.Colors.BackgroundDark,
		BorderColor = Theme.Colors.Border,
		Padding = UDim.new(0, 6),
		Parent = body,
	})

	local gridScroll = Instance.new("ScrollingFrame")
	gridScroll.Name = "GridScroll"
	gridScroll.Size = UDim2.new(1, 0, 1, 0)
	gridScroll.BackgroundTransparency = 1
	gridScroll.ScrollBarThickness = 4
	gridScroll.ScrollBarImageColor3 = Theme.Colors.AuraCyan
	gridScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	gridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	gridScroll.Parent = gridPanel.Content

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 72, 0, 80)
	gridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = gridScroll

	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyLabel"
	emptyLabel.Size = UDim2.new(1, -20, 0, 80)
	emptyLabel.Position = UDim2.new(0.5, 0, 0.4, 0)
	emptyLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Font = Theme.Fonts.Body
	emptyLabel.TextSize = 14
	emptyLabel.TextColor3 = Theme.Colors.TextMuted
	emptyLabel.TextWrapped = true
	emptyLabel.Text = "No swords in inventory.\nRoll the dice to pull swords!"
	emptyLabel.Visible = false
	emptyLabel.Parent = gridPanel.Content

	-- Right: Sword Inspector Detail Panel
	local inspectorPanel = Panel.new({
		Name = "InspectorPanel",
		Size = UDim2.new(0.35, 0, 1, 0),
		Position = UDim2.new(0.65, 0, 0, 0),
		BackgroundColor = Theme.Colors.PanelBackground,
		BorderColor = Theme.Colors.Border,
		Padding = UDim.new(0, 10),
		Parent = body,
	})

	local inspContent = inspectorPanel.Content

	local inspName = Instance.new("TextLabel")
	inspName.Name = "InspName"
	inspName.Size = UDim2.new(1, 0, 0, 24)
	inspName.Position = UDim2.new(0, 0, 0, 0)
	inspName.BackgroundTransparency = 1
	inspName.Font = Theme.Fonts.Title
	inspName.TextSize = 16
	inspName.TextColor3 = Theme.Colors.TextPrimary
	inspName.TextTruncate = Enum.TextTruncate.AtEnd
	inspName.Text = "Select a Sword"
	inspName.Parent = inspContent

	local inspRarity = Instance.new("TextLabel")
	inspRarity.Name = "InspRarity"
	inspRarity.Size = UDim2.new(1, 0, 0, 18)
	inspRarity.Position = UDim2.new(0, 0, 0, 26)
	inspRarity.BackgroundTransparency = 1
	inspRarity.Font = Theme.Fonts.Button
	inspRarity.TextSize = 12
	inspRarity.TextColor3 = Theme.Colors.AuraCyan
	inspRarity.Text = ""
	inspRarity.Parent = inspContent

	local inspDamage = Instance.new("TextLabel")
	inspDamage.Name = "InspDamage"
	inspDamage.Size = UDim2.new(1, 0, 0, 20)
	inspDamage.Position = UDim2.new(0, 0, 0, 48)
	inspDamage.BackgroundTransparency = 1
	inspDamage.Font = Theme.Fonts.Body
	inspDamage.TextSize = 13
	inspDamage.TextColor3 = Theme.Colors.TextGold
	inspDamage.Text = ""
	inspDamage.Parent = inspContent

	local inspStatus = Instance.new("TextLabel")
	inspStatus.Name = "InspStatus"
	inspStatus.Size = UDim2.new(1, 0, 0, 18)
	inspStatus.Position = UDim2.new(0, 0, 0, 72)
	inspStatus.BackgroundTransparency = 1
	inspStatus.Font = Theme.Fonts.Button
	inspStatus.TextSize = 12
	inspStatus.TextColor3 = Theme.Colors.TextSecondary
	inspStatus.Text = ""
	inspStatus.Parent = inspContent

	local feedbackLabel = Instance.new("TextLabel")
	feedbackLabel.Name = "FeedbackLabel"
	feedbackLabel.Size = UDim2.new(1, 0, 0, 36)
	feedbackLabel.Position = UDim2.new(0, 0, 0, 94)
	feedbackLabel.BackgroundTransparency = 1
	feedbackLabel.Font = Theme.Fonts.Button
	feedbackLabel.TextSize = 11
	feedbackLabel.TextColor3 = Theme.Colors.AuraEmerald
	feedbackLabel.TextWrapped = true
	feedbackLabel.Text = ""
	feedbackLabel.Parent = inspContent

	-- Floating Toast Banner for Equip Best and action feedback
	-- Positioned directly below top bar so it is visible even when no sword is selected
	local toastFrame = Instance.new("Frame")
	toastFrame.Name = "ToastFrame"
	toastFrame.Size = UDim2.new(0.94, 0, 0, 28)
	toastFrame.Position = UDim2.new(0.5, 0, 0, 86)
	toastFrame.AnchorPoint = Vector2.new(0.5, 0)
	toastFrame.BackgroundColor3 = Theme.Colors.PanelBackground
	toastFrame.BackgroundTransparency = 0.05
	toastFrame.BorderSizePixel = 0
	toastFrame.ZIndex = 25
	toastFrame.Visible = false
	toastFrame.Parent = rootContent

	local toastCorner = Instance.new("UICorner")
	toastCorner.CornerRadius = Theme.Corner.Small
	toastCorner.Parent = toastFrame

	local toastStroke = Instance.new("UIStroke")
	toastStroke.Name = "ToastStroke"
	toastStroke.Color = Theme.Colors.AuraEmerald
	toastStroke.Thickness = 1.5
	toastStroke.Parent = toastFrame

	local toastLabel = Instance.new("TextLabel")
	toastLabel.Name = "ToastLabel"
	toastLabel.Size = UDim2.new(1, -12, 1, 0)
	toastLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	toastLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	toastLabel.BackgroundTransparency = 1
	toastLabel.Font = Theme.Fonts.Button
	toastLabel.TextSize = 11
	toastLabel.TextColor3 = Theme.Colors.AuraEmerald
	toastLabel.TextWrapped = true
	toastLabel.ZIndex = 26
	toastLabel.Parent = toastFrame

	local feedbackTimer: thread? = nil
	local function showFeedback(msg: string, isSuccess: boolean?)
		if feedbackTimer then
			task.cancel(feedbackTimer)
			feedbackTimer = nil
		end
		local color = if isSuccess ~= false then Theme.Colors.AuraEmerald else Theme.Colors.AuraCrimson

		feedbackLabel.Text = msg
		feedbackLabel.TextColor3 = color

		toastLabel.Text = msg
		toastLabel.TextColor3 = color
		toastStroke.Color = color
		toastFrame.Visible = true

		feedbackTimer = task.delay(4, function()
			feedbackLabel.Text = ""
			toastFrame.Visible = false
			feedbackTimer = nil
		end)
	end

	-- Action buttons container (Equip and Sell)
	local actionContainer = Instance.new("Frame")
	actionContainer.Name = "ActionContainer"
	actionContainer.Size = UDim2.new(1, 0, 0, 96)
	actionContainer.Position = UDim2.new(0, 0, 1, 0)
	actionContainer.AnchorPoint = Vector2.new(0, 1)
	actionContainer.BackgroundTransparency = 1
	actionContainer.Parent = inspContent

	local equipButton = Button.new({
		Name = "EquipButton",
		Text = "EQUIP",
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor = Theme.Colors.ButtonPrimary,
		BorderColor = Theme.Colors.AuraCyan,
		TextColor = Theme.Colors.TextPrimary,
		CornerRadius = Theme.Corner.Medium,
		Parent = actionContainer,
	})

	local sellButton = Button.new({
		Name = "SellButton",
		Text = "SELL",
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.new(0, 0, 0, 48),
		BackgroundColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.ButtonClose,
		TextColor = Theme.Colors.ButtonClose,
		CornerRadius = Theme.Corner.Medium,
		Parent = actionContainer,
	})

	-- Sell Confirmation Sub-Popup
	local sellConfirmPopup = Popup.new({
		Title = "Confirm Sale",
		Size = UDim2.new(0.65, 0, 0.42, 0),
		MaxWidth = 360,
		MaxHeight = 220,
		Parent = screenGui,
	})

	local sellConfirmText = Instance.new("TextLabel")
	sellConfirmText.Name = "ConfirmDesc"
	sellConfirmText.Size = UDim2.new(1, -16, 0, 60)
	sellConfirmText.Position = UDim2.new(0.5, 0, 0, 10)
	sellConfirmText.AnchorPoint = Vector2.new(0.5, 0)
	sellConfirmText.BackgroundTransparency = 1
	sellConfirmText.Font = Theme.Fonts.Body
	sellConfirmText.TextSize = 13
	sellConfirmText.TextColor3 = Theme.Colors.TextSecondary
	sellConfirmText.TextWrapped = true
	sellConfirmText.Text = "Are you sure you want to sell this sword?\n(Sold swords are permanently removed with no Gold.)"
	sellConfirmText.Parent = sellConfirmPopup.Content

	local sellConfirmActions = Instance.new("Frame")
	sellConfirmActions.Name = "ConfirmActions"
	sellConfirmActions.Size = UDim2.new(1, -16, 0, 38)
	sellConfirmActions.Position = UDim2.new(0.5, 0, 1, -8)
	sellConfirmActions.AnchorPoint = Vector2.new(0.5, 1)
	sellConfirmActions.BackgroundTransparency = 1
	sellConfirmActions.Parent = sellConfirmPopup.Content

	local sellConfirmActionsLayout = Instance.new("UIListLayout")
	sellConfirmActionsLayout.FillDirection = Enum.FillDirection.Horizontal
	sellConfirmActionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sellConfirmActionsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	sellConfirmActionsLayout.Padding = UDim.new(0, 10)
	sellConfirmActionsLayout.Parent = sellConfirmActions

	local cancelSellBtn = Button.new({
		Name = "CancelSellButton",
		Text = "CANCEL",
		Size = UDim2.new(0.46, 0, 1, 0),
		BackgroundColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.Border,
		TextColor = Theme.Colors.TextPrimary,
		Parent = sellConfirmActions,
		OnClick = function()
			sellConfirmPopup:Close()
		end,
	})

	local confirmSellBtn = Button.new({
		Name = "ConfirmSellButton",
		Text = "YES, SELL",
		Size = UDim2.new(0.46, 0, 1, 0),
		BackgroundColor = Theme.Colors.ButtonClose,
		BorderColor = Theme.Colors.AuraCrimson,
		TextColor = Theme.Colors.TextPrimary,
		Parent = sellConfirmActions,
	})

	-- Internal state
	local currentOwnedSwords: { OwnedSwordEntry } = {}
	local currentEquippedUid = ""
	local currentPlacedSwords: { [string]: string } = {}
	local currentAutoSellRules: { [string]: boolean } = {}
	local selectedUid: string? = nil

	local onEquipCallback: ((string) -> ())? = nil
	local onUnequipCallback: (() -> ())? = nil
	local onSellCallback: ((string) -> ())? = nil
	local onToggleAutoSellCallback: ((string, boolean) -> ())? = nil

	-- Chip buttons for Auto-Sell
	local chipButtons: { [string]: TextButton } = {}

	for order, rarity in ipairs(Swords.Rarities) do
		local chip = Instance.new("TextButton")
		chip.Name = "Chip_" .. rarity
		chip.Size = UDim2.new(0, 88, 0, 30)
		chip.BackgroundColor3 = Theme.Colors.ButtonSecondary
		chip.AutoButtonColor = false
		chip.Text = ""
		chip.LayoutOrder = order
		chip.Parent = filterScroll

		local chipCorner = Instance.new("UICorner")
		chipCorner.CornerRadius = Theme.Corner.Small
		chipCorner.Parent = chip

		local chipStroke = Instance.new("UIStroke")
		chipStroke.Name = "ChipStroke"
		chipStroke.Color = Theme.Colors.BorderSubtle
		chipStroke.Thickness = Theme.Stroke.WidthDefault
		chipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		chipStroke.Parent = chip

		local chipLabel = Instance.new("TextLabel")
		chipLabel.Name = "Label"
		chipLabel.Size = UDim2.new(1, -4, 1, 0)
		chipLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
		chipLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		chipLabel.BackgroundTransparency = 1
		chipLabel.Font = Theme.Fonts.Button
		chipLabel.TextSize = 10
		chipLabel.TextColor3 = Theme.Colors.TextMuted
		chipLabel.Text = rarity:upper() .. ": OFF"
		chipLabel.Parent = chip

		chip.Activated:Connect(function()
			local current = currentAutoSellRules[rarity] == true
			if onToggleAutoSellCallback then
				onToggleAutoSellCallback(rarity, not current)
			end
		end)

		chipButtons[rarity] = chip
	end

	local function updateChips()
		for _, rarity in Swords.Rarities do
			local chip = chipButtons[rarity]
			if not chip then continue end
			local isEnabled = currentAutoSellRules[rarity] == true
			local rarityColor = (Swords.RarityColors and Swords.RarityColors[rarity]) or Theme.Colors.AuraCyan
			local stroke = chip:FindFirstChild("ChipStroke") :: UIStroke?
			local label = chip:FindFirstChild("Label") :: TextLabel?

			if isEnabled then
				chip.BackgroundColor3 = Color3.fromRGB(48, 20, 20)
				if stroke then
					stroke.Color = Theme.Colors.AuraCrimson
					stroke.Thickness = Theme.Stroke.WidthThick
				end
				if label then
					label.Text = rarity:upper() .. ": SELL"
					label.TextColor3 = Theme.Colors.AuraCrimson
				end
			else
				chip.BackgroundColor3 = Theme.Colors.ButtonSecondary
				if stroke then
					stroke.Color = Theme.Colors.BorderSubtle
					stroke.Thickness = Theme.Stroke.WidthDefault
				end
				if label then
					label.Text = rarity:upper() .. ": KEEP"
					label.TextColor3 = rarityColor
				end
			end
		end
	end

	-- Forward reference to select a sword
	local updateInspector: () -> ()

	local cardInstances: { [string]: Frame } = {}

	local function rebuildGrid()
		for _, child in gridScroll:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		table.clear(cardInstances)

		local maxCap = (GameConfig.Inventory and GameConfig.Inventory.MaxSwords) or 50
		countLabel.Text = ("CAPACITY: %d/%d"):format(#currentOwnedSwords, maxCap)

		if #currentOwnedSwords == 0 then
			emptyLabel.Visible = true
			selectedUid = nil
			updateInspector()
			return
		else
			emptyLabel.Visible = false
		end

		-- If current selection was sold or lost, default to equipped or first owned sword
		local selectedExists = false
		if selectedUid then
			for _, entry in currentOwnedSwords do
				if entry.uid == selectedUid then
					selectedExists = true
					break
				end
			end
		end

		if not selectedExists then
			selectedUid = if currentEquippedUid ~= "" then currentEquippedUid else currentOwnedSwords[1].uid
		end

		for idx, entry in ipairs(currentOwnedSwords) do
			local swordDef = swordDefMap[entry.id]
			local rarityName = swordDef and swordDef.rarity or "Common"
			local rarityColor = (Swords.RarityColors and Swords.RarityColors[rarityName]) or Theme.Colors.AuraCyan
			local isEquipped = (entry.uid == currentEquippedUid)
			local placedSlot: number? = nil
			for slotKey, pUid in currentPlacedSwords do
				if pUid == entry.uid then
					placedSlot = tonumber(slotKey) or 1
					break
				end
			end
			local isPlaced = (placedSlot ~= nil)
			local isSelected = (entry.uid == selectedUid)

			local card = Instance.new("Frame")
			card.Name = "Card_" .. entry.uid
			card.Size = UDim2.new(0, 72, 0, 80)
			card.BackgroundColor3 = Theme.Colors.ButtonSecondary
			card.BackgroundTransparency = 0.2
			card.LayoutOrder = idx
			card.Parent = gridScroll

			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = Theme.Corner.Medium
			cardCorner.Parent = card

			local cardStroke = Instance.new("UIStroke")
			cardStroke.Name = "CardStroke"
			cardStroke.Color = if isSelected then Theme.Colors.AuraGold
				elseif isEquipped then Theme.Colors.AuraEmerald
				elseif isPlaced then Theme.Colors.AuraCyan
				else rarityColor
			cardStroke.Thickness = isSelected and 2.5 or ((isEquipped or isPlaced) and 2 or 1.2)
			cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			cardStroke.Parent = card

			-- Click button covering card
			local btn = Instance.new("TextButton")
			btn.Name = "ClickBtn"
			btn.Size = UDim2.new(1, 0, 1, 0)
			btn.BackgroundTransparency = 1
			btn.Text = ""
			btn.AutoButtonColor = false
			btn.Parent = card

			-- Icon
			local icon = Instance.new("TextLabel")
			icon.Name = "Icon"
			icon.Size = UDim2.new(1, 0, 0, 36)
			icon.Position = UDim2.new(0, 0, 0, 6)
			icon.BackgroundTransparency = 1
			icon.Font = Theme.Fonts.Title
			icon.TextSize = 24
			icon.TextColor3 = rarityColor
			icon.Text = "🗡️"
			icon.Parent = card

			-- Name label
			local nameLbl = Instance.new("TextLabel")
			nameLbl.Name = "NameLabel"
			nameLbl.Size = UDim2.new(1, -4, 0, 24)
			nameLbl.Position = UDim2.new(0.5, 0, 1, -4)
			nameLbl.AnchorPoint = Vector2.new(0.5, 1)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Font = Theme.Fonts.Button
			nameLbl.TextSize = 10
			nameLbl.TextColor3 = rarityColor
			nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
			nameLbl.Text = swordDef and swordDef.name or "Unknown"
			nameLbl.Parent = card

			-- Equipped or Placed Badge
			if isEquipped then
				local badge = Instance.new("Frame")
				badge.Name = "EquippedBadge"
				badge.Size = UDim2.new(0, 16, 0, 16)
				badge.Position = UDim2.new(1, -2, 0, 2)
				badge.AnchorPoint = Vector2.new(1, 0)
				badge.BackgroundColor3 = Theme.Colors.AuraEmerald
				badge.BorderSizePixel = 0
				badge.Parent = card

				local badgeCorner = Instance.new("UICorner")
				badgeCorner.CornerRadius = Theme.Corner.Round
				badgeCorner.Parent = badge

				local badgeText = Instance.new("TextLabel")
				badgeText.Size = UDim2.new(1, 0, 1, 0)
				badgeText.BackgroundTransparency = 1
				badgeText.Text = "✓"
				badgeText.TextColor3 = Theme.Colors.TextPrimary
				badgeText.TextSize = 10
				badgeText.Font = Theme.Fonts.Title
				badgeText.Parent = badge
			elseif isPlaced then
				local badge = Instance.new("Frame")
				badge.Name = "PlacedBadge"
				badge.Size = UDim2.new(0, 24, 0, 16)
				badge.Position = UDim2.new(1, -2, 0, 2)
				badge.AnchorPoint = Vector2.new(1, 0)
				badge.BackgroundColor3 = Theme.Colors.AuraCyan
				badge.BorderSizePixel = 0
				badge.Parent = card

				local badgeCorner = Instance.new("UICorner")
				badgeCorner.CornerRadius = Theme.Corner.Round
				badgeCorner.Parent = badge

				local badgeText = Instance.new("TextLabel")
				badgeText.Size = UDim2.new(1, 0, 1, 0)
				badgeText.BackgroundTransparency = 1
				badgeText.Text = "P#" .. tostring(placedSlot)
				badgeText.TextColor3 = Theme.Colors.PanelBackground
				badgeText.TextSize = 10
				badgeText.Font = Theme.Fonts.Title
				badgeText.Parent = badge
			end

			btn.Activated:Connect(function()
				selectedUid = entry.uid
				rebuildGrid()
			end)

			cardInstances[entry.uid] = card
		end

		updateInspector()
	end

	updateInspector = function()
		if not selectedUid then
			inspName.Text = "No Selection"
			inspName.TextColor3 = Theme.Colors.TextMuted
			inspRarity.Text = ""
			inspDamage.Text = ""
			inspStatus.Text = ""
			equipButton:SetEnabled(false)
			equipButton:SetText("EQUIP")
			sellButton:SetEnabled(false)
			return
		end

		local selectedEntry: OwnedSwordEntry? = nil
		for _, entry in currentOwnedSwords do
			if entry.uid == selectedUid then
				selectedEntry = entry
				break
			end
		end

		if not selectedEntry then
			inspName.Text = "Select a Sword"
			inspRarity.Text = ""
			inspDamage.Text = ""
			inspStatus.Text = ""
			equipButton:SetEnabled(false)
			sellButton:SetEnabled(false)
			return
		end

		local swordDef = swordDefMap[selectedEntry.id]
		local rarityName = swordDef and swordDef.rarity or "Common"
		local rarityColor = (Swords.RarityColors and Swords.RarityColors[rarityName]) or Theme.Colors.AuraCyan
		local isEquipped = (selectedEntry.uid == currentEquippedUid)
		local placedSlot: number? = nil
		for slotKey, pUid in currentPlacedSwords do
			if pUid == selectedEntry.uid then
				placedSlot = tonumber(slotKey) or 1
				break
			end
		end

		inspName.Text = swordDef and swordDef.name or "Sword"
		inspName.TextColor3 = rarityColor
		inspRarity.Text = ("%s (1 in %s)"):format(rarityName:upper(), swordDef and NumberFormat.format(swordDef.baseOdds) or "?")
		inspRarity.TextColor3 = rarityColor
		inspDamage.Text = ("Base Damage: %s Gold/Tap"):format(swordDef and NumberFormat.format(swordDef.baseDamage) or "1")

		if isEquipped then
			inspStatus.Text = "STATUS: EQUIPPED"
			inspStatus.TextColor3 = Theme.Colors.AuraEmerald
			equipButton:SetText("UNEQUIP")
			equipButton:SetBorderColor(Theme.Colors.Border)
			equipButton:SetEnabled(true)
			sellButton:SetEnabled(false)
		elseif placedSlot ~= nil then
			inspStatus.Text = ("STATUS: PLACED ON PEDESTAL #%d"):format(placedSlot)
			inspStatus.TextColor3 = Theme.Colors.AuraCyan
			equipButton:SetText("PLACED")
			equipButton:SetBorderColor(Theme.Colors.Border)
			equipButton:SetEnabled(false) -- Disabled for placed swords
			sellButton:SetEnabled(false)  -- Disabled for placed swords
		else
			inspStatus.Text = "STATUS: IN BACKPACK"
			inspStatus.TextColor3 = Theme.Colors.TextSecondary
			equipButton:SetText("EQUIP")
			equipButton:SetBorderColor(rarityColor)
			equipButton:SetEnabled(true)
			sellButton:SetEnabled(true)
		end
	end

	equipButton.Instance.Activated:Connect(function()
		if not selectedUid then return end
		if selectedUid == currentEquippedUid then
			if onUnequipCallback then
				onUnequipCallback()
			end
		else
			if onEquipCallback then
				onEquipCallback(selectedUid)
			end
		end
	end)

	sellButton.Instance.Activated:Connect(function()
		if not selectedUid then return end
		if selectedUid == currentEquippedUid then return end

		local selectedEntry = nil
		for _, e in currentOwnedSwords do
			if e.uid == selectedUid then
				selectedEntry = e
				break
			end
		end
		local swordDef = selectedEntry and swordDefMap[selectedEntry.id]
		local name = swordDef and swordDef.name or "this sword"
		sellConfirmText.Text = ("Are you sure you want to sell [%s]?\n(Sold swords are permanently removed with no Gold.)"):format(name)
		sellConfirmPopup:Open()
	end)

	confirmSellBtn.Instance.Activated:Connect(function()
		sellConfirmPopup:Close()
		if selectedUid and onSellCallback then
			onSellCallback(selectedUid)
		end
	end)

	local self: InventoryUIInstance = {
		Open = function(_)
			popup:Open()
		end,
		Close = function(_)
			popup:Close()
			sellConfirmPopup:Close()
		end,
		SetData = function(_, ownedSwords: { OwnedSwordEntry }, equippedUid: string, autoSellRules: { [string]: boolean }, placedSwords: { [string]: string }?)
			currentOwnedSwords = ownedSwords or {}
			currentEquippedUid = equippedUid or ""
			currentAutoSellRules = autoSellRules or {}
			currentPlacedSwords = placedSwords or {}
			updateChips()
			rebuildGrid()
		end,
		SetOnEquip = function(_, callback: (uid: string) -> ())
			onEquipCallback = callback
		end,
		SetOnUnequip = function(_, callback: () -> ())
			onUnequipCallback = callback
		end,
		SetOnSell = function(_, callback: (uid: string) -> ())
			onSellCallback = callback
		end,
		SetOnToggleAutoSell = function(_, callback: (rarity: string, enabled: boolean) -> ())
			onToggleAutoSellCallback = callback
		end,
		SetOnEquipBest = function(_, callback: () -> ())
			onEquipBestCallback = callback
		end,
		SetEquipBestBusy = function(_, isBusy: boolean)
			equipBestBtn:SetEnabled(not isBusy)
			equipBestBtn:SetText(if isBusy then "EQUIPPING..." else "EQUIP BEST")
		end,
		ShowEquipBestMessage = function(_, message: string, isSuccess: boolean?)
			showFeedback(message, isSuccess)
		end,
		Destroy = function(_)
			if feedbackTimer then
				task.cancel(feedbackTimer)
				feedbackTimer = nil
			end
			toastFrame:Destroy()
			equipBestBtn:Destroy()
			cancelSellBtn:Destroy()
			confirmSellBtn:Destroy()
			equipButton:Destroy()
			sellButton:Destroy()
			inspectorPanel:Destroy()
			gridPanel:Destroy()
			sellConfirmPopup:Destroy()
			popup:Destroy()
			if ownsScreenGui then
				screenGui:Destroy()
			end
		end,
	}

	return self
end

return InventoryUI
