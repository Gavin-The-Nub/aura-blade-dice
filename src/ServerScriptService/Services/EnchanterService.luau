--!strict
-- EnchanterService: Server-authoritative sword enchanting and auto enchant roll service.
-- Powered by the generic AutoRollRunner helper.
-- RollEnchant costs 1 EnchantToken with atomic token deduction + OwnedSwords write,
-- and server-driven Auto Enchant Roll (StartAutoEnchant, StopAutoEnchant) with live progress events.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Config.Game)
local Enchants = require(ReplicatedStorage.Config.Enchants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local AutoRollRunner = require(ServerScriptService.AutoRollRunner)

local runner = AutoRollRunner.new({
	CurrencyKey = "EnchantTokens",
	CurrencyCost = (GameConfig.Enchanter and GameConfig.Enchanter.TokenCost) or 1,
	SwordField = "enchant",
	ProgressEventName = "AutoEnchantProgress",
	RollFn = Enchants.RollRandomEnchant,
	GetRankFn = Enchants.GetRank,
	GetLoopInterval = function(): number
		local enchanterCfg = GameConfig.Enchanter
		local minInterval = (enchanterCfg and enchanterCfg.MinAutoInterval) or 0.1
		local baseInterval = (enchanterCfg and enchanterCfg.AutoInterval) or 0.5
		return math.max(minInterval, baseInterval)
	end,
	ActionNoun = "Enchant",
	TargetNoun = "enchant",
	CurrencyNoun = "Tokens",
})

local EnchanterService = {}

function EnchanterService.IsAutoRolling(player: Player): boolean
	return runner:IsAutoRolling(player)
end

function EnchanterService.RollEnchant(player: Player, uid: unknown): (boolean, string?, string?, number?, string?)
	return runner:Roll(player, uid)
end

function EnchanterService.StartAutoEnchant(player: Player, uid: unknown, targetEnchant: unknown, maxTokens: unknown): (boolean, string?)
	return runner:StartAuto(player, uid, targetEnchant, maxTokens)
end

function EnchanterService.StopAutoEnchant(player: Player): (boolean, string?)
	return runner:StopAuto(player)
end

function EnchanterService.Start()
	local rollEnchantFunc = Remotes.getFunction("RollEnchant")
	local startAutoEnchantFunc = Remotes.getFunction("StartAutoEnchant")
	local stopAutoEnchantFunc = Remotes.getFunction("StopAutoEnchant")

	rollEnchantFunc.OnServerInvoke = function(player: Player, uid: unknown)
		return EnchanterService.RollEnchant(player, uid)
	end

	startAutoEnchantFunc.OnServerInvoke = function(player: Player, uid: unknown, targetEnchant: unknown, maxTokens: unknown)
		return EnchanterService.StartAutoEnchant(player, uid, targetEnchant, maxTokens)
	end

	stopAutoEnchantFunc.OnServerInvoke = function(player: Player)
		return EnchanterService.StopAutoEnchant(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		runner:CleanupPlayer(player)
	end)
end

return EnchanterService
