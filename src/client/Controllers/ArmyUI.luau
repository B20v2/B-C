--[[
	ArmyUI
	Overview of your vehicles: counts per type and location, plus one-click
	Deploy (through the tunnel to the mainland), Recall and Select.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Units = require(Shared.Catalog.Units)
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

local ArmyUI = {}

function ArmyUI.open()
	local win = Modal.open("Army", "Vehicles are built in Military Factories", 640, 520)
	local ic = Icons.tank(40, Color3.fromRGB(110, 130, 80))
	ic.Position = UDim2.fromOffset(6, 4)
	ic.Parent = win.iconHolder

	local mine = UnitView.mine()
	local byType: { [string]: { home: number, mainland: number } } = {}
	for _, m in mine do
		local id = m:GetAttribute("UnitId") :: string
		byType[id] = byType[id] or { home = 0, mainland = 0 }
		if m:GetAttribute("Location") == "mainland" then
			byType[id].mainland += 1
		else
			byType[id].home += 1
		end
	end

	local top = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = win.body }, { Lib.list("x", 8) })
	Lib.text({
		Text = ("%d / %d vehicles"):format(ClientState.get("units") or #mine, ClientState.get("unitCap") or 10),
		FontFace = Theme.Font.Bold,
		TextSize = Theme.TextSize.Title,
		Size = UDim2.new(0, 190, 1, 0),
		LayoutOrder = 1,
		Parent = top,
	})
	local function action(text: string, color: Color3, order: number, fn: () -> ())
		Lib.button({
			Text = text,
			FontFace = Theme.Font.Bold,
			TextColor3 = Color3.new(1, 1, 1),
			BackgroundColor3 = color,
			Size = UDim2.fromOffset(128, 38),
			LayoutOrder = order,
			Parent = top,
			Activated = fn,
		}, { Lib.corner(7) })
	end
	action("Deploy All", Theme.Color.Military, 2, function()
		local res = Net.request("DeployUnits", nil)
		if res.ok then
			Sounds.play("Whoosh")
			Modal.close()
			Hub.call("goWar", "mainland")
		elseif res.err then
			Notifications.show(res.err, "info")
		end
	end)
	action("Recall All", Theme.Color.Time, 3, function()
		local res = Net.request("RecallUnits", nil)
		if res.ok then
			Modal.close()
		elseif res.err then
			Notifications.show(res.err, "info")
		end
	end)
	action("Command", Theme.Color.Good, 4, function()
		Modal.close()
		Hub.call("goWar", "mainland")
		for _, m in UnitView.mine() do
			if m:GetAttribute("Location") == "mainland" then
				UnitView.select(m, true)
			end
		end
	end)

	local list = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		BorderSizePixel = 0,
		Parent = win.body,
	}, { Lib.list("y", 6) })
	local any = false
	for i, def in Units.all() do
		local counts = byType[def.id]
		if counts then
			any = true
			local row = Lib.card({ Size = UDim2.new(1, -6, 0, 56), LayoutOrder = i, Parent = list }, { Lib.pad(8, 14) })
			Lib.text({ Text = def.name, FontFace = Theme.Font.Bold, Size = UDim2.new(0.4, 0, 0, 20), Parent = row })
			Lib.text({ Text = def.role .. " · " .. def.desc, TextSize = Theme.TextSize.Tiny, TextColor3 = Theme.Color.Muted, Position = UDim2.fromOffset(0, 20), Size = UDim2.new(0.6, 0, 0, 16), Parent = row })
			Lib.chip(("%d home"):format(counts.home), Theme.Color.TimeSoft, Theme.Color.Time, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -86, 0.5, 0), Parent = row })
			Lib.chip(("%d mainland"):format(counts.mainland), Theme.Color.BadSoft, Theme.Color.Bad, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Parent = row })
		end
	end
	if not any then
		Lib.text({
			Text = "No vehicles yet. Research Mechanized Forces, build a Military Factory, then queue vehicles in its panel.",
			TextWrapped = true,
			TextColor3 = Theme.Color.Muted,
			Size = UDim2.new(1, 0, 0, 44),
			Parent = list,
		})
	end
end

function ArmyUI.init()
	Hub.openArmy = ArmyUI.open
end

return ArmyUI
