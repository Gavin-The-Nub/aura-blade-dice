--!strict
-- RunesmithService: Server-authoritative sword blessing service.
-- GDD section 5C: RollBlessing costs Gold computed exclusively on the server from the
-- player's highest owned Dice tier (from OwnedDice).
-- Guarantees:
-- - Shared PlayerActionLock per roll
-- - Validation (rate limit, ownership, Gold balance) re-checked inside lock
-- - Single non-yielding atomic DataService.SetMany per roll
-- - Equipped and placed swords are allowed
-- - Return payload and error reasons mirror RollEnchant exactly:
--   (success, oldVal, newVal, costPaid, errorReason)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Blessings = require(ReplicatedStorage.Config.Blessings)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(ServerScriptService.Services.DataService)
local PlayerActionLock = require(ServerScriptService.PlayerActionLock)

local ROLL_RATE_LIMIT_SECONDS = 0.2

local RunesmithService = {}

local lastRollTime: { [Player]: number } = {}

-- Helper to find player's highest owned Dice tier from OwnedDice table
local function getHighestOwnedDiceTier(player: Player): number
	local highestTier = 1
	local ownedDice = DataService.Get(player, "OwnedDice")
	if typeof(ownedDice) == "table" then
		for tierKey, owned in ownedDice do
			if owned == true then
				local tNum = tonumber(tierKey)
				if tNum and tNum > highestTier then
					highestTier = tNum
				end
			end
		end
	end
	return highestTier
end

-- Server-authoritative calculation of current blessing roll cost for a player
function RunesmithService.GetBlessingCost(player: Player): number
	if not DataService.IsLoaded(player) then
		return Blessings.MinCost
	end
	local highestTier = getHighestOwnedDiceTier(player)
	local cost = Blessings.CalculateCost(highestTier)
	return cost
end

-- Rolls a random blessing onto a sword.
-- Returns: (success, oldBlessing, newBlessing, costPaid, errorReason)
function RunesmithService.RollBlessing(player: Player, uid: unknown): (boolean, string?, string?, number?, string?)
	if typeof(uid) ~= "string" or uid == "" then
		return false, nil, nil, nil, "Invalid sword identifier."
	end

	-- Rate limiting check
	local now = os.clock()
	local lastTime = lastRollTime[player] or 0
	if now - lastTime < ROLL_RATE_LIMIT_SECONDS then
		return false, nil, nil, nil, "Rolling blessings too fast; please slow down."
	end
	lastRollTime[player] = now

	if not PlayerActionLock.Acquire(player) then
		return false, nil, nil, nil, "Another inventory action is in progress."
	end

	local ok, success, oldVal, newVal, costPaid, errMsg = pcall(function(): (boolean, string?, string?, number?, string?)
		if not DataService.IsLoaded(player) then
			return false, nil, nil, nil, "Player data is not loaded."
		end

		local ownedSwords = DataService.Get(player, "OwnedSwords")
		if typeof(ownedSwords) ~= "table" then
			return false, nil, nil, nil, "Inventory data unavailable."
		end

		-- Find sword entry by uid (equipped and placed swords are allowed)
		local targetIndex: number? = nil
		local targetEntry: any = nil
		for i, entry in ipairs(ownedSwords) do
			if typeof(entry) == "table" and entry.uid == uid then
				targetIndex = i
				targetEntry = entry
				break
			end
		end

		if targetIndex == nil or targetEntry == nil then
			return false, nil, nil, nil, "Sword not found in your inventory."
		end

		-- Server-computed cost (never trust client)
		local highestTier = getHighestOwnedDiceTier(player)
		local cost = Blessings.CalculateCost(highestTier)

		local currentGold = DataService.Get(player, "Gold") or 0
		if currentGold < cost then
			return false, nil, nil, nil, "Not enough Gold to roll blessing."
		end

		-- Roll new blessing from Config weights
		local rolledDef = Blessings.RollRandomBlessing()
		local oldBlessing = targetEntry.blessing or ""

		-- Deep clone inventory for atomic write
		local updatedSwords = table.create(#ownedSwords)
		for i, entry in ipairs(ownedSwords) do
			if i == targetIndex then
				local cloned = table.clone(entry)
				cloned.blessing = rolledDef.name
				updatedSwords[i] = cloned
			else
				updatedSwords[i] = entry
			end
		end

		-- Atomic non-yielding update
		local setOk = DataService.SetMany(player, {
			Gold = currentGold - cost,
			OwnedSwords = updatedSwords,
		})

		if not setOk then
			return false, nil, nil, nil, "Failed to save blessing result."
		end

		return true, oldBlessing, rolledDef.name, cost, nil
	end)

	PlayerActionLock.Release(player)

	if not ok then
		warn(("[RunesmithService.RollBlessing] Error for %s: %s"):format(player.Name, tostring(success)))
		return false, nil, nil, nil, "An unexpected error occurred while rolling blessing."
	end

	return success, oldVal, newVal, costPaid, errMsg
end

function RunesmithService.Start()
	local rollBlessingFunc = Remotes.getFunction("RollBlessing")
	local getBlessingCostFunc = Remotes.getFunction("GetBlessingCost")

	rollBlessingFunc.OnServerInvoke = function(player: Player, uid: unknown)
		return RunesmithService.RollBlessing(player, uid)
	end

	getBlessingCostFunc.OnServerInvoke = function(player: Player)
		return RunesmithService.GetBlessingCost(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		lastRollTime[player] = nil
	end)
end

return RunesmithService
