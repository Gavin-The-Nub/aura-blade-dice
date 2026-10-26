--!strict
-- ShopController: Client controller managing the lifecycle of ShopUI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local ShopUI = require(UI:WaitForChild("ShopUI"))

local ShopController = {}

local uiInstance: ShopUI.ShopUIInstance? = nil

function ShopController.Open()
	if uiInstance then
		uiInstance:Open()
	end
end

function ShopController.Close()
	if uiInstance then
		uiInstance:Close()
	end
end

function ShopController.Toggle()
	if uiInstance then
		uiInstance:Toggle()
	end
end

function ShopController.Init()
	if uiInstance then
		return
	end
	uiInstance = ShopUI.new(playerGui)
end

return ShopController
