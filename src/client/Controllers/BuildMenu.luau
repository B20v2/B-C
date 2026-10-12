--[[
	BuildMenu
	The bottom build bar:
	  [Civilian/Military rail] [tabs, breadcrumb, faction toggle, item cards]
	  [tools: Delete 2, Undo 3, Drag 4, Move 5, Rotate 6, close X + selected detail]
	plus the hover tooltip ("SRBM Launcher $12000 · LMB place · R turn").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
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

local BuildMenu = {}

local root: Frame
local tooltip: Frame
local category = "Civilian"
local tab = "Housing"
local faction = "Standard"
local refs: { [string]: any } = {}
local cards: { [string]: { btn: TextButton, lock: Frame, price: Frame, def: any } } = {}
local thumbs: { [string]: Model } = {}

local W, H = 1480, 218

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
		return ("Requires 1 %s per launch | max %d shared · %ds reload"):format(def.launcher, w and w.stockCap or 60, def.reload or 20)
	end
	if def.airDefense then
		local ad = def.airDefense
		return ("Range %d · %d%% hit chance · %ds reload"):format(ad.range, math.floor(ad.chance * 100), ad.reload)
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
		table.insert(bits, "Builds weapons & vehicles")
	end
	if def.rpOut then
		table.insert(bits, ("+%d RP/min"):format(def.rpOut))
	end
	if def.income then
		table.insert(bits, ("+$%s per pay"):format(Format.commas(def.income)))
	end
	if def.service then
		table.insert(bits, ("Serves %s"):format(Format.short(def.service.serves)))
	end
	if def.storage then
		table.insert(bits, ("+%s storage"):format(Format.short((def.storage.oil or 0) + (def.storage.steel or 0))))
	end
	if def.depot then
		table.insert(bits, ("+%d army size"):format(def.depot))
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

local function tinyLock(color: Color3): Frame
	local f = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(10, 12) })
	New("Frame", {
		BackgroundColor3 = color,
		Position = UDim2.fromOffset(0, 5),
		Size = UDim2.fromOffset(10, 7),
		Parent = f,
	}, { Lib.corner(2) })
	local shackle = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(2, 0),
		Size = UDim2.fromOffset(6, 8),
		Parent = f,
	}, { Lib.round() })
	Lib.stroke(color, 1.5).Parent = shackle
	return f
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
	stroke.Color = isSel and Theme.Color.Teal or Theme.Color.CardStroke
	stroke.Thickness = isSel and 2 or 1
	Lib.setButtonColor(entry.btn, isSel and Theme.Color.AccentSoft or Theme.Color.Card)
	local afford = (ClientState.get("cash") or 0) >= def.cost
	local label = entry.price:FindFirstChild("Label") :: TextLabel
	label.TextColor3 = afford and Theme.Color.Good or Theme.Color.Bad
end

local function makeCard(def, order: number): TextButton
	local btn = Lib.button({
		Name = def.id,
		Size = UDim2.fromOffset(150, 118),
		BackgroundColor3 = Theme.Color.Card,
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
	}, { Lib.corner(Theme.Radius.Card), Lib.stroke(Theme.Color.CardStroke) })
	local art = New("Frame", {
		BackgroundColor3 = Theme.Color.CivilSoft,
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 0, 62),
		Parent = btn,
	}, { Lib.corner(6) })
	art.BackgroundColor3 = category == "Military" and Color3.fromRGB(232, 238, 246) or Theme.Color.CivilSoft
	Lib.viewport(thumbModel(def), { Parent = art }, 40)
	local lock = New("Frame", {
		Name = "Lock",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(52, 18),
		Visible = false,
		Parent = btn,
	}, {
		Lib.corner(4),
		Lib.text({
			Text = "Locked",
			TextColor3 = Theme.Color.Bad,
			TextSize = Theme.TextSize.Tiny,
			FontFace = Theme.Font.Bold,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
	})
	Lib.text({
		Text = def.name,
		FontFace = Theme.Font.Bold,
		TextSize = Theme.TextSize.Small,
		Position = UDim2.fromOffset(10, 70),
		Size = UDim2.new(1, -16, 0, 18),
		Parent = btn,
	})
	local chips = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 90),
		Size = UDim2.new(1, -16, 0, 22),
		Parent = btn,
	}, { Lib.list("x", 6) })
	local price = Lib.chip("$" .. Format.commas(def.cost), Theme.Color.GoodSoft, Theme.Color.Good, { LayoutOrder = 1 })
	price.Parent = chips
	if def.buildTime > 0 then
		Lib.chip(Format.duration(def.buildTime), Theme.Color.TimeSoft, Theme.Color.Time, { LayoutOrder = 2 }).Parent = chips
	end
	cards[def.id] = { btn = btn, lock = lock, price = price, def = def }
	updateCard(cards[def.id])
	btn.MouseEnter:Connect(function()
		refs.hoverDef = def
		BuildMenu.refreshTooltip()
	end)
	btn.MouseLeave:Connect(function()
		if refs.hoverDef == def then
			refs.hoverDef = nil
			BuildMenu.refreshTooltip()
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
	refs.crumb.Text = ("%s / %s (%d)"):format(category, tab, #list)
	if #list == 0 then
		Lib.text({
			Text = "Nothing here yet.",
			TextColor3 = Theme.Color.Muted,
			Size = UDim2.fromOffset(300, 40),
			Parent = refs.scroller,
		})
	end
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
				Lib.button({
					Text = t,
					FontFace = Theme.Font.Semi,
					TextSize = Theme.TextSize.Small,
					BackgroundColor3 = active and Theme.Color.TabActive or Theme.Color.Tab,
					Size = UDim2.fromOffset(98, 32),
					LayoutOrder = i,
					Parent = refs.tabs,
					Activated = function()
						tab = t
						faction = "Standard"
						renderTabs()
						BuildMenu.renderFactions()
						renderCards()
					end,
				}, { Lib.corner(6), active and Lib.stroke(Theme.Color.Teal, 1, 0.4) or nil })
			end
		end
	end
	for _, c in Buildings.Categories do
		local tile = refs["cat_" .. c.id] :: TextButton
		local active = c.id == category
		Lib.setButtonColor(tile, active and (c.id == "Civilian" and Theme.Color.CivilSoft or Theme.Color.MilitarySoft) or Theme.Color.Card)
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
			Size = UDim2.fromOffset(86, 26),
			BackgroundColor3 = active and Theme.Color.Card or Theme.Color.CardAlt,
			LayoutOrder = i,
			Parent = refs.factions,
			Activated = function()
				if locked and passKey then
					local p = Products.pass(passKey)
					Notifications.show(("%s requires the %s"):format(f, p and p.name or "pack"), "info")
					Hub.call("openShop", "Passes")
					return
				end
				faction = f
				BuildMenu.renderFactions()
				renderCards()
			end,
		}, { Lib.corner(5), Lib.list("x", 5, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
		Lib.text({
			Text = f,
			TextSize = Theme.TextSize.Small,
			FontFace = active and Theme.Font.Bold or Theme.Font.Semi,
			TextColor3 = active and Theme.Color.Text or Theme.Color.Muted,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			LayoutOrder = 1,
			Parent = btn,
		})
		if locked then
			local l = tinyLock(Theme.Color.Amber)
			l.LayoutOrder = 2
			l.Parent = btn
		end
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
-- Right panel
---------------------------------------------------------------------------
local function toolButton(parent: Instance, label: string, key: string, icon: string?, order: number, onClick: () -> ()): TextButton
	local btn = Lib.button({
		Name = label,
		Size = UDim2.fromOffset(92, 30),
		BackgroundColor3 = Theme.Color.Card,
		LayoutOrder = order,
		Parent = parent,
		Activated = onClick,
	}, { Lib.corner(6), Lib.stroke(Theme.Color.CardStroke) })
	local x = 8
	if icon then
		local ic = Icons.get(icon, 14, Theme.Color.Text)
		ic.Position = UDim2.fromOffset(7, 8)
		ic.Parent = btn
		x = 26
	end
	Lib.text({
		Text = label,
		TextSize = Theme.TextSize.Small,
		FontFace = Theme.Font.Semi,
		Position = UDim2.fromOffset(x, 0),
		Size = UDim2.new(1, -x - 18, 1, 0),
		Parent = btn,
	})
	if key ~= "" then
		Lib.text({
			Text = key,
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = Theme.Color.Muted,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 0),
			Size = UDim2.new(0, 12, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = btn,
		})
	end
	return btn
end

local function buildRight(parent: Frame)
	local tools = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 0, 68),
		Parent = parent,
	}, { Lib.grid(UDim2.fromOffset(92, 30), 6) })
	refs.toolDelete = toolButton(tools, "Delete", "2", "trash", 1, function()
		Placement.setTool("delete")
	end)
	refs.toolUndo = toolButton(tools, "Undo", "3", "undo", 2, function()
		Placement.undo()
	end)
	refs.toolDrag = toolButton(tools, "Drag", "4", nil, 3, function()
		Placement.toggleDrag()
	end)
	refs.toolMove = toolButton(tools, "Move", "5", nil, 4, function()
		Placement.setTool("move")
	end)
	refs.toolRotate = toolButton(tools, "Rotate", "6", nil, 5, function()
		Placement.rotate()
	end)
	local close = Lib.button({
		Name = "Close",
		Size = UDim2.fromOffset(30, 30),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		BackgroundColor3 = Theme.Color.Card,
		Parent = parent,
		Activated = function()
			BuildMenu.close()
		end,
	}, { Lib.corner(6), Lib.stroke(Theme.Color.CardStroke) })
	local x = Icons.close(12, Theme.Color.Text)
	x.AnchorPoint = Vector2.new(0.5, 0.5)
	x.Position = UDim2.fromScale(0.5, 0.5)
	x.Parent = close
	tools.Size = UDim2.new(1, -54, 0, 68)

	local detail = Lib.card({
		Position = UDim2.fromOffset(8, 82),
		Size = UDim2.new(1, -16, 0, 76),
		Parent = parent,
	})
	local art = New("Frame", {
		BackgroundColor3 = Theme.Color.CivilSoft,
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(70, 64),
		Parent = detail,
	}, { Lib.corner(6) })
	refs.detailArt = art
	refs.detailName = Lib.text({ Text = "Nothing selected", FontFace = Theme.Font.Bold, TextSize = Theme.TextSize.Small, Position = UDim2.fromOffset(84, 6), Size = UDim2.new(1, -170, 0, 18), Parent = detail })
	refs.detailPrice = Lib.text({ Text = "", FontFace = Theme.Font.Bold, TextSize = Theme.TextSize.Small, TextColor3 = Theme.Color.Good, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), Size = UDim2.fromOffset(80, 18), TextXAlignment = Enum.TextXAlignment.Right, Parent = detail })
	refs.detailReq = Lib.text({ Text = "Pick something to build", TextSize = Theme.TextSize.Tiny, TextColor3 = Theme.Color.Time, Position = UDim2.fromOffset(84, 26), Size = UDim2.new(1, -92, 0, 28), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Parent = detail })
	refs.detailTime = Lib.text({ Text = "", TextSize = Theme.TextSize.Tiny, TextColor3 = Theme.Color.Muted, Position = UDim2.fromOffset(84, 54), Size = UDim2.new(1, -92, 0, 16), Parent = detail })

	local footer = New("Frame", {
		BackgroundColor3 = Theme.Color.CardAlt,
		Position = UDim2.fromOffset(8, 166),
		Size = UDim2.new(1, -16, 0, 26),
		Parent = parent,
	}, { Lib.corner(6) })
	refs.selectedLabel = Lib.text({ Text = "Selected: none", TextSize = Theme.TextSize.Tiny, TextColor3 = Theme.Color.TextSoft, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), Parent = footer })
end

local function refreshTools()
	local s = Placement.state()
	local function mark(btn: TextButton, on: boolean)
		Lib.setButtonColor(btn, on and Theme.Color.TabActive or Theme.Color.Card)
	end
	mark(refs.toolDelete, s.tool == "delete")
	mark(refs.toolMove, s.tool == "move")
	mark(refs.toolDrag, s.drag)
	local def = s.def
	Lib.clear(refs.detailArt)
	if def then
		Lib.viewport(thumbModel(def), { Parent = refs.detailArt }, 40)
		refs.detailName.Text = def.name
		refs.detailPrice.Text = "$" .. Format.commas(def.cost)
		refs.detailReq.Text = BuildMenu.describe(def)
		refs.detailTime.Text = def.buildTime > 0 and ("Builds in " .. Format.duration(def.buildTime)) or "Builds instantly"
		refs.selectedLabel.Text = (s.moving and "Moving: " or "Selected: ") .. def.name .. (s.drag and "  (drag to place a line)" or "")
	else
		refs.detailName.Text = s.tool == "delete" and "Demolish" or (s.tool == "move" and "Move" or "Nothing selected")
		refs.detailPrice.Text = ""
		refs.detailReq.Text = s.tool == "delete" and "Click a building to remove it (50% refund, 100% while under construction)"
			or (s.tool == "move" and "Click a building, then click its new spot" or "Pick something to build")
		refs.detailTime.Text = ""
		refs.selectedLabel.Text = s.tool and ("Tool: " .. s.tool) or "Selected: none"
	end
	for _, entry in cards do
		updateCard(entry)
	end
	BuildMenu.refreshTooltip()
end

function BuildMenu.refreshTooltip()
	local s = Placement.state()
	local def = refs.hoverDef or s.def
	if not def or not root.Visible then
		tooltip.Visible = false
		return
	end
	tooltip.Visible = true
	refs.tipName.Text = def.name
	local afford = (ClientState.get("cash") or 0) >= def.cost
	refs.tipPrice.Text = "$" .. Format.commas(def.cost)
	refs.tipPrice.TextColor3 = afford and Theme.Color.Good or Theme.Color.Bad
	local ok, reason = lockReason(def)
	refs.tipHint.Text = ok and (s.drag and "LMB drag   R turn   Q cancel" or "LMB place   R turn   Q cancel") or (reason or "Locked")
	if not ok and def.research then
		local r = Research.get(def.research)
		refs.tipHint.Text = "Research: " .. (r and r.name or def.research)
	elseif not ok and def.pass then
		local p = Products.pass(def.pass)
		refs.tipHint.Text = "Requires " .. (p and p.name or def.pass)
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

	-- category rail
	local rail = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(84, H - 20),
		Parent = root,
	}, { Lib.list("y", 8) })
	for i, c in Buildings.Categories do
		local tile = Lib.button({
			Name = c.id,
			Size = UDim2.fromOffset(84, (H - 28) / 2),
			BackgroundColor3 = Theme.Color.Card,
			LayoutOrder = i,
			Parent = rail,
			Activated = function()
				setCategory(c.id)
			end,
		}, { Lib.corner(8), Lib.stroke(Theme.Color.CardStroke) })
		local color = c.id == "Civilian" and Theme.Color.Civil or Theme.Color.Military
		local box = New("Frame", {
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 12),
			Size = UDim2.fromOffset(42, 42),
			Parent = tile,
		}, { Lib.corner(8) })
		local ic = Icons.get(c.id == "Civilian" and "house" or "helmet", 28, Color3.new(1, 1, 1))
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.Parent = box
		Lib.text({
			Text = c.id,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Color.TextSoft,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 0, 1, -28),
			Size = UDim2.new(1, 0, 0, 18),
			Parent = tile,
		})
		refs["cat_" .. c.id] = tile
	end

	-- main area
	local mainW = W - 104 - 330
	local main = Lib.card({
		BackgroundColor3 = Theme.Color.CardAlt,
		Position = UDim2.fromOffset(104, 10),
		Size = UDim2.fromOffset(mainW, H - 20),
		Parent = root,
	})
	refs.tabs = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 32),
		Parent = main,
	}, { Lib.list("x", 8) })
	refs.crumb = Lib.caption("", {
		Position = UDim2.fromOffset(12, 46),
		Size = UDim2.new(0.5, 0, 0, 18),
		TextSize = Theme.TextSize.Small,
		Parent = main,
	})
	refs.factions = New("Frame", {
		BackgroundColor3 = Theme.Color.CardAlt,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 42),
		Size = UDim2.fromOffset(276, 30),
		Parent = main,
	}, { Lib.corner(6), Lib.stroke(Theme.Color.CardStroke), Lib.pad(2), Lib.list("x", 4) })
	refs.scroller = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 72),
		Size = UDim2.new(1, -20, 0, 124),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Color.Faint,
		BorderSizePixel = 0,
		Parent = main,
	}, { Lib.list("x", 8), Lib.pad(2, 2, 6, 2) })

	-- right panel
	local right = Lib.card({
		BackgroundColor3 = Theme.Color.CardAlt,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(316, H - 20),
		Parent = root,
	})
	buildRight(right)

	-- tooltip
	tooltip = Lib.card({
		Name = "Tooltip",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -H - 22),
		Size = UDim2.fromOffset(320, 60),
		Visible = false,
		Parent = gui,
	}, { Lib.pad(8, 14) })
	refs.tipName = Lib.text({ Text = "", FontFace = Theme.Font.Bold, Size = UDim2.new(1, -90, 0, 22), Parent = tooltip })
	refs.tipPrice = Lib.text({ Text = "", FontFace = Theme.Font.Bold, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(90, 22), TextXAlignment = Enum.TextXAlignment.Right, Parent = tooltip })
	refs.tipHint = Lib.text({ Text = "", TextSize = Theme.TextSize.Small, TextColor3 = Theme.Color.Muted, Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 18), Parent = tooltip })

	Placement.onChanged(refreshTools)
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
