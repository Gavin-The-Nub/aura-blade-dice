--!strict
-- Reusable Button component with touch/mouse micro-interactions and mobile-first sizing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))

export type ButtonConfig = {
	Name: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Text: string?,
	SubText: string?,
	IconText: string?,
	IconColor: Color3?,
	BackgroundColor: Color3?,
	BorderColor: Color3?,
	TextColor: Color3?,
	CornerRadius: UDim?,
	LayoutOrder: number?,
	Direction: string?, -- "Vertical" | "Horizontal" (defaults to "Horizontal" or auto)
	Parent: Instance?,
	OnClick: (() -> ())?,
}

export type ButtonComponent = {
	Instance: TextButton,
	SetText: (self: ButtonComponent, text: string) -> (),
	SetEnabled: (self: ButtonComponent, enabled: boolean) -> (),
	SetBorderColor: (self: ButtonComponent, color: Color3) -> (),
	SetTextColor: (self: ButtonComponent, color: Color3) -> (),
	Destroy: (self: ButtonComponent) -> (),
}

local Button = {}

function Button.new(config: ButtonConfig): ButtonComponent
	local isVertical = config.Direction == "Vertical"
	local button = Instance.new("TextButton")
	button.Name = config.Name or "ThemedButton"
	button.Size = config.Size or UDim2.new(1, 0, 1, 0)
	button.Position = config.Position or UDim2.new(0, 0, 0, 0)
	button.AnchorPoint = config.AnchorPoint or Vector2.new(0, 0)
	button.BackgroundColor3 = config.BackgroundColor or Theme.Colors.ButtonPrimary
	button.AutoButtonColor = false
	button.Text = ""
	button.LayoutOrder = config.LayoutOrder or 0
	button.ClipsDescendants = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = config.CornerRadius or Theme.Corner.Medium
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = config.BorderColor or Theme.Colors.Border
	stroke.Thickness = Theme.Stroke.WidthDefault
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	-- Scale modifier for bouncy press animation
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = button

	-- Content container for centered layout
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -8, 1, -6)
	content.Position = UDim2.new(0.5, 0, 0.5, 0)
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.BackgroundTransparency = 1
	content.Parent = button

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = isVertical and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Padding = UDim.new(0, isVertical and 2 or 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = content

	-- Optional placeholder icon (stylized shape or text symbol)
	local iconLabel: TextLabel? = nil
	if config.IconText then
		iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "Icon"
		iconLabel.Size = isVertical and UDim2.new(0, 26, 0, 26) or UDim2.new(0, 22, 0, 22)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Text = config.IconText
		iconLabel.TextColor3 = config.IconColor or Theme.Colors.TextPrimary
		iconLabel.TextScaled = true
		iconLabel.Font = Theme.Fonts.Title
		iconLabel.LayoutOrder = 1
		iconLabel.Parent = content
	end

	-- Text labels container (main text + optional subtext)
	local textContainer = Instance.new("Frame")
	textContainer.Name = "TextContainer"
	textContainer.Size = isVertical and UDim2.new(1, 0, 0, 16) or UDim2.new(0.8, 0, 1, 0)
	textContainer.BackgroundTransparency = 1
	textContainer.LayoutOrder = 2
	textContainer.Parent = content

	local textList = Instance.new("UIListLayout")
	textList.FillDirection = Enum.FillDirection.Vertical
	textList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	textList.VerticalAlignment = Enum.VerticalAlignment.Center
	textList.Padding = UDim.new(0, 2)
	textList.Parent = textContainer

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.Size = UDim2.new(1, 0, config.SubText and 0.6 or 1, 0)
	label.BackgroundTransparency = 1
	label.Text = config.Text or ""
	label.TextColor3 = config.TextColor or Theme.Colors.TextPrimary
	label.TextScaled = false
	label.TextSize = isVertical and 12 or 14
	label.Font = Theme.Fonts.Button
	label.Parent = textContainer

	local subLabel: TextLabel? = nil
	if config.SubText then
		subLabel = Instance.new("TextLabel")
		subLabel.Name = "SubText"
		subLabel.Size = UDim2.new(1, 0, 0.4, 0)
		subLabel.BackgroundTransparency = 1
		subLabel.Text = config.SubText
		subLabel.TextColor3 = Theme.Colors.TextSecondary
		subLabel.TextScaled = true
		subLabel.Font = Theme.Fonts.Body
		subLabel.Parent = textContainer
	end

	-- Touch & Mouse animations
	local isEnabled = true
	local baseBg = button.BackgroundColor3
	local baseBorder = stroke.Color

	local function tweenScale(target: number)
		TweenService:Create(scale, Theme.Transitions.Fast, { Scale = target }):Play()
	end

	button.MouseEnter:Connect(function()
		if not isEnabled then return end
		tweenScale(1.04)
		TweenService:Create(button, Theme.Transitions.Fast, {
			BackgroundColor3 = config.BackgroundColor and config.BackgroundColor:Lerp(Color3.new(1, 1, 1), 0.1) or Theme.Colors.BackgroundHover,
		}):Play()
	end)

	button.MouseLeave:Connect(function()
		if not isEnabled then return end
		tweenScale(1.0)
		TweenService:Create(button, Theme.Transitions.Fast, { BackgroundColor3 = baseBg }):Play()
	end)

	button.InputBegan:Connect(function(input)
		if not isEnabled then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			tweenScale(0.94)
		end
	end)

	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			tweenScale(1.0)
		end
	end)

	if config.OnClick then
		button.Activated:Connect(function()
			if not isEnabled then return end
			config.OnClick()
		end)
	end

	if config.Parent then
		button.Parent = config.Parent
	end

	local self: ButtonComponent = {
		Instance = button,
		SetText = function(_, text: string)
			label.Text = text
		end,
		SetEnabled = function(_, enabled: boolean)
			isEnabled = enabled
			button.Active = enabled
			stroke.Color = enabled and baseBorder or Theme.Colors.BorderSubtle
			label.TextColor3 = enabled and (config.TextColor or Theme.Colors.TextPrimary) or Theme.Colors.TextMuted
			button.BackgroundColor3 = enabled and baseBg or Theme.Colors.BackgroundDark
		end,
		SetBorderColor = function(_, color: Color3)
			baseBorder = color
			if isEnabled then
				stroke.Color = color
			end
		end,
		SetTextColor = function(_, color: Color3)
			if isEnabled then
				label.TextColor3 = color
			end
		end,
		Destroy = function(_)
			button:Destroy()
		end,
	}

	return self
end

return Button
