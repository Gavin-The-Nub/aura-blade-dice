--!strict
-- StationService: Manages server-side station generation in the Plaza.
-- Generates placeholder station models tagged "Station" with StationType attributes
-- only if none exist, clear of the spawn location and player plots.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StationsConfig = require(ReplicatedStorage.Config.Stations)
local Theme = require(ReplicatedStorage.Shared.Theme)

local STATION_TAG = "Station"
local TELEPORT_DESTINATION_TAG = "TeleportDestination"
local STATIONS_FOLDER_NAME = "Stations"

local StationService = {}

local function resolveColor(tokenName: string): Color3
	local colorsTable = Theme.Colors :: any
	if typeof(colorsTable[tokenName]) == "Color3" then
		return colorsTable[tokenName]
	end
	return Theme.Colors.AuraCyan
end

-- Generates or updates teleport destination pads (Hub & Shop)
local function generateTeleportDestinations(folder: Folder)
	for destName, pos in StationsConfig.TeleportDestinations do
		local markerName = "TeleportDestination_" .. destName
		local existing: Instance? = folder:FindFirstChild(markerName)
		if not existing then
			for _, taggedInst in CollectionService:GetTagged(TELEPORT_DESTINATION_TAG) do
				if taggedInst:GetAttribute("Destination") == destName then
					existing = taggedInst
					break
				end
			end
		end

		if existing and existing:IsA("BasePart") then
			existing.Position = pos
			continue
		end

		local pad = Instance.new("Part")
		pad.Name = markerName
		pad.Size = Vector3.new(6, 0.4, 6)
		pad.Position = pos
		pad.Anchored = true
		pad.CanCollide = false
		pad.Material = Enum.Material.Neon
		pad.Color = if destName == "Hub" then Theme.Colors.AuraCyan else Theme.Colors.AuraGold
		pad.TopSurface = Enum.SurfaceType.Smooth
		pad.BottomSurface = Enum.SurfaceType.Smooth
		pad:SetAttribute("Destination", destName)
		CollectionService:AddTag(pad, TELEPORT_DESTINATION_TAG)
		pad.Parent = folder
	end
end

-- Generates placeholder models for plaza stations and trial entrances,
-- moving existing tagged instances when config coordinates change (never duplicating).
local function generatePlazaStations()
	local existingFolder = workspace:FindFirstChild(STATIONS_FOLDER_NAME)
	local folder: Folder
	if existingFolder and existingFolder:IsA("Folder") then
		folder = existingFolder
	else
		folder = Instance.new("Folder")
		folder.Name = STATIONS_FOLDER_NAME
		folder.Parent = workspace
	end

	generateTeleportDestinations(folder)

	for _, def in StationsConfig.AllStations do
		if not def.HasModel then
			continue
		end

		local modelName = "Station_" .. def.Type
		local existing: Instance? = folder:FindFirstChild(modelName)
		if not existing then
			for _, taggedModel in CollectionService:GetTagged(STATION_TAG) do
				if taggedModel:GetAttribute("StationType") == def.Type then
					existing = taggedModel
					break
				end
			end
		end

		-- If already exists, update position from config so moving stations never duplicates them
		if existing and existing:IsA("Model") then
			local basePart = existing:FindFirstChild("Base") :: BasePart?
				or existing.PrimaryPart
				or (existing:FindFirstChildWhichIsA("BasePart") :: BasePart?)
			local accentPad = existing:FindFirstChild("AccentPad") :: BasePart?
			local prompt = if basePart then basePart:FindFirstChildOfClass("ProximityPrompt") else existing:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = if def.PromptEnabled ~= nil then def.PromptEnabled else true
			end
			if basePart then
				basePart.Size = def.Size
				basePart.Position = def.Position
				if existing.PrimaryPart == basePart then
					existing:PivotTo(CFrame.new(def.Position))
				end
			end
			if accentPad then
				accentPad.Size = Vector3.new(def.Size.X * 0.75, 0.4, def.Size.Z * 0.75)
				accentPad.Position = def.Position + Vector3.new(0, (def.Size.Y / 2) + 0.1, 0)
			end
			continue
		end

		local model = Instance.new("Model")
		model.Name = modelName
		model:SetAttribute("StationType", def.Type)

		-- Main base platform
		local basePart = Instance.new("Part")
		basePart.Name = "Base"
		basePart.Size = def.Size
		basePart.Position = def.Position
		basePart.Anchored = true
		basePart.CanCollide = true
		basePart.Material = Enum.Material.SmoothPlastic
		basePart.Color = Theme.Colors.PanelBackground
		basePart.TopSurface = Enum.SurfaceType.Smooth
		basePart.BottomSurface = Enum.SurfaceType.Smooth
		basePart.Parent = model
		model.PrimaryPart = basePart

		-- Glowing accent ring / pad on top
		local accentColor = resolveColor(def.ColorToken)
		local accentPad = Instance.new("Part")
		accentPad.Name = "AccentPad"
		accentPad.Size = Vector3.new(def.Size.X * 0.75, 0.4, def.Size.Z * 0.75)
		accentPad.Position = def.Position + Vector3.new(0, (def.Size.Y / 2) + 0.1, 0)
		accentPad.Anchored = true
		accentPad.CanCollide = false
		accentPad.Material = Enum.Material.Neon
		accentPad.Color = accentColor
		accentPad.TopSurface = Enum.SurfaceType.Smooth
		accentPad.BottomSurface = Enum.SurfaceType.Smooth
		accentPad.Parent = model

		-- Overhead billboard sign
		local signGui = Instance.new("BillboardGui")
		signGui.Name = "StationSign"
		signGui.Size = UDim2.new(0, 180, 0, 50)
		signGui.StudsOffset = StationsConfig.SignDefaults.StudsOffset
		signGui.MaxDistance = StationsConfig.SignDefaults.MaxDistance
		signGui.AlwaysOnTop = false
		signGui.Parent = basePart

		local signFrame = Instance.new("Frame")
		signFrame.Name = "SignFrame"
		signFrame.Size = UDim2.new(1, 0, 1, 0)
		signFrame.BackgroundColor3 = Theme.Colors.PanelBackground
		signFrame.BackgroundTransparency = 0.25
		signFrame.Parent = signGui

		local signCorner = Instance.new("UICorner")
		signCorner.CornerRadius = Theme.Corner.Medium
		signCorner.Parent = signFrame

		local signStroke = Instance.new("UIStroke")
		signStroke.Color = accentColor
		signStroke.Thickness = Theme.Stroke.WidthDefault
		signStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		signStroke.Parent = signFrame

		local signLabel = Instance.new("TextLabel")
		signLabel.Name = "SignLabel"
		signLabel.Size = UDim2.new(1, -8, 1, 0)
		signLabel.Position = UDim2.new(0, 4, 0, 0)
		signLabel.BackgroundTransparency = 1
		signLabel.Text = def.ObjectText:upper()
		signLabel.TextColor3 = Theme.Colors.TextPrimary
		signLabel.Font = Theme.Fonts.Title
		signLabel.TextSize = 16
		signLabel.TextScaled = false
		signLabel.Parent = signFrame

		-- Server-created ProximityPrompt (replicates to clients)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StationPrompt"
		prompt.ActionText = def.ActionText
		prompt.ObjectText = def.ObjectText
		prompt.HoldDuration = StationsConfig.PromptDefaults.HoldDuration
		prompt.RequiresLineOfSight = StationsConfig.PromptDefaults.RequiresLineOfSight
		prompt.MaxActivationDistance = StationsConfig.PromptDefaults.MaxActivationDistance
		prompt.Enabled = if def.PromptEnabled ~= nil then def.PromptEnabled else true
		prompt.Parent = basePart

		-- Tag the model as a Station for CollectionService discovery
		CollectionService:AddTag(model, STATION_TAG)
		model.Parent = folder
	end

	print(("[StationService] Configured stations and teleport destinations in Workspace.%s."):format(STATIONS_FOLDER_NAME))
end

function StationService.Start()
	generatePlazaStations()
end

return StationService
