--!strict
-- DataService: loads, holds, and saves every player's profile (server only).
-- Other services read/change data ONLY through this module's API; nothing the client
-- sends is ever written here directly.
--
-- Persistence is delegated to ProfileStore (Vendor/ProfileStore), which provides the
-- DataStore retries, session locking, and the shutdown save (it binds its own
-- game:BindToClose). We add: autosave period, load retries, kick-on-failure, validation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local DataTemplate = require(ReplicatedStorage.Config.DataTemplate)
local GameConfig = require(ReplicatedStorage.Config.Game)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ProfileStore = require(ServerScriptService.Vendor.ProfileStore) :: any

local STORE_NAME = "PlayerData_v1"
local AUTO_SAVE_SECONDS = 60
local LOAD_ATTEMPTS = 3
-- Per-attempt cap for DataStore *errors*; session conflicts are handled separately by ProfileStore.
local ATTEMPT_TIMEOUT_SECONDS = 20

local KICK_LOAD_FAILED = "Your data could not be loaded, so we kicked you to keep it safe. Please rejoin in a minute."
local KICK_SESSION_ENDED = "Your data was opened on another server. Please rejoin."

-- Counters can never go negative; this also makes Increment(-cost) double as "can afford?".
local NON_NEGATIVE_KEYS: { [string]: boolean } = {
	Gold = true,
	Gems = true,
	Rebirths = true,
	DiceTier = true,
	LastLogout = true,
	PedestalSlots = true,
}

ProfileStore.SetConstant("AUTO_SAVE_PERIOD", AUTO_SAVE_SECONDS)
ProfileStore.SetConstant("START_SESSION_TIMEOUT", ATTEMPT_TIMEOUT_SECONDS)

local playerStore = ProfileStore.New(STORE_NAME, DataTemplate)

local profiles: { [Player]: any } = {}
local mockOfflineHours: { [Player]: number } = {}
local changedEvent = Instance.new("BindableEvent")

local DataService = {}

-- Fires (player, key, newValue) after any successful Set/Increment.
DataService.Changed = changedEvent.Event

-- Sets a mock offline duration (in hours) to be stamped when this player disconnects.
-- Studio-only testing helper for /fakeoffline command.
function DataService.SetMockOfflineHours(player: Player, hours: number)
	mockOfflineHours[player] = hours
end

local function profileKey(player: Player): string
	return tostring(player.UserId)
end

-- pcall + retries: ProfileStore retries DataStore errors internally, but it can still
-- throw or return nil (timeout / session conflict), so we retry a few times ourselves.
local function loadProfile(player: Player): any?
	for attempt = 1, LOAD_ATTEMPTS do
		local ok, result = pcall(function()
			return playerStore:StartSessionAsync(profileKey(player), {
				Cancel = function()
					return player.Parent ~= Players
				end,
			})
		end)
		if ok and result ~= nil then
			return result
		end
		if player.Parent ~= Players then
			return nil -- they left, no point retrying
		end
		warn(("[DataService] Load attempt %d/%d failed for %s: %s"):format(attempt, LOAD_ATTEMPTS, player.Name, tostring(result)))
		task.wait(attempt) -- small backoff between our own attempts
	end
	return nil
end

-- Stamps logout time and releases the profile (ProfileStore saves it as it releases).
local function releaseProfile(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return
	end
	profiles[player] = nil -- clear first so OnSessionEnd below doesn't try to kick

	local mockHours = mockOfflineHours[player]
	mockOfflineHours[player] = nil
	if mockHours and mockHours > 0 then
		profile.Data.LastLogout = os.time() - math.floor(mockHours * 3600)
	else
		profile.Data.LastLogout = os.time()
	end

	profile.Data.Gold = math.floor(profile.Data.Gold + 0.5) -- whole Gold only when saving
	profile:EndSession()
end

local function onPlayerAdded(player: Player)
	local profile = loadProfile(player)
	if profile == nil then
		-- Never hand out a blank profile: it would overwrite real progress on the next save.
		if player.Parent == Players then
			player:Kick(KICK_LOAD_FAILED)
		end
		return
	end

	if player.Parent ~= Players then
		profile:EndSession() -- left while loading
		return
	end

	profile:Reconcile() -- add any template fields this old profile is missing

	-- Migrate OwnedDice: ensure set exists and marks tiers 1..DiceTier as owned
	if type(profile.Data.OwnedDice) ~= "table" then
		local copy = {}
		local equipped = profile.Data.DiceTier or 1
		for t = 1, equipped do
			copy[tostring(t)] = true
		end
		copy["1"] = true
		profile.Data.OwnedDice = copy
	else
		local equipped = profile.Data.DiceTier or 1
		for t = 1, equipped do
			profile.Data.OwnedDice[tostring(t)] = true
		end
		profile.Data.OwnedDice["1"] = true
	end

	-- Ensure AutoSellRules has all rarity keys even if loaded from an older profile shape
	if type(profile.Data.AutoSellRules) ~= "table" then
		local copy = {}
		for k, v in DataTemplate.AutoSellRules do
			copy[k] = v
		end
		profile.Data.AutoSellRules = copy
	else
		for k, v in DataTemplate.AutoSellRules do
			if profile.Data.AutoSellRules[k] == nil then
				profile.Data.AutoSellRules[k] = v
			end
		end
	end

	-- Reset EquippedSword to "" if its uid isn't owned
	local equippedUid = profile.Data.EquippedSword
	if type(equippedUid) == "string" and equippedUid ~= "" then
		local owned = profile.Data.OwnedSwords
		local found = false
		if type(owned) == "table" then
			for _, entry in owned do
				if type(entry) == "table" and entry.uid == equippedUid then
					found = true
					break
				end
			end
		end
		if not found then
			profile.Data.EquippedSword = ""
		end
	end

	-- Migrate PedestalSlots: default to GameConfig.Plot.DefaultPedestalsPerPlot
	if type(profile.Data.PedestalSlots) ~= "number" or profile.Data.PedestalSlots < 1 then
		profile.Data.PedestalSlots = GameConfig.Plot.DefaultPedestalsPerPlot
	end
	local maxPedestalSlots = profile.Data.PedestalSlots

	-- Migrate PlacedSwords:
	-- Drop invalid slot keys (not "1".."10"), slots > PedestalSlots, unowned swords,
	-- duplicate swords across multiple slots (keep lowest slot), and currently equipped sword
	if type(profile.Data.PlacedSwords) ~= "table" then
		profile.Data.PlacedSwords = {}
	else
		local owned = profile.Data.OwnedSwords
		local ownedMap: { [string]: boolean } = {}
		if type(owned) == "table" then
			for _, entry in owned do
				if type(entry) == "table" and type(entry.uid) == "string" then
					ownedMap[entry.uid] = true
				end
			end
		end

		local equippedUid = profile.Data.EquippedSword
		local cleanedPlaced: { [string]: string } = {}
		local seenUids: { [string]: number } = {} -- uid -> lowest slot number

		for slotNum = 1, math.min(10, maxPedestalSlots) do
			local slotKey = tostring(slotNum)
			local uid = profile.Data.PlacedSwords[slotKey]
			if type(uid) == "string" and uid ~= "" then
				if ownedMap[uid] and uid ~= equippedUid and not seenUids[uid] then
					cleanedPlaced[slotKey] = uid
					seenUids[uid] = slotNum
				end
			end
		end

		profile.Data.PlacedSwords = cleanedPlaced
	end

	profile.OnSessionEnd:Connect(function()
		-- Fires when another server steals the session (or on release). Only kick on a steal.
		if profiles[player] == profile then
			profiles[player] = nil
			player:Kick(KICK_SESSION_ENDED)
		end
	end)

	profiles[player] = profile

	if ProfileStore.DataStoreState ~= "Access" and RunService:IsStudio() then
		warn("[DataService] DataStore API access is OFF: data uses a temporary mock store and will NOT persist between playtests.")
	end
end

local function onPlayerRemoving(player: Player)
	releaseProfile(player)
end

-- Start once from Main. Handles players already in the server as well as new joins.
function DataService.Start()
	local getInitialDataFunc = Remotes.getFunction("GetInitialData")
	getInitialDataFunc.OnServerInvoke = function(player: Player)
		if not DataService.WaitForProfile(player) then
			return nil
		end
		return DataService.GetAll(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Periodically refresh LastLogout on active profiles so that a server crash
	-- does not result in hours of free offline income when ProfileStore autosaves.
	-- If a mock offline duration is staged via /fakeoffline, skip overwriting it.
	task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_SECONDS)
			local now = os.time()
			for player, profile in profiles do
				if player.Parent == Players and profile.Data and not mockOfflineHours[player] then
					profile.Data.LastLogout = now
				end
			end
		end
	end)

	-- ProfileStore already saves everything on shutdown; this additionally stamps
	-- LastLogout for any profile PlayerRemoving didn't get to, and waits for them to release.
	game:BindToClose(function()
		for player in profiles do
			releaseProfile(player)
		end
		while next(profiles) ~= nil do
			task.wait()
		end
	end)
end

-- True once the player's data is loaded and usable.
function DataService.IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- Yields until the player's data is loaded. Returns false if they left or load failed.
function DataService.WaitForProfile(player: Player): boolean
	while profiles[player] == nil do
		if player.Parent ~= Players then
			return false
		end
		task.wait(0.1)
	end
	return true
end

-- Reads one field. Treat tables (e.g. OwnedSwords) as read-only; change them via Set.
function DataService.Get(player: Player, key: string): any?
	local profile = profiles[player]
	if profile == nil then
		return nil
	end
	return profile.Data[key]
end

-- Returns a deep-copied snapshot of the whole profile (safe to read/modify freely).
function DataService.GetAll(player: Player): DataTemplate.PlayerData?
	local profile = profiles[player]
	if profile == nil then
		return nil
	end
	local function deepCopy(value: any): any
		if type(value) ~= "table" then
			return value
		end
		local copy = {}
		for k, v in value do
			copy[k] = deepCopy(v)
		end
		return copy
	end
	return deepCopy(profile.Data)
end

-- Validates and writes one field. Returns false (and writes nothing) on bad input.
function DataService.Set(player: Player, key: string, value: any): boolean
	local profile = profiles[player]
	if profile == nil then
		return false
	end
	local templateValue = (DataTemplate :: any)[key]
	if templateValue == nil or type(value) ~= type(templateValue) then
		return false
	end
	if type(value) == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return false -- NaN / infinity would corrupt the save
		end
		if NON_NEGATIVE_KEYS[key] and value < 0 then
			return false
		end
		if key == "Gold" then
			value = math.floor(value + 0.5)
		end
	end
	profile.Data[key] = value
	changedEvent:Fire(player, key, value)
	if player.Parent == Players then
		task.spawn(function()
			local ok, event = pcall(function()
				return Remotes.getEvent("DataChanged")
			end)
			if ok and event then
				event:FireClient(player, key, value)
			end
		end)
	end
	return true
end

-- Validates and writes multiple fields atomically without yielding between them.
-- Fires Changed / DataChanged only after all keys are successfully updated.
-- If any key fails validation or writing, nothing is applied (rollback) and returns false.
function DataService.SetMany(player: Player, updates: { [string]: any }): boolean
	local profile = profiles[player]
	if profile == nil or typeof(updates) ~= "table" then
		return false
	end

	-- Pre-validation step
	local sanitized: { [string]: any } = {}
	local oldValues: { [string]: any } = {}

	for key, value in updates do
		local templateValue = (DataTemplate :: any)[key]
		if templateValue == nil or type(value) ~= type(templateValue) then
			return false
		end
		if type(value) == "number" then
			if value ~= value or value == math.huge or value == -math.huge then
				return false
			end
			if NON_NEGATIVE_KEYS[key] and value < 0 then
				return false
			end
			if key == "Gold" then
				value = math.floor(value + 0.5)
			end
		end
		sanitized[key] = value
		oldValues[key] = profile.Data[key]
	end

	-- Synchronous write without yields, with rollback safeguard
	local ok, err = pcall(function()
		for key, value in sanitized do
			profile.Data[key] = value
		end
	end)

	if not ok then
		-- Rollback
		for key, oldVal in oldValues do
			profile.Data[key] = oldVal
		end
		warn(("[DataService.SetMany] Failed to apply updates for %s, rolled back: %s"):format(player.Name, tostring(err)))
		return false
	end

	-- Fire Changed events after all fields are set
	for key, value in sanitized do
		changedEvent:Fire(player, key, value)
	end

	if player.Parent == Players then
		task.spawn(function()
			local okEvent, event = pcall(function()
				return Remotes.getEvent("DataChanged")
			end)
			if okEvent and event then
				for key, value in sanitized do
					event:FireClient(player, key, value)
				end
			end
		end)
	end

	return true
end

-- Adds (or subtracts, if negative) from a number field. Returns false if it would go below zero,
-- so spending is: `if DataService.Increment(player, "Gold", -cost) then give item end`.
function DataService.Increment(player: Player, key: string, amount: number): boolean
	local current = DataService.Get(player, key)
	if type(current) ~= "number" or type(amount) ~= "number" then
		return false
	end
	return DataService.Set(player, key, current + amount)
end

return DataService
