--[[
	WarView
	"Travel" opens the strategic view: a top-down camera over the mainland or
	any nation. From here you:
	  * pick a weapon in the hotbar (1-7) and click to launch at the reticle
	  * drag a box (or tap) to select your vehicles, right-click / tap to move
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
local ModelBuilder = require(Shared.ModelBuilder)
local Unlocks = require(Shared.Util.Unlocks)
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

local focus = Vector3.zero
local height = 620
local keys: { [Enum.KeyCode]: boolean } = {}
local selectedWeapon: string? = nil
local pointer = Vector2.zero
local boxStart: Vector2? = nil
local rmbStart: Vector2? = nil
local slots: { [string]: { btn: TextButton, count: TextLabel, sub: TextLabel } } = {}

local RETICLE = Color3.fromRGB(232, 150, 52)
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
			local sp, onScreen = camera:WorldToScreenPoint(root.Position)
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
			Size = UDim2.fromOffset(66, 66),
			BackgroundColor3 = Theme.Color.Hud,
			BackgroundTransparency = 0.25,
			LayoutOrder = i,
			Parent = hotbar,
			Activated = function()
				WarView.selectWeapon(selectedWeapon ~= w.id and w.id or nil)
			end,
		}, { Lib.corner(8), Lib.stroke(Color3.new(1, 1, 1), 1, 0.8) })
		local art = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 10), Size = UDim2.new(1, -8, 0, 36), Parent = btn })
		Lib.viewport(ModelBuilder.projectile(w), { Parent = art }, 90)
		local count = Lib.text({
			Text = "0",
			TextColor3 = Theme.Color.HudText,
			FontFace = Theme.Font.Bold,
			TextSize = Theme.TextSize.Tiny,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -5, 0, 3),
			Size = UDim2.fromOffset(30, 12),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = btn,
		})
		local sub = Lib.text({
			Text = w.short,
			TextColor3 = Theme.Color.HudMuted,
			FontFace = Theme.Font.Bold,
			TextSize = 10,
			Position = UDim2.new(0, 0, 1, -16),
			Size = UDim2.new(1, 0, 0, 12),
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = btn,
		})
		Lib.text({
			Text = tostring(i),
			TextColor3 = Theme.Color.HudMuted,
			TextSize = 10,
			Position = UDim2.fromOffset(5, 2),
			Size = UDim2.fromOffset(10, 12),
			Parent = btn,
		})
		slots[w.id] = { btn = btn, count = count, sub = sub }
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
			s.count.Text = tostring(inv[id] or 0)
			local l = launchers[w.family]
			local stroke = s.btn:FindFirstChildOfClass("UIStroke") :: UIStroke
			local isSel = selectedWeapon == id
			stroke.Color = isSel and Theme.Color.Teal or Color3.new(1, 1, 1)
			stroke.Transparency = isSel and 0 or 0.8
			stroke.Thickness = isSel and 2 or 1
			if not l then
				s.sub.Text = "NO LAUNCHER"
			elseif l.ready == 0 and l.nextReady > now then
				s.sub.Text = ("RELOAD %ds"):format(math.ceil(l.nextReady - now))
			else
				s.sub.Text = w.short
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
		hint.Text = ("%s selected · Click a target to launch · Right-click to cancel"):format(w and w.name or selectedWeapon)
	elseif UnitView.count() > 0 then
		hint.Text = ("%d units selected · Right-click (or tap) the ground to move · Esc to clear"):format(UnitView.count())
	else
		hint.Text = "WASD pan · Scroll zoom · 1-7 weapons · Drag to select vehicles"
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
		Size = UDim2.fromOffset(260, 56),
		StudsOffsetWorldSpace = Vector3.new(0, 24, 0),
		AlwaysOnTop = true,
		MaxDistance = 6000,
		LightInfluence = 0,
		Enabled = false,
		Parent = labelParent,
	})
	local title = Lib.text({
		Name = "Title",
		Text = "",
		TextColor3 = Color3.fromRGB(240, 240, 232),
		TextStrokeTransparency = 0.5,
		FontFace = Theme.Font.Semi,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 18),
		Parent = bb,
	})
	local bonus = Lib.text({
		Name = "Bonus",
		Text = point:GetAttribute("Bonus") :: string? or "",
		TextColor3 = Color3.fromRGB(200, 220, 180),
		TextStrokeTransparency = 0.6,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 17),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = bb,
	})
	local garrison = Lib.progress({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 36), Size = UDim2.fromOffset(120, 4), Parent = bb })
	local capture = Lib.progress({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.fromOffset(120, 4), Parent = bb })
	local function update()
		local owner = (point:GetAttribute("Owner") :: number?) or 0
		local ownerName = (point:GetAttribute("OwnerName") :: string?) or ""
		local name = (point:GetAttribute("PointName") :: string?) or point.Name
		local status
		if owner == 0 then
			status = "UNCAPTURED"
		elseif owner == player.UserId then
			status = "YOURS"
		else
			status = string.upper(ownerName)
		end
		if point:GetAttribute("Contested") then
			status ..= " · CONTESTED"
		end
		title.Text = ("%s  ·  %s"):format(name, status)
		title.TextColor3 = owner == player.UserId and Color3.fromRGB(140, 230, 160) or Color3.fromRGB(240, 240, 232)
		local g = (point:GetAttribute("Garrison") :: number?) or 0
		local gm = (point:GetAttribute("MaxGarrison") :: number?) or 1
		garrison.set(g / gm, Theme.Color.Bad)
		local c = (point:GetAttribute("Capture") :: number?) or 0
		capture.frame.Visible = c > 0
		capture.set(c / 100, Theme.Color.Good)
		bonus.Text = ((point:GetAttribute("Bonus") :: string?) or "") .. ("  ·  garrison %d"):format(g)
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
				Size = UDim2.fromOffset(300, 40),
				StudsOffsetWorldSpace = Vector3.new(0, 60, 0),
				AlwaysOnTop = true,
				MaxDistance = 8000,
				LightInfluence = 0,
				Enabled = false,
				Parent = labelParent,
			})
			local label = Lib.text({
				Text = "",
				TextColor3 = Color3.new(1, 1, 1),
				TextStrokeTransparency = 0.4,
				FontFace = Theme.Font.Bold,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.fromScale(1, 1),
				Parent = bb,
			})
			local function update()
				local owner = plot:GetAttribute("OwnerId") :: number?
				local p = owner and Players:GetPlayerByUserId(owner)
				if not p then
					label.Text = ""
					return
				end
				local pvp = p:GetAttribute("Pvp") == true
				label.Text = ("%s%s  ·  PVP %s"):format(p == player and "YOUR NATION - " or "", string.upper(p.DisplayName), pvp and "ON" or "OFF")
				label.TextColor3 = pvp and Color3.fromRGB(255, 170, 160) or Color3.fromRGB(220, 230, 240)
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

local function setLabels(on: boolean)
	for _, bb in pointLabels do
		bb.Enabled = on
	end
	for _, bb in plotLabels do
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
	focus = Vector3.new(math.clamp(focus.X, -2600, 2600), 0, math.clamp(focus.Z, -800, 4600))
	local target = CFrame.lookAt(focus + Vector3.new(0, height, height * 0.22), focus)
	camera.CFrame = camera.CFrame:Lerp(target, math.min(1, dt * 10))

	-- reticle + blast ring
	if selectedWeapon then
		reticle.Position = UDim2.fromOffset(pointer.X, pointer.Y)
		local hit = groundAt(pointer)
		if hit then
			blastRing.CFrame = CFrame.new(hit.X, 0.3, hit.Z) * CFrame.Angles(0, 0, math.rad(90))
		end
	end
end

function WarView.go(target: string | number)
	Modal.close()
	Hub.call("closeBuild")
	if target == "mainland" then
		focus = Config.MainlandOrigin
		height = 900
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
	local win = Modal.open("Travel", "Choose where to look. Launch strikes and command units from the map.", 520, 520)
	local ic = Icons.map(38, Theme.Color.Accent)
	ic.Position = UDim2.fromOffset(6, 4)
	ic.Parent = win.iconHolder
	local list = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		BorderSizePixel = 0,
		Parent = win.body,
	}, { Lib.list("y", 8) })
	local function entry(order: number, title: string, sub: string, chipText: string?, chipBad: boolean?, onClick: () -> ())
		local btn = Lib.button({ Size = UDim2.new(1, -6, 0, 58), LayoutOrder = order, Parent = list, Activated = onClick }, { Lib.corner(8), Lib.stroke(), Lib.pad(8, 14) })
		Lib.text({ Text = title, FontFace = Theme.Font.Bold, Size = UDim2.new(1, -120, 0, 22), Parent = btn })
		Lib.text({ Text = sub, TextSize = Theme.TextSize.Small, TextColor3 = Theme.Color.Muted, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, -120, 0, 18), Parent = btn })
		if chipText then
			Lib.chip(chipText, chipBad and Theme.Color.BadSoft or Theme.Color.GoodSoft, chipBad and Theme.Color.Bad or Theme.Color.Good, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				Parent = btn,
			})
		end
	end
	entry(1, "Mainland - War Map", "Capture strategic points for big bonuses", "WARZONE", true, function()
		WarView.go("mainland")
	end)
	entry(2, "Your Nation (overview)", "Command units and watch your city from above", nil, nil, function()
		WarView.go(ClientState.get("plot") or 1)
	end)
	entry(3, "Your Nation (walk)", "Back to your character", nil, nil, function()
		Modal.close()
		WarView.goHome()
	end)
	local order = 10
	for _, p in Players:GetPlayers() do
		if p ~= player then
			local idx = p:GetAttribute("PlotIndex") :: number?
			if idx then
				order += 1
				local pvp = p:GetAttribute("Pvp") == true
				entry(order, p.DisplayName .. "'s Nation", pvp and "PvP ON - can be attacked" or "PvP OFF - can't be attacked", pvp and "PVP ON" or "PVP OFF", pvp, function()
					WarView.go(idx)
				end)
			end
		end
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
				local sp, onScreen = camera:WorldToScreenPoint(root.Position)
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
		height = math.clamp(height * (1 - input.Position.Z * 0.12), 120, 1800)
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
	hotbar = New("Frame", {
		Name = "Hotbar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.fromOffset(600, 66),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	}, { Lib.list("x", 6, Enum.HorizontalAlignment.Center) })

	reticle = New("Frame", {
		Name = "Reticle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(46, 46),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	})
	for _, c in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local corner = New("Frame", {
			AnchorPoint = Vector2.new(c[1], c[2]),
			Position = UDim2.fromScale(c[1], c[2]),
			Size = UDim2.fromOffset(12, 12),
			BackgroundTransparency = 1,
			Parent = reticle,
		})
		New("Frame", { BackgroundColor3 = RETICLE, BorderSizePixel = 0, Size = UDim2.fromOffset(12, 2), Position = UDim2.fromOffset(0, c[2] == 0 and 0 or 10), Parent = corner })
		New("Frame", { BackgroundColor3 = RETICLE, BorderSizePixel = 0, Size = UDim2.fromOffset(2, 12), Position = UDim2.fromOffset(c[1] == 0 and 0 or 10, 0), Parent = corner })
	end
	New("Frame", { BackgroundColor3 = RETICLE, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 4), Parent = reticle }, { Lib.round() })

	selectBox = New("Frame", {
		Name = "SelectBox",
		BackgroundColor3 = Color3.fromRGB(90, 230, 130),
		BackgroundTransparency = 0.85,
		Visible = false,
		Parent = screen,
	}, { Lib.stroke(Color3.fromRGB(90, 230, 130), 1) })

	hint = Lib.text({
		Name = "Hint",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -168),
		Size = UDim2.fromOffset(700, 20),
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.5,
		TextSize = Theme.TextSize.Small,
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
	blastRing.Color = RETICLE
	blastRing.Transparency = 0.72
	blastRing.CastShadow = false

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.InputEnded:Connect(onInputEnded)
	UserInputService.TouchPinch:Connect(function(_positions, scale, _velocity, state)
		if ClientState.mode == "war" and state == Enum.UserInputState.Change then
			height = math.clamp(height / math.max(0.5, scale ^ 0.05), 120, 1800)
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
	task.spawn(function()
		while true do
			task.wait(0.5)
			if ClientState.mode == "war" then
				WarView.refreshHotbar()
			end
		end
	end)
	UnitView.onSelectionChanged(WarView.refreshHint)

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

	Hub.openTravel = WarView.openTravel
	Hub.goWar = WarView.go
	Hub.goHome = WarView.goHome
end

return WarView
