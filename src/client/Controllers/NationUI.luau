--[[
	NationUI
	"Found your nation": name + flag designer with a live preview on a
	flagpole. Opens automatically for brand-new commanders and from the flag
	in the HUD badge. Also shows the RANK UP banner when the server promotes
	the nation.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Flag = require(Shared.Util.Flag)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Hub = require(Client.Hub)
local Lib = require(Client.UI.Lib)
local Theme = require(Client.UI.Theme)
local Modal = require(script.Parent.Modal)
local Notifications = require(script.Parent.Notifications)
local Sounds = require(script.Parent.Sounds)

local New = Lib.New
local C = Theme.Color

local NationUI = {}

local player = Players.LocalPlayer
local bannerLayer: GuiObject
local prompted = false

local ADJECTIVES = { "Iron", "Free", "Northern", "Southern", "Azure", "Crimson", "Golden", "Grand", "Silver", "United", "Eastern", "Western", "High", "New", "Royal", "Emerald" }
local NOUNS = { "Republic", "Union", "Federation", "Dominion", "Commonwealth", "Coalition", "Empire", "Alliance", "Territory", "Protectorate", "League", "Realm" }

function NationUI.randomName(rng: Random?): string
	local r = rng or Random.new()
	for _ = 1, 10 do
		local name = ADJECTIVES[r:NextInteger(1, #ADJECTIVES)] .. " " .. NOUNS[r:NextInteger(1, #NOUNS)]
		if #name <= Config.NationNameMax then
			return name
		end
	end
	return "Free Republic"
end

local function randomFlag(r: Random): Flag.Data
	local a = r:NextInteger(1, #Flag.Colors)
	local b = r:NextInteger(1, #Flag.Colors - 1)
	if b >= a then
		b += 1
	end
	local c = r:NextInteger(1, #Flag.Colors)
	return { p = r:NextInteger(1, #Flag.Patterns), c = { a, b, c }, e = r:NextInteger(0, #Flag.Emblems - 1) }
end

function NationUI.open()
	local current = ClientState.get("nation")
	local founded = type(current) == "table" and current.name ~= nil
	local rng = Random.new()
	local data: Flag.Data = founded and Flag.decode(current.flag) or randomFlag(rng)
	data = { p = data.p, c = { data.c[1], data.c[2], data.c[3] }, e = data.e }
	local band = 1

	local win = Modal.open(
		founded and "Nation Identity" or "Found Your Nation",
		"Name it and raise a flag. Rivals see both on the war map and your border sign.",
		900,
		580
	)

	-- left: preview on a pole
	local stage = Lib.inset({ Name = "Preview", Size = UDim2.new(0, 330, 1, 0), Parent = win.body })
	New("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(40, 58, 66), C.Ink), Rotation = 90, Parent = stage })
	New("Frame", { BackgroundColor3 = Color3.fromRGB(200, 204, 206), BorderSizePixel = 0, Position = UDim2.fromOffset(46, 40), Size = UDim2.fromOffset(5, 300), Parent = stage })
	New("Frame", { BackgroundColor3 = C.Accent, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(48, 38), Size = UDim2.fromOffset(12, 12), Parent = stage }, { Lib.round() })
	local flagFrame = New("Frame", { Name = "Flag", BackgroundTransparency = 1, Position = UDim2.fromOffset(51, 48), Size = UDim2.fromOffset(240, 160), Parent = stage }, { Lib.stroke(Color3.new(0, 0, 0), 1, 0.6) })
	local nameLabel = Lib.display({
		Name = "NamePreview",
		Text = "",
		TextSize = 24,
		TextWrapped = true,
		Position = UDim2.fromOffset(20, 360),
		Size = UDim2.new(1, -40, 0, 56),
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = stage,
	})
	Lib.caption("Est. by commander " .. player.DisplayName, { TextColor3 = C.Accent, Position = UDim2.fromOffset(20, 420), Size = UDim2.new(1, -40, 0, 14), Parent = stage })

	-- right: controls
	local panel = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(350, 0), Size = UDim2.new(1, -350, 1, 0), Parent = win.body })
	Lib.caption("Nation name", { Parent = panel })
	local box = Lib.textbox({
		Name = "NameBox",
		Text = founded and current.name or NationUI.randomName(rng),
		PlaceholderText = "e.g. Iron Republic",
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, -120, 0, 40),
		Parent = panel,
	})
	Lib.button({
		Name = "Randomize",
		Variant = "secondary",
		Text = "RANDOM",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 18),
		Size = UDim2.fromOffset(110, 40),
		Parent = panel,
		Activated = function()
			box.Text = NationUI.randomName(rng)
		end,
	})

	local patternRow, colorRow, emblemRow, bandTabs
	local errorLabel: TextLabel

	local function redraw()
		Lib.clear(flagFrame)
		Flag.draw(flagFrame, data)
		nameLabel.Text = string.upper(box.Text ~= "" and box.Text or "Unnamed nation")
		for i, btn in patternRow:GetChildren() do
			if btn:IsA("GuiButton") then
				local idx = btn:GetAttribute("Index") :: number
				local holder = btn:FindFirstChild("Mini") :: Frame
				Lib.clear(holder)
				Flag.draw(holder, { p = idx, c = data.c, e = 0 })
				local st = btn:FindFirstChildOfClass("UIStroke") :: UIStroke
				st.Color = idx == data.p and C.Accent or C.Line
				st.Thickness = idx == data.p and 2 or 1
			end
			local _ = i
		end
		for _, btn in colorRow:GetChildren() do
			if btn:IsA("GuiButton") then
				local st = btn:FindFirstChildOfClass("UIStroke") :: UIStroke
				local sel = btn:GetAttribute("Index") == data.c[band]
				st.Color = sel and C.Accent or C.Line
				st.Thickness = sel and 3 or 1
			end
		end
		for _, btn in emblemRow:GetChildren() do
			if btn:IsA("GuiButton") then
				local st = btn:FindFirstChildOfClass("UIStroke") :: UIStroke
				local sel = btn:GetAttribute("Index") == data.e
				st.Color = sel and C.Accent or C.Line
				st.Thickness = sel and 2 or 1
			end
		end
		for _, btn in bandTabs:GetChildren() do
			if btn:IsA("GuiButton") then
				Lib.setButtonColor(btn, btn:GetAttribute("Index") == band and C.AccentSoft or C.Raised)
			end
		end
	end

	Lib.caption("Pattern", { Position = UDim2.fromOffset(0, 74), Parent = panel })
	patternRow = New("Frame", { Name = "Patterns", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 92), Size = UDim2.new(1, 0, 0, 52), Parent = panel }, { Lib.list("x", 8) })
	for i, name in Flag.Patterns do
		local btn = Lib.button({
			Name = name,
			BackgroundColor3 = C.Raised,
			Size = UDim2.fromOffset(72, 52),
			LayoutOrder = i,
			Parent = patternRow,
			Activated = function()
				data.p = i
				Sounds.play("Click", 1.2)
				redraw()
			end,
		}, { Lib.corner(3), Lib.stroke(C.Line, 1, 0) })
		btn:SetAttribute("Index", i)
		New("Frame", { Name = "Mini", BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12), Parent = btn })
	end

	Lib.caption("Colours", { Position = UDim2.fromOffset(0, 160), Parent = panel })
	bandTabs = New("Frame", { Name = "Bands", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 178), Size = UDim2.new(1, 0, 0, 30), Parent = panel }, { Lib.list("x", 6) })
	for i, label in { "PRIMARY", "SECOND", "ACCENT" } do
		local tab = Lib.button({
			Name = "Band" .. i,
			Text = label,
			FontFace = Theme.Font.Display,
			TextSize = 12,
			BackgroundColor3 = C.Raised,
			Size = UDim2.fromOffset(110, 30),
			LayoutOrder = i,
			Parent = bandTabs,
			Activated = function()
				band = i
				redraw()
			end,
		}, { Lib.corner(3), Lib.stroke(C.Line, 1, 0.3) })
		tab:SetAttribute("Index", i)
	end
	colorRow = New("Frame", { Name = "Colors", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 216), Size = UDim2.new(1, 0, 0, 40), Parent = panel }, { Lib.list("x", 6) })
	for i, col in Flag.Colors do
		local sw = Lib.button({
			Name = "Color" .. i,
			BackgroundColor3 = col,
			Size = UDim2.fromOffset(34, 34),
			LayoutOrder = i,
			Parent = colorRow,
			Activated = function()
				data.c[band] = i
				redraw()
			end,
		}, { Lib.corner(3), Lib.stroke(C.Line, 1, 0) })
		sw:SetAttribute("Index", i)
	end

	Lib.caption("Emblem", { Position = UDim2.fromOffset(0, 272), Parent = panel })
	emblemRow = New("Frame", { Name = "Emblems", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 290), Size = UDim2.new(1, 0, 0, 40), Parent = panel }, { Lib.list("x", 8) })
	for i, name in Flag.Emblems do
		local btn = Lib.button({
			Name = name,
			Text = string.upper(name),
			FontFace = Theme.Font.Display,
			TextSize = 12,
			BackgroundColor3 = C.Raised,
			Size = UDim2.fromOffset(84, 36),
			LayoutOrder = i,
			Parent = emblemRow,
			Activated = function()
				data.e = i - 1
				redraw()
			end,
		}, { Lib.corner(3), Lib.stroke(C.Line, 1, 0) })
		btn:SetAttribute("Index", i - 1)
	end

	errorLabel = Lib.text({
		Name = "Error",
		Text = "",
		TextColor3 = C.Bad,
		TextSize = 13,
		FontFace = Theme.Font.BodyBold,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -62),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = panel,
	})
	Lib.hazard({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -54), Size = UDim2.new(1, 0, 0, 4), BackgroundTransparency = 0.3, Parent = panel }, C.Accent, C.Panel, 9)
	local busy = false
	Lib.button({
		Name = "Found",
		Variant = "primary",
		Text = founded and "UPDATE NATION" or "FOUND NATION",
		TextSize = 16,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(220, 46),
		Parent = panel,
		Activated = function()
			if busy then
				return
			end
			busy = true
			errorLabel.Text = ""
			local res = Net.request("SetNation", box.Text, Flag.encode(data))
			busy = false
			if res.ok then
				Sounds.play("Success")
				Modal.close()
				if not founded then
					Notifications.show(("The nation of %s is born. Long may it stand."):format(res.name or box.Text), "good")
				end
			else
				errorLabel.Text = res.err or "Something went wrong"
				Sounds.play("Error")
			end
		end,
	})
	if not founded then
		Lib.text({
			Text = "You can change this any time from the flag in the top-left.",
			TextSize = 12,
			TextColor3 = C.Muted,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -14),
			Size = UDim2.new(1, -230, 0, 18),
			Parent = panel,
		})
	end

	box:GetPropertyChangedSignal("Text"):Connect(function()
		if #box.Text > Config.NationNameMax then
			box.Text = string.sub(box.Text, 1, Config.NationNameMax)
		end
		nameLabel.Text = string.upper(box.Text ~= "" and box.Text or "Unnamed nation")
	end)
	redraw()
end

---------------------------------------------------------------------------
-- Rank-up banner
---------------------------------------------------------------------------
function NationUI.showRankUp(level: number)
	local r = Config.Ranks[level]
	if not r or not bannerLayer then
		return
	end
	Sounds.play("Success")
	local banner = Lib.panel({
		Name = "RankUp",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -140),
		Size = UDim2.fromOffset(520, 118),
		BackgroundTransparency = 0.02,
		Parent = bannerLayer,
	}, { Lib.pad(14, 20) })
	Lib.brackets(banner, C.Accent, 14, 2, 4)
	Lib.hazard({ Position = UDim2.new(0, -20, 0, -14), Size = UDim2.new(1, 40, 0, 6), Parent = banner }, C.Accent, C.Panel, 9)
	Lib.caption(("Rank up · tier %d of %d"):format(level, #Config.Ranks), { TextColor3 = C.Accent, Position = UDim2.fromOffset(0, 4), Parent = banner })
	Lib.display({ Text = string.upper(r.name), TextSize = 38, Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 44), Parent = banner })
	local nxt = Config.Ranks[level + 1]
	Lib.text({
		Text = ("Treasury +%s%s"):format(Format.cash(r.reward), nxt and ("  ·  next: %s at %s power"):format(nxt.name, Format.short(nxt.power)) or "  ·  the top of the world"),
		TextSize = 13,
		TextColor3 = C.TextSoft,
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = banner,
	})
	Lib.tween(banner, 0.45, { Position = UDim2.new(0.5, 0, 0, 120) }, Enum.EasingStyle.Back)
	task.delay(5, function()
		Lib.tween(banner, 0.35, { Position = UDim2.new(0.5, 0, 0, -140) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.4)
		banner:Destroy()
	end)
end

function NationUI.init(layer: GuiObject)
	bannerLayer = layer
	Hub.openNation = NationUI.open
	Hub.showRankUp = NationUI.showRankUp
	-- brand-new commanders found their nation first
	ClientState.on("nation", function(nation)
		if nation == false and not prompted then
			prompted = true
			task.delay(1.5, function()
				if ClientState.get("nation") == false and not Modal.isOpen() then
					NationUI.open()
				end
			end)
		end
	end)
end

return NationUI
