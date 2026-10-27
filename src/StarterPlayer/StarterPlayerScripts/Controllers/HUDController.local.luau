--!strict
-- HUDController: mounts the main HUD, connects DataChanged remotes, and binds tap feedback.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = Shared:WaitForChild("UI")
local MainHUD = require(UI:WaitForChild("HUD"):WaitForChild("MainHUD"))

-- Initialize and mount HUD
local hud = MainHUD.new(playerGui)

-- Listen for real-time data changes from the server
local dataChangedRemote = Remotes.getEvent("DataChanged")
dataChangedRemote.OnClientEvent:Connect(function(key: unknown, value: unknown)
	if key == "Gold" and type(value) == "number" then
		hud:UpdateGold(value)
	elseif key == "Gems" and type(value) == "number" then
		hud:UpdateGems(value)
	elseif key == "EnchantTokens" and type(value) == "number" then
		hud:UpdateTokens(value)
	end
end)

-- Fetch initial player data
task.spawn(function()
	local getInitialDataFunc = Remotes.getFunction("GetInitialData")
	local ok, data = pcall(function()
		return getInitialDataFunc:InvokeServer()
	end)
	if ok and type(data) == "table" then
		if type(data.Gold) == "number" then
			hud:UpdateGold(data.Gold)
		end
		if type(data.Gems) == "number" then
			hud:UpdateGems(data.Gems)
		end
		if type(data.EnchantTokens) == "number" then
			hud:UpdateTokens(data.EnchantTokens)
		end
	end
end)

local Controllers = script.Parent
local TapController = require(Controllers:WaitForChild("TapController"))
local RollController = require(Controllers:WaitForChild("RollController"))
local InventoryController = require(Controllers:WaitForChild("InventoryController"))
local MerchantController = require(Controllers:WaitForChild("MerchantController"))
local PlotController = require(Controllers:WaitForChild("PlotController"))
local TargetDummyController = require(Controllers:WaitForChild("TargetDummyController"))
local ShopController = require(Controllers:WaitForChild("ShopController"))
local SellStallController = require(Controllers:WaitForChild("SellStallController"))
local StationController = require(Controllers:WaitForChild("StationController"))
local AppraiserController = require(Controllers:WaitForChild("AppraiserController"))
local EnchanterController = require(Controllers:WaitForChild("EnchanterController"))

-- Initialize controllers with the HUD instance
TapController.Init(hud)
RollController.Init(hud)
InventoryController.Init()
MerchantController.Init()
PlotController.Init()
TargetDummyController.Init()
ShopController.Init()
SellStallController.Init()
StationController.Init()
AppraiserController.Init(playerGui)
EnchanterController.Init(playerGui)

hud:SetOnBackpack(function()
	InventoryController.Toggle()
end)

hud:SetOnDice(function()
	MerchantController.Toggle()
end)

