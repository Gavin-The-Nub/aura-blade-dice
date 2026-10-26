--!strict
-- StationController: Client controller managing world stations tagged "Station".
-- Dynamically discovers stations via CollectionService (handles late replication robustly),
-- ensures exactly one ProximityPrompt per station, and routes interactions to the matching UI.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local Config = ReplicatedStorage:WaitForChild("Config")
local StationsConfig = require(Config:WaitForChild("Stations"))

local Controllers = script.Parent
local MerchantController = require(Controllers:WaitForChild("MerchantController"))
local InventoryController = require(Controllers:WaitForChild("InventoryController"))
local ShopController = require(Controllers:WaitForChild("ShopController"))
local SellStallController = require(Controllers:WaitForChild("SellStallController"))
local AppraiserController = require(Controllers:WaitForChild("AppraiserController"))

local STATION_TAG = "Station"
local MAX_SCAN_RETRIES = 6
local RETRY_INTERVAL_SECONDS = 0.5

local StationController = {}

-- State tracking
local stationPrompts: { [Instance]: ProximityPrompt } = {}
local promptConnections: { [ProximityPrompt]: RBXScriptConnection } = {}
local registeringInProgress: { [Instance]: boolean } = {}
local isInitialized = false

-- Handles when a player triggers a station prompt
local function onStationTriggered(stationType: string)
	if stationType == "Dice" then
		MerchantController.Open()
	elseif stationType == "Sell" then
		SellStallController.Open()
	elseif stationType == "Shop" then
		ShopController.Open()
	elseif stationType == "Appraiser" then
		AppraiserController.Open()
	else
		-- Reserved or future station types (Enchanter, Runesmith)
		print(("[StationController] Station %s triggered (UI coming in a future update)."):format(stationType))
	end
end

-- Robustly finds the target BasePart of a station model
local function getStationBasePart(stationInst: Instance): BasePart?
	if stationInst:IsA("BasePart") then
		return stationInst
	elseif stationInst:IsA("Model") then
		if stationInst.PrimaryPart then
			return stationInst.PrimaryPart
		end
		local base = stationInst:FindFirstChild("Base")
		if base and base:IsA("BasePart") then
			return base
		end
		return stationInst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- Registers and configures a station instance (handles late-replicating children and attributes)
local function registerStation(stationInst: Instance)
	if not stationInst:IsA("Model") and not stationInst:IsA("BasePart") then
		return
	end

	if registeringInProgress[stationInst] then
		return
	end
	registeringInProgress[stationInst] = true

	task.spawn(function()
		-- 1. Resolve StationType attribute (wait briefly if replicating late)
		local stationType = stationInst:GetAttribute("StationType")
		local waitStart = os.clock()
		while not stationType and (os.clock() - waitStart) < 3 do
			task.wait(0.1)
			stationType = stationInst:GetAttribute("StationType")
		end

		if typeof(stationType) ~= "string" then
			registeringInProgress[stationInst] = nil
			return
		end

		local def = StationsConfig.AllStations[stationType :: any]
		if not def then
			registeringInProgress[stationInst] = nil
			return
		end

		-- 2. Wait for base part if not yet replicated
		local targetPart = getStationBasePart(stationInst)
		local partWaitStart = os.clock()
		while not targetPart and (os.clock() - partWaitStart) < 3 do
			task.wait(0.1)
			targetPart = getStationBasePart(stationInst)
		end

		if not targetPart then
			registeringInProgress[stationInst] = nil
			return
		end

		-- 3. Check for existing prompt or wait briefly for server prompt to replicate
		local prompt = stationPrompts[stationInst]
			or stationInst:FindFirstChildWhichIsA("ProximityPrompt", true)

		local promptWaitStart = os.clock()
		while not prompt and (os.clock() - promptWaitStart) < 1 do
			task.wait(0.1)
			prompt = stationInst:FindFirstChildWhichIsA("ProximityPrompt", true)
		end

		if prompt then
			-- Reuse existing prompt, update texts from config
			prompt.ActionText = def.ActionText
			prompt.ObjectText = def.ObjectText
		else
			-- Fallback: create prompt on client only if none replicated
			local newPrompt = Instance.new("ProximityPrompt")
			newPrompt.Name = "StationPrompt"
			newPrompt.ActionText = def.ActionText
			newPrompt.ObjectText = def.ObjectText
			newPrompt.HoldDuration = StationsConfig.PromptDefaults.HoldDuration
			newPrompt.RequiresLineOfSight = StationsConfig.PromptDefaults.RequiresLineOfSight
			newPrompt.MaxActivationDistance = StationsConfig.PromptDefaults.MaxActivationDistance
			newPrompt.Parent = targetPart
			prompt = newPrompt
		end

		stationPrompts[stationInst] = prompt

		-- 4. Connect Triggered exactly once per prompt
		if not promptConnections[prompt] then
			local connection = prompt.Triggered:Connect(function(triggerPlayer: Player)
				if triggerPlayer == localPlayer then
					onStationTriggered(stationType)
				end
			end)
			promptConnections[prompt] = connection
		end

		registeringInProgress[stationInst] = nil
	end)
end

-- Cleans up tracking and disconnects connections when a station is removed
local function unregisterStation(stationInst: Instance)
	registeringInProgress[stationInst] = nil
	local prompt = stationPrompts[stationInst]
	if prompt then
		local conn = promptConnections[prompt]
		if conn then
			conn:Disconnect()
			promptConnections[prompt] = nil
		end
		stationPrompts[stationInst] = nil
	end
end

function StationController.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	-- Listen for stations added or removed dynamically via CollectionService
	CollectionService:GetInstanceAddedSignal(STATION_TAG):Connect(registerStation)
	CollectionService:GetInstanceRemovedSignal(STATION_TAG):Connect(unregisterStation)

	-- Initial scan with limited retries to handle late replication gracefully
	task.spawn(function()
		local retries = 0
		while retries < MAX_SCAN_RETRIES do
			local tagged = CollectionService:GetTagged(STATION_TAG)
			if #tagged > 0 then
				local allConfigured = true
				for _, inst in tagged do
					if not stationPrompts[inst] then
						registerStation(inst)
						allConfigured = false
					end
				end
				if allConfigured then
					return
				end
			end
			retries += 1
			task.wait(RETRY_INTERVAL_SECONDS)
		end

		-- Check one final time after retries
		local finalTagged = CollectionService:GetTagged(STATION_TAG)
		if #finalTagged == 0 then
			warn("[StationController] No stations found after initial scan retries; awaiting replication.")
		else
			for _, inst in finalTagged do
				if not stationPrompts[inst] then
					registerStation(inst)
				end
			end
		end
	end)
end

return StationController
