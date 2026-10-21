--!strict
-- Reusable modal Popup component with animated scrim, pop-in tween, and mobile-safe constraints.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Button = require(script.Parent:WaitForChild("Button"))

export type PopupConfig = {
	Title: string,
	Size: UDim2?,
	MaxWidth: number?,
	MaxHeight: number?,
	Parent: Instance?,
	OnClose: (() -> ())?,
}

export type PopupComponent = {
	Instance: Frame,
	Content: Frame,
	Open: (self: PopupComponent) -> (),
	Close: (self: PopupComponent) -> (),
	SetTitle: (self: PopupComponent, title: string) -> (),
	Destroy: (self: PopupComponent) -> (),
}

local Popup = {}

function Popup.new(config: PopupConfig): PopupComponent
	-- Fullscreen dark scrim
	local scrim = Instance.new("Frame")
	scrim.Name = "PopupScrim_" .. config.Title
	scrim.Size = UDim2.new(1, 0, 1, 0)
	scrim.Position = UDim2.new(0, 0, 0, 0)
	scrim.BackgroundColor3 = Theme.Colors.PanelOverlay
	scrim.BackgroundTransparency = 1
	scrim.Visible = false
	scrim.Active = false -- only active when open to prevent blocking taps when hidden
	scrim.ZIndex = 10

	-- Centered Dialog Box
	local dialog = Instance.new("Frame")
	dialog.Name = "Dialog"
	dialog.Size = config.Size or UDim2.new(0.88, 0, 0.72, 0)
	dialog.Position = UDim2.new(0.5, 0, 0.5, 0)
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	dialog.BackgroundColor3 = Theme.Colors.PanelBackground
	dialog.BackgroundTransparency = 0.05
	dialog.Parent = scrim

	-- Mobile-first size constraints (fits phones, caps on desktop)
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(280, 220)
	sizeConstraint.MaxSize = Vector2.new(config.MaxWidth or 520, config.MaxHeight or 440)
	sizeConstraint.Parent = dialog

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.Corner.Large
	corner.Parent = dialog

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.AuraCyan
	stroke.Thickness = Theme.Stroke.WidthThick
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = dialog

	local dialogScale = Instance.new("UIScale")
	dialogScale.Scale = 0.8
	dialogScale.Parent = dialog

	-- Header container
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 48)
	header.BackgroundTransparency = 1
	header.Parent = dialog

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, -60, 1, 0)
	titleLabel.Position = UDim2.new(0, 16, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = config.Title:upper()
	titleLabel.TextColor3 = Theme.Colors.TextPrimary
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextScaled = false
	titleLabel.TextSize = 20
	titleLabel.Font = Theme.Fonts.Title
	titleLabel.Parent = header

	-- Decorative aura accent bar under title
	local auraBar = Instance.new("Frame")
	auraBar.Name = "AuraBar"
	auraBar.Size = UDim2.new(1, -32, 0, 2)
	auraBar.Position = UDim2.new(0, 16, 1, -2)
	auraBar.BackgroundColor3 = Theme.Colors.AuraCyan
	auraBar.BorderSizePixel = 0
	auraBar.Parent = header

	-- Content frame for inner components/scrolling
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -24, 1, -62)
	content.Position = UDim2.new(0.5, 0, 0, 54)
	content.AnchorPoint = Vector2.new(0.5, 0)
	content.BackgroundTransparency = 1
	content.Parent = dialog

	local contentPadding = Instance.new("UIPadding")
	contentPadding.PaddingTop = UDim.new(0, 6)
	contentPadding.PaddingBottom = UDim.new(0, 6)
	contentPadding.PaddingLeft = UDim.new(0, 6)
	contentPadding.PaddingRight = UDim.new(0, 6)
	contentPadding.Parent = content

	if config.Parent then
		scrim.Parent = config.Parent
	end

	local isOpen = false

	local function openDialog()
		isOpen = true
		scrim.Active = true
		scrim.Visible = true
		dialogScale.Scale = 0.8
		TweenService:Create(scrim, Theme.Transitions.Smooth, { BackgroundTransparency = 0.35 }):Play()
		TweenService:Create(dialogScale, Theme.Transitions.Pop, { Scale = 1.0 }):Play()
	end

	local function closeDialog()
		if not isOpen then return end
		isOpen = false
		scrim.Active = false
		local tween = TweenService:Create(dialogScale, Theme.Transitions.Fast, { Scale = 0.85 })
		TweenService:Create(scrim, Theme.Transitions.Fast, { BackgroundTransparency = 1 }):Play()
		tween:Play()
		tween.Completed:Connect(function()
			if not isOpen then
				scrim.Visible = false
				if config.OnClose then
					config.OnClose()
				end
			end
		end)
	end

	-- Close button ("✕")
	local closeBtn = Button.new({
		Name = "CloseButton",
		Size = UDim2.new(0, 32, 0, 32),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Text = "X",
		TextColor = Theme.Colors.TextPrimary,
		BackgroundColor = Theme.Colors.ButtonClose,
		BorderColor = Theme.Colors.Border,
		CornerRadius = Theme.Corner.Round,
		Parent = header,
		OnClick = closeDialog,
	})

	local self: PopupComponent = {
		Instance = scrim,
		Content = content,
		Open = function(_)
			openDialog()
		end,
		Close = function(_)
			closeDialog()
		end,
		SetTitle = function(_, title: string)
			titleLabel.Text = title:upper()
		end,
		Destroy = function(_)
			closeBtn:Destroy()
			scrim:Destroy()
		end,
	}

	return self
end

return Popup
