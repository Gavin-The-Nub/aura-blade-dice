--!strict
-- EnchantBadge: Specialized wrapper around generic Badge component for sword enchants.
-- Uses Badge for consistent styling, Theme token resolution, and RainbowSequence UIGradients (Singularity).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Config")
local Enchants = require(Config:WaitForChild("Enchants"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local Components = UI:WaitForChild("Components")
local Badge = require(Components:WaitForChild("Badge"))

export type EnchantBadgeConfig = {
	Enchant: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Parent: Instance?,
	ZIndex: number?,
	AutomaticSize: Enum.AutomaticSize?,
	TextSize: number?,
}

local EnchantBadge = {}

function EnchantBadge.new(config: EnchantBadgeConfig): Frame
	local enchantName = config.Enchant or ""
	local def = Enchants.GetEnchantDef(enchantName)

	local badge = Badge.new({
		Text = if enchantName ~= "" then enchantName else "—",
		ColorToken = def and def.badgeColor or nil,
		Size = config.Size or UDim2.new(0, 52, 0, 18),
		Position = config.Position or UDim2.new(1, -2, 0, 2),
		AnchorPoint = config.AnchorPoint or Vector2.new(1, 0),
		Parent = config.Parent,
		ZIndex = config.ZIndex or 5,
		AutomaticSize = config.AutomaticSize or Enum.AutomaticSize.X,
		TextSize = config.TextSize or 11,
	})
	badge.Name = "EnchantBadge"

	local label = badge:FindFirstChild("BadgeLabel") :: TextLabel?
	if label then
		label.Name = "EnchantLabel"
	end

	return badge
end

function EnchantBadge.Update(badgeFrame: Frame, enchantName: string?)
	local def = Enchants.GetEnchantDef(enchantName)
	local text = if def then def.name else "—"
	local colorToken = def and def.badgeColor or nil

	Badge.Update(badgeFrame, text, colorToken)
end

return EnchantBadge
