--!strict
-- Config/Rebirths: Progression configuration and helper formulas for the Rebirth system.
-- All values below are marked PLACEHOLDER and will be replaced with verified Anime Dice data.

-- PLACEHOLDER: Maximum rebirth tier currently supported
local MAX_REBIRTHS = 15

-- PLACEHOLDER: Base gold cost for Rebirth 1
local BASE_COST = 250000

-- PLACEHOLDER: Cost scaling multiplier per tier (250,000 * 5^(n-1))
local COST_GROWTH_FACTOR = 5

-- PLACEHOLDER: Base starting pedestal slots
local BASE_PEDESTAL_SLOTS = 4

-- PLACEHOLDER: Rebirth milestones that grant +1 Pedestal Slot
local PEDESTAL_MILESTONES = { 3, 5, 7, 9, 10 }

local Rebirths = {
	MaxRebirths = MAX_REBIRTHS,
	BaseCost = BASE_COST,
	CostGrowthFactor = COST_GROWTH_FACTOR,
	BasePedestalSlots = BASE_PEDESTAL_SLOTS,
	PedestalMilestones = PEDESTAL_MILESTONES,
}

-- Returns the Gold cost required to execute rebirth n (where n is the next rebirth number, 1..MaxRebirths).
-- Formula: 250,000 * 5^(n-1) [PLACEHOLDER]
function Rebirths.GetCost(n: number): number
	if type(n) ~= "number" or n <= 0 then
		return 0
	end
	n = math.floor(n)
	return math.floor(BASE_COST * (COST_GROWTH_FACTOR ^ (n - 1)))
end

-- Returns the permanent Gold multiplier after n rebirths.
-- Formula: 1.0 + 0.5 * n [PLACEHOLDER]
function Rebirths.GetGoldMultiplier(n: number): number
	if type(n) ~= "number" or n <= 0 then
		return 1.0
	end
	return 1.0 + (0.5 * math.floor(n))
end

-- Returns the permanent Luck multiplier after n rebirths.
-- Rebirth Luck is kept at 1.0 for now pending Anime Dice data [PLACEHOLDER].
function Rebirths.GetLuckMultiplier(_n: number): number
	return 1.0
end

-- Returns the Gems granted upon reaching rebirth n.
-- Formula: 100 * n [PLACEHOLDER]
function Rebirths.GetGemsGrant(n: number): number
	if type(n) ~= "number" or n <= 0 then
		return 0
	end
	return 100 * math.floor(n)
end

-- Returns the milestone Pedestal Slots earned at rebirth level n.
-- Formula: 4 base + count of reached milestones {3, 5, 7, 9, 10} [PLACEHOLDER]
function Rebirths.GetPedestalSlots(n: number): number
	if type(n) ~= "number" or n <= 0 then
		return BASE_PEDESTAL_SLOTS
	end
	local count = 0
	for _, milestone in PEDESTAL_MILESTONES do
		if n >= milestone then
			count += 1
		end
	end
	return BASE_PEDESTAL_SLOTS + count
end

return Rebirths
