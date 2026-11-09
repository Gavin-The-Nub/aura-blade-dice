--!strict
-- TeleportController: Client controller managing Hub, Home, and Shop teleport requests.
-- Closes all open popup dialogs via Popup.CloseAll() before invoking,
-- enforces client-side debounce, and invokes the server-authoritative Teleport remote.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = Shared:WaitForChild("UI")
local Popup = require(UI:WaitForChild("Components"):WaitForChild("Popup"))

local DEBOUNCE_SECONDS = 1.1

local TeleportController = {}

local lastTeleportRequest = 0
local teleportFunction: RemoteFunction? = nil
local activeHud: any = nil

function TeleportController.TeleportTo(destination: string): (boolean, string?)
	local now = os.clock()
	if now - lastTeleportRequest < DEBOUNCE_SECONDS then
		return false, "Please wait before teleporting again."
	end
	lastTeleportRequest = now

	-- Close all currently open popups across the game
	Popup.CloseAll()

	if not teleportFunction then
		teleportFunction = Remotes.getFunction("Teleport")
	end

	local ok, success, errMsg = pcall(function()
		return teleportFunction:InvokeServer(destination)
	end)

	if not ok then
		warn("[TeleportController] Teleport remote error: " .. tostring(success))
		if activeHud and typeof(activeHud.ShowRollToast) == "function" then
			activeHud:ShowRollToast("Teleport failed", true)
		end
		return false, tostring(success)
	end

	if not success and errMsg then
		warn("[TeleportController] Teleport rejected: " .. tostring(errMsg))
		if activeHud and typeof(activeHud.ShowRollToast) == "function" then
			activeHud:ShowRollToast(tostring(errMsg), true)
		end
	end

	return success, errMsg
end

function TeleportController.Init(hud: any?)
	activeHud = hud
	teleportFunction = Remotes.getFunction("Teleport")
end

return TeleportController
