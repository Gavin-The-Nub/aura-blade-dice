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
local WorldTeleportService = require(ServerScriptService.Services.WorldTeleportService)
local Swords = require(ReplicatedStorage.Config.Swords)
local Dice = require(ReplicatedStorage.Config.Dice)
local Grades = require(ReplicatedStorage.Config.Grades)
local Enchants = require(ReplicatedStorage.Config.Enchants)
local Blessings = require(ReplicatedStorage.Config.Blessings)
local BlessingService = require(ServerScriptService.BlessingService)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Config.Game)
local EconSim = require(ServerScriptService.EconSim)
local Rebirths = require(ReplicatedStorage.Config.Rebirths)
local GoldCredit = require(ServerScriptService.GoldCredit)

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

function DevCommands.SetPedSlots(player: Player, slots: number): (boolean, string)
	local maxPedestals = (GameConfig.Plot and GameConfig.Plot.MaxPedestals) or 11
	if slots ~= math.floor(slots) or slots < 1 or slots > maxPedestals then
		local msg = ("Usage: /pedslots <1-%d>"):format(maxPedestals)
		say(player, msg)
		return false, msg
	end

	local updates: { [string]: any } = {
		PedestalSlots = slots,
	}

	-- When lowering, also clear PlacedSwords above slots so no sword stays stuck in a locked slot
	local placed = DataService.Get(player, "PlacedSwords")
	if type(placed) == "table" then
		local cleaned = table.clone(placed)
		local changed = false
		for slotKey, _ in cleaned do
			local sNum = tonumber(slotKey)
			if sNum and sNum > slots then
				cleaned[slotKey] = nil
				changed = true
			end
		end
		if changed then
			updates["PlacedSwords"] = cleaned
		end
	end

	local ok = DataService.SetMany(player, updates)
	if ok then
		local msg = ("PedestalSlots set to %d"):format(slots)
		say(player, msg)
		return true, msg
	else
		local msg = "/pedslots rejected (data not loaded or update failed)"
		say(player, msg)
		return false, msg
	end
end

local function handleRebirthTest(player: Player, arg: string?): (boolean, string)
	if not RunService:IsStudio() then
		local msg = "[DevCommands] /rebirthtest is Studio-only."
		say(player, msg)
		return false, msg
	end

	if arg and arg ~= "" then
		local n = tonumber(arg)
		if not n or n ~= math.floor(n) or n < 0 or n > Rebirths.MaxRebirths then
			local msg = string.format("Usage: /rebirthtest <0-%d>", Rebirths.MaxRebirths)
			say(player, msg)
			return false, msg
		end

		local targetSlots = Rebirths.GetPedestalSlots(n)
		local currentSlots = DataService.Get(player, "PedestalSlots") or Rebirths.BasePedestalSlots
		local newSlots = math.max(currentSlots, targetSlots)

		local ok = DataService.SetMany(player, {
			Rebirths = n,
			PedestalSlots = newSlots,
		})

		if ok then
			local msg = string.format("Rebirths set to %d, PedestalSlots set to %d (No Gems granted)", n, newSlots)
			say(player, msg)
			return true, msg
		else
			local msg = "Failed to update Rebirths/PedestalSlots."
			say(player, msg)
			return false, msg
		end
	else
		-- Print 1-15 table:
		-- cost, multiplier, income gain vs previous rebirth (ratio), and cost divided by (Auto GPS x GetGoldMultiplier(n-1)) as hours
		local gps6 = EconSim.GetTierAutoTapGps(6)
		local gps9 = EconSim.GetTierAutoTapGps(9)
		local gps12 = EconSim.GetTierAutoTapGps(12)

		print(string.rep("=", 120))
		print("  [REBIRTH SCALING TABLE (1-15)]  (PLACEHOLDER)")
		print(string.format("  Reference EconSim Auto GPS: T6=%s (%d/s), T9=%s (%d/s), T12=%s (%d/s)",
			NumberFormat.format(gps6), gps6,
			NumberFormat.format(gps9), gps9,
			NumberFormat.format(gps12), gps12))
		print(string.rep("-", 120))
		print(string.format(
			"%-4s | %-12s | %-6s | %-12s | %-8s | %-8s | %-10s | %-10s | %-10s",
			"Tier", "Gold Cost", "Mult", "Income Gain", "Gems", "Slots", "Hours(T6)", "Hours(T9)", "Hours(T12)"
		))
		print(string.rep("-", 120))

		for i = 1, Rebirths.MaxRebirths do
			local cost = Rebirths.GetCost(i)
			local mult = Rebirths.GetGoldMultiplier(i)
			local prevMult = Rebirths.GetGoldMultiplier(i - 1)
			local incomeGainRatio = if prevMult > 0 then mult / prevMult else mult
			local gems = Rebirths.GetGemsGrant(i)
			local slots = Rebirths.GetPedestalSlots(i)

			local effGps6 = gps6 * prevMult
			local effGps9 = gps9 * prevMult
			local effGps12 = gps12 * prevMult

			local h6 = if effGps6 > 0 then (cost / effGps6) / 3600 else 0
			local h9 = if effGps9 > 0 then (cost / effGps9) / 3600 else 0
			local h12 = if effGps12 > 0 then (cost / effGps12) / 3600 else 0

			print(string.format(
				"%-4d | %-12s | %-6s | %-12s | %-8s | %-8d | %-10.2f | %-10.2f | %-10.2f",
				i,
				NumberFormat.format(cost),
				string.format("%.1fx", mult),
				string.format("%.2fx", incomeGainRatio),
				string.format("+%d", gems),
				slots,
				h6,
				h9,
				h12
			))
		end
		print(string.rep("=", 120))

		local msg = string.format("Printed Rebirth 1-%d table to Output (T6 GPS: %s, T9 GPS: %s, T12 GPS: %s)",
			Rebirths.MaxRebirths,
			NumberFormat.format(gps6),
			NumberFormat.format(gps9),
			NumberFormat.format(gps12))
		say(player, msg)
		return true, msg
	end
end

local function onRebirthTestCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local arg = unfilteredText:match("^%S+%s+(%S+)")
	handleRebirthTest(player, arg)
end

local function onPedSlotsCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local maxPedestals = (GameConfig.Plot and GameConfig.Plot.MaxPedestals) or 11
	local defaultSlots = (GameConfig.Plot and GameConfig.Plot.DefaultPedestalsPerPlot) or 4
	local arg = unfilteredText:match("^%S+%s+(%S+)")
	local slots = tonumber(arg)
	if arg == nil or slots == nil then
		local cur = DataService.Get(player, "PedestalSlots") or defaultSlots
		say(player, ("Current PedestalSlots: %d (Max: %d)"):format(cur, maxPedestals))
		return
	end

	DevCommands.SetPedSlots(player, slots)
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

	local ok, msg = InventoryService.EquipBest(player, true)
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

local function onBlessingCostCommand(originTextSource: TextSource, _unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil or not RunService:IsStudio() then
		return
	end

	print("================================================================================")
	print("[DevCommands] Hilt Blessing Roll Cost Table (Dice Tiers 1 to 12)")
	print("Formula: cost = math.floor(math.max(MinCost, CostFraction * nextTierPrice))")
	print(("Parameters: MinCost = %d Gold, CostFraction = %.4f"):format(Blessings.MinCost, Blessings.CostFraction))
	print("--------------------------------------------------------------------------------")
	print(string.format("%-5s | %-18s | %-16s | %-16s | %-14s", "Tier", "Dice Name", "Dice Cost", "Next Tier Cost", "Blessing Cost"))
	print("--------------------------------------------------------------------------------")

	for tier = 1, 12 do
		local diceDef = Dice[tier]
		local diceName = diceDef and diceDef.name or ("Tier " .. tier)
		local diceCost = diceDef and diceDef.cost or 0
		local cost, targetTier, targetPrice = Blessings.CalculateCost(tier)
		print(string.format("%-5d | %-18s | %-16s | %-16s | %-14s",
			tier,
			diceName,
			NumberFormat.format(diceCost) .. " Gold",
			NumberFormat.format(targetPrice) .. " (T" .. targetTier .. ")",
			NumberFormat.format(cost) .. " Gold"
		))
	end
	print("================================================================================")
	say(player, "[BlessingCost] Printed Dice Tiers 1-12 blessing cost table to Output console.")
end

local function onSetBlessingCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil or not RunService:IsStudio() then
		return
	end

	local idxStr, nameArg = unfilteredText:match("^%S+%s+(%S+)%s+(.+)$")
	local idx = tonumber(idxStr)
	if not idx or not nameArg then
		say(player, "Usage: /setblessing <inventoryIndex> <name|none> (e.g. /setblessing 1 Fortune III)")
		return
	end

	local owned = DataService.Get(player, "OwnedSwords")
	if type(owned) ~= "table" or not owned[idx] then
		say(player, ("Inventory sword #%d not found!"):format(idx))
		return
	end

	local blessingName: string? = nil
	local lower = nameArg:lower():gsub("^%s*(.-)%s*$", "%1")
	if lower == "none" or lower == "clear" or lower == "nil" or lower == "" then
		blessingName = nil
	else
		local foundDef = nil
		for _, def in ipairs(Blessings.List) do
			if def.name:lower() == lower then
				foundDef = def
				break
			end
		end
		if not foundDef then
			say(player, ("Unknown blessing '%s'. Available: Fortune I/II/III, Greed I/II/III, Appraiser's Eye, Enchanter's Soul, Swiftfoot, or none"):format(nameArg))
			return
		end
		blessingName = foundDef.name
	end

	local updated = table.clone(owned)
	local entryClone = table.clone(updated[idx])
	entryClone.blessing = blessingName
	updated[idx] = entryClone

	local ok = DataService.Set(player, "OwnedSwords", updated)
	if ok then
		say(player, ("Set inventory sword #%d ('%s') blessing to '%s'"):format(
			idx,
			entryClone.id,
			blessingName or "none"
		))
	else
		say(player, "/setblessing failed to save.")
	end
end

local function onBlessingTestCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil or not RunService:IsStudio() then
		return
	end

	local arg = unfilteredText:match("^%S+%s+(%S+)")
	local count = tonumber(arg) or 1000
	count = math.clamp(math.floor(count), 1, 100000)

	local counts: { [string]: number } = {}
	for _, def in ipairs(Blessings.List) do
		counts[def.name] = 0
	end

	for _ = 1, count do
		local rolled = Blessings.RollRandomBlessing()
		counts[rolled.name] = (counts[rolled.name] or 0) + 1
	end

	print(("[DevCommands] ====== Blessing Distribution Test (%d Rolls, Studio Only, 0 Gold) ======"):format(count))
	say(player, ("[BlessingTest] Simulating %d rolls against Config/Blessings (0 Gold)... (check Output)"):format(count))
	for _, def in ipairs(Blessings.List) do
		local c = counts[def.name] or 0
		local actual = (c / count) * 100
		print(string.format("  %-18s : %6d rolls (%5.2f%%) | Expected: %5.2f%%", def.name, c, actual, def.rollChance))
	end
	print("================================================================================")
end

local function onLuckCommand(originTextSource: TextSource, _unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil or not RunService:IsStudio() then
		return
	end

	local bonuses = BlessingService.GetBonuses(player)
	local totalSwordLuck = RollService.GetTotalLuck(player)
	local totalGradeLuck = BlessingService.GetGradeLuck(player)
	local totalEnchantLuck = BlessingService.GetEnchantLuck(player)
	local greedMultiplier = BlessingService.GetGreedMultiplier(player)

	local fortuneCap = (Blessings.Caps and Blessings.Caps.FortuneLuck) or 1.0
	local greedCap = (Blessings.Caps and Blessings.Caps.GreedGold) or 1.0
	local gradeCap = (Blessings.Caps and Blessings.Caps.GradeLuck) or 1.0
	local enchantCap = (Blessings.Caps and Blessings.Caps.EnchantLuck) or 1.0
	local swiftWalkCap = (Blessings.Caps and Blessings.Caps.SwiftfootWalk) or 0.5
	local swiftTapCap = (Blessings.Caps and Blessings.Caps.SwiftfootAutoTap) or 0.5

	local baseWalkSpeed = (GameConfig.Player and GameConfig.Player.BaseWalkSpeed) or 16
	local effectiveWalkSpeed = baseWalkSpeed * (1 + bonuses.swiftWalkCapped)
	local baseTapRate = GameConfig.AutoTap.BaseTapsPerSecond
	local feverMultiplier = GameConfig.Fever.SpeedMultiplier
	local effectiveTapRate = baseTapRate * (1 + bonuses.swiftTapCapped)
	local feverTapRate = effectiveTapRate * feverMultiplier

	-- Equipped sword stats breakdown
	local equippedEntry = TapService.GetEquippedEntry(player)
	local equippedId = "Unarmed"
	local baseDamage = GameConfig.Tap.UnarmedDamage
	local gradeMult = 1.0
	local enchantMult = 1.0
	if equippedEntry and typeof(equippedEntry) == "table" then
		equippedId = equippedEntry.id or "sword"
		baseDamage = TapService.GetEquippedDamage(player)
		if typeof(equippedEntry.grade) == "string" then
			gradeMult = Grades.GetMultiplier(equippedEntry.grade)
		end
		if typeof(equippedEntry.enchant) == "string" then
			enchantMult = Enchants.GetMultiplier(equippedEntry.enchant)
		end
	end
	local goldPerTapNoCrit = TapService.CalculateSwordGoldIncome(player, equippedEntry)

	-- Total passive Gold per second
	local placed = DataService.Get(player, "PlacedSwords")
	local owned = DataService.Get(player, "OwnedSwords")
	local rawSlots = DataService.Get(player, "PedestalSlots")
	local defaultSlots = (GameConfig.Plot and GameConfig.Plot.DefaultPedestalsPerPlot) or 4
	local maxSlots = (GameConfig.Plot and GameConfig.Plot.MaxPedestals) or 11
	local pedestalSlots = math.clamp(if typeof(rawSlots) == "number" then rawSlots else defaultSlots, 1, maxSlots)
	local passiveRate = (GameConfig.Plot and GameConfig.Plot.PassiveRateMultiplier) or 0.5
	local totalPassiveGps = 0
	if typeof(placed) == "table" and typeof(owned) == "table" then
		local ownedMap: { [string]: any } = {}
		for _, entry in owned do
			if typeof(entry) == "table" and typeof(entry.uid) == "string" then
				ownedMap[entry.uid] = entry
			end
		end
		for s = 1, pedestalSlots do
			local pUid = placed[tostring(s)]
			if pUid and ownedMap[pUid] then
				local gpt = TapService.CalculateSwordGoldIncome(player, ownedMap[pUid])
				totalPassiveGps += (gpt * passiveRate)
			end
		end
	end

	print("================================================================================")
	print(("[DevCommands] Luck & Blessing Report for %s"):format(player.Name))
	print("--------------------------------------------------------------------------------")
	print(("[Fortune Blessing] Raw: +%.1f%% | Capped: +%.1f%% (Cap: +%.1f%%) | Total Sword Luck: %.2fx"):format(
		bonuses.fortuneRaw * 100,
		bonuses.fortuneCapped * 100,
		fortuneCap * 100,
		totalSwordLuck
	))
	print(("[Greed Blessing]   Raw: +%.1f%% | Capped: +%.1f%% (Cap: +%.1f%%) | Total Gold Multiplier: %.2fx"):format(
		bonuses.greedRaw * 100,
		bonuses.greedCapped * 100,
		greedCap * 100,
		greedMultiplier
	))
	print(("[Grade Blessing]   Raw: +%.1f%% | Capped: +%.1f%% (Cap: +%.1f%%) | Total Grade Luck: %.2fx"):format(
		bonuses.gradeRaw * 100,
		bonuses.gradeCapped * 100,
		gradeCap * 100,
		totalGradeLuck
	))
	print(("[Enchant Blessing] Raw: +%.1f%% | Capped: +%.1f%% (Cap: +%.1f%%) | Total Enchant Luck: %.2fx"):format(
		bonuses.enchantRaw * 100,
		bonuses.enchantCapped * 100,
		enchantCap * 100,
		totalEnchantLuck
	))
	print(("[Swiftfoot Blessing] Raw Walk: +%.1f%% | Capped Walk: +%.1f%% (Cap: +%.1f%%) | WalkSpeed: %.1f studs/s"):format(
		bonuses.swiftWalkRaw * 100,
		bonuses.swiftWalkCapped * 100,
		swiftWalkCap * 100,
		effectiveWalkSpeed
	))
	print(("                     Raw Tap:  +%.1f%% | Capped Tap:  +%.1f%% (Cap: +%.1f%%) | Auto-Tap: %.1f taps/s (Fever: %.1f taps/s)"):format(
		bonuses.swiftTapRaw * 100,
		bonuses.swiftTapCapped * 100,
		swiftTapCap * 100,
		effectiveTapRate,
		feverTapRate
	))
	print("--------------------------------------------------------------------------------")
	print(("[Equipped Sword] %s | Base Damage: %.1f | Grade: %.2fx | Enchant: %.2fx | Greed: %.2fx | Gold per tap (no crit): %.2f"):format(
		equippedId,
		baseDamage,
		gradeMult,
		enchantMult,
		greedMultiplier,
		goldPerTapNoCrit
	))
	print(("[Passive Gold]   Total Passive Gold / Sec: %.2f Gold/s (active pedestals: %d, rate: %.0f%%)"):format(
		totalPassiveGps,
		pedestalSlots,
		passiveRate * 100
	))
	print("--------------------------------------------------------------------------------")
	print("Contributing Blessing Sources:")
	if #bonuses.sources == 0 then
		print("  (None - no blessed swords equipped or placed)")
	else
		for _, src in ipairs(bonuses.sources) do
			print(("  [%s] %s (%s): %s"):format(src.slot, src.swordId, src.uid, src.blessing))
		end
	end
	print("--------------------------------------------------------------------------------")

	-- Rarest 3 Swords (from Config, sorted descending by baseOdds)
	local rollable: { Swords.SwordDef } = {}
	for _, s in Swords do
		if not s.isTest then
			table.insert(rollable, s)
		end
	end
	table.sort(rollable, function(a, b)
		return a.baseOdds > b.baseOdds
	end)
	print(("Effective Odds - Rarest 3 Swords (Total Sword Luck: %.2fx):"):format(totalSwordLuck))
	for i = 1, math.min(3, #rollable) do
		local s = rollable[i]
		local effOdds = math.max(1, s.baseOdds / totalSwordLuck)
		print(("  #%d %-28s | Base: 1 in %-10s | Effective: 1 in %.2f"):format(
			i, s.name, NumberFormat.format(s.baseOdds), effOdds
		))
	end

	-- Rarest 3 Grades (from Config, sorted ascending by rollChance)
	local rarestGrades: { Grades.GradeDef } = table.clone(Grades.GetAll())
	table.sort(rarestGrades, function(a, b)
		return a.rollChance < b.rollChance
	end)
	print(("Effective Odds - Rarest 3 Grades (Total Grade Luck: %.2fx):"):format(totalGradeLuck))
	for i = 1, math.min(3, #rarestGrades) do
		local g = rarestGrades[i]
		local baseOdds = g.baseOdds or (100 / g.rollChance)
		local effOdds = math.max(1, (baseOdds :: number) / totalGradeLuck)
		print(("  #%d Grade %-6s (weight %5.2f%%) | Base Odds: 1 in %-8.2f | Effective: 1 in %.2f"):format(
			i, g.name, g.rollChance, baseOdds, effOdds
		))
	end

	-- Rarest 3 Enchants (from Config, sorted ascending by rollChance)
	local rarestEnchants: { Enchants.EnchantDef } = table.clone(Enchants.GetAll())
	table.sort(rarestEnchants, function(a, b)
		return a.rollChance < b.rollChance
	end)
	print(("Effective Odds - Rarest 3 Enchants (Total Enchant Luck: %.2fx):"):format(totalEnchantLuck))
	for i = 1, math.min(3, #rarestEnchants) do
		local e = rarestEnchants[i]
		local baseOdds = e.baseOdds or (100 / e.rollChance)
		local effOdds = math.max(1, (baseOdds :: number) / totalEnchantLuck)
		print(("  #%d Enchant %-14s (weight %5.2f%%) | Base Odds: 1 in %-8.2f | Effective: 1 in %.2f"):format(
			i, e.name, e.rollChance, baseOdds, effOdds
		))
	end
	print("================================================================================")

	say(player, ("[Luck] Slots: %d | Fortune: +%.1f%% | Greed: +%.1f%% (x%.2f) | Grade: +%.1f%% | Enchant: +%.1f%% | SwiftWalk: +%.1f%% (%.1f spd) | SwiftTap: +%.1f%% (%.1f taps/s) | GPT: %.2f | Passive: %.2f/s"):format(
		pedestalSlots,
		bonuses.fortuneCapped * 100,
		bonuses.greedCapped * 100,
		greedMultiplier,
		bonuses.gradeCapped * 100,
		bonuses.enchantCapped * 100,
		bonuses.swiftWalkCapped * 100,
		effectiveWalkSpeed,
		bonuses.swiftTapCapped * 100,
		effectiveTapRate,
		goldPerTapNoCrit,
		totalPassiveGps
	))
end


local function runGoldCreditTestSuite(player: Player): boolean
	print("================================================================================")
	print("[DevCommands] ====== GoldCredit Simulation & Invariant Test Suite ======")
	print("================================================================================")

	local initialGold = DataService.Get(player, "Gold") or 0
	GoldCredit.Clear(player)

	local allPassed = true

	-- (a) 1000 credits of 1.25 -> exactly 1250 (within 1)
	local goldStartA = DataService.Get(player, "Gold") or 0
	local sumCreditedA = 0
	for _ = 1, 1000 do
		local ok, whole = GoldCredit.Credit(player, 1.25)
		if ok then
			sumCreditedA += whole
		else
			allPassed = false
		end
	end
	local goldEndA = DataService.Get(player, "Gold") or 0
	local deltaA = goldEndA - goldStartA
	local remA = GoldCredit.GetRemainder(player)
	local passA = math.abs(deltaA - 1250) <= 1 and deltaA == sumCreditedA
	if not passA then allPassed = false end
	print(("[Test A: 1000 x 1.25 GPT] %s | Delta Gold: %d (Expected: 1250, within 1) | Remainder: %.4f | Sum Credited: %d"):format(
		if passA then "PASS" else "FAIL", deltaA, remA, sumCreditedA
	))
	print("  -> Old DataService rounding comparison: floor(1.25 + 0.5) paid 1000 Gold (-250 Gold lost bias).")

	GoldCredit.Clear(player)

	-- (b) 60 credits of 10.5 -> exactly 630
	local goldStartB = DataService.Get(player, "Gold") or 0
	local sumCreditedB = 0
	for _ = 1, 60 do
		local ok, whole = GoldCredit.Credit(player, 10.5)
		if ok then
			sumCreditedB += whole
		else
			allPassed = false
		end
	end
	local goldEndB = DataService.Get(player, "Gold") or 0
	local deltaB = goldEndB - goldStartB
	local remB = GoldCredit.GetRemainder(player)
	local passB = math.abs(deltaB - 630) <= 1 and deltaB == sumCreditedB
	if not passB then allPassed = false end
	print(("[Test B: 60 x 10.5 GPS]   %s | Delta Gold: %d (Expected: 630) | Remainder: %.4f | Sum Credited: %d"):format(
		if passB then "PASS" else "FAIL", deltaB, remB, sumCreditedB
	))
	print("  -> Old DataService rounding comparison: floor(10.5 + 0.5) paid 660 Gold (+30 Gold overpayment bias).")

	GoldCredit.Clear(player)

	-- (c) 1000 credits of 12 -> 12000 exactly
	local goldStartC = DataService.Get(player, "Gold") or 0
	local sumCreditedC = 0
	for _ = 1, 1000 do
		local ok, whole = GoldCredit.Credit(player, 12)
		if ok then
			sumCreditedC += whole
		else
			allPassed = false
		end
	end
	local goldEndC = DataService.Get(player, "Gold") or 0
	local deltaC = goldEndC - goldStartC
	local remC = GoldCredit.GetRemainder(player)
	local passC = deltaC == 12000 and deltaC == sumCreditedC and remC == 0
	if not passC then allPassed = false end
	print(("[Test C: 1000 x 12 GPT]   %s | Delta Gold: %d (Expected: 12000) | Remainder: %.4f | Sum Credited: %d"):format(
		if passC then "PASS" else "FAIL", deltaC, remC, sumCreditedC
	))
	print("  -> Old DataService rounding comparison: paid 12000 Gold (identical).")

	GoldCredit.Clear(player)

	-- (d) 1000 credits of 2.5 (an odd-base crit) -> 2500 (within 1), with old rounding result for comparison
	local goldStartD = DataService.Get(player, "Gold") or 0
	local sumCreditedD = 0
	for _ = 1, 1000 do
		local ok, whole = GoldCredit.Credit(player, 2.5)
		if ok then
			sumCreditedD += whole
		else
			allPassed = false
		end
	end
	local goldEndD = DataService.Get(player, "Gold") or 0
	local deltaD = goldEndD - goldStartD
	local remD = GoldCredit.GetRemainder(player)
	local passD = math.abs(deltaD - 2500) <= 1 and deltaD == sumCreditedD
	if not passD then allPassed = false end
	print(("[Test D: 1000 x 2.5 Crit] %s | Delta Gold: %d (Expected: 2500, within 1) | Remainder: %.4f | Sum Credited: %d"):format(
		if passD then "PASS" else "FAIL", deltaD, remD, sumCreditedD
	))
	print("  -> Old DataService rounding comparison: floor(2.5 + 0.5) = 3 per crit -> paid 3000 Gold (+500 Gold overpayment bias).")

	-- (e) Increment failure: use a player whose data is not loaded, remainder stays unchanged and returns false, 0
	GoldCredit.Clear(player)
	GoldCredit.Credit(player, 0.75)
	local playerRemBefore = GoldCredit.GetRemainder(player)
	local unloadedPlayer = Instance.new("Folder") :: any
	unloadedPlayer.Name = "UnloadedTester"
	local okFail, creditedFail = GoldCredit.Credit(unloadedPlayer, 1.25)
	local playerRemAfter = GoldCredit.GetRemainder(player)
	local unloadedRem = GoldCredit.GetRemainder(unloadedPlayer)
	unloadedPlayer:Destroy()

	local passE = (okFail == false) and (creditedFail == 0) and (playerRemBefore == 0.75) and (playerRemAfter == 0.75) and (unloadedRem == 0)
	if not passE then allPassed = false end
	print(("[Test E: Failure Safe]   %s | Unloaded Credit: ok=%s, credited=%d | Real Player Remainder Untouched: %.2f -> %.2f"):format(
		if passE then "PASS" else "FAIL", tostring(okFail), creditedFail, playerRemBefore, playerRemAfter
	))

	-- (f) Invariant: Gold delta == sum of wholeCredited AND nominal total - Gold delta == remainder
	GoldCredit.Clear(player)
	local goldStartF = DataService.Get(player, "Gold") or 0
	local nominalTotalF = 0
	local sumCreditedF = 0
	local testAmounts = { 1.25, 0.50, 0.33, 2.75, 10.5, 0.17, 3.14 }
	for _, amt in testAmounts do
		nominalTotalF += amt
		local ok, whole = GoldCredit.Credit(player, amt)
		if ok then
			sumCreditedF += whole
		else
			allPassed = false
		end
	end
	local goldEndF = DataService.Get(player, "Gold") or 0
	local deltaF = goldEndF - goldStartF
	local remF = GoldCredit.GetRemainder(player)
	local diffF = nominalTotalF - deltaF
	local invariantMathOk = math.abs(diffF - remF) < 1e-6
	local passF = (deltaF == sumCreditedF) and invariantMathOk
	if not passF then allPassed = false end
	print(("[Test F: Invariants]     %s | Gold Delta (%d) == Sum Credited (%d) | Nominal Total (%.4f) - Gold Delta (%d) == Remainder (%.4f, match: %s)"):format(
		if passF then "PASS" else "FAIL", deltaF, sumCreditedF, nominalTotalF, deltaF, remF, tostring(invariantMathOk)
	))

	-- Restore player's initial gold
	DataService.Set(player, "Gold", initialGold)
	GoldCredit.Clear(player)

	print("================================================================================")
	print(("[DevCommands] ====== GoldCredit Suite Completed: %s ======"):format(if allPassed then "ALL TESTS PASSED" else "SOME TESTS FAILED"))
	print("================================================================================")

	say(player, ("[GoldCreditTest] %s! Real server credit verified: 1000x1.25, 60x10.5, 1000x12, 1000x2.5, failure-safety, and invariants."):format(
		if allPassed then "ALL TESTS PASSED" else "TESTS FAILED"
	))

	player:SetAttribute("GoldCreditTestCompleted", allPassed)

	return allPassed
end

local function runGoldCreditTest(player: Player): boolean
	return runGoldCreditTestSuite(player)
end

local function onGoldCreditTestCommand(originTextSource: TextSource, _unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end
	runGoldCreditTest(player)
end

local function onTeleportCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end

	local target = unfilteredText:match("^%S+%s+(%S+)")
	if not target then
		say(player, "Usage: /tp <hub|home|shop>")
		return
	end

	local lower = string.lower(target)
	local dest: string? = nil
	if lower == "hub" then
		dest = "Hub"
	elseif lower == "home" then
		dest = "Home"
	elseif lower == "shop" then
		dest = "Shop"
	else
		say(player, "Unknown destination '" .. target .. "'. Usage: /tp <hub|home|shop>")
		return
	end

	local success, err = WorldTeleportService.TeleportPlayer(player, dest)
	if success then
		say(player, ("Teleported to %s!"):format(dest))
	else
		say(player, ("/tp rejected: %s"):format(err or "Unknown error"))
	end
end

function DevCommands.Start()
	if not RunService:IsStudio() then
		return
	end

	local tpCommand = Instance.new("TextChatCommand")
	tpCommand.Name = "DevTpCommand"
	tpCommand.PrimaryAlias = "/tp"
	tpCommand.Triggered:Connect(onTeleportCommand)
	tpCommand.Parent = TextChatService

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

	local pedSlotsCommand = Instance.new("TextChatCommand")
	pedSlotsCommand.Name = "DevPedSlotsCommand"
	pedSlotsCommand.PrimaryAlias = "/pedslots"
	pedSlotsCommand.Triggered:Connect(onPedSlotsCommand)
	pedSlotsCommand.Parent = TextChatService

	local blessingCostCommand = Instance.new("TextChatCommand")
	blessingCostCommand.Name = "DevBlessingCostCommand"
	blessingCostCommand.PrimaryAlias = "/blessingcost"
	blessingCostCommand.Triggered:Connect(onBlessingCostCommand)
	blessingCostCommand.Parent = TextChatService

	local setBlessingCommand = Instance.new("TextChatCommand")
	setBlessingCommand.Name = "DevSetBlessingCommand"
	setBlessingCommand.PrimaryAlias = "/setblessing"
	setBlessingCommand.Triggered:Connect(onSetBlessingCommand)
	setBlessingCommand.Parent = TextChatService

	local blessingTestCommand = Instance.new("TextChatCommand")
	blessingTestCommand.Name = "DevBlessingTestCommand"
	blessingTestCommand.PrimaryAlias = "/blessingtest"
	blessingTestCommand.Triggered:Connect(onBlessingTestCommand)
	blessingTestCommand.Parent = TextChatService

	local luckCommand = Instance.new("TextChatCommand")
	luckCommand.Name = "DevLuckCommand"
	luckCommand.PrimaryAlias = "/luck"
	luckCommand.Triggered:Connect(onLuckCommand)
	luckCommand.Parent = TextChatService

	local goldCreditTestCommand = Instance.new("TextChatCommand")
	goldCreditTestCommand.Name = "DevGoldCreditTestCommand"
	goldCreditTestCommand.PrimaryAlias = "/goldcredittest"
	goldCreditTestCommand.Triggered:Connect(onGoldCreditTestCommand)
	goldCreditTestCommand.Parent = TextChatService

	local rebirthTestCommand = Instance.new("TextChatCommand")
	rebirthTestCommand.Name = "DevRebirthTestCommand"
	rebirthTestCommand.PrimaryAlias = "/rebirthtest"
	rebirthTestCommand.Triggered:Connect(onRebirthTestCommand)
	rebirthTestCommand.Parent = TextChatService

end

return DevCommands
