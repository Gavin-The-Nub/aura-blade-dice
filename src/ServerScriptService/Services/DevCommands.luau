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
local RollService = require(ServerScriptService.Services.RollService)
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

local function onRollTestCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local arg = unfilteredText:match("^%S+%s+(%S+)")
	local count = tonumber(arg) or 500
	if count <= 0 then
		count = 500
	end

	local sim = RollService.SimulateRolls(player, count)

	print(("[DevCommands] ====== Roll Distribution Test (%d Rolls, Luck: %.1fx) ======"):format(sim.Count, sim.TotalLuck))
	for _, rarity in { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" } do
		local c = sim.CountsByRarity[rarity] or 0
		local exp = (sim.ExpectedRarity[rarity] or 0) * 100
		local actual = (c / sim.Count) * 100
		if c > 0 or exp > 0.001 then
			print(("[DevCommands] %-10s : %5d (%6.2f%%) | Expected: %6.2f%%"):format(rarity, c, actual, exp))
		end
	end
	print("[DevCommands] ===============================================================")

	say(player, ("[RollTest] Ran %d rolls (Luck: %.1fx). Rarity distribution printed to Output!"):format(sim.Count, sim.TotalLuck))
end

local function onClearSwordsCommand(originTextSource: TextSource, _unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	DataService.Set(player, "OwnedSwords", {})
	DataService.Set(player, "EquippedSword", "")
	say(player, "Swords cleared and unequipped!")
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

	local rollTestCommand = Instance.new("TextChatCommand")
	rollTestCommand.Name = "DevRollTestCommand"
	rollTestCommand.PrimaryAlias = "/rolltest"
	rollTestCommand.Triggered:Connect(onRollTestCommand)
	rollTestCommand.Parent = TextChatService

	local clearSwordsCommand = Instance.new("TextChatCommand")
	clearSwordsCommand.Name = "DevClearSwordsCommand"
	clearSwordsCommand.PrimaryAlias = "/clearswords"
	clearSwordsCommand.Triggered:Connect(onClearSwordsCommand)
	clearSwordsCommand.Parent = TextChatService
end

return DevCommands
