--[[
	Theme - "FIELD COMMAND"
	Forge & Frontline's own visual identity: dark tactical glass, warm
	off-white type, signal-amber accents and corner brackets that echo the
	targeting reticle. Stencil-style display font for headings and numbers,
	Roblox's Builder Sans for readable body text.
]]

local rgb = Color3.fromRGB

local Theme = {}

local function family(name: string): string
	return "rbxasset://fonts/families/" .. name .. ".json"
end

local DISPLAY = family("Sarpanch")
local BODY = family("BuilderSans")
local MONO = family("RobotoMono")

Theme.Font = {
	Display = Font.new(DISPLAY, Enum.FontWeight.Bold),
	DisplayHeavy = Font.new(DISPLAY, Enum.FontWeight.ExtraBold),
	Body = Font.new(BODY, Enum.FontWeight.Medium),
	BodyBold = Font.new(BODY, Enum.FontWeight.Bold),
	BodyHeavy = Font.new(BODY, Enum.FontWeight.ExtraBold),
	Mono = Font.new(MONO, Enum.FontWeight.Bold),
	-- legacy names used by older call sites
	Regular = Font.new(BODY, Enum.FontWeight.Regular),
	Semi = Font.new(BODY, Enum.FontWeight.Medium),
	Bold = Font.new(BODY, Enum.FontWeight.Bold),
}

Theme.Color = {
	-- surfaces (dark → light)
	Ink = rgb(14, 18, 16),
	Panel = rgb(20, 25, 22),
	Raised = rgb(29, 35, 31),
	Hover = rgb(40, 47, 42),
	Inset = rgb(10, 13, 11),
	Line = rgb(62, 71, 63),
	LineSoft = rgb(40, 47, 42),

	-- type
	Text = rgb(236, 232, 216),
	TextSoft = rgb(198, 196, 180),
	Muted = rgb(146, 151, 134),
	Faint = rgb(96, 103, 92),
	OnAccent = rgb(24, 20, 10),

	-- signals
	Accent = rgb(255, 180, 54), -- signal amber
	AccentDim = rgb(120, 86, 28),
	AccentSoft = rgb(52, 41, 20),
	Teal = rgb(84, 214, 186), -- radar
	TealSoft = rgb(22, 52, 46),
	Good = rgb(132, 222, 110),
	GoodSoft = rgb(28, 54, 26),
	Bad = rgb(244, 88, 72),
	BadSoft = rgb(64, 26, 22),
	Info = rgb(104, 174, 255),
	InfoSoft = rgb(22, 40, 64),
	Gold = rgb(255, 206, 84),
	GoldSoft = rgb(66, 52, 18),
	Premium = rgb(190, 136, 255),
	PremiumSoft = rgb(44, 30, 64),

	Civil = rgb(98, 172, 255),
	Military = rgb(244, 98, 78),

	-- HUD
	Hud = rgb(14, 18, 16),
	HudText = rgb(236, 232, 216),
	HudMuted = rgb(146, 151, 134),

	White = rgb(255, 255, 255),
	Black = rgb(0, 0, 0),
	Shadow = rgb(0, 0, 0),

	-- legacy aliases (older controllers)
	Card = rgb(29, 35, 31),
	CardAlt = rgb(20, 25, 22),
	CardStroke = rgb(62, 71, 63),
	PanelStroke = rgb(62, 71, 63),
	Header = rgb(20, 25, 22),
	Track = rgb(40, 47, 42),
	Tab = rgb(29, 35, 31),
	TabActive = rgb(52, 41, 20),
	Time = rgb(104, 174, 255),
	TimeSoft = rgb(22, 40, 64),
	Amber = rgb(255, 180, 54),
	CivilSoft = rgb(22, 40, 64),
	MilitarySoft = rgb(64, 26, 22),
}

Theme.Transparency = {
	Panel = 0.06,
	Glass = 0.14,
}

Theme.Radius = {
	Panel = 6,
	Card = 5,
	Chip = 3,
	Pill = 6,
	Button = 4,
}

Theme.TextSize = {
	Tiny = 11,
	Small = 13,
	Body = 15,
	Title = 20,
	Big = 26,
	Huge = 34,
}

-- Flag colours players can pick for their nation.
Theme.FlagColors = {
	rgb(232, 232, 226), rgb(28, 30, 34), rgb(210, 52, 46), rgb(38, 92, 196),
	rgb(46, 150, 82), rgb(250, 196, 48), rgb(240, 128, 36), rgb(120, 70, 180),
	rgb(64, 176, 196), rgb(140, 32, 46), rgb(26, 54, 110), rgb(120, 132, 70),
}

return Theme
