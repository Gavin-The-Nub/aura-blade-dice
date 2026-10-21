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
	{
		tier = 4,
		name = "Verdant Dice",
		cost = 75000,
		baseLuck = 20,
		rollCooldown = 2.8,
	},
	{
		tier = 5,
		name = "Volt Dice",
		cost = 500000,
		baseLuck = 42,
		rollCooldown = 2.8,
	},
	{
		tier = 6,
		name = "Glacier Dice",
		cost = 4000000,
		baseLuck = 100,
		rollCooldown = 2.7,
	},
	{
		tier = 7,
		name = "Magma Dice",
		cost = 30000000,
		baseLuck = 200,
		rollCooldown = 2.7,
	},
	{
		tier = 8,
		name = "Gale Dice",
		cost = 200000000,
		baseLuck = 450,
		rollCooldown = 2.6,
	},
	{
		tier = 9,
		name = "Sandstorm Dice",
		cost = 1500000000,
		baseLuck = 1000,
		rollCooldown = 2.6,
	},
	{
		tier = 10,
		name = "Phantom Dice",
		cost = 12000000000,
		baseLuck = 2250,
		rollCooldown = 2.5,
	},
}

return Dice
