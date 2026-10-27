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
local Grades = require(ReplicatedStorage.Config.Grades)
local Enchants = require(ReplicatedStorage.Config.Enchants)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local EconSim = require(ServerScriptService.EconSim)

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

local function onGemsCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local arg = unfilteredText:match("^%S+%s+(%S+)")
	local amount = tonumber(arg)
	if arg == nil or amount == nil then
		say(player, "Usage: /gems <amount>  or  /gems +<amount>")
		return
	end

	local ok
	if arg:sub(1, 1) == "+" then
		ok = DataService.Increment(player, "Gems", amount)
	else
		ok = DataService.Set(player, "Gems", amount)
	end

	local gems = DataService.Get(player, "Gems")
	if ok and type(gems) == "number" then
		say(player, ("Gems is now %s (%d)"):format(NumberFormat.format(gems), gems))
	else
		say(player, "/gems rejected (data not loaded yet, or invalid value)")
	end
end

local function onSetGradeCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local idxStr, gradeArg = unfilteredText:match("^%S+%s+(%S+)%s*(%S*)")
	local index = tonumber(idxStr)
	if not index or index < 1 then
		say(player, "Usage: /setgrade <inventoryIndex> <grade>")
		return
	end

	local grade = gradeArg or ""
	if grade ~= "" and not Grades.GetGradeDef(grade) then
		say(player, ("Invalid grade '%s'. Valid grades: D, C, B, A, S, SS, SSS, Z, Z+ (or empty string for ungraded)"):format(grade))
		return
	end

	local owned = DataService.Get(player, "OwnedSwords")
	if type(owned) ~= "table" or not owned[index] then
		say(player, ("Inventory index %d out of bounds (you have %d swords)"):format(index, type(owned) == "table" and #owned or 0))
		return
	end

	local updated = table.clone(owned)
	local entry = table.clone(updated[index])
	entry.grade = if grade ~= "" then grade else nil
	updated[index] = entry

	local ok = DataService.Set(player, "OwnedSwords", updated)
	if ok then
		say(player, ("Sword #%d (%s) grade set to: %s"):format(index, entry.id or "sword", if grade ~= "" then grade else "Ungraded"))
	else
		say(player, "/setgrade failed to save.")
	end
end

local function onGradeTestCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local arg = unfilteredText:match("^%S+%s+(%S+)")
	local count = tonumber(arg) or 1000
	if count <= 0 then
		count = 1000
	end

	local counts: { [string]: number } = {}
	for _, def in ipairs(Grades.GetAll()) do
		counts[def.name] = 0
	end

	for _ = 1, count do
		local rolled = Grades.RollRandomGrade()
		counts[rolled.name] = (counts[rolled.name] or 0) + 1
	end

	print(("[DevCommands] ====== Grade Distribution Test (%d Rolls) ======"):format(count))
	say(player, ("[GradeTest] Simulating %d rolls against Config/Grades... (check Output)"):format(count))
	for _, def in ipairs(Grades.GetAll()) do
		local c = counts[def.name] or 0
		local actual = (c / count) * 100
		local exp = def.rollChance
		print(("[DevCommands] Grade %-4s : %6d (%6.2f%%) | Expected: %6.2f%% (x%.2f)"):format(
			def.name,
			c,
			actual,
			exp,
			def.multiplier
		))
	end
end

local function onTokensCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local arg = unfilteredText:match("^%S+%s+(%S+)")
	local amount = tonumber(arg)
	if arg == nil or amount == nil then
		say(player, "Usage: /tokens <amount>  or  /tokens +<amount>")
		return
	end

	local ok
	if arg:sub(1, 1) == "+" then
		ok = DataService.Increment(player, "EnchantTokens", amount)
	else
		ok = DataService.Set(player, "EnchantTokens", amount)
	end

	local tokens = DataService.Get(player, "EnchantTokens")
	if ok and type(tokens) == "number" then
		say(player, ("EnchantTokens is now %s (%d)"):format(NumberFormat.format(tokens), tokens))
	else
		say(player, "/tokens rejected (data not loaded yet, or invalid value)")
	end
end

local function onSetEnchantCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local idxStr, enchantArg = unfilteredText:match("^%S+%s+(%S+)%s*(%S*)")
	local index = tonumber(idxStr)
	if not index or index < 1 then
		say(player, "Usage: /setenchant <inventoryIndex> <enchant>")
		return
	end

	local enchant = enchantArg or ""
	if enchant ~= "" and not Enchants.GetEnchantDef(enchant) then
		say(player, ("Invalid enchant '%s'. Valid enchants: Sharpness, Berserker, Vampiric, Executioner, Ronin, Sovereign, Transcendent, Genesis, Singularity (or empty string for none)"):format(enchant))
		return
	end

	local owned = DataService.Get(player, "OwnedSwords")
	if type(owned) ~= "table" or not owned[index] then
		say(player, ("Inventory index %d out of bounds (you have %d swords)"):format(index, type(owned) == "table" and #owned or 0))
		return
	end

	local updated = table.clone(owned)
	local entry = table.clone(updated[index])
	entry.enchant = if enchant ~= "" then enchant else ""
	updated[index] = entry

	local ok = DataService.Set(player, "OwnedSwords", updated)
	if ok then
		say(player, ("Sword #%d (%s) enchant set to: %s"):format(index, entry.id or "sword", if enchant ~= "" then enchant else "None"))
	else
		say(player, "/setenchant failed to save.")
	end
end

local function onEnchantTestCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local arg = unfilteredText:match("^%S+%s+(%S+)")
	local count = tonumber(arg) or 1000
	if count <= 0 then
		count = 1000
	end

	local counts: { [string]: number } = {}
	for _, def in ipairs(Enchants.GetAll()) do
		counts[def.name] = 0
	end

	for _ = 1, count do
		local rolled = Enchants.RollRandomEnchant()
		counts[rolled.name] = (counts[rolled.name] or 0) + 1
	end

	print(("[DevCommands] ====== Enchant Distribution Test (%d Rolls) ======"):format(count))
	say(player, ("[EnchantTest] Simulating %d rolls against Config/Enchants... (check Output)"):format(count))
	for _, def in ipairs(Enchants.GetAll()) do
		local c = counts[def.name] or 0
		local actual = (c / count) * 100
		local exp = def.rollChance
		print(("[DevCommands] Enchant %-14s : %6d (%6.2f%%) | Expected: %6.2f%% (x%.2f)"):format(
			def.name,
			c,
			actual,
			exp,
			def.multiplier
		))
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
		say(player, ("Dice set to Tier %d (%s | Luck: %sx). Tiers 1..%d marked owned."):format(tier, targetDef.name, NumberFormat.format(targetDef.baseLuck), tier))
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

local function onEconCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local textLower = unfilteredText:lower()

	-- Handle "/econ expected": prints expected multipliers for Grades & Enchants
	if textLower:find("expected") then
		say(player, "[EconSim] Calculating expected multipliers for Grades & Enchants... Results printed to Output!")
		local res = EconSim.PrintExpected(player)
		if res and res.Grades and res.Enchants then
			say(player, ("[EconSim] Expected: 1-roll: Grade %.2fx, Enchant %.2fx (%.1fx combined) | Best-of-100: Grade %.2fx, Enchant %.2fx (%.1fx combined)"):format(
				res.Grades[1] or 0,
				res.Enchants[1] or 0,
				(res.Grades[1] or 0) * (res.Enchants[1] or 0),
				res.Grades[100] or 0,
				res.Enchants[100] or 0,
				(res.Grades[100] or 0) * (res.Enchants[100] or 0)
			))
		end
		return
	end

	local isExtended = textLower:find("extended") ~= nil

	-- Extract scope N if present (e.g. "/econ scope 10")
	local scopeNum: number? = nil
	local scopeMatch = textLower:match("scope%s+(%d+)")
	if scopeMatch then
		scopeNum = tonumber(scopeMatch)
	end

	-- Remove command token, "extended", and "scope %d+" to extract numeric multipliers
	local cleaned = textLower
		:gsub("^%S+", "")
		:gsub("extended", "")
		:gsub("scope%s+%d+", "")

	local args: { number } = {}
	for num in cleaned:gmatch("[%d%.]+") do
		local val = tonumber(num)
		if val then
			table.insert(args, val)
		end
	end

	local goldMult = args[1] or 1.0
	local luckMult = args[2] or 1.0
	local critFeverFactor = args[3] or 1.0

	say(player, ("[EconSim] Running %s simulation (Scope: %s, Gold: %.1fx, Luck: %.1fx, Crit/Fever: %.2fx)... Full tables printed to Output!"):format(
		if isExtended then "extended" else "standard",
		if scopeNum then ("T1.." .. tostring(scopeNum)) else "all",
		goldMult,
		luckMult,
		critFeverFactor
	))

	local report = EconSim.Run(player, goldMult, luckMult, isExtended, scopeNum, critFeverFactor)
	if report then
		say(player, ("[EconSim] Done! Pool runout: %s | Auto-Tap >24h: %s | Exceed Budget A: %s | Exceed Budget B: %s"):format(
			if report.firstPoolRunoutTier then ("T" .. tostring(report.firstPoolRunoutTier)) else "None",
			if report.first24hAutoTapTier then ("T" .. tostring(report.first24hAutoTapTier)) else "None",
			if report.firstExceedBudgetA_Auto then ("T" .. tostring(report.firstExceedBudgetA_Auto)) else "None",
			if report.firstExceedBudgetB_Auto then ("T" .. tostring(report.firstExceedBudgetB_Auto)) else "None"
		))
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

	local econCommand = Instance.new("TextChatCommand")
	econCommand.Name = "DevEconCommand"
	econCommand.PrimaryAlias = "/econ"
	econCommand.Triggered:Connect(onEconCommand)
	econCommand.Parent = TextChatService

	local gemsCommand = Instance.new("TextChatCommand")
	gemsCommand.Name = "DevGemsCommand"
	gemsCommand.PrimaryAlias = "/gems"
	gemsCommand.Triggered:Connect(onGemsCommand)
	gemsCommand.Parent = TextChatService

	local setGradeCommand = Instance.new("TextChatCommand")
	setGradeCommand.Name = "DevSetGradeCommand"
	setGradeCommand.PrimaryAlias = "/setgrade"
	setGradeCommand.Triggered:Connect(onSetGradeCommand)
	setGradeCommand.Parent = TextChatService

	local gradeTestCommand = Instance.new("TextChatCommand")
	gradeTestCommand.Name = "DevGradeTestCommand"
	gradeTestCommand.PrimaryAlias = "/gradetest"
	gradeTestCommand.Triggered:Connect(onGradeTestCommand)
	gradeTestCommand.Parent = TextChatService

	local tokensCommand = Instance.new("TextChatCommand")
	tokensCommand.Name = "DevTokensCommand"
	tokensCommand.PrimaryAlias = "/tokens"
	tokensCommand.Triggered:Connect(onTokensCommand)
	tokensCommand.Parent = TextChatService

	local setEnchantCommand = Instance.new("TextChatCommand")
	setEnchantCommand.Name = "DevSetEnchantCommand"
	setEnchantCommand.PrimaryAlias = "/setenchant"
	setEnchantCommand.Triggered:Connect(onSetEnchantCommand)
	setEnchantCommand.Parent = TextChatService

	local enchantTestCommand = Instance.new("TextChatCommand")
	enchantTestCommand.Name = "DevEnchantTestCommand"
	enchantTestCommand.PrimaryAlias = "/enchanttest"
	enchantTestCommand.Triggered:Connect(onEnchantTestCommand)
	enchantTestCommand.Parent = TextChatService
end

return DevCommands
