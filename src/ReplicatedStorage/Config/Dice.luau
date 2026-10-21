--!strict
-- Dice ladder config (GDD section 3). Structure only; data is added in a later task.

export type DiceDef = {
	tier: number,
	name: string,
	cost: number, -- Gold
	baseLuck: number,
	rollCooldown: number, -- seconds
}

local Dice: { DiceDef } = {}

return Dice
