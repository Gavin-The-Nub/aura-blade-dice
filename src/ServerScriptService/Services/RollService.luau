--!strict
-- RollService: Server-authoritative Dice rolling, Luck calculations, cooldowns,
-- inventory size validation, Auto-Roll loops, and simulation test commands.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Config.Game)
local Swords = require(ReplicatedStorage.Config.Swords)
local Dice = require(ReplicatedStorage.Config.Dice)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataService = require(ServerScriptService.Services.DataService)
local TapService = require(ServerScriptService.Services.TapService)

local RollService = {}

-- Cached list of rollable swords sorted descending by baseOdds (rarest to most common)
local rollableSwords: { Swords.SwordDef } = {}
local mostCommonSword: Swords.SwordDef

for _, sword in Swords do
	if not sword.isTest then
		table.insert(rollableSwords, sword)
	end
end

table.sort(rollableSwords, function(a, b)
	return a.baseOdds > b.baseOdds
end)

mostCommonSword = rollableSwords[#rollableSwords]

-- Indexed Dice tier lookup
local diceMap: { [number]: Dice.DiceDef } = {}
for _, def in Dice do
	diceMap[def.tier] = def
end

-- Player state tracking
local lastRollTime: { [Player]: number } = {}
local autoRollActive: { [Player]: boolean } = {}
local autoRollThreads: { [Player]: thread } = {}

-- Cleans up all state and threads for a player
local function cleanupPlayer(player: Player)
	autoRollActive[player] = nil
	if autoRollThreads[player] then
		task.cancel(autoRollThreads[player])
		autoRollThreads[player] = nil
	end
	lastRollTime[player] = nil
end

-- Gets player's equipped Dice definition (fallback to Tier 1)
local function getPlayerDice(player: Player): Dice.DiceDef
	local tier = DataService.Get(player, "DiceTier")
	if type(tier) ~= "number" then
		tier = 1
	end
	return diceMap[tier] or diceMap[1]
end

-- Calculates Total Luck: Dice Base Luck × Fever (+50%) × Future Boosts
function RollService.GetTotalLuck(player: Player): number
	local diceDef = getPlayerDice(player)
	local diceLuck = diceDef.baseLuck or 1
	local feverLuck = TapService.GetLuckMultiplier(player)
	return diceLuck * feverLuck
end

-- Core roll selection algorithm:
-- Check swords from rarest to most common.
-- Each succeeds with chance 1 / Effective Odds. First success wins.
-- Fallback to the most common sword.
function RollService.PickSwordWithLuck(totalLuck: number): Swords.SwordDef
	for _, sword in rollableSwords do
		local effectiveOdds = math.max(1, sword.baseOdds / totalLuck)
		local chance = 1 / effectiveOdds
		if math.random() <= chance then
			return sword
		end
	end
	return mostCommonSword
end

-- Executes a single roll for a player.
-- Returns: success (boolean), sword (SwordDef?), errorMessage (string?)
function RollService.Roll(player: Player, isAuto: boolean): (boolean, Swords.SwordDef?, string?)
	if player.Parent ~= Players then
		return false, nil, "Player left"
	end

	if not DataService.IsLoaded(player) then
		return false, nil, "Data is loading..."
	end

	local cooldown = GameConfig.Roll.Cooldown
	local now = os.clock()
	local lastTime = lastRollTime[player] or 0

	-- Cooldown validation (allow 0.05s network leeway for manual rolls)
	local timeSince = now - lastTime
	if timeSince < (cooldown - 0.05) then
		return false, nil, ("Rolling on cooldown (%.1fs remaining)"):format(math.max(0, cooldown - timeSince))
	end

	-- Determine roll result
	local totalLuck = RollService.GetTotalLuck(player)
	local wonSword = RollService.PickSwordWithLuck(totalLuck)

	-- Check Auto-Sell rule (Auto-sold swords don't count against inventory cap, simply removed)
	local autoSellRules = DataService.Get(player, "AutoSellRules")
	local isAutoSold = type(autoSellRules) == "table" and autoSellRules[wonSword.rarity] == true

	if isAutoSold then
		lastRollTime[player] = now
		return true, wonSword, nil, true
	end

	-- Inventory capacity validation (only for swords kept in inventory)
	local ownedSwords = DataService.Get(player, "OwnedSwords")
	if type(ownedSwords) ~= "table" then
		ownedSwords = {}
	end

	local maxCapacity = (GameConfig.Inventory and GameConfig.Inventory.MaxSwords) or 50
	if #ownedSwords >= maxCapacity then
		return false, nil, ("Inventory is full! (Max %d swords)"):format(maxCapacity), false
	end

	-- Update cooldown timestamp
	lastRollTime[player] = now

	-- Add to player inventory {uid = <unique id>, id = <sword id>}
	local newEntry = {
		uid = HttpService:GenerateGUID(false),
		id = wonSword.id,
	}

	local updatedSwords = table.clone(ownedSwords)
	table.insert(updatedSwords, newEntry)
	DataService.Set(player, "OwnedSwords", updatedSwords)

	return true, wonSword, nil, false
end

local function stopAutoRoll(player: Player)
	autoRollActive[player] = false
	local thread = autoRollThreads[player]
	if thread then
		autoRollThreads[player] = nil
		if thread ~= coroutine.running() then
			task.cancel(thread)
		end
	end
	if player.Parent == Players then
		Remotes.getEvent("AutoRollStateChanged"):FireClient(player, false)
	end
end

local function startAutoRoll(player: Player)
	if autoRollActive[player] then
		return
	end
	autoRollActive[player] = true
	Remotes.getEvent("AutoRollStateChanged"):FireClient(player, true)

	autoRollThreads[player] = task.spawn(function()
		while autoRollActive[player] do
			if player.Parent ~= Players or not DataService.IsLoaded(player) then
				cleanupPlayer(player)
				break
			end

			local success, wonSword, err, isAutoSold = RollService.Roll(player, true)
			if success and wonSword then
				Remotes.getEvent("RollResult"):FireClient(player, true, wonSword, true, nil, isAutoSold)
			else
				-- If inventory is full or data unloaded, notify and halt auto roll
				Remotes.getEvent("RollResult"):FireClient(player, false, nil, true, err, false)
				stopAutoRoll(player)
				break
			end

			task.wait(GameConfig.Roll.Cooldown)
		end
	end)
end

function RollService.ToggleAutoRoll(player: Player)
	if autoRollActive[player] then
		stopAutoRoll(player)
	else
		startAutoRoll(player)
	end
end

-- Simulates N rolls and returns distribution data for testing
function RollService.SimulateRolls(player: Player, count: number): { [string]: any }
	local totalLuck = RollService.GetTotalLuck(player)
	local countsByRarity: { [string]: number } = {
		Common = 0,
		Uncommon = 0,
		Rare = 0,
		Epic = 0,
		Legendary = 0,
		Mythic = 0,
		Secret = 0,
	}
	local countsBySword: { [string]: number } = {}

	for _ = 1, count do
		local sword = RollService.PickSwordWithLuck(totalLuck)
		countsByRarity[sword.rarity] = (countsByRarity[sword.rarity] or 0) + 1
		countsBySword[sword.name] = (countsBySword[sword.name] or 0) + 1
	end

	-- Compute theoretical probability for each sword in rarest-to-common order
	-- P(S_i) = (prod_{j < i} (1 - p_j)) * p_i
	local expectedOdds: { [string]: number } = {}
	local expectedRarity: { [string]: number } = {
		Common = 0,
		Uncommon = 0,
		Rare = 0,
		Epic = 0,
		Legendary = 0,
		Mythic = 0,
		Secret = 0,
	}

	local runningMissProbability = 1.0
	for i, sword in ipairs(rollableSwords) do
		local effectiveOdds = math.max(1, sword.baseOdds / totalLuck)
		local p = 1 / effectiveOdds
		local probWon: number

		if i == #rollableSwords then
			-- Fallback catches all remaining probability
			probWon = runningMissProbability
		else
			probWon = runningMissProbability * p
			runningMissProbability *= (1 - p)
		end

		expectedOdds[sword.name] = probWon
		expectedRarity[sword.rarity] = (expectedRarity[sword.rarity] or 0) + probWon
	end

	return {
		Count = count,
		TotalLuck = totalLuck,
		CountsByRarity = countsByRarity,
		CountsBySword = countsBySword,
		ExpectedRarity = expectedRarity,
		ExpectedOdds = expectedOdds,
	}
end

function RollService.Start()
	-- Remotes setup
	local rollEvent = Remotes.getEvent("Roll")
	local toggleAutoRollEvent = Remotes.getEvent("ToggleAutoRoll")
	local rollResultEvent = Remotes.getEvent("RollResult")

	rollEvent.OnServerEvent:Connect(function(player: Player)
		local success, wonSword, err, isAutoSold = RollService.Roll(player, false)
		if success and wonSword then
			rollResultEvent:FireClient(player, true, wonSword, false, nil, isAutoSold)
		else
			rollResultEvent:FireClient(player, false, nil, false, err, false)
		end
	end)

	toggleAutoRollEvent.OnServerEvent:Connect(function(player: Player)
		RollService.ToggleAutoRoll(player)
	end)

	-- Clean up players
	Players.PlayerRemoving:Connect(cleanupPlayer)
end

return RollService
