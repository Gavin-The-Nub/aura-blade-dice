--!strict
-- TapService: Handles player tap inputs, rate limiting (token bucket with burst),
-- gold calculation from equipped sword + crits, saves gold via DataService,
-- manages server-driven Auto-Tap, and tracks the 100-point Fever Meter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Config.Game)
local Swords = require(ReplicatedStorage.Config.Swords)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(ServerScriptService.Services.DataService)

type Bucket = {
	tokens: number,
	lastRefill: number,
}

type FeverState = {
	points: number,
	isActive: boolean,
	endTime: number,
}

local playerBuckets: { [Player]: Bucket } = {}
local playerFever: { [Player]: FeverState } = {}
local feverThreads: { [Player]: thread } = {}
local autoTapActive: { [Player]: boolean } = {}
local autoTapThreads: { [Player]: thread } = {}
local playerEquippedDamage: { [Player]: number } = {}
local playerEquippedGoldPerTap: { [Player]: number } = {}
local playerEquippedEntry: { [Player]: any } = {}

local TapService = {}

-- Indexed sword lookup cache
local swordMap: { [string]: Swords.SwordDef } = {}
for _, def in Swords do
	swordMap[def.id] = def
end

-- Calculates expected Gold per tap with NO crit, NO Fever, and NO random effects.
-- Base Damage × Grade × Enchant × Rebirth
-- Active tapping and passive pedestal income both call this.
function TapService.CalculateSwordGoldPerTap(player: Player, swordEntry: any): number
	local baseDamage = GameConfig.Tap.UnarmedDamage
	if type(swordEntry) == "table" then
		local swordId = swordEntry.id
		if type(swordId) == "string" then
			local swordDef = swordMap[swordId]
			if swordDef and type(swordDef.baseDamage) == "number" then
				baseDamage = swordDef.baseDamage
			end
		end
	elseif type(swordEntry) == "string" then
		local swordDef = swordMap[swordEntry]
		if swordDef and type(swordDef.baseDamage) == "number" then
			baseDamage = swordDef.baseDamage
		end
	end

	-- Multipliers (placeholders for future systems: Grade, Enchant, Rebirth)
	local gradeMult = 1
	local enchantMult = 1
	local rebirthMult = 1

	return baseDamage * gradeMult * enchantMult * rebirthMult
end

local function updateEquippedDamageCache(player: Player)
	if not DataService.IsLoaded(player) then
		playerEquippedDamage[player] = GameConfig.Tap.UnarmedDamage
		playerEquippedGoldPerTap[player] = GameConfig.Tap.UnarmedDamage
		playerEquippedEntry[player] = nil
		return
	end

	local equippedUid = DataService.Get(player, "EquippedSword")
	if type(equippedUid) ~= "string" or equippedUid == "" then
		playerEquippedDamage[player] = GameConfig.Tap.UnarmedDamage
		playerEquippedGoldPerTap[player] = GameConfig.Tap.UnarmedDamage
		playerEquippedEntry[player] = nil
		return
	end

	local ownedSwords = DataService.Get(player, "OwnedSwords")
	local foundEntry = nil
	if type(ownedSwords) == "table" then
		for _, entry in ownedSwords do
			if type(entry) == "table" and entry.uid == equippedUid then
				foundEntry = entry
				break
			end
		end
	end

	playerEquippedEntry[player] = foundEntry
	if foundEntry and type(foundEntry.id) == "string" then
		local swordDef = swordMap[foundEntry.id]
		if swordDef then
			playerEquippedDamage[player] = swordDef.baseDamage
			playerEquippedGoldPerTap[player] = TapService.CalculateSwordGoldPerTap(player, foundEntry)
			return
		end
	end

	playerEquippedDamage[player] = GameConfig.Tap.UnarmedDamage
	playerEquippedGoldPerTap[player] = GameConfig.Tap.UnarmedDamage
end

function TapService.GetEquippedDamage(player: Player): number
	local damage = playerEquippedDamage[player]
	if damage == nil then
		updateEquippedDamageCache(player)
		damage = playerEquippedDamage[player] or GameConfig.Tap.UnarmedDamage
	end
	return damage
end

function TapService.GetEquippedEntry(player: Player): any?
	return playerEquippedEntry[player]
end

function TapService.RefreshEquippedDamage(player: Player)
	updateEquippedDamageCache(player)
end

local function getFeverState(player: Player): FeverState
	local state = playerFever[player]
	if not state then
		state = {
			points = 0,
			isActive = false,
			endTime = 0,
		}
		playerFever[player] = state
	end
	return state
end

local function isFeverActive(player: Player): boolean
	local state = playerFever[player]
	if not state or not state.isActive then
		return false
	end
	if os.clock() >= state.endTime then
		return false
	end
	return true
end

function TapService.IsFeverActive(player: Player): boolean
	return isFeverActive(player)
end

function TapService.IsAutoTapActive(player: Player): boolean
	return autoTapActive[player] == true
end

-- Returns the max tap rate per second for a player (2x during Fever Mode)
function TapService.getMaxTapRate(player: Player): number
	local rate = GameConfig.Tap.MaxTapsPerSecond
	if isFeverActive(player) then
		rate *= GameConfig.Fever.SpeedMultiplier
	end
	return rate
end

-- Global luck multiplier contribution from Fever (+50% during Fever Mode)
function TapService.GetLuckMultiplier(player: Player): number
	if isFeverActive(player) then
		return GameConfig.Fever.LuckMultiplier
	end
	return 1.0
end

local function sendFeverUpdate(player: Player)
	if player.Parent ~= Players then
		return
	end
	local fever = getFeverState(player)
	local remaining = if fever.isActive then math.max(0, fever.endTime - os.clock()) else 0
	local event = Remotes.getEvent("FeverUpdated")
	event:FireClient(player, fever.points, GameConfig.Fever.MaxPoints, fever.isActive, remaining)
end

local function endFever(player: Player)
	if feverThreads[player] then
		task.cancel(feverThreads[player])
		feverThreads[player] = nil
	end

	local fever = getFeverState(player)
	fever.isActive = false
	fever.points = 0
	fever.endTime = 0

	sendFeverUpdate(player)
end

local function startFever(player: Player)
	if feverThreads[player] then
		task.cancel(feverThreads[player])
		feverThreads[player] = nil
	end

	local fever = getFeverState(player)
	fever.isActive = true
	fever.points = GameConfig.Fever.MaxPoints
	fever.endTime = os.clock() + GameConfig.Fever.Duration

	sendFeverUpdate(player)

	feverThreads[player] = task.delay(GameConfig.Fever.Duration, function()
		feverThreads[player] = nil
		if player.Parent == Players then
			endFever(player)
		end
	end)
end

function TapService.TriggerFever(player: Player)
	startFever(player)
end

function TapService.SetFeverPoints(player: Player, points: number)
	local fever = getFeverState(player)
	if fever.isActive then
		return
	end
	fever.points = math.clamp(points, 0, GameConfig.Fever.MaxPoints)
	if fever.points >= GameConfig.Fever.MaxPoints then
		startFever(player)
	else
		sendFeverUpdate(player)
	end
end

-- Token bucket rate limiter check with burst allowance
local function consumeTapToken(player: Player): boolean
	local now = os.clock()
	local rate = TapService.getMaxTapRate(player)
	local capacity = rate * GameConfig.Tap.BurstAllowanceMultiplier

	local bucket = playerBuckets[player]
	if not bucket then
		bucket = {
			tokens = capacity,
			lastRefill = now,
		}
		playerBuckets[player] = bucket
	else
		local elapsed = now - bucket.lastRefill
		bucket.tokens = math.min(capacity, bucket.tokens + (elapsed * rate))
		bucket.lastRefill = now
	end

	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end

	return false
end

-- Calculates gold per tap: Base Damage × Grade × Enchant × Rebirth × Crit
local function calculateTapEarnings(player: Player): (number, boolean)
	local baseGold = playerEquippedGoldPerTap[player]
	if baseGold == nil then
		updateEquippedDamageCache(player)
		baseGold = playerEquippedGoldPerTap[player] or GameConfig.Tap.UnarmedDamage
	end

	-- Crit calculation: 10% base chance for 2.5x multiplier, or 100% in Fever Mode
	local feverActive = isFeverActive(player)
	local critChance = if feverActive then GameConfig.Fever.CritChance else GameConfig.Tap.CritChance
	local isCrit = math.random() < critChance
	local critBonus = if isCrit then GameConfig.Tap.CritMultiplier else 1

	local goldEarned = baseGold * critBonus
	return goldEarned, isCrit
end

-- Unified tap processing (used by both manual tap and server auto-tap)
local function executeTap(player: Player): boolean
	local isLoaded = DataService.IsLoaded(player)
	if not isLoaded then
		return false
	end

	-- Enforce server-side rate limit
	if not consumeTapToken(player) then
		return false
	end

	local goldEarned, isCrit = calculateTapEarnings(player)

	-- Increment player's Gold via DataService
	if DataService.Increment(player, "Gold", goldEarned) then
		local tapResultEvent = Remotes.getEvent("TapResult")
		tapResultEvent:FireClient(player, goldEarned, isCrit)

		-- Fever progress: only charge when Fever is NOT active
		local fever = getFeverState(player)
		if not fever.isActive then
			fever.points = math.min(GameConfig.Fever.MaxPoints, fever.points + GameConfig.Fever.ChargePerTap)
			if fever.points >= GameConfig.Fever.MaxPoints then
				startFever(player)
			else
				sendFeverUpdate(player)
			end
		end

		return true
	end

	return false
end

local function stopAutoTap(player: Player)
	autoTapActive[player] = false
	local thread = autoTapThreads[player]
	if thread then
		task.cancel(thread)
		autoTapThreads[player] = nil
	end
	if player.Parent == Players then
		local autoTapStateEvent = Remotes.getEvent("AutoTapStateChanged")
		autoTapStateEvent:FireClient(player, false)
	end
end

local function startAutoTap(player: Player)
	if not DataService.IsLoaded(player) then
		return
	end

	if autoTapThreads[player] then
		task.cancel(autoTapThreads[player])
		autoTapThreads[player] = nil
	end

	autoTapActive[player] = true
	local autoTapStateEvent = Remotes.getEvent("AutoTapStateChanged")
	autoTapStateEvent:FireClient(player, true)

	autoTapThreads[player] = task.spawn(function()
		while autoTapActive[player] and player.Parent == Players and DataService.IsLoaded(player) do
			executeTap(player)

			-- Interval scales with Fever speed multiplier
			local tapsPerSecond = GameConfig.AutoTap.BaseTapsPerSecond
			if isFeverActive(player) then
				tapsPerSecond *= GameConfig.Fever.SpeedMultiplier
			end
			task.wait(1 / tapsPerSecond)
		end

		if autoTapActive[player] then
			stopAutoTap(player)
		end
		autoTapThreads[player] = nil
	end)
end

local function toggleAutoTap(player: Player)
	if not DataService.IsLoaded(player) then
		return
	end

	if autoTapActive[player] then
		stopAutoTap(player)
	else
		startAutoTap(player)
	end
end

function TapService.Start()
	local tapEvent = Remotes.getEvent("Tap")
	tapEvent.OnServerEvent:Connect(function(player: Player)
		executeTap(player)
	end)

	local toggleAutoTapEvent = Remotes.getEvent("ToggleAutoTap")
	toggleAutoTapEvent.OnServerEvent:Connect(function(player: Player)
		toggleAutoTap(player)
	end)

	local function initPlayer(player: Player)
		task.spawn(function()
			if DataService.WaitForProfile(player) then
				updateEquippedDamageCache(player)
				sendFeverUpdate(player)
			end
		end)
	end

	DataService.Changed:Connect(function(player: Player, key: string, _value: any)
		if key == "EquippedSword" or key == "OwnedSwords" then
			updateEquippedDamageCache(player)
		end
	end)

	Players.PlayerAdded:Connect(initPlayer)
	for _, player in Players:GetPlayers() do
		initPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		playerBuckets[player] = nil
		playerEquippedDamage[player] = nil
		playerEquippedGoldPerTap[player] = nil
		playerEquippedEntry[player] = nil

		-- Clean up Auto-Tap
		autoTapActive[player] = nil
		local aThread = autoTapThreads[player]
		if aThread then
			task.cancel(aThread)
			autoTapThreads[player] = nil
		end

		-- Clean up Fever
		local fThread = feverThreads[player]
		if fThread then
			task.cancel(fThread)
			feverThreads[player] = nil
		end
		playerFever[player] = nil
	end)
end

return TapService
