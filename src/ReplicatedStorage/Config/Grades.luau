--!strict
-- Grade config (GDD section 5A). Structure only; data is added in a later task.

export type GradeDef = {
	name: string,
	rollChance: number, -- percent
	multiplier: number,
	badgeColor: string,
}

local Grades: { GradeDef } = {}

return Grades
