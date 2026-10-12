--[[
	ArmyUI
	Your forces, grouped into infantry, vehicles and aircraft: unit cards with
	3D previews, roles, stats and how many are at home vs. out at the front,
	your FOB (health, supplies, airlift), plus DEPLOY ALL / RECALL ALL /
	COMMAND.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Units = require(Shared.Catalog.Units)
local ModelBuilder = require(Shared.ModelBuilder)
local Unlocks = require(Shared.Util.Unlocks)
local Net = require(Shared.Net)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Hub = require(Client.Hub)
local Lib = require(Client.UI.Lib)
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)
local Modal = require(script.Parent.Modal)
local Notifications = require(script.Parent.Notifications)
local Sounds = require(script.Parent.Sounds)
local UnitView = require(script.Parent.UnitView)

local New = Lib.New
local C = Theme.Color

local ArmyUI = {}

local ROLE_COLORS = {
	IFV = C.Info,
	Tank = C.Gold,
	Artillery = C.Military,
	["Anti-Air"] = C.Teal,
	Capture = C.Good,
	Transport = C.Good,
	Infantry = C.Accent,
	["Anti-Tank"] = C.Bad,
	Recon = C.Teal,
	["Air Assault"] = C.Info,
	["Heavy Lift"] = C.Gold,
}

local GROUPS = {
	{ class = "infantry", title = "Infantry", sub = "trained at a Barracks" },
	{ class = "vehicle", title = "Vehicles", sub = "built in Military Factories" },
	{ class = "air", title = "Aircraft", sub = "built at a Helipad" },
}

function ArmyUI.open()
	local win = Modal.open("Army Command", "Infantry, vehicles and helicopters · drive over your bridge or fly to the front", 1180, 640)
	local ic = Icons.tank(36, Color3.fromRGB(170, 200, 130))
	ic.Position = UDim2.fromOffset(8, 6)
	ic.Parent = win.iconHolder

	local mine = UnitView.mine()
	local byType: { [string]: { home: number, mainland: number } } = {}
	local deployed = 0
	for _, m in mine do
		local id = m:GetAttribute("UnitId") :: string
		byType[id] = byType[id] or { home = 0, mainland = 0 }
		if (m:GetAttribute("Location") or "home") ~= "home" then
			byType[id].mainland += 1
			deployed += 1
		else
			byType[id].home += 1
		end
	end

	local top = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 64), Parent = win.body }, { Lib.list("x", 8, nil, Enum.VerticalAlignment.Center) })
	local function stat(caption: string, value: string, color: Color3, order: number)
		local card = Lib.card({ Size = UDim2.fromOffset(170, 64), LayoutOrder = order, Parent = top }, { Lib.pad(9, 12) })
		Lib.caption(caption, { Parent = card })
		Lib.display({ Text = value, TextSize = 22, TextColor3 = color, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 26), Parent = card })
	end
	stat("Units", ("%d / %d"):format(ClientState.get("units") or #mine, ClientState.get("unitCap") or 10), C.Text, 1)
	stat("Out at the front", tostring(deployed), C.Military, 2)
	local function action(name: string, text: string, variant: string, order: number, fn: () -> ())
		Lib.button({ Name = name, Variant = variant, Text = text, TextSize = 13, Size = UDim2.fromOffset(150, 44), LayoutOrder = order, Parent = top, Activated = fn })
	end
	action("DeployAll", "DEPLOY ALL", "primary", 3, function()
		local res = Net.request("DeployUnits", nil)
		if res.ok then
			Sounds.play("Whoosh")
			Modal.close()
			Hub.call("goWar", "mainland")
		elseif res.err then
			Notifications.show(res.err, "info")
		end
	end)
	action("RecallAll", "RECALL ALL", "secondary", 4, function()
		local res = Net.request("RecallUnits", nil)
		if res.ok then
			Modal.close()
		elseif res.err then
			Notifications.show(res.err, "info")
		end
	end)
	action("Command", "COMMAND", "secondary", 5, function()
		Modal.close()
		Hub.call("goWar", "mainland")
		for _, m in UnitView.mine() do
			if (m:GetAttribute("Location") or "home") ~= "home" then
				UnitView.select(m, true)
			end
		end
	end)

	-- FOB status
	local fobs = ClientState.get("fobs") or {}
	local fobCard = Lib.card({ Name = "FobCard", Size = UDim2.fromOffset(200, 64), LayoutOrder = 6, Parent = top }, { Lib.pad(8, 10) })
	if #fobs > 0 then
		local f = fobs[1]
		Lib.caption(("FOB · %d / %d supplies"):format(f.supplies, f.cap), { Parent = fobCard })
		local hp = Lib.progress({ Segments = 10, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 5), Parent = fobCard })
		hp.set(f.hp / f.maxHp, C.Good)
		local sup = Lib.progress({ Position = UDim2.fromOffset(0, 27), Size = UDim2.new(1, 0, 0, 4), Parent = fobCard })
		sup.set(f.supplies / f.cap, C.Gold)
		Lib.button({
			Name = "AirliftAll",
			Variant = "primary",
			Text = "AIRLIFT TO FOB",
			TextSize = 11,
			Position = UDim2.fromOffset(0, 34),
			Size = UDim2.new(1, 0, 0, 22),
			Parent = fobCard,
			Activated = function()
				local helis = {}
				for _, m in UnitView.mine() do
					if m:GetAttribute("Class") == "air" and (m:GetAttribute("Location") or "home") == "home" then
						table.insert(helis, m:GetAttribute("Uid"))
					end
				end
				local res = Net.request("UnitOrder", "airlift", helis, "fob")
				if res.ok then
					Sounds.play("Whoosh")
					Notifications.show(("%d helicopters loading up for the FOB"):format(res.count or 0), "good")
				elseif res.err then
					Notifications.show(#helis == 0 and "No helicopters at home - build a Helipad" or res.err, "info")
				end
			end,
		})
	else
		Lib.caption("No FOB yet", { Parent = fobCard })
		Lib.text({
			Text = "Drive a Logistics Truck or fly a Chinook to the battlefield, then SET UP FOB.",
			TextSize = 11,
			TextWrapped = true,
			TextColor3 = C.Muted,
			Position = UDim2.fromOffset(0, 16),
			Size = UDim2.new(1, 0, 0, 30),
			Parent = fobCard,
		})
	end

	local list = Lib.scroll({ Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 1, -76), Parent = win.body }, { Lib.list("y", 10) })
	local access = { researched = ClientState.get("researched") or {}, passes = ClientState.get("passes") or {} }
	for gi, group in GROUPS do
		local header = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 22), LayoutOrder = gi * 2 - 1, Parent = list })
		Lib.display({ Text = string.upper(group.title), TextSize = 15, TextColor3 = C.Accent, Size = UDim2.new(0.5, 0, 1, 0), Parent = header })
		Lib.text({ Text = group.sub, TextSize = 12, TextColor3 = C.Muted, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.5, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, Parent = header })
		local grid = New("Frame", {
			Name = "Group_" .. group.class,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = gi * 2,
			Parent = list,
		}, { Lib.grid(UDim2.new(1 / 3, -6, 0, 214), 8) })
		local shown = 0
		for i, def in Units.all() do
			local counts = byType[def.id]
			local unlocked = Unlocks.check(def, access)
			if def.class == group.class and (counts or unlocked) then
				shown += 1
				local card = Lib.card({ Name = def.id, LayoutOrder = counts and i or 100 + i, Parent = grid }, { Lib.pad(8) })
				local art = Lib.inset({ Size = UDim2.new(1, 0, 0, 92), Parent = card })
				New("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(38, 48, 40), C.Ink), Rotation = 90, Parent = art })
				Lib.viewport(ModelBuilder.unit(def), { Parent = art }, 35)
				local roleCol = ROLE_COLORS[def.role] or C.Text
				Lib.chip(string.upper(def.role), roleCol:Lerp(C.Ink, 0.75), roleCol, { Position = UDim2.fromOffset(6, 6), Parent = art })
				Lib.display({ Text = string.upper(def.name), TextSize = 16, Position = UDim2.fromOffset(2, 98), Size = UDim2.new(1, -4, 0, 20), Parent = card })
				local carry = def.cargo and ("  ·  CARRIES %d SQ%s%s"):format(def.cargo.squads or 0, (def.cargo.supplies or 0) > 0 and (" + " .. def.cargo.supplies .. " SUP") or "", (def.cargo.vehicles or 0) > 0 and " + VEHICLE" or "") or ""
				Lib.text({
					Text = ("HP %d · DMG %d/s · RNG %d%s"):format(def.hp, def.dps, def.range, carry),
					FontFace = Theme.Font.Mono,
					TextSize = 10,
					TextColor3 = C.Muted,
					Position = UDim2.fromOffset(2, 120),
					Size = UDim2.new(1, -4, 0, 14),
					Parent = card,
				})
				Lib.text({ Text = def.desc, TextSize = 12, TextColor3 = C.TextSoft, TextWrapped = true, Position = UDim2.fromOffset(2, 136), Size = UDim2.new(1, -4, 0, 30), TextYAlignment = Enum.TextYAlignment.Top, Parent = card })
				local chips = New("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 2, 1, 0), Size = UDim2.new(1, -4, 0, 20), Parent = card }, { Lib.list("x", 6) })
				if counts then
					Lib.chip(("%d HOME"):format(counts.home), C.InfoSoft, C.Info, { Parent = chips })
					Lib.chip(("%d DEPLOYED"):format(counts.mainland), C.BadSoft, C.Military, { Parent = chips })
				else
					Lib.chip("NONE BUILT", C.Inset, C.Faint, { Parent = chips })
				end
			end
		end
		if shown == 0 then
			grid.Visible = false
			header.Visible = false
		end
	end
	if #mine == 0 then
		Lib.text({
			Name = "Empty",
			Text = "No units yet. Build a Barracks for infantry, a Military Factory for vehicles, or a Helipad for helicopters, then queue them from the building's panel.",
			TextWrapped = true,
			TextColor3 = C.Muted,
			Size = UDim2.new(1, -8, 0, 40),
			LayoutOrder = 999,
			Parent = list,
		})
	end
end

function ArmyUI.init()
	Hub.openArmy = ArmyUI.open
end

return ArmyUI
