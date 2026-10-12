--[[
	Minimap
	Radar scope in the bottom-right corner with a rotating sweep.
	  home:  your island (front edge up): buildings coloured by category,
	         vehicles and you
	  war:   the whole map: the central battlefield, every island and
	         bridge, strategic points (coloured by owner) and vehicles
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Grid = require(Shared.Util.Grid)
local Buildings = require(Shared.Catalog.Buildings)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Lib = require(Client.UI.Lib)
local Theme = require(Client.UI.Theme)

local New = Lib.New
local C = Theme.Color

local Minimap = {}

local player = Players.LocalPlayer
local SIZE = 176
local R = SIZE / 2 - 6

local scope: Frame
local dotsHolder: Frame
local sweep: Frame
local label: TextLabel
local pool: { Frame } = {}
local used = 0

local TAB_COLORS = {
	Housing = Color3.fromRGB(236, 222, 190),
	Roads = Color3.fromRGB(110, 116, 112),
	Utilities = Color3.fromRGB(104, 190, 255),
	Industry = Color3.fromRGB(255, 170, 70),
	Services = Color3.fromRGB(150, 230, 140),
	Research = Color3.fromRGB(84, 214, 186),
	Buildings = Color3.fromRGB(210, 220, 120),
	["Air Defense"] = Color3.fromRGB(255, 110, 90),
	Missiles = Color3.fromRGB(255, 90, 70),
	Drones = Color3.fromRGB(255, 140, 110),
}

local function dot(pos: Vector2, size: number, color: Color3, round: boolean?)
	used += 1
	local d = pool[used]
	if not d then
		d = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, Parent = dotsHolder })
		New("UICorner", { Name = "Round", CornerRadius = UDim.new(0, 0), Parent = d })
		pool[used] = d
	end
	d.Visible = true
	d.Position = UDim2.fromOffset(SIZE / 2 + pos.X, SIZE / 2 + pos.Y)
	d.Size = UDim2.fromOffset(size, size)
	d.BackgroundColor3 = color
	d.BackgroundTransparency = 0
	d.Rotation = 0
	;(d:FindFirstChild("Round") :: UICorner).CornerRadius = UDim.new(round and 1 or 0, 0)
	return d
end

-- frame: draw in that frame's local axes (local -Z up the screen).
local function project(world: Vector3, center: Vector3, scale: number, frame: CFrame?): Vector2?
	local v
	if frame then
		local l = frame:PointToObjectSpace(world)
		v = Vector2.new(l.X, l.Z) * scale
	else
		v = Vector2.new(world.X - center.X, world.Z - center.Z) * scale
	end
	if v.Magnitude > R - 2 then
		return nil
	end
	return v
end

local function ownerOfPlot(index: number): Player?
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("PlotIndex") == index then
			return p
		end
	end
	return nil
end

local function redraw()
	used = 0
	local mode = ClientState.mode
	local war = mode == "war"
	local center, scale
	local frame: CFrame? = nil
	if war then
		center = Config.MainlandOrigin
		scale = R / (Config.PlotRingRadius + Grid.PlotSize * 0.72)
		label.Text = "THEATER // ALL FRONTS"
		-- battlefield, bridges and islands
		local land = dot(Vector2.zero, Config.MainlandRadius * 2 * scale, Color3.fromRGB(60, 84, 50), true)
		land.BackgroundTransparency = 0.35
		for i = 1, Config.MaxPlots do
			local owner = ownerOfPlot(i)
			local col = owner == player and C.Accent
				or (owner and ((owner:GetAttribute("Pvp") == true) and C.Bad or C.Muted) or C.Faint)
			local v = project(Grid.plotOrigin(i), center, scale)
			if v then
				local isl = dot(v, Grid.PlotSize * scale, col)
				isl.Rotation = -math.deg(Grid.plotAngle(i))
				isl.BackgroundTransparency = owner and 0.25 or 0.7
			end
			local mid = (Grid.shore(i) + Grid.gate(i)) / 2
			local bv = project(mid, center, scale)
			if bv then
				local bridge = dot(bv, 2, C.TextSoft)
				bridge.Size = UDim2.fromOffset(2, math.max(2, (Grid.gate(i) - Grid.shore(i)).Magnitude * scale))
				bridge.Rotation = -math.deg(Grid.plotAngle(i))
			end
		end
		local points = workspace:FindFirstChild("Mainland") and workspace.Mainland:FindFirstChild("Points")
		if points then
			for _, p in points:GetChildren() do
				local base = p:FindFirstChild("Base") :: BasePart?
				if base then
					local v = project(base.CFrame.Position, center, scale)
					if v then
						local owner = (p:GetAttribute("Owner") :: number?) or 0
						local col = owner == 0 and C.Muted or (owner == player.UserId and C.Good or ((p:GetAttribute("Color") :: Color3?) or C.Bad))
						dot(v, 7, col).Rotation = 45
					end
				end
			end
		end
	else
		local idx = ClientState.get("plot")
		if not idx then
			return
		end
		center = Grid.plotOrigin(idx)
		frame = Grid.plotCFrame(idx)
		scale = R / (Grid.PlotSize / 2 * 1.42 + 20)
		label.Text = "SECTOR // HOME"
		local isl = dot(Vector2.zero, Grid.PlotSize * scale, Color3.fromRGB(46, 70, 42))
		isl.BackgroundTransparency = 0.4
		local homeland = workspace:FindFirstChild("Homeland")
		local plot = homeland and homeland:FindFirstChild("Plot_" .. idx)
		local folder = plot and plot:FindFirstChild("Buildings")
		if folder then
			for _, b in folder:GetChildren() do
				if b:IsA("Model") then
					local def = Buildings.get(b:GetAttribute("BuildingId") :: string)
					local base = b.PrimaryPart
					if def and base then
						local v = project(base.CFrame.Position, center, scale, frame)
						if v then
							local col = TAB_COLORS[def.tab] or C.TextSoft
							if b:GetAttribute("Damaged") then
								col = C.Bad
							elseif b:GetAttribute("FinishAt") then
								col = col:Lerp(C.Panel, 0.5)
							end
							local len = b:GetAttribute("Len") :: number?
							local w = math.max(def.size[1] * Grid.CellSize * scale, 1.5)
							local d = math.max((len or def.size[2] * Grid.CellSize) * scale, 1.5)
							local f = dot(v, w, col)
							f.Size = UDim2.fromOffset(w, d)
							f.Rotation = -((b:GetAttribute("Angle") :: number?) or 0)
						end
					end
				end
			end
		end
	end
	local units = workspace:FindFirstChild("Units")
	if units then
		for _, u in units:GetChildren() do
			local root = u:IsA("Model") and u.PrimaryPart
			if root then
				local v = project(root.CFrame.Position, center, scale, frame)
				if v then
					local mine = u:GetAttribute("OwnerId") == player.UserId
					dot(v, 5, mine and C.Teal or C.Bad, true)
				end
			end
		end
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp and not war then
		local v = project(hrp.CFrame.Position, center, scale, frame)
		if v then
			local d = dot(v, 8, C.Accent)
			local look = frame and frame:VectorToObjectSpace(hrp.CFrame.LookVector) or hrp.CFrame.LookVector
			d.Rotation = math.deg(math.atan2(look.X, -look.Z)) + 45
		end
	end
	for i = used + 1, #pool do
		pool[i].Visible = false
	end
end

function Minimap.init(gui: GuiObject)
	local holder = New("Frame", {
		Name = "Minimap",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(SIZE, SIZE + 22),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	scope = New("Frame", {
		Name = "Scope",
		BackgroundColor3 = Color3.fromRGB(10, 20, 16),
		BackgroundTransparency = 0.08,
		Size = UDim2.fromOffset(SIZE, SIZE),
		Parent = holder,
	}, { Lib.round(), Lib.stroke(C.Teal, 1.5, 0.35) })
	-- range rings + crosshair
	for _, f in { 0.33, 0.66 } do
		New("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(SIZE * f, SIZE * f),
			Parent = scope,
		}, { Lib.round(), Lib.stroke(C.Teal, 1, 0.8) })
	end
	New("Frame", { BackgroundColor3 = C.Teal, BackgroundTransparency = 0.82, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -12, 0, 1), Parent = scope })
	New("Frame", { BackgroundColor3 = C.Teal, BackgroundTransparency = 0.82, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 1, 1, -12), Parent = scope })
	-- sweep: a full-diameter bar, only one half is visible (gradient)
	sweep = New("Frame", {
		Name = "Sweep",
		BackgroundColor3 = C.Teal,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(2, SIZE - 12),
		Parent = scope,
	}, {
		New("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(0.5, 0.6),
				NumberSequenceKeypoint.new(0.501, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	dotsHolder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = scope })
	label = Lib.display({
		Text = "SECTOR // HOME",
		TextSize = 11,
		TextColor3 = C.Teal,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 1, -18),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = holder,
	})
	Lib.brackets(scope, C.Teal, 10, 2, 4)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		sweep.Rotation = (sweep.Rotation + dt * 90) % 360
		acc += dt
		if acc >= 0.5 then
			acc = 0
			local ok, err = pcall(redraw)
			if not ok then
				warn("[Minimap] " .. tostring(err))
			end
		end
	end)
	ClientState.onMode(function(mode)
		holder.Visible = mode ~= "build"
		task.defer(redraw)
	end)
end

return Minimap
