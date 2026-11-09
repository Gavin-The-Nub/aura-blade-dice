--!strict
-- InventoryUI: Grid-based sword backpack with rarity colors, stats preview,
-- Equip/Unequip flow, Sell confirmation modal, and Auto-Sell filter chips.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local SalePrice = require(Shared:WaitForChild("SalePrice"))
local Config = ReplicatedStorage:WaitForChild("Config")
local Swords = require(Config:WaitForChild("Swords"))
local Grades = require(Config:WaitForChild("Grades"))
local Enchants = require(Config:WaitForChild("Enchants"))
local Blessings = require(Config:WaitForChild("Blessings"))
local GameConfig = require(Config:WaitForChild("Game"))
local Assets = require(Config:WaitForChild("Assets"))

local Components = Shared:WaitForChild("UI"):WaitForChild("Components")
local Popup = require(Components:WaitForChild("Popup"))
local Button = require(Components:WaitForChild("Button"))
local Panel = require(Components:WaitForChild("Panel"))
local GradeBadge = require(Components:WaitForChild("GradeBadge"))
local EnchantBadge = require(Components:WaitForChild("EnchantBadge"))
local BlessingBadge = require(Components:WaitForChild("BlessingBadge"))

export type OwnedSwordEntry = {
	uid: string,
	id: string,
	[string]: any,
}

export type InventoryUIInstance = {
	Open: (self: InventoryUIInstance, initialTab: ("Swords" | "Items")?) -> (),
	Close: (self: InventoryUIInstance) -> (),
	SetData: (
		self: InventoryUIInstance,
		ownedSwords: { OwnedSwordEntry },
		equippedUid: string,
		autoSellRules: { [string]: boolean },
		placedSwords: { [string]: string }?,
		gems: number?,
		tokens: number?
	) -> (),
	SetItemData: (self: InventoryUIInstance, gems: number, tokens: number) -> (),
	SetTab: (self: InventoryUIInstance, tab: "Swords" | "Items") -> (),
	SetOnEquip: (self: InventoryUIInstance, callback: (uid: string) -> ()) -> (),
	SetOnUnequip: (self: InventoryUIInstance, callback: () -> ()) -> (),
	SetOnSell: (self: InventoryUIInstance, callback: (uid: string) -> ()) -> (),
	SetOnToggleLock: (self: InventoryUIInstance, callback: (uid: string) -> ()) -> (),
	SetOnToggleAutoSell: (self: InventoryUIInstance, callback: (rarity: string, enabled: boolean) -> ()) -> (),
	SetOnEquipBest: (self: InventoryUIInstance, callback: () -> ()) -> (),
	SetEquipBestBusy: (self: InventoryUIInstance, isBusy: boolean) -> (),
	ShowEquipBestMessage: (self: InventoryUIInstance, message: string, isSuccess: boolean?) -> (),
	ShowFeedback: (self: InventoryUIInstance, message: string, isSuccess: boolean?) -> (),
	OpenAutoSell: (self: InventoryUIInstance) -> (),
	SetOnClose: (self: InventoryUIInstance, callback: () -> ()) -> (),
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

	-- Forward reference for close callback
	local onCloseCallback: (() -> ())? = nil

	-- Main Backpack Modal
	local popup = Popup.new({
		Title = "Backpack",
		Size = UDim2.new(0.92, 0, 0.86, 0),
		MaxWidth = 740,
		MaxHeight = 520,
		Parent = screenGui,
		OnClose = function()
			if onCloseCallback then
				onCloseCallback()
			end
		end,
	})

	local rootContent = popup.Content

	-- Left Tab Strip (Vertical)
	local tabStrip = Instance.new("Frame")
	tabStrip.Name = "TabStrip"
	tabStrip.Size = UDim2.new(0, 68, 1, 0)
	tabStrip.Position = UDim2.new(0, 0, 0, 0)
	tabStrip.BackgroundTransparency = 1
	tabStrip.Parent = rootContent

	local tabList = Instance.new("UIListLayout")
	tabList.FillDirection = Enum.FillDirection.Vertical
	tabList.SortOrder = Enum.SortOrder.LayoutOrder
	tabList.Padding = UDim.new(0, 8)
	tabList.Parent = tabStrip

	-- Main View Container
	local mainContainer = Instance.new("Frame")
	mainContainer.Name = "MainContainer"
	mainContainer.Size = UDim2.new(1, -76, 1, 0)
	mainContainer.Position = UDim2.new(0, 76, 0, 0)
	mainContainer.BackgroundTransparency = 1
	mainContainer.Parent = rootContent

	-- Swords View
	local swordsView = Instance.new("Frame")
	swordsView.Name = "SwordsView"
	swordsView.Size = UDim2.new(1, 0, 1, 0)
	swordsView.BackgroundTransparency = 1
	swordsView.Visible = true
	swordsView.Parent = mainContainer

	-- Items View
	local itemsView = Instance.new("Frame")
	itemsView.Name = "ItemsView"
	itemsView.Size = UDim2.new(1, 0, 1, 0)
	itemsView.BackgroundTransparency = 1
	itemsView.Visible = false
	itemsView.Parent = mainContainer

	local function createTabButton(name: string, label: string, iconText: string, layoutOrder: number)
		local btn = Instance.new("ImageButton")
		btn.Name = name .. "TabButton"
		btn.Size = UDim2.new(1, 0, 0, 64)
		btn.LayoutOrder = layoutOrder
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = Theme.Colors.BackgroundDark
		btn.BorderSizePixel = 0
		btn.Parent = tabStrip

		local corner = Instance.new("UICorner")
		corner.CornerRadius = Theme.Corner.Medium
		corner.Parent = btn

		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.Colors.Border
		stroke.Thickness = 1
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = btn

		local icon = Instance.new("TextLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(1, 0, 0, 30)
		icon.Position = UDim2.new(0, 0, 0, 6)
		icon.BackgroundTransparency = 1
		icon.Font = Theme.Fonts.Title
		icon.TextSize = 22
		icon.TextColor3 = Theme.Colors.TextMuted
		icon.Text = iconText
		icon.Parent = btn

		local text = Instance.new("TextLabel")
		text.Name = "Label"
		text.Size = UDim2.new(1, 0, 0, 18)
		text.Position = UDim2.new(0, 0, 0, 38)
		text.BackgroundTransparency = 1
		text.Font = Theme.Fonts.Button
		text.TextSize = 11
		text.TextColor3 = Theme.Colors.TextMuted
		text.Text = label
		text.Parent = btn

		return {
			Button = btn,
			Stroke = stroke,
			Icon = icon,
			Label = text,
		}
	end

	local swordsTab = createTabButton("Swords", "Swords", "🗡️", 1)
	local itemsTab = createTabButton("Items", "Items", "🎒", 2)

	local currentTab: "Swords" | "Items" = "Swords"
	local rebuildItemsGrid: () -> () -- forward reference

	local function setTab(tab: "Swords" | "Items")
		currentTab = tab
		if tab == "Swords" then
			swordsTab.Button.BackgroundColor3 = Theme.Colors.ButtonPrimary
			swordsTab.Stroke.Color = Theme.Colors.AuraCyan
			swordsTab.Stroke.Thickness = 2
			swordsTab.Icon.TextColor3 = Theme.Colors.TextPrimary
			swordsTab.Label.TextColor3 = Theme.Colors.TextPrimary

			itemsTab.Button.BackgroundColor3 = Theme.Colors.BackgroundDark
			itemsTab.Stroke.Color = Theme.Colors.Border
			itemsTab.Stroke.Thickness = 1
			itemsTab.Icon.TextColor3 = Theme.Colors.TextMuted
			itemsTab.Label.TextColor3 = Theme.Colors.TextMuted

			swordsView.Visible = true
			itemsView.Visible = false
		else
			itemsTab.Button.BackgroundColor3 = Theme.Colors.ButtonPrimary
			itemsTab.Stroke.Color = Theme.Colors.AuraPurple
			itemsTab.Stroke.Thickness = 2
			itemsTab.Icon.TextColor3 = Theme.Colors.TextPrimary
			itemsTab.Label.TextColor3 = Theme.Colors.TextPrimary

			swordsTab.Button.BackgroundColor3 = Theme.Colors.BackgroundDark
			swordsTab.Stroke.Color = Theme.Colors.Border
			swordsTab.Stroke.Thickness = 1
			swordsTab.Icon.TextColor3 = Theme.Colors.TextMuted
			swordsTab.Label.TextColor3 = Theme.Colors.TextMuted

			swordsView.Visible = false
			itemsView.Visible = true
			if rebuildItemsGrid then
				rebuildItemsGrid()
			end
		end
	end

	swordsTab.Button.MouseButton1Click:Connect(function()
		setTab("Swords")
	end)

	itemsTab.Button.MouseButton1Click:Connect(function()
		setTab("Items")
	end)

	-- Top Bar: Capacity + Equip Best on Row 1; Auto-Sell Header on Row 2; Rarity Chips on Row 3
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 80)
	topBar.Position = UDim2.new(0, 0, 0, 0)
	topBar.BackgroundTransparency = 1
	topBar.Parent = swordsView

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
	body.Parent = swordsView

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
	inspName.Size = UDim2.new(1, -180, 0, 24)
	inspName.Position = UDim2.new(0, 0, 0, 0)
	inspName.BackgroundTransparency = 1
	inspName.Font = Theme.Fonts.Title
	inspName.TextSize = 16
	inspName.TextColor3 = Theme.Colors.TextPrimary
	inspName.TextTruncate = Enum.TextTruncate.AtEnd
	inspName.Text = "Select a Sword"
	inspName.Parent = inspContent

	local inspGradeBadge = GradeBadge.new({
		Grade = nil,
		Size = UDim2.new(0, 28, 0, 20),
		Position = UDim2.new(1, 0, 0, 2),
		AnchorPoint = Vector2.new(1, 0),
		Parent = inspContent,
	})

	local inspEnchantBadge = EnchantBadge.new({
		Enchant = nil,
		Size = UDim2.new(0, 68, 0, 20),
		Position = UDim2.new(1, -32, 0, 2),
		AnchorPoint = Vector2.new(1, 0),
		Parent = inspContent,
	})

	local inspBlessingBadge = BlessingBadge.new({
		Blessing = nil,
		Size = UDim2.new(0, 72, 0, 20),
		Position = UDim2.new(1, -104, 0, 2),
		AnchorPoint = Vector2.new(1, 0),
		Parent = inspContent,
	})

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
	inspDamage.Size = UDim2.new(1, 0, 0, 18)
	inspDamage.Position = UDim2.new(0, 0, 0, 46)
	inspDamage.BackgroundTransparency = 1
	inspDamage.Font = Theme.Fonts.Body
	inspDamage.TextSize = 12
	inspDamage.TextColor3 = Theme.Colors.TextGold
	inspDamage.Text = ""
	inspDamage.Parent = inspContent

	local inspSellValue = Instance.new("TextLabel")
	inspSellValue.Name = "InspSellValue"
	inspSellValue.Size = UDim2.new(1, 0, 0, 18)
	inspSellValue.Position = UDim2.new(0, 0, 0, 66)
	inspSellValue.BackgroundTransparency = 1
	inspSellValue.Font = Theme.Fonts.Body
	inspSellValue.TextSize = 12
	inspSellValue.TextColor3 = Theme.Colors.AuraEmerald
	inspSellValue.Text = ""
	inspSellValue.Parent = inspContent

	local inspBlessingDesc = Instance.new("TextLabel")
	inspBlessingDesc.Name = "InspBlessingDesc"
	inspBlessingDesc.Size = UDim2.new(1, 0, 0, 18)
	inspBlessingDesc.Position = UDim2.new(0, 0, 0, 86)
	inspBlessingDesc.BackgroundTransparency = 1
	inspBlessingDesc.Font = Theme.Fonts.Body
	inspBlessingDesc.TextSize = 11
	inspBlessingDesc.TextColor3 = Theme.Colors.AuraCyan
	inspBlessingDesc.Text = ""
	inspBlessingDesc.Visible = false
	inspBlessingDesc.Parent = inspContent

	local inspStatus = Instance.new("TextLabel")
	inspStatus.Name = "InspStatus"
	inspStatus.Size = UDim2.new(1, 0, 0, 18)
	inspStatus.Position = UDim2.new(0, 0, 0, 106)
	inspStatus.BackgroundTransparency = 1
	inspStatus.Font = Theme.Fonts.Button
	inspStatus.TextSize = 11
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
	toastFrame.ZIndex = 35
	toastFrame.Visible = false
	toastFrame.Parent = mainContainer

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

	-- Action buttons container (Equip, Lock, and Sell)
	local actionContainer = Instance.new("Frame")
	actionContainer.Name = "ActionContainer"
	actionContainer.Size = UDim2.new(1, 0, 0, 114)
	actionContainer.Position = UDim2.new(0, 0, 1, 0)
	actionContainer.AnchorPoint = Vector2.new(0, 1)
	actionContainer.BackgroundTransparency = 1
	actionContainer.Parent = inspContent

	local equipButton = Button.new({
		Name = "EquipButton",
		Text = "EQUIP",
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor = Theme.Colors.ButtonPrimary,
		BorderColor = Theme.Colors.AuraCyan,
		TextColor = Theme.Colors.TextPrimary,
		CornerRadius = Theme.Corner.Medium,
		Parent = actionContainer,
	})

	local lockButton = Button.new({
		Name = "LockButton",
		Text = "LOCK",
		Size = UDim2.new(1, 0, 0, 32),
		Position = UDim2.new(0, 0, 0, 40),
		BackgroundColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.AuraGold,
		TextColor = Theme.Colors.TextGold,
		CornerRadius = Theme.Corner.Medium,
		Parent = actionContainer,
	})

	local sellButton = Button.new({
		Name = "SellButton",
		Text = "SELL",
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.new(0, 0, 0, 76),
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

	-- Items View: Top Bar
	local itemsTopBar = Instance.new("Frame")
	itemsTopBar.Name = "ItemsTopBar"
	itemsTopBar.Size = UDim2.new(1, 0, 0, 32)
	itemsTopBar.Position = UDim2.new(0, 0, 0, 0)
	itemsTopBar.BackgroundTransparency = 1
	itemsTopBar.Parent = itemsView

	local itemsTitle = Instance.new("TextLabel")
	itemsTitle.Name = "ItemsTitle"
	itemsTitle.Size = UDim2.new(0.6, 0, 0, 18)
	itemsTitle.Position = UDim2.new(0, 4, 0, 0)
	itemsTitle.BackgroundTransparency = 1
	itemsTitle.Font = Theme.Fonts.Title
	itemsTitle.TextSize = 13
	itemsTitle.TextColor3 = Theme.Colors.TextGold
	itemsTitle.TextXAlignment = Enum.TextXAlignment.Left
	itemsTitle.Text = "ITEMS & CURRENCIES"
	itemsTitle.Parent = itemsTopBar

	local itemsSubtitle = Instance.new("TextLabel")
	itemsSubtitle.Name = "ItemsSubtitle"
	itemsSubtitle.Size = UDim2.new(1, -8, 0, 14)
	itemsSubtitle.Position = UDim2.new(0, 4, 0, 16)
	itemsSubtitle.BackgroundTransparency = 1
	itemsSubtitle.Font = Theme.Fonts.Body
	itemsSubtitle.TextSize = 10
	itemsSubtitle.TextColor3 = Theme.Colors.TextMuted
	itemsSubtitle.TextXAlignment = Enum.TextXAlignment.Left
	itemsSubtitle.Text = "Collectible tokens, gems, and stackable items in your backpack."
	itemsSubtitle.Parent = itemsTopBar

	-- Items Body: Left Items Grid (63%), Right Items Inspector (35%)
	local itemsBody = Instance.new("Frame")
	itemsBody.Name = "ItemsBody"
	itemsBody.Size = UDim2.new(1, 0, 1, -38)
	itemsBody.Position = UDim2.new(0, 0, 0, 38)
	itemsBody.BackgroundTransparency = 1
	itemsBody.Parent = itemsView

	-- Left: Items Grid Panel
	local itemsGridPanel = Panel.new({
		Name = "ItemsGridPanel",
		Size = UDim2.new(0.63, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor = Theme.Colors.BackgroundDark,
		BorderColor = Theme.Colors.Border,
		Padding = UDim.new(0, 6),
		Parent = itemsBody,
	})

	local itemsGridScroll = Instance.new("ScrollingFrame")
	itemsGridScroll.Name = "ItemsGridScroll"
	itemsGridScroll.Size = UDim2.new(1, 0, 1, 0)
	itemsGridScroll.BackgroundTransparency = 1
	itemsGridScroll.ScrollBarThickness = 4
	itemsGridScroll.ScrollBarImageColor3 = Theme.Colors.AuraPurple
	itemsGridScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	itemsGridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	itemsGridScroll.Parent = itemsGridPanel.Content

	local itemsGridLayout = Instance.new("UIGridLayout")
	itemsGridLayout.CellSize = UDim2.new(0, 72, 0, 80)
	itemsGridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
	itemsGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	itemsGridLayout.Parent = itemsGridScroll

	-- Right: Items Inspector Detail Panel
	local itemsInspectorPanel = Panel.new({
		Name = "ItemsInspectorPanel",
		Size = UDim2.new(0.35, 0, 1, 0),
		Position = UDim2.new(0.65, 0, 0, 0),
		BackgroundColor = Theme.Colors.PanelBackground,
		BorderColor = Theme.Colors.Border,
		Padding = UDim.new(0, 10),
		Parent = itemsBody,
	})

	local itemInspContent = itemsInspectorPanel.Content

	local itemInspName = Instance.new("TextLabel")
	itemInspName.Name = "ItemInspName"
	itemInspName.Size = UDim2.new(1, 0, 0, 22)
	itemInspName.Position = UDim2.new(0, 0, 0, 2)
	itemInspName.BackgroundTransparency = 1
	itemInspName.Font = Theme.Fonts.Title
	itemInspName.TextSize = 16
	itemInspName.TextColor3 = Theme.Colors.TextPrimary
	itemInspName.TextTruncate = Enum.TextTruncate.AtEnd
	itemInspName.Text = "Item Details"
	itemInspName.Parent = itemInspContent

	local itemInspCategory = Instance.new("TextLabel")
	itemInspCategory.Name = "ItemInspCategory"
	itemInspCategory.Size = UDim2.new(1, 0, 0, 16)
	itemInspCategory.Position = UDim2.new(0, 0, 0, 24)
	itemInspCategory.BackgroundTransparency = 1
	itemInspCategory.Font = Theme.Fonts.Button
	itemInspCategory.TextSize = 10
	itemInspCategory.TextColor3 = Theme.Colors.AuraCyan
	itemInspCategory.Text = "CURRENCY"
	itemInspCategory.Parent = itemInspContent

	local itemInspIconFrame = Instance.new("Frame")
	itemInspIconFrame.Name = "ItemInspIconFrame"
	itemInspIconFrame.Size = UDim2.new(0, 64, 0, 64)
	itemInspIconFrame.Position = UDim2.new(0.5, 0, 0, 48)
	itemInspIconFrame.AnchorPoint = Vector2.new(0.5, 0)
	itemInspIconFrame.BackgroundColor3 = Theme.Colors.BackgroundDark
	itemInspIconFrame.Parent = itemInspContent

	local itemInspIconCorner = Instance.new("UICorner")
	itemInspIconCorner.CornerRadius = Theme.Corner.Medium
	itemInspIconCorner.Parent = itemInspIconFrame

	local itemInspIconStroke = Instance.new("UIStroke")
	itemInspIconStroke.Name = "IconStroke"
	itemInspIconStroke.Color = Theme.Colors.AuraCyan
	itemInspIconStroke.Thickness = 1.5
	itemInspIconStroke.Parent = itemInspIconFrame

	local itemInspIconLabel = Instance.new("TextLabel")
	itemInspIconLabel.Name = "IconLabel"
	itemInspIconLabel.Size = UDim2.new(1, 0, 1, 0)
	itemInspIconLabel.BackgroundTransparency = 1
	itemInspIconLabel.Font = Theme.Fonts.Title
	itemInspIconLabel.TextSize = 34
	itemInspIconLabel.Text = "💎"
	itemInspIconLabel.Parent = itemInspIconFrame

	local itemInspCount = Instance.new("TextLabel")
	itemInspCount.Name = "ItemInspCount"
	itemInspCount.Size = UDim2.new(1, 0, 0, 20)
	itemInspCount.Position = UDim2.new(0, 0, 0, 120)
	itemInspCount.BackgroundTransparency = 1
	itemInspCount.Font = Theme.Fonts.Title
	itemInspCount.TextSize = 14
	itemInspCount.TextColor3 = Theme.Colors.TextGold
	itemInspCount.Text = "Owned: 0"
	itemInspCount.Parent = itemInspContent

	local itemInspDesc = Instance.new("TextLabel")
	itemInspDesc.Name = "ItemInspDesc"
	itemInspDesc.Size = UDim2.new(1, 0, 0, 72)
	itemInspDesc.Position = UDim2.new(0, 0, 0, 144)
	itemInspDesc.BackgroundTransparency = 1
	itemInspDesc.Font = Theme.Fonts.Body
	itemInspDesc.TextSize = 11
	itemInspDesc.TextColor3 = Theme.Colors.TextSecondary
	itemInspDesc.TextWrapped = true
	itemInspDesc.TextYAlignment = Enum.TextYAlignment.Top
	itemInspDesc.Text = ""
	itemInspDesc.Parent = itemInspContent

	local itemInspTip = Instance.new("TextLabel")
	itemInspTip.Name = "ItemInspTip"
	itemInspTip.Size = UDim2.new(1, 0, 0, 60)
	itemInspTip.Position = UDim2.new(0, 0, 0, 220)
	itemInspTip.BackgroundTransparency = 1
	itemInspTip.Font = Theme.Fonts.Body
	itemInspTip.TextSize = 11
	itemInspTip.TextColor3 = Theme.Colors.AuraCyan
	itemInspTip.TextWrapped = true
	itemInspTip.TextYAlignment = Enum.TextYAlignment.Top
	itemInspTip.Text = ""
	itemInspTip.Parent = itemInspContent

	-- Internal state
	local currentOwnedSwords: { OwnedSwordEntry } = {}
	local currentEquippedUid = ""
	local currentPlacedSwords: { [string]: string } = {}
	local currentAutoSellRules: { [string]: boolean } = {}
	local selectedUid: string? = nil

	local currentGems: number = 0
	local currentTokens: number = 0
	local selectedItemId: string = "Gems"

	type ItemEntry = {
		id: string,
		name: string,
		category: string,
		icon: string,
		borderColor: Color3,
		description: string,
		tip: string,
		getAmount: () -> number,
	}

	local itemDefinitions: { ItemEntry } = {
		{
			id = "Gems",
			name = "Gems",
			category = "CURRENCY",
			icon = "💎",
			borderColor = Theme.Colors.AuraCyan,
			description = "Precious radiant crystals awarded from Rebirths and boss trials. Required at the Runesmith to roll and upgrade sword Grades.",
			tip = "💡 Visit the Runesmith station to forge Grades onto your blades (1 Gem per roll).",
			getAmount = function()
				return currentGems
			end,
		},
		{
			id = "EnchantTokens",
			name = "Tickets",
			category = "UPGRADE ITEM",
			icon = "🎟️",
			borderColor = Theme.Colors.AuraPurple,
			description = "Enchanted trial tickets. Used at the Enchanter to reroll mystical passive abilities and modifiers onto your swords.",
			tip = "💡 Visit the Enchanter station in the Plaza to enchant your weapon.",
			getAmount = function()
				return currentTokens
			end,
		},
	}

	local function updateItemsInspector()
		local activeDef: ItemEntry? = nil
		for _, item in itemDefinitions do
			if item.id == selectedItemId then
				activeDef = item
				break
			end
		end
		if not activeDef then
			activeDef = itemDefinitions[1]
			if activeDef then
				selectedItemId = activeDef.id
			end
		end

		if activeDef then
			itemInspName.Text = activeDef.name
			itemInspCategory.Text = activeDef.category
			itemInspCategory.TextColor3 = activeDef.borderColor
			itemInspIconLabel.Text = activeDef.icon
			itemInspIconStroke.Color = activeDef.borderColor
			itemInspCount.Text = "Owned: " .. NumberFormat.format(activeDef.getAmount())
			itemInspDesc.Text = activeDef.description
			itemInspTip.Text = activeDef.tip
		end
	end

	rebuildItemsGrid = function()
		for _, child in itemsGridScroll:GetChildren() do
			if not child:IsA("UIGridLayout") then
				child:Destroy()
			end
		end

		for idx, item in ipairs(itemDefinitions) do
			local amount = item.getAmount()
			local isSelected = (item.id == selectedItemId)

			local card = Instance.new("ImageButton")
			card.Name = "Item_" .. item.id
			card.Size = UDim2.new(0, 72, 0, 80)
			card.BackgroundColor3 = if isSelected then Theme.Colors.ButtonPrimary else Theme.Colors.BackgroundDark
			card.AutoButtonColor = false
			card.LayoutOrder = idx
			card.Parent = itemsGridScroll

			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = Theme.Corner.Medium
			cardCorner.Parent = card

			local cardStroke = Instance.new("UIStroke")
			cardStroke.Color = if isSelected then Theme.Colors.AuraGold else item.borderColor
			cardStroke.Thickness = if isSelected then 2.5 else 1.5
			cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			cardStroke.Parent = card

			local iconLabel = Instance.new("TextLabel")
			iconLabel.Name = "Icon"
			iconLabel.Size = UDim2.new(1, 0, 0, 36)
			iconLabel.Position = UDim2.new(0, 0, 0, 8)
			iconLabel.BackgroundTransparency = 1
			iconLabel.Font = Theme.Fonts.Title
			iconLabel.TextSize = 28
			iconLabel.Text = item.icon
			iconLabel.Parent = card

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "Name"
			nameLabel.Size = UDim2.new(1, -6, 0, 14)
			nameLabel.Position = UDim2.new(0.5, 0, 0, 44)
			nameLabel.AnchorPoint = Vector2.new(0.5, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Theme.Fonts.Button
			nameLabel.TextSize = 10
			nameLabel.TextColor3 = Theme.Colors.TextPrimary
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Text = item.name
			nameLabel.Parent = card

			local countLabel = Instance.new("TextLabel")
			countLabel.Name = "Count"
			countLabel.Size = UDim2.new(1, -8, 0, 16)
			countLabel.Position = UDim2.new(1, -4, 1, -4)
			countLabel.AnchorPoint = Vector2.new(1, 1)
			countLabel.BackgroundTransparency = 1
			countLabel.Font = Theme.Fonts.Number
			countLabel.TextSize = 12
			countLabel.TextColor3 = Theme.Colors.TextGold
			countLabel.TextXAlignment = Enum.TextXAlignment.Right
			countLabel.Text = "x" .. NumberFormat.format(amount)
			countLabel.Parent = card

			local countStroke = Instance.new("UIStroke")
			countStroke.Color = Theme.TextStroke.Color
			countStroke.Thickness = 1.5
			countStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			countStroke.Parent = countLabel

			card.MouseButton1Click:Connect(function()
				selectedItemId = item.id
				rebuildItemsGrid()
				updateItemsInspector()
			end)
		end

		-- Visual empty slots to fill out the backpack grid
		local totalSlotsToShow = math.max(16, #itemDefinitions + 10)
		for i = #itemDefinitions + 1, totalSlotsToShow do
			local slot = Instance.new("Frame")
			slot.Name = "EmptySlot_" .. i
			slot.Size = UDim2.new(0, 72, 0, 80)
			slot.BackgroundColor3 = Theme.Colors.BackgroundDark
			slot.BackgroundTransparency = 0.55
			slot.LayoutOrder = i
			slot.Parent = itemsGridScroll

			local slotCorner = Instance.new("UICorner")
			slotCorner.CornerRadius = Theme.Corner.Medium
			slotCorner.Parent = slot

			local slotStroke = Instance.new("UIStroke")
			slotStroke.Color = Theme.Colors.Border
			slotStroke.Thickness = 1
			slotStroke.Transparency = 0.5
			slotStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			slotStroke.Parent = slot
		end

		updateItemsInspector()
	end

	local onEquipCallback: ((string) -> ())? = nil
	local onUnequipCallback: (() -> ())? = nil
	local onSellCallback: ((string) -> ())? = nil
	local onToggleLockCallback: ((string) -> ())? = nil
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

			-- Padlock badge on top-left if sword is locked
			if entry.locked == true then
				local lockBadge = Instance.new("Frame")
				lockBadge.Name = "LockBadge"
				lockBadge.Size = UDim2.new(0, 18, 0, 18)
				lockBadge.Position = UDim2.new(0, 2, 0, 2)
				lockBadge.AnchorPoint = Vector2.new(0, 0)
				lockBadge.BackgroundColor3 = Theme.Colors.PanelBackground
				lockBadge.BackgroundTransparency = 0.2
				lockBadge.BorderSizePixel = 0
				lockBadge.Parent = card

				local lockCorner = Instance.new("UICorner")
				lockCorner.CornerRadius = Theme.Corner.Round
				lockCorner.Parent = lockBadge

				local lockStroke = Instance.new("UIStroke")
				lockStroke.Color = Theme.Colors.AuraGold
				lockStroke.Thickness = 1
				lockStroke.Parent = lockBadge

				local lockIcon = Instance.new("TextLabel")
				lockIcon.Name = "LockIcon"
				lockIcon.Size = UDim2.new(1, 0, 1, 0)
				lockIcon.BackgroundTransparency = 1
				lockIcon.Text = "🔒"
				lockIcon.TextSize = 10
				lockIcon.TextColor3 = Theme.Colors.AuraGold
				lockIcon.Parent = lockBadge
			end

			-- Grade badge on top-right if sword has a grade
			local hasGrade = typeof(entry.grade) == "string" and entry.grade ~= ""
			if hasGrade then
				GradeBadge.new({
					Grade = entry.grade,
					Size = UDim2.new(0, 22, 0, 16),
					Position = UDim2.new(1, -2, 0, 2),
					AnchorPoint = Vector2.new(1, 0),
					Parent = card,
					ZIndex = 6,
				})
			end

			-- Enchant badge on top-right (below Grade badge if graded, else top-right)
			local hasEnchant = typeof(entry.enchant) == "string" and entry.enchant ~= ""
			if hasEnchant then
				EnchantBadge.new({
					Enchant = entry.enchant,
					Size = UDim2.new(0, 48, 0, 15),
					Position = if hasGrade then UDim2.new(1, -2, 0, 20) else UDim2.new(1, -2, 0, 2),
					AnchorPoint = Vector2.new(1, 0),
					Parent = card,
					ZIndex = 6,
					TextSize = 9,
				})
			end

			-- Blessing badge on top-right (stacked below Enchant/Grade)
			if typeof(entry.blessing) == "string" and entry.blessing ~= "" then
				local yPos = 2
				if hasGrade and hasEnchant then
					yPos = 37
				elseif hasGrade or hasEnchant then
					yPos = 20
				end
				BlessingBadge.new({
					Blessing = entry.blessing,
					Size = UDim2.new(0, 48, 0, 15),
					Position = UDim2.new(1, -2, 0, yPos),
					AnchorPoint = Vector2.new(1, 0),
					Parent = card,
					ZIndex = 6,
					TextSize = 8,
				})
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
			inspSellValue.Text = ""
			inspStatus.Text = ""
			equipButton:SetEnabled(false)
			equipButton:SetText("EQUIP")
			lockButton:SetEnabled(false)
			lockButton:SetText("LOCK")
			sellButton:SetEnabled(false)
			sellButton:SetText("SELL")
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
			inspSellValue.Text = ""
			inspBlessingDesc.Text = ""
			inspBlessingDesc.Visible = false
			inspStatus.Text = ""
			GradeBadge.Update(inspGradeBadge, nil)
			EnchantBadge.Update(inspEnchantBadge, nil)
			BlessingBadge.Update(inspBlessingBadge, nil)
			equipButton:SetEnabled(false)
			lockButton:SetEnabled(false)
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

		local isLocked = (selectedEntry.locked == true)
		local salePrice = SalePrice.calculate(selectedEntry)

		inspName.Text = swordDef and swordDef.name or "Sword"
		inspName.TextColor3 = rarityColor
		inspRarity.Text = ("%s (1 in %s)"):format(rarityName:upper(), swordDef and NumberFormat.format(swordDef.baseOdds) or "?")
		inspRarity.TextColor3 = rarityColor

		GradeBadge.Update(inspGradeBadge, selectedEntry.grade)
		EnchantBadge.Update(inspEnchantBadge, selectedEntry.enchant)
		BlessingBadge.Update(inspBlessingBadge, selectedEntry.blessing)

		if selectedEntry.blessing and selectedEntry.blessing ~= "" then
			local bDef = Blessings.GetBlessingDef(selectedEntry.blessing)
			inspBlessingDesc.Text = ("Blessing: %s"):format(bDef and bDef.effectText or selectedEntry.blessing)
			inspBlessingDesc.Visible = true
		else
			inspBlessingDesc.Text = ""
			inspBlessingDesc.Visible = false
		end

		local gradeMult = Grades.GetMultiplier(selectedEntry.grade)
		local enchantMult = Enchants.GetMultiplier(selectedEntry.enchant)
		local totalMult = gradeMult * enchantMult

		if swordDef and totalMult > 1 then
			local effectiveDmg = math.floor((swordDef.baseDamage * totalMult) + 0.5)
			if gradeMult > 1 and enchantMult > 1 then
				inspDamage.Text = ("Damage: %s Gold/Tap (Total x%.2f: %s x%.2f, %s x%.2f)"):format(
					NumberFormat.format(effectiveDmg),
					totalMult,
					selectedEntry.grade or "",
					gradeMult,
					selectedEntry.enchant or "",
					enchantMult
				)
			elseif gradeMult > 1 then
				inspDamage.Text = ("Damage: %s Gold/Tap (%s x%.2f)"):format(
					NumberFormat.format(effectiveDmg),
					selectedEntry.grade or "",
					gradeMult
				)
			else
				inspDamage.Text = ("Damage: %s Gold/Tap (%s x%.2f)"):format(
					NumberFormat.format(effectiveDmg),
					selectedEntry.enchant or "",
					enchantMult
				)
			end
		else
			inspDamage.Text = ("Base Damage: %s Gold/Tap"):format(swordDef and NumberFormat.format(swordDef.baseDamage) or "1")
		end
		inspSellValue.Text = ("Sell Value: +%s Gold"):format(NumberFormat.format(salePrice))

		lockButton:SetEnabled(true)
		if isLocked then
			lockButton:SetText("UNLOCK")
			lockButton:SetBorderColor(Theme.Colors.Border)
			lockButton:SetTextColor(Theme.Colors.TextPrimary)
		else
			lockButton:SetText("LOCK")
			lockButton:SetBorderColor(Theme.Colors.AuraGold)
			lockButton:SetTextColor(Theme.Colors.TextGold)
		end

		if isEquipped then
			inspStatus.Text = "STATUS: EQUIPPED"
			inspStatus.TextColor3 = Theme.Colors.AuraEmerald
			equipButton:SetText("UNEQUIP")
			equipButton:SetBorderColor(Theme.Colors.Border)
			equipButton:SetEnabled(true)
			sellButton:SetEnabled(false)
			sellButton:SetText("SELL")
			sellButton:SetBorderColor(Theme.Colors.BorderSubtle)
			sellButton:SetTextColor(Theme.Colors.TextMuted)
		elseif placedSlot ~= nil then
			inspStatus.Text = ("STATUS: PLACED ON PEDESTAL #%d"):format(placedSlot)
			inspStatus.TextColor3 = Theme.Colors.AuraCyan
			equipButton:SetText("PLACED")
			equipButton:SetBorderColor(Theme.Colors.Border)
			equipButton:SetEnabled(false) -- Disabled for placed swords
			sellButton:SetEnabled(false)  -- Disabled for placed swords
			sellButton:SetText("SELL")
			sellButton:SetBorderColor(Theme.Colors.BorderSubtle)
			sellButton:SetTextColor(Theme.Colors.TextMuted)
		else
			inspStatus.Text = "STATUS: IN BACKPACK"
			inspStatus.TextColor3 = Theme.Colors.TextSecondary
			equipButton:SetText("EQUIP")
			equipButton:SetBorderColor(rarityColor)
			equipButton:SetEnabled(true)
			if isLocked then
				sellButton:SetEnabled(false)
				sellButton:SetText("Locked")
				sellButton:SetBorderColor(Theme.Colors.BorderSubtle)
				sellButton:SetTextColor(Theme.Colors.TextMuted)
			else
				sellButton:SetEnabled(true)
				sellButton:SetText(("SELL (+%s)"):format(NumberFormat.format(salePrice)))
				sellButton:SetBorderColor(Theme.Colors.ButtonClose)
				sellButton:SetTextColor(Theme.Colors.ButtonClose)
			end
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

	lockButton.Instance.Activated:Connect(function()
		if not selectedUid then return end
		if onToggleLockCallback then
			onToggleLockCallback(selectedUid)
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
		if not selectedEntry or selectedEntry.locked == true then return end
		local swordDef = selectedEntry and swordDefMap[selectedEntry.id]
		local name = swordDef and swordDef.name or "this sword"
		local salePrice = SalePrice.calculate(selectedEntry)

		local warnings = {}
		if selectedEntry.grade and selectedEntry.grade ~= "" then
			table.insert(warnings, "Grade " .. selectedEntry.grade)
		end
		if selectedEntry.enchant and selectedEntry.enchant ~= "" then
			table.insert(warnings, "Enchant " .. selectedEntry.enchant)
		end
		if selectedEntry.blessing and selectedEntry.blessing ~= "" then
			table.insert(warnings, "Blessing " .. selectedEntry.blessing)
		end

		local warnText = ""
		if #warnings > 0 then
			warnText = ("\n\n⚠️ Warning: This sword has %s!"):format(table.concat(warnings, ", "))
		end

		sellConfirmText.Text = ("Are you sure you want to sell %s for +%s Gold?%s\n\n(This action cannot be undone.)"):format(name, NumberFormat.format(salePrice), warnText)
		sellConfirmPopup:Open()
	end)

	confirmSellBtn.Instance.Activated:Connect(function()
		sellConfirmPopup:Close()
		if selectedUid and onSellCallback then
			onSellCallback(selectedUid)
		end
	end)

	local self: InventoryUIInstance = {
		Open = function(_, initialTab: ("Swords" | "Items")?)
			if initialTab then
				setTab(initialTab)
			end
			popup:Open()
		end,
		Close = function(_)
			popup:Close()
			sellConfirmPopup:Close()
			if onCloseCallback then
				onCloseCallback()
			end
		end,
		SetData = function(
			_,
			ownedSwords: { OwnedSwordEntry },
			equippedUid: string,
			autoSellRules: { [string]: boolean },
			placedSwords: { [string]: string }?,
			gems: number?,
			tokens: number?
		)
			currentOwnedSwords = ownedSwords or {}
			currentEquippedUid = equippedUid or ""
			currentAutoSellRules = autoSellRules or {}
			currentPlacedSwords = placedSwords or {}
			if type(gems) == "number" then
				currentGems = gems
			end
			if type(tokens) == "number" then
				currentTokens = tokens
			end

			-- Cleanly deselect if the selected sword was sold or removed
			local stillExists = false
			if selectedUid then
				for _, e in currentOwnedSwords do
					if e.uid == selectedUid then
						stillExists = true
						break
					end
				end
			end
			if not stillExists then
				selectedUid = nil
			end

			updateChips()
			rebuildGrid()
			rebuildItemsGrid()
		end,
		SetItemData = function(_, gems: number, tokens: number)
			if type(gems) == "number" then
				currentGems = gems
			end
			if type(tokens) == "number" then
				currentTokens = tokens
			end
			rebuildItemsGrid()
		end,
		SetTab = function(_, tab: "Swords" | "Items")
			setTab(tab)
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
		SetOnToggleLock = function(_, callback: (uid: string) -> ())
			onToggleLockCallback = callback
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
		ShowFeedback = function(_, message: string, isSuccess: boolean?)
			showFeedback(message, isSuccess)
		end,
		OpenAutoSell = function(this)
			this:Open("Swords")
		end,
		SetOnClose = function(_, callback: () -> ())
			onCloseCallback = callback
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
			lockButton:Destroy()
			sellButton:Destroy()
			itemsInspectorPanel:Destroy()
			itemsGridPanel:Destroy()
			inspectorPanel:Destroy()
			gridPanel:Destroy()
			sellConfirmPopup:Destroy()
			popup:Destroy()
			if ownsScreenGui then
				screenGui:Destroy()
			end
		end,
	}

	setTab("Swords")
	rebuildItemsGrid()

	return self
end

return InventoryUI
