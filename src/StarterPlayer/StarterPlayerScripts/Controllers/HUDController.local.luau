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
	end
end)

-- Fetch initial player data
task.spawn(function()
	local getInitialDataFunc = Remotes.getFunction("GetInitialData")
	local ok, data = pcall(function()
		return getInitialDataFunc:InvokeServer()
	end)
	if ok and type(data) == "table" and type(data.Gold) == "number" then
		hud:UpdateGold(data.Gold)
	end
end)

local Controllers = script.Parent
local TapController = require(Controllers:WaitForChild("TapController"))
local RollController = require(Controllers:WaitForChild("RollController"))

-- Initialize controllers with the HUD instance
TapController.Init(hud)
RollController.Init(hud)

