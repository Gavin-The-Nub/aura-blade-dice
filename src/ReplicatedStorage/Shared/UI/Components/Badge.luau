--!strict
-- Badge: Reusable, generalized badge component for rendering pill badges with Theme tokens.
-- Encapsulates RainbowSequence UIGradient styling for top-tier items (Grade Z+, Enchant Singularity)
-- without duplicating gradient creation or cleanup logic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))

export type BadgeConfig = {
	Text: string?,
	ColorToken: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Parent: Instance?,
	ZIndex: number?,
	AutomaticSize: Enum.AutomaticSize?,
	TextSize: number?,
	CornerRadius: UDim?,
}

local Badge = {}

local function resolveThemeColor(tokenName: string?): Color3
	if typeof(tokenName) == "string" then
		local colorsTable = Theme.Colors :: any
		if typeof(colorsTable[tokenName]) == "Color3" then
			return colorsTable[tokenName]
		end
	end
	return Theme.Colors.TextPrimary
end

function Badge.ApplyStyle(badgeFrame: Frame, colorToken: string?, text: string?)
	local label = (badgeFrame:FindFirstChild("BadgeLabel")
		or badgeFrame:FindFirstChild("GradeLabel")
		or badgeFrame:FindFirstChild("EnchantLabel")
		or badgeFrame:FindFirstChildOfClass("TextLabel")) :: TextLabel?
	local stroke = badgeFrame:FindFirstChild("BadgeStroke") :: UIStroke?

	-- Remove old gradients
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
		if text ~= nil then
			label.Text = text
		end
	end

	if colorToken == "AuraRainbow" then
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
	elseif colorToken and colorToken ~= "" then
		local color = resolveThemeColor(colorToken)
		if stroke then
			stroke.Color = color
		end
		if label then
			label.TextColor3 = color
		end
	else
		-- Missing / default styling
		if stroke then
			stroke.Color = Theme.Colors.BorderSubtle
		end
		if label then
			label.TextColor3 = Theme.Colors.TextMuted
			if text == nil then
				label.Text = "—"
			end
		end
	end
end

function Badge.new(config: BadgeConfig): Frame
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.Size = config.Size or UDim2.new(0, 36, 0, 18)
	badge.Position = config.Position or UDim2.new(1, -2, 0, 2)
	badge.AnchorPoint = config.AnchorPoint or Vector2.new(1, 0)
	badge.BackgroundColor3 = Theme.Colors.PanelBackground
	badge.BackgroundTransparency = 0.15
	badge.BorderSizePixel = 0
	badge.ZIndex = config.ZIndex or 5
	if config.AutomaticSize then
		badge.AutomaticSize = config.AutomaticSize
	end
	if config.Parent then
		badge.Parent = config.Parent
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = config.CornerRadius or Theme.Corner.Small
	corner.Parent = badge

	local stroke = Instance.new("UIStroke")
	stroke.Name = "BadgeStroke"
	stroke.Thickness = Theme.Stroke.WidthThin
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = badge

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 4)
	padding.Parent = badge

	local label = Instance.new("TextLabel")
	label.Name = "BadgeLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Theme.Fonts.Button
	label.TextSize = config.TextSize or 11
	label.Text = config.Text or "—"
	label.ZIndex = (config.ZIndex or 5) + 1
	label.Parent = badge

	Badge.ApplyStyle(badge, config.ColorToken, config.Text)

	return badge
end

function Badge.Update(badgeFrame: Frame, text: string?, colorToken: string?)
	Badge.ApplyStyle(badgeFrame, colorToken, text)
end

return Badge
