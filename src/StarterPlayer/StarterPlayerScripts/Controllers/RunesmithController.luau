--!strict
-- RunesmithController: Client controller managing Runesmith UI,
-- invoking RollBlessing and GetBlessingCost remotes, and syncing live player Gold and inventory.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = Shared:WaitForChild("UI")
local RunesmithUI = require(UI:WaitForChild("RunesmithUI"))
local Blessings = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("Blessings"))

type RunesmithUIInstance = RunesmithUI.RunesmithUIInstance

local RunesmithController = {}

local ui: RunesmithUIInstance? = nil
local isOpened = false

-- Local cached data
local localOwnedSwords: { any } = {}
local localEquippedUid = ""
local localPlacedMap: { [string]: boolean } = {}
local localGold = 0
local localCost = Blessings.MinCost

local function syncPlacedMap(placedSwordsData: any)
	table.clear(localPlacedMap)
	if typeof(placedSwordsData) == "table" then
		for _, pUid in placedSwordsData do
			if typeof(pUid) == "string" and pUid ~= "" then
				localPlacedMap[pUid] = true
			end
		end
	end
end

function RunesmithController.Init(playerGui: Instance?)
	local guiParent = playerGui or player:WaitForChild("PlayerGui")
	local runesmithInstance = RunesmithUI.new(guiParent)
	ui = runesmithInstance

	-- Remote bindings
	local rollBlessingFunc = Remotes.getFunction("RollBlessing")
	local getBlessingCostFunc = Remotes.getFunction("GetBlessingCost")
	local dataChangedEvent = Remotes.getEvent("DataChanged")

	-- Handle roll
	runesmithInstance:SetOnRoll(function(uid: string)
		task.spawn(function()
			local ok, success, oldBlessing, newBlessing, costPaid, errMsg = pcall(function()
				return rollBlessingFunc:InvokeServer(uid)
			end)

			if ok and success and newBlessing then
				runesmithInstance:ShowRollResult(oldBlessing or "", newBlessing, costPaid or localCost)
			elseif not ok or not success then
				warn(("[RunesmithController] Roll failed: %s"):format(tostring(errMsg or success)))
				runesmithInstance:UpdateGold(localGold)
			end
		end)
	end)

	runesmithInstance:SetOnClose(function()
		isOpened = false
	end)

	-- Listen for real-time profile data changes
	dataChangedEvent.OnClientEvent:Connect(function(key: unknown, value: unknown)
		if key == "Gold" and typeof(value) == "number" then
			localGold = value
			if isOpened then
				runesmithInstance:UpdateGold(localGold)
			end
		elseif key == "OwnedSwords" and typeof(value) == "table" then
			localOwnedSwords = value
			if isOpened then
				runesmithInstance:UpdateSwords(localOwnedSwords, localEquippedUid, localPlacedMap)
			end
		elseif key == "EquippedSword" and typeof(value) == "string" then
			localEquippedUid = value
			if isOpened then
				runesmithInstance:UpdateSwords(localOwnedSwords, localEquippedUid, localPlacedMap)
			end
		elseif key == "PlacedSwords" then
			syncPlacedMap(value)
			if isOpened then
				runesmithInstance:UpdateSwords(localOwnedSwords, localEquippedUid, localPlacedMap)
			end
		elseif key == "OwnedDice" then
			-- Refresh cost dynamically if dice ownership changed
			task.spawn(function()
				local okCost, cost = pcall(function()
					return getBlessingCostFunc:InvokeServer()
				end)
				if okCost and typeof(cost) == "number" then
					localCost = cost
					if isOpened then
						runesmithInstance:UpdateCost(localCost)
					end
				end
			end)
		end
	end)

	-- Fetch initial snapshot
	task.spawn(function()
		local getInitialDataFunc = Remotes.getFunction("GetInitialData")
		local ok, data = pcall(function()
			return getInitialDataFunc:InvokeServer()
		end)
		if ok and typeof(data) == "table" then
			if typeof(data.Gold) == "number" then
				localGold = data.Gold
			end
			if typeof(data.OwnedSwords) == "table" then
				localOwnedSwords = data.OwnedSwords
			end
			if typeof(data.EquippedSword) == "string" then
				localEquippedUid = data.EquippedSword
			end
			if typeof(data.PlacedSwords) == "table" then
				syncPlacedMap(data.PlacedSwords)
			end
		end

		local okCost, cost = pcall(function()
			return getBlessingCostFunc:InvokeServer()
		end)
		if okCost and typeof(cost) == "number" then
			localCost = cost
		end
	end)
end

function RunesmithController.Open()
	if not ui then
		return
	end
	isOpened = true

	local getInitialDataFunc = Remotes.getFunction("GetInitialData")
	local getBlessingCostFunc = Remotes.getFunction("GetBlessingCost")

	local okData, data = pcall(function()
		return getInitialDataFunc:InvokeServer()
	end)
	if okData and typeof(data) == "table" then
		if typeof(data.Gold) == "number" then
			localGold = data.Gold
		end
		if typeof(data.OwnedSwords) == "table" then
			localOwnedSwords = data.OwnedSwords
		end
		if typeof(data.EquippedSword) == "string" then
			localEquippedUid = data.EquippedSword
		end
		if typeof(data.PlacedSwords) == "table" then
			syncPlacedMap(data.PlacedSwords)
		end
	end

	local okCost, cost = pcall(function()
		return getBlessingCostFunc:InvokeServer()
	end)
	if okCost and typeof(cost) == "number" then
		localCost = cost
	end

	ui:Open(localOwnedSwords, localEquippedUid, localPlacedMap, localGold, localCost)
end

function RunesmithController.Close()
	if not ui then
		return
	end
	isOpened = false
	ui:Close()
end

function RunesmithController.IsOpen(): boolean
	return isOpened
end

function RunesmithController.Toggle()
	if isOpened then
		RunesmithController.Close()
	else
		RunesmithController.Open()
	end
end

function RunesmithController.SelectSword(uid: string)
	if ui and isOpened then
		ui:SelectSword(uid)
	end
end

function RunesmithController.ConfirmTierIIIReroll()
	if ui and isOpened then
		ui:ConfirmTierIIIReroll()
	end
end

function RunesmithController.TriggerRollButton()
	if ui and isOpened then
		ui:TriggerRollButton()
	end
end

return RunesmithController
