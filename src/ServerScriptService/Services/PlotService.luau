--!strict
-- PlotService: Manages server-authoritative plot allocation, plot lifecycle,
-- CollectionService "Plot" tag scanning / default plot generation, owner signs,
-- pedestal sword placement (Move not copy), passive Gold generation ticker (1 Hz),
-- and capped offline income calculations on join.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Config.Game)
local Swords = require(ReplicatedStorage.Config.Swords)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Theme = require(ReplicatedStorage.Shared.Theme)
local DataService = require(ServerScriptService.Services.DataService)
local TapService = require(ServerScriptService.Services.TapService)
local PlayerActionLock = require(ServerScriptService.PlayerActionLock)

local PLOT_TAG = "Plot"
local PEDESTAL_TAG = "Pedestal"
local TARGET_DUMMY_TAG = "TargetDummy"
local DEFAULT_PLOTS_FOLDER_NAME = "Plots"

local swordDefMap: { [string]: Swords.SwordDef } = {}
for _, def in Swords do
	swordDefMap[def.id] = def
end

local PlotService = {}

-- Plot state tracking
local registeredPlots: { [number]: Instance } = {} -- plotId -> Plot Instance (Model or Part)
local playerToPlot: { [Player]: number } = {} -- Player -> plotId
local plotToPlayer: { [number]: Player } = {} -- plotId -> Player
local ownerLabels: { [number]: TextLabel } = {} -- plotId -> TextLabel on billboard sign

-- Rate limiting and player state tracking
type RateBucket = {
	lastTime: number,
	tokens: number,
}
local playerBuckets: { [Player]: RateBucket } = {}
local playerInitialized: { [Player]: boolean } = {}
local plotAssignmentFinished: { [Player]: boolean } = {}
local RATE_LIMIT_CAPACITY = 6
local RATE_LIMIT_REFILL_PER_SEC = 3

-- Pending offline income (consumed once client invokes GetPlotData)
local pendingOfflineIncome: { [Player]: { gold: number, seconds: number } } = {}

local function checkRateLimit(player: Player): boolean
	local now = os.clock()
	local bucket = playerBuckets[player]
	if not bucket then
		bucket = {
			lastTime = now,
			tokens = RATE_LIMIT_CAPACITY - 1,
		}
		playerBuckets[player] = bucket
		return true
	end

	local elapsed = now - bucket.lastTime
	bucket.tokens = math.min(RATE_LIMIT_CAPACITY, bucket.tokens + (elapsed * RATE_LIMIT_REFILL_PER_SEC))
	bucket.lastTime = now

	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end

	return false
end

-- Helper to find or create the TextLabel for the plot's owner sign
local function ensureOwnerLabel(plotInstance: Instance, plotId: number): TextLabel?
	local existingLabel = plotInstance:FindFirstChild("OwnerLabel", true)
	if existingLabel and existingLabel:IsA("TextLabel") then
		return existingLabel
	end

	local targetPart: BasePart? = nil
	if plotInstance:IsA("Model") then
		targetPart = plotInstance:FindFirstChild("SignPost") :: BasePart?
			or plotInstance.PrimaryPart
			or (plotInstance:FindFirstChildWhichIsA("BasePart") :: BasePart?)
	elseif plotInstance:IsA("BasePart") then
		targetPart = plotInstance
	end

	if not targetPart then
		return nil
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PlotOwnerBillboard"
	billboard.Size = UDim2.new(0, 220, 0, 60)
	billboard.StudsOffset = Vector3.new(0, 4.5, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 120
	billboard.Parent = targetPart

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundColor3 = Theme.Colors.PanelBackground
	container.BackgroundTransparency = 0.2
	container.BorderSizePixel = 0
	container.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.Corner.Medium
	corner.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Border
	stroke.Thickness = Theme.Stroke.WidthDefault
	stroke.Parent = container

	local label = Instance.new("TextLabel")
	label.Name = "OwnerLabel"
	label.Size = UDim2.new(1, -16, 1, -12)
	label.Position = UDim2.new(0, 8, 0, 6)
	label.BackgroundTransparency = 1
	label.Font = Theme.Fonts.Title
	label.TextScaled = true
	label.TextColor3 = Theme.Colors.TextSecondary
	label.Text = ("Plot %d\n[Available]"):format(plotId)
	label.Parent = container

	return label
end

-- Updates the visual owner sign on a plot
local function updateOwnerSign(plotId: number, player: Player?)
	local label = ownerLabels[plotId]
	if not label then
		local inst = registeredPlots[plotId]
		if inst then
			label = ensureOwnerLabel(inst, plotId)
			if label then
				ownerLabels[plotId] = label
			end
		end
	end

	if not label then
		return
	end

	if player then
		label.TextColor3 = Theme.Colors.AuraCyan
		label.Text = ("%s's Plot\n(Plot #%d)"):format(player.DisplayName, plotId)
	else
		label.TextColor3 = Theme.Colors.TextMuted
		label.Text = ("Plot #%d\n[Available]"):format(plotId)
	end
end

-- Helper to create a placeholder target dummy at the front of a plot relative to its CFrame
local function createPlaceholderDummy(plotInstance: Instance, plotId: number): Model?
	local floor: BasePart? = nil
	if plotInstance:IsA("Model") then
		if plotInstance.PrimaryPart and (plotInstance.PrimaryPart.Name == "PlotFloor" or plotInstance.PrimaryPart.Name == "Floor" or plotInstance.PrimaryPart.Name == "Platform") then
			floor = plotInstance.PrimaryPart
		else
			local namedFloor = plotInstance:FindFirstChild("PlotFloor") or plotInstance:FindFirstChild("Floor")
			if namedFloor and namedFloor:IsA("BasePart") then
				floor = namedFloor
			elseif plotInstance.PrimaryPart then
				floor = plotInstance.PrimaryPart
			end
		end
	elseif plotInstance:IsA("BasePart") and (plotInstance.Name == "PlotFloor" or plotInstance.Name == "Floor") then
		floor = plotInstance
	end

	if not floor then
		warn(("[PlotService] Cannot create TargetDummy: no valid floor part (PrimaryPart or 'PlotFloor') found for Plot %d; skipping dummy generation."):format(plotId))
		return nil
	end

	local plotCFrame = floor.CFrame
	-- Position relative to the plot's CFrame: front of plot (local +Z offset), facing back toward center (math.pi)
	-- Floor is 30x30; front is at local Z = 11, clear of pedestals (at Z = -5 and 5, X = ±8)
	local dummyCFrame = plotCFrame * CFrame.new(0, 2.25, 11) * CFrame.Angles(0, math.pi, 0)

	local dummy = Instance.new("Model")
	dummy.Name = "TargetDummy"
	dummy:SetAttribute("PlotId", plotId)

	-- Base post/stand
	local post = Instance.new("Part")
	post.Name = "Post"
	post.Size = Vector3.new(0.8, 2.5, 0.8)
	post.CFrame = dummyCFrame * CFrame.new(0, -0.75, 0)
	post.Anchored = true
	post.CanCollide = true
	post.Material = Enum.Material.Wood
	post.Color = Color3.fromRGB(120, 80, 45)
	post.TopSurface = Enum.SurfaceType.Smooth
	post.BottomSurface = Enum.SurfaceType.Smooth
	post.Parent = dummy

	-- Straw/burlap torso (PrimaryPart)
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2.2, 2.6, 1.4)
	torso.CFrame = dummyCFrame * CFrame.new(0, 1.0, 0)
	torso.Anchored = true
	torso.CanCollide = true
	torso.Material = Enum.Material.Fabric
	torso.Color = Color3.fromRGB(205, 175, 130)
	torso.TopSurface = Enum.SurfaceType.Smooth
	torso.BottomSurface = Enum.SurfaceType.Smooth
	torso.Parent = dummy
	dummy.PrimaryPart = torso

	-- Head
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.CFrame = dummyCFrame * CFrame.new(0, 2.7, 0)
	head.Anchored = true
	head.CanCollide = true
	head.Material = Enum.Material.Fabric
	head.Color = Color3.fromRGB(215, 185, 140)
	head.TopSurface = Enum.SurfaceType.Smooth
	head.BottomSurface = Enum.SurfaceType.Smooth
	head.Parent = dummy

	-- Wooden cross arms
	local crossArms = Instance.new("Part")
	crossArms.Name = "CrossArms"
	crossArms.Size = Vector3.new(3.6, 0.6, 0.6)
	crossArms.CFrame = dummyCFrame * CFrame.new(0, 1.3, 0)
	crossArms.Anchored = true
	crossArms.CanCollide = false
	crossArms.Material = Enum.Material.Wood
	crossArms.Color = Color3.fromRGB(120, 80, 45)
	crossArms.TopSurface = Enum.SurfaceType.Smooth
	crossArms.BottomSurface = Enum.SurfaceType.Smooth
	crossArms.Parent = dummy

	CollectionService:AddTag(dummy, TARGET_DUMMY_TAG)

	if plotInstance:IsA("Model") then
		dummy.Parent = plotInstance
	else
		dummy.Parent = plotInstance.Parent or workspace
	end

	return dummy
end

-- Generates default plot platforms in Workspace ONLY if no Plot-tagged objects exist
local function generateDefaultPlots()
	local folder = Instance.new("Folder")
	folder.Name = DEFAULT_PLOTS_FOLDER_NAME
	folder.Parent = workspace

	local maxPlots = GameConfig.Plot.MaxPlots or 8
	local radius = 80 -- radius from center where plots are arranged

	for i = 1, maxPlots do
		local angle = ((i - 1) / maxPlots) * math.pi * 2
		local posX = math.cos(angle) * radius
		local posZ = math.sin(angle) * radius

		local model = Instance.new("Model")
		model.Name = ("Plot_%d"):format(i)
		model:SetAttribute("PlotId", i)
		model.Parent = folder

		-- Base floor platform (30 x 1.5 x 30 studs)
		local floor = Instance.new("Part")
		floor.Name = "PlotFloor"
		floor.Size = Vector3.new(30, 1.5, 30)
		floor.Position = Vector3.new(posX, 0.75, posZ)
		floor.Anchored = true
		floor.Material = Enum.Material.Slate
		floor.Color = Theme.Colors.BackgroundDark
		floor.TopSurface = Enum.SurfaceType.Smooth
		floor.BottomSurface = Enum.SurfaceType.Smooth
		floor.Parent = model
		model.PrimaryPart = floor

		-- Center sign post for owner billboard
		local signPost = Instance.new("Part")
		signPost.Name = "SignPost"
		signPost.Size = Vector3.new(1.5, 5, 1.5)
		signPost.Position = Vector3.new(posX, 3.5, posZ - 12)
		signPost.Anchored = true
		signPost.Material = Enum.Material.SmoothPlastic
		signPost.Color = Theme.Colors.PanelBackground
		signPost.CanCollide = false
		signPost.Parent = model

		-- 4 Pedestal base parts (tagged "Pedestal")
		local defaultPedestals = GameConfig.Plot.DefaultPedestalsPerPlot or 4
		local pedestalOffsets = {
			Vector3.new(-8, 1.25, -5),
			Vector3.new(8, 1.25, -5),
			Vector3.new(-8, 1.25, 5),
			Vector3.new(8, 1.25, 5),
		}

		for slot = 1, defaultPedestals do
			local offset = pedestalOffsets[slot] or Vector3.new(0, 1.25, 0)
			local pedPart = Instance.new("Part")
			pedPart.Name = ("Pedestal_%d"):format(slot)
			pedPart.Size = Vector3.new(4, 1.5, 4)
			pedPart.Position = floor.Position + offset
			pedPart.Anchored = true
			pedPart.Material = Enum.Material.Neon
			pedPart.Color = Theme.Colors.BorderSubtle
			pedPart.TopSurface = Enum.SurfaceType.Smooth
			pedPart.BottomSurface = Enum.SurfaceType.Smooth
			pedPart:SetAttribute("Slot", slot)
			pedPart:SetAttribute("SlotIndex", slot)
			pedPart:SetAttribute("PlotId", i)
			CollectionService:AddTag(pedPart, PEDESTAL_TAG)
			pedPart.Parent = model
		end

		-- Target dummy placeholder at front of plot
		createPlaceholderDummy(model, i)

		CollectionService:AddTag(model, PLOT_TAG)
	end

	print(("[PlotService] Generated %d default plots in Workspace."):format(maxPlots))
end

-- Discovers all Plot-tagged instances in Workspace
local function discoverPlots()
	local tagged = CollectionService:GetTagged(PLOT_TAG)

	if #tagged == 0 then
		generateDefaultPlots()
		tagged = CollectionService:GetTagged(PLOT_TAG)
	else
		print(("[PlotService] Found %d existing Plot-tagged instances in Workspace."):format(#tagged))
	end

	for _, inst in tagged do
		local plotId = inst:GetAttribute("PlotId")
		if type(plotId) ~= "number" then
			local num = tonumber(inst.Name:match("%d+$"))
			plotId = num or (#registeredPlots + 1)
			inst:SetAttribute("PlotId", plotId)
		end

		for _, ped in inst:GetDescendants() do
			if CollectionService:HasTag(ped, PEDESTAL_TAG) then
				ped:SetAttribute("PlotId", plotId)
				local slot = ped:GetAttribute("SlotIndex") or ped:GetAttribute("Slot")
				if type(slot) ~= "number" then
					local num = tonumber(ped.Name:match("%d+$"))
					slot = num or 1
				end
				ped:SetAttribute("SlotIndex", slot)
			end
		end

		-- Find or create TargetDummy for this plot
		local dummy: Instance? = nil
		for _, desc in inst:GetDescendants() do
			if CollectionService:HasTag(desc, TARGET_DUMMY_TAG) or desc.Name == "TargetDummy" then
				dummy = desc
				break
			end
		end

		if dummy then
			dummy:SetAttribute("PlotId", plotId)
			if not CollectionService:HasTag(dummy, TARGET_DUMMY_TAG) then
				CollectionService:AddTag(dummy, TARGET_DUMMY_TAG)
			end
		else
			createPlaceholderDummy(inst, plotId)
		end

		registeredPlots[plotId] = inst
		local label = ensureOwnerLabel(inst, plotId)
		if label then
			ownerLabels[plotId] = label
		end
		updateOwnerSign(plotId, nil)
	end
end

-- Clears all sword attributes from a plot's pedestals
local function clearPlotPedestals(plotId: number)
	local plotModel = registeredPlots[plotId]
	if not plotModel then
		return
	end
	for _, ped in plotModel:GetDescendants() do
		if CollectionService:HasTag(ped, PEDESTAL_TAG) then
			ped:SetAttribute("PlacedSwordId", nil)
			ped:SetAttribute("PlacedSwordName", nil)
			ped:SetAttribute("PlacedSwordRarity", nil)
			ped:SetAttribute("PlacedSwordGoldPerSec", nil)
			ped:SetAttribute("PlacedSwordOwner", nil)
		end
	end
end

-- Syncs pedestal attributes on a player's plot from profile.Data.PlacedSwords
local function refreshPedestals(player: Player)
	local plotId = playerToPlot[player]
	if not plotId then
		return
	end

	local plotModel = registeredPlots[plotId]
	if not plotModel then
		return
	end

	local placed = DataService.Get(player, "PlacedSwords")
	local owned = DataService.Get(player, "OwnedSwords")
	local pedestalSlots = DataService.Get(player, "PedestalSlots") or GameConfig.Plot.DefaultPedestalsPerPlot
	local passiveRate = GameConfig.Plot.PassiveRateMultiplier or 0.5

	local ownedMap: { [string]: any } = {}
	if type(owned) == "table" then
		for _, entry in owned do
			if type(entry) == "table" and type(entry.uid) == "string" then
				ownedMap[entry.uid] = entry
			end
		end
	end

	local placedMap = if type(placed) == "table" then placed else {}

	for _, ped in plotModel:GetDescendants() do
		if CollectionService:HasTag(ped, PEDESTAL_TAG) then
			local slot = ped:GetAttribute("SlotIndex") or ped:GetAttribute("Slot")
			if type(slot) ~= "number" then
				slot = tonumber(ped.Name:match("%d+$")) or 1
			end
			ped:SetAttribute("SlotIndex", slot)
			ped:SetAttribute("PlotId", plotId)

			local uid = placedMap[tostring(slot)]
			local swordEntry = if uid then ownedMap[uid] else nil
			local swordDef = if swordEntry then swordDefMap[swordEntry.id] else nil

			-- Pedestals above PedestalSlots get no sword attributes
			if slot <= pedestalSlots and swordEntry and swordDef then
				local gpt = TapService.CalculateSwordGoldPerTap(player, swordEntry)
				local gps = gpt * passiveRate

				ped:SetAttribute("PlacedSwordId", swordEntry.id)
				ped:SetAttribute("PlacedSwordName", swordDef.name)
				ped:SetAttribute("PlacedSwordRarity", swordDef.rarity)
				ped:SetAttribute("PlacedSwordGoldPerSec", gps)
				ped:SetAttribute("PlacedSwordOwner", player.DisplayName)
			else
				ped:SetAttribute("PlacedSwordId", nil)
				ped:SetAttribute("PlacedSwordName", nil)
				ped:SetAttribute("PlacedSwordRarity", nil)
				ped:SetAttribute("PlacedSwordGoldPerSec", nil)
				ped:SetAttribute("PlacedSwordOwner", nil)
			end
		end
	end
end

-- Assigns a free plot to a player, or handles "no free plot" gracefully
local function assignPlot(player: Player): number?
	if player.Parent ~= Players then
		return nil
	end

	if playerToPlot[player] then
		return playerToPlot[player]
	end

	local maxPlots = GameConfig.Plot.MaxPlots or 8
	local assignedId: number? = nil

	for id = 1, maxPlots do
		if registeredPlots[id] and plotToPlayer[id] == nil then
			assignedId = id
			break
		end
	end

	if assignedId then
		playerToPlot[player] = assignedId
		plotToPlayer[assignedId] = player
		updateOwnerSign(assignedId, player)
		refreshPedestals(player)

		local plotInst = registeredPlots[assignedId]
		local plotAssignedEvent = Remotes.getEvent("PlotAssigned")
		plotAssignedEvent:FireClient(player, assignedId, plotInst)

		print(("[PlotService] Assigned Plot #%d to %s"):format(assignedId, player.Name))
		return assignedId
	else
		local plotAssignedEvent = Remotes.getEvent("PlotAssigned")
		plotAssignedEvent:FireClient(player, nil, nil)

		local devMessageEvent = Remotes.getEvent("DevMessage")
		devMessageEvent:FireClient(player, "[Notice] All plots are currently claimed. You can still tap and roll!")

		warn(("[PlotService] No free plot available for %s (%d plots registered)"):format(player.Name, #registeredPlots))
		return nil
	end
end

-- Frees a player's plot upon leaving and cleans up memory
local function releasePlot(player: Player)
	local plotId = playerToPlot[player]
	if plotId then
		clearPlotPedestals(plotId)
		playerToPlot[player] = nil
		plotToPlayer[plotId] = nil
		updateOwnerSign(plotId, nil)
		print(("[PlotService] Released Plot #%d from %s"):format(plotId, player.Name))
	end

	playerBuckets[player] = nil
	PlayerActionLock.Release(player)
	pendingOfflineIncome[player] = nil
	playerInitialized[player] = nil
	plotAssignmentFinished[player] = nil
end

-- Evaluates offline income on join, before passive ticking begins
local function processOfflineIncome(player: Player)
	local lastLogout = DataService.Get(player, "LastLogout")
	if type(lastLogout) ~= "number" or lastLogout <= 0 then
		-- No previous valid logout time recorded; stamp now and exit
		DataService.Set(player, "LastLogout", os.time())
		return
	end

	local now = os.time()
	local cap = GameConfig.Plot.OfflineIncomeCapSeconds or (8 * 3600)
	local elapsed = math.clamp(now - lastLogout, 0, cap)

	if elapsed <= 0 then
		DataService.Set(player, "LastLogout", now)
		return
	end

	-- Calculate passive gold per second across placed swords
	local placed = DataService.Get(player, "PlacedSwords")
	local owned = DataService.Get(player, "OwnedSwords")
	local pedestalSlots = DataService.Get(player, "PedestalSlots") or GameConfig.Plot.DefaultPedestalsPerPlot

	local passivePerSec = 0
	if type(placed) == "table" and type(owned) == "table" then
		local ownedMap: { [string]: any } = {}
		for _, entry in owned do
			if type(entry) == "table" and type(entry.uid) == "string" then
				ownedMap[entry.uid] = entry
			end
		end

		local passiveRate = GameConfig.Plot.PassiveRateMultiplier or 0.5
		for slotNum = 1, math.min(10, pedestalSlots) do
			local swordUid = placed[tostring(slotNum)]
			if swordUid and ownedMap[swordUid] then
				local swordEntry = ownedMap[swordUid]
				local gpt = TapService.CalculateSwordGoldPerTap(player, swordEntry)
				passivePerSec += (gpt * passiveRate)
			end
		end
	end

	local rawOfflineGold = passivePerSec * elapsed
	local earnedGold = math.floor(rawOfflineGold + 0.5)

	if earnedGold > 0 then
		DataService.Increment(player, "Gold", earnedGold)
	end

	-- IMMEDIATELY after paying, set LastLogout = os.time() so crash & rejoin can't pay twice
	DataService.Set(player, "LastLogout", now)

	-- Apply thresholds for popup display
	local minGold = GameConfig.Plot.MinOfflineIncomePopupThreshold or 1
	local minSeconds = GameConfig.Plot.MinOfflineSeconds or 60
	if earnedGold >= minGold and elapsed >= minSeconds then
		pendingOfflineIncome[player] = {
			gold = earnedGold,
			seconds = elapsed,
		}
		print(("[PlotService] Offline income awarded to %s: %d Gold (%d seconds)"):format(player.Name, earnedGold, elapsed))
	end
end

-- Places a sword on a pedestal slot (Move not copy)
function PlotService.PlaceSword(player: Player, slotIndex: unknown, swordUid: unknown): (boolean, string?)
	if not checkRateLimit(player) then
		return false, "Action rate limited. Please slow down."
	end

	if not PlayerActionLock.Acquire(player) then
		return false, "Another pedestal or inventory action is in progress."
	end

	local ok, success, errMsg = pcall(function(): (boolean, string?)
		-- Type validation
		if typeof(slotIndex) ~= "number" or slotIndex ~= math.floor(slotIndex) then
			return false, "Invalid pedestal slot index."
		end

		if typeof(swordUid) ~= "string" or swordUid == "" or #swordUid > 100 then
			return false, "Invalid sword identifier."
		end

		if not DataService.IsLoaded(player) then
			return false, "Data is loading..."
		end

		local pedestalSlots = DataService.Get(player, "PedestalSlots") or GameConfig.Plot.DefaultPedestalsPerPlot
		if slotIndex < 1 or slotIndex > pedestalSlots or slotIndex > 10 then
			return false, ("Slot %d is not unlocked (Unlocked: 1..%d)."):format(slotIndex, pedestalSlots)
		end

		-- Check ownership
		local ownedSwords = DataService.Get(player, "OwnedSwords")
		if typeof(ownedSwords) ~= "table" then
			return false, "No swords owned."
		end

		local owned = false
		for _, entry in ownedSwords do
			if typeof(entry) == "table" and entry.uid == swordUid then
				owned = true
				break
			end
		end

		if not owned then
			return false, "You do not own this sword."
		end

		-- Reject placing the equipped sword
		local equippedUid = DataService.Get(player, "EquippedSword")
		if equippedUid == swordUid then
			return false, "Cannot place your currently equipped sword on a pedestal!"
		end

		-- Move not copy: if already placed on another slot, remove it from old slot first
		local placed = DataService.Get(player, "PlacedSwords")
		local updated = if typeof(placed) == "table" then table.clone(placed) else {}

		for sKey, pUid in updated do
			if pUid == swordUid then
				updated[sKey] = nil
			end
		end

		-- Place onto target slot (replaces old sword on slot if occupied)
		updated[tostring(slotIndex)] = swordUid

		local saved = DataService.Set(player, "PlacedSwords", updated)
		if saved then
			return true, nil
		else
			return false, "Failed to save placed sword."
		end
	end)

	PlayerActionLock.Release(player)

	if not ok then
		warn(("[PlotService.PlaceSword] Error for %s: %s"):format(player.Name, tostring(success)))
		return false, "An unexpected error occurred while placing sword."
	end

	return success, errMsg
end

-- Removes a sword from a pedestal slot
function PlotService.RemoveSword(player: Player, slotIndex: unknown): (boolean, string?)
	if not checkRateLimit(player) then
		return false, "Action rate limited. Please slow down."
	end

	if not PlayerActionLock.Acquire(player) then
		return false, "Another pedestal or inventory action is in progress."
	end

	local ok, success, errMsg = pcall(function(): (boolean, string?)
		if typeof(slotIndex) ~= "number" or slotIndex ~= math.floor(slotIndex) then
			return false, "Invalid pedestal slot index."
		end

		if not DataService.IsLoaded(player) then
			return false, "Data is loading..."
		end

		local pedestalSlots = DataService.Get(player, "PedestalSlots") or GameConfig.Plot.DefaultPedestalsPerPlot
		if slotIndex < 1 or slotIndex > pedestalSlots or slotIndex > 10 then
			return false, "Invalid slot."
		end

		local placed = DataService.Get(player, "PlacedSwords")
		local slotKey = tostring(slotIndex)
		if typeof(placed) ~= "table" or placed[slotKey] == nil then
			return false, "Slot is already empty."
		end

		local updated = table.clone(placed)
		updated[slotKey] = nil

		local saved = DataService.Set(player, "PlacedSwords", updated)
		if saved then
			return true, nil
		else
			return false, "Failed to update pedestal slot."
		end
	end)

	PlayerActionLock.Release(player)

	if not ok then
		warn(("[PlotService.RemoveSword] Error for %s: %s"):format(player.Name, tostring(success)))
		return false, "An unexpected error occurred while removing sword."
	end

	return success, errMsg
end

-- Simulates offline income calculation for a given number of seconds (testing helper)
function PlotService.SimulateOfflineIncome(player: Player, seconds: number): (number, number)
	if not DataService.IsLoaded(player) then
		return 0, 0
	end

	local cap = GameConfig.Plot.OfflineIncomeCapSeconds or (8 * 3600)
	local elapsed = math.clamp(seconds, 0, cap)
	if elapsed <= 0 then
		return 0, 0
	end

	local placed = DataService.Get(player, "PlacedSwords")
	local owned = DataService.Get(player, "OwnedSwords")
	local pedestalSlots = DataService.Get(player, "PedestalSlots") or GameConfig.Plot.DefaultPedestalsPerPlot

	local passivePerSec = 0
	if type(placed) == "table" and type(owned) == "table" then
		local ownedMap: { [string]: any } = {}
		for _, entry in owned do
			if type(entry) == "table" and type(entry.uid) == "string" then
				ownedMap[entry.uid] = entry
			end
		end

		local passiveRate = GameConfig.Plot.PassiveRateMultiplier or 0.5
		for slotNum = 1, math.min(10, pedestalSlots) do
			local swordUid = placed[tostring(slotNum)]
			if swordUid and ownedMap[swordUid] then
				local swordEntry = ownedMap[swordUid]
				local gpt = TapService.CalculateSwordGoldPerTap(player, swordEntry)
				passivePerSec += (gpt * passiveRate)
			end
		end
	end

	local rawOfflineGold = passivePerSec * elapsed
	local earnedGold = math.floor(rawOfflineGold + 0.5)

	if earnedGold > 0 then
		DataService.Increment(player, "Gold", earnedGold)
	end

	DataService.Set(player, "LastLogout", os.time())

	local minGold = GameConfig.Plot.MinOfflineIncomePopupThreshold or 1
	local minSeconds = GameConfig.Plot.MinOfflineSeconds or 60
	if earnedGold >= minGold and elapsed >= minSeconds then
		pendingOfflineIncome[player] = {
			gold = earnedGold,
			seconds = elapsed,
		}
	end

	return earnedGold, elapsed
end

-- Checks if a sword uid is placed on any of the player's pedestals
function PlotService.IsSwordPlaced(player: Player, uid: string): boolean
	if typeof(uid) ~= "string" or uid == "" then
		return false
	end
	if not DataService.IsLoaded(player) then
		return false
	end

	local placed = DataService.Get(player, "PlacedSwords")
	if type(placed) ~= "table" then
		return false
	end

	for _, placedUid in placed do
		if placedUid == uid then
			return true
		end
	end

	return false
end

-- Returns the player's assigned plot ID and instance
function PlotService.GetPlayerPlot(player: Player): (number?, Instance?)
	local plotId = playerToPlot[player]
	if plotId then
		return plotId, registeredPlots[plotId]
	end
	return nil, nil
end

-- Returns the player who owns a specific plot ID
function PlotService.GetPlotOwner(plotId: number): Player?
	return plotToPlayer[plotId]
end

-- Returns all registered plot instances
function PlotService.GetAllPlots(): { [number]: Instance }
	return registeredPlots
end

function PlotService.Start()
	-- 1. Discover or create plots
	discoverPlots()

	-- 2. Setup RemoteFunctions
	local getPlotDataFunc = Remotes.getFunction("GetPlotData")
	getPlotDataFunc.OnServerInvoke = function(player: Player)
		-- Wait until explicit plot assignment has finished (up to 10s)
		local start = os.clock()
		while not plotAssignmentFinished[player] and (os.clock() - start) < 10 and player.Parent == Players do
			task.wait(0.1)
		end

		local plotId = playerToPlot[player]
		local placedSwords = DataService.Get(player, "PlacedSwords") or {}
		local pedestalSlots = DataService.Get(player, "PedestalSlots") or (GameConfig.Plot.DefaultPedestalsPerPlot or 4)

		-- Read-only: does not clear pending offline income
		local offlineIncome = pendingOfflineIncome[player]

		return {
			plotId = plotId,
			placedSwords = placedSwords,
			pedestalSlots = pedestalSlots,
			offlineIncome = offlineIncome,
		}
	end

	local claimOfflineFunc = Remotes.getFunction("ClaimOfflineIncome")
	claimOfflineFunc.OnServerInvoke = function(player: Player)
		-- Waits until playerInitialized is true for that player (with 10s safety timeout)
		local start = os.clock()
		while not playerInitialized[player] and (os.clock() - start) < 10 and player.Parent == Players do
			task.wait(0.1)
		end
		if not playerInitialized[player] then
			return nil
		end

		local result = pendingOfflineIncome[player]
		pendingOfflineIncome[player] = nil
		return result
	end

	local placeSwordFunc = Remotes.getFunction("PlaceSword")
	placeSwordFunc.OnServerInvoke = function(player: Player, slotIndex: unknown, swordUid: unknown)
		return PlotService.PlaceSword(player, slotIndex, swordUid)
	end

	local removeSwordFunc = Remotes.getFunction("RemoveSword")
	removeSwordFunc.OnServerInvoke = function(player: Player, slotIndex: unknown)
		return PlotService.RemoveSword(player, slotIndex)
	end

	-- 3. Player lifecycle handling
	local function onPlayerJoined(player: Player)
		task.spawn(function()
			if DataService.WaitForProfile(player) then
				if player.Parent ~= Players then
					plotAssignmentFinished[player] = true
					return
				end
				processOfflineIncome(player)
				playerInitialized[player] = true
				assignPlot(player)
				plotAssignmentFinished[player] = true
			else
				plotAssignmentFinished[player] = true
			end
		end)
	end

	-- Listen for PlacedSwords, PedestalSlots, or OwnedSwords updates to refresh pedestal attributes
	DataService.Changed:Connect(function(player: Player, key: string, _value: any)
		if key == "PlacedSwords" or key == "PedestalSlots" or key == "OwnedSwords" then
			refreshPedestals(player)
		end
	end)

	Players.PlayerAdded:Connect(onPlayerJoined)
	Players.PlayerRemoving:Connect(function(player: Player)
		releasePlot(player)
		playerBuckets[player] = nil
		PlayerActionLock.Release(player)
		pendingOfflineIncome[player] = nil
		playerInitialized[player] = nil
		plotAssignmentFinished[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		onPlayerJoined(player)
	end

	-- 4. Passive Income Ticker (1 Hz)
	-- Reads profile.Data.PlacedSwords, sums passive Gold across placed swords,
	-- and issues exactly ONE DataService.Increment per player per second without rounding per sword.
	task.spawn(function()
		local passiveRate = GameConfig.Plot.PassiveRateMultiplier or 0.5
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				if playerInitialized[player] and DataService.IsLoaded(player) then
					local placed = DataService.Get(player, "PlacedSwords")
					local owned = DataService.Get(player, "OwnedSwords")
					local pedestalSlots = DataService.Get(player, "PedestalSlots") or GameConfig.Plot.DefaultPedestalsPerPlot

					if type(placed) == "table" and type(owned) == "table" then
						local ownedMap: { [string]: any } = {}
						for _, entry in owned do
							if type(entry) == "table" and type(entry.uid) == "string" then
								ownedMap[entry.uid] = entry
							end
						end

						local totalPlayerPassiveGold = 0
						for slotNum = 1, math.min(10, pedestalSlots) do
							local swordUid = placed[tostring(slotNum)]
							if swordUid and ownedMap[swordUid] then
								local swordEntry = ownedMap[swordUid]
								local gpt = TapService.CalculateSwordGoldPerTap(player, swordEntry)
								totalPlayerPassiveGold += (gpt * passiveRate)
							end
						end

						if totalPlayerPassiveGold > 0 then
							DataService.Increment(player, "Gold", totalPlayerPassiveGold)
						end
					end
				end
			end
		end
	end)
end

return PlotService
