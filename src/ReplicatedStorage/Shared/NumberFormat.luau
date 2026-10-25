--!strict
-- Formats big numbers for display, e.g. 1500 -> "1.5K", 5e24 -> "5Sp".
-- Suffix ladder comes from the GDD (Dice/Rebirth cost tables).

local NumberFormat = {}

-- Ordered smallest to largest.
local SUFFIXES: { { name: string, value: number } } = {
	{ name = "K", value = 1e3 },
	{ name = "M", value = 1e6 },
	{ name = "B", value = 1e9 },
	{ name = "T", value = 1e12 },
	{ name = "Qa", value = 1e15 },
	{ name = "Qi", value = 1e18 },
	{ name = "Sx", value = 1e21 },
	{ name = "Sp", value = 1e24 },
	{ name = "Oc", value = 1e27 },
}

local MAX_DECIMALS = 2

-- Truncate (not round) so 999,999 shows as 999.99K and never as "1000K".
-- The tiny epsilon stops float error turning 1.5 into 1.49.
local function trimmed(scaled: number): string
	local factor = 10 ^ MAX_DECIMALS
	local truncated = math.floor(scaled * factor + 1e-6) / factor
	local text = string.format("%." .. MAX_DECIMALS .. "f", truncated)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

function NumberFormat.format(value: number): string
	if value ~= value then
		return "0" -- NaN: never show it to the player
	end
	if value < 0 then
		return "-" .. NumberFormat.format(-value)
	end
	if value == math.huge then
		return "inf"
	end
	if value < 1000 then
		return tostring(math.floor(value))
	end

	local chosen = SUFFIXES[1]
	for _, suffix in SUFFIXES do
		if value >= suffix.value then
			chosen = suffix
		else
			break
		end
	end
	return trimmed(value / chosen.value) .. chosen.name
end

return NumberFormat
