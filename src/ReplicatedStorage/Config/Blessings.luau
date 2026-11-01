--!strict
-- Config/Blessings: Central configuration for Hilt Blessings and Runesmith roll mechanics.
-- GDD section 5C: Blessings remain active whether the sword is equipped OR placed on a plot pedestal.
-- In this phase (11-1), data and manual rolls are implemented with NO gameplay effects yet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Dice = require(ReplicatedStorage.Config.Dice)

export type BlessingFamily = "Fortune" | "Greed" | "Appraiser" | "Enchanter" | "Swiftfoot"

export type BlessingDef = {
	name: string,
	family: BlessingFamily,
	tier: number?, -- 1, 2, 3 for tiered families (Fortune, Greed); nil for unique
	rollChance: number, -- percentage weight (sums to 100.0) - CLEARLY MARKED PLACEHOLDER
	badgeColor: string, -- Theme.Colors key name, e.g. "AuraCyan"
	effectValues: { [string]: number }, -- Data-only effect numbers
	effectText: string, -- Display description
}

-- Cost parameters: CLEARLY MARKED PLACEHOLDER
local MinCost = 500
local CostFraction = 0.005

local list: { BlessingDef } = {
	{
		name = "Fortune I",
		family = "Fortune",
		tier = 1,
		rollChance = 18.0, -- PLACEHOLDER
		badgeColor = "AuraCyan",
		effectValues = { rollLuck = 0.05 },
		effectText = "+5% Global Roll Luck",
	},
	{
		name = "Fortune II",
		family = "Fortune",
		tier = 2,
		rollChance = 8.0, -- PLACEHOLDER
		badgeColor = "AuraBlue",
		effectValues = { rollLuck = 0.12 },
		effectText = "+12% Global Roll Luck",
	},
	{
		name = "Fortune III",
		family = "Fortune",
		tier = 3,
		rollChance = 2.0, -- PLACEHOLDER
		badgeColor = "AuraGold",
		effectValues = { rollLuck = 0.25 },
		effectText = "+25% Global Roll Luck",
	},
	{
		name = "Greed I",
		family = "Greed",
		tier = 1,
		rollChance = 18.0, -- PLACEHOLDER
		badgeColor = "TextPrimary",
		effectValues = { goldMultiplier = 0.10 },
		effectText = "+10% Global Gold Earned",
	},
	{
		name = "Greed II",
		family = "Greed",
		tier = 2,
		rollChance = 8.0, -- PLACEHOLDER
		badgeColor = "AuraEmerald",
		effectValues = { goldMultiplier = 0.25 },
		effectText = "+25% Global Gold Earned",
	},
	{
		name = "Greed III",
		family = "Greed",
		tier = 3,
		rollChance = 2.0, -- PLACEHOLDER
		badgeColor = "AuraGold",
		effectValues = { goldMultiplier = 0.50 },
		effectText = "+50% Global Gold Earned",
	},
	{
		name = "Appraiser's Eye",
		family = "Appraiser",
		tier = nil,
		rollChance = 15.0, -- PLACEHOLDER
		badgeColor = "AuraPurple",
		effectValues = { gradeLuck = 0.20 },
		effectText = "+20% Luck when rolling Grades",
	},
	{
		name = "Enchanter's Soul",
		family = "Enchanter",
		tier = nil,
		rollChance = 15.0, -- PLACEHOLDER
		badgeColor = "AuraPurple",
		effectValues = { enchantLuck = 0.20 },
		effectText = "+20% Luck when rolling Enchants",
	},
	{
		name = "Swiftfoot",
		family = "Swiftfoot",
		tier = nil,
		rollChance = 14.0, -- PLACEHOLDER
		badgeColor = "AuraEmerald",
		effectValues = { walkSpeed = 0.15, autoTapSpeed = 0.10 },
		effectText = "+15% WalkSpeed, +10% Auto-Tap Speed",
	},
}

-- Fast lookup map by blessing name
local defMap: { [string]: BlessingDef } = {}
for _, def in list do
	defMap[def.name] = def
end

-- Ranks for ordering / UI display / tier detection
local ranks: { [string]: number } = {
	["Fortune I"] = 1,
	["Fortune II"] = 2,
	["Fortune III"] = 3,
	["Greed I"] = 1,
	["Greed II"] = 2,
	["Greed III"] = 3,
	["Appraiser's Eye"] = 2,
	["Enchanter's Soul"] = 2,
	["Swiftfoot"] = 2,
}

local Blessings = {}
Blessings.List = list
Blessings.MinCost = MinCost
Blessings.CostFraction = CostFraction

function Blessings.GetBlessingDef(name: string?): BlessingDef?
	if name == nil or name == "" then
		return nil
	end
	return defMap[name]
end

function Blessings.GetRank(name: string?): number
	if name == nil or name == "" then
		return 0
	end
	return ranks[name] or 0
end

-- Returns true if this blessing is a top-tier blessing requiring user confirmation before rerolling
function Blessings.IsTierIII(name: string?): boolean
	if name == nil or name == "" then
		return false
	end
	local def = defMap[name]
	return def ~= nil and def.tier == 3
end

-- Roll random blessing according to weights (sums to 100.0)
function Blessings.RollRandomBlessing(): BlessingDef
	local roll = math.random() * 100.0
	local cumulative = 0
	for _, def in list do
		cumulative += def.rollChance
		if roll <= cumulative then
			return def
		end
	end
	return list[#list]
end

-- Computes blessing roll cost given player's highest owned dice tier:
-- cost = math.floor(math.max(MinCost, CostFraction * price))
-- Price is taken from next Dice tier above highest owned, or last tier if all owned.
function Blessings.CalculateCost(highestOwnedTier: number): (number, number, number)
	local totalTiers = #Dice
	local clampedTier = math.clamp(highestOwnedTier, 1, totalTiers)
	local targetTier = if clampedTier < totalTiers then (clampedTier + 1) else totalTiers
	local targetPrice = Dice[targetTier] and Dice[targetTier].cost or 0
	local cost = math.floor(math.max(MinCost, CostFraction * targetPrice))
	return cost, targetTier, targetPrice
end

return Blessings
