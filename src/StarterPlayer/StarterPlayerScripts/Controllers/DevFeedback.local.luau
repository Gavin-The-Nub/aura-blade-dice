--!strict
-- Shows Studio-only dev command replies (see DevCommands service) in the chat window.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local channels = TextChatService:WaitForChild("TextChannels")
local systemChannel = channels:WaitForChild("RBXSystem") :: TextChannel

Remotes.getEvent("DevMessage").OnClientEvent:Connect(function(text: unknown)
	if type(text) == "string" then
		systemChannel:DisplaySystemMessage(text)
	end
end)
