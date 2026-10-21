--!strict
-- Global game configuration constants (AI_GUIDE rule 3: data-driven design).

local Game = {
	Tap = {
		MaxTapsPerSecond = 10,
		BurstAllowanceMultiplier = 2, -- token bucket capacity = MaxTapsPerSecond * BurstAllowanceMultiplier
		CritChance = 0.10,
		CritMultiplier = 2.5,
	},
}

return Game
