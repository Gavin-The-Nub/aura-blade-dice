--!strict
-- PlotController: Client controller for plot lifecycle, active pedestal ProximityPrompts
-- on own plot, SwordSelectorPopup for placing/removing swords, and OfflineIncomePopup on startup.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Theme = require(ReplicatedStorage.Shared.Theme)
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
local currentPrompts: { [Instance]: ProximityPrompt } = {}
local promptRetryCount = 0
local MAX_PROMPT_RETRIES = 10
local initialized = false

local function openSwordSelector(slotIndex: number)
	print(("[PlotController] Before opening popup for slot %d"):format(slotIndex))
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

	local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
	local scrim = playerGui and playerGui:FindFirstChild("PopupScrim_PEDESTAL #" .. slotIndex, true)
	local screenGui = scrim and scrim:FindFirstAncestorWhichIsA("ScreenGui")
	print(("[PlotController] After opening popup: ScreenGui.Enabled = %s, root Visible = %s, AbsoluteSize = %s"):format(
		tostring(screenGui and screenGui.Enabled),
		tostring(scrim and scrim.Visible),
		tostring(scrim and scrim.AbsoluteSize)
	))
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

-- Sets up ProximityPrompts on active pedestals of the player's OWN plot only
local function refreshPlotPrompts()
	for ped, prompt in currentPrompts do
		prompt:Destroy()
	end
	table.clear(currentPrompts)

	if not assignedPlotId then
		warn("[PlotController] Cannot mount prompts: assignedPlotId is nil")
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

	local mountedCount = 0
	for _, ped in assignedPlotModel:GetDescendants() do
		if CollectionService:HasTag(ped, "Pedestal") and ped:IsA("BasePart") then
			local slot = ped:GetAttribute("SlotIndex") or ped:GetAttribute("Slot")
			if type(slot) ~= "number" then
				slot = tonumber(ped.Name:match("%d+$")) or 1
			end

			if slot <= pedestalSlots then
				ped.Material = Enum.Material.Neon
				ped.Color = Theme.Colors.BorderSubtle

				local isOccupied = placedSwords[tostring(slot)] ~= nil and placedSwords[tostring(slot)] ~= ""

				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "PedestalPrompt"
				prompt.ActionText = if isOccupied then "Manage" else "Place Sword"
				prompt.ObjectText = ("Pedestal #%d"):format(slot)
				prompt.HoldDuration = 0
				prompt.RequiresLineOfSight = false
				prompt.MaxActivationDistance = 10
				prompt.Parent = ped

				prompt.Triggered:Connect(function(promptPlayer: Player)
					if promptPlayer == Players.LocalPlayer then
						print(("[PlotController] Prompt triggered for slot %d"):format(slot))
						openSwordSelector(slot)
					end
				end)

				currentPrompts[ped] = prompt
				mountedCount += 1
			else
				ped.Material = Enum.Material.Slate
				ped.Color = Theme.Colors.BackgroundDark
			end
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
		print(("[PlotController] Mounted %d prompts on plot %d"):format(mountedCount, assignedPlotId))
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
