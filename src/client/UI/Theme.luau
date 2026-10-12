--[[
	Theme
	The visual language of the whole UI: soft blue-grey panels, white cards,
	small uppercase labels, bold numbers, green price / blue time chips and a
	dark glass HUD. Change values here to restyle everything.
]]

local rgb = Color3.fromRGB

local Theme = {}

Theme.Font = {
	Regular = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Regular),
	Semi = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.SemiBold),
	Bold = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Bold),
}

Theme.Color = {
	Panel = rgb(234, 240, 246),
	PanelStroke = rgb(206, 216, 228),
	Card = rgb(250, 251, 253),
	CardAlt = rgb(242, 246, 250),
	CardStroke = rgb(220, 228, 238),
	Header = rgb(246, 249, 252),
	Text = rgb(28, 36, 50),
	TextSoft = rgb(70, 80, 96),
	Muted = rgb(112, 122, 138),
	Faint = rgb(160, 170, 184),

	Accent = rgb(58, 124, 228),
	AccentSoft = rgb(222, 234, 250),
	Teal = rgb(52, 166, 196),
	TealSoft = rgb(206, 236, 244),
	Amber = rgb(196, 128, 26),
	Good = rgb(36, 140, 74),
	GoodSoft = rgb(214, 240, 222),
	Time = rgb(56, 104, 182),
	TimeSoft = rgb(220, 232, 248),
	Bad = rgb(204, 52, 52),
	BadSoft = rgb(250, 224, 224),
	Gold = rgb(222, 170, 40),
	GoldSoft = rgb(252, 240, 206),

	Track = rgb(218, 225, 234),
	Tab = rgb(226, 233, 241),
	TabActive = rgb(204, 236, 244),

	Civil = rgb(84, 156, 230),
	CivilSoft = rgb(226, 238, 250),
	Military = rgb(208, 76, 76),
	MilitarySoft = rgb(248, 220, 220),

	Hud = rgb(26, 32, 30),
	HudText = rgb(244, 246, 248),
	HudMuted = rgb(186, 196, 190),
	CashTint = rgb(56, 96, 66),
	PopTint = rgb(58, 74, 92),
	HappyTint = rgb(104, 100, 52),

	White = rgb(255, 255, 255),
	Black = rgb(0, 0, 0),
	Shadow = rgb(20, 28, 40),
}

Theme.Radius = {
	Panel = 10,
	Card = 8,
	Chip = 5,
	Pill = 8,
}

Theme.TextSize = {
	Tiny = 11,
	Small = 13,
	Body = 15,
	Title = 19,
	Big = 24,
	Huge = 32,
}

return Theme
