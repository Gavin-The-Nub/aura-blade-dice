--!strict
-- AppraiserController: Client controller managing Master Appraiser UI,
-- invoking RollGrade, StartAutoGrade, StopAutoGrade remotes, and throttling live progress updates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = Shared:WaitForChild("UI")
local AppraiserUI = require(UI:WaitForChild("AppraiserUI"))

type AppraiserUIInstance = AppraiserUI.AppraiserUIInstance

local AppraiserController = {}

local ui: AppraiserUIInstance? = nil
local isOpened = false
local isAutoRolling = false

-- Local cached data
local localOwnedSwords: { any } = {}
local localEquippedUid = ""
local localPlacedMap: { [string]: boolean } = {}
local localGems = 0

-- Progress throttling
local lastProgressUpdateTime = 0
local PROGRESS_THROTTLE_SECONDS = 0.15

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

function AppraiserController.Init(playerGui: Instance?)
	local guiParent = playerGui or player:WaitForChild("PlayerGui")
	local appraiserInstance = AppraiserUI.new(guiParent)
	ui = appraiserInstance

	-- Remote bindings
	local rollGradeFunc = Remotes.getFunction("RollGrade")
	local startAutoGradeFunc = Remotes.getFunction("StartAutoGrade")
	local stopAutoGradeFunc = Remotes.getFunction("StopAutoGrade")
	local autoProgressEvent = Remotes.getEvent("AutoGradeProgress")
	local dataChangedEvent = Remotes.getEvent("DataChanged")

	-- Handle manual roll
	appraiserInstance:SetOnRoll(function(uid: string)
		if isAutoRolling then
			return
		end
		task.spawn(function()
			local ok, success, oldGrade, newGrade, remainingGems, errMsg = pcall(function()
				return rollGradeFunc:InvokeServer(uid)
			end)
			if ok and success and newGrade then
				appraiserInstance:ShowRollResult(oldGrade or "", newGrade)
				if remainingGems then
					localGems = remainingGems
					appraiserInstance:UpdateGems(localGems)
				end
			elseif not ok or not success then
				warn(("[AppraiserController] Roll failed: %s"):format(tostring(errMsg or success)))
			end
		end)
	end)

	-- Handle start auto grade
	appraiserInstance:SetOnStartAuto(function(uid: string, targetGrade: string, maxGems: number?)
		if isAutoRolling then
			return
		end
		isAutoRolling = true
		task.spawn(function()
			local ok, success, errMsg = pcall(function()
				return startAutoGradeFunc:InvokeServer(uid, targetGrade, maxGems)
			end)
			if not ok or not success then
				isAutoRolling = false
				warn(("[AppraiserController] StartAutoGrade failed: %s"):format(tostring(errMsg or success)))
				appraiserInstance:UpdateAutoProgress(0, 0, "", false, errMsg or "Could not start")
			end
		end)
	end)

	-- Handle stop auto grade
	appraiserInstance:SetOnStopAuto(function()
		task.spawn(function()
			pcall(function()
				stopAutoGradeFunc:InvokeServer()
			end)
			isAutoRolling = false
		end)
	end)

	-- Stop auto roll when closing modal
	appraiserInstance:SetOnClose(function()
		isOpened = false
		if isAutoRolling then
			isAutoRolling = false
			task.spawn(function()
				pcall(function()
					stopAutoGradeFunc:InvokeServer()
				end)
			end)
		end
	end)

	-- Throttled AutoGradeProgress listener
	autoProgressEvent.OnClientEvent:Connect(function(
		uid: unknown,
		rollsDone: unknown,
		gemsSpent: unknown,
		lastGrade: unknown,
		isRunning: unknown,
		stopReason: unknown
	)
		local rolls = if typeof(rollsDone) == "number" then rollsDone else 0
		local gems = if typeof(gemsSpent) == "number" then gemsSpent else 0
		local grade = if typeof(lastGrade) == "string" then lastGrade else ""
		local running = (isRunning == true)
		local reason = if typeof(stopReason) == "string" then stopReason else nil

		isAutoRolling = running

		local now = os.clock()
		-- Always deliver terminal states immediately; throttle active rolling states
		if not running or (now - lastProgressUpdateTime >= PROGRESS_THROTTLE_SECONDS) then
			lastProgressUpdateTime = now
			appraiserInstance:UpdateAutoProgress(rolls, gems, grade, running, reason)
		end
	end)

	-- DataChanged updates
	dataChangedEvent.OnClientEvent:Connect(function(key: unknown, value: unknown)
		if key == "Gems" and typeof(value) == "number" then
			localGems = value
			appraiserInstance:UpdateGems(localGems)
		elseif key == "OwnedSwords" and typeof(value) == "table" then
			localOwnedSwords = value
			if isOpened then
				appraiserInstance:UpdateSwords(localOwnedSwords, localEquippedUid, localPlacedMap)
			end
		elseif key == "EquippedSword" and typeof(value) == "string" then
			localEquippedUid = value
			if isOpened then
				appraiserInstance:UpdateSwords(localOwnedSwords, localEquippedUid, localPlacedMap)
			end
		elseif key == "PlacedSwords" and typeof(value) == "table" then
			syncPlacedMap(value)
			if isOpened then
				appraiserInstance:UpdateSwords(localOwnedSwords, localEquippedUid, localPlacedMap)
			end
		end
	end)

	-- Fetch initial snapshot
	task.spawn(function()
		local getInitialFunc = Remotes.getFunction("GetInitialData")
		local ok, data = pcall(function()
			return getInitialFunc:InvokeServer()
		end)
		if ok and typeof(data) == "table" then
			if typeof(data.Gems) == "number" then
				localGems = data.Gems
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
	end)
end

function AppraiserController.Open()
	if not ui then
		return
	end
	isOpened = true
	ui:Open(localOwnedSwords, localEquippedUid, localPlacedMap, localGems)
end

function AppraiserController.Close()
	if not ui then
		return
	end
	isOpened = false
	if isAutoRolling then
		isAutoRolling = false
		task.spawn(function()
			pcall(function()
				local stopAutoGradeFunc = Remotes.getFunction("StopAutoGrade")
				stopAutoGradeFunc:InvokeServer()
			end)
		end)
	end
	ui:Close()
end

function AppraiserController.Toggle()
	if isOpened then
		AppraiserController.Close()
	else
		AppraiserController.Open()
	end
end

return AppraiserController
