--!strict
-- RollController: Connects client roll input to RollService via Roll and ToggleAutoRoll remotes,
-- and routes server RollResults to either the modal Popup (manual roll) or non-blocking Toast (Auto-Roll).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = Shared:WaitForChild("UI")
local MainHUD = require(UI:WaitForChild("HUD"):WaitForChild("MainHUD"))

type MainHUDInstance = MainHUD.MainHUDInstance

local RollController = {}

function RollController.Init(hud: MainHUDInstance)
	local rollEvent = Remotes.getEvent("Roll")
	local toggleAutoRollEvent = Remotes.getEvent("ToggleAutoRoll")
	local rollResultEvent = Remotes.getEvent("RollResult")
	local autoRollStateEvent = Remotes.getEvent("AutoRollStateChanged")

	-- Wire manual Roll button
	hud:SetOnRoll(function()
		rollEvent:FireServer()
	end)

	-- Wire Auto-Roll toggle button
	hud:SetOnAutoRollToggle(function()
		toggleAutoRollEvent:FireServer()
	end)

	-- Listen for Auto-Roll state changes
	autoRollStateEvent.OnClientEvent:Connect(function(isEnabled: unknown)
		if type(isEnabled) == "boolean" then
			hud:SetAutoRollState(isEnabled)
		end
	end)

	-- Listen for verified roll results from the server
	rollResultEvent.OnClientEvent:Connect(function(success: unknown, swordData: unknown, isAuto: unknown, message: unknown)
		local ok = success == true
		local auto = isAuto == true

		if ok and type(swordData) == "table" then
			if auto then
				-- Non-blocking toast for Auto-Roll
				hud:ShowRollToast(swordData, false)
			else
				-- Modal popup for manual roll
				hud:ShowRollPopup(swordData)
			end
		else
			-- Display feedback for rejected roll (e.g. cooldown or inventory full)
			local msg = if type(message) == "string" then message else "Roll could not be completed."
			hud:ShowRollToast(msg, true)
		end
	end)
end

return RollController
