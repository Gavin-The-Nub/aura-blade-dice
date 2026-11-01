--!strict
-- BlessingBadge: Specialized wrapper around generic Badge component for sword blessings.
-- Uses Badge for consistent styling, Theme token resolution, and formatting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Config")
local Blessings = require(Config:WaitForChild("Blessings"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local Components = UI:WaitForChild("Components")
local Badge = require(Components:WaitForChild("Badge"))

export type BlessingBadgeConfig = {
	Blessing: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Parent: Instance?,
	ZIndex: number?,
	AutomaticSize: Enum.AutomaticSize?,
	TextSize: number?,
}

local BlessingBadge = {}

function BlessingBadge.new(config: BlessingBadgeConfig): Frame
	local blessingName = config.Blessing or ""
	local def = Blessings.GetBlessingDef(blessingName)

	local badge = Badge.new({
		Text = if blessingName ~= "" then blessingName else "—",
		ColorToken = def and def.badgeColor or nil,
		Size = config.Size or UDim2.new(0, 52, 0, 18),
		Position = config.Position or UDim2.new(1, -2, 0, 2),
		AnchorPoint = config.AnchorPoint or Vector2.new(1, 0),
		Parent = config.Parent,
		ZIndex = config.ZIndex or 5,
		AutomaticSize = config.AutomaticSize or Enum.AutomaticSize.X,
		TextSize = config.TextSize or 11,
	})
	badge.Name = "BlessingBadge"

	local label = badge:FindFirstChild("BadgeLabel") :: TextLabel?
	if label then
		label.Name = "BlessingLabel"
	end

	return badge
end

function BlessingBadge.Update(badgeFrame: Frame, blessingName: string?)
	local def = Blessings.GetBlessingDef(blessingName)
	local text = if def then def.name else "—"
	local colorToken = def and def.badgeColor or nil

	Badge.Update(badgeFrame, text, colorToken)
end

return BlessingBadge
