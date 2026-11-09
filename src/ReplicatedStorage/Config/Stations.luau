--!strict
-- Config/Stations: Central configuration for world stations.
-- Defines prompt texts, layout positions, sizes, and Theme token names (strings only, no Color3).

export type StationType = "Dice" | "Sell" | "Shop" | "Appraiser" | "Enchanter" | "Runesmith" | "IronCitadel" | "CrimsonPagoda" | "VoidSpire"

export type StationDef = {
	Type: StationType,
	ActionText: string,
	ObjectText: string,
	Position: Vector3,
	Size: Vector3,
	ColorToken: string, -- Key in Theme.Colors, e.g. "AuraGold"
	HasModel: boolean,
	Group: "Plaza" | "TrialGrounds",
	PromptEnabled: boolean?,
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
	TeleportDestinations: {
		Hub: Vector3,
		Shop: Vector3,
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
	TeleportDestinations = {
		Hub = Vector3.new(0, 1.5, 0),
		Shop = Vector3.new(0, 1.5, -135),
	},
	PlazaStations = {
		-- Central Hub stalls (center of map, leaving space for Trial entrances)
		Appraiser = {
			Type = "Appraiser",
			ActionText = "Appraise",
			ObjectText = "Master Appraiser",
			Position = Vector3.new(-16, 1.5, -10),
			Size = Vector3.new(8, 2, 8),
			ColorToken = "AuraPurple",
			HasModel = true,
			Group = "Plaza",
		},
		Enchanter = {
			Type = "Enchanter",
			ActionText = "Enchant",
			ObjectText = "Enchanter",
			Position = Vector3.new(16, 1.5, -10),
			Size = Vector3.new(8, 2, 8),
			ColorToken = "AuraPurple",
			HasModel = true,
			Group = "Plaza",
		},
		Runesmith = {
			Type = "Runesmith",
			ActionText = "Bless",
			ObjectText = "Runesmith",
			Position = Vector3.new(0, 1.5, 18),
			Size = Vector3.new(8, 2, 8),
			ColorToken = "AuraCyan",
			HasModel = true,
			Group = "Plaza",
		},
		-- Shop area stalls (outside plots perimeter at North Z = -150 to -155)
		Dice = {
			Type = "Dice",
			ActionText = "Roll",
			ObjectText = "Dice Merchant",
			Position = Vector3.new(-30, 1.5, -150),
			Size = Vector3.new(8, 2, 8),
			ColorToken = "AuraGold",
			HasModel = true,
			Group = "Plaza",
		},
		Shop = {
			Type = "Shop",
			ActionText = "Browse",
			ObjectText = "Shop",
			Position = Vector3.new(0, 1.5, -155),
			Size = Vector3.new(8, 2, 8),
			ColorToken = "AuraCyan",
			HasModel = true,
			Group = "Plaza",
		},
		Sell = {
			Type = "Sell",
			ActionText = "Sell",
			ObjectText = "Sell Stall",
			Position = Vector3.new(30, 1.5, -150),
			Size = Vector3.new(8, 2, 8),
			ColorToken = "AuraEmerald",
			HasModel = true,
			Group = "Plaza",
		},
	},
	TrialGroundsMarkers = {
		-- Three Trial entrance markers inside the hub (radius 35-45 from hub center, >=20 studs from stalls & plots)
		IronCitadel = {
			Type = "IronCitadel",
			ActionText = "Enter",
			ObjectText = "Iron Citadel",
			Position = Vector3.new(-38, 1.5, 15),
			Size = Vector3.new(8, 2, 8),
			ColorToken = "AuraEmerald",
			HasModel = true,
			Group = "TrialGrounds",
			PromptEnabled = false,
		},
		CrimsonPagoda = {
			Type = "CrimsonPagoda",
			ActionText = "Enter",
			ObjectText = "Crimson Pagoda",
			Position = Vector3.new(38, 1.5, 15),
			Size = Vector3.new(8, 2, 8),
			ColorToken = "AuraCrimson",
			HasModel = true,
			Group = "TrialGrounds",
			PromptEnabled = false,
		},
		VoidSpire = {
			Type = "VoidSpire",
			ActionText = "Enter",
			ObjectText = "Void Spire",
			Position = Vector3.new(0, 1.5, -38),
			Size = Vector3.new(8, 2, 8),
			ColorToken = "AuraPurple",
			HasModel = true,
			Group = "TrialGrounds",
			PromptEnabled = false,
		},
	},
	AllStations = {} :: { [StationType]: StationDef },
}

-- Populate AllStations map for quick lookup by StationType (Plaza takes precedence)
for _, def in Stations.PlazaStations do
	Stations.AllStations[def.Type] = def
end
for _, def in Stations.TrialGroundsMarkers do
	if not Stations.AllStations[def.Type] then
		Stations.AllStations[def.Type] = def
	end
end

return Stations
