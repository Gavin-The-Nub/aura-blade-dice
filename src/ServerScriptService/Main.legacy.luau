--!strict
-- Starts every service. Keep this thin: all logic lives in the Services modules.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local servicesFolder = ServerScriptService:WaitForChild("Services")

-- Create all RemoteEvents/RemoteFunctions before any service runs
Remotes.init()

local started = 0
for _, child in servicesFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		-- pcall so one broken service can't stop the others from starting
		local ok, result = pcall(function()
			local service = require(child) :: any
			if type(service) == "table" and type(service.Start) == "function" then
				service.Start()
			end
		end)
		if ok then
			started += 1
		else
			warn(("Service %s failed to start: %s"):format(child.Name, tostring(result)))
		end
	end
end

print(("[Main] %d service(s) loaded"):format(started))
