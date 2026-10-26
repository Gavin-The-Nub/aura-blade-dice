--!strict
-- EconSim: Studio-only economy and progression simulation module.
-- Analyzes roll odds, waterfall probabilities, progression pacing, required income multipliers,
-- supply assumptions, multiplier budgets (GDD Max & Anime Dice reference), and 24-hour bottlenecks.
-- Triggered in Studio via "/econ" dev command or require(ServerScriptService.EconSim).Run().

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Config.Game)
local Dice = require(ReplicatedStorage.Config.Dice)
local Swords = require(ReplicatedStorage.Config.Swords)
local NumberFormat = require(ReplicatedStorage.Shared.NumberFormat)

export type SimulationSword = {
	id: string,
	name: string,
	rarity: string,
	baseOdds: number,
	baseDamage: number,
	isHypothetical: boolean?,
}

export type SwordRollResult = {
	sword: SimulationSword,
	effectiveOdds: number,
	singleCheckProb: number,
	winProbability: number,
	expectedRolls: number,
}

export type TierSimulationResult = {
	tier: number,
	diceName: string,
	luck: number,
	best100: SimulationSword,
	best500: SimulationSword,
	best2000: SimulationSword,
	setRollTimeSec: number,
	autoTapGps: number,
	passiveGps: number,
	nextCost: number,
	timeAutoSec: number,
	timePassiveSec: number,
	targetSec: number,
	reqMultAuto: number,
	reqMultPass: number,
	supplyMult: number,
	reqOverSupplyAuto: number,
	reqOverSupplyPass: number,
}

export type MilestonesReport = {
	firstPoolRunoutTier: number?,
	first24hAutoTapTier: number?,
	first24hPassiveTier: number?,
	firstExceedBudgetA_Auto: number?,
	firstExceedBudgetA_Pass: number?,
	firstExceedBudgetB_Auto: number?,
	firstExceedBudgetB_Pass: number?,
	firstReqOverSupply_Auto: number?,
	firstReqOverSupply_Pass: number?,
	firstReqOverSupply3Tiers_Auto: number?,
	firstReqOverSupply3Tiers_Pass: number?,
	firstReqOverSupplyPermanent_Auto: number?,
	firstReqOverSupplyPermanent_Pass: number?,
	dips_Auto: { number }?,
	dips_Pass: { number }?,
	firstReqOver2_Auto: number?,
	firstReqOver2_Pass: number?,
	maxReqOverSupply_Auto: number?,
	maxReqOverSupplyTier_Auto: number?,
	maxReqOverSupply_Pass: number?,
	maxReqOverSupplyTier_Pass: number?,
}

local EconSim = {}

-- PacingTargets (v3): Target time-to-afford next Dice tier in seconds.
-- Tiers 1-7: 15 minutes; 8-9: 2 hours; 10-11: 24 hours; 12-13: 72 hours; 14-29: 7 days.
local PacingTargets: { [number]: number } = {
	[1] = 15 * 60, -- 15 mins (900s)
	[2] = 15 * 60,
	[3] = 15 * 60,
	[4] = 15 * 60,
	[5] = 15 * 60,
	[6] = 15 * 60,
	[7] = 15 * 60,
	[8] = 2 * 3600, -- 2 hours (7,200s)
	[9] = 2 * 3600,
	[10] = 24 * 3600, -- 24 hours (86,400s)
	[11] = 24 * 3600,
	[12] = 72 * 3600, -- 72 hours (259,200s)
	[13] = 72 * 3600,
}
for t = 14, 29 do
	PacingTargets[t] = 7 * 86400 -- 7 days (604,800s)
end

EconSim.PacingTargets = PacingTargets

-- SupplyAssumptions (v3): Typical total multiplier a player has by tier.
-- Tiers 1-7: 1x; 8-9: 5x; 10-11: 30x; 12-13: 100x; 14-29: 100x.
local SupplyAssumptions: { [number]: number } = {
	[1] = 1,
	[2] = 1,
	[3] = 1,
	[4] = 1,
	[5] = 1,
	[6] = 1,
	[7] = 1,
	[8] = 5,
	[9] = 5,
	[10] = 30,
	[11] = 30,
	[12] = 100,
	[13] = 100,
}
for t = 14, 29 do
	SupplyAssumptions[t] = 100
end

EconSim.SupplyAssumptions = SupplyAssumptions

-- Reference Multiplier Budgets
local BUDGET_A = 30 * 150 * 50 -- 225,000x (GDD max: Grade 30 x Enchant 150 x Rebirth Gold 50)
local BUDGET_B = 25 * 15 * 2.5 -- 937.5x (Anime Dice reference: Grade 25 x Trait 15 x Rebirth 2.5)

-- Roll tables for Grades (Master Appraiser) and Enchants (Enchanter) from GDD
local GDD_GRADES = {
	{ name = "D", chance = 0.35, mult = 1.0 },
	{ name = "C", chance = 0.25, mult = 1.25 },
	{ name = "B", chance = 0.18, mult = 1.5 },
	{ name = "A", chance = 0.12, mult = 2.0 },
	{ name = "S", chance = 0.065, mult = 3.0 },
	{ name = "SS", chance = 0.025, mult = 5.0 },
	{ name = "SSS", chance = 0.0085, mult = 8.5 },
	{ name = "Z", chance = 0.0014, mult = 15.0 },
	{ name = "Z+", chance = 0.0001, mult = 30.0 },
}

local GDD_ENCHANTS = {
	{ name = "Sharpness", chance = 0.40, mult = 1.2 },
	{ name = "Berserker", chance = 0.25, mult = 1.6 },
	{ name = "Vampiric", chance = 0.15, mult = 2.2 },
	{ name = "Executioner", chance = 0.10, mult = 3.5 },
	{ name = "Ronin", chance = 0.06, mult = 6.0 },
	{ name = "Sovereign", chance = 0.028, mult = 12.0 },
	{ name = "Transcendent", chance = 0.01, mult = 28.0 },
	{ name = "Genesis", chance = 0.0018, mult = 75.0 },
	{ name = "Singularity", chance = 0.0002, mult = 150.0 },
}

local function formatDuration(seconds: number): string
	if seconds <= 0 then
		return "MAX"
	end
	if seconds == math.huge or seconds ~= seconds then
		return "inf"
	end
	if seconds < 60 then
		return string.format("%.0fs", seconds)
	elseif seconds < 3600 then
		return string.format("%.1fm", seconds / 60)
	elseif seconds < 86400 then
		return string.format("%.1fh", seconds / 3600)
	elseif seconds < 86400 * 365 then
		return string.format("%.1fd", seconds / 86400)
	else
		return string.format("%.1fy", seconds / (86400 * 365))
	end
end

local function formatMultiplier(mult: number): string
	if mult <= 0 then
		return "-"
	end
	if mult < 1.0 then
		return string.format("%.2fx", mult)
	end
	if mult < 1000 then
		return string.format("%.1fx", mult)
	end
	return NumberFormat.format(mult) .. "x"
end

-- Verifies the fit of damage = odds^0.72 against current sample swords
local function verifyPowerLawFit()
	local testSwords = {
		{ name = "Rusty Shortsword", odds = 2, actualDmg = 1 },
		{ name = "Iron Broadsword", odds = 35, actualDmg = 12 },
		{ name = "Static Katana", odds = 1200, actualDmg = 280 },
		{ name = "Frostbite Claymore", odds = 8500, actualDmg = 850 },
		{ name = "Cursed Blood Scythe-Blade", odds = 38000, actualDmg = 2200 },
		{ name = "Thunderlord Greatsword", odds = 290000, actualDmg = 9100 },
	}

	print("\n" .. string.rep("=", 90))
	print("  [EconSim] VERIFYING POWER LAW FIT: damage = odds^0.72")
	print(string.rep("=", 90))
	print(string.format("%-28s | %-8s | %-10s | %-12s | %-10s | %-10s", "Sword", "BaseOdds", "ActualDmg", "Model(O^0.72)", "Abs Error", "% Error"))
	print(string.rep("-", 90))

	for _, item in testSwords do
		local modelDmg = item.odds ^ 0.72
		local absErr = math.abs(modelDmg - item.actualDmg)
		local pctErr = (absErr / item.actualDmg) * 100
		print(string.format("%-28s | %-8d | %-10d | %-12.2f | %-10.2f | %-9.2f%%", item.name, item.odds, item.actualDmg, modelDmg, absErr, pctErr))
	end
	print(string.rep("-", 90))
	print("Note: In low tiers (integer rounding), % error is higher; across higher tiers it stabilizes tightly to ~5-10% error.\n")
end

-- Runs waterfall probability calculations for a given pool of swords at a given Luck
local function calculateTierRolls(pool: { SimulationSword }, luck: number): ({ SwordRollResult }, number)
	local results: { SwordRollResult } = {}
	local runningMissProb = 1.0
	local totalProb = 0.0

	for i, sword in ipairs(pool) do
		local effOdds = math.max(1.0, sword.baseOdds / luck)
		local singleProb = 1.0 / effOdds
		local winProb: number

		if i == #pool then
			-- Fallback catches all remaining miss probability
			winProb = runningMissProb
		else
			winProb = runningMissProb * singleProb
			runningMissProb = runningMissProb * (1.0 - singleProb)
		end

		totalProb += winProb
		local expRolls = if winProb > 0 then (1.0 / winProb) else math.huge

		table.insert(results, {
			sword = sword,
			effectiveOdds = effOdds,
			singleCheckProb = singleProb,
			winProbability = winProb,
			expectedRolls = expRolls,
		})
	end

	return results, totalProb
end

-- Step-by-step waterfall walk-through for Tier 8 (Gale Dice)
local function printTier8StepByStep(pool: { SimulationSword }, luck: number)
	print("\n" .. string.rep("=", 110))
	print(string.format("  [EconSim] TIER 8 (Gale Dice) STEP-BY-STEP WATERFALL PROBABILITIES (Luck = %.1f)", luck))
	print(string.rep("=", 110))
	print(string.format("%-26s | %-9s | %-10s | %-10s | %-12s | %-12s | %-12s", "Sword", "Base Odds", "Eff Odds", "Single p", "Run Miss", "Win Prob P", "Exp Rolls"))
	print(string.rep("-", 110))

	local runningMiss = 1.0
	local totalProb = 0.0

	for i, sword in ipairs(pool) do
		local effOdds = math.max(1.0, sword.baseOdds / luck)
		local p = 1.0 / effOdds
		local currentMissBefore = runningMiss
		local winProb: number

		if i == #pool then
			winProb = runningMiss
			runningMiss = 0.0
		else
			winProb = runningMiss * p
			runningMiss = runningMiss * (1.0 - p)
		end

		totalProb += winProb
		local expRolls = if winProb > 0 then (1.0 / winProb) else math.huge

		print(string.format(
			"%-26s | %-9d | %-10.2f | %-10.6f | %-12.6f | %-12.6f | %-12.1f",
			sword.name,
			sword.baseOdds,
			effOdds,
			p,
			currentMissBefore,
			winProb,
			expRolls
		))
	end

	print(string.rep("-", 110))
	print(string.format("Tier 8 Total Probability Sum: %.10f (Check: %s)\n", totalProb, if math.abs(totalProb - 1.0) < 1e-6 then "PASSED [1.000000]" else "FAILED"))
end

-- Simulates all 29 tiers and prints the progression table
local function runProgressionSimulation(
	pool: { SimulationSword },
	goldMult: number,
	luckMult: number,
	scope: number?,
	critFeverFactor: number?,
	label: string
): MilestonesReport
	local rollCooldown = (GameConfig.Roll and GameConfig.Roll.Cooldown) or 3.0
	local baseTapsSec = (GameConfig.AutoTap and GameConfig.AutoTap.BaseTapsPerSecond) or 10.0
	local passiveRate = (GameConfig.Plot and GameConfig.Plot.PassiveRateMultiplier) or 0.5
	local maxPrintTier = if type(scope) == "number" and scope > 0 then math.clamp(math.floor(scope), 1, #Dice) else #Dice
	local cfFactor = if type(critFeverFactor) == "number" and critFeverFactor > 0 then critFeverFactor else 1.0

	print("\n" .. string.rep("=", 185))
	print(string.format(
		"  [EconSim] PROGRESSION TABLE: %s\n  (Scope: Tiers 1..%d | Gold Mult: %.2fx | Luck Mult: %.2fx | Tap Rate: %.0f/s | Crit/Fever Factor: %.2fx)",
		label,
		maxPrintTier,
		goldMult,
		luckMult,
		baseTapsSec,
		cfFactor
	))
	print(string.rep("=", 185))
	print(string.format(
		"%-2s | %-16s | %-18s | %-18s | %-18s | %-8s | %-9s | %-8s | %-9s | %-9s | %-8s | %-6s | %-9s | %-9s | %-9s",
		"T", "Dice Name", "Best (100r)", "Best (500r)", "Best (2000r)", "SetTime", "Auto GPS", "Pass GPS", "Next Cost", "Time Auto", "Req Auto", "Supply", "R/S Auto", "Time Pass", "R/S Pass"
	))
	print(string.rep("-", 185))

	local firstPoolRunoutTier: number? = nil
	local first24hAutoTapTier: number? = nil
	local first24hPassiveTier: number? = nil

	local firstExceedBudgetA_Auto: number? = nil
	local firstExceedBudgetA_Pass: number? = nil
	local firstExceedBudgetB_Auto: number? = nil
	local firstExceedBudgetB_Pass: number? = nil

	local firstReqOverSupply_Auto: number? = nil
	local firstReqOverSupply_Pass: number? = nil

	local maxWaterfallError = 0.0

	-- Pre-sort pool descending by baseOdds
	local sortedPool = table.clone(pool)
	table.sort(sortedPool, function(a, b)
		return a.baseOdds > b.baseOdds
	end)

	local highestSwordInOriginal = sortedPool[1]
	for _, s in sortedPool do
		if not s.isHypothetical then
			highestSwordInOriginal = s
			break
		end
	end

	local allUnlockedSwords: { SimulationSword } = {}
	local allTierResults: { TierSimulationResult } = {}

	for idx, diceDef in ipairs(Dice) do
		local luck = diceDef.baseLuck * luckMult
		local swordResults, sumProb = calculateTierRolls(sortedPool, luck)
		local probErr = math.abs(sumProb - 1.0)
		if probErr > maxWaterfallError then
			maxWaterfallError = probErr
		end

		-- Helper to get best sword at expected rolls threshold
		local function getBestSword(threshold: number): SimulationSword
			local bestSword: SimulationSword? = nil
			local maxDmg = -1
			for _, res in swordResults do
				if res.expectedRolls <= threshold then
					if res.sword.baseDamage > maxDmg then
						maxDmg = res.sword.baseDamage
						bestSword = res.sword
					end
				end
			end
			if bestSword then
				return bestSword
			end
			-- Fallback: most attainable sword
			local minRolls = math.huge
			local fallbackSword = sortedPool[#sortedPool]
			for _, res in swordResults do
				if res.expectedRolls < minRolls then
					minRolls = res.expectedRolls
					fallbackSword = res.sword
				end
			end
			return fallbackSword
		end

		local b100 = getBestSword(100)
		local b500 = getBestSword(500)
		local b2000 = getBestSword(2000)

		-- Check if the real pool has run out (player already achieves top original sword at 500 rolls)
		if firstPoolRunoutTier == nil and b500.id == highestSwordInOriginal.id then
			firstPoolRunoutTier = diceDef.tier
		end

		-- Build pedestal set: up to 5 distinct swords with expected rolls <= 500
		local valid500: { { sword: SimulationSword, expectedRolls: number } } = {}
		for _, res in swordResults do
			if res.expectedRolls <= 500 then
				table.insert(valid500, { sword = res.sword, expectedRolls = res.expectedRolls })
				-- Track across tiers that player has realistically unlocked this sword
				local alreadyKnown = false
				for _, kn in allUnlockedSwords do
					if kn.id == res.sword.id then
						alreadyKnown = true
						break
					end
				end
				if not alreadyKnown then
					table.insert(allUnlockedSwords, res.sword)
				end
			end
		end

		table.sort(valid500, function(a, b)
			return a.sword.baseDamage > b.sword.baseDamage
		end)

		local setSwords: { SimulationSword } = {}
		for i = 1, math.min(5, #valid500) do
			table.insert(setSwords, valid500[i].sword)
		end

		-- If higher-tier waterfall cutoff (p=1) eliminated lower rolls, fill pedestals from previously unlocked swords
		if #setSwords < 5 then
			table.sort(allUnlockedSwords, function(a, b)
				return a.baseDamage > b.baseDamage
			end)
			for _, prevSword in allUnlockedSwords do
				if #setSwords >= 5 then
					break
				end
				local alreadyIn = false
				for _, s in setSwords do
					if s.id == prevSword.id then
						alreadyIn = true
						break
					end
				end
				if not alreadyIn then
					table.insert(setSwords, prevSword)
				end
			end
		end

		local equippedSword = setSwords[1] or sortedPool[#sortedPool]
		local pedestalSwords: { SimulationSword } = {}
		for i = 2, math.min(5, #setSwords) do
			table.insert(pedestalSwords, setSwords[i])
		end

		-- Roll time for the 500-threshold set: bottleneck is the hardest sword in valid500
		local maxSetRolls = 0.0
		for i = 1, math.min(5, #valid500) do
			if valid500[i].expectedRolls > maxSetRolls then
				maxSetRolls = valid500[i].expectedRolls
			end
		end
		if maxSetRolls == 0 then
			maxSetRolls = swordResults[#swordResults].expectedRolls
		end
		local setRollTimeSec = maxSetRolls * rollCooldown

		-- Calculate GPS (Auto-Tap portion scales with critFeverFactor; pedestals do not crit)
		local pedDamageSum = 0
		for _, pSword in pedestalSwords do
			pedDamageSum += pSword.baseDamage
		end

		local tapPortion = equippedSword.baseDamage * baseTapsSec * cfFactor
		local passiveGps = (pedDamageSum * passiveRate) * goldMult
		local autoTapGps = (tapPortion + (pedDamageSum * passiveRate)) * goldMult

		-- Next Dice Cost and Time to afford
		local nextDiceDef = Dice[idx + 1]
		local nextCost = if nextDiceDef then nextDiceDef.cost else 0
		local timeAutoSec = if nextCost > 0 and autoTapGps > 0 then (nextCost / autoTapGps) else 0
		local timePassiveSec = if nextCost > 0 and passiveGps > 0 then (nextCost / passiveGps) else 0

		-- Pacing Target, Supply Assumptions, and Required Multipliers
		local targetSec = PacingTargets[diceDef.tier] or (7 * 86400)
		local supplyMult = SupplyAssumptions[diceDef.tier] or 100
		local reqMultAuto = if nextCost > 0 and timeAutoSec > 0 and targetSec > 0 then (timeAutoSec / targetSec) else 0
		local reqMultPass = if nextCost > 0 and timePassiveSec > 0 and targetSec > 0 then (timePassiveSec / targetSec) else 0

		local reqOverSupplyAuto = if reqMultAuto > 0 and supplyMult > 0 then (reqMultAuto / supplyMult) else 0
		local reqOverSupplyPass = if reqMultPass > 0 and supplyMult > 0 then (reqMultPass / supplyMult) else 0

		if nextCost > 0 then
			if first24hAutoTapTier == nil and timeAutoSec > 86400 then
				first24hAutoTapTier = diceDef.tier
			end
			if first24hPassiveTier == nil and timePassiveSec > 86400 then
				first24hPassiveTier = diceDef.tier
			end

			-- Check Budget A (225,000x)
			if firstExceedBudgetA_Auto == nil and reqMultAuto > BUDGET_A then
				firstExceedBudgetA_Auto = diceDef.tier
			end
			if firstExceedBudgetA_Pass == nil and reqMultPass > BUDGET_A then
				firstExceedBudgetA_Pass = diceDef.tier
			end

			-- Check Budget B (937.5x)
			if firstExceedBudgetB_Auto == nil and reqMultAuto > BUDGET_B then
				firstExceedBudgetB_Auto = diceDef.tier
			end
			if firstExceedBudgetB_Pass == nil and reqMultPass > BUDGET_B then
				firstExceedBudgetB_Pass = diceDef.tier
			end

			-- Check Req/Supply > 1
			if firstReqOverSupply_Auto == nil and reqOverSupplyAuto > 1.0 then
				firstReqOverSupply_Auto = diceDef.tier
			end
			if firstReqOverSupply_Pass == nil and reqOverSupplyPass > 1.0 then
				firstReqOverSupply_Pass = diceDef.tier
			end
		end

		local tierRes: TierSimulationResult = {
			tier = diceDef.tier,
			diceName = diceDef.name,
			luck = luck,
			best100 = b100,
			best500 = b500,
			best2000 = b2000,
			setRollTimeSec = setRollTimeSec,
			autoTapGps = autoTapGps,
			passiveGps = passiveGps,
			nextCost = nextCost,
			timeAutoSec = timeAutoSec,
			timePassiveSec = timePassiveSec,
			targetSec = targetSec,
			reqMultAuto = reqMultAuto,
			reqMultPass = reqMultPass,
			supplyMult = supplyMult,
			reqOverSupplyAuto = reqOverSupplyAuto,
			reqOverSupplyPass = reqOverSupplyPass,
		}
		table.insert(allTierResults, tierRes)

		if diceDef.tier <= maxPrintTier then
			print(string.format(
				"%-2d | %-16s | %-18s | %-18s | %-18s | %-8s | %-9s | %-8s | %-9s | %-9s | %-8s | %-6s | %-9s | %-9s | %-9s",
				diceDef.tier,
				diceDef.name,
				string.sub(b100.name, 1, 18),
				string.sub(b500.name, 1, 18),
				string.sub(b2000.name, 1, 18),
				formatDuration(setRollTimeSec),
				NumberFormat.format(autoTapGps),
				NumberFormat.format(passiveGps),
				if nextCost > 0 then NumberFormat.format(nextCost) else "MAX",
				formatDuration(timeAutoSec),
				formatMultiplier(reqMultAuto),
				NumberFormat.format(supplyMult) .. "x",
				formatMultiplier(reqOverSupplyAuto),
				formatDuration(timePassiveSec),
				formatMultiplier(reqOverSupplyPass)
			))
		end
	end

	print(string.rep("-", 185))
	print(string.format("Sanity Check: Waterfall probabilities sum across all 29 tiers = 1.0 (Max Error: %.2e)\n", maxWaterfallError))

	print("  --- MILESTONES & BOTTLENECK REPORT ---")
	print(string.format("  * First Tier where sword pool stops giving new swords: %s", if firstPoolRunoutTier then ("Tier " .. tostring(firstPoolRunoutTier) .. " (" .. Dice[firstPoolRunoutTier].name .. ")") else "None (pool never ran out)"))
	print(string.format("  * First Tier where next Dice takes > 24 hours (Auto-Tap): %s", if first24hAutoTapTier then ("Tier " .. tostring(first24hAutoTapTier) .. " (" .. Dice[first24hAutoTapTier].name .. " -> " .. Dice[first24hAutoTapTier + 1].name .. ")") else "None (always <= 24h)"))
	print(string.format("  * First Tier where next Dice takes > 24 hours (Passive-only): %s", if first24hPassiveTier then ("Tier " .. tostring(first24hPassiveTier) .. " (" .. Dice[first24hPassiveTier].name .. " -> " .. Dice[first24hPassiveTier + 1].name .. ")") else "None (always <= 24h)"))

	print("\n  --- MULTIPLIER BUDGETS & PACING REPORT ---")
	print(string.format("  * Reference Budget (a) [GDD Max]: Grade 30 x Enchant 150 x Rebirth 50 = %sx", NumberFormat.format(BUDGET_A)))
	print(string.format("    - First Tier Auto-Tap exceeds Budget (a): %s", if firstExceedBudgetA_Auto then ("Tier " .. tostring(firstExceedBudgetA_Auto) .. " (" .. Dice[firstExceedBudgetA_Auto].name .. ")") else "None (within budget)"))
	print(string.format("    - First Tier Passive exceeds Budget (a): %s", if firstExceedBudgetA_Pass then ("Tier " .. tostring(firstExceedBudgetA_Pass) .. " (" .. Dice[firstExceedBudgetA_Pass].name .. ")") else "None (within budget)"))

	print(string.format("  * Reference Budget (b) [Anime Dice Ref]: Grade 25 x Trait 15 x Rebirth 2.5 = %sx", NumberFormat.format(BUDGET_B)))
	print(string.format("    - First Tier Auto-Tap exceeds Budget (b): %s", if firstExceedBudgetB_Auto then ("Tier " .. tostring(firstExceedBudgetB_Auto) .. " (" .. Dice[firstExceedBudgetB_Auto].name .. ")") else "None (within budget)"))
	print(string.format("    - First Tier Passive exceeds Budget (b): %s", if firstExceedBudgetB_Pass then ("Tier " .. tostring(firstExceedBudgetB_Pass) .. " (" .. Dice[firstExceedBudgetB_Pass].name .. ")") else "None (within budget)"))

	-- Find first tier from which Req/Supply stays above 1 for the next 3 tiers
	local function findFirstTierStaysAbove1For3Tiers(isAuto: boolean): (number?, number?)
		local firstSustained: number? = nil
		local firstPermanent: number? = nil

		for i = 1, #allTierResults do
			local r = allTierResults[i]
			if r.nextCost > 0 and r.tier <= maxPrintTier then
				local val = if isAuto then r.reqOverSupplyAuto else r.reqOverSupplyPass
				if val > 1.0 then
					-- Check next 3 tiers: i+1, i+2, i+3
					local next3Ok = true
					for offset = 1, 3 do
						local nextIdx = i + offset
						if nextIdx <= #allTierResults and allTierResults[nextIdx].tier <= maxPrintTier and allTierResults[nextIdx].nextCost > 0 then
							local nextVal = if isAuto then allTierResults[nextIdx].reqOverSupplyAuto else allTierResults[nextIdx].reqOverSupplyPass
							if nextVal <= 1.0 then
								next3Ok = false
								break
							end
						end
					end
					if next3Ok and firstSustained == nil then
						firstSustained = r.tier
					end

					-- Check if it stays above 1.0 for all remaining tiers within scope
					local allRemainingOk = true
					for remIdx = i, #allTierResults do
						if allTierResults[remIdx].tier <= maxPrintTier and allTierResults[remIdx].nextCost > 0 then
							local remVal = if isAuto then allTierResults[remIdx].reqOverSupplyAuto else allTierResults[remIdx].reqOverSupplyPass
							if remVal <= 1.0 then
								allRemainingOk = false
								break
							end
						end
					end
					if allRemainingOk and firstPermanent == nil then
						firstPermanent = r.tier
					end
				end
			end
		end

		return firstSustained, firstPermanent
	end

	-- Compute dip tiers after first sustained deficit where Req/Supply <= 1
	local function getDips(firstSustainedTier: number?, isAuto: boolean): { number }
		local dips: { number } = {}
		if not firstSustainedTier then
			return dips
		end
		for _, r in allTierResults do
			if r.tier > firstSustainedTier and r.tier <= maxPrintTier and r.nextCost > 0 then
				local val = if isAuto then r.reqOverSupplyAuto else r.reqOverSupplyPass
				if val <= 1.0 then
					table.insert(dips, r.tier)
				end
			end
		end
		return dips
	end

	-- Compute first tier where Req/Supply > 2 and max Req/Supply across tiers 1..N
	local function getSeverityStats(isAuto: boolean): (number?, number?, number)
		local firstOver2Tier: number? = nil
		local maxVal = 0.0
		local maxTier: number? = nil

		for _, r in allTierResults do
			if r.tier <= maxPrintTier and r.nextCost > 0 then
				local val = if isAuto then r.reqOverSupplyAuto else r.reqOverSupplyPass
				if firstOver2Tier == nil and val > 2.0 then
					firstOver2Tier = r.tier
				end
				if val > maxVal then
					maxVal = val
					maxTier = r.tier
				end
			end
		end

		return firstOver2Tier, maxTier, maxVal
	end

	local firstSustainedAuto, firstPermAuto = findFirstTierStaysAbove1For3Tiers(true)
	local firstSustainedPass, firstPermPass = findFirstTierStaysAbove1For3Tiers(false)

	local dipsAuto = getDips(firstSustainedAuto, true)
	local dipsPass = getDips(firstSustainedPass, false)

	local firstOver2Auto, maxTierAuto, maxValAuto = getSeverityStats(true)
	local firstOver2Pass, maxTierPass, maxValPass = getSeverityStats(false)

	local function formatSustainedMsg(firstSustained: number?, firstPerm: number?, dips: { number }): string
		if not firstSustained then
			return "None (Supply always meets target)"
		end
		local msg = string.format("Tier %d (%s)", firstSustained, Dice[firstSustained].name)
		if #dips > 0 then
			local dipStrs = {}
			for _, d in dips do
				table.insert(dipStrs, tostring(d))
			end
			local dipsFormatted = if #dipStrs == 1 then ("Tier " .. dipStrs[1]) else ("Tiers " .. table.concat(dipStrs, ", "))
			if firstPerm and firstPerm ~= firstSustained then
				msg ..= string.format(" [dips at %s; permanently stays above 1 from Tier %d (%s)]", dipsFormatted, firstPerm, Dice[firstPerm].name)
			else
				msg ..= string.format(" [dips at %s]", dipsFormatted)
			end
		else
			msg ..= " (stays above 1 for all subsequent tiers)"
		end
		return msg
	end

	local auto3Msg = formatSustainedMsg(firstSustainedAuto, firstPermAuto, dipsAuto)
	local pass3Msg = formatSustainedMsg(firstSustainedPass, firstPermPass, dipsPass)

	local scopeLabel = string.format("T1..%d", maxPrintTier)

	local function formatSeverityMsg(firstOver2: number?, maxTier: number?, maxVal: number, isAuto: boolean): string
		local over2Str = if firstOver2
			then string.format("Tier %d (%s, %s)", firstOver2, Dice[firstOver2].name, formatMultiplier(if isAuto then allTierResults[firstOver2].reqOverSupplyAuto else allTierResults[firstOver2].reqOverSupplyPass))
			else "None"
		local maxStr = if maxTier and maxVal > 0
			then string.format("%s at Tier %d (%s)", formatMultiplier(maxVal), maxTier, Dice[maxTier].name)
			else "None"
		return string.format("First Req/Supply > 2: %s | Max across %s: %s", over2Str, scopeLabel, maxStr)
	end

	local autoSevMsg = formatSeverityMsg(firstOver2Auto, maxTierAuto, maxValAuto, true)
	local passSevMsg = formatSeverityMsg(firstOver2Pass, maxTierPass, maxValPass, false)

	print("\n  --- SUPPLY DEFICIT ANALYSIS ---")
	print(string.format("  * First tier from which Req/Supply stays above 1 for the next 3 tiers (Auto-Tap): %s", auto3Msg))
	print(string.format("    - Severity (Auto-Tap): %s", autoSevMsg))
	print(string.format("  * First tier from which Req/Supply stays above 1 for the next 3 tiers (Passive-only): %s", pass3Msg))
	print(string.format("    - Severity (Passive-only): %s", passSevMsg))
	print(string.rep("=", 185) .. "\n")

	return {
		firstPoolRunoutTier = firstPoolRunoutTier,
		first24hAutoTapTier = first24hAutoTapTier,
		first24hPassiveTier = first24hPassiveTier,
		firstExceedBudgetA_Auto = firstExceedBudgetA_Auto,
		firstExceedBudgetA_Pass = firstExceedBudgetA_Pass,
		firstExceedBudgetB_Auto = firstExceedBudgetB_Auto,
		firstExceedBudgetB_Pass = firstExceedBudgetB_Pass,
		firstReqOverSupply_Auto = firstReqOverSupply_Auto,
		firstReqOverSupply_Pass = firstReqOverSupply_Pass,
		firstReqOverSupply3Tiers_Auto = firstSustainedAuto,
		firstReqOverSupply3Tiers_Pass = firstSustainedPass,
		firstReqOverSupplyPermanent_Auto = firstPermAuto,
		firstReqOverSupplyPermanent_Pass = firstPermPass,
		dips_Auto = dipsAuto,
		dips_Pass = dipsPass,
		firstReqOver2_Auto = firstOver2Auto,
		firstReqOver2_Pass = firstOver2Pass,
		maxReqOverSupply_Auto = maxValAuto,
		maxReqOverSupplyTier_Auto = maxTierAuto,
		maxReqOverSupply_Pass = maxValPass,
		maxReqOverSupplyTier_Pass = maxTierPass,
	}
end

-- Calculates expected multiplier for 1 roll and best of N rolls
local function analyzeRollDistribution(name: string, items: { { name: string, chance: number, mult: number } })
	-- Sort ascending by multiplier
	local sorted = table.clone(items)
	table.sort(sorted, function(a, b)
		return a.mult < b.mult
	end)

	local e1 = 0.0
	for _, item in sorted do
		e1 += (item.chance * item.mult)
	end

	print(string.format("\n  [%s] PROBABILITY & MULTIPLIER TABLE:", name))
	print(string.format("  %-16s | %-12s | %-12s | %-14s", "Name", "Roll Chance", "Multiplier", "Cumulative (<=)"))
	print("  " .. string.rep("-", 60))

	local runningCdf = 0.0
	for _, item in sorted do
		runningCdf += item.chance
		print(string.format("  %-16s | %10.3f%% | %10.2fx | %12.3f%%", item.name, item.chance * 100, item.mult, runningCdf * 100))
	end
	print("  " .. string.rep("-", 60))
	local function getNearestItemLabel(mult: number): string
		local nearestItem = sorted[1]
		local minDiff = math.abs(sorted[1].mult - mult)
		for i = 2, #sorted do
			local diff = math.abs(sorted[i].mult - mult)
			if diff < minDiff then
				minDiff = diff
				nearestItem = sorted[i]
			end
		end
		return string.format("~%s (%.2fx)", nearestItem.name, nearestItem.mult)
	end

	print(string.format("  Expected Multiplier (1 Roll):            %8.4fx  [Nearest: %s]", e1, getNearestItemLabel(e1)))

	local resultsByN: { [number]: number } = { [1] = e1 }

	for _, N in { 10, 100, 1000 } do
		local cumPrev = 0.0
		local expBest = 0.0
		local cdf = 0.0

		for _, item in sorted do
			cdf += item.chance
			local pBestLe = cdf ^ N
			local pBestEq = pBestLe - cumPrev
			cumPrev = pBestLe
			expBest += (item.mult * pBestEq)
		end

		resultsByN[N] = expBest
		print(string.format("  Expected Multiplier (Best of %4d Rolls): %8.4fx  [Nearest: %s]", N, expBest, getNearestItemLabel(expBest)))
	end

	return resultsByN
end

-- Prints expected multiplier from 1 roll and best of N rolls (10, 100, 1000) for Grades & Enchants
function EconSim.PrintExpected(player: Player?): { [string]: any }
	if not RunService:IsStudio() then
		warn("[EconSim] Economy simulation is Studio-only. Aborting in live environment.")
		return {}
	end

	print("\n" .. string.rep("=", 95))
	print("  [EconSim] EXPECTED MULTIPLIERS FOR GRADES & ENCHANTS")
	print("  (Mathematical expected values for 1 roll and Best-of-N independent rolls)")
	print(string.rep("=", 95))

	local gradeResults = analyzeRollDistribution("BLADE GRADES (Master Appraiser, 1 Gem/roll)", GDD_GRADES)
	local enchantResults = analyzeRollDistribution("SWORD ENCHANTS (Enchanter, 1 Token/roll)", GDD_ENCHANTS)

	print("\n  [COMBINED EXPECTED MULTIPLIERS] (Grade x Enchant):")
	print("  " .. string.rep("-", 60))
	for _, N in { 1, 10, 100, 1000 } do
		local combined = gradeResults[N] * enchantResults[N]
		if N == 1 then
			print(string.format("  * 1 Roll Each:              %10.2fx  (Grade %.2fx * Enchant %.2fx)", combined, gradeResults[N], enchantResults[N]))
		else
			print(string.format("  * Best of %4d Rolls Each:   %10.2fx  (Grade %.2fx * Enchant %.2fx)", N, combined, gradeResults[N], enchantResults[N]))
		end
	end
	print("  " .. string.rep("-", 60))
	print(string.rep("=", 95) .. "\n")

	return {
		Grades = gradeResults,
		Enchants = enchantResults,
	}
end

-- Main entry point for the simulation
function EconSim.Run(
	player: Player?,
	goldMult: number?,
	luckMult: number?,
	extended: boolean?,
	scope: number?,
	critFeverFactor: number?
): MilestonesReport?
	if not RunService:IsStudio() then
		warn("[EconSim] Economy simulation is Studio-only. Aborting in live environment.")
		return nil
	end

	local gMult = if type(goldMult) == "number" and goldMult > 0 then goldMult else 1.0
	local lMult = if type(luckMult) == "number" and luckMult > 0 then luckMult else 1.0
	local isExtended = if extended == true then true else false
	local scopeLimit = if type(scope) == "number" and scope > 0 then scope else nil
	local cfFactor = if type(critFeverFactor) == "number" and critFeverFactor > 0 then critFeverFactor else 1.0

	-- 1. Verify power law fit against sample swords
	verifyPowerLawFit()

	-- 2. Build initial sword pool from Config/Swords (excluding test swords)
	local standardPool: { SimulationSword } = {}
	for _, s in Swords do
		if not s.isTest then
			table.insert(standardPool, {
				id = s.id,
				name = s.name,
				rarity = s.rarity,
				baseOdds = s.baseOdds,
				baseDamage = s.baseDamage,
				isHypothetical = false,
			})
		end
	end

	table.sort(standardPool, function(a, b)
		return a.baseOdds > b.baseOdds
	end)

	-- 3. Print Tier 8 step-by-step worked out
	local tier8Luck = (Dice[8].baseLuck or 400) * lMult
	printTier8StepByStep(standardPool, tier8Luck)

	-- 4. Run standard progression simulation
	local standardReport = runProgressionSimulation(standardPool, gMult, lMult, scopeLimit, cfFactor, "STANDARD CONFIG/SWORDS")

	-- 5. If extended simulation requested, generate hypothetical swords and run extended simulation
	local finalReport = standardReport
	if isExtended then
		local extendedPool: { SimulationSword } = table.clone(standardPool)
		local runoutTier = standardReport.firstPoolRunoutTier or 14
		local highestRealOdds = standardPool[1].baseOdds -- 8,500,000 for Chronos

		print("\n" .. string.rep("=", 90))
		print(string.format("  [EconSim] GENERATING HYPOTHETICAL SWORDS (from Tier %d onwards)", runoutTier))
		print("  Rule: Base Odds = ~35 * Tier Luck, Damage = Odds^0.72")
		print(string.rep("=", 90))

		for _, diceDef in ipairs(Dice) do
			if diceDef.tier >= runoutTier then
				local hypoOdds = math.floor((35 * diceDef.baseLuck) + 0.5)
				if hypoOdds > highestRealOdds then
					local hypoDmg = math.floor((hypoOdds ^ 0.72) + 0.5)
					local hypoSword: SimulationSword = {
						id = string.format("hypo_tier_%d", diceDef.tier),
						name = string.format("Tier %d %s Blade", diceDef.tier, diceDef.name:gsub(" Dice$", "")),
						rarity = "Hypothetical",
						baseOdds = hypoOdds,
						baseDamage = hypoDmg,
						isHypothetical = true,
					}
					table.insert(extendedPool, hypoSword)
					print(string.format("  + Added %-28s | Odds: 1 in %-12s | Base Damage: %s", hypoSword.name, NumberFormat.format(hypoOdds), NumberFormat.format(hypoDmg)))
				end
			end
		end

		table.sort(extendedPool, function(a, b)
			return a.baseOdds > b.baseOdds
		end)

		finalReport = runProgressionSimulation(extendedPool, gMult, lMult, scopeLimit, cfFactor, "EXTENDED POOL WITH HYPOTHETICAL SWORDS")
	end

	return finalReport
end

return EconSim
