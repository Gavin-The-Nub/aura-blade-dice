--!strict
-- Shared/SalePrice: Central pure function for sword sale price calculation.
-- Used by server (InventoryService, RollService) and client (InventoryUI, SellStallUI).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("Game"))
local Swords = require(Config:WaitForChild("Swords"))

local swordDefMap: { [string]: Swords.SwordDef } = {}
for _, def in Swords do
	swordDefMap[def.id] = def
end

local SalePrice = {}

-- Pure calculation of sale price for an owned sword entry or definition table.
-- Formula: math.max(1, math.floor(baseDamage * BaseDamageMultiplier * gradeMultiplier * enchantMultiplier + 0.5))
-- Missing grade/enchant fields count as zero / default 1.0 multiplier.
function SalePrice.calculate(swordEntryOrDef: any): number
	if typeof(swordEntryOrDef) ~= "table" then
		return 1
	end

	local baseDamage = 1
	if typeof(swordEntryOrDef.baseDamage) == "number" then
		baseDamage = swordEntryOrDef.baseDamage
	elseif swordEntryOrDef.id and swordDefMap[swordEntryOrDef.id] then
		baseDamage = swordDefMap[swordEntryOrDef.id].baseDamage
	end

	local mult = (GameConfig.Selling and GameConfig.Selling.BaseDamageMultiplier) or 10
	local gradeMultiplier = 1.0 -- placeholder until Grades system is added
	local enchantMultiplier = 1.0 -- placeholder until Enchants system is added

	return math.max(1, math.floor((baseDamage * mult * gradeMultiplier * enchantMultiplier) + 0.5))
end

return SalePrice
