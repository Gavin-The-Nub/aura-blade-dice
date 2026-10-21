--!strict
-- Config/Assets: Centralized registry for 2D UI image asset IDs (rbxassetid://...).
-- Paste your custom image IDs here; MainHUD and UI components read from this module directly.

export type AssetRegistry = {
	Plates: {
		Default: string,
		Shop: string,
		Rebirth: string,
		Index: string,
		Swords: string,
		Roll: string,
		Upgrades: string,
	},
	Icons: {
		Shop: string,
		Rebirth: string,
		Index: string,
		Swords: string,
		Roll: string,
		Upgrades: string,
	},
}

local Assets: AssetRegistry = {
	-- Background card / plate images (leave blank "" for fallback styled shape)
	Plates = {
		Default = "",
		Shop = "",
		Rebirth = "",
		Index = "",
		Swords = "",
		Roll = "",
		Upgrades = "",
	},

	-- Foreground icon images (leave blank "" for placeholder icon)
	Icons = {
		Shop = "",
		Rebirth = "",
		Index = "",
		Swords = "",
		Roll = "",
		Upgrades = "",
	},
}

return Assets
