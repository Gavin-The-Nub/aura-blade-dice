--!strict
-- SellStallController: Client controller managing the Sell Stall UI lifecycle,
-- requesting Sell All previews with snapshot tokens, invoking the SellAll remote,
-- and debouncing auto-refreshes when OwnedSwords change.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = Shared:WaitForChild("UI")
local SellStallUI = require(UI:WaitForChild("SellStallUI"))

local Controllers = script.Parent

local SellStallController = {}

local uiInstance: SellStallUI.SellStallUIInstance? = nil
local latestToken: string = ""
local lastAutoRefreshTime = 0
local autoRefreshDebounceTask: thread? = nil

local function requestPreview()
	if not uiInstance then
		return
	end
	task.spawn(function()
		local getPreviewFunc = Remotes.getFunction("GetSellAllPreview")
		local ok, success, data, errMsg = pcall(function()
			return getPreviewFunc:InvokeServer()
		end)
		if uiInstance then
			if ok and success and typeof(data) == "table" then
				latestToken = if typeof(data.token) == "string" then data.token else ""
				uiInstance:SetPreviewData({
					count = data.count or 0,
					totalGold = data.totalGold or 0,
					gradedOrEnchantedCount = data.gradedOrEnchantedCount or 0,
					token = latestToken,
				})
			else
				uiInstance:ShowResult(tostring(errMsg or "Failed to load sell preview."), false)
			end
		end
	end)
end

local function executeSellAll()
	if not uiInstance then
		return
	end
	uiInstance:SetBusy(true)

	local tokenToSend = latestToken
	task.spawn(function()
		local sellAllFunc = Remotes.getFunction("SellAll")
		local ok, success, soldCount, goldEarned, errMsg = pcall(function()
			return sellAllFunc:InvokeServer(tokenToSend)
		end)

		if uiInstance then
			uiInstance:SetBusy(false)
			if ok and success then
				uiInstance:ShowResult(
					("Successfully sold %d sword(s) for +%s Gold!"):format(
						soldCount or 0,
						tostring(goldEarned or 0)
					),
					true
				)
				-- Refresh preview after sale
				requestPreview()
			else
				uiInstance:ShowResult(tostring(errMsg or "Sell All failed."), false)
				requestPreview()
			end
		end
	end)
end

-- Debounced automatic refresh when OwnedSwords changes:
-- Only while panel is open, not while confirmation is open, debounced to at most once per 2s.
local function scheduleAutoRefresh()
	if not uiInstance or not uiInstance:IsOpen() or uiInstance:IsConfirmOpen() then
		return
	end

	local now = os.clock()
	local elapsed = now - lastAutoRefreshTime
	if elapsed >= 2 then
		lastAutoRefreshTime = now
		if autoRefreshDebounceTask then
			task.cancel(autoRefreshDebounceTask)
			autoRefreshDebounceTask = nil
		end
		requestPreview()
	elseif not autoRefreshDebounceTask then
		autoRefreshDebounceTask = task.delay(2 - elapsed, function()
			autoRefreshDebounceTask = nil
			if uiInstance and uiInstance:IsOpen() and not uiInstance:IsConfirmOpen() then
				lastAutoRefreshTime = os.clock()
				requestPreview()
			end
		end)
	end
end

function SellStallController.Open()
	if uiInstance then
		uiInstance:Open()
	end
end

function SellStallController.Close()
	if uiInstance then
		uiInstance:Close()
	end
end

function SellStallController.Toggle()
	if uiInstance then
		uiInstance:Toggle()
	end
end

function SellStallController.Init()
	if uiInstance then
		return
	end

	uiInstance = SellStallUI.new(playerGui)

	uiInstance:SetOnRequestPreview(requestPreview)
	uiInstance:SetOnConfirmSellAll(executeSellAll)

	uiInstance:SetOnOpenAutoSell(function()
		local InventoryController = require(Controllers:WaitForChild("InventoryController"))
		InventoryController.OpenAutoSell()
	end)

	-- Auto-refresh preview if inventory data changes while the panel is visible and not in confirmation
	local dataChangedRemote = Remotes.getEvent("DataChanged")
	dataChangedRemote.OnClientEvent:Connect(function(key: unknown)
		if key == "OwnedSwords" then
			scheduleAutoRefresh()
		end
	end)
end

return SellStallController
