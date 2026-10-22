--!strict
-- SwordSelectorPopup: Mobile-first modal to place available swords onto a pedestal or remove
-- currently placed swords. Enforces server-authoritative validation and disables buttons in flight.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Config = ReplicatedStorage:WaitForChild("Config")
local Swords = require(Config:WaitForChild("Swords"))
local GameConfig = require(Config:WaitForChild("Game"))

local Components = Shared:WaitForChild("UI"):WaitForChild("Components")
local Popup = require(Components:WaitForChild("Popup"))
local Button = require(Components:WaitForChild("Button"))

export type OwnedSwordEntry = {
	uid: string,
	id: string,
	[string]: any,
}

export type SwordSelectorPopupInstance = {
	Open: (
		self: SwordSelectorPopupInstance,
		slotIndex: number,
		currentPlacedUid: string?,
		ownedSwords: { OwnedSwordEntry },
		equippedUid: string,
		placedUidsMap: { [string]: boolean }
	) -> (),
	Close: (self: SwordSelectorPopupInstance) -> (),
	SetBusy: (self: SwordSelectorPopupInstance, isBusy: boolean) -> (),
	SetOnPlace: (self: SwordSelectorPopupInstance, callback: (slotIndex: number, swordUid: string) -> ()) -> (),
	SetOnRemove: (self: SwordSelectorPopupInstance, callback: (slotIndex: number) -> ()) -> (),
	Destroy: (self: SwordSelectorPopupInstance) -> (),
}

local SwordSelectorPopup = {}

-- Cached sword definitions
local swordDefMap: { [string]: Swords.SwordDef } = {}
for _, def in Swords do
	swordDefMap[def.id] = def
end

-- Rarity rank for sorting (highest first)
local rarityRank: { [string]: number } = {}
for idx, rarity in ipairs(Swords.Rarities) do
	rarityRank[rarity] = idx
end

function SwordSelectorPopup.new(parentGui: Instance): SwordSelectorPopupInstance
	local screenGui: Instance
	if parentGui:IsA("ScreenGui") then
		screenGui = parentGui
	else
		local sg = Instance.new("ScreenGui")
		sg.Name = "AuraBladeSwordSelectorGui"
		sg.ResetOnSpawn = false
		sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		sg.DisplayOrder = 15
		sg.Parent = parentGui
		screenGui = sg
	end

	local popup = Popup.new({
		Title = "PEDESTAL #1",
		Size = UDim2.new(0.92, 0, 0.85, 0),
		MaxWidth = 560,
		MaxHeight = 520,
		Parent = screenGui,
	})

	local rootContent = popup.Content

	-- Header container for occupied slot info / remove button
	local topContainer = Instance.new("Frame")
	topContainer.Name = "TopContainer"
	topContainer.Size = UDim2.new(1, 0, 0, 84)
	topContainer.Position = UDim2.new(0, 0, 0, 0)
	topContainer.BackgroundTransparency = 1
	topContainer.Parent = rootContent

	local occupiedFrame = Instance.new("Frame")
	occupiedFrame.Name = "OccupiedFrame"
	occupiedFrame.Size = UDim2.new(1, 0, 1, 0)
	occupiedFrame.BackgroundColor3 = Theme.Colors.BackgroundDark
	occupiedFrame.BackgroundTransparency = 0.3
	occupiedFrame.Parent = topContainer

	local occCorner = Instance.new("UICorner")
	occCorner.CornerRadius = Theme.Corner.Medium
	occCorner.Parent = occupiedFrame

	local occStroke = Instance.new("UIStroke")
	occStroke.Color = Theme.Colors.Border
	occStroke.Thickness = Theme.Stroke.WidthDefault
	occStroke.Parent = occupiedFrame

	local occTitle = Instance.new("TextLabel")
	occTitle.Name = "OccupiedTitle"
	occTitle.Size = UDim2.new(1, -16, 0, 18)
	occTitle.Position = UDim2.new(0, 10, 0, 6)
	occTitle.BackgroundTransparency = 1
	occTitle.Font = Theme.Fonts.Button
	occTitle.TextSize = 11
	occTitle.TextColor3 = Theme.Colors.TextGold
	occTitle.TextXAlignment = Enum.TextXAlignment.Left
	occTitle.Text = "CURRENTLY PLACED SWORD:"
	occTitle.Parent = occupiedFrame

	local occSwordName = Instance.new("TextLabel")
	occSwordName.Name = "OccupiedSwordName"
	occSwordName.Size = UDim2.new(0.6, -16, 0, 26)
	occSwordName.Position = UDim2.new(0, 10, 0, 24)
	occSwordName.BackgroundTransparency = 1
	occSwordName.Font = Theme.Fonts.Title
	occSwordName.TextSize = 16
	occSwordName.TextColor3 = Theme.Colors.TextPrimary
	occSwordName.TextXAlignment = Enum.TextXAlignment.Left
	occSwordName.Text = "None"
	occSwordName.Parent = occupiedFrame

	local occSwordRates = Instance.new("TextLabel")
	occSwordRates.Name = "OccupiedRates"
	occSwordRates.Size = UDim2.new(0.6, -16, 0, 20)
	occSwordRates.Position = UDim2.new(0, 10, 0, 52)
	occSwordRates.BackgroundTransparency = 1
	occSwordRates.Font = Theme.Fonts.Body
	occSwordRates.TextSize = 12
	occSwordRates.TextColor3 = Theme.Colors.TextSecondary
	occSwordRates.TextXAlignment = Enum.TextXAlignment.Left
	occSwordRates.Text = "+0 Gold/s passive"
	occSwordRates.Parent = occupiedFrame

	-- Remove Button
	local removeBtn = Button.new({
		Name = "RemoveSwordButton",
		Text = "REMOVE",
		Size = UDim2.new(0, 110, 0, 42),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor = Theme.Colors.ButtonSecondary,
		BorderColor = Theme.Colors.ButtonClose,
		TextColor = Theme.Colors.ButtonClose,
		CornerRadius = Theme.Corner.Medium,
		Parent = occupiedFrame,
	})

	-- Empty Pedestal banner
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyLabel"
	emptyLabel.Size = UDim2.new(1, -20, 1, 0)
	emptyLabel.Position = UDim2.new(0, 10, 0, 0)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Font = Theme.Fonts.Title
	emptyLabel.TextSize = 14
	emptyLabel.TextColor3 = Theme.Colors.TextMuted
	emptyLabel.Text = "Pedestal is empty. Select an owned sword below to place it."
	emptyLabel.Visible = false
	emptyLabel.Parent = occupiedFrame

	-- Section Divider
	local sectionHeader = Instance.new("TextLabel")
	sectionHeader.Name = "SectionHeader"
	sectionHeader.Size = UDim2.new(1, 0, 0, 22)
	sectionHeader.Position = UDim2.new(0, 0, 0, 92)
	sectionHeader.BackgroundTransparency = 1
	sectionHeader.Font = Theme.Fonts.Button
	sectionHeader.TextSize = 12
	sectionHeader.TextColor3 = Theme.Colors.TextSecondary
	sectionHeader.TextXAlignment = Enum.TextXAlignment.Left
	sectionHeader.Text = "AVAILABLE SWORDS IN BACKPACK (50% PASSIVE INCOME):"
	sectionHeader.Parent = rootContent

	-- Scrolling container for candidates
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "CandidateScroll"
	scrollFrame.Size = UDim2.new(1, 0, 1, -122)
	scrollFrame.Position = UDim2.new(0, 0, 0, 118)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = Theme.Colors.Border
	scrollFrame.BorderSizePixel = 0
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.Parent = rootContent

	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.FillDirection = Enum.FillDirection.Vertical
	scrollLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	scrollLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	scrollLayout.Padding = UDim.new(0, 8)
	scrollLayout.Parent = scrollFrame

	local noSwordsText = Instance.new("TextLabel")
	noSwordsText.Name = "NoSwordsNotice"
	noSwordsText.Size = UDim2.new(1, -24, 0, 100)
	noSwordsText.Position = UDim2.new(0, 12, 0, 40)
	noSwordsText.BackgroundTransparency = 1
	noSwordsText.Font = Theme.Fonts.Body
	noSwordsText.TextSize = 13
	noSwordsText.TextColor3 = Theme.Colors.TextMuted
	noSwordsText.TextWrapped = true
	noSwordsText.Text = "No available swords to place.\n\nSwords currently equipped or placed on other pedestals cannot be selected."
	noSwordsText.Visible = false
	noSwordsText.Parent = scrollFrame

	-- Internal state
	local currentSlot = 1
	local currentPlacedSwordUid: string? = nil
	local isCurrentlyBusy = false
	local placeButtons: { Button.ButtonComponent } = {}

	local onPlaceCallback: ((number, string) -> ())? = nil
	local onRemoveCallback: ((number) -> ())? = nil

	local function setBusyState(busy: boolean)
		isCurrentlyBusy = busy
		removeBtn:SetEnabled(not busy)
		for _, b in placeButtons do
			b:SetEnabled(not busy)
		end
	end

	removeBtn.Instance.Activated:Connect(function()
		if isCurrentlyBusy then
			return
		end
		if onRemoveCallback and currentSlot then
			setBusyState(true)
			onRemoveCallback(currentSlot)
		end
	end)

	local function clearList()
		for _, b in placeButtons do
			b:Destroy()
		end
		table.clear(placeButtons)

		for _, child in scrollFrame:GetChildren() do
			if child:IsA("Frame") and child.Name:match("^Row_") then
				child:Destroy()
			end
		end
	end

	local function renderPopup(
		slotIndex: number,
		placedUid: string?,
		ownedSwords: { OwnedSwordEntry },
		equippedUid: string,
		placedUidsMap: { [string]: boolean }
	)
		currentSlot = slotIndex
		currentPlacedSwordUid = placedUid
		popup:SetTitle(("PEDESTAL #%d"):format(slotIndex))

		-- Render occupied slot banner
		if placedUid and placedUid ~= "" then
			local placedEntry: OwnedSwordEntry? = nil
			for _, e in ownedSwords do
				if e.uid == placedUid then
					placedEntry = e
					break
				end
			end

			local def = placedEntry and swordDefMap[placedEntry.id]
			local rColor = (def and Swords.RarityColors and Swords.RarityColors[def.rarity]) or Theme.Colors.TextPrimary
			local baseDmg = (def and def.baseDamage) or 1
			local passiveGps = math.floor((baseDmg * (GameConfig.Plot.PassiveRateMultiplier or 0.5)) + 0.5)

			occSwordName.Text = def and def.name or "Unknown Sword"
			occSwordName.TextColor3 = rColor
			occSwordRates.Text = ("Damage: %s | Passive: +%s Gold/sec"):format(
				NumberFormat.format(baseDmg),
				NumberFormat.format(passiveGps)
			)

			occTitle.Visible = true
			occSwordName.Visible = true
			occSwordRates.Visible = true
			removeBtn.Instance.Visible = true
			emptyLabel.Visible = false
		else
			occTitle.Visible = false
			occSwordName.Visible = false
			occSwordRates.Visible = false
			removeBtn.Instance.Visible = false
			emptyLabel.Visible = true
		end

		clearList()

		-- Filter available swords: not equipped, and not placed on any slot
		local candidates: { OwnedSwordEntry } = {}
		for _, entry in ownedSwords do
			if entry.uid ~= equippedUid and not placedUidsMap[entry.uid] then
				table.insert(candidates, entry)
			end
		end

		-- Sort by rarity (highest first) then by damage (highest first)
		table.sort(candidates, function(a, b)
			local defA = swordDefMap[a.id]
			local defB = swordDefMap[b.id]
			local rankA = if defA then rarityRank[defA.rarity] or 0 else 0
			local rankB = if defB then rarityRank[defB.rarity] or 0 else 0
			if rankA ~= rankB then
				return rankA > rankB
			end
			local dmgA = if defA then defA.baseDamage else 0
			local dmgB = if defB then defB.baseDamage else 0
			return dmgA > dmgB
		end)

		if #candidates == 0 then
			noSwordsText.Visible = true
			scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 140)
			return
		end

		noSwordsText.Visible = false
		local totalHeight = #candidates * 64
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)

		for idx, entry in ipairs(candidates) do
			local def = swordDefMap[entry.id]
			local rarityName = def and def.rarity or "Common"
			local rColor = (Swords.RarityColors and Swords.RarityColors[rarityName]) or Theme.Colors.AuraCyan
			local baseDmg = def and def.baseDamage or 1
			local passiveGps = math.floor((baseDmg * (GameConfig.Plot.PassiveRateMultiplier or 0.5)) + 0.5)

			local row = Instance.new("Frame")
			row.Name = "Row_" .. entry.uid
			row.Size = UDim2.new(1, -12, 0, 56)
			row.BackgroundColor3 = Theme.Colors.ButtonSecondary
			row.BackgroundTransparency = 0.2
			row.LayoutOrder = idx
			row.Parent = scrollFrame

			local rowCorner = Instance.new("UICorner")
			rowCorner.CornerRadius = Theme.Corner.Medium
			rowCorner.Parent = row

			local rowStroke = Instance.new("UIStroke")
			rowStroke.Color = rColor
			rowStroke.Thickness = 1.2
			rowStroke.Parent = row

			-- Sword Icon
			local icon = Instance.new("TextLabel")
			icon.Name = "Icon"
			icon.Size = UDim2.new(0, 36, 1, 0)
			icon.Position = UDim2.new(0, 8, 0, 0)
			icon.BackgroundTransparency = 1
			icon.Font = Theme.Fonts.Title
			icon.TextSize = 22
			icon.TextColor3 = rColor
			icon.Text = "🗡️"
			icon.Parent = row

			-- Sword info
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "Name"
			nameLabel.Size = UDim2.new(0.55, -48, 0, 22)
			nameLabel.Position = UDim2.new(0, 48, 0, 7)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Theme.Fonts.Title
			nameLabel.TextSize = 14
			nameLabel.TextColor3 = rColor
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Text = def and def.name or "Sword"
			nameLabel.Parent = row

			local statsLabel = Instance.new("TextLabel")
			statsLabel.Name = "Stats"
			statsLabel.Size = UDim2.new(0.55, -48, 0, 18)
			statsLabel.Position = UDim2.new(0, 48, 0, 30)
			statsLabel.BackgroundTransparency = 1
			statsLabel.Font = Theme.Fonts.Body
			statsLabel.TextSize = 11
			statsLabel.TextColor3 = Theme.Colors.TextSecondary
			statsLabel.TextXAlignment = Enum.TextXAlignment.Left
			statsLabel.Text = ("%s | +%s Gold/sec"):format(
				rarityName:upper(),
				NumberFormat.format(passiveGps)
			)
			statsLabel.Parent = row

			-- Place Button
			local placeBtn = Button.new({
				Name = "PlaceButton",
				Text = "PLACE",
				Size = UDim2.new(0, 88, 0, 38),
				Position = UDim2.new(1, -10, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				BackgroundColor = Theme.Colors.ButtonPrimary,
				BorderColor = Theme.Colors.AuraCyan,
				TextColor = Theme.Colors.TextPrimary,
				CornerRadius = Theme.Corner.Medium,
				Parent = row,
				OnClick = function()
					if isCurrentlyBusy then
						return
					end
					if onPlaceCallback and currentSlot then
						setBusyState(true)
						onPlaceCallback(currentSlot, entry.uid)
					end
				end,
			})

			table.insert(placeButtons, placeBtn)
		end

		setBusyState(false)
	end

	local self: SwordSelectorPopupInstance = {
		Open = function(_, slotIndex, placedUid, ownedSwords, equippedUid, placedUidsMap)
			renderPopup(slotIndex, placedUid, ownedSwords, equippedUid, placedUidsMap)
			popup:Open()
		end,
		Close = function(_)
			popup:Close()
		end,
		SetBusy = function(_, busy)
			setBusyState(busy)
		end,
		SetOnPlace = function(_, callback)
			onPlaceCallback = callback
		end,
		SetOnRemove = function(_, callback)
			onRemoveCallback = callback
		end,
		Destroy = function(_)
			clearList()
			removeBtn:Destroy()
			popup:Destroy()
		end,
	}

	return self
end

return SwordSelectorPopup
