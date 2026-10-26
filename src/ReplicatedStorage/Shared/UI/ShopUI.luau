--!strict
-- ShopUI: "Coming soon" modal dialog for the Plaza Shop station.
-- Implemented inside its own ScreenGui using the shared Popup component.
-- Contains no purchase buttons and no prices.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))

local Components = Shared:WaitForChild("UI"):WaitForChild("Components")
local Popup = require(Components:WaitForChild("Popup"))

export type ShopUIInstance = {
	Open: (self: ShopUIInstance) -> (),
	Close: (self: ShopUIInstance) -> (),
	Toggle: (self: ShopUIInstance) -> (),
	Destroy: (self: ShopUIInstance) -> (),
}

local ShopUI = {}

function ShopUI.new(parentGui: Instance): ShopUIInstance
	local screenGui: ScreenGui
	if parentGui:IsA("ScreenGui") then
		screenGui = parentGui
	else
		local existing = parentGui:FindFirstChild("AuraBladeShopGui")
		if existing and existing:IsA("ScreenGui") then
			existing:Destroy()
		end
		local sg = Instance.new("ScreenGui")
		sg.Name = "AuraBladeShopGui"
		sg.ResetOnSpawn = false
		sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		sg.DisplayOrder = 10
		sg.Parent = parentGui
		screenGui = sg
	end

	local isOpened = false

	-- Shared Popup component
	local popup = Popup.new({
		Title = "Shop",
		Size = UDim2.new(0.85, 0, 0.45, 0),
		MaxWidth = 460,
		MaxHeight = 280,
		Parent = screenGui,
		OnClose = function()
			isOpened = false
		end,
	})

	-- Container card inside popup.Content
	local container = Instance.new("Frame")
	container.Name = "InfoCard"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundColor3 = Theme.Colors.BackgroundCard
	container.BackgroundTransparency = 0.2
	container.Parent = popup.Content

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = Theme.Corner.Medium
	containerCorner.Parent = container

	local containerStroke = Instance.new("UIStroke")
	containerStroke.Color = Theme.Colors.BorderSubtle
	containerStroke.Thickness = Theme.Stroke.WidthDefault
	containerStroke.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = container

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.PaddingLeft = UDim.new(0, 20)
	padding.PaddingRight = UDim.new(0, 20)
	padding.Parent = container

	-- "COMING SOON" Badge
	local badge = Instance.new("Frame")
	badge.Name = "ComingSoonBadge"
	badge.Size = UDim2.new(0, 160, 0, 32)
	badge.BackgroundColor3 = Theme.Colors.ButtonPrimary
	badge.Parent = container

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = Theme.Corner.Round
	badgeCorner.Parent = badge

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = Theme.Colors.AuraCyan
	badgeStroke.Thickness = Theme.Stroke.WidthDefault
	badgeStroke.Parent = badge

	local badgeLabel = Instance.new("TextLabel")
	badgeLabel.Name = "BadgeLabel"
	badgeLabel.Size = UDim2.new(1, 0, 1, 0)
	badgeLabel.BackgroundTransparency = 1
	badgeLabel.Text = "COMING SOON"
	badgeLabel.TextColor3 = Theme.Colors.AuraCyan
	badgeLabel.Font = Theme.Fonts.Title
	badgeLabel.TextSize = 14
	badgeLabel.Parent = badge

	-- Descriptive informational message (no prices, no buy buttons)
	local messageLabel = Instance.new("TextLabel")
	messageLabel.Name = "MessageLabel"
	messageLabel.Size = UDim2.new(1, 0, 0, 80)
	messageLabel.BackgroundTransparency = 1
	messageLabel.Text = "The Aura Blade Shop is currently under construction.\n\nPremium gamepasses, boosts, and developer products will be available here in a future update."
	messageLabel.TextColor3 = Theme.Colors.TextSecondary
	messageLabel.Font = Theme.Fonts.Body
	messageLabel.TextSize = 14
	messageLabel.TextWrapped = true
	messageLabel.TextYAlignment = Enum.TextYAlignment.Center
	messageLabel.Parent = container

	local self: ShopUIInstance = {
		Open = function(_)
			isOpened = true
			popup:Open()
		end,
		Close = function(_)
			isOpened = false
			popup:Close()
		end,
		Toggle = function(this)
			if isOpened then
				this:Close()
			else
				this:Open()
			end
		end,
		Destroy = function(_)
			isOpened = false
			popup:Destroy()
			if screenGui and screenGui.Parent then
				screenGui:Destroy()
			end
		end,
	}

	return self
end

return ShopUI
