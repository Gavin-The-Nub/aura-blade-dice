--!strict
-- Config/Stations: Central configuration for world stations.
-- Defines prompt texts, layout positions, sizes, and Theme token names (strings only, no Color3).

export type StationType = "Dice" | "Sell" | "Shop" | "Appraiser" | "Enchanter" | "Runesmith"

export type StationDef = {
	Type: StationType,
	ActionText: string,
	ObjectText: string,
	Position: Vector3,
	Size: Vector3,
	ColorToken: string, -- Key in Theme.Colors, e.g. "AuraGold"
	HasModel: boolean,
	Group: "Plaza" | "TrialGrounds",
}

export type StationsConfig = {
	PromptDefaults: {
		HoldDuration: number,
		RequiresLineOfSight: boolean,
		MaxActivationDistance: number,
	},
	SignDefaults: {
		MaxDistance: number,
		StudsOffset: Vector3,
	},
	PlazaStations: { [StationType]: StationDef },
	TrialGroundsMarkers: { [string]: StationDef },
	AllStations: { [StationType]: StationDef },
}

local Stations: StationsConfig = {
	PromptDefaults = {
		HoldDuration = 0,
		RequiresLineOfSight = false,
		MaxActivationDistance = 12,
	},
	SignDefaults = {
		MaxDistance = 45,
		StudsOffset = Vector3.new(0, 4.5, 0),
	},
	PlazaStations = {
		Dice = {
			Type = "Dice",
			ActionText = "Roll",
			ObjectText = "Dice Merchant",
			-- North of SpawnLocation (0, 0.5, 0, size 12x12), clear of plots at radius 80
			Position = Vector3.new(0, 1.5, -22),
			Size = Vector3.new(8, 2, 8),
			ColorToken = "AuraGold",
			HasModel = true,
			Group = "Plaza",
		},
		Sell = {
			Type = "Sell",
			ActionText = "Sell",
			ObjectText = "Sell Stall",
			-- West of SpawnLocation, clear of plots and pedestal prompts
			Position = Vector3.new(-20, 1.5, -10),
			Size = Vector3.new(8, 2, 8),
			ColorToken = "AuraEmerald",
			HasModel = true,
			Group = "Plaza",
		},
		Shop = {
			Type = "Shop",
			ActionText = "Browse",
			ObjectText = "Shop",
			-- East of SpawnLocation, clear of plots and pedestal prompts
			Position = Vector3.new(20, 1.5, -10),
			Size = Vector3.new(8, 2, 8),
			ColorToken = "AuraCyan",
			HasModel = true,
			Group = "Plaza",
		},
	},
	TrialGroundsMarkers = {
		-- Reserved marker for Trial-side group (near Trials): no world model generated in S1
		TrialGroupReserved = {
			Type = "Appraiser",
			ActionText = "Appraise",
			ObjectText = "Master Appraiser",
			Position = Vector3.new(0, 1.5, 120),
			Size = Vector3.new(8, 2, 8),
			ColorToken = "AuraPurple",
			HasModel = false,
			Group = "TrialGrounds",
		},
	},
	AllStations = {} :: { [StationType]: StationDef },
}

-- Populate AllStations map for quick lookup by StationType
for _, def in Stations.PlazaStations do
	Stations.AllStations[def.Type] = def
end
for _, def in Stations.TrialGroundsMarkers do
	Stations.AllStations[def.Type] = def
end

return Stations
