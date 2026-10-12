--[[
	BuildingPanel - the Inspector
	Click any of your buildings: a panel docks on the right (the world stays
	visible) with a live 3D header, status, a 2x2 stat grid, activity and a
	building-specific section (fuel destinations, production queue, crops to
	plant and harvest, launcher readiness, billboard text), then Repair /
	Move / Demolish.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Buildings = require(Shared.Catalog.Buildings)
local Weapons = require(Shared.Catalog.Weapons)
local Units = require(Shared.Catalog.Units)
local Crops = require(Shared.Catalog.Crops)
local ModelBuilder = require(Shared.ModelBuilder)
local Unlocks = require(Shared.Util.Unlocks)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Hub = require(Client.Hub)
local Lib = require(Client.UI.Lib)
local Theme = require(Client.UI.Theme)
local Modal = require(script.Parent.Modal)
local Notifications = require(script.Parent.Notifications)
local Placement = require(script.Parent.Placement)
local Sounds = require(script.Parent.Sounds)

local New = Lib.New
local C = Theme.Color

local BuildingPanel = {}

type StatCard = { value: TextLabel, sub: TextLabel, caption: TextLabel, bar: Lib.Progress }

local function statCard(parent: Instance, order: number): StatCard
	local card = Lib.card({ LayoutOrder = order, Parent = parent }, { Lib.pad(9, 11) })
	local caption = Lib.caption("", { Parent = card })
	local value = Lib.display({ Text = "-", TextSize = 20, Position = UDim2.fromOffset(0, 15), Size = UDim2.new(1, 0, 0, 24), Parent = card })
	local sub = Lib.text({ Text = "", TextSize = 11, TextColor3 = C.Muted, FontFace = Theme.Font.BodyBold, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 13), Parent = card })
	local bar = Lib.progress({ Segments = 8, Position = UDim2.new(0, 0, 1, -5), Size = UDim2.new(1, 0, 0, 5), Parent = card })
	return { value = value, sub = sub, caption = caption, bar = bar }
end

local function setStat(c: StatCard, caption: string, value: string, sub: string, frac: number?, color: Color3?)
	c.caption.Text = string.upper(caption)
	c.value.Text = value
	c.sub.Text = sub
	c.bar.frame.Visible = frac ~= nil
	if frac then
		c.bar.set(frac, color)
	end
end

local function weaponForFamily(family: string)
	for _, w in Weapons.all() do
		if w.family == family then
			return w
		end
	end
	return nil
end

local function plotFolder(): Folder?
	local idx = ClientState.get("plot")
	local homeland = workspace:FindFirstChild("Homeland")
	local plot = idx and homeland and homeland:FindFirstChild("Plot_" .. idx)
	return plot and plot:FindFirstChild("Buildings") :: Folder? or nil
end

-- Fuel consumers in your nation, numbered per type ("Large Military Factory #2").
local function consumers(): { { uid: number, name: string, model: Model, cap: number } }
	local out = {}
	local folder = plotFolder()
	if not folder then
		return out
	end
	local models = {}
	for _, m in folder:GetChildren() do
		local def = Buildings.get(m:GetAttribute("BuildingId") :: string)
		if def and def.fuelCap then
			table.insert(models, { m = m, def = def })
		end
	end
	table.sort(models, function(a, b)
		return (a.m:GetAttribute("Uid") :: number) < (b.m:GetAttribute("Uid") :: number)
	end)
	local counts = {}
	for _, e in models do
		counts[e.def.id] = (counts[e.def.id] or 0) + 1
		table.insert(out, {
			uid = e.m:GetAttribute("Uid") :: number,
			name = ("%s #%d"):format(e.def.name, counts[e.def.id]),
			model = e.m,
			cap = e.def.fuelCap,
		})
	end
	return out
end

local function statusColor(status: string, model: Model): Color3
	if model:GetAttribute("Damaged") then
		return C.Bad
	elseif status:find("Not Enough") or status:find("No Road") or status:find("Waiting") or status:find("Full") then
		return C.Gold
	elseif model:GetAttribute("FinishAt") then
		return C.Info
	end
	return C.Good
end

local function section(parent: Instance, title: string, order: number): (Frame, TextLabel)
	local s = Lib.card({ LayoutOrder = order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = parent }, { Lib.pad(10, 12), Lib.list("y", 6) })
	local t = Lib.caption(title, { TextColor3 = C.Accent, LayoutOrder = 0, Parent = s })
	return s, t
end

function BuildingPanel.open(model: Model)
	local def = Buildings.get(model:GetAttribute("BuildingId") :: string)
	if not def then
		return
	end
	local uid = model:GetAttribute("Uid") :: number
	local win = Modal.openSide(def.name, ("%s · %s · %dx%d"):format(def.category == "Civilian" and "CIVIL" or "MILITARY", string.upper(def.tab), def.size[1], def.size[2]), 440)
	Sounds.play("Open")
	Lib.viewport(ModelBuilder.building(def), { Parent = win.iconHolder }, 40, 30)

	local scroll = Lib.scroll({ Size = UDim2.new(1, 0, 1, -54), Parent = win.body }, { Lib.list("y", 8), Lib.pad(0, 6, 6, 0) })

	-- status line
	local statusRow = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, Parent = scroll })
	local statusDot = New("Frame", { BackgroundColor3 = C.Good, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0), Size = UDim2.fromOffset(8, 8), Parent = statusRow }, { Lib.round() })
	local statusText = Lib.display({ Text = "", TextSize = 13, Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -18, 1, 0), Parent = statusRow })

	-- stat grid
	local grid = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 2 * 70 + 8), LayoutOrder = 2, Parent = scroll }, { Lib.grid(UDim2.new(0.5, -4, 0, 70), 8) })
	local stats = { statCard(grid, 1), statCard(grid, 2), statCard(grid, 3), statCard(grid, 4) }

	-- activity
	local activity = Lib.card({ LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = scroll }, { Lib.pad(10, 12), Lib.list("y", 3) })
	Lib.caption("Activity", { TextColor3 = C.Accent, LayoutOrder = 0, Parent = activity })
	local doingDesc = Lib.text({
		Text = def.desc,
		TextSize = 13,
		TextColor3 = C.TextSoft,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextTruncate = Enum.TextTruncate.None,
		LayoutOrder = 1,
		Parent = activity,
	})

	-- actions (fixed at the bottom)
	local actions = New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 44),
		Parent = win.body,
	}, { Lib.list("x", 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
	local repairBtn = Lib.button({
		Name = "Repair",
		Variant = "primary",
		Text = "REPAIR",
		TextSize = 13,
		Size = UDim2.fromOffset(160, 40),
		LayoutOrder = 1,
		Visible = false,
		Parent = actions,
		Activated = function()
			local res = Net.request("RepairBuilding", uid)
			if res.ok then
				Sounds.play("Success")
			elseif res.err then
				Notifications.show(res.err, "bad")
			end
		end,
	})
	Lib.button({
		Name = "Move",
		Variant = "secondary",
		Text = "MOVE",
		TextSize = 13,
		Size = UDim2.fromOffset(96, 40),
		LayoutOrder = 2,
		Parent = actions,
		Activated = function()
			Modal.close()
			Hub.call("openBuild")
			Placement.beginMove(model)
		end,
	})
	local confirmDelete = false
	local deleteBtn: TextButton
	deleteBtn = Lib.button({
		Name = "Demolish",
		Variant = "danger",
		Text = "DEMOLISH",
		TextSize = 13,
		Size = UDim2.fromOffset(130, 40),
		LayoutOrder = 3,
		Parent = actions,
		Activated = function()
			if not confirmDelete then
				confirmDelete = true
				deleteBtn.Text = "CONFIRM?"
				task.delay(3, function()
					confirmDelete = false
					if deleteBtn.Parent then
						deleteBtn.Text = "DEMOLISH"
					end
				end)
				return
			end
			local res = Net.request("DeleteBuilding", uid)
			if res.ok then
				Modal.close()
				Notifications.show(("%s demolished (+%s)"):format(def.name, Format.cash(res.refund or 0)), "info")
			elseif res.err then
				Notifications.show(res.err, "bad")
			end
		end,
	})

	-------------------------------------------------------------------
	-- building-specific sections
	-------------------------------------------------------------------
	local rebuildSpecial: (() -> ())? = nil
	local updateSpecial: (() -> ())? = nil

	if def.refine then
		local special, specialTitle = section(scroll, "Fuel goes to", 4)
		local rows: { [number]: { bar: Lib.Progress, amount: TextLabel, radio: Frame } } = {}
		local signature = ""
		local listHolder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = special }, { Lib.list("y", 5) })
		local function row(destUid: number, name: string, right: string, order: number)
			local btn = Lib.button({
				Name = destUid == 0 and "Auto" or ("Dest" .. destUid),
				Size = UDim2.new(1, 0, 0, destUid == 0 and 36 or 46),
				BackgroundColor3 = C.Inset,
				LayoutOrder = order,
				Parent = listHolder,
				Activated = function()
					local res = Net.request("SetFuelDestination", uid, destUid)
					if not res.ok and res.err then
						Notifications.show(res.err, "bad")
					end
				end,
			}, { Lib.corner(4), Lib.stroke(C.LineSoft) })
			local radio = New("Frame", {
				BackgroundColor3 = C.Panel,
				Position = UDim2.fromOffset(10, destUid == 0 and 9 or 13),
				Size = UDim2.fromOffset(18, 18),
				Parent = btn,
			}, { Lib.round(), Lib.stroke(C.Faint, 2) })
			New("Frame", { Name = "Dot", BackgroundColor3 = C.Accent, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 10), Visible = false, Parent = radio }, { Lib.round() })
			Lib.text({ Text = name, FontFace = Theme.Font.BodyBold, TextSize = 13, TextColor3 = destUid == 0 and C.Accent or C.Text, Position = UDim2.fromOffset(38, destUid == 0 and 0 or 4), Size = UDim2.new(0.6, 0, 0, destUid == 0 and 36 or 20), Parent = btn })
			local amount = Lib.text({ Text = right, FontFace = Theme.Font.Mono, TextSize = 11, TextColor3 = C.Muted, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, destUid == 0 and 0 or 4), Size = UDim2.new(0.36, 0, 0, destUid == 0 and 36 or 20), TextXAlignment = Enum.TextXAlignment.Right, Parent = btn })
			local bar = Lib.progress({ Segments = 10, Position = UDim2.new(0, 38, 0, 30), Size = UDim2.new(1, -48, 0, 5), Parent = btn, Visible = destUid ~= 0 })
			rows[destUid] = { bar = bar, amount = amount, radio = radio }
		end
		local function rebuildList()
			local list = consumers()
			local sig = ""
			for _, c in list do
				sig ..= c.uid .. ","
			end
			if sig == signature then
				return
			end
			signature = sig
			Lib.clear(listHolder)
			table.clear(rows)
			specialTitle.Text = ("FUEL GOES TO (%d BUILDINGS)"):format(#list)
			row(0, "Auto", "most free space", 0)
			for i, c in list do
				row(c.uid, c.name, "", i)
			end
			if #list == 0 then
				Lib.text({ Text = "No fuel users yet - build a Military Factory.", TextSize = 12, TextColor3 = C.Muted, LayoutOrder = 99, Parent = listHolder })
			end
		end
		rebuildSpecial = rebuildList
		updateSpecial = function()
			rebuildList()
			local dest = (model:GetAttribute("Dest") :: number?) or 0
			for _, c in consumers() do
				local r = rows[c.uid]
				if r then
					local fuel = (c.model:GetAttribute("Fuel") :: number?) or 0
					r.amount.Text = ("%s / %s"):format(Format.commas(fuel), Format.commas(c.cap))
					r.bar.set(fuel / c.cap)
				end
			end
			for id, r in rows do
				(r.radio:FindFirstChild("Dot") :: Frame).Visible = id == dest
			end
		end
	elseif def.factory then
		local queueSection, queueTitle = section(scroll, "Production queue", 4)
		local queueHolder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = queueSection }, { Lib.list("y", 4) })
		local optSection = section(scroll, "Build orders", 5)
		local options = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = optSection }, { Lib.grid(UDim2.new(0.5, -4, 0, 58), 6) })
		local lastQueue = ""
		local function renderOptions()
			Lib.clear(options)
			local acc = { researched = ClientState.get("researched") or {}, passes = ClientState.get("passes") or {} }
			local items = {}
			local makes = def.factory and def.factory.makes or {}
			if table.find(makes, "weapon") then
				for _, w in Weapons.all() do
					table.insert(items, { kind = "weapon", def = w })
				end
			end
			for _, u in Units.all() do
				if table.find(makes, u.class) then
					table.insert(items, { kind = "unit", def = u })
				end
			end
			for i, item in items do
				local d = item.def
				local ok = Unlocks.check(d, acc)
				local btn = Lib.button({
					Name = "Order_" .. d.id,
					LayoutOrder = (ok and 0 or 100) + i,
					BackgroundColor3 = ok and C.Raised or C.Inset,
					Parent = options,
					Activated = function()
						if not ok then
							Notifications.show(d.name .. " is locked - check Research" .. (d.pass and " or the Store" or ""), "info")
							return
						end
						local res = Net.request("QueueProduction", uid, item.kind, d.id)
						if res.ok then
							Sounds.play("Click", 1.1)
						elseif res.err then
							Notifications.show(res.err, "bad")
						end
					end,
				}, { Lib.corner(4), Lib.stroke(ok and C.LineSoft or C.Inset), Lib.pad(6, 8) })
				Lib.display({ Text = string.upper(item.kind == "weapon" and (d :: any).short or d.name), TextSize = 13, TextColor3 = ok and C.Text or C.Faint, Size = UDim2.new(1, -60, 0, 16), Parent = btn })
				Lib.display({ Text = "$" .. Format.short(d.cost), TextSize = 12, TextColor3 = ok and C.Good or C.Faint, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(58, 16), TextXAlignment = Enum.TextXAlignment.Right, Parent = btn })
				Lib.text({
					Text = ok and (d.fuel > 0 and ("%d fuel · %d steel · %s"):format(d.fuel, d.steel, Format.duration(d.time)) or ("%d steel · %s"):format(d.steel, Format.duration(d.time))) or "LOCKED",
					TextSize = 11,
					FontFace = Theme.Font.BodyBold,
					TextColor3 = ok and C.Muted or C.Accent,
					Position = UDim2.fromOffset(0, 22),
					Size = UDim2.new(1, 0, 0, 14),
					Parent = btn,
				})
			end
		end
		renderOptions()
		rebuildSpecial = renderOptions
		updateSpecial = function()
			local q = (model:GetAttribute("Queue") :: string?) or "[]"
			if q == lastQueue then
				return
			end
			lastQueue = q
			local ok, items = pcall(HttpService.JSONDecode, HttpService, q)
			if not ok then
				items = {}
			end
			Lib.clear(queueHolder)
			queueTitle.Text = ("PRODUCTION QUEUE (%d / %d)"):format(#items, ClientState.get("queueLimit") or Config.MaxQueuePerFactory)
			if #items == 0 then
				Lib.text({ Text = "Queue is empty - pick a build order below.", TextSize = 12, TextColor3 = C.Muted, Parent = queueHolder })
			end
			for i, it in items do
				local cat = it.k == "unit" and Units.get(it.id) or Weapons.get(it.id)
				local rowF = Lib.inset({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = i, Parent = queueHolder })
				Lib.text({ Text = cat and cat.name or it.id, FontFace = Theme.Font.BodyBold, TextSize = 13, Position = UDim2.fromOffset(10, 2), Size = UDim2.new(0.6, 0, 0, 20), Parent = rowF })
				local bar = Lib.progress({ Segments = 10, Position = UDim2.new(0, 10, 0, 24), Size = UDim2.new(1, -90, 0, 5), Parent = rowF })
				bar.set(it.p or 0, i == 1 and C.Accent or C.Faint)
				Lib.button({
					Text = "CANCEL",
					Variant = "danger",
					TextSize = 10,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -6, 0.5, 0),
					Size = UDim2.fromOffset(64, 24),
					Parent = rowF,
					Activated = function()
						Net.request("CancelProduction", uid, i)
					end,
				})
			end
		end
	elseif def.farm then
		local cropSection, cropTitle = section(scroll, "Field", 4)
		local status = Lib.display({ Text = "", TextSize = 15, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, Parent = cropSection })
		local growBar = Lib.progress({ Segments = 12, Size = UDim2.new(1, 0, 0, 8), LayoutOrder = 2, Parent = cropSection })
		local row = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 3, Parent = cropSection }, { Lib.list("x", 6) })
		local harvestBtn = Lib.button({
			Name = "Harvest",
			Variant = "good",
			Text = "HARVEST",
			TextSize = 13,
			Size = UDim2.fromOffset(120, 34),
			Parent = row,
			Activated = function()
				local res = Net.request("FarmAction", uid, "harvest")
				if res.ok then
					Sounds.play("Success")
				elseif res.err then
					Notifications.show(res.err, "info")
				end
			end,
		})
		local autoBtn = Lib.button({
			Name = "AutoReplant",
			Variant = "secondary",
			Text = "AUTO-REPLANT: OFF",
			TextSize = 11,
			Size = UDim2.fromOffset(150, 34),
			Parent = row,
			Activated = function()
				Net.request("FarmAction", uid, "auto")
			end,
		})
		Lib.button({
			Name = "HarvestAll",
			Variant = "secondary",
			Text = "HARVEST ALL",
			TextSize = 11,
			Size = UDim2.fromOffset(110, 34),
			Parent = row,
			Activated = function()
				local res = Net.request("HarvestAll")
				if res.ok then
					Sounds.play("Success")
					Notifications.show(("Harvested %d fields: +%d food"):format(res.count or 0, res.food or 0), "good")
				elseif res.err then
					Notifications.show(res.err, "info")
				end
			end,
		})
		local plantSection = section(scroll, "Plant a crop", 5)
		local cropGrid = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = plantSection }, { Lib.grid(UDim2.new(0.5, -4, 0, 62), 6) })
		for i, crop in Crops.all() do
			local btn = Lib.button({
				Name = "Plant_" .. crop.id,
				LayoutOrder = i,
				BackgroundColor3 = C.Raised,
				Parent = cropGrid,
				Activated = function()
					local res = Net.request("FarmAction", uid, "plant", crop.id)
					if res.ok then
						Sounds.play("Place")
					elseif res.err then
						Notifications.show(res.err, "info")
					end
				end,
			}, { Lib.corner(4), Lib.stroke(C.LineSoft), Lib.pad(6, 8) })
			New("Frame", { BackgroundColor3 = crop.ripe, Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(0, 3), Parent = btn }, { Lib.round() })
			Lib.display({ Text = string.upper(crop.name), TextSize = 13, Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -70, 0, 16), Parent = btn })
			Lib.display({ Text = "$" .. crop.seed, TextSize = 12, TextColor3 = C.Good, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(54, 16), TextXAlignment = Enum.TextXAlignment.Right, Parent = btn })
			Lib.text({ Text = ("%d food · %s"):format(crop.yield, Format.duration(crop.time)), TextSize = 11, FontFace = Theme.Font.BodyBold, TextColor3 = C.Muted, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 14), Parent = btn })
		end
		Lib.button({
			Name = "SellFood",
			Variant = "gold",
			Text = "SELL ALL FOOD",
			TextSize = 12,
			Size = UDim2.fromOffset(160, 32),
			LayoutOrder = 2,
			Parent = plantSection,
			Activated = function()
				local res = Net.request("SellFood")
				if res.ok then
					Sounds.play("Pay")
					Notifications.show(res.text or "Food sold", "pay")
				elseif res.err then
					Notifications.show(res.err, "info")
				end
			end,
		})
		updateSpecial = function()
			local crop = Crops.get(model:GetAttribute("Crop") :: string?)
			local growth = ((model:GetAttribute("Growth") :: number?) or 0) / 100
			local ripe = crop ~= nil and growth >= 1
			cropTitle.Text = crop and ("FIELD · %s"):format(string.upper(crop.name)) or "FIELD · EMPTY"
			status.Text = crop and (ripe and "RIPE - READY TO HARVEST" or ("%s · %d%%"):format(string.upper(Crops.StageNames[Crops.stage(growth)]), math.floor(growth * 100))) or "PICK A CROP BELOW"
			status.TextColor3 = ripe and C.Good or (crop and C.Text or C.Muted)
			growBar.set(growth, ripe and C.Good or C.Gold)
			harvestBtn.Visible = ripe
			autoBtn.Text = model:GetAttribute("AutoReplant") and "AUTO-REPLANT: ON" or "AUTO-REPLANT: OFF"
			plantSection.Visible = crop == nil
		end
	elseif def.launcher then
		local special = section(scroll, "Strike", 4)
		Lib.text({ Text = "Open the war map, pick this weapon in the hotbar and click a target.", TextSize = 13, TextColor3 = C.TextSoft, TextWrapped = true, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 1, Parent = special })
		Lib.button({
			Variant = "primary",
			Text = "OPEN WAR MAP",
			TextSize = 13,
			Size = UDim2.fromOffset(180, 36),
			LayoutOrder = 2,
			Parent = special,
			Activated = function()
				Modal.close()
				Hub.call("goWar", "mainland")
			end,
		})
	elseif def.billboard then
		local special = section(scroll, "Billboard message", 4)
		local box = Lib.textbox({
			Text = ClientState.get("billboard") or "",
			PlaceholderText = "Your message (40 characters)",
			LayoutOrder = 1,
			Parent = special,
		})
		Lib.button({
			Variant = "primary",
			Text = "SAVE MESSAGE",
			TextSize = 13,
			Size = UDim2.fromOffset(160, 34),
			LayoutOrder = 2,
			Parent = special,
			Activated = function()
				local res = Net.request("SetBillboard", box.Text)
				if res.ok then
					Notifications.show("Billboards updated", "good")
				elseif res.err then
					Notifications.show(res.err, "bad")
				end
			end,
		})
	end

	-------------------------------------------------------------------
	-- live refresh
	-------------------------------------------------------------------
	local function refresh()
		if not model.Parent then
			Modal.close()
			return
		end
		local status = (model:GetAttribute("Status") :: string?) or ""
		local finishAt = model:GetAttribute("FinishAt") :: number?
		local now = Lib.serverNow()
		if finishAt then
			local start = (model:GetAttribute("BuildStart") :: number?) or now
			local frac = (now - start) / math.max(0.1, finishAt - start)
			status = ("Under construction · %s left"):format(Format.duration(finishAt - now))
			setStat(stats[1], "Construction", Format.percent(frac * 100), "being built", frac, C.Info)
			setStat(stats[2], "Cost", Format.cash(def.cost), "full refund if cancelled", nil)
			setStat(stats[3], "Health", ("%d"):format(def.hp), "max structure", nil)
			setStat(stats[4], "Footprint", ("%dx%d"):format(def.size[1], def.size[2]), "grid cells", nil)
		else
			local eff = ((model:GetAttribute("Eff") :: number?) or 0) / 100
			local hp = (model:GetAttribute("Hp") :: number?) or def.hp
			local d = ClientState.data
			if def.refine then
				local oil = (model:GetAttribute("Oil") :: number?) or 0
				local fuel = (model:GetAttribute("Fuel") :: number?) or 0
				setStat(stats[1], "Oil stored", ("%s/%s"):format(Format.short(oil), Format.short(def.refine.oilCap)), "waiting to refine", oil / def.refine.oilCap)
				setStat(stats[2], "Fuel stored", ("%s/%s"):format(Format.short(fuel), Format.short(def.refine.fuelCap)), "waiting for trucks", fuel / def.refine.fuelCap)
				setStat(stats[3], "Fuel output", ("%s/min"):format(Format.short(def.refine.rate * eff)), "refined from oil", eff, C.Teal)
				setStat(stats[4], "Oil arriving", ("+%s/min"):format(Format.short((model:GetAttribute("OilArriving") :: number?) or 0)), "from your oil pumps", nil)
			elseif def.factory then
				local fuel = (model:GetAttribute("Fuel") :: number?) or 0
				if def.fuelCap then
					setStat(stats[1], "Fuel stored", ("%s/%s"):format(Format.short(fuel), Format.short(def.fuelCap)), "delivered by trucks", fuel / def.fuelCap)
				else
					setStat(stats[1], "Army", ("%d/%d"):format(d.units or 0, d.unitCap or 0), "units in service", (d.unitCap or 0) > 0 and (d.units or 0) / d.unitCap or 0, C.Info)
				end
				setStat(stats[2], "Steel", Format.short(d.steel or 0), ("+%s/min nationally"):format(Format.short(d.steelRate or 0)), (d.steelCap or 0) > 0 and (d.steel or 0) / d.steelCap or 0, C.TextSoft)
				setStat(stats[3], "Build speed", ("x%s"):format(tostring(def.factory.speed * ((d.passes or {}).FastBuild and 2 or 1))), "Fast Construction doubles it", nil)
				setStat(stats[4], "Efficiency", Format.percent(eff * 100), "workers, power, road", eff, C.Teal)
			elseif def.launcher then
				local w = weaponForFamily(def.launcher)
				local stock = w and ((d.inventory or {})[w.id] or 0) or 0
				local l = (d.launchers or {})[def.launcher]
				local reloadUntil = (model:GetAttribute("ReloadUntil") :: number?) or 0
				setStat(stats[1], "Stockpile", ("%d/%d"):format(stock, w and w.stockCap or 60), (w and w.short or def.launcher) .. " rounds", w and stock / w.stockCap or 0)
				setStat(stats[2], "Launchers ready", l and ("%d/%d"):format(l.ready, l.total) or "0", "of this type", l and l.total > 0 and l.ready / l.total or 0, C.Good)
				setStat(stats[3], "Reload", reloadUntil > now and Format.duration(reloadUntil - now) or "READY", ("%ds per launch"):format(def.reload or 20), nil)
				setStat(stats[4], "Hits landed", Format.commas(((d.stats or {}).Hits) or 0), "unlocks better missiles", nil)
			elseif def.farm then
				local crop = Crops.get(model:GetAttribute("Crop") :: string?)
				local growth = ((model:GetAttribute("Growth") :: number?) or 0) / 100
				setStat(stats[1], "Growth", crop and Format.percent(growth * 100) or "-", crop and crop.name or "nothing planted", growth, C.Good)
				setStat(stats[2], "Food stored", ("%s/%s"):format(Format.short(d.food or 0), Format.short(d.foodCap or 0)), d.fed and "citizens well fed" or ("citizens eat %s/pay"):format(Format.short(d.foodUse or 0)), (d.foodCap or 0) > 0 and (d.food or 0) / d.foodCap or 0, C.Gold)
				setStat(stats[3], "Harvest", crop and ("%d food"):format(crop.yield) or "-", "overflow sells for cash", nil)
				setStat(stats[4], "Efficiency", Format.percent(eff * 100), "farmhands + barns nearby", eff, C.Teal)
			elseif def.airDefense then
				local ad = def.airDefense
				setStat(stats[1], "Range", ("%d"):format(ad.range), "studs · +25% with radar", nil)
				setStat(stats[2], "Intercept", Format.percent(ad.chance * 100), "per engagement", ad.chance, C.Teal)
				setStat(stats[3], "Reload", Format.duration(ad.reload), "between shots", nil)
				setStat(stats[4], "Health", ("%d/%d"):format(hp, def.hp), "armor", hp / def.hp, C.Good)
			elseif def.housing then
				setStat(stats[1], "Residents", ("%s"):format(Format.commas(def.housing * eff)), ("of %s capacity"):format(Format.commas(def.housing)), eff, C.Teal)
				setStat(stats[2], "Population", Format.short(d.pop or 0), ("nation cap %s"):format(Format.short(d.popCap or 0)), (d.popCap or 0) > 0 and (d.pop or 0) / d.popCap or 0, C.Info)
				setStat(stats[3], "Power use", ("%d MW"):format(def.power or 0), "needs electricity", nil)
				setStat(stats[4], "Water use", ("%d"):format(def.water or 0), "needs water", nil)
			else
				local outText, outSub = "-", ""
				if def.powerOut then
					outText, outSub = ("%s MW"):format(Format.short(def.powerOut * eff)), "power produced"
				elseif def.waterOut then
					outText, outSub = Format.short(def.waterOut * eff), "water supplied"
				elseif def.oilOut then
					outText, outSub = ("%s/min"):format(Format.short(def.oilOut * eff)), "oil pumped"
				elseif def.steelOut then
					outText, outSub = ("%s/min"):format(Format.short(def.steelOut * eff)), "steel produced"
				elseif def.rpOut then
					outText, outSub = ("%s/min"):format(Format.short(def.rpOut * eff)), "research points"
				elseif def.income then
					outText, outSub = Format.cash(def.income * eff), "earned per pay"
				elseif def.service then
					outText, outSub = Format.short(def.service.serves * eff), string.lower(def.service.kind) .. " coverage"
				elseif def.storage then
					outText, outSub = "+" .. Format.short((def.storage.oil or 0) + (def.storage.steel or 0) + (def.storage.food or 0)), def.storage.food and "food storage" or "extra storage"
				elseif def.depot then
					outText, outSub = "+" .. def.depot, "army capacity"
				elseif def.radar then
					outText, outSub = "+25%", "air defense range"
				end
				setStat(stats[1], "Output", outText, outSub, nil)
				setStat(stats[2], "Efficiency", Format.percent(eff * 100), "workers, power, water, road", eff, C.Teal)
				setStat(stats[3], "Workers", ("%d"):format(def.workers or 0), "needed to run", nil)
				setStat(stats[4], "Health", ("%d/%d"):format(hp, def.hp), model:GetAttribute("Damaged") and "knocked out!" or "structure", hp / def.hp, C.Good)
			end
		end
		statusText.Text = string.upper(status)
		local col = statusColor(status, model)
		statusText.TextColor3 = col
		statusDot.BackgroundColor3 = col
		if model:GetAttribute("Connected") == false and def.needsRoad then
			doingDesc.Text = "No road access: place a road next to this building to run at full speed."
		else
			doingDesc.Text = Hub.describeBuilding and Hub.describeBuilding(def) or def.desc
		end
		local damaged = model:GetAttribute("Damaged") == true
		repairBtn.Visible = damaged
		repairBtn.Text = ("REPAIR %s"):format(Format.cash(math.floor(def.cost * Config.RepairCostRate)))
		if updateSpecial then
			updateSpecial()
		end
	end

	refresh()
	local acc = 0
	local conn = RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.4 then
			acc = 0
			refresh()
		end
	end)
	local unsubscribe = ClientState.onAny(function(patch)
		if (patch.researched or patch.passes) and rebuildSpecial and def.factory then
			rebuildSpecial()
		end
	end)
	win.onClose(function()
		unsubscribe()
		conn:Disconnect()
	end)
end

function BuildingPanel.init()
	Hub.openBuilding = BuildingPanel.open
end

return BuildingPanel
