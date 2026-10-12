--[[
	BuildMenu - the build drawer
	  [ department: CIVIL / MILITARY ]
	  [ tabs · faction toggle / structure cards with 3D previews ]
	  [ detail: spinning preview, cost, stats / tools: DEMOLISH 2, UNDO 3,
	    DRAG 4, MOVE 5, ROTATE 6, CLOSE ]
	plus the placement hint bar above the drawer.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Buildings = require(Shared.Catalog.Buildings)
local Weapons = require(Shared.Catalog.Weapons)
local Research = require(Shared.Catalog.Research)
local Products = require(Shared.Catalog.Products)
local ModelBuilder = require(Shared.ModelBuilder)
local Unlocks = require(Shared.Util.Unlocks)
local Format = require(Shared.Util.Format)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Hub = require(Client.Hub)
local Lib = require(Client.UI.Lib)
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)
local Placement = require(script.Parent.Placement)
local Notifications = require(script.Parent.Notifications)
local Sounds = require(script.Parent.Sounds)

local New = Lib.New
local C = Theme.Color

local BuildMenu = {}

local root: Frame
local tooltip: Frame
local category = "Civilian"
local tab = "Housing"
local faction = "Standard"
local refs: { [string]: any } = {}
local cards: { [string]: { btn: TextButton, lock: Frame, price: TextLabel, def: any } } = {}
local thumbs: { [string]: Model } = {}
local lastDetail: string? = nil

local W, H = 1520, 250
local LEFT = 150
local RIGHT = 410

local function access(): Unlocks.Access
	return {
		researched = ClientState.get("researched") or {},
		passes = ClientState.get("passes") or {},
	}
end

local function thumbModel(def): Model
	local m = thumbs[def.id]
	if not m then
		m = ModelBuilder.building(def)
		thumbs[def.id] = m
	end
	return m
end

function BuildMenu.describe(def): string
	local bits = {}
	if def.launcher then
		local w
		for _, wd in Weapons.all() do
			if wd.family == def.launcher then
				w = wd
				break
			end
		end
		return ("Fires %s · stock max %d · %ds reload"):format(def.launcher, w and w.stockCap or 60, def.reload or 20)
	end
	if def.airDefense then
		local ad = def.airDefense
		return ("Range %d · %d%% intercept · %ds reload"):format(ad.range, math.floor(ad.chance * 100), ad.reload)
	end
	if def.housing then
		table.insert(bits, ("+%d residents"):format(def.housing))
	end
	if def.powerOut then
		table.insert(bits, ("+%d MW"):format(def.powerOut))
	end
	if def.waterOut then
		table.insert(bits, ("+%d water"):format(def.waterOut))
	end
	if def.oilOut then
		table.insert(bits, ("+%d oil/min"):format(def.oilOut))
	end
	if def.steelOut then
		table.insert(bits, ("+%d steel/min"):format(def.steelOut))
	end
	if def.refine then
		table.insert(bits, ("%d fuel/min"):format(def.refine.rate))
	end
	if def.factory then
		table.insert(bits, "builds weapons & vehicles")
	end
	if def.rpOut then
		table.insert(bits, ("+%d RP/min"):format(def.rpOut))
	end
	if def.income then
		table.insert(bits, ("+$%s / pay"):format(Format.commas(def.income)))
	end
	if def.service then
		table.insert(bits, ("serves %s"):format(Format.short(def.service.serves)))
	end
	if def.storage then
		table.insert(bits, ("+%s storage"):format(Format.short((def.storage.oil or 0) + (def.storage.steel or 0))))
	end
	if def.depot then
		table.insert(bits, ("+%d army"):format(def.depot))
	end
	if def.workers then
		table.insert(bits, ("%d workers"):format(def.workers))
	end
	if def.power then
		table.insert(bits, ("uses %d MW"):format(def.power))
	end
	if #bits == 0 then
		return def.desc
	end
	return table.concat(bits, " · ")
end

local function lockReason(def): (boolean, string?)
	return Unlocks.check(def, access())
end

local function lockText(def): string
	if def.pass and not (access().passes[def.pass]) then
		local p = Products.pass(def.pass)
		return "PASS · " .. string.upper(p and p.name or def.pass)
	end
	if def.research then
		local r = Research.get(def.research)
		return "RESEARCH · " .. string.upper(r and r.name or def.research)
	end
	return "LOCKED"
end

---------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------
local function updateCard(entry)
	local def = entry.def
	local ok = lockReason(def)
	entry.lock.Visible = not ok
	local state = Placement.state()
	local isSel = state.def ~= nil and state.def.id == def.id
	local stroke = entry.btn:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Color = isSel and C.Accent or C.LineSoft
	stroke.Thickness = isSel and 2 or 1
	Lib.setButtonColor(entry.btn, isSel and C.AccentSoft or C.Raised)
	local afford = (ClientState.get("cash") or 0) >= def.cost
	entry.price.TextColor3 = afford and C.Good or C.Bad
end

local function makeCard(def, order: number): TextButton
	local btn = Lib.button({
		Name = def.id,
		Size = UDim2.fromOffset(150, 166),
		BackgroundColor3 = C.Raised,
		LayoutOrder = order,
		Activated = function()
			local ok, reason = lockReason(def)
			if not ok then
				Notifications.show(("%s: %s"):format(def.name, reason or "Locked"), "info")
				if def.pass then
					Hub.call("openShop", "Passes")
				elseif def.research then
					Hub.call("openResearch", def.research)
				end
				return
			end
			local state = Placement.state()
			if state.def and state.def.id == def.id then
				Placement.select(nil)
			else
				Placement.select(def)
			end
		end,
	}, { Lib.corner(4), Lib.stroke(C.LineSoft) })
	local art = Lib.inset({ Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 0, 96), Parent = btn })
	New("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(36, 46, 40), Color3.fromRGB(14, 18, 16)), Rotation = 90, Parent = art })
	Lib.viewport(thumbModel(def), { Parent = art }, 40)
	local lock = New("Frame", {
		Name = "Lock",
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.25,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 3,
		Parent = art,
	}, { Lib.corner(4) })
	local lk = Icons.get("shield", 18, C.Accent)
	lk.AnchorPoint = Vector2.new(0.5, 0)
	lk.Position = UDim2.new(0.5, 0, 0, 22)
	lk.Parent = lock
	for _, d in lk:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 4
		end
	end
	Lib.display({
		Text = lockText(def),
		TextSize = 10,
		TextColor3 = C.Accent,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(6, 46),
		Size = UDim2.new(1, -12, 0, 30),
		ZIndex = 4,
		Parent = lock,
	})
	Lib.text({
		Text = def.name,
		FontFace = Theme.Font.BodyHeavy,
		TextSize = 13,
		Position = UDim2.fromOffset(9, 106),
		Size = UDim2.new(1, -16, 0, 18),
		Parent = btn,
	})
	local price = Lib.display({
		Text = "$" .. Format.commas(def.cost),
		TextSize = 15,
		TextColor3 = C.Good,
		Position = UDim2.fromOffset(9, 128),
		Size = UDim2.new(1, -16, 0, 18),
		Parent = btn,
	})
	if def.buildTime > 0 then
		Lib.chip(Format.duration(def.buildTime), C.InfoSoft, C.Info, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 128),
			Size = UDim2.fromOffset(0, 18),
			Parent = btn,
		})
	end
	cards[def.id] = { btn = btn, lock = lock, price = price, def = def }
	updateCard(cards[def.id])
	btn.MouseEnter:Connect(function()
		refs.hoverDef = def
		BuildMenu.refreshTooltip()
		BuildMenu.refreshDetail()
	end)
	btn.MouseLeave:Connect(function()
		if refs.hoverDef == def then
			refs.hoverDef = nil
			BuildMenu.refreshTooltip()
			BuildMenu.refreshDetail()
		end
	end)
	return btn
end

local function renderCards()
	Lib.clear(refs.scroller)
	table.clear(cards)
	local hasFactions = Buildings.tabHasFactions(category, tab)
	refs.factions.Visible = hasFactions
	local list = Buildings.forTab(category, tab, hasFactions and faction or nil)
	for i, def in list do
		makeCard(def, i).Parent = refs.scroller
	end
	refs.crumb.Text = ("%s  /  %s  ·  %d STRUCTURES"):format(string.upper(category == "Civilian" and "Civil" or category), string.upper(tab), #list)
end

---------------------------------------------------------------------------
-- Tabs / categories / factions
---------------------------------------------------------------------------
local function renderTabs()
	Lib.clear(refs.tabs)
	for _, c in Buildings.Categories do
		if c.id == category then
			for i, t in c.tabs do
				local active = t == tab
				local b = Lib.button({
					Name = t,
					Text = string.upper(t),
					FontFace = Theme.Font.Display,
					TextSize = 14,
					TextColor3 = active and C.Accent or C.Muted,
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(112, 32),
					LayoutOrder = i,
					Parent = refs.tabs,
					Activated = function()
						tab = t
						faction = "Standard"
						renderTabs()
						BuildMenu.renderFactions()
						renderCards()
					end,
				})
				if active then
					New("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(0.7, 0, 0, 2), Parent = b })
				end
			end
		end
	end
	for _, c in Buildings.Categories do
		local tile = refs["cat_" .. c.id] :: TextButton
		local active = c.id == category
		local tint = c.id == "Civilian" and C.Civil or C.Military
		Lib.setButtonColor(tile, active and (c.id == "Civilian" and C.InfoSoft or C.BadSoft) or C.Raised)
		local stroke = tile:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = active and tint or C.LineSoft
		stroke.Thickness = active and 2 or 1
	end
end

function BuildMenu.renderFactions()
	Lib.clear(refs.factions)
	local passes = ClientState.get("passes") or {}
	for i, f in Buildings.Factions do
		local passKey = Buildings.FactionPass[f]
		local locked = passKey ~= nil and not passes[passKey]
		local active = f == faction
		local btn = Lib.button({
			Name = f,
			Size = UDim2.fromOffset(96, 26),
			BackgroundColor3 = active and C.AccentSoft or C.Inset,
			LayoutOrder = i,
			Parent = refs.factions,
			Activated = function()
				if locked and passKey then
					local p = Products.pass(passKey)
					Notifications.show(("%s arsenal requires the %s"):format(f, p and p.name or "pack"), "info")
					Hub.call("openShop", "Passes")
					return
				end
				faction = f
				BuildMenu.renderFactions()
				renderCards()
			end,
		}, { Lib.corner(3), Lib.stroke(active and C.Accent or C.LineSoft, 1, active and 0.2 or 0) })
		Lib.display({
			Text = string.upper(f) .. (locked and "  ◆" or ""),
			TextSize = 11,
			TextColor3 = active and C.Accent or (locked and C.Faint or C.TextSoft),
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Parent = btn,
		})
	end
end

local function setCategory(c: string)
	category = c
	for _, cat in Buildings.Categories do
		if cat.id == c then
			tab = cat.tabs[1]
		end
	end
	faction = "Standard"
	renderTabs()
	BuildMenu.renderFactions()
	renderCards()
end

---------------------------------------------------------------------------
-- Detail + tools
---------------------------------------------------------------------------
local function toolButton(parent: Instance, label: string, key: string, icon: string, order: number, onClick: () -> ()): TextButton
	local btn = Lib.button({
		Name = label,
		Size = UDim2.fromOffset(50, 50),
		BackgroundColor3 = C.Raised,
		LayoutOrder = order,
		Parent = parent,
		Activated = onClick,
	}, { Lib.corner(4), Lib.stroke(C.LineSoft) })
	local ic = Icons.get(icon, 16, C.Text)
	ic.AnchorPoint = Vector2.new(0.5, 0)
	ic.Position = UDim2.new(0.5, 0, 0, 8)
	ic.Parent = btn
	Lib.display({ Name = "Label", Text = label, TextSize = 9, TextColor3 = C.TextSoft, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 1, -18), Size = UDim2.new(1, 0, 0, 14), Parent = btn })
	if key ~= "" then
		Lib.text({ Text = key, FontFace = Theme.Font.Mono, TextSize = 9, TextColor3 = C.Faint, Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(10, 10), Parent = btn })
	end
	return btn
end

local function buildRight(parent: Frame)
	local view = Lib.inset({ Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(166, 150), Parent = parent })
	New("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(38, 50, 42), Color3.fromRGB(12, 16, 14)), Rotation = 90, Parent = view })
	refs.detailView = view
	refs.detailName = Lib.display({ Text = "SELECT A STRUCTURE", TextSize = 17, TextWrapped = true, Position = UDim2.fromOffset(188, 10), Size = UDim2.new(1, -198, 0, 40), TextYAlignment = Enum.TextYAlignment.Top, Parent = parent })
	refs.detailPrice = Lib.display({ Text = "", TextSize = 20, TextColor3 = C.Good, Position = UDim2.fromOffset(188, 52), Size = UDim2.new(1, -198, 0, 22), Parent = parent })
	refs.detailTime = Lib.text({ Text = "", FontFace = Theme.Font.BodyBold, TextSize = 12, TextColor3 = C.Info, Position = UDim2.fromOffset(188, 76), Size = UDim2.new(1, -198, 0, 16), Parent = parent })
	refs.detailReq = Lib.text({
		Text = "Pick anything and build it anywhere on your island, at any angle. Roads are drawn point to point.",
		TextSize = 12,
		TextColor3 = C.TextSoft,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(188, 96),
		Size = UDim2.new(1, -198, 0, 64),
		Parent = parent,
	})
	local tools = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 1, -60),
		Size = UDim2.new(1, -20, 0, 50),
		Parent = parent,
	}, { Lib.list("x", 5) })
	refs.toolDelete = toolButton(tools, "DEMOLISH", "2", "trash", 1, function()
		Placement.setTool("delete")
	end)
	refs.toolUndo = toolButton(tools, "UNDO", "3", "undo", 2, function()
		Placement.undo()
	end)
	refs.toolDrag = toolButton(tools, "DRAG", "4", "beam", 3, function()
		Placement.toggleDrag()
	end)
	refs.toolMove = toolButton(tools, "MOVE", "5", "map", 4, function()
		Placement.setTool("move")
	end)
	refs.toolRotate = toolButton(tools, "ROTATE", "6", "undo", 5, function()
		Placement.rotate()
	end)
	refs.toolSnap = toolButton(tools, "SNAP", "G", "target", 6, function()
		Placement.toggleSnap()
	end)
	local close = Lib.button({
		Name = "Close",
		Variant = "danger",
		Size = UDim2.fromOffset(50, 50),
		LayoutOrder = 7,
		Parent = tools,
		Activated = function()
			BuildMenu.close()
		end,
	})
	local x = Icons.close(14, C.Bad)
	x.AnchorPoint = Vector2.new(0.5, 0)
	x.Position = UDim2.new(0.5, 0, 0, 9)
	x.Parent = close
	Lib.display({ Text = "CLOSE", TextSize = 10, TextColor3 = C.Bad, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 1, -18), Size = UDim2.new(1, 0, 0, 14), Parent = close })
end

function BuildMenu.refreshDetail()
	local s = Placement.state()
	local def = refs.hoverDef or s.def
	local key = def and def.id or (s.tool or "none")
	if key ~= lastDetail then
		lastDetail = key
		Lib.clear(refs.detailView)
		if def then
			Lib.viewport(thumbModel(def), { Parent = refs.detailView }, 30, 24)
		else
			local ic = Icons.get(s.tool == "delete" and "trash" or (s.tool == "move" and "map" or "hammer"), 44, C.Faint)
			ic.AnchorPoint = Vector2.new(0.5, 0.5)
			ic.Position = UDim2.fromScale(0.5, 0.5)
			ic.Parent = refs.detailView
		end
	end
	if def then
		refs.detailName.Text = string.upper(def.name)
		refs.detailPrice.Text = "$" .. Format.commas(def.cost)
		refs.detailPrice.TextColor3 = (ClientState.get("cash") or 0) >= def.cost and C.Good or C.Bad
		refs.detailTime.Text = (def.buildTime > 0 and ("BUILDS IN " .. string.upper(Format.duration(def.buildTime))) or "BUILDS INSTANTLY")
			.. ("  ·  %dx%d"):format(def.size[1], def.size[2])
		local ok = lockReason(def)
		refs.detailReq.Text = (ok and "" or (lockText(def) .. "\n")) .. BuildMenu.describe(def)
	else
		refs.detailName.Text = s.tool == "delete" and "DEMOLISH" or (s.tool == "move" and "MOVE" or "SELECT A STRUCTURE")
		refs.detailPrice.Text = ""
		refs.detailTime.Text = ""
		refs.detailReq.Text = s.tool == "delete" and "Click a building to remove it. 50% refund (100% while it's still under construction)."
			or (s.tool == "move" and "Click a building, then click its new spot. R rotates it." or "Pick anything and build it anywhere on your island, at any angle. Roads are drawn point to point.")
	end
end

local function refreshTools()
	local s = Placement.state()
	local function mark(btn: TextButton, on: boolean)
		Lib.setButtonColor(btn, on and C.AccentSoft or C.Raised)
		local stroke = btn:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = on and C.Accent or C.LineSoft
	end
	mark(refs.toolDelete, s.tool == "delete")
	mark(refs.toolMove, s.tool == "move")
	mark(refs.toolDrag, s.drag)
	mark(refs.toolSnap, s.snap == "grid")
	local snapLabel = refs.toolSnap:FindFirstChild("Label") :: TextLabel?
	if snapLabel then
		snapLabel.Text = s.snap == "grid" and "GRID" or "FREE"
	end
	for _, entry in cards do
		updateCard(entry)
	end
	BuildMenu.refreshDetail()
	BuildMenu.refreshTooltip()
end

function BuildMenu.refreshTooltip()
	local s = Placement.state()
	local def = s.def
	if not root.Visible or (not def and not s.tool) then
		tooltip.Visible = false
		return
	end
	tooltip.Visible = true
	local cash = ClientState.get("cash") or 0
	local snap = s.snap == "grid" and "G FREE" or "G GRID"
	if def and def.id == "road" and not s.moving then
		local road = s.road
		if road then
			refs.tipName.Text = ("ROAD  ·  %d STUDS"):format(math.floor(road.len + 0.5))
			refs.tipPrice.Text = "$" .. Format.commas(road.cost)
			refs.tipPrice.TextColor3 = road.valid and C.Good or C.Bad
			refs.tipHint.Text = "CLICK NEXT POINT  ·  SAME SPOT / RMB / Q FINISH  ·  SHIFT 15°"
		else
			refs.tipName.Text = "ROAD"
			refs.tipPrice.Text = ("$%s / %d studs"):format(Format.commas(def.cost), def.size[2] * Config.CellSize)
			refs.tipPrice.TextColor3 = cash >= def.cost and C.Good or C.Bad
			refs.tipHint.Text = "CLICK START, THEN CLICK OR DRAG TO DRAW  ·  ENDS SNAP TO ROADS  ·  " .. snap
		end
	elseif def then
		refs.tipName.Text = ("%s%s  ·  %d°"):format(s.moving and "MOVING " or "", string.upper(def.name), math.floor(s.rotation + 0.5) % 360)
		refs.tipPrice.Text = s.moving and "" or ("$" .. Format.commas(def.cost))
		refs.tipPrice.TextColor3 = cash >= def.cost and C.Good or C.Bad
		local rot = s.snap == "grid" and "R ROTATE 90°" or "R / SHIFT+R ROTATE 15°  ·  AUTO-ALIGNS TO ROADS (ALT OFF)"
		refs.tipHint.Text = (s.drag and "HOLD LMB + DRAG A ROW" or "LMB PLACE") .. "  ·  " .. rot .. "  ·  " .. snap .. "  ·  Q CANCEL"
	else
		refs.tipName.Text = s.tool == "delete" and "DEMOLISH MODE" or "MOVE MODE"
		refs.tipPrice.Text = ""
		refs.tipHint.Text = s.tool == "delete" and "CLICK A BUILDING  ·  2 EXIT" or "CLICK A BUILDING  ·  5 EXIT"
	end
end

---------------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------------
function BuildMenu.open()
	if ClientState.mode == "war" then
		return
	end
	root.Visible = true
	root.Position = UDim2.new(0.5, 0, 1, 40)
	Lib.tween(root, 0.22, { Position = UDim2.new(0.5, 0, 1, -12) }, Enum.EasingStyle.Quint)
	ClientState.setMode("build")
	Sounds.play("Open", 1.1)
	renderTabs()
	BuildMenu.renderFactions()
	renderCards()
	refreshTools()
end

function BuildMenu.close()
	Placement.cancel()
	root.Visible = false
	tooltip.Visible = false
	if ClientState.mode == "build" then
		ClientState.setMode("play")
	end
end

function BuildMenu.toggle()
	if ClientState.mode == "war" then
		Hub.call("goHome")
	elseif root.Visible then
		BuildMenu.close()
	else
		BuildMenu.open()
	end
end

function BuildMenu.init(gui: GuiObject)
	root = Lib.panel({
		Name = "BuildMenu",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(W, H),
		Visible = false,
		Parent = gui,
	})
	Lib.brackets(root, C.Accent, 14, 2, 4)
	Lib.hazard({ Position = UDim2.fromOffset(0, 0), Size = UDim2.new(0, 160, 0, 4), BackgroundTransparency = 0.1, Parent = root }, C.Accent, C.Panel, 9)

	-- department column
	local rail = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(LEFT, H - 24),
		Parent = root,
	}, { Lib.list("y", 8) })
	Lib.caption("Department", { LayoutOrder = 0, Parent = rail })
	for i, c in Buildings.Categories do
		local tint = c.id == "Civilian" and C.Civil or C.Military
		local tile = Lib.button({
			Name = c.id,
			Size = UDim2.fromOffset(LEFT, 92),
			BackgroundColor3 = C.Raised,
			LayoutOrder = i,
			Parent = rail,
			Activated = function()
				setCategory(c.id)
			end,
		}, { Lib.corner(4), Lib.stroke(C.LineSoft) })
		local ic = Icons.get(c.id == "Civilian" and "house" or "helmet", 34, tint)
		ic.Position = UDim2.fromOffset(14, 14)
		ic.Parent = tile
		Lib.display({ Text = c.id == "Civilian" and "CIVIL" or "MILITARY", TextSize = 17, Position = UDim2.fromOffset(14, 54), Size = UDim2.new(1, -20, 0, 20), Parent = tile })
		Lib.text({ Text = c.id == "Civilian" and "economy & people" or "arms & defense", TextSize = 11, TextColor3 = C.Muted, Position = UDim2.fromOffset(14, 72), Size = UDim2.new(1, -20, 0, 14), Parent = tile })
		refs["cat_" .. c.id] = tile
	end

	-- main column
	local mainW = W - LEFT - RIGHT - 48
	local main = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(LEFT + 24, 10),
		Size = UDim2.fromOffset(mainW, H - 20),
		Parent = root,
	})
	refs.tabs = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -310, 0, 32), Parent = main }, { Lib.list("x", 2) })
	refs.factions = New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 3),
		Size = UDim2.fromOffset(300, 26),
		Parent = main,
	}, { Lib.list("x", 4, Enum.HorizontalAlignment.Right) })
	Lib.divider({ Position = UDim2.fromOffset(0, 34), Parent = main })
	refs.crumb = Lib.caption("", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 14), Parent = main })
	refs.scroller = Lib.scroll({
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 172),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		Parent = main,
	}, { Lib.list("x", 8), Lib.pad(2, 2, 6, 2) })

	-- detail column
	local right = Lib.inset({
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(RIGHT, H - 24),
		Parent = root,
	})
	Lib.stroke(C.LineSoft, 1, 0).Parent = right
	buildRight(right)

	-- placement hint bar
	tooltip = Lib.panel({
		Name = "PlaceHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -H - 24),
		Size = UDim2.fromOffset(520, 42),
		Visible = false,
		Parent = gui,
	})
	Lib.brackets(tooltip, C.Accent, 8, 2, 3)
	refs.tipName = Lib.display({ Text = "", TextSize = 15, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.5, -14, 1, 0), Parent = tooltip })
	refs.tipPrice = Lib.display({ Text = "", TextSize = 15, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.fromOffset(110, 42), TextXAlignment = Enum.TextXAlignment.Right, Parent = tooltip })
	refs.tipHint = Lib.text({ Text = "", FontFace = Theme.Font.Mono, TextSize = 10, TextColor3 = C.Muted, Position = UDim2.new(0.42, 0, 0, 0), Size = UDim2.new(0.58, -130, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, Parent = tooltip })

	Placement.onChanged(refreshTools)
	RunService.RenderStepped:Connect(function()
		if root.Visible and Placement.state().drawing then
			BuildMenu.refreshTooltip()
		end
	end)
	ClientState.onAny(function(patch)
		if not root.Visible then
			return
		end
		if patch.researched or patch.passes then
			BuildMenu.renderFactions()
			renderCards()
		elseif patch.cash then
			for _, entry in cards do
				updateCard(entry)
			end
			BuildMenu.refreshDetail()
			BuildMenu.refreshTooltip()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.B then
			BuildMenu.toggle()
		elseif input.KeyCode == Enum.KeyCode.X and root.Visible then
			BuildMenu.close()
		end
	end)

	Hub.toggleBuild = BuildMenu.toggle
	Hub.openBuild = BuildMenu.open
	Hub.closeBuild = BuildMenu.close
	Hub.describeBuilding = BuildMenu.describe
	setCategory("Civilian")
end

return BuildMenu
