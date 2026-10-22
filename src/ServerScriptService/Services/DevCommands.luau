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
local PlotService = require(ServerScriptService.Services.PlotService)
local InventoryService = require(ServerScriptService.Services.InventoryService)
local Dice = require(ReplicatedStorage.Config.Dice)
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
	DataService.Set(player, "PlacedSwords", {})
	say(player, "Swords cleared, unequipped, and removed from pedestals!")
end

local function onDiceCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local arg = unfilteredText:match("^%S+%s+(%S+)")
	local tier = tonumber(arg)
	if arg == nil or tier == nil or tier ~= math.floor(tier) or tier < 1 then
		say(player, "Usage: /dice <tierNumber>  (e.g. /dice 4)")
		return
	end

	local diceMap: { [number]: Dice.DiceDef } = {}
	for _, def in Dice do
		diceMap[def.tier] = def
	end

	local targetDef = diceMap[tier]
	if not targetDef then
		say(player, ("Dice tier %d does not exist in Config (Available: 1 to %d)"):format(tier, #Dice))
		return
	end

	local updatedOwned: { [string]: boolean } = {}
	for t = 1, tier do
		updatedOwned[tostring(t)] = true
	end
	DataService.Set(player, "OwnedDice", updatedOwned)
	local ok = DataService.Set(player, "DiceTier", tier)
	if ok then
		say(player, ("Dice set to Tier %d (%s | Luck: %sx | CD: %.1fs). Tiers 1..%d marked owned."):format(tier, targetDef.name, tostring(targetDef.baseLuck), targetDef.rollCooldown, tier))
	else
		say(player, "/dice rejected (data not loaded yet, or invalid value)")
	end
end

local function onResetDiceCommand(originTextSource: TextSource, _unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	DataService.Set(player, "OwnedDice", { ["1"] = true })
	local ok = DataService.Set(player, "DiceTier", 1)
	if ok then
		say(player, "Dice reset: only Tier 1 (Basic Dice) is owned and equipped.")
	else
		say(player, "/resetdice rejected (data not loaded yet)")
	end
end

local function onPlaceCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local slotStr, invIdxStr = unfilteredText:match("^%S+%s+(%S+)%s+(%S+)")
	local slot = tonumber(slotStr)
	local invIdx = tonumber(invIdxStr)
	if not slot or not invIdx then
		say(player, "Usage: /place <slotIndex> <inventoryIndex> (e.g. /place 1 1)")
		return
	end

	local owned = DataService.Get(player, "OwnedSwords")
	if type(owned) ~= "table" or not owned[invIdx] then
		say(player, ("Inventory sword #%d not found!"):format(invIdx))
		return
	end

	local swordUid = owned[invIdx].uid
	local ok, err = PlotService.PlaceSword(player, slot, swordUid)
	if ok then
		say(player, ("Placed sword '%s' (inv #%d) onto Pedestal Slot #%d!"):format(tostring(owned[invIdx].id), invIdx, slot))
	else
		say(player, "/place failed: " .. tostring(err))
	end
end

local function onUnplaceCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local slotStr = unfilteredText:match("^%S+%s+(%S+)")
	local slot = tonumber(slotStr)
	if not slot then
		say(player, "Usage: /unplace <slotIndex> (e.g. /unplace 1)")
		return
	end

	local ok, err = PlotService.RemoveSword(player, slot)
	if ok then
		say(player, ("Removed sword from Pedestal Slot #%d!"):format(slot))
	else
		say(player, "/unplace failed: " .. tostring(err))
	end
end

local function onFakeOfflineCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local nowArg, hoursArg = unfilteredText:match("^%S+%s+(now)%s+(%S+)")
	if not nowArg then
		hoursArg = unfilteredText:match("^%S+%s+(%S+)")
	end

	local hours = tonumber(hoursArg)
	if not hours or hours <= 0 then
		say(player, "Usage: /fakeoffline <hours> (stage for leave & rejoin) or /fakeoffline now <hours> (simulate immediately)")
		return
	end

	if nowArg == "now" then
		local earned, elapsed = PlotService.SimulateOfflineIncome(player, hours * 3600)
		say(player, ("[FakeOffline] Simulated %s hours offline: Earned %s Gold (%d seconds)."):format(tostring(hours), NumberFormat.format(earned), elapsed))
	else
		DataService.SetMockOfflineHours(player, hours)
		say(player, ("[FakeOffline] Staged %s hours offline for next leave & rejoin. Stop play and rejoin to test offline income calculation!"):format(tostring(hours)))
	end
end

local function onEquipBestCommand(originTextSource: TextSource, _unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local ok, msg = InventoryService.EquipBest(player)
	say(player, msg or (if ok then "Equip Best succeeded!" else "Equip Best failed!"))
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

	local diceCommand = Instance.new("TextChatCommand")
	diceCommand.Name = "DevDiceCommand"
	diceCommand.PrimaryAlias = "/dice"
	diceCommand.Triggered:Connect(onDiceCommand)
	diceCommand.Parent = TextChatService

	local resetDiceCommand = Instance.new("TextChatCommand")
	resetDiceCommand.Name = "DevResetDiceCommand"
	resetDiceCommand.PrimaryAlias = "/resetdice"
	resetDiceCommand.Triggered:Connect(onResetDiceCommand)
	resetDiceCommand.Parent = TextChatService

	local placeCommand = Instance.new("TextChatCommand")
	placeCommand.Name = "DevPlaceCommand"
	placeCommand.PrimaryAlias = "/place"
	placeCommand.Triggered:Connect(onPlaceCommand)
	placeCommand.Parent = TextChatService

	local unplaceCommand = Instance.new("TextChatCommand")
	unplaceCommand.Name = "DevUnplaceCommand"
	unplaceCommand.PrimaryAlias = "/unplace"
	unplaceCommand.Triggered:Connect(onUnplaceCommand)
	unplaceCommand.Parent = TextChatService

	local fakeOfflineCommand = Instance.new("TextChatCommand")
	fakeOfflineCommand.Name = "DevFakeOfflineCommand"
	fakeOfflineCommand.PrimaryAlias = "/fakeoffline"
	fakeOfflineCommand.Triggered:Connect(onFakeOfflineCommand)
	fakeOfflineCommand.Parent = TextChatService

	local equipBestCommand = Instance.new("TextChatCommand")
	equipBestCommand.Name = "DevEquipBestCommand"
	equipBestCommand.PrimaryAlias = "/equipbest"
	equipBestCommand.Triggered:Connect(onEquipBestCommand)
	equipBestCommand.Parent = TextChatService
end

return DevCommands
