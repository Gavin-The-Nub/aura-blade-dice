--!strict
-- GradeBadge: Specialized wrapper around generic Badge component for sword grades.
-- Uses Badge for consistent styling, Theme token resolution, and RainbowSequence UIGradients.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Config")
local Grades = require(Config:WaitForChild("Grades"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = Shared:WaitForChild("UI")
local Components = UI:WaitForChild("Components")
local Badge = require(Components:WaitForChild("Badge"))

export type GradeBadgeConfig = {
	Grade: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Parent: Instance?,
	ZIndex: number?,
}

local GradeBadge = {}

function GradeBadge.new(config: GradeBadgeConfig): Frame
	local gradeName = config.Grade or ""
	local def = Grades.GetGradeDef(gradeName)

	local badge = Badge.new({
		Text = if gradeName ~= "" then gradeName else "—",
		ColorToken = def and def.badgeColor or nil,
		Size = config.Size or UDim2.new(0, 24, 0, 18),
		Position = config.Position or UDim2.new(1, -2, 0, 2),
		AnchorPoint = config.AnchorPoint or Vector2.new(1, 0),
		Parent = config.Parent,
		ZIndex = config.ZIndex or 5,
		TextSize = 11,
	})
	badge.Name = "GradeBadge"

	local label = badge:FindFirstChild("BadgeLabel") :: TextLabel?
	if label then
		label.Name = "GradeLabel"
	end

	return badge
end

function GradeBadge.Update(badgeFrame: Frame, gradeName: string?)
	local def = Grades.GetGradeDef(gradeName)
	local text = if def then def.name else "—"
	local colorToken = def and def.badgeColor or nil

	Badge.Update(badgeFrame, text, colorToken)
end

return GradeBadge
