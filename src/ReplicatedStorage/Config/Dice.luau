--!strict
-- Dice ladder config (GDD section 3): 29-tier Anime Dice progression ladder.
-- Roll cooldown is a global constant in Config/Game (Dice no longer alter cooldown).

export type DiceDef = {
	tier: number,
	name: string,
	cost: number, -- Gold
	baseLuck: number,
}

local Dice: { DiceDef } = {
	{
		tier = 1,
		name = "Basic Dice",
		cost = 0,
		baseLuck = 1,
	},
	{
		tier = 2,
		name = "Ember Dice",
		cost = 2500,
		baseLuck = 5,
	},
	{
		tier = 3,
		name = "Tide Dice",
		cost = 10000,
		baseLuck = 10,
	},
	{
		tier = 4,
		name = "Verdant Dice",
		cost = 75000,
		baseLuck = 20,
	},
	{
		tier = 5,
		name = "Volt Dice",
		cost = 500000,
		baseLuck = 42,
	},
	{
		tier = 6,
		name = "Glacier Dice",
		cost = 4e6,
		baseLuck = 100,
	},
	{
		tier = 7,
		name = "Magma Dice",
		cost = 30e6,
		baseLuck = 200,
	},
	{
		tier = 8,
		name = "Gale Dice",
		cost = 200e6,
		baseLuck = 400,
	},
	{
		tier = 9,
		name = "Sandstorm Dice",
		cost = 1.5e9,
		baseLuck = 750,
	},
	{
		tier = 10,
		name = "Phantom Dice",
		cost = 12e9,
		baseLuck = 1500,
	},
	{
		tier = 11,
		name = "Bloodforged Dice",
		cost = 100e9,
		baseLuck = 3000,
	},
	{
		tier = 12,
		name = "Solaris Dice",
		cost = 750e9,
		baseLuck = 6000,
	},
	{
		tier = 13,
		name = "Lunaris Dice",
		cost = 5e12,
		baseLuck = 12500,
	},
	{
		tier = 14,
		name = "Gravity Dice",
		cost = 37e12,
		baseLuck = 25000,
	},
	{
		tier = 15,
		name = "Venomspire Dice",
		cost = 150e12,
		baseLuck = 50000,
	},
	{
		tier = 16,
		name = "Cybernetic Dice",
		cost = 1e15,
		baseLuck = 100000,
	},
	{
		tier = 17,
		name = "Dragonheart Dice",
		cost = 8.5e15,
		baseLuck = 200000,
	},
	{
		tier = 18,
		name = "Runic Dice",
		cost = 100e15,
		baseLuck = 400000,
	},
	{
		tier = 19,
		name = "Nebula Dice",
		cost = 1e18,
		baseLuck = 1e6,
	},
	{
		tier = 20,
		name = "Chronos Dice",
		cost = 12e18,
		baseLuck = 2e6,
	},
	{
		tier = 21,
		name = "Abyssal Dice",
		cost = 150e18,
		baseLuck = 5e6,
	},
	{
		tier = 22,
		name = "Seraphic Dice",
		cost = 1e21,
		baseLuck = 10e6,
	},
	{
		tier = 23,
		name = "Dimension Dice",
		cost = 15e21,
		baseLuck = 25e6,
	},
	{
		tier = 24,
		name = "Singularity Dice",
		cost = 100e21,
		baseLuck = 62.5e6,
	},
	{
		tier = 25,
		name = "Omniversal Dice",
		cost = 750e21,
		baseLuck = 150e6,
	},
	{
		tier = 26,
		name = "Astral Dice",
		cost = 10e24,
		baseLuck = 375e6,
	},
	{
		tier = 27,
		name = "Eternal Dice",
		cost = 250e24,
		baseLuck = 950e6,
	},
	{
		tier = 28,
		name = "Infinity Dice",
		cost = 5e27,
		baseLuck = 2e9,
	},
	{
		tier = 29,
		name = "Zenith Dice",
		cost = 100e27,
		baseLuck = 5e9,
	},
}

return Dice
