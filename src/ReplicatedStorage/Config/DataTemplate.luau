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
	EquippedSword: string, -- "" means nothing equipped (nil can't be stored in a template)
	DiceTier: number, -- highest unlocked Dice tier, 1 = Basic Dice
	LastLogout: number, -- unix seconds, used later for offline Gold
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
}

return DataTemplate
