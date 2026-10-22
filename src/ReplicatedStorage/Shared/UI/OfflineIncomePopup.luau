--!strict
-- OfflineIncomePopup: Displays welcome back modal with offline Gold earned and away duration.
-- Opened automatically once on join when ClaimOfflineIncome returns earned Gold.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local Components = Shared:WaitForChild("UI"):WaitForChild("Components")
local Popup = require(Components:WaitForChild("Popup"))
local Button = require(Components:WaitForChild("Button"))

export type OfflineIncomePopupInstance = {
	Show: (self: OfflineIncomePopupInstance, gold: number, durationSeconds: number) -> (),
	Close: (self: OfflineIncomePopupInstance) -> (),
	Destroy: (self: OfflineIncomePopupInstance) -> (),
}

local OfflineIncomePopup = {}

local function formatDuration(seconds: number): string
	if seconds < 60 then
		return ("%d seconds"):format(math.max(1, math.floor(seconds)))
	elseif seconds < 3600 then
		local mins = math.floor(seconds / 60)
		return ("%d minute%s"):format(mins, if mins == 1 then "" else "s")
	else
		local hours = math.floor(seconds / 3600)
		local mins = math.floor((seconds % 3600) / 60)
		if mins == 0 then
			return ("%d hour%s"):format(hours, if hours == 1 then "" else "s")
		end
		return ("%dh %dm"):format(hours, mins)
	end
end

function OfflineIncomePopup.new(parentGui: Instance): OfflineIncomePopupInstance
	local screenGui: Instance
	if parentGui:IsA("ScreenGui") then
		screenGui = parentGui
	else
		local sg = Instance.new("ScreenGui")
		sg.Name = "AuraBladeOfflineIncomeGui"
		sg.ResetOnSpawn = false
		sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		sg.DisplayOrder = 25
		sg.Parent = parentGui
		screenGui = sg
	end

	local popup = Popup.new({
		Title = "WELCOME BACK!",
		Size = UDim2.new(0.85, 0, 0.45, 0),
		MaxWidth = 440,
		MaxHeight = 280,
		Parent = screenGui,
	})

	local content = popup.Content

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = container

	-- Subtitle banner
	local subHeader = Instance.new("TextLabel")
	subHeader.Name = "SubHeader"
	subHeader.Size = UDim2.new(1, -20, 0, 22)
	subHeader.BackgroundTransparency = 1
	subHeader.Font = Theme.Fonts.Title
	subHeader.TextSize = 14
	subHeader.TextColor3 = Theme.Colors.AuraCyan
	subHeader.Text = "SWORD PEDESTALS AT WORK"
	subHeader.Parent = container

	-- Earned Gold display
	local goldLabel = Instance.new("TextLabel")
	goldLabel.Name = "GoldEarned"
	goldLabel.Size = UDim2.new(1, -20, 0, 44)
	goldLabel.BackgroundTransparency = 1
	goldLabel.Font = Theme.Fonts.Title
	goldLabel.TextSize = 28
	goldLabel.TextColor3 = Theme.Colors.TextGold
	goldLabel.Text = "+0 Gold"
	goldLabel.Parent = container

	local goldStroke = Instance.new("UIStroke")
	goldStroke.Color = Theme.Colors.AuraGold
	goldStroke.Thickness = 1.2
	goldStroke.Transparency = 0.5
	goldStroke.Parent = goldLabel

	-- Duration text
	local durationLabel = Instance.new("TextLabel")
	durationLabel.Name = "DurationLabel"
	durationLabel.Size = UDim2.new(1, -20, 0, 24)
	durationLabel.BackgroundTransparency = 1
	durationLabel.Font = Theme.Fonts.Body
	durationLabel.TextSize = 13
	durationLabel.TextColor3 = Theme.Colors.TextSecondary
	durationLabel.Text = "While you were away"
	durationLabel.Parent = container

	-- Big action button ("AWESOME!")
	local awesomeBtn = Button.new({
		Name = "AwesomeButton",
		Text = "AWESOME!",
		Size = UDim2.new(0.7, 0, 0, 44),
		BackgroundColor = Theme.Colors.ButtonPrimary,
		BorderColor = Theme.Colors.AuraCyan,
		TextColor = Theme.Colors.TextPrimary,
		CornerRadius = Theme.Corner.Medium,
		Parent = container,
		OnClick = function()
			popup:Close()
		end,
	})

	local self: OfflineIncomePopupInstance = {
		Show = function(_, gold: number, durationSeconds: number)
			goldLabel.Text = ("+%s Gold"):format(NumberFormat.format(gold))
			durationLabel.Text = ("Earned while away for %s"):format(formatDuration(durationSeconds))
			popup:Open()
		end,
		Close = function(_)
			popup:Close()
		end,
		Destroy = function(_)
			awesomeBtn:Destroy()
			popup:Destroy()
		end,
	}

	return self
end

return OfflineIncomePopup
