--!strict
-- AppraiserUI: Mobile-first modal for blade grading and auto grade roll.
-- Pick a sword from inventory (including equipped and placed swords),
-- view current grade and multiplier, roll grade for 1 Gem with confirmation for S+,
-- and set a target grade for automated rolling with live progress.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Config = ReplicatedStorage:WaitForChild("Config")
local Swords = require(Config:WaitForChild("Swords"))
local Grades = require(Config:WaitForChild("Grades"))

local Components = Shared:WaitForChild("UI"):WaitForChild("Components")
local Popup = require(Components:WaitForChild("Popup"))
local Button = require(Components:WaitForChild("Button"))
local GradeBadge = require(Components:WaitForChild("GradeBadge"))

export type OwnedSwordEntry = {
	uid: string,
	id: string,
	grade: string?,
	locked: boolean?,
	[string]: any,
}

export type AppraiserUIInstance = {
	Open: (
		self: AppraiserUIInstance,
		ownedSwords: { OwnedSwordEntry },
		equippedUid: string,
		placedUids: { [string]: boolean },
		gemBalance: number
	) -> (),
	Close: (self: AppraiserUIInstance) -> (),
	UpdateGems: (self: AppraiserUIInstance, gems: number) -> (),
	UpdateSwords: (
		self: AppraiserUIInstance,
		ownedSwords: { OwnedSwordEntry },
		equippedUid: string,
		placedUids: { [string]: boolean }
	) -> (),
	ShowRollResult: (self: AppraiserUIInstance, oldGrade: string, newGrade: string) -> (),
	UpdateAutoProgress: (
		self: AppraiserUIInstance,
		rollsDone: number,
		gemsSpent: number,
		lastGrade: string,
		isRunning: boolean,
		stopReason: string?
	) -> (),
	SetOnRoll: (self: AppraiserUIInstance, callback: (uid: string) -> ()) -> (),
	SetOnStartAuto: (self: AppraiserUIInstance, callback: (uid: string, targetGrade: string, maxGems: number?) -> ()) -> (),
	SetOnStopAuto: (self: AppraiserUIInstance, callback: () -> ()) -> (),
	SetOnClose: (self: AppraiserUIInstance, callback: () -> ()) -> (),
	Destroy: (self: AppraiserUIInstance) -> (),
}

local AppraiserUI = {}

local swordDefMap: { [string]: Swords.SwordDef } = {}
for _, def in Swords do
	swordDefMap[def.id] = def
end

function AppraiserUI.new(parentGui: Instance): AppraiserUIInstance
	local screenGui: ScreenGui
	if parentGui:IsA("ScreenGui") then
		screenGui = parentGui
	else
		local sg = Instance.new("ScreenGui")
		sg.Name = "AuraBladeAppraiserGui"
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
	local currentGems = 0
	local selectedUid: string? = nil
	local selectedTargetGrade = "S"
	local isAutoRunning = false

	-- Callbacks
	local onRollCallback: ((string) -> ())? = nil
	local onStartAutoCallback: ((string, string) -> ())? = nil
	local onStopAutoCallback: (() -> ())? = nil
	local onCloseCallback: (() -> ())? = nil

	-- Main popup
	local popup = Popup.new({
		Title = "Master Appraiser",
		WidthScale = 0.94,
		MaxWidth = 620,
		HeightScale = 0.86,
		MaxHeight = 520,
		Parent = screenGui,
		OnClose = function()
			if onCloseCallback then
				onCloseCallback()
			end
		end,
	})

	local root = popup.Content

	-- Confirmation Modal overlay (for high-grade replacement)
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
	confirmCard.Size = UDim2.new(0.85, 0, 0, 180)
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
	confirmTitle.Text = "⚠️ High Grade Warning"
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
	confirmMsg.Text = "This sword currently has a high Grade! Rolling will permanently replace it. Are you sure?"
	confirmMsg.ZIndex = 32
	confirmMsg.Parent = confirmCard

	local confirmYesBtn = Button.new({
		Name = "ConfirmYes",
		Text = "YES, REPLACE",
		Size = UDim2.new(0.44, 0, 0, 34),
		Position = UDim2.new(0.04, 0, 1, -12),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor = Theme.Colors.ButtonClose,
		BorderColor = Theme.Colors.AuraCrimson,
		TextColor = Theme.Colors.TextPrimary,
		Parent = confirmCard,
	})
	local confirmNoBtn = Button.new({
		Name = "ConfirmNo",
		Text = "CANCEL",
		Size = UDim2.new(0.44, 0, 0, 34),
		Position = UDim2.new(0.96, 0, 1, -12),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.Border,
		TextColor = Theme.Colors.TextSecondary,
		Parent = confirmCard,
	})

	-- Split Body: Left List (40%), Right Operations (60%)
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 1, 0)
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

	-- Right: Active Appraising Panel
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
	rightLayout.FillDirection = Enum.FillDirection.Vertical
	rightLayout.Padding = UDim.new(0, 10)
	rightLayout.Parent = rightScroll

	-- Sword Detail Header Card
	local detailCard = Instance.new("Frame")
	detailCard.Name = "DetailCard"
	detailCard.Size = UDim2.new(1, 0, 0, 74)
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
	swordNameLabel.Size = UDim2.new(1, -50, 0, 24)
	swordNameLabel.Position = UDim2.new(0, 10, 0, 6)
	swordNameLabel.BackgroundTransparency = 1
	swordNameLabel.Font = Theme.Fonts.Title
	swordNameLabel.TextSize = 15
	swordNameLabel.TextColor3 = Theme.Colors.AuraCyan
	swordNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	swordNameLabel.Text = "No Sword Selected"
	swordNameLabel.Parent = detailCard

	local currentGradeBadge = GradeBadge.new({
		Grade = nil,
		Size = UDim2.new(0, 32, 0, 22),
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

	local replaceWarningLabel = Instance.new("TextLabel")
	replaceWarningLabel.Name = "ReplaceWarning"
	replaceWarningLabel.Size = UDim2.new(1, -20, 0, 16)
	replaceWarningLabel.Position = UDim2.new(0, 10, 0, 50)
	replaceWarningLabel.BackgroundTransparency = 1
	replaceWarningLabel.Font = Theme.Fonts.Body
	replaceWarningLabel.TextSize = 11
	replaceWarningLabel.TextColor3 = Theme.Colors.TextMuted
	replaceWarningLabel.TextXAlignment = Enum.TextXAlignment.Left
	replaceWarningLabel.Text = "⚠️ Rolling replaces the sword's existing grade."
	replaceWarningLabel.Parent = detailCard

	-- Currency & Cost Card
	local costCard = Instance.new("Frame")
	costCard.Name = "CostCard"
	costCard.Size = UDim2.new(1, 0, 0, 32)
	costCard.BackgroundColor3 = Theme.Colors.BackgroundCard
	costCard.BackgroundTransparency = 0.3
	costCard.Parent = rightScroll

	local costCorner = Instance.new("UICorner")
	costCorner.CornerRadius = Theme.Corner.Small
	costCorner.Parent = costCard

	local gemCostLabel = Instance.new("TextLabel")
	gemCostLabel.Name = "CostLabel"
	gemCostLabel.Size = UDim2.new(0.5, -10, 1, 0)
	gemCostLabel.Position = UDim2.new(0, 10, 0, 0)
	gemCostLabel.BackgroundTransparency = 1
	gemCostLabel.Font = Theme.Fonts.Button
	gemCostLabel.TextSize = 12
	gemCostLabel.TextColor3 = Theme.Colors.AuraPurple
	gemCostLabel.TextXAlignment = Enum.TextXAlignment.Left
	gemCostLabel.Text = "Cost: 1 Gem / Roll"
	gemCostLabel.Parent = costCard

	local gemBalanceLabel = Instance.new("TextLabel")
	gemBalanceLabel.Name = "BalanceLabel"
	gemBalanceLabel.Size = UDim2.new(0.5, -10, 1, 0)
	gemBalanceLabel.Position = UDim2.new(1, -10, 0, 0)
	gemBalanceLabel.AnchorPoint = Vector2.new(1, 0)
	gemBalanceLabel.BackgroundTransparency = 1
	gemBalanceLabel.Font = Theme.Fonts.Number
	gemBalanceLabel.TextSize = 13
	gemBalanceLabel.TextColor3 = Theme.Colors.AuraCyan
	gemBalanceLabel.TextXAlignment = Enum.TextXAlignment.Right
	gemBalanceLabel.Text = "💎 0"
	gemBalanceLabel.Parent = costCard

	-- Manual Roll Card
	local manualCard = Instance.new("Frame")
	manualCard.Name = "ManualCard"
	manualCard.Size = UDim2.new(1, 0, 0, 84)
	manualCard.BackgroundColor3 = Theme.Colors.BackgroundCard
	manualCard.BackgroundTransparency = 0.2
	manualCard.Parent = rightScroll

	local manualCorner = Instance.new("UICorner")
	manualCorner.CornerRadius = Theme.Corner.Small
	manualCorner.Parent = manualCard

	local rollButton = Button.new({
		Name = "RollButton",
		Text = "ROLL GRADE (1 💎)",
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
	rollResultLabel.Text = "Tap Roll to appraise this blade."
	rollResultLabel.Parent = manualCard

	-- Auto Grade Card
	local autoCard = Instance.new("Frame")
	autoCard.Name = "AutoCard"
	autoCard.Size = UDim2.new(1, 0, 0, 195)
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
	autoTitle.Text = "AUTO GRADE ROLL (FREE)"
	autoTitle.Parent = autoCard

	-- Target Grade selector horizontal container
	local targetContainer = Instance.new("Frame")
	targetContainer.Name = "TargetContainer"
	targetContainer.Size = UDim2.new(1, -20, 0, 28)
	targetContainer.Position = UDim2.new(0, 10, 0, 28)
	targetContainer.BackgroundTransparency = 1
	targetContainer.Parent = autoCard

	local targetLayout = Instance.new("UIListLayout")
	targetLayout.FillDirection = Enum.FillDirection.Horizontal
	targetLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	targetLayout.Padding = UDim.new(0, 4)
	targetLayout.Parent = targetContainer

	local forwardUpdateDetail: () -> ()

	local targetButtons: { [string]: TextButton } = {}
	for _, def in ipairs(Grades.GetAll()) do
		local btn = Instance.new("TextButton")
		btn.Name = "Target_" .. def.name
		btn.Size = UDim2.new(0, 28, 1, 0)
		btn.BackgroundColor3 = Theme.Colors.ButtonSecondary
		btn.BackgroundTransparency = 0.2
		btn.Font = Theme.Fonts.Button
		btn.TextSize = 10
		btn.Text = def.name
		btn.TextColor3 = Theme.Colors.TextSecondary
		btn.AutoButtonColor = false
		btn.Parent = targetContainer

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = Theme.Corner.Small
		btnCorner.Parent = btn

		local btnStroke = Instance.new("UIStroke")
		btnStroke.Name = "BtnStroke"
		btnStroke.Color = Theme.Colors.BorderSubtle
		btnStroke.Thickness = 1
		btnStroke.Parent = btn

		targetButtons[def.name] = btn

		btn.Activated:Connect(function()
			if isAutoRunning then
				return
			end
			selectedTargetGrade = def.name
			for gName, b in targetButtons do
				local s = b:FindFirstChild("BtnStroke") :: UIStroke?
				if gName == selectedTargetGrade then
					b.TextColor3 = Theme.Colors.AuraGold
					if s then
						s.Color = Theme.Colors.AuraGold
						s.Thickness = 2
					end
				else
					b.TextColor3 = Theme.Colors.TextSecondary
					if s then
						s.Color = Theme.Colors.BorderSubtle
						s.Thickness = 1
					end
				end
			end
			if forwardUpdateDetail then
				forwardUpdateDetail()
			end
		end)
	end

	-- Expected Gems label
	local expectedGemsLabel = Instance.new("TextLabel")
	expectedGemsLabel.Name = "ExpectedGemsLabel"
	expectedGemsLabel.Size = UDim2.new(1, -20, 0, 18)
	expectedGemsLabel.Position = UDim2.new(0, 10, 0, 60)
	expectedGemsLabel.BackgroundTransparency = 1
	expectedGemsLabel.Font = Theme.Fonts.Body
	expectedGemsLabel.TextSize = 11
	expectedGemsLabel.TextColor3 = Theme.Colors.TextGold
	expectedGemsLabel.TextXAlignment = Enum.TextXAlignment.Left
	expectedGemsLabel.Text = "Target: S or better (Expected: ~10 Gems)"
	expectedGemsLabel.Parent = autoCard

	-- Max Gems spend limit row
	local maxGemsRow = Instance.new("Frame")
	maxGemsRow.Name = "MaxGemsRow"
	maxGemsRow.Size = UDim2.new(1, -20, 0, 24)
	maxGemsRow.Position = UDim2.new(0, 10, 0, 80)
	maxGemsRow.BackgroundTransparency = 1
	maxGemsRow.Parent = autoCard

	local maxGemsTitle = Instance.new("TextLabel")
	maxGemsTitle.Name = "MaxGemsTitle"
	maxGemsTitle.Size = UDim2.new(0, 115, 1, 0)
	maxGemsTitle.Position = UDim2.new(0, 0, 0, 0)
	maxGemsTitle.BackgroundTransparency = 1
	maxGemsTitle.Font = Theme.Fonts.Button
	maxGemsTitle.TextSize = 11
	maxGemsTitle.TextColor3 = Theme.Colors.TextSecondary
	maxGemsTitle.TextXAlignment = Enum.TextXAlignment.Left
	maxGemsTitle.Text = "Max Gems to spend:"
	maxGemsTitle.Parent = maxGemsRow

	local maxGemsBox = Instance.new("TextBox")
	maxGemsBox.Name = "MaxGemsInput"
	maxGemsBox.Size = UDim2.new(0, 90, 1, 0)
	maxGemsBox.Position = UDim2.new(0, 120, 0, 0)
	maxGemsBox.BackgroundColor3 = Theme.Colors.ButtonSecondary
	maxGemsBox.BackgroundTransparency = 0.2
	maxGemsBox.Font = Theme.Fonts.Number
	maxGemsBox.TextSize = 12
	maxGemsBox.TextColor3 = Theme.Colors.AuraCyan
	maxGemsBox.PlaceholderText = "All Gems"
	maxGemsBox.PlaceholderColor3 = Theme.Colors.TextMuted
	maxGemsBox.Text = ""
	maxGemsBox.ClearTextOnFocus = false
	maxGemsBox.Parent = maxGemsRow

	local maxGemsCorner = Instance.new("UICorner")
	maxGemsCorner.CornerRadius = Theme.Corner.Small
	maxGemsCorner.Parent = maxGemsBox

	local maxGemsStroke = Instance.new("UIStroke")
	maxGemsStroke.Color = Theme.Colors.BorderSubtle
	maxGemsStroke.Thickness = 1
	maxGemsStroke.Parent = maxGemsBox

	-- Auto Action buttons (Start / Stop)
	local autoBtnContainer = Instance.new("Frame")
	autoBtnContainer.Name = "AutoBtnContainer"
	autoBtnContainer.Size = UDim2.new(1, -20, 0, 36)
	autoBtnContainer.Position = UDim2.new(0, 10, 0, 110)
	autoBtnContainer.BackgroundTransparency = 1
	autoBtnContainer.Parent = autoCard

	local startAutoBtn = Button.new({
		Name = "StartAutoButton",
		Text = "START AUTO",
		Size = UDim2.new(0.60, -4, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor = Theme.Colors.ButtonPrimary,
		BorderColor = Theme.Colors.AuraEmerald,
		TextColor = Theme.Colors.AuraEmerald,
		Parent = autoBtnContainer,
	})

	local stopAutoBtn = Button.new({
		Name = "StopAutoButton",
		Text = "STOP",
		Size = UDim2.new(0.40, -4, 1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.BorderSubtle,
		TextColor = Theme.Colors.TextMuted,
		Parent = autoBtnContainer,
	})
	stopAutoBtn:SetEnabled(false)

	-- Live progress summary label
	local autoProgressLabel = Instance.new("TextLabel")
	autoProgressLabel.Name = "AutoProgressLabel"
	autoProgressLabel.Size = UDim2.new(1, -20, 0, 36)
	autoProgressLabel.Position = UDim2.new(0, 10, 0, 152)
	autoProgressLabel.BackgroundTransparency = 1
	autoProgressLabel.Font = Theme.Fonts.Body
	autoProgressLabel.TextSize = 11
	autoProgressLabel.TextColor3 = Theme.Colors.TextSecondary
	autoProgressLabel.TextWrapped = true
	autoProgressLabel.Text = "Auto rolls until target grade or better is reached."
	autoProgressLabel.Parent = autoCard

	-- Forward declarations
	local rebuildList: () -> ()
	local updateDetailPanel: () -> ()

	updateDetailPanel = function()
		gemBalanceLabel.Text = "💎 " .. NumberFormat.format(currentGems)

		local expGems = math.ceil(Grades.GetExpectedGems(selectedTargetGrade))
		expectedGemsLabel.Text = ("Target: %s or better (Expected: ~%s Gems)"):format(
			selectedTargetGrade,
			NumberFormat.format(expGems)
		)

		local selectedEntry: OwnedSwordEntry? = nil
		if selectedUid then
			for _, entry in currentSwords do
				if entry.uid == selectedUid then
					selectedEntry = entry
					break
				end
			end
		end

		if not selectedEntry then
			swordNameLabel.Text = "Select a Sword from the list"
			swordNameLabel.TextColor3 = Theme.Colors.TextMuted
			swordStatsLabel.Text = "Tap a sword on the left to begin appraising."
			GradeBadge.Update(currentGradeBadge, nil)
			rollButton:SetEnabled(false)
			startAutoBtn:SetEnabled(false)
			return
		end

		local swordDef = swordDefMap[selectedEntry.id]
		local rarityName = swordDef and swordDef.rarity or "Common"
		local rarityColor = (Swords.RarityColors and Swords.RarityColors[rarityName]) or Theme.Colors.AuraCyan
		swordNameLabel.Text = swordDef and swordDef.name or "Sword"
		swordNameLabel.TextColor3 = rarityColor

		local grade = selectedEntry.grade or ""
		GradeBadge.Update(currentGradeBadge, grade)

		local mult = Grades.GetMultiplier(grade)
		local baseDmg = swordDef and swordDef.baseDamage or 1
		local effectiveDmg = math.floor((baseDmg * mult) + 0.5)

		swordStatsLabel.Text = ("Damage: %s Gold/Tap (%s x%.2f)"):format(
			NumberFormat.format(effectiveDmg),
			if grade ~= "" then grade else "Ungraded",
			mult
		)

		local canAfford = currentGems >= 1
		local currentRank = Grades.GetRank(grade)
		local targetRank = Grades.GetRank(selectedTargetGrade)

		rollButton:SetEnabled(canAfford and not isAutoRunning)
		startAutoBtn:SetEnabled(canAfford and not isAutoRunning and currentRank < targetRank)
	end
	forwardUpdateDetail = updateDetailPanel

	rebuildList = function()
		for _, child in listScroll:GetChildren() do
			if child:IsA("Frame") or child:IsA("TextButton") then
				child:Destroy()
			end
		end

		for idx, entry in ipairs(currentSwords) do
			local swordDef = swordDefMap[entry.id]
			local isSelected = (entry.uid == selectedUid)
			local isEquipped = (entry.uid == currentEquippedUid)
			local isPlaced = (currentPlacedMap[entry.uid] == true)
			local rarityColor = (swordDef and Swords.RarityColors and Swords.RarityColors[swordDef.rarity])
				or Theme.Colors.AuraCyan

			local card = Instance.new("Frame")
			card.Name = "SwordCard_" .. entry.uid
			card.Size = UDim2.new(1, 0, 0, 48)
			card.BackgroundColor3 = if isSelected then Theme.Colors.BackgroundHover else Theme.Colors.ButtonSecondary
			card.BackgroundTransparency = 0.2
			card.LayoutOrder = idx
			card.Parent = listScroll

			local corner = Instance.new("UICorner")
			corner.CornerRadius = Theme.Corner.Small
			corner.Parent = card

			local stroke = Instance.new("UIStroke")
			stroke.Name = "CardStroke"
			stroke.Color = if isSelected then Theme.Colors.AuraGold else Theme.Colors.BorderSubtle
			stroke.Thickness = if isSelected then 2 else 1
			stroke.Parent = card

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "NameLabel"
			nameLabel.Size = UDim2.new(1, -70, 0, 20)
			nameLabel.Position = UDim2.new(0, 8, 0, 4)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Theme.Fonts.Button
			nameLabel.TextSize = 11
			nameLabel.TextColor3 = rarityColor
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Text = swordDef and swordDef.name or "Sword"
			nameLabel.Parent = card

			local tagLabel = Instance.new("TextLabel")
			tagLabel.Name = "TagLabel"
			tagLabel.Size = UDim2.new(1, -70, 0, 16)
			tagLabel.Position = UDim2.new(0, 8, 0, 24)
			tagLabel.BackgroundTransparency = 1
			tagLabel.Font = Theme.Fonts.Body
			tagLabel.TextSize = 10
			tagLabel.TextXAlignment = Enum.TextXAlignment.Left
			if isEquipped then
				tagLabel.Text = "EQUIPPED"
				tagLabel.TextColor3 = Theme.Colors.AuraEmerald
			elseif isPlaced then
				tagLabel.Text = "PLACED"
				tagLabel.TextColor3 = Theme.Colors.AuraCyan
			else
				tagLabel.Text = "BACKPACK"
				tagLabel.TextColor3 = Theme.Colors.TextMuted
			end
			tagLabel.Parent = card

			-- Grade badge on right
			GradeBadge.new({
				Grade = entry.grade,
				Size = UDim2.new(0, 24, 0, 18),
				Position = UDim2.new(1, -8, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				Parent = card,
				ZIndex = 5,
			})

			local clickBtn = Instance.new("TextButton")
			clickBtn.Name = "ClickBtn"
			clickBtn.Size = UDim2.new(1, 0, 1, 0)
			clickBtn.BackgroundTransparency = 1
			clickBtn.Text = ""
			clickBtn.Parent = card

			clickBtn.Activated:Connect(function()
				if isAutoRunning then
					return
				end
				selectedUid = entry.uid
				rebuildList()
				updateDetailPanel()
			end)
		end
	end

	-- Connect buttons
	rollButton.Instance.Activated:Connect(function()
		if not selectedUid or isAutoRunning then
			return
		end

		local selectedEntry: OwnedSwordEntry? = nil
		for _, entry in currentSwords do
			if entry.uid == selectedUid then
				selectedEntry = entry
				break
			end
		end

		if not selectedEntry then
			return
		end

		-- Check if current grade is S or better: requirement 4 confirmation
		if Grades.IsHighGrade(selectedEntry.grade) then
			confirmMsg.Text = ("Warning: This sword currently has Grade %s (%.1fx multiplier)! Rolling will replace it. Are you sure?"):format(
				selectedEntry.grade or "",
				Grades.GetMultiplier(selectedEntry.grade)
			)
			confirmModal.Visible = true
			return
		end

		if onRollCallback then
			onRollCallback(selectedUid)
		end
	end)

	confirmYesBtn.Instance.Activated:Connect(function()
		confirmModal.Visible = false
		if selectedUid and onRollCallback and not isAutoRunning then
			onRollCallback(selectedUid)
		end
	end)

	confirmNoBtn.Instance.Activated:Connect(function()
		confirmModal.Visible = false
	end)

	startAutoBtn.Instance.Activated:Connect(function()
		if not selectedUid or isAutoRunning then
			return
		end
		local maxGems = tonumber(maxGemsBox.Text)
		if onStartAutoCallback then
			onStartAutoCallback(selectedUid, selectedTargetGrade, maxGems)
		end
	end)

	stopAutoBtn.Instance.Activated:Connect(function()
		if onStopAutoCallback then
			onStopAutoCallback()
		end
	end)

	-- Initialize target button highlight (default S)
	if targetButtons[selectedTargetGrade] then
		targetButtons[selectedTargetGrade].TextColor3 = Theme.Colors.AuraGold
		local s = targetButtons[selectedTargetGrade]:FindFirstChild("BtnStroke") :: UIStroke?
		if s then
			s.Color = Theme.Colors.AuraGold
			s.Thickness = 2
		end
	end

	local self: AppraiserUIInstance = {
		Open = function(_, ownedSwords, equippedUid, placedUids, gemBalance)
			currentSwords = ownedSwords
			currentEquippedUid = equippedUid
			currentPlacedMap = placedUids
			currentGems = gemBalance
			confirmModal.Visible = false

			-- Default selected to equipped sword or first sword
			if not selectedUid or selectedUid == "" then
				if equippedUid ~= "" then
					selectedUid = equippedUid
				elseif #ownedSwords > 0 then
					selectedUid = ownedSwords[1].uid
				end
			end

			rebuildList()
			updateDetailPanel()
			popup:Open()
		end,

		Close = function(_)
			confirmModal.Visible = false
			popup:Close()
		end,

		UpdateGems = function(_, gems: number)
			currentGems = gems
			updateDetailPanel()
		end,

		UpdateSwords = function(_, ownedSwords, equippedUid, placedUids)
			currentSwords = ownedSwords
			currentEquippedUid = equippedUid
			currentPlacedMap = placedUids
			rebuildList()
			updateDetailPanel()
		end,

		ShowRollResult = function(_, oldGrade: string, newGrade: string)
			local newDef = Grades.GetGradeDef(newGrade)
			local mult = if newDef then newDef.multiplier else 1.0
			rollResultLabel.Text = ("Result: %s ➔ %s (%.1fx multiplier!)"):format(
				if oldGrade ~= "" then oldGrade else "Ungraded",
				newGrade,
				mult
			)
			rollResultLabel.TextColor3 = Theme.Colors.AuraGold
			updateDetailPanel()
		end,

		UpdateAutoProgress = function(_, rollsDone: number, gemsSpent: number, lastGrade: string, isRunning: boolean, stopReason: string?)
			isAutoRunning = isRunning
			startAutoBtn:SetEnabled(not isRunning and currentGems >= 1)
			stopAutoBtn:SetEnabled(isRunning)
			if isRunning then
				stopAutoBtn:SetBorderColor(Theme.Colors.AuraCrimson)
				stopAutoBtn:SetTextColor(Theme.Colors.AuraCrimson)
			else
				stopAutoBtn:SetBorderColor(Theme.Colors.BorderSubtle)
				stopAutoBtn:SetTextColor(Theme.Colors.TextMuted)
			end

			if isRunning then
				autoProgressLabel.Text = ("Rolling... Rolls: %d  •  Gems Spent: %d  •  Current: %s"):format(
					rollsDone,
					gemsSpent,
					if lastGrade ~= "" then lastGrade else "—"
				)
				autoProgressLabel.TextColor3 = Theme.Colors.AuraEmerald
			else
				autoProgressLabel.Text = ("Auto Roll Ended (%s). Rolls: %d  •  Gems Spent: %d  •  Final Grade: %s"):format(
					stopReason or "Stopped",
					rollsDone,
					gemsSpent,
					if lastGrade ~= "" then lastGrade else "—"
				)
				autoProgressLabel.TextColor3 = Theme.Colors.TextGold
			end

			updateDetailPanel()
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

return AppraiserUI
