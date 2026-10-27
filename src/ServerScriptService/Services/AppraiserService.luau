--!strict
-- AppraiserService: Server-authoritative blade grading and auto grade roll service.
-- Powered by the generic AutoRollRunner helper.
-- Manages manual grade rolls (RollGrade) with atomic Gem deduction + OwnedSwords write,
-- and server-driven Auto Grade Roll (StartAutoGrade, StopAutoGrade) with live progress events.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Config.Game)
local Grades = require(ReplicatedStorage.Config.Grades)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local AutoRollRunner = require(ServerScriptService.AutoRollRunner)

local runner = AutoRollRunner.new({
	CurrencyKey = "Gems",
	CurrencyCost = (GameConfig.Appraiser and GameConfig.Appraiser.GemCost) or 1,
	SwordField = "grade",
	ProgressEventName = "AutoGradeProgress",
	RollFn = Grades.RollRandomGrade,
	GetRankFn = Grades.GetRank,
	GetLoopInterval = function(): number
		local appraiserCfg = GameConfig.Appraiser
		local minInterval = (appraiserCfg and appraiserCfg.MinAutoInterval) or 0.1
		local baseInterval = (appraiserCfg and appraiserCfg.AutoInterval) or 0.5
		return math.max(minInterval, baseInterval)
	end,
	ActionNoun = "Appraise",
	TargetNoun = "grade",
	CurrencyNoun = "Gems",
	RateLimitRollMessage = "Appraising too fast; please slow down.",
	NotEnoughCurrencyMessage = "Not enough Gems! 1 Gem required to appraise.",
	NotEnoughCurrencyRollMessage = "Not enough Gems! 1 Gem required to roll.",
	SaveErrorMessage = "Failed to save appraisal result.",
	DefaultValueName = "Ungraded",
})

local AppraiserService = {}

function AppraiserService.IsAutoRolling(player: Player): boolean
	return runner:IsAutoRolling(player)
end

function AppraiserService.RollGrade(player: Player, uid: unknown): (boolean, string?, string?, number?, string?)
	return runner:Roll(player, uid)
end

function AppraiserService.StartAutoGrade(player: Player, uid: unknown, targetGrade: unknown, maxGems: unknown): (boolean, string?)
	return runner:StartAuto(player, uid, targetGrade, maxGems)
end

function AppraiserService.StopAutoGrade(player: Player): (boolean, string?)
	return runner:StopAuto(player)
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
		runner:CleanupPlayer(player)
	end)
end

return AppraiserService
