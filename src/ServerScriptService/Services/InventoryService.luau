--!strict
-- InventoryService: Server-authoritative inventory operations (Equip, Sell, Auto-Sell Rules).
-- Validates ownership, argument types, rate limits, and persists updates via DataService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Swords = require(ReplicatedStorage.Config.Swords)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(ServerScriptService.Services.DataService)

local InventoryService = {}

type RateLimitBucket = {
	lastTime: number,
	tokens: number,
}

local playerBuckets: { [Player]: RateLimitBucket } = {}
local RATE_LIMIT_CAPACITY = 8
local RATE_LIMIT_REFILL_PER_SEC = 4

local function checkRateLimit(player: Player): boolean
	local now = os.clock()
	local bucket = playerBuckets[player]
	if not bucket then
		bucket = {
			lastTime = now,
			tokens = RATE_LIMIT_CAPACITY - 1,
		}
		playerBuckets[player] = bucket
		return true
	end

	local elapsed = now - bucket.lastTime
	bucket.tokens = math.min(RATE_LIMIT_CAPACITY, bucket.tokens + (elapsed * RATE_LIMIT_REFILL_PER_SEC))
	bucket.lastTime = now

	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end

	return false
end

-- Equips a sword by its unique instance id (uid), or uneips if uid == ""
function InventoryService.Equip(player: Player, uid: string): (boolean, string?)
	if not checkRateLimit(player) then
		return false, "Action rate limited. Please slow down."
	end

	if typeof(uid) ~= "string" or #uid > 100 then
		return false, "Invalid sword identifier."
	end

	if not DataService.IsLoaded(player) then
		return false, "Data is loading..."
	end

	-- Unequip if empty string
	if uid == "" then
		DataService.Set(player, "EquippedSword", "")
		return true, nil
	end

	-- Check ownership
	local ownedSwords = DataService.Get(player, "OwnedSwords")
	if typeof(ownedSwords) ~= "table" then
		return false, "No swords owned."
	end

	local found = false
	for _, entry in ownedSwords do
		if typeof(entry) == "table" and entry.uid == uid then
			found = true
			break
		end
	end

	if not found then
		return false, "You do not own this sword."
	end

	local success = DataService.Set(player, "EquippedSword", uid)
	if success then
		return true, nil
	else
		return false, "Failed to equip sword."
	end
end

-- Sells (removes) a sword by its uid. Equipped swords cannot be sold.
function InventoryService.Sell(player: Player, uid: string): (boolean, string?)
	if not checkRateLimit(player) then
		return false, "Action rate limited. Please slow down."
	end

	if typeof(uid) ~= "string" or #uid > 100 or uid == "" then
		return false, "Invalid sword identifier."
	end

	if not DataService.IsLoaded(player) then
		return false, "Data is loading..."
	end

	local equippedUid = DataService.Get(player, "EquippedSword")
	if equippedUid == uid then
		return false, "Cannot sell your currently equipped sword!"
	end

	local ownedSwords = DataService.Get(player, "OwnedSwords")
	if typeof(ownedSwords) ~= "table" then
		return false, "No swords owned."
	end

	local targetIndex = nil
	for i, entry in ipairs(ownedSwords) do
		if typeof(entry) == "table" and entry.uid == uid then
			targetIndex = i
			break
		end
	end

	if not targetIndex then
		return false, "You do not own this sword."
	end

	local updated = table.clone(ownedSwords)
	table.remove(updated, targetIndex)
	local success = DataService.Set(player, "OwnedSwords", updated)
	if success then
		return true, nil
	else
		return false, "Failed to sell sword."
	end
end

-- Toggles auto-sell rule for a specific rarity
function InventoryService.SetAutoSellRule(player: Player, rarity: string, enabled: boolean): boolean
	if not checkRateLimit(player) then
		return false
	end

	if typeof(rarity) ~= "string" or typeof(enabled) ~= "boolean" then
		return false
	end

	if not Swords.IsValidRarity(rarity) then
		return false
	end

	if not DataService.IsLoaded(player) then
		return false
	end

	local rules = DataService.Get(player, "AutoSellRules")
	local updated = if typeof(rules) == "table" then table.clone(rules) else {}
	updated[rarity] = enabled

	return DataService.Set(player, "AutoSellRules", updated)
end

function InventoryService.Start()
	local equipFunc = Remotes.getFunction("EquipSword")
	equipFunc.OnServerInvoke = function(player: Player, uid: unknown)
		if typeof(uid) ~= "string" then
			return false, "Invalid argument."
		end
		return InventoryService.Equip(player, uid)
	end

	local sellFunc = Remotes.getFunction("SellSword")
	sellFunc.OnServerInvoke = function(player: Player, uid: unknown)
		if typeof(uid) ~= "string" then
			return false, "Invalid argument."
		end
		return InventoryService.Sell(player, uid)
	end

	local setAutoSellEvent = Remotes.getEvent("SetAutoSellRule")
	setAutoSellEvent.OnServerEvent:Connect(function(player: Player, rarity: unknown, enabled: unknown)
		if typeof(rarity) ~= "string" or typeof(enabled) ~= "boolean" then
			return
		end
		InventoryService.SetAutoSellRule(player, rarity, enabled)
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerBuckets[player] = nil
	end)
end

return InventoryService
