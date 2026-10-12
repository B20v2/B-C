--[[
	ResearchUI - Tech Tree
	Full-screen window: summary strip (RP, hits, current project), branch
	tabs (CIVIL / MILITARY), a node graph with connector lines between
	prerequisites, and a detail pane showing what a node unlocks.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Research = require(Shared.Catalog.Research)
local Buildings = require(Shared.Catalog.Buildings)
local Weapons = require(Shared.Catalog.Weapons)
local Units = require(Shared.Catalog.Units)
local Format = require(Shared.Util.Format)
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

local New = Lib.New
local C = Theme.Color

local ResearchUI = {}

local NODE_W, NODE_H = 168, 84
local GAP_X, GAP_Y = 48, 22

local function nodeState(def): (string, string?)
	local d = ClientState.data
	local researched = d.researched or {}
	if researched[def.id] then
		return "done", nil
	end
	local active = d.research
	if active and active.id == def.id then
		return "active", nil
	end
	for _, req in def.requires do
		if not researched[req] then
			local r = Research.get(req)
			return "locked", "Needs " .. (r and r.name or req)
		end
	end
	local hits = (d.stats or {}).Hits or 0
	if def.hits and hits < def.hits then
		return "locked", ("Needs %d hits (%d)"):format(def.hits, hits)
	end
	return "available", nil
end

local function unlocksOf(id: string): { string }
	local out = {}
	for _, b in Buildings.all() do
		if b.research == id then
			table.insert(out, b.name)
		end
	end
	for _, w in Weapons.all() do
		if w.research == id then
			table.insert(out, w.name)
		end
	end
	for _, u in Units.all() do
		if u.research == id then
			table.insert(out, u.name)
		end
	end
	return out
end

local function nodePos(def): Vector2
	return Vector2.new(16 + (def.col - 1) * (NODE_W + GAP_X), 16 + (def.row - 1) * (NODE_H + GAP_Y))
end

-- Axis-aligned connector segment (rotated frames escape scroll clipping).
local function line(parent: Instance, a: Vector2, b: Vector2, color: Color3, thickness: number?)
	local t = thickness or 2
	local x0, x1 = math.min(a.X, b.X), math.max(a.X, b.X)
	local y0, y1 = math.min(a.Y, b.Y), math.max(a.Y, b.Y)
	return New("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(x0 - t / 2, y0 - t / 2),
		Size = UDim2.fromOffset(math.max(x1 - x0, 0) + t, math.max(y1 - y0, 0) + t),
		ZIndex = 1,
		Parent = parent,
	})
end

function ResearchUI.open(focusId: string?)
	local win = Modal.open("Tech Tree", "Unlock new buildings, weapons and vehicles", 1240, 720)
	local ic = Icons.flask(34, C.Teal)
	ic.Position = UDim2.fromOffset(9, 7)
	ic.Parent = win.iconHolder

	local d0 = ClientState.data
	local branch = "Civil"
	if focusId then
		local f = Research.get(focusId)
		if f then
			branch = f.branch
		end
	elseif d0.researched and d0.researched.urban_planning and not d0.researched.military_doctrine then
		branch = "Military"
	end
	local selected: string? = focusId

	-- summary strip
	local top = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 70), Parent = win.body }, { Lib.list("x", 8) })
	local function summary(caption: string, order: number, width: number, color: Color3): TextLabel
		local card = Lib.card({ Size = UDim2.new(0, width, 1, 0), LayoutOrder = order, Parent = top }, { Lib.pad(9, 12) })
		Lib.caption(caption, { Parent = card })
		return Lib.display({ Text = "-", TextSize = 22, TextColor3 = color, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 28), Parent = card })
	end
	local rpLabel = summary("Research points", 1, 220, C.Teal)
	local hitsLabel = summary("Confirmed hits", 2, 160, C.Military)
	local activeCard = Lib.card({ Size = UDim2.new(1, -396, 1, 0), LayoutOrder = 3, Parent = top }, { Lib.pad(9, 12) })
	Lib.caption("Current project", { Parent = activeCard })
	local activeName = Lib.display({ Text = "IDLE", TextSize = 17, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, -160, 0, 22), Parent = activeCard })
	local activeBar = Lib.progress({ Segments = 20, Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, -160, 0, 6), Parent = activeCard })
	local activeTime = Lib.text({ Text = "", FontFace = Theme.Font.Mono, TextSize = 11, TextColor3 = C.Muted, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -160, 0, 18), Size = UDim2.fromOffset(120, 16), TextXAlignment = Enum.TextXAlignment.Right, Parent = activeCard })
	Lib.button({
		Variant = "gold",
		Text = "FINISH NOW",
		TextSize = 13,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(140, 38),
		Parent = activeCard,
		Activated = function()
			Hub.call("buyProduct", "InstantResearch")
		end,
	})

	-- branch tabs
	local tabs = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, -330, 0, 32), Parent = win.body }, { Lib.list("x", 6) })
	-- tree canvas + detail pane
	local canvas = Lib.inset({ Position = UDim2.fromOffset(0, 118), Size = UDim2.new(1, -330, 1, -118), ClipsDescendants = true, Parent = win.body })
	local scroll = Lib.scroll({
		ScrollingDirection = Enum.ScrollingDirection.XY,
		AutomaticCanvasSize = Enum.AutomaticSize.XY,
		Parent = canvas,
	})
	local detail = Lib.card({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 80), Size = UDim2.new(0, 318, 1, -80), Parent = win.body }, { Lib.pad(14) })

	local nodes: { [string]: { btn: TextButton, status: TextLabel, bar: Lib.Progress, stroke: UIStroke } } = {}
	local links: { { frame: Frame, from: string, to: string } } = {}

	local renderDetail
	local function renderTree()
		Lib.clear(scroll)
		table.clear(nodes)
		table.clear(links)
		local area = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(10, 10), Parent = scroll })
		local maxX, maxY = 0, 0
		for _, def in Research.all() do
			if def.branch == branch then
				local p = nodePos(def)
				maxX = math.max(maxX, p.X + NODE_W + 16)
				maxY = math.max(maxY, p.Y + NODE_H + 16)
				for _, req in def.requires do
					local r = Research.get(req)
					if r and r.branch == branch then
						local a = nodePos(r) + Vector2.new(NODE_W, NODE_H / 2)
						local b = p + Vector2.new(0, NODE_H / 2)
						local midX = (a.X + b.X) / 2
						-- elbow connector: out, across, in
						local f1 = line(area, a, Vector2.new(midX, a.Y), C.Line)
						local f2 = line(area, Vector2.new(midX, a.Y), Vector2.new(midX, b.Y), C.Line)
						local f3 = line(area, Vector2.new(midX, b.Y), b, C.Line)
						for _, f in { f1, f2, f3 } do
							table.insert(links, { frame = f, from = req, to = def.id })
						end
					end
				end
			end
		end
		area.Size = UDim2.fromOffset(maxX, maxY)
		for _, def in Research.all() do
			if def.branch == branch then
				local p = nodePos(def)
				local btn = Lib.button({
					Name = def.id,
					Position = UDim2.fromOffset(p.X, p.Y),
					Size = UDim2.fromOffset(NODE_W, NODE_H),
					BackgroundColor3 = C.Raised,
					ZIndex = 2,
					Parent = area,
					Activated = function()
						selected = def.id
						renderDetail()
						ResearchUI.refreshNodes()
					end,
				}, { Lib.corner(4), Lib.pad(8, 10) })
				local stroke = Lib.stroke(C.LineSoft, 1, 0)
				stroke.Parent = btn
				Lib.display({ Text = string.upper(def.name), TextSize = 13, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, 0, 0, 32), ZIndex = 3, Parent = btn })
				Lib.text({
					Text = ("%s RP · %s"):format(Format.short(def.rp), Format.cash(def.cash)),
					FontFace = Theme.Font.Mono,
					TextSize = 10,
					TextColor3 = C.Info,
					Position = UDim2.fromOffset(0, 34),
					Size = UDim2.new(1, 0, 0, 13),
					ZIndex = 3,
					Parent = btn,
				})
				local status = Lib.display({ Text = "", TextSize = 10, Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 13), ZIndex = 3, Parent = btn })
				local bar = Lib.progress({ Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 3), ZIndex = 3, Parent = btn })
				nodes[def.id] = { btn = btn, status = status, bar = bar, stroke = stroke }
			end
		end
		ResearchUI.refreshNodes()
	end

	local function renderTabs()
		Lib.clear(tabs)
		for i, b in { "Civil", "Military" } do
			local active = b == branch
			Lib.button({
				Name = b,
				Variant = active and "primary" or "secondary",
				Text = string.upper(b),
				TextSize = 13,
				Size = UDim2.fromOffset(130, 32),
				LayoutOrder = i,
				Parent = tabs,
				Activated = function()
					branch = b
					renderTabs()
					renderTree()
				end,
			})
		end
	end

	renderDetail = function()
		Lib.clear(detail)
		local def = selected and Research.get(selected)
		if not def then
			Lib.display({ Text = "SELECT A PROJECT", TextSize = 18, Parent = detail })
			Lib.text({ Text = "Click a node to see what it unlocks.", TextColor3 = C.Muted, TextSize = 13, Position = UDim2.fromOffset(0, 28), Parent = detail })
			return
		end
		local st, reason = nodeState(def)
		Lib.caption(def.branch .. " research", { TextColor3 = C.Accent, Parent = detail })
		Lib.display({ Text = string.upper(def.name), TextSize = 21, TextWrapped = true, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 50), TextYAlignment = Enum.TextYAlignment.Top, Parent = detail })
		Lib.text({ Text = def.desc, TextSize = 13, TextColor3 = C.TextSoft, TextWrapped = true, Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 0, 36), TextYAlignment = Enum.TextYAlignment.Top, Parent = detail })
		local costs = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 108), Size = UDim2.new(1, 0, 0, 22), Parent = detail }, { Lib.list("x", 6) })
		Lib.chip(Format.short(def.rp) .. " RP", C.TealSoft, C.Teal, { Parent = costs })
		Lib.chip(Format.cash(def.cash), C.GoodSoft, C.Good, { Parent = costs })
		Lib.chip(Format.duration(def.time), C.InfoSoft, C.Info, { Parent = costs })
		if def.hits then
			Lib.chip(("%d HITS"):format(def.hits), C.BadSoft, C.Military, { Parent = costs })
		end
		Lib.caption("Unlocks", { Position = UDim2.fromOffset(0, 142), Parent = detail })
		local list = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 160), Size = UDim2.new(1, 0, 1, -230), Parent = detail }, { Lib.list("y", 4) })
		for i, name in unlocksOf(def.id) do
			local row = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = i, Parent = list }, { Lib.list("x", 8, nil, Enum.VerticalAlignment.Center) })
			New("Frame", { BackgroundColor3 = C.Accent, Size = UDim2.fromOffset(5, 5), LayoutOrder = 1, Parent = row })
			Lib.text({ Text = name, TextSize = 13, FontFace = Theme.Font.BodyBold, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = 2, Parent = row })
		end
		local label, variant = "RESEARCH", "primary"
		if st == "done" then
			label, variant = "RESEARCHED", "good"
		elseif st == "active" then
			label, variant = "IN PROGRESS", "secondary"
		elseif st == "locked" then
			label, variant = string.upper(reason or "LOCKED"), "ghost"
		elseif ClientState.get("research") then
			label, variant = "ANOTHER PROJECT RUNNING", "ghost"
		end
		Lib.button({
			Name = "StartResearch",
			Variant = variant,
			Text = label,
			TextSize = 13,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 44),
			Parent = detail,
			Activated = function()
				if st ~= "available" then
					if reason then
						Notifications.show(reason, "info")
					end
					return
				end
				local res = Net.request("StartResearch", def.id)
				if res.ok then
					Sounds.play("Success", 1.2)
					task.delay(0.3, renderDetail)
				elseif res.err then
					Notifications.show(res.err, "bad")
				end
			end,
		})
	end

	function ResearchUI.refreshNodes()
		local d = ClientState.data
		local active = d.research
		local now = Lib.serverNow()
		for id, n in nodes do
			local def = Research.get(id)
			if def then
				local st, reason = nodeState(def)
				local isSel = selected == id
				if st == "done" then
					Lib.setButtonColor(n.btn, C.GoodSoft)
					n.status.Text = "RESEARCHED"
					n.status.TextColor3 = C.Good
					n.bar.frame.Visible = false
					n.stroke.Color = C.Good
				elseif st == "active" and active then
					Lib.setButtonColor(n.btn, C.AccentSoft)
					n.status.Text = "IN PROGRESS"
					n.status.TextColor3 = C.Accent
					n.bar.frame.Visible = true
					n.bar.set((now - active.startAt) / math.max(1, active.finishAt - active.startAt), C.Accent)
					n.stroke.Color = C.Accent
				elseif st == "available" then
					Lib.setButtonColor(n.btn, C.Raised)
					local affordable = (d.rp or 0) >= def.rp and (d.cash or 0) >= def.cash
					n.status.Text = affordable and "AVAILABLE" or "NEED RP / CASH"
					n.status.TextColor3 = affordable and C.Teal or C.Gold
					n.bar.frame.Visible = false
					n.stroke.Color = C.Teal
				else
					Lib.setButtonColor(n.btn, C.Inset)
					n.status.Text = string.upper(reason or "LOCKED")
					n.status.TextColor3 = C.Faint
					n.bar.frame.Visible = false
					n.stroke.Color = C.LineSoft
				end
				if isSel then
					n.stroke.Color = C.Gold
					n.stroke.Thickness = 2
				else
					n.stroke.Thickness = 1
				end
			end
		end
		for _, l in links do
			local done = (d.researched or {})[l.from] == true
			l.frame.BackgroundColor3 = done and C.Teal or C.Line
			l.frame.BackgroundTransparency = done and 0 or 0.3
		end
	end

	local function refreshSummary()
		local d = ClientState.data
		rpLabel.Text = ("%s  +%s/m"):format(Format.short(d.rp or 0), Format.short(d.rpRate or 0))
		hitsLabel.Text = Format.commas(((d.stats or {}).Hits) or 0)
		local active = d.research
		local now = Lib.serverNow()
		if active then
			local def = Research.get(active.id)
			activeName.Text = string.upper(def and def.name or active.id)
			activeBar.set((now - active.startAt) / math.max(1, active.finishAt - active.startAt), C.Accent)
			activeTime.Text = Format.clock(active.finishAt - now)
		else
			activeName.Text = (d.rpRate or 0) <= 0 and "IDLE · BUILD A RESEARCH LAB" or "IDLE · PICK A PROJECT"
			activeBar.set(0)
			activeTime.Text = ""
		end
	end

	renderTabs()
	renderTree()
	renderDetail()
	refreshSummary()
	local acc = 0
	local conn = RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc > 0.5 then
			acc = 0
			refreshSummary()
			ResearchUI.refreshNodes()
		end
	end)
	win.onClose(function()
		conn:Disconnect()
	end)
end

function ResearchUI.refreshNodes() end

function ResearchUI.init()
	Hub.openResearch = ResearchUI.open
end

return ResearchUI
