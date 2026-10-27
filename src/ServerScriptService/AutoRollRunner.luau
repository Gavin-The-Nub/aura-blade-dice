--!strict
-- AutoRollRunner: Data-driven server runner for single and automated rolls (Grades, Enchants).
-- Contains NO game-specific rules: all currencies, sword fields, rank functions, roll functions,
-- intervals, nouns, and remotes are injected via the configuration table.
-- Guarantees:
-- - PlayerActionLock on every manual or auto roll
-- - Single non-yielding atomic DataService.SetMany per roll
-- - Full validation (balance, ownership, target rank) re-checked inside the lock on EVERY iteration
-- - Graceful stops on player leave, UI close, out of currency, sword missing, max currency reached, or target reached

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(ServerScriptService.Services.DataService)
local PlayerActionLock = require(ServerScriptService.PlayerActionLock)

export type RollResultItem = {
	name: string,
	[string]: any,
}

export type RunnerConfig = {
	CurrencyKey: string,              -- "Gems" or "EnchantTokens"
	CurrencyCost: number,             -- typically 1
	SwordField: string,               -- "grade" or "enchant"
	ProgressEventName: string,        -- "AutoGradeProgress" or "AutoEnchantProgress"
	RollFn: () -> RollResultItem,
	GetRankFn: (name: string?) -> number,
	GetLoopInterval: () -> number,
	ActionNoun: string,               -- "Appraise" or "Enchant"
	TargetNoun: string,               -- "grade" or "enchant"
	CurrencyNoun: string,             -- "Gems" or "Tokens"
	RateLimitRollMessage: string?,
	NotEnoughCurrencyMessage: string?,
	NotEnoughCurrencyRollMessage: string?,
	SaveErrorMessage: string?,
	DefaultValueName: string?,
}

type AutoRunState = {
	uid: string,
	targetName: string,
	targetRank: number,
	rollsDone: number,
	currencySpent: number,
	lastValue: string,
	maxCurrency: number?,
	isRunning: boolean,
	stopReason: string?,
	thread: thread?,
}

export type AutoRollRunnerInstance = {
	config: RunnerConfig,
	IsAutoRolling: (self: AutoRollRunnerInstance, player: Player) -> boolean,
	Roll: (self: AutoRollRunnerInstance, player: Player, uid: unknown) -> (boolean, string?, string?, number?, string?),
	StartAuto: (self: AutoRollRunnerInstance, player: Player, uid: unknown, targetName: unknown, maxCurrency: unknown) -> (boolean, string?),
	StopAuto: (self: AutoRollRunnerInstance, player: Player) -> (boolean, string?),
	CleanupPlayer: (self: AutoRollRunnerInstance, player: Player) -> (),
}

local ROLL_RATE_LIMIT_SECONDS = 0.2
local AUTO_ACTION_RATE_LIMIT_SECONDS = 0.3

local AutoRollRunner = {}

function AutoRollRunner.new(config: RunnerConfig): AutoRollRunnerInstance
	local activeAutoRuns: { [Player]: AutoRunState } = {}
	local lastRollTime: { [Player]: number } = {}
	local lastAutoTime: { [Player]: number } = {}

	local self = {} :: AutoRollRunnerInstance
	self.config = config

	function self:IsAutoRolling(player: Player): boolean
		local run = activeAutoRuns[player]
		return run ~= nil and run.isRunning == true
	end

	function self:Roll(player: Player, uid: unknown): (boolean, string?, string?, number?, string?)
		if typeof(uid) ~= "string" or uid == "" then
			return false, nil, nil, nil, "Invalid sword identifier."
		end

		if self:IsAutoRolling(player) then
			return false, nil, nil, nil, ("Cannot manually roll while auto %s roll is active."):format(config.TargetNoun)
		end

		-- Rate limiting check
		local now = os.clock()
		local lastTime = lastRollTime[player] or 0
		if now - lastTime < ROLL_RATE_LIMIT_SECONDS then
			return false, nil, nil, nil, config.RateLimitRollMessage or ("Rolling %s too fast; please slow down."):format(config.TargetNoun)
		end
		lastRollTime[player] = now

		if not PlayerActionLock.Acquire(player) then
			return false, nil, nil, nil, "Another inventory action is in progress."
		end

		local success, oldValue, newValue, remainingCurrency, err = false, nil, nil, nil, nil

		local ok, runErr = pcall(function()
			if not DataService.IsLoaded(player) then
				err = "Player data is not loaded."
				return
			end

			local balance = DataService.Get(player, config.CurrencyKey)
			if typeof(balance) ~= "number" or balance < config.CurrencyCost then
				err = config.NotEnoughCurrencyMessage or ("Not enough %s! %d %s required to %s."):format(
					config.CurrencyNoun,
					config.CurrencyCost,
					config.CurrencyNoun,
					config.ActionNoun:lower()
				)
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

			local currentFieldVal = targetEntry[config.SwordField]
			oldValue = if typeof(currentFieldVal) == "string" then currentFieldVal else ""

			-- Execute weighted roll
			local rolledItem = config.RollFn()
			newValue = rolledItem.name

			-- Clone list and entry, update field
			local updatedSwords = table.clone(ownedSwords)
			local updatedEntry = table.clone(targetEntry)
			updatedEntry[config.SwordField] = newValue
			updatedSwords[targetIndex] = updatedEntry

			local newBalance = balance - config.CurrencyCost

			-- Atomic write of both OwnedSwords and currency together in one SetMany
			local writeOk = DataService.SetMany(player, {
				[config.CurrencyKey] = newBalance,
				OwnedSwords = updatedSwords,
			})

			if not writeOk then
				err = config.SaveErrorMessage or ("Failed to save %s result."):format(config.TargetNoun)
				return
			end

			remainingCurrency = newBalance
			success = true
		end)

		PlayerActionLock.Release(player)

		if not ok then
			warn(("[AutoRollRunner.Roll] Error for %s (%s): %s"):format(player.Name, config.TargetNoun, tostring(runErr)))
			return false, nil, nil, nil, "An internal error occurred."
		end

		if not success then
			return false, nil, nil, nil, err or ("%s could not be completed."):format(config.ActionNoun)
		end

		return true, oldValue, newValue, remainingCurrency, nil
	end

	function self:StopAuto(player: Player): (boolean, string?)
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
					return Remotes.getEvent(config.ProgressEventName)
				end)
				if ok and event then
					event:FireClient(player, run.uid, run.rollsDone, run.currencySpent, run.lastValue, false, run.stopReason)
				end
			end)
		end

		if thread and thread ~= coroutine.running() then
			task.cancel(thread)
		end

		return true, nil
	end

	function self:StartAuto(player: Player, uid: unknown, targetName: unknown, maxCurrency: unknown): (boolean, string?)
		if typeof(uid) ~= "string" or uid == "" then
			return false, "Invalid sword identifier."
		end
		if typeof(targetName) ~= "string" or targetName == "" then
			return false, ("Invalid target %s."):format(config.TargetNoun)
		end

		local targetRank = config.GetRankFn(targetName)
		if targetRank == 0 then
			return false, ("Target %s '%s' is not recognized."):format(config.TargetNoun, targetName)
		end

		local now = os.clock()
		if now - (lastAutoTime[player] or 0) < AUTO_ACTION_RATE_LIMIT_SECONDS then
			return false, "Action rate limited; please wait."
		end
		lastAutoTime[player] = now

		if self:IsAutoRolling(player) then
			return false, ("Auto %s roll is already active."):format(config.TargetNoun)
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

		local currentVal = if typeof(targetEntry[config.SwordField]) == "string" then targetEntry[config.SwordField] else ""
		local currentRank = config.GetRankFn(currentVal)

		if currentRank >= targetRank then
			return false, ("Sword already has %s %s (target is %s or better)."):format(
				config.TargetNoun,
				if currentVal ~= "" then currentVal else (config.DefaultValueName or "None"),
				targetName
			)
		end

		local balance = DataService.Get(player, config.CurrencyKey)
		if typeof(balance) ~= "number" or balance < config.CurrencyCost then
			return false, config.NotEnoughCurrencyRollMessage or ("Not enough %s! %d %s required to roll."):format(
				config.CurrencyNoun,
				config.CurrencyCost,
				config.CurrencyNoun
			)
		end

		local maxCurrencyLimit: number? = nil
		if typeof(maxCurrency) == "number" and maxCurrency > 0 and maxCurrency < math.huge then
			maxCurrencyLimit = math.floor(maxCurrency)
		end

		local loopInterval = config.GetLoopInterval()

		local runState: AutoRunState = {
			uid = uid,
			targetName = targetName,
			targetRank = targetRank,
			rollsDone = 0,
			currencySpent = 0,
			lastValue = currentVal,
			maxCurrency = maxCurrencyLimit,
			isRunning = true,
			stopReason = nil,
			thread = nil,
		}

		activeAutoRuns[player] = runState

		-- Spawn auto execution loop
		runState.thread = task.spawn(function()
			local progressEvent = Remotes.getEvent(config.ProgressEventName)

			-- Send initial running state
			progressEvent:FireClient(player, uid, 0, 0, currentVal, true, nil)

			while runState.isRunning do
				if player.Parent ~= Players or not DataService.IsLoaded(player) then
					runState.stopReason = "Player disconnected"
					break
				end

				-- Re-verify ownership, balance, and target inside lock per roll
				local acquired = false
				for _ = 1, 5 do
					if PlayerActionLock.Acquire(player) then
						acquired = true
						break
					end
					task.wait(0.05)
				end

				if not acquired then
					task.wait(loopInterval)
					continue
				end

				local shouldStop = false
				local stopReason: string? = nil
				local rolledValueName: string? = nil

				local ok, loopErr = pcall(function()
					if runState.maxCurrency and runState.currencySpent >= runState.maxCurrency then
						shouldStop = true
						stopReason = ("Max %s limit reached"):format(config.CurrencyNoun)
						return
					end

					local currentBal = DataService.Get(player, config.CurrencyKey)
					if typeof(currentBal) ~= "number" or currentBal < config.CurrencyCost then
						shouldStop = true
						stopReason = ("Out of %s"):format(config.CurrencyNoun)
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

					local checkRank = config.GetRankFn(entryFound[config.SwordField])
					if checkRank >= runState.targetRank then
						shouldStop = true
						stopReason = ("Target %s reached"):format(config.TargetNoun)
						return
					end

					-- Perform weighted roll
					local rolledItem = config.RollFn()
					rolledValueName = rolledItem.name

					local updatedSwords = table.clone(currentSwords)
					local updatedEntry = table.clone(entryFound)
					updatedEntry[config.SwordField] = rolledValueName
					updatedSwords[entryIndex] = updatedEntry

					local setOk = DataService.SetMany(player, {
						[config.CurrencyKey] = currentBal - config.CurrencyCost,
						OwnedSwords = updatedSwords,
					})

					if not setOk then
						shouldStop = true
						stopReason = "Save error"
						return
					end

					runState.rollsDone += 1
					runState.currencySpent += config.CurrencyCost
					runState.lastValue = rolledValueName

					local newRank = config.GetRankFn(rolledValueName)
					if newRank >= runState.targetRank then
						shouldStop = true
						stopReason = ("Target %s reached"):format(config.TargetNoun)
					end
				end)

				PlayerActionLock.Release(player)

				if not ok then
					warn(("[AutoRollRunner.Auto] Error during roll (%s): %s"):format(config.TargetNoun, tostring(loopErr)))
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
					runState.currencySpent,
					runState.lastValue,
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
					runState.currencySpent,
					runState.lastValue,
					false,
					runState.stopReason or "Finished"
				)
			end
		end)

		return true, nil
	end

	function self:CleanupPlayer(player: Player)
		self:StopAuto(player)
		lastRollTime[player] = nil
		lastAutoTime[player] = nil
	end

	return self
end

return AutoRollRunner
