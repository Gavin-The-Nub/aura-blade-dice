--!strict
-- RebirthService: Manages server-authoritative Rebirth previews and executions.
-- Enforces rate limiting, single-use cryptographically random tokens, PlayerActionLock,
-- atomic profile mutation via DataService.SetMany, and fractional remainder clearing via GoldCredit.Clear.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Rebirths = require(ReplicatedStorage.Config.Rebirths)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(ServerScriptService.Services.DataService)
local GoldCredit = require(ServerScriptService.GoldCredit)
local PlayerActionLock = require(ServerScriptService.PlayerActionLock)

type RebirthSnapshot = {
	token: string,
	createdAt: number,
	ttl: number,
	currentRebirths: number,
	nextRebirths: number,
	cost: number,
	gemsGrant: number,
	targetSlots: number,
	newGoldMult: number,
	newLuckMult: number,
}

type RateBucket = {
	lastTime: number,
	tokens: number,
}

local RATE_LIMIT_CAPACITY = 6
local RATE_LIMIT_REFILL_PER_SEC = 3
local DEFAULT_TOKEN_TTL = 60

local playerBuckets: { [Player]: RateBucket } = {}
local rebirthSnapshots: { [Player]: RebirthSnapshot } = {}

local RebirthService = {}

local function isAutoRolling(player: Player): boolean
	local appraiserOk, appraiser = pcall(function()
		return require(ServerScriptService.Services.AppraiserService)
	end)
	if appraiserOk and appraiser and type(appraiser.IsAutoRolling) == "function" and appraiser.IsAutoRolling(player) then
		return true
	end
	local enchanterOk, enchanter = pcall(function()
		return require(ServerScriptService.Services.EnchanterService)
	end)
	if enchanterOk and enchanter and type(enchanter.IsAutoRolling) == "function" and enchanter.IsAutoRolling(player) then
		return true
	end
	return false
end

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

-- Generates a rebirth preview for a player.
-- In one non-yielding block, reads player state, computes costs and rewards.
-- If player cannot afford the rebirth, returns canAfford = false and NO token.
function RebirthService.GetRebirthPreview(player: Player): (boolean, any?, string?)
	if not checkRateLimit(player) then
		return false, nil, "Action rate limited. Please slow down."
	end

	if not DataService.IsLoaded(player) then
		return false, nil, "Data is loading..."
	end

	-- Execute read and decision in one synchronous, non-yielding block
	local currentRebirths = DataService.Get(player, "Rebirths") or 0
	if typeof(currentRebirths) ~= "number" then
		currentRebirths = 0
	end

	local currentGold = DataService.Get(player, "Gold") or 0
	local currentGoldMult = Rebirths.GetGoldMultiplier(currentRebirths)
	local currentLuckMult = Rebirths.GetLuckMultiplier(currentRebirths)
	local currentSlots = DataService.Get(player, "PedestalSlots") or Rebirths.BasePedestalSlots

	if currentRebirths >= Rebirths.MaxRebirths then
		rebirthSnapshots[player] = nil
		return true, {
			token = nil,
			canAfford = false,
			isMaxRebirth = true,
			currentRebirths = currentRebirths,
			nextRebirths = currentRebirths,
			cost = 0,
			currentGold = currentGold,
			currentGoldMult = currentGoldMult,
			newGoldMult = currentGoldMult,
			currentLuckMult = currentLuckMult,
			newLuckMult = currentLuckMult,
			gemsGrant = 0,
			currentSlots = currentSlots,
			newSlots = currentSlots,
			slotChange = 0,
		}, nil
	end

	local nextRebirths = currentRebirths + 1
	local cost = Rebirths.GetCost(nextRebirths)
	local canAfford = currentGold >= cost

	local newGoldMult = Rebirths.GetGoldMultiplier(nextRebirths)
	local newLuckMult = Rebirths.GetLuckMultiplier(nextRebirths)
	local gemsGrant = Rebirths.GetGemsGrant(nextRebirths)

	local milestoneSlots = Rebirths.GetPedestalSlots(nextRebirths)
	local newSlots = math.max(currentSlots, milestoneSlots)
	local slotChange = newSlots - currentSlots

	if not canAfford then
		-- Rule 1: If player cannot afford, return preview with canAfford = false and NO token
		rebirthSnapshots[player] = nil
		return true, {
			token = nil,
			canAfford = false,
			isMaxRebirth = false,
			currentRebirths = currentRebirths,
			nextRebirths = nextRebirths,
			cost = cost,
			currentGold = currentGold,
			currentGoldMult = currentGoldMult,
			newGoldMult = newGoldMult,
			currentLuckMult = currentLuckMult,
			newLuckMult = newLuckMult,
			gemsGrant = gemsGrant,
			currentSlots = currentSlots,
			newSlots = newSlots,
			slotChange = slotChange,
		}, nil
	end

	-- Player can afford: generate single-use token and store snapshot
	local token = HttpService:GenerateGUID(false):sub(1, 12)
	local ttl = DEFAULT_TOKEN_TTL

	rebirthSnapshots[player] = {
		token = token,
		createdAt = os.clock(),
		ttl = ttl,
		currentRebirths = currentRebirths,
		nextRebirths = nextRebirths,
		cost = cost,
		gemsGrant = gemsGrant,
		targetSlots = newSlots,
		newGoldMult = newGoldMult,
		newLuckMult = newLuckMult,
	}

	return true, {
		token = token,
		canAfford = true,
		currentRebirths = currentRebirths,
		nextRebirths = nextRebirths,
		cost = cost,
		currentGold = currentGold,
		currentGoldMult = currentGoldMult,
		newGoldMult = newGoldMult,
		currentLuckMult = currentLuckMult,
		newLuckMult = newLuckMult,
		gemsGrant = gemsGrant,
		currentSlots = currentSlots,
		newSlots = newSlots,
		slotChange = slotChange,
	}, nil
end

-- Confirms and executes a rebirth using a valid single-use token.
-- Acquires PlayerActionLock, validates token and live balances, writes updates atomically
-- in one non-yielding block, and clears GoldCredit.
function RebirthService.ConfirmRebirth(player: Player, token: unknown): (boolean, any?, string?)
	if not checkRateLimit(player) then
		return false, nil, "Action rate limited. Please slow down."
	end

	if typeof(token) ~= "string" or token == "" then
		return false, nil, "Preview again"
	end

	if not DataService.IsLoaded(player) then
		return false, nil, "Data is loading..."
	end

	if isAutoRolling(player) then
		return false, nil, "Stop your auto roll first."
	end

	if not PlayerActionLock.Acquire(player) then
		task.wait(0.05)
		if isAutoRolling(player) then
			return false, nil, "Stop your auto roll first."
		end
		if not PlayerActionLock.Acquire(player) then
			return false, nil, "Another inventory or rebirth action is in progress."
		end
	end

	local ok, success, result, errMsg = pcall(function(): (boolean, any?, string?)
		-- In one non-yielding block:
		-- 1. Validate snapshot and consume token immediately (strictly single-use)
		local snap = rebirthSnapshots[player]
		rebirthSnapshots[player] = nil

		if not snap or (os.clock() - snap.createdAt) > snap.ttl or snap.token ~= token then
			return false, nil, "Preview again"
		end

		-- 2. Re-read live state inside lock without yielding
		local currentRebirths = DataService.Get(player, "Rebirths") or 0
		if currentRebirths ~= snap.currentRebirths or currentRebirths >= Rebirths.MaxRebirths then
			return false, nil, "Preview again"
		end

		local currentGold = DataService.Get(player, "Gold") or 0
		if currentGold < snap.cost then
			return false, nil, "Not enough Gold."
		end

		local currentGems = DataService.Get(player, "Gems") or 0
		local currentSlots = DataService.Get(player, "PedestalSlots") or Rebirths.BasePedestalSlots
		local targetSlots = math.max(currentSlots, snap.targetSlots)

		-- Taps credit Gold outside the lock, so re-reading Gold and setting Gold = 0
		-- without yielding guarantees no tap income earned before reset is lost or corrupted,
		-- and resets Gold atomically.
		local updates = {
			Gold = 0,
			Rebirths = snap.nextRebirths,
			Gems = currentGems + snap.gemsGrant,
			PedestalSlots = targetSlots,
		}

		local setOk = DataService.SetMany(player, updates)
		if not setOk then
			return false, nil, "Failed to apply rebirth."
		end

		-- Clear in-memory fractional gold remainder carry-over
		GoldCredit.Clear(player)

		return true, {
			newRebirths = snap.nextRebirths,
			gemsAwarded = snap.gemsGrant,
			newGoldMult = snap.newGoldMult,
			newLuckMult = snap.newLuckMult,
			newPedestalSlots = targetSlots,
		}, nil
	end)

	PlayerActionLock.Release(player)

	if not ok then
		warn(("[RebirthService.ConfirmRebirth] Error for %s: %s"):format(player.Name, tostring(success)))
		return false, nil, "An unexpected error occurred while executing Rebirth."
	end

	return success, result, errMsg
end

function RebirthService.Start()
	local getRebirthPreviewFunc = Remotes.getFunction("GetRebirthPreview")
	getRebirthPreviewFunc.OnServerInvoke = function(player: Player)
		return RebirthService.GetRebirthPreview(player)
	end

	local confirmRebirthFunc = Remotes.getFunction("ConfirmRebirth")
	confirmRebirthFunc.OnServerInvoke = function(player: Player, token: unknown)
		return RebirthService.ConfirmRebirth(player, token)
	end

	-- Rule 7: Clear snapshot on player disconnect
	Players.PlayerRemoving:Connect(function(player: Player)
		rebirthSnapshots[player] = nil
		playerBuckets[player] = nil
	end)

	-- Rule 7: Clear snapshot on any Rebirths data change
	DataService.Changed:Connect(function(player: Player, key: string, _value: any)
		if key == "Rebirths" then
			rebirthSnapshots[player] = nil
		end
	end)
end

return RebirthService
