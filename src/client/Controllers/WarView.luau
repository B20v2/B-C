--[[
	WarView
	"Travel" opens the strategic view: a top-down camera over the central
	battlefield (every nation's island rings it, joined by a bridge) or any
	nation. From here you:
	  * pick a weapon in the hotbar (1-7) and click to launch at the reticle
	  * drag a box (or tap) to select your vehicles, right-click / tap to move;
	    they drive over the bridges, and into a rival city with PvP on
	  * watch strategic points ("AIRPORT · UNCAPTURED") and enemy nations
	WASD / arrows pan, scroll / pinch zoom, the hammer button returns home.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Grid = require(Shared.Util.Grid)
local Weapons = require(Shared.Catalog.Weapons)
local Units = require(Shared.Catalog.Units)
local ModelBuilder = require(Shared.ModelBuilder)
local Unlocks = require(Shared.Util.Unlocks)
local Flag = require(Shared.Util.Flag)
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
local UnitView = require(script.Parent.UnitView)

local New = Lib.New
local C = Theme.Color

local WarView = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local labelParent: Instance
local hotbar: Frame
local reticle: Frame
local hint: TextLabel
local selectBox: Frame
local blastRing: Part
local pointLabels: { [Instance]: BillboardGui } = {}
local plotLabels: { BillboardGui } = {}
local fobLabels: { [Instance]: BillboardGui } = {}
local ordersPanel: Frame
local orderButtons: { [string]: TextButton } = {}

local focus = Vector3.zero
local height = 620
local keys: { [Enum.KeyCode]: boolean } = {}
local selectedWeapon: string? = nil
local pointer = Vector2.zero
local boxStart: Vector2? = nil
local rmbStart: Vector2? = nil
local slots: { [string]: { btn: TextButton, count: TextLabel, sub: TextLabel, reload: Frame, bar: Lib.Progress } } = {}
local readout: { [string]: TextLabel } = {}
local targetLabel: TextLabel
local warOverlay: Frame

local PAN_KEYS = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function groundAt(screen: Vector2): Vector3?
	local ray = camera:ScreenPointToRay(screen.X, screen.Y)
	if math.abs(ray.Direction.Y) < 1e-4 then
		return nil
	end
	local t = -ray.Origin.Y / ray.Direction.Y
	if t < 0 then
		return nil
	end
	return ray.Origin + ray.Direction * t
end

local function access(): Unlocks.Access
	return { researched = ClientState.get("researched") or {}, passes = ClientState.get("passes") or {} }
end

local function availableWeapons()
	local out = {}
	local inv = ClientState.get("inventory") or {}
	for _, w in Weapons.all() do
		if Unlocks.check(w, access()) or (inv[w.id] or 0) > 0 then
			table.insert(out, w)
		end
	end
	return out
end

local function unitUnder(screen: Vector2): Model?
	-- generous screen-space pick: closest own unit within 28px
	local best, bestD = nil, 28
	for _, m in UnitView.mine() do
		local root = m.PrimaryPart
		if root then
			local sp, onScreen = camera:WorldToScreenPoint(root.CFrame.Position)
			if onScreen then
				local d = (Vector2.new(sp.X, sp.Y) - screen).Magnitude
				if d < bestD then
					best, bestD = m, d
				end
			end
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Hotbar
---------------------------------------------------------------------------
local function renderHotbar()
	Lib.clear(hotbar)
	table.clear(slots)
	local list = availableWeapons()
	hotbar.Visible = ClientState.mode == "war" and #list > 0
	for i, w in list do
		local btn = Lib.button({
			Name = w.id,
			Size = UDim2.fromOffset(82, 90),
			BackgroundColor3 = C.Panel,
			BackgroundTransparency = 0.05,
			LayoutOrder = i,
			Parent = hotbar,
			Activated = function()
				WarView.selectWeapon(selectedWeapon ~= w.id and w.id or nil)
			end,
		}, { Lib.corner(4), Lib.stroke(C.Line, 1, 0.3) })
		local art = Lib.inset({ Position = UDim2.fromOffset(5, 18), Size = UDim2.new(1, -10, 0, 40), Parent = btn })
		Lib.viewport(ModelBuilder.projectile(w), { Parent = art }, 90)
		local reload = New("Frame", {
			Name = "Reload",
			BackgroundColor3 = C.Ink,
			BackgroundTransparency = 0.25,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			ZIndex = 3,
			Parent = art,
		})
		local count = Lib.display({
			Text = "0",
			TextSize = 15,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 1),
			Size = UDim2.fromOffset(44, 16),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = btn,
		})
		local sub = Lib.display({
			Text = w.short,
			TextSize = 10,
			TextColor3 = C.Muted,
			Position = UDim2.new(0, 0, 1, -28),
			Size = UDim2.new(1, 0, 0, 12),
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = btn,
		})
		local bar = Lib.progress({ Segments = 6, Position = UDim2.new(0, 6, 1, -11), Size = UDim2.new(1, -12, 0, 4), Parent = btn })
		Lib.text({ Text = tostring(i), FontFace = Theme.Font.Mono, TextColor3 = C.Accent, TextSize = 11, Position = UDim2.fromOffset(6, 2), Size = UDim2.fromOffset(12, 14), Parent = btn })
		slots[w.id] = { btn = btn, count = count, sub = sub, reload = reload, bar = bar }
	end
	WarView.refreshHotbar()
end

function WarView.refreshHotbar()
	local inv = ClientState.get("inventory") or {}
	local launchers = ClientState.get("launchers") or {}
	local now = Lib.serverNow()
	for id, s in slots do
		local w = Weapons.get(id)
		if w then
			local stock = inv[id] or 0
			s.count.Text = tostring(stock)
			s.count.TextColor3 = stock > 0 and C.Text or C.Bad
			s.bar.set(stock / w.stockCap, C.Accent)
			local l = launchers[w.family]
			local stroke = s.btn:FindFirstChildOfClass("UIStroke") :: UIStroke
			local isSel = selectedWeapon == id
			stroke.Color = isSel and C.Accent or C.Line
			stroke.Transparency = isSel and 0 or 0.3
			stroke.Thickness = isSel and 2 or 1
			Lib.setButtonColor(s.btn, isSel and C.AccentSoft or C.Panel)
			if not l then
				s.sub.Text = "NO LAUNCHER"
				s.sub.TextColor3 = C.Bad
				s.reload.Size = UDim2.fromScale(1, 1)
			elseif l.ready == 0 and l.nextReady > now then
				s.sub.Text = ("RELOAD %ds"):format(math.ceil(l.nextReady - now))
				s.sub.TextColor3 = C.Gold
				s.reload.Size = UDim2.fromScale(1, 0.6)
			else
				s.sub.Text = ("%s · %d/%d READY"):format(w.short, l.ready, l.total)
				s.sub.TextColor3 = C.Muted
				s.reload.Size = UDim2.fromScale(1, 0)
			end
		end
	end
	if selectedWeapon and not slots[selectedWeapon] then
		WarView.selectWeapon(nil)
	end
end

function WarView.selectWeapon(id: string?)
	selectedWeapon = id
	reticle.Visible = id ~= nil
	blastRing.Parent = id and workspace or nil
	if id then
		local w = Weapons.get(id)
		if w then
			local d = w.radius * 2
			blastRing.Size = Vector3.new(0.3, d, d)
		end
		UnitView.clear()
		Sounds.play("Click", 1.3)
	end
	WarView.refreshHotbar()
	WarView.refreshHint()
end

function WarView.refreshHint()
	if selectedWeapon then
		local w = Weapons.get(selectedWeapon)
		hint.Text = ("ARMED: %s  ·  LMB LAUNCH  ·  RMB CANCEL"):format(string.upper(w and w.name or selectedWeapon))
		hint.TextColor3 = C.Accent
	elseif UnitView.count() > 0 then
		hint.Text = ("%d VEHICLES SELECTED  ·  RMB / TAP TO DRIVE THERE  ·  A RIVAL CITY TO INVADE (PVP)  ·  ESC CLEAR"):format(UnitView.count())
		hint.TextColor3 = C.Teal
	else
		hint.Text = "WASD PAN  ·  SCROLL ZOOM  ·  1-7 WEAPONS  ·  DRAG TO SELECT VEHICLES"
		hint.TextColor3 = C.TextSoft
	end
	if readout.sel then
		readout.sel.Text = ("%d SELECTED"):format(UnitView.count())
	end
end

---------------------------------------------------------------------------
-- Labels for strategic points and nations
---------------------------------------------------------------------------
local function makePointLabel(point: Model)
	if pointLabels[point] then
		return
	end
	local base = point:WaitForChild("Base", 5) :: BasePart?
	if not base then
		return
	end
	local bb = New("BillboardGui", {
		Name = "PointLabel",
		Adornee = base,
		Size = UDim2.fromOffset(250, 74),
		StudsOffsetWorldSpace = Vector3.new(0, 28, 0),
		AlwaysOnTop = true,
		MaxDistance = 6000,
		LightInfluence = 0,
		Enabled = false,
		Parent = labelParent,
	})
	local tag = New("Frame", {
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.12,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(240, 64),
		Parent = bb,
	}, { Lib.corner(3), Lib.stroke(C.Line, 1, 0.3), Lib.pad(6, 10) })
	local stripe = New("Frame", { BackgroundColor3 = C.Muted, BorderSizePixel = 0, Position = UDim2.new(0, -10, 0, -6), Size = UDim2.new(0, 3, 1, 12), Parent = tag })
	local title = Lib.display({ Name = "Title", Text = "", TextSize = 14, Size = UDim2.new(1, 0, 0, 16), Parent = tag })
	local status = Lib.display({ Name = "Status", Text = "", TextSize = 11, TextColor3 = C.Muted, Position = UDim2.fromOffset(0, 17), Size = UDim2.new(1, 0, 0, 13), Parent = tag })
	local bonus = Lib.text({ Name = "Bonus", Text = "", FontFace = Theme.Font.BodyBold, TextSize = 11, TextColor3 = C.Good, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 13), Parent = tag })
	local garrison = Lib.progress({ Segments = 10, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 4), Parent = tag })
	local capture = Lib.progress({ Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 3), Parent = tag })
	local function update()
		local owner = (point:GetAttribute("Owner") :: number?) or 0
		local ownerName = (point:GetAttribute("OwnerName") :: string?) or ""
		local name = (point:GetAttribute("PointName") :: string?) or point.Name
		local st
		local col
		if owner == 0 then
			st, col = "UNCAPTURED", C.Muted
		elseif owner == player.UserId then
			st, col = "HELD BY YOU", C.Good
		else
			st, col = "HELD BY " .. string.upper(ownerName), (point:GetAttribute("Color") :: Color3?) or C.Bad
		end
		if point:GetAttribute("Contested") then
			st ..= "  ·  CONTESTED"
			col = C.Gold
		end
		title.Text = name
		status.Text = st
		status.TextColor3 = col
		stripe.BackgroundColor3 = col
		local g = (point:GetAttribute("Garrison") :: number?) or 0
		local gm = (point:GetAttribute("MaxGarrison") :: number?) or 1
		garrison.set(g / gm, C.Bad)
		local c = (point:GetAttribute("Capture") :: number?) or 0
		capture.frame.Visible = c > 0
		capture.set(c / 100, C.Good)
		bonus.Text = (("%s  ·  GARRISON %d"):format(string.upper((point:GetAttribute("Bonus") :: string?) or ""), g))
	end
	point.AttributeChanged:Connect(update)
	update()
	pointLabels[point] = bb
end

local function makePlotLabels()
	local homeland = workspace:WaitForChild("Homeland")
	for i = 1, Config.MaxPlots do
		local plot = homeland:WaitForChild("Plot_" .. i, 10)
		if plot then
			local ground = plot:FindFirstChild("Ground") :: BasePart?
			local bb = New("BillboardGui", {
				Name = "NationLabel",
				Adornee = ground,
				Size = UDim2.fromOffset(300, 46),
				StudsOffsetWorldSpace = Vector3.new(0, 70, 0),
				AlwaysOnTop = true,
				MaxDistance = 8000,
				LightInfluence = 0,
				Enabled = false,
				Parent = labelParent,
			})
			local tag = New("Frame", {
				BackgroundColor3 = C.Panel,
				BackgroundTransparency = 0.12,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromOffset(280, 42),
				Visible = false,
				Parent = bb,
			}, { Lib.corner(3), Lib.stroke(C.Line, 1, 0.3) })
			local flagBox = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(45, 30), Parent = tag })
			local name = Lib.display({ Text = "", TextSize = 14, Position = UDim2.fromOffset(60, 4), Size = UDim2.new(1, -66, 0, 18), Parent = tag })
			local sub = Lib.display({ Text = "", TextSize = 11, Position = UDim2.fromOffset(60, 22), Size = UDim2.new(1, -66, 0, 14), Parent = tag })
			local lastFlag = ""
			local function update()
				local owner = plot:GetAttribute("OwnerId") :: number?
				local p = owner and Players:GetPlayerByUserId(owner)
				if not p then
					tag.Visible = false
					return
				end
				tag.Visible = true
				local flag = (p:GetAttribute("NationFlag") :: string?) or ""
				if flag ~= lastFlag then
					lastFlag = flag
					Lib.clear(flagBox)
					Flag.draw(flagBox, flag ~= "" and flag or nil)
				end
				local pvp = p:GetAttribute("Pvp") == true
				name.Text = string.upper((p:GetAttribute("NationName") :: string?) or (p.DisplayName .. "'s nation"))
				sub.Text = (p == player and "YOUR NATION  ·  " or ("COMMANDER " .. string.upper(p.DisplayName) .. "  ·  ")) .. (pvp and "PVP ON" or "PVP OFF")
				sub.TextColor3 = pvp and C.Bad or C.Muted
			end
			plot:GetAttributeChangedSignal("OwnerId"):Connect(update)
			task.spawn(function()
				while bb.Parent do
					update()
					task.wait(2)
				end
			end)
			table.insert(plotLabels, bb)
		end
	end
end

-- Label over a FOB: owner, health and supplies.
local function makeFobLabel(fob: Instance)
	if not fob:IsA("Model") or fobLabels[fob] then
		return
	end
	local base = fob:WaitForChild("Base", 5) :: BasePart?
	if not base then
		return
	end
	local mine = fob:GetAttribute("OwnerId") == player.UserId
	local bb = New("BillboardGui", {
		Name = "FobLabel",
		Adornee = base,
		Size = UDim2.fromOffset(200, 58),
		StudsOffsetWorldSpace = Vector3.new(0, 26, 0),
		AlwaysOnTop = true,
		MaxDistance = 6000,
		LightInfluence = 0,
		Enabled = ClientState.mode == "war",
		Parent = labelParent,
	})
	local tag = New("Frame", {
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.12,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(190, 52),
		Parent = bb,
	}, { Lib.corner(3), Lib.stroke(mine and C.Teal or C.Line, 1, 0.3), Lib.pad(5, 9) })
	New("Frame", { BackgroundColor3 = (fob:GetAttribute("Color") :: Color3?) or C.Muted, BorderSizePixel = 0, Position = UDim2.new(0, -9, 0, -5), Size = UDim2.new(0, 3, 1, 10), Parent = tag })
	Lib.display({ Text = ("FOB · %s"):format(mine and "YOURS" or string.upper((fob:GetAttribute("OwnerName") :: string?) or "")), TextSize = 13, Size = UDim2.new(1, 0, 0, 15), Parent = tag })
	local hpBar = Lib.progress({ Segments = 10, Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 5), Parent = tag })
	local supBar = Lib.progress({ Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 4), Parent = tag })
	local supText = Lib.text({ Text = "", FontFace = Theme.Font.Mono, TextSize = 10, TextColor3 = C.Muted, Position = UDim2.fromOffset(0, 35), Size = UDim2.new(1, 0, 0, 12), Parent = tag })
	local function update()
		local hp = (fob:GetAttribute("Hp") :: number?) or 0
		local max = (fob:GetAttribute("MaxHp") :: number?) or 1
		local sup = (fob:GetAttribute("Supplies") :: number?) or 0
		local cap = (fob:GetAttribute("SupplyCap") :: number?) or 1
		hpBar.set(hp / max, hp / max > 0.35 and C.Good or C.Bad)
		supBar.set(sup / cap, C.Gold)
		supText.Text = ("HP %d · SUPPLIES %d/%d"):format(hp, sup, cap)
	end
	fob.AttributeChanged:Connect(update)
	update()
	fobLabels[fob] = bb
	pcall(function()
		fob.Destroying:Connect(function()
			fobLabels[fob] = nil
			bb:Destroy()
		end)
	end)
end

---------------------------------------------------------------------------
-- Field orders for the selected units
---------------------------------------------------------------------------
local ORDERS = {
	{ key = "mount", order = "mount", label = "MOUNT UP", sub = "squads board transports" },
	{ key = "dismount", order = "dismount", label = "DISMOUNT", sub = "everyone out here" },
	{ key = "loadSupplies", order = "loadSupplies", label = "LOAD SUPPLIES", sub = "at home · 1 food + 1 steel each" },
	{ key = "unloadSupplies", order = "unloadSupplies", label = "UNLOAD AT FOB", sub = "fill the supply dump" },
	{ key = "fob", order = "fob", label = "SET UP FOB", sub = ("%s + %d steel"):format(Format.cash(Config.FobCost), Config.FobSteel) },
	{ key = "airliftFob", order = "airlift", arg = "fob", label = "AIRLIFT TO FOB", sub = "loads squads, supplies, a vehicle" },
	{ key = "airliftHome", order = "airlift", arg = "home", label = "AIRLIFT HOME", sub = "picks up squads at the FOB" },
}

function WarView.refreshOrders()
	if not ordersPanel then
		return
	end
	local f = { mount = false, dismount = false, loadSupplies = false, unloadSupplies = false, fob = false, airliftFob = false, airliftHome = false }
	local hasFob = #(ClientState.get("fobs") or {}) > 0
	for _, m in UnitView.selectedModels() do
		local def = Units.get(m:GetAttribute("UnitId") :: string)
		if def then
			local loc = (m:GetAttribute("Location") :: string?) or "home"
			local supplies = def.cargo and def.cargo.supplies or 0
			if def.class == "infantry" then
				f.mount = true
			end
			if m:GetAttribute("Cargo") or m:GetAttribute("Slung") then
				f.dismount = true
			end
			if supplies > 0 and loc == "home" then
				f.loadSupplies = true
			end
			if (m:GetAttribute("Supplies") or 0) > 0 and hasFob then
				f.unloadSupplies = true
			end
			if def.fob and loc == "mainland" then
				f.fob = true
			end
			if def.class == "air" and def.cargo then
				f.airliftFob = hasFob
				f.airliftHome = loc ~= "home"
			end
		end
	end
	local any = false
	for key, btn in orderButtons do
		btn.Visible = f[key] == true
		any = any or btn.Visible
	end
	ordersPanel.Visible = any
end

local function giveOrder(o)
	local uids = UnitView.selectedUids()
	local res = Net.request("UnitOrder", o.order, uids, o.arg)
	if res.ok then
		Sounds.play("Click", 1.1)
		local done = {
			mount = "%d squads boarding",
			dismount = "%d units out",
			loadSupplies = "%d supplies loaded",
			unloadSupplies = "%d supplies delivered to the FOB",
			airlift = "%d helicopters on the airlift",
		}
		local text = done[o.order]
		Notifications.show(text and text:format(res.count or 0) or "FOB established", "good")
	elseif res.err then
		Notifications.show(res.err, "bad")
	end
	task.delay(0.3, WarView.refreshOrders)
end

local function setLabels(on: boolean)
	for _, bb in pointLabels do
		bb.Enabled = on
	end
	for _, bb in plotLabels do
		bb.Enabled = on
	end
	for _, bb in fobLabels do
		bb.Enabled = on
	end
end

---------------------------------------------------------------------------
-- Camera
---------------------------------------------------------------------------
local function panHandler(_action: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	keys[input.KeyCode] = state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
	return Enum.ContextActionResult.Sink
end

-- What sits under the reticle: a strategic point, a nation, or open ground.
local function describeTarget(hit: Vector3): string
	for point, _ in pointLabels do
		local base = point:FindFirstChild("Base") :: BasePart?
		local bp = base and base.CFrame.Position
		if bp and (Vector3.new(bp.X, 0, bp.Z) - Vector3.new(hit.X, 0, hit.Z)).Magnitude < 110 then
			return string.upper(((point:GetAttribute("PointName") :: string?) or point.Name))
		end
	end
	for i = 1, Config.MaxPlots do
		if Grid.insidePlot(i, hit) then
			for _, p in Players:GetPlayers() do
				if p:GetAttribute("PlotIndex") == i then
					return string.upper((p:GetAttribute("NationName") :: string?) or p.DisplayName) .. (p == player and "  ·  OWN TERRITORY" or "")
				end
			end
			return "UNCLAIMED LAND"
		end
	end
	return ("GRID %04d·%04d"):format(math.floor(hit.X + 5000), math.floor(hit.Z + 5000))
end

local function updateCamera(dt: number)
	if ClientState.mode ~= "war" then
		return
	end
	local move = Vector3.zero
	if keys[Enum.KeyCode.W] or keys[Enum.KeyCode.Up] then
		move += Vector3.new(0, 0, -1)
	end
	if keys[Enum.KeyCode.S] or keys[Enum.KeyCode.Down] then
		move += Vector3.new(0, 0, 1)
	end
	if keys[Enum.KeyCode.A] or keys[Enum.KeyCode.Left] then
		move += Vector3.new(-1, 0, 0)
	end
	if keys[Enum.KeyCode.D] or keys[Enum.KeyCode.Right] then
		move += Vector3.new(1, 0, 0)
	end
	if move.Magnitude > 0 then
		focus += move.Unit * height * 1.3 * dt
	end
	local o = Config.MainlandOrigin
	focus = Vector3.new(math.clamp(focus.X, o.X - 2100, o.X + 2100), 0, math.clamp(focus.Z, o.Z - 2100, o.Z + 2100))
	local target = CFrame.lookAt(focus + Vector3.new(0, height, height * 0.22), focus)
	camera.CFrame = camera.CFrame:Lerp(target, math.min(1, dt * 10))

	readout.grid.Text = ("GRID %04d·%04d   ALT %dm"):format(math.floor(focus.X + 5000), math.floor(focus.Z + 5000), math.floor(height))

	-- reticle + blast ring + target readout
	if selectedWeapon then
		reticle.Position = UDim2.fromOffset(pointer.X, pointer.Y)
		local hit = groundAt(pointer)
		if hit then
			blastRing.CFrame = CFrame.new(hit.X, 0.3, hit.Z) * CFrame.Angles(0, 0, math.rad(90))
			targetLabel.Text = describeTarget(hit)
		end
	end
end

function WarView.go(target: string | number)
	Modal.close()
	Hub.call("closeBuild")
	if target == "mainland" then
		focus = Config.MainlandOrigin
		height = 1500
	elseif type(target) == "number" then
		focus = Grid.plotOrigin(target)
		height = 520
	end
	if ClientState.mode ~= "war" then
		ClientState.setMode("war")
		camera.CameraType = Enum.CameraType.Scriptable
		ContextActionService:BindActionAtPriority("WarPan", panHandler, false, Enum.ContextActionPriority.High.Value + 10, table.unpack(PAN_KEYS))
		camera.CFrame = CFrame.lookAt(focus + Vector3.new(0, height, height * 0.22), focus)
	end
	if target == "mainland" then
		readout.theater.Text = "CENTRAL FRONT"
	elseif type(target) == "number" then
		local name = "UNCLAIMED LAND"
		for _, p in Players:GetPlayers() do
			if p:GetAttribute("PlotIndex") == target then
				name = string.upper((p:GetAttribute("NationName") :: string?) or (p.DisplayName .. "'s nation"))
			end
		end
		readout.theater.Text = name
	end
	setLabels(true)
	renderHotbar()
	WarView.refreshHint()
	hint.Visible = true
	Sounds.play("Whoosh")
end

function WarView.goHome()
	if ClientState.mode ~= "war" then
		return
	end
	ContextActionService:UnbindAction("WarPan")
	table.clear(keys)
	WarView.selectWeapon(nil)
	UnitView.clear()
	setLabels(false)
	hotbar.Visible = false
	hint.Visible = false
	selectBox.Visible = false
	camera.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		camera.CameraSubject = hum
	end
	ClientState.setMode("play")
end

---------------------------------------------------------------------------
-- Travel menu
---------------------------------------------------------------------------
function WarView.openTravel()
	local win = Modal.open("Theater Select", "Pick a theater. Launch strikes and command vehicles from the map.", 820, 560)
	local ic = Icons.map(36, C.Accent)
	ic.Position = UDim2.fromOffset(8, 6)
	ic.Parent = win.iconHolder

	-- left: fixed theaters
	local left = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 300, 1, 0), Parent = win.body }, { Lib.list("y", 10) })
	local function theater(name: string, order: number, h: number, title: string, sub: string, accent: Color3, onClick: () -> ()): TextButton
		local btn = Lib.button({
			Name = name,
			BackgroundColor3 = C.Raised,
			Size = UDim2.new(1, 0, 0, h),
			LayoutOrder = order,
			Parent = left,
			Activated = onClick,
		}, { Lib.corner(Theme.Radius.Card), Lib.stroke(accent, 1, 0.55) })
		New("Frame", { BackgroundColor3 = accent, BorderSizePixel = 0, Size = UDim2.new(0, 3, 1, 0), Parent = btn })
		Lib.display({ Text = string.upper(title), TextSize = 17, Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -28, 0, 20), Parent = btn })
		Lib.text({
			Text = sub,
			TextSize = 12,
			TextColor3 = C.Muted,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(16, 32),
			Size = UDim2.new(1, -28, 0, 30),
			Parent = btn,
		})
		return btn
	end

	local held, total = 0, 0
	local mainland = workspace:FindFirstChild("Mainland")
	local points = mainland and mainland:FindFirstChild("Points")
	if points then
		for _, p in points:GetChildren() do
			total += 1
			if p:GetAttribute("Owner") == player.UserId then
				held += 1
			end
		end
	end
	local deployed = 0
	for _, m in UnitView.mine() do
		if (m:GetAttribute("Location") or "home") ~= "home" then
			deployed += 1
		end
	end
	local war = theater("Mainland", 1, 170, "Central front", "The battlefield every nation's bridge leads to. Capture points for permanent bonuses.", C.Bad, function()
		WarView.go("mainland")
	end)
	Lib.hazard({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 3, 1, 0), Size = UDim2.new(1, -3, 0, 5), Parent = war }, C.Bad, C.Raised, 9)
	Lib.chip("WARZONE", C.BadSoft, C.Bad, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Parent = war })
	Lib.caption("Points held", { Position = UDim2.fromOffset(16, 80), Size = UDim2.fromOffset(120, 14), Parent = war })
	Lib.display({ Text = ("%d / %d"):format(held, total), TextSize = 26, TextColor3 = held > 0 and C.Good or C.Text, Position = UDim2.fromOffset(16, 96), Size = UDim2.fromOffset(140, 30), Parent = war })
	Lib.caption("Deployed", { Position = UDim2.fromOffset(160, 80), Size = UDim2.fromOffset(120, 14), Parent = war })
	Lib.display({ Text = tostring(deployed), TextSize = 26, Position = UDim2.fromOffset(160, 96), Size = UDim2.fromOffset(120, 30), Parent = war })

	theater("Overview", 2, 74, "Your nation · overview", "Command vehicles and watch your city from above.", C.Accent, function()
		WarView.go(ClientState.get("plot") or 1)
	end)
	theater("Walk", 3, 74, "Your nation · on foot", "Back to your commander.", C.Teal, function()
		Modal.close()
		WarView.goHome()
	end)

	-- right: rival nations
	local right = Lib.inset({ Position = UDim2.fromOffset(316, 0), Size = UDim2.new(1, -316, 1, 0), Parent = win.body }, { Lib.pad(12) })
	Lib.caption("Rival nations", { TextColor3 = C.Accent, Parent = right })
	local list = Lib.scroll({ Name = "Nations", Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 1, -22), Parent = right }, { Lib.list("y", 8) })
	local count = 0
	for _, p in Players:GetPlayers() do
		local idx = p:GetAttribute("PlotIndex") :: number?
		if p ~= player and idx then
			count += 1
			local pvp = p:GetAttribute("Pvp") == true
			local row = Lib.card({ Name = "Nation_" .. p.UserId, Size = UDim2.new(1, -8, 0, 64), LayoutOrder = pvp and count or 100 + count, Parent = list })
			local flagBox = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 12), Size = UDim2.fromOffset(60, 40), Parent = row }, { Lib.stroke(C.Line, 1, 0.3) })
			Flag.draw(flagBox, p:GetAttribute("NationFlag") :: string?)
			Lib.display({
				Text = string.upper((p:GetAttribute("NationName") :: string?) or (p.DisplayName .. "'s nation")),
				TextSize = 15,
				Position = UDim2.fromOffset(82, 11),
				Size = UDim2.new(1, -250, 0, 18),
				Parent = row,
			})
			Lib.text({
				Text = ("Cmdr %s  ·  %s  ·  Power %s"):format(p.DisplayName, (p:GetAttribute("RankName") :: string?) or "Outpost", Format.short((p:GetAttribute("Power") :: number?) or 0)),
				TextSize = 12,
				TextColor3 = C.Muted,
				Position = UDim2.fromOffset(82, 32),
				Size = UDim2.new(1, -250, 0, 16),
				Parent = row,
			})
			Lib.chip(pvp and "PVP ON" or "PVP OFF", pvp and C.BadSoft or C.Inset, pvp and C.Bad or C.Muted, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -92, 0.5, 0),
				Parent = row,
			})
			Lib.button({
				Name = "View",
				Variant = pvp and "danger" or "secondary",
				Text = "VIEW",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(72, 34),
				Parent = row,
				Activated = function()
					WarView.go(idx)
				end,
			})
		end
	end
	if count == 0 then
		Lib.text({
			Name = "Empty",
			Text = "No other nations on this server yet. The central front is still yours to take.",
			TextWrapped = true,
			TextColor3 = C.Muted,
			Size = UDim2.new(1, -8, 0, 40),
			Parent = list,
		})
	end
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------
local function launchAt(screen: Vector2)
	local id = selectedWeapon
	local hit = groundAt(screen)
	if not id or not hit then
		return
	end
	local res = Net.request("LaunchWeapon", id, hit)
	if res.ok then
		Sounds.play("Launch")
	elseif res.err then
		Notifications.show(res.err, "bad")
	end
end

local function commandAt(screen: Vector2)
	local uids = UnitView.selectedUids()
	local hit = groundAt(screen)
	if #uids == 0 or not hit then
		return
	end
	local res = Net.request("CommandUnits", uids, hit)
	if res.ok then
		Sounds.play("Click", 0.9)
		Hub.call("moveMarker", hit)
	elseif res.err then
		Notifications.show(res.err, "bad")
	end
end

local function finishBox(endPos: Vector2, additive: boolean)
	local start = boxStart
	boxStart = nil
	selectBox.Visible = false
	if not start then
		return
	end
	if (endPos - start).Magnitude < 6 then
		local unit = unitUnder(endPos)
		if unit then
			if not additive then
				UnitView.clear()
			end
			UnitView.select(unit, not UnitView.isSelected(unit))
		elseif UnitView.count() > 0 and UserInputService.TouchEnabled then
			commandAt(endPos) -- tap ground to move on touch devices
		else
			UnitView.clear()
		end
	else
		if not additive then
			UnitView.clear()
		end
		local minV = Vector2.new(math.min(start.X, endPos.X), math.min(start.Y, endPos.Y))
		local maxV = Vector2.new(math.max(start.X, endPos.X), math.max(start.Y, endPos.Y))
		for _, m in UnitView.mine() do
			local root = m.PrimaryPart
			if root then
				-- WorldToScreenPoint is in GUI space, same as InputObject.Position
				local sp, onScreen = camera:WorldToScreenPoint(root.CFrame.Position)
				local p = Vector2.new(sp.X, sp.Y)
				if onScreen and p.X >= minV.X and p.X <= maxV.X and p.Y >= minV.Y and p.Y <= maxV.Y then
					UnitView.select(m, true)
				end
			end
		end
	end
	WarView.refreshHint()
end

local function onInputBegan(input: InputObject, processed: boolean)
	if ClientState.mode ~= "war" then
		return
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		pointer = Vector2.new(input.Position.X, input.Position.Y)
		if processed then
			return
		end
		if selectedWeapon then
			launchAt(pointer)
		else
			boxStart = pointer
		end
	elseif t == Enum.UserInputType.MouseButton2 then
		rmbStart = Vector2.new(input.Position.X, input.Position.Y)
	elseif not processed and t == Enum.UserInputType.Keyboard then
		local n = input.KeyCode.Value - Enum.KeyCode.One.Value + 1
		if n >= 1 and n <= 9 then
			local list = availableWeapons()
			local w = list[n]
			if w then
				WarView.selectWeapon(selectedWeapon ~= w.id and w.id or nil)
			end
		elseif input.KeyCode == Enum.KeyCode.Escape then
			WarView.selectWeapon(nil)
			UnitView.clear()
			WarView.refreshHint()
		end
	end
end

local function onInputChanged(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		pointer = Vector2.new(input.Position.X, input.Position.Y)
		if boxStart and ClientState.mode == "war" and input.UserInputType == Enum.UserInputType.MouseMovement then
			local minV = Vector2.new(math.min(boxStart.X, pointer.X), math.min(boxStart.Y, pointer.Y))
			local size = Vector2.new(math.abs(pointer.X - boxStart.X), math.abs(pointer.Y - boxStart.Y))
			selectBox.Visible = size.Magnitude > 6
			selectBox.Position = UDim2.fromOffset(minV.X, minV.Y)
			selectBox.Size = UDim2.fromOffset(size.X, size.Y)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and ClientState.mode == "war" then
		height = math.clamp(height * (1 - input.Position.Z * 0.12), 120, 2800)
	end
end

local function onInputEnded(input: InputObject)
	if ClientState.mode ~= "war" then
		return
	end
	local t = input.UserInputType
	local pos = Vector2.new(input.Position.X, input.Position.Y)
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		if boxStart then
			finishBox(pos, UserInputService:IsKeyDown(Enum.KeyCode.LeftShift))
		end
	elseif t == Enum.UserInputType.MouseButton2 and rmbStart then
		if (pos - rmbStart).Magnitude < 8 then
			if selectedWeapon then
				WarView.selectWeapon(nil)
			else
				commandAt(pos)
			end
		end
		rmbStart = nil
	end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
function WarView.init(screen: GuiObject)
	labelParent = player:WaitForChild("PlayerGui")

	-- strategic-view frame: vignette + screen brackets, drawn beneath the HUD
	warOverlay = New("Frame", {
		Name = "WarOverlay",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Visible = false,
		Parent = screen,
	})
	for _, e in { { 0, 0, 1, 0, 90 }, { 0, 1, 1, 0, -90 }, { 0, 0, 0, 1, 0 }, { 1, 0, 0, 1, 180 } } do
		local horizontal = e[3] == 1
		New("Frame", {
			BackgroundColor3 = Color3.fromRGB(4, 8, 6),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(e[1], e[2]),
			Position = UDim2.fromScale(e[1], e[2]),
			Size = horizontal and UDim2.new(1, 0, 0, 140) or UDim2.new(0, 220, 1, 0),
			ZIndex = 0,
			Parent = warOverlay,
		}, {
			New("UIGradient", {
				Rotation = e[5],
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
			}),
		})
	end
	local frameInset = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16), ZIndex = 0, Parent = warOverlay })
	Lib.brackets(frameInset, C.Accent, 34, 2, 0)

	-- theater readout (takes the mission card's slot while in war mode)
	local panel = Lib.panel({
		Name = "Theater",
		Position = UDim2.fromOffset(16, 104),
		Size = UDim2.fromOffset(300, 104),
		Parent = warOverlay,
	}, { Lib.pad(10, 14) })
	Lib.caption("Theater", { TextColor3 = C.Accent, Parent = panel })
	readout.theater = Lib.display({ Name = "Name", Text = "CENTRAL FRONT", TextSize = 20, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 24), Parent = panel })
	readout.grid = Lib.text({ Name = "Grid", Text = "", FontFace = Theme.Font.Mono, TextSize = 12, TextColor3 = C.Muted, Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 16), Parent = panel })
	readout.sel = Lib.display({ Name = "Selected", Text = "0 SELECTED", TextSize = 12, TextColor3 = C.Teal, Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 16), Parent = panel })

	ordersPanel = Lib.panel({
		Name = "Orders",
		Position = UDim2.fromOffset(16, 216),
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = warOverlay,
	}, { Lib.pad(10, 12), Lib.list("y", 6) })
	Lib.caption("Field orders", { TextColor3 = C.Accent, LayoutOrder = 0, Parent = ordersPanel })
	for i, o in ORDERS do
		local btn = Lib.button({
			Name = "Order_" .. o.key,
			Variant = (o.order == "fob" or o.order == "airlift") and "primary" or "secondary",
			Text = "",
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = i,
			Visible = false,
			Parent = ordersPanel,
			Activated = function()
				giveOrder(o)
			end,
		})
		Lib.display({ Text = o.label, TextSize = 14, TextColor3 = btn.TextColor3, Position = UDim2.fromOffset(12, 3), Size = UDim2.new(1, -24, 0, 18), Parent = btn })
		Lib.text({ Text = o.sub, TextSize = 11, TextColor3 = btn.TextColor3, TextTransparency = 0.25, Position = UDim2.fromOffset(12, 21), Size = UDim2.new(1, -24, 0, 14), Parent = btn })
		orderButtons[o.key] = btn
	end

	hotbar = New("Frame", {
		Name = "Hotbar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -112),
		Size = UDim2.fromOffset(760, 90),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	}, { Lib.list("x", 6, Enum.HorizontalAlignment.Center) })

	-- targeting reticle: brackets, crosshair ticks and a live target readout
	reticle = New("Frame", {
		Name = "Reticle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(52, 52),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	})
	Lib.brackets(reticle, C.Accent, 13, 2, 0)
	for _, t in { { 0.5, 0, 2, 9 }, { 0.5, 1, 2, 9 }, { 0, 0.5, 9, 2 }, { 1, 0.5, 9, 2 } } do
		New("Frame", {
			BackgroundColor3 = C.Accent,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(t[1], t[2]),
			Position = UDim2.new(t[1], t[1] == 0.5 and 0 or (t[1] == 0 and 13 or -13), t[2], t[2] == 0.5 and 0 or (t[2] == 0 and 13 or -13)),
			Size = UDim2.fromOffset(t[3], t[4]),
			Parent = reticle,
		})
	end
	New("Frame", { BackgroundColor3 = C.Accent, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 4), Parent = reticle }, { Lib.round() })
	targetLabel = Lib.display({
		Name = "Target",
		Text = "",
		TextSize = 11,
		TextColor3 = C.Accent,
		TextStrokeTransparency = 0.4,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		Size = UDim2.fromOffset(240, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = reticle,
	})

	selectBox = New("Frame", {
		Name = "SelectBox",
		BackgroundColor3 = C.Teal,
		BackgroundTransparency = 0.88,
		Visible = false,
		Parent = screen,
	}, { Lib.stroke(C.Teal, 1, 0.1) })

	hint = Lib.display({
		Name = "Hint",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -210),
		Size = UDim2.fromOffset(760, 18),
		TextColor3 = C.TextSoft,
		TextStrokeTransparency = 0.55,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = screen,
	})

	blastRing = Instance.new("Part")
	blastRing.Name = "BlastRing"
	blastRing.Shape = Enum.PartType.Cylinder
	blastRing.Anchored = true
	blastRing.CanCollide = false
	blastRing.CanQuery = false
	blastRing.CanTouch = false
	blastRing.Material = Enum.Material.Neon
	blastRing.Color = C.Accent
	blastRing.Transparency = 0.72
	blastRing.CastShadow = false

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.InputEnded:Connect(onInputEnded)
	UserInputService.TouchPinch:Connect(function(_positions, scale, _velocity, state)
		if ClientState.mode == "war" and state == Enum.UserInputState.Change then
			height = math.clamp(height / math.max(0.5, scale ^ 0.05), 120, 2800)
		end
	end)
	UserInputService.TouchPan:Connect(function(_positions, _translation, velocity, state)
		if ClientState.mode == "war" and not selectedWeapon and state == Enum.UserInputState.Change then
			boxStart = nil
			focus -= Vector3.new(velocity.X, 0, velocity.Y) * height * 0.00035
		end
	end)
	RunService.RenderStepped:Connect(updateCamera)

	ClientState.onAny(function(patch)
		if ClientState.mode ~= "war" then
			return
		end
		if patch.researched or patch.passes then
			renderHotbar()
		elseif patch.inventory or patch.launchers then
			WarView.refreshHotbar()
		end
	end)
	ClientState.onMode(function(mode)
		warOverlay.Visible = mode == "war"
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if ClientState.mode == "war" then
				WarView.refreshHotbar()
				WarView.refreshOrders()
			end
		end
	end)
	UnitView.onSelectionChanged(WarView.refreshHint)
	UnitView.onSelectionChanged(WarView.refreshOrders)

	-- labels
	task.spawn(function()
		local mainland = workspace:WaitForChild("Mainland")
		local points = mainland:WaitForChild("Points")
		for _, p in points:GetChildren() do
			task.spawn(makePointLabel, p :: Model)
		end
		points.ChildAdded:Connect(function(p)
			makePointLabel(p :: Model)
		end)
	end)
	task.spawn(makePlotLabels)
	task.spawn(function()
		local fobs = workspace:WaitForChild("Mainland"):WaitForChild("Fobs")
		for _, f in fobs:GetChildren() do
			task.spawn(makeFobLabel, f)
		end
		fobs.ChildAdded:Connect(function(f)
			makeFobLabel(f)
		end)
	end)

	Hub.openTravel = WarView.openTravel
	Hub.goWar = WarView.go
	Hub.goHome = WarView.goHome
end

return WarView
