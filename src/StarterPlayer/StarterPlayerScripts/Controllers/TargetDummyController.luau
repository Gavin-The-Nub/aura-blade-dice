--!strict
-- TargetDummyController: Manages personal target dummy visual reactions on tap results.
-- Triggers sparks, slight hit recoil, and 3D floating damage numbers when the player
-- is within range of their own dummy on their assigned plot.
-- Never calculates Gold, never displays both 2D and 3D numbers, and caps active instances.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("Game"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlotController = require(script.Parent:WaitForChild("PlotController"))

local TARGET_DUMMY_TAG = "TargetDummy"
local MAX_DUMMY_RETRIES = 10

local TargetDummyController = {}

-- State tracking
local assignedPlotId: number? = nil
local assignedPlotModel: Instance? = nil
local currentDummy: Instance? = nil
local dummyPrimaryPart: BasePart? = nil
local initialDummyPivot: CFrame? = nil

local sparkAttachment: Attachment? = nil
local sparkEmitter: ParticleEmitter? = nil

local recoilCFrameValue: CFrameValue? = nil
local recoilTweenIn: Tween? = nil
local recoilTweenOut: Tween? = nil
local recoilConn: RBXScriptConnection? = nil

local activeFloatingNumbers: { BillboardGui } = {}
local lastSparkTime = 0
local lastRecoilTime = 0

local retryThread: thread? = nil
local plotAssignedConn: RBXScriptConnection? = nil

-- Cleans up temporary visual instances, animations, and restores dummy pivot
local function cleanupDummyVisuals()
	for _, billboard in activeFloatingNumbers do
		if billboard and billboard.Parent then
			billboard:Destroy()
		end
	end
	table.clear(activeFloatingNumbers)

	if recoilTweenIn then
		recoilTweenIn:Cancel()
		recoilTweenIn = nil
	end
	if recoilTweenOut then
		recoilTweenOut:Cancel()
		recoilTweenOut = nil
	end
	if recoilConn then
		recoilConn:Disconnect()
		recoilConn = nil
	end
	if recoilCFrameValue then
		recoilCFrameValue:Destroy()
		recoilCFrameValue = nil
	end

	if sparkEmitter and sparkEmitter.Parent then
		sparkEmitter:Destroy()
		sparkEmitter = nil
	end
	if sparkAttachment and sparkAttachment.Parent then
		sparkAttachment:Destroy()
		sparkAttachment = nil
	end

	-- Restore original pivot of the entire dummy
	if currentDummy and currentDummy.Parent and initialDummyPivot then
		if currentDummy:IsA("Model") then
			currentDummy:PivotTo(initialDummyPivot)
		elseif currentDummy:IsA("BasePart") then
			currentDummy.CFrame = initialDummyPivot
		end
	end

	currentDummy = nil
	dummyPrimaryPart = nil
	initialDummyPivot = nil
end

-- Completely resets and cleans up controller state
function TargetDummyController.Cleanup()
	if retryThread then
		task.cancel(retryThread)
		retryThread = nil
	end
	cleanupDummyVisuals()
	assignedPlotId = nil
	assignedPlotModel = nil
end

-- Searches for the TargetDummy instance corresponding to a plotId
local function findDummyForPlot(plotId: number): Instance?
	-- 1. Check inside assignedPlotModel if available
	if assignedPlotModel and assignedPlotModel.Parent then
		for _, desc in assignedPlotModel:GetDescendants() do
			if CollectionService:HasTag(desc, TARGET_DUMMY_TAG) or desc.Name == "TargetDummy" then
				return desc
			end
		end
	end

	-- 2. Check CollectionService tagged dummies matching PlotId attribute
	for _, inst in CollectionService:GetTagged(TARGET_DUMMY_TAG) do
		if inst:GetAttribute("PlotId") == plotId then
			return inst
		end
	end

	-- 3. Check workspace Plots folder
	local plotsFolder = workspace:FindFirstChild("Plots")
	if plotsFolder then
		local pModel = plotsFolder:FindFirstChild(("Plot_%d"):format(plotId))
		if pModel then
			for _, desc in pModel:GetDescendants() do
				if CollectionService:HasTag(desc, TARGET_DUMMY_TAG) or desc.Name == "TargetDummy" then
					return desc
				end
			end
		end
	end

	-- 4. Check all Plot-tagged objects in workspace
	for _, p in CollectionService:GetTagged("Plot") do
		if p:GetAttribute("PlotId") == plotId then
			for _, desc in p:GetDescendants() do
				if CollectionService:HasTag(desc, TARGET_DUMMY_TAG) or desc.Name == "TargetDummy" then
					return desc
				end
			end
		end
	end

	return nil
end

-- Configures particle emitters and attachments on a newly bound dummy
local function setupDummy(dummy: Instance)
	cleanupDummyVisuals()
	currentDummy = dummy

	local primary: BasePart? = nil
	if dummy:IsA("Model") then
		primary = dummy.PrimaryPart
			or (dummy:FindFirstChild("Torso") :: BasePart?)
			or (dummy:FindFirstChildWhichIsA("BasePart") :: BasePart?)
	elseif dummy:IsA("BasePart") then
		primary = dummy
	end

	dummyPrimaryPart = primary
	if dummy:IsA("Model") then
		initialDummyPivot = dummy:GetPivot()
	elseif primary then
		initialDummyPivot = primary.CFrame
	end

	if primary then
		local attach = Instance.new("Attachment")
		attach.Name = "HitEffectAttachment"
		attach.Position = Vector3.new(0, 0, -0.6)
		attach.Parent = primary
		sparkAttachment = attach

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "HitSparks"
		emitter.Rate = 0 -- manual emit only
		emitter.Speed = NumberRange.new(5, 10)
		emitter.Lifetime = NumberRange.new(0.2, 0.3)
		emitter.SpreadAngle = Vector2.new(50, 50)
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Color = ColorSequence.new(Theme.Colors.AuraCyan)
		emitter.Enabled = true
		emitter.Parent = attach
		sparkEmitter = emitter
	end
end

-- Binds controller to a target plot, handling replication delays and rebinding on plot changes
local function bindToPlot(plotId: number?, plotModel: Instance?)
	if retryThread then
		task.cancel(retryThread)
		retryThread = nil
	end

	if plotId == nil then
		TargetDummyController.Cleanup()
		return
	end

	if plotId == assignedPlotId and currentDummy and currentDummy.Parent then
		return
	end

	cleanupDummyVisuals()
	assignedPlotId = plotId
	assignedPlotModel = plotModel

	retryThread = task.spawn(function()
		local attempts = 0
		while attempts < MAX_DUMMY_RETRIES do
			if assignedPlotId ~= plotId then
				return
			end

			local dummy = findDummyForPlot(plotId)
			if dummy then
				setupDummy(dummy)
				return
			end

			attempts += 1
			task.wait(0.5)
		end

		warn(("[TargetDummyController] Plot %d dummy not found after %d attempts; stopping retries."):format(plotId, MAX_DUMMY_RETRIES))
	end)
end

-- Reacts to a TapResult event from the server if character is near own dummy.
-- Returns true if dummy reacted, or false if out of range / dummy not found / error.
function TargetDummyController.OnTapResult(goldEarned: number, isCrit: boolean): boolean
	local ok, handled = pcall(function(): boolean
		-- Validate goldEarned is a valid finite number
		if type(goldEarned) ~= "number" or goldEarned ~= goldEarned or math.abs(goldEarned) == math.huge or goldEarned < 0 then
			return false
		end

		if not assignedPlotId then
			local pId, pModel = PlotController.GetAssignedPlot()
			if pId then
				bindToPlot(pId, pModel)
			else
				return false
			end
		end

		if not currentDummy or not currentDummy.Parent or not dummyPrimaryPart or not dummyPrimaryPart.Parent then
			return false
		end

		local character = player.Character
		if not character then
			return false
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			return false
		end

		local maxDist = (GameConfig.TargetDummy and GameConfig.TargetDummy.NearDistance) or 18
		local dist = (rootPart.Position - dummyPrimaryPart.Position).Magnitude
		if dist > maxDist then
			return false
		end

		local now = os.clock()

		-- 1. Spark burst (throttled min 0.1s apart, few short particles)
		local sparkThrottle = (GameConfig.TargetDummy and GameConfig.TargetDummy.SparkThrottle) or 0.1
		if sparkEmitter and (now - lastSparkTime >= sparkThrottle) then
			lastSparkTime = now
			sparkEmitter:Emit(if isCrit then 6 else 4)
		end

		-- 2. Whole dummy recoil / wobble via Model:PivotTo on a short tween of CFrameValue
		if currentDummy and currentDummy.Parent and initialDummyPivot and (now - lastRecoilTime >= 0.08) then
			lastRecoilTime = now
			local pivot = initialDummyPivot :: CFrame

			if recoilTweenIn then
				recoilTweenIn:Cancel()
				recoilTweenIn = nil
			end
			if recoilTweenOut then
				recoilTweenOut:Cancel()
				recoilTweenOut = nil
			end
			if recoilConn then
				recoilConn:Disconnect()
				recoilConn = nil
			end
			if not recoilCFrameValue then
				recoilCFrameValue = Instance.new("CFrameValue")
			end

			local cval = recoilCFrameValue :: CFrameValue
			cval.Value = pivot

			recoilConn = cval.Changed:Connect(function(newCFrame: CFrame)
				if currentDummy and currentDummy.Parent then
					if currentDummy:IsA("Model") then
						currentDummy:PivotTo(newCFrame)
					elseif currentDummy:IsA("BasePart") then
						currentDummy.CFrame = newCFrame
					end
				end
			end)

			local recoilTarget = pivot * CFrame.Angles(-0.07, 0, 0)
			local inInfo = TweenInfo.new(0.04, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local outInfo = TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

			local tweenIn = TweenService:Create(cval, inInfo, { Value = recoilTarget })
			local tweenOut = TweenService:Create(cval, outInfo, { Value = pivot })
			recoilTweenIn = tweenIn
			recoilTweenOut = tweenOut

			tweenIn.Completed:Connect(function()
				if recoilTweenOut and currentDummy and currentDummy.Parent then
					tweenOut:Play()
				end
			end)

			tweenIn:Play()
		end

		-- 3. Floating damage number (capped at 6, oldest removed first)
		local maxNumbers = (GameConfig.TargetDummy and GameConfig.TargetDummy.MaxFloatingNumbers) or 6
		while #activeFloatingNumbers >= maxNumbers do
			local oldest = table.remove(activeFloatingNumbers, 1)
			if oldest and oldest.Parent then
				oldest:Destroy()
			end
		end

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "DummyDamageNumber"
		billboard.Size = UDim2.new(0, 160, 0, 40)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 60
		billboard.Adornee = dummyPrimaryPart

		local jitterX = (math.random(-6, 6)) / 10
		local jitterZ = (math.random(-6, 6)) / 10
		local startY = 2.4
		billboard.StudsOffset = Vector3.new(jitterX, startY, jitterZ)
		billboard.Parent = dummyPrimaryPart

		local label = Instance.new("TextLabel")
		label.Name = "DamageLabel"
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Active = false

		local formattedGold = NumberFormat.format(goldEarned)
		if isCrit then
			label.Text = "+" .. formattedGold .. " CRIT!"
			label.TextColor3 = Theme.Colors.TextCrit
			label.TextSize = 28
			label.Font = Theme.Fonts.Title
		else
			label.Text = "+" .. formattedGold
			label.TextColor3 = Theme.Colors.TextPrimary
			label.TextSize = 20
			label.Font = Theme.Fonts.Body
		end

		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.TextStroke.Color
		stroke.Thickness = if isCrit then 2.2 else 1.2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = label
		label.Parent = billboard

		table.insert(activeFloatingNumbers, billboard)

		local tweenDuration = if isCrit then 0.75 else 0.6
		local targetY = startY + (if isCrit then 3.0 else 2.2)
		local tweenInfo = TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		local moveTween = TweenService:Create(billboard, tweenInfo, {
			StudsOffset = Vector3.new(jitterX, targetY, jitterZ),
		})
		local fadeTween = TweenService:Create(label, tweenInfo, {
			TextTransparency = 1,
		})
		local strokeFade = TweenService:Create(stroke, tweenInfo, {
			Transparency = 1,
		})

		moveTween:Play()
		fadeTween:Play()
		strokeFade:Play()

		moveTween.Completed:Connect(function()
			local idx = table.find(activeFloatingNumbers, billboard)
			if idx then
				table.remove(activeFloatingNumbers, idx)
			end
			billboard:Destroy()
		end)

		return true
	end)

	if not ok then
		warn("[TargetDummyController] Error during dummy tap reaction: " .. tostring(handled))
		return false
	end

	return handled == true
end

-- Initializes the controller and listens for plot assignment changes
function TargetDummyController.Init()
	-- Handle PlotAssigned if already received before controller started
	local existingPlotId, existingPlotModel = PlotController.GetAssignedPlot()
	if existingPlotId then
		bindToPlot(existingPlotId, existingPlotModel)
	end

	-- Watch for initial plot assignment in case GetPlotData was in-flight when Init ran
	task.spawn(function()
		local start = os.clock()
		while not assignedPlotId and (os.clock() - start) < 10 do
			local pId, pModel = PlotController.GetAssignedPlot()
			if pId then
				bindToPlot(pId, pModel)
				break
			end
			task.wait(0.2)
		end
	end)

	-- Listen for future PlotAssigned events
	local plotAssignedEvent = Remotes.getEvent("PlotAssigned")
	if plotAssignedConn then
		plotAssignedConn:Disconnect()
		plotAssignedConn = nil
	end

	plotAssignedConn = plotAssignedEvent.OnClientEvent:Connect(function(plotId: unknown, pModel: unknown)
		local pId = if type(plotId) == "number" then plotId else nil
		local pInst = if typeof(pModel) == "Instance" then pModel else nil
		bindToPlot(pId, pInst)
	end)
end

function TargetDummyController.Destroy()
	if plotAssignedConn then
		plotAssignedConn:Disconnect()
		plotAssignedConn = nil
	end
	TargetDummyController.Cleanup()
end

return TargetDummyController
