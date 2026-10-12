--[[
	ResearchUI
	The research tree window: Civil and Military branches laid out by
	column/row, with costs, requirements, hit gates and the active project.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Research = require(Shared.Catalog.Research)
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

local ResearchUI = {}

local NODE_W, NODE_H, GAP = 142, 92, 8

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

function ResearchUI.open(focusId: string?)
	local win = Modal.open("Research", "Unlock new buildings, weapons and vehicles", 960, 660)
	local ic = Icons.flask(40, Color3.fromRGB(70, 170, 150))
	ic.Position = UDim2.fromOffset(4, 4)
	ic.Parent = win.iconHolder

	-- summary row
	local top = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 76), Parent = win.body }, { Lib.list("x", 8) })
	local function summary(caption: string, order: number, width: number): TextLabel
		local card = Lib.card({ Size = UDim2.new(0, width, 1, 0), LayoutOrder = order, Parent = top }, { Lib.pad(10, 12) })
		Lib.caption(caption, { Parent = card })
		return Lib.text({ Text = "-", FontFace = Theme.Font.Bold, TextSize = Theme.TextSize.Title, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 26), Parent = card })
	end
	local rpLabel = summary("Research Points", 1, 190)
	local hitsLabel = summary("Hits Landed", 2, 150)
	local activeCard = Lib.card({ Size = UDim2.new(1, -364, 1, 0), LayoutOrder = 3, Parent = top }, { Lib.pad(10, 12) })
	Lib.caption("Current Project", { Parent = activeCard })
	local activeName = Lib.text({ Text = "Nothing - pick a project below", FontFace = Theme.Font.Bold, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, -150, 0, 22), Parent = activeCard })
	local activeBar = Lib.progress({ Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, -150, 0, 6), Parent = activeCard })
	local activeTime = Lib.text({ Text = "", TextSize = Theme.TextSize.Tiny, TextColor3 = Theme.Color.Muted, Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, -150, 0, 14), Parent = activeCard })
	Lib.button({
		Text = "Finish Now",
		FontFace = Theme.Font.Bold,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Theme.Color.Gold,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(136, 36),
		Parent = activeCard,
		Activated = function()
			Hub.call("buyProduct", "InstantResearch")
		end,
	}, { Lib.corner(6) })

	local scroll = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(1, 0, 1, -86),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Color.Faint,
		BorderSizePixel = 0,
		Parent = win.body,
	}, { Lib.list("y", 10) })

	local nodes: { [string]: { btn: TextButton, status: TextLabel, bar: Lib.Progress } } = {}

	for bi, branch in { "Civil", "Military" } do
		local maxRow, maxCol = 0, 0
		for _, def in Research.all() do
			if def.branch == branch then
				maxRow = math.max(maxRow, def.row)
				maxCol = math.max(maxCol, def.col)
			end
		end
		Lib.caption(branch .. " Research", { LayoutOrder = bi * 2 - 1, Parent = scroll })
		local area = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, maxRow * (NODE_H + GAP)),
			LayoutOrder = bi * 2,
			Parent = scroll,
		})
		for _, def in Research.all() do
			if def.branch == branch then
				local btn = Lib.button({
					Name = def.id,
					Position = UDim2.fromOffset((def.col - 1) * (NODE_W + GAP), (def.row - 1) * (NODE_H + GAP)),
					Size = UDim2.fromOffset(NODE_W, NODE_H),
					BackgroundColor3 = Theme.Color.Card,
					Parent = area,
					Activated = function()
						local st, reason = nodeState(def)
						if st == "available" then
							local res = Net.request("StartResearch", def.id)
							if res.ok then
								Sounds.play("Success", 1.2)
							elseif res.err then
								Notifications.show(res.err, "bad")
							end
						elseif reason then
							Notifications.show(reason, "info")
						end
					end,
				}, { Lib.corner(8), Lib.stroke(), Lib.pad(7, 9) })
				Lib.text({ Text = def.name, FontFace = Theme.Font.Bold, TextSize = Theme.TextSize.Small, Size = UDim2.new(1, 0, 0, 18), Parent = btn })
				Lib.text({ Text = def.desc, TextSize = Theme.TextSize.Tiny, TextColor3 = Theme.Color.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 28), Parent = btn })
				Lib.text({
					Text = ("%s RP · %s · %s"):format(Format.short(def.rp), Format.cash(def.cash), Format.duration(def.time)),
					TextSize = Theme.TextSize.Tiny,
					TextColor3 = Theme.Color.Time,
					FontFace = Theme.Font.Bold,
					Position = UDim2.fromOffset(0, 46),
					Size = UDim2.new(1, 0, 0, 14),
					Parent = btn,
				})
				local status = Lib.text({ Text = "", TextSize = Theme.TextSize.Tiny, FontFace = Theme.Font.Bold, Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 14), Parent = btn })
				local bar = Lib.progress({ Position = UDim2.new(0, 0, 1, -3), Size = UDim2.new(1, 0, 0, 3), Parent = btn })
				nodes[def.id] = { btn = btn, status = status, bar = bar }
				if def.id == focusId then
					local stroke = btn:FindFirstChildOfClass("UIStroke") :: UIStroke
					stroke.Color = Theme.Color.Gold
					stroke.Thickness = 2
				end
			end
		end
	end

	local function refresh()
		local d = ClientState.data
		rpLabel.Text = ("%s  (+%s/m)"):format(Format.short(d.rp or 0), Format.short(d.rpRate or 0))
		hitsLabel.Text = Format.commas(((d.stats or {}).Hits) or 0)
		local active = d.research
		local now = Lib.serverNow()
		if active then
			local def = Research.get(active.id)
			activeName.Text = def and def.name or active.id
			local frac = (now - active.startAt) / math.max(1, active.finishAt - active.startAt)
			activeBar.set(frac, Theme.Color.Accent)
			activeTime.Text = Format.duration(active.finishAt - now) .. " left"
		else
			activeName.Text = "Nothing - pick a project below"
			activeBar.set(0)
			activeTime.Text = (d.rpRate or 0) <= 0 and "Build a Research Lab (Military > Research) to earn RP" or ""
		end
		for id, n in nodes do
			local def = Research.get(id)
			if def then
				local st, reason = nodeState(def)
				local stroke = n.btn:FindFirstChildOfClass("UIStroke") :: UIStroke
				if st == "done" then
					Lib.setButtonColor(n.btn, Theme.Color.GoodSoft)
					n.status.Text = "RESEARCHED"
					n.status.TextColor3 = Theme.Color.Good
					n.bar.frame.Visible = false
				elseif st == "active" and active then
					Lib.setButtonColor(n.btn, Theme.Color.AccentSoft)
					n.status.Text = "IN PROGRESS"
					n.status.TextColor3 = Theme.Color.Accent
					n.bar.frame.Visible = true
					n.bar.set((now - active.startAt) / math.max(1, active.finishAt - active.startAt), Theme.Color.Accent)
				elseif st == "available" then
					Lib.setButtonColor(n.btn, Theme.Color.Card)
					local affordable = (d.rp or 0) >= def.rp and (d.cash or 0) >= def.cash
					n.status.Text = d.research and "WAIT FOR CURRENT PROJECT" or (affordable and "CLICK TO RESEARCH" or "NOT ENOUGH RP / CASH")
					n.status.TextColor3 = affordable and Theme.Color.Teal or Theme.Color.Amber
					n.bar.frame.Visible = false
					if stroke.Color ~= Theme.Color.Gold then
						stroke.Color = Theme.Color.Teal
					end
				else
					Lib.setButtonColor(n.btn, Theme.Color.CardAlt)
					n.status.Text = string.upper(reason or "LOCKED")
					n.status.TextColor3 = Theme.Color.Faint
					n.bar.frame.Visible = false
				end
			end
		end
	end

	refresh()
	local acc = 0
	local conn = RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc > 0.5 then
			acc = 0
			refresh()
		end
	end)
	win.onClose(function()
		conn:Disconnect()
	end)
end

function ResearchUI.init()
	Hub.openResearch = ResearchUI.open
end

return ResearchUI
