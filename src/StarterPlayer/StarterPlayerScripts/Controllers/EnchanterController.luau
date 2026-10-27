--!strict
-- EnchanterController: Client controller managing Enchanter UI,
-- invoking RollEnchant, StartAutoEnchant, StopAutoEnchant remotes, and throttling live progress updates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = Shared:WaitForChild("UI")
local EnchanterUI = require(UI:WaitForChild("EnchanterUI"))

type EnchanterUIInstance = EnchanterUI.EnchanterUIInstance

local EnchanterController = {}

local ui: EnchanterUIInstance? = nil
local isOpened = false
local isAutoRolling = false

-- Local cached data
local localOwnedSwords: { any } = {}
local localEquippedUid = ""
local localPlacedMap: { [string]: boolean } = {}
local localTokens = 0

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

function EnchanterController.Init(playerGui: Instance?)
	local guiParent = playerGui or player:WaitForChild("PlayerGui")
	local enchanterInstance = EnchanterUI.new(guiParent)
	ui = enchanterInstance

	-- Remote bindings
	local rollEnchantFunc = Remotes.getFunction("RollEnchant")
	local startAutoEnchantFunc = Remotes.getFunction("StartAutoEnchant")
	local stopAutoEnchantFunc = Remotes.getFunction("StopAutoEnchant")
	local autoProgressEvent = Remotes.getEvent("AutoEnchantProgress")
	local dataChangedEvent = Remotes.getEvent("DataChanged")

	-- Handle manual roll
	enchanterInstance:SetOnRoll(function(uid: string)
		if isAutoRolling then
			return
		end
		task.spawn(function()
			local ok, success, oldEnchant, newEnchant, remainingTokens, errMsg = pcall(function()
				return rollEnchantFunc:InvokeServer(uid)
			end)
			if ok and success and newEnchant then
				enchanterInstance:ShowRollResult(oldEnchant or "", newEnchant)
				if remainingTokens then
					localTokens = remainingTokens
					enchanterInstance:UpdateTokens(localTokens)
				end
			elseif not ok or not success then
				warn(("[EnchanterController] Roll failed: %s"):format(tostring(errMsg or success)))
			end
		end)
	end)

	-- Handle start auto enchant
	enchanterInstance:SetOnStartAuto(function(uid: string, targetEnchant: string, maxTokens: number?)
		if isAutoRolling then
			return
		end
		isAutoRolling = true
		task.spawn(function()
			local ok, success, errMsg = pcall(function()
				return startAutoEnchantFunc:InvokeServer(uid, targetEnchant, maxTokens)
			end)
			if not ok or not success then
				isAutoRolling = false
				warn(("[EnchanterController] StartAutoEnchant failed: %s"):format(tostring(errMsg or success)))
				enchanterInstance:UpdateAutoProgress(0, 0, "", false, errMsg or "Could not start")
			end
		end)
	end)

	-- Handle stop auto enchant
	enchanterInstance:SetOnStopAuto(function()
		task.spawn(function()
			pcall(function()
				stopAutoEnchantFunc:InvokeServer()
			end)
			isAutoRolling = false
		end)
	end)

	-- Stop auto roll when closing modal
	enchanterInstance:SetOnClose(function()
		isOpened = false
		isAutoRolling = false
		task.spawn(function()
			pcall(function()
				stopAutoEnchantFunc:InvokeServer()
			end)
		end)
	end)

	-- Throttled AutoEnchantProgress listener
	autoProgressEvent.OnClientEvent:Connect(function(
		uid: unknown,
		rollsDone: unknown,
		tokensSpent: unknown,
		lastEnchant: unknown,
		isRunning: unknown,
		stopReason: unknown
	)
		local rolls = if typeof(rollsDone) == "number" then rollsDone else 0
		local tokens = if typeof(tokensSpent) == "number" then tokensSpent else 0
		local enchant = if typeof(lastEnchant) == "string" then lastEnchant else ""
		local running = (isRunning == true)
		local reason = if typeof(stopReason) == "string" then stopReason else nil

		isAutoRolling = running

		local now = os.clock()
		-- Always deliver terminal states immediately; throttle active rolling states
		if not running or (now - lastProgressUpdateTime >= PROGRESS_THROTTLE_SECONDS) then
			lastProgressUpdateTime = now
			enchanterInstance:UpdateAutoProgress(rolls, tokens, enchant, running, reason)
		end
	end)

	-- DataChanged updates
	dataChangedEvent.OnClientEvent:Connect(function(key: unknown, value: unknown)
		if key == "EnchantTokens" and typeof(value) == "number" then
			localTokens = value
			enchanterInstance:UpdateTokens(localTokens)
		elseif key == "OwnedSwords" and typeof(value) == "table" then
			localOwnedSwords = value
			if isOpened then
				enchanterInstance:UpdateSwords(localOwnedSwords, localEquippedUid, localPlacedMap)
			end
		elseif key == "EquippedSword" and typeof(value) == "string" then
			localEquippedUid = value
			if isOpened then
				enchanterInstance:UpdateSwords(localOwnedSwords, localEquippedUid, localPlacedMap)
			end
		elseif key == "PlacedSwords" then
			syncPlacedMap(value)
			if isOpened then
				enchanterInstance:UpdateSwords(localOwnedSwords, localEquippedUid, localPlacedMap)
			end
		end
	end)

	-- Fetch initial snapshot
	task.spawn(function()
		local getInitialDataFunc = Remotes.getFunction("GetInitialData")
		local ok, data = pcall(function()
			return getInitialDataFunc:InvokeServer()
		end)
		if ok and typeof(data) == "table" then
			if typeof(data.EnchantTokens) == "number" then
				localTokens = data.EnchantTokens
				enchanterInstance:UpdateTokens(localTokens)
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

function EnchanterController.Open()
	if not ui then
		return
	end
	isOpened = true
	ui:Open(localOwnedSwords, localEquippedUid, localPlacedMap, localTokens)
end

function EnchanterController.Close()
	if not ui then
		return
	end
	isOpened = false
	isAutoRolling = false
	task.spawn(function()
		local stopAutoEnchantFunc = Remotes.getFunction("StopAutoEnchant")
		pcall(function()
			stopAutoEnchantFunc:InvokeServer()
		end)
	end)
	ui:Close()
end

function EnchanterController.IsOpen(): boolean
	return isOpened
end

function EnchanterController.Toggle()
	if isOpened then
		EnchanterController.Close()
	else
		EnchanterController.Open()
	end
end

return EnchanterController
