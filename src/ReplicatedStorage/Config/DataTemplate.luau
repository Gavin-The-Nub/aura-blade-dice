--!strict
-- Default player profile (AI_GUIDE rule 3: content/defaults live in Config).
-- DataService hands this to ProfileStore; fields added here later are filled into
-- existing saved profiles automatically via Profile:Reconcile().

export type OwnedSwordData = {
	uid: string,
	id: string,
	locked: boolean?,
	grade: string?,
	enchant: string?,
}

export type PlayerData = {
	Version: number, -- bump + migrate if the shape ever changes incompatibly
	Gold: number,
	Gems: number,
	Rebirths: number,
	OwnedSwords: { OwnedSwordData }, -- sword entries with uid, id, and locked flag
	EquippedSword: string, -- uid of equipped sword, or "" for nothing equipped
	DiceTier: number, -- equipped Dice tier, 1 = Basic Dice
	OwnedDice: { [string]: boolean }, -- set of owned tiers ("1", "2", ...)
	LastLogout: number, -- unix seconds, used later for offline Gold
	AutoSellRules: { [string]: boolean }, -- rarity -> boolean
	PlacedSwords: { [string]: string }, -- pedestal slot string ("1".."10") -> sword uid
	PedestalSlots: number, -- active pedestal capacity (default 4)
}

local DataTemplate: PlayerData = {
	Version = 1,
	Gold = 0,
	Gems = 0,
	Rebirths = 0,
	OwnedSwords = {},
	EquippedSword = "",
	DiceTier = 1,
	OwnedDice = {
		["1"] = true,
	},
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
	PlacedSwords = {},
	PedestalSlots = 4,
}

return DataTemplate
