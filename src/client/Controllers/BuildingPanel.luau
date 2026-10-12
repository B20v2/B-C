--[[
	BuildingPanel
	Click any of your buildings to inspect it. Layout follows the classic
	"Medium Refinery" panel: four stat cards, "What it is doing", then a
	building-specific section (fuel destinations, production queue, launcher
	readiness...) and Repair / Move / Delete actions.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Buildings = require(Shared.Catalog.Buildings)
local Weapons = require(Shared.Catalog.Weapons)
local Units = require(Shared.Catalog.Units)
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

local BuildingPanel = {}

type StatCard = { value: TextLabel, sub: TextLabel, caption: TextLabel, bar: Lib.Progress }

local function statCard(parent: Instance, order: number): StatCard
	local card = Lib.card({ LayoutOrder = order, Size = UDim2.new(0.25, -6, 0, 88), Parent = parent }, { Lib.pad(10, 12) })
	local caption = Lib.caption("", { Parent = card })
	local value = Lib.text({
		Text = "-",
		FontFace = Theme.Font.Bold,
		TextSize = Theme.TextSize.Big,
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = card,
	})
	local sub = Lib.text({
		Text = "",
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Color.Muted,
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = card,
	})
	local bar = Lib.progress({ Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(1, 0, 0, 4), Parent = card })
	return { value = value, sub = sub, caption = caption, bar = bar }
end

local function setStat(c: StatCard, caption: string, value: string, sub: string, frac: number?)
	c.caption.Text = string.upper(caption)
	c.value.Text = value
	c.sub.Text = sub
	c.bar.frame.Visible = frac ~= nil
	if frac then
		c.bar.set(frac)
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

function BuildingPanel.open(model: Model)
	local def = Buildings.get(model:GetAttribute("BuildingId") :: string)
	if not def then
		return
	end
	local uid = model:GetAttribute("Uid") :: number
	local win = Modal.open(def.name, model:GetAttribute("Status") :: string? or "", 720, 620)
	Sounds.play("Open")
	Lib.viewport(ModelBuilder.building(def), { Parent = win.iconHolder }, 40)

	local scroll = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Color.Faint,
		BorderSizePixel = 0,
		Parent = win.body,
	}, { Lib.list("y", 10), Lib.pad(0, 6, 6, 0) })

	-- stat cards
	local statRow = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 88), LayoutOrder = 1, Parent = scroll }, { Lib.list("x", 8) })
	local stats = { statCard(statRow, 1), statCard(statRow, 2), statCard(statRow, 3), statCard(statRow, 4) }

	-- what it is doing
	local doing = Lib.card({ LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 70), Parent = scroll }, { Lib.pad(10, 12) })
	Lib.caption("What it is doing", { Parent = doing })
	local doingText = Lib.text({ Text = "", FontFace = Theme.Font.Bold, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 20), Parent = doing })
	local doingDesc = Lib.text({ Text = def.desc, TextSize = Theme.TextSize.Small, TextColor3 = Theme.Color.Muted, Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 16), Parent = doing })

	-- special section container
	local special = Lib.card({ LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = scroll }, { Lib.pad(10, 12), Lib.list("y", 6) })
	local specialTitle = Lib.caption("", { LayoutOrder = 0, Parent = special })
	special.Visible = false

	-- actions
	local actions = New("Frame", { BackgroundTransparency = 1, LayoutOrder = 9, Size = UDim2.new(1, 0, 0, 40), Parent = scroll }, { Lib.list("x", 8, Enum.HorizontalAlignment.Right) })
	local repairBtn = Lib.button({
		Text = "Repair",
		FontFace = Theme.Font.Bold,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Theme.Color.Good,
		Size = UDim2.fromOffset(160, 38),
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
	}, { Lib.corner(6) })
	Lib.button({
		Text = "Move",
		FontFace = Theme.Font.Bold,
		Size = UDim2.fromOffset(110, 38),
		LayoutOrder = 2,
		Parent = actions,
		Activated = function()
			Modal.close()
			Hub.call("openBuild")
			Placement.beginMove(model)
		end,
	}, { Lib.corner(6), Lib.stroke() })
	local confirmDelete = false
	local deleteBtn: TextButton
	deleteBtn = Lib.button({
		Text = "Delete",
		FontFace = Theme.Font.Bold,
		TextColor3 = Theme.Color.Bad,
		Size = UDim2.fromOffset(150, 38),
		LayoutOrder = 3,
		Parent = actions,
		Activated = function()
			if not confirmDelete then
				confirmDelete = true
				deleteBtn.Text = "Click again to confirm"
				task.delay(3, function()
					confirmDelete = false
					if deleteBtn.Parent then
						deleteBtn.Text = "Delete"
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
	}, { Lib.corner(6), Lib.stroke(Theme.Color.Bad, 1, 0.5) })

	-------------------------------------------------------------------
	-- building specific sections
	-------------------------------------------------------------------
	local rebuildSpecial: (() -> ())? = nil
	local updateSpecial: (() -> ())? = nil

	if def.refine then
		special.Visible = true
		local rows: { [number]: { bar: Lib.Progress, amount: TextLabel, radio: Frame } } = {}
		local signature = ""
		local listHolder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = special }, { Lib.list("y", 6) })
		local function row(destUid: number, name: string, right: string, order: number)
			local btn = Lib.button({
				Size = UDim2.new(1, 0, 0, destUid == 0 and 38 or 48),
				BackgroundColor3 = Theme.Color.Card,
				LayoutOrder = order,
				Parent = listHolder,
				Activated = function()
					local res = Net.request("SetFuelDestination", uid, destUid)
					if not res.ok and res.err then
						Notifications.show(res.err, "bad")
					end
				end,
			}, { Lib.corner(6), Lib.stroke() })
			local radio = New("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				Position = UDim2.fromOffset(12, destUid == 0 and 9 or 14),
				Size = UDim2.fromOffset(20, 20),
				Parent = btn,
			}, { Lib.round(), Lib.stroke(Theme.Color.Faint, 2) })
			New("Frame", { Name = "Dot", BackgroundColor3 = Theme.Color.Accent, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(12, 12), Visible = false, Parent = radio }, { Lib.round() })
			Lib.text({ Text = name, FontFace = Theme.Font.Bold, TextSize = Theme.TextSize.Small, TextColor3 = destUid == 0 and Theme.Color.Accent or Theme.Color.Text, Position = UDim2.fromOffset(44, destUid == 0 and 0 or 4), Size = UDim2.new(0.6, 0, 0, destUid == 0 and 38 or 22), Parent = btn })
			local amount = Lib.text({ Text = right, TextSize = Theme.TextSize.Tiny, TextColor3 = Theme.Color.TextSoft, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, destUid == 0 and 0 or 4), Size = UDim2.new(0.35, 0, 0, destUid == 0 and 38 or 22), TextXAlignment = Enum.TextXAlignment.Right, Parent = btn })
			local bar = Lib.progress({ Position = UDim2.new(0, 44, 0, 30), Size = UDim2.new(1, -56, 0, 5), Parent = btn, Visible = destUid ~= 0 })
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
			row(0, "Auto", "Most free space", 0)
			for i, c in list do
				row(c.uid, c.name, "", i)
			end
			if #list == 0 then
				Lib.text({ Text = "No fuel users yet - build a Military Factory.", TextSize = Theme.TextSize.Small, TextColor3 = Theme.Color.Muted, LayoutOrder = 99, Parent = listHolder })
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
		special.Visible = true
		local queueHolder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = special }, { Lib.list("y", 4) })
		Lib.caption("Build", { LayoutOrder = 2, Parent = special })
		local options = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Parent = special }, { Lib.grid(UDim2.new(0.25, -6, 0, 74), 6) })
		local lastQueue = ""
		local function renderOptions()
			Lib.clear(options)
			local acc = { researched = ClientState.get("researched") or {}, passes = ClientState.get("passes") or {} }
			local items = {}
			for _, w in Weapons.all() do
				table.insert(items, { kind = "weapon", def = w })
			end
			for _, u in Units.all() do
				table.insert(items, { kind = "unit", def = u })
			end
			for i, item in items do
				local d = item.def
				local ok = Unlocks.check(d, acc)
				local btn = Lib.button({
					LayoutOrder = (ok and 0 or 100) + i,
					BackgroundColor3 = ok and Theme.Color.Card or Theme.Color.CardAlt,
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
				}, { Lib.corner(6), Lib.stroke(), Lib.pad(6, 8) })
				Lib.text({ Text = (item.kind == "weapon" and (d :: any).short or d.name), FontFace = Theme.Font.Bold, TextSize = Theme.TextSize.Small, TextColor3 = ok and Theme.Color.Text or Theme.Color.Faint, Size = UDim2.new(1, 0, 0, 18), Parent = btn })
				Lib.text({ Text = ok and ("%d fuel · %d steel · %s"):format(d.fuel, d.steel, Format.duration(d.time)) or "Locked", TextSize = Theme.TextSize.Tiny, TextColor3 = ok and Theme.Color.Muted or Theme.Color.Bad, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 14), Parent = btn })
				local chip = Lib.chip("$" .. Format.commas(d.cost), Theme.Color.GoodSoft, Theme.Color.Good, { Position = UDim2.fromOffset(0, 38), Size = UDim2.fromOffset(0, 20) })
				chip.Parent = btn
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
			specialTitle.Text = ("PRODUCTION QUEUE (%d / %d)"):format(#items, ClientState.get("queueLimit") or Config.MaxQueuePerFactory)
			if #items == 0 then
				Lib.text({ Text = "Queue is empty - pick something below.", TextSize = Theme.TextSize.Small, TextColor3 = Theme.Color.Muted, Parent = queueHolder })
			end
			for i, it in items do
				local cat = it.k == "unit" and Units.get(it.id) or Weapons.get(it.id)
				local rowF = Lib.card({ Size = UDim2.new(1, 0, 0, 34), LayoutOrder = i, Parent = queueHolder })
				Lib.text({ Text = cat and cat.name or it.id, FontFace = Theme.Font.Semi, TextSize = Theme.TextSize.Small, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.4, 0, 0, 22), Parent = rowF })
				local bar = Lib.progress({ Position = UDim2.new(0, 10, 0, 24), Size = UDim2.new(0.85, -20, 0, 4), Parent = rowF })
				bar.set(it.p or 0, Theme.Color.Accent)
				Lib.button({
					Text = "Cancel",
					TextSize = Theme.TextSize.Tiny,
					TextColor3 = Theme.Color.Bad,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -6, 0.5, 0),
					Size = UDim2.fromOffset(60, 24),
					Parent = rowF,
					Activated = function()
						Net.request("CancelProduction", uid, i)
					end,
				}, { Lib.corner(5), Lib.stroke() })
			end
		end
	elseif def.launcher then
		special.Visible = true
		specialTitle.Text = "STRIKE"
		Lib.text({ Text = "Open the war map with Travel, pick this weapon in the hotbar and click a target.", TextSize = Theme.TextSize.Small, TextColor3 = Theme.Color.TextSoft, TextWrapped = true, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 1, Parent = special })
		Lib.button({
			Text = "Open War Map",
			FontFace = Theme.Font.Bold,
			TextColor3 = Color3.new(1, 1, 1),
			BackgroundColor3 = Theme.Color.Military,
			Size = UDim2.fromOffset(180, 36),
			LayoutOrder = 2,
			Parent = special,
			Activated = function()
				Modal.close()
				Hub.call("goWar", "mainland")
			end,
		}, { Lib.corner(6) })
	elseif def.billboard then
		special.Visible = true
		specialTitle.Text = "BILLBOARD MESSAGE"
		local box = New("TextBox", {
			Text = ClientState.get("billboard") or "",
			PlaceholderText = "Type your message (40 characters)",
			FontFace = Theme.Font.Semi,
			TextSize = Theme.TextSize.Body,
			TextColor3 = Theme.Color.Text,
			BackgroundColor3 = Color3.new(1, 1, 1),
			ClearTextOnFocus = false,
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = 1,
			Parent = special,
		}, { Lib.corner(6), Lib.stroke(), Lib.pad(0, 10) })
		Lib.button({
			Text = "Save Message",
			FontFace = Theme.Font.Bold,
			TextColor3 = Color3.new(1, 1, 1),
			BackgroundColor3 = Theme.Color.Accent,
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
		}, { Lib.corner(6) })
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
			status = ("Under Construction - %s left"):format(Format.duration(finishAt - now))
			setStat(stats[1], "Construction", Format.percent(frac * 100), "Being built", frac)
			setStat(stats[2], "Cost", Format.cash(def.cost), "Full refund if cancelled", nil)
			setStat(stats[3], "Health", ("%d"):format(def.hp), "Max health", nil)
			setStat(stats[4], "Size", ("%dx%d"):format(def.size[1], def.size[2]), "Grid cells", nil)
		else
			local eff = ((model:GetAttribute("Eff") :: number?) or 0) / 100
			local hp = (model:GetAttribute("Hp") :: number?) or def.hp
			local d = ClientState.data
			if def.refine then
				local oil = (model:GetAttribute("Oil") :: number?) or 0
				local fuel = (model:GetAttribute("Fuel") :: number?) or 0
				setStat(stats[1], "Oil Stored", ("%s / %s"):format(Format.commas(oil), Format.commas(def.refine.oilCap)), "Waiting To Refine", oil / def.refine.oilCap)
				setStat(stats[2], "Fuel Stored", ("%s / %s"):format(Format.commas(fuel), Format.commas(def.refine.fuelCap)), "Waiting For Trucks", fuel / def.refine.fuelCap)
				setStat(stats[3], "Fuel Output", ("%s / Min"):format(Format.short(def.refine.rate * eff)), "Refined From Oil", nil)
				setStat(stats[4], "Oil Arriving", ("+%s / Min"):format(Format.short((model:GetAttribute("OilArriving") :: number?) or 0)), "From Your Oil Pumps", nil)
			elseif def.factory then
				local fuel = (model:GetAttribute("Fuel") :: number?) or 0
				setStat(stats[1], "Fuel Stored", ("%s / %s"):format(Format.commas(fuel), Format.commas(def.fuelCap or 0)), "Delivered By Trucks", fuel / (def.fuelCap or 1))
				setStat(stats[2], "Steel", Format.short(d.steel or 0), ("+%s / Min nationally"):format(Format.short(d.steelRate or 0)), nil)
				setStat(stats[3], "Build Speed", ("x%s"):format(tostring(def.factory.speed * ((d.passes or {}).FastBuild and 2 or 1))), "Fast Construction doubles it", nil)
				setStat(stats[4], "Efficiency", Format.percent(eff * 100), "Workers, power, road", eff)
			elseif def.launcher then
				local w = weaponForFamily(def.launcher)
				local stock = w and ((d.inventory or {})[w.id] or 0) or 0
				local l = (d.launchers or {})[def.launcher]
				local reloadUntil = (model:GetAttribute("ReloadUntil") :: number?) or 0
				setStat(stats[1], "Stockpile", ("%d / %d"):format(stock, w and w.stockCap or 60), (w and w.short or def.launcher) .. " missiles", w and stock / w.stockCap or 0)
				setStat(stats[2], "Launchers Ready", l and ("%d / %d"):format(l.ready, l.total) or "0", "Of this type", nil)
				setStat(stats[3], "Reload", reloadUntil > now and Format.duration(reloadUntil - now) or "Ready", ("%ds per launch"):format(def.reload or 20), nil)
				setStat(stats[4], "Hits Landed", Format.commas(((d.stats or {}).Hits) or 0), "Unlocks better missiles", nil)
			elseif def.airDefense then
				local ad = def.airDefense
				setStat(stats[1], "Range", ("%d"):format(ad.range), "Studs (+25% with radar)", nil)
				setStat(stats[2], "Hit Chance", Format.percent(ad.chance * 100), "Per engagement", ad.chance)
				setStat(stats[3], "Reload", Format.duration(ad.reload), "Between shots", nil)
				setStat(stats[4], "Health", ("%d / %d"):format(hp, def.hp), "Armor", hp / def.hp)
			elseif def.housing then
				setStat(stats[1], "Residents", ("up to %s"):format(Format.commas(def.housing * eff)), ("Max %s"):format(Format.commas(def.housing)), eff)
				setStat(stats[2], "Population", Format.short(d.pop or 0), ("Capacity %s"):format(Format.short(d.popCap or 0)), (d.popCap or 0) > 0 and (d.pop or 0) / d.popCap or 0)
				setStat(stats[3], "Power Use", ("%d MW"):format(def.power or 0), "Needs electricity", nil)
				setStat(stats[4], "Water Use", ("%d"):format(def.water or 0), "Needs water", nil)
			else
				local outText, outSub = "-", ""
				if def.powerOut then
					outText, outSub = ("%s MW"):format(Format.short(def.powerOut * eff)), "Power produced"
				elseif def.waterOut then
					outText, outSub = Format.short(def.waterOut * eff), "Water supplied"
				elseif def.oilOut then
					outText, outSub = ("%s / Min"):format(Format.short(def.oilOut * eff)), "Oil pumped"
				elseif def.steelOut then
					outText, outSub = ("%s / Min"):format(Format.short(def.steelOut * eff)), "Steel produced"
				elseif def.rpOut then
					outText, outSub = ("%s / Min"):format(Format.short(def.rpOut * eff)), "Research points"
				elseif def.income then
					outText, outSub = Format.cash(def.income * eff), "Earned per pay"
				elseif def.service then
					outText, outSub = Format.short(def.service.serves * eff), def.service.kind .. " coverage"
				elseif def.storage then
					outText, outSub = "+" .. Format.short((def.storage.oil or 0) + (def.storage.steel or 0)), "Extra storage"
				elseif def.depot then
					outText, outSub = "+" .. def.depot, "Army capacity"
				end
				setStat(stats[1], "Output", outText, outSub, nil)
				setStat(stats[2], "Efficiency", Format.percent(eff * 100), "Workers, power, water, road", eff)
				setStat(stats[3], "Workers", ("%d"):format(def.workers or 0), "Needed to run", nil)
				setStat(stats[4], "Health", ("%d / %d"):format(hp, def.hp), model:GetAttribute("Damaged") and "Knocked out!" or "Structure", hp / def.hp)
			end
		end
		win.subtitle.Text = status
		doingText.Text = status
		doingText.TextColor3 = (model:GetAttribute("Damaged") or status:find("Not Enough") or status:find("No Road")) and Theme.Color.Bad or Theme.Color.Text
		if model:GetAttribute("Connected") == false and def.needsRoad then
			doingDesc.Text = "Place a road next to this building to run at full speed."
		else
			doingDesc.Text = Hub.describeBuilding and Hub.describeBuilding(def) or def.desc
		end
		local damaged = model:GetAttribute("Damaged") == true
		repairBtn.Visible = damaged
		repairBtn.Text = ("Repair (%s)"):format(Format.cash(math.floor(def.cost * Config.RepairCostRate)))
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
