--[[
	HUD
	Always-on interface:
	  * top bar: PvP toggle, cash + next pay countdown, population + free
	    workers, happiness, Travel
	  * resource strip: power, water, oil, steel, research points, army
	  * objective tracker with claim button (left)
	  * side menu: Store, Research, Army, Daily, Gift, Codes (left)
	  * hammer button to open the build menu (bottom center)
]]

local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Hub = require(Client.Hub)
local Lib = require(Client.UI.Lib)
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Notifications = require(script.Parent.Notifications)
local Sounds = require(script.Parent.Sounds)

local New = Lib.New

local HUD = {}

local refs: { [string]: any } = {}

local function pill(width: number, tint: Color3, order: number): Frame
	return New("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.12,
		Size = UDim2.fromOffset(width, 46),
		LayoutOrder = order,
	}, {
		Lib.corner(Theme.Radius.Pill),
		Lib.stroke(Color3.new(1, 1, 1), 1, 0.86),
		New("UIGradient", {
			Color = ColorSequence.new(tint, Theme.Color.Hud),
			Rotation = 0,
		}),
	})
end

local function hudText(props: { [string]: any }): TextLabel
	local p = {
		TextColor3 = Theme.Color.HudText,
		FontFace = Theme.Font.Bold,
		TextSize = Theme.TextSize.Body,
	}
	for k, v in props do
		p[k] = v
	end
	return Lib.text(p)
end

local function buildTopBar(gui: GuiObject)
	local bar = New("Frame", {
		Name = "TopBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(800, 46),
		Parent = gui,
	}, { Lib.list("x", 10, Enum.HorizontalAlignment.Center) })

	-- PvP toggle
	local pvp = Lib.button({
		Name = "Pvp",
		Size = UDim2.fromOffset(104, 46),
		BackgroundColor3 = Theme.Color.Hud,
		BackgroundTransparency = 0.25,
		LayoutOrder = 1,
		Parent = bar,
		Activated = function()
			local on = ClientState.get("pvp") == true
			local res = Net.request("SetPvp", not on)
			if not res.ok and res.err then
				Notifications.show(res.err, "bad")
			end
		end,
	}, { Lib.corner(Theme.Radius.Pill), Lib.stroke(Color3.new(1, 1, 1), 1, 0.86) })
	refs.pvpLabel = hudText({ Text = "PVP OFF", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = Theme.TextSize.Small, Parent = pvp })
	refs.pvp = pvp

	-- Cash
	local cash = pill(196, Theme.Color.CashTint, 2)
	cash.Parent = bar
	local coin = Icons.coin(22, Theme.Color.HudText)
	coin.Position = UDim2.fromOffset(12, 12)
	coin.Parent = cash
	refs.cash = hudText({ Text = "$0", Position = UDim2.fromOffset(40, 0), Size = UDim2.new(0, 84, 1, 0), TextSize = 19, Parent = cash })
	refs.payTimer = hudText({ Text = "01:00", Position = UDim2.new(1, -66, 0, 6), Size = UDim2.fromOffset(56, 18), TextSize = Theme.TextSize.Small, TextXAlignment = Enum.TextXAlignment.Center, Parent = cash })
	hudText({ Text = "Next Pay", Position = UDim2.new(1, -66, 0, 23), Size = UDim2.fromOffset(56, 14), TextSize = Theme.TextSize.Tiny, TextColor3 = Color3.fromRGB(150, 220, 160), TextXAlignment = Enum.TextXAlignment.Center, Parent = cash })
	refs.cashPill = cash

	-- Population
	local pop = pill(196, Theme.Color.PopTint, 3)
	pop.Parent = bar
	local people = Icons.people(24, Theme.Color.HudText)
	people.Position = UDim2.fromOffset(12, 11)
	people.Parent = pop
	refs.pop = hudText({ Text = "0", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 4), Size = UDim2.fromOffset(120, 22), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right, Parent = pop })
	refs.workers = hudText({ Text = "0 workers free", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 25), Size = UDim2.fromOffset(150, 14), TextSize = Theme.TextSize.Tiny, TextColor3 = Theme.Color.HudMuted, FontFace = Theme.Font.Semi, TextXAlignment = Enum.TextXAlignment.Right, Parent = pop })

	-- Happiness
	local happy = pill(176, Theme.Color.HappyTint, 4)
	happy.Parent = bar
	local smile = Icons.smile(22, Theme.Color.HudText)
	smile.Position = UDim2.fromOffset(12, 12)
	smile.Parent = happy
	refs.happy = hudText({ Text = "0%", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.new(0, 80, 1, 0), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right, Parent = happy })

	-- Travel
	local travel = Lib.button({
		Name = "Travel",
		Size = UDim2.fromOffset(104, 46),
		BackgroundColor3 = Theme.Color.Hud,
		BackgroundTransparency = 0.25,
		LayoutOrder = 5,
		Parent = bar,
		Activated = function()
			Hub.call("openTravel")
		end,
	}, { Lib.corner(Theme.Radius.Pill), Lib.stroke(Color3.new(1, 1, 1), 1, 0.86) })
	hudText({ Text = "Travel", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = Theme.TextSize.Small, Parent = travel })

	-- status chips (boost / shield) under the bar
	refs.chips = New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 98),
		Size = UDim2.fromOffset(600, 22),
		Parent = gui,
	}, { Lib.list("x", 6, Enum.HorizontalAlignment.Center) })
end

local function resourceChip(parent: Instance, icon: string, color: Color3, order: number): TextLabel
	local f = New("Frame", {
		BackgroundColor3 = Theme.Color.Hud,
		BackgroundTransparency = 0.35,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		LayoutOrder = order,
		Parent = parent,
	}, { Lib.corner(6), Lib.pad(0, 10, 0, 6), Lib.list("x", 6, nil, Enum.VerticalAlignment.Center) })
	local ic = Icons.get(icon, 14, color)
	ic.LayoutOrder = 1
	ic.Parent = f
	return hudText({
		Text = "-",
		TextSize = Theme.TextSize.Small,
		FontFace = Theme.Font.Semi,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextTruncate = Enum.TextTruncate.None,
		LayoutOrder = 2,
		Parent = f,
	})
end

local function buildResourceStrip(gui: GuiObject)
	local strip = New("Frame", {
		Name = "Resources",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 66),
		Size = UDim2.fromOffset(900, 26),
		Parent = gui,
	}, { Lib.list("x", 6, Enum.HorizontalAlignment.Center) })
	refs.power = resourceChip(strip, "bolt", Color3.fromRGB(250, 210, 80), 1)
	refs.water = resourceChip(strip, "drop", Color3.fromRGB(110, 190, 250), 2)
	refs.oil = resourceChip(strip, "barrel", Color3.fromRGB(200, 170, 120), 3)
	refs.steel = resourceChip(strip, "beam", Color3.fromRGB(200, 206, 214), 4)
	refs.rp = resourceChip(strip, "flask", Color3.fromRGB(160, 220, 200), 5)
	refs.army = resourceChip(strip, "tank", Color3.fromRGB(170, 200, 130), 6)
end

local function buildQuest(gui: GuiObject)
	local card = Lib.card({
		Name = "Objective",
		Position = UDim2.fromOffset(16, 130),
		Size = UDim2.fromOffset(250, 104),
		BackgroundTransparency = 0.04,
		Parent = gui,
	}, { Lib.pad(10, 12) })
	refs.questCaption = Lib.caption("Objective", { Parent = card })
	refs.questText = Lib.text({
		Text = "...",
		FontFace = Theme.Font.Bold,
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = card,
	})
	local bar = Lib.progress({ Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 6), Parent = card })
	refs.questBar = bar
	refs.questProgress = Lib.text({
		Text = "0 / 0",
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.Muted,
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(0.5, 0, 0, 24),
		Parent = card,
	})
	refs.questReward = Lib.chip("$0", Theme.Color.GoodSoft, Theme.Color.Good, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 56),
		Parent = card,
	})
	refs.questClaim = Lib.button({
		Text = "CLAIM REWARD",
		FontFace = Theme.Font.Bold,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Theme.Color.Good,
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 0, 28),
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
	}, { Lib.corner(6) })
	refs.questCard = card
end

local function sideButton(parent: Instance, name: string, icon: string, color: Color3, order: number, onClick: () -> ()): TextButton
	local btn = Lib.button({
		Name = name,
		Size = UDim2.fromOffset(58, 58),
		BackgroundColor3 = Theme.Color.Card,
		LayoutOrder = order,
		Parent = parent,
		Activated = onClick,
	}, { Lib.corner(10), Lib.stroke(Theme.Color.CardStroke) })
	local tile = New("Frame", {
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(30, 30),
		Parent = btn,
	}, { Lib.corner(7) })
	local ic = Icons.get(icon, 20, Color3.new(1, 1, 1))
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)
	ic.Parent = tile
	Lib.text({
		Name = "Label",
		Text = name,
		TextSize = Theme.TextSize.Tiny,
		FontFace = Theme.Font.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = btn,
	})
	local badge = New("Frame", {
		Name = "Badge",
		BackgroundColor3 = Theme.Color.Bad,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(12, 12),
		Visible = false,
		Parent = btn,
	}, { Lib.round(), Lib.stroke(Color3.new(1, 1, 1), 2) })
	local _ = badge
	return btn
end

local function buildSideMenu(gui: GuiObject)
	local col = New("Frame", {
		Name = "SideMenu",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 246),
		Size = UDim2.fromOffset(124, 400),
		Parent = gui,
	}, { Lib.grid(UDim2.fromOffset(58, 58), 8) })
	refs.shopBtn = sideButton(col, "Store", "cart", Theme.Color.Gold, 1, function()
		Hub.call("openShop")
	end)
	refs.researchBtn = sideButton(col, "Research", "flask", Color3.fromRGB(70, 170, 150), 2, function()
		Hub.call("openResearch")
	end)
	refs.armyBtn = sideButton(col, "Army", "tank", Color3.fromRGB(110, 130, 80), 3, function()
		Hub.call("openArmy")
	end)
	refs.dailyBtn = sideButton(col, "Daily", "calendar", Theme.Color.Military, 4, function()
		Hub.call("openDaily")
	end)
	refs.giftBtn = sideButton(col, "Gift", "gift", Color3.fromRGB(150, 96, 216), 5, function()
		local res = Net.request("ClaimPlaytime")
		if res.ok then
			Sounds.play("Success")
		elseif res.err then
			Notifications.show(res.err, "info")
		end
	end)
	refs.codesBtn = sideButton(col, "Codes", "ticket", Theme.Color.Civil, 6, function()
		Hub.call("openCodes")
	end)
end

local function buildHammer(gui: GuiObject)
	local btn = Lib.button({
		Name = "BuildButton",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(100, 66),
		BackgroundColor3 = Theme.Color.Card,
		Parent = gui,
		Activated = function()
			Hub.call("toggleBuild")
		end,
	}, { Lib.corner(12), Lib.stroke(Theme.Color.CardStroke, 1) })
	local ic = Icons.hammer(30, Theme.Color.Text)
	ic.AnchorPoint = Vector2.new(0.5, 0)
	ic.Position = UDim2.new(0.5, 0, 0, 8)
	ic.Parent = btn
	refs.hammerLabel = Lib.text({
		Text = "BUILD  [B]",
		TextSize = Theme.TextSize.Tiny,
		FontFace = Theme.Font.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 1, -20),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = btn,
	})
	refs.hammer = btn
end

local function setChip(name: string, text: string?, bg: Color3, fg: Color3)
	local existing = refs.chips:FindFirstChild(name)
	if not text then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		(existing:FindFirstChild("Label") :: TextLabel).Text = text
	else
		local chip = Lib.chip(text, bg, fg)
		chip.Name = name
		chip.Parent = refs.chips
	end
end

local function refresh()
	local d = ClientState.data
	if d.cash == nil then
		return
	end
	refs.cash.Text = Format.cash(d.cash)
	refs.pop.Text = Format.short(d.pop or 0)
	local free = math.max(0, (d.pop or 0) - (d.workersUsed or 0))
	refs.workers.Text = Format.short(free) .. " workers free"
	refs.happy.Text = Format.percent(d.happiness or 0)

	local pvpOn = d.pvp == true
	refs.pvpLabel.Text = pvpOn and "PVP ON" or "PVP OFF"
	Lib.setButtonColor(refs.pvp, pvpOn and Color3.fromRGB(150, 40, 40) or Theme.Color.Hud)

	local power, water = d.power or { 0, 0 }, d.water or { 0, 0 }
	refs.power.Text = ("%s / %s MW"):format(Format.short(power[1]), Format.short(power[2]))
	refs.power.TextColor3 = power[1] + 0.5 < power[2] and Color3.fromRGB(255, 140, 120) or Theme.Color.HudText
	refs.water.Text = ("%s / %s"):format(Format.short(water[1]), Format.short(water[2]))
	refs.water.TextColor3 = water[1] + 0.5 < water[2] and Color3.fromRGB(255, 140, 120) or Theme.Color.HudText
	refs.oil.Text = ("%s / %s"):format(Format.short(d.oil or 0), Format.short(d.oilCap or 0))
	refs.steel.Text = ("%s / %s"):format(Format.short(d.steel or 0), Format.short(d.steelCap or 0))
	refs.rp.Text = ("%s RP  +%s/m"):format(Format.short(d.rp or 0), Format.short(d.rpRate or 0))
	refs.army.Text = ("%d / %d"):format(d.units or 0, d.unitCap or 0)

	local q = d.quest
	if q then
		refs.questCard.Visible = true
		refs.questCaption.Text = ("OBJECTIVE %d"):format(q.i)
		refs.questText.Text = q.text
		refs.questBar.set(q.max > 0 and q.cur / q.max or 0, q.done and Theme.Color.Good or nil)
		refs.questProgress.Text = ("%s / %s"):format(Format.commas(q.cur), Format.commas(q.max))
		;(refs.questReward:FindFirstChild("Label") :: TextLabel).Text = Format.cash(q.reward)
		refs.questClaim.Visible = q.done
		refs.questProgress.Visible = not q.done
		refs.questReward.Visible = not q.done
	else
		refs.questCard.Visible = false
	end

	local daily = d.daily
	refs.dailyBtn.Badge.Visible = daily ~= nil and daily.canClaim == true
end

function HUD.payPop(amount: number)
	Notifications.float((amount >= 0 and "+" or "") .. Format.cash(amount), UDim2.new(0.5, -90, 0, 70))
end

function HUD.init(gui: GuiObject)
	buildTopBar(gui)
	buildResourceStrip(gui)
	buildQuest(gui)
	buildSideMenu(gui)
	buildHammer(gui)
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
		refs.hammerLabel.Text = mode == "war" and "BACK HOME" or (mode == "build" and "CLOSE  [B]" or "BUILD  [B]")
		refs.hammer.Visible = mode ~= "build"
	end)

	-- countdowns
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
			refs.payTimer.Text = Format.clock(d.nextPay - now)
		end
		if d.giftAt then
			local left = d.giftAt - now
			local label = refs.giftBtn:FindFirstChild("Label") :: TextLabel
			label.Text = left > 0 and Format.clock(left) or "CLAIM!"
			refs.giftBtn.Badge.Visible = left <= 0
		end
		local boost = (d.boostUntil or 0) - os.time()
		setChip("Boost", boost > 0 and ("2x CASH  " .. Format.clock(boost)) or nil, Theme.Color.GoodSoft, Theme.Color.Good)
		local shield = (d.shield or 0) - os.time()
		setChip("Shield", shield > 0 and ("NEW NATION SHIELD  " .. Format.clock(shield)) or nil, Theme.Color.TimeSoft, Theme.Color.Time)
		local lock = (d.pvpLock or 0) - now
		setChip("PvpLock", lock > 0 and ("PVP LOCKED ON  " .. Format.clock(lock)) or nil, Theme.Color.BadSoft, Theme.Color.Bad)
		setChip("Unsaved", d.persistent == false and "STUDIO: DATA NOT SAVED (enable API access)" or nil, Theme.Color.GoldSoft, Theme.Color.Amber)
	end)
end

return HUD
