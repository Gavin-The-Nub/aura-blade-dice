--!strict
-- InventoryService: Server-authoritative inventory operations (Equip, Sell, Auto-Sell Rules).
-- Validates ownership, argument types, rate limits, and persists updates via DataService.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Swords = require(ReplicatedStorage.Config.Swords)
local GameConfig = require(ReplicatedStorage.Config.Game)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SalePrice = require(ReplicatedStorage.Shared.SalePrice)
local DataService = require(ServerScriptService.Services.DataService)
local TapService = require(ServerScriptService.Services.TapService)
local PlayerActionLock = require(ServerScriptService.PlayerActionLock)

local InventoryService = {}

type RateLimitBucket = {
	lastTime: number,
	tokens: number,
}

local playerBuckets: { [Player]: RateLimitBucket } = {}
local RATE_LIMIT_CAPACITY = 8
local RATE_LIMIT_REFILL_PER_SEC = 4

-- Cached sword definitions
local swordDefMap: { [string]: Swords.SwordDef } = {}
for _, def in Swords do
	swordDefMap[def.id] = def
end

-- Rarity rank for tie-breaking (higher is better)
local rarityRank: { [string]: number } = {}
for idx, rarity in ipairs(Swords.Rarities) do
	rarityRank[rarity] = idx
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

-- Equips a sword by its unique instance id (uid), or unequips if uid == ""
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

	if not PlayerActionLock.Acquire(player) then
		return false, "Another inventory or pedestal action is in progress."
	end

	local ok, success, errMsg = pcall(function(): (boolean, string?)
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

		-- Reject equipping a sword placed on a pedestal
		local placedSwords = DataService.Get(player, "PlacedSwords")
		if typeof(placedSwords) == "table" then
			for _, placedUid in placedSwords do
				if placedUid == uid then
					return false, "Cannot equip a sword placed on a pedestal! Remove it first."
				end
			end
		end

		local saved = DataService.Set(player, "EquippedSword", uid)
		if saved then
			return true, nil
		else
			return false, "Failed to equip sword."
		end
	end)

	PlayerActionLock.Release(player)

	if not ok then
		warn(("[InventoryService.Equip] Error for %s: %s"):format(player.Name, tostring(success)))
		return false, "An unexpected error occurred while equipping sword."
	end

	return success, errMsg
end

-- Unequips currently equipped sword. Protected by PlayerActionLock via Equip(player, "").
function InventoryService.Unequip(player: Player): (boolean, string?)
	return InventoryService.Equip(player, "")
end

-- Central server formula for calculating sword sale price (delegates to Shared/SalePrice)
function InventoryService.CalculateSwordSalePrice(swordEntryOrDef: any): number
	return SalePrice.calculate(swordEntryOrDef)
end

-- Toggles the locked status of an owned sword by its uid.
-- Locked swords can be equipped and placed on pedestals, but cannot be sold.
function InventoryService.ToggleLock(player: Player, uid: string): (boolean, boolean?, string?)
	if not checkRateLimit(player) then
		return false, nil, "Action rate limited. Please slow down."
	end

	if typeof(uid) ~= "string" or #uid > 100 or uid == "" then
		return false, nil, "Invalid sword identifier."
	end

	if not DataService.IsLoaded(player) then
		return false, nil, "Data is loading..."
	end

	if not PlayerActionLock.Acquire(player) then
		return false, nil, "Another inventory or pedestal action is in progress."
	end

	local ok, success, isLocked, errMsg = pcall(function(): (boolean, boolean?, string?)
		local ownedSwords = DataService.Get(player, "OwnedSwords")
		if typeof(ownedSwords) ~= "table" then
			return false, nil, "No swords owned."
		end

		local targetIndex = nil
		local targetEntry = nil
		for i, entry in ipairs(ownedSwords) do
			if typeof(entry) == "table" and entry.uid == uid then
				targetIndex = i
				targetEntry = entry
				break
			end
		end

		if not targetIndex or not targetEntry then
			return false, nil, "You do not own this sword."
		end

		local updated = table.clone(ownedSwords)
		local newEntry = table.clone(targetEntry)
		newEntry.locked = not (targetEntry.locked == true)
		updated[targetIndex] = newEntry

		local saved = DataService.Set(player, "OwnedSwords", updated)
		if saved then
			return true, newEntry.locked, nil
		else
			return false, nil, "Failed to update sword lock status."
		end
	end)

	PlayerActionLock.Release(player)

	if not ok then
		warn(("[InventoryService.ToggleLock] Error for %s: %s"):format(player.Name, tostring(success)))
		return false, nil, "An unexpected error occurred while toggling sword lock."
	end

	return success, isLocked, errMsg
end

-- Sells (removes) a sword by its uid. Equipped swords, pedestal swords, and locked swords cannot be sold.
-- Awards Gold atomically via DataService.SetMany.
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

	if not PlayerActionLock.Acquire(player) then
		return false, "Another inventory or pedestal action is in progress."
	end

	local ok, success, errMsg = pcall(function(): (boolean, string?)
		local equippedUid = DataService.Get(player, "EquippedSword")
		if equippedUid == uid then
			return false, "Cannot sell your currently equipped sword!"
		end

		-- Reject selling a sword placed on a pedestal
		local placedSwords = DataService.Get(player, "PlacedSwords")
		if typeof(placedSwords) == "table" then
			for _, placedUid in placedSwords do
				if placedUid == uid then
					return false, "Cannot sell a sword placed on a pedestal!"
				end
			end
		end

		local ownedSwords = DataService.Get(player, "OwnedSwords")
		if typeof(ownedSwords) ~= "table" then
			return false, "No swords owned."
		end

		local targetIndex = nil
		local targetEntry = nil
		for i, entry in ipairs(ownedSwords) do
			if typeof(entry) == "table" and entry.uid == uid then
				targetIndex = i
				targetEntry = entry
				break
			end
		end

		if not targetIndex or not targetEntry then
			return false, "You do not own this sword."
		end

		if targetEntry.locked == true then
			return false, "Cannot sell a locked sword! Unlock it first."
		end

		local salePrice = InventoryService.CalculateSwordSalePrice(targetEntry)
		local currentGold = DataService.Get(player, "Gold") or 0
		if typeof(currentGold) ~= "number" then
			currentGold = 0
		end
		local newGold = math.floor(currentGold + salePrice + 0.5)

		local updated = table.clone(ownedSwords)
		table.remove(updated, targetIndex)

		-- Atomic write of OwnedSwords and Gold in one non-yielding block
		local saved = DataService.SetMany(player, {
			OwnedSwords = updated,
			Gold = newGold,
		})
		if saved then
			return true, nil
		else
			return false, "Failed to sell sword."
		end
	end)

	PlayerActionLock.Release(player)

	if not ok then
		warn(("[InventoryService.Sell] Error for %s: %s"):format(player.Name, tostring(success)))
		return false, "An unexpected error occurred while selling sword."
	end

	return success, errMsg
end

type SellSnapshot = {
	token: string,
	createdAt: number,
	uids: { string },
}

local sellSnapshots: { [Player]: SellSnapshot } = {}

-- Previews Sell All: collects eligible swords (not equipped, not placed, not locked)
-- and saves a server snapshot that expires after 60 seconds.
function InventoryService.GetSellAllPreview(player: Player): (boolean, any?, string?)
	if not checkRateLimit(player) then
		return false, nil, "Action rate limited. Please slow down."
	end

	if not DataService.IsLoaded(player) then
		return false, nil, "Data is loading..."
	end

	local ok, success, data, errMsg = pcall(function(): (boolean, any?, string?)
		local ownedSwords = DataService.Get(player, "OwnedSwords")
		local equippedUid = DataService.Get(player, "EquippedSword")
		local placedSwords = DataService.Get(player, "PlacedSwords")

		local placedMap: { [string]: boolean } = {}
		if typeof(placedSwords) == "table" then
			for _, pUid in placedSwords do
				if typeof(pUid) == "string" and pUid ~= "" then
					placedMap[pUid] = true
				end
			end
		end

		local eligibleUids: { string } = {}
		local totalGold = 0
		local gradedOrEnchantedCount = 0

		if typeof(ownedSwords) == "table" then
			for _, entry in ownedSwords do
				if typeof(entry) == "table" and typeof(entry.uid) == "string" then
					if entry.uid ~= equippedUid and not placedMap[entry.uid] and entry.locked ~= true then
						table.insert(eligibleUids, entry.uid)
						totalGold += InventoryService.CalculateSwordSalePrice(entry)
						if (entry.grade and entry.grade ~= "") or (entry.enchant and entry.enchant ~= "") then
							gradedOrEnchantedCount += 1
						end
					end
				end
			end
		end

		local token = HttpService:GenerateGUID(false):sub(1, 12)

		-- Store snapshot valid for 60 seconds
		sellSnapshots[player] = {
			token = token,
			createdAt = os.clock(),
			uids = eligibleUids,
		}

		return true, {
			token = token,
			count = #eligibleUids,
			totalGold = math.floor(totalGold + 0.5),
			gradedOrEnchantedCount = gradedOrEnchantedCount,
		}, nil
	end)

	if not ok then
		warn(("[InventoryService.GetSellAllPreview] Error for %s: %s"):format(player.Name, tostring(success)))
		return false, nil, "An unexpected error occurred while generating Sell All preview."
	end

	return success, data, errMsg
end

-- Executes Sell All using the server-side snapshot. Sells ONLY those snapshot uids that
-- remain owned, unlocked, unequipped, and unplaced. Requires matching token and snapshot age <= 60s.
function InventoryService.SellAll(player: Player, token: unknown): (boolean, number?, number?, string?)
	if not checkRateLimit(player) then
		return false, nil, nil, "Action rate limited. Please slow down."
	end

	if typeof(token) ~= "string" or token == "" then
		return false, nil, nil, "Preview again"
	end

	if not DataService.IsLoaded(player) then
		return false, nil, nil, "Data is loading..."
	end

	if not PlayerActionLock.Acquire(player) then
		return false, nil, nil, "Another inventory or pedestal action is in progress."
	end

	local ok, success, soldCount, goldEarned, errMsg = pcall(function(): (boolean, number?, number?, string?)
		local snap = sellSnapshots[player]
		if not snap or (os.clock() - snap.createdAt) > 60 or snap.token ~= token then
			sellSnapshots[player] = nil
			return false, nil, nil, "Preview again"
		end

		local snapSet: { [string]: boolean } = {}
		for _, uid in snap.uids do
			snapSet[uid] = true
		end

		local ownedSwords = DataService.Get(player, "OwnedSwords")
		local currentGold = DataService.Get(player, "Gold") or 0
		local equippedUid = DataService.Get(player, "EquippedSword")
		local placedSwords = DataService.Get(player, "PlacedSwords")

		if typeof(ownedSwords) ~= "table" then
			sellSnapshots[player] = nil
			return false, 0, 0, "No swords owned."
		end

		local placedMap: { [string]: boolean } = {}
		if typeof(placedSwords) == "table" then
			for _, pUid in placedSwords do
				if typeof(pUid) == "string" and pUid ~= "" then
					placedMap[pUid] = true
				end
			end
		end

		local remainingSwords: { any } = {}
		local actualGold = 0
		local actualCount = 0

		for _, entry in ownedSwords do
			if typeof(entry) == "table" and typeof(entry.uid) == "string" and snapSet[entry.uid] then
				-- Validate still eligible
				if entry.uid ~= equippedUid and not placedMap[entry.uid] and entry.locked ~= true then
					actualCount += 1
					actualGold += InventoryService.CalculateSwordSalePrice(entry)
				else
					table.insert(remainingSwords, entry)
				end
			else
				table.insert(remainingSwords, entry)
			end
		end

		sellSnapshots[player] = nil

		if actualCount == 0 then
			return false, 0, 0, "No eligible swords to sell."
		end

		if typeof(currentGold) ~= "number" then
			currentGold = 0
		end
		local newGold = math.floor(currentGold + actualGold + 0.5)

		-- Atomic write of remaining swords and new Gold
		local saved = DataService.SetMany(player, {
			OwnedSwords = remainingSwords,
			Gold = newGold,
		})

		if saved then
			return true, actualCount, math.floor(actualGold + 0.5), nil
		else
			return false, nil, nil, "Failed to complete Sell All. Changes were rolled back."
		end
	end)

	PlayerActionLock.Release(player)

	if not ok then
		warn(("[InventoryService.SellAll] Error for %s: %s"):format(player.Name, tostring(success)))
		return false, nil, nil, "An unexpected error occurred while executing Sell All."
	end

	return success, soldCount, goldEarned, errMsg
end

-- Ranks all owned swords by GoldPerTap descending (ties broken by rarity rank then uid)
local function rankSwords(player: Player, swords: { any }): { any }
	local sorted = table.clone(swords)
	table.sort(sorted, function(a, b)
		local gptA = TapService.CalculateSwordGoldPerTap(player, a)
		local gptB = TapService.CalculateSwordGoldPerTap(player, b)
		if gptA ~= gptB then
			return gptA > gptB
		end

		local defA = swordDefMap[a.id]
		local defB = swordDefMap[b.id]
		local rankA = if defA then rarityRank[defA.rarity] or 0 else 0
		local rankB = if defB then rarityRank[defB.rarity] or 0 else 0
		if rankA ~= rankB then
			return rankA > rankB
		end

		local uidA = if type(a.uid) == "string" then a.uid else ""
		local uidB = if type(b.uid) == "string" then b.uid else ""
		return uidA < uidB
	end)
	return sorted
end

-- Equips the single best sword and assigns the next PedestalSlots swords onto pedestals 1..PedestalSlots.
-- Atomically writes EquippedSword and PlacedSwords via DataService.SetMany.
function InventoryService.EquipBest(player: Player): (boolean, string?)
	if not checkRateLimit(player) then
		return false, "Action rate limited. Please slow down."
	end

	if not DataService.IsLoaded(player) then
		return false, "Data is loading..."
	end

	if not PlayerActionLock.Acquire(player) then
		return false, "Another inventory or pedestal action is in progress."
	end

	local ok, success, msg = pcall(function(): (boolean, string?)
		local ownedSwords = DataService.Get(player, "OwnedSwords")
		if typeof(ownedSwords) ~= "table" or #ownedSwords == 0 then
			return true, "No swords in inventory! Roll the dice to pull swords."
		end

		local oldEquipped = DataService.Get(player, "EquippedSword")
		if typeof(oldEquipped) ~= "string" then
			oldEquipped = ""
		end

		local oldPlaced = DataService.Get(player, "PlacedSwords")
		local oldPlacedMap: { [string]: string } = {}
		if typeof(oldPlaced) == "table" then
			for k, v in oldPlaced do
				if typeof(k) == "string" and typeof(v) == "string" then
					oldPlacedMap[k] = v
				end
			end
		end

		local pedestalSlots = DataService.Get(player, "PedestalSlots") or GameConfig.Plot.DefaultPedestalsPerPlot
		if typeof(pedestalSlots) ~= "number" then
			pedestalSlots = 4
		end
		pedestalSlots = math.clamp(math.floor(pedestalSlots), 1, 10)

		-- Rank swords descending
		local ranked = rankSwords(player, ownedSwords)

		-- Top sword becomes equipped
		local targetEquippedUid = ranked[1].uid

		-- Next PedestalSlots swords go to pedestals 1..PedestalSlots
		local targetPlaced: { [string]: string } = {}
		local placedCount = 0
		for slot = 1, pedestalSlots do
			local candidateIdx = 1 + slot
			if candidateIdx <= #ranked then
				targetPlaced[tostring(slot)] = ranked[candidateIdx].uid
				placedCount += 1
			end
		end

		-- Check if anything changes (skip writes if nothing changes)
		local sameEquipped = (targetEquippedUid == oldEquipped)
		local samePlaced = true
		for slot = 1, 10 do
			local k = tostring(slot)
			if (targetPlaced[k] or "") ~= (oldPlacedMap[k] or "") then
				samePlaced = false
				break
			end
		end
		for k, _ in oldPlacedMap do
			if not targetPlaced[k] then
				samePlaced = false
				break
			end
		end

		if sameEquipped and samePlaced then
			return true, "Best swords already equipped and placed!"
		end

		-- Atomically update EquippedSword and PlacedSwords
		local saved = DataService.SetMany(player, {
			EquippedSword = targetEquippedUid,
			PlacedSwords = targetPlaced,
		})

		if not saved then
			return false, "Failed to save equipped and placed swords."
		end

		local bestDef = swordDefMap[ranked[1].id]
		local bestName = if bestDef then bestDef.name else "best sword"
		local reply = ("Equipped %s and filled %d pedestal%s"):format(
			bestName,
			placedCount,
			if placedCount == 1 then "" else "s"
		)
		return true, reply
	end)

	PlayerActionLock.Release(player)

	if not ok then
		warn(("[InventoryService.EquipBest] Error for %s: %s"):format(player.Name, tostring(success)))
		return false, "An unexpected error occurred while equipping best swords."
	end

	return success, msg
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

	local equipBestFunc = Remotes.getFunction("EquipBest")
	equipBestFunc.OnServerInvoke = function(player: Player)
		return InventoryService.EquipBest(player)
	end

	local toggleLockFunc = Remotes.getFunction("ToggleLock")
	toggleLockFunc.OnServerInvoke = function(player: Player, uid: unknown)
		if typeof(uid) ~= "string" then
			return false, nil, "Invalid argument."
		end
		return InventoryService.ToggleLock(player, uid)
	end

	local getSellAllPreviewFunc = Remotes.getFunction("GetSellAllPreview")
	getSellAllPreviewFunc.OnServerInvoke = function(player: Player)
		return InventoryService.GetSellAllPreview(player)
	end

	local sellAllFunc = Remotes.getFunction("SellAll")
	sellAllFunc.OnServerInvoke = function(player: Player, token: unknown)
		if typeof(token) ~= "string" then
			return false, nil, nil, "Preview again"
		end
		return InventoryService.SellAll(player, token)
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
		sellSnapshots[player] = nil
	end)
end

return InventoryService
