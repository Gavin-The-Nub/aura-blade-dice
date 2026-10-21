--!strict
-- Sword config (GDD section 4). Structure only; data is added in a later task.

export type SwordDef = {
	id: string,
	name: string,
	rarity: string,
	baseOdds: number, -- the X in "1 in X"
	baseDamage: number, -- Gold per tap
}

local Swords: { SwordDef } = {}

return Swords
