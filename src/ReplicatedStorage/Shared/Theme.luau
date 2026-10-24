--!strict
-- Shared Theme configuration for UI styling.
-- Sword/Aura aesthetic: deep obsidian/slate backgrounds with luminous elemental aura accents.

export type Theme = {
	Colors: {
		BackgroundDark: Color3,
		BackgroundCard: Color3,
		BackgroundHover: Color3,
		PanelBackground: Color3,
		PanelOverlay: Color3,
		
		Border: Color3,
		BorderGlow: Color3,
		BorderSubtle: Color3,
		
		AuraCyan: Color3,
		AuraPurple: Color3,
		AuraGold: Color3,
		AuraCrimson: Color3,
		AuraEmerald: Color3,
		
		TextPrimary: Color3,
		TextSecondary: Color3,
		TextMuted: Color3,
		TextGold: Color3,
		TextCrit: Color3,
		
		ButtonPrimary: Color3,
		ButtonSecondary: Color3,
		ButtonClose: Color3,
	},
	Fonts: {
		Title: Enum.Font,
		Body: Enum.Font,
		Number: Enum.Font,
		Button: Enum.Font,
	},
	Corner: {
		Small: UDim,
		Medium: UDim,
		Large: UDim,
		Round: UDim,
	},
	Stroke: {
		WidthThin: number,
		WidthDefault: number,
		WidthThick: number,
		WidthHeavy: number,
	},
	TextStroke: {
		Color: Color3,
		Thickness: number,
		HeavyThickness: number,
	},
	Transitions: {
		Fast: TweenInfo,
		Pop: TweenInfo,
		Smooth: TweenInfo,
	},
}

local Theme: Theme = {
	Colors = {
		BackgroundDark = Color3.fromRGB(14, 17, 24),
		BackgroundCard = Color3.fromRGB(22, 27, 38),
		BackgroundHover = Color3.fromRGB(32, 40, 56),
		PanelBackground = Color3.fromRGB(18, 22, 32),
		PanelOverlay = Color3.fromRGB(6, 8, 14),

		Border = Color3.fromRGB(48, 58, 80),
		BorderGlow = Color3.fromRGB(0, 229, 255),
		BorderSubtle = Color3.fromRGB(32, 38, 54),

		AuraCyan = Color3.fromRGB(0, 229, 255),      -- Blade edge / spirit
		AuraPurple = Color3.fromRGB(168, 85, 247),    -- Void / enchant
		AuraGold = Color3.fromRGB(255, 204, 0),       -- Wealth / dice luck
		AuraCrimson = Color3.fromRGB(255, 64, 96),    -- Fever / crit
		AuraEmerald = Color3.fromRGB(34, 197, 94),    -- Grades / growth

		TextPrimary = Color3.fromRGB(248, 250, 252),
		TextSecondary = Color3.fromRGB(170, 180, 200),
		TextMuted = Color3.fromRGB(110, 120, 140),
		TextGold = Color3.fromRGB(255, 220, 75),
		TextCrit = Color3.fromRGB(255, 170, 0),

		ButtonPrimary = Color3.fromRGB(30, 41, 64),
		ButtonSecondary = Color3.fromRGB(22, 28, 42),
		ButtonClose = Color3.fromRGB(220, 53, 69),
	},
	Fonts = {
		Title = Enum.Font.GothamBold,
		Body = Enum.Font.GothamMedium,
		Number = Enum.Font.FredokaOne,
		Button = Enum.Font.GothamBold,
	},
	Corner = {
		Small = UDim.new(0, 6),
		Medium = UDim.new(0, 10),
		Large = UDim.new(0, 16),
		Round = UDim.new(1, 0),
	},
	Stroke = {
		WidthThin = 1,
		WidthDefault = 1.5,
		WidthThick = 2.5,
		WidthHeavy = 3.5,
	},
	TextStroke = {
		Color = Color3.fromRGB(8, 10, 16),
		Thickness = 2,
		HeavyThickness = 3.5,
	},
	Transitions = {
		Fast = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Pop = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		Smooth = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	},
}

return Theme
