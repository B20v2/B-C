--[[
	ArmyUI
	Your forces: unit-type cards with 3D previews, roles, stats and how many
	are at home vs. on the mainland, plus DEPLOY ALL / RECALL ALL / COMMAND.
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
}

function ArmyUI.open()
	local win = Modal.open("Army Command", "Build vehicles in Military Factories · deploy them to the mainland", 980, 620)
	local ic = Icons.tank(36, Color3.fromRGB(170, 200, 130))
	ic.Position = UDim2.fromOffset(8, 6)
	ic.Parent = win.iconHolder

	local mine = UnitView.mine()
	local byType: { [string]: { home: number, mainland: number } } = {}
	local deployed = 0
	for _, m in mine do
		local id = m:GetAttribute("UnitId") :: string
		byType[id] = byType[id] or { home = 0, mainland = 0 }
		if m:GetAttribute("Location") == "mainland" then
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
	stat("Vehicles", ("%d / %d"):format(ClientState.get("units") or #mine, ClientState.get("unitCap") or 10), C.Text, 1)
	stat("On the mainland", tostring(deployed), C.Military, 2)
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
			if m:GetAttribute("Location") == "mainland" then
				UnitView.select(m, true)
			end
		end
	end)

	local list = Lib.scroll({ Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 1, -76), Parent = win.body })
	New("UIGridLayout", { CellSize = UDim2.new(1 / 3, -8, 0, 214), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	local access = { researched = ClientState.get("researched") or {}, passes = ClientState.get("passes") or {} }
	for i, def in Units.all() do
		local counts = byType[def.id]
		local unlocked = Unlocks.check(def, access)
		if counts or unlocked then
			local card = Lib.card({ Name = def.id, LayoutOrder = counts and i or 100 + i, Parent = list }, { Lib.pad(8) })
			local art = Lib.inset({ Size = UDim2.new(1, 0, 0, 92), Parent = card })
			New("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(38, 48, 40), C.Ink), Rotation = 90, Parent = art })
			Lib.viewport(ModelBuilder.unit(def), { Parent = art }, 35)
			local roleCol = ROLE_COLORS[def.role] or C.Text
			Lib.chip(string.upper(def.role), roleCol:Lerp(C.Ink, 0.75), roleCol, { Position = UDim2.fromOffset(6, 6), Parent = art })
			Lib.display({ Text = string.upper(def.name), TextSize = 16, Position = UDim2.fromOffset(2, 98), Size = UDim2.new(1, -4, 0, 20), Parent = card })
			Lib.text({
				Text = ("HP %d · DMG %d/s · RNG %d · CAP %d"):format(def.hp, def.dps, def.range, def.capture),
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
	if #mine == 0 then
		Lib.text({
			Name = "Empty",
			Text = "No vehicles yet. Research Mechanized Forces, build a Military Factory, then queue vehicles from its panel.",
			TextWrapped = true,
			TextColor3 = C.Muted,
			LayoutOrder = 999,
			Parent = list,
		})
	end
end

function ArmyUI.init()
	Hub.openArmy = ArmyUI.open
end

return ArmyUI
