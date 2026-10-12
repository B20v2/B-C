--[[
	HUD - Field Command
	  top-left    nation badge (flag, name, rank, power progress)
	  top-center  treasury / population / morale / power / water bar
	              + logistics strip (oil, steel, research, army)
	  top-right   PvP switch + status chips (boost, shield, PvP lock)
	  left        mission card (objective chain)
	  bottom      command dock: BUILD, ARMY, RESEARCH, WAR MAP, REWARDS, STORE
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Util.Format)
local Flag = require(Shared.Util.Flag)
local Net = require(Shared.Net)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Hub = require(Client.Hub)
local Lib = require(Client.UI.Lib)
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)
local Notifications = require(script.Parent.Notifications)
local Sounds = require(script.Parent.Sounds)

local New = Lib.New
local C = Theme.Color

local HUD = {}

local refs: { [string]: any } = {}
local dockButtons: { [string]: TextButton } = {}

---------------------------------------------------------------------------
-- Nation badge
---------------------------------------------------------------------------
local function buildBadge(gui: GuiObject)
	local badge = Lib.panel({
		Name = "NationBadge",
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(318, 74),
		Parent = gui,
	})
	Lib.brackets(badge, C.Accent, 8, 2, 3)
	local flagBox = New("Frame", {
		Name = "FlagBox",
		BackgroundColor3 = C.Inset,
		Position = UDim2.fromOffset(10, 12),
		Size = UDim2.fromOffset(72, 48),
		Parent = badge,
	}, { Lib.corner(3), Lib.stroke(C.Line, 1, 0.2) })
	refs.flagBox = New("Frame", { Name = "Holder", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, Parent = flagBox })
	refs.foundHint = Lib.display({
		Name = "Found",
		Text = "+ FLAG",
		TextSize = 12,
		TextColor3 = C.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = flagBox,
	})
	local edit = New("TextButton", {
		Name = "EditNation",
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = flagBox,
		Activated = function()
			Hub.call("openNation")
		end,
	})
	local _ = edit
	refs.nationName = Lib.display({
		Text = "UNNAMED NATION",
		TextSize = 19,
		Position = UDim2.fromOffset(94, 8),
		Size = UDim2.new(1, -104, 0, 24),
		Parent = badge,
	})
	refs.rank = Lib.display({
		Text = "RANK I · OUTPOST",
		TextSize = 12,
		TextColor3 = C.Accent,
		Position = UDim2.fromOffset(94, 32),
		Size = UDim2.new(1, -104, 0, 14),
		Parent = badge,
	})
	refs.rankBar = Lib.progress({ Segments = 10, Position = UDim2.fromOffset(94, 52), Size = UDim2.new(1, -104, 0, 6), Parent = badge })
	refs.power = Lib.text({
		Text = "",
		TextSize = 11,
		TextColor3 = C.Muted,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 32),
		Size = UDim2.fromOffset(110, 14),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = badge,
	})
end

---------------------------------------------------------------------------
-- Resource bar
---------------------------------------------------------------------------
local function cell(parent: Instance, name: string, width: number, order: number, icon: string, color: Color3)
	local f = New("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, 62),
		LayoutOrder = order,
		Parent = parent,
	})
	local ic = Icons.get(icon, 16, color)
	ic.Position = UDim2.fromOffset(12, 10)
	ic.Parent = f
	Lib.caption(name, { Position = UDim2.fromOffset(34, 9), Size = UDim2.new(1, -40, 0, 14), Parent = f })
	local value = Lib.display({ Text = "-", TextSize = 22, Position = UDim2.fromOffset(12, 24), Size = UDim2.new(1, -20, 0, 24), Parent = f })
	local sub = Lib.text({ Text = "", TextSize = 11, TextColor3 = C.Muted, FontFace = Theme.Font.BodyBold, Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -20, 0, 12), Parent = f })
	return f, value, sub
end

local function vline(parent: Instance, order: number)
	New("Frame", { BackgroundColor3 = C.Line, BackgroundTransparency = 0.45, BorderSizePixel = 0, Size = UDim2.fromOffset(1, 44), LayoutOrder = order, Parent = parent })
end

local function buildResources(gui: GuiObject)
	local bar = Lib.panel({
		Name = "Resources",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(746, 62),
		Parent = gui,
	})
	local row = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = bar }, { Lib.list("x", 0, nil, Enum.VerticalAlignment.Center) })
	local cash, cashV, cashS = cell(row, "Treasury", 200, 1, "coin", C.Good)
	refs.cash, refs.income = cashV, cashS
	refs.payBar = Lib.progress({ Position = UDim2.new(0, 12, 1, -4), Size = UDim2.new(1, -24, 0, 3), Parent = cash })
	refs.payTimer = Lib.text({
		Text = "00:00",
		FontFace = Theme.Font.Mono,
		TextSize = 11,
		TextColor3 = C.Accent,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 9),
		Size = UDim2.fromOffset(60, 14),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = cash,
	})
	refs.cashCell = cash
	vline(row, 2)
	local _, popV, popS = cell(row, "Population", 150, 3, "people", C.Info)
	refs.pop, refs.workers = popV, popS
	vline(row, 4)
	local mood, moodV = cell(row, "Morale", 118, 5, "smile", C.Gold)
	refs.mood = moodV
	refs.moodBar = Lib.progress({ Segments = 5, Position = UDim2.new(0, 12, 0, 50), Size = UDim2.new(1, -24, 0, 4), Parent = mood })
	vline(row, 6)
	local pw, pwV = cell(row, "Power", 136, 7, "bolt", C.Gold)
	refs.powerV = pwV
	refs.powerBar = Lib.progress({ Position = UDim2.new(0, 12, 0, 50), Size = UDim2.new(1, -24, 0, 4), Parent = pw })
	vline(row, 8)
	local wt, wtV = cell(row, "Water", 136, 9, "drop", C.Info)
	refs.waterV = wtV
	refs.waterBar = Lib.progress({ Position = UDim2.new(0, 12, 0, 50), Size = UDim2.new(1, -24, 0, 4), Parent = wt })

	-- logistics strip
	local strip = New("Frame", {
		Name = "Logistics",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84),
		Size = UDim2.fromOffset(746, 24),
		Parent = gui,
	}, { Lib.list("x", 6, Enum.HorizontalAlignment.Center) })
	local function chip(icon: string, color: Color3, order: number): TextLabel
		local f = New("Frame", {
			BackgroundColor3 = C.Panel,
			BackgroundTransparency = 0.15,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 24),
			LayoutOrder = order,
			Parent = strip,
		}, { Lib.corner(3), Lib.stroke(C.LineSoft, 1, 0.2), Lib.pad(0, 9, 0, 6), Lib.list("x", 6, nil, Enum.VerticalAlignment.Center) })
		local ic = Icons.get(icon, 13, color)
		ic.LayoutOrder = 1
		ic.Parent = f
		return Lib.text({
			Text = "-",
			FontFace = Theme.Font.BodyBold,
			TextSize = 12,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			TextTruncate = Enum.TextTruncate.None,
			LayoutOrder = 2,
			Parent = f,
		})
	end
	refs.oil = chip("barrel", Color3.fromRGB(214, 176, 120), 1)
	refs.steel = chip("beam", C.TextSoft, 2)
	refs.rp = chip("flask", C.Teal, 3)
	refs.army = chip("tank", Color3.fromRGB(170, 200, 130), 4)
end

---------------------------------------------------------------------------
-- PvP + status chips
---------------------------------------------------------------------------
local function buildStatus(gui: GuiObject)
	local pvp = Lib.panel({
		Name = "PvpPanel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(170, 48),
		Parent = gui,
	})
	Lib.display({ Text = "PVP", TextSize = 15, Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(40, 48), Parent = pvp })
	refs.pvpState = Lib.display({ Text = "OFF", TextSize = 13, TextColor3 = C.Muted, Position = UDim2.fromOffset(52, 0), Size = UDim2.fromOffset(40, 48), Parent = pvp })
	local toggle, setToggle = Lib.toggle({
		Name = "PvpToggle",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Parent = pvp,
	}, function(want)
		local res = Net.request("SetPvp", want)
		if not res.ok and res.err then
			Notifications.show(res.err, "bad")
		end
	end)
	local _ = toggle
	refs.setPvp = setToggle
	refs.pvpPanel = pvp

	refs.chips = New("Frame", {
		Name = "StatusChips",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 72),
		Size = UDim2.fromOffset(330, 120),
		Parent = gui,
	}, { Lib.list("y", 5, Enum.HorizontalAlignment.Right) })
end

local function setChip(name: string, text: string?, color: Color3?)
	local existing = refs.chips:FindFirstChild(name)
	if not text then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		(existing:FindFirstChild("Label", true) :: TextLabel).Text = text
		return
	end
	local col = color or C.Accent
	local chip = New("Frame", {
		Name = name,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.08,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		Parent = refs.chips,
	}, {
		Lib.corner(3),
		Lib.stroke(col, 1, 0.45),
		Lib.pad(0, 10, 0, 8),
		Lib.list("x", 7, nil, Enum.VerticalAlignment.Center),
		New("Frame", { BackgroundColor3 = col, Size = UDim2.fromOffset(6, 6), LayoutOrder = 1 }, { Lib.round() }),
		Lib.display({
			Name = "Label",
			Text = text,
			TextSize = 11,
			TextColor3 = col,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			TextTruncate = Enum.TextTruncate.None,
			LayoutOrder = 2,
		}),
	})
	local _ = chip
end

---------------------------------------------------------------------------
-- Mission card
---------------------------------------------------------------------------
local function buildMission(gui: GuiObject)
	local card = Lib.panel({
		Name = "Mission",
		Position = UDim2.fromOffset(16, 104),
		Size = UDim2.fromOffset(300, 118),
		Parent = gui,
	})
	Lib.hazard({ Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 4), BackgroundTransparency = 0.15, Parent = card }, C.Accent, C.Panel, 9)
	refs.missionCaption = Lib.caption("Mission", { TextColor3 = C.Accent, Position = UDim2.fromOffset(14, 12), Size = UDim2.new(1, -28, 0, 14), Parent = card })
	refs.missionText = Lib.text({
		Text = "...",
		FontFace = Theme.Font.BodyHeavy,
		TextSize = 16,
		TextWrapped = true,
		Position = UDim2.fromOffset(14, 28),
		Size = UDim2.new(1, -28, 0, 22),
		Parent = card,
	})
	refs.missionBar = Lib.progress({ Segments = 12, Position = UDim2.fromOffset(14, 58), Size = UDim2.new(1, -28, 0, 6), Parent = card })
	refs.missionProgress = Lib.text({
		Text = "0 / 0",
		FontFace = Theme.Font.Mono,
		TextSize = 12,
		TextColor3 = C.Muted,
		Position = UDim2.fromOffset(14, 72),
		Size = UDim2.new(0.5, -14, 0, 32),
		Parent = card,
	})
	refs.missionReward = Lib.chip("$0", C.GoodSoft, C.Good, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 78),
		Parent = card,
	})
	refs.missionClaim = Lib.button({
		Variant = "primary",
		Text = "CLAIM REWARD",
		TextSize = 14,
		Position = UDim2.fromOffset(14, 74),
		Size = UDim2.new(1, -28, 0, 32),
		Visible = false,
		Parent = card,
		Activated = function()
			local res = Net.request("ClaimQuest")
			if res.ok then
				Sounds.play("Success")
			elseif res.err then
				Notifications.show(res.err, "bad")
			end
		end,
	})
	refs.missionCard = card
end

---------------------------------------------------------------------------
-- Command dock
---------------------------------------------------------------------------
local DOCK = {
	{ id = "Build", label = "BUILD", key = "B", icon = "hammer", hub = "toggleBuild" },
	{ id = "Army", label = "ARMY", key = "G", icon = "tank", hub = "openArmy" },
	{ id = "Research", label = "RESEARCH", key = "T", icon = "flask", hub = "openResearch" },
	{ id = "War", label = "WAR MAP", key = "M", icon = "map", hub = "openTravel" },
	{ id = "Rewards", label = "REWARDS", key = "J", icon = "gift", hub = "openRewards" },
	{ id = "Store", label = "STORE", key = "", icon = "cart", hub = "openShop", gold = true },
}

local function buildDock(gui: GuiObject)
	local dock = Lib.panel({
		Name = "CommandDock",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(#DOCK * 86 + 16, 86),
		Parent = gui,
	}, { Lib.pad(8), Lib.list("x", 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	Lib.brackets(dock, C.Accent, 12, 2, 4)
	for i, d in DOCK do
		local btn = Lib.button({
			Name = d.id,
			Size = UDim2.fromOffset(80, 70),
			BackgroundColor3 = d.gold and C.GoldSoft or C.Raised,
			LayoutOrder = i,
			Parent = dock,
			Activated = function()
				Hub.call(d.hub)
			end,
		}, { Lib.corner(4), Lib.stroke(d.gold and C.Gold or C.LineSoft, 1, d.gold and 0.2 or 0) })
		local ic = Icons.get(d.icon, 26, d.gold and C.Gold or C.Text)
		ic.AnchorPoint = Vector2.new(0.5, 0)
		ic.Position = UDim2.new(0.5, 0, 0, 10)
		ic.Parent = btn
		Lib.display({
			Name = "Label",
			Text = d.label,
			TextSize = 12,
			TextColor3 = d.gold and C.Gold or C.TextSoft,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 0, 1, -22),
			Size = UDim2.new(1, 0, 0, 16),
			Parent = btn,
		})
		if d.key ~= "" then
			Lib.text({
				Text = d.key,
				FontFace = Theme.Font.Mono,
				TextSize = 10,
				TextColor3 = C.Faint,
				Position = UDim2.fromOffset(6, 3),
				Size = UDim2.fromOffset(14, 12),
				Parent = btn,
			})
		end
		New("Frame", {
			Name = "Badge",
			BackgroundColor3 = C.Bad,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -8, 0, 8),
			Size = UDim2.fromOffset(10, 10),
			Visible = false,
			Parent = btn,
		}, { Lib.round(), Lib.stroke(C.Panel, 2) })
		dockButtons[d.id] = btn
	end
	refs.dock = dock

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local map = { [Enum.KeyCode.G] = "openArmy", [Enum.KeyCode.T] = "openResearch", [Enum.KeyCode.M] = "openTravel", [Enum.KeyCode.J] = "openRewards" }
		local hub = map[input.KeyCode]
		if hub and ClientState.mode ~= "build" then
			Hub.call(hub)
		end
	end)
end

---------------------------------------------------------------------------
-- refresh
---------------------------------------------------------------------------
local RANKS = { "I", "II", "III", "IV", "V", "VI", "VII" }

local function refresh()
	local d = ClientState.data
	if d.cash == nil then
		return
	end
	refs.cash.Text = Format.cash(d.cash)
	local income = d.income or 0
	refs.income.Text = (income >= 0 and "+" or "") .. Format.cash(income) .. " / pay"
	refs.income.TextColor3 = income >= 0 and C.Good or C.Bad
	refs.pop.Text = Format.short(d.pop or 0)
	local free = math.max(0, (d.pop or 0) - (d.workersUsed or 0))
	refs.workers.Text = ("%s idle · cap %s"):format(Format.short(free), Format.short(d.popCap or 0))
	local mood = d.happiness or 0
	refs.mood.Text = Format.percent(mood)
	refs.moodBar.set(mood / 100, mood >= 70 and C.Good or (mood >= 40 and C.Gold or C.Bad))

	local power, water = d.power or { 0, 0 }, d.water or { 0, 0 }
	refs.powerV.Text = ("%s/%s"):format(Format.short(power[1]), Format.short(power[2]))
	refs.powerBar.set(power[2] > 0 and power[1] / power[2] or 1, power[1] + 0.5 < power[2] and C.Bad or C.Gold)
	refs.waterV.Text = ("%s/%s"):format(Format.short(water[1]), Format.short(water[2]))
	refs.waterBar.set(water[2] > 0 and water[1] / water[2] or 1, water[1] + 0.5 < water[2] and C.Bad or C.Info)

	refs.oil.Text = ("OIL %s/%s"):format(Format.short(d.oil or 0), Format.short(d.oilCap or 0))
	refs.steel.Text = ("STEEL %s/%s"):format(Format.short(d.steel or 0), Format.short(d.steelCap or 0))
	refs.rp.Text = ("RP %s  +%s/m"):format(Format.short(d.rp or 0), Format.short(d.rpRate or 0))
	refs.army.Text = ("ARMY %d/%d"):format(d.units or 0, d.unitCap or 0)

	local pvpOn = d.pvp == true
	refs.setPvp(pvpOn)
	refs.pvpState.Text = pvpOn and "ON" or "OFF"
	refs.pvpState.TextColor3 = pvpOn and C.Bad or C.Muted

	-- nation badge
	local nation = d.nation
	if nation ~= nil then
		local founded = type(nation) == "table" and nation.name ~= nil
		refs.nationName.Text = founded and string.upper(nation.name) or "UNNAMED NATION"
		refs.foundHint.Visible = not founded
		local flag = founded and nation.flag or ""
		if flag ~= refs.lastFlag then
			refs.lastFlag = flag
			Lib.clear(refs.flagBox)
			if founded then
				Flag.draw(refs.flagBox, flag)
			end
		end
	end
	local rank = d.rank
	if rank then
		refs.rank.Text = ("RANK %s · %s"):format(RANKS[rank.level] or tostring(rank.level), string.upper(rank.name))
		refs.rankBar.set(rank.progress or 0)
		refs.power.Text = ("POWER %s"):format(Format.short(rank.power or 0))
	end

	-- mission
	local q = d.quest
	if q then
		refs.missionCard.Visible = true
		refs.missionCaption.Text = ("MISSION %02d"):format(q.i)
		refs.missionText.Text = q.text
		refs.missionBar.set(q.max > 0 and q.cur / q.max or 0, q.done and C.Good or nil)
		refs.missionProgress.Text = ("%s / %s"):format(Format.commas(q.cur), Format.commas(q.max))
		;(refs.missionReward:FindFirstChild("Label") :: TextLabel).Text = Format.cash(q.reward)
		refs.missionClaim.Visible = q.done
		refs.missionProgress.Visible = not q.done
		refs.missionReward.Visible = not q.done
	else
		refs.missionCard.Visible = false
	end

	local daily = d.daily
	local rewardsReady = (daily ~= nil and daily.canClaim == true) or ((d.giftAt or math.huge) <= Lib.serverNow())
	;(dockButtons.Rewards:FindFirstChild("Badge") :: Frame).Visible = rewardsReady
	;(dockButtons.Research:FindFirstChild("Badge") :: Frame).Visible = d.research == false and (d.rp or 0) >= 40
end

function HUD.payPop(amount: number)
	Notifications.float((amount >= 0 and "+" or "") .. Format.cash(amount), UDim2.new(0.5, -270, 0, 88), amount >= 0 and C.Good or C.Bad)
end

function HUD.init(gui: GuiObject)
	buildBadge(gui)
	buildResources(gui)
	buildStatus(gui)
	buildMission(gui)
	buildDock(gui)
	ClientState.onAny(refresh)

	local lastCash: number? = nil
	ClientState.on("nextPay", function()
		local cash = ClientState.get("cash")
		if lastCash and cash then
			HUD.payPop(ClientState.get("income") or 0)
		end
		lastCash = cash
	end)

	ClientState.onMode(function(mode)
		local build = dockButtons.Build
		;(build:FindFirstChild("Label") :: TextLabel).Text = mode == "war" and "HOME" or "BUILD"
		refs.dock.Visible = mode ~= "build"
		refs.missionCard.Visible = mode == "play" and ClientState.get("quest") ~= false
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local d = ClientState.data
		local now = Lib.serverNow()
		if d.nextPay then
			local left = d.nextPay - now
			refs.payTimer.Text = "PAY " .. Format.clock(left)
			refs.payBar.set(1 - math.clamp(left / 60, 0, 1), C.Accent)
		end
		local boost = (d.boostUntil or 0) - os.time()
		setChip("Boost", boost > 0 and ("2X CASH  " .. Format.clock(boost)) or nil, C.Good)
		local shield = (d.shield or 0) - os.time()
		setChip("Shield", shield > 0 and ("SHIELD  " .. Format.clock(shield)) or nil, C.Info)
		local lock = (d.pvpLock or 0) - now
		setChip("PvpLock", lock > 0 and ("PVP LOCKED  " .. Format.clock(lock)) or nil, C.Bad)
		setChip("Damaged", (d.damaged or 0) > 0 and (("%d BUILDINGS DAMAGED"):format(d.damaged)) or nil, C.Bad)
		setChip("Unsaved", d.persistent == false and "STUDIO · DATA NOT SAVED" or nil, C.Gold)
		local giftLeft = (d.giftAt or 0) - now
		setChip("Gift", giftLeft <= 0 and d.giftAt and "GIFT READY · REWARDS [J]" or nil, C.Premium)
	end)
end

return HUD
