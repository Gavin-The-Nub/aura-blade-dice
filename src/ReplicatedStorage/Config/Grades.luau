--!strict
-- Grade config (GDD section 5A).
-- Defines names, roll chances, multipliers, and badge colors as Theme token names.

export type GradeDef = {
	name: string,
	rollChance: number, -- percent (sum is 100.0)
	multiplier: number,
	badgeColor: string, -- Key in Theme.Colors, e.g. "AuraPurple"
	baseOdds: number?, -- Conditional waterfall base odds
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

-- Sort tiers by weight ascending explicitly (rarest first: Z+ -> Z -> SSS ... -> D)
local waterfallGrades: { GradeDef } = table.clone(list)
table.sort(waterfallGrades, function(a, b)
	return a.rollChance < b.rollChance
end)

-- Compute conditional waterfall baseOdds dynamically from Config weights:
-- For step i (from rarest down to second-most common):
-- baseOdds_i = remaining weight before tier / tier weight
-- The common fallback absorbs the remainder.
local remainingGradeWeight = 0
for _, def in waterfallGrades do
	remainingGradeWeight += def.rollChance
end

for i = 1, #waterfallGrades - 1 do
	local def = waterfallGrades[i]
	def.baseOdds = remainingGradeWeight / def.rollChance
	remainingGradeWeight -= def.rollChance
end

local mostCommonGrade = waterfallGrades[#waterfallGrades]
mostCommonGrade.baseOdds = 1.0

-- Analytic check: verify probabilities sum to 100.0% (1.0) at luck = 1.0
local function computeAnalyticProbSum(): number
	local runningMissProbability = 1.0
	local sum = 0.0
	for i = 1, #waterfallGrades - 1 do
		local def = waterfallGrades[i]
		local p = 1.0 / (def.baseOdds :: number)
		local prob = runningMissProbability * p
		sum += prob
		runningMissProbability *= (1.0 - p)
	end
	sum += runningMissProbability
	return sum
end

local analyticProbSum = computeAnalyticProbSum()
assert(math.abs(analyticProbSum - 1.0) < 1e-6, ("[Grades] Waterfall probabilities do not sum to 100%% (got %f)"):format(analyticProbSum))

function Grades.GetAnalyticSum(): number
	return analyticProbSum
end

function Grades.GetWaterfallList(): { GradeDef }
	return waterfallGrades
end

-- Performs a server-side waterfall roll with optional luck (defaults to 1.0)
function Grades.RollRandomGrade(luck: number?): GradeDef
	local effectiveLuck = if typeof(luck) == "number" and luck > 0 then luck else 1.0
	for i = 1, #waterfallGrades - 1 do
		local def = waterfallGrades[i]
		local effectiveOdds = math.max(1, (def.baseOdds :: number) / effectiveLuck)
		local chance = 1 / effectiveOdds
		if math.random() <= chance then
			return def
		end
	end
	return mostCommonGrade
end

function Grades.GetAll(): { GradeDef }
	return list
end

return Grades
