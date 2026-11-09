--!strict
-- WorldTeleportService: Server-authoritative player teleportation between Hub, Home plot, and Shop.
-- Validates rate limits, character health, data loaded state, trial state, and plot assignment.
-- Resolves destinations via CollectionService tags, requests streaming around arrival if StreamingEnabled,
-- applies a safe vertical and random horizontal offset (+-1.5 studs), and pivots the character.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StationsConfig = require(ReplicatedStorage.Config.Stations)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(ServerScriptService.Services.DataService)
local PlotService = require(ServerScriptService.Services.PlotService)

local TELEPORT_DESTINATION_TAG = "TeleportDestination"
local RATE_LIMIT_SECONDS = 1.0
local VALID_DESTINATIONS: { [string]: boolean } = {
	Hub = true,
	Home = true,
	Shop = true,
}

local WorldTeleportService = {}

-- State tracking
local lastTeleportTime: { [Player]: number } = {}

-- Clear hook for future Trial system (Trials reject teleports when active)
function WorldTeleportService.IsTrialActive(_player: Player): boolean
	return false
end

-- Resolves the target destination CFrame on the server
local function resolveDestinationCFrame(player: Player, destination: string): (CFrame?, string?)
	if destination == "Home" then
		local plotId = PlotService.GetPlayerPlot(player)
		if not plotId then
			return nil, "You do not have an assigned plot yet."
		end
		local spawnCFrame = PlotService.GetPlotSpawnCFrame(plotId)
		if not spawnCFrame then
			return nil, "Could not find plot spawn pad."
		end
		return spawnCFrame, nil
	elseif destination == "Hub" or destination == "Shop" then
		for _, inst in CollectionService:GetTagged(TELEPORT_DESTINATION_TAG) do
			if inst:IsA("BasePart") and inst:GetAttribute("Destination") == destination then
				return inst.CFrame, nil
			end
		end

		-- Fallback to config coordinates if marker instance is missing
		local fallbackPos = StationsConfig.TeleportDestinations[destination :: any]
		if fallbackPos then
			return CFrame.new(fallbackPos), nil
		end

		return nil, ("Destination '%s' is not configured."):format(destination)
	end

	return nil, "Invalid destination."
end

-- Teleports a player to a destination with full server authority and safety checks
function WorldTeleportService.TeleportPlayer(player: Player, destination: unknown): (boolean, string?)
	if typeof(destination) ~= "string" or not VALID_DESTINATIONS[destination] then
		return false, "Invalid destination."
	end

	-- Check rate limit
	local now = os.clock()
	local lastTime = lastTeleportTime[player] or 0
	if now - lastTime < RATE_LIMIT_SECONDS then
		return false, "Please wait before teleporting again."
	end

	-- Check character alive
	local character = player.Character
	if not character then
		return false, "Character unavailable."
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false, "Character is not alive."
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return false, "Character root part unavailable."
	end

	-- Check data loaded
	if not DataService.IsLoaded(player) then
		return false, "Player data is still loading."
	end

	-- Check trial active hook
	if WorldTeleportService.IsTrialActive(player) then
		return false, "Cannot teleport while in a Trial!"
	end

	-- Resolve target destination
	local targetCFrame, err = resolveDestinationCFrame(player, destination)
	if not targetCFrame then
		return false, err or "Destination unreachable."
	end

	-- Apply rate limit timestamp
	lastTeleportTime[player] = now

	-- Add random horizontal arrival offset (+-1.5 studs) and vertical clearance (+3 studs)
	local randomX = (math.random() * 3) - 1.5
	local randomZ = (math.random() * 3) - 1.5
	local arrivalCFrame = targetCFrame * CFrame.new(randomX, 3.0, randomZ)

	-- Request streaming around destination before PivotTo if StreamingEnabled
	if workspace.StreamingEnabled then
		pcall(function()
			player:RequestStreamAroundAsync(arrivalCFrame.Position)
		end)
	end

	-- Re-verify character state after yielding streaming request
	local currentChar = player.Character
	if currentChar ~= character or not currentChar or not currentChar.Parent then
		return false, "Character changed or unavailable during teleport."
	end
	local currentHum = currentChar:FindFirstChildOfClass("Humanoid")
	if not currentHum or currentHum.Health <= 0 or currentHum.Parent ~= currentChar then
		return false, "Character is no longer alive."
	end
	local currentHrp = currentChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not currentHrp or currentHrp ~= hrp or currentHrp.Parent ~= currentChar then
		return false, "Character root part unavailable."
	end

	-- Cancel residual momentum before moving
	currentHrp.AssemblyLinearVelocity = Vector3.zero
	currentHrp.AssemblyAngularVelocity = Vector3.zero

	-- Server-authoritative move
	currentChar:PivotTo(arrivalCFrame)

	return true, nil
end

function WorldTeleportService.Start()
	-- Clean up rate-limit state on leave
	Players.PlayerRemoving:Connect(function(player: Player)
		lastTeleportTime[player] = nil
	end)

	-- Register RemoteFunction handler
	local teleportFunc = Remotes.getFunction("Teleport")
	teleportFunc.OnServerInvoke = function(player: Player, destination: unknown)
		return WorldTeleportService.TeleportPlayer(player, destination)
	end

	print("[WorldTeleportService] Initialized.")
end

return WorldTeleportService
