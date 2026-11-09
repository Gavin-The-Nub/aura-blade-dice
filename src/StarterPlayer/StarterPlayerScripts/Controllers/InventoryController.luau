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
local EquipBestWarningPopup = require(UI:WaitForChild("EquipBestWarningPopup"))

local InventoryController = {}

local ownedSwords: { any } = {}
local equippedSwordUid: string = ""
local autoSellRules: { [string]: boolean } = {}
local placedSwords: { [string]: string } = {}
local currentGems: number = 0
local currentTokens: number = 0
local uiInstance: InventoryUI.InventoryUIInstance? = nil

local function refreshUI()
	if uiInstance then
		uiInstance:SetData(ownedSwords, equippedSwordUid, autoSellRules, placedSwords, currentGems, currentTokens)
	end
end

function InventoryController.Open(tab: ("Swords" | "Items")?)
	if uiInstance then
		uiInstance:Open(tab)
	end
end

function InventoryController.Close()
	if uiInstance then
		uiInstance:Close()
	end
end

function InventoryController.Toggle(tab: ("Swords" | "Items")?)
	if uiInstance then
		uiInstance:Open(tab)
	end
end

function InventoryController.OpenTab(tab: "Swords" | "Items")
	if uiInstance then
		uiInstance:Open(tab)
	end
end

function InventoryController.SetItems(gems: number, tokens: number)
	currentGems = gems
	currentTokens = tokens
	if uiInstance then
		uiInstance:SetItemData(currentGems, currentTokens)
	end
end

function InventoryController.OpenAutoSell()
	if uiInstance then
		uiInstance:OpenAutoSell()
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

	uiInstance:SetOnToggleLock(function(uid: string)
		task.spawn(function()
			local lockFunc = Remotes.getFunction("ToggleLock")
			local ok, success, isLocked, err = pcall(function()
				return lockFunc:InvokeServer(uid)
			end)
			if not ok or not success then
				local failMsg = if not ok then "Request failed" else tostring(err or "Failed to toggle lock")
				warn("[InventoryController] ToggleLock failed: " .. failMsg)
				if uiInstance then
					uiInstance:ShowFeedback(failMsg, false)
				end
			end
		end)
	end)

	local warningPopupInstance = EquipBestWarningPopup.new(playerGui)

	uiInstance:SetOnClose(function()
		if warningPopupInstance then
			warningPopupInstance:Close()
		end
	end)

	uiInstance:SetOnToggleAutoSell(function(rarity: string, enabled: boolean)
		autoSellRules[rarity] = enabled
		refreshUI()
		local toggleEvent = Remotes.getEvent("SetAutoSellRule")
		toggleEvent:FireServer(rarity, enabled)
	end)

	uiInstance:SetOnEquipBest(function()
		task.spawn(function()
			if not uiInstance then return end
			uiInstance:SetEquipBestBusy(true)
			local equipBestFunc = Remotes.getFunction("EquipBest")
			local ok, success, msg, data = pcall(function()
				return equipBestFunc:InvokeServer()
			end)

			if not uiInstance then return end
			uiInstance:SetEquipBestBusy(false)

			if not ok then
				uiInstance:ShowEquipBestMessage("Request failed: " .. tostring(msg or "network error"), false)
				return
			end

			if not success then
				uiInstance:ShowEquipBestMessage(tostring(msg or "Failed to equip best swords"), false)
				return
			end

			-- Check if preview requires confirmation
			if type(data) == "table" and data.needsConfirmation == true and data.token and warningPopupInstance then
				warningPopupInstance:Show(data, function(token: string)
					task.spawn(function()
						if not warningPopupInstance then return end
						warningPopupInstance:SetBusy(true)
						local confirmFunc = Remotes.getFunction("ConfirmEquipBest")
						local confirmOk, confirmSuccess, confirmMsg = pcall(function()
							return confirmFunc:InvokeServer(token)
						end)

						if warningPopupInstance then
							warningPopupInstance:SetBusy(false)
							warningPopupInstance:Close()
						end

						if uiInstance then
							if confirmOk then
								uiInstance:ShowEquipBestMessage(tostring(confirmMsg or (if confirmSuccess then "Equipped best swords!" else "Failed to equip")), confirmSuccess)
							else
								uiInstance:ShowEquipBestMessage("Confirm failed: " .. tostring(confirmMsg or "network error"), false)
							end
						end
					end)
				end)
			else
				-- Immediate execution path
				uiInstance:ShowEquipBestMessage(tostring(msg or "Equipped best swords!"), true)
			end
		end)
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
		elseif key == "PlacedSwords" and type(value) == "table" then
			placedSwords = value :: { [string]: string }
			refreshUI()
		elseif key == "AutoSellRules" and type(value) == "table" then
			autoSellRules = value :: { [string]: boolean }
			refreshUI()
		elseif key == "Gems" and type(value) == "number" then
			currentGems = value :: number
			if uiInstance then
				uiInstance:SetItemData(currentGems, currentTokens)
			end
		elseif key == "EnchantTokens" and type(value) == "number" then
			currentTokens = value :: number
			if uiInstance then
				uiInstance:SetItemData(currentGems, currentTokens)
			end
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
			if type(data.PlacedSwords) == "table" then
				placedSwords = data.PlacedSwords
			end
			if type(data.AutoSellRules) == "table" then
				autoSellRules = data.AutoSellRules
			end
			if type(data.Gems) == "number" then
				currentGems = data.Gems
			end
			if type(data.EnchantTokens) == "number" then
				currentTokens = data.EnchantTokens
			end
			refreshUI()
			if uiInstance then
				uiInstance:SetItemData(currentGems, currentTokens)
			end
		end
	end)
end

return InventoryController
