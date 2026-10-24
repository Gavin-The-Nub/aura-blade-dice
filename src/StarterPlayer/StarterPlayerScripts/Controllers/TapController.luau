--!strict
-- TapController: Connects client tap input to TapService via the Tap remote,
-- and listens for TapResult from the server to spawn floating damage numbers on the HUD.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = Shared:WaitForChild("UI")
local MainHUD = require(UI:WaitForChild("HUD"):WaitForChild("MainHUD"))
local TargetDummyController = require(script.Parent:WaitForChild("TargetDummyController"))

type MainHUDInstance = MainHUD.MainHUDInstance

local TapController = {}

local tapEvent: RemoteEvent? = nil
local tapResultEvent: RemoteEvent? = nil

-- Keep track of the most recent tap screen position to spawn the damage number where the player tapped
local lastTapPos: Vector2? = nil

function TapController.Init(hud: MainHUDInstance)
	tapEvent = Remotes.getEvent("Tap")
	tapResultEvent = Remotes.getEvent("TapResult")
	local toggleAutoTapEvent = Remotes.getEvent("ToggleAutoTap")
	local autoTapStateEvent = Remotes.getEvent("AutoTapStateChanged")
	local feverUpdatedEvent = Remotes.getEvent("FeverUpdated")

	-- Wire tap input from the HUD tap area
	hud:SetOnTap(function(pos: Vector2)
		lastTapPos = pos
		if tapEvent then
			tapEvent:FireServer()
		end
	end)

	-- Wire Auto-Tap toggle button
	hud:SetOnAutoTapToggle(function()
		if toggleAutoTapEvent then
			toggleAutoTapEvent:FireServer()
		end
	end)

	-- Listen for Auto-Tap state updates from server
	if autoTapStateEvent then
		autoTapStateEvent.OnClientEvent:Connect(function(isEnabled: unknown)
			if type(isEnabled) == "boolean" then
				hud:SetAutoTapState(isEnabled)
			end
		end)
	end

	-- Listen for Fever meter & mode updates from server
	if feverUpdatedEvent then
		feverUpdatedEvent.OnClientEvent:Connect(function(points: unknown, maxPoints: unknown, isActive: unknown, durationRemaining: unknown)
			local pts = if type(points) == "number" then points else 0
			local maxPts = if type(maxPoints) == "number" then maxPoints else 100
			local active = if type(isActive) == "boolean" then isActive else false
			local duration = if type(durationRemaining) == "number" then durationRemaining else 0
			hud:UpdateFever(pts, maxPts, active, duration)
		end)
	end

	-- Listen for verified tap results from the server
	if tapResultEvent then
		tapResultEvent.OnClientEvent:Connect(function(goldEarned: unknown, isCrit: unknown)
			if type(goldEarned) ~= "number" then
				return
			end
			local crit = if type(isCrit) == "boolean" then isCrit else false

			-- Check if character is near personal target dummy to play 3D reactions instead of 2D HUD number
			local reacted = TargetDummyController.OnTapResult(goldEarned, crit)
			if not reacted then
				local spawnPos = lastTapPos or Vector2.new(workspace.CurrentCamera.ViewportSize.X / 2, workspace.CurrentCamera.ViewportSize.Y / 2)
				hud:SpawnFloatingNumber(spawnPos, goldEarned, crit)
			end
		end)
	end
end

return TapController
