--!strict
-- Creates every RemoteEvent / RemoteFunction from code at server startup, because
-- Script Sync can't save Remote instances to disk. Add new remotes to the lists below.
-- Server: Remotes.init() once (Main does this). Client: Remotes.getEvent("Name").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

-- Names only. Payload shapes are validated by the server handler that owns each remote.
local EVENTS: { string } = {
	"DevMessage", -- server -> client text for Studio-only dev commands (DevCommands)
	"DataChanged", -- server -> client: (key: string, value: any)
	"Tap", -- client -> server: ()
	"TapResult", -- server -> client: (goldEarned: number, isCrit: boolean)
	"ToggleAutoTap", -- client -> server: ()
	"AutoTapStateChanged", -- server -> client: (isEnabled: boolean)
	"FeverUpdated", -- server -> client: (points: number, maxPoints: number, isActive: boolean, durationRemaining: number)
	"Roll", -- client -> server: ()
	"RollResult", -- server -> client: (success: boolean, swordData: any, isAuto: boolean, message: string?)
	"ToggleAutoRoll", -- client -> server: ()
	"AutoRollStateChanged", -- server -> client: (isEnabled: boolean)
	"SetAutoSellRule", -- client -> server: (rarity: string, enabled: boolean)
	"PlotAssigned", -- server -> client: (plotId: number?, plotModel: Instance?)
}
local FUNCTIONS: { string } = {
	"GetInitialData", -- client -> server: () -> DataTemplate.PlayerData?
	"EquipSword", -- client -> server: (uid: string) -> (boolean, string?)
	"SellSword", -- client -> server: (uid: string) -> (boolean, string?)
	"BuyDice", -- client -> server: (tier: number) -> (boolean, string?)
	"EquipDice", -- client -> server: (tier: number) -> (boolean, string?)
	"GetPlotData", -- client -> server: () -> { plotId: number?, placedSwords: { [string]: string }, pedestalSlots: number, offlineIncome: any? }?
	"ClaimOfflineIncome", -- client -> server: () -> { gold: number, seconds: number }?
	"PlaceSword", -- client -> server: (slotIndex: number, swordUid: string) -> (boolean, string?)
	"RemoveSword", -- client -> server: (slotIndex: number) -> (boolean, string?)
	"EquipBest", -- client -> server: () -> (boolean, string?)
}

local Remotes = {}

local function getFolder(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing and existing:IsA("Folder") then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	-- Client: wait for the server to create it, so we never race startup.
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local function ensure(folder: Folder, className: string, name: string)
	if folder:FindFirstChild(name) then
		return
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
end

-- Server only. Safe to call more than once.
function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init must run on the server")
	local folder = getFolder()
	for _, name in EVENTS do
		ensure(folder, "RemoteEvent", name)
	end
	for _, name in FUNCTIONS do
		ensure(folder, "RemoteFunction", name)
	end
end

function Remotes.getEvent(name: string): RemoteEvent
	assert(table.find(EVENTS, name), "Unknown RemoteEvent: " .. name)
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Remotes.getFunction(name: string): RemoteFunction
	assert(table.find(FUNCTIONS, name), "Unknown RemoteFunction: " .. name)
	return getFolder():WaitForChild(name) :: RemoteFunction
end

return Remotes
