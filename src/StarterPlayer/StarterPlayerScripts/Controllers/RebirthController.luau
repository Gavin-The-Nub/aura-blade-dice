--!strict
-- RebirthController: Client-side controller orchestrating Rebirth previews,
-- popup modal presentation, and confirmation RPCs with the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local UI = Shared:WaitForChild("UI")
local RebirthPopup = require(UI:WaitForChild("RebirthPopup"))

local popupInstance: RebirthPopup.RebirthPopupInstance? = nil
local isFetchingPreview = false

local RebirthController = {}

function RebirthController.Init(playerGui: Instance)
	if popupInstance then
		return
	end
	popupInstance = RebirthPopup.new(playerGui)
end

function RebirthController.Open()
	if not popupInstance or isFetchingPreview then
		return
	end

	isFetchingPreview = true

	task.spawn(function()
		local getPreviewFunc = Remotes.getFunction("GetRebirthPreview")
		local ok, success, data, errMsg = pcall(function()
			return getPreviewFunc:InvokeServer()
		end)

		isFetchingPreview = false

		if not ok or not success or not data then
			local message = errMsg or "Unable to load rebirth preview. Please try again."
			warn("[RebirthController] Preview failed: " .. tostring(message))
			if popupInstance then
				popupInstance:ShowError(message)
			end
			return
		end

		if not popupInstance then
			return
		end

		popupInstance:Show(data, function(token: string)
			local confirmFunc = Remotes.getFunction("ConfirmRebirth")
			local cOk, cSuccess, result, cErr = pcall(function()
				return confirmFunc:InvokeServer(token)
			end)

			if not popupInstance then
				return
			end

			if cOk and cSuccess and result then
				popupInstance:SetStatus(string.format("Rebirth successful! Now Rebirth %d.", result.newRebirths), false)
				task.delay(1.0, function()
					if popupInstance then
						popupInstance:Close()
					end
				end)
			else
				local failMsg = cErr or "Rebirth execution failed. Please preview again."
				popupInstance:SetBusy(false)
				popupInstance:SetStatus(failMsg, true)
			end
		end)
	end)
end

function RebirthController.Close()
	if popupInstance then
		popupInstance:Close()
	end
end

return RebirthController
