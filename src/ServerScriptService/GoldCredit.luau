--!strict
-- GoldCredit: Server-only in-memory helper for fractional Gold remainder carry-over.
-- Eliminates high-frequency rounding bias on active taps and 1 Hz passive income ticks.
-- Not started by Main (passive utility module). Contains zero yields, ensuring atomic execution.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local DataService = require(ServerScriptService.Services.DataService)

local remainders: { [Player]: number } = {}

local GoldCredit = {}

-- NOTE on large balances: Above approximately 9e15 (2^53), standard Luau double precision integers
-- have a step size of >= 2, so additions like +12 are lost to double precision limits.
-- This is harmless by then, as early/mid-game balances operate with full precision and end-game
-- costs and earnings scale far past single-unit granularity.

-- Credits gold with fractional remainder carry-over.
-- Returns: (ok: boolean, wholeCredited: number)
function GoldCredit.Credit(player: Player, amount: number): (boolean, number)
	-- 1. Input sanitization: reject NaN, infinite, negative, or non-numeric values
	if type(amount) ~= "number" or amount ~= amount or amount == math.huge or amount == -math.huge or amount < 0 then
		return false, 0
	end

	-- Zero credit is a valid no-op (remainder unchanged)
	if amount == 0 then
		return true, 0
	end

	-- 2. Verify player profile is loaded
	if not DataService.IsLoaded(player) then
		return false, 0
	end

	-- 3. Calculate total and split into integer and fractional remainder
	local currentRemainder = remainders[player] or 0
	local total = currentRemainder + amount
	local whole = math.floor(total)
	local newRemainder = total - whole

	-- Strictly preserve [0, 1) invariant against IEEE 754 precision boundary quirks
	if newRemainder < 0 then
		newRemainder = 0
	elseif newRemainder >= 1 then
		whole += 1
		newRemainder -= 1
	end

	-- 4. Apply integer credit to ProfileStore via DataService
	if whole > 0 then
		local ok = DataService.Increment(player, "Gold", whole)
		if ok then
			-- Success: atomically update in-memory remainder
			remainders[player] = newRemainder
			return true, whole
		else
			-- Increment failure: profile closing or data error.
			-- Retain currentRemainder so fractional remainder is NOT lost or double-counted.
			return false, 0
		end
	else
		-- whole == 0: purely accumulating fraction (< 1 gold)
		remainders[player] = newRemainder
		return true, 0
	end
end

-- Inspects current in-memory fractional remainder for a player.
function GoldCredit.GetRemainder(player: Player): number
	return remainders[player] or 0
end

-- Clears fractional remainder for a player.
-- NOTE: Any future Rebirth Gold reset should call GoldCredit.Clear(player) to purge in-memory remainder.
function GoldCredit.Clear(player: Player)
	remainders[player] = nil
end

-- Clear in-memory remainder on player disconnect
Players.PlayerRemoving:Connect(function(player: Player)
	remainders[player] = nil
end)

return GoldCredit
