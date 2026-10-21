--!strict
-- TapController: Connects client tap input to TapService via the Tap remote,
-- and listens for TapResult from the server to spawn floating damage numbers on the HUD.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = Shared:WaitForChild("UI")
local MainHUD = require(UI:WaitForChild("HUD"):WaitForChild("MainHUD"))

type MainHUDInstance = MainHUD.MainHUDInstance

local TapController = {}

local tapEvent: RemoteEvent? = nil
local tapResultEvent: RemoteEvent? = nil

-- Keep track of the most recent tap screen position to spawn the damage number where the player tapped
local lastTapPos: Vector2? = nil

function TapController.Init(hud: MainHUDInstance)
	tapEvent = Remotes.getEvent("Tap")
	tapResultEvent = Remotes.getEvent("TapResult")

	-- Wire tap input from the HUD tap area
	hud:SetOnTap(function(pos: Vector2)
		lastTapPos = pos
		if tapEvent then
			tapEvent:FireServer()
		end
	end)

	-- Listen for verified tap results from the server
	if tapResultEvent then
		tapResultEvent.OnClientEvent:Connect(function(goldEarned: unknown, isCrit: unknown)
			if type(goldEarned) ~= "number" then
				return
			end
			local crit = if type(isCrit) == "boolean" then isCrit else false
			local spawnPos = lastTapPos or Vector2.new(workspace.CurrentCamera.ViewportSize.X / 2, workspace.CurrentCamera.ViewportSize.Y / 2)
			hud:SpawnFloatingNumber(spawnPos, goldEarned, crit)
		end)
	end
end

return TapController
