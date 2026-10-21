--!strict
-- Sword config (GDD section 4). Structure only; data is added in a later task.

export type SwordDef = {
	id: string,
	name: string,
	rarity: string,
	baseOdds: number, -- the X in "1 in X"
	baseDamage: number, -- Gold per tap
	isTest: boolean?, -- if true, excluded from rolling pool
}

local RarityColors: { [string]: Color3 } = {
	Common = Color3.fromRGB(180, 190, 205),
	Uncommon = Color3.fromRGB(34, 197, 94),
	Rare = Color3.fromRGB(59, 130, 246),
	Epic = Color3.fromRGB(168, 85, 247),
	Legendary = Color3.fromRGB(255, 204, 0),
	Mythic = Color3.fromRGB(255, 64, 96),
	Secret = Color3.fromRGB(0, 229, 255),
}

-- Sample swords from GDD Section 4 (lines 85-94)
local Swords: { SwordDef } = {
	-- Line 85
	{
		id = "rusty_shortsword",
		name = "Rusty Shortsword",
		rarity = "Common",
		baseOdds = 2,
		baseDamage = 1,
	},
	-- Line 86
	{
		id = "wooden_training_blade",
		name = "Wooden Training Blade",
		rarity = "Common",
		baseOdds = 8,
		baseDamage = 3,
	},
	-- Line 87
	{
		id = "iron_broadsword",
		name = "Iron Broadsword",
		rarity = "Common",
		baseOdds = 35,
		baseDamage = 12,
	},
	-- Line 88
	{
		id = "ember_wakizashi",
		name = "Ember Wakizashi",
		rarity = "Uncommon",
		baseOdds = 150,
		baseDamage = 45,
	},
	-- Line 89
	{
		id = "static_katana",
		name = "Static Katana",
		rarity = "Rare",
		baseOdds = 1200,
		baseDamage = 280,
	},
	-- Line 90
	{
		id = "frostbite_claymore",
		name = "Frostbite Claymore",
		rarity = "Rare",
		baseOdds = 8500,
		baseDamage = 850,
	},
	-- Line 91
	{
		id = "cursed_blood_scythe",
		name = "Cursed Blood Scythe-Blade",
		rarity = "Epic",
		baseOdds = 38000,
		baseDamage = 2200,
	},
	-- Line 92
	{
		id = "thunderlord_greatsword",
		name = "Thunderlord Greatsword",
		rarity = "Epic",
		baseOdds = 290000,
		baseDamage = 9100,
	},
	-- Line 93
	{
		id = "solar_flare_saber",
		name = "Solar Flare Saber",
		rarity = "Legendary",
		baseOdds = 1500000,
		baseDamage = 32000,
	},
	-- Line 94
	{
		id = "chronos_clockwork_blade",
		name = "Chronos Clockwork Blade",
		rarity = "Legendary",
		baseOdds = 8500000,
		baseDamage = 115000,
	},

	-- TEMP: temporary test sword for TapService validation. Kept until equip feature step.
	{
		id = "test_sword",
		name = "Test Sword",
		rarity = "Common",
		baseOdds = 1,
		baseDamage = 1,
		isTest = true,
	},
}

local module = setmetatable({
	RarityColors = RarityColors,
}, {
	__iter = function()
		return ipairs(Swords)
	end,
	__len = function()
		return #Swords
	end,
	__index = function(_, key)
		return (Swords :: any)[key]
	end,
})

return module :: { SwordDef } & { RarityColors: { [string]: Color3 } }
