--!strict
-- MerchantController: Client controller syncing DiceTier, OwnedDice, and Gold with server,
-- handling purchase and equip actions via BuyDice and EquipDice remotes, and managing MerchantUI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = Shared:WaitForChild("UI")
local MerchantUI = require(UI:WaitForChild("MerchantUI"))

local MerchantController = {}

local currentDiceTier: number = 1
local currentGold: number = 0
local ownedDice: { [string]: boolean } = { ["1"] = true }
local uiInstance: MerchantUI.MerchantUIInstance? = nil

local function refreshUI()
	if uiInstance then
		uiInstance:SetData(currentDiceTier, currentGold, ownedDice)
	end
end

function MerchantController.Open()
	if uiInstance then
		uiInstance:Open()
	end
end

function MerchantController.Close()
	if uiInstance then
		uiInstance:Close()
	end
end

function MerchantController.Toggle()
	if uiInstance then
		uiInstance:Toggle()
	end
end

function MerchantController.Init()
	if uiInstance then
		return
	end

	uiInstance = MerchantUI.new(playerGui)

	-- Handle purchase request
	uiInstance:SetOnBuy(function(targetTier: number)
		task.spawn(function()
			local buyFunc = Remotes.getFunction("BuyDice")
			local ok, success, err = pcall(function()
				return buyFunc:InvokeServer(targetTier)
			end)
			if not ok or not success then
				warn("[MerchantController] BuyDice failed: " .. tostring(err or "Unknown error"))
			end
		end)
	end)

	-- Handle equip request
	uiInstance:SetOnEquip(function(targetTier: number)
		task.spawn(function()
			local equipFunc = Remotes.getFunction("EquipDice")
			local ok, success, err = pcall(function()
				return equipFunc:InvokeServer(targetTier)
			end)
			if not ok or not success then
				warn("[MerchantController] EquipDice failed: " .. tostring(err or "Unknown error"))
			end
		end)
	end)

	-- Sync on real-time DataChanged from server
	local dataChangedRemote = Remotes.getEvent("DataChanged")
	dataChangedRemote.OnClientEvent:Connect(function(key: unknown, value: unknown)
		if key == "DiceTier" and type(value) == "number" then
			currentDiceTier = value
			refreshUI()
		elseif key == "OwnedDice" and type(value) == "table" then
			ownedDice = value :: { [string]: boolean }
			refreshUI()
		elseif key == "Gold" and type(value) == "number" then
			currentGold = value
			refreshUI()
		end
	end)

	-- Fetch initial player data
	task.spawn(function()
		local getInitialDataFunc = Remotes.getFunction("GetInitialData")
		local ok, data = pcall(function()
			return getInitialDataFunc:InvokeServer()
		end)
		if ok and type(data) == "table" then
			if type(data.DiceTier) == "number" then
				currentDiceTier = data.DiceTier
			end
			if type(data.OwnedDice) == "table" then
				ownedDice = data.OwnedDice
			end
			if type(data.Gold) == "number" then
				currentGold = data.Gold
			end
			refreshUI()
		end
	end)
end

return MerchantController
