--!strict
-- MerchantService: Server-authoritative Dice merchant handling tier purchases and equipping.
-- Allows buying any valid unowned Dice tier using Gold, auto-equips on purchase only if higher than
-- the current equipped tier, and allows players to switch between any owned Dice tiers freely.
-- Protects all operations with strict type/value validation, per-player locks, and rate limiting.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Dice = require(ReplicatedStorage.Config.Dice)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(ServerScriptService.Services.DataService)

local MerchantService = {}

-- Cached lookup for dice definitions by tier
local diceMap: { [number]: Dice.DiceDef } = {}
for _, def in Dice do
	diceMap[def.tier] = def
end

-- Per-player concurrency lock and rate-limiting
local playerLocks: { [Player]: boolean } = {}
local lastRequestTimes: { [Player]: number } = {}
local RATE_LIMIT_SECONDS = 0.25

local function cleanupPlayer(player: Player)
	playerLocks[player] = nil
	lastRequestTimes[player] = nil
end

-- Validates that tier is a non-NaN, non-infinite whole number that exists in Config
local function validateTier(tier: unknown): (boolean, number, Dice.DiceDef?, string?)
	if type(tier) ~= "number" then
		return false, 0, nil, "Dice tier must be a number"
	end
	if tier ~= tier or tier == math.huge or tier == -math.huge then
		return false, 0, nil, "Invalid Dice tier value"
	end
	if tier ~= math.floor(tier) or tier < 1 then
		return false, 0, nil, "Dice tier must be a positive integer"
	end
	local def = diceMap[tier]
	if not def then
		return false, 0, nil, ("Dice tier %d does not exist in Config"):format(tier)
	end
	return true, tier, def, nil
end

-- Acquires per-player concurrency lock and enforces rate-limiting
local function tryLock(player: Player): (boolean, string?)
	if player.Parent ~= Players or not DataService.IsLoaded(player) then
		return false, "Data is not loaded yet"
	end

	local now = os.clock()
	local lastTime = lastRequestTimes[player] or 0
	if (now - lastTime) < RATE_LIMIT_SECONDS then
		return false, "Please wait before making another request"
	end
	lastRequestTimes[player] = now

	if playerLocks[player] then
		return false, "Action already in progress"
	end
	playerLocks[player] = true
	return true, nil
end

local function unlock(player: Player)
	playerLocks[player] = nil
end

-- Purchases an unowned Dice tier with Gold.
-- Auto-equips if and only if the new tier is higher than the currently equipped tier.
-- Gold is refunded ONLY if setting OwnedDice fails; a failed auto-equip leaves the Dice owned.
function MerchantService.BuyDice(player: Player, targetTier: unknown): (boolean, string?)
	local lockOk, lockErr = tryLock(player)
	if not lockOk then
		return false, lockErr
	end

	local valid, tier, def, tierErr = validateTier(targetTier)
	if not valid or not def then
		unlock(player)
		return false, tierErr
	end

	-- 1. Check ownership
	local ownedDice = DataService.Get(player, "OwnedDice")
	if type(ownedDice) == "table" and ownedDice[tostring(tier)] == true then
		unlock(player)
		return false, "You already own this Dice"
	end

	-- 2. Check Gold affordability and deduct
	local cost = def.cost
	local deducted = DataService.Increment(player, "Gold", -cost)
	if not deducted then
		unlock(player)
		return false, "Not enough Gold to buy this Dice"
	end

	-- 3. Update OwnedDice
	local updatedOwned: { [string]: boolean } = {}
	if type(ownedDice) == "table" then
		for k, v in ownedDice do
			updatedOwned[k] = v
		end
	end
	updatedOwned[tostring(tier)] = true

	local setOwnedOk = DataService.Set(player, "OwnedDice", updatedOwned)
	if not setOwnedOk then
		-- Refund Gold only if OwnedDice write fails
		DataService.Increment(player, "Gold", cost)
		unlock(player)
		return false, "Failed to save purchased Dice. Gold refunded."
	end

	-- 4. Option 1: Auto-equip only if the new tier is higher than currently equipped
	local equippedTier = DataService.Get(player, "DiceTier")
	if type(equippedTier) ~= "number" then
		equippedTier = 1
	end

	if tier > equippedTier then
		local equipOk = DataService.Set(player, "DiceTier", tier)
		if not equipOk then
			warn(("[MerchantService] Auto-equip failed for player %s to tier %d; dice remains owned"):format(player.Name, tier))
		end
	end

	unlock(player)
	return true, nil
end

-- Equips an owned Dice tier
function MerchantService.EquipDice(player: Player, targetTier: unknown): (boolean, string?)
	local lockOk, lockErr = tryLock(player)
	if not lockOk then
		return false, lockErr
	end

	local valid, tier, _def, tierErr = validateTier(targetTier)
	if not valid then
		unlock(player)
		return false, tierErr
	end

	-- Must be owned
	local ownedDice = DataService.Get(player, "OwnedDice")
	if type(ownedDice) ~= "table" or ownedDice[tostring(tier)] ~= true then
		unlock(player)
		return false, "You do not own this Dice"
	end

	local setOk = DataService.Set(player, "DiceTier", tier)
	unlock(player)

	if not setOk then
		return false, "Failed to equip Dice"
	end
	return true, nil
end

function MerchantService.Start()
	local buyDiceFunc = Remotes.getFunction("BuyDice")
	buyDiceFunc.OnServerInvoke = function(player: Player, targetTier: unknown)
		return MerchantService.BuyDice(player, targetTier)
	end

	local equipDiceFunc = Remotes.getFunction("EquipDice")
	equipDiceFunc.OnServerInvoke = function(player: Player, targetTier: unknown)
		return MerchantService.EquipDice(player, targetTier)
	end

	Players.PlayerRemoving:Connect(cleanupPlayer)
end

return MerchantService
