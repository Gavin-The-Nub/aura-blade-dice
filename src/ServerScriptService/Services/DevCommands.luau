--!strict
-- Studio-only test commands. Does nothing in a live game; delete this file before launch.
--   /gold 500    sets your Gold to 500
--   /gold +250   adds 250 Gold
--   /gold +0     just shows your current Gold
-- Results are sent back to your chat window (and printed to server Output).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")

local DataService = require(ServerScriptService.Services.DataService)
local TapService = require(ServerScriptService.Services.TapService)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DevCommands = {}

-- The command runs on the server, so chat can't show our reply by itself;
-- DevFeedback (client) displays whatever text we send here.
local function say(player: Player, text: string)
	print("[DevCommands] " .. text)
	Remotes.getEvent("DevMessage"):FireClient(player, text)
end

local function onGoldCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local arg = unfilteredText:match("^%S+%s+(%S+)")
	local amount = tonumber(arg)
	if arg == nil or amount == nil then
		say(player, "Usage: /gold <amount>  or  /gold +<amount>")
		return
	end

	local ok
	if arg:sub(1, 1) == "+" then
		ok = DataService.Increment(player, "Gold", amount)
	else
		ok = DataService.Set(player, "Gold", amount)
	end

	local gold = DataService.Get(player, "Gold")
	if ok and type(gold) == "number" then
		say(player, ("Gold is now %s (%d)"):format(NumberFormat.format(gold), gold))
	else
		say(player, "/gold rejected (data not loaded yet, or invalid value)")
	end
end

local function onFeverCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local arg = unfilteredText:match("^%S+%s+(%S+)")
	local amount = tonumber(arg)
	if amount == nil then
		TapService.TriggerFever(player)
		say(player, "Fever Mode triggered for 15s!")
	else
		TapService.SetFeverPoints(player, amount)
		say(player, ("Fever points set to %d"):format(amount))
	end
end

function DevCommands.Start()
	if not RunService:IsStudio() then
		return
	end

	local goldCommand = Instance.new("TextChatCommand")
	goldCommand.Name = "DevGoldCommand"
	goldCommand.PrimaryAlias = "/gold"
	goldCommand.Triggered:Connect(onGoldCommand)
	goldCommand.Parent = TextChatService

	local feverCommand = Instance.new("TextChatCommand")
	feverCommand.Name = "DevFeverCommand"
	feverCommand.PrimaryAlias = "/fever"
	feverCommand.Triggered:Connect(onFeverCommand)
	feverCommand.Parent = TextChatService
end

return DevCommands
