--!strict
-- Enchant config (GDD section 5B).
-- Defines names, roll chances, multipliers, badge colors as Theme token names,
-- and bonus passive effects (data-only for now; only Gold multiplier is applied in this build).

export type EnchantDef = {
	name: string,
	rollChance: number, -- percent (sum is 100.0)
	multiplier: number, -- Gold & Damage multiplier
	badgeColor: string, -- Key in Theme.Colors, e.g. "AuraPurple"
	effectText: string, -- Bonus passive effect description
}

local list: { EnchantDef } = {
	{
		name = "Sharpness",
		rollChance = 40.0,
		multiplier = 1.2,
		badgeColor = "TextMuted",
		effectText = "+5% Swing Speed",
	},
	{
		name = "Berserker",
		rollChance = 25.0,
		multiplier = 1.6,
		badgeColor = "TextPrimary",
		effectText = "+10% Crit Chance",
	},
	{
		name = "Vampiric",
		rollChance = 15.0,
		multiplier = 2.2,
		badgeColor = "AuraEmerald",
		effectText = "+15% Fever Bar Charge Rate",
	},
	{
		name = "Executioner",
		rollChance = 10.0,
		multiplier = 3.5,
		badgeColor = "AuraBlue",
		effectText = "+25% Boss & Trial Damage",
	},
	{
		name = "Ronin",
		rollChance = 6.0,
		multiplier = 6.0,
		badgeColor = "AuraPurple",
		effectText = "+20% Swing Speed & Double Slash chance",
	},
	{
		name = "Sovereign",
		rollChance = 2.8,
		multiplier = 12.0,
		badgeColor = "AuraGold",
		effectText = "+35% Crit Chance & +15% Base Luck",
	},
	{
		name = "Transcendent",
		rollChance = 1.0,
		multiplier = 28.0,
		badgeColor = "AuraCrimson",
		effectText = "Every 3rd tap deals 3x Damage",
	},
	{
		name = "Genesis",
		rollChance = 0.18,
		multiplier = 75.0,
		badgeColor = "AuraCyan",
		effectText = "+50% Swing Speed & +50% Total Luck",
	},
	{
		name = "Singularity",
		rollChance = 0.02,
		multiplier = 150.0,
		badgeColor = "AuraRainbow",
		effectText = "2x All Sword Stats & Instant Fever Recovery",
	},
}

local enchantMap: { [string]: EnchantDef } = {}
local rankMap: { [string]: number } = {}

for rank, def in ipairs(list) do
	enchantMap[def.name] = def
	rankMap[def.name] = rank
end

local Enchants = {}

-- Array access (1 = Sharpness, ..., 9 = Singularity)
for i, def in ipairs(list) do
	(Enchants :: any)[i] = def
end

function Enchants.GetEnchantDef(enchantName: string?): EnchantDef?
	if typeof(enchantName) ~= "string" or enchantName == "" then
		return nil
	end
	return enchantMap[enchantName]
end

function Enchants.GetMultiplier(enchantName: string?): number
	if typeof(enchantName) ~= "string" or enchantName == "" then
		return 1.0
	end
	local def = enchantMap[enchantName]
	if def then
		return def.multiplier
	end
	return 1.0
end

-- Returns 1..9 for valid enchants, 0 for missing/unenchanted/invalid.
function Enchants.GetRank(enchantName: string?): number
	if typeof(enchantName) ~= "string" or enchantName == "" then
		return 0
	end
	return rankMap[enchantName] or 0
end

-- Returns true if enchant is Sovereign or better (Sovereign, Transcendent, Genesis, Singularity)
function Enchants.IsHighEnchant(enchantName: string?): boolean
	local rank = Enchants.GetRank(enchantName)
	return rank >= 6 -- 6 is Sovereign
end

-- Computes the expected Tokens (1 / probability of rolling target enchant or better)
function Enchants.GetExpectedTokens(targetEnchant: string?): number
	local targetRank = Enchants.GetRank(targetEnchant)
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
function Enchants.RollRandomEnchant(): EnchantDef
	-- Total weight is 100.0 (40 + 25 + 15 + 10 + 6 + 2.8 + 1 + 0.18 + 0.02)
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

function Enchants.GetAll(): { EnchantDef }
	return list
end

return Enchants
