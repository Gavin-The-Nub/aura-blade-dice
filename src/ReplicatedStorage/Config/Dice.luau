--!strict
-- Dice ladder config (GDD section 3). Structure only; data is added in a later task.

export type DiceDef = {
	tier: number,
	name: string,
	cost: number, -- Gold
	baseLuck: number,
	rollCooldown: number, -- seconds
}

local Dice: { DiceDef } = {
	{
		tier = 1,
		name = "Basic Dice",
		cost = 0,
		baseLuck = 1,
		rollCooldown = 3.0,
	},
	{
		tier = 2,
		name = "Ember Dice",
		cost = 2500,
		baseLuck = 5,
		rollCooldown = 2.9,
	},
	{
		tier = 3,
		name = "Tide Dice",
		cost = 10000,
		baseLuck = 10,
		rollCooldown = 2.9,
	},
}

return Dice
