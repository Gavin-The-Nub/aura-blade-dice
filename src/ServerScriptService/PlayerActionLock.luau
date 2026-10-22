--!strict
-- PlayerActionLock: Shared per-player mutex to serialize inventory and pedestal operations
-- (Equip, Sell, EquipBest, PlaceSword, RemoveSword). Always releases on error and clears on disconnect.

local Players = game:GetService("Players")

local locks: { [Player]: boolean } = {}

local PlayerActionLock = {}

-- Attempts to acquire the action lock for a player. Returns true if acquired, false if busy.
function PlayerActionLock.Acquire(player: Player): boolean
	if locks[player] then
		return false
	end
	locks[player] = true
	return true
end

-- Releases the action lock for a player.
function PlayerActionLock.Release(player: Player)
	locks[player] = nil
end

-- Checks if a player's action lock is held.
function PlayerActionLock.IsLocked(player: Player): boolean
	return locks[player] == true
end

-- Automatically cleans up on player disconnect
Players.PlayerRemoving:Connect(function(player: Player)
	locks[player] = nil
end)

return PlayerActionLock
