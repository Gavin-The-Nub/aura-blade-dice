--!strict
-- InventoryController: Client controller syncing inventory state with server,
-- handling user actions (Equip, Unequip, Sell, Auto-Sell toggle), and managing InventoryUI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = Shared:WaitForChild("UI")
local InventoryUI = require(UI:WaitForChild("InventoryUI"))

local InventoryController = {}

local ownedSwords: { any } = {}
local equippedSwordUid: string = ""
local autoSellRules: { [string]: boolean } = {}
local uiInstance: InventoryUI.InventoryUIInstance? = nil

local function refreshUI()
	if uiInstance then
		uiInstance:SetData(ownedSwords, equippedSwordUid, autoSellRules)
	end
end

function InventoryController.Open()
	if uiInstance then
		uiInstance:Open()
	end
end

function InventoryController.Close()
	if uiInstance then
		uiInstance:Close()
	end
end

function InventoryController.Toggle()
	if uiInstance then
		uiInstance:Open()
	end
end

function InventoryController.Init()
	if uiInstance then
		return
	end

	uiInstance = InventoryUI.new(playerGui)

	uiInstance:SetOnEquip(function(uid: string)
		task.spawn(function()
			local equipFunc = Remotes.getFunction("EquipSword")
			local ok, success, err = pcall(function()
				return equipFunc:InvokeServer(uid)
			end)
			if not ok or not success then
				warn("[InventoryController] Equip failed: " .. tostring(err or "Unknown error"))
			end
		end)
	end)

	uiInstance:SetOnUnequip(function()
		task.spawn(function()
			local equipFunc = Remotes.getFunction("EquipSword")
			local ok, success, err = pcall(function()
				return equipFunc:InvokeServer("")
			end)
			if not ok or not success then
				warn("[InventoryController] Unequip failed: " .. tostring(err or "Unknown error"))
			end
		end)
	end)

	uiInstance:SetOnSell(function(uid: string)
		task.spawn(function()
			local sellFunc = Remotes.getFunction("SellSword")
			local ok, success, err = pcall(function()
				return sellFunc:InvokeServer(uid)
			end)
			if not ok or not success then
				warn("[InventoryController] Sell failed: " .. tostring(err or "Unknown error"))
			end
		end)
	end)

	uiInstance:SetOnToggleAutoSell(function(rarity: string, enabled: boolean)
		autoSellRules[rarity] = enabled
		refreshUI()
		local toggleEvent = Remotes.getEvent("SetAutoSellRule")
		toggleEvent:FireServer(rarity, enabled)
	end)

	-- Sync on DataChanged
	local dataChangedRemote = Remotes.getEvent("DataChanged")
	dataChangedRemote.OnClientEvent:Connect(function(key: unknown, value: unknown)
		if key == "OwnedSwords" and type(value) == "table" then
			ownedSwords = value :: { any }
			refreshUI()
		elseif key == "EquippedSword" and type(value) == "string" then
			equippedSwordUid = value :: string
			refreshUI()
		elseif key == "AutoSellRules" and type(value) == "table" then
			autoSellRules = value :: { [string]: boolean }
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
			if type(data.OwnedSwords) == "table" then
				ownedSwords = data.OwnedSwords
			end
			if type(data.EquippedSword) == "string" then
				equippedSwordUid = data.EquippedSword
			end
			if type(data.AutoSellRules) == "table" then
				autoSellRules = data.AutoSellRules
			end
			refreshUI()
		end
	end)
end

return InventoryController
