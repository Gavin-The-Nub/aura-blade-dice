--!strict
-- Sword config (GDD section 4). Structure only; data is added in a later task.

export type SwordDef = {
	id: string,
	name: string,
	rarity: string,
	baseOdds: number, -- the X in "1 in X"
	baseDamage: number, -- Gold per tap
}

-- TEMP: temporary test sword for TapService validation. Remove or replace in equip feature step.
local Swords: { SwordDef } = {
	{
		id = "test_sword",
		name = "Test Sword",
		rarity = "Common",
		baseOdds = 1,
		baseDamage = 1,
	},
}

return Swords
