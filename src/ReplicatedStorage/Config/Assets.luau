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
		Shop = "rbxassetid://114505581952233",
		Rebirth = "rbxassetid://99418679601643",
		Index = "rbxassetid://110329880068770",
		Swords = "",
		Roll = "",
		Upgrades = "",
	},

	-- Foreground icon images (leave blank "" for placeholder icon)
	Icons = {
		Shop = "rbxassetid://114505581952233",
		Rebirth = "rbxassetid://99418679601643",
		Index = "rbxassetid://110329880068770",
		Swords = "",
		Roll = "",
		Upgrades = "",
	},
}

return Assets
