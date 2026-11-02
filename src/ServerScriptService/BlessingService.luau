--!strict
-- BlessingService: Server-only aggregator for active Hilt Blessings.
-- Located at ServerScriptService root so Main.legacy.luau does not Start it.
-- GDD section 5C: Sums active blessings across equipped sword + placed pedestal swords.
-- Rules:
-- - Inspects only equipped uid plus placed uids up to player's current PedestalSlots (at most 12 swords)
-- - Counts each sword uid at most once (strict deduplication)
-- - Per-player cache: invalidates on equip, place, unplace, blessing roll, sell, pedestal slots change, and profile load
-- - Never caches when player data is not loaded; never caches ZERO_BONUSES
-- - Freezes cached table and its sources list for immutability
-- - Returns zero bonuses without erroring if player data is not loaded
-- - Clamps summed family bonuses against Config/Blessings.Caps
-- - Server-side WalkSpeed application on CharacterAdded, respawn, and blessing changes

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
	greedRaw: number,
	greedCapped: number,
	gradeRaw: number,
	gradeCapped: number,
	enchantRaw: number,
	enchantCapped: number,
	swiftWalkRaw: number,
	swiftWalkCapped: number,
	swiftTapRaw: number,
	swiftTapCapped: number,
	sources: { BlessingSource },
}

local ZERO_BONUSES: BlessingBonuses = table.freeze({
	fortuneRaw = 0,
	fortuneCapped = 0,
	greedRaw = 0,
	greedCapped = 0,
	gradeRaw = 0,
	gradeCapped = 0,
	enchantRaw = 0,
	enchantCapped = 0,
	swiftWalkRaw = 0,
	swiftWalkCapped = 0,
	swiftTapRaw = 0,
	swiftTapCapped = 0,
	sources = table.freeze({}),
})

local cachedBonuses: { [Player]: BlessingBonuses } = {}

local BlessingService = {}

-- Invalidates the cached blessing bonuses for a player
function BlessingService.InvalidateCache(player: Player)
	if player ~= nil then
		cachedBonuses[player] = nil
	end
end

-- Returns the full breakdown of aggregated raw and capped luck/gold/swiftfoot bonuses and contributing sources
function BlessingService.GetBonuses(player: Player, dataServiceOverride: any?): BlessingBonuses
	if player == nil then
		return ZERO_BONUSES
	end
	if typeof(player) == "Instance" and player.Parent ~= Players then
		return ZERO_BONUSES
	end

	-- Fast-path cached lookup when not in test-override mode
	if dataServiceOverride == nil then
		local cached = cachedBonuses[player]
		if cached ~= nil then
			return cached
		end
	end

	local ds = dataServiceOverride or DataService

	-- NEVER cache when data is not loaded, and NEVER cache ZERO_BONUSES
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
	local rawGreed = 0
	local rawGrade = 0
	local rawEnchant = 0
	local rawSwiftWalk = 0
	local rawSwiftTap = 0

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
		elseif def.family == "Greed" then
			rawGreed += def.effectValues.goldMultiplier or 0
		elseif def.family == "Appraiser" then
			rawGrade += def.effectValues.gradeLuck or 0
		elseif def.family == "Enchanter" then
			rawEnchant += def.effectValues.enchantLuck or 0
		elseif def.family == "Swiftfoot" then
			rawSwiftWalk += def.effectValues.walkSpeed or 0
			rawSwiftTap += def.effectValues.autoTapSpeed or 0
		end
	end

	-- 1. Check equipped sword (at most 1)
	processCandidate(equippedUid, "Equipped")

	-- 2. Check placed pedestal swords up to current PedestalSlots (at most activeSlots <= 11)
	for slotNum = 1, activeSlots do
		local placedUid = placedMap[tostring(slotNum)]
		processCandidate(placedUid, ("Pedestal Slot #%d"):format(slotNum))
	end

	local caps = Blessings.Caps or {
		FortuneLuck = 1.0,
		GradeLuck = 1.0,
		EnchantLuck = 1.0,
		GreedGold = 2.0,
		SwiftfootWalk = 0.5,
		SwiftfootAutoTap = 0.5,
	}
	local fortuneCap = caps.FortuneLuck or 1.0
	local greedCap = caps.GreedGold or 2.0
	local gradeCap = caps.GradeLuck or 1.0
	local enchantCap = caps.EnchantLuck or 1.0
	local swiftWalkCap = caps.SwiftfootWalk or 0.5
	local swiftTapCap = caps.SwiftfootAutoTap or 0.5

	local result: BlessingBonuses = table.freeze({
		fortuneRaw = rawFortune,
		fortuneCapped = math.min(rawFortune, fortuneCap),
		greedRaw = rawGreed,
		greedCapped = math.min(rawGreed, greedCap),
		gradeRaw = rawGrade,
		gradeCapped = math.min(rawGrade, gradeCap),
		enchantRaw = rawEnchant,
		enchantCapped = math.min(rawEnchant, enchantCap),
		swiftWalkRaw = rawSwiftWalk,
		swiftWalkCapped = math.min(rawSwiftWalk, swiftWalkCap),
		swiftTapRaw = rawSwiftTap,
		swiftTapCapped = math.min(rawSwiftTap, swiftTapCap),
		sources = table.freeze(sources),
	})

	if dataServiceOverride == nil then
		cachedBonuses[player] = result
	end

	return result
end

-- Returns capped Fortune bonus as a fraction (e.g. 0.25 for +25%, 0 if none)
function BlessingService.GetFortuneLuckBonus(player: Player): number
	return BlessingService.GetBonuses(player).fortuneCapped
end

-- Returns capped Greed bonus as a fraction (e.g. 0.50 for +50%, 0 if none)
function BlessingService.GetGreedBonus(player: Player): number
	return BlessingService.GetBonuses(player).greedCapped
end

-- Returns total Greed Gold multiplier: 1.0 + greedBonus (e.g. 1.50 for +50%)
function BlessingService.GetGreedMultiplier(player: Player): number
	return 1.0 + BlessingService.GetGreedBonus(player)
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

-- Returns capped Swiftfoot WalkSpeed bonus as a fraction (e.g. 0.15 for +15%, 0 if none)
function BlessingService.GetSwiftWalkBonus(player: Player): number
	return BlessingService.GetBonuses(player).swiftWalkCapped
end

-- Returns total WalkSpeed multiplier: 1.0 + swiftWalkBonus (e.g. 1.15 for +15%)
function BlessingService.GetSwiftWalkMultiplier(player: Player): number
	return 1.0 + BlessingService.GetSwiftWalkBonus(player)
end

-- Returns capped Swiftfoot Auto-Tap speed bonus as a fraction (e.g. 0.10 for +10%, 0 if none)
function BlessingService.GetSwiftTapBonus(player: Player): number
	return BlessingService.GetBonuses(player).swiftTapCapped
end

-- Returns total Auto-Tap speed multiplier: 1.0 + swiftTapBonus (e.g. 1.10 for +10%)
function BlessingService.GetSwiftTapMultiplier(player: Player): number
	return 1.0 + BlessingService.GetSwiftTapBonus(player)
end

-- Server-side WalkSpeed application directly to player's Humanoid
local function applyPlayerWalkSpeed(player: Player)
	if player == nil or player.Parent ~= Players then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local baseSpeed = (GameConfig.Player and GameConfig.Player.BaseWalkSpeed) or 16
	local bonus = BlessingService.GetSwiftWalkBonus(player)
	humanoid.WalkSpeed = baseSpeed * (1 + bonus)
end

function BlessingService.ApplyWalkSpeed(player: Player)
	applyPlayerWalkSpeed(player)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if humanoid then
		applyPlayerWalkSpeed(player)
	end
end

local function setupPlayer(player: Player)
	BlessingService.InvalidateCache(player)

	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end

	task.spawn(function()
		if DataService.WaitForProfile(player) then
			BlessingService.InvalidateCache(player)
			applyPlayerWalkSpeed(player)
		end
	end)
end

-- Lifecycle invalidation and WalkSpeed connections established immediately upon require:
DataService.Changed:Connect(function(player: Player, key: string, _value: any)
	if key == "EquippedSword" or key == "PlacedSwords" or key == "PedestalSlots" or key == "OwnedSwords" then
		BlessingService.InvalidateCache(player)
		applyPlayerWalkSpeed(player)
	end
end)

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	cachedBonuses[player] = nil
end)

return BlessingService
