--!strict
-- GradeBadge: Reusable UI component for rendering sword grade badges.
-- Resolves badge color from Theme tokens and applies RainbowSequence UIGradient for Z+.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Config = ReplicatedStorage:WaitForChild("Config")
local Grades = require(Config:WaitForChild("Grades"))

export type GradeBadgeConfig = {
	Grade: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Parent: Instance?,
	ZIndex: number?,
}

local GradeBadge = {}

local function resolveThemeColor(tokenName: string): Color3
	local colorsTable = Theme.Colors :: any
	if typeof(colorsTable[tokenName]) == "Color3" then
		return colorsTable[tokenName]
	end
	return Theme.Colors.TextPrimary
end

function GradeBadge.new(config: GradeBadgeConfig): Frame
	local gradeName = config.Grade or ""
	local def = Grades.GetGradeDef(gradeName)

	local badge = Instance.new("Frame")
	badge.Name = "GradeBadge"
	badge.Size = config.Size or UDim2.new(0, 24, 0, 18)
	badge.Position = config.Position or UDim2.new(1, -2, 0, 2)
	badge.AnchorPoint = config.AnchorPoint or Vector2.new(1, 0)
	badge.BackgroundColor3 = Theme.Colors.PanelBackground
	badge.BackgroundTransparency = 0.15
	badge.BorderSizePixel = 0
	badge.ZIndex = config.ZIndex or 5
	if config.Parent then
		badge.Parent = config.Parent
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.Corner.Small
	corner.Parent = badge

	local stroke = Instance.new("UIStroke")
	stroke.Name = "BadgeStroke"
	stroke.Thickness = Theme.Stroke.WidthThin
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = badge

	local label = Instance.new("TextLabel")
	label.Name = "GradeLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Theme.Fonts.Button
	label.TextSize = 11
	label.Text = if gradeName ~= "" then gradeName else "-"
	label.ZIndex = (config.ZIndex or 5) + 1
	label.Parent = badge

	if def then
		if def.badgeColor == "AuraRainbow" then
			-- Rainbow badge with gradient
			local gradStroke = Instance.new("UIGradient")
			gradStroke.Color = Theme.RainbowSequence
			gradStroke.Parent = stroke

			local gradText = Instance.new("UIGradient")
			gradText.Color = Theme.RainbowSequence
			gradText.Parent = label

			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			stroke.Color = Color3.fromRGB(255, 255, 255)
		else
			local color = resolveThemeColor(def.badgeColor)
			stroke.Color = color
			label.TextColor3 = color
		end
	else
		-- Ungraded / missing
		stroke.Color = Theme.Colors.BorderSubtle
		label.TextColor3 = Theme.Colors.TextMuted
		label.Text = "—"
	end

	return badge
end

-- Updates an existing badge frame created by GradeBadge.new
function GradeBadge.Update(badgeFrame: Frame, gradeName: string?)
	local def = Grades.GetGradeDef(gradeName)
	local label = badgeFrame:FindFirstChild("GradeLabel") :: TextLabel?
	local stroke = badgeFrame:FindFirstChild("BadgeStroke") :: UIStroke?

	if stroke then
		local oldGrad = stroke:FindFirstChildOfClass("UIGradient")
		if oldGrad then
			oldGrad:Destroy()
		end
	end
	if label then
		local oldGrad = label:FindFirstChildOfClass("UIGradient")
		if oldGrad then
			oldGrad:Destroy()
		end
	end

	if def then
		if label then
			label.Text = def.name
		end
		if def.badgeColor == "AuraRainbow" then
			if stroke then
				stroke.Color = Color3.fromRGB(255, 255, 255)
				local gradStroke = Instance.new("UIGradient")
				gradStroke.Color = Theme.RainbowSequence
				gradStroke.Parent = stroke
			end
			if label then
				label.TextColor3 = Color3.fromRGB(255, 255, 255)
				local gradText = Instance.new("UIGradient")
				gradText.Color = Theme.RainbowSequence
				gradText.Parent = label
			end
		else
			local color = resolveThemeColor(def.badgeColor)
			if stroke then
				stroke.Color = color
			end
			if label then
				label.TextColor3 = color
			end
		end
	else
		if stroke then
			stroke.Color = Theme.Colors.BorderSubtle
		end
		if label then
			label.TextColor3 = Theme.Colors.TextMuted
			label.Text = "—"
		end
	end
end

return GradeBadge
