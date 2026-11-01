--!strict
-- RunesmithUI: Mobile-first modal for Hilt Blessings and Runesmith station.
-- Select a sword from inventory (including equipped and placed swords),
-- view current blessing and effect description, and roll a blessing for server-calculated Gold.
-- Includes confirmation warning when attempting to roll over a Tier III blessing (Fortune III / Greed III).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Config = ReplicatedStorage:WaitForChild("Config")
local Swords = require(Config:WaitForChild("Swords"))
local Blessings = require(Config:WaitForChild("Blessings"))

local Components = Shared:WaitForChild("UI"):WaitForChild("Components")
local Popup = require(Components:WaitForChild("Popup"))
local Button = require(Components:WaitForChild("Button"))
local BlessingBadge = require(Components:WaitForChild("BlessingBadge"))
local GradeBadge = require(Components:WaitForChild("GradeBadge"))
local EnchantBadge = require(Components:WaitForChild("EnchantBadge"))

export type OwnedSwordEntry = {
	uid: string,
	id: string,
	grade: string?,
	enchant: string?,
	blessing: string?,
	locked: boolean?,
	[string]: any,
}

export type RunesmithUIInstance = {
	Open: (
		self: RunesmithUIInstance,
		ownedSwords: { OwnedSwordEntry },
		equippedUid: string,
		placedUids: { [string]: boolean },
		goldBalance: number,
		rollCost: number
	) -> (),
	Close: (self: RunesmithUIInstance) -> (),
	UpdateGold: (self: RunesmithUIInstance, gold: number) -> (),
	UpdateCost: (self: RunesmithUIInstance, cost: number) -> (),
	UpdateSwords: (
		self: RunesmithUIInstance,
		ownedSwords: { OwnedSwordEntry },
		equippedUid: string,
		placedUids: { [string]: boolean }
	) -> (),
	ShowRollResult: (self: RunesmithUIInstance, oldBlessing: string?, newBlessing: string, costPaid: number) -> (),
	SetOnRoll: (self: RunesmithUIInstance, callback: (uid: string) -> ()) -> (),
	SetOnClose: (self: RunesmithUIInstance, callback: () -> ()) -> (),
	SelectSword: (self: RunesmithUIInstance, uid: string) -> (),
	ConfirmTierIIIReroll: (self: RunesmithUIInstance) -> (),
	TriggerRollButton: (self: RunesmithUIInstance) -> (),
	Destroy: (self: RunesmithUIInstance) -> (),
}

local RunesmithUI = {}

local swordDefMap: { [string]: Swords.SwordDef } = {}
for _, def in Swords do
	swordDefMap[def.id] = def
end

function RunesmithUI.new(parentGui: Instance): RunesmithUIInstance
	local screenGui: ScreenGui
	if parentGui:IsA("ScreenGui") then
		screenGui = parentGui
	else
		local sg = Instance.new("ScreenGui")
		sg.Name = "AuraBladeRunesmithGui"
		sg.ResetOnSpawn = false
		sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		sg.DisplayOrder = 16
		sg.Parent = parentGui
		screenGui = sg
	end

	-- State
	local currentSwords: { OwnedSwordEntry } = {}
	local currentEquippedUid = ""
	local currentPlacedMap: { [string]: boolean } = {}
	local currentGold = 0
	local currentCost = Blessings.MinCost
	local selectedUid: string? = nil
	local isRolling = false

	local onRollCallback: ((string) -> ())? = nil
	local onCloseCallback: (() -> ())? = nil

	local popup = Popup.new({
		Title = "Runesmith",
		WidthScale = 0.94,
		MaxWidth = 720,
		HeightScale = 0.88,
		MaxHeight = 560,
		Parent = screenGui,
		OnClose = function()
			if onCloseCallback then
				onCloseCallback()
			end
		end,
	})

	local container = popup.Content

	-- Header with live Gold and roll cost
	local headerBar = Instance.new("Frame")
	headerBar.Name = "HeaderBar"
	headerBar.Size = UDim2.new(1, 0, 0, 32)
	headerBar.Position = UDim2.new(0, 0, 0, 0)
	headerBar.BackgroundColor3 = Theme.Colors.PanelBackground
	headerBar.BorderSizePixel = 0
	headerBar.Parent = container

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = Theme.Corner.Small
	headerCorner.Parent = headerBar

	local goldBalanceLabel = Instance.new("TextLabel")
	goldBalanceLabel.Name = "GoldBalance"
	goldBalanceLabel.Size = UDim2.new(0.5, -10, 1, 0)
	goldBalanceLabel.Position = UDim2.new(0, 10, 0, 0)
	goldBalanceLabel.BackgroundTransparency = 1
	goldBalanceLabel.Font = Theme.Fonts.Button
	goldBalanceLabel.TextSize = 13
	goldBalanceLabel.TextColor3 = Theme.Colors.TextGold
	goldBalanceLabel.TextXAlignment = Enum.TextXAlignment.Left
	goldBalanceLabel.Text = "💰 Gold: 0"
	goldBalanceLabel.Parent = headerBar

	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "CostLabel"
	costLabel.Size = UDim2.new(0.5, -10, 1, 0)
	costLabel.Position = UDim2.new(0.5, 0, 0, 0)
	costLabel.BackgroundTransparency = 1
	costLabel.Font = Theme.Fonts.Button
	costLabel.TextSize = 13
	costLabel.TextColor3 = Theme.Colors.AuraCyan
	costLabel.TextXAlignment = Enum.TextXAlignment.Right
	costLabel.Text = ("Roll Cost: %s Gold"):format(NumberFormat.format(currentCost))
	costLabel.Parent = headerBar

	-- Two-column layout container (Left: Sword List, Right: Active Preview & Roll)
	local contentFrame = Instance.new("Frame")
	contentFrame.Name = "ContentFrame"
	contentFrame.Size = UDim2.new(1, 0, 1, -40)
	contentFrame.Position = UDim2.new(0, 0, 0, 38)
	contentFrame.BackgroundTransparency = 1
	contentFrame.Parent = container

	-- Left column: Sword Selection List
	local leftCol = Instance.new("Frame")
	leftCol.Name = "LeftCol"
	leftCol.Size = UDim2.new(0.46, -4, 1, 0)
	leftCol.Position = UDim2.new(0, 0, 0, 0)
	leftCol.BackgroundColor3 = Theme.Colors.BackgroundCard
	leftCol.BackgroundTransparency = 0.3
	leftCol.Parent = contentFrame

	local leftCorner = Instance.new("UICorner")
	leftCorner.CornerRadius = Theme.Corner.Small
	leftCorner.Parent = leftCol

	local leftTitle = Instance.new("TextLabel")
	leftTitle.Name = "LeftTitle"
	leftTitle.Size = UDim2.new(1, -12, 0, 24)
	leftTitle.Position = UDim2.new(0, 6, 0, 4)
	leftTitle.BackgroundTransparency = 1
	leftTitle.Font = Theme.Fonts.Button
	leftTitle.TextSize = 11
	leftTitle.TextColor3 = Theme.Colors.TextSecondary
	leftTitle.TextXAlignment = Enum.TextXAlignment.Left
	leftTitle.Text = "SELECT BLADE TO BLESS"
	leftTitle.Parent = leftCol

	local listScroll = Instance.new("ScrollingFrame")
	listScroll.Name = "SwordListScroll"
	listScroll.Size = UDim2.new(1, -8, 1, -34)
	listScroll.Position = UDim2.new(0, 4, 0, 30)
	listScroll.BackgroundTransparency = 1
	listScroll.BorderSizePixel = 0
	listScroll.ScrollBarThickness = 4
	listScroll.ScrollBarImageColor3 = Theme.Colors.BorderGlow
	listScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listScroll.Parent = leftCol

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 4)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = listScroll

	-- Right column: Selected Sword View, Blessing Info, and Roll Button
	local rightCol = Instance.new("Frame")
	rightCol.Name = "RightCol"
	rightCol.Size = UDim2.new(0.54, -4, 1, 0)
	rightCol.Position = UDim2.new(0.46, 4, 0, 0)
	rightCol.BackgroundColor3 = Theme.Colors.BackgroundCard
	rightCol.BackgroundTransparency = 0.3
	rightCol.Parent = contentFrame

	local rightCorner = Instance.new("UICorner")
	rightCorner.CornerRadius = Theme.Corner.Small
	rightCorner.Parent = rightCol

	local rightScroll = Instance.new("ScrollingFrame")
	rightScroll.Name = "RightScroll"
	rightScroll.Size = UDim2.new(1, -12, 1, -12)
	rightScroll.Position = UDim2.new(0, 6, 0, 6)
	rightScroll.BackgroundTransparency = 1
	rightScroll.BorderSizePixel = 0
	rightScroll.ScrollBarThickness = 4
	rightScroll.ScrollBarImageColor3 = Theme.Colors.BorderGlow
	rightScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	rightScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rightScroll.Parent = rightCol

	local rightLayout = Instance.new("UIListLayout")
	rightLayout.Padding = UDim.new(0, 8)
	rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rightLayout.Parent = rightScroll

	-- Active Sword Card
	local activeCard = Instance.new("Frame")
	activeCard.Name = "ActiveCard"
	activeCard.LayoutOrder = 1
	activeCard.Size = UDim2.new(1, 0, 0, 72)
	activeCard.BackgroundColor3 = Theme.Colors.PanelBackground
	activeCard.Parent = rightScroll

	local activeCorner = Instance.new("UICorner")
	activeCorner.CornerRadius = Theme.Corner.Small
	activeCorner.Parent = activeCard

	local swordNameLabel = Instance.new("TextLabel")
	swordNameLabel.Name = "SwordName"
	swordNameLabel.Size = UDim2.new(1, -16, 0, 20)
	swordNameLabel.Position = UDim2.new(0, 8, 0, 6)
	swordNameLabel.BackgroundTransparency = 1
	swordNameLabel.Font = Theme.Fonts.Title
	swordNameLabel.TextSize = 15
	swordNameLabel.TextColor3 = Theme.Colors.TextPrimary
	swordNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	swordNameLabel.Text = "No Sword Selected"
	swordNameLabel.Parent = activeCard

	local swordStatsLabel = Instance.new("TextLabel")
	swordStatsLabel.Name = "SwordStats"
	swordStatsLabel.Size = UDim2.new(1, -16, 0, 16)
	swordStatsLabel.Position = UDim2.new(0, 8, 0, 28)
	swordStatsLabel.BackgroundTransparency = 1
	swordStatsLabel.Font = Theme.Fonts.Body
	swordStatsLabel.TextSize = 11
	swordStatsLabel.TextColor3 = Theme.Colors.TextSecondary
	swordStatsLabel.TextXAlignment = Enum.TextXAlignment.Left
	swordStatsLabel.Text = "Base: —"
	swordStatsLabel.Parent = activeCard

	local swordEquipTag = Instance.new("TextLabel")
	swordEquipTag.Name = "SwordEquipTag"
	swordEquipTag.Size = UDim2.new(1, -16, 0, 16)
	swordEquipTag.Position = UDim2.new(0, 8, 0, 48)
	swordEquipTag.BackgroundTransparency = 1
	swordEquipTag.Font = Theme.Fonts.Button
	swordEquipTag.TextSize = 10
	swordEquipTag.TextColor3 = Theme.Colors.AuraEmerald
	swordEquipTag.TextXAlignment = Enum.TextXAlignment.Left
	swordEquipTag.Text = ""
	swordEquipTag.Parent = activeCard

	-- Blessing Details Card
	local blessingCard = Instance.new("Frame")
	blessingCard.Name = "BlessingCard"
	blessingCard.LayoutOrder = 2
	blessingCard.Size = UDim2.new(1, 0, 0, 115)
	blessingCard.BackgroundColor3 = Theme.Colors.PanelBackground
	blessingCard.Parent = rightScroll

	local blessingCorner = Instance.new("UICorner")
	blessingCorner.CornerRadius = Theme.Corner.Small
	blessingCorner.Parent = blessingCard

	local currentBlessingTitle = Instance.new("TextLabel")
	currentBlessingTitle.Name = "Title"
	currentBlessingTitle.Size = UDim2.new(1, -16, 0, 18)
	currentBlessingTitle.Position = UDim2.new(0, 8, 0, 6)
	currentBlessingTitle.BackgroundTransparency = 1
	currentBlessingTitle.Font = Theme.Fonts.Button
	currentBlessingTitle.TextSize = 11
	currentBlessingTitle.TextColor3 = Theme.Colors.TextSecondary
	currentBlessingTitle.TextXAlignment = Enum.TextXAlignment.Left
	currentBlessingTitle.Text = "CURRENT HILT BLESSING"
	currentBlessingTitle.Parent = blessingCard

	local currentBlessingBadge = BlessingBadge.new({
		Blessing = nil,
		Size = UDim2.new(0, 75, 0, 22),
		Position = UDim2.new(0, 8, 0, 28),
		AnchorPoint = Vector2.new(0, 0),
		Parent = blessingCard,
		TextSize = 11,
	})

	local blessingEffectLabel = Instance.new("TextLabel")
	blessingEffectLabel.Name = "BlessingEffect"
	blessingEffectLabel.Size = UDim2.new(1, -16, 0, 32)
	blessingEffectLabel.Position = UDim2.new(0, 8, 0, 54)
	blessingEffectLabel.BackgroundTransparency = 1
	blessingEffectLabel.Font = Theme.Fonts.Body
	blessingEffectLabel.TextSize = 11
	blessingEffectLabel.TextColor3 = Theme.Colors.AuraCyan
	blessingEffectLabel.TextXAlignment = Enum.TextXAlignment.Left
	blessingEffectLabel.TextYAlignment = Enum.TextYAlignment.Top
	blessingEffectLabel.TextWrapped = true
	blessingEffectLabel.Text = "Effect: None"
	blessingEffectLabel.Parent = blessingCard

	local overwriteWarning = Instance.new("TextLabel")
	overwriteWarning.Name = "OverwriteWarning"
	overwriteWarning.Size = UDim2.new(1, -16, 0, 18)
	overwriteWarning.Position = UDim2.new(0, 8, 0, 90)
	overwriteWarning.BackgroundTransparency = 1
	overwriteWarning.Font = Theme.Fonts.Body
	overwriteWarning.TextSize = 10
	overwriteWarning.TextColor3 = Theme.Colors.TextMuted
	overwriteWarning.TextXAlignment = Enum.TextXAlignment.Left
	overwriteWarning.Text = "⚠️ Rolling will overwrite the current blessing on this sword."
	overwriteWarning.Parent = blessingCard

	-- Roll Action Card
	local actionCard = Instance.new("Frame")
	actionCard.Name = "ActionCard"
	actionCard.LayoutOrder = 3
	actionCard.Size = UDim2.new(1, 0, 0, 110)
	actionCard.BackgroundColor3 = Theme.Colors.PanelBackground
	actionCard.Parent = rightScroll

	local actionCorner = Instance.new("UICorner")
	actionCorner.CornerRadius = Theme.Corner.Small
	actionCorner.Parent = actionCard

	local rollButton = Button.new({
		Name = "RollBlessingBtn",
		Text = "ROLL BLESSING",
		Size = UDim2.new(1, -16, 0, 42),
		Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor = Theme.Colors.ButtonPrimary,
		BorderColor = Theme.Colors.AuraCyan,
		TextColor = Theme.Colors.AuraCyan,
		Parent = actionCard,
	})

	local rollResultLabel = Instance.new("TextLabel")
	rollResultLabel.Name = "RollResult"
	rollResultLabel.Size = UDim2.new(1, -16, 0, 42)
	rollResultLabel.Position = UDim2.new(0.5, 0, 0, 60)
	rollResultLabel.AnchorPoint = Vector2.new(0.5, 0)
	rollResultLabel.BackgroundTransparency = 1
	rollResultLabel.Font = Theme.Fonts.Body
	rollResultLabel.TextSize = 12
	rollResultLabel.TextColor3 = Theme.Colors.TextSecondary
	rollResultLabel.TextWrapped = true
	rollResultLabel.Text = "Tap Roll to bless this blade."
	rollResultLabel.Parent = actionCard

	-- Confirmation Modal for Tier III Blessings (Fortune III / Greed III)
	local confirmModal = Instance.new("Frame")
	confirmModal.Name = "Tier3ConfirmModal"
	confirmModal.Size = UDim2.new(1, 0, 1, 0)
	confirmModal.Position = UDim2.new(0, 0, 0, 0)
	confirmModal.BackgroundColor3 = Color3.new(0, 0, 0)
	confirmModal.BackgroundTransparency = 0.5
	confirmModal.Visible = false
	confirmModal.ZIndex = 50
	confirmModal.Parent = container

	local confirmCard = Instance.new("Frame")
	confirmCard.Name = "ConfirmCard"
	confirmCard.Size = UDim2.new(0.85, 0, 0, 175)
	confirmCard.Position = UDim2.new(0.5, 0, 0.5, 0)
	confirmCard.AnchorPoint = Vector2.new(0.5, 0.5)
	confirmCard.BackgroundColor3 = Theme.Colors.BackgroundDark
	confirmCard.ZIndex = 51
	confirmCard.Parent = confirmModal

	local cCorner = Instance.new("UICorner")
	cCorner.CornerRadius = Theme.Corner.Medium
	cCorner.Parent = confirmCard

	local cStroke = Instance.new("UIStroke")
	cStroke.Color = Theme.Colors.AuraGold
	cStroke.Thickness = 2
	cStroke.Parent = confirmCard

	local confirmTitle = Instance.new("TextLabel")
	confirmTitle.Name = "Title"
	confirmTitle.Size = UDim2.new(1, -20, 0, 24)
	confirmTitle.Position = UDim2.new(0, 10, 0, 10)
	confirmTitle.BackgroundTransparency = 1
	confirmTitle.Font = Theme.Fonts.Title
	confirmTitle.TextSize = 14
	confirmTitle.TextColor3 = Theme.Colors.AuraGold
	confirmTitle.Text = "⚠️ REROLL TIER III BLESSING?"
	confirmTitle.ZIndex = 52
	confirmTitle.Parent = confirmCard

	local confirmMsg = Instance.new("TextLabel")
	confirmMsg.Name = "Message"
	confirmMsg.Size = UDim2.new(1, -24, 0, 60)
	confirmMsg.Position = UDim2.new(0, 12, 0, 40)
	confirmMsg.BackgroundTransparency = 1
	confirmMsg.Font = Theme.Fonts.Body
	confirmMsg.TextSize = 12
	confirmMsg.TextColor3 = Theme.Colors.TextPrimary
	confirmMsg.TextWrapped = true
	confirmMsg.Text = "This sword currently has a rare Tier III blessing! Are you sure you want to reroll it?"
	confirmMsg.ZIndex = 52
	confirmMsg.Parent = confirmCard

	local cancelBtn = Button.new({
		Name = "CancelBtn",
		Text = "CANCEL",
		Size = UDim2.new(0.44, 0, 0, 36),
		Position = UDim2.new(0.04, 0, 1, -48),
		BackgroundColor = Theme.Colors.PanelBackground,
		BorderColor = Theme.Colors.Border,
		TextColor = Theme.Colors.TextSecondary,
		Parent = confirmCard,
		ZIndex = 52,
	})

	local confirmBtn = Button.new({
		Name = "ConfirmBtn",
		Text = "REROLL",
		Size = UDim2.new(0.44, 0, 0, 36),
		Position = UDim2.new(0.52, 0, 1, -48),
		BackgroundColor = Theme.Colors.ButtonPrimary,
		BorderColor = Theme.Colors.AuraGold,
		TextColor = Theme.Colors.AuraGold,
		Parent = confirmCard,
		ZIndex = 52,
	})

	local pendingRollAction: (() -> ())? = nil

	cancelBtn.Instance.Activated:Connect(function()
		confirmModal.Visible = false
		pendingRollAction = nil
	end)

	confirmBtn.Instance.Activated:Connect(function()
		confirmModal.Visible = false
		local action = pendingRollAction
		pendingRollAction = nil
		if action then
			action()
		end
	end)

	local function getSelectedEntry(): OwnedSwordEntry?
		if not selectedUid then
			return nil
		end
		for _, entry in ipairs(currentSwords) do
			if entry.uid == selectedUid then
				return entry
			end
		end
		return nil
	end

	local forwardUpdateActiveView: (() -> ())? = nil

	local function updateActiveSwordView()
		local entry = getSelectedEntry()
		if not entry then
			swordNameLabel.Text = "No Sword Selected"
			swordStatsLabel.Text = "Base: —"
			swordEquipTag.Text = ""
			BlessingBadge.Update(currentBlessingBadge, nil)
			blessingEffectLabel.Text = "Effect: None"
			rollButton:SetEnabled(false)
			return
		end

		local def = swordDefMap[entry.id]
		local bName = entry.blessing or ""
		local bDef = Blessings.GetBlessingDef(bName)

		swordNameLabel.Text = def and def.name or "Sword"
		swordStatsLabel.Text = ("Base: %s Damage"):format(
			def and NumberFormat.format(def.baseDamage) or "1"
		)

		if entry.uid == currentEquippedUid then
			swordEquipTag.Text = "[EQUIPPED]"
			swordEquipTag.TextColor3 = Theme.Colors.AuraEmerald
		elseif currentPlacedMap[entry.uid] then
			swordEquipTag.Text = "[ON PEDESTAL]"
			swordEquipTag.TextColor3 = Theme.Colors.AuraCyan
		else
			swordEquipTag.Text = ""
		end

		BlessingBadge.Update(currentBlessingBadge, bName)
		if bDef then
			blessingEffectLabel.Text = ("Effect: %s"):format(bDef.effectText)
			blessingEffectLabel.TextColor3 = Theme.Colors.AuraCyan
		else
			blessingEffectLabel.Text = "Effect: None (No blessing attached)"
			blessingEffectLabel.TextColor3 = Theme.Colors.TextMuted
		end

		local canRoll = (currentGold >= currentCost and not isRolling)
		rollButton:SetEnabled(canRoll)
		rollButton:SetText(("ROLL BLESSING (💰 %s)"):format(NumberFormat.format(currentCost)))
	end

	local function rebuildSwordList()
		for _, child in listScroll:GetChildren() do
			if child:IsA("GuiObject") and child.Name ~= "UIListLayout" then
				child:Destroy()
			end
		end

		if #currentSwords == 0 then
			local empty = Instance.new("TextLabel")
			empty.Name = "EmptyLabel"
			empty.Size = UDim2.new(1, 0, 0, 50)
			empty.BackgroundTransparency = 1
			empty.Font = Theme.Fonts.Body
			empty.TextSize = 12
			empty.TextColor3 = Theme.Colors.TextMuted
			empty.Text = "No swords in inventory."
			empty.Parent = listScroll
			return
		end

		for _, entry in ipairs(currentSwords) do
			local def = swordDefMap[entry.id]
			local isSelected = (entry.uid == selectedUid)

			local itemCard = Instance.new("TextButton")
			itemCard.Name = "Item_" .. entry.uid
			itemCard.Size = UDim2.new(1, 0, 0, 48)
			itemCard.BackgroundColor3 = if isSelected then Theme.Colors.BackgroundHover else Theme.Colors.PanelBackground
			itemCard.AutoButtonColor = false
			itemCard.Text = ""
			itemCard.Parent = listScroll

			local iCorner = Instance.new("UICorner")
			iCorner.CornerRadius = Theme.Corner.Small
			iCorner.Parent = itemCard

			local iStroke = Instance.new("UIStroke")
			iStroke.Color = if isSelected then Theme.Colors.AuraCyan else Theme.Colors.Border
			iStroke.Thickness = if isSelected then 1.5 else 1
			iStroke.Parent = itemCard

			local iName = Instance.new("TextLabel")
			iName.Name = "Name"
			iName.Size = UDim2.new(1, -12, 0, 18)
			iName.Position = UDim2.new(0, 8, 0, 4)
			iName.BackgroundTransparency = 1
			iName.Font = Theme.Fonts.Button
			iName.TextSize = 12
			iName.TextColor3 = if isSelected then Theme.Colors.AuraCyan else Theme.Colors.TextPrimary
			iName.TextXAlignment = Enum.TextXAlignment.Left
			iName.TextTruncate = Enum.TextTruncate.AtEnd
			iName.Text = def and def.name or "Sword"
			iName.Parent = itemCard

			local tagsContainer = Instance.new("Frame")
			tagsContainer.Name = "TagsContainer"
			tagsContainer.Size = UDim2.new(1, -16, 0, 20)
			tagsContainer.Position = UDim2.new(0, 8, 0, 24)
			tagsContainer.BackgroundTransparency = 1
			tagsContainer.Parent = itemCard

			local tagsLayout = Instance.new("UIListLayout")
			tagsLayout.FillDirection = Enum.FillDirection.Horizontal
			tagsLayout.Padding = UDim.new(0, 4)
			tagsLayout.SortOrder = Enum.SortOrder.LayoutOrder
			tagsLayout.Parent = tagsContainer

			-- Status tag if equipped or placed
			if entry.uid == currentEquippedUid then
				local eTag = Instance.new("TextLabel")
				eTag.Name = "EquippedTag"
				eTag.LayoutOrder = 1
				eTag.Size = UDim2.new(0, 32, 1, 0)
				eTag.BackgroundTransparency = 1
				eTag.Font = Theme.Fonts.Button
				eTag.TextSize = 9
				eTag.TextColor3 = Theme.Colors.AuraEmerald
				eTag.Text = "[EQ]"
				eTag.Parent = tagsContainer
			elseif currentPlacedMap[entry.uid] then
				local pTag = Instance.new("TextLabel")
				pTag.Name = "PlacedTag"
				pTag.LayoutOrder = 1
				pTag.Size = UDim2.new(0, 32, 1, 0)
				pTag.BackgroundTransparency = 1
				pTag.Font = Theme.Fonts.Button
				pTag.TextSize = 9
				pTag.TextColor3 = Theme.Colors.AuraCyan
				pTag.Text = "[PED]"
				pTag.Parent = tagsContainer
			end

			-- Badges
			if entry.grade and entry.grade ~= "" then
				local gBadge = GradeBadge.new({
					Grade = entry.grade,
					Size = UDim2.new(0, 24, 0, 16),
					Parent = tagsContainer,
					TextSize = 9,
				})
				gBadge.LayoutOrder = 2
			end

			if entry.enchant and entry.enchant ~= "" then
				local eBadge = EnchantBadge.new({
					Enchant = entry.enchant,
					Size = UDim2.new(0, 48, 0, 16),
					Parent = tagsContainer,
					TextSize = 9,
				})
				eBadge.LayoutOrder = 3
			end

			if entry.blessing and entry.blessing ~= "" then
				local bBadge = BlessingBadge.new({
					Blessing = entry.blessing,
					Size = UDim2.new(0, 56, 0, 16),
					Parent = tagsContainer,
					TextSize = 9,
				})
				bBadge.LayoutOrder = 4
			end

			itemCard.Activated:Connect(function()
				selectedUid = entry.uid
				rebuildSwordList()
				updateActiveSwordView()
			end)
		end
	end

	local function executeRoll()
		if not selectedUid or isRolling then
			return
		end
		if currentGold < currentCost then
			rollResultLabel.Text = "Not enough Gold to roll blessing."
			rollResultLabel.TextColor3 = Theme.Colors.ButtonClose
			return
		end

		isRolling = true
		rollButton:SetEnabled(false)
		rollResultLabel.Text = "Blessing blade..."
		rollResultLabel.TextColor3 = Theme.Colors.AuraCyan

		if onRollCallback then
			onRollCallback(selectedUid)
		end
	end

	rollButton.Instance.Activated:Connect(function()
		local entry = getSelectedEntry()
		if not entry then
			return
		end

		if Blessings.IsTierIII(entry.blessing) then
			confirmMsg.Text = ("This sword has rare Tier III blessing '%s'! Rerolling will overwrite it."):format(entry.blessing or "")
			pendingRollAction = executeRoll
			confirmModal.Visible = true
		else
			executeRoll()
		end
	end)

	local self: RunesmithUIInstance = {
		Open = function(_, ownedSwords, equippedUid, placedUids, goldBalance, rollCost)
			currentSwords = ownedSwords or {}
			currentEquippedUid = equippedUid or ""
			currentPlacedMap = placedUids or {}
			currentGold = goldBalance or 0
			currentCost = rollCost or Blessings.MinCost
			isRolling = false

			goldBalanceLabel.Text = "💰 Gold: " .. NumberFormat.format(currentGold)
			costLabel.Text = ("Roll Cost: %s Gold"):format(NumberFormat.format(currentCost))
			rollResultLabel.Text = "Tap Roll to bless this blade."
			rollResultLabel.TextColor3 = Theme.Colors.TextSecondary

			-- Default selection
			if not selectedUid or not getSelectedEntry() then
				if equippedUid ~= "" then
					selectedUid = equippedUid
				elseif #currentSwords > 0 then
					selectedUid = currentSwords[1].uid
				else
					selectedUid = nil
				end
			end

			rebuildSwordList()
			updateActiveSwordView()
			popup:Open()
		end,

		Close = function(_)
			confirmModal.Visible = false
			popup:Close()
		end,

		UpdateGold = function(_, gold)
			currentGold = gold
			goldBalanceLabel.Text = "💰 Gold: " .. NumberFormat.format(gold)
			updateActiveSwordView()
		end,

		UpdateCost = function(_, cost)
			currentCost = cost
			costLabel.Text = ("Roll Cost: %s Gold"):format(NumberFormat.format(cost))
			updateActiveSwordView()
		end,

		UpdateSwords = function(_, ownedSwords, equippedUid, placedUids)
			currentSwords = ownedSwords or {}
			currentEquippedUid = equippedUid or ""
			currentPlacedMap = placedUids or {}
			rebuildSwordList()
			updateActiveSwordView()
		end,

		ShowRollResult = function(_, oldBlessing, newBlessing, costPaid)
			isRolling = false
			local def = Blessings.GetBlessingDef(newBlessing)
			local effectDesc = def and def.effectText or ""
			rollResultLabel.Text = ("✨ Rolled %s! (%s)"):format(newBlessing, effectDesc)
			rollResultLabel.TextColor3 = Theme.Colors.AuraGold

			-- Subtle text scale pop effect
			local originalSize = rollResultLabel.TextSize
			rollResultLabel.TextSize = 14
			task.delay(0.2, function()
				rollResultLabel.TextSize = originalSize
			end)

			updateActiveSwordView()
		end,

		SetOnRoll = function(_, callback)
			onRollCallback = callback
		end,

		SetOnClose = function(_, callback)
			onCloseCallback = callback
		end,

		SelectSword = function(_, uid: string)
			selectedUid = uid
			rebuildSwordList()
			updateActiveSwordView()
		end,

		ConfirmTierIIIReroll = function(_)
			if pendingRollAction then
				confirmModal.Visible = false
				local action = pendingRollAction
				pendingRollAction = nil
				action()
			end
		end,

		TriggerRollButton = function(_)
			local entry = getSelectedEntry()
			if not entry then
				return
			end
			if Blessings.IsTierIII(entry.blessing) then
				confirmMsg.Text = ("This sword has rare Tier III blessing '%s'! Rerolling will overwrite it."):format(entry.blessing or "")
				pendingRollAction = executeRoll
				confirmModal.Visible = true
			else
				executeRoll()
			end
		end,

		Destroy = function(_)
			screenGui:Destroy()
		end,
	}

	return self
end

return RunesmithUI
