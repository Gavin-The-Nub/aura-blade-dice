--!strict
-- Default player profile (AI_GUIDE rule 3: content/defaults live in Config).
-- DataService hands this to ProfileStore; fields added here later are filled into
-- existing saved profiles automatically via Profile:Reconcile().

export type PlayerData = {
	Version: number, -- bump + migrate if the shape ever changes incompatibly
	Gold: number,
	Gems: number,
	Rebirths: number,
	OwnedSwords: { any }, -- sword entries are defined by a later feature
	EquippedSword: string, -- uid of equipped sword, or "" for nothing equipped
	DiceTier: number, -- highest unlocked Dice tier, 1 = Basic Dice
	LastLogout: number, -- unix seconds, used later for offline Gold
	AutoSellRules: { [string]: boolean }, -- rarity -> boolean
}

local DataTemplate: PlayerData = {
	Version = 1,
	Gold = 0,
	Gems = 0,
	Rebirths = 0,
	OwnedSwords = {},
	EquippedSword = "",
	DiceTier = 1,
	LastLogout = 0,
	AutoSellRules = {
		Common = false,
		Uncommon = false,
		Rare = false,
		Epic = false,
		Legendary = false,
		Mythic = false,
		Secret = false,
	},
}

return DataTemplate
