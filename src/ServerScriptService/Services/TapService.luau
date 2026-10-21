--!strict
-- TapService: Handles player tap inputs, rate limiting (token bucket with burst),
-- gold calculation from equipped sword + crits, and saves gold via DataService.

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

local playerBuckets: { [Player]: Bucket } = {}

local TapService = {}

-- Indexed sword lookup cache
local swordMap: { [string]: Swords.SwordDef } = {}
for _, def in Swords do
	swordMap[def.id] = def
end

-- Returns the max tap rate per second for a player (designed to be modified by Fever / Gamepasses later)
function TapService.getMaxTapRate(player: Player): number
	-- Placeholder: GameConfig.Tap.MaxTapsPerSecond. Fever Mode / Fast Slash gamepass can scale this later.
	return GameConfig.Tap.MaxTapsPerSecond
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
	local equippedId = DataService.Get(player, "EquippedSword")
	
	-- Fallback to test_sword if no sword equipped (NOTE: To be removed during equip step)
	if type(equippedId) ~= "string" or equippedId == "" then
		equippedId = "test_sword"
	end

	local sword = swordMap[equippedId]
	local baseDamage = if sword then sword.baseDamage else 1

	-- Multipliers (placeholders for future systems: Grade, Enchant, Rebirth)
	local gradeMult = 1
	local enchantMult = 1
	local rebirthMult = 1

	-- Crit calculation: 10% base chance for 2.5x multiplier
	local isCrit = math.random() < GameConfig.Tap.CritChance
	local critBonus = if isCrit then GameConfig.Tap.CritMultiplier else 1

	local goldEarned = baseDamage * gradeMult * enchantMult * rebirthMult * critBonus
	return goldEarned, isCrit
end

local function onTapReceived(player: Player)
	local isLoaded = DataService.IsLoaded(player)
	-- Ignore tap if data is not loaded yet
	if not isLoaded then
		return
	end

	-- Enforce server-side rate limit
	if not consumeTapToken(player) then
		return
	end

	local goldEarned, isCrit = calculateTapEarnings(player)

	-- Increment player's Gold via DataService
	if DataService.Increment(player, "Gold", goldEarned) then
		local tapResultEvent = Remotes.getEvent("TapResult")
		tapResultEvent:FireClient(player, goldEarned, isCrit)
	end
end

function TapService.Start()
	local tapEvent = Remotes.getEvent("Tap")
	tapEvent.OnServerEvent:Connect(onTapReceived)

	Players.PlayerRemoving:Connect(function(player)
		playerBuckets[player] = nil
	end)
end

return TapService
