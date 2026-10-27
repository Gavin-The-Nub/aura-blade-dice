--!strict
-- EnchanterUI: Mobile-first modal for sword enchanting and auto enchant roll.
-- Pick a sword from inventory (including equipped and placed swords),
-- view current enchant, multiplier, and passive effect description, roll enchant for 1 Token
-- with confirmation warning for high enchants (Sovereign+), and set target enchant for automated rolling.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Config = ReplicatedStorage:WaitForChild("Config")
local Swords = require(Config:WaitForChild("Swords"))
local Enchants = require(Config:WaitForChild("Enchants"))

local Components = Shared:WaitForChild("UI"):WaitForChild("Components")
local Popup = require(Components:WaitForChild("Popup"))
local Button = require(Components:WaitForChild("Button"))
local EnchantBadge = require(Components:WaitForChild("EnchantBadge"))

export type OwnedSwordEntry = {
	uid: string,
	id: string,
	grade: string?,
	enchant: string?,
	locked: boolean?,
	[string]: any,
}

export type EnchanterUIInstance = {
	Open: (
		self: EnchanterUIInstance,
		ownedSwords: { OwnedSwordEntry },
		equippedUid: string,
		placedUids: { [string]: boolean },
		tokenBalance: number
	) -> (),
	Close: (self: EnchanterUIInstance) -> (),
	UpdateTokens: (self: EnchanterUIInstance, tokens: number) -> (),
	UpdateSwords: (
		self: EnchanterUIInstance,
		ownedSwords: { OwnedSwordEntry },
		equippedUid: string,
		placedUids: { [string]: boolean }
	) -> (),
	ShowRollResult: (self: EnchanterUIInstance, oldEnchant: string, newEnchant: string) -> (),
	UpdateAutoProgress: (
		self: EnchanterUIInstance,
		rollsDone: number,
		tokensSpent: number,
		lastEnchant: string,
		isRunning: boolean,
		stopReason: string?
	) -> (),
	SetOnRoll: (self: EnchanterUIInstance, callback: (uid: string) -> ()) -> (),
	SetOnStartAuto: (self: EnchanterUIInstance, callback: (uid: string, targetEnchant: string, maxTokens: number?) -> ()) -> (),
	SetOnStopAuto: (self: EnchanterUIInstance, callback: () -> ()) -> (),
	SetOnClose: (self: EnchanterUIInstance, callback: () -> ()) -> (),
	Destroy: (self: EnchanterUIInstance) -> (),
}

local EnchanterUI = {}

local swordDefMap: { [string]: Swords.SwordDef } = {}
for _, def in Swords do
	swordDefMap[def.id] = def
end

function EnchanterUI.new(parentGui: Instance): EnchanterUIInstance
	local screenGui: ScreenGui
	if parentGui:IsA("ScreenGui") then
		screenGui = parentGui
	else
		local sg = Instance.new("ScreenGui")
		sg.Name = "AuraBladeEnchanterGui"
		sg.ResetOnSpawn = false
		sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		sg.DisplayOrder = 15
		sg.Parent = parentGui
		screenGui = sg
	end

	-- State
	local currentSwords: { OwnedSwordEntry } = {}
	local currentEquippedUid = ""
	local currentPlacedMap: { [string]: boolean } = {}
	local currentTokens = 0
	local selectedUid: string? = nil
	local selectedTargetEnchant = "Executioner"
	local isAutoRunning = false

	local onRollCallback: ((string) -> ())? = nil
	local onStartAutoCallback: ((string, string, number?) -> ())? = nil
	local onStopAutoCallback: (() -> ())? = nil
	local onCloseCallback: (() -> ())? = nil

	local popup = Popup.new({
		Title = "Enchanter",
		WidthScale = 0.94,
		MaxWidth = 620,
		HeightScale = 0.86,
		MaxHeight = 540,
		Parent = screenGui,
		OnClose = function()
			if onCloseCallback then
				onCloseCallback()
			end
		end,
	})

	local root = popup.Content

	-- Confirmation Modal overlay (for high-enchant replacement)
	local confirmModal = Instance.new("Frame")
	confirmModal.Name = "ConfirmModal"
	confirmModal.Size = UDim2.new(1, 0, 1, 0)
	confirmModal.Position = UDim2.new(0, 0, 0, 0)
	confirmModal.BackgroundColor3 = Theme.Colors.PanelOverlay
	confirmModal.BackgroundTransparency = 0.35
	confirmModal.Visible = false
	confirmModal.ZIndex = 30
	confirmModal.Parent = root

	local confirmCard = Instance.new("Frame")
	confirmCard.Name = "ConfirmCard"
	confirmCard.Size = UDim2.new(0.85, 0, 0, 190)
	confirmCard.Position = UDim2.new(0.5, 0, 0.5, 0)
	confirmCard.AnchorPoint = Vector2.new(0.5, 0.5)
	confirmCard.BackgroundColor3 = Theme.Colors.PanelBackground
	confirmCard.BorderSizePixel = 0
	confirmCard.ZIndex = 31
	confirmCard.Parent = confirmModal

	local confirmCorner = Instance.new("UICorner")
	confirmCorner.CornerRadius = Theme.Corner.Medium
	confirmCorner.Parent = confirmCard

	local confirmStroke = Instance.new("UIStroke")
	confirmStroke.Color = Theme.Colors.AuraCrimson
	confirmStroke.Thickness = Theme.Stroke.WidthThick
	confirmStroke.Parent = confirmCard

	local confirmTitle = Instance.new("TextLabel")
	confirmTitle.Name = "ConfirmTitle"
	confirmTitle.Size = UDim2.new(1, -20, 0, 30)
	confirmTitle.Position = UDim2.new(0, 10, 0, 12)
	confirmTitle.BackgroundTransparency = 1
	confirmTitle.Font = Theme.Fonts.Title
	confirmTitle.TextSize = 16
	confirmTitle.TextColor3 = Theme.Colors.AuraCrimson
	confirmTitle.Text = "⚠️ High Enchant Warning"
	confirmTitle.ZIndex = 32
	confirmTitle.Parent = confirmCard

	local confirmMsg = Instance.new("TextLabel")
	confirmMsg.Name = "ConfirmMsg"
	confirmMsg.Size = UDim2.new(1, -24, 0, 60)
	confirmMsg.Position = UDim2.new(0, 12, 0, 46)
	confirmMsg.BackgroundTransparency = 1
	confirmMsg.Font = Theme.Fonts.Body
	confirmMsg.TextSize = 13
	confirmMsg.TextColor3 = Theme.Colors.TextPrimary
	confirmMsg.TextWrapped = true
	confirmMsg.Text = "This sword has a rare Enchant! Rerolling will permanently overwrite it."
	confirmMsg.ZIndex = 32
	confirmMsg.Parent = confirmCard

	local pendingRollAction: (() -> ())? = nil

	local confirmCancelBtn = Button.new({
		Name = "CancelBtn",
		Text = "CANCEL",
		Size = UDim2.new(0.44, 0, 0, 36),
		Position = UDim2.new(0.05, 0, 1, -12),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.Border,
		TextColor = Theme.Colors.TextSecondary,
		Parent = confirmCard,
		OnClick = function()
			pendingRollAction = nil
			confirmModal.Visible = false
		end,
	})

	local confirmProceedBtn = Button.new({
		Name = "ProceedBtn",
		Text = "OVERWRITE",
		Size = UDim2.new(0.44, 0, 0, 36),
		Position = UDim2.new(0.95, 0, 1, -12),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor = Theme.Colors.ButtonPrimary,
		BorderColor = Theme.Colors.AuraCrimson,
		TextColor = Theme.Colors.AuraCrimson,
		Parent = confirmCard,
		OnClick = function()
			local act = pendingRollAction
			pendingRollAction = nil
			confirmModal.Visible = false
			if act then
				act()
			end
		end,
	})

	-- Two-column Layout: Left = Swords list, Right = Active Enchanting controls
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, -20, 1, -20)
	body.Position = UDim2.new(0, 10, 0, 10)
	body.BackgroundTransparency = 1
	body.Parent = root

	-- Left: Sword selector list
	local listContainer = Instance.new("Frame")
	listContainer.Name = "ListContainer"
	listContainer.Size = UDim2.new(0.40, -6, 1, 0)
	listContainer.Position = UDim2.new(0, 0, 0, 0)
	listContainer.BackgroundColor3 = Theme.Colors.BackgroundCard
	listContainer.BackgroundTransparency = 0.2
	listContainer.Parent = body

	local listCorner = Instance.new("UICorner")
	listCorner.CornerRadius = Theme.Corner.Medium
	listCorner.Parent = listContainer

	local listStroke = Instance.new("UIStroke")
	listStroke.Color = Theme.Colors.BorderSubtle
	listStroke.Thickness = Theme.Stroke.WidthDefault
	listStroke.Parent = listContainer

	local listTitle = Instance.new("TextLabel")
	listTitle.Name = "ListTitle"
	listTitle.Size = UDim2.new(1, -12, 0, 26)
	listTitle.Position = UDim2.new(0, 8, 0, 6)
	listTitle.BackgroundTransparency = 1
	listTitle.Font = Theme.Fonts.Button
	listTitle.TextSize = 12
	listTitle.TextColor3 = Theme.Colors.TextSecondary
	listTitle.TextXAlignment = Enum.TextXAlignment.Left
	listTitle.Text = "SELECT SWORD"
	listTitle.Parent = listContainer

	local listScroll = Instance.new("ScrollingFrame")
	listScroll.Name = "ListScroll"
	listScroll.Size = UDim2.new(1, -12, 1, -38)
	listScroll.Position = UDim2.new(0, 6, 0, 32)
	listScroll.BackgroundTransparency = 1
	listScroll.BorderSizePixel = 0
	listScroll.ScrollBarThickness = 4
	listScroll.ScrollBarImageColor3 = Theme.Colors.BorderGlow
	listScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listScroll.Parent = listContainer

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = listScroll

	-- Right: Active Enchanting Panel
	local rightPanel = Instance.new("Frame")
	rightPanel.Name = "RightPanel"
	rightPanel.Size = UDim2.new(0.60, -6, 1, 0)
	rightPanel.Position = UDim2.new(1, 0, 0, 0)
	rightPanel.AnchorPoint = Vector2.new(1, 0)
	rightPanel.BackgroundColor3 = Theme.Colors.PanelBackground
	rightPanel.BackgroundTransparency = 0.15
	rightPanel.Parent = body

	local rightCorner = Instance.new("UICorner")
	rightCorner.CornerRadius = Theme.Corner.Medium
	rightCorner.Parent = rightPanel

	local rightStroke = Instance.new("UIStroke")
	rightStroke.Color = Theme.Colors.Border
	rightStroke.Thickness = Theme.Stroke.WidthDefault
	rightStroke.Parent = rightPanel

	local rightScroll = Instance.new("ScrollingFrame")
	rightScroll.Name = "RightScroll"
	rightScroll.Size = UDim2.new(1, -16, 1, -16)
	rightScroll.Position = UDim2.new(0, 8, 0, 8)
	rightScroll.BackgroundTransparency = 1
	rightScroll.BorderSizePixel = 0
	rightScroll.ScrollBarThickness = 4
	rightScroll.ScrollBarImageColor3 = Theme.Colors.BorderGlow
	rightScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	rightScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rightScroll.Parent = rightPanel

	local rightLayout = Instance.new("UIListLayout")
	rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rightLayout.FillDirection = Enum.FillDirection.Vertical
	rightLayout.Padding = UDim.new(0, 10)
	rightLayout.Parent = rightScroll

	-- Selected Sword Detail Card
	local detailCard = Instance.new("Frame")
	detailCard.Name = "DetailCard"
	detailCard.LayoutOrder = 1
	detailCard.Size = UDim2.new(1, 0, 0, 88)
	detailCard.BackgroundColor3 = Theme.Colors.BackgroundCard
	detailCard.BackgroundTransparency = 0.2
	detailCard.Parent = rightScroll

	local detailCorner = Instance.new("UICorner")
	detailCorner.CornerRadius = Theme.Corner.Small
	detailCorner.Parent = detailCard

	local detailStroke = Instance.new("UIStroke")
	detailStroke.Color = Theme.Colors.BorderSubtle
	detailStroke.Thickness = 1
	detailStroke.Parent = detailCard

	local swordNameLabel = Instance.new("TextLabel")
	swordNameLabel.Name = "SwordName"
	swordNameLabel.Size = UDim2.new(1, -80, 0, 24)
	swordNameLabel.Position = UDim2.new(0, 10, 0, 6)
	swordNameLabel.BackgroundTransparency = 1
	swordNameLabel.Font = Theme.Fonts.Title
	swordNameLabel.TextSize = 15
	swordNameLabel.TextColor3 = Theme.Colors.AuraCyan
	swordNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	swordNameLabel.Text = "No Sword Selected"
	swordNameLabel.Parent = detailCard

	local currentEnchantBadge = EnchantBadge.new({
		Enchant = nil,
		Size = UDim2.new(0, 64, 0, 22),
		Position = UDim2.new(1, -8, 0, 6),
		AnchorPoint = Vector2.new(1, 0),
		Parent = detailCard,
	})

	local swordStatsLabel = Instance.new("TextLabel")
	swordStatsLabel.Name = "SwordStats"
	swordStatsLabel.Size = UDim2.new(1, -20, 0, 18)
	swordStatsLabel.Position = UDim2.new(0, 10, 0, 30)
	swordStatsLabel.BackgroundTransparency = 1
	swordStatsLabel.Font = Theme.Fonts.Body
	swordStatsLabel.TextSize = 12
	swordStatsLabel.TextColor3 = Theme.Colors.TextGold
	swordStatsLabel.TextXAlignment = Enum.TextXAlignment.Left
	swordStatsLabel.Text = "Base: -   •   Current Multiplier: 1.0x"
	swordStatsLabel.Parent = detailCard

	local swordEffectLabel = Instance.new("TextLabel")
	swordEffectLabel.Name = "SwordEffect"
	swordEffectLabel.Size = UDim2.new(1, -20, 0, 16)
	swordEffectLabel.Position = UDim2.new(0, 10, 0, 48)
	swordEffectLabel.BackgroundTransparency = 1
	swordEffectLabel.Font = Theme.Fonts.Body
	swordEffectLabel.TextSize = 11
	swordEffectLabel.TextColor3 = Theme.Colors.AuraEmerald
	swordEffectLabel.TextXAlignment = Enum.TextXAlignment.Left
	swordEffectLabel.Text = "Effect: None"
	swordEffectLabel.Parent = detailCard

	local replaceWarningLabel = Instance.new("TextLabel")
	replaceWarningLabel.Name = "ReplaceWarning"
	replaceWarningLabel.Size = UDim2.new(1, -20, 0, 16)
	replaceWarningLabel.Position = UDim2.new(0, 10, 0, 66)
	replaceWarningLabel.BackgroundTransparency = 1
	replaceWarningLabel.Font = Theme.Fonts.Body
	replaceWarningLabel.TextSize = 10
	replaceWarningLabel.TextColor3 = Theme.Colors.TextMuted
	replaceWarningLabel.TextXAlignment = Enum.TextXAlignment.Left
	replaceWarningLabel.Text = "⚠️ Rolling replaces the sword's existing enchant."
	replaceWarningLabel.Parent = detailCard

	-- Currency & Cost Card
	local costCard = Instance.new("Frame")
	costCard.Name = "CostCard"
	costCard.LayoutOrder = 2
	costCard.Size = UDim2.new(1, 0, 0, 32)
	costCard.BackgroundColor3 = Theme.Colors.BackgroundCard
	costCard.BackgroundTransparency = 0.3
	costCard.Parent = rightScroll

	local costCorner = Instance.new("UICorner")
	costCorner.CornerRadius = Theme.Corner.Small
	costCorner.Parent = costCard

	local tokenCostLabel = Instance.new("TextLabel")
	tokenCostLabel.Name = "CostLabel"
	tokenCostLabel.Size = UDim2.new(0.5, -10, 1, 0)
	tokenCostLabel.Position = UDim2.new(0, 10, 0, 0)
	tokenCostLabel.BackgroundTransparency = 1
	tokenCostLabel.Font = Theme.Fonts.Button
	tokenCostLabel.TextSize = 12
	tokenCostLabel.TextColor3 = Theme.Colors.AuraPurple
	tokenCostLabel.TextXAlignment = Enum.TextXAlignment.Left
	tokenCostLabel.Text = "Cost: 1 Token / Roll"
	tokenCostLabel.Parent = costCard

	local tokenBalanceLabel = Instance.new("TextLabel")
	tokenBalanceLabel.Name = "BalanceLabel"
	tokenBalanceLabel.Size = UDim2.new(0.5, -10, 1, 0)
	tokenBalanceLabel.Position = UDim2.new(1, -10, 0, 0)
	tokenBalanceLabel.AnchorPoint = Vector2.new(1, 0)
	tokenBalanceLabel.BackgroundTransparency = 1
	tokenBalanceLabel.Font = Theme.Fonts.Number
	tokenBalanceLabel.TextSize = 13
	tokenBalanceLabel.TextColor3 = Theme.Colors.AuraPurple
	tokenBalanceLabel.TextXAlignment = Enum.TextXAlignment.Right
	tokenBalanceLabel.Text = "🎟️ 0"
	tokenBalanceLabel.Parent = costCard

	-- Manual Roll Card
	local manualCard = Instance.new("Frame")
	manualCard.Name = "ManualCard"
	manualCard.LayoutOrder = 3
	manualCard.Size = UDim2.new(1, 0, 0, 84)
	manualCard.BackgroundColor3 = Theme.Colors.BackgroundCard
	manualCard.BackgroundTransparency = 0.2
	manualCard.Parent = rightScroll

	local manualCorner = Instance.new("UICorner")
	manualCorner.CornerRadius = Theme.Corner.Small
	manualCorner.Parent = manualCard

	local rollButton = Button.new({
		Name = "RollButton",
		Text = "ROLL ENCHANT (1 🎟️)",
		Size = UDim2.new(1, -20, 0, 36),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor = Theme.Colors.ButtonPrimary,
		BorderColor = Theme.Colors.AuraPurple,
		TextColor = Theme.Colors.TextPrimary,
		Parent = manualCard,
	})

	local rollResultLabel = Instance.new("TextLabel")
	rollResultLabel.Name = "RollResultLabel"
	rollResultLabel.Size = UDim2.new(1, -20, 0, 26)
	rollResultLabel.Position = UDim2.new(0.5, 0, 1, -8)
	rollResultLabel.AnchorPoint = Vector2.new(0.5, 1)
	rollResultLabel.BackgroundTransparency = 1
	rollResultLabel.Font = Theme.Fonts.Button
	rollResultLabel.TextSize = 12
	rollResultLabel.TextColor3 = Theme.Colors.TextSecondary
	rollResultLabel.Text = "Tap Roll to enchant this blade."
	rollResultLabel.Parent = manualCard

	-- Auto Enchant Card
	local autoCard = Instance.new("Frame")
	autoCard.Name = "AutoCard"
	autoCard.LayoutOrder = 4
	autoCard.Size = UDim2.new(1, 0, 0, 205)
	autoCard.BackgroundColor3 = Theme.Colors.BackgroundCard
	autoCard.BackgroundTransparency = 0.2
	autoCard.Parent = rightScroll

	local autoCorner = Instance.new("UICorner")
	autoCorner.CornerRadius = Theme.Corner.Small
	autoCorner.Parent = autoCard

	local autoTitle = Instance.new("TextLabel")
	autoTitle.Name = "AutoTitle"
	autoTitle.Size = UDim2.new(1, -20, 0, 20)
	autoTitle.Position = UDim2.new(0, 10, 0, 6)
	autoTitle.BackgroundTransparency = 1
	autoTitle.Font = Theme.Fonts.Button
	autoTitle.TextSize = 11
	autoTitle.TextColor3 = Theme.Colors.AuraEmerald
	autoTitle.TextXAlignment = Enum.TextXAlignment.Left
	autoTitle.Text = "AUTO ENCHANT ROLL (FREE)"
	autoTitle.Parent = autoCard

	-- Target Enchant selector horizontal container
	local targetContainer = Instance.new("ScrollingFrame")
	targetContainer.Name = "TargetContainer"
	targetContainer.Size = UDim2.new(1, -20, 0, 30)
	targetContainer.Position = UDim2.new(0, 10, 0, 28)
	targetContainer.BackgroundTransparency = 1
	targetContainer.BorderSizePixel = 0
	targetContainer.ScrollBarThickness = 2
	targetContainer.ScrollBarImageColor3 = Theme.Colors.BorderGlow
	targetContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
	targetContainer.AutomaticCanvasSize = Enum.AutomaticSize.X
	targetContainer.Parent = autoCard

	local targetLayout = Instance.new("UIListLayout")
	targetLayout.FillDirection = Enum.FillDirection.Horizontal
	targetLayout.Padding = UDim.new(0, 4)
	targetLayout.Parent = targetContainer

	local targetButtons: { [string]: TextButton } = {}

	-- Expected Tokens label
	local expectedTokensLabel = Instance.new("TextLabel")
	expectedTokensLabel.Name = "ExpectedTokensLabel"
	expectedTokensLabel.Size = UDim2.new(1, -20, 0, 16)
	expectedTokensLabel.Position = UDim2.new(0, 10, 0, 62)
	expectedTokensLabel.BackgroundTransparency = 1
	expectedTokensLabel.Font = Theme.Fonts.Body
	expectedTokensLabel.TextSize = 11
	expectedTokensLabel.TextColor3 = Theme.Colors.TextSecondary
	expectedTokensLabel.TextXAlignment = Enum.TextXAlignment.Left
	expectedTokensLabel.Text = "Expected: ~10 Tokens"
	expectedTokensLabel.Parent = autoCard

	-- Max Tokens Limit input
	local maxTokensRow = Instance.new("Frame")
	maxTokensRow.Name = "MaxTokensRow"
	maxTokensRow.Size = UDim2.new(1, -20, 0, 28)
	maxTokensRow.Position = UDim2.new(0, 10, 0, 82)
	maxTokensRow.BackgroundTransparency = 1
	maxTokensRow.Parent = autoCard

	local maxTokensLabel = Instance.new("TextLabel")
	maxTokensLabel.Name = "MaxTokensLabel"
	maxTokensLabel.Size = UDim2.new(0.55, 0, 1, 0)
	maxTokensLabel.Position = UDim2.new(0, 0, 0, 0)
	maxTokensLabel.BackgroundTransparency = 1
	maxTokensLabel.Font = Theme.Fonts.Body
	maxTokensLabel.TextSize = 12
	maxTokensLabel.TextColor3 = Theme.Colors.TextPrimary
	maxTokensLabel.TextXAlignment = Enum.TextXAlignment.Left
	maxTokensLabel.Text = "Max Tokens (optional):"
	maxTokensLabel.Parent = maxTokensRow

	local maxTokensBox = Instance.new("TextBox")
	maxTokensBox.Name = "MaxTokensBox"
	maxTokensBox.Size = UDim2.new(0.42, 0, 1, 0)
	maxTokensBox.Position = UDim2.new(1, 0, 0, 0)
	maxTokensBox.AnchorPoint = Vector2.new(1, 0)
	maxTokensBox.BackgroundColor3 = Theme.Colors.PanelBackground
	maxTokensBox.PlaceholderText = "Unlimited"
	maxTokensBox.PlaceholderColor3 = Theme.Colors.TextMuted
	maxTokensBox.TextColor3 = Theme.Colors.TextGold
	maxTokensBox.Font = Theme.Fonts.Button
	maxTokensBox.TextSize = 12
	maxTokensBox.ClearTextOnFocus = false
	maxTokensBox.Parent = maxTokensRow

	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = Theme.Corner.Small
	boxCorner.Parent = maxTokensBox

	local boxStroke = Instance.new("UIStroke")
	boxStroke.Color = Theme.Colors.Border
	boxStroke.Thickness = 1
	boxStroke.Parent = maxTokensBox

	-- Auto Action Controls
	local startAutoBtn = Button.new({
		Name = "StartAutoBtn",
		Text = "START AUTO ENCHANT",
		Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.new(0.5, 0, 0, 116),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor = Theme.Colors.ButtonPrimary,
		BorderColor = Theme.Colors.AuraEmerald,
		TextColor = Theme.Colors.AuraEmerald,
		Parent = autoCard,
	})

	local stopAutoBtn = Button.new({
		Name = "StopAutoBtn",
		Text = "STOP AUTO ENCHANT",
		Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.new(0.5, 0, 0, 116),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor = Theme.Colors.ButtonPrimary,
		BorderColor = Theme.Colors.ButtonClose,
		TextColor = Theme.Colors.ButtonClose,
		Parent = autoCard,
	})
	stopAutoBtn.Instance.Visible = false

	-- Auto status text
	local autoStatusLabel = Instance.new("TextLabel")
	autoStatusLabel.Name = "AutoStatus"
	autoStatusLabel.Size = UDim2.new(1, -20, 0, 44)
	autoStatusLabel.Position = UDim2.new(0.5, 0, 1, -6)
	autoStatusLabel.AnchorPoint = Vector2.new(0.5, 1)
	autoStatusLabel.BackgroundTransparency = 1
	autoStatusLabel.Font = Theme.Fonts.Body
	autoStatusLabel.TextSize = 11
	autoStatusLabel.TextColor3 = Theme.Colors.TextSecondary
	autoStatusLabel.TextWrapped = true
	autoStatusLabel.Text = "Select a target enchant and tap Start Auto."
	autoStatusLabel.Parent = autoCard

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

	local forwardUpdateSwordView: (() -> ())? = nil

	local function updateTargetSelectorUI()
		for eName, btn in pairs(targetButtons) do
			local isSelected = (eName == selectedTargetEnchant)
			local stroke = btn:FindFirstChild("Stroke") :: UIStroke?
			if stroke then
				stroke.Color = if isSelected then Theme.Colors.AuraGold else Theme.Colors.BorderSubtle
				stroke.Thickness = if isSelected then 2 else 1
			end
			btn.BackgroundColor3 = if isSelected then Theme.Colors.BackgroundHover else Theme.Colors.PanelBackground
		end

		local expected = Enchants.GetExpectedTokens(selectedTargetEnchant)
		expectedTokensLabel.Text = ("Expected Tokens for %s+: ~%s Tokens"):format(
			selectedTargetEnchant,
			NumberFormat.format(math.floor(expected + 0.5))
		)
	end

	-- Build target selector buttons
	for _, def in ipairs(Enchants.GetAll()) do
		local tBtn = Instance.new("TextButton")
		tBtn.Name = "Target_" .. def.name
		tBtn.Size = UDim2.new(0, 0, 1, 0)
		tBtn.AutomaticSize = Enum.AutomaticSize.X
		tBtn.BackgroundColor3 = Theme.Colors.PanelBackground
		tBtn.AutoButtonColor = false
		tBtn.Font = Theme.Fonts.Button
		tBtn.TextSize = 11
		tBtn.TextColor3 = Theme.Colors.TextPrimary
		tBtn.Text = " " .. def.name .. " "
		tBtn.Parent = targetContainer

		local tCorner = Instance.new("UICorner")
		tCorner.CornerRadius = Theme.Corner.Small
		tCorner.Parent = tBtn

		local tStroke = Instance.new("UIStroke")
		tStroke.Name = "Stroke"
		tStroke.Color = Theme.Colors.BorderSubtle
		tStroke.Thickness = 1
		tStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		tStroke.Parent = tBtn

		local tPadding = Instance.new("UIPadding")
		tPadding.PaddingLeft = UDim.new(0, 4)
		tPadding.PaddingRight = UDim.new(0, 4)
		tPadding.Parent = tBtn

		tBtn.Activated:Connect(function()
			if isAutoRunning then
				return
			end
			selectedTargetEnchant = def.name
			updateTargetSelectorUI()
			if forwardUpdateSwordView then
				forwardUpdateSwordView()
			end
		end)

		targetButtons[def.name] = tBtn
	end
	updateTargetSelectorUI()

	local function updateActiveSwordView()
		forwardUpdateSwordView = updateActiveSwordView
		local entry = getSelectedEntry()
		if not entry then
			swordNameLabel.Text = "No Sword Selected"
			swordStatsLabel.Text = "Base: -   •   Current Multiplier: 1.0x"
			swordEffectLabel.Text = "Effect: None"
			EnchantBadge.Update(currentEnchantBadge, nil)
			rollButton:SetEnabled(false)
			startAutoBtn:SetEnabled(false)
			return
		end

		local def = swordDefMap[entry.id]
		local eName = entry.enchant or ""
		local eDef = Enchants.GetEnchantDef(eName)
		local mult = Enchants.GetMultiplier(eName)

		swordNameLabel.Text = def and def.name or "Sword"
		swordStatsLabel.Text = ("Base: %s   •   Multiplier: %.1fx"):format(
			def and NumberFormat.format(def.baseDamage) or "1",
			mult
		)
		swordEffectLabel.Text = ("Effect: %s"):format(eDef and eDef.effectText or "None")
		EnchantBadge.Update(currentEnchantBadge, eName)

		local canRoll = (currentTokens >= 1 and not isAutoRunning)
		rollButton:SetEnabled(canRoll)

		local currentRank = Enchants.GetRank(eName)
		local targetRank = Enchants.GetRank(selectedTargetEnchant)
		local canStartAuto = (canRoll and currentRank < targetRank and not isAutoRunning)
		startAutoBtn:SetEnabled(canStartAuto)
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
			empty.Text = "No swords found."
			empty.Parent = listScroll
			return
		end

		for _, entry in ipairs(currentSwords) do
			local def = swordDefMap[entry.id]
			local isSelected = (entry.uid == selectedUid)

			local itemCard = Instance.new("TextButton")
			itemCard.Name = "Item_" .. entry.uid
			itemCard.Size = UDim2.new(1, 0, 0, 42)
			itemCard.BackgroundColor3 = if isSelected then Theme.Colors.BackgroundHover else Theme.Colors.PanelBackground
			itemCard.AutoButtonColor = false
			itemCard.Text = ""
			itemCard.Parent = listScroll

			local corner = Instance.new("UICorner")
			corner.CornerRadius = Theme.Corner.Small
			corner.Parent = itemCard

			local stroke = Instance.new("UIStroke")
			stroke.Color = if isSelected then Theme.Colors.AuraGold else Theme.Colors.BorderSubtle
			stroke.Thickness = if isSelected then 2 else 1
			stroke.Parent = itemCard

			local name = Instance.new("TextLabel")
			name.Name = "Name"
			name.Size = UDim2.new(1, -70, 0, 20)
			name.Position = UDim2.new(0, 8, 0, 4)
			name.BackgroundTransparency = 1
			name.Font = Theme.Fonts.Button
			name.TextSize = 12
			name.TextColor3 = (Swords.RarityColors and def and Swords.RarityColors[def.rarity]) or Theme.Colors.TextPrimary
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Text = def and def.name or "Sword"
			name.Parent = itemCard

			local status = Instance.new("TextLabel")
			status.Name = "Status"
			status.Size = UDim2.new(1, -70, 0, 14)
			status.Position = UDim2.new(0, 8, 0, 22)
			status.BackgroundTransparency = 1
			status.Font = Theme.Fonts.Body
			status.TextSize = 10
			status.TextColor3 = Theme.Colors.TextMuted
			status.TextXAlignment = Enum.TextXAlignment.Left

			if entry.uid == currentEquippedUid then
				status.Text = "EQUIPPED"
				status.TextColor3 = Theme.Colors.AuraEmerald
			elseif currentPlacedMap[entry.uid] then
				status.Text = "PLACED"
				status.TextColor3 = Theme.Colors.AuraCyan
			else
				status.Text = "STORED"
			end
			status.Parent = itemCard

			EnchantBadge.new({
				Enchant = entry.enchant,
				Size = UDim2.new(0, 56, 0, 18),
				Position = UDim2.new(1, -6, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				Parent = itemCard,
			})

			itemCard.Activated:Connect(function()
				if isAutoRunning then
					return
				end
				selectedUid = entry.uid
				rebuildSwordList()
				updateActiveSwordView()
			end)
		end
	end

	local function executeManualRoll()
		if not selectedUid then
			return
		end
		rollResultLabel.Text = "Enchanting..."
		rollResultLabel.TextColor3 = Theme.Colors.TextSecondary
		if onRollCallback then
			onRollCallback(selectedUid)
		end
	end

	-- Connect Roll button with high-enchant check
	rollButton.Instance.Activated:Connect(function()
		if isAutoRunning then
			return
		end
		local entry = getSelectedEntry()
		if not entry then
			return
		end

		if Enchants.IsHighEnchant(entry.enchant) then
			confirmMsg.Text = ("This sword has rare enchant '%s' (%.1fx)! Rerolling will permanently overwrite it."):format(
				entry.enchant or "",
				Enchants.GetMultiplier(entry.enchant)
			)
			pendingRollAction = executeManualRoll
			confirmModal.Visible = true
		else
			executeManualRoll()
		end
	end)

	local function executeStartAuto()
		if not selectedUid then
			return
		end
		local maxTokens = tonumber(maxTokensBox.Text)
		if onStartAutoCallback then
			onStartAutoCallback(selectedUid, selectedTargetEnchant, maxTokens)
		end
	end

	startAutoBtn.Instance.Activated:Connect(function()
		if isAutoRunning then
			return
		end
		local entry = getSelectedEntry()
		if not entry then
			return
		end

		if Enchants.IsHighEnchant(entry.enchant) then
			confirmMsg.Text = ("This sword has rare enchant '%s' (%.1fx)! Starting auto enchant roll will overwrite it."):format(
				entry.enchant or "",
				Enchants.GetMultiplier(entry.enchant)
			)
			pendingRollAction = executeStartAuto
			confirmModal.Visible = true
		else
			executeStartAuto()
		end
	end)

	stopAutoBtn.Instance.Activated:Connect(function()
		if onStopAutoCallback then
			onStopAutoCallback()
		end
	end)

	local self: EnchanterUIInstance = {
		Open = function(_, ownedSwords, equippedUid, placedUids, tokenBalance)
			currentSwords = ownedSwords
			currentEquippedUid = equippedUid
			currentPlacedMap = placedUids
			currentTokens = tokenBalance

			tokenBalanceLabel.Text = "🎟️ " .. NumberFormat.format(tokenBalance)

			-- Default selection: equipped sword or first owned sword
			if not selectedUid or not getSelectedEntry() then
				if equippedUid ~= "" then
					selectedUid = equippedUid
				elseif #ownedSwords > 0 then
					selectedUid = ownedSwords[1].uid
				end
			end

			rebuildSwordList()
			updateActiveSwordView()
			popup:Open()
		end,

		Close = function(_)
			if isAutoRunning and onStopAutoCallback then
				onStopAutoCallback()
			end
			popup:Close()
		end,

		UpdateTokens = function(_, tokens)
			currentTokens = tokens
			tokenBalanceLabel.Text = "🎟️ " .. NumberFormat.format(tokens)
			updateActiveSwordView()
		end,

		UpdateSwords = function(_, ownedSwords, equippedUid, placedUids)
			currentSwords = ownedSwords
			currentEquippedUid = equippedUid
			currentPlacedMap = placedUids
			rebuildSwordList()
			updateActiveSwordView()
		end,

		ShowRollResult = function(_, oldEnchant, newEnchant)
			local newDef = Enchants.GetEnchantDef(newEnchant)
			local mult = newDef and newDef.multiplier or 1.0
			rollResultLabel.Text = ("Rolled: %s (%.1fx)!"):format(newEnchant, mult)
			rollResultLabel.TextColor3 = Theme.Colors.AuraPurple

			local tween = TweenService:Create(rollResultLabel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				TextTransparency = 0,
			})
			tween:Play()
			updateActiveSwordView()
		end,

		UpdateAutoProgress = function(_, rollsDone, tokensSpent, lastEnchant, isRunning, stopReason)
			isAutoRunning = isRunning

			startAutoBtn.Instance.Visible = not isRunning
			stopAutoBtn.Instance.Visible = isRunning
			rollButton:SetEnabled(not isRunning and currentTokens >= 1)
			maxTokensBox.TextEditable = not isRunning

			if isRunning then
				autoStatusLabel.Text = ("Rolling... Rolls: %d | Tokens Spent: %d | Current: %s"):format(
					rollsDone,
					tokensSpent,
					if lastEnchant ~= "" then lastEnchant else "None"
				)
				autoStatusLabel.TextColor3 = Theme.Colors.AuraCyan
			else
				local reasonText = stopReason or "Stopped"
				autoStatusLabel.Text = ("Auto Concluded: %s (Rolls: %d, Tokens: %d)"):format(
					reasonText,
					rollsDone,
					tokensSpent
				)
				autoStatusLabel.TextColor3 = if reasonText:find("Target") then Theme.Colors.AuraEmerald else Theme.Colors.TextSecondary
			end

			updateActiveSwordView()
			rebuildSwordList()
		end,

		SetOnRoll = function(_, callback)
			onRollCallback = callback
		end,

		SetOnStartAuto = function(_, callback)
			onStartAutoCallback = callback
		end,

		SetOnStopAuto = function(_, callback)
			onStopAutoCallback = callback
		end,

		SetOnClose = function(_, callback)
			onCloseCallback = callback
		end,

		Destroy = function(_)
			popup:Destroy()
			screenGui:Destroy()
		end,
	}

	return self
end

return EnchanterUI
