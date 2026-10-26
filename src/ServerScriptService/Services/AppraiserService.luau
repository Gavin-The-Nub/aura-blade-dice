--!strict
-- AppraiserService: Server-authoritative blade grading and auto grade roll service.
-- Manages manual grade rolls (RollGrade) with atomic Gem deduction + OwnedSwords write,
-- and server-driven Auto Grade Roll (StartAutoGrade, StopAutoGrade) with live progress events.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Config.Game)
local Grades = require(ReplicatedStorage.Config.Grades)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(ServerScriptService.Services.DataService)
local PlayerActionLock = require(ServerScriptService.PlayerActionLock)

type AutoRunState = {
	uid: string,
	targetGrade: string,
	rollsDone: number,
	gemsSpent: number,
	lastGrade: string,
	maxGems: number?,
	isRunning: boolean,
	stopReason: string?,
	thread: thread?,
}

local activeAutoRuns: { [Player]: AutoRunState } = {}
local lastRollTime: { [Player]: number } = {}
local lastAutoTime: { [Player]: number } = {}

local ROLL_RATE_LIMIT_SECONDS = 0.2
local AUTO_ACTION_RATE_LIMIT_SECONDS = 0.3

local AppraiserService = {}

-- Checks if a player currently has an active auto grade run
function AppraiserService.IsAutoRolling(player: Player): boolean
	local run = activeAutoRuns[player]
	return run ~= nil and run.isRunning == true
end

-- Manually rolls a grade for a sword.
-- Replaces existing grade. Rejects if auto-roll is running for player.
-- Deducts 1 Gem and writes new grade in ONE atomic DataService.SetMany.
function AppraiserService.RollGrade(player: Player, uid: unknown): (boolean, string?, string?, number?, string?)
	if typeof(uid) ~= "string" or uid == "" then
		return false, nil, nil, nil, "Invalid sword identifier."
	end

	if AppraiserService.IsAutoRolling(player) then
		return false, nil, nil, nil, "Cannot manually roll while auto grade roll is active."
	end

	-- Rate limiting check
	local now = os.clock()
	local lastTime = lastRollTime[player] or 0
	if now - lastTime < ROLL_RATE_LIMIT_SECONDS then
		return false, nil, nil, nil, "Appraising too fast; please slow down."
	end
	lastRollTime[player] = now

	if not PlayerActionLock.Acquire(player) then
		return false, nil, nil, nil, "Another inventory action is in progress."
	end

	local success, oldGrade, newGrade, remainingGems, err = false, nil, nil, nil, nil

	local ok, runErr = pcall(function()
		if not DataService.IsLoaded(player) then
			err = "Player data is not loaded."
			return
		end

		local gems = DataService.Get(player, "Gems")
		if typeof(gems) ~= "number" or gems < 1 then
			err = "Not enough Gems! 1 Gem required to appraise."
			return
		end

		local ownedSwords = DataService.Get(player, "OwnedSwords")
		if typeof(ownedSwords) ~= "table" then
			err = "Inventory data unavailable."
			return
		end

		local targetEntry: any = nil
		local targetIndex: number? = nil
		for idx, entry in ipairs(ownedSwords) do
			if typeof(entry) == "table" and entry.uid == uid then
				targetEntry = entry
				targetIndex = idx
				break
			end
		end

		if not targetEntry or not targetIndex then
			err = "Sword not found in your inventory."
			return
		end

		oldGrade = if typeof(targetEntry.grade) == "string" then targetEntry.grade else ""

		-- Roll weighted random grade
		local newGradeDef = Grades.RollRandomGrade()
		newGrade = newGradeDef.name

		-- Clone list and entry, update grade
		local updatedSwords = table.clone(ownedSwords)
		local updatedEntry = table.clone(targetEntry)
		updatedEntry.grade = newGrade
		updatedSwords[targetIndex] = updatedEntry

		local newGems = gems - 1

		-- Atomic write of both OwnedSwords and Gems together in one SetMany
		local writeOk = DataService.SetMany(player, {
			Gems = newGems,
			OwnedSwords = updatedSwords,
		})

		if not writeOk then
			err = "Failed to save appraisal result."
			return
		end

		remainingGems = newGems
		success = true
	end)

	PlayerActionLock.Release(player)

	if not ok then
		warn(("[AppraiserService.RollGrade] Error for %s: %s"):format(player.Name, tostring(runErr)))
		return false, nil, nil, nil, "An internal error occurred."
	end

	if not success then
		return false, nil, nil, nil, err or "Appraisal could not be completed."
	end

	return true, oldGrade, newGrade, remainingGems, nil
end

-- Halts any running auto grade roll for the player
function AppraiserService.StopAutoGrade(player: Player): (boolean, string?)
	local run = activeAutoRuns[player]
	if not run then
		return true, nil
	end

	run.isRunning = false
	run.stopReason = run.stopReason or "Stopped by player"

	local thread = run.thread
	run.thread = nil
	activeAutoRuns[player] = nil

	if player.Parent == Players then
		task.spawn(function()
			local ok, event = pcall(function()
				return Remotes.getEvent("AutoGradeProgress")
			end)
			if ok and event then
				event:FireClient(player, run.uid, run.rollsDone, run.gemsSpent, run.lastGrade, false, run.stopReason)
			end
		end)
	end

	if thread and thread ~= coroutine.running() then
		task.cancel(thread)
	end

	return true, nil
end

-- Starts the server-driven Auto Grade Roll loop for a sword.
function AppraiserService.StartAutoGrade(player: Player, uid: unknown, targetGrade: unknown, maxGems: unknown): (boolean, string?)
	if typeof(uid) ~= "string" or uid == "" then
		return false, "Invalid sword identifier."
	end
	if typeof(targetGrade) ~= "string" or targetGrade == "" then
		return false, "Invalid target grade."
	end

	local targetRank = Grades.GetRank(targetGrade)
	if targetRank == 0 then
		return false, ("Target grade '%s' is not recognized."):format(targetGrade)
	end

	local now = os.clock()
	if now - (lastAutoTime[player] or 0) < AUTO_ACTION_RATE_LIMIT_SECONDS then
		return false, "Action rate limited; please wait."
	end
	lastAutoTime[player] = now

	if AppraiserService.IsAutoRolling(player) then
		return false, "Auto grade roll is already active."
	end

	if not DataService.IsLoaded(player) then
		return false, "Player data is not loaded yet."
	end

	local ownedSwords = DataService.Get(player, "OwnedSwords")
	if typeof(ownedSwords) ~= "table" then
		return false, "Inventory data unavailable."
	end

	local targetEntry: any = nil
	for _, entry in ipairs(ownedSwords) do
		if typeof(entry) == "table" and entry.uid == uid then
			targetEntry = entry
			break
		end
	end

	if not targetEntry then
		return false, "Sword not found in your inventory."
	end

	local currentGrade = if typeof(targetEntry.grade) == "string" then targetEntry.grade else ""
	local currentRank = Grades.GetRank(currentGrade)

	if currentRank >= targetRank then
		return false, ("Sword already has grade %s (target is %s or better)."):format(
			if currentGrade ~= "" then currentGrade else "Ungraded",
			targetGrade
		)
	end

	local gems = DataService.Get(player, "Gems")
	if typeof(gems) ~= "number" or gems < 1 then
		return false, "Not enough Gems! 1 Gem required to roll."
	end

	local maxGemsLimit: number? = nil
	if typeof(maxGems) == "number" and maxGems > 0 and maxGems < math.huge then
		maxGemsLimit = math.floor(maxGems)
	end

	-- Compute loop interval from Config, clamped to safety minimum
	local appraiserCfg = GameConfig.Appraiser
	local minInterval = (appraiserCfg and appraiserCfg.MinAutoInterval) or 0.1
	local baseInterval = (appraiserCfg and appraiserCfg.AutoInterval) or 0.5
	local loopInterval = math.max(minInterval, baseInterval)

	local runState: AutoRunState = {
		uid = uid,
		targetGrade = targetGrade,
		rollsDone = 0,
		gemsSpent = 0,
		lastGrade = currentGrade,
		maxGems = maxGemsLimit,
		isRunning = true,
		stopReason = nil,
		thread = nil,
	}

	activeAutoRuns[player] = runState

	-- Spawn auto-grade execution loop
	runState.thread = task.spawn(function()
		local progressEvent = Remotes.getEvent("AutoGradeProgress")

		-- Send initial running state
		progressEvent:FireClient(player, uid, 0, 0, currentGrade, true, nil)

		while runState.isRunning do
			if player.Parent ~= Players or not DataService.IsLoaded(player) then
				runState.stopReason = "Player disconnected"
				break
			end

			-- Re-verify ownership, Gems, and target inside lock per roll
			local acquired = false
			for _ = 1, 5 do
				if PlayerActionLock.Acquire(player) then
					acquired = true
					break
				end
				task.wait(0.05)
			end

			if not acquired then
				-- Skip this tick and retry next iteration if busy
				task.wait(loopInterval)
				continue
			end

			local shouldStop = false
			local stopReason: string? = nil
			local rolledGradeName: string? = nil

			local ok, loopErr = pcall(function()
				if runState.maxGems and runState.gemsSpent >= runState.maxGems then
					shouldStop = true
					stopReason = "Max Gems limit reached"
					return
				end

				local currentGems = DataService.Get(player, "Gems")
				if typeof(currentGems) ~= "number" or currentGems < 1 then
					shouldStop = true
					stopReason = "Out of Gems"
					return
				end

				local currentSwords = DataService.Get(player, "OwnedSwords")
				if typeof(currentSwords) ~= "table" then
					shouldStop = true
					stopReason = "Inventory unavailable"
					return
				end

				local entryIndex: number? = nil
				local entryFound: any = nil
				for idx, entry in ipairs(currentSwords) do
					if typeof(entry) == "table" and entry.uid == uid then
						entryIndex = idx
						entryFound = entry
						break
					end
				end

				if not entryIndex or not entryFound then
					shouldStop = true
					stopReason = "Sword no longer exists"
					return
				end

				local checkRank = Grades.GetRank(entryFound.grade)
				if checkRank >= targetRank then
					shouldStop = true
					stopReason = "Target grade reached"
					return
				end

				-- Perform roll
				local newGradeDef = Grades.RollRandomGrade()
				rolledGradeName = newGradeDef.name

				local updatedSwords = table.clone(currentSwords)
				local updatedEntry = table.clone(entryFound)
				updatedEntry.grade = rolledGradeName
				updatedSwords[entryIndex] = updatedEntry

				local setOk = DataService.SetMany(player, {
					Gems = currentGems - 1,
					OwnedSwords = updatedSwords,
				})

				if not setOk then
					shouldStop = true
					stopReason = "Save error"
					return
				end

				runState.rollsDone += 1
				runState.gemsSpent += 1
				runState.lastGrade = rolledGradeName

				local newRank = Grades.GetRank(rolledGradeName)
				if newRank >= targetRank then
					shouldStop = true
					stopReason = "Target grade reached"
				end
			end)

			PlayerActionLock.Release(player)

			if not ok then
				warn(("[AppraiserService.AutoGrade] Error during roll: %s"):format(tostring(loopErr)))
				runState.stopReason = "Internal error"
				break
			end

			if shouldStop then
				runState.stopReason = stopReason
				break
			end

			-- Fire client progress
			progressEvent:FireClient(
				player,
				uid,
				runState.rollsDone,
				runState.gemsSpent,
				runState.lastGrade,
				true,
				nil
			)

			task.wait(loopInterval)
		end

		-- Loop concluded
		runState.isRunning = false
		if activeAutoRuns[player] == runState then
			activeAutoRuns[player] = nil
		end

		if player.Parent == Players then
			progressEvent:FireClient(
				player,
				uid,
				runState.rollsDone,
				runState.gemsSpent,
				runState.lastGrade,
				false,
				runState.stopReason or "Finished"
			)
		end
	end)

	return true, nil
end

function AppraiserService.Start()
	local rollGradeFunc = Remotes.getFunction("RollGrade")
	local startAutoGradeFunc = Remotes.getFunction("StartAutoGrade")
	local stopAutoGradeFunc = Remotes.getFunction("StopAutoGrade")

	rollGradeFunc.OnServerInvoke = function(player: Player, uid: unknown)
		return AppraiserService.RollGrade(player, uid)
	end

	startAutoGradeFunc.OnServerInvoke = function(player: Player, uid: unknown, targetGrade: unknown, maxGems: unknown)
		return AppraiserService.StartAutoGrade(player, uid, targetGrade, maxGems)
	end

	stopAutoGradeFunc.OnServerInvoke = function(player: Player)
		return AppraiserService.StopAutoGrade(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		AppraiserService.StopAutoGrade(player)
		lastRollTime[player] = nil
		lastAutoTime[player] = nil
	end)
end

return AppraiserService
