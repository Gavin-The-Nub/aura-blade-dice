--!strict
-- PlotController: Client controller for plot lifecycle, active pedestal ProximityPrompts
-- on own plot, 3D pedestal visuals for all players, SwordSelectorPopup, and OfflineIncomePopup.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Swords = require(ReplicatedStorage.Config.Swords)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local SwordSelectorPopup = require(ReplicatedStorage.Shared.UI.SwordSelectorPopup)
local OfflineIncomePopup = require(ReplicatedStorage.Shared.UI.OfflineIncomePopup)

local PlotController = {}

local assignedPlotId: number? = nil
local assignedPlotModel: Instance? = nil
local pedestalSlots: number = 4
local placedSwords: { [string]: string } = {}
local ownedSwords: { any } = {}
local equippedSwordUid: string = ""

local selectorPopupInstance: SwordSelectorPopup.SwordSelectorPopupInstance? = nil
local offlinePopupInstance: OfflineIncomePopup.OfflineIncomePopupInstance? = nil

-- ProximityPrompt tracking (pedestal -> prompt)
local currentPrompts: { [Instance]: ProximityPrompt } = {}
local promptRetryCount = 0
local MAX_PROMPT_RETRIES = 10
local initialized = false

-- 3D Pedestal Visuals tracking (pedestal -> visual data)
type PedestalVisual = {
	blade: BasePart,
	billboard: BillboardGui,
	nameLabel: TextLabel,
	incomeLabel: TextLabel,
	floatTween: Tween?,
	currentId: string,
}

local pedestalVisuals: { [Instance]: PedestalVisual } = {}
local trackedPedestals: { [Instance]: { RBXScriptConnection } } = {}

-- Safely retrieves rarity color with fallback to default theme color
local function getRarityColor(rarityName: unknown): Color3
	if type(rarityName) == "string" and Swords.RarityColors and Swords.RarityColors[rarityName] then
		return Swords.RarityColors[rarityName]
	end
	return Theme.Colors.AuraCyan
end

-- Destroys 3D blade, billboard, and cancels/destroys float tween
local function cleanupPedestalVisual(ped: Instance)
	local visual = pedestalVisuals[ped]
	if not visual then
		return
	end
	pedestalVisuals[ped] = nil

	if visual.floatTween then
		visual.floatTween:Cancel()
		visual.floatTween:Destroy()
		visual.floatTween = nil
	end

	if visual.billboard then
		visual.billboard:Destroy()
	end
	if visual.blade then
		visual.blade:Destroy()
	end
end

-- Updates existing blade color and billboard text in place without destroying the visual
local function updatePedestalVisualDetails(ped: Instance, visual: PedestalVisual)
	local rawName = ped:GetAttribute("PlacedSwordName")
	local name = if type(rawName) == "string" and rawName ~= "" then rawName else "Sword"

	local rawRarity = ped:GetAttribute("PlacedSwordRarity")
	local rarityColor = getRarityColor(rawRarity)

	local rawGps = ped:GetAttribute("PlacedSwordGoldPerSec")
	local gps = if type(rawGps) == "number" and rawGps == rawGps and rawGps > 0 then rawGps else 0

	visual.blade.Color = rarityColor
	visual.nameLabel.Text = name
	visual.nameLabel.TextColor3 = rarityColor
	visual.incomeLabel.Text = ("+%s Gold/s"):format(NumberFormat.format(gps))
end

-- Creates, updates in-place, or removes 3D visual on a pedestal
local function refreshPedestalVisual(ped: Instance)
	if not ped:IsA("BasePart") then
		return
	end

	local rawId = ped:GetAttribute("PlacedSwordId")
	local swordId = if type(rawId) == "string" and rawId ~= "" then rawId else nil

	local existingVisual = pedestalVisuals[ped]

	-- No sword placed: clean up if visual exists
	if not swordId then
		if existingVisual then
			cleanupPedestalVisual(ped)
		end
		return
	end

	-- Sword is placed! If same sword ID, update details in place
	if existingVisual then
		if existingVisual.currentId == swordId then
			updatePedestalVisualDetails(ped, existingVisual)
			return
		else
			cleanupPedestalVisual(ped)
		end
	end

	local rawRarity = ped:GetAttribute("PlacedSwordRarity")
	local rarityColor = getRarityColor(rawRarity)

	-- Floating blade: single Part, no shadow, no collision, anchored, parented under pedestal
	local blade = Instance.new("Part")
	blade.Name = "FloatingBlade"
	blade.Size = Vector3.new(0.35, 2.6, 0.6)
	local pedCFrame = ped.CFrame
	local basePos = pedCFrame.Position + Vector3.new(0, (ped.Size.Y / 2) + 1.8, 0)
	blade.CFrame = CFrame.new(basePos) * CFrame.Angles(0, 0, math.rad(15))
	blade.Material = Enum.Material.Neon
	blade.Color = rarityColor
	blade.CastShadow = false
	blade.CanCollide = false
	blade.CanTouch = false
	blade.CanQuery = false
	blade.Anchored = true
	blade.Parent = ped

	-- Floating animation via single looped Tween (canceled and destroyed in cleanup)
	local tweenInfo = TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local floatTween = TweenService:Create(blade, tweenInfo, {
		CFrame = blade.CFrame + Vector3.new(0, 0.35, 0),
	})
	floatTween:Play()

	-- BillboardGui: parented under pedestal, LightInfluence = 0, AlwaysOnTop = false, MaxDistance = 60
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PedestalInfoGui"
	billboard.Adornee = blade
	billboard.Size = UDim2.new(0, 160, 0, 44)
	billboard.StudsOffset = Vector3.new(0, 2.0, 0)
	billboard.MaxDistance = 60
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = false
	billboard.Parent = ped

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "SwordName"
	nameLabel.Size = UDim2.new(1, 0, 0, 22)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Theme.Fonts.Title
	nameLabel.TextSize = 13
	nameLabel.TextColor3 = rarityColor
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = billboard

	local incomeLabel = Instance.new("TextLabel")
	incomeLabel.Name = "SwordIncome"
	incomeLabel.Size = UDim2.new(1, 0, 0, 18)
	incomeLabel.Position = UDim2.new(0, 0, 0, 22)
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.Font = Theme.Fonts.Button
	incomeLabel.TextSize = 11
	incomeLabel.TextColor3 = Theme.Colors.TextGold
	incomeLabel.TextStrokeTransparency = 0.6
	incomeLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	incomeLabel.Parent = billboard

	local visual: PedestalVisual = {
		blade = blade,
		billboard = billboard,
		nameLabel = nameLabel,
		incomeLabel = incomeLabel,
		floatTween = floatTween,
		currentId = swordId,
	}

	updatePedestalVisualDetails(ped, visual)
	pedestalVisuals[ped] = visual
end

-- Cleanly removes all visual state and listeners for a pedestal
local function cleanupPedestal(ped: Instance)
	cleanupPedestalVisual(ped)
	local conns = trackedPedestals[ped]
	if conns then
		for _, conn in conns do
			conn:Disconnect()
		end
		trackedPedestals[ped] = nil
	end
	if currentPrompts[ped] then
		currentPrompts[ped]:Destroy()
		currentPrompts[ped] = nil
	end
end

-- Hooks attribute and lifecycle listeners for any pedestal in workspace
local function trackPedestal(ped: Instance)
	if not ped:IsA("BasePart") or trackedPedestals[ped] then
		return
	end

	-- Initial visual check
	refreshPedestalVisual(ped)

	local idConn = ped:GetAttributeChangedSignal("PlacedSwordId"):Connect(function()
		refreshPedestalVisual(ped)
	end)

	local nameConn = ped:GetAttributeChangedSignal("PlacedSwordName"):Connect(function()
		local visual = pedestalVisuals[ped]
		if visual then
			updatePedestalVisualDetails(ped, visual)
		end
	end)

	local rarityConn = ped:GetAttributeChangedSignal("PlacedSwordRarity"):Connect(function()
		local visual = pedestalVisuals[ped]
		if visual then
			updatePedestalVisualDetails(ped, visual)
		end
	end)

	local gpsConn = ped:GetAttributeChangedSignal("PlacedSwordGoldPerSec"):Connect(function()
		local visual = pedestalVisuals[ped]
		if visual then
			updatePedestalVisualDetails(ped, visual)
		end
	end)

	local ancestryConn: RBXScriptConnection? = nil
	ancestryConn = ped.AncestryChanged:Connect(function(_, parent)
		if not parent or not ped:IsDescendantOf(workspace) then
			cleanupPedestal(ped)
		end
	end)

	trackedPedestals[ped] = { idConn, nameConn, rarityConn, gpsConn, ancestryConn :: RBXScriptConnection }
end

local function openSwordSelector(slotIndex: number)
	if not selectorPopupInstance then
		warn("[PlotController] Cannot open popup: selectorPopupInstance is nil")
		return
	end

	local placedUid = placedSwords[tostring(slotIndex)]
	local placedUidsMap: { [string]: boolean } = {}
	for _, pUid in placedSwords do
		if type(pUid) == "string" and pUid ~= "" then
			placedUidsMap[pUid] = true
		end
	end

	selectorPopupInstance:Open(
		slotIndex,
		placedUid,
		ownedSwords,
		equippedSwordUid,
		placedUidsMap
	)
end

local function getPlotModel(plotId: number?): Instance?
	if assignedPlotModel and assignedPlotModel.Parent then
		return assignedPlotModel
	end
	if not plotId then
		return nil
	end
	local plotsFolder = workspace:FindFirstChild("Plots") or (workspace:WaitForChild("Plots", 3) :: Folder?)
	if plotsFolder then
		local model = plotsFolder:FindFirstChild(("Plot_%d"):format(plotId)) or plotsFolder:WaitForChild(("Plot_%d"):format(plotId), 3)
		if model then
			return model
		end
	end
	for _, inst in CollectionService:GetTagged("Plot") do
		if inst:GetAttribute("PlotId") == plotId then
			return inst
		end
	end
	return nil
end

-- Sets up / reuses ProximityPrompts on active pedestals of the player's OWN plot only
local function refreshPlotPrompts()
	if not assignedPlotId then
		for ped, prompt in currentPrompts do
			prompt:Destroy()
		end
		table.clear(currentPrompts)
		return
	end

	local plotModel = getPlotModel(assignedPlotId)
	if not plotModel then
		warn(("[PlotController] No plot found for plot %s (waiting for replication)"):format(tostring(assignedPlotId)))
		if promptRetryCount < MAX_PROMPT_RETRIES then
			promptRetryCount += 1
			task.delay(1, refreshPlotPrompts)
		else
			warn(("[PlotController] Failed to find plot %s after %d attempts; stopping retries."):format(tostring(assignedPlotId), MAX_PROMPT_RETRIES))
		end
		return
	end
	assignedPlotModel = plotModel

	local activePedestalsOnOwnPlot: { [Instance]: boolean } = {}
	local mountedCount = 0

	for _, ped in assignedPlotModel:GetDescendants() do
		if CollectionService:HasTag(ped, "Pedestal") and ped:IsA("BasePart") then
			local slot = ped:GetAttribute("SlotIndex") or ped:GetAttribute("Slot")
			if type(slot) ~= "number" then
				slot = tonumber(ped.Name:match("%d+$")) or 1
			end

			if slot <= pedestalSlots then
				activePedestalsOnOwnPlot[ped] = true
				ped.Material = Enum.Material.Neon
				ped.Color = Theme.Colors.BorderSubtle

				local isOccupied = placedSwords[tostring(slot)] ~= nil and placedSwords[tostring(slot)] ~= ""
				local actionText = if isOccupied then "Manage" else "Place Sword"

				local prompt = currentPrompts[ped] or (ped:FindFirstChild("PedestalPrompt") :: ProximityPrompt?)
				if prompt then
					-- Reuse existing prompt without reconnecting Triggered
					prompt.ActionText = actionText
					prompt.ObjectText = ("Pedestal #%d"):format(slot)
					currentPrompts[ped] = prompt
				else
					-- Create new prompt and connect Triggered exactly once
					prompt = Instance.new("ProximityPrompt")
					prompt.Name = "PedestalPrompt"
					prompt.ActionText = actionText
					prompt.ObjectText = ("Pedestal #%d"):format(slot)
					prompt.HoldDuration = 0
					prompt.RequiresLineOfSight = false
					prompt.MaxActivationDistance = 10
					prompt.Parent = ped

					local currentSlot = slot
					prompt.Triggered:Connect(function(promptPlayer: Player)
						if promptPlayer == Players.LocalPlayer then
							openSwordSelector(currentSlot)
						end
					end)

					currentPrompts[ped] = prompt
				end
				mountedCount += 1
			else
				-- Locked pedestal above owner's PedestalSlots
				ped.Material = Enum.Material.Slate
				ped.Color = Theme.Colors.BackgroundDark

				local prompt = currentPrompts[ped] or (ped:FindFirstChild("PedestalPrompt") :: ProximityPrompt?)
				if prompt then
					prompt:Destroy()
					currentPrompts[ped] = nil
				end
			end
		end
	end

	-- Destroy prompts for any pedestals that are no longer active on player's own plot
	for ped, prompt in currentPrompts do
		if not activePedestalsOnOwnPlot[ped] then
			prompt:Destroy()
			currentPrompts[ped] = nil
		end
	end

	if mountedCount == 0 then
		warn(("[PlotController] No pedestals found on plot %s (waiting for replication)"):format(plotModel.Name))
		if promptRetryCount < MAX_PROMPT_RETRIES then
			promptRetryCount += 1
			task.delay(1, refreshPlotPrompts)
		else
			warn(("[PlotController] Failed to find pedestals on plot %s after %d attempts; stopping retries."):format(plotModel.Name, MAX_PROMPT_RETRIES))
		end
	else
		promptRetryCount = 0
	end
end

function PlotController.GetAssignedPlot(): (number?, Instance?)
	return assignedPlotId, assignedPlotModel
end

function PlotController.Init()
	if initialized or not RunService:IsClient() then
		return
	end

	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end
	initialized = true

	local playerGui = localPlayer:WaitForChild("PlayerGui")

	-- Create UI popup components attached to PlayerGui
	selectorPopupInstance = SwordSelectorPopup.new(playerGui)
	offlinePopupInstance = OfflineIncomePopup.new(playerGui)

	-- SwordSelector callbacks
	if selectorPopupInstance then
		selectorPopupInstance:SetOnPlace(function(slotIndex: number, swordUid: string)
			task.spawn(function()
				local placeFunc = Remotes.getFunction("PlaceSword")
				local ok, success, errMsg = pcall(function()
					return placeFunc:InvokeServer(slotIndex, swordUid)
				end)

				if ok and success then
					placedSwords[tostring(slotIndex)] = swordUid
					local placedUidsMap: { [string]: boolean } = {}
					for _, pUid in placedSwords do
						if type(pUid) == "string" and pUid ~= "" then
							placedUidsMap[pUid] = true
						end
					end
					if selectorPopupInstance then
						selectorPopupInstance:Open(
							slotIndex,
							swordUid,
							ownedSwords,
							equippedSwordUid,
							placedUidsMap
						)
					end
				else
					if selectorPopupInstance then
						selectorPopupInstance:SetBusy(false)
					end
					warn("[PlotController] PlaceSword failed: " .. tostring(errMsg or "Unknown error"))
				end
			end)
		end)

		selectorPopupInstance:SetOnRemove(function(slotIndex: number)
			task.spawn(function()
				local removeFunc = Remotes.getFunction("RemoveSword")
				local ok, success, errMsg = pcall(function()
					return removeFunc:InvokeServer(slotIndex)
				end)

				if ok and success then
					placedSwords[tostring(slotIndex)] = nil
					local placedUidsMap: { [string]: boolean } = {}
					for _, pUid in placedSwords do
						if type(pUid) == "string" and pUid ~= "" then
							placedUidsMap[pUid] = true
						end
					end
					if selectorPopupInstance then
						selectorPopupInstance:Open(
							slotIndex,
							nil,
							ownedSwords,
							equippedSwordUid,
							placedUidsMap
						)
					end
				else
					if selectorPopupInstance then
						selectorPopupInstance:SetBusy(false)
					end
					warn("[PlotController] RemoveSword failed: " .. tostring(errMsg or "Unknown error"))
				end
			end)
		end)
	end

	-- Track all pedestals across Workspace for 3D visuals
	for _, ped in CollectionService:GetTagged("Pedestal") do
		trackPedestal(ped)
	end

	CollectionService:GetInstanceAddedSignal("Pedestal"):Connect(function(ped)
		trackPedestal(ped)
	end)

	CollectionService:GetInstanceRemovedSignal("Pedestal"):Connect(function(ped)
		cleanupPedestal(ped)
	end)

	-- Listen for plot assignment event from server
	local plotAssignedEvent = Remotes.getEvent("PlotAssigned")
	plotAssignedEvent.OnClientEvent:Connect(function(plotId: number?, plotModel: Instance?)
		assignedPlotId = plotId
		assignedPlotModel = plotModel
		refreshPlotPrompts()

		if plotId and plotModel then
			print(("[PlotController] Welcome to your plot! (Plot #%d)"):format(plotId))
		else
			print("[PlotController] All plots in this server are currently claimed.")
		end
	end)

	-- Sync initial plot data
	task.spawn(function()
		local getPlotDataFunc = Remotes.getFunction("GetPlotData")
		local ok, data = pcall(function()
			return getPlotDataFunc:InvokeServer()
		end)

		if ok and type(data) == "table" then
			if data.plotId then
				assignedPlotId = data.plotId
			end
			if type(data.placedSwords) == "table" then
				placedSwords = data.placedSwords
			end
			if type(data.pedestalSlots) == "number" then
				pedestalSlots = data.pedestalSlots
			end
			refreshPlotPrompts()
		end
	end)

	-- Sync initial inventory data for candidates & equipped status
	task.spawn(function()
		local getInitialDataFunc = Remotes.getFunction("GetInitialData")
		local ok, data = pcall(function()
			return getInitialDataFunc:InvokeServer()
		end)

		if ok and type(data) == "table" then
			if type(data.OwnedSwords) == "table" then
				ownedSwords = data.OwnedSwords
			end
			if type(data.EquippedSword) == "string" then
				equippedSwordUid = data.EquippedSword
			end
			if type(data.PlacedSwords) == "table" then
				placedSwords = data.PlacedSwords
			end
			if type(data.PedestalSlots) == "number" then
				pedestalSlots = data.PedestalSlots
			end
			refreshPlotPrompts()
		end
	end)

	-- Claim offline income once on startup
	task.spawn(function()
		local claimOfflineFunc = Remotes.getFunction("ClaimOfflineIncome")
		local ok, result = pcall(function()
			return claimOfflineFunc:InvokeServer()
		end)

		if ok and type(result) == "table" and type(result.gold) == "number" and result.gold > 0 then
			if offlinePopupInstance then
				offlinePopupInstance:Show(result.gold, result.seconds or 0)
			end
		end
	end)

	-- Listen for DataChanged events
	local dataChangedEvent = Remotes.getEvent("DataChanged")
	dataChangedEvent.OnClientEvent:Connect(function(key: unknown, value: unknown)
		if key == "PlacedSwords" and type(value) == "table" then
			placedSwords = value :: { [string]: string }
			refreshPlotPrompts()
		elseif key == "PedestalSlots" and type(value) == "number" then
			pedestalSlots = value :: number
			refreshPlotPrompts()
		elseif key == "OwnedSwords" and type(value) == "table" then
			ownedSwords = value :: { any }
		elseif key == "EquippedSword" and type(value) == "string" then
			equippedSwordUid = value :: string
		end
	end)
end

-- Auto-initialize when required by player scripts
task.spawn(PlotController.Init)

return PlotController
