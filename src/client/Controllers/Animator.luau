--[[
	Animator
	Makes the cities feel alive (client-side only, distance culled):
	  * wind turbine rotors and radar dishes spin, pump jacks rock
	  * construction progress bars over buildings being built
	  * fuel trucks drive refinery -> factory -> refinery along the grid
	  * soldiers' legs swing while they march, helicopter rotors spin
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local ModelBuilder = require(Shared.ModelBuilder)
local Format = require(Shared.Util.Format)

local Client = script.Parent.Parent
local Lib = require(Client.UI.Lib)
local Theme = require(Client.UI.Theme)

local New = Lib.New

local Animator = {}

local camera = workspace.CurrentCamera
local CULL = 650

type Spinner = { sub: Model, base: CFrame, speed: number, axis: string, rock: number?, phase: number }

local spinners: { [Model]: Spinner } = {}
local bars: { [Model]: { gui: BillboardGui, bar: Lib.Progress, label: TextLabel } } = {}
local trucks: { [string]: Model } = {}

-- Unit rigs: Motor6D hips (Swing = +-1) and rotor joints (Spin = rad/s).
type Rig = { hips: { Motor6D }, rotors: { Motor6D }, phase: number }
local rigs: { [Model]: Rig } = {}

function Animator.registerRig(m: Instance)
	if not m:IsA("Model") then
		return
	end
	local hips, rotors = {}, {}
	for _, d in m:GetDescendants() do
		if d:IsA("Motor6D") then
			if d:GetAttribute("Swing") then
				table.insert(hips, d)
			elseif d:GetAttribute("Spin") then
				table.insert(rotors, d)
			end
		end
	end
	if #hips > 0 or #rotors > 0 then
		rigs[m] = { hips = hips, rotors = rotors, phase = math.random() * 6 }
	end
end

-- Returns how many joints were posed this frame.
function Animator.animateRigs(t: number): number
	local camPos = camera.CFrame.Position
	local posed = 0
	for m, r in rigs do
		local root = m.PrimaryPart
		if root and (root.CFrame.Position - camPos).Magnitude < CULL * 1.6 then
			local moving = m:GetAttribute("Moving") == true
			for _, hip in r.hips do
				local swing = (hip:GetAttribute("Swing") :: number?) or 1
				hip.Transform = moving and CFrame.Angles(math.sin(t * 9 + r.phase) * 0.7 * swing, 0, 0) or CFrame.new()
				posed += 1
			end
			local rate = moving and 1 or 0.45
			for _, rotor in r.rotors do
				local spin = (rotor:GetAttribute("Spin") :: number?) or 10
				rotor.Transform = CFrame.Angles(0, (t + r.phase) * spin * rate % (math.pi * 2), 0)
				posed += 1
			end
		end
	end
	return posed
end
local refineries: { [Model]: boolean } = {}

local function axisAngles(axis: string, angle: number): CFrame
	if axis == "X" then
		return CFrame.Angles(angle, 0, 0)
	elseif axis == "Y" then
		return CFrame.Angles(0, angle, 0)
	end
	return CFrame.Angles(0, 0, angle)
end

local function registerSpinners(building: Model)
	for _, d in building:GetDescendants() do
		if d:IsA("Model") and (d:GetAttribute("Spin") or d:GetAttribute("Rock")) and d.PrimaryPart then
			spinners[d] = {
				sub = d,
				base = d:GetPivot(),
				speed = (d:GetAttribute("Spin") :: number?) or 2,
				axis = (d:GetAttribute("SpinAxis") :: string?) or "Y",
				rock = d:GetAttribute("Rock") :: number?,
				phase = math.random() * 10,
			}
		end
	end
	local base = building.PrimaryPart
	if base then
		-- the server moved the building: re-read the rest pose
		base:GetPropertyChangedSignal("CFrame"):Connect(function()
			task.defer(function()
				for sub, s in spinners do
					if sub:IsDescendantOf(building) then
						s.base = sub:GetPivot()
					end
				end
			end)
		end)
	end
end

local function updateBar(building: Model)
	local finishAt = building:GetAttribute("FinishAt") :: number?
	local existing = bars[building]
	if finishAt and not existing then
		local base = building.PrimaryPart
		if not base then
			return
		end
		local gui = New("BillboardGui", {
			Name = "Construction",
			Adornee = base,
			Size = UDim2.fromOffset(120, 34),
			StudsOffsetWorldSpace = Vector3.new(0, 12, 0),
			AlwaysOnTop = true,
			MaxDistance = 380,
			LightInfluence = 0,
			Parent = building,
		})
		local card = New("Frame", {
			BackgroundColor3 = Theme.Color.Hud,
			BackgroundTransparency = 0.2,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
		}, { Lib.corner(6), Lib.pad(4, 8) })
		local label = Lib.text({ Text = "", TextColor3 = Color3.new(1, 1, 1), TextSize = 12, FontFace = Theme.Font.Bold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 16), Parent = card })
		local bar = Lib.progress({ Position = UDim2.new(0, 0, 1, -6), Size = UDim2.new(1, 0, 0, 5), Parent = card })
		bars[building] = { gui = gui, bar = bar, label = label }
	elseif not finishAt and existing then
		existing.gui:Destroy()
		bars[building] = nil
	end
end

local function hookBuilding(building: Instance)
	if not building:IsA("Model") then
		return
	end
	task.defer(function()
		registerSpinners(building)
		updateBar(building)
		if building:GetAttribute("BuildingId") and tostring(building:GetAttribute("BuildingId")):find("refinery") then
			refineries[building] = true
		end
	end)
	building:GetAttributeChangedSignal("FinishAt"):Connect(function()
		updateBar(building)
	end)
	building.AncestryChanged:Connect(function()
		if not building.Parent then
			for sub in spinners do
				if not sub.Parent or sub:IsDescendantOf(building) then
					spinners[sub] = nil
				end
			end
			if bars[building] then
				bars[building] = nil
			end
			refineries[building] = nil
		end
	end)
end

local function hookPlot(plot: Instance)
	local folder = plot:WaitForChild("Buildings", 10)
	if not folder then
		return
	end
	folder.ChildAdded:Connect(hookBuilding)
	for _, b in folder:GetChildren() do
		hookBuilding(b)
	end
end

---------------------------------------------------------------------------
-- Trucks
---------------------------------------------------------------------------
local function truckModel(key: string): Model
	local m = trucks[key]
	if not m then
		m = ModelBuilder.fuelTruck()
		m.Parent = workspace:FindFirstChild("FX") or workspace
		trucks[key] = m
	end
	return m
end

-- L-shaped route: along X first, then Z.
local function routePoint(a: Vector3, b: Vector3, f: number): (Vector3, Vector3)
	local corner = Vector3.new(b.X, 0, a.Z)
	local l1 = math.abs(b.X - a.X)
	local l2 = math.abs(b.Z - a.Z)
	local total = math.max(0.01, l1 + l2)
	local d = f * total
	if d <= l1 then
		local dir = Vector3.new(b.X >= a.X and 1 or -1, 0, 0)
		return Vector3.new(a.X, 0, a.Z) + dir * d, dir
	end
	local dir = Vector3.new(0, 0, b.Z >= a.Z and 1 or -1)
	return corner + dir * (d - l1), dir
end

local function updateTrucks(now: number)
	local active: { [string]: boolean } = {}
	local camPos = camera.CFrame.Position
	for refinery in refineries do
		local folder = refinery.Parent
		if folder and refinery.PrimaryPart then
			for i = 1, 3 do
				local attr = refinery:GetAttribute("Truck" .. i) :: string?
				if attr and attr ~= "" then
					local uidStr, depart, arrive, ret = attr:match("^(%d+)|([%d%.]+)|([%d%.]+)|([%d%.]+)$")
					local target = uidStr and folder:FindFirstChild(uidStr) :: Model?
					local a = refinery:GetPivot().Position
					if target and depart and arrive and ret and (a - camPos).Magnitude < CULL * 1.5 then
						local b = target:GetPivot().Position
						local t0, t1, t2 = tonumber(depart) :: number, tonumber(arrive) :: number, tonumber(ret) :: number
						local pos, dir
						if now <= t1 then
							pos, dir = routePoint(a, b, math.clamp((now - t0) / math.max(0.1, t1 - t0), 0, 1))
						else
							pos, dir = routePoint(b, a, math.clamp((now - t1) / math.max(0.1, t2 - t1), 0, 1))
						end
						-- reversed route on the way back so the truck retraces the L
						local key = refinery.Name .. "_" .. i
						active[key] = true
						local m = truckModel(key)
						m:PivotTo(CFrame.lookAt(pos + Vector3.new(0, 0.2, 0), pos + Vector3.new(0, 0.2, 0) + dir))
					end
				end
			end
		end
	end
	for key, m in trucks do
		if not active[key] then
			m:Destroy()
			trucks[key] = nil
		end
	end
end

---------------------------------------------------------------------------
-- Frame loop
---------------------------------------------------------------------------
local function step()
	local now = Lib.serverNow()
	local t = os.clock()
	local camPos = camera.CFrame.Position
	for sub, s in spinners do
		if sub.Parent and (s.base.Position - camPos).Magnitude < CULL then
			local angle
			if s.rock then
				angle = math.sin(t * 2.2 + s.phase) * s.rock
				sub:PivotTo(s.base * CFrame.Angles(angle, 0, 0))
			else
				angle = (t + s.phase) * s.speed
				sub:PivotTo(s.base * axisAngles(s.axis, angle))
			end
		end
	end
	for building, b in bars do
		local finishAt = building:GetAttribute("FinishAt") :: number?
		local start = building:GetAttribute("BuildStart") :: number?
		if finishAt and start then
			b.bar.set((now - start) / math.max(0.1, finishAt - start), Theme.Color.Accent)
			b.label.Text = "Building " .. Format.clock(finishAt - now)
		end
	end
	updateTrucks(now)
	Animator.animateRigs(t)
end

function Animator.init()
	task.spawn(function()
		local units = workspace:WaitForChild("Units")
		units.ChildAdded:Connect(function(m)
			task.defer(Animator.registerRig, m)
		end)
		units.ChildRemoved:Connect(function(m)
			rigs[m :: Model] = nil
		end)
		for _, m in units:GetChildren() do
			Animator.registerRig(m)
		end
	end)
	task.spawn(function()
		local homeland = workspace:WaitForChild("Homeland")
		homeland.ChildAdded:Connect(function(c)
			if c.Name:match("^Plot_") then
				hookPlot(c)
			end
		end)
		for _, c in homeland:GetChildren() do
			if c.Name:match("^Plot_") then
				task.spawn(hookPlot, c)
			end
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return Animator
