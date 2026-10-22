--!strict
-- Global game configuration constants (AI_GUIDE rule 3: data-driven design).

local Game = {
	Tap = {
		UnarmedDamage = 1, -- Base damage when no sword is equipped
		MaxTapsPerSecond = 10,
		BurstAllowanceMultiplier = 2, -- token bucket capacity = MaxTapsPerSecond * BurstAllowanceMultiplier
		CritChance = 0.10,
		CritMultiplier = 2.5,
	},
	Fever = {
		MaxPoints = 100,
		ChargePerTap = 1,
		Duration = 15, -- seconds of Fever Mode
		SpeedMultiplier = 2, -- 2x swing speed / tap rate limit
		CritChance = 1.0, -- 100% crit chance during Fever Mode
		LuckMultiplier = 1.5, -- +50% Total Luck
	},
	AutoTap = {
		BaseTapsPerSecond = 10, -- Base auto-tap rate (matches MaxTapsPerSecond)
	},
	Inventory = {
		MaxSwords = 50, -- Maximum number of swords a player can store
	},
	Plot = {
		MaxPlots = 8,
		DefaultPedestalsPerPlot = 4,
		PassiveRateMultiplier = 0.5, -- 50% Gold-per-tap every second
		OfflineIncomeCapSeconds = 8 * 3600, -- 8-hour cap (28,800 seconds)
		MinOfflineIncomePopupThreshold = 1, -- minimum Gold to trigger offline welcome popup
		MinOfflineSeconds = 60, -- minimum offline seconds required for popup
	},
}

return Game
