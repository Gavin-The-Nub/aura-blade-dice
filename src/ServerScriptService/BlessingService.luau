--!strict
-- BlessingService: Server-only aggregator for active Hilt Blessings.
-- Located at ServerScriptService root so Main.legacy.luau does not Start it.
-- GDD section 5C: Sums active blessings across equipped sword + placed pedestal swords.
-- Rules:
-- - Inspects only equipped uid plus placed uids up to player's current PedestalSlots (at most 12 swords)
-- - Counts each sword uid at most once (strict deduplication)
-- - No caching: re-reads fresh from DataService on every call
-- - Returns zero bonuses without erroring if player data is not loaded
-- - Clamps summed family bonuses against Config/Blessings.Caps

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Blessings = require(ReplicatedStorage.Config.Blessings)
local GameConfig = require(ReplicatedStorage.Config.Game)
local DataService = require(ServerScriptService.Services.DataService)

export type BlessingSource = {
	uid: string,
	swordId: string,
	slot: string, -- "Equipped" or "Pedestal Slot #X"
	blessing: string,
}

export type BlessingBonuses = {
	fortuneRaw: number,
	fortuneCapped: number,
	gradeRaw: number,
	gradeCapped: number,
	enchantRaw: number,
	enchantCapped: number,
	sources: { BlessingSource },
}

local ZERO_BONUSES: BlessingBonuses = table.freeze({
	fortuneRaw = 0,
	fortuneCapped = 0,
	gradeRaw = 0,
	gradeCapped = 0,
	enchantRaw = 0,
	enchantCapped = 0,
	sources = table.freeze({}),
})

local BlessingService = {}

-- Returns the full breakdown of aggregated raw and capped luck bonuses and contributing sources
function BlessingService.GetBonuses(player: Player, dataServiceOverride: any?): BlessingBonuses
	if player == nil then
		return ZERO_BONUSES
	end
	if typeof(player) == "Instance" and player.Parent ~= Players then
		return ZERO_BONUSES
	end

	local ds = dataServiceOverride or DataService

	if not ds.IsLoaded(player) then
		return ZERO_BONUSES
	end

	local owned = ds.Get(player, "OwnedSwords")
	if typeof(owned) ~= "table" then
		return ZERO_BONUSES
	end

	-- Map owned swords by uid for O(1) lookup
	local ownedMap: { [string]: any } = {}
	for _, entry in ipairs(owned) do
		if typeof(entry) == "table" and typeof(entry.uid) == "string" then
			ownedMap[entry.uid] = entry
		end
	end

	local equippedUid = ds.Get(player, "EquippedSword")
	local placed = ds.Get(player, "PlacedSwords")
	local placedMap = if typeof(placed) == "table" then placed else {}

	local defaultSlots = (GameConfig.Plot and GameConfig.Plot.DefaultPedestalsPerPlot) or 4
	local maxSlots = (GameConfig.Plot and GameConfig.Plot.MaxPedestals) or 11
	local rawSlots = ds.Get(player, "PedestalSlots")
	local activeSlots = math.clamp(
		if typeof(rawSlots) == "number" then rawSlots else defaultSlots,
		1,
		maxSlots
	)

	local seenUids: { [string]: boolean } = {}
	local sources: { BlessingSource } = {}
	local rawFortune = 0
	local rawGrade = 0
	local rawEnchant = 0

	local function processCandidate(uid: unknown, slotLabel: string)
		if typeof(uid) ~= "string" or uid == "" then
			return
		end
		if seenUids[uid] then
			return
		end
		seenUids[uid] = true

		local entry = ownedMap[uid]
		if not entry or typeof(entry.blessing) ~= "string" or entry.blessing == "" then
			return
		end

		local def = Blessings.GetBlessingDef(entry.blessing)
		if not def or not def.effectValues then
			return
		end

		table.insert(sources, {
			uid = uid,
			swordId = if typeof(entry.id) == "string" then entry.id else "sword",
			slot = slotLabel,
			blessing = def.name,
		})

		if def.family == "Fortune" then
			rawFortune += def.effectValues.rollLuck or 0
		elseif def.family == "Appraiser" then
			rawGrade += def.effectValues.gradeLuck or 0
		elseif def.family == "Enchanter" then
			rawEnchant += def.effectValues.enchantLuck or 0
		end
	end

	-- 1. Check equipped sword (at most 1)
	processCandidate(equippedUid, "Equipped")

	-- 2. Check placed pedestal swords up to current PedestalSlots (at most activeSlots <= 11)
	for slotNum = 1, activeSlots do
		local placedUid = placedMap[tostring(slotNum)]
		processCandidate(placedUid, ("Pedestal Slot #%d"):format(slotNum))
	end

	local caps = Blessings.Caps or { FortuneLuck = 1.0, GradeLuck = 1.0, EnchantLuck = 1.0 }
	local fortuneCap = caps.FortuneLuck or 1.0
	local gradeCap = caps.GradeLuck or 1.0
	local enchantCap = caps.EnchantLuck or 1.0

	return {
		fortuneRaw = rawFortune,
		fortuneCapped = math.min(rawFortune, fortuneCap),
		gradeRaw = rawGrade,
		gradeCapped = math.min(rawGrade, gradeCap),
		enchantRaw = rawEnchant,
		enchantCapped = math.min(rawEnchant, enchantCap),
		sources = sources,
	}
end

-- Returns capped Fortune bonus as a fraction (e.g. 0.25 for +25%, 0 if none)
function BlessingService.GetFortuneLuckBonus(player: Player): number
	return BlessingService.GetBonuses(player).fortuneCapped
end

-- Returns capped Grade bonus as a fraction (e.g. 0.20 for +20%, 0 if none)
function BlessingService.GetGradeLuckBonus(player: Player): number
	return BlessingService.GetBonuses(player).gradeCapped
end

-- Returns total Grade Luck multiplier: 1.0 + gradeLuckBonus (e.g. 1.20 for +20%)
function BlessingService.GetGradeLuck(player: Player): number
	return 1.0 + BlessingService.GetGradeLuckBonus(player)
end

-- Returns capped Enchant bonus as a fraction (e.g. 0.20 for +20%, 0 if none)
function BlessingService.GetEnchantLuckBonus(player: Player): number
	return BlessingService.GetBonuses(player).enchantCapped
end

-- Returns total Enchant Luck multiplier: 1.0 + enchantLuckBonus (e.g. 1.20 for +20%)
function BlessingService.GetEnchantLuck(player: Player): number
	return 1.0 + BlessingService.GetEnchantLuckBonus(player)
end

return BlessingService
