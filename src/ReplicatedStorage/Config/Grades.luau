--!strict
-- Grade config (GDD section 5A).
-- Defines names, roll chances, multipliers, and badge colors as Theme token names.

export type GradeDef = {
	name: string,
	rollChance: number, -- percent (sum is 100.0)
	multiplier: number,
	badgeColor: string, -- Key in Theme.Colors, e.g. "AuraPurple"
}

local list: { GradeDef } = {
	{
		name = "D",
		rollChance = 35.0,
		multiplier = 1.0,
		badgeColor = "TextMuted",
	},
	{
		name = "C",
		rollChance = 25.0,
		multiplier = 1.25,
		badgeColor = "TextPrimary",
	},
	{
		name = "B",
		rollChance = 18.0,
		multiplier = 1.5,
		badgeColor = "AuraEmerald",
	},
	{
		name = "A",
		rollChance = 12.0,
		multiplier = 2.0,
		badgeColor = "AuraBlue",
	},
	{
		name = "S",
		rollChance = 6.5,
		multiplier = 3.0,
		badgeColor = "AuraPurple",
	},
	{
		name = "SS",
		rollChance = 2.5,
		multiplier = 5.0,
		badgeColor = "AuraGold",
	},
	{
		name = "SSS",
		rollChance = 0.85,
		multiplier = 8.5,
		badgeColor = "AuraCrimson",
	},
	{
		name = "Z",
		rollChance = 0.14,
		multiplier = 15.0,
		badgeColor = "AuraCyan",
	},
	{
		name = "Z+",
		rollChance = 0.01,
		multiplier = 30.0,
		badgeColor = "AuraRainbow",
	},
}

local gradeMap: { [string]: GradeDef } = {}
local rankMap: { [string]: number } = {}

for rank, def in ipairs(list) do
	gradeMap[def.name] = def
	rankMap[def.name] = rank
end

local Grades = {}

-- Array access (1 = D, ..., 9 = Z+)
for i, def in ipairs(list) do
	(Grades :: any)[i] = def
end

function Grades.GetGradeDef(gradeName: string?): GradeDef?
	if typeof(gradeName) ~= "string" or gradeName == "" then
		return nil
	end
	return gradeMap[gradeName]
end

function Grades.GetMultiplier(gradeName: string?): number
	if typeof(gradeName) ~= "string" or gradeName == "" then
		return 1.0
	end
	local def = gradeMap[gradeName]
	if def then
		return def.multiplier
	end
	return 1.0
end

-- Returns 1..9 for valid grades, 0 for missing/ungraded/invalid.
function Grades.GetRank(gradeName: string?): number
	if typeof(gradeName) ~= "string" or gradeName == "" then
		return 0
	end
	return rankMap[gradeName] or 0
end

-- Returns true if grade is S or better (S, SS, SSS, Z, Z+)
function Grades.IsHighGrade(gradeName: string?): boolean
	local rank = Grades.GetRank(gradeName)
	return rank >= 5 -- 5 is S
end

-- Computes the expected Gems (1 / probability of rolling target grade or better)
function Grades.GetExpectedGems(targetGrade: string?): number
	local targetRank = Grades.GetRank(targetGrade)
	if targetRank == 0 then
		return 1
	end
	local totalChance = 0
	for _, def in ipairs(list) do
		if (rankMap[def.name] or 0) >= targetRank then
			totalChance += def.rollChance
		end
	end
	if totalChance <= 0 then
		return 1
	end
	return 100 / totalChance
end

-- Performs a server-side weighted roll using Config chances
function Grades.RollRandomGrade(): GradeDef
	-- Total weight is 100.0 (35 + 25 + 18 + 12 + 6.5 + 2.5 + 0.85 + 0.14 + 0.01)
	local roll = math.random() * 100.0
	local cumulative = 0.0
	for _, def in ipairs(list) do
		cumulative += def.rollChance
		if roll <= cumulative then
			return def
		end
	end
	return list[#list]
end

function Grades.GetAll(): { GradeDef }
	return list
end

return Grades
