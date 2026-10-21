--!strict
-- Reusable Panel component providing consistent aura-themed container styling.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))

export type PanelConfig = {
	Name: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	BackgroundColor: Color3?,
	BackgroundTransparency: number?,
	BorderColor: Color3?,
	BorderThickness: number?,
	CornerRadius: UDim?,
	Padding: UDim?,
	ClipsDescendants: boolean?,
	LayoutOrder: number?,
	Parent: Instance?,
}

export type PanelComponent = {
	Instance: Frame,
	Content: Frame,
	SetVisible: (self: PanelComponent, visible: boolean) -> (),
	SetBorderColor: (self: PanelComponent, color: Color3) -> (),
	Destroy: (self: PanelComponent) -> (),
}

local Panel = {}

function Panel.new(config: PanelConfig): PanelComponent
	local frame = Instance.new("Frame")
	frame.Name = config.Name or "ThemedPanel"
	frame.Size = config.Size or UDim2.new(1, 0, 1, 0)
	frame.Position = config.Position or UDim2.new(0, 0, 0, 0)
	frame.AnchorPoint = config.AnchorPoint or Vector2.new(0, 0)
	frame.BackgroundColor3 = config.BackgroundColor or Theme.Colors.PanelBackground
	frame.BackgroundTransparency = config.BackgroundTransparency or 0.1
	frame.ClipsDescendants = if config.ClipsDescendants ~= nil then config.ClipsDescendants else false
	frame.LayoutOrder = config.LayoutOrder or 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = config.CornerRadius or Theme.Corner.Large
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = config.BorderColor or Theme.Colors.Border
	stroke.Thickness = config.BorderThickness or Theme.Stroke.WidthDefault
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	-- Content frame inside the panel
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, 0, 1, 0)
	content.BackgroundTransparency = 1
	content.Parent = frame

	local padding = Instance.new("UIPadding")
	local padDim = config.Padding or UDim.new(0, 8)
	padding.PaddingTop = padDim
	padding.PaddingBottom = padDim
	padding.PaddingLeft = padDim
	padding.PaddingRight = padDim
	padding.Parent = content

	if config.Parent then
		frame.Parent = config.Parent
	end

	local self: PanelComponent = {
		Instance = frame,
		Content = content,
		SetVisible = function(_, visible: boolean)
			frame.Visible = visible
		end,
		SetBorderColor = function(_, color: Color3)
			stroke.Color = color
		end,
		Destroy = function(_)
			frame:Destroy()
		end,
	}

	return self
end

return Panel
